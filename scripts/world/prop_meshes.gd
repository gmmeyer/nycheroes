class_name PropMeshes
extends RefCounted
## Low-poly meshes for the city's props (see CityProps), built in code at unit
## size: the prop's base point at the origin, its top at y = 1, and its crown
## or tank 1 wide (x and z from -0.5 to 0.5). Each instance scales the mesh to
## its real height and width; the shaders turn it to its yaw and add the
## per-prop variety.
##
## UV.x says which part a vertex belongs to (the shaders color by part) and
## UV.y how far up that part it is; UV2 carries a part's own data (below).
## Trees (shaders/tree.gdshader), one mesh in three shapes, so one MultiMesh
## draws every kind of tree:
##   VERTEX, NORMAL, UV, UV2  a broadleaf with a round crown
##   CUSTOM0, CUSTOM1         (position, UV.y), (normal, UV2.x) of a narrow one
##   CUSTOM2, CUSTOM3         the same of a conifer
##   UV = (PART_TRUNK or PART_CROWN, 0 at the crown's bottom .. 1 at its top)
##   UV2 = (a shade offset per blob (-1..1), so lumps read apart; the blob's
##   number, 1..4, 0 on the trunk), the same in every shape
##   trunks TRUNK_RADIUS (of the crown's width) around, which the shader
##   scales to the tree's real trunk
## Crowns are clusters of lumpy blobs (icosahedra) whose normals lean toward
## the normals of one ellipsoid around the whole crown, so the toon light
## wraps the crown as one soft ball while the outline stays lumpy. A round
## crown's blobs only just touch, so there's sky between them; the shader
## nudges each blob about per tree, raises the crown to the tree's size and
## thins it out up close. A conifer's blobs become stacked five-sided cones.
## Woods seen from afar are clumps of crowns, a mesh of their own in the
## round shape's layout (blobs, no trunk) that the same shader draws.
## Water towers (shaders/water_tower.gdshader):
##   UV = (part, 0 at the part's bottom .. 1 at its top)
##   UV2.x = around the tank (0..1) on the wall and roof, for staves and seams
## Street lights (shaders/street_light.gdshader), one mesh with both styles,
## the other style's parts folded away by the shader, and not at unit size:
## each part is measured from what the shader stretches it to.
##   UV = (part, 0 at the part's bottom .. 1 at its top)
##   cobra-head: the pole's y in its height (0..1); the mast arm's z in its
##   length (0..1, reaching along +z) and y in meters from the pole's top;
##   the luminaire (housing and lens) in meters from the arm's end
##   post-top: everything's y in the lamp's height (0..1), x and z in meters
## Plus their glows (street_light_glow.gdshader, a quad the shader turns to
## the camera) and pools of light on the ground (street_light_pool.gdshader,
## a 2D quad drawn into StreetLightMap).
## Street furniture (shaders/street_furniture.gdshader), in two meshes:
## small pieces (hydrants, benches, litter baskets, bike racks, parking
## meters) and large ones (bus shelters, LinkNYC kiosks, subway entrances,
## traffic signals, newsstands). Each mesh holds all its pieces' shapes one
## after another, and the shader folds away every shape but the instance's
## own (their vertices still run, so the meshes stay small). Shapes are built
## in meters at the sizes the tiles give each type and variant, standing on
## the origin with their front toward +z (the street) and their right toward
## -x; the shader scales them to each piece's height and width.
##   UV = (part (Furniture), 0)
##   UV2 = 0..1 across the part's face (around and up a turned part)
##   CUSTOM0 = (prop type, the variants it's drawn for as bits (1 << variant),
##             the height and width it's built at, m)
##   CUSTOM1 = (the face's width and height m, 0, 0), or for a light that
##             stays visible far away (signal lenses, subway globes) (its
##             center, radius m), about which the shader grows it
## Cars (shaders/car.gdshader), parked and moving, one mesh for every model
## (CityTileDecoder.CAR_*): the shader builds each model from its own table,
## so the mesh only says which point of a car each vertex is. Cars face +z
## (their right toward -x), stand on y = 0 and are centered on their
## footprint. A body below the windows (each side a fan about its middle, and
## the faces round its side profile), a cabin on it, a tire across each axle
## with a wheel at each end, the box truck's box, the taxi's roof sign, and a
## contact shadow under it all (an octagon on the ground).
##   UV = (part (Car), 0), UV2 = 0..1 across a wheel, box, sign or shadow
##   CUSTOM0 = which point:
##     body and cabin  (outline point, 0, side -1 or 1, 0); the outline runs
##                     round the profile from the rear bumper's bottom (0)
##                     over the deck, belt and hood to the front bumper's
##                     bottom (9); the cabin's from the rear window's base
##                     over the roof to the windshield's base (10..13); 14 is
##                     a body side's middle. The faces round the outline are
##                     numbered (Car) like the point they end at (rear) or
##                     start from (front).
##     tire and wheel  (axle: 0 rear or 1 front, corner 0..7 round it, side, 0)
##     box and sign    (x, y, z: 0 or 1, its low or high end, 0)
##     shadow          (x, z: -1..1 across the footprint, 0, 0)
## VERTEX is a rough sedan at unit size, for the editor only; the mesh's
## custom AABB holds every model at unit size (the instances scale it by
## their length and height).
## Subway cars (shaders/train.gdshader): one car in meters at the B
## Division's size (Trains.B_CAR), its front toward +z and its left toward
## +x, the rails at y = 0 under its middle: the body (its sides, a roof
## rounded along its edges, its ends), the equipment under its floor and two
## trucks. The shader paints doors, windows, cabs and lights by where they
## are on the car.
##   UV = (part (TrainPart), 0)

const PART_TRUNK := 0
const PART_CROWN := 1

const PART_TANK := 0
const PART_TANK_BOTTOM := 1
const PART_ROOF := 2
const PART_FINIAL := 3
const PART_STEEL := 4
const PART_PLATFORM := 5

const PART_POLE := 0
const PART_ARM := 1
const PART_HOUSING := 2
const PART_LENS := 3
const PART_POST := 4
const PART_LANTERN := 5
const PART_CAP := 6
## The sizes the street light mesh is built at (m): a cobra-head's pole and
## arm, and a post-top's height.
const COBRA_HEAD_HEIGHT := 9.0
const COBRA_HEAD_ARM := 2.6
const POST_TOP_HEIGHT := 4.4

## How far blob normals lean toward the whole crown's (0 = each blob its own
## ball, 1 = one smooth ball).
const CROWN_NORMAL_BLEND := 0.6
## Where the three shapes' crowns start (share of the height); the shader
## moves these heights to the tree's own crown base (shaders/tree.gdshader's
## CROWN_BOTTOM has the same numbers).
const ROUND_BOTTOM := 0.38
const NARROW_BOTTOM := 0.22
const CONIFER_BOTTOM := 0.12
## Trees' trunks' radius halfway up (they flare at the foot), as a share of
## the crown's width; shaders/tree.gdshader assumes it.
const TRUNK_RADIUS := 0.04

## Street furniture's parts (UV.x); shaders/street_furniture.gdshader has the
## same numbers.
enum Furniture {
	HYDRANT, HYDRANT_CAP, BASKET, BASKET_FILL, COMPACTOR, COMPACTOR_DOOR, SOLAR_PANEL, BIKE_RACK,
	METER, METER_FACE, METER_SIGN, BENCH, STEEL, ROOF, CEILING, GLASS, AD_BOX, POSTER, LINK, LINK_FRONT,
	SCREEN, STAIRWELL, RAILING, LAMP_POST, GLOBE, SIGNAL_POLE, SIGNAL_HEAD, SIGNAL_FACE, SIGNAL_LAMP,
	WALK_LAMP, STREET_SIGN, NEWSSTAND, NEWSSTAND_ROOF, MAGAZINES, BENCH_END,
}
## The variant bits of a shape drawn for every variant.
const ALL_VARIANTS := 255
## A traffic signal's lenses are this far apart (m), top (red) to bottom
## (green); its lit lens is built at the top one, and the shader moves it.
const SIGNAL_LAMP_SPACING := 0.35
## A subway stair's opening: its length along the curb (the stairs go down
## from its open end at +x) and its width (m).
const STAIR_LENGTH := 4.2
const STAIR_WIDTH := 1.8

## Cars' parts (UV.x); shaders/car.gdshader has the same numbers.
enum Car {
	BODY_SIDE, REAR_LOW, REAR, REAR_TOP, DECK, HOOD, NOSE, FRONT, FRONT_LOW, CABIN_SIDE, REAR_WINDOW, ROOF,
	WINDSHIELD, TIRE, WHEEL, BOX, SIGN, SHADOW,
}
## Every car model's size (length, width, height m) and wheels' radius (m),
## by CityTileDecoder.CAR_*, as shaders/car.gdshader builds them: traffic
## sizes its instances by them (and rolls the wheels by distance over radius).
const CAR_SIZES: Array[Vector3] = [Vector3(4.7, 1.85, 1.45), Vector3(4.2, 1.8, 1.5), Vector3(4.9, 1.95, 1.75),
	Vector3(5.1, 2.0, 1.8), Vector3(5.7, 2.0, 1.85), Vector3(5.6, 2.05, 2.5), Vector3(4.8, 1.85, 1.5),
	Vector3(7.5, 2.4, 3.3), Vector3(12.2, 2.6, 3.2)]
