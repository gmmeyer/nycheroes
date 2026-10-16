class_name Traffic
extends Node3D
## Moving traffic: cars driving the near tiles' lanes (TrafficLanes, from
## CityStreamer.traffic_lanes_changed) around the camera, drawn as one
## MultiMesh (one draw call for every car).
##
## Cars appear out of sight (behind the camera or buildings) or, far off,
## grow in, up to max_cars within `radius` of the camera, and go once they're
## past despawn_distance (shrinking away if they're in view) or their tile
## unloads. Wide streets get more of them (TrafficLanes.spawn_weight(), and
## at intersections they keep to wide streets), and fewer appear behind the
## camera, where those out of sight go sooner (BEHIND_*), so most drive where
## it looks. They follow their lane at its speed limit (each driver a little
## under it), keeping their distance from the car ahead with the Intelligent
## Driver Model, also across intersections. At a signal they stop at the stop
## line on red, and on yellow if they can stop comfortably (else they're
## through before red); TrafficSignals' clock is the one the signal poles show.
## Where there's no signal the widest street has the right of way: its cars
## keep going (slowing only for turns, or for a car crossing their way), and
## the others slow down and go once their way across is clear
## (TrafficLanes.box_free) with no car on the widest street about to cross
## it (also one still on its way onto a short stretch of it), and give their
## way back to one that turns up while they can still stop; no car appears
## just short of an intersection it would have the right of way at while one
## giving way crosses. They never drive into an intersection without room on
## the other side. At each intersection a car picks its next
## lane (TrafficLanes.pick_next), blinking before it turns. They stop for
## heroes, thugs (standing or lying) and pedestrians in their way. Nothing
## collides with them yet. Yellow cabs make up about a third of the cars in
## Manhattan below 110th Street, a few percent elsewhere; buses keep to
## streets.
##
## Driving runs 30 times a second whatever the frame rate (each car drawn
## moved on by the time since), with the cars as rows of numbers rather than
## nodes; cars behind the camera are drawn every 4th frame and far ones every
## other, and cars standing still aren't redrawn: about 0.25 ms a frame for
## 120 cars on the web (?stats logs the parts).
##
## Each car is an instance of PropMeshes.car() with CityStreamer.car_material:
## its transform scales the mesh to (length, height, length) m with no
## rotation and moves it to the middle of its footprint on the road;
## INSTANCE_CUSTOM is (yaw radians, model, seed 0..1, 16), the front facing
## (sin yaw, 0, cos yaw); COLOR is (paint 0..11, LIGHT_* flags, wheel roll
## radians, 0). The buffer is rewritten every frame (only what changed) and
## each car keeps its slot while it lives; unused slots are scaled to nothing.
## While the city's lights are on, a second MultiMesh on the same buffer
## draws glows round their headlights and taillights
## (shaders/car_light_glow.gdshader).
## ?traffic=N sets how many cars (0: none); Quality sets fewer on phones.

## How hard each car model (CityTileDecoder.CAR_*) pulls away (m/s^2).
const PULL: Array[float] = [2.2, 2.2, 2.0, 1.9, 1.9, 1.5, 2.2, 1.2, 1.0]
## Everything but taxis and buses, as common as in the city's traffic
## (cumulative shares, by MIX_MODELS).
const MIX_MODELS: Array[int] = [CityTileDecoder.CAR_SEDAN, CityTileDecoder.CAR_HATCHBACK, CityTileDecoder.CAR_SUV,
	CityTileDecoder.CAR_MINIVAN, CityTileDecoder.CAR_PICKUP, CityTileDecoder.CAR_VAN, CityTileDecoder.CAR_BOX_TRUCK]
const MIX_SHARES: Array[float] = [0.35, 0.44, 0.74, 0.81, 0.87, 0.95, 1.0]
## Paint 0..11 (white, black, silver, mid gray, dark gray, dark blue, red,
## blue, dark green, beige, brown, orange) as common as on real cars (the
## parked cars' mix in tools/citygen/traffic.py), cumulative.
const PAINT_SHARES: Array[float] = [0.24, 0.45, 0.57, 0.69, 0.75, 0.80, 0.88, 0.93, 0.95, 0.97, 0.99, 1.0]
## Yellow cabs: their share in Manhattan below about 110th Street, and elsewhere.
const TAXI_SHARE_MANHATTAN := 0.35
const TAXI_SHARE := 0.03
## Buses, on streets no faster than BUS_MAX_SPEED (m/s).
const BUS_SHARE := 0.025
const BUS_MAX_SPEED := 12.0
## Manhattan up to about 110th Street (latitude, longitude), for taxis.
const MANHATTAN: Array[Vector2] = [
	Vector2(40.7003, -74.0161), Vector2(40.7055, -74.0190), Vector2(40.7150, -74.0180), Vector2(40.7280, -74.0130),
	Vector2(40.7420, -74.0110), Vector2(40.7530, -74.0085), Vector2(40.7660, -73.9980), Vector2(40.7800, -73.9900),
	Vector2(40.7930, -73.9800), Vector2(40.8050, -73.9700), Vector2(40.7912, -73.9372), Vector2(40.7840, -73.9415),
	Vector2(40.7745, -73.9435), Vector2(40.7600, -73.9575), Vector2(40.7485, -73.9680), Vector2(40.7370, -73.9725),
	Vector2(40.7265, -73.9705), Vector2(40.7120, -73.9785), Vector2(40.7088, -73.9935), Vector2(40.7040, -74.0055),
	Vector2(40.7010, -74.0125)]
## World x and z from latitude and longitude (as the debug HUD does).
const ORIGIN_LAT := 40.7580
const ORIGIN_LON := -73.9855
const METERS_PER_DEGREE := 111320.0

## Light flags (COLOR.g): driving (headlights at night), braking, left and
## right turn signals, a taxi's roof sign lit (it's free).
const LIGHT_DRIVING := 1
const LIGHT_BRAKING := 2
const LIGHT_LEFT := 4
const LIGHT_RIGHT := 8
const LIGHT_TAXI_SIGN := 16

