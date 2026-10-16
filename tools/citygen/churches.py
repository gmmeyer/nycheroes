"""Houses of worship drawn as churches: stone or brick walls with tall
pointed or round-arched windows between buttresses and no floors, a steep
gable roof over the nave, a portal and a rose window in the gable facing the
street, and the 3-D model's towers as belfries under spires.

prepare() picks them from the city's tax lot database (PLUTO building class
M1: church, synagogue, chapel), joined to the footprints like facades.py's
types: buildings at least MIN_AREA and MIN_HEIGHT big, with few or tall
floors (not a parish house or a school on the same lot). Built before
MODERN_YEAR they're Gothic (pointed arches; always where the footprint
measures a spire above the 3-D model's tower) or Romanesque (round arches),
in brownstone, gray stone, limestone, red or buff brick by era (big ones and
landmarks in stone); later ones are modern brick with tall narrow windows.
It makes data/cache/churches.pkl: each prepared building's kind (0: not a
church) and wall material.

build_tiles.py calls add() for every church it draws on its own (all of them
up close, the taller ones further out). From the 3-D model (buildings3d.py),
whose roofs are flat levels: the biggest level is the nave, and if its
outline fills most of its smallest enclosing rectangle it gets a gable roof
whose ridge is the level's height (the model's levels sit at about the
ridge), PITCH degrees steep where that leaves the eaves at least EAVES_SHARE
of the way up; the model's walls up to it are drawn again up to the roof.
Smaller parts rising above it are towers: their walls are belfries at the
top, and the top gets a spire (to the footprint's height, where that's above
the model's, as at Marble Collegiate; else in proportion to the tower), an
octagonal one inset on square towers, with pinnacles at a square stage's
corners. Churches the model has as one flat level get the same gable over
their footprint.

The faces go in the tile's churches surface (common.SURFACE_CHURCHES), which
shaders/church.gdshader paints. Per vertex:
  UV    walls: (m from the face's middle, to the right seen from outside; m
        above the church's ground, its footprint's lowest corner, with the
        feet sunk 1 m below it); pitched roofs: (m along the eaves, m up the
        slope); flat roofs: world x/z; spires and pinnacles: (m from the
        middle of the face's base, m up the slope)
  UV2.x part + PARTS * flags + WIDTH_SCALE * the face's width in dm (walls;
        spires: the base's)
  UV2.y the top in dm (walls: of the wall, gable ends: the eaves; spires:
        the slope's length) + the church's seed (0..0.999)
Flags: FRONT (the wall faces a street), the kind * KIND and the material *
MATERIAL.
"""

import numpy as np
import shapely
from shapely.geometry import Polygon

import buildings3d
import facades
from common import polygon_normal, polygons_of, triangles_of, triangulate_planar

# Kinds (0: not a church).
GOTHIC, ROMANESQUE, MODERN = 1, 2, 3
# Wall materials, as the shader numbers them.
BROWNSTONE, GRAY_STONE, LIMESTONE, RED_BRICK, BUFF_BRICK = range(5)
# Odds of each material by era: built by 1890, by 1919, by 1944, since.
MATERIAL_ODDS = ((35, 30, 10, 25, 0), (10, 25, 25, 30, 10), (0, 20, 30, 25, 25), (0, 10, 15, 35, 40))
GOTHIC_SHARE = 0.65
# Big churches (cathedrals) and designated landmarks are stone, whatever the era.
STONE_AREA = 1500.0
MODERN_YEAR = 1945

# Parts (UV2.x % PARTS), as the shader numbers them.
WALL = 0       # a wall with windows up to the eaves (or its top)
GABLE = 1      # a gable end: the portal and a rose window (UV2.y: the eaves)
TOWER = 2      # a tower's wall: stages, a clock, the belfry at its top
ROOF = 3       # a pitched roof's slope
FLAT_ROOF = 4  # flat roofs (world x/z)
SPIRE = 5      # a spire's or a pyramid cap's face
PINNACLE = 6   # pinnacles at a tower's corners
PARTS = 16
FRONT = 1
KIND = 2
MATERIAL = 8
WIDTH_SCALE = 1024
MAX_WIDTH = 1600.0  # m (in dm it keeps UV2.x a whole number a float holds exactly)

# Which PLUTO lots and buildings: area (m2), height (m), at most this many
# floors unless they're this tall each (m).
CLASSES = ("M1",)
MIN_AREA = 120.0
MIN_HEIGHT = 7.0
MAX_FLOORS = 3
MIN_STORY = 4.5

