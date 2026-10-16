"""Overpasses: roads raised above the ground on land (highway viaducts like
the Gowanus and the Major Deegan, ramps, streets over rail cuts and sunken
highways, rail bridges over streets), as decks on columns.

Two sources, combined:
- The street centerlines (CSCL) give each segment's level at both ends:
  13 is street level, 17 one level up, 21 two, 25 three (9 and 5 are below,
  in trenches and tunnels, left alone). A raised road climbs from street level
  to LEVEL_RISE per level (a typical 5 m clearance under a 2 m deck) above
  the low ground around it, ramping along each segment between the levels at
  its ends, and never dips below the ground. Raised segments become decks
  their width wide (merged per level, so carriageways and ramps at one level
  form one deck).
- The planimetric bridge outlines (Transportation Structures, feature code
  2300) on land: the outline becomes the deck. Outlines that raised roads run
  through join those roads' deck; the others (streets over rail cuts and
  trenches, rail bridges, footbridges) span between the ground at their two
  ends, and rise LEVEL_RISE over any street that passes underneath.
Outlines over water are bridges.py's.

Decks less than AT_GRADE_GAP above the street are left out (the street is
already there); where a deck is low, its sides go down to the ground (an
abutment or embankment) instead of standing on columns. Everything under a
deck stays: the streets, sidewalks and people.

The city's elevation model can't give deck heights: it's bare earth, with
bridges removed (and its 10 m pixels blur embankments). It does give the
ground the levels count up from.

prepare() makes data/cache/overpasses.pkl from the raw downloads. Network
holds the raised roads and their heights; build() adds the decks to the
bridge buckets (bridges.build's format, so they get collision up close), and
lanes() / paint() give each near tile its driving lanes and paint on decks.
"""

import numpy as np
import shapely
from shapely.geometry import shape

import bridges
import markings
import props
import traffic
from common import (CURB_HEIGHT, FEET, GROUND_ROAD, MARKING_LIFT, STRUCTURE_CONCRETE, MeshBuilder, lines_of,
                    load_features, polygons_of, project)
from markings import AT_GRADE, BOTH, HIGHWAY, STREET

BRIDGE_CODE = "2300"
# Roadway types (CSCL rw_type) that get decks: streets, highways, bridges,
# ramps; and paths (footbridges), which get no lanes or paint.
BRIDGE, RAMP, PATH = 3, 9, 6
ROAD_TYPES = (STREET, HIGHWAY, BRIDGE, RAMP)
LEVEL_STEP = 4       # level codes per level
LEVEL_RISE = 7.0     # meters from the road below to the deck's top, per level
# The ground a raised road's levels count up from: the lowest within these
# rings around it (so a road on an embankment isn't counted from its top).
LOW_RINGS = (15.0, 30.0)
# Heights along each segment at least this often (meters).
STATION_STEP = 10.0
# Widths when the data has none (meters): per lane, plus shoulders.
LANE_WIDTH, SHOULDERS = 3.6, 2.0
PATH_WIDTH = 4.0
MIN_WIDTH, MAX_WIDTH = 5.0, 40.0
# Bridge outlines with less water under them than this are overpasses
# (bridges.MIN_WATER_AREA).
MAX_WATER = 150.0
# A raised road counts as running through an outline with at least this much
# of its length (meters) inside.
MIN_INSIDE = 15.0
# Outlines without a raised road: streets passing underneath (at an angle of
# at least this much to the deck) lift the deck LEVEL_RISE above them,
# tapering off at RAMP_GRADE either side.
CROSSING_SINE = 0.6
RAMP_GRADE = 0.08
END_STRIP = 6.0      # meters at each end of an outline where its ends' ground is read
# Street crossings of creeks and canals the data has no bridge for, this long
# (meters over the water); their decks sit this far above the banks' street.
MIN_CROSSING, MAX_CROSSING = 5.0, 300.0
CROSSING_LIFT = 0.3
# Outlines that never rise this far above the street aren't built (they'd
# only hide the street they carry).
MIN_RISE = 1.0

DECK_THICKNESS = 2.0
WATER_FOOTING_Y = -8.0
PARAPET_HEIGHT = 1.1
AT_GRADE_GAP = 0.25  # decks closer than this to the street are left out
GRADE_DECK = 3.0     # street-level roads on land take decks at most this far from the street
PARAPET_FROM = 1.0   # parapets where the deck is at least this high
SOLID_BELOW = 2.5    # under a lower gap, the deck's sides go down to the ground
COLUMN_SPACING = 36.0
COLUMN_CLEARANCE = 3.0
COLUMN_SIZE = (1.0, 0.7)   # half sizes along and across the road (m)
MEDIAN = 1.0               # columns may stand this close to a two-way street's middle
CAP_DEPTH = 1.2            # the pier cap under the deck
WIDE_DECK = 16.0           # wider roads stand on two columns
COLUMN_STREET_GAP = 4.0    # columns keep this far from streets crossing underneath
# How finely decks follow their heights, per level (meters between points),
# and the smallest decks the far tiles keep (m^2).
DECK_SPACING = {"lod0": 10.0, "lod1": 20.0, "lod2": 40.0}
FAR_MIN_AREA = 3000.0
DETAILED = ("lod0", "lod1")

# Node ids for raised roads' ends that aren't at a street-level node:
# above any street node id (markings.prepare), below 2^24 (exact as floats).
NODE_BASE = 4_000_000
# Lanes over water without a deck (bridges left out of the world) are dropped.


