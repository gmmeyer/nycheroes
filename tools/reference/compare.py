"""Reference views: real photos next to the game at the same camera pose.

Downloads any missing reference photo from Wikimedia Commons, screenshots the
game at every view's ?cam= pose (shoot.mjs, headless Chrome), and writes
side-by-side images, photo | game, cropped to the same field of view.

    tools/citygen/.venv/Scripts/python.exe tools/reference/compare.py
        [--site https://nycheroes.party/index.html]   # or a local build URL
        [--label NAME]       # output folder name (default: <host>-<date>)
        [--only a,b]         # just these views
        [--skip-shots]       # reuse the screenshots already under --label
        [--also LABEL[,LABEL]]  # add earlier runs' screenshots as middle columns
        [--chrome PATH] [--width 2560] [--height 1440] [--port 9384]
        [--profile DIR]      # keep Chrome's cache here between runs
        [--query weather=overcast]  # launch options added to every view

    compare.py --pose LAT,LON,HEADING[,PITCH[,EYE]]
        prints the ?cam= pose for a photo taken at LAT,LON looking toward
        HEADING (degrees clockwise from north), EYE meters above the ground
        (default 1.6; needs pyproj, and data/cache/terrain.npy for the ground).

Writes build/reference/photos/<view>.jpg (never committed),
build/reference/shots/<label>/<view>.png and
build/reference/compare/<label>/<view>.jpg plus _all.jpg (every view), and
measures.md / measures.json there: brightness, contrast, saturation, masonry
and foliage share, edge density and sky color of the photo and each game
crop (see MEASURES).
Needs Pillow (the citygen venv has it; --pose also uses its pyproj and numpy)
and Node 22+ (shoot.mjs uses its built-in WebSocket).
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import math
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = ROOT / "build" / "reference"
API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "NYCHeroesReference/1.0 (https://nycheroes.party; reference photo comparison)"
PHOTO_WIDTH = 2560  # download size (Commons thumbnail), plenty for a 1000 px panel
PANEL_HEIGHT = 1000
DEFAULT_CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe"


def load_views() -> dict:
    return json.loads((HERE / "views.json").read_text(encoding="utf-8"))


def http_get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def download_photo(view: dict, folder: Path) -> Path:
    path = folder / f"{view['name']}.jpg"
    if path.exists():
        return path
    title = view["photo"]["file"]
    query = urllib.parse.urlencode({
        "action": "query", "format": "json", "formatversion": "2", "titles": title,
        "prop": "imageinfo", "iiprop": "url", "iiurlwidth": str(PHOTO_WIDTH)})
    info = json.loads(http_get(f"{API}?{query}"))
    page = info["query"]["pages"][0]
    if "imageinfo" not in page:
        raise SystemExit(f"{view['name']}: {title} not found on Commons")
    image = page["imageinfo"][0]
    data = http_get(image.get("thumburl") or image["url"])
    folder.mkdir(parents=True, exist_ok=True)
    Image.open(io.BytesIO(data)).convert("RGB").save(path, quality=92)
    print(f"downloaded {view['name']} <- {title}")
    return path


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    for name in (("arialbd.ttf", "DejaVuSans-Bold.ttf") if bold else ("arial.ttf", "DejaVuSans.ttf")):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default(size)


def tangent_extent(size, f: float, center: tuple[float, float]) -> list[float]:
    """Left, top, right, bottom edges of an image as tangents of the angle
    off its optical axis, which crosses the image at `center` (pixels)."""
    w, h = size
    cx, cy = center
    return [-cx / f, -cy / f, (w - cx) / f, (h - cy) / f]


def avoid_hud(rect: list[float], game_size, fg: float, hud_boxes) -> list[float]:
    """Shrinks the shared view (tangents, game camera on the screen center)
    until it misses the game's HUD boxes, moving whichever edge loses least."""
    w, h = game_size
    for box in hud_boxes:
        # box: [x0, y0, x1, y1] in screen pixels; negative counts from the right/bottom
        x0, y0, x1, y1 = [(v + (w if i % 2 == 0 else h)) if v < 0 else v for i, v in enumerate(box)]
        b = [(x0 - w / 2) / fg, (y0 - h / 2) / fg, (x1 - w / 2) / fg, (y1 - h / 2) / fg]
        l, t, r, bt = rect
        if l >= b[2] or r <= b[0] or t >= b[3] or bt <= b[1]:
            continue
        options = [[b[2], t, r, bt], [l, b[3], r, bt], [l, t, b[0], bt], [l, t, r, b[1]]]
        options = [o for o in options if o[2] > o[0] and o[3] > o[1]]
        rect = max(options, key=lambda o: (o[2] - o[0]) * (o[3] - o[1]))
    return rect


