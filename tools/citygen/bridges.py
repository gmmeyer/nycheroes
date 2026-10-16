"""Bridges: decks that sit at each bridge's height over the water and ramp down
to the street on land, with parapets and support columns, and towers and
cables on the big suspension bridges.

Outlines come from the planimetric Transportation Structures dataset (bridges
are feature code 2300). Only bridges that cross water and have land at both
ends are built, which also leaves out bridges to New Jersey and Nassau County
(ocean in this world); outlines mostly over land (a highway viaduct that
crosses a canal on its way) are overpasses (overpasses.py). Heights of the
major bridges are rounded public figures; their towers stand where
OpenStreetMap's mappers put them (TOWERS). The most famous ones are built by
hand over their main spans (bridge_landmarks.py: the Brooklyn, Manhattan,
Hell Gate and High Bridges), the generic deck only on their approaches.

build(land, terrain, sizes) returns, per LOD level, the bridge triangles bucketed by tile:
{level: {(i, j): (pos, uv, uv2, front)}} in Godot world space; "lamps" and
"post_lamps" (historic lamps) hold street lights along decks per lod0 tile,
"hand_made" the hand-made bridges' sections (east/north polygons).
"""

import numpy as np
import shapely
from shapely.geometry import shape

import bridge_landmarks
import props
from common import (CURB_HEIGHT, GROUND_ROAD, STRUCTURE_CABLE, STRUCTURE_CONCRETE, STRUCTURE_RAIL, STRUCTURE_STONE,
                    MeshBuilder, lines_of, load_features, polygons_of, project, triangles_of)

BRIDGE_CODE = "2300"
# Name in the data -> (style, deck height above the water, tower top above the
# water, main span between the towers), meters. "girder" bridges get columns
# but no towers; "cantilever" ones (the Queensboro) steel towers over their
# piers with truss chords between; "cable_stayed" ones (the Kosciuszko) a
# tower with stay cables fanning out over a main and a back span.
MAJOR_BRIDGES = {
    # The Brooklyn Bridge's roadway at its towers (bridge_landmarks.CAMBER
    # raises it to 41.1 m mid-river).
    "Brooklyn Bridge": ("stone_suspension", 36.35, 84.3, 486.3),
    "Manhatten Bridge": ("suspension", 41.0, 102.0, 448.0),  # sic, as spelled in the data
    "Williamsburg Bridge": ("suspension", 41.0, 94.0, 488.0),
    "Verrazano-Narrows Bridge": ("suspension", 69.0, 211.0, 1298.0),
    "THROGS NECK BRIDGE": ("suspension", 43.0, 109.0, 549.0),
    "BRONX-WHITESTONE BRIDGE": ("suspension", 46.0, 115.0, 701.0),
    # The RFK's outline covers the whole Y-shaped complex; its suspension span
    # crosses Hell Gate between the towers in TOWERS.
    "ROBERT F KENNEDY BRG": ("suspension", 43.0, 96.0, 421.0),
    "ED KOCH QUEENSBORO BRIDGE": ("cantilever", 40.0, 107.0, 0.0),
    # A pair of single-tower cable-stayed spans (2017, 2019), the towers on the
    # Queens bank, 27 m over Newtown Creek: main span 190 m across the creek,
    # back span 115 m into Queens (NYSDOT; Roads & Bridges).
    "Kosciuszko Bridge": ("cable_stayed", 30.0, 90.0, 190.0),
    "HENRY HUDSON BRIDGE": ("girder", 43.0, 0.0, 0.0),
    "Washington Bridge": ("girder", 46.0, 0.0, 0.0),
    "ALEXANDER HAMILTON BRIDGE": ("girder", 31.0, 0.0, 0.0),
    "Gil Hodges Memorial Bridge": ("girder", 17.0, 0.0, 0.0),
    "Cross Bay Bridge": ("girder", 17.0, 0.0, 0.0),
    "NORTH CHANNEL BRIDGE": ("girder", 18.0, 0.0, 0.0),
    # Hand-made over their arches (bridge_landmarks.py): the Hell Gate's
    # deck top 145 ft over high water, the High Bridge's walkway 140 ft.
    "Hellgate Bridge": ("arch", 44.2, 67.1, 0.0),
    "High Bridge/Aqueduct Bridge": ("arch", 42.5, 0.0, 0.0),
}
# Bridges to New Jersey or Nassau County.
EXCLUDED = {"George Washington Bridge", "Bayonne Bridge", "Outerbridge Crossing",
            "Atlantic Beach Bridge", "Ellis Island Bridge"}
