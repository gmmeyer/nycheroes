class_name Trains
extends Node3D
## Subway trains on the els: they run along the near tiles' el tracks
## (TrainTracks, from CityStreamer.train_tracks_changed) around the camera,
## both ways where an el has two or more tracks, and stand at each platform
## for DWELL seconds. Between stations they run at up to TOP_SPEED, slower
## on curves (each point of track has its curve's speed limit), keep well
## back from the train ahead, take turns where tracks merge, and stop for
## anyone on the tracks ahead (heroes and thugs). A train is its line's
## number of cars (SERVICES): the numbered lines' (the A Division's) 15.5 m
## long and narrower, the lettered lines' 18.4 m; it shows one of its line's
## route bullets (picked when it appears) on its front and on every car's
## side signs, headlights at the front and red lights at the back, and its
## windows light up at night (shaders/train.gdshader).
##
## Trains appear out of sight (behind the camera or buildings, further than
## far_spawn, or coming out of a tunnel) within `radius` of the camera, at
## most max_trains of them, and go once they're past despawn_distance, have
## run off the end of the tracks into a tunnel, or their tiles unload. While
## the city first loads they appear anywhere, some standing at a platform.
##
## Every car is an instance of one MultiMesh (one draw call for all the
## trains) of PropMeshes.train_car() with shaders/train.gdshader, whose
## header has the instance layout. Trains move on physics ticks and are
## drawn between them, as heroes are, so a hero riding one stays put on its
## roof. Heroes within COLLISION_REACH of a train give its cars collision: a
## box per car on the trains' physics layer, moved with the car, carrying
## whoever stands on its roof (StaticBody3D.constant_linear_velocity).
## The nearest trains rumble and squeal on curves (GameAudio.set_trains).
## ?trains=N sets how many trains (0: none); Quality sets fewer on phones.

## Per line (the tiles' service numbers, tools/citygen/trains.py's
## SERVICES): its routes' bullets (a train shows one), its cars, and whether
## they're the A Division's (the numbered lines').
const SERVICES: Array[Dictionary] = [
	{},
	{routes = "7", cars = 11, a = true},   # Flushing
	{routes = "4", cars = 10, a = true},   # Jerome Avenue
	{routes = "25", cars = 10, a = true},  # White Plains Road
	{routes = "6", cars = 10, a = true},   # Pelham
	{routes = "1", cars = 10, a = true},   # Broadway-Seventh Avenue
	{routes = "3", cars = 10, a = true},   # New Lots (Eastern Parkway)
	{routes = "5", cars = 10, a = true},   # Dyre Avenue
	{routes = "JZ", cars = 8, a = false},  # Jamaica (Broadway, Brooklyn)
	{routes = "M", cars = 8, a = false},   # Myrtle Avenue
	{routes = "NW", cars = 10, a = false},  # Astoria
	{routes = "FG", cars = 10, a = false},  # Culver
	{routes = "D", cars = 10, a = false},  # West End
	{routes = "BQ", cars = 10, a = false},  # Brighton
	{routes = "N", cars = 10, a = false},  # Sea Beach
	{routes = "AS", cars = 8, a = false},  # Rockaway
	{routes = "A", cars = 10, a = false},  # Liberty Avenue
	{routes = "L", cars = 8, a = false},   # Canarsie
	{routes = "S", cars = 4, a = false},   # Franklin Avenue
]
## The route bullets' letters and numbers, in the order of the shader's
## glyph texture (_glyph_texture()), and their colors (sRGB, the MTA's).
const GLYPHS := "1234567ABDEFGJLMNQSWZ"
const BULLET_COLORS: Array[Color] = [
	Color(0.933, 0.208, 0.18), Color(0.933, 0.208, 0.18), Color(0.933, 0.208, 0.18),
	Color(0.0, 0.576, 0.235), Color(0.0, 0.576, 0.235), Color(0.0, 0.576, 0.235), Color(0.725, 0.2, 0.678),
	Color(0.0, 0.224, 0.651), Color(1.0, 0.388, 0.098), Color(1.0, 0.388, 0.098), Color(0.0, 0.224, 0.651),
	Color(1.0, 0.388, 0.098), Color(0.424, 0.745, 0.271), Color(0.6, 0.4, 0.2), Color(0.655, 0.663, 0.675),
	Color(1.0, 0.388, 0.098), Color(0.988, 0.8, 0.039), Color(0.988, 0.8, 0.039), Color(0.502, 0.506, 0.514),
	Color(0.988, 0.8, 0.039), Color(0.6, 0.4, 0.2)]
## Yellow bullets have black letters.
const DARK_GLYPHS := "NQW"
## Each glyph, 5 x 7 pixels, rows top to bottom.
const GLYPH_PIXELS := [
	"..#...##....#....#....#....#...###.", ".###.#...#....#...#...#...#...#####", "#####...#...#.....#.....##...#.###.",
	"...#...##..#.#.#..#.#####...#....#.", "######....####.....#....##...#.###.", "..##..#...#....####.#...##...#.###.",
	"#####....#...#...#...#....#....#...", ".###.#...##...#######...##...##...#", "####.#...##...#####.#...##...#####.",
	"###..#..#.#...##...##...##..#.###..", "######....#....####.#....#....#####", "######....#....####.#....#....#....",
	".###.#...##....#.####...##...#.####", "..###...#....#....#....#.#..#..##..", "#....#....#....#....#....#....#####",
	"#...###.###.#.##.#.##...##...##...#", "#...##...###..##.#.##..###...##...#", ".###.#...##...##...##.#.##..#..##.#",
	".#####....#.....###.....#....#####.", "#...##...##...##.#.##.#.##.#.#.#.#.", "#####....#...#...#...#...#....#####"]

