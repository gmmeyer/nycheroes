extends Node
## Co-op sessions (autoload "Net"): hosting and joining games, and who's in them.
##
## Players find each other through a small signaling server (tools/signaling
## locally, tools/cloudflare on the public site) using a short room code,
## then connect directly over WebRTC, every player to every other (a full
## mesh). Each game runs the thugs around its own hero and decides the hits on
## them (see EncounterDirector, Combat). One of the players is the host: in a
## private game, players who join start next to its hero, and when a player
## leaves, its game takes over their thugs. When the host leaves, the game goes
## on: the signaling server names the player who has been in the room longest
## the new host (host_changed), whose game takes the thugs over from the
## copies it and the others have; the room keeps its code, so friends can
## still join. Desktop builds get WebRTC from the webrtc-native
## GDExtension (addons/webrtc_native), so they play with browser players, and
## use the public site's signaling server by default. The co-op tests connect
## over ENet on this machine instead (--net=enet), through the same signaling;
## --net=webrtc makes them use WebRTC too.
##
## The signaling server only hears of players through their sockets: games
## ping it every PING_INTERVAL, and tell it when they lose touch with a player
## it still counts in the room, so it can drop players whose connection died
## without closing (a host whose Wi-Fi went away) and pick a new host. If such
## a player is still there, only the connection between us broke: the one of
## us with the lower number connects again.
##
## Game traffic never goes through the signaling server, so when it drops us
## (a Worker deploy restarts its Durable Object and closes every socket) the
## game goes on over the connections between players, and we connect to it
## again, sooner at first, then every RETRY_DELAY_MAX. We rejoin the room as
## the same player, with the key the server gave us, saying who's in the room,
## in the order they came, and who hosts: a server that lost the room rebuilds
## it from the players who come back (see tools/signaling/server.mjs). Only if
## that takes more than a few seconds does the menu say so (is_reconnecting).
##
## The public game: everyone playing online is put in a public room
## (join_public), the fullest one with a place free, or a new one when they're
## all full; the signaling server matches only games of the same NET_VERSION.
## Game asks for it once the city has loaded (start_public), unless the player
## asked for something else or turned it off (the setting "online_public"); it
## goes quietly: if the server can't be reached, or the room's host can't, we
## play alone and try again later (PUBLIC_RETRY), and nothing is shown. Public
## rooms have codes like any other, so friends can join one with its code.
##
## Launch options (read by Game): ?host hosts a game, ?join=CODE joins one,
## ?solo=1 plays alone (no public game), ?public=1 joins the public game even
## where Game wouldn't (headless, or a browser driven by a script),
## ?signal=wss://... picks the signaling server (default: /signal on the page's
## host over https, else the page's host on port 8070; desktop builds the
## public site's, the editor port 8070 on this machine), and ?relay=1 connects
## only through the TURN relay the signaling server hands out, to test the path
## players on strict networks need.

signal state_changed
## Connected to another player (who joined, or came back after their
## connection to us dropped: see is_newcomer).
signal player_joined(id: int)
## The connection to another player closed.
signal player_left(id: int)
## The signaling server says a player left the room (their connection closes
## too, if it hasn't).
signal left_room(id: int)
## Another player (or we) became the host: nodes whose "authority" RPCs come
## from the host follow it (set_multiplayer_authority).
signal host_changed(id: int)
## is_reconnecting changed.
signal reconnecting_changed
## We're back in the room after the signaling server let us go meanwhile (our
## socket dropped): the others took us for gone, and connect to us again.
signal readmitted

enum State { OFFLINE, CONNECTING, HOSTING, JOINED }