# Outlines the data leaves unnamed (or has only a scrap of), named by a point
# (latitude, longitude) on them.
NAMED_AT = {
    "Kosciuszko Bridge": (40.72765, -73.92899),  # the data names only a 149 m^2 scrap
}
# Where the towers stand (latitude, longitude): the centers of OpenStreetMap's
# bridge:support ways (ODbL), which match the main spans above to a few
# meters. The Queensboro's four are its piers (Manhattan, Roosevelt Island
# west and east, Queens). The Kosciuszko's is an estimate: on the Queens
# bank, 15 m inland, where the axis crosses it.
TOWERS = {
    "Brooklyn Bridge": ((40.7072684, -73.9983348), (40.7041035, -73.9943545)),
    "Manhatten Bridge": ((40.7088123, -73.9914889), (40.7051158, -73.9894365)),
    "Williamsburg Bridge": ((40.7143945, -73.9748202), (40.7127579, -73.9694585)),
    "Verrazano-Narrows Bridge": ((40.6040556, -74.0525057), (40.6086185, -74.0383771)),
    "THROGS NECK BRIDGE": ((40.8027528, -73.7936472), (40.7978062, -73.7935992)),
    "BRONX-WHITESTONE BRIDGE": ((40.8048870, -73.8315735), (40.7992136, -73.8279270)),
    "ROBERT F KENNEDY BRG": ((40.7813077, -73.9279451), (40.7780319, -73.9254442)),
    "ED KOCH QUEENSBORO BRIDGE": ((40.7588769, -73.9591299), (40.7572668, -73.9554167),
                                  (40.7564098, -73.9534525), (40.7550719, -73.9503566)),
    "Kosciuszko Bridge": ((40.72802, -73.92858),),
}
# The Kosciuszko's back span (m), on the far side of its tower from the main span.
BACK_SPAN = {"Kosciuszko Bridge": 115.0}

MIN_WATER_AREA = 150.0
# Outlines with less of their area over water than this share are overpasses
# (unless they're a major bridge).
OVERPASS_WATER_SHARE = 0.1
# Ends of a bridge that stop right at the shore (no land under the outline to
# ramp down over) ramp over the deck itself, as steep as this at most; such
# low bridges (drawbridges, causeways) get a lower default clearance.
SHORE_RAMP_GRADE = 0.08
SHORE_CONTACT = 1.0
DECK_THICKNESS = 2.0
PARAPET_HEIGHT = 1.1
COLUMN_SPACING = 60.0
SUSPENDER_SPACING = 12.0
# A main span never takes up more than this fraction of the water it crosses
# (the towers stand in the water, a little out from each shore).
MAX_SPAN_OF_WATER = 0.9
WATER_FOOTING_Y = -8.0
ALL_LEVELS = ("lod0", "lod1", "lod2")


def build(land, terrain, level_sizes: dict, approach=None) -> dict:
    """Bridge triangles for every level, bucketed by tile of that level's size.
    `terrain` is a terrain.Terrain (ground and water heights). approach(en)
    gives the height a bridge's approach comes down to at (N, 2) points on
    land: the street by default, or a raised road it goes on as
    (overpasses.Network.approach)."""
    shapely.prepare(land)
    features = [f for f in load_features("transport_structures")
                if (str(f["properties"].get("feat_code")) == BRIDGE_CODE and f["properties"].get("name") not in EXCLUDED)
                or f["properties"].get("name") in bridge_landmarks.OUTLINES]
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in features], dtype=object)))
    if approach is None:
        def approach(en):
            return terrain.height(en) - CURB_HEIGHT

    builders = {level: MeshBuilder() for level in ALL_LEVELS}
    builders["lamps"] = []  # (positions, heights, arm directions) per deck
    builders["post_lamps"] = []  # the same, historic post-tops (bridge_landmarks)
    builders["towers"] = set()  # bridges whose towers are built (some have more than one outline)
    builders["hand_made"] = []  # the sections bridge_landmarks builds (east/north polygons)
    built = []
    for feat, geom in zip(features, geoms):
        for poly in polygons_of(geom, min_area=50.0):
            name = outline_name(poly, feat["properties"].get("name"))
            if _build_bridge(shapely.orient_polygons(poly), name, land, terrain, builders, approach):
                built.append(name)
    named = sorted({n for n in built if n != "NO NAME"})
    print(f"  bridges: {len(built)} decks ({len(named)} named: {', '.join(named)})", flush=True)

    buckets = {}
    for level, size in level_sizes.items():
        buckets[level] = _bucket(builders[level], size)
    buckets["lamps"] = _bucket_lamps(builders["lamps"], level_sizes["lod0"])
    buckets["post_lamps"] = _bucket_lamps(builders["post_lamps"], level_sizes["lod0"])
    buckets["hand_made"] = builders["hand_made"]
    return buckets


def outline_name(poly, name) -> str:
    """An outline's name: from the data, or NAMED_AT."""
    for named, (lat, lon) in NAMED_AT.items():
        if shapely.dwithin(poly, project(shapely.Point(lon, lat)), 20.0):
            return named
    return name or "NO NAME"


