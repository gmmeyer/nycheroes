class_name CityProps
extends RefCounted
## Trees, rooftop water towers, street lights and street furniture of a near
## city tile (its props surface, see CityTileDecoder), drawn with the low-poly
## meshes from PropMeshes: one MultiMeshInstance3D for every kind of tree
## (they share a mesh with three shapes), one that casts the trees' shadows,
## one for water towers, one for street lights (both styles share a mesh),
## two for street furniture: small pieces (hydrants, benches, litter baskets,
## bike racks, parking meters) and large ones (bus shelters, LinkNYC kiosks,
## subway entrances, traffic signals, newsstands), each mesh holding all its
## pieces' shapes, one for parked cars (every model on one mesh, which
## traffic's cars share), one for shop fronts' signs and awnings (their own
## shader, shaders/shop_sign.gdshader, with the names texture), and two more
## with shaders/street_extras.gdshader: sidewalk sheds (many, so on a small
## mesh of their own), and the bike share's docks with plaza furniture. Draw
## calls are what props cost most on the web (measured), hence so few. Woods
## seen from afar are clumps of crowns, in tiles of every level (mid and far
## tiles have nothing else): one more MultiMesh, drawn by the trees' shader,
## which grows them in where the trees shrink away.
##
## At night street lights add a MultiMesh of glows around their heads (shown
## only while the city's lights are on: set lights_on), and their pools of
## light go to the street light map (StreetLightMap) as a 2D MultiMesh, with
## the light of lit bus shelters and newsstands; the ground, paint, walls,
## trees and furniture look it up, and the main view draws no extra geometry
## for it.
##
## Each instance's transform scales the unit mesh to the prop's size (x and z
## by its width, y by its height) and moves it to its base point; its color
## is (trunk diameter m, 0, 0, 0) and INSTANCE_CUSTOM (yaw radians, variant,
## seed 0..1, type). The shaders turn the mesh to its yaw (rotating there
## keeps the transform free of sines and cosines). A street light's "width"
## is its arm's length (0 for post-tops), so its shader places its vertices
## itself, and so does the furniture's (its meshes are in meters). A parked
## car's "width" is its length, and its color (paint, 0, 0, 0): the layout
## shaders/car.gdshader expects (traffic's cars add light flags and their
## wheels' roll). A traffic signal's "trunk" is its phase offset
## (TrafficSignals).
##
## Tiles are built under a few milliseconds a frame on the web, where a
## GDScript loop writing thousands of props would take too long, so the
## instance buffer is assembled by native code: the decoded columns are
## wrapped as one-channel float images and copied into place column by column
## with Image.blit_rect. The tiles have the props sorted by type, so each
## MultiMesh's share is a slice of it per range of types.

## The MultiMeshes: their node names, and the prop types
## (CityTileDecoder.PROP_*) each holds, as ranges (first, last).
const GROUP_NAMES: Array[String] = ["Trees", "WaterTowers", "StreetLights", "SmallFurniture", "LargeFurniture",
	"ParkedCars", "Canopy", "ShopFronts", "SidewalkSheds", "StreetExtras"]
