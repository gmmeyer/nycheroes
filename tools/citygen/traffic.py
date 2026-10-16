"""Traffic from the city's street centerlines (CSCL, prepared by markings.py):
driving lanes for the game's moving cars, and parked cars along the curbs.

Driving lanes follow the paint: the same lane count and width as the dashed
lines (markings.lane_layout), keeping right of the center line on two-way
streets, centered on one-way streets. Each lane runs from where it leaves an
intersection (the crossing street's curb line) to its stop line, or to the
curb line where no stop line is painted; the game drives cars through the
intersections between them. Lanes carry their segment's end nodes (ids shared
across tiles), speed limit, and the signal phase where they end
(markings.prepare: the same phase as the signal pole there).

Parked cars line the curbs of streets whose centerline has parking lanes
(CSCL number_park_lanes: 2 both sides, 1 the right-hand side), stopping short
of crosswalks, leaving fire hydrants 15 feet each side (the law) and bus stops
clear, and staying out of the travel lanes where the road is narrower than
the data says. Cars are drawn from a mix of models and paint colors per
street and side, so every tile that touches a segment makes the same cars.
"""

import numpy as np
import shapely

import markings
from common import (CAR_BOX_TRUCK, CAR_HATCHBACK, CAR_MINIVAN, CAR_PICKUP, CAR_SEDAN, CAR_SUV, CAR_TAXI,
                    CAR_VAN)
from markings import AGAINST, BOTH, CROSSWALK_DEPTH, HIGHWAY, STOP_GAP, STOP_WIDTH, STREET, WITH

STREET_SPEED = 11.2   # m/s: 25 mph, New York's default limit
HIGHWAY_SPEED = 17.9  # 40 mph
LANE_STEP = 20.0      # lane points at least this often (the road bends with the terrain every 20 m)
MIN_LANE_LENGTH = 1.0

# Car models (common.CAR_*): length, width, height (m), and their shares of
# parked cars.
CAR_SIZES = {
    CAR_SEDAN: (4.7, 1.85, 1.45), CAR_HATCHBACK: (4.2, 1.8, 1.5), CAR_SUV: (4.9, 1.95, 1.75),
    CAR_MINIVAN: (5.1, 2.0, 1.8), CAR_PICKUP: (5.7, 2.0, 1.85), CAR_VAN: (5.6, 2.05, 2.5),
    CAR_TAXI: (4.8, 1.85, 1.5), CAR_BOX_TRUCK: (7.5, 2.4, 3.3),
}
PARKED_MIX = {CAR_SEDAN: 0.34, CAR_HATCHBACK: 0.10, CAR_SUV: 0.30, CAR_MINIVAN: 0.07, CAR_PICKUP: 0.05,
              CAR_VAN: 0.08, CAR_TAXI: 0.03, CAR_BOX_TRUCK: 0.03}
# Paint colors 0..11 (the game's palette: white, black, silver, mid gray, dark
# gray, dark blue, red, blue, dark green, beige, brown, orange), as common
# as on real cars.
PAINT_MIX = (0.24, 0.21, 0.12, 0.12, 0.06, 0.05, 0.08, 0.05, 0.02, 0.02, 0.02, 0.01)
EMPTY_SPACE = 0.12      # share of spaces left empty
GAP = (0.6, 1.8)        # meters between parked cars
SIZE_JITTER = 0.03
CURB_GAP = 0.15         # wheels to curb (markings' road spans already stop 0.2 m short)
NO_PARKING = 4.5        # meters past a crosswalk before the first car
SEGMENT_GAP = 0.3       # where a street just continues into the next segment
TRAVEL_OVERLAP = 0.3    # parked cars may reach this far into the outer travel lane
# Kept clear along the curb on either side of: fire hydrants (15 feet), bus stops.
HYDRANT_CLEAR = 4.6
BUS_STOP_CLEAR = 15.0
BLOCKER_REACH = 8.0     # how far from the curb line a hydrant or shelter still counts

_MODELS = np.array(sorted(CAR_SIZES))
_SIZES = np.array([CAR_SIZES[m] for m in _MODELS])
_MODEL_SHARES = np.array([PARKED_MIX[m] for m in _MODELS])
_PAINT_SHARES = np.array(PAINT_MIX)


