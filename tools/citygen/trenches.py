"""Sunken roads: highways and streets below the streets around them, in open
cuts between retaining walls (the BQE along Hicks Street, the Cross Bronx
through East Tremont, the Trans-Manhattan Expressway, the Gowanus approach
cuts, the Prospect Expressway, the Grand Central and the Long Island
Expressway's depressed stretches, the Central Park transverses...), with the
cross streets bridging over them; and roads the level codes put below street
level that really run at grade. The BQE's triple cantilever is
cantilever.py's.

The data:
- The street centerlines' level codes (9 one level below street level, 5
  two) say which segments run under the streets (overpasses.prepare already
  has the ramps and bridges; prepare() adds the streets and highways).
- The city's 2017 lidar survey (lidar.prepare_sunken) says where they
  really are: every 10 m along them, the surfaces over the centerline (in a
  cut, the road below the ground around; over it a bridge, a building or a
  tunnel's lid), and the lowest surface across the road.
- The planimetric bridge outlines (Transportation Structures, 2300): the
  cross streets' bridges over the cuts (their true edges).

Heights (fit()): the road follows the lowest surface the survey sees along
it, the way a road can (climbing at most GRADE): a surface that jumps up from
the road it came from is something over it (a bridge, a building, or the lid
of a tunnel), and holds the road at least CLEAR below it, spreading on along
the lid as long as what the survey sees stays up there; long covered
stretches are tunnels. Ends at street level stay on the street. Then a
smoothed least-squares fit over the whole network at once, like the raised
roads' (overpasses.Network._fit); the raised ramps leaving them start from
their heights.

The ground (Trenches, Ground): along every sunken road but its tunnels, a
strip (out to the walls where the survey sees them, else the road's width;
the medians between carriageways closed) is cut down under the road's
surface, which spans it; retaining walls stand where its edge meets higher
ground (and side walls where the road runs higher), with parapets on top and
street lights along them. The elevation model blurs the cuts' edges, so the
ground beside them is brought up to the ground FILL_REACH out. Nothing is cut
under buildings, nor under streets running along a cut's edge. Streets
crossing a cut bridge it on short flat decks at the street's height (an
outline's true edges where there is one), and tunnels' portals open into the
walls at the cuts' ends. Far tiles, which draw no streets, keep their ground
whole. This wraps the triple cantilever's ground (Ground over
cantilever.Ground) and builds with its deck, underside and wall builders: no
road is special-cased.

prepare() makes data/cache/trenches.pkl; overpasses.Network takes the roads
in with the others (their driving lanes and paint ride on the cut's road
surface, linked to the streets at their ends) and makes Trenches; build()
adds the roads' surfaces, the walls, parapets, lamps, bridges and portals to
the bridge buckets (with collision up close).
"""

import numpy as np
import shapely
import shapely.ops
from shapely.geometry import shape

import cantilever
import lidar
import markings
import overpasses
import props
from common import (CURB_HEIGHT, FEET, GROUND_PAVEMENT, GROUND_ROAD, STRUCTURE_CONCRETE, MeshBuilder, lines_of,
                    load_features, polygons_of, project)
from markings import AT_GRADE, BOTH

# Roadway types prepare() takes (streets and highways; the ramps and bridges
# below street level are overpasses.prepare's already).
ROAD_TYPES = (markings.STREET, markings.HIGHWAY)
LEVEL_STEP = 4      # level codes per level
LEVEL_DEPTH = 6.0   # where the survey sees nothing: meters below the street per level
# Following the survey (fit()): a road climbs at most GRADE, and stays CLEAR
# under anything over it; a surface within TOLERANCE of where the road could
# be is the road, one JUMP higher up (and no more than LID_DEPTH below the
# street around) is over it, and so is one CLEAR over the road. Lowest
# surfaces without another within SUPPORT_TOLERANCE (allowing for GRADE) at a
# neighboring station don't count.
GRADE = 0.08
JUMP_GRADE = 0.04   # (where the survey has gaps, for telling what's over the road)
TOLERANCE = 0.6
CLEAR = 5.0
SUPPORT_TOLERANCE = 0.5
JUMP = 3.0
LID_DEPTH = 3.0     # (if no further below the street around than this)
MAX_DEPTH = 25.0    # roads at most this far below the street around
MIN_ROAD = 0.5      # and never under the game's sea (a few by the water are, by up to 3.7 m)
DEPTH_RING = (20.0, 30.0)  # the street around: the ground in these rings
# Stretches of road between covered ones shorter than MIN_OPEN are under the
# same cover (and those at the street around's level shorter than LID_GAP
# under the same lid); covered stretches at least TUNNEL long are tunnels.
MIN_OPEN = 60.0
LID_GAP = 100.0
TUNNEL = 45.0
OPEN_STATE, BRIDGE_STATE, TUNNEL_STATE = 0, 1, 2
STATION_STEP = lidar.STATION_STEP
CLASSIFY_ROUNDS = 80
SPREAD_ROUNDS = 60
# The cuts (Trenches): a road's strip reaches SHOULDER past its edges, and
# gaps between strips narrower than twice MEDIAN are closed; nothing is cut
# within BUILDING_GAP of a building. The road's surface spans the cut, the
# ground FLOOR_DROP under it; the ground within FILL_REACH of a cut is
# brought up to the elevation model's ground FILL_REACH out (its 10 m pixels
# blur the cuts' edges) where the cut is at least FILL_DEPTH deep.
SHOULDER = 1.5
MEDIAN = 4.0
BUILDING_GAP = 1.0
FLOOR_DROP = 0.5
FILL_REACH = 15.0
FILL_DEPTH = 1.5
EDGE_STEP = 2.0
FIELD_BLEND = 20.0  # the surface blends the heights of the roads in it this close
# Where the survey shows the cut's walls, the strip reaches them: where the
# lowest surface across the road rises WALL_RISE over it, up to MAX_WIDEN past
# the strip (smoothed over WALL_SMOOTH stations).
WALL_RISE = 2.5
MAX_WIDEN = 15.0
WALL_SMOOTH = 7
STRIP_STEP = 5.0
# Streets crossing a cut (at least CROSSING_MIN of them inside it, at an angle
# whose sine is at least CROSSING_SINE to the road under them) bridge it on a
# deck across it, half their width plus SIDEWALK wide (and a bridge outline's
# true edges), at the street's height LANDING out from the cut at either end;
# streets running along inside a cut keep their ground, STREET_GAP from their
# edges.
CROSSING_MIN = 4.0
CROSSING_SINE = 0.5
LANDING = 1.0
SIDEWALK = 2.5
STREET_GAP = 0.5
DEFAULT_HALF = 5.0
# Bridge outlines (2300) claimed by a cut: those no raised road runs over,
# overlapping it by at least OUTLINE_SHARE of their area or OUTLINE_AREA.
OUTLINE_SHARE = 0.3
OUTLINE_AREA = 100.0
OUTLINE_PART = 50.0  # (outline parts smaller than this are left out, as overpasses.build does)
# Building them (build()): walls reach WALL_FOOT under the road's surface,
# where the ground around is at least WALL_MIN higher (or lower); parapets
# PARAPET high and PARAPET_THICK thick top retaining walls PARAPET_FROM high
# or more (up close). Tunnels' portals open PORTAL_CLEAR over the road (less
# where the ground over them is lower), the tunnel built PORTAL_DEPTH in (up
# close). Bridges' decks are BRIDGE_DEPTH deep, their parapets BRIDGE_PARAPET
# high.
WALL_FOOT = 0.5
WALL_MIN = 0.2
PARAPET = 1.0
PARAPET_THICK = 0.3
PARAPET_FROM = 2.0
PORTAL_CLEAR = 5.0
PORTAL_DEPTH = 25.0
LID_THICKNESS = 0.3  # (portals' ceilings stay this far under the ground over them)
BRIDGE_DEPTH = 1.2
BRIDGE_PARAPET = 1.1
DETAILED = overpasses.DETAILED
LEVELS = DETAILED   # the levels with cuts (far tiles draw no streets: their ground stays whole)
NEAR = ("lod0",)    # parapets and portals only up close
ROAD_TOP = (GROUND_ROAD, 0.0)
SIDEWALK_TOP = (GROUND_PAVEMENT, 0.0)
WALL = (STRUCTURE_CONCRETE, 0.0)
# The smoothed fit (as overpasses.Network._fit's).
MEASURE = 1.0
PRIOR = 0.01
SMOOTH = 20.0
HOLD = 1e4
LIMIT_ROUNDS = 10
LIMIT_SLACK = 0.05


