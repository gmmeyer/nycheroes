extends Node
## Headless check of co-op, through the signaling server (tools/signaling,
## Node.js) and over ENet on this machine (everything above the connection is
## the same as over WebRTC; --net=webrtc tests WebRTC, as desktop builds play,
## through the webrtc-native extension). Run it once: it starts the server, hosts
## a game, starts a second copy of the game that joins, and checks that each
## sees the other's hero in the right place, that the host's thugs show up for
## the joined player and hurt them, and that the joined player's punches take
## the host's thugs down. Then the joined player goes across the city: its own
## game puts gangs down there, and the host's runs none and loads no streets
## there; the host comes over, sees the joined player's gang (run by that
## game) and takes it down with punches that game applies. The joined copy
## sends its results back before leaving. See coop_migration_test for the host
## leaving, and coop_public_test for the public game.
## Run: godot --headless --path . res://tests/coop_test.tscn [-- --port=8071]
## (--port: the signaling server's; other options, e.g. --tiles, go to both games)

const SignalingServer := preload("res://tests/signaling_server.gd")
## The signaling server's port, unless --port=N says otherwise.
const DEFAULT_PORT := 8071
## Across the city from the host: the Bronx, by Yankee Stadium (world meters).
const FAR_SPOT := Vector3(4998.0, 150.0, -7700.0)
## How close a hero copy must be to where its player says the hero is (m).
const POSITION_TOLERANCE := 0.5

var _role := "host"
var _port := DEFAULT_PORT
var _room := ""
var _server := SignalingServer.new()
var _world: Node
var _hero: Hero
var _city: CityStreamer
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
var _far_since := -1.0  # (host) when the other hero was last seen arriving far off


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--room="):
			_room = arg.trim_prefix("--room=")
	LaunchOptions.set_default("signal", "ws://127.0.0.1:%d" % _port)
	LaunchOptions.set_default("net", "enet")
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	for node_name in ["PlayerInput", "Crowd"]:
		_world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_players = _world.get_node("Players")
	_encounters = _world.get_node("Encounters")
	_encounters.max_gangs = 0  # only the gang this test puts down
	# Run before the hero each tick so the scripted input is used right away.
	process_physics_priority = -20
	_steps = _host_steps() if _role == "host" else _client_steps()


func _host_steps() -> Array[Dictionary]:
	return [
		_step("start the co-op server on port %d" % _port, 10.0, func() -> void:
			var problem := _server.start(_port)
			if problem:
				_fail(problem),
			func() -> bool: return _server.is_up()),
		_step("host a game", 10.0, Net.host, func() -> bool: return Net.state == Net.State.HOSTING),
		_step("start a second game that joins", 40.0, func() -> void:
			_client_log = ProjectSettings.globalize_path("user://coop_test_client_%d.log" % _port)
			var args := ["--headless", "--log-file", _client_log, "--path", ProjectSettings.globalize_path("res://"),
				"res://tests/coop_test.tscn", "--", "--role=client", "--room=" + Net.room_code]
			for arg in OS.get_cmdline_user_args():
				if not arg.begins_with("--role=") and not arg.begins_with("--room="):
					args.append(arg)  # --port, --tiles, ...
			_client_pid = OS.create_process(OS.get_executable_path(), args),
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
		_step("they go across the city: we run no thugs there, nor load its streets", 60.0, Callable(), func() -> bool:
			var other := _other_hero()
			if other == null or other.frozen or other.global_position.distance_to(_hero.global_position) < 1000.0:
				_far_since = -1.0
				return false
			if _far_since < 0.0:
				_far_since = _time
			return _time - _far_since > 10.0 and _city.extra_foci.is_empty() \
				and not _city.has_collision_at(other.world_position()) \
				and Combat.thugs.all(func(thug: Thug) -> bool:
					return thug.global_position.distance_to(other.global_position) > 500.0)),
		_step("go over to them: their gang shows up for us, run by their game", 60.0, func() -> void:
			var other := _other_hero()
			(_world as Game).place_hero(other.world_position() + Vector3(4.0, 0.0, 0.0), other.facing, true),
			func() -> bool:
				_gang.assign(_standing_thugs().filter(func(thug: Thug) -> bool:
					return thug.puppet and thug.run_by == _other_id()))
				return not _hero.frozen and _gang.size() >= 3),
		_step("go up to it; our punches (applied by their game) take it down", 60.0, func() -> void:
			var center := Vector3.ZERO
			for thug in _gang:
				center += thug.global_position / _gang.size()
			(_world as Game).place_hero(WorldOrigin.to_world(center) + Vector3(0.0, 2.0, 2.5), _hero.facing, true),
			func() -> bool:
				return _gang.all(func(thug: Thug) -> bool: return not is_instance_valid(thug) or thug.is_down())),
		_step("they report back", 20.0, Callable(), func() -> bool: return not _client_report.is_empty()),
		_step("their hero goes away when they leave", 10.0, Callable(), func() -> bool:
			return _players.remote_heroes.is_empty()),
	]


func _client_steps() -> Array[Dictionary]:
	return [
		_step("join the host", 20.0, Net.join.bind(_room), func() -> bool: return Net.state == Net.State.JOINED),
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
		_step("our own gang shows up over there", 60.0, func() -> void: _encounters.max_gangs = 1, func() -> bool:
			_gang.assign(_standing_thugs().filter(func(thug: Thug) -> bool:
				return not thug.puppet and thug.global_position.distance_to(_hero.global_position) < 150.0))
			if _gang.size() < 3:
				return false
			_encounters.max_gangs = 0  # just that one
			return true),
		_step("the host comes over", 60.0, Callable(), func() -> bool:
			var other := _other_hero()
			return other != null and other.global_position.distance_to(_hero.global_position) < 200.0),
		_step("the host's punches (applied by us) take our gang down", 60.0, Callable(), func() -> bool:
			return _gang.all(func(thug: Thug) -> bool: return is_instance_valid(thug) and thug.is_down())),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	if step.name in ["our punches take them down", "go up to it; our punches (applied by their game) take it down"]:
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
		_report.rpc_id(Net.host_id, _results, _failures)
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
	_server.stop()
	print("co-op test finished: %d problems" % total)
	get_tree().quit(1 if total else 0)


func _fail(text: String) -> void:
	_failures += 1
	_results.append("FAIL  " + text)


func _other_hero() -> Hero:
	return _players.remote_heroes.values().front() if not _players.remote_heroes.is_empty() else null


func _other_id() -> int:
	return _players.remote_heroes.keys().front() if not _players.remote_heroes.is_empty() else 0


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