def local_land(land, geom, margin: float = 10.0):
    """The land around a shape (overlays with the whole city's are slow)."""
    min_e, min_n, max_e, max_n = geom.bounds
    return shapely.make_valid(shapely.clip_by_rect(land, min_e - margin, min_n - margin, max_e + margin, max_n + margin))


def is_overpass(poly, water_area: float, name: str) -> bool:
    """Whether an outline (part) is an overpass rather than a bridge: too
    little water under it, or mostly over land and not a major bridge."""
    return water_area < MIN_WATER_AREA or (water_area < OVERPASS_WATER_SHARE * poly.area
                                           and name not in MAJOR_BRIDGES)


def _bucket_lamps(found: list, size: float) -> dict:
    """Deck lamps by lod0 tile: {(i, j): (positions (N, 2), heights, arms (N, 2))}."""
    if not found:
        return {}
    en = np.concatenate([f[0] for f in found])
    y = np.concatenate([f[1] for f in found])
    arms = np.concatenate([f[2] for f in found])
    ii = np.floor(en[:, 0] / size).astype(np.int64)
    jj = np.floor(-en[:, 1] / size).astype(np.int64)
    out = {}
    for key in set(zip(ii.tolist(), jj.tolist())):
        mask = (ii == key[0]) & (jj == key[1])
        out[key] = (en[mask], y[mask], arms[mask])
    return out


def _bucket(builder: MeshBuilder, size: float) -> dict:
    if builder.is_empty():
        return {}
    pos = np.concatenate(builder.pos)
    uv = np.concatenate(builder.uv)
    uv2 = np.concatenate(builder.uv2)
    front = np.concatenate(builder.front)
    centroid = pos.mean(axis=1)
    ii = np.floor(centroid[:, 0] / size).astype(np.int64)
    jj = np.floor(centroid[:, 2] / size).astype(np.int64)
    out = {}
    for key in set(zip(ii.tolist(), jj.tolist())):
        mask = (ii == key[0]) & (jj == key[1])
        out[key] = (pos[mask], uv[mask], uv2[mask], front[mask])
    return out


