extends Node
## Headless check of co-op games outliving the signaling server (a Worker
## deploy restarts the Durable Object and closes every socket): four copies of
## the game, through the signaling server (tools/signaling, Node.js) and over
## ENet on this machine, like coop_test.
##   - A hosts; B and C join.
##   - The server is killed mid-game. The games stay in their room (same
##     code, numbers and host) and play on: the heroes still agree where they
##     are, A puts a gang by B, and B's punches, applied by A, take it down.
##     After a few seconds (not before), the menu says it's reconnecting.
##   - The server starts again. B and C come back to the room, as the same
##     players, nobody having left; A holds off (its game paused, say), so
##     the server rebuilds the room from what B and C say, keeping A's place.
##   - D joins with the room code before A is back: it gets number 4 (A's is
##     kept), and once A is back, A, still the host, connects to D and places
##     it by its hero.
##   - A's own socket to the server drops (its game goes on): the server lets
##     A go and names B, in the room longest after A, the host; B runs A's
##     thugs. A comes back as player 1, now in B's game, and the others
##     connect to it again.
##   - B's game is closed: C becomes the host (in the room longer than A, who
##     came back after it) and runs the thugs; A and D follow.
## Each game checks that its copies of the others' heroes are where they are.
## This copy of the test runs the server (stopping and starting it) and the
## four games, and closes B's; the games go step by step together through
## files in a scratch folder, and leave their results there.
## Run: godot --headless --path . res://tests/coop_reconnect_test.tscn [-- --port=8071]
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
var _dropped_msec := 0  # when we saw the signaling server go
var _reconnecting_after := -1.0  # seconds from then until the menu said we're reconnecting


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
	# Run before the hero each tick so the scripted input is used right away.
	process_physics_priority = -20
	if _role.is_empty():
		_run_dir = ProjectSettings.globalize_path("user://coop_reconnect_test_%d" % OS.get_process_id())
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
	_encounters.max_gangs = 0  # only the gang this test puts down
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
		_step("start the co-op server on port %d" % _port, 10.0, _start_server, func() -> bool: return _server.is_up()),
		_step("A hosts a game", 60.0, _launch.bind("a"), func() -> bool: return _flag("a", "room")),
		_step("B joins it", 60.0, func() -> void:
			_room = _read("a", "room")
			_launch("b"),
			func() -> bool: return _flag("b", "joined")),
		_step("C joins too", 90.0, _launch.bind("c"), _flags.bind(["a", "b", "c"], "p1")),
		_step("stop the co-op server mid-game; the games play on", 120.0, _server.stop,
			_flags.bind(["a", "b", "c"], "outage_ok")),
		_step("start it again; B and C come back to the room", 60.0, _start_server, func() -> bool:
			return _server.is_up() and _flags(["b", "c"], "back")),
		_step("D joins with the room code before A is back", 120.0, _launch.bind("d"),
			_flags.bind(["a", "b", "c", "d"], "p3")),
		_step("A's socket drops: B hosts, and A comes back", 120.0, Callable(), _flags.bind(ROLES, "p4")),
		_step("close B's game; C hosts; the rest plays out", 120.0, func() -> void: OS.kill(_pids.b), func() -> bool:
			return ["a", "c", "d"].all(func(role: String) -> bool: return _flag(role, "results"))),
	]


func _a_steps() -> Array[Dictionary]:
	return [
		_step("host a game", 10.0, Net.host, func() -> bool: return Net.state == Net.State.HOSTING),
		_step("B and C join", 120.0, func() -> void:
			_room = Net.room_code
			_raise("room", Net.room_code),
			_all_here.bind(2)),
		_agree_on_positions("p1", 2),
		_step("the co-op server goes; we play on, hosting the same room", 30.0, Callable(), _in_room_without_server),
		_agree_on_positions("p2", 2, 0.5),
		_step("step away and put a gang by B", 1.0, func() -> void:
			var b: Hero = _players.remote_heroes[2]
			_step_away(80.0)  # out of the thugs' sight
			_watch(_encounters.spawn_gang(b.world_position() + Vector3(0.0, 0.0, -5.0), 3, Vector3.RIGHT, b))),
		_step("B's punches (applied by us) take them down", 90.0, Callable(), _gang_down),
		_step("nobody has left, and we still host", 1.0, Callable(), func() -> bool:
			return _notices.is_empty() and Net.state == Net.State.HOSTING and _players.remote_heroes.size() == 2),
		_step("we hold off coming back (paused) until D is in", 180.0, func() -> void:
			_raise("outage_ok")
			Net.set_process(false),
			_flag.bind("d", "in_room")),
		_step("we come back: still the host, and D connects to us", 30.0, Net.set_process.bind(true), func() -> bool:
			return Net.has_signaling() and Net.state == Net.State.HOSTING and Net.room_code == _room \
				and _all_here(3) and _players.remote_heroes.has(4)),
		_agree_on_positions("p3", 3, 1.0),
		_step("B, C and D have checked where we are", 30.0, Callable(), _flags.bind(["b", "c", "d"], "p3")),
		_step("our socket to the server drops: B hosts, and we're back as player 1", 30.0, func() -> void:
			Net._signaling.close(),  # (as if our network blinked; the game goes on)
			func() -> bool:
				return Net.has_signaling() and Net.state == Net.State.JOINED and Net.host_id == 2 \
					and Net.local_id() == 1 and _all_here(3) and _notices.has("Player 2 is now the host")),
		_step("B's copies of our thugs replace ours", 10.0, Callable(), func() -> bool:
			var ids := Combat.thugs.map(func(thug: Thug) -> int: return thug.net_id)
			ids.sort()
			return ids == _gang_ids and Combat.thugs.all(func(thug: Thug) -> bool: return thug.puppet)),
		_agree_on_positions("p4", 3, 1.0),
		_step("B's game closes: C is the host now (in the room longer than us)", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.JOINED and Net.host_id == 3 and _sorted_players() == [3, 4] \
				and _notices.has("Player 2 left") and _notices.has("Player 3 is now the host")),
		_agree_on_positions("p5", 2, 0.5),
		_step("C and D have checked where we are", 30.0, Callable(), _flags.bind(["c", "d"], "p5")),
	]


