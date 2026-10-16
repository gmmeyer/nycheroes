"""Hand-made bridges: New York's famous bridges at their real dimensions, in
place of bridges.py's generic deck, towers and cables.

Each one takes over a stretch of its outline (its section: anchorage to
anchorage, the arch between its towers, or the whole bridge) and builds its
own structure there; the generic deck, columns and lamps stay on the rest
(the approaches). Road decks sit at bridges.py's deck profile (deck_y, with a
camber for the Brooklyn Bridge), so traffic lanes, street paint and props
find them like any other deck (overpasses.DeckSurface reads road tops), and
near tiles give everything collision.

  - Brooklyn Bridge (John A. and Washington Roebling, 1883): granite towers
    with two pointed arches each, four cables over four stiffening trusses
    with vertical suspenders and the diagonal stays, the raised promenade
    between the roadways, overhead crossbeams, limestone anchorages.
  - Manhattan Bridge (Leon Moisseiff, 1909): blue steel towers of four
    braced columns with arched portals, four cables over four deep trusses,
    upper roadways over the subway tracks, the lower roadway between them,
    the walkway and bikeway outside, granite anchorages.
  - Hell Gate Bridge (Gustav Lindenthal, 1916): the two-hinged steel arch
    between granite towers, its humped upper chord, four tracks; the rest of
    the viaduct is the generic deck with a ballast top.
  - High Bridge (John B. Jervis, 1848; steel arch 1928): granite arches on
    tall piers and the steel arch over the Harlem River, the brick walkway.

Sources: dimensions from NYC DOT, the HAER records and Wikipedia's articles
on each bridge (with the figures they cite); tower and pier positions from
OpenStreetMap (ODbL; bridges.TOWERS and TOWERS here).

Faces are structures (common.STRUCTURE_*) that shaders/ground.gdshader
paints; their uv2.y is palette + 8 * flags (the palette picks the bridge's
colors: Brooklyn's tan steel and buff granite, Manhattan's blue, Hell Gate's
red): LATTICE paints steel as an open truss (uv = (m along, 0..1 up the
band)), FLOODLIT lights it at night, BALLAST draws track beds without ties
(their uv is then world x/z), RIVETS rivets steel (and stiffens plates; the
els', els.py).
"""

import math
from dataclasses import dataclass, field

import numpy as np
import shapely
from shapely.geometry import Polygon

from common import (GROUND_ROAD, STRUCTURE_CABLE, STRUCTURE_CONCRETE, STRUCTURE_RAIL,
                    STRUCTURE_STEEL, STRUCTURE_STONE, STRUCTURE_WALKWAY, lines_of, polygons_of, project,
                    triangles_of)

# Palettes (uv2.y % 8), as in shaders/ground.gdshader.
BROOKLYN, MANHATTAN, HELL_GATE, HIGH_BRIDGE = 1, 2, 3, 4
PALETTES = {"Brooklyn Bridge": BROOKLYN, "Manhatten Bridge": MANHATTAN, "Hellgate Bridge": HELL_GATE,
            "High Bridge/Aqueduct Bridge": HIGH_BRIDGE}
# Flags (uv2.y // 8).
LATTICE, FLOODLIT, BALLAST, RIVETS = 1, 2, 4, 8

# Outlines that aren't vehicular bridges (feature code 2300) in the data:
# the Hell Gate's is a railroad bridge (2320), the High Bridge's a
# pedestrian one (2330). bridges.build takes these too.
OUTLINES = ("Hellgate Bridge", "High Bridge/Aqueduct Bridge")
# Where towers and piers stand that bridges.TOWERS doesn't list (latitude,
# longitude; OpenStreetMap's bridge:support ways): the Hell Gate's towers
# (Wards Island, Queens) and the High Bridge's steel arch piers (Manhattan,
# the Bronx).
TOWERS = {
    "Hellgate Bridge": ((40.783585, -73.923419), (40.781499, -73.920641)),
    "High Bridge/Aqueduct Bridge": ((40.842436, -73.931349), (40.842281, -73.929676)),
}
# Deck rise from the towers to mid-span (m), parabolic: the Brooklyn Bridge's
# roadway is 119.25 ft above high water at the towers and 135 ft mid-river.
CAMBER = {"Brooklyn Bridge": 4.75}
# Rail and footbridges: no street lamps along their decks, no traffic.
NOT_ROADS = ("Hellgate Bridge", "High Bridge/Aqueduct Bridge")
# Approaches built of masonry: stone sides and piers on the generic deck.
MASONRY = ("Brooklyn Bridge",)

DETAIL = {"lod0": 0, "lod1": 1, "lod2": 2}
DECK_STEP = (8.0, 16.0, 40.0)  # meters between deck stations per detail level
WATER_FOOTING_Y = -8.0


def towers_of(name: str) -> np.ndarray:
    """TOWERS' points for a bridge, (N, 2) east/north."""
    return shapely.get_coordinates(project(shapely.points([(lon, lat) for lat, lon in TOWERS[name]])))


@dataclass
class Site:
    """What a hand-made bridge is built on: its outline, its towers (east/north,
    in order along the bridge), the deck profile and the city around it."""
    name: str
    poly: object
    towers: np.ndarray
    deck_y: object      # (N, 2) east/north -> deck top heights (m)
    terrain: object
    land: object


@dataclass
class Built:
    """What a hand-made bridge leaves to bridges.py: the section it built (the
    generic deck stays off it), and lamps along it (positions, heights, arm
    directions, like props.deck_lamps; post_tops are historic lamps)."""
    section: object
    cobra_heads: list = field(default_factory=list)
    post_tops: list = field(default_factory=list)


class Frame:
    """A bridge's frame: s meters along u from `center` (east/north), t meters
    across, toward u turned left; z meters above sea level."""

    def __init__(self, center, u):
        self.center = np.asarray(center, np.float64)
        u = np.asarray(u, np.float64)
        self.u = u / np.linalg.norm(u)
        self.v = np.array([-self.u[1], self.u[0]])

    def en(self, s, t):
        s, t = np.broadcast_arrays(np.asarray(s, np.float64), np.asarray(t, np.float64))
        return self.center + s[..., None] * self.u + t[..., None] * self.v

    def godot(self, local):
        """(..., 3) local (s, t, z) points -> Godot x, y, z."""
        local = np.asarray(local, np.float64)
        en = self.en(local[..., 0], local[..., 1])
        return np.stack([en[..., 0], local[..., 2], -en[..., 1]], axis=-1)

    def direction(self, local):
        """(..., 3) local directions -> Godot directions."""
        local = np.asarray(local, np.float64)
        e = local[..., 0] * self.u[0] + local[..., 1] * self.v[0]
        n = local[..., 0] * self.u[1] + local[..., 1] * self.v[1]
        return np.stack([e, local[..., 2], -n], axis=-1)

    def along(self, en) -> np.ndarray:
        """s of (N, 2) east/north points."""
        return (np.asarray(en, np.float64) - self.center) @ self.u

    def rect(self, s0, s1, t0, t1):
        """The east/north polygon of an s, t rectangle."""
        return Polygon(self.en(np.array([s0, s1, s1, s0]), np.array([t0, t0, t1, t1])))


def _unit(v):
    v = np.asarray(v, np.float64)
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


