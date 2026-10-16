"""Rowhouse and walk-up fronts, up close (lod0 tiles): stoops (steps up to
the parlor floor between cheek walls or iron railings, the front door on the
landing, an awning over some), the low wall or iron fence along the front
yard (the areaway) with shrubs behind it, deep cornices, and bow fronts.

build_tiles.py calls add() for every building it draws in full detail. A
building with stoop steps (facades.py: brownstones 8-10, later rows 3-7,
walk-ups 2-4, none behind shop fronts) gets one on its street front (the
footprint's, or for buildings drawn from the 3-D model, the model's own
outline at the ground): on the part of the front set furthest back (beside a
bay window, if there is one), at the lot line (walk-ups: in the middle),
narrower where that part is narrow. The steps go straight out toward the
street; there have to be CURB_CLEAR meters left to the curb (the walking
lanes run 2.5 m from it) and no other building or stoop in the way, so where
the sidewalk and front yard are shallow the stoop has fewer steps, or none.
Its walls are then marked STOOP, so the shader draws the front door up on the
landing instead of at the sidewalk.

A rowhouse with a stoop and a front yard also gets an areaway wall (or iron
fence) along the yard's edge, CURB_CLEAR from the curb (so neighbors' line up
and the stoops end at or inside it), from the far lot line to a gate GATE
wide beside the stoop: every yard has a way out, so heroes and thugs never get
boxed in between stoops, walls and fences.

A stoop is a few faces of the building's own surface (so it has collision,
and it's a ramp the hero walks up): the landing and the steps' slope (drawn
as steps by the shader), each cheek wall's outside reaching down to the
ground and its inside above the steps (THIN apart and open on top, so the
two never sit exactly on each other in the depth or shadow map), and the
doorway, a panel standing just off the wall: 20 triangles, 34 vertices. An areaway wall is two
faces THIN apart: 4 triangles, 8 vertices. The parts are told apart by
facades.FRONT_PART in uv2.x; the shader (shaders/building.gdshader, stoop())
paints them.

Most stoops (RAILING_SHARE) have iron railings instead of solid cheek walls:
the cheeks are a CURB, with a see-through railing on top and a newel post at
the foot. A yard's edge is a stone wall, or (FENCE_SHARE) an iron fence on a
low curb between brick posts with pyramid caps every POST_SPACING or so
(iron posts beside brownstones); behind it a shrub or two. Queens rows
(AWNING_SHARE) and some others have a striped metal awning over the door.
These small parts are in the tile's fronts surface (common.SURFACE_FRONTS),
without collision, which shaders/fronts.gdshader paints (the railings' and
fences' bars see-through): a railing is 4 triangles a side and a newel 10, a
fence 2 a span and a post 12, a shrub 30, an awning 8.

Up close, prewar rowhouses' and walk-ups' cornices (facades.CORNICE) stand
CORNICE_DEPTH out from the front, over a sloping underside: faces of the
building's own surface marked FRONT, so building.gdshader paints its
cornice on them, crown, brackets and all; about 10 triangles a wall. Queens'
prewar buff brick rows (Ridgewood's) and BOW_SHARE of other bayed rows have
their bays rounded into bow fronts (bow(); BOW_SEGMENTS facets).

Uv per part (meters; the shader relies on them and on the measures below):
  STEPS       (across from the left side, out from the wall)
  STOOP_SIDE  (out from the wall, above the landing)
  CHEEK       (out from the wall, above the landing)
  DOORWAY     (across from its left edge, above the landing)
  AREAWAY     (along it, above the ground)
In the fronts surface, uv2 = (part + FRONT_PARTS * variant, seed) and uv:
  IRON_PANEL  (m along it, m above its foot); variant: its height in dm
  IRON        (m around, m up)
  POST        (m around, m above the ground; its cap above POST_HEIGHT)
  SHRUB       (m around, m above the ground)
  AWNING      (m across, m up the slope from its front edge; the valance
              below 0, the sides below -0.3); variant: the color
"""

import math

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