def prepare() -> dict:
    """Raised road segments (any end above street level), street-level ramps
    and bridges (which link them and the bridges over water to the streets),
    and the bridge outlines."""
    lines, rows = [], []
    for feat in load_features("centerline"):
        p = feat["properties"]
        rw = int(p.get("rw_type") or 0)
        if rw not in ROAD_TYPES + (PATH,) or p.get("status", "2") != "2":
            continue
        levels = (int(p.get("from_level_code") or AT_GRADE), int(p.get("to_level_code") or AT_GRADE))
        if max(levels) <= int(AT_GRADE) and rw not in (RAMP, BRIDGE):
            continue
        trafdir = {"FT": markings.WITH, "TF": markings.AGAINST, "TW": BOTH}.get(p.get("trafdir"), BOTH)
        geom = shapely.line_merge(shape(feat["geometry"]))
        for part in shapely.get_parts(geom):
            lines.append(part)
            rows.append((rw, trafdir, int(float(p.get("number_travel_lanes") or 0)),
                         int(float(p.get("number_park_lanes") or 0)), float(p.get("streetwidth") or 0) * FEET,
                         levels[0], levels[1]))
    lines = project(np.array(lines, dtype=object))
    attrs = np.array(rows, dtype=np.float64)
    keep = shapely.length(lines) > 1.0
    lines, attrs = lines[keep], attrs[keep]

    outlines = [f for f in load_features("transport_structures") if str(f["properties"].get("feat_code")) == BRIDGE_CODE]
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in outlines], dtype=object)))
    return {
        "lines": lines,
        "rw": attrs[:, 0].astype(np.int8),
        "trafdir": attrs[:, 1].astype(np.int8),
        "lanes": attrs[:, 2].astype(np.int16),
        "parking": attrs[:, 3].astype(np.int16),
        "width": attrs[:, 4].astype(np.float32),
        "levels": attrs[:, 5:7].astype(np.int8),  # (from, to)
        "outlines": geoms,
        "outline_names": [f["properties"].get("name") or "NO NAME" for f in outlines],
    }


def rise(level) -> np.ndarray:
    """Meters above the road below for CSCL level codes (0 at street level and below)."""
    return np.maximum(np.asarray(level, np.float64) - int(AT_GRADE), 0.0) / LEVEL_STEP * LEVEL_RISE


