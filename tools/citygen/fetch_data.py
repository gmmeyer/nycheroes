"""Download the raw data used to build the city tiles (all five boroughs): NYC
Open Data vector datasets, cached as GeoJSON in data/raw/; tables (the tax
lot database PLUTO, and which tax lot each building is on) as JSON in
data/raw/; the USGS ground elevation model, cached as GeoTIFFs in
data/raw/elevation/; the city's 3-D Building Model (CityGML, 0.9 GB zip)
in data/raw/buildings3d/; and the 2017 land cover map (ERDAS Imagine, 1.3 GB
zip) in data/raw/landcover/, unpacked except for its full-resolution layer. Delete a file to re-download it.

Usage: python fetch_data.py
"""

import json
import shutil
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw"
API = "https://data.cityofnewyork.us/resource"
STATE_API = "https://data.ny.gov/resource"  # New York State's open data (the MTA's)
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
    "trees": (
        "hn5i-inap",  # Forestry Tree Points: the Parks Department's street tree inventory, living trees
        {"$select": "geometry,dbh,genusspecies",
         "$where": "tpstructure='Full' AND (tpcondition IS NULL OR tpcondition!='Dead')"},
    ),
    "centerline": (
        "inkn-q76z",  # Centerline (CSCL): street centerlines with lanes and traffic direction
        {"$select": "the_geom,physicalid,rw_type,status,trafdir,from_level_code,to_level_code,"
                    "streetwidth,number_travel_lanes,number_park_lanes,bike_lane"},
    ),
}


# Bare-earth ground elevation: USGS 3DEP 1/3 arc-second (about 10 m) DEM, in
# meters above NAVD88 (about sea level), as 1x1 degree tiles named by their
# north-west corner. These two cover all five boroughs.
ELEVATION_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/{tile}/USGS_13_{tile}.tif"
ELEVATION_TILES = ["n41w074", "n41w075"]
ELEVATION_DIR = RAW_DIR / "elevation"

# Real building shapes: NYC 3-D Building Model (Office of Technology and
# Innovation, dataset tnru-abg2), LoD2 CityGML in 20 delivery areas.
BUILDING_MODEL_URL = "https://s-media.nyc.gov/agencies/oti/DA_WISE_GML.zip"
BUILDING_MODEL_PATH = RAW_DIR / "buildings3d" / "DA_WISE_GML.zip"

# What covers the ground, from the 2017 LiDAR: tree canopy, grass, bare soil,
# water, buildings, roads, other paved, railroads (dataset he6d-2qns, 6-inch
# pixels, in a 1.3 GB zip). landcover.py reads its reduced-resolution layers,
# so the full-resolution one (the .ige file, 98 GB unpacked) stays zipped.
LAND_COVER_URL = ("https://data.cityofnewyork.us/api/views/he6d-2qns/files/"
                  "64c49dc7-c17f-43db-a4e3-669a28f73234?download=true&filename=Land_Cover.zip")
LAND_COVER_PATH = RAW_DIR / "landcover" / "Land_Cover.zip"


# Tables without geometry, as JSON rows.
TABLES = {
    "pluto": (
        "64uk-42ks",  # Primary Land Use Tax Lot Output (PLUTO): per tax lot
        {"$select": "bbl,borough,bldgclass,numfloors,yearbuilt,landmark,histdist,"
                    "retailarea,comarea,officearea,resarea,unitsres"},
    ),
    "building_lots": (
        "5zhs-2jue",  # Building Footprints: each building's PLUTO tax lot
        {"$select": "bin,mappluto_bbl"},
    ),
    # Street furniture, as points (props.py).
    "hydrants": ("5bgh-vtsn", {"$select": "latitude,longitude"}),
    "bus_shelters": ("t4f2-8md7", {"$select": "latitude,longitude"}),
    "linknyc": ("s4kf-3yrf", {"$select": "latitude,longitude,planned_kiosk_type",
                              "$where": "link_installation_status='Live'"}),
    "seating": ("esmy-s8q5", {"$select": "latitude,longitude"}),  # benches and leaning bars
    "subway_entrances": ("i9wp-a4ja", {"$select": "entrance_latitude,entrance_longitude,entrance_type,entry_allowed"},
                         STATE_API),
    "bike_racks": ("592z-n7dk", {"$select": "latitude,longitude,racktype"}),
    "litter_baskets": ("8znf-7b2c", {"$select": "latitude,longitude,baskettype"}),
    "parking_meters": ("693u-uax6", {"$select": "lat,long", "$where": "status='Active'"}),
    "newsstands": ("w9zq-xm8b", {"$select": "latitude,longitude"}),
}
TABLE_PAGE_SIZE = 50000


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


def fetch_table(name: str, dataset_id: str, params: dict, api: str = API) -> None:
    out_path = RAW_DIR / f"{name}.json"
    if out_path.exists():
        print(f"{name}: cached at {out_path}")
        return
    rows = []
    while True:
        query = urllib.parse.urlencode({**params, "$order": ":id", "$limit": TABLE_PAGE_SIZE, "$offset": len(rows)})
        request = urllib.request.Request(f"{api}/{dataset_id}.json?{query}", headers={"User-Agent": "new-game-citygen/1.0"})
        for attempt in range(6):
            try:
                with urllib.request.urlopen(request, timeout=300) as response:
                    page = json.load(response)
                break
            except Exception as error:
                if attempt == 5:
                    raise
                print(f"  retrying after error: {error}")
                time.sleep(10 * (attempt + 1))
        rows.extend(page)
        print(f"{name}: {len(rows)} rows", flush=True)
        if len(page) < TABLE_PAGE_SIZE:
            break
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(rows))
    tmp_path.replace(out_path)


def fetch_file(label: str, url: str, out_path: Path) -> None:
    if out_path.exists():
        print(f"{label}: cached at {out_path}")
        return
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(".tmp")
    request = urllib.request.Request(url, headers={"User-Agent": "new-game-citygen/1.0"})
    for attempt in range(6):
        try:
            print(f"{label}: downloading...", flush=True)
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
    for name, (dataset_id, params, *api) in TABLES.items():
        fetch_table(name, dataset_id, params, *api)
    for tile in ELEVATION_TILES:
        fetch_file(f"elevation {tile}", ELEVATION_URL.format(tile=tile), ELEVATION_DIR / f"USGS_13_{tile}.tif")
    fetch_file("3-D building model", BUILDING_MODEL_URL, BUILDING_MODEL_PATH)
    fetch_file("land cover", LAND_COVER_URL, LAND_COVER_PATH)
    unpack_land_cover()


def unpack_land_cover() -> None:
    with zipfile.ZipFile(LAND_COVER_PATH) as z:
        for name in z.namelist():
            target = LAND_COVER_PATH.parent / name
            if name.endswith((".ige", "/")) or target.exists():
                continue
            print(f"land cover: unpacking {name}", flush=True)
            z.extract(name, LAND_COVER_PATH.parent)


if __name__ == "__main__":
    main()
