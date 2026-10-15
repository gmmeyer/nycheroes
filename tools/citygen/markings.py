"""Paint on the streets, from the city's street centerlines (CSCL): double
yellow center lines on two-way streets, dashed white lines between lanes,
edge lines on highways, and at intersections high-visibility crosswalks and
stop lines.

Lines are strips of quads up to LINE_PIECE long, with uv along and across
the strip; the game's shader paints the dashes and the double line from the
uv (see common.GROUND_MARKING_*), so a line costs a few vertices, not one
quad per dash. A strip quad that would hang over a curb or median is left
out (keep() checks its corners against the road surface): no polygon
overlays. Crosswalks and stop lines are one quad each, from curb to curb,
measured across the road surface. Lines are laid out from each segment's
own start, so every tile that touches a segment makes the same paint and
keeps the quads centered inside it.

prepare() makes data/cache/centerline.pkl; build_tiles.py calls quads() per
lod0 tile and drapes them over the road (common.MARKING_LIFT above it).
"""

import numpy as np
import shapely
from shapely.geometry import LineString, shape

from common import (FEET, GROUND_MARKING_CROSSWALK, GROUND_MARKING_DASHED, GROUND_MARKING_WHITE,
                    GROUND_MARKING_YELLOW, lines_of, load_features, project)

# Roadway types (CSCL rw_type) that get paint; only segments at street level
# (level code 13) do: elevated and sunken roads aren't modeled yet.
STREET = 1
HIGHWAY = 2
AT_GRADE = "13"
# Traffic direction (CSCL trafdir): with, against or both ways along the line.
WITH, AGAINST, BOTH = 1, 2, 0

LINE_WIDTH = 0.15         # lane lines and edge lines (bold, for the look)
YELLOW_WIDTH = 0.45       # the double yellow line's strip: two 0.15 m lines, 0.15 m apart
DASH = 3.0                # the shader's dashes: 3 m of every 12 (New York's 10 and 30 feet)
LINE_PIECE = 8.0          # strips are cut at least this often (and at every bend)
LANE_WIDTH = 3.3          # when the street's width doesn't say
PARKING_WIDTH = 2.4
MIN_LANE, MAX_LANE = 2.8, 3.8
CENTER_LINE_MIN_WIDTH = 9.0  # narrower two-way streets have no center line

# Intersections: where three or more painted segments meet. Crosswalks start
# this far past the crossing street's curb line and are this deep; stop lines
# come after them. Both stop this far short of the curbs.
CROSSWALK_SETBACK = 1.0
CROSSWALK_DEPTH = 3.0
STOP_GAP = 1.2
STOP_WIDTH = 0.45
CURB_GAP = 0.2
# Road pieces closer than this across a crosswalk count as one road.
ROAD_SEAM = 0.6
# Crosswalks only at intersections with a bigger street (this many lanes or
# this wide), and only across streets at least this wide.
MAJOR_LANES, MAJOR_WIDTH = 2, 12.0
CROSSWALK_MIN_WIDTH = 8.0
DEFAULT_HALF_WIDTH = 5.0
MAX_SETBACK = 25.0


def prepare() -> dict:
    """Painted street segments: lines (east/north) and per-segment attributes,
    with each end's intersection setback (0 where it isn't an intersection)."""
    lines, rows = [], []
    for feat in load_features("centerline"):
        p = feat["properties"]
        if p.get("from_level_code") != AT_GRADE or p.get("to_level_code") != AT_GRADE:
            continue
        rw = int(p.get("rw_type") or 0)
        trafdir = {"FT": WITH, "TF": AGAINST, "TW": BOTH}.get(p.get("trafdir"))
        if rw not in (STREET, HIGHWAY) or trafdir is None or p.get("status", "2") != "2":
            continue
        geom = shapely.line_merge(shape(feat["geometry"]))
        for part in shapely.get_parts(geom):
            lines.append(part)
            rows.append((rw, trafdir, int(float(p.get("number_travel_lanes") or 0)),
                         int(float(p.get("number_park_lanes") or 0)), float(p.get("streetwidth") or 0) * FEET))
    lines = project(np.array(lines, dtype=object))
    attrs = np.array(rows, dtype=np.float64)
    keep = shapely.length(lines) > 1.0
    lines, attrs = lines[keep], attrs[keep]
    rw, lanes, width = attrs[:, 0], attrs[:, 2], attrs[:, 4]

    # Ends meeting at the same point (to 0.5 m) form a node.
    starts = shapely.get_coordinates(shapely.get_point(lines, 0))
    ends = shapely.get_coordinates(shapely.get_point(lines, -1))
    keys = np.round(np.vstack([starts, ends]) * 2.0).astype(np.int64)
    _, node, degree = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
    node = node.reshape(-1)
    count = len(lines)
    half = np.where(width > 0, width / 2.0, np.where(lanes > 0, (lanes * LANE_WIDTH + attrs[:, 3] * PARKING_WIDTH) / 2.0,
                                                    DEFAULT_HALF_WIDTH))
    both_half = np.concatenate([half, half])
    major_end = np.concatenate([(lanes >= MAJOR_LANES) | (width >= MAJOR_WIDTH)] * 2) & (np.concatenate([rw, rw]) == STREET)
    widest = np.zeros(degree.size)
    second = np.zeros(degree.size)
    major = np.zeros(degree.size, dtype=bool)
    # The widest and second-widest street at each node: an end's setback is the
    # widest *other* street's half width.
    order = np.argsort(both_half)
    for e in order:
        n = node[e]
        second[n] = widest[n]
        widest[n] = both_half[e]
    np.logical_or.at(major, node, major_end)
    other = np.where(both_half >= widest[node], second[node], widest[node])
    setback = np.minimum(other + CROSSWALK_SETBACK, MAX_SETBACK)
    is_crossing = degree[node] >= 3
    setback = np.where(is_crossing, setback, 0.0)
    return {
        "lines": lines,
        "rw": rw.astype(np.int8),
        "trafdir": attrs[:, 1].astype(np.int8),
        "lanes": lanes.astype(np.int16),
        "parking": attrs[:, 3].astype(np.int16),
        "width": width.astype(np.float32),
        "setback": setback.reshape(2, count).T.astype(np.float32),  # (start, end)
        "major": (major[node] & is_crossing).reshape(2, count).T,
    }


