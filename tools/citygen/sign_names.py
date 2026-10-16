"""The invented names on shop signs (props.shop_fronts()) and the texture the
game draws them from (shaders/shop_sign.gdshader).

No real brands: kinds of shops ("PIZZA", "FARMACIA"), made-up family and
fancy names, the upstairs businesses' signs and the banners of a commercial
street. Each name is a row of the texture, in one of four typefaces picked
for the kind of shop, all under the SIL Open Font License (Google Fonts):
Anton (tall and condensed), Lilita One (round and heavy), Alfa Slab One
(slab serif) and Pacifico (script). Rendered text isn't the fonts'
software, so the fonts themselves stay out of the game; `build` downloads
them to data/raw/fonts.

The texture (assets/signs/sign_names.png, 1024 x 2048, one channel) holds
the names as a signed distance field: 0.5 on a letter's edge, more inside,
less outside, by DISTANCE_SPREAD pixels either way, so the shader draws
crisp letters at any size, with outlines. Name k is in cell (k // ROWS,
k % ROWS), CELL pixels each, centered, as wide as it is (up to TEXT_WIDTH),
TEXT_HEIGHT tall. The texture's bottom row of pixels says how wide each
name is: pixel k is its width as a share of a cell (x 255), which the shader
reads to fit the name to a sign.

Usage: python sign_names.py build    (with tools/citygen's Python)
"""

import sys
import urllib.request
from pathlib import Path

import numpy as np

from common import RAW_DIR, ROOT

# Typefaces: (file, the Google Fonts path, size relative to the cell's text
# height, nudge down as a share of it).
ANTON, LILITA, SLAB, SCRIPT = range(4)
FONTS = (
    ("Anton-Regular.ttf", "ofl/anton/Anton-Regular.ttf", 1.0, 0.0),
    ("LilitaOne-Regular.ttf", "ofl/lilitaone/LilitaOne-Regular.ttf", 1.0, 0.0),
    ("AlfaSlabOne-Regular.ttf", "ofl/alfaslabone/AlfaSlabOne-Regular.ttf", 1.0, 0.0),
    ("Pacifico-Regular.ttf", "ofl/pacifico/Pacifico-Regular.ttf", 0.8, -0.08),
)
FONT_URL = "https://github.com/google/fonts/raw/main/{}"

