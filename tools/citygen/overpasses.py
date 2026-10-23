"""Overpasses: roads raised above the ground on land (highway viaducts like
the Gowanus and the Major Deegan, ramps, streets over rail cuts and sunken
highways, rail bridges over streets), as decks on columns.

Two sources, combined:
- The street centerlines (CSCL) give each segment's level at both ends:
  13 is street level, 17 one level up, 21 two, 25 three (9 and 5 are below,
  in cuts and tunnels: the BQE's triple cantilever's are cantilever.py's,
  the rest trenches.py's, which the Network takes in with their heights).
  Raised segments become decks their width wide (merged per level, so
  carriageways and ramps at one level form one deck).
- The city's 2017 lidar survey (lidar.py) gives their decks' heights where
  it sees them (Network._fit): the Gowanus Expressway 31 m over the Gowanus
  Canal, the Cross Bronx's ramps onto the Alexander Hamilton Bridge 33 m
  over the Major Deegan. Where it doesn't, a raised road climbs from street
  level to LEVEL_RISE per level (a typical 5 m clearance under a 2 m deck)
  above the low ground around it, ramping along each segment between the
  levels at its ends. It never dips below the ground, and the fit keeps it
  clear of the roads and streets passing under it.
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
ground the levels count up from, and the survey's heights are matched to it.

Streets crossing a creek where the data has no bridge at all get a low deck
from bank to bank; on decks that carry a street over a dip, the street's
paint, lanes and props ride on the deck (OnDecks).

prepare() makes data/cache/overpasses.pkl from the raw downloads. Network
holds the raised roads and their heights; build() adds the decks to the
bridge buckets (bridges.build's format, so they get collision up close), and
lanes() / add_paint() give each near tile its driving lanes and paint on
decks; clear_of_decks() keeps props from standing up through them.
"""

import numpy as np
import shapely
from shapely.geometry import shape

import bridges
import lidar
import markings
import props
import traffic
from common import (CURB_HEIGHT, FEET, GROUND_PAVERS, GROUND_ROAD, MARKING_LIFT, STRUCTURE_CONCRETE, STRUCTURE_RAIL,
                    STRUCTURE_STEEL, STRUCTURE_WALKWAY, MeshBuilder, lines_of, load_features, polygons_of, project)
from markings import AT_GRADE, BOTH, HIGHWAY, STREET

BRIDGE_CODE = "2300"
# Roadway types (CSCL rw_type) that get decks: streets, highways, bridges,
# ramps; and paths (footbridges), which get no lanes or paint.
BRIDGE, RAMP, PATH = 3, 9, 6
ROAD_TYPES = (STREET, HIGHWAY, BRIDGE, RAMP)
LEVEL_STEP = 4       # level codes per level
MAX_LEVEL = 30       # higher codes are unknowns, taken as street level
LEVEL_RISE = 7.0     # meters from the road below to the deck's top, per level
# The lidar survey's deck heights (lidar.py), fitted over the raised roads
# (Network._fit): a deck is at least MIN_DECK and at most MAX_DECK over the
# street under it (MAX_BRIDGE_DECK on a bridge outline: the big bridges' decks
# stand 45-80 m over the water), climbs from the street at most MAX_GRADE (within
# PICK_TOLERANCE); one under another road keeps COVER_GAP below it, one over a
# road or street UNDER_CLEAR above the street (4.5 m clear under a 1 m deck).
MIN_DECK = 2.5
MAX_DECK = 40.0
MAX_BRIDGE_DECK = 100.0
TRUSS_CLEAR = 12.0  # but on a major bridge no more than this over its published deck (not its trusses or towers)
# Around a bridge built since the survey (bridges.NEWER_THAN_SURVEY), out to
# NEWER_REACH, nothing NEWER_ABOVE over its published deck (the old bridge's).
NEWER_REACH, NEWER_ABOVE = 800.0, 4.0
UNDER_CLEAR = 5.5
COVER_GAP = 4.5
MAX_GRADE = 0.08
PICK_TOLERANCE = 2.5
# A double-decker's lower roadway: a raised road with at least STACKED_SHARE
# of its stations under another road running along it (within STACKED_COS),
# which hides it from the survey, is taken STACK_DROP under that road's deck.
STACKED_SHARE = 0.6
STACKED_COS = 0.9
STACK_DROP = 7.0
# Fitting heights to the survey (Network._fit): each station's pull toward
# its surface (MEASURE, softening past FIT_SOFT off it, none past FIT_REACH),
# toward the level codes' height (PRIOR), toward the next station's along the
# road (SMOOTH meters over the distance between them), and nodes where other
# roads meet held (HOLD).
MEASURE = 1.0
PRIOR = 0.02
SMOOTH = 20.0
HOLD = 1e4
FIT_SOFT = 1.0
FIT_REACH = 4.0
FIT_ROUNDS = 4
FIT_ITERATIONS = 400
LIMIT_ROUNDS = 6
LIMIT_SLACK = 0.05
# The ground a raised road's levels count up from: the lowest within these
# rings around it (so a road on an embankment isn't counted from its top).
LOW_RINGS = (15.0, 30.0)
# Heights along each segment at least this often (meters).
STATION_STEP = 10.0
FIELD_BLEND = 20.0  # decks blend the heights of the roads on them this close
# Nodes off the streets in a dip (or on a hump) of the elevation model the
# street-level roads meeting there don't have NODE_INNER (meters) in, by at
# least NODE_DIP, are at those roads' height (Network._repair_nodes).
NODE_INNER, NODE_DIP = 20.0, 3.0
# Bridges' decks over the water follow the roads on them (on_bridge) out to
# the first of these past a road's edge, fading out by the second (meters).
ROAD_REACH = (2.0, 20.0)
# ... where the survey saw them, within the first of these along the road of
# a station it saw, fading out by the second (meters).
SEEN_GAP = (40.0, 120.0)
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
SNAP_GAP = (2.0, 4.0)  # raised roads on land take decks this close to their own height, easing off by the second
# Bridges at street level in the data follow their deck from point to point
# along a lane (_tracked) while it's within this much (m), plus this grade, of
# the height before.
TRACK_STEP, TRACK_GRADE = 1.0, 0.2
PARAPET_FROM = 1.0   # parapets where the deck is at least this high
SOLID_BELOW = 2.5    # under a lower gap, the deck's sides go down to the ground
COLUMN_SPACING = 36.0
COLUMN_CLEARANCE = 3.0
COLUMN_SIZE = (1.0, 0.7)   # half sizes along and across the road (m)
MEDIAN = 1.0               # columns may stand this close to a two-way street's middle
CAP_DEPTH = 1.2            # the pier cap under the deck
WIDE_DECK = 16.0           # wider roads stand on two columns
COLUMN_STREET_GAP = 4.0    # columns keep this far from streets crossing underneath
# The city's roadbed outlines take in raised roads too, so they'd draw road on
# the ground under viaducts and bridge approaches: under decks at least this
# high, away from the streets at grade (their width and this margin), the
# roadbed isn't road (roads_under_decks).
GHOST_GAP = 3.0
STREET_MARGIN = 1.0
# Walking lanes on decks with sidewalks (bridges over water, raised streets):
# the city's sidewalk outlines on them, those running along the deck (at
# least this cosine), at least WALK_MIN_AREA, a loop around each one's middle.
WALK_ALONG = 0.8
WALK_MIN_AREA = 10.0
WALK_STEP = 10.0
# Sidewalk outlines kept for that (prepare_sidewalks): this close to a bridge
# outline or a raised road.
WALK_REACH = 20.0
# How finely decks follow their heights, per level (meters between points),
# and the smallest decks the far tiles keep (m^2).
DECK_SPACING = {"lod0": 10.0, "lod1": 20.0, "lod2": 40.0}
FAR_MIN_AREA = 3000.0
DETAILED = ("lod0", "lod1")

# What props mustn't reach up into: decks' and bridges' tops, and the hand-made
# bridges' and the els' (els.py).
OVERHEAD = (GROUND_ROAD, STRUCTURE_CONCRETE, STRUCTURE_STEEL, STRUCTURE_RAIL, STRUCTURE_WALKWAY)

