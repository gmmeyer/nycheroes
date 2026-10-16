class_name TrainSounds
extends Node
## Trains on the els near the listener, from what Trains reports through
## GameAudio.set_trains() (each train's nearest point to the listener, its
## speed, and how much its wheels squeal): the nearest VOICES trains each
## carry a looping rumble (wheels clattering over the rail joints and the
## steel el roaring under them) that grows louder and quicker as they speed
## up, and a squeal that comes in on tight curves and braking slowly into a
## station. Without reports (no trains, or none for a moment) they fade out.

const VOICES := 2
## Trains further away than this (m) aren't heard.
const HEAR_DISTANCE := 260.0
## Without a report for this long (s), the sounds fade out.
const STALE_TIME := 0.6
## A loop that fades out keeps playing silently this long (s).
const LINGER := 3.0

## Trains reported within HEAR_DISTANCE at the last report (for ?stats).
var nearby_count := 0

var _rumbles: Array[LoopVoice] = []
var _squeals: Array[LoopVoice] = []
var _rumble_gain := PackedFloat32Array()
var _rumble_pitch := PackedFloat32Array()
var _squeal_gain := PackedFloat32Array()
var _last_report := -1000.0
# The nearest trains of the last report: distance squared and index.
var _best_d2 := PackedFloat32Array()
var _best_index := PackedInt32Array()


func _ready() -> void:
	for sound: StringName in [&"train_rumble", &"train_squeal"]:
		var files := SoundBank.streams(sound)
		var entry := SoundBank.entry(sound)
		for i in VOICES:
			var player := AudioStreamPlayer3D.new()
			player.bus = &"Ambience"
			player.stream = files[0] if not files.is_empty() else null
			player.unit_size = entry.get("unit", 10.0)
			player.max_distance = entry.get("reach", HEAR_DISTANCE)
			player.max_db = entry.get("db", 0.0)
			player.attenuation_filter_db = 0.0
			player.panning_strength = 0.8
			add_child(player)
			var voice := LoopVoice.new(player, entry.get("db", 0.0), LINGER)
			(_rumbles if sound == &"train_rumble" else _squeals).append(voice)
	_rumble_gain.resize(VOICES)
	_rumble_gain.fill(0.0)
	_rumble_pitch.resize(VOICES)
	_rumble_pitch.fill(1.0)
	_squeal_gain.resize(VOICES)
	_squeal_gain.fill(0.0)
	_best_d2.resize(VOICES)
	_best_index.resize(VOICES)


## Each train's nearest point to the listener (world), its speed (m/s) and
## its wheels' squeal (0..1). See GameAudio.set_trains().
func update_trains(points: PackedVector3Array, speeds: PackedFloat32Array, squeals: PackedFloat32Array) -> void:
	var start := Time.get_ticks_usec()
	_last_report = GameAudio.now()
	var listener := WorldOrigin.to_world(GameAudio.listener())
	_best_d2.fill(HEAR_DISTANCE * HEAR_DISTANCE)
	_best_index.fill(-1)
	nearby_count = 0
	for i in points.size():
		var d2 := points[i].distance_squared_to(listener)
		if d2 >= HEAR_DISTANCE * HEAR_DISTANCE:
			continue
		nearby_count += 1
		# Into the short list of the nearest, kept sorted.
		var slot := VOICES - 1
		if d2 >= _best_d2[slot]:
			continue
		while slot > 0 and _best_d2[slot - 1] > d2:
			_best_d2[slot] = _best_d2[slot - 1]
			_best_index[slot] = _best_index[slot - 1]
			slot -= 1
		_best_d2[slot] = d2
		_best_index[slot] = i
	for v in VOICES:
		var i := _best_index[v]
		if i < 0:
			_rumble_gain[v] = 0.0
			_squeal_gain[v] = 0.0
			continue
		var at := WorldOrigin.to_local(points[i])
		(_rumbles[v].player as Node3D).global_position = at
		(_squeals[v].player as Node3D).global_position = at
		# Standing, a hum (motors, air conditioning); faster, louder and quicker.
		_rumble_gain[v] = 0.2 + 0.8 * smoothstep(0.0, 14.0, speeds[i])
		_rumble_pitch[v] = clampf(0.55 + speeds[i] / 22.0, 0.55, 1.4)
		_squeal_gain[v] = squeals[i] if i < squeals.size() else 0.0
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	if not GameAudio.can_play():
		for voice in _rumbles + _squeals:
			voice.silence()
	else:
		var stale := GameAudio.now() - _last_report > STALE_TIME
		var follow := 1.0 - exp(-delta * 3.0)
		for v in VOICES:
			var rumble := _rumbles[v]
			rumble.target = 0.0 if stale else _rumble_gain[v]
			rumble.pitch = lerpf(rumble.pitch, _rumble_pitch[v], follow)
			rumble.update(delta, 2.5)
			_squeals[v].target = 0.0 if stale else _squeal_gain[v]
			_squeals[v].update(delta, 4.0)
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func status_text() -> String:
	var playing := 0
	for voice in _rumbles:
		if voice.on and voice.gain >= LoopVoice.SILENT:
			playing += 1
	return "trains: %d rumbling, %d near" % [playing, nearby_count]