const GROUP_TYPES: Array[Array] = [
	[Vector2i(0, 2)], [Vector2i(3, 3)], [Vector2i(4, 4)],
	# Hydrants; benches; litter baskets, bike racks and parking meters.
	[Vector2i(5, 5), Vector2i(8, 8), Vector2i(11, 13)],
	# Bus shelters and LinkNYC; subway entrances and traffic signals; newsstands.
	[Vector2i(6, 7), Vector2i(9, 10), Vector2i(14, 14)],
	[Vector2i(15, 15)],
	[Vector2i(16, 16)],
	# Shop signs and awnings; sidewalk sheds; bike docks, plaza tables, planters and kiosks.
	[Vector2i(17, 18)], [Vector2i(19, 19)], [Vector2i(20, 23)],
]
const WATER_TOWERS := 1
const STREET_LIGHTS := 2
const SMALL_FURNITURE := 3
const LARGE_FURNITURE := 4
const PARKED_CARS := 5
const CANOPY := 6
const SHOP_FRONTS := 7
const SIDEWALK_SHEDS := 8
const STREET_EXTRAS := 9
## Street lights' glows: their node name, and the group they're all in.
const GLOW_NAME := "StreetLightGlow"
const GLOW_GROUP := &"street_light_glow"
## Floats per instance in the buffer: a 3x4 transform, a color, custom data.
const STRIDE := 20
## Where the decoded columns go in an instance's 20 floats:
## [source, source column, buffer column]. Sources: 0 positions (x, y, z),
## 1 normals (height, width, yaw), 2 uv (variant, trunk), 3 uv2 (type, seed).
## The transform's rows are (width, 0, 0, x), (0, height, 0, y),
## (0, 0, width, z); the color is (trunk, 0, 0, 0); custom is (yaw, variant,
## seed, type).
const COPIES: Array[Vector3i] = [
	Vector3i(0, 0, 3), Vector3i(0, 1, 7), Vector3i(0, 2, 11),
	Vector3i(1, 1, 0), Vector3i(1, 0, 5), Vector3i(1, 1, 10),
	Vector3i(2, 1, 12),
	Vector3i(1, 2, 16), Vector3i(2, 0, 17), Vector3i(3, 1, 18), Vector3i(3, 0, 19),
]
## Street lights' pools in the light map: a 2D MultiMesh's 12 floats per
## instance, a 2x4 transform and custom data. Sources as above, plus 4: ones.
## The transform's rows are (1, 0, 0, x), (0, 1, 0, z) (meters, tile-local);
## custom is (yaw, arm length, pole height, style).
const POOL_STRIDE := 12
const POOL_COPIES: Array[Vector3i] = [
	Vector3i(4, 0, 0), Vector3i(0, 0, 3), Vector3i(4, 0, 5), Vector3i(0, 2, 7),
	Vector3i(1, 2, 8), Vector3i(1, 1, 9), Vector3i(1, 0, 10), Vector3i(2, 0, 11),
]
## Lit furniture's light in the same map: custom is (yaw, 0, height, prop
## type), so shaders/street_light_pool.gdshader tells it from lamps.
const LIT_FURNITURE_POOL_COPIES: Array[Vector3i] = [
	Vector3i(4, 0, 0), Vector3i(0, 0, 3), Vector3i(4, 0, 5), Vector3i(0, 2, 7),
	Vector3i(1, 2, 8), Vector3i(1, 0, 10), Vector3i(3, 0, 11),
]
## Furniture lit at night that lights the sidewalk around it (prop types):
## bus shelters, newsstands and the lamps under sidewalk sheds.
const LIT_FURNITURE: Array[int] = [CityTileDecoder.PROP_BUS_SHELTER, CityTileDecoder.PROP_NEWSSTAND,
	CityTileDecoder.PROP_SIDEWALK_SHED]
## Wind sway, seed variety and the distance shrink move vertices a little
## outside the unit mesh's box (meters).
const CULL_MARGIN := 1.5
## Street lights' arms reach out of the box their transforms give (it doesn't
## know their yaw), and post-tops' boxes have no width at all; their glows
## grow with distance.
const STREET_LIGHT_CULL_MARGIN := 4.0
const GLOW_CULL_MARGIN := 8.0
## Furniture's boxes don't know its yaw or its meshes' real sizes either: a
## signal's arm reaches 4.6 m from its pole.
const FURNITURE_CULL_MARGIN := 5.0
## Shop signs' boxes don't know their yaw either, and the widest are 12 m.
const SHOP_CULL_MARGIN := 6.5
## Cars' boxes are their length wide either way (PropMeshes.CAR_BOUNDS), so
## they hold them however they're turned; a little more for good measure.
const CAR_CULL_MARGIN := 0.5
## A tile's furniture (and parked cars) draws until its tile's center is this
## much further from the camera than where its pieces have shrunk away (half a
## 500 m tile's diagonal, and a little).
const FURNITURE_RANGE_PAST_FADE := 370.0
## Shop signs and awnings, and sidewalk sheds, shrink away at these shares of
## the large furniture's distances: a sign is a few pixels tall by then, and
## every instance a tile draws runs all its mesh's vertices, shrunk or not
## (at the large furniture's distances they cost about 0.5 ms a frame on the
## dev machine in Queens and Manhattan views).
const SHOP_FADE_SHARE := 0.62
const SHED_FADE_SHARE := 0.78

