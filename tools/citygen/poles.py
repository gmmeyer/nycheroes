"""Wooden utility poles and the overhead wires strung between them, on the
streets lined with houses in Queens, the Bronx, Staten Island and outer
Brooklyn, where the power and phone lines run overhead (Manhattan's, and
most of brownstone Brooklyn's, run under the street).

The city publishes no pole positions, so they're inferred, like the street
lights' (props.lamp_spots()):
  streets: segments of the street centerlines (markings.prepare()) with at
    most POLE_STREET_LANES lanes and POLE_STREET_WIDTH of roadbed, lined
    with houses: of the buildings within FRONTAGE_REACH of the curb (at
    least MIN_BUILDINGS), at least HOME_SHARE are houses and rowhouses
    (PLUTO's classes A and B, and C walk-ups under four floors:
    facades.HOUSE and ROWHOUSE) up to LOW_RISE tall, and at most TALL_SHARE
    are TALL; or low-rise shopping streets among them (at least
    STRIP_HOME_SHARE houses, and with low shop buildings at least
    STRIP_SHARE); outside Manhattan and downtown Brooklyn
    (UNDERGROUND_BROOKLYN);
  lines: such segments meeting nearly straight on (within STRAIGHT degrees)
    join into one line along the street, its poles on one side all the way
    (the side with clearly more houses, else either), so the wires run on
    across the intersections;
  poles: evenly along each stretch between the streets that join on the
    poles' side, about POLE_SPACING apart, CORNER_GAP back from the crossing
    street's curb, POLE_SETBACK onto the sidewalk from the curb (found by a
    ray from the centerline out through the road surface), clear of street
    trees' trunks; on most a cobra-head street light (LIGHT_SHARE), on some
    a transformer can (TRANSFORMER_SHARE); three-phase lines (a third wire
    on a pin on the pole's top) on THREE_PHASE_SHARE of the lines;
  wires: a span from each pole to the next along its line (up to MAX_SPAN),
    a service drop to each house (and low shop building) from the nearest
    pole within DROP_REACH, unless it would pass through another building,
    and a down guy from each line's end poles to an anchor GUY_REACH further
    out along the sidewalk, against the wires' pull.

prepare() makes data/cache/poles.pkl; build_tiles.py takes each tile's poles,
spans and drops from it, mounts the street lights on the poles, and takes
the curb lamps away from the streets the poles line (they'd stand beside
them).
"""

import numpy as np
import shapely

import facades
import props
from common import (POLE_THREE_PHASE, POLE_TRANSFORMER, PROP_STREET_LIGHT, PROP_UTILITY_POLE, PROP_WIRE,
                    WIRE_DROP, WIRE_GUY, WIRE_THREE_PHASE, project)

# Streets that get poles (see above).
POLE_STREET_WIDTH = 20.0
POLE_STREET_LANES = 4
FRONTAGE_REACH = 22.0
MIN_BUILDINGS = 4
HOME_SHARE = 0.6
STRIP_HOME_SHARE = 0.25
STRIP_SHARE = 0.75
TALL_SHARE = 0.1
LOW_RISE = 13.0
TALL = 16.0
POLE_BOROUGHS = (2, 3, 4, 5)
HOMES = (facades.HOUSE, facades.ROWHOUSE)
# Downtown Brooklyn and the brownstone neighborhoods around it (Brooklyn
# Heights, Park Slope, Fort Greene, Bedford-Stuyvesant's west) have their
# lines underground: within this many meters of Borough Hall (lon, lat).
UNDERGROUND_BROOKLYN = (-73.9903, 40.6928, 4500.0)
# A side of the street with this share of the other's houses or fewer gets
# no poles (they stand where the houses are).
LOPSIDED = 0.4