const CAR_WHEEL_RADII: Array[float] = [0.33, 0.31, 0.37, 0.35, 0.4, 0.36, 0.33, 0.48, 0.5]
## Corners round a wheel.
const CAR_WHEEL_SIDES := 8
## Every model at unit size (length and height 1), with its wheels, the
## taxi's sign and the contact shadow, turned any way (the shader turns each
## car to its yaw, so the box is as wide as it's long).
const CAR_BOUNDS := AABB(Vector3(-0.56, -0.02, -0.56), Vector3(1.12, 1.27, 1.12))
## The rough sedan's outline at unit size (z, y), numbered as above, and a
## side's middle; its half width.
const _CAR_OUTLINE: Array[Vector2] = [Vector2(-0.474, 0.207), Vector2(-0.5, 0.29), Vector2(-0.5, 0.607),
	Vector2(-0.474, 0.69), Vector2(-0.266, 0.662), Vector2(0.245, 0.662), Vector2(0.457, 0.552), Vector2(0.5, 0.414),
	Vector2(0.5, 0.29), Vector2(0.474, 0.207), Vector2(-0.266, 0.662), Vector2(-0.128, 1.0), Vector2(0.096, 1.0),
	Vector2(0.245, 0.662), Vector2(-0.01, 0.434)]
const _CAR_HALF_WIDTH := 0.19

## Subway cars' parts (UV.x); shaders/train.gdshader has the same numbers.
enum TrainPart { SIDE, ROOF, END, UNDER, TRUCK }
## A subway car's cross-section (x, y m) round from the bottom of its left
## side over the roof to the bottom of its right side, at Trains.B_CAR's
## size; the parts of its faces.
const _TRAIN_PROFILE: Array[Vector2] = [Vector2(1.525, 0.95), Vector2(1.525, 3.2), Vector2(1.37, 3.52),
	Vector2(0.95, 3.7), Vector2(-0.95, 3.7), Vector2(-1.37, 3.52), Vector2(-1.525, 3.2), Vector2(-1.525, 0.95)]
const _TRAIN_PROFILE_PARTS: Array[int] = [TrainPart.SIDE, TrainPart.ROOF, TrainPart.ROOF, TrainPart.ROOF,
	TrainPart.ROOF, TrainPart.ROOF, TrainPart.SIDE]
## Its trucks' middles (share of its length from its middle), and their
## half sizes (m); the equipment under its floor.
const _TRAIN_TRUCKS := 0.354
const _TRAIN_TRUCK_SIZE := Vector3(1.25, 0.85, 1.35)
const _TRAIN_UNDER := AABB(Vector3(-1.28, 0.4, -7.6), Vector3(2.56, 0.55, 15.2))

static var _car_mesh: ArrayMesh
static var _train_mesh: ArrayMesh


## Every tree: a trunk up into a crown of four blobs, in three shapes (see
## above). 90 triangles.
static func tree() -> ArrayMesh:
	var round := _Builder.new()
	_trunk(round, 0.62)
	var crown := _Crown.new(ROUND_BOTTOM, 1.0, round)
	# Blobs: center, radii (unit space: 1 = the crown's width and the tree's
	# height). A top blob over three clumps around it, each at its own height
	# and only just touching the next, like a street tree's scaffold limbs.
	crown.blob(Vector3(0.03, 0.82, -0.04), Vector3(0.26, 0.18, 0.26), 0.3, 1)
	crown.blob(Vector3(-0.24, 0.68, 0.08), Vector3(0.24, 0.20, 0.24), -0.5, 2)
	crown.blob(Vector3(0.22, 0.62, 0.14), Vector3(0.24, 0.20, 0.24), 0.9, 3)
	crown.blob(Vector3(0.05, 0.56, -0.25), Vector3(0.22, 0.18, 0.22), -0.1, 4)
	# Columnar or oval (Callery pear, ginkgo): stacked blobs on a slimmer trunk.
	var narrow := _Builder.new()
	_trunk(narrow, 0.4)
	crown = _Crown.new(NARROW_BOTTOM, 1.0, narrow)
	crown.blob(Vector3(0.0, 0.42, 0.01), Vector3(0.47, 0.21, 0.47), -0.4, 1)
	crown.blob(Vector3(0.03, 0.62, -0.02), Vector3(0.45, 0.21, 0.45), 0.6, 2)
	crown.blob(Vector3(-0.02, 0.80, 0.01), Vector3(0.35, 0.16, 0.35), 0.0, 3)
	crown.blob(Vector3(0.01, 0.92, 0.0), Vector3(0.21, 0.08, 0.21), 0.4, 4)
	# Conifer: four cones (base height, radius, apex height), smaller going up.
	var conifer := _Builder.new()
	_trunk(conifer, 0.3)
	crown = _Crown.new(CONIFER_BOTTOM, 1.0, conifer)
	crown.cone(CONIFER_BOTTOM, 0.5, 0.56, -0.3, 1)
	crown.cone(0.33, 0.42, 0.73, 0.4, 2)
	crown.cone(0.53, 0.32, 0.88, -0.1, 3)
	crown.cone(0.70, 0.2, 1.0, 0.5, 4)
	return round.commit([narrow, conifer])


## A stand-in that casts trees' shadows, cheaper than a tree: a trunk and one
## plain ball (or cone) a little inside the crown, so the crown's own lumps on
## the sunny side stay lit. In the same three shapes (its blob is number 0:
## the shader leaves it whole and where it is). 30 triangles.
static func tree_shadow() -> ArrayMesh:
	var round := _Builder.new()
	_trunk(round, 0.62)
	_Crown.new(ROUND_BOTTOM, 1.0, round).blob(Vector3(0.0, 0.69, 0.0), Vector3(0.38, 0.25, 0.38), 0.0, 0)
	var narrow := _Builder.new()
	_trunk(narrow, 0.4)
	_Crown.new(NARROW_BOTTOM, 1.0, narrow).blob(Vector3(0.0, 0.62, 0.0), Vector3(0.38, 0.33, 0.38), 0.0, 0)
	var conifer := _Builder.new()
	_trunk(conifer, 0.3)
	_Crown.new(CONIFER_BOTTOM, 1.0, conifer).cone(CONIFER_BOTTOM, 0.42, 1.0, 0.0, 0)
	return round.commit([narrow, conifer])


## Woods seen from afar (CityTileDecoder.PROP_CANOPY): a clump of crowns,
## one lumpy blob and no trunk (the woods' clumps overlap into one lumpy
## canopy that hides them). Drawn by tree.gdshader in the round shape's
## place. 20 triangles: there are a lot of them, and from a few hundred
## meters off a second blob (tried) looked the same and cost twice as much.
static func canopy() -> ArrayMesh:
	var b := _Builder.new()
	_Crown.new(0.25, 1.0, b).blob(Vector3(0.0, 0.62, 0.0), Vector3(0.48, 0.38, 0.48), 0.2, 1)
	return b.commit()


## New York's rooftop water tank: a wooden (or steel) tank with a conical
## roof and a finial, on a platform over six braced steel legs. 140 triangles.
static func water_tower() -> ArrayMesh:
	var b := _Builder.new()
	const SIDES := 12
	const RADIUS := 0.5
	const TANK_BOTTOM := 0.36
	const TANK_TOP := 0.8
	const ROOF_RADIUS := 0.53
	const ROOF_TOP := 0.95
	# Tank wall, with a seam of doubled vertices so UV2.x runs 0..1 around.
	var bottom_ring := PackedInt32Array()
	var top_ring := PackedInt32Array()
	for i in SIDES + 1:
		var a := TAU * i / SIDES
		var out := Vector3(cos(a), 0.0, sin(a))
		bottom_ring.append(b.vertex(out * RADIUS + Vector3.UP * TANK_BOTTOM, out, Vector2(PART_TANK, 0.0), Vector2(float(i) / SIDES, 0.0)))
		top_ring.append(b.vertex(out * RADIUS + Vector3.UP * TANK_TOP, out, Vector2(PART_TANK, 1.0), Vector2(float(i) / SIDES, 0.0)))
	for i in SIDES:
		var out := Vector3(cos(TAU * (i + 0.5) / SIDES), 0.0, sin(TAU * (i + 0.5) / SIDES))
		b.quad(bottom_ring[i], bottom_ring[i + 1], top_ring[i + 1], top_ring[i], out)
	# Tank bottom, seen from the street.
	var floor_ring := PackedInt32Array()
	for i in SIDES:
		var a := TAU * i / SIDES
		floor_ring.append(b.vertex(Vector3(cos(a) * RADIUS, TANK_BOTTOM, sin(a) * RADIUS), Vector3.DOWN, Vector2(PART_TANK_BOTTOM, 0.0)))
	for i in range(1, SIDES - 1):
		b.triangle(floor_ring[0], floor_ring[i], floor_ring[i + 1], Vector3.DOWN)
	# Conical roof overhanging the tank a little (the material is double-sided,
	# so its underside shows from below).
	var slope := Vector2(ROOF_TOP - TANK_TOP, ROOF_RADIUS).normalized()
	var eave := PackedInt32Array()
	for i in SIDES + 1:
		var a := TAU * i / SIDES
		var n := Vector3(cos(a) * slope.x, slope.y, sin(a) * slope.x)
		eave.append(b.vertex(Vector3(cos(a) * ROOF_RADIUS, TANK_TOP, sin(a) * ROOF_RADIUS), n, Vector2(PART_ROOF, 0.0), Vector2(float(i) / SIDES, 0.0)))
	for i in SIDES:
		var a := TAU * (i + 0.5) / SIDES
		var n := Vector3(cos(a) * slope.x, slope.y, sin(a) * slope.x)
		var apex := b.vertex(Vector3(0.0, ROOF_TOP, 0.0), n, Vector2(PART_ROOF, 1.0), Vector2((i + 0.5) / SIDES, 0.0))
		b.triangle(eave[i], eave[i + 1], apex, n)
	# Finial: a little six-sided spike on top.
	_spike(b, 6, Vector3(0.0, ROOF_TOP - 0.01, 0.0), 0.035, 1.0, PART_FINIAL)
	# Platform under the tank: a hexagonal slab, sides and underside.
	const PLATFORM_BOTTOM := 0.32
	const PLATFORM_RADIUS := 0.48
	var under := PackedInt32Array()
	for k in 6:
		var a0 := TAU * (k + 0.5) / 6.0
		var a1 := TAU * (k + 1.5) / 6.0
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * PLATFORM_RADIUS
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * PLATFORM_RADIUS
		var out := ((p0 + p1) * 0.5).normalized()
		var uv := Vector2(PART_PLATFORM, 0.0)
		b.quad(b.vertex(p0 + Vector3.UP * PLATFORM_BOTTOM, out, uv), b.vertex(p1 + Vector3.UP * PLATFORM_BOTTOM, out, uv),
			b.vertex(p1 + Vector3.UP * TANK_BOTTOM, out, Vector2(PART_PLATFORM, 1.0)),
			b.vertex(p0 + Vector3.UP * TANK_BOTTOM, out, Vector2(PART_PLATFORM, 1.0)), out)
		under.append(b.vertex(p0 + Vector3.UP * PLATFORM_BOTTOM, Vector3.DOWN, uv))
	for k in range(1, 5):
		b.triangle(under[0], under[k], under[k + 1], Vector3.DOWN)
	# Six steel legs, splayed a little, with X bracing between neighbors.
	const LEG_HALF := 0.022
	var feet: Array[Vector3] = []
	var heads: Array[Vector3] = []
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		feet.append(dir * 0.42)
		heads.append(dir * 0.37 + Vector3.UP * PLATFORM_BOTTOM)
		_beam(b, feet[k], heads[k], LEG_HALF)
	for k in 6:
		var n := (k + 1) % 6
		var out := ((feet[k] + feet[n]) * 0.5).normalized()
		var low := 0.04 / PLATFORM_BOTTOM
		var high := 0.92
		_strut(b, feet[k].lerp(heads[k], low), feet[n].lerp(heads[n], high), out, 0.012)
		_strut(b, feet[n].lerp(heads[n], low), feet[k].lerp(heads[k], high), out, 0.012)
	return b.commit()


