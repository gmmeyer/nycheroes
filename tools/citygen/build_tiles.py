"""Build the game's streaming city tiles from the raw NYC data.

Reads data/raw/*.geojson (written by fetch_data.py) and writes data/tiles/manhattan/:
  manifest.json        tile index and settings, read by scripts/world/city_streamer.gd
  lod0/<i>_<j>.nyct    full detail: buildings, streets, sidewalks, parks
  lod1/<i>_<j>.nyct    simplified buildings and ground, for distant tiles

Coordinates are Godot world space: meters, +X east, +Y up, +Z south, with the
origin at Times Square. Tile (i, j) covers x in [i*T, (i+1)*T) and z in
[j*T, (j+1)*T); its vertices are stored relative to that corner.

Tile file (zstd-compressed, little-endian):
  "NYCT", u32 version, u32 surface_count,
  surface_count x (u32 kind, u32 vertex_count, u32 index_count),
  then per surface: positions f32x3, normals f32x3, uv f32x2, uv2 f32x2 (all per vertex),
  indices u32.

Usage: python build_tiles.py
"""

import json
import math
import shutil
import struct
import time
from collections import defaultdict
from compression import zstd
from pathlib import Path

import numpy as np
import shapely
from pyproj import Transformer
from shapely.geometry import Polygon, box, shape

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw"
OUT_DIR = ROOT / "data" / "tiles" / "manhattan"

ORIGIN_LAT = 40.7580  # Times Square
ORIGIN_LON = -73.9855
PROJECTION = (
    f"+proj=tmerc +lat_0={ORIGIN_LAT} +lon_0={ORIGIN_LON} +k=1 +x_0=0 +y_0=0 "
    "+ellps=WGS84 +units=m +no_defs"
)
TILE_SIZE = 500.0
LAND_Y = 2.0  # ground height above sea level; the map is flat for now
SEAWALL_BOTTOM_Y = -6.0
FEET = 0.3048
DEFAULT_HEIGHT = 9.0
MIN_HEIGHT = 2.5

FORMAT_VERSION = 2
SURFACE_BUILDINGS = 0
SURFACE_GROUND = 1

# Ground kinds, stored in uv2.x and read by shaders/ground.gdshader.
GROUND_PAVEMENT = 0
GROUND_ROAD = 1
GROUND_PARK = 2
GROUND_SEAWALL = 3

# Facade styles, stored in uv2.x and read by shaders/building.gdshader.
STYLE_BRICK = 0
STYLE_PREWAR = 1
STYLE_POSTWAR = 2
STYLE_GLASS = 3

# Skybridges float above the street and placeholders have no height.
SKIPPED_FEATURE_CODES = {"2110", "1003"}
# Park categories that are paved or are buildings, so they aren't drawn as grass.
NON_GREEN_PARK_TYPES = {"Buildings/Institutions", "Triangle/Plaza", "Managed Sites"}

LODS = {
    "lod0": {"building_tolerance": 0.3, "ground_tolerance": 0.2, "keep_holes": True, "min_area": 4.0},
    "lod1": {"building_tolerance": 2.5, "ground_tolerance": 1.5, "keep_holes": False, "min_area": 40.0},
}

_to_local = Transformer.from_crs("EPSG:4326", PROJECTION, always_xy=True)


def project(geoms):
    """Lon/lat geometries -> (east, north) meters around the origin."""
    return shapely.transform(geoms, lambda c: np.column_stack(_to_local.transform(c[:, 0], c[:, 1])))


def load_features(name: str) -> list[dict]:
    with open(RAW_DIR / f"{name}.geojson", encoding="utf-8") as f:
        return [feat for feat in json.load(f)["features"] if feat.get("geometry")]


def polygons_of(geom, min_area: float = 0.01) -> list[Polygon]:
    """Polygon parts of any geometry, dropping slivers and non-areal parts."""
    if geom is None or geom.is_empty:
        return []
    parts = shapely.get_parts(geom)
    out = []
    for part in parts:
        if part.geom_type == "Polygon" and part.area >= min_area:
            out.append(part)
        elif part.geom_type in ("MultiPolygon", "GeometryCollection"):
            out.extend(polygons_of(part, min_area))
    return out