def ways(data: dict, k: int) -> list[tuple[bool, list[float]]]:
    """Segment k's directions of travel: (along the line?, lane offsets to the
    line's left, from the center line out)."""
    trafdir = int(data["trafdir"][k])
    lanes, lane = markings.lane_layout(data, k)
    if trafdir == BOTH:
        with_lanes = max(lanes // 2, 1)
        against_lanes = max(lanes - lanes // 2, 1)
        return [(True, [-(j + 0.5) * lane for j in range(with_lanes)]),
                (False, [(j + 0.5) * lane for j in range(against_lanes)])]
    # One way, centered: lane 0 is the left-most in the direction of travel.
    offsets = [(lanes / 2 - 0.5 - j) * lane for j in range(lanes)]
    if trafdir == WITH:
        return [(True, offsets)]
    return [(False, [-o for o in offsets])]


def lanes(data: dict, segments: np.ndarray, bounds, height) -> list[tuple[np.ndarray, tuple]]:
    """Driving lanes of the segments whose middle is in `bounds` (a box):
    [(points (P, 3) east, north, height in driving order), (from node, to node,
    speed, lane, lanes its way, phase or -1, how it ends: 0 the street goes
    on, 1 at an intersection, 2 at one where it has the right of way))].
    `height(en)` gives the road's height."""
    min_e, min_n, max_e, max_n = bounds.bounds
    out = []
    for k in segments:
        k = int(k)
        rw = int(data["rw"][k])
        if rw not in (STREET, HIGHWAY):
            continue
        line = data["lines"][k]
        middle = line.interpolate(0.5, normalized=True)
        if not (min_e <= middle.x < max_e and min_n <= middle.y < max_n):
            continue
        length = line.length
        speed = HIGHWAY_SPEED if rw == HIGHWAY else STREET_SPEED
        for forward, offsets in ways(data, k):
            first, last = (0, 1) if forward else (1, 0)
            # Leave the intersection behind at its curb line; stop at the stop
            # line, or the curb line where there's none.
            enter = float(data["setback"][k][first]) if data["crossing"][k][first] else 0.0
            stop = 0.0
            if data["crossing"][k][last]:
                stop = float(data["setback"][k][last])
                if data["major"][k][last]:
                    stop += CROSSWALK_DEPTH + STOP_GAP + STOP_WIDTH
            if length - stop - enter < MIN_LANE_LENGTH:
                continue
            # Distances along the line, in driving order.
            if forward:
                s = _stations(line, enter, length - stop)
            else:
                s = _stations(line, stop, length - enter)[::-1]
            points, normal = markings._frame(line, s)
            info = (float(data["nodes"][k][first]), float(data["nodes"][k][last]), speed,
                    float(data["phase"][k][last]),
                    (2.0 if data["priority"][k][last] else 1.0) if data["crossing"][k][last] else 0.0)
            for j, offset in enumerate(offsets):
                en = points + normal * offset
                out.append((np.column_stack([en, height(en)]),
                            (info[0], info[1], info[2], float(j), float(len(offsets)), info[3], info[4])))
    return out


def parked_cars(data: dict, segments: np.ndarray, bounds, road, blockers: tuple) -> dict:
    """Parked cars at the curbs of these segments, centered in `bounds` (a box),
    on the (prepared) road surface `road`. `blockers` is (points (M, 2),
    clearances (M,)): fire hydrants and bus stops to keep clear along the curb.
    Returns arrays en, yaw, model, paint, length, height, seed."""
    min_e, min_n, max_e, max_n = bounds.bounds
    found = []
    for k in segments:
        k = int(k)
        parking = int(data["parking"][k])
        if parking <= 0 or int(data["rw"][k]) != STREET:
            continue
        line = data["lines"][k]
        length = line.length
        trafdir = int(data["trafdir"][k])
        # Travel lanes' outer edges, to the line's left (markings.lane_layout).
        lanes, lane = markings.lane_layout(data, k)
        offsets = [o for _, way in ways(data, k) for o in way]
        travel = (min(offsets) - lane / 2, max(offsets) + lane / 2)
        # One parking lane: on the right-hand side of the traffic.
        right_of_traffic = 1 if trafdir == AGAINST else -1
        sides = (-1, 1) if parking >= 2 else (right_of_traffic,)
        a = (float(data["setback"][k][0]) + CROSSWALK_DEPTH + NO_PARKING) if data["crossing"][k][0] else SEGMENT_GAP
        b = length - ((float(data["setback"][k][1]) + CROSSWALK_DEPTH + NO_PARKING)
                      if data["crossing"][k][1] else SEGMENT_GAP)
        if b - a < 4.0:
            continue
        for side in sides:  # -1 the line's right, 1 its left
            rng = np.random.default_rng([k, side + 1])
            count = int((b - a) / 4.0) + 2
            model = rng.choice(len(_MODELS), size=count, p=_MODEL_SHARES)
            size = _SIZES[model] * (1.0 + rng.uniform(-SIZE_JITTER, SIZE_JITTER, (count, 1)))
            pitch = size[:, 0] + rng.uniform(*GAP, count)
            start = a + np.concatenate([[0.0], np.cumsum(pitch)[:-1]])
            center = start + size[:, 0] / 2
            keep = (center + size[:, 0] / 2 <= b) & (rng.random(count) >= EMPTY_SPACE)
            paint = rng.choice(len(_PAINT_SHARES), size=count, p=_PAINT_SHARES)
            seed = rng.random(count)
            jitter = rng.uniform(-0.08, 0.08, count)
            # Facing the traffic on its side of the street.
            forward = trafdir == WITH or (trafdir == BOTH and side < 0)
            keep &= ~_blocked(line, center, size[:, 0], side, travel, blockers)
            points, normal = markings._frame(line, center)
            near = (points[:, 0] >= min_e - 10) & (points[:, 0] < max_e + 10) & \
                   (points[:, 1] >= min_n - 10) & (points[:, 1] < max_n + 10)
            for c in np.flatnonzero(keep & near):
                across = markings._road_across(line, float(center[c]), road, (travel[1] - travel[0]) / 2 + 12.0)
                if across is None:
                    continue
                half_width = size[c, 1] / 2
                if side > 0:
                    offset = across[1] - CURB_GAP - half_width
                    if offset - half_width < travel[1] - TRAVEL_OVERLAP:
                        continue
                else:
                    offset = across[0] + CURB_GAP + half_width
                    if offset + half_width > travel[0] + TRAVEL_OVERLAP:
                        continue
                tangent = np.array([normal[c, 1], -normal[c, 0]]) * (1.0 if forward else -1.0)
                en = points[c] + normal[c] * (offset + jitter[c])
                if not (min_e <= en[0] < max_e and min_n <= en[1] < max_n):
                    continue
                found.append((en[0], en[1], np.arctan2(tangent[0], -tangent[1]) + jitter[c] * 0.2,
                              _MODELS[model[c]], paint[c], size[c, 0], size[c, 1], size[c, 2], seed[c]))
    if not found:
        return {"en": np.zeros((0, 2)), "yaw": np.zeros(0), "model": np.zeros(0), "paint": np.zeros(0),
                "length": np.zeros(0), "height": np.zeros(0), "seed": np.zeros(0)}
    cars = np.array(found)
    corners = _footprints(cars[:, :2], cars[:, 2], cars[:, 5], cars[:, 6])
    cars = cars[markings.keep(corners, road)]
    return {"en": cars[:, :2], "yaw": cars[:, 2], "model": cars[:, 3], "paint": cars[:, 4],
            "length": cars[:, 5], "height": cars[:, 7], "seed": cars[:, 8]}


def _stations(line, a: float, b: float) -> np.ndarray:
    """Distances along the line from a to b: every bend, and at least every
    LANE_STEP."""
    coords = np.asarray(line.coords)[:, :2]
    bends = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(coords, axis=0), axis=1))])
    even = np.linspace(a, b, max(2, int(np.ceil((b - a) / LANE_STEP)) + 1))
    return np.union1d(even, bends[(bends > a + 0.5) & (bends < b - 0.5)])