## New York's street lights, both styles in one mesh (see above):
## a cobra-head, a tapered steel pole whose mast arm curves up and out over
## the street to a long luminaire with a lens underneath (52 triangles); and a
## historic post-top, a fluted cast-iron post with a glass lantern under a
## cap (78 triangles).
static func street_light() -> ArrayMesh:
	var b := _Builder.new()
	# Cobra-head: the pole, flaring into a base at the foot.
	_lathe(b, 6, [Vector2(0.0, 0.16), Vector2(0.55, 0.13), Vector2(COBRA_HEAD_HEIGHT, 0.07)], PART_POLE)
	# The mast arm, from just below the pole's top, rising to the luminaire.
	var top := COBRA_HEAD_HEIGHT
	var arm := [Vector3(0.0, top - 0.6, 0.0), Vector3(0.0, top - 0.2, COBRA_HEAD_ARM * 0.45), Vector3(0.0, top - 0.08, COBRA_HEAD_ARM)]
	for k in 2:
		_beam(b, arm[k], arm[k + 1], 0.045, PART_ARM)
	# The luminaire: a long housing, wider and lower toward its front, with
	# the lens underneath.
	var end := Vector3(0.0, top - 0.08, COBRA_HEAD_ARM)
	var back := [Vector3(-0.13, 0.05, -0.12), Vector3(0.13, 0.05, -0.12), Vector3(0.13, -0.09, -0.12), Vector3(-0.13, -0.09, -0.12)]
	var front := [Vector3(-0.17, 0.0, 0.62), Vector3(0.17, 0.0, 0.62), Vector3(0.17, -0.12, 0.62), Vector3(-0.17, -0.12, 0.62)]
	var corners: Array[int] = []
	for k in 4:
		var p: Vector3 = back[k]
		corners.append(b.vertex(end + p, p.normalized(), Vector2(PART_HOUSING, 0.0 if p.y < 0.0 else 1.0)))
	for k in 4:
		var p: Vector3 = front[k]
		corners.append(b.vertex(end + p, p.normalized(), Vector2(PART_HOUSING, 0.0 if p.y < 0.0 else 1.0)))
	var center := end + Vector3(0.0, -0.04, 0.25)
	for face in [[0, 1, 5, 4], [1, 2, 6, 5], [3, 0, 4, 7], [0, 3, 2, 1], [4, 5, 6, 7]]:
		var mid := Vector3.ZERO
		for k in face:
			mid += b.positions[corners[k]]
		b.quad(corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]], mid / 4.0 - center)
	var lens: Array[int] = []
	for k in [2, 3, 7, 6]:
		var p: Vector3 = (back + front)[k]
		lens.append(b.vertex(end + p + Vector3(0.0, -0.005, 0.0), Vector3.DOWN, Vector2(PART_LENS, 0.0)))
	b.quad(lens[0], lens[1], lens[2], lens[3], Vector3.DOWN)
	# Post-top: a fluted post on a stepped base, a glass lantern, a cap.
	_lathe(b, 6, [Vector2(0.0, 0.19), Vector2(0.75, 0.14), Vector2(0.9, 0.085), Vector2(3.4, 0.065)], PART_POST)
	_lathe(b, 6, [Vector2(3.4, 0.09), Vector2(3.75, 0.25), Vector2(4.15, 0.2)], PART_LANTERN)
	_lathe(b, 6, [Vector2(4.13, 0.23), Vector2(4.3, 0.08), Vector2(POST_TOP_HEIGHT, 0.0)], PART_CAP)
	# Measured from what the shader stretches them to (see above).
	for i in b.positions.size():
		var p := b.positions[i]
		match int(b.uvs[i].x):
			PART_POLE:
				p.y /= COBRA_HEAD_HEIGHT
			PART_ARM:
				p.y -= COBRA_HEAD_HEIGHT
				p.z /= COBRA_HEAD_ARM
			PART_HOUSING, PART_LENS:
				p.y -= COBRA_HEAD_HEIGHT
				p.z -= COBRA_HEAD_ARM
			_:
				p.y /= POST_TOP_HEIGHT
		b.positions[i] = p
	return b.commit()


## A street light's glow: a quad (corners -1..1 in UV) that the shader turns
## to face the camera at the lamp's head.
static func street_light_glow() -> ArrayMesh:
	var b := _Builder.new()
	var corners: Array[int] = []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(b.vertex(Vector3(c.x, c.y, 0.0), Vector3.BACK, c))
	b.quad(corners[0], corners[1], corners[2], corners[3], Vector3.BACK)
	return b.commit()


## A street light's pool of light, as a 2D quad from -1 to 1 (StreetLightMap).
static func light_pool() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Small street furniture (see above): a hydrant, a CityBench, a wire litter
## basket and a solar compactor, a hoop and a U bike rack, and a Muni-Meter
## pay station.
static func street_furniture_small() -> ArrayMesh:
	var k := _Kit.new()
	_hydrant(k)
	_bench(k)
	_litter_baskets(k)
	_bike_racks(k)
	_parking_meter(k)
	return k.build()


## Large street furniture (see above): a bus shelter, a LinkNYC kiosk and a
## Link5G pole, a subway stair and a street elevator, a traffic signal, and a
## newsstand.
static func street_furniture_large() -> ArrayMesh:
	var k := _Kit.new()
	_bus_shelter(k)
	_linknyc(k)
	_subway_entrances(k)
	_traffic_signal(k)
	_newsstand(k)
	return k.build()


## New York's hydrant: a barrel on a flared foot, a bonnet with an operating
## nut on top, hose outlets on both sides and the bigger pumper outlet facing
## the street. The bonnet and the outlets' ends are the caps (colored apart).
static func _hydrant(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_HYDRANT, ALL_VARIANTS, 0.75, 0.4)
	_turned(k, 6, [Vector2(0.0, 0.15), Vector2(0.07, 0.11), Vector2(0.5, 0.11)], Furniture.HYDRANT)
	_turned(k, 6, [Vector2(0.5, 0.11), Vector2(0.54, 0.14), Vector2(0.6, 0.13), Vector2(0.67, 0.09),
		Vector2(0.7, 0.04), Vector2(0.75, 0.035), Vector2(0.75, 0.0)], Furniture.HYDRANT_CAP)
	var outlets := _faces(Furniture.HYDRANT)
	outlets["+x"] = Furniture.HYDRANT_CAP
	outlets["-x"] = Furniture.HYDRANT_CAP
	_box(k, Vector3(-0.19, 0.34, -0.045), Vector3(0.19, 0.43, 0.045), outlets)
	var pumper := _faces(Furniture.HYDRANT, "-z")
	pumper["+z"] = Furniture.HYDRANT_CAP
	_box(k, Vector3(-0.065, 0.27, 0.0), Vector3(0.065, 0.4, 0.19), pumper)