## The first host's number (and ours when offline).
const FIRST_HOST := 1
## The full mesh's limit: each player connects to every other, and sends its
## hero's state to each (see PlayerSync).
const MAX_PLAYERS := 8
## Games send the signaling server this number (plus ENET_VERSION over ENet),
## which matches public games only with games of the same number, and turns
## away room codes of another. Raise it whenever what games send each other
## changes (RPCs), so games that can't play together never meet.
const NET_VERSION := 1
const ENET_VERSION := 1000000
## After failing to reach the public game, try again after this long
## (seconds), twice as long after each try that fails, up to PUBLIC_RETRY_MAX.
const PUBLIC_RETRY := 30.0
const PUBLIC_RETRY_MAX := 300.0
## After losing the public room's host (or being dropped), look for a public
## room again after this long (seconds).
const PUBLIC_REJOIN := 3.0
## How often to check the player's "online_public" setting (seconds).
const SETTING_INTERVAL := 1.0
const SIGNALING_PORT := 8070
## The public site, whose signaling server desktop builds use by default; their
## invite links open the game there.
const SITE_URL := "https://nycheroes.party/"
const PUBLIC_SIGNALING_URL := "wss://nycheroes.party/signal"
## Give up on reaching a host after this long (seconds).
const CONNECT_TIMEOUT := 20.0
## After losing touch with the host, give up on the game after this long
## (seconds) if the signaling server hasn't named a new host meanwhile.
const HOST_TIMEOUT := 60.0
## Seconds between pings to the signaling server, and between reports of
## players we've lost touch with.
const PING_INTERVAL := 10.0
const LOST_REPORT_INTERVAL := 5.0
## A signaling connection still opening after this long, or that hasn't
## answered a ping for this long, is given up on and made again (seconds).
const SIGNALING_TIMEOUT := 15.0
## After the signaling server drops us, connect again after this long
## (seconds), twice as long after each try that fails, up to RETRY_DELAY_MAX;
## a little random, so a room's players don't all come back at once.
const RETRY_DELAY := 0.5
const RETRY_DELAY_MAX := 5.0
## Tell the player we're reconnecting only once it's taken this long (seconds).
const RECONNECTING_NOTICE := 5.0
## A join the server has no room for is asked again this many times, this far
## apart (seconds): just after a restart, the room's players may not be back.
const JOIN_RETRIES := 2
const JOIN_RETRY_DELAY := 2.0
## After a connection to a player still in the room drops, connect again after
## this long, and again every RECONNECT_INTERVAL while it's down (msec).
const RECONNECT_DELAY := 2000
const RECONNECT_INTERVAL := 10000
## ENet (tests, and desktop builds without the WebRTC extension) channels per
## connection: enough for ENetMultiplayerPeer's own and the RPCs'.
const ENET_CHANNELS := 8
## ENet connections drop after this long without an answer (msec, at least
## and at most): long enough to ride out a slow frame with four games on one
## machine.
const ENET_TIMEOUT := Vector2i(15000, 30000)
## One color per player number (1 is the first host), used for their hero's suit.
const PLAYER_COLORS: Array[Color] = [
	Color(0.72, 0.06, 0.08), Color(0.1, 0.3, 0.85), Color(0.1, 0.6, 0.2), Color(0.9, 0.7, 0.05),
	Color(0.55, 0.15, 0.75), Color(0.95, 0.45, 0.05), Color(0.05, 0.7, 0.75), Color(0.85, 0.85, 0.85),
]

var state := State.OFFLINE
var room_code := ""
## The host's player number (ours when offline or hosting).
var host_id := FIRST_HOST
## The last problem worth telling the player about (empty when all is well).
var error := ""
## Whether our room is a public one (we asked for the public game, or joined a
## public room with its code).
var is_public := false

