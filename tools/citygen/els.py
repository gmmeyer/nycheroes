"""Elevated railways, the "els": the subway's elevated lines (the 7 over
Queens Boulevard and Roosevelt Avenue, the J/M/Z over Broadway in Brooklyn,
the 2/5 and the 4 in the Bronx, the N/W in Astoria, the F/G's Culver Viaduct,
the 1 over 125th Street, the B/D/F/N/Q in south Brooklyn, the A in the
Rockaways...) and the railroads' viaducts (Metro-North's Park Avenue Viaduct,
the LIRR through Jamaica), as viaducts over the streets: open steel for the
subway (a deck with ties and rails, side girders, bents of columns and cap
girders standing in the street), concrete for the railroads; and elevated
stations' platforms under canopies.

Sources (none has heights):
- The planimetric railroad lines (Railroad Line): every track's centerline,
  feature code 2410 elevated and 2430 viaduct, named by line ("IRT C
  FLUSHING"); 2400 at grade, 2420 on an embankment and 2440 in an open cut
  say where an el comes down to the ground.
- The planimetric transportation structures' rail bridges (2320) and railroad
  viaducts (2340): the viaducts' true edges (405 of the 406 km of elevated
  track lie inside them). Rail bridges no el track runs through (railroads on
  embankments crossing a street) are built like overpasses.py's outlines
  without a road.
- The planimetric railroad structures' elevated stations (2140): their roofs'
  outlines, which take in the platforms beside or between the tracks.

Heights: an el's deck sits EL_RISE above the street (5.3 m clear under its
2.2 m girders, as the old els' 14 to 18 feet), and over dips, valleys and the
roads it crosses it holds its height and climbs at most GRADE: the lowest
profile that keeps the clearance everywhere, worked out over the whole track
network at once (so the 1 crosses the 125th Street valley high, as on the
Manhattan Valley Viaduct). Where a track goes on into an embankment, a cut or
a tunnel, the el comes down to the ground at END_GRADE. Tracks within SHARE
share one level. Where navigation needs more (the Culver Viaduct over the
Gowanus Canal), MIN_TOPS says so.

Outlines that are part of a bridge bridges.py builds (the Manhattan and
Williamsburg Bridges' tracks, the Hell Gate Bridge and its approaches) are
left to it; creeks and canals the els cross are crossed.

They're painted with the landmark bridges' structure kinds (STEEL, TRACK,
CONCRETE below): no shader code of their own.

build() adds the els to the bridge buckets (bridges.build's format, with
collision up close) and the columns' spots per near tile ("el_columns", for
keeping parked cars and other props out of them).
"""

import heapq

import numpy as np
import shapely
from shapely.geometry import shape

import bridge_landmarks
import bridges
import markings
import overpasses
from common import (STRUCTURE_CONCRETE, STRUCTURE_RAIL, STRUCTURE_STEEL, MeshBuilder, lines_of, load_features,
                    polygons_of, project)

EL_CODES = ("2410", "2430")              # railroad lines: elevated, viaduct centerline
GROUND_CODES = ("2400", "2420", "2440")  # at grade, on an embankment, in an open cut
OUTLINE_CODES = ("2320", "2340")         # transportation structures: rail bridge, railroad viaduct
STATION_CODE = "2140"                    # railroad structures: elevated station
# Outlines bridges.py builds by hand, approaches and all (the Hell Gate); and
# rail outlines this much on a bridge it builds (the Manhattan and
# Williamsburg Bridges' tracks).
ELSEWHERE = set(bridge_landmarks.OUTLINES)
ELSEWHERE_MARGIN = 30.0
ON_BRIDGE = 0.25
# Lines in steel: the subway's (its divisions name them); the railroads' are concrete.
STEEL_LINES = ("IRT", "BMT", "IND", "STILLWELL")
# Where an el must be higher than its clearance gives (navigation): name ->
# (latitude, longitude, reach m, deck top m above sea level). The Culver
# Viaduct crosses the Gowanus Canal 88 feet up (Smith-9th Streets, the
# highest station in the subway, is 87.5 feet over the street).
MIN_TOPS = {
    "Culver Viaduct over the Gowanus Canal": (40.6740, -73.9965, 150.0, 30.0),
    # The 1's Manhattan Valley Viaduct: 125th Street station is 54 feet up.
    "Manhattan Valley Viaduct": (40.8155, -73.9585, 120.0, 24.0),
}
# Track ends going on into a yard (by the lines' names) come down on their own
# track, without pulling down the line they branch off.
YARD = "YARD"
# Short at-grade track pieces joining elevated ones at both ends are elevated
# too (the data has them where station roofs hide the tracks).
MAX_HIDDEN = 400.0
# Outlines count as an el's deck this close to its tracks (some outlines run
# on past them, over a demolished line).
OUTLINE_REACH = 25.0
MAX_OUTLINE_PER_TRACK = 30.0  # m^2 of outline per meter of track in it

EL_RISE = 7.5        # deck top above the street (m)
GIRDER_DEPTH = 2.2   # side girders reach this far below the deck's top
GIRDER_TOP = 0.5     # and this far above it
FLOOR_DEPTH = 0.8    # the floor's underside, between the girders
STRINGER_DEPTH = 1.6  # girders under each track
STRINGER_OFFSET = 0.8
GRADE = 0.03         # els climb over dips and obstacles at most this steeply
END_GRADE = 0.035    # and come down to the ground at most this steeply
SHARE = 7.0          # tracks this close share one level (the highest)
STATION_STEP = 10.0  # heights along tracks at least this often (m)
SNAP = 1.5           # track ends this close to another track join it
PIN_REACH = 3.0      # a track end this close to a track on the ground comes down to it
MIN_TRACK = 5.0
# Roads (decks) under an el that it climbs over: up to this far above where
# its deck would be anyway (higher ones pass over it).
OVER_REACH = 4.0
TRACK_HALF = 1.3     # ties' half length: a track's strip on the deck
TRACK_CLEAR = 1.6    # platform edges from a track's middle
DECK_MARGIN = 0.4    # decks reach this far past their outer tracks where outlines are missing
AT_GRADE_GAP = overpasses.AT_GRADE_GAP
SOLID_BELOW = overpasses.SOLID_BELOW
DECK_SPACING = overpasses.DECK_SPACING
FAR_MIN_AREA = overpasses.FAR_MIN_AREA
DETAILED = ("lod0", "lod1")
CHUNK = 200.0  # big polygons are cut into squares this big for gridding (a multiple of DECK_SPACING)
WATER_FOOTING_Y = overpasses.WATER_FOOTING_Y

