class_name CityProps
extends RefCounted
## Trees, rooftop water towers and street lights of a near city tile (its
## props surface, see CityTileDecoder), drawn with the low-poly meshes from
## PropMeshes: one MultiMeshInstance3D for every kind of tree (they share a
## mesh with three shapes), one that casts the trees' shadows, one for water
## towers, and one for street lights (both styles share a mesh). Draw calls
## are what props cost most on the web (measured), hence so few.
##
## At night street lights add a MultiMesh of glows around their heads (shown
## only while the city's lights are on: set lights_on), and their pools of
## light go to the street light map (StreetLightMap) as a 2D MultiMesh, which
## the ground, paint, walls and trees look up; the main view draws no extra
## geometry for them.
##
## Each instance's transform scales the unit mesh to the prop's size (x and z
## by its width, y by its height) and moves it to its base point; its color
## is (trunk diameter m, 0, 0, 0) and INSTANCE_CUSTOM (yaw radians, variant,
## seed 0..1, type). The shaders turn the mesh to its yaw (rotating there
## keeps the transform free of sines and cosines). A street light's "width"
## is its arm's length (0 for post-tops), so its shader places its vertices
## itself.
##
## Tiles are built under a few milliseconds a frame on the web, where a
## GDScript loop writing thousands of props would take too long, so the
## instance buffer is assembled by native code: the decoded columns are
## wrapped as one-channel float images and copied into place column by column
## with Image.blit_rect. The tiles have the props sorted by type, so each
## MultiMesh's share is one slice of it.

## The MultiMeshes: their node names, and the first and last prop type
## (CityTileDecoder.PROP_*) each holds.
const GROUP_NAMES: Array[String] = ["Trees", "WaterTowers", "StreetLights"]
const GROUP_TYPES: Array[Vector2i] = [Vector2i(0, 2), Vector2i(3, 3), Vector2i(4, 4)]
const WATER_TOWERS := 1
const STREET_LIGHTS := 2
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
## Wind sway, seed variety and the distance shrink move vertices a little
## outside the unit mesh's box (meters).
const CULL_MARGIN := 1.5
## Street lights' arms reach out of the box their transforms give (it doesn't
## know their yaw), and post-tops' boxes have no width at all; their glows
## grow with distance.
const STREET_LIGHT_CULL_MARGIN := 4.0
const GLOW_CULL_MARGIN := 8.0

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
## Water towers, few and big, draw a little further than trees.
var water_tower_range := 1600.0
## Street lights shrink away before 650 m (street_light.gdshader); their glows
## go on to 1500 m (street_light_glow.gdshader).
var street_light_range := 1050.0
var glow_range := 1900.0
## Whether new tiles' glows show (the city's lights are on).
var lights_on := false
## Where street lights' pools go (null: nowhere).
var light_map: StreetLightMap

var _meshes: Array[Mesh] = []
var _shadow_meshes: Array[Mesh] = []
var _materials: Array[Material] = []
var _glow_mesh: Mesh
var _glow_material: Material


func _init(tree_material: Material, water_tower_material: Material, street_light_material: Material,
		street_light_glow_material: Material) -> void:
	_meshes = [PropMeshes.tree(), PropMeshes.water_tower(), PropMeshes.street_light()]
	# Water towers cast their own shadows; street lights cast none (too thin
	# to show in the shadow map, and they'd cost a draw call per split).
	_shadow_meshes = [PropMeshes.tree_shadow(), null, null]
	_materials = [tree_material, water_tower_material, street_light_material]
	_glow_mesh = PropMeshes.street_light_glow()
	_glow_material = street_light_glow_material


## Adds a tile's props (a decoded props surface) under its node. Returns how
## many there were.
func add_to(parent: Node3D, props: Dictionary) -> int:
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
		# Types are whole numbers, sorted.
		var start := types.bsearch(GROUP_TYPES[group].x - 0.5)
		var end := types.bsearch(GROUP_TYPES[group].y + 0.5)
		if end <= start:
			continue
		var share := buffer.slice(start * STRIDE, end * STRIDE)
		var instance := _instance(group, share, _meshes[group])
		parent.add_child(instance)
		if group == STREET_LIGHTS:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add_street_light_extras(parent, share, sources, start, end)
		elif _shadow_meshes[group]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if tree_shadows:
				var shadows := _instance(group, share, _shadow_meshes[group])
				shadows.name += "Shadows"
				shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				shadows.visibility_range_end = tree_shadow_range
				parent.add_child(shadows)
	return count


## Street lights' glows (under the tile's node) and pools (in the light map).
func _add_street_light_extras(parent: Node3D, share: PackedFloat32Array, sources: Array[Image], start: int, end: int) -> void:
	var glows := _instance(STREET_LIGHTS, share, _glow_mesh)
	glows.name = GLOW_NAME
	glows.material_override = _glow_material
	glows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glows.extra_cull_margin = GLOW_CULL_MARGIN
	glows.visibility_range_end = glow_range
	glows.visible = lights_on
	glows.add_to_group(GLOW_GROUP)
	parent.add_child(glows)
	if light_map == null:
		return
	var count := end - start
	var lamps: Array[Image] = []
	for source in sources:
		lamps.append(source.get_region(Rect2i(0, start, source.get_width(), count)))
	var ones := Image.create_empty(1, count, false, Image.FORMAT_RF)
	ones.fill(Color(1.0, 0.0, 0.0))
	lamps.append(ones)
	light_map.add_pools(parent, _buffer(lamps, count, POOL_COPIES, POOL_STRIDE), count)


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
		_:
			instance.extra_cull_margin = CULL_MARGIN
			instance.visibility_range_end = tree_range
	return instance
