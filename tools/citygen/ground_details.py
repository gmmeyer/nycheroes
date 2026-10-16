"""Ground details from more of the city's open data, drawn by
shaders/ground.gdshader:

  Planted medians and malls: the medians in the Planimetric Database that
    are planted: a Parks Department mall, parkway or Greenstreet, grass in
    the land cover map, or a curb-lined median along one of a few boulevards
    (PLANTED_STREETS: the Grand Concourse, Park Avenue, Broadway uptown, the
    parkways). Narrow curb-lined ones become shrub beds (GROUND_SHRUBS:
    clipped shrubs behind a concrete edge, or a hedge around a lawn), wide
    malls lawns where the land cover has grass or trees and paving where it
    has paving.
    Narrow medians get no canopy trees, and the street trees on planted ones
    stay small (MEDIAN_TREE_HEIGHT).
  Parks missing from the Parks Department's layer: state, federal and
    authority parks along the water (City Planning's Publicly Owned
    Waterfront: Brooklyn Bridge Park, Hudson River Park, Battery Park City,
    Governors, Liberty and Ellis Islands, Gateway, Riverbank, Roberto
    Clemente, Roosevelt Island...), and cemeteries and recreation areas
    (Planimetric Open Space), drawn as park where the land cover map shows
    grass or trees (woods come from the canopy map, as in any park).
  Special pavements: pavers in the DOT's pedestrian plazas (GROUND_PAVERS)
    and Belgian block on a list of streets (GROUND_COBBLES: DUMBO, the
    Meatpacking District, SoHo, Tribeca...), each piece with the direction
    its courses follow (uv2.y).
  Historic lamps: the boulevards in props.HISTORIC_LAMP_STREETS get
    post-tops instead of cobra-heads.

prepare() makes data/cache/ground_details.pkl; build_tiles.py uses it per
tile through GroundDetails.
"""

import json

import numpy as np
import rasterio.features
import shapely
from rasterio.transform import Affine
from shapely.geometry import MultiPolygon, Polygon, box, shape

import landcover
import props
from common import (FEET, GROUND_COBBLES, GROUND_PARK, GROUND_PAVEMENT, GROUND_PAVERS, GROUND_ROAD, GROUND_SHRUBS,
                    GROUND_YARD, RAW_DIR, STRUCTURE_CONCRETE, load_features, polygons_of, project, split_triangles,
                    triangles_of)

# Medians: the Planimetric Database's kinds that stand above the road (not
# painted ones, which are road, nor concrete barriers).
MEDIAN_KINDS = {360000, 360020, 360030, 360040, 360050, 360070, 360080}
MEDIAN_MIN_AREA = 6.0
# A median is planted if at least PLANTED_OVERLAP of it is a Parks mall,
# parkway or strip, or a Greenstreet; or if the land cover map has at least
# PLANTED_GRASS of it as grass, or PLANTED_GREEN as grass, trees and bare
# soil together; or if it's a curb-lined median along a planted boulevard:
# (street name as in the centerline data, borough code, (south, west, north,
# east) or None for its whole length).
PARK_MALL_TYPES = {"Mall", "Parkway", "Strip"}
PLANTED_OVERLAP = 0.3
PLANTED_GRASS = 0.2
PLANTED_GREEN = 0.5
PLANTED_STREETS = (
    ("GRAND CONC", 2, None),
    ("PARK AVE", 1, (40.7535, -73.9790, 40.7865, -73.9510)),  # 46th to 96th Street
    ("BROADWAY", 1, (40.7690, -73.9870, 40.8420, -73.9350)),  # 60th to 168th Street
    ("OCEAN PKWY", 3, None),
    ("EASTERN PKWY", 3, None),
    ("PELHAM PKWY", 2, None),
)
BOULEVARD_MEDIAN_KINDS = {360020, 360050, 360070}  # curb, grass, other: not traffic islands
BOULEVARD_MEDIAN_MIN_AREA = 30.0
# Planted medians up to BED_MAX_WIDTH wide (twice their inscribed circle's
# radius) are shrub beds if they're curb-lined islands (BED_KINDS: curb,
# fence, other, traffic island), else lawn (grass strips without curbs and
# highway medians behind guardrails); wider ones are malls, lawn where the
# land cover shows grass or trees.
BED_MAX_WIDTH = 9.0
BED_KINDS = {360000, 360020, 360040, 360070, 360080}
# Shrub beds: a concrete edge BED_EDGE wide inside the curb, then shrubs
# rising at BED_SLOPE degrees to BED_HEIGHT, like a clipped hedge (too high
# to step onto: heroes jump them; nobody's walking lanes run along medians).
# Beds with room for a lawn at least LAWN_MIN wide get a hedge HEDGE_WIDTH
# wide around a lawn. The shrubs' height above the ground goes in uv2.y.
BED_EDGE = 0.3
BED_HEIGHT = 0.7
BED_SLOPE = 70.0
HEDGE_WIDTH = 1.1
LAWN_MIN = 1.8
# Planted medians are taken this much bigger, to cover their islands in the
# road data.
MEDIAN_GROW = 0.3
# Street trees on planted narrow medians are mostly small ornamentals
# (hawthorns, pears, honeylocusts): no taller than this.
MEDIAN_TREE_HEIGHT = 7.5

