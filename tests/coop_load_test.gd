extends Node
## Measures what other players far away cost a game in co-op: its frame time,
## physics time and memory, the city tiles it loads and the thugs it runs.
## A hosts a game at Times Square; it measures while alone, then once 3 more
## players have joined and gone to places across the city (Yankee Stadium,
## Wall Street, Downtown Brooklyn), then with 7 (also Long Island City,
## Flushing, Harlem and Park Slope). They join with the room code and go
## there themselves, so this runs against any version of the game. Each phase
## waits for the players to be in place and SETTLE seconds more (tiles load,
## gangs come), then samples SAMPLE seconds of frames. Headless, through the
## signaling server and over ENet on this machine, like coop_test. The
## players can also join a host in a browser (--role=client --room=CODE
## --spot=N --net=webrtc; the game's nodes are where the game has them).
## Run: godot --headless --path . res://tests/coop_load_test.tscn [-- --port=8071]
## (--port: the signaling server's; other options, e.g. --tiles, go to the games)

const SignalingServer := preload("res://tests/signaling_server.gd")
const DEFAULT_PORT := 8071
## Where the other players go (world meters; dropped onto the ground).
const SPOTS: Array[Vector3] = [
	Vector3(4998.0, 150.0, -7700.0),  # Yankee Stadium
	Vector3(-1965.0, 150.0, 5789.0),  # Wall Street
	Vector3(-405.0, 150.0, 7258.0),  # Downtown Brooklyn
	Vector3(3120.0, 150.0, 1481.0),  # Long Island City
	Vector3(13086.0, 150.0, -111.0),  # Flushing
	Vector3(3162.0, 150.0, -5733.0),  # Harlem, 125th Street
	Vector3(346.0, 150.0, 9685.0),  # Park Slope
]
const BATCHES: Array[int] = [3, 7]
## Others count as far once this far from our hero (m).
const FAR := 1500.0
const SETTLE := 30.0
const SAMPLE := 20.0

var _role := ""  # empty for the copy that runs the others
var _port := DEFAULT_PORT
var _run_dir := ""
var _room := ""
var _spot := -1
var _server := SignalingServer.new()
var _pids: Array[int] = []
var _world: Node
var _hero: Hero
var _players: PlayerSync
var _city: CityStreamer
var _phase := 0  # host: index into the phases (alone, then BATCHES)
var _phase_time := -1.0  # seconds into the current phase's settling (-1: waiting for the players)
var _frames := PackedFloat64Array()
var _process_ms := PackedFloat64Array()
var _physics_ms := PackedFloat64Array()
var _last_usec := 0
var _report: Array[String] = []
var _placed_by_host := false
var _placed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--run="):
			_run_dir = arg.trim_prefix("--run=")
		elif arg.begins_with("--room="):
			_room = arg.trim_prefix("--room=")
		elif arg.begins_with("--spot="):
			_spot = int(arg.trim_prefix("--spot="))
	LaunchOptions.set_default("signal", "ws://127.0.0.1:%d" % _port)
	LaunchOptions.set_default("net", "enet")
	if _role.is_empty():
		_run_dir = ProjectSettings.globalize_path("user://coop_load_test_%d" % OS.get_process_id())
		DirAccess.make_dir_recursive_absolute(_run_dir)
		_run()
		return
	_world = load("res://scenes/world.tscn").instantiate()
	# At the root, as in the game, so its nodes' paths (which RPCs go by) are
	# the game's: the host may be the game in a browser.
	get_tree().root.add_child.call_deferred(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_players = _world.get_node("Players")
	_city = _world.get_node("City")
	if _role == "client":
		_players.placed_by_host.connect(func(_at: Vector3, _facing: float) -> void: _placed_by_host = true)
		# Only what the host needs from us: our hero, where it is.
		for node_name in ["Crowd", "Traffic", "Trains"]:
			_world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
		Net.join(_room)
	else:
		Net.host()


## The runner: the server, the host, then the players in batches.
func _run() -> void:
	var problem := _server.start(_port)
	if problem:
		print("FAIL  " + problem)
		get_tree().quit(1)
		return
	while not _server.is_up():
		await get_tree().process_frame
	_launch(["--role=host"], "host")
	var room := await _wait_for("room", 120.0)
	var started := 0
	for batch in BATCHES.size():
		await _wait_for("batch%d" % batch, 900.0)
		if not _flag("batch%d" % batch):
			break
		while started < BATCHES[batch]:
			_launch(["--role=client", "--room=" + room, "--spot=%d" % started], "client%d" % started)
			started += 1
	await _wait_for("done", 900.0)
	print(FileAccess.get_file_as_string(_run_dir.path_join("done")))
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_server.stop()
	get_tree().quit()


func _launch(role_args: Array, log_name: String) -> void:
	var args := ["--headless", "--log-file", _run_dir.path_join(log_name + ".log"), "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/coop_load_test.tscn", "--", "--run=" + _run_dir]
	args.append_array(role_args)
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--role=") and not arg.begins_with("--run="):
			args.append(arg)  # --port, --tiles, ...
	_pids.append(OS.create_process(OS.get_executable_path(), args))


func _wait_for(flag: String, seconds: float) -> String:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not _flag(flag) and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.25).timeout
	return FileAccess.get_file_as_string(_run_dir.path_join(flag)) if _flag(flag) else ""


