"""Build the game's streaming city tiles for all five boroughs.

Reads the prepared data (prepare.py, which reads fetch_data.py's downloads)
and writes data/tiles/nyc/:
  manifest.json        levels and tiles, read by scripts/world/city_streamer.gd
  lod0/<i>_<j>.nyct    500 m tiles, full detail: buildings, streets, sidewalks,
                       parks, raised lakes, walking lanes, bridges (with
                       collision in game), paint on the streets (markings.py),
                       trees and water towers (props.py)
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
from pathlib import Path
from collections import defaultdict
from compression import zstd
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np
import shapely
from shapely.geometry import Polygon

import bridges
import buildings3d
import cantilever
import els
import facades
import fronts
import ground_details
import landcover
import landmarks
import markings
import overpasses
import prepare
import props
import times_square
import towers
import traffic
from common import (CACHE_DIR, CURB_HEIGHT, FORMAT_VERSION, GROUND_MARSH, GROUND_PARK, GROUND_PAVEMENT,
                    GROUND_ROAD, GROUND_SAND, GROUND_SEAWALL, GROUND_SHRUBS, GROUND_YARD, LANE_BREAK, MARKING_LIFT,
                    ORIGIN_LAT, ORIGIN_LON, PROJECTION, PROP_BUS_SHELTER, PROP_HYDRANT, PROP_PARKED_CAR, PROP_PARKING_METER,
                    PROP_TRAFFIC_SIGNAL, PROP_WATER_TOWER, SEAWALL_BOTTOM_Y,
                    STRUCTURE_CONCRETE, SURFACE_LANDMARKS,
                    SURFACE_BUILDINGS, SURFACE_GROUND, SURFACE_LANES, SURFACE_MARKINGS, SURFACE_PROPS,
                    SURFACE_STRUCTURES, SURFACE_TRAFFIC, SURFACE_WATER, TILES_DIR, MeshBuilder, encode_tile, lines_of,
                    polygon_normal, polygons_of, tile_box, tile_range, to_godot, triangles_of,
                    triangulate_planar)
from terrain import Terrain

REGION = "nyc"
# --out (passed on to the worker processes through the environment) puts the
# tiles, and the bridges they're built from, somewhere else.
OUT_DIR = Path(os.environ["NYC_TILES_OUT"]) if os.environ.get("NYC_TILES_OUT") else TILES_DIR / REGION
BRIDGE_PATH = OUT_DIR.parent / f"{REGION}_bridges.pkl" if os.environ.get("NYC_TILES_OUT") else CACHE_DIR / "bridges.pkl"

# ground_cell: the ground bends with the terrain at least this often (meters).
# shapes_from: buildings at least this tall (meters) get their real shape
# from the 3-D model instead of a footprint prism, where the model has one.
# curbs: streets sit CURB_HEIGHT below the sidewalks, behind curbs (up close
# only; from further away nobody can tell).
# roofs: flat roofs get parapets and houses pitched roofs (up close only).
LEVELS = {
    "lod0": {"size": 500.0, "building_tolerance": 0.3, "ground_tolerance": 0.2, "keep_holes": True,
             "min_area": 4.0, "roads": True, "min_ground_area": 0.5, "ground_cell": 20.0,
             "shapes_from": 0.0, "curbs": True, "roofs": True},
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

# Sign walls (facades.SIGNS) at least this wide measure uv.x from their own
# left corner, so the shader can fit screens to them (narrower ones, like the
# facets of a rounded corner, keep measuring along the building).
SIGN_FACE_MIN = 6.0

# Gaps between road pieces narrower than twice this (meters) are filled.
ROAD_GAP = 0.25

# Yards: paved ground further than SIDEWALK_WIDTH from any street and within
# YARD_REACH of a home is a yard (back yards, gardens, lawns around housing
# towers). Lots, plazas, rail yards and airports away from homes stay paved.
SIDEWALK_WIDTH = 6.0
YARD_REACH = 25.0
HOMES = (facades.HOUSE, facades.ROWHOUSE, facades.WALKUP, facades.PREWAR_APARTMENT,
         facades.POSTWAR_APARTMENT, facades.MODERN_RESIDENTIAL)

# Raised lakes: the bed sits this far below the surface, and their shore walls
# reach a little below the bed.
LAKE_DEPTH = 2.5
SHORE_WALL_DEPTH = 4.5
# How far either side of a shoreline to look for the water's level (meters).
SHORE_PROBE = 4.0

# Real building shapes (buildings3d.py) replace a footprint prism only when
# the model still matches today's building: outlines overlapping at least
# this much (intersection over union of their convex hulls), and the model
# not shorter than the footprint's height by more than the larger of these
# (then it's a building since replaced by a taller one). A taller model is
# right: footprint heights often measure a podium (the MetLife Building's is
# Grand Central's 48 m) or stop below a spire (One World Trade Center).
SHAPE_MIN_OVERLAP = 0.6
SHAPE_HEIGHT_TOLERANCE = (6.0, 0.25)  # meters, fraction of the height

# A wall faces a street (gets a storefront, fire escapes, more windows) if a
# road is within FRONT_REACH of a point this far in front of it; two points,
# so setback walls above a lower roof count too.
FRONT_PROBES = (6.0, 15.0)
FRONT_REACH = 4.0

# Pitched roofs: houses whose footprint fills at least PITCH_FILL of its
# smallest enclosing rectangle, PITCH_WIDTH wide, get a gable or (on longer
# ones, HIP_SHARE of the time) a hip roof, PITCH_DEGREES steep, rising to the
# building's height; the walls stop at the eaves, at least MIN_EAVES up.
PITCH_FILL = 0.8
PITCH_WIDTH = (3.5, 16.0)
PITCH_DEGREES = (28.0, 40.0)
HIP_SHARE = 0.4
MIN_EAVES = 2.6

# Paint can come from street centerlines this far outside a tile.
MARKING_REACH = 30.0
# Street trees standing in the road (the inventory and the road outlines
# disagree by a meter or two) move this far onto the sidewalk, unless they'd
# have to move further than TREE_MAX_MOVE (then they're left out).
TREE_CURB_GAP = 0.8
TREE_MAX_MOVE = 4.0
# Hydrants and parking meters stand CURBSIDE_GAP from the curb; the data puts
# some of them meters back, so ones within CURBSIDE_REACH of it move up.
CURBSIDE_TYPES = (PROP_HYDRANT, PROP_PARKING_METER)
CURBSIDE_GAP = 0.5
CURBSIDE_REACH = 6.0
# Canopy trees keep this far from street trees (which already stand for the
# canopy over sidewalks) and judge how wooded it is within CANOPY_REACH.
CANOPY_CLEARANCE = 4.5
CANOPY_REACH = 6.0

# Each worker holds the whole city (about 3.5 GB in October 2026), so the
# default worker count also leaves this much memory per worker, plus
# MEMORY_SPARE for everything else.
WORKER_MEMORY_GB = 4.0
MEMORY_SPARE_GB = 12.0

_W = {}  # per-worker data, filled by _init_worker


def _default_workers() -> int:
    """All cores but two, as many as fit in memory."""
    cores = max(1, (os.cpu_count() or 4) - 2)
    try:
        if os.name == "nt":
            import ctypes

            class MemoryStatus(ctypes.Structure):
                _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong),
                            ("total", ctypes.c_ulonglong), ("available", ctypes.c_ulonglong),
                            ("total_page", ctypes.c_ulonglong), ("available_page", ctypes.c_ulonglong),
                            ("total_virtual", ctypes.c_ulonglong), ("available_virtual", ctypes.c_ulonglong),
                            ("available_extended", ctypes.c_ulonglong)]
            status = MemoryStatus(length=ctypes.sizeof(MemoryStatus))
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
            total = status.total
        else:
            total = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    except (AttributeError, OSError, ValueError):
        return cores
    return max(1, min(cores, int((total / 2**30 - MEMORY_SPARE_GB) / WORKER_MEMORY_GB)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=_default_workers(),
                        help="processes building tiles (default: all cores but two, as memory allows)")
    parser.add_argument("--out", type=Path, help="build into this tiles directory instead of data/tiles/nyc")
    parser.add_argument("--only", nargs="+", metavar="LEVEL:I,J",
                        help="rebuild just these tiles (e.g. lod0:0,-1) in an existing build in --out, "
                             "updating its manifest; for trying changes quickly")
    args = parser.parse_args()
    if args.out:
        os.environ["NYC_TILES_OUT"] = str(args.out.resolve())
        _set_out(args.out.resolve())
    if args.only:
        _rebuild(args.only, args.workers)
        return
    started = time.time()

    buildings = prepare.load("buildings")
    ground = prepare.load("ground")
    prepare.load("water")
    prepare.load("facades")
    prepare.load("trees")
    prepare.load("centerline")
    prepare.load("furniture")
    prepare.load("ground_details")
    prepare.load_terrain()
    prepare.load_landcover()
    buildings3d.load()
    print(f"{len(buildings['geoms']):,} buildings", flush=True)

    bridge_buckets = _build_bridges(ground)

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

    # Only our own folders: the aerial photos (aerial.py) live alongside.
    for level in LEVELS:
        if (OUT_DIR / level).exists():
            shutil.rmtree(OUT_DIR / level)
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
                for key in ("lane_points", "props", "trees", "water_towers", "street_lights", "furniture",
                            "parked_cars", "traffic_lanes"):
                    totals[key] += entry.pop(key, 0)
            if n % 250 == 0 or n == len(tasks):
                print(f"  {n:,}/{len(tasks):,} tiles ({time.time() - started:.0f} s)", flush=True)

    min_e, min_n, max_e, max_n = prepare.load("ground")["land"].bounds
    canopy = landcover.write_canopy_map(OUT_DIR / "canopy.png")
    manifest = {
        "version": FORMAT_VERSION,
        # Goes on tile URLs, so browsers never mix tiles from different builds.
        "build": f"{int(started):x}",
        "region": REGION,
        # Building faces carry archetype, flags and floor height (facades.py).
        "facades": 1,
        "origin": {"lat": ORIGIN_LAT, "lon": ORIGIN_LON},
        "projection": PROJECTION,
        "bounds": {"min_x": min_e, "max_x": max_e, "min_z": -max_n, "max_z": -min_n},
        # How much of each 16 m square is tree canopy, citywide (landcover.py).
        "canopy": canopy,
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
    print(f"  props: {totals['trees']:,} trees, {totals['water_towers']:,} water towers, "
          f"{totals['street_lights']:,} street lights, {totals['furniture']:,} pieces of street furniture, "
          f"{totals['parked_cars']:,} parked cars")
    print(f"  driving lanes: {totals['traffic_lanes']:,}")
    if failed:
        print(f"  {len(failed)} tiles FAILED and are missing: {failed}")
        raise SystemExit(1)


def _anchor_tiles(anchor: np.ndarray, size: float) -> list[tuple[int, int]]:
    ii = np.floor(anchor[:, 0] / size).astype(np.int64)
    jj = np.floor(-anchor[:, 1] / size).astype(np.int64)
    return list(zip(ii.tolist(), jj.tolist()))


def _set_out(path: Path) -> None:
    global OUT_DIR, BRIDGE_PATH
    OUT_DIR = path
    BRIDGE_PATH = path.parent / f"{REGION}_bridges.pkl"


def _build_bridges(ground) -> dict:
    print("building bridges...", flush=True)
    terrain = Terrain()
    sizes = {level: s["size"] for level, s in LEVELS.items()}
    # Raised roads first: bridge approaches come down to them (overpasses.py),
    # at the heights the lidar survey has them (lidar.py), with the roadways
    # the BQE's triple cantilever carries (cantilever.py).
    network = overpasses.Network(prepare.load("overpasses"), prepare.load("centerline"), terrain, _structure(terrain),
                                 prepare.load("deck_heights"))
    buckets = bridges.build(ground["land"], terrain, sizes, approach=network.approach)
    overpasses.build(network, ground["land"], buckets, sizes)
    cantilever.build(network, buckets, sizes)
    # Elevated railways over (and around) both (els.py).
    els.build(prepare.load("els"), network, ground["land"], buckets, sizes)
    # No roadbed drawn on the ground under them where no street is.
    buckets["roads_under_decks"] = overpasses.roads_under_decks(network, buckets.pop("overhead", []), ground["roads"])
    print(f"  {len(buckets['roads_under_decks'])} roadbed outlines cut back from under decks", flush=True)
    # Walking lanes on bridges' and raised streets' sidewalks.
    buckets["deck_walks"] = np.concatenate([overpasses.deck_walks(network, prepare.load("deck_sidewalks")["geoms"]),
                                            cantilever.walks(network.structure)])
    print(f"  {len(buckets['deck_walks'])} walking lanes on decks", flush=True)
    BRIDGE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(BRIDGE_PATH, "wb") as f:
        pickle.dump(buckets, f, protocol=pickle.HIGHEST_PROTOCOL)
    return buckets


def _structure(terrain):
    """The BQE's triple cantilever (cantilever.py): its roadways, and the
    ground cut away under it and filled up behind it."""
    return cantilever.Structure(prepare.load("cantilever"), terrain, prepare.load("centerline"),
                                prepare.load("overpasses"))


def _rebuild(only: list[str], workers: int) -> None:
    """Rebuilds the listed tiles (level:i,j) of the build in OUT_DIR, with the
    bridges, and updates their manifest entries and the build id."""
    started = time.time()
    manifest_path = OUT_DIR / "manifest.json"
    if OUT_DIR == TILES_DIR / REGION or not manifest_path.exists():
        raise SystemExit("--only needs --out pointing at a copy of a full build (with its manifest.json)")
    _build_bridges(prepare.load("ground"))
    prepare.load("ground_details")
    tasks = []
    for item in only:
        level, ij = item.split(":")
        i, j = (int(v) for v in ij.split(","))
        tasks.append((level, i, j))
    manifest = json.loads(manifest_path.read_text())
    levels = {data["name"]: data for data in manifest["levels"]}
    with ProcessPoolExecutor(max_workers=min(workers, len(tasks)), initializer=_init_worker) as pool:
        for (level, i, j), (_, entry) in zip(tasks, pool.map(_build_tile, tasks)):
            tiles = levels[level]["tiles"]
            old = next((e for e in tiles if e["i"] == i and e["j"] == j), None)
            if entry is None:
                if old:
                    tiles.remove(old)
                print(f"  {level} {i},{j}: empty", flush=True)
                continue
            counts = {key: entry.pop(key) for key in list(entry) if key not in ("i", "j", "raw_bytes")}
            if old:
                old.update(entry)
            else:
                tiles.append(entry)
                tiles.sort(key=lambda e: (e["i"], e["j"]))
            print(f"  {level} {i},{j}: {counts}", flush=True)
    manifest["build"] = f"{int(started):x}"
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")))
    print(f"rebuilt {len(tasks)} tiles in {time.time() - started:.0f} s", flush=True)


def _init_worker() -> None:
    buildings = prepare.load("buildings")
    ground = prepare.load("ground")
    with open(BRIDGE_PATH, "rb") as f:
        _W["bridges"] = pickle.load(f)
    # Roadbed under raised roads and bridges, away from streets, isn't road (overpasses.py).
    for index, left in _W["bridges"].get("roads_under_decks", {}).items():
        ground["roads"][index] = left
    walks = _W["bridges"].get("deck_walks", np.zeros(0, dtype=object))
    _W["deck_walk_tree"] = shapely.STRtree(walks) if len(walks) else None
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
    # The ground cut away under the triple cantilever and filled up behind it (cantilever.py).
    _W["structure"] = _structure(_W["terrain"])
    _W["ground"] = {level: _W["structure"].ground(_W["terrain"].lattice(settings["ground_cell"]))
                    for level, settings in LEVELS.items()}
    # Things on streets that cross dips on decks stand on the deck (overpasses.py).
    _W["ground"]["lod0"] = overpasses.OnDecks(_W["ground"]["lod0"], _W["bridges"].get("street_decks", []))
    _W["creeks"] = {level: _W["terrain"].lattice(settings["ground_cell"], raw=True) for level, settings in LEVELS.items()}
    _W["water"] = prepare.load("water")
    _W["shapes"] = buildings3d.load()
    _W["facades"] = prepare.load("facades")
    _W["building_index_tree"] = shapely.STRtree(buildings["geoms"])
    _W["water_tree"] = shapely.STRtree(_W["water"]["geoms"])
    _W["centerline"] = prepare.load("centerline")
    _W["centerline_tree"] = shapely.STRtree(_W["centerline"]["lines"])
    _W["overpasses"] = overpasses.Network(prepare.load("overpasses"), _W["centerline"], _W["terrain"], _W["structure"],
                                          prepare.load("deck_heights"))
    trees = prepare.load("trees")
    _W["trees"] = trees
    groups = defaultdict(list)
    for index, key in enumerate(_anchor_tiles(trees["en"], LEVELS["lod0"]["size"])):
        groups[key].append(index)
    _W["tree_groups"] = {key: np.array(value) for key, value in groups.items()}
    furniture = prepare.load("furniture")
    _W["furniture"] = furniture
    groups = defaultdict(list)
    for index, key in enumerate(_anchor_tiles(furniture["en"], LEVELS["lod0"]["size"])):
        groups[key].append(index)
    _W["furniture_groups"] = {key: np.array(value) for key, value in groups.items()}
    blockers = np.isin(furniture["type"], (PROP_HYDRANT, PROP_BUS_SHELTER))
    _W["car_blockers"] = (furniture["en"][blockers],
                          np.where(furniture["type"][blockers] == PROP_HYDRANT, traffic.HYDRANT_CLEAR,
                                   traffic.BUS_STOP_CLEAR))
    _W["landcover"] = landcover.LandCover()
    _W["details"] = ground_details.GroundDetails(prepare.load("ground_details"))


def _build_tile(task):
    level, i, j = task
    settings = LEVELS[level]
    size = settings["size"]
    origin = (i * size, 0.0, j * size)
    bounds = tile_box(i, j, size)

    building_mesh, ground_mesh, structure_mesh, water_mesh = MeshBuilder(), MeshBuilder(), MeshBuilder(), MeshBuilder()
    landmark_mesh = MeshBuilder()
    _W["level"] = level
    _W["streets"] = _streets_near(bounds)
    indices = _W["groups"][level].get((i, j), np.array([], dtype=np.int64))
    # Hand-made landmarks (landmarks.py) stand in for their data buildings.
    indices = landmarks.without(indices, _W["b"]["bin"])
    indices = times_square.without(indices, _W["b"]["bin"])  # the TKTS booth's steps stand in for it
    if settings.get("blocks"):
        _add_blocks(building_mesh, indices, settings)
    else:
        for index in indices:
            _add_building(building_mesh, index, settings)
    landmarks.add_to_tile(building_mesh, level, size, i, j, _W["b"], _W["shapes"], _footprint_ground,
                          overpasses.bare(_W["ground"][level]).height, landmark_mesh)
    times_square.add_to_tile(building_mesh, level, size, i, j, _W, _footprint_ground)
    _add_ground(ground_mesh, bounds, settings)
    _add_raised_water(water_mesh, ground_mesh, bounds, settings)
    bridge = _W["bridges"][level].get((i, j))
    if bridge:
        structure_mesh.add(*bridge)

    surfaces = []
    stats = {"vertices": 0, "triangles": 0}
    for kind, mesh in ((SURFACE_BUILDINGS, building_mesh), (SURFACE_GROUND, ground_mesh),
                       (SURFACE_STRUCTURES, structure_mesh), (SURFACE_WATER, water_mesh),
                       (SURFACE_LANDMARKS, landmark_mesh)):
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
        marking_mesh = MeshBuilder()
        _add_markings(marking_mesh, bounds)
        built = marking_mesh.build(origin, decimals=2)
        if built is not None:
            surfaces.append((SURFACE_MARKINGS, built))
            stats["vertices"] += len(built[0])
            stats["triangles"] += len(built[-1]) // 3
        lanes_surface = _build_traffic(bounds, origin)
        if lanes_surface is not None:
            surfaces.append((SURFACE_TRAFFIC, lanes_surface))
            stats["traffic_lanes"] = int(np.sum(lanes_surface[-1] == LANE_BREAK))
        prop_surface, counts = _build_props(i, j, bounds, indices, origin)
        if prop_surface is not None:
            surfaces.append((SURFACE_PROPS, prop_surface))
            stats.update(counts)

    raw = encode_tile(surfaces)
    packed = zstd.compress(raw, level=12)
    (OUT_DIR / level / f"{i}_{j}.nyct").write_bytes(packed)
    return level, {"i": i, "j": j, "bytes": len(packed), "raw_bytes": len(raw), **stats}


def _streets_near(bounds):
    """The road surface around a tile, for telling which walls face a street."""
    area = shapely.buffer(bounds, max(FRONT_PROBES) + FRONT_REACH + 10.0, join_style="mitre")
    nearby = _W["g"]["roads"][_W["road_tree"].query(area)]
    streets = shapely.union_all(nearby) if len(nearby) else Polygon()
    shapely.prepare(streets)
    return streets


def _faces_street(middles: np.ndarray, outward: np.ndarray) -> np.ndarray:
    """For walls with these (N, 2) midpoints and outward unit normals (east/north),
    whether each faces a street."""
    streets = _W["streets"]
    if streets.is_empty or len(middles) == 0:
        return np.zeros(len(middles), dtype=bool)
    near = np.zeros(len(middles), dtype=bool)
    for reach in FRONT_PROBES:
        probes = middles + outward * reach
        near |= shapely.dwithin(streets, shapely.points(probes), FRONT_REACH)
    return near


def _facade(index: int) -> tuple[int, int, int, float]:
    """A building's (archetype, flags, floor height in dm, seed)."""
    f, b = _W["facades"], _W["b"]
    archetype, flags = int(f["archetype"][index]), int(f["flags"][index])
    # PLUTO's retail area isn't always a shopfront: none on landmark institutions
    # (the Racquet Club's arcade on Park Avenue).
    if archetype == facades.INSTITUTION and flags & facades.LANDMARK:
        flags &= ~facades.RETAIL
    return archetype, flags, int(f["floor_dm"][index]), float(b["seed"][index])


