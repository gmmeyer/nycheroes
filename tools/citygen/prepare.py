"""Turn the raw GeoJSON downloads (fetch_data.py) into cleaned, projected
geometry for build_tiles.py, cached as pickles in data/cache/.

build_tiles.py runs this automatically when the cache is missing; delete the
cache files after re-downloading to rebuild them.

Usage: python prepare.py
"""

import pickle
import time

import numpy as np
import shapely
from shapely.geometry import shape

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


PREPARERS = {"buildings": prepare_buildings, "ground": prepare_ground}


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
