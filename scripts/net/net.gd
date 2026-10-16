extends Node
## Co-op sessions (autoload "Net"): hosting and joining games, and who's in them.
##
## Players find each other through a small signaling server (tools/signaling
## locally, tools/cloudflare on the public site) using a short room code,
## then connect directly over WebRTC, every player to every other (a full
## mesh). One of them is the host: its game runs the thugs and decides every
## hit (see Combat). When the host leaves, the game goes on: the signaling
## server names the player who has been in the room longest the new host
## (host_changed), whose game takes the thugs over from the copies it and the
## others have (see EncounterDirector); the room keeps its code, so friends
## can still join. Desktop builds have no WebRTC, so tests connect over ENet
## on this machine instead, through the same signaling.
##
## The signaling server only hears of players through their sockets: games
## ping it every PING_INTERVAL, and tell it when they lose touch with a player
## it still counts in the room, so it can drop players whose connection died
## without closing (a host whose Wi-Fi went away) and pick a new host. If such
## a player is still there, only the connection between us broke: the one of
## us with the lower number connects again.
##
## Launch options (read by Game): ?host hosts a game, ?join=CODE joins one,
## ?signal=wss://... picks the signaling server (default: /signal on the page's
## host over https, else the page's host on port 8070), and ?relay=1 connects
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

enum State { OFFLINE, CONNECTING, HOSTING, JOINED }

## The first host's number (and ours when offline).
const FIRST_HOST := 1
const MAX_PLAYERS := 8
const SIGNALING_PORT := 8070
## Give up on reaching a host after this long (seconds).
const CONNECT_TIMEOUT := 20.0
## After losing touch with the host, give up on the game after this long
## (seconds) if the signaling server hasn't named a new host meanwhile.
const HOST_TIMEOUT := 60.0
## Seconds between pings to the signaling server, and between reports of
## players we've lost touch with.
const PING_INTERVAL := 10.0
const LOST_REPORT_INTERVAL := 5.0
## After a connection to a player still in the room drops, connect again after
## this long, and again every RECONNECT_INTERVAL while it's down (msec).
const RECONNECT_DELAY := 2000
const RECONNECT_INTERVAL := 10000
## ENet (desktop and tests) channels per connection: enough for
## ENetMultiplayerPeer's own and the RPCs'.
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

var _signaling: WebSocketPeer
var _signaling_url := ""
var _greeting := {}  # first message to send once the signaling socket opens
var _mesh: MultiplayerPeer  # WebRTCMultiplayerPeer, or ENetMultiplayerPeer on desktop
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


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(delta: float) -> void:
	if _signaling:
		_poll_signaling()
	if _mesh is ENetMultiplayerPeer:
		_poll_enet_connections()
	if state == State.CONNECTING:
		_connect_time += delta
		if _connect_time > CONNECT_TIMEOUT:
			leave("Couldn't reach the game. The host's or your network may be blocking it.")
			return
	_host_missing_time = _host_missing_time + delta if state == State.JOINED and not _connected(host_id) else 0.0
	if _host_missing_time > HOST_TIMEOUT:
		leave("Lost the connection to the host.")
		return
	_ping_cooldown -= delta
	if _ping_cooldown <= 0.0 and _signaling and _signaling.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ping_cooldown = PING_INTERVAL
		_signaling.send_text("ping")
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


## Whether this game runs the thugs and decides hits: true when playing alone
## or hosting, false when playing in someone else's game.
func is_authority() -> bool:
	return state != State.JOINED


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


## A link that opens the game and joins this room (web only).
func invite_link() -> String:
	if room_code.is_empty() or not OS.has_feature("web"):
		return room_code
	var link := str(JavaScriptBridge.eval("location.origin + location.pathname")) + "?join=" + room_code
	if LaunchOptions.has("signal"):
		link += "&signal=" + LaunchOptions.get_string("signal").uri_encode()
	return link


func host() -> void:
	_start({type = "host"})


func join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.is_empty():
		error = "Type in the room code first."
		state_changed.emit()
		return
	_start({type = "join", code = code})


