"""Shared pieces of the city tile pipeline: paths, the map projection, geometry
helpers, the triangle mesh builder, and the tile file format.

Coordinates: shapely work happens in (east, north) meters around the origin;
meshes are in Godot world space: meters, +X east, +Y up, +Z south.

Tile file (zstd-compressed, little-endian):
  "NYCT", u32 version, u32 surface_count,
  surface_count x (u32 kind, u32 vertex_count, u32 index_count),
  then per surface: positions f32x3, normals f32x3, uv f32x2, uv2 f32x2 (all per vertex),
  indices u32.
Mesh surfaces are triangle lists. The lanes surface is instead a set of polylines
(points along the sidewalks, LANE_BREAK between polylines); its normals and uvs are zero.
The water surface is inland water above sea level (lakes, reservoirs, creeks);
sea-level water is the game's ocean plane.
"""

import json
import math
import struct
from pathlib import Path

import numpy as np
import shapely
from pyproj import Transformer
from shapely.geometry import box

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw"
CACHE_DIR = ROOT / "data" / "cache"
TILES_DIR = ROOT / "data" / "tiles"

ORIGIN_LAT = 40.7580  # Times Square
ORIGIN_LON = -73.9855
PROJECTION = (
    f"+proj=tmerc +lat_0={ORIGIN_LAT} +lon_0={ORIGIN_LON} +k=1 +x_0=0 +y_0=0 "
    "+ellps=WGS84 +units=m +no_defs"
)
# Land never sits lower than this above sea level (waterfronts, piers).
LAND_MIN = 1.5
SEAWALL_BOTTOM_Y = -6.0
FEET = 0.3048

FORMAT_VERSION = 5
SURFACE_BUILDINGS = 0
SURFACE_GROUND = 1
SURFACE_LANES = 2
SURFACE_STRUCTURES = 3
SURFACE_WATER = 4
LANE_BREAK = 0xFFFFFFFF

# Ground and structure kinds, stored in uv2.x and read by shaders/ground.gdshader.
GROUND_PAVEMENT = 0
GROUND_ROAD = 1
GROUND_PARK = 2
GROUND_SEAWALL = 3
GROUND_SAND = 4
GROUND_MARSH = 5
STRUCTURE_CONCRETE = 6
STRUCTURE_CABLE = 7
STRUCTURE_STONE = 8

# Facade styles, stored in uv2.x and read by shaders/building.gdshader.
STYLE_BRICK = 0
STYLE_PREWAR = 1
STYLE_POSTWAR = 2
STYLE_GLASS = 3

_to_local = Transformer.from_crs("EPSG:4326", PROJECTION, always_xy=True)


def project(geoms):
    """Lon/lat geometries -> (east, north) meters around the origin."""
    return shapely.transform(geoms, lambda c: np.column_stack(_to_local.transform(c[:, 0], c[:, 1])))


def load_features(name: str) -> list[dict]:
    with open(RAW_DIR / f"{name}.geojson", encoding="utf-8") as f:
        return [feat for feat in json.load(f)["features"] if feat.get("geometry")]


def polygons_of(geom, min_area: float = 0.01) -> list:
    """Polygon parts of any geometry, dropping slivers and non-areal parts."""
    if geom is None or geom.is_empty:
        return []
    if geom.geom_type == "Polygon":
        return [geom] if geom.area >= min_area else []
    if geom.geom_type not in ("MultiPolygon", "GeometryCollection"):
        return []
    out = []
    for part in shapely.get_parts(geom):
        out.extend(polygons_of(part, min_area))
    return out


def lines_of(geom) -> list:
    """LineString parts of any geometry."""
    if geom is None or geom.is_empty:
        return []
    if geom.geom_type == "LineString":
        return [geom]
    if geom.geom_type not in ("MultiLineString", "GeometryCollection"):
        return []
    out = []
    for part in shapely.get_parts(geom):
        out.extend(lines_of(part))
    return out


def tile_box(i: int, j: int, size: float):
    """Bounds of tile (i, j) in (east, north) space."""
    return box(i * size, -(j + 1) * size, (i + 1) * size, -j * size)


def tile_range(bounds, size: float):
    """All (i, j) of tiles of `size` overlapping (min_e, min_n, max_e, max_n)."""
    min_e, min_n, max_e, max_n = bounds
    return [
        (i, j)
        for i in range(math.floor(min_e / size), math.floor(max_e / size) + 1)
        for j in range(math.floor(-max_n / size), math.floor(-min_n / size) + 1)
    ]


