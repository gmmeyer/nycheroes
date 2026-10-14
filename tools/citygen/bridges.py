"""Bridges: decks that sit at each bridge's height over the water and ramp down
to the street on land, with parapets and support columns, and towers and
cables on the big suspension bridges.

Outlines come from the planimetric Transportation Structures dataset (bridges
are feature code 2300). Only bridges that cross water and have land at both
ends are built, which also leaves out bridges to New Jersey and Nassau County
(ocean in this world). Heights of the major bridges are rounded public figures.

build(land, terrain, sizes) returns, per LOD level, the bridge triangles bucketed by tile:
{level: {(i, j): (pos, uv, uv2, front)}} in Godot world space.
"""

import numpy as np
import shapely
from shapely.geometry import shape

from common import (CURB_HEIGHT, GROUND_ROAD, STRUCTURE_CABLE, STRUCTURE_CONCRETE, STRUCTURE_STONE,
                    MeshBuilder, lines_of, load_features, polygons_of, project, triangles_of)

BRIDGE_CODE = "2300"
# Name in the data -> (style, deck height above the water, tower top above the
# water, main span between the towers), meters. "girder" bridges get columns
# but no towers.
MAJOR_BRIDGES = {
    "Brooklyn Bridge": ("stone_suspension", 41.0, 84.0, 486.0),
    "Manhatten Bridge": ("suspension", 41.0, 102.0, 448.0),  # sic, as spelled in the data
    "Williamsburg Bridge": ("suspension", 41.0, 102.0, 488.0),
    "Verrazano-Narrows Bridge": ("suspension", 69.0, 211.0, 1298.0),
    "THROGS NECK BRIDGE": ("suspension", 43.0, 109.0, 549.0),
    "BRONX-WHITESTONE BRIDGE": ("suspension", 46.0, 115.0, 701.0),
    # The RFK outline covers the whole Y-shaped complex, so towers can't be placed reliably.
    "ROBERT F KENNEDY BRG": ("girder", 43.0, 0.0, 0.0),
    "ED KOCH QUEENSBORO BRIDGE": ("girder", 40.0, 0.0, 0.0),
    "HENRY HUDSON BRIDGE": ("girder", 43.0, 0.0, 0.0),
    "Washington Bridge": ("girder", 46.0, 0.0, 0.0),
    "ALEXANDER HAMILTON BRIDGE": ("girder", 31.0, 0.0, 0.0),
    "Gil Hodges Memorial Bridge": ("girder", 17.0, 0.0, 0.0),
    "Cross Bay Bridge": ("girder", 17.0, 0.0, 0.0),
    "NORTH CHANNEL BRIDGE": ("girder", 18.0, 0.0, 0.0),
}
# Bridges to New Jersey or Nassau County.
EXCLUDED = {"George Washington Bridge", "Bayonne Bridge", "Outerbridge Crossing",
            "Atlantic Beach Bridge", "Ellis Island Bridge"}

MIN_WATER_AREA = 150.0
DECK_THICKNESS = 2.0
PARAPET_HEIGHT = 1.1
COLUMN_SPACING = 60.0
SUSPENDER_SPACING = 12.0
# A main span never takes up more than this fraction of the water it crosses
# (the towers stand in the water, a little out from each shore).
MAX_SPAN_OF_WATER = 0.9
WATER_FOOTING_Y = -8.0
ALL_LEVELS = ("lod0", "lod1", "lod2")


def build(land, terrain, level_sizes: dict) -> dict:
    """Bridge triangles for every level, bucketed by tile of that level's size.
    `terrain` is a terrain.Terrain (ground and water heights)."""
    shapely.prepare(land)
    features = [f for f in load_features("transport_structures")
                if str(f["properties"].get("feat_code")) == BRIDGE_CODE
                and f["properties"].get("name") not in EXCLUDED]
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in features], dtype=object)))

    builders = {level: MeshBuilder() for level in ALL_LEVELS}
    built = []
    for feat, geom in zip(features, geoms):
        name = feat["properties"].get("name") or "NO NAME"
        for poly in polygons_of(geom, min_area=50.0):
            if _build_bridge(shapely.orient_polygons(poly), name, land, terrain, builders):
                built.append(name)
    named = sorted({n for n in built if n != "NO NAME"})
    print(f"  bridges: {len(built)} decks ({len(named)} named: {', '.join(named)})", flush=True)

    buckets = {}
    for level, size in level_sizes.items():
        buckets[level] = _bucket(builders[level], size)
    return buckets


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


