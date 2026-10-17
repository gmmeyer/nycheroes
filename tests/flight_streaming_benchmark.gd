extends Node
## Real NYC tiles, 4.5 km of uninterrupted 187.5 m/s flight at 60 ticks/s.
## Checks coverage while tiles are still arriving, not only after settling.
## Reports CPU time inside streaming; headless timings are NOT rendered FPS.
## godot --headless --max-fps 60 --path . res://tests/flight_streaming_benchmark.tscn -- --tiles=DIR --solo=1
## Add --quality=low to exercise Low's shorter tile and detail ranges.
## For a baseline, --streamer_script=res://tests/streaming_legacy_temp.gd
## can select an unmodified CityStreamer script exported from git HEAD.

const STEP := 1.0 / 60.0
const FLIGHT_FRAMES := 1440
const SPEED := 187.5
const DIRECTION := Vector3(0.485, 0.0, -0.875)

var _city: Node3D
var _camera: Camera3D
var _warm_frames := 0
var _settled := 0
var _flight_frames := 0
var _flying := false
var _problems := 0
var _checks := 0
var _busy_frames := 0
var _max_backlog := 0
var _partial_frames := 0
var _stream_times: Array[float] = []
var _build_times: Array[float] = []
var _update_times: Array[float] = []
var _offset_before := Vector3.ZERO


func _ready() -> void:
	var script_path := LaunchOptions.get_string("streamer_script", "res://scripts/world/city_streamer.gd")
	var instrumented := GDScript.new()
	instrumented.source_code = "extends \"%s\"\nvar measured_build := 0.0\nvar measured_update := 0.0\nfunc _build_ready_tiles() -> void:\n\tvar start := Time.get_ticks_usec()\n\tsuper._build_ready_tiles()\n\tmeasured_build = (Time.get_ticks_usec() - start) / 1000.0\nfunc _update_wanted_tiles() -> void:\n\tvar start := Time.get_ticks_usec()\n\tsuper._update_wanted_tiles()\n\tmeasured_update = (Time.get_ticks_usec() - start) / 1000.0\n" % script_path
	if script_path == "res://scripts/world/city_streamer.gd":
		instrumented.source_code += "var surface_costs := {}\nfunc _add_tile_surface(tile: Tile, node: Node3D, surface: Dictionary) -> void:\n\tvar start := Time.get_ticks_usec()\n\tsuper._add_tile_surface(tile, node, surface)\n\tvar cost := (Time.get_ticks_usec() - start) / 1000.0\n\tvar key := str(surface.kind)\n\tsurface_costs[key] = maxf(surface_costs.get(key, 0.0), cost)\n"
	if instrumented.reload() != OK:
		get_tree().quit(1)
		return
	_city = instrumented.new()
	_city.name = "MeasuredCity"
	# Use the real scene's materials, but keep gameplay/AI out of CPU timings.
	var template: Node = load("res://scenes/world.tscn").instantiate()
	var source: Node3D = template.get_node("City")
	for property: Dictionary in source.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
			_city.set(property.name, source.get(property.name))
	template.free()
	var low := LaunchOptions.get_string("quality") == "low"
	if low:
		_city.load_distances.assign(Quality.PRESETS[Quality.Level.LOW].load_distances)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 120.0, 0.0)
	_camera.add_to_group("floating")
	add_child(_camera)
	_camera.current = true
	WorldOrigin.focus = _camera
	add_child(_city)
	if low:
		var preset: Dictionary = Quality.PRESETS[Quality.Level.LOW]
		_city.set_tree_shadows(false)
		_city.set_furniture_fade(preset.furniture_fade[0], preset.furniture_fade[1])
		_city.set_car_fade(preset.car_fade)
		_city.fronts_range = preset.fronts_range
		var canopy: Array[float] = []
		canopy.assign(preset.canopy_ranges)
		_city.set_canopy_ranges(canopy)
	_city.set_process(false)
	print("[flight benchmark] source=%s, fixed step=%.5f, speed=%.1f" % [script_path, STEP, SPEED])