# Bents: every BENT_SPACING along the el (about 50 feet, as on the old els),
# a cap girder across the deck on columns at its edges, and more columns
# under wide decks (at most MAX_BENT_SPAN apart). Columns stay out of the
# roadway of streets crossing under the el (the bent moves along it, or the
# span grows) and out of the travel lanes of the street it runs over (they
# move out toward the curb).
BENT_SPACING = 15.0
BENT_GAP = 10.5       # bents at least this far apart (where tracks branch)
BENT_SHIFTS = (4.0, -4.0, 8.0, -8.0)
MAX_BENT_SPAN = 11.0
COLUMN_INSET = 0.6
COLUMN_SIZE = {"steel": (0.35, 0.45), "concrete": (0.55, 0.7)}  # half sizes along and across the track
CAP_BELOW = 0.2       # the cap's bottom below the girders'
BRACE = 1.5           # knee braces reach this far down the column and along the cap
COLUMN_CLEARANCE = 2.0
TRAVEL_GAP = 0.6      # columns moved out of travel lanes stand this far past them
COLUMN_REACH = 5.0    # ... at most this far past the deck's edge
CROSSING_COSINE = 0.7  # streets at least this far off the el's direction cross under it
# Props keep this far from columns (m): parked cars, everything else.
CAR_CLEAR, PROP_CLEAR = 3.2, 1.0

# Elevated stations: platforms PLATFORM_HEIGHT above the deck within
# PLATFORM_REACH of the tracks (the station outlines also take in stairs and
# station houses), windscreens along their outer edges, canopies
# CANOPY_HEIGHT over them on posts every POST_SPACING; lit at night.
PLATFORM_HEIGHT = 1.0
PLATFORM_REACH = 12.0
MIN_PLATFORM_WIDTH = 1.5
WINDSCREEN = 1.2
CANOPY_HEIGHT = 3.4
CANOPY_THICKNESS = 0.35
CANOPY_INSET = 0.2
POST_SPACING = 9.0

# How the els are painted (the structures' kinds and their uv2.y: palette + 8
# * flags, see bridge_landmarks): steel in palette 0, the els' green; tracks
# as track beds (uv: meters along the track, across from its middle); the
# railroads' viaducts in concrete; platforms and canopies' undersides lit
# (floodlit) at night.
STEEL = (STRUCTURE_STEEL, 0.0)
TRACK = (STRUCTURE_RAIL, 0.0)
CONCRETE = (STRUCTURE_CONCRETE, 0.0)
LIT = 8.0 * bridge_landmarks.FLOODLIT
PLATFORM = (STRUCTURE_CONCRETE, LIT)
LIT_STEEL = (STRUCTURE_STEEL, LIT)


def prepare() -> dict:
    """The elevated tracks (and their lines' names), the tracks on the ground,
    the rail bridge and viaduct outlines, and the elevated stations."""
    tracks, names, others, other_rows = [], [], [], []
    for feat in load_features("railroad_lines"):
        p = feat["properties"]
        code = str(p.get("feat_code"))
        if code not in EL_CODES + GROUND_CODES:
            continue
        parts = [part for part in shapely.get_parts(shapely.line_merge(shape(feat["geometry"])))
                 if part.geom_type == "LineString"]
        if code in EL_CODES:
            tracks += parts
            names += [str(p.get("name") or "NO NAME")] * len(parts)
        else:
            others += parts
            other_rows += [(code, str(p.get("name") or "NO NAME"))] * len(parts)
    tracks = project(np.array(tracks, dtype=object))
    keep = shapely.length(tracks) > 1.0
    others = project(np.array(others, dtype=object))
    long_enough = shapely.length(others) > 1.0
    outlines = [f for f in load_features("transport_structures") if str(f["properties"].get("feat_code")) in OUTLINE_CODES]
    stations = [f for f in load_features("railroad_structures") if str(f["properties"].get("feat_code")) == STATION_CODE]
    return {
        "tracks": tracks[keep],
        "track_names": np.array(names, dtype=object)[keep],
        "others": others[long_enough],
        "other_codes": np.array([r[0] for r in other_rows], dtype=object)[long_enough],
        "other_names": np.array([r[1] for r in other_rows], dtype=object)[long_enough],
        "outlines": shapely.make_valid(project(np.array([shape(f["geometry"]) for f in outlines], dtype=object))),
        "outline_names": [str(f["properties"].get("name") or "NO NAME") for f in outlines],
        "stations": shapely.make_valid(project(np.array([shape(f["geometry"]) for f in stations], dtype=object))),
    }