# Node ids for raised roads' ends that aren't at a street-level node:
# above any street node id (markings.prepare), below 2^24 (exact as floats).
NODE_BASE = 4_000_000


def prepare() -> dict:
    """Raised road segments (any end above street level), street-level ramps
    and bridges (which link them and the bridges over water to the streets),
    and the bridge outlines."""
    lines, rows, walkway = [], [], []
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
            walkway.append(p.get("trafdir") == "NV")
            rows.append((rw, trafdir, int(float(p.get("number_travel_lanes") or 0)),
                         int(float(p.get("number_park_lanes") or 0)), float(p.get("streetwidth") or 0) * FEET,
                         levels[0], levels[1]))
    lines = project(np.array(lines, dtype=object))
    attrs = np.array(rows, dtype=np.float64)
    keep = shapely.length(lines) > 1.0
    lines, attrs, walkway = lines[keep], attrs[keep], np.array(walkway, dtype=bool)[keep]

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
        # Non-vehicular (trafdir NV): bridges' walkways and bikeways, which get
        # decks but no driving lanes or paint (the streets skip them too).
        "walkway": walkway,
        "outlines": geoms,
        "outline_names": [f["properties"].get("name") or "NO NAME" for f in outlines],
    }


def _solve(count: int, ea, eb, ew, diag, rhs, x) -> np.ndarray:
    """Solves (diag + the weighted graph Laplacian of edges ea-eb) x = rhs by
    conjugate gradients, preconditioned by the diagonal, from x."""
    full = diag + np.bincount(ea, weights=ew, minlength=count) + np.bincount(eb, weights=ew, minlength=count)

    def apply(v):
        return full * v - np.bincount(ea, weights=ew * v[eb], minlength=count) \
            - np.bincount(eb, weights=ew * v[ea], minlength=count)
    inverse = 1.0 / np.maximum(full, 1e-12)
    r = rhs - apply(x)
    z = inverse * r
    p = z.copy()
    rz = r @ z
    for _ in range(FIT_ITERATIONS):
        ap = apply(p)
        alpha = rz / max(p @ ap, 1e-30)
        x = x + alpha * p
        r = r - alpha * ap
        if np.abs(r).max() < 1e-4:
            break
        z = inverse * r
        rz, previous = r @ z, rz
        p = z + (rz / max(previous, 1e-30)) * p
    return x


def _nearest(layers: np.ndarray, target: np.ndarray) -> np.ndarray:
    """Per row of (N, L) layers (NaN: none), the one nearest target (N,), or NaN."""
    miss = np.where(np.isnan(layers), np.inf, np.abs(layers - target[:, None]))
    pick = np.argmin(miss, axis=1)
    out = layers[np.arange(len(layers)), pick]
    return np.where(np.isfinite(miss[np.arange(len(layers)), pick]), out, np.nan)


def rise(level) -> np.ndarray:
    """Meters above the road below for CSCL level codes (0 at street level and below)."""
    return np.maximum(np.asarray(level, np.float64) - int(AT_GRADE), 0.0) / LEVEL_STEP * LEVEL_RISE


def _inward(lines: np.ndarray) -> np.ndarray:
    """Unit directions into each line from its start, then from its end
    (2N, 2), as markings.prepare measures them."""
    length = shapely.length(lines)
    step = np.minimum(3.0, length / 2)
    starts = shapely.get_coordinates(shapely.get_point(lines, 0))
    ends = shapely.get_coordinates(shapely.get_point(lines, -1))
    inward = np.vstack([shapely.get_coordinates(shapely.line_interpolate_point(lines, step)) - starts,
                        shapely.get_coordinates(shapely.line_interpolate_point(lines, length - step)) - ends])
    return inward / np.maximum(np.linalg.norm(inward, axis=1, keepdims=True), 1e-9)


def _running_median(values: np.ndarray, window: int) -> np.ndarray:
    """The median of each value and its neighbors (`window` wide), ignoring
    NaNs and -inf (NaN where there are none)."""
    v = np.where(np.isfinite(values), values, np.nan)
    half = window // 2
    padded = np.pad(v, half, constant_values=np.nan)
    stack = np.stack([padded[i:i + len(v)] for i in range(window)])
    with np.errstate(all="ignore"):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            return np.nanmedian(stack, axis=0)


def _directions(line, s: np.ndarray) -> np.ndarray:
    """Unit directions along a line at distances s along it (N, 2)."""
    length = line.length
    ahead = shapely.get_coordinates(shapely.line_interpolate_point(line, np.minimum(s + 1.0, length)))
    behind = shapely.get_coordinates(shapely.line_interpolate_point(line, np.maximum(s - 1.0, 0.0)))
    d = ahead - behind
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)


