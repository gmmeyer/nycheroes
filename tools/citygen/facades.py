"""What each building's walls look like: one of a dozen New York building
types (archetypes), its floor height, its wall material, and a few details
(storefronts, fire escapes, cornices, how many steps its stoop has), from the
city's tax lot database (PLUTO) joined to the building footprints by tax lot.

The game's building shader draws them (shaders/building.gdshader). In the
tiles, building surfaces carry, per vertex:
  uv2.x = archetype + FLAG_SCALE * flags   (a whole number in a float)
  uv2.y = floor height in decimeters + the building's random seed (0..0.999)
Flags are per face: ROOF, FRONT (the wall faces a street), PARAPET,
PARAPET_INSIDE, SIGNS, STOOP and the FRONT_PART field are set by
build_tiles.py (and fronts.py, times_square.py); the rest, including the
MATERIAL field, are per building, from here.

Wall materials follow the borough, the era and the historic district:
brownstone rows in Brooklyn and Harlem, limestone rows from the 1900s, buff
"blond" brick in Ridgewood, deep red and brown brick in the Bronx and in
DUMBO's warehouses, limestone and cream brick for prewar Manhattan. Houses in
a row (consecutive tax lots on a block, built the same year) mostly share
one; the shader picks each building's own shade of it.

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
# The wall material, a field of three bits: flags // MATERIAL % 8 is one of
# the materials below (AUTO leaves it to the shader's mix for the type).
MATERIAL = 512
STOOP = 4096      # the building has a stoop (fronts.py), so its front door is there
# A field of three bits: flags // FRONT_PART is the part of a stoop a face is
# (fronts.py), 0 for walls and roofs. On SIGNS faces (which never have stoops)
# it's which of Times Square's own pieces the face is instead
# (times_square.py: One Times Square's screens to the top, the TKTS steps,
# plaza benches).
FRONT_PART = 8192
FLAG_SCALE = 64
PARAPET_HEIGHT = 1.0  # meters; the shader has the same constant

DEFAULT_FLOOR = 3.3  # meters, when the floor count isn't known or doesn't fit
MIN_FLOOR, MAX_FLOOR = 2.6, 6.0
PREWAR_YEAR = 1945
MODERN_RESIDENTIAL_YEAR = 1990
MODERN_OFFICE_YEAR = 1985
CORNICE_YEAR = 1940

# Wall materials (the MATERIAL field), in the order the shader numbers them.
AUTO = 0          # the shader's own mix for the building type
BROWNSTONE = 1    # chocolate-brown sandstone
RED_BRICK = 2     # deep red brick
BUFF_BRICK = 3    # buff, tan and "blond" brick
LIMESTONE = 4     # limestone and cream
BROWN_BRICK = 5   # dark brown and red-brown brick
PAINTED = 6       # painted brick and stucco
SIDING = 7        # vinyl and wood siding
# Odds of each material (BROWNSTONE, RED_BRICK, BUFF_BRICK, LIMESTONE,
# BROWN_BRICK, PAINTED, SIDING) by group of building types, borough and era
# (0: built by 1900, 1: 1901-1919, 2: 1920-1944, 3: since); None matches any.
MATERIAL_ODDS = {
    ("row", "MN", 0): (55, 30, 0, 5, 0, 10, 0),
    ("row", "MN", 1): (15, 20, 15, 40, 10, 0, 0),
    ("row", "MN", None): (0, 40, 20, 5, 30, 5, 0),
    ("row", "BK", 0): (60, 22, 0, 5, 5, 8, 0),
    ("row", "BK", 1): (25, 20, 15, 30, 10, 0, 0),
    ("row", "BK", 2): (0, 35, 30, 5, 25, 5, 0),
    ("row", "BK", None): (0, 30, 35, 0, 20, 10, 5),
    ("row", "BX", 0): (25, 30, 10, 10, 20, 5, 0),
    ("row", "BX", 1): (25, 30, 10, 10, 20, 5, 0),
    ("row", "BX", None): (0, 35, 25, 0, 30, 10, 0),
    ("row", "QN", 0): (0, 20, 65, 0, 15, 0, 0),
    ("row", "QN", 1): (0, 20, 65, 0, 15, 0, 0),
    ("row", "QN", 2): (0, 40, 25, 0, 25, 10, 0),
    ("row", "QN", None): (0, 35, 30, 0, 15, 10, 10),
    ("row", "SI", None): (0, 25, 15, 0, 10, 15, 35),
    ("walkup", "MN", None): (5, 40, 15, 0, 25, 15, 0),
    ("walkup", "BK", 0): (20, 35, 10, 0, 20, 15, 0),
    ("walkup", "BK", None): (5, 35, 25, 0, 25, 10, 0),
    ("walkup", "BX", None): (0, 40, 20, 0, 35, 5, 0),
    ("walkup", "QN", None): (0, 30, 45, 0, 20, 5, 0),
    ("walkup", "SI", None): (0, 40, 20, 0, 10, 30, 0),
    ("apartment", "MN", None): (0, 15, 30, 30, 25, 0, 0),
    ("apartment", "BX", None): (0, 20, 30, 5, 45, 0, 0),
    ("apartment", "SI", None): (0, 50, 40, 0, 10, 0, 0),
    ("apartment", None, None): (0, 30, 30, 5, 35, 0, 0),
    ("office", "MN", None): (0, 10, 30, 45, 15, 0, 0),
    ("office", None, None): (0, 30, 30, 20, 20, 0, 0),
    ("loft", "MN", None): (0, 30, 25, 20, 25, 0, 0),
    ("loft", None, None): (0, 55, 10, 0, 35, 0, 0),
    # Prewar buildings of any kind in the old warehouse districts (DUMBO).
    ("warehouse", None, None): (0, 60, 5, 0, 35, 0, 0),
}
# Rows in these historic districts (words of PLUTO's names) have their own
# odds, in the eras given.
DISTRICT_ODDS = (
    (("RIDGEWOOD",), (0, 1, 2), (0, 12, 80, 0, 8, 0, 0)),
    (("GREENWICH VILLAGE", "BROOKLYN HEIGHTS", "COBBLE HILL", "BOERUM HILL", "FORT GREENE", "CLINTON HILL"),
     (0,), (40, 45, 0, 0, 5, 10, 0)),
    (("PARK SLOPE", "PROSPECT HEIGHTS", "CROWN HEIGHTS", "BEDFORD", "STUYVESANT HEIGHTS", "MOUNT MORRIS",
      "HAMILTON HEIGHTS", "CENTRAL PARK WEST", "CARROLL GARDENS", "PROSPECT LEFFERTS", "ST. NICHOLAS",
      "DORRANCE BROOKS", "CENTRAL HARLEM", "WEST END-COLLEGIATE", "RIVERSIDE-WEST END"),
     (0, 1), (55, 15, 5, 20, 5, 0, 0)),
    (("JACKSON HEIGHTS", "SUNNYSIDE"), (1, 2, 3), (0, 50, 15, 0, 35, 0, 0)),
)
WAREHOUSE_DISTRICTS = ("DUMBO", "FULTON FERRY", "VINEGAR HILL", "WALLABOUT", "GANSEVOORT", "WEST CHELSEA")
# Houses in a row share a material, except this share, picked on their own.
OWN_MATERIAL_SHARE = 0.2

CACHE_NAME = "facades"


def lot_tables() -> tuple[dict, dict]:
    """The tax lot of each building ID (BIN), and PLUTO's row for each lot (BBL)."""
    lots = {}
    for row in json.loads((RAW_DIR / "building_lots.json").read_text()):
        if row.get("bin") and row.get("mappluto_bbl"):
            lots[int(float(row["bin"]))] = int(float(row["mappluto_bbl"]))
    pluto = {}
    for row in json.loads((RAW_DIR / "pluto.json").read_text()):
        if row.get("bbl"):
            pluto[int(float(row["bbl"]))] = row
    return lots, pluto