# Parks missing from the parks layer: Publicly Owned Waterfront entries not
# run by the Parks Department (whose parks are in the layer), and Open Space
# cemeteries and recreation areas. Park paths get post-top lamps
# (build_tiles._path_lamps) in the waterfront parks, except Gateway's and
# the state's natural areas (Floyd Bennett Field's runways aren't paths).
PARKS_AGENCY = "NYC DPR"
NO_LAMP_AGENCIES = {"Federal GNRA", "NYS DEC"}
OPEN_SPACE_CODES = {"2500", "2510"}  # cemetery, recreational area (not vacant lots)
# Islands that are parks as a whole, by a point (latitude, longitude) on
# them, where the datasets outline only part: Governors Island (the
# Waterfront dataset has the National Monument and a few Trust parcels, not
# the Trust's park on the south half).
PARK_ISLANDS = ((40.6870, -74.0180),)
GREEN_CLASSES = (landcover.GRASS, landcover.CANOPY)
# Land cover outlines: the grid's gaps and specks one cell wide are closed
# and opened away, the stair-stepped outline simplified to GREEN_TOLERANCE
# (m) and its corners rounded by GREEN_ROUND; lawns and holes smaller than
# GREEN_MIN_AREA are dropped.
GREEN_TOLERANCE = 1.5
GREEN_ROUND = 0.8
GREEN_MIN_AREA = 30.0

# Belgian block streets: (street names as in the centerline data, borough
# code, (south, west, north, east)). Streets known for their granite setts;
# avenues through these areas are asphalt.
COBBLE_STREETS = (
    # DUMBO and Vinegar Hill, north of the BQE.
    (("WASHINGTON ST", "WATER ST", "MAIN ST", "PLYMOUTH ST", "ADAMS ST", "JOHN ST", "BRIDGE ST", "JAY ST",
      "PEARL ST", "ANCHORAGE PL", "DOCK ST", "HUDSON AVE", "EVANS ST", "GOLD ST"), 3,
     (40.7010, -73.9935, 40.7060, -73.9790)),
    # The Meatpacking District.
    (("GANSEVOORT ST", "LITTLE W 12 ST", "WASHINGTON ST", "W 13 ST", "9 AVE"), 1,
     (40.7383, -74.0102, 40.7418, -74.0040)),
    # SoHo's cast-iron streets.
    (("WOOSTER ST", "GREENE ST", "MERCER ST", "CROSBY ST"), 1, (40.7195, -74.0040, 40.7270, -73.9950)),
    # Tribeca.
    (("STAPLE ST", "JAY ST", "HARRISON ST", "COLLISTER ST", "LAIGHT ST", "VESTRY ST", "DESBROSSES ST", "YORK ST",
      "ST JOHNS LN", "ERICSSON PL"), 1, (40.7170, -74.0115, 40.7250, -74.0050)),
    # The Financial District's old lanes, and Front Street at the Seaport.
    (("STONE ST", "MILL LN", "S WILLIAM ST"), 1, (40.7035, -74.0115, 40.7058, -74.0085)),
    (("FRONT ST",), 1, (40.7058, -74.0045, 40.7085, -74.0010)),
)
# A cobbled street's road is taken this far beyond its half width.
COBBLE_MARGIN = 2.0
# Streets with no width in the data count as this wide (m).
DEFAULT_STREET_WIDTH = 10.0


