"""Props standing in the city, one point each (see common.py's props surface):
trees, rooftop water towers, street lights and street furniture.

Trees come from two places:
  street trees: the Parks Department's tree inventory (Forestry Tree Points),
    with each tree's species and trunk size, which set its shape, color and size;
  everything else (parks, yards, woods): the 2017 land cover map's tree
    canopy (landcover.py), planted on a jittered grid wherever there's canopy.
Seen from afar, past where those trees are drawn, woods are clumps of crowns
from the same map (canopy_clumps()), in tiles of every level.
Water towers: New York's wooden rooftop tanks sit on most older buildings of
six floors and up (the height city water pressure reaches). Which buildings
have one is a guess from the building's type, floors and borough, seeded
per building, and the tank stands at a back corner of the roof.
Street lights: the city doesn't publish where its lamps are, so they stand
along every curb at a typical spacing (lamp_spots()).
Street furniture: hydrants, bus shelters, LinkNYC kiosks, benches, subway
entrances, litter baskets, bike racks, parking meters and newsstands where
the city's inventories put them (prepare_furniture()); traffic signals at
intersections with a wide street (markings.signals()).

prepare_trees() makes data/cache/trees.pkl; build_tiles.py does the rest per
lod0 tile with the helpers here (clumps per tile of every level).
"""

import json

import numpy as np
import shapely

import facades
from common import (PROP_BENCH, PROP_BIKE_RACK, PROP_BUS_SHELTER, PROP_CANOPY, PROP_CONIFER, PROP_HYDRANT,
                    PROP_LINKNYC, PROP_LITTER_BASKET, PROP_NEWSSTAND, PROP_PARKING_METER, PROP_STREET_LIGHT,
                    PROP_SUBWAY_ENTRANCE, PROP_TONE_DARK, PROP_TONE_GREEN, PROP_TONE_LIGHT, PROP_TONE_RED,
                    PROP_TRAFFIC_SIGNAL, PROP_TREE, PROP_TREE_NARROW, RAW_DIR, project)

# Street trees' shapes and colors by genus (the inventory's species names
# start with it: "Acer saccharinum - silver maple").
NARROW_GENERA = {"Pyrus", "Ginkgo", "Carpinus", "Populus"}
CONIFER_GENERA = {"Pinus", "Picea", "Abies", "Tsuga", "Cedrus", "Juniperus", "Thuja", "Taxodium",
                  "Metasequoia", "Chamaecyparis", "Cryptomeria", "Pseudotsuga", "Larix", "Taxus",
                  "Cupressus", "Cupressocyparis", "xCupressocyparis", "Sequoia", "Sequoiadendron", "Platycladus"}
LIGHT_GENERA = {"Gleditsia", "Ginkgo", "Betula", "Salix", "Robinia", "Cladrastis", "Koelreuteria",
                "Gymnocladus", "Liriodendron", "Styphnolobium", "Sophora"}
DARK_GENERA = {"Quercus", "Tilia", "Fagus", "Magnolia", "Ilex", "Aesculus", "Ulmus"}
RED_SPECIES = ("cerasifera", "purple", "copper", "crimson", "canada red", "not green leaf")
# Crown diameter as a share of the height. Callery pears are teardrops once
# grown, not columns; small flowering trees spread about as wide as they're
# tall.
CROWN_RATIO = {PROP_TREE: 0.62, PROP_TREE_NARROW: 0.38, PROP_CONIFER: 0.42}
GENUS_CROWN_RATIO = {"Platanus": 0.72, "Gleditsia": 0.68, "Quercus": 0.66, "Zelkova": 0.7, "Pyrus": 0.55,
                     "Prunus": 0.85, "Malus": 0.85, "Cercis": 0.85, "Cornus": 0.8, "Crataegus": 0.8}
# Heights come from trunk size, as for a shade tree (a London plane or oak of
# 12 inches is about 10 m, of 24 inches about 16 m); small flowering trees
# stay shorter by this share.
GENUS_HEIGHT_SCALE = {"Prunus": 0.8, "Malus": 0.75, "Cercis": 0.75, "Syringa": 0.7, "Cornus": 0.7,
                      "Amelanchier": 0.75, "Crataegus": 0.75, "Maackia": 0.8, "Koelreuteria": 0.85}