class Network:
    """The raised roads (and the street-level ramps and bridges that link them
    to the streets): their heights, their decks' groups, and their attributes
    in markings.prepare's format (for traffic.lanes and markings.quads), with
    node ids that match the streets'.

    `terrain` is a terrain.Terrain; `streets` the prepared street centerlines
    (markings.prepare). `structure` (a cantilever.Structure) brings the
    roadways below street level it carries, their heights, and its ground;
    `decks` the lidar survey's deck heights (lidar.prepare); `sunken` (a
    trenches.Sunken) the streets and highways below street level elsewhere,
    their heights (self.sunken) and their cuts (self.trenches). With `land`
    (the prepared ground's), the bridges at street level in the data that
    cross the water are fitted to the survey too, and the roads on the big
    bridges lean on their published heights over the water where the survey
    doesn't see them (bridges.over_water)."""

    def __init__(self, data: dict, streets: dict, terrain, structure=None, decks=None, sunken=None, land=None):
        self.structure = structure
        stacked = np.zeros(len(data["lines"]), dtype=bool)
        surveyed = data["lines"]  # as the survey's stations were laid out (lidar.py)
        if structure is not None:
            data, stacked = structure.merged(data, streets)
        self.added = np.zeros(len(data["lines"]), dtype=bool)
        if sunken is not None:
            data, self.added = sunken.merged(data)
            stacked = np.concatenate([stacked, np.zeros(self.added.sum(), dtype=bool)])
        self.data = data
        self.lines = data["lines"]
        self.count = len(self.lines)
        # Walkways and bikeways (prepare's; none among the roads added above).
        self.walkway = np.zeros(self.count, dtype=bool)
        self.walkway[:len(data.get("walkway", []))] = data.get("walkway", [])
        self.terrain = terrain
        self.ground_lattice = terrain.lattice(20.0)  # the lod0 ground (build_tiles.LEVELS)
        if structure is not None:
            self.ground_lattice = structure.ground(self.ground_lattice)
        # The ground before the sunken roads' cuts (roads' heights count from
        # it), but for the street-level highways through the mounds the
        # elevation model has over them (trenches.Mounds).
        self.mounds = None
        if sunken is not None:
            up = data["levels"].max(axis=1) > int(AT_GRADE)
            self.mounds = sunken.mounds(streets, terrain, data["outlines"], data["lines"][up])
        if self.mounds is not None:
            self.ground_lattice = self.mounds.lattice(self.ground_lattice)
        self.grade_lattice = self.ground_lattice
        self.levels = data["levels"].astype(np.int64)
        # (Codes past the top level are unknowns: one road has 99.)
        self.levels[self.levels > MAX_LEVEL] = int(AT_GRADE)
        top = self.levels.max(axis=1)
        # Roadways on the structure's decks, and streets bridging over it (its
        # build() makes their decks).
        self.stacked = stacked
        self.over = np.zeros(len(self.lines), dtype=bool)
        if structure is not None:
            self.over = np.array([structure.bridge(line) for line in self.lines])
        self.width = self._widths()
        self.published, self.wet = bridges.over_water(land, terrain) if land is not None else ([], shapely.Polygon())
        self.under = np.zeros(self.count, dtype=bool)  # double-deckers' lower roadways (_surveyed)
        self.tree = shapely.STRtree(self.lines)
        self._stations = [None] * self.count
        self.attrs = self._attributes(streets)
        self.ends = self._end_heights()
        # Roads below street level, as the survey has them (trenches.fit; the
        # raised roads leaving them start from their heights).
        self.sunken = sunken.fit(self) if sunken is not None else {}
        self.lids = None
        if sunken is not None:
            # The ground over their tunnels is their lid (trenches.Lids), and
            # the roads at street level there count from it.
            self.lids = sunken.lids(self)
            self.grade_lattice = self.ground_lattice = self.lids.lattice(self.grade_lattice)
            below = self.levels < int(AT_GRADE)
            self.ends = np.where(below, self.ends, self._end_heights())
        self.fitted = self._fit(decks or {}, surveyed, streets)
        # Raised: above street level, or (at street level in the data) brought
        # up to meet roads that are.
        starts = shapely.get_coordinates(shapely.get_point(self.lines, 0))
        finishes = shapely.get_coordinates(shapely.get_point(self.lines, -1))
        lifted = (self.ends - np.column_stack([self.grade(starts), self.grade(finishes)])).max(axis=1) > GRADE_DECK
        lifted &= ~np.isin(np.arange(self.count), list(self.sunken))  # (in their cuts: trenches.py's)
        self.raised = (top > int(AT_GRADE)) | stacked | (lifted & (data["rw"] != PATH))
        # Decks are grouped by level, rounded up to whole levels.
        self.group = np.where(self.raised, int(AT_GRADE) + LEVEL_STEP * np.ceil((top - int(AT_GRADE)) / LEVEL_STEP), 0)
        self.group = self.group.astype(np.int64)
        # Street-level roads, for what passes under (or along) a deck: the
        # streets and our street-level ramps and bridges.
        level = ~self.raised & (data["rw"] != PATH)
        street_half = np.where(streets["width"] > 0, streets["width"] / 2.0,
                               np.maximum(streets["lanes"], 1) * markings.LANE_WIDTH / 2.0 + 1.0)
        self.under_lines = np.concatenate([streets["lines"], self.lines[level]])
        # (Which are below street level: their cuts and bridges are trenches.py's.)
        self.under_sunken = np.concatenate([np.zeros(len(streets["lines"]), dtype=bool),
                                            np.isin(np.flatnonzero(level), list(self.sunken))])
        self.under_half = np.concatenate([street_half, self.width[level] / 2.0])
        self.under_two_way = np.concatenate([streets["trafdir"] == BOTH, data["trafdir"][level] == BOTH])
        self.under_tree = shapely.STRtree(self.under_lines)
        # Half the width of their travel lanes (markings.lane_layout), for
        # keeping columns out of them (els.py).
        lanes = np.where(streets["lanes"] > 0, streets["lanes"],
                         np.where((streets["trafdir"] == BOTH) & (streets["width"] >= markings.CENTER_LINE_MIN_WIDTH), 2, 1))
        lane = np.where(streets["width"] > 0, np.clip((streets["width"] - streets["parking"] * markings.PARKING_WIDTH) /
                                                      lanes, markings.MIN_LANE, markings.MAX_LANE), markings.LANE_WIDTH)
        self.under_travel = np.concatenate([lanes * lane / 2.0, np.maximum(self.width[level] / 2.0 - 1.0, 1.5)])
        # The sunken roads' cuts, walls and bridges (trenches.Trenches); from
        # here on the street under decks is the cuts' floor where they are.
        self.trenches = None
        if sunken is not None:
            self.trenches = sunken.trenches(self, streets)
            self.ground_lattice = self.trenches.ground(self.ground_lattice)

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
        # Signalized nodes' approaches: (direction away from the node, phase).
        approaches, major_at = {}, {}
        street_inward = _inward(street_lines)
        for node, phase, direction, major in zip(flat.tolist(), streets["phase"].T.reshape(-1).tolist(), street_inward,
                                                 streets["major"].T.reshape(-1).tolist()):
            major_at[node] = major_at.get(node, False) or bool(major)
            if phase >= 0.0:
                approaches.setdefault(node, []).append((direction, phase))

        mine = np.vstack([shapely.get_coordinates(shapely.get_point(self.lines, 0)),
                          shapely.get_coordinates(shapely.get_point(self.lines, -1))])
        my_keys = np.round(mine * 2.0).astype(np.int64)
        my_levels = np.concatenate([self.levels[:, 0], self.levels[:, 1]])
        nodes = np.zeros(len(mine), dtype=np.int64)
        ends_setback = np.zeros(len(mine), dtype=np.float32)
        ends_crossing = np.zeros(len(mine), dtype=bool)
        ends_signal = np.zeros(len(mine), dtype=bool)
        ends_major = np.zeros(len(mine), dtype=bool)
        ends_phase = np.full(len(mine), -1.0, dtype=np.float32)
        my_inward = _inward(self.lines)
        others = {}
        for e, ((x, y), level) in enumerate(zip(my_keys.tolist(), my_levels.tolist())):
            street = node_of.get((x, y)) if level == int(AT_GRADE) else None
            if street is not None:
                nodes[e] = street
                ends_crossing[e] = crossing_at[street]
                ends_setback[e] = setback_at[street] if crossing_at[street] else 0.0
                if crossing_at[street] and street in approaches:
                    # A ramp or bridge arriving at a signal goes with the
                    # street approach most in line with it, or the others.
                    direction, phase = max(approaches[street], key=lambda a: abs(float(a[0] @ my_inward[e])))
                    in_line = abs(float(direction @ my_inward[e])) >= markings.CROSSING_ANGLE
                    ends_phase[e] = phase if in_line else (phase + 0.5) % 1.0
                    ends_signal[e] = True
                    ends_major[e] = major_at[street]
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
            "major": ends_major.reshape(2, n).T,
            "signal": ends_signal.reshape(2, n).T,
            "phase": ends_phase.reshape(2, n).T,
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

    def grade(self, en: np.ndarray) -> np.ndarray:
        """street(), but for the sunken roads' cuts (what roads' heights count from)."""
        return self.grade_lattice.height(en) - CURB_HEIGHT

    def low(self, en: np.ndarray) -> np.ndarray:
        """The lowest street height in LOW_RINGS around each point."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        angles = np.arange(8) * (np.pi / 4)
        offsets = np.concatenate([[[0.0, 0.0]]] + [np.column_stack([np.cos(angles), np.sin(angles)]) * r
                                                   for r in LOW_RINGS])
        h = self.terrain.height((en[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(len(en), -1)
        return h.min(axis=1) - CURB_HEIGHT

    def _surveyed(self, decks: dict, surveyed: np.ndarray, streets: dict, members: np.ndarray) -> dict:
        """What the lidar survey has along each of these raised segments
        (lidar.py), and the limits on their heights: {segment: (distances
        along, surfaces (S, L) NaN-padded, floors, ceilings)}. A deck is
        MIN_DECK to MAX_DECK over the street (MAX_BRIDGE_DECK on a bridge
        outline, but at most TRUSS_CLEAR over a major bridge's published
        deck). Where a road (or street) at
        least half a level down by the level codes there passes under a
        station, the deck is at least UNDER_CLEAR over the street; where one
        at least half a level up passes over it, COVER_GAP below that one
        (whose deck is the station's highest surface). A road can't climb
        from where it meets the street faster than MAX_GRADE (what's higher
        there is something over it)."""
        out = {}
        under_lines = np.concatenate([streets["lines"], self.lines])
        under_half = np.concatenate([np.where(streets["width"] > 0, streets["width"] / 2.0, markings.DEFAULT_HALF_WIDTH),
                                     self.width / 2.0])
        under_levels = np.concatenate([np.full((len(streets["lines"]), 2), int(AT_GRADE)), self.levels])
        under_tree = shapely.STRtree(under_lines)
        # (Not roads that go below street level: in cuts, or the triple
        # cantilever's ramps, what the survey sees is over them.)
        below = self.levels.min(axis=1) < int(AT_GRADE)
        bridges_area = shapely.union_all(self.data["outlines"])
        shapely.prepare(bridges_area)
        for k in members:
            length = self.lines[k].length
            found = lidar.heights(decks, surveyed[k]) if k < len(surveyed) and not below[k] else None
            if found is not None:
                s, layers = (np.asarray(a, np.float64) for a in found)
                s = s * length / max(float(surveyed[k].length), 1e-6)
            else:
                s = np.linspace(0.0, length, max(2, int(np.ceil(length / STATION_STEP)) + 1))
                layers = np.full((len(s), lidar.MAX_LAYERS), np.nan)
            en = shapely.get_coordinates(shapely.line_interpolate_point(self.lines[k], s))
            points = shapely.points(en)
            street = self.street(en)
            top = street + np.where(shapely.contains_xy(bridges_area, en[:, 0], en[:, 1]), MAX_BRIDGE_DECK, MAX_DECK)
            for _, height, outline, newer in self.published:
                on = shapely.contains_xy(outline, en[:, 0], en[:, 1])
                top[on] = np.minimum(top[on], height + TRUSS_CLEAR)
                if newer:
                    # (The survey saw what stood there before: the old bridge,
                    # higher, approaches and all.)
                    layers[on] = np.nan
                    around = shapely.dwithin(outline, shapely.points(en), NEWER_REACH)
                    layers[around] = np.where(layers[around] > height + NEWER_ABOVE, np.nan, layers[around])
            layers = np.where((layers >= street[:, None] + MIN_DECK) & (layers <= top[:, None]), layers, np.nan)
            highest = np.nanmax(np.where(np.isnan(layers), -np.inf, layers), axis=1)
            # The level codes here, and the other roads' over and under the
            # stations (half a level or more apart).
            mine = self.levels[k, 0] + (self.levels[k, 1] - self.levels[k, 0]) * s / max(length, 1e-6)
            point, other = under_tree.query(points, predicate="dwithin", distance=MAX_WIDTH)
            near = shapely.distance(under_lines[other], points[point]) <= under_half[other] + 1.0
            point, other = point[near], other[near]
            along = shapely.line_locate_point(under_lines[other], points[point], normalized=True)
            theirs = under_levels[other, 0] + (under_levels[other, 1] - under_levels[other, 0]) * along
            covered = np.zeros(len(s), dtype=bool)
            over = theirs >= mine[point] + LEVEL_STEP / 2
            covered[point[over]] = True
            passing = np.zeros(len(s), dtype=bool)
            passing[point[theirs <= mine[point] - LEVEL_STEP / 2]] = True
            floor = np.where(passing, street + UNDER_CLEAR, -np.inf)
            layers[covered] = np.where(layers[covered] <= highest[covered, None] - COVER_GAP, layers[covered], np.nan)
            ceiling = np.where(covered & np.isfinite(highest), highest - COVER_GAP, np.inf)
            # Under a road running along it most of the way: a double-decker's
            # lower roadway, which the survey can't see. Where it sees nothing
            # of its own, STACK_DROP under the deck over it.
            if over.any() and min(self.levels[k]) > int(AT_GRADE):
                along_line = _directions(self.lines[k], s)
                theirs_at = shapely.line_locate_point(under_lines[other[over]], points[point[over]])
                theirs_line = np.array([_directions(under_lines[o], np.array([a]))[0]
                                        for o, a in zip(other[over], theirs_at)])
                parallel = np.abs((along_line[point[over]] * theirs_line).sum(axis=1)) >= STACKED_COS
                stacked = np.zeros(len(s), dtype=bool)
                stacked[point[over][parallel]] = True
                if stacked.mean() >= STACKED_SHARE:
                    self.under[k] = True
                    blind = stacked & np.isnan(layers).all(axis=1) & np.isfinite(highest)
                    layers[blind, 0] = highest[blind] - STACK_DROP
            # On a bridge, a roadway a level up running along it, edge to edge
            # (a double-decker the data draws side by side: the Henry
            # Hudson's): the same, and what the survey has under that deck is
            # no road of its own.
            on_deck = shapely.contains_xy(bridges_area, en[:, 0], en[:, 1])
            if on_deck.any() and min(self.levels[k]) > int(AT_GRADE):
                point2, o = self.tree.query(points, predicate="dwithin", distance=MAX_WIDTH)
                up = (o != k) & (self.levels[o].max(axis=1) >= self.levels[k].max() + LEVEL_STEP // 2)
                point2, o = point2[up], o[up]
                close = shapely.distance(self.lines[o], points[point2]) <= (self.width[o] + self.width[k]) / 2.0 + 2.0
                point2, o = point2[close], o[close]
                if len(o):
                    at = shapely.line_locate_point(self.lines[o], points[point2])
                    theirs = np.array([_directions(self.lines[j], np.array([a]))[0] for j, a in zip(o, at)])
                    parallel = np.abs((_directions(self.lines[k], s)[point2] * theirs).sum(axis=1)) >= STACKED_COS
                    beside = np.zeros(len(s), dtype=bool)
                    beside[point2[parallel]] = True
                    deck = _running_median(highest, 5)  # (the deck over it, strays out)
                    beside &= on_deck & np.isfinite(deck)
                    if beside.sum() >= STACKED_SHARE * on_deck.sum():
                        self.under[k] = True
                        layers[beside] = np.nan
                        layers[beside, 0] = deck[beside] - STACK_DROP
                        ceiling[beside] = np.maximum(ceiling[beside], deck[beside] - COVER_GAP)
            layers = np.where(layers >= floor[:, None], layers, np.nan)
            for i, level in ((0, self.levels[k, 0]), (-1, self.levels[k, 1])):
                # (A bridge at street level in the data climbs from the streets
                # at its ends, not from where it's cut into pieces on the way.)
                if level <= int(AT_GRADE) and (max(self.levels[k]) > int(AT_GRADE)
                                               or self.attrs["nodes"][k, i] < NODE_BASE):
                    reach = street[i] + MAX_GRADE * np.abs(s - s[i]) + PICK_TOLERANCE
                    layers = np.where(layers <= reach[:, None], layers, np.nan)
            out[int(k)] = (s, layers, floor, ceiling)
        return out

    def _fit(self, decks: dict, surveyed: np.ndarray, streets: dict) -> dict:
        """The raised roads' heights fitted to the lidar survey, all at once:
        {segment: (distances along, heights)}. Every station's height follows
        the survey's surface there (_surveyed), ties to the next station's
        along the road (SMOOTH; at nodes the roads meeting share one), and
        leans a little on the level codes' heights (PRIOR); nodes where other
        roads meet stay at their heights. The surface a station follows is the
        highest at first, then the one nearest the fit; ones far from the fit
        stop counting (other bridges, roads and roofs over and under it), as
        an iteratively reweighted least squares fit over FIT_ROUNDS. Then
        stations under their floors or over their ceilings are held there,
        until none are (or LIMIT_ROUNDS)."""
        self.followed = {}
        if not decks:
            return {}
        top = self.levels.max(axis=1)
        # Raised roads, and the bridges at street level in the data
        # (drawbridges, causeways), which rise over the water between the
        # streets at their ends.
        level_bridge = (top <= int(AT_GRADE)) & (self.data["rw"] == BRIDGE) & ~self.added
        level_bridge[level_bridge] = shapely.length(shapely.intersection(self.lines[level_bridge], self.wet)) >= 1.0
        members = np.flatnonzero(((top > int(AT_GRADE)) | level_bridge) & ~self.stacked & ~self.over)
        survey = self._surveyed(decks, surveyed, streets, members)
        nodes = self.attrs["nodes"]
        inside = np.zeros(self.count, dtype=bool)
        inside[members] = True
        raised_in = inside & ~level_bridge
        held = (set(nodes[~inside].reshape(-1).tolist())
                | set(nodes[raised_in][self.levels[raised_in] <= int(AT_GRADE)].tolist())
                | {n for n in nodes[inside & level_bridge].reshape(-1).tolist() if n < NODE_BASE})
        node_var = {}
        count = 0
        index = {}
        prior_w, prior_v, hold_w = [], [], []
        start_w, start_v = [], []  # (where the fit starts from: the priors, and the roads' ends between)
        edges = []

        def new_vars(n):
            nonlocal count
            out = np.arange(count, count + n)
            count += n
            return out
        for k in members:
            s = survey[k][0]
            idx = np.empty(len(s), dtype=np.int64)
            for i in (0, -1):
                node = int(nodes[k, 0 if i == 0 else 1])
                if node not in node_var:
                    node_var[node] = new_vars(1)[0]
                    if node in held:
                        hold_w.append((node_var[node], self.ends[k, 0 if i == 0 else 1]))
                idx[i] = node_var[node]
            if len(s) > 2:
                idx[1:-1] = new_vars(len(s) - 2)
            t = s / max(self.lines[k].length, 1e-6)
            prior = self.ends[k, 0] + (self.ends[k, 1] - self.ends[k, 0]) * (0.5 * t + 0.5 * t * t * (3.0 - 2.0 * t))
            keep = np.ones(len(s), dtype=bool)
            if self.published:
                # On a big bridge over the water, its published deck height
                # (a lower roadway STACK_DROP under it); on the approaches of
                # one built since the survey, none (the fit carries the roads
                # around it to that height).
                en = shapely.get_coordinates(shapely.line_interpolate_point(self.lines[k], s))
                for area, height, outline, newer in self.published:
                    on = shapely.contains_xy(area, en[:, 0], en[:, 1])
                    prior[on] = height - (STACK_DROP if self.under[k] else 0.0)
                    if newer:
                        keep &= on | ~shapely.contains_xy(outline, en[:, 0], en[:, 1])
            prior_w.append(idx[keep])
            prior_v.append(prior[keep])
            start_w.append(idx)
            start_v.append(prior)
            ds = np.maximum(np.diff(s), 0.5)
            edges.append(np.column_stack([idx[:-1], idx[1:], SMOOTH / ds]))
            index[k] = idx
        edges = np.concatenate(edges)
        ea, eb, ew = edges[:, 0].astype(np.int64), edges[:, 1].astype(np.int64), edges[:, 2]
        prior_idx, prior_val = np.concatenate(prior_w), np.concatenate(prior_v)
        held_idx = np.array([i for i, _ in hold_w], dtype=np.int64)
        held_val = np.array([v for _, v in hold_w])
        floor = np.full(count, -np.inf)
        ceiling = np.full(count, np.inf)
        for k in members:
            np.maximum.at(floor, index[k], survey[k][2])
            np.minimum.at(ceiling, index[k], survey[k][3])
        floor[held_idx], ceiling[held_idx] = -np.inf, np.inf  # (held as they are)
        # The survey's stations.
        obs_idx = np.concatenate([index[k] for k in members])
        obs_layers = np.concatenate([survey[k][1] for k in members])
        obs_pick = np.nanmax(np.where(np.isnan(obs_layers), -np.inf, obs_layers), axis=1)
        obs_weight = np.where(np.isfinite(obs_pick), MEASURE, 0.0)
        obs_pick = np.where(np.isfinite(obs_pick), obs_pick, 0.0)
        x = np.zeros(count)
        start_idx, start_val = np.concatenate(start_w), np.concatenate(start_v)
        np.add.at(x, start_idx, start_val)
        x /= np.maximum(np.bincount(start_idx, minlength=count), 1)
        limit_idx, limit_val = np.zeros(0, dtype=np.int64), np.zeros(0)
        for round_ in range(FIT_ROUNDS + LIMIT_ROUNDS):
            diag = np.bincount(prior_idx, minlength=count) * PRIOR
            rhs = np.bincount(prior_idx, weights=prior_val * PRIOR, minlength=count)
            diag += np.bincount(obs_idx, weights=obs_weight, minlength=count)
            rhs += np.bincount(obs_idx, weights=obs_weight * obs_pick, minlength=count)
            diag[held_idx] += HOLD
            rhs[held_idx] += HOLD * held_val
            np.add.at(diag, limit_idx, HOLD)
            np.add.at(rhs, limit_idx, HOLD * limit_val)
            x = _solve(count, ea, eb, ew, diag, rhs, x)
            if round_ < FIT_ROUNDS - 1:
                # Next: the surfaces nearest the fit, those far from it not counting.
                fit = x[obs_idx]
                obs_pick = _nearest(obs_layers, fit)
                miss = np.abs(obs_pick - fit)
                obs_weight = np.where(np.isfinite(obs_pick) & (miss <= FIT_REACH),
                                      MEASURE / np.maximum(1.0, miss / FIT_SOFT), 0.0)
                obs_pick = np.where(np.isfinite(obs_pick), obs_pick, 0.0)
            else:
                # Hold the stations past their limits there.
                low = np.flatnonzero(x < floor - LIMIT_SLACK)
                high = np.flatnonzero(x > ceiling + LIMIT_SLACK)
                if not len(low) and not len(high):
                    break
                limit_idx = np.concatenate([limit_idx, low, high])
                limit_val = np.concatenate([limit_val, floor[low], ceiling[high]])
        out = {}
        # Which stations follow the survey (bridges.py's decks take their
        # heights over the water only where they do).
        followed = np.split(obs_weight > 0, np.cumsum([len(index[k]) for k in members])[:-1])
        self.followed = {}
        for k, seen in zip(members, followed):
            h = x[index[k]]
            out[int(k)] = (survey[k][0], h)
            self.followed[int(k)] = seen
            self.ends[k] = (h[0], h[-1])
        self.surveyed_share = float((obs_weight > 0).mean()) if len(obs_weight) else 0.0
        return out

    def _end_height(self, level: int, en: np.ndarray) -> np.ndarray:
        """Road heights at (N, 2) segment ends at one level code: the street
        at street level (and below, except on the structure), LEVEL_RISE per
        level above the low ground around above it."""
        street = self.grade(en)
        if level > int(AT_GRADE):
            return np.maximum(street, self.low(en) + float(rise(level)))
        if level < int(AT_GRADE) and self.structure is not None:
            return np.where(self.structure.carries(en), self.structure.level(level, en), street)
        return street

    def _end_heights(self) -> np.ndarray:
        """Each segment's road height at its start and end (N, 2), the same
        for every road meeting at a node. At street level in the data, where
        no street meets them:
        - where roads leave the structure's decks: the deck's level
          (cantilever.py);
        - where only roads off street level meet (a highway between two
          viaducts that only its level codes bring down): the mean of those
          roads' other ends."""
        en = np.stack([shapely.get_coordinates(shapely.get_point(self.lines, 0)),
                       shapely.get_coordinates(shapely.get_point(self.lines, -1))], axis=1).reshape(-1, 2)
        node = self.attrs["nodes"].astype(np.int64).reshape(-1)
        level = self.levels.reshape(-1)
        other = self.levels[:, ::-1].reshape(-1)
        ends = np.zeros(len(en))
        for value in np.unique(level):
            ends[level == value] = self._end_height(int(value), en[level == value])
        self._repair_nodes(ends, node, level)
        unknown = (node >= NODE_BASE) & (level == int(AT_GRADE))
        pinned = {}
        if self.structure is not None:
            for e in np.flatnonzero(unknown & (other < int(AT_GRADE))):
                if self.structure.on_decks(en[e:e + 1])[0]:
                    pinned[node[e]] = float(self.structure.level(int(other[e]), en[e:e + 1])[0])
        free = unknown & (other != int(AT_GRADE)) & np.repeat(self.data["rw"] != PATH, 2) & ~np.isin(node, list(pinned))
        # (The streets and highways below street level, trenches.py's, go
        # with what the others make of such nodes.)
        counted = ~np.repeat(self.added, 2)
        free &= counted
        ids, index = np.unique(node, return_inverse=True)
        incident = np.bincount(index[counted], minlength=len(ids))
        qualified = np.bincount(index[free], minlength=len(ids))
        total = np.bincount(index[free], weights=ends.reshape(-1, 2)[:, ::-1].reshape(-1)[free], minlength=len(ids))
        node_free = (qualified == incident) & (incident >= 2)
        pick = node_free[index] & (free | (unknown & ~counted))
        ends[pick] = total[index[pick]] / qualified[index[pick]]
        for e in np.flatnonzero(np.isin(node, list(pinned))):
            ends[e] = pinned[node[e]]
        self.free_nodes = int(node_free.sum())
        return ends.reshape(-1, 2)

    def _repair_nodes(self, ends: np.ndarray, node: np.ndarray, level: np.ndarray) -> None:
        """Nodes off the streets (not shared with the streets' lanes) where
        street-level roads meet, in a dip or on a hump of the elevation model
        that none of those roads has NODE_INNER in (the blurred edge of a
        cliff: the Washington Bridge's ramps meet at the Manhattan bluff's),
        NODE_DIP or more: at those roads' median height there. `ends` (2N,),
        in place."""
        lines, n = self.lines, self.count
        flat = np.flatnonzero((self.levels == int(AT_GRADE)).all(axis=1) & (self.data["rw"] != PATH))
        e = np.concatenate([flat * 2, flat * 2 + 1])
        e = e[node[e] >= NODE_BASE]
        if not len(e):
            return
        k = e // 2
        length = shapely.length(lines[k])
        reach = np.minimum(NODE_INNER, 0.5 * length)
        at = np.where(e % 2 == 0, reach, length - reach)
        inner = self.grade(shapely.get_coordinates(shapely.line_interpolate_point(lines[k], at)))
        by_node = {}
        for end, height in zip(e.tolist(), inner.tolist()):
            by_node.setdefault(int(node[end]), []).append((end, height))
        for found in by_node.values():
            if len(found) < 2:
                continue
            here = ends[found[0][0]]
            heights = np.array([h for _, h in found])
            if here < heights.min() - NODE_DIP or here > heights.max() + NODE_DIP:
                ends[(node == node[found[0][0]]) & (level == int(AT_GRADE))] = float(np.median(heights))

    def stations(self, k: int) -> tuple[np.ndarray, np.ndarray]:
        """Distances along segment k and its road's height there."""
        if self._stations[k] is None:
            line = self.lines[k]
            length = line.length
            s = np.linspace(0.0, length, max(2, int(np.ceil(length / STATION_STEP)) + 1))
            en = shapely.get_coordinates(shapely.line_interpolate_point(line, s))
            street = self.grade(en)
            l0, l1 = self.levels[k]
            ends = self.ends[k]
            t = s / max(length, 1e-6)
            if k in self.sunken:
                # Below street level, as the survey has it (trenches.fit).
                s, h = self.sunken[k][:2]
            elif self.stacked[k]:
                # On the structure's decks, at its levels' heights.
                h = self.structure.level(int(l0), en) * (1.0 - t) + self.structure.level(int(l1), en) * t
            elif self.over[k]:
                h = ends[0] + (ends[1] - ends[0]) * t  # straight across, over the structure
            elif max(l0, l1) <= int(AT_GRADE) and k not in self.fitted and np.allclose(ends, street[[0, -1]]):
                h = street
            else:
                # Half straight, half eased: ramps climb steadily but round
                # into the level road at either end.
                ease = 0.5 * t + 0.5 * t * t * (3.0 - 2.0 * t)
                h = ends[0] + (ends[1] - ends[0]) * ease
                if k in self.fitted:
                    # As fitted to the lidar survey.
                    h = np.interp(s, *self.fitted[k])
                    floor = street
                elif min(l0, l1) <= int(AT_GRADE):
                    floor = street
                else:
                    floor = np.maximum(street, self.low(en) + float(rise(min(l0, l1))))
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
        """Heights at (N, 2) points from these segments: the nearest one's,
        blended with the others' within FIELD_BLEND (by inverse square
        distance), so a deck that carries roads at different heights (a ramp
        leaving a highway) bends between them rather than steps."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if len(segments) == 1:
            return self.along(int(segments[0]), en)
        tree = shapely.STRtree(self.lines[segments])
        points = shapely.points(en)
        nearest = tree.query_nearest(points, return_distance=False, all_matches=False)
        near = tree.query(points, predicate="dwithin", distance=FIELD_BLEND)
        pairs = np.unique(np.concatenate([nearest, near], axis=1), axis=1)
        point, j = pairs
        heights = np.empty(len(point))
        for one in np.unique(j):
            mask = j == one
            heights[mask] = self.along(int(segments[one]), en[point[mask]])
        weight = 1.0 / (shapely.distance(self.lines[segments][j], points[point]) + 1.0) ** 2
        total = np.bincount(point, weights=weight, minlength=len(en))
        return np.bincount(point, weights=weight * heights, minlength=len(en)) / total

    def on_bridge(self, poly):
        """The raised roads (and bridges at street level in the data, as
        fitted) running on a bridge outline (at least MIN_INSIDE of them, or
        half), for bridges.py's decks to follow: a function of
        (N, 2) points giving their heights (field()) and how much those count
        over the water (0..1: near the roads, where the survey saw them), or
        None if none run on it. Not paths and walkways, nor roads under another
        one on the bridge (a double-decker's lower roadways: the deck is the
        top one)."""
        found = self.tree.query(poly, predicate="intersects")
        d = self.data
        fitted = np.isin(found, list(self.fitted))
        found = found[(self.raised[found] | fitted) & ~self.stacked[found] & (d["rw"][found] != PATH)
                      & ~self.walkway[found]]
        if not len(found):
            return None
        inside = shapely.length(shapely.intersection(self.lines[found], poly))
        found = found[inside >= np.minimum(MIN_INSIDE, 0.5 * shapely.length(self.lines[found]))]
        if not len(found):
            return None
        tree = shapely.STRtree(self.lines[found])
        keep = []
        for k in found:
            s, h = self.stations(int(k))
            en = shapely.get_coordinates(shapely.line_interpolate_point(self.lines[k], s))
            points = shapely.points(en)
            point, other = tree.query(points, predicate="dwithin", distance=MAX_WIDTH)
            other_k = found[other]
            near = (other_k != k) & (shapely.distance(self.lines[other_k], points[point]) <= self.width[other_k] / 2.0)
            covered = np.zeros(len(s), dtype=bool)
            for i, j in zip(point[near], other_k[near]):
                if not covered[i] and self.along(int(j), en[i:i + 1])[0] >= h[i] + COVER_GAP:
                    covered[i] = True
            if covered.mean() < 0.5:
                keep.append(int(k))
        if not keep:
            return None
        keep = np.array(keep)
        lines = self.lines[keep]
        tree = shapely.STRtree(lines)

        def heights(en):
            en = np.asarray(en, np.float64).reshape(-1, 2)
            if len(en) == 0:
                return np.zeros(0), np.zeros(0)
            points = shapely.points(en)
            nearest = tree.query_nearest(points, return_distance=False, all_matches=False)[1]
            gap = shapely.distance(lines[nearest], points) - self.width[keep][nearest] / 2.0
            seen = np.zeros(len(en))
            for one in np.unique(nearest):
                mask = nearest == one
                k = int(keep[one])
                if k not in self.followed:
                    continue
                s = self.fitted[k][0]
                followed = s[self.followed[k]]
                if not len(followed):
                    continue
                # (Between stations the survey saw, the fit holds over a gap
                # of a few misses.)
                at = shapely.line_locate_point(lines[one], points[mask])
                miss = np.abs(at[:, None] - followed[None, :]).min(axis=1)
                seen[mask] = 1.0 - np.clip((miss - SEEN_GAP[0]) / (SEEN_GAP[1] - SEEN_GAP[0]), 0.0, 1.0)
            near = 1.0 - np.clip((gap - ROAD_REACH[0]) / (ROAD_REACH[1] - ROAD_REACH[0]), 0.0, 1.0)
            return self.field(en, keep), seen * near
        return heights

    def approach(self, en: np.ndarray) -> np.ndarray:
        """Where a bridge's approach (bridges.py) meets the land: the street,
        or the raised road it continues as."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        street = self.grade(en)
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
    structure = network.structure
    taken = structure.footprint if structure is not None else shapely.Polygon()  # cantilever.build's
    if network.trenches is not None and network.trenches.claimed:
        # The bridges over the sunken roads' cuts are trenches.build's.
        taken = shapely.union_all([taken] + network.trenches.claimed)
    for outline, name in zip(data["outlines"], data["outline_names"]):
        for part in polygons_of(outline, 50.0):
            if shapely.area(shapely.intersection(part, taken)) > 0.5 * part.area:
                continue
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
    # Also off the hand-made bridges (bridges.build's "hand_made"): the data
    # codes some of their walkways as raised roads (the High Bridge's).
    over_water += buckets.get("hand_made", [])
    keep_out = shapely.union_all(shapely.buffer(over_water, 1.0)) if over_water else shapely.Polygon()
    shapely.prepare(keep_out)
    network.keep_out = keep_out  # the bridges' outlines (els.py leaves them alone too)
    # Decks that may carry sidewalks (deck_walks): bridges, along their axis...
    network.walk_areas = [(part, bridges._axis(part)[0]) for part in over_water]
    wet_outlines = shapely.union_all(wet_outlines) if wet_outlines else shapely.Polygon()

    roads = np.flatnonzero(network.raised & ~network.stacked)
    builders = {level: MeshBuilder() for level in level_sizes}
    lamps = []
    overhead = _bridge_overhead(buckets.get("lod0", {}), network, land)  # what's high over the ground
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
        strips = shapely.buffer(network.lines[members], network.width[members] / 2.0, quad_segs=2)
        area = shapely.union_all(list(strips) + groups.get(group, []))
        area = shapely.difference(area, shapely.union(keep_out, taken))
        tree = shapely.STRtree(network.lines[members])
        for poly in _over_land(polygons_of(area, 20.0), land, wet_outlines):
            poly = shapely.orient_polygons(shapely.simplify(poly, 0.2))
            segs = members[tree.query(poly, predicate="intersects")]
            if len(segs) == 0:
                continue

            def deck_y(en, segs=segs):
                return network.field(en, segs)
            top = _add_deck(poly, deck_y, network, builders, top_kind=GROUND_ROAD)
            if top is not None:
                overhead.append(_overhead(top, network))
                decks += 1
                # ... and raised streets, along them.
                streets = segs[np.isin(data["rw"][segs], (STREET, BRIDGE))]
                if len(streets):
                    network.walk_areas.append((poly, streets))
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
    covered = shapely.union_all([keep_out] + list(on_land) + (network.trenches.claimed if network.trenches else []))
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
    buckets["overhead"] = [o for o in overhead if o is not None and not o.is_empty]


def _overhead(top: np.ndarray, network: Network):
    """The part of a deck's top (lod0 triangles, Godot space) at least
    GHOST_GAP above the street under it, or None."""
    en = top[:, :, [0, 2]] * np.array([1.0, -1.0])
    gap = top[:, :, 1] - network.street(en.reshape(-1, 2)).reshape(-1, 3)
    high = (gap >= GHOST_GAP).all(axis=1)
    if not high.any():
        return None
    return shapely.union_all(shapely.polygons(np.concatenate([en[high], en[high][:, :1]], axis=1)), grid_size=0.01)


def _bridge_overhead(found: dict, network: Network, land) -> list:
    """_overhead for the bridges' decks over land (their approaches), per tile."""
    out = []
    for pos, _, uv2, front in found.values():
        top = pos[(uv2[:, 0, 0] == GROUND_ROAD) & (front[:, 1] > 0.9)]
        if len(top) == 0:
            continue
        middle = top.mean(axis=1)
        top = top[shapely.contains_xy(land, middle[:, 0], -middle[:, 2])]
        if len(top):
            out.append(_overhead(top, network))
    return out


def prepare_sidewalks() -> dict:
    """The planimetric sidewalk outlines near bridges and raised roads (see
    WALK_REACH), for deck_walks."""
    near = [shape(f["geometry"]) for f in load_features("transport_structures")
            if str(f["properties"].get("feat_code")) == BRIDGE_CODE]
    near = list(shapely.buffer(shapely.make_valid(project(np.array(near, dtype=object))), WALK_REACH))
    raised = [shape(f["geometry"]) for f in load_features("centerline")
              if max(int(f["properties"].get("from_level_code") or AT_GRADE),
                     int(f["properties"].get("to_level_code") or AT_GRADE)) > int(AT_GRADE)]
    near += list(shapely.buffer(project(np.array(raised, dtype=object)), WALK_REACH))
    tree = shapely.STRtree(np.array(near, dtype=object))
    sidewalks = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in load_features("sidewalks")],
                                                    dtype=object)))
    keep = np.zeros(len(sidewalks), dtype=bool)
    keep[tree.query(sidewalks, predicate="intersects")[0]] = True
    return {"geoms": sidewalks[keep]}


