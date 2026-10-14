"""Build the game's streaming city tiles for all five boroughs.

Reads the prepared data (prepare.py, which reads fetch_data.py's downloads)
and writes data/tiles/nyc/:
  manifest.json        levels and tiles, read by scripts/world/city_streamer.gd
  lod0/<i>_<j>.nyct    500 m tiles, full detail: buildings, streets, sidewalks,
                       parks, raised lakes, walking lanes, bridges (with
                       collision in game)
  lod1/<i>_<j>.nyct    1 km tiles: buildings under 20 m merged into blocks,
                       taller ones simplified; simplified ground
  lod2/<i>_<j>.nyct    4 km tiles: everything under 60 m merged into blocks by
                       height band, skyscrapers simplified, ground without streets
The game shows a tile's children instead of the tile once they've all loaded.
The ground follows the real terrain (terrain.py); buildings stand on it.

Tile (i, j) of size T covers x in [i*T, (i+1)*T) and z in [j*T, (j+1)*T) in
Godot space (+X east, +Z south, origin at Times Square); its vertices are
stored relative to that corner. See common.py for the file format.

Usage: python build_tiles.py [--workers N]
"""

import argparse
import json
import os
import pickle
import shutil
import time
from collections import defaultdict
from compression import zstd
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np
import shapely
from shapely.geometry import Polygon

import bridges
import buildings3d
import prepare
from common import (CACHE_DIR, FORMAT_VERSION, GROUND_MARSH, GROUND_PARK, GROUND_PAVEMENT, GROUND_ROAD,
                    GROUND_SAND, GROUND_SEAWALL, LANE_BREAK, ORIGIN_LAT, ORIGIN_LON, PROJECTION, ROOF,
                    SEAWALL_BOTTOM_Y, STYLE_BRICK, STYLE_POSTWAR, SURFACE_BUILDINGS, SURFACE_GROUND,
                    SURFACE_LANES, SURFACE_STRUCTURES, SURFACE_WATER, TILES_DIR, MeshBuilder, encode_tile,
                    lines_of, polygon_normal, polygons_of, tile_box, tile_range, to_godot, triangulate_planar)
from terrain import Terrain

REGION = "nyc"
OUT_DIR = TILES_DIR / REGION

# ground_cell: the ground bends with the terrain at least this often (meters).
# shapes_from: buildings at least this tall (meters) get their real shape
# from the 3-D model instead of a footprint prism, where the model has one.
LEVELS = {
    "lod0": {"size": 500.0, "building_tolerance": 0.3, "ground_tolerance": 0.2, "keep_holes": True,
             "min_area": 4.0, "roads": True, "min_ground_area": 0.5, "ground_cell": 20.0,
             "shapes_from": 0.0},
    "lod1": {"size": 1000.0, "building_tolerance": 3.0, "ground_tolerance": 2.5, "keep_holes": False,
             "min_area": 60.0, "roads": True, "min_ground_area": 20.0, "ground_cell": 40.0,
             "shapes_from": 40.0,
             # Buildings lower than `individual_from` are merged into blocks, one
             # per height band (min height, max height, block height).
             "blocks": {"individual_from": 20.0, "bands": ((0.0, 12.0, 8.0), (12.0, 20.0, 15.0)),
                        "merge_gap": 1.5, "tolerance": 3.0, "min_area": 150.0}},
    "lod2": {"size": 4000.0, "building_tolerance": 6.0, "ground_tolerance": 15.0, "keep_holes": False,
             "min_area": 300.0, "roads": False, "min_ground_area": 5000.0, "ground_cell": 160.0,
             "shapes_from": 120.0,
             "blocks": {"individual_from": 60.0,
                        "bands": ((0.0, 12.0, 8.0), (12.0, 30.0, 18.0), (30.0, 60.0, 40.0)),
                        "merge_gap": 3.0, "tolerance": 10.0, "min_area": 1000.0}},
}

# Walking lanes for pedestrians: lines along every sidewalk.
LANE_OFFSET = 2.5  # meters in from the curb
LANE_WALL_GAP = 0.8  # keep this far from building walls
MIN_LANE_LENGTH = 10.0
LANE_STEP = 10.0  # points along a lane at least this often, to follow the terrain

