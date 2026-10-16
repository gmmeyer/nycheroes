"""Stoops on rowhouse and walk-up fronts, up close (lod0 tiles): steps up to
the parlor floor between cheek walls, the front door on the landing, and the
low wall or iron fence along the front yard (the areaway).

build_tiles.py calls add() for every building it draws in full detail. A
building with stoop steps (facades.py: brownstones 8-10, later rows 3-7,
walk-ups 2-4, none behind shop fronts) gets one on its street front (the
footprint's, or for buildings drawn from the 3-D model, the model's own
outline at the ground): on the part of the front set furthest back (beside a
bay window, if there is one), at the lot line (walk-ups: in the middle),
narrower where that part is narrow. The steps go straight out toward the
street; there have to be CURB_CLEAR (4) meters left to the curb (the
walking lanes run 2.5 m from it) and no other building in the way, so where the
sidewalk and front yard are shallow the stoop has fewer steps, or none. Its
walls are then marked STOOP, so the shader draws the front door up on the
landing instead of at the sidewalk.

A rowhouse with a stoop and a front yard gets an areaway wall (or iron
fence) along the yard's edge, CURB_CLEAR from the curb (so neighbors' line up
and the stoops end at or inside it), from the far lot line to a gate GATE
wide beside the stoop: every yard has a way out, so heroes and thugs never get
boxed in between stoops, walls and fences.

A stoop is a few faces of the building's own surface (so it has collision,
and it's a ramp the hero walks up): the landing and the steps' slope (drawn
as steps by the shader), each cheek wall's outside reaching down to the
ground and its inside above the steps (two faces back to back, so they need
no thickness), and the doorway, a panel standing just off the wall: 20
triangles, 34 vertices; the areaway wall is two faces back to back, 4
triangles. The parts are told apart by facades.FRONT_PART in uv2.x; the
shader (shaders/building.gdshader, stoop()) paints them.

Uv per part (meters; the shader relies on them and on the measures below):
  STEPS       (across from the left side, out from the wall)
  STOOP_SIDE  (out from the wall, above the landing)
  CHEEK       (out from the wall, above the landing)
  DOORWAY     (across from its left edge, above the landing)
  AREAWAY     (along it, above the ground)
"""

import numpy as np
import shapely

import buildings3d
import facades

# Parts (facades.FRONT_PART field); same as the shader.
STEPS = 1
STOOP_SIDE = 2
CHEEK = 3
DOORWAY = 4
AREAWAY = 5

# Measures (m); the shader has the same.
LANDING = 1.2          # the landing's depth, from the wall
RISE, RUN = 0.19, 0.28  # each step
CHEEK_HEIGHT = 0.85    # the cheek walls stand this high above the steps
DOORWAY_WIDTH = 1.5
DOORWAY_HEIGHT = 3.0
DOORWAY_OUT = 0.08     # the doorway panel stands this far off the wall
AREAWAY_HEIGHT = 0.8

# Stoops are this wide (cheek walls included): brownstones' high stoops,
# lower ones, walk-ups'.
HIGH_WIDTH, LOW_WIDTH, WALKUP_WIDTH = 2.0, 1.75, 2.1
HIGH_STEPS = 6
MIN_STEPS = 2
MIN_WIDTH = 1.3
# The landing runs this far back into the house, to meet a wall that isn't
# quite where the footprint has it; the faces' feet sink this far below the
# ground.
BACK = 0.6
SINK = 0.5
# At least this far from the curb (walking lanes run LANE_OFFSET = 2.5 m in
# from it, pedestrians stray 0.8 m to either side; and heroes run there).
CURB_CLEAR = 4.0
# From the lot line (the party wall), or a bay, to the stoop's side.
EDGE = 0.15
# Other buildings' footprints may reach this far into the stoop (the 3-D
# model's walls and the footprints disagree by that much).
NEIGHBOR_SLACK = 0.3
# Front walls this close to the way the front faces count as facing it
# (cosine), for grouping a corner house's two fronts, and for the wall the
# stoop stands against.
SAME_FRONT = 0.64
STOOP_WALL = 0.96
# Areaway walls: the gate beside the stoop, and the least yard depth and wall
# length worth one.
GATE = 1.0
MIN_YARD = 1.5
MIN_AREAWAY = 0.8
# The 3-D model's outline at the ground must cover at least this share of
# the footprint's area (else its walls are too odd to stand a stoop on).
MODEL_OUTLINE_SHARE = 0.6
# ... and stand no further than this (m) from it.
MODEL_SHIFT = 2.5


