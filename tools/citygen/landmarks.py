"""Hand-made landmarks: New York's most famous buildings, modeled here at
their real dimensions in place of the footprint prisms and 3-D model shapes.

Each landmark replaces the data buildings with its BINs (build_tiles.py drops
them) and is added once per detail level, to the tile holding its main
building's anchor (or its `at`), into that tile's buildings surface: no extra
draw calls, it streams with the levels of detail, and near tiles give it
collision. Faces carry a landmark material in the archetype slot of uv2.x (16
and up; the data buildings use 0-15, see facades.py), which
shaders/building.gdshader paints; the second batch's own materials (OWN_SHADER
and up) go to the tile's landmarks surface instead, painted by
shaders/landmark.gdshader, and the waterfront's (WATERFRONT_SHADER and up) to
its waterfront surface, painted by shaders/waterfront.gdshader (one more draw
call each where there's one):

  uv2.x = material + FLAG_SCALE * flags (facades.ROOF on roofs)
  uv2.y = param + SEED; on walls param = face width in dm * 4 + variant
  uv    = walls: (m from the face's left corner seen from outside, m above
          the landmark's ground); roofs: local (x, y) in m; some materials
          use their own (see the material list)

Massing below the hand-made tops comes from the city's 3-D Building Model
(buildings3d.py) where it has the building: its roof levels sliced into
terraces, cleaned up and squared to the building's axes, so setbacks are where
the city measured them. Crowns, masts, spires, the statue and the rest are
built here from published dimensions (sources with each landmark).

Coordinates: each landmark has a frame on the ground: an origin (east/north
m, the main footprint's centroid) and the direction of its local x axis; its
z is meters above where the main building stands (its footprint's lowest
corner on our terrain, like the data buildings).
"""

import math
from dataclasses import dataclass

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import Polygon
from shapely.geometry import shape as geojson_shape

import buildings3d
import facades
from common import FEET, load_features, polygon_normal, polygons_of, project, triangles_of

# Landmark materials (the archetype slot of uv2.x). Same numbers in
# shaders/building.gdshader.
PLAIN_STONE = 16     # plain limestone: plinths, parapets, ledges
PAVING = 17          # paved roof terraces and decks (roofs)
ESB_BASE = 18        # Empire State: the five-floor limestone base with shops
ESB_SHAFT = 19       # limestone piers, window strips, aluminum spandrels, steel mullions
ESB_CROWN = 20       # the setbacks above the 86th floor, floodlit at night
ESB_MAST = 21        # the mooring mast: aluminum ribs, the 102nd floor's windows
ANTENNA = 22         # dark steel, aircraft warning lights
CHRYSLER_SHAFT = 23  # white brick with gray bands
CHRYSLER_CROWN = 24  # stainless arches with triangular windows: uv = (m from the
                     # face's middle, m above the arch's springing), param's width
                     # = the arch's radius
STEEL = 25           # stainless steel (spire, eagles)
WTC_PODIUM = 26      # One WTC's base: glass fins over concrete
WTC_GLASS = 27       # One WTC's curtain wall
WTC_SPIRE = 28       # the spire, white, with a beacon
FLATIRON = 29        # limestone and terracotta; variant 1 the cornice
WOOLWORTH = 30       # cream gothic terracotta
COPPER = 31          # green copper roofs
LIBERTY = 32         # the statue's copper
GOLD = 33            # the torch's flame
PEDESTAL = 34        # granite; variant 1 the loggias' back walls
FORT = 35            # Fort Wood's granite walls
GC_FACADE = 36       # Grand Central; variant 1 the 42nd Street front, 2 the gable ends
GC_SCULPTURE = 37    # the sculpture group's stone
CLOCK = 38           # Grand Central's clock: uv = (m right of its center, m up)
ROCK_SHAFT = 39      # 30 Rockefeller Plaza: limestone piers, dark spandrels
WTC_RING = 40        # the ring at the foot of One WTC's spire
# The second batch.
GUGGENHEIM = 41      # white painted concrete: 0 the spiral's bands, 1 the glass strips between
                     # them, 2 plain walls with window bands (the name on the bridge), 3 the
                     # annex's limestone grid; uv on the spiral = (m around, z)
NYPL = 42            # Vermont marble: 0 the walls, 1 the Fifth Avenue portico, 2 the attic
CATHEDRAL = 43       # gray-tan marble Gothic: 0 aisles and chapels, 1 the clerestory and
                     # gables, 2 the west front's central wall (and plates: its gable), 3 the
                     # towers, lanterns and spires (uv on spires = (share across a face * 3.6, z))
SLATE = 44           # slate roofs; on pitched roofs uv = (m along the eaves, m up the slope)
UN_GLASS = 45        # the Secretariat's blue-green curtain walls and mechanical floors
UN_MARBLE = 46       # 0 white marble and limestone, 1 glass between marble piers, 2 the
                     # Conference Building's bands
CITIGROUP = 47       # 0 aluminum and glass bands, 1 the crown's slope (uv = (m across, z)),
                     # 2 the stilts and core, 3 St. Peter's granite
HEARST = 48          # the diagrid tower: 0 a face (uv = (m from its middle, z), param's width
                     # the face's full width), 1 a corner's "bird's mouth"
HEARST_BASE = 49     # 0 the 1928 cast-stone base, 1 the glass clerestory above it
MET = 50             # limestone: 0 the wings, 1 Hunt's central facade, 2 plain walls
SKYLIGHT = 51        # glass roofs (roofs); on walls glass panes with white mullions
VESSEL = 52          # copper-clad flights of stairs: uv = (honeycomb cells around, z)
WHITE_STEEL = 53     # 0 white-painted steel (the Oculus's ribs: uv = (m around, m along)),
                     # 1 the stadium's frieze
STADIUM = 54         # 0 limestone with arched openings, 1 the same with the name in gold,
                     # 2 the stands' risers, 3 the scoreboard
PLAYFIELD = 55       # roofs: 0 a ball field (uv = m from home plate toward second base, m to
                     # its left), 1 seats, 2 a fountain pool, 3 lawn
UNISPHERE = 56       # stainless steel: 0 the lattice, 1 a whole globe painted (uv = degrees
                     # east, north), 2 the continents' plates (the same uv)
RIDE = 57            # painted steel: 0 white, 1 blue, 2 red with LED lights (uv = (m around,
                     # m along)), 3 the Wonder Wheel's cars and its sign
MARQUEE = 58         # Radio City Music Hall: 0 the marquee (4.4 to 7.4 m up), 1 the vertical
                     # sign (uv = m across its face, m above its foot)
GOTHIC = 59          # St. Patrick's carved work, in CATHEDRAL's marble: 0 plain (reveals,
                     # buttresses, parapets), 1 pinnacles, crockets and gables, 2 a window's
                     # glass and tracery (the rose window on the central front), 3 a portal's
                     # bronze doors under its tympanum; walls' uv on the face they're set in
# The waterfront.
PIERSIDE = 60        # ferry terminals and pier sheds: 0 a glass curtain wall, 1 brick (the slip
                     # houses), 2 metal panels with window bands, 3 white-painted steel; roofs
                     # metal, the canopies' undersides (down) steel
TIMBER = 61          # 0 fender racks (timber piles), 1 decking (docks; roofs: boards), 2 a boat
                     # (white hull and cabin), 3 a Staten Island ferry (orange); boats' bands by
                     # their height above the water
# Materials from here on are painted by shaders/landmark.gdshader, in the tiles'
# landmarks surface (the buildings' shader would grow too big to compile fast),
# and from WATERFRONT_SHADER on by shaders/waterfront.gdshader, in the
# waterfront surface (so the landmarks' shader stays small too).
OWN_SHADER = GUGGENHEIM
WATERFRONT_SHADER = PIERSIDE

ROOF = facades.ROOF
FLAG_SCALE = facades.FLAG_SCALE
SEED = 0.5  # landmarks' "random seed" (the shader doesn't randomize them)

# Detail levels: 0 near tiles, 1 mid, 2 far.
DETAIL = {"lod0": 0, "lod1": 1, "lod2": 2}
# Terraces from the 3-D model, per detail level: roof levels this close (m)
# merge, notches narrower than twice OPEN close, outlines simplify to TOLERANCE,
# and parts smaller than MIN_PART (m^2) go.
MERGE = (1.2, 3.0, 6.0)
OPEN = (0.6, 1.2, 2.5)
TOLERANCE = (0.3, 1.0, 2.5)
MIN_PART = (2.0, 15.0, 60.0)
# Segments around round parts per detail level, scaled by each part.
ROUND = (16, 10, 6)


class Model:
    """A landmark's triangles in its local frame (x, y on the ground, z up, m),
    each with a material, flags and a param (see the module notes)."""

    def __init__(self, detail: int):
        self.detail = detail
        self.pos, self.uv, self.code, self.param, self.front, self.normals = [], [], [], [], [], []

    def add(self, pos, uv, material, param, front, normals=None, flags=0):
        pos = np.asarray(pos, np.float64).reshape(-1, 3, 3)
        count = len(pos)
        if count == 0:
            return
        self.pos.append(pos)
        self.uv.append(np.asarray(uv, np.float64).reshape(count, 3, 2))
        self.code.append(np.full(count, float(material + FLAG_SCALE * flags)))
        self.param.append(np.broadcast_to(np.asarray(param, np.float64), (count,)).copy())
        front = np.broadcast_to(np.asarray(front, np.float64), (count, 3)).copy()
        self.front.append(front)
        self.normals.append(np.repeat(front[:, None], 3, axis=1) if normals is None
                            else np.asarray(normals, np.float64).reshape(count, 3, 3))

    def triangles(self) -> int:
        return sum(len(p) for p in self.pos)

    def walls(self, ring, z0, z1, material, variant=0, flags=0, closed=True):
        """Vertical walls along `ring` ((N, 2); for an outline counter-clockwise,
        the outside right of travel) from z0 to z1 (scalars or per point).
        `variant` is a number or a function (face middle (2,), outward (2,)) -> number."""
        a = np.asarray(ring, np.float64)[:, :2]
        if closed and len(a) > 1 and np.allclose(a[0], a[-1]):
            a = a[:-1]
        n = len(a)
        z0 = np.broadcast_to(np.asarray(z0, np.float64), n).copy()
        z1 = np.broadcast_to(np.asarray(z1, np.float64), n).copy()
        if closed:
            b, z0b, z1b = np.roll(a, -1, axis=0), np.roll(z0, -1), np.roll(z1, -1)
        else:
            a, b, z0b, z1b, z0, z1 = a[:-1], a[1:], z0[1:], z1[1:], z0[:-1], z1[:-1]
        d = b - a
        width = np.hypot(d[:, 0], d[:, 1])
        keep = (width > 0.03) & ((z1 > z0 + 1e-3) | (z1b > z0b + 1e-3))
        if not keep.any():
            return
        a, b, d, width, z0, z1, z0b, z1b = a[keep], b[keep], d[keep], width[keep], z0[keep], z1[keep], z0b[keep], z1b[keep]
        out = np.column_stack([d[:, 1], -d[:, 0]]) / width[:, None]
        if callable(variant):
            variants = np.array([variant((p + q) / 2, o) for p, q, o in zip(a, b, out)], np.float64)
        else:
            variants = np.full(len(a), float(variant))
        a0, b0 = np.column_stack([a, z0]), np.column_stack([b, z0b])
        b1, a1 = np.column_stack([b, z1b]), np.column_stack([a, z1])
        pos = np.stack([np.stack([a0, b0, b1], 1), np.stack([a0, b1, a1], 1)], 1).reshape(-1, 3, 3)
        zeros = np.zeros(len(a))
        uv_a0, uv_b0 = np.column_stack([zeros, z0]), np.column_stack([width, z0b])
        uv_b1, uv_a1 = np.column_stack([width, z1b]), np.column_stack([zeros, z1])
        uv = np.stack([np.stack([uv_a0, uv_b0, uv_b1], 1), np.stack([uv_a0, uv_b1, uv_a1], 1)], 1).reshape(-1, 3, 2)
        param = np.repeat(np.round(width * 10.0) * 4 + variants, 2)
        front = np.repeat(np.column_stack([out, zeros]), 2, axis=0)
        self.add(pos, uv, material, param, front, flags=flags)

    def cap(self, geom, z, material, variant=0, flags=ROOF, down=False):
        """Flat polygons (local x/y) at height z, facing up (or down)."""
        for poly in polygons_of(geom, 0.05):
            tris = triangles_of(poly)
            if tris is None:
                continue
            pos = np.concatenate([tris, np.full(tris.shape[:2] + (1,), float(z))], axis=-1)
            self.add(pos, tris, material, float(variant), (0.0, 0.0, -1.0 if down else 1.0), flags=flags)

    def prism(self, geom, z0, z1, material, roof=PAVING, variant=0, bottom=False, roof_variant=0):
        """Walls around every part (holes included) of a polygon, and a roof."""
        for poly in polygons_of(geom, 0.05):
            poly = shapely.orient_polygons(poly)
            for ring in (poly.exterior, *poly.interiors):
                self.walls(np.asarray(ring.coords), z0, z1, material, variant)
            if roof is not None:
                self.cap(poly, z1, roof, roof_variant)
            if bottom:
                self.cap(poly, z0, material, flags=0, down=True)

    def loft(self, rings, material, variant=0, flags=0, smooth=True, close_bottom=False, close_top=False,
             along=False):
        """A surface through rings of points ((N, 3) each, the same N), each
        running counter-clockwise around the direction the rings advance, so
        the faces point out. uv = (m around, z) or with `along`, (m around, m
        along the rings' centers)."""
        rings = np.asarray(rings, np.float64)
        count, n = rings.shape[:2]
        nxt = np.roll(np.arange(n), -1)
        a0, b0 = rings[:-1], rings[:-1][:, nxt]
        b1, a1 = rings[1:][:, nxt], rings[1:]
        face = np.cross(b1 - a0, a1 - b0)
        face /= np.maximum(np.linalg.norm(face, axis=-1, keepdims=True), 1e-12)
        # Smooth normals: each vertex averages the faces around it.
        vertex = np.zeros_like(rings)
        vertex[:-1] += face + np.roll(face, 1, axis=1)
        vertex[1:] += face + np.roll(face, 1, axis=1)
        vertex /= np.maximum(np.linalg.norm(vertex, axis=-1, keepdims=True), 1e-12)
        around = np.concatenate([np.zeros((count, 1)),
                                 np.cumsum(np.linalg.norm(np.roll(rings, -1, axis=1) - rings, axis=-1), axis=1)], 1)
        if along:
            centers = rings.mean(axis=1)
            v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(centers, axis=0), axis=-1))])
            v = np.broadcast_to(v[:, None], (count, n + 1))
        else:
            v = np.concatenate([rings[..., 2], rings[:, :1, 2]], axis=1)
        idx = np.arange(n)
        uv_a0 = np.stack([around[:-1, idx], v[:-1, idx]], -1)
        uv_b0 = np.stack([around[:-1, idx + 1], v[:-1, idx + 1]], -1)
        uv_b1 = np.stack([around[1:, idx + 1], v[1:, idx + 1]], -1)
        uv_a1 = np.stack([around[1:, idx], v[1:, idx]], -1)
        n_a0, n_b0, n_b1, n_a1 = vertex[:-1], vertex[:-1][:, nxt], vertex[1:][:, nxt], vertex[1:]
        if not smooth:
            n_a0 = n_b0 = n_b1 = n_a1 = face
        pos = np.stack([np.stack([a0, b0, b1], -2), np.stack([a0, b1, a1], -2)], -3).reshape(-1, 3, 3)
        uv = np.stack([np.stack([uv_a0, uv_b0, uv_b1], -2), np.stack([uv_a0, uv_b1, uv_a1], -2)], -3).reshape(-1, 3, 2)
        normals = np.stack([np.stack([n_a0, n_b0, n_b1], -2), np.stack([n_a0, n_b1, n_a1], -2)], -3).reshape(-1, 3, 3)
        front = np.repeat(face.reshape(-1, 3), 2, axis=0)
        perimeter = float(around[0, -1])
        self.add(pos, uv, material, round(perimeter * 10.0) * 4 + variant, front, normals, flags)
        for ring, sign in ((rings[0], -1.0), (rings[-1], 1.0)):
            if (sign < 0 and not close_bottom) or (sign > 0 and not close_top):
                continue
            self._fan(ring, sign, material, flags)

    def _fan(self, ring, sign, material, flags):
        center = ring.mean(axis=0)
        nxt = np.roll(ring, -1, axis=0)
        pos = np.stack([np.broadcast_to(center, ring.shape), nxt, ring] if sign < 0 else
                       [np.broadcast_to(center, ring.shape), ring, nxt], 1)
        normal = np.cross(pos[:, 1] - pos[:, 0], pos[:, 2] - pos[:, 0])
        normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-12)
        self.add(pos, pos[..., :2], material, 0.0, normal, flags=flags | (ROOF if sign > 0 and normal[:, 2].mean() > 0.5 else 0))

    def box(self, center, size, material, yaw=0.0, roof=None, variant=0):
        """An upright box (local frame), turned `yaw` radians about z."""
        cx, cy, cz = center
        sx, sy, sz = size
        corners = np.array([[-sx, -sy], [sx, -sy], [sx, sy], [-sx, sy]]) * 0.5
        c, s = math.cos(yaw), math.sin(yaw)
        corners = corners @ np.array([[c, s], [-s, c]]) + [cx, cy]
        self.walls(corners, cz - sz / 2, cz + sz / 2, material, variant)
        self.cap(Polygon(corners), cz + sz / 2, roof if roof is not None else material, flags=ROOF)
        self.cap(Polygon(corners), cz - sz / 2, material, flags=0, down=True)

    def tri_plate(self, a, b, c, thickness, material, variant=0):
        """A triangle (3-D points) given a thickness: two faces and its edges.
        uv = (m along the plate's level direction, z)."""
        a, b, c = (np.asarray(p, np.float64) for p in (a, b, c))
        normal = np.cross(b - a, c - a)
        normal /= np.linalg.norm(normal)
        level = np.cross([0.0, 0.0, 1.0], normal)
        level = level / np.linalg.norm(level) if np.linalg.norm(level) > 1e-6 else np.array([1.0, 0.0, 0.0])
        off = normal * thickness / 2
        top = np.array([a + off, b + off, c + off])
        bottom = np.array([a - off, b - off, c - off])
        center = (a + b + c) / 3

        def uv(points):
            return np.column_stack([points @ level, points[:, 2]])
        self.add(top[None], uv(top)[None], material, variant, normal)
        self.add(bottom[None], uv(bottom)[None], material, variant, -normal)
        for p, q in ((0, 1), (1, 2), (2, 0)):
            quad = np.array([bottom[p], bottom[q], top[q], top[p]])
            edge = np.cross(quad[1] - quad[0], quad[3] - quad[0])
            if np.linalg.norm(edge) < 1e-9:
                continue
            edge /= np.linalg.norm(edge)
            if edge @ (quad.mean(0) - center) < 0:
                edge = -edge
            side = np.cross([0.0, 0.0, 1.0], edge)
            side = side / np.linalg.norm(side) if np.linalg.norm(side) > 1e-6 else np.array([1.0, 0.0, 0.0])
            quad_uv = np.column_stack([quad @ side, quad[:, 2]])
            self.add(quad[[[0, 1, 2], [0, 2, 3]]], quad_uv[[[0, 1, 2], [0, 2, 3]]], material, variant, edge)


def rect(x0, y0, x1, y1) -> Polygon:
    return Polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])


def chamfered(cx, cy, hx, hy, c=0.0) -> Polygon:
    """A rectangle around (cx, cy) with half sizes (hx, hy), corners cut by c."""
    if c <= 0.0:
        return rect(cx - hx, cy - hy, cx + hx, cy + hy)
    return Polygon([(cx - hx + c, cy - hy), (cx + hx - c, cy - hy), (cx + hx, cy - hy + c), (cx + hx, cy + hy - c),
                    (cx + hx - c, cy + hy), (cx - hx + c, cy + hy), (cx - hx, cy + hy - c), (cx - hx, cy - hy + c)])


def circle(cx, cy, r, n, z=0.0, start=0.0) -> np.ndarray:
    """(n, 3) points counter-clockwise around (cx, cy) at height z."""
    t = start + np.arange(n) * (2 * np.pi / n)
    return np.column_stack([cx + r * np.cos(t), cy + r * np.sin(t), np.full(n, float(z))])


def segments(detail: int, scale: float = 1.0, least: int = 4) -> int:
    return max(least, int(round(ROUND[detail] * scale)))


def tower(model, cx, cy, profile, n, material, close_top=True, start=None, smooth=True, variant=0, flags=0):
    """A round (n-sided) tower: profile = [(z, radius), ...] bottom up."""
    start = np.pi / n if start is None else start
    rings = [circle(cx, cy, max(r, 1e-3), n, z, start) for z, r in profile]
    model.loft(rings, material, variant=variant, flags=flags, smooth=smooth, close_top=close_top)


# --- Terraces from the city's 3-D model ---

def model_terraces(shape, frame, top: float, detail: int) -> list:
    """The 3-D model's building as stacked terraces in the landmark's frame:
    [(level, polygon)] bottom up, each polygon the building's outline from the
    level below up to `level` (m above the model's ground), up to `top`."""
    vertices, offsets, ring_polygon, kinds, model_ground = shape
    starts = np.searchsorted(ring_polygon, np.arange(len(kinds)))
    ends = np.append(starts[1:], len(ring_polygon))
    roofs = []
    for polygon in np.flatnonzero(np.asarray(kinds) == buildings3d.ROOF):
        rings = [vertices[offsets[r]:offsets[r + 1]].astype(np.float64) for r in range(starts[polygon], ends[polygon])]
        if len(rings[0]) < 3 or abs(polygon_normal(rings[0])[2]) < 0.3:
            continue
        poly = shapely.make_valid(Polygon(frame.to_local(rings[0][:, :2]),
                                          [frame.to_local(h[:, :2]) for h in rings[1:] if len(h) >= 3]))
        level = float(rings[0][:, 2].max() - model_ground)
        if level > 0.5 and poly.area > 0.05:
            roofs.append((level, poly))
    if not roofs:
        return []
    levels = sorted({level for level, _ in roofs})
    clusters = []
    for level in levels:
        if clusters and level - clusters[-1][-1] <= MERGE[detail]:
            clusters[-1].append(level)
        else:
            clusters.append([level])
    out = []
    for cluster in clusters:
        level = min(cluster[-1], top)
        if out and level - out[-1][0] < 0.5:
            break
        pieces = [shapely.buffer(p, 0.05, join_style="mitre") for lv, p in roofs if lv >= cluster[0] - 1e-3]
        outline = _clean(shapely.union_all(pieces), detail)
        if outline.is_empty:
            break
        out.append((level, outline))
        if cluster[-1] >= top:
            break
    return out