class Network:
    """The raised roads (and street-level ramps): their heights, their decks'
    groups, and their attributes in markings.prepare's format (for traffic.lanes
    and markings.quads), with node ids that match the streets'.

    `terrain` is a terrain.Terrain; `streets` the prepared street centerlines
    (markings.prepare)."""

    def __init__(self, data: dict, streets: dict, terrain):
        self.data = data
        self.lines = data["lines"]
        self.count = len(self.lines)
        self.terrain = terrain
        self.ground_lattice = terrain.lattice(20.0)  # the lod0 ground (build_tiles.LEVELS)
        self.levels = data["levels"].astype(np.int64)
        top = self.levels.max(axis=1)
        self.raised = top > int(AT_GRADE)
        # Decks are grouped by level, rounded up to whole levels.
        self.group = np.where(self.raised, int(AT_GRADE) + LEVEL_STEP * np.ceil((top - int(AT_GRADE)) / LEVEL_STEP), 0)
        self.group = self.group.astype(np.int64)
        self.width = self._widths()
        self.tree = shapely.STRtree(self.lines)
        self._stations = [None] * self.count
        self.attrs = self._attributes(streets)
        # Street-level roads, for what passes under a deck: the streets and
        # our street-level ramps.
        ramps = ~self.raised & (data["rw"] != PATH)
        street_half = np.where(streets["width"] > 0, streets["width"] / 2.0,
                               np.maximum(streets["lanes"], 1) * markings.LANE_WIDTH / 2.0 + 1.0)
        self.under_lines = np.concatenate([streets["lines"], self.lines[ramps]])
        self.under_half = np.concatenate([street_half, self.width[ramps] / 2.0])
        self.under_two_way = np.concatenate([streets["trafdir"] == BOTH, data["trafdir"][ramps] == BOTH])
        self.under_tree = shapely.STRtree(self.under_lines)

    def _widths(self) -> np.ndarray:
        d = self.data
        rw = d["rw"].astype(np.int64)
        lanes = np.maximum(d["lanes"].astype(np.float64), np.where(d["trafdir"] == BOTH, 2.0, 1.0))
        guess = lanes * LANE_WIDTH + d["parking"] * markings.PARKING_WIDTH + SHOULDERS
        width = np.where(d["width"] > 0, d["width"] + 1.0, guess)
        width = np.where(rw == PATH, PATH_WIDTH, width)
        return np.clip(width, MIN_WIDTH, MAX_WIDTH)

    def _attributes(self, streets: dict) -> dict:
        """markings.prepare-style attributes. Ramps and bridges paint and
        drive like highways (two-way ones like streets); lanes run from end to
        end, except at street intersections, where they stop at the curb line
        like the streets'."""
        d = self.data
        rw = d["rw"].astype(np.int64)
        painted = np.where(np.isin(rw, (BRIDGE, RAMP)), np.where(d["trafdir"] == BOTH, STREET, HIGHWAY), rw)
        painted = np.where(rw == PATH, PATH, painted)

        # Street nodes by position (to 0.5 m), as markings.prepare finds them.
        street_lines = streets["lines"]
        ends = np.vstack([shapely.get_coordinates(shapely.get_point(street_lines, 0)),
                          shapely.get_coordinates(shapely.get_point(street_lines, -1))])
        keys = np.round(ends * 2.0).astype(np.int64)
        flat = streets["nodes"].T.reshape(-1)
        crossing = streets["crossing"].T.reshape(-1)
        setback = streets["setback"].T.reshape(-1)
        node_of, setback_at, crossing_at = {}, {}, {}
        for (x, y), node, c, s in zip(keys.tolist(), flat.tolist(), crossing.tolist(), setback.tolist()):
            node_of[(x, y)] = node
            crossing_at[node] = crossing_at.get(node, False) or bool(c)
            setback_at[node] = max(setback_at.get(node, 0.0), float(s))

        mine = np.vstack([shapely.get_coordinates(shapely.get_point(self.lines, 0)),
                          shapely.get_coordinates(shapely.get_point(self.lines, -1))])
        my_keys = np.round(mine * 2.0).astype(np.int64)
        my_levels = np.concatenate([self.levels[:, 0], self.levels[:, 1]])
        nodes = np.zeros(len(mine), dtype=np.int64)
        ends_setback = np.zeros(len(mine), dtype=np.float32)
        ends_crossing = np.zeros(len(mine), dtype=bool)
        others = {}
        for e, ((x, y), level) in enumerate(zip(my_keys.tolist(), my_levels.tolist())):
            street = node_of.get((x, y)) if level == int(AT_GRADE) else None
            if street is not None:
                nodes[e] = street
                ends_crossing[e] = crossing_at[street]
                ends_setback[e] = setback_at[street] if crossing_at[street] else 0.0
            else:
                nodes[e] = others.setdefault((x, y, level), NODE_BASE + len(others))
        n = self.count
        out = {
            "lines": self.lines,
            "rw": painted.astype(np.int8),
            "trafdir": d["trafdir"],
            "lanes": d["lanes"],
            "parking": np.zeros(n, dtype=np.int16),  # no parking on raised roads
            "width": d["width"],
            "setback": ends_setback.reshape(2, n).T,
            "major": np.zeros((n, 2), dtype=bool),
            "signal": np.zeros((n, 2), dtype=bool),
            "phase": np.full((n, 2), -1.0, dtype=np.float32),
            "nodes": nodes.reshape(2, n).T.astype(np.int32),
            "crossing": ends_crossing.reshape(2, n).T,
            "priority": np.zeros((n, 2), dtype=bool),
        }
        # Anything else the streets carry, as zeros (so traffic and markings
        # find every field they look for).
        for key, value in streets.items():
            if key not in out and isinstance(value, np.ndarray) and len(value) == len(street_lines):
                out[key] = np.zeros((n,) + value.shape[1:], dtype=value.dtype)
        return out

    # Heights.

    def street(self, en: np.ndarray) -> np.ndarray:
        """The street surface's height at (N, 2) points (the ground less the curb)."""
        return self.ground_lattice.height(en) - CURB_HEIGHT

    def low(self, en: np.ndarray) -> np.ndarray:
        """The lowest street height in LOW_RINGS around each point."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        angles = np.arange(8) * (np.pi / 4)
        offsets = np.concatenate([[[0.0, 0.0]]] + [np.column_stack([np.cos(angles), np.sin(angles)]) * r
                                                   for r in LOW_RINGS])
        h = self.terrain.height((en[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(len(en), -1)
        return h.min(axis=1) - CURB_HEIGHT

    def stations(self, k: int) -> tuple[np.ndarray, np.ndarray]:
        """Distances along segment k and its road's height there."""
        if self._stations[k] is None:
            line = self.lines[k]
            length = line.length
            s = np.linspace(0.0, length, max(2, int(np.ceil(length / STATION_STEP)) + 1))
            en = shapely.get_coordinates(shapely.line_interpolate_point(line, s))
            street = self.street(en)
            l0, l1 = self.levels[k]
            if max(l0, l1) <= int(AT_GRADE):
                h = street
            else:
                low = self.low(en)
                ends = [max(street[i], low[i] + float(rise(level))) if level > int(AT_GRADE) else street[i]
                        for i, level in ((0, l0), (-1, l1))]
                t = s / max(length, 1e-6)
                # Half straight, half eased: ramps climb steadily but round
                # into the level road at either end.
                ease = 0.5 * t + 0.5 * t * t * (3.0 - 2.0 * t)
                h = ends[0] + (ends[1] - ends[0]) * ease
                floor = street if min(l0, l1) <= int(AT_GRADE) else np.maximum(street, low + float(rise(min(l0, l1))))
                h = np.maximum(h, floor)
                h[0], h[-1] = ends[0], ends[1]
            self._stations[k] = (s, h)
        return self._stations[k]

    def along(self, k: int, en: np.ndarray) -> np.ndarray:
        """Segment k's road height at the points nearest (N, 2) points."""
        s, h = self.stations(k)
        at = shapely.line_locate_point(self.lines[k], shapely.points(np.asarray(en, np.float64).reshape(-1, 2)))
        return np.interp(at, s, h)

    def field(self, en: np.ndarray, segments: np.ndarray) -> np.ndarray:
        """Heights at (N, 2) points from the nearest of these segments."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if len(segments) == 1:
            return self.along(int(segments[0]), en)
        tree = shapely.STRtree(self.lines[segments])
        nearest = tree.query_nearest(shapely.points(en), return_distance=False, all_matches=False)
        out = np.empty(len(en))
        for j in np.unique(nearest[1]):
            mask = nearest[0][nearest[1] == j]
            out[mask] = self.along(int(segments[j]), en[mask])
        return out

    def approach(self, en: np.ndarray) -> np.ndarray:
        """Where a bridge's approach (bridges.py) meets the land: the street,
        or the raised road it continues as."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        street = self.street(en)
        if len(en) == 0:
            return street
        out = street.copy()
        hits = self.tree.query(shapely.points(en), predicate="dwithin", distance=12.0)
        for i in np.unique(hits[0]):
            candidates = hits[1][hits[0] == i]
            candidates = candidates[self.raised[candidates] & (self.data["rw"][candidates] != PATH)]
            if len(candidates):
                out[i] = max(street[i], float(self.field(en[i:i + 1], candidates)[0]))
        return out