## The driver model (Intelligent Driver Model): time gap to the car ahead
## (s), gap left when stopped (m), comfortable and hardest braking (m/s^2).
const HEADWAY := 1.3
const JAM_GAP := 2.0
const COMFORT_BRAKE := 2.5
const MAX_BRAKE := 8.0
## Added to the distance to a stop line, so cars pull up to about 0.8 m
## from it (instead of JAM_GAP).
const STOP_LINE_GAP := 1.2
## On yellow, cars that can stop braking at most this hard (m/s^2) do.
const YELLOW_BRAKE := 3.5
## Drivers aim for this share of the speed limit (cartoon city, gentle).
const DESIRE := Vector2(0.82, 0.97)
## Through an intersection without a signal, at most this fast (m/s), unless
## the street has the right of way there, or on highways (lanes at least
## HIGHWAY_SPEED), where those are ramps.
const UNSIGNALED_SPEED := 4.5
const HIGHWAY_SPEED := 15.0
## The car ahead, a stop line or a turn further than this is no concern yet (m).
const LOOK_AHEAD := 70.0
## A car waiting this long at a clear light for its way across (s) claims
## the intersection next (TrafficLanes.Box).
const CLAIM_AFTER := 4.0
## Without a signal, a car on a street without the right of way waits for a
## car on the widest street whose way it would cross while that one is less
## than this long (s) or this far (m) from its stop line.
const YIELD_TIME := 4.0
const YIELD_DISTANCE := 8.0
## People within this far ahead (m), and this far to either side of a car's
## middle (on top of half its width), make it stop this far short of them.
const PERSON_AHEAD := 25.0
const PERSON_SIDE := 0.9
const PERSON_GAP := 2.0
## People are looked up in a grid of this many cells of this size (m) around
## the camera.
const PERSON_CELL := 32.0
const PERSON_CELLS := 24

## Cars appear at least this far from the camera (m), out of its sight; past
## grow_distance they may also appear in view, growing in over GROW_TIME (s)
## (and shrink away the same way). Further than despawn_distance they go.
const MIN_SPAWN_DISTANCE := 25.0
const GROW_TIME := 1.2
## Behind the camera (more than about 120 degrees off where it looks, and
## past BEHIND_REACH m), where cars are only seen if it turns round, only
## BEHIND_SHARE of the spots tried take a new car, and cars out of sight past
## BEHIND_DESPAWN of the radius go, so more drive ahead.
const BEHIND_COS := -0.5
const BEHIND_REACH := 60.0
const BEHIND_SHARE := 0.3
const BEHIND_DESPAWN := 0.7
## Fewer cars than this (high's) drive nearer the camera, as densely.
const FULL_CARS := 180.0
## Room kept around a new car on its lane (m), and from its lane's ends.
const SPAWN_ROOM := 8.0
const SPAWN_END_ROOM := 6.0
## Spawn tries per frame: while the city first loads, and after.
const FILL_TRIES := 40
const TRIES := 4
## A car standing this long out of sight (s), or stuck at a dead end, goes.
const STUCK_TIME := 45.0
## A car held up by someone in the road honks after this long (s), then not
## again for HONK_AGAIN.
const HONK_AFTER := 2.0
const HONK_AGAIN := 8.0
## How often cars' places and speeds go to the engine sounds (s).
const SOUND_INTERVAL := 0.1
const UPKEEP_INTERVAL := 0.25
## Floats per instance in the MultiMesh buffer: a 3x4 transform, color, custom.
const STRIDE := 20
## A car stands still below this speed (m/s), braking lights on.
const STOPPED := 0.3
## Cars blink this far before a turn (m), and through it.
const BLINK_AHEAD := 40.0
## Driving steps per second, and at most this many in one frame.
const SIM_STEP := 1.0 / 30.0
const MAX_STEPS := 3
## Cars behind the camera are drawn every DRAW_BEHIND frames, and cars
## further than DRAW_FAR (m) every other frame.
const DRAW_BEHIND := 4
const DRAW_FAR := 150.0
## With ?stats, how often the time spent is logged (s).
const LOG_INTERVAL := 2.0

@export var city: CityStreamer
@export var crowd: CrowdManager
## How many cars at most (?traffic=N), and how far from the camera they
## drive (m). Quality lowers both on phones and tablets.
@export var max_cars := 180
@export var radius := 300.0
@export var grow_distance := 180.0
@export var despawn_distance := 360.0

## The lane graph.
var lanes := TrafficLanes.new()
## Cars driving now.
var car_count := 0
## Script time per frame (ms, smoothed), and to add the last tile's lanes.
var update_msec := 0.0
var last_tile_msec := 0.0

var _multimesh: MultiMesh
var _instance: MultiMeshInstance3D
var _glow_multimesh: MultiMesh
var _glows: MultiMeshInstance3D
var _buffer := PackedFloat32Array()
var _highest := -1
# Per car slot. A car's s is how far its front is along its path; its back
# may still be on the path before.
var _path: Array[TrafficLanes.Path] = []
var _prev: Array[TrafficLanes.Path] = []
## On a lane: the lane it goes to next and the connector there (null if it
## has nowhere to go yet).
var _next: Array[TrafficLanes.Lane] = []
var _via: Array[TrafficLanes.Connector] = []
## The connector of the intersection it's in (until its back is out).
var _in_box: Array[TrafficLanes.Connector] = []
var _s := PackedFloat32Array()
var _v := PackedFloat32Array()
var _length := PackedFloat32Array()
var _desire := PackedFloat32Array()
var _pull := PackedFloat32Array()
## 1 / (2 sqrt(pull x comfortable braking)), for the driver model.
var _brake_term := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _roll := PackedFloat32Array()
## 0..1 while growing in or shrinking away, else 1.
var _grow := PackedFloat32Array()
var _shrinking := PackedByteArray()
var _wait := PackedFloat32Array()
var _stuck := PackedFloat32Array()
## Time held up by someone in the road (s); negative after a honk.
var _honk := PackedFloat32Array()
## Whether the last _look_for_people found someone nearer than the car ahead.
var _person_in_way := false
## Speeds for the engine sounds (GameAudio.set_traffic): -1 for empty slots.
var _sound_speeds := PackedFloat32Array()
var _sound_cooldown := 0.0
var _model := PackedInt32Array()
var _lights := PackedInt32Array()
## LIGHT_LEFT or LIGHT_RIGHT for the turn ahead, or 0.
var _turn_light := PackedInt32Array()
## Committed to going through on yellow.
var _going := PackedByteArray()
var _segment := PackedInt32Array()
## Drawn standing still (its place needn't be written again until it moves).
var _at_rest := PackedByteArray()
var _drawn_origin := Vector3.ZERO
## Each car's middle and heading as last drawn (world), for seeing people ahead.
var _at := PackedVector3Array()
## Paths with cars on them.
var _busy: Array[TrafficLanes.Path] = []
# People in the way: world positions, and a grid of linked lists over them.
var _people := PackedVector3Array()
var _cell_first := PackedInt32Array()
var _cell_next := PackedInt32Array()
var _grid_origin := Vector2.ZERO
## Around all the people, grown by how far ahead cars look for them (x, z).
var _people_box := Rect2()
# Where cars may appear: tiles near the camera and their running lane lengths.
var _spawn_tiles: Array[Vector2i] = []
var _spawn_totals := PackedFloat32Array()
var _focus := Vector3.ZERO
## Where the camera looks, on the ground (x, z; zero looking straight down).
var _heading := Vector2.ZERO
var _camera: Camera3D
var _now := 0.0
var _upkeep := 0.0
var _city_ready := false
# ?stats: each part's time (ms, smoothed) and when the last part ended.
var _log_stats := false
var _log_cooldown := 0.0
var _part_msec := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _part_mark := 0
## Seconds since the game started (scaled), since the last driving step, and
## when each car was last drawn.
var _clock := 0.0
var _since_step := 0.0
var _drawn_time := PackedFloat32Array()
var _manhattan := PackedVector2Array()
# What _look_ahead found: the gap to what's ahead (m), how fast we close on
# it (m/s), and the speed to keep to for what's coming (m/s).
var _gap := INF
var _closing := 0.0
var _cap := INF