def add(builder, index: int, facade: tuple, shape, w: dict, settings: dict, faces_street) -> tuple:
    """Adds building `index`'s stoop to `builder`, if it has one and there's
    room; returns its facade (archetype, flags, floor height, seed) with
    STOOP set if it did. `shape` is the 3-D model it's drawn from, or None;
    `w` build_tiles' worker data; faces_street(middles, outward) tells which
    walls face a street."""
    archetype, flags, floor_dm, seed = facade
    stoops = w["facades"].get("stoop")
    if stoops is None or archetype not in (facades.ROWHOUSE, facades.WALKUP):
        return facade
    steps = int(stoops[index])
    if steps < MIN_STEPS:
        return facade
    footprint = w["b"]["geoms"][index]
    poly = _largest(shapely.simplify(footprint, settings["building_tolerance"], preserve_topology=True))
    # Where the footprints are, from where the stoop stands (they and the 3-D
    # model are often a meter apart).
    shift = np.zeros(2)
    if shape is not None:
        poly = _model_outline(shape)
        if poly is not None and poly.area < MODEL_OUTLINE_SHARE * shapely.area(footprint):
            poly = None
        if poly is not None:
            shift = shapely.get_coordinates(shapely.centroid(footprint))[0] - shapely.get_coordinates(poly.centroid)[0]
            if np.hypot(*shift) > MODEL_SHIFT:
                poly = None
    if poly is None:
        return facade
    width = WALKUP_WIDTH if archetype == facades.WALKUP else (HIGH_WIDTH if steps >= HIGH_STEPS else LOW_WIDTH)
    place = _placement(poly, faces_street, width, seed, centered=archetype == facades.WALKUP)
    if place is None:
        return facade
    door, out, along, width = place
    stoop = _fit(w, index, poly, shift, door, out, along, width, steps)
    if stoop is None:
        return facade
    flags |= facades.STOOP

    def uv2_of(part):
        return facades.encode(archetype, flags | part * facades.FRONT_PART, floor_dm, seed)

    ground = w["ground"]["lod0"]
    _build(builder, door, out, along, width, stoop, ground, uv2_of)
    if archetype == facades.ROWHOUSE:
        areaway = _areaway(w, index, poly, shift, door, out, along, width)
        if areaway is not None:
            _build_areaway(builder, door, out, along, areaway, ground, uv2_of)
    return archetype, flags, floor_dm, seed


def _largest(geom):
    """The biggest polygon in `geom`, or None."""
    parts = [p for p in shapely.get_parts(geom) if p.geom_type == "Polygon" and not p.is_empty]
    return max(parts, key=lambda p: p.area) if parts else None


def _model_outline(shape):
    """The 3-D model's outline at the ground (east/north), from the feet of
    its walls that stand on the ground, or None."""
    vertices, offsets, ring_polygon, kinds, model_ground = shape
    starts = np.searchsorted(ring_polygon, np.arange(len(kinds)))
    lines = []
    for polygon, kind in enumerate(kinds):
        if kind != buildings3d.WALL:
            continue
        ring = vertices[offsets[starts[polygon]]:offsets[starts[polygon] + 1]].astype(np.float64)
        low = ring[:, 2].min()
        if low - float(model_ground) > 0.5:  # standing on a lower roof
            continue
        feet = ring[ring[:, 2] <= low + 0.05, :2]
        if len(feet) < 2:
            continue
        span = feet - feet[0]
        direction = span[np.argmax(np.hypot(span[:, 0], span[:, 1]))]
        if np.hypot(*direction) < 0.05:
            continue
        along = span @ direction
        lines.append([feet[np.argmin(along)], feet[np.argmax(along)]])
    if len(lines) < 3:
        return None
    noded = shapely.node(shapely.multilinestrings(lines))
    return _largest(shapely.polygonize(shapely.get_parts(noded)))


