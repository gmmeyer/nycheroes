"""Street name signs: the green blades at every intersection and the signs on
traffic signals' mast arms, with the real streets' names on them, and the
textures the game draws the names from (shaders/street_sign.gdshader).

The names come from the street centerlines (CSCL's full_street_name, like
"W 42 ST"), written as the city's mixed-case signs write them ("W 42 St",
"Lexington Av", "Beach 116 St"; sign_text()). Ramps, connectors and other
roads that aren't streets get no signs.

Two textures (assets/signs), built by `build` from the raw data:
- street_glyphs.png: the sign typeface's printable ASCII characters as a
  signed distance field (one channel, 0.5 on a letter's edge, more inside,
  DISTANCE_SPREAD pixels either way), GLYPH_COLUMNS to a row of GLYPH_CELL
  cells, each with its character's pen origin GLYPH_ORIGIN pixels from the
  cell's left and top (on the baseline), GLYPH_EM pixels to the em. Overpass
  Bold (SIL Open Font License, Google Fonts), after the signs' Highway
  Gothic; rendered letters aren't the font's software, so the font itself
  stays out of the game (`build` downloads it to data/raw/fonts).
- street_names.png: every name's characters, SLOTS texels a name,
  NAMES_PER_ROW names to a row (name k at texel (k % NAMES_PER_ROW * SLOTS,
  k // NAMES_PER_ROW)). Texel i of a name is (its i-th character's glyph:
  1 + the cell's index, or 0 past the end; and the pen's x there, in 1/256
  em, high byte then low byte; 255): so the slot after the last character
  holds the name's width, and so do the empty ones after it, which lets the
  shader find the character under a point by bisection.
The names' ids are their lines in street_names.txt ("text<TAB>width in
em"), written with the textures: the tiles use those ids, so tiles and
textures must come from the same list.

Signs in the tiles (common.PROP_STREET_SIGN, see common.py): at the
corners of each intersection of two or more named streets, a post with a
blade for each of the two streets meeting there, at every other corner (two
diagonally opposite corners of a crossing, one of a T); and on every
traffic signal's mast arm, a bigger sign naming the street its drivers are
coming up to.

Usage: python street_signs.py build    (with tools/citygen's Python)
"""

import json
import sys
import urllib.request

import numpy as np
import shapely

from common import (PROP_STREET_SIGN, RAW_DIR, ROOT, STREET_SIGN_BLADE, STREET_SIGN_OVERHEAD, STREET_SIGN_POST,
                    load_features)

FONT_FILE = "Overpass-Bold.ttf"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/overpass/Overpass%5Bwght%5D.ttf"
FONT_WEIGHT = 700
FONT_DIR = RAW_DIR / "fonts"
ASSET_DIR = ROOT / "assets" / "signs"
GLYPHS_PATH = ASSET_DIR / "street_glyphs.png"
TABLE_PATH = ASSET_DIR / "street_names.png"
NAMES_PATH = ASSET_DIR / "street_names.txt"

# The glyph atlas (pixels). Same numbers in the shader.
FIRST_CHAR, LAST_CHAR = 32, 126
GLYPH_COLUMNS = 16
GLYPH_CELL = (64, 72)
GLYPH_ORIGIN = (8, 54)
GLYPH_EM = 48
DISTANCE_SPREAD = 6.0
SUPERSAMPLE = 4
# The names table. Same numbers in the shader.
SLOTS = 32
NAMES_PER_ROW = 64
POSITION_SCALE = 256.0   # the pen's x in 1/256 em