var _signaling: WebSocketPeer
var _signaling_url := ""
var _greeting := {}  # first message to the signaling server, until we're in a room
var _hello_msec := -1  # when to send it (or ask to rejoin) on the signaling socket (-1: sent)
var _got_through := false  # the signaling socket opened at least once
var _rejoining := false  # we've asked to rejoin the room, and wait for the answer
var _awaiting_msec := 0  # since when we've been waiting for the signaling server to answer (0: we aren't)
var _signaling_lost_msec := 0  # when the signaling server dropped us (0: it hasn't)
var _retry_msec := 0  # when to connect to it again (0: not waiting to)
var _retry_delay := RETRY_DELAY
var _join_retries := 0
var _reconnecting := false
var _key := ""  # from the signaling server: ours, to take our place in the room back
var _order: Array[int] = []  # everyone in the room, us too, in the order they came (as the server has it)
var _mesh: MultiplayerPeer  # WebRTCMultiplayerPeer, or ENetMultiplayerPeer in tests
var _connections := {}  # player number -> WebRTCPeerConnection, or ENetConnection until connected
var _ice_servers: Array = []
var _members := {}  # player number -> true: everyone in the room as the signaling server last said, but us
var _newcomers := {}  # player number -> true: members who joined the room and haven't connected to us yet
var _lost := {}  # player number -> reported yet: members we've lost touch with
var _reconnect_at := {}  # player number -> msec: when to connect again to a member we lost touch with
var _connect_time := 0.0
var _host_missing_time := 0.0
var _ping_cooldown := 0.0
var _report_cooldown := 0.0
var _auto_public := false  # Game allows the public game (start_public): we follow the setting
var _wants_public := false  # we're in the public game, or looking for it (quietly, see _give_up)
var _public_at := 0  # when to look for a public room again (msec; 0: not waiting to)
var _public_retry := PUBLIC_RETRY
var _setting_cooldown := 0.0
var _setting_on := true  # the "online_public" setting, as of the last check

static var _webrtc := -1  # whether a WebRTC library loaded (desktop): -1 not checked yet, else 1 or 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(delta: float) -> void:
	_follow_setting(delta)
	if _public_at != 0 and Time.get_ticks_msec() >= _public_at:
		_public_at = 0
		if state == State.OFFLINE and _wants_public:
			_start({type = "public"})
	if _signaling:
		_poll_signaling()
	elif _retry_msec != 0 and Time.get_ticks_msec() >= _retry_msec:
		_retry_msec = 0
		if not _open_signaling():
			_signaling_dropped()
	var reconnecting := is_online() and _signaling_lost_msec != 0 \
		and Time.get_ticks_msec() - _signaling_lost_msec > RECONNECTING_NOTICE * 1000.0
	if reconnecting != _reconnecting:
		_reconnecting = reconnecting
		reconnecting_changed.emit()
	if _mesh is ENetMultiplayerPeer:
		_poll_enet_connections()
	if state == State.CONNECTING:
		_connect_time += delta
		if _connect_time > CONNECT_TIMEOUT:
			_give_up("Couldn't reach the game. The host's or your network may be blocking it.")
			return
	_host_missing_time = _host_missing_time + delta if state == State.JOINED and not _connected(host_id) else 0.0
	if _host_missing_time > HOST_TIMEOUT:
		_give_up("Lost the connection to the host.")
		return
	_ping_cooldown -= delta
	if _ping_cooldown <= 0.0 and _signaling and _signaling.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ping_cooldown = PING_INTERVAL
		_signaling.send_text("ping")
		if _awaiting_msec == 0:
			_awaiting_msec = Time.get_ticks_msec()
	_report_cooldown -= delta
	if _report_cooldown <= 0.0 and not _lost.is_empty():
		_report_cooldown = LOST_REPORT_INTERVAL
		for id: int in _lost:
			if not _lost[id]:
				print("[net] lost touch with player %d; telling the co-op server" % id)
				_lost[id] = true
			_send({type = "lost", id = id})
	for id: int in _reconnect_at.keys():
		if Time.get_ticks_msec() < _reconnect_at[id]:
			continue
		if not _members.has(id) or _connected(id):
			_reconnect_at.erase(id)
			continue
		print("[net] connecting to player %d again" % id)
		_reconnect_at[id] = Time.get_ticks_msec() + RECONNECT_INTERVAL
		_drop(id)
		_offer(id)


func is_online() -> bool:
	return state == State.HOSTING or state == State.JOINED


## Whether the signaling server has us in our room now: not while it's gone
## and we're getting back to it (the game goes on meanwhile).
func has_signaling() -> bool:
	return is_online() and _signaling_lost_msec == 0


## Whether to tell the player we're reconnecting to the signaling server:
## it's been gone for more than RECONNECTING_NOTICE (reconnecting_changed).
func is_reconnecting() -> bool:
	return _reconnecting


## Whether we're in the public game or looking for it (also while waiting to
## try again after failing to reach it).
func wants_public() -> bool:
	return _wants_public