# Raised lakes: the bed sits this far below the surface, and their shore walls
# reach a little below the bed.
LAKE_DEPTH = 2.5
SHORE_WALL_DEPTH = 4.5
# How far either side of a shoreline to look for the water's level (meters).
SHORE_PROBE = 4.0

# Real building shapes (buildings3d.py) replace a footprint prism only when
# the model still matches today's building: outlines overlapping at least
# this much (intersection over union of their convex hulls), and heights
# within the larger of these.
SHAPE_MIN_OVERLAP = 0.6
SHAPE_HEIGHT_TOLERANCE = (6.0, 0.25)  # meters, fraction of the height

_W = {}  # per-worker data, filled by _init_worker


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 4) - 2))
    args = parser.parse_args()
    started = time.time()

    buildings = prepare.load("buildings")
    ground = prepare.load("ground")
    prepare.load("water")
    prepare.load_terrain()
    buildings3d.load()
    print(f"{len(buildings['geoms']):,} buildings", flush=True)

    bridge_path = CACHE_DIR / "bridges.pkl"
    print("building bridges...", flush=True)
    bridge_buckets = bridges.build(ground["land"], Terrain(), {level: s["size"] for level, s in LEVELS.items()})
    with open(bridge_path, "wb") as f:
        pickle.dump(bridge_buckets, f, protocol=pickle.HIGHEST_PROTOCOL)

    land_parts = np.array(polygons_of(ground["land"], min_area=1.0), dtype=object)
    land_tree = shapely.STRtree(land_parts)
    tasks = []
    for level in ("lod2", "lod1", "lod0"):  # big tiles first, so they don't straggle at the end
        size = LEVELS[level]["size"]
        keys = set(_anchor_tiles(buildings["anchor"], size))
        keys |= set(bridge_buckets[level])
        for i, j in tile_range(ground["land"].bounds, size):
            if (i, j) not in keys and len(land_tree.query(tile_box(i, j, size), predicate="intersects")):
                keys.add((i, j))
        tasks += [(level, i, j) for i, j in sorted(keys)]
    del buildings, ground, land_parts, land_tree
    print(f"{len(tasks):,} tiles to build with {args.workers} workers", flush=True)

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    for level in LEVELS:
        (OUT_DIR / level).mkdir(parents=True)

    entries = defaultdict(list)
    totals = defaultdict(int)
    failed = []
    with ProcessPoolExecutor(max_workers=args.workers, initializer=_init_worker) as pool:
        futures = {pool.submit(_build_tile, task): task for task in tasks}
        for n, future in enumerate(as_completed(futures), 1):
            try:
                level, entry = future.result()
            except Exception as error:  # one bad tile shouldn't sink the whole build
                failed.append(futures[future])
                print(f"  FAILED {futures[future]}: {error}", flush=True)
                continue
            if entry:
                entries[level].append(entry)
                for key in ("bytes", "vertices", "triangles"):
                    totals[f"{level}_{key}"] += entry.pop(key)
                totals["lane_points"] += entry.pop("lane_points", 0)
            if n % 250 == 0 or n == len(tasks):
                print(f"  {n:,}/{len(tasks):,} tiles ({time.time() - started:.0f} s)", flush=True)

    min_e, min_n, max_e, max_n = prepare.load("ground")["land"].bounds
    manifest = {
        "version": FORMAT_VERSION,
        "region": REGION,
        "origin": {"lat": ORIGIN_LAT, "lon": ORIGIN_LON},
        "projection": PROJECTION,
        "bounds": {"min_x": min_e, "max_x": max_e, "min_z": -max_n, "max_z": -min_n},
        "levels": [
            {"name": level, "tile_size": s["size"],
             "tiles": sorted(entries[level], key=lambda e: (e["i"], e["j"]))}
            for level, s in LEVELS.items()
        ],
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, separators=(",", ":")))

    print(f"done in {time.time() - started:.0f} s", flush=True)
    for level in LEVELS:
        print(f"  {level}: {len(entries[level]):,} tiles, {totals[f'{level}_bytes'] / 1e6:.1f} MB, "
              f"{totals[f'{level}_vertices']:,} vertices, {totals[f'{level}_triangles']:,} triangles")
    print(f"  walking lanes: {totals['lane_points']:,} points")
    if failed:
        print(f"  {len(failed)} tiles FAILED and are missing: {failed}")
        raise SystemExit(1)


