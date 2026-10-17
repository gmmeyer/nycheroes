extends Node
## Deterministic checks of flight limits and incomplete tile handovers.
## godot --headless --path . res://tests/flight_streaming_regression.tscn -- --solo=1

class TestHero extends Hero:
	func _ready() -> void:
		set_physics_process(false)

class TestCity extends CityStreamer:
	func _ready() -> void:
		set_process(false)
		_initial_load_done = true

	func _add_tile_surface(tile: Tile, node: Node3D, surface: Dictionary) -> void:
		super._add_tile_surface(tile, node, surface)
		# Force a frame boundary even on a fast machine.
		var until := Time.get_ticks_usec() + 200
		while Time.get_ticks_usec() < until:
			pass

var _problems := 0
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	_test_flight()
	_test_visibility()
	_test_partial_build()
	_test_partial_cleanup()
	_test_prediction()
	_test_prefetch_requests()
	print("flight/streaming regression: %d checks, %d problems" % [_checks, _problems])
	get_tree().quit(1 if _problems else 0)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_problems += 1
		push_error(message)


func _advance(mode: FlightMode, seconds: float, hz := 60) -> void:
	for tick in roundi(seconds * hz):
		mode.physics_update(1.0 / hz)
		_check(mode.hero.velocity.length() <= 187.501, "Flight exceeded the 187.5 m/s cap")


func _test_flight() -> void:
	var hero := TestHero.new()
	add_child(hero)
	var mode := FlightMode.new()
	hero.add_child(mode)
	mode.hero = hero
	mode.enter(&"OnFoot")
	hero.input.stick = Vector2(0.0, -1.0)
	_advance(mode, 2.0)
	_check(is_equal_approx(hero.velocity.length(), 33.0), "Cruise should reach 33 m/s")
	hero.input.sprint_held = true
	_advance(mode, 2.0)
	var early := hero.velocity.length()
	_check(early > 150.0 and early < 175.0, "Boost should ramp progressively above 150")
	_advance(mode, 5.0)
	_check(is_equal_approx(hero.velocity.length(), 187.5), "Sustained boost should reach 187.5")
	var charged := mode._boost_time
	hero.input.aim = hero.input.aim.rotated(Vector3.UP, 0.1)
	_advance(mode, 0.2)
	_check(mode._boost_time >= charged, "Gentle steering should preserve sustained boost")
	hero.input.sprint_held = false
	_advance(mode, 0.1)
	_check(is_zero_approx(mode._boost_time), "Releasing boost should reset its timer")
	_advance(mode, 5.0)
	_check(is_equal_approx(hero.velocity.length(), 33.0), "Releasing boost should return to cruise")
	hero.input.sprint_held = true
	hero.input.stick = Vector2(1.0, -1.0)
	hero.input.vertical = 1.0
	_advance(mode, 8.0)
	_check(absf(hero.velocity.length() - 187.5) < 0.01, "Diagonal flight must share the same cap")
	hero.input.clear()
	hero.input.sprint_held = true
	_advance(mode, 1.0)
	_check(is_zero_approx(mode._boost_time), "Holding boost while hovering must not charge it")
	hero.velocity = Vector3.ZERO
	hero.input.vertical = 1.0
	_advance(mode, 8.0, 30)
	_check(absf(hero.velocity.y - 187.5) < 0.01, "Vertical boost should work at 30 Hz")
	hero.velocity = Vector3.ZERO
	mode.physics_update(1.0 / 60.0)
	_check(is_zero_approx(mode._boost_time), "Blocked movement must reset sustained boost")
	mode._boost_time = 6.0
	mode.exit()
	_check(is_zero_approx(mode._boost_time), "Leaving flight should reset boost")
	mode._boost_time = 6.0
	mode.enter(&"Dive")
	_check(is_zero_approx(mode._boost_time), "Entering flight should start a fresh boost")
	hero.free()


