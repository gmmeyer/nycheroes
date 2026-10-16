"""Times Square's own pieces, beyond the billboards every street wall in the
sign district carries (props.SIGN_ALONG / SIGN_ACROSS, facades.SIGNS):

- Walls on the plazas (Broadway's roadbed from 42nd to 47th Street, which
  the data has as pavement) count as street fronts (faces_plaza()), so they
  get shop fronts and billboards like those on the streets.
- One Times Square, the ball-drop tower at the south end, covered in screens
  to its top: its sign walls are marked SIGN_TOWER (SIGN_TOWERS lists it by
  BIN, so others can join).
- The TKTS booth in Father Duffy Square (46th to 47th Street): its red glass
  steps, 27 risers up to the booth's roof 4.9 m above the square, facing south
  over Times Square, with the booth's glass sides and its ticket windows at
  the back. It replaces the data's 4.9 m box over the same footprint.
- Granite benches in lines down the middle of the plazas.
- A curved screen wrapped around a building corner, like the cola signs that
  have bulged over the north end of the square (an invented brand here): a
  drum of screens around the corner of 47th Street and Seventh Avenue, over
  the TKTS steps.
- Walking lanes across the plazas (plaza_lanes()), so pedestrians fill them
  and not only the curbs, and up the TKTS steps (step_lanes()).

All of it goes into the buildings surface of the tiles (no extra draw calls;
near tiles give it collision, so the steps can be climbed and sat on). Faces
carry facades.SIGNS plus one of the parts below in the FRONT_PART field (a
stoop's field, which SIGNS faces never use), and shaders/building.gdshader's
sign code paints them:

  uv2.x = archetype + FLAG_SCALE * (SIGNS + part * FRONT_PART [+ ROOF])
  uv    = walls: (m along the wall, m above the piece's ground); tops (ROOF):
          world x/z, like roofs

Plazas: the sign district's sidewalk area (land, not roadbed, PLAZA_WALL_GAP
from buildings) more than PLAZA_INSET from its edges, in pieces of at least
PLAZA_MIN_AREA that touch a street (courtyards inside blocks don't).
"""

import math

import numpy as np
import shapely
from shapely.geometry import LineString, Polygon

import facades
import props
from common import lines_of, polygons_of, triangles_of

# Parts (the FRONT_PART field of SIGNS faces). Same numbers in the shader.
SIGN_TOWER = 1    # a sign wall with screens up to its top
TKTS_STEPS = 2    # the red steps: risers (walls) and treads (ROOF)
TKTS_BOOTH = 3    # the booth's glass sides and its back with the ticket windows
PLAZA_BENCH = 4   # a granite bench: sides (walls) and seat (ROOF)
CORNER_SCREEN = 5  # a drum of screens around a corner: its screen (walls, uv.x
                   # m around it from 0), and steel top and bottom (ROOF)

ONE_TIMES_SQUARE = 1022581
SIGN_TOWERS = {ONE_TIMES_SQUARE}

# The TKTS booth: the data's box (its footprint is the real one), and its
# steps (27 risers of 18 cm; the top step runs on 1.1 m to the back).
TKTS_BIN = 1085637
TKTS_RISERS = 27
TKTS_HEIGHT = 4.9
TKTS_LANDING = 1.1

# Corner screens: (BIN, the corner (m along, across the avenues), radius,
# how far the drum's axis stands out from the corner, its bottom and top (m
# above the building's ground)). 1568 Broadway, at 47th Street and Seventh
# Avenue, faces the square over the TKTS steps. The shader's DRUM_HEIGHT is
# top - bottom.
CORNER_DRUMS = [
    (1024757, (163.4, -18.7), 5.5, 1.5, 9.0, 23.0),
]
DRUM_SEGMENTS = 12  # per quarter circle

