"""Makes the game's soundscape map, assets/audio/soundscape.png: what the city
around each 64 m square sounds like, for the ambience (scripts/audio/
soundscape.gd reads it). From the land cover grid and the ground heights that
tools/citygen prepared in data/cache (see landcover.py and terrain.py):

  R  green: tree canopy and grass within about 100 m (birds by day,
     crickets at night, grass underfoot)
  G  water: open water within about 150 m, counting the ocean past the
     city's edge (waves lapping)
  B  built up: buildings, roads, paving and rails within about 300 m (the
     traffic hum)
  A  ground height in meters (to 4 m), for how high above the street the
     listener is

Shares are worked out on a 32 m grid, blurred, then averaged down to 64 m
and rounded to steps of 8 (of 255): the game blends between pixels, and
the map stays small (about 270 kB).

North is up; the top-left corner sits at world (MIN_X, MIN_Z), like the
tree canopy map. Run with tools/citygen's Python:
    tools/citygen/.venv/Scripts/python tools/audio/soundscape_map.py
It prints the map's placement for soundscape.gd.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "data" / "cache"
OUT = ROOT / "assets" / "audio" / "soundscape.png"
BASE = 32.0  # meters: shares and blurs
PIXEL = 64.0  # meters: the map

# Land cover classes (tools/citygen/landcover.py).
NO_DATA, CANOPY, GRASS, SOIL, WATER, BUILDING, ROAD, PAVED, RAIL = range(9)

# Box blur half-widths, in meters.
GREEN_REACH = 100.0
WATER_REACH = 150.0
BUILT_REACH = 300.0


def class_shares(grid: np.ndarray, k: int) -> dict[str, np.ndarray]:
    """Shares (0..1) of green, water and built-up ground in each k x k block."""
    rows, columns = grid.shape[0] // k, grid.shape[1] // k
    shares = {name: np.zeros((rows, columns), np.float32) for name in ("green", "water", "built")}
    chunk = 256
    for r0 in range(0, rows, chunk):
        r1 = min(r0 + chunk, rows)
        block = np.asarray(grid[r0 * k:r1 * k, :columns * k]).reshape(r1 - r0, k, columns, k)
        shares["green"][r0:r1] = ((block == CANOPY) | (block == GRASS)).mean(axis=(1, 3))
        shares["water"][r0:r1] = ((block == WATER) | (block == NO_DATA)).mean(axis=(1, 3))
        shares["built"][r0:r1] = ((block >= BUILDING) & (block <= RAIL)).mean(axis=(1, 3))
    return shares


def box_blur(values: np.ndarray, radius: int, outside: float) -> np.ndarray:
    """Mean over a (2 radius + 1)^2 box around each cell; off the map counts as `outside`."""
    padded = np.pad(values.astype(np.float64), radius + 1, constant_values=outside)
    total = padded.cumsum(axis=0).cumsum(axis=1)
    size = 2 * radius + 1
    rows, columns = values.shape
    a = total[size:size + rows, size:size + columns]
    b = total[0:rows, size:size + columns]
    c = total[size:size + rows, 0:columns]
    d = total[0:rows, 0:columns]
    return ((a - b - c + d) / (size * size)).astype(np.float32)


def shrink(values: np.ndarray) -> np.ndarray:
    """Averages 2 x 2 cells into one (BASE to PIXEL)."""
    k = int(round(PIXEL / BASE))
    rows, columns = values.shape[0] // k, values.shape[1] // k
    return values[:rows * k, :columns * k].reshape(rows, k, columns, k).mean(axis=(1, 3))


def main() -> None:
    meta = json.loads((CACHE / "landcover.json").read_text())
    grid = np.load(CACHE / "landcover.npy", mmap_mode="r")
    shares = class_shares(grid, int(round(BASE / meta["spacing"])))
    green = shrink(box_blur(shares["green"], int(GREEN_REACH / BASE), 0.0))
    water = shrink(box_blur(shares["water"], int(WATER_REACH / BASE), 1.0))
    built = shrink(box_blur(shares["built"], int(BUILT_REACH / BASE), 0.0))
    rows, columns = green.shape

    # Ground height at each cell's middle (nearest terrain sample).
    terrain_meta = json.loads((CACHE / "terrain.json").read_text())
    terrain = np.load(CACHE / "terrain.npy", mmap_mode="r")
    east = meta["min_e"] + (np.arange(columns) + 0.5) * PIXEL
    north = meta["max_n"] - (np.arange(rows) + 0.5) * PIXEL
    t_col = np.clip(np.round((east - terrain_meta["min_e"]) / terrain_meta["spacing"]).astype(int),
                    0, terrain.shape[1] - 1)
    t_row = np.clip(np.round((terrain_meta["max_n"] - north) / terrain_meta["spacing"]).astype(int),
                    0, terrain.shape[0] - 1)
    height = np.nan_to_num(np.asarray(terrain[np.ix_(t_row, t_col)]), nan=0.0)
    # Past the city's edge is ocean in the game (the terrain goes on into New
    # Jersey and Nassau County).
    height[shrink(shares["water"]) > 0.5] = 0.0

    def steps(share: np.ndarray) -> np.ndarray:
        return np.clip(np.round(np.clip(share, 0, 1) * 255 / 8) * 8, 0, 255)

    rgba = np.stack([steps(green), steps(water), steps(built),
                     np.clip(np.round(height / 4.0) * 4.0, 0, 252)], axis=-1).astype(np.uint8)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(OUT, optimize=True)
    placement = {"min_x": meta["min_e"], "min_z": -meta["max_n"], "pixel": PIXEL, "width": columns, "height": rows}
    print(f"wrote {OUT} ({OUT.stat().st_size / 1e3:.0f} kB): {json.dumps(placement)}")


if __name__ == "__main__":
    sys.exit(main())