def tile_of(east: float, north: float) -> tuple[int, int]:
    return math.floor(east / TILE_SIZE), math.floor(-north / TILE_SIZE)


def tile_box(i: int, j: int):
    """Tile bounds in (east, north) space."""
    return box(i * TILE_SIZE, -(j + 1) * TILE_SIZE, (i + 1) * TILE_SIZE, -j * TILE_SIZE)


def to_godot(en: np.ndarray, y) -> np.ndarray:
    """(N, 2) east/north -> (N, 3) Godot x/y/z."""
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
        self.pos, self.uv, self.uv2, self.front = [], [], [], []

    def add(self, pos, uv, uv2, front):
        """pos (T,3,3), uv (T,3,2), uv2 (2,), front (T,3) or (3,): unit outward normal."""
        count = len(pos)
        if count == 0:
            return
        self.pos.append(pos)
        self.uv.append(uv)
        self.uv2.append(np.broadcast_to(np.asarray(uv2, np.float64), (count, 3, 2)))
        self.front.append(np.broadcast_to(np.asarray(front, np.float64), (count, 3)))

    def add_flat(self, polygons, y, uv2):
        """Upward-facing triangulated polygons at height y."""
        for poly in polygons:
            try:
                tris = shapely.constrained_delaunay_triangles(poly)
            except shapely.errors.GEOSException:
                continue
            coords = shapely.get_coordinates(tris)
            if len(coords) == 0:
                continue
            en = coords.reshape(-1, 4, 2)[:, :3]
            pos = np.stack([en[..., 0], np.full(en.shape[:2], y), -en[..., 1]], axis=-1)
            uv = np.stack([en[..., 0], -en[..., 1]], axis=-1)
            self.add(pos, uv, uv2, (0.0, 1.0, 0.0))

    def add_walls(self, ring_coords, bottom_y, top_y, uv2, ground_y=LAND_Y):
        """Vertical walls along a line; the outward side is right of travel.

        uv = (meters along the line, meters above ground).
        """
        pts = np.asarray(ring_coords)[:, :2]
        seg = pts[1:] - pts[:-1]
        length = np.hypot(seg[:, 0], seg[:, 1])
        keep = length > 0.01
        if not keep.any():
            return
        u_end = np.cumsum(length)
        u0, u1 = (u_end - length)[keep], u_end[keep]
        a, b, seg, length = pts[:-1][keep], pts[1:][keep], seg[keep], length[keep]

        ab, bb, at, bt = to_godot(a, bottom_y), to_godot(b, bottom_y), to_godot(a, top_y), to_godot(b, top_y)
        pos = np.stack([np.stack([ab, bb, bt], 1), np.stack([ab, bt, at], 1)], 1).reshape(-1, 3, 3)
        vb, vt = bottom_y - ground_y, top_y - ground_y
        uv_ab = np.column_stack([u0, np.full(len(u0), vb)])
        uv_bb = np.column_stack([u1, np.full(len(u1), vb)])
        uv_at = np.column_stack([u0, np.full(len(u0), vt)])
        uv_bt = np.column_stack([u1, np.full(len(u1), vt)])
        uv = np.stack([np.stack([uv_ab, uv_bb, uv_bt], 1), np.stack([uv_ab, uv_bt, uv_at], 1)], 1).reshape(-1, 3, 2)
        # Right of travel in east/north is (dy, -dx); in Godot that's x = dy, z = dx.
        out = np.column_stack([seg[:, 1], np.zeros(len(seg)), seg[:, 0]]) / length[:, None]
        self.add(pos, uv, uv2, np.repeat(out, 2, axis=0))

    def build(self, origin):
        if not self.pos:
            return None
        pos = np.concatenate(self.pos) - np.asarray(origin)
        uv = np.concatenate(self.uv)
        uv2 = np.concatenate(self.uv2)
        front = np.concatenate(self.front)

        normal = np.cross(pos[:, 1] - pos[:, 0], pos[:, 2] - pos[:, 0])
        area = np.linalg.norm(normal, axis=1)
        keep = area > 1e-6
        pos, uv, uv2, front, normal = pos[keep], uv[keep], uv2[keep], front[keep], normal[keep]
        # Godot treats clockwise triangles as front-facing, so a triangle whose
        # counter-clockwise normal points outward gets its winding reversed.
        flip = (normal * front).sum(axis=1) > 0
        for arr in (pos, uv, uv2):
            arr[flip] = arr[flip][:, [0, 2, 1]]

        normals = np.repeat(front[:, None, :], 3, axis=1)
        verts = np.concatenate(
            [pos.reshape(-1, 3), normals.reshape(-1, 3), uv.reshape(-1, 2), uv2.reshape(-1, 2)], axis=1
        ).astype(np.float32)
        unique, inverse = np.unique(verts, axis=0, return_inverse=True)
        return unique[:, 0:3], unique[:, 3:6], unique[:, 6:8], unique[:, 8:10], inverse.reshape(-1).astype(np.uint32)


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


