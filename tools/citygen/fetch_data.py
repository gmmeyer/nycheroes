"""Download the raw NYC Open Data used to build the city tiles (all five boroughs).

Each dataset is cached as GeoJSON in data/raw/. Delete a file to re-download it.

Usage: python fetch_data.py
"""

import json
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


def main() -> None:
    for name, (dataset_id, params) in DATASETS.items():
        fetch_dataset(name, dataset_id, params)


if __name__ == "__main__":
    main()
