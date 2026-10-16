extends Node
## Headless check of the trains on the els: loads the city around the 7 over
## Roosevelt Avenue at 74th Street at 15:30 (the evening rush: the 7's
## express track runs away from Manhattan, and only that way), puts an
## express train on it, lets the trains run for a while and checks every
## frame that trains on the same tracks never overlap, that none runs faster
## than its track allows, that they move, and that each train that stops at
## a platform stands with its middle at the platform's middle. Then stands
## the hero on the tracks ahead of a moving train (it must stop short), drops
## the hero onto a moving train's roof (the hero must ride along on it),
## moves the camera to the 4 on Jerome Avenue until Queens unloads (no train
## may be left on unloaded tracks, and trains must run there), and on to the
## 4's terminal at Woodlawn: a train put on the track into it must stop at
## the bumper, go back out over the switch onto the other track, and no
## other train may be on the terminal's track meanwhile.
## --tiles=DIR (see CityStreamer) runs it on a copy of the tiles, which must
## have the trains surface around all three places. With TRAINS_TERMINAL_ONLY
## set in the environment it goes straight from loading to Woodlawn.
## Run: godot --headless --path . res://tests/trains_test.tscn -- --tiles=DIR

## Roosevelt Avenue at 74th Street, over the el, Jerome Avenue at about
## Burnside Avenue, and Woodlawn, the 4's terminal (world meters).
const ROOSEVELT := Vector3(7990.0, 40.0, 1220.0)
const JEROME := Vector3(5750.0, 40.0, -9250.0)
const WOODLAWN := Vector3(9000.0, 80.0, -14200.0)
const LOAD_WAIT := 120.0
const RUN_TIME := 120.0
const PERSON_TIME := 60.0
const BOARD_WAIT := 60.0
const RIDE_TIME := 8.0
const AWAY_TIME := 45.0
const TERMINAL_WAIT := 120.0
const TERMINAL_TIME := 360.0
## The train at the terminal starts this far before the bumper (m).
const TERMINAL_START := 350.0
## Where the hero stands ahead of a train (m along the tracks).
const PERSON_AHEAD := 100.0

var _world: Game
var _city: CityStreamer
var _trains: Trains
var _camera: FreeFlyCamera
var _hero: Hero
var _phase := "load"
var _time := 0.0
var _problems := 0
var _stats := {}
## Per train: whether it stood at a platform last frame.
var _dwelling := {}
## The train the hero stands in front of or rides, and how far ahead of its
## front the hero stands (along the tracks; updated as it moves).
var _subject: Trains.Train
var _person_piece: TrainTracks.Piece
var _person_at := 0.0
var _closest := INF
var _stood_near := false
var _ride_start := Vector3.ZERO
## The express train, how far it ran and where it stopped.
var _express: Trains.Train
var _express_run := 0.0
var _express_stops := 0
## At the terminal: its bumper's node, and what the train did (stood at the
## bumper, turned back, came out onto the other track), and how often
## another train was on the terminal's track while it was.
var _bumper := 0
var _at_bumper := false
var _turned := false
var _out := false
var _shared := 0


func _ready() -> void:
	# After the trains have moved and been drawn this frame.
	process_priority = 100
	LaunchOptions.set_default("time", "15:30")
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	_world = world
	for node_name in ["PlayerInput", "Crowd", "Encounters", "Traffic"]:
		world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_city = world.get_node("City")
	_trains = world.get_node("Trains")
	_hero = world.get_node("Hero")
	_camera = world.get_node("FreeCamera")
	world.use_free_camera(true)
	_camera.set_process(false)
	_camera.global_position = WorldOrigin.to_local(ROOSEVELT)
	_camera.rotation = Vector3(-0.1, deg_to_rad(100.0), 0.0)
	_park_hero()
	for key in ["overlaps", "overspeed", "curve_overspeed", "distance", "train_seconds", "max_trains", "stops",
			"misaligned", "removed"]:
		_stats[key] = 0.0


