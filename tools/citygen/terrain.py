"""Ground height anywhere in the city, from the USGS elevation model.

prepare() resamples the downloaded elevation tiles (fetch_data.py) onto a
regular grid in our map projection, data/cache/terrain.npy (+ .json), so
tile building can look heights up quickly. Terrain() reads that grid.

Heights are meters above sea level (NAVD88). The model is bare earth: water
surfaces are flattened, and over open water it's about 0. Land never goes
below LAND_MIN, which keeps waterfronts and piers above the water.
"""

import json
import time

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.windows import from_bounds

from common import CACHE_DIR, LAND_MIN, PROJECTION, RAW_DIR

GRID_SPACING = 5.0  # meters
MARGIN = 1000.0  # meters around the land
ELEVATION_FILES = ["USGS_13_n41w075.tif", "USGS_13_n41w074.tif"]  # west to east
GRID_PATH = CACHE_DIR / "terrain.npy"
NODATA_BELOW = -1000.0
ROWS_PER_CHUNK = 400


def prepare(land_bounds) -> None:
    """Builds the height grid covering `land_bounds` (min_e, min_n, max_e, max_n)."""
    started = time.time()
    min_e, min_n, max_e, max_n = land_bounds
    min_e, min_n = np.floor((min_e - MARGIN) / GRID_SPACING) * GRID_SPACING, np.floor((min_n - MARGIN) / GRID_SPACING) * GRID_SPACING
    max_e, max_n = np.ceil((max_e + MARGIN) / GRID_SPACING) * GRID_SPACING, np.ceil((max_n + MARGIN) / GRID_SPACING) * GRID_SPACING
    columns = int(round((max_e - min_e) / GRID_SPACING)) + 1
    rows = int(round((max_n - min_n) / GRID_SPACING)) + 1
    print(f"preparing terrain: {columns} x {rows} grid at {GRID_SPACING:g} m...", flush=True)

    to_lonlat = Transformer.from_crs(PROJECTION, "EPSG:4269", always_xy=True)
    corners_lon, corners_lat = to_lonlat.transform([min_e, max_e, min_e, max_e], [min_n, min_n, max_n, max_n])
    sources = [_Source(RAW_DIR / "elevation" / name, min(corners_lon), min(corners_lat),
                       max(corners_lon), max(corners_lat)) for name in ELEVATION_FILES]

    grid = np.lib.format.open_memmap(GRID_PATH.with_suffix(".tmp.npy"), mode="w+", dtype=np.float32, shape=(rows, columns))
    east = min_e + np.arange(columns) * GRID_SPACING
    for row0 in range(0, rows, ROWS_PER_CHUNK):
        row1 = min(rows, row0 + ROWS_PER_CHUNK)
        north = max_n - np.arange(row0, row1) * GRID_SPACING
        e, n = np.meshgrid(east, north)
        lon, lat = to_lonlat.transform(e.ravel(), n.ravel())
        heights = np.full(len(lon), np.nan, dtype=np.float64)
        for source in sources:
            source.sample_into(heights, lon, lat)
        heights = np.nan_to_num(heights, nan=0.0)
        grid[row0:row1] = heights.reshape(e.shape)
    grid.flush()
    del grid
    GRID_PATH.with_suffix(".tmp.npy").replace(GRID_PATH)
    GRID_PATH.with_suffix(".json").write_text(json.dumps(
        {"min_e": min_e, "max_n": max_n, "spacing": GRID_SPACING, "rows": rows, "columns": columns}))
    print(f"  terrain ready in {time.time() - started:.0f} s", flush=True)


