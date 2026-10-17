extends Node
## Two actual Godot processes exercise the production PlayerSync cosmetic RPC
## over loopback ENet. No city data, signaling service or external connection.
## godot --headless --path . res://tests/customization_coop_test.tscn
var _client := false
var _client_pid := 0
var _peer: ENetMultiplayerPeer
var _players: PlayerSync
var _hero: Hero
var _reports := {}
var _port := 18763

func _ready() -> void:
	_client = LaunchOptions.get_string("role") == "client"
	_port = LaunchOptions.get_string("port", str(_port)).to_int()
	_run()

func _run() -> void:
	Net.set_process(false)  # this harness supplies the connection instead of signaling
	Net.state = Net.State.JOINED if _client else Net.State.HOSTING
	Net.host_id = 1
	var initial := HeroAppearance.DEFAULT.duplicate()
	initial.suit = "leotard" if _client else "mech"
	initial.primary = "abcdef" if _client else "123456"
	HeroAppearance.save(initial)
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	_hero.frozen = true
	add_child(_hero)
	_players = PlayerSync.new()
	_players.name = "Players"
	_players.hero = _hero
	add_child(_players)
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client("127.0.0.1", _port) if _client else _peer.create_server(_port, 1)
	if error != OK:
		_fail("could not open loopback peer: %d" % error)
		return
	multiplayer.multiplayer_peer = _peer
	if not _client:
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/customization_coop_test.tscn", "--", "--role=client", "--port=" + str(_port)]
		_client_pid = OS.create_process(OS.get_executable_path(), args)
	if not await _until(func() -> bool: return _players.remote_heroes.size() == 1, "peer's hero created"):
		return
	var other_id: int = _players.remote_heroes.keys()[0]
	var remote := (_players.remote_heroes[other_id] as Hero).get_node("Model") as HeroAnimator
	if not await _until(func() -> bool: return remote.appearance.suit == ("mech" if _client else "leotard") and remote.appearance.primary == ("123456" if _client else "abcdef"), "initial saved costume arrived over reliable RPC"):
		return
	if _client:
		_report.rpc_id(1, "initial")
		if not await _until(func() -> bool: return remote.appearance.suit == "longsleeve" and remote.appearance.cape == "split", "host's live edit arrived"):
			return
		var edited := initial.duplicate()
		edited.boots = "armored"
		edited.hair = "ponytail"
		HeroAppearance.save(edited)
		_report.rpc_id(1, "updated")
		await get_tree().create_timer(1.0).timeout
		print("CUSTOMIZATION_COOP client passed")
		_peer.close()
		get_tree().quit()
	else:
		if not await _until(func() -> bool: return _reports.has("initial"), "client confirms its view of host"):
			return
		var edited := initial.duplicate()
		edited.suit = "longsleeve"
		edited.cape = "split"
		HeroAppearance.save(edited)
		if not await _until(func() -> bool: return _reports.has("updated") and remote.appearance.boots == "armored" and remote.appearance.hair == "ponytail", "both live cosmetic edits crossed the connection"):
			return
		Net.state_changed.emit()
		if (_hero.get_node("Model") as HeroAnimator).appearance != edited:
			_fail("network state change overwrote host costume")
			return
		print("PASS network state preserves local costume")
		await get_tree().create_timer(1.2).timeout
		print("CUSTOMIZATION_COOP_TEST failures=0")
		_peer.close()
		get_tree().quit()

func _until(predicate: Callable, label: String) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call():
		if Time.get_ticks_msec() - start > 15000:
			_fail("timed out: " + label)
			return false
		await get_tree().process_frame
	print("PASS ", "client " if _client else "host ", label)
	return true

func _fail(message: String) -> void:
	push_error(message)
	if _client_pid > 0 and OS.is_process_running(_client_pid):
		OS.kill(_client_pid)
	if _peer:
		_peer.close()
	get_tree().quit(1)

@rpc("any_peer", "call_remote", "reliable")
func _report(stage: String) -> void:
	_reports[stage] = true