def quads(data: dict, segments: np.ndarray, center_box, road) -> dict:
    """Paint {kind: (quads (Q, 4, 2) east/north corners, uv (Q, 4, 2), check (Q,))}
    for these segments, keeping quads whose centers fall inside center_box
    (min_e, min_n, max_e, max_n). `road` is the (prepared) road surface around
    them; quads with `check` set still have to pass keep()."""
    out = {}
    for k in segments:
        _segment(data, int(k), out, road)
    min_e, min_n, max_e, max_n = center_box
    result = {}
    for kind, parts in out.items():
        q = np.concatenate([part[0] for part in parts])
        uv = np.concatenate([part[1] for part in parts])
        check = np.concatenate([np.full(len(part[0]), part[2]) for part in parts])
        c = q.mean(axis=1)
        inside = (c[:, 0] >= min_e) & (c[:, 0] < max_e) & (c[:, 1] >= min_n) & (c[:, 1] < max_n)
        if inside.any():
            result[kind] = (q[inside], uv[inside], check[inside])
    return result


def keep(q: np.ndarray, road) -> np.ndarray:
    """Which (Q, 4, 2) quads lie on the (prepared) road surface, all corners in."""
    inside = shapely.contains_xy(road, q[..., 0].ravel(), q[..., 1].ravel()).reshape(-1, 4)
    return inside.all(axis=1)


def _add(out: dict, kind: int, quads: np.ndarray, uv: np.ndarray, check: bool) -> None:
    if len(quads):
        out.setdefault(kind, []).append((quads, uv, check))


def _segment(data: dict, k: int, out: dict, road) -> None:
    line = data["lines"][k]
    length = line.length
    rw, trafdir = int(data["rw"][k]), int(data["trafdir"][k])
    lanes, parking, width = int(data["lanes"][k]), int(data["parking"][k]), float(data["width"][k])
    start_setback, end_setback = (float(v) for v in data["setback"][k])

    if lanes <= 0:
        lanes = 2 if (trafdir == BOTH and width >= CENTER_LINE_MIN_WIDTH) else 1
    if width > 0:
        lane = float(np.clip((width - parking * PARKING_WIDTH) / lanes, MIN_LANE, MAX_LANE))
    else:
        lane = LANE_WIDTH

    # Lines stop short of intersections: past the crosswalk and stop line.
    trim = CROSSWALK_DEPTH + STOP_GAP + STOP_WIDTH + 1.0
    a = start_setback + trim if start_setback > 0 else 0.0
    b = length - (end_setback + trim if end_setback > 0 else 0.0)
    if b - a > DASH:
        dashed, solid, yellow = [], [], False
        if trafdir == BOTH:
            yellow = lanes >= 2 and (width == 0 or width >= CENTER_LINE_MIN_WIDTH)
            dashed = [side * j * lane for j in range(1, lanes // 2) for side in (-1, 1)]
        else:
            dashed = [(j - lanes / 2) * lane for j in range(1, lanes)]
            if rw == HIGHWAY:
                solid = [-(lanes / 2) * lane - 0.3, (lanes / 2) * lane + 0.3]
        if yellow or dashed or solid:
            s = _stations(line, a, b)
            if yellow:
                _add(out, GROUND_MARKING_YELLOW, *_strip(line, s, 0.0, YELLOW_WIDTH), True)
            for offset in solid:
                _add(out, GROUND_MARKING_WHITE, *_strip(line, s, offset, LINE_WIDTH), True)
            for offset in dashed:
                _add(out, GROUND_MARKING_DASHED, *_strip(line, s, offset, LINE_WIDTH), True)

    if rw != STREET:
        return
    for at_start, setback, major in ((True, start_setback, data["major"][k][0]), (False, end_setback, data["major"][k][1])):
        if setback <= 0 or not major or setback + CROSSWALK_DEPTH + STOP_GAP + STOP_WIDTH > length / 2:
            continue
        span = width if width > 0 else lanes * lane + parking * PARKING_WIDTH
        if span < CROSSWALK_MIN_WIDTH:
            continue

        def along(d):  # distance along the line, from this end
            return d if at_start else length - d
        reach = span / 2 + 3.0
        middle = along(setback + CROSSWALK_DEPTH / 2)
        across = _road_across(line, middle, road, reach)
        if across is not None:
            _add(out, GROUND_MARKING_CROSSWALK, *_cross_quad(line, middle, across, CROSSWALK_DEPTH, True), False)
        # Stop line across the lanes coming toward the intersection.
        if not (trafdir == BOTH or (trafdir == WITH) != at_start):
            continue
        middle = along(setback + CROSSWALK_DEPTH + STOP_GAP + STOP_WIDTH / 2)
        across = _road_across(line, middle, road, reach)
        if across is None:
            continue
        lo, hi = across
        if trafdir == BOTH:
            # Traffic keeps right: arriving at the start, it travels against the
            # line, so its lanes are on the line's left; at the end, on its right.
            lo, hi = (max(lo, 0.0), hi) if at_start else (lo, min(hi, 0.0))
        if hi - lo > 1.0:
            _add(out, GROUND_MARKING_WHITE, *_cross_quad(line, middle, (lo, hi), STOP_WIDTH, False), False)


def _stations(line, a: float, b: float) -> np.ndarray:
    """Distances along the line from a to b where strips are cut: every bend,
    and at least every LINE_PIECE."""
    coords = np.asarray(line.coords)[:, :2]
    bends = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(coords, axis=0), axis=1))])
    even = np.linspace(a, b, max(2, int(np.ceil((b - a) / LINE_PIECE)) + 1))
    s = np.union1d(even, bends[(bends > a + 0.5) & (bends < b - 0.5)])
    return s