# Gable roofs: over outlines filling at least GABLE_FILL of their smallest
# enclosing rectangle, GABLE_WIDTH wide (m); PITCH degrees steep by kind
# (low, high) where the eaves stay at least EAVES_SHARE of the ridge's height
# and MIN_EAVES up (else shallower); OVERHANG past the walls.
GABLE_FILL = 0.72
GABLE_WIDTH = (5.0, 40.0)
PITCH = {GOTHIC: (48.0, 58.0), ROMANESQUE: (38.0, 46.0), MODERN: (24.0, 34.0)}
EAVES_SHARE = 0.58
MIN_EAVES = 4.0
OVERHANG = 0.25
# The model's levels within this of each other are one level (m).
LEVEL_SLACK = 0.6
# Towers: parts rising at least TOWER_RISE above the nave, covering at most
# TOWER_SHARE of its area and TOWER_AREA (m2).
TOWER_RISE = 3.0
TOWER_SHARE = 0.5
TOWER_AREA = 1200.0
# Spires: on towers up to SPIRE_BASE wide (m), this share of them by kind,
# this many times the tower's width tall (low, high); the footprint's height
# instead where it's at least DATA_SPIRE above the model's top.
SPIRE_BASE = 14.0
SPIRE_SHARE = {GOTHIC: 0.85, ROMANESQUE: 0.6, MODERN: 0.6}
SPIRE_RATIO = {GOTHIC: (1.8, 2.8), ROMANESQUE: (0.6, 1.0), MODERN: (2.0, 3.0)}
DATA_SPIRE = 4.0
DATA_SPIRE_RATIO = 4.5  # at most this many times the tower's width
# Square tops (filling this much of their rectangle) get an octagonal spire
# inset this share of their width, and Gothic ones pinnacles at the corners.
SQUARE_FILL = 0.85
SPIRE_INSET = 0.1
PINNACLE_WIDTH = 0.7
PINNACLE_SHAFT = 1.0
PINNACLE_HEIGHT = 2.4


def prepare(buildings: dict) -> dict:
    """Per building (same order as `buildings`): kind (0: not a church) and material."""
    lots, pluto = facades.lot_tables()
    shapes = buildings3d.load()
    count = len(buildings["bin"])
    kinds = np.zeros(count, dtype=np.uint8)
    materials = np.zeros(count, dtype=np.uint8)
    areas = shapely.area(buildings["geoms"])
    for k in range(count):
        bin_number = int(buildings["bin"][k])
        lot = pluto.get(lots.get(bin_number, int(buildings["bbl"][k])))
        if lot is None or (lot.get("bldgclass") or "").upper() not in CLASSES:
            continue
        height = float(buildings["height"][k])
        floors = facades.number(lot, "numfloors")
        if areas[k] < MIN_AREA or height < MIN_HEIGHT or (floors > MAX_FLOORS and height / floors < MIN_STORY):
            continue
        year = int(facades.number(lot, "yearbuilt"))
        shape = shapes.get(bin_number)
        spire = shape is not None and height - float(shape[0][:, 2].max() - shape[4]) >= DATA_SPIRE
        if year >= MODERN_YEAR:
            kinds[k] = MODERN
        else:
            kinds[k] = GOTHIC if spire or facades.unit_hash(bin_number, 41) < GOTHIC_SHARE else ROMANESQUE
        era = 3 if year >= MODERN_YEAR else (0 if 0 < year <= 1890 else (1 if year < 1920 else 2))
        odds = np.array(MATERIAL_ODDS[era], np.float64)
        if areas[k] >= STONE_AREA or (lot.get("landmark") or "").strip():
            odds[RED_BRICK:] = 0.0
        cumulative = np.cumsum(odds) / odds.sum()
        r = facades.unit_hash(bin_number, 43)
        materials[k] = min(int(np.searchsorted(cumulative, r, side="right")), len(cumulative) - 1)
    print(f"  churches: {int((kinds > 0).sum()):,} buildings", flush=True)
    return {"kind": kinds, "material": materials}