# Kinds of names (props.shop_fronts() picks by kind): on a shop's sign; on
# a shop's sign, likelier in the boroughs' Spanish-speaking neighborhoods;
# upstairs businesses; banners.
SHOP, SHOP_SPANISH, UPSTAIRS, BANNER = range(4)
# (text, typeface, kind), in the texture's order.
NAMES = (
    ("DELI & GROCERY", ANTON, SHOP),
    ("PIZZA", LILITA, SHOP),
    ("Bakery", SCRIPT, SHOP),
    ("Nails", SCRIPT, SHOP),
    ("PHARMACY", ANTON, SHOP),
    ("LAUNDROMAT", LILITA, SHOP),
    ("CELL PHONES", ANTON, SHOP),
    ("99 CENT STORE", LILITA, SHOP),
    ("JEWELRY", SLAB, SHOP),
    ("Cafe", SCRIPT, SHOP),
    ("BAGELS", LILITA, SHOP),
    ("DINER", SLAB, SHOP),
    ("SUSHI", LILITA, SHOP),
    ("TACOS", LILITA, SHOP_SPANISH),
    ("BARBER SHOP", SLAB, SHOP),
    ("OPTICAL", ANTON, SHOP),
    ("WINE & LIQUORS", SLAB, SHOP),
    ("Flowers", SCRIPT, SHOP),
    ("HARDWARE", ANTON, SHOP),
    ("SHOES", ANTON, SHOP),
    ("PANADERIA", SLAB, SHOP_SPANISH),
    ("FARMACIA", ANTON, SHOP_SPANISH),
    ("La Estrella", SCRIPT, SHOP_SPANISH),
    ("LUCKY GARDEN", SLAB, SHOP),
    ("SUNRISE DELI", LILITA, SHOP),
    ("TONY'S PIZZA", LILITA, SHOP),
    ("Mama Rosa", SCRIPT, SHOP),
    ("BLUE MOON CAFE", SLAB, SHOP),
    ("FRUIT MARKET", ANTON, SHOP),
    ("HALAL GRILL", LILITA, SHOP),
    ("TAQUERIA", SLAB, SHOP_SPANISH),
    ("Beauty Salon", SCRIPT, SHOP),
    ("DRY CLEANERS", ANTON, SHOP),
    ("MINI MARKET", ANTON, SHOP),
    ("BOOKS", SLAB, SHOP),
    ("BOMBAY SPICE", SLAB, SHOP),
    ("EL SOL", LILITA, SHOP_SPANISH),
    ("NOODLE HOUSE", LILITA, SHOP),
    ("SUPERMARKET", ANTON, SHOP),
    ("CHECK CASHING", ANTON, SHOP),
    ("TOYS & GIFTS", LILITA, SHOP),
    ("BODEGA", SLAB, SHOP_SPANISH),
    ("KOREAN BBQ", LILITA, SHOP),
    ("ELECTRONICS", ANTON, SHOP),
    ("DENTIST", ANTON, UPSTAIRS),
    ("LAW OFFICE", SLAB, UPSTAIRS),
    ("TAX SERVICE", ANTON, UPSTAIRS),
    ("TRAVEL", LILITA, UPSTAIRS),
    ("MEDICAL", ANTON, UPSTAIRS),
    ("Dance Studio", SCRIPT, UPSTAIRS),
    ("KARATE", LILITA, UPSTAIRS),
    ("INSURANCE", ANTON, UPSTAIRS),
    ("REAL ESTATE", SLAB, UPSTAIRS),
    ("ACUPUNCTURE", ANTON, UPSTAIRS),
    ("ENGLISH CLASSES", ANTON, UPSTAIRS),
    ("CHIROPRACTOR", ANTON, UPSTAIRS),
    ("TUTORING", LILITA, UPSTAIRS),
    ("MULTI SERVICES", ANTON, UPSTAIRS),
    ("GRAND OPENING", LILITA, BANNER),
    ("NOW OPEN", LILITA, BANNER),
    ("SALE", ANTON, BANNER),
    ("FOR RENT", ANTON, BANNER),
    ("SE RENTA", ANTON, BANNER),
    ("OPEN 24 HRS", LILITA, BANNER),
)

ROWS = 32
CELL = (512, 64)
TEXT_HEIGHT = 40       # pixels: capitals' height in a cell
TEXT_WIDTH = 496       # pixels at most
DISTANCE_SPREAD = 6.0  # pixels either side of an edge that the field spans
SUPERSAMPLE = 4        # names are drawn this much bigger, then reduced
TEXTURE_PATH = ROOT / "assets" / "signs" / "sign_names.png"
FONT_DIR = RAW_DIR / "fonts"


def names_of(kind: int) -> list[int]:
    """The rows of the names of this kind."""
    return [k for k, (_, _, k_kind) in enumerate(NAMES) if k_kind == kind]