def prepare(buildings: dict) -> dict:
    """Per building (same order as `buildings`): archetype, flags, floor height (dm)."""
    lots, pluto = lot_tables()

    count = len(buildings["bin"])
    archetype = np.full(count, UNKNOWN, dtype=np.uint8)
    flags = np.zeros(count, dtype=np.uint16)
    floor_dm = np.zeros(count, dtype=np.uint8)
    stoop = np.zeros(count, dtype=np.uint8)
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
        archetype[k], flags[k], stoop[k] = _classify(lot, floors, bin_number)
    print(f"  facades: {matched:,} of {count:,} buildings matched to tax lots", flush=True)
    # stoop: steps up to the front door (fronts.py), 0 for none.
    return {"archetype": archetype, "flags": flags, "floor_dm": floor_dm, "stoop": stoop}


def _floors(lot, height: float) -> int:
    """The building's floor count: the tax lot's, if it fits the height (a lot's
    count is for its main building), else estimated from the height."""
    floors = number(lot, "numfloors") if lot else 0.0
    if floors >= 1 and MIN_FLOOR <= height / floors <= MAX_FLOOR + 1.0:
        return int(round(floors))
    return max(1, int(round(height / DEFAULT_FLOOR)))


def row_attached(lot: dict):
    """Whether the lot's building is attached on both sides (PLUTO's proximity
    code 3) or detached (1); None if PLUTO doesn't know or says semi-attached
    (2), which is as often the end of a row as half of a pair."""
    code = str(lot.get("proxcode") or "0")
    return {"1": False, "3": True}.get(code)