## This player's number (1 when offline).
func local_id() -> int:
	return multiplayer.get_unique_id()


func player_name(id: int) -> String:
	return "Player %d" % (id if id <= 99 else id % 100)


func player_color(id: int) -> Color:
	return PLAYER_COLORS[(id - 1) % PLAYER_COLORS.size()]


## Everyone else in the game.
func peers() -> PackedInt32Array:
	return multiplayer.get_peers() if is_online() else PackedInt32Array()


## Whether a player who just connected (player_joined) joined the room just
## now, rather than coming back after their connection to us dropped.
func is_newcomer(id: int) -> bool:
	return _newcomers.has(id)


## A link that opens the game in the browser and joins this room: on the
## web, this page's; on desktop, the public site's (unless this game uses
## another signaling server: then friends join with the code).
func invite_link() -> String:
	if room_code.is_empty():
		return room_code
	var page := SITE_URL
	if OS.has_feature("web"):
		page = str(JavaScriptBridge.eval("location.origin + location.pathname"))
	elif _signaling_url != PUBLIC_SIGNALING_URL:
		return room_code
	var link := page + "?join=" + room_code
	if LaunchOptions.has("signal") and OS.has_feature("web"):
		link += "&signal=" + LaunchOptions.get_string("signal").uri_encode()
	return link


## Hosts a private game (leaving the public one, if we're in it).
func host() -> void:
	_stop_public()
	_start({type = "host"})


func join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.is_empty():
		error = "Type in the room code first."
		state_changed.emit()
		return
	_stop_public()
	_start({type = "join", code = code})


## Joins the public game: the public room with the most players and a place
## free, or a new one. Quietly: if it can't be reached, we play alone and try
## again in a while.
func join_public() -> void:
	_wants_public = true
	_public_retry = PUBLIC_RETRY
	_start({type = "public"})


## Game allows the public game in this session: we join it now unless the
## player turned it off (or is in a game already), and follow the setting from
## then on: turning it off leaves the public game, turning it on joins it.
func start_public() -> void:
	_auto_public = true
	_setting_on = _public_setting()
	if _setting_on and state == State.OFFLINE:
		join_public()


## Leaves the game. `reason`, if any, is shown to the player. The others play on.
func leave(reason := "") -> void:
	var was_offline := state == State.OFFLINE and not _wants_public
	_stop_public()
	_reset()
	error = reason
	if reason:
		push_warning("[net] " + reason)
	if not was_offline or reason:
		_set_state(State.OFFLINE)


## Something went wrong: we leave the game, telling the player why, unless
## it's the public game. Then we play alone without a word, and look for a
## public room again in a while (soon if we were in one: its host may be gone).
func _give_up(reason: String) -> void:
	if not _wants_public:
		leave(reason)
		return
	var delay := PUBLIC_REJOIN
	if not is_online():
		delay = _public_retry
		_public_retry = minf(_public_retry * 2.0, PUBLIC_RETRY_MAX)
	print("[net] public game: %s; looking again in %.0f s" % [reason, delay])
	_reset()
	_public_at = Time.get_ticks_msec() + int(delay * 1000.0)
	_set_state(State.OFFLINE)


func _stop_public() -> void:
	_wants_public = false
	_public_at = 0


## The player's "online_public" setting: on unless they turned it off (kept
## by the Settings autoload, if there is one).
func _public_setting() -> bool:
	var settings := get_node_or_null("/root/Settings")
	if settings == null or not settings.has_method("get_value"):
		return true
	return bool(settings.call("get_value", "online_public", true))


## Once the public game is allowed (start_public), follows the setting.
func _follow_setting(delta: float) -> void:
	_setting_cooldown -= delta
	if not _auto_public or _setting_cooldown > 0.0:
		return
	_setting_cooldown = SETTING_INTERVAL
	var on := _public_setting()
	if on == _setting_on:
		return
	_setting_on = on
	if on and state == State.OFFLINE:
		join_public()
	elif not on and _wants_public:
		leave()


