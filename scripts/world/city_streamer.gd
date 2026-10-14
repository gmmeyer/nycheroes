class_name CityStreamer
extends Node3D
## Streams the city around the camera from a three-level tile tree, built by
## tools/citygen/build_tiles.py into data/tiles/<region>/:
##   lod0: 500 m tiles, full detail, with collision and walking lanes
##   lod1: 1 km tiles, simplified
##   lod2: 4 km tiles, coarse, out to the horizon
## A level's tiles load when their parent tile is near the camera. A tile is
## drawn until all its children have loaded; then the children are drawn
## instead, so there's never doubled-up or missing geometry. Collision comes
## from lod0 tiles whether or not they're drawn.
## Web builds fetch tiles over HTTP from tiles/<region>/ next to index.html
## (tools/build_web.ps1 copies them there).

signal initial_load_finished(seconds: float)

const LEVEL_NEAR := 0
const LEVEL_COUNT := 3
const UPDATE_INTERVAL := 0.25
const MAX_ATTEMPTS := 3
## Physics layer 1, "world".
const COLLISION_LAYER := 1
## Physics layer 5, "water": raised lakes' surfaces, which nothing collides
## with but heroes look for to know where the water is.
const WATER_LAYER := 16
## Added to the camera distance when ordering downloads, so nearby detail
## arrives first and coarse tiles follow.
const LEVEL_PRIORITY: Array[float] = [0.0, 400.0, 1500.0]

@export var region := "nyc"
## Tiles of each level load once their parent tile is within this distance of
## the camera (the top level, which has no parent, within its own distance).
@export var load_distances: Array[float] = [700.0, 1500.0, 30000.0]
## Loaded tiles are kept until this far past their distance, so they don't flicker.
@export var unload_margin := 300.0
## Near tiles (with collision and walking lanes) also load within this
## distance of each extra focus.
@export var extra_focus_radius := 350.0
@export var max_requests := 6
## Time per frame spent turning downloaded tiles into meshes.
@export var build_budget_msec := 6.0
@export var building_material: Material
@export var ground_material: Material
@export var water_material: Material

var loaded_counts: Array[int] = [0, 0, 0]
## World positions that need the ground loaded around them besides the
## camera's: other players' heroes on the host, so thugs near them have
## streets to stand on.
var extra_foci: Array[Vector3] = []
## Time the last tile took to turn into meshes and collision, in milliseconds.
var last_build_msec := 0.0

var _levels: Array[Dictionary] = []  # {name, size, tiles: Array[Tile], by_coord: {Vector2i: Tile}}
var _queue: Array[Array] = []  # [priority, tile], sorted
var _ready_to_build: Array[Array] = []  # [tile, bytes]
var _in_flight := 0
var _base_url := ""  # web only
var _idle_requests: Array[HTTPRequest] = []
var _update_cooldown := 0.0
var _start_msec := 0
var _initial_load_done := false


class Tile:
	var level: int
	var i: int
	var j: int
	var size: float
	var info: Dictionary
	var node: Node3D
	var pending := false
	var failures := 0
	var parent: Tile
	var children: Array[Tile] = []
	## Sidewalk walking lanes (world-space polylines), lod0 only, while loaded.
	var lanes: Array[PackedVector3Array] = []

	func distance_to(x: float, z: float) -> float:
		var dx := maxf(maxf(i * size - x, 0.0), x - (i + 1) * size)
		var dz := maxf(maxf(j * size - z, 0.0), z - (j + 1) * size)
		return sqrt(dx * dx + dz * dz)


func _ready() -> void:
	add_to_group("floating")
	_start_msec = Time.get_ticks_msec()
	if OS.has_feature("web"):
		var page_dir := str(JavaScriptBridge.eval("location.href.split(/[?#]/)[0].replace(/[^/]*$/, '')"))
		_base_url = page_dir + "tiles/%s/" % region
		for n in max_requests:
			var request := HTTPRequest.new()
			add_child(request)
			_idle_requests.append(request)
	_load_file("manifest.json", _on_manifest_loaded)


func _process(delta: float) -> void:
	if _levels.is_empty():
		return
	_update_cooldown -= delta
	if _update_cooldown <= 0.0:
		_update_cooldown = UPDATE_INTERVAL
		_update_wanted_tiles()
		_refresh_visibility()
	while _in_flight < max_requests and not _queue.is_empty():
		_request_tile(_queue.pop_front()[1])
	_build_ready_tiles()


func pending_count() -> int:
	return _in_flight + _queue.size() + _ready_to_build.size()


## True once the ground at this world position can be stood on: its lod0 tile
## has loaded with collision, or there's no tile there at all (open water).
func has_collision_at(world_position: Vector3) -> bool:
	if _levels.is_empty():
		return false
	var tile := _tile_at(LEVEL_NEAR, world_position)
	return tile == null or tile.node != null