def _clean(geom, detail):
    w = OPEN[detail]
    geom = shapely.buffer(shapely.buffer(geom, -w, join_style="mitre"), w, join_style="mitre")
    geom = shapely.buffer(shapely.buffer(geom, w, join_style="mitre"), -w, join_style="mitre")
    geom = shapely.simplify(geom, TOLERANCE[detail])
    parts = []
    for poly in polygons_of(geom, MIN_PART[detail]):
        holes = [h for h in poly.interiors if Polygon(h).area >= MIN_PART[detail]]
        parts.append(shapely.orient_polygons(Polygon(poly.exterior, holes)))
    return shapely.MultiPolygon(parts) if parts else Polygon()


def add_terraces(model, terraces, material, roof=PAVING):
    """Walls and roofs for model_terraces(); `material(bottom, top)` gives a
    tier's (material, variant), the variant a number or a function of a face
    (see Model.walls); `roof` is a material, a (material, variant), or a
    function of the level giving either."""
    bottom = -1.0  # walls' feet sink into the ground, like the data buildings
    for k, (level, outline) in enumerate(terraces):
        kind, variant = material(max(bottom, 0.0), level)
        for poly in polygons_of(outline, 0.05):
            for ring in (poly.exterior, *poly.interiors):
                model.walls(np.asarray(ring.coords), bottom, level, kind, variant)
        above = terraces[k + 1][1] if k + 1 < len(terraces) else Polygon()
        kind = roof(level) if callable(roof) else roof
        kind, variant = kind if isinstance(kind, tuple) else (kind, 0)
        model.cap(shapely.difference(outline, above) if not above.is_empty else outline, level, kind, variant)
        bottom = level


# --- Frames, placement ---

@dataclass
class Frame:
    origin: np.ndarray  # east/north
    angle: float        # radians: the local x axis, counter-clockwise from east

    def to_local(self, en):
        d = np.asarray(en, np.float64) - self.origin
        c, s = math.cos(self.angle), math.sin(self.angle)
        return np.column_stack([d[:, 0] * c + d[:, 1] * s, -d[:, 0] * s + d[:, 1] * c])

    def to_world(self, xy):
        xy = np.asarray(xy, np.float64)
        c, s = math.cos(self.angle), math.sin(self.angle)
        return np.stack([self.origin[0] + xy[..., 0] * c - xy[..., 1] * s,
                         self.origin[1] + xy[..., 0] * s + xy[..., 1] * c], axis=-1)


def footprint_frame(footprint, nominal_degrees: float) -> Frame:
    """The footprint's centroid, and the direction of one of its smallest
    enclosing rectangle's sides closest to `nominal_degrees`."""
    corners = np.asarray(shapely.oriented_envelope(footprint).exterior.coords)[:4]
    edge = corners[1] - corners[0]
    base = math.atan2(edge[1], edge[0])
    nominal = math.radians(nominal_degrees)
    best = min((base + k * math.pi / 2 for k in range(4)),
               key=lambda a: abs((a - nominal + math.pi) % (2 * math.pi) - math.pi))
    centroid = np.asarray(footprint.centroid.coords)[0]
    return Frame(centroid, best)


def place(model: Model, builder, frame: Frame, ground: float, own_builder=None, waterfront_builder=None) -> None:
    """Adds a model to a tile's MeshBuilders (Godot space), standing at
    `ground`: faces in the materials from OWN_SHADER on to `own_builder` (the
    landmarks surface, shaders/landmark.gdshader), from WATERFRONT_SHADER on to
    `waterfront_builder` (the waterfront surface, shaders/waterfront.gdshader),
    the rest to `builder` (the buildings surface)."""
    c, s = math.cos(frame.angle), math.sin(frame.angle)

    def rotate(v):
        return np.stack([v[..., 0] * c - v[..., 1] * s, v[..., 2], -(v[..., 0] * s + v[..., 1] * c)], axis=-1)

    for pos, uv, code, param, front, normals in zip(model.pos, model.uv, model.code, model.param, model.front,
                                                    model.normals):
        en = frame.to_world(pos[..., :2])
        world = np.stack([en[..., 0], pos[..., 2] + ground, -en[..., 1]], axis=-1)
        uv2 = np.repeat(np.column_stack([code, param + SEED])[:, None, :], 3, axis=1)
        material = np.mod(code, FLAG_SCALE)
        own = (material >= OWN_SHADER) if own_builder is not None else np.zeros(len(code), bool)
        waterfront = own & (material >= WATERFRONT_SHADER) if waterfront_builder is not None else np.zeros(len(code), bool)
        own &= ~waterfront
        for target, keep in ((builder, ~own & ~waterfront), (own_builder, own), (waterfront_builder, waterfront)):
            if keep.any():
                target.add(world[keep], uv[keep], uv2[keep], rotate(front[keep]), rotate(normals[keep]))


# --- The landmarks ---

@dataclass
class Landmark:
    name: str
    bins: tuple          # data buildings it replaces; the first is the main one
    angle: float         # nominal direction of the local x axis (degrees from east)
    build: object        # build(model, context)
    at: tuple = None     # (east, north) of its frame's origin if not the main footprint's
                         # centroid; for landmarks without bins also where they're anchored
    exact: bool = False  # local x exactly at `angle` (else the footprint's side nearest it)


def _flat(xy) -> np.ndarray:
    return np.zeros(len(np.asarray(xy).reshape(-1, 2)))


@dataclass
class Context:
    footprint: object    # the main building's footprint (east/north)
    frame: Frame
    shape: object        # the 3-D model's shape for the main BIN, or None
    detail: int
    ground: object = _flat  # ground(local xy (N, 2)): the terrain's height above the base (m)
    base: float = 0.0    # the base's height above sea level (m)


def _empire_state(m: Model, ctx: Context) -> None:
    """Empire State Building (Shreve, Lamb & Harmon, 1931). Setbacks up to the
    85th floor from the city's 3-D model (it agrees with the published floor
    heights: the 86th floor deck at 320 m, the 102nd floor at 373 m); above
    them the 86th floor observatory, the crown's steps and the mooring mast
    measured from the same model, and the antenna to the official tip at
    443.2 m (1,454 ft; CTBUH). Local x runs west along 34th Street, y south;
    the crown is centered at (-4.7, -0.2)."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 315.5, d) if ctx.shape else []
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (ESB_BASE, 0) if hi < 27.0 else (ESB_SHAFT, 0))
    cx, cy = -4.7, -0.2
    steps = [(315.5, 322.7, 21.1, 13.05, 1.5), (322.7, 327.7, 16.6, 10.25, 2.0), (327.7, 333.4, 13.2, 8.8, 1.8),
             (333.4, 336.2, 10.45, 8.8, 0.0), (336.2, 342.7, 9.2, 7.6, 0.6)]
    if d == 0:
        # The 86th floor promenade's parapet, around the deck.
        deck = chamfered(cx, cy, 22.4, 14.2, 1.2)
        inner = shapely.buffer(deck, -0.45, join_style="mitre")
        m.prism(shapely.difference(deck, inner), 315.5, 317.0, ESB_CROWN, roof=PLAIN_STONE)
    for z0, z1, hx, hy, c in steps:
        m.prism(chamfered(cx, cy, hx, hy, c), z0, z1, ESB_CROWN, roof=PAVING if z1 < 330 else PLAIN_STONE)
    # The mast: a glass and aluminum drum (variant 1) with four aluminum wings
    # at its corners, the 102nd floor's glass drum, a cap, and the antenna.
    n = segments(d, 1.0, 8)
    tower(m, cx, cy, [(342.7, 5.3), (370.0, 5.3)], n, ESB_MAST, close_top=False, variant=1)
    for degrees in (39.6, 180.0 - 39.6, 180.0 + 39.6, -39.6):
        a = math.radians(degrees)
        direction = np.array([math.cos(a), math.sin(a)])
        root = np.array([cx, cy]) + direction * 4.8
        tip = np.array([cx, cy]) + direction * 9.4
        knee = np.array([cx, cy]) + direction * 7.4
        top = np.array([cx, cy]) + direction * 5.4
        thick = 1.1 if d < 2 else 1.8
        if d == 0:
            # Stepped like the real wings: a steep outer edge, then a long taper.
            m.tri_plate((*root, 342.7), (*tip, 342.7), (*knee, 352.0), thick, ESB_MAST)
            m.tri_plate((*root, 342.7), (*knee, 352.0), (*top, 371.0), thick, ESB_MAST)
            m.tri_plate((*root, 342.7), (*top, 371.0), (*root, 371.0), thick, ESB_MAST)
        else:
            m.tri_plate((*root, 342.7), (*tip, 342.7), (*top, 371.0), thick, ESB_MAST)
    tower(m, cx, cy, [(370.0, 5.45), (377.2, 5.45), (377.2, 5.15), (382.2, 5.15), (382.2, 3.0), (383.5, 2.6)],
          n, ESB_MAST)
    tower(m, cx, cy, [(383.5, 2.1), (419.0, 1.6)], 4, ANTENNA, start=math.radians(39.6))
    tower(m, cx, cy, [(419.0, 0.9), (436.0, 0.45), (443.2, 0.15)], segments(d, 0.5, 4), ANTENNA)


def _chrysler(m: Model, ctx: Context) -> None:
    """Chrysler Building (William Van Alen, 1930). The tower up to the crown
    from the city's 3-D model; the crown's seven tiers of stainless steel
    arches (Nirosta) with triangular windows, the 61st floor's eagles and the
    spire ("vertex", 125 ft) to the official 318.9 m (1,046 ft; CTBUH), with
    the arches' widths and springing heights measured from the model's steps.
    Local x runs west along 42nd Street; the tower is centered at (-2.9, 1.95)."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 237.5, d) if ctx.shape else []
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (CHRYSLER_SHAFT, 0))
    cx, cy = -2.9, 1.95
    half = [10.45, 9.25, 8.05, 6.85, 5.65, 4.45, 3.25]
    springing = [237.5 + 5.8 * k for k in range(7)]
    samples = (12, 6, 4)[d]
    base = 235.0
    for k, (h, zc) in enumerate(zip(half, springing)):
        inner = half[k + 1] if k + 1 < len(half) else 1.7
        _arch_tier(m, cx, cy, h, inner, zc, h, base, samples)
        base = zc
    spire_base = springing[-1] + half[-1]
    tower(m, cx, cy, [(spire_base - 2.0, 1.9), (spire_base + 6.0, 1.45), (300.0, 0.6), (318.9, 0.05)],
          segments(d, 0.5, 4), STEEL, start=math.pi / 4)
    if d == 0:
        # The eagles: two on each corner of the 61st floor, looking out.
        for sx in (-1, 1):
            for sy in (-1, 1):
                corner = np.array([cx + sx * 12.6, cy + sy * 12.8])
                for turn in (-0.33, 0.33):
                    a = math.atan2(sy, sx) + turn
                    direction = np.array([math.cos(a), math.sin(a)])
                    root = corner - direction * 0.5
                    tip = corner + direction * 4.2
                    m.tri_plate((*root, 211.0), (*tip, 212.6), (*root, 214.2), 1.6, STEEL)
                    m.tri_plate((*root, 211.6), (*(corner + direction * 3.0), 211.9), (*root, 212.6), 2.4, STEEL)


def _arch_tier(m, cx, cy, h, inner, zc, rise, base, samples):
    """One tier of the Chrysler crown: four faces half-width `h` whose tops
    arch from the corners (at zc) up to zc + rise in the middle, from `base`
    up; and the ledge behind each arch, back to the next tier (half-width
    `inner`) at the arch's height."""
    u = np.linspace(-h, h, 2 * samples + 1)
    top = zc + rise * np.sqrt(np.clip(1.0 - (u / h) ** 2, 0.0, 1.0))
    for side in range(4):
        a = side * np.pi / 2
        c, s = math.cos(a), math.sin(a)
        # Face along local -y (rotated by a): points (u, -h), outward (0, -1).
        outer = np.column_stack([u, np.full_like(u, -h)])
        back = np.column_stack([u * inner / h, np.full_like(u, -inner)])
        rot = np.array([[c, s], [-s, c]])
        outer = outer @ rot + [cx, cy]
        back = back @ rot + [cx, cy]
        # The arched wall: quads from base up to the arch.
        a0 = np.column_stack([outer[:-1], np.full(len(u) - 1, base)])
        b0 = np.column_stack([outer[1:], np.full(len(u) - 1, base)])
        b1 = np.column_stack([outer[1:], top[1:]])
        a1 = np.column_stack([outer[:-1], top[:-1]])
        pos = np.stack([np.stack([a0, b0, b1], 1), np.stack([a0, b1, a1], 1)], 1).reshape(-1, 3, 3)
        rise_at = top - zc
        uv_a0 = np.column_stack([u[:-1], np.full(len(u) - 1, base - zc)])
        uv_b0 = np.column_stack([u[1:], np.full(len(u) - 1, base - zc)])
        uv_b1 = np.column_stack([u[1:], rise_at[1:]])
        uv_a1 = np.column_stack([u[:-1], rise_at[:-1]])
        uv = np.stack([np.stack([uv_a0, uv_b0, uv_b1], 1), np.stack([uv_a0, uv_b1, uv_a1], 1)], 1).reshape(-1, 3, 2)
        out = np.array([0.0, -1.0]) @ rot
        m.add(pos, uv, CHRYSLER_CROWN, round(h * 10.0) * 4, (out[0], out[1], 0.0))
        # The ledge: from the arch back to the next tier, level across.
        a0 = np.column_stack([outer[:-1], top[:-1]])
        b0 = np.column_stack([outer[1:], top[1:]])
        b1 = np.column_stack([back[1:], top[1:]])
        a1 = np.column_stack([back[:-1], top[:-1]])
        pos = np.stack([np.stack([a0, b0, b1], 1), np.stack([a0, b1, a1], 1)], 1).reshape(-1, 3, 3)
        normal = np.cross(pos[:, 1] - pos[:, 0], pos[:, 2] - pos[:, 0])
        normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-12)
        normal *= np.sign(normal[:, 2:3] + 1e-9)
        m.add(pos, pos[..., :2], CHRYSLER_CROWN, round(h * 10.0) * 4, normal, flags=ROOF)


def _one_wtc(m: Model, ctx: Context) -> None:
    """One World Trade Center (SOM, David Childs, 2014): a 200 ft square
    (here the footprint data's square) on a 186 ft (56.7 m) podium of glass
    fins, then eight triangles: the square's sides rise as upright triangles
    to the roof at 417 m (1,368 ft), where the top square is turned 45
    degrees, its corners over the base's sides (as the city's 3-D model
    shows); the ring at the foot of the spire, and the 408 ft spire to
    541.3 m (1,776 ft). Sources: SOM, Port Authority, CTBUH."""
    d = m.detail
    corners = np.asarray(shapely.oriented_envelope(ctx.footprint).exterior.coords)[:4]
    local = ctx.frame.to_local(corners)
    hx = float(local[:, 0].max() - local[:, 0].min()) / 2
    hy = float(local[:, 1].max() - local[:, 1].min()) / 2
    cx = float(local[:, 0].max() + local[:, 0].min()) / 2
    cy = float(local[:, 1].max() + local[:, 1].min()) / 2
    podium, roof, parapet = 56.7, 410.5, 417.0
    m.prism(rect(cx - hx, cy - hy, cx + hx, cy + hy), -1.0, podium, WTC_PODIUM, roof=None)
    # The shaft: four upright triangles in the sides' planes and four sloped
    # ones turned down to the base's corners.
    t = lambda z: (z - podium) / (parapet - podium)
    square = np.array([[-hx, -hy], [hx, -hy], [hx, hy], [-hx, hy]]) + [cx, cy]
    mids = np.array([[0, -hy], [hx, 0], [0, hy], [-hx, 0]]) + [cx, cy]
    for k in range(4):
        a, b = square[k], square[(k + 1) % 4]
        apex = mids[k]
        width = float(np.linalg.norm(b - a))
        out = np.array([(b - a)[1], -(b - a)[0]]) / width
        pos = [[(*a, podium), (*b, podium), (*apex, parapet)]]
        uv = [[(0.0, podium), (width, podium), (width / 2, parapet)]]
        m.add(pos, uv, WTC_GLASS, round(width * 10) * 4, (out[0], out[1], 0.0))
        # The sloped triangle from this corner b up to the top square's side.
        nxt = mids[(k + 1) % 4]
        p0, p1, p2 = np.array([*b, podium]), np.array([*nxt, parapet]), np.array([*apex, parapet])
        normal = np.cross(p1 - p0, p2 - p0)
        normal /= np.linalg.norm(normal)
        if normal[:2] @ (b - [cx, cy]) < 0:
            normal = -normal
        along = (nxt - apex) / np.linalg.norm(nxt - apex)  # level, across the face
        top_width = float(np.linalg.norm(nxt - apex))
        uv = [[(float((b - apex) @ along), podium), (top_width, parapet), (0.0, parapet)]]
        m.add([[p0, p1, p2]], uv, WTC_GLASS, round(top_width * 10) * 4 + 1, normal)
    top = Polygon(mids)
    m.cap(top, parapet, PAVING)
    # The ring at the spire's foot (open steel, here a drum), and the spire.
    n = segments(d, 2.0, 8)
    tower(m, cx, cy, [(parapet, 20.5), (parapet + 9.0, 20.5)], n, WTC_RING, close_top=False)
    m.cap(Polygon(circle(cx, cy, 20.5, n, start=np.pi / n)[:, :2]), parapet + 9.0, PAVING)
    spire = [(parapet, 2.6), (431.0, 2.4), (431.0, 3.4), (433.0, 3.4), (433.0, 2.2), (470.0, 1.6), (470.0, 2.3),
             (472.0, 2.3), (472.0, 1.4), (505.0, 1.0), (505.0, 1.6), (507.0, 1.6), (507.0, 0.8), (536.0, 0.5),
             (541.3, 0.25)]
    if d == 2:
        spire = [(parapet, 2.6), (470.0, 1.6), (541.3, 0.4)]
    tower(m, cx, cy, spire, segments(d, 0.5, 6), WTC_SPIRE)


def _flatiron(m: Model, ctx: Context) -> None:
    """Flatiron Building (Daniel Burnham, 1902): the footprint data's
    triangle with its rounded prow, 285 ft (87 m) to the roof; the cornice at
    the 20th floor, the top floors behind it, and the 22nd floor penthouse
    set back (heights from the city's 3-D model)."""
    d = m.detail
    outline = shapely.simplify(_local_footprint(ctx), TOLERANCE[d])
    outline = polygons_of(outline, 5.0)[0] if polygons_of(outline, 5.0) else outline
    m.prism(outline, -1.0, 81.6, FLATIRON, roof=None)
    if d < 2:
        cornice = shapely.buffer(outline, 1.3, join_style="mitre")
        m.prism(cornice, 81.6, 83.4, FLATIRON, variant=1, bottom=True, roof=None)
        m.cap(shapely.difference(cornice, shapely.buffer(outline, -0.2, join_style="mitre")), 83.4, PLAIN_STONE)
        m.prism(shapely.buffer(outline, -0.2, join_style="mitre"), 83.4, 87.0, FLATIRON, variant=2)
    else:
        m.prism(outline, 81.6, 87.0, FLATIRON, variant=2)
    penthouse = shapely.buffer(outline, -1.6, join_style="mitre")
    m.prism(penthouse, 87.0, 91.0, FLATIRON, variant=3)
    if d < 2:
        m.prism(shapely.buffer(outline, -4.0, join_style="mitre"), 91.0, 93.0, PLAIN_STONE)


