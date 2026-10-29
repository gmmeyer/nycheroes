"""The Brooklyn-Queens Expressway's triple cantilever in Brooklyn Heights
(1948-54): the Staten Island-bound roadway on the lower deck, the
Queens-bound one on the middle deck and the Brooklyn Heights Promenade on top
(Remsen Street to Orange Street), each cantilevered west off a cellular
retaining wall cut into the Heights' bluff, and each set back about 5 m from
the one below. Furman Street runs along the foot, by the wall under the lower
deck (the "Great Wall of Furman"). South of the Promenade and north of it to
the Columbia Heights overpass the two roadways go on stacked; past that,
their ramps climb out of a trench toward the Brooklyn Bridge.

Sources: NYC DOT's BQE Central draft scope (2026, its section: 33'-6"
roadways, 37' decks), the BQE expert panel's report (2020: which way runs on
which level; Remsen to Orange Streets), NYC DOT's 2018 section (each level
set back about 15 feet; the lower roadway about 15 feet above Furman Street,
the middle 33, the Promenade 52), the federal bridge inventory (4.2 m clear
on both roadways), the city's 2017 lidar survey (the heights, below), photos
from Brooklyn Bridge Park (Wikimedia Commons: rust-colored fascias, pale
green pipe railings, the Promenade's brown picket fence over a rounded edge,
curved soffits, square-paneled walls).

The data: the roadways are street centerlines at levels 5 and 9 (below the
Heights' streets), the decks' outlines are planimetric bridge outlines, the
Promenade's path is a centerline (a path), and Furman Street's centerline
gives the level everything counts up from. The centerlines run along the
decks' west edges rather than their middles, so they're moved onto the decks
(Structure.realign; lanes follow them). The city's elevation model is bare
earth and blurs the bluff: it slopes over 40 m from Furman Street up to the
gardens behind the Promenade, right through where the decks stand. So the
ground is cut down under the structure (and along the trench past it) and,
behind it, filled up to its top (the Promenade, or the middle deck where
there's no Promenade), sloping back down to the model's ground further east;
walls close the cut's edges, and Columbia Heights bridges it (Ground).

prepare() makes data/cache/cantilever.pkl; Structure gives overpasses.Network
the roadways' heights and the ground; build() adds the decks to the bridge
buckets (with collision up close), and their walls, railings and the
Promenade's lamps; walks() the Promenade's walking lanes.
"""

import json

import numpy as np
import shapely
import shapely.ops
from shapely.geometry import shape

import markings
import overpasses
from common import (CURB_HEIGHT, FEET, GROUND_PARK, GROUND_PAVERS, GROUND_ROAD, RAW_DIR, STRUCTURE_CONCRETE,
                    STRUCTURE_STEEL, MeshBuilder, lines_of, load_features, polygons_of, project)
from common import segmentize_polygon
from markings import AT_GRADE, BOTH

# Atlantic Avenue to Old Fulton Street (west, south, east, north).
AREA = (-74.0010, 40.6900, -73.9925, 40.7030)
LOWER, MIDDLE = 5, 9  # the roadways' level codes
ROAD_TYPES = (1, 2, 3, 9)  # streets, highways, bridges, ramps
PROMENADE_NAME = "BROOKLYN HEIGHTS PROMENADE"
FURMAN_NAME = "FURMAN ST"
# A segment below street level is one of the roadways if at least this much
# of it lies in the bridge outlines (and so are the ones it leads on to below
# street level).
INSIDE_SHARE = 0.5
MIN_DECK_RUN = 100.0  # meters of roadway in an outline that make it a deck

# The decks' tops above Furman Street (m), as the city's 2017 lidar survey
# has them (NOAA's copy; the 2018 section says 15, 33 and 52 feet): 3.7 m
# above sea level on Furman Street at Montague Street, 8.8 on the lower
# roadway, 14.3 on the middle one and 19.7 on the Promenade; the gardens
# behind it are 2.2 m lower.
LOWER_TOP = 5.1
MIDDLE_TOP = 10.6
PROMENADE_TOP = 16.0
GARDENS = 2.2
# Furman Street's height along the structure: the median of the street's
# heights within this far (m) of each point along it.
FURMAN_WINDOW = 75.0
FURMAN_STEP = 10.0
# The Promenade: this far either side of its path (rounded ends, as built);
# planted along its back this wide.
PROMENADE_HALF = 5.0
PLANTING = 2.5
# Where the Promenade's height blends into the middle deck's beyond its ends
# (for the ground behind; m).
TOP_BLEND = 30.0
# The slabs: this deep at their tip, curving down (soffits) to this deep where
# they meet the wall they hang from.
DECK_TIP = 0.6
DECK_ROOT = 1.6
EDGE_BEAM = 1.0       # the lower deck's edge beam over Furman Street
OVER_DEPTH = 2.0      # the bridges over it
RAILING = 1.1         # pipe railings and the Promenade's fence
RAILS = (0.55, 1.1)   # the railings' pipes, this high
RAIL_DEPTH = 0.12
POST_SPACING = 5.0    # and their posts, this far apart (up close)
POST_HALF = 0.06
PARAPET = 1.1         # where a deck's back has nothing above it
WALL_FOOT = 1.0       # walls reach this far into the ground
# The ground behind (east of) the structure: up to GARDENS below its top for
# FILL_FLAT m, then down at FILL_SLOPE to the elevation model's ground,
# within FILL_REACH.
FILL_FLAT = 25.0
FILL_SLOPE = 0.5
FILL_REACH = 60.0
FILL_STREET_BLEND = 15.0  # it fades out this close to streets passing under the structure
# The cut floor under the structure, this far below the lower deck's base.
FLOOR_DROP = 1.0
# The trench past the north end: along the ramps there until they're
# TRENCH_MARGIN above the ground (taking them to climb RAMP_CLIMB), its floor
# TRENCH_FLOOR under them.
RAMP_CLIMB = 0.04
TRENCH_MARGIN = 0.5
TRENCH_FLOOR = 1.0
TRENCH_STEP = 5.0
# Lanes moved onto the decks fade back onto their centerline over this
# distance from the decks' outlines (m), and toward ends shared with roads
# that aren't moved.
REALIGN_BLEND = 25.0
REALIGN_REACH = 3.0   # lines this close to a deck are on it
REALIGN_TOLERANCE = 0.05  # and the moved lines' points this close to straight are left out
# Streets bridging over the structure (Columbia Heights, lidar): this high
# over the middle roadway (4.2 m clear, then the bridge), across the cut and
# BRIDGE_REACH past it; the ground climbs to their ends at LANDING_SLOPE,
# within LANDING_REACH.
OVER_CLEAR = 7.0
BRIDGE_REACH = 3.0
LANDING_SLOPE = 0.15
LANDING_REACH = 50.0
# Past their outlines the decks are the roadways' own width, from this far
# before the outline's north end (it tapers).
STRIP_OVERLAP = 15.0
# Road ends below street level this close to the structure are on it (m).
CARRY_REACH = 20.0
# Heights are kept along the lower roadway and this far past its ends (m).
AXIS_REACH = 150.0
# Streets crossing under the decks (at least this long under them, and at
# most this much along the structure: the cosine of the angle between them)
# get CROSSING_CLEAR from their lowest point under them to the lower roadway
# (4.2 m clear under the deck), the decks climbing to it at CROSSING_CLIMB; a
# corridor their width wide, and a sidewalk either side, is open under them.
CROSSING_MIN = 8.0
CROSSING_ALONG = 0.7
CROSSING_CLEAR = 5.4
CROSSING_CLIMB = 0.05
SIDEWALK = 2.0
DEFAULT_HALF = 5.0
# Edges of a deck facing this much across the structure (cosine) are its front
# or back; the rest are its ends.
EDGE_FACING = 0.6
DECK_SPACING = overpasses.DECK_SPACING
DETAILED = overpasses.DETAILED
NEAR = ("lod0",)  # railings only up close
LAMP_SPACING = 30.0   # the Promenade's lamps, along its railing
LAMP_INSET = 1.2
WALK_OFFSET = 2.5     # a walking lane this far from the Promenade's path, toward its railing