## A car's length, width and height over the rails (m): the A Division's
## (like an R142) and the B Division's (an R160); the mesh is the B
## Division's. Cars stand this far apart.
const A_CAR := Vector3(15.55, 2.69, 3.6)
const B_CAR := Vector3(18.35, 3.05, 3.7)
const CAR_GAP := 0.9
const A_DOORS := 3
const B_DOORS := 4
const MAX_CARS := 11
## Instance flags (shaders/train.gdshader): a cab at the car's front (+z) or
## back, the front cab leading (its headlights on).
const CAB_FRONT := 1
const CAB_BACK := 2
const LEADING := 4

## Running (m/s, m/s^2): top speed, pulling away, braking for stops, curves
## and the train ahead, and for someone on the tracks.
const TOP_SPEED := 18.0
const ACCELERATION := 1.1
const BRAKING := 1.0
const HARD_BRAKING := 2.6
## How quickly speed follows what's wanted (1/s).
const SPEED_GAIN := 2.5
## Seconds standing at a platform; it's reached within STOP_REACH (m).
const DWELL := Vector2(20.0, 30.0)
const STOP_REACH := 1.0
## Stopping this far (m) behind the train ahead, or short of a junction a
## train is crossing, of someone on the tracks (within PERSON_SIDE of a
## track's middle, up to PERSON_HEIGHT over its rails) and of the end of the
## tracks.
const KEEP_BACK := 60.0
const JUNCTION_GAP := 25.0
const PERSON_GAP := 12.0
const PERSON_SIDE := 1.45
const PERSON_HEIGHT := 2.5
const END_GAP := 3.0
## Looking this far ahead of the front (m), every CONTROL_STEP seconds.
const LOOK_AHEAD := 250.0
const CONTROL_STEP := 0.2
## Past an open end (into a tunnel) the track goes on straight; cars this far
## past it are gone, and the train once all are.
const RUN_PAST := 25.0
## A train standing this long (s) out of sight, not at a platform, goes.
const STUCK_TIME := 90.0
## Trains appear at least this far from the camera (m), with at least
## SPAWN_AHEAD of track ahead of them (or a tunnel).
const MIN_SPAWN_DISTANCE := 120.0
const SPAWN_AHEAD := 200.0
## Spawn tries per upkeep: while the city first loads, and after.
const FILL_TRIES := 30
const TRIES := 4
const UPKEEP_INTERVAL := 0.5
## Heroes this close to a train (m) give its cars collision; it goes again
## past COLLISION_REACH + COLLISION_MARGIN. On physics layer 6, "trains"
## (the heroes collide with it; webs, cameras and thugs don't).
const COLLISION_REACH := 80.0
const COLLISION_MARGIN := 40.0
const COLLISION_LAYER := 32
## The cars' boxes start this high over the rails (m).
const BODY_FLOOR := 0.9
## Floats per instance in the MultiMesh buffer: a 3x4 transform, color, custom.
const STRIDE := 20
## Trains further than DRAW_MID (m) from the camera are drawn every other
## frame, further than DRAW_FAR every third, and those out of its view
## (further than DRAW_NEAR) every DRAW_UNSEEN frames.
const DRAW_MID := 150.0
const DRAW_FAR := 400.0
const DRAW_UNSEEN := 4
const DRAW_NEAR := 60.0
## How often the nearest trains go to the sounds (s).
const SOUND_INTERVAL := 0.1
const LOG_INTERVAL := 2.0

@export var city: CityStreamer
## How many trains at most (?trains=N), how far from the camera they appear
## and go (m), and past what distance they may appear in view.
@export var max_trains := 4
@export var radius := 1000.0
@export var despawn_distance := 1300.0
@export var far_spawn := 650.0

## The track graph.
var tracks := TrainTracks.new()
var trains: Array[Train] = []
## Script time per frame (ms, smoothed), and to add the last tile's tracks.
var update_msec := 0.0
var last_tile_msec := 0.0

var _multimesh: MultiMesh
var _instance: MultiMeshInstance3D
var _buffer := PackedFloat32Array()
## Train slots (each MAX_CARS instances); null where free.
var _slots: Array[Train] = []
## Junction nodes (where tracks merge) and the train crossing each.
var _claims := {}
# Where trains may appear: tiles near the camera and their running totals.
var _spawn_tiles: Array[Vector2i] = []
var _spawn_totals := PackedFloat32Array()
var _camera: Camera3D
var _focus := Vector3.ZERO
var _upkeep := 0.0
var _city_ready := false
var _sound_cooldown := 0.0
var _sound_points := PackedVector3Array()
var _sound_speeds := PackedFloat32Array()
var _sound_squeals := PackedFloat32Array()
var _free_bodies: Array[StaticBody3D] = []
var _car_shapes: Array[BoxShape3D] = []
var _people := PackedVector3Array()
var _near_people := PackedVector3Array()
var _drawn_origin := Vector3.ZERO
var _body_check := 0.0
# What _walk_cars found, per car (for their collision).
var _car_middle := PackedVector3Array()
var _car_forward := PackedVector3Array()
var _physics_since_frame := 0.0
## ?stats: each part's time (microseconds since the last line): the physics
## ticks' people, looking ahead, running and collision; the frames' upkeep,
## drawing and sounds; and how many frames and ticks.
var _part_usec := PackedInt64Array([0, 0, 0, 0, 0, 0, 0])
var _stat_frames := 0
var _stat_ticks := 0
var _log_stats := false
var _log_cooldown := 0.0


