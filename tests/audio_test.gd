extends Node
## Headless check of the game's sound (with the dummy audio driver nothing is
## heard, but everything still plays): drives the hero through its moves and
## a fight in the real city, visits spots whose ambience differs (Times
## Square, Central Park by day and at night, the Hudson, high above
## Midtown), feeds fake traffic to GameAudio.set_traffic (Traffic paused
## meanwhile), switches the sound off and on, and prints what played. Ends
## with a list of checks.
## Run: godot --headless --path . res://tests/audio_test.tscn

const AVENUE := Vector3(0.485, 0.0, -0.875)
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const TIMES_SQUARE := Vector3(0.0, 15.0, 0.0)
## The Great Lawn in Central Park.
const CENTRAL_PARK := Vector3(1800.0, 40.0, -2700.0)
const HUDSON := Vector3(-2200.0, 5.0, 0.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")
const HERO_SCENE := preload("res://scenes/hero/hero.tscn")

var _world: Game
var _hero: Hero
var _city: CityStreamer
var _audio: GameAudio
var _traffic: Node
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _checks: Array[String] = []
var _failed := 0
var _counts_before := {}
var _spawned_at := -1.0
var _gang: Array[Thug] = []
## Ticks the passing cars weren't all given engines (once they had been).
var _engine_gaps := 0
var _copy: Hero
var _copy_swung := false


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_audio = _world.get_node("Audio")
	_traffic = _world.get_node("Traffic")
	_check_loop_transitions()
	process_physics_priority = -20
	_steps = [
		_step("wait for the city to load", 30.0, Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0),
		_step("Times Square by day", 3.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(TIMES_SQUARE)),
		_step("run along the avenue", 2.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
			_move(i)),
		_step("super speed", 3.0, func(i: HeroInput, _t: float) -> void:
			_move(i)
			i.sprint_held = true),
		_step("stop, tap jump", 2.5, func(i: HeroInput, t: float) -> void: i.jump_held = t > 1.0 and t < 1.1),
		_step("charge a super jump", 1.3, func(i: HeroInput, _t: float) -> void: i.jump_held = true),
		_step("super jump and land", 8.0, Callable(), func() -> bool: return _time > 1.0 and _hero.is_on_floor()),
		_step("web swing", 3.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
			i.aim = AVENUE
			i.web_held = t > 0.5 and t < 2.3),  # (once the camera, which hears, has caught up)
		_step("fly and boost", 4.0, func(i: HeroInput, t: float) -> void:
			i.fly_toggle_pressed = t == 0.0
			i.aim = AVENUE
			i.stick = Vector2(0.0, -1.0)
			i.vertical = 0.3
			i.sprint_held = t > 0.5),
		_step("dive slam", 6.0, func(i: HeroInput, t: float) -> void:
			i.aim = (AVENUE * 0.3 - Vector3.UP).normalized()
			i.attack_held = t < 0.1,
			func() -> bool: return _time > 0.5 and _hero.is_on_floor()),
		_step("thugs walk up, punch combos", 8.5, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
			elif _spawned_at < 0.0 and t >= 0.5:
				_spawned_at = t
				_spawn_gang(OPEN_AVENUE + AVENUE * 8.0, 4)
			i.aim = AVENUE
			i.attack_held = t > 2.5 and fmod(t, 0.3) < 0.12),
		_step("Central Park by day, walking", 4.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(CENTRAL_PARK)
			if t > 1.0:
				_move(i)),
		_step("Central Park at night", 4.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_world.time_of_day.set_clock(23.0)),
		_step("swimming in the Hudson", 4.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_world.time_of_day.set_clock(15.5)
				_teleport(HUDSON)
			if t > 1.5:
				_move(i)),
		_step("hovering 600 m over Midtown", 4.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_hero.set_mode(&"Flight")
				_hero.global_position = WorldOrigin.to_local(Vector3(0.0, 600.0, 0.0))
				_hero.velocity = Vector3.ZERO
			i.vertical = 0.0),
		_step("cars driving past", 3.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_hero.set_mode(&"OnFoot")
				_teleport(OPEN_AVENUE)
				# Only these cars: Traffic's own reports (of the real cars, ten
				# times a second) would take the engines off them.
				_traffic.process_mode = Node.PROCESS_MODE_DISABLED
			_report_traffic(t)),
		_step("another player's hero swings and slams", 2.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_traffic.process_mode = Node.PROCESS_MODE_INHERIT
			_drive_copy(t)),
		_step("sound off", 1.5, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_audio.set_muted(true)),
		_step("sound back on", 2.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_audio.set_muted(false)),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_index = 0
		_counts_before = _audio.play_counts.duplicate()
	var step := _steps[_index]
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)
	_time += delta
	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	_report(step.name)
	_index += 1
	_time = 0.0
	if _index >= _steps.size():
		print("\nChecks:")
		for line in _checks:
			print("  " + line)
		print("%d of %d checks passed" % [_checks.size() - _failed, _checks.size()])
		get_tree().quit(1 if _failed > 0 else 0)


## Abrupt speed/charge changes must glide in pitch, then settle on target;
## fading and lingering must still release the player and allow a restart.
func _check_loop_transitions() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = SoundBank.streams(&"air_low")[0]
	add_child(player)
	var voice := LoopVoice.new(player, -14.0, 0.2)
	voice.target = 1.0
	voice.update(1.0 / 60.0, 6.0)
	_check("a loop fades in below its full gain", voice.on and voice.gain > 0.0 and voice.gain < 0.15)
	voice.pitch = 1.5
	voice.update(1.0 / 60.0, 6.0)
	_check("a pitch change glides instead of jumping", player.pitch_scale > 1.0 and player.pitch_scale < 1.1)
	for i in 120:
		voice.update(1.0 / 60.0, 6.0)
	_check("pitch settles on the requested speed", absf(player.pitch_scale - 1.5) < 0.01)
	voice.target = 0.0
	for i in 60:
		voice.update(1.0 / 60.0, 6.0)
	_check("a quiet loop lingers before stopping", voice.on and voice.gain < LoopVoice.SILENT)
	for i in 30:
		voice.update(1.0 / 60.0, 6.0)
	_check("a faded loop releases its player", not voice.on)
	voice.target = 1.0
	voice.pitch = 0.9
	voice.update(1.0 / 60.0, 6.0)
	_check("a restarted loop uses its new pitch", voice.on and is_equal_approx(player.pitch_scale, 0.9))
	voice.silence()
	_check("muting stops a loop immediately", not voice.on and voice.gain == 0.0)
	player.queue_free()


func _report(step_name: String) -> void:
	var played := PackedStringArray()
	for sound: StringName in _audio.play_counts:
		var count: int = _audio.play_counts[sound] - int(_counts_before.get(sound, 0))
		if count > 0:
			played.append("%s x%d" % [sound, count])
	var new_counts := _audio.play_counts.duplicate()
	print("%-32s %4.1fs  played: %s\n%38s%s" % [step_name, _time, ", ".join(played) if not played.is_empty() else "-",
		"", _audio.status_text()])
	var beds := _audio.ambience.status_text()
	match step_name:
		"Times Square by day":
			_check("Times Square's traffic bed plays there", beds.contains("times_square"))
			_check("the day's street plays by day", beds.contains("traffic_day"))
		"run along the avenue":
			_check("footsteps on the avenue", _played("step_concrete", new_counts))
		"super speed":
			_check("super speed zooms", _played("zoom", new_counts))
		"stop, tap jump":
			_check("a jump", _played("jump", new_counts))
		"super jump and land":
			_check("a super jump launches", _played("launch", new_counts))
			_check("a landing", _played("land", new_counts) or _played("land_heavy", new_counts) or _played("slam", new_counts))
		"web swing":
			_check("a web thwips", _played("thwip", new_counts))
		"fly and boost":
			_check("flying takes off", _played("takeoff", new_counts))
			_check("the air rushes past", _loop_playing("air_low"))
		"dive slam":
			_check("a dive", _played("dive", new_counts))
			_check("a slam", _played("slam", new_counts))
		"thugs walk up, punch combos":
			_check("punches whoosh", _played("whoosh_punch", new_counts))
			_check("punches land", _played("punch", new_counts) or _played("punch_heavy", new_counts))
			_check("thugs go down", _played("thug_down", new_counts))
			_check("bodies fall", _played("body_fall", new_counts))
			_check("no spoken NPC calls", not _played("thug_shout", new_counts))
		"Central Park by day, walking":
			_check("birds in the park by day", beds.contains("birds"))
			_check("grass underfoot", _played("step_grass", new_counts))
		"Central Park at night":
			_check("crickets in the park at night", beds.contains("crickets"))
			_check("the night's street at night", beds.contains("traffic_night"))
		"swimming in the Hudson":
			_check("waves in the river", beds.contains("water"))
			_check("swim strokes", _played("swim", new_counts) or _played("splash", new_counts))
		"hovering 600 m over Midtown":
			_check("wind up high", beds.contains("wind"))
			_check("the city's far-off hum up high", beds.contains("city_far"))
			_check("no street up high", not beds.contains("traffic_day"))
		"cars driving past":
			_check("engines on passing cars", _audio.traffic.status_text().contains("4 engines") and _engine_gaps == 0)
		"another player's hero swings and slams":
			_check("another player's web thwips", _played("thwip", new_counts))
			_check("another player's slam", _played("slam", new_counts))
		"sound off":
			_check("nothing plays with the sound off", beds.contains("none"))
		"sound back on":
			_check("beds come back with the sound on", not beds.contains("none"))
	_counts_before = new_counts


func _played(sound: String, counts: Dictionary) -> bool:
	return int(counts.get(StringName(sound), 0)) > int(_counts_before.get(StringName(sound), 0))


func _loop_playing(sound: String) -> bool:
	var sounds := _hero.get_node("Sounds") as HeroSounds
	return sounds.loop_on(HeroSounds.LOOP_SOUNDS.find(StringName(sound)) as HeroSounds.Loop)


func _check(what: String, ok: bool) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		_failed += 1


## A copy of another player's hero 10 m away, driven the way PlayerSync
## drives one from the network: it swings, then lands hard.
func _drive_copy(t: float) -> void:
	if _copy == null:
		_copy = HERO_SCENE.instantiate()
		_copy.remote_id = 2
		_copy.frozen = true
		_world.get_node("Players").add_child(_copy)
		_copy.global_position = _hero.global_position + Vector3(AVENUE.z, 0.0, -AVENUE.x) * 10.0
		_copy.remote_grounded = true
	elif t > 0.3 and _copy.frozen:
		_copy.frozen = false
	elif t > 0.6 and not _copy_swung:
		_copy_swung = true
		_copy.remote_grounded = false
		_copy.set_mode(&"Swing", false)
	elif t > 1.2 and _copy.mode.name == &"Swing":
		_copy.set_mode(&"OnFoot", false)
		_copy.remote_grounded = true
		_copy.landed.emit(50.0)


## Five cars on the avenue around the hero, driving along it at 12 m/s (and
## a free slot, which doesn't count); the nearest four keep an engine each
## all along (after the first half second).
func _report_traffic(t: float) -> void:
	var positions := PackedVector3Array([_hero.world_position()])
	var speeds := PackedFloat32Array([-1.0])
	for k in 5:
		var along := -40.0 + 20.0 * k + 12.0 * t
		positions.append(_hero.world_position() + AVENUE * along + Vector3(AVENUE.z, 0.0, -AVENUE.x) * 4.0)
		speeds.append(12.0)
	GameAudio.set_traffic(positions, speeds)
	if t > 0.5 and not _audio.traffic.status_text().contains("4 engines"):
		_engine_gaps += 1


func _move(input: HeroInput) -> void:
	input.move = AVENUE
	input.stick = Vector2(0.0, -1.0)
	input.aim = AVENUE


func _spawn_gang(world_center: Vector3, count: int) -> void:
	for k in count:
		var thug: Thug = THUG_SCENE.instantiate()
		add_child(thug)
		var spot := world_center + Vector3(AVENUE.z, 0.0, -AVENUE.x) * (k - (count - 1) * 0.5) * 1.6
		spot.y = _hero.world_position().y
		var ground := _city.ground_height_at(spot, 6.0)
		if not is_nan(ground):
			spot.y = ground
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(_hero, k, TAU * k / count)
		_gang.append(thug)


## Moves the hero to a world position, standing on the ground there if there is any.
func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground) and ground > 0.5:
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until}