# Lines: segment ends this close to straight on (degrees) join.
STRAIGHT = 35.0
# Poles: spacing, how far back from a crossing street's curb, how far from
# a dead end, onto the sidewalk from the curb; stretches shorter than
# MIN_STRETCH get none (STRETCH_SINGLE: one in the middle).
POLE_SPACING = 40.0
POLE_JITTER = 2.0
CORNER_GAP = 3.0
END_GAP = 3.0
POLE_SETBACK = 0.6
MIN_STRETCH = 6.0
STRETCH_SINGLE = 20.0
# Another street joins on the poles' side where its direction away from the
# junction is at least this much toward that side (a cosine).
SIDE_JOIN = 0.35
# The curb: the ray from the centerline out through the road reaches this
# much past the street's half width; road pieces closer than SEAM along it
# are one road. Curbs found further than CURB_RANGE (of the half width, plus
# 2 m) from what the street's width says are mistrusted.
RAY_REACH = 8.0
SEAM = 0.5
CURB_RANGE = (0.5, 1.6)
# Street trees' trunks: poles this close move along the curb by TREE_STEP.
TREE_CLEAR = 1.0
TREE_STEP = 1.6
# Pole sizes (m, above the ground) and how many have what.
POLE_HEIGHT = (10.5, 12.0)
LIGHT_SHARE = 0.9
TRANSFORMER_SHARE = 0.18
THREE_PHASE_SHARE = 0.4
# A cobra-head on a wooden pole: its "pole height" (where its arm's top
# meets the pole) this far below the pole's top, and its arm's length.
LIGHT_BELOW_TOP = 2.4
LIGHT_ARM = 2.2
# Wires: spans up to MAX_SPAN long; drops up to DROP_REACH, to a house's wall
# (under the eaves of a house with a pitched roof, at DROP_SHARE of its
# height; under the cornice of a flat-roofed one, DROP_BELOW_ROOF below its
# roof; within DROP_HEIGHT), from DROP_CLEAR short of it on not passing
# through other buildings.
MAX_SPAN = 62.0
GUY_REACH = 3.5
DROP_REACH = 36.0
DROP_MIN = 2.5
DROP_MIN_AREA = 35.0  # m²: no drops to garages and sheds
DROP_FRONT = 14.0     # the wall it reaches is at most this far from a street
DROP_SHARE = 0.6
DROP_BELOW_ROOF = 1.4
DROP_HEIGHT = (3.0, 9.0)
DROP_CLEAR = 0.5
DROP_STORE_HEIGHT = 10.0  # low shop buildings get drops too