func _reset() -> void:
	error = ""
	if _signaling:
		_signaling.close()
		_signaling = null
	_greeting = {}
	_got_through = false
	_rejoining = false
	_signaling_lost_msec = 0
	_retry_msec = 0
	_key = ""
	_order.clear()
	for connection: Object in _connections.values():
		if connection is WebRTCPeerConnection:
			(connection as WebRTCPeerConnection).close()
		else:
			(connection as ENetConnection).destroy()
	_connections.clear()
	_members.clear()
	_newcomers.clear()
	_lost.clear()
	_reconnect_at.clear()
	_mesh = null
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	room_code = ""
	is_public = false
	state = State.OFFLINE
	if _reconnecting:
		_reconnecting = false
		reconnecting_changed.emit()
	_set_host(FIRST_HOST)


func _start(greeting: Dictionary) -> void:
	_reset()
	_signaling_url = _default_signaling_url()
	if not _open_signaling():
		_give_up("Couldn't reach the co-op server at %s." % _signaling_url)
		return
	greeting.version = _version()
	_greeting = greeting
	_join_retries = JOIN_RETRIES
	_connect_time = 0.0
	_set_state(State.CONNECTING)


func _default_signaling_url() -> String:
	if LaunchOptions.has("signal"):
		return LaunchOptions.get_string("signal")
	if not OS.has_feature("web"):
		# Desktop builds play with the public site's players; the editor
		# (and a build without WebRTC) with a local server.
		if OS.has_feature("editor") or not uses_webrtc():
			return "ws://127.0.0.1:%d" % SIGNALING_PORT
		return PUBLIC_SIGNALING_URL
	# The public site (https, tools/cloudflare) has it at /signal on the same
	# host; a local build (tools/build_web.ps1 -Serve) on its own port.
	if str(JavaScriptBridge.eval("location.protocol")) == "https:":
		return "wss://%s/signal" % str(JavaScriptBridge.eval("location.host"))
	return "ws://%s:%d" % [str(JavaScriptBridge.eval("location.hostname")), SIGNALING_PORT]


## Starts connecting to the signaling server. False if it can't even try.
func _open_signaling() -> bool:
	_signaling = WebSocketPeer.new()
	if _signaling.connect_to_url(_signaling_url) != OK:
		_signaling = null
		return false
	_hello_msec = 0
	_awaiting_msec = Time.get_ticks_msec()
	_ping_cooldown = 0.0  # right away: the server counts us as heard from
	return true


func _poll_signaling() -> void:
	_signaling.poll()
	match _signaling.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_got_through = true
			if _hello_msec >= 0 and Time.get_ticks_msec() >= _hello_msec:
				_hello_msec = -1
				# Back in touch after it dropped us: our place in the room.
				_rejoining = not room_code.is_empty()
				_send(_rejoin_request() if _rejoining else _greeting)
			while _signaling and _signaling.get_available_packet_count() > 0:
				_awaiting_msec = 0
				var text := _signaling.get_packet().get_string_from_utf8()
				if text == "pong":
					continue
				var message = JSON.parse_string(text)
				if typeof(message) == TYPE_DICTIONARY:
					_on_signaling_message(message)
		WebSocketPeer.STATE_CLOSED:
			_signaling_dropped()
			return
	if _signaling and _awaiting_msec != 0 and Time.get_ticks_msec() - _awaiting_msec > SIGNALING_TIMEOUT * 1000.0:
		print("[net] the co-op server isn't answering")
		_signaling_dropped()


## The signaling socket closed, or stopped answering. Unless it never got
## through, the game goes on, and we connect again in a moment (and again,
## less often, while that fails).
func _signaling_dropped() -> void:
	if _signaling:
		_signaling.close()
		_signaling = null
	_rejoining = false
	if state == State.OFFLINE:
		return
	if not _got_through:
		_give_up("Couldn't reach the co-op server at %s." % _signaling_url)
		return
	var now := Time.get_ticks_msec()
	if _signaling_lost_msec == 0:
		_signaling_lost_msec = now
		_retry_delay = RETRY_DELAY
		print("[net] lost the co-op server; connecting again")
	_retry_msec = now + int(_retry_delay * randf_range(0.75, 1.25) * 1000.0)
	_retry_delay = minf(_retry_delay * 2.0, RETRY_DELAY_MAX)


