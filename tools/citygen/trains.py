"""The tracks the subway's trains run on over the els (scripts/world/trains.gd),
from els.py's tracks, for the near tiles' trains surface
(common.SURFACE_TRAINS).

Each track's centerline, at the height of its rails (the deck's top), is cut
into pieces where another track joins it (switches and junctions) and at least
every PIECE, and each piece runs the way trains do on it. Trains keep right:
a track with tracks alongside to its left runs along its line, one with
tracks to its right against it, and a middle track (the express track of a
three-track el, run only in the rush hours) gets no trains. Tracks with none
alongside (flyovers, switches, crossovers) take their direction from the
tracks they join. Pieces meet at nodes shared by all tiles, like the driving
lanes', so trains go on from tile to tile; a piece is in the tile holding its
middle, whole.

Along each piece: the speed limit at each point (curves are taken at no more
than CURVE_GRIP sideways), the stops (the middle of each platform beside the
track, els._add_platforms: tracks between platforms or with none, like
express tracks, run through), and the line's service (SERVICES: the route
bullets its trains show). Where no piece goes on, an end is open (into a
tunnel, down to the ground, onto a bridge built elsewhere: trains run off it
out of sight and come out of it) or a dead end (bumper blocks at a
terminal).
"""

import numpy as np
import shapely

PIECE = 250.0         # pieces at most this long (m)
STEP = 10.0           # heights along pieces at least this often, before simplifying (m)
TOLERANCE = 0.03      # points are dropped where the line stays this close without them (m)
CURVE_GRIP = 0.8      # sideways acceleration on curves (m/s^2)
SPEEDS = (4.5, 18.0)  # the slowest a curve asks for, and the fastest trains run (m/s)
CURVE_REACH = 10.0    # curves are measured over this far either way (m)
# Running directions: tracks alongside within NEIGHBOR_REACH (and further
# than NEIGHBOR_MIN), parallel to within PARALLEL (cosine), looked for every
# SAMPLE_STEP along a track. Tracks that join go on from one another at
# least this straight (cosine).
NEIGHBOR_REACH = 20.0
NEIGHBOR_MIN = 2.0
PARALLEL = 0.95
SAMPLE_STEP = 25.0
FOLLOW = 0.7
# A track this close to a platform stops at it, if the platform runs at least
# MIN_STOP beside it; stops on a track at least STOP_GAP apart.
PLATFORM_SIDE = 2.6
MIN_STOP = 40.0
STOP_GAP = 60.0
# Tracks joined up into less than this much (m) carry no trains.
MIN_NETWORK = 400.0

# Piece flags (uv2.y of the trains surface).
OPEN_START = 1  # no piece leads into its start, a track's end going on out of sight: trains may come out of it
OPEN_END = 2    # no piece goes on from its end, going on out of sight: trains run off it
DEAD_END = 4    # no piece goes on from its end (bumper blocks, a track trains don't use): trains stop short
MAIN = 8        # a running track (a long one with tracks alongside): trains may appear on it
# Track ends going on out of sight (els.Tracks.end_kinds): into a tunnel or
# down to the ground, into a yard, onto a bridge built elsewhere.
OPEN_KINDS = ("ground", "yard", "excluded")
# Running tracks are at least this long (switches and crossovers are shorter).
MAIN_LENGTH = 150.0

