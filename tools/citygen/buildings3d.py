"""Real building shapes (setbacks, pitched roofs, spires) from the city's 3-D
Building Model (NYC Office of Technology and Innovation, LoD2 CityGML; see
fetch_data.py), for buildings that aren't simple flat-topped prisms.

prepare() reads the model straight from its zip and caches, per building ID
(BIN), the roof and wall polygons of every building whose roof has more than
one level or slopes: data/cache/buildings3d.pkl. Plain flat-roofed buildings
are left out; the footprint prisms already match them.

Each kept building is (vertices, ring_offsets, ring_polygon, polygon_kind,
ground): vertices (N, 3) float32 east/north/up meters (up above sea level),
rings as vertex ranges, each ring's polygon (the first ring of a polygon is
its outline, any others are holes), each polygon's kind (ROOF or WALL), and
the model's ground height under the building.
"""

import pickle
import time
import xml.etree.ElementTree as ET
import zipfile
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import shapely
from pyproj import Transformer

from common import CACHE_DIR, PROJECTION, RAW_DIR, polygon_normal

MODEL_ZIP = RAW_DIR / "buildings3d" / "DA_WISE_GML.zip"
CACHE_PATH = CACHE_DIR / "buildings3d.pkl"
US_FOOT = 1200.0 / 3937.0
ROOF, WALL = 0, 1
# A roof whose heights span less than this is flat: the prism matches it.
FLAT_ROOF_SPREAD = 1.0
# How far in front of a wall to check for open air (feet, the model's units).
WALL_PROBE = 1.0

# Some files are CityGML 1.0 and some 2.0, so elements are matched by local name.
SURFACE_KINDS = {"RoofSurface": ROOF, "WallSurface": WALL, "GroundSurface": None}


def prepare(workers: int = 14) -> None:
    started = time.time()
    with zipfile.ZipFile(MODEL_ZIP) as archive:
        names = sorted(n for n in archive.namelist() if n.endswith(".gml"))
    print(f"reading the 3-D building model ({len(names)} files)...", flush=True)
    buildings, stats = {}, {"buildings": 0, "kept": 0}
    with ProcessPoolExecutor(max_workers=workers) as pool:
        for part, part_stats in pool.map(_read_file, names):
            buildings.update(part)
            for key in stats:
                stats[key] += part_stats[key]
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE_PATH.with_suffix(".tmp")
    with open(tmp, "wb") as f:
        pickle.dump(buildings, f, protocol=pickle.HIGHEST_PROTOCOL)
    tmp.replace(CACHE_PATH)
    print(f"  {stats['buildings']:,} buildings read, {stats['kept']:,} kept (not flat-roofed) "
          f"in {time.time() - started:.0f} s", flush=True)


def load() -> dict:
    if not CACHE_PATH.exists():
        prepare()
    with open(CACHE_PATH, "rb") as f:
        return pickle.load(f)


def _read_file(name: str):
    to_local = Transformer.from_crs("EPSG:2263", PROJECTION, always_xy=True)
    kept, stats = {}, {"buildings": 0, "kept": 0}
    with zipfile.ZipFile(MODEL_ZIP) as archive, archive.open(name) as f:
        context = ET.iterparse(f, events=("start", "end"))
        _, root = next(context)
        for event, element in context:
            if event != "end" or _local(element.tag) != "Building":
                continue
            stats["buildings"] += 1
            building = _read_building(element, to_local)
            if building is not None:
                bin_number, shape = building
                kept[bin_number] = shape
                stats["kept"] += 1
            element.clear()
            root.clear()  # drop finished buildings so memory stays flat
    return kept, stats