class Mesh:
    """One detail level of a bridge: faces given in its frame, added to the
    level's MeshBuilder with the bridge's palette."""

    def __init__(self, builder, frame: Frame, palette: int, detail: int):
        self.builder, self.f, self.palette, self.detail = builder, frame, palette, detail

    def code(self, flags=0) -> float:
        return float(self.palette + 8 * flags)

    def tris(self, pos, uv, kind, normal, flags=0, plain=False):
        """Triangles (T, 3, 3) in local s, t, z with uv (T, 3, 2) and outward
        normals (T, 3) or (3,); `plain` ones carry no palette (road tops)."""
        pos = np.asarray(pos, np.float64).reshape(-1, 3, 3)
        if len(pos) == 0:
            return
        normal = np.broadcast_to(np.asarray(normal, np.float64), (len(pos), 3))
        self.builder.add(self.f.godot(pos), np.asarray(uv, np.float64).reshape(-1, 3, 2),
                         (kind, 0.0 if plain else self.code(flags)), self.f.direction(normal))

    def quads(self, corners, uv, kind, normal, flags=0, plain=False):
        corners = np.asarray(corners, np.float64).reshape(-1, 4, 3)
        uv = np.asarray(uv, np.float64).reshape(-1, 4, 2)
        normal = np.broadcast_to(np.asarray(normal, np.float64), (len(corners), 3))
        half = [[0, 1, 2], [0, 2, 3]]
        self.tris(corners[:, half].reshape(-1, 3, 3), uv[:, half].reshape(-1, 3, 2), kind,
                  np.repeat(normal, 2, axis=0), flags, plain)

    def strips(self, a, b, across, half, kind, flags=0):
        """Flat bars from a to b ((N, 3) local), `half` wide either side along
        `across` (unit, (3,) or (N, 3)). uv = (m along, 2 + m across), clear of
        the cables' necklace lights."""
        a, b = np.atleast_2d(np.asarray(a, np.float64)), np.atleast_2d(np.asarray(b, np.float64))
        if len(a) == 0:
            return
        across = np.broadcast_to(np.asarray(across, np.float64), a.shape)
        half = np.broadcast_to(np.asarray(half, np.float64), (len(a),))[:, None]
        length = np.linalg.norm(b - a, axis=1)
        normal = _unit(np.cross(b - a, across))
        corners = np.stack([a - across * half, b - across * half, b + across * half, a + across * half], 1)
        zero, width = np.zeros(len(a)), 2.0 * half[:, 0]
        uv = np.stack([np.column_stack([zero, zero + 2.0]), np.column_stack([length, zero + 2.0]),
                       np.column_stack([length, width + 2.0]), np.column_stack([zero, width + 2.0])], 1)
        self.quads(corners, uv, kind, normal, flags)

    def rods(self, a, b, width, kind, flags=0, ref=(0.0, 0.0, 1.0), crossed=True):
        """Thin members from a to b: two crossed bars `width` wide (one, facing
        across `ref`, unless `crossed`), so they show from any side."""
        a, b = np.atleast_2d(np.asarray(a, np.float64)), np.atleast_2d(np.asarray(b, np.float64))
        if len(a) == 0:
            return
        d = _unit(b - a)
        ref = np.broadcast_to(np.asarray(ref, np.float64), d.shape)
        e1 = ref - (ref * d).sum(1, keepdims=True) * d
        fallback = np.linalg.norm(e1, axis=1) < 1e-3
        e1[fallback] = np.cross(d[fallback], [0.0, 1.0, 0.0])
        e1 = _unit(e1)
        e2 = _unit(np.cross(d, e1))
        self.strips(a, b, e2, width / 2, kind, flags)
        if crossed:
            self.strips(a, b, e1, width / 2, kind, flags)

    def walls(self, st, z0, z1, kind, flags=0):
        """Upright walls along a polyline of local (s, t) points (outward to the
        right of travel, as MeshBuilder.add_walls): uv = (m along, height)."""
        st = np.asarray(st, np.float64)
        self.builder.add_walls(self.f.en(st[:, 0], st[:, 1]), z0, z1, (kind, self.code(flags)))

    def band(self, s, t, z0, z1, side, kind, flags=0):
        """An upright band at t along stations s, from z0 to z1 (per station),
        facing toward side * t: uv = (m along, 0..1 up the band)."""
        s = np.asarray(s, np.float64)
        z0 = np.broadcast_to(np.asarray(z0, np.float64), s.shape)
        z1 = np.broadcast_to(np.asarray(z1, np.float64), s.shape)
        tt = np.full(len(s), float(t))
        p0, p1 = np.column_stack([s, tt, z0]), np.column_stack([s, tt, z1])
        corners = np.stack([p0[:-1], p0[1:], p1[1:], p1[:-1]], 1)
        u = s - s[0]
        uv = np.stack([np.column_stack([u[:-1], np.zeros(len(s) - 1)]), np.column_stack([u[1:], np.zeros(len(s) - 1)]),
                       np.column_stack([u[1:], np.ones(len(s) - 1)]), np.column_stack([u[:-1], np.ones(len(s) - 1)])], 1)
        self.quads(corners, uv, kind, (0.0, float(side), 0.0), flags)

    def surface(self, s, t, z, kind, flags=0, uv="world", down=False, plain=False, t_origin=0.0):
        """A surface over stations s (M,) by t (K,) at heights z (M, K), facing
        up (or down). uv "world" is world x/z (like the ground), "local" (s, t
        - t_origin)."""
        S, T = np.meshgrid(np.asarray(s, np.float64), np.asarray(t, np.float64), indexing="ij")
        P = np.stack([S, T, np.asarray(z, np.float64)], -1)
        corners = np.stack([P[:-1, :-1], P[1:, :-1], P[1:, 1:], P[:-1, 1:]], 2).reshape(-1, 4, 3)
        if uv == "local":
            UV = P[..., :2] - np.array([0.0, t_origin])
        else:
            en = self.f.en(S, T)
            UV = np.stack([en[..., 0], -en[..., 1]], -1)
        UV = np.stack([UV[:-1, :-1], UV[1:, :-1], UV[1:, 1:], UV[:-1, 1:]], 2).reshape(-1, 4, 2)
        self.quads(corners, UV, kind, (0.0, 0.0, -1.0 if down else 1.0), flags, plain)

    def box(self, s, t, hs, ht, z0, z1, kind, flags=0, top=True, bottom=False):
        """An upright box centered on (s, t), half sizes hs, ht."""
        ring = np.array([(s - hs, t - ht), (s + hs, t - ht), (s + hs, t + ht), (s - hs, t + ht), (s - hs, t - ht)])
        self.walls(ring, z0, z1, kind, flags)
        corners = np.column_stack([ring[:4], np.full(4, 0.0)])
        for z, wanted, up in ((z1, top, 1.0), (z0, bottom, -1.0)):
            if wanted:
                corners[:, 2] = z
                en = self.f.en(corners[:, 0], corners[:, 1])
                self.quads(corners.copy(), np.column_stack([en[:, 0], -en[:, 1]]), kind, (0.0, 0.0, up), flags)

    def frustum(self, s, t, hs0, ht0, hs1, ht1, z0, z1, kind, flags=0, top=True):
        """A box narrowing from half sizes (hs0, ht0) at z0 to (hs1, ht1) at z1;
        z1 is a number or per top corner (s-, t-), (s+, t-), (s+, t+), (s-, t+)."""
        signs = np.array([(-1, -1), (1, -1), (1, 1), (-1, 1)], np.float64)
        z1 = np.broadcast_to(np.asarray(z1, np.float64), (4,))
        low = np.column_stack([s + signs[:, 0] * hs0, t + signs[:, 1] * ht0, np.full(4, float(z0))])
        high = np.column_stack([s + signs[:, 0] * hs1, t + signs[:, 1] * ht1, z1])
        for k in range(4):
            j = (k + 1) % 4
            corners = np.array([low[k], low[j], high[j], high[k]])
            edge = corners[1] - corners[0]
            normal = _unit(np.cross(edge, corners[3] - corners[0]))
            out = np.array([corners[:2, 0].mean() - s, corners[:2, 1].mean() - t, 0.0])
            if normal @ out < 0:
                normal = -normal
            width = float(np.linalg.norm(edge))
            uv = np.array([[0.0, z0], [width, z0], [width, corners[2, 2]], [0.0, corners[3, 2]]])
            self.quads(corners, uv, kind, normal, flags)
        if top:
            en = self.f.en(high[:, 0], high[:, 1])
            self.quads(high, np.column_stack([en[:, 0], -en[:, 1]]), kind, (0.0, 0.0, 1.0), flags)

    def plane(self, poly, origin, a_axis, b_axis, normal, kind, flags=0):
        """A flat polygon given in 2-D (a, b), placed at origin + a * a_axis +
        b * b_axis (local 3-D axes); uv = (a, b)."""
        for part in polygons_of(poly, 0.01):
            tris = triangles_of(part)
            if tris is None:
                continue
            pos = (np.asarray(origin, np.float64) + tris[..., 0:1] * np.asarray(a_axis, np.float64)
                   + tris[..., 1:2] * np.asarray(b_axis, np.float64))
            self.tris(pos, tris, kind, normal, flags)

    def reveal(self, path, origin, a_axis, b_axis, depth_axis, d0, d1, kind, flags=0):
        """The inside faces of an opening through a wall: `path` (N, 2) runs in
        the wall's (a, b) plane around the opening with it on the right
        (up its left side, over, down its right), from depth d0 to d1."""
        path = np.asarray(path, np.float64)
        a_axis, b_axis, depth_axis = (np.asarray(x, np.float64) for x in (a_axis, b_axis, depth_axis))

        def at(p, d):
            return np.asarray(origin, np.float64) + p[:, 0:1] * a_axis + p[:, 1:2] * b_axis + d * depth_axis
        p, q = path[:-1], path[1:]
        step = q - p
        keep = np.linalg.norm(step, axis=1) > 1e-4
        p, q, step = p[keep], q[keep], step[keep]
        normal = _unit(step[:, 1:2] * a_axis - step[:, 0:1] * b_axis)  # right of travel: into the opening
        corners = np.stack([at(p, d0), at(q, d0), at(q, d1), at(p, d1)], 1)
        along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(step, axis=1))])
        uv = np.stack([np.column_stack([along[:-1], np.full(len(p), d0)]), np.column_stack([along[1:], np.full(len(p), d0)]),
                       np.column_stack([along[1:], np.full(len(p), d1)]), np.column_stack([along[:-1], np.full(len(p), d1)])], 1)
        self.quads(corners, uv, kind, normal, flags)

    def tube(self, points, radius, kind=STRUCTURE_CABLE, flags=0):
        """A square tube along a polyline of local points (main cables): each
        face's uv runs (m along, 0..1 across), where the shader strings lights."""
        g = self.f.godot(np.asarray(points, np.float64))
        pos, uv, front = [], [], []
        for a, b in zip(g[:-1], g[1:]):
            direction = b - a
            length = float(np.linalg.norm(direction))
            if length < 1e-3:
                continue
            direction /= length
            side = np.cross(direction, [0.0, 1.0, 0.0])
            side = side / np.linalg.norm(side) if np.linalg.norm(side) > 1e-3 else np.array([1.0, 0.0, 0.0])
            up = np.cross(side, direction)
            for normal, tangent in ((side, up), (up, -side), (-side, -up), (-up, side)):
                corner, edge = normal * radius, tangent * radius
                quad = [a + corner - edge, b + corner - edge, b + corner + edge, a + corner + edge]
                pos += [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]
                front += [normal, normal]
                uv += [[[0, 0], [length, 0], [length, 1]], [[0, 0], [length, 1], [0, 1]]]
        if pos:
            self.builder.add(np.array(pos), np.array(uv, np.float64), (kind, self.code(flags)), np.array(front))


def stations(a: float, b: float, step: float, keep=()) -> np.ndarray:
    """Distances from a to b at most `step` apart, with any of `keep` between."""
    n = max(1, int(math.ceil(abs(b - a) / step)))
    s = np.linspace(a, b, n + 1)
    extra = [k for k in keep if min(a, b) < k < max(a, b)]
    return np.unique(np.concatenate([s, extra]))


def arch_path(center: float, width: float, spring: float, bottom: float, pointed: bool, n: int) -> np.ndarray:
    """An arched opening's outline in a wall's (a, b) plane, up its left side
    from `bottom`, over the arch (a semicircle springing at `spring`, or a
    pointed arch of two arcs as wide as the opening), and down its right."""
    h = width / 2
    if pointed:
        left = [(center + h + width * math.cos(a), spring + width * math.sin(a))
                for a in np.linspace(math.pi, math.radians(120.0), n + 1)]
        right = [(center - h + width * math.cos(a), spring + width * math.sin(a))
                 for a in np.linspace(math.radians(60.0), 0.0, n + 1)]
        top = left + right[1:]
    else:
        top = [(center + h * math.cos(a), spring + h * math.sin(a)) for a in np.linspace(math.pi, 0.0, 2 * n + 1)]
    return np.array([(center - h, bottom)] + top + [(center + h, bottom)])