def prepare() -> dict:
    """Poles (positions east/north, the direction to the street, heights,
    variants, lights, seeds), spans (pairs of poles), drops (pole, building,
    the point on its wall) and which centerline segments the poles line."""
    import prepare as prepared
    c = prepared.load("centerline")
    b = prepared.load("buildings")
    f = prepared.load("facades")
    g = prepared.load("ground")
    lines = c["lines"]
    count = len(lines)
    half = _half_widths(c)
    lanes = c["lanes"]
    candidate = (c["rw"] == 1) & (lanes <= POLE_STREET_LANES) & (2.0 * half <= POLE_STREET_WIDTH)

    # Which streets are lined with houses, and on which side the houses are.
    height = b["height"]
    archetype = f["archetype"]
    home = np.isin(archetype, HOMES) & (height <= LOW_RISE)
    tall = height > TALL
    borough = (b["bbl"] // 1_000_000_000).astype(np.int64)
    k = np.flatnonzero(candidate)
    zones = shapely.buffer(lines[k], half[k] + FRONTAGE_REACH, cap_style="flat")
    seg, building = shapely.STRtree(shapely.points(b["anchor"])).query(zones, predicate="contains")
    seg = k[seg]
    buildings = np.bincount(seg, minlength=count)
    homes = np.bincount(seg, weights=home[building], minlength=count)
    low_shop = (archetype == facades.STORE) & (height <= DROP_STORE_HEIGHT)
    shops = np.bincount(seg, weights=low_shop[building], minlength=count)
    talls = np.bincount(seg, weights=tall[building], minlength=count)
    by_borough = np.zeros((count, 6))
    np.add.at(by_borough, (seg, np.clip(borough[building], 0, 5)), 1.0)
    main_borough = np.argmax(by_borough, axis=1)
    middles = shapely.get_coordinates(shapely.line_interpolate_point(lines, 0.5, normalized=True))
    center = shapely.get_coordinates(project(shapely.points(*UNDERGROUND_BROOKLYN[:2])))[0]
    underground = (main_borough == 3) & (np.linalg.norm(middles - center, axis=1) < UNDERGROUND_BROOKLYN[2])
    lined = (homes >= HOME_SHARE * buildings) | (
        (homes >= STRIP_HOME_SHARE * buildings) & (homes + shops >= STRIP_SHARE * buildings))
    qualifying = (candidate & (buildings >= MIN_BUILDINGS) & lined
                  & (talls <= TALL_SHARE * buildings) & np.isin(main_borough, POLE_BOROUGHS) & ~underground)
    # Houses on the left of each segment's direction, and on its right.
    starts = shapely.get_coordinates(shapely.get_point(lines, 0))
    ends = shapely.get_coordinates(shapely.get_point(lines, -1))
    chord = ends[seg] - starts[seg]
    away = b["anchor"][building] - starts[seg]
    left = (chord[:, 0] * away[:, 1] - chord[:, 1] * away[:, 0]) > 0
    homes_left = np.bincount(seg, weights=home[building] & left, minlength=count)
    homes_right = homes - homes_left
    print(f"  poles: {int(qualifying.sum()):,} of {int(candidate.sum()):,} street segments lined with houses",
          flush=True)

    inward = _inward(lines)
    chains = _chains(c["nodes"], inward, qualifying)
    ends_at = _ends_at(c["nodes"])
    found = {key: [] for key in ("center", "toward", "segment", "line")}
    for number, chain in enumerate(chains):
        _place(chain, number, lines, half, c["nodes"], inward, ends_at, homes_left, homes_right, found)
    center_points = np.asarray(found["center"]).reshape(-1, 2)
    toward = np.asarray(found["toward"]).reshape(-1, 2)
    segment = np.asarray(found["segment"], dtype=np.int64)
    line = np.asarray(found["line"], dtype=np.int64)

    # Out to the curb, onto the sidewalk.
    curb = _curb_distances(center_points, -toward, half[segment], g["roads"])
    en = center_points - toward * (curb + POLE_SETBACK)[:, None]
    # Not into a street tree's trunk: along the curb a little.
    trees = prepared.load("trees")["en"]
    tree_tree = shapely.STRtree(shapely.points(trees))
    near = tree_tree.query(shapely.points(en), predicate="dwithin", distance=TREE_CLEAR)
    if len(near[0]):
        pole, tree = near
        along = np.column_stack([-toward[pole, 1], toward[pole, 0]])
        ahead = np.sum((en[pole] - trees[tree]) * along, axis=1) >= 0
        en[pole] += along * np.where(ahead, TREE_STEP, -TREE_STEP)[:, None]
    # On land, outside buildings and off the road.
    ok = shapely.contains_xy(g["land"], en[:, 0], en[:, 1])
    hits = shapely.STRtree(b["geoms"]).query(shapely.points(en), predicate="within")
    ok[hits[0]] = False
    hits = shapely.STRtree(g["roads"]).query(shapely.points(en), predicate="within")
    ok[hits[0]] = False

    # Spans: each pole to the next along its line.
    index = np.arange(len(en))
    same_line = (line[1:] == line[:-1]) & ok[1:] & ok[:-1]
    span_a, span_b = index[:-1][same_line], index[1:][same_line]
    length = np.linalg.norm(en[span_b] - en[span_a], axis=1)
    keep_span = length <= MAX_SPAN
    span_a, span_b = span_a[keep_span], span_b[keep_span]
    # Poles left on their own (the rest of their line fell through) go too.
    spanned = np.zeros(len(en), dtype=bool)
    spanned[span_a] = spanned[span_b] = True
    keep = ok & spanned
    renumber = np.cumsum(keep) - 1
    en, toward, line, segment = en[keep], toward[keep], line[keep], segment[keep]
    span_a, span_b = renumber[span_a], renumber[span_b]

    seed = props.location_seed(en)
    line_seed = props._hash(line.astype(np.float64) * 0.001 % 1.0, 61)
    pole_height = POLE_HEIGHT[0] + (POLE_HEIGHT[1] - POLE_HEIGHT[0]) * props._hash(seed, 62)
    variant = ((props._hash(seed, 63) < TRANSFORMER_SHARE).astype(np.int8) * POLE_TRANSFORMER
               + (line_seed < THREE_PHASE_SHARE).astype(np.int8) * POLE_THREE_PHASE)
    light = props._hash(seed, 64) < LIGHT_SHARE

    # Service drops: each house's wall nearest its nearest pole.
    drop_home = ((np.isin(archetype, HOMES) & (height <= LOW_RISE)) | (
        (archetype == facades.STORE) & (height <= DROP_STORE_HEIGHT))) & (shapely.area(b["geoms"]) >= DROP_MIN_AREA)
    houses = np.flatnonzero(drop_home)
    pole_points = shapely.points(en)
    house, pole = shapely.STRtree(pole_points).query_nearest(b["geoms"][houses], max_distance=DROP_REACH,
                                                             all_matches=False)
    house = houses[house]
    wire = shapely.shortest_line(shapely.get_exterior_ring(_outer(b["geoms"][house])), pole_points[pole])
    attach = shapely.get_coordinates(shapely.get_point(wire, 0))
    run = en[pole] - attach
    run_length = np.linalg.norm(run, axis=1)
    # Onto the front (or a side by the street), not a wall round the back.
    by_street = np.zeros(len(house), dtype=bool)
    by_street[shapely.STRtree(g["roads"]).query(shapely.points(attach), predicate="dwithin", distance=DROP_FRONT)[0]] = True
    good = (run_length >= DROP_MIN) & by_street
    house, pole, attach, run, run_length = house[good], pole[good], attach[good], run[good], run_length[good]
    unit = run / run_length[:, None]
    # Not through another building (or the house itself, round a corner).
    clear_line = shapely.linestrings(np.stack([attach + unit * DROP_CLEAR, en[pole]], axis=1))
    hits = shapely.STRtree(b["geoms"]).query(clear_line, predicate="intersects")
    blocked = np.zeros(len(house), dtype=bool)
    blocked[hits[0]] = True
    house, pole, attach = house[~blocked], pole[~blocked], attach[~blocked]
    # Just off the wall, under the eaves or the cornice.
    attach = attach + unit[~blocked] * 0.05
    pitched = archetype[house] == facades.HOUSE
    attach_height = np.clip(np.where(pitched, height[house] * DROP_SHARE, height[house] - DROP_BELOW_ROOF),
                            *DROP_HEIGHT)

    # Down guys at the lines' ends (poles with one span), pulling outward.
    degree = np.bincount(np.concatenate([span_a, span_b]), minlength=len(en))
    partner = np.full(len(en), -1)
    partner[span_a], partner[span_b] = span_b, span_a
    ends = np.flatnonzero(degree == 1)
    out = en[ends] - en[partner[ends]]
    anchor = en[ends] + out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9) * GUY_REACH
    ok = shapely.contains_xy(g["land"], anchor[:, 0], anchor[:, 1])
    for geoms in (b["geoms"], g["roads"]):
        ok[shapely.STRtree(geoms).query(shapely.points(anchor), predicate="within")[0]] = False
    guy_pole, anchor = ends[ok], anchor[ok]

    pole_segment = np.zeros(count, dtype=bool)
    pole_segment[np.unique(segment)] = True
    print(f"  poles: {len(en):,} poles on {len(np.unique(line)):,} lines, {len(span_a):,} spans, "
          f"{int(light.sum()):,} street lights, {len(house):,} service drops, {len(guy_pole):,} down guys",
          flush=True)
    return {"en": en, "toward": toward.astype(np.float32), "height": pole_height.astype(np.float32),
            "variant": variant, "light": light, "seed": seed.astype(np.float32),
            "spans": np.column_stack([span_a, span_b]).astype(np.int32),
            "drops": {"pole": pole.astype(np.int32), "building": house.astype(np.int64), "en": attach,
                      "height": attach_height.astype(np.float32)},
            "guys": {"pole": guy_pole.astype(np.int32), "en": anchor},
            "pole_segment": pole_segment}