def build(network: Network, land, buckets: dict, level_sizes: dict) -> None:
    """Adds the overpass decks to bridges.build's buckets: triangles per level
    and tile, and lamps along the decks."""
    shapely.prepare(land)
    data = network.data
    # Each part of an outline on its own, as bridges.py takes them: parts
    # over water are bridges, the rest overpasses.
    network.land = land
    on_land, names, over_water, wet_outlines = [], [], [], []
    for outline, name in zip(data["outlines"], data["outline_names"]):
        for part in polygons_of(outline, 50.0):
            name = bridges.outline_name(part, name)
            local = bridges.local_land(land, part)
            water = shapely.area(shapely.difference(part, local))
            if not bridges.is_overpass(part, water, name):
                over_water.append(part)
            elif water < MAX_WATER:
                on_land.append(shapely.intersection(part, local))
                names.append(name)
            else:
                # A viaduct that crosses a canal or creek on its way: all of it.
                on_land.append(part)
                names.append(name)
                wet_outlines.append(part)
    keep_out = shapely.union_all(shapely.buffer(over_water, 1.0)) if over_water else shapely.Polygon()
    shapely.prepare(keep_out)
    wet_outlines = shapely.union_all(wet_outlines) if wet_outlines else shapely.Polygon()

    roads = np.flatnonzero(network.raised)
    builders = {level: MeshBuilder() for level in level_sizes}
    lamps = []
    street_decks = []  # lod0 tops of decks that carry a street over a dip (OnDecks)

    # Which outlines raised roads run through, and at which level.
    groups = {}
    plain = []
    for poly, name in zip(on_land, names):
        for part in polygons_of(poly, 20.0):
            inside = network.tree.query(part, predicate="intersects")
            inside = inside[network.raised[inside]]
            lengths = shapely.length(shapely.intersection(network.lines[inside], part)) if len(inside) else []
            through = inside[np.asarray(lengths) >= np.minimum(MIN_INSIDE, 0.5 * shapely.length(network.lines[inside]))] \
                if len(inside) else inside
            if len(through):
                totals = {}
                for k, length in zip(inside, lengths):
                    totals[network.group[k]] = totals.get(network.group[k], 0.0) + length
                groups.setdefault(max(totals, key=totals.get), []).append(part)
            else:
                plain.append(part)

    decks = 0
    for group in sorted(set(network.group[roads].tolist())):
        members = roads[network.group[roads] == group]
        strips = shapely.buffer(network.lines[members], network.width[members] / 2.0, cap_style="flat", quad_segs=2)
        area = shapely.union_all(list(strips) + groups.get(group, []))
        area = shapely.difference(area, keep_out)
        tree = shapely.STRtree(network.lines[members])
        for poly in _over_land(polygons_of(area, 20.0), land, wet_outlines):
            poly = shapely.orient_polygons(shapely.simplify(poly, 0.2))
            segs = members[tree.query(poly, predicate="intersects")]
            if len(segs) == 0:
                continue

            def deck_y(en, segs=segs):
                return network.field(en, segs)
            if _add_deck(poly, deck_y, network, builders, top_kind=GROUND_ROAD) is not None:
                decks += 1
                _add_road_columns(poly, segs, deck_y, network, builders)
                lamps.append(_deck_lamps(poly, deck_y, network))

    plain_built = 0
    for poly in plain:
        poly = shapely.orient_polygons(poly)
        deck_y, carries = _plain_profile(poly, network)
        if deck_y is None:
            continue
        top = _add_deck(poly, deck_y, network, builders, top_kind=GROUND_ROAD if carries else STRUCTURE_CONCRETE)
        if top is not None:
            plain_built += 1
            _add_axis_columns(poly, deck_y, network, builders)
            if carries:
                street_decks.append(top)

    # Streets crossing a creek or canal where the data has no bridge at all.
    covered = shapely.union_all([keep_out] + list(on_land))
    shapely.prepare(covered)
    crossings = 0
    for poly, deck_y in _missing_crossings(network, land, covered):
        top = _add_deck(poly, deck_y, network, builders, top_kind=GROUND_ROAD)
        if top is not None:
            crossings += 1
            _add_axis_columns(poly, deck_y, network, builders)
            street_decks.append(top)
    print(f"  overpasses: {decks} raised road decks, {plain_built} other decks over land "
          f"({len(plain)} outlines without a raised road), {crossings} creek crossings the data lacks", flush=True)

    for level, size in level_sizes.items():
        _merge(buckets.setdefault(level, {}), _bucket(builders[level], size))
    found = [l for l in lamps if len(l[0])]
    if found:
        _merge_lamps(buckets.setdefault("lamps", {}), found, level_sizes["lod0"])
    buckets["street_decks"] = street_decks


def _deck_lamps(poly, deck_y, network: Network):
    """Lamps along a road deck's edges, where it's off the street."""
    points, heights, arms = props.deck_lamps(np.asarray(poly.exterior.coords)[:, :2], deck_y)
    if len(points):
        high = heights - network.street(points) > PARAPET_FROM
        points, heights, arms = points[high], heights[high], arms[high]
    return points, heights, arms


def _add_deck(poly, deck_y, network: Network, builders: dict, top_kind: int):
    """A deck over `poly` at deck_y(en): its top (where it's off the street),
    underside, and sides with parapets, going down to the ground where the gap
    under it is low. Returns its top's triangles in the near tiles (T, 3, 3),
    or None if none of it was built."""
    built = None
    for level, spacing in DECK_SPACING.items():
        if level not in builders or (level == "lod2" and poly.area < FAR_MIN_AREA):
            continue
        dense = shapely.segmentize(poly, spacing)
        tris = _grid_triangles(dense, spacing)
        if tris is None:
            continue
        en = tris.reshape(-1, 2)
        y = deck_y(en)
        street = network.street(en)
        off = (y - street).reshape(-1, 3) >= AT_GRADE_GAP
        keep = off.any(axis=1)
        if not keep.any():
            continue
        y = np.maximum(y, street - 0.05).reshape(-1, 3)[keep]
        tris = tris[keep]
        top = np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        builders[level].add(top, uv, (top_kind, 0.0), (0.0, 1.0, 0.0))
        if level == "lod0":
            built = top
        detailed = level in DETAILED
        if detailed:
            builders[level].add(top - np.array([0.0, DECK_THICKNESS, 0.0]), uv, (STRUCTURE_CONCRETE, 0.0),
                                (0.0, -1.0, 0.0))
        for ring in (dense.exterior, *dense.interiors):
            coords = np.asarray(ring.coords)[:, :2]
            ring_y = deck_y(coords)
            ground = network.street(coords)
            gap = ring_y - DECK_THICKNESS - ground
            bottom = np.where(gap < SOLID_BELOW, np.minimum(ground - 0.5, ring_y - DECK_THICKNESS), ring_y - DECK_THICKNESS)
            top_y = np.where(detailed & (ring_y - ground >= PARAPET_FROM), ring_y + PARAPET_HEIGHT, ring_y)
            # Leave out sides along stretches at street level (the deck's ends).
            high = ring_y - ground >= AT_GRADE_GAP
            seg_high = high[:-1] | high[1:]
            for start, stop in _runs(seg_high):
                builders[level].add_walls(coords[start:stop + 1], bottom[start:stop + 1], top_y[start:stop + 1],
                                          (STRUCTURE_CONCRETE, 0.0))
    return built