def _add_prism(builder: MeshBuilder, poly, height: float, facade: tuple, fronts: bool = True,
               parapet: bool = False) -> None:
    """A building standing on its lowest corner (heights are measured from
    there); uphill, its walls run into the ground. Walls facing a street are
    marked FRONT (unless `fronts` is off, for merged blocks). With `parapet`,
    the walls rise PARAPET_HEIGHT above the roof, with an inner face."""
    archetype, flags, floor_dm, seed = facade
    poly = shapely.orient_polygons(poly)
    ground = _footprint_ground(poly)
    top = ground + height
    wall_flags = flags | (facades.PARAPET if parapet else 0)
    for ring in (poly.exterior, *poly.interiors):
        coords = np.asarray(ring.coords)[:, :2]
        uv2 = _wall_uv2(coords, (archetype, wall_flags, floor_dm, seed), fronts)
        restart = _sign_faces(coords, uv2)
        if parapet:
            builder.add_walls(coords, ground - 1.0, top + facades.PARAPET_HEIGHT, uv2, ground_y=ground,
                              restart=restart)
            inside = facades.encode(archetype, flags | facades.PARAPET_INSIDE, floor_dm, seed)
            builder.add_walls(coords[::-1], top, top + facades.PARAPET_HEIGHT, inside, ground_y=ground)
        else:
            builder.add_walls(coords, ground - 1.0, top, uv2, ground_y=ground, restart=restart)
    builder.add_flat([poly], top, facades.encode(archetype, flags | facades.ROOF, floor_dm, seed))


