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
The markings surface (lod0) is paint on the streets: a triangle mesh
MARKING_LIFT above the road, with no collision. Its uv2.x is a GROUND_MARKING_*
kind, uv is local to each strip of paint in meters (x along the street, y
across it; see the kinds for what the shader paints), normals face up and
positions are rounded to 1 cm.
The props surface (lod0) is one point per prop, no indices:
  position = where it stands (a tree's trunk on the ground, a water tower's
             legs on the roof)
  normal   = (height m, width m, yaw radians): total height to the top; the
             crown's or tank's diameter; rotation about +Y
  uv       = (variant, trunk): trees' foliage tone (PROP_TONE_*) and trunk
             diameter (m); water towers' tank (0 wood, 1 steel) and 0;
             street lights' style (see PROP_STREET_LIGHT) and 0
  uv2      = (PROP_* type, seed 0..1)
Props are sorted by type. The manifest's "canopy" entry is a citywide map of
tree canopy (landcover.write_canopy_map) for the ground shader.
"""

import json
import math
import os
import struct
from pathlib import Path

import numpy as np
import shapely
from pyproj import Transformer
from shapely.geometry import box

ROOT = Path(__file__).resolve().parents[2]
# The data lives in data/ (gitignored); NYC_DATA_DIR points a git worktree at
# the main checkout's.
DATA_DIR = Path(os.environ["NYC_DATA_DIR"]) if os.environ.get("NYC_DATA_DIR") else ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
CACHE_DIR = DATA_DIR / "cache"
TILES_DIR = DATA_DIR / "tiles"

ORIGIN_LAT = 40.7580  # Times Square
ORIGIN_LON = -73.9855
PROJECTION = (
    f"+proj=tmerc +lat_0={ORIGIN_LAT} +lon_0={ORIGIN_LON} +k=1 +x_0=0 +y_0=0 "
    "+ellps=WGS84 +units=m +no_defs"
)
# Land never sits lower than this above sea level: waterfronts and piers (the
# pier data's median deck height is 2.1 m).
LAND_MIN = 2.0
# Streets sit this far below the sidewalks, behind a curb.
CURB_HEIGHT = 0.15
SEAWALL_BOTTOM_Y = -6.0
FEET = 0.3048

FORMAT_VERSION = 7
SURFACE_BUILDINGS = 0
SURFACE_GROUND = 1
SURFACE_LANES = 2
SURFACE_STRUCTURES = 3
SURFACE_WATER = 4
SURFACE_PROPS = 5
SURFACE_MARKINGS = 6
# Driving lanes, near tiles only (traffic.py): polylines like the sidewalk
# lanes, separated by LANE_BREAK, on the road surface; every point of a lane
# carries normal = (from node, to node, speed m/s), uv = (lane number from the
# center line, lanes its way), uv2 = (signal phase at its end or -1, how it
# ends: 0 the street goes on, 1 at an intersection, 2 at one where its street
# is the widest, so it has the right of way where there's no signal).
SURFACE_TRAFFIC = 7
LANE_BREAK = 0xFFFFFFFF
# Hand-made landmarks' faces in the materials shaders/landmark.gdshader paints
# (landmarks.py, 41 and up), laid out like the buildings surface; the rest of
# a landmark is in the buildings surface. With collision up close.
SURFACE_LANDMARKS = 8

# Props (uv2.x of the props surface).
PROP_TREE = 0         # broadleaf tree, round crown
PROP_TREE_NARROW = 1  # columnar or oval crown (Callery pear, ginkgo, columnar oaks)
PROP_CONIFER = 2      # pine, spruce, fir, cedar
PROP_WATER_TOWER = 3  # rooftop water tank on legs
PROP_STREET_LIGHT = 4  # lamp post at the curb: its normal is (pole height, arm
                       # length, yaw); the arm reaches along (sin yaw, 0, cos yaw),
                       # over the street; uv.x 0 cobra-head, 1 historic post-top
# Street furniture: normal = (height, width, yaw); the front faces along
# (sin yaw, 0, cos yaw), toward the street. uv.x is the variant.
PROP_HYDRANT = 5
PROP_BUS_SHELTER = 6       # width = length along the curb
PROP_LINKNYC = 7           # uv.x 0 kiosk (Link1.0), 1 tall Link5G pole
PROP_BENCH = 8             # benches and leaning bars (CityBench seating)
PROP_SUBWAY_ENTRANCE = 9   # stairs down, railing and globe lamps; uv.x 0 entrance
                           # (green globes), 1 exit only (red), 2 elevator
PROP_TRAFFIC_SIGNAL = 10   # pole at an intersection; faces the traffic it controls;
                           # uv.y its phase (markings.prepare)
PROP_LITTER_BASKET = 11    # uv.x 0 wire basket, 1 other (solar compactor)
PROP_BIKE_RACK = 12        # uv.x 0 hoop, 1 other
PROP_PARKING_METER = 13    # pay station (Muni-Meter)
PROP_NEWSSTAND = 14
# Parked cars at the curbs (traffic.py): normal = (height, length, yaw), the
# front facing along (sin yaw, 0, cos yaw); uv = (model CAR_*, paint 0..11).
PROP_PARKED_CAR = 15
CAR_SEDAN, CAR_HATCHBACK, CAR_SUV, CAR_MINIVAN, CAR_PICKUP, CAR_VAN, CAR_TAXI, CAR_BOX_TRUCK = range(8)
# Trees' foliage tones (uv.x of the props surface).
PROP_TONE_GREEN = 0
PROP_TONE_LIGHT = 1   # yellow-green: honeylocust, ginkgo, birch, willow
PROP_TONE_DARK = 2    # oaks, lindens, conifers
PROP_TONE_RED = 3     # purple-leaf plum, copper beech, red-leaved maples

# Ground and structure kinds, stored in uv2.x and read by shaders/ground.gdshader.
GROUND_PAVEMENT = 0
GROUND_ROAD = 1
GROUND_PARK = 2
GROUND_SEAWALL = 3
GROUND_SAND = 4
GROUND_MARSH = 5
STRUCTURE_CONCRETE = 6
STRUCTURE_CABLE = 7    # main cables (uv.y 0..1 across each face: necklace lights) and ropes
STRUCTURE_STONE = 8
GROUND_YARD = 9  # back yards, gardens and lawns around homes
# Hand-made bridges' structures (bridge_landmarks.py). Their uv2.y (and that
# of concrete, cables and stone there) is a palette and flags, see
# bridge_landmarks.PALETTES; 0 elsewhere.
STRUCTURE_STEEL = 14    # painted steel: towers, trusses, arches
STRUCTURE_WALKWAY = 15  # walkways: uv = (meters along, meters across)
STRUCTURE_RAIL = 16     # track beds: uv = (meters along, meters from the track's middle)
# Ground details (ground_details.py). Paving kinds carry the direction their
# courses follow in uv2.y (radians in uv space, from +x toward +y).
GROUND_SHRUBS = 20   # shrub beds and hedges on planted medians (a low mound)
GROUND_PAVERS = 21   # concrete pavers in pedestrian plazas; uv2.y their rows' direction
GROUND_COBBLES = 22  # Belgian block streets; uv2.y the street's direction
# Markings surface kinds (10-13, another surface); uv = (meters along, meters across).
GROUND_MARKING_WHITE = 10      # solid white: stop lines, highway edge lines
GROUND_MARKING_YELLOW = 11     # double yellow center line: a 0.45 m strip, uv.y -0.225..0.225,
                               # painted where |uv.y| >= 0.075
GROUND_MARKING_DASHED = 12     # white lane line: painted where fract(uv.x / 12) < 0.25
GROUND_MARKING_CROSSWALK = 13  # curb to curb, uv.y from one curb: bars where fract(uv.y / 1.2) < 0.5
# Paint sits this far above the road (the shader also nudges it toward the camera).
MARKING_LIFT = 0.03

# Facade styles, stored in uv2.x and read by shaders/building.gdshader. Roof
# surfaces add ROOF to their building's style.
STYLE_BRICK = 0
STYLE_PREWAR = 1
STYLE_POSTWAR = 2
STYLE_GLASS = 3
ROOF = 4

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
        if tris:
            self.add_draped_triangles(np.concatenate(tris), cell, height, uv2, normal)

    def add_draped_triangles(self, tris, cell, height, uv2, normal=None, uv=None):
        """Like add_draped, for (T, 3, 2) east/north triangles. uv (T, 3, 2)
        replaces the default (world x/z) and is blended across the cuts."""
        if len(tris) == 0:
            return
        tris = np.asarray(tris, np.float64)
        if uv is None:
            tris = split_triangles(tris, cell)
            uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        else:
            pieces, owner = split_triangles(tris, cell, owners=True)
            uv = _blend(tris[owner], np.asarray(uv, np.float64)[owner], pieces)
            tris = pieces
        en = tris.reshape(-1, 2)
        y = np.asarray(height(en), np.float64)
        pos = np.column_stack([en[:, 0], y, -en[:, 1]]).reshape(-1, 3, 3)
        normals = None if normal is None else normal(en).reshape(-1, 3, 3)
        self.add(pos, uv, uv2, (0.0, 1.0, 0.0), normals)

    def add_walls(self, ring_coords, bottom_y, top_y, uv2, ground_y=0.0, restart=None):
        """Vertical walls along a line; the outward side is right of travel.

        bottom_y/top_y are scalars or per-point arrays; uv2 is one pair, or one
        per segment ((N - 1, 2)). uv = (meters along the line, meters above
        ground_y); segments where `restart` (N - 1 bools) is set measure from
        their own start instead.
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
        u_start = u_end - length
        if restart is not None:
            u_start = np.where(restart, 0.0, u_start)
            u_end = np.where(restart, length, u_end)
        u0, u1 = u_start[keep], u_end[keep]
        uv2 = np.asarray(uv2, np.float64)
        if uv2.ndim == 2:
            uv2 = np.repeat(uv2[keep], 2, axis=0)[:, None, :]  # two triangles per segment
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

    def build(self, origin, decimals: int = 3):
        """The mesh arrays relative to origin, with positions and uvs rounded
        to `decimals` (normals to 0.001) so the files compress well."""
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

        verts = np.concatenate(
            [np.round(pos.reshape(-1, 3), decimals), np.round(normals.reshape(-1, 3), 3),
             np.round(uv.reshape(-1, 2), decimals), uv2.reshape(-1, 2)], axis=1
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


def triangulate_planar(rings: list) -> np.ndarray | None:
    """Triangles (T, 3, 3) of a flat polygon in 3-D: rings[0] is the outline,
    any others are holes; each ring is (N, 3) points without a closing point."""
    outline = rings[0]
    if len(rings) == 1 and len(outline) == 3:
        return outline[None]
    normal = polygon_normal(outline)
    if not normal.any():
        return None
    if len(rings) == 1 and len(outline) == 4:
        return outline[[[0, 1, 2], [0, 2, 3]]]
    # Flatten onto the two axes the polygon faces least, triangulate, then
    # put the dropped axis back from the polygon's plane.
    drop = int(np.argmax(np.abs(normal)))
    keep = [axis for axis in range(3) if axis != drop]
    try:
        flat = shapely.Polygon(outline[:, keep], [ring[:, keep] for ring in rings[1:]])
        tris = shapely.get_coordinates(shapely.constrained_delaunay_triangles(flat)).reshape(-1, 4, 2)[:, :3]
    except (shapely.errors.GEOSException, ValueError):
        return None
    if len(tris) == 0:
        return None
    plane = normal @ outline[0]
    out = np.empty(tris.shape[:2] + (3,))
    out[..., keep[0]] = tris[..., 0]
    out[..., keep[1]] = tris[..., 1]
    out[..., drop] = (plane - normal[keep[0]] * tris[..., 0] - normal[keep[1]] * tris[..., 1]) / normal[drop]
    return out


def polygon_normal(ring: np.ndarray) -> np.ndarray:
    """Unit normal of a 3-D ring by Newell's method (zero if degenerate);
    it faces the side the ring runs counter-clockwise around."""
    nxt = np.roll(ring, -1, axis=0)
    normal = np.array([
        ((ring[:, 1] - nxt[:, 1]) * (ring[:, 2] + nxt[:, 2])).sum(),
        ((ring[:, 2] - nxt[:, 2]) * (ring[:, 0] + nxt[:, 0])).sum(),
        ((ring[:, 0] - nxt[:, 0]) * (ring[:, 1] + nxt[:, 1])).sum(),
    ])
    length = np.linalg.norm(normal)
    return normal / length if length > 1e-9 else np.zeros(3)


def split_triangles(tris: np.ndarray, cell: float, owners: bool = False):
    """Cuts (T, 3, 2) triangles along a `cell`-meter grid wherever they cross
    it, so no piece spans more than one grid cell. Neighbors are cut at the
    same points, so a surface bent along the grid has no cracks. With
    `owners`, also returns which input triangle each piece came from."""
    lows = np.floor(tris.min(axis=1) / cell).astype(np.int64)
    highs = np.floor((tris.max(axis=1) - 1e-6) / cell).astype(np.int64)
    single = (lows == highs).all(axis=1)
    if single.all():
        return (tris, np.arange(len(tris))) if owners else tris
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
    kept = (shapely.get_type_id(pieces) == 3) & (shapely.area(pieces) > 1e-6)
    parts, which = shapely.get_parts(shapely.constrained_delaunay_triangles(pieces[kept]), return_index=True)
    cut = shapely.get_coordinates(parts).reshape(-1, 4, 2)[:, :3]
    out = np.concatenate([tris[single], cut])
    if not owners:
        return out
    return out, np.concatenate([np.flatnonzero(single), many[owner[kept]][which]])


def _blend(corners: np.ndarray, values: np.ndarray, points: np.ndarray) -> np.ndarray:
    """Values (T, 3, D) at triangles' corners (T, 3, 2), blended at points
    (T, K, 2) inside them (barycentric)."""
    a = corners[:, 0][:, None]
    v0, v1 = (corners[:, 1] - corners[:, 0])[:, None], (corners[:, 2] - corners[:, 0])[:, None]
    v2 = points - a
    d00, d01, d11 = (v0 * v0).sum(-1), (v0 * v1).sum(-1), (v1 * v1).sum(-1)
    d20, d21 = (v2 * v0).sum(-1), (v2 * v1).sum(-1)
    denom = np.where(np.abs(d00 * d11 - d01 * d01) > 1e-12, d00 * d11 - d01 * d01, 1e-12)
    w1 = (d11 * d20 - d01 * d21) / denom
    w2 = (d00 * d21 - d01 * d20) / denom
    w0 = 1.0 - w1 - w2
    return (w0[..., None] * values[:, 0][:, None] + w1[..., None] * values[:, 1][:, None]
            + w2[..., None] * values[:, 2][:, None])


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
