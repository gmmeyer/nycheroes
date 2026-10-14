extends Node
## Headless check of city streaming across the five boroughs: at each spot,
## waits for tiles to finish loading, then checks that no tile is drawn
## together with an ancestor or descendant (doubled-up geometry) and that the
## ground around the camera is covered by some drawn tile (no holes).
## Run: godot --headless --path . res://tests/streaming_test.tscn

## [name, world position of the camera]
const SPOTS := [
	["Times Square", Vector3(0.0, 120.0, 0.0)],
	["Brooklyn Bridge", Vector3(-960.0, 80.0, 5768.0)],
	["Coney Island", Vector3(1247.0, 120.0, 20282.0)],
	["Flushing Meadows", Vector3(11850.0, 200.0, 1323.0)],
	["Staten Island", Vector3(-13870.0, 200.0, 19780.0)],
	["Bronx (Yankee Stadium)", Vector3(4998.0, 150.0, -7957.0)],
	["At the ceiling", Vector3(0.0, 1000.0, 10000.0)],
]
const MAX_WAIT := 60.0

var _city: CityStreamer
var _camera: FreeFlyCamera
var _spot := -1
var _time := 0.0
var _settled := 0.0
var _problems := 0


func _ready() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	for node_name in ["PlayerInput", "Crowd", "Encounters", "Hero"]:
		world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_city = world.get_node("City")
	_camera = world.get_node("FreeCamera")
	_camera.current = true
	_camera.set_process(false)
	WorldOrigin.focus = _camera
	_next_spot()


func _process(delta: float) -> void:
	_time += delta
	_settled = _settled + delta if _city.pending_count() == 0 and _time > 1.0 else 0.0
	if _settled < 1.0 and _time < MAX_WAIT:
		return
	_check()
	_next_spot()


func _next_spot() -> void:
	_spot += 1
	if _spot >= SPOTS.size():
		print("streaming test finished: %d problems" % _problems)
		get_tree().quit(1 if _problems else 0)
		return
	_camera.global_position = WorldOrigin.to_local(SPOTS[_spot][1])
	_time = 0.0
	_settled = 0.0


func _check() -> void:
	var visible := [0, 0, 0]
	var loaded := [0, 0, 0]
	var doubled := 0
	for level in _city._levels.size():
		for tile in _city._levels[level]["tiles"]:
			if tile.node == null:
				continue
			loaded[level] += 1
			if not tile.node.visible:
				continue
			visible[level] += 1
			var ancestor = tile.parent
			while ancestor:
				if ancestor.node and ancestor.node.visible:
					doubled += 1
				ancestor = ancestor.parent
	# Coverage: sample points around the camera; each must be drawn at some level
	# (or have no tile at any level, which means open water).
	var holes := 0
	var focus: Vector3 = SPOTS[_spot][1]
	for k in 24:
		var angle := TAU * k / 24.0
		for radius: float in [50.0, 400.0, 1500.0]:
			var point := focus + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if not _drawn_at(point):
				holes += 1
	var ok := doubled == 0 and holes == 0 and _time < MAX_WAIT
	if not ok:
		_problems += 1
	print("%-24s %5.1fs  loaded %s  drawn %s  doubled %d  holes %d  %s" % [
		SPOTS[_spot][0], _time, loaded, visible, doubled, holes, "ok" if ok else "PROBLEM"])


## True if something is drawn at this point, or nothing needs to be: no tile
## covers it, or the most detailed tile there has handed over to its children
## and none of them covers this spot (open water at that detail).
func _drawn_at(point: Vector3) -> bool:
	var deepest = null
	for level in _city._levels.size():
		var tile = _city._tile_at(level, point)
		if tile == null:
			continue
		if deepest == null:
			deepest = tile
		if tile.node and tile.node.visible:
			return true
	return deepest == null or _city._children_ready(deepest)