def _anchor_tiles(anchor: np.ndarray, size: float) -> list[tuple[int, int]]:
    ii = np.floor(anchor[:, 0] / size).astype(np.int64)
    jj = np.floor(-anchor[:, 1] / size).astype(np.int64)
    return list(zip(ii.tolist(), jj.tolist()))


def _init_worker() -> None:
    buildings = prepare.load("buildings")
    ground = prepare.load("ground")
    with open(CACHE_DIR / "bridges.pkl", "rb") as f:
        _W["bridges"] = pickle.load(f)
    _W["b"] = buildings
    _W["groups"] = {}
    for level, settings in LEVELS.items():
        groups = defaultdict(list)
        for index, key in enumerate(_anchor_tiles(buildings["anchor"], settings["size"])):
            groups[key].append(index)
        _W["groups"][level] = {key: np.array(value) for key, value in groups.items()}
    _W["building_tree"] = shapely.STRtree(buildings["geoms"])
    for name in ("land", "beaches", "marsh"):
        shapely.prepare(ground[name])
    _W["g"] = ground
    _W["coast"] = ground["land"].boundary
    _W["road_tree"] = shapely.STRtree(ground["roads"])
    _W["park_tree"] = shapely.STRtree(ground["parks"])
    _W["terrain"] = Terrain()
    _W["ground"] = {level: _W["terrain"].lattice(settings["ground_cell"]) for level, settings in LEVELS.items()}
    _W["creeks"] = {level: _W["terrain"].lattice(settings["ground_cell"], raw=True) for level, settings in LEVELS.items()}
    _W["water"] = prepare.load("water")
    _W["shapes"] = buildings3d.load()
    _W["water_tree"] = shapely.STRtree(_W["water"]["geoms"])


def _build_tile(task):
    level, i, j = task
    settings = LEVELS[level]
    size = settings["size"]
    origin = (i * size, 0.0, j * size)
    bounds = tile_box(i, j, size)

    building_mesh, ground_mesh, structure_mesh, water_mesh = MeshBuilder(), MeshBuilder(), MeshBuilder(), MeshBuilder()
    _W["level"] = level
    indices = _W["groups"][level].get((i, j), np.array([], dtype=np.int64))
    if settings.get("blocks"):
        _add_blocks(building_mesh, indices, settings)
    else:
        for index in indices:
            _add_building(building_mesh, index, settings)
    _add_ground(ground_mesh, bounds, settings)
    _add_raised_water(water_mesh, ground_mesh, bounds, settings)
    bridge = _W["bridges"][level].get((i, j))
    if bridge:
        structure_mesh.add(*bridge)

    surfaces = []
    stats = {"vertices": 0, "triangles": 0}
    for kind, mesh in ((SURFACE_BUILDINGS, building_mesh), (SURFACE_GROUND, ground_mesh),
                       (SURFACE_STRUCTURES, structure_mesh), (SURFACE_WATER, water_mesh)):
        built = mesh.build(origin)
        if built is not None:
            surfaces.append((kind, built))
            stats["vertices"] += len(built[0])
            stats["triangles"] += len(built[-1]) // 3
    if not surfaces:
        return level, None
    if level == "lod0":
        try:
            lanes = _build_lanes(bounds, origin)
        except shapely.errors.GEOSException as error:
            print(f"  no walking lanes in tile {i}_{j}: {error}", flush=True)
            lanes = None
        if lanes is not None:
            surfaces.append((SURFACE_LANES, lanes))
            stats["lane_points"] = len(lanes[0])

    raw = encode_tile(surfaces)
    packed = zstd.compress(raw, level=12)
    (OUT_DIR / level / f"{i}_{j}.nyct").write_bytes(packed)
    return level, {"i": i, "j": j, "bytes": len(packed), "raw_bytes": len(raw), **stats}


def _add_prism(builder: MeshBuilder, poly, height: float, style: int, seed: float) -> None:
    """A building standing on its lowest corner (heights are measured from
    there); uphill, its walls run into the ground."""
    poly = shapely.orient_polygons(poly)
    ground = _footprint_ground(poly)
    top = ground + height
    for ring in (poly.exterior, *poly.interiors):
        builder.add_walls(ring.coords, ground - 1.0, top, (style, seed), ground_y=ground)
    builder.add_flat([poly], top, (style + ROOF, seed))