def prepare(land) -> dict:
    """The ground details; `land` is the prepared ground's land (prepare.py)."""
    cover = landcover.LandCover()
    medians = _prepare_medians(cover)
    green, lamp_parks = _prepare_green(cover, land)
    plazas = load_features("plazas")
    plaza_geoms = polygons_of(shapely.union_all(_projected(plazas)), min_area=1.0)
    cobbles, cobble_angles = [], []
    for names, borough, bounds in COBBLE_STREETS:
        lines, half = _street_lines([(name, borough, bounds) for name in names])
        for line, h in zip(lines, half):
            cobbles.append(shapely.buffer(line, h + COBBLE_MARGIN, cap_style="flat"))
            cobble_angles.append(_angle(line))
    historic, historic_half = _street_lines(props.HISTORIC_LAMP_STREETS)
    print(f"  {int(medians['planted'].sum()):,} of {len(medians['planted']):,} medians planted, "
          f"{len(green):,} lawns in other parks, {len(plaza_geoms)} plazas, {len(cobbles)} cobbled blocks, "
          f"{len(historic)} historic lamp blocks", flush=True)
    return {
        "medians": medians,
        "green": np.array(green, dtype=object),
        "lamp_parks": np.array(lamp_parks, dtype=object),
        "plazas": {"geoms": np.array(plaza_geoms, dtype=object),
                   "angle": np.array([_angle(shapely.oriented_envelope(p).exterior) for p in plaza_geoms])},
        "cobbles": {"geoms": np.array(cobbles, dtype=object), "angle": np.array(cobble_angles)},
        "historic": {"lines": np.array(historic, dtype=object),
                     "reach": np.asarray(historic_half, np.float64) + props.HISTORIC_LAMP_REACH},
    }


def _projected(features) -> np.ndarray:
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in features], dtype=object)))
    return geoms[~shapely.is_empty(geoms)] if len(geoms) else geoms


def _prepare_medians(cover) -> dict:
    feats = [f for f in load_features("medians") if int(float(f["properties"].get("sub_code") or 0)) in MEDIAN_KINDS]
    kinds = np.array([int(float(f["properties"]["sub_code"])) for f in feats])
    geoms = shapely.make_valid(project(np.array([shape(f["geometry"]) for f in feats], dtype=object)))
    parts, owner = shapely.get_parts(geoms, return_index=True)
    keep = (shapely.get_type_id(parts) == 3) & (shapely.area(parts) >= MEDIAN_MIN_AREA)
    geoms, kinds = parts[keep], kinds[owner[keep]]
    width = _inscribed_width(geoms)
    area = shapely.area(geoms)

    # Parks malls and Greenstreets.
    malls = [f for f in load_features("parks") if f["properties"].get("typecategory") in PARK_MALL_TYPES]
    streets = [f for f in load_features("greenstreets") if f["properties"].get("featurestatus") == "Active"]
    planted_areas = np.concatenate([_projected(malls), _projected(streets)])
    covered = np.zeros(len(geoms))
    tree = shapely.STRtree(planted_areas)
    pairs = tree.query(geoms, predicate="intersects")
    if pairs.shape[1]:
        overlap = shapely.area(shapely.intersection(geoms[pairs[0]], planted_areas[pairs[1]]))
        np.add.at(covered, pairs[0], overlap)
    planted = covered >= PLANTED_OVERLAP * area

    # The land cover map.
    grass, green = np.zeros(len(geoms)), np.zeros(len(geoms))
    for k, geom in enumerate(geoms):
        classes = _classes_in(cover, geom)
        if classes is not None and len(classes):
            grass[k] = np.mean(classes == landcover.GRASS)
            green[k] = np.mean(np.isin(classes, (landcover.GRASS, landcover.CANOPY, landcover.SOIL)))
    planted |= (grass >= PLANTED_GRASS) | (green >= PLANTED_GREEN)

    # Boulevards.
    lines, half = _street_lines(PLANTED_STREETS)
    if len(lines):
        corridors = shapely.buffer(np.array(lines, dtype=object), np.asarray(half) + 3.0)
        hits = shapely.STRtree(corridors).query(geoms, predicate="intersects")
        along = np.zeros(len(geoms), dtype=bool)
        along[hits[0]] = True
        planted |= along & np.isin(kinds, list(BOULEVARD_MEDIAN_KINDS)) & (area >= BOULEVARD_MEDIAN_MIN_AREA)

    # Wide malls are lawn only where the land cover has grass or trees.
    lawn = np.full(len(geoms), None, dtype=object)
    for k in np.flatnonzero(planted & (width > BED_MAX_WIDTH)):
        lawn[k] = _green_parts(cover, geoms[k])
    return {"geoms": geoms, "kind": kinds, "planted": planted, "width": width.astype(np.float32), "lawn": lawn}