## Sidewalk lanes (world-space polylines) of loaded tiles within `radius` of a
## world position.
func lanes_near(world_position: Vector3, radius: float) -> Array[PackedVector3Array]:
	var found: Array[PackedVector3Array] = []
	if _levels.is_empty():
		return found
	for tile: Tile in _levels[LEVEL_NEAR]["tiles"]:
		if not tile.lanes.is_empty() and tile.distance_to(world_position.x, world_position.z) < radius:
			found.append_array(tile.lanes)
	return found


## Height of the first surface (ground, roof or bridge) straight down from
## `search_from` meters above a world position (from the sky by default), or
## NAN if nothing there has loaded with collision yet.
func ground_height_at(world_position: Vector3, search_from := INF) -> float:
	var start_y := minf(world_position.y + search_from, WorldOrigin.CEILING + 50.0)
	var top := WorldOrigin.to_local(Vector3(world_position.x, start_y, world_position.z))
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (start_y + 100.0), COLLISION_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else NAN


func _tile_at(level: int, world_position: Vector3) -> Tile:
	var size: float = _levels[level]["size"]
	var coord := Vector2i(floori(world_position.x / size), floori(world_position.z / size))
	return _levels[level]["by_coord"].get(coord)


func _on_manifest_loaded(bytes: PackedByteArray) -> void:
	var manifest = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(manifest) != TYPE_DICTIONARY or not manifest.has("levels"):
		push_error("City manifest for '%s' is missing or out of date. Run tools/citygen/build_tiles.py." % region)
		return
	for level in manifest.levels.size():
		var data: Dictionary = manifest.levels[level]
		var size := float(data.tile_size)
		var tiles: Array[Tile] = []
		var by_coord := {}
		for tile_info: Dictionary in data.tiles:
			var tile := Tile.new()
			tile.level = level
			tile.i = int(tile_info.i)
			tile.j = int(tile_info.j)
			tile.size = size
			tile.info = tile_info
			tiles.append(tile)
			by_coord[Vector2i(tile.i, tile.j)] = tile
		_levels.append({"name": data.name, "size": size, "tiles": tiles, "by_coord": by_coord})
	# Link each tile to the tile one level up that contains it.
	for level in range(_levels.size() - 1):
		var ratio := int(round(_levels[level + 1]["size"] / _levels[level]["size"]))
		for tile: Tile in _levels[level]["tiles"]:
			var parent: Tile = _levels[level + 1]["by_coord"].get(Vector2i(floori(float(tile.i) / ratio), floori(float(tile.j) / ratio)))
			if parent:
				tile.parent = parent
				parent.children.append(tile)


func _update_wanted_tiles() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var focus := WorldOrigin.to_world(camera.global_position)
	# Height counts too, so flying high doesn't load street-level detail.
	var height := maxf(focus.y, 0.0)
	_queue.clear()
	for level in _levels.size():
		var limit: float = load_distances[mini(level, load_distances.size() - 1)]
		for tile: Tile in _levels[level]["tiles"]:
			# A tile is wanted when its parent is near (or itself, at the top level).
			var anchor: Tile = tile.parent if tile.parent else tile
			var distance := Vector2(anchor.distance_to(focus.x, focus.z), height).length()
			var extra := _extra_focus_distance(tile) if level == LEVEL_NEAR else INF
			if tile.node == null:
				if (distance < limit or extra < extra_focus_radius) and not tile.pending and tile.failures < MAX_ATTEMPTS:
					_queue.append([minf(tile.distance_to(focus.x, focus.z), extra) + LEVEL_PRIORITY[level], tile])
			elif distance > limit + unload_margin and extra > extra_focus_radius + unload_margin:
				_unload(tile)
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _extra_focus_distance(tile: Tile) -> float:
	var nearest := INF
	for focus in extra_foci:
		nearest = minf(nearest, tile.distance_to(focus.x, focus.z))
	return nearest


func _refresh_visibility() -> void:
	for tile: Tile in _levels[_levels.size() - 1]["tiles"]:
		_show(tile)
	# Tiles whose parent level has no tile there have nobody to show them.
	for level in range(_levels.size() - 1):
		for tile: Tile in _levels[level]["tiles"]:
			if tile.parent == null:
				_show(tile)


## Draws a tile, or its children instead once they're all ready.
func _show(tile: Tile) -> void:
	var use_children := _children_ready(tile)
	if tile.node:
		tile.node.visible = not use_children
	for child in tile.children:
		if use_children:
			_show(child)
		else:
			_hide(child)


func _hide(tile: Tile) -> void:
	if tile.node:
		tile.node.visible = false
	for child in tile.children:
		_hide(child)


func _children_ready(tile: Tile) -> bool:
	if tile.children.is_empty():
		return false
	for child in tile.children:
		if child.node == null and not _children_ready(child):
			return false
	return true