DEFAULT_DBH = 6.0  # inches, when the inventory has none
MAX_TREE_HEIGHT = 28.0
INCH = 0.0254
# Canopy trees' trunks: this share of the height, within these limits (m).
TRUNK_SHARE, TRUNK_RANGE = 0.025, (0.12, 0.6)

# Other trees: one per CANOPY_SPACING-meter cell of canopy, sized by how much
# canopy is around (lone trees are smaller than woods).
CANOPY_SPACING = 7.0
CANOPY_JITTER = 0.4  # of the spacing, either way
CANOPY_HEIGHT = (6.0, 18.0)  # meters: a lone tree, and in woods (before jitter)
# Conifers grow in patches: each CONIFER_PATCH-meter square has its own share.
CONIFER_PATCH = 150.0
CONIFER_MAX_SHARE = 0.4
CANOPY_TONES = ((PROP_TONE_GREEN, 0.55), (PROP_TONE_DARK, 0.3), (PROP_TONE_LIGHT, 0.12), (PROP_TONE_RED, 0.03))
# Woods seen from afar, in every tile level: a clump of crowns (a squat dome)
# for each CLUMP_CELL-meter square of the land cover map (the canopy map's
# pixels) that is at least CLUMP_MIN_SHARE canopy, standing where its canopy
# is, as wide as that much canopy (CLUMP_WIDTH times the side of a square of
# it: lone trees small, woods closing over each other) and as tall as canopy
# trees there. Far tiles' squares are CLUMP_CELL_FAR meters and need more
# canopy. The game grows them in where the trees shrink away
# (shaders/tree.gdshader), so woods keep their crowns out to the horizon.
CLUMP_CELL = 16.0
CLUMP_CELL_FAR = 32.0
CLUMP_MIN_SHARE = 0.15
CLUMP_MIN_SHARE_FAR = 0.3
CLUMP_WIDTH = 1.3

# Street lights: one every LAMP_SPACING meters along every curb (the first
# half a spacing in), LAMP_SETBACK onto the sidewalk, and none closer than
# LAMP_MIN_GAP to another. Curbs around road islands shorter than
# LAMP_MIN_ISLAND get none. In and beside parks, and along the boulevards in
# HISTORIC_LAMP_STREETS, they're historic post-tops.
LAMP_SPACING = 35.0
LAMP_SETBACK = 0.6
LAMP_MIN_GAP = 12.0
LAMP_MIN_ISLAND = 40.0
LAMP_PARK_REACH = 4.0
COBRA_HEAD = (9.0, 2.6)  # pole height, arm length (m)
POST_TOP = (4.4, 0.0)
# Boulevards lit by historic post-tops instead of cobra-heads: (street name
# as in the centerline data, borough code, (south, west, north, east) or
# None for its whole length). Curb lamps up to HISTORIC_LAMP_REACH beyond the
# street's half width, with their arm across it, are post-tops
# (ground_details.GroundDetails.historic_lamps).
HISTORIC_LAMP_STREETS = (
    ("GRAND CONC", 2, None),
    ("OCEAN PKWY", 3, None),
    ("EASTERN PKWY", 3, None),
    ("RIVERSIDE DR", 1, None),
    ("RIVERSIDE DR W", 1, None),
    ("RIVERSIDE DR E", 1, None),
    ("5 AVE", 1, (40.7638, -73.9745, 40.7972, -73.9485)),  # along Central Park, 59th to 110th Street
)
HISTORIC_LAMP_REACH = 4.0

# Times Square's sign district: street walls in this box get billboards
# (facades.SIGNS). Meters along Manhattan's avenues (29 degrees east of north,
# from the origin at 46th St and Broadway; south is negative) and across them
# (east is positive): 42nd to about 50th Street (as far as the real signs
# go), Broadway and Seventh Avenue with the fronts facing them. The ground
# shader's sign_district_along/_across must match.
SIGN_ALONG = (-330.0, 420.0)
SIGN_ACROSS = (-120.0, 110.0)
AVENUE_ALONG = np.array([0.485, 0.875])   # east/north
AVENUE_ACROSS = np.array([0.875, -0.485])

