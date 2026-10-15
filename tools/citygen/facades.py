"""What each building's walls look like: one of a dozen New York building
types (archetypes), its floor height, and a few details (storefronts, fire
escapes, cornices), from the city's tax lot database (PLUTO) joined to the
building footprints by tax lot.

The game's building shader draws them (shaders/building.gdshader). In the
tiles, building surfaces carry, per vertex:
  uv2.x = archetype + FLAG_SCALE * flags   (a whole number in a float)
  uv2.y = floor height in decimeters + the building's random seed (0..0.999)
Flags are per face: ROOF, FRONT (the wall faces a street), PARAPET,
PARAPET_INSIDE and SIGNS are set by build_tiles.py; the rest are per
building, from here.

prepare() makes data/cache/facades.pkl: arrays in the same order as the
prepared buildings (prepare.py).
"""

import json

import numpy as np

from common import RAW_DIR

# Building types, in the order the shader numbers them.
HOUSE = 0             # detached or semi-detached house (Queens, Staten Island)
ROWHOUSE = 1          # rowhouse, brownstone
WALKUP = 2            # prewar walk-up tenement, 4-7 floors
PREWAR_APARTMENT = 3  # prewar elevator apartment building
POSTWAR_APARTMENT = 4  # 1945-1989 apartment slab or tower
MODERN_RESIDENTIAL = 5  # 1990 on, glassy
PREWAR_OFFICE = 6     # masonry office tower, setbacks
MIDCENTURY_OFFICE = 7  # 1945-1984 curtain wall
MODERN_OFFICE = 8     # 1985 on, glass
LOFT = 9              # loft, cast-iron building
STORE = 10            # low-rise shops
INDUSTRIAL = 11       # warehouse, factory, garage
INSTITUTION = 12      # school, hospital, government, church, theater
HOTEL = 13
OTHER = 14            # utility, transportation, misc
UNKNOWN = 15          # no tax lot data

# Flags (bits of uv2.x / FLAG_SCALE).
ROOF = 1          # the face is a roof
FRONT = 2         # the wall faces a street
RETAIL = 4        # shops on the ground floor
FIRE_ESCAPES = 8  # fire escapes on the street front
CORNICE = 16      # a cornice along the top of the walls
LANDMARK = 32     # a designated landmark
PARAPET = 64      # the wall's top PARAPET_HEIGHT stands above its roof
PARAPET_INSIDE = 128  # the face is a parapet's inner side, facing the roof
SIGNS = 256       # a street wall in a sign district (Times Square): billboards
FLAG_SCALE = 64
PARAPET_HEIGHT = 1.0  # meters; the shader has the same constant

DEFAULT_FLOOR = 3.3  # meters, when the floor count isn't known or doesn't fit
MIN_FLOOR, MAX_FLOOR = 2.6, 6.0
PREWAR_YEAR = 1945
MODERN_RESIDENTIAL_YEAR = 1990
MODERN_OFFICE_YEAR = 1985
CORNICE_YEAR = 1940

CACHE_NAME = "facades"


def prepare(buildings: dict) -> dict:
    """Per building (same order as `buildings`): archetype, flags, floor height (dm)."""
    lots = {}
    for row in json.loads((RAW_DIR / "building_lots.json").read_text()):
        if row.get("bin") and row.get("mappluto_bbl"):
            lots[int(float(row["bin"]))] = int(float(row["mappluto_bbl"]))
    pluto = {}
    for row in json.loads((RAW_DIR / "pluto.json").read_text()):
        if row.get("bbl"):
            pluto[int(float(row["bbl"]))] = row

    count = len(buildings["bin"])
    archetype = np.full(count, UNKNOWN, dtype=np.uint8)
    flags = np.zeros(count, dtype=np.uint8)
    floor_dm = np.zeros(count, dtype=np.uint8)
    matched = 0
    for k in range(count):
        bin_number = int(buildings["bin"][k])
        height = float(buildings["height"][k])
        lot = pluto.get(lots.get(bin_number, int(buildings["bbl"][k])))
        floors = _floors(lot, height)
        floor_dm[k] = int(round(np.clip(height / floors, MIN_FLOOR, MAX_FLOOR) * 10))
        if lot is None:
            continue
        matched += 1
        archetype[k], flags[k] = _classify(lot, floors)
    print(f"  facades: {matched:,} of {count:,} buildings matched to tax lots", flush=True)
    return {"archetype": archetype, "flags": flags, "floor_dm": floor_dm}