## A train: its cars, where it is on the tracks and how it's running.
class Train:
	## Its block of MAX_CARS instances (from slot * MAX_CARS) and its look.
	var slot := 0
	var service := 0
	var glyph := 0
	var cars := 10
	var car := B_CAR
	var doors := B_DOORS
	var a_division := false
	var length := 0.0
	## The pieces it's on, back to front, and their lengths but the last's
	## together; its front is `s` along the last (past its end only when it
	## runs off an open end).
	var pieces: Array[TrainTracks.Piece] = []
	var span := 0.0
	var s := 0.0
	var v := 0.0
	## How far it moved on the last physics tick (it's drawn between ticks).
	var step := 0.0
	## What _control found ahead: the speed to keep to, how far ahead it must
	## have stopped (INF: nowhere) and whether that's its stop at a platform
	## (that piece, how far along it), or someone on the tracks.
	var target := TOP_SPEED
	var stop_in := INF
	var stop_piece: TrainTracks.Piece
	var stop_at := 0.0
	var hard := false
	var control := 0.0
	## Seconds left standing at a platform, and the stop it stood at last.
	var dwell := 0.0
	var served: TrainTracks.Piece
	var served_at := 0.0
	var stuck := 0.0
	## Junction nodes it has claimed.
	var claims: Array[int] = []
	## Its cars' collision (while heroes are near), and their headings at
	## the last tick (for turning rates).
	var bodies: Array[StaticBody3D] = []
	var headings := PackedVector3Array()
	## Its front and back (world) as last drawn, and how sharply the track
	## under it curves (0..1), for the sounds.
	var head := Vector3.ZERO
	var tail := Vector3.ZERO
	var squeal := 0.0
	## Drawn standing still (its cars needn't be written again until it moves).
	var at_rest := false
	var drawn := false


func _ready() -> void:
	if LaunchOptions.has("trains"):
		max_trains = maxi(int(LaunchOptions.get_string("trains")), 0)
	_log_stats = LaunchOptions.has("stats")
	_slots.resize(max_trains)
	_car_middle.resize(MAX_CARS)
	_car_forward.resize(MAX_CARS)
	_buffer.resize(max_trains * MAX_CARS * STRIDE)
	_buffer.fill(0.0)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = PropMeshes.train_car()
	_multimesh.instance_count = max_trains * MAX_CARS
	_multimesh.visible_instance_count = 0
	if max_trains > 0:
		_multimesh.buffer = _buffer
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Cars"
	_instance.multimesh = _multimesh
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/train.gdshader")
	material.set_shader_parameter("glyphs", _glyph_texture())
	material.set_shader_parameter("glyph_count", float(GLYPHS.length()))
	_instance.material_override = material
	# The el's deck shades the street; the cars cast no shadows of their own.
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cars are written in scene space around the camera wherever the origin
	# is, so the box only needs to hold the whole area that can be drawn.
	_instance.custom_aabb = AABB(Vector3(-4000.0, -200.0, -4000.0), Vector3(8000.0, 1400.0, 8000.0))
	_instance.visible = max_trains > 0
	add_child(_instance)
	for car: Vector3 in [A_CAR, B_CAR]:
		var box := BoxShape3D.new()
		box.size = Vector3(car.y, car.z - BODY_FLOOR, car.x)
		_car_shapes.append(box)
	if city and max_trains > 0:
		city.train_tracks_changed.connect(set_tile_tracks)
		city.initial_load_finished.connect(func(_seconds: float) -> void: _city_ready = true)
		var loaded := city.train_tracks()
		for key: Vector2i in loaded:
			set_tile_tracks(key, loaded[key])
	set_process(max_trains > 0)
	set_physics_process(max_trains > 0)