# Lamps on bridge decks (cobra-heads along both edges, arms over the deck)
# and on park paths (post-tops where the land cover shows paving in a park).
DECK_LAMP_SPACING = 30.0
DECK_LAMP_INSET = 0.8
PATH_LAMP_TRY = 7.0  # one try per cell of this size; it lands on a path or not
PATH_LAMP_GAP = 22.0  # then lamps closer than this are thinned out
PATH_LAMP_STREET_GAP = 8.0  # streets already have their own lamps

# Water towers: the chance a building has one, by type and by borough (from
# borough code), for buildings of at least TOWER_MIN_FLOORS floors and at most
# TOWER_MAX_HEIGHT meters (skyscrapers keep their tanks inside).
TOWER_TYPE_CHANCE = {
    facades.WALKUP: 1.0, facades.PREWAR_APARTMENT: 1.0, facades.PREWAR_OFFICE: 0.9, facades.LOFT: 0.9,
    facades.HOTEL: 0.75, facades.INDUSTRIAL: 0.6, facades.POSTWAR_APARTMENT: 0.55,
    facades.MIDCENTURY_OFFICE: 0.4, facades.STORE: 0.4, facades.INSTITUTION: 0.35,
    facades.OTHER: 0.3, facades.UNKNOWN: 0.3,
}
TOWER_BOROUGH_CHANCE = {1: 0.85, 2: 0.6, 3: 0.65, 4: 0.35, 5: 0.12}
TOWER_MIN_FLOORS = 6
TOWER_MAX_HEIGHT = 160.0
TOWER_STEEL_SHARE = 0.15
# A second tank on big roofs.
TOWER_SECOND_AREA = 3000.0


def prepare_trees() -> dict:
    """Street trees from the inventory: positions (east/north) and props."""
    # The inventory's "geometry" column is text (WKT), so it lands in the properties.
    with open(RAW_DIR / "trees.geojson", encoding="utf-8") as f:
        feats = [feat for feat in json.load(f)["features"] if feat["properties"].get("geometry")]
    points = project(shapely.from_wkt([f["properties"]["geometry"] for f in feats]))
    en = shapely.get_coordinates(points)
    dbh = np.array([float(f["properties"].get("dbh") or 0) for f in feats])
    species = [str(f["properties"].get("genusspecies") or "") for f in feats]
    seed = location_seed(en)

    kinds = np.full(len(en), PROP_TREE, dtype=np.int8)
    tones = np.full(len(en), PROP_TONE_GREEN, dtype=np.int8)
    ratio = np.full(len(en), CROWN_RATIO[PROP_TREE])
    scale = np.ones(len(en))
    for k, name in enumerate(species):
        genus = name.split(" ", 1)[0]
        if genus in CONIFER_GENERA:
            kinds[k], tones[k] = PROP_CONIFER, PROP_TONE_DARK
        elif genus in NARROW_GENERA:
            kinds[k] = PROP_TREE_NARROW
        if genus in LIGHT_GENERA:
            tones[k] = PROP_TONE_LIGHT
        elif genus in DARK_GENERA:
            tones[k] = PROP_TONE_DARK
        if any(word in name.lower() for word in RED_SPECIES):
            tones[k] = PROP_TONE_RED
        ratio[k] = GENUS_CROWN_RATIO.get(genus, CROWN_RATIO[int(kinds[k])])
        scale[k] = GENUS_HEIGHT_SCALE.get(genus, 1.0)

    dbh = np.where(dbh > 0, dbh, DEFAULT_DBH)
    height = np.minimum(3.0 + 0.9 * dbh ** 0.85, MAX_TREE_HEIGHT) * scale * (0.9 + 0.2 * _hash(seed, 1))
    width = height * ratio * (0.88 + 0.24 * _hash(seed, 2))
    return {"en": en, "height": height.astype(np.float32), "width": width.astype(np.float32),
            "trunk": (dbh * INCH).astype(np.float32), "type": kinds, "tone": tones, "seed": seed.astype(np.float32)}


