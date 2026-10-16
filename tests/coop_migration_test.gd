extends Node
## Headless check of co-op as players come and go, the host too: four copies
## of the game in one room, through the signaling server (tools/signaling,
## Node.js) and over ENet on this machine, like coop_test.
##   - A hosts; B and C join; A puts a gang of thugs by them.
##   - A's game is closed (killed, so nothing says goodbye). B, in the room
##     longest after A, becomes the host and runs A's thugs; C keeps its
##     copies of the same thugs. Nobody has a thug twice; the thugs, run by B
##     now, hurt C, and C's punches, applied by B, take them down.
##   - The connection between B and C drops (both stay in the room); B, with
##     the lower number, connects again through the server.
##   - D joins with the same room code (and gets A's number, free again); B
##     puts a new gang by D, and D's punches take it down.
##   - C leaves; B and D play on.
##   - B's game stops answering, as if its network went (nothing closes): once
##     D has reported losing it and it has stopped pinging, the server drops
##     it and D becomes the host, running the thugs it had copies of.
## Each game checks that its copies of the others' heroes are where they are.
## This copy of the test starts the server and the four games, and closes A's;
## the games go step by step together through files in a scratch folder, and
## leave their results there.
## Run: godot --headless --path . res://tests/coop_migration_test.tscn [-- --port=8071]
## (--port: the signaling server's; other options, e.g. --tiles, go to the games)

const SignalingServer := preload("res://tests/signaling_server.gd")
## The signaling server's port, unless --port=N says otherwise.
const DEFAULT_PORT := 8071
const ROLES: Array[String] = ["a", "b", "c", "d"]
## How close a hero copy must be to where its player says the hero is (m).
const POSITION_TOLERANCE := 0.5
## Players who join appear about this close to the host's hero (m).
const PLACED_NEAR := 15.0

var _role := ""  # empty for the copy that runs the others
var _port := DEFAULT_PORT
var _run_dir := ""
var _room := ""
var _server := SignalingServer.new()
var _pids := {}  # role -> process id
var _world: Node
var _hero: Hero
var _players: PlayerSync
var _encounters: EncounterDirector
var _hud: GameHud
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _results: Array[String] = []
var _failures := 0
var _notices := PackedStringArray()  # every co-op notice shown so far
var _checked := {}  # phase -> {player number: true}: copies whose position we checked
var _gang: Array = []  # the thugs we're watching: a gang we put down, or copies we saw
var _gang_ids: Array = []  # their numbers, sorted
var _first_gang_ids: Array = []
var _hurts := 0
var _connection_closed := {}  # player number -> true: our connection to them closed at some point


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
	LaunchOptions.set_default("signal", "ws://127.0.0.1:%d" % _port)
	LaunchOptions.set_default("net", "enet")  # (it drops ENet connections on purpose)
	# Run before the hero each tick so the scripted input is used right away.
	process_physics_priority = -20
	if _role.is_empty():
		_run_dir = ProjectSettings.globalize_path("user://coop_migration_test_%d" % OS.get_process_id())
		DirAccess.make_dir_recursive_absolute(_run_dir)
		_steps = _runner_steps()
		return
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	for node_name in ["PlayerInput", "Crowd"]:
		_world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_players = _world.get_node("Players")
	_encounters = _world.get_node("Encounters")
	_hud = _world.get_node("HUD/GameHud")
	_encounters.max_gangs = 0  # only the gangs this test puts down
	_hero.hurt.connect(func(_damage: float) -> void: _hurts += 1)
	Net.player_left.connect(func(id: int) -> void: _connection_closed[id] = true)
	match _role:
		"a":
			_steps = _a_steps()
		"b":
			_steps = _b_steps()
		"c":
			_steps = _c_steps()
		"d":
			_steps = _d_steps()


func _runner_steps() -> Array[Dictionary]:
	return [
		_step("start the co-op server on port %d" % _port, 10.0, func() -> void:
			var problem := _server.start(_port)
			if problem:
				_fail(problem),
			func() -> bool: return _server.is_up()),
		_step("A hosts a game", 60.0, _launch.bind("a"), func() -> bool: return _flag("a", "room")),
		_step("B joins it", 60.0, func() -> void:
			_room = _read("a", "room")
			_launch("b"),
			func() -> bool: return _flag("b", "joined")),
		_step("C joins too, and A puts a gang by them", 90.0, _launch.bind("c"), func() -> bool:
			return _flags(["b", "c"], "saw_thugs") and _flag("a", "results")),
		_step("close A's game; B and C play on", 120.0, func() -> void: OS.kill(_pids.a), func() -> bool:
			return _flag("c", "fought")),
		_step("D joins with the same room code; the rest plays out", 300.0, _launch.bind("d"), func() -> bool:
			return ["b", "c", "d"].all(func(role: String) -> bool: return _flag(role, "results"))),
	]