# Plazas, benches, and lanes across them (meters).
PLAZA_WALL_GAP = 0.8
PLAZA_INSET = 4.0
PLAZA_MIN_AREA = 150.0
PLAZA_STREET_REACH = 6.0  # a plaza piece this close to a street is open to it
BENCH_SIZE = (8.0, 0.9, 0.45)  # length, depth, height
BENCH_GAP = 5.0  # between benches in a line
BENCH_END = 3.0  # keep this far in from a plaza's ends
BENCH_CLEAR = 1.6  # from street furniture, trees and the TKTS steps
BENCH_TWO_LINES = 16.0  # plazas wider than this get two lines of benches
LANE_FROM_CURB = 2.5  # build_tiles.LANE_OFFSET: the curbside lanes
PLAZA_LANE_STEP = 3.0  # then a lane every this many meters further in
PLAZA_LANE_MAX = 22.0
LANE_CLEAR = 0.8  # lanes keep this far from benches
PLAZA_PROBES = (4.0, 12.0, 24.0)  # a wall faces a plaza if a point this far out is on one
STEP_LANES = (0.2, 0.5, 0.8)  # lanes up the TKTS steps, across them (0 west, 1 east)
STEP_LANE_APPROACH = 4.0  # they start this far out on the square

ARCHETYPE = facades.OTHER
SEED = 0.37
# The avenues' directions (props'), as unit vectors.
ALONG = props.AVENUE_ALONG / np.linalg.norm(props.AVENUE_ALONG)
ACROSS = props.AVENUE_ACROSS / np.linalg.norm(props.AVENUE_ACROSS)

_cache: dict = {}


def sign_part(bin_: int) -> int:
    """The part for a data building's sign walls: SIGN_TOWER or 0."""
    return SIGN_TOWER if bin_ in SIGN_TOWERS else 0


def without(indices: np.ndarray, bins: np.ndarray) -> np.ndarray:
    """Building indices without the TKTS booth (its steps are built here)."""
    return indices[bins[indices] != TKTS_BIN] if len(indices) else indices


def add_to_tile(builder, level: str, size: float, i: int, j: int, w: dict, ground_of) -> None:
    """Adds the TKTS steps (near and mid tiles) and the plaza benches (near
    tiles) whose middles are in tile (i, j) of `level` (tiles `size` m) to its
    buildings MeshBuilder. `w` is build_tiles' worker data; ground_of(polygon)
    is where something with that footprint stands."""
    if level not in ("lod0", "lod1"):
        return
    pieces = plazas(w)

    def here(geom) -> bool:
        c = geom.centroid
        return (math.floor(c.x / size), math.floor(-c.y / size)) == (i, j)

    if pieces["tkts"] is not None and here(pieces["tkts"]):
        _add_tkts(builder, pieces["tkts"], ground_of(pieces["tkts"]))
    for footprint, drum in pieces["drums"]:
        if here(footprint):
            _add_drum(builder, footprint, *drum, ground_of(footprint))
    if level == "lod0":
        for bench in pieces["benches"]:
            if here(bench):
                _add_bench(builder, bench, ground_of(bench))


def plaza_lanes(w: dict, bounds, sidewalks, roads):
    """Extra walking lanes across the plazas in `bounds`: lines every
    PLAZA_LANE_STEP from the curbside lanes, parallel to the streets, within
    `sidewalks` (the tile's walkable area) and clear of the benches. `roads`
    is the roadbed around the tile. Returns a geometry of lines (maybe empty)."""
    pieces = plazas(w)
    area = shapely.intersection(shapely.intersection(pieces["walkable"], bounds), sidewalks)
    if area.is_empty:
        return LineString()
    near = pieces["bench_tree"].query(shapely.buffer(bounds, 10.0))
    if len(near):
        area = shapely.difference(area, shapely.buffer(shapely.union_all(pieces["benches"][near]), LANE_CLEAR))
    lines = []
    reach = LANE_FROM_CURB + PLAZA_LANE_STEP
    while reach <= PLAZA_LANE_MAX:
        lines.extend(lines_of(shapely.intersection(shapely.buffer(roads, reach).boundary, area)))
        reach += PLAZA_LANE_STEP
    return shapely.MultiLineString(lines) if lines else LineString()