def _frame(line, s: np.ndarray):
    """Points at distances s along a line, and the unit left normals there."""
    s = np.clip(s, 0.0, line.length)
    points = shapely.get_coordinates(shapely.line_interpolate_point(line, s))
    step = np.minimum(0.5, line.length / 4)
    ahead = shapely.get_coordinates(shapely.line_interpolate_point(line, np.minimum(s + step, line.length)))
    behind = shapely.get_coordinates(shapely.line_interpolate_point(line, np.maximum(s - step, 0.0)))
    tangent = ahead - behind
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-9)
    return points, np.column_stack([-tangent[:, 1], tangent[:, 0]])


def _strip(line, s: np.ndarray, offset: float, width: float):
    """A strip `width` wide, centered `offset` to the left of the line, as
    quads between the points at distances s, and their uv (meters along the
    line, meters across from the strip's middle)."""
    points, normal = _frame(line, s)
    left = points + normal * (offset + width / 2)
    right = points + normal * (offset - width / 2)
    quads = np.stack([right[:-1], right[1:], left[1:], left[:-1]], axis=1)
    h = width / 2
    s0, s1 = s[:-1], s[1:]
    uv = np.stack([np.column_stack([s0, np.full_like(s0, -h)]), np.column_stack([s1, np.full_like(s1, -h)]),
                   np.column_stack([s1, np.full_like(s1, h)]), np.column_stack([s0, np.full_like(s0, h)])], axis=1)
    return quads, uv


def _road_across(line, s: float, road, reach: float):
    """The road surface across the line at distance s: (lo, hi) meters to the
    line's left (negative: right), short of the curbs, or None if the line
    isn't on the road there."""
    point, normal = _frame(line, np.array([s]))
    point, normal = point[0], normal[0]
    cut = shapely.intersection(LineString([point - normal * reach, point + normal * reach]), road)
    spans = sorted((float(t.min()), float(t.max()))
                   for t in (((np.asarray(part.coords)[:, :2] - point) @ normal) for part in lines_of(cut)))
    merged = []
    for lo, hi in spans:
        if merged and lo - merged[-1][1] < ROAD_SEAM:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    for lo, hi in merged:
        if lo - 0.5 <= 0.0 <= hi + 0.5 and hi - lo > 2 * CURB_GAP + 1.0:
            return lo + CURB_GAP, hi - CURB_GAP
    return None


def _cross_quad(line, s: float, across: tuple, depth: float, from_curb: bool):
    """A quad across the line at distance s, `depth` along it, spanning
    `across` (lo, hi) to its left; uv = (meters along 0..depth, meters across
    from the lo side if from_curb, else from the line)."""
    point, normal = _frame(line, np.array([s]))
    point, normal = point[0], normal[0]
    tangent = np.array([normal[1], -normal[0]])
    lo, hi = across
    half = tangent * (depth / 2)
    quad = np.array([point - half + normal * lo, point + half + normal * lo,
                     point + half + normal * hi, point - half + normal * hi])
    v0, v1 = (0.0, hi - lo) if from_curb else (lo, hi)
    uv = np.array([[0.0, v0], [depth, v0], [depth, v1], [0.0, v1]])
    return quad[None], uv[None]
