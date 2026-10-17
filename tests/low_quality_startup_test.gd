extends Node
## A saved Low choice applies before any populations are generated.
## Uses its own settings file, without altering the player's preferences.
## godot --headless --path . res://tests/low_quality_startup_test.tscn -- --tiles=DIR --solo=1

const SETTINGS_FILE := "user://low_quality_startup_test.cfg"
var _world: Game
var _problems := 0
var _peak_peds := 0
var _peak_cars := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var saved := ConfigFile.new()
	saved.set_value("settings", "quality", "low")
	saved.set_value("settings", "online_public", false)
	saved.save(SETTINGS_FILE)
	Settings.use_file(SETTINGS_FILE)
	get_tree().root.size = Vector2i(1920, 1080)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	var crowd := _world.get_node("Crowd") as CrowdManager
	var traffic := _world.get_node("Traffic") as Traffic
	var quality := _world.get_node("Quality") as Quality
	_check(Quality.choice() == "low" and Quality.level() == Quality.Level.LOW,
		"Saved Low must be selected without a --quality override")
	_check(crowd.max_pedestrians == 6 and crowd.plaza_crowd == 1.0 and traffic.max_cars == 12,
		"Low population limits must apply at startup")
	_check(traffic._path.size() == 12 and traffic._multimesh.instance_count == 12,
		"A Low start must allocate only twelve simulated car slots")
	var root := get_tree().root
	_check(root.size == Vector2i(1920, 1080) and is_equal_approx(root.scaling_3d_scale, 1.0 / 3.0),
		"Low must render a 1080p window at 360p while keeping its UI resolution")
	root.size = Vector2i(3840, 2160)
	quality._update_render_scale()
	_check(is_equal_approx(root.scaling_3d_scale, 1.0 / 6.0), "Low must also reach 360p on a 4K laptop display")
	root.size = Vector2i(5120, 2880)
	quality._update_render_scale()
	_check(is_equal_approx(root.scaling_3d_scale, 0.125), "The viewport must accept Low's one-eighth minimum scale")
	root.size = Vector2i(1920, 1080)
	quality._update_render_scale()
	var started := Time.get_ticks_msec()
	while _world.hero.frozen or _world.city.pending_count() > 0:
		await get_tree().create_timer(0.2).timeout
		if Time.get_ticks_msec() - started > 60000:
			_check(false, "Saved-Low city must finish loading")
			_finish()
			return
	await get_tree().create_timer(4.0).timeout
	_check(_peak_peds <= 6 and _peak_cars <= 12 and crowd.pedestrians.size() > 0 and traffic.car_count > 0,
		"Startup must generate a bounded, populated Low city (peaks %d peds, %d cars)" % [_peak_peds, _peak_cars])
	_check(_world.city.has_collision_at(_world.hero.world_position()), "Saved Low must still load the ground under the hero")
	_finish()


func _process(_delta: float) -> void:
	if _world == null:
		return
	_peak_peds = maxi(_peak_peds, _world.get_node("Crowd").pedestrians.size())
	_peak_cars = maxi(_peak_cars, _world.get_node("Traffic").car_count)


func _check(ok: bool, message: String) -> void:
	print(("ok: " if ok else "FAILED: ") + message)
	if not ok:
		_problems += 1


func _finish() -> void:
	# Release active routes through the normal tile-unload path before exit.
	var traffic := _world.get_node("Traffic") as Traffic
	for key: Vector2i in traffic.lanes.tiles.keys():
		traffic.set_tile_lanes(key, [] as Array[PackedVector3Array], PackedFloat32Array())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("saved Low startup: %d problems" % _problems)
	get_tree().quit(1 if _problems else 0)