# Parts in the fronts surface (common.SURFACE_FRONTS); same as shaders/fronts.gdshader.
IRON_PANEL = 0  # a see-through railing or fence
IRON = 1        # solid iron: newel and fence posts
POST = 2        # a brick fence post and its stone cap
SHRUB = 3
AWNING = 4
FRONT_PARTS = 16

# Measures (m); the shader has the same.
LANDING = 1.2          # the landing's depth, from the wall
RISE, RUN = 0.19, 0.28  # each step
CHEEK_HEIGHT = 0.85    # the cheek walls stand this high above the steps
CURB = 0.22            # ... or, under an iron railing, this high
RAIL_HEIGHT = 0.95     # the railing's top above the steps
NEWEL = 0.12           # a newel post's width
DOORWAY_WIDTH = 1.5
DOORWAY_HEIGHT = 3.0
DOORWAY_OUT = 0.08     # the doorway panel stands this far off the wall
AREAWAY_HEIGHT = 0.8
THIN = 0.06            # cheek and areaway walls' thickness

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
# Iron railings and fences: the share of stoops and yards with them, by the
# house's material (brownstone and limestone, others).
RAILING_SHARE = (0.7, 0.6)
FENCE_SHARE = (0.35, 0.75)
# Fences: the curb they stand on, their top, posts (brick: width, height,
# cap; iron: IRON_POST wide) about POST_SPACING apart.
FENCE_CURB = 0.3
FENCE_HEIGHT = 1.05
POST_WIDTH, POST_HEIGHT, POST_CAP = 0.42, 1.15, 0.3
IRON_POST = 0.1
POST_SPACING = 2.6
# Shrubs in a yard: how many per m of yard (at most SHRUBS), the share of
# yards with none, their radius and height (low, high).
SHRUB_SPACING = 1.8
SHRUBS = 3
BARE_YARDS = 0.25
SHRUB_RADIUS = (0.35, 0.7)
SHRUB_HEIGHT = (0.6, 1.3)
# Door awnings: the share of stoops with one (Queens', others'; none on
# brownstone or limestone), their width past the doorway, depth, drop and
# valance, and their top above the doorway.
AWNING_SHARE = (0.6, 0.12)
AWNING_MARGIN, AWNING_DEPTH, AWNING_DROP, AWNING_VALANCE = 0.25, 0.9, 0.45, 0.18
AWNING_ABOVE = 0.15
AWNING_COLORS = 4
# Cornices: how far they stand out, and how much their underside rises from
# the wall to their front. Their height is the shader's (cornice_height()).
CORNICE_DEPTH = 0.6
CORNICE_COVE = 0.35
# Bow fronts: bays at least MIN_BAY deep and BAY_WIDTH wide (m) rounded into
# BOW_SEGMENTS facets, on Queens' prewar buff brick rows and this share of
# other rows.
BOW_SHARE = 0.2
MIN_BAY = 0.3
BAY_WIDTH = (1.5, 8.0)
BOW_SEGMENTS = 8
QUEENS = 4  # the borough's code (the BBL's first digit)
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
    count, foot, top = stoop
    _placed(w).append(_rect(door, out, along, width, LANDING + count * RUN))

    def uv2_of(part):
        return facades.encode(archetype, flags | part * facades.FRONT_PART, floor_dm, seed)

    ground = w["ground"]["lod0"]
    small = w["front_mesh"]  # the fronts surface
    bin_number = int(w["b"]["bin"][index])
    material = (flags // facades.MATERIAL) % 8
    stone = material in (facades.BROWNSTONE, facades.LIMESTONE)
    railing = facades.unit_hash(bin_number, 71) < RAILING_SHARE[0 if stone else 1]
    _build(builder, door, out, along, width, stoop, ground, uv2_of, CURB if railing else CHEEK_HEIGHT)
    if railing:
        _build_railings(small, door, out, along, width, stoop, seed)
    queens = int(w["b"]["bbl"][index]) // 1_000_000_000 == QUEENS
    if not stone and facades.unit_hash(bin_number, 77) < AWNING_SHARE[0 if queens else 1]:
        _build_awning(small, door, out, along, stoop[2], seed, bin_number)
    if archetype == facades.ROWHOUSE:
        areaway = _areaway(w, index, poly, shift, door, out, along, width)
        if areaway is not None:
            fence = facades.unit_hash(bin_number, 73) < FENCE_SHARE[0 if stone else 1]
            _build_areaway(builder, door, out, along, areaway, ground, uv2_of, FENCE_CURB if fence else AREAWAY_HEIGHT)
            if fence:
                _build_fence(small, door, out, along, areaway, ground, seed, brick=not stone)
            _build_shrubs(small, door, out, along, areaway, ground, seed, bin_number)
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


def _rect(door, out, along, width: float, depth: float, start: float = 0.0):
    """The ground a stoop covers (east/north), from `start` out from the wall."""
    return shapely.Polygon([door + along * (width / 2) + out * start, door + along * (width / 2) + out * depth,
                            door - along * (width / 2) + out * depth, door - along * (width / 2) + out * start])


def _placed(w: dict) -> list:
    """The stoops placed in this tile so far (their ground, as drawn)."""
    placed = w.get("stoops_placed")
    if placed is None or placed[0] is not w["streets"]:  # a new tile
        placed = w["stoops_placed"] = (w["streets"], [])
    return placed[1]


def _fit(w: dict, index: int, own, shift, door, out, along, width: float, steps: int):
    """The most steps (up to `steps`) the stoop can have here, clear of the
    curb, of the building's own walls (`own`, its outline), of other
    buildings (their footprints, `shift` away) and of stoops already placed:
    (steps, foot height, top height), or None."""
    streets = w["streets"]
    ground = w["ground"]["lod0"]
    own = shapely.buffer(own, -0.05)
    placed = np.array(_placed(w), dtype=object)
    if len(placed):
        placed = placed[shapely.dwithin(placed, shapely.Point(door), 12.0)]
    for count in range(steps, MIN_STEPS - 1, -1):
        depth = LANDING + count * RUN
        rect = _rect(door, out, along, width, depth, 0.05)
        if not streets.is_empty and shapely.dwithin(streets, rect, CURB_CLEAR):
            continue
        if len(placed) and np.any(shapely.intersects(placed, rect)):
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


def _build_areaway(builder, door, out, along, areaway: tuple, ground, uv2_of, height: float) -> None:
    """The areaway wall's two faces (see _areaway), `height` tall (a fence's curb is lower)."""
    yard, start, end = areaway
    ends = np.array([door + out * yard + along * start, door + out * yard + along * end])
    feet = ground.height(ends)
    pos = np.array([[e[0], y - SINK, -e[1]] for e, y in zip(ends, feet)]
                   + [[e[0], y + height, -e[1]] for e, y in zip(ends, feet)])
    length = end - start
    uv = np.array([[0.0, -SINK], [length, -SINK], [0.0, height], [length, height]])
    quad = [(0, 1, 3), (0, 3, 2)]
    normal = np.array([out[0], 0.0, -out[1]])
    builder.add(pos[quad], uv[quad], uv2_of(AREAWAY), normal)
    inside = pos - normal * THIN
    builder.add(inside[quad], uv[quad], uv2_of(AREAWAY), -normal)


def _build(builder, door, out, along, width: float, stoop: tuple, ground, uv2_of, cheek: float) -> None:
    """The stoop's faces (see the module's docstring), its cheek walls `cheek` above the steps."""
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
        outside = [(-BACK, s, base), (depth, s, base), (depth, s, foot + cheek),
                   (LANDING, s, top + cheek), (-BACK, s, top + cheek)]
        face(outside, [(p[0], p[2] - top) for p in outside], normal, STOOP_SIDE)
        s -= side * THIN
        for quad in ([(-BACK, s, top), (LANDING, s, top), (LANDING, s, top + cheek), (-BACK, s, top + cheek)],
                     [(LANDING, s, top), (depth, s, foot), (depth, s, foot + cheek), (LANDING, s, top + cheek)]):
            face(quad, [(p[0], p[2] - top) for p in quad], -normal, CHEEK)
    # The doorway, just off the wall.
    door_half = DOORWAY_WIDTH / 2
    doorway = [(DOORWAY_OUT, -door_half, top), (DOORWAY_OUT, door_half, top),
               (DOORWAY_OUT, door_half, top + DOORWAY_HEIGHT), (DOORWAY_OUT, -door_half, top + DOORWAY_HEIGHT)]
    face(doorway, [(p[1] + door_half, p[2] - top) for p in doorway], godot(out), DOORWAY)


# --- The fronts surface's small parts ---

def _small_uv2(part: int, variant: int, seed: float) -> tuple[float, float]:
    return float(part + FRONT_PARTS * variant), min(float(seed), 0.999)


def _quad(builder, corners, uv, uv2, normal) -> None:
    """A quad of four (N, 3) Godot points, fanned from the first."""
    corners, uv = np.asarray(corners, np.float64), np.asarray(uv, np.float64)
    tri = [(0, 1, 2), (0, 2, 3)]
    builder.add(corners[tri], uv[tri], uv2, np.asarray(normal, np.float64) / np.linalg.norm(normal))


def _box(builder, center, half: float, low: float, high: float, uv2, cap: float = 0.0, foot: float | None = None) -> None:
    """An upright square post (east/north center, half its width) from `low` to
    `high`, its uv (m around, m above `foot`, default `low`), under a pyramid
    cap `cap` tall (or a flat top)."""
    x, n = center
    base = low if foot is None else foot
    ring = [(x - half, n - half), (x + half, n - half), (x + half, n + half), (x - half, n + half)]
    for k in range(4):
        (e0, n0), (e1, n1) = ring[k], ring[(k + 1) % 4]
        outward = np.array([n1 - n0, -(e1 - e0)]) / (2 * half)
        _quad(builder, [[e0, low, -n0], [e1, low, -n1], [e1, high, -n1], [e0, high, -n0]],
              [[k * 2 * half, low - base], [(k + 1) * 2 * half, low - base], [(k + 1) * 2 * half, high - base],
               [k * 2 * half, high - base]], uv2, (outward[0], 0.0, -outward[1]))
        apex = [x, high + max(cap, 0.0), -n]
        if cap > 0.0:
            slant = math.hypot(cap, half)
            builder.add(np.array([[[e0, high, -n0], [e1, high, -n1], apex]]),
                        np.array([[[k * 2 * half, high - base], [(k + 1) * 2 * half, high - base],
                                   [(k + 0.5) * 2 * half, high - base + slant]]]),
                        uv2, np.array([outward[0] * cap, half, -outward[1] * cap]) / slant)
    if cap <= 0.0:
        top = np.array([[e, high, -nn] for e, nn in ring])
        _quad(builder, top, [[0.0, high - base]] * 4, uv2, (0.0, 1.0, 0.0))


def _build_railings(builder, door, out, along, width: float, stoop: tuple, seed: float) -> None:
    """Iron railings along both sides of a stoop, on its curbs: a see-through
    panel along the landing and down the steps, and a newel post at the foot."""
    count, foot, top = stoop
    depth = LANDING + count * RUN
    slope = RISE / RUN
    end = depth - NEWEL
    line = [(0.15, top), (LANDING, top), (end, top - (end - LANDING) * slope)]
    uv2 = _small_uv2(IRON_PANEL, int(round((RAIL_HEIGHT - CURB) * 10)), seed)
    for side in (-1.0, 1.0):
        s = side * (width / 2 - THIN / 2)
        normal = (along[0] * side, 0.0, -along[1] * side)
        for (t0, y0), (t1, y1) in zip(line[:-1], line[1:]):
            a, b = door + out * t0 + along * s, door + out * t1 + along * s
            _quad(builder, [[a[0], y0 + CURB, -a[1]], [b[0], y1 + CURB, -b[1]],
                            [b[0], y1 + RAIL_HEIGHT, -b[1]], [a[0], y0 + RAIL_HEIGHT, -a[1]]],
                  [[t0, 0.0], [t1, 0.0], [t1, RAIL_HEIGHT - CURB], [t0, RAIL_HEIGHT - CURB]], uv2, normal)
        post = door + out * (depth - NEWEL / 2) + along * s
        _box(builder, post, NEWEL / 2, foot, foot + RAIL_HEIGHT + 0.12, _small_uv2(IRON, 0, seed), cap=0.08)


def _build_fence(builder, door, out, along, areaway: tuple, ground, seed: float, brick: bool) -> None:
    """An iron fence along the yard's edge, on the areaway's curb, between
    posts (brick, with pyramid caps; or iron)."""
    yard, start, end = areaway
    half = POST_WIDTH / 2 if brick else IRON_POST / 2
    t = yard - THIN / 2
    spans = max(1, math.ceil((end - start - 2 * half) / POST_SPACING))
    stations = np.linspace(start + half, end - half, spans + 1)
    spots = door + out * t + along * stations[:, None]
    feet = ground.height(spots)
    post_uv2 = _small_uv2(POST if brick else IRON, 0, seed)
    for spot, foot in zip(spots, feet):
        if brick:
            _box(builder, spot, half, foot - SINK, foot + POST_HEIGHT, post_uv2, cap=POST_CAP, foot=foot)
        else:
            _box(builder, spot, half, foot - SINK, foot + FENCE_HEIGHT + 0.1, post_uv2, cap=0.12)
    panel = _small_uv2(IRON_PANEL, int(round((FENCE_HEIGHT - FENCE_CURB) * 10)), seed)
    normal = (out[0], 0.0, -out[1])
    for k in range(spans):
        s0, s1 = stations[k] + half, stations[k + 1] - half
        if s1 - s0 < 0.1:
            continue
        a, b = door + out * t + along * s0, door + out * t + along * s1
        y0, y1 = feet[k], feet[k + 1]
        _quad(builder, [[a[0], y0 + FENCE_CURB, -a[1]], [b[0], y1 + FENCE_CURB, -b[1]],
                        [b[0], y1 + FENCE_HEIGHT, -b[1]], [a[0], y0 + FENCE_HEIGHT, -a[1]]],
              [[s0, 0.0], [s1, 0.0], [s1, FENCE_HEIGHT - FENCE_CURB], [s0, FENCE_HEIGHT - FENCE_CURB]], panel, normal)


def _build_shrubs(builder, door, out, along, areaway: tuple, ground, seed: float, bin_number: int) -> None:
    """A shrub or a few in the yard behind the areaway (none in some yards)."""
    yard, start, end = areaway
    if facades.unit_hash(bin_number, 81) < BARE_YARDS:
        return
    length = end - start
    count = int(np.clip(length / SHRUB_SPACING, 1, SHRUBS))
    for k in range(count):
        r = [facades.unit_hash(bin_number, 83 + 7 * k + j) for j in range(4)]
        radius = SHRUB_RADIUS[0] + (SHRUB_RADIUS[1] - SHRUB_RADIUS[0]) * r[0]
        radius = min(radius, 0.5 * (yard - THIN - 0.2), 0.5 * length / count)
        if radius < 0.25:
            continue
        height = SHRUB_HEIGHT[0] + (SHRUB_HEIGHT[1] - SHRUB_HEIGHT[0]) * r[1]
        s = start + length * (k + 0.3 + 0.4 * r[2]) / count
        t = min(max(yard * (0.4 + 0.25 * r[3]), radius + 0.15), yard - THIN - radius - 0.05)
        center = door + out * t + along * s
        _shrub(builder, center, float(ground.height(center[None])[0]), radius, height,
               _small_uv2(SHRUB, int(r[0] * 4), seed), bin_number + k)


def _shrub(builder, center, foot: float, radius: float, height: float, uv2, salt: int) -> None:
    """A low-poly shrub: six bulging sides and a rounded top, a little uneven."""
    sides = 6
    rings = [(0.75, -0.1), (1.0, 0.45), (0.6, 0.85)]  # (share of the radius, share of the height)
    points = []
    for share, up in rings:
        ring = []
        for k in range(sides):
            angle = 2 * math.pi * (k + 0.5 * (len(points) % 2)) / sides
            wobble = 0.85 + 0.3 * facades.unit_hash(salt, 91 + 10 * len(points) + k)
            e = center[0] + math.cos(angle) * radius * share * wobble
            n = center[1] + math.sin(angle) * radius * share * wobble
            ring.append((e, foot + height * up, n, angle * radius))
        points.append(ring)
    top = (center[0], foot + height, center[1])
    tris, uvs = [], []
    for low, high in zip(points[:-1], points[1:]):
        for k in range(sides):
            a, b = low[k], low[(k + 1) % sides]
            c, d = high[(k + 1) % sides], high[k]
            for tri in ((a, b, c), (a, c, d)):
                tris.append([[p[0], p[1], -p[2]] for p in tri])
                uvs.append([[p[3], p[1] - foot] for p in tri])
    for k in range(sides):
        a, b = points[-1][k], points[-1][(k + 1) % sides]
        tris.append([[a[0], a[1], -a[2]], [b[0], b[1], -b[2]], [top[0], top[1], -top[2]]])
        uvs.append([[a[3], a[1] - foot], [b[3], b[1] - foot], [a[3], height]])
    tris, uvs = np.array(tris), np.array(uvs)
    # Normals: away from the shrub's middle, for a rounded look.
    middle = np.array([center[0], foot + 0.4 * height, -center[1]])
    normals = tris - middle
    normals[..., 1] *= 0.7
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    builder.add(tris, uvs, uv2, normals.mean(axis=1), normals)


def _build_awning(builder, door, out, along, top: float, seed: float, bin_number: int) -> None:
    """A striped metal awning over the front door, on the landing."""
    half = DOORWAY_WIDTH / 2 + AWNING_MARGIN
    high = top + DOORWAY_HEIGHT + AWNING_ABOVE
    low = high - AWNING_DROP
    bottom = low - AWNING_VALANCE
    uv2 = _small_uv2(AWNING, int(facades.unit_hash(bin_number, 79) * AWNING_COLORS), seed)

    def at(t, s, y):
        en = door + out * t + along * s
        return [en[0], y, -en[1]]

    slant = math.hypot(AWNING_DEPTH, AWNING_DROP)
    up = np.array([out[0] * AWNING_DROP, AWNING_DEPTH, -out[1] * AWNING_DROP])
    _quad(builder, [at(AWNING_DEPTH, -half, low), at(AWNING_DEPTH, half, low), at(0.02, half, high), at(0.02, -half, high)],
          [[-half, 0.0], [half, 0.0], [half, slant], [-half, slant]], uv2, up)
    _quad(builder, [at(AWNING_DEPTH, -half, bottom), at(AWNING_DEPTH, half, bottom), at(AWNING_DEPTH, half, low),
                    at(AWNING_DEPTH, -half, low)],
          [[-half, -AWNING_VALANCE], [half, -AWNING_VALANCE], [half, 0.0], [-half, 0.0]], uv2, (out[0], 0.0, -out[1]))
    for side in (-1.0, 1.0):
        corners = np.array([at(0.02, side * half, high), at(AWNING_DEPTH, side * half, low),
                            at(AWNING_DEPTH, side * half, bottom)])
        uv = np.array([[0.02, -0.3], [AWNING_DEPTH, -0.3 - AWNING_DROP], [AWNING_DEPTH, -0.3 - AWNING_DROP - AWNING_VALANCE]])
        builder.add(corners[None], uv[None], uv2, (along[0] * side, 0.0, -along[1] * side))


# --- Cornices and bow fronts (the building's own surface) ---

def cornice_height(floor_dm: int) -> float:
    """A row's cornice's height (m); the shader's facade() paints it so."""
    return float(np.clip(0.36 * max(floor_dm / 10.0, 2.4), 1.0, 1.6))


def add_cornice(builder, poly, ground: float, top: float, facade: tuple, faces_street) -> None:
    """A deep cornice along the street fronts of a prewar row's or walk-up's
    wall (CORNICE flag) whose top is at `top`: a front and ends (FRONT walls,
    so the shader paints the cornice on them), a sloping underside and a top."""
    archetype, flags, floor_dm, seed = facade
    if archetype not in (facades.ROWHOUSE, facades.WALKUP) or not flags & facades.CORNICE:
        return
    ring = np.asarray(shapely.orient_polygons(poly).exterior.coords)[:, :2]
    seg = ring[1:] - ring[:-1]
    length = np.hypot(seg[:, 0], seg[:, 1])
    outward = np.column_stack([seg[:, 1], -seg[:, 0]]) / np.maximum(length, 1e-9)[:, None]
    front = faces_street((ring[1:] + ring[:-1]) * 0.5, outward) & (length > 0.05)
    if not front.any():
        return
    count = len(seg)
    # Runs of consecutive front walls (wrapping around the ring).
    first = int(np.flatnonzero(~front)[0]) + 1 if not front.all() else 0
    order = [(first + k) % count for k in range(count)]
    runs, run = [], []
    for k in order:
        if front[k]:
            run.append(k)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    height = cornice_height(floor_dm)
    low = top - height
    uv2 = facades.encode(archetype, flags | facades.FRONT, floor_dm, seed)
    roof_uv2 = facades.encode(archetype, flags | facades.ROOF, floor_dm, seed)
    for run in runs:
        wall = np.array([ring[k] for k in run] + [ring[run[-1] + 1]])
        normals = outward[run]
        # The front's corners, mitred (capped where the wall turns sharply).
        offsets = [normals[0]]
        for n0, n1 in zip(normals[:-1], normals[1:]):
            miter = (n0 + n1) / max(1.0 + float(n0 @ n1), 0.3)
            offsets.append(miter)
        offsets.append(normals[-1])
        outer = wall + np.array(offsets) * CORNICE_DEPTH
        u = np.concatenate([[0.0], np.cumsum(np.hypot(*(wall[1:] - wall[:-1]).T))])
        for k in range(len(run)):
            w0, w1, o0, o1 = wall[k], wall[k + 1], outer[k], outer[k + 1]
            n = normals[k]
            # The front, from the top of the underside up.
            _quad(builder, [[o0[0], low + CORNICE_COVE, -o0[1]], [o1[0], low + CORNICE_COVE, -o1[1]],
                            [o1[0], top, -o1[1]], [o0[0], top, -o0[1]]],
                  [[u[k], low + CORNICE_COVE - ground], [u[k + 1], low + CORNICE_COVE - ground],
                   [u[k + 1], top - ground], [u[k], top - ground]], uv2, (n[0], 0.0, -n[1]))
            # The underside, sloping up and out from the wall.
            cove = np.array([n[0] * CORNICE_COVE, -CORNICE_DEPTH, -n[1] * CORNICE_COVE])
            _quad(builder, [[w0[0], low, -w0[1]], [o0[0], low + CORNICE_COVE, -o0[1]],
                            [o1[0], low + CORNICE_COVE, -o1[1]], [w1[0], low, -w1[1]]],
                  [[u[k], low - ground], [u[k], low + CORNICE_COVE - ground],
                   [u[k + 1], low + CORNICE_COVE - ground], [u[k + 1], low - ground]], uv2, cove)
            # The top (a roof).
            top_pts = np.array([[w0[0], top, -w0[1]], [w1[0], top, -w1[1]], [o1[0], top, -o1[1]], [o0[0], top, -o0[1]]])
            _quad(builder, top_pts, top_pts[:, [0, 2]], roof_uv2, (0.0, 1.0, 0.0))
        # The ends: a rectangle above the underside's top, a triangle below it.
        for w, o, side in ((wall[0], outer[0], -1.0), (wall[-1], outer[-1], 1.0)):
            d = o - w
            depth = float(np.hypot(*d))
            away = np.array([-d[1], d[0]]) * side / max(depth, 1e-9)  # away from the run
            normal = (away[0], 0.0, -away[1])
            _quad(builder, [[w[0], low + CORNICE_COVE, -w[1]], [o[0], low + CORNICE_COVE, -o[1]], [o[0], top, -o[1]],
                            [w[0], top, -w[1]]],
                  [[0.0, low + CORNICE_COVE - ground], [depth, low + CORNICE_COVE - ground], [depth, top - ground],
                   [0.0, top - ground]], uv2, normal)
            builder.add(np.array([[[w[0], low, -w[1]], [o[0], low + CORNICE_COVE, -o[1]],
                                   [w[0], low + CORNICE_COVE, -w[1]]]]),
                        np.array([[[0.0, low - ground], [depth, low + CORNICE_COVE - ground],
                                   [0.0, low + CORNICE_COVE - ground]]]), uv2, normal)


def bow(poly, facade: tuple, bin_number: int, borough: int, faces_street):
    """The footprint with its street front's bays rounded into bow fronts, on
    Queens' prewar buff brick rows and BOW_SHARE of other rows (see the
    module's docstring); else `poly` itself."""
    archetype, flags, floor_dm, seed = facade
    if archetype != facades.ROWHOUSE or len(poly.interiors):
        return poly
    ridgewood = borough == QUEENS and (flags // facades.MATERIAL) % 8 == facades.BUFF_BRICK and flags & facades.CORNICE
    if not ridgewood and facades.unit_hash(bin_number, 87) >= BOW_SHARE:
        return poly
    ring = np.asarray(shapely.orient_polygons(poly).exterior.coords)[:-1, :2]
    count = len(ring)
    nxt = np.roll(ring, -1, axis=0)
    seg = nxt - ring
    length = np.hypot(seg[:, 0], seg[:, 1])
    outward = np.column_stack([seg[:, 1], -seg[:, 0]]) / np.maximum(length, 1e-9)[:, None]
    front = faces_street((ring + nxt) * 0.5, outward) & (length > 0.05)
    if not front.any():
        return poly
    main = outward[int(np.argmax(np.where(front, length, 0.0)))]
    on_front = front | np.roll(front, 1)  # vertices at either end of a front wall
    depth = ring @ main
    base = float(depth[on_front].min())
    bay = on_front & (depth > base + MIN_BAY)
    if not bay.any() or bay.all():
        return poly
    # Start the walk at a vertex that's not in a bay, so no bay wraps around.
    start = int(np.flatnonzero(~bay)[0])
    order = [(start + k) % count for k in range(count)]
    out_ring, k = [], 0
    while k < count:
        i = order[k]
        if not bay[i]:
            out_ring.append(ring[i])
            k += 1
            continue
        run = []
        while k < count and bay[order[k]]:
            run.append(order[k])
            k += 1
        a, b = ring[(run[0] - 1) % count], ring[(run[-1] + 1) % count]
        chord = float(np.hypot(*(b - a)))
        sagitta = float(depth[run].max()) - base
        if (abs(a @ main - base) > MIN_BAY or abs(b @ main - base) > MIN_BAY
                or not BAY_WIDTH[0] <= chord <= BAY_WIDTH[1] or sagitta > 0.5 * chord):
            out_ring.extend(ring[j] for j in run)
            continue
        # The arc from a to b bulging `sagitta` out toward the street.
        normal = np.array([(b - a)[1], -(b - a)[0]]) / chord
        if normal @ main < 0.0:
            normal = -normal
        radius = (chord * chord / 4.0 + sagitta * sagitta) / (2.0 * sagitta)
        center = (a + b) * 0.5 - normal * (radius - sagitta)
        a0 = math.atan2(*(a - center)[::-1])
        a1 = math.atan2(*(b - center)[::-1])
        sweep = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for step in range(1, BOW_SEGMENTS):
            angle = a0 + sweep * step / BOW_SEGMENTS
            out_ring.append(center + radius * np.array([math.cos(angle), math.sin(angle)]))
    rounded = shapely.Polygon(out_ring)
    if not rounded.is_valid or abs(rounded.area - poly.area) > 0.3 * poly.area:
        return poly
    return rounded