def _footprint_ground(geom) -> float:
    """Where a building stands: the ground at its lowest corner."""
    ring = shapely.get_coordinates(shapely.get_exterior_ring(shapely.get_parts(geom)))
    return float(_W["ground"][_W["level"]].height(ring).min())


def _add_building(builder: MeshBuilder, index: int, settings: dict) -> None:
    b = _W["b"]
    height = float(b["height"][index])
    shape = _W["shapes"].get(int(b["bin"][index])) if height >= settings["shapes_from"] else None
    if shape is not None and _shape_matches(shape, b["geoms"][index], height):
        _add_shape(builder, shape, _footprint_ground(b["geoms"][index]), int(b["style"][index]),
                   float(b["seed"][index]))
        return
    geom = shapely.simplify(b["geoms"][index], settings["building_tolerance"], preserve_topology=True)
    for poly in polygons_of(geom, settings["min_area"]):
        if not settings["keep_holes"]:
            poly = Polygon(poly.exterior)
        _add_prism(builder, poly, float(b["height"][index]), int(b["style"][index]), float(b["seed"][index]))


def _shape_matches(shape, footprint, height: float) -> bool:
    """Whether the 3-D model's building is still today's (see SHAPE_MIN_OVERLAP)."""
    vertices, _, _, _, model_ground = shape
    model_hull = shapely.convex_hull(shapely.multipoints(vertices[:, :2]))
    hull = shapely.convex_hull(footprint)
    union = shapely.area(shapely.union(model_hull, hull))
    if union <= 0.0 or shapely.area(shapely.intersection(model_hull, hull)) / union < SHAPE_MIN_OVERLAP:
        return False
    model_height = float(vertices[:, 2].max() - model_ground)
    meters, fraction = SHAPE_HEIGHT_TOLERANCE
    return abs(model_height - height) <= max(meters, fraction * height)


def _add_shape(builder: MeshBuilder, shape, ground: float, style: int, seed: float) -> None:
    """A building from the 3-D model, moved to stand on our ground at `ground`.
    Walls get facade coordinates (meters along the wall, meters above the
    ground); roofs are marked as roofs."""
    vertices, offsets, ring_polygon, kinds, model_ground = shape
    points = vertices.astype(np.float64)
    points[:, 2] += ground - float(model_ground)
    # Sink the walls' feet a meter into the ground, like the prisms.
    points[points[:, 2] <= ground + 0.05, 2] -= 1.0
    starts = np.searchsorted(ring_polygon, np.arange(len(kinds)))
    ends = np.append(starts[1:], len(ring_polygon))
    for polygon, kind in enumerate(kinds):
        rings = [points[offsets[r]:offsets[r + 1]] for r in range(starts[polygon], ends[polygon])]
        tris = triangulate_planar(rings)
        if tris is None:
            continue
        normal = polygon_normal(rings[0])
        if kind == buildings3d.ROOF:
            if normal[2] < 0.0:
                normal = -normal
            uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
            uv2 = (style + ROOF, seed)
        else:
            along = np.array([-normal[1], normal[0]])
            length = np.linalg.norm(along)
            along = along / length if length > 1e-6 else np.array([1.0, 0.0])
            uv = np.stack([tris[..., 0] * along[0] + tris[..., 1] * along[1], tris[..., 2] - ground], axis=-1)
            uv2 = (style, seed)
        pos = np.stack([tris[..., 0], tris[..., 2], -tris[..., 1]], axis=-1)
        builder.add(pos, uv, uv2, (normal[0], normal[2], -normal[1]))