# How signs write the centerlines' words (which are abbreviated, upper case).
WORDS = {
    "ST": "St", "AVE": "Av", "AV": "Av", "PL": "Pl", "RD": "Rd", "CT": "Ct", "LN": "Ln", "DR": "Dr",
    "BCH": "Beach", "BLVD": "Blvd", "BL": "Blvd", "TER": "Ter", "CIR": "Cir", "PKWY": "Pkwy", "PLZ": "Plaza",
    "CRES": "Cres", "SQ": "Sq", "ALY": "Alley", "EXPY": "Expy", "EXPWY": "Expy", "EP": "Expy", "BRG": "Bridge",
    "BRDG": "Bridge", "GRN": "Green", "HWY": "Hwy", "TPKE": "Tpke", "FT": "Ft", "MT": "Mt", "HTS": "Hts",
    "MC": "Mc", "SR": "Service Rd", "VLG": "Village",
}
# Small words, in lower case between others.
SMALL_WORDS = {"OF", "THE", "AND", "AT", "ON", "IN"}
# Kept in capitals.
CAPITALS = {"JFK", "LGA", "USS", "FDR", "II", "III", "IV", "NYC", "US", "PS", "MLK"}
# Names with any of these words aren't streets with signs (ramps,
# connectors, airport roads, paths).
NOT_STREETS = {"EN", "EX", "EB", "WB", "NB", "SB", "EXIT", "ENTRANCE", "CONNECTOR", "ACCESS", "DRIVEWAY", "TO",
               "RAMP", "ET", "ARRIVALS", "DEPARTURES", "TERMINAL", "PED", "PATH", "BIKE", "LOT", "UNNAMED"}

# Roadway type (CSCL rw_type) of streets, and status of built ones.
STREET = "1"
BUILT = "2"

# Sizes (m). Blades: their height, the letters' em and the margin either side
# of the name, as long as the name needs between BLADE_LENGTH (squeezing
# longer names); on a post this tall, the two blades one over the other
# BLADE_GAP apart (the lower one on the post's top). Mast arm signs: bigger,
# hung under the arm centered ARM_REACH out from the pole, their top at
# ARM_SIGN_TOP.
BLADE_HEIGHT = 0.36
BLADE_EM = 0.25
BLADE_MARGIN = 0.12
BLADE_LENGTH = (0.75, 2.2)
POST_HEIGHT = 2.75
BLADE_GAP = 0.04
OVERHEAD_HEIGHT = 0.5
OVERHEAD_EM = 0.36
OVERHEAD_MARGIN = 0.15
OVERHEAD_LENGTH = (1.2, 2.5)
ARM_REACH = 1.95
ARM_SIGN_TOP = 5.7
# Posts stand this far onto the sidewalk from both curb lines (where the
# centerlines' widths put them), moved further in along the corner's middle
# (STEP at a time, up to MAX_PUSH) while that's still in the road (a rounded
# curb); corners narrower or wider than CORNER_ANGLE get none.
CURB_SETBACK = 0.7
STEP = 0.5
MAX_PUSH = 5.0
CORNER_ANGLE = (np.radians(30.0), np.radians(150.0))
# Two ends of a node whose streets head within this angle of opposite ways
# are one street going on (markings.CONTINUING).
CONTINUING = np.cos(np.radians(35.0))


def sign_text(name: str) -> str | None:
    """How a street sign writes the centerline's name (None: no sign)."""
    words = name.upper().split()
    if not words or NOT_STREETS & set(words):
        return None
    out = []
    for i, word in enumerate(words):
        if word in WORDS:
            out.append(WORDS[word])
        elif word in CAPITALS or len(word) == 1 or any(c.isdigit() for c in word):
            out.append(word)
        elif word in SMALL_WORDS and 0 < i < len(words) - 1:
            out.append(word.lower())
        else:
            out.append("-".join(_capitalized(part) for part in word.split("-")))
    return " ".join(out)


def _capitalized(word: str) -> str:
    """A word in title case, with McX, O'X and D'X capitalized after the prefix."""
    out = word[:1] + word[1:].lower()
    if out.startswith("Mc") and len(out) > 2:
        out = "Mc" + out[2:].capitalize()
    if len(out) > 2 and out[1] == "'":
        out = out[:2] + out[2:].capitalize()
    return out


def raw_names() -> dict[int, str]:
    """Every centerline segment's sign text (physicalid -> text), for those
    that have one."""
    with open(RAW_DIR / "centerline_names.json", encoding="utf-8") as f:
        rows = json.load(f)
    out = {}
    for row in rows:
        text = sign_text(" ".join(str(row.get("full_street_name") or "").split()))
        if text:
            out[int(row["physicalid"])] = text
    return out


def load_names() -> tuple[dict[str, int], np.ndarray]:
    """The names' ids (text -> id) and widths (em), from street_names.txt."""
    ids, widths = {}, []
    with open(NAMES_PATH, encoding="utf-8") as f:
        for line in f:
            text, width = line.rstrip("\n").split("\t")
            ids[text] = len(widths)
            widths.append(float(width))
    return ids, np.array(widths)