def _inscribed_width(geoms: np.ndarray) -> np.ndarray:
    """Twice the radius of each polygon's largest inscribed circle."""
    circles = shapely.maximum_inscribed_circle(geoms, 0.05)
    return 2.0 * shapely.length(circles)


def _prepare_green(cover, land) -> tuple[list, list]:
    """Lawns (polygons) in parks the parks layer lacks, and the outlines of
    those whose paths get lamps."""
    waterfront = [f for f in load_features("public_waterfront") if f["properties"].get("agency") != PARKS_AGENCY]
    open_space = [f for f in load_features("open_space") if str(f["properties"].get("feature_co")) in OPEN_SPACE_CODES]
    lat, lon = np.array(PARK_ISLANDS).T
    spots = project(shapely.points(lon, lat))
    islands = [part for part in polygons_of(land) if shapely.intersects(part, spots).any()]
    outlines = np.concatenate([_projected(waterfront), _projected(open_space), np.array(islands, dtype=object)])
    lit = [f for f in waterfront if f["properties"].get("agency") not in NO_LAMP_AGENCIES]
    lamps = np.concatenate([_projected(lit), np.array(islands, dtype=object)])
    lawns = []
    for poly in polygons_of(shapely.union_all(outlines), min_area=GREEN_MIN_AREA):
        lawns.extend(polygons_of(_green_parts(cover, poly), min_area=GREEN_MIN_AREA))
    return lawns, polygons_of(shapely.union_all(lamps), min_area=1.0)


def _window(cover, geom):
    """The land cover grid's rows and columns over a geometry's bounds, and
    the window's transform (east/north meters), or None off the map."""
    min_e, min_n, max_e, max_n = geom.bounds
    s = cover.spacing
    rows, columns = cover.grid.shape
    c0, c1 = int(np.floor((min_e - cover.min_e) / s)), int(np.ceil((max_e - cover.min_e) / s))
    r0, r1 = int(np.floor((cover.max_n - max_n) / s)), int(np.ceil((cover.max_n - min_n) / s))
    c0, r0, c1, r1 = max(c0, 0), max(r0, 0), min(c1, columns), min(r1, rows)
    if c1 <= c0 or r1 <= r0:
        return None
    transform = Affine(s, 0.0, cover.min_e + c0 * s, 0.0, -s, cover.max_n - r0 * s)
    return np.asarray(cover.grid[r0:r1, c0:c1]), transform


def _classes_in(cover, geom) -> np.ndarray | None:
    """The land cover classes of the grid cells whose centers are in a polygon."""
    found = _window(cover, geom)
    if found is None:
        return None
    grid, transform = found
    inside = rasterio.features.geometry_mask([geom], grid.shape, transform, invert=True)
    return grid[inside]


