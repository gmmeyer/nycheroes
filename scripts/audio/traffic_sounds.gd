class_name TrafficSounds
extends Node
## Engines for the moving cars near the listener, from what the traffic
## simulation reports through GameAudio.set_traffic() (world positions and
## speeds, as Traffic keeps them): the nearest few cars
## each carry a looping engine that rises in pitch as they speed up and
## fades in and out as they come and go. One pass over the report, nothing
## allocated, so it can be called every frame. Without reports (no traffic,
## or none for a moment) the engines fade out; the city's hum
## (CityAmbience) doesn't depend on them.

const VOICES := 4
## Cars further away than this (m) aren't given an engine.
const HEAR_DISTANCE := 60.0
## A voice stays on its car if the car is within this of where it last was (m).
const FOLLOW_DISTANCE := 8.0
## Without a report for this long (s), the engines fade out.
const STALE_TIME := 0.5
## An engine that fades out keeps playing silently this long (s).
const LINGER := 3.0

## Cars reported within 150 m at the last report (for ?stats).
var nearby_count := 0

var _engines: Array[LoopVoice] = []
var _car_position := PackedVector3Array()
var _has_car := PackedByteArray()
var _wanted_gain := PackedFloat32Array()
var _wanted_pitch := PackedFloat32Array()
var _last_report := -1000.0
# The nearest cars of the last report: distance squared and index, nearest first.
var _best_d2 := PackedFloat32Array()
var _best_index := PackedInt32Array()
var _taken := PackedByteArray()


func _ready() -> void:
	var files := SoundBank.streams(&"engine")
	var entry := SoundBank.entry(&"engine")
	for i in VOICES:
		var player := AudioStreamPlayer3D.new()
		player.bus = &"Ambience"
		player.stream = files[0] if not files.is_empty() else null
		player.unit_size = entry.get("unit", 6.0)
		player.max_distance = HEAR_DISTANCE + 10.0
		player.max_db = entry.get("db", 0.0)
		player.attenuation_filter_db = 0.0
		player.panning_strength = 0.8
		add_child(player)
		_engines.append(LoopVoice.new(player, entry.get("db", 0.0), LINGER))
	_car_position.resize(VOICES)
	_car_position.fill(Vector3.ZERO)
	_has_car.resize(VOICES)
	_has_car.fill(0)
	_wanted_gain.resize(VOICES)
	_wanted_gain.fill(0.0)
	_wanted_pitch.resize(VOICES)
	_wanted_pitch.fill(1.0)
	_taken.resize(VOICES)
	_best_d2.resize(VOICES)
	_best_index.resize(VOICES)


## The moving cars' world positions and speeds (m/s); only the first `count`
## entries are used (all with -1), and ones with a negative speed are free
## slots. See GameAudio.set_traffic().
func update_cars(positions: PackedVector3Array, speeds: PackedFloat32Array, count := -1) -> void:
	var start := Time.get_ticks_usec()
	_match_cars(positions, speeds, count)
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func _match_cars(positions: PackedVector3Array, speeds: PackedFloat32Array, count: int) -> void:
	_last_report = GameAudio.now()
	var listener := WorldOrigin.to_world(GameAudio.listener())
	var n := positions.size() if count < 0 else mini(count, positions.size())
	var has_speeds := speeds.size() >= n
	_best_d2.fill(HEAR_DISTANCE * HEAR_DISTANCE)
	_best_index.fill(-1)
	nearby_count = 0
	for i in n:
		if has_speeds and speeds[i] < 0.0:
			continue  # a free slot
		var d2 := positions[i].distance_squared_to(listener)
		if d2 < 22500.0:
			nearby_count += 1
		if d2 >= _best_d2[VOICES - 1]:
			continue
		# Insert into the short list of the nearest, keeping it sorted.
		var slot := VOICES - 1
		while slot > 0 and _best_d2[slot - 1] > d2:
			_best_d2[slot] = _best_d2[slot - 1]
			_best_index[slot] = _best_index[slot - 1]
			slot -= 1
		_best_d2[slot] = d2
		_best_index[slot] = i

	# Engines keep following their cars; the other near cars get free ones.
	_taken.fill(0)
	for v in VOICES:
		if _has_car[v] == 0:
			continue
		var found := -1
		var found_d2 := FOLLOW_DISTANCE * FOLLOW_DISTANCE
		for b in VOICES:
			var car := _best_index[b]
			if car == -1 or _taken[b] == 1:
				continue
			var d2 := positions[car].distance_squared_to(_car_position[v])
			if d2 < found_d2:
				found_d2 = d2
				found = b
		if found == -1:
			_has_car[v] = 0
			_wanted_gain[v] = 0.0
		else:
			_taken[found] = 1
			_follow(v, _best_index[found], positions, speeds)
	for b in VOICES:
		if _best_index[b] == -1 or _taken[b] == 1:
			continue
		for v in VOICES:
			if _has_car[v] == 0 and _engines[v].gain < LoopVoice.SILENT:
				_has_car[v] = 1
				_follow(v, _best_index[b], positions, speeds)
				_engines[v].pitch = _wanted_pitch[v]
				break


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_fade(delta)
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func _fade(delta: float) -> void:
	if not GameAudio.can_play():
		for engine in _engines:
			engine.silence()
		return
	var stale := GameAudio.now() - _last_report > STALE_TIME
	var follow := 1.0 - exp(-delta * 4.0)
	for v in VOICES:
		var engine := _engines[v]
		engine.target = 0.0 if stale else _wanted_gain[v]
		engine.pitch = lerpf(engine.pitch, _wanted_pitch[v], follow)
		engine.update(delta, 4.0)
		if stale and engine.gain < LoopVoice.SILENT:
			_has_car[v] = 0


func status_text() -> String:
	var playing := 0
	for engine in _engines:
		if engine.on and engine.gain >= LoopVoice.SILENT:
			playing += 1
	return "traffic: %d engines, %d cars near" % [playing, nearby_count]


func _follow(voice: int, car: int, positions: PackedVector3Array, speeds: PackedFloat32Array) -> void:
	var speed := speeds[car] if car < speeds.size() else 8.0
	_car_position[voice] = positions[car]
	(_engines[voice].player as Node3D).global_position = WorldOrigin.to_local(positions[car])
	# Idling cars are quieter; faster ones higher.
	_wanted_gain[voice] = 0.35 + 0.65 * smoothstep(0.0, 14.0, speed)
	# An idle recording shifted nearly an octave sounded like a small motor
	# whining. Keep the engine's body while still suggesting acceleration.
	_wanted_pitch[voice] = lerpf(0.9, 1.3, smoothstep(0.0, 22.0, speed))