func _process(delta: float) -> void:
	_time += delta
	match _phase:
		"load":
			if (_city.pending_count() == 0 and _trains.trains.size() >= 2) or _time > LOAD_WAIT:
				print("loaded in %.1f s: %d trains on %d tiles' tracks" % [_time, _trains.trains.size(), _trains.tracks.tiles.size()])
				if _trains.trains.is_empty():
					_fail("no trains on the 7")
					_finish()
					return
				_place_express()
				_next("run")
				if OS.has_environment("TRAINS_TERMINAL_ONLY"):
					_camera.global_position = WorldOrigin.to_local(WOODLAWN)
					_next("terminal_load")
		"run":
			_check_frame(delta)
			if OS.has_environment("TRAINS_DEBUG") and fmod(_time, 10.0) < delta:
				for train in _trains.trains:
					var front := train.pieces[train.pieces.size() - 1]
					print("  train %d: v %.1f target %.1f stop_in %.1f stop %s dwell %.1f, front %.0f/%.0f flags %d next %s, %d pieces, stops ahead %s, at %s" % [
						train.slot, train.v, train.target, train.stop_in, train.stop_piece != null, train.dwell, train.s,
						front.length, front.flags, _trains.tracks.next(front, train.service) != null, train.pieces.size(),
						front.stops, train.head.round()])
			if _time > RUN_TIME:
				_report_run()
				_next("place")
		"place":
			# (Once a train is running near the camera.)
			_check_frame(delta)
			if _place_person():
				_next("person")
			elif _time > BOARD_WAIT:
				_fail("no train to stand in front of")
				_next("person")
		"person":
			_check_frame(delta)
			_check_person()
			if _time > PERSON_TIME:
				_report_person()
				_park_hero()
				_next("board")
		"board":
			# (Once a train is running near the camera.)
			_check_frame(delta)
			if _board():
				_next("ride")
			elif _time > BOARD_WAIT:
				_fail("no moving train to board")
				_next("ride")
		"ride":
			_check_frame(delta)
			if _time > RIDE_TIME:
				_report_ride()
				_park_hero()
				_camera.global_position = WorldOrigin.to_local(JEROME)
				_next("away")
		"away":
			_check_frame(delta)
			if _time > AWAY_TIME and _city.pending_count() == 0:
				_report_away()
				_camera.global_position = WorldOrigin.to_local(WOODLAWN)
				_next("terminal_load")
		"terminal_load":
			if (_time > 20.0 and _city.pending_count() == 0) or _time > TERMINAL_WAIT:
				if _place_at_terminal():
					_next("terminal")
				else:
					_finish()
		"terminal":
			_check_frame(delta)
			_check_terminal()
			if _out or _time > TERMINAL_TIME:
				_report_terminal()
				_finish()


func _next(phase: String) -> void:
	_phase = phase
	_time = 0.0


func _fail(what: String) -> void:
	_problems += 1
	push_error("trains: " + what)


func _finish() -> void:
	print("trains test finished: %d problems" % _problems)
	get_tree().quit(1 if _problems else 0)


## Keeps the hero out of the way, high over the el and still (not dropped
## onto the ground, its physics off).
func _park_hero() -> void:
	_world.place_hero(ROOSEVELT + Vector3(0.0, 600.0, 0.0), 0.0)
	_hero.process_mode = Node.PROCESS_MODE_DISABLED


## Per-frame checks over every train.
func _check_frame(delta: float) -> void:
	var t := _trains
	_stats.max_trains = maxf(_stats.max_trains, t.trains.size())
	_stats.train_seconds += t.trains.size() * delta
	for train in t.trains:
		_stats.distance += train.v * delta
		for piece in train.pieces:
			if piece.removed:
				_stats.removed += 1
		if train.v > Trains.TOP_SPEED + 0.3:
			_stats.overspeed += 1
		if train == _express:
			_express_run += train.v * delta
		var front := train.pieces[train.pieces.size() - 1]
		if train.s < front.length and train.v > front.speed_at(train.s) + 1.5:
			_stats.curve_overspeed += 1
			if _stats.curve_overspeed < 5:
				print("  over a curve's limit: %.1f m/s where %.1f m/s (%s, front piece's flags %d, turning %s)" % [
					train.v, front.speed_at(train.s), "the train put at the terminal" if train == _subject else "a train",
					front.flags, train.turning])
		# Just stopped at a platform: its middle at the platform's middle.
		var dwelling := train.dwell > 0.0
		if dwelling and not _dwelling.get(train, false) and train.served:
			_stats.stops += 1
			if train == _express:
				_express_stops += 1
			var middle := _point(train, train.span + train.s - train.length * 0.5)
			var stop := train.served.point_at(train.served_at)
			if middle.distance_to(stop) > 2.5:
				_stats.misaligned += 1
				print("  stopped %.1f m off its platform's middle" % middle.distance_to(stop))
		_dwelling[train] = dwelling
	# Trains on the same tracks never overlap.
	for m in t.trains.size():
		for n in range(m + 1, t.trains.size()):
			if _overlap(t.trains[m], t.trains[n]):
				_stats.overlaps += 1
				if _stats.overlaps < 5:
					print("  trains %d and %d overlap" % [m, n])


