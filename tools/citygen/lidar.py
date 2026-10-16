"""Raised roads' deck heights from the city's 2017 lidar survey (NYC
topobathymetric lidar, flown May 2017, public domain; NOAA's copy as Entwine
point tiles: NAD83(2011) UTM zone 18N, heights above NAVD88). The street
centerlines' level codes only say which road is over which (overpasses.py
counts 7 m a level), but the Gowanus Expressway stands 14 m over Third
Avenue and 31 m over the Gowanus Canal, the Cross Bronx's ramps 20 m up.

prepare() fetches the point tiles around the raised roads, down to DEPTH
(about 0.6 points a square meter: some 80 million points, 290 MB, kept in
data/raw/lidar/), and every STATION_STEP along each raised segment measures
the surfaces within RADIUS of its centerline, above the ground: the deck
(the bridge deck class, else unclassified points) and anything over it
(another road's deck), as layers split by gaps of LAYER_GAP. The survey's
heights are matched to the elevation model's (terrain.py) through the ground
points around (they differ by a meter or so). data/cache/deck_heights.pkl;
overpasses.Network picks each station's layer.
"""

import io
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import shapely
from pyproj import Transformer

from common import PROJECTION, RAW_DIR
from markings import AT_GRADE

SOURCE = "https://noaa-nos-coastal-lidar-pds.s3.amazonaws.com/entwine/geoid18/9306"
SOURCE_CRS = 6347
CACHE = RAW_DIR / "lidar" / "9306"
DEPTH = 7
STATION_STEP = 10.0
RADIUS = 3.0          # points this close to a station's centerline point (m)
LAYER_GAP = 1.5       # surfaces this far apart (vertically) are separate layers
MIN_LAYER = 4         # points that make a layer
MAX_LAYERS = 4
# Classes that can be a deck: unclassified, road surface, bridge deck (ASPRS).
DECK_CLASSES = (1, 11, 17)
BRIDGE_DECK, GROUND = 17, 2
# Deck heights are the bridge deck points' median, or this percentile of the
# layer's points (cars stand on the deck).
DECK_PERCENTILE = 30.0
# Matching the survey to the elevation model: the median difference of their
# ground heights in OFFSET_CELL squares around each station.
OFFSET_CELL = 50.0
GATHER = 30.0         # points this close to any station are kept while reading the tiles
WORKERS = 16


def prepare(roads: dict, terrain) -> dict:
    """{(start, end) keys (to 0.5 m): (distances along, layers (S, MAX_LAYERS)
    in the elevation model's heights, highest first, NaN where none)} for the
    raised segments in overpasses.prepare's `roads`."""
    started = time.time()
    raised = np.flatnonzero(roads["levels"].max(axis=1) > int(AT_GRADE))
    stations, owners, along = [], [], []
    for k in raised:
        line = roads["lines"][k]
        s = np.linspace(0.0, line.length, max(2, int(np.ceil(line.length / STATION_STEP)) + 1))
        stations.append(shapely.get_coordinates(shapely.line_interpolate_point(line, s)))
        owners.append(np.full(len(s), k))
        along.append(s)
    stations, owners, along = np.vstack(stations), np.concatenate(owners), np.concatenate(along)
    to_source = Transformer.from_crs(PROJECTION, SOURCE_CRS, always_xy=True)
    sx, sy = to_source.transform(stations[:, 0], stations[:, 1])
    print(f"  lidar: {len(stations):,} stations on {len(raised):,} raised segments", flush=True)

    points = _gather(np.column_stack([sx, sy]))
    print(f"  lidar: {len(points):,} points near them ({time.time() - started:.0f} s)", flush=True)
    to_local = Transformer.from_crs(SOURCE_CRS, PROJECTION, always_xy=True)
    e, n = to_local.transform(points[:, 0], points[:, 1])
    en = np.column_stack([e, n])
    z, cls = points[:, 2], points[:, 3].astype(np.int64)

    offset = _offsets(en[cls == GROUND], z[cls == GROUND], terrain, stations)
    keep = np.isin(cls, DECK_CLASSES)
    layers = _layers(stations, en[keep], z[keep], cls[keep])
    layers -= offset[:, None]

    out = {}
    for k in raised:
        mine = owners == k
        out[_key(roads["lines"][k])] = (along[mine].astype(np.float32), layers[mine].astype(np.float32))
    found = np.isfinite(layers[:, 0])
    print(f"  lidar: decks measured at {found.mean():.0%} of stations ({time.time() - started:.0f} s)", flush=True)
    return out


def _key(line) -> tuple:
    """A segment's key: its ends and middle to 0.5 m."""
    middle = shapely.get_coordinates(shapely.line_interpolate_point(line, 0.5, normalized=True))
    points = np.vstack([shapely.get_coordinates(line)[[0, -1]], middle])
    return tuple(np.round(points * 2.0).astype(np.int64).ravel().tolist())


def heights(decks: dict, line) -> tuple | None:
    """A raised segment's measured layers (prepare()), or None."""
    return decks.get(_key(line))


def _get(rel: str) -> bytes:
    path = CACHE / rel.replace("/", "_")
    if not path.exists():
        for attempt in range(4):
            try:
                with urllib.request.urlopen(f"{SOURCE}/{rel}", timeout=120) as response:
                    data = response.read()
                break
            except OSError:
                if attempt == 3:
                    raise
                time.sleep(2 + 4 * attempt)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.replace(path)
    return path.read_bytes()