func _ready() -> void:
	if LaunchOptions.has("traffic"):
		max_cars = maxi(int(LaunchOptions.get_string("traffic")), 0)
	_log_stats = LaunchOptions.has("stats")
	# Fewer cars drive nearer, as densely.
	var full := radius
	radius = clampf(full * sqrt(max_cars / FULL_CARS), 160.0, full)
	despawn_distance += radius - full
	grow_distance = minf(grow_distance, radius * 0.6)
	for corner in MANHATTAN:
		_manhattan.append(Vector2((corner.y - ORIGIN_LON) * METERS_PER_DEGREE * cos(deg_to_rad(ORIGIN_LAT)),
			-(corner.x - ORIGIN_LAT) * METERS_PER_DEGREE))
	_cell_first.resize(PERSON_CELLS * PERSON_CELLS)
	_setup_slots(max_cars)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = PropMeshes.car()
	_multimesh.instance_count = max_cars
	_multimesh.visible_instance_count = 0
	if max_cars > 0:
		_multimesh.buffer = _buffer
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Cars"
	_instance.multimesh = _multimesh
	_instance.material_override = _car_material()
	# The shader draws each car's contact shadow; cars cast no real ones.
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cars are written in scene space around the camera wherever the origin
	# is, so the box only needs to hold the whole area that can be drawn.
	_instance.custom_aabb = AABB(Vector3(-4000.0, -200.0, -4000.0), Vector3(8000.0, 1400.0, 8000.0))
	_instance.visible = max_cars > 0
	add_child(_instance)
	_glow_multimesh = MultiMesh.new()
	_glow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_glow_multimesh.use_colors = true
	_glow_multimesh.use_custom_data = true
	_glow_multimesh.mesh = _light_glow_mesh()
	_glow_multimesh.instance_count = max_cars
	_glow_multimesh.visible_instance_count = 0
	_glows = MultiMeshInstance3D.new()
	_glows.name = "CarLightGlows"
	_glows.multimesh = _glow_multimesh
	var glow_material := ShaderMaterial.new()
	glow_material.shader = load("res://shaders/car_light_glow.gdshader")
	_glows.material_override = glow_material
	_glows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glows.custom_aabb = _instance.custom_aabb
	_glows.visible = false
	add_child(_glows)
	if city and max_cars > 0:
		city.traffic_lanes_changed.connect(set_tile_lanes)
		city.initial_load_finished.connect(func(_seconds: float) -> void: _city_ready = true)
		var loaded := city.traffic_lanes()
		for key: Vector2i in loaded:
			set_tile_lanes(key, loaded[key][0], loaded[key][1])
	set_process(max_cars > 0)


## A tile's driving lanes arrived, or went (both empty): cars on lanes that
## went go with them.
func set_tile_lanes(key: Vector2i, polylines: Array[PackedVector3Array], info: PackedFloat32Array) -> void:
	var started := Time.get_ticks_usec()
	var removed := lanes.set_tile(key, polylines, info)
	last_tile_msec = (Time.get_ticks_usec() - started) / 1000.0
	if removed.is_empty():
		return
	for i in _highest + 1:
		if _path[i] == null:
			continue
		if _path[i].removed:
			_despawn(i)
			continue
		if _in_box[i] and _in_box[i].removed:
			_in_box[i] = null
		if _prev[i] and _prev[i].removed and _s[i] >= _length[i]:
			_prev[i] = null
		if _next[i] and _next[i].removed:
			_route(i)


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_camera = get_viewport().get_camera_3d()
	if _camera:
		_focus = WorldOrigin.to_world(_camera.global_position)
		var forward := -_camera.global_basis.z
		_heading = Vector2(forward.x, forward.z)
		_heading = _heading.normalized() if _heading.length() > 0.1 else Vector2.ZERO
	_clock += delta
	# Driving runs at a steady SIM_RATE (drawing goes on every frame).
	_since_step += delta
	var steps := 0
	while _since_step >= SIM_STEP and steps < MAX_STEPS:
		_since_step -= SIM_STEP
		steps += 1
		_now = TrafficSignals.clock()
		if car_count > 0:
			_find_people()
			_time_part(0, started)
			_drive(SIM_STEP)
			_time_part(1, started)
			_move_on()
			_time_part(2, started)
	_since_step = minf(_since_step, SIM_STEP)
	_upkeep -= delta
	if _upkeep <= 0.0:
		_upkeep = UPKEEP_INTERVAL
		_clear_away()
		_refresh_spawn_tiles()
	if _camera:
		_spawn(FILL_TRIES if not _city_ready else TRIES)
	_time_part(3, started)
	_draw()
	_sound_cooldown -= delta
	if _sound_cooldown <= 0.0:
		_sound_cooldown = SOUND_INTERVAL
		_send_sounds()
	_time_part(4, started)
	update_msec = lerpf(update_msec, (Time.get_ticks_usec() - started) / 1000.0, 0.05)
	if _log_stats:
		_log_cooldown -= delta
		if _log_cooldown <= 0.0:
			_log_cooldown = LOG_INTERVAL
			print("[traffic] %d cars (%d in sight), %.2f ms a frame; a driving step: people %.2f, driving %.2f, moving on %.2f; a frame: spawning %.2f, drawing %.2f; last tile's lanes %.2f" % [
				car_count, _count_in_sight(), update_msec, _part_msec[0], _part_msec[1], _part_msec[2], _part_msec[3],
				_part_msec[4], last_tile_msec])


## How many cars the camera sees (for ?stats).
func _count_in_sight() -> int:
	var seen := 0
	for i in _highest + 1:
		if _path[i] != null and not _hidden(_at[i]):
			seen += 1
	return seen


## Cars' places and speeds for the engine sounds.
func _send_sounds() -> void:
	var count := _highest + 1
	if _sound_speeds.size() < count:
		_sound_speeds.resize(_path.size())
	for i in count:
		_sound_speeds[i] = _v[i] if _path[i] != null else -1.0
	GameAudio.set_traffic(_at, _sound_speeds, count)