def canopy_candidates(bounds) -> tuple[np.ndarray, np.ndarray]:
    """Jittered grid points (one per CANOPY_SPACING cell) inside the
    (min_e, min_n, max_e, max_n) box, and their seeds. The grid is global, so
    neighboring tiles agree."""
    min_e, min_n, max_e, max_n = bounds
    s = CANOPY_SPACING
    i = np.arange(np.floor(min_e / s) - 1, np.ceil(max_e / s) + 1)
    j = np.arange(np.floor(min_n / s) - 1, np.ceil(max_n / s) + 1)
    ii, jj = (a.ravel() for a in np.meshgrid(i, j))
    seed = _cell_hash(ii, jj)
    jitter = CANOPY_JITTER * s * 2
    e = (ii + 0.5) * s + (_hash(seed, 3) - 0.5) * jitter
    n = (jj + 0.5) * s + (_hash(seed, 4) - 0.5) * jitter
    inside = (e >= min_e) & (e < max_e) & (n >= min_n) & (n < max_n)
    return np.column_stack([e[inside], n[inside]]), seed[inside]


def canopy_trees(en: np.ndarray, seed: np.ndarray, density: np.ndarray) -> dict:
    """Props for canopy trees at these points; density (0..1) is how much of
    the ground around each is canopy."""
    low, high = CANOPY_HEIGHT
    height = (low + (high - low) * np.clip(density, 0, 1) ** 0.7) * (0.8 + 0.45 * _hash(seed, 5))
    patch = _cell_hash(np.floor(en[:, 0] / CONIFER_PATCH), np.floor(en[:, 1] / CONIFER_PATCH))
    conifer_share = CONIFER_MAX_SHARE * _hash(patch, 6) ** 3
    roll = _hash(seed, 7)
    kinds = np.where(roll < conifer_share, PROP_CONIFER,
                     np.where(roll > 0.965, PROP_TREE_NARROW, PROP_TREE)).astype(np.int8)
    ratio = np.array([CROWN_RATIO[kind] for kind in (PROP_TREE, PROP_TREE_NARROW, PROP_CONIFER)])[kinds]
    width = np.clip(height * ratio * 1.15, 3.0, 13.0) * (0.85 + 0.3 * _hash(seed, 8))
    tone_roll = _hash(seed, 9)
    tones = np.full(len(en), PROP_TONE_GREEN, dtype=np.int8)
    edge = 0.0
    for tone, share in CANOPY_TONES:
        tones[(tone_roll >= edge) & (tone_roll < edge + share)] = tone
        edge += share
    tones[kinds == PROP_CONIFER] = PROP_TONE_DARK
    trunk = np.clip(height * TRUNK_SHARE, *TRUNK_RANGE) * (0.85 + 0.3 * _hash(seed, 15))
    return {"en": en, "height": height.astype(np.float32), "width": width.astype(np.float32),
            "trunk": trunk.astype(np.float32), "type": kinds, "tone": tones, "seed": seed.astype(np.float32)}


def canopy_clumps(en: np.ndarray, share: np.ndarray, cells: np.ndarray, cell: float) -> dict:
    """Props for clumps of crowns (PROP_CANOPY) seen from afar, from the land
    cover's `cell`-meter squares (LandCover.canopy_cells: the middle of each
    one's canopy, its share of canopy, its column and row). Their "trunk" is
    1 for conifers (in the canopy trees' patches), else 0."""
    far = cell > CLUMP_CELL
    keep = share >= (CLUMP_MIN_SHARE_FAR if far else CLUMP_MIN_SHARE)
    en, share, cells = en[keep], share[keep], cells[keep]
    seed = _cell_hash(cells[:, 0] * 2 + int(far), cells[:, 1])
    low, high = CANOPY_HEIGHT
    height = (low + (high - low) * share ** 0.7) * (0.9 + 0.25 * _hash(seed, 21))
    width = CLUMP_WIDTH * np.sqrt(share) * cell * (0.9 + 0.2 * _hash(seed, 22))
    tone_roll = _hash(seed, 9)
    tones = np.full(len(en), PROP_TONE_GREEN, dtype=np.int8)
    edge = 0.0
    for tone, part in CANOPY_TONES:
        # A red-leaved tree doesn't color a whole clump.
        tones[(tone_roll >= edge) & (tone_roll < edge + part)] = PROP_TONE_GREEN if tone == PROP_TONE_RED else tone
        edge += part
    patch = _cell_hash(np.floor(en[:, 0] / CONIFER_PATCH), np.floor(en[:, 1] / CONIFER_PATCH))
    conifer = _hash(seed, 7) < CONIFER_MAX_SHARE * _hash(patch, 6) ** 3
    tones[conifer] = PROP_TONE_DARK
    return {"en": en, "height": height.astype(np.float32), "width": width.astype(np.float32),
            "trunk": conifer.astype(np.float32), "type": np.full(len(en), PROP_CANOPY, dtype=np.int8),
            "tone": tones, "seed": seed.astype(np.float32), "yaw": _hash(seed, 23) * (2 * np.pi)}