## A CityBench: a perforated steel seat and backrest facing the street, on
## legs that rise into armrests at the ends and in the middle (the shader
## cuts them out of flat panels).
static func _bench(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_BENCH, ALL_VARIANTS, 0.85, 1.8)
	_panel(k, Vector3(-0.9, 0.45, 0.24), Vector3(1.8, 0.0, 0.0), Vector3(0.0, -0.03, -0.46), Furniture.BENCH)
	_panel(k, Vector3(-0.9, 0.39, 0.25), Vector3(1.8, 0.0, 0.0), Vector3(0.0, 0.06, 0.0), Furniture.BENCH)
	_panel(k, Vector3(-0.9, 0.49, -0.23), Vector3(1.8, 0.0, 0.0), Vector3(0.0, 0.36, -0.08), Furniture.BENCH)
	for x: float in [-0.9, 0.0, 0.9]:
		_panel(k, Vector3(x, 0.0, -0.27), Vector3(0.0, 0.0, 0.52), Vector3(0.0, 0.64, 0.0), Furniture.BENCH_END)


## Litter baskets: the green wire basket (variant 0), open at the top with
## trash inside, and a solar compactor (1), a box with a slanted solar panel
## on top and its hopper door toward the sidewalk.
static func _litter_baskets(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_LITTER_BASKET, 1 << CityTileDecoder.BASKET_WIRE, 0.9, 0.6)
	_turned(k, 8, [Vector2(0.0, 0.23), Vector2(0.9, 0.3)], Furniture.BASKET, Vector3.ZERO, true)
	_disc(k, Vector3(0.0, 0.72, 0.0), 0.28, 8, Furniture.BASKET_FILL)
	k.shape = Vector4(CityTileDecoder.PROP_LITTER_BASKET, 1 << CityTileDecoder.BASKET_COMPACTOR, 1.2, 0.7)
	var lo := Vector3(-0.33, 0.0, -0.3)
	var hi := Vector3(0.33, 0.0, 0.3)
	var front_y := 1.06  # the panel slopes up to the back
	var back_y := 1.2
	var corners: Array[Vector3] = [Vector3(lo.x, 0.0, hi.z), Vector3(hi.x, 0.0, hi.z), Vector3(hi.x, 0.0, lo.z), Vector3(lo.x, 0.0, lo.z)]
	var tops: Array[float] = [front_y, front_y, back_y, back_y]
	for side in 4:
		var a := corners[side]
		var b := corners[(side + 1) % 4]
		var part := Furniture.COMPACTOR_DOOR if side == 2 else Furniture.COMPACTOR
		_quad(k, a, b, Vector3(b.x, tops[(side + 1) % 4], b.z), Vector3(a.x, tops[side], a.z), part)
	_quad(k, Vector3(lo.x, front_y, hi.z), Vector3(hi.x, front_y, hi.z), Vector3(hi.x, back_y, lo.z),
		Vector3(lo.x, back_y, lo.z), Furniture.SOLAR_PANEL)


## Bike racks along the curb: the round CityRack hoop on a short stem
## (variant 0) and an inverted U (1), as thin tubes.
static func _bike_racks(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_BIKE_RACK, 1 << CityTileDecoder.BIKE_RACK_HOOP, 0.9, 0.9)
	var ring: Array[Vector3] = []
	for i in 9:
		var a := TAU * i / 9.0
		ring.append(Vector3(sin(a) * 0.4, 0.48 + cos(a) * 0.4, 0.0))
	_tube(k, ring, 0.022, Vector3.BACK, Furniture.BIKE_RACK, true)
	_tube(k, [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.09, 0.0)], 0.03, Vector3.BACK, Furniture.BIKE_RACK)
	k.shape = Vector4(CityTileDecoder.PROP_BIKE_RACK, 1 << CityTileDecoder.BIKE_RACK_U, 0.9, 1.2)
	_tube(k, [Vector3(-0.5, 0.0, 0.0), Vector3(-0.5, 0.74, 0.0), Vector3(-0.38, 0.88, 0.0), Vector3(0.38, 0.88, 0.0),
		Vector3(0.5, 0.74, 0.0), Vector3(0.5, 0.0, 0.0)], 0.024, Vector3.BACK, Furniture.BIKE_RACK)


## A Muni-Meter: a gray pay station on a pedestal, its screen and keypad
## toward the sidewalk, under a blue sign that faces along the street.
static func _parking_meter(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_PARKING_METER, ALL_VARIANTS, 1.6, 0.35)
	_box(k, Vector3(-0.08, 0.0, -0.07), Vector3(0.08, 0.78, 0.07), _faces(Furniture.METER, "+y -y"))
	var faces := _faces(Furniture.METER, "-y")
	faces["-z"] = Furniture.METER_FACE
	_box(k, Vector3(-0.16, 0.78, -0.12), Vector3(0.16, 1.34, 0.12), faces)
	_panel(k, Vector3(0.0, 1.34, 0.15), Vector3(0.0, 0.0, -0.3), Vector3(0.0, 0.26, 0.0), Furniture.METER_SIGN)


## A bus shelter (the city's glass and steel design): a thin roof on posts at
## the back, a glass back wall and one glass end, a lit ad panel at the other
## end, and a bench inside. The front, toward the curb, is open.
static func _bus_shelter(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_BUS_SHELTER, ALL_VARIANTS, 2.6, 4.2)
	var roof := _faces(Furniture.ROOF, "-y")
	roof["-y"] = Furniture.CEILING
	_box(k, Vector3(-2.2, 2.46, -0.85), Vector3(2.2, 2.6, 0.85), roof)
	for x: float in [-2.1, 2.02]:
		_box(k, Vector3(x, 0.0, -0.81), Vector3(x + 0.08, 2.46, -0.73), _faces(Furniture.STEEL, "+y -y"))
	_panel(k, Vector3(-2.02, 0.1, -0.77), Vector3(4.04, 0.0, 0.0), Vector3(0.0, 2.3, 0.0), Furniture.GLASS)
	_panel(k, Vector3(-2.06, 0.1, 0.3), Vector3(0.0, 0.0, -1.03), Vector3(0.0, 2.3, 0.0), Furniture.GLASS)
	_box(k, Vector3(1.9, 0.12, -0.73), Vector3(2.08, 2.36, 0.62), _faces(Furniture.AD_BOX, "-y"))
	_panel(k, Vector3(2.09, 0.24, 0.52), Vector3(0.0, 0.0, -1.14), Vector3(0.0, 1.98, 0.0), Furniture.POSTER)
	_panel(k, Vector3(1.89, 0.24, -0.62), Vector3(0.0, 0.0, 1.14), Vector3(0.0, 1.98, 0.0), Furniture.POSTER)
	_panel(k, Vector3(-1.5, 0.47, -0.4), Vector3(2.3, 0.0, 0.0), Vector3(0.0, 0.0, -0.32), Furniture.STEEL)
	_panel(k, Vector3(-1.5, 0.42, -0.4), Vector3(2.3, 0.0, 0.0), Vector3(0.0, 0.05, 0.0), Furniture.STEEL)
	for x: float in [-1.4, 0.7]:
		_panel(k, Vector3(x, 0.0, -0.72), Vector3(0.0, 0.0, 0.3), Vector3(0.0, 0.47, 0.0), Furniture.STEEL)


## LinkNYC: the Link1.0 kiosk (variant 0), a slim slab with a big screen on
## each side (facing along the sidewalk) and a tablet toward the street; and
## the Link5G pole (1), a wider kiosk with screens under a tall column.
static func _linknyc(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_LINKNYC, 1 << CityTileDecoder.LINKNYC_KIOSK, 2.9, 0.9)
	var faces := _faces(Furniture.LINK, "-y")
	faces["+z"] = Furniture.LINK_FRONT
	_box(k, Vector3(-0.14, 0.0, -0.45), Vector3(0.14, 2.9, 0.45), faces)
	_panel(k, Vector3(0.15, 1.12, 0.34), Vector3(0.0, 0.0, -0.68), Vector3(0.0, 1.22, 0.0), Furniture.SCREEN)
	_panel(k, Vector3(-0.15, 1.12, -0.34), Vector3(0.0, 0.0, 0.68), Vector3(0.0, 1.22, 0.0), Furniture.SCREEN)
	k.shape = Vector4(CityTileDecoder.PROP_LINKNYC, 1 << CityTileDecoder.LINKNYC_5G, 9.0, 0.6)
	_box(k, Vector3(-0.3, 0.0, -0.3), Vector3(0.3, 2.75, 0.3), faces)
	_panel(k, Vector3(0.31, 1.0, 0.22), Vector3(0.0, 0.0, -0.44), Vector3(0.0, 1.45, 0.0), Furniture.SCREEN)
	_panel(k, Vector3(-0.31, 1.0, -0.22), Vector3(0.0, 0.0, 0.44), Vector3(0.0, 1.45, 0.0), Furniture.SCREEN)
	_box(k, Vector3(-0.19, 2.75, -0.19), Vector3(0.19, 9.0, 0.19), _faces(Furniture.LINK, "-y"))