def build() -> None:
    from PIL import Image, ImageDraw, ImageFont

    size = (CELL[0] * ((len(NAMES) + ROWS - 1) // ROWS), CELL[1] * ROWS)
    atlas = np.zeros((size[1], size[0]), np.uint8)
    widths = np.zeros(len(NAMES))
    for k, (text, typeface, _) in enumerate(NAMES):
        file, path, scale, nudge = FONTS[typeface]
        font_path = FONT_DIR / file
        if not font_path.exists():
            FONT_DIR.mkdir(parents=True, exist_ok=True)
            print(f"downloading {file}", flush=True)
            urllib.request.urlretrieve(FONT_URL.format(path), font_path)
        # Size the font so its capitals are TEXT_HEIGHT tall (supersampled).
        s = SUPERSAMPLE
        probe = ImageFont.truetype(str(font_path), 100)
        cap = probe.getbbox("H")
        points = 100 * TEXT_HEIGHT * scale * s / (cap[3] - cap[1])
        font = ImageFont.truetype(str(font_path), int(round(points)))
        box = font.getbbox(text)
        width = box[2] - box[0]
        squeeze = min(1.0, TEXT_WIDTH * s / width)
        big = Image.new("L", (int(np.ceil(width)) + 8 * s, CELL[1] * s), 0)
        cap = font.getbbox("H")
        # Capitals centered up and down (descenders hang below).
        top = (CELL[1] * s - (cap[3] - cap[1])) / 2 - cap[1] + nudge * TEXT_HEIGHT * s
        ImageDraw.Draw(big).text((4 * s - box[0], top), text, font=font, fill=255)
        cell_width = min(int(round((width + 8 * s) * squeeze / s)), CELL[0])
        mask = np.asarray(big.resize((cell_width * s, CELL[1] * s), Image.LANCZOS)) > 127
        field = _distance_field(mask, s)
        x0 = (CELL[0] - cell_width) // 2
        column, row = divmod(k, ROWS)
        cell = atlas[row * CELL[1]:(row + 1) * CELL[1], column * CELL[0]:(column + 1) * CELL[0]]
        cell[:, x0:x0 + cell_width] = field
        widths[k] = (cell_width - 8 * squeeze) / CELL[0]
    # Each name's width in the bottom row, one pixel per name.
    atlas[-1, :] = 0
    atlas[-1, :len(NAMES)] = np.round(np.clip(widths, 0.0, 1.0) * 255).astype(np.uint8)
    TEXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "L").save(TEXTURE_PATH, optimize=True)
    print(f"{len(NAMES)} names -> {TEXTURE_PATH} ({TEXTURE_PATH.stat().st_size // 1024} kB)")


def _distance_field(mask: np.ndarray, s: int) -> np.ndarray:
    """The signed distance field of a supersampled mask, reduced s times:
    0.5 on the edge (as uint8 128), DISTANCE_SPREAD pixels to 0 or 1. The
    distance steps out one neighbor at a time, alternating square and
    cross-shaped steps (an octagon: close enough to round)."""
    spread = int(np.ceil(DISTANCE_SPREAD * s))
    inside = _steps(mask, spread)
    outside = _steps(~mask, spread)
    signed = np.where(mask, inside - 0.5, 0.5 - outside) / s  # output pixels
    h, w = mask.shape
    reduced = signed.reshape(h // s, s, w // s, s).mean(axis=(1, 3))
    return np.round(np.clip(0.5 + reduced / (2.0 * DISTANCE_SPREAD), 0.0, 1.0) * 255).astype(np.uint8)


def _steps(mask: np.ndarray, limit: int) -> np.ndarray:
    """How many steps each pixel of `mask` is from its outside (up to limit)."""
    distance = np.full(mask.shape, float(limit))
    current = mask.copy()
    for step in range(limit):
        shrunk = current.copy()
        shrunk[1:, :] &= current[:-1, :]
        shrunk[:-1, :] &= current[1:, :]
        shrunk[:, 1:] &= current[:, :-1]
        shrunk[:, :-1] &= current[:, 1:]
        if step % 2 == 0:
            shrunk[1:, 1:] &= current[:-1, :-1]
            shrunk[:-1, :-1] &= current[1:, 1:]
            shrunk[1:, :-1] &= current[:-1, 1:]
            shrunk[:-1, 1:] &= current[1:, :-1]
        distance[current & ~shrunk] = step + 1
        current = shrunk
        if not current.any():
            break
    return np.where(mask, distance, 0.0)


if __name__ == "__main__":
    if sys.argv[1:] == ["build"]:
        build()
    else:
        print(__doc__)
