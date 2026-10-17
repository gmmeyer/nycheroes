extends Node
## Headless check of the options menu and the settings behind it, in the
## real city at Times Square:
## - Settings: values are saved in the file as they change (read back by a
##   fresh ConfigFile and by reloading), `changed` comes once per real
##   change, and the old mute switch ([sound] muted) is moved in.
## - "high"'s preset (Quality.PRESETS) matches the scene the game starts with.
## - Quality: "Low" picked in the menu while playing applies at once (MSAA,
##   sun shadows, load distances, fog, pedestrians, cars, trains, gangs, and
##   built tiles' furniture, fronts and trees' shadows), then far tiles
##   unload to low's distances; "High" brings back the start's values, and
##   more cars and trains than low's come back in.
## - Volumes: the sliders set the buses at once and save once they stop; the
##   sound switch mutes Master; look speed and invert reach the camera.
## - The menu: O opens it and pauses the game (single player), O closes it;
##   M swaps it for the co-op menu, and so does its Co-op button: one menu at
##   a time, the hero's controls off while either is open; "Show FPS and
##   stats" and "Join the public game automatically" are saved.
## Uses a settings file of its own, not the player's.
## Run: godot --headless --path . res://tests/options_test.tscn -- --tiles=DIR

const SETTINGS_FILE := "user://options_test_settings.cfg"
const MAX_LOAD_WAIT := 60.0

var _world: Game
var _city: CityStreamer
var _options: OptionsPanel
var _coop: CoopPanel
var _quality: Quality
var _traffic: Traffic
var _trains: Trains
var _crowd: CrowdManager
var _encounters: EncounterDirector
var _camera: ThirdPersonCamera
var _time_of_day: TimeOfDay
var _input: PlayerInput
var _checks: Array[String] = []
var _failed := 0
var _changes := {}  # key -> how many times Settings.changed told of it


func _ready() -> void:
	_run()  # (pausable like the game: its timers run while paused)


func _run() -> void:
	_check_settings_file()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_options = _world.get_node("HUD/OptionsPanel")
	_coop = _world.get_node("HUD/CoopPanel")
	_quality = _world.get_node("Quality")
	_traffic = _world.get_node("Traffic")
	_trains = _world.get_node("Trains")
	_crowd = _world.get_node("Crowd")
	_encounters = _world.get_node("Encounters")
	_camera = _world.get_node("HeroCamera")
	_time_of_day = _world.get_node("TimeOfDay")
	_input = _world.get_node("PlayerInput")
	var started := Time.get_ticks_msec()
	while _city.loaded_counts[0] == 0 or _city.pending_count() > 0:
		await _wait(0.5)
		if Time.get_ticks_msec() - started > MAX_LOAD_WAIT * 1000.0:
			_check(false, "the city loaded")
			_finish()
			return
	await _wait(4.0)  # (cars, trains and pedestrians come in)
	_check_high_preset()
	await _check_quality()
	await _check_sound_and_look()
	await _check_menu()
	_finish()


func _check_settings_file() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_FILE)
	DirAccess.remove_absolute(path)
	var old := ConfigFile.new()
	old.set_value("sound", "muted", true)
	old.save(SETTINGS_FILE)
	Settings.use_file(SETTINGS_FILE)
	Settings.changed.connect(func(key: String) -> void: _changes[key] = _changes.get(key, 0) + 1)
	var saved := ConfigFile.new()
	saved.load(SETTINGS_FILE)
	_check(Settings.get_value("muted", false) == true and saved.get_value("settings", "muted", false) == true
		and not saved.has_section("sound"), "the old mute switch ([sound] muted) moved into [settings]")
	Settings.set_value("muted", false)
	Settings.set_value("look_mouse", 1.5)
	Settings.set_value("look_mouse", 1.5)
	saved.load(SETTINGS_FILE)
	_check(saved.get_value("settings", "look_mouse", 0.0) == 1.5 and _changes.get("look_mouse", 0) == 1,
		"set_value saves at once, and tells `changed` once per real change (%d)" % _changes.get("look_mouse", 0))
	Settings.use_file(SETTINGS_FILE)
	_check(is_equal_approx(float(Settings.get_value("look_mouse", 1.0)), 1.5) and Settings.get_value("muted", true) == false,
		"settings read back from the file")
	_check(Settings.get_value("nothing_here", 7) == 7, "a missing setting gives the default")
	Settings.set_value("look_mouse", 1.0)


