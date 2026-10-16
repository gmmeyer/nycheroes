extends RefCounted
## Runs the co-op signaling server (tools/signaling/server.mjs, Node.js) for
## the co-op tests, whose games connect through it like players' do (then over
## ENet, as desktop builds have no WebRTC). Needs `npm install` in
## tools/signaling once.

var pid := 0
var _port := 0
var _started_msec := 0
var _probe: StreamPeerTCP


## Starts the server on `port`. Returns what went wrong, or "" if it's starting.
func start(port: int) -> String:
	var dir := ProjectSettings.globalize_path("res://tools/signaling")
	if not DirAccess.dir_exists_absolute(dir.path_join("node_modules/ws")):
		return "the co-op server needs `npm install` in tools/signaling"
	_port = port
	OS.set_environment("PORT", str(port))
	pid = OS.create_process("node", [dir.path_join("server.mjs")])
	_started_msec = Time.get_ticks_msec()
	return "" if pid > 0 else "couldn't start Node.js (node server.mjs)"


## True once it takes connections (ask every frame while waiting). Not before a
## second has passed, so a server already on the port (ours then quits) isn't
## mistaken for ours.
func is_up() -> bool:
	if pid == 0 or not OS.is_process_running(pid):
		return false
	if _probe == null:
		_probe = StreamPeerTCP.new()
		_probe.connect_to_host("127.0.0.1", _port)
	_probe.poll()
	match _probe.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			_probe.disconnect_from_host()
			_probe = null
			return Time.get_ticks_msec() - _started_msec > 1000 and OS.is_process_running(pid)
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			_probe = null  # not listening yet
	return false


func stop() -> void:
	if pid and OS.is_process_running(pid):
		OS.kill(pid)
	pid = 0