## Times a part of the update (for ?stats): from the last mark to now.
func _time_part(part: int, started: int) -> void:
	var now := Time.get_ticks_usec()
	var since: int = maxi(_part_mark, started)
	_part_msec[part] = lerpf(_part_msec[part], (now - since) / 1000.0, 0.05)
	_part_mark = now


## Driving: every car's speed and position this frame, path by path, front
## car first, so each knows the car ahead.
func _drive(dt: float) -> void:
	for path in _busy:
		var cars := path.cars
		var leader := -1
		for k in cars.size():
			var i := cars[k]
			var s := _s[i]
			var v := _v[i]
			if leader >= 0:
				_gap = _s[leader] - _length[leader] - s
				_closing = v - _v[leader]
				_cap = INF
			else:
				_look_ahead(i, path, s, v, dt)
			_person_in_way = false
			if _people_box.has_point(Vector2(_at[i].x, _at[i].z)):
				_look_for_people(i, v)
			if _person_in_way and v < STOPPED:
				_honk[i] += dt
				if _honk[i] >= HONK_AFTER:
					GameAudio.car_horn(_at[i])
					_honk[i] = -HONK_AGAIN
			else:
				_honk[i] = minf(_honk[i] + dt, 0.0)
			var desired := minf(path.speed * _desire[i], _cap)
			# The Intelligent Driver Model.
			var free := v / maxf(desired, 0.1)
			var a := 1.0 - free * free * free * free
			if _gap < LOOK_AHEAD:
				var wanted := JAM_GAP + maxf(0.0, v * HEADWAY + v * _closing * _brake_term[i])
				var squeeze := wanted / maxf(_gap, 0.05)
				a -= squeeze * squeeze
			a = maxf(a * _pull[i], -MAX_BRAKE)
			var v_next := v + a * dt
			if v_next < 0.0:
				# Stops within this frame.
				s += v * v / (-2.0 * a) if a < 0.0 else 0.0
				v_next = 0.0
			else:
				s += (v + v_next) * 0.5 * dt
			_s[i] = s
			_v[i] = v_next
			var lights := LIGHT_DRIVING
			if path.length - s < BLINK_AHEAD:
				lights |= _turn_light[i]  # (connectors are all shorter)
			if a < -0.8 or v_next < STOPPED:
				lights |= LIGHT_BRAKING
			_lights[i] = (_lights[i] & LIGHT_TAXI_SIGN) | lights
			leader = i


## For the front car of a path: what's ahead, past the path's end (the stop
## line, the intersection and the car ahead beyond them). Sets _gap,
## _closing and _cap.
func _look_ahead(i: int, path: TrafficLanes.Path, s: float, v: float, dt: float) -> void:
	_gap = INF
	_closing = 0.0
	_cap = INF
	var to_end := path.length - s
	if to_end > LOOK_AHEAD:
		return
	var lane := path as TrafficLanes.Lane
	var after: TrafficLanes.Path
	if lane:
		var via := _via[i]
		if via == null or via.removed:
			_gap = to_end + STOP_LINE_GAP  # nowhere to go (yet): wait at the end
			_closing = v
			return
		var through := via.speed
		if lane.at_intersection and lane.signal_offset < 0.0 and not lane.priority and lane.speed < HIGHWAY_SPEED:
			through = minf(through, UNSIGNALED_SPEED)
		_cap = sqrt(through * through + 2.0 * COMFORT_BRAKE * to_end)
		var stopping := v * v / (2.0 * COMFORT_BRAKE)
		if to_end < stopping + 2.0 * v + 12.0:
			if not _may_enter(i, lane, via, to_end, v, dt):
				_gap = to_end + STOP_LINE_GAP
				_closing = v
				return
			# Too close to stop comfortably now: it takes its way across, so
			# nobody else crosses it meanwhile.
			if _in_box[i] != via and to_end < stopping + 0.5 * v + 1.0:
				_enter_box(i, via)
		# The car that left this lane last, whichever way it went.
		var exit := lane.last_exit
		if exit >= 0 and exit != i and _path[exit] is TrafficLanes.Connector \
				and (_path[exit] as TrafficLanes.Connector).in_lane == lane:
			_gap = to_end + _s[exit] - _length[exit]
			_closing = v - _v[exit]
		after = via
	else:
		after = (path as TrafficLanes.Connector).out_lane
		if after.removed:
			_gap = to_end + STOP_LINE_GAP
			_closing = v
			return
	# The last car on the next path, or on the one after it.
	var reach := to_end
	for step in 2:
		if not after.cars.is_empty():
			var last := after.cars[after.cars.size() - 1]
			var gap := reach + _s[last] - _length[last]
			if gap < _gap:
				_gap = gap
				_closing = v - _v[last]
			return
		reach += after.length
		if reach > LOOK_AHEAD or not (after is TrafficLanes.Connector):
			return
		after = (after as TrafficLanes.Connector).out_lane


## Whether the front car of a lane may cross its stop line into the
## intersection: the signal lets it (on yellow only if it can't stop
## comfortably and gets through before red), its way across is clear, and
## there's room for it on the far side.
func _may_enter(i: int, lane: TrafficLanes.Lane, via: TrafficLanes.Connector, to_end: float, v: float,
		dt: float) -> bool:
	var box := via.box
	if lane.signal_offset >= 0.0:
		var light := TrafficSignals.light(lane.signal_offset, _now)
		if light != TrafficSignals.Light.GREEN:
			var arrival := TrafficSignals.light(lane.signal_offset, _now + to_end / maxf(v, 0.5))
			var can_stop := v * v <= 2.0 * YELLOW_BRAKE * maxf(to_end - 0.3, 0.0)
			if light == TrafficSignals.Light.RED or arrival == TrafficSignals.Light.RED or (can_stop and _going[i] == 0):
				_going[i] = 0
				_release_claim(i, via)
				if _in_box[i] == via:
					_leave_box(i)
				return false
			_going[i] = 1
	var unsignaled := lane.signal_offset < 0.0 and lane.at_intersection
	var gives_way := unsignaled and not lane.priority
	if _in_box[i] == via:
		# Its way is taken already. A car giving way takes it once it can't stop
		# comfortably, which coming fast is seconds before the line: while it
		# could still stop as on yellow, it gives it back to a car with the right
		# of way that turns up.
		if not gives_way or v * v > 2.0 * YELLOW_BRAKE * maxf(to_end - 0.3, 0.0) or not _priority_coming(lane, via):
			return true
		_leave_box(i)
	# Without a signal, cars on the widest street go first, whatever the others
	# have claimed.
	var priority_coming := gives_way and _priority_coming(lane, via)
	var free := lanes.box_free(via, i, not (unsignaled and lane.priority))
	if priority_coming or not free or not _room_after(i, via):
		# Waiting at the line: after a while, go next (but not before a car
		# with the right of way).
		if v < 1.0 and to_end < 6.0:
			_wait[i] += dt
			if _wait[i] > CLAIM_AFTER and box and box.claim == null and not priority_coming:
				box.claim = via
				box.claim_slot = i
		return false
	return true