def _blocked(line, center: np.ndarray, length: np.ndarray, side: int, travel: tuple, blockers: tuple) -> np.ndarray:
    """Which cars (centers along the line, lengths) on this side would stand
    in front of a hydrant or at a bus stop."""
    points, clear = blockers
    blocked = np.zeros(len(center), dtype=bool)
    if len(points) == 0:
        return blocked
    reach = max(abs(travel[0]), abs(travel[1])) + BLOCKER_REACH
    x0, y0, x1, y1 = line.bounds
    near = (points[:, 0] > x0 - reach) & (points[:, 0] < x1 + reach) & \
           (points[:, 1] > y0 - reach) & (points[:, 1] < y1 + reach)
    if not near.any():
        return blocked
    points, clear = points[near], clear[near]
    along = shapely.line_locate_point(line, shapely.points(points))
    foot, normal = markings._frame(line, along)
    lateral = np.sum((points - foot) * normal, axis=1)
    mine = (lateral * side > 0) & (np.abs(lateral) < reach) & (along > 0.0) & (along < line.length)
    for s, c in zip(along[mine], clear[mine]):
        blocked |= np.abs(center - s) < length / 2 + c
    return blocked


def _footprints(en: np.ndarray, yaw: np.ndarray, length: np.ndarray, width: np.ndarray) -> np.ndarray:
    """(N, 4, 2) corners of cars at en facing yaw (common.PROP_* convention)."""
    front = np.column_stack([np.sin(yaw), -np.cos(yaw)])  # east, north
    side = np.column_stack([-front[:, 1], front[:, 0]])
    f = front * (length / 2)[:, None]
    s = side * (width / 2)[:, None]
    return np.stack([en + f + s, en + f - s, en - f - s, en - f + s], axis=1)