def _wall_uv2(coords: np.ndarray, facade: tuple, fronts: bool) -> np.ndarray:
    """Per-segment uv2 for walls along coords, FRONT where they face a street."""
    archetype, flags, floor_dm, seed = facade
    uv2 = np.tile(facades.encode(archetype, flags, floor_dm, seed), (max(len(coords) - 1, 0), 1))
    if fronts and len(coords) > 1:
        seg = coords[1:] - coords[:-1]
        length = np.maximum(np.hypot(seg[:, 0], seg[:, 1]), 1e-9)
        outward = np.column_stack([seg[:, 1], -seg[:, 0]]) / length[:, None]  # right of travel
        middles = (coords[1:] + coords[:-1]) * 0.5
        front = _faces_street(middles, outward) | times_square.faces_plaza(_W, middles, outward)
        uv2[front, 0] += facades.FLAG_SCALE * facades.FRONT
        signs = front & props.in_sign_district(middles)
        uv2[signs, 0] += facades.FLAG_SCALE * (facades.SIGNS + _W.get("sign_part", 0) * facades.FRONT_PART)
    return uv2


def _sign_faces(coords: np.ndarray, uv2: np.ndarray) -> np.ndarray:
    """Which wall segments along coords (with per-segment uv2) are sign walls
    of at least SIGN_FACE_MIN, measuring uv.x from their own corner."""
    flags = (np.asarray(uv2)[:, 0] // facades.FLAG_SCALE).astype(np.int64)
    seg = np.diff(np.asarray(coords)[:, :2], axis=0)
    return ((flags & facades.SIGNS) != 0) & (np.hypot(seg[:, 0], seg[:, 1]) >= SIGN_FACE_MIN)


def _add_pitched(builder: MeshBuilder, poly, height: float, facade: tuple) -> bool:
    """A house with a gable or hip roof over its footprint's smallest
    enclosing rectangle, peaking at `height` (see PITCH_FILL). Returns False,
    adding nothing, if the footprint doesn't suit one."""
    archetype, flags, floor_dm, seed = facade
    if len(poly.interiors):
        return False
    rect = shapely.oriented_envelope(poly)
    if rect.geom_type != "Polygon" or poly.area < PITCH_FILL * rect.area:
        return False
    corners = np.asarray(rect.exterior.coords)[:4]
    edges = [corners[1] - corners[0], corners[2] - corners[1]]
    lengths = [float(np.hypot(*e)) for e in edges]
    k = 0 if lengths[0] >= lengths[1] else 1
    along, length = edges[k] / lengths[k], lengths[k]
    across, width = edges[1 - k] / lengths[1 - k], lengths[1 - k]
    if not PITCH_WIDTH[0] <= width <= PITCH_WIDTH[1]:
        return False
    r = props.location_seed(np.array([[seed * 1000.0, 17.0]]))[0]
    degrees = PITCH_DEGREES[0] + (PITCH_DEGREES[1] - PITCH_DEGREES[0]) * r
    rise = min(np.tan(np.radians(degrees)) * width / 2, height - MIN_EAVES)
    if rise < 1.0:
        return False
    pitch = np.arctan2(rise, width / 2)  # shallower than `degrees` on low houses
    hip = props.location_seed(np.array([[seed * 1000.0, 29.0]]))[0] < HIP_SHARE and length > 1.15 * width
    center = corners.mean(axis=0)
    poly = shapely.orient_polygons(poly)
    ground = _footprint_ground(poly)
    eaves = ground + height - rise
    half_l, half_w = length / 2, width / 2

    def local(en):
        d = np.asarray(en, np.float64).reshape(-1, 2) - center
        return d @ along, d @ across

    def roof_height(en):
        u, v = local(en)
        slope = 1.0 - np.abs(v) / half_w
        if hip:
            slope = np.minimum(slope, (half_l - np.abs(u)) / half_w)
        return eaves + rise * np.clip(slope, 0.0, 1.0)

    def world(uv):
        uv = np.asarray(uv, np.float64)
        return center + uv[:, :1] * along + uv[:, 1:] * across

    # Roof faces in (u, v): each with its outline and its downhill direction.
    if hip:
        ridge = half_l - half_w
        faces = [([(-half_l, half_w), (half_l, half_w), (ridge, 0.0), (-ridge, 0.0)], (0.0, 1.0)),
                 ([(-half_l, -half_w), (half_l, -half_w), (ridge, 0.0), (-ridge, 0.0)], (0.0, -1.0)),
                 ([(half_l, half_w), (half_l, -half_w), (ridge, 0.0)], (1.0, 0.0)),
                 ([(-half_l, half_w), (-half_l, -half_w), (-ridge, 0.0)], (-1.0, 0.0))]
        breaks = [[(-half_l, half_w), (-ridge, 0.0), (ridge, 0.0), (half_l, half_w)],
                  [(-half_l, -half_w), (-ridge, 0.0)], [(ridge, 0.0), (half_l, -half_w)]]
    else:
        faces = [([(-half_l, half_w), (half_l, half_w), (half_l, 0.0), (-half_l, 0.0)], (0.0, 1.0)),
                 ([(-half_l, -half_w), (half_l, -half_w), (half_l, 0.0), (-half_l, 0.0)], (0.0, -1.0))]
        breaks = [[(-half_l - 1.0, 0.0), (half_l + 1.0, 0.0)]]
    grown = shapely.buffer(poly, 0.01, join_style="mitre")
    roof_uv2 = facades.encode(archetype, flags | facades.ROOF, floor_dm, seed)
    for outline, down in faces:
        piece = shapely.intersection(Polygon(world(np.array(outline) * 1.002)), grown)
        tris = [t for t in (triangles_of(p) for p in polygons_of(piece, 0.01)) if t is not None]
        if not tris:
            continue
        tris = np.concatenate(tris)
        en = tris.reshape(-1, 2)
        y = roof_height(en)
        pos = np.column_stack([en[:, 0], y, -en[:, 1]]).reshape(-1, 3, 3)
        # uv: meters along the eave, meters up the slope (shingle rows).
        u, v = local(en)
        down_u, down_v = down
        across_eave = u * down_v - v * down_u
        up_slope = (half_w - (u * down_u + v * down_v)) / np.cos(pitch)
        uv = np.column_stack([across_eave, up_slope]).reshape(-1, 3, 2)
        d = down_u * along + down_v * across  # downhill, east/north
        normal = np.array([d[0] * np.sin(pitch), np.cos(pitch),
                           -d[1] * np.sin(pitch)])
        builder.add(pos, uv, roof_uv2, normal / np.linalg.norm(normal))

    # Walls up to the roof, with corners where they pass under a ridge or hip.
    ring = shapely.LineString(np.asarray(poly.exterior.coords)[:, :2])
    lines = shapely.MultiLineString([world(np.array(b)) for b in breaks])
    cuts = shapely.get_coordinates(shapely.intersection(ring, lines))
    distances = np.concatenate([
        shapely.line_locate_point(ring, shapely.points(np.asarray(ring.coords))),
        shapely.line_locate_point(ring, shapely.points(cuts)) if len(cuts) else np.zeros(0)])
    distances[len(ring.coords) - 1] = ring.length  # the closing point
    distances = np.unique(np.round(distances, 3))
    coords = shapely.get_coordinates(shapely.line_interpolate_point(ring, distances))
    uv2 = _wall_uv2(coords, facade, True)
    builder.add_walls(coords, ground - 1.0, roof_height(coords), uv2, ground_y=ground,
                      restart=_sign_faces(coords, uv2))
    return True


def _footprint_ground(geom) -> float:
    """Where a building stands: the ground at its lowest corner."""
    ring = shapely.get_coordinates(shapely.get_exterior_ring(shapely.get_parts(geom)))
    return float(overpasses.bare(_W["ground"][_W["level"]]).height(ring).min())


def _add_building(builder: MeshBuilder, index: int, settings: dict) -> None:
    b = _W["b"]
    # Its sign walls' part (times_square.py: One Times Square's screens go to the top).
    _W["sign_part"] = times_square.sign_part(int(b["bin"][index]))
    # Towers newer than the 3-D model have their massing from a table (towers.py).
    if towers.has(int(b["bin"][index])):
        towers.add(builder, index, _W, settings, _footprint_ground, _faces_street, _add_shape)
        return
    height = float(b["height"][index])
    shape = _W["shapes"].get(int(b["bin"][index])) if height >= settings["shapes_from"] else None
    # Houses get pitched roofs instead (the 3-D model's roofs are flat levels).
    if settings.get("roofs") and _W["facades"]["archetype"][index] == facades.HOUSE:
        shape = None
    if shape is not None and not _shape_matches(shape, b["geoms"][index], height):
        shape = None
    facade = _facade(index)
    if settings.get("roofs"):  # stoops on rowhouse and walk-up fronts (fronts.py)
        facade = fronts.add(builder, index, facade, shape, _W, settings, _faces_street)
    if shape is not None:
        _add_shape(builder, shape, _footprint_ground(b["geoms"][index]), facade)
        return
    geom = shapely.simplify(b["geoms"][index], settings["building_tolerance"], preserve_topology=True)
    roofs = settings.get("roofs", False)
    for poly in polygons_of(geom, settings["min_area"]):
        if not settings["keep_holes"]:
            poly = Polygon(poly.exterior)
        if roofs and facade[0] == facades.HOUSE:
            if not _add_pitched(builder, poly, height, facade):
                _add_prism(builder, poly, height, facade)
        else:
            _add_prism(builder, poly, height, facade, parapet=roofs)


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
    return model_height - height >= -max(meters, fraction * height)


def _add_shape(builder: MeshBuilder, shape, ground: float, facade: tuple) -> None:
    """A building from the 3-D model, moved to stand on our ground at `ground`.
    Walls get facade coordinates (meters along the wall, meters above the
    ground) and are marked FRONT if they face a street; roofs are marked ROOF."""
    archetype, flags, floor_dm, seed = facade
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
            uv2 = facades.encode(archetype, flags | facades.ROOF, floor_dm, seed)
        else:
            along = np.array([-normal[1], normal[0]])
            length = np.linalg.norm(along)
            along = along / length if length > 1e-6 else np.array([1.0, 0.0])
            uv = np.stack([tris[..., 0] * along[0] + tris[..., 1] * along[1], tris[..., 2] - ground], axis=-1)
            wall_flags = flags
            if length > 1e-6:
                middle = rings[0][:, :2].mean(axis=0)
                outward = (normal[:2] / length)[None]
                if _faces_street(middle[None], outward)[0] or times_square.faces_plaza(_W, middle[None], outward)[0]:
                    wall_flags |= facades.FRONT
                    if props.in_sign_district(middle[None])[0]:
                        wall_flags |= facades.SIGNS | _W.get("sign_part", 0) * facades.FRONT_PART
                        # Wide sign walls measure from their left corner (see SIGN_FACE_MIN).
                        span = rings[0][:, :2] @ along
                        if span.max() - span.min() >= SIGN_FACE_MIN:
                            uv[..., 0] -= span.min()
            uv2 = facades.encode(archetype, wall_flags, floor_dm, seed)
        pos = np.stack([tris[..., 0], tris[..., 2], -tris[..., 1]], axis=-1)
        builder.add(pos, uv, uv2, (normal[0], normal[2], -normal[1]))


def _add_blocks(builder: MeshBuilder, indices: np.ndarray, settings: dict) -> None:
    """Tall buildings one by one; everything lower merged into simple blocks."""
    if len(indices) == 0:
        return
    blocks = settings["blocks"]
    b = _W["b"]
    heights = towers.heights(b["bin"][indices], b["height"][indices])
    for index in indices[heights >= blocks["individual_from"]]:
        _add_building(builder, index, settings)
    gap = blocks["merge_gap"]
    archetypes = _W["facades"]["archetype"]
    for low, high, block_height in blocks["bands"]:
        band = indices[(heights >= low) & (heights < high)]
        if len(band) == 0:
            continue
        band_tree = shapely.STRtree(b["geoms"][band])
        grown = shapely.buffer(b["geoms"][band], gap, join_style="mitre")
        try:
            merged = shapely.union_all(grown)
        except shapely.errors.GEOSException:
            merged = shapely.union_all(shapely.set_precision(grown, 0.01))  # see _add_ground
        merged = shapely.buffer(merged, -gap, join_style="mitre")
        merged = shapely.simplify(merged, blocks["tolerance"], preserve_topology=True)
        for poly in polygons_of(merged, blocks["min_area"]):
            center = poly.centroid
            seed = float((hash((round(center.x), round(center.y))) % 1000) / 1000.0)
            # The block looks like most of the buildings in it (by area).
            members = band[band_tree.query(poly, predicate="intersects")]
            block_flags = 0
            if len(members):
                areas = shapely.area(b["geoms"][members])
                votes = np.bincount(archetypes[members], weights=areas, minlength=16)
                archetype = int(np.argmax(votes))
                # ... and their wall material.
                block_flags = facades.block_flags(archetypes[members], _W["facades"]["flags"][members], areas, archetype)
            else:
                archetype = facades.UNKNOWN
            floor_dm = int(round(np.clip(block_height / max(1, round(block_height / facades.DEFAULT_FLOOR)),
                                         facades.MIN_FLOOR, facades.MAX_FLOOR) * 10))
            _add_prism(builder, Polygon(poly.exterior), block_height, (archetype, block_flags, floor_dm, seed),
                       fronts=False)


def _add_ground(builder: MeshBuilder, bounds, settings: dict) -> None:
    try:
        layers = _ground_layers(bounds, settings, grid=0.0)
    except shapely.errors.GEOSException:
        # GEOS overlays occasionally fail on nearly-coincident edges; snapping
        # everything to a 1 cm grid first gets them through.
        layers = _ground_layers(bounds, settings, grid=0.01)
    ground = overpasses.bare(_W["ground"][_W["level"]])
    cell = settings["ground_cell"]
    for kind, geom in layers:
        geom = shapely.simplify(geom, settings["ground_tolerance"], preserve_topology=True)
        polys = polygons_of(geom, min_area=settings["min_ground_area"])
        if kind == GROUND_ROAD and settings.get("curbs"):
            _W["tile_roads"] = [shapely.orient_polygons(p) for p in polys]  # for street lights
        # Cut away under the triple cantilever, and the rest (cantilever.Ground).
        for terrain, part_polys in ground.regions(polys):
            if kind == GROUND_SHRUBS:  # planted medians (ground_details.py)
                _W["details"].add_beds(builder, part_polys, cell, terrain)
                continue
            height = terrain.height
            if kind == GROUND_ROAD and settings.get("curbs"):
                def height(en, terrain=terrain):
                    return terrain.height(en) - CURB_HEIGHT
                _add_curbs(builder, part_polys, bounds, cell, terrain)
            # Belgian block and plaza pavers where streets are drawn (ground_details.py).
            parts = _W["details"].paving(kind, part_polys) if settings["roads"] else [((kind, 0.0), part_polys)]
            for uv2, part in parts:
                builder.add_draped(part, cell, height, uv2, terrain.normal)

    # Walls where the ground is cut away under the triple cantilever (cantilever.Ground).
    for coords, bottom, top in ground.walls(bounds):
        builder.add_walls(coords, bottom, top, (STRUCTURE_CONCRETE, 0.0))

    # Walls where the land meets water: down into the sea, or into a raised
    # lake's bed.
    coast_t = shapely.clip_by_rect(_W["coast"], *bounds.bounds)
    if coast_t.geom_type == "MultiLineString":
        coast_t = shapely.line_merge(coast_t)
    coast_t = shapely.simplify(coast_t, settings["ground_tolerance"])
    for line in lines_of(coast_t):
        coords = np.asarray(shapely.segmentize(line, cell).coords)[:, :2]
        builder.add_walls(coords, _shore_wall_bottom(coords), ground.height(coords), (GROUND_SEAWALL, 0.0))


def _add_curbs(builder: MeshBuilder, roads: list, bounds, cell: float, terrain) -> None:
    """Curb faces along every road edge (except where the tile cuts the road),
    facing the road. Medians are left out of the road data, so they become
    raised islands with curbs too."""
    tile_edge = shapely.buffer(bounds.boundary, 0.01)
    for poly in roads:
        poly = shapely.orient_polygons(poly)
        for ring in (poly.exterior, *poly.interiors):
            # Reversed, the right side of travel (the wall's face) is the road.
            edge = shapely.LineString(np.asarray(ring.coords)[::-1])
            for line in lines_of(shapely.difference(edge, tile_edge)):
                coords = np.asarray(shapely.segmentize(line, cell).coords)[:, :2]
                top = terrain.height(coords)
                builder.add_walls(coords, top - CURB_HEIGHT - 0.05, top, (STRUCTURE_CONCRETE, 0.0))


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
    """The tile's land split into [(kind, geometry)]: pavement, roads, parks, sand,
    marsh and yards (only where streets are drawn, so yards can tell sidewalks apart).

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
            roads_t = shapely.union_all(snap(nearby))
            # Close hairline gaps between neighboring road pieces, which would
            # otherwise get curbs across the street.
            roads_t = shapely.buffer(shapely.buffer(roads_t, ROAD_GAP, join_style="mitre"), -ROAD_GAP, join_style="mitre")
            roads_t = _polygonal(shapely.intersection(roads_t, land_t))
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
    yards_t = _yards(bounds, pavement_t, roads_t) if settings["roads"] else Polygon()
    pavement_t = shapely.difference(pavement_t, yards_t)
    layers = [(GROUND_PAVEMENT, pavement_t), (GROUND_ROAD, roads_t), (GROUND_PARK, parks_t),
              (GROUND_SAND, sand_t), (GROUND_MARSH, marsh_t), (GROUND_YARD, yards_t)]
    # Parks the parks layer lacks, and planted medians (ground_details.py).
    return _W["details"].layers(layers, bounds, clip, medians=settings["roads"], beds=settings.get("curbs", False))


def _yards(bounds, pavement, roads):
    """The part of the paved ground that's yards (see YARD_REACH)."""
    if pavement.is_empty:
        return Polygon()
    near = _W["building_index_tree"].query(shapely.buffer(bounds, YARD_REACH, join_style="mitre"))
    homes = near[np.isin(_W["facades"]["archetype"][near], HOMES)]
    if len(homes) == 0:
        return Polygon()
    zone = shapely.buffer(shapely.union_all(_W["b"]["geoms"][homes]), YARD_REACH, quad_segs=2)
    if not roads.is_empty:
        zone = shapely.difference(zone, shapely.buffer(roads, SIDEWALK_WIDTH, quad_segs=2))
    return _polygonal(shapely.intersection(pavement, zone))


def _polygonal(geom):
    """Only the polygon parts of a geometry (overlays can leave stray lines and
    points, which make later overlays fail), as a MultiPolygon or empty Polygon."""
    parts = polygons_of(geom, min_area=0.0)
    return shapely.MultiPolygon(parts) if parts else Polygon()


def _add_markings(builder: MeshBuilder, bounds) -> None:
    """Paint on the tile's streets (markings.py), draped over the road, and on
    raised roads' decks (overpasses.py)."""
    overpasses.add_paint(builder, _W["overpasses"], _W["bridges"]["lod0"], bounds, LEVELS["lod0"]["ground_cell"],
                         _W["g"]["land"])
    segments = _W["centerline_tree"].query(shapely.buffer(bounds, MARKING_REACH, join_style="mitre"))
    if not len(segments) or _W["streets"].is_empty:
        return
    terrain = _W["ground"]["lod0"]

    def height(en):
        return terrain.height(en) - CURB_HEIGHT + MARKING_LIFT
    halves = [[0, 1, 2], [0, 2, 3]]
    for kind, (quads, uv, check) in markings.quads(_W["centerline"], segments, bounds.bounds, _W["streets"]).items():
        ok = ~check
        ok[check] = markings.keep(quads[check], _W["streets"])
        triangles = quads[ok][:, halves].reshape(-1, 3, 2)
        builder.add_draped_triangles(triangles, LEVELS["lod0"]["ground_cell"], height, (kind, 0.0),
                                     uv=uv[ok][:, halves].reshape(-1, 3, 2))


def _build_props(i: int, j: int, bounds, indices: np.ndarray, origin):
    """The tile's props surface (see common.py) and counts, or (None, {})."""
    street = _street_trees(i, j)
    canopy = _canopy_trees(i, j, bounds, street["en"])
    towers = _water_towers(indices)
    lamps = _street_lights(i, j, bounds)
    furniture = _furniture(i, j, bounds)
    cars = _parked_cars(bounds)
    parts = [street, canopy, towers, lamps, furniture, cars]
    en = np.concatenate([p["en"] for p in parts])
    if len(en) == 0:
        return None, {}
    trees = len(street["en"]) + len(canopy["en"])
    ground = _W["ground"]["lod0"]
    y = np.concatenate([ground.height(street["en"]), ground.height(canopy["en"]), towers["y"], lamps["y"],
                        furniture["y"], cars["y"]])
    seed = np.concatenate([p["seed"] for p in parts])
    # Trees and towers face any way; lamps reach over the street.
    yaw = np.concatenate([p["yaw"] if "yaw" in p else props.location_seed(p["en"] * 3.7) * (2 * np.pi)
                          for p in parts])
    positions = np.round(to_godot(en, y) - np.asarray(origin), 2).astype(np.float32)
    normals = np.column_stack([np.concatenate([p["height"] for p in parts]),
                               np.concatenate([p["width"] for p in parts]), yaw])
    uv = np.column_stack([np.concatenate([p["tone"] for p in parts]), np.concatenate([p["trunk"] for p in parts])])
    kinds = np.concatenate([p["type"] for p in parts])
    # Centimeters, except signals' phases (exact 1024ths, see markings.prepare).
    uv = np.where((kinds == PROP_TRAFFIC_SIGNAL)[:, None], uv, np.round(uv, 2))
    uv2 = np.column_stack([kinds, np.minimum(np.round(seed, 3), 0.999)])
    # Nothing stands up through a deck overhead (overpasses.py), or in an el's columns (els.py).
    keep = overpasses.clear_of_decks(_W["bridges"]["lod0"], bounds, en, y, normals[:, 0])
    keep &= els.clear_of_columns(_W["bridges"].get("el_columns", {}), i, j, en, kinds == PROP_PARKED_CAR)
    order = np.flatnonzero(keep)[np.argsort(kinds[keep], kind="stable")]  # grouped by type, for the game
    surface = (positions[order], np.round(normals, 2).astype(np.float32)[order],
               uv.astype(np.float32)[order], uv2.astype(np.float32)[order], np.zeros(0, dtype=np.uint32))
    return surface, {"props": len(en), "trees": trees, "water_towers": len(towers["en"]),
                     "street_lights": len(lamps["en"]), "furniture": len(furniture["en"]),
                     "parked_cars": len(cars["en"])}


def _furniture(i: int, j: int, bounds) -> dict:
    """The city's street furniture in the tile (props.prepare_furniture), on
    the sidewalk and facing the street, plus traffic signals."""
    parts = []
    idx = _W["furniture_groups"].get((i, j))
    if idx is not None:
        f = _W["furniture"]
        found = {key: f[key][idx] for key in ("en", "type", "tone", "height", "width", "seed")}
        en, keep = _onto_sidewalk(found["en"])
        found["en"] = en
        found = {key: value[keep] for key, value in found.items()}
        curbside = np.flatnonzero(np.isin(found["type"], CURBSIDE_TYPES))
        found["en"][curbside] = _to_curb(found["en"][curbside])
        found["yaw"] = _toward_street(found["en"], found["seed"])
        found["trunk"] = np.zeros(len(found["en"]))
        parts.append(found)
    if not _W["streets"].is_empty:
        segments = _W["centerline_tree"].query(shapely.buffer(bounds, MARKING_REACH, join_style="mitre"))
        points, facing, phases = markings.signals(_W["centerline"], segments, bounds.bounds, _W["streets"])
        if len(points):
            ok = _on_open_ground(points) & ~shapely.contains_xy(_W["streets"], points[:, 0], points[:, 1])
            points, facing, phases = points[ok], facing[ok], phases[ok]
            height, width = props.TRAFFIC_SIGNAL_SIZE
            parts.append({"en": points, "type": np.full(len(points), PROP_TRAFFIC_SIGNAL, dtype=np.int8),
                          "tone": np.zeros(len(points), dtype=np.int8), "height": np.full(len(points), height),
                          "width": np.full(len(points), width), "seed": props.location_seed(points),
                          "yaw": np.arctan2(facing[:, 0], -facing[:, 1]), "trunk": phases})
    if not parts:
        return _no_props()
    out = {key: np.concatenate([p[key] for p in parts]) for key in parts[0]}
    out["y"] = _W["ground"]["lod0"].height(out["en"])
    return out


def _parked_cars(bounds) -> dict:
    """Parked cars at the tile's curbs (traffic.parked_cars), on the road."""
    if _W["streets"].is_empty:
        return _no_props()
    segments = _W["centerline_tree"].query(shapely.buffer(bounds, MARKING_REACH, join_style="mitre"))
    cars = traffic.parked_cars(_W["centerline"], segments, bounds, _W["streets"], _W["car_blockers"])
    if len(cars["en"]) == 0:
        return _no_props()
    return {"en": cars["en"], "type": np.full(len(cars["en"]), PROP_PARKED_CAR, dtype=np.int8),
            "tone": cars["model"], "trunk": cars["paint"], "height": cars["height"], "width": cars["length"],
            "seed": cars["seed"], "yaw": cars["yaw"],
            "y": _W["ground"]["lod0"].height(cars["en"]) - CURB_HEIGHT}


def _build_traffic(bounds, origin):
    """The tile's driving lanes surface (traffic.lanes; see common.SURFACE_TRAFFIC),
    or None."""
    segments = _W["centerline_tree"].query(shapely.buffer(bounds, 1.0, join_style="mitre"))
    terrain = _W["ground"]["lod0"]
    found = traffic.lanes(_W["centerline"], segments, bounds, lambda en: terrain.height(en) - CURB_HEIGHT)
    found += overpasses.lanes(_W["overpasses"], _W["bridges"]["lod0"], bounds, _W["g"]["land"])
    if not found:
        return None
    points, normals, uv, uv2, indices = [], [], [], [], []
    for lane, (from_node, to_node, speed, number, count, phase, crossing) in found:
        start = sum(len(p) for p in points)
        points.append(to_godot(lane[:, :2], lane[:, 2]) - np.asarray(origin))
        n = len(lane)
        normals.append(np.tile([from_node, to_node, speed], (n, 1)))
        uv.append(np.tile([number, count], (n, 1)))
        uv2.append(np.tile([phase, crossing], (n, 1)))
        indices.extend(range(start, start + n))
        indices.append(LANE_BREAK)
    return (np.round(np.concatenate(points), 2).astype(np.float32), np.concatenate(normals).astype(np.float32),
            np.concatenate(uv).astype(np.float32), np.concatenate(uv2).astype(np.float32),
            np.asarray(indices, dtype=np.uint32))


def _onto_sidewalk(en: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Points the data puts in the road (it and the road outlines disagree by
    a meter or two) moved TREE_CURB_GAP onto the sidewalk; and which points
    to keep (not too far in the road, on land, not in a building)."""
    en = en.copy()
    keep = np.ones(len(en), dtype=bool)
    streets = _W["streets"]
    if not streets.is_empty and len(en):
        in_road = np.flatnonzero(shapely.contains_xy(streets, en[:, 0], en[:, 1]))
        if len(in_road):
            lines = shapely.shortest_line(shapely.points(en[in_road]), shapely.boundary(streets))
            ends = shapely.get_coordinates(shapely.get_point(lines, 1))
            step = ends - en[in_road]
            moved = np.linalg.norm(step, axis=1)
            en[in_road] = ends + step / np.maximum(moved, 1e-6)[:, None] * TREE_CURB_GAP
            keep[in_road[moved > TREE_MAX_MOVE]] = False
    if len(en):
        keep &= _on_open_ground(en)
    return en, keep


def _to_curb(en: np.ndarray) -> np.ndarray:
    """Points within CURBSIDE_REACH of a curb moved to CURBSIDE_GAP from it."""
    streets = _W["streets"]
    if streets.is_empty or len(en) == 0:
        return en
    lines = shapely.shortest_line(shapely.points(en), shapely.boundary(streets))
    curb = shapely.get_coordinates(shapely.get_point(lines, 1))
    away = en - curb
    distance = np.linalg.norm(away, axis=1)
    move = (distance > CURBSIDE_GAP) & (distance < CURBSIDE_REACH)
    out = en.copy()
    out[move] = curb[move] + away[move] / distance[move, None] * CURBSIDE_GAP
    return out


def _toward_street(en: np.ndarray, seed: np.ndarray) -> np.ndarray:
    """Yaws (see common.PROP_*) facing each point's nearest street; random
    where no street is near."""
    yaw = seed * (2 * np.pi)
    streets = _W["streets"]
    if streets.is_empty or len(en) == 0:
        return yaw
    lines = shapely.shortest_line(shapely.points(en), shapely.boundary(streets))
    step = shapely.get_coordinates(shapely.get_point(lines, 1)) - en
    near = np.linalg.norm(step, axis=1) > 1e-3
    yaw[near] = np.arctan2(step[near, 0], -step[near, 1])
    return yaw


def _street_lights(i: int, j: int, bounds) -> dict:
    """The tile's lamps: along its curbs (props.lamp_spots), on bridge decks,
    and on park paths; each with its base height in "y"."""
    parts = [_curb_lamps(bounds), _deck_lamps(i, j), _path_lamps(bounds)]
    parts = [p for p in parts if len(p["en"])]
    if not parts:
        return _no_props()
    return {key: np.concatenate([p[key] for p in parts]) for key in parts[0]}


def _curb_lamps(bounds) -> dict:
    roads = _W.pop("tile_roads", [])
    if not roads:
        return _no_props()
    points, arms = props.lamp_spots(roads, shapely.buffer(bounds.boundary, 0.01))
    if len(points) == 0:
        return _no_props()
    keep = _on_open_ground(points)
    if not _W["streets"].is_empty:
        keep &= ~shapely.contains_xy(_W["streets"], points[:, 0], points[:, 1])
    points, arms = points[keep], arms[keep]
    near_park = np.zeros(len(points), dtype=bool)
    hits = _W["park_tree"].query(shapely.points(points), predicate="dwithin", distance=props.LAMP_PARK_REACH)
    near_park[hits[0]] = True
    # Other parks', and historic boulevards' (ground_details.py).
    near_park |= _W["details"].near_lamp_park(points, props.LAMP_PARK_REACH)
    near_park |= _W["details"].historic_lamps(points, arms)
    found = props.lamps(points, arms, near_park)
    found["y"] = _W["ground"]["lod0"].height(points)
    return found


def _deck_lamps(i: int, j: int) -> dict:
    """Cobra-heads along bridge decks, and the hand-made bridges' historic
    lamps (bridges.build's "post_lamps")."""
    parts = []
    for key, post_top in (("lamps", False), ("post_lamps", True)):
        deck = _W["bridges"].get(key, {}).get((i, j))
        if deck is None or len(deck[0]) == 0:
            continue
        points, heights, arms = deck
        found = props.lamps(points, arms, np.full(len(points), post_top))
        found["y"] = heights
        parts.append(found)
    if not parts:
        return _no_props()
    return {key: np.concatenate([p[key] for p in parts]) for key in parts[0]}


def _path_lamps(bounds) -> dict:
    """Post-tops where a try per PATH_LAMP_SPACING cell lands on paving in a
    park, away from streets (which have their own lamps) and buildings."""
    parks = np.concatenate([_W["g"]["parks"][_W["park_tree"].query(bounds)], _W["details"].lamp_parks_near(bounds)])
    if not len(parks):
        return _no_props()
    min_e, min_n, max_e, max_n = bounds.bounds
    s = props.PATH_LAMP_TRY
    ii, jj = np.meshgrid(np.arange(np.floor(min_e / s), np.ceil(max_e / s)),
                         np.arange(np.floor(min_n / s), np.ceil(max_n / s)))
    seed = props.location_seed(np.column_stack([ii.ravel(), jj.ravel()]) * 7.0)
    en = (np.column_stack([ii.ravel(), jj.ravel()]) + 0.15 + 0.7 * np.column_stack(
        [seed, props.location_seed(np.column_stack([jj.ravel(), ii.ravel()]) * 5.0)])) * s
    inside = (en[:, 0] >= min_e) & (en[:, 0] < max_e) & (en[:, 1] >= min_n) & (en[:, 1] < max_n)
    en = en[inside]
    en = en[_W["landcover"].classes(en) == landcover.PAVED]
    if len(en) == 0:
        return _no_props()
    park = shapely.union_all(parks)
    shapely.prepare(park)
    en = en[shapely.contains_xy(park, en[:, 0], en[:, 1])]
    if len(en) == 0:
        return _no_props()
    keep = _on_open_ground(en)
    if not _W["streets"].is_empty:
        keep &= ~shapely.dwithin(_W["streets"], shapely.points(en), props.PATH_LAMP_STREET_GAP)
    en = en[keep]
    en = en[props.spread(en, props.PATH_LAMP_GAP)]
    found = props.lamps(en, np.tile([1.0, 0.0], (len(en), 1)), np.ones(len(en), dtype=bool))
    found["y"] = _W["ground"]["lod0"].height(en)
    return found


def _no_props() -> dict:
    return {"en": np.zeros((0, 2)), "height": np.zeros(0), "width": np.zeros(0), "trunk": np.zeros(0),
            "type": np.zeros(0, np.int8), "tone": np.zeros(0, np.int8), "seed": np.zeros(0), "y": np.zeros(0),
            "yaw": np.zeros(0)}


def _on_open_ground(en: np.ndarray) -> np.ndarray:
    """Which (N, 2) points are on land and not inside a building (or the
    triple cantilever, but for its Promenade)."""
    ok = shapely.contains_xy(_W["g"]["land"], en[:, 0], en[:, 1])
    hits = _W["building_tree"].query(shapely.points(en), predicate="within")
    ok[hits[0]] = False
    ok &= ~_W["structure"].inside(en)
    return ok


def _street_trees(i: int, j: int) -> dict:
    """The inventory's street trees in the tile, moved out of the road where
    the data puts them in it."""
    idx = _W["tree_groups"].get((i, j))
    if idx is None:
        return _no_props()
    t = _W["trees"]
    found = {key: t[key][idx] for key in ("en", "height", "width", "trunk", "type", "tone", "seed")}
    en = found["en"].copy()
    streets = _W["streets"]
    keep = np.ones(len(en), dtype=bool)
    if not streets.is_empty:
        in_road = np.flatnonzero(shapely.contains_xy(streets, en[:, 0], en[:, 1]))
        if len(in_road):
            lines = shapely.shortest_line(shapely.points(en[in_road]), shapely.boundary(streets))
            ends = shapely.get_coordinates(shapely.get_point(lines, 1))
            step = ends - en[in_road]
            moved = np.linalg.norm(step, axis=1)
            en[in_road] = ends + step / np.maximum(moved, 1e-6)[:, None] * TREE_CURB_GAP
            keep[in_road[moved > TREE_MAX_MOVE]] = False
    found["en"] = en
    keep &= _on_open_ground(en)
    # Small trees on planted medians (ground_details.py).
    return _W["details"].median_trees({key: value[keep] for key, value in found.items()})


def _canopy_trees(i: int, j: int, bounds, street_en: np.ndarray) -> dict:
    """Trees wherever the land cover map shows canopy, off the streets and
    away from street trees."""
    en, seed = props.canopy_candidates(bounds.bounds)
    cover = _W["landcover"]
    on = cover.is_canopy(en)
    en, seed = en[on], seed[on]
    if len(en) == 0:
        return _no_props()
    keep = _on_open_ground(en)
    if not _W["streets"].is_empty:
        keep &= ~shapely.contains_xy(_W["streets"], en[:, 0], en[:, 1])
    # Canopy over narrow medians is their street trees' (ground_details.py).
    keep &= ~_W["details"].on_narrow_median(en)
    # Street trees in this tile (as placed) and the ones around it.
    near = [street_en] + [_W["trees"]["en"][idx] for di in (-1, 0, 1) for dj in (-1, 0, 1)
                          if (di or dj) and (idx := _W["tree_groups"].get((i + di, j + dj))) is not None]
    near = np.concatenate(near)
    if len(near):
        hits = shapely.STRtree(shapely.points(near)).query(shapely.points(en), predicate="dwithin",
                                                            distance=CANOPY_CLEARANCE)
        keep[hits[0]] = False
    en, seed = en[keep], seed[keep]
    return props.canopy_trees(en, seed, cover.canopy_share(en, CANOPY_REACH))


def _water_towers(indices: np.ndarray) -> dict:
    """Rooftop water tanks on the tile's buildings that get one (props.py)."""
    if len(indices) == 0:
        return _no_props()
    b, f = _W["b"], _W["facades"]
    height = b["height"][indices].astype(np.float64)
    floors = height / np.maximum(f["floor_dm"][indices] / 10.0, 1.0)
    borough = b["bbl"][indices] // 1_000_000_000
    found = defaultdict(list)
    found_mask = props.tower_mask(f["archetype"][indices], floors, height, borough, b["seed"][indices])
    for k in np.flatnonzero(found_mask & ~towers.mask(b["bin"][indices])):
        index = int(indices[k])
        parts = polygons_of(b["geoms"][index], 20.0)
        if not parts:
            continue
        poly = shapely.simplify(max(parts, key=lambda p: p.area), 0.3)
        seed = float(b["seed"][index])
        tower_height, diameter, variant = props.tower_sizes(poly.area, seed)
        ground = _footprint_ground(b["geoms"][index])
        shape = _W["shapes"].get(int(b["bin"][index]))
        if shape is not None and not _shape_matches(shape, b["geoms"][index], float(height[k])):
            shape = None
        for n, spot in enumerate(props.tower_spots(poly, _W["streets"], diameter, seed)):
            roof = _shape_roof_at(shape, ground, spot) if shape is not None else None
            found["en"].append(spot)
            found["y"].append(roof if roof is not None else ground + float(height[k]))
            found["height"].append(tower_height)
            found["width"].append(diameter)
            found["tone"].append(variant)
            found["seed"].append((seed + 0.37 * n) % 1.0)
    if not found:
        return _no_props()
    out = {key: np.asarray(value, np.float64) for key, value in found.items()}
    out["en"] = out["en"].reshape(-1, 2)
    out["trunk"] = np.zeros(len(out["en"]))
    out["type"] = np.full(len(out["en"]), PROP_WATER_TOWER, dtype=np.int8)
    return out


def _shape_roof_at(shape, ground: float, en: np.ndarray) -> float | None:
    """The highest roof of a 3-D model building over a point (moved to stand
    at `ground`, like _add_shape), or None if no roof covers it."""
    vertices, offsets, ring_polygon, kinds, model_ground = shape
    starts = np.searchsorted(ring_polygon, np.arange(len(kinds)))
    best = None
    for polygon in np.flatnonzero(np.asarray(kinds) == buildings3d.ROOF):
        outline = vertices[offsets[starts[polygon]]:offsets[starts[polygon] + 1]].astype(np.float64)
        if len(outline) < 3 or not shapely.contains_xy(Polygon(outline[:, :2]), en[0], en[1]):
            continue
        normal = polygon_normal(outline)
        if abs(normal[2]) < 1e-3:
            continue
        z = (normal @ outline[0] - normal[0] * en[0] - normal[1] * en[1]) / normal[2]
        best = z if best is None else max(best, z)
    return None if best is None else float(best + ground - float(model_ground))


def _build_lanes(bounds, origin):
    """Walking lanes along every sidewalk in the tile, LANE_OFFSET in from the curb.

    Returns the lanes surface (positions, normals, uv, uv2, indices), or None.
    """
    g = _W["g"]
    # Look a little past the tile so sidewalks along its edges still find their street.
    area = shapely.buffer(bounds, 4 * LANE_OFFSET, join_style="mitre")
    nearby_roads = g["roads"][_W["road_tree"].query(area)]
    lines = []
    if len(nearby_roads):
        roads_near = shapely.intersection(shapely.union_all(nearby_roads), g["land"])
        nearby_buildings = _W["b"]["geoms"][_W["building_tree"].query(area)]
        sidewalks = shapely.difference(shapely.intersection(g["land"], bounds), roads_near)
        if len(nearby_buildings):
            sidewalks = shapely.difference(sidewalks, shapely.buffer(shapely.union_all(nearby_buildings), LANE_WALL_GAP))
        sidewalks = _W["details"].without_narrow_medians(sidewalks, area)  # nobody walks along medians
        sidewalks = shapely.difference(sidewalks, _W["structure"].closed)  # nor in the triple cantilever
        # Times Square's plazas: around their benches, and lanes across them too.
        sidewalks = shapely.difference(sidewalks, times_square.bench_obstacles(_W, bounds))
        lanes = shapely.intersection(shapely.buffer(roads_near, LANE_OFFSET).boundary, sidewalks)
        plaza_lanes = times_square.plaza_lanes(_W, bounds, sidewalks, roads_near)
        if not plaza_lanes.is_empty:  # (GEOS can't overlay an empty line with a mixed collection)
            lanes = shapely.union(shapely.MultiLineString(lines_of(lanes)), plaza_lanes)
        lines = [line for line in lines_of(lanes) if line.length >= 1.0]
    points, indices = [], []
    for line in lines_of(shapely.line_merge(shapely.MultiLineString(lines))) if lines else []:
        if line.length < MIN_LANE_LENGTH:
            continue
        coords = np.asarray(shapely.segmentize(shapely.simplify(line, 0.5), LANE_STEP).coords)[:, :2]
        start = len(points)
        points.extend(to_godot(coords, _W["ground"]["lod0"].height(coords)) - np.asarray(origin))
        indices.extend(range(start, start + len(coords)))
        indices.append(LANE_BREAK)
    # Times Square's TKTS steps, and bridges' and raised streets' sidewalks (overpasses.py).
    on_decks = overpasses.walks_on_decks(_W["bridges"].get("deck_walks"), _W["deck_walk_tree"], _W["bridges"]["lod0"],
                                         bounds)
    for lane in times_square.step_lanes(_W, bounds, _footprint_ground) + on_decks:
        start = len(points)
        points.extend(to_godot(lane[:, :2], lane[:, 2]) - np.asarray(origin))
        indices.extend(range(start, start + len(lane)))
        indices.append(LANE_BREAK)
    if not points:
        return None
    positions = np.round(np.asarray(points), 2).astype(np.float32)
    zeros2 = np.zeros((len(positions), 2), dtype=np.float32)
    return positions, np.zeros_like(positions), zeros2, zeros2, np.asarray(indices, dtype=np.uint32)


if __name__ == "__main__":
    main()