def _add_blocks(builder: MeshBuilder, indices: np.ndarray, settings: dict) -> None:
    """Tall buildings one by one; everything lower merged into simple blocks."""
    if len(indices) == 0:
        return
    blocks = settings["blocks"]
    b = _W["b"]
    heights = b["height"][indices]
    for index in indices[heights >= blocks["individual_from"]]:
        _add_building(builder, index, settings)
    gap = blocks["merge_gap"]
    for low, high, block_height in blocks["bands"]:
        band = indices[(heights >= low) & (heights < high)]
        if len(band) == 0:
            continue
        grown = shapely.buffer(b["geoms"][band], gap, join_style="mitre")
        try:
            merged = shapely.union_all(grown)
        except shapely.errors.GEOSException:
            merged = shapely.union_all(shapely.set_precision(grown, 0.01))  # see _add_ground
        merged = shapely.buffer(merged, -gap, join_style="mitre")
        merged = shapely.simplify(merged, blocks["tolerance"], preserve_topology=True)
        style = STYLE_BRICK if block_height < 12.0 else STYLE_POSTWAR
        for poly in polygons_of(merged, blocks["min_area"]):
            center = poly.centroid
            seed = float((hash((round(center.x), round(center.y))) % 1000) / 1000.0)
            _add_prism(builder, Polygon(poly.exterior), block_height, style, seed)


def _add_ground(builder: MeshBuilder, bounds, settings: dict) -> None:
    try:
        layers = _ground_layers(bounds, settings, grid=0.0)
    except shapely.errors.GEOSException:
        # GEOS overlays occasionally fail on nearly-coincident edges; snapping
        # everything to a 1 cm grid first gets them through.
        layers = _ground_layers(bounds, settings, grid=0.01)
    terrain = _W["ground"][_W["level"]]
    cell = settings["ground_cell"]
    for kind, geom in layers:
        geom = shapely.simplify(geom, settings["ground_tolerance"], preserve_topology=True)
        builder.add_draped(polygons_of(geom, min_area=settings["min_ground_area"]), cell, terrain.height,
                           (kind, 0.0), terrain.normal)

    # Walls where the land meets water: down into the sea, or into a raised
    # lake's bed.
    coast_t = shapely.clip_by_rect(_W["coast"], *bounds.bounds)
    if coast_t.geom_type == "MultiLineString":
        coast_t = shapely.line_merge(coast_t)
    coast_t = shapely.simplify(coast_t, settings["ground_tolerance"])
    for line in lines_of(coast_t):
        coords = np.asarray(shapely.segmentize(line, cell).coords)[:, :2]
        builder.add_walls(coords, _shore_wall_bottom(coords), terrain.height(coords), (GROUND_SEAWALL, 0.0))


def _shore_wall_bottom(coords: np.ndarray) -> np.ndarray:
    """How deep a shore wall goes at each point of a shoreline: below the sea
    floor line, or for a raised lake, a little below its bed. The water side
    is whichever side of the shoreline is lower."""
    ahead = np.vstack([coords[1:] - coords[:-1], coords[-1:] - coords[-2:-1]])
    behind = np.vstack([coords[1:2] - coords[:1], coords[1:] - coords[:-1]])
    tangent = ahead + behind
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-9)
    side = np.column_stack([-tangent[:, 1], tangent[:, 0]]) * SHORE_PROBE
    terrain = _W["terrain"]
    level = np.minimum(terrain.raw(coords + side), terrain.raw(coords - side))
    raised = level > prepare.RAISED_WATER_MIN - 0.5
    return np.where(raised, level - SHORE_WALL_DEPTH, SEAWALL_BOTTOM_Y)


def _add_raised_water(water: MeshBuilder, ground: MeshBuilder, bounds, settings: dict) -> None:
    """Lakes, reservoirs and creeks above sea level: a water surface (a flat
    one for lakes, one that follows the terrain down for creeks) over a bed."""
    w = _W["water"]
    creeks = _W["creeks"][_W["level"]]
    cell = settings["ground_cell"]
    for k in _W["water_tree"].query(bounds, predicate="intersects"):
        clipped = shapely.intersection(w["geoms"][k], bounds)
        clipped = shapely.simplify(clipped, settings["ground_tolerance"], preserve_topology=True)
        polys = polygons_of(clipped, min_area=settings["min_ground_area"])
        if not polys:
            continue
        level = float(w["level"][k])
        if np.isnan(level):
            def surface(en):
                return np.maximum(creeks.height(en), prepare.RAISED_WATER_MIN)
            water.add_draped(polys, cell, surface, (0.0, 0.0))
            ground.add_draped(polys, cell, lambda en: surface(en) - LAKE_DEPTH, (GROUND_MARSH, 0.0))
        else:
            water.add_flat(polys, level, (0.0, 0.0))
            ground.add_flat(polys, level - LAKE_DEPTH, (GROUND_MARSH, 0.0))