## In a room (again) as far as the signaling server goes.
func _signaling_back() -> void:
	if _signaling_lost_msec != 0:
		print("[net] back in touch with the co-op server after %.1f s" \
			% ((Time.get_ticks_msec() - _signaling_lost_msec) / 1000.0))
	_signaling_lost_msec = 0
	_greeting = {}
	_public_retry = PUBLIC_RETRY


## Our place in the room, for a signaling server that dropped us (and may have
## lost the room: it rebuilds it from what its players say).
func _rejoin_request() -> Dictionary:
	var request := {type = "rejoin", code = room_code, id = local_id(), key = _key, host = host_id, players = _order,
		version = _version()}
	if is_public:
		request.public = true
	return request


## What we tell the signaling server our version is (see NET_VERSION).
static func _version() -> int:
	return NET_VERSION + (0 if uses_webrtc() else ENET_VERSION)


func _on_signaling_message(message: Dictionary) -> void:
	match message.get("type"):
		"hosted":
			room_code = message.code
			_key = str(message.get("key", ""))
			_ice_servers = message.get("ice", [])
			is_public = message.get("public") == true
			_open_mesh(int(message.id))
			_order.assign([int(message.id)])
			_signaling_back()
			print("[net] hosting %sroom %s" % ["public " if is_public else "", room_code])
			_set_host(int(message.id))
		"joined":
			room_code = message.code
			_key = str(message.get("key", ""))
			_ice_servers = message.get("ice", [])
			is_public = message.get("public") == true
			_open_mesh(int(message.id))
			# The players already in the room each send us an offer.
			_order.clear()
			for id in message.get("peers", [FIRST_HOST]):
				_members[int(id)] = true
				_order.append(int(id))
				if _mesh is WebRTCMultiplayerPeer:
					_add_connection(int(id))
			_order.append(int(message.id))
			_signaling_back()
			print("[net] joining %sroom %s as player %d" % ["public " if is_public else "", room_code, int(message.id)])
			_set_host(int(message.get("host", FIRST_HOST)))
		"rejoined":
			_on_rejoined(message)
		"peer_joined":
			# Fresh relay credentials, if the server sends them: a game can go
			# on for longer than they last.
			_update_ice(message.get("ice", []))
			var id := int(message.id)
			_members[id] = true
			if not _order.has(id):
				_order.append(id)
			# One coming back after the server let them go (their socket alone
			# dropped) isn't new: we connect to them again, unless we still are.
			var back: bool = message.get("back") == true
			if not back:
				_newcomers[id] = true
			if not (back and _connected(id)):
				_drop(id)
				_offer(id)
			_reconnect_at.erase(id)
		"peer_left":
			_forget(int(message.id))
			# The host may have been the one leaving; the server names the next.
			_set_host(int(message.get("host", host_id)))
		"signal":
			_on_signal(int(message.from), message.get("data", {}))
		"error":
			if message.get("reason") == "no_room" and state == State.CONNECTING and _join_retries > 0:
				# Just after a restart, the room's players may not be back yet.
				_join_retries -= 1
				_hello_msec = Time.get_ticks_msec() + int(JOIN_RETRY_DELAY * 1000.0)
			elif _rejoining:
				push_warning("[net] couldn't rejoin room %s: %s" % [room_code, message.get("message", "")])
				_give_up("Lost the connection to the co-op server.")
			else:
				# (Also a server from before the public game, which doesn't know
				# the request: we try again later, and it may have been updated.)
				_give_up(str(message.get("message", "Something went wrong.")))