func _process(_delta: float) -> void:
	if _flying:
		_camera.position += DIRECTION.normalized() * SPEED * STEP
	_city.measured_update = 0.0
	var start := Time.get_ticks_usec()
	_city._process(STEP)
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	if not _flying:
		_warm_frames += 1
		_settled = _settled + 1 if _city.pending_count() == 0 and _warm_frames > 60 else 0
		if _settled >= 30:
			_flying = true
			_offset_before = WorldOrigin.offset
			print("[flight benchmark] warm in %d frames; loaded %s" % [_warm_frames, _city.loaded_counts])
		elif _warm_frames > 3600:
			push_error("City failed to settle before the flight test")
			get_tree().quit(1)
		return
	_flight_frames += 1
	_stream_times.append(elapsed)
	_build_times.append(_city.measured_build)
	if _city.measured_update > 0.0:
		_update_times.append(_city.measured_update)
	if _city.pending_count() > 0:
		_busy_frames += 1
	_check_coverage()
	_check_incomplete_build()
	if _flight_frames >= FLIGHT_FRAMES:
		_finish()


func _check_coverage() -> void:
	var doubled := 0
	for level: Dictionary in _city._levels:
		for tile in level.tiles:
			if tile.node == null or not tile.node.visible:
				continue
			var ancestor = tile.parent
			while ancestor:
				if ancestor.node and ancestor.node.visible:
					doubled += 1
				ancestor = ancestor.parent
	var holes := 0
	var focus := WorldOrigin.to_world(_camera.global_position)
	if not _city.has_collision_at(focus):
		if _problems < 5:
			push_error("Ground collision missing under the flight path at %s" % focus)
		_problems += 1
	for k in 16:
		var direction := Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0))
		for radius: float in [50.0, 400.0, 1500.0]:
			if not _drawn_at(focus + direction * radius):
				holes += 1
	_checks += 1
	if doubled or holes:
		if _problems < 5:
			push_error("Flight frame %d: %d holes, %d overlapping ancestors at %s" % [_flight_frames, holes, doubled, focus])
		_problems += 1


func _drawn_at(point: Vector3) -> bool:
	var deepest = null
	for level in _city._levels.size():
		var tile = _city._tile_at(level, point)
		if tile == null:
			continue
		if deepest == null:
			deepest = tile
		if tile.node and tile.node.visible:
			return true
	return deepest == null or _city._children_ready(deepest)


func _check_incomplete_build() -> void:
	var pending := 0
	for level: Dictionary in _city._levels:
		for tile in level.tiles:
			pending += int(tile.pending)
	_max_backlog = maxi(_max_backlog, pending)
	if not _city.has_method("_build_backlog"):
		return
	if pending > CityStreamer.MAX_BUILD_BACKLOG:
		_problems += 1
		push_error("More than the bounded number of geometry tiles are in flight")
	if _city._building_tile != null:
		_partial_frames += 1
		var tile = _city._building_tile
		if tile.node != null or not tile.pending or _city._building_node.visible:
			_problems += 1
			push_error("A partially built tile was published")


func _stats(values: Array[float]) -> String:
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	return "mean %.3f ms; p50 %.3f; p95 %.3f; p99 %.3f; max %.3f" % [
		total / values.size(), values[values.size() / 2], values[floori(values.size() * 0.95)],
		values[floori(values.size() * 0.99)], values[-1]]


func _finish() -> void:
	if _busy_frames == 0 or WorldOrigin.offset == _offset_before:
		_problems += 1
		push_error("Route did not exercise both active streaming and origin shifts")
	print("[flight benchmark] streaming CPU: %s" % _stats(_stream_times))
	print("[flight benchmark] building CPU:  %s" % _stats(_build_times))
	print("[flight benchmark] wanted CPU:    %s" % _stats(_update_times))
	if _city.get("surface_costs") != null:
		print("[flight benchmark] worst surface CPU ms (kind: time): %s" % _city.get("surface_costs"))
	print("[flight benchmark] %d frames, %d loading, %d partial; max geometry backlog %d; %d coverage checks, %d problems; offset %s" % [
		_flight_frames, _busy_frames, _partial_frames, _max_backlog, _checks, _problems, WorldOrigin.offset])
	# Also clean up baseline scripts that predate explicit cycle release.
	for level: Dictionary in _city._levels:
		for tile in level.tiles:
			tile.parent = null
			tile.children.clear()
	get_tree().quit(1 if _problems else 0)