class _Source:
    """The part of one elevation tile we need, sampled bilinearly by lon/lat."""

    def __init__(self, path, west, south, east, north):
        with rasterio.open(path) as data:
            pad = 4 * data.res[0]
            west, east = max(west - pad, data.bounds.left), min(east + pad, data.bounds.right)
            south, north = max(south - pad, data.bounds.bottom), min(north + pad, data.bounds.top)
            self.empty = west >= east or south >= north
            if self.empty:
                return
            window = from_bounds(west, south, east, north, data.transform).round_offsets().round_lengths()
            values = data.read(1, window=window).astype(np.float64)
            values[values < NODATA_BELOW] = np.nan
            self.values = values
            transform = data.window_transform(window)
            self.left, self.top = transform.c, transform.f
            self.dx, self.dy = transform.a, -transform.e

    def sample_into(self, out, lon, lat):
        if self.empty:
            return
        # Pixel centers sit half a pixel in from the corner.
        x = (lon - self.left) / self.dx - 0.5
        y = (self.top - lat) / self.dy - 0.5
        rows, columns = self.values.shape
        inside = (x >= 0) & (y >= 0) & (x <= columns - 1) & (y <= rows - 1) & np.isnan(out)
        x, y = x[inside], y[inside]
        x0 = np.minimum(np.floor(x).astype(np.int64), columns - 2)
        y0 = np.minimum(np.floor(y).astype(np.int64), rows - 2)
        fx, fy = x - x0, y - y0
        v = self.values
        out[inside] = ((v[y0, x0] * (1 - fx) + v[y0, x0 + 1] * fx) * (1 - fy)
                       + (v[y0 + 1, x0] * (1 - fx) + v[y0 + 1, x0 + 1] * fx) * fy)


class Terrain:
    """Ground heights from the prepared grid (see prepare())."""

    def __init__(self):
        meta = json.loads(GRID_PATH.with_suffix(".json").read_text())
        self.grid = np.load(GRID_PATH, mmap_mode="r")
        self.min_e, self.max_n, self.spacing = meta["min_e"], meta["max_n"], meta["spacing"]

    def raw(self, en: np.ndarray) -> np.ndarray:
        """Elevation model heights at (N, 2) east/north points, water included."""
        en = np.asarray(en, dtype=np.float64).reshape(-1, 2)
        rows, columns = self.grid.shape
        x = np.clip((en[:, 0] - self.min_e) / self.spacing, 0, columns - 1.001)
        y = np.clip((self.max_n - en[:, 1]) / self.spacing, 0, rows - 1.001)
        x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
        fx, fy = x - x0, y - y0
        g = self.grid
        return ((g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx) * (1 - fy)
                + (g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx) * fy)

    def height(self, en: np.ndarray) -> np.ndarray:
        """Ground height at (N, 2) east/north points (never below LAND_MIN)."""
        return np.maximum(self.raw(en), LAND_MIN)

    def lattice(self, cell: float, raw: bool = False) -> "Lattice":
        """The ground as a mesh bent every `cell` meters can show it (see Lattice)."""
        return Lattice(self.raw if raw else self.height, cell)


class Lattice:
    """Ground heights taken every `cell` meters on a square lattice and blended
    in between. A mesh cut along the lattice lines (common.split_triangles)
    matches this exactly along them, so anything placed with it (sidewalk
    lanes, building bases) sits right on the mesh."""

    def __init__(self, sample, cell: float):
        self.sample, self.cell = sample, cell

    def height(self, en: np.ndarray) -> np.ndarray:
        en = np.asarray(en, dtype=np.float64).reshape(-1, 2)
        c = self.cell
        corner = np.floor(en / c) * c
        f = (en - corner) / c
        offsets = np.array([[0.0, 0.0], [c, 0.0], [0.0, c], [c, c]])
        h = self.sample((corner[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(-1, 4)
        fx, fy = f[:, 0], f[:, 1]
        return (h[:, 0] * (1 - fx) + h[:, 1] * fx) * (1 - fy) + (h[:, 2] * (1 - fx) + h[:, 3] * fx) * fy

    def normal(self, en: np.ndarray) -> np.ndarray:
        """Unit normals at (N, 2) east/north points, in Godot space (+Y up, +Z south)."""
        en = np.asarray(en, dtype=np.float64).reshape(-1, 2)
        d = self.cell
        offsets = np.array([[d, 0.0], [-d, 0.0], [0.0, d], [0.0, -d]])
        h = self.height((en[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(-1, 4)
        slope_e = (h[:, 0] - h[:, 1]) / (2 * d)
        slope_n = (h[:, 2] - h[:, 3]) / (2 * d)
        # Godot +Z is south, so the height's slope along +Z is -slope_n.
        normal = np.column_stack([-slope_e, np.ones(len(en)), slope_n])
        return normal / np.linalg.norm(normal, axis=1, keepdims=True)
