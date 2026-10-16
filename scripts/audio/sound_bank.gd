class_name SoundBank
## Every sound the game plays and how: its files, loudness, pitch spread, bus,
## how far it carries and how many may play at once. The files are mono Ogg
## Vorbis in assets/audio/, made by tools/audio/build_sounds.py (some are
## synthesized there, the rest cut from CC0 recordings; CREDITS.md lists
## them). A sound with several files plays a random one, never the same one
## twice in a row; phones (Quality's low preset) load two at most, since
## browsers keep every sound decoded (Godot's web build: 48 kHz stereo, 384
## kB a second).
##
## Per sound:
##   count   files: <name>.ogg for one, <name>_1.ogg .. <name>_<count>.ogg
##   db      loudness (files are normalized, so these set the mix)
##   pitch   random pitch spread, +- this fraction
##   unit    distance (m) out to which it plays at full loudness; it then
##           falls off 6 dB per doubling (inverse distance)
##   reach   distance (m) past which it isn't played at all (it fades to
##           nothing there)
##   voices  how many may play at once (the oldest is cut off for a new one)
##   gap     seconds before it may start again (anywhere)
##   bus     "SFX" (default), "Ambience" or "UI"
##   loop    loops (beds and engines, played by their own players)

const DIR := "res://assets/audio/"