def _half_widths(c: dict) -> np.ndarray:
    """Each centerline segment's half width (m), as the paint has it."""
    import markings
    width, lanes, parking = c["width"], c["lanes"], c["parking"]
    return np.where(width > 0, width / 2.0,
                    np.where(lanes > 0, (lanes * markings.LANE_WIDTH + parking * markings.PARKING_WIDTH) / 2.0,
                             markings.DEFAULT_HALF_WIDTH)).astype(np.float64)


def _inward(lines: np.ndarray) -> np.ndarray:
    """(N, 2, 2): each segment's direction into it from its start and end."""
    length = shapely.length(lines)
    step = np.minimum(5.0, length / 2)
    starts = shapely.get_coordinates(shapely.get_point(lines, 0))
    ends = shapely.get_coordinates(shapely.get_point(lines, -1))
    into_start = shapely.get_coordinates(shapely.line_interpolate_point(lines, step)) - starts
    into_end = shapely.get_coordinates(shapely.line_interpolate_point(lines, length - step)) - ends
    out = np.stack([into_start, into_end], axis=1)
    return out / np.maximum(np.linalg.norm(out, axis=2, keepdims=True), 1e-9)


def _ends_at(nodes: np.ndarray) -> dict:
    """Node id -> the segment ends (segment, 0 start or 1 end) there."""
    found = {}
    for k, (start, end) in enumerate(nodes):
        found.setdefault(int(start), []).append((k, 0))
        found.setdefault(int(end), []).append((k, 1))
    return found