def _green_parts(cover, geom):
    """The parts of a polygon that the land cover map shows as grass or
    trees, smoothed (see GREEN_SMOOTH)."""
    found = _window(cover, geom)
    if found is None:
        return Polygon()
    grid, transform = found
    closed = ~_grow(~_grow(np.isin(grid, GREEN_CLASSES)))
    opened = _grow(~_grow(~closed))
    mask = opened & rasterio.features.geometry_mask([geom], grid.shape, transform, invert=True, all_touched=True)
    if not mask.any():
        return Polygon()
    cells = [shape(g) for g, _ in rasterio.features.shapes(mask.astype(np.uint8), mask=mask, transform=transform)]
    green = shapely.simplify(shapely.union_all(cells), GREEN_TOLERANCE, preserve_topology=True)
    green = shapely.buffer(shapely.buffer(green, -GREEN_ROUND, quad_segs=2), GREEN_ROUND, quad_segs=2)
    parts = []
    for poly in polygons_of(green, min_area=GREEN_MIN_AREA):
        holes = [ring for ring in poly.interiors if Polygon(ring).area >= GREEN_MIN_AREA]
        parts.append(Polygon(poly.exterior, holes))
    if not parts:
        return Polygon()
    return shapely.intersection(shapely.make_valid(MultiPolygon(parts)), shapely.make_valid(geom))


def _grow(mask: np.ndarray) -> np.ndarray:
    """A boolean grid grown by one cell (4-connected)."""
    out = mask.copy()
    out[1:] |= mask[:-1]
    out[:-1] |= mask[1:]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    return out


def _street_lines(specs) -> tuple[list, list]:
    """The street centerline's segments named in specs ((name, borough code,
    (south, west, north, east) or None) each): lines (east/north) and each
    one's half width (m)."""
    names = {}
    with open(RAW_DIR / "centerline_names.json", encoding="utf-8") as f:
        for row in json.load(f):
            name = " ".join(str(row.get("full_street_name") or "").split())
            names[str(row.get("physicalid"))] = (name, int(float(row.get("boroughcode") or 0)))
    wanted = {}
    for name, borough, bounds in specs:
        wanted.setdefault((name, borough), []).append(
            None if bounds is None else box(bounds[1], bounds[0], bounds[3], bounds[2]))
    lines, half = [], []
    for feat in load_features("centerline"):
        p = feat["properties"]
        areas = wanted.get(names.get(str(p.get("physicalid"))))
        if areas is None:
            continue
        geom = shape(feat["geometry"])
        if not any(area is None or area.intersects(geom) for area in areas):
            continue
        width = float(p.get("streetwidth") or 0) * FEET
        for part in shapely.get_parts(shapely.line_merge(geom)):
            lines.append(part)
            half.append((width if width > 0 else DEFAULT_STREET_WIDTH) / 2.0)
    if not lines:
        return [], []
    return list(project(np.array(lines, dtype=object))), half


def _angle(line) -> float:
    """The direction a line runs, from its first point to its last, as an
    angle in the ground's uv space (world x/z: east, south)."""
    coords = np.asarray(line.coords)
    d = coords[-1] - coords[0]
    return float(np.arctan2(-d[1], d[0]))