class Tracks:
    """The els' tracks as chains (track lines joined end to end), with their
    deck heights along them (see the module's notes)."""

    def __init__(self, lines: list, names: list, others, other_names, network, terrain, buckets: dict, size: float,
                 excluded):
        merged = shapely.line_merge(shapely.MultiLineString(lines)) if lines else shapely.MultiLineString()
        self.chains = np.array([c for c in lines_of(merged) if c.length >= MIN_TRACK], dtype=object)
        self.tree = shapely.STRtree(self.chains)
        # Each chain's line name: the input line nearest its middle.
        source = shapely.STRtree(np.array(lines, dtype=object))
        middles = shapely.line_interpolate_point(self.chains, 0.5, normalized=True)
        nearest = source.query_nearest(middles, return_distance=False, all_matches=False)
        self.names = np.empty(len(self.chains), dtype=object)
        self.names[nearest[0]] = np.asarray(names, dtype=object)[nearest[1]]
        self.steel = np.array([str(n).startswith(STEEL_LINES) for n in self.names])
        self.named = np.array([str(n) != "NO NAME" for n in self.names])

        # Stations along every chain: the nodes of the track graph.
        self.s, starts = [], [0]
        for chain in self.chains:
            self.s.append(np.linspace(0.0, chain.length, max(2, int(np.ceil(chain.length / STATION_STEP)) + 1)))
            starts.append(starts[-1] + len(self.s[-1]))
        self.starts = np.array(starts)
        en = np.vstack([shapely.get_coordinates(shapely.line_interpolate_point(c, s))
                        for c, s in zip(self.chains, self.s)]) if len(self.chains) else np.zeros((0, 2))
        count = len(en)
        adjacent = [[] for _ in range(count)]

        def link(a, b, weight):
            adjacent[a].append((b, weight))
            adjacent[b].append((a, weight))
        for c, s in enumerate(self.s):
            o = self.starts[c]
            for k, step in enumerate(np.diff(s)):
                link(o + k, o + k + 1, float(step))

        # Track ends: joined to tracks they meet; else brought down to the
        # ground where a track on the ground goes on from them.
        others_tree = shapely.STRtree(others)
        pinned, local = {}, {}
        self.free_ends = 0
        for c in range(len(self.chains)):
            for node in (self.starts[c], self.starts[c + 1] - 1):
                p = en[node]
                point = shapely.Point(p)
                joined = False
                for other in self.tree.query(point, predicate="dwithin", distance=SNAP):
                    if other == c:
                        continue
                    at = self.chains[other].project(point)
                    k = self.starts[other] + int(np.argmin(np.abs(self.s[other] - at)))
                    link(node, k, max(float(np.linalg.norm(en[k] - p)), 0.1))
                    joined = True
                if joined or shapely.dwithin(excluded, point, 3 * PIN_REACH):
                    continue
                ground = others_tree.query(point, predicate="dwithin", distance=PIN_REACH)
                if not len(ground):
                    self.free_ends += 1
                elif any(YARD in str(n) for n in [self.names[c]] + list(other_names[ground])):
                    # A yard lead comes down on its own, not the line it leaves.
                    local[node] = (c, float(terrain.height(p[None])[0]))
                else:
                    pinned[node] = float(terrain.height(p[None])[0])
        self.pinned = len(pinned) + len(local)

        # What the clearance is measured from: the street, roads and bridges
        # passing under, navigation.
        street = network.street(en)
        base = np.maximum(street, _decks_under(en, street, buckets, size))
        for lat, lon, reach, top in MIN_TOPS.values():
            center = shapely.get_coordinates(project(shapely.Point(lon, lat)))[0]
            near = np.linalg.norm(en - center, axis=1) < reach
            base[near] = np.maximum(base[near], top - EL_RISE)

        inf = np.full(count, np.inf)
        ends = inf.copy()
        if pinned:
            ends[list(pinned)] = 0.0
        to_end = _spread(adjacent, ends, 1.0)
        # The clearance fades out toward the ends that come down.
        rise = EL_RISE * np.clip(to_end / (EL_RISE / END_GRADE), 0.0, 1.0)
        floor = inf.copy()
        if pinned:
            floor[list(pinned)] = list(pinned.values())
        ceiling = _spread(adjacent, floor, END_GRADE)
        for node, (c, ground) in local.items():
            nodes = slice(self.starts[c], self.starts[c + 1])
            along = np.abs(self.s[c] - self.s[c][node - self.starts[c]])
            rise[nodes] = np.minimum(rise[nodes], EL_RISE * np.clip(along / (EL_RISE / END_GRADE), 0.0, 1.0))
            ceiling[nodes] = np.minimum(ceiling[nodes], ground + END_GRADE * along)
        envelope = -_spread(adjacent, -(base + rise), GRADE)
        h = np.maximum(np.minimum(envelope, ceiling), street)
        for node, value in list(pinned.items()) + [(n, g) for n, (_, g) in local.items()]:
            h[node] = value
        self.h = [h[self.starts[c]:self.starts[c + 1]] for c in range(len(self.chains))]
        self.en = en
        self.street = street

        # The pieces between stations, for looking heights and places along
        # tracks up quickly (each is straight to within centimeters).
        first = np.concatenate([np.arange(self.starts[c], self.starts[c + 1] - 1) for c in range(len(self.chains))]) \
            if len(self.chains) else np.zeros(0, dtype=np.int64)
        self.seg_a, self.seg_b = en[first], en[first + 1]
        self.seg_h = np.column_stack([h[first], h[first + 1]])
        self.seg_chain = np.searchsorted(self.starts, first, side="right") - 1
        s_all = np.concatenate(self.s) if self.s else np.zeros(0)
        self.seg_s = np.column_stack([s_all[first], s_all[first + 1]])
        self.seg_tree = shapely.STRtree(shapely.linestrings(np.stack([self.seg_a, self.seg_b], axis=1))) \
            if len(first) else None

    def _project(self, en: np.ndarray, segs: np.ndarray):
        """Where points (N, 2) fall on pieces segs (N,): (fraction along the
        piece, distance to the left of it)."""
        a, b = self.seg_a[segs], self.seg_b[segs]
        d = b - a
        length2 = np.maximum((d * d).sum(axis=1), 1e-12)
        t = np.clip(((en - a) * d).sum(axis=1) / length2, 0.0, 1.0)
        left = (d[:, 0] * (en[:, 1] - a[:, 1]) - d[:, 1] * (en[:, 0] - a[:, 0])) / np.sqrt(length2)
        return t, left

    def height(self, en: np.ndarray) -> np.ndarray:
        """Deck heights at (N, 2) points: the highest track within SHARE, or
        the nearest track's."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.full(len(en), -np.inf)
        if len(en) == 0 or self.seg_tree is None:
            return out
        points = shapely.points(en)
        point, seg = self.seg_tree.query(points, predicate="dwithin", distance=SHARE)
        if len(point):
            t, _ = self._project(en[point], seg)
            np.maximum.at(out, point, self.seg_h[seg, 0] + t * (self.seg_h[seg, 1] - self.seg_h[seg, 0]))
        missing = np.flatnonzero(out == -np.inf)
        if len(missing):
            point, seg = self.seg_tree.query_nearest(points[missing], return_distance=False, all_matches=False)
            t, _ = self._project(en[missing[point]], seg)
            out[missing[point]] = self.seg_h[seg, 0] + t * (self.seg_h[seg, 1] - self.seg_h[seg, 0])
        return out

    def place(self, c: int, en: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Where (N, 2) points are along chain c: (meters along it, meters to
        its left)."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        segs = np.arange(self.starts[c] - c, self.starts[c + 1] - c - 1)
        along, left = np.zeros(len(en)), np.zeros(len(en))
        for start in range(0, len(en), 2048):
            chunk = en[start:start + 2048]
            a, b = self.seg_a[segs], self.seg_b[segs]
            d = b - a
            length2 = np.maximum((d * d).sum(axis=1), 1e-12)
            rel = chunk[:, None, :] - a[None]
            t = np.clip((rel * d[None]).sum(axis=2) / length2[None], 0.0, 1.0)
            gap = np.linalg.norm(rel - t[..., None] * d[None], axis=2)
            best = np.argmin(gap, axis=1)
            seg = segs[best]
            tt, ll = self._project(chunk, seg)
            along[start:start + 2048] = self.seg_s[seg, 0] + tt * (self.seg_s[seg, 1] - self.seg_s[seg, 0])
            left[start:start + 2048] = ll
        return along, left


def _spread(adjacent: list, start: np.ndarray, slope: float) -> np.ndarray:
    """The smallest of start[u] + slope * (distance from u along the graph)
    over all nodes u, at every node (Dijkstra from many sources)."""
    out = np.array(start, np.float64, copy=True)
    heap = [(float(v), int(n)) for n, v in enumerate(out) if np.isfinite(v)]
    heapq.heapify(heap)
    while heap:
        value, node = heapq.heappop(heap)
        if value > out[node]:
            continue
        for other, weight in adjacent[node]:
            candidate = value + slope * weight
            if candidate < out[other]:
                out[other] = candidate
                heapq.heappush(heap, (candidate, other))
    return out


def _decks_under(en: np.ndarray, street: np.ndarray, buckets: dict, size: float) -> np.ndarray:
    """Tops of road decks (bridges.py's and overpasses.py's) under points
    along the els that the els climb over, else -inf."""
    out = np.full(len(en), -np.inf)
    ii = np.floor(en[:, 0] / size).astype(np.int64)
    jj = np.floor(-en[:, 1] / size).astype(np.int64)
    found_in = buckets.get("lod0", {})
    for key in set(zip(ii.tolist(), jj.tolist())):
        if not any((key[0] + di, key[1] + dj) in found_in for di in (-1, 0, 1) for dj in (-1, 0, 1)):
            continue
        mask = np.flatnonzero((ii == key[0]) & (jj == key[1]))
        surface = overpasses.DeckSurface(found_in, key[0], key[1])
        y, found = surface.height(en[mask], street[mask] + EL_RISE)
        under = found & (y > street[mask] + 0.5) & (y < street[mask] + EL_RISE + OVER_REACH)
        out[mask[under]] = y[under]
    return out


def _el_lines(data: dict, excluded) -> tuple[list, list, np.ndarray, np.ndarray]:
    """The elevated tracks outside `excluded` (with the at-grade pieces
    between them, see MAX_HIDDEN) and their names; the other tracks on the
    ground and theirs."""
    lines, names = [], []
    for line, name in zip(data["tracks"], data["track_names"]):
        pieces = lines_of(shapely.difference(line, excluded)) if shapely.intersects(excluded, line) else [line]
        for piece in pieces:
            if piece.length >= MIN_TRACK:
                lines.append(piece)
                names.append(name)
    # At-grade pieces between elevated ones (hidden under station roofs).
    el_tree = shapely.STRtree(np.array(lines, dtype=object))
    others, other_names = data["others"], data["other_names"]
    level = np.flatnonzero((data["other_codes"] == "2400") & (shapely.length(others) <= MAX_HIDDEN))
    ends = shapely.points(np.vstack([shapely.get_coordinates(shapely.get_point(others[level], 0)),
                                     shapely.get_coordinates(shapely.get_point(others[level], -1))]))
    touching = np.zeros(len(ends), dtype=bool)
    touching[el_tree.query(ends, predicate="dwithin", distance=SNAP)[0]] = True
    hidden = level[touching[:len(level)] & touching[len(level):]]
    for k in hidden:
        if not shapely.intersects(excluded, others[k]):
            lines.append(others[k])
            names.append(other_names[k])
    rest = np.setdiff1d(np.arange(len(others)), hidden)
    return lines, names, others[rest], other_names[rest]


def build(data: dict, network, land, buckets: dict, level_sizes: dict) -> None:
    """Adds the els to bridges.build's buckets: triangles per level and tile,
    and the columns' spots per near tile in buckets["el_columns"]."""
    shapely.prepare(land)
    keep_out = getattr(network, "keep_out", shapely.Polygon())
    near_bridges = shapely.buffer(keep_out, 5.0)
    elsewhere = [shapely.buffer(o, ELSEWHERE_MARGIN) for o, name in zip(data["outlines"], data["outline_names"])
                 if name in ELSEWHERE or shapely.area(shapely.intersection(o, near_bridges)) >= ON_BRIDGE * o.area]
    excluded = shapely.union_all([keep_out] + elsewhere)
    shapely.prepare(excluded)

    lines, names, others, other_names = _el_lines(data, excluded)
    tracks = Tracks(lines, names, others, other_names, network, network.terrain, buckets, level_sizes["lod0"], excluded)

    # The decks: the outlines tracks run through, and the tracks' own strips
    # where the outlines miss them; over water only crossing creeks and canals.
    line_tree = shapely.STRtree(np.array(lines, dtype=object))
    outlines = [o for o, name in zip(data["outlines"], data["outline_names"]) if name not in ELSEWHERE]
    touched = [o for o in outlines if len(line_tree.query(o, predicate="intersects"))]
    # Outlines far bigger than the tracks in them take in more than the
    # structure (the Bronx Zoo's old monorail loop): the tracks' strips do.
    inside = [shapely.length(shapely.intersection(shapely.MultiLineString(lines), o)) for o in touched]
    touched = [o for o, length in zip(touched, inside) if o.area <= MAX_OUTLINE_PER_TRACK * max(length, 1.0)]
    ground_tree = shapely.STRtree(others)
    untouched = [o for o in outlines if not len(line_tree.query(o, predicate="intersects"))
                 and len(ground_tree.query(o, predicate="intersects"))]
    strips = shapely.buffer(tracks.chains, TRACK_HALF + DECK_MARGIN, cap_style="flat", quad_segs=2)
    near_tracks = shapely.union_all(shapely.buffer(tracks.chains, OUTLINE_REACH, quad_segs=2))
    area = shapely.difference(shapely.union_all([shapely.intersection(o, near_tracks) for o in touched] + list(strips)),
                              excluded)
    wet_outlines = shapely.union_all(touched) if touched else shapely.Polygon()
    pieces = overpasses._over_land(polygons_of(area, 20.0), land, wet_outlines)

    builders = {level: MeshBuilder() for level in level_sizes}
    builders["parts"] = _Parts()
    columns = []
    built = platforms = bents = 0
    for poly in pieces:
        poly = shapely.orient_polygons(shapely.simplify(poly, 0.2))
        chains = tracks.tree.query(poly, predicate="intersects")
        if len(chains) == 0:
            continue
        lengths = shapely.length(shapely.intersection(tracks.chains[chains], poly))
        named = tracks.named[chains]
        steel_share = (lengths * tracks.steel[chains]).sum() / max((lengths * named).sum(), 1e-6)
        style = "steel" if steel_share >= 0.5 or not named.any() else "concrete"
        if not _add_deck(poly, chains, tracks, network, builders, style):
            continue
        built += 1
        bents += _add_bents(poly, chains, tracks, network, builders, style, columns)
    for station in data["stations"]:
        near = tracks.tree.query(station, predicate="dwithin", distance=PLATFORM_REACH)
        if len(near):
            platforms += _add_platforms(station, near, tracks, network, builders)

    # Rail bridges over streets that no el runs through: railroads on
    # embankments; spanned like overpasses.py's outlines without a road.
    plain = 0
    for outline in untouched:
        for part in polygons_of(outline, 50.0):
            local = bridges.local_land(land, part)
            if shapely.area(shapely.difference(part, local)) >= overpasses.MAX_WATER or shapely.intersects(excluded, part):
                continue
            for poly in polygons_of(shapely.intersection(part, local), 20.0):
                poly = shapely.orient_polygons(poly)
                deck_y, _ = overpasses._plain_profile(poly, network)
                if deck_y is None:
                    continue
                if overpasses._add_deck(poly, deck_y, network, builders, top_kind=STRUCTURE_CONCRETE) is not None:
                    plain += 1
                    overpasses._add_axis_columns(poly, deck_y, network, builders)
    total = sum(c.length for c in tracks.chains) / 1000.0
    print(f"  els: {total:.0f} km of track in {len(tracks.chains)} chains ({tracks.pinned} ends come down, "
          f"{tracks.free_ends} end in the air), {built} decks, {bents} bents, {platforms} station platforms, "
          f"{plain} rail bridges over streets", flush=True)

    builders["parts"].build(builders)
    for level, size in level_sizes.items():
        overpasses._merge(buckets.setdefault(level, {}), overpasses._bucket(builders[level], size))
    _bucket_columns(buckets.setdefault("el_columns", {}), columns, level_sizes["lod0"])