func _b_steps() -> Array[Dictionary]:
	return [
		_step("join A's game as player 2", 30.0, Net.join.bind(_room), func() -> bool:
			return Net.state == Net.State.JOINED and Net.local_id() == 2),
		_step("we're placed by A's hero", 30.0, _raise.bind("joined"), _placed),
		_step("C joins too", 90.0, Callable(), _all_here.bind(2)),
		_agree_on_positions("p1", 2),
		_step("the co-op server goes; we play on in the same room", 30.0, Callable(), _in_room_without_server),
		_agree_on_positions("p2", 2, 0.5),
		_step("A's gang shows up by us", 30.0, Callable(), _gang_arrived),
		_step("our punches (applied by A) take them down", 90.0, Callable(), _gang_down, true),
		_reconnecting_shown(),
		_step("the server's back: we're in the room again, as before", 60.0, _raise.bind("outage_ok"), func() -> bool:
			return _back_in_room(1)),
		_step("D joins as player 4 (A, away, keeps number 1)", 120.0, _raise.bind("back"), func() -> bool:
			return _all_here(3) and _players.remote_heroes.has(4)),
		_agree_on_positions("p3", 3, 1.0),
		_step("A's socket drops, so the server lets A go: we're the host now", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.HOSTING and Net.host_id == 2 \
				and _notices.has("Player 1 left") and _notices.has("You're the host now")),
		_step("we run A's thugs now, the same ones, once each", 10.0, Callable(), _same_thugs.bind(false)),
		_step("A comes back (player 1): we see A, C and D", 30.0, Callable(), func() -> bool:
			return _all_here(3) and _sorted_players() == [1, 3, 4]),
		_agree_on_positions("p4", 3, 1.0),
		_step("our game gets closed", 120.0, _write_results, func() -> bool: return false),
	]


func _c_steps() -> Array[Dictionary]:
	return [
		_step("join A's game as player 3", 30.0, Net.join.bind(_room), func() -> bool:
			return Net.state == Net.State.JOINED and Net.local_id() == 3),
		_step("we're placed by A's hero", 30.0, Callable(), _placed),
		_step("we see A and B", 30.0, Callable(), _all_here.bind(2)),
		_agree_on_positions("p1", 2),
		_step("the co-op server goes; we play on in the same room", 30.0, Callable(), _in_room_without_server),
		_agree_on_positions("p2", 2, 0.5),
		_step("A's gang shows up by us", 30.0, Callable(), _gang_arrived),
		_step("B's punches take them down", 90.0, Callable(), _gang_down),
		_reconnecting_shown(),
		_step("the server's back: we're in the room again, as before", 60.0, _raise.bind("outage_ok"), func() -> bool:
			return _back_in_room(1)),
		_step("D joins as player 4", 120.0, _raise.bind("back"), func() -> bool:
			return _all_here(3) and _players.remote_heroes.has(4)),
		_agree_on_positions("p3", 3, 1.0),
		_step("A's socket drops, so the server lets A go: B is the host now", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.JOINED and Net.host_id == 2 \
				and _notices.has("Player 1 left") and _notices.has("Player 2 is now the host")),
		_step("we keep our copies of the same thugs, once each", 8.0, Callable(), func() -> bool:
			# Past the time the new host waits for everyone's copies.
			return _time > EncounterDirector.HANDOVER_WAIT + 1.0 and _same_thugs(true)),
		_step("A comes back (player 1): we see A, B and D", 30.0, Callable(), func() -> bool:
			return _all_here(3) and _sorted_players() == [1, 2, 4]),
		_agree_on_positions("p4", 3, 1.0),
		_step("B's game closes: we're the host now (in the room longer than A)", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.HOSTING and Net.host_id == 3 and _sorted_players() == [1, 4] \
				and _notices.has("Player 2 left") and _notices.has("You're the host now")),
		_step("we run the thugs now, the same ones, once each", 10.0, Callable(), _same_thugs.bind(false)),
		_agree_on_positions("p5", 2, 0.5),
		_step("A and D have checked where we are", 30.0, Callable(), _flags.bind(["a", "d"], "p5")),
	]