def load_buildings():
    feats = [f for f in load_features("manhattan_buildings")
             if f["properties"].get("feature_code") not in SKIPPED_FEATURE_CODES]
    geoms = project(np.array([shape(f["geometry"]) for f in feats]))
    geoms = shapely.make_valid(geoms)
    buildings = []
    for feat, geom in zip(feats, geoms):
        props = feat["properties"]
        height = float(props.get("height_roof") or 0) * FEET
        if height <= 0:
            height = DEFAULT_HEIGHT
        height = max(height, MIN_HEIGHT)
        year = int(props.get("construction_year") or 0)
        bin_number = int(props.get("bin") or 0)
        seed = ((bin_number * 2654435761) % 4294967296) / 4294967296.0
        point = geom.representative_point()
        buildings.append({
            "geom": geom,
            "height": height,
            "style": facade_style(height, year),
            "seed": seed,
            "tile": tile_of(point.x, point.y),
        })
    return buildings


def load_ground():
    boroughs = load_features("boroughs")
    manhattan = next(f for f in boroughs if str(f["properties"].get("borocode")) == "1")
    land = shapely.make_valid(project(shape(manhattan["geometry"])))
    land = shapely.union_all(polygons_of(land, min_area=1.0))

    roads = project(np.array([shape(f["geometry"]) for f in load_features("manhattan_roadbed")]))
    roads = shapely.make_valid(roads)

    parks = [f for f in load_features("manhattan_parks")
             if f["properties"].get("typecategory") not in NON_GREEN_PARK_TYPES]
    parks = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in parks])))
    return land, roads, parks


def build_ground(builder, tile_bounds, land, coast, roads, road_tree, parks, park_tree, tolerance):
    land_t = shapely.intersection(land, tile_bounds)
    if land_t.is_empty:
        return

    nearby_roads = roads[road_tree.query(tile_bounds)]
    roads_t = shapely.intersection(shapely.union_all(nearby_roads), land_t) if len(nearby_roads) else Polygon()
    nearby_parks = parks[park_tree.query(tile_bounds)]
    parks_t = shapely.intersection(shapely.union_all(nearby_parks), land_t) if len(nearby_parks) else Polygon()
    parks_t = shapely.difference(parks_t, roads_t)
    pavement_t = shapely.difference(shapely.difference(land_t, roads_t), parks_t)

    for kind, geom in ((GROUND_PAVEMENT, pavement_t), (GROUND_ROAD, roads_t), (GROUND_PARK, parks_t)):
        geom = shapely.simplify(geom, tolerance, preserve_topology=True)
        builder.add_flat(polygons_of(geom, min_area=0.5), LAND_Y, (kind, 0.0))

    coast_t = shapely.intersection(coast, tile_bounds)
    for line in shapely.get_parts(shapely.line_merge(coast_t) if coast_t.geom_type == "MultiLineString" else coast_t):
        if line.geom_type == "LineString" and not line.is_empty:
            builder.add_walls(line.coords, SEAWALL_BOTTOM_Y, LAND_Y, (GROUND_SEAWALL, 0.0))