## Leaves the game. `reason`, if any, is shown to the player. The others play on.
func leave(reason := "") -> void:
	var was_offline := state == State.OFFLINE
	_reset()
	error = reason
	if reason:
		push_warning("[net] " + reason)
	if not was_offline or reason:
		_set_state(State.OFFLINE)


func _reset() -> void:
	error = ""
	if _signaling:
		_signaling.close()
		_signaling = null
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
	state = State.OFFLINE
	_set_host(FIRST_HOST)


func _start(greeting: Dictionary) -> void:
	_reset()
	_signaling_url = _default_signaling_url()
	_signaling = WebSocketPeer.new()
	if _signaling.connect_to_url(_signaling_url) != OK:
		leave("Couldn't reach the co-op server at %s." % _signaling_url)
		return
	_greeting = greeting
	_connect_time = 0.0
	_ping_cooldown = PING_INTERVAL
	_set_state(State.CONNECTING)


func _default_signaling_url() -> String:
	if LaunchOptions.has("signal"):
		return LaunchOptions.get_string("signal")
	if not OS.has_feature("web"):
		return "ws://127.0.0.1:%d" % SIGNALING_PORT
	# The public site (https, tools/cloudflare) has it at /signal on the same
	# host; a local build (tools/build_web.ps1 -Serve) on its own port.
	if str(JavaScriptBridge.eval("location.protocol")) == "https:":
		return "wss://%s/signal" % str(JavaScriptBridge.eval("location.host"))
	return "ws://%s:%d" % [str(JavaScriptBridge.eval("location.hostname")), SIGNALING_PORT]


func _poll_signaling() -> void:
	_signaling.poll()
	match _signaling.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _greeting.is_empty():
				_send(_greeting)
				_greeting = {}
			while _signaling and _signaling.get_available_packet_count() > 0:
				var text := _signaling.get_packet().get_string_from_utf8()
				if text == "pong":
					continue
				var message = JSON.parse_string(text)
				if typeof(message) == TYPE_DICTIONARY:
					_on_signaling_message(message)
		WebSocketPeer.STATE_CLOSED:
			_signaling = null
			if state != State.OFFLINE:
				# Without it nobody new can join, and the server has told the
				# others we left.
				leave("Lost the connection to the co-op server at %s." % _signaling_url)


func _on_signaling_message(message: Dictionary) -> void:
	match message.get("type"):
		"hosted":
			room_code = message.code
			_ice_servers = message.get("ice", [])
			_open_mesh(int(message.id))
			print("[net] hosting room %s" % room_code)
			_set_host(int(message.id))
		"joined":
			room_code = message.code
			_ice_servers = message.get("ice", [])
			_open_mesh(int(message.id))
			# The players already in the room each send us an offer.
			for id in message.get("peers", [FIRST_HOST]):
				_members[int(id)] = true
				if _mesh is WebRTCMultiplayerPeer:
					_add_connection(int(id))
			print("[net] joining room %s as player %d" % [room_code, int(message.id)])
			_set_host(int(message.get("host", FIRST_HOST)))
		"peer_joined":
			# Fresh relay credentials, if the server sends them: a game can go
			# on for longer than they last.
			_ice_servers = message.get("ice", _ice_servers)
			var id := int(message.id)
			_members[id] = true
			_newcomers[id] = true
			_offer(id)
		"peer_left":
			var id := int(message.id)
			_members.erase(id)
			_newcomers.erase(id)
			_lost.erase(id)
			_reconnect_at.erase(id)
			left_room.emit(id)
			_drop(id)
			# The host may have been the one leaving; the server names the next.
			_set_host(int(message.get("host", host_id)))
		"signal":
			_on_signal(int(message.from), message.get("data", {}))
		"error":
			leave(str(message.get("message", "Something went wrong.")))


func _open_mesh(id: int) -> void:
	if OS.has_feature("web"):
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
		if not JSON.stringify(_ice_servers).contains("turn"):
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
