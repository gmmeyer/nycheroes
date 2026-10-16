"""Hand-made landmarks: New York's most famous buildings, modeled here at
their real dimensions in place of the footprint prisms and 3-D model shapes.

Each landmark replaces the data buildings with its BINs (build_tiles.py drops
them) and is added once per detail level, to the tile holding its main
building's anchor, into that tile's buildings surface: no extra draw calls, it
streams with the levels of detail, and near tiles give it collision. Faces
carry a landmark material in the archetype slot of uv2.x (16 and up; the data
buildings use 0-15, see facades.py), which shaders/building.gdshader paints:

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

import buildings3d
import facades
from common import polygon_normal, polygons_of, triangles_of

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
    tier's (material, variant)."""
    bottom = -1.0  # walls' feet sink into the ground, like the data buildings
    for k, (level, outline) in enumerate(terraces):
        kind, variant = material(max(bottom, 0.0), level)
        for poly in polygons_of(outline, 0.05):
            for ring in (poly.exterior, *poly.interiors):
                model.walls(np.asarray(ring.coords), bottom, level, kind, variant)
        above = terraces[k + 1][1] if k + 1 < len(terraces) else Polygon()
        model.cap(shapely.difference(outline, above) if not above.is_empty else outline, level, roof)
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


def place(model: Model, builder, frame: Frame, ground: float) -> None:
    """Adds a model to a tile's MeshBuilder (Godot space), standing at `ground`."""
    c, s = math.cos(frame.angle), math.sin(frame.angle)

    def rotate(v):
        return np.stack([v[..., 0] * c - v[..., 1] * s, v[..., 2], -(v[..., 0] * s + v[..., 1] * c)], axis=-1)

    for pos, uv, code, param, front, normals in zip(model.pos, model.uv, model.code, model.param, model.front,
                                                    model.normals):
        en = frame.to_world(pos[..., :2])
        world = np.stack([en[..., 0], pos[..., 2] + ground, -en[..., 1]], axis=-1)
        uv2 = np.repeat(np.column_stack([code, param + SEED])[:, None, :], 3, axis=1)
        builder.add(world, uv, uv2, rotate(front), rotate(normals))


# --- The landmarks ---

@dataclass
class Landmark:
    name: str
    bins: tuple          # data buildings it replaces; the first is the main one
    angle: float         # nominal direction of the local x axis (degrees from east)
    build: object        # build(model, context)


@dataclass
class Context:
    footprint: object    # the main building's footprint (east/north)
    frame: Frame
    shape: object        # the 3-D model's shape for the main BIN, or None
    detail: int


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


LANDMARKS = [
    Landmark("Empire State Building", (1015862,), 151.06, _empire_state),
    Landmark("Chrysler Building", (1036156,), 150.94, _chrysler),
    Landmark("One World Trade Center", (1088469,), 151.0, _one_wtc),
    Landmark("Flatiron Building", (1016278,), -96.08, _flatiron),
    Landmark("Statue of Liberty", (1000002,), 230.0, _liberty),
    Landmark("Woolworth Building", (1087167,), -31.07, _woolworth),
    Landmark("Grand Central Terminal", (1035381,), -29.21, _grand_central),
    Landmark("30 Rockefeller Plaza", (1076262,), 150.71, _rockefeller),
]
# Statue of Liberty: her frame is her own (facing south-east), not the
# footprint's; see _frame().
FACING_FRAMES = {"Statue of Liberty"}
REPLACED = np.array(sorted({b for landmark in LANDMARKS for b in landmark.bins}), dtype=np.int64)

_index = {}


def without(indices: np.ndarray, bins: np.ndarray) -> np.ndarray:
    """`indices` (into the prepared buildings) minus the buildings landmarks replace."""
    if len(indices) == 0:
        return indices
    return indices[~np.isin(bins[indices], REPLACED)]


def _frame(landmark: Landmark, footprint) -> Frame:
    if landmark.name in FACING_FRAMES:
        return Frame(np.asarray(footprint.centroid.coords)[0], math.radians(landmark.angle))
    return footprint_frame(footprint, landmark.angle)


def build(landmark: Landmark, footprint, shape, detail: int) -> tuple[Model, Frame]:
    frame = _frame(landmark, footprint)
    model = Model(detail)
    landmark.build(model, Context(footprint, frame, shape, detail))
    return model, frame


def add_to_tile(builder, level: str, size: float, i: int, j: int, buildings: dict, shapes: dict,
                ground_of) -> int:
    """Adds the landmarks whose main building is anchored in tile (i, j) of
    `level` (tiles `size` m) to its buildings MeshBuilder; ground_of(footprint)
    is where a building stands. Returns how many triangles it added."""
    key = id(buildings)
    if key not in _index:
        found = np.flatnonzero(np.isin(buildings["bin"], [lm.bins[0] for lm in LANDMARKS]))
        _index.clear()
        _index[key] = {int(buildings["bin"][k]): int(k) for k in found}
    index = _index[key]
    added = 0
    for landmark in LANDMARKS:
        k = index.get(landmark.bins[0])
        if k is None:
            continue
        anchor = buildings["anchor"][k]
        if (math.floor(anchor[0] / size), math.floor(-anchor[1] / size)) != (i, j):
            continue
        footprint = buildings["geoms"][k]
        model, frame = build(landmark, footprint, shapes.get(landmark.bins[0]), DETAIL[level])
        place(model, builder, frame, ground_of(footprint))
        added += model.triangles()
    return added
