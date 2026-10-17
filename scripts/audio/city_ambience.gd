class_name CityAmbience
extends Node
## The city around the listener (the camera): looping beds of sound that
## crossfade with the time of day (TimeOfDay.night) and with where the
## listener is, read from the soundscape map (Soundscape): the street's
## traffic by day and a quieter street at night, Times Square's traffic, birds
## in parks by day and crickets at night, waves lapping near the water, and
## wind up high and out over the water. Up high the street gives way to the
## whole city's far-off hum. Now and then a horn honks, a siren wails far
## away, a bird calls or, at night, a dog barks, somewhere around. Cars
## driving by (TrafficSounds) add their engines on top of all this.

const UPDATE_INTERVAL := 0.25
## About how long beds take to follow a change (s).
const FADE_TIME := 1.2
## A bed that fades out keeps playing silently this long (s), in case it's
## wanted again soon (starting one copies its whole buffer, on the web).
const LINGER := 20.0

## Beds, in the order of the gains worked out in _update_targets().
const BEDS: Array[StringName] = [&"amb_traffic_day", &"amb_traffic_night", &"amb_city_far", &"amb_times_square",
	&"amb_birds", &"amb_crickets", &"amb_water", &"amb_wind"]

var time_of_day: TimeOfDay

var _beds: Array[LoopVoice] = []
var _cooldown := 0.0
# Chances per second of the odd sounds, from the last update.
var _horn_rate := 0.0
var _siren_rate := 0.0
var _bird_rate := 0.0
var _dog_rate := 0.0
## Where the street is below the listener (scene y), for placing those sounds.
var _street_y := 0.0


func _ready() -> void:
	for bed in BEDS:
		var player := AudioStreamPlayer.new()
		player.bus = &"Ambience"
		var files := SoundBank.streams(bed)
		if not files.is_empty():
			player.stream = files[0]
		add_child(player)
		_beds.append(LoopVoice.new(player, SoundBank.entry(bed).get("db", 0.0), LINGER))


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_fade(delta)
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func _fade(delta: float) -> void:
	if not GameAudio.can_play():
		for bed in _beds:
			bed.silence()
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = UPDATE_INTERVAL
		_update_targets()
		_maybe_play_odd_sounds()
	for bed in _beds:
		bed.update(delta, 3.0 / FADE_TIME)


## Which beds can be heard, and how loud (for ?stats).
func status_text() -> String:
	var parts := PackedStringArray()
	for i in BEDS.size():
		if _beds[i].on and _beds[i].gain >= LoopVoice.SILENT:
			parts.append("%s %d dB" % [str(BEDS[i]).trim_prefix("amb_"), roundi(_beds[i].volume_db())])
	return "beds: " + (", ".join(parts) if not parts.is_empty() else "none")


## How loud each bed should be (0..1), from the time and the listener's spot.
func _update_targets() -> void:
	var listener := GameAudio.listener()
	var world := WorldOrigin.to_world(listener)
	var spot := Soundscape.shared().sample(world)
	var green := spot.r
	var water := spot.g
	var city := clampf(spot.b * 1.25, 0.0, 1.0)
	var altitude := maxf(world.y - spot.a, 0.0)
	_street_y = listener.y - altitude
	# 1 down in the street, toward 0 a couple of hundred meters up, where
	# the city turns into a far-off hum.
	var street := 1.0 - smoothstep(10.0, 200.0, altitude)
	# Birds, crickets and waves are only heard close to the ground.
	var low := 1.0 - smoothstep(10.0, 80.0, altitude)
	var night := time_of_day.night if time_of_day else 0.0
	var square := Soundscape.times_square(world) * street
	var hum := (0.08 + 0.92 * city) * street * (1.0 - 0.5 * square)

	_beds[0].target = (1.0 - night) * hum
	_beds[1].target = night * hum
	_beds[2].target = (0.1 + 0.9 * city) * maxf(1.0 - street, 0.25) * (1.0 - 0.4 * night)
	_beds[3].target = square * (1.0 - 0.25 * night)
	_beds[4].target = (1.0 - night) * smoothstep(0.2, 0.65, green) * low
	_beds[5].target = night * smoothstep(0.15, 0.55, green) * low
	_beds[6].target = smoothstep(0.12, 0.55, water) * (1.0 - smoothstep(4.0, 35.0, world.y)) * (1.0 - square)
	_beds[7].target = maxf(smoothstep(30.0, 350.0, altitude), 0.35 * smoothstep(0.7, 1.0, water))

	_horn_rate = (0.07 * city * (1.0 - 0.6 * night) + 0.2 * square) * street
	_siren_rate = city * (0.4 + 0.6 * street) / 50.0
	_bird_rate = 0.5 * _beds[4].target
	_dog_rate = 0.03 * night * smoothstep(0.1, 0.4, green) * (1.0 - 0.5 * city) * low


## Horns, sirens, birds and dogs, at random, somewhere around the listener.
func _maybe_play_odd_sounds() -> void:
	if randf() < _horn_rate * UPDATE_INTERVAL:
		GameAudio.play(&"horn", _around(25.0, 140.0, 1.0), randf_range(-6.0, 0.0))
	if randf() < _siren_rate * UPDATE_INTERVAL:
		GameAudio.play(&"siren", _around(250.0, 700.0, 3.0), randf_range(-4.0, 0.0))
	if randf() < _bird_rate * UPDATE_INTERVAL:
		GameAudio.play(&"bird", _around(8.0, 35.0, randf_range(5.0, 14.0)), randf_range(-6.0, 0.0))
	if randf() < _dog_rate * UPDATE_INTERVAL:
		GameAudio.play(&"dog", _around(60.0, 250.0, 1.0), randf_range(-6.0, 0.0))


## A random spot `near` to `far` meters from the listener, `height` above the street.
func _around(near: float, far: float, height: float) -> Vector3:
	var listener := GameAudio.listener()
	var angle := randf() * TAU
	var distance := randf_range(near, far)
	return Vector3(listener.x + cos(angle) * distance, _street_y + height, listener.z + sin(angle) * distance)