def step_lanes(w: dict, bounds, ground_of) -> list:
    """Lanes up the TKTS steps, if they're in `bounds`: (N, 3) arrays of
    east, north and height, from the square in front up every step to the top
    (pedestrians turn around at the ends). ground_of(polygon) is where the
    booth stands, as for add_to_tile()."""
    tkts = plazas(w)["tkts"]
    if tkts is None or not shapely.contains(bounds, tkts.centroid):
        return []
    ground = ground_of(tkts)
    a0, a1, run, rise, cuts, edges = _steps(tkts)
    lanes = []
    for share in STEP_LANES:
        def across(a: float, k: int) -> float:
            west, east = edges[k]
            return west + share * (east - west)
        points = [(a0 - STEP_LANE_APPROACH, across(a0, 0), ground), (a0 - 0.05, across(a0, 0), ground)]
        for k in range(TKTS_RISERS):
            height = ground + (k + 1) * rise
            points.append((cuts[k] + 0.05, across(cuts[k], k), height))
            points.append((cuts[k + 1] - 0.05, across(cuts[k + 1], k + 1), height))
        en = np.array([_en(a, c) for a, c, _ in points])
        lanes.append(np.column_stack([en, [h for _, _, h in points]]))
    return lanes


def faces_plaza(w: dict, middles: np.ndarray, outward: np.ndarray) -> np.ndarray:
    """For walls with these (N, 2) midpoints and outward unit normals
    (east/north), whether each faces one of the plazas (a point PLAZA_PROBES
    in front of it is on one)."""
    walkable = plazas(w)["walkable"]
    near = np.zeros(len(middles), dtype=bool)
    if walkable.is_empty or len(middles) == 0:
        return near
    for reach in PLAZA_PROBES:
        near |= shapely.intersects(walkable, shapely.points(middles + outward * reach))
    return near


def bench_obstacles(w: dict, bounds):
    """The benches near `bounds`, grown by LANE_CLEAR (for keeping the
    curbside lanes off them), or an empty geometry."""
    pieces = plazas(w)
    near = pieces["bench_tree"].query(shapely.buffer(bounds, 10.0))
    if not len(near):
        return Polygon()
    return shapely.buffer(shapely.union_all(pieces["benches"][near]), LANE_CLEAR)


def plazas(w: dict) -> dict:
    """The sign district's plazas, worked out once per worker: "walkable"
    (the plazas grown back toward their edges, where the extra lanes go),
    "benches" (rectangles, east/north) with "bench_tree", and "tkts" (the
    booth's footprint, or None)."""
    if "plazas" in _cache:
        return _cache["plazas"]
    b, g = w["b"], w["g"]
    district = _district()
    roads = g["roads"][w["road_tree"].query(district)]
    roads = shapely.union_all(roads) if len(roads) else Polygon()
    near = w["building_tree"].query(district)
    buildings = shapely.union_all(b["geoms"][near]) if len(near) else Polygon()
    open_ground = shapely.difference(shapely.intersection(g["land"], district), roads)
    open_ground = shapely.difference(open_ground, shapely.buffer(buildings, PLAZA_WALL_GAP))
    cores = [p for p in polygons_of(shapely.buffer(open_ground, -PLAZA_INSET), PLAZA_MIN_AREA)
             if shapely.dwithin(roads, p, PLAZA_INSET + PLAZA_STREET_REACH)]
    walkable = shapely.intersection(shapely.buffer(shapely.union_all(cores), PLAZA_INSET - LANE_FROM_CURB),
                                    open_ground) if cores else Polygon()

    found = np.flatnonzero(b["bin"] == TKTS_BIN)
    tkts = b["geoms"][found[0]] if len(found) else None
    if tkts is not None:
        tkts = max(polygons_of(tkts), key=lambda p: p.area)

    # Benches keep clear of street furniture, street trees and the steps.
    blockers = [shapely.points(w["furniture"]["en"]), shapely.points(w["trees"]["en"])]
    blockers = [p[shapely.intersects(district, p)] for p in blockers]
    clear = shapely.union_all(np.concatenate(blockers)) if sum(len(p) for p in blockers) else Polygon()
    clear = shapely.buffer(clear, BENCH_CLEAR)
    if tkts is not None:
        clear = shapely.union(clear, shapely.buffer(tkts, BENCH_CLEAR + 2.0))
    benches = []
    for core in cores:
        benches.extend(_bench_lines(core, shapely.difference(core, clear)))
    benches = np.array(benches, dtype=object)
    drums = []
    for bin_, *drum in CORNER_DRUMS:
        found = np.flatnonzero(b["bin"] == bin_)
        if len(found):
            drums.append((max(polygons_of(b["geoms"][found[0]]), key=lambda p: p.area), drum))
    shapely.prepare(walkable)
    _cache["plazas"] = {"walkable": walkable, "benches": benches, "bench_tree": shapely.STRtree(benches),
                        "tkts": tkts, "drums": drums}
    return _cache["plazas"]


