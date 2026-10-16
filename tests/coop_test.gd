extends Node
## Headless check of co-op, over ENet on this machine (WebRTC needs a browser;
## everything above the connection is the same). Run it once: it hosts a game,
## starts a second copy of the game that joins, and checks that each sees the
## other's hero in the right place, that the host's thugs show up for the
## joined player and hurt them, and that the joined player's punches take the
## host's thugs down. The joined copy sends its results back before leaving.
## Run: godot --headless --path . res://tests/coop_test.tscn

const PORT := 8071
## Across the city from the host: the Bronx, by Yankee Stadium (world meters).
const FAR_SPOT := Vector3(4998.0, 150.0, -7700.0)
## How close a hero copy must be to where its player says the hero is (m).
const POSITION_TOLERANCE := 0.5

var _role := "host"
var _world: Node
var _hero: Hero
var _players: PlayerSync
var _encounters: EncounterDirector
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _results: Array[String] = []
var _failures := 0
var _client_pid := 0
var _client_log := ""
var _client_report: Array = []
var _gang: Array[Thug] = []
var _position_checked := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	for node_name in ["PlayerInput", "Crowd"]:
		_world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_players = _world.get_node("Players")
	_encounters = _world.get_node("Encounters")
	_encounters.max_gangs = 0  # only the gang this test puts down
	# Run before the hero each tick so the scripted input is used right away.
	process_physics_priority = -20
	_steps = _host_steps() if _role == "host" else _client_steps()


func _host_steps() -> Array[Dictionary]:
	return [
		_step("host, and start a second game that joins", 40.0, func() -> void:
			if Net.host_enet(PORT) != OK:
				_fail("couldn't host on port %d" % PORT)
			_client_log = ProjectSettings.globalize_path("user://coop_test_client.log")
			var client_args := ["--headless", "--log-file", _client_log, "--path", ProjectSettings.globalize_path("res://"),
				"res://tests/coop_test.tscn", "--", "--role=client"]
			if LaunchOptions.has("tiles"):  # the same city as ours
				client_args.append("--tiles=" + LaunchOptions.get_string("tiles"))
			_client_pid = OS.create_process(OS.get_executable_path(), client_args),
			func() -> bool: return Net.peers().size() == 1),
		_step("their hero appears next to ours", 30.0, Callable(), func() -> bool:
			var other := _other_hero()
			return other != null and not other.frozen and other.global_position.distance_to(_hero.global_position) < 10.0),
		_step("both sides agree where the heroes are", 10.0, Callable(), func() -> bool: return _position_checked),
		_step("step away and put a gang next to them", 1.0, func() -> void:
			var other := _other_hero()
			_hero.global_position += Vector3(0.0, 0.0, 80.0)  # out of the thugs' sight
			var along := Vector3(1.0, 0.0, 0.0)
			_gang = _encounters.spawn_gang(other.world_position() + Vector3(0.0, 0.0, -5.0), 3, along, other)),
		_step("their punches take our thugs down", 45.0, Callable(), func() -> bool:
			return _gang.all(func(thug: Thug) -> bool: return not is_instance_valid(thug) or thug.is_down())),
		_step("a gang shows up where they went", 60.0, func() -> void: _encounters.max_gangs = 1, func() -> bool:
			var other := _other_hero()
			if other == null or other.global_position.distance_to(_hero.global_position) < 1000.0:
				return false
			return Combat.thugs.any(func(thug: Thug) -> bool:
				return not thug.is_down() and thug.global_position.distance_to(other.global_position) < 150.0)),
		_step("they report back", 20.0, Callable(), func() -> bool: return not _client_report.is_empty()),
		_step("their hero goes away when they leave", 10.0, Callable(), func() -> bool:
			return _players.remote_heroes.is_empty()),
	]