def _woolworth(m: Model, ctx: Context) -> None:
    """Woolworth Building (Cass Gilbert, 1913): the U-shaped base and the
    tower's setbacks from the city's 3-D model up to 197.5 m; above, the
    chamfered top stages, four corner turrets, the steep copper roof, its
    lantern and the spire to the official 241.4 m (792 ft), measured from the
    model. Local x runs east to Broadway; the tower's top is centered at
    (14.9, -0.7)."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 197.5, d) if ctx.shape else []
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (WOOLWORTH, 0))
    cx, cy = 14.9, -0.7
    m.prism(chamfered(cx, cy, 9.85, 9.95, 2.8), 197.5, 210.0, WOOLWORTH)
    m.prism(chamfered(cx, cy, 7.7, 7.6, 2.6), 210.0, 218.0, WOOLWORTH)
    n = 8
    # The pyramid: from the chamfered stage (an octagon) to the lantern.
    tower(m, cx, cy, [(218.0, 7.9), (225.0, 5.4), (232.0, 2.5)], n, COPPER, close_top=False, smooth=False,
          start=np.pi / 8)
    tower(m, cx, cy, [(232.0, 2.5), (237.5, 2.1), (237.5, 2.4), (238.3, 2.4)], n, WOOLWORTH, close_top=False,
          smooth=False, start=np.pi / 8)
    tower(m, cx, cy, [(238.3, 2.0), (241.4, 0.05)], n, COPPER, smooth=False, start=np.pi / 8)
    if d < 2:
        for sx in (-1, 1):
            for sy in (-1, 1):
                tx, ty = cx + sx * 8.5, cy + sy * 8.9
                tower(m, tx, ty, [(197.5, 1.75), (214.0, 1.75), (214.0, 1.95), (214.8, 1.95)], 8, WOOLWORTH,
                      close_top=False, smooth=False, start=np.pi / 8)
                tower(m, tx, ty, [(214.8, 1.7), (220.5, 0.05)], 8, COPPER, smooth=False, start=np.pi / 8)


def _grand_central(m: Model, ctx: Context) -> None:
    """Grand Central Terminal (Reed & Stem, Warren & Wetmore, 1913): the
    footprint data's block, its facades to the attic at 33 m (the city's
    3-D model), the copper roof over the Main Concourse (275 x 120 ft, ridge
    from the model), the 42nd Street front's three great windows, and on its
    attic Jules-Felix Coutan's "Glory of Commerce" (48 ft tall, 60 ft wide)
    around the 13 ft Tiffany clock. Local x runs east, y north."""
    d = m.detail
    outline = shapely.simplify(_local_footprint(ctx), TOLERANCE[d])
    south = float(outline.bounds[1])

    def front(middle, out):
        return 1 if out[1] < -0.9 and middle[1] < south + 3.0 else 0
    for poly in polygons_of(outline, 5.0):
        poly = shapely.orient_polygons(poly)
        m.walls(np.asarray(poly.exterior.coords), -1.0, 33.0, GC_FACADE, front)
        m.cap(poly, 33.0, PAVING)
        if d == 0:
            m.prism(shapely.difference(shapely.buffer(poly, 0.9, join_style="mitre"), poly), 26.6, 28.0,
                    PLAIN_STONE, roof=PLAIN_STONE, bottom=True)
    # The concourse roof: a copper gable, ridge east-west, gable ends glazed.
    x0, x1, y0, y1, eaves, ridge = -40.0, 40.0, south + 18.0, south + 55.0, 33.0, 41.0
    ym = (y0 + y1) / 2
    for ya, yb in ((y0, ym), (y1, ym)):
        pos = [[(x0, ya, eaves), (x1, ya, eaves), (x1, yb, ridge)], [(x0, ya, eaves), (x1, yb, ridge), (x0, yb, ridge)]]
        normal = np.cross(np.subtract(pos[0][1], pos[0][0]), np.subtract(pos[0][2], pos[0][0]))
        normal = normal / np.linalg.norm(normal) * np.sign(normal[2])
        slope = math.hypot(yb - ya, ridge - eaves)
        uv = [[(0, 0), (x1 - x0, 0), (x1 - x0, slope)], [(0, 0), (x1 - x0, slope), (0, slope)]]
        m.add(pos, uv, COPPER, 0.0, normal, flags=ROOF)
    for x, sign in ((x0, -1.0), (x1, 1.0)):
        a, b = (y1, y0) if sign < 0 else (y0, y1)
        width = abs(y1 - y0)
        pos = [[(x, a, eaves), (x, b, eaves), (x, ym, ridge)]]
        uv = [[(0, eaves), (width, eaves), (width / 2, ridge)]]
        m.add(pos, uv, GC_FACADE, round(width * 10) * 4 + 2, (sign, 0.0, 0.0))
    # The sculpture group and the clock, at the middle of the 42nd Street front.
    y = south
    m.box((0.0, y + 2.0, 34.0), (18.0, 3.6, 2.0), GC_SCULPTURE)
    if d < 2:
        m.box((0.0, y + 2.2, 39.5), (2.6, 2.0, 9.0), GC_SCULPTURE)  # Mercury
        m.box((0.0, y + 2.2, 44.8), (1.2, 1.2, 1.6), GC_SCULPTURE)  # his head
        m.tri_plate((-1.0, y + 2.4, 43.6), (-3.8, y + 2.4, 45.8), (-1.0, y + 2.4, 41.5), 0.5, GC_SCULPTURE)
        m.tri_plate((1.0, y + 2.4, 43.6), (3.8, y + 2.4, 45.8), (1.0, y + 2.4, 41.5), 0.5, GC_SCULPTURE)
        for sx in (-1.0, 1.0):  # Hercules and Minerva, reclining
            m.tri_plate((sx * 2.2, y + 2.0, 35.0), (sx * 8.6, y + 2.0, 35.0), (sx * 2.6, y + 2.0, 41.5), 2.6,
                        GC_SCULPTURE)
            m.box((sx * 3.0, y + 2.0, 41.4), (1.0, 1.0, 1.3), GC_SCULPTURE)
    n = segments(d, 1.0, 8)
    rim = circle(0.0, 0.0, 2.0, n, start=np.pi / n)
    face = [(p[0], y - 0.55, 35.6 + p[1]) for p in rim]
    back = [(p[0], y + 0.4, 35.6 + p[1]) for p in rim]
    m.loft([np.array(back), np.array(face)], GC_SCULPTURE, smooth=True, along=True)
    tris = np.array([[(0.0, y - 0.55, 35.6), face[(k + 1) % n], face[k]] for k in range(n)])
    m.add(tris, np.stack([tris[..., 0], tris[..., 2] - 35.6], -1), CLOCK, 0.0, (0.0, -1.0, 0.0))


def _rockefeller(m: Model, ctx: Context) -> None:
    """30 Rockefeller Plaza (Raymond Hood, 1933): the slab and all its
    setbacks, up to the Top of the Rock at 259 m (850 ft), from the city's
    3-D model."""
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, m.detail) if ctx.shape else []
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (ROCK_SHAFT, 0))
    else:
        m.prism(_local_footprint(ctx), -1.0, 259.0, ROCK_SHAFT)


def _liberty(m: Model, ctx: Context) -> None:
    """Statue of Liberty (Bartholdi and Eiffel, 1886) on Richard Morris Hunt's
    pedestal, in Fort Wood's eleven-pointed star (the footprint data). NPS
    statistics: ground to the top of the pedestal 154 ft (46.94 m), top of the
    base to the torch 151 ft 1 in (46.05 m: the torch at 92.99 m), heel to top
    of head 111 ft 1 in (33.86 m), right arm 42 ft (12.8 m), head 17 ft 3 in by
    10 ft, tablet 23 ft 7 in by 13 ft 7 in by 2 ft; seven rays. The pedestal
    is about 62 ft square at its base and 40 ft at its top, on a stepped
    foundation about 90 ft square that rises 65 ft from the ground. She faces
    south-east (the city's 3-D model puts her torch 5 m forward and 5 m right
    of her center). Local x runs to her right, y forward."""
    d = m.detail
    star = shapely.simplify(_local_footprint(ctx), TOLERANCE[d] + 0.2)
    star = max(polygons_of(star, 50.0), key=lambda p: p.area)
    fort = 6.5
    m.prism(Polygon(star.exterior), -1.0, fort, FORT, roof=PAVING)
    steps = [(fort, 10.0, 13.7), (10.0, 14.0, 12.2), (14.0, 19.8, 10.6)]
    for z0, z1, h in steps:
        m.prism(chamfered(0, 0, h, h), z0, z1, PEDESTAL, roof=PAVING)
    m.prism(chamfered(0, 0, 9.6, 9.6), 19.8, 21.0, PEDESTAL, roof=PEDESTAL)
    m.prism(chamfered(0, 0, 9.0, 9.0), 21.0, 23.0, PEDESTAL, roof=PEDESTAL)
    m.prism(chamfered(0, 0, 8.4, 8.4), 23.0, 31.0, PEDESTAL, roof=PEDESTAL)
    # The loggias: a recess with four columns in each face.
    h, w, depth = 8.4, 4.4, 1.5
    if d < 2:
        notched = chamfered(0, 0, h, h)
        for k in range(4):
            a = k * np.pi / 2
            box = affinity.rotate(rect(-w, -h - 1, w, -h + depth), math.degrees(a), origin=(0, 0))
            notched = shapely.difference(notched, box)
        m.prism(notched, 31.0, 37.6, PEDESTAL,
                variant=lambda middle, out: 1 if max(abs(middle[0]), abs(middle[1])) < h - 0.5 else 0)
        if d == 0:
            for k in range(4):
                a = k * np.pi / 2
                c, s = math.cos(a), math.sin(a)
                for x in (-3.0, -1.0, 1.0, 3.0):
                    px, py = x * c - (-h + 0.55) * s, x * s + (-h + 0.55) * c
                    m.box((px, py, 34.3), (0.7, 0.7, 6.6), PEDESTAL, yaw=a)
    else:
        m.prism(chamfered(0, 0, h, h), 31.0, 37.6, PEDESTAL)
    m.prism(chamfered(0, 0, 8.9, 8.9), 37.6, 40.2, PEDESTAL, roof=PEDESTAL, bottom=d == 0)
    m.prism(chamfered(0, 0, 8.0, 8.0), 40.2, 43.6, PEDESTAL, roof=PEDESTAL)
    m.prism(chamfered(0, 0, 8.7, 8.7), 43.6, 44.3, PEDESTAL, roof=PEDESTAL, bottom=d == 0)
    m.prism(chamfered(0, 0, 6.7, 6.7), 44.3, 46.94, PEDESTAL, roof=PEDESTAL)
    _statue(m, 46.94, d)


def _statue(m: Model, base: float, d: int) -> None:
    """The statue, low-poly but unmistakable: robe, raised torch, crown of
    seven rays, tablet. x right, y forward, z from the top of the pedestal."""
    n = (16, 10, 7)[d]
    t = np.arange(n) * (2 * np.pi / n) + np.pi / n

    def section(z, hw, hd, cy=0.0, cx=0.0, folds=0.0, phase=0.0, power=2.4):
        # A superellipse around (cx, cy), with vertical folds.
        c, s = np.cos(t), np.sin(t)
        r = (np.abs(c) ** power + np.abs(s) ** power) ** (-1.0 / power)
        r = r * (1.0 + folds * np.sin(7 * t + phase))
        return np.column_stack([cx + hw * r * c, cy + hd * r * s, np.full(n, base + z)])

    # Her plinth, then the robe from the hem to the shoulders.
    m.prism(chamfered(0, 0.2, 5.6, 4.8, 1.2), base, base + 1.3, LIBERTY, roof=LIBERTY)
    folds = 0.06 if d < 2 else 0.0
    robe = [(1.3, 5.2, 4.4, 0.3, 0.0, folds), (3.0, 5.0, 4.2, 0.4, 0.0, folds), (8.0, 4.6, 3.7, 0.6, 0.0, folds * 0.8),
            (13.0, 4.25, 3.25, 0.8, -0.1, folds * 0.6), (17.0, 4.1, 3.0, 0.95, -0.15, folds * 0.4),
            (21.0, 4.05, 2.85, 1.1, -0.1, folds * 0.2), (24.3, 4.45, 2.65, 1.2, 0.0, 0.0),
            (26.3, 3.6, 2.25, 1.3, 0.0, 0.0), (27.2, 1.7, 1.55, 1.4, 0.0, 0.0)]
    if d == 2:
        robe = [robe[0], robe[2], robe[4], robe[6], robe[8]]
    m.loft([section(z, hw, hd, cy, cx, f, 0.7) for z, hw, hd, cy, cx, f in robe], LIBERTY)
    # Neck and head (chin to cranium 5.26 m, 3.05 m wide).
    neck = [(27.2, 1.25), (28.7, 1.2)]
    head = [(28.3, 1.0), (28.9, 1.42), (30.0, 1.6), (31.4, 1.6), (32.5, 1.42), (33.2, 1.0), (33.55, 0.35)]
    hn = (10, 8, 6)[d]
    tower(m, 0.0, 1.45, [(base + z, r) for z, r in neck], hn, LIBERTY, close_top=False)
    rings = [circle(0.0, 1.7, r, hn, base + z) * [1.0, 1.0, 1.0] for z, r in head]
    for ring in rings:  # a little deeper than wide (the face and nose)
        ring[:, 1] = 1.7 + (ring[:, 1] - 1.7) * 1.15
    m.loft(rings, LIBERTY, close_top=True)
    # The crown: a band, and seven rays fanned over her brow.
    tower(m, 0.0, 1.7, [(base + 31.6, 1.78), (base + 32.6, 1.78)], hn, LIBERTY, close_top=False)
    rays = 7
    for k in range(rays):
        a = math.radians(-78 + 26 * k) if d < 2 else math.radians(-75 + 25 * k)
        direction = np.array([math.sin(a), math.cos(a), 0.0])
        up = np.array([0.0, 0.0, 1.0])
        root = np.array([0.0, 1.7, base + 32.3]) + direction * 1.6
        tip = root + (direction * math.cos(math.radians(20)) + up * math.sin(math.radians(20))) * 3.6
        side = np.cross(direction, up) * 0.42
        m.tri_plate(root - side, root + side, tip, 0.3, LIBERTY)
    # The raised right arm (12.8 m), with the sleeve hanging from it.
    shoulder = np.array([3.7, 1.2, base + 25.2])
    hand = np.array([5.2, 3.0, base + 37.3])
    _limb(m, shoulder, hand, 1.95, 1.05, (12, 8, 6)[d], LIBERTY)
    m.tri_plate(shoulder + [0.3, -0.2, -1.0], shoulder + (hand - shoulder) * 0.6 + [0.2, 0.0, 0.0],
                np.array([4.2, 0.9, base + 20.5]), 1.9, LIBERTY)
    # The torch: handle, the balcony's cup, the gold flame.
    handle_top = np.array([5.45, 3.45, base + 41.3])
    _limb(m, hand + [0.0, 0.0, -0.6], handle_top, 0.75, 0.6, (8, 6, 4)[d], LIBERTY)
    tn = (12, 8, 6)[d]
    tower(m, handle_top[0], handle_top[1], [(base + 41.0, 0.9), (base + 41.7, 1.75), (base + 42.6, 1.85)], tn,
          LIBERTY, close_top=True)
    tower(m, handle_top[0], handle_top[1], [(base + 42.6, 1.15), (base + 43.4, 1.3), (base + 44.4, 1.0),
                                            (base + 45.3, 0.45), (base + 46.05, 0.02)], tn, GOLD)
    # The left arm, down and forward, and the tablet against her side.
    _limb(m, np.array([-3.5, 1.1, base + 25.0]), np.array([-4.2, 0.9, base + 19.5]), 1.5, 1.2, (10, 6, 4)[d], LIBERTY)
    _limb(m, np.array([-4.2, 0.9, base + 19.5]), np.array([-4.3, 2.4, base + 19.2]), 1.15, 0.9, (8, 6, 4)[d], LIBERTY)
    _tablet(m, np.array([-4.75, 2.3, base + 21.2]), d)


def _limb(m, a, b, ra, rb, n, material):
    """A tapered tube from a to b, closed at both ends."""
    axis = b - a
    axis = axis / np.linalg.norm(axis)
    ref = np.array([0.0, 0.0, 1.0]) if abs(axis[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(axis, ref)
    u /= np.linalg.norm(u)
    v = np.cross(axis, u)
    t = np.arange(n) * (2 * np.pi / n)
    circle_ = np.cos(t)[:, None] * u + np.sin(t)[:, None] * v
    m.loft([a + ra * circle_, b + rb * circle_], material, along=True, close_bottom=True, close_top=True)


def _tablet(m, center, d):
    """The tablet (7.19 x 4.14 x 0.61 m), held upright against her left side,
    leaning back a little, its face toward her front and left."""
    length, width, thick = 7.19, 4.14, 0.61
    yaw = math.radians(28)   # its face turned this far to her left
    tilt = math.radians(14)  # its top leaning in toward her
    face = np.array([-math.sin(yaw), math.cos(yaw), 0.0])
    across = np.array([math.cos(yaw), math.sin(yaw), 0.0])
    up = np.array([0.0, 0.0, 1.0]) * math.cos(tilt) - face * math.sin(tilt)
    face = np.cross(across, up)
    corners = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                corners.append(center + across * (sx * width / 2) + up * (sz * length / 2) + face * (sy * thick / 2))
    c = np.array(corners).reshape(2, 2, 2, 3)  # [x][y][z]
    quads = [  # (corners, outward)
        ([c[0, 1, 0], c[1, 1, 0], c[1, 1, 1], c[0, 1, 1]], face),
        ([c[1, 0, 0], c[0, 0, 0], c[0, 0, 1], c[1, 0, 1]], -face),
        ([c[1, 1, 0], c[1, 0, 0], c[1, 0, 1], c[1, 1, 1]], across),
        ([c[0, 0, 0], c[0, 1, 0], c[0, 1, 1], c[0, 0, 1]], -across),
        ([c[0, 1, 1], c[1, 1, 1], c[1, 0, 1], c[0, 0, 1]], up),
        ([c[0, 0, 0], c[1, 0, 0], c[1, 1, 0], c[0, 1, 0]], -up),
    ]
    for k, (q, out) in enumerate(quads):
        q = np.array(q)
        uv = [(0.0, 0.0), (width, 0.0), (width, length), (0.0, length)] if k == 0 else [(0, 0), (1, 0), (1, 1), (0, 1)]
        uv = np.array(uv, np.float64)
        # The front face carries the inscription: variant 1, uv across and up it.
        m.add(q[[[0, 1, 2], [0, 2, 3]]], uv[[[0, 1, 2], [0, 2, 3]]], LIBERTY, 1.0 if k == 0 else 0.0, out)


def _local_footprint(ctx: Context):
    """The main footprint in the landmark's frame (largest part, no holes)."""
    parts = polygons_of(ctx.footprint, 1.0)
    out = []
    for poly in parts:
        out.append(Polygon(ctx.frame.to_local(np.asarray(poly.exterior.coords)[:, :2])))
    geom = shapely.union_all(out)
    return max(polygons_of(geom, 1.0), key=lambda p: p.area)


# --- The second batch ---

def _beam(m, a, b, w, h, material, variant=0, normal=(0.0, 0.0, 1.0), sides=4):
    """A straight member from a to b (3-D points): a box `w` wide and `h`
    deep, its depth along `normal` (as far as it's square to the member), or
    with sides=3 a triangular one about `w` across. Open ends; uv = (m around,
    m along)."""
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    along = b - a
    length = np.linalg.norm(along)
    if length < 1e-6:
        return
    along /= length
    side = np.cross(along, normal)
    if np.linalg.norm(side) < 1e-6:
        side = np.cross(along, (1.0, 0.0, 0.0) if abs(along[0]) < 0.9 else (0.0, 1.0, 0.0))
    side /= np.linalg.norm(side)
    up = np.cross(along, side)
    if sides == 3:
        t = np.radians([90.0, 210.0, 330.0])
        section = (np.cos(t)[:, None] * side + np.sin(t)[:, None] * up) * (w * 0.58)
    else:
        section = np.array([side * w / 2 + up * h / 2, -side * w / 2 + up * h / 2,
                            -side * w / 2 - up * h / 2, side * w / 2 - up * h / 2])
    m.loft([a + section, b + section], material, variant=variant, smooth=False, along=True)


def _quads(m, corners, uv, material, param, flags=0, normals=None):
    """Quads (N, 4, 3), counter-clockwise seen from their front, with uv
    (N, 4, 2), as triangles; flat normals unless given (N, 4, 3)."""
    corners = np.asarray(corners, np.float64)
    uv = np.asarray(uv, np.float64)
    param = np.broadcast_to(np.asarray(param, np.float64), (len(corners),))
    face = np.cross(corners[:, 2] - corners[:, 0], corners[:, 3] - corners[:, 1])
    size = np.linalg.norm(face, axis=-1)
    keep = size > 1e-6
    if not keep.any():
        return
    corners, uv, param, face = corners[keep], uv[keep], param[keep], face[keep] / size[keep, None]
    halves = [[0, 1, 2], [0, 2, 3]]
    tri_normals = None
    if normals is not None:
        tri_normals = np.asarray(normals, np.float64)[keep][:, halves].reshape(-1, 3, 3)
    m.add(corners[:, halves].reshape(-1, 3, 3), uv[:, halves].reshape(-1, 3, 2), material, np.repeat(param, 2),
          np.repeat(face, 2, axis=0), tri_normals, flags)