func _a_steps() -> Array[Dictionary]:
	return [
		_step("host a game", 10.0, Net.host, func() -> bool: return Net.state == Net.State.HOSTING),
		_step("B and C join", 120.0, func() -> void: _raise("room", Net.room_code), _all_here.bind(2)),
		_agree_on_positions("p1", 2),
		_step("B and C have checked where we are", 20.0, Callable(), _flags.bind(["b", "c"], "p1")),
		_step("step away and put a gang by B and C", 1.0, func() -> void:
			var b: Hero = _players.remote_heroes[2]
			_step_away(80.0)  # out of the thugs' sight
			_watch(_encounters.spawn_gang(b.world_position() + Vector3(0.0, 0.0, -5.0), 3, Vector3.RIGHT, b))),
		_step("our game gets closed", 120.0, _write_results, func() -> bool: return false),
	]


func _b_steps() -> Array[Dictionary]:
	return [
		_step("join A's game as player 2", 30.0, Net.join.bind(_room), func() -> bool:
			return Net.state == Net.State.JOINED and Net.local_id() == 2),
		_step("we're placed by A's hero", 30.0, _raise.bind("joined"), _placed),
		_step("C joins too", 90.0, Callable(), _all_here.bind(2)),
		_agree_on_positions("p1", 2),
		_step("A's gang shows up by us", 30.0, Callable(), _gang_arrived),
		_step("A's game closes: we're the host now", 30.0, func() -> void:
			_first_gang_ids = _gang_ids.duplicate()
			_raise("saw_thugs", str(_gang_ids)),
			func() -> bool:
				return Net.state == Net.State.HOSTING and Net.host_id == 2 and _players.remote_heroes.keys() == [3] \
					and _notices.has("Player 1 left") and _notices.has("You're the host now")),
		_step("we run A's thugs now, the same ones, once each", 10.0, Callable(), _same_thugs.bind(false)),
		_step("step away from the thugs, so they go for C", 1.0, _step_away.bind(150.0)),  # past where they'd give up on us
		_step("C's punches (applied by us) take them down", 90.0, Callable(), _gang_down),
		_agree_on_positions("p2", 1, 1.5),
		_step("our connection to C drops, and we connect again", 30.0, Callable(), func() -> bool:
			return _connection_closed.has(3) and _all_here(1) and Net.state == Net.State.HOSTING),
		_step("D joins as player 1", 120.0, Callable(), func() -> bool:
			return _all_here(2) and _players.remote_heroes.has(1)),
		_agree_on_positions("p3", 2, 1.0),
		_step("C and D have checked where we are", 30.0, Callable(), _flags.bind(["c", "d"], "p3")),
		_step("step away and put a gang by D", 1.0, func() -> void:
			var d: Hero = _players.remote_heroes[1]
			_step_away(80.0)
			_watch(_encounters.spawn_gang(d.world_position() + Vector3(0.0, 0.0, -4.0), 3, Vector3.RIGHT, d))),
		_step("its thugs get numbers of our own", 1.0, Callable(), func() -> bool:
			return _gang_ids.all(func(id: int) -> bool:
				return id % EncounterDirector.ID_STRIDE == Net.local_id() and not _first_gang_ids.has(id))),
		_step("D's punches take the new gang down", 90.0, Callable(), _gang_down),
		_step("C leaves; D and we play on", 60.0, Callable(), func() -> bool:
			return _players.remote_heroes.keys() == [1] and Net.state == Net.State.HOSTING \
				and _notices.has("Player 3 left")),
		_step("our game stops answering, as if its network went", 300.0, func() -> void:
			_write_results()
			get_tree().multiplayer_poll = false
			Net.set_process(false),
			func() -> bool: return false),
	]