def prepare() -> dict:
    """The streets and highways below street level (overpasses.prepare's
    format; none above it, and not the triple cantilever's roadways), what the
    survey has along every road below street level (theirs and
    overpasses.prepare's ramps and bridges, lidar.prepare_sunken), and the
    building footprints near them."""
    import prepare as prepared  # (prepare imports this module)
    from terrain import Terrain
    lines, rows = [], []
    for feat in load_features("centerline"):
        p = feat["properties"]
        rw = int(p.get("rw_type") or 0)
        if rw not in ROAD_TYPES or p.get("status", "2") != "2":
            continue
        levels = (int(p.get("from_level_code") or AT_GRADE), int(p.get("to_level_code") or AT_GRADE))
        if min(levels) >= int(AT_GRADE) or max(levels) > int(AT_GRADE):
            continue
        trafdir = {"FT": markings.WITH, "TF": markings.AGAINST, "TW": BOTH}.get(p.get("trafdir"), BOTH)
        for part in shapely.get_parts(shapely.line_merge(shape(feat["geometry"]))):
            lines.append(part)
            rows.append((rw, trafdir, int(float(p.get("number_travel_lanes") or 0)),
                         int(float(p.get("number_park_lanes") or 0)), float(p.get("streetwidth") or 0) * FEET,
                         levels[0], levels[1]))
    lines = project(np.array(lines, dtype=object))
    attrs = np.array(rows, dtype=np.float64).reshape(-1, 7)
    keep = shapely.length(lines) > 1.0
    # The triple cantilever's roadways are its own (cantilever.prepare).
    theirs = {_ends_key(line) for line in prepared.load("cantilever")["lines"]}
    keep &= np.array([_ends_key(line) not in theirs for line in lines], dtype=bool)
    lines, attrs = lines[keep], attrs[keep]

    roads = prepared.load("overpasses")
    below = (roads["levels"].min(axis=1) < int(AT_GRADE)) & (roads["levels"].max(axis=1) <= int(AT_GRADE))
    surveyed = np.concatenate([lines, roads["lines"][below]])
    prepared.load_terrain()
    survey = lidar.prepare_sunken(surveyed, Terrain())

    near = shapely.buffer(shapely.union_all(surveyed), 40.0)
    buildings = prepared.load("buildings")["geoms"]
    shapely.prepare(near)
    return {
        "lines": lines,
        "rw": attrs[:, 0].astype(np.int8),
        "trafdir": attrs[:, 1].astype(np.int8),
        "lanes": attrs[:, 2].astype(np.int16),
        "parking": attrs[:, 3].astype(np.int16),
        "width": attrs[:, 4].astype(np.float32),
        "levels": attrs[:, 5:7].astype(np.int8),
        "survey": survey,
        "buildings": buildings[shapely.intersects(near, buildings)],
    }


def _ends_key(line) -> tuple:
    return tuple(np.round(shapely.get_coordinates(line)[[0, -1]] * 2.0).astype(np.int64).ravel().tolist())


def merged(data: dict, sunken: dict) -> tuple[dict, np.ndarray]:
    """overpasses.prepare's data (with the cantilever's roadways) and
    prepare()'s streets and highways below street level, and which segments
    are those."""
    out = dict(data)
    for key in ("lines", "rw", "trafdir", "lanes", "parking", "width", "levels"):
        out[key] = np.concatenate([data[key], sunken[key].astype(data[key].dtype)])
    added = np.arange(len(out["lines"])) >= len(data["lines"])
    return out, added


# Heights.

def _spread(seed: np.ndarray, cap: np.ndarray, ea: np.ndarray, eb: np.ndarray, length: np.ndarray,
            grade: float) -> np.ndarray:
    """The lowest of each variable's seed and its neighbors' (along the edges
    ea-eb, this long) plus `grade` per meter between them, all the way along
    (inf: no seed), never over `cap` on the way."""
    out = np.minimum(seed, cap)
    for _ in range(SPREAD_ROUNDS):
        step = out.copy()
        np.minimum.at(step, ea, out[eb] + grade * length)
        np.minimum.at(step, eb, out[ea] + grade * length)
        step = np.minimum(step, cap)
        if np.array_equal(step, out):
            break
        out = step
    return out


def _from_neighbors(value: np.ndarray, ea: np.ndarray, eb: np.ndarray, length: np.ndarray, grade: float) -> np.ndarray:
    """The lowest of each variable's neighbors' values plus `grade` per meter
    to them (not its own)."""
    out = np.full(len(value), np.inf)
    np.minimum.at(out, ea, value[eb] + grade * length)
    np.minimum.at(out, eb, value[ea] + grade * length)
    return out


def _close(mask: np.ndarray, ea: np.ndarray, eb: np.ndarray, length: np.ndarray, reach: float) -> np.ndarray:
    """mask with its gaps narrower than twice `reach` (meters along the
    roads) filled."""
    grown = _spread(np.where(mask, 0.0, np.inf), np.full(len(mask), np.inf), ea, eb, length, 1.0) <= reach
    return _spread(np.where(grown, np.inf, 0.0), np.full(len(mask), np.inf), ea, eb, length, 1.0) > reach


def _open(mask: np.ndarray, ea: np.ndarray, eb: np.ndarray, length: np.ndarray, reach: float) -> np.ndarray:
    """mask without its stretches shorter than twice `reach`."""
    kept = _spread(np.where(mask, np.inf, 0.0), np.full(len(mask), np.inf), ea, eb, length, 1.0) > reach
    return _spread(np.where(kept, 0.0, np.inf), np.full(len(mask), np.inf), ea, eb, length, 1.0) <= reach


