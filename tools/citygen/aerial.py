"""Aerial photos for the city tiles: the city's 2024 orthoimagery (NYC Office
of Technology and Innovation / NYS Statewide Digital Orthoimagery Program,
6-inch, flown March 2024; CC BY 4.0 per the city's metadata), draped by the
game over streets, parks and roofs.

fetch() downloads the photo service's 256 px web-map tiles at zoom FETCH_ZOOM
(about 0.45 m per pixel here) covering every full-detail city tile, cached
in data/raw/aerial/. build() resamples them into one image per city tile, in
our map projection, and marks those tiles in the manifest:

  data/tiles/nyc/aerial/<level>/<i>_<j>.jpg   square JPEG covering the tile
      plus a margin of LEVELS[level] meters all round (roofs can overhang a
      tile's edge); row 0 is the north edge of that square, column 0 its west
      edge. In tile-local Godot x/z, the image spans [-margin, size + margin].
  manifest.json: each level gets "aerial_size" (pixels) and "aerial_margin"
      (meters); each tile with an image gets "aerial": 1.

Pixel sizes nest (0.5, 2 and 16 m), so each coarser level is made by
averaging the finer level's pixels exactly (the ground only exists on land,
and every bit of land has a full-detail tile).

Usage: python aerial.py [fetch|build|mark|all] [--area i0,j0,i1,j1] (lod0 tiles)
("mark" only re-marks existing images after build_tiles.py rewrites the manifest.)
"""

import argparse
import io
import json
import math
import time
import urllib.request
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

import numpy as np
from PIL import Image
from pyproj import Transformer

from common import PROJECTION, RAW_DIR, TILES_DIR

REGION = "nyc"
SERVICE = "https://tiles.arcgis.com/tiles/yG5s3afENB5iO9fj/arcgis/rest/services/NYC_Orthos_2024/MapServer/tile"
FETCH_ZOOM = 18
CACHE = RAW_DIR / "aerial" / str(FETCH_ZOOM)
OUT_DIR = TILES_DIR / REGION / "aerial"
# Per level: meters per pixel, and the margin around the tile (meters, a
# whole number of pixels).
LEVELS = {"lod0": (0.5, 32.0), "lod1": (2.0, 64.0), "lod2": (16.0, 128.0)}
JPEG_QUALITY = 82
# Where there's no photo (beyond the city): a neutral gray.
NO_PHOTO = (128, 128, 128)
WEB_TILE = 256


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("step", nargs="?", default="all", choices=["fetch", "build", "mark", "all"])
    parser.add_argument("--area", help="only lod0 tiles i0,j0,i1,j1 (inclusive), for trying things out")
    parser.add_argument("--workers", type=int, default=14)
    args = parser.parse_args()
    area = tuple(int(v) for v in args.area.split(",")) if args.area else None
    if args.step in ("fetch", "all"):
        fetch(area)
    if args.step in ("build", "all"):
        build(area, args.workers)
    if args.step == "mark":
        mark()


def _manifest() -> dict:
    return json.loads((TILES_DIR / REGION / "manifest.json").read_text())


def _lod0_tiles(manifest: dict, area) -> list:
    level = next(level for level in manifest["levels"] if level["name"] == "lod0")
    tiles = [(t["i"], t["j"]) for t in level["tiles"]]
    if area:
        i0, j0, i1, j1 = area
        tiles = [(i, j) for i, j in tiles if i0 <= i <= i1 and j0 <= j <= j1]
    return tiles


