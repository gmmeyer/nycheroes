class_name StreetLightMap
extends SubViewport
## Street lights' pools of light on the ground around the camera, drawn from
## above into a texture (PIXELS square, METERS_PER_PIXEL each) that the city's
## shaders look up at night (shaders/night.gdshaderinc, street_light_at()):
## the ground, paint, the feet of walls, tree crowns and lamp posts near a
## lamp pick up its light. Real lights would be far too many for the
## Compatibility renderer, and it has no decals; this costs one texture lookup
## per pixel, and no draw calls in the main view.
##
## Each near tile adds its lamps (and lit bus shelters and newsstands) as a
## MultiMeshInstance2D of soft additive discs (CityProps,
## shaders/street_light_pool.gdshader), at its world position in meters; the
## canvas transform maps meters to pixels. The map
## only redraws when tiles come or go or it moves to follow the camera (in
## STEP-meter steps), and not at all while the lights are off: nothing
## happens per frame. The shader globals street_light_map (this viewport's
## texture) and street_light_rect (the square it covers, in scene x/z) tell
## the shaders where it is.

const PIXELS := 1024
const METERS_PER_PIXEL := 2.0
## The map moves in steps of this many meters to stay centered on the camera.
const STEP := 256.0

## Whether the city's lights are on: the map only draws then.
var on := false: set = set_on

var _pool_material: Material
var _pool_mesh: Mesh
## World x/z of the map's center, and where it was when it last drew.
var _center := Vector2(INF, INF)
var _drawn_center := Vector2(INF, INF)
var _dirty := true


func _init(pool_material: Material) -> void:
	_pool_material = pool_material
	_pool_mesh = PropMeshes.light_pool()
	name = "StreetLightMap"
	size = Vector2i(PIXELS, PIXELS)
	disable_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED


func _ready() -> void:
	RenderingServer.global_shader_parameter_set("street_light_map", get_texture())
	RenderingServer.global_shader_parameter_set("street_light_rect", Vector4.ZERO)
	WorldOrigin.shifted.connect(func(_delta: Vector3) -> void: _publish_rect())


func set_on(value: bool) -> void:
	on = value
	if on and _center.is_finite():
		_redraw()


## Adds a tile's pools: a 2D MultiMesh buffer of `count` lamps
## (CityProps.POOL_COPIES), tile-local. They go when the tile does.
func add_pools(tile: Node3D, buffer: PackedFloat32Array, count: int) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = _pool_mesh
	multimesh.instance_count = count
	multimesh.buffer = buffer
	var pools := MultiMeshInstance2D.new()
	pools.name = tile.name
	pools.multimesh = multimesh
	pools.material = _pool_material
	# Tiles sit at their world position under the city (which floats).
	pools.position = Vector2(tile.position.x, tile.position.z)
	add_child(pools)
	tile.tree_exiting.connect(_remove.bind(pools), CONNECT_ONE_SHOT)
	_dirty = true


## Keeps the map around the camera's world position; call it a few times a
## second. Redraws if it moved or its tiles changed (while the lights are on).
func follow(focus: Vector3) -> void:
	var at := Vector2(focus.x, focus.z)
	if not _center.is_finite() or at.distance_to(_center) > STEP:
		_center = at.snapped(Vector2(STEP, STEP))
		var scale := 1.0 / METERS_PER_PIXEL
		canvas_transform = Transform2D(0.0, Vector2(scale, scale), 0.0, Vector2(PIXELS, PIXELS) * 0.5 - _center * scale)
		_dirty = true
	if _dirty and on:
		_redraw()


func _remove(pools: Node) -> void:
	pools.queue_free()
	_dirty = true


func _redraw() -> void:
	_dirty = false
	_drawn_center = _center
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_publish_rect()


## Tells the shaders where the map is, in scene coordinates (the world shifted
## by WorldOrigin).
func _publish_rect() -> void:
	if not _drawn_center.is_finite():
		return
	var span := PIXELS * METERS_PER_PIXEL
	var corner := _drawn_center - Vector2(span, span) * 0.5 - Vector2(WorldOrigin.offset.x, WorldOrigin.offset.z)
	RenderingServer.global_shader_parameter_set("street_light_rect", Vector4(corner.x, corner.y, span, span))
