extends Node
## Headless check of the public game: copies of the game that join it by
## themselves once their city has loaded (as players' games do, here with
## --public=1), through the signaling server (tools/signaling, Node.js), which
## relays the public game's traffic (here with rooms of 6, RELAY_PUBLIC_PLAYERS).
##   - Six games start at different places: all join the same public room
##     (its public places, 6), each keeps its own start (nobody is moved to
##     the host), and each sees the others' heroes where they are.
##   - A seventh opens another public room.
##   - C leaves (plays alone): it stays alone, and the others see it go. It
##     joins the public game again from the menu: back in the first room
##     (the fullest with a place free), not the seventh's.
##   - D turns the public game off in the options (it leaves), then on (it's
##     back in the first room).
##   - The first room's host's game is closed: the next player hosts, and the
##     room stays public with its code.
##   - An eighth asks: it's put in the first room, with the old host's number.
##   - The server restarts: every game comes back to its room.
##   - The seventh leaves; its room closes, and with the first one full, a
##     ninth opens a new one.
##   - C leaves, and a tenth asks: it's put in the first room (still public
##     after the restart, rebuilt by its players).
## Each game writes what it sees to a file in a scratch folder every half
## second; this copy (the runner) starts the server and the games, tells them
## what to do through files there, and checks.
## Run: godot --headless --path . res://tests/coop_public_test.tscn [-- --port=8071]
## (--port: the signaling server's; other options, e.g. --tiles, go to the games)

const SignalingServer := preload("res://tests/signaling_server.gd")
const DEFAULT_PORT := 8071
## The public game is one big relayed room; a small one here, so the test
## sees it fill up and another open.
const SERVER_ENVIRONMENT := {RELAY_PUBLIC_PLAYERS = 6}
const ROLES: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
## Each game's start (world x, z; dropped from SPAWN_HEIGHT).
const SPAWNS: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(420.0, -220.0), Vector2(-300.0, 200.0), Vector2(300.0, 300.0),
	Vector2(-400.0, -300.0), Vector2(200.0, -500.0), Vector2(600.0, 100.0), Vector2(-100.0, 500.0),
	Vector2(500.0, -600.0), Vector2(-500.0, 600.0),
]
const SPAWN_HEIGHT := 40.0
## A hero counts as at its start within this far of it (m), and a copy of a
## hero as in place within POSITION_TOLERANCE of where its game says it is.
const AT_START := 30.0
const POSITION_TOLERANCE := 1.0

var _role := ""  # empty for the runner
var _port := DEFAULT_PORT
var _run_dir := ""
var _server := SignalingServer.new()
var _pids := {}  # role -> process id
var _world: Node
var _hero: Hero
var _players: PlayerSync
var _report_cooldown := 0.0
var _done_commands := {}
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _results: Array[String] = []
var _failures := 0
var _rooms := {}  # name -> room code, as the runner saw them
var _host_number := 0  # the first room's first host's number
var _dropped := {}  # role -> true: the game said it had lost the server (while it restarted)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--run="):
			_run_dir = arg.trim_prefix("--run=")
	LaunchOptions.set_default("signal", "ws://127.0.0.1:%d" % _port)
	LaunchOptions.set_default("net", "enet")
	if _role.is_empty():
		_run_dir = ProjectSettings.globalize_path("user://coop_public_test_%d" % OS.get_process_id())
		DirAccess.make_dir_recursive_absolute(_run_dir)
		_steps = _runner_steps()
		return
	var spawn := SPAWNS[ROLES.find(_role)]
	LaunchOptions.set_default("spawn", "%f,%f,%f,0" % [spawn.x, SPAWN_HEIGHT, spawn.y])
	LaunchOptions.set_default("public", "1")  # (headless games don't, by themselves)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	for node_name in ["PlayerInput", "Crowd", "Traffic", "Trains"]:
		_world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	(_world.get_node("Encounters") as EncounterDirector).max_gangs = 0
	_hero = _world.get_node("Hero")
	_players = _world.get_node("Players")