def _build_bridge(poly, name: str, land, terrain, builders: dict, approach) -> bool:
    land = local_land(land, poly)
    water = shapely.difference(poly, land)
    if is_overpass(poly, water.area, name):
        return False  # overpasses.py's

    # The whole bridge's direction (columns run along it), and the biggest
    # stretch over water, where a suspension bridge's towers stand if TOWERS
    # doesn't say (the main span is centered on it).
    u, v, center, length = _axis(poly)
    width = float(np.clip(poly.area / max(length, 1.0), 6.0, 60.0))
    ring = np.asarray(poly.exterior.coords)[:, :2]
    s_range = (float(((ring - center) @ u).min()), float(((ring - center) @ u).max()))
    main_span = max(polygons_of(water, MIN_WATER_AREA) or [water], key=lambda p: p.area)
    span_u, _, span_center, span_length = _axis(main_span)
    span_width = float(np.clip(main_span.area / max(span_length, 1.0), 6.0, 60.0))

    # Land under the bridge: approaches (land meeting the water on one side)
    # ramp down with distance from the water, reaching the street (or the
    # raised road the bridge goes on as) at their far end; islands the bridge
    # crosses (water on both sides) stay at full height. Each ramp is
    # (where, how far along it a point is (0 at the water, 1 at its end), the
    # height it comes down to).
    ramps = []
    ends = []  # the heights the approaches come down to at their far ends
    for part in polygons_of(shapely.intersection(poly, land), min_area=5.0):
        if _shores(part, water) != 1:
            continue
        part_ring = np.asarray(part.exterior.coords)[:, :2]
        away = shapely.distance(shapely.points(part_ring), water)
        reach = max(float(away.max()), 1.0)
        shapely.prepare(part)
        ramps.append((part, lambda geoms, reach=reach: shapely.distance(geoms, water) / reach, approach))
        ends.append(float(approach(part_ring[[int(np.argmax(away))]])[0]))
    shore_ends = _shore_ends(poly, land, [r[0] for r in ramps])
    if len(ramps) + len(shore_ends) < 2:
        return False  # doesn't reach land at both ends

    default_clearance = float(np.clip(6.0 + 0.03 * span_length, 6.0, 20.0))
    if shore_ends:
        default_clearance = float(np.clip(3.0 + 0.02 * span_length, 3.0, 10.0))
    style, clearance, tower_top, main_span_length = MAJOR_BRIDGES.get(name, ("girder", default_clearance, 0.0, 0.0))
    # Clearance is over the water, which inland can be well above sea level.
    water_level = max(0.0, float(terrain.raw(shapely.get_coordinates(shapely.point_on_surface(main_span)))[0]))
    deck_top = water_level + clearance
    if name not in MAJOR_BRIDGES and len(ends) >= 2:
        # A viaduct crossing a creek or canal on its way holds its height over it.
        deck_top = max(deck_top, min(ends))

    # Ends at the shore ramp down over the deck, from the street where it
    # meets the land.
    ramp_length = float(np.clip(clearance / SHORE_RAMP_GRADE, 20.0, 0.3 * length))
    for contact in shore_ends:
        region = shapely.intersection(poly, shapely.buffer(contact, ramp_length))
        shapely.prepare(region)
        street = float(approach(shapely.get_coordinates(shapely.line_interpolate_point(contact, 0.5, normalized=True)))[0])
        ramps.append((region, lambda geoms, contact=contact: 1.0 - shapely.distance(geoms, contact) / ramp_length,
                      lambda en, street=street: np.full(len(en), street)))

    towers = _towers(name, poly)
    landmark = bridge_landmarks.BRIDGES.get(name)
    if landmark is not None and name not in TOWERS:
        towers = bridge_landmarks.towers_of(name)
        towers = towers if shapely.dwithin(poly, shapely.points(towers), 30.0).all() else np.zeros((0, 2))
    camber = bridge_landmarks.CAMBER.get(name, 0.0) if len(towers) == 2 else 0.0

    def deck_y(points: np.ndarray) -> np.ndarray:
        y = np.full(len(points), deck_top)
        if camber:
            # Rising from the towers to mid-span.
            middle, axis = towers.mean(axis=0), towers[1] - towers[0]
            k = np.clip(1.0 - (((points - middle) @ axis) / (axis @ axis / 2)) ** 2, 0.0, 1.0)
            y += camber * k
        geoms = shapely.points(points)
        for region, along, comes_to in ramps:
            # Deck points sit right on the approach's edge, where floating point
            # puts them a hair outside; a small tolerance keeps them in.
            inside = shapely.dwithin(region, geoms, 0.5)
            if inside.any():
                t = np.clip(along(geoms[inside]), 0.0, 1.0)
                street = comes_to(points[inside])  # meet the road, not the sidewalk
                y[inside] = street + (np.maximum(deck_top, street + 1.0) - street) * (1.0 - t * t * (3.0 - 2.0 * t))
        return y

    # A hand-made bridge takes over its section; the generic deck stays on
    # the rest, its sides only along the outline (it just ends at the section).
    hand_made = None
    if landmark is not None and len(towers) == 2:
        hand_made = landmark(bridge_landmarks.Site(name, poly, towers, deck_y, terrain, land))
    section = hand_made.section() if hand_made else None
    road = name not in bridge_landmarks.NOT_ROADS
    rest = shapely.difference(poly, section) if section is not None else poly
    # Approaches built of masonry (the Brooklyn Bridge's) get stone sides and piers.
    masonry = (STRUCTURE_STONE, float(bridge_landmarks.PALETTES[name])) if name in bridge_landmarks.MASONRY else None
    _add_deck(rest, deck_y, builders, sides=poly.boundary if section is not None else None,
              ballast=None if road else bridge_landmarks.PALETTES.get(name, 0), stone=masonry)
    if road:
        lamps = props.deck_lamps(np.asarray(poly.exterior.coords)[:, :2], deck_y)
        if section is not None:
            off = ~shapely.dwithin(section, shapely.points(lamps[0]), 2.0)
            lamps = tuple(part[off] for part in lamps)
        builders["lamps"].append(lamps)
    held = None  # where cables hold the deck up (no columns)
    if hand_made:
        held = section
        if name not in builders["towers"]:
            builders["towers"].add(name)
            built = hand_made.build(builders)
            builders["hand_made"].append(built.section)
            builders["lamps"] += built.cobra_heads
            builders["post_lamps"] += built.post_tops
    elif style.endswith("suspension") and len(towers) == 2:
        tower_u = (towers[1] - towers[0]) / np.linalg.norm(towers[1] - towers[0])
        middle = towers.mean(axis=0)
        span = float(np.linalg.norm(towers[1] - towers[0]))
        tower_width = _width_at(poly, middle, np.array([-tower_u[1], tower_u[0]]), span_width)
        held = _span_box(middle, tower_u, span, tower_width)
        if name not in builders["towers"]:
            builders["towers"].add(name)
            _add_suspension(poly, middle, tower_u, tower_width, span, deck_y, deck_top, tower_top,
                            style.startswith("stone"), builders)
    elif style.endswith("suspension") and span_length > 100.0:
        main_span_length = min(main_span_length, span_length * MAX_SPAN_OF_WATER)
        held = main_span
        _add_suspension(poly, span_center, span_u, span_width, main_span_length, deck_y, deck_top, tower_top,
                        style.startswith("stone"), builders)
    elif style == "cantilever" and len(towers) >= 2:
        if name not in builders["towers"]:
            builders["towers"].add(name)
            _add_cantilever(poly, towers, span_width, deck_y, deck_top, tower_top, builders)
    elif style == "cable_stayed" and len(towers):
        held = _add_cable_stayed(poly, towers[0], main_span, main_span_length, BACK_SPAN.get(name, 0.5 * main_span_length),
                                 deck_y, tower_top, name not in builders["towers"], builders)
        builders["towers"].add(name)
    _add_columns(poly, center, u, v, width, s_range, held, deck_y, land, terrain, builders, masonry)
    return True