## The scene at the start (a computer: "high") against PRESETS[HIGH].
func _check_high_preset() -> void:
	var high: Dictionary = Quality.PRESETS[Quality.Level.HIGH]
	var sun: DirectionalLight3D = _world.get_node("Sun")
	var props: CityProps = _city._props
	var root := get_tree().root
	var differences: Array[String] = []
	var compare := func(what: String, now: Variant, preset: Variant) -> void:
		var same := str(now) == str(preset)
		if typeof(now) == TYPE_FLOAT:  # (float32 in the engine)
			same = absf(now - float(preset)) <= absf(float(preset)) * 1e-5
		if not same:
			differences.append("%s %s, preset %s" % [what, now, preset])
	compare.call("level", Quality.level_name(), "high")
	compare.call("msaa", root.msaa_3d, ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d"))
	compare.call("scaling", root.scaling_3d_scale, 1.0)
	compare.call("shadows", sun.shadow_enabled, high.shadows)
	compare.call("shadow mode", sun.directional_shadow_mode, high.shadow_mode)
	compare.call("shadow distance", sun.directional_shadow_max_distance, high.shadow_distance)
	compare.call("tree shadows", props.tree_shadows, high.tree_shadows)
	compare.call("load distances", _city.load_distances, high.load_distances)
	compare.call("furniture fade", [props.small_furniture_fade, props.large_furniture_fade], high.furniture_fade)
	compare.call("car fade", props.car_fade, high.car_fade)
	compare.call("fronts", _city.fronts_range, high.fronts_range)
	compare.call("canopy", props.canopy_ranges, high.canopy_ranges)
	compare.call("fog", _time_of_day._fog, high.fog_density)
	compare.call("clear fog", Quality.clear_fog(), high.clear_fog)
	compare.call("pedestrians", _crowd.max_pedestrians, high.pedestrians)
	compare.call("busy crowd", _crowd.busy_crowd, high.busy_crowd)
	compare.call("plaza crowd", _crowd.plaza_crowd, high.plaza_crowd)
	compare.call("pedestrian range", _crowd.spawn_range, high.pedestrian_range)
	compare.call("pedestrian despawn", _crowd.despawn_distance, high.pedestrian_despawn)
	compare.call("cars", _traffic.max_cars, high.cars)
	compare.call("traffic minimum radius", _traffic.minimum_radius, high.traffic_min_radius)
	compare.call("trains", _trains.max_trains, high.trains)
	compare.call("gangs", _encounters.max_gangs, high.gangs)
	compare.call("gang size", _encounters.gang_size, high.gang_size)
	compare.call("bodies", _encounters.max_bodies, high.bodies)
	_check(differences.is_empty(), "the game starts as Quality.PRESETS' \"high\" says %s" % ", ".join(differences))


func _check_quality() -> void:
	var sun: DirectionalLight3D = _world.get_node("Sun")
	var root := get_tree().root
	var far_before := _city.loaded_counts[2]
	var cars_before := _traffic.car_count
	var peds_before := _crowd.pedestrians.size()
	_options.open()
	_options._quality_buttons[1].pressed.emit()  # Low
	var saved := ConfigFile.new()
	saved.load(SETTINGS_FILE)
	_check(Quality.level() == Quality.Level.LOW and saved.get_value("settings", "quality", "") == "low",
		"\"Low\" in the menu: the preset is low, and saved")
	_check(root.msaa_3d == Viewport.MSAA_DISABLED and not sun.shadow_enabled, "low: no MSAA, no sun shadows (at once)")
	_check(str(_city.load_distances) == str([250.0, 600.0, 4500.0]), "low: load distances %s" % [_city.load_distances])
	_check(is_equal_approx(_time_of_day._fog, 0.00022), "low: fog %s" % _time_of_day._fog)
	_check(_crowd.max_pedestrians == 6 and _crowd.plaza_crowd == 1.0 and _crowd.pedestrians.size() <= 6,
		"low: at most 6 actual pedestrians, including Times Square (%d before, %d now)" % [peds_before, _crowd.pedestrians.size()])
	_check(peds_before > 6 and cars_before > 12, "the downgrade started with more than Low's actor limits")
	_check(_traffic.max_cars == 12 and _traffic.car_count <= 12 and _traffic.radius <= 100.0,
		"low: at most 12 simulated cars in 100 m (%d before, %d now)" % [cars_before, _traffic.car_count])
	_check(_trains.max_trains == 1 and _trains.trains.size() <= 1, "low: at most 1 train (%d now)" % _trains.trains.size())
	_check(_encounters.max_gangs == 1 and _encounters.max_bodies == 6, "low: 1 gang, 6 bodies")
	var furniture := 0
	var right := 0
	var tree_shadows_shown := 0
	var fronts_right := true
	for tile_node in _city.get_children():
		var small := tile_node.get_node_or_null(^"SmallFurniture") as GeometryInstance3D
		if small:
			furniture += 1
			if is_equal_approx(small.visibility_range_end, 65.0 + CityProps.FURNITURE_RANGE_PAST_FADE):
				right += 1
		var shadows := tile_node.get_node_or_null(^"TreesShadows") as GeometryInstance3D
		if shadows and shadows.visible:
			tree_shadows_shown += 1
		var fronts := tile_node.get_node_or_null(^"Fronts") as GeometryInstance3D
		if fronts and not is_equal_approx(fronts.visibility_range_end, 150.0):
			fronts_right = false
	_check(furniture > 0 and right == furniture and tree_shadows_shown == 0 and fronts_right,
		"low: built tiles' furniture draws to low's range (%d of %d), no trees' shadows (%d shown), fronts to 150 m" % [
			right, furniture, tree_shadows_shown])
	_options.close()
	await _wait(6.0)
	_check(_city.loaded_counts[2] < far_before, "low: far tiles unload to 4.5 km (%d far tiles before, %d now)" % [
		far_before, _city.loaded_counts[2]])
	_check(_traffic.car_count > 0 and _traffic.car_count <= 12, "low: cars still drive (%d)" % _traffic.car_count)
	_check(_crowd.get_child_count() <= 6, "low: removed pedestrian nodes are freed, not merely hidden")
	_world.place_hero(Vector3(420.0, 3.0, -220.0), 0.0, true)
	var bounded := true
	for sample in 20:
		await _wait(0.2)
		bounded = bounded and _crowd.pedestrians.size() <= 6 and _traffic.car_count <= 12
	_check(bounded and not _world.hero.frozen and _city.has_collision_at(_world.hero.world_position()),
		"low: moving to another tile keeps generation capped and ground ready")
	_world.place_hero(Game.DEFAULT_SPAWN, 0.0, true)

	_options.open()
	_options._quality_buttons[3].pressed.emit()  # High
	_options.close()
	_check_high_preset()
	await _wait(8.0)
	var multimesh: MultiMesh = _traffic._multimesh
	_check(_traffic.car_count > 12 and multimesh.instance_count == 180,
		"high again: more than low's 12 cars come in (%d)" % _traffic.car_count)
	_check(_crowd.pedestrians.size() > 6, "high again: pedestrian generation recovers (%d)" % _crowd.pedestrians.size())
	_check(_trains._slots.size() == 4, "high again: room for 4 trains (%d running)" % _trains.trains.size())
	_check(_city.loaded_counts[2] >= far_before, "high again: far tiles load to 30 km again (%d)" % _city.loaded_counts[2])
	_options._quality_buttons[2].pressed.emit()  # Medium keeps its existing limits.
	_check(_crowd.max_pedestrians == 24 and _crowd.plaza_crowd == 1.5 and _traffic.max_cars == 90
		and _traffic.minimum_radius == 160.0 and _city.load_distances == [500.0, 1100.0, 12000.0],
		"medium keeps its original populations, radius, and load distances")
	_options._quality_buttons[0].pressed.emit()  # Auto: a computer's high
	_check(Quality.level() == Quality.Level.HIGH and Settings.get_value("quality", "") == "auto", "\"Auto\" on a computer is high")


func _check_sound_and_look() -> void:
	_options.open()
	var slider: HSlider = _options._sliders["volume_effects"]
	slider.value = 50.0
	var sfx := AudioServer.get_bus_index(&"SFX")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.25)),
		"the Effects slider at 50%% sets the SFX bus at once (%.1f dB)" % AudioServer.get_bus_volume_db(sfx))
	await _wait(0.6)
	_check(is_equal_approx(float(Settings.get_value("volume_effects", 1.0)), 0.5), "and saves once it stops")
	Settings.set_value("volume_ambience", 0.0)
	_check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Ambience")) <= SoundSettings.SILENT_DB,
		"Ambience at 0 silences its bus")
	Settings.set_value("volume_master", 0.8)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.64)), "Master at 80%% (%.1f dB)" % AudioServer.get_bus_volume_db(0))
	_options._sound.toggled.emit(false)
	_check(GameAudio.is_muted() and AudioServer.is_bus_mute(0) and Settings.get_value("muted", false) == true,
		"the Sound switch mutes Master, and is saved")
	_options._sound.toggled.emit(true)
	_check(not GameAudio.is_muted() and not AudioServer.is_bus_mute(0), "and turns it back on")
	for key: String in SoundSettings.VOLUMES:
		Settings.set_value(key, 1.0)
	var look: HSlider = _options._sliders["look_mouse"]
	look.value = 200.0
	_options.close()  # (saves at once)
	_check(is_equal_approx(_camera._look_scale, 2.0), "look speed 200%% reaches the camera (%.2f)" % _camera._look_scale)
	_options._invert.toggled.emit(true)
	_check(_camera._look_y < 0.0 and Settings.get_value("invert_y", false) == true, "invert reaches the camera")
	_options._invert.toggled.emit(false)
	Settings.set_value("look_mouse", 1.0)