def _floors(lot, height: float) -> int:
    """The building's floor count: the tax lot's, if it fits the height (a lot's
    count is for its main building), else estimated from the height."""
    floors = _number(lot, "numfloors") if lot else 0.0
    if floors >= 1 and MIN_FLOOR <= height / floors <= MAX_FLOOR + 1.0:
        return int(round(floors))
    return max(1, int(round(height / DEFAULT_FLOOR)))


def _classify(lot: dict, floors: int) -> tuple[int, int]:
    code = (lot.get("bldgclass") or "").upper()
    kind = code[:1]
    year = int(_number(lot, "yearbuilt")) or 1950
    prewar = year < PREWAR_YEAR
    retail = _number(lot, "retailarea") > 0 or code in ("C7", "D6", "D7") or kind in ("S", "K")
    residential = _number(lot, "resarea") >= max(_number(lot, "officearea"), 1.0)

    district = (lot.get("histdist") or "").upper()
    if year < 1920 and floors <= 12 and ("CAST IRON" in district or "TRIBECA" in district) and kind not in ("A", "B"):
        archetype = LOFT  # SoHo and Tribeca lofts, whatever they're used as now
    elif kind in ("A", "B"):
        attached = code in ("A4", "A5") or (kind == "B" and year < 1930 and lot.get("borough") in ("MN", "BK", "BX"))
        archetype = ROWHOUSE if attached else HOUSE
    elif kind in ("C", "S"):
        archetype = WALKUP if floors >= 4 else (ROWHOUSE if year < 1940 else HOUSE)
    elif kind == "D" or (kind == "R" and residential):
        archetype = PREWAR_APARTMENT if prewar else (
            POSTWAR_APARTMENT if year < MODERN_RESIDENTIAL_YEAR else MODERN_RESIDENTIAL)
    elif kind in ("O", "R"):
        archetype = PREWAR_OFFICE if prewar else (MIDCENTURY_OFFICE if year < MODERN_OFFICE_YEAR else MODERN_OFFICE)
    elif kind == "L":
        archetype = LOFT
    elif kind == "K":
        archetype = STORE if floors <= 3 else (PREWAR_OFFICE if prewar else MIDCENTURY_OFFICE)
    elif kind in ("E", "F", "G"):
        archetype = INDUSTRIAL
    elif kind in ("I", "J", "M", "N", "P", "W", "Y"):
        archetype = INSTITUTION
    elif kind == "H":
        archetype = HOTEL
    else:
        archetype = OTHER

    flags = RETAIL if retail else 0
    if archetype == WALKUP and year < 1930:
        flags |= FIRE_ESCAPES
    if year < CORNICE_YEAR and archetype in (ROWHOUSE, WALKUP, PREWAR_APARTMENT, PREWAR_OFFICE, LOFT, INSTITUTION):
        flags |= CORNICE
    if (lot.get("landmark") or "").strip():
        flags |= LANDMARK
    return archetype, flags


def _number(lot: dict, field: str) -> float:
    try:
        return float(lot.get(field) or 0)
    except (TypeError, ValueError):
        return 0.0


def encode(archetype: int, flags: int, floor_dm: int, seed: float) -> tuple[float, float]:
    """The uv2 pair for a building face."""
    return float(archetype + FLAG_SCALE * flags), float(floor_dm) + min(float(seed), 0.999)