def _shore_ends(poly, land, ramps: list) -> list:
    """Where a bridge's outline stops at the shore with no land under it to
    ramp down over: one line per such end."""
    contact = shapely.intersection(poly.boundary, shapely.buffer(land, SHORE_CONTACT))
    if contact.geom_type == "MultiLineString":
        contact = shapely.line_merge(contact)
    pieces = [line for line in lines_of(contact) if line.length >= 3.0]
    if not pieces:
        return []
    covered = shapely.union_all([shapely.buffer(r, 5.0) for r in ramps]) if ramps else shapely.Polygon()
    # Bits of shore close together are one end (on short bridges, closer still).
    gap = min(25.0, 0.2 * _axis(poly)[3])
    ends = []
    for cluster in polygons_of(shapely.union_all([shapely.buffer(line, gap) for line in pieces])):
        lines = [line for line in pieces if shapely.intersects(cluster, line)]
        if any(shapely.intersects(covered, line) for line in lines):
            continue  # an approach's own shore
        ends.append(max(lines, key=lambda line: line.length))
    return ends


def _towers(name: str, poly) -> np.ndarray:
    """The bridge's towers (TOWERS) on or near this outline, (N, 2) east/north."""
    if name not in TOWERS:
        return np.zeros((0, 2))
    points = shapely.get_coordinates(project(shapely.points([(lon, lat) for lat, lon in TOWERS[name]])))
    near = shapely.dwithin(poly, shapely.points(points), 30.0)
    return points if near.all() else points[near]


def _width_at(poly, point: np.ndarray, across: np.ndarray, default: float) -> float:
    """The deck's width across `point` (the piece of a cross line through it)."""
    line = shapely.LineString([point - across * 80.0, point + across * 80.0])
    pieces = lines_of(shapely.intersection(line, poly))
    if not pieces:
        return default
    best = min(pieces, key=lambda p: shapely.distance(p, shapely.Point(point)))
    return float(np.clip(best.length, 6.0, 60.0))


def _span_box(middle: np.ndarray, u: np.ndarray, span: float, width: float):
    """The rectangle a main span hangs over, with a margin."""
    v = np.array([-u[1], u[0]])
    a, b = span / 2 + 10.0, width / 2 + 10.0
    return shapely.Polygon([middle + u * su * a + v * sv * b for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))])


def _axis(geom):
    """Direction (unit vector along the long side of its minimum rotated
    rectangle), perpendicular, center, and length of a shape."""
    rect = np.asarray(shapely.minimum_rotated_rectangle(geom).exterior.coords)[:4]
    sides = rect[1:] - rect[:-1]
    longest = int(np.argmax(np.hypot(sides[:, 0], sides[:, 1])))
    length = float(np.hypot(*sides[longest]))
    u = sides[longest] / max(length, 1e-6)
    return u, np.array([-u[1], u[0]]), rect.mean(axis=0), length


def _shores(part, water) -> int:
    """How many separate shores a piece of land under a bridge has: 1 for an
    approach, 2 or more for an island the bridge crosses. Bits of shoreline
    within 50 m of each other count as one shore (jagged edges, pier slips)."""
    contact = shapely.intersection(part.boundary, shapely.buffer(water, 0.5))
    if contact.geom_type == "MultiLineString":
        contact = shapely.line_merge(contact)
    pieces = [line for line in lines_of(contact) if line.length >= 10.0]
    if len(pieces) < 2:
        return len(pieces)
    return len(polygons_of(shapely.union_all([shapely.buffer(line, 25.0) for line in pieces])))


# How finely decks follow their height profile, per level (meters between points).
DECK_SPACING = {"lod0": 8.0, "lod1": 16.0, "lod2": 40.0}


def _add_deck(poly, deck_y, builders: dict, sides=None, ballast=None, stone=None) -> None:
    """A deck over `poly` at deck_y: road top, underside, and sides rising
    into parapets up close. `sides` (a line) keeps the sides to the edges
    along it. Rail decks (`ballast`: the bridge's palette, see
    bridge_landmarks) have a concrete top under a ballast bed; `stone` (a
    uv2 pair) makes the sides masonry."""
    for level, spacing in DECK_SPACING.items():
        for part in polygons_of(poly, 1.0):
            _add_deck_part(level, shapely.segmentize(part, spacing), deck_y, builders, sides, ballast, stone)