## Whether a car with the right of way is about to cross `via` (the way of a
## car on `lane`, which hasn't): a car on another lane into the same
## intersection that has it, close to its stop line, going a way that
## conflicts. A lane that has it may be shorter than how far its cars look:
## cars still on their way onto it count too.
func _priority_coming(lane: TrafficLanes.Lane, via: TrafficLanes.Connector) -> bool:
	for other: TrafficLanes.Lane in lanes.arriving(lane.to_node):
		if not other.priority or other == lane:
			continue
		for j in other.cars:
			var to_line := other.length - _s[j]
			if to_line > LOOK_AHEAD:
				break  # (the rest are further back)
			if not _arrives_soon(j, other, to_line):
				continue
			var other_via := _via[j]
			if other_via and not other_via.removed and lanes.conflict(via, other_via):
				return true
		if other.length < LOOK_AHEAD and _coming_onto(other, other.length, other, via):
			return true
	return false


## Whether car j, `to_line` from the stop line of `lane` (which has the right
## of way), is there within YIELD_TIME (or YIELD_DISTANCE), speeding up as it
## may (a slow car that was behind one crossing just now is about to).
func _arrives_soon(j: int, lane: TrafficLanes.Lane, to_line: float) -> bool:
	var v := _v[j]
	var top := maxf(lane.speed * _desire[j], v)
	var t := minf((top - v) / _pull[j], YIELD_TIME)
	return to_line < v * t + 0.5 * _pull[j] * t * t + top * (YIELD_TIME - t) + YIELD_DISTANCE


## Whether a car on its way onto `path` (whose start is `behind` short of the
## stop line of `lane`, which has the right of way) is there soon and could
## cross `via`: it picks its way across only once it's on `lane`, so any way
## it may take counts.
func _coming_onto(path: TrafficLanes.Path, behind: float, lane: TrafficLanes.Lane,
		via: TrafficLanes.Connector) -> bool:
	var feeders: Array[TrafficLanes.Path] = []
	var into := path as TrafficLanes.Lane
	if into:
		for up: TrafficLanes.Lane in lanes.arriving(into.from_node):
			var connector: TrafficLanes.Connector = up.connectors.get(into)
			if connector:
				feeders.append(connector)
	else:
		feeders.append((path as TrafficLanes.Connector).in_lane)
	for feeder in feeders:
		for j in feeder.cars:
			var to_line := feeder.length - _s[j] + behind
			if to_line > LOOK_AHEAD:
				break
			if feeder is TrafficLanes.Lane and _via[j] != path:
				continue  # going another way
			if _arrives_soon(j, lane, to_line) and _may_cross(lane, via):
				return true
		var start := behind + feeder.length
		if start < LOOK_AHEAD and _coming_onto(feeder, start, lane, via):
			return true
	return false


## Whether a car on `lane` could cross `via`, whichever way it picks on
## (TrafficLanes.pick_next: back the way it came only at a dead end).
func _may_cross(lane: TrafficLanes.Lane, via: TrafficLanes.Connector) -> bool:
	var backs: Array[TrafficLanes.Lane] = []
	var any := false
	for out: TrafficLanes.Lane in lanes.leaving(lane.to_node):
		if lanes.turn_between(lane, out) == TrafficLanes.Turn.U_TURN:
			backs.append(out)
			continue
		any = true
		if lanes.conflict(via, lanes.connector(lane, out)):
			return true
	if not any:
		for out in backs:
			if lanes.conflict(via, lanes.connector(lane, out)):
				return true
	return false


## Whether there's room for car i on the lane past the intersection, behind
## the cars on it and the ones driving into it.
func _room_after(i: int, via: TrafficLanes.Connector) -> bool:
	var out := via.out_lane
	var room := out.length
	if not out.cars.is_empty():
		var last := out.cars[out.cars.size() - 1]
		room = _s[last] - _length[last]
	if via.box:
		for other in via.box.busy:
			if other.out_lane == out:
				for j in other.occupants:
					if j != i and _path[j] != out:
						room -= _length[j] + JAM_GAP
	return room >= minf(_length[i] + JAM_GAP, out.length * 0.6)


## People in car i's way: the nearest in a strip ahead of it. Lowers _gap.
func _look_for_people(i: int, v: float) -> void:
	var at := _at[i]
	var yaw := _yaw[i]
	var dx := sin(yaw)
	var dz := cos(yaw)
	# The middle of the strip ahead, and the 2x2 cells around it.
	var cx := (at.x + dx * PERSON_AHEAD * 0.5 - _grid_origin.x) / PERSON_CELL
	var cz := (at.z + dz * PERSON_AHEAD * 0.5 - _grid_origin.y) / PERSON_CELL
	var x0 := floori(cx - 0.5)
	var z0 := floori(cz - 0.5)
	var half := _length[i] * 0.5
	for gx in range(x0, x0 + 2):
		if gx < 0 or gx >= PERSON_CELLS:
			continue
		for gz in range(z0, z0 + 2):
			if gz < 0 or gz >= PERSON_CELLS:
				continue
			var p := _cell_first[gz * PERSON_CELLS + gx]
			while p >= 0:
				var person := _people[p]
				p = _cell_next[p]
				var rx := person.x - at.x
				var rz := person.z - at.z
				var ahead := rx * dx + rz * dz - half
				if ahead < -0.5 or ahead > PERSON_AHEAD or absf(person.y - at.y) > 2.5:
					continue
				if absf(rx * dz - rz * dx) > PropMeshes.CAR_SIZES[_model[i]].y * 0.5 + PERSON_SIDE:
					continue
				var gap := ahead - PERSON_GAP
				if gap < _gap:
					_gap = gap
					_closing = v
					_person_in_way = true


