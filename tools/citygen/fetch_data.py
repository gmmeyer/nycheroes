"""Download the raw data used to build the city tiles (all five boroughs): NYC
Open Data vector datasets, cached as GeoJSON in data/raw/, and the USGS
ground elevation model, cached as GeoTIFFs in data/raw/elevation/. Delete a
file to re-download it.

Usage: python fetch_data.py
"""

import json
import shutil
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw"
API = "https://data.cityofnewyork.us/resource"
PAGE_SIZE = 10000

DATASETS = {
    "boroughs": (
        "gthc-hcne",  # Borough Boundaries, clipped to the shoreline
        {},
    ),
    "parks": (
        "enfh-gkve",  # Parks Properties
        {"$select": "multipolygon,signname,typecategory,subcategory,acres,borough"},
    ),
    "roadbed": (
        "i36f-5ih7",  # Planimetric Database: Roadbed
        {"$select": "the_geom,feat_code,sub_code"},
    ),
    "hydrography": (
        "pjs3-c3z5",  # Planimetric Database: Hydrography (lakes, creeks, beaches, marsh)
        {"$select": "the_geom,name,feat_code"},
    ),
    "hydro_structures": (
        "6hbv-tek4",  # Planimetric Database: Hydrography Structures (piers)
        {"$select": "the_geom,feat_code,sub_code,elevation"},
    ),
    "transport_structures": (
        "r9cu-9r7b",  # Planimetric Database: Transportation Structures (bridges)
        {"$select": "the_geom,name,feat_code,sub_code"},
    ),
    "buildings": (
        "5zhs-2jue",  # Building Footprints
        {"$select": "the_geom,bin,base_bbl,height_roof,ground_elevation,construction_year,feature_code"},
    ),
}


# Bare-earth ground elevation: USGS 3DEP 1/3 arc-second (about 10 m) DEM, in
# meters above NAVD88 (about sea level), as 1x1 degree tiles named by their
# north-west corner. These two cover all five boroughs.
ELEVATION_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/{tile}/USGS_13_{tile}.tif"
ELEVATION_TILES = ["n41w074", "n41w075"]
ELEVATION_DIR = RAW_DIR / "elevation"


def fetch_page(dataset_id: str, params: dict) -> dict:
    url = f"{API}/{dataset_id}.geojson?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": "new-game-citygen/1.0"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return json.load(response)
        except Exception as error:
            if attempt == 5:
                raise
            print(f"  retrying after error: {error}")
            time.sleep(10 * (attempt + 1))
    raise AssertionError("unreachable")


def fetch_dataset(name: str, dataset_id: str, params: dict) -> None:
    out_path = RAW_DIR / f"{name}.geojson"
    if out_path.exists():
        print(f"{name}: cached at {out_path}")
        return

    features = []
    offset = 0
    while True:
        page_params = {**params, "$order": ":id", "$limit": PAGE_SIZE, "$offset": offset}
        page = fetch_page(dataset_id, page_params)
        features.extend(page["features"])
        print(f"{name}: {len(features)} features", flush=True)
        if len(page["features"]) < PAGE_SIZE:
            break
        offset += PAGE_SIZE

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    tmp_path.replace(out_path)


def fetch_elevation(tile: str) -> None:
    out_path = ELEVATION_DIR / f"USGS_13_{tile}.tif"
    if out_path.exists():
        print(f"elevation {tile}: cached at {out_path}")
        return
    ELEVATION_DIR.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(".tmp")
    request = urllib.request.Request(ELEVATION_URL.format(tile=tile), headers={"User-Agent": "new-game-citygen/1.0"})
    for attempt in range(6):
        try:
            print(f"elevation {tile}: downloading...", flush=True)
            with urllib.request.urlopen(request, timeout=300) as response, open(tmp_path, "wb") as f:
                shutil.copyfileobj(response, f, length=1 << 20)
            break
        except Exception as error:
            if attempt == 5:
                raise
            print(f"  retrying after error: {error}")
            time.sleep(10 * (attempt + 1))
    tmp_path.replace(out_path)


def main() -> None:
    for name, (dataset_id, params) in DATASETS.items():
        fetch_dataset(name, dataset_id, params)
    for tile in ELEVATION_TILES:
        fetch_elevation(tile)


if __name__ == "__main__":
    main()