def add(builder, index: int, shape, ground: float, w: dict, settings: dict, faces_street) -> bool:
    """Draws building `index` into `builder` (the churches surface) if it's a
    church, standing at `ground`: from the 3-D model's `shape` if there is
    one, else its footprint. Returns whether it did."""
    data = w.get("churches")
    if data is None or not data["kind"][index]:
        return False
    b = w["b"]
    church = _Church(builder, int(data["kind"][index]), int(data["material"][index]), float(b["seed"][index]),
                     ground, faces_street)
    height = float(b["height"][index])
    if shape is not None and church.from_model(shape, height):
        return True
    geom = shapely.simplify(b["geoms"][index], settings["building_tolerance"], preserve_topology=True)
    for poly in polygons_of(geom, settings["min_area"]):
        church.from_footprint(Polygon(poly.exterior), height)
    return True


class _Church:
    def __init__(self, builder, kind: int, material: int, seed: float, ground: float, faces_street):
        self.builder = builder
        self.kind = kind
        self.material = material
        self.seed = seed
        self.ground = ground
        self.faces_street = faces_street

    def rnd(self, salt: int) -> float:
        return facades.unit_hash(int(self.seed * 16777216.0), salt)

    def uv2(self, part: int, width: float = 0.0, top: float = 0.0, front: bool = False) -> tuple[float, float]:
        flags = (FRONT if front else 0) + KIND * self.kind + MATERIAL * self.material
        code = part + PARTS * flags + WIDTH_SCALE * int(round(min(max(width, 0.0), MAX_WIDTH) * 10.0))
        return float(code), float(int(round(max(top, 0.0) * 10.0))) + min(self.seed, 0.999)

    # --- From the footprint ---

    def from_footprint(self, poly, height: float) -> None:
        """A church over a footprint: gabled if it suits one, else flat-topped."""
        gable = self.gable(poly, height)
        ring = np.asarray(shapely.orient_polygons(poly).exterior.coords)[:, :2]
        if gable is None:
            self.walls(ring, lambda en: np.full(len(en), self.ground + height), None)
            self.builder.add_flat([poly], self.ground + height, self.uv2(FLAT_ROOF))
        else:
            self.walls(ring, gable["height"], gable)

    # --- From the 3-D model ---

    def from_model(self, shape, footprint_height: float) -> bool:
        """A church from the 3-D model's levels (see the module's docstring).
        Returns False, adding nothing, if the model has no roofs."""
        vertices, offsets, ring_polygon, kinds, model_ground = shape
        points = vertices.astype(np.float64)
        points[:, 2] += self.ground - float(model_ground)
        points[points[:, 2] <= self.ground + 0.05, 2] -= 1.0  # the walls' feet, as the buildings'
        starts = np.searchsorted(ring_polygon, np.arange(len(kinds)))
        ends = np.append(starts[1:], len(ring_polygon))
        polygons = [[points[offsets[r]:offsets[r + 1]] for r in range(starts[p], ends[p])] for p in range(len(kinds))]
        roofs = []
        for p, kind in enumerate(kinds):
            if kind != buildings3d.ROOF:
                continue
            outline = shapely.make_valid(Polygon(polygons[p][0][:, :2]))
            if outline.area > 0.5:
                roofs.append((p, float(polygons[p][0][:, 2].mean()), outline))
        if not roofs:
            return False
        main = max(roofs, key=lambda r: r[2].area)
        level = main[1]
        near_main = shapely.buffer(main[2], 0.3)
        nave = shapely.union_all([r[2] for r in roofs if abs(r[1] - level) < LEVEL_SLACK
                                  and shapely.intersects(r[2], near_main)])
        nave_area = float(nave.area)
        towers = [r for r in roofs if r[1] > level + TOWER_RISE
                  and r[2].area <= min(TOWER_AREA, TOWER_SHARE * nave_area)]
        clusters = _clusters(towers)
        parts = polygons_of(nave)
        if not parts:
            return False
        outline = max(parts, key=lambda q: q.area)
        outline = shapely.simplify(Polygon(outline.exterior), 0.3, preserve_topology=True)
        gable = self.gable(outline, level - self.ground)
        main_ids = {r[0] for r in roofs if abs(r[1] - level) < LEVEL_SLACK and shapely.intersects(r[2], near_main)}
        tower_area = shapely.buffer(shapely.union_all([r[2] for c in clusters for r in c]), 0.5) if clusters else None
        nave_band = shapely.buffer(nave, 0.5)
        if gable is not None:
            ring = np.asarray(shapely.orient_polygons(outline).exterior.coords)[:, :2]
            self.walls(ring, gable["height"], gable)
        for p, kind in enumerate(kinds):
            rings = polygons[p]
            if kind == buildings3d.ROOF:
                if gable is None or p not in main_ids:
                    self.model_face(rings, FLAT_ROOF)
                continue
            low, high = float(rings[0][:, 2].min()), float(rings[0][:, 2].max())
            middle = shapely.Point(rings[0][:, :2].mean(axis=0))
            if gable is not None and abs(high - level) < LEVEL_SLACK and shapely.intersects(nave_band, middle):
                continue  # drawn again up to the gable roof
            if gable is not None and abs(low - level) < LEVEL_SLACK:
                # Standing on the nave's level: reach down through the sloping roof.
                rings = [ring.copy() for ring in rings]
                for ring in rings:
                    ring[ring[:, 2] <= low + 0.05, 2] = gable["eaves"] - 1.0
            tower = tower_area is not None and high > level + 1.0 and shapely.intersects(tower_area, middle)
            self.model_face(rings, TOWER if tower else WALL, top=high - self.ground)
        model_top = float(points[:, 2].max()) - self.ground
        for k, cluster in enumerate(clusters):
            self.spire(cluster, footprint_height - model_top if k == 0 else 0.0, k)
        return True

    def model_face(self, rings: list, part: int, top: float = 0.0) -> None:
        """One of the model's polygons (outline and holes, (N, 3) east/north/up)."""
        tris = triangulate_planar(rings)
        if tris is None:
            return
        normal = polygon_normal(rings[0])
        if part == FLAT_ROOF:
            if normal[2] < 0.0:
                normal = -normal
            uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
            uv2 = self.uv2(FLAT_ROOF)
        else:
            along = np.array([-normal[1], normal[0]])
            length = np.linalg.norm(along)
            if length < 1e-6:
                return
            along /= length
            span = rings[0][:, :2] @ along
            middle = 0.5 * (span.min() + span.max())
            uv = np.stack([tris[..., :2] @ along - middle, tris[..., 2] - self.ground], axis=-1)
            outward = normal[:2] / length
            front = bool(self.faces_street(rings[0][:, :2].mean(axis=0)[None], outward[None])[0])
            uv2 = self.uv2(part, float(span.max() - span.min()), top, front)
        pos = np.stack([tris[..., 0], tris[..., 2], -tris[..., 1]], axis=-1)
        self.builder.add(pos, uv, uv2, (normal[0], normal[2], -normal[1]))

    # --- Shared ---

    def gable(self, poly, ridge: float):
        """A gable roof over `poly` with its ridge `ridge` m up (see the
        module's docstring), added to the builder: its numbers (ridge
        direction, eaves height, a function for the roof's height over (N, 2)
        east/north points), or None if `poly` doesn't suit one."""
        if poly is None or poly.is_empty or len(poly.interiors):
            return None
        rect = shapely.oriented_envelope(poly)
        if rect.geom_type != "Polygon" or poly.area < GABLE_FILL * rect.area:
            return None
        corners = np.asarray(rect.exterior.coords)[:4]
        edges = [corners[1] - corners[0], corners[2] - corners[1]]
        lengths = [float(np.hypot(*e)) for e in edges]
        k = 0 if lengths[0] >= lengths[1] else 1
        along, length = edges[k] / lengths[k], lengths[k]
        across, width = edges[1 - k] / lengths[1 - k], lengths[1 - k]
        if not GABLE_WIDTH[0] <= width <= GABLE_WIDTH[1]:
            return None
        low, high = PITCH[self.kind]
        degrees = low + (high - low) * self.rnd(51)
        rise = min(np.tan(np.radians(degrees)) * width / 2, ridge - max(MIN_EAVES, EAVES_SHARE * ridge))
        if rise < 1.5:
            return None
        pitch = np.arctan2(rise, width / 2)
        center = corners.mean(axis=0)
        eaves = self.ground + ridge - rise
        half_l, half_w = length / 2 + OVERHANG, width / 2 + OVERHANG

        def local(en):
            d = np.asarray(en, np.float64).reshape(-1, 2) - center
            return d @ along, d @ across

        def height(en):
            _, v = local(en)
            return eaves + rise * (1.0 - np.abs(v) / (width / 2))

        def world(uv):
            uv = np.asarray(uv, np.float64)
            return center + uv[:, :1] * along + uv[:, 1:] * across

        grown = shapely.buffer(poly, OVERHANG, join_style="mitre")
        roof_uv2 = self.uv2(ROOF, top=float(np.hypot(rise, width / 2) + OVERHANG / np.cos(pitch)))
        for side in (1.0, -1.0):
            outline = [(-half_l, side * half_w), (half_l, side * half_w), (half_l, 0.0), (-half_l, 0.0)]
            piece = shapely.intersection(Polygon(world(outline)), grown)
            tris = [t for t in (triangles_of(p) for p in polygons_of(piece, 0.01)) if t is not None]
            if not tris:
                continue
            en = np.concatenate(tris).reshape(-1, 2)
            pos = np.column_stack([en[:, 0], height(en), -en[:, 1]]).reshape(-1, 3, 3)
            u, v = local(en)
            # uv: m along the eaves (left to right seen from below the eaves), m up the slope.
            uv = np.column_stack([u * side, (half_w - v * side) / np.cos(pitch)]).reshape(-1, 3, 2)
            d = side * across
            normal = np.array([d[0] * np.sin(pitch), np.cos(pitch), -d[1] * np.sin(pitch)])
            self.builder.add(pos, uv, roof_uv2, normal / np.linalg.norm(normal))
        return {"along": along, "center": center, "eaves": eaves, "height": height}

    def walls(self, ring: np.ndarray, top_of, gable) -> None:
        """Walls along a closed ring (east/north, outside to the right) from
        below the ground up to top_of(points) (absolute heights): under a
        gable, its ends rise to the ridge (GABLE faces) and the rest stop at
        the roof (WALL); else every wall is a WALL."""
        builder = self.builder
        bottom = self.ground - 1.0
        for a, b in zip(ring[:-1], ring[1:]):
            seg = b - a
            length = float(np.hypot(*seg))
            if length < 0.05:
                continue
            direction = seg / length
            outward = np.array([direction[1], -direction[0]])
            ts = [0.0, length]
            part = WALL
            if gable is not None:
                # Break where the wall passes under the ridge.
                along, center = gable["along"], gable["center"]
                normal = np.array([-along[1], along[0]])
                da, db = (a - center) @ normal, (b - center) @ normal
                if da * db < 0.0:
                    ts.insert(1, length * da / (da - db))
                if abs(outward @ along) > 0.8:
                    part = GABLE
            ts = np.array(ts)
            en = a + direction * ts[:, None]
            tops = top_of(en)
            top = (gable["eaves"] if part == GABLE else float(tops.min())) - self.ground
            front = bool(self.faces_street(((a + b) * 0.5)[None], outward[None])[0])
            uv2 = self.uv2(part, length, top, front)
            normal = (outward[0], 0.0, -outward[1])
            for k in range(len(ts) - 1):
                e0, e1 = en[k], en[k + 1]
                quad = np.array([[e0[0], bottom, -e0[1]], [e1[0], bottom, -e1[1]],
                                 [e1[0], tops[k + 1], -e1[1]], [e0[0], tops[k], -e0[1]]])
                u0, u1 = ts[k] - length / 2, ts[k + 1] - length / 2
                uv = np.array([[u0, -1.0], [u1, -1.0], [u1, tops[k + 1] - self.ground], [u0, tops[k] - self.ground]])
                tri = [(0, 1, 2), (0, 2, 3)]
                builder.add(quad[tri], uv[tri], uv2, normal)

    def spire(self, cluster: list, data_height: float, salt: int) -> None:
        """A spire (or a pyramid cap) on a tower: the highest of the
        cluster's levels, with pinnacles at a square stage's corners."""
        top = max(cluster, key=lambda r: r[1])
        base_y = top[1]
        outline = shapely.convex_hull(top[2])
        size = float(np.sqrt(outline.area))
        rect = shapely.oriented_envelope(outline)
        square = rect.geom_type == "Polygon" and outline.area >= SQUARE_FILL * rect.area
        if data_height >= DATA_SPIRE:
            height = min(data_height, DATA_SPIRE_RATIO * size)
        elif size <= SPIRE_BASE and self.rnd(61 + salt) < SPIRE_SHARE[self.kind]:
            low, high = SPIRE_RATIO[self.kind]
            height = size * (low + (high - low) * self.rnd(62 + salt))
        else:
            height = 0.0
        if square:
            corners = np.asarray(rect.exterior.coords)[:4]
            middle = corners.mean(axis=0)
            if height > 0.0:
                inset = middle + (corners - middle) * (1.0 - SPIRE_INSET)
                octagon = []
                for c0, c1 in zip(inset, np.roll(inset, -1, axis=0)):
                    octagon += [c0 + (c1 - c0) * 0.293, c0 + (c1 - c0) * 0.707]
                self.pyramid(np.array(octagon), base_y, height, SPIRE)
            if self.kind == GOTHIC:
                self.pinnacles(corners, base_y)
        else:
            if height > 0.0:
                ring = np.asarray(shapely.simplify(outline, 0.15).exterior.coords)[:-1]
                self.pyramid(ring, base_y, height, SPIRE)
            # Pinnacles on the corners of a square stage below.
            lower = [r for r in cluster if r[1] < base_y - 3.0]
            if lower and self.kind == GOTHIC:
                stage = max(lower, key=lambda r: r[2].area)
                hull = shapely.convex_hull(shapely.union_all([r[2] for r in lower]))
                rect = shapely.oriented_envelope(hull)
                if rect.geom_type == "Polygon" and hull.area >= SQUARE_FILL * rect.area:
                    self.pinnacles(np.asarray(rect.exterior.coords)[:4], stage[1])

    def pyramid(self, ring: np.ndarray, base_y: float, height: float, part: int) -> None:
        """A pyramid over a convex ring (east/north, no closing point)."""
        apex = ring.mean(axis=0)
        ring = np.asarray(shapely.orient_polygons(Polygon(ring)).exterior.coords)[:-1]
        for p0, p1 in zip(ring, np.roll(ring, -1, axis=0)):
            edge = p1 - p0
            length = float(np.hypot(*edge))
            if length < 0.01:
                continue
            direction = edge / length
            outward = np.array([direction[1], -direction[0]])
            middle = (p0 + p1) * 0.5
            reach = float((middle - apex) @ outward)  # the apex's distance in from the base edge
            slant = float(np.hypot(height, reach))
            pos = np.array([[p0[0], base_y, -p0[1]], [p1[0], base_y, -p1[1]], [apex[0], base_y + height, -apex[1]]])
            uv = np.array([[-length / 2, 0.0], [length / 2, 0.0], [float((apex - middle) @ direction), slant]])
            normal = np.array([outward[0] * height, reach, -outward[1] * height])
            self.builder.add(pos[None], uv[None], self.uv2(part, length, slant), normal / np.linalg.norm(normal))

    def pinnacles(self, corners: np.ndarray, base_y: float) -> None:
        """Small pinnacles at a square tower top's corners: a shaft and a point."""
        middle = corners.mean(axis=0)
        half = PINNACLE_WIDTH / 2
        for corner in corners:
            to_middle = middle - corner
            spot = corner + to_middle / max(np.hypot(*to_middle), 1e-6) * (half * 1.42)
            square = np.array([spot + (-half, -half), spot + (half, -half), spot + (half, half), spot + (-half, half)])
            ring = np.vstack([square, square[:1]])
            for a, b in zip(ring[:-1], ring[1:]):
                outward = np.array([(b - a)[1], -(b - a)[0]]) / PINNACLE_WIDTH
                quad = np.array([[a[0], base_y - 0.3, -a[1]], [b[0], base_y - 0.3, -b[1]],
                                 [b[0], base_y + PINNACLE_SHAFT, -b[1]], [a[0], base_y + PINNACLE_SHAFT, -a[1]]])
                uv = np.array([[-half, 0.0], [half, 0.0], [half, PINNACLE_SHAFT + 0.3], [-half, PINNACLE_SHAFT + 0.3]])
                tri = [(0, 1, 2), (0, 2, 3)]
                self.builder.add(quad[tri], uv[tri], self.uv2(PINNACLE, PINNACLE_WIDTH),
                                 (outward[0], 0.0, -outward[1]))
            self.pyramid(square, base_y + PINNACLE_SHAFT, PINNACLE_HEIGHT, PINNACLE)


def _clusters(towers: list) -> list:
    """Towers' levels grouped into towers (levels that touch), tallest first."""
    clusters = []
    for roof in sorted(towers, key=lambda r: -r[1]):
        grown = shapely.buffer(roof[2], 0.5)
        for cluster in clusters:
            if any(shapely.intersects(grown, other[2]) for other in cluster):
                cluster.append(roof)
                break
        else:
            clusters.append([roof])
    return clusters