## A tile's tracks arrived, or went (empty): trains on tracks that went go too.
func set_tile_tracks(key: Vector2i, tile_tracks: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var removed := tracks.set_tile(key, tile_tracks)
	last_tile_msec = (Time.get_ticks_usec() - started) / 1000.0
	if removed.is_empty():
		return
	for train: Train in trains.duplicate():
		for piece in train.pieces:
			if piece.removed:
				_despawn(train)
				break


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	var looking := false
	for train in trains:
		train.control -= delta
		looking = looking or train.control <= 0.0
	if looking:
		_find_people()
	var mark := _time_part(0, started)
	if looking:
		for train in trains:
			if train.control <= 0.0:
				train.control = CONTROL_STEP
				_control(train)
	mark = _time_part(1, mark)
	for train in trains:
		_run(train, delta)
	mark = _time_part(2, mark)
	_update_bodies(delta)
	_time_part(3, mark)
	var spent := (Time.get_ticks_usec() - started) / 1000.0
	_physics_since_frame += spent
	_stat_ticks += 1


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_camera = get_viewport().get_camera_3d()
	if _camera:
		_focus = WorldOrigin.to_world(_camera.global_position)
	_upkeep -= delta
	if _upkeep <= 0.0:
		_upkeep = UPKEEP_INTERVAL
		_clear_away()
		_refresh_spawn_tiles()
		if _camera:
			_spawn(FILL_TRIES if not _city_ready else TRIES)
	var mark := _time_part(4, started)
	_draw()
	mark = _time_part(5, mark)
	_sound_cooldown -= delta
	if _sound_cooldown <= 0.0:
		_sound_cooldown = SOUND_INTERVAL
		_send_sounds()
	_time_part(6, mark)
	# Per frame: drawing here and the physics ticks' running since the last frame.
	update_msec = lerpf(update_msec, (Time.get_ticks_usec() - started) / 1000.0 + _physics_since_frame, 0.05)
	_physics_since_frame = 0.0
	_stat_frames += 1
	if _log_stats:
		_log_cooldown -= delta
		if _log_cooldown <= 0.0:
			_log_cooldown = LOG_INTERVAL
			_log_stats_line()


## The ?stats line: trains, the nearest one, and the script's time (averaged
## since the last line): a frame's, a physics tick's, and their parts.
func _log_stats_line() -> void:
	var bodies := 0
	var nearest := INF
	var speed := 0.0
	for train in trains:
		bodies += train.bodies.size()
		var gap := Geometry3D.get_closest_point_to_segment(_focus, train.head, train.tail).distance_to(_focus)
		if gap < nearest:
			nearest = gap
			speed = train.v
	var frames := maxf(_stat_frames, 1.0)
	var ticks := maxf(_stat_ticks, 1.0)
	var tick := 0.0
	var own := 0.0
	for part in _part_usec.size():
		if part < 4:
			tick += _part_usec[part]
		else:
			own += _part_usec[part]
	print("[trains] %d trains (%d cars with collision), the nearest %.0f m off at %.1f m/s; %.3f ms a frame (%d frames, %d physics ticks); a physics tick %.3f: people %.3f, looking ahead %.3f, running %.3f, collision %.3f; a frame's own %.3f: spawning %.3f, drawing %.3f, sounds %.3f; %d tiles of track, the last one's %.2f ms" % [
		trains.size(), bodies, nearest, speed, (tick + own) / frames / 1000.0, frames, ticks, tick / ticks / 1000.0,
		_part_usec[0] / ticks / 1000.0, _part_usec[1] / ticks / 1000.0, _part_usec[2] / ticks / 1000.0,
		_part_usec[3] / ticks / 1000.0, own / frames / 1000.0, _part_usec[4] / frames / 1000.0,
		_part_usec[5] / frames / 1000.0, _part_usec[6] / frames / 1000.0, tracks.tiles.size(), last_tile_msec])
	_part_usec.fill(0)
	_stat_frames = 0
	_stat_ticks = 0


## Times a part of the update (for ?stats), from `since` to now; returns now.
func _time_part(part: int, since: int) -> int:
	if not _log_stats:
		return since
	var now := Time.get_ticks_usec()
	_part_usec[part] += now - since
	return now


## What's ahead of a train, from its back to LOOK_AHEAD past its front: the
## speed limits of the curves under it and coming up (braking for them in
## time), its next stop, the train ahead, a junction another train is
## crossing, someone on the tracks, the end of the tracks. Sets its target,
## stop_in and what it stops for.
func _control(train: Train) -> void:
	var limit := TOP_SPEED
	var stop_in := INF
	var stop_piece: TrainTracks.Piece = null
	var stop_at := 0.0
	var hard := false
	var curve := TOP_SPEED
	# Who's up on the el near its front, ahead of it.
	_near_people.clear()
	for person in _people:
		if absf(person.y - train.head.y) < PERSON_HEIGHT + 4.0 \
				and Vector2(person.x - train.head.x, person.z - train.head.z).length() < LOOK_AHEAD + 20.0:
			_near_people.append(person)
	# `offset`: where the piece starts, measured from the train's front.
	var offset := -(train.span + train.s)
	var index := 0
	var piece := train.pieces[0]
	while true:
		var end := offset + piece.length
		# Curves: under the train its own limit, ahead what it must slow to
		# by then.
		for k in piece.points.size():
			var x := offset + piece.along[k]
			if x < -train.length and k + 1 < piece.points.size() and offset + piece.along[k + 1] < -train.length:
				continue
			if x > LOOK_AHEAD:
				break
			var allowed := piece.speeds[k]
			if x <= 0.0:
				curve = minf(curve, allowed)
			else:
				allowed = sqrt(allowed * allowed + 2.0 * BRAKING * x)
			limit = minf(limit, allowed)
		# Its stops: the train's middle at the platform's middle.
		for d in piece.stops:
			var x := offset + d + train.length * 0.5
			if x < -STOP_REACH or x >= stop_in or (piece == train.served and absf(d - train.served_at) < 1.0):
				continue
			if x > STOP_REACH and train.v * train.v > 2.0 * BRAKING * 1.5 * x:
				continue  # too late to stop there: it runs through
			stop_in = x
			stop_piece = piece
			stop_at = d
		# The train ahead: its back.
		for other in trains:
			if other == train or not other.pieces.has(piece):
				continue
			var back := offset + (other.span + other.s - other.length if other.pieces[0] == piece else 0.0)
			if back > 0.0 and back - KEEP_BACK < stop_in:
				stop_in = back - KEEP_BACK
				stop_piece = null
		# Someone on the tracks.
		if not _near_people.is_empty() and end > 0.0 and offset < LOOK_AHEAD:
			var found := _person_on(piece, offset)
			if found - PERSON_GAP < stop_in:
				stop_in = found - PERSON_GAP
				stop_piece = null
				hard = true
		if end > LOOK_AHEAD:
			break
		var next: TrainTracks.Piece = train.pieces[index + 1] if index + 1 < train.pieces.size() \
				else tracks.next(piece, train.service)
		if next == null:
			if piece.flags & CityTileDecoder.TRACK_OPEN_END == 0 and end - END_GAP < stop_in:
				stop_in = end - END_GAP  # the end of the tracks (or of what's loaded)
				stop_piece = null
			break
		# Where tracks merge, one train at a time.
		if end > 0.0 and tracks.arriving(piece.to_node).size() > 1:
			var holder: Train = _claims.get(piece.to_node)
			if holder != null and holder != train:
				if end - JUNCTION_GAP < stop_in:
					stop_in = end - JUNCTION_GAP
					stop_piece = null
				break
			if holder == null and end < train.v * train.v / (2.0 * BRAKING) + JUNCTION_GAP * 2.0:
				_claims[piece.to_node] = train
				train.claims.append(piece.to_node)
		offset = end
		piece = next
		index += 1
	train.target = limit
	train.stop_in = stop_in
	train.stop_piece = stop_piece
	train.stop_at = stop_at
	train.hard = hard
	train.squeal = clampf((12.0 - curve) / 6.0, 0.0, 1.0)


## How far ahead of a train's front someone stands on `piece` (which starts
## `offset` from the front), or INF.
func _person_on(piece: TrainTracks.Piece, offset: float) -> float:
	var nearest := INF
	for person in _near_people:
		for k in piece.points.size() - 1:
			var a := piece.points[k]
			var b := piece.points[k + 1]
			var ab := b - a
			var t := clampf((person - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var on := a + ab * t
			var rise := person.y - on.y
			if Vector2(person.x - on.x, person.z - on.z).length() < PERSON_SIDE and rise > -1.0 and rise < PERSON_HEIGHT:
				var x := offset + lerpf(piece.along[k], piece.along[k + 1], t)
				if x > 0.0:
					nearest = minf(nearest, x)
	return nearest


## A physics tick of a train's running: speeding up or braking toward what
## _control wants, standing at platforms, moving on along the tracks.
func _run(train: Train, dt: float) -> void:
	train.step = 0.0
	if train.dwell > 0.0:
		train.dwell -= dt
		return
	var target := train.target
	var braking := HARD_BRAKING if train.hard else BRAKING
	if train.stop_in < INF:
		target = minf(target, sqrt(2.0 * braking * maxf(train.stop_in, 0.0)))
	var a := clampf((target - train.v) * SPEED_GAIN, -braking * 1.5, ACCELERATION)
	if train.stop_in < INF:
		# Braking evenly to stand just there, once it's time to.
		var needed := train.v * train.v / (2.0 * maxf(train.stop_in, 0.01))
		if train.stop_in <= 0.0:
			needed = HARD_BRAKING * 2.0
		if needed > braking * 0.7:
			a = minf(a, -needed)
	var v := maxf(train.v + a * dt, 0.0)
	train.step = (train.v + v) * 0.5 * dt
	train.v = v
	train.s += train.step
	train.stop_in -= train.step
	if train.stop_piece and train.stop_in < STOP_REACH and v < 0.3:
		# At the platform: doors open.
		train.v = 0.0
		train.dwell = randf_range(DWELL.x, DWELL.y)
		train.served = train.stop_piece
		train.served_at = train.stop_at
		train.stop_piece = null
		train.stop_in = INF
	_advance(train)


## Moves a train's front on to the next piece once past its end, and lets
## go of the pieces (and junctions) its back has left.
func _advance(train: Train) -> void:
	var front := train.pieces[train.pieces.size() - 1]
	while train.s > front.length:
		var next := tracks.next(front, train.service)
		if next == null:
			if front.flags & CityTileDecoder.TRACK_OPEN_END == 0:
				# The end of the tracks (or of those loaded): no further.
				train.s = front.length
				train.v = 0.0
			break  # (else running off into a tunnel)
		train.s -= front.length
		train.span += front.length
		train.pieces.append(next)
		front = next
	while train.pieces.size() > 1 and train.span + train.s - train.pieces[0].length > train.length:
		var gone: TrainTracks.Piece = train.pieces.pop_front()
		train.span -= gone.length
		_release(train, gone.to_node)


func _release(train: Train, node: int) -> void:
	if _claims.get(node) == train:
		_claims.erase(node)
	train.claims.erase(node)


## Writes each car's place into the instance buffer, between physics ticks.
func _draw() -> void:
	if trains.is_empty() and _multimesh.visible_instance_count == 0:
		return
	var origin := WorldOrigin.offset
	var moved_origin := origin != _drawn_origin
	_drawn_origin = origin
	var between := 1.0 - Engine.get_physics_interpolation_fraction()
	var frame := Engine.get_process_frames()
	var highest := -1
	for train in trains:
		highest = maxi(highest, train.slot)
		if train.drawn and not moved_origin:
			if train.step == 0.0 and train.at_rest:
				continue  # standing where it was drawn
			# Out of view (and not right by the camera) or far off, not every frame.
			if (frame + train.slot) % DRAW_UNSEEN != 0 and not _in_view(train):
				continue
			var distance := minf(_flat_distance(train.head), _flat_distance(train.tail))
			if (distance > DRAW_FAR and (frame + train.slot) % 3 != 0) \
					or (distance > DRAW_MID and (frame + train.slot) % 2 != 0):
				continue
		train.at_rest = train.step == 0.0
		train.drawn = true
		_place_cars(train, train.step * between, origin)
	_multimesh.visible_instance_count = (highest + 1) * MAX_CARS
	_multimesh.buffer = _buffer


## Puts a train's cars where they are `behind` meters back from its front,
## in scene space (the origin at `origin`): each one's middle and heading
## (the shader turns it; see its header); cars past an open end, or not yet
## out of a tunnel, are scaled to nothing.
func _place_cars(train: Train, behind: float, origin: Vector3) -> void:
	_walk_cars(train, behind, origin, train.slot * MAX_CARS * STRIDE)


## Whether any of a train might be on screen: its ends or middle in the
## camera's view, or the camera close by.
func _in_view(train: Train) -> bool:
	if _camera == null:
		return true
	var head := WorldOrigin.to_local(train.head)
	var tail := WorldOrigin.to_local(train.tail)
	var camera := _camera.global_position
	return _camera.is_position_in_frustum(head) or _camera.is_position_in_frustum(tail) \
			or _camera.is_position_in_frustum((head + tail) * 0.5) \
			or Geometry3D.get_closest_point_to_segment(camera, head, tail).distance_to(camera) < DRAW_NEAR


## Where a train's cars are, `behind` meters back from its front: each car's
## middle (on the tracks; world) and heading (the tracks' there, tilted with
## their grade), into _car_middle and _car_forward; or, from buffer index
## `b` on, into the instance buffer (scene space, the origin at `origin`;
## cars past an open end, or not yet out of a tunnel, as none). Sets the
## train's head and tail.
func _walk_cars(train: Train, behind: float, origin := Vector3.ZERO, b := -1) -> void:
	var stretch := train.car.x / B_CAR.x
	var pitch := train.car.x + CAR_GAP
	var pieces := train.pieces
	var last := pieces.size() - 1
	var index := last
	var piece := pieces[last]
	var start := train.span  # where `piece` starts, from the start of the first
	var x := train.span + train.s - behind - train.car.x * 0.5  # the first car's middle
	for k in train.cars:
		while index > 0 and x < start:
			index -= 1
			piece = pieces[index]
			start -= piece.length
		var d := x - start
		var middle: Vector3
		var forward: Vector3
		if d <= 0.0 or d >= piece.length:
			# Before its start or past its end: straight on.
			middle = piece.point_at(d)
			forward = piece.start_direction if d <= 0.0 else piece.end_direction
		else:
			var along := piece.along
			var i := clampi(along.bsearch(d) - 1, 0, along.size() - 2)
			var t := (d - along[i]) / maxf(along[i + 1] - along[i], 0.0001)
			middle = piece.points[i].lerp(piece.points[i + 1], t)
			forward = piece.tangents[i].lerp(piece.tangents[i + 1], t).normalized()
		if b < 0:
			_car_middle[k] = middle
			_car_forward[k] = forward
		else:
			var gone := (index == last and d > piece.length and piece.flags & CityTileDecoder.TRACK_OPEN_END != 0) \
					or (index == 0 and d < 0.0 and piece.flags & CityTileDecoder.TRACK_OPEN_START != 0)
			var heading := forward * (0.0 if gone else stretch)
			var at := middle - origin
			_buffer[b + 2] = heading.x
			_buffer[b + 3] = at.x
			_buffer[b + 6] = heading.y
			_buffer[b + 7] = at.y
			_buffer[b + 10] = heading.z
			_buffer[b + 11] = at.z
			b += STRIDE
		if k == 0:
			train.head = middle + forward * (train.car.x * 0.5)
		if k == train.cars - 1:
			train.tail = middle - forward * (train.car.x * 0.5)
		x -= pitch


## Heroes near trains give the cars collision (a box each, moved with the
## car every tick, carrying whoever stands on it); trains no hero is near
## give theirs back.
func _update_bodies(delta: float) -> void:
	_body_check -= delta
	var checking := _body_check <= 0.0
	if checking:
		_body_check = CONTROL_STEP
	for train in trains:
		if checking:
			var near := INF
			var along := train.head - train.tail
			for hero in Combat.heroes:
				if hero.is_remote():
					continue
				var at := hero.world_position()
				var t := clampf((at - train.tail).dot(along) / maxf(along.length_squared(), 1.0), 0.0, 1.0)
				near = minf(near, at.distance_to(train.tail + along * t))
			if train.bodies.is_empty() and near < COLLISION_REACH:
				_take_bodies(train)
			elif not train.bodies.is_empty() and near > COLLISION_REACH + COLLISION_MARGIN:
				_give_bodies(train)
		if not train.bodies.is_empty():
			_place_bodies(train, delta)


func _take_bodies(train: Train) -> void:
	for k in train.cars:
		var body: StaticBody3D = _free_bodies.pop_back() if not _free_bodies.is_empty() else null
		if body == null:
			body = StaticBody3D.new()
			body.collision_layer = COLLISION_LAYER
			body.collision_mask = 0
			body.add_to_group("floating")
			var shape := CollisionShape3D.new()
			body.add_child(shape)
			add_child(body)
		var box: CollisionShape3D = body.get_child(0)
		box.shape = _car_shapes[0 if train.a_division else 1]
		box.position = Vector3(0.0, BODY_FLOOR + (train.car.z - BODY_FLOOR) * 0.5, 0.0)
		body.process_mode = Node.PROCESS_MODE_INHERIT
		train.bodies.append(body)
	train.headings.resize(train.cars)
	train.headings.fill(Vector3.ZERO)


func _give_bodies(train: Train) -> void:
	for body in train.bodies:
		body.constant_linear_velocity = Vector3.ZERO
		body.constant_angular_velocity = Vector3.ZERO
		body.global_position = Vector3(0.0, -1000.0, 0.0)
		_free_bodies.append(body)
	train.bodies.clear()


## Moves a train's boxes to its cars (at this tick), with their velocities.
func _place_bodies(train: Train, delta: float) -> void:
	_walk_cars(train, 0.0)
	for k in train.cars:
		var forward := _car_forward[k]
		var left := Vector3.UP.cross(forward).normalized()
		var body := train.bodies[k]
		body.global_transform = Transform3D(Basis(left, forward.cross(left), forward), WorldOrigin.to_local(_car_middle[k]))
		body.constant_linear_velocity = forward * train.v
		var last := train.headings[k]
		var turn := 0.0
		if last != Vector3.ZERO and delta > 0.0:
			turn = Vector2(last.x, last.z).angle_to(Vector2(forward.x, forward.z)) / delta
		body.constant_angular_velocity = Vector3(0.0, -turn, 0.0)
		train.headings[k] = forward


## Where people are whom trains stop for: heroes and thugs (world).
func _find_people() -> void:
	_people.clear()
	for hero in Combat.heroes:
		_people.append(hero.world_position())
	for thug in Combat.thugs:
		_people.append(WorldOrigin.to_world(thug.ground_position()))


## Trains too far away, run off into a tunnel, or stuck for good out of
## sight, go.
func _clear_away() -> void:
	for train: Train in trains.duplicate():
		var front := train.pieces[train.pieces.size() - 1]
		if train.s - train.length > front.length + RUN_PAST:
			_despawn(train)  # all of it in the tunnel
			continue
		var distance := minf(_flat_distance(train.head), _flat_distance(train.tail))
		if distance > despawn_distance:
			_despawn(train)
			continue
		if train.v < 0.1 and train.dwell <= 0.0:
			train.stuck += UPKEEP_INTERVAL
			if train.stuck > STUCK_TIME and _unseen(train.head) and _unseen(train.tail):
				_despawn(train)
		else:
			train.stuck = 0.0


func _flat_distance(world: Vector3) -> float:
	return Vector2(world.x - _focus.x, world.z - _focus.z).length()


## The tiles whose running tracks reach within `radius` of the camera.
func _refresh_spawn_tiles() -> void:
	_spawn_tiles.clear()
	_spawn_totals.clear()
	var total := 0.0
	var focus := Vector2(_focus.x, _focus.z)
	for key: Vector2i in tracks.tile_mains:
		var bounds: Rect2 = tracks.tile_bounds[key]
		if focus.clamp(bounds.position, bounds.end).distance_to(focus) < radius:
			var totals: PackedFloat32Array = tracks.tile_mains[key][1]
			total += totals[totals.size() - 1]
			_spawn_tiles.append(key)
			_spawn_totals.append(total)


## Tries a few spots on the running tracks near the camera for new trains:
## out of sight, or far off. While the city first loads, anywhere, some at a
## platform.
func _spawn(tries: int) -> void:
	if _spawn_tiles.is_empty():
		return
	var total := _spawn_totals[_spawn_totals.size() - 1]
	for attempt in tries:
		var slot := _slots.find(null)
		if slot < 0:
			return
		var tile := _spawn_tiles[mini(_spawn_totals.bsearch(randf() * total), _spawn_tiles.size() - 1)]
		var mains: Array = tracks.tile_mains[tile][0]
		var totals: PackedFloat32Array = tracks.tile_mains[tile][1]
		var piece: TrainTracks.Piece = mains[mini(totals.bsearch(randf() * totals[totals.size() - 1]), mains.size() - 1)]
		var info: Dictionary = SERVICES[piece.service] if piece.service < SERVICES.size() else {}
		if info.is_empty():
			continue
		var train := Train.new()
		train.service = piece.service
		var routes: String = info.routes
		train.glyph = GLYPHS.find(routes[randi() % routes.length()])
		train.a_division = info.a
		train.cars = info.cars
		train.car = A_CAR if train.a_division else B_CAR
		train.doors = A_DOORS if train.a_division else B_DOORS
		train.length = train.cars * train.car.x + (train.cars - 1) * CAR_GAP
		# Its front somewhere on the piece; at first, maybe its middle at a
		# platform, standing there.
		var s := randf() * piece.length
		var at_platform := not _city_ready and not piece.stops.is_empty() and randf() < 0.6
		if at_platform:
			s = piece.stops[randi() % piece.stops.size()]
			train.served = piece
			train.served_at = s
			if not _lay_out(train, piece, s + train.length * 0.5):
				continue
			train.dwell = randf_range(0.0, DWELL.y)
		elif not _lay_out(train, piece, s) or _track_ahead(train) < SPAWN_AHEAD:
			continue
		if _occupied(train):
			continue
		var front := train.span + train.s
		train.head = _point(train, front)
		train.tail = _point(train, front - train.length)
		var middle := _point(train, front - train.length * 0.5)
		var distance := minf(_flat_distance(train.head), _flat_distance(train.tail))
		if distance > radius or (distance < MIN_SPAWN_DISTANCE and _city_ready):
			continue
		if _city_ready and not (_unseen(train.head) and _unseen(middle) and _unseen(train.tail)):
			continue
		_add(train, slot)


## Places a train with its front `s` along `piece` (going on ahead past its
## end, to the pieces that follow), its back on the pieces before: false if
## the tracks don't reach that far (unless they come out of a tunnel).
func _lay_out(train: Train, piece: TrainTracks.Piece, s: float) -> bool:
	while s > piece.length:
		var next := tracks.next(piece, train.service)
		if next == null:
			return false
		s -= piece.length
		piece = next
	train.pieces = [piece]
	train.s = s
	train.span = 0.0
	var reach := s
	while reach < train.length:
		var before := tracks.previous(train.pieces[0], train.service)
		if before == null or train.pieces.has(before):
			return train.pieces[0].flags & CityTileDecoder.TRACK_OPEN_START != 0
		train.pieces.push_front(before)
		train.span += before.length
		reach += before.length
	return true


## How far the tracks go on ahead of a train's front (up to SPAWN_AHEAD;
## INF if they go into a tunnel before that).
func _track_ahead(train: Train) -> float:
	var piece := train.pieces[train.pieces.size() - 1]
	var ahead := piece.length - train.s
	while ahead < SPAWN_AHEAD:
		var next := tracks.next(piece, train.service)
		if next == null:
			return INF if piece.flags & CityTileDecoder.TRACK_OPEN_END != 0 else ahead
		piece = next
		ahead += piece.length
	return ahead


## The point `x` along a train's pieces, measured from the start of its first.
func _point(train: Train, x: float) -> Vector3:
	var start := 0.0
	for piece in train.pieces:
		if x < start + piece.length or piece == train.pieces[train.pieces.size() - 1]:
			return piece.point_at(x - start)
		start += piece.length
	return Vector3.ZERO


## Whether another train is on a train's pieces or close ahead of it.
func _occupied(train: Train) -> bool:
	var near: Array[TrainTracks.Piece] = train.pieces.duplicate()
	var ahead := train.pieces[train.pieces.size() - 1]
	var reach := ahead.length - train.s
	while reach < KEEP_BACK * 3.0:
		ahead = tracks.next(ahead, train.service)
		if ahead == null:
			break
		near.append(ahead)
		reach += ahead.length
	for other in trains:
		for piece in other.pieces:
			if near.has(piece):
				return true
	return false


## Out of the camera's sight: far off, outside its view, or behind a building.
func _unseen(world_point: Vector3) -> bool:
	if _camera == null or _flat_distance(world_point) > far_spawn:
		return true
	var target := WorldOrigin.to_local(world_point) + Vector3.UP * 2.0
	if not _camera.is_position_in_frustum(target):
		return true
	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target, CityStreamer.COLLISION_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and from.distance_to(hit.position) < from.distance_to(target) - 3.0


func _add(train: Train, slot: int) -> void:
	train.slot = slot
	_slots[slot] = train
	trains.append(train)
	var front := train.pieces[train.pieces.size() - 1]
	train.v = 0.0 if train.dwell > 0.0 else minf(TOP_SPEED * 0.6, front.speed_at(train.s))
	train.control = randf() * CONTROL_STEP  # (trains look ahead at different ticks)
	# Each car's look: cabs at the train's ends, its route's bullet.
	var color := BULLET_COLORS[train.glyph]
	var dark := 1.0 if DARK_GLYPHS.contains(GLYPHS[train.glyph]) else 0.0
	var b := slot * MAX_CARS * STRIDE
	for k in MAX_CARS:
		for n in STRIDE:
			_buffer[b + n] = 0.0
		if k < train.cars:
			var flags := 0
			if k == 0:
				flags |= CAB_FRONT | LEADING
			if k == train.cars - 1:
				flags |= CAB_BACK
			_buffer[b] = train.car.y / B_CAR.y
			_buffer[b + 5] = train.car.z / B_CAR.z
			_buffer[b + 12] = color.r
			_buffer[b + 13] = color.g
			_buffer[b + 14] = color.b
			_buffer[b + 15] = dark
			_buffer[b + 16] = flags
			_buffer[b + 17] = train.glyph
			_buffer[b + 18] = randi_range(0, 1023) / 1024.0
			_buffer[b + 19] = train.doors
		b += STRIDE
	_place_cars(train, 0.0, WorldOrigin.offset)
	train.drawn = true
	train.at_rest = false


func _despawn(train: Train) -> void:
	if not trains.has(train):
		return
	trains.erase(train)
	_slots[train.slot] = null
	for node in train.claims.duplicate():
		_release(train, node)
	_give_bodies(train)
	var b := train.slot * MAX_CARS * STRIDE
	for n in MAX_CARS * STRIDE:
		_buffer[b + n] = 0.0
	_multimesh.buffer = _buffer


## The nearest point of each train to the listener, its speed and how much
## its wheels squeal (tight curves, braking slowly into a stop), for the
## sounds.
func _send_sounds() -> void:
	_sound_points.clear()
	_sound_speeds.clear()
	_sound_squeals.clear()
	var listener := WorldOrigin.to_world(GameAudio.listener())
	for train in trains:
		var along := train.head - train.tail
		var t := clampf((listener - train.tail).dot(along) / maxf(along.length_squared(), 1.0), 0.0, 1.0)
		_sound_points.append(train.tail + along * t)
		_sound_speeds.append(train.v)
		var braking := 1.0 if train.stop_in < 40.0 and train.v > 1.0 and train.v < 7.0 else 0.0
		_sound_squeals.append(maxf(train.squeal * smoothstep(2.0, 6.0, train.v), braking * 0.6))
	GameAudio.set_trains(_sound_points, _sound_speeds, _sound_squeals)


## The route bullets' letters and numbers (GLYPH_PIXELS) side by side, each
## in a 7 x 9 cell (a pixel's border), white on black, for the shader.
static func _glyph_texture() -> ImageTexture:
	var image := Image.create(GLYPHS.length() * 7, 9, false, Image.FORMAT_R8)
	for g in GLYPHS.length():
		var pixels: String = GLYPH_PIXELS[g]
		for row in 7:
			for column in 5:
				if pixels[row * 5 + column] == "#":
					image.set_pixel(g * 7 + 1 + column, 1 + row, Color.WHITE)
	return ImageTexture.create_from_image(image)
