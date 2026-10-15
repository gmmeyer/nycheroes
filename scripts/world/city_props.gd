class_name CityProps
extends RefCounted
## Trees and rooftop water towers of a near city tile (its props surface, see
## CityTileDecoder), drawn with the low-poly meshes from PropMeshes: one
## MultiMeshInstance3D for every kind of tree (they share a mesh with three
## shapes), one that casts the trees' shadows, and one for water towers.
## Draw calls are what props cost most on the web (measured), hence so few.
##
## Each instance's transform scales the unit mesh to the prop's size (x and z
## by its width, y by its height) and moves it to its base point; its color
## is (trunk diameter m, 0, 0, 0) and INSTANCE_CUSTOM (yaw radians, variant,
## seed 0..1, type). The shaders turn the mesh to its yaw (rotating there
## keeps the transform free of sines and cosines).
##
## Tiles are built under a few milliseconds a frame on the web, where a
## GDScript loop writing thousands of props would take too long, so the
## instance buffer is assembled by native code: the decoded columns are
## wrapped as one-channel float images and copied into place column by column
## with Image.blit_rect. The tiles have the props sorted by type, so each
## MultiMesh's share is one slice of it.

## The MultiMeshes: their node names, and the first and last prop type
## (CityTileDecoder.PROP_*) each holds.
const GROUP_NAMES: Array[String] = ["Trees", "WaterTowers"]
const GROUP_TYPES: Array[Vector2i] = [Vector2i(0, 2), Vector2i(3, 3)]
const WATER_TOWERS := 1
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
## Wind sway, seed variety and the distance shrink move vertices a little
## outside the unit mesh's box (meters).
const CULL_MARGIN := 1.5

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

var _meshes: Array[Mesh] = []
var _shadow_meshes: Array[Mesh] = []
var _materials: Array[Material] = []


func _init(tree_material: Material, water_tower_material: Material) -> void:
	_meshes = [PropMeshes.tree(), PropMeshes.water_tower()]
	# Water towers cast their own shadows.
	_shadow_meshes = [PropMeshes.tree_shadow(), null]
	_materials = [tree_material, water_tower_material]


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
	var buffer := _buffer(sources, count)
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
		if _shadow_meshes[group]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if tree_shadows:
				var shadows := _instance(group, share, _shadow_meshes[group])
				shadows.name += "Shadows"
				shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				shadows.visibility_range_end = tree_shadow_range
				parent.add_child(shadows)
	return count


## The instance buffer of all `count` props, in the tile's order.
func _buffer(sources: Array[Image], count: int) -> PackedFloat32Array:
	var buffer := Image.create_empty(STRIDE, count, false, Image.FORMAT_RF)
	for copy in COPIES:
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
	instance.extra_cull_margin = CULL_MARGIN
	instance.visibility_range_end = water_tower_range if group == WATER_TOWERS else tree_range
	return instance
