"""Download the raw NYC Open Data used to build the city tiles.

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

# Manhattan bounding box with a margin, for datasets that have no borough field.
# Socrata's within_box takes (north lat, west lon, south lat, east lon).
MANHATTAN_BOX = "40.882, -74.050, 40.679, -73.905"

DATASETS = {
    "manhattan_buildings": (
        "5zhs-2jue",  # Building Footprints
        {
            "$select": "the_geom,bin,height_roof,ground_elevation,construction_year,feature_code,name",
            "$where": "starts_with(base_bbl,'1')",
        },
    ),
    "boroughs": (
        "gthc-hcne",  # Borough Boundaries, clipped to the shoreline
        {},
    ),
    "manhattan_parks": (
        "enfh-gkve",  # Parks Properties
        {
            "$select": "multipolygon,signname,typecategory,subcategory,acres",
            "$where": "borough='M'",
        },
    ),
    "manhattan_roadbed": (
        "i36f-5ih7",  # Planimetric Database: Roadbed
        {
            "$select": "the_geom,feat_code,sub_code",
            "$where": f"within_box(the_geom, {MANHATTAN_BOX})",
        },
    ),
}


def fetch_page(dataset_id: str, params: dict) -> dict:
    url = f"{API}/{dataset_id}.geojson?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": "new-game-citygen/1.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return json.load(response)
        except Exception as error:
            if attempt == 3:
                raise
            print(f"  retrying after error: {error}")
            time.sleep(5 * (attempt + 1))
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
        print(f"{name}: {len(features)} features")
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