def _chains(nodes: np.ndarray, inward: np.ndarray, qualifying: np.ndarray) -> list:
    """The qualifying segments joined into lines along their streets: each a
    list of (segment, reversed) in order, ends meeting nearly straight on
    (the straightest pairs first) joined."""
    straight = -np.cos(np.radians(STRAIGHT))
    link = {}
    at_node = {}
    for k in np.flatnonzero(qualifying):
        for end in (0, 1):
            at_node.setdefault(int(nodes[k, end]), []).append((int(k), end))
    for ends in at_node.values():
        if len(ends) < 2:
            continue
        pairs = []
        for x in range(len(ends)):
            for y in range(x + 1, len(ends)):
                (ka, ea), (kb, eb) = ends[x], ends[y]
                if ka == kb:
                    continue
                dot = float(np.dot(inward[ka, ea], inward[kb, eb]))
                if dot < straight:
                    pairs.append((dot, ends[x], ends[y]))
        for _, a, b in sorted(pairs):
            if a not in link and b not in link:
                link[a], link[b] = b, a
    chains, seen = [], set()

    def walk(k: int, reverse: bool) -> list:
        chain = []
        while k not in seen:
            seen.add(k)
            chain.append((k, reverse))
            out_end = 0 if reverse else 1
            nxt = link.get((k, out_end))
            if nxt is None:
                break
            k, reverse = nxt[0], nxt[1] == 1
        return chain

    for k in np.flatnonzero(qualifying):
        k = int(k)
        if k in seen:
            continue
        if (k, 0) not in link:
            chains.append(walk(k, False))
        elif (k, 1) not in link:
            chains.append(walk(k, True))
    # What's left are loops: start anywhere.
    for k in np.flatnonzero(qualifying):
        if int(k) not in seen:
            chains.append(walk(int(k), False))
    return chains


