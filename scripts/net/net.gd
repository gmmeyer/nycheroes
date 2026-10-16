extends Node
## Co-op sessions (autoload "Net"): hosting and joining games, and who's in them.
##
## Players find each other through a small signaling server (tools/signaling
## locally, tools/cloudflare on the public site) using a short room code,
## then connect directly over WebRTC in a star: every
## player connects to the host, whose game runs the thugs and decides every hit
## (see Combat), and Godot relays messages between the other players. Desktop
## builds have no WebRTC, so tests connect over ENet instead.
##
## Launch options (read by Game): ?host hosts a game, ?join=CODE joins one,
## ?signal=wss://... picks the signaling server (default: /signal on the page's
## host over https, else the page's host on port 8070), and ?relay=1 connects
## only through the TURN relay the signaling server hands out, to test the path
## players on strict networks need.

signal state_changed
signal player_joined(id: int)
signal player_left(id: int)

enum State { OFFLINE, CONNECTING, HOSTING, JOINED }

const HOST_ID := 1
const MAX_PLAYERS := 8
const SIGNALING_PORT := 8070
## Give up on reaching a host after this long (seconds).
const CONNECT_TIMEOUT := 20.0
## One color per player number (1 is the host), used for their hero's suit.
const PLAYER_COLORS: Array[Color] = [
	Color(0.72, 0.06, 0.08), Color(0.1, 0.3, 0.85), Color(0.1, 0.6, 0.2), Color(0.9, 0.7, 0.05),
	Color(0.55, 0.15, 0.75), Color(0.95, 0.45, 0.05), Color(0.05, 0.7, 0.75), Color(0.85, 0.85, 0.85),
]

var state := State.OFFLINE
var room_code := ""
## The last problem worth telling the player about (empty when all is well).
var error := ""

var _signaling: WebSocketPeer
var _signaling_url := ""
var _greeting := {}  # first message to send once the signaling socket opens
var _rtc: WebRTCMultiplayerPeer
var _connections := {}  # peer id -> WebRTCPeerConnection (WebRTC only)
var _ice_servers: Array = []
var _connect_time := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: player_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: player_left.emit(id))
	multiplayer.connected_to_server.connect(_on_connected_to_host)
	multiplayer.connection_failed.connect(func() -> void: leave("Couldn't connect to the host."))
	multiplayer.server_disconnected.connect(func() -> void: leave("Lost the connection to the host."))


func _process(delta: float) -> void:
	if _signaling:
		_poll_signaling()
	if state == State.CONNECTING:
		_connect_time += delta
		if _connect_time > CONNECT_TIMEOUT:
			leave("Couldn't reach the game. The host's or your network may be blocking it.")


func is_online() -> bool:
	return state == State.HOSTING or state == State.JOINED


## Whether this game runs the thugs and decides hits: true when playing alone
## or hosting, false when playing in someone else's game.
func is_authority() -> bool:
	return state != State.JOINED


## This player's number: 1 for the host (and when offline).
func local_id() -> int:
	return multiplayer.get_unique_id()


func player_name(id: int) -> String:
	return "Player %d" % (id if id <= 99 else id % 100)


func player_color(id: int) -> Color:
	return PLAYER_COLORS[(id - 1) % PLAYER_COLORS.size()]


## Everyone else in the game.
func peers() -> PackedInt32Array:
	return multiplayer.get_peers() if is_online() else PackedInt32Array()


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


## Hosts over ENet on the local network (desktop and tests; no signaling).
func host_enet(port: int) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		return result
	multiplayer.multiplayer_peer = peer
	room_code = "LAN"
	_set_state(State.HOSTING)
	return OK


func join_enet(address: String, port: int) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port)
	if result != OK:
		return result
	multiplayer.multiplayer_peer = peer
	room_code = "LAN"
	_connect_time = 0.0
	_set_state(State.CONNECTING)
	return OK


## Leaves the game (or stops hosting it). `reason`, if any, is shown to the player.
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
	for connection: WebRTCPeerConnection in _connections.values():
		connection.close()
	_connections.clear()
	_rtc = null
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	room_code = ""
	state = State.OFFLINE


func _start(greeting: Dictionary) -> void:
	_reset()
	if not OS.has_feature("web"):
		error = "Co-op needs the web version of the game."
		state_changed.emit()
		return
	_signaling_url = _default_signaling_url()
	_signaling = WebSocketPeer.new()
	if _signaling.connect_to_url(_signaling_url) != OK:
		leave("Couldn't reach the co-op server at %s." % _signaling_url)
		return
	_greeting = greeting
	_connect_time = 0.0
	_set_state(State.CONNECTING)


func _default_signaling_url() -> String:
	if LaunchOptions.has("signal"):
		return LaunchOptions.get_string("signal")
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
				var message = JSON.parse_string(_signaling.get_packet().get_string_from_utf8())
				if typeof(message) == TYPE_DICTIONARY:
					_on_signaling_message(message)
		WebSocketPeer.STATE_CLOSED:
			_signaling = null
			if state == State.CONNECTING or state == State.HOSTING:
				# Hosts need the server to let new players in; joined players don't.
				leave("Lost the connection to the co-op server at %s." % _signaling_url)


func _on_signaling_message(message: Dictionary) -> void:
	match message.get("type"):
		"hosted":
			room_code = message.code
			_ice_servers = message.get("ice", [])
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_server()
			multiplayer.multiplayer_peer = _rtc
			print("[net] hosting room %s" % room_code)
			_set_state(State.HOSTING)
		"joined":
			room_code = message.code
			_ice_servers = message.get("ice", [])
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_client(int(message.id))
			multiplayer.multiplayer_peer = _rtc
			_add_connection(HOST_ID)  # the host sends the offer
			print("[net] joining room %s as player %d" % [room_code, int(message.id)])
		"peer_joined":
			# Fresh relay credentials, if the server sends them: a game can be
			# hosted for longer than they last.
			_ice_servers = message.get("ice", _ice_servers)
			_add_connection(int(message.id)).create_offer()
		"peer_left":
			var id := int(message.id)
			if _rtc and _rtc.has_peer(id):
				_rtc.remove_peer(id)
			_connections.erase(id)
		"signal":
			_on_signal(int(message.from), message.get("data", {}))
		"room_closed":
			leave("The host closed the game.")
		"error":
			leave(str(message.get("message", "Something went wrong.")))


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
	_rtc.add_peer(connection, id)
	_connections[id] = connection
	return connection


func _on_signal(from: int, data: Dictionary) -> void:
	var connection: WebRTCPeerConnection = _connections.get(from)
	if connection == null:
		return
	match data.get("kind"):
		"offer", "answer":
			# Setting an offer makes the connection create the answer.
			connection.set_remote_description(data.kind, data.sdp)
		"candidate":
			connection.add_ice_candidate(data.media, int(data.index), data.name)


func _on_connected_to_host() -> void:
	print("[net] connected to room %s" % room_code)
	_set_state(State.JOINED)


func _send(message: Dictionary) -> void:
	if _signaling and _signaling.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_signaling.send_text(JSON.stringify(message))


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit()