## Moves cars that have driven off the end of their path onto the next one,
## and lets go of intersections they've left.
func _move_on() -> void:
	for i in _highest + 1:
		var path := _path[i]
		if path == null:
			continue
		while _s[i] >= path.length:
			var lane := path as TrafficLanes.Lane
			var next: TrafficLanes.Path
			if lane:
				next = _via[i]
				if next == null or next.removed:
					break
				# Only with its way across taken (or taken now): else it waits
				# at the line.
				if _in_box[i] != next:
					if not _may_enter(i, lane, next, 0.0, _v[i], 0.0):
						break
					_enter_box(i, next)
				lane.last_exit = i
				_release_claim(i, next)
			else:
				next = (path as TrafficLanes.Connector).out_lane
				if next.removed:
					break
			_take(path, i)
			_s[i] -= path.length
			_prev[i] = path
			_path[i] = next
			_put(next, i)
			_segment[i] = 0
			if next is TrafficLanes.Lane:
				_route(i)
			path = next
		if _s[i] > path.length:
			_s[i] = path.length  # waiting at the end
			_v[i] = 0.0
		# Out of the intersection once its back is off the connector.
		var box := _in_box[i]
		if box and path != box and _via[i] != box and (_prev[i] != box or _s[i] >= _length[i]):
			_leave_box(i)


## Picks where car i goes after the lane it's on, and the light it shows for it.
func _route(i: int) -> void:
	var lane := _path[i] as TrafficLanes.Lane
	_release_claim(i, _via[i])
	if _in_box[i] and _path[i] == _in_box[i].in_lane:
		_leave_box(i)  # taken, but not driven onto yet
	_going[i] = 0
	_wait[i] = 0.0
	_next[i] = lanes.pick_next(lane) if lane else null
	_via[i] = lanes.connector(lane, _next[i]) if _next[i] else null
	_turn_light[i] = 0
	if _via[i]:
		match _via[i].turn:
			TrafficLanes.Turn.LEFT, TrafficLanes.Turn.U_TURN:
				_turn_light[i] = LIGHT_LEFT
			TrafficLanes.Turn.RIGHT:
				_turn_light[i] = LIGHT_RIGHT


## Lets go of car i's claim on the intersection at the end of `via`, if it has one.
func _release_claim(i: int, via: TrafficLanes.Connector) -> void:
	if via and via.box and via.box.claim_slot == i:
		via.box.claim = null
		via.box.claim_slot = -1


func _enter_box(i: int, via: TrafficLanes.Connector) -> void:
	if _in_box[i]:
		_leave_box(i)
	_in_box[i] = via
	via.occupants.append(i)
	if via.occupants.size() == 1 and via.box:
		via.box.busy.append(via)


func _leave_box(i: int) -> void:
	var via := _in_box[i]
	_in_box[i] = null
	var at := via.occupants.find(i)
	if at >= 0:
		via.occupants.remove_at(at)
	if via.occupants.is_empty() and via.box:
		via.box.busy.erase(via)


## Adds car i to the back of a path's cars.
func _put(path: TrafficLanes.Path, i: int) -> void:
	path.cars.append(i)
	if path.busy_index < 0:
		path.busy_index = _busy.size()
		_busy.append(path)


## Adds car i to a path's cars where its position puts it.
func _insert(path: TrafficLanes.Path, i: int) -> void:
	var at := 0
	while at < path.cars.size() and _s[path.cars[at]] > _s[i]:
		at += 1
	path.cars.insert(at, i)
	if path.busy_index < 0:
		path.busy_index = _busy.size()
		_busy.append(path)


func _take(path: TrafficLanes.Path, i: int) -> void:
	var at := path.cars.find(i)
	if at >= 0:
		path.cars.remove_at(at)
	if path.cars.is_empty() and path.busy_index >= 0:
		# Swap the last busy path into its place.
		var last: TrafficLanes.Path = _busy[_busy.size() - 1]
		_busy[path.busy_index] = last
		last.busy_index = path.busy_index
		_busy.resize(_busy.size() - 1)
		path.busy_index = -1


## Writes each car's place, heading and lights into the instance buffer.
func _draw() -> void:
	if _highest < 0 and _multimesh.visible_instance_count == 0:
		return
	var origin := WorldOrigin.offset
	var moved_origin := origin != _drawn_origin
	_drawn_origin = origin
	var frame := Engine.get_process_frames()
	var forward := -_camera.global_basis.z if _camera else Vector3.FORWARD
	for i in _highest + 1:
		var path := _path[i]
		if path == null:
			continue
		var v := _v[i]
		var steady := _grow[i] >= 1.0 and not _shrinking[i] and not moved_origin
		if steady:
			if v == 0.0 and _at_rest[i]:
				# Standing where it was drawn: only its lights may change.
				_buffer[i * STRIDE + 13] = _lights[i]
				continue
			# Behind the camera or far off, not every frame.
			var to_car := _at[i] - _focus
			var behind := to_car.dot(forward) < -20.0
			var far := to_car.x * to_car.x + to_car.z * to_car.z > DRAW_FAR * DRAW_FAR
			if (behind and (frame + i) % DRAW_BEHIND != 0) or (far and (frame + i) % 2 != 0):
				continue
		_at_rest[i] = 1 if v == 0.0 else 0
		var dt := _clock - _drawn_time[i]
		_drawn_time[i] = _clock
		var length := _length[i]
		# The middle of the car, on its path or the one before, moved on by
		# the time since the last driving step.
		var d := _s[i] - length * 0.5 + v * _since_step
		if d < 0.0 and _prev[i]:
			path = _prev[i]
			d += path.length
			if d < 0.0 and path is TrafficLanes.Connector:
				# Through a short connector: back on the lane before it.
				path = (path as TrafficLanes.Connector).in_lane
				d += path.length
		var along := path.along
		var last := along.size() - 2
		var k := mini(_segment[i], last)
		while k < last and d > along[k + 1]:
			k += 1
		while k > 0 and d < along[k]:
			k -= 1
		_segment[i] = k
		var span := along[k + 1] - along[k]
		var middle := path.points[k]
		if span > 0.0001:
			middle = middle.lerp(path.points[k + 1], (d - along[k]) / span)
		# The body turns toward the road's heading as it moves, like a car does.
		var yaw := _yaw[i]
		yaw += wrapf(path.yaws[k] - yaw, -PI, PI) * minf(v * dt / (0.45 * length), 1.0)
		yaw = wrapf(yaw, -PI, PI)
		_yaw[i] = yaw
		_at[i] = middle
		var roll := fposmod(_roll[i] + v * dt / PropMeshes.CAR_WHEEL_RADII[_model[i]], TAU)
		_roll[i] = roll
		if _shrinking[i]:
			_grow[i] = maxf(_grow[i] - dt / GROW_TIME, 0.0)
			if _grow[i] <= 0.0:
				_despawn(i)
				continue
			_write_size(i)
		elif _grow[i] < 1.0:
			_grow[i] = minf(_grow[i] + dt / GROW_TIME, 1.0)
			_write_size(i)
		var b := i * STRIDE
		_buffer[b + 3] = middle.x - origin.x
		_buffer[b + 7] = middle.y
		_buffer[b + 11] = middle.z - origin.z
		_buffer[b + 13] = _lights[i]
		_buffer[b + 14] = roll
		_buffer[b + 16] = yaw
	_multimesh.visible_instance_count = _highest + 1
	_multimesh.buffer = _buffer
	var lights_on := city != null and city.city_lights > 0.0
	if lights_on != _glows.visible:
		_glows.visible = lights_on
		# Fading out where the cars do (Quality may have moved that).
		var fade: Variant = _instance.material_override.get("shader_parameter/fade_distance")
		if fade is Vector2:
			(_glows.material_override as ShaderMaterial).set_shader_parameter("fade_distance", fade)
	if lights_on:
		_glow_multimesh.visible_instance_count = _highest + 1
		_glow_multimesh.buffer = _buffer