def deck_walks(network: Network, sidewalks: np.ndarray) -> np.ndarray:
    """Walking lanes (east/north lines) on the sidewalks of decks that carry
    them (network.walk_areas, from build()): around the middle of each
    sidewalk outline on such a deck that runs along it."""
    tree = shapely.STRtree(sidewalks)
    out = []
    for area, along in getattr(network, "walk_areas", []):
        for k in tree.query(area, predicate="intersects"):
            for piece in polygons_of(shapely.intersection(sidewalks[k], area), WALK_MIN_AREA):
                u, _, center, _ = bridges._axis(piece)
                if along.dtype.kind == "f":
                    direction = along
                else:
                    line = network.lines[along[np.argmin(shapely.distance(network.lines[along], shapely.Point(center)))]]
                    _, normal = markings._frame(line, np.array([line.project(shapely.Point(center))]))
                    direction = np.array([normal[0][1], -normal[0][0]])
                if abs(float(u @ direction)) < WALK_ALONG:
                    continue  # a sidewalk under the deck, crossing it
                width = 2.0 * piece.area / max(piece.length, 1e-6)
                for middle in polygons_of(shapely.buffer(piece, -max(width / 2 - 0.3, 0.1)), 0.0):
                    out.append(shapely.LineString(middle.exterior.coords))
    return np.array(out, dtype=object)