const SOUNDS := {
	# The hero (HeroSounds).
	&"step_concrete": {count = 5, db = -15.0, pitch = 0.08, unit = 3.0, reach = 35.0, voices = 4},
	&"step_grass": {count = 5, db = -13.0, pitch = 0.08, unit = 3.0, reach = 35.0, voices = 4},
	&"step_wood": {count = 5, db = -14.0, pitch = 0.08, unit = 3.0, reach = 35.0, voices = 4},
	&"jump": {count = 3, db = -13.0, pitch = 0.1, unit = 4.0, reach = 50.0, voices = 2},
	&"launch": {count = 1, db = -6.0, pitch = 0.05, unit = 8.0, reach = 200.0, voices = 2},
	&"land": {count = 3, db = -9.0, pitch = 0.08, unit = 5.0, reach = 80.0, voices = 2},
	&"land_heavy": {count = 2, db = -6.0, pitch = 0.06, unit = 8.0, reach = 150.0, voices = 2},
	&"slam": {count = 1, db = -5.0, pitch = 0.04, unit = 12.0, reach = 300.0, voices = 2},
	&"debris": {count = 2, db = -10.0, pitch = 0.1, unit = 8.0, reach = 120.0, voices = 2},
	&"whoosh_punch": {count = 4, db = -12.0, pitch = 0.1, unit = 4.0, reach = 40.0, voices = 3},
	&"whoosh_heavy": {count = 2, db = -8.0, pitch = 0.08, unit = 5.0, reach = 60.0, voices = 2},
	&"whoosh_swing": {count = 3, db = -9.0, pitch = 0.08, unit = 6.0, reach = 100.0, voices = 2},
	&"dive": {count = 1, db = -7.0, pitch = 0.05, unit = 8.0, reach = 150.0, voices = 2},
	&"takeoff": {count = 1, db = -9.0, pitch = 0.06, unit = 6.0, reach = 100.0, voices = 2},
	&"zoom": {count = 1, db = -8.0, pitch = 0.05, unit = 8.0, reach = 150.0, voices = 2},
	&"thwip": {count = 3, db = -8.0, pitch = 0.08, unit = 5.0, reach = 80.0, voices = 3},
	&"web_release": {count = 1, db = -16.0, pitch = 0.1, unit = 4.0, reach = 40.0, voices = 2},
	&"creak": {count = 3, db = -17.0, pitch = 0.1, unit = 4.0, reach = 40.0, voices = 2},
	&"powerup": {count = 1, db = -6.0, pitch = 0.0, unit = 8.0, reach = 120.0, voices = 1},
	&"hero_hurt": {count = 4, db = -9.0, pitch = 0.06, unit = 5.0, reach = 60.0, voices = 1, gap = 0.45},
	&"hero_effort": {count = 2, db = -13.0, pitch = 0.06, unit = 5.0, reach = 50.0, voices = 1, gap = 1.0},
	&"splash": {count = 2, db = -7.0, pitch = 0.08, unit = 6.0, reach = 100.0, voices = 2},
	&"swim": {count = 3, db = -15.0, pitch = 0.1, unit = 4.0, reach = 40.0, voices = 2},
	&"air_low": {count = 1, db = -10.0, unit = 6.0, reach = 200.0, loop = true},
	&"air_high": {count = 1, db = -12.0, unit = 6.0, reach = 200.0, loop = true},
	&"speed_loop": {count = 1, db = -11.0, unit = 6.0, reach = 150.0, loop = true},
	&"charge_loop": {count = 1, db = -14.0, unit = 5.0, reach = 60.0, loop = true},

	# Fights (Thug, Combat, Pedestrian).
	&"punch": {count = 5, db = -6.0, pitch = 0.08, unit = 6.0, reach = 80.0, voices = 4},
	&"punch_heavy": {count = 5, db = -4.0, pitch = 0.06, unit = 8.0, reach = 120.0, voices = 3},
	&"body_fall": {count = 3, db = -8.0, pitch = 0.08, unit = 6.0, reach = 80.0, voices = 3},
	&"thug_hurt": {count = 5, db = -9.0, pitch = 0.07, unit = 6.0, reach = 80.0, voices = 2, gap = 0.25},
	&"thug_effort": {count = 3, db = -13.0, pitch = 0.07, unit = 5.0, reach = 50.0, voices = 1, gap = 0.8},
	&"thug_down": {count = 3, db = -7.0, pitch = 0.06, unit = 6.0, reach = 90.0, voices = 2},
	&"thug_shout": {count = 4, db = -6.0, pitch = 0.05, unit = 8.0, reach = 120.0, voices = 1, gap = 3.0},
	&"scream": {count = 5, db = -9.0, pitch = 0.06, unit = 8.0, reach = 120.0, voices = 1, gap = 4.0},

	# The city (CityAmbience, TrafficSounds).
	&"horn": {count = 5, db = -9.0, pitch = 0.04, unit = 25.0, reach = 500.0, voices = 2, gap = 1.2, bus = &"Ambience"},
	&"siren": {count = 2, db = -12.0, pitch = 0.03, unit = 80.0, reach = 1500.0, voices = 1, bus = &"Ambience"},
	&"bird": {count = 4, db = -15.0, pitch = 0.1, unit = 10.0, reach = 120.0, voices = 3, bus = &"Ambience"},
	&"dog": {count = 2, db = -17.0, pitch = 0.06, unit = 30.0, reach = 600.0, voices = 1, gap = 6.0, bus = &"Ambience"},
	&"engine": {count = 1, db = -12.0, unit = 6.0, reach = 70.0, loop = true, bus = &"Ambience"},
	&"amb_traffic_day": {count = 1, db = -9.0, loop = true, bus = &"Ambience"},
	&"amb_traffic_night": {count = 1, db = -10.0, loop = true, bus = &"Ambience"},
	&"amb_city_far": {count = 1, db = -12.0, loop = true, bus = &"Ambience"},
	&"amb_times_square": {count = 1, db = -8.0, loop = true, bus = &"Ambience"},
	&"amb_birds": {count = 1, db = -13.0, loop = true, bus = &"Ambience"},
	&"amb_crickets": {count = 1, db = -15.0, loop = true, bus = &"Ambience"},
	&"amb_water": {count = 1, db = -11.0, loop = true, bus = &"Ambience"},
	&"amb_wind": {count = 1, db = -12.0, loop = true, bus = &"Ambience"},

	# The interface.
	&"ui_toggle": {count = 1, db = -8.0, bus = &"UI"},
}

static var _streams := {}  # name -> Array[AudioStream]


## Loads every sound's files (once). Loops are set to loop.
static func load_all() -> void:
	if not _streams.is_empty():
		return
	var most := 2 if Quality.level() == Quality.Level.LOW else 99
	for sound: StringName in SOUNDS:
		var entry: Dictionary = SOUNDS[sound]
		var count: int = entry.count
		var files: Array[AudioStream] = []
		for i in mini(count, most):
			var path := DIR + (str(sound) if count == 1 else "%s_%d" % [sound, i + 1]) + ".ogg"
			var stream := load(path) as AudioStream
			if stream == null:
				push_warning("Missing sound %s" % path)
				continue
			if entry.get("loop", false) and stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			files.append(stream)
		_streams[sound] = files


## A sound's files (empty if it has none).
static func streams(sound: StringName) -> Array:
	return _streams.get(sound, [])


## Every loaded file, e.g. to get them ready to play ahead of time.
static func all_streams() -> Array[AudioStream]:
	var all: Array[AudioStream] = []
	for files: Array in _streams.values():
		all.append_array(files)
	return all


static func entry(sound: StringName) -> Dictionary:
	return SOUNDS.get(sound, {})
