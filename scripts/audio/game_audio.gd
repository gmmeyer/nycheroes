class_name GameAudio
extends Node
## The game's sound (the "Audio" node in world.tscn): plays one-off sounds in
## the 3-D world from a pool of players, runs the city's ambience
## (CityAmbience), the engines of passing cars (TrafficSounds) and the
## trains on the els (TrainSounds), and
## switches the sound off and on: N, or the speaker button on touch screens
## (remembered between visits, see SoundSettings). Other scripts call the
## static functions (play(), play_later(), set_traffic(), ...), which do
## nothing when there's no GameAudio. The hero's own sounds are HeroSounds,
## on every hero (ours and other players').
##
## Buses (default_bus_layout.tres): Master, with SFX (the hero and fights),
## Ambience (the city) and UI under it.
##
## Browsers only let a page make sound after a click, tap or key press, and
## Godot resumes its audio then. Until the first one nothing is started, so
## nothing queues up to blare all at once; ?demo tours (which have no input)
## start right away (record them with autoplay allowed).
##
## Web builds play sounds as Web Audio samples (Godot's default there), so
## the browser mixes them off the main thread; while the city loads, the
## files are decoded into samples one per frame, so the first punch doesn't
## stall a frame. ?stats logs what's playing every few seconds, and
## how long the sound scripts take a frame; ?audio=0 leaves sound out
## altogether (to compare frame rates).

signal muted_changed(muted: bool)

## One-off sounds playing at once, at most (all kinds together).
const MAX_VOICES := 24
const BUSES: Array[StringName] = [&"SFX", &"Ambience", &"UI"]
## How long the "Sound off" note stays up (s).
const NOTE_TIME := 2.2
const STATS_INTERVAL := 4.0
## Sounds held back to play a moment later (play_later), at most.
const MAX_PENDING := 16

@export var time_of_day: TimeOfDay

## The city's ambience, the traffic's engines and the trains (children,
## made in _ready).
var ambience: CityAmbience
var traffic: TrafficSounds
var trains: TrainSounds
var muted := false

## Microseconds the sound scripts have taken since the last ?stats line
## (each adds its own).
static var cost_usec := 0
static var _instance: GameAudio
static var _audible := -1

var _unlocked := false
var _listener := Vector3.ZERO
var _voice_root: Node3D
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_sound: Array[StringName] = []
var _voice_start := PackedFloat64Array()
var _voice_end := PackedFloat64Array()
var _last_start := {}  # sound -> seconds
var _last_file := {}  # sound -> index of the file it played last
var _ui_player: AudioStreamPlayer
var _pending_sound: Array[StringName] = []
var _pending_node: Array[Node3D] = []
var _pending_time := PackedFloat64Array()
var _pending_db := PackedFloat32Array()
var _to_register: Array[AudioStream] = []
var _note: Label
var _note_time := 0.0
var _stats_cooldown := STATS_INTERVAL
var _log_stats := false
var _frames := 0
## How many times each sound has started (for tests and ?stats).
var play_counts := {}


func _enter_tree() -> void:
	if not off():
		_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	if off():
		print("[audio] off (?audio=0)")
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	_ensure_buses()
	if not InputMap.has_action(&"mute"):
		InputMap.add_action(&"mute")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_N
		InputMap.action_add_event(&"mute", key)
	SoundBank.load_all()
	_voice_root = Node3D.new()
	_voice_root.name = "Voices"
	_voice_root.add_to_group("floating")
	add_child(_voice_root)
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.attenuation_filter_db = 0.0  # the same on the web, whose samples have no filters
		voice.panning_strength = 0.8
		_voice_root.add_child(voice)
		_voices.append(voice)
		_voice_sound.append(&"")
	_voice_start.resize(MAX_VOICES)
	_voice_end.resize(MAX_VOICES)
	_voice_end.fill(0.0)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = &"UI"
	add_child(_ui_player)
	for i in MAX_PENDING:
		_pending_sound.append(&"")
		_pending_node.append(null)
	_pending_time.resize(MAX_PENDING)
	_pending_time.fill(-1.0)
	_pending_db.resize(MAX_PENDING)

	ambience = CityAmbience.new()
	ambience.name = "Ambience"
	ambience.time_of_day = time_of_day
	add_child(ambience)
	traffic = TrafficSounds.new()
	traffic.name = "Traffic"
	add_child(traffic)
	trains = TrainSounds.new()
	trains.name = "Trains"
	add_child(trains)

	_log_stats = LaunchOptions.has("stats")
	muted = SoundSettings.load_muted()
	AudioServer.set_bus_mute(0, muted)
	_unlocked = not OS.has_feature("web") or LaunchOptions.has("demo")
	if OS.has_feature("web") and int(ProjectSettings.get_setting("audio/general/default_playback_type", 0)) == 1:
		_to_register = SoundBank.all_streams()
	print("[audio] %d sounds, driver %s, %s%s" % [SoundBank.all_streams().size(), AudioServer.get_driver_name(),
		"muted" if muted else "on", "" if _unlocked else ", waiting for the first click, tap or key"])


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	var camera := get_viewport().get_camera_3d()
	if camera:
		_listener = camera.global_position
	if not _unlocked and Input.is_anything_pressed():
		_unlock()
	if not _to_register.is_empty():
		var stream: AudioStream = _to_register.pop_back()
		if not AudioServer.is_stream_registered_as_sample(stream):
			AudioServer.register_stream_as_sample(stream)
	_play_pending()
	if _note and _note.visible:
		_note_time -= delta
		_note.modulate.a = clampf(_note_time / 0.4, 0.0, 1.0)
		_note.visible = _note_time > 0.0
	cost_usec += Time.get_ticks_usec() - start
	_frames += 1
	if _log_stats:
		_stats_cooldown -= delta
		if _stats_cooldown <= 0.0:
			_stats_cooldown = STATS_INTERVAL
			print("[audio] %s, scripts %.3f ms a frame" % [status_text(), cost_usec / 1000.0 / maxi(_frames, 1)])
			cost_usec = 0
			_frames = 0


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_unlock()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"mute") and not event.is_echo():
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return  # typing a room code
		toggle()
		get_viewport().set_input_as_handled()