def _grid_triangles(poly, cell: float):
    """Triangles (T, 3, 2) covering a polygon, cut along a `cell`-meter grid
    (so heights can follow a field inside wide decks), or None."""
    min_e, min_n, max_e, max_n = poly.bounds
    ii, jj = np.meshgrid(np.arange(np.floor(min_e / cell), np.ceil(max_e / cell)),
                         np.arange(np.floor(min_n / cell), np.ceil(max_n / cell)))
    cells = shapely.box(ii.ravel() * cell, jj.ravel() * cell, (ii.ravel() + 1) * cell, (jj.ravel() + 1) * cell)
    shapely.prepare(poly)
    cells = cells[shapely.intersects(poly, cells)]
    inside = shapely.contains_properly(poly, cells)
    whole = shapely.get_coordinates(cells[inside]).reshape(-1, 5, 2)[:, :4]
    out = [whole[:, [0, 1, 2]], whole[:, [0, 2, 3]]]
    pieces = shapely.intersection(cells[~inside], poly)
    pieces = pieces[shapely.area(pieces) > 1e-4]
    if len(pieces):
        try:
            tris = shapely.constrained_delaunay_triangles(pieces)
        except shapely.errors.GEOSException:
            tris = None
        if tris is not None:
            coords = shapely.get_coordinates(shapely.get_parts(shapely.get_parts(tris)))
            if len(coords):
                out.append(coords.reshape(-1, 4, 2)[:, :3])
    tris = np.concatenate(out)
    return tris if len(tris) else None


def _runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """(start, stop) index pairs of the runs of True in a mask of segments
    (segment i joins points i and i + 1; stop is the run's last segment + 1)."""
    out = []
    start = None
    for i, value in enumerate(mask.tolist() + [False]):
        if value and start is None:
            start = i
        elif not value and start is not None:
            out.append((start, i))
            start = None
    return out


def _missing_crossings(network: Network, land, covered) -> list:
    """Street-level roads crossing water (a creek, a canal) with no bridge
    outline there: a deck their width wide across it, from the street at one
    bank to the street at the other. [(polygon, deck_y)]"""
    out = []
    candidates = network.under_tree.query(shapely.box(*land.bounds))
    shapely.prepare(land)
    wet_lines = ~shapely.covers(land, network.under_lines[candidates])
    for k in candidates[wet_lines]:
        line = network.under_lines[k]
        local = bridges.local_land(land, line)
        for piece in lines_of(shapely.difference(line, local)):
            if not MIN_CROSSING <= piece.length <= MAX_CROSSING:
                continue
            ends = shapely.get_coordinates(piece)[[0, -1]]
            if not shapely.dwithin(local, shapely.points(ends), 2.0).all():
                continue  # runs out into the water (the city's edge)
            # The banks must be different pieces of land nearby: a street that
            # dips past the city's edge and comes back starts and ends on one.
            around = shapely.intersection(local, shapely.buffer(piece, 40.0))
            banks = [p for p in polygons_of(around, 1.0) if shapely.dwithin(p, shapely.points(ends), 2.0).any()]
            if len(banks) < 2:
                continue
            if shapely.length(shapely.intersection(piece, shapely.buffer(covered, 3.0))) > 0.5 * piece.length:
                continue
            direction = (ends[1] - ends[0]) / max(np.linalg.norm(ends[1] - ends[0]), 1e-6)
            span = shapely.LineString([ends[0] - direction * 4.0, ends[1] + direction * 4.0])
            half = float(network.under_half[k]) + 0.5
            poly = shapely.difference(shapely.buffer(span, half, cap_style="flat"), covered)
            poly = max(polygons_of(poly, 20.0), key=lambda p: p.area, default=None)
            if poly is None:
                continue
            banks = network.street(np.vstack([ends[0] - direction * 3.0, ends[1] + direction * 3.0]))
            length = float(np.linalg.norm(ends[1] - ends[0]))

            def deck_y(en, a=ends[0], d=direction, banks=banks, length=length):
                t = np.clip(((np.asarray(en, np.float64).reshape(-1, 2) - a) @ d) / max(length, 1e-6), 0.0, 1.0)
                return banks[0] + (banks[1] - banks[0]) * t + CROSSING_LIFT
            out.append((shapely.orient_polygons(poly), deck_y))
    return out