# The deck.

def _add_deck(poly, chains: np.ndarray, tracks: Tracks, network, builders: dict, style: str) -> bool:
    """A deck over `poly` at the tracks' height: up close its top in track
    strips (ties and rails) and the deck between them, the floor's underside,
    girders under each track, and side girders along its edges that go down
    to the ground where it's low. Returns whether any of it was built."""
    side_kind = STEEL if style == "steel" else CONCRETE
    zones = _track_zones(poly, chains, tracks)
    built = False
    for level, spacing in DECK_SPACING.items():
        if level not in builders or (level == "lod2" and poly.area < FAR_MIN_AREA):
            continue
        builder = builders[level]
        dense = shapely.segmentize(poly, spacing)
        if level == "lod0":
            parts = [(z, c) for z, c in zones] + [(shapely.difference(dense, shapely.union_all([z for z, _ in zones]))
                                                   if zones else dense, None)]
        else:
            parts = [(dense, None)]
        detailed = level in DETAILED
        for part, chain in parts:
            for piece in polygons_of(part, 0.05):
                tris = _triangles(piece, spacing)
                if tris is None:
                    continue
                en = tris.reshape(-1, 2)
                y = tracks.height(en)
                street = network.street(en)
                keep = ((y - street).reshape(-1, 3) >= AT_GRADE_GAP).any(axis=1)
                if not keep.any():
                    continue
                y = np.maximum(y, street - 0.05).reshape(-1, 3)[keep]
                tris = tris[keep]
                top = np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1)
                if chain is None:
                    uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
                    builder.add(top, uv, side_kind, (0.0, 1.0, 0.0))
                else:
                    builder.add(top, _track_uv(tracks, chain, tris), TRACK, (0.0, 1.0, 0.0))
                built = True
                if detailed:
                    uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
                    builder.add(top - np.array([0.0, FLOOR_DEPTH, 0.0]), uv, side_kind,
                                (0.0, -1.0, 0.0))
        for ring in (dense.exterior, *dense.interiors):
            coords = np.asarray(ring.coords)[:, :2]
            ring_y = tracks.height(coords)
            ground = network.street(coords)
            gap = ring_y - GIRDER_DEPTH - ground
            bottom = np.where(gap < SOLID_BELOW, np.minimum(ground - 0.5, ring_y - GIRDER_DEPTH), ring_y - GIRDER_DEPTH)
            top_y = ring_y + GIRDER_TOP if detailed else ring_y
            high = ring_y - ground >= AT_GRADE_GAP
            for start, stop in overpasses._runs(high[:-1] | high[1:]):
                _add_walls(builder, coords[start:stop + 1], bottom[start:stop + 1], top_y[start:stop + 1],
                           ring_y[start:stop + 1] - GIRDER_DEPTH, side_kind)
    if built and "lod0" in builders:
        _add_stringers(poly, chains, tracks, network, builders["lod0"], side_kind)
    return built