func _d_steps() -> Array[Dictionary]:
	return [
		_step("join with the room code while A is away: player 4", 30.0, Net.join.bind(_room), func() -> bool:
			if Net.room_code != _room or Net.local_id() != 4:
				return false
			_raise("in_room")
			return Net.host_id == 1),
		_step("A comes back and connects to us: we're in its game", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.JOINED and Net.host_id == 1),
		_step("we're placed by A's hero", 30.0, Callable(), _placed),
		_step("we see A, B and C", 30.0, Callable(), _all_here.bind(3)),
		_agree_on_positions("p3", 3, 1.0),
		_step("A's socket drops, so the server lets A go: B is the host now", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.JOINED and Net.host_id == 2 \
				and _notices.has("Player 1 left") and _notices.has("Player 2 is now the host")),
		_step("A comes back (player 1): we see A, B and C", 30.0, Callable(), func() -> bool:
			return _all_here(3) and _sorted_players() == [1, 2, 3]),
		_agree_on_positions("p4", 3, 1.0),
		_step("B's game closes: C is the host now", 30.0, Callable(), func() -> bool:
			return Net.state == Net.State.JOINED and Net.host_id == 3 and _sorted_players() == [1, 3] \
				and _notices.has("Player 2 left") and _notices.has("Player 3 is now the host")),
		_agree_on_positions("p5", 2, 0.5),
		_step("A and C have checked where we are", 30.0, Callable(), _flags.bind(["a", "c"], "p5")),
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
	if _dropped_msec != 0 and _reconnecting_after < 0.0 and Net.is_reconnecting():
		_reconnecting_after = (Time.get_ticks_msec() - _dropped_msec) / 1000.0
	if step.punch:
		_punch_nearest_thug()
	var done: bool = step.until.call() if step.until.is_valid() else _time >= step.seconds
	if not done:
		if _time < step.seconds:
			return
		_fail("%s: timed out after %.0f s" % [step.name, step.seconds])
	else:
		_results.append("ok    %-55s %5.1f s" % [step.name, _time])
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
	print("co-op reconnect test finished: %d problems" % total)
	get_tree().quit(1 if total else 0)


func _start_server() -> void:
	var problem := _server.start(_port)
	if problem:
		_fail(problem)


## Starts one of the games.
func _launch(role: String) -> void:
	var args := ["--headless", "--log-file", _run_dir.path_join(role + ".log"), "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/coop_reconnect_test.tscn", "--",
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


## The signaling server is gone, but we're in our room as before: same code,
## same number, same host, and the menu doesn't say so yet.
func _in_room_without_server() -> bool:
	if Net.has_signaling() or not Net.is_online():
		return false
	_dropped_msec = Time.get_ticks_msec()
	var expected_id: int = {"a": 1, "b": 2, "c": 3}[_role]
	if Net.room_code != _room or Net.local_id() != expected_id or Net.host_id != 1:
		_fail("without the server, we're player %d in room %s (host %d), not player %d in %s (host 1)" \
			% [Net.local_id(), Net.room_code, Net.host_id, expected_id, _room])
	elif Net.is_reconnecting():
		_fail("the menu says we're reconnecting right away")
	return true


## After a few seconds without the server (not before), the menu says we're
## reconnecting.
func _reconnecting_shown() -> Dictionary:
	return _step("after a few seconds, the menu says we're reconnecting", 30.0, Callable(), func() -> bool:
		if _reconnecting_after < 0.0:
			return false
		if _reconnecting_after < Net.RECONNECTING_NOTICE - 0.5:
			_fail("the menu said we're reconnecting after only %.1f s" % _reconnecting_after)
		return true)


## Back in our room with the signaling server, as before it went: nobody left,
## the host the same, and the menu doesn't say we're reconnecting any more.
func _back_in_room(host: int) -> bool:
	return Net.has_signaling() and not Net.is_reconnecting() and Net.is_online() and Net.room_code == _room \
		and Net.host_id == host and _notices.is_empty() and _all_here(2)


func _sorted_players() -> Array:
	var ids := _players.remote_heroes.keys()
	ids.sort()
	return ids


## Everyone tells the others where their hero is (`settle` seconds into the
## step, standing still); each game checks its copy of that hero.
func _agree_on_positions(phase: String, count: int, settle := 0.0) -> Dictionary:
	var told := [false]
	return _step("%s: we all agree where the heroes are" % phase, 20.0, Callable(), func() -> bool:
		if not told[0] and _time >= settle:
			told[0] = true
			_check_position.rpc(phase, _hero.world_position())
		# (The others may have told us first.)
		if not told[0] or _checked.get(phase, {}).size() < count:
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
		_results.append("ok    %-55s %.2f m off" % [what, error])
	_checked.get_or_add(phase, {})[sender] = true
