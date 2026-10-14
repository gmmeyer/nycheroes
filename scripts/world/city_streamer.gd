class_name CityStreamer
extends Node3D
## Streams city tiles around the camera.
##
## Each tile has a full-detail version (lod0) loaded near the camera and a
## simplified one (lod1) loaded out to the horizon; lod1 is hidden while lod0
## is present. Tiles are built by tools/citygen/build_tiles.py into
## data/tiles/<region>/. Web builds fetch them over HTTP from tiles/<region>/
## next to index.html (tools/build_web.ps1 copies them there).

signal initial_load_finished(seconds: float)

const LOD_NEAR := 0
const LOD_FAR := 1
const LOD_NAMES: Array[String] = ["lod0", "lod1"]
const UPDATE_INTERVAL := 0.25
const MAX_ATTEMPTS := 3

@export var region := "manhattan"
@export var near_radius := 1200.0
@export var far_radius := 30000.0
## Loaded tiles are kept until this far past their radius, so they don't flicker at the edge.
@export var unload_margin := 250.0
@export var max_requests := 6
## Time per frame spent turning downloaded tiles into meshes.
@export var build_budget_msec := 6.0
@export var building_material: Material
@export var ground_material: Material

var tile_size := 500.0
var loaded_counts: Array[int] = [0, 0]

var _tiles: Array[Tile] = []
var _queue: Array[Array] = []  # [priority, tile, lod], sorted
var _ready_to_build: Array[Array] = []  # [tile, lod, bytes]
var _in_flight := 0
var _base_url := ""  # web only
var _idle_requests: Array[HTTPRequest] = []
var _update_cooldown := 0.0
var _start_msec := 0
var _initial_load_done := false


class Tile:
	var i: int
	var j: int
	var info: Dictionary
	var nodes: Array[Node3D] = [null, null]
	var pending: Array[bool] = [false, false]
	var failures: Array[int] = [0, 0]

	func _init(entry: Dictionary) -> void:
		i = int(entry.i)
		j = int(entry.j)
		info = entry


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
	if _tiles.is_empty():
		return
	_update_cooldown -= delta
	if _update_cooldown <= 0.0:
		_update_cooldown = UPDATE_INTERVAL
		_update_wanted_tiles()
	while _in_flight < max_requests and not _queue.is_empty():
		_request_tile(_queue.pop_front())
	_build_ready_tiles()


func pending_count() -> int:
	return _in_flight + _queue.size() + _ready_to_build.size()


func _on_manifest_loaded(bytes: PackedByteArray) -> void:
	var manifest = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(manifest) != TYPE_DICTIONARY:
		push_error("City manifest for '%s' is missing or invalid. Run tools/citygen/build_tiles.py." % region)
		return
	tile_size = manifest.tile_size
	for entry in manifest.tiles:
		_tiles.append(Tile.new(entry))


func _update_wanted_tiles() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var focus := WorldOrigin.to_world(camera.global_position)
	_queue.clear()
	for tile in _tiles:
		var distance := _distance_to_tile(tile, focus.x, focus.z)
		for lod in LOD_NAMES.size():
			if not tile.info.has(LOD_NAMES[lod]):
				continue
			var radius := near_radius if lod == LOD_NEAR else far_radius
			if tile.nodes[lod] == null:
				if distance < radius and not tile.pending[lod]:
					# Nearby detail first, then the horizon.
					var priority := distance if lod == LOD_NEAR else near_radius + distance
					_queue.append([priority, tile, lod])
			elif distance > radius + unload_margin:
				_unload(tile, lod)
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _distance_to_tile(tile: Tile, x: float, z: float) -> float:
	var min_x := tile.i * tile_size
	var min_z := tile.j * tile_size
	var dx := maxf(maxf(min_x - x, 0.0), x - (min_x + tile_size))
	var dz := maxf(maxf(min_z - z, 0.0), z - (min_z + tile_size))
	return sqrt(dx * dx + dz * dz)


func _request_tile(item: Array) -> void:
	var tile: Tile = item[1]
	var lod: int = item[2]
	tile.pending[lod] = true
	_in_flight += 1
	_load_file("%s/%d_%d.nyct" % [LOD_NAMES[lod], tile.i, tile.j], _on_tile_loaded.bind(tile, lod))


func _on_tile_loaded(bytes: PackedByteArray, tile: Tile, lod: int) -> void:
	_in_flight -= 1
	_ready_to_build.append([tile, lod, bytes])


func _build_ready_tiles() -> void:
	var deadline := Time.get_ticks_usec() + int(build_budget_msec * 1000.0)
	while not _ready_to_build.is_empty() and Time.get_ticks_usec() < deadline:
		var item: Array = _ready_to_build.pop_front()
		var tile: Tile = item[0]
		var lod: int = item[1]
		var bytes: PackedByteArray = item[2]
		tile.pending[lod] = false
		if bytes.is_empty():
			# The next update requests it again; give up after a few tries.
			tile.failures[lod] += 1
			if tile.failures[lod] >= MAX_ATTEMPTS:
				push_error("Giving up on tile %s %d_%d" % [LOD_NAMES[lod], tile.i, tile.j])
				tile.info.erase(LOD_NAMES[lod])
			continue
		var node := _build_tile_node(tile, lod, bytes)
		add_child(node)
		tile.nodes[lod] = node
		loaded_counts[lod] += 1
		_refresh_visibility(tile)

	if not _initial_load_done and pending_count() == 0 and loaded_counts[LOD_NEAR] + loaded_counts[LOD_FAR] > 0:
		_initial_load_done = true
		var seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
		print("[city] %s ready in %.1f s: %d near tiles, %d far tiles" % [
			region, seconds, loaded_counts[LOD_NEAR], loaded_counts[LOD_FAR]])
		initial_load_finished.emit(seconds)


func _build_tile_node(tile: Tile, lod: int, bytes: PackedByteArray) -> Node3D:
	var node := Node3D.new()
	node.name = "%s_%d_%d" % [LOD_NAMES[lod], tile.i, tile.j]
	node.position = Vector3(tile.i * tile_size, 0.0, tile.j * tile_size)
	for surface in CityTileDecoder.decode(bytes, int(tile.info[LOD_NAMES[lod]].raw_bytes)):
		var is_buildings: bool = surface.kind == CityTileDecoder.SURFACE_BUILDINGS
		var instance := MeshInstance3D.new()
		instance.mesh = surface.mesh
		instance.material_override = building_material if is_buildings else ground_material
		if not (is_buildings and lod == LOD_NEAR):
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
	return node


func _unload(tile: Tile, lod: int) -> void:
	tile.nodes[lod].queue_free()
	tile.nodes[lod] = null
	loaded_counts[lod] -= 1
	_refresh_visibility(tile)


func _refresh_visibility(tile: Tile) -> void:
	if tile.nodes[LOD_FAR] != null:
		tile.nodes[LOD_FAR].visible = tile.nodes[LOD_NEAR] == null


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