def lamp_spots(roads: list, tile_edge) -> tuple[np.ndarray, np.ndarray]:
    """Street light positions (N, 2) along the curbs of these road polygons
    (east/north, oriented), and the direction (N, 2) each one's arm reaches,
    over the road. Curbs along `tile_edge` (where the tile cuts the road)
    don't count."""
    points, arms = [], []
    for poly in roads:
        for k, ring in enumerate((poly.exterior, *poly.interiors)):
            if k > 0 and ring.length < LAMP_MIN_ISLAND:
                continue
            # Oriented polygons have the road on the left of every ring.
            for line in shapely.get_parts(shapely.difference(ring, tile_edge)):
                if line.geom_type != "LineString" or line.length < LAMP_SPACING / 2:
                    continue
                s = np.arange(LAMP_SPACING / 2, line.length, LAMP_SPACING)
                at = shapely.get_coordinates(shapely.line_interpolate_point(line, s))
                ahead = shapely.get_coordinates(shapely.line_interpolate_point(line, np.minimum(s + 0.5, line.length)))
                behind = shapely.get_coordinates(shapely.line_interpolate_point(line, np.maximum(s - 0.5, 0.0)))
                tangent = ahead - behind
                tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-9)
                left = np.column_stack([-tangent[:, 1], tangent[:, 0]])
                points.append(at - left * LAMP_SETBACK)
                arms.append(left)
    if not points:
        return np.zeros((0, 2)), np.zeros((0, 2))
    points, arms = np.concatenate(points), np.concatenate(arms)
    # Thin out lamps that ended up close together (corners, narrow islands).
    keep = spread(points, LAMP_MIN_GAP)
    return points[keep], arms[keep]


def spread(points: np.ndarray, gap: float) -> np.ndarray:
    """Which of these (N, 2) points to keep so none are closer than `gap`
    (earlier ones win)."""
    keep = np.ones(len(points), dtype=bool)
    if len(points) < 2:
        return keep
    pairs = shapely.STRtree(shapely.points(points)).query(shapely.points(points), predicate="dwithin", distance=gap)
    pairs = pairs[:, pairs[0] < pairs[1]]
    for a, b in pairs[:, np.lexsort((pairs[1], pairs[0]))].T:
        if keep[a]:
            keep[b] = False
    return keep


def in_sign_district(en: np.ndarray) -> np.ndarray:
    """Which (N, 2) east/north points are in Times Square's sign district."""
    en = np.asarray(en, np.float64).reshape(-1, 2)
    along, across = en @ AVENUE_ALONG, en @ AVENUE_ACROSS
    return ((along >= SIGN_ALONG[0]) & (along <= SIGN_ALONG[1])
            & (across >= SIGN_ACROSS[0]) & (across <= SIGN_ACROSS[1]))