def arch_apex(width: float, spring: float, pointed: bool) -> float:
    return spring + (width * math.sqrt(3.0) / 2 if pointed else width / 2)


def wall_with_arches(m: Mesh, outline, openings, origin, a_axis, b_axis, depth_axis, thickness, kind,
                     flags=0, reveal_flags=0):
    """A wall `thickness` thick (centered on origin along depth_axis) whose face
    is `outline` (a polygon in (a, b)) less the arched `openings` (arch_path
    outlines): both faces and the openings' reveals; the wall's edges are the
    caller's."""
    a_axis, b_axis, depth_axis = (np.asarray(x, np.float64) for x in (a_axis, b_axis, depth_axis))
    holes = [shapely.orient_polygons(Polygon(path)) for path in openings]
    face = shapely.difference(outline, shapely.union_all(holes)) if holes else outline
    for sign in (-1.0, 1.0):
        m.plane(face, np.asarray(origin, np.float64) + depth_axis * (sign * thickness / 2), a_axis, b_axis,
                depth_axis * sign, kind, flags)
    a0, a1 = outline.bounds[0], outline.bounds[2]
    for path in openings:
        # Only the part of the opening inside the wall (openings reach below its foot).
        inside = shapely.intersection(shapely.LineString(path), shapely.buffer(outline, 0.01))
        for piece in lines_of(shapely.line_merge(inside) if inside.geom_type == "MultiLineString" else inside):
            coords = np.asarray(piece.coords)
            if coords[0, 0] > coords[-1, 0] and len(coords) > 1 and abs(coords[0, 0] - coords[-1, 0]) > 1e-6:
                coords = coords[::-1]  # keep the opening on the right
            if np.all((coords[:, 0] <= a0 + 1e-6) | (coords[:, 0] >= a1 - 1e-6)):
                continue
            m.reveal(coords, origin, a_axis, b_axis, depth_axis, -thickness / 2, thickness / 2, kind, reveal_flags)


def _deck_at(site: Site, f: Frame, s, t) -> np.ndarray:
    s, t = np.broadcast_arrays(np.asarray(s, np.float64), np.asarray(t, np.float64))
    return np.asarray(site.deck_y(f.en(s, t).reshape(-1, 2)), np.float64).reshape(s.shape)


def _cable_curve(s, s0, z0, s1, z1, low):
    """A main cable between saddles (s0, z0) and (s1, z1), parabolic, `low` at
    its middle."""
    middle = (s0 + s1) / 2
    k = (np.asarray(s, np.float64) - middle) / ((s1 - s0) / 2)
    return low + ((z0 + z1) / 2 - low) * k * k + (z1 - z0) / 2 * k


def _side_curve(s, s0, z0, s1, z1, sag):
    k = (np.asarray(s, np.float64) - s0) / (s1 - s0)
    return z0 + (z1 - z0) * k - 4.0 * sag * k * (1.0 - k)


def _lamps(f: Frame, s, t, y, toward) -> tuple:
    """Lamp props (positions, heights, arm directions) at local s, t."""
    s = np.asarray(s, np.float64)
    t = np.broadcast_to(np.asarray(t, np.float64), s.shape)
    en = f.en(s, t)
    arms = np.outer(np.broadcast_to(np.asarray(toward, np.float64), s.shape), f.v)
    return en, np.asarray(y, np.float64), arms


# --- Brooklyn Bridge ---