class GroundDetails:
    """The prepared ground details (prepare()), for build_tiles.py's workers."""

    def __init__(self, data: dict):
        m = data["medians"]
        self.medians = m
        self.median_tree = shapely.STRtree(m["geoms"])
        narrow = m["width"] <= BED_MAX_WIDTH
        self.narrow = narrow
        self.beds = narrow & m["planted"] & np.isin(m["kind"], list(BED_KINDS))
        self.green = data["green"]
        self.green_tree = shapely.STRtree(self.green)
        self.lamp_parks = data["lamp_parks"]
        self.lamp_park_tree = shapely.STRtree(self.lamp_parks)
        self.plazas = data["plazas"]
        self.plaza_tree = shapely.STRtree(self.plazas["geoms"])
        self.cobbles = data["cobbles"]
        self.cobble_tree = shapely.STRtree(self.cobbles["geoms"])
        self.historic = data["historic"]
        self.historic_tree = shapely.STRtree(self.historic["lines"])

    def layers(self, layers: list, bounds, clip, medians: bool, beds: bool) -> list:
        """A tile's ground layers ([(kind, geometry)], see
        build_tiles._ground_layers) with the parks the parks layer lacks and,
        if `medians` (where streets are drawn), the planted medians: shrub
        beds (GROUND_SHRUBS) if `beds`, else lawn. `clip` cuts a geometry to
        the tile (and snaps it like the layers).
        If the overlays fail (GEOS, on nearly coincident edges), the layers
        come back as they were."""
        try:
            return self._layers(layers, bounds, clip, medians, beds)
        except shapely.errors.GEOSException as error:
            print(f"  no ground details in tile at {bounds.bounds[:2]}: {error}", flush=True)
            return layers

    def _layers(self, layers: list, bounds, clip, medians: bool, beds: bool) -> list:
        kinds = {kind: _polygonal(geom) for kind, geom in layers}
        pavement, park, yard = kinds[GROUND_PAVEMENT], kinds[GROUND_PARK], kinds[GROUND_YARD]

        def cut(geoms, away):
            return [_polygonal(shapely.difference(g, away)) for g in geoms]

        # Lawns of the parks the parks layer lacks, on paved ground and yards.
        found = self.green[self.green_tree.query(bounds)]
        if len(found):
            green = _polygonal(shapely.intersection(clip(shapely.union_all(found)), shapely.union(pavement, yard)))
            pavement, yard = cut((pavement, yard), green)
            park = _polygonal(shapely.union(park, green))
        # Planted medians.
        near = self.median_tree.query(bounds) if medians else np.zeros(0, dtype=np.int64)
        near = near[self.medians["planted"][near]]
        shrubs = Polygon()
        if len(near):
            open_ground = _polygonal(shapely.union_all([pavement, park, yard]))
            narrow = near[self.narrow[near]]
            if len(narrow):
                grown = clip(shapely.buffer(shapely.union_all(self.medians["geoms"][narrow]), MEDIAN_GROW,
                                            join_style="mitre"))
                strip = _polygonal(shapely.intersection(grown, open_ground))
                pavement, park, yard = cut((pavement, park, yard), strip)
                bedded = narrow[self.beds[narrow]]
                if beds and len(bedded):
                    shrubs = _polygonal(shapely.intersection(strip, clip(shapely.buffer(
                        shapely.union_all(self.medians["geoms"][bedded]), MEDIAN_GROW, join_style="mitre"))))
                    strip = _polygonal(shapely.difference(strip, shrubs))
                park = _polygonal(shapely.union(park, strip))
            wide = near[~self.narrow[near]]
            if len(wide):
                mall = _polygonal(shapely.intersection(clip(shapely.union_all(self.medians["geoms"][wide])),
                                                       open_ground))
                lawns = [g for g in self.medians["lawn"][wide] if g is not None and not g.is_empty]
                lawn = _polygonal(shapely.intersection(clip(shapely.union_all(lawns)), mall)) if lawns else Polygon()
                pavement, park, yard = cut((pavement, park, yard), mall)
                park = _polygonal(shapely.union(park, lawn))
                pavement = _polygonal(shapely.union(pavement, shapely.difference(mall, lawn)))
        kinds[GROUND_PAVEMENT], kinds[GROUND_PARK], kinds[GROUND_YARD] = pavement, park, yard
        out = list(kinds.items())
        if not shrubs.is_empty:
            out.append((GROUND_SHRUBS, shrubs))
        return out

    def paving(self, kind: int, polys: list) -> list:
        """How to draw a ground layer's polygons, as [(uv2, polygons)]: roads
        on the cobbled streets as Belgian block, pavement in pedestrian plazas
        as pavers, each with the direction of its courses (see _angle); the
        rest as they are."""
        if kind == GROUND_ROAD:
            areas, tree, special = self.cobbles, self.cobble_tree, GROUND_COBBLES
        elif kind == GROUND_PAVEMENT:
            areas, tree, special = self.plazas, self.plaza_tree, GROUND_PAVERS
        else:
            return [((kind, 0.0), polys)]
        if not polys:
            return []
        rest = MultiPolygon(polys)
        hits = tree.query(rest, predicate="intersects")
        if not len(hits):
            return [((kind, 0.0), polys)]
        out = []
        try:
            for k in hits:
                piece = polygons_of(shapely.intersection(rest, areas["geoms"][k]), min_area=0.5)
                if piece:
                    out.append(((special, float(areas["angle"][k])), piece))
                    rest = shapely.difference(rest, areas["geoms"][k])
        except shapely.errors.GEOSException:
            return [((kind, 0.0), polys)]
        out.append(((kind, 0.0), polygons_of(rest, min_area=0.01)))
        return out

    def add_beds(self, builder, polys: list, cell: float, terrain) -> None:
        """Shrub beds on planted medians: a concrete edge inside the curb,
        then a mound of shrubs, or on wide enough beds a hedge around a lawn
        (see BED_*)."""
        run = BED_HEIGHT / np.tan(np.radians(BED_SLOPE))
        for poly in polys:
            bed = shapely.buffer(poly, -BED_EDGE, join_style="mitre")
            builder.add_draped(polygons_of(shapely.difference(poly, bed), 0.01), cell, terrain.height,
                               (STRUCTURE_CONCRETE, 0.0), terrain.normal)
            for part in polygons_of(bed, 0.5):
                self._add_bed(builder, part, cell, terrain, run)

    @staticmethod
    def _add_bed(builder, bed, cell: float, terrain, run: float) -> None:
        width = float(_inscribed_width(np.array([bed], dtype=object))[0])
        hedge = width >= 2.0 * HEDGE_WIDTH + LAWN_MIN
        if hedge:
            # Up, across the top, and down to the lawn.
            offsets = [0.0, run, HEDGE_WIDTH - run, HEDGE_WIDTH]
            lawn = shapely.buffer(bed, -HEDGE_WIDTH, join_style="round", quad_segs=2)
            builder.add_draped(polygons_of(lawn, 0.5), cell, terrain.height, (GROUND_PARK, 0.0), terrain.normal)
        else:
            # Up to a flat top (on narrow beds a lower ridge).
            offsets = [0.0, min(run, 0.45 * width)]
        rings = [bed] + [shapely.buffer(bed, -o, join_style="round", quad_segs=2) for o in offsets[1:]]
        bands = [shapely.difference(outer, inner) for outer, inner in zip(rings, rings[1:])]
        if not hedge:
            bands.append(rings[-1])
        tris = [t for band in bands for p in polygons_of(band, 0.001)
                if (t := triangles_of(p)) is not None]
        if not tris:
            return
        tris = split_triangles(np.concatenate(tris), cell)  # bent with the ground, as add_draped does
        edge = bed.boundary
        top = BED_HEIGHT * min(1.0, offsets[1] / run)

        def mound(en):
            d = shapely.distance(edge, shapely.points(en))
            if hedge:
                d = np.minimum(d, HEDGE_WIDTH - d)
            return np.clip(d / run * BED_HEIGHT, 0.0, top)

        def height(en):
            en = np.asarray(en, np.float64).reshape(-1, 2)
            return terrain.height(en) + mound(en)

        def normal(en):
            # Smooth normals from the surface's slope, so the shrubs look rounded.
            step = 0.06
            de = (height(en + [step, 0.0]) - height(en - [step, 0.0])) / (2 * step)
            dn = (height(en + [0.0, step]) - height(en - [0.0, step])) / (2 * step)
            n = np.column_stack([-de, np.ones(len(en)), dn])
            return n / np.linalg.norm(n, axis=1, keepdims=True)
        en = tris.reshape(-1, 2)
        rise = np.round(mound(en), 2)
        pos = np.column_stack([en[:, 0], terrain.height(en) + rise, -en[:, 1]]).reshape(-1, 3, 3)
        uv = np.stack([tris[..., 0], -tris[..., 1]], axis=-1)
        uv2 = np.column_stack([np.full(len(en), float(GROUND_SHRUBS)), rise]).reshape(-1, 3, 2)
        builder.add(pos, uv, uv2, (0.0, 1.0, 0.0), normal(en).reshape(-1, 3, 3))

    def lamp_parks_near(self, bounds) -> np.ndarray:
        """Outlines of the parks (beyond the parks layer) whose paths have lamps."""
        return self.lamp_parks[self.lamp_park_tree.query(bounds)]

    def near_lamp_park(self, points: np.ndarray, reach: float) -> np.ndarray:
        near = np.zeros(len(points), dtype=bool)
        if len(points):
            near[self.lamp_park_tree.query(shapely.points(points), predicate="dwithin", distance=reach)[0]] = True
        return near

    def historic_lamps(self, points: np.ndarray, arms: np.ndarray) -> np.ndarray:
        """Which curb lamps (at (N, 2) points, arms reaching along (N, 2) unit
        directions) light a historic boulevard: within its reach of one of
        its centerlines, with the arm across it (not a cross street's lamp
        near the corner)."""
        found = np.zeros(len(points), dtype=bool)
        if not len(points):
            return found
        lines, reach = self.historic["lines"], self.historic["reach"]
        pairs = self.historic_tree.query(shapely.points(points), predicate="dwithin",
                                         distance=float(reach.max()) if len(reach) else 0.0)
        if not pairs.shape[1]:
            return found
        p, k = pairs
        lines_to = shapely.shortest_line(shapely.points(points[p]), lines[k])
        nearest = shapely.get_coordinates(shapely.get_point(lines_to, 1))
        to_line = nearest - points[p]
        distance = np.linalg.norm(to_line, axis=1)
        across = np.abs((to_line * arms[p]).sum(axis=1)) / np.maximum(distance, 1e-6)
        ok = (distance <= reach[k]) & ((across >= 0.6) | (distance < 3.0))
        found[p[ok]] = True
        return found

    def on_narrow_median(self, en: np.ndarray) -> np.ndarray:
        """Which (N, 2) points stand on a narrow median (planted or not)."""
        return self._on(en, self.narrow)

    def median_trees(self, trees: dict) -> dict:
        """Street trees (props dicts as in build_tiles._street_trees) with
        those on shrub-bed medians kept small (MEDIAN_TREE_HEIGHT)."""
        on = self._on(trees["en"], self.beds)
        tall = on & (trees["height"] > MEDIAN_TREE_HEIGHT)
        if tall.any():
            trees = dict(trees)
            scale = MEDIAN_TREE_HEIGHT / trees["height"][tall]
            trees["height"] = trees["height"].copy()
            trees["width"] = trees["width"].copy()
            trees["height"][tall] = MEDIAN_TREE_HEIGHT
            trees["width"][tall] *= np.sqrt(scale)
        return trees

    def without_narrow_medians(self, geom, area):
        """`geom` without the narrow medians around `area` (nobody walks along them)."""
        near = self.median_tree.query(area)
        near = near[self.narrow[near]]
        if not len(near):
            return geom
        return shapely.difference(geom, shapely.buffer(shapely.union_all(self.medians["geoms"][near]), MEDIAN_GROW))

    def _on(self, en: np.ndarray, which: np.ndarray) -> np.ndarray:
        out = np.zeros(len(en), dtype=bool)
        if not len(en):
            return out
        pairs = self.median_tree.query(shapely.points(en), predicate="dwithin", distance=MEDIAN_GROW)
        pairs = pairs[:, which[pairs[1]]]
        out[pairs[0]] = True
        return out


def _polygonal(geom):
    parts = polygons_of(geom, min_area=0.0)
    return MultiPolygon(parts) if parts else Polygon()