def _gather(stations: np.ndarray) -> np.ndarray:
    """The survey's points (x, y, z, class; the source's coordinates) within
    about GATHER of the stations (source coordinates), down to DEPTH."""
    ept = json.loads(_get("ept.json"))
    bounds = ept["bounds"]
    span = bounds[3] - bounds[0]
    hierarchy = json.loads(_get("ept-hierarchy/0-0-0-0.json"))
    # The nodes over the stations, depth by depth.
    nodes = []
    for depth in range(DEPTH + 1):
        size = span / 2 ** depth
        cells = set()
        for dx in (-GATHER, 0.0, GATHER):
            for dy in (-GATHER, 0.0, GATHER):
                cells |= set(zip(np.floor((stations[:, 0] + dx - bounds[0]) / size).astype(int).tolist(),
                                 np.floor((stations[:, 1] + dy - bounds[1]) / size).astype(int).tolist()))
        for key, count in list(hierarchy.items()):
            d, x, y, _ = map(int, key.split("-"))
            if d != depth or (x, y) not in cells:
                continue
            if count == -1:
                hierarchy.update(json.loads(_get(f"ept-hierarchy/{key}.json")))
                count = hierarchy[key]
            if count > 0:
                nodes.append(key)
    # Points near stations: a grid of GATHER cells around them.
    grid = set()
    cx, cy = np.floor(stations[:, 0] / GATHER).astype(np.int64), np.floor(stations[:, 1] / GATHER).astype(np.int64)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            grid |= set(((cx + dx) * 1_000_000 + (cy + dy)).tolist())
    grid = np.array(sorted(grid), dtype=np.int64)

    def read(key):
        import laspy
        las = laspy.read(io.BytesIO(_get(f"ept-data/{key}.laz")))
        x, y = np.asarray(las.x), np.asarray(las.y)
        cell = np.floor(x / GATHER).astype(np.int64) * 1_000_000 + np.floor(y / GATHER).astype(np.int64)
        near = np.isin(cell, grid)
        return np.column_stack([x[near], y[near], np.asarray(las.z)[near],
                                np.asarray(las.classification)[near]]).astype(np.float64)

    print(f"  lidar: {len(nodes):,} point tiles", flush=True)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        parts = list(pool.map(read, nodes))
    return np.concatenate(parts) if parts else np.zeros((0, 4))


def _offsets(en: np.ndarray, z: np.ndarray, terrain, stations: np.ndarray) -> np.ndarray:
    """How much higher the survey's ground is than the elevation model's
    around each station (the median over OFFSET_CELL squares, the station's
    and its neighbors')."""
    diff = z - terrain.raw(en)
    cells = np.floor(en / OFFSET_CELL).astype(np.int64)
    keys = cells[:, 0] * 1_000_000 + cells[:, 1]
    order = np.argsort(keys)
    keys, diff = keys[order], diff[order]
    unique, starts = np.unique(keys, return_index=True)
    ends = np.append(starts[1:], len(keys))
    medians = {int(k): float(np.median(diff[a:b])) for k, a, b in zip(unique, starts, ends)}
    out = np.zeros(len(stations))
    sc = np.floor(stations / OFFSET_CELL).astype(np.int64)
    for i, (x, y) in enumerate(sc.tolist()):
        around = [medians[k] for k in ((x + dx) * 1_000_000 + y + dy for dx in (-1, 0, 1) for dy in (-1, 0, 1))
                  if k in medians]
        out[i] = float(np.median(around)) if around else 0.0
    return out


def _layers(stations: np.ndarray, en: np.ndarray, z: np.ndarray, cls: np.ndarray) -> np.ndarray:
    """(S, MAX_LAYERS) deck heights at each station (the survey's), highest
    first, NaN where none."""
    out = np.full((len(stations), MAX_LAYERS), np.nan)
    cell = RADIUS
    keys = np.floor(en[:, 0] / cell).astype(np.int64) * 1_000_000 + np.floor(en[:, 1] / cell).astype(np.int64)
    order = np.argsort(keys)
    keys, en, z, cls = keys[order], en[order], z[order], cls[order]
    sx, sy = np.floor(stations[:, 0] / cell).astype(np.int64), np.floor(stations[:, 1] / cell).astype(np.int64)
    ranges = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            k = (sx + dx) * 1_000_000 + (sy + dy)
            ranges.append((np.searchsorted(keys, k, side="left"), np.searchsorted(keys, k, side="right")))
    for i in range(len(stations)):
        picks = [np.arange(lo[i], hi[i]) for lo, hi in ranges if hi[i] > lo[i]]
        if not picks:
            continue
        idx = np.concatenate(picks)
        idx = idx[np.hypot(en[idx, 0] - stations[i, 0], en[idx, 1] - stations[i, 1]) <= RADIUS]
        if len(idx) < MIN_LAYER:
            continue
        idx = idx[np.argsort(z[idx])]
        zz, cc = z[idx], cls[idx]
        cuts = np.flatnonzero(np.diff(zz) > LAYER_GAP) + 1
        found = []
        for part_z, part_c in zip(np.split(zz, cuts), np.split(cc, cuts)):
            if len(part_z) < MIN_LAYER:
                continue
            deck = part_z[part_c == BRIDGE_DECK]
            found.append(float(np.median(deck)) if len(deck) >= 3 else float(np.percentile(part_z, DECK_PERCENTILE)))
        found = sorted(found, reverse=True)[:MAX_LAYERS]
        out[i, :len(found)] = found
    return out