def add_building(builder, building, settings):
    geom = shapely.simplify(building["geom"], settings["building_tolerance"], preserve_topology=True)
    for poly in polygons_of(geom, settings["min_area"]):
        if not settings["keep_holes"]:
            poly = Polygon(poly.exterior)
        poly = shapely.orient_polygons(poly)
        top = LAND_Y + building["height"]
        uv2 = (building["style"], building["seed"])
        for ring in (poly.exterior, *poly.interiors):
            builder.add_walls(ring.coords, LAND_Y - 1.0, top, uv2)
        builder.add_flat([poly], top, uv2)


def main() -> None:
    started = time.time()
    print("loading buildings...")
    buildings = load_buildings()
    print(f"  {len(buildings)} buildings")
    print("loading ground...")
    land, roads, parks = load_ground()
    coast = land.boundary
    road_tree, park_tree = shapely.STRtree(roads), shapely.STRtree(parks)

    by_tile = defaultdict(list)
    for building in buildings:
        by_tile[building["tile"]].append(building)

    min_e, min_n, max_e, max_n = land.bounds
    land_tiles = {
        (i, j)
        for i in range(math.floor(min_e / TILE_SIZE), math.floor(max_e / TILE_SIZE) + 1)
        for j in range(math.floor(-max_n / TILE_SIZE), math.floor(-min_n / TILE_SIZE) + 1)
        if shapely.intersects(land, tile_box(i, j))
    }
    tiles = sorted(land_tiles | set(by_tile))
    print(f"  {len(tiles)} tiles of {TILE_SIZE:.0f} m")

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    for lod in LODS:
        (OUT_DIR / lod).mkdir(parents=True)

    manifest_tiles = []
    totals = defaultdict(int)
    for n, (i, j) in enumerate(tiles):
        origin = (i * TILE_SIZE, 0.0, j * TILE_SIZE)
        entry = {"i": i, "j": j, "buildings": len(by_tile[(i, j)])}
        for lod, settings in LODS.items():
            building_mesh, ground_mesh = MeshBuilder(), MeshBuilder()
            for building in by_tile[(i, j)]:
                add_building(building_mesh, building, settings)
            build_ground(ground_mesh, tile_box(i, j), land, coast, roads, road_tree, parks, park_tree,
                         settings["ground_tolerance"])

            surfaces = []
            for kind, mesh in ((SURFACE_BUILDINGS, building_mesh), (SURFACE_GROUND, ground_mesh)):
                built = mesh.build(origin)
                if built is not None:
                    surfaces.append((kind, built))
                    totals[f"{lod}_vertices"] += len(built[0])
                    totals[f"{lod}_triangles"] += len(built[-1]) // 3
            if not surfaces:
                continue
            raw = encode_tile(surfaces)
            packed = zstd.compress(raw, level=12)
            (OUT_DIR / lod / f"{i}_{j}.nyct").write_bytes(packed)
            entry[lod] = {"bytes": len(packed), "raw_bytes": len(raw)}
            totals[f"{lod}_bytes"] += len(packed)
        if "lod0" in entry or "lod1" in entry:
            manifest_tiles.append(entry)
        if (n + 1) % 25 == 0:
            print(f"  {n + 1}/{len(tiles)} tiles")

    manifest = {
        "version": FORMAT_VERSION,
        "region": "manhattan",
        "tile_size": TILE_SIZE,
        "land_height": LAND_Y,
        "origin": {"lat": ORIGIN_LAT, "lon": ORIGIN_LON},
        "projection": PROJECTION,
        "bounds": {"min_x": min_e, "max_x": max_e, "min_z": -max_n, "max_z": -min_n},
        "lods": list(LODS),
        "tiles": manifest_tiles,
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=1))

    print(f"done in {time.time() - started:.0f} s: {len(manifest_tiles)} tiles")
    for lod in LODS:
        print(f"  {lod}: {totals[f'{lod}_bytes'] / 1e6:.1f} MB, "
              f"{totals[f'{lod}_vertices']:,} vertices, {totals[f'{lod}_triangles']:,} triangles")


if __name__ == "__main__":
    main()