## Whether two trains are on the same piece of track at once, their spans
## along it crossing.
func _overlap(a: Trains.Train, b: Trains.Train) -> bool:
	var start_a := 0.0
	for piece in a.pieces:
		var k := b.pieces.find(piece)
		if k >= 0:
			var start_b := 0.0
			for q in k:
				start_b += b.pieces[q].length
			var front_a := a.span + a.s - start_a
			var front_b := b.span + b.s - start_b
			if maxf(front_a - a.length, front_b - b.length) < minf(front_a, front_b) - 0.5:
				return true
		start_a += piece.length
	return false


## The point `x` along a train's pieces from the start of its first.
func _point(train: Trains.Train, x: float) -> Vector3:
	var start := 0.0
	for piece in train.pieces:
		if x < start + piece.length or piece == train.pieces[train.pieces.size() - 1]:
			return piece.point_at(x - start)
		start += piece.length
	return Vector3.ZERO


## Checks the express tracks loaded run one way (the evening's, away from
## Manhattan) and puts an express train on one near the camera (making room).
func _place_express() -> void:
	var out := 0
	var into := 0
	var near: Array[TrainTracks.Piece] = []
	for key: Vector2i in _trains.tracks.tiles:
		for piece: TrainTracks.Piece in _trains.tracks.tiles[key]:
			if piece.flags & CityTileDecoder.TRACK_EXPRESS_OUT != 0:
				out += 1
				if piece.is_main() and piece.points[0].distance_to(ROOSEVELT) < 800.0:
					near.append(piece)
			if piece.flags & CityTileDecoder.TRACK_EXPRESS_IN != 0:
				into += 1
	print("express tracks: %d pieces away from Manhattan, %d toward it" % [out, into])
	if out == 0 or into > 0:
		_fail("the express tracks don't run away from Manhattan alone at 15:30")
	if _trains.trains.size() >= _trains.max_trains:
		_trains._despawn(_trains.trains[0])
	for piece in near:
		_express = _trains.place(piece, piece.length)
		if _express != null:
			break
	print("an express train put on the 7's express track: %s" % (_express != null))
	if _express == null:
		_fail("no room for an express train")


func _report_run() -> void:
	print("ran %.0f s: up to %d trains, %.0f m run (%.1f m/s on average), %d stops at platforms (%d off their middle), %d overlaps, %d over the top speed, %d over a curve's limit, %.3f ms a frame" % [
		RUN_TIME, _stats.max_trains, _stats.distance, _stats.distance / maxf(_stats.train_seconds, 1.0), _stats.stops,
		_stats.misaligned, _stats.overlaps, _stats.overspeed, _stats.curve_overspeed, _trains.update_msec])
	if _stats.overlaps > 0:
		_fail("%d overlaps" % _stats.overlaps)
	if _stats.overspeed > 0 or _stats.curve_overspeed > 0:
		_fail("trains over their speed limits")
	if _stats.distance < _stats.max_trains * RUN_TIME * 3.0:
		_fail("trains hardly moved (%.0f m)" % _stats.distance)
	if _stats.stops < 2:
		_fail("too few stops at platforms")
	if _stats.misaligned > 0:
		_fail("%d stops off the platform's middle" % _stats.misaligned)
	print("the express train ran %.0f m and stopped %d times (express stations only)" % [_express_run, _express_stops])
	if _express != null and _express_run < 200.0:
		_fail("the express train hardly moved")