def _build_bridge(poly, name: str, land, terrain, builders: dict) -> bool:
    water = shapely.difference(poly, land)
    if water.area < MIN_WATER_AREA:
        return False  # an overpass over land; those stay at street level for now

    # The whole bridge's direction (columns run along it), and the biggest
    # stretch over water, where a suspension bridge's towers stand. (Without
    # depth data the main span is centered on it; the real channel can be
    # off-center, as at the Throgs Neck.)
    u, v, center, length = _axis(poly)
    width = float(np.clip(poly.area / max(length, 1.0), 6.0, 60.0))
    ring = np.asarray(poly.exterior.coords)[:, :2]
    s_range = (float(((ring - center) @ u).min()), float(((ring - center) @ u).max()))
    main_span = max(polygons_of(water, MIN_WATER_AREA) or [water], key=lambda p: p.area)
    span_u, _, span_center, span_length = _axis(main_span)
    span_width = float(np.clip(main_span.area / max(span_length, 1.0), 6.0, 60.0))

    # Land under the bridge: approaches (land meeting the water on one side)
    # ramp down with distance from the water, reaching the street at their far
    # end; islands the bridge crosses (water on both sides) stay at full height.
    ramps = []
    for part in polygons_of(shapely.intersection(poly, land), min_area=5.0):
        if _shores(part, water) != 1:
            continue
        part_ring = np.asarray(part.exterior.coords)[:, :2]
        reach = float(shapely.distance(shapely.points(part_ring), water).max())
        shapely.prepare(part)
        ramps.append((part, max(reach, 1.0)))
    if len(ramps) < 2:
        return False  # doesn't reach land at both ends

    style, clearance, tower_top, main_span_length = MAJOR_BRIDGES.get(
        name, ("girder", float(np.clip(6.0 + 0.03 * span_length, 6.0, 20.0)), 0.0, 0.0))
    # Clearance is over the water, which inland can be well above sea level.
    water_level = max(0.0, float(terrain.raw(shapely.get_coordinates(shapely.point_on_surface(main_span)))[0]))
    deck_top = water_level + clearance

    def deck_y(points: np.ndarray) -> np.ndarray:
        y = np.full(len(points), deck_top)
        geoms = shapely.points(points)
        for part, reach in ramps:
            # Deck points sit right on the approach's edge, where floating point
            # puts them a hair outside; a small tolerance keeps them in.
            inside = shapely.dwithin(part, geoms, 0.5)
            if inside.any():
                t = np.clip(shapely.distance(geoms[inside], water) / reach, 0.0, 1.0)
                street = terrain.height(points[inside]) - CURB_HEIGHT  # meet the road, not the sidewalk
                y[inside] = street + (np.maximum(deck_top, street + 1.0) - street) * (1.0 - t * t * (3.0 - 2.0 * t))
        return y

    _add_deck(poly, deck_y, builders)
    suspended = style.endswith("suspension") and span_length > 100.0
    if suspended:
        main_span_length = min(main_span_length, span_length * MAX_SPAN_OF_WATER)
        _add_suspension(poly, span_center, span_u, span_width, main_span_length, deck_y, deck_top, tower_top,
                        style.startswith("stone"), builders)
    _add_columns(poly, center, u, v, width, s_range, main_span if suspended else None, deck_y, land, terrain, builders)
    return True


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


def _add_deck(poly, deck_y, builders: dict) -> None:
    for level, spacing in DECK_SPACING.items():
        dense = shapely.segmentize(poly, spacing)
        tris = triangles_of(dense)
        if tris is None:
            continue
        y = deck_y(tris.reshape(-1, 2)).reshape(-1, 3)
        top = np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        builders[level].add(top, uv, (GROUND_ROAD, 0.0), (0.0, 1.0, 0.0))
        detailed = level != "lod2"
        if detailed:
            bottom = top - np.array([0.0, DECK_THICKNESS, 0.0])
            builders[level].add(bottom, uv, (STRUCTURE_CONCRETE, 0.0), (0.0, -1.0, 0.0))
        for ring in (dense.exterior, *dense.interiors):
            coords = np.asarray(ring.coords)[:, :2]
            ring_y = deck_y(coords)
            # Sides of the deck, rising into a parapet up close.
            top_y = ring_y + PARAPET_HEIGHT if detailed else ring_y
            builders[level].add_walls(coords, ring_y - DECK_THICKNESS, top_y, (STRUCTURE_CONCRETE, 0.0))


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


def _reach_on_deck(poly, center, u, start, direction, limit) -> float:
    """How far the deck continues from `start` along `u` in `direction`, up to `limit`."""
    steps = np.arange(2.0, limit, 2.0)
    if len(steps) == 0:
        return 0.0
    on_deck = shapely.covers(poly, shapely.points(center + np.outer(start + direction * steps, u)))
    off = np.flatnonzero(~on_deck)
    return float(steps[off[0] - 1]) if len(off) and off[0] > 0 else (0.0 if len(off) else float(steps[-1]))


def _add_columns(poly, center, u, v, width, s_range, suspended, deck_y, land, terrain, builders) -> None:
    """Columns under the deck every COLUMN_SPACING along it, except under a
    suspended span (`suspended`, a shape or None)."""
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
            _add_box(base, u, half, half, bottom, top, STRUCTURE_CONCRETE, ("lod0", "lod1"), builders)


def _add_box(base_en, u, half_u, half_v, y0, y1, kind, levels, builders) -> None:
    """A box standing on (east, north) `base_en`, turned to `u`, from y0 to y1 (no bottom face)."""
    v = np.array([-u[1], u[0]])
    corners = [base_en + u * su * half_u + v * sv * half_v for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    ring = np.array(corners + [corners[0]])
    for level in levels:
        builders[level].add_walls(ring, y0, y1, (kind, 0.0))
        builders[level].add_flat([shapely.Polygon(corners)], y1, (kind, 0.0))


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