def _guggenheim(m: Model, ctx: Context) -> None:
    """Solomon R. Guggenheim Museum (Frank Lloyd Wright, 1959). The rotunda:
    on a base drum that carries the bridge's band round its front over the
    lobby's glass (set back under it), white-gray bands spiraling up around
    the ramp (432 m at a 5% grade), each band leaning out over a glass strip,
    the whole an inverted ziggurat 38 m across at the top (the footprint
    data; the drum about 35 m and the lowest band 31 m, from photos), its roof
    at 29.7 m and the skylight's twelve-sided dome to 37.5 m (the city's 3-D
    model); the Monitor (the small rotunda, four stories) to the north, the
    bridge band along Fifth Avenue with the museum's name, and Gwathmey
    Siegel's ten-story annex (1992), a limestone grid, behind. Wikipedia,
    "Solomon R. Guggenheim Museum". Local x runs west to Fifth Avenue, y
    south; the rotunda is centered at (0.2, 11.1), the Monitor at (7.7,
    -22.0)."""
    d = m.detail
    cx, cy = 0.2, 11.1
    top, z0, pitch, band, tuck, drum = 29.7, 9.6, 5.6, 4.4, 0.35, 10.9

    def radius(z):  # the bands' outer face
        return 15.4 + 3.6 * np.clip((z - z0) / (top - z0), 0.0, 1.0)

    def inner(z):  # the glass strips
        return radius(z) - 1.5
    rotunda = shapely.Point(cx, cy).buffer(19.0, quad_segs=8)
    monitor = shapely.Point(7.7, -22.0).buffer(7.6, quad_segs=6)
    annex = rect(-15.2, -30.8, -4.2, -0.4)
    # The base: the rest of the lot behind the rotunda and around the Monitor
    # (offices, the 1968 wing), to 12 m; the rotunda stands free on Fifth Avenue.
    front = rect(-3.0, -14.0, 40.0, 40.0)
    rest = shapely.difference(_local_footprint(ctx), shapely.union_all([rotunda, monitor, annex, front]))
    m.prism(shapely.simplify(rest, TOLERANCE[d]), -1.0, 12.0, GUGGENHEIM, variant=2)
    m.prism(annex, -1.0, 44.0, GUGGENHEIM, variant=3)
    if d == 2:
        # Far away: a frustum with its bands painted, and the Monitor.
        tower(m, cx, cy, [(-1.0, 15.0), (top, 19.0)], 16, GUGGENHEIM, close_top=False)
        m.cap(Polygon(circle(cx, cy, 19.0, 16, start=np.pi / 16)[:, :2]), top, PAVING)
        tower(m, 7.7, -22.0, [(-1.0, 7.5), (18.5, 7.7)], 8, GUGGENHEIM, variant=2)
        return
    # The ground floor: the lobby's glass, set back under the base drum.
    n = (72, 32)[d]
    _surface_of_revolution(m, cx, cy, [(-1.0, 14.2), (4.4, 14.2)], n, GUGGENHEIM, 1, 2 * np.pi * 14.2)
    m.cap(shapely.difference(shapely.Point(cx, cy).buffer(17.2, quad_segs=n // 4),
                             shapely.Point(cx, cy).buffer(14.2, quad_segs=n // 4)), 4.4, GUGGENHEIM, flags=0, down=True)
    _surface_of_revolution(m, cx, cy, [(4.4, 17.2), (drum, 17.8)], n, GUGGENHEIM, 0, 2 * np.pi * 17.5)
    m.cap(shapely.difference(shapely.Point(cx, cy).buffer(17.8, quad_segs=n // 4),
                             shapely.Point(cx, cy).buffer(float(inner(z0)) - 0.05, quad_segs=n // 4)), drum, GUGGENHEIM)
    # The spiral: one long strip of band (its face, underside and top ledge)
    # and the glass strip under it, around and up from the back (east). Its
    # bottom edge rises `pitch` a turn until the band reaches the roof, then
    # runs level for a last turn; each band stops short of the one above.
    per_turn = (72, 32)[d]
    turns = (top - band - z0) / pitch + 1.0
    theta = np.linspace(0.0, 2 * np.pi * turns, int(per_turn * turns) + 1)

    def bottom_at(t):
        return np.minimum(z0 + pitch * t / (2 * np.pi), top - band)

    def top_at(t):
        above = np.where(t + 2 * np.pi <= theta[-1] + 1e-9, bottom_at(t + 2 * np.pi), top)
        return np.minimum(bottom_at(t) + band, above)
    lo, hi = bottom_at(theta), top_at(theta)
    below = np.minimum(np.where(theta >= 2 * np.pi - 1e-9, top_at(theta - 2 * np.pi), drum - 0.1), lo)
    phi = np.pi + theta
    c, s = np.cos(phi), np.sin(phi)

    def at(r, z):
        return np.stack([cx + r * c, cy + r * s, z], -1)
    arc = theta * 17.0  # m around, at a middle radius

    def strip(p, q, variant, normal, flags=0):
        # Quads between consecutive samples of the lower ring p and the upper q,
        # normal = (out, up) at each sample for smooth shading round the turn.
        a0, a1, b1, b0 = p[:-1], p[1:], q[1:], q[:-1]
        if flags & ROOF:
            uv = np.stack([a0[:, :2], a1[:, :2], b1[:, :2], b0[:, :2]], 1)
        else:
            uv = np.stack([np.column_stack([arc[:-1], a0[:, 2]]), np.column_stack([arc[1:], a1[:, 2]]),
                           np.column_stack([arc[1:], b1[:, 2]]), np.column_stack([arc[:-1], b0[:, 2]])], 1)
        normal = np.broadcast_to(np.asarray(normal, np.float64), (len(c), 2))
        normal = normal / np.linalg.norm(normal, axis=-1, keepdims=True)
        n3 = np.stack([normal[:, 0] * c, normal[:, 0] * s, normal[:, 1]], -1)
        _quads(m, np.stack([a0, a1, b1, b0], 1), uv, GUGGENHEIM, 4 * 380 + variant, flags,
               normals=np.stack([n3[:-1], n3[1:], n3[1:], n3[:-1]], 1))
    lean = np.column_stack([hi - lo, -(radius(hi) - radius(lo) + tuck)])
    strip(at(inner(below), below), at(inner(lo), lo), 1, (1.0, 0.0))
    strip(at(inner(lo), lo), at(radius(lo) - tuck, lo), 0, (0.0, -1.0))
    strip(at(radius(lo) - tuck, lo), at(radius(hi), hi), 0, lean)
    strip(at(radius(hi), hi), at(inner(hi), hi), 0, (0.0, 1.0), flags=ROOF)
    # The band's first end, at the back, facing back along the spiral.
    def first(r, z):
        return (cx + r * c[0], cy + r * s[0], z)
    end = np.array([first(inner(lo[0]), lo[0]), first(radius(lo[0]) - tuck, lo[0]), first(radius(hi[0]), hi[0]),
                    first(inner(hi[0]), hi[0])])
    end_uv = np.array([[0.0, lo[0]], [1.5, lo[0]], [1.5, hi[0]], [0.0, hi[0]]])
    back = np.array([-math.sin(phi[0]), math.cos(phi[0]), 0.0]) * -1.0
    if np.cross(end[2] - end[0], end[3] - end[1]) @ back < 0:
        end, end_uv = end[::-1], end_uv[::-1]
    _quads(m, end[None], end_uv[None], GUGGENHEIM, 4 * 15)
    # The roof, and the skylight's dome (a concrete ring, then glass).
    m.cap(Polygon(circle(cx, cy, float(inner(top)) + 0.05, segments(d, 3.0))[:, :2]), top, PAVING)
    tower(m, cx, cy, [(top - 0.1, 14.0), (31.6, 11.3), (32.55, 11.2)], 12, GUGGENHEIM, close_top=False, variant=2)
    tower(m, cx, cy, [(32.55, 11.2), (35.8, 4.5), (37.55, 0.6)], 12, SKYLIGHT, smooth=False)
    # The Monitor: three bands over glass strips, and its shallow dome.
    mx, my = 7.7, -22.0
    n = segments(d, 1.6, 8)
    for z_lo, z_hi, r, variant in ((-1.0, 3.6, 7.0, 1), (3.6, 7.6, 7.5, 0), (7.6, 8.7, 7.0, 1), (8.7, 12.8, 7.6, 0),
                                   (12.8, 13.9, 7.1, 1), (13.9, 18.5, 7.7, 0)):
        tower(m, mx, my, [(z_lo, r), (z_hi, r)], n, GUGGENHEIM, close_top=False, variant=variant)
    m.cap(Polygon(circle(mx, my, 7.7, n)[:, :2]), 18.5, PAVING)
    tower(m, mx, my, [(18.5, 6.2), (19.6, 5.0), (20.3, 0.5)], n, GUGGENHEIM, variant=2)
    # The bridge along Fifth Avenue between the two, over the glass entrance.
    m.prism(rect(5.0, -14.8, 15.6, 1.0), 4.4, 7.8, GUGGENHEIM, variant=2, bottom=True)
    m.prism(rect(5.0, -14.8, 13.8, 1.0), -1.0, 4.4, GUGGENHEIM, variant=1, roof=None)


def _nypl(m: Model, ctx: Context) -> None:
    """New York Public Library, Stephen A. Schwarzman Building (Carrere and
    Hastings, 1911): Vermont marble, 120 m along Fifth Avenue; the massing
    (the wings, the courts, the reading room's block) from the city's 3-D
    model. On Fifth Avenue the central portico (three arches behind six
    Corinthian columns, statues on the attic), the 27 m terrace with its
    balustrade, the steps, and Edward Clark Potter's lions, Patience and
    Fortitude (Tennessee marble), on their pedestals either side of the steps.
    Wikipedia, "Stephen A. Schwarzman Building". Local x runs west (Bryant
    Park), y south; the Fifth Avenue front is at x = -40, the portico at -46.4."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []

    def face(middle, out):
        return 1 if out[0] < -0.9 and middle[0] < -45.0 and abs(middle[1]) < 15.5 else 0
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (NYPL, 2 if lo > 26.0 else face), roof=SLATE)
    else:
        m.prism(_local_footprint(ctx), -1.0, 27.4, NYPL, roof=SLATE)
    front = float(ctx.ground(np.array([[-60.0, 0.0]]))[0])
    terrace = front + 1.3
    # The terrace, its balustrade and the steps down to Fifth Avenue.
    m.prism(rect(-66.0, -52.0, -40.0, 52.0), -1.0, terrace, PLAIN_STONE)
    steps = 4 if d < 2 else 1
    for k in range(steps):
        x = -66.0 - 3.0 * (k + 1) / steps
        m.prism(rect(x, -13.5, -66.0 - 3.0 * k / steps, 13.5), -1.0, terrace - (k + 1) * 1.3 / (steps + 1),
                PLAIN_STONE)
    if d == 2:
        return
    if d == 0:
        for y0, y1 in ((-52.0, -13.5), (13.5, 52.0)):
            m.prism(rect(-66.0, y0, -65.6, y1), terrace, terrace + 1.0, PLAIN_STONE, roof=PLAIN_STONE)
    # The portico: six columns, the entablature and the attic's statues.
    n = segments(d, 0.6, 6)
    for y in (-13.8, -5.5, -3.8, 3.8, 5.5, 13.8):
        tower(m, -47.5, y, [(terrace, 0.8), (terrace + 0.8, 0.8), (terrace + 0.8, 0.62), (terrace + 11.5, 0.55),
                            (terrace + 12.6, 0.8)], n, NYPL, variant=2)
        if d == 0:
            m.box((-47.4, y, terrace + 15.8), (1.0, 1.0, 3.2), GC_SCULPTURE)
    m.prism(rect(-48.6, -15.0, -46.4, 15.0), terrace + 12.6, terrace + 14.2, NYPL, variant=2, bottom=True)
    if d == 0:
        m.prism(rect(-49.5, -12.0, -46.4, 12.0), terrace - 0.2, terrace + 0.35, PLAIN_STONE)
    # The lions, recumbent on their pedestals, facing Fifth Avenue.
    for y in (-16.0, 16.0):
        m.prism(rect(-68.0, y - 1.0, -63.6, y + 1.0), -1.0, terrace + 0.6, PLAIN_STONE, roof=PLAIN_STONE)
        _lion(m, np.array([-65.8, y, terrace + 0.6]), d)


def _lion(m, base, d):
    """A recumbent lion, low-poly, about 3.8 m long, its head toward -x."""
    x, y, z = base
    m.box((x + 0.3, y, z + 0.5), (2.6, 1.1, 1.0), GC_SCULPTURE)              # body
    m.box((x - 0.9, y, z + 0.85), (1.1, 1.4, 1.5), GC_SCULPTURE)             # chest and mane
    m.box((x - 1.4, y, z + 1.55), (0.8, 0.85, 0.85), GC_SCULPTURE)           # head
    if d == 0:
        m.box((x - 1.6, y - 0.35, z + 0.15), (1.4, 0.35, 0.3), GC_SCULPTURE)  # paws
        m.box((x - 1.6, y + 0.35, z + 0.15), (1.4, 0.35, 0.3), GC_SCULPTURE)
        m.box((x - 1.9, y, z + 1.4), (0.35, 0.5, 0.4), GC_SCULPTURE)         # muzzle
        m.box((x + 1.0, y, z + 0.35), (0.9, 1.2, 0.7), GC_SCULPTURE)         # haunches


class _Face:
    """A vertical face from a to b (local x/y), its outside right of travel (as
    in Model.walls): u runs m from a (its left end seen from outside), z up,
    and `depth` m into it."""

    def __init__(self, a, b):
        self.a = np.asarray(a, np.float64)
        d = np.asarray(b, np.float64) - self.a
        self.width = float(np.linalg.norm(d))
        self.along = d / self.width
        self.out = np.array([self.along[1], -self.along[0]])

    def point(self, u, z, depth=0.0):
        u, z, depth = np.broadcast_arrays(np.asarray(u, np.float64), np.asarray(z, np.float64),
                                          np.asarray(depth, np.float64))
        xy = self.a + u[..., None] * self.along - depth[..., None] * self.out
        return np.concatenate([xy, z[..., None]], axis=-1)

    def direction(self, du, dz, dout=0.0):
        """A 3-D direction from its parts along the face, up and out of it."""
        return np.array([du * self.along[0] + dout * self.out[0], du * self.along[1] + dout * self.out[1], dz])


def _arch(u0, u1, sill, apex, rise=None, n=6):
    """A pointed arch's opening as a (u, z) polygon: upright sides from `sill`,
    then two arcs meeting at `apex`, `rise` above the springing (by default an
    equilateral arch's, 0.866 of its width; half its width makes it round);
    n points to an arc."""
    w = u1 - u0
    rise = min(0.866 * w if rise is None else rise, apex - sill)
    spring = apex - rise
    r = (rise * rise + w * w / 4.0) / w
    top = math.acos(max(-1.0, min(1.0, (w / 2.0 - r) / r)))  # the apex, seen from the left arc's center
    right = [(u1 - r + r * math.cos(a), spring + r * math.sin(a)) for a in np.linspace(0.0, math.pi - top, n + 1)]
    left = [(u0 + r + r * math.cos(a), spring + r * math.sin(a)) for a in np.linspace(top, math.pi, n + 1)[1:]]
    return Polygon([(u0, sill), (u1, sill)] + right + left)


def _face_poly(m, face, poly, material, variant=0, depth=0.0, facing=1.0):
    """(u, z) polygons (holes allowed) on `face`, `depth` m in, facing out (or
    in, facing=-1); uv = (u, z), param's width the face's."""
    for part in polygons_of(poly, 0.01):
        tris = triangles_of(part)
        if tris is not None:
            m.add(face.point(tris[..., 0], tris[..., 1], depth), tris, material,
                  round(face.width * 10.0) * 4 + variant, (facing * face.out[0], facing * face.out[1], 0.0))


def _face_sides(m, face, poly, d0, d1, material, variant=0, inward=True):
    """The sides of a (u, z) polygon's outline on `face` from depth d0 to d1:
    facing into the polygon (a recess's reveals) or out of it (a projecting
    block's). uv = (m along the outline and in, z)."""
    ring = np.asarray(shapely.orient_polygons(poly).exterior.coords)
    p, q = ring[:-1], ring[1:]
    e = q - p
    length = np.hypot(e[:, 0], e[:, 1])
    keep = length > 1e-3
    p, q, e, length = p[keep], q[keep], e[keep], length[keep]
    s = np.concatenate([[0.0], np.cumsum(length)[:-1]])
    side = np.column_stack([-e[:, 1], e[:, 0]]) / length[:, None] * (1.0 if inward else -1.0)
    normal = np.column_stack([side[:, 0] * face.along[0], side[:, 0] * face.along[1], side[:, 1]])
    corners = np.stack([face.point(p[:, 0], p[:, 1], d0), face.point(q[:, 0], q[:, 1], d0),
                        face.point(q[:, 0], q[:, 1], d1), face.point(p[:, 0], p[:, 1], d1)], 1)
    uv = np.stack([np.column_stack([s + d0, p[:, 1]]), np.column_stack([s + length + d0, q[:, 1]]),
                   np.column_stack([s + length + d1, q[:, 1]]), np.column_stack([s + d1, p[:, 1]])], 1)
    halves = [[0, 1, 2], [0, 2, 3]]
    m.add(corners[:, halves].reshape(-1, 3, 3), uv[:, halves].reshape(-1, 3, 2), material, 4 * 10 + variant,
          np.repeat(normal, 2, axis=0))


def _face_recess(m, face, opening, depth, orders, inset, base=0.0, keep_sill=False):
    """Sets an opening ((u, z) polygon) into `face` from `base` to `depth` m
    in, in `orders` steps each `inset` m narrower (a Gothic portal's or
    window's orders): the reveals and the steps between them, plain stone.
    With keep_sill the orders keep the opening's foot (a doorway). Returns
    the innermost opening."""
    current = opening
    step = (depth - base) / orders
    for k in range(orders):
        d1 = base + step * (k + 1)
        _face_sides(m, face, current, base + step * k, d1, GOTHIC)
        if k + 1 == orders:
            break
        inner = shapely.buffer(current, -inset, join_style="mitre")
        if keep_sill:
            bounds = inner.bounds
            inner = shapely.union(inner, rect(bounds[0], current.bounds[1], bounds[2], bounds[1] + 0.01))
        inner = max(polygons_of(inner, 0.01), key=lambda poly: poly.area)
        _face_poly(m, face, shapely.difference(current, inner), GOTHIC, 0, d1)
        current = inner
    return current


def _crocket(m, p, up, out, size):
    """A crocket: a stone leaf curling up and out from an edge at p (3-D),
    `up` along the edge, `out` away from it (unit vectors)."""
    m.tri_plate(p, p + up * size * 1.3, p + up * size * 0.9 + out * size, size * 0.5, GOTHIC, variant=1)


def _crockets(m, a, b, out, size, spacing):
    """Crockets every `spacing` m up the edge from a to b (3-D points), their
    leaves toward `out` (made square to the edge)."""
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    length = float(np.linalg.norm(b - a))
    up = (b - a) / length
    out = np.asarray(out, np.float64) - up * (up @ np.asarray(out, np.float64))
    out /= np.linalg.norm(out)
    for t in np.arange(spacing * 0.6, length - size * 1.4, spacing):
        _crocket(m, a + up * t, up, out, size)


def _pinnacle(m, x, y, z0, z1, half, start=np.pi / 4):
    """A Gothic pinnacle on (x, y) from z0 to its tip at z1: a square shaft
    `half` m from its axis, a ledge, and a spirelet (its crockets painted)."""
    c = half * math.sqrt(2.0)
    zs = z0 + 0.4 * (z1 - z0)
    tower(m, x, y, [(z0, c), (zs, c), (zs, c * 1.2), (zs + 0.12 * (z1 - z0), c * 1.2), (zs + 0.12 * (z1 - z0), c),
                    (z1, 0.03)], 4, GOTHIC, smooth=False, variant=1, start=start)


def _gabled_frame(m, face, center, half, foot, eaves, apex, opening, out, d):
    """A Gothic portal's or window's frame: a block `out` m proud of `face`,
    `half` m either side of `center`, from `foot` up to a gable (`eaves` to
    `apex`), the opening cut through it; crockets up the gable's rakes and a
    finial on near tiles."""
    house = Polygon([(center - half, foot), (center + half, foot), (center + half, eaves), (center, apex),
                     (center - half, eaves)])
    _face_poly(m, face, shapely.difference(house, opening), GOTHIC, 1, -out)
    _face_poly(m, face, shapely.difference(house, opening), GOTHIC, 1, 0.0, facing=-1.0)
    _face_sides(m, face, house, -out, 0.0, GOTHIC, 1, inward=False)
    if d == 0:
        top = face.point(center, apex, -out / 2)
        for side in (-1.0, 1.0):
            foot_point = face.point(center + side * half, eaves, -out / 2)
            rake = np.array([-side * half, apex - eaves])
            _crockets(m, foot_point, top, face.direction(side * rake[1], abs(rake[0])), 0.45, 1.1)
        tower(m, top[0], top[1], [(apex - 0.3, 0.32), (apex + 1.4, 0.03)], 4, GOTHIC, smooth=False, variant=1,
              start=np.pi / 4)


def _openwork_spire(m, cx, cy, z0, z1, r0, r1, d, start=np.pi / 8):
    """An octagonal spire from z0 (corners r0 from its axis) to z1 (r1), in
    tiers of tracery (painted: uv = (share across a face * 3.6, z)), with
    crockets up its eight edges on near tiles."""
    tiers = (12, 4, 1)[d]
    z = np.linspace(z0, z1, tiers + 1)
    r = r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    a = start + np.arange(9) * (np.pi / 4)
    c, s = np.cos(a), np.sin(a)
    quads, uvs = [], []
    for i in range(tiers):
        for k in range(8):
            quads.append([(cx + r[i] * c[k], cy + r[i] * s[k], z[i]), (cx + r[i] * c[k + 1], cy + r[i] * s[k + 1], z[i]),
                          (cx + r[i + 1] * c[k + 1], cy + r[i + 1] * s[k + 1], z[i + 1]),
                          (cx + r[i + 1] * c[k], cy + r[i + 1] * s[k], z[i + 1])])
            uvs.append([(0.0, z[i]), (3.6, z[i]), (3.6, z[i + 1]), (0.0, z[i + 1])])
    _quads(m, np.array(quads), np.array(uvs), CATHEDRAL, round(28.8 * 10) * 4 + 3)
    if d == 0:
        for k in range(8):
            foot = np.array([cx + r0 * c[k], cy + r0 * s[k], z0])
            tip = np.array([cx + r1 * c[k], cy + r1 * s[k], z1])
            _crockets(m, foot, tip, (c[k], s[k], 0.0), 0.55, 1.65)


def _st_patricks_front(m, d, front):
    """St. Patrick's west front on near and mid tiles (see _st_patricks)."""
    orders = 3 if d == 0 else 1
    # The central wall: the main portal (9.4 x 16 m, set back 3.7 m in orders
    # to the bronze doors) under its gablet, the rose window (7.9 m) in its
    # arch above, the gable over all.
    face = _Face((front, -7.4), (front, 8.0))
    mid = face.width / 2
    portal = _arch(mid - 4.7, mid + 4.7, -1.0, 16.0, rise=6.0)
    rose_arch = _arch(mid - 6.4, mid + 6.4, 18.5, 33.0)
    _face_poly(m, face, shapely.difference(rect(0.0, -1.0, face.width, 34.0), shapely.union(portal, rose_arch)),
               CATHEDRAL, 2)
    doors = _face_recess(m, face, portal, 3.7, orders, 0.55, base=-0.7, keep_sill=True)
    _face_poly(m, face, doors, GOTHIC, 3, 3.7)
    _gabled_frame(m, face, mid, 5.7, -1.0, 12.0, 22.5, portal, 0.7, d)
    back = _face_recess(m, face, rose_arch, 1.1, max(orders - 1, 1), 0.5)
    rose = shapely.Point(mid, 26.0).buffer(4.25, quad_segs=(8, 4, 2)[d])
    _face_poly(m, face, shapely.difference(back, rose), GOTHIC, 0, 1.1)
    _face_poly(m, face, _face_recess(m, face, rose, 1.7, 1, 0.0, base=1.1), GOTHIC, 2, 1.7)
    m.cap(rect(front - 3.6, -7.4, front, 8.0), 34.0, SLATE)
    gable = Polygon([(0.0, 34.0), (face.width, 34.0), (mid, 47.5)])
    _face_poly(m, face, gable, CATHEDRAL, 2)
    _face_poly(m, face, gable, CATHEDRAL, 2, 2.7, facing=-1.0)
    _face_sides(m, face, gable, 0.0, 2.7, GOTHIC, 1, inward=False)
    if d == 0:
        top = face.point(mid, 47.5, 1.2)
        for side in (-1.0, 1.0):
            _crockets(m, face.point(mid + side * mid, 34.0, 1.2), top, face.direction(side * 13.5, mid), 0.8, 1.6)
    # The cross on the gable.
    cx, cy, _ = face.point(mid, 0.0, 1.2)
    m.box((cx, cy, 49.0), (0.5, 0.5, 3.0), GOTHIC)
    m.box((cx, cy, 49.6), (0.5, 2.0, 0.45), GOTHIC)
    # The towers.
    for y0, y1, sign in ((-17.2, -7.4, -1.0), (8.0, 17.8, 1.0)):
        outer, inner = (y0, y1) if sign < 0 else (y1, y0)
        tx, ty = (42.5 + front) / 2, (y0 + y1) / 2
        faces = [(_Face((front, y0), (front, y1)), True)]
        side = _Face((42.5, outer), (front, outer)) if sign < 0 else _Face((front, outer), (42.5, outer))
        faces.append((side, False))
        for face, has_portal in faces:
            c = face.width / 2
            low = (_arch(c - 2.0, c + 2.0, -1.0, 10.0) if has_portal else _arch(c - 1.2, c + 1.2, 3.0, 11.0))
            window = _arch(c - 1.9, c + 1.9, 16.0, 28.0)
            _face_poly(m, face, shapely.difference(rect(0.0, -1.0, face.width, 41.5), shapely.union(low, window)),
                       CATHEDRAL, 3)
            if has_portal:
                _face_poly(m, face, _face_recess(m, face, low, 1.6, orders, 0.45, base=-0.5, keep_sill=True),
                           GOTHIC, 3, 1.6)
                _gabled_frame(m, face, c, 2.8, -1.0, 8.0, 14.5, low, 0.5, d)
            else:
                _face_poly(m, face, _face_recess(m, face, low, 0.6, 1, 0.0), GOTHIC, 2, 0.6)
            _face_poly(m, face, _face_recess(m, face, window, 0.9, max(orders - 1, 1), 0.3, base=-0.35), GOTHIC, 2,
                       0.9)
            _gabled_frame(m, face, c, 2.6, 15.0, 24.5, 31.0, window, 0.35, d)
        # The back and the inner side, plain; the top, its pierced battlement.
        if sign < 0:
            m.walls([(42.5, y1), (42.5, y0)], -1.0, 41.5, CATHEDRAL, 3, closed=False)
            m.walls([(front, y1), (42.5, y1)], -1.0, 41.5, CATHEDRAL, 3, closed=False)
        else:
            m.walls([(42.5, y1), (42.5, y0)], -1.0, 41.5, CATHEDRAL, 3, closed=False)
            m.walls([(42.5, y0), (front, y0)], -1.0, 41.5, CATHEDRAL, 3, closed=False)
        square = rect(42.5, y0, front, y1)
        m.cap(square, 41.5, PAVING)
        m.prism(shapely.difference(square, shapely.buffer(square, -0.4, join_style="mitre")), 41.5, 43.0, GOTHIC,
                roof=GOTHIC)
        # Buttresses at the corners, stepping back in three stages, small
        # pinnacles on the setbacks and clustered ones on top.
        stages = ((-1.0, 15.0, 1.6), (15.0, 28.0, 1.1), (28.0, 41.5, 0.6))
        for k, (z0, z1, p) in enumerate(stages):
            for box in (rect(front - 2.0, min(outer + sign * p, outer - sign * 1.8), front + p,
                             max(outer + sign * p, outer - sign * 1.8)),
                        rect(front - 0.5, min(inner - sign * 1.8, inner + sign * 0.8), front + p,
                             max(inner - sign * 1.8, inner + sign * 0.8)),
                        rect(42.5, min(outer + sign * p, outer - sign * 1.2), 44.5,
                             max(outer + sign * p, outer - sign * 1.2))):
                m.prism(box, z0, z1, GOTHIC, roof=GOTHIC)
            if d == 0 and k < 2:
                nxt = stages[k + 1][2]
                for y in (outer - sign * 0.8, inner - sign * 0.5):
                    _pinnacle(m, front + (p + nxt) / 2, y, z1, z1 + 4.0, 0.22)
        if d < 2:
            # Each corner's cluster: a tall pinnacle and, on near tiles, two
            # smaller ones beside it along the faces.
            for x, y, h in ((front - 0.7, outer - sign * 0.6, 1.05), (front, inner - sign * 0.5, 0.95),
                            (43.5, outer - sign * 0.3, 0.95), (43.2, inner + sign * 0.7, 0.8)):
                _pinnacle(m, x, y, 41.5, 56.0, h)
                if d == 0:
                    cx, cy = (x - tx, y - ty)
                    for ox, oy in ((-np.sign(cx) * 1.9, 0.0), (0.0, -np.sign(cy) * 1.9)):
                        _pinnacle(m, x + ox, y + oy, 41.5, 50.0, 0.45)
        if d == 0:
            for x, y in ((front - 0.3, ty), (tx, outer - sign * 0.3), (tx, inner + sign * 0.3), (42.8, ty)):
                _pinnacle(m, x, y, 43.0, 48.5, 0.35)
        # The octagonal lantern with gablets and pinnacles round its top, the
        # spire, its molding between the two tiers, and the cross.
        tower(m, tx, ty, [(41.5, 4.75), (57.6, 4.75)], 8, CATHEDRAL, close_top=False, smooth=False, variant=3,
              start=np.pi / 8)
        tower(m, tx, ty, [(57.6, 5.1), (59.0, 5.1), (59.0, 4.7)], 8, CATHEDRAL, close_top=False, smooth=False,
              variant=3, start=np.pi / 8)
        corners = [(tx + 4.75 * math.cos(np.pi / 8 + k * np.pi / 4), ty + 4.75 * math.sin(np.pi / 8 + k * np.pi / 4))
                   for k in range(9)]
        if d < 2:
            for k in range(8):
                lantern = _Face(corners[k], corners[k + 1])
                _gabled_frame(m, lantern, lantern.width / 2, lantern.width / 2 - 0.25, 54.0, 56.5, 61.5,
                              Polygon(), 0.45, d)
                a = np.pi / 8 + k * np.pi / 4
                _pinnacle(m, tx + 5.2 * math.cos(a), ty + 5.2 * math.sin(a), 53.0, 63.0, 0.38)
        _openwork_spire(m, tx, ty, 59.0, 98.6, 4.7, 0.25, d)
        tower(m, tx, ty, [(78.4, 2.75), (79.6, 2.75)], 8, GOTHIC, close_top=False, smooth=False, variant=1,
              start=np.pi / 8)
        m.box((tx, ty, 99.5), (0.3, 0.3, 1.9), GOTHIC)
        m.box((tx, ty, 99.8), (0.3, 1.1, 0.25), GOTHIC)


def _st_patricks(m: Model, ctx: Context) -> None:
    """St. Patrick's Cathedral (James Renwick Jr., 1878; spires 1888): Tuckahoe
    and Lee marble Gothic on a Latin cross, weathered gray-tan. The aisles and
    chapels to 20.5 m over the footprint data's plan, the nave (15 m across,
    the clerestory's top at 32 m) and transepts (53 m across) under steep
    slate roofs to the city's 3-D model's ridge at 42.6 m, the apse. The west
    front on Fifth Avenue: the central gable (156 ft, 48 m, crocketed, with its
    cross) over the main portal (31 ft wide and 51 ft high, set back 12 ft in
    orders to the bronze doors, 16.5 ft high) and its gablet, and the rose
    window (26 ft) in a pointed arch; two towers 32 ft (9.8 m) square to
    136 ft (41.5 m), each with a portal and gablet, a window under a gable,
    four small windows to a side under a pierced battlement, buttresses at the
    corners stepping back in three stages, and clustered pinnacles on top; the
    octagonal lanterns (54 ft) with gablets and pinnacles round their tops,
    and the spires (140 ft) in two tiers of tracery, crockets up their edges,
    to 100.4 m. Wikipedia, "St. Patrick's Cathedral (Manhattan)". Local x runs
    west to Fifth Avenue, y south; the nave's axis is y = 0.4, the front at
    x = 52.3."""
    d = m.detail
    yc, eaves, ridge, aisle, front = 0.4, 32.0, 42.6, 20.5, 52.3
    plan = shapely.simplify(_local_footprint(ctx), TOLERANCE[d])
    nave = rect(-35.0, yc - 8.0, 49.6, yc + 8.0)
    transept = rect(-13.8, -22.2, 2.5, 23.8)
    apse = shapely.intersection(shapely.Point(-35.0, yc).buffer(8.0, quad_segs=4),
                                rect(-44.0, yc - 8.0, -35.0, yc + 8.0))
    cross = shapely.union_all([nave, transept, apse])
    towers = [rect(42.5, -17.2, front, -7.4), rect(42.5, 8.0, front, 17.8)]
    # Aisles and chapels, then the clerestory over the cross.
    # (Near, the west front between the towers is built on its own.)
    if d < 2:
        towers_and_front = shapely.union_all(towers + [rect(48.0, -7.4, front + 10.0, 8.0)])
    else:
        towers_and_front = shapely.union_all(towers)
    low = shapely.difference(plan, towers_and_front)
    for poly in polygons_of(low, 1.0):
        poly = shapely.orient_polygons(poly)
        m.walls(np.asarray(poly.exterior.coords), -1.0, aisle, CATHEDRAL, 0)
    m.cap(shapely.difference(low, cross), aisle, SLATE)
    for poly in polygons_of(cross, 1.0):
        poly = shapely.orient_polygons(poly)
        m.walls(np.asarray(poly.exterior.coords), aisle, eaves, CATHEDRAL, 1)
    # The roofs: the nave's and the transept's gables, the apse's half cone.
    _gable(m, (-35.0, yc), (49.6, yc), 8.0, eaves, ridge, SLATE, CATHEDRAL, ends=(False, False))
    _gable(m, (-5.65, -22.2), (-5.65, 23.8), 8.15, eaves, ridge, SLATE, CATHEDRAL)
    n = (8, 6, 4)[d]
    t = np.linspace(np.pi / 2, 3 * np.pi / 2, n + 1)
    rim = np.column_stack([-35.0 + 8.0 * np.cos(t), yc + 8.0 * np.sin(t), np.full(n + 1, eaves)])
    apex = np.array([-35.0, yc, ridge])
    for k in range(n):
        tri = np.array([apex, rim[k], rim[k + 1]])
        normal = np.cross(tri[1] - tri[0], tri[2] - tri[0])
        if normal[2] < 0:
            tri, normal = tri[[0, 2, 1]], -normal
        m.add(tri[None], tri[None, :, :2], SLATE, 0.0, normal / np.linalg.norm(normal), flags=ROOF)
    if d < 2:
        _st_patricks_front(m, d, front)
    else:
        # Far away: the central wall and gable, the towers, lanterns and spires.
        m.prism(rect(49.6, -7.4, front, 8.0), -1.0, 34.0, CATHEDRAL, variant=2, roof=SLATE)
        m.tri_plate((51.1, -7.4, 34.0), (51.1, 8.0, 34.0), (51.1, yc, 47.5), 2.4, CATHEDRAL, variant=2)
        for tw in towers:
            tx, ty = tw.centroid.x, tw.centroid.y
            m.prism(tw, -1.0, 41.5, CATHEDRAL, variant=3, roof=PAVING)
            tower(m, tx, ty, [(41.5, 4.75), (57.6, 4.75)], 8, CATHEDRAL, close_top=False, smooth=False, variant=3,
                  start=np.pi / 8)
            tower(m, tx, ty, [(57.6, 5.1), (59.0, 5.1), (59.0, 4.7)], 8, CATHEDRAL, close_top=False, smooth=False,
                  variant=3, start=np.pi / 8)
            _openwork_spire(m, tx, ty, 59.0, 100.4, 4.7, 0.15, d)
    # Pinnacles on the buttresses along the aisles and on the transepts' corners.
    if d == 0:
        for x in np.arange(-31.0, 42.0, 7.2):
            if -15.5 < x < 4.0:
                continue
            for y in (yc - 21.0, yc + 21.0):
                if shapely.contains_xy(plan, x, y + (0.8 if y < yc else -0.8)):
                    _pinnacle(m, x, y, aisle - 0.5, aisle + 5.0, 0.42)
        for x in (-13.8, 2.5):
            for y in (-22.2, 23.8):
                _pinnacle(m, x, y, eaves - 1.0, eaves + 8.0, 0.57)


def _gable(m, a, b, half, eaves, ridge, roof, wall, ends=(True, True), wall_variant=1):
    """A gable roof whose ridge runs from a to b (local x/y) over a strip
    `half` wide either side, eaves to ridge, and with `ends` the triangular
    gable walls at a and b. The roof's uv = (m along the eaves, m up the slope)."""
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    length = float(np.linalg.norm(b - a))
    along = (b - a) / length
    left = np.array([-along[1], along[0]])
    slope = math.hypot(half, ridge - eaves)
    uv = np.array([[[0.0, 0.0], [length, 0.0], [length, slope], [0.0, slope]]])
    # The right slope (seen along a -> b) and the left one, counter-clockwise from above.
    right = np.array([[*(a - left * half), eaves], [*(b - left * half), eaves], [*b, ridge], [*a, ridge]])
    left_side = np.array([[*(b + left * half), eaves], [*(a + left * half), eaves], [*a, ridge], [*b, ridge]])
    _quads(m, right[None], uv, roof, 0.0, flags=ROOF)
    _quads(m, left_side[None], uv, roof, 0.0, flags=ROOF)
    width = 2 * half
    for end, (point, out) in enumerate(((a, -along), (b, along))):
        if not ends[end]:
            continue
        p0, p1 = point + np.array([out[1], -out[0]]) * half, point - np.array([out[1], -out[0]]) * half
        tri = np.array([[*p0, eaves], [*p1, eaves], [*point, ridge]])
        normal = np.array([out[0], out[1], 0.0])
        if np.cross(tri[1] - tri[0], tri[2] - tri[0]) @ normal < 0:
            tri = tri[[1, 0, 2]]
        uv_tri = np.array([[0.0, eaves], [width, eaves], [half, ridge]])
        m.add(tri[None], uv_tri[None], wall, round(width * 10) * 4 + wall_variant, normal)


def _sides(m, corners, z0, z1, material_of):
    """Walls around a counter-clockwise polygon's corners, each side its own
    (material, variant) from material_of(outward (2,))."""
    corners = np.asarray(corners, np.float64)
    for k in range(len(corners)):
        a, b = corners[k], corners[(k + 1) % len(corners)]
        out = np.array([(b - a)[1], -(b - a)[0]]) / np.linalg.norm(b - a)
        kind, variant = material_of(out)
        m.walls([a, b], z0, z1, kind, variant, closed=False)


def _un_secretariat(m: Model, ctx: Context) -> None:
    """United Nations Secretariat (Wallace Harrison's board of architects with
    Le Corbusier and Oscar Niemeyer, 1952): a slab 22 x 87 m (72 x 287 ft),
    154 m (505 ft) to the roof, 39 floors; its long east and west faces
    blue-green glass curtain walls, its narrow ends unbroken Vermont marble,
    the mechanical floors (6, 16, 28 and 39) behind grilles. Wikipedia,
    "United Nations Secretariat Building". Local x runs west to First Avenue,
    y south."""
    top = 154.0
    corners = [(-10.5, -43.2), (10.5, -43.2), (10.5, 43.2), (-10.5, 43.2)]
    _sides(m, corners, -1.0, top, lambda out: (UN_GLASS, 0) if abs(out[0]) > 0.5 else (UN_MARBLE, 0))
    m.cap(Polygon(corners), top, PAVING)
    if m.detail < 2:
        m.prism(rect(-4.3, -25.2, 7.8, 9.8), top, top + 3.5, PLAIN_STONE)


def _un_general_assembly(m: Model, ctx: Context) -> None:
    """United Nations General Assembly Building (1952): 116 x 49 m (380 x
    160 ft) of white stone, its long sides curving in, its roof sweeping down
    from the north end (the visitors' entrance, glass between marble piers)
    and up again to the south front's great window, the shallow dome over the
    hall; the Conference Building along the river and the links between them
    as the city's 3-D model has them. Wikipedia, "United Nations General
    Assembly Building"; the dome's place from the city's aerial photos. The
    hall's outline is the 3-D model's highest part."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []
    if not terraces:
        m.prism(_local_footprint(ctx), -1.0, 21.6, UN_MARBLE, variant=2)
        return
    hall = max(polygons_of(terraces[-1][1], 1.0), key=lambda p: p.area)
    rest = [(level, shapely.difference(outline, shapely.buffer(hall, 0.3, join_style="mitre")))
            for level, outline in terraces[:-1]]
    rest = [(level, outline) for level, outline in rest if not outline.is_empty]
    add_terraces(m, rest, lambda lo, hi: (UN_MARBLE, 2))
    # The hall: its axis, north end up.
    corners = np.asarray(shapely.oriented_envelope(hall).exterior.coords)[:4]
    edges = [corners[1] - corners[0], corners[2] - corners[1]]
    axis = max(edges, key=lambda e: np.linalg.norm(e))
    half = float(np.linalg.norm(axis)) / 2
    axis = axis / np.linalg.norm(axis)
    center = corners.mean(axis=0)
    north = ctx.frame.to_world(np.array([center + axis * half, center - axis * half]))
    if north[1, 1] > north[0, 1]:
        axis = -axis
    across = np.array([-axis[1], axis[0]])

    def roof(xy):
        t = np.clip(((np.asarray(xy) - center) @ axis) / half, -1.0, 1.0)
        return 29.0 + np.where(t > 0, 38.3 - 29.0, 34.0 - 29.0) * t * t
    ring = shapely.segmentize(shapely.orient_polygons(hall).exterior, 6.0 if d < 2 else 15.0)
    points = np.asarray(ring.coords)[:-1, :2]
    m.walls(points, -1.0, roof(points), UN_MARBLE,
            lambda middle, out: 1 if abs(out @ axis) > 0.6 else 0)
    step = 6.0 if d < 2 else 20.0
    for t0 in np.arange(-half - 1.0, half + 1.0, step):
        strip = Polygon([center + axis * t0 + across * 40.0, center + axis * (t0 + step) + across * 40.0,
                         center + axis * (t0 + step) - across * 40.0, center + axis * t0 - across * 40.0])
        for piece in polygons_of(shapely.intersection(hall, strip), 0.05):
            tris = triangles_of(piece)
            if tris is None:
                continue
            z = roof(tris.reshape(-1, 2)).reshape(tris.shape[:2])
            pos = np.concatenate([tris, z[..., None]], axis=-1)
            normal = np.cross(pos[:, 1] - pos[:, 0], pos[:, 2] - pos[:, 0])
            normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-9)
            flip = normal[:, 2] < 0
            pos[flip] = pos[flip][:, [0, 2, 1]]
            normal[flip] = -normal[flip]
            m.add(pos, pos[..., :2], PAVING, 0.0, normal, flags=ROOF)
    # The dome.
    dome = ctx.frame.to_local(np.array([[1497.5, -872.5]]))[0]
    z = float(roof(dome[None])[0]) - 0.4
    tower(m, dome[0], dome[1], [(z, 13.0), (z + 1.4, 13.0), (z + 2.8, 10.6), (z + 4.0, 6.4), (z + 4.6, 0.3)],
          segments(d, 2.0), UN_MARBLE)


def _citigroup(m: Model, ctx: Context) -> None:
    """Citigroup Center (601 Lexington Avenue; Hugh Stubbins, 1977): a 48 m
    (157 ft) square tower of aluminum and glass bands raised on four 34.7 m
    (114 ft) stilts at the middle of its sides around a central core, its
    top sloping 45 degrees down to the south, from 283.7 m to 246.4 m (the
    city's 3-D model; 279 m to the roof officially); the base buildings and
    St. Peter's Church north of the tower from the 3-D model. Wikipedia,
    "Citigroup Center". Local x runs west to Lexington Avenue, y south."""
    d = m.detail
    x0, x1, y0, y1 = -3.2, 44.8, -15.0, 33.0
    lift, high, low, slope_hi, slope_lo = 34.7, 283.7, 246.4, -11.3, 26.0
    square = rect(x0, y0, x1, y1)
    church = rect(18.0, -27.5, 45.0, -14.0)
    if ctx.shape:
        terraces = [(level, _clean(shapely.difference(outline, square), d))
                    for level, outline in model_terraces(ctx.shape, ctx.frame, 39.0, d)]
        terraces = [(level, outline) for level, outline in terraces if not outline.is_empty]
        add_terraces(m, terraces, lambda lo, hi: (
            CITIGROUP, lambda middle, out: 3 if shapely.contains_xy(church, middle[0], middle[1]) else 0))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    w = 3.65
    for stilt in (rect(cx - w, y0, cx + w, y0 + 2 * w), rect(cx - w, y1 - 2 * w, cx + w, y1),
                  rect(x0, cy - w, x0 + 2 * w, cy + w), rect(x1 - 2 * w, cy - w, x1, cy + w)):
        m.prism(stilt, -1.0, lift, CITIGROUP, variant=2, roof=None)
    m.prism(chamfered(cx, cy, 9.5, 11.0, 3.0), -1.0, lift, CITIGROUP, variant=2, roof=None)
    m.cap(square, lift, CITIGROUP, variant=2, flags=0, down=True)
    # The tower: the north face to the top, the south face to the slope's foot.
    m.walls([(x0, y0), (x1, y0)], lift, high, CITIGROUP, closed=False)
    m.walls([(x1, y1), (x0, y1)], lift, low, CITIGROUP, closed=False)
    m.walls([(x1, y0), (x1, slope_hi), (x1, slope_lo), (x1, y1)], lift, [high, high, low, low], CITIGROUP,
            closed=False)
    m.walls([(x0, y1), (x0, slope_lo), (x0, slope_hi), (x0, y0)], lift, [low, low, high, high], CITIGROUP,
            closed=False)
    m.cap(rect(x0, y0, x1, slope_hi), high, PAVING)
    m.cap(rect(x0, slope_lo, x1, y1), low, PAVING)
    slope = np.array([[x1, slope_lo, low], [x0, slope_lo, low], [x0, slope_hi, high], [x1, slope_hi, high]])
    width = x1 - x0
    _quads(m, slope[None], np.array([[[0.0, low], [width, low], [width, high], [0.0, high]]]), CITIGROUP,
           round(width * 10) * 4 + 1)


def _hearst(m: Model, ctx: Context) -> None:
    """Hearst Tower (Foster + Partners, 2006) on the Hearst Magazine Building
    (Joseph Urban, 1928): the six-story cast-stone base (21 m) with its
    pylons and urns, kept as a shell; over a glass clerestory the tower, 49 x
    37 m (160 x 120 ft), its diagrid of triangles four floors (16.4 m) tall
    from the 10th floor (34 m) to the roof at 182 m, the corners cut back
    into "bird's mouths" every eight floors (deepest at the 14th, 22nd, 30th
    and 38th). Wikipedia, "Hearst Tower (Manhattan)"; the tower's place from
    the city's 3-D model. Local x runs west, y south."""
    d = m.detail
    m.prism(shapely.simplify(_local_footprint(ctx), TOLERANCE[d]), -1.0, 21.0, HEARST_BASE, roof=PAVING)
    tx, ty, hx, hy = 2.45, 0.85, 25.05, 19.05
    m.prism(rect(tx - hx + 1.2, ty - hy + 1.2, tx + hx - 1.2, ty + hy - 1.2), 21.0, 34.0, HEARST_BASE, variant=1,
            roof=None)
    tier = 16.4
    levels = [34.0 + tier * k for k in range(9)] + [182.0]
    cuts = [0.3 if k % 2 == 0 else 4.6 for k in range(len(levels))]
    if d == 2:
        levels, cuts = [34.0, 182.0], [2.0, 2.0]
    x0, x1, y0, y1 = tx - hx, tx + hx, ty - hy, ty + hy

    def ring(c, z):
        return np.array([(x0 + c, y0, z), (x1 - c, y0, z), (x1, y0 + c, z), (x1, y1 - c, z), (x1 - c, y1, z),
                         (x0 + c, y1, z), (x0, y1 - c, z), (x0, y0 + c, z)])
    # Main faces' u: m from the face's middle; their width the face's full width.
    faces = {0: (lambda p: p[0] - tx, 2 * hx), 2: (lambda p: p[1] - ty, 2 * hy),
             4: (lambda p: tx - p[0], 2 * hx), 6: (lambda p: ty - p[1], 2 * hy)}
    for k in range(len(levels) - 1):
        lower, upper = ring(cuts[k], levels[k]), ring(cuts[k + 1], levels[k + 1])
        for side in range(8):
            a, b = side, (side + 1) % 8
            quad = np.array([lower[a], lower[b], upper[b], upper[a]])
            if side in faces:
                u, width = faces[side]
                uv = np.array([[u(p), p[2]] for p in quad])
                param = round(width * 10) * 4
            else:
                length = np.linalg.norm(quad[1, :2] - quad[0, :2])
                uv = np.array([[0.0, quad[0, 2]], [length, quad[1, 2]], [np.linalg.norm(quad[2, :2] - quad[3, :2]),
                                                                       quad[2, 2]], [0.0, quad[3, 2]]])
                param = 4 * 46 + 1
            _quads(m, quad[None], uv[None], HEARST, param)
    m.cap(Polygon(ring(cuts[-1], 0.0)[:, :2]), levels[-1], PAVING)
    if d < 2:
        m.prism(rect(tx - 15.0, ty - 9.0, tx + 15.0, ty + 9.0), levels[-1], levels[-1] + 5.0, PLAIN_STONE)
    if d == 0:
        # The pylons with their sculpture groups, crowned by urns.
        for px, py, ox, oy in ((-29.9, -10.0, -1, 0), (-29.9, 10.0, -1, 0), (-10.0, -30.0, 0, -1),
                               (10.0, -30.0, 0, -1), (-10.0, 30.6, 0, 1), (10.0, 30.6, 0, 1)):
            cxp, cyp = px + ox * 0.4, py + oy * 0.4
            size = (2.8 if ox == 0 else 0.8, 0.8 if ox == 0 else 2.8, 15.0)
            m.box((cxp, cyp, 14.5), size, HEARST_BASE)
            tower(m, cxp, cyp, [(22.0, 0.45), (22.6, 0.9), (24.0, 1.0), (24.6, 0.35)], 6, HEARST_BASE)


def _met(m: Model, ctx: Context) -> None:
    """The Metropolitan Museum of Art: the massing (Hunt's central pavilion
    and McKim, Mead & White's wings on Fifth Avenue, the later wings into the
    park, the skylit galleries) from the city's 3-D model; on Fifth Avenue,
    Richard Morris Hunt's facade (1902): three great arched entrances between
    four pairs of Corinthian columns, each pair crowned by a block of
    uncarved stone meant for sculpture, and the grand steps. Wikipedia,
    "Metropolitan Museum of Art". Local x runs west into the park, y south;
    the central facade faces Fifth Avenue at x = -72 from y = -31.5 to 33.5."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []

    def face(middle, out):
        if out[0] < -0.9:
            return 1 if -31.5 < middle[1] < 33.5 and middle[0] < -70.0 else 0
        return 2
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (MET, face if lo < 28.0 else 2),
                     roof=lambda level: SKYLIGHT if level > 30.0 else PAVING)
    else:
        m.prism(_local_footprint(ctx), -1.0, 26.8, MET, variant=face)
    front = float(ctx.ground(np.array([[-90.0, 1.0]]))[0])
    floor = front + 3.2
    steps = (6, 2, 1)[d]
    for k in range(steps):
        x = -72.0 - 16.0 * (steps - k) / steps
        m.prism(rect(x, 1.0 - 34.0, -72.0, 1.0 + 34.0), -1.0, front + 3.2 * (k + 1) / steps, PLAIN_STONE)
    if d == 2:
        return
    n = segments(d, 0.6, 6)
    for pair in (-24.5, -8.5, 10.5, 26.5):
        for y in (pair - 1.1, pair + 1.1):
            tower(m, -73.8, y, [(floor, 1.05), (floor + 1.2, 1.05), (floor + 1.2, 0.85), (floor + 15.5, 0.75),
                                (floor + 16.8, 1.0)], n, MET, variant=2)
        m.box((-73.6, pair, floor + 18.0), (2.8, 4.8, 2.4), MET, variant=2)       # the entablature
        m.box((-73.4, pair, floor + 21.0), (2.6, 3.8, 3.6), MET, variant=2)       # the uncarved block


def _surface_of_revolution(m, cx, cy, profile, n, material, variant, u_scale, inward=False, z_sink=0.0):
    """Quads around (cx, cy) through profile [(z, r), ...] bottom up, n
    sides, uv = (turns * u_scale, z), smooth normals; facing out, or in."""
    profile = np.asarray(profile, np.float64)
    t = np.linspace(0.0, 2 * np.pi, n + 1)
    c, s = np.cos(t), np.sin(t)
    z, r = profile[:, 0], profile[:, 1]
    slope = np.gradient(r, z) if len(z) > 1 else np.zeros_like(z)
    quads, uvs, normals = [], [], []
    for i in range(len(profile) - 1):
        for k in range(n):
            corners = []
            corner_normals = []
            for kk, ii in ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1)):
                corners.append((cx + r[ii] * c[kk], cy + r[ii] * s[kk], z[ii] - (z_sink if ii == 0 else 0.0)))
                nrm = np.array([c[kk], s[kk], -slope[ii]])
                corner_normals.append(nrm / np.linalg.norm(nrm))
            uv = [(t[kk] / (2 * np.pi) * u_scale, z[ii]) for kk, ii in ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1))]
            if inward:
                corners, uv, corner_normals = corners[::-1], uv[::-1], [-v for v in corner_normals[::-1]]
            quads.append(corners)
            uvs.append(uv)
            normals.append(corner_normals)
    _quads(m, np.array(quads), np.array(uvs), material, variant, normals=np.array(normals))


def _vessel(m: Model, ctx: Context) -> None:
    """Vessel (Thomas Heatherwick, 2019), Hudson Yards: 154 interlocking
    flights of stairs (2,500 steps, 80 landings) in 16 levels, a bowl 15 m
    (50 ft) across at the bottom opening out to 46 m (150 ft) at the top,
    46 m tall, its stairs clad in copper-colored steel. Wikipedia, "Vessel
    (structure)"; its place from the footprint data's circle. Local x runs
    east."""
    d = m.detail
    bowl = shapely.minimum_bounding_circle(_local_footprint(ctx))
    cx, cy = bowl.centroid.x, bowl.centroid.y
    height, cells = 46.0, 16.0
    rows, n = (8, 4, 2)[d], (28, 14, 8)[d]
    z = np.linspace(0.0, height, rows + 1)
    outer = 7.6 + 15.3 * (z / height) ** 1.15
    _surface_of_revolution(m, cx, cy, np.column_stack([z, outer]), n, VESSEL, 0, cells, z_sink=1.0)
    if d < 2:
        _surface_of_revolution(m, cx, cy, np.column_stack([z, outer - 0.9]), n, VESSEL, 1, cells, inward=True)
        rim = shapely.difference(Polygon(circle(cx, cy, outer[-1], n)[:, :2]),
                                 Polygon(circle(cx, cy, outer[-1] - 0.9, n)[:, :2]))
        m.cap(rim, height, VESSEL)


def _oculus(m: Model, ctx: Context) -> None:
    """The Oculus (Santiago Calatrava, 2016), the World Trade Center
    Transportation Hub's head house: an elliptical hall 107 x 35 m (350 x
    115 ft), glass between white steel ribs that rise from its edge, meet
    over the 100 m (330 ft) skylight at about 29 m (96 ft) and cross, going
    on up as wings to 51 m (168 ft). Architectural Record; Arch2o; the
    footprint data's ellipse. Local x runs along the hall, y across it."""
    d = m.detail
    hall = _local_footprint(ctx)
    x0, y0, x1, y1 = hall.bounds
    cx, cy, a, b = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    n = (28, 16, 10)[d]
    t = np.arange(n) * (2 * np.pi / n)
    rings = [np.column_stack([cx + a * sa * np.cos(t), cy + b * sb * np.sin(t), np.full(n, z)])
             for sa, sb, z in ((1.0, 1.0, -1.0), (0.99, 0.88, 9.0), (0.96, 0.66, 18.0), (0.92, 0.38, 24.5),
                               (0.88, 0.07, 28.8))]
    m.loft(rings, SKYLIGHT, close_top=True)
    # The ribs, each from its foot on one side over the skylight to a wing tip
    # on the other; tallest in the middle, splaying toward the ends.
    count = (12, 6, 4)[d]
    for side in (-1.0, 1.0):
        for i in range(count):
            u = -1.0 + 2.0 * (i + 0.5 + (0.25 if side > 0 else -0.25)) / count
            x = cx + u * a * 0.9
            foot = b * math.sqrt(max(1.0 - (u * 0.9) ** 2, 0.0))
            f = 1.0 - 0.5 * u * u
            points = [(x, cy + side * foot, -0.5), (x + u * 1.0, cy + side * 0.82 * foot, 14.0),
                      (x + u * 2.0, cy + side * 1.0, 28.6), (x + u * 5.0 * f, cy - side * 9.0 * f, 28.6 + 11.0 * f),
                      (x + u * 9.0 * f, cy - side * (21.0 * f + 3.0), 28.6 + 22.0 * f)]
            if d > 0:
                points = [points[0], points[2], points[4]]
            widths = [1.4, 1.2, 1.0, 0.7]
            for k in range(len(points) - 1):
                _beam(m, points[k], points[k + 1], widths[min(k, 3)], 0.7, WHITE_STEEL, normal=(1.0, 0.0, 0.0))


YANKEE_HOME = (4938.5, 7940.6)   # home plate (east/north), from the city's aerial photos
YANKEE_AXIS = 14.0               # degrees from east: home plate toward center field


def _yankee_stadium(m: Model, ctx: Context) -> None:
    """Yankee Stadium (Populous, 2009): the stands and concourses as the
    city's 3-D model has them (the upper deck to 41 m), the limestone outer
    wall with its tall arched openings and YANKEE STADIUM in gold over the
    entrance behind home plate, the white frieze along the roof over the
    upper deck, the field (home plate and the line to center field from the
    city's aerial photos) and the video board in center field (31 x 18 m).
    Wikipedia, "Yankee Stadium"."""
    d = m.detail
    home = ctx.frame.to_local(np.array([YANKEE_HOME]))[0]
    a = math.radians(YANKEE_AXIS) - ctx.frame.angle
    axis = np.array([math.cos(a), math.sin(a)])
    left = np.array([-axis[1], axis[0]])
    plan = _local_footprint(ctx)
    outline = Polygon(plan.exterior)
    # The field: the footprint's hole.
    holes = [Polygon(ctx.frame.to_local(np.asarray(h.coords)[:, :2]))
             for poly in polygons_of(ctx.footprint, 1.0) for h in poly.interiors]
    holes = [h for h in holes if h.area > 5000.0]
    field = max(holes, key=lambda h: h.area) if holes else None
    center = np.asarray(field.centroid.coords)[0] if field is not None else home + axis * 60.0
    edge = outline.exterior
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []
    # The name goes on each tier's outer face nearest the gate behind home plate.
    gate = shapely.Point(home - axis * 200.0)
    named = []
    for _, tier in terraces:
        for poly in polygons_of(tier, 50.0):
            ring = np.asarray(poly.exterior.coords)[:, :2]
            k = min(range(len(ring) - 1), key=lambda k: shapely.LineString(ring[k:k + 2]).distance(gate))
            named.append((ring[k] + ring[k + 1]) / 2)

    def wall(middle, out):
        if out @ (middle - center) > 0 and edge.distance(shapely.Point(middle)) < 4.0:
            return 1 if any(np.allclose(middle, n, atol=0.01) for n in named) else 0
        return 2
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (STADIUM, wall),
                     roof=lambda level: (PLAYFIELD, 1) if 2.0 < level < 37.0 else PAVING)
        # The frieze, hanging from the roof's edge over the upper deck.
        top_level, top = terraces[-1]
        if d < 2:
            for poly in polygons_of(top, 50.0):
                ring = np.asarray(shapely.orient_polygons(poly).exterior.coords)[:-1, :2]
                for k in range(len(ring)):
                    p, q = ring[k], ring[(k + 1) % len(ring)]
                    length = np.linalg.norm(q - p)
                    if length < 1.0:
                        continue
                    out = np.array([(q - p)[1], -(q - p)[0]]) / length
                    if out @ (center - (p + q) / 2) < 0.3 * np.linalg.norm(center - (p + q) / 2):
                        continue
                    p2, q2 = p + out * 0.8, q + out * 0.8
                    m.walls([p2, q2], top_level - 3.2, top_level, WHITE_STEEL, 1, closed=False)
                    m.walls([q2, p2], top_level - 3.2, top_level, WHITE_STEEL, 1, closed=False)
    else:
        m.prism(plan, -1.0, 36.6, STADIUM)
    if field is not None:
        inside = np.asarray(field.representative_point().coords)
        z = float(np.median(ctx.ground(np.vstack([inside, home[None], (home + axis * 80.0)[None]])))) + 0.05
        tris = triangles_of(shapely.simplify(field, TOLERANCE[d]))
        if tris is not None:
            rel = tris - home
            uv = np.stack([rel @ axis, rel @ left], -1)
            pos = np.concatenate([tris, np.full(tris.shape[:2] + (1,), z)], axis=-1)
            m.add(pos, uv, PLAYFIELD, 0.0, (0.0, 0.0, 1.0), flags=ROOF)
    else:
        z = 1.0
    # The video board beyond center field, facing home plate.
    if d < 2:
        mid = home + axis * 140.0
        corners = [mid - left * 15.5 - axis * 1.0, mid - left * 15.5 + axis * 1.0, mid + left * 15.5 + axis * 1.0,
                   mid + left * 15.5 - axis * 1.0]
        corners = np.asarray(shapely.orient_polygons(Polygon(corners)).exterior.coords)[:-1]
        _sides(m, corners, z + 22.0, z + 40.0, lambda out: (STADIUM, 3) if out @ axis < -0.9 else (STADIUM, 2))
        m.cap(Polygon(corners), z + 40.0, PAVING)
        m.cap(Polygon(corners), z + 22.0, STADIUM, variant=2, flags=0, down=True)


# Natural Earth's 1:110m land (public domain) in 7.5-degree cells at least 30%
# land, north (90 N) to south, west (180 W) to east; Antarctica left out.
UNISPHERE_LAND = (
    "................................................",
    "...........###########...............#..........",
    "..###.#########..####......#...#.#############..",
    "..###########.#..##..#...#######################",
    "......##########.......#.##################..#..",
    ".......##########......####################.....",
    ".......########........###################......",
    "........######.........###..############........",
    ".........##...........##################........",
    "..........###.........##########.######.........",
    "............#.##......#########...#..##.........",
    ".............####......#.#####.......#.#........",
    ".............######......#####........##..#.....",
    ".............######.......####..................",
    "..............#####......####.#.........####....",
    "..............####........###..........######...",
    "..............###.........##...........##.##....",
    "..............##................................",
    "..............#.................................",
    "................................................",
    "................................................",
)
UNISPHERE_SPIN = -15.0   # degrees: 75 W (the Americas) faces south
UNISPHERE_TILT = 23.5    # the axis leans this far toward the south


def _unisphere(m: Model, ctx: Context) -> None:
    """The Unisphere (Gilmore D. Clarke, 1964), Flushing Meadows-Corona Park:
    a stainless steel globe 37 m (120 ft) across, 43 m (140 ft) tall on its
    6 m inverted tripod, its axis tilted 23.5 degrees, the continents plates
    on a lattice of meridians and parallels, three rings around it (the
    orbits of Gagarin, Glenn and Telstar), in a fountain pool 94 m (310 ft)
    across. Wikipedia, "Unisphere"; the continents from Natural Earth's
    1:110m land; its place from the city's aerial photos. Local x runs east,
    y north."""
    d = m.detail
    radius, center = 18.3, np.array([0.0, 0.0, 24.4])
    tilt, spin = math.radians(UNISPHERE_TILT), math.radians(UNISPHERE_SPIN)
    rotate = np.array([[1.0, 0.0, 0.0], [0.0, math.cos(tilt), -math.sin(tilt)],
                       [0.0, math.sin(tilt), math.cos(tilt)]])

    def unit(lon, lat):  # degrees -> unit vectors (..., 3) in the local frame
        lon, lat = np.radians(lon) + spin, np.radians(lat)
        v = np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)], -1)
        return v @ rotate.T
    # The pool, its granite rim, and the tripod.
    n = segments(d, 3.0)
    m.prism(shapely.difference(shapely.Point(0, 0).buffer(48.0, quad_segs=n // 4),
                               shapely.Point(0, 0).buffer(47.0, quad_segs=n // 4)), -0.5, 0.5, PLAIN_STONE,
            roof=PLAIN_STONE)
    m.cap(shapely.Point(0, 0).buffer(47.05, quad_segs=n // 4), 0.15, PLAYFIELD, variant=2)
    for k in range(3):
        a = math.radians(90.0 + 120.0 * k)
        top = center + np.array([9.0 * math.cos(a), 9.0 * math.sin(a), -radius * 0.86])
        _beam(m, (0.0, 0.0, -0.5), top, 1.8, 1.8, UNISPHERE, sides=3)
    tower(m, 0.0, 0.0, [(-0.5, 2.0), (center[2] - radius + 1.0, 1.4)], 6, UNISPHERE)
    if d == 0:
        # The lattice: meridians and parallels standing out from the globe.
        quads = []
        lats = np.arange(-90.0, 90.1, 15.0)
        for lon in np.arange(0.0, 360.0, 20.0):
            v = unit(np.full(len(lats), lon), lats)
            outer, inner = center + v * (radius + 0.1), center + v * (radius - 0.7)
            for i in range(len(lats) - 1):
                quads.append([outer[i], outer[i + 1], inner[i + 1], inner[i]])
        lons = np.arange(0.0, 360.1, 15.0)
        for lat in (-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0):
            v = unit(lons, np.full(len(lons), lat))
            outer, inner = center + v * (radius + 0.1), center + v * (radius - 0.7)
            for i in range(len(lons) - 1):
                quads.append([outer[i], outer[i + 1], inner[i + 1], inner[i]])
        quads = np.array(quads)
        uv = np.zeros(quads.shape[:2] + (2,))
        uv[:, [1, 2], 0] = 1.0
        uv[:, [2, 3], 1] = 0.8
        _quads(m, quads, uv, UNISPHERE, 0.0)
        _quads(m, quads[:, ::-1], uv[:, ::-1], UNISPHERE, 0.0)
        # The continents: plates over the land cells, two cells at most each.
        plates, plate_uv = [], []
        for row, line in enumerate(UNISPHERE_LAND):
            lat1 = 90.0 - row * 7.5
            col = 0
            while col < len(line):
                if line[col] != "#":
                    col += 1
                    continue
                span = 2 if col + 1 < len(line) and line[col + 1] == "#" else 1
                lon0, lon1 = -180.0 + col * 7.5, -180.0 + (col + span) * 7.5
                corners = [(lon0, lat1 - 7.5), (lon1, lat1 - 7.5), (lon1, lat1), (lon0, lat1)]
                v = unit(np.array([c[0] for c in corners]), np.array([c[1] for c in corners]))
                plates.append(center + v * (radius + 0.05))
                plate_uv.append(corners)
                col += span
        plates, plate_uv = np.array(plates), np.array(plate_uv, np.float64)
        normals = (plates - center) / radius
        _quads(m, plates, plate_uv, UNISPHERE, 2.0, normals=normals)
        _quads(m, plates[:, ::-1], plate_uv[:, ::-1], UNISPHERE, 2.0, normals=-normals[:, ::-1])
    else:
        # Further away, a whole globe with the continents painted on.
        lats = np.linspace(-90.0, 90.0, (9, 7)[d - 1])
        lons = np.linspace(-180.0, 180.0, (19, 13)[d - 1])
        quads, uvs = [], []
        for i in range(len(lats) - 1):
            for k in range(len(lons) - 1):
                corners = [(lons[k], lats[i]), (lons[k + 1], lats[i]), (lons[k + 1], lats[i + 1]), (lons[k], lats[i + 1])]
                v = unit(np.array([c[0] for c in corners]), np.array([c[1] for c in corners]))
                quads.append(center + v * radius)
                uvs.append(corners)
        quads = np.array(quads)
        _quads(m, quads, np.array(uvs, np.float64), UNISPHERE, 1.0, normals=(quads - center) / radius)
    # The three orbits.
    if d < 2:
        count = (32, 16)[d]
        for ring_radius, tilt_x, tilt_y in ((21.6, 32.0, 10.0), (22.9, -48.0, 25.0), (24.2, 12.0, -62.0)):
            t = np.linspace(0.0, 2 * np.pi, count + 1)
            ring = np.column_stack([np.cos(t), np.sin(t), np.zeros_like(t)]) * ring_radius
            ax, ay = math.radians(tilt_x), math.radians(tilt_y)
            rx = np.array([[1, 0, 0], [0, math.cos(ax), -math.sin(ax)], [0, math.sin(ax), math.cos(ax)]])
            ry = np.array([[math.cos(ay), 0, math.sin(ay)], [0, 1, 0], [-math.sin(ay), 0, math.cos(ay)]])
            ring = ring @ (ry @ rx).T + center
            for k in range(count):
                _beam(m, ring[k], ring[k + 1], 0.55, 0.55, UNISPHERE, sides=3)


def _box_faces(m, center, size, material, variant, u0=0.0, yaw=0.0):
    """An upright box whose faces' uv.x starts at u0 (so the shader can tell
    boxes apart), uv.y = m above its bottom; top and bottom closed."""
    cx, cy, cz = center
    sx, sy, sz = size
    corners = np.array([[-sx, -sy], [sx, -sy], [sx, sy], [-sx, sy]]) * 0.5
    c, s = math.cos(yaw), math.sin(yaw)
    corners = corners @ np.array([[c, s], [-s, c]]) + [cx, cy]
    z0, z1 = cz - sz / 2, cz + sz / 2
    quads, uvs, params = [], [], []
    for k in range(4):
        a, b = corners[k], corners[(k + 1) % 4]
        width = float(np.linalg.norm(b - a))
        quads.append([(*a, z0), (*b, z0), (*b, z1), (*a, z1)])
        uvs.append([(u0, 0.0), (u0 + width, 0.0), (u0 + width, sz), (u0, sz)])
        params.append(round(width * 10) * 4 + variant)
    top = [(*corners[0], z1), (*corners[1], z1), (*corners[2], z1), (*corners[3], z1)]
    under = [(*corners[3], z0), (*corners[2], z0), (*corners[1], z0), (*corners[0], z0)]
    for face in (top, under):
        quads.append(face)
        uvs.append([(u0, 0.0), (u0 + sx, 0.0), (u0 + sx, sy), (u0, sy)])
        params.append(round(sx * 10) * 4 + variant)
    _quads(m, np.array(quads), np.array(uvs), material, np.array(params, np.float64))


def _wonder_wheel(m: Model, ctx: Context) -> None:
    """Deno's Wonder Wheel (Charles Herman, Eccentric Ferris Wheel Company,
    1920), Coney Island: 46 m (150 ft) tall and 43 m (140 ft) across, 16
    spokes to a sixteen-sided rim, the hub on two blue A-frames; 24 cars, 8
    white ones fixed to the rim and 16 that swing out along curved tracks;
    "WONDER WHEEL" in lights at the hub. Wikipedia, "Wonder Wheel"; the
    diameter from Deno's; its place and its plane (east-west) from the city's
    aerial photos. Local x runs east in the wheel's plane, y north; the
    station it replaces is south of the hub."""
    d = m.detail
    hub, rim, inner = 24.4, 21.3, 12.8
    wheel = (0.0, 1.0, 0.0)  # members' depth runs across the wheel
    # The station under the wheel, open where the wheel turns through it.
    station = shapely.difference(_local_footprint(ctx), rect(-30.0, -2.4, 30.0, 2.4))
    m.prism(station, -1.0, 2.8, PLAIN_STONE)
    # The A-frames and the hub.
    for y in (-1.0, 1.0):
        feet = [np.array([-12.5, y * 5.5, -0.5]), np.array([12.5, y * 5.5, -0.5])]
        top = np.array([0.0, y * 2.6, hub])
        for foot in feet:
            _beam(m, foot, top, 1.0, 1.0, RIDE, 1)
        if d < 2:
            f = 9.0 / hub
            _beam(m, feet[0] + (top - feet[0]) * f, feet[1] + (top - feet[1]) * f, 0.6, 0.6, RIDE, 1)
    _beam(m, (0.0, -3.2, hub), (0.0, 3.2, hub), 2.2, 2.2, RIDE, 0)
    count = 16 if d < 2 else 8
    angles = np.radians(11.25) + np.arange(count) * (2 * np.pi / count)
    points = np.column_stack([np.cos(angles), np.zeros(count), np.sin(angles)])
    ring = points * rim + [0.0, 0.0, hub]
    for k in range(count):
        _beam(m, ring[k], ring[(k + 1) % count], 0.6, 2.6, RIDE, 0, normal=wheel)
        if d < 2 or k % 2 == 0:
            _beam(m, (0.0, 0.0, hub), ring[k], 0.5, 1.8, RIDE, 0, normal=wheel)
    if d == 2:
        return
    inside = points * inner + [0.0, 0.0, hub]
    for k in range(count):
        _beam(m, inside[k], inside[(k + 1) % count], 0.45, 2.2, RIDE, 0, normal=wheel)
    if d == 0:
        # The swinging cars' curved tracks, from the inner ring out to the rim.
        for k in range(count):
            a0, a1 = angles[k], angles[k] + np.radians(22.5)
            bend = angles[k] + np.radians(16.0)
            p0 = np.array([math.cos(a0), 0.0, math.sin(a0)]) * inner
            p1 = np.array([math.cos(bend), 0.0, math.sin(bend)]) * (inner + rim) * 0.5
            p2 = np.array([math.cos(a1), 0.0, math.sin(a1)]) * rim
            for p, q in ((p0, p1), (p1, p2)):
                _beam(m, p + [0.0, 0.0, hub], q + [0.0, 0.0, hub], 0.3, 2.0, RIDE, 0, normal=wheel)
    # The cars: 8 white ones fixed to the rim, 16 swinging between them.
    for k in range(24):
        fixed = k % 3 == 0
        a = np.radians(11.25 + 15.0 * k)
        r = rim if fixed else rim - 4.0
        x, z = r * math.cos(a), hub + r * math.sin(a) - 1.7
        kind = 0 if fixed else (1 if k % 3 == 1 else 2)
        _box_faces(m, (x, 0.0, z), (2.2, 2.4, 2.4), RIDE, 3, u0=10.0 * kind)
    # The sign at the hub, on both faces.
    for y in (-1.0, 1.0):
        _box_faces(m, (0.0, y * 1.75, hub - 3.4), (12.0, 0.3, 2.0), RIDE, 3, u0=30.0)


def _parachute_jump(m: Model, ctx: Context) -> None:
    """The Parachute Jump (1939 New York World's Fair; at Coney Island since
    1941): an open steel tower 76 m (250 ft) tall, six legs on a hexagonal
    base braced by rings and diagonals, twelve arms radiating 14 m (45 ft)
    from its top joined by a ring, painted red, and lit by 8,000 LEDs (2013);
    the two-story six-sided pavilion at its foot is the footprint data's.
    Wikipedia, "Parachute Jump". Local x runs along a side of the hexagon."""
    d = m.detail
    pavilion = _local_footprint(ctx)
    m.prism(shapely.simplify(pavilion, TOLERANCE[d]), -1.0, 7.0, PLAIN_STONE)
    hexagon = np.asarray(shapely.simplify(pavilion, 1.0).exterior.coords)[:-1]
    start = math.atan2(hexagon[0][1], hexagon[0][0]) if len(hexagon) else 0.0
    legs = start + np.arange(6) * (np.pi / 3)
    profile = [(0.0, 7.6), (7.0, 6.8), (15.0, 5.9), (23.0, 5.2), (31.0, 4.7), (39.0, 4.3), (47.0, 4.0),
               (55.0, 3.7), (62.0, 3.4)]
    if d == 2:
        tower(m, 0.0, 0.0, [(-1.0, 7.6), (23.0, 5.2), (62.0, 3.4), (63.0, 3.4)], 6, RIDE, variant=2, start=start)
        tower(m, 0.0, 0.0, [(63.0, 14.0), (64.4, 14.0)], 12, RIDE, variant=2)
        tower(m, 0.0, 0.0, [(64.4, 3.0), (76.0, 0.1)], 6, RIDE, variant=2, start=start)
        return
    if d == 1:
        profile = [profile[k] for k in (0, 1, 3, 5, 8)]
    z = np.array([p[0] for p in profile])
    r = np.array([p[1] for p in profile])
    corners = np.stack([np.stack([r * math.cos(a), r * math.sin(a), z], -1) for a in legs])  # (6, levels, 3)
    for k in range(6):
        nxt = (k + 1) % 6
        for i in range(len(z) - 1):
            _beam(m, corners[k, i] - [0.0, 0.0, 0.5 if i == 0 else 0.0], corners[k, i + 1], 0.7, 0.7, RIDE, 2, sides=3)
            if i + 1 < len(z):
                _beam(m, corners[k, i + 1], corners[nxt, i + 1], 0.4, 0.4, RIDE, 2, sides=3)
            if d == 0:
                a, b = (corners[k, i], corners[nxt, i + 1]) if (i + k) % 2 == 0 else (corners[nxt, i], corners[k, i + 1])
                _beam(m, a, b, 0.3, 0.3, RIDE, 2, sides=3)
    # The top: a platform, the twelve arms and their ring, and the crown.
    m.prism(Polygon(circle(0.0, 0.0, 3.8, 6, start=start)[:, :2]), 62.0, 63.2, RIDE, roof=PAVING, variant=2)
    arms = np.arange(12) * (np.pi / 6) + start
    tips = np.column_stack([14.0 * np.cos(arms), 14.0 * np.sin(arms), np.full(12, 64.4)])
    for k in range(12):
        root = np.array([3.0 * math.cos(arms[k]), 3.0 * math.sin(arms[k]), 63.0])
        _beam(m, root, tips[k], 0.5, 0.5, RIDE, 2, sides=3)
        _beam(m, tips[k], tips[(k + 1) % 12], 0.4, 0.4, RIDE, 2, sides=3)
        if d == 0:
            _beam(m, tips[k], tips[k] - [0.0, 0.0, 2.2], 0.25, 0.25, RIDE, 2, sides=3)
    for a in legs:
        _beam(m, (3.4 * math.cos(a), 3.4 * math.sin(a), 63.2), (0.0, 0.0, 71.0), 0.4, 0.4, RIDE, 2, sides=3)
    tower(m, 0.0, 0.0, [(70.0, 0.35), (76.0, 0.08)], 4, RIDE, variant=2)


def _radio_city(m: Model, ctx: Context) -> None:
    """Radio City Music Hall (Edward Durell Stone and Donald Deskey, 1932),
    in the base of 1270 Avenue of the Americas: the building's massing from
    the city's 3-D model in Rockefeller Center's limestone; at the corner of
    Sixth Avenue and 50th Street the marquee, rounding the corner with the
    hall's name in lights, and the vertical RADIO CITY sign over it.
    Wikipedia, "Radio City Music Hall". Local x runs west to Sixth Avenue, y
    south to 50th Street; the corner is at (19, 30.5)."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (ROCK_SHAFT, 0))
    else:
        m.prism(_local_footprint(ctx), -1.0, 123.7, ROCK_SHAFT)
    if d == 2:
        return
    # The marquee: along Sixth Avenue, round the corner and along 50th Street.
    t = np.linspace(0.0, np.pi / 2, (5, 3)[d])
    path = np.vstack([[(19.9, 0.0)], np.column_stack([18.8 + 1.1 * np.cos(t), 30.3 + 1.1 * np.sin(t)]),
                      [(-16.0, 31.4)]])
    band = shapely.buffer(shapely.LineString(path), 0.8, cap_style="flat", join_style="round", quad_segs=2)
    m.prism(band, 4.4, 7.4, MARQUEE, bottom=True, roof=PAVING)
    # The vertical sign at the corner, its faces toward the avenue and the street.
    _box_faces(m, (20.6, 32.1, 17.0), (1.0, 4.4, 18.0), MARQUEE, 1, yaw=math.radians(-45.0))


# --- The waterfront ---

_HYDRO = {}


def _hydro_parts(area, codes) -> list:
    """The city's planimetric hydrography structures (piers, fender racks) with
    feature codes in `codes` whose parts lie in `area` (east/north): a list
    of (polygon, its top in m above sea level, from the data's elevation)."""
    if not _HYDRO:
        features = load_features("hydro_structures")
        _HYDRO["geoms"] = project(np.array([geojson_shape(f["geometry"]) for f in features], dtype=object))
        _HYDRO["codes"] = np.array([f["properties"].get("feat_code") for f in features])
        _HYDRO["tops"] = np.array([float(f["properties"].get("elevation") or 0.0) * FEET for f in features])
        _HYDRO["tree"] = shapely.STRtree(_HYDRO["geoms"])
    out = []
    for k in sorted(_HYDRO["tree"].query(area)):
        if _HYDRO["codes"][k] in codes:
            out += [(part, float(_HYDRO["tops"][k])) for part in polygons_of(_HYDRO["geoms"][k], 1.0)
                    if shapely.contains(area, part.centroid)]
    return out


def piers():
    """The piers out over the water (the planimetric hydrography structures'
    piers, feature code 2800) as one geometry, east/north. prepare.py adds
    them to the land before taking the water away, which drops every pier
    standing over the water again; build_tiles.py adds them back."""
    _hydro_parts(shapely.box(0.0, 0.0, 0.0, 0.0), ())
    if "piers" not in _HYDRO:
        picked = _HYDRO["geoms"][_HYDRO["codes"] == "2800"]
        _HYDRO["piers"] = shapely.union_all(polygons_of(shapely.union_all(shapely.make_valid(picked)), 4.0))
    return _HYDRO["piers"]


def _local(ctx, poly, tolerance):
    """An east/north polygon in the landmark's frame, simplified."""
    shell = ctx.frame.to_local(np.asarray(poly.exterior.coords)[:, :2])
    holes = [ctx.frame.to_local(np.asarray(h.coords)[:, :2]) for h in poly.interiors]
    return shapely.simplify(shapely.make_valid(Polygon(shell, holes)), tolerance)


def _heading_frame(ctx, at, heading):
    """A point (east/north) in the landmark's frame and the unit vectors
    along `heading` (degrees from east) and across it (to its left)."""
    a = math.radians(heading) - ctx.frame.angle
    along = np.array([math.cos(a), math.sin(a)])
    return ctx.frame.to_local(np.asarray([at], np.float64))[0], along, np.array([-along[1], along[0]])


def _racks(m, ctx, parts, d):
    """Timber fender racks guiding the ferries into their slips, over the
    data's outlines: walls of piles from under the water to their tops (the
    data's elevations, kept 3 to 4.5 m above the water as in photos),
    decked."""
    for poly, top in parts:
        m.prism(_local(ctx, poly, TOLERANCE[d] + 0.1), -1.5 - ctx.base, min(max(top, 3.0), 4.5) - ctx.base, TIMBER,
                roof=TIMBER, roof_variant=1)


def _slip_house(m, ctx, head, heading, d, half=12.0, top=16.0):
    """A ferry slip's house where the slip meets the terminal (`head`,
    east/north; the slip runs out toward `heading`, degrees from east): brick
    towers either side of the slip, a white steel frame over the opening,
    the transfer bridge's deck inside and the terminal's glass behind it.
    Heights in m above the water."""
    c, along, across = _heading_frame(ctx, head, heading)

    def box(u0, u1, v0, v1):
        return Polygon([c + across * u + along * v for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))])
    low, beam = -1.5 - ctx.base, top - 3.2 - ctx.base
    for side in (-1.0, 1.0):
        u0, u1 = sorted((side * half, side * (half + 6.0)))
        m.prism(box(u0, u1, -10.0, 10.0), low, beam, PIERSIDE, variant=1, roof=PAVING)
    m.prism(box(-half - 6.5, half + 6.5, -10.5, 10.5), beam, top - ctx.base, PIERSIDE, variant=3, roof=PIERSIDE)
    m.cap(box(-half, half, -10.5, 10.5), beam, PIERSIDE, variant=3, flags=0, down=True)
    if d < 2:
        m.prism(box(-half + 1.0, half - 1.0, -10.0, 4.0), low, 4.2 - ctx.base, PIERSIDE, variant=3, roof=PIERSIDE)
        m.walls([c + across * -half - along * 10.0, c + across * half - along * 10.0], 4.2 - ctx.base, beam,
                PIERSIDE, 0, closed=False)


def _ferry(m, ctx, center, heading, d):
    """A Staten Island Ferry at its slip (the Barberi and Molinari classes:
    about 95 m long and 21 m across, double-ended, orange): the hull to its
    main deck 4.5 m above the water, two passenger decks, a pilothouse at
    each end, the mast. Wikipedia, "Staten Island Ferry"."""
    c, along, across = _heading_frame(ctx, center, heading)
    n = (32, 16, 8)[d]
    t = np.arange(n) * (2 * np.pi / n)

    def plan(half_l, half_w, power):
        x = half_l * np.sign(np.cos(t)) * np.abs(np.cos(t)) ** (2.0 / power)
        y = half_w * np.sign(np.sin(t)) * np.abs(np.sin(t)) ** (2.0 / power)
        return Polygon(c + x[:, None] * along + y[:, None] * across)
    w = -ctx.base
    hull, deck, upper = plan(47.5, 10.5, 3.0), plan(43.0, 10.3, 4.0), plan(35.0, 8.6, 5.0)
    m.prism(hull, w - 2.0, w + 4.5, TIMBER, variant=3, roof=None)
    m.cap(shapely.difference(hull, deck), w + 4.5, PAVING)
    m.prism(deck, w + 4.5, w + 10.5, TIMBER, variant=3, roof=PAVING)
    m.prism(upper, w + 10.5, w + 13.6, TIMBER, variant=3, roof=PAVING)
    if d < 2:
        for end in (-1.0, 1.0):
            m.box((*(c + along * end * 29.0), w + 15.2), (5.0, 8.0, 3.2), TIMBER, yaw=math.atan2(along[1], along[0]),
                  roof=PAVING, variant=3)
        tower(m, c[0], c[1], [(w + 13.6, 0.3), (w + 22.0, 0.15)], 6, PIERSIDE, variant=3)


def _boat(m, ctx, east, north, heading, length, beam, d):
    """A boat at its mooring (place, heading, length and beam from the aerial
    photos): a white hull with a pointed bow, its cabin, a flybridge on the
    bigger ones and a mast on some of the smaller."""
    c, along, across = _heading_frame(ctx, (east, north), heading)
    w = -ctx.base

    def hull(l0, l1, half, bow):
        pts = [(l0, -half), (l1 - bow, -half), (l1, 0.0), (l1 - bow, half), (l0, half)]
        return Polygon([c + along * x + across * y for x, y in pts])
    half_l, half_b = length / 2, beam / 2
    m.prism(hull(-half_l, half_l, half_b, length * 0.3), w - 0.5, w + 1.5, TIMBER, variant=2, roof=TIMBER,
            roof_variant=2)
    if d == 2:
        return
    m.prism(hull(-half_l * 0.55, half_l * 0.35, half_b * 0.72, length * 0.12), w + 1.5, w + 2.9, TIMBER, variant=2,
            roof=TIMBER, roof_variant=2)
    seed = (east * 12.9898 + north * 78.233) % 1.0
    if length > 13.0:
        m.prism(hull(-half_l * 0.35, half_l * 0.1, half_b * 0.6, length * 0.05), w + 2.9, w + 3.9, TIMBER, variant=2,
                roof=TIMBER, roof_variant=2)
    elif seed < 0.4:
        tower(m, *(c + along * length * 0.1), [(w + 2.9, 0.12), (w + 2.9 + length * 1.3, 0.06)], 4, PIERSIDE,
              variant=3)


def _st_george(m: Model, ctx: Context) -> None:
    """St. George Ferry Terminal, Staten Island (1951; rebuilt 2005): the
    building's massing from the city's 3-D model, the waiting room's curved
    aluminum and glass curtain wall toward the harbor (40 ft high, 208 ft
    long; ENR, 2005) and brick elsewhere; four slip houses where the slips
    meet it (brick towers either side of each slip, a white steel frame over
    it; their places and headings from the city's aerial photos), the slips'
    timber fender racks (the city's planimetric hydrography structures, their
    tops from its elevations), and two ferries in their slips. Local x runs
    east, y north."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []
    harbor = np.array([math.cos(math.radians(35.0)), math.sin(math.radians(35.0))])

    def wall(middle, out):
        return 0 if out @ harbor > 0.35 else 1
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (PIERSIDE, wall), roof=PAVING)
    else:
        m.prism(_local_footprint(ctx), -1.0, 18.5, PIERSIDE, variant=wall)
    for head, heading in STG_SLIPS:
        _slip_house(m, ctx, head, heading, d)
    _racks(m, ctx, _hydro_parts(shapely.box(-7400.0, -12740.0, -7190.0, -12540.0), {"2800"}), d)
    for center, heading in STG_FERRIES:
        _ferry(m, ctx, center, heading, d)


def _whitehall(m: Model, ctx: Context) -> None:
    """Whitehall Terminal, the Staten Island Ferry's Manhattan end (Frederic
    Schwartz Architects, 2005): four stories, glass on three sides (the
    waiting room's 75 ft glass wall) and corrugated stainless steel toward the
    slips, and the long, sinuous canopy over the street side carrying the
    words "Staten Island Ferry" (Wikipedia, "Whitehall Terminal"); the
    massing and the canopy's outline from the city's 3-D model; the slips'
    timber racks (the city's planimetric hydrography structures) and a
    ferry in the east slip (the city's aerial photos). Local x runs east, y
    north."""
    d = m.detail
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, d) if ctx.shape else []

    def wall(middle, out):
        return 2 if out[1] < -0.7 else 0
    if len(terraces) > 1:
        # The canopy: the lowest tier beyond the building above it, a slab on columns.
        building = terraces[1][1]
        canopy = shapely.difference(terraces[0][1], shapely.buffer(building, 0.3, join_style="mitre"))
        add_terraces(m, [(level, shapely.intersection(outline, shapely.buffer(building, 0.3, join_style="mitre")))
                         for level, outline in terraces], lambda lo, hi: (PIERSIDE, wall), roof=PAVING)
        top = terraces[0][0]
        for part in polygons_of(canopy, 20.0):
            # Its fascia's uv.y runs up from the fascia's foot: the words' band.
            part = shapely.orient_polygons(part)
            count = len(m.pos)
            m.walls(np.asarray(part.exterior.coords), 0.0, 1.1, PIERSIDE, 3)
            for k in range(count, len(m.pos)):
                m.pos[k] = m.pos[k] + np.array([0.0, 0.0, top - 1.1])
            m.cap(part, top, PIERSIDE)
            m.cap(part, top - 1.1, PIERSIDE, variant=3, flags=0, down=True)
            if d < 2:
                spine = shapely.buffer(part, -1.5, join_style="mitre")
                for ring in polygons_of(spine, 1.0):
                    line = ring.exterior
                    for s in np.arange(0.0, line.length, 14.0):
                        p = line.interpolate(s)
                        m.box((p.x, p.y, (top - 1.1 - 1.0) / 2), (0.5, 0.5, top - 1.1 + 1.0), PIERSIDE, variant=3,
                              roof=PIERSIDE)
    else:
        m.prism(_local_footprint(ctx), -1.0, 27.7, PIERSIDE, variant=wall)
    _racks(m, ctx, _hydro_parts(shapely.box(-2400.0, -6480.0, -2240.0, -6378.0), {"2810"}), d)
    _ferry(m, ctx, (-2276.0, -6422.5), -72.7, d)


def _chelsea_shed(m: Model, ctx: Context) -> None:
    """Chelsea Piers' pier sheds (Warren and Wetmore, 1910; a sports complex
    since 1995), Piers 60 and 61 on the Hudson: the sheds' side aisles to
    8 m and the stepped monitor roof up to 22 m from the city's 3-D model,
    clad in metal panels with bands of windows. Wikipedia, "Chelsea
    Piers". Local x runs east, y north."""
    terraces = model_terraces(ctx.shape, ctx.frame, 1000.0, m.detail) if ctx.shape else []
    if terraces:
        add_terraces(m, terraces, lambda lo, hi: (PIERSIDE, 2), roof=PIERSIDE)
    else:
        m.prism(_local_footprint(ctx), -1.0, 24.0, PIERSIDE, variant=2, roof=PIERSIDE)


def _chelsea_golf(m: Model, ctx: Context) -> None:
    """The Golf Club at Chelsea Piers, Pier 59: the driving range's netting
    over the pier, hung from steel poles about 46 m (150 ft) tall along both
    sides and the far end (its outline and the poles' spacing from the
    city's aerial photos, the height from their shadows), drawn as its poles
    and cables. Local x runs east, y north."""
    d = m.detail
    nw, ne, se, sw = (ctx.frame.to_local(np.asarray([p], np.float64))[0] for p in CHELSEA_GOLF)
    top = 46.0
    count = 6
    north = [nw + (ne - nw) * k / (count - 1) for k in range(count)]
    south = [sw + (se - sw) * k / (count - 1) for k in range(count)]
    for p in north + south:
        tower(m, p[0], p[1], [(-1.0, 0.45), (top, 0.22)], (8, 6, 4)[d], PIERSIDE, variant=3)
    if d == 2:
        return
    for a, b in zip(north[:-1], north[1:]):
        for z in (top, top / 2):
            _beam(m, (*a, z), (*b, z), 0.15, 0.15, PIERSIDE, variant=3)
    for a, b in zip(south[:-1], south[1:]):
        for z in (top, top / 2):
            _beam(m, (*a, z), (*b, z), 0.15, 0.15, PIERSIDE, variant=3)
    for a, b in zip(north, south):
        _beam(m, (*a, top), (*b, top), 0.15, 0.15, PIERSIDE, variant=3)
    _beam(m, (*north[0], top / 2), (*south[0], top / 2), 0.15, 0.15, PIERSIDE, variant=3)


def _bbp_pier2(m: Model, ctx: Context) -> None:
    """Brooklyn Bridge Park's Pier 2 (2013): the 1950s pier shed's steel frame
    and roof kept, open-sided, over basketball and handball courts and a
    roller rink, cut back to leave the lawn at the west end and courts in
    the middle open to the sky. Its three roofs (the city's aerial photos)
    in ridged bays 10 m up (the footprint data) on steel columns. Local x
    runs east, y north."""
    d = m.detail
    eaves, ridge = 9.0, 10.1
    for corners in BBP_PIER2_ROOFS:
        nw, ne, se, sw = ctx.frame.to_local(np.asarray(corners, np.float64))
        length, width = float(np.linalg.norm(ne - nw)), float(np.linalg.norm(sw - nw))
        along, across = (ne - nw) / length, (sw - nw) / width
        bays = max(1, round(width / 6.5))
        quads, uvs = [], []
        for k in range(bays):
            s0, s1 = width * k / bays, width * (k + 1) / bays
            sm = (s0 + s1) / 2
            for a, b, za, zb in ((s0, sm, eaves, ridge), (sm, s1, ridge, eaves)):
                p0, p1 = nw + across * a, nw + across * b
                quad = np.array([(*p0, za), (*(p0 + along * length), za), (*(p1 + along * length), zb), (*p1, zb)])
                if np.cross(quad[1] - quad[0], quad[3] - quad[0])[2] < 0:
                    quad = quad[::-1]
                quads.append(quad)
                uvs.append(quad[:, :2])
        _quads(m, np.array(quads), np.array(uvs), PIERSIDE, 0.0, flags=ROOF)
        # The bays' gable ends.
        for k in range(bays):
            s0, s1 = width * k / bays, width * (k + 1) / bays
            for end, out in ((0.0, -along), (length, along)):
                p0, p1, top = (nw + along * end + across * s0, nw + along * end + across * s1,
                               nw + along * end + across * (s0 + s1) / 2)
                tri = np.array([(*p0, eaves), (*p1, eaves), (*top, ridge)])
                m.add(tri[None], np.array([[[0.0, eaves], [s1 - s0, eaves], [(s1 - s0) / 2, ridge]]]), PIERSIDE,
                      4 * 10 + 3, (out[0], out[1], 0.0))
        outline = Polygon([nw, ne, se, sw])
        m.prism(outline, eaves - 0.7, eaves, PIERSIDE, variant=3, roof=None)
        m.cap(outline, eaves - 0.7, PIERSIDE, variant=3, flags=0, down=True)
        if d < 2:
            for k in range(bays + 1):
                line = nw + across * (width * k / bays + (0.3 if k == 0 else -0.3 if k == bays else 0.0))
                for s in np.linspace(0.6, length - 0.6, max(2, round(length / 12.0) + 1)):
                    p = line + along * s
                    m.box((p[0], p[1], (eaves - 0.7 - 1.0) / 2), (0.4, 0.4, eaves - 0.7 + 1.0), PIERSIDE, variant=3,
                          roof=PIERSIDE)


def berm_height(en) -> np.ndarray:
    """The Pier 3 berm's height above the ground at (N, 2) east/north points
    (0 off it): a ridge along BBP_BERM, steep toward Furman Street (east) and
    sloping gently into the park (west), tapering at its ends."""
    en = np.asarray(en, np.float64).reshape(-1, 2)
    crest = np.asarray(BBP_BERM, np.float64)
    near = np.full(len(en), np.inf)
    side = np.zeros(len(en))
    place = np.zeros(len(en))
    start = 0.0
    for a, b in zip(crest[:-1], crest[1:]):
        length = float(np.linalg.norm(b - a))
        u = (b - a) / length
        rel = en - a
        t = np.clip(rel @ u, 0.0, length)
        dist = np.linalg.norm(rel - t[:, None] * u, axis=1)
        closer = dist < near
        near[closer] = dist[closer]
        side[closer] = -(u[0] * rel[closer, 1] - u[1] * rel[closer, 0])  # west of the crest positive
        place[closer] = start + t[closer]
        start += length
    reach = np.where(side >= 0.0, BERM_WEST, BERM_EAST)
    x = np.clip(near / reach, 0.0, 1.0)
    ends = np.clip(place / BERM_ENDS, 0.0, 1.0) * np.clip((start - place) / BERM_ENDS, 0.0, 1.0)
    return BERM_HEIGHT * 0.5 * (1.0 + np.cos(np.pi * x)) * (ends * ends * (3.0 - 2.0 * ends))


def lift(en) -> np.ndarray:
    """How far above the terrain hand-made ground (the Pier 3 berm) raises
    what stands at (N, 2) east/north points: trees and their crowns."""
    en = np.asarray(en, np.float64).reshape(-1, 2)
    out = np.zeros(len(en))
    crest = np.asarray(BBP_BERM)
    lo, hi = crest.min(axis=0) - BERM_WEST, crest.max(axis=0) + BERM_WEST
    inside = np.all((en >= lo) & (en <= hi), axis=1)
    if inside.any():
        out[inside] = berm_height(en[inside])
    return out


def _bbp_berm(m: Model, ctx: Context) -> None:
    """Brooklyn Bridge Park's sound-attenuating berm (2013) along Furman
    Street at the Pier 3 uplands: a hill 30 ft (9.1 m) high and about 800 ft
    long, planted with meadow grasses, lawns sloping from its foot and trees
    (from the land cover map, standing on it: lift()). Brooklyn Bridge Park's
    press release (2013); its line from the city's aerial photos. Local x
    runs east, y north."""
    d = m.detail
    crest = np.asarray(BBP_BERM, np.float64)
    step, across = (3.0, 6.0, 15.0)[d], (2.0, 4.0, 8.0)[d]
    stations, normals = [], []
    for a, b in zip(crest[:-1], crest[1:]):
        length = float(np.linalg.norm(b - a))
        u = (b - a) / length
        for t in np.arange(0.0, length, step):
            stations.append(a + u * t)
            normals.append(np.array([-u[1], u[0]]) * -1.0)  # west
    stations.append(crest[-1])
    normals.append(normals[-1])
    s = np.arange(-BERM_EAST - 2.0, BERM_WEST + 2.0 + 1e-6, across)
    grid = np.array([[p + nrm * v for v in s] for p, nrm in zip(stations, normals)])  # (rows, cols, 2) east/north
    flat = grid.reshape(-1, 2)
    local = ctx.frame.to_local(flat)
    z = ctx.ground(local) + berm_height(flat) - 0.3
    eps = 0.5
    gx = (berm_height(flat + [eps, 0.0]) - berm_height(flat - [eps, 0.0])) / (2 * eps)
    gy = (berm_height(flat + [0.0, eps]) - berm_height(flat - [0.0, eps])) / (2 * eps)
    c, s_ = math.cos(ctx.frame.angle), math.sin(ctx.frame.angle)
    normal = np.column_stack([-(gx * c + gy * s_), -(-gx * s_ + gy * c), np.ones(len(flat))])
    normal /= np.linalg.norm(normal, axis=1, keepdims=True)
    points = np.column_stack([local, z]).reshape(grid.shape[0], grid.shape[1], 3)
    normal = normal.reshape(points.shape)
    rows, cols = points.shape[:2]
    quads = np.stack([points[:-1, :-1], points[:-1, 1:], points[1:, 1:], points[1:, :-1]], 2).reshape(-1, 4, 3)
    quad_normals = np.stack([normal[:-1, :-1], normal[:-1, 1:], normal[1:, 1:], normal[1:, :-1]], 2).reshape(-1, 4, 3)
    up = np.cross(quads[:, 1] - quads[:, 0], quads[:, 3] - quads[:, 0])[:, 2] < 0
    quads[up] = quads[up][:, ::-1]
    quad_normals[up] = quad_normals[up][:, ::-1]
    _quads(m, quads, quads[..., :2], PLAYFIELD, 3.0, flags=ROOF, normals=quad_normals)


def _bbp_marina(m: Model, ctx: Context) -> None:
    """ONE15 Brooklyn Marina (2016), between Piers 3 and 5 in Brooklyn
    Bridge Park: its floating docks (the narrow parts of the city's
    planimetric pier outline there, which joins them to Pier 5) decked in
    timber, the wave attenuators' pilings, and the boats moored there in the
    city's aerial photos (March 2024). Local x runs east, y north."""
    d = m.detail
    w = -ctx.base
    for poly, _ in _hydro_parts(shapely.box(-1460.0, -7000.0, -1150.0, -6700.0), {"2800"}):
        local = _local(ctx, poly, 0.2)
        body = shapely.buffer(shapely.buffer(local, -3.0, join_style="mitre"), 3.0, join_style="mitre")
        for dock in polygons_of(shapely.difference(local, shapely.buffer(body, 0.05, join_style="mitre")), 6.0):
            dock = shapely.simplify(dock, TOLERANCE[d])
            m.prism(dock, w - 0.5, w + 2.15, TIMBER, variant=1, roof=TIMBER, roof_variant=1)
            corners = np.asarray(shapely.oriented_envelope(dock).exterior.coords)[:4]
            edges = [corners[1] - corners[0], corners[2] - corners[1]]
            longest = max(edges, key=lambda e: np.linalg.norm(e))
            if d < 2 and np.linalg.norm(longest) > 60.0:
                middle = corners.mean(axis=0)
                axis = longest / np.linalg.norm(longest)
                half = float(np.linalg.norm(longest)) / 2
                for s in np.arange(-half + 4.0, half - 3.0, 15.0):
                    p = middle + axis * s
                    tower(m, p[0], p[1], [(w - 1.5, 0.38), (w + 7.0, 0.38)], 6, TIMBER, variant=0)
    for boat in BBP_BOATS:
        _boat(m, ctx, *boat, d)


# Where the St. George slips meet the terminal (the slip houses' middles,
# east/north) and their headings (degrees from east); the ferries in two of
# them. From the city's aerial photos.
STG_SLIPS = (((-7385.0, -12568.0), 48.0), ((-7331.0, -12603.0), 27.0), ((-7309.0, -12644.0), 23.0),
             ((-7294.0, -12692.0), 15.0))
STG_FERRIES = (((-7285.0, -12572.0), 27.0), ((-7260.0, -12627.0), 23.0))
# The Chelsea Piers driving range's netting (NW, NE, SE, SW corners, east/north).
CHELSEA_GOLF = ((-2190.0, -1337.0), (-2042.0, -1358.0), (-2042.0, -1398.0), (-2190.0, -1380.0))
# Pier 2's three roofs (NW, NE, SE, SW corners, east/north).
BBP_PIER2_ROOFS = (((-1148.5, -6429.5), (-1034.5, -6482.0), (-1049.5, -6509.0), (-1162.0, -6456.5)),
                   ((-1096.0, -6492.5), (-1049.5, -6510.5), (-1060.0, -6542.0), (-1106.5, -6521.0)),
                   ((-1210.0, -6479.0), (-1084.0, -6524.0), (-1090.0, -6549.5), (-1216.0, -6500.0)))
# The Pier 3 berm's crest (east/north, north to south), its height, reach east
# and west of the crest and the length its ends taper over (m).
BBP_BERM = ((-1011.0, -6602.0), (-1021.5, -6637.5), (-1039.0, -6707.5), (-1060.0, -6767.0), (-1081.0, -6816.0),
            (-1088.0, -6832.0))
BERM_HEIGHT, BERM_EAST, BERM_WEST, BERM_ENDS = 9.1, 13.0, 30.0, 25.0
# Boats moored in the ONE15 marina: (east, north, heading, length, beam), found
# as bright hulls on the water in the city's aerial photos (March 2024).
BBP_BOATS = ((-1302.2, -6873.1, 138.0, 9.6, 3.1), (-1312.4, -6893.3, 153.0, 11.7, 4.3),
             (-1218.2, -6903.5, 159.0, 5.7, 2.5), (-1319.4, -6907.9, 155.0, 12.9, 4.9),
             (-1221.2, -6913.0, 162.0, 8.0, 3.3), (-1262.1, -6920.9, 174.0, 8.9, 4.6),
             (-1226.5, -6923.6, 155.0, 8.0, 3.1), (-1325.6, -6925.4, 154.0, 12.6, 3.9),
             (-1230.4, -6931.5, 162.0, 7.8, 3.2), (-1332.4, -6936.2, 170.0, 10.4, 3.5),
             (-1234.1, -6939.7, 158.0, 8.2, 3.4), (-1239.3, -6949.0, 158.0, 8.0, 3.3),
             (-1243.0, -6958.7, 159.0, 7.9, 3.2), (-1246.9, -6966.7, 162.0, 8.0, 3.3),
             (-1249.1, -6972.7, 155.0, 5.5, 2.6))


LANDMARKS = [
    Landmark("Empire State Building", (1015862,), 151.06, _empire_state),
    Landmark("Chrysler Building", (1036156,), 150.94, _chrysler),
    Landmark("One World Trade Center", (1088469,), 151.0, _one_wtc),
    Landmark("Flatiron Building", (1016278,), -96.08, _flatiron),
    Landmark("Statue of Liberty", (1000002,), 230.0, _liberty, exact=True),  # facing south-east
    Landmark("Woolworth Building", (1087167,), -31.07, _woolworth),
    Landmark("Grand Central Terminal", (1035381,), -29.21, _grand_central),
    Landmark("30 Rockefeller Plaza", (1076262,), 150.71, _rockefeller),
    # The second batch.
    Landmark("Guggenheim Museum", (1046946,), 150.89, _guggenheim),
    Landmark("New York Public Library", (1034194,), 150.97, _nypl),
    Landmark("St. Patrick's Cathedral", (1081150,), 151.52, _st_patricks),
    Landmark("United Nations Secretariat", (1083875,), 150.91, _un_secretariat),
    Landmark("United Nations General Assembly", (1083872,), 163.03, _un_general_assembly),
    Landmark("Citigroup Center", (1036474,), 150.76, _citigroup),
    Landmark("Hearst Tower", (1025451,), 150.92, _hearst),
    Landmark("Metropolitan Museum of Art", (1083810,), 151.19, _met),
    Landmark("Vessel", (1090391, 1090967), 0.0, _vessel, exact=True),
    Landmark("The Oculus", (1089309,), 141.81, _oculus),
    Landmark("Yankee Stadium", (2114490,), -24.09, _yankee_stadium),
    Landmark("Unisphere", (), 0.0, _unisphere, at=(11859.8, -1278.2), exact=True),
    Landmark("Wonder Wheel", (3347224,), 0.0, _wonder_wheel, at=(538.0, -20425.5), exact=True),
    Landmark("Parachute Jump", (3404019,), 0.0, _parachute_jump),
    Landmark("Radio City Music Hall", (1083861,), 151.06, _radio_city),
    # The waterfront.
    Landmark("St. George Ferry Terminal", (5141706,), 0.0, _st_george, exact=True),
    Landmark("Whitehall Terminal", (1085792,), 0.0, _whitehall, exact=True),
    Landmark("Chelsea Piers, Pier 60", (1012255,), 0.0, _chelsea_shed, exact=True),
    Landmark("Chelsea Piers, Pier 61", (1085935,), 0.0, _chelsea_shed, exact=True),
    Landmark("Chelsea Piers golf range", (), 0.0, _chelsea_golf, at=(-2116.0, -1368.0), exact=True),
    Landmark("Brooklyn Bridge Park, Pier 2", (3423335,), 0.0, _bbp_pier2, exact=True),
    Landmark("Brooklyn Bridge Park berm", (), 0.0, _bbp_berm, at=(-1046.0, -6720.0), exact=True),
    Landmark("ONE15 Brooklyn Marina", (), 0.0, _bbp_marina, at=(-1300.0, -6900.0), exact=True),
]
REPLACED = np.array(sorted({b for landmark in LANDMARKS for b in landmark.bins}), dtype=np.int64)

_index = {}


def without(indices: np.ndarray, bins: np.ndarray) -> np.ndarray:
    """`indices` (into the prepared buildings) minus the buildings landmarks replace."""
    if len(indices) == 0:
        return indices
    return indices[~np.isin(bins[indices], REPLACED)]


def _frame(landmark: Landmark, footprint) -> Frame:
    origin = np.asarray(landmark.at if landmark.at else footprint.centroid.coords[0], np.float64)
    if landmark.exact:
        return Frame(origin, math.radians(landmark.angle))
    return Frame(origin, footprint_frame(footprint, landmark.angle).angle)


def build(landmark: Landmark, footprint, shape, detail: int, height=None, base: float = 0.0) -> tuple[Model, Frame]:
    """A landmark's model and frame; height(east/north (N, 2)) is the terrain's
    height above where it stands (`base` m above sea level), if known."""
    frame = _frame(landmark, footprint)
    model = Model(detail)
    context = Context(footprint, frame, shape, detail, base=base)
    if height is not None:
        context.ground = lambda xy: height(frame.to_world(np.asarray(xy, np.float64).reshape(-1, 2)))
    landmark.build(model, context)
    return model, frame


def add_to_tile(builder, level: str, size: float, i: int, j: int, buildings: dict, shapes: dict,
                ground_of, terrain=None, own_builder=None, waterfront_builder=None) -> int:
    """Adds the landmarks whose main building (or `at`) is anchored in tile
    (i, j) of `level` (tiles `size` m) to its buildings MeshBuilder;
    ground_of(footprint) is where a building stands, terrain(east/north (N, 2))
    the ground's height; own_builder and waterfront_builder take the faces
    shaders/landmark.gdshader and shaders/waterfront.gdshader paint (see
    place()). Returns how many triangles it added."""
    key = id(buildings)
    if key not in _index:
        found = np.flatnonzero(np.isin(buildings["bin"], [lm.bins[0] for lm in LANDMARKS if lm.bins]))
        _index.clear()
        _index[key] = {int(buildings["bin"][k]): int(k) for k in found}
    index = _index[key]
    added = 0
    for landmark in LANDMARKS:
        if landmark.bins:
            k = index.get(landmark.bins[0])
            if k is None:
                continue
            anchor, footprint = buildings["anchor"][k], buildings["geoms"][k]
            shape = shapes.get(landmark.bins[0])
        else:
            anchor = np.asarray(landmark.at, np.float64)
            footprint, shape = shapely.Point(anchor).buffer(2.0, quad_segs=2), None
        if (math.floor(anchor[0] / size), math.floor(-anchor[1] / size)) != (i, j):
            continue
        base = ground_of(footprint)
        height = None if terrain is None else (lambda en, base=base: terrain(en) - base)
        model, frame = build(landmark, footprint, shape, DETAIL[level], height, base)
        place(model, builder, frame, base, own_builder, waterfront_builder)
        added += model.triangles()
    return added