## Trees stop drawing once their tile's center is this far from the camera
## (m). The tree shader shrinks each tree away before that (its
## fade_distance), so this only needs to be past that plus half a tile's
## diagonal.
var tree_range := 1250.0
## Trees' shadows come from a second MultiMesh with plain stand-in meshes,
## drawn only into the shadow map and only this far (tile center to camera,
## m). The tree shader shrinks each tree's shadow away before that (its
## shadow_distance), so no tile's shadows pop. Off, trees cast none.
var tree_shadow_range := 1000.0
var tree_shadows := true
## Woods' clumps of crowns draw until their tile's center is this far from
## the camera (m), by the tile's level (CityStreamer.LEVEL_*; 0: not at all;
## set_canopy_ranges() changes them). Near tiles' start drawing once their
## center is canopy_range_begin away: the tree shader grows each clump in
## from 600 m (its canopy_distance), and a 500 m tile's corners are 354 m
## from its center.
var canopy_ranges: Array[float] = [6000.0, 6000.0, 9000.0]
var canopy_range_begin := 240.0
## Water towers, few and big, draw a little further than trees.
var water_tower_range := 1600.0
## Street lights shrink away before 650 m (street_light.gdshader); their glows
## go on to 1500 m (street_light_glow.gdshader).
var street_light_range := 1050.0
var glow_range := 1900.0
## Street furniture shrinks away piece by piece between these distances from
## the camera (m; set_furniture_fade() changes them): small pieces (hydrants,
## benches, baskets, bike racks, meters), which are a pixel or two by then,
## and large ones. Each tile's furniture stops drawing past them.
var small_furniture_fade := Vector2(180.0, 260.0)
var large_furniture_fade := Vector2(420.0, 580.0)
## Parked cars shrink away between these distances (m; set_car_fade()), and
## so does traffic, which shares their material.
var car_fade := Vector2(320.0, 460.0)
## Whether new tiles' glows show (the city's lights are on).
var lights_on := false
## Where street lights' pools go (null: nowhere).
var light_map: StreetLightMap
## Shop signs' and awnings' material (shaders/shop_sign.gdshader), and
## sidewalk sheds', bike docks' and plaza furniture's
## (shaders/street_extras.gdshader).
var shop_material: ShaderMaterial
var extras_material: ShaderMaterial

var _meshes: Array[Mesh] = []
var _shadow_meshes: Array[Mesh] = []
var _materials: Array[Material] = []
var _glow_mesh: Mesh
var _glow_material: Material


func _init(tree_material: Material, water_tower_material: Material, street_light_material: Material,
		street_light_glow_material: Material, street_furniture_material: Material, car_material: Material) -> void:
	_meshes = [PropMeshes.tree(), PropMeshes.water_tower(), PropMeshes.street_light(),
		PropMeshes.street_furniture_small(), PropMeshes.street_furniture_large(), PropMeshes.car(),
		PropMeshes.canopy(), PropMeshes.shop_fronts(), PropMeshes.sidewalk_shed(), PropMeshes.street_furniture_extra()]
	# Water towers cast their own shadows; street lights, furniture and cars
	# cast none (thin, or small next to the buildings' shadows, and each would
	# cost a draw call per shadow split: large furniture's shadows measured
	# 3-11% of the frame rate in midtown for little to see; cars draw a
	# contact shadow of their own).
	_shadow_meshes = [PropMeshes.tree_shadow(), null, null, null, null, null, null, null, null, null]
	# Shop fronts', sheds', docks' and plaza furniture's materials are the
	# props' own (the first needs only the names texture).
	shop_material = ShaderMaterial.new()
	shop_material.shader = preload("res://shaders/shop_sign.gdshader")
	shop_material.set_shader_parameter("sign_names", preload("res://assets/signs/sign_names.png"))
	extras_material = ShaderMaterial.new()
	extras_material.shader = preload("res://shaders/street_extras.gdshader")
	_materials = [tree_material, water_tower_material, street_light_material, street_furniture_material,
		street_furniture_material, car_material, tree_material, shop_material, extras_material, extras_material]
	_glow_mesh = PropMeshes.street_light_glow()
	_glow_material = street_light_glow_material
	# Fade distances already set on the material (?sh_small_fade_distance=...,
	# see LightingOverrides) win over the defaults.
	var material := street_furniture_material as ShaderMaterial
	if material:
		var small: Variant = material.get_shader_parameter("small_fade_distance")
		var large: Variant = material.get_shader_parameter("large_fade_distance")
		small_furniture_fade = small if small is Vector2 else small_furniture_fade
		large_furniture_fade = large if large is Vector2 else large_furniture_fade
	set_furniture_fade(small_furniture_fade, large_furniture_fade)
	var cars := car_material as ShaderMaterial
	if cars:
		var fade: Variant = cars.get_shader_parameter("fade_distance")
		car_fade = fade if fade is Vector2 else car_fade
	set_car_fade(car_fade)