def _plain_profile(poly, network: Network):
    """Heights for an outline no raised road runs through: from the ground at
    its two ends (along its long axis), lifted LEVEL_RISE over streets that
    pass under it. Returns (deck_y, carries a street) or (None, False) if it
    wouldn't rise MIN_RISE above the street anywhere."""
    u, v, center, length = _axis(poly)
    ring = np.asarray(shapely.segmentize(poly.exterior, 2.0).coords)[:, :2]
    s = (ring - center) @ u
    s_min, s_max = float(s.min()), float(s.max())
    strip = min(END_STRIP, 0.2 * (s_max - s_min))
    ends = (float(np.median(network.street(ring[s <= s_min + strip]))),
            float(np.median(network.street(ring[s >= s_max - strip]))))

    # Streets on it (running along it) and under it (crossing it).
    lifts = []
    carries = False
    for k in network.under_tree.query(poly, predicate="intersects"):
        line = network.under_lines[k]
        inside = shapely.intersection(line, poly)
        if inside.is_empty or inside.length < 1.0:
            continue
        coords = shapely.get_coordinates(inside)
        direction = coords[-1] - coords[0]
        sine = abs(direction @ v) / max(np.linalg.norm(direction), 1e-6)
        if sine < CROSSING_SINE:
            if inside.length >= min(MIN_INSIDE, 0.4 * line.length):
                carries = True
            continue
        middle = shapely.get_coordinates(shapely.line_interpolate_point(inside, 0.5, normalized=True))[0]
        at = float((middle - center) @ u)
        if s_min + strip < at < s_max - strip:
            lifts.append((at, float(network.street(middle[None])[0]) + LEVEL_RISE, float(network.under_half[k])))
    if carries:
        lifts = []  # a street on it can't also cross under it: the data disagrees

    def deck_y(en):
        en = np.asarray(en, np.float64).reshape(-1, 2)
        at = (en - center) @ u
        t = np.clip((at - s_min) / max(s_max - s_min, 1e-6), 0.0, 1.0)
        y = ends[0] + (ends[1] - ends[0]) * t
        for s_c, top, half in lifts:
            y = np.maximum(y, top - np.maximum(np.abs(at - s_c) - half, 0.0) * RAMP_GRADE)
        return np.maximum(y, network.street(en))

    probe = shapely.get_coordinates(shapely.segmentize(poly, 4.0))
    inner = probe if len(probe) else ring
    grid = _grid_points(poly, 4.0)
    if len(grid):
        inner = np.vstack([inner, grid])
    if (deck_y(inner) - network.street(inner)).max() < MIN_RISE:
        return None, False
    return deck_y, carries


def _grid_points(poly, step: float) -> np.ndarray:
    min_e, min_n, max_e, max_n = poly.bounds
    e, n = np.meshgrid(np.arange(min_e, max_e, step), np.arange(min_n, max_n, step))
    pts = np.column_stack([e.ravel(), n.ravel()])
    return pts[shapely.contains_xy(poly, pts[:, 0], pts[:, 1])] if len(pts) else pts


def _axis(geom):
    """Direction (unit vector along the long side of its minimum rotated
    rectangle), perpendicular, center, and length of a shape."""
    rect = np.asarray(shapely.minimum_rotated_rectangle(geom).exterior.coords)[:4]
    sides = rect[1:] - rect[:-1]
    longest = int(np.argmax(np.hypot(sides[:, 0], sides[:, 1])))
    length = float(np.hypot(*sides[longest]))
    u = sides[longest] / max(length, 1e-6)
    return u, np.array([-u[1], u[0]]), rect.mean(axis=0), length


def _clear_of_streets(points: np.ndarray, network: Network) -> np.ndarray:
    """Which column spots are off the traffic lanes of the street-level roads
    passing underneath (a two-way street's middle is fine: a median)."""
    ok = np.ones(len(points), dtype=bool)
    if len(points) == 0:
        return ok
    hits = network.under_tree.query(shapely.points(points), predicate="dwithin", distance=MAX_WIDTH / 2 + 1.0)
    if len(hits[0]):
        gap = shapely.distance(network.under_lines[hits[1]], shapely.points(points[hits[0]]))
        in_lanes = (gap < network.under_half[hits[1]] + 0.5) & ~(network.under_two_way[hits[1]] & (gap < MEDIAN))
        ok[hits[0][in_lanes]] = False
    return ok


def _add_road_columns(poly, segments, deck_y, network: Network, builders: dict) -> None:
    """Bents every COLUMN_SPACING under the raised roads of a deck, where it's
    high enough: a cap beam across the road on one or two columns, which keep
    off the lanes of streets underneath (standing in their medians, or beside
    them)."""
    for k in segments:
        line = network.lines[k]
        if line.length < COLUMN_SPACING * 0.5:
            continue
        s = np.arange(COLUMN_SPACING * 0.5, line.length, COLUMN_SPACING)
        points, normal = markings._frame(line, s)
        width = float(network.width[k])
        half = width / 2
        for point, across in zip(points, normal):
            top = float(deck_y(point[None])[0]) - DECK_THICKNESS
            ground = float(network.street(point[None])[0])
            if top - ground < COLUMN_CLEARANCE + CAP_DEPTH:
                continue
            # Where columns could go across the road, best first: a pair under
            # a wide road, the middles of two-way streets running underneath,
            # the middle, then near the edges.
            options = [0.0, -(half - 2.0), half - 2.0, -half / 2, half / 2]
            for m in _medians_under(point, across, half, network):
                options.insert(0, m)
            spots = point + np.outer(options, across)
            ok = shapely.covers(poly, shapely.points(spots)) & _clear_of_streets(spots, network)
            pair = width >= WIDE_DECK and ok[3] and ok[4]
            chosen = [3, 4] if pair else []
            for i in np.flatnonzero(ok):
                if len(chosen) >= (2 if width >= WIDE_DECK else 1):
                    break
                if all(abs(options[i] - options[j]) >= 4.0 for j in chosen):
                    chosen.append(int(i))
            if not chosen:
                continue
            tangent = np.array([across[1], -across[0]])
            for i in chosen:
                spot = spots[i]
                _add_box(spot, tangent, COLUMN_SIZE[0], COLUMN_SIZE[1],
                         _footing(spot, float(network.street(spot[None])[0]), network), top - CAP_DEPTH, builders)
            _add_box(point, tangent, COLUMN_SIZE[0] + 0.1, max(min(half - 0.5, 9.0), COLUMN_SIZE[1]),
                     top - CAP_DEPTH, top, builders)


def _medians_under(point: np.ndarray, across: np.ndarray, half: float, network: Network) -> list:
    """Offsets across a raised road (from `point`, along `across`) where the
    middles of two-way streets running underneath it are."""
    reach = shapely.LineString([point - across * half, point + across * half])
    out = []
    for k in network.under_tree.query(reach, predicate="intersects"):
        if not network.under_two_way[k]:
            continue
        hit = shapely.intersection(reach, network.under_lines[k])
        for p in shapely.get_coordinates(hit):
            out.append(float((p - point) @ across))
    return out