def _track_zones(poly, chains: np.ndarray, tracks: Tracks) -> list:
    """Each track's strip on the deck (ties' length wide), longest track
    first, none overlapping the ones before: [(polygon, chain)]."""
    out = []
    claimed = shapely.Polygon()
    for c in sorted(chains.tolist(), key=lambda c: -tracks.chains[c].length):
        strip = shapely.buffer(tracks.chains[c], TRACK_HALF, cap_style="flat", quad_segs=2)
        zone = shapely.difference(shapely.intersection(strip, poly), claimed)
        zone = shapely.MultiPolygon(polygons_of(zone, 0.5)) if not zone.is_empty else zone
        if zone.is_empty:
            continue
        out.append((shapely.segmentize(zone, DECK_SPACING["lod0"]), c))
        claimed = shapely.union(claimed, zone)
    return out


def _track_uv(tracks: Tracks, c: int, tris: np.ndarray) -> np.ndarray:
    """uv for (T, 3, 2) triangles on chain c's strip: meters along the
    track, meters across from its middle (left positive)."""
    along, left = tracks.place(c, tris.reshape(-1, 2))
    return np.column_stack([along, left]).reshape(-1, 3, 2)


def _triangles(poly, cell: float):
    """overpasses._grid_triangles, CHUNK meters square at a time (long
    diagonal els have huge bounds), or None."""
    min_e, min_n, max_e, max_n = poly.bounds
    if max(max_e - min_e, max_n - min_n) <= CHUNK:
        return overpasses._grid_triangles(poly, cell)
    out = []
    shapely.prepare(poly)
    for x in np.arange(np.floor(min_e / CHUNK) * CHUNK, max_e, CHUNK):
        for y in np.arange(np.floor(min_n / CHUNK) * CHUNK, max_n, CHUNK):
            if not shapely.intersects(poly, shapely.box(x, y, x + CHUNK, y + CHUNK)):
                continue
            for piece in polygons_of(shapely.clip_by_rect(poly, x, y, x + CHUNK, y + CHUNK), 1e-4):
                tris = overpasses._grid_triangles(piece, cell)
                if tris is not None:
                    out.append(tris)
    return np.concatenate(out) if out else None


def _add_stringers(poly, chains: np.ndarray, tracks: Tracks, network, builder: MeshBuilder, kind: tuple) -> None:
    """Girders under each track, either side of its middle, under the floor."""
    for c in chains:
        for line in lines_of(shapely.intersection(tracks.chains[c], poly)):
            if line.length < 2.0:
                continue
            s = np.linspace(0.0, line.length, max(2, int(np.ceil(line.length / DECK_SPACING["lod0"])) + 1))
            points, normal = markings._frame(line, s)
            y = tracks.height(points)
            high = y - network.street(points) - STRINGER_DEPTH >= COLUMN_CLEARANCE
            for start, stop in overpasses._runs(high[:-1] & high[1:]):
                for side in (-1.0, 1.0):
                    coords = points[start:stop + 1] + normal[start:stop + 1] * side * STRINGER_OFFSET
                    ys = y[start:stop + 1]
                    _add_walls(builder, coords, ys - STRINGER_DEPTH, ys - FLOOR_DEPTH, ys - STRINGER_DEPTH, kind)