func _write_size(i: int) -> void:
	var size := PropMeshes.CAR_SIZES[_model[i]]
	var g := _grow[i]
	g = g * g * (3.0 - 2.0 * g)
	var b := i * STRIDE
	_buffer[b] = _length[i] * g
	_buffer[b + 5] = size.z * g
	_buffer[b + 10] = _length[i] * g


## Where people are (heroes, thugs standing or lying, pedestrians), in a grid
## around the camera.
func _find_people() -> void:
	_people.clear()
	for hero in Combat.heroes:
		_people.append(hero.world_position())
	for thug in Combat.thugs:
		_people.append(WorldOrigin.to_world(thug.ground_position()))
	if crowd:
		for pedestrian in crowd.pedestrians:
			_people.append(pedestrian.world_position)
	_people_box = Rect2()
	if _people.is_empty():
		return
	_grid_origin = Vector2(_focus.x, _focus.z) - Vector2.ONE * (PERSON_CELL * PERSON_CELLS * 0.5)
	_cell_first.fill(-1)
	_cell_next.resize(_people.size())
	for p in _people.size():
		var person := _people[p]
		var gx := floori((person.x - _grid_origin.x) / PERSON_CELL)
		var gz := floori((person.z - _grid_origin.y) / PERSON_CELL)
		if gx < 0 or gz < 0 or gx >= PERSON_CELLS or gz >= PERSON_CELLS:
			continue
		var cell := gz * PERSON_CELLS + gx
		_cell_next[p] = _cell_first[cell]
		_cell_first[cell] = p
		var spot := Rect2(person.x, person.z, 0.0, 0.0).grow(PERSON_AHEAD + 8.0)
		_people_box = spot if _people_box.size == Vector2.ZERO else _people_box.merge(spot)


## Cars too far away, stuck for good, or with nowhere to go once out of
## sight, go (shrinking away if in view).
func _clear_away() -> void:
	for i in _highest + 1:
		var path := _path[i]
		if path == null or _shrinking[i]:
			continue
		if _v[i] < STOPPED:
			_stuck[i] += UPKEEP_INTERVAL
		else:
			_stuck[i] = 0.0
		var at := _at[i]
		var distance := Vector2(at.x - _focus.x, at.z - _focus.z).length()
		var stranded := path is TrafficLanes.Lane and _via[i] == null and path.length - _s[i] < 1.0
		if stranded:
			_route(i)  # maybe the lanes on have loaded since
			stranded = _via[i] == null
		if distance < despawn_distance and _stuck[i] < STUCK_TIME and not stranded \
				and not _behind(at, radius * BEHIND_DESPAWN):
			continue
		if _hidden(at):
			_despawn(i)
		elif distance > despawn_distance:
			_shrinking[i] = 1


## The tiles whose lanes reach within `radius` of the camera, for spawning.
func _refresh_spawn_tiles() -> void:
	_spawn_tiles.clear()
	_spawn_totals.clear()
	var total := 0.0
	var focus := Vector2(_focus.x, _focus.z)
	for key: Vector2i in lanes.tile_bounds:
		var bounds: Rect2 = lanes.tile_bounds[key]
		var nearest := focus.clamp(bounds.position, bounds.end)
		if nearest.distance_to(focus) < radius:
			var totals: PackedFloat32Array = lanes.tile_totals[key]
			total += totals[totals.size() - 1]
			_spawn_tiles.append(key)
			_spawn_totals.append(total)


## Tries a few random spots on the lanes near the camera for new cars: out of
## sight, or far enough off to grow in. While the city first loads, anywhere.
func _spawn(tries: int) -> void:
	if car_count >= max_cars or _spawn_tiles.is_empty():
		return
	var anywhere := not _city_ready
	var total := _spawn_totals[_spawn_totals.size() - 1]
	for attempt in tries:
		if car_count >= max_cars:
			return
		var tile := _spawn_tiles[mini(_spawn_totals.bsearch(randf() * total), _spawn_tiles.size() - 1)]
		var tile_lanes: Array = lanes.tiles[tile]
		var totals: PackedFloat32Array = lanes.tile_totals[tile]
		var lane: TrafficLanes.Lane = tile_lanes[mini(totals.bsearch(randf() * totals[totals.size() - 1]), tile_lanes.size() - 1)]
		var model := _pick_model(lane)
		var length := PropMeshes.CAR_SIZES[model].x
		if lane.length < length + 2.0 * SPAWN_END_ROOM:
			continue
		var s := randf_range(length + SPAWN_END_ROOM, lane.length - SPAWN_END_ROOM)
		var k := lane.segment_at(s - length * 0.5, 0)
		var point := lane.point_on(k, s - length * 0.5)
		var distance := Vector2(point.x - _focus.x, point.z - _focus.z).length()
		if distance > radius or distance < MIN_SPAWN_DISTANCE:
			continue
		if _behind(point, BEHIND_REACH) and randf() > BEHIND_SHARE:
			continue
		var grow := not anywhere and not _hidden(point)
		if grow and point.distance_to(_focus) < grow_distance:
			continue
		var room := _room_at(lane, s, length)
		if room < 0.0:
			continue
		if _giving_way_ahead(lane, lane.length - s, lane.speed * DESIRE.y * YIELD_TIME + YIELD_DISTANCE):
			continue
		_add_car(lane, s, model, point, k, room, grow)


## Free road ahead of a new car on `lane` with its front at s, or -1 if it
## would be too close to another car.
func _room_at(lane: TrafficLanes.Lane, s: float, length: float) -> float:
	var room := lane.length - s
	for j in lane.cars:
		var front := _s[j]
		if front > s:
			if front - _length[j] < s + SPAWN_ROOM:
				return -1.0
			room = minf(room, front - _length[j] - s)
		elif front > s - length - SPAWN_ROOM - _v[j] * HEADWAY * 2.0:
			return -1.0  # too close in front of a car coming up behind
	return room