def to_godot(en: np.ndarray, y) -> np.ndarray:
    """(N, 2) east/north -> (N, 3) Godot x/y/z; y may be a scalar or an (N,) array."""
    return np.column_stack([en[:, 0], np.broadcast_to(y, len(en)), -en[:, 1]])


def facade_style(height_m: float, year: int) -> int:
    if height_m >= 120 or (year >= 1985 and height_m >= 45):
        return STYLE_GLASS
    if height_m < 22:
        return STYLE_BRICK
    if 0 < year < 1946:
        return STYLE_PREWAR
    return STYLE_POSTWAR


class MeshBuilder:
    """Collects flat-shaded triangles, then fixes winding and merges shared vertices."""

    def __init__(self):
        self.pos, self.uv, self.uv2, self.front, self.normals = [], [], [], [], []

    def add(self, pos, uv, uv2, front, normals=None):
        """pos (T,3,3), uv (T,3,2), uv2 (2,) or (T,3,2), front (T,3) or (3,): unit
        outward normal. Shading uses `front` unless per-vertex `normals` (T,3,3)
        are given (for smooth surfaces)."""
        count = len(pos)
        if count == 0:
            return
        front = np.broadcast_to(np.asarray(front, np.float64), (count, 3))
        self.pos.append(np.asarray(pos, np.float64))
        self.uv.append(np.asarray(uv, np.float64))
        self.uv2.append(np.broadcast_to(np.asarray(uv2, np.float64), (count, 3, 2)))
        self.front.append(front)
        self.normals.append(np.repeat(front[:, None, :], 3, axis=1) if normals is None
                            else np.asarray(normals, np.float64).reshape(count, 3, 3))

    def add_flat(self, polygons, y, uv2):
        """Upward-facing triangulated polygons at height y."""
        for poly in polygons:
            en = triangles_of(poly)
            if en is None:
                continue
            pos = np.stack([en[..., 0], np.full(en.shape[:2], y), -en[..., 1]], axis=-1)
            uv = np.stack([en[..., 0], -en[..., 1]], axis=-1)
            self.add(pos, uv, uv2, (0.0, 1.0, 0.0))

    def add_draped(self, polygons, cell, height, uv2, normal=None):
        """Upward-facing polygons laid over the ground: cut along a `cell`-meter
        grid so they bend with it, at height(en) for (N, 2) east/north points.
        normal(en) gives smooth per-vertex normals (Godot space); without it
        they face straight up."""
        tris = [t for t in (triangles_of(poly) for poly in polygons) if t is not None]
        if not tris:
            return
        tris = split_triangles(np.concatenate(tris), cell)
        en = tris.reshape(-1, 2)
        y = np.asarray(height(en), np.float64)
        pos = np.column_stack([en[:, 0], y, -en[:, 1]]).reshape(-1, 3, 3)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        normals = None if normal is None else normal(en).reshape(-1, 3, 3)
        self.add(pos, uv, uv2, (0.0, 1.0, 0.0), normals)

    def add_walls(self, ring_coords, bottom_y, top_y, uv2, ground_y=0.0):
        """Vertical walls along a line; the outward side is right of travel.

        bottom_y/top_y are scalars or per-point arrays. uv = (meters along the
        line, meters above ground_y).
        """
        pts = np.asarray(ring_coords)[:, :2]
        bottom = np.broadcast_to(np.asarray(bottom_y, np.float64), len(pts))
        top = np.broadcast_to(np.asarray(top_y, np.float64), len(pts))
        seg = pts[1:] - pts[:-1]
        length = np.hypot(seg[:, 0], seg[:, 1])
        keep = length > 0.01
        if not keep.any():
            return
        u_end = np.cumsum(length)
        u0, u1 = (u_end - length)[keep], u_end[keep]
        a, b, seg, length = pts[:-1][keep], pts[1:][keep], seg[keep], length[keep]
        ab_y, bb_y = bottom[:-1][keep], bottom[1:][keep]
        at_y, bt_y = top[:-1][keep], top[1:][keep]

        ab, bb, at, bt = to_godot(a, ab_y), to_godot(b, bb_y), to_godot(a, at_y), to_godot(b, bt_y)
        pos = np.stack([np.stack([ab, bb, bt], 1), np.stack([ab, bt, at], 1)], 1).reshape(-1, 3, 3)
        uv_ab = np.column_stack([u0, ab_y - ground_y])
        uv_bb = np.column_stack([u1, bb_y - ground_y])
        uv_at = np.column_stack([u0, at_y - ground_y])
        uv_bt = np.column_stack([u1, bt_y - ground_y])
        uv = np.stack([np.stack([uv_ab, uv_bb, uv_bt], 1), np.stack([uv_ab, uv_bt, uv_at], 1)], 1).reshape(-1, 3, 2)
        # Right of travel in east/north is (dy, -dx); in Godot that's x = dy, z = dx.
        out = np.column_stack([seg[:, 1], np.zeros(len(seg)), seg[:, 0]]) / length[:, None]
        self.add(pos, uv, uv2, np.repeat(out, 2, axis=0))

    def is_empty(self) -> bool:
        return not self.pos

    def build(self, origin):
        if not self.pos:
            return None
        pos = np.concatenate(self.pos) - np.asarray(origin)
        uv = np.concatenate(self.uv)
        uv2 = np.concatenate(self.uv2)
        front = np.concatenate(self.front)
        normals = np.concatenate(self.normals)

        normal = np.cross(pos[:, 1] - pos[:, 0], pos[:, 2] - pos[:, 0])
        area = np.linalg.norm(normal, axis=1)
        keep = area > 1e-6
        pos, uv, uv2, front, normals, normal = pos[keep], uv[keep], uv2[keep], front[keep], normals[keep], normal[keep]
        # Godot treats clockwise triangles as front-facing, so a triangle whose
        # counter-clockwise normal points outward gets its winding reversed.
        flip = (normal * front).sum(axis=1) > 0
        for arr in (pos, uv, uv2, normals):
            arr[flip] = arr[flip][:, [0, 2, 1]]

        # Rounded (1 mm positions, 0.001 normals) so the files compress well.
        verts = np.concatenate(
            [np.round(pos.reshape(-1, 3), 3), np.round(normals.reshape(-1, 3), 3),
             np.round(uv.reshape(-1, 2), 3), uv2.reshape(-1, 2)], axis=1
        ).astype(np.float32)
        unique, inverse = np.unique(verts, axis=0, return_inverse=True)
        return unique[:, 0:3], unique[:, 3:6], unique[:, 6:8], unique[:, 8:10], inverse.reshape(-1).astype(np.uint32)