def deck_lamps(ring: np.ndarray, deck_y) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Lamps along a bridge deck's outline (an oriented exterior ring, deck on
    its left): positions (N, 2), heights (N,) and arm directions (N, 2)."""
    line = shapely.LineString(ring)
    if line.length < DECK_LAMP_SPACING:
        return np.zeros((0, 2)), np.zeros(0), np.zeros((0, 2))
    s = np.arange(DECK_LAMP_SPACING / 2, line.length, DECK_LAMP_SPACING)
    at = shapely.get_coordinates(shapely.line_interpolate_point(line, s))
    ahead = shapely.get_coordinates(shapely.line_interpolate_point(line, np.minimum(s + 0.5, line.length)))
    behind = shapely.get_coordinates(shapely.line_interpolate_point(line, np.maximum(s - 0.5, 0.0)))
    tangent = ahead - behind
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-9)
    left = np.column_stack([-tangent[:, 1], tangent[:, 0]])
    points = at + left * DECK_LAMP_INSET
    return points, np.asarray(deck_y(points), np.float64), left


def lamps(points: np.ndarray, arms: np.ndarray, post_top: np.ndarray) -> dict:
    """Street light props at these points: cobra-heads reaching along `arms`
    (east/north), or post-tops where post_top."""
    seed = location_seed(points)
    height = np.where(post_top, POST_TOP[0], COBRA_HEAD[0]) * (0.95 + 0.1 * _hash(seed, 16))
    arm = np.where(post_top, POST_TOP[1], COBRA_HEAD[1])
    # Godot: x east, z south; the arm reaches along (sin yaw, cos yaw) there.
    yaw = np.arctan2(arms[:, 0], -arms[:, 1])
    return {"en": points, "height": height, "width": arm, "trunk": np.zeros(len(points)),
            "type": np.full(len(points), PROP_STREET_LIGHT, dtype=np.int8),
            "tone": post_top.astype(np.int8), "seed": seed, "yaw": yaw}


# Street furniture: (table, latitude and longitude fields, type, height and
# width in meters for variant 0 and 1 (and 2)).
FURNITURE = (
    ("hydrants", "latitude", "longitude", PROP_HYDRANT, [(0.75, 0.4)]),
    ("bus_shelters", "latitude", "longitude", PROP_BUS_SHELTER, [(2.6, 4.2)]),
    ("linknyc", "latitude", "longitude", PROP_LINKNYC, [(2.9, 0.9), (9.0, 0.6)]),
    ("seating", "latitude", "longitude", PROP_BENCH, [(0.85, 1.8)]),
    ("subway_entrances", "entrance_latitude", "entrance_longitude", PROP_SUBWAY_ENTRANCE,
     [(2.5, 1.8), (2.5, 1.8), (3.0, 2.2)]),
    ("bike_racks", "latitude", "longitude", PROP_BIKE_RACK, [(0.9, 0.9), (0.9, 1.2)]),
    ("litter_baskets", "latitude", "longitude", PROP_LITTER_BASKET, [(0.9, 0.6), (1.2, 0.7)]),
    ("parking_meters", "lat", "long", PROP_PARKING_METER, [(1.6, 0.35)]),
    ("newsstands", "latitude", "longitude", PROP_NEWSSTAND, [(2.7, 3.0)]),
)
# Subway entrances that are a stairway, ramp or elevator on the sidewalk (not
# inside a building, a station house, or a passage).
SUBWAY_STREET_TYPES = ("Stair", "Elevator", "Escalator", "Ramp")
TRAFFIC_SIGNAL_SIZE = (6.2, 0.4)  # pole height, width (m)


def prepare_furniture() -> dict:
    """Street furniture from the city's inventories: positions (east/north),
    types, variants (uv.x), sizes and seeds."""
    parts = []
    for table, lat_key, lon_key, kind, sizes in FURNITURE:
        with open(RAW_DIR / f"{table}.json", encoding="utf-8") as f:
            rows = [r for r in json.load(f) if r.get(lat_key) and r.get(lon_key)]
        variant = np.zeros(len(rows), dtype=np.int8)
        keep = np.ones(len(rows), dtype=bool)
        for k, r in enumerate(rows):
            if table == "linknyc":
                variant[k] = 1 if "5G" in str(r.get("planned_kiosk_type", "")) else 0
            elif table == "subway_entrances":
                kind_name = str(r.get("entrance_type", ""))
                keep[k] = kind_name.startswith(SUBWAY_STREET_TYPES)
                variant[k] = 2 if kind_name == "Elevator" else (0 if r.get("entry_allowed") == "YES" else 1)
            elif table == "bike_racks":
                variant[k] = 0 if "hoop" in str(r.get("racktype", "")).lower() else 1
            elif table == "litter_baskets":
                variant[k] = 0 if "wire" in str(r.get("baskettype", "")).lower() else 1
        lon = np.array([float(r[lon_key]) for r in rows])
        lat = np.array([float(r[lat_key]) for r in rows])
        en = shapely.get_coordinates(project(shapely.points(lon, lat)))
        size = np.array(sizes)[np.minimum(variant, len(sizes) - 1)]
        part = {"en": en, "type": np.full(len(rows), kind, dtype=np.int8), "tone": variant,
                "height": size[:, 0], "width": size[:, 1]}
        parts.append({key: value[keep] for key, value in part.items()})
        print(f"  {table}: {int(keep.sum()):,}", flush=True)
    out = {key: np.concatenate([p[key] for p in parts]) for key in parts[0]}
    out["seed"] = location_seed(out["en"]).astype(np.float32)
    return out


def tower_mask(archetype, floors, height, borough, seed) -> np.ndarray:
    """Which buildings (arrays of their type, floors, height, borough code and
    seed) have a water tower."""
    type_chance = np.zeros(64)
    for kind, chance in TOWER_TYPE_CHANCE.items():
        type_chance[kind] = chance
    borough_chance = np.zeros(10)
    for code, chance in TOWER_BOROUGH_CHANCE.items():
        borough_chance[code] = chance
    chance = (type_chance[np.asarray(archetype, np.int64) % 64]
              * borough_chance[np.clip(np.asarray(borough), 0, 9).astype(np.int64)])
    return (np.asarray(floors) >= TOWER_MIN_FLOORS) & (np.asarray(height) <= TOWER_MAX_HEIGHT) & (_hash(seed, 10) < chance)


def tower_sizes(area: float, seed: float) -> tuple[float, float, int]:
    """(total height, tank diameter, variant) of a building's water tower."""
    big = min(1.0, area / 2500.0)
    diameter = 3.6 + 1.4 * big + 0.8 * float(_hash(np.float64(seed), 11))
    height = 7.0 + 1.5 * big + 2.0 * float(_hash(np.float64(seed), 12))
    variant = 1 if float(_hash(np.float64(seed), 13)) < TOWER_STEEL_SHARE else 0
    return height, diameter, variant