# The subway's services (scripts/world/trains.gd's SERVICES: route bullets,
# division, cars), by the planimetric lines' names, which start with the
# division and the line's code; "NO NAME" tracks take their neighbors'.
# Railroads and yards have none (0).
SERVICES = {
    "IRT C FLUSHING": 1,                                          # 7
    "IRT J JEROME AVE": 2,                                        # 4
    "IRT W WHITE PLAINS RD": 3, "IRT F WHITE PLAINS RD": 3,       # 2, 5
    "IRT P PELHAM": 4, "IRT PW WESTCHESTER PELHAM": 4,            # 6
    "IRT BB BROADWAY 7TH AVE": 5, "IRT BV BROADWAY 7TH AVE": 5,   # 1
    "IRT BB BROADWAY-7TH AVE": 5, "IRT BB BROADWAY": 5, "BROADWAY": 5,
    "IRT E EASTERN PKY": 6,                                       # 3
    "IRT Y DYRE AVE": 7,                                          # 5
    "BMT J JAMAICA": 8,                                           # J, Z
    "BMT M MYRTLE AVE": 9,                                        # M
    "BMT G ASTORIA": 10, "BMT G BROADWAY": 10,                    # N, W
    "IND B CULVER-6TH AVE": 11, "STILLWELL- CONEY IS.- CUL": 11,  # F, G
    "BMT D WEST END": 12,                                         # D
    "BMT A BRIGHTON": 13,                                         # B, Q
    "BMT E SEA BEACH": 14,                                        # N
    "IND FA ROCKAWAY": 15, "IND F ROCKAWAY": 15, "IND FR ROCKAWAY": 15,  # A, S
    "IND K LIBERTY AVE RR": 16,                                   # A
    "BMT P CANARSIE": 17, "BMT Q CANARSIE": 17,                   # L
    "BMT O FRANKLIN AVE": 18,                                     # S
}
UNNAMED = "NO NAME"


def pieces(tracks, platforms: list, snap: float) -> list[dict]:
    """The pieces trains run on: {"points" (N, 3) east, north, rail height;
    "speeds" (N,) m/s; "stops" (N,) bool; "from", "to" node ids; "service";
    "flags"}. `platforms` are the els' platform outlines, `snap` how far
    apart joined track ends may be (els.SNAP)."""
    chains = tracks.chains
    if len(chains) == 0:
        return []
    service = _services(tracks)
    direction, voted = _directions(tracks, service)
    stops = _stops(tracks, platforms, service, direction)

    # Cuts along every chain: its ends, where other tracks join it, and
    # evenly between, at most PIECE apart.
    lengths = shapely.length(chains)
    joined_at = [[] for _ in chains]
    for c, end, other, at in tracks.joins:
        if snap < at < lengths[other] - snap:
            joined_at[other].append(at)
    cuts = []
    for c, length in enumerate(lengths):
        fixed = np.unique(np.concatenate([[0.0, length], joined_at[c]]))
        even = [np.linspace(a, b, max(1, int(np.ceil((b - a) / PIECE))) + 1)[:-1] for a, b in zip(fixed[:-1], fixed[1:])]
        cuts.append(np.append(np.concatenate(even), length))

    # Nodes: every cut, the cuts where tracks join made one.
    first = np.concatenate([[0], np.cumsum([len(c) for c in cuts])])
    parent = np.arange(first[-1])

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def cut_at(c, at):
        return first[c] + int(np.argmin(np.abs(cuts[c] - at)))
    inner = np.zeros(first[-1], dtype=bool)
    for c, end, other, at in tracks.joins:
        a, b = find(cut_at(c, 0.0 if end == 0 else lengths[c])), find(cut_at(other, at))
        parent[a] = b
        if snap < at < lengths[other] - snap:
            inner[cut_at(other, at)] = True
    root = np.array([find(a) for a in range(first[-1])])
    _, node_id = np.unique(root, return_inverse=True)
    node_id += 1
    # Where each node is: on the track a joining one meets, else between the
    # ends that meet there.
    places = np.vstack([shapely.get_coordinates(shapely.line_interpolate_point(chain, cut))
                        for chain, cut in zip(chains, cuts)])
    sums = np.zeros((node_id.max() + 1, 2))
    np.add.at(sums, node_id, places)
    node_place = sums / np.maximum(np.bincount(node_id), 1)[:, None]
    node_place[node_id[inner]] = places[inner]

    out = []
    for c, chain in enumerate(chains):
        if service[c] <= 0 or direction[c] == 0:
            continue
        coords = np.asarray(chain.coords)[:, :2]
        bends = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(coords, axis=0), axis=1))])
        own_stops = stops.get(c, np.zeros(0))
        for k in range(len(cuts[c]) - 1):
            a, b = cuts[c][k], cuts[c][k + 1]
            if b - a < 0.5:
                continue
            here = own_stops[(own_stops >= a) & (own_stops < b)]
            s = np.unique(np.concatenate([np.linspace(a, b, max(2, int(np.ceil((b - a) / STEP)) + 1)),
                                          bends[(bends > a) & (bends < b)], here]))
            en = shapely.get_coordinates(shapely.line_interpolate_point(chain, s))
            ends = (node_id[first[c] + k], node_id[first[c] + k + 1])
            en[0], en[-1] = node_place[ends[0]], node_place[ends[1]]
            y = tracks.height(en)
            speeds = _speeds(chain, s)
            is_stop = np.isin(s, here)
            keep = _simplify(np.column_stack([en, y]), TOLERANCE, is_stop)
            # A kept point's limit is the lowest of those dropped either side of it.
            low = np.minimum.reduceat(speeds, keep)
            low = np.minimum(low, np.concatenate([low[:1], low[:-1]]))
            piece = {"points": np.column_stack([en, y])[keep], "speeds": low, "stops": is_stop[keep],
                     "from": int(ends[0]), "to": int(ends[1]), "service": int(service[c]),
                     "flags": MAIN if voted[c] and chain.length >= MAIN_LENGTH else 0, "kinds": (_end_kind(tracks, c, k == 0, 0),
                                                                _end_kind(tracks, c, k == len(cuts[c]) - 2, 1))}
            if direction[c] < 0:
                piece = _reversed(piece)
            out.append(piece)

    # Tracks that don't reach far (short bits of el where a line on an
    # embankment crosses a street) carry no trains.
    out = _without_scraps(out)
    # Open and dead ends: nodes no piece leads on from (or into).
    leaving = {p["from"] for p in out}
    arriving = {p["to"] for p in out}
    for p in out:
        if p["to"] not in leaving:
            p["flags"] |= OPEN_END if p["kinds"][1] in OPEN_KINDS else DEAD_END
        if p["from"] not in arriving and p["kinds"][0] in OPEN_KINDS:
            p["flags"] |= OPEN_START
        del p["kinds"]
    return out