func _tile(city: CityStreamer, level: int, i: int, with_node := true) -> CityStreamer.Tile:
	var tile := CityStreamer.Tile.new()
	tile.level = level
	tile.i = i
	tile.size = 500.0 * pow(2.0, level)
	if with_node:
		tile.node = Node3D.new()
		city.add_child(tile.node)
	return tile


func _test_visibility() -> void:
	var city := TestCity.new()
	add_child(city)
	var parent := _tile(city, 2, 0)
	var a := _tile(city, 1, 0, false)
	var b := _tile(city, 1, 1)
	var a1 := _tile(city, 0, 0)
	var a2 := _tile(city, 0, 1, false)
	parent.children.assign([a, b])
	a.parent = parent
	b.parent = parent
	a.children.assign([a1, a2])
	a1.parent = a
	a2.parent = a
	city._levels.assign([
		{"tiles": [a1, a2]}, {"tiles": [a, b]}, {"tiles": [parent]},
	])
	city._refresh_visibility()
	_check(parent.node.visible and not b.node.visible and not a1.node.visible,
		"A parent must remain drawn until all its descendant branches cover it")
	parent.node.free()
	parent.node = null
	city._refresh_visibility()
	_check(b.node.visible and a1.node.visible,
		"Ready descendants must draw while an absent parent or sibling loads")
	parent.node = Node3D.new()
	city.add_child(parent.node)
	a2.node = Node3D.new()
	city.add_child(a2.node)
	city._refresh_visibility()
	_check(not parent.node.visible and b.node.visible and a1.node.visible and a2.node.visible,
		"Complete child coverage must replace the parent without overlapping it")
	a2.node.free()
	a2.node = null
	city._refresh_visibility()
	_check(parent.node.visible and not b.node.visible and not a1.node.visible,
		"Unloading a child must restore the complete parent")
	var ref: WeakRef = weakref(parent)
	city.free()
	parent = null
	a = null
	b = null
	a1 = null
	a2 = null
	_check(ref.get_ref() == null, "Destroying the streamer must release the tile tree")


func _test_partial_build() -> void:
	var city := TestCity.new()
	add_child(city)
	city._threaded = true
	city.build_budget_msec = 0.1
	var tile := _tile(city, 0, 0, false)
	tile.pending = true
	city._levels.assign([{"name": "lod0", "size": 500.0, "tiles": [tile], "by_coord": {Vector2i.ZERO: tile}}])
	var lanes: Array[PackedVector3Array] = [PackedVector3Array([Vector3(1, 0, 1), Vector3(20, 0, 20)])]
	var surfaces: Array[Dictionary] = [
		{"kind": CityTileDecoder.SURFACE_LANES, "lanes": lanes.duplicate(true)},
		{"kind": CityTileDecoder.SURFACE_TRAFFIC, "lanes": lanes.duplicate(true), "info": PackedFloat32Array()},
		{"kind": CityTileDecoder.SURFACE_TRAINS, "tracks": lanes.duplicate(true)},
	]
	city._decoded.append([tile, surfaces])
	var frames := 0
	while tile.node == null and frames < 20:
		city._build_ready_tiles()
		frames += 1
		if tile.node == null:
			_check(tile.pending and city.pending_count() > 0, "A partial build must stay pending")
			_check(not city._building_node.visible, "Partial geometry must remain hidden")
			_check(not city.has_collision_at(Vector3.ONE), "Partial collision must not be advertised")
			_check(city.lanes_near(Vector3.ONE, 30.0).is_empty(), "Partial walking lanes must stay private")
			_check(city.traffic_lanes().is_empty() and city.train_tracks().is_empty(),
				"Partial traffic and train data must stay private")
	_check(frames > 1 and tile.node != null and not tile.pending, "A split build must finish and publish")
	_check(city.has_collision_at(Vector3.ONE) and city.lanes_near(Vector3.ONE, 30.0).size() == 1,
		"Completed collision and walking lanes must become available together")
	_check(city.traffic_lanes().size() == 1 and city.train_tracks().size() == 1,
		"Completed traffic and train metadata must become available")
	city.free()


