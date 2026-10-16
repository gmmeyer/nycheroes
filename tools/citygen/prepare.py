"""Turn the raw downloads (fetch_data.py) into cleaned, projected data for
build_tiles.py, cached in data/cache/: geometry as pickles, and the ground
height grid (terrain.py).

build_tiles.py runs this automatically when the cache is missing; delete the
cache files after re-downloading to rebuild them.

Usage: python prepare.py
"""

import pickle
import time

import numpy as np
import shapely
from shapely.geometry import shape

import cantilever
import churches
import els
import facades
import ground_details
import landcover
import lidar
import markings
import overpasses
import poles
import props
import terrain
from common import (CACHE_DIR, FEET, facade_style, load_features, polygons_of, project)

DEFAULT_HEIGHT = 9.0
MIN_HEIGHT = 2.5
# Taller than any building in the city; above this a height is a data error
# (one Bronx footprint claims 2 million feet) and is treated as missing.
MAX_HEIGHT = 600.0
# Skybridges float above the street and placeholders have no height.
SKIPPED_FEATURE_CODES = {"2110", "1003"}
# Park categories that are paved or are buildings, so they aren't drawn as grass.
NON_GREEN_PARK_TYPES = {"Buildings/Institutions", "Triangle/Plaza", "Managed Sites"}

# Planimetric hydrography feature codes.
LAKE_CODES = {"2600", "2610"}  # lakes, reservoirs, ponds
WATERWAY_CODES = {"2620", "2630", "2660"}  # rivers, creeks, bays and open water
MARSH_CODE = "2640"
BEACH_CODE = "2650"
# Planimetric hydrography structures: piers.
PIER_CODES = {"2800"}
# Inland water whose surface is higher than this above sea level gets its own
# water surface (the game's ocean plane is at sea level).
RAISED_WATER_MIN = 2.0
# Water with less spread than this between its high and low points is a lake
# with one level; more, and it's a creek that runs downhill.
FLAT_WATER_SPREAD = 0.6


def prepare_buildings() -> dict:
    feats = [f for f in load_features("buildings")
             if f["properties"].get("feature_code") not in SKIPPED_FEATURE_CODES]
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in feats], dtype=object)))
    keep = ~shapely.is_empty(geoms) & (shapely.area(geoms) > 1.0)
    feats = [f for f, k in zip(feats, keep) if k]
    geoms = geoms[keep]

    heights = np.array([float(f["properties"].get("height_roof") or 0) * FEET for f in feats])
    heights = np.where((heights > 0) & (heights <= MAX_HEIGHT), heights, DEFAULT_HEIGHT)
    heights = np.maximum(heights, MIN_HEIGHT)
    years = np.array([int(f["properties"].get("construction_year") or 0) for f in feats])
    bins = np.array([int(f["properties"].get("bin") or 0) for f in feats], dtype=np.int64)
    bbls = np.array([int(float(f["properties"].get("base_bbl") or 0)) for f in feats], dtype=np.int64)
    return {
        "geoms": geoms,
        "height": heights.astype(np.float32),
        "style": np.array([facade_style(h, y) for h, y in zip(heights, years)], dtype=np.int8),
        "seed": (((bins * 2654435761) % 4294967296) / 4294967296.0).astype(np.float32),
        "bin": bins,
        "bbl": bbls,
        "anchor": shapely.get_coordinates(shapely.point_on_surface(geoms)),
    }


def _union(features, codes=None, key="feat_code"):
    picked = [f for f in features if codes is None or str(f["properties"].get(key)) in codes]
    if not picked:
        return shapely.Polygon()
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in picked], dtype=object)))
    return shapely.union_all(geoms)