func _runner_steps() -> Array[Dictionary]:
	return [
		_step("start the co-op server on port %d" % _port, 10.0, func() -> void:
			var problem := _server.start(_port, SERVER_ENVIRONMENT)
			if problem:
				_fail(problem),
			func() -> bool: return _server.is_up()),
		_step("six games start; they all join one public room", 120.0, func() -> void:
			for role in ["a", "b", "c", "d", "e", "f"]:
				_launch(role),
			func() -> bool:
				if not _all_in_room(["a", "b", "c", "d", "e", "f"], 5):
					return false
				_rooms.first = _state("a").room
				_host_number = int(_state("a").host)
				return ["a", "b", "c", "d", "e", "f"].all(func(role: String) -> bool: return _state(role).room == _rooms.first) \
					and _numbers(["a", "b", "c", "d", "e", "f"]) == [1, 2, 3, 4, 5, 6]),
		_step("each keeps its own start, and sees the others where they are", 30.0, Callable(), func() -> bool:
			return _at_starts(["a", "b", "c", "d", "e", "f"]) and _copies_in_place(["a", "b", "c", "d", "e", "f"])),
		_step("a seventh opens another public room, as its host", 60.0, _launch.bind("g"), func() -> bool:
			var g := _state("g")
			if not _all_in_room(["g"], 0) or g.room == _rooms.first:
				return false
			_rooms.second = g.room
			return int(g.id) == 1 and int(g.host) == 1),
		_step("C leaves (plays alone): it stays alone, and the others see it go", 30.0, _command.bind("c", "leave"),
			func() -> bool:
				var c := _state("c")
				return _time > 5.0 and c.state == "OFFLINE" and not c.wants_public \
					and ["a", "b", "d", "e", "f"].all(func(role: String) -> bool: return (_state(role).peers as Array).size() == 4)),
		_step("C joins the public game again from the menu: the first room", 60.0, _command.bind("c", "public"),
			func() -> bool: return _all_in_room(["c"], 5) and _state("c").room == _rooms.first),
		_step("D turns the public game off in the options: it leaves", 30.0, _command.bind("d", "setting_off"),
			func() -> bool:
				var d := _state("d")
				return d.state == "OFFLINE" and not d.wants_public \
					and ["a", "b", "c", "e", "f"].all(func(role: String) -> bool: return (_state(role).peers as Array).size() == 4)),
		_step("D turns it back on: it's in the first room again", 60.0, _command.bind("d", "setting_on"),
			func() -> bool: return _all_in_room(["d"], 5) and _state("d").room == _rooms.first),
		_step("the first room's host's game closes: the next hosts, the room stays public", 60.0, func() -> void:
			OS.kill(_pids[_role_numbered(_host_number)]),
			func() -> bool:
				var rest := _first_room_roles()
				if rest.size() != 5 or not _all_in_room(rest, 4):
					return false
				var host: int = int(_state(rest[0]).host)
				return host != _host_number and rest.all(func(role: String) -> bool:
					return int(_state(role).host) == host and _state(role).room == _rooms.first)),
		_step("an eighth is put in the first room, with the old host's number, at its own start", 60.0, _launch.bind("h"),
			func() -> bool:
				var h := _state("h")
				return _all_in_room(["h"], 5) and h.room == _rooms.first and int(h.id) == _host_number \
					and _at_starts(["h"]) and _copies_in_place(_first_room_roles())),
		_step("the server restarts: every game comes back to its room", 120.0, func() -> void:
			_server.stop()
			await get_tree().create_timer(3.0).timeout
			_server.start(_port, SERVER_ENVIRONMENT),
			func() -> bool:
				var first := _first_room_roles()
				for role: String in first + ["g"]:
					if not _state(role).signaling:
						_dropped[role] = true
				return first.size() == 6 and _all_in_room(first, 5) and _all_in_room(["g"], 0) \
					and (first + ["g"]).all(func(role: String) -> bool: return _dropped.has(role) and _state(role).signaling) \
					and _state("g").room == _rooms.second),
		_step("the seventh leaves (its room closes); the first is full: a ninth opens a new room", 60.0, func() -> void:
			_command("g", "leave")
			_launch("i"),
			func() -> bool:
				var i := _state("i")
				return _state("g").state == "OFFLINE" and _all_in_room(["i"], 0) \
					and not [_rooms.first, _rooms.second].has(i.room) and int(i.id) == 1),
		_step("C leaves; a tenth is put in the first room (still public after the restart)", 60.0, func() -> void:
			_command("c", "leave")
			_launch("j"),
			func() -> bool:
				var j := _state("j")
				return _state("c").state == "OFFLINE" and _all_in_room(["j"], 5) and j.room == _rooms.first),
	]


## Starts one of the games.
func _launch(role: String) -> void:
	var args := ["--headless", "--log-file", _run_dir.path_join(role + ".log"), "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/coop_public_test.tscn", "--",
		"--role=" + role, "--run=" + _run_dir]
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--role=") and not arg.begins_with("--run="):
			args.append(arg)  # --port, --tiles, ...
	_pids[role] = OS.create_process(OS.get_executable_path(), args)


func _command(role: String, what: String) -> void:
	_write(_run_dir.path_join(role + ".do"), what)


## What a game last said it sees (see _report), or an empty state.
func _state(role: String) -> Dictionary:
	var path := _run_dir.path_join(role + ".state")
	var state = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(state) != TYPE_DICTIONARY:
		return {state = "", room = "", id = 0, host = 0, public = false, wants_public = false, signaling = false, peers = [],
			hero = [0, 0, 0], others = {}, frozen = true}
	return state