func _c_steps() -> Array[Dictionary]:
	return [
		_step("join A's game as player 3", 30.0, Net.join.bind(_room), func() -> bool:
			return Net.state == Net.State.JOINED and Net.local_id() == 3),
		_step("we're placed by A's hero", 30.0, Callable(), _placed),
		_step("we see A and B", 30.0, Callable(), _all_here.bind(2)),
		_agree_on_positions("p1", 2),
		_step("A's gang shows up by us", 30.0, Callable(), _gang_arrived),
		_step("A's game closes: B is the host now", 30.0, _raise.bind("saw_thugs"), func() -> bool:
			return Net.state == Net.State.JOINED and Net.host_id == 2 and _players.remote_heroes.keys() == [2] \
				and _notices.has("Player 1 left") and _notices.has("Player 2 is now the host")),
		_step("we keep our copies of the same thugs, once each", 8.0, Callable(), func() -> bool:
			# Past the time the new host waits for everyone's copies.
			return _time > EncounterDirector.HANDOVER_WAIT + 1.0 and _same_thugs(true)),
		_step("B's thugs come for us and hurt us", 30.0, func() -> void: _hurts = 0, func() -> bool:
			return _hurts > 0),
		_step("our punches (applied by B) take them down", 90.0, Callable(), func() -> bool:
			if not _gang_down():
				return false
			_raise("fought")
			return true, true),
		_agree_on_positions("p2", 1, 1.5),
		_step("B has checked where we are", 20.0, Callable(), _flags.bind(["b"], "p2")),
		_step("our connection to B drops (we both stay); B connects again", 30.0, func() -> void:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(2).peer_disconnect_now(),
			func() -> bool:
				return _connection_closed.has(2) and _all_here(1) and Net.state == Net.State.JOINED \
					and Net.host_id == 2 and not _notices.has("Player 2 left")),
		_step("D joins as player 1", 120.0, Callable(), func() -> bool:
			return _all_here(2) and _players.remote_heroes.has(1)),
		_agree_on_positions("p3", 2, 1.0),
		_step("D fights B's new gang", 120.0, Callable(), _flags.bind(["d"], "fought")),
		_step("leave the game", 1.0, Net.leave),
	]


func _d_steps() -> Array[Dictionary]:
	return [
		_step("join with A's room code, A gone", 30.0, Net.join.bind(_room), func() -> bool:
			return Net.state == Net.State.JOINED),
		_step("B hosts; we're player 1 (A's number)", 1.0, Callable(), func() -> bool:
			return Net.host_id == 2 and Net.local_id() == 1),
		_step("we're placed by B's hero", 30.0, Callable(), _placed),
		_step("we see B and C", 30.0, Callable(), _all_here.bind(2)),
		_agree_on_positions("p3", 2, 1.0),
		_step("B's gang shows up by us", 30.0, Callable(), _gang_arrived),
		_step("our punches take them down", 90.0, Callable(), func() -> bool:
			if not _gang_down():
				return false
			_raise("fought")
			return true, true),
		_step("C leaves; B and we play on", 60.0, Callable(), func() -> bool:
			return _players.remote_heroes.keys() == [2] and Net.host_id == 2 and _notices.has("Player 3 left")),
		_step("B stops answering: we're the host now", 150.0, func() -> void: _watch(Combat.thugs.duplicate()),
			func() -> bool:
				return Net.state == Net.State.HOSTING and _players.remote_heroes.is_empty() \
					and _notices.has("You're the host now")),
		_step("we run the thugs we had copies of, once each", 10.0, Callable(), _same_thugs.bind(false)),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	if _hud:
		for text in _hud.current_notices():
			if not _notices.has(text):
				_notices.append(text)
	if step.punch:
		_punch_nearest_thug()
	var done: bool = step.until.call() if step.until.is_valid() else _time >= step.seconds
	if not done:
		if _time < step.seconds:
			return
		_fail("%s: timed out after %.0f s" % [step.name, step.seconds])
	else:
		_results.append("ok    %-50s %5.1f s" % [step.name, _time])
	if _index + 1 < _steps.size():
		_begin(_index + 1)
		return
	set_physics_process(false)
	_finish()


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	if _hero:
		_hero.input.clear()
	if _steps[index].start.is_valid():
		_steps[index].start.call()


func _finish() -> void:
	if _role.is_empty():
		_finish_running()
		return
	_write_results()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if _failures else 0)


## The test's results, with every game's; their logs too if anything failed.
func _finish_running() -> void:
	for role in ROLES:
		var pid: int = _pids.get(role, 0)
		if pid and OS.is_process_running(pid):
			OS.kill(pid)
	_server.stop()
	var total := _failures
	print("test:")
	for line in _results:
		print("  " + line)
	for role in ROLES:
		print("player %s:" % role.to_upper())
		var report = JSON.parse_string(_read(role, "results")) if _flag(role, "results") else null
		if typeof(report) != TYPE_DICTIONARY:
			print("  (no report)")
			total += 1
			continue
		for line: String in report.lines:
			print("  " + line)
		total += int(report.failures)
	if total:
		for role in ROLES:
			print("player %s's log:\n%s" % [role.to_upper(), _read(role, "log")])
		print("(files in %s)" % _run_dir)
	else:
		await get_tree().create_timer(0.5).timeout  # until the games have let go of their logs
		for file in DirAccess.get_files_at(_run_dir):
			DirAccess.remove_absolute(_run_dir.path_join(file))
		DirAccess.remove_absolute(_run_dir)
	print("co-op migration test finished: %d problems" % total)
	get_tree().quit(1 if total else 0)