class Brooklyn:
    """Brooklyn Bridge: 1,595.5 ft (486.3 m) main span, 930 ft (283.5 m) side
    spans, 85 ft (25.9 m) wide. Towers 276.5 ft (84.3 m) above high water,
    140 x 59 ft at the water, each with two pointed arches 117 ft (35.7 m)
    high and 33.75 ft (10.3 m) wide over the roadway (119.25 ft up at the
    towers). Four 15.75 in cables, one over each of the four stiffening
    trusses (33 ft deep, the outer ones at the deck's edges, the inner ones
    flanking the promenade); suspenders about every 9 ft, about 400 diagonal
    stays 138-449 ft long fanning from the tower tops. The promenade, 10-17 ft
    wide, runs 18 ft (5.5 m) above the roadways, 4 ft below the crossbeams.
    Anchorages 129 x 119 ft at the base, 117 x 104 ft at the top."""

    HALF = 12.95
    TRUSSES = (2.7, 12.7)
    TRUSS_TOP = 6.7         # above the roadway
    FASCIA = (-3.3, 0.8)    # the floor system's sides, below and just above the roadway
    PANEL = 2.77            # suspenders and truss panels
    PROMENADE = (2.6, 5.5, 0.5)    # half width, height of its top above the roadway, thickness
    PLATFORM = (6.6, 17.0)  # around the towers: half width, half length
    SIDE_SPAN = 283.5
    ANCHORAGE = ((18.15, 19.65), (15.85, 17.85))  # half (along, across) at the base and top
    TOWER_TOP = 84.3
    TOWER_BASE = (9.0, 21.35)
    TOWER = (8.1, 20.75)    # half (along, across) above the roadway
    ARCH_WIDTH = 10.29
    ARCH_HEIGHT = 35.66     # above the roadway
    ARCHES = 8.445          # |t| of the arches' middles (central pier 6.6 m wide)
    CORNICE = (80.0, 81.6)
    CABLE_RADIUS = 0.3
    STAYS = 24
    STAY_REACH = (14.0, 131.0)  # meters from the tower's middle

    def __init__(self, site: Site):
        self.site = site
        t0, t1 = site.towers[0], site.towers[1]
        self.f = Frame((t0 + t1) / 2, t1 - t0)
        half = float(np.linalg.norm(t1 - t0)) / 2
        self.towers = (-half, half)
        self.fronts = (-half - self.SIDE_SPAN, half + self.SIDE_SPAN)
        depth = 2 * self.ANCHORAGE[0][0]
        self.backs = (self.fronts[0] - depth, self.fronts[1] + depth)

    def section(self):
        f = self.f
        parts = [f.rect(self.backs[0], self.backs[1], -self.HALF - 0.5, self.HALF + 0.5)]
        for s in self.towers:
            parts.append(f.rect(s - self.TOWER_BASE[0] - 1.0, s + self.TOWER_BASE[0] + 1.0,
                                -self.TOWER_BASE[1] - 1.0, self.TOWER_BASE[1] + 1.0))
        for a, b in zip(self.fronts, self.backs):
            parts.append(f.rect(min(a, b), max(a, b), -self.ANCHORAGE[0][1] - 1.0, self.ANCHORAGE[0][1] + 1.0))
        return shapely.union_all(parts)

    def deck(self, s, t=0.0):
        return _deck_at(self.site, self.f, s, t)

    def build(self, builders: dict) -> Built:
        built = Built(self.section())
        for level, detail in DETAIL.items():
            m = Mesh(builders[level], self.f, BROOKLYN, detail)
            self._deck(m)
            self._trusses(m)
            self._promenade(m)
            for s in self.towers:
                self._tower(m, s)
            for a, b in zip(self.fronts, self.backs):
                self._anchorage(m, a, b)
            self._cables(m)
        built.post_tops.append(self._lamps())
        return built

    def _deck(self, m: Mesh):
        d = m.detail
        s = stations(self.backs[0], self.backs[1], DECK_STEP[d], self.towers + self.fronts)
        # The roadways between the trusses; under the promenade a plain floor
        # (no traffic: the data's path along the promenade isn't a road).
        inner = self.TRUSSES[0]
        for t, kind in ((np.array([-self.HALF, -inner]), GROUND_ROAD), (np.array([-inner, inner]), STRUCTURE_CONCRETE),
                        (np.array([inner, self.HALF]), GROUND_ROAD)):
            m.surface(s, t, self.deck(s[:, None], t[None, :]), kind, plain=kind == GROUND_ROAD)
        t = np.array([-self.HALF, self.HALF])
        top = self.deck(s[:, None], t[None, :])
        if d < 2:
            m.surface(s, t, top + self.FASCIA[0], STRUCTURE_STEEL, down=True)
        # The floor system's sides: a lattice band along the deck's edges.
        y = self.deck(s)
        for side in (-1.0, 1.0):
            m.band(s, side * self.HALF, y + self.FASCIA[0], y + (self.FASCIA[1] if d == 0 else self.TRUSS_TOP),
                   side, STRUCTURE_STEEL, LATTICE)

    def _suspended(self, step, clear=None):
        """Stations over the suspended spans, leaving out the towers (or
        `clear` meters either side of their middles)."""
        clear = self.TOWER[0] + 0.5 if clear is None else clear
        out = []
        for a, b in ((self.fronts[0], self.towers[0]), (self.towers[0], self.towers[1]), (self.towers[1], self.fronts[1])):
            a2 = a + (clear if a in self.towers else 0.0)
            b2 = b - (clear if b in self.towers else 0.0)
            out.append(stations(a2, b2, step))
        return out

    def _trusses(self, m: Mesh):
        """The stiffening trusses above the roadway: open (chords, posts and
        crossed diagonals) up close, lattice bands further off, and the
        crossbeams over the roadways."""
        d = m.detail
        if d == 2:
            return
        step = self.PANEL * 2 if d == 0 else 24.0
        # The inner trusses stop short of the towers' platforms, so the
        # promenade opens onto them.
        for span, inner_span in zip(self._suspended(step), self._suspended(step, self.PLATFORM[1])):
            for t in (-self.TRUSSES[1], -self.TRUSSES[0], self.TRUSSES[0], self.TRUSSES[1]):
                outer = abs(t) > 5.0
                s = span if outer else inner_span
                y = self.deck(s)
                if d == 1:
                    if not outer:
                        for side in (-1.0, 1.0):
                            m.band(s, t, y, y + self.TRUSS_TOP, side, STRUCTURE_STEEL, LATTICE)
                    continue
                base = y + (self.FASCIA[1] if outer else 0.0)
                tt = np.full(len(s), t)
                top_chord = np.column_stack([s, tt, y + self.TRUSS_TOP - 0.25])
                m.strips(top_chord[:-1], top_chord[1:], (0.0, 0.0, 1.0), 0.25, STRUCTURE_STEEL)
                low_chord = np.column_stack([s, tt, base + 0.2])
                m.strips(low_chord[:-1], low_chord[1:], (0.0, 0.0, 1.0), 0.2, STRUCTURE_STEEL)
                foot = np.column_stack([s, tt, base])
                head = np.column_stack([s, tt, y + self.TRUSS_TOP - 0.5])
                m.strips(foot, head, (1.0, 0.0, 0.0), 0.12, STRUCTURE_STEEL)
                m.strips(foot[:-1], head[1:], (0.0, 1.0, 0.0), 0.06, STRUCTURE_STEEL)
                m.strips(foot[1:], head[:-1], (0.0, 1.0, 0.0), 0.06, STRUCTURE_STEEL)
        if d == 0:
            # Crossbeams over both roadways at every panel point.
            for span in self._suspended(self.PANEL):
                y = self.deck(span)
                for sign in (-1.0, 1.0):
                    a = np.column_stack([span, np.full(len(span), sign * self.TRUSSES[0]), y + self.TRUSS_TOP - 0.3])
                    b = np.column_stack([span, np.full(len(span), sign * self.TRUSSES[1]), y + self.TRUSS_TOP - 0.3])
                    m.strips(a, b, (0.0, 0.0, 1.0), 0.3, STRUCTURE_STEEL)
                    m.strips(a, b, (1.0, 0.0, 0.0), 0.15, STRUCTURE_STEEL)

    def promenade_ends(self):
        """Where the promenade comes down to the roadway: past each
        anchorage, inside the outline."""
        return (self.backs[0] - 110.0, self.backs[1] + 110.0)

    def _promenade_height(self, s):
        """The promenade's top along it: 18 ft over the roadway, coming down
        to it over 90 m at each end."""
        lo, hi = self.promenade_ends()
        ramp = np.clip(np.minimum(np.asarray(s) - lo, hi - np.asarray(s)) / 90.0, 0.0, 1.0)
        ramp = ramp * ramp * (3.0 - 2.0 * ramp)
        return self.deck(s) + self.PROMENADE[1] * ramp

    def _promenade(self, m: Mesh):
        d = m.detail
        half, _, thick = self.PROMENADE
        lo, hi = self.promenade_ends()
        s = stations(lo, hi, DECK_STEP[d], self.towers + self.fronts + self.backs)
        y = self._promenade_height(s)
        t = np.array([-half, half])
        m.surface(s, t, np.repeat(y[:, None], 2, 1), STRUCTURE_WALKWAY, uv="local")
        if d == 2:
            return
        m.surface(s, t, np.repeat(y[:, None] - thick, 2, 1), STRUCTURE_STEEL, down=True)
        for side in (-1.0, 1.0):
            m.band(s, side * half, y - thick, y, side, STRUCTURE_STEEL)
        # Past the trusses, parapets of its own and posts down to the roadway.
        for a, b in ((lo, self.fronts[0]), (self.fronts[1], hi)):
            ss = stations(a, b, DECK_STEP[d])
            yy = self._promenade_height(ss)
            for side in (-1.0, 1.0):
                m.band(ss, side * half, yy, yy + 1.1, side, STRUCTURE_STEEL, LATTICE)
                m.band(ss, side * (half - 0.15), yy, yy + 1.1, -side, STRUCTURE_STEEL, LATTICE)
            if d == 0:
                posts = stations(a, b, 12.0)
                ground = self.deck(posts)
                for p, g, top in zip(posts, ground, self._promenade_height(posts) - thick):
                    if top - g > 1.0:
                        for side in (-1.0, 1.0):
                            m.box(p, side * (half - 0.3), 0.2, 0.2, g, top, STRUCTURE_STEEL, top=False)
        # Platforms around the towers, past the central pier on both sides.
        wide, reach = self.PLATFORM
        for tower in self.towers:
            ss = stations(tower - reach, tower + reach, 4.0 if d == 0 else reach)
            yy = self._promenade_height(ss)
            for sign in (-1.0, 1.0):
                tt = np.array([half, wide]) * sign
                m.surface(ss, np.sort(tt), np.repeat(yy[:, None], 2, 1), STRUCTURE_WALKWAY, uv="local")
                m.surface(ss, np.sort(tt), np.repeat(yy[:, None] - thick, 2, 1), STRUCTURE_STEEL, down=True)
                m.band(ss, sign * wide, yy - thick, yy + 1.1, sign, STRUCTURE_STEEL, LATTICE)
                m.band(ss, sign * (wide - 0.15), yy, yy + 1.1, -sign, STRUCTURE_STEEL, LATTICE)
                for end in (ss[0], ss[-1]):
                    y_end = float(self._promenade_height(np.array([end]))[0])
                    # Facing away from the tower (walls face right of travel).
                    edge = np.array([(end, sign * half), (end, sign * wide)])
                    if sign * (end - tower) < 0:
                        edge = edge[::-1]
                    m.walls(edge, y_end - thick, y_end + 1.1, STRUCTURE_STEEL, LATTICE)

    def _tower(self, m: Mesh, s0: float):
        """A granite tower: the base below the roadway, the arched block with
        its two pointed openings, cornice and attic."""
        d = m.detail
        y = float(self.deck(np.array([s0]))[0])
        hb_s, hb_t = self.TOWER_BASE
        h_s, h_t = self.TOWER
        foot = y - 3.5
        m.box(s0, 0.0, hb_s, hb_t, WATER_FOOTING_Y, foot, STRUCTURE_STONE)
        z1 = self.CORNICE[0]
        apex = y + self.ARCH_HEIGHT
        spring = apex - self.ARCH_WIDTH * math.sqrt(3.0) / 2
        n = (8, 4, 2)[d]
        openings = [arch_path(c, self.ARCH_WIDTH, spring, foot - 1.0, True, n) for c in (-self.ARCHES, self.ARCHES)]
        outline = Polygon([(-h_t, foot), (h_t, foot), (h_t, z1), (-h_t, z1)])
        # The faces lie across the bridge: a = t, b = z, depth along s.
        wall_with_arches(m, outline, openings, (s0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                         2 * h_s, STRUCTURE_STONE, FLOODLIT, FLOODLIT)
        for side in (-1.0, 1.0):
            m.walls(np.array([(s0 + h_s * side, side * h_t), (s0 - h_s * side, side * h_t)]), foot, z1,
                    STRUCTURE_STONE, FLOODLIT)
        m.box(s0, 0.0, h_s + 0.7, h_t + 0.7, self.CORNICE[0], self.CORNICE[1], STRUCTURE_STONE, FLOODLIT, bottom=True)
        m.box(s0, 0.0, h_s - 0.1, h_t - 0.1, self.CORNICE[1], self.TOWER_TOP, STRUCTURE_STONE, FLOODLIT)
        if d < 2:
            # The three piers stand a little proud of the faces up to the
            # cornice (kept clear of the arches' and sides' planes).
            edge = self.ARCHES - self.ARCH_WIDTH / 2
            for t0, t1 in ((-edge + 0.3, edge - 0.3), (self.ARCHES + self.ARCH_WIDTH / 2 + 0.3, h_t - 0.3),
                           (-h_t + 0.3, -self.ARCHES - self.ARCH_WIDTH / 2 - 0.3)):
                m.box(s0, (t0 + t1) / 2, h_s + 0.6, (t1 - t0) / 2, foot, self.CORNICE[0], STRUCTURE_STONE, FLOODLIT,
                      top=False)
        if d == 0:
            # A string course at the springing line across the piers' faces.
            edge = self.ARCH_WIDTH / 2
            for c0, c1 in ((-h_t, -self.ARCHES - edge), (-self.ARCHES + edge, self.ARCHES - edge),
                           (self.ARCHES + edge, h_t)):
                m.box(s0, (c0 + c1) / 2, h_s + 0.85, (c1 - c0) / 2, spring - 0.9, spring, STRUCTURE_STONE, FLOODLIT,
                      bottom=True)

    def _anchorage(self, m: Mesh, front: float, back: float):
        """A limestone anchorage, battered, its top just under the roadway,
        with a parapet along both sides."""
        (bs, bt), (ts, tt) = self.ANCHORAGE
        middle = (front + back) / 2
        corners_s = np.array([middle - ts, middle + ts, middle + ts, middle - ts])
        corners_t = np.array([-tt, -tt, tt, tt])
        tops = self.deck(corners_s, corners_t) - 0.4
        ground = float(np.min(self.site.terrain.height(self.f.en(corners_s, corners_t * bt / tt)))) - 1.0
        m.frustum(middle, 0.0, bs, bt, ts, tt, ground, tops, STRUCTURE_STONE)
        if m.detail < 2:
            for side in (-1.0, 1.0):
                ring = np.array([(middle + ts * side, side * tt), (middle - ts * side, side * tt)])
                y = self.deck(ring[:, 0], ring[:, 1]) - 0.4
                m.walls(ring, y - 2.6, y + 1.2, STRUCTURE_STONE)
                inner = np.array([(middle - ts * side, side * (tt - 0.5)), (middle + ts * side, side * (tt - 0.5))])
                m.walls(inner, y[::-1], y[::-1] + 1.2, STRUCTURE_STONE)

    def saddle(self, s_tower):
        return s_tower, self.TOWER_TOP + 0.3

    def _cables(self, m: Mesh):
        """The four cables, suspenders and diagonal stays."""
        d = m.detail
        (sa, za), (sb, zb) = self.saddle(self.towers[0]), self.saddle(self.towers[1])
        mid_deck = float(self.deck(np.array([0.0]))[0])
        low = mid_deck + self.TRUSS_TOP + 0.6
        main = stations(sa, sb, (6.0, 20.0, 60.0)[d])
        main_z = _cable_curve(main, sa, za, sb, zb, low)
        anchors = []
        for front, back, tower in ((self.fronts[0], self.backs[0], sa), (self.fronts[1], self.backs[1], sb)):
            top = float(self.deck(np.array([front]))[0]) - 0.4
            anchors.append((front + (back - front) * 0.08, top + 0.6, tower))
        for t in (-self.TRUSSES[1], -self.TRUSSES[0], self.TRUSSES[0], self.TRUSSES[1]):
            m.tube(np.column_stack([main, np.full(len(main), t), main_z]), self.CABLE_RADIUS)
            for s_anchor, z_anchor, tower in anchors:
                side = stations(tower, s_anchor, (8.0, 30.0, 90.0)[d])
                m.tube(np.column_stack([side, np.full(len(side), t), _side_curve(side, tower, za, s_anchor, z_anchor,
                                                                                 3.0)]), self.CABLE_RADIUS)
        if d == 2:
            return
        # Suspenders down to the trusses' top chords.
        step = self.PANEL if d == 0 else self.PANEL * 4
        for k, s in enumerate(self._suspended(step)):
            if k == 1:
                z = _cable_curve(s, sa, za, sb, zb, low)
            else:
                s_anchor, z_anchor, tower = anchors[0 if k == 0 else 1]
                z = _side_curve(s, tower, za, s_anchor, z_anchor, 3.0)
            y = self.deck(s) + self.TRUSS_TOP
            keep = z - y > 0.8
            for t in (-self.TRUSSES[1], -self.TRUSSES[0], self.TRUSSES[0], self.TRUSSES[1]):
                tt = np.full(keep.sum(), t)
                m.rods(np.column_stack([s[keep], tt, y[keep]]), np.column_stack([s[keep], tt, z[keep] - self.CABLE_RADIUS]),
                       0.12, STRUCTURE_CABLE, ref=(1.0, 0.0, 0.0), crossed=d == 0)
        # The stays: from the tower tops down to the trusses, both ways.
        reach = np.linspace(self.STAY_REACH[0], self.STAY_REACH[1], self.STAYS if d == 0 else 8)
        for tower in self.towers:
            for direction in (-1.0, 1.0):
                s = tower + direction * reach
                inside = (s > self.fronts[0] + 5.0) & (s < self.fronts[1] - 5.0)
                s = s[inside]
                y = self.deck(s) + self.TRUSS_TOP
                for t in (-self.TRUSSES[1], -self.TRUSSES[0], self.TRUSSES[0], self.TRUSSES[1]):
                    tt = np.full(len(s), t)
                    start = np.column_stack([np.full(len(s), tower + direction * (self.TOWER[0] - 0.2)), tt,
                                             np.full(len(s), self.TOWER_TOP - 2.0)])
                    m.rods(start, np.column_stack([s, tt, y]), 0.12, STRUCTURE_CABLE, ref=(0.0, 1.0, 0.0),
                           crossed=d == 0)

    def _lamps(self):
        """Lanterns along the promenade, staggered, every 30 m."""
        lo, hi = self.promenade_ends()
        s = np.arange(lo + 15.0, hi - 15.0, 30.0)
        s = s[np.all(np.abs(s[:, None] - np.array(self.towers)[None, :]) > self.PLATFORM[1], axis=1)]
        side = np.where(np.arange(len(s)) % 2 == 0, 1.0, -1.0)
        t = side * (self.PROMENADE[0] - 0.4)
        return _lamps(self.f, s, t, self._promenade_height(s), -side)


# --- Manhattan Bridge ---

class Manhattan:
    """Manhattan Bridge: 1,470 ft (448 m) main span, 725 ft (221 m) side
    spans, 120 ft wide. Steel towers 330 ft (100.6 m) to the cable tops, 350
    ft to the finials, of four columns (one under each cable), 5 ft across,
    tapering along the bridge from 32 ft at the pedestals to 10 ft at the top,
    braced diagonally, on masonry piers 23 ft above high water. Four cables
    over four stiffening trusses 24 ft deep, the inner ones 40 ft apart, each
    outer one 28 ft further out (here 2 ft more, for the upper roadways'
    lanes); the upper roadways over the subway tracks (two each side), the
    lower roadway between the inner trusses, the walkway and bikeway outside.
    Anchorages 237 x 182 ft."""

    INNER, OUTER = 6.1, 15.2      # |t| of the trusses, cables and tower columns
    WALK = (15.95, 19.0)          # walkway (south) and bikeway (north)
    LOWER = 6.2                   # the lower level's floor below the upper roadways
    TRUSS = (-7.2, 1.1)           # trusses' bottom and top (parapet) around the upper roadway
    PANEL = 7.5
    SUSPENDERS = 5.0
    SIDE_SPAN = 221.0
    ANCHORAGE = (36.1, 27.75)     # half along, across
    PIER = (10.35, 20.4, 7.0)     # masonry pier: half along, half across, top
    COLUMN = (0.75, 4.9, 1.5)     # half across; half along at the pedestal and at the top
    CABLE_TOP = 100.6
    FINIAL = 106.7
    CABLE_RADIUS = 0.33
    RAMP = 90.0                   # the lower roadway climbs to the anchorages over this

    def __init__(self, site: Site):
        self.site = site
        t0, t1 = site.towers[0], site.towers[1]
        self.f = Frame((t0 + t1) / 2, t1 - t0)
        half = float(np.linalg.norm(t1 - t0)) / 2
        self.towers = (-half, half)
        self.fronts = (-half - self.SIDE_SPAN, half + self.SIDE_SPAN)
        depth = 2 * self.ANCHORAGE[0]
        self.backs = (self.fronts[0] - depth, self.fronts[1] + depth)

    def section(self):
        f = self.f
        parts = [f.rect(self.backs[0], self.backs[1], -self.WALK[1] - 0.5, self.WALK[1] + 0.5)]
        for s in self.towers:
            parts.append(f.rect(s - self.PIER[0] - 1.0, s + self.PIER[0] + 1.0, -self.PIER[1] - 1.0, self.PIER[1] + 1.0))
        for a, b in zip(self.fronts, self.backs):
            parts.append(f.rect(min(a, b), max(a, b), -self.ANCHORAGE[1] - 1.0, self.ANCHORAGE[1] + 1.0))
        return shapely.union_all(parts)

    def deck(self, s, t=0.0):
        return _deck_at(self.site, self.f, s, t)

    def lower(self, s):
        """How far the lower roadway is below the upper ones: LOWER over the
        spans, climbing to 0 at the anchorages."""
        s = np.asarray(s, np.float64)
        k = np.clip(np.minimum(s - self.fronts[0], self.fronts[1] - s) / self.RAMP, 0.0, 1.0)
        return self.LOWER * k * k * (3.0 - 2.0 * k)

    def build(self, builders: dict) -> Built:
        built = Built(self.section())
        for level, detail in DETAIL.items():
            m = Mesh(builders[level], self.f, MANHATTAN, detail)
            self._deck(m)
            self._trusses(m)
            for s in self.towers:
                self._tower(m, s)
            for a, b in zip(self.fronts, self.backs):
                self._anchorage(m, a, b)
            self._cables(m)
        built.cobra_heads.append(self._lamps())
        return built

    def _deck(self, m: Mesh):
        d = m.detail
        s = stations(self.backs[0], self.backs[1], DECK_STEP[d], self.towers + self.fronts)
        span = (s >= self.fronts[0]) & (s <= self.fronts[1])
        y = self.deck(s)
        # Over the anchorages one deck, full width; over the spans the upper
        # roadways, and the lower level between and under them.
        for a, b in ((0, np.flatnonzero(span)[0] + 1), (np.flatnonzero(span)[-1], len(s))):
            ss = s[a:b]
            t = np.array([-self.WALK[1], self.WALK[1]])
            m.surface(ss, t, self.deck(ss[:, None], t[None, :]), GROUND_ROAD, plain=True)
        ss = s[span]
        yy = y[span]
        drop = self.lower(ss)
        for sign in (-1.0, 1.0):
            t = np.sort(sign * np.array([self.INNER, self.OUTER]))
            m.surface(ss, t, self.deck(ss[:, None], t[None, :]), GROUND_ROAD, plain=True)
            if d < 2:
                m.surface(ss, t, self.deck(ss[:, None], t[None, :]) - 0.6, STRUCTURE_STEEL, down=True)
            # Subway tracks under the upper roadway, the walkway outside.
            if d < 2:
                for track in (sign * (self.INNER + 2.55), sign * (self.OUTER - 2.55)):
                    tt = np.array([track - 1.8, track + 1.8])
                    lv = yy - self.LOWER + 0.3
                    m.surface(ss, tt, np.repeat(lv[:, None], 2, 1), STRUCTURE_RAIL, uv="local", t_origin=track)
                walk = np.sort(sign * np.array(self.WALK))
                lv = yy - self.LOWER
                m.surface(ss, walk, np.repeat(lv[:, None], 2, 1), STRUCTURE_WALKWAY, uv="local")
                m.band(ss, sign * self.WALK[1], lv, lv + 1.2, sign, STRUCTURE_STEEL, LATTICE)
                m.band(ss, sign * (self.WALK[1] - 0.1), lv, lv + 1.2, -sign, STRUCTURE_STEEL, LATTICE)
        t = np.array([-self.INNER, self.INNER])
        m.surface(ss, t, self.deck(ss[:, None], t[None, :]) - drop[:, None], GROUND_ROAD, plain=True)
        if d < 2:
            t = np.array([-self.WALK[1], self.WALK[1]])
            m.surface(ss, t, np.repeat((yy - self.LOWER - 1.0)[:, None], 2, 1), STRUCTURE_STEEL, down=True)
        else:
            for sign in (-1.0, 1.0):
                m.band(ss, sign * self.WALK[1], yy - self.LOWER - 1.0, yy + self.TRUSS[1], sign, STRUCTURE_STEEL,
                       LATTICE)
        # The deck's ends over the anchorages: sides down to the masonry.
        for a, b in ((0, np.flatnonzero(span)[0] + 1), (np.flatnonzero(span)[-1], len(s))):
            ss2 = s[a:b]
            y2 = self.deck(ss2)
            for sign in (-1.0, 1.0):
                m.band(ss2, sign * self.WALK[1], y2 - 2.0, y2 + 1.1, sign, STRUCTURE_STONE)

    def _trusses(self, m: Mesh):
        d = m.detail
        if d == 2:
            return
        for k, (a, b) in enumerate(((self.fronts[0], self.towers[0]), (self.towers[0], self.towers[1]),
                                    (self.towers[1], self.fronts[1]))):
            s = stations(a, b, self.PANEL if d == 0 else 30.0)
            y = self.deck(s)
            for t in (-self.OUTER, -self.INNER, self.INNER, self.OUTER):
                bottom, top = y + self.TRUSS[0], y + self.TRUSS[1]
                if d == 1:
                    for side in (-1.0, 1.0):
                        m.band(s, t, bottom, top, side, STRUCTURE_STEEL, LATTICE)
                    continue
                tt = np.full(len(s), t)
                # Chords: the top one is the upper roadway's parapet.
                for side in (-1.0, 1.0):
                    m.band(s, t + side * 0.3, y - 0.2, top, side, STRUCTURE_STEEL)
                    m.band(s, t + side * 0.3, bottom, bottom + 1.0, side, STRUCTURE_STEEL)
                cap = np.column_stack([s, tt, top])
                m.strips(cap[:-1], cap[1:], (0.0, 1.0, 0.0), 0.3, STRUCTURE_STEEL)
                foot = np.column_stack([s, tt, bottom + 1.0])
                head = np.column_stack([s, tt, y - 0.2])
                m.rods(foot, head, 0.5, STRUCTURE_STEEL, ref=(1.0, 0.0, 0.0))
                # Warren diagonals, alternating.
                even = np.arange(len(s) - 1) % 2 == 0
                lo = np.where(even[:, None], foot[:-1], head[:-1])
                hi = np.where(even[:, None], head[1:], foot[1:])
                m.rods(lo, hi, 0.45, STRUCTURE_STEEL, ref=(0.0, 1.0, 0.0))

    def _tower(self, m: Mesh, s0: float):
        """A steel tower: four tapering columns on a masonry pier, X bracing
        between each pair, an arched portal under the top girder and another
        under the deck, finials."""
        d = m.detail
        y = float(self.deck(np.array([s0]))[0])
        ps, pt, ptop = self.PIER
        m.box(s0, 0.0, ps, pt, WATER_FOOTING_Y, ptop, STRUCTURE_STONE)
        across, along0, along1 = self.COLUMN
        columns = (-self.OUTER, -self.INNER, self.INNER, self.OUTER)
        girder = (self.CABLE_TOP - 7.0, self.CABLE_TOP)
        for t in columns:
            m.frustum(s0, t, along0, across, along1, across, ptop, self.CABLE_TOP, STRUCTURE_STEEL, FLOODLIT)
            if d < 2:
                # The finial: a cap and a ball.
                m.box(s0, t, along1 + 0.3, across + 0.3, self.CABLE_TOP, self.CABLE_TOP + 1.5, STRUCTURE_STEEL, FLOODLIT)
                ball = [(self.CABLE_TOP + 1.5, 0.5), (self.CABLE_TOP + 2.5, 1.1), (self.FINIAL - 2.2, 1.1),
                        (self.FINIAL - 1.0, 0.5), (self.FINIAL, 0.05)]
                for (z0, r0), (z1, r1) in zip(ball[:-1], ball[1:]):
                    m.frustum(s0, t, r0, r0, r1, r1, z0, z1, STRUCTURE_STEEL, FLOODLIT, top=False)

        def half_along(z):
            k = (np.asarray(z, np.float64) - ptop) / (self.CABLE_TOP - ptop)
            return along0 + (along1 - along0) * k
        # The top girder across all four columns.
        hg = float(half_along(girder[0])) * 0.6
        m.box(s0, 0.0, hg, self.OUTER + across, girder[0], girder[1], STRUCTURE_STEEL, FLOODLIT, bottom=True)
        # The portals between the inner columns: an arch under the girder,
        # and one under the deck.
        width = 2 * (self.INNER - across)
        for top in (girder[0], y + self.TRUSS[0] - 0.5):
            spring = top - width / 2 - (1.5 if top == girder[0] else 0.0)
            outline = Polygon([(-width / 2, spring - 2.0), (width / 2, spring - 2.0), (width / 2, top), (-width / 2, top)])
            opening = arch_path(0.0, width, spring, spring - 3.0, False, (6, 3, 2)[d])
            wall_with_arches(m, outline, [opening], (s0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                             1.2, STRUCTURE_STEEL, FLOODLIT, FLOODLIT)
        if d == 2:
            return
        # Bracing in the tower's plane: X panels between each pair of columns
        # above the deck and below it, struts between the panels.
        for sign in (-1.0, 1.0):
            t_in, t_out = sign * (self.INNER + across), sign * (self.OUTER - across)
            for z_lo, z_hi, panels in ((y + self.TRUSS[1] + 1.0, girder[0], 3), (ptop + 1.0, y + self.TRUSS[0] - 0.5, 2)):
                levels = np.linspace(z_lo, z_hi, panels + 1)
                for z0, z1 in zip(levels[:-1], levels[1:]):
                    a = np.array([[s0, t_in, z0], [s0, t_out, z0]])
                    b = np.array([[s0, t_out, z1], [s0, t_in, z1]])
                    m.rods(a, b, 0.9, STRUCTURE_STEEL, FLOODLIT, ref=(1.0, 0.0, 0.0), crossed=False)
                for z in levels:
                    m.box(s0, (t_in + t_out) / 2, 0.5, abs(t_out - t_in) / 2, z - 0.6, z + 0.6, STRUCTURE_STEEL,
                          FLOODLIT, bottom=True)
        # The strut under the deck across all columns.
        m.box(s0, 0.0, 1.0, self.OUTER + across, y + self.TRUSS[0] - 1.5, y + self.TRUSS[0] - 0.3, STRUCTURE_STEEL,
              FLOODLIT, bottom=True)

    def _anchorage(self, m: Mesh, front: float, back: float):
        hs, ht = self.ANCHORAGE
        middle = (front + back) / 2
        corners_s = np.array([middle - hs, middle + hs, middle + hs, middle - hs])
        corners_t = np.array([-ht, -ht, ht, ht])
        tops = self.deck(corners_s, np.clip(corners_t, -self.WALK[1], self.WALK[1])) - 0.4
        ground = float(np.min(self.site.terrain.height(self.f.en(corners_s, corners_t)))) - 1.0
        m.frustum(middle, 0.0, hs + 1.2, ht + 1.2, hs, ht, ground, tops, STRUCTURE_STONE)
        if m.detail < 2:
            # A cornice, and parapets along both sides.
            z = tops - 3.0
            m.frustum(middle, 0.0, hs + 0.8, ht + 0.8, hs + 0.8, ht + 0.8, float(z.min()) - 1.2, z, STRUCTURE_STONE)
            for side in (-1.0, 1.0):
                ring = np.array([(middle + hs * side, side * ht), (middle - hs * side, side * ht)])
                y = self.deck(ring[:, 0], np.clip(ring[:, 1], -self.WALK[1], self.WALK[1])) - 0.4
                m.walls(ring, y - 0.1, y + 1.4, STRUCTURE_STONE)

    def _cables(self, m: Mesh):
        d = m.detail
        sa, sb = self.towers
        z_top = self.CABLE_TOP + 0.4
        low = float(self.deck(np.array([0.0]))[0]) + self.TRUSS[1] + 1.2
        main = stations(sa, sb, (6.0, 20.0, 60.0)[d])
        main_z = _cable_curve(main, sa, z_top, sb, z_top, low)
        anchors = []
        for front, tower in ((self.fronts[0], sa), (self.fronts[1], sb)):
            anchors.append((front + np.sign(front) * 4.0, float(self.deck(np.array([front]))[0]) + 0.6, tower))
        columns = (-self.OUTER, -self.INNER, self.INNER, self.OUTER)
        for t in columns:
            m.tube(np.column_stack([main, np.full(len(main), t), main_z]), self.CABLE_RADIUS)
            for s_anchor, z_anchor, tower in anchors:
                side = stations(tower, s_anchor, (8.0, 30.0, 90.0)[d])
                m.tube(np.column_stack([side, np.full(len(side), t), _side_curve(side, tower, z_top, s_anchor, z_anchor,
                                                                                 4.0)]), self.CABLE_RADIUS)
        if d == 2:
            return
        step = self.SUSPENDERS if d == 0 else self.SUSPENDERS * 4
        clear = self.COLUMN[1] + 0.5
        for k, (a, b) in enumerate(((self.fronts[0] + 2.0, sa - clear), (sa + clear, sb - clear), (sb + clear, self.fronts[1] - 2.0))):
            s = stations(a, b, step)
            if k == 1:
                z = _cable_curve(s, sa, z_top, sb, z_top, low)
            else:
                s_anchor, z_anchor, tower = anchors[0 if k == 0 else 1]
                z = _side_curve(s, tower, z_top, s_anchor, z_anchor, 4.0)
            y = self.deck(s) + self.TRUSS[1]
            keep = z - y > 0.8
            for t in columns:
                tt = np.full(keep.sum(), t)
                m.rods(np.column_stack([s[keep], tt, y[keep]]), np.column_stack([s[keep], tt, z[keep] - self.CABLE_RADIUS]),
                       0.15, STRUCTURE_CABLE, ref=(1.0, 0.0, 0.0), crossed=d == 0)

    def _lamps(self):
        """Cobra-heads along the upper roadways' outer edges, every 30 m."""
        s = np.arange(self.fronts[0] + 15.0, self.fronts[1] - 15.0, 30.0)
        s = s[np.all(np.abs(s[:, None] - np.array(self.towers)[None, :]) > 8.0, axis=1)]
        en, y, arms = [], [], []
        for sign in (-1.0, 1.0):
            e, h, a = _lamps(self.f, s, sign * (self.OUTER - 0.7), self.deck(s), -sign)
            en.append(e), y.append(h), arms.append(a)
        return np.concatenate(en), np.concatenate(y), np.concatenate(arms)


# --- Hell Gate Bridge ---

class HellGate:
    """Hell Gate Bridge: a two-hinged steel arch, 977.5 ft clear between the
    towers (hinges at their feet), its upper chord 305 ft (93 m) above high
    water at the crown, the chords 140 ft (43 m) apart at the ends and 40 ft
    at mid-river; the deck 60 ft (18.3 m) wide, 135 ft clear over the water
    (145 ft to its top), hung from the lower chord over the middle and on
    posts toward the ends; four tracks. Towers 220 ft (67 m) tall, 104 x 140
    ft, granite over concrete. Painted Hell Gate Red."""

    TOWER = (16.0, 21.5, 67.1)   # half along, half across, height
    ARCH_T = 12.5                # |t| of the arch trusses
    DECK_HALF = 9.15
    TRACKS = (-6.0, -2.0, 2.0, 6.0)
    CROWN = 93.0
    CHORDS = (42.7, 12.2)        # chords' spacing at the ends and the crown
    PANELS = 23
    PASSAGE = (11.0, 16.0)       # the towers' arched passage: half width, apex above the deck

    def __init__(self, site: Site):
        self.site = site
        t0, t1 = site.towers[0], site.towers[1]
        self.f = Frame((t0 + t1) / 2, t1 - t0)
        half = float(np.linalg.norm(t1 - t0)) / 2
        self.towers = (-half, half)
        self.hinge = half - self.TOWER[0]
        self.ground = [float(site.terrain.height(self.f.en(np.array([s]), np.array([0.0])))[0]) for s in self.towers]

    def section(self):
        hs, ht, _ = self.TOWER
        f = self.f
        parts = [f.rect(self.towers[0] - hs, self.towers[1] + hs, -self.ARCH_T - 1.5, self.ARCH_T + 1.5)]
        for s in self.towers:
            parts.append(f.rect(s - hs - 0.5, s + hs + 0.5, -ht - 0.5, ht + 0.5))
        return shapely.union_all(parts)

    def deck(self, s, t=0.0):
        return _deck_at(self.site, self.f, s, t)

    def lower_chord(self, s):
        k = 1.0 - (np.asarray(s, np.float64) / self.hinge) ** 2
        z0 = max(self.ground) + 1.5
        return z0 + (self.CROWN - self.CHORDS[1] - z0) * np.clip(k, 0.0, 1.0) ** 0.85

    def upper_chord(self, s):
        k = np.clip(1.0 - (np.asarray(s, np.float64) / self.hinge) ** 2, 0.0, 1.0)
        z0 = max(self.ground) + 1.5 + self.CHORDS[0]
        return z0 + (self.CROWN - z0) * (1.0 - (1.0 - k) ** 1.6)

    def build(self, builders: dict) -> Built:
        built = Built(self.section())
        for level, detail in DETAIL.items():
            m = Mesh(builders[level], self.f, HELL_GATE, detail)
            self._deck(m)
            self._arch(m)
            for s, ground in zip(self.towers, self.ground):
                self._tower(m, s, ground)
        return built

    def _deck(self, m: Mesh):
        d = m.detail
        hs = self.TOWER[0]
        s = stations(self.towers[0] - hs, self.towers[1] + hs, DECK_STEP[d], self.towers)
        y = self.deck(s)
        t = np.array([-self.DECK_HALF, self.DECK_HALF])
        m.surface(s, t, self.deck(s[:, None], t[None, :]), STRUCTURE_CONCRETE, plain=True)
        for track in self.TRACKS if d < 2 else ():
            tt = np.array([track - 1.8, track + 1.8])
            m.surface(s, tt, np.repeat((y + 0.3)[:, None], 2, 1), STRUCTURE_RAIL, uv="local", t_origin=track)
        if d < 2:
            m.surface(s, t, np.repeat((y - 2.5)[:, None], 2, 1), STRUCTURE_STEEL, down=True)
        for side in (-1.0, 1.0):
            m.band(s, side * self.DECK_HALF, y - 2.5, y + 0.9, side, STRUCTURE_STEEL)
            if d < 2:
                m.band(s, side * (self.DECK_HALF - 0.2), y, y + 0.9, -side, STRUCTURE_STEEL)

    def _arch(self, m: Mesh):
        d = m.detail
        panels = self.PANELS if d == 0 else (self.PANELS + 1) // 2 if d == 1 else 6
        s = np.linspace(-self.hinge, self.hinge, panels + 1)
        fine = np.linspace(-self.hinge, self.hinge, (64, 32, 12)[d] + 1)
        y_deck = self.deck(s)
        for t in (-self.ARCH_T, self.ARCH_T):
            # The chords: box sections, the lower one deeper.
            for curve, depth, half in ((self.lower_chord, 3.0, 1.2), (self.upper_chord, 2.0, 0.9)):
                z = curve(fine)
                for side in (-1.0, 1.0):
                    m.band(fine, t + side * half, z - depth / 2, z + depth / 2, side, STRUCTURE_STEEL)
                pts_lo = np.column_stack([fine, np.full(len(fine), t), z - depth / 2])
                pts_hi = np.column_stack([fine, np.full(len(fine), t), z + depth / 2])
                m.strips(pts_hi[:-1], pts_hi[1:], (0.0, 1.0, 0.0), half, STRUCTURE_STEEL)
                m.strips(pts_lo[:-1], pts_lo[1:], (0.0, 1.0, 0.0), half, STRUCTURE_STEEL)
            low, high = self.lower_chord(s), self.upper_chord(s)
            tt = np.full(len(s), t)
            width = (1.0, 1.4, 2.0)[d]
            # Verticals between the chords, and N-truss diagonals toward the crown.
            m.rods(np.column_stack([s, tt, low]), np.column_stack([s, tt, high]), width, STRUCTURE_STEEL,
                   ref=(1.0, 0.0, 0.0), crossed=d == 0)
            if d < 2:
                outer = np.abs(s[:-1]) > np.abs(s[1:])
                a = np.where(outer[:, None], np.column_stack([s[:-1], tt[:-1], low[:-1]]), np.column_stack([s[:-1], tt[:-1], high[:-1]]))
                b = np.where(outer[:, None], np.column_stack([s[1:], tt[1:], high[1:]]), np.column_stack([s[1:], tt[1:], low[1:]]))
                m.rods(a, b, width * 0.8, STRUCTURE_STEEL, ref=(0.0, 1.0, 0.0), crossed=d == 0)
            # Hangers down to the deck where the lower chord is above it, posts
            # up to it where it's below.
            above = low - 1.5 > y_deck
            m.rods(np.column_stack([s[above], tt[above], y_deck[above] - 1.0]),
                   np.column_stack([s[above], tt[above], low[above] - 1.5]), 0.5, STRUCTURE_STEEL,
                   ref=(1.0, 0.0, 0.0), crossed=d == 0)
            below = low + 1.5 < y_deck - 2.5
            m.rods(np.column_stack([s[below], tt[below], low[below] + 1.5]),
                   np.column_stack([s[below], np.full(below.sum(), t), y_deck[below] - 2.5]), width, STRUCTURE_STEEL,
                   ref=(1.0, 0.0, 0.0), crossed=d == 0)
        if d == 2:
            return
        # Floor beams out to the arches, and bracing between the arches' tops.
        tt0, tt1 = np.full(len(s), -self.ARCH_T), np.full(len(s), self.ARCH_T)
        m.strips(np.column_stack([s, tt0, y_deck - 1.6]), np.column_stack([s, tt1, y_deck - 1.6]), (0.0, 0.0, 1.0), 0.8,
                 STRUCTURE_STEEL)
        high = self.upper_chord(s)
        clear = high - 1.0 > y_deck + 9.0
        m.strips(np.column_stack([s[clear], tt0[clear], high[clear] - 1.0]),
                 np.column_stack([s[clear], tt1[clear], high[clear] - 1.0]), (1.0, 0.0, 0.0), 0.6, STRUCTURE_STEEL)
        if d == 0:
            both = clear[:-1] & clear[1:]
            a = np.column_stack([s[:-1], tt0[:-1], high[:-1] - 1.0])[both]
            b = np.column_stack([s[1:], tt1[1:], high[1:] - 1.0])[both]
            c = np.column_stack([s[:-1], tt1[:-1], high[:-1] - 1.0])[both]
            e = np.column_stack([s[1:], tt0[1:], high[1:] - 1.0])[both]
            m.strips(a, b, (0.0, 0.0, 1.0), 0.3, STRUCTURE_STEEL)
            m.strips(c, e, (0.0, 0.0, 1.0), 0.3, STRUCTURE_STEEL)

    def _tower(self, m: Mesh, s0: float, ground: float):
        """A granite tower with an arched passage for the tracks, a cornice
        and an attic."""
        d = m.detail
        hs, ht, height = self.TOWER
        y = float(self.deck(np.array([s0]))[0])
        foot = ground - 2.0
        cornice = height - 7.0
        half, apex = self.PASSAGE
        spring = y + apex - half
        outline = Polygon([(-ht, foot), (ht, foot), (ht, cornice), (-ht, cornice)])
        opening = arch_path(0.0, 2 * half, spring, y - 3.5, False, (8, 4, 2)[d])
        # The passage starts at the deck: below it the tower is solid.
        wall_with_arches(m, outline, [opening], (s0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                         2 * hs, STRUCTURE_STONE)
        m.box(s0, 0.0, hs - 0.5, half, foot, y - 3.5, STRUCTURE_STONE)
        for side in (-1.0, 1.0):
            m.walls(np.array([(s0 + hs * side, side * ht), (s0 - hs * side, side * ht)]), foot, cornice, STRUCTURE_STONE)
        m.box(s0, 0.0, hs + 0.8, ht + 0.8, cornice, cornice + 1.8, STRUCTURE_STONE, bottom=True)
        m.box(s0, 0.0, hs - 1.0, ht - 1.0, cornice + 1.8, height, STRUCTURE_STONE)
        if d == 0:
            # Pilasters on the faces along the bridge, either side of the passage.
            for side in (-1.0, 1.0):
                for c in (side * (half + 3.0), side * (ht - 2.5)):
                    m.box(s0, c, hs + 0.4, 1.4, foot, cornice, STRUCTURE_STONE, top=False)


# --- High Bridge ---

class HighBridge:
    """High Bridge: the Croton Aqueduct's bridge over the Harlem River, 1,450 ft
    (440 m) long, about 140 ft (42.7 m) above the river. Of its 15 granite
    arches (eight 80 ft, seven 50 ft, springing 84 ft above high water, on
    piers 20 x 40 ft at the ground), five over the river were replaced in
    1928 by one steel arch about 450 ft across. The walkway on top is brick,
    between brick and granite parapets, lit by Victorian lampposts."""

    TOP = 42.5
    HALF = 3.95          # the outline's width
    PARAPET = 1.2
    SPRING = 25.6
    WIDE, NARROW = 24.4, 15.2
    PIER = (3.05, 6.1)   # half along, half across
    ARCH_PIER = (5.0, 6.5)
    # Arches from the steel arch's piers outward: the Manhattan side's wide
    # arch below the bluff, then the Bronx side's.
    MANHATTAN_BAYS = (24.4,)
    BRONX_BAYS = (24.4, 24.4, 15.2, 15.2, 15.2, 15.2, 15.2, 15.2, 15.2)
    STEEL_SPRING = 12.0
    RIBS = 2.6           # |t| of the steel arch's ribs
    REACH = 80.0         # how far past the outline's ends the bridge may go to meet the bluffs

    def __init__(self, site: Site):
        self.site = site
        t0, t1 = site.towers[0], site.towers[1]
        self.f = Frame((t0 + t1) / 2, t1 - t0)
        self.piers = (-float(np.linalg.norm(t1 - t0)) / 2, float(np.linalg.norm(t1 - t0)) / 2)
        ring = np.asarray(site.poly.exterior.coords)[:, :2]
        along = self.f.along(ring)
        # The walkway is level from bluff to bluff; the outline stops short of
        # where our (10 m) terrain comes up to it.
        ends = []
        for end, sign in ((float(along.min()), -1.0), (float(along.max()), 1.0)):
            reach = end + sign * np.arange(0.0, self.REACH, 2.0)
            high = np.flatnonzero(self.ground(reach) >= self.TOP - 0.3)
            ends.append(float(reach[high[0]]) if len(high) else end)
        self.ends = tuple(ends)

    def section(self):
        return shapely.union_all([shapely.buffer(self.site.poly, 2.0),
                                  self.f.rect(self.ends[0], self.ends[1], -self.HALF - 2.0, self.HALF + 2.0)])

    def ground(self, s):
        s = np.asarray(s, np.float64)
        return np.asarray(self.site.terrain.height(self.f.en(s, np.zeros_like(s))), np.float64)

    def bays(self):
        """The stone arches: (start, end) in s, each between two piers."""
        out = []
        for sign, bays in ((-1.0, self.MANHATTAN_BAYS), (1.0, self.BRONX_BAYS)):
            at = sign * (abs(self.piers[0 if sign < 0 else 1]) + self.ARCH_PIER[0])
            for width in bays:
                start, end = at, at + sign * width
                if sign * end > sign * self.ends[0 if sign < 0 else 1] - 2.0:
                    break
                if float(self.ground(np.array([end]))[0]) > self.SPRING + width / 2 - 1.0:
                    break  # the land has come up to the arches
                out.append((min(start, end), max(start, end)))
                at = end + sign * 2 * self.PIER[0]
        return out

    def build(self, builders: dict) -> Built:
        built = Built(self.section())
        for level, detail in DETAIL.items():
            m = Mesh(builders[level], self.f, HIGH_BRIDGE, detail)
            self._walls(m)
            self._steel(m)
        built.post_tops.append(self._lamps())
        return built

    def _walls(self, m: Mesh):
        """The masonry: the spandrel walls with their arches from end to end
        (open between the steel arch's piers), piers, the walkway and parapets."""
        d = m.detail
        lo, hi = self.ends
        bays = self.bays()
        s = stations(lo, hi, (5.0, 10.0, 25.0)[d])
        base = np.minimum(self.ground(s), self.TOP) - 3.0
        gap = (self.piers[0] + self.ARCH_PIER[0], self.piers[1] - self.ARCH_PIER[0])
        top = self.TOP + (self.PARAPET if d < 2 else 0.0)
        for a, b in ((lo, gap[0]), (gap[1], hi)):
            keep = (s > a) & (s < b)
            ss = np.concatenate([[a], s[keep], [b]])
            bb = np.minimum(np.interp(ss, s, base), self.TOP - 3.0)
            outline = Polygon(list(zip(ss, bb)) + [(b, top), (a, top)])
            openings = [arch_path((x0 + x1) / 2, x1 - x0, self.SPRING, -50.0, False, (6, 3, 2)[d])
                        for x0, x1 in bays if a <= x0 and x1 <= b]
            wall_with_arches(m, outline, openings, (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                             2 * self.HALF, STRUCTURE_STONE, reveal_flags=FLOODLIT)
            for x, end in ((a, a == lo), (b, b == hi)):
                if end:
                    m.walls(np.array([(x, self.HALF), (x, -self.HALF)])[::(1 if x == lo else -1)],
                            float(np.interp(x, s, base)), top, STRUCTURE_STONE)
        # Piers between the arches: wider than the walls, up to the springing.
        if d < 2:
            edges = sorted({round(x, 3) for bay in bays for x in bay})
            for x0, x1 in zip(edges[:-1], edges[1:]):
                if any(abs(x0 - a) < 1e-3 and abs(x1 - b) < 1e-3 for a, b in bays):
                    continue  # an arch, not a pier
                middle = (x0 + x1) / 2
                if x1 - x0 > 2 * self.PIER[0] + 0.5:
                    continue
                g = float(np.min(self.ground(np.array([x0, x1])))) - 2.0
                m.frustum(middle, 0.0, self.PIER[0] + 0.4, self.PIER[1], self.PIER[0], self.PIER[1] - 1.2, g,
                          self.SPRING - 1.0, STRUCTURE_STONE)
                m.frustum(middle, 0.0, self.PIER[0], self.PIER[1] - 1.2, 0.2, self.HALF, self.SPRING - 1.0,
                          self.SPRING + 2.0, STRUCTURE_STONE, top=False)
        # The steel arch's piers.
        for p in self.piers:
            g = float(self.ground(np.array([p]))[0]) - 2.0
            m.frustum(p, 0.0, self.ARCH_PIER[0] + 0.6, self.ARCH_PIER[1] + 0.6, self.ARCH_PIER[0], self.ARCH_PIER[1],
                      g, self.TOP - 1.5, STRUCTURE_STONE, top=False)
            m.box(p, 0.0, self.ARCH_PIER[0] + 0.3, self.ARCH_PIER[1] + 0.3, self.TOP - 1.5, top, STRUCTURE_STONE,
                  bottom=True)
        # The walkway, and the parapets' inner faces and copings.
        s = stations(lo, hi, DECK_STEP[d])
        t = np.array([-self.HALF, self.HALF])
        m.surface(s, t, np.full((len(s), 2), self.TOP), STRUCTURE_WALKWAY, uv="local")
        if d < 2:
            for side in (-1.0, 1.0):
                m.band(s, side * (self.HALF - 0.45), np.full(len(s), self.TOP), np.full(len(s), top), -side,
                       STRUCTURE_STONE)
                m.surface(s, np.sort(side * np.array([self.HALF - 0.45, self.HALF])), np.full((len(s), 2), top),
                          STRUCTURE_STONE)

    def _steel(self, m: Mesh):
        """The steel arch: two ribs springing from the piers, posts up to the
        deck between them, cross bracing, the deck's girders."""
        d = m.detail
        a, b = self.piers[0] + self.ARCH_PIER[0], self.piers[1] - self.ARCH_PIER[0]
        half = (b - a) / 2
        middle = (a + b) / 2
        crown = self.TOP - 4.5
        fine = np.linspace(a, b, (40, 20, 10)[d] + 1)
        k = 1.0 - ((fine - middle) / half) ** 2
        rib = self.STEEL_SPRING + (crown - self.STEEL_SPRING) * k
        for t in (-self.RIBS, self.RIBS):
            for side in (-1.0, 1.0):
                m.band(fine, t + side * 0.75, rib - 1.5, rib + 1.5, side, STRUCTURE_STEEL)
            for z in (rib - 1.5, rib + 1.5):
                pts = np.column_stack([fine, np.full(len(fine), t), z])
                m.strips(pts[:-1], pts[1:], (0.0, 1.0, 0.0), 0.75, STRUCTURE_STEEL)
        # The deck over the arch: girders and an underside (the walkway on top
        # is the masonry's, end to end).
        s = stations(a, b, DECK_STEP[d])
        for side in (-1.0, 1.0):
            m.band(s, side * self.HALF, np.full(len(s), self.TOP - 1.6), np.full(len(s), self.TOP + self.PARAPET),
                   side, STRUCTURE_STEEL, LATTICE if d == 0 else 0)
        if d < 2:
            m.surface(s, np.array([-self.HALF, self.HALF]), np.full((len(s), 2), self.TOP - 1.6), STRUCTURE_STEEL,
                      down=True)
        if d == 2:
            return
        posts = np.linspace(a, b, 21)[1:-1]
        kp = 1.0 - ((posts - middle) / half) ** 2
        z_rib = self.STEEL_SPRING + (crown - self.STEEL_SPRING) * kp + 1.5
        keep = self.TOP - 1.6 - z_rib > 0.5
        for t in (-self.RIBS, self.RIBS):
            tt = np.full(keep.sum(), t)
            m.rods(np.column_stack([posts[keep], tt, z_rib[keep]]),
                   np.column_stack([posts[keep], tt, np.full(keep.sum(), self.TOP - 1.6)]), 0.7, STRUCTURE_STEEL,
                   ref=(1.0, 0.0, 0.0), crossed=d == 0)
        # Struts between the ribs.
        struts = np.linspace(a, b, 11)
        ks = 1.0 - ((struts - middle) / half) ** 2
        zs = self.STEEL_SPRING + (crown - self.STEEL_SPRING) * ks
        m.strips(np.column_stack([struts, np.full(len(struts), -self.RIBS), zs]),
                 np.column_stack([struts, np.full(len(struts), self.RIBS), zs]), (1.0, 0.0, 0.0), 0.6, STRUCTURE_STEEL)

    def _lamps(self):
        lo, hi = self.ends
        s = np.arange(lo + 12.0, hi - 12.0, 24.0)
        side = np.where(np.arange(len(s)) % 2 == 0, 1.0, -1.0)
        return _lamps(self.f, s, side * (self.HALF - 0.8), np.full(len(s), self.TOP), -side)


BRIDGES = {"Brooklyn Bridge": Brooklyn, "Manhatten Bridge": Manhattan, "Hellgate Bridge": HellGate,
           "High Bridge/Aqueduct Bridge": HighBridge}