## Plays a sound at a scene position: `volume_db` on top of its loudness,
## `pitch` times its pitch. Nothing plays when it's out of earshot.
static func play(sound: StringName, at: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if _instance:
		_instance._play(sound, at, volume_db, pitch)


## Plays a sound `seconds` from now where `follow` is then (or where its
## body lies, for a node with ground_position(), like a thrown thug).
static func play_later(sound: StringName, seconds: float, follow: Node3D, volume_db := 0.0) -> void:
	if _instance == null or not _instance.is_running():
		return
	var i := _instance._pending_time.find(-1.0)
	if i == -1:
		return
	_instance._pending_sound[i] = sound
	_instance._pending_node[i] = follow
	_instance._pending_db[i] = volume_db
	_instance._pending_time[i] = now() + seconds


## Plays an interface sound (not in the 3-D world).
static func play_ui(sound: StringName) -> void:
	if _instance == null or not _instance.is_running():
		return
	var files := SoundBank.streams(sound)
	if files.is_empty() or not audible():
		return
	_instance._ui_player.stream = files[0]
	_instance._ui_player.volume_db = SoundBank.entry(sound).get("db", 0.0)
	_instance._ui_player.play()


## For the traffic simulation, to give nearby cars engine sounds: the moving
## cars' world positions and speeds (m/s), every frame or a few times a
## second (Traffic can pass its own arrays). Only the first `count` entries
## count (all with -1), and entries with a negative speed are skipped (free
## slots). See TrafficSounds.
static func set_traffic(positions: PackedVector3Array, speeds: PackedFloat32Array, count := -1) -> void:
	if _instance:
		_instance.traffic.update_cars(positions, speeds, count)


## For the trains on the els: each train's nearest point to the listener
## (world), its speed (m/s) and how much its wheels squeal (0..1), a few
## times a second. See TrainSounds.
static func set_trains(points: PackedVector3Array, speeds: PackedFloat32Array, squeals: PackedFloat32Array) -> void:
	if _instance:
		_instance.trains.update_trains(points, speeds, squeals)


## A car honks at a world position (stuck behind a hero or a pedestrian,
## say). Only one or two horns sound at a time, anywhere.
static func car_horn(world_position: Vector3) -> void:
	play(&"horn", WorldOrigin.to_local(world_position), randf_range(-3.0, 0.0))


## Sound is left out altogether (?audio=0).
static func off() -> bool:
	return LaunchOptions.get_string("audio") == "0"


## Whether sounds can play now: after the first input, and not muted.
static func can_play() -> bool:
	return _instance != null and _instance.is_running()


## Whether there's an audio output. Without one (the dummy driver: headless
## tests) everything is worked out as usual, but no player is started: a
## sound still playing when a test quits would be reported as leaked.
static func audible() -> bool:
	if _audible == -1:
		_audible = 0 if AudioServer.get_driver_name() == "Dummy" else 1
	return _audible == 1


## Whether the sound is switched off.
static func is_muted() -> bool:
	return _instance != null and _instance.muted


## Switches the sound off or back on (N, the touch speaker button).
static func toggle_mute() -> void:
	if _instance:
		_instance.toggle()


## Where sounds are heard from: the current camera (scene space).
static func listener() -> Vector3:
	return _instance._listener if _instance else Vector3.ZERO


## Sounds can play: after the first input, and not muted.
func is_running() -> bool:
	return _unlocked and not muted


func toggle() -> void:
	if not _unlocked:
		_unlock()  # a tap on the speaker button is a first input too
	set_muted(not muted)


func set_muted(on: bool) -> void:
	muted = on
	AudioServer.set_bus_mute(0, on)
	SoundSettings.save_muted(on)
	if on:
		for voice in _voices:
			voice.stop()
		_voice_end.fill(0.0)
	else:
		play_ui(&"ui_toggle")
	var hint := "" if Device.is_mobile() else "  ·  N turns it back on"
	_show_note("Sound off" + hint if on else "Sound on")
	print("[audio] sound %s" % ("off" if on else "on"))
	muted_changed.emit(on)


## A line for ?stats: one-off sounds playing, and the ambience's beds.
func status_text() -> String:
	var time := now()
	var busy := 0
	for i in MAX_VOICES:
		if _voice_end[i] > time:
			busy += 1
	return "%s, %d/%d voices, %s, %s, %s" % ["muted" if muted else ("on" if _unlocked else "waiting for input"),
		busy, MAX_VOICES, ambience.status_text(), traffic.status_text(), trains.status_text()]


func _unlock() -> void:
	_unlocked = true
	print("[audio] started by the first input")


func _play(sound: StringName, at: Vector3, volume_db: float, pitch: float) -> void:
	if not is_running():
		return
	var entry: Dictionary = SoundBank.SOUNDS.get(sound, {})
	var files := SoundBank.streams(sound)
	if files.is_empty():
		return
	var reach: float = entry.get("reach", 100.0)
	if at.distance_squared_to(_listener) > reach * reach:
		return
	var time := now()
	var gap: float = entry.get("gap", 0.0)
	if gap > 0.0 and time - float(_last_start.get(sound, -1000.0)) < gap:
		return
	_last_start[sound] = time
	play_counts[sound] = int(play_counts.get(sound, 0)) + 1

	var index := randi() % files.size()
	if files.size() > 1 and index == int(_last_file.get(sound, -1)):
		index = (index + 1) % files.size()
	_last_file[sound] = index
	var stream: AudioStream = files[index]
	var i := _pick_voice(sound, entry.get("voices", 4), time)
	var voice := _voices[i]
	var spread: float = entry.get("pitch", 0.0)
	var db: float = entry.get("db", 0.0) + volume_db
	voice.stream = stream
	voice.bus = entry.get("bus", &"SFX")
	voice.unit_size = entry.get("unit", 6.0)
	voice.max_distance = reach
	voice.volume_db = db
	voice.max_db = db  # no louder than this, however close
	voice.pitch_scale = pitch * (1.0 + randf_range(-spread, spread))
	voice.global_position = at
	if audible():
		voice.play()
	_voice_sound[i] = sound
	_voice_start[i] = time
	_voice_end[i] = time + stream.get_length() / voice.pitch_scale


## A free voice; or, with `limit` of this sound already playing, the oldest
## of them; or the oldest voice of all.
func _pick_voice(sound: StringName, limit: int, time: float) -> int:
	var free := -1
	var same := 0
	var oldest_same := -1
	var oldest := 0
	for i in MAX_VOICES:
		if _voice_end[i] <= time:
			if free == -1:
				free = i
			continue
		if _voice_sound[i] == sound:
			same += 1
			if oldest_same == -1 or _voice_start[i] < _voice_start[oldest_same]:
				oldest_same = i
		if _voice_start[i] < _voice_start[oldest]:
			oldest = i
	if same >= limit:
		return oldest_same
	return free if free != -1 else oldest


func _play_pending() -> void:
	var time := now()
	for i in MAX_PENDING:
		if _pending_time[i] < 0.0 or _pending_time[i] > time:
			continue
		_pending_time[i] = -1.0
		var node := _pending_node[i]
		_pending_node[i] = null
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var at: Vector3 = node.call(&"ground_position") if node.has_method(&"ground_position") else node.global_position
		_play(_pending_sound[i], at, _pending_db[i], 1.0)


func _show_note(text: String) -> void:
	if _note == null:
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		_note = Label.new()
		_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_note.position.y = 80.0
		_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_note.add_theme_font_size_override("font_size", 20)
		_note.add_theme_constant_override("outline_size", 6)
		_note.add_theme_color_override("font_outline_color", Color.BLACK)
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_note)
	_note.text = text
	_note.visible = true
	_note_time = NOTE_TIME


## The bus layout normally comes from default_bus_layout.tres; this only
## fills in buses that are missing.
func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")


## Seconds since the game started, in real time (hit stops slow the game,
## not its sound).
static func now() -> float:
	return Time.get_ticks_msec() * 0.001