def _add_walls(builder: MeshBuilder, coords: np.ndarray, bottom, top, base, uv2) -> None:
    """Vertical walls along a line (outward to the right of travel, as
    MeshBuilder.add_walls), uv = (meters along, meters above `base`, per
    point)."""
    pts = np.asarray(coords, np.float64)[:, :2]
    n = len(pts)
    bottom, top, base = (np.broadcast_to(np.asarray(v, np.float64), n) for v in (bottom, top, base))
    seg = pts[1:] - pts[:-1]
    length = np.hypot(seg[:, 0], seg[:, 1])
    keep = length > 0.01
    if not keep.any():
        return
    u1 = np.cumsum(length)
    u0 = u1 - length
    i0, i1 = np.flatnonzero(keep), np.flatnonzero(keep) + 1
    a, b = pts[i0], pts[i1]

    def corner(p, y):
        return np.column_stack([p[:, 0], y, -p[:, 1]])
    ab, bb, at, bt = corner(a, bottom[i0]), corner(b, bottom[i1]), corner(a, top[i0]), corner(b, top[i1])
    pos = np.stack([np.stack([ab, bb, bt], 1), np.stack([ab, bt, at], 1)], 1).reshape(-1, 3, 3)
    uv_ab = np.column_stack([u0[keep], bottom[i0] - base[i0]])
    uv_bb = np.column_stack([u1[keep], bottom[i1] - base[i1]])
    uv_at = np.column_stack([u0[keep], top[i0] - base[i0]])
    uv_bt = np.column_stack([u1[keep], top[i1] - base[i1]])
    uv = np.stack([np.stack([uv_ab, uv_bb, uv_bt], 1), np.stack([uv_ab, uv_bt, uv_at], 1)], 1).reshape(-1, 3, 2)
    s = seg[keep]
    out = np.column_stack([s[:, 1], np.zeros(len(s)), s[:, 0]]) / length[keep][:, None]
    builder.add(pos, uv, uv2, np.repeat(out, 2, axis=0))


# Bents.

def _add_bents(poly, chains: np.ndarray, tracks: Tracks, network, builders: dict, style: str, columns: list) -> int:
    """Bents every BENT_SPACING along the deck's tracks (longest first; other
    tracks only where they branch off): a cap girder across the deck on
    columns. Returns how many."""
    accepted = []
    count = 0
    shapely.prepare(poly)
    for c in sorted(chains.tolist(), key=lambda c: -tracks.chains[c].length):
        for line in lines_of(shapely.intersection(tracks.chains[c], poly)):
            if line.length < BENT_SPACING * 0.5:
                continue
            for s in np.arange(BENT_SPACING * 0.5, line.length, BENT_SPACING):
                point = line.interpolate(s)
                if accepted and shapely.distance(np.array(accepted, dtype=object), point).min() < BENT_GAP:
                    continue
                for shift in (0.0,) + BENT_SHIFTS:
                    if not 0.0 <= s + shift <= line.length:
                        continue
                    bent = _bent(poly, line, s + shift, tracks, network, style)
                    if bent is not None:
                        break
                if bent is None:
                    continue
                cross, spots, y, tangent = bent
                accepted.append(cross)
                _build_bent(cross, spots, y, tangent, network, builders, style)
                for spot in spots:
                    columns.append((spot[0], spot[1]))
                count += 1
    return count


def _bent(poly, line, s: float, tracks: Tracks, network, style: str):
    """The bent at distance s along a track: (its cap's line, the columns'
    spots (N, 2), the deck's height, the track's direction), or None where it
    can't stand (low deck, columns in a crossing street's roadway)."""
    points, normal = markings._frame(line, np.array([s]))
    point, across = points[0], normal[0]
    tangent = np.array([across[1], -across[0]])
    y = float(tracks.height(point[None])[0])
    ground = float(network.street(point[None])[0])
    cap_bottom = y - GIRDER_DEPTH - CAP_BELOW
    if cap_bottom - ground < COLUMN_CLEARANCE:
        return None
    reach = shapely.LineString([point - across * 40.0, point + across * 40.0])
    local = shapely.clip_by_rect(poly, point[0] - 41.0, point[1] - 41.0, point[0] + 41.0, point[1] + 41.0)
    pieces = [p for p in lines_of(shapely.intersection(reach, local)) if shapely.dwithin(p, shapely.Point(point), 0.5)]
    if not pieces:
        return None
    ends = (shapely.get_coordinates(pieces[0]) - point) @ across
    lo, hi = float(ends.min()), float(ends.max())
    if hi - lo < 2 * COLUMN_INSET + 0.5:
        return None
    offsets = [lo + COLUMN_INSET, hi - COLUMN_INSET]
    span = offsets[1] - offsets[0]
    if span > MAX_BENT_SPAN:
        n = int(np.ceil(span / MAX_BENT_SPAN))
        offsets = list(np.linspace(offsets[0], offsets[1], n + 1))

    # Streets under the bent: crossing ones keep the columns out of their
    # roadway; the one it runs along, out of its travel lanes.
    hits = network.under_tree.query(reach, predicate="dwithin", distance=1.0)
    moved = []
    for o in offsets:
        spot = point + across * o
        for k in hits:
            street = network.under_lines[k]
            gap = float(shapely.distance(street, shapely.Point(spot)))
            if gap > network.under_half[k] + 2.0:
                continue
            at = street.project(shapely.Point(spot))
            foot, street_normal = markings._frame(street, np.array([at]))
            direction = np.array([street_normal[0][1], -street_normal[0][0]])
            if abs(direction @ tangent) < CROSSING_COSINE:
                if gap < network.under_half[k] + 0.5:
                    return None
                continue
            travel = float(network.under_travel[k])
            if gap < travel + TRAVEL_GAP - 0.1:
                center = float((foot[0] - point) @ across)
                side = 1.0 if o >= center else -1.0
                o = center + side * (travel + TRAVEL_GAP)
                spot = point + across * o
        if lo - COLUMN_REACH <= o <= hi + COLUMN_REACH:
            moved.append(o)
    moved = sorted(moved)
    kept = []
    for o in moved:
        if not kept or o - kept[-1] >= 2.0:
            kept.append(o)
    if not kept:
        return None
    lo, hi = min(lo, kept[0] - COLUMN_INSET), max(hi, kept[-1] + COLUMN_INSET)
    cross = shapely.LineString([point + across * lo, point + across * hi])
    return cross, point + np.outer(kept, across), y, tangent


