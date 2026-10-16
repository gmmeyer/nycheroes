extends Node
## Headless check of moving traffic in midtown: loads the city around Sixth
## Avenue, lets the cars drive for a while and checks every frame that no car
## crosses a stop line on red, that cars on a path never overlap, that each
## car is drawn on its path, that no two cars use crossing ways through an
## intersection at once, and that cars move (and go through intersections with
## signals). Then stands the hero in front of a car and checks it stops
## short, and moves the camera to Brooklyn streets without signals until
## midtown unloads: no car may be left on an unloaded lane, and cars must
## appear there and take turns through its intersections, giving way to the
## widest street (no car without the right of way drives in front of one with
## it less than YIELD_CHECK seconds from its stop line). Prints the average
## speed in midtown (signals timed in green waves).
## --tiles=DIR (see CityStreamer) runs it on a copy of the tiles.
## Run: godot --headless --path . res://tests/traffic_test.tscn

## Sixth Avenue at about 40th Street, at street level (world meters).
const MIDTOWN := Vector3(420.0, 20.0, -220.0)
## Far enough away that midtown's tiles unload: Brooklyn streets around
## Bedford Avenue, whose intersections have no signals.
const ELSEWHERE := Vector3(3250.0, 25.0, 4750.0)
const LOAD_WAIT := 60.0
const DRIVE_TIME := 75.0
const HERO_TIME := 15.0
const AWAY_TIME := 40.0
## A car giving way never drives in front of a car with the right of way that's
## less than this long (s) from its line (Traffic.YIELD_TIME is longer).
const YIELD_CHECK := 1.5

var _world: Game
var _city: CityStreamer
var _traffic: Traffic
var _camera: FreeFlyCamera
var _hero: Hero
var _phase := "load"
var _time := 0.0
var _problems := 0
# Per car slot, what it was on last frame: path, and its front's position.
var _last_path: Array = []
var _last_s := PackedFloat32Array()
var _stats := {}
## The lane the hero stands on, how far along it, and where (world); the
## closest any car's front came to the hero, and the cars already past it.
var _hero_lane: TrafficLanes.Lane
var _hero_s := 0.0
var _hero_spot := Vector3.ZERO
var _closest_to_hero := INF
var _ahead_of_hero := {}


func _ready() -> void:
	# After the cars have moved and been drawn this frame.
	process_priority = 100
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	_world = world
	for node_name in ["PlayerInput", "Crowd", "Encounters"]:
		world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_city = world.get_node("City")
	_traffic = world.get_node("Traffic")
	_hero = world.get_node("Hero")
	_hero.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = world.get_node("FreeCamera")
	world.use_free_camera(true)
	_camera.set_process(false)
	_camera.global_position = WorldOrigin.to_local(MIDTOWN)
	_camera.rotation = Vector3(-0.1, deg_to_rad(-29.0), 0.0)
	# Keep the hero out of the way until it's needed.
	_hero.global_position = WorldOrigin.to_local(Vector3(0.0, 500.0, 0.0))
	_last_path.resize(_traffic.max_cars)
	_last_s.resize(_traffic.max_cars)
	for key in ["red_runs", "overlaps", "off_path", "box_conflicts", "signal_crossings", "free_crossings",
			"continuing", "distance", "max_cars", "car_seconds", "priority_crossings", "yield_crossings",
			"cut_offs"]:
		_stats[key] = 0.0


func _process(delta: float) -> void:
	_time += delta
	match _phase:
		"load":
			if (_city.pending_count() == 0 and _traffic.car_count >= _traffic.max_cars * 0.8) or _time > LOAD_WAIT:
				print("loaded in %.1f s: %d cars on %d tiles' lanes" % [_time, _traffic.car_count, _traffic.lanes.tiles.size()])
				if _traffic.car_count == 0:
					_fail("no cars in midtown")
				_next("drive")
		"drive":
			_stats.car_seconds += _traffic.car_count * delta
			_check_frame()
			if _time > DRIVE_TIME:
				_report_drive()
				_place_hero()
				_next("hero")
		"hero":
			_check_frame()
			_check_hero()
			if _time > HERO_TIME:
				_report_hero()
				_hero.global_position = WorldOrigin.to_local(Vector3(0.0, 500.0, 0.0))
				_camera.global_position = WorldOrigin.to_local(ELSEWHERE)
				_next("away")
		"away":
			_check_frame()
			if _time > AWAY_TIME and _city.pending_count() == 0:
				_report_away()
				print("traffic test finished: %d problems" % _problems)
				get_tree().quit(1 if _problems else 0)


func _next(phase: String) -> void:
	_phase = phase
	_time = 0.0


func _fail(what: String) -> void:
	_problems += 1
	push_error("traffic: " + what)


