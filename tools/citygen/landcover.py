"""What covers the ground, from the city's 2017 land cover map (LiDAR and
aerial photos, 6-inch pixels): tree canopy, grass, bare soil, water,
buildings, roads, other paved ground, railroads.

prepare() samples it every SPACING meters on our own (east, north) grid into
data/cache/landcover.npy (+ .json), from the map's 8x reduced-resolution
layer (1.2 m pixels, nearest-neighbor, so classes stay classes). Only that
layer is needed: unzip Land_Cover.zip except the 98 GB full-resolution .ige.
LandCover reads the grid back; write_canopy_map() makes the game's citywide
tree canopy map from it.
"""

import json
import time

import numpy as np
import rasterio
from PIL import Image
from pyproj import Transformer
from rasterio.windows import Window

from common import CACHE_DIR, PROJECTION, RAW_DIR

SOURCE = RAW_DIR / "landcover" / "Land_Cover" / "NYC_2017_LiDAR_LandCover.img"
SOURCE_CRS = "EPSG:2263"  # New York State Plane, Long Island, US feet
OVERVIEW_LEVEL = 2  # the source's overviews are 2x, 4x, 8x, ...: the 8x one
GRID_PATH = CACHE_DIR / "landcover.npy"
SPACING = 2.0  # meters
BLOCK = 2000  # cells per side, sampled at a time
CANOPY_MAP_PIXEL = 8.0  # meters, for write_canopy_map()

NO_DATA = 0
CANOPY = 1
GRASS = 2
SOIL = 3
WATER = 4
BUILDING = 5
ROAD = 6
PAVED = 7
RAIL = 8


def prepare(land_bounds) -> None:
    started = time.time()
    min_e, min_n, max_e, max_n = land_bounds
    columns = int(np.ceil((max_e - min_e) / SPACING))
    rows = int(np.ceil((max_n - min_n) / SPACING))
    grid = np.lib.format.open_memmap(GRID_PATH.with_suffix(".tmp.npy"), mode="w+", dtype=np.uint8, shape=(rows, columns))
    to_source = Transformer.from_crs(PROJECTION, SOURCE_CRS, always_xy=True)
    with rasterio.open(SOURCE, overview_level=OVERVIEW_LEVEL) as src:
        inverse = ~src.transform
        for r0 in range(0, rows, BLOCK):
            for c0 in range(0, columns, BLOCK):
                r1, c1 = min(r0 + BLOCK, rows), min(c0 + BLOCK, columns)
                e = min_e + (np.arange(c0, c1) + 0.5) * SPACING
                n = max_n - (np.arange(r0, r1) + 0.5) * SPACING
                ee, nn = np.meshgrid(e, n)
                x, y = to_source.transform(ee.ravel(), nn.ravel())
                col, row = inverse * (np.asarray(x), np.asarray(y))
                col, row = np.floor(col).astype(np.int64), np.floor(row).astype(np.int64)
                inside = (col >= 0) & (row >= 0) & (col < src.width) & (row < src.height)
                out = np.zeros(len(col), dtype=np.uint8)
                if inside.any():
                    left, top = col[inside].min(), row[inside].min()
                    width, height = col[inside].max() - left + 1, row[inside].max() - top + 1
                    window = src.read(1, window=Window(left, top, width, height))
                    out[inside] = window[row[inside] - top, col[inside] - left]
                grid[r0:r1, c0:c1] = out.reshape(r1 - r0, c1 - c0)
            print(f"  land cover: {min(r0 + BLOCK, rows):,}/{rows:,} rows ({time.time() - started:.0f} s)", flush=True)
    grid.flush()
    del grid
    GRID_PATH.with_suffix(".tmp.npy").replace(GRID_PATH)
    GRID_PATH.with_suffix(".json").write_text(json.dumps({"min_e": min_e, "max_n": max_n, "spacing": SPACING}))


def write_canopy_map(path, pixel: float = CANOPY_MAP_PIXEL) -> dict:
    """Writes how much of each `pixel`-meter square is tree canopy (0..255) as
    a grayscale PNG covering the grid, north up, and returns where it lies in
    Godot space ({file, min_x, min_z, pixel, width, height}). The game's
    ground shader darkens wooded parks and yards with it, out to the horizon."""
    grid = np.load(GRID_PATH, mmap_mode="r")
    meta = json.loads(GRID_PATH.with_suffix(".json").read_text())
    k = int(round(pixel / meta["spacing"]))
    rows, columns = grid.shape[0] // k, grid.shape[1] // k
    out = np.zeros((rows, columns), dtype=np.uint8)
    chunk = 512
    for r0 in range(0, rows, chunk):
        r1 = min(r0 + chunk, rows)
        block = grid[r0 * k:r1 * k, :columns * k] == CANOPY
        share = block.reshape(r1 - r0, k, columns, k).mean(axis=(1, 3))
        out[r0:r1] = np.round(share * 255).astype(np.uint8)
    Image.fromarray(out, mode="L").save(path, optimize=True)
    return {"file": path.name, "min_x": meta["min_e"], "min_z": -meta["max_n"], "pixel": k * meta["spacing"],
            "width": columns, "height": rows}


class LandCover:
    """The prepared land cover grid (see prepare())."""

    def __init__(self):
        meta = json.loads(GRID_PATH.with_suffix(".json").read_text())
        self.grid = np.load(GRID_PATH, mmap_mode="r")
        self.min_e, self.max_n, self.spacing = meta["min_e"], meta["max_n"], meta["spacing"]

    def classes(self, en: np.ndarray) -> np.ndarray:
        """The class at each (N, 2) east/north point (NO_DATA off the map)."""
        en = np.asarray(en, dtype=np.float64).reshape(-1, 2)
        rows, columns = self.grid.shape
        c = np.floor((en[:, 0] - self.min_e) / self.spacing).astype(np.int64)
        r = np.floor((self.max_n - en[:, 1]) / self.spacing).astype(np.int64)
        inside = (c >= 0) & (r >= 0) & (c < columns) & (r < rows)
        out = np.zeros(len(en), dtype=np.uint8)
        out[inside] = self.grid[r[inside], c[inside]]
        return out

    def is_canopy(self, en: np.ndarray) -> np.ndarray:
        return self.classes(en) == CANOPY

    def canopy_share(self, en: np.ndarray, reach: float) -> np.ndarray:
        """How much of the square `reach` meters around each point is canopy (0..1)."""
        en = np.asarray(en, dtype=np.float64).reshape(-1, 2)
        if len(en) == 0:
            return np.zeros(0)
        steps = np.arange(-reach, reach + 1e-6, self.spacing)
        offsets = np.stack(np.meshgrid(steps, steps), axis=-1).reshape(-1, 2)
        hits = self.is_canopy((en[:, None, :] + offsets[None]).reshape(-1, 2)).reshape(len(en), -1)
        return hits.mean(axis=1)