func _request_tile(tile: Tile) -> void:
	tile.pending = true
	_in_flight += 1
	_load_file("%s/%d_%d.nyct" % [_levels[tile.level]["name"], tile.i, tile.j], _on_tile_loaded.bind(tile))


func _on_tile_loaded(bytes: PackedByteArray, tile: Tile) -> void:
	_in_flight -= 1
	_ready_to_build.append([tile, bytes])


func _build_ready_tiles() -> void:
	var deadline := Time.get_ticks_usec() + int(build_budget_msec * 1000.0)
	var changed := false
	while not _ready_to_build.is_empty() and Time.get_ticks_usec() < deadline:
		var item: Array = _ready_to_build.pop_front()
		var tile: Tile = item[0]
		var bytes: PackedByteArray = item[1]
		tile.pending = false
		if bytes.is_empty():
			# The next update requests it again; give up after a few tries.
			tile.failures += 1
			if tile.failures >= MAX_ATTEMPTS:
				push_error("Giving up on tile %s %d_%d" % [_levels[tile.level]["name"], tile.i, tile.j])
			continue
		var build_start := Time.get_ticks_usec()
		var node := _build_tile_node(tile, bytes)
		last_build_msec = (Time.get_ticks_usec() - build_start) / 1000.0
		node.visible = false  # _refresh_visibility decides
		add_child(node)
		tile.node = node
		loaded_counts[tile.level] += 1
		changed = true
	if changed:
		_refresh_visibility()

	if not _initial_load_done and pending_count() == 0 and loaded_counts.any(func(n: int) -> bool: return n > 0):
		_initial_load_done = true
		var seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
		print("[city] %s ready in %.1f s: %d near, %d mid, %d far tiles" % [
			region, seconds, loaded_counts[0], loaded_counts[1], loaded_counts[2]])
		initial_load_finished.emit(seconds)


func _build_tile_node(tile: Tile, bytes: PackedByteArray) -> Node3D:
	var near := tile.level == LEVEL_NEAR
	var node := Node3D.new()
	node.name = "%s_%d_%d" % [_levels[tile.level]["name"], tile.i, tile.j]
	node.position = Vector3(tile.i * tile.size, 0.0, tile.j * tile.size)
	var body: StaticBody3D = null
	if near:
		body = StaticBody3D.new()
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = 0
		node.add_child(body)
	for surface in CityTileDecoder.decode(bytes, int(tile.info.raw_bytes)):
		if surface.kind == CityTileDecoder.SURFACE_LANES:
			tile.lanes.clear()
			for lane: PackedVector3Array in surface.lanes:
				for p in lane.size():
					lane[p] += node.position
				tile.lanes.append(lane)
			continue
		if surface.kind == CityTileDecoder.SURFACE_WATER:
			node.add_child(_water_node(surface.mesh, near))
			continue
		var is_buildings: bool = surface.kind == CityTileDecoder.SURFACE_BUILDINGS
		var instance := MeshInstance3D.new()
		instance.mesh = surface.mesh
		instance.material_override = building_material if is_buildings else ground_material
		var casts_shadow: bool = near and surface.kind != CityTileDecoder.SURFACE_GROUND
		if not casts_shadow:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
		if body:
			var shape := CollisionShape3D.new()
			shape.shape = surface.mesh.create_trimesh_shape()
			body.add_child(shape)
	return node


## A raised lake's surface, which heroes can find (but not stand on) up close.
func _water_node(mesh: ArrayMesh, near: bool) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = water_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if near:
		var body := StaticBody3D.new()
		body.collision_layer = WATER_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		instance.add_child(body)
	return instance


func _unload(tile: Tile) -> void:
	tile.node.queue_free()
	tile.node = null
	tile.lanes.clear()
	loaded_counts[tile.level] -= 1


## Loads a file from the tile directory and calls on_loaded(bytes) when done;
## bytes is empty on failure.
func _load_file(file: String, on_loaded: Callable) -> void:
	if _base_url.is_empty():
		on_loaded.call_deferred(FileAccess.get_file_as_bytes(_local_dir() + file))
		return
	var request: HTTPRequest = _idle_requests.pop_back()
	var callback := _on_request_completed.bind(request, file, on_loaded)
	request.request_completed.connect(callback, CONNECT_ONE_SHOT)
	if request.request(_base_url + file) != OK:
		request.request_completed.disconnect(callback)
		_idle_requests.append(request)
		push_warning("Couldn't request %s" % file)
		on_loaded.call_deferred(PackedByteArray())


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest, file: String, on_loaded: Callable) -> void:
	_idle_requests.append(request)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Failed to load %s (result %d, HTTP %d)" % [file, result, code])
		body = PackedByteArray()
	on_loaded.call(body)


func _local_dir() -> String:
	if OS.has_feature("editor"):
		return "res://data/tiles/%s/" % region
	return OS.get_executable_path().get_base_dir().path_join("tiles/%s/" % region)
