"""Massing for towers the city's 3-D building model doesn't have.

The 3-D Building Model (buildings3d.py) is from 2014, so dozens of newer
towers have no shape there, or an obsolete one (432 Park Avenue half-built,
111 West 57th Street's the 70 m building that stood on part of its lot), and
their footprint record alone would draw a flat-topped box over the whole
footprint or lot, up to the spire's tip: One Vanderbilt over its whole
block, the Shops at Hudson Yards at 30 Hudson Yards' 386 m. Some footprint
heights were measured during construction, so finished towers stand as
stumps (55 Hudson Yards at 24 m, 270 Park Avenue at half height).

Here each of the worst of them (the ones over about 200 m, and some lower
ones whose box covers a whole podium) gets a simple, recognizable massing
from a table: which part of its footprint the tower really stands on, its
podium, setbacks, taper, crown and spire, at its published heights (sources
with each tower; where a tower stands on its lot is checked against the
city's 2024 aerial photos, or taken from OpenStreetMap's 3-D building parts
where the photo can't show it). Slender towers whose footprint is the tower
keep their prisms. build_tiles.py draws the table's towers in place of the
footprint prism at every detail level (all far taller than LEVELS'
shapes_from) and keeps them out of far tiles' merged blocks and off the
water tower list.

Faces carry the same uv/uv2 as other buildings (facades.py): the building's
type (modern glass offices and apartments, mostly), FRONT on walls that face
a street, ROOF on roofs, uv = (m along the wall, m above the ground) on walls
and world x/z on roofs. Spires are stainless steel (landmarks.STEEL).

Coordinates: each tower has a frame on the ground, origin at the center of
its main footprint's bounding box in axes turned `angle` degrees (counter-
clockwise from east) for local x; y is 90 degrees left of x. For Manhattan's
street grid (GRID) x runs along the streets toward the East River and y up
the avenues. z is meters above where the footprint stands (its lowest corner
on our terrain, like the prisms).
"""

import math
from dataclasses import dataclass, field

import numpy as np
import shapely
from shapely.geometry import Polygon

import facades
import landmarks
from common import polygons_of, triangles_of, triangulate_planar

GRID = -29.0  # Manhattan's street grid: local x along the streets, y uptown

# Detail levels: 0 near tiles, 1 mid, 2 far (as in landmarks.py).
DETAIL = {"lod0": 0, "lod1": 1, "lod2": 2}
# Points around round parts per detail level, before scaling by each part.
ROUND = (24, 12, 8)
# A face whose normal points up more than this is a roof, else a wall.
ROOF_FACING = 0.8
# Walls of parts standing on the ground sink this far into it, like the prisms.
SINK = 1.0

FOOTPRINT = "footprint"  # a part's outline: the main building's whole footprint


@dataclass
class Block:
    """A part of a tower: walls from z0 up to z1 around `outline` (local x/y
    points, or FOOTPRINT, or Minus(...)), and a roof. With `top` (the same
    number of points), the walls lean in or out to it (tapers, flares); with
    `slope`, the top rises by that many meters per meter along local x and y
    (z1 at the frame's origin). `top` needs a points outline. `kind` overrides the tower's building type
    (facades.py; landmarks.STEEL for metal), `flags` adds facade flags.
    `soffit` closes the bottom (cantilevers); `details` lists the detail
    levels it's drawn at; `seed` gives the part its own look."""
    outline: object
    z0: float
    z1: float
    top: object = None
    slope: tuple = (0.0, 0.0)
    kind: int | None = None
    flags: int = 0
    soffit: bool = False
    details: tuple = (0, 1, 2)
    seed: float | None = None


@dataclass
class Minus:
    """An outline (FOOTPRINT or points) without other outlines: podiums around a tower."""
    outline: object
    cut: list = field(default_factory=list)


@dataclass
class Shrunk:
    """The main building's footprint, `by` meters in all round."""
    by: float


@dataclass
class Model:
    """The 3-D model's shape of the main building, as it was in 2014: an
    older building the tower stands beside (the Dime Savings Bank), with its
    own look. Up close only (far tiles draw buildings that low as prisms)."""
    kind: int = facades.PREWAR_OFFICE
    flags: int = facades.LANDMARK
    seed: float | None = None
    details: tuple = (0, 1, 2)


@dataclass
class Tower:
    name: str
    bins: tuple          # data buildings it replaces; the first one draws it
    height: float        # to the top of its highest part (m)
    build: object        # build(detail) -> [Block]
    kind: int = facades.MODERN_RESIDENTIAL
    floor: float = 3.4   # floor height (m), for the windows
    seed: float | None = None  # a look (see look()); default the data building's seed
    flags: int = 0       # facade flags for every part (LANDMARK: stone, floodlit setbacks)
    angle: float = GRID


# --- Outline helpers (local x/y, counter-clockwise) ---

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def square(cx, cy, side):
    return rect(cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)