def _build_bent(cross, spots: np.ndarray, y: float, tangent: np.ndarray, network, builders: dict, style: str) -> None:
    """A cap girder along `cross` under the deck at height y, and columns at
    `spots` down to the ground (knee braces on steel ones, up close)."""
    ends = shapely.get_coordinates(cross)
    middle = ends.mean(axis=0)
    across = (ends[1] - ends[0]) / max(np.linalg.norm(ends[1] - ends[0]), 1e-6)
    half_cap = np.linalg.norm(ends[1] - ends[0]) / 2
    cap_top = y - FLOOR_DEPTH
    cap_bottom = y - GIRDER_DEPTH - CAP_BELOW
    half_along, half_across = COLUMN_SIZE[style]
    kind = STEEL if style == "steel" else CONCRETE
    parts = builders["parts"]
    parts.box(middle, across, half_cap, half_along + 0.1, cap_bottom, cap_top, kind, DETAILED)
    for spot in spots:
        ground = float(network.street(spot[None])[0])
        footing = ground - 1.0 if shapely.contains_xy(network.land, spot[0], spot[1]) else WATER_FOOTING_Y
        parts.box(spot, across, half_across, half_along, footing, cap_bottom, kind, DETAILED, base=ground)
        if style != "steel" or cap_bottom - ground < 2 * BRACE + 1.0:
            continue
        for side in (-1.0, 1.0):
            reach = spot + across * side * BRACE
            if abs((reach - middle) @ across) > half_cap:
                continue
            low = np.array([spot[0] + across[0] * side * half_across, cap_bottom - BRACE,
                            -(spot[1] + across[1] * side * half_across)])
            parts.beam(low, (reach[0], cap_bottom, -reach[1]), 0.12, kind, ("lod0",))


class _Parts:
    """Boxes (columns, cap girders, posts) and beams (braces), collected and
    then built all at once."""

    def __init__(self):
        self.boxes = {level: [] for level in DETAILED}
        self.beams = {level: [] for level in DETAILED}

    def box(self, base_en, u, half_u, half_v, y0, y1, kind: tuple, levels, base=None) -> None:
        """A box standing on (east, north) `base_en`, turned to `u`, from y0 to
        y1 (no bottom face); its walls' uv.y is meters above `base` (y0 if None)."""
        row = (base_en[0], base_en[1], u[0], u[1], half_u, half_v, y0, y1, y0 if base is None else base) + tuple(kind)
        for level in levels:
            self.boxes[level].append(row)

    def beam(self, a, b, half: float, kind: tuple, levels) -> None:
        """A square beam between two Godot-space points."""
        for level in levels:
            self.beams[level].append(tuple(a) + tuple(b) + (half,) + tuple(kind))

    def build(self, builders: dict) -> None:
        for level in DETAILED:
            if level in builders and self.boxes[level]:
                _build_boxes(builders[level], np.array(self.boxes[level]))
            if level in builders and self.beams[level]:
                _build_beams(builders[level], np.array(self.beams[level]))


def _build_boxes(builder: MeshBuilder, rows: np.ndarray) -> None:
    base, u = rows[:, 0:2], rows[:, 2:4]
    half_u, half_v, y0, y1, ground = rows[:, 4:5], rows[:, 5:6], rows[:, 6], rows[:, 7], rows[:, 8]
    v = np.column_stack([-u[:, 1], u[:, 0]])
    corners = np.stack([base + u * su * half_u + v * sv * half_v for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))],
                       axis=1)  # (N, 4, 2), counter-clockwise
    a, b = corners, np.roll(corners, -1, axis=1)
    n = len(rows)

    def at(p, y):
        return np.stack([p[..., 0], np.broadcast_to(y[:, None], p.shape[:2]), -p[..., 1]], axis=-1)
    ab, bb, at_, bt = at(a, y0), at(b, y0), at(a, y1), at(b, y1)
    walls = np.stack([np.stack([ab, bb, bt], 2), np.stack([ab, bt, at_], 2)], 2).reshape(-1, 3, 3)
    length = np.linalg.norm(b - a, axis=2)  # (N, 4)
    lo, hi = (y0 - ground)[:, None], (y1 - ground)[:, None]
    zero = np.zeros((n, 4))

    def uv(x, y):
        return np.stack([x, np.broadcast_to(y, (n, 4))], axis=-1)
    uv_ab, uv_bb, uv_at, uv_bt = uv(zero, lo), uv(length, lo), uv(zero, hi), uv(length, hi)
    walls_uv = np.stack([np.stack([uv_ab, uv_bb, uv_bt], 2), np.stack([uv_ab, uv_bt, uv_at], 2)], 2).reshape(-1, 3, 2)
    d = b - a
    out = np.stack([d[..., 1], np.zeros((n, 4)), d[..., 0]], axis=-1) / np.maximum(length, 1e-9)[..., None]
    walls_front = np.repeat(out, 2, axis=1).reshape(-1, 3)
    kinds = np.repeat(rows[:, 9:11], 8, axis=0)[:, None, :].repeat(3, axis=1)
    builder.add(walls, walls_uv, kinds, walls_front)
    top = np.stack([corners[:, [0, 1, 2]], corners[:, [0, 2, 3]]], axis=1).reshape(-1, 3, 2)
    top_y = np.repeat(y1, 2)[:, None].repeat(3, axis=1)
    builder.add(np.stack([top[..., 0], top_y, -top[..., 1]], axis=-1), np.stack([top[..., 0], -top[..., 1]], axis=-1),
                np.repeat(rows[:, 9:11], 2, axis=0)[:, None, :].repeat(3, axis=1), (0.0, 1.0, 0.0))


def _build_beams(builder: MeshBuilder, rows: np.ndarray) -> None:
    a, b, half = rows[:, 0:3], rows[:, 3:6], rows[:, 6:7]
    direction = b - a
    length = np.linalg.norm(direction, axis=1, keepdims=True)
    keep = length[:, 0] > 1e-3
    a, b, half, direction, length, rows = a[keep], b[keep], half[keep], direction[keep], length[keep], rows[keep]
    direction = direction / length
    side = np.cross(direction, [0.0, 1.0, 0.0])
    side_length = np.linalg.norm(side, axis=1, keepdims=True)
    side = np.where(side_length > 1e-3, side / np.maximum(side_length, 1e-9), [1.0, 0.0, 0.0])
    up = np.cross(side, direction)
    pos, front = [], []
    for normal, tangent in ((side, up), (up, -side), (-side, -up), (-up, side)):
        corner, edge = normal * half, tangent * half
        quad = [a + corner - edge, b + corner - edge, b + corner + edge, a + corner + edge]
        pos += [np.stack([quad[0], quad[1], quad[2]], 1), np.stack([quad[0], quad[2], quad[3]], 1)]
        front += [normal, normal]
    n = len(rows)
    pos = np.stack(pos, axis=1).reshape(-1, 3, 3)
    front = np.stack(front, axis=1).reshape(-1, 3)
    span = length[:, 0]
    one = np.stack([np.stack([np.zeros(n), np.zeros(n)], 1), np.stack([span, np.zeros(n)], 1),
                    np.stack([span, np.ones(n)], 1)], 1)
    two = np.stack([np.stack([np.zeros(n), np.zeros(n)], 1), np.stack([span, np.ones(n)], 1),
                    np.stack([np.zeros(n), np.ones(n)], 1)], 1)
    uv = np.stack([one, two] * 4, axis=1).reshape(-1, 3, 2)
    kinds = np.repeat(rows[:, 7:9], 8, axis=0)[:, None, :].repeat(3, axis=1)
    builder.add(pos, uv, kinds, front)