def crop(image: Image.Image, f: float, center: tuple[float, float], rect: list[float]) -> Image.Image:
    cx, cy = center
    return image.crop((round(cx + rect[0] * f), round(cy + rect[1] * f),
                       round(cx + rect[2] * f), round(cy + rect[3] * f)))


MEASURES = {
    # name: (what it is, number format)
    "lower_v": ("mean value (HSV) of the lower half: buildings and street", "{:.2f}"),
    "lower_v_sd": ("spread (std dev) of value in the lower half: contrast, shade", "{:.2f}"),
    "lower_s": ("mean saturation of the lower half", "{:.2f}"),
    "warm_s": ("median saturation of warm pixels (hue under 50 deg: brick, brownstone, tan) in the lower half", "{:.2f}"),
    "warm": ("share of the lower half that is warm (masonry)", "{:.2f}"),
    "green": ("share of the frame that is green (foliage, lawn)", "{:.2f}"),
    "edges": ("share of the lower half on a strong edge (detail and clutter; 480 px high)", "{:.3f}"),
    "top": ("median color of the top 5% of the frame (sky where there is sky)", "{}"),
}


def measure(image: Image.Image) -> dict:
    """A few numbers that say how a panel looks, comparable between the photo
    and the game crops (same field of view): brightness and contrast of the
    lower half, saturation, how much is masonry or foliage, how busy it is,
    and the sky color at the top."""
    import numpy as np

    small = image.resize((max(1, round(image.width * 480 / image.height)), 480), Image.BILINEAR)
    hsv = np.asarray(small.convert("HSV"), dtype=np.float32) / 255.0
    rgb = np.asarray(small, dtype=np.float32)
    hue, sat, val = hsv[..., 0] * 360.0, hsv[..., 1], hsv[..., 2]
    lower = slice(small.height // 2, small.height)
    warm = ((hue < 50) | (hue > 340)) & (sat > 0.08) & (val > 0.12) & (val < 0.92)
    green = (hue > 60) & (hue < 170) & (sat > 0.18) & (val > 0.08)
    gray = np.asarray(small.convert("L"), dtype=np.float32)[lower] / 255.0
    grad = np.zeros_like(gray)
    grad[:-1, :-1] = np.abs(np.diff(gray, axis=1))[:-1] + np.abs(np.diff(gray, axis=0))[:, :-1]
    top = np.median(rgb[: max(2, small.height // 20)].reshape(-1, 3), axis=0)
    warm_lower = warm[lower]
    return {
        "lower_v": float(val[lower].mean()),
        "lower_v_sd": float(val[lower].std()),
        "lower_s": float(sat[lower].mean()),
        "warm_s": float(np.median(sat[lower][warm_lower])) if warm_lower.any() else 0.0,
        "warm": float(warm_lower.mean()),
        "green": float(green.mean()),
        "edges": float((grad > 0.12).mean()),
        "top": "#%02X%02X%02X" % tuple(int(round(c)) for c in top),
    }


def write_measures(results: dict, columns: list[str], out_dir: Path) -> None:
    """measures.json plus measures.md (one table per measure: a row per view,
    a column for the photo and each game run, and the mean over views). Views
    measured earlier into the same folder (an --only run) keep their rows."""
    path = out_dir / "measures.json"
    if path.exists():
        earlier = json.loads(path.read_text(encoding="utf-8"))
        results = {view: results.get(view, values) for view, values in earlier.items()} | results
    path.write_text(json.dumps(results, indent=1), encoding="utf-8")
    lines = ["# Measured values", "",
             "Photo and game crops over the same field of view (`compare.py`).", ""]
    # Means only over the views every column has, so the columns compare.
    common = [view for view, values in results.items() if all(c in values for c in columns)]
    for key, (about, fmt) in MEASURES.items():
        lines += [f"## {key}: {about}", "", "| View | " + " | ".join(columns) + " |",
                  "|---|" + "---|" * len(columns)]
        for view, values in results.items():
            cells = [fmt.format(values[c][key]) if c in values else "" for c in columns]
            lines.append(f"| {view} | " + " | ".join(cells) + " |")
        if key != "top" and common:
            lines.append(f"| **mean of {len(common)}** | " + " | ".join(
                fmt.format(sum(results[v][c][key] for v in common) / len(common)) for c in columns) + " |")
        lines.append("")
    (out_dir / "measures.md").write_text("\n".join(lines), encoding="utf-8")
    print("wrote", out_dir / "measures.md")


def compose(view: dict, photo_path: Path, shots: list[tuple[str, Path]], game: dict, out_path: Path,
            measures: dict | None = None) -> Path:
    """Photo | game side by side over the field of view both cover. The photo's
    optical axis crosses it at view.photo.principal (fractions, default the
    center; perspective-corrected photos have it at the horizon), the game's
    at the screen center. Fills `measures` (photo and each shot) if given."""
    photo = Image.open(photo_path).convert("RGB")
    frames = [Image.open(p).convert("RGB") for _, p in shots]
    vfov = game["vfov"]
    info = view["photo"]
    fp = (photo.width / 2) / math.tan(math.radians(info["hfov"] / 2))
    px, py = info.get("principal", [0.5, 0.5])
    pcenter = (px * photo.width, py * photo.height)
    rect = tangent_extent(photo.size, fp, pcenter)
    g = frames[0]
    fg = (g.height / 2) / math.tan(math.radians(vfov / 2))
    gext = tangent_extent(g.size, fg, (g.width / 2, g.height / 2))
    rect = [max(rect[0], gext[0]), max(rect[1], gext[1]), min(rect[2], gext[2]), min(rect[3], gext[3])]
    rect = avoid_hud(rect, g.size, fg, game.get("hud_boxes", []))
    panels = [crop(photo, fp, pcenter, rect)]
    for f in frames:
        ff = (f.height / 2) / math.tan(math.radians(vfov / 2))
        panels.append(crop(f, ff, (f.width / 2, f.height / 2), rect))
    pw = round(PANEL_HEIGHT * (rect[2] - rect[0]) / (rect[3] - rect[1]))
    panels = [p.resize((pw, PANEL_HEIGHT), Image.LANCZOS) for p in panels]
    if measures is not None:
        for name, panel in zip(["photo"] + [n.split(" (")[0] for n, _ in shots], panels):
            measures[name] = measure(panel)

    gap, head, foot = 8, 64, 58
    sheet = Image.new("RGB", (len(panels) * pw + (len(panels) - 1) * gap, head + PANEL_HEIGHT + foot), (24, 24, 28))
    for i, p in enumerate(panels):
        sheet.paste(p, (i * (pw + gap), head))
    draw = ImageDraw.Draw(sheet)
    fov_h = math.degrees(math.atan(rect[2]) - math.atan(rect[0]))
    draw.text((14, 10), f"{view['name']} - {view['title']}", fill=(255, 255, 255), font=font(26, True))
    draw.text((14, 40), f"?cam={view['cam']}    field of view shown: {fov_h:.0f} deg wide",
              fill=(190, 190, 200), font=font(17))
    labels = [f"PHOTO {info.get('date', '')[:10]}: {info['author']}, {info['license']} (Wikimedia Commons)"]
    labels += [f"GAME {name}" for name, _ in shots]
    small = font(17)
    for i, text in enumerate(labels):
        draw.text((i * (pw + gap) + 12, head + PANEL_HEIGHT + 8), text, fill=(235, 235, 235), font=small)
    draw.text((12, head + PANEL_HEIGHT + 32), info["page"], fill=(150, 170, 220), font=font(14))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, quality=90)
    return out_path


def contact_sheet(paths: list[Path], out_path: Path) -> None:
    thumbs = []
    for p in paths:
        im = Image.open(p)
        im.thumbnail((1400, 700))
        thumbs.append(im)
    if not thumbs:
        return
    cw = max(t.width for t in thumbs)
    ch = max(t.height for t in thumbs)
    cols = 2
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * cw, rows * ch), (24, 24, 28))
    for i, t in enumerate(thumbs):
        sheet.paste(t, ((i % cols) * cw, (i // cols) * ch))
    sheet.save(out_path, quality=85)


def print_pose(spec: str) -> None:
    """?cam= for a camera at lat, lon looking toward a compass heading."""
    from pyproj import Transformer  # citygen venv
    import numpy as np

    values = [float(v) for v in spec.split(",")]
    lat, lon, heading = values[:3]
    pitch = values[3] if len(values) > 3 else 0.0
    eye = values[4] if len(values) > 4 else 1.6
    manifest = load_views()["game"]["projection"]
    east, north = Transformer.from_crs("EPSG:4326", manifest, always_xy=True).transform(lon, lat)
    ground = 0.0
    grid = ROOT / "data" / "cache" / "terrain.npy"
    if grid.exists():
        meta = json.loads(grid.with_suffix(".json").read_text())
        heights = np.load(grid, mmap_mode="r")
        row = int(round((meta["max_n"] - north) / meta["spacing"]))
        column = int(round((east - meta["min_e"]) / meta["spacing"]))
        ground = max(float(heights[row, column]), 0.0)
    else:
        print("(no data/cache/terrain.npy: height is above sea level, not above the ground)")
    yaw = (-heading + 180.0) % 360.0 - 180.0
    print(f"ground {ground:.1f} m")
    print(f"cam={east:.0f},{ground + eye:.1f},{-north:.0f},{yaw:.1f},{pitch:.1f}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--site", default="https://nycheroes.party/index.html")
    parser.add_argument("--label")
    parser.add_argument("--only")
    parser.add_argument("--skip-shots", action="store_true")
    parser.add_argument("--also", help="earlier labels (comma-separated) whose screenshots go in middle columns")
    parser.add_argument("--chrome", default=DEFAULT_CHROME)
    parser.add_argument("--width", type=int, default=2560)
    parser.add_argument("--height", type=int, default=1440)
    parser.add_argument("--port", type=int, default=9384)
    parser.add_argument("--settle", type=int, default=6000)
    parser.add_argument("--profile", help="Chrome profile folder to reuse (keeps its cache)")
    parser.add_argument("--query", help="launch options added to every view, e.g. weather=overcast or time=19:00")
    parser.add_argument("--pose", help="LAT,LON,HEADING[,PITCH[,EYE]]: print a ?cam= pose and exit")
    args = parser.parse_args()
    if args.pose:
        print_pose(args.pose)
        return

    config = load_views()
    views = config["views"]
    if args.only:
        wanted = set(args.only.split(","))
        views = [v for v in views if v["name"] in wanted]
    host = urllib.parse.urlparse(args.site).hostname or "site"
    label = args.label or f"{host.split('.')[0]}-{dt.date.today():%Y%m%d}"

    for view in views:
        download_photo(view, OUT / "photos")

    shot_dir = OUT / "shots" / label
    if not args.skip_shots:
        command = ["node", str(HERE / "shoot.mjs"), "--chrome", args.chrome, "--url", args.site,
                   "--out", str(shot_dir), "--views", str(HERE / "views.json"),
                   "--width", str(args.width), "--height", str(args.height),
                   "--port", str(args.port), "--settle", str(args.settle)]
        if args.only:
            command += ["--only", args.only]
        if args.profile:
            command += ["--profile", args.profile]
        if args.query:
            command += ["--query", args.query]
        subprocess.run(command, check=True)

    written = []
    results = {}
    earlier = args.also.split(",") if args.also else []
    for view in views:
        shots = []
        for older_label in earlier:
            older = OUT / "shots" / older_label / f"{view['name']}.png"
            if older.exists():
                shots.append((older_label, older))
        current = shot_dir / f"{view['name']}.png"
        if not current.exists():
            print(f"{view['name']}: no screenshot in {shot_dir}", file=sys.stderr)
            continue
        shots.append((f"{label} ({args.site})", current))
        results[view["name"]] = {}
        written.append(compose(view, OUT / "photos" / f"{view['name']}.jpg", shots, config["game"],
                               OUT / "compare" / label / f"{view['name']}.jpg", results[view["name"]]))
        print("wrote", written[-1])
    if written:
        write_measures(results, ["photo"] + earlier + [label], OUT / "compare" / label)
    if written and not args.only:
        contact_sheet(written, OUT / "compare" / label / "_all.jpg")


if __name__ == "__main__":
    main()