## These games are in a public room with `others` others each, their heroes on the ground.
func _all_in_room(roles: Array, others: int) -> bool:
	return roles.all(func(role: String) -> bool:
		var state := _state(role)
		return state.state in ["HOSTING", "JOINED"] and state.public and (state.peers as Array).size() == others \
			and not state.frozen)


func _numbers(roles: Array) -> Array:
	var numbers := roles.map(func(role: String) -> int: return int(_state(role).id))
	numbers.sort()
	return numbers


func _first_room_roles() -> Array:
	return ROLES.filter(func(role: String) -> bool:
		return _pids.has(role) and OS.is_process_running(_pids[role]) and _state(role).room == _rooms.first)


func _role_numbered(number: int) -> String:
	for role in _first_room_roles():
		if int(_state(role).id) == number:
			return role
	return ""


## Their heroes are where they started (nobody moved them to the host).
func _at_starts(roles: Array) -> bool:
	return roles.all(func(role: String) -> bool:
		var at: Array = _state(role).hero
		return Vector2(at[0], at[2]).distance_to(SPAWNS[ROLES.find(role)]) < AT_START)


## Each game's copy of each other game's hero is where that game says it is.
func _copies_in_place(roles: Array) -> bool:
	var positions := {}
	for role: String in roles:
		var state := _state(role)
		positions[str(int(state.id))] = state.hero
	for role: String in roles:
		var others: Dictionary = _state(role).others
		for id: String in positions:
			if id == str(int(_state(role).id)):
				continue
			if not others.has(id):
				return false
			var a: Array = others[id]
			var b: Array = positions[id]
			if Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2])) > POSITION_TOLERANCE:
				return false
	return true


func _process(delta: float) -> void:
	if _role.is_empty():
		_run_steps(delta)
		return
	_report_cooldown -= delta
	if _report_cooldown > 0.0:
		return
	_report_cooldown = 0.5
	var command_path := _run_dir.path_join(_role + ".do")
	if FileAccess.file_exists(command_path):
		var command := FileAccess.get_file_as_string(command_path)
		DirAccess.remove_absolute(command_path)
		print("[test] %s" % command)
		match command:
			"leave":
				Net.leave()  # the menu's Leave
			"public":
				Net.join_public()  # the menu's Join the public game
			"setting_off", "setting_on":
				Settings.set_value("online_public", command == "setting_on")  # the options menu's switch
	_report()


## Tells the runner what we see.
func _report() -> void:
	var others := {}
	for id: int in _players.remote_heroes:
		var at := (_players.remote_heroes[id] as Hero).world_position()
		others[str(id)] = [at.x, at.y, at.z]
	var at := _hero.world_position()
	_write(_run_dir.path_join(_role + ".state"), JSON.stringify({
		state = Net.State.keys()[Net.state], room = Net.room_code, id = Net.local_id(), host = Net.host_id,
		public = Net.is_public, wants_public = Net.wants_public(), signaling = Net.has_signaling(), peers = Array(Net.peers()),
		hero = [at.x, at.y, at.z], others = others, frozen = _hero.frozen}))


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	file.store_string(content)
	file.close()
	DirAccess.rename_absolute(path + ".part", path)


func _run_steps(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	var done: bool = step.until.call() if step.until.is_valid() else _time >= step.seconds
	if not done:
		if _time < step.seconds:
			return
		_fail("%s: timed out after %.0f s" % [step.name, step.seconds])
		_finish()
		return
	_results.append("ok    %-80s %5.1f s" % [step.name, _time])
	if _index + 1 < _steps.size():
		_begin(_index + 1)
		return
	_finish()


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	if _steps[index].start.is_valid():
		_steps[index].start.call()


func _finish() -> void:
	set_process(false)
	for role: String in _pids:
		if OS.is_process_running(_pids[role]):
			OS.kill(_pids[role])
	_server.stop()
	for line in _results:
		print("  " + line)
	if _failures:
		for role: String in _pids:
			print("game %s's state: %s" % [role.to_upper(), JSON.stringify(_state(role))])
			print("game %s's log:\n%s" % [role.to_upper(), FileAccess.get_file_as_string(_run_dir.path_join(role + ".log"))])
		print("(files in %s)" % _run_dir)
	else:
		await get_tree().create_timer(0.5).timeout  # until the games have let go of their logs
		for file in DirAccess.get_files_at(_run_dir):
			DirAccess.remove_absolute(_run_dir.path_join(file))
		DirAccess.remove_absolute(_run_dir)
	print("co-op public test finished: %d problems" % _failures)
	get_tree().quit(1 if _failures else 0)


func _fail(text: String) -> void:
	_failures += 1
	_results.append("FAIL  " + text)


func _step(step_name: String, seconds: float, start := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, start = start, until = until}