## Stands the hero (still) on the tracks PERSON_AHEAD ahead of a train
## running at least 5 m/s near the camera with no stop before that, if there
## is one; returns whether it did.
func _place_person() -> bool:
	for train in _trains.trains:
		if train.v < 5.0 or train.stop_in < PERSON_AHEAD + 30.0 or train.head.distance_to(ROOSEVELT) > 600.0:
			continue
		var piece := train.pieces[train.pieces.size() - 1]
		var at := train.s + PERSON_AHEAD
		while piece and at > piece.length:
			at -= piece.length
			piece = _trains.tracks.next(piece, train.service)
		if piece == null:
			continue
		_subject = train
		_person_piece = piece
		_person_at = at
		_hero.global_position = WorldOrigin.to_local(piece.point_at(at) + Vector3.UP * 0.05)
		print("hero stands on the tracks %.0f m ahead of a train (%.1f m/s)" % [PERSON_AHEAD, train.v])
		return true
	return false


## How close the train comes to the hero (along the tracks).
func _check_person() -> void:
	if _subject == null or not _trains.trains.has(_subject):
		return
	var train := _subject
	var start := 0.0
	var gap := INF
	for piece in train.pieces:
		if piece == _person_piece:
			gap = start + _person_at - (train.span + train.s)
		start += piece.length
	if gap == INF:
		# Not on the hero's piece yet: along the pieces ahead.
		var piece := train.pieces[train.pieces.size() - 1]
		var reach := piece.length - train.s
		for step in 6:
			piece = _trains.tracks.next(piece, train.service)
			if piece == null:
				break
			if piece == _person_piece:
				gap = reach + _person_at
				break
			reach += piece.length
	if gap < INF:
		_closest = minf(_closest, gap)
		if gap < 40.0 and train.v < 0.1 and train.dwell <= 0.0:
			_stood_near = true


func _report_person() -> void:
	var speed := _subject.v if _subject and _trains.trains.has(_subject) else -1.0
	print("hero on the tracks: the train came within %.1f m, stood near it: %s, now at %.1f m/s" % [
		_closest, _stood_near, speed])
	if _subject == null:
		return
	if _closest < 4.0:
		_fail("a train ran into the hero")
	if not _stood_near:
		_fail("the train didn't stop for the hero")


## Drops the hero onto the roof of a moving train's middle car near the
## camera, if one is running at least 8 m/s with a clear way on; returns
## whether it did.
func _board() -> bool:
	_subject = null
	for train in _trains.trains:
		if train.v < 8.0 or train.stop_in < 150.0 or train.head.distance_to(ROOSEVELT) > 700.0:
			continue
		_subject = train
		var middle := _point(train, train.span + train.s - train.length * 0.5)
		_hero.global_position = WorldOrigin.to_local(middle + Vector3.UP * (train.car.z + 1.2))
		_hero.velocity = Vector3.ZERO
		_hero.frozen = false
		_hero.process_mode = Node.PROCESS_MODE_INHERIT
		_ride_start = middle
		print("hero dropped onto a train's roof (%.1f m/s)" % train.v)
		return true
	return false


## The hero is still on the train's roof, carried along: standing on top of
## one of its cars' boxes (in the car's own frame).
func _report_ride() -> void:
	if _subject == null:
		return
	var train := _subject
	var on: Vector3 = Vector3.INF
	for body in train.bodies:
		var local := body.global_transform.affine_inverse() * _hero.global_position
		if local.length_squared() < on.length_squared():
			on = local
	var carried := Vector2(_hero.world_position().x - _ride_start.x, _hero.world_position().z - _ride_start.z).length()
	print("ride: the hero stands %.1f m across and %.1f m along from the nearest car's middle, %.2f m over its rails, on the floor: %s; carried %.0f m (the train at %.1f m/s)" % [
		on.x, on.z, on.y, _hero.is_on_floor(), carried, train.v])
	if absf(on.x) > train.car.y * 0.5 or absf(on.z) > train.car.x * 0.5 or absf(on.y - train.car.z) > 0.3:
		_fail("the hero fell off the train")
	if carried < 15.0:
		_fail("the train didn't carry the hero")