func _test_prediction() -> void:
	var city := TestCity.new()
	add_child(city)
	var camera := Camera3D.new()
	add_child(camera)
	camera.add_to_group("floating")
	camera.current = true
	WorldOrigin.focus = null
	city._track_motion(1.0 / 60.0)
	for tick in 120:
		camera.position.x += 187.5 / 60.0
		city._track_motion(1.0 / 60.0)
	var focus := WorldOrigin.to_world(camera.global_position)
	var ahead := city._predicted_focus(focus)
	_check(absf(ahead.x - focus.x - 562.5) < 0.1, "Fast flight should prefetch three seconds ahead")
	var velocity := city._focus_velocity
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	camera.position.x += 187.5 / 60.0
	city._track_motion(1.0 / 60.0)
	_check(city._focus_velocity.distance_to(velocity) < 0.01, "Origin shifts must not disturb prediction")
	camera.position.x += 10000.0
	city._track_motion(1.0 / 60.0)
	_check(city._focus_velocity == Vector3.ZERO, "Teleports must reset the predictor")
	camera.rotation.y += PI
	city._track_motion(1.0 / 60.0)
	_check(city._focus_velocity == Vector3.ZERO, "Turning in place must not request distant tiles")
	city._focus_velocity = Vector3(400.0, 0.0, 0.0)
	_check(city._predicted_focus(Vector3.ZERO).length() <= 600.01, "Prefetch distance must be bounded")
	camera.free()
	city.free()
	WorldOrigin.offset = Vector3.ZERO


func _test_partial_cleanup() -> void:
	var city := TestCity.new()
	add_child(city)
	city._threaded = true
	city.build_budget_msec = 0.1
	var tile := _tile(city, 0, 0, false)
	tile.pending = true
	city._levels.assign([{"name": "lod0", "size": 500.0, "tiles": [tile]}])
	var lanes: Array[PackedVector3Array] = [PackedVector3Array([Vector3.ZERO, Vector3.ONE])]
	var surfaces: Array[Dictionary] = [
		{"kind": CityTileDecoder.SURFACE_LANES, "lanes": lanes},
		{"kind": CityTileDecoder.SURFACE_LANES, "lanes": lanes.duplicate(true)},
	]
	city._decoded.append([tile, surfaces])
	city._build_ready_tiles()
	_check(city._building_node != null and tile.node == null, "Cleanup fixture must stop during a partial build")
	var ref: WeakRef = weakref(city._building_node)
	city.free()
	_check(ref.get_ref() == null, "Exiting during a partial build must free the staging subtree exactly once")


func _test_prefetch_requests() -> void:
	var city := TestCity.new()
	add_child(city)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position.y = 120.0
	camera.current = true
	var ahead := _tile(city, 0, 2, false)
	var behind := _tile(city, 0, -2, false)
	var distant := _tile(city, 0, 10, false)
	city._levels.assign([{"tiles": [ahead, behind, distant]}])
	city._focus_velocity = Vector3(187.5, 0.0, 0.0)
	city._update_wanted_tiles()
	var requested: Array = city._queue.map(func(item: Array): return item[1])
	_check(requested.has(ahead) and requested.has(behind) and not requested.has(distant),
		"Prefetch must add upcoming detail and retain nearby coverage without loading the whole route")
	city._focus_velocity = Vector3.ZERO
	city._update_wanted_tiles()
	requested = city._queue.map(func(item: Array): return item[1])
	_check(not requested.has(ahead) and requested.has(behind), "A stopped camera should stop requesting ahead-only tiles")
	city.extra_foci.assign([Vector3(5000.0, 0.0, 0.0)])
	city._update_wanted_tiles()
	requested = city._queue.map(func(item: Array): return item[1])
	_check(requested.has(distant), "Co-op extra focus collision requests must be preserved")
	camera.free()
	city.free()