def triangles_of(poly):
    """Constrained Delaunay triangles of a polygon as an (T, 3, 2) array, or None."""
    try:
        tris = shapely.constrained_delaunay_triangles(poly)
    except shapely.errors.GEOSException:
        return None
    coords = shapely.get_coordinates(tris)
    if len(coords) == 0:
        return None
    return coords.reshape(-1, 4, 2)[:, :3]


def split_triangles(tris: np.ndarray, cell: float) -> np.ndarray:
    """Cuts (T, 3, 2) triangles along a `cell`-meter grid wherever they cross
    it, so no piece spans more than one grid cell. Neighbors are cut at the
    same points, so a surface bent along the grid has no cracks."""
    lows = np.floor(tris.min(axis=1) / cell).astype(np.int64)
    highs = np.floor((tris.max(axis=1) - 1e-6) / cell).astype(np.int64)
    single = (lows == highs).all(axis=1)
    if single.all():
        return tris
    many = np.flatnonzero(~single)
    span = highs[many] - lows[many] + 1
    counts = span[:, 0] * span[:, 1]
    owner = np.repeat(np.arange(len(many)), counts)
    k = np.arange(counts.sum()) - np.repeat(np.cumsum(counts) - counts, counts)
    cx = lows[many][owner, 0] + k % span[owner, 0]
    cy = lows[many][owner, 1] + k // span[owner, 0]
    rings = tris[many][owner]
    triangles = shapely.polygons(np.concatenate([rings, rings[:, :1]], axis=1))
    cells = shapely.box(cx * cell, cy * cell, (cx + 1) * cell, (cy + 1) * cell)
    pieces = shapely.intersection(triangles, cells)
    pieces = pieces[(shapely.get_type_id(pieces) == 3) & (shapely.area(pieces) > 1e-6)]
    cut = shapely.get_coordinates(shapely.constrained_delaunay_triangles(pieces)).reshape(-1, 4, 2)[:, :3]
    return np.concatenate([tris[single], cut])


def encode_tile(surfaces: list[tuple[int, tuple]]) -> bytes:
    header = [b"NYCT", struct.pack("<II", FORMAT_VERSION, len(surfaces))]
    body = []
    for kind, (pos, normals, uv, uv2, idx) in surfaces:
        header.append(struct.pack("<III", kind, len(pos), len(idx)))
        body += [
            pos.astype("<f4").tobytes(),
            normals.astype("<f4").tobytes(),
            uv.astype("<f4").tobytes(),
            uv2.astype("<f4").tobytes(),
            idx.astype("<u4").tobytes(),
        ]
    return b"".join(header + body)