func _flag(flag: String) -> bool:
	return FileAccess.file_exists(_run_dir.path_join(flag))


func _raise(flag: String, content := "") -> void:
	var path := _run_dir.path_join(flag)
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	file.store_string(content)
	file.close()
	DirAccess.rename_absolute(path + ".part", path)


func _process(delta: float) -> void:
	if _role == "client":
		# Once in the game and placed by the host, go to our spot.
		if not _placed and _placed_by_host and not _hero.frozen:
			_placed = true
			(_world as Game).place_hero(SPOTS[_spot], 0.0, true)
		return
	if _role != "host":
		return
	if not Net.is_online():
		return
	if not _flag("room"):
		_raise("room", Net.room_code)
	var now := Time.get_ticks_usec()
	if _phase_time < 0.0:
		if _ready_for_phase():
			_phase_time = 0.0
			print("[load] phase %d: everyone in place; settling" % _phase)
		_last_usec = now
		return
	_phase_time += delta
	if _phase_time < SETTLE:
		_last_usec = now
		return
	_frames.append((now - _last_usec) / 1000.0)
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_last_usec = now
	if _phase_time < SETTLE + SAMPLE:
		return
	_report.append(_summary())
	print("[load] " + _report[-1])
	_frames.clear()
	_process_ms.clear()
	_physics_ms.clear()
	_phase_time = -1.0
	if _phase < BATCHES.size():
		_raise("batch%d" % _phase)
		_phase += 1
	else:
		_raise("done", "\n".join(_report))
		set_process(false)


## Alone: the city around us has loaded. Later: everyone of the batch is here,
## far off and standing on the ground there.
func _ready_for_phase() -> bool:
	if _phase == 0:
		return not _hero.frozen and _city.pending_count() == 0
	var count := BATCHES[_phase - 1]
	return _players.remote_heroes.size() == count and _players.remote_heroes.values().all(func(other: Hero) -> bool:
		return not other.frozen and other.global_position.distance_to(_hero.global_position) > FAR)


func _summary() -> String:
	var sorted := _frames.duplicate()
	sorted.sort()
	var others := 0 if _phase == 0 else BATCHES[_phase - 1]
	var standing := Combat.thugs.filter(func(thug: Thug) -> bool: return not thug.is_down()).size()
	return "%d others far off: %d frames, %.2f ms a frame (99th %.1f, max %.1f), process %.2f ms, physics %.2f ms, memory %d MB, %d near tiles, %d thugs (%d standing), %d nodes" % [
		others, _frames.size(), _mean(_frames), sorted[int(sorted.size() * 0.99)], sorted[-1], _mean(_process_ms),
		_mean(_physics_ms), OS.get_static_memory_usage() / 1000000, _city.loaded_counts[0], Combat.thugs.size(), standing,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]


static func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1)