def _add_deck_part(level, dense, deck_y, builders: dict, sides, ballast, stone) -> None:
    tris = triangles_of(dense)
    if tris is None:
        return
    y = deck_y(tris.reshape(-1, 2)).reshape(-1, 3)
    top = np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1)
    uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
    builders[level].add(top, uv, (GROUND_ROAD if ballast is None else STRUCTURE_CONCRETE, 0.0), (0.0, 1.0, 0.0))
    detailed = level != "lod2"
    if ballast is not None and detailed:
        bed = triangles_of(shapely.buffer(dense, -1.0, join_style="mitre"))
        if bed is not None:
            bed_y = deck_y(bed.reshape(-1, 2)).reshape(-1, 3) + 0.3
            builders[level].add(np.stack([bed[..., 0], bed_y, -bed[..., 1]], axis=-1),
                                np.stack([bed[..., 0], -bed[..., 1]], axis=-1),
                                (STRUCTURE_RAIL, ballast + 8.0 * bridge_landmarks.BALLAST), (0.0, 1.0, 0.0))
    if detailed:
        bottom = top - np.array([0.0, DECK_THICKNESS, 0.0])
        builders[level].add(bottom, uv, (STRUCTURE_CONCRETE, 0.0), (0.0, -1.0, 0.0))
    for ring in (dense.exterior, *dense.interiors):
        coords = np.asarray(ring.coords)[:, :2]
        runs = [coords]
        if sides is not None:
            # Only the edges along `sides`, in runs of consecutive segments.
            middles = shapely.points((coords[:-1] + coords[1:]) / 2)
            along = shapely.dwithin(sides, middles, 0.05)
            runs = [coords[a:b + 1] for a, b in _true_runs(along)]
        for run in runs:
            run_y = deck_y(run)
            # Sides of the deck, rising into a parapet up close.
            top_y = run_y + PARAPET_HEIGHT if detailed else run_y
            builders[level].add_walls(run, run_y - DECK_THICKNESS, top_y, stone or (STRUCTURE_CONCRETE, 0.0))


def _true_runs(mask: np.ndarray) -> list:
    """(start, end) of each run of True in a boolean array, end exclusive."""
    edges = np.diff(np.concatenate([[0], mask.astype(np.int8), [0]]))
    return list(zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)))


def _add_suspension(poly, center, u, width, span, deck_y, deck_top, tower_top, stone, builders) -> None:
    """Two towers `span` apart along `u`, centered on `center`, main cables
    between them, side cables down to anchors on the approaches, and
    suspenders up close."""
    v = np.array([-u[1], u[0]])
    t2 = span * 0.5
    t1 = -t2
    leg = float(np.clip(width * 0.06, 1.5, 4.5))
    cable_offset = width * 0.5 + (2.0 if stone else leg)
    for s in (t1, t2):
        base = center + u * s
        if stone:
            _add_box(base, u, 7.0, width * 0.5 + 4.0, WATER_FOOTING_Y, tower_top, STRUCTURE_STONE, ALL_LEVELS, builders)
            continue
        for side in (-1.0, 1.0):
            _add_box(base + v * side * (width * 0.5 + leg), u, leg, leg, WATER_FOOTING_Y, tower_top,
                     STRUCTURE_CONCRETE, ALL_LEVELS, builders)
        half_beam = width * 0.5 + 2.0 * leg
        for y0 in (deck_top - DECK_THICKNESS - 4.0, (deck_top + tower_top) * 0.5, tower_top - 4.0):
            _add_box(base, u, leg, half_beam, y0, y0 + 3.0, STRUCTURE_CONCRETE, ALL_LEVELS, builders)

    half = t2
    cable_top = tower_top - 1.5
    cable_low = deck_top + 2.5
    side_span = 0.45 * (t2 - t1)
    anchors = (t1 - _reach_on_deck(poly, center, u, t1, -1.0, side_span),
               t2 + _reach_on_deck(poly, center, u, t2, 1.0, side_span))
    for side in (-1.0, 1.0):
        offset = v * side * cable_offset

        def cable(s_values, heights):
            en = center + np.outer(s_values, u) + offset
            return np.column_stack([en[:, 0], heights, -en[:, 1]])

        s_main = np.linspace(t1, t2, 33)
        y_main = cable_top - (cable_top - cable_low) * (1.0 - (s_main / half) ** 2)
        _add_tube(cable(s_main, y_main), 0.6, ALL_LEVELS, builders)
        for anchor, tower in ((anchors[0], t1), (anchors[1], t2)):
            if abs(anchor - tower) < 20.0:
                continue
            s_side = np.linspace(tower, anchor, 13)
            anchor_y = float(deck_y((center + u * anchor)[None, :])[0]) + 1.0
            k = np.linspace(0.0, 1.0, 13)
            y_side = cable_top + (anchor_y - cable_top) * k - 6.0 * k * (1.0 - k)
            _add_tube(cable(s_side, y_side), 0.6, ALL_LEVELS, builders)
        for s in np.arange(t1 + SUSPENDER_SPACING, t2 - SUSPENDER_SPACING * 0.5, SUSPENDER_SPACING):
            top_y = cable_top - (cable_top - cable_low) * (1.0 - (s / half) ** 2)
            _add_box(center + u * s + offset, u, 0.15, 0.15, deck_top, top_y, STRUCTURE_CABLE, ("lod0",), builders)