def _place(chain: list, number: int, lines, half, nodes, inward, ends_at: dict, homes_left, homes_right,
           found: dict) -> None:
    """Poles along one line (see _chains()): points on the centerline
    ("center"), the unit direction from the curb toward the street's middle
    ("toward", to be moved out to the curb), their segments and line number,
    into `found`."""
    coords, junctions, segments = [], [0.0], []
    left, right = 0.0, 0.0
    for k, reverse in chain:
        part = np.asarray(lines[k].coords)[:, :2]
        part = part[::-1] if reverse else part
        coords.append(part if not coords else part[1:])
        junctions.append(junctions[-1] + float(lines[k].length))
        segments.append(k)
        # Houses on the line's left and right, as it runs.
        left += homes_right[k] if reverse else homes_left[k]
        right += homes_left[k] if reverse else homes_right[k]
    line = shapely.LineString(np.concatenate(coords))
    total = float(line.length)
    if total < MIN_STRETCH:
        return
    # The side: where the houses are, if clearly; else the line's own pick.
    if right <= LOPSIDED * left:
        side = 1.0
    elif left <= LOPSIDED * right:
        side = -1.0
    else:
        side = 1.0 if float(props._hash(np.float64(min(segments) % 100000) / 100000.0, 60)) < 0.5 else -1.0

    def side_normal(s: float) -> np.ndarray:
        ahead = shapely.get_coordinates(shapely.line_interpolate_point(line, min(s + 1.0, total)))[0]
        behind = shapely.get_coordinates(shapely.line_interpolate_point(line, max(s - 1.0, 0.0)))[0]
        t = ahead - behind
        t /= max(float(np.linalg.norm(t)), 1e-9)
        return np.array([-t[1], t[0]]) * side

    def others(at: int, own: set) -> list:
        node = int(nodes[at[0], at[1]])
        return [(k, e) for k, e in ends_at.get(node, []) if k not in own]

    # The chain's own ends at its first and last node.
    first_k, first_rev = chain[0]
    last_k, last_rev = chain[-1]
    start_end = (first_k, 1 if first_rev else 0)
    end_end = (last_k, 0 if last_rev else 1)
    own = {k for k, _ in chain}
    begin = max([half[k] + CORNER_GAP for k, _ in others(start_end, own)], default=END_GAP)
    finish = total - max([half[k] + CORNER_GAP for k, _ in others(end_end, own)], default=END_GAP)
    # Streets joining on the poles' side along the way.
    blocked = []
    for n in range(1, len(chain)):
        k, reverse = chain[n]
        at = (k, 1 if reverse else 0)
        s = junctions[n]
        normal = side_normal(s)
        for ko, eo in others(at, own):
            if float(np.dot(inward[ko, eo], normal)) > SIDE_JOIN:
                reach = half[ko] + CORNER_GAP
                blocked.append((s - reach, s + reach))
    stretches = [(begin, finish)]
    for lo, hi in sorted(blocked):
        cut = []
        for a, b in stretches:
            if hi <= a or lo >= b:
                cut.append((a, b))
                continue
            if lo > a:
                cut.append((a, lo))
            if hi < b:
                cut.append((hi, b))
        stretches = cut
    spots = []
    for a, b in stretches:
        length = b - a
        if length < MIN_STRETCH:
            continue
        if length < STRETCH_SINGLE:
            spots.append((a + b) / 2)
            continue
        n = max(1, int(length / POLE_SPACING + 0.5))
        s = a + np.arange(n + 1) * (length / n)
        # A little jitter, but not at the stretch's ends.
        jitter = (props._hash(props.location_seed(np.column_stack([s, np.full(len(s), number % 9973)])), 65)
                  - 0.5) * 2.0 * POLE_JITTER
        jitter[0] = jitter[-1] = 0.0
        spots.extend(np.clip(s + jitter, a, b).tolist())
    if not spots:
        return
    for s in spots:
        normal = side_normal(s)
        k = segments[min(int(np.searchsorted(junctions, s, side="right")) - 1, len(segments) - 1)]
        center = shapely.get_coordinates(shapely.line_interpolate_point(line, s))[0]
        found["center"].append(center)
        found["toward"].append(-normal)
        found["segment"].append(k)
        found["line"].append(number)


def _curb_distances(centers: np.ndarray, out: np.ndarray, half: np.ndarray, roads: np.ndarray) -> np.ndarray:
    """How far from each centerline point the road ends going `out` (unit
    (N, 2)): the end of the run of road pieces the ray starts in; the street's
    half width where the ray doesn't start in the road or ends far from it."""
    reach = half + RAY_REACH
    rays = shapely.linestrings(np.stack([centers, centers + out * reach[:, None]], axis=1))
    ray, road = shapely.STRtree(roads).query(rays, predicate="intersects")
    pieces = shapely.intersection(rays[ray], roads[road])
    parts, owner = shapely.get_parts(pieces, return_index=True)
    owner = ray[owner]
    is_line = shapely.get_type_id(parts) == 1
    parts, owner = parts[is_line], owner[is_line]
    first = shapely.get_coordinates(shapely.get_point(parts, 0))
    last = shapely.get_coordinates(shapely.get_point(parts, -1))
    t0 = np.sum((first - centers[owner]) * out[owner], axis=1)
    t1 = np.sum((last - centers[owner]) * out[owner], axis=1)
    lo, hi = np.minimum(t0, t1), np.maximum(t0, t1)
    curb = half.copy()
    order = np.lexsort((lo, owner))
    owner, lo, hi = owner[order], lo[order], hi[order]
    bounds = np.searchsorted(owner, np.arange(len(centers) + 1))
    for n in range(len(centers)):
        a, b = bounds[n], bounds[n + 1]
        if a == b or lo[a] > SEAM:
            continue
        end = hi[a]
        for m in range(a + 1, b):
            if lo[m] > end + SEAM:
                break
            end = max(end, hi[m])
        if CURB_RANGE[0] * half[n] <= end <= CURB_RANGE[1] * half[n] + 2.0:
            curb[n] = end
    return curb