def bucket(found: list, size: float) -> dict:
    """Pieces by the near tile holding their middle: {(i, j): [piece]}."""
    out = {}
    for piece in found:
        en = piece["points"][:, :2]
        steps = np.linalg.norm(np.diff(en, axis=0), axis=1)
        along = np.concatenate([[0.0], np.cumsum(steps)])
        middle = np.array([np.interp(along[-1] / 2, along, en[:, 0]), np.interp(along[-1] / 2, along, en[:, 1])])
        key = (int(np.floor(middle[0] / size)), int(np.floor(-middle[1] / size)))
        out.setdefault(key, []).append(piece)
    return out


def surface(found: list, origin) -> tuple:
    """A near tile's trains surface (common.SURFACE_TRAINS) from its pieces,
    tile-local; no indices."""
    points, normals, uv, uv2 = [], [], [], []
    for number, piece in enumerate(found):
        p = piece["points"]
        n = len(p)
        points.append(np.column_stack([p[:, 0], p[:, 2], -p[:, 1]]) - np.asarray(origin))
        normals.append(np.column_stack([np.full(n, piece["from"]), np.full(n, piece["to"]), piece["speeds"]]))
        uv.append(np.column_stack([piece["stops"].astype(np.float64), np.full(n, piece["service"])]))
        uv2.append(np.column_stack([np.full(n, number), np.full(n, piece["flags"])]))
    return (np.round(np.concatenate(points), 2).astype(np.float32), np.round(np.concatenate(normals), 2).astype(np.float32),
            np.concatenate(uv).astype(np.float32), np.concatenate(uv2).astype(np.float32), np.zeros(0, dtype=np.uint32))