def _add_cantilever(poly, towers: np.ndarray, width: float, deck_y, deck_top, tower_top, builders) -> None:
    """Steel towers over a cantilever bridge's piers, the truss's top chords
    dipping between them toward the deck, and posts between chords and deck
    up close."""
    for k, base in enumerate(towers):
        # Lean the tower across the deck as the bridge runs here.
        ahead = towers[min(k + 1, len(towers) - 1)] - towers[max(k - 1, 0)]
        u = ahead / max(np.linalg.norm(ahead), 1e-6)
        v = np.array([-u[1], u[0]])
        deck_width = _width_at(poly, base, v, width)
        leg = 2.5
        for side in (-1.0, 1.0):
            _add_box(base + v * side * (deck_width * 0.5 + leg), u, leg, leg, WATER_FOOTING_Y, tower_top,
                     STRUCTURE_CONCRETE, ALL_LEVELS, builders)
        for y0 in (deck_top - DECK_THICKNESS - 3.0, deck_top + 12.0, tower_top - 6.0):
            _add_box(base, u, leg, deck_width * 0.5 + 2.0 * leg, y0, y0 + 2.5, STRUCTURE_CONCRETE, ALL_LEVELS, builders)
    chord_low = deck_top + 10.0
    for a, b in zip(towers[:-1], towers[1:]):
        u = (b - a) / np.linalg.norm(b - a)
        v = np.array([-u[1], u[0]])
        middle = (a + b) / 2
        deck_width = _width_at(poly, middle, v, width)
        k = np.linspace(0.0, 1.0, 17)
        chord_y = tower_top - 4.0 - (tower_top - 4.0 - chord_low) * np.sin(np.pi * k) ** 0.7
        for side in (-1.0, 1.0):
            en = a + np.outer(k, b - a) + v * side * (deck_width * 0.5 + 2.5)
            _add_tube(np.column_stack([en[:, 0], chord_y, -en[:, 1]]), 1.0, ALL_LEVELS, builders)
            for j in range(1, len(k) - 1):
                _add_box(en[j], u, 0.4, 0.4, deck_top, chord_y[j], STRUCTURE_CABLE, ("lod0", "lod1"), builders)


def _add_cable_stayed(poly, tower, main_span, main_length, back_length, deck_y, tower_top, add_tower, builders):
    """A cable-stayed bridge's tower (two legs either side of each deck under
    it) at `tower`, stays fanning from the top of each leg to the deck's edges
    over the main span (toward the water, `main_span`) and the back span.
    Returns the stretch the stays hold up (no columns there)."""
    to_water = np.asarray(main_span.centroid.coords)[0] - tower
    u = to_water / max(np.linalg.norm(to_water), 1e-6)
    # Follow the deck's own direction (the outline's axis), facing the water.
    axis_u, _, _, _ = _axis(poly)
    u = axis_u if axis_u @ u > 0 else -axis_u
    v = np.array([-u[1], u[0]])
    cross = shapely.LineString([tower - v * 80.0, tower + v * 80.0])
    decks = [p for p in lines_of(shapely.intersection(cross, poly)) if p.length >= 8.0]
    stays = 14
    for piece in decks:
        ends = shapely.get_coordinates(piece)
        lo, hi = sorted(float((e - tower) @ v) for e in ends)
        for edge in (lo - 1.5, hi + 1.5):
            base = tower + v * edge
            if add_tower:
                _add_box(base, u, 1.6, 1.0, -2.0, tower_top, STRUCTURE_CONCRETE, ALL_LEVELS, builders)
            for direction, length in ((1.0, main_length), (-1.0, back_length)):
                reach = np.linspace(22.0, 0.94 * length, stays)
                anchors = tower + np.outer(direction * reach, u) + v * (edge - np.sign(edge - (lo + hi) / 2) * 1.0)
                anchor_y = deck_y(anchors) + 0.5
                top_y = np.linspace(tower_top - 4.0, tower_top - 26.0, stays)
                for anchor, ay, ty in zip(anchors, anchor_y, top_y):
                    _add_tube(np.array([[base[0], ty, -base[1]], [anchor[0], ay, -anchor[1]]]), 0.12,
                              ("lod0", "lod1"), builders)
        if add_tower:
            # A strut under the deck and one near the top between the legs.
            middle = tower + v * (lo + hi) / 2
            half = (hi - lo) / 2 + 1.5
            y = float(deck_y(middle[None])[0])
            for y0 in (y - DECK_THICKNESS - 2.5, tower_top - 12.0):
                _add_box(middle, u, 1.2, half, y0, y0 + 2.0, STRUCTURE_CONCRETE, ALL_LEVELS, builders)
    back = tower - u * back_length
    front = tower + u * main_length
    a, b = (back, front)
    across = 60.0
    return shapely.Polygon([a - v * across, b - v * across, b + v * across, a + v * across])