## Per-frame checks over every car.
func _check_frame() -> void:
	var t := _traffic
	var now := TrafficSignals.clock()
	var origin := WorldOrigin.offset
	_stats.max_cars = maxf(_stats.max_cars, t.car_count)
	for i in t._highest + 1:
		var path: TrafficLanes.Path = t._path[i]
		var last: TrafficLanes.Path = _last_path[i]
		if path == null:
			_last_path[i] = null
			continue
		if path.removed:
			_stats.removed = _stats.get("removed", 0) + 1
		# Crossing a stop line: last frame on a lane short of its end, now
		# past it (on the connector out of it).
		if last is TrafficLanes.Lane and path != last and path is TrafficLanes.Connector \
				and (path as TrafficLanes.Connector).in_lane == last:
			var lane := last as TrafficLanes.Lane
			if lane.signal_offset >= 0.0:
				_stats.signal_crossings += 1
				if TrafficSignals.light(lane.signal_offset, now) == TrafficSignals.Light.RED:
					_stats.red_runs += 1
					push_error("car %d crossed a stop line on red (phase %.3f, speed %.1f m/s)" % [
						i, TrafficSignals.phase(lane.signal_offset, now), t._v[i]])
			elif lane.at_intersection:
				_stats.free_crossings += 1
				_check_yield(i, lane, path as TrafficLanes.Connector)
			else:
				_stats.continuing += 1
		if last == path:
			_stats.distance += maxf(t._s[i] - _last_s[i], 0.0)
		_last_path[i] = path
		_last_s[i] = t._s[i]
		# Drawn where it is: its middle on its path (or the one before).
		var b := i * Traffic.STRIDE
		var drawn := Vector3(t._buffer[b + 3], t._buffer[b + 7], t._buffer[b + 11]) + origin
		var near := _distance_to(path, drawn)
		if t._prev[i]:
			near = minf(near, _distance_to(t._prev[i], drawn))
			if t._prev[i] is TrafficLanes.Connector:
				near = minf(near, _distance_to((t._prev[i] as TrafficLanes.Connector).in_lane, drawn))
		if near > 0.3:
			_stats.off_path += 1
			if _stats.off_path < 8:
				print("  off path: car %d %.2f m, %s, s %.1f of %.1f, v %.1f, prev %s" % [i, near, "lane" if path is TrafficLanes.Lane else "connector", t._s[i], path.length, t._v[i], t._prev[i] != null])
	# Cars on one path keep their order and never overlap.
	for path in t._busy:
		for k in range(1, path.cars.size()):
			var ahead := path.cars[k - 1]
			var behind := path.cars[k]
			if t._s[ahead] - t._length[ahead] - t._s[behind] < -0.05:
				_stats.overlaps += 1
	# No two connectors in use at an intersection cross each other.
	var seen := {}
	for path in t._busy:
		var via := path as TrafficLanes.Connector
		if via == null or via.box == null or seen.has(via.box):
			continue
		seen[via.box] = true
		var busy := via.box.busy
		for m in busy.size():
			for n in range(m + 1, busy.size()):
				if t.lanes.conflict(busy[m], busy[n]):
					_stats.box_conflicts += 1


## A car from `lane` (no signal) just drove onto `via`: with the right of way,
## or after giving way to any car that has it.
func _check_yield(i: int, lane: TrafficLanes.Lane, via: TrafficLanes.Connector) -> void:
	var t := _traffic
	if lane.priority:
		_stats.priority_crossings += 1
		return
	_stats.yield_crossings += 1
	for other: TrafficLanes.Lane in t.lanes.arriving(lane.to_node):
		if not other.priority:
			continue
		for j in other.cars:
			var other_via: TrafficLanes.Connector = t._via[j]
			if other_via == null or not t.lanes.conflict(via, other_via) or t._v[j] < 1.0:
				continue
			if other.length - t._s[j] < t._v[j] * YIELD_CHECK + 2.0:
				_stats.cut_offs += 1
				push_warning("car %d cut off car %d (%.1f m from its line at %.1f m/s)" % [i, j, other.length - t._s[j], t._v[j]])
				return


func _distance_to(path: TrafficLanes.Path, point: Vector3) -> float:
	var best := INF
	for k in path.points.size() - 1:
		var closest := Geometry3D.get_closest_point_to_segment(point, path.points[k], path.points[k + 1])
		best = minf(best, closest.distance_to(point))
	# The middle of a car on a short path may be before its start, and cars are
	# drawn moved on a little since the last driving step (maybe past its end).
	var n := path.points.size()
	var start_out := path.points[0] - (path.points[1] - path.points[0]).normalized() * 8.0
	var end_out := path.points[n - 1] + (path.points[n - 1] - path.points[n - 2]).normalized() * 1.0
	best = minf(best, point.distance_to(Geometry3D.get_closest_point_to_segment(point, start_out, path.points[0])))
	best = minf(best, point.distance_to(Geometry3D.get_closest_point_to_segment(point, path.points[n - 1], end_out)))
	return best


