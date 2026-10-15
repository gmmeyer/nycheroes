"""Props standing in the city, one point each (see common.py's props surface):
trees, rooftop water towers and street lights.

Trees come from two places:
  street trees: the Parks Department's tree inventory (Forestry Tree Points),
    with each tree's species and trunk size, which set its shape, color and size;
  everything else (parks, yards, woods): the 2017 land cover map's tree
    canopy (landcover.py), planted on a jittered grid wherever there's canopy.
Water towers: New York's wooden rooftop tanks sit on most older buildings of
six floors and up (the height city water pressure reaches). Which buildings
have one is a guess from the building's type, floors and borough, seeded
per building, and the tank stands at a back corner of the roof.
Street lights: the city doesn't publish where its lamps are, so they stand
along every curb at a typical spacing (lamp_spots()).

prepare_trees() makes data/cache/trees.pkl; build_tiles.py does the rest per
lod0 tile with the helpers here.
"""

import json

import numpy as np
import shapely

import facades
from common import (PROP_CONIFER, PROP_STREET_LIGHT, PROP_TONE_DARK, PROP_TONE_GREEN, PROP_TONE_LIGHT,
                    PROP_TONE_RED, PROP_TREE, PROP_TREE_NARROW, RAW_DIR, project)

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
# Crown diameter as a share of the height.
CROWN_RATIO = {PROP_TREE: 0.62, PROP_TREE_NARROW: 0.38, PROP_CONIFER: 0.42}
GENUS_CROWN_RATIO = {"Platanus": 0.72, "Gleditsia": 0.68, "Quercus": 0.66, "Zelkova": 0.7}
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

# Street lights: one every LAMP_SPACING meters along every curb (the first
# half a spacing in), LAMP_SETBACK onto the sidewalk, and none closer than
# LAMP_MIN_GAP to another. Curbs around road islands shorter than
# LAMP_MIN_ISLAND get none. In and beside parks they're historic post-tops.
LAMP_SPACING = 35.0
LAMP_SETBACK = 0.6
LAMP_MIN_GAP = 12.0
LAMP_MIN_ISLAND = 40.0
LAMP_PARK_REACH = 4.0
COBRA_HEAD = (9.0, 2.6)  # pole height, arm length (m)
POST_TOP = (4.4, 0.0)

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

    dbh = np.where(dbh > 0, dbh, DEFAULT_DBH)
    height = np.minimum(3.0 + 0.9 * dbh ** 0.85, MAX_TREE_HEIGHT) * (0.9 + 0.2 * _hash(seed, 1))
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
    keep = np.ones(len(points), dtype=bool)
    tree = shapely.STRtree(shapely.points(points))
    pairs = tree.query(shapely.points(points), predicate="dwithin", distance=LAMP_MIN_GAP)
    for a, b in pairs.T:
        if a < b and keep[a]:
            keep[b] = False
    return points[keep], arms[keep]


def street_lights(points: np.ndarray, arms: np.ndarray, in_park: np.ndarray) -> dict:
    """Props for street lights at these points, with arms reaching along `arms`
    (east/north), post-tops where in_park."""
    seed = location_seed(points)
    height = np.where(in_park, POST_TOP[0], COBRA_HEAD[0]) * (0.95 + 0.1 * _hash(seed, 16))
    arm = np.where(in_park, POST_TOP[1], COBRA_HEAD[1])
    # Godot: x east, z south; the arm reaches along (sin yaw, cos yaw) there.
    yaw = np.arctan2(arms[:, 0], -arms[:, 1])
    return {"en": points, "height": height, "width": arm, "trunk": np.zeros(len(points)),
            "type": np.full(len(points), PROP_STREET_LIGHT, dtype=np.int8),
            "tone": in_park.astype(np.int8), "seed": seed, "yaw": yaw}


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