## Sets where street furniture shrinks away (see small_furniture_fade), in
## its shader too. Tiles built from then on draw it to match.
func set_furniture_fade(small: Vector2, large: Vector2) -> void:
	small_furniture_fade = small
	large_furniture_fade = large
	var material := _materials[SMALL_FURNITURE] as ShaderMaterial
	if material:
		material.set_shader_parameter("small_fade_distance", small)
		material.set_shader_parameter("large_fade_distance", large)
	# Shop fronts and sheds go a little before the large pieces; docks and
	# plaza furniture with the small ones, kiosks with the large.
	shop_material.set_shader_parameter("fade_distance", large * SHOP_FADE_SHARE)
	extras_material.set_shader_parameter("small_fade_distance", small)
	extras_material.set_shader_parameter("large_fade_distance", large)
	extras_material.set_shader_parameter("shed_fade_distance", large * SHED_FADE_SHARE)


## Sets where cars shrink away (see car_fade), in their shader too, parked
## and moving alike. Tiles built from then on draw parked cars to match.
func set_car_fade(fade: Vector2) -> void:
	car_fade = fade
	var material := _materials[PARKED_CARS] as ShaderMaterial
	if material:
		material.set_shader_parameter("fade_distance", fade)


## Sets how far woods' clumps of crowns draw, by tile level (see
## canopy_ranges). Takes effect for tiles built from then on, so set it
## before the city loads (Quality does).
func set_canopy_ranges(ranges: Array[float]) -> void:
	canopy_ranges = ranges


## Adds a tile's props (a decoded props surface) under its node; `level` is
## the tile's (CityStreamer.LEVEL_*). Returns how many it draws.
func add_to(parent: Node3D, props: Dictionary, level := 0) -> int:
	var count: int = props.positions.size()
	if count == 0:
		return 0
	var sources: Array[Image] = [
		Image.create_from_data(3, count, false, Image.FORMAT_RF, props.positions.to_byte_array()),
		Image.create_from_data(3, count, false, Image.FORMAT_RF, props.normals.to_byte_array()),
		Image.create_from_data(2, count, false, Image.FORMAT_RF, props.uv.to_byte_array()),
		Image.create_from_data(2, count, false, Image.FORMAT_RF, props.uv2.to_byte_array()),
	]
	var buffer := _buffer(sources, count, COPIES, STRIDE)
	var types := sources[3].get_region(Rect2i(0, 0, 1, count)).get_data().to_float32_array()
	for group in GROUP_NAMES.size():
		# Types are whole numbers, sorted: a slice per range.
		var share := PackedFloat32Array()
		for types_range: Vector2i in GROUP_TYPES[group]:
			var start := types.bsearch(types_range.x - 0.5)
			var end := types.bsearch(types_range.y + 0.5)
			if end > start:
				share.append_array(buffer.slice(start * STRIDE, end * STRIDE))
		if share.is_empty():
			continue
		if group == CANOPY and canopy_ranges[level] <= 0.0:
			count -= share.size() / STRIDE
			continue
		var instance := _instance(group, share, _meshes[group])
		parent.add_child(instance)
		if group == CANOPY:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = canopy_ranges[level]
			if level == 0:
				instance.visibility_range_begin = canopy_range_begin
		elif group == STREET_LIGHTS:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add_glows(parent, share)
		elif group >= SMALL_FURNITURE:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _shadow_meshes[group]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if tree_shadows:
				var shadows := _instance(group, share, _shadow_meshes[group])
				shadows.name += "Shadows"
				shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				shadows.visibility_range_end = tree_shadow_range
				parent.add_child(shadows)
	if light_map:
		_add_pools(parent, sources, types)
	return count