func _report_drive() -> void:
	print("drove %.0f s: up to %d cars, %.0f m driven (%.1f m/s on average), %d stop lines crossed at signals (%d on red), %d crossings without a signal, %d where the street goes on, %d overlaps, %d drawn off their path, %d crossing ways in use at once, %.3f ms a frame" % [
		DRIVE_TIME, _stats.max_cars, _stats.distance, _stats.distance / maxf(_stats.car_seconds, 1.0), _stats.signal_crossings, _stats.red_runs, _stats.free_crossings,
		_stats.continuing, _stats.overlaps, _stats.off_path, _stats.box_conflicts, _traffic.update_msec])
	if _stats.red_runs > 0:
		_fail("%d cars ran red lights" % _stats.red_runs)
	if _stats.overlaps > 0:
		_fail("%d overlaps" % _stats.overlaps)
	if _stats.off_path > 0:
		_fail("%d cars drawn off their path" % _stats.off_path)
	if _stats.box_conflicts > 0:
		_fail("%d crossing ways used at once" % _stats.box_conflicts)
	if _stats.distance < _stats.max_cars * DRIVE_TIME * 1.5:
		_fail("cars hardly moved (%.0f m)" % _stats.distance)
	if _stats.signal_crossings < 10:
		_fail("too few cars went through signals")


## Stands the hero on a lane 20 m ahead of a moving car near the camera, on a
## long straight stretch.
func _place_hero() -> void:
	var t := _traffic
	for i in t._highest + 1:
		var lane := t._path[i] as TrafficLanes.Lane
		if lane == null or t._v[i] < 4.0 or lane.length - t._s[i] < 45.0 or t._at[i].distance_to(MIDTOWN) > 150.0:
			continue
		_hero_lane = lane
		_hero_s = t._s[i] + 20.0
		_hero_spot = lane.point_on(lane.segment_at(_hero_s, 0), _hero_s)
		_hero.global_position = WorldOrigin.to_local(_hero_spot)
		for j in lane.cars:
			if t._s[j] > _hero_s:
				_ahead_of_hero[j] = true
		print("hero stands on a lane 20 m ahead of car %d (%.1f m/s)" % [i, t._v[i]])
		return
	_fail("no car to stand in front of")


## No car on the hero's lane drives into the hero (cars already past it, or
## that appear past it, drive on).
func _check_hero() -> void:
	var t := _traffic
	if _hero_lane == null:
		return
	for j in _hero_lane.cars:
		if _ahead_of_hero.has(j):
			continue
		if t._s[j] > _hero_s + 3.0:
			_ahead_of_hero[j] = true  # appeared past the hero
			continue
		_closest_to_hero = minf(_closest_to_hero, _hero_s - t._s[j])


func _report_hero() -> void:
	var t := _traffic
	# The car nearest behind the hero stands still.
	var nearest := -1
	if _hero_lane:
		for j in _hero_lane.cars:
			if not _ahead_of_hero.has(j) and (nearest < 0 or t._s[j] > t._s[nearest]):
				nearest = j
	var speed: float = t._v[nearest] if nearest >= 0 else -1.0
	print("hero: cars on its lane came within %.1f m; the nearest stands at %.1f m/s" % [_closest_to_hero, speed])
	if _closest_to_hero < 0.5 or speed > 0.3:
		_fail("a car didn't stop for the hero")


func _report_away() -> void:
	var t := _traffic
	var stale := 0
	var far := 0
	for i in t._highest + 1:
		if t._path[i] == null:
			continue
		if t._path[i].removed:
			stale += 1
		if Vector2(t._at[i].x - ELSEWHERE.x, t._at[i].z - ELSEWHERE.z).length() > t.despawn_distance + 50.0:
			far += 1
	var midtown_tiles := 0
	for key: Vector2i in t.lanes.tiles:
		var bounds: Rect2 = t.lanes.tile_bounds[key]
		if bounds.has_point(Vector2(MIDTOWN.x, MIDTOWN.z)):
			midtown_tiles += 1
	print("moved away: %d cars, %d on unloaded lanes, %d far from the camera, midtown lanes loaded: %d, %d removed-lane sightings, %d crossings without a signal (%d in all), %d red runs, %d overlaps, %d crossing ways in use at once, %d drawn off their path; without signals %d with the right of way, %d giving way, %d cut off a car with it" % [
		t.car_count, stale, far, midtown_tiles, _stats.get("removed", 0), _stats.free_crossings, _stats.signal_crossings + _stats.free_crossings + _stats.continuing,
		_stats.red_runs, _stats.overlaps, _stats.box_conflicts, _stats.off_path, _stats.priority_crossings,
		_stats.yield_crossings, _stats.cut_offs])
	if _stats.priority_crossings < 5 or _stats.yield_crossings < 5:
		_fail("too few crossings with and without the right of way")
	if _stats.cut_offs > _stats.yield_crossings * 0.02:
		_fail("cars without the right of way cut off cars with it")
	if _stats.free_crossings < 10:
		_fail("too few cars went through intersections without signals")
	if _stats.red_runs > 0 or _stats.overlaps > 0 or _stats.box_conflicts > 0 or _stats.off_path > 0:
		_fail("red runs, overlaps or crossing ways in Brooklyn")
	if stale > 0 or _stats.get("removed", 0) > 0:
		_fail("cars left on unloaded lanes")
	if far > 0:
		_fail("cars left far from the camera")
	if midtown_tiles > 0:
		_fail("midtown's lanes didn't unload")
	if t.car_count == 0:
		_fail("no cars at the new spot")