def _outer(geoms: np.ndarray) -> np.ndarray:
    """The biggest polygon of each (multi)polygon."""
    out = geoms.copy()
    multi = np.flatnonzero(shapely.get_type_id(geoms) == 6)
    for k in multi:
        out[k] = max(shapely.get_parts(geoms[k]), key=lambda p: p.area)
    return out


def tile_props(data: dict, poles: np.ndarray, spans: np.ndarray, drops: np.ndarray, guys: np.ndarray, ground,
               drop_bases: np.ndarray) -> tuple[dict, dict, dict]:
    """A tile's props from the prepared `data`: its poles (indices), the
    spans starting at them (indices into data["spans"]), the drops and down
    guys from them (into data["drops"], data["guys"]); `ground` gives the
    ground's height at (N, 2)
    points, and drop_bases each drop's house's ground. Returns the poles, the
    street lights on them and the wires (see common.PROP_UTILITY_POLE,
    PROP_WIRE)."""
    en, height, seed = data["en"], data["height"].astype(np.float64), data["seed"].astype(np.float64)
    toward = data["toward"].astype(np.float64)
    yaw = np.arctan2(toward[:, 0], -toward[:, 1])
    count = len(poles)
    pole_y = ground(en[poles])
    pole_props = {"en": en[poles], "y": pole_y, "height": height[poles], "width": np.ones(count),
                  "yaw": yaw[poles], "tone": data["variant"][poles].astype(np.int8), "trunk": np.zeros(count),
                  "type": np.full(count, PROP_UTILITY_POLE, dtype=np.int8), "seed": seed[poles]}
    lit = poles[data["light"][poles]]
    light_props = {"en": en[lit], "y": ground(en[lit]), "height": height[lit] - LIGHT_BELOW_TOP,
                   "width": np.full(len(lit), LIGHT_ARM), "yaw": yaw[lit], "tone": np.zeros(len(lit), np.int8),
                   "trunk": np.ones(len(lit)), "type": np.full(len(lit), PROP_STREET_LIGHT, dtype=np.int8),
                   "seed": props.location_seed(en[lit] + 0.37)}
    # Spans: from pole a's top to pole b's; drops from a pole to a house's
    # wall; guys from a pole down to their anchor.
    a, b = data["spans"][spans, 0], data["spans"][spans, 1]
    pole = data["drops"]["pole"][drops]
    guy_pole, anchor = data["guys"]["pole"][guys], data["guys"]["en"][guys]
    ends = np.concatenate([en[b], data["drops"]["en"][drops], anchor])
    starts = np.concatenate([a, pole, guy_pole])
    start_y = ground(en[starts]) + height[starts]
    end_y = np.concatenate([ground(en[b]) + height[b], drop_bases + data["drops"]["height"][drops], ground(anchor)])
    run = ends - en[starts]
    three_phase = np.where(data["variant"][a] & POLE_THREE_PHASE, WIRE_THREE_PHASE, 0).astype(np.int8)
    kind = np.concatenate([three_phase, np.full(len(pole), WIRE_DROP, np.int8),
                           np.full(len(guy_pole), WIRE_GUY, np.int8)])
    wire_props = {"en": en[starts], "y": start_y - height[starts], "height": height[starts],
                  "width": np.linalg.norm(run, axis=1), "yaw": np.arctan2(run[:, 0], -run[:, 1]),
                  "tone": kind, "trunk": end_y - start_y,
                  "type": np.full(len(starts), PROP_WIRE, dtype=np.int8),
                  "seed": props.location_seed(ends)}
    return pole_props, light_props, wire_props