def _placement(poly, faces_street, width: float, seed: float, centered: bool):
    """Where the front door goes and how wide the stoop can be there: (a
    point on the wall, the wall's outward unit normal, a unit vector along
    it, all east/north; the width), or None."""
    ring = np.asarray(shapely.orient_polygons(poly).exterior.coords)[:, :2]
    seg = ring[1:] - ring[:-1]
    count = len(seg)
    length = np.hypot(seg[:, 0], seg[:, 1])
    outward = np.column_stack([seg[:, 1], -seg[:, 0]]) / np.maximum(length, 1e-9)[:, None]
    front = faces_street((ring[1:] + ring[:-1]) * 0.5, outward) & (length > 0.05)
    if not front.any():
        return None
    # The fronts: walls facing the way the longest front wall does, and any
    # others (a corner house's side); the door is on the narrower of two.
    groups = []
    left = front.copy()
    while left.any() and len(groups) < 2:
        main = outward[np.argmax(np.where(left, length, 0.0))]
        group = left & (outward @ main > SAME_FRONT)
        groups.append((group, main))
        left &= ~group
    totals = [float(length[g].sum()) for g, _ in groups]
    wide_enough = [k for k, total in enumerate(totals) if total >= 3.5]
    pick_group = min(wide_enough, key=lambda k: totals[k]) if wide_enough else int(np.argmax(totals))
    group, main = groups[pick_group]
    facing = group & (outward @ main > 0.94)
    out = (outward[facing] * length[facing, None]).sum(axis=0)
    out /= max(np.hypot(*out), 1e-9)
    along = np.array([-out[1], out[0]])
    # The wall for the stoop: facing the street squarely, wide enough, and
    # the furthest back (beside a bay rather than on it).
    candidates = np.flatnonzero(group & (outward @ out > STOOP_WALL) & (length >= MIN_WIDTH + 2 * EDGE))
    if not len(candidates):
        return None
    setback = ((ring[candidates] + ring[candidates + 1]) * 0.5) @ out
    nearly = candidates[setback <= setback.min() + 0.3]
    i = int(nearly[np.argmax(length[nearly])])
    start, end = ring[i], ring[i + 1]
    direction = seg[i] / length[i]
    width = min(width, length[i] - 2 * EDGE)
    if centered:
        return (start + end) * 0.5, out, along, width
    # At the lot line: the end where the wall turns back from the street
    # (not into a bay); either, if both or neither do.
    before = ring[i - 1] if i > 0 else ring[count - 1]
    after = ring[i + 2] if i + 2 <= count else ring[1]
    back_at_start = (start - before) @ out > 0.2 * np.hypot(*(start - before))
    back_at_end = (end - after) @ out > 0.2 * np.hypot(*(end - after))
    at_end = back_at_end if back_at_start != back_at_end else (seed * 7.31) % 1.0 < 0.5
    offset = width / 2 + EDGE
    door = end - direction * offset if at_end else start + direction * offset
    return door, out, along, width


def _fit(w: dict, index: int, own, shift, door, out, along, width: float, steps: int):
    """The most steps (up to `steps`) the stoop can have here, clear of the
    curb, of the building's own walls (`own`, its outline) and of other
    buildings (their footprints, `shift` away): (steps, foot height, top
    height), or None."""
    streets = w["streets"]
    ground = w["ground"]["lod0"]
    own = shapely.buffer(own, -0.05)
    for count in range(steps, MIN_STEPS - 1, -1):
        depth = LANDING + count * RUN
        corners = np.array([door + along * (width / 2) + out * 0.05, door + along * (width / 2) + out * depth,
                            door - along * (width / 2) + out * depth, door - along * (width / 2) + out * 0.05])
        rect = shapely.Polygon(corners)
        if not streets.is_empty and shapely.dwithin(streets, rect, CURB_CLEAR):
            continue
        moved = shapely.transform(rect, lambda c: c + shift)
        hits = w["building_index_tree"].query(shapely.buffer(moved, -NEIGHBOR_SLACK), predicate="intersects")
        if np.any(hits != index) or shapely.intersects(own, rect):
            continue
        foot = float(ground.height((door + out * depth)[None])[0])
        return count, foot, foot + count * RISE
    return None


def _areaway(w: dict, index: int, own, shift, door, out, along, width: float):
    """Where the areaway wall goes: (meters out from the wall, from and to
    meters along it), or None: from the far lot line (the outline's widest
    point at the front) to the gate beside the stoop."""
    streets = w["streets"]
    if streets.is_empty:
        return None
    ray = shapely.LineString([door, door + out * 30.0])
    hit = shapely.intersection(ray, streets)
    if hit.is_empty:
        return None
    gap = float(np.min((shapely.get_coordinates(hit) - door) @ out))
    yard = gap - CURB_CLEAR
    if yard < MIN_YARD:
        return None
    corners = shapely.get_coordinates(own.exterior) - door
    front = corners[corners @ out > -2.0] @ along
    if not len(front):
        return None
    low, high = float(front.min()), float(front.max())
    # The stoop is at one lot line; the wall runs to the other.
    if high - width / 2 > -width / 2 - low:
        start, end = width / 2 + GATE, high - 0.02
    else:
        start, end = low + 0.02, -width / 2 - GATE
    if end - start < MIN_AREAWAY:
        return None
    line = shapely.LineString([door + out * yard + along * start, door + out * yard + along * end])
    if shapely.dwithin(streets, line, CURB_CLEAR - 0.5):
        return None
    moved = shapely.transform(line, lambda c: c + shift)  # among the footprints
    if np.any(w["building_index_tree"].query(shapely.buffer(moved, 0.05), predicate="intersects") != index):
        return None
    return yard, start, end