def _add_axis_columns(poly, deck_y, network: Network, builders: dict) -> None:
    """Columns every COLUMN_SPACING along an outline's long axis (for decks
    without a road of their own to follow)."""
    u, v, center, length = _axis(poly)
    ring = np.asarray(poly.exterior.coords)[:, :2]
    s = (ring - center) @ u
    width = float(np.clip(poly.area / max(length, 1.0), 4.0, 60.0))
    offsets = (0.0,) if width < WIDE_DECK else (-width * 0.25, width * 0.25)
    stations = np.arange(s.min() + COLUMN_SPACING * 0.5, s.max() - 4.0, COLUMN_SPACING)
    for offset in offsets:
        spots = center + np.outer(stations, u) + v * offset
        if len(spots) == 0:
            continue
        ok = shapely.covers(poly, shapely.points(spots)) & _clear_of_streets(spots, network)
        for spot in spots[ok]:
            top = float(deck_y(spot[None])[0]) - DECK_THICKNESS
            ground = float(network.street(spot[None])[0])
            if top - ground < COLUMN_CLEARANCE:
                continue
            _add_box(spot, v, COLUMN_SIZE[1], COLUMN_SIZE[0], _footing(spot, ground, network), top, builders)


def _footing(spot: np.ndarray, ground: float, network: Network) -> float:
    """Where a column starts: a meter into the ground, or down in the water."""
    return ground - 1.0 if shapely.contains_xy(network.land, spot[0], spot[1]) else WATER_FOOTING_Y


def _over_land(polys: list, land, wet_outlines) -> list:
    """Deck pieces, over water only where a viaduct's outline says so or
    across a creek (not sticking out into a river or the sea)."""
    out = []
    for poly in polys:
        local = bridges.local_land(land, poly)
        wet = [p for p in polygons_of(shapely.difference(poly, local), 1.0)
               if not _crossing(p, land) and shapely.area(shapely.intersection(p, wet_outlines)) < 0.5 * p.area]
        if wet:
            poly = shapely.difference(poly, shapely.union_all(wet))
        out.extend(polygons_of(poly, 20.0))
    return out


def _crossing(piece, land) -> bool:
    """Whether a piece of deck over water reaches land on two sides (a creek
    crossing) rather than sticking out into the water."""
    local = bridges.local_land(land, piece)
    contact = shapely.intersection(piece.boundary, shapely.buffer(local, 1.0))
    lines = [line for line in lines_of(contact) if line.length >= 2.0]
    if len(lines) < 2:
        return False
    return len(polygons_of(shapely.union_all([shapely.buffer(line, 15.0) for line in lines]))) >= 2


