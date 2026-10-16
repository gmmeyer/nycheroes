"""Sky light: how much of the sky the city's surfaces see (reference round
3's 21). The ground and the walls' feet down narrow, tall streets, and the
ground under el decks and bridge approaches, see less of the sky, so their
shade is deeper. Worked out per vertex as a tile is built (build_tiles.py),
from the buildings' heights and the decks around it, and baked into the
tiles:
  buildings' walls (not roofs, landmarks' faces or parapets' inner sides):
      uv2.y += 64 * (blocked + 16 * reach): `blocked` 0..15 the share of the
      sky a wall's foot doesn't see (15ths), `reach` 1..7 how far up the wall
      that share fades away (CANYON_TOPS, meters above the building's base);
      0 where nothing is baked (the shader's own canyon_occlusion then). The
      building's seed stays in 1024ths and its floor height (dm) under 64.
  the ground and the street paint (flat faces): uv2.x += (1 + blocked) / 40
      (blocked 0..15 in 15ths; the kind is still uv2.x rounded; 0 where
      nothing is baked: the structures, older tiles).
The shaders turn the share into ambient light (toon.gdshaderinc's
sky_light), applied once in the shared lighting path: the sun and its
shadows are left alone.

A surface's view of the sky is measured along rays (GROUND_AZIMUTHS around
flat ground, WALL_AZIMUTHS across the half in front of a wall) stepping out
over a height field of the ground, the buildings' tops and the decks' tops
(SETTINGS); the highest thing along each ray hides the sky below it. Under
a deck the sky shows only between that and the deck's edge (and DECK_SEEN
of what the deck hides). The share is cosine weighted (a wall sees the sky
in front of it best, the ground the sky overhead), and a wall's own
building isn't in its way.
"""

import numpy as np
import shapely
from PIL import Image, ImageDraw

import overpasses
import towers
from common import polygons_of

# Per level: the height field's cell (m), how far around the tile it reaches
# (m), and how far out the rays step (m).
_STEPS = np.array([1.5, 2.5, 3.5, 5.0, 7.0, 9.5, 12.5, 16.0, 21.0, 27.0, 35.0, 45.0, 58.0, 75.0, 95.0, 120.0])
SETTINGS = {
    "lod0": (1.5, 125.0, _STEPS),
    "lod1": (3.0, 190.0, _STEPS[1:] * 1.5),
    "lod2": (6.0, 370.0, _STEPS[3:] * 3.0),
}
GROUND_AZIMUTHS = 12
WALL_AZIMUTHS = 8          # over the half in front of the wall
# Heights above a wall's base (m) where its view is measured; the first is
# its foot. The share fades away by the height where it's down to
# FADE_LEFT of the foot's.
WALL_HEIGHTS = np.array([1.5, 6.0, 12.0, 24.0, 48.0, 96.0, 192.0])
FADE_LEFT = 0.15
# How high a street canyon reaches up a wall, by `reach` 1..7 (the shader
# has the same: CANYON_TOP * exp2((reach - 1) * CANYON_STEP)).
CANYON_TOP = 8.0
CANYON_STEP = 0.68
CANYON_TOPS = CANYON_TOP * np.exp2(np.arange(7) * CANYON_STEP)
# Decks closer than this above a point (m) don't cover it; a deck is this
# thick (its underside is this far below its top). Under a deck, the sky it
# hides still counts this much: light comes through the els' open steel and
# off the decks' undersides.
DECK_CLEAR = 1.0
DECK_THICKNESS = overpasses.DECK_THICKNESS
DECK_SEEN = 0.5
GROUND_SCALE = 40.0
LEVELS_OF_SHARE = 15
# Building faces' flags (facades.py), and the first landmark material.
_FLAG_SCALE, _ROOF, _PARAPET_INSIDE, _LANDMARKS = 64, 1, 128, 16
CHUNK = 6000