def _ground_layers(bounds, settings: dict, grid: float) -> list:
    """The tile's land split into [(kind, geometry)]: pavement, roads, parks, sand, marsh.

    With `grid`, inputs are snapped to that precision first.
    """
    def snap(geom):
        return shapely.set_precision(geom, grid) if grid else geom

    def clip(geom):
        # A plain rectangle clip: no general overlay on the city-sized geometry.
        return _polygonal(snap(shapely.make_valid(shapely.clip_by_rect(geom, *bounds.bounds))))

    g = _W["g"]
    land_t = clip(g["land"])
    if land_t.is_empty:
        return []
    roads_t = Polygon()
    if settings["roads"]:
        nearby = g["roads"][_W["road_tree"].query(bounds)]
        if len(nearby):
            roads_t = _polygonal(shapely.intersection(shapely.union_all(snap(nearby)), land_t))
    parks_t = Polygon()
    nearby = g["parks"][_W["park_tree"].query(bounds)]
    if len(nearby):
        parks_t = _polygonal(shapely.intersection(shapely.union_all(snap(nearby)), land_t))
    sand_t = shapely.difference(clip(g["beaches"]), roads_t)
    marsh_t = shapely.difference(shapely.difference(clip(g["marsh"]), roads_t), sand_t)
    parks_t = shapely.difference(shapely.difference(shapely.difference(parks_t, roads_t), sand_t), marsh_t)
    pavement_t = land_t
    for other in (roads_t, parks_t, sand_t, marsh_t):
        pavement_t = shapely.difference(pavement_t, other)
    return [(GROUND_PAVEMENT, pavement_t), (GROUND_ROAD, roads_t), (GROUND_PARK, parks_t),
            (GROUND_SAND, sand_t), (GROUND_MARSH, marsh_t)]


def _polygonal(geom):
    """Only the polygon parts of a geometry (overlays can leave stray lines and
    points, which make later overlays fail), as a MultiPolygon or empty Polygon."""
    parts = polygons_of(geom, min_area=0.0)
    return shapely.MultiPolygon(parts) if parts else Polygon()


def _build_lanes(bounds, origin):
    """Walking lanes along every sidewalk in the tile, LANE_OFFSET in from the curb.

    Returns the lanes surface (positions, normals, uv, uv2, indices), or None.
    """
    g = _W["g"]
    # Look a little past the tile so sidewalks along its edges still find their street.
    area = shapely.buffer(bounds, 4 * LANE_OFFSET, join_style="mitre")
    nearby_roads = g["roads"][_W["road_tree"].query(area)]
    if not len(nearby_roads):
        return None
    roads_near = shapely.intersection(shapely.union_all(nearby_roads), g["land"])
    nearby_buildings = _W["b"]["geoms"][_W["building_tree"].query(area)]
    sidewalks = shapely.difference(shapely.intersection(g["land"], bounds), roads_near)
    if len(nearby_buildings):
        sidewalks = shapely.difference(sidewalks, shapely.buffer(shapely.union_all(nearby_buildings), LANE_WALL_GAP))
    lanes = shapely.intersection(shapely.buffer(roads_near, LANE_OFFSET).boundary, sidewalks)

    lines = [line for line in lines_of(lanes) if line.length >= 1.0]
    if not lines:
        return None
    points, indices = [], []
    for line in lines_of(shapely.line_merge(shapely.MultiLineString(lines))):
        if line.length < MIN_LANE_LENGTH:
            continue
        coords = np.asarray(shapely.segmentize(shapely.simplify(line, 0.5), LANE_STEP).coords)[:, :2]
        start = len(points)
        points.extend(to_godot(coords, _W["ground"]["lod0"].height(coords)) - np.asarray(origin))
        indices.extend(range(start, start + len(coords)))
        indices.append(LANE_BREAK)
    if not points:
        return None
    positions = np.round(np.asarray(points), 2).astype(np.float32)
    zeros2 = np.zeros((len(positions), 2), dtype=np.float32)
    return positions, np.zeros_like(positions), zeros2, zeros2, np.asarray(indices, dtype=np.uint32)


if __name__ == "__main__":
    main()