def _build_areaway(builder, door, out, along, areaway: tuple, ground, uv2_of) -> None:
    """The areaway wall's two faces (see _areaway)."""
    yard, start, end = areaway
    ends = np.array([door + out * yard + along * start, door + out * yard + along * end])
    feet = ground.height(ends)
    pos = np.array([[e[0], y - SINK, -e[1]] for e, y in zip(ends, feet)]
                   + [[e[0], y + AREAWAY_HEIGHT, -e[1]] for e, y in zip(ends, feet)])
    length = end - start
    uv = np.array([[0.0, -SINK], [length, -SINK], [0.0, AREAWAY_HEIGHT], [length, AREAWAY_HEIGHT]])
    quad = [(0, 1, 3), (0, 3, 2)]
    normal = np.array([out[0], 0.0, -out[1]])
    for side in (1.0, -1.0):
        builder.add(pos[quad], uv[quad], uv2_of(AREAWAY), normal * side)


def _build(builder, door, out, along, width: float, stoop: tuple, ground, uv2_of) -> None:
    """The stoop's faces (see the module's docstring)."""
    count, foot, top = stoop
    depth = LANDING + count * RUN
    half = width / 2
    wall_ground = float(ground.height(door[None])[0])
    base = min(foot, wall_ground) - SINK

    def world(t, s, y):
        en = door + out * t + along * s
        return [en[0], y, -en[1]]

    def godot(direction_en, up=0.0):
        return np.array([direction_en[0], up, -direction_en[1]])

    def face(points, uv, normal, part):
        """A convex polygon of (t, s, y) points, fanned into triangles."""
        pos = np.array([world(*p) for p in points])
        uv = np.asarray(uv, np.float64)
        fan = [(0, k, k + 1) for k in range(1, len(points) - 1)]
        builder.add(pos[fan], uv[fan], uv2_of(part), normal / np.linalg.norm(normal))

    # The landing and the steps' slope.
    landing = [(-BACK, -half, top), (LANDING, -half, top), (LANDING, half, top), (-BACK, half, top)]
    face(landing, [(p[1] + half, p[0]) for p in landing], np.array([0.0, 1.0, 0.0]), STEPS)
    slope = [(LANDING, -half, top), (depth, -half, foot), (depth, half, foot), (LANDING, half, top)]
    pitch = np.arctan2(RISE, RUN)
    face(slope, [(p[1] + half, p[0]) for p in slope], godot(out * np.sin(pitch), np.cos(pitch)), STEPS)
    # The cheek walls: outsides down to the ground, insides above the steps.
    for side in (-1.0, 1.0):
        s = side * half
        normal = godot(along * side)
        outside = [(-BACK, s, base), (depth, s, base), (depth, s, foot + CHEEK_HEIGHT),
                   (LANDING, s, top + CHEEK_HEIGHT), (-BACK, s, top + CHEEK_HEIGHT)]
        face(outside, [(p[0], p[2] - top) for p in outside], normal, STOOP_SIDE)
        for quad in ([(-BACK, s, top), (LANDING, s, top), (LANDING, s, top + CHEEK_HEIGHT),
                      (-BACK, s, top + CHEEK_HEIGHT)],
                     [(LANDING, s, top), (depth, s, foot), (depth, s, foot + CHEEK_HEIGHT),
                      (LANDING, s, top + CHEEK_HEIGHT)]):
            face(quad, [(p[0], p[2] - top) for p in quad], -normal, CHEEK)
    # The doorway, just off the wall.
    door_half = DOORWAY_WIDTH / 2
    doorway = [(DOORWAY_OUT, -door_half, top), (DOORWAY_OUT, door_half, top),
               (DOORWAY_OUT, door_half, top + DOORWAY_HEIGHT), (DOORWAY_OUT, -door_half, top + DOORWAY_HEIGHT)]
    face(doorway, [(p[1] + door_half, p[2] - top) for p in doorway], godot(out), DOORWAY)