func _client_steps() -> Array[Dictionary]:
	return [
		_step("join the host", 20.0, func() -> void:
			if Net.join_enet("127.0.0.1", PORT) != OK:
				_fail("couldn't start joining"),
			func() -> bool: return Net.state == Net.State.JOINED),
		_step("we're placed next to the host's hero", 30.0, Callable(), func() -> bool:
			var other := _other_hero()
			return other != null and not _hero.frozen and other.global_position.distance_to(_hero.global_position) < 10.0),
		_step("both sides agree where the heroes are", 3.0, func() -> void:
			_check_position.rpc(_hero.world_position()),
			func() -> bool: return _time > 1.0),
		_step("the host's thugs show up", 20.0, Callable(), func() -> bool:
			return _standing_thugs().size() >= 3),
		_step("the host's thugs hurt our hero", 20.0, Callable(), func() -> bool:
			return _hero.health < Hero.MAX_HEALTH),
		_step("our punches take them down", 45.0, Callable(), func() -> bool:
			return _standing_thugs().is_empty() and Combat.defeated_count >= 3),
		_step("travel across the city", 30.0, func() -> void:
			_hero.global_position = WorldOrigin.to_local(FAR_SPOT)
			_hero.velocity = Vector3.ZERO
			_hero.frozen = true,  # until the ground there loads
			func() -> bool: return _time > 0.5 and not _hero.frozen),
		_step("the host's thugs show up over there", 60.0, Callable(), func() -> bool:
			return _standing_thugs().any(func(thug: Thug) -> bool:
				return thug.global_position.distance_to(_hero.global_position) < 150.0)),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	if _role == "client" and step.name == "our punches take them down":
		_punch_nearest_thug()
	var done: bool = step.until.call() if step.until.is_valid() else _time >= step.seconds
	if not done:
		if _time < step.seconds:
			return
		_fail("%s: timed out after %.0f s" % [step.name, step.seconds])
	else:
		_results.append("ok    %-45s %5.1f s" % [step.name, _time])
	if _index + 1 < _steps.size():
		_begin(_index + 1)
		return
	set_physics_process(false)
	_finish()


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	if _steps[index].start.is_valid():
		_steps[index].start.call()


func _finish() -> void:
	if _role == "client":
		_report.rpc_id(Net.HOST_ID, _results, _failures)
		await get_tree().create_timer(1.0).timeout
		Net.leave()
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(1 if _failures else 0)
		return
	print("host:")
	for line in _results:
		print("  " + line)
	print("joined player:")
	for line: String in (_client_report[0] if _client_report.size() > 0 else ["(no report)"]):
		print("  " + line)
	var total: int = _failures + (int(_client_report[1]) if _client_report.size() > 1 else 1)
	if total and FileAccess.file_exists(_client_log):
		print("joined player's log:\n" + FileAccess.get_file_as_string(_client_log))
	if _client_pid and OS.is_process_running(_client_pid):
		OS.kill(_client_pid)
	print("co-op test finished: %d problems" % total)
	get_tree().quit(1 if total else 0)


func _fail(text: String) -> void:
	_failures += 1
	_results.append("FAIL  " + text)


func _other_hero() -> Hero:
	return _players.remote_heroes.values().front() if not _players.remote_heroes.is_empty() else null


func _standing_thugs() -> Array[Thug]:
	return Combat.thugs.filter(func(thug: Thug) -> bool: return not thug.is_down())


## Keeps tapping attack, turned toward the nearest standing thug.
func _punch_nearest_thug() -> void:
	var input := _hero.input
	input.clear()
	var thugs := _standing_thugs()
	if thugs.is_empty():
		return
	thugs.sort_custom(func(a: Thug, b: Thug) -> bool:
		return a.global_position.distance_to(_hero.global_position) < b.global_position.distance_to(_hero.global_position))
	var offset := thugs[0].global_position - _hero.global_position
	input.aim = Vector3(offset.x, 0.0, offset.z).normalized()
	input.attack_held = fmod(_time, 0.3) < 0.15


func _step(step_name: String, seconds: float, start := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, start = start, until = until}


## Tells the other side where our hero is (standing still); it checks that its
## copy of our hero is there too.
@rpc("any_peer", "call_remote", "reliable")
func _check_position(world_position: Vector3) -> void:
	if _role == "host":
		_check_position.rpc_id(multiplayer.get_remote_sender_id(), _hero.world_position())
	await get_tree().create_timer(0.5).timeout
	var other := _other_hero()
	var error := other.world_position().distance_to(world_position) if other else INF
	if error > POSITION_TOLERANCE:
		_fail("our copy of the other hero is %.2f m from where it really is" % error)
	else:
		_results.append("ok    %-45s %.2f m off" % ["our copy of the other hero is in place", error])
	_position_checked = true


@rpc("any_peer", "call_remote", "reliable")
func _report(results: Array, failures: int) -> void:
	_client_report = [results, failures]