def _district() -> Polygon:
    along, across = props.SIGN_ALONG, props.SIGN_ACROSS
    corners = [(along[0], across[0]), (along[1], across[0]), (along[1], across[1]), (along[0], across[1])]
    return Polygon([_en(a, c) for a, c in corners])


def _en(along: float, across: float) -> tuple[float, float]:
    """East/north of a point `along` and `across` the avenues from the origin."""
    p = along * ALONG + across * ACROSS
    return float(p[0]), float(p[1])


def _bench_lines(core, free) -> list:
    """Benches in one or two lines down the long axis of a plaza piece, each
    wholly inside `free` (with half a meter to spare)."""
    rect = np.asarray(shapely.oriented_envelope(core).exterior.coords)[:4]
    edges = [rect[1] - rect[0], rect[2] - rect[1]]
    long_edge = edges[int(np.hypot(*edges[1]) > np.hypot(*edges[0]))]
    length = float(np.hypot(*long_edge))
    width = float(np.hypot(*edges[0] if long_edge is edges[1] else edges[1]))
    u = long_edge / length
    v = np.array([-u[1], u[0]])
    center = rect.mean(axis=0)
    bench_length, depth, _ = BENCH_SIZE
    offsets = (-width / 4.0, width / 4.0) if width > BENCH_TWO_LINES else (0.0,)
    pitch = bench_length + BENCH_GAP
    count = int((length - 2.0 * BENCH_END + BENCH_GAP) // pitch)
    found = []
    for offset in offsets:
        for k in range(count):
            t = (k - (count - 1) / 2.0) * pitch
            middle = center + u * t + v * offset
            half_u, half_v = u * bench_length / 2.0, v * depth / 2.0
            corners = [middle - half_u - half_v, middle + half_u - half_v, middle + half_u + half_v,
                       middle - half_u + half_v]
            bench = shapely.orient_polygons(Polygon(corners))
            if shapely.contains(free, shapely.buffer(bench, 0.5)):
                found.append(bench)
    return found


def _uv2(part: int, roof: bool = False) -> tuple[float, float]:
    flags = facades.SIGNS + part * facades.FRONT_PART + (facades.ROOF if roof else 0)
    return facades.encode(ARCHETYPE, flags, 0, SEED)


def _steps(footprint):
    """The TKTS steps over the booth's footprint, in meters along and across
    the avenues: its front and back (a0, a1), each step's run and rise, where
    each riser stands (cuts, with a1 last), and the footprint's west and east
    edges at each (edges)."""
    coords = np.asarray(footprint.exterior.coords)[:, :2]
    a0, a1 = float((coords @ ALONG).min()), float((coords @ ALONG).max())
    run = (a1 - a0 - TKTS_LANDING) / TKTS_RISERS
    rise = TKTS_HEIGHT / TKTS_RISERS
    cuts = [a0 + k * run for k in range(TKTS_RISERS)] + [a1]

    def width_at(a: float) -> tuple[float, float]:
        a = min(max(a, a0 + 0.05), a1 - 0.05)
        line = LineString([_en(a, -1e3), _en(a, 1e3)])
        across = shapely.get_coordinates(shapely.intersection(line, footprint)) @ ACROSS
        return float(across.min()), float(across.max())

    return a0, a1, run, rise, cuts, [width_at(a) for a in cuts]


def _add_tkts(builder, footprint, ground: float) -> None:
    """The red steps over the booth's footprint, rising toward 47th Street:
    for each step a tread and a riser across the footprint (as wide as it is
    there), its sides down to the ground, and the booth's back wall."""
    a0, a1, run, rise, cuts, edges = _steps(footprint)

    def point(a: float, c: float) -> np.ndarray:
        return a * ALONG + c * ACROSS

    steps = _uv2(TKTS_STEPS)
    treads = _uv2(TKTS_STEPS, roof=True)
    sides = _uv2(TKTS_BOOTH)
    for k in range(TKTS_RISERS):
        (w0, e0), (w1, e1) = edges[k], edges[k + 1]
        front_west, front_east = point(cuts[k], w0), point(cuts[k], e0)
        back_west, back_east = point(cuts[k + 1], w1), point(cuts[k + 1], e1)
        top = ground + (k + 1) * rise
        bottom = ground + k * rise if k else ground - 1.0
        builder.add_flat([Polygon([front_west, front_east, back_east, back_west])], top, treads)
        # Walls run with their outside on the right: the riser faces south,
        # the sides east and west.
        builder.add_walls(np.array([front_west, front_east]), bottom, top, steps, ground_y=ground)
        builder.add_walls(np.array([front_east, back_east]), ground - 1.0, top, sides, ground_y=ground)
        builder.add_walls(np.array([back_west, front_west]), ground - 1.0, top, sides, ground_y=ground)
    w1, e1 = edges[-1]
    builder.add_walls(np.array([point(a1, e1), point(a1, w1)]), ground - 1.0, ground + TKTS_HEIGHT, sides,
                      ground_y=ground)


def _add_drum(builder, footprint, corner, radius: float, out: float, bottom: float, top: float,
              ground: float) -> None:
    """A drum of screens around the footprint's corner nearest `corner` (m
    along, across): a cylinder `radius` m around an axis `out` m out from the
    corner, from `bottom` to `top` m above `ground`, where it's outside the
    building; steel top and bottom."""
    ring = np.asarray(shapely.orient_polygons(footprint).exterior.coords)[:-1, :2]
    k = int(np.argmin(np.hypot(*(ring - np.array(_en(*corner))).T)))
    along_walls = [ring[k - 1] - ring[k], ring[(k + 1) % len(ring)] - ring[k]]
    diagonal = -sum(v / np.hypot(*v) for v in along_walls)
    center = ring[k] + diagonal / np.hypot(*diagonal) * out
    circle = shapely.Point(center).buffer(radius, quad_segs=DRUM_SEGMENTS)
    outside = max(polygons_of(shapely.difference(circle, footprint)), key=lambda p: p.area)
    points = np.asarray(shapely.orient_polygons(outside).exterior.coords)[:-1, :2]
    on_circle = np.hypot(*(points - center).T) > radius * 0.995
    # The arc: the longest run of points on the circle, in the ring's order
    # (counter-clockwise, so the outside is on the right).
    start = int(np.flatnonzero(~on_circle)[0]) if not on_circle.all() else 0
    order = np.roll(np.arange(len(points)), -start)
    runs, run = [], []
    for i in order:
        if on_circle[i]:
            run.append(i)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    arc = points[max(runs, key=len)]
    builder.add_walls(arc, ground + bottom, ground + top, _uv2(CORNER_SCREEN), ground_y=ground)
    builder.add_flat([outside], ground + top, _uv2(CORNER_SCREEN, roof=True))
    tris = triangles_of(outside)
    if tris is not None:
        pos = np.stack([tris[..., 0], np.full(tris.shape[:2], ground + bottom), -tris[..., 1]], axis=-1)
        builder.add(pos, np.stack([tris[..., 0], -tris[..., 1]], axis=-1), _uv2(CORNER_SCREEN, roof=True),
                    (0.0, -1.0, 0.0))


def _add_bench(builder, bench, ground: float) -> None:
    """A granite bench: four sides and a seat."""
    height = BENCH_SIZE[2]
    builder.add_walls(np.asarray(bench.exterior.coords)[:, :2], ground - 1.0, ground + height, _uv2(PLAZA_BENCH),
                      ground_y=ground)
    builder.add_flat([bench], ground + height, _uv2(PLAZA_BENCH, roof=True))