## Subway entrances. A stair (variants 0 and 1): an opening in the sidewalk
## along the curb, which the shader fills with steps going down from its open
## end (+x) into the dark, a railing on the other three sides, and a globe
## lamp on a post either side of the open end (green for an entrance, red for
## exit only). A street elevator (2): a small glass box under a flat roof.
static func _subway_entrances(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_SUBWAY_ENTRANCE, (1 << CityTileDecoder.SUBWAY_STAIR) | (1 << CityTileDecoder.SUBWAY_STAIR_EXIT), 2.5,
		STAIR_WIDTH)
	var half := Vector2(STAIR_LENGTH, STAIR_WIDTH) * 0.5
	_panel(k, Vector3(-half.x, 0.04, half.y), Vector3(STAIR_LENGTH, 0.0, 0.0), Vector3(0.0, 0.0, -STAIR_WIDTH),
		Furniture.STAIRWELL)
	var rail := 1.05
	_panel(k, Vector3(-half.x, 0.0, half.y), Vector3(STAIR_LENGTH - 0.08, 0.0, 0.0), Vector3(0.0, rail, 0.0), Furniture.RAILING)
	_panel(k, Vector3(half.x - 0.08, 0.0, -half.y), Vector3(0.08 - STAIR_LENGTH, 0.0, 0.0), Vector3(0.0, rail, 0.0),
		Furniture.RAILING)
	_panel(k, Vector3(-half.x, 0.0, -half.y), Vector3(0.0, 0.0, STAIR_WIDTH), Vector3(0.0, rail, 0.0), Furniture.RAILING)
	for z: float in [-half.y, half.y]:
		_turned(k, 4, [Vector2(0.0, 0.085), Vector2(2.14, 0.045)], Furniture.LAMP_POST, Vector3(half.x, 0.0, z))
		_globe(k, Vector3(half.x, 2.31, z), 0.19, Furniture.GLOBE)
	k.shape = Vector4(CityTileDecoder.PROP_SUBWAY_ENTRANCE, 1 << CityTileDecoder.SUBWAY_ELEVATOR, 3.0, 2.2)
	_box(k, Vector3(-1.1, 0.0, -0.8), Vector3(1.1, 2.75, 0.8), _faces(Furniture.GLASS, "+y -y"))
	var roof := _faces(Furniture.STEEL, "-y")
	roof["-y"] = Furniture.CEILING
	_box(k, Vector3(-1.2, 2.75, -0.9), Vector3(1.2, 3.0, 0.9), roof)


## A traffic signal on the corner, facing the drivers it controls (+z): a
## pole with a mast arm over the road (to its right, -x) carrying a signal
## head and a street name sign, a second head on the pole, and a pedestrian
## signal facing across the road. Each head's lit lens is a quad of its own.
## Under an el (variant SIGNAL_ON_COLUMN) only the heads on the pole are
## drawn, mounted on a column of the el.
static func _traffic_signal(k: _Kit) -> void:
	var on_pole := 1 << CityTileDecoder.SIGNAL_ON_POLE
	k.shape = Vector4(CityTileDecoder.PROP_TRAFFIC_SIGNAL, on_pole, 6.2, 0.4)
	_turned(k, 6, [Vector2(0.0, 0.16), Vector2(0.4, 0.12), Vector2(0.5, 0.095), Vector2(6.1, 0.08), Vector2(6.2, 0.0)],
		Furniture.SIGNAL_POLE)
	_beam(k, Vector3(-0.05, 5.72, 0.0), Vector3(-4.6, 5.95, 0.0), 0.055, Furniture.SIGNAL_POLE)
	var head := _faces(Furniture.SIGNAL_HEAD)
	head["+z"] = Furniture.SIGNAL_FACE
	for top: Vector3 in [Vector3(-4.1, 5.88, 0.0), Vector3(-0.26, 4.01, 0.0)]:
		# The mast arm's head only on a pole.
		k.shape.y = on_pole if top.x < -1.0 else ALL_VARIANTS
		_box(k, top + Vector3(-0.18, -1.06, -0.13), top + Vector3(0.18, 0.0, 0.11), head)
		var lens := top + Vector3(0.0, -0.18, 0.125)
		k.extra = Vector4(lens.x, lens.y, lens.z, 0.125)
		_panel(k, lens + Vector3(-0.125, -0.125, 0.0), Vector3(0.25, 0.0, 0.0), Vector3(0.0, 0.25, 0.0), Furniture.SIGNAL_LAMP)
		k.extra = Vector4.ZERO
	var walk := _faces(Furniture.SIGNAL_HEAD, "+x")
	_box(k, Vector3(-0.38, 2.2, -0.23), Vector3(-0.1, 2.66, 0.23), walk)
	k.extra = Vector4(-0.39, 2.43, 0.0, 0.18)
	_panel(k, Vector3(-0.39, 2.25, -0.18), Vector3(0.0, 0.0, 0.36), Vector3(0.0, 0.36, 0.0), Furniture.WALK_LAMP)
	k.extra = Vector4.ZERO
	k.shape.y = on_pole
	_panel(k, Vector3(-2.7, 5.4, 0.0), Vector3(1.7, 0.0, 0.0), Vector3(0.0, 0.3, 0.0), Furniture.STREET_SIGN)


## A newsstand: a steel box under a green roof that overhangs the sidewalk
## side, with racks of magazines in its windows there and at both ends, and
## an ad toward the street.
static func _newsstand(k: _Kit) -> void:
	k.shape = Vector4(CityTileDecoder.PROP_NEWSSTAND, ALL_VARIANTS, 2.7, 3.0)
	_box(k, Vector3(-1.5, 0.0, -0.8), Vector3(1.5, 2.45, 0.8), _faces(Furniture.NEWSSTAND, "+y -y"))
	var roof := _faces(Furniture.NEWSSTAND_ROOF)
	roof["-y"] = Furniture.CEILING
	_box(k, Vector3(-1.62, 2.45, -1.08), Vector3(1.62, 2.7, 0.92), roof)
	_panel(k, Vector3(1.35, 0.55, -0.81), Vector3(-2.7, 0.0, 0.0), Vector3(0.0, 1.55, 0.0), Furniture.MAGAZINES)
	_panel(k, Vector3(1.51, 0.55, 0.62), Vector3(0.0, 0.0, -1.24), Vector3(0.0, 1.55, 0.0), Furniture.MAGAZINES)
	_panel(k, Vector3(-1.51, 0.55, -0.62), Vector3(0.0, 0.0, 1.24), Vector3(0.0, 1.55, 0.0), Furniture.MAGAZINES)
	# An ad toward the street.
	_panel(k, Vector3(-1.2, 0.5, 0.81), Vector3(2.4, 0.0, 0.0), Vector3(0.0, 1.6, 0.0), Furniture.POSTER)


## Every car model (see above), one mesh shared by parked cars and traffic.
## 186 vertices, 128 triangles; a car draws all but the box and sign it
## hasn't (the shader folds them away).
static func car() -> ArrayMesh:
	if _car_mesh:
		return _car_mesh
	var k := _CarKit.new()
	# The body below the windows: each side a fan about its middle, then the
	# faces round its profile (but the bottom, and the top under the cabin).
	for side: float in [-1.0, 1.0]:
		var middle := k.outline_point(14, side, Car.BODY_SIDE)
		var ring: Array[int] = []
		for id in 10:
			ring.append(k.outline_point(id, side, Car.BODY_SIDE))
		for i in 10:
			k.triangle(middle, ring[i], ring[(i + 1) % 10], Vector3(side, 0.0, 0.0))
	for part: int in [Car.REAR_LOW, Car.REAR, Car.REAR_TOP, Car.DECK, Car.HOOD, Car.NOSE, Car.FRONT, Car.FRONT_LOW]:
		var from := part - 1 if part <= Car.DECK else part
		_car_outline_face(k, from, part)
	# The cabin: its sides (the windows), the rear window, the roof and the
	# windshield.
	for side: float in [-1.0, 1.0]:
		var corners: Array[int] = []
		for id in range(10, 14):
			corners.append(k.outline_point(id, side, Car.CABIN_SIDE))
		k.quad(corners[0], corners[1], corners[2], corners[3], Vector3(side, 0.0, 0.0))
	for part: int in [Car.REAR_WINDOW, Car.ROOF, Car.WINDSHIELD]:
		_car_outline_face(k, part, part)
	# A tire across each axle (its middle hidden under the car), a wheel at
	# each end.
	for axle in 2:
		var rings: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
		for end in 2:
			var side := -1.0 if end == 0 else 1.0
			var cap := PackedInt32Array()
			for i in CAR_WHEEL_SIDES:
				var a := TAU * i / CAR_WHEEL_SIDES
				var around := Vector2(sin(a), cos(a))
				var rough := Vector3(side * _CAR_HALF_WIDTH, 0.07 * (1.0 + around.y), (axle - 0.5) * 0.6 + 0.07 * around.x)
				var code := Vector4(axle, i, side, 0.0)
				rings[end].append(k.coded(rough, Vector3(0.0, around.y, around.x), Car.TIRE, code))
				cap.append(k.coded(rough, Vector3(side, 0.0, 0.0), Car.WHEEL, code, Vector2(around.x, around.y) * 0.5 + Vector2(0.5, 0.5)))
			for i in range(1, CAR_WHEEL_SIDES - 1):
				k.triangle(cap[0], cap[i], cap[i + 1], Vector3(side, 0.0, 0.0))
		for i in CAR_WHEEL_SIDES:
			var j := (i + 1) % CAR_WHEEL_SIDES
			var a := TAU * (i + 0.5) / CAR_WHEEL_SIDES
			k.quad(rings[0][i], rings[0][j], rings[1][j], rings[1][i], Vector3(0.0, cos(a), sin(a)))
	# The box truck's box, and the taxi's roof sign.
	_car_box(k, Car.BOX, AABB(Vector3(-0.16, 0.34, -0.5), Vector3(0.32, 0.66, 0.7)))
	_car_box(k, Car.SIGN, AABB(Vector3(-0.03, 1.0, -0.1), Vector3(0.06, 0.2, 0.2)))
	# The contact shadow: an octagon a little bigger than the footprint.
	var shadow := PackedInt32Array()
	for corner: Vector2 in [Vector2(1.0, 0.88), Vector2(0.8, 1.0), Vector2(-0.8, 1.0), Vector2(-1.0, 0.88),
			Vector2(-1.0, -0.88), Vector2(-0.8, -1.0), Vector2(0.8, -1.0), Vector2(1.0, -0.88)]:
		var rough := Vector3(corner.x * (_CAR_HALF_WIDTH + 0.03), 0.0, corner.y * 0.54)
		shadow.append(k.coded(rough, Vector3.UP, Car.SHADOW, Vector4(corner.x, corner.y, 0.0, 0.0),
			corner * 0.5 + Vector2(0.5, 0.5)))
	for i in range(1, shadow.size() - 1):
		k.triangle(shadow[0], shadow[i], shadow[i + 1], Vector3.UP)
	_car_mesh = k.build()
	_car_mesh.custom_aabb = CAR_BOUNDS
	return _car_mesh