def _bucket_columns(target: dict, columns: list, size: float) -> None:
    if not columns:
        return
    en = np.array(columns)
    ii = np.floor(en[:, 0] / size).astype(np.int64)
    jj = np.floor(-en[:, 1] / size).astype(np.int64)
    for key in set(zip(ii.tolist(), jj.tolist())):
        found = en[(ii == key[0]) & (jj == key[1])]
        target[key] = np.vstack([target[key], found]) if key in target else found


def clear_of_columns(columns: dict, i: int, j: int, en: np.ndarray, cars: np.ndarray) -> np.ndarray:
    """Which props at (N, 2) points keep clear of the el columns around near
    tile (i, j) (`cars` marks parked cars, which need more room)."""
    keep = np.ones(len(en), dtype=bool)
    found = [columns[key] for key in ((i + di, j + dj) for di in (-1, 0, 1) for dj in (-1, 0, 1)) if key in columns]
    if not found or len(en) == 0:
        return keep
    spots = shapely.points(np.vstack(found))
    hits = shapely.STRtree(spots).query(shapely.points(en), predicate="dwithin", distance=CAR_CLEAR)
    if len(hits[0]):
        gap = shapely.distance(spots[hits[1]], shapely.points(en[hits[0]]))
        near = gap < np.where(cars[hits[0]], CAR_CLEAR, PROP_CLEAR)
        keep[hits[0][near]] = False
    return keep


# Stations.

def _add_platforms(station, chains: np.ndarray, tracks: Tracks, network, builders: dict) -> int:
    """An elevated station's platforms: its outline near the deck's tracks,
    clear of them, PLATFORM_HEIGHT above the deck; windscreens along the
    outer edges and canopies on posts up close. Returns how many platforms."""
    near = [c for c in chains.tolist() if shapely.dwithin(tracks.chains[c], station, PLATFORM_REACH)]
    if not near:
        return 0
    lines = shapely.union_all(tracks.chains[near])
    clear = shapely.buffer(lines, TRACK_CLEAR, cap_style="flat")
    region = shapely.difference(shapely.intersection(station, shapely.buffer(lines, PLATFORM_REACH)), clear)
    count = 0
    for platform in polygons_of(region, 4.0):
        if shapely.buffer(platform, -MIN_PLATFORM_WIDTH / 2).is_empty:
            continue
        platform = shapely.orient_polygons(shapely.simplify(platform, 0.1))
        count += 1

        def floor(en):
            return tracks.height(en) + PLATFORM_HEIGHT
        for level, spacing in (("lod0", DECK_SPACING["lod0"]), ("lod1", DECK_SPACING["lod1"])):
            if level not in builders:
                continue
            builder = builders[level]
            tris = _triangles(shapely.segmentize(platform, spacing), spacing)
            if tris is not None:
                y = floor(tris.reshape(-1, 2)).reshape(-1, 3)
                top = np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1)
                builder.add(top, np.stack([tris[..., 0], -tris[..., 1]], axis=-1), PLATFORM, (0.0, 1.0, 0.0))
            dense = shapely.segmentize(platform, spacing)
            for ring in (dense.exterior, *dense.interiors):
                coords = np.asarray(ring.coords)[:, :2]
                y = floor(coords)
                bottom = y - PLATFORM_HEIGHT - FLOOR_DEPTH
                _add_walls(builder, coords, bottom, y, bottom, CONCRETE)
                if level == "lod0":
                    # Windscreens where the edge is away from the tracks.
                    mids = shapely.points((coords[1:] + coords[:-1]) / 2)
                    outer = shapely.distance(lines, mids) > TRACK_CLEAR + 1.0
                    for start, stop in overpasses._runs(outer):
                        _add_walls(builder, coords[start:stop + 1], y[start:stop + 1], y[start:stop + 1] + WINDSCREEN,
                                   y[start:stop + 1], STEEL)
            _add_canopy(platform, floor, spacing, builder, builders["parts"], level == "lod0")
    return count


def _add_canopy(platform, floor, spacing: float, builder: MeshBuilder, parts: _Parts, detailed: bool) -> None:
    """A canopy CANOPY_HEIGHT over a platform, and up close its edges and posts."""
    roof = shapely.buffer(platform, -CANOPY_INSET, join_style="mitre")
    for piece in polygons_of(roof, 2.0):
        piece = shapely.orient_polygons(piece)
        tris = _triangles(shapely.segmentize(piece, spacing), spacing)
        if tris is None:
            continue
        y = (floor(tris.reshape(-1, 2)) + CANOPY_HEIGHT).reshape(-1, 3)
        top = np.stack([tris[..., 0], y + CANOPY_THICKNESS, -tris[..., 1]], axis=-1)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        builder.add(top, uv, STEEL, (0.0, 1.0, 0.0))
        if not detailed:
            continue
        builder.add(top - np.array([0.0, CANOPY_THICKNESS, 0.0]), uv, LIT_STEEL, (0.0, -1.0, 0.0))
        dense = shapely.segmentize(piece, spacing)
        for ring in (dense.exterior, *dense.interiors):
            coords = np.asarray(ring.coords)[:, :2]
            y_ring = floor(coords) + CANOPY_HEIGHT
            _add_walls(builder, coords, y_ring, y_ring + CANOPY_THICKNESS, y_ring, STEEL)
        # Posts down the platform's middle.
        u, _, center, length = bridges._axis(piece)
        inner = shapely.buffer(piece, -0.4)
        if inner.is_empty:
            continue
        shapely.prepare(inner)
        line = shapely.LineString([center - u * length / 2, center + u * length / 2])
        cut = shapely.intersection(line, inner)
        for part in lines_of(cut):
            for s in np.arange(POST_SPACING / 2, part.length, POST_SPACING):
                spot = np.asarray(part.interpolate(s).coords)[0]
                y0 = float(floor(spot[None])[0])
                parts.box(spot, u, 0.12, 0.12, y0, y0 + CANOPY_HEIGHT, STEEL, ("lod0",))