## Back in the room after the signaling server dropped us: who's in it now,
## and who hosts (it may have named another host if it let us go).
func _on_rejoined(message: Dictionary) -> void:
	_rejoining = false
	_update_ice(message.get("ice", []))
	is_public = is_public or message.get("public") == true
	_order.assign(message.get("players", []).map(func(id: Variant) -> int: return int(id)))
	for id: int in _members.keys():
		if not _order.has(id):
			_forget(id)  # they left while we were away
	for id in _order:
		if id != local_id():
			_members[id] = true
	if message.get("back") == true:
		# The server had let us go, and the others dropped their connections
		# to us: they connect to us again, as when we joined (we do only if
		# they haven't after a while).
		for id: int in _members.keys():
			_drop(id)
		for id: int in _members:
			_reconnect_at[id] = Time.get_ticks_msec() + RECONNECT_INTERVAL
		readmitted.emit()
	else:
		# Connections that broke meanwhile: the one of us with the lower
		# number connects again (players who joined meanwhile hear from us
		# next, in peer_joined).
		for id: int in _members:
			if not _connected(id) and local_id() < id:
				_reconnect_at[id] = Time.get_ticks_msec() + RECONNECT_DELAY
	_signaling_back()
	print("[net] back in room %s as player %d" % [room_code, local_id()])
	_set_host(int(message.get("host", host_id)))


## The signaling server says a player left the room: we let go of them.
func _forget(id: int) -> void:
	_members.erase(id)
	_order.erase(id)
	_newcomers.erase(id)
	_lost.erase(id)
	_reconnect_at.erase(id)
	left_room.emit(id)
	_drop(id)


## New STUN/TURN servers from the signaling server replace ours, unless they
## come without the relay (Cloudflare didn't answer it just then) and ours have it.
func _update_ice(servers: Array) -> void:
	if not servers.is_empty() and (_has_relay(servers) or not _has_relay(_ice_servers)):
		_ice_servers = servers


static func _has_relay(servers: Array) -> bool:
	return JSON.stringify(servers).contains("turn")


## Whether connections between players go over WebRTC: always in the
## browser; on desktop when the webrtc-native extension loaded, unless
## --net=enet (the co-op tests) says otherwise.
static func uses_webrtc() -> bool:
	if OS.has_feature("web"):
		return true
	match LaunchOptions.get_string("net"):
		"enet":
			return false
		"webrtc":
			return true
	return _has_webrtc()


## Whether a WebRTC library is there (desktop: the GDExtension loaded).
static func _has_webrtc() -> bool:
	if _webrtc < 0:
		var probe := WebRTCPeerConnection.new()
		_webrtc = 1 if probe.initialize({}) == OK else 0
		probe.close()
		if _webrtc == 0:
			push_warning("[net] no WebRTC library: co-op connects over ENet, so only with other desktop games on this machine")
	return _webrtc == 1


func _open_mesh(id: int) -> void:
	if uses_webrtc():
		var rtc := WebRTCMultiplayerPeer.new()
		rtc.create_mesh(id)
		_mesh = rtc
	else:
		var enet := ENetMultiplayerPeer.new()
		enet.create_mesh(id)
		_mesh = enet
	multiplayer.multiplayer_peer = _mesh


## Starts connecting to a player who just joined, or to one we lost touch
## with (we make the offer).
func _offer(id: int) -> void:
	if _mesh is WebRTCMultiplayerPeer:
		_add_connection(id).create_offer()
	elif _mesh is ENetMultiplayerPeer:
		# Listen on a port of the system's choosing; they connect to it.
		var host := ENetConnection.new()
		if host.create_host_bound("127.0.0.1", 0, 1, ENET_CHANNELS) == OK:
			_connections[id] = host
			_send({type = "signal", to = id, data = {kind = "enet", port = host.get_local_port()}})


func _add_connection(id: int) -> WebRTCPeerConnection:
	var connection := WebRTCPeerConnection.new()
	var config := {"iceServers": _ice_servers}
	if LaunchOptions.get_string("relay", "0") != "0":
		config.iceTransportPolicy = "relay"
		if not _has_relay(_ice_servers):
			push_warning("[net] ?relay=1, but the co-op server offers no TURN relay")
	connection.initialize(config)
	connection.session_description_created.connect(func(type: String, sdp: String) -> void:
		connection.set_local_description(type, sdp)
		_send({type = "signal", to = id, data = {kind = type, sdp = sdp}}))
	connection.ice_candidate_created.connect(func(media: String, index: int, candidate: String) -> void:
		_send({type = "signal", to = id, data = {kind = "candidate", media = media, index = index, name = candidate}}))
	(_mesh as WebRTCMultiplayerPeer).add_peer(connection, id)
	_connections[id] = connection
	return connection