func _report_away() -> void:
	var t := _trains
	var queens := 0
	for key: Vector2i in t.tracks.tile_bounds:
		var bounds: Rect2 = t.tracks.tile_bounds[key]
		if bounds.grow(200.0).has_point(Vector2(ROOSEVELT.x, ROOSEVELT.z)):
			queens += 1
	var stale := 0
	for train in t.trains:
		for piece in train.pieces:
			if piece.removed:
				stale += 1
	print("moved away: %d trains, %d on unloaded tracks, %d removed-track sightings, Queens' tracks loaded: %d, %d overlaps, %d over their limits" % [
		t.trains.size(), stale, _stats.removed, queens, _stats.overlaps, _stats.overspeed + _stats.curve_overspeed])
	if stale > 0 or _stats.removed > 0:
		_fail("trains left on unloaded tracks")
	if queens > 0:
		_fail("Queens' tracks didn't unload")
	if t.trains.is_empty():
		_fail("no trains on Jerome Avenue")
	if _stats.overlaps > 0:
		_fail("overlaps")


## Puts a train on the track into the 4's terminal at Woodlawn,
## TERMINAL_START before the terminal's track starts (the other trains go,
## and no more appear); returns whether it did.
func _place_at_terminal() -> bool:
	var tracks := _trains.tracks
	var dead: TrainTracks.Piece = null
	for key: Vector2i in tracks.tiles:
		for piece: TrainTracks.Piece in tracks.tiles[key]:
			if piece.flags & CityTileDecoder.TRACK_DEAD_END != 0 and tracks.turn_back(piece) != null \
					and (dead == null or piece.points[-1].distance_to(WOODLAWN) < dead.points[-1].distance_to(WOODLAWN)):
				dead = piece
	if dead == null or dead.points[-1].distance_to(WOODLAWN) > 1000.0:
		_fail("no terminal with a way back near Woodlawn")
		return false
	_bumper = dead.to_node
	# The train alone: no others appear meanwhile.
	_trains.radius = 0.0
	for train in _trains.trains.duplicate():
		_trains._despawn(train)
	var piece := dead
	var back := TERMINAL_START
	var to_bumper := 0.0
	while piece != null and (piece.is_terminal() or back > piece.length):
		if not piece.is_terminal():
			back -= piece.length
		to_bumper += piece.length
		piece = tracks.previous(piece, dead.service)
	if piece == null:
		_fail("the terminal's track isn't loaded far enough")
		return false
	_subject = _trains.place(piece, piece.length - back)
	print("a train put %.0f m before the bumper at Woodlawn, %.0f m before its track: %s" % [
		to_bumper + back, TERMINAL_START, _subject != null])
	if _subject == null:
		_fail("no room for a train at the terminal")
		return false
	return true


## Follows the train at the terminal, and looks for others on its track
## while it's there.
func _check_terminal() -> void:
	if _subject == null or not _trains.trains.has(_subject):
		return
	var train := _subject
	_at_bumper = _at_bumper or train.turn_wait > 0.0
	_turned = _turned or train.turning
	var inside := train.pieces.any(func(p: TrainTracks.Piece) -> bool: return p.is_terminal() or p.is_turn_back())
	if _turned and not train.turning and not inside:
		_out = true
	if not inside:
		return
	for other in _trains.trains:
		if other != train and other.pieces.any(
				func(p: TrainTracks.Piece) -> bool: return p.is_terminal() and _trains.tracks.bumper(p) == _bumper):
			_shared += 1


func _report_terminal() -> void:
	var gone := _subject == null or not _trains.trains.has(_subject)
	print("terminal: the train stood at the bumper: %s, turned back: %s, came out onto the other track: %s (after %.0f s), %d frames with another train on its track, still there: %s" % [
		_at_bumper, _turned, _out, _time, _shared, not gone])
	if not _at_bumper:
		_fail("the train didn't reach the terminal's bumper")
	if not _turned or not _out:
		_fail("the train didn't turn back out of the terminal")
	if _shared > 0:
		_fail("another train ran onto the terminal's track")
	if _stats.overlaps > 0:
		_fail("overlaps")