def _reach_on_deck(poly, center, u, start, direction, limit) -> float:
    """How far the deck continues from `start` along `u` in `direction`, up to `limit`."""
    steps = np.arange(2.0, limit, 2.0)
    if len(steps) == 0:
        return 0.0
    on_deck = shapely.covers(poly, shapely.points(center + np.outer(start + direction * steps, u)))
    off = np.flatnonzero(~on_deck)
    return float(steps[off[0] - 1]) if len(off) and off[0] > 0 else (0.0 if len(off) else float(steps[-1]))


def _add_columns(poly, center, u, v, width, s_range, suspended, deck_y, land, terrain, builders, stone=None) -> None:
    """Columns under the deck every COLUMN_SPACING along it, except under a
    suspended span (`suspended`, a shape or None); `stone` (a uv2 pair) makes
    them wider masonry piers."""
    s_min, s_max = s_range
    if suspended is not None:
        suspended = shapely.buffer(suspended, 10.0)
        shapely.prepare(suspended)
    offsets = (0.0,) if width < 18.0 else (-width * 0.25, width * 0.25)
    half = float(np.clip(width * 0.08, 1.0, 2.5))
    for s in np.arange(s_min + COLUMN_SPACING * 0.5, s_max, COLUMN_SPACING):
        for offset in offsets:
            base = center + u * s + v * offset
            point = shapely.Point(base)
            if not shapely.covers(poly, point):
                continue
            if suspended is not None and shapely.covers(suspended, point):
                continue  # the suspension span hangs from its cables
            top = float(deck_y(base[None, :])[0]) - DECK_THICKNESS
            street = float(terrain.height(base[None, :])[0])
            on_land = shapely.covers(land, point)
            bottom = street - 1.0 if on_land else WATER_FOOTING_Y
            if top - max(bottom, street) < 3.0:
                continue
            if stone:
                _add_box(base, u, half * 1.5, half * 2.5, bottom, top, stone, ("lod0", "lod1"), builders)
            else:
                _add_box(base, u, half, half, bottom, top, STRUCTURE_CONCRETE, ("lod0", "lod1"), builders)


def _add_box(base_en, u, half_u, half_v, y0, y1, kind, levels, builders) -> None:
    """A box standing on (east, north) `base_en`, turned to `u`, from y0 to y1 (no bottom face)."""
    v = np.array([-u[1], u[0]])
    corners = [base_en + u * su * half_u + v * sv * half_v for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    ring = np.array(corners + [corners[0]])
    uv2 = kind if isinstance(kind, tuple) else (kind, 0.0)
    for level in levels:
        builders[level].add_walls(ring, y0, y1, uv2)
        builders[level].add_flat([shapely.Polygon(corners)], y1, uv2)


def _add_tube(points: np.ndarray, radius: float, levels, builders) -> None:
    """A square tube along a polyline of Godot-space points (for cables)."""
    pos, uv, front = [], [], []
    for a, b in zip(points[:-1], points[1:]):
        direction = b - a
        length = np.linalg.norm(direction)
        if length < 1e-3:
            continue
        direction /= length
        side = np.cross(direction, [0.0, 1.0, 0.0])
        side = side / np.linalg.norm(side) if np.linalg.norm(side) > 1e-3 else np.array([1.0, 0.0, 0.0])
        up = np.cross(side, direction)
        for normal, tangent in ((side, up), (up, -side), (-side, -up), (-up, side)):
            corner = normal * radius
            edge = tangent * radius
            quad = [a + corner - edge, b + corner - edge, b + corner + edge, a + corner + edge]
            pos += [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]
            front += [normal, normal]
            uv += [[[0, 0], [length, 0], [length, 1]], [[0, 0], [length, 1], [0, 1]]]
    if not pos:
        return
    for level in levels:
        builders[level].add(np.array(pos), np.array(uv, dtype=np.float64), (STRUCTURE_CABLE, 0.0), np.array(front))