## Whether a car appearing `to_end` short of the end of `lane` could have the
## right of way, less than `reach` on, at an intersection that a car giving way
## is crossing (that one looked out for cars coming before this one was
## there). Looks on along the lanes after it, as lanes that have it may be short.
func _giving_way_ahead(lane: TrafficLanes.Lane, to_end: float, reach: float) -> bool:
	if to_end >= reach:
		return false
	if lane.priority and lane.signal_offset < 0.0:
		var box := lanes.box_at(lane.to_node)
		if box:
			for via in box.busy:
				if not via.in_lane.priority:
					return true
	for out: TrafficLanes.Lane in lanes.leaving(lane.to_node):
		if lanes.turn_between(lane, out) != TrafficLanes.Turn.U_TURN \
				and _giving_way_ahead(out, to_end + out.length, reach):
			return true
	return false


func _add_car(lane: TrafficLanes.Lane, s: float, model: int, middle: Vector3, k: int, room: float, grow: bool) -> void:
	var i := _path.find(null)
	if i < 0:
		return
	_path[i] = lane
	_prev[i] = null
	_in_box[i] = null
	_s[i] = s
	_length[i] = PropMeshes.CAR_SIZES[model].x
	_model[i] = model
	_desire[i] = randf_range(DESIRE.x, DESIRE.y)
	_pull[i] = PULL[model] * randf_range(0.9, 1.1)
	_brake_term[i] = 1.0 / (2.0 * sqrt(_pull[i] * COMFORT_BRAKE))
	# Already moving, slow enough to stop in the room it has.
	_v[i] = minf(lane.speed * _desire[i], sqrt(2.0 * COMFORT_BRAKE * maxf(room - JAM_GAP - 2.0, 0.0)) * 0.7)
	_yaw[i] = lane.yaws[k]
	_segment[i] = k
	_at[i] = middle
	_roll[i] = randf() * TAU
	_grow[i] = 0.0 if grow else 1.0
	_shrinking[i] = 0
	_at_rest[i] = 0
	_drawn_time[i] = _clock
	_stuck[i] = 0.0
	_honk[i] = 0.0
	var paint := _pick(PAINT_SHARES)
	_lights[i] = LIGHT_DRIVING | (LIGHT_TAXI_SIGN if model == CityTileDecoder.CAR_TAXI and randf() < 0.5 else 0)
	_insert(lane, i)
	_route(i)
	var b := i * STRIDE
	for n in STRIDE:
		_buffer[b + n] = 0.0
	_buffer[b + 3] = middle.x - WorldOrigin.offset.x
	_buffer[b + 7] = middle.y
	_buffer[b + 11] = middle.z - WorldOrigin.offset.z
	_buffer[b + 12] = paint
	_buffer[b + 13] = _lights[i]
	_buffer[b + 16] = _yaw[i]
	_buffer[b + 17] = model
	_buffer[b + 18] = randf()
	_buffer[b + 19] = 16.0
	_write_size(i)
	car_count += 1
	_highest = maxi(_highest, i)


func _despawn(i: int) -> void:
	if _path[i] == null:
		return
	_take(_path[i], i)
	if _in_box[i]:
		_leave_box(i)
	_release_claim(i, _via[i])
	_path[i] = null
	_prev[i] = null
	_next[i] = null
	_via[i] = null
	var b := i * STRIDE
	_buffer[b] = 0.0
	_buffer[b + 5] = 0.0
	_buffer[b + 10] = 0.0
	car_count -= 1
	while _highest >= 0 and _path[_highest] == null:
		_highest -= 1


## Whether a world point is behind the camera (see BEHIND_COS), further
## than `reach` from it on the ground.
func _behind(world_point: Vector3, reach: float) -> bool:
	var to := Vector2(world_point.x - _focus.x, world_point.z - _focus.z)
	var distance := to.length()
	return distance > reach and to.dot(_heading) < BEHIND_COS * distance


## Whether a world point is out of the camera's sight: outside its view, or
## behind a building (or the ground).
func _hidden(world_point: Vector3) -> bool:
	if _camera == null:
		return true
	var target := WorldOrigin.to_local(world_point) + Vector3.UP * 1.2
	if not _camera.is_position_in_frustum(target):
		return true
	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target, CityStreamer.COLLISION_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and from.distance_to(hit.position) < from.distance_to(target) - 2.0


func _pick_model(lane: TrafficLanes.Lane) -> int:
	if lane.speed <= BUS_MAX_SPEED and randf() < BUS_SHARE:
		return CityTileDecoder.CAR_BUS
	var middle := lane.points[lane.points.size() / 2]
	var in_manhattan := Geometry2D.is_point_in_polygon(Vector2(middle.x, middle.z), _manhattan)
	if randf() < (TAXI_SHARE_MANHATTAN if in_manhattan else TAXI_SHARE):
		return CityTileDecoder.CAR_TAXI
	return MIX_MODELS[_pick(MIX_SHARES)]


## An index into running shares (the last one 1), at random.
static func _pick(shares: Array[float]) -> int:
	var roll := randf()
	for n in shares.size():
		if roll < shares[n]:
			return n
	return shares.size() - 1


func _setup_slots(count: int) -> void:
	_path.resize(count)
	_prev.resize(count)
	_next.resize(count)
	_via.resize(count)
	_in_box.resize(count)
	# (Packed arrays are values: each is resized itself, not through a list.)
	_s.resize(count)
	_v.resize(count)
	_length.resize(count)
	_desire.resize(count)
	_pull.resize(count)
	_brake_term.resize(count)
	_yaw.resize(count)
	_roll.resize(count)
	_grow.resize(count)
	_wait.resize(count)
	_stuck.resize(count)
	_honk.resize(count)
	_model.resize(count)
	_lights.resize(count)
	_turn_light.resize(count)
	_segment.resize(count)
	_shrinking.resize(count)
	_at_rest.resize(count)
	_drawn_time.resize(count)
	_going.resize(count)
	_at.resize(count)
	_buffer.resize(count * STRIDE)
	_buffer.fill(0.0)


## Four quads (corners -1..1 in UV), one per light: UV2.x 0 and 1 the
## headlights, 2 and 3 the taillights (shaders/car_light_glow.gdshader).
## Vertex colors are white so the instances' colors (the light flags) reach
## the shader as they are (see PropMeshes._Builder.commit()).
static func _light_glow_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	for light in 4:
		var first := vertices.size()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			vertices.append(Vector3(corner.x, corner.y, 0.0))
			uv.append(corner)
			uv2.append(Vector2(light, 0.0))
		indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var white := PackedColorArray()
	white.resize(vertices.size())
	white.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = white
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## CityStreamer.car_material (the parked cars'), or one of our own with the
## same shader (in tests without a city).
func _car_material() -> Material:
	if city and city.car_material:
		return city.car_material
	var own := ShaderMaterial.new()
	own.shader = load("res://shaders/car.gdshader")
	return own