def chamfered(x0, y0, x1, y1, c):
    """A rectangle with its corners cut `c` back along each side."""
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c),
            (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


def ngon(cx, cy, r, n, start=0.0):
    return [(cx + r * math.cos(math.radians(start + 360.0 * k / n)),
             cy + r * math.sin(math.radians(start + 360.0 * k / n))) for k in range(n)]


def scaled(points, sx, sy=None, about=None):
    """Points scaled about `about` (default: their mean)."""
    p = np.asarray(points, np.float64)
    c = p.mean(axis=0) if about is None else np.asarray(about, np.float64)
    return [tuple(v) for v in c + (p - c) * [sx, sx if sy is None else sy]]


def turned(points, degrees, about=None):
    """Points turned counter-clockwise about `about` (default: their mean)."""
    p = np.asarray(points, np.float64)
    c = p.mean(axis=0) if about is None else np.asarray(about, np.float64)
    a = math.radians(degrees)
    m = np.array([[math.cos(a), math.sin(a)], [-math.sin(a), math.cos(a)]])
    return [tuple(v) for v in c + (p - c) @ m]


def spire(cx, cy, z0, z1, r0, r1=0.15, n=4, details=(0, 1, 2)):
    """A tapering steel mast."""
    return Block(ngon(cx, cy, r0, n, 45.0 if n == 4 else 0.0), z0, z1, top=ngon(cx, cy, r1, n, 45.0 if n == 4 else 0.0),
                 kind=landmarks.STEEL, details=details)


def outline_of(geom, detail):
    """A shapely polygon's outline (local) as points, simplified for the detail level."""
    geom = shapely.simplify(geom, (0.15, 0.6, 1.5)[detail], preserve_topology=True)
    poly = max(polygons_of(geom, 1.0), key=lambda p: p.area)
    return [tuple(p) for p in np.asarray(shapely.orient_polygons(poly).exterior.coords)[:-1]]


def softened(points, r, detail):
    """An outline with its corners rounded to radius r."""
    poly = shapely.buffer(shapely.buffer(Polygon(points), -r, join_style="mitre"), r,
                          quad_segs=max(2, ROUND[detail] // 4))
    return outline_of(poly, detail)


def hexagon(cx, cy, length, width, degrees):
    """An elongated hexagon with 120-degree corners, its long axis turned
    `degrees` from local x."""
    shoulder = length / 2 - width / 2 / math.tan(math.radians(60.0))
    a = math.radians(degrees)
    ux, uy = math.cos(a), math.sin(a)
    points = [(length / 2, 0.0), (shoulder, width / 2), (-shoulder, width / 2), (-length / 2, 0.0),
              (-shoulder, -width / 2), (shoulder, -width / 2)]
    return [(cx + u * ux - v * uy, cy + u * uy + v * ux) for u, v in points]


# --- Looks ---
# The building shader picks a palette from each building's seed (rnd() in
# shaders/building.gdshader, which sees the seed in 1024 steps). A tower can
# ask for a look instead of its data building's random one: the first seed
# whose shader random numbers r1..r5 pass a test.

def _hash(x: float, y: float) -> float:
    """shaders/patterns.gdshaderinc's hash(), in 32-bit floats like the GPU."""
    f = np.float32
    p3 = np.array([x, y, x], f) * f(0.1031)
    p3 = p3 - np.floor(p3)
    p3 = p3 + f(np.dot(p3, p3[[1, 2, 0]] + f(33.33)))
    v = (p3[0] + p3[1]) * p3[2]
    return float(v - np.floor(v))


_RANDOMS = []


def _shader_randoms(seed: float) -> list:
    return [_hash(np.float32(seed * 1024.0 + salt * 3.7), np.float32(salt * 13.1 + 7.0)) for salt in (1, 2, 3, 4, 5)]


def look(test) -> float:
    """The first seed (as the shader sees it) whose r1..r5 pass test(r)."""
    if not _RANDOMS:
        _RANDOMS.extend(_shader_randoms((k + 0.5) / 1024.0) for k in range(1024))
    for k, r in enumerate(_RANDOMS):
        if test(r):
            return (k + 0.5) / 1024.0
    raise ValueError("no seed has that look")


def _in(r, low, high, margin=0.03):
    return low + margin <= r <= high - margin


# Glass towers (MODERN_RESIDENTIAL curtain walls, r1 < 0.7; MODERN_OFFICE):
# GLASS_TOWER 0 blue, 1 teal-gray, 2 light blue, 3 gray-green, 4 dark blue-gray.
def glass_residential(tone):
    return look(lambda r: _in(r[0], 0.0, 0.7) and _in(r[2] * 5, tone, tone + 1, 0.15))


def glass_office(tone, dark_frame=False):
    frame = (0.7, 1.0) if dark_frame else (0.0, 0.7)
    return look(lambda r: _in(r[0] * 5, tone, tone + 1, 0.15) and _in(r[1], *frame))


# MODERN_RESIDENTIAL's other look: a light gray concrete grid with big windows.
def concrete_grid():
    return look(lambda r: _in(r[0], 0.7, 1.0) and _in(r[3], 0.5, 1.0))


# Masonry towers drawn as LANDMARK prewar offices (or, with office off,
# apartments and hotels): pale limestone or ivory terracotta.
def limestone(shade=0, office=True):
    high = 0.7 if office else 0.45
    return look(lambda r: _in(r[4], 0.0, high) and _in(r[3] * 3, shade, shade + 1, 0.15))


def terracotta(shade=0, office=True):
    low, high = (0.7, 1.0) if office else (0.45, 0.64)
    return look(lambda r: _in(r[4], low, high) and _in(r[3] * 3, shade, shade + 1, 0.15))


# --- The towers ---
# Each build(d) returns the tower's Blocks at detail level d. Heights are from
# street level at the footprint's lowest corner.


def _central_park_tower(d):
    """Central Park Tower (Adrian Smith + Gordon Gill, 2020), 472.4 m to the
    roof: an 85 m glass base over the lot (Nordstrom, "280 feet to its top
    floor"), and a tower on its eastern end that cantilevers 8.5 m east over
    the Art Students League from about 89 m up, 24 m back from 57th Street.
    The corners step back near the top (the north corners at about 332 m)
    and the crown of tall slats tops out at the middle. Plan about 38 x 28 m
    (from the floor area). Wikipedia, "Central Park Tower"; New York YIMBY,
    Dec. 2017."""
    x0, x1, y0, y1 = 12.0, 42.0, -7.0, 21.0
    over = 50.5  # the cantilever's east face
    return [Block(Minus(FOOTPRINT, [rect(x0, y0, x1, y1)]), 0.0, 85.0, kind=facades.STORE),
            Block(rect(x0, y0, x1, y1), 0.0, 89.0),
            Block(rect(x0, y0, over, y1), 89.0, 332.0, soffit=True),
            Block(rect(x0, y0, over, y1 - 9.0), 332.0, 433.0),
            Block(rect(x0 + 3.0, y0 + 3.0, x1 - 4.0, y1 - 10.0), 433.0, 472.4)]


def _park_432(d):
    """432 Park Avenue (Rafael Vinoly, 2015): a 28.5 m square tube of white
    concrete frames, 425.5 m to the flat roof, with five open double-height
    floors (about 9 m, the glass set back) at about 95, 156, 227, 293 and
    359 m; low retail and office wings around it. The tower's place is the
    2014 3-D model's (247 m tall then). Wikipedia, "432 Park Avenue"."""
    tower = square(-20.5, 0.5, 28.5)
    parts = [Block(Minus(FOOTPRINT, [tower]), 0.0, 14.0, kind=facades.STORE),
             Block(tower, 0.0, 425.5)]
    for z in (95.0, 156.0, 227.0, 293.0, 359.0):
        parts.append(Block(square(-20.5, 0.5, 27.4), z, z + 9.0, details=(0, 1)))
    return parts


def _w57_111(d):
    """111 West 57th Street (SHoP, 2021): an 18 x 23 m blade of terracotta
    and bronze piers rising through Steinway Hall's block, set back from
    57th Street; its north face goes straight up, its south face steps back
    in a feather of setbacks from about 200 m to the pinnacle at 435 m.
    Steinway Hall (1925), the 16-story L around it, stays: its main mass
    about 52 m, the campanile on 57th Street about 70 m with a copper
    pyramid. Wikipedia, "111 West 57th Street", "Steinway Hall"; the tower's
    place on the lot from OpenStreetMap's building parts."""
    x0, x1, north = -2.8, 15.2, 10.3
    hall = dict(kind=facades.PREWAR_OFFICE, flags=facades.LANDMARK | facades.CORNICE, seed=limestone(0))
    parts = [Block(Minus(FOOTPRINT, [rect(x0, north - 23.0, x1, north)]), 0.0, 52.0, **hall),
             Block(rect(-14.0, -28.0, -3.5, -17.0), 52.0, 70.0, **hall),
             Block(rect(-14.0, -28.0, -3.5, -17.0), 70.0, 79.0, top=rect(-9.2, -23.0, -8.3, -22.0),
                   kind=landmarks.COPPER, details=(0, 1))]
    steps = 12 if d < 2 else 6
    zs = np.linspace(200.0, 434.5, steps + 1)
    depths = np.linspace(23.0, 2.5, steps + 1)
    parts.append(Block(rect(x0, north - 23.0, x1, north), 0.0, zs[0]))
    for z0, z1, depth in zip(zs[:-1], zs[1:], depths[1:]):
        parts.append(Block(rect(x0, north - depth, x1, north), z0, z1))
    return parts


def _vanderbilt(d):
    """One Vanderbilt (KPF, 2020): the whole block west of Grand Central, a
    base cut open at 42nd Street and Vanderbilt Avenue, then four
    interlocking volumes whose faces lean in all the way up (plates from
    about 58 x 62 m to 40 m square), ending at 330, 350 and 397 m around a
    crown off-center to the north-east, and a 30 m mast to 427 m. Glass and
    pearl-white terracotta. Wikipedia, "One Vanderbilt"; KPF; the crown's
    place from OpenStreetMap's building parts."""
    cx, cy = 6.0, 6.0

    def box(half, chamfer, dx=0.0, dy=0.0):
        return chamfered(cx + dx - half, cy + dy - half, cx + dx + half, cy + dy + half, chamfer)
    return [Block(Minus(FOOTPRINT, [[(14.0, -31.0), (33.0, -31.0), (33.0, -12.0)]]), 0.0, 22.0),
            Block(chamfered(-30.0, -29.0, 30.0, 29.0, 5.0), 22.0, 160.0, top=box(25.0, 6.5, -2.5, -2.5)),
            Block(box(24.0, 7.0, -2.5, -2.5), 160.0, 330.0, top=box(19.0, 8.0, -1.0, -1.0)),
            Block(box(16.0, 6.5), 330.0, 350.0, top=box(15.0, 6.5)),
            Block(box(12.0, 5.0), 350.0, 375.0, top=box(10.5, 4.5)),
            Block(box(8.0, 3.0), 375.0, 397.0, top=box(5.5, 2.0)),
            spire(cx + 1.0, cy + 1.0, 397.0, 427.0, 1.6)]


def _w53_53(d):
    """53 West 53rd Street (Jean Nouvel, 2019), 320 m: a through-block tower
    west of MoMA (gallery floors in its base) whose north and south faces
    lean in as it rises while the east and west faces stay plumb; above
    about the 60th floor it splits into faceted peaks, the middle one
    highest, with lower shoulders either side. Concrete diagrid, gray panels
    and glass. Wikipedia, "53 West 53rd Street"."""
    x0, x1 = -16.0, 16.0
    return [Block(FOOTPRINT, 0.0, 22.0),
            Block(rect(x0, -28.0, x1, 28.0), 22.0, 250.0, top=rect(x0, -8.0, x1, 8.0)),
            Block(rect(-10.0, -8.0, 10.0, 8.0), 250.0, 320.0, top=rect(-1.2, -1.0, 1.2, 1.0)),
            Block(rect(x0, -7.5, -6.0, 7.5), 250.0, 284.0, top=rect(-12.5, 0.5, -10.5, 2.5)),
            Block(rect(6.0, -7.5, x1, 7.5), 250.0, 300.0, top=rect(10.5, -2.5, 12.5, -0.5))]


def _hudson_yards_30(d):
    """30 Hudson Yards (KPF, 2019) and the Shops at Hudson Yards, which
    share a footprint record: the tower at 10th Avenue and 33rd Street is
    two interlocking slabs, a tall west shaft whose glass crown slopes from
    387 m on the east side down to about 350 m on the west, and a lower east
    slab whose east face leans in to a roof at about 300 m; the Edge deck,
    a triangle at 335 m, juts out from the shaft's south-east corner. The
    Shops (seven stories, about 38 m) fill the rest. Wikipedia, "30 Hudson
    Yards"; KPF; Architectural Record; places from OpenStreetMap's building
    parts."""
    shaft = rect(-48.0, 27.0, -4.0, 78.0)
    slab = rect(-4.0, 30.0, 55.0, 76.0)
    return [Block(Minus(FOOTPRINT, [shaft, slab]), 0.0, 38.0, kind=facades.STORE),
            Block(shaft, 0.0, 387.0 + 4.0 * 0.84, slope=(0.84, 0.0)),
            Block(slab, 0.0, 40.0),
            Block(slab, 40.0, 300.0, top=rect(-4.0, 30.0, 14.0, 76.0)),
            Block([(-4.0, 52.0), (-26.0, 27.0), (20.0, 20.0)], 333.0, 336.0, kind=landmarks.STEEL, soffit=True)]


def _hudson_yards_10(d):
    """10 Hudson Yards (KPF, 2016), 268 m to the crown: a broad slab at 10th
    Avenue and 30th Street over the High Line spur, set back at the 23rd
    floor, its west face leaning in over the upper tower, the crown high on
    the south edge and sloping down toward 30 Hudson Yards. Its footprint
    record says 45 m (measured during construction). Wikipedia, "10 Hudson
    Yards"."""
    return [Block(FOOTPRINT, 0.0, 100.0),
            Block(rect(-28.0, -26.5, 44.3, 21.8), 100.0, 250.0, top=rect(-10.0, -26.5, 44.3, 21.8)),
            Block(rect(-10.0, -26.5, 44.3, 21.8), 250.0, 259.0, slope=(0.0, -0.37))]


def _hudson_yards_15(d):
    """15 Hudson Yards (Diller Scofidio + Renfro and Rockwell, 2019), 280 m,
    and The Shed: a rectangular base to about 145 m that turns into a
    four-lobed cloverleaf of blue glass, the lobes ending at 256 m around a
    steel crown screen; east of it The Shed's base building, under its
    37 m shell (nested; it rolls east over the plaza for big shows).
    Wikipedia, "15 Hudson Yards", "The Shed"; the lobes' extent from
    OpenStreetMap's building parts."""
    cx, cy = -43.8, -1.0
    lobes = [shapely.Point(cx + sx * 7.0, cy + sy * 14.5).buffer(8.0, quad_segs=(4, 2, 1)[d])
             for sx in (-1, 1) for sy in (-1, 1)]
    clover = shapely.union_all(lobes + [shapely.box(cx - 15.0, cy - 14.5, cx + 15.0, cy + 14.5)])
    return [Block(rect(-56.8, -23.7, -28.8, 23.7), 0.0, 145.0),
            Block(outline_of(clover, d), 145.0, 256.0),
            Block(softened(rect(cx - 9.0, cy - 13.0, cx + 9.0, cy + 13.0), 4.0, d), 256.0, 278.6),
            Block(rect(-28.8, -22.0, 6.0, 22.0), 0.0, 37.0, kind=facades.INSTITUTION)]


def _hudson_yards_35(d):
    """35 Hudson Yards (SOM, 2019), 305 m: a base over the whole site at 11th
    Avenue and 33rd Street to about 77 m, then setbacks that twist up around
    the tower, and a crown of three wings around a 305 m middle. Pleated
    limestone fins and glass. SOM; Wikipedia; tier heights from
    OpenStreetMap's building parts."""
    parts = [Block(FOOTPRINT, 0.0, 77.0)]
    tiers = [((-22.0, -25.0, 22.0, 24.0), 77.0, 135.0, 6.0), ((-21.0, -24.0, 21.0, 22.0), 135.0, 173.0, 8.0),
             ((-20.0, -23.0, 19.5, 20.5), 173.0, 210.0, 6.0), ((-18.5, -22.0, 18.0, 19.0), 210.0, 248.0, 8.0),
             ((-17.0, -21.0, 17.0, 17.0), 248.0, 276.0, 6.0)]
    for (x0, y0, x1, y1), z0, z1, c in tiers:
        parts.append(Block(chamfered(x0, y0, x1, y1, c), z0, z1))
    parts += [Block(rect(-8.0, -10.0, 9.0, 8.0), 276.0, 305.0),
              Block(rect(-4.0, 8.0, 14.0, 16.0), 276.0, 290.0),
              Block(rect(-16.0, -6.0, -8.0, 10.0), 276.0, 286.0),
              Block(rect(-12.0, -20.0, 5.0, -10.0), 276.0, 282.0)]
    return parts


def _hudson_yards_50(d):
    """50 Hudson Yards (Foster + Partners, 2022), 308 m: a whole block from
    33rd to 34th Street, a six-story podium, then three stacked volumes in a
    white granite grid set back on top of the podium and about halfway up
    on the west face, and a glass-fin crown. Wikipedia, "50 Hudson Yards"."""
    return [Block(FOOTPRINT, 0.0, 30.0),
            Block(rect(-44.0, -22.0, 46.0, 22.0), 30.0, 160.0),
            Block(rect(-34.0, -22.0, 46.0, 22.0), 160.0, 255.0),
            Block(rect(-31.0, -20.0, 44.0, 20.0), 255.0, 296.0),
            Block(rect(-26.0, -16.0, 40.0, 16.0), 296.0, 308.2)]


def _hudson_yards_55(d):
    """55 Hudson Yards (KPF with Kevin Roche, 2018), 238 m, flat-roofed: a
    ten-story base with 4,090 m2 floors on 11th Avenue, set back on the
    east (Hudson Park) side for a tower with 2,600 m2 floors; a dark bronze
    grid. Its footprint record says 24 m (measured during construction).
    Wikipedia, "55 Hudson Yards"."""
    return [Block(FOOTPRINT, 0.0, 48.0),
            Block(rect(-31.0, -27.0, 19.0, 27.0), 48.0, 238.0)]


def _spiral(d):
    """The Spiral (BIG, 2022), 314 m: a whole block from 34th to 35th Street,
    a six-story base, then planted terraces that climb around the tower in
    a spiral, each floor stepping back a little, to a ziggurat outline.
    Wikipedia, "The Spiral"."""
    x0, y0, x1, y1 = -47.1, -27.5, 47.1, 27.5
    parts = [Block(FOOTPRINT, 0.0, 30.0)]
    zs = [30.0, 72.0, 110.0, 146.0, 180.0, 212.0, 242.0, 270.0, 296.0, 314.4]
    trims = [(0, 0, 0, 0), (0, 0, 5, 0), (0, 0, 5, 3), (5, 0, 5, 3), (5, 3, 5, 3),
             (5, 3, 10, 3), (5, 3, 10, 6), (10, 3, 10, 6), (10, 6, 10, 6)]
    for (w, s, e, n), z0, z1 in zip(trims, zs[:-1], zs[1:]):
        parts.append(Block(rect(x0 + w, y0 + s, x1 - e, y1 - n), z0, z1))
    return parts


def _manhattan_west_1(d):
    """One Manhattan West (SOM, 2019), 304 m: at Ninth Avenue and 33rd
    Street; the north, south and west faces plumb, the east face bowing out
    to the 19th floor (about 80 m) and then leaning in evenly to the roof;
    rounded corners, silvery glass. Wikipedia, "One Manhattan West"."""
    base, top = rect(-30.0, -23.0, 30.0, 22.6), rect(-30.0, -23.0, 12.0, 22.6)
    return [Block(base, 0.0, 80.0), Block(base, 80.0, 304.0, top=top)]


def _manhattan_west_2(d):
    """Two Manhattan West (SOM, 2023), 285 m: One Manhattan West's twin
    turned 90 degrees, at Ninth Avenue and 31st Street; its north face,
    toward its twin, leans in as it rises. Wikipedia, "Manhattan West"."""
    return [Block(FOOTPRINT, 0.0, 80.0),
            Block(rect(-29.5, -23.0, 29.5, 21.7), 80.0, 285.0, top=rect(-29.5, -23.0, 29.5, 5.0))]


def _cps_220(d):
    """220 Central Park South (Robert A.M. Stern, 2019), 290 m of gray-white
    limestone: a 16 x 39 m slab on the west part of 58th Street with a
    stepped crown (corner pavilions about 285 m around a 290 m middle), a
    motor court, and an 18-story villa (84 m, set back above the sixth
    floor) on Central Park South at the east end of the site. Wikipedia,
    "220 Central Park South"; the slab's place and crown from
    OpenStreetMap's building parts."""
    return [Block(rect(-30.2, -30.3, 9.5, -3.0), 0.0, 30.0),
            Block(rect(-29.5, -28.0, 9.5, -11.0), 30.0, 259.0),
            Block(chamfered(-29.5, -28.0, 9.5, -11.0, 3.0), 259.0, 274.0),
            Block(chamfered(-25.5, -27.0, 5.5, -12.0, 3.0), 274.0, 285.0),
            Block(rect(-16.0, -23.0, -4.5, -15.5), 285.0, 290.0),
            Block(rect(7.6, 0.0, 30.0, 30.3), 0.0, 25.0),
            Block(rect(7.6, 0.0, 30.0, 24.0), 25.0, 70.0),
            Block(rect(10.0, 2.0, 28.0, 20.0), 70.0, 84.0)]


def _park_270(d):
    """270 Park Avenue (Foster + Partners, 2025), JPMorgan Chase's
    headquarters, 423 m: the whole block from Madison to Park Avenue, lifted
    on fan columns over a 24 m lobby with plazas at both ends, then setbacks
    on the east and west faces only, four symmetric sets, to a narrow
    crown. Its footprint record says 213 m (measured during construction).
    Wikipedia, "270 Park Avenue (2021-present)"; the setbacks' heights and
    widths from OpenStreetMap's building parts."""
    c = 2.0
    parts = [Block(rect(c - 42.0, -22.0, c + 42.0, 22.0), 0.0, 24.0)]
    for half, z0, z1 in ((54.5, 24.0, 130.0), (42.5, 130.0, 250.0), (30.5, 250.0, 330.0),
                         (18.3, 330.0, 382.0), (6.1, 382.0, 423.0)):
        parts.append(Block(rect(c - half, -24.0, c + half, 24.0), z0, z1, soffit=z0 == 24.0))
    return parts


def _wtc_3(d):
    """3 World Trade Center (Rogers Stirk Harbour, 2018), 329 m: a podium
    over the lot to 62 m (17 stories), then three parallel slabs, the middle
    one to the roof, the north shoulder to the 76th floor (285 m), the south
    to the 60th (219 m); K-braced east and west faces. Wikipedia, "3 World
    Trade Center"; the slabs' places from OpenStreetMap's building parts."""
    x0, x1 = -9.0, 47.0
    return [Block(FOOTPRINT, 0.0, 62.0),
            Block(rect(x0, -11.0, x1, 11.0), 62.0, 329.0),
            Block(rect(x0, 11.0, x1, 29.0), 62.0, 285.0),
            Block(rect(x0, -29.0, x1, -11.0), 62.0, 219.0)]


def _wtc_4(d):
    """4 World Trade Center (Fumihiko Maki, 2013), 298 m: a parallelogram
    following the site up to the 46th floor, then a trapezoid, its east side
    cut on a slant, to the roof. Wikipedia, "4 World Trade Center"."""
    parallelogram = [(-28.9, -29.9), (42.1, -30.4), (39.6, 29.8), (-28.8, 30.2), (-42.1, 26.0)]
    trapezoid = [(-28.9, -29.9), (30.0, -30.3), (12.0, 29.9), (-28.8, 30.2), (-42.1, 26.0)]
    return [Block(FOOTPRINT, 0.0, 30.0), Block(parallelogram, 30.0, 196.0), Block(trapezoid, 196.0, 297.7)]


def _park_place_30(d):
    """30 Park Place (Robert A.M. Stern, 2016), 282 m: a wider four-story
    base, then a slim column about 27 m square with notched corners, one
    setback at the top of the hotel (about the 24th floor), and five stepped
    setbacks with corner terraces from about 265 m. Buff precast like
    limestone. Wikipedia, "30 Park Place"."""
    parts = [Block(FOOTPRINT, 0.0, 18.0),
             Block(chamfered(-15.5, -16.5, 15.5, 16.5, 3.0), 18.0, 100.0),
             Block(chamfered(-13.5, -13.5, 13.5, 13.5, 3.0), 100.0, 256.0)]
    for k, half in enumerate((12.5, 11.5, 10.3, 9.0, 7.5)):
        parts.append(Block(chamfered(-half, -half, half, half, 3.5), 256.0 + 5.2 * k, 261.2 + 5.2 * k))
    return parts + [Block(square(0.0, 0.0, 10.0), 282.0, 286.0)]


def _greenwich_125(d):
    """125 Greenwich Street (Rafael Vinoly, 2023), 278 m: a slim rounded
    parallelogram on an eight-story dark base, its crown set back. Wikipedia,
    "125 Greenwich Street"."""
    shaft = softened([(-14.3, -11.6), (18.3, -12.0), (17.8, 11.8), (-18.3, 12.0)], 4.0, d)
    return [Block(FOOTPRINT, 0.0, 30.0, seed=glass_office(4, dark_frame=True), kind=facades.MODERN_OFFICE),
            Block(shaft, 30.0, 262.0),
            Block(scaled(shaft, 0.82), 262.0, 278.0)]


def _leonard_56(d):
    """56 Leonard Street (Herzog & de Meuron, 2017), 250 m: glass boxes
    stacked like a game of Jenga, cantilevering 3-7.6 m, most in the lowest
    seven floors and the top nine or ten. Its footprint record says 78 m
    (measured during construction). Wikipedia, "56 Leonard Street"."""
    parts = [Block(rect(-20.0, -15.0, 19.0, 15.0), 0.0, 30.0),
             Block(rect(-15.0, -12.5, 14.0, 12.5), 30.0, 205.0)]
    boxes = [(-18, -12, 14, 13), (-14, -15, 17, 11), (-19, -11, 13, 15), (-13, -14, 18, 12), (-17, -16, 12, 13),
             (-12, -12, 17, 15), (-18, -13, 13, 12), (-13, -15, 15, 11), (-15, -11, 11, 13)]
    if d == 2:
        boxes = boxes[::3]
    zs = np.linspace(205.0, 250.0, len(boxes) + 1)
    for (x0, y0, x1, y1), z0, z1 in zip(boxes, zs[:-1], zs[1:]):
        parts.append(Block(rect(x0, y0, x1, y1), z0, z1, soffit=True))
    return parts


def _brooklyn_tower(d):
    """The Brooklyn Tower (SHoP, 2022), Brooklyn's tallest: an elongated
    hexagon of dark fluted steel and glass east of the Dime Savings Bank,
    its long side along Flatbush Avenue Extension, with slight setbacks on
    all six faces near the top (roof 315 m) and corner fins to about 326 m.
    The bank (1908, marble, its dome 33.5 m) is the 3-D model's shape.
    Wikipedia, "The Brooklyn Tower"; the tower's place from OpenStreetMap's
    building parts."""
    hexa = hexagon(-4.0, 16.6, 38.0, 26.0, 140.0)
    bank = dict(kind=facades.PREWAR_OFFICE, flags=facades.LANDMARK, seed=limestone(2))
    parts = [Model(**bank, details=(0,)), Block(Minus(FOOTPRINT, [hexa]), 0.0, 24.0, details=(1, 2), **bank),
             Block(hexa, 0.0, 250.0)]
    for z0, z1, s in ((250.0, 280.0, 0.95), (280.0, 300.0, 0.9), (300.0, 315.0, 0.85), (315.0, 326.0, 0.8)):
        parts.append(Block(scaled(hexa, s), z0, z1))
    return parts


def _city_point(d):
    """City Point (Brooklyn): its tower, 189 m, on the retail podium the 3-D
    model has (24-34 m). Wikipedia, "City Point (Brooklyn)"; the tower's
    place from OpenStreetMap's building parts."""
    tower = rect(-6.0, -18.0, 23.0, 12.0)
    return [Model(kind=facades.STORE, flags=0, details=(0,)),
            Block(Minus(FOOTPRINT, [tower]), 0.0, 24.0, kind=facades.STORE, details=(1, 2)),
            Block(tower, 0.0, 189.0)]


def _fifth_520(d):
    """520 Fifth Avenue (KPF, 2025), about 305 m, at Fifth Avenue and 43rd
    Street: a beige terracotta base, then a slim tower whose setbacks spiral
    up it asymmetrically to an arched crown. Its footprint record says 281 m
    (measured before topping out). Wikipedia, "520 Fifth Avenue"."""
    return [Block(FOOTPRINT, 0.0, 40.0),
            Block(rect(-18.0, -12.0, 18.0, 12.0), 40.0, 200.0),
            Block(rect(-18.0, -12.0, 14.0, 12.0), 200.0, 240.0),
            Block(rect(-14.0, -12.0, 14.0, 9.0), 240.0, 268.0),
            Block(rect(-14.0, -9.0, 11.0, 9.0), 268.0, 288.0),
            Block(rect(-11.0, -8.0, 9.0, 7.0), 288.0, 305.0)]


def _murray_111(d):
    """111 Murray Street (KPF, 2018), 241 m: a rounded glass square about
    25 m wide that flares gently from the 40th floor to about 29 m, like a
    champagne flute, under a curved crown higher on the south side (roof
    228 m). Wikipedia, "111 Murray Street"."""
    shaft = softened(square(0.0, -0.5, 25.0), 5.0, d)
    flare = scaled(shaft, 29.0 / 25.0)
    return [Block(shaft, 0.0, 160.0),
            Block(shaft, 160.0, 228.0, top=flare),
            Block(flare, 228.0, 235.0, slope=(0.0, -0.4))]


def _w66_50(d):
    """50 West 66th Street (Snohetta), 236 m: a 15-story limestone podium
    through the block, then a slimmer glass and bronze shaft with opposite
    corners carved out, its crown tapering the corners to a point. Its
    footprint record says 219 m (measured before topping out). Wikipedia,
    "50 West 66th Street"; the shaft's place from OpenStreetMap's building
    parts."""
    cx, cy, h = -6.6, 12.0, 13.0
    shaft = [(cx - h + 2, cy - h), (cx + h, cy - h), (cx + h, cy + h - 7), (cx + h - 7, cy + h),
             (cx - h, cy + h), (cx - h, cy - h + 2)]
    return [Block(FOOTPRINT, 0.0, 58.0, kind=facades.PREWAR_APARTMENT, flags=facades.LANDMARK,
                  seed=limestone(1, office=False)),
            Block(shaft, 58.0, 212.0),
            Block(shaft, 212.0, 236.0, top=scaled(shaft, 0.15))]


def _park_520(d):
    """520 Park Avenue (Robert A.M. Stern, 2018), 238 m of Indiana limestone,
    mid-block on 60th Street: its lot is 18 m wide, and above the Grolier
    Club next door the tower cantilevers 9 m east; a crown with four corner
    chimneys. Wikipedia, "520 Park Avenue"."""
    x0, y0, x1, y1 = -9.2, -10.5, 18.2, 10.5
    parts = [Block(FOOTPRINT, 0.0, 30.0),
             Block(rect(x0, y0, x1, y1), 30.0, 214.0, soffit=True),
             Block(chamfered(x0 + 1.5, y0 + 1.5, x1 - 1.5, y1 - 1.5, 3.0), 214.0, 226.0)]
    for cx in (x0 + 4.0, x1 - 4.0):
        for cy in (y0 + 4.0, y1 - 4.0):
            parts.append(Block(square(cx, cy, 3.0), 226.0, 238.0, details=(0, 1)))
    return parts


def _e22_45(d):
    """45 East 22nd Street (KPF, 2017), 237 m of blue-gray glass: a granite
    base, then a tower 19 x 16 m near the bottom that widens, mostly to the
    west, to 29 x 16 m, under a faceted prow that echoes the Flatiron.
    Wikipedia, "45 East 22nd Street"."""
    low = [(-3.1, -8.0), (15.9, -8.0), (15.9, 8.0), (-3.1, 8.0), (-3.1, 3.0), (-3.1, -2.0)]
    wide = [(-11.7, -8.0), (15.9, -8.0), (15.9, 8.0), (-9.8, 8.0), (-15.9, 3.0), (-15.9, -2.0)]
    return [Block(rect(-7.1, -9.0, 15.9, 9.0), 0.0, 22.0, kind=facades.PREWAR_OFFICE, flags=facades.LANDMARK,
                  seed=limestone(1)),
            Block(low, 22.0, 140.0, top=wide),
            Block(wide, 140.0, 225.0),
            Block(wide, 225.0, 237.0, top=scaled(wide, 0.8))]


def _amsterdam_200(d):
    """200 Amsterdam Avenue (Elkus Manfredi, 2021), 204 m: a limestone base,
    then glass between masonry piers, the Amsterdam Avenue (east) face
    stepping back seven times from about mid-height, under a stepped crown
    about 20 m tall. Wikipedia, "200 Amsterdam"."""
    parts = [Block(FOOTPRINT, 0.0, 100.0)]
    for k in range(7):
        parts.append(Block(rect(-14.8, -18.0, 13.3 - 1.6 * k, 18.0), 100.0 + 12.0 * k, 112.0 + 12.0 * k))
    return parts + [Block(rect(-13.0, -15.0, 0.0, 15.0), 184.0, 196.0),
                    Block(rect(-11.0, -11.0, -2.0, 11.0), 196.0, 203.6)]


def _brooklyn_point(d):
    """Brooklyn Point (KPF, 2021) at City Point, 219.5 m to the roof: a
    slightly wider four-story base, a straight glass shaft and a crown that
    slopes up to a point over its rooftop pool. Wikipedia, "City Point
    (Brooklyn)"; KPF."""
    return [Block(FOOTPRINT, 0.0, 18.0),
            Block(Shrunk(1.5), 18.0, 205.0),
            Block(Shrunk(1.5), 205.0, 216.0, slope=(0.35, 0.0))]


def _w29_601(d):
    """601 West 29th Street (2023), 194 m: a tower of about 60 stories at the
    east end of a block-long low podium by the Hudson River Park. The
    tower's place from the 2024 aerial photo (its roof and tanks)."""
    tower = rect(29.0, -24.0, 60.0, 30.4)
    return [Block(Minus(FOOTPRINT, [tower]), 0.0, 24.0), Block(tower, 0.0, 194.2)]


def _five_pointz(d):
    """5Pointz (22-44 Jackson Avenue, Long Island City, 2019): two towers,
    47 and 41 stories, on a podium filling the block along the rail line.
    The towers' places from the 2024 aerial photo (their roofs)."""
    a = turned(rect(-54.0, 5.0, -32.0, 33.0), -33.0)
    b = turned(rect(24.0, -53.0, 46.0, -25.0), -33.0)
    return [Block(Minus(FOOTPRINT, [a, b]), 0.0, 22.0), Block(a, 0.0, 151.8), Block(b, 0.0, 132.0)]


TOWERS = [
    # Billionaires' Row and midtown.
    Tower("Central Park Tower", (1090180,), 472.4, _central_park_tower, floor=4.4, seed=glass_residential(2)),
    Tower("111 West 57th Street", (1023728,), 434.5, _w57_111, kind=facades.PREWAR_OFFICE, floor=4.3,
          flags=facades.LANDMARK, seed=terracotta(1)),
    Tower("432 Park Avenue", (1088817, 1035787), 425.5, _park_432, floor=4.7, seed=concrete_grid()),
    Tower("One Vanderbilt", (1090825,), 427.0, _vanderbilt, kind=facades.MODERN_OFFICE, floor=4.6,
          seed=glass_office(2)),
    Tower("270 Park Avenue", (1091010,), 423.0, _park_270, kind=facades.MODERN_OFFICE, floor=5.0,
          seed=glass_office(1, dark_frame=True)),
    Tower("53 West 53rd Street", (1090777,), 320.0, _w53_53, floor=3.8, seed=glass_residential(1)),
    Tower("520 Fifth Avenue", (1091887,), 305.0, _fifth_520, kind=facades.PREWAR_APARTMENT, floor=3.8,
          flags=facades.LANDMARK, seed=terracotta(0, office=False)),
    Tower("220 Central Park South", (1090184,), 290.0, _cps_220, kind=facades.PREWAR_APARTMENT, floor=3.9,
          flags=facades.LANDMARK, seed=limestone(1, office=False)),
    Tower("50 West 66th Street", (1028168,), 236.0, _w66_50, seed=glass_residential(1)),
    Tower("520 Park Avenue", (1090526,), 238.0, _park_520, kind=facades.PREWAR_APARTMENT, floor=4.2,
          flags=facades.LANDMARK, seed=limestone(0, office=False)),
    Tower("45 East 22nd Street", (1089831,), 237.0, _e22_45, floor=3.9, seed=glass_residential(4)),
    Tower("200 Amsterdam Avenue", (1030358,), 203.6, _amsterdam_200, floor=3.6, seed=glass_residential(3)),
    # Hudson Yards and Manhattan West.
    Tower("30 Hudson Yards", (1088961,), 387.0, _hudson_yards_30, kind=facades.MODERN_OFFICE, floor=4.5,
          seed=glass_office(0)),
    Tower("The Spiral", (1090122,), 314.4, _spiral, kind=facades.MODERN_OFFICE, floor=4.7, seed=glass_office(2)),
    Tower("50 Hudson Yards", (1090274,), 308.2, _hudson_yards_50, kind=facades.MODERN_OFFICE, floor=5.3,
          seed=glass_office(4)),
    Tower("35 Hudson Yards", (1091590,), 305.0, _hudson_yards_35, kind=facades.PREWAR_OFFICE, floor=4.2,
          flags=facades.LANDMARK, seed=limestone(0)),
    Tower("One Manhattan West", (1089972,), 304.0, _manhattan_west_1, kind=facades.MODERN_OFFICE, floor=4.5,
          seed=glass_office(3)),
    Tower("Two Manhattan West", (1089694,), 285.0, _manhattan_west_2, kind=facades.MODERN_OFFICE, floor=4.8,
          seed=glass_office(3)),
    Tower("15 Hudson Yards", (1089411,), 278.6, _hudson_yards_15, floor=3.2, seed=glass_residential(0)),
    Tower("10 Hudson Yards", (1089323,), 268.0, _hudson_yards_10, kind=facades.MODERN_OFFICE, floor=5.0,
          seed=glass_office(3)),
    Tower("55 Hudson Yards", (1089412,), 238.0, _hudson_yards_55, kind=facades.MODERN_OFFICE, floor=4.6,
          seed=glass_office(4, dark_frame=True)),
    Tower("601 West 29th Street", (1091671,), 194.2, _w29_601, floor=3.2, seed=glass_residential(1)),
    # Lower Manhattan.
    Tower("3 World Trade Center", (1088797,), 329.0, _wtc_3, kind=facades.MODERN_OFFICE, floor=4.1,
          seed=glass_office(3, dark_frame=True)),
    Tower("4 World Trade Center", (1088795,), 297.7, _wtc_4, kind=facades.MODERN_OFFICE, floor=4.0,
          seed=glass_office(2)),
    Tower("30 Park Place", (1089428,), 286.0, _park_place_30, kind=facades.PREWAR_APARTMENT, floor=3.4,
          flags=facades.LANDMARK, seed=limestone(0, office=False)),
    Tower("125 Greenwich Street", (1090832,), 278.0, _greenwich_125, floor=3.2, seed=glass_residential(2)),
    Tower("56 Leonard Street", (1088646,), 250.0, _leonard_56, floor=4.4, seed=glass_residential(2)),
    Tower("111 Murray Street", (1089698,), 235.5, _murray_111, floor=3.9, seed=glass_residential(0)),
    # Brooklyn.
    Tower("The Brooklyn Tower", (3000370,), 326.0, _brooklyn_tower, floor=4.25, seed=glass_residential(4)),
    Tower("Brooklyn Point", (3396962,), 226.8, _brooklyn_point, floor=3.2, seed=glass_residential(2)),
    Tower("City Point", (3329438,), 189.0, _city_point, floor=3.3, seed=glass_residential(2)),
    # Queens.
    Tower("5Pointz", (4596913,), 151.8, _five_pointz, floor=3.2, seed=glass_residential(1)),
]

_BY_BIN = {b: t for t in TOWERS for b in t.bins}
_HEIGHT = {b: t.height for t in TOWERS for b in t.bins}


def has(bin_number: int) -> bool:
    return bin_number in _BY_BIN


def heights(bins: np.ndarray, heights_: np.ndarray) -> np.ndarray:
    """Building heights with the table's towers at their real heights (so far
    tiles keep them out of the merged low blocks)."""
    out = np.asarray(heights_, np.float64).copy()
    for k, b in enumerate(np.asarray(bins).tolist()):
        if b in _HEIGHT:
            out[k] = _HEIGHT[b]
    return out


def mask(bins: np.ndarray) -> np.ndarray:
    """Which of these buildings the table draws."""
    return np.isin(np.asarray(bins), list(_BY_BIN))


def add(builder, index: int, w: dict, settings: dict, ground_of, faces_street, add_shape) -> int:
    """Draws building `index` (of the prepared buildings in w["b"]) if it's
    the main building of a table tower; its other buildings draw nothing.
    ground_of(footprint), faces_street(middles, outward) and add_shape(builder,
    shape, ground, facade) are build_tiles.py's. Returns triangles added."""
    b, f = w["b"], w["facades"]
    bin_number = int(b["bin"][index])
    tower = _BY_BIN[bin_number]
    if bin_number != tower.bins[0]:
        return 0
    footprint = b["geoms"][index]
    ground = ground_of(footprint)
    seed = float(b["seed"][index]) if tower.seed is None else tower.seed
    flags = int(f["flags"][index]) & ~(facades.LANDMARK | facades.CORNICE)
    detail = DETAIL[w["level"]]
    frame = Frame.of(footprint, tower.angle)
    outline = shapely.simplify(footprint, settings["building_tolerance"], preserve_topology=True)
    outline = max(polygons_of(outline, 1.0), key=lambda p: p.area)
    count = 0
    floor_dm = int(round(np.clip(tower.floor, facades.MIN_FLOOR, facades.MAX_FLOOR) * 10))
    for part in tower.build(detail):
        if detail not in part.details:
            continue
        if isinstance(part, Model):
            shape = w["shapes"].get(bin_number)
            if shape is not None:
                add_shape(builder, shape, ground, (part.kind, part.flags, int(f["floor_dm"][index]),
                                                   seed if part.seed is None else part.seed))
            continue
        kind = tower.kind if part.kind is None else part.kind
        facade = (kind, flags | tower.flags | part.flags, floor_dm, seed if part.seed is None else part.seed)
        count += _add_block(builder, part, frame, outline, ground, facade, faces_street)
    return count


class Frame:
    def __init__(self, origin, angle_degrees):
        a = math.radians(angle_degrees)
        self.origin = np.asarray(origin, np.float64)
        self.ex = np.array([math.cos(a), math.sin(a)])
        self.ey = np.array([-math.sin(a), math.cos(a)])

    @staticmethod
    def of(footprint, angle_degrees):
        """The frame centered on the footprint's bounding box in its axes."""
        a = math.radians(angle_degrees)
        ex, ey = np.array([math.cos(a), math.sin(a)]), np.array([-math.sin(a), math.cos(a)])
        c = shapely.get_coordinates(footprint)
        x, y = c @ ex, c @ ey
        return Frame(ex * (x.min() + x.max()) / 2 + ey * (y.min() + y.max()) / 2, angle_degrees)

    def to_world(self, local):
        p = np.asarray(local, np.float64)
        return self.origin + p[..., :1] * self.ex + p[..., 1:2] * self.ey

    def to_local(self, en):
        p = np.asarray(en, np.float64) - self.origin
        return np.stack([p @ self.ex, p @ self.ey], axis=-1)


def _outlines(outline, frame: Frame, footprint) -> list:
    """A part's outline(s) as counter-clockwise (N, 2) east/north rings."""
    if isinstance(outline, Minus):
        geom = _geom(outline.outline, frame, footprint)
        for cut in outline.cut:
            geom = shapely.difference(geom, _geom(cut, frame, footprint))
        return [np.asarray(shapely.orient_polygons(p).exterior.coords)[:-1] for p in polygons_of(geom, 1.0)]
    if isinstance(outline, str):
        return [np.asarray(shapely.orient_polygons(footprint).exterior.coords)[:-1]]
    if isinstance(outline, Shrunk):
        geom = shapely.buffer(footprint, -outline.by, join_style="mitre")
        return [np.asarray(shapely.orient_polygons(p).exterior.coords)[:-1] for p in polygons_of(geom, 1.0)]
    ring = frame.to_world(outline)
    return [ring if _area(ring) > 0 else ring[::-1]]


def _geom(outline, frame, footprint):
    if isinstance(outline, str):
        return footprint
    return shapely.make_valid(Polygon(frame.to_world(outline)))


def _area(ring) -> float:
    x, y = ring[:, 0], ring[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def _add_block(builder, part: Block, frame: Frame, footprint, ground: float, facade: tuple, faces_street) -> int:
    kind, flags, floor_dm, seed = facade
    steel = kind == landmarks.STEEL
    count = 0
    rings = _outlines(part.outline, frame, footprint)
    for ring in rings:
        if part.top is not None:
            top = frame.to_world(part.top)
            if _area(frame.to_world(part.outline)) < 0:
                top = top[::-1]
        else:
            top = ring
        # Heights of the top ring (sloped tops rise along local x and y).
        local_top = frame.to_local(top)
        top_z = ground + part.z1 + local_top[:, 0] * part.slope[0] + local_top[:, 1] * part.slope[1]
        bottom_z = ground + part.z0 - (SINK if part.z0 <= 0.0 else 0.0)
        count += _walls(builder, ring, top, bottom_z, top_z, ground, facade, faces_street, steel)
        count += _cap(builder, top, top_z, ground, facade, steel, up=True)
        if part.soffit:
            count += _cap(builder, ring, np.full(len(ring), bottom_z), ground, facade, steel, up=False)
    return count


def _uv2(kind, flags, floor_dm, seed, steel, width=0.0):
    if steel:
        return (float(kind + facades.FLAG_SCALE * flags), float(round(width * 10.0) * 4) + landmarks.SEED)
    return facades.encode(kind, flags, floor_dm, seed)


def _walls(builder, bottom, top, bottom_z, top_z, ground, facade, faces_street, steel) -> int:
    """Walls between a bottom ring (at bottom_z) and a top ring (same count,
    at top_z per point), each a quad; leaning ones too."""
    kind, flags, floor_dm, seed = facade
    n = len(bottom)
    nxt = np.roll(np.arange(n), -1)
    a, b, c, d = bottom, bottom[nxt], top[nxt], top
    edge = b - a
    length = np.hypot(edge[:, 0], edge[:, 1])
    top_edge = c - d
    top_length = np.hypot(top_edge[:, 0], top_edge[:, 1])
    keep = (length > 0.05) | (top_length > 0.05)
    along = np.where(length[:, None] > 0.05, edge, top_edge)
    along /= np.maximum(np.linalg.norm(along, axis=1, keepdims=True), 1e-9)
    outward = np.column_stack([along[:, 1], -along[:, 0]])
    start = np.concatenate([[0.0], np.cumsum(length)[:-1]])
    middles = (a + b + c + d) / 4
    front = faces_street(middles, outward) if not steel else np.zeros(n, dtype=bool)
    count = 0
    for k in np.flatnonzero(keep):
        p = np.array([[*a[k], bottom_z], [*b[k], bottom_z], [*c[k], top_z[nxt[k]]], [*d[k], top_z[k]]])
        # The face's normal (east/north/up), pointing out.
        normal = np.cross(p[1] - p[0], p[3] - p[0]) if length[k] > 0.05 else np.cross(p[2] - p[0], p[3] - p[0])
        if np.linalg.norm(normal) < 1e-9:
            normal = np.cross(p[2] - p[0], p[3] - p[1])
        normal /= max(np.linalg.norm(normal), 1e-12)
        if normal[:2] @ outward[k] < 0:
            normal = -normal
        u = start[k] + (p[:, :2] - a[k]) @ along[k]
        uv = np.column_stack([u, p[:, 2] - ground])
        if normal[2] > ROOF_FACING:
            uv = np.column_stack([p[:, 0], -p[:, 1]])
            uv2 = _uv2(kind, flags | facades.ROOF, floor_dm, seed, steel)
        else:
            uv2 = _uv2(kind, flags | (facades.FRONT if front[k] else 0), floor_dm, seed, steel,
                       max(length[k], top_length[k]))
        tris = [[0, 1, 2], [0, 2, 3]]
        pos = np.stack([p[:, 0], p[:, 2], -p[:, 1]], axis=-1)
        builder.add(pos[tris], uv[tris], uv2, (normal[0], normal[2], -normal[1]))
        count += 2
    return count


def _cap(builder, ring, z, ground, facade, steel, up=True) -> int:
    """A roof over a ring (east/north, heights z per point), or with `up` off,
    a soffit facing down."""
    kind, flags, floor_dm, seed = facade
    z = np.asarray(z, np.float64)
    if np.ptp(z) < 1e-6:
        tris = triangles_of(Polygon(ring))
        if tris is None:
            return 0
        tris = np.concatenate([tris, np.full(tris.shape[:2] + (1,), z[0])], axis=-1)
        normal = np.array([0.0, 0.0, 1.0])
    else:
        tris = triangulate_planar([np.column_stack([ring, z])])
        if tris is None:
            return 0
        normal = np.cross(tris[0, 1] - tris[0, 0], tris[0, 2] - tris[0, 0])
        normal /= max(np.linalg.norm(normal), 1e-12)
        if normal[2] < 0:
            normal = -normal
    if not up:
        normal = -normal
    if normal[2] > ROOF_FACING or not up:
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        uv2 = _uv2(kind, flags | facades.ROOF, floor_dm, seed, steel)
    else:
        # A steep top (a slanted crown) is glass like the walls.
        level = np.array([-normal[1], normal[0]])
        level /= max(np.linalg.norm(level), 1e-12)
        uv = np.stack([tris[..., :2] @ level, tris[..., 2] - ground], axis=-1)
        uv2 = _uv2(kind, flags, floor_dm, seed, steel)
    pos = np.stack([tris[..., 0], tris[..., 2], -tris[..., 1]], axis=-1)
    builder.add(pos, uv, uv2, (normal[0], normal[2], -normal[1]))
    return len(tris)