# How it's painted (the landmark bridges' structure kinds and uv2.y: palette +
# 8 * flags, see bridge_landmarks): concrete walls; rust-colored fascias
# (palette 3's concrete); pipe railings in the els' green-gray steel; the
# Promenade's fence drawn as open steel (lattice) in rust brown.
WALL = (STRUCTURE_CONCRETE, 0.0)
FASCIA = (STRUCTURE_CONCRETE, 3.0)
RAILING_STEEL = (STRUCTURE_STEEL, 0.0)
FENCE_STEEL = (STRUCTURE_STEEL, 11.0)
ROAD_TOP = (GROUND_ROAD, 0.0)
PLANTED = (GROUND_PARK, 0.0)


def prepare() -> dict:
    """The roadways (overpasses.prepare's format, the segments below street
    level in the area that run through its bridge outlines and those they lead
    on to), the deck outlines (which level each), the Promenade's path and
    Furman Street."""
    area = project(shapely.box(*AREA))
    with open(RAW_DIR / "centerline_names.json", encoding="utf-8") as f:
        names = {str(row.get("physicalid")): " ".join(str(row.get("full_street_name") or "").split())
                 for row in json.load(f)}
    lines, rows, promenade, furman = [], [], [], []
    for feat in load_features("centerline"):
        p = feat["properties"]
        if p.get("status", "2") != "2":
            continue
        geom = project(shape(feat["geometry"]))
        if not shapely.intersects(area, geom):
            continue
        name = names.get(str(p.get("physicalid")), "")
        if name == PROMENADE_NAME:
            promenade.append(geom)
        elif name == FURMAN_NAME:
            furman.append(geom)
        rw = int(p.get("rw_type") or 0)
        levels = (int(p.get("from_level_code") or AT_GRADE), int(p.get("to_level_code") or AT_GRADE))
        if rw not in ROAD_TYPES or max(levels) >= int(AT_GRADE):
            continue
        trafdir = {"FT": markings.WITH, "TF": markings.AGAINST, "TW": BOTH}.get(p.get("trafdir"), BOTH)
        for part in shapely.get_parts(shapely.line_merge(geom)):
            lines.append(part)
            rows.append((rw, trafdir, int(float(p.get("number_travel_lanes") or 0)),
                         int(float(p.get("number_park_lanes") or 0)), float(p.get("streetwidth") or 0) * FEET,
                         levels[0], levels[1]))
    lines = np.array(lines, dtype=object)
    attrs = np.array(rows, dtype=np.float64).reshape(-1, 7)

    outlines = [project(shape(f["geometry"])) for f in load_features("transport_structures")
                if str(f["properties"].get("feat_code")) == overpasses.BRIDGE_CODE]
    outlines = [o for o in shapely.make_valid(np.array(outlines, dtype=object)) if shapely.intersects(area, o)]
    inside = shapely.length(shapely.intersection(lines, shapely.union_all(outlines))) >= \
        INSIDE_SHARE * shapely.length(lines)
    # ... and the segments below street level they lead on to.
    keep = inside.copy()
    ends = np.vstack([shapely.get_coordinates(shapely.get_point(lines, 0)),
                      shapely.get_coordinates(shapely.get_point(lines, -1))])
    keys = [tuple(k) for k in np.round(ends * 2.0).astype(np.int64).tolist()]
    count = len(lines)
    grown = True
    while grown:
        reached = {keys[e] for e in range(2 * count) if keep[e % count]}
        more = np.array([keys[k] in reached or keys[k + count] in reached for k in range(count)]) & ~keep
        grown = bool(more.any())
        keep |= more
    # Ramps and bridges are overpasses.prepare's already.
    keep &= np.isin(attrs[:, 0], (markings.STREET, markings.HIGHWAY))
    lines, attrs = lines[keep], attrs[keep]

    # The decks' outlines (those the roadways run through for a while), and
    # which level each is: the lower deck is the westernmost.
    axis = _axis_line(lines[np.minimum(attrs[:, 5], attrs[:, 6]) == LOWER])
    used = [o for o in outlines if shapely.length(shapely.intersection(lines, o)).sum() >= MIN_DECK_RUN]
    offsets = np.array([_place(axis, shapely.get_coordinates(shapely.point_on_surface(o)))[1][0] for o in used])
    middle = offsets > (offsets.min() + offsets.max()) / 2.0 if len(offsets) else np.zeros(0, dtype=bool)
    return {
        "lines": lines,
        "rw": attrs[:, 0].astype(np.int8),
        "trafdir": attrs[:, 1].astype(np.int8),
        "lanes": attrs[:, 2].astype(np.int16),
        "parking": attrs[:, 3].astype(np.int16),
        "width": attrs[:, 4].astype(np.float32),
        "levels": attrs[:, 5:7].astype(np.int8),
        "decks": {LOWER: shapely.union_all([o for o, m in zip(used, middle) if not m]),
                  MIDDLE: shapely.union_all([o for o, m in zip(used, middle) if m])},
        "promenade": shapely.line_merge(shapely.union_all(promenade)),
        "furman": shapely.line_merge(shapely.union_all(furman)),
    }


def _axis_line(lines):
    """The lower roadway's centerlines as one line, south to north."""
    merged = shapely.line_merge(shapely.union_all(lines))
    line = max(lines_of(merged), key=lambda l: l.length)
    coords = np.asarray(line.coords)
    return shapely.LineString(coords if coords[0, 1] <= coords[-1, 1] else coords[::-1])