def _services(tracks) -> np.ndarray:
    """Each chain's service; unnamed ones take a joined track's."""
    names = [str(n).strip() for n in tracks.names]
    service = np.array([SERVICES.get(n, -1 if n == UNNAMED else 0) for n in names])
    for _ in range(50):
        changed = False
        for c, _end, other, _at in tracks.joins:
            for a, b in ((c, other), (other, c)):
                if service[a] < 0 and service[b] >= 0:
                    service[a] = service[b]
                    changed = True
        if not changed:
            break
    return np.maximum(service, 0)


def _tangents(chain, s: np.ndarray) -> np.ndarray:
    """Unit directions (N, 2) along a chain at distances s."""
    step = min(1.0, chain.length / 4)
    ahead = shapely.get_coordinates(shapely.line_interpolate_point(chain, np.minimum(s + step, chain.length)))
    behind = shapely.get_coordinates(shapely.line_interpolate_point(chain, np.maximum(s - step, 0.0)))
    d = ahead - behind
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)


def _directions(tracks, service: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Which way trains run on each chain: 1 along it, -1 against it, 0 none
    (a middle track, or no service); and whether that came from tracks
    alongside (else from the tracks it joins)."""
    chains = tracks.chains
    running = np.flatnonzero(service > 0)
    tree = shapely.STRtree(chains[running])
    direction = np.zeros(len(chains), dtype=np.int64)
    known = np.zeros(len(chains), dtype=bool)
    for c in running:
        chain = chains[c]
        s = np.arange(SAMPLE_STEP / 2, chain.length, SAMPLE_STEP) if chain.length > SAMPLE_STEP else np.array([chain.length / 2])
        points = shapely.line_interpolate_point(chain, s)
        p = shapely.get_coordinates(points)
        t = _tangents(chain, s)
        votes, middles = 0, 0
        sample, near = tree.query(points, predicate="dwithin", distance=NEIGHBOR_REACH)
        left = np.zeros(len(s), dtype=np.int64)
        right = np.zeros(len(s), dtype=np.int64)
        for k, o in zip(sample, running[near]):
            if o == c:
                continue
            at = chains[o].project(points[k])
            q = shapely.get_coordinates(chains[o].interpolate(at))[0]
            if abs(float(_tangents(chains[o], np.array([at]))[0] @ t[k])) < PARALLEL:
                continue
            offset = t[k, 0] * (q[1] - p[k, 1]) - t[k, 1] * (q[0] - p[k, 0])
            if abs(offset) < NEIGHBOR_MIN:
                continue
            if offset > 0:
                left[k] += 1
            else:
                right[k] += 1
        votes = int(np.sum(left > right) - np.sum(right > left))
        middles = int(np.sum((left == right) & (left > 0)))
        if votes == 0 and middles == 0:
            continue  # nothing alongside: decided below
        known[c] = True
        direction[c] = int(np.sign(votes)) if abs(votes) > middles else 0
    voted = known.copy()
    # Tracks with none alongside: as the tracks they join run.
    lengths = shapely.length(chains)
    for _ in range(50):
        changed = False
        for c, end, other, at in tracks.joins:
            at_c = 0.0 if end == 0 else lengths[c]
            for a, at_a, b, at_b in ((c, at_c, other, at), (other, at, c, at_c)):
                if known[a] or not known[b] or direction[b] == 0 or service[a] <= 0:
                    continue
                along = float(_tangents(chains[b], np.array([at_b]))[0] @ _tangents(chains[a], np.array([at_a]))[0])
                if abs(along) < FOLLOW:
                    continue
                direction[a] = direction[b] * int(np.sign(along))
                known[a] = changed = True
        if not changed:
            break
    # Lone tracks joining nothing that runs: along their line.
    direction[(service > 0) & ~known] = 1
    return direction, voted


def _stops(tracks, platforms: list, service: np.ndarray, direction: np.ndarray) -> dict:
    """Where trains stop on each chain: {chain: distances along it}, the
    middle of each platform beside it."""
    chains = tracks.chains
    tree = shapely.STRtree(chains)
    out = {}
    for platform in platforms:
        boundary = shapely.segmentize(platform.exterior, 2.0)
        coords = shapely.points(np.asarray(boundary.coords)[:, :2])
        for c in tree.query(platform, predicate="dwithin", distance=PLATFORM_SIDE):
            if service[c] <= 0 or direction[c] == 0:
                continue
            beside = coords[shapely.dwithin(chains[c], coords, PLATFORM_SIDE)]
            if len(beside) < 2:
                continue
            along = shapely.line_locate_point(chains[c], beside)
            if along.max() - along.min() < MIN_STOP:
                continue
            middle = (along.max() + along.min()) / 2
            found = out.setdefault(int(c), [])
            if all(abs(middle - other) >= STOP_GAP for other in found):
                found.append(middle)
    return {c: np.array(sorted(v)) for c, v in out.items()}


def _speeds(chain, s: np.ndarray) -> np.ndarray:
    """Speed limits (m/s) at distances s along a chain, from how sharply it
    curves there (over CURVE_REACH either way)."""
    a = shapely.get_coordinates(shapely.line_interpolate_point(chain, np.maximum(s - CURVE_REACH, 0.0)))
    b = shapely.get_coordinates(shapely.line_interpolate_point(chain, s))
    c = shapely.get_coordinates(shapely.line_interpolate_point(chain, np.minimum(s + CURVE_REACH, chain.length)))
    # The circle through the three points: R = |ab| |bc| |ca| / (4 area).
    ab, bc, ca = (np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1))
    area = 0.5 * np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0]))
    radius = np.where(area > 1e-6, ab * bc * ca / np.maximum(4.0 * area, 1e-9), 1e9)
    return np.clip(np.sqrt(CURVE_GRIP * radius), *SPEEDS)


def _simplify(points: np.ndarray, tolerance: float, keep: np.ndarray) -> np.ndarray:
    """Indices of the points (N, 3) a polyline needs to stay within
    `tolerance` of them (Douglas-Peucker in 3-D), with its ends and the
    points marked `keep`."""
    marked = keep.copy()
    marked[0] = marked[-1] = True
    fixed = np.flatnonzero(marked)
    stack = list(zip(fixed[:-1], fixed[1:]))
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        d = points[b] - points[a]
        span = points[a + 1:b] - points[a]
        t = np.clip((span @ d) / max(float(d @ d), 1e-12), 0.0, 1.0)
        gap = np.linalg.norm(span - t[:, None] * d, axis=1)
        k = int(np.argmax(gap))
        if gap[k] > tolerance:
            marked[a + 1 + k] = True
            stack += [(a, a + 1 + k), (a + 1 + k, b)]
    return np.flatnonzero(marked)


def _without_scraps(found: list) -> list:
    """The pieces in networks (pieces joined at their nodes, either way)
    with at least MIN_NETWORK of track."""
    parent = {}

    def find(a):
        parent.setdefault(a, a)
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for p in found:
        parent[find(p["from"])] = find(p["to"])
    total = {}
    lengths = [float(np.linalg.norm(np.diff(p["points"][:, :2], axis=0), axis=1).sum()) for p in found]
    for p, length in zip(found, lengths):
        root = find(p["from"])
        total[root] = total.get(root, 0.0) + length
    return [p for p in found if total[find(p["from"])] >= MIN_NETWORK]


def _end_kind(tracks, c: int, at_end: bool, end: int):
    """What became of chain c's end (0 start, 1 end) if a piece ends there
    (Tracks.end_kinds), else None."""
    return tracks.end_kinds.get((c, end)) if at_end else None


def _reversed(piece: dict) -> dict:
    return {"points": piece["points"][::-1], "speeds": piece["speeds"][::-1], "stops": piece["stops"][::-1],
            "from": piece["to"], "to": piece["from"], "service": piece["service"], "flags": piece["flags"],
            "kinds": piece["kinds"][::-1]}