## A subway car (see the header): 62 triangles.
static func train_car() -> ArrayMesh:
	if _train_mesh:
		return _train_mesh
	var b := _Builder.new()
	var half := Trains.B_CAR.x * 0.5
	# The body's sides and roof, along its length.
	for i in _TRAIN_PROFILE.size() - 1:
		var p := _TRAIN_PROFILE[i]
		var q := _TRAIN_PROFILE[i + 1]
		var out := Vector3(q.y - p.y, p.x - q.x, 0.0).normalized()
		var uv := Vector2(_TRAIN_PROFILE_PARTS[i], 0.0)
		b.quad(b.vertex(Vector3(p.x, p.y, -half), out, uv), b.vertex(Vector3(p.x, p.y, half), out, uv),
			b.vertex(Vector3(q.x, q.y, half), out, uv), b.vertex(Vector3(q.x, q.y, -half), out, uv), out)
	# Its ends: fans round the cross-section (closed along the floor).
	for end: float in [-1.0, 1.0]:
		var out := Vector3(0.0, 0.0, end)
		var uv := Vector2(TrainPart.END, 0.0)
		var middle := b.vertex(Vector3(0.0, 2.3, end * half), out, uv)
		var ring := PackedInt32Array()
		for p in _TRAIN_PROFILE:
			ring.append(b.vertex(Vector3(p.x, p.y, end * half), out, uv))
		for i in ring.size():
			b.triangle(middle, ring[i], ring[(i + 1) % ring.size()], out)
	# The floor's underside, the equipment under it and the trucks.
	var under := Vector2(TrainPart.UNDER, 0.0)
	var floor_y := _TRAIN_PROFILE[0].y
	b.quad(b.vertex(Vector3(-1.525, floor_y, -half), Vector3.DOWN, under),
		b.vertex(Vector3(1.525, floor_y, -half), Vector3.DOWN, under),
		b.vertex(Vector3(1.525, floor_y, half), Vector3.DOWN, under),
		b.vertex(Vector3(-1.525, floor_y, half), Vector3.DOWN, under), Vector3.DOWN)
	_train_box(b, _TRAIN_UNDER.position, _TRAIN_UNDER.end, TrainPart.UNDER)
	for end: float in [-1.0, 1.0]:
		var middle := Vector3(0.0, 0.0, end * _TRAIN_TRUCKS * Trains.B_CAR.x)
		var size := _TRAIN_TRUCK_SIZE
		_train_box(b, middle + Vector3(-size.x, 0.1, -size.z), middle + Vector3(size.x, size.y, size.z), TrainPart.TRUCK)
	_train_mesh = b.commit()
	return _train_mesh


## A box's sides and bottom (no top: it's under the car).
static func _train_box(b: _Builder, lo: Vector3, hi: Vector3, part: int) -> void:
	var uv := Vector2(part, 0.0)
	var corners: Array[Vector3] = [Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, 0.0, lo.z), Vector3(hi.x, 0.0, hi.z),
		Vector3(lo.x, 0.0, hi.z)]
	for i in 4:
		var p := corners[i]
		var q := corners[(i + 1) % 4]
		var out := Vector3(q.z - p.z, 0.0, p.x - q.x).normalized()
		b.quad(b.vertex(Vector3(p.x, lo.y, p.z), out, uv), b.vertex(Vector3(q.x, lo.y, q.z), out, uv),
			b.vertex(Vector3(q.x, hi.y, q.z), out, uv), b.vertex(Vector3(p.x, hi.y, p.z), out, uv), out)
	var bottom: Array[int] = []
	for p in corners:
		bottom.append(b.vertex(Vector3(p.x, lo.y, p.z), Vector3.DOWN, uv))
	b.quad(bottom[0], bottom[1], bottom[2], bottom[3], Vector3.DOWN)


## A face round a car's outline (or its cabin's), from point `from` to the
## next, across the car.
static func _car_outline_face(k: _CarKit, from: int, part: int) -> void:
	var d := _CAR_OUTLINE[from + 1] - _CAR_OUTLINE[from]
	var out := Vector3(0.0, d.x, -d.y)
	k.quad(k.outline_point(from, -1.0, part), k.outline_point(from + 1, -1.0, part),
		k.outline_point(from + 1, 1.0, part), k.outline_point(from, 1.0, part), out)