## Street lights' glows, under the tile's node.
func _add_glows(parent: Node3D, share: PackedFloat32Array) -> void:
	var glows := _instance(STREET_LIGHTS, share, _glow_mesh)
	glows.name = GLOW_NAME
	glows.material_override = _glow_material
	glows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glows.extra_cull_margin = GLOW_CULL_MARGIN
	glows.visibility_range_end = glow_range
	glows.visible = lights_on
	glows.add_to_group(GLOW_GROUP)
	parent.add_child(glows)


## The street lights' pools and lit furniture's light, as one 2D MultiMesh
## in the light map (if the tile has any).
func _add_pools(parent: Node3D, sources: Array[Image], types: PackedFloat32Array) -> void:
	var buffer := PackedFloat32Array()
	var count := 0
	for kind: int in [CityTileDecoder.PROP_STREET_LIGHT] + LIT_FURNITURE:
		var start := types.bsearch(kind - 0.5)
		var end := types.bsearch(kind + 0.5)
		if end <= start:
			continue
		var slice: Array[Image] = []
		for source in sources:
			slice.append(source.get_region(Rect2i(0, start, source.get_width(), end - start)))
		var ones := Image.create_empty(1, end - start, false, Image.FORMAT_RF)
		ones.fill(Color(1.0, 0.0, 0.0))
		slice.append(ones)
		var copies := POOL_COPIES if kind == CityTileDecoder.PROP_STREET_LIGHT else LIT_FURNITURE_POOL_COPIES
		buffer.append_array(_buffer(slice, end - start, copies, POOL_STRIDE))
		count += end - start
	if count > 0:
		light_map.add_pools(parent, buffer, count)


## The instance buffer of all `count` props, in the tile's order: `stride`
## floats each, laid out by `copies` (see COPIES).
func _buffer(sources: Array[Image], count: int, copies: Array[Vector3i], stride: int) -> PackedFloat32Array:
	var buffer := Image.create_empty(stride, count, false, Image.FORMAT_RF)
	for copy in copies:
		buffer.blit_rect(sources[copy.x], Rect2i(copy.y, 0, 1, count), Vector2i(copy.z, 0))
	return buffer.get_data().to_float32_array()


func _instance(group: int, buffer: PackedFloat32Array, mesh: Mesh) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = buffer.size() / STRIDE
	multimesh.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.name = GROUP_NAMES[group]
	instance.multimesh = multimesh
	instance.material_override = _materials[group]
	match group:
		WATER_TOWERS:
			instance.extra_cull_margin = CULL_MARGIN
			instance.visibility_range_end = water_tower_range
		STREET_LIGHTS:
			instance.extra_cull_margin = STREET_LIGHT_CULL_MARGIN
			instance.visibility_range_end = street_light_range
		SMALL_FURNITURE:
			instance.extra_cull_margin = FURNITURE_CULL_MARGIN
			instance.visibility_range_end = small_furniture_fade.y + FURNITURE_RANGE_PAST_FADE
		LARGE_FURNITURE, STREET_EXTRAS:
			instance.extra_cull_margin = FURNITURE_CULL_MARGIN
			instance.visibility_range_end = large_furniture_fade.y + FURNITURE_RANGE_PAST_FADE
		SIDEWALK_SHEDS:
			instance.extra_cull_margin = FURNITURE_CULL_MARGIN
			instance.visibility_range_end = large_furniture_fade.y * SHED_FADE_SHARE + FURNITURE_RANGE_PAST_FADE
		SHOP_FRONTS:
			instance.extra_cull_margin = SHOP_CULL_MARGIN
			instance.visibility_range_end = large_furniture_fade.y * SHOP_FADE_SHARE + FURNITURE_RANGE_PAST_FADE
		PARKED_CARS:
			instance.extra_cull_margin = CAR_CULL_MARGIN
			instance.visibility_range_end = car_fade.y + FURNITURE_RANGE_PAST_FADE
		_:
			instance.extra_cull_margin = CULL_MARGIN
			instance.visibility_range_end = tree_range
	return instance