class Sky:
    """The height field around one tile (see the module's docstring): `w` is
    build_tiles' worker data, `bounds` the tile's box."""

    def __init__(self, level: str, bounds, w: dict):
        self.cell, margin, self.steps = SETTINGS[level]
        min_e, min_n, max_e, max_n = bounds.bounds
        self.e0, self.n0 = min_e - margin, min_n - margin
        self.nx = int(np.ceil((max_e - min_e + 2 * margin) / self.cell))
        self.ny = int(np.ceil((max_n - min_n + 2 * margin) / self.cell))
        ix, iy = np.meshgrid(np.arange(self.nx), np.arange(self.ny))
        centers = np.column_stack([self.e0 + (ix.ravel() + 0.5) * self.cell, self.n0 + (iy.ravel() + 0.5) * self.cell])
        ground = overpasses.bare(w["ground"][level]).height(centers)
        # The buildings around, drawn lowest first, so each cell keeps the
        # tallest one over it.
        b = w["b"]
        area = shapely.box(self.e0, self.n0, self.e0 + self.nx * self.cell, self.n0 + self.ny * self.cell)
        near = w["building_tree"].query(area)
        heights = towers.heights(b["bin"][near], b["height"][near])
        parts = [(polygon, k) for k in near[np.argsort(heights)] for polygon in polygons_of(b["geoms"][k], 0.0)]
        self.owner = self._raster([p for p, _ in parts], np.array([k for _, k in parts], dtype=np.int64))
        self.top = ground.astype(np.float32)
        built = self.owner >= 0
        lookup = np.argsort(near)
        self.top[built] += heights[lookup[np.searchsorted(near, self.owner[built], sorter=lookup)]]
        # Decks overhead: their tops are in the way like anything else, and
        # points under one see the sky only past its edge.
        self.solid = self.top.copy()
        self.deck_under = np.full(len(centers), -np.inf, dtype=np.float32)
        surface = overpasses.surface_for(w["bridges"][level], bounds, overpasses.OVERHEAD)
        if surface.tree is not None:
            order = np.argsort(surface.tris[:, :, 1].max(axis=1))
            tri = self._raster((shapely.Polygon(t) for t in surface.flat[order]), order)
            cell = np.flatnonzero(tri >= 0)
            y = surface.interpolate(centers[cell], tri[cell]).astype(np.float32)
            np.maximum.at(self.solid, cell, y)
            self.deck_under[cell] = y - DECK_THICKNESS

    def _raster(self, polygons, values: np.ndarray) -> np.ndarray:
        """The value (whole numbers, -1 where none) of the last of the
        polygons (east/north) over each cell's middle."""
        image = Image.new("I", (self.nx, self.ny), -1)
        draw = ImageDraw.Draw(image)
        origin = np.array([self.e0, self.n0])
        for polygon, value in zip(polygons, values.tolist()):
            draw.polygon([tuple(p) for p in (np.asarray(polygon.exterior.coords) - origin) / self.cell],
                         fill=int(value))
            for hole in polygon.interiors:
                draw.polygon([tuple(p) for p in (np.asarray(hole.coords) - origin) / self.cell], fill=-1)
        return np.asarray(image, dtype=np.int32).ravel()

    def _index(self, en: np.ndarray) -> np.ndarray:
        i = np.clip(((en[..., 0] - self.e0) / self.cell).astype(np.int64), 0, self.nx - 1)
        j = np.clip(((en[..., 1] - self.n0) / self.cell).astype(np.int64), 0, self.ny - 1)
        return j * self.nx + i

    def _rays(self, en, directions, own=None):
        """The cells along each point's rays (N points, A directions (N, A, 2)
        or (A, 2), S steps) and under the point itself, for _view(); cells of
        the building `own` (N,) are left out of the way (-1)."""
        cells = self._index(en[:, None, None, :] + np.asarray(directions)[..., None, :] * self.steps[:, None])
        if own is not None:
            cells = np.where((self.owner[cells] == own[:, None, None]) & (own[:, None, None] >= 0), -1, cells)
        return cells, self._index(en)

    def _view(self, cells, here, z):
        """Along rays from _rays(), seen from height z (N,): the tangent of
        the highest thing's elevation (N, A) and, for points under a deck,
        the tangent of the deck's edge where each ray leaves it (N, A; inf
        where the point isn't under one)."""
        d = self.steps
        under = self.deck_under[here] > z + DECK_CLEAR
        height = np.where(under[:, None, None], self.top[cells], self.solid[cells])
        height[cells < 0] = -np.inf
        rise = ((height - z[:, None, None]) / d).max(axis=2)
        edge = np.full(rise.shape, np.inf)
        if under.any():
            covered = self.deck_under[cells[under]] > z[under, None, None] + DECK_CLEAR
            leaves = np.argmin(covered, axis=2)  # the first step out from under it
            out = np.where(covered.all(axis=2), d[-1], d[leaves])
            edge[under] = (self.deck_under[here[under]] - z[under])[:, None] / out
        return rise, edge

    def ground(self, en: np.ndarray, z: np.ndarray) -> np.ndarray:
        """The share of the sky flat ground at (N, 2) points, heights z, doesn't see."""
        angles = (np.arange(GROUND_AZIMUTHS) + 0.5) * (2 * np.pi / GROUND_AZIMUTHS)
        directions = np.column_stack([np.cos(angles), np.sin(angles)])
        out = np.zeros(len(en))
        for s in range(0, len(en), CHUNK):
            rise, edge = self._view(*self._rays(en[s:s + CHUNK], directions), z[s:s + CHUNK] + 0.3)
            low = _sin2(np.maximum(rise, 0.0))
            high = np.maximum(_sin2(edge), low)  # (1 where there's no deck: the zenith)
            out[s:s + CHUNK] = 1.0 - (high - low + DECK_SEEN * (1.0 - high)).mean(axis=1)
        return out

    def walls(self, en: np.ndarray, base: np.ndarray, outward: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """For wall columns at (N, 2) points, standing on `base`, facing
        `outward` (unit, east/north): the share of the sky the foot doesn't
        see, and the height above the base by which it's faded away."""
        angles = (np.arange(WALL_AZIMUTHS) + 0.5) * (np.pi / WALL_AZIMUTHS) - np.pi / 2
        weight = np.cos(angles) / np.cos(angles).sum()
        blocked = np.zeros((len(en), len(WALL_HEIGHTS)))
        for s in range(0, len(en), CHUNK):
            o = outward[s:s + CHUNK]
            side = np.column_stack([-o[:, 1], o[:, 0]])
            directions = (o[:, None, :] * np.cos(angles)[None, :, None]
                          + side[:, None, :] * np.sin(angles)[None, :, None])
            # Its own building (the one just behind the wall) isn't in its way.
            own = self.owner[self._index(en[s:s + CHUNK] - o * 0.75)]
            cells, here = self._rays(en[s:s + CHUNK] + o * 0.5, directions, own)
            for k, h in enumerate(WALL_HEIGHTS):
                rise, edge = self._view(cells, here, base[s:s + CHUNK] + h)
                low = _wall_sky(np.maximum(rise, 0.0))
                high = np.minimum(_wall_sky(edge), low)
                blocked[s:s + CHUNK, k] = 1.0 - ((low - high + DECK_SEEN * high) * weight).sum(axis=1)
        foot = blocked[:, 0]
        # The first height where it's faded to FADE_LEFT of the foot's.
        faded = blocked <= foot[:, None] * FADE_LEFT + 0.02
        k = np.argmax(faded, axis=1)
        k = np.where(faded.any(axis=1), k, len(WALL_HEIGHTS) - 1)
        lo = np.maximum(k - 1, 0)
        span = blocked[np.arange(len(en)), lo] - blocked[np.arange(len(en)), k]
        t = np.where(span > 1e-6, (blocked[np.arange(len(en)), lo] - (foot * FADE_LEFT + 0.02)) / np.maximum(span, 1e-6), 1.0)
        reach = WALL_HEIGHTS[lo] + np.clip(t, 0.0, 1.0) * (WALL_HEIGHTS[k] - WALL_HEIGHTS[lo])
        return foot, np.maximum(reach, WALL_HEIGHTS[1])


def _sin2(tangent: np.ndarray) -> np.ndarray:
    """sin^2 of an elevation given by its tangent (inf: the zenith)."""
    t2 = np.minimum(np.square(tangent), 1e12)
    return t2 / (1.0 + t2)


def _wall_sky(tangent: np.ndarray) -> np.ndarray:
    """The share of a wall's sky (cosine weighted) above an elevation given
    by its tangent, straight out from the wall: 1 at the horizon, 0 overhead."""
    e = np.arctan(tangent)
    return 1.0 - (2.0 * e + np.sin(2.0 * e)) / np.pi


def _quantize(share: np.ndarray) -> np.ndarray:
    return np.clip(np.round(share * LEVELS_OF_SHARE), 0, LEVELS_OF_SHARE)


def shade_buildings(sky: Sky, builder) -> None:
    """Bakes the walls' sky into a buildings mesh (MeshBuilder) as it stands."""
    joined = builder.joined()
    if joined is None:
        return
    # (Views of the mesh's arrays: writes to uv2 go to the mesh.)
    pos, uv, uv2, normals = (a.reshape(-1, a.shape[-1]) for a in joined)
    code = np.floor(uv2[:, 0] + 0.5).astype(np.int64)
    flags = code // _FLAG_SCALE
    wall = ((code % _FLAG_SCALE) < _LANDMARKS) & ((flags & (_ROOF | _PARAPET_INSIDE)) == 0) & (uv2[:, 1] < 64.0) \
        & (np.abs(normals[:, 1]) < 0.3)
    if not wall.any():
        return
    k = np.flatnonzero(wall)
    flat = np.hypot(normals[k, 0], normals[k, 2])
    outward = np.column_stack([normals[k, 0], -normals[k, 2]]) / np.maximum(flat, 1e-6)[:, None]
    base = pos[k, 1] - uv[k, 1]
    columns = np.round(np.column_stack([pos[k, 0], pos[k, 2], base, outward * 20.0]), 1)
    unique, inverse = np.unique(columns, axis=0, return_inverse=True)
    inverse = inverse.reshape(-1)
    first = np.zeros(len(unique), dtype=np.int64)
    first[inverse] = np.arange(len(k))
    en = np.column_stack([pos[k[first], 0], -pos[k[first], 2]])
    foot, reach = sky.walls(en, base[first], outward[first])
    share = _quantize(foot)
    level = 1 + np.argmin(np.abs(np.log(reach)[:, None] - np.log(CANYON_TOPS)[None]), axis=1)
    baked = (share + 16 * level)[inverse]
    # The seed in whole 1024ths (as the shader reads it), so it stays exact.
    floor_dm = np.floor(uv2[k, 1] + 0.0005)
    seed = (np.floor(np.clip(uv2[k, 1] - floor_dm, 0.0, 0.999) * 1024.0) + 0.5) / 1024.0
    uv2[k, 1] = floor_dm + seed + 64.0 * baked


def shade_ground(sky: Sky, builder) -> None:
    """Bakes the sky into a ground or street paint mesh's flat faces."""
    joined = builder.joined()
    if joined is None:
        return
    pos = joined[0].reshape(-1, 3)
    normals = joined[3].reshape(-1, 3)
    uv2 = joined[2].reshape(-1, 2)
    k = np.flatnonzero(normals[:, 1] > 0.7)
    if len(k) == 0:
        return
    points, inverse = np.unique(np.round(pos[k], 2), axis=0, return_inverse=True)
    share = _quantize(sky.ground(np.column_stack([points[:, 0], -points[:, 2]]), points[:, 1]))
    uv2[k, 0] = np.floor(uv2[k, 0] + 0.5) + (1.0 + share[inverse.reshape(-1)]) / GROUND_SCALE