def prepare_ground() -> dict:
    land = _union(load_features("boroughs"))
    piers = _union(load_features("hydro_structures"), PIER_CODES)
    hydro = load_features("hydrography")
    water = _union(hydro, LAKE_CODES | WATERWAY_CODES)
    land = shapely.union_all(polygons_of(shapely.difference(shapely.union(land, piers), water), min_area=4.0))

    roads = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in load_features("roadbed")], dtype=object)))
    parks = [f for f in load_features("parks")
             if f["properties"].get("typecategory") not in NON_GREEN_PARK_TYPES]
    parks = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in parks], dtype=object)))
    return {
        "land": land,
        "roads": roads[~shapely.is_empty(roads)],
        "parks": parks[~shapely.is_empty(parks)],
        "beaches": shapely.intersection(_union(hydro, {BEACH_CODE}), land),
        "marsh": shapely.intersection(_union(hydro, {MARSH_CODE}), land),
    }


def prepare_water() -> dict:
    """Inland water above sea level: reservoirs, lakes, ponds and creeks inside
    the shoreline. Each gets a level (meters above sea level), or NaN for
    creeks, whose surface follows the ground model downhill."""
    load_terrain()
    heights = terrain.Terrain()
    water = _union(load_features("hydrography"), LAKE_CODES | WATERWAY_CODES)
    inland = polygons_of(shapely.intersection(water, _union(load_features("boroughs"))), min_area=50.0)
    geoms, levels = [], []
    for poly in inland:
        # Away from the banks, where the model blends in the land around.
        inner = shapely.buffer(poly, -6.0)
        if inner.is_empty:
            inner = poly
        min_e, min_n, max_e, max_n = inner.bounds
        e, n = np.meshgrid(np.arange(min_e, max_e, 10.0), np.arange(min_n, max_n, 10.0))
        points = shapely.points(e.ravel(), n.ravel())
        points = points[shapely.contains(inner, points)]
        if len(points) == 0:
            points = shapely.point_on_surface([poly])
        h = heights.raw(shapely.get_coordinates(points))
        level = float(np.median(h))
        if level < RAISED_WATER_MIN:
            continue
        geoms.append(poly)
        levels.append(level if np.percentile(h, 90) - np.percentile(h, 10) < FLAT_WATER_SPREAD else np.nan)
    return {"geoms": np.array(geoms, dtype=object), "level": np.array(levels)}


def load_terrain() -> None:
    """Builds the ground height grid if it's missing."""
    if not terrain.GRID_PATH.exists():
        terrain.prepare(load("ground")["land"].bounds)


def load_landcover() -> None:
    """Builds the land cover grid if it's missing."""
    if not landcover.GRID_PATH.exists():
        landcover.prepare(load("ground")["land"].bounds)


def prepare_facades() -> dict:
    return facades.prepare(load("buildings"))


def prepare_churches() -> dict:
    return churches.prepare(load("buildings"))


def prepare_deck_heights() -> dict:
    load_terrain()
    return lidar.prepare(load("overpasses"), terrain.Terrain())


def prepare_ground_details() -> dict:
    load_landcover()
    return ground_details.prepare(load("ground")["land"])


PREPARERS = {"buildings": prepare_buildings, "ground": prepare_ground, "water": prepare_water,
             "facades": prepare_facades, "churches": prepare_churches, "trees": props.prepare_trees, "centerline": markings.prepare,
             "furniture": props.prepare_furniture, "overpasses": overpasses.prepare,
             "ground_details": prepare_ground_details, "els": els.prepare,
             "deck_sidewalks": overpasses.prepare_sidewalks, "cantilever": cantilever.prepare,
             "deck_heights": prepare_deck_heights, "shops": props.prepare_shops, "sheds": props.prepare_sheds,
             "bike_docks": props.prepare_bike_docks, "el_stairs": els.prepare_stairs, "poles": poles.prepare}


def load(name: str) -> dict:
    """The prepared dataset `name`, building and caching it if needed."""
    path = CACHE_DIR / f"{name}.pkl"
    if not path.exists():
        started = time.time()
        print(f"preparing {name}...", flush=True)
        data = PREPARERS[name]()
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        with open(tmp, "wb") as f:
            pickle.dump(data, f, protocol=pickle.HIGHEST_PROTOCOL)
        tmp.replace(path)
        print(f"  {name} ready in {time.time() - started:.0f} s", flush=True)
    with open(path, "rb") as f:
        return pickle.load(f)


if __name__ == "__main__":
    for dataset in PREPARERS:
        load(dataset)
    load_terrain()
    load_landcover()