def fit(network, survey: dict) -> dict:
    """The heights of the roads below street level (network: an
    overpasses.Network, its segments, levels, nodes and end heights so far),
    from the survey along them (prepare()'s "survey"): {segment: (distances
    along, heights, states)}: OPEN_STATE where nothing is over the road,
    BRIDGE_STATE under something short, TUNNEL_STATE in a tunnel. Ends where
    other roads meet get the heights too (network.ends)."""
    levels = network.levels
    lines = network.lines
    nodes = network.attrs["nodes"].astype(np.int64)
    rw = network.data["rw"]
    members = (levels.min(axis=1) < int(AT_GRADE)) & (levels.max(axis=1) <= int(AT_GRADE)) & ~network.stacked
    members &= rw != overpasses.PATH
    if network.structure is not None:
        # The roads on and off the triple cantilever are its own.
        ends = np.stack([shapely.get_coordinates(shapely.get_point(lines, 0)),
                         shapely.get_coordinates(shapely.get_point(lines, -1))], axis=1)
        members &= ~network.structure.near(ends.reshape(-1, 2)).reshape(-1, 2).any(axis=1)
    members = np.flatnonzero(members)
    if not len(members):
        return {}

    # Variables: a station along a segment, one per node.
    node_var, count = {}, 0
    index, stations = {}, {}
    edges, var_layers, var_points = [], {}, {}

    def new_vars(n):
        nonlocal count
        out = np.arange(count, count + n)
        count += n
        return out
    for k in members:
        line = lines[k]
        found = survey.get(lidar._key(line))
        if found is not None:
            s, layers = found[0].astype(np.float64), found[1].astype(np.float64)
        else:
            s = np.linspace(0.0, line.length, max(2, int(np.ceil(line.length / STATION_STEP)) + 1))
            layers = np.full((len(s), lidar.MAX_LAYERS), np.nan)
        idx = np.empty(len(s), dtype=np.int64)
        for i, node in ((0, nodes[k, 0]), (-1, nodes[k, 1])):
            if node not in node_var:
                node_var[node] = new_vars(1)[0]
            idx[i] = node_var[node]
        if len(s) > 2:
            idx[1:-1] = new_vars(len(s) - 2)
        edges.append(np.column_stack([idx[:-1], idx[1:], np.maximum(np.diff(s), 0.5)]))
        index[k], stations[k] = idx, s
        points = shapely.get_coordinates(shapely.line_interpolate_point(line, s))
        for v, row, p in zip(idx.tolist(), layers, points):
            var_layers.setdefault(v, row)
            var_points.setdefault(v, p)
    edges = np.concatenate(edges)
    ea, eb, el = edges[:, 0].astype(np.int64), edges[:, 1].astype(np.int64), edges[:, 2]
    layers = np.array([var_layers[v] for v in range(count)])
    points = np.array([var_points[v] for v in range(count)])
    lowest = np.nanmin(np.where(np.isnan(layers), np.inf, layers), axis=1)
    lowest[~np.isfinite(lowest)] = np.nan

    # The street around each station, and the ends held on it.
    angles = np.arange(8) * (np.pi / 4)
    ring = np.vstack([np.column_stack([np.cos(angles), np.sin(angles)]) * r for r in DEPTH_RING])
    around = np.percentile(network.grade((points[:, None, :] + ring[None]).reshape(-1, 2)).reshape(count, -1),
                           75, axis=1)
    held = np.zeros(count, dtype=bool)
    held_y = np.zeros(count)
    for k in members:
        for i, end in ((0, 0), (-1, 1)):
            if levels[k, end] >= int(AT_GRADE):
                v = index[k][i]
                held[v], held_y[v] = True, network.ends[k, end]
    usable = np.isfinite(lowest) & (lowest > around - MAX_DEPTH)
    # Lowest surfaces another station's surfaces back up.
    support = np.zeros(count, dtype=bool)
    for a, b in ((ea, eb), (eb, ea)):
        close = np.abs(layers[b] - lowest[a][:, None]) <= GRADE * el[:, None] + SUPPORT_TOLERANCE
        support[a[close.any(axis=1)]] = True
    usable &= support | held

    # Which surfaces are the road: those no higher than the road could have
    # come up to from the road elsewhere, never coming up through what's over
    # it; surfaces JUMP higher than that are over it.
    road = usable.copy()
    over = np.zeros(count, dtype=bool)
    lid = usable & (lowest >= around - LID_DEPTH)
    for _ in range(CLASSIFY_ROUNDS):
        seed = np.where(held, held_y, np.where(road, lowest, np.inf))
        cap = np.where(over & ~held, lowest - CLEAR, np.inf)
        reach = _from_neighbors(_spread(seed, cap, ea, eb, el, GRADE), ea, eb, el, GRADE)
        jump = _from_neighbors(_spread(seed, cap, ea, eb, el, JUMP_GRADE), ea, eb, el, JUMP_GRADE) + JUMP
        now = usable & (lowest <= reach + TOLERANCE)
        now_over = lid & (lowest > jump)
        if np.array_equal(now, road) and np.array_equal(now_over, over):
            break
        road, over = now, now_over

    # Covered stretches: where something is over the road (gaps shorter than
    # MIN_OPEN closed). Those where the survey can't see the road for it, at
    # least TUNNEL long, are tunnels (gaps at the street around's level
    # between them are their lid too); the rest are bridges.
    above = np.where(layers >= np.where(road, lowest, np.inf)[:, None] + CLEAR - TOLERANCE, layers, np.inf).min(axis=1)
    shallow = np.isfinite(lowest) & (lowest >= around - LID_DEPTH)
    hidden = over | (_close(over, ea, eb, el, LID_GAP / 2) & (shallow | ~np.isfinite(lowest)))
    # (Under a bridge outline, however wide, the road is under a bridge.)
    outlines = network.data["outlines"]
    under = np.zeros(count, dtype=bool)
    under[shapely.STRtree(outlines).query(shapely.points(points), predicate="within")[0]] = True
    tunnel = _open(hidden & ~under, ea, eb, el, TUNNEL / 2)
    covered = tunnel | _close(over | np.isfinite(above), ea, eb, el, MIN_OPEN / 2)
    lidded = tunnel & shallow

    # Then fit the road's heights to the surfaces: held at the street at
    # street-level ends, CLEAR under what's over it, never deeper than
    # MAX_DEPTH nor under MIN_ROAD, leaning a little on the level codes where
    # the survey has nothing.
    prior = np.full(count, np.nan)
    for k in members:
        t = stations[k] / max(lines[k].length, 1e-6)
        code = levels[k, 0] + (levels[k, 1] - levels[k, 0]) * t
        prior[index[k]] = around[index[k]] - np.maximum(int(AT_GRADE) - code, 0.0) / LEVEL_STEP * LEVEL_DEPTH
    ceiling = np.minimum(np.where(over | lidded, lowest, np.inf), above) - CLEAR
    floor = np.maximum(around - MAX_DEPTH, MIN_ROAD)
    ceiling = np.maximum(ceiling, floor)
    seen = road & ~lidded
    weight = np.where(seen, MEASURE, 0.0)
    target = np.where(seen, lowest, 0.0)
    x = np.where(seen, lowest, np.where(held, held_y, prior))
    limit_idx, limit_val = np.zeros(0, dtype=np.int64), np.zeros(0)
    for _ in range(LIMIT_ROUNDS + 1):
        diag = weight + PRIOR + np.where(held, HOLD, 0.0)
        rhs = weight * target + PRIOR * prior + np.where(held, HOLD * held_y, 0.0)
        np.add.at(diag, limit_idx, HOLD)
        np.add.at(rhs, limit_idx, HOLD * limit_val)
        x = overpasses._solve(count, ea, eb, SMOOTH / el, diag, rhs, x)
        low = np.flatnonzero((x < floor - LIMIT_SLACK) & ~held)
        high = np.flatnonzero((x > ceiling + LIMIT_SLACK) & ~held)
        if not len(low) and not len(high):
            break
        limit_idx = np.concatenate([limit_idx, low, high])
        limit_val = np.concatenate([limit_val, floor[low], ceiling[high]])
    state = np.where(tunnel, TUNNEL_STATE, np.where(covered, BRIDGE_STATE, OPEN_STATE)).astype(np.int8)

    out = {}
    for k in members:
        h = x[index[k]]
        out[int(k)] = (stations[k], h, state[index[k]])
    # Every end at these nodes gets their height (ramps climbing out of a cut
    # onto a viaduct start from it).
    var_height = {node: x[v] for node, v in node_var.items()}
    for k in range(network.count):
        for end in (0, 1):
            node = int(nodes[k, end])
            if node in var_height and levels[k, end] < int(AT_GRADE):
                network.ends[k, end] = var_height[node]
    length = float(shapely.length(lines[members]).sum())
    print(f"  trenches: {len(members)} roads below street level ({length / 1000:.0f} km), the survey sees the road at "
          f"{road.mean():.0%} of {count:,} stations, something over it at {covered.mean():.0%}, "
          f"{tunnel.sum() * STATION_STEP / 1000:.0f} km in tunnels", flush=True)
    return out