def _add_box(base_en, u, half_u, half_v, y0, y1, builders) -> None:
    """A box standing on (east, north) `base_en`, turned to `u`, from y0 to y1
    (no bottom face), in the detailed levels."""
    v = np.array([-u[1], u[0]])
    corners = [base_en + u * su * half_u + v * sv * half_v for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    ring = np.array(corners + [corners[0]])
    for level in DETAILED:
        if level in builders:
            builders[level].add_walls(ring, y0, y1, (STRUCTURE_CONCRETE, 0.0))
            builders[level].add_flat([shapely.Polygon(corners)], y1, (STRUCTURE_CONCRETE, 0.0))


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


def _merge(target: dict, extra: dict) -> None:
    for key, arrays in extra.items():
        if key in target:
            target[key] = tuple(np.concatenate([a, b]) for a, b in zip(target[key], arrays))
        else:
            target[key] = arrays


def _merge_lamps(target: dict, found: list, size: float) -> None:
    en = np.concatenate([f[0] for f in found])
    y = np.concatenate([f[1] for f in found])
    arms = np.concatenate([f[2] for f in found])
    ii = np.floor(en[:, 0] / size).astype(np.int64)
    jj = np.floor(-en[:, 1] / size).astype(np.int64)
    for key in set(zip(ii.tolist(), jj.tolist())):
        mask = (ii == key[0]) & (jj == key[1])
        extra = (en[mask], y[mask], arms[mask])
        if key in target:
            target[key] = tuple(np.concatenate([a, b]) for a, b in zip(target[key], extra))
        else:
            target[key] = extra


# Per near tile: driving lanes and paint on decks.

class DeckSurface:
    """Road decks' tops (bridges and overpasses) around one near tile, from
    the bridge buckets: the deck height under points, picking the deck nearest
    an expected height where decks cross."""

    def __init__(self, buckets: dict, i: int, j: int, kinds=(GROUND_ROAD,), tris=None):
        if tris is None:
            tris = []
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    found = buckets.get((i + di, j + dj))
                    if found is None:
                        continue
                    pos, _, uv2, front = found
                    top = np.isin(uv2[:, 0, 0], kinds) & (front[:, 1] > 0.9)
                    tris.append(pos[top])
        self.tris = np.concatenate(tris) if len(tris) else np.zeros((0, 3, 3))
        flat = self.tris[:, :, [0, 2]] * np.array([1.0, -1.0])  # east, north
        self.flat = flat
        self.tree = shapely.STRtree(shapely.polygons(np.concatenate([flat, flat[:, :1]], axis=1))) if len(flat) else None

    def interpolate(self, p: np.ndarray, tri: np.ndarray) -> np.ndarray:
        """Heights of triangles `tri` at (N, 2) points inside them."""
        a, b, c = self.flat[tri, 0], self.flat[tri, 1], self.flat[tri, 2]
        v0, v1, v2 = b - a, c - a, p - a
        d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
        d20, d21 = (v2 * v0).sum(1), (v2 * v1).sum(1)
        denom = np.where(np.abs(d00 * d11 - d01 * d01) > 1e-12, d00 * d11 - d01 * d01, 1e-12)
        w1 = (d11 * d20 - d01 * d21) / denom
        w2 = (d00 * d21 - d01 * d20) / denom
        return self.tris[tri, 0, 1] * (1 - w1 - w2) + self.tris[tri, 1, 1] * w1 + self.tris[tri, 2, 1] * w2

    def height(self, en: np.ndarray, expected: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """(heights, found) at (N, 2) points: the deck top nearest `expected`
        (N,) where a deck is there."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.array(expected, np.float64, copy=True)
        found = np.zeros(len(en), dtype=bool)
        if self.tree is None or len(en) == 0:
            return out, found
        hits = self.tree.query(shapely.points(en), predicate="intersects")
        if len(hits[0]) == 0:
            return out, found
        point, tri = hits
        y = self.interpolate(en[point], tri)
        miss = np.abs(y - expected[point])
        order = np.lexsort((miss, point))
        first = np.ones(len(order), dtype=bool)
        first[1:] = point[order][1:] != point[order][:-1]
        chosen = order[first]
        out[point[chosen]] = y[chosen]
        found[point[chosen]] = True
        return out, found


class OnDecks:
    """The near tiles' ground (a terrain.Lattice) as things on the street see
    it: on decks that carry a street over a dip (a rail cut, a sunken
    highway), the deck (plus the curb, so the street is on the deck); the
    ground elsewhere. Street paint, driving and walking lanes and props stand
    on this; the ground's own mesh uses the bare lattice (bare())."""

    def __init__(self, ground, street_decks: list):
        self.bare = ground
        self.decks = DeckSurface({}, 0, 0, tris=street_decks)

    def height(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        h = self.bare.height(en)
        if self.decks.tree is None or len(en) == 0:
            return h
        y, found = self.decks.height(en, h - CURB_HEIGHT)
        return np.where(found, np.maximum(h, y + CURB_HEIGHT), h)

    def __getattr__(self, name):
        return getattr(self.bare, name)


def bare(ground):
    """The ground lattice under an OnDecks (or the lattice itself)."""
    return getattr(ground, "bare", ground)


def surface_for(buckets: dict, bounds, kinds=(GROUND_ROAD,)) -> DeckSurface:
    """The deck tops around a near tile (bounds, a box), from the lod0 bridge buckets."""
    min_e, min_n, max_e, max_n = bounds.bounds
    size = max_e - min_e
    return DeckSurface(buckets, int(round(min_e / size)), int(round(-max_n / size)), kinds)


def clear_of_decks(buckets: dict, bounds, en: np.ndarray, base: np.ndarray, height: np.ndarray) -> np.ndarray:
    """Which props (standing at (N, 2) points, from heights `base`, `height`
    tall) don't reach up into a deck or bridge overhead."""
    keep = np.ones(len(en), dtype=bool)
    surface = surface_for(buckets, bounds, (GROUND_ROAD, STRUCTURE_CONCRETE))
    if surface.tree is None or len(en) == 0:
        return keep
    hits = surface.tree.query(shapely.points(en), predicate="intersects")
    if len(hits[0]) == 0:
        return keep
    point, tri = hits
    y = surface.interpolate(en[point], tri)
    underside = y - DECK_THICKNESS
    blocked = (underside > base[point] + 0.3) & (underside < base[point] + height[point])
    keep[point[blocked]] = False
    return keep


def road_height(network: Network, surface: DeckSurface, k: int, en: np.ndarray, land) -> tuple[np.ndarray, np.ndarray]:
    """Segment k's road height at (N, 2) points and whether it's on a deck
    there: the deck under them nearest the road's own height, else the road's
    own height (Network.along). Street-level roads on land (except bridges,
    which their decks carry) only take decks within GRADE_DECK of the street,
    not one passing overhead."""
    expected = network.along(k, en)
    y, found = surface.height(en, expected)
    if not network.raised[k] and network.data["rw"][k] != BRIDGE and found.any():
        on_land = shapely.contains_xy(land, en[:, 0], en[:, 1])
        overhead = found & on_land & (np.abs(y - expected) > GRADE_DECK)
        y[overhead], found[overhead] = expected[overhead], False
    return y, found


def lanes(network: Network, buckets: dict, bounds, land) -> list:
    """Driving lanes (traffic.lanes' format) of the raised roads, ramps and
    bridges whose middle is in `bounds` (a near tile's box), at their deck's
    height (from the lod0 bridge buckets); lanes over water with no deck under
    them (bridges left out of the world) are dropped."""
    surface = surface_for(buckets, bounds)
    out = []
    attrs = network.attrs
    for k in network.tree.query(bounds, predicate="intersects"):
        k = int(k)
        if network.data["rw"][k] == PATH:
            continue

        def height(en, k=k):
            return road_height(network, surface, k, en, land)[0]
        for lane, info in traffic.lanes(attrs, np.array([k]), bounds, height):
            _, found = road_height(network, surface, k, lane[:, :2], land)
            wet = ~shapely.contains_xy(land, lane[:, 0], lane[:, 1])
            if (wet & ~found).any():
                continue
            out.append((lane, info))
    return out


def add_paint(builder: MeshBuilder, network: Network, buckets: dict, bounds, cell: float, land) -> None:
    """Adds the paint on decks around a near tile (bounds) to its markings
    mesh: lane lines and edge lines of the roads on them (markings.quads),
    kept where all their corners are on a deck, draped over the decks
    (MARKING_LIFT above them) along a `cell`-meter grid like the streets'
    paint."""
    surface = surface_for(buckets, bounds)
    if surface.tree is None:
        return
    halves = [[0, 1, 2], [0, 2, 3]]
    for k in network.tree.query(shapely.buffer(bounds, 30.0, join_style="mitre"), predicate="intersects"):
        k = int(k)
        if network.data["rw"][k] == PATH:
            continue

        def height(en, k=k):
            return road_height(network, surface, k, en, land)[0] + MARKING_LIFT
        for kind, (quads, uv, _) in markings.quads(network.attrs, np.array([k]), bounds.bounds, None).items():
            _, found = road_height(network, surface, k, quads.reshape(-1, 2), land)
            ok = found.reshape(-1, 4).all(axis=1)
            if ok.any():
                builder.add_draped_triangles(quads[ok][:, halves].reshape(-1, 3, 2), cell, height, (kind, 0.0),
                                             uv=uv[ok][:, halves].reshape(-1, 3, 2))