def tower_spots(poly, streets, diameter: float, seed: float) -> list[np.ndarray]:
    """Where on a footprint's roof its tank(s) stand: back corners (furthest
    from the street), clear of the roof's edge. Empty if the roof is too small."""
    for inset in (diameter / 2 + 1.0, diameter / 2 + 0.3):
        inner = shapely.buffer(poly, -inset, join_style="mitre")
        parts = [p for p in shapely.get_parts(inner) if not p.is_empty]
        if parts:
            break
    else:
        return []
    inner = max(parts, key=lambda p: p.area)
    corners = np.asarray(inner.exterior.coords)[:-1]
    if len(corners) == 0:
        return []
    if streets is not None and not streets.is_empty:
        away = shapely.distance(streets, shapely.points(corners))
    else:
        away = np.zeros(len(corners))
    # A little randomness so not every tank picks the same corner.
    away = away + _hash(np.full(len(corners), seed) + np.arange(len(corners)), 14) * 3.0
    order = np.argsort(-away)
    spots = [corners[order[0]]]
    if poly.area >= TOWER_SECOND_AREA and len(order) > 1:
        far = corners[order[1:]]
        gap = np.linalg.norm(far - spots[0], axis=1)
        if gap.max() > diameter * 3:
            spots.append(far[int(np.argmax(gap > diameter * 3))])
    return spots


def location_seed(en: np.ndarray) -> np.ndarray:
    """A 0..1 seed from each (east, north) position (to the decimeter)."""
    return _cell_hash(np.round(en[:, 0] * 10.0), np.round(en[:, 1] * 10.0))


def _cell_hash(i: np.ndarray, j: np.ndarray) -> np.ndarray:
    """0..1 hash of integer cell coordinates."""
    h = (np.asarray(i, np.float64).astype(np.int64) * 73856093) ^ (np.asarray(j, np.float64).astype(np.int64) * 19349663)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFFFF).astype(np.float64) / float(0x1000000)


def _hash(seed, salt: int):
    """Another 0..1 number from a 0..1 seed, different for each salt."""
    x = np.asarray(seed, np.float64) * 1000.0 + salt * 7.123
    return np.mod(np.sin(x * 12.9898 + salt * 78.233) * 43758.5453, 1.0)
