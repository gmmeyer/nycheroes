class_name RelayPeer
extends MultiplayerPeerExtension
## The multiplayer peer of a relayed public room: game traffic goes through
## the signaling server (Net's socket) instead of a connection to each player,
## so one room holds everyone online (see tools/signaling/server.mjs for the
## binary messages). Net tells it who's in the room (add_peer, remove_peer)
## and hands it what arrives (receive); it sends through `transport`.
##
## Packets sent to several players in a frame with the same contents (a
## hero's state to everyone near, an RPC to each player) go out as one message
## naming them all, so a game sends about as much in a room of fifty as of
## two. Everything arrives, in order (it's one WebSocket), whatever the
## transfer mode; unreliable packets are dropped instead when the socket is
## backed up (UNRELIABLE_BACKLOG).

## Sends one binary message to the server (Net's socket). Returns its Error.
var transport: Callable
## Bytes waiting in the socket to go out (Net's socket), to drop unreliable
## packets when it's backed up.
var backlog: Callable

## Unreliable packets wait while more than this is waiting to go out (bytes).
const UNRELIABLE_BACKLOG := 256 * 1024
## The server's limit is 64 KiB per message, headers and names included.
const MAX_PACKET := 60000
## Player numbers are 16 bits on the wire.
const MAX_ID := 65535

var _id := 0
var _peers := {}  # player number -> when we last heard from them (msec)
var _incoming: Array = []  # [from, channel, mode, packet]
var _outgoing: Array = []  # [players (empty: everyone), channel, mode, packet], in order
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _open := true


func _init(id: int) -> void:
	_id = id


## A player in the room (now, or since we came).
func add_peer(id: int) -> void:
	if not _open or _peers.has(id) or id == _id or id <= 0 or id > MAX_ID:
		return
	_peers[id] = Time.get_ticks_msec()
	peer_connected.emit(id)


## A player who left the room.
func remove_peer(id: int) -> void:
	if not _peers.erase(id):
		return
	_incoming = _incoming.filter(func(packet: Array) -> bool: return packet[0] != id)
	peer_disconnected.emit(id)


func has_peer(id: int) -> bool:
	return _peers.has(id)


## Players we haven't heard from for `msec` (every game sends its hero's state
## at least once a second): their game may be gone without its socket closing.
func silent_peers(msec: int) -> Array[int]:
	var now := Time.get_ticks_msec()
	var silent: Array[int] = []
	for id: int in _peers:
		if now - int(_peers[id]) > msec:
			silent.append(id)
	return silent


## A binary message from the server: [from u16][channel u8][mode u8][packet].
func receive(message: PackedByteArray) -> void:
	if not _open or message.size() < 4:
		return
	var from := message.decode_u16(0)
	if _peers.has(from):
		_peers[from] = Time.get_ticks_msec()
		_incoming.append([from, message[2], message[3], message.slice(4)])


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()[3]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if not _open:
		return ERR_UNCONFIGURED
	if buffer.size() > MAX_PACKET:
		return ERR_OUT_OF_MEMORY
	var players: Array[int] = []
	if _target > 0:
		if not _peers.has(_target):
			return ERR_INVALID_PARAMETER
		players.append(_target)
	elif _target < 0:
		for id: int in _peers:
			if id != -_target:
				players.append(id)
		if players.is_empty():
			return OK
	_outgoing.append([players, _channel, _mode, buffer])
	return OK


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return MAX_PACKET


func _get_packet_peer() -> int:
	return _incoming[0][0] if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return _incoming[0][1] if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _incoming[0][2] if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _id == 1


func _is_server_relay_supported() -> bool:
	return false


func _set_refuse_new_connections(_enable: bool) -> void:
	pass


func _is_refusing_new_connections() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return MultiplayerPeer.CONNECTION_CONNECTED if _open else MultiplayerPeer.CONNECTION_DISCONNECTED


func _disconnect_peer(id: int, _force: bool) -> void:
	remove_peer(id)


func _close() -> void:
	_open = false
	_outgoing.clear()
	_incoming.clear()
	for id: int in _peers.keys():
		remove_peer(id)


## Sends what the game put out since the last poll (SceneMultiplayer polls
## every frame).
func _poll() -> void:
	flush()


## Sends the packets waiting, one message per contents for all the players
## it's for. A packet joins an earlier one with the same contents only if
## none of its players has been sent anything after that one, so each player
## still gets everything in the order it was sent.
func flush() -> void:
	if _outgoing.is_empty() or not transport.is_valid():
		return
	var backed_up := backlog.is_valid() and int(backlog.call()) > UNRELIABLE_BACKLOG
	var merged: Array[Array] = []  # [players, channel, mode, packet]
	var by_contents := {}  # [channel, mode, packet] -> index in merged
	var last := {}  # player number -> index in merged of the last message for them
	for item: Array in _outgoing:
		if backed_up and item[2] != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
			continue
		var players: Array[int] = item[0]
		var key := [item[1], item[2], item[3]]
		var index: int = by_contents.get(key, -1)
		if index >= 0 and not players.is_empty() and not (merged[index][0] as Array).is_empty() \
				and players.all(func(id: int) -> bool:
					return int(last.get(id, -1)) <= index and not (merged[index][0] as Array).has(id)):
			(merged[index][0] as Array).append_array(players)
		else:
			index = merged.size()
			merged.append([players.duplicate(), item[1], item[2], item[3]])
			by_contents[key] = index
		for id: int in (players if not players.is_empty() else _peers.keys()):
			last[id] = index
	_outgoing.clear()
	for message: Array in merged:
		_send(message[0], message[1], message[2], message[3])


## [channel u8][mode u8][count u16][count x player u16][packet]
func _send(players: Array, channel: int, mode: int, packet: PackedByteArray) -> void:
	var header := PackedByteArray()
	header.resize(4 + players.size() * 2)
	header[0] = channel
	header[1] = mode
	header.encode_u16(2, players.size())
	for i in players.size():
		header.encode_u16(4 + i * 2, players[i])
	transport.call(header + packet)