func _on_signal(from: int, data: Dictionary) -> void:
	if not _members.has(from):
		return
	if data.get("kind") == "enet" and _mesh is ENetMultiplayerPeer:
		_drop(from)  # (a connection that broke on their side first)
		var host := ENetConnection.new()
		if host.create_host(1, ENET_CHANNELS) == OK \
				and host.connect_to_host("127.0.0.1", int(data.port), ENET_CHANNELS) != null:
			_connections[from] = host
		return
	var connection := _connections.get(from) as WebRTCPeerConnection
	if data.get("kind") == "offer" and _mesh is WebRTCMultiplayerPeer \
			and (connection == null or connection.get_connection_state() != WebRTCPeerConnection.STATE_NEW):
		# They're connecting again: the connection we had broke.
		_drop(from)
		connection = _add_connection(from)
	if connection == null:
		return
	match data.get("kind"):
		"offer", "answer":
			# Setting an offer makes the connection create the answer.
			connection.set_remote_description(data.kind, data.sdp)
		"candidate":
			connection.add_ice_candidate(data.media, int(data.index), data.name)


## ENet connections join the mesh once they're through.
func _poll_enet_connections() -> void:
	for id: int in _connections.keys():
		var host: ENetConnection = _connections[id]
		if host.service()[0] == ENetConnection.EVENT_CONNECT:
			_connections.erase(id)
			host.get_peers()[0].set_timeout(0, ENET_TIMEOUT.x, ENET_TIMEOUT.y)
			(_mesh as ENetMultiplayerPeer).add_mesh_peer(id, host)


## Closes the connection to a player who left (peer_disconnected follows).
func _drop(id: int) -> void:
	var connection: Object = _connections.get(id)
	_connections.erase(id)
	if _mesh is WebRTCMultiplayerPeer:
		if (_mesh as WebRTCMultiplayerPeer).has_peer(id):
			(_mesh as WebRTCMultiplayerPeer).remove_peer(id)
	elif _mesh is ENetMultiplayerPeer:
		if connection:
			(connection as ENetConnection).destroy()
		elif multiplayer.get_peers().has(id):
			(_mesh as ENetMultiplayerPeer).get_peer(id).peer_disconnect_now()
			_mesh.poll()  # it lets go of them now, not on the next frame


func _connected(id: int) -> bool:
	return multiplayer.get_peers().has(id)


func _on_peer_connected(id: int) -> void:
	_lost.erase(id)
	_reconnect_at.erase(id)
	player_joined.emit(id)
	_newcomers.erase(id)  # (after player_joined: is_newcomer)
	_follow_host()


func _on_peer_disconnected(id: int) -> void:
	if _members.has(id):
		# The server still counts them in: tell it, unless it says they left
		# meanwhile (its word usually comes a moment after). If they're still
		# there, the one of us with the lower number connects again.
		_lost[id] = false
		_report_cooldown = maxf(_report_cooldown, 0.5)
		if local_id() < id:
			_reconnect_at[id] = Time.get_ticks_msec() + RECONNECT_DELAY
	player_left.emit(id)


func _set_host(id: int) -> void:
	if id != host_id:
		host_id = id
		if state != State.OFFLINE:
			print("[net] player %d is the host" % id)
		host_changed.emit(id)
	_follow_host()


## We're HOSTING when we're the host, and JOINED once connected to the host.
func _follow_host() -> void:
	if state == State.OFFLINE:
		return
	if host_id == local_id():
		if state != State.HOSTING:
			_set_state(State.HOSTING)
	elif state == State.HOSTING:
		# The server let us go while it was out of touch with us, and named
		# another host: their game runs the thugs now.
		_set_state(State.JOINED)
	elif _connected(host_id):
		if state == State.CONNECTING:
			print("[net] connected to room %s" % room_code)
			_set_state(State.JOINED)
	elif state == State.JOINED and not _lost.has(host_id):
		_lost[host_id] = false  # not yet, anyway: the server checks on them


func _send(message: Dictionary) -> void:
	if _signaling and _signaling.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_signaling.send_text(JSON.stringify(message))


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit()