def segment_names(physicalids: np.ndarray) -> np.ndarray:
    """Each centerline segment's name id (-1: no sign)."""
    ids, _ = load_names()
    texts = raw_names()
    return np.array([ids.get(texts.get(int(p), ""), -1) for p in physicalids], dtype=np.int32)


def build() -> None:
    """Writes the glyph atlas, the names table and the names list from the
    streets at street level in the raw centerline data."""
    from PIL import Image, ImageDraw, ImageFont

    font_path = FONT_DIR / FONT_FILE
    if not font_path.exists():
        FONT_DIR.mkdir(parents=True, exist_ok=True)
        print(f"downloading {FONT_FILE}", flush=True)
        urllib.request.urlretrieve(FONT_URL, font_path)
    font = ImageFont.truetype(str(font_path), GLYPH_EM * SUPERSAMPLE)
    font.set_variation_by_axes([FONT_WEIGHT])

    texts = raw_names()
    used = set()
    for feat in load_features("centerline"):
        p = feat["properties"]
        if p.get("rw_type") == STREET and p.get("status", BUILT) == BUILT:
            text = texts.get(int(p["physicalid"]))
            if text:
                used.add(text)
    names = sorted(t for t in used if len(t) < SLOTS and all(FIRST_CHAR <= ord(c) <= LAST_CHAR for c in t))

    # Glyphs: each character's pen origin at GLYPH_ORIGIN in its cell.
    s = SUPERSAMPLE
    count = LAST_CHAR - FIRST_CHAR + 1
    rows = (count + GLYPH_COLUMNS - 1) // GLYPH_COLUMNS
    atlas = np.zeros((rows * GLYPH_CELL[1], GLYPH_COLUMNS * GLYPH_CELL[0]), np.uint8)
    for index in range(count):
        big = Image.new("L", (GLYPH_CELL[0] * s, GLYPH_CELL[1] * s), 0)
        ImageDraw.Draw(big).text((GLYPH_ORIGIN[0] * s, GLYPH_ORIGIN[1] * s), chr(FIRST_CHAR + index), font=font,
                                 fill=255, anchor="ls")
        field = _distance_field(np.asarray(big) > 127, s)
        row, column = divmod(index, GLYPH_COLUMNS)
        atlas[row * GLYPH_CELL[1]:(row + 1) * GLYPH_CELL[1], column * GLYPH_CELL[0]:(column + 1) * GLYPH_CELL[0]] = field
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "L").save(GLYPHS_PATH, optimize=True)

    # Names: glyphs and pen positions.
    em = GLYPH_EM * s
    table = np.zeros(((len(names) + NAMES_PER_ROW - 1) // NAMES_PER_ROW, NAMES_PER_ROW * SLOTS, 4), np.uint8)
    table[..., 3] = 255
    widths = []
    for k, text in enumerate(names):
        pen = [font.getlength(text[:i]) / em for i in range(len(text) + 1)]
        at = np.round(np.array(pen) * POSITION_SCALE).astype(np.int64)
        at = np.concatenate([at, np.full(SLOTS - len(at), at[-1])])
        row, column = divmod(k, NAMES_PER_ROW)
        cells = table[row, column * SLOTS:(column + 1) * SLOTS]
        cells[:len(text), 0] = [ord(c) - FIRST_CHAR + 1 for c in text]
        cells[:, 1] = at >> 8
        cells[:, 2] = at & 255
        widths.append(pen[-1])
    Image.fromarray(table, "RGBA").save(TABLE_PATH, optimize=True)
    with open(NAMES_PATH, "w", encoding="utf-8", newline="\n") as f:
        for text, width in zip(names, widths):
            f.write(f"{text}\t{width:.4f}\n")
    print(f"{len(names)} names -> {TABLE_PATH} ({TABLE_PATH.stat().st_size // 1024} kB), "
          f"glyphs -> {GLYPHS_PATH} ({GLYPHS_PATH.stat().st_size // 1024} kB)")


def _distance_field(mask: np.ndarray, s: int) -> np.ndarray:
    """The signed distance field of a supersampled mask, reduced s times (as
    sign_names._distance_field, with this file's spread)."""
    import sign_names
    spread = int(np.ceil(DISTANCE_SPREAD * s))
    inside = sign_names._steps(mask, spread)
    outside = sign_names._steps(~mask, spread)
    signed = np.where(mask, inside - 0.5, 0.5 - outside) / s
    h, w = mask.shape
    reduced = signed.reshape(h // s, s, w // s, s).mean(axis=(1, 3))
    return np.round(np.clip(0.5 + reduced / (2.0 * DISTANCE_SPREAD), 0.0, 1.0) * 255).astype(np.uint8)


def blade_length(width_em: np.ndarray, em: float, margin: float, limits: tuple) -> np.ndarray:
    """How long a sign is for names `width_em` wide (m)."""
    return np.clip(np.asarray(width_em) * em + 2.0 * margin, *limits)


def _props(en, height, width, yaw, variant, name) -> dict:
    """Signs as props (build_tiles' layout): name ids split for half floats
    (see common.PROP_STREET_SIGN)."""
    name = np.asarray(name, dtype=np.int64)
    return {"en": np.asarray(en, dtype=np.float64).reshape(-1, 2), "type": np.full(len(name), PROP_STREET_SIGN, np.int8),
            "tone": (np.asarray(variant) + 4 * (name >> 10)).astype(np.int16), "trunk": (name & 1023).astype(np.float64),
            "height": np.asarray(height, dtype=np.float64), "width": np.asarray(width, dtype=np.float64),
            "yaw": np.asarray(yaw, dtype=np.float64), "seed": np.zeros(len(name))}


def _ends(data: dict, segments: np.ndarray, names: np.ndarray) -> dict:
    """The ends of these segments at crossings, by node: node -> list of
    (segment, at its start, unit direction into the segment, half width,
    name id)."""
    from markings import DEFAULT_HALF_WIDTH, LANE_WIDTH, PARKING_WIDTH
    out = {}
    for k in segments:
        k = int(k)
        line = data["lines"][k]
        length = line.length
        step = min(3.0, length / 2)
        width = float(data["width"][k])
        lanes = int(data["lanes"][k])
        half = width / 2 if width > 0 else ((lanes * LANE_WIDTH + int(data["parking"][k]) * PARKING_WIDTH) / 2
                                            if lanes > 0 else DEFAULT_HALF_WIDTH)
        coords = np.asarray(line.coords)[:, :2]
        for end, at_start in ((0, True), (1, False)):
            if not data["crossing"][k][end]:
                continue
            point = coords[0] if at_start else coords[-1]
            toward = np.asarray(line.interpolate(step if at_start else length - step).coords[0][:2]) - point
            toward /= max(np.linalg.norm(toward), 1e-9)
            street = int(data["rw"][k]) == 1
            out.setdefault(int(data["nodes"][k][end]), []).append(
                (k, at_start, toward, half, int(names[k]) if street else -1, point))
    return out


def corner_signs(data: dict, names: np.ndarray, widths: np.ndarray, segments: np.ndarray, center_box,
                 road) -> dict:
    """Sign posts at the corners of the intersections inside center_box
    (min_e, min_n, max_e, max_n) among these segments (all of each node's
    segments must be among them), as props: per post its lower blade with
    the post (STREET_SIGN_POST) and the upper one (STREET_SIGN_BLADE).
    `names` are the segments' name ids, `widths` the names' widths (em),
    `road` the (prepared) road surface around."""
    min_e, min_n, max_e, max_n = center_box
    en, height, length, yaw, variant, name = [], [], [], [], [], []
    for node, ends in sorted(_ends(data, segments, names).items()):
        point = ends[0][5]
        if not (min_e <= point[0] < max_e and min_n <= point[1] < max_n) or len(ends) < 3:
            continue
        if len({e[4] for e in ends if e[4] >= 0}) < 2:
            continue
        # The corners between neighboring ends, going around; those between
        # two different named streets get a post, but no two next to each
        # other (starting at one picked by the node, so it varies).
        ends = sorted(ends, key=lambda e: np.arctan2(e[2][1], e[2][0]))
        corners = []
        for i in range(len(ends)):
            a, b = ends[i], ends[(i + 1) % len(ends)]
            angle = np.arctan2(a[2][0] * b[2][1] - a[2][1] * b[2][0], a[2] @ b[2]) % (2 * np.pi)
            corners.append(a[4] >= 0 and b[4] >= 0 and a[4] != b[4] and CORNER_ANGLE[0] <= angle <= CORNER_ANGLE[1])
        taken = np.zeros(len(ends), dtype=bool)
        start = node % len(ends)
        for offset in range(len(ends)):
            i = (start + offset) % len(ends)
            if not corners[i] or taken[i] or taken[(i - 1) % len(ends)] or taken[(i + 1) % len(ends)]:
                continue
            a, b = ends[i], ends[(i + 1) % len(ends)]
            spot = _corner_spot(point, a, b, road)
            if spot is None:
                continue
            taken[i] = True
            # The wider street's blade on top.
            low, high = (a, b) if a[3] <= b[3] else (b, a)
            for end, kind, top in ((low, STREET_SIGN_POST, POST_HEIGHT + BLADE_HEIGHT),
                                   (high, STREET_SIGN_BLADE, POST_HEIGHT + 2 * BLADE_HEIGHT + BLADE_GAP)):
                en.append(spot)
                height.append(top)
                length.append(blade_length(widths[end[4]], BLADE_EM, BLADE_MARGIN, BLADE_LENGTH))
                # The blade runs along its street (its +x along the end's direction).
                yaw.append(np.arctan2(end[2][1], end[2][0]))
                variant.append(kind)
                name.append(end[4])
    return _props(en, height, length, yaw, variant, name)


def _corner_spot(point: np.ndarray, a: tuple, b: tuple, road):
    """Where a corner's post stands: CURB_SETBACK onto the sidewalk from both
    streets' curbs, further in if that's in the road (None if it stays so)."""
    u, v = a[2], b[2]
    sine = abs(u[0] * v[1] - u[1] * v[0])
    # Off a's street by b's coefficient, and the other way round.
    spot = point + u * ((b[3] + CURB_SETBACK) / sine) + v * ((a[3] + CURB_SETBACK) / sine)
    middle = (u + v) / max(np.linalg.norm(u + v), 1e-9)
    for push in np.arange(0.0, MAX_PUSH + 1e-6, STEP):
        here = spot + middle * push
        if not shapely.contains_xy(road, here[0], here[1]):
            return here
    return None


def cross_streets(data: dict, names: np.ndarray, segments: np.ndarray, ends: np.ndarray) -> np.ndarray:
    """For signals at these (segment, end) pairs, the name id of the widest
    street their drivers come up to (-1: none named): of the other ends at
    the node, those not continuing the signal's street, with another name."""
    by_node = _ends(data, segments, names)
    out = np.full(len(ends), -1, dtype=np.int32)
    for n, (k, end) in enumerate(ends):
        here = by_node.get(int(data["nodes"][k][end]), [])
        own = next((e for e in here if e[0] == k and e[1] == (end == 0)), None)
        if own is None:
            continue
        best = -1.0
        for e in here:
            if e[0] == k or e[4] < 0 or e[4] == names[k] or e[2] @ own[2] < -CONTINUING:
                continue
            if e[3] > best:
                best, out[n] = e[3], e[4]
    return out


def overhead_signs(points: np.ndarray, facing: np.ndarray, names: np.ndarray, widths: np.ndarray) -> dict:
    """Signs on the mast arms of traffic signals at (N, 2) points facing
    along (N, 2) `facing` (toward their drivers), naming `names` (ids). Each
    hangs under its arm, ARM_REACH out over the road."""
    yaw = np.arctan2(facing[:, 0], -facing[:, 1])
    return _props(points - ARM_REACH * _along(yaw), np.full(len(names), ARM_SIGN_TOP),
                  blade_length(widths[names], OVERHEAD_EM, OVERHEAD_MARGIN, OVERHEAD_LENGTH), yaw,
                  np.full(len(names), STREET_SIGN_OVERHEAD), names)


def arm_poles(en: np.ndarray, yaw: np.ndarray) -> np.ndarray:
    """The poles whose arms mast arm signs at (N, 2) `en` with these yaws
    hang from."""
    return en + ARM_REACH * _along(yaw)


def _along(yaw: np.ndarray) -> np.ndarray:
    """A prop's +x in east/north (PropMeshes' mast arm reaches along -x)."""
    return np.column_stack([np.cos(yaw), np.sin(yaw)])

if __name__ == "__main__":
    if sys.argv[1:] == ["build"]:
        build()
    else:
        print(__doc__)