def walks_on_decks(walks, tree, buckets: dict, bounds) -> list:
    """deck_walks' lanes in a near tile (bounds, a box), on the decks under
    them (from the lod0 bridge buckets: the highest roadway, hand-made
    walkway or paved deck, the Brooklyn Heights Promenade's): [(N, 3) east,
    north, height]."""
    if tree is None:
        return []
    hits = tree.query(bounds, predicate="intersects")
    if not len(hits):
        return []
    surface = surface_for(buckets, bounds, (GROUND_ROAD, STRUCTURE_WALKWAY, GROUND_PAVERS))
    out = []
    for line in walks[hits]:
        for piece in lines_of(shapely.intersection(line, bounds)):
            coords = np.asarray(shapely.segmentize(piece, WALK_STEP).coords)[:, :2]
            y, found = surface.height(coords, np.full(len(coords), 1e4))
            for start, stop in _runs(found[:-1] & found[1:]):
                out.append(np.column_stack([coords[start:stop + 1], y[start:stop + 1]]))
    return out


def roads_under_decks(network: Network, overhead: list, roads: np.ndarray) -> dict:
    """The roadbed polygons (prepare's ground["roads"]) that reach under
    decks away from the streets at grade (see GHOST_GAP), cut back to the
    streets: {index: what's left}."""
    pieces = [p for o in overhead for p in polygons_of(o, 1.0)]
    if not pieces:
        return {}
    area = shapely.union_all(pieces, grid_size=0.01)
    near = network.under_tree.query(area, predicate="dwithin", distance=40.0)
    corridors = shapely.union_all(shapely.buffer(network.under_lines[near], network.under_half[near] + STREET_MARGIN,
                                                 quad_segs=4)) if len(near) else shapely.Polygon()
    ghost = np.array(polygons_of(shapely.difference(area, corridors), 4.0), dtype=object)
    if len(ghost) == 0:
        return {}
    tree = shapely.STRtree(ghost)
    hits = tree.query(roads, predicate="intersects")
    out = {}
    for k in np.unique(hits[0]):
        cut = shapely.union_all(ghost[hits[1][hits[0] == k]])
        left = shapely.make_valid(shapely.difference(roads[k], cut))
        if roads[k].area - left.area > 1.0:
            out[int(k)] = shapely.MultiPolygon(polygons_of(left, 0.5)) if polygons_of(left, 0.5) else shapely.Polygon()
    return out


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
        for ring in (r for part in polygons_of(dense) for r in (part.exterior, *part.interiors)):
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
    if poly.is_empty:
        return None
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
    candidates = candidates[~network.under_sunken[candidates]]
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
            street = network.street(np.vstack([ends[0] - direction * 3.0, ends[1] + direction * 3.0]))
            length = float(np.linalg.norm(ends[1] - ends[0]))

            def deck_y(en, a=ends[0], d=direction, street=street, length=length):
                t = np.clip(((np.asarray(en, np.float64).reshape(-1, 2) - a) @ d) / max(length, 1e-6), 0.0, 1.0)
                return street[0] + (street[1] - street[0]) * t + CROSSING_LIFT
            out.append((shapely.orient_polygons(poly), deck_y))
    return out