## A car's box (the box truck's, or the taxi's sign): its sides, top, front
## and back (no bottom), as corners 0..1 of a box the shader places; `rough`
## is where it roughly is at unit size.
static func _car_box(k: _CarKit, part: int, rough: AABB) -> void:
	# Each face: a corner, and its two edges (UV2 runs along them).
	for face: Array in [
			[Vector3(1, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
			[Vector3(0, 1, 1), Vector3(1, 0, 0), Vector3(0, 0, -1)]]:
		var corner: Vector3 = face[0]
		var along: Vector3 = face[1]
		var up: Vector3 = face[2]
		var normal := along.cross(up)
		var corners := PackedInt32Array()
		for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			var code := corner + along * uv.x + up * uv.y
			corners.append(k.coded(rough.position + rough.size * code, normal, part, Vector4(code.x, code.y, code.z, 0.0), uv))
		k.quad(corners[0], corners[1], corners[2], corners[3], normal)


## A box's faces ("+x", "-x", "+y", "-y", "+z", "-z") all as `part`, but
## those in `skip` (space-separated).
static func _faces(part: int, skip := "") -> Dictionary:
	var faces := {}
	for face: String in ["+x", "-x", "+y", "-y", "+z", "-z"]:
		if not face in skip.split(" "):
			faces[face] = part
	return faces


## An axis-aligned box from lo to hi with flat faces: `faces` maps the faces
## to draw ("+x" ... "-z") to their parts. UV2 runs 0..1 across each face as
## seen from outside (left to right, bottom to top; top and bottom faces
## along x and z).
static func _box(k: _Kit, lo: Vector3, hi: Vector3, faces: Dictionary) -> void:
	var size := hi - lo
	var sides := {
		"+x": [Vector3(hi.x, lo.y, hi.z), Vector3(0.0, 0.0, -size.z), Vector3(0.0, size.y, 0.0)],
		"-x": [Vector3(lo.x, lo.y, lo.z), Vector3(0.0, 0.0, size.z), Vector3(0.0, size.y, 0.0)],
		"+z": [Vector3(lo.x, lo.y, hi.z), Vector3(size.x, 0.0, 0.0), Vector3(0.0, size.y, 0.0)],
		"-z": [Vector3(hi.x, lo.y, lo.z), Vector3(-size.x, 0.0, 0.0), Vector3(0.0, size.y, 0.0)],
		"+y": [Vector3(lo.x, hi.y, hi.z), Vector3(size.x, 0.0, 0.0), Vector3(0.0, 0.0, -size.z)],
		"-y": [Vector3(lo.x, lo.y, lo.z), Vector3(size.x, 0.0, 0.0), Vector3(0.0, 0.0, size.z)],
	}
	for face: String in faces:
		var side: Array = sides[face]
		_panel(k, side[0], side[1], side[2], faces[face])


## A flat quad from `origin` across `u` and up `v`, facing u x v. UV2 runs
## 0..1 along u and v, CUSTOM1 holds their lengths (unless k.extra is set).
static func _panel(k: _Kit, origin: Vector3, u: Vector3, v: Vector3, part: int) -> void:
	_quad(k, origin, origin + u, origin + u + v, origin + v, part)


## A flat quad through four corners in order (UV2 (0,0), (1,0), (1,1),
## (0,1)), facing (b - a) x (d - a).
static func _quad(k: _Kit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, part: int) -> void:
	var normal := (b - a).cross(d - a).normalized()
	var saved := k.extra
	if k.extra.w <= 0.0:
		k.extra = Vector4((b - a).length(), (d - a).length(), 0.0, 0.0)
	var uv := Vector2(part, 0.0)
	k.quad(k.vertex(a, normal, uv, Vector2(0.0, 0.0)), k.vertex(b, normal, uv, Vector2(1.0, 0.0)),
		k.vertex(c, normal, uv, Vector2(1.0, 1.0)), k.vertex(d, normal, uv, Vector2(0.0, 1.0)), normal)
	k.extra = saved


## A turned shape about the vertical line through `center`, through
## `profile`'s (height, radius) points bottom to top, with smooth normals
## shared between neighboring rings (fewer vertices than _lathe); a radius of
## 0 at either end closes it with a point. With `seam`, the first column is
## doubled so UV2.x runs 0..1 around. `light` is for a light's CUSTOM1 (see
## _globe()).
static func _turned(k: _Kit, sides: int, profile: Array[Vector2], part: int, center := Vector3.ZERO,
		seam := false, light := Vector4.ZERO) -> void:
	var bottom := profile[0].x
	var height := profile[profile.size() - 1].x - bottom
	var around := TAU * profile[0].y
	var rings: Array[PackedInt32Array] = []
	var columns := sides + 1 if seam else sides
	# Squares are turned to line up with the axes.
	var turn := 0.5 if sides == 4 else 0.0
	for p in profile.size():
		var slope := Vector2.ZERO  # (out, up) of the profile's normal here
		if p > 0:
			slope += Vector2(profile[p].x - profile[p - 1].x, profile[p - 1].y - profile[p].y).normalized()
		if p < profile.size() - 1:
			slope += Vector2(profile[p + 1].x - profile[p].x, profile[p].y - profile[p + 1].y).normalized()
		slope = slope.normalized()
		var up := (profile[p].x - bottom) / height
		k.extra = light if light.w > 0.0 else Vector4(around, height, 0.0, 0.0)
		var ring := PackedInt32Array()
		if profile[p].y <= 0.0:
			var pole := Vector3.DOWN if p == 0 else Vector3.UP
			ring.append(k.vertex(center + Vector3.UP * profile[p].x, pole, Vector2(part, 0.0), Vector2(0.5, up)))
		else:
			for i in columns:
				var a := TAU * (i + turn) / sides
				var out := Vector3(cos(a), 0.0, sin(a))
				ring.append(k.vertex(center + out * profile[p].y + Vector3.UP * profile[p].x,
					out * slope.x + Vector3.UP * slope.y, Vector2(part, 0.0), Vector2(float(i) / sides, up)))
		rings.append(ring)
	k.extra = Vector4.ZERO
	for p in rings.size() - 1:
		var low := rings[p]
		var high := rings[p + 1]
		for i in sides:
			var j := i + 1 if seam else (i + 1) % sides
			var a := TAU * (i + 0.5 + turn) / sides
			var out := Vector3(cos(a), 0.0, sin(a)) + Vector3.UP * (0.5 if high.size() == 1 else 0.0) 					+ Vector3.DOWN * (0.5 if low.size() == 1 else 0.0)
			if high.size() == 1:
				k.triangle(low[i], low[j], high[0], out)
			elif low.size() == 1:
				k.triangle(low[0], high[j], high[i], out)
			else:
				k.quad(low[i], low[j], high[j], high[i], out)


## A flat, upward-facing polygon with `sides` corners (a fan).
static func _disc(k: _Kit, center: Vector3, radius: float, sides: int, part: int) -> void:
	k.extra = Vector4(radius * 2.0, radius * 2.0, 0.0, 0.0)
	var rim := PackedInt32Array()
	for i in sides:
		var a := TAU * i / sides
		rim.append(k.vertex(center + Vector3(cos(a), 0.0, sin(a)) * radius, Vector3.UP, Vector2(part, 0.0),
			Vector2(cos(a), sin(a)) * 0.5 + Vector2(0.5, 0.5)))
	k.extra = Vector4.ZERO
	for i in range(1, sides - 1):
		k.triangle(rim[0], rim[i], rim[i + 1], Vector3.UP)


## A thin tube along `points` (lying in the plane facing `across`), as two
## crossed strips: one in the plane, one across it, so it reads as a tube
## from any side (the material is double-sided). 4 triangles a segment.
static func _tube(k: _Kit, points: Array[Vector3], radius: float, across: Vector3, part: int, closed := false) -> void:
	var count := points.size()
	var flat := PackedInt32Array()
	var deep := PackedInt32Array()
	var length := 0.0
	for i in count:
		var before := points[(i - 1 + count) % count] if closed or i > 0 else points[i]
		var after := points[(i + 1) % count] if closed or i < count - 1 else points[i]
		var side := across.cross(after - before).normalized()
		if i > 0:
			length += points[i].distance_to(points[i - 1])
		var uv := Vector2(part, 0.0)
		flat.append(k.vertex(points[i] + side * radius, across, uv, Vector2(0.0, length)))
		flat.append(k.vertex(points[i] - side * radius, across, uv, Vector2(1.0, length)))
		deep.append(k.vertex(points[i] + across * radius, side, uv, Vector2(0.0, length)))
		deep.append(k.vertex(points[i] - across * radius, side, uv, Vector2(1.0, length)))
	for i in (count if closed else count - 1):
		var j := (i + 1) % count
		var side := across.cross(points[j] - points[i]).normalized()
		k.quad(flat[2 * i], flat[2 * j], flat[2 * j + 1], flat[2 * i + 1], across)
		k.quad(deep[2 * i], deep[2 * j], deep[2 * j + 1], deep[2 * i + 1], side)


## A smooth ball (eight sides, three rings: 48 triangles) that the shader
## keeps at least a pixel or two across far away (CUSTOM1: its center and
## radius).
static func _globe(k: _Kit, center: Vector3, radius: float, part: int) -> void:
	var profile: Array[Vector2] = []
	for y: float in [-1.0, -0.7, 0.0, 0.7, 1.0]:
		profile.append(Vector2(center.y + y * radius, sqrt(maxf(1.0 - y * y, 0.0)) * radius))
	_turned(k, 8, profile, part, Vector3(center.x, 0.0, center.z), false, Vector4(center.x, center.y, center.z, radius))


## A turned shape around the y axis through `profile`'s points (height,
## radius), bottom to top, with `sides` flat sides; a radius of 0 closes it to
## a point. UV.y runs 0..1 up it.
static func _lathe(b: _Builder, sides: int, profile: Array[Vector2], part: int) -> void:
	var bottom := profile[0].x
	var height := profile[profile.size() - 1].x - bottom
	for k in profile.size() - 1:
		var p0 := profile[k]
		var p1 := profile[k + 1]
		# Each side leans out by the profile's slope.
		var slope := Vector2(p1.x - p0.x, p0.y - p1.y).normalized()
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			var n := (out * slope.x + Vector3.UP * slope.y).normalized()
			var v0 := b.vertex(Vector3(cos(a0) * p0.y, p0.x, sin(a0) * p0.y), n, Vector2(part, (p0.x - bottom) / height))
			var v1 := b.vertex(Vector3(cos(a1) * p0.y, p0.x, sin(a1) * p0.y), n, Vector2(part, (p0.x - bottom) / height))
			var v2 := b.vertex(Vector3(cos(a1) * p1.y, p1.x, sin(a1) * p1.y), n, Vector2(part, (p1.x - bottom) / height))
			if p1.y <= 0.0:
				b.triangle(v0, v1, v2, n)
			else:
				var v3 := b.vertex(Vector3(cos(a0) * p1.y, p1.x, sin(a0) * p1.y), n, Vector2(part, (p1.x - bottom) / height))
				b.quad(v0, v1, v2, v3, n)


## A small pointed cone (a water tower's finial).
static func _spike(b: _Builder, sides: int, base: Vector3, radius: float, apex_y: float, part: int) -> void:
	var rim := PackedInt32Array()
	for i in sides:
		var a := TAU * i / sides
		var out := Vector3(cos(a), 0.0, sin(a))
		rim.append(b.vertex(base + out * radius, (out + Vector3.UP * 0.5).normalized(), Vector2(part, 0.0)))
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		var n := (Vector3(cos(a), 0.0, sin(a)) + Vector3.UP * 0.5).normalized()
		b.triangle(rim[i], rim[(i + 1) % sides], b.vertex(Vector3(base.x, apex_y, base.z), n, Vector2(part, 1.0)), n)


## A square steel column from `from` to `to`, open at the ends (8 triangles).
static func _beam(b: _Builder, from: Vector3, to: Vector3, half: float, part := PART_STEEL) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	var front := side.cross(axis).normalized()
	var corners: Array[Vector3] = [side + front, -side + front, -side - front, side - front]
	for k in 4:
		var c0 := corners[k] * half
		var c1 := corners[(k + 1) % 4] * half
		var out := (corners[k] + corners[(k + 1) % 4]).normalized()
		var uv0 := Vector2(part, 0.0)
		var uv1 := Vector2(part, 1.0)
		b.quad(b.vertex(from + c0, out, uv0), b.vertex(from + c1, out, uv0), b.vertex(to + c1, out, uv1), b.vertex(to + c0, out, uv1), out)


## A flat strip (a brace) from `from` to `to`, facing `out` (2 triangles;
## the material is double-sided).
static func _strut(b: _Builder, from: Vector3, to: Vector3, out: Vector3, half: float) -> void:
	var across := (to - from).cross(out).normalized() * half
	var uv := Vector2(PART_STEEL, 0.5)
	b.quad(b.vertex(from - across, out, uv), b.vertex(from + across, out, uv), b.vertex(to + across, out, uv), b.vertex(to - across, out, uv), out)


## A tree trunk: an open five-sided prism from the ground up into the crown.
static func _trunk(b: _Builder, top: float) -> void:
	const SIDES := 5
	var radius := TRUNK_RADIUS
	var ring_bottom := PackedInt32Array()
	var ring_top := PackedInt32Array()
	for i in SIDES:
		var a := TAU * i / SIDES
		var out := Vector3(cos(a), 0.0, sin(a))
		# Flares a little at the foot.
		ring_bottom.append(b.vertex(out * radius * 1.25, out, Vector2(PART_TRUNK, 0.0)))
		ring_top.append(b.vertex(out * radius * 0.8 + Vector3.UP * top, out, Vector2(PART_TRUNK, 1.0)))
	for i in SIDES:
		var n := (i + 1) % SIDES
		var out := Vector3(cos(TAU * (i + 0.5) / SIDES), 0.0, sin(TAU * (i + 0.5) / SIDES))
		b.quad(ring_bottom[i], ring_bottom[n], ring_top[n], ring_top[i], out)


## Collects vertices and triangles, then makes an ArrayMesh.
class _Builder:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	func vertex(position: Vector3, normal: Vector3, uv: Vector2, uv2 := Vector2.ZERO) -> int:
		positions.append(position)
		normals.append(normal.normalized())
		uvs.append(uv)
		uv2s.append(uv2)
		return positions.size() - 1

	## A triangle whose front faces `outward`. Godot draws clockwise triangles
	## as front-facing, so a counter-clockwise one (as seen from outside) is
	## flipped.
	func triangle(a: int, b: int, c: int, outward: Vector3) -> void:
		var normal := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		if normal.dot(outward) > 0.0:
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])

	## Two triangles over the corners a, b, c, d in order around the quad.
	func quad(a: int, b: int, c: int, d: int, outward: Vector3) -> void:
		triangle(a, b, c, outward)
		triangle(a, c, d, outward)

	## The mesh. Each of `shapes` (built from the same vertices in the same
	## order; their triangles are ignored) goes in two custom arrays, CUSTOM0
	## and CUSTOM1 for the first, CUSTOM2 and CUSTOM3 for the second:
	## (position, UV.y) and (normal, UV2.x). Vertex colors are white, so a
	## MultiMesh's instance colors reach the shader as they are (without a
	## color array, the Compatibility renderer leaves whatever was last set).
	func commit(shapes: Array[_Builder] = []) -> ArrayMesh:
		var arrays := base_arrays()
		const SHIFTS: Array[int] = [Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT,
				Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT]
		var flags := 0
		for k in shapes.size():
			var shape := shapes[k]
			assert(shape.positions.size() == positions.size(), "A mesh's other shapes need the same vertices.")
			var places := PackedFloat32Array()
			var shading := PackedFloat32Array()
			for i in positions.size():
				var p := shape.positions[i]
				var n := shape.normals[i]
				places.append_array([p.x, p.y, p.z, shape.uvs[i].y])
				shading.append_array([n.x, n.y, n.z, shape.uv2s[i].x])
			arrays[Mesh.ARRAY_CUSTOM0 + 2 * k] = places
			arrays[Mesh.ARRAY_CUSTOM1 + 2 * k] = shading
			flags |= (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << SHIFTS[2 * k]) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << SHIFTS[2 * k + 1])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		return mesh

	## The mesh arrays of the vertices and triangles so far, with white
	## vertex colors (see commit()).
	func base_arrays() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		var white := PackedColorArray()
		white.resize(positions.size())
		white.fill(Color.WHITE)
		arrays[Mesh.ARRAY_COLOR] = white
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays


