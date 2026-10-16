class_name LoopVoice
extends RefCounted
## A looping sound (an AudioStreamPlayer or AudioStreamPlayer3D) whose
## loudness and pitch glide toward targets: it starts from a random point in
## its loop when it becomes audible, stops once it has been silent for
## `linger` seconds, and only passes on changes big enough to hear (on the
## web each one is a call into the browser's audio). Lingering matters on
## the web, where Godot copies a sound's whole decoded buffer each time it
## starts. Without an audio output (the dummy driver: headless tests) it
## keeps track of all that without playing anything.

## Quieter than this (linear gain), it counts as silent.
const SILENT := 0.004
const MIN_DB_STEP := 0.3
const MIN_PITCH_STEP := 0.02

## AudioStreamPlayer or AudioStreamPlayer3D.
var player: Node
## Loudness at full gain (dB).
var base_db := 0.0
## Seconds of silence before it stops.
var linger := 0.0
## Where gain (0..1) and pitch are heading.
var target := 0.0
var pitch := 1.0
var gain := 0.0
## Playing (or, without an audio output, would be).
var on := false

var _applied_db := -80.0
var _quiet_time := 0.0


func _init(player_node: Node, loudness_db: float, linger_seconds := 0.0) -> void:
	player = player_node
	base_db = loudness_db
	linger = linger_seconds


## Glides the gain toward the target (most of the way in about 1 / `rate`
## seconds) and passes it on.
func update(delta: float, rate: float) -> void:
	if player.stream == null:
		return
	gain = lerpf(gain, target, 1.0 - exp(-delta * rate))
	if gain < SILENT and target < SILENT:
		_quiet_time += delta
		if on and _quiet_time >= linger:
			on = false
			player.stop()
		if not on:
			return
	else:
		_quiet_time = 0.0
	var db := base_db + linear_to_db(maxf(gain, 0.0001))
	if not on:
		on = true
		_applied_db = db
		player.volume_db = db
		player.pitch_scale = pitch
		if GameAudio.audible():
			player.play(randf() * player.stream.get_length())
		return
	if absf(db - _applied_db) >= MIN_DB_STEP:
		player.volume_db = db
		_applied_db = db
	if absf(player.pitch_scale - pitch) > MIN_PITCH_STEP:
		player.pitch_scale = pitch


## Stops at once.
func silence() -> void:
	target = 0.0
	gain = 0.0
	_quiet_time = 0.0
	if on:
		on = false
		player.stop()


## The loudness last passed on (dB).
func volume_db() -> float:
	return _applied_db