class Trenches:
    """The sunken roads' cuts: where the ground is cut away (cut, a polygon),
    the road's surface in it (road()), the ground around it (outside()), and
    the streets bridging over it (bridges: [(deck polygon, crossings)], each
    crossing a (line, half width, height at its start, at its end), the line
    None for an outline no street crosses), with the bridge outlines they take
    (claimed, which overpasses.build leaves out), and the tunnels' portals
    (portals: [(segment, distance along it, +1 if the tunnel goes on along
    it, -1 back, half width)])."""

    def __init__(self, data: dict, network, streets: dict):
        self.network = network
        lines = network.lines
        self.members = np.array(sorted(network.sunken), dtype=np.int64)
        self.member_tree = shapely.STRtree(lines[self.members]) if len(self.members) else None
        # Each road's strip out to the cut's walls, but for its tunnels (and
        # their portals: segment, distance along, which way in, half width).
        strips, self.portals = [], []
        survey = data["survey"]
        for k in self.members:
            s, h, state = network.sunken[int(k)]
            half = float(network.width[k]) / 2.0 + SHOULDER
            found = survey.get(lidar._key(lines[k]))
            if found is not None and len(found[0]) == len(s):
                left, right = _walls(found[2], h, state == OPEN_STATE, half)
            else:
                left = right = np.full(len(s), half)
            for a, b in _open_runs(s, state != TUNNEL_STATE, lines[k].length):
                if b - a < 1.0:
                    continue
                strips.append(_strip(lines[k], s, left, right, a, b))
                for at, ahead in ((a, -1.0), (b, 1.0)):
                    if 0.5 < at < lines[k].length - 0.5:
                        self.portals.append((int(k), at, ahead, half))
        cut = shapely.union_all(strips) if strips else shapely.Polygon()
        cut = shapely.buffer(shapely.buffer(cut, MEDIAN, join_style="mitre"), -MEDIAN, join_style="mitre")
        buildings = data["buildings"]
        near = buildings[shapely.intersects(cut, buildings)] if len(buildings) else buildings
        if len(near):
            cut = shapely.difference(cut, shapely.union_all(shapely.buffer(near, BUILDING_GAP, join_style="mitre")))
        if network.structure is not None:
            cut = shapely.difference(cut, network.structure.reach)

        # Streets over the cut: those crossing it bridge it; those running
        # along it keep their ground.
        level = network.levels
        at_grade = np.flatnonzero((level.min(axis=1) >= int(AT_GRADE)) & (level.max(axis=1) <= int(AT_GRADE))
                                  & (network.data["rw"] != overpasses.PATH))
        street_lines = np.concatenate([streets["lines"], lines[at_grade]])
        street_half = np.concatenate([np.where(streets["width"] > 0, streets["width"] / 2.0, DEFAULT_HALF),
                                      network.width[at_grade] / 2.0])
        crossings, along = [], []
        shapely.prepare(cut)
        for k in shapely.STRtree(street_lines).query(cut, predicate="intersects"):
            for piece in lines_of(shapely.intersection(street_lines[k], cut)):
                if piece.length < CROSSING_MIN:
                    continue
                if self._crossing_sine(piece) >= CROSSING_SINE:
                    crossings.append(k)
                else:
                    along.append(shapely.buffer(piece, float(street_half[k]) + STREET_GAP, cap_style="flat"))
        if along:
            cut = shapely.difference(cut, shapely.union_all(along))
        cut = shapely.union_all(polygons_of(cut, 5.0))
        self.cut = shapely.orient_polygons(shapely.simplify(cut, 0.1))
        shapely.prepare(self.cut)
        self.reach = shapely.buffer(self.cut, FILL_REACH + 1.0)
        shapely.prepare(self.reach)
        self.bounds = self.reach.bounds if not self.reach.is_empty else (0.0, 0.0, 0.0, 0.0)
        self._edge_levels()

        # The bridges: each crossing street across the cut, with the outlines
        # over the cut.
        spans = {}
        for k in sorted(set(crossings)):
            for span in lines_of(shapely.intersection(street_lines[k], self.cut)):
                if span.length >= CROSSING_MIN:
                    spans[_ends_key(span)] = (span, float(street_half[k]))
        spans = list(spans.values())
        self.claimed = self._claim(network)
        areas = [shapely.buffer(span, half + SIDEWALK, cap_style="flat") for span, half in spans] + self.claimed
        decks = polygons_of(shapely.intersection(shapely.union_all(areas), self.cut), 1.0) if areas else []
        self.bridges = []
        span_tree = shapely.STRtree([span for span, _ in spans]) if spans else None
        for deck in decks:
            mine = [spans[j] for j in span_tree.query(deck, predicate="intersects")] if span_tree is not None else []
            parts = []
            for span, half in mine:
                coords = shapely.get_coordinates(span)
                out = np.array([coords[0] - coords[1], coords[-1] - coords[-2]])
                out /= np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)
                h = self._landing(coords[[0, -1]] + out * LANDING)
                parts.append((span, half, float(h[0]), float(h[1])))
            if not parts:
                # An outline with no street across it: level with the ground at its edges.
                ring = shapely.get_coordinates(shapely.segmentize(shapely.buffer(deck, LANDING).exterior, 2.0))
                ring = ring[~shapely.contains_xy(self.cut, ring[:, 0], ring[:, 1])]
                if not len(ring):
                    continue
                y = float(np.median(self._landing(ring)))
                parts.append((None, 0.0, y, y))
            self.bridges.append((shapely.orient_polygons(shapely.simplify(deck, 0.1)), parts))
        decks = [deck for deck, _ in self.bridges]
        self.bridge_areas = shapely.union_all(decks) if decks else shapely.Polygon()
        shapely.prepare(self.bridge_areas)
        self.bridge_tree = shapely.STRtree(decks) if decks else None
        # Where nothing stands but the road.
        self.closed = shapely.difference(self.cut, self.bridge_areas)
        shapely.prepare(self.closed)
        print(f"  trenches: {len(self.members)} roads below street level, cuts {self.cut.area / 1e6:.2f} km2, "
              f"{len(self.bridges)} bridges over them ({len(self.claimed)} outlines), "
              f"{len(along)} streets along them", flush=True)

    def _crossing_sine(self, piece) -> float:
        """The sine of the angle between a line inside the cut and the
        sunken road nearest its middle."""
        middle = shapely.line_interpolate_point(piece, 0.5, normalized=True)
        k = int(self.members[self.member_tree.query_nearest(middle)[0]])
        road = self.network.lines[k]
        at = road.project(middle)
        a = np.asarray(road.interpolate(max(at - 2.0, 0.0)).coords[0])
        b = np.asarray(road.interpolate(min(at + 2.0, road.length)).coords[0])
        coords = shapely.get_coordinates(piece)
        d, t = coords[-1] - coords[0], b - a
        return abs(float(d[0] * t[1] - d[1] * t[0])) / max(float(np.linalg.norm(d) * np.linalg.norm(t)), 1e-9)

    def _claim(self, network) -> list:
        """The bridge outline parts over the cut that no raised road runs
        over (overpasses.build leaves them to the cut's bridges)."""
        out = []
        raised = np.flatnonzero(network.levels.max(axis=1) > int(AT_GRADE))
        tree = shapely.STRtree(network.lines[raised]) if len(raised) else None
        for outline in network.data["outlines"]:
            if not shapely.intersects(self.cut, outline):
                continue
            for part in polygons_of(outline, OUTLINE_PART):
                over = shapely.area(shapely.intersection(part, self.cut))
                if over < min(OUTLINE_SHARE * part.area, OUTLINE_AREA):
                    continue
                if tree is not None:
                    through = network.lines[raised[tree.query(part, predicate="intersects")]]
                    if len(through) and (shapely.length(shapely.intersection(through, part)) >= 1.0).any():
                        continue
                out.append(part)
        return out

    def _landing(self, en: np.ndarray) -> np.ndarray:
        """The street's surface at points around the cut (outside it)."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        return self.outside(en, self.network.grade_lattice.height(en)) - CURB_HEIGHT

    # Heights.

    def near(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) points are within reach of the cuts' ground."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        min_e, min_n, max_e, max_n = self.bounds
        box = (en[:, 0] >= min_e) & (en[:, 0] <= max_e) & (en[:, 1] >= min_n) & (en[:, 1] <= max_n)
        out = np.zeros(len(en), dtype=bool)
        if box.any():
            out[box] = shapely.contains_xy(self.reach, en[box, 0], en[box, 1])
        return out

    def inside(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) points are in a cut, not on a bridge over it (nothing
        stands there but the road)."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.zeros(len(en), dtype=bool)
        near = self.near(en)
        if near.any():
            out[near] = shapely.contains_xy(self.closed, en[near, 0], en[near, 1])
        return out

    def road(self, en: np.ndarray) -> np.ndarray:
        """The road's surface in the cut at (N, 2) points: the nearest sunken
        road's height, blended with the others' within FIELD_BLEND."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if len(en) == 0 or self.member_tree is None:
            return np.zeros(len(en))
        network = self.network
        points = shapely.points(en)
        nearest = self.member_tree.query_nearest(points, return_distance=False, all_matches=False)
        near = self.member_tree.query(points, predicate="dwithin", distance=FIELD_BLEND)
        point, j = np.unique(np.concatenate([nearest, near], axis=1), axis=1)
        heights = np.empty(len(point))
        for one in np.unique(j):
            mask = j == one
            heights[mask] = network.along(int(self.members[one]), en[point[mask]])
        weight = 1.0 / (shapely.distance(network.lines[self.members[j]], points[point]) + 1.0) ** 2
        total = np.bincount(point, weights=weight, minlength=len(en))
        return np.bincount(point, weights=weight * heights, minlength=len(en)) / total

    def floor(self, en: np.ndarray) -> np.ndarray:
        """The ground in the cut, under the road's surface."""
        return self.road(en) - FLOOR_DROP

    def outside(self, en: np.ndarray, ground: np.ndarray) -> np.ndarray:
        """The ground around the cuts (`ground` at (N, 2) points, as the
        lattice has it), within FILL_REACH of the edge of a cut at least
        FILL_DEPTH deep (on it too) brought up to the elevation model's ground
        FILL_REACH out from that edge (_edge_levels)."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.array(ground, np.float64, copy=True)
        near = self.near(en)
        if not near.any() or self.edge_tree is None:
            return out
        idx = np.flatnonzero(near)
        point, edge = self.edge_tree.query_nearest(shapely.points(en[idx]), max_distance=FILL_REACH, all_matches=False)
        idx, edge = idx[point], edge
        outside = ~shapely.contains_xy(self.cut, en[idx, 0], en[idx, 1])
        idx, edge = idx[outside], edge[outside]
        out[idx] = np.maximum(out[idx], self.edge_level[edge])
        return out

    def _edge_levels(self):
        """Points every EDGE_STEP along the edges of the cuts at least
        FILL_DEPTH deep, and the elevation model's ground FILL_REACH out from
        each (the cut's rings run with it on their left)."""
        points, levels = [], []
        for part in polygons_of(self.cut, 1.0):
            for ring in (part.exterior, *part.interiors):
                coords = np.asarray(shapely.segmentize(ring, EDGE_STEP).coords)[:-1, :2]
                if len(coords) < 3:
                    continue
                level = self.network.terrain.height(_right_of(coords, FILL_REACH))
                deep = level - self.road(coords) >= FILL_DEPTH
                points.append(coords[deep])
                levels.append(level[deep])
        points = np.concatenate(points) if points else np.zeros((0, 2))
        self.edge_level = np.concatenate(levels) if levels else np.zeros(0)
        self.edge_tree = shapely.STRtree(shapely.points(points)) if len(points) else None

    def over(self, en: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """(heights, found): the bridges' decks over (N, 2) points."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.zeros(len(en))
        found = np.zeros(len(en), dtype=bool)
        if self.bridge_tree is None or len(en) == 0:
            return out, found
        point, deck = self.bridge_tree.query(shapely.points(en), predicate="intersects")
        for one in np.unique(deck):
            mask = point[deck == one]
            out[mask] = _deck_height(self.bridges[one][1], en[mask])
            found[mask] = True
        return out, found

    def ground(self, lattice) -> "Ground":
        return Ground(lattice, self)


def _deck_height(parts: list, en: np.ndarray) -> np.ndarray:
    """A bridge deck's height at (N, 2) points: its nearest crossing street's,
    straight between the street at its ends."""
    best = np.full(len(en), np.inf)
    out = np.zeros(len(en))
    points = shapely.points(en)
    for span, _, h0, h1 in parts:
        if span is None:
            d = np.zeros(len(en))
            y = np.full(len(en), h0)
        else:
            d = shapely.distance(span, points)
            y = h0 + (h1 - h0) * shapely.line_locate_point(span, points, normalized=True)
        closer = d < best
        best[closer], out[closer] = d[closer], y[closer]
    return out


def _walls(across: np.ndarray, road: np.ndarray, seen: np.ndarray, half: float) -> tuple[np.ndarray, np.ndarray]:
    """How far left and right of a road its cut reaches at each station: out
    to where the survey's lowest surface across it (lidar.prepare_sunken's
    `across`) rises WALL_RISE over the road for two bins running, between
    half (the road's own half width and shoulder) and half + MAX_WIDEN; where
    it doesn't, or the road isn't `seen` in the open, half (smoothed along
    the road over WALL_SMOOTH stations)."""
    offsets = lidar.offsets()
    middle = len(offsets) // 2
    out = []
    for side in (np.arange(middle, len(offsets)), np.arange(middle, -1, -1)):
        rel = across[:, side] - road[:, None]
        high = rel > WALL_RISE
        rising = high[:, :-1] & (high[:, 1:] | np.isnan(rel[:, 1:]))
        first = np.where(rising.any(axis=1), np.argmax(rising, axis=1), -1)
        reach = np.abs(offsets[side][np.maximum(first, 0)]) - lidar.ACROSS_STEP / 2.0
        reach = np.where((first > 0) & seen, np.clip(reach, half, half + MAX_WIDEN), np.nan)
        out.append(reach)
    smooth = []
    for reach in out:
        padded = np.concatenate([np.full(WALL_SMOOTH // 2, np.nan), reach, np.full(WALL_SMOOTH // 2, np.nan)])
        window = np.lib.stride_tricks.sliding_window_view(padded, WALL_SMOOTH)
        with np.errstate(all="ignore"):
            value = np.nanmedian(np.where(np.isnan(window).all(axis=1, keepdims=True), half, window), axis=1)
        smooth.append(np.where(np.isnan(value), half, value))
    return smooth[0], smooth[1]


def _strip(line, s: np.ndarray, left: np.ndarray, right: np.ndarray, a: float, b: float):
    """The polygon from `left` to `right` of a line (given at its stations s)
    between distances a and b along it."""
    at = np.linspace(a, b, max(2, int(np.ceil((b - a) / STRIP_STEP)) + 1))
    points, normal = markings._frame(line, at)
    lo, hi = np.interp(at, s, left), np.interp(at, s, right)
    ring = np.vstack([points + normal * lo[:, None], (points - normal * hi[:, None])[::-1]])
    return shapely.union_all(polygons_of(shapely.make_valid(shapely.Polygon(ring)), 0.1))


def _open_runs(s: np.ndarray, keep: np.ndarray, length: float) -> list:
    """(start, end) distances along a road of its runs of stations where
    `keep`, each reaching halfway to the next station."""
    out = []
    bounds = np.concatenate([[0.0], (s[1:] + s[:-1]) / 2.0, [length]])
    start = None
    for i, value in enumerate(keep.tolist() + [False]):
        if value and start is None:
            start = bounds[i]
        elif not value and start is not None:
            out.append((float(start), float(bounds[i])))
            start = None
    return out


class Ground:
    """A ground lattice (terrain.Lattice, or cantilever.Ground) with the
    sunken roads' cuts in it: the ground cut down under the road's surface,
    the streets on their bridges over the cuts, and the ground around them
    brought up past the cuts' blurred edges. regions() leaves the cuts out of
    the ground's mesh (the road's surface covers them)."""

    def __init__(self, lattice, trenches: Trenches):
        self.lattice = lattice
        self.trenches = trenches
        self.cell = lattice.cell

    def height(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        h = self.lattice.height(en)
        trenches = self.trenches
        near = trenches.near(en)
        if not near.any():
            return h
        pts = en[near]
        sub = trenches.outside(pts, h[near])
        inside = shapely.contains_xy(trenches.cut, pts[:, 0], pts[:, 1])
        if inside.any():
            sub[inside] = trenches.floor(pts[inside])
            # Streets over it are on their bridges.
            y, found = trenches.over(pts[inside])
            sub[np.flatnonzero(inside)[found]] = y[found] + CURB_HEIGHT
        h[near] = sub
        return h

    def normal(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if not self.trenches.near(en).any():
            return self.lattice.normal(en)
        return _normal(self.height, en, self.cell)

    def walls(self, bounds) -> list:
        return self.lattice.walls(bounds) if hasattr(self.lattice, "walls") else []

    def regions(self, polys: list) -> list:
        """[(terrain, polygons)]: the lattice's own regions, but for the parts
        in the cuts, on the ground around them."""
        inner = self.lattice.regions(polys) if hasattr(self.lattice, "regions") else [(self.lattice, polys)]
        box = shapely.box(*self.trenches.bounds)
        out = []
        for terrain, parts in inner:
            rest = []
            for poly in parts:
                if not shapely.intersects(box, poly) or not shapely.intersects(self.trenches.cut, poly):
                    rest.append(poly)
                else:
                    rest += polygons_of(shapely.difference(poly, self.trenches.cut), 0.01)
            out.append((_Around(self.trenches, terrain), rest))
        return out

    def __getattr__(self, name):
        return getattr(self.lattice, name)


class _Around:
    """One of the lattice's regions' terrains, with the ground around the
    cuts brought up."""

    def __init__(self, trenches: Trenches, terrain):
        self.trenches = trenches
        self.terrain = terrain
        self.cell = terrain.cell

    def height(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        return self.trenches.outside(en, self.terrain.height(en))

    def normal(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if not self.trenches.near(en).any():
            return self.terrain.normal(en)
        return _normal(self.height, en, self.cell)


def _normal(height, en: np.ndarray, d: float) -> np.ndarray:
    """Unit normals (Godot space) of a height function at (N, 2) points, by
    central differences `d` apart."""
    offsets = np.array([[d, 0.0], [-d, 0.0], [0.0, d], [0.0, -d]])
    h = height((en[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(-1, 4)
    normal = np.column_stack([-(h[:, 0] - h[:, 1]) / (2 * d), np.ones(len(en)), (h[:, 2] - h[:, 3]) / (2 * d)])
    return normal / np.linalg.norm(normal, axis=1, keepdims=True)


# Building it.

def build(network, buckets: dict, level_sizes: dict, cells: dict) -> None:
    """Adds the cuts to bridges.build's buckets (with collision up close):
    the road's surface over them, their walls (from the ground around as each
    level's lattice, `cells` meters, has it) with parapets up close, the
    tunnels' portals, and the streets' bridges over them; the bridges' tops
    to "street_decks" (what stands on them, overpasses.OnDecks)."""
    trenches = network.trenches
    builders = {level: MeshBuilder() for level in level_sizes}
    for piece in _pieces(trenches.cut):
        cantilever._add_top(piece, trenches.road, ROAD_TOP, builders)
    portals = [_portal(trenches, *portal) for portal in trenches.portals]
    runs, lamps = 0, []
    for level in level_sizes:
        lattice = network.terrain.lattice(cells[level])
        if network.structure is not None:
            lattice = network.structure.ground(lattice)
        runs += _add_walls(trenches, trenches.ground(lattice), cells[level] / 2, portals, builders, level,
                           lamps if level == "lod0" else None)
    if lamps:
        overpasses._merge_lamps(buckets.setdefault("lamps", {}), lamps, level_sizes["lod0"])
    for portal in portals:
        _add_portal(portal, {level: builders[level] for level in NEAR if level in builders})
    street_decks = []
    inner = shapely.buffer(trenches.cut, -0.3)  # (the cut but for its edges)
    shapely.prepare(inner)
    for deck, parts in trenches.bridges:
        top = _add_bridge(deck, parts, inner, builders)
        if top is not None:
            street_decks.append(top)
    for level, size in level_sizes.items():
        overpasses._merge(buckets.setdefault(level, {}), overpasses._bucket(builders[level], size))
    buckets["street_decks"] = buckets.get("street_decks", []) + street_decks
    print(f"  trenches: {len(street_decks)} bridges over the cuts, {len(portals)} tunnel portals, "
          f"{runs} runs of wall", flush=True)


def _pieces(poly, size: float = 250.0) -> list:
    """A polygon cut along a `size`-meter grid (so the decks' grids stay
    small)."""
    out = []
    for part in polygons_of(poly, 0.01):
        min_e, min_n, max_e, max_n = part.bounds
        for i in range(int(np.floor(min_e / size)), int(np.ceil(max_e / size))):
            for j in range(int(np.floor(min_n / size)), int(np.ceil(max_n / size))):
                box = shapely.box(i * size, j * size, (i + 1) * size, (j + 1) * size)
                out += polygons_of(shapely.intersection(part, box), 0.01)
    return out


def _add_walls(trenches: Trenches, ground, step: float, portals: list, builders: dict, level: str,
               lamps: list | None) -> int:
    """The walls along the cuts' edges in one level: retaining walls from
    under the road's surface up to the ground around, where that's higher
    (from a portal's opening's top up, over a portal), with a parapet along
    their tops up close; side walls down to the ground around, where that's
    lower. With `lamps`, adds the street lights along the retaining walls
    PARAPET_FROM high or more ((points, heights, arms), as
    overpasses._merge_lamps takes them). Returns how many runs of retaining
    wall."""
    runs = 0
    keep_off = shapely.buffer(trenches.bridge_areas, 1.0) if not trenches.bridge_areas.is_empty else None
    for part in polygons_of(trenches.cut, 1.0):
        # Counter-clockwise (holes clockwise): the cut on their left.
        for ring in (part.exterior, *part.interiors):
            coords = np.asarray(shapely.segmentize(ring, step).coords)[:, :2]
            if len(coords) < 2:
                continue
            openings = [portal for portal in portals if level in NEAR and shapely.intersects(portal["mouth"], ring)]
            ceiling = np.full(len(coords), -np.inf)
            for portal in openings:
                coords, ceiling, inside = _split_at(coords, ceiling, portal["mouth"])
                ceiling[inside] = np.maximum(ceiling[inside], portal["ceiling"])
            road = trenches.road(coords)
            # (The ground around as its mesh has it along the edge.)
            around = trenches.outside(coords, ground.lattice.height(coords))
            bottom = np.maximum(road - WALL_FOOT, ceiling)
            retaining = around > road + WALL_MIN
            for start, stop in overpasses._runs(retaining[:-1] | retaining[1:]):
                run = slice(start, stop + 1)
                # Facing into the cut.
                cantilever._wall(builders, coords[run][::-1], bottom[run][::-1],
                                 np.maximum(around[run], bottom[run])[::-1], WALL, levels=(level,))
                runs += 1
                if level in NEAR:
                    high = around[run] - road[run] >= PARAPET_FROM
                    if keep_off is not None:
                        high &= ~shapely.contains_xy(keep_off, coords[run][:, 0], coords[run][:, 1])
                    for a, b in overpasses._runs(high[:-1] & high[1:]):
                        _parapet(builders, coords[run][a:b + 1], around[run][a:b + 1], level)
            if lamps is not None and len(coords) > 2:
                points, heights, arms = props.deck_lamps(coords, trenches.road)
                deep = ground.height(points + arms * -(props.DECK_LAMP_INSET + 0.05)) - heights >= PARAPET_FROM
                deep &= ~trenches.over(points)[1]
                if deep.any():
                    lamps.append((points[deep], heights[deep], arms[deep]))
            lower = around < road - WALL_MIN
            for start, stop in overpasses._runs(lower[:-1] & lower[1:]):
                run = slice(start, stop + 1)
                cantilever._wall(builders, coords[run], around[run] - WALL_FOOT, road[run], WALL, levels=(level,))
    return runs


def _split_at(coords: np.ndarray, values: np.ndarray, poly) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """A line's points (with a value each) with two more where it crosses a
    polygon's edge (so what changes there changes at once), and which points
    are in the polygon (of the two, the one on its side)."""
    inside = shapely.contains_xy(poly, coords[:, 0], coords[:, 1])
    out_coords, out_values, out_inside = [coords[:1]], [values[:1]], [inside[:1]]
    for i in range(1, len(coords)):
        if inside[i] != inside[i - 1]:
            crossing = shapely.intersection(shapely.LineString(coords[i - 1:i + 1]), poly.boundary)
            hit = shapely.get_coordinates(crossing)
            if len(hit):
                at = hit[np.argmin(np.linalg.norm(hit - coords[i - 1], axis=1))][None]
                out_coords += [at, at]
                out_values += [values[i - 1:i], values[i:i + 1]]
                out_inside += [inside[i - 1:i], inside[i:i + 1]]
        out_coords.append(coords[i:i + 1])
        out_values.append(values[i:i + 1])
        out_inside.append(inside[i:i + 1])
    return np.concatenate(out_coords), np.concatenate(out_values), np.concatenate(out_inside)


def _right_of(coords: np.ndarray, distance: float) -> np.ndarray:
    """Points `distance` to the right of a line's travel from its points."""
    coords = np.asarray(coords, np.float64)
    step = np.gradient(coords, axis=0)
    step /= np.maximum(np.linalg.norm(step, axis=1, keepdims=True), 1e-9)
    return coords + np.column_stack([step[:, 1], -step[:, 0]]) * distance


def _parapet(builders: dict, coords: np.ndarray, base: np.ndarray, level: str) -> None:
    """A concrete parapet PARAPET high and PARAPET_THICK thick along a
    retaining wall's top (coords with the cut on their left)."""
    back = _right_of(coords, PARAPET_THICK)
    cantilever._wall(builders, coords[::-1], base[::-1], base[::-1] + PARAPET, WALL, levels=(level,))
    cantilever._wall(builders, back, base - WALL_FOOT, base + PARAPET, WALL, levels=(level,))
    _cap(builders, coords, back, base + PARAPET, (level,))


def _cap(builders: dict, a: np.ndarray, b: np.ndarray, y: np.ndarray, levels) -> None:
    """The flat top between two lines of points side by side, at heights y
    (the shader draws both sides of walls, so walls with two faces need a
    thickness and a top)."""
    quads = np.stack([a[:-1], a[1:], b[1:], b[:-1]], axis=1)
    heights = np.stack([y[:-1], y[1:], y[1:], y[:-1]], axis=1)
    for level in levels:
        if level not in builders:
            continue
        for tri in ((0, 1, 2), (0, 2, 3)):
            q = quads[:, tri]
            pos = np.stack([q[..., 0], heights[:, tri], -q[..., 1]], axis=-1)
            builders[level].add(pos, np.stack([q[..., 0], -q[..., 1]], axis=-1), WALL, (0.0, 1.0, 0.0))


def _portal(trenches: Trenches, k: int, at: float, ahead: float, half: float) -> dict:
    """A tunnel's portal where a cut's road (segment k, `at` along it) goes on
    under a lid (`ahead` +1 along the line, -1 back): the cut's edge across
    its mouth, the tunnel PORTAL_DEPTH in, and the top of its opening."""
    line = trenches.network.lines[k]
    inner = float(np.clip(at + ahead * PORTAL_DEPTH, 0.0, line.length))
    piece = shapely.ops.substring(line, min(at, inner), max(at, inner))
    if ahead < 0:
        piece = shapely.LineString(np.asarray(piece.coords)[::-1])
    road = float(trenches.network.along(k, np.asarray(line.interpolate(at).coords)[:, :2])[0])
    # Under the ground over it, however thin the lid.
    box = shapely.buffer(piece, half, cap_style="flat")
    over = shapely.get_coordinates(shapely.segmentize(box.exterior, 5.0))
    lid = float(trenches.network.grade(over).min()) + CURB_HEIGHT - LID_THICKNESS
    # (Its opening: the tunnel's width, from a little before the cut's edge.)
    outer = float(np.clip(at - ahead * 1.0, 0.0, line.length))
    mouth = shapely.buffer(shapely.ops.substring(line, min(outer, inner), max(outer, inner)), half, cap_style="flat")
    return {"line": piece, "half": half, "road": road, "ceiling": max(min(road + PORTAL_CLEAR, lid), road + 2.0),
            "mouth": mouth}


def _add_portal(portal: dict, builders: dict) -> None:
    """A tunnel's first PORTAL_DEPTH past its portal (up close): walls either
    side, the road and a ceiling over it, and a wall closing its far end."""
    line, half, ceiling = portal["line"], portal["half"], portal["ceiling"]
    if line.length < 1.0:
        return
    s = np.linspace(0.0, line.length, max(2, int(np.ceil(line.length / 5.0)) + 1))
    points, normal = markings._frame(line, s)
    bottom = portal["road"] - WALL_FOOT
    left, right = points + normal * half, points - normal * half
    # Facing in: the tunnel on their right.
    cantilever._wall(builders, left[::-1], bottom, ceiling, WALL)
    cantilever._wall(builders, right, bottom, ceiling, WALL)
    cantilever._wall(builders, np.array([left[-1], right[-1]]), bottom, ceiling, WALL)
    box = shapely.buffer(line, half, cap_style="flat")
    cantilever._add_top(box, lambda en: np.full(len(en), portal["road"]), ROAD_TOP, builders)
    cantilever._add_underside(box, lambda en: np.full(len(en), ceiling), builders, depth=0.0)


def _add_bridge(deck, parts: list, inner, builders: dict):
    """A street's bridge over a cut: its top (road along the street, sidewalk
    beside it), its underside, and along its edges over the cut (`inner`, the
    cut but for its edges) a fascia and parapets. Returns its top's lod0
    triangles (or None)."""
    def deck_y(en):
        return _deck_height(parts, np.asarray(en, np.float64).reshape(-1, 2))
    roads = [shapely.buffer(span, half, cap_style="flat") for span, half, _, _ in parts if span is not None]
    road = shapely.intersection(deck, shapely.union_all(roads)) if roads else deck
    tops = [cantilever._add_top(road, deck_y, ROAD_TOP, builders)]
    if roads:
        tops.append(cantilever._add_top(shapely.difference(deck, road), deck_y, SIDEWALK_TOP, builders))
    cantilever._add_underside(deck, deck_y, builders, depth=BRIDGE_DEPTH)
    # (Counter-clockwise: the deck on their left.)
    for part in polygons_of(deck, 1.0):
        ring = shapely.LineString(np.asarray(shapely.orient_polygons(part).exterior.coords))
        local = shapely.clip_by_rect(inner, *shapely.buffer(part, 1.0).bounds)
        for line in lines_of(shapely.intersection(ring, local)):
            coords = np.asarray(shapely.segmentize(line, 5.0).coords)[:, :2]
            y = deck_y(coords)
            inner = _right_of(coords, -PARAPET_THICK)
            cantilever._wall(builders, coords, y - BRIDGE_DEPTH, y + BRIDGE_PARAPET, WALL)
            cantilever._wall(builders, inner[::-1], y[::-1], y[::-1] + BRIDGE_PARAPET, WALL)
            _cap(builders, coords, inner, y + BRIDGE_PARAPET, DETAILED)
    tops = [t for t in tops if t is not None]
    return np.concatenate(tops) if tops else None


class Sunken:
    """prepare()'s data, for overpasses.Network: its roads (merged()), their
    heights (fit()) and their cuts (trenches())."""

    def __init__(self, data: dict):
        self.data = data

    def merged(self, data: dict) -> tuple[dict, np.ndarray]:
        return merged(data, self.data)

    def fit(self, network) -> dict:
        return fit(network, self.data["survey"])

    def trenches(self, network, streets: dict) -> "Trenches":
        return Trenches(self.data, network, streets)