## Collects street furniture's shapes: a _Builder whose vertices also carry
## the shape they belong to (CUSTOM0) and their face's size or light's center
## (CUSTOM1), as the header describes.
class _Kit extends _Builder:
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	## The shape being built: (type, variant bits, height, width).
	var shape := Vector4.ZERO
	## What the next vertices carry in CUSTOM1.
	var extra := Vector4.ZERO

	func vertex(position: Vector3, normal: Vector3, uv: Vector2, uv2 := Vector2.ZERO) -> int:
		custom0.append_array([shape.x, shape.y, shape.z, shape.w])
		custom1.append_array([extra.x, extra.y, extra.z, extra.w])
		return super(position, normal, uv, uv2)

	func build() -> ArrayMesh:
		var arrays := base_arrays()
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		arrays[Mesh.ARRAY_CUSTOM1] = custom1
		var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		return mesh


## Collects a car's vertices: a _Builder whose vertices also carry which
## point of a car they are (CUSTOM0), as the header describes.
class _CarKit extends _Builder:
	var codes := PackedFloat32Array()

	## A vertex at `rough` (the rough unit-size sedan) with its code.
	func coded(rough: Vector3, normal: Vector3, part: int, code: Vector4, uv2 := Vector2.ZERO) -> int:
		codes.append_array([code.x, code.y, code.z, code.w])
		return vertex(rough, normal, Vector2(part, 0.0), uv2)

	## A point of the outline (see the header) on a side (-1 or 1).
	func outline_point(id: int, side: float, part: int) -> int:
		var p: Vector2 = PropMeshes._CAR_OUTLINE[id]
		var rough := Vector3(side * PropMeshes._CAR_HALF_WIDTH, p.y, p.x)
		return coded(rough, Vector3(side, 0.0, 0.0), part, Vector4(id, 0.0, side, 0.0))

	func build() -> ArrayMesh:
		var arrays := base_arrays()
		arrays[Mesh.ARRAY_CUSTOM0] = codes
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return mesh


## A tree crown being built from blobs between heights `bottom` and `top`.
## Blobs are icosahedra with a corner at each pole: the top corner, a ring of
## five above the middle, a ring of five below (turned half a step), and the
## bottom corner.
class _Crown:
	var bottom: float
	var top: float
	var builder: _Builder
	var center: Vector3
	var radii: Vector3

	func _init(bottom_y: float, top_y: float, b: _Builder) -> void:
		bottom = bottom_y
		top = top_y
		builder = b
		# The ellipsoid around the whole crown, whose normals the blobs lean toward.
		center = Vector3(0.0, (bottom + top) * 0.5, 0.0)
		radii = Vector3(0.5, (top - bottom) * 0.5, 0.5)

	## The 12 corners of a unit icosahedron with a corner at each pole.
	static func corners() -> Array[Vector3]:
		var out: Array[Vector3] = [Vector3.UP]
		var ring_y := 1.0 / sqrt(5.0)
		var ring_r := 2.0 / sqrt(5.0)
		for k in 5:
			out.append(Vector3(cos(TAU * k / 5.0) * ring_r, ring_y, sin(TAU * k / 5.0) * ring_r))
		for k in 5:
			out.append(Vector3(cos(TAU * (k + 0.5) / 5.0) * ring_r, -ring_y, sin(TAU * (k + 0.5) / 5.0) * ring_r))
		out.append(Vector3.DOWN)
		return out

	## An icosahedron blob at `blob_center` with `blob_radii`, turned by an
	## angle from `shade` (which also shades it a little lighter or darker);
	## `number` goes in UV2.y.
	func blob(blob_center: Vector3, blob_radii: Vector3, shade: float, number: int) -> void:
		var turn := Basis(Vector3(0.3, 1.0, 0.2).normalized(), 1.3 + shade * 2.0)
		var first := builder.positions.size()
		for corner in corners():
			var dir := turn * corner
			var p := blob_center + dir * blob_radii
			var own := dir / blob_radii
			var whole := (p - center) / (radii * radii)
			var n := own.normalized().lerp(whole.normalized(), PropMeshes.CROWN_NORMAL_BLEND)
			builder.vertex(p, n, Vector2(PropMeshes.PART_CROWN, _up(p.y)), Vector2(shade, number))
		# Faces: the top cap, the band between the rings, the bottom cap.
		for k in 5:
			var u0 := first + 1 + k
			var u1 := first + 1 + (k + 1) % 5
			var l0 := first + 6 + k
			var l1 := first + 6 + (k + 1) % 5
			for face in [[first, u0, u1], [u0, l0, u1], [l0, l1, u1], [first + 11, l1, l0]]:
				var mid: Vector3 = (builder.positions[face[0]] + builder.positions[face[1]] + builder.positions[face[2]]) / 3.0
				builder.triangle(face[0], face[1], face[2], mid - blob_center)

	## The same 12 corners as a conifer's tier: the top corner at the apex, the
	## upper ring part way up the cone, the lower ring around its base, the
	## bottom corner in the middle of its shallow underside. Adds no triangles
	## (it's a second shape for a blob's).
	func cone(base_y: float, radius: float, apex_y: float, shade: float, number: int) -> void:
		var slope := Vector2(apex_y - base_y, radius).normalized()
		var places: Array[Vector3] = [Vector3(0.0, apex_y, 0.0)]
		var faces: Array[Vector3] = [Vector3.UP]
		for k in 5:
			var out := Vector3(cos(TAU * k / 5.0), 0.0, sin(TAU * k / 5.0))
			places.append(out * radius * 0.55 + Vector3.UP * lerpf(base_y, apex_y, 0.45))
			faces.append(Vector3(out.x * slope.x, slope.y, out.z * slope.x))
		for k in 5:
			var out := Vector3(cos(TAU * (k + 0.5) / 5.0), 0.0, sin(TAU * (k + 0.5) / 5.0))
			places.append(out * radius + Vector3.UP * base_y)
			# The rim is shared by the cone and the underside: halfway between.
			faces.append((out + Vector3.UP * 0.2).normalized())
		places.append(Vector3(0.0, base_y + 0.05, 0.0))
		faces.append(Vector3.DOWN)
		for i in places.size():
			builder.vertex(places[i], faces[i], Vector2(PropMeshes.PART_CROWN, _up(places[i].y)), Vector2(shade, number))

	func _up(y: float) -> float:
		return clampf((y - bottom) / (top - bottom), 0.0, 1.0)