def _read_building(element, to_local):
    bin_text = None
    for attribute in element:
        if _local(attribute.tag) == "stringAttribute" and attribute.get("name") == "BIN":
            bin_text = next((v.text for v in attribute if _local(v.tag) == "value"), None)
    if not bin_text or not bin_text.strip().isdigit():
        return None

    rings, ring_polygon, kinds, grounds = [], [], [], []
    for surface in element.iter():
        local = _local(surface.tag)
        if local not in SURFACE_KINDS:
            continue
        kind = SURFACE_KINDS[local]
        for polygon in surface.iter():
            if _local(polygon.tag) != "Polygon":
                continue
            outline, holes = None, []
            for boundary in polygon:
                points = _ring(next((p for p in boundary.iter() if _local(p.tag) == "posList"), None))
                if _local(boundary.tag) == "exterior":
                    outline = points
                elif points is not None:
                    holes.append(points)
            if outline is None:
                continue
            if kind is None:
                grounds.append(outline[:, 2].min())
                continue
            index = len(kinds)
            kinds.append(kind)
            for points in (outline, *holes):
                rings.append(points)
                ring_polygon.append(index)
    if not kinds:
        return None
    kinds = np.array(kinds, dtype=np.uint8)
    roof_z = np.concatenate([r[:, 2] for r, p in zip(rings, ring_polygon) if kinds[p] == ROOF] or [np.zeros(1)])
    if roof_z.max() - roof_z.min() < FLAT_ROOF_SPREAD / US_FOOT:
        return None  # one flat roof: the footprint prism matches it

    _face_outward(rings, ring_polygon, kinds)
    vertices = np.concatenate(rings)
    east, north = to_local.transform(vertices[:, 0], vertices[:, 1])
    up = vertices[:, 2] * US_FOOT
    offsets = np.zeros(len(rings) + 1, dtype=np.int32)
    offsets[1:] = np.cumsum([len(r) for r in rings])
    ground = (min(grounds) if grounds else vertices[:, 2].min()) * US_FOOT
    shape = (np.column_stack([east, north, up]).astype(np.float32), offsets,
             np.array(ring_polygon, dtype=np.int32), kinds, np.float32(ground))
    return int(bin_text), shape


def _face_outward(rings: list, ring_polygon: list, kinds: np.ndarray) -> None:
    """Turns every roof to face up and every wall to face open air (the model
    has some backwards), by reversing their rings. A wall faces the wrong way
    if just in front of it is inside the building: under a roof higher than
    the wall's middle."""
    outlines = {}
    for ring, polygon in zip(rings, ring_polygon):
        outlines.setdefault(polygon, ring)
    normals = {p: polygon_normal(outline) for p, outline in outlines.items()}
    roofs = [p for p in outlines if kinds[p] == ROOF and abs(normals[p][2]) > 0.05]
    flip = set()
    for p in roofs:
        if normals[p][2] < 0.0:
            flip.add(p)
            normals[p] = -normals[p]
    roof_shapes = [shapely.Polygon(outlines[p][:, :2]) for p in roofs]
    walls = [p for p in outlines if kinds[p] == WALL and np.linalg.norm(normals[p][:2]) > 0.1]
    if roofs and walls:
        probes, heights = [], []
        for p in walls:
            across = normals[p][:2] / np.linalg.norm(normals[p][:2])
            middle = outlines[p].mean(axis=0)
            probes.append(middle[:2] + across * WALL_PROBE)
            heights.append(middle[2])
        probes, heights = np.array(probes), np.array(heights)
        inside = np.zeros(len(walls), dtype=bool)
        for roof, shape in zip(roofs, roof_shapes):
            over = shapely.contains_xy(shape, probes[:, 0], probes[:, 1])
            if not over.any():
                continue
            n, point = normals[roof], outlines[roof][0]
            roof_z = point[2] - (n[0] * (probes[:, 0] - point[0]) + n[1] * (probes[:, 1] - point[1])) / n[2]
            inside |= over & (roof_z > heights)
        flip.update(p for p, wrong in zip(walls, inside) if wrong)
    for k, polygon in enumerate(ring_polygon):
        if polygon in flip:
            rings[k] = rings[k][::-1]


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _ring(pos_list):
    """A posList as (N, 3) points without the repeated closing point, or None."""
    if pos_list is None or not pos_list.text:
        return None
    values = np.array(pos_list.text.split(), dtype=np.float64)
    if len(values) < 12 or len(values) % 3:
        return None
    points = values.reshape(-1, 3)
    if np.allclose(points[0], points[-1]):
        points = points[:-1]
    return points if len(points) >= 3 else None


if __name__ == "__main__":
    prepare()