def _place(axis, en: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """(N, 2) points as (distance along the axis, offset east of it)."""
    en = np.asarray(en, np.float64).reshape(-1, 2)
    s = shapely.line_locate_point(axis, shapely.points(en))
    a = shapely.get_coordinates(shapely.line_interpolate_point(axis, np.maximum(s - 1.0, 0.0)))
    b = shapely.get_coordinates(shapely.line_interpolate_point(axis, np.minimum(s + 1.0, axis.length)))
    t = (b - a) / np.maximum(np.linalg.norm(b - a, axis=1, keepdims=True), 1e-9)
    on = shapely.get_coordinates(shapely.line_interpolate_point(axis, s))
    d = en - on
    # East is right of the axis' travel (south to north).
    side = np.sign(t[:, 0] * d[:, 1] - t[:, 1] * d[:, 0])
    return s, -side * np.linalg.norm(d, axis=1)


class Structure:
    """The cantilever's shape and heights: its decks (east/north polygons),
    the levels' heights along it, and the ground around it (ground()).
    `streets` are the street centerlines (markings.prepare): the roadways
    clear the ones passing under them; `roads` overpasses.prepare's roads,
    where the street bridges over the structure are."""

    def __init__(self, data: dict, terrain, streets: dict, roads: dict):
        self.data = data
        levels = data["levels"].astype(np.int64)
        # Along the lower roadway, and on past its ends (the decks go on).
        line = _axis_line(data["lines"][levels.min(axis=1) == LOWER])
        coords = np.asarray(line.coords)
        ahead = [(coords[0] - coords[1]) / np.linalg.norm(coords[0] - coords[1]),
                 (coords[-1] - coords[-2]) / np.linalg.norm(coords[-1] - coords[-2])]
        self.axis = shapely.LineString(np.vstack([coords[0] + ahead[0] * AXIS_REACH, coords,
                                                  coords[-1] + ahead[1] * AXIS_REACH]))
        # Furman Street's surface along the structure.
        furman = data["furman"]
        points = np.vstack([shapely.get_coordinates(shapely.segmentize(line, FURMAN_STEP))
                            for line in lines_of(furman)])
        s, offset = _place(self.axis, points)
        near = np.abs(offset) < 30.0
        s, h = s[near], terrain.height(points[near]) - CURB_HEIGHT
        self.s = np.arange(0.0, self.axis.length + FURMAN_STEP, FURMAN_STEP)
        base = np.array([np.median(h[np.abs(s - x) <= FURMAN_WINDOW]) if (np.abs(s - x) <= FURMAN_WINDOW).any()
                         else np.nan for x in self.s])
        known = ~np.isnan(base)
        self.base = np.interp(self.s, self.s[known], base[known])

        # The decks: the outlines, and past them, the roadways' own width.
        lines = data["lines"]
        width = np.maximum(data["width"].astype(np.float64), 9.0) + 1.0
        decks = {}
        for level in (LOWER, MIDDLE):
            own = levels.min(axis=1) == level
            outline = data["decks"][level]
            strips = shapely.union_all(shapely.buffer(lines[own], width[own] / 2.0, cap_style="flat"))
            # Past the outline's north end and over its tapered last meters (the
            # roadways start at its south end).
            north = float(_place(self.axis, shapely.get_coordinates(outline))[0].max()) - STRIP_OVERLAP
            past = shapely.buffer(shapely.ops.substring(self.axis, north, self.axis.length), 60.0, cap_style="flat")
            beyond = shapely.intersection(strips, past)
            decks[level] = shapely.union_all([outline] + polygons_of(beyond, 20.0))
        self.decks = {level: shapely.orient_polygons(shapely.simplify(d, 0.2)) for level, d in decks.items()}
        # The Promenade: over the middle deck, back to the bluff.
        promenade = shapely.buffer(data["promenade"], PROMENADE_HALF, quad_segs=8)
        self.promenade = shapely.orient_polygons(shapely.simplify(promenade, 0.2))
        ps = shapely.line_locate_point(self.axis, shapely.points(shapely.get_coordinates(data["promenade"])))
        self.promenade_s = (float(ps.min()), float(ps.max()))
        roadways = shapely.union_all(list(self.decks.values()))
        shapely.prepare(roadways)
        self.on_deck_area = shapely.buffer(roadways, 2.0)
        shapely.prepare(self.on_deck_area)

        # Streets passing under the decks: the roadways clear them, and the
        # structure is open over them.
        self.lower = self.base + LOWER_TOP
        corridors, under_streets = [], []
        for k in shapely.STRtree(streets["lines"]).query(roadways, predicate="intersects"):
            street = streets["lines"][k]
            inside = shapely.intersection(street, roadways)
            if inside.length < CROSSING_MIN:
                continue
            ends = shapely.get_coordinates(inside)[[0, -1]]
            ends_s, _ = _place(self.axis, ends)
            along = abs(ends_s[1] - ends_s[0]) / max(float(np.linalg.norm(ends[1] - ends[0])), 1e-6)
            if along > CROSSING_ALONG:
                continue  # running along the structure (Furman Street)
            middle = shapely.get_coordinates(shapely.line_interpolate_point(inside, 0.5, normalized=True))
            at, _ = _place(self.axis, middle)
            half = (float(streets["width"][k]) / 2.0 if streets["width"][k] > 0 else DEFAULT_HALF) + SIDEWALK
            reach = half / max(np.sqrt(1.0 - min(along, 0.99) ** 2), 0.3)
            # From its lowest point under them (it climbs the bluff).
            under = float((terrain.height(shapely.get_coordinates(shapely.segmentize(inside, 2.0))).min()))
            climb = CROSSING_CLIMB * np.maximum(np.abs(self.s - at[0]) - reach, 0.0)
            need = under - CURB_HEIGHT + CROSSING_CLEAR - climb
            self.lower = np.maximum(self.lower, need)
            corridors.append(shapely.buffer(street, half, cap_style="flat"))
            under_streets.append(shapely.buffer(street, half))
        self.middle = np.maximum(self.base + MIDDLE_TOP, self.lower + (MIDDLE_TOP - LOWER_TOP))
        self.corridors = shapely.union_all(corridors) if corridors else shapely.Polygon()
        self.under_streets = shapely.union_all(under_streets) if under_streets else shapely.Polygon()

        self.footprint = shapely.union_all([*self.decks.values(), self.promenade])
        # The solid part, cut into the bluff: the footprint but for the streets
        # under it, and what's past them (the decks there stand on columns).
        pieces = polygons_of(shapely.difference(self.footprint, self.corridors), 1.0)
        self.solid = shapely.orient_polygons(max(pieces, key=lambda p: p.area))
        shapely.prepare(self.solid)
        # The middle of the structure across the axis, along it (what's east of
        # that is behind it).
        across = shapely.linestrings(np.stack([self._at(self.s, -80.0), self._at(self.s, 80.0)], axis=1))
        middle = np.full(len(self.s), np.nan)
        for i, piece in enumerate(shapely.intersection(across, self.footprint)):
            if not piece.is_empty:
                o = _place(self.axis, shapely.get_coordinates(piece))[1]
                middle[i] = (o.min() + o.max()) / 2.0
        known = ~np.isnan(middle)
        self.middle_offset = np.interp(self.s, self.s[known], middle[known])

        # Past the north end the ramps on from the roadways run in a trench
        # (under Columbia Heights and the Brooklyn Bridge's approach) until
        # they come up out of the ground.
        approach, self.trenches = [], []  # (the ramp from the structure on, its level's height there, area)
        for k in np.flatnonzero(np.isin(roads["levels"], (LOWER, MIDDLE)).any(axis=1)):
            line = roads["lines"][k]
            ends = shapely.get_coordinates(line)[[0, -1]]
            north = _place(self.axis, ends)[0] > self.axis.length / 2
            for i in (0, 1):
                level = int(roads["levels"][k][i])
                if level not in (LOWER, MIDDLE) or not north[i] or \
                        not shapely.dwithin(self.footprint, shapely.Point(ends[i]), CARRY_REACH):
                    continue
                ramp = line if i == 0 else shapely.LineString(np.asarray(line.coords)[::-1])
                s = np.arange(0.0, ramp.length, TRENCH_STEP)
                start = float(self.level(level, ends[i:i + 1])[0])
                road = start + RAMP_CLIMB * s
                ground = terrain.height(shapely.get_coordinates(shapely.line_interpolate_point(ramp, s))) - CURB_HEIGHT
                under = road < ground + TRENCH_MARGIN
                length = float(s[np.argmin(under)]) if not under.all() else ramp.length
                if length < TRENCH_STEP:
                    continue
                piece = shapely.ops.substring(ramp, 0.0, length)
                half = (float(roads["width"][k]) if roads["width"][k] > 0 else 2 * DEFAULT_HALF) / 2.0 + 1.0
                area = shapely.buffer(piece, half, cap_style="flat")
                approach.append(area)
                self.trenches.append((piece, start, area))
        self.approach = shapely.difference(shapely.union_all(approach), self.footprint) if approach \
            else shapely.Polygon()
        self.cut = shapely.union(self.solid, self.approach)
        shapely.prepare(self.approach)
        shapely.prepare(self.cut)
        self.taken = shapely.union(self.footprint, self.approach)
        shapely.prepare(self.taken)
        # Streets bridging over it (Columbia Heights): across the whole cut,
        # OVER_CLEAR over the middle roadway, the ground around their ends
        # brought up to them.
        self.bridges = []  # (the street over the cut, height, half width, deck)
        keys = set()
        street_tree = shapely.STRtree(streets["lines"])
        reach = shapely.buffer(self.cut, BRIDGE_REACH)
        street_level = (roads["levels"] == int(AT_GRADE)).all(axis=1) & (roads["rw"] == overpasses.BRIDGE)
        for k in np.flatnonzero(street_level):
            line = roads["lines"][k]
            if shapely.length(shapely.intersection(line, self.cut)) < CROSSING_MIN / 2:
                continue
            touching = streets["lines"][street_tree.query(line, predicate="dwithin", distance=1.0)]
            crossing = shapely.line_merge(shapely.union_all([line] + list(touching)))
            crossing = max(lines_of(shapely.intersection(crossing, reach)), key=lambda l: l.length)
            ends = shapely.get_coordinates(crossing)[[0, -1]]
            middle = shapely.get_coordinates(shapely.line_interpolate_point(crossing, 0.5, normalized=True))
            height = max(float(self.level(MIDDLE, middle)[0]) + OVER_CLEAR,
                         float((terrain.height(ends) - CURB_HEIGHT).max()))
            half = (float(roads["width"][k]) / 2.0 if roads["width"][k] > 0 else DEFAULT_HALF) + SIDEWALK
            self.bridges.append((crossing, height, half, shapely.buffer(crossing, half, cap_style="flat")))
            keys.add(tuple(np.round(shapely.get_coordinates(line)[[0, -1]] * 2.0).astype(np.int64).ravel()))
        self.bridge_keys = keys
        self.bridge_areas = shapely.union_all([area for *_, area in self.bridges]) if self.bridges \
            else shapely.Polygon()
        shapely.prepare(self.bridge_areas)
        self.landings = shapely.union_all([shapely.buffer(line, LANDING_REACH) for line, *_ in self.bridges]) \
            if self.bridges else shapely.Polygon()
        # Where nothing stands but the structure.
        self.closed = shapely.difference(self.cut, shapely.union(self.promenade, self.bridge_areas))
        shapely.prepare(self.closed)
        self.reach = shapely.buffer(shapely.union_all([self.taken, self.landings]), FILL_REACH)
        shapely.prepare(self.reach)
        self.bounds = self.reach.bounds

    def _at(self, s: np.ndarray, offset: float) -> np.ndarray:
        """Points `offset` east of the axis at distances s along it."""
        a = shapely.get_coordinates(shapely.line_interpolate_point(self.axis, np.maximum(s - 1.0, 0.0)))
        b = shapely.get_coordinates(shapely.line_interpolate_point(self.axis, np.minimum(s + 1.0, self.axis.length)))
        t = (b - a) / np.maximum(np.linalg.norm(b - a, axis=1, keepdims=True), 1e-9)
        on = shapely.get_coordinates(shapely.line_interpolate_point(self.axis, s))
        return on + np.column_stack([t[:, 1], -t[:, 0]]) * offset

    # Heights.

    def furman(self, en: np.ndarray) -> np.ndarray:
        """Furman Street's surface level abreast of (N, 2) points."""
        s, _ = _place(self.axis, en)
        return np.interp(s, self.s, self.base)

    def level(self, level: int, en: np.ndarray) -> np.ndarray:
        """The road surface at level 5 or 9 at (N, 2) points."""
        s, _ = _place(self.axis, en)
        return np.interp(s, self.s, self.lower if level == LOWER else self.middle)

    def on_decks(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) points are on the roadways' decks."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.zeros(len(en), dtype=bool)
        near = self.near(en)
        if near.any():
            out[near] = shapely.contains_xy(self.on_deck_area, en[near, 0], en[near, 1])
        return out

    def top(self, en: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """The structure's top abreast of (N, 2) points: the Promenade along
        it (blending into the middle deck past its ends), else the middle
        deck; and how much of it is the Promenade's (0..1)."""
        s, _ = _place(self.axis, en)
        middle = np.interp(s, self.s, self.middle)
        promenade = np.interp(s, self.s, self.base) + PROMENADE_TOP
        beyond = np.maximum(self.promenade_s[0] - s, s - self.promenade_s[1])
        share = np.clip(1.0 - beyond / TOP_BLEND, 0.0, 1.0)
        return middle + (promenade - middle) * share, share

    def promenade_y(self, en: np.ndarray) -> np.ndarray:
        return self.furman(en) + PROMENADE_TOP

    def near(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) points are within reach of the structure's ground."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        min_e, min_n, max_e, max_n = self.bounds
        box = (en[:, 0] >= min_e) & (en[:, 0] <= max_e) & (en[:, 1] >= min_n) & (en[:, 1] <= max_n)
        out = np.zeros(len(en), dtype=bool)
        if box.any():
            out[box] = shapely.contains_xy(self.reach, en[box, 0], en[box, 1])
        return out

    def inside(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) points are in the ground cut away, not on the
        Promenade or a bridge over it (nothing stands there but the
        structure)."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.zeros(len(en), dtype=bool)
        near = self.near(en)
        if near.any():
            out[near] = shapely.contains_xy(self.closed, en[near, 0], en[near, 1])
        return out

    def floor(self, en: np.ndarray) -> np.ndarray:
        """The ground cut away: under the structure, and in the trench past
        its north end."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        under = self.furman(en) + CURB_HEIGHT - FLOOR_DROP
        trench = shapely.contains_xy(self.approach, en[:, 0], en[:, 1])
        if trench.any():
            points = shapely.points(en[trench])
            deepest = np.full(trench.sum(), np.inf)
            for ramp, start, area in self.trenches:
                inside = shapely.contains(area, points)
                road = start + RAMP_CLIMB * shapely.line_locate_point(ramp, points[inside])
                deepest[inside] = np.minimum(deepest[inside], road - TRENCH_FLOOR)
            under[trench] = np.where(np.isfinite(deepest), deepest, under[trench])
        return under

    def fill(self, en: np.ndarray, ground: np.ndarray) -> np.ndarray:
        """The ground behind the structure (east of it): GARDENS below its
        top, then down to the model's ground (`ground` at the points) further
        away; and up to the bridges over it around their ends."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.array(ground, np.float64, copy=True)
        near = self.near(en)
        if not near.any():
            return out
        idx = np.flatnonzero(near)
        pts = en[idx]
        outside = ~shapely.contains_xy(self.taken, pts[:, 0], pts[:, 1])
        s, offset = _place(self.axis, pts)
        east = outside & (offset > np.interp(s, self.s, self.middle_offset)) & (s > 1.0) & (s < self.axis.length - 1.0)
        if east.any():
            points = shapely.points(pts[east])
            d = shapely.distance(self.footprint, points)
            top, promenade = self.top(pts[east])
            raised = top + CURB_HEIGHT - GARDENS * promenade - np.maximum(d - FILL_FLAT, 0.0) * FILL_SLOPE
            # Not over the streets passing under it, which climb the bluff on their own.
            share = np.clip(shapely.distance(self.under_streets, points) / FILL_STREET_BLEND, 0.0, 1.0) \
                if not self.under_streets.is_empty else 1.0
            raised = out[idx[east]] + (raised - out[idx[east]]) * share
            out[idx[east]] = np.maximum(out[idx[east]], raised)
        for line, height, half, _ in self.bridges:
            d = shapely.distance(line, shapely.points(pts))
            landing = outside & (d < LANDING_REACH)
            raised = height + CURB_HEIGHT - LANDING_SLOPE * np.maximum(d - half, 0.0)
            out[idx[landing]] = np.maximum(out[idx[landing]], raised[landing])
        return out

    def bridge(self, line) -> bool:
        """Whether a road segment (east/north line) is a street bridging over
        the structure (its decks are build()'s)."""
        key = tuple(np.round(shapely.get_coordinates(line)[[0, -1]] * 2.0).astype(np.int64).ravel())
        return key in self.bridge_keys

    def ground(self, lattice) -> "Ground":
        return Ground(lattice, self)

    def carries(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) road ends below street level are on the structure."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        out = np.zeros(len(en), dtype=bool)
        near = self.near(en)
        if near.any():
            out[near] = shapely.dwithin(self.footprint, shapely.points(en[near]), CARRY_REACH)
        return out

    # The roadways' lines.

    def merged(self, data: dict, streets: dict) -> tuple[dict, np.ndarray]:
        """overpasses.prepare's data with the roadways added and the lines on
        the decks moved onto them (realign), and which segments are the
        roadways."""
        out = dict(data)
        for key in ("lines", "rw", "trafdir", "lanes", "parking", "width", "levels"):
            out[key] = np.concatenate([data[key], self.data[key]])
        stacked = np.arange(len(out["lines"])) >= len(data["lines"])
        levels = out["levels"].astype(np.int64)
        # Ends of roads that aren't moved stay put (and so do the moved roads'
        # ends meeting them there, at the same level).
        still = ~np.isin(levels, (LOWER, MIDDLE)).any(axis=1)
        fixed = set()
        for lines, ends_levels in ((out["lines"][still], levels[still]),
                                   (streets["lines"], np.full((len(streets["lines"]), 2), int(AT_GRADE)))):
            for i in (0, 1):
                coords = np.round(shapely.get_coordinates(shapely.get_point(lines, -i)) * 2.0).astype(np.int64)
                fixed |= {(x, y, int(level)) for (x, y), level in zip(coords.tolist(), ends_levels[:, i].tolist())}
        out["lines"] = self.realign(out["lines"], levels, fixed)
        return out, stacked

    def realign(self, lines: np.ndarray, levels: np.ndarray, fixed: set) -> np.ndarray:
        """Lines (east/north) moved onto the middle of their deck where they
        run on it: those with an end at level 5 onto the lower deck, at 9 onto
        the middle one. Ends in `fixed` ((x, y) to 0.5 m, and level) stay
        put, and the move fades out toward them and off the decks."""
        out = lines.copy()
        placed = {}  # where moved ends went, so the roads meeting there still meet
        # (The centerlines run along the decks' edges, a little off them in places.)
        reach = {level: shapely.buffer(deck, REALIGN_REACH) for level, deck in self.decks.items()}
        for k, (line, (l0, l1)) in enumerate(zip(lines, levels.tolist())):
            level = LOWER if LOWER in (l0, l1) else MIDDLE if MIDDLE in (l0, l1) else None
            if level is None or not shapely.intersects(reach[level], line):
                continue
            dense = shapely.segmentize(line, 5.0)
            coords = np.asarray(dense.coords)[:, :2]
            s = shapely.line_locate_point(dense, shapely.points(coords))
            points, normal = markings._frame(dense, s)
            shift = self._to_middle(self.decks[level], points, normal)
            # Fade out along the road toward where it leaves the deck, and
            # toward fixed ends.
            on = shapely.contains_xy(reach[level], points[:, 0], points[:, 1])
            off = s[~on]
            inside = np.min(np.abs(s[:, None] - off[None, :]), axis=1) if len(off) else np.full(len(s), np.inf)
            weight = np.clip(np.where(on, inside, 0.0) / REALIGN_BLEND, 0.0, 1.0)
            keys = [tuple(np.round(end * 2.0).astype(np.int64).tolist()) + (level_at,)
                    for end, level_at in ((coords[0], l0), (coords[-1], l1))]
            for key, along in zip(keys, (s, s[-1] - s)):
                if key in fixed:
                    weight = np.minimum(weight, np.clip(along / REALIGN_BLEND, 0.0, 1.0))
            moved = coords + normal * (shift * weight)[:, None]
            for key, i in zip(keys, (0, -1)):
                if key not in fixed:
                    moved[i] = placed.setdefault(key, moved[i].copy())
            out[k] = shapely.simplify(shapely.LineString(moved), REALIGN_TOLERANCE)
        return out

    @staticmethod
    def _to_middle(deck, points: np.ndarray, normal: np.ndarray) -> np.ndarray:
        """How far along `normal` (left of travel) each point is from the middle
        of the deck across it (0 where the deck isn't there)."""
        out = np.zeros(len(points))
        reach = 30.0
        cuts = shapely.linestrings(np.stack([points - normal * reach, points + normal * reach], axis=1))
        for i, piece in enumerate(shapely.intersection(cuts, deck)):
            spans = [shapely.get_coordinates(l) for l in lines_of(piece)]
            if not spans:
                continue
            # The span across the point, or the nearest.
            ts = [((c - points[i]) @ normal[i]) for c in spans]
            best = min(ts, key=lambda t: 0.0 if t.min() <= 0.0 <= t.max() else min(abs(t.min()), abs(t.max())))
            out[i] = (best.min() + best.max()) / 2.0
        return out


class Ground:
    """A ground lattice (terrain.Lattice) with the structure's ground in it:
    cut down to the floor under the structure (and in the trench past it),
    filled up behind it. regions() splits polygons for draping so the cut has
    a hard edge; walls() closes it."""

    def __init__(self, lattice, structure: Structure):
        self.lattice = lattice
        self.structure = structure
        self.cell = lattice.cell
        self.outside = _Outside(self)
        self.under = _Floor(self)

    def height(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        h = self.lattice.height(en)
        near = self.structure.near(en)
        if not near.any():
            return h
        pts = en[near]
        inside = shapely.contains_xy(self.structure.cut, pts[:, 0], pts[:, 1])
        sub = self.structure.fill(pts, h[near])
        if inside.any():
            sub[inside] = self.structure.floor(pts[inside])
            # Streets over it are on their bridges.
            for _, height, _, area in self.structure.bridges:
                over = inside & shapely.contains_xy(area, pts[:, 0], pts[:, 1])
                sub[over] = height + CURB_HEIGHT
        h[near] = sub
        return h

    def normal(self, en: np.ndarray) -> np.ndarray:
        return self.outside.normal(en)

    def walls(self, bounds) -> list:
        """[(coords, bottom, top)]: walls along the cut's edge in a tile
        (bounds, a box), from the floor to the ground outside where that's
        higher, facing out of the cut."""
        cut = self.structure.cut
        if not shapely.intersects(bounds, cut):
            return []
        out = []
        rings = [ring for part in polygons_of(cut, 1.0) for ring in (part.exterior, *part.interiors)]
        for line in lines_of(shapely.intersection(shapely.MultiLineString(rings), bounds)):
            coords = np.asarray(shapely.segmentize(line, self.cell / 2).coords)[:, :2]
            floor = self.structure.floor(coords)
            outside = self.outside.height(_outside(coords, 0.05))
            high = outside > floor + 0.2
            for start, stop in overpasses._runs(high[:-1] | high[1:]):
                out.append((coords[start:stop + 1], floor[start:stop + 1] - 0.5, outside[start:stop + 1]))
        return out

    def regions(self, polys: list) -> list:
        """[(terrain, polygons)]: the parts of `polys` under the structure, on
        the floor, and the rest."""
        if not polys:
            return []
        box = shapely.box(*self.structure.bounds)
        if not any(shapely.intersects(box, p) for p in polys):
            return [(self.outside, polys)]
        footprint = self.structure.cut
        under, rest = [], []
        for poly in polys:
            if not shapely.intersects(footprint, poly):
                rest.append(poly)
                continue
            under += polygons_of(shapely.intersection(poly, footprint), 0.01)
            rest += polygons_of(shapely.difference(poly, footprint), 0.01)
        return [(self.under, under), (self.outside, rest)]

    def __getattr__(self, name):
        return getattr(self.lattice, name)


class _Outside:
    """The ground outside the structure (filled up behind it)."""

    def __init__(self, ground: Ground):
        self.ground = ground
        self.cell = ground.cell

    def height(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        return self.ground.structure.fill(en, self.ground.lattice.height(en))

    def normal(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if not self.ground.structure.near(en).any():
            return self.ground.lattice.normal(en)
        d = self.cell
        offsets = np.array([[d, 0.0], [-d, 0.0], [0.0, d], [0.0, -d]])
        h = self.height((en[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(-1, 4)
        normal = np.column_stack([-(h[:, 0] - h[:, 1]) / (2 * d), np.ones(len(en)), (h[:, 2] - h[:, 3]) / (2 * d)])
        return normal / np.linalg.norm(normal, axis=1, keepdims=True)


class _Floor:
    """The ground cut away under the structure (hidden by it)."""

    def __init__(self, ground: Ground):
        self.ground = ground
        self.cell = ground.cell

    def height(self, en: np.ndarray) -> np.ndarray:
        return self.ground.structure.floor(en)

    def normal(self, en: np.ndarray) -> np.ndarray:
        return np.tile([0.0, 1.0, 0.0], (len(np.asarray(en).reshape(-1, 2)), 1))


# Building it.

def build(network, buckets: dict, level_sizes: dict) -> None:
    """Adds the structure to bridges.build's buckets (with collision up
    close): the roadways' decks, the walls under and behind them, the
    Promenade with its lamps, and the streets bridging over it; also its
    decks' tops to "overhead" (the roadbed under them) and the Promenade's and
    bridges' to "street_decks" (what stands on them, overpasses.OnDecks)."""
    structure = network.structure
    builders = {level: MeshBuilder() for level in level_sizes}
    tops = []
    chains = {level: _chain(network, level) for level in (LOWER, MIDDLE)}
    lower, middle = structure.decks[LOWER], structure.decks[MIDDLE]

    def lower_y(en):
        return network.field(en, chains[LOWER])

    def middle_y(en):
        return network.field(en, chains[MIDDLE])

    promenade_y = structure.promenade_y

    def ground(coords):
        """The ground just outside a deck's edge (to the right of coords'
        travel): the street, the fill behind, or the floor under the next deck."""
        return network.ground_lattice.height(_outside(coords, 1.0))
    edges = {LOWER: _Edges(structure, lower), MIDDLE: _Edges(structure, middle),
             "promenade": _Edges(structure, structure.promenade)}

    # Tops: the roadways, and the Promenade's pavers with a planted strip
    # along its back.
    tops.append(_add_top(lower, lower_y, ROAD_TOP, builders))
    tops.append(_add_top(middle, middle_y, ROAD_TOP, builders))
    planted = shapely.intersection(structure.promenade, shapely.buffer(edges["promenade"].lines(1), PLANTING))
    walk = shapely.difference(structure.promenade, planted)
    promenade_top = _add_top(walk, promenade_y, (GROUND_PAVERS, _angle(structure.axis)), builders)
    _add_top(planted, promenade_y, PLANTED, builders)
    tops.append(promenade_top)

    # Soffits: the middle deck over the lower roadway, the Promenade over the
    # middle one, curving down to the wall behind.
    solid = structure.solid
    _add_soffit(shapely.intersection(shapely.intersection(middle, lower), solid), middle_y,
                edges[MIDDLE].lines(-1), edges[LOWER].lines(1, solid=True), builders)
    _add_soffit(shapely.intersection(structure.promenade, middle), promenade_y,
                edges["promenade"].lines(-1, ends=True), edges[MIDDLE].lines(1, solid=True), builders)

    # The lower deck: over Furman Street, the wall under its edge beam; at
    # its back, the wall up to the middle deck.
    for coords, facing, inside in edges[LOWER].runs():
        y = lower_y(coords)
        if facing < 0:
            if inside:
                # Down to Furman Street, or where the ground beside it is
                # higher (in the cut at the north end), up to that.
                beside = ground(coords)
                _wall(builders, coords, np.minimum(beside - WALL_FOOT, y - EDGE_BEAM), np.maximum(beside, y - EDGE_BEAM),
                      WALL)
            _edge_beam(builders, coords, y, EDGE_BEAM)
        elif facing > 0 and inside:
            _wall(builders, coords[::-1], y[::-1] - 0.3, _back_top(coords, y, middle, middle_y, ground)[::-1], WALL)
        elif facing > 0:
            _edge_beam(builders, coords, y, DECK_TIP)
        else:
            top = np.maximum(y, ground(coords)) if inside else y
            _wall(builders, coords, structure.floor(coords) if inside else y - DECK_ROOT, top, WALL)
    # The middle deck: its edge, and its back up to the Promenade.
    for coords, facing, inside in edges[MIDDLE].runs():
        y = middle_y(coords)
        if facing < 0 or (facing > 0 and not inside):
            _edge_beam(builders, coords, y, DECK_TIP)
        elif facing > 0:
            _wall(builders, coords[::-1], y[::-1] - 0.3,
                  _back_top(coords, y, structure.promenade, promenade_y, ground)[::-1], WALL)
        else:
            over = shapely.contains_xy(lower, coords[:, 0], coords[:, 1])
            bottom = np.where(over, lower_y(coords), structure.floor(coords)) if inside else y - DECK_ROOT
            _wall(builders, coords, bottom, np.maximum(y, ground(coords)) if inside else y, WALL)
    # The Promenade: its rounded edge and fence over the roadways, the wall
    # down to the gardens behind.
    for coords, facing, inside in edges["promenade"].runs():
        y = promenade_y(coords)
        if facing > 0:
            _wall(builders, coords, ground(coords) - WALL_FOOT, y, WALL)
            _wall(builders, coords, y, y + RAILING, FENCE_STEEL, band=True, levels=NEAR)
        else:
            _edge_beam(builders, coords, y, DECK_TIP + 0.2, fence=True)

    # Over the streets passing under (Joralemon Street) and past them, the
    # decks stand on columns: undersides, and walls beside the streets.
    for deck, deck_y, level, under in ((lower, lower_y, LOWER, shapely.Polygon()),
                                        (middle, middle_y, MIDDLE, lower)):
        for poly in polygons_of(shapely.difference(deck, solid), 1.0):
            _add_underside(poly, deck_y, builders)
            overpasses._add_road_columns(shapely.difference(poly, under), chains[level], deck_y, network, builders)
    for line in lines_of(shapely.intersection(solid.boundary, shapely.buffer(structure.corridors, 0.5))):
        coords = np.asarray(shapely.segmentize(line, DECK_SPACING["lod0"]).coords)[:, :2]
        lowest = np.where(shapely.contains_xy(lower, coords[:, 0], coords[:, 1]), lower_y(coords), middle_y(coords))
        _wall(builders, coords, network.terrain.height(coords) - WALL_FOOT, lowest - DECK_ROOT, WALL)

    # Streets bridging over it, flat across the cut, parapets along their sides.
    street_decks = [promenade_top - np.array([0.0, CURB_HEIGHT, 0.0])] if promenade_top is not None else []
    for crossing, height, half, area in structure.bridges:
        top = _add_top(area, lambda en, h=height: np.full(len(en), h), ROAD_TOP, builders)
        _add_underside(area, lambda en, h=height: np.full(len(en), h), builders, depth=OVER_DEPTH)
        for side in (half, -half):
            for line in lines_of(shapely.offset_curve(crossing, side)):
                coords = np.asarray(shapely.segmentize(line, DECK_SPACING["lod0"]).coords)[:, :2]
                _wall(builders, coords, height - OVER_DEPTH, height + overpasses.PARAPET_HEIGHT, WALL)
        if top is not None:
            tops.append(top)
            street_decks.append(top)

    # The Promenade's lamps: historic post-tops along its railing.
    points, arms = [], []
    for line in lines_of(edges["promenade"].lines(-1)):
        s = np.arange(LAMP_SPACING / 2, line.length, LAMP_SPACING)
        if len(s) == 0:
            continue
        p, normal = markings._frame(line, s)
        points.append(p + normal * LAMP_INSET)  # the west edge runs south: its left is the Promenade
        arms.append(normal)
    if points:
        points = np.concatenate(points)
        overpasses._merge_lamps(buckets.setdefault("post_lamps", {}),
                                [(points, promenade_y(points), np.concatenate(arms))], level_sizes["lod0"])

    for level, size in level_sizes.items():
        overpasses._merge(buckets.setdefault(level, {}), overpasses._bucket(builders[level], size))
    overhead = [overpasses._overhead(top, network) for top in tops if top is not None]
    buckets["overhead"] = buckets.get("overhead", []) + [o for o in overhead if o is not None and not o.is_empty]
    buckets["street_decks"] = buckets.get("street_decks", []) + street_decks
    print(f"  cantilever: {int(network.stacked.sum())} roadway segments on its decks, "
          f"{int(network.over.sum())} streets bridging over it", flush=True)


def walks(structure: Structure) -> np.ndarray:
    """Walking lanes on the Promenade (overpasses.deck_walks' lines): along
    its path, and nearer its railing."""
    out = []
    for line in lines_of(structure.data["promenade"]):
        sides = [l for side in (WALK_OFFSET, -WALK_OFFSET) for l in lines_of(shapely.offset_curve(line, side))]
        west = min(sides, key=lambda l: float(np.mean(_place(structure.axis, shapely.get_coordinates(l))[1])))
        out += [line, west]
    return np.array(out, dtype=object)


def _chain(network, level: int) -> np.ndarray:
    """The roads on one deck: its roadways, and the roads leading on from
    them (with an end at its level on the structure)."""
    levels = network.levels
    out = []
    for k in np.flatnonzero((levels == level).any(axis=1)):
        if network.stacked[k]:
            out.append(k)
            continue
        ends = shapely.get_coordinates(network.lines[k])[[0, -1]]
        if network.structure.carries(ends[levels[k] == level]).any():
            out.append(k)
    return np.array(out, dtype=np.int64)


def _angle(axis) -> float:
    """The axis' direction in uv space (x east, y south), for the pavers' rows."""
    coords = shapely.get_coordinates(axis)
    d = coords[-1] - coords[0]
    return float(np.arctan2(-d[1], d[0]))


class _Edges:
    """A deck's outline, densified, in runs by which way each piece faces:
    across the structure to the east (+1), to the west (-1), or along it (0,
    its ends), and whether it's on the solid part."""

    def __init__(self, structure: Structure, poly):
        self.rings = []
        solid = shapely.buffer(structure.solid, 0.5)
        for part in polygons_of(poly, 1.0):
            ring = shapely.segmentize(shapely.orient_polygons(part).exterior, DECK_SPACING["lod0"])
            ring = np.asarray(ring.coords)[:, :2]
            mid = (ring[1:] + ring[:-1]) / 2.0
            seg = ring[1:] - ring[:-1]
            length = np.maximum(np.hypot(seg[:, 0], seg[:, 1]), 1e-9)
            outward = np.column_stack([seg[:, 1], -seg[:, 0]]) / length[:, None]
            s, _ = _place(structure.axis, mid)
            a = shapely.get_coordinates(shapely.line_interpolate_point(structure.axis, np.maximum(s - 1.0, 0.0)))
            b = shapely.get_coordinates(shapely.line_interpolate_point(structure.axis,
                                                                       np.minimum(s + 1.0, structure.axis.length)))
            t = (b - a) / np.maximum(np.linalg.norm(b - a, axis=1, keepdims=True), 1e-9)
            dot = (outward * np.column_stack([t[:, 1], -t[:, 0]])).sum(axis=1)
            facing = np.where(dot > EDGE_FACING, 1, np.where(dot < -EDGE_FACING, -1, 0))
            inside = shapely.contains_xy(solid, mid[:, 0], mid[:, 1])
            self.rings.append((ring, facing, inside))

    def runs(self):
        """(coords, facing, on the solid part) for each run of pieces alike."""
        for ring, facing, inside in self.rings:
            key = facing * 2 + inside
            start = 0
            for i in range(1, len(key) + 1):
                if i == len(key) or key[i] != key[start]:
                    yield ring[start:i + 1], int(facing[start]), bool(inside[start])
                    start = i

    def lines(self, facing: int, solid: bool = False, ends: bool = False):
        """The pieces facing one way (and the ends, with `ends`), as lines."""
        out = [shapely.LineString(coords) for coords, f, inside in self.runs()
               if (f == facing or (ends and f == 0)) and (inside or not solid)]
        return shapely.MultiLineString(out) if out else shapely.MultiLineString()


def _outside(coords: np.ndarray, distance: float) -> np.ndarray:
    """Points `distance` to the right of a line's travel from its points."""
    coords = np.asarray(coords, np.float64)
    step = np.gradient(coords, axis=0)
    step /= np.maximum(np.linalg.norm(step, axis=1, keepdims=True), 1e-9)
    return coords + np.column_stack([step[:, 1], -step[:, 0]]) * distance


def _back_top(coords: np.ndarray, y: np.ndarray, above, above_y, ground) -> np.ndarray:
    """How high the wall at a deck's back (coords, the deck to their left)
    goes: up to the soffit's root of the deck above where there is one, else a
    parapet, or up to the ground behind where that's higher."""
    covered = shapely.contains_xy(shapely.buffer(above, 1.0), coords[:, 0], coords[:, 1])
    return np.where(covered, above_y(coords) - DECK_ROOT, np.maximum(y + PARAPET, ground(coords)))


def _add_top(poly, deck_y, uv2, builders: dict):
    """A deck's top over `poly` at deck_y(en), in every level, cut along a
    grid (so it follows the heights); returns its lod0 triangles (T, 3, 3),
    or None."""
    built = None
    poly = shapely.union_all(polygons_of(poly, 0.01))  # (a difference can leave slivers and lines)
    for level, spacing in DECK_SPACING.items():
        if level not in builders or poly.is_empty:
            continue
        tris = overpasses._grid_triangles(segmentize_polygon(poly, spacing), spacing)
        if tris is None:
            continue
        y = deck_y(tris.reshape(-1, 2)).reshape(-1, 3)
        top = np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        builders[level].add(top, uv, uv2, (0.0, 1.0, 0.0))
        if level == "lod0":
            built = top
    return built


def _add_underside(poly, deck_y, builders: dict, depth: float = DECK_ROOT) -> None:
    """A flat underside `depth` below a deck's top (detailed levels)."""
    for level in DETAILED:
        if level not in builders or poly.is_empty:
            continue
        spacing = DECK_SPACING[level]
        tris = overpasses._grid_triangles(segmentize_polygon(poly, spacing), spacing)
        if tris is None:
            continue
        y = deck_y(tris.reshape(-1, 2)).reshape(-1, 3) - depth
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        builders[level].add(np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1), uv, WALL, (0.0, -1.0, 0.0))


def _add_soffit(poly, deck_y, tips, roots, builders: dict) -> None:
    """A cantilever's underside over `poly`: DECK_TIP under its top at its
    edge (`tips`, lines), curving down to DECK_ROOT at the wall it hangs from
    (`roots`)."""
    if poly.is_empty or tips.is_empty or roots.is_empty:
        return
    for level in DETAILED:
        if level not in builders:
            continue
        spacing = DECK_SPACING[level] / 2
        tris = overpasses._grid_triangles(segmentize_polygon(poly, spacing), spacing)
        if tris is None:
            continue
        en = tris.reshape(-1, 2)
        points = shapely.points(en)
        tip, root = shapely.distance(tips, points), shapely.distance(roots, points)
        t = tip / np.maximum(tip + root, 1e-6)
        y = (deck_y(en) - DECK_TIP - (DECK_ROOT - DECK_TIP) * t * t).reshape(-1, 3)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        builders[level].add(np.stack([tris[..., 0], y, -tris[..., 1]], axis=-1), uv, WALL, (0.0, -1.0, 0.0))


def _edge_beam(builders: dict, coords: np.ndarray, y: np.ndarray, depth: float, fence: bool = False) -> None:
    """A deck's edge: its rust-colored fascia `depth` deep, and on it a pipe
    railing (or the Promenade's fence)."""
    _wall(builders, coords, y - depth, y, FASCIA)
    if fence:
        _wall(builders, coords, y, y + RAILING, FENCE_STEEL, band=True, levels=NEAR)
        return
    for rail in RAILS:
        _wall(builders, coords, y + rail - RAIL_DEPTH, y + rail, RAILING_STEEL, levels=NEAR)
    if "lod0" in builders:
        line = shapely.LineString(coords)
        s = np.arange(POST_SPACING / 2, line.length, POST_SPACING)
        if len(s):
            points, normal = markings._frame(line, s)
            base = np.interp(s, np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(coords, axis=0).T))]), y)
            for point, across, foot in zip(points, normal, base):
                along = np.array([-across[1], across[0]])
                for face in (along, across):
                    ends = np.array([point - face * POST_HALF, point + face * POST_HALF])
                    builders["lod0"].add_walls(ends, foot, foot + RAILING, RAILING_STEEL)


def _wall(builders: dict, coords: np.ndarray, bottom, top, uv2: tuple, band: bool = False,
          levels=DETAILED) -> None:
    """A wall along coords (outward to the right of travel) in these levels
    (from far away only the tops show); a `band`'s uv.y runs 0..1 from its
    foot to its top (railings drawn as open steel)."""
    coords = np.asarray(coords, np.float64)
    if len(coords) < 2:
        return
    bottom = np.broadcast_to(np.asarray(bottom, np.float64), len(coords))
    top = np.maximum(np.broadcast_to(np.asarray(top, np.float64), len(coords)), bottom)
    for level in levels:
        if level not in builders:
            continue
        count = len(builders[level].pos)
        builders[level].add_walls(coords, bottom, top, uv2)
        if band and len(builders[level].pos) > count:
            # add_walls' uv.y is meters up; a band's runs 0..1 (each piece's
            # two triangles: foot, foot, top and foot, top, top).
            uv = builders[level].uv[-1]
            uv[0::2, :, 1] = (0.0, 0.0, 1.0)
            uv[1::2, :, 1] = (0.0, 1.0, 1.0)