func _check_menu() -> void:
	_check(not _options.visible and not get_tree().paused and _input.enabled, "no menu: the game runs, the hero listens")
	await _press(KEY_O)
	_check(_options.visible and get_tree().paused and not _input.enabled and not _traffic.can_process()
		and _options.can_process(), "O opens the options menu and pauses the game (not the menu)")
	await _press(KEY_O)
	_check(not _options.visible and not get_tree().paused and _input.enabled, "O again closes it and the game goes on")
	await _press(KEY_ESCAPE)
	_check(_options.visible, "Esc opens it too (desktop builds)")
	await _press(KEY_M)
	_check(_coop.visible and not _options.visible and not get_tree().paused and not _input.enabled,
		"M swaps it for the co-op menu (one menu at a time, not paused)")
	await _press(KEY_O)
	_check(_options.visible and not _coop.visible, "O swaps the co-op menu for the options menu")
	_options._open_coop()
	_check(_coop.visible and not _options.visible, "the Co-op button opens the co-op menu instead")
	await _press(KEY_ESCAPE)
	_check(not _coop.visible and not _options.visible and _input.enabled, "Esc closes the co-op menu")
	_options.open()
	var label: Control = _world.get_node("HUD/DebugLabel")
	_options._stats.toggled.emit(false)
	_check(not label.visible and Settings.get_value("show_stats", true) == false, "\"Show FPS and stats\" off hides the stats, saved")
	_options._stats.toggled.emit(true)
	_check(label.visible, "and on shows them")
	_options._public.toggled.emit(false)
	_check(Settings.get_value("online_public", true) == false, "\"Join the public game automatically\" off is saved (online_public)")
	_options._public.toggled.emit(true)
	_options._time_buttons[3].pressed.emit()
	_check(_time_of_day.phase_name() == "night", "Night while paused: the clock goes there at once (%s)" % _time_of_day.clock_text())
	_options.close()
	await _wait(0.2)


## A key press and release, as the keyboard sends them.
func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _wait(0.05)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok      " if ok else "FAILED  ") + what)
	if not ok:
		_failed += 1


func _finish() -> void:
	if _traffic:
		# Release active routes through the normal tile-unload path before exit.
		for key: Vector2i in _traffic.lanes.tiles.keys():
			_traffic.set_tile_lanes(key, [] as Array[PackedVector3Array], PackedFloat32Array())
	print("\n".join(_checks))
	print("%d checks, %d failed" % [_checks.size(), _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	get_tree().paused = false
	get_tree().quit(1 if _failed else 0)