def _plain_profile(poly, network: Network):
    """Heights for an outline no raised road runs through: from the ground at
    its two ends (along its long axis), lifted LEVEL_RISE over streets that
    pass under it. Returns (deck_y, carries a street) or (None, False) if it
    wouldn't rise MIN_RISE above the street anywhere."""
    u, v, center, length = bridges._axis(poly)
    ring = np.asarray(shapely.segmentize(poly.exterior, 2.0).coords)[:, :2]
    s = (ring - center) @ u
    s_min, s_max = float(s.min()), float(s.max())
    strip = min(END_STRIP, 0.2 * (s_max - s_min))
    ends = (float(np.median(network.grade(ring[s <= s_min + strip]))),
            float(np.median(network.grade(ring[s >= s_max - strip]))))

    # Streets on it (running along it) and under it (crossing it).
    lifts = []
    carries = False
    for k in network.under_tree.query(poly, predicate="intersects"):
        if network.under_sunken[k]:
            continue  # (in a cut or a tunnel, trenches.py's)
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
            # a wide road, then one by one the middles of two-way streets
            # running underneath, the middle, and near the edges.
            options = [-half / 2, half / 2] + _medians_under(point, across, half, network) + [0.0, -(half - 2.0),
                                                                                              half - 2.0]
            spots = point + np.outer(options, across)
            ok = shapely.covers(poly, shapely.points(spots)) & _clear_of_streets(spots, network)
            chosen = [0, 1] if width >= WIDE_DECK and ok[0] and ok[1] else []
            for i in np.flatnonzero(ok[2:]) + 2:
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
    u, v, center, length = bridges._axis(poly)
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
    # Grouped by sorting (a mask per tile is slow with the els' many tiles).
    order = np.lexsort((jj, ii))
    breaks = np.flatnonzero((np.diff(ii[order]) != 0) | (np.diff(jj[order]) != 0)) + 1
    out = {}
    for group in np.split(order, breaks):
        out[(int(ii[group[0]]), int(jj[group[0]]))] = (pos[group], uv[group], uv2[group], front[group])
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

    def candidates(self, en: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Every deck top under (N, 2) points: (point index, height) pairs."""
        en = np.asarray(en, np.float64).reshape(-1, 2)
        if self.tree is None or len(en) == 0:
            return np.zeros(0, dtype=np.int64), np.zeros(0)
        point, tri = self.tree.query(shapely.points(en), predicate="intersects")
        return point, self.interpolate(en[point], tri)

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
    surface = surface_for(buckets, bounds, OVERHEAD)
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
    not one passing overhead (easing off from a meter closer). Raised roads on
    land (and double-deckers' lower roadways anywhere) keep to their own
    height where the nearest deck is further off than SNAP_GAP (another road's deck over or under them, as on
    a bridge carrying ramps below its roadway), easing onto the deck closer
    in, so their lanes meet the roads they lead to; `found` is then False
    (no paint)."""
    expected = network.along(k, en)
    y, found = surface.height(en, expected)
    if not found.any():
        return y, found
    on_land = shapely.contains_xy(land, en[:, 0], en[:, 1])
    if network.raised[k] or network.data["rw"][k] != BRIDGE:
        off = np.abs(y - expected)
        near, far = SNAP_GAP if network.raised[k] else (GRADE_DECK - 1.0, GRADE_DECK)
        take = np.clip((far - off) / (far - near), 0.0, 1.0)
        take = np.where(found & (on_land | network.under[k]), take, 1.0)
        y = expected + (y - expected) * take
        found &= take > 0.0
    return y, found


def _tracked(network: Network, surface: DeckSurface, k: int, en: np.ndarray, land) -> np.ndarray:
    """Heights along a lane (points (N, 2) in driving order) of segment k, a
    bridge at street level in the data: from the road's own height at an end
    (Network.along, where it meets the streets), on along the deck it's on
    (the deck under each point nearest the height before, if within
    TRACK_STEP and TRACK_GRADE of it), else at its own height on land (not
    onto a deck passing overhead); over the water, the deck nearest, if it's
    within UNDER_CLEAR. Tracked from both ends, the steadier way wins."""
    own = network.along(k, en)
    point, decks = surface.candidates(en)
    wet = ~shapely.contains_xy(land, en[:, 0], en[:, 1])
    under = [decks[point == i] for i in range(len(en))]

    def walk(order):
        y = np.empty(len(en))
        before, last = own[order[0]], order[0]
        for i in order:
            reach = TRACK_STEP + TRACK_GRADE * float(np.hypot(*(en[i] - en[last])))
            last = i
            options = under[i]
            close = options[np.abs(options - before) <= reach]
            if len(close):
                y[i] = close[np.argmin(np.abs(close - before))]
            else:
                # Over the water, the deck nearest, unless it's well over or
                # under (another road's: then its own height, as if on a low
                # deck the data folds into that road's outline).
                nearest = options[np.argmin(np.abs(options - before))] if len(options) else np.inf
                y[i] = nearest if wet[i] and abs(nearest - before) <= UNDER_CLEAR else own[i]
            before = y[i]
        return y
    forward = walk(np.arange(len(en)))
    backward = walk(np.arange(len(en))[::-1])
    return forward if np.abs(np.diff(forward)).sum() <= np.abs(np.diff(backward)).sum() else backward


def lanes(network: Network, buckets: dict, bounds, land) -> list:
    """Driving lanes (traffic.lanes' format) of the raised roads, ramps and
    bridges whose middle is in `bounds` (a near tile's box), at their deck's
    height (from the lod0 bridge buckets); lanes over water with no deck under
    them (bridges left out of the world) are dropped, and so are footpaths
    the data codes as bridges (no lanes, no width) along a hand-made bridge's
    walkways (bridge_landmarks: the Brooklyn Bridge's promenade, the
    Manhattan Bridge's walkway and bikeway, the High Bridge), and walkways
    and bikeways (non-vehicular in the data). Bridges at street level in the
    data follow the deck they're on (_tracked)."""
    surface = surface_for(buckets, bounds)
    walkways = surface_for(buckets, bounds, (STRUCTURE_WALKWAY,))
    out = []
    attrs = network.attrs
    for k in network.tree.query(bounds, predicate="intersects"):
        k = int(k)
        if network.data["rw"][k] == PATH or network.walkway[k]:
            continue
        footpath = network.data["lanes"][k] == 0 and network.data["width"][k] == 0

        def height(en, k=k):
            return road_height(network, surface, k, en, land)[0]
        tracked = not network.raised[k] and network.data["rw"][k] == BRIDGE
        for lane, info in traffic.lanes(attrs, np.array([k]), bounds, height):
            if tracked:
                lane[:, 2] = _tracked(network, surface, k, lane[:, :2], land)
            _, found = surface.height(lane[:, :2], lane[:, 2])  # a deck at all (not a bridge left out)
            wet = ~shapely.contains_xy(land, lane[:, 0], lane[:, 1])
            if (wet & ~found).any():
                continue
            if footpath and walkways.tree is not None and walkways.height(lane[:, :2], lane[:, 2])[1].any():
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
        if network.data["rw"][k] == PATH or network.walkway[k]:
            continue

        def height(en, k=k):
            return road_height(network, surface, k, en, land)[0] + MARKING_LIFT
        for kind, (quads, uv, _) in markings.quads(network.attrs, np.array([k]), bounds.bounds, None).items():
            _, found = road_height(network, surface, k, quads.reshape(-1, 2), land)
            ok = found.reshape(-1, 4).all(axis=1)
            if ok.any():
                builder.add_draped_triangles(quads[ok][:, halves].reshape(-1, 3, 2), cell, height, (kind, 0.0),
                                             uv=uv[ok][:, halves].reshape(-1, 3, 2))