## Starts one of the games.
func _launch(role: String) -> void:
	var args := ["--headless", "--log-file", _run_dir.path_join(role + ".log"), "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/coop_migration_test.tscn", "--",
		"--role=" + role, "--run=" + _run_dir, "--room=" + _room]
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--role=") and not arg.begins_with("--run=") and not arg.begins_with("--room="):
			args.append(arg)  # --port, --tiles, ...
	_pids[role] = OS.create_process(OS.get_executable_path(), args)


## Leaves word for the other games (and the runner): a file named after us.
func _raise(flag: String, content := "") -> void:
	var path := _run_dir.path_join("%s.%s" % [_role, flag])
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	file.store_string(content)
	file.close()
	DirAccess.rename_absolute(path + ".part", path)


func _flag(role: String, flag: String) -> bool:
	return FileAccess.file_exists(_run_dir.path_join("%s.%s" % [role, flag]))


func _flags(roles: Array, flag: String) -> bool:
	return roles.all(func(role: String) -> bool: return _flag(role, flag))


func _read(role: String, flag: String) -> String:
	var path := _run_dir.path_join("%s.%s" % [role, flag])
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _write_results() -> void:
	_raise("results", JSON.stringify({lines = _results, failures = _failures}))


func _fail(text: String) -> void:
	_failures += 1
	_results.append("FAIL  " + text)


func _step(step_name: String, seconds: float, start := Callable(), until := Callable(), punch := false) -> Dictionary:
	return {name = step_name, seconds = seconds, start = start, until = until, punch = punch}


## Everyone tells the others where their hero is (`settle` seconds into the
## step, standing still); each game checks its copy of that hero.
func _agree_on_positions(phase: String, count: int, settle := 0.0) -> Dictionary:
	var told := [false]
	return _step("%s: we all agree where the heroes are" % phase, 20.0, Callable(), func() -> bool:
		if not told[0] and _time >= settle:
			told[0] = true
			_check_position.rpc(phase, _hero.world_position())
		if _checked.get(phase, {}).size() < count:
			return false
		_raise(phase)
		return true)


## `count` other players' heroes are here and moving.
func _all_here(count: int) -> bool:
	return _players.remote_heroes.size() == count \
		and _players.remote_heroes.values().all(func(other: Hero) -> bool: return not other.frozen)


## Our hero stands by the host's.
func _placed() -> bool:
	var host: Hero = _players.remote_heroes.get(Net.host_id)
	return host != null and not host.frozen and not _hero.frozen \
		and host.global_position.distance_to(_hero.global_position) < PLACED_NEAR


## Moves our hero south down the avenue, landing once the ground there loads
## (as the game places heroes).
func _step_away(meters: float) -> void:
	(_world as Game).place_hero(_hero.world_position() + Vector3(0.0, 0.0, meters), _hero.facing, true)


func _watch(thugs: Array) -> void:
	_gang = thugs
	_gang_ids = thugs.map(func(thug: Thug) -> int: return thug.net_id)
	_gang_ids.sort()


## Copies of a gang the host put down by us came: we watch them.
func _gang_arrived() -> bool:
	var standing := _standing_thugs()
	if standing.size() < 3:
		return false
	_watch(standing)
	return true


## Every thug we're watching is down (and still there: none was cleared away).
## (Untyped thugs: freed ones can't be passed as Thug.)
func _gang_down() -> bool:
	return _gang.all(func(thug: Variant) -> bool: return is_instance_valid(thug) and (thug as Thug).is_down())


## The thugs there are now are the ones we watched (the same nodes, each
## once), run by our game (copies false) or copies of the host's.
func _same_thugs(copies: bool) -> bool:
	var ids := Combat.thugs.map(func(thug: Thug) -> int: return thug.net_id)
	ids.sort()
	return ids == _gang_ids and _gang.all(func(thug: Variant) -> bool:
		return is_instance_valid(thug) and Combat.thugs.has(thug) and (thug as Thug).puppet == copies)


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


## Another player says where their hero is (standing still): our copy of it
## should be there too.
@rpc("any_peer", "call_remote", "reliable")
func _check_position(phase: String, world_position: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	await get_tree().create_timer(0.5).timeout
	var other: Hero = _players.remote_heroes.get(sender) if _players else null
	var error := other.world_position().distance_to(world_position) if other else INF
	var what := "%s: our copy of %s is in place" % [phase, Net.player_name(sender)]
	if error > POSITION_TOLERANCE:
		_fail("%s: our copy of %s is %.2f m from where it really is" % [phase, Net.player_name(sender), error])
	else:
		_results.append("ok    %-50s %.2f m off" % [what, error])
	_checked.get_or_add(phase, {})[sender] = true