def _classify(lot: dict, floors: int, bin_number: int) -> tuple[int, int, int]:
    """The building's archetype, flags and stoop steps."""
    code = (lot.get("bldgclass") or "").upper()
    kind = code[:1]
    year = int(number(lot, "yearbuilt")) or 1950
    prewar = year < PREWAR_YEAR
    retail = number(lot, "retailarea") > 0 or code in ("C7", "D6", "D7") or kind in ("S", "K")
    residential = number(lot, "resarea") >= max(number(lot, "officearea"), 1.0)

    district = (lot.get("histdist") or "").upper()
    if year < 1920 and floors <= 12 and ("CAST IRON" in district or "TRIBECA" in district) and kind not in ("A", "B"):
        archetype = LOFT  # SoHo and Tribeca lofts, whatever they're used as now
    elif kind in ("A", "B"):
        attached = row_attached(lot)
        if attached is None:
            attached = code in ("A4", "A5") or (kind == "B" and year < 1930 and lot.get("borough") in ("MN", "BK", "BX"))
        archetype = ROWHOUSE if attached else HOUSE
    elif kind in ("C", "S"):
        attached = row_attached(lot)
        archetype = WALKUP if floors >= 4 else (ROWHOUSE if (year < 1940 if attached is None else attached) else HOUSE)
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
    flags |= MATERIAL * _material(lot, archetype, year, district, bin_number)
    return archetype, flags, _stoop_steps(lot, archetype, retail, year, bin_number)


def _material(lot: dict, archetype: int, year: int, district: str, bin_number: int) -> int:
    """The building's wall material (see MATERIAL_ODDS), or AUTO."""
    borough = lot.get("borough")
    if year < PREWAR_YEAR and any(name in district for name in WAREHOUSE_DISTRICTS) and archetype in (
            WALKUP, PREWAR_APARTMENT, PREWAR_OFFICE, LOFT, INDUSTRIAL):
        group = "warehouse"
    elif archetype == ROWHOUSE:
        group = "row"
    elif archetype == WALKUP:
        group = "walkup"
    elif archetype == PREWAR_APARTMENT:
        group = "apartment"
    elif archetype == PREWAR_OFFICE:
        group = "office"
    elif archetype == LOFT and "CAST IRON" not in district and "TRIBECA" not in district:
        group = "loft"
    else:
        return AUTO
    era = 0 if year <= 1900 else (1 if year < 1920 else (2 if year < PREWAR_YEAR else 3))
    odds = None
    if group == "row":
        for names, eras, district_odds in DISTRICT_ODDS:
            if era in eras and any(name in district for name in names):
                odds = district_odds
                break
    if odds is None:
        odds = (MATERIAL_ODDS.get((group, borough, era)) or MATERIAL_ODDS.get((group, borough, None))
                or MATERIAL_ODDS.get((group, None, None)))
    if odds is None:
        return AUTO
    # A row: consecutive lots on the block, built the same year.
    bbl = int(float(lot.get("bbl") or 0))
    r = unit_hash(bbl // 10000, (bbl % 10000) // 5, year)
    if unit_hash(bin_number, 7) < OWN_MATERIAL_SHARE:
        r = unit_hash(bin_number, 11)
    cumulative = np.cumsum(odds) / float(sum(odds))
    return BROWNSTONE + min(int(np.searchsorted(cumulative, r, side="right")), len(odds) - 1)


def _stoop_steps(lot: dict, archetype: int, retail: bool, year: int, bin_number: int) -> int:
    """Steps up to the front door: brownstones' parlor floors are 8-10 steps
    up, later rows' fewer; walk-ups have a few (none behind shop fronts)."""
    if retail:
        return 0
    r = unit_hash(bin_number, 13)
    if archetype == ROWHOUSE:
        if lot.get("borough") in ("QN", "SI"):
            steps = 5 if year < 1920 else (4 if year < PREWAR_YEAR else 3)
        else:
            steps = 9 if year <= 1900 else (7 if year < 1916 else (4 if year < PREWAR_YEAR else 3))
        return steps + (1 if r > 0.75 else (-1 if r < 0.25 else 0))
    if archetype == WALKUP:
        return (3 if year < 1930 else 2) + (1 if r > 0.6 else 0)
    return 0


def unit_hash(*values: int) -> float:
    """A repeatable pseudo-random number in [0, 1) from whole numbers."""
    h = 2166136261
    for v in values:
        h = ((h ^ (int(v) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
        h ^= h >> 15
    return ((h * 2654435761) & 0xFFFFFFFF) / 4294967296.0


def number(lot: dict, field: str) -> float:
    try:
        return float(lot.get(field) or 0)
    except (TypeError, ValueError):
        return 0.0


def block_flags(archetypes: np.ndarray, flags: np.ndarray, weights: np.ndarray, archetype: int) -> int:
    """Flags for a merged block of buildings (far tiles) drawn as `archetype`:
    the wall material most of its buildings of that type have (by weight)."""
    same = archetypes == archetype
    if not same.any():
        return 0
    votes = np.bincount((flags[same].astype(np.int64) // MATERIAL) % 8, weights=weights[same], minlength=8)
    return MATERIAL * int(np.argmax(votes))


def encode(archetype: int, flags: int, floor_dm: int, seed: float) -> tuple[float, float]:
    """The uv2 pair for a building face."""
    return float(archetype + FLAG_SCALE * flags), float(floor_dm) + min(float(seed), 0.999)