def _web_tiles_for(i: int, j: int, size: float) -> set:
    """Web-map tiles (x, y) at FETCH_ZOOM covering city tile (i, j) and its
    image margin, plus one tile all round."""
    to_lonlat = Transformer.from_crs(PROJECTION, "EPSG:4326", always_xy=True)
    m = LEVELS["lod0"][1]
    e = np.array([i * size - m, (i + 1) * size + m, i * size - m, (i + 1) * size + m])
    n = np.array([-j * size + m, -j * size + m, -(j + 1) * size - m, -(j + 1) * size - m])
    lon, lat = to_lonlat.transform(e, n)
    px, py = _web_pixels(np.asarray(lon), np.asarray(lat))
    x0, x1 = int(px.min() // WEB_TILE) - 1, int(px.max() // WEB_TILE) + 1
    y0, y1 = int(py.min() // WEB_TILE) - 1, int(py.max() // WEB_TILE) + 1
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}


def _web_pixels(lon, lat):
    """Global web-map pixel coordinates at FETCH_ZOOM."""
    scale = WEB_TILE * 2 ** FETCH_ZOOM
    px = (lon + 180.0) / 360.0 * scale
    lat_r = np.radians(lat)
    py = (1.0 - np.log(np.tan(lat_r) + 1.0 / np.cos(lat_r)) / math.pi) / 2.0 * scale
    return px, py


def fetch(area=None, workers: int = 12) -> None:
    started = time.time()
    manifest = _manifest()
    size = next(level["tile_size"] for level in manifest["levels"] if level["name"] == "lod0")
    wanted = set()
    for i, j in _lod0_tiles(manifest, area):
        wanted |= _web_tiles_for(i, j, size)
    missing = sorted(t for t in wanted if not _cache_path(*t).exists())
    print(f"aerial photos: {len(wanted):,} web tiles needed, {len(missing):,} to download", flush=True)
    done = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for ok in pool.map(lambda t: _download(*t), missing):
            done += 1
            if done % 2000 == 0:
                print(f"  {done:,}/{len(missing):,} ({time.time() - started:.0f} s)", flush=True)
    print(f"  aerial photos fetched in {time.time() - started:.0f} s", flush=True)


def _cache_path(x: int, y: int):
    return CACHE / str(x) / f"{y}.img"


def _download(x: int, y: int) -> bool:
    path = _cache_path(x, y)
    request = urllib.request.Request(f"{SERVICE}/{FETCH_ZOOM}/{y}/{x}", headers={"User-Agent": "new-game-citygen/1.0"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            break
        except urllib.error.HTTPError as error:
            if error.code == 404:
                data = b""  # outside the photos: remember that, so it isn't asked again
                break
            time.sleep(2 * (attempt + 1))
        except Exception:
            time.sleep(2 * (attempt + 1))
    else:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)
    return True


def build(area=None, workers: int = 14) -> None:
    started = time.time()
    manifest = _manifest()
    sizes = {level["name"]: level["tile_size"] for level in manifest["levels"]}
    lod0 = _lod0_tiles(manifest, area)
    (OUT_DIR / "lod0").mkdir(parents=True, exist_ok=True)
    print(f"aerial images: {len(lod0):,} full-detail tiles...", flush=True)
    made = {"lod0": set()}
    with ProcessPoolExecutor(max_workers=workers) as pool:
        for key in pool.map(_build_lod0, lod0, [sizes["lod0"]] * len(lod0), chunksize=8):
            if key:
                made["lod0"].add(key)
    # Coarser levels: each tile averages the finer level's pixels.
    for child, parent in (("lod0", "lod1"), ("lod1", "lod2")):
        (OUT_DIR / parent).mkdir(parents=True, exist_ok=True)
        ratio = int(round(sizes[parent] / sizes[child]))
        parents = {(math.floor(i / ratio), math.floor(j / ratio)) for i, j in made[child]}
        made[parent] = set()
        for pi, pj in sorted(parents):
            if _build_parent(child, parent, pi, pj, sizes, made[child]):
                made[parent].add((pi, pj))
        print(f"  {parent}: {len(made[parent]):,} images", flush=True)

    for level in manifest["levels"]:
        level["aerial_size"] = _pixels(level["tile_size"], level["name"])
        level["aerial_margin"] = LEVELS[level["name"]][1]
        for tile in level["tiles"]:
            if (tile["i"], tile["j"]) in made.get(level["name"], ()):
                tile["aerial"] = 1
            elif not area:
                tile.pop("aerial", None)
    path = TILES_DIR / REGION / "manifest.json"
    path.write_text(json.dumps(manifest, separators=(",", ":")))
    total = sum(f.stat().st_size for f in OUT_DIR.rglob("*.jpg"))
    print(f"  aerial images built in {time.time() - started:.0f} s ({total / 1e6:.0f} MB)", flush=True)


def _pixels(size: float, level: str) -> int:
    pixel, margin = LEVELS[level]
    return int(round((size + 2 * margin) / pixel))


def mark() -> None:
    """Marks the tiles that already have images in a freshly built manifest
    (build_tiles.py writes it without them), without rebuilding any."""
    manifest = _manifest()
    for level in manifest["levels"]:
        level["aerial_size"] = _pixels(level["tile_size"], level["name"])
        level["aerial_margin"] = LEVELS[level["name"]][1]
        for tile in level["tiles"]:
            if (OUT_DIR / level["name"] / f"{tile['i']}_{tile['j']}.jpg").exists():
                tile["aerial"] = 1
    (TILES_DIR / REGION / "manifest.json").write_text(json.dumps(manifest, separators=(",", ":")))
    print("aerial images marked in the manifest", flush=True)


def _build_lod0(key, size: float):
    """Resamples the web-map photos into city tile `key`'s image; returns key, or None if no photos."""
    i, j = key
    pixel, margin = LEVELS["lod0"]
    pixels = _pixels(size, "lod0")
    web = sorted(_web_tiles_for(i, j, size))
    xs = [x for x, _ in web]
    ys = [y for _, y in web]
    x0, y0 = min(xs), min(ys)
    mosaic = np.zeros(((max(ys) - y0 + 1) * WEB_TILE, (max(xs) - x0 + 1) * WEB_TILE, 3), dtype=np.uint8)
    mosaic[:] = NO_PHOTO
    found = False
    for x, y in web:
        path = _cache_path(x, y)
        data = path.read_bytes() if path.exists() else b""
        if not data:
            continue
        try:
            image = Image.open(io.BytesIO(data)).convert("RGB")
        except Exception:
            continue
        mosaic[(y - y0) * WEB_TILE:(y - y0 + 1) * WEB_TILE, (x - x0) * WEB_TILE:(x - x0 + 1) * WEB_TILE] = np.asarray(image)
        found = True
    if not found:
        return None
    # Pixel centers of the output, in our projection, to lon/lat to web pixels.
    centers = (np.arange(pixels) + 0.5) * pixel - margin
    e, n = np.meshgrid(i * size + centers, -j * size - centers)
    lon, lat = Transformer.from_crs(PROJECTION, "EPSG:4326", always_xy=True).transform(e.ravel(), n.ravel())
    px, py = _web_pixels(np.asarray(lon), np.asarray(lat))
    out = _bilinear(mosaic, px - x0 * WEB_TILE - 0.5, py - y0 * WEB_TILE - 0.5).reshape(pixels, pixels, 3)
    Image.fromarray(out).save(OUT_DIR / "lod0" / f"{i}_{j}.jpg", quality=JPEG_QUALITY)
    return key


def _bilinear(image: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    height, width = image.shape[:2]
    x = np.clip(x, 0, width - 1.001)
    y = np.clip(y, 0, height - 1.001)
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    img = image.astype(np.float32)
    top = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    bottom = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return np.clip(top * (1 - fy) + bottom * fy + 0.5, 0, 255).astype(np.uint8)


def _build_parent(child: str, parent: str, pi: int, pj: int, sizes: dict, children: set) -> bool:
    """A coarser tile's image: the finer tiles' images (without their margins)
    laid out at their own pixel size over the coarser tile and its margin,
    then averaged down."""
    child_size, size = sizes[child], sizes[parent]
    child_pixel, child_margin = LEVELS[child]
    margin = LEVELS[parent][1]
    core = int(round(child_size / child_pixel))
    trim = int(round(child_margin / child_pixel))
    west, north = pi * size - margin, -pj * size + margin  # the image's north-west corner, east/north
    span = int(round((size + 2 * margin) / child_pixel))
    canvas = Image.new("RGB", (span, span), NO_PHOTO)
    reach = math.ceil(margin / child_size)
    ratio = int(round(size / child_size))
    own_children = False
    for ci in range(pi * ratio - reach, (pi + 1) * ratio + reach):
        for cj in range(pj * ratio - reach, (pj + 1) * ratio + reach):
            if (ci, cj) not in children:
                continue
            with Image.open(OUT_DIR / child / f"{ci}_{cj}.jpg") as image:
                piece = image.crop((trim, trim, trim + core, trim + core))
            canvas.paste(piece, (int(round((ci * child_size - west) / child_pixel)),
                                 int(round((north + cj * child_size) / child_pixel))))
            own_children |= pi * ratio <= ci < (pi + 1) * ratio and pj * ratio <= cj < (pj + 1) * ratio
    if own_children:
        pixels = _pixels(size, parent)
        canvas.resize((pixels, pixels), Image.Resampling.BOX).save(OUT_DIR / parent / f"{pi}_{pj}.jpg", quality=JPEG_QUALITY)
    return own_children


if __name__ == "__main__":
    main()
