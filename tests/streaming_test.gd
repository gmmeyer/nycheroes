extends Node
## Headless check of city streaming across the five boroughs: at each spot,
## waits for tiles to finish loading, then checks that no tile is drawn
## together with an ancestor or descendant (doubled-up geometry) and that the
## ground around the camera is covered by some drawn tile (no holes). Also
## checks that every loaded tile with an aerial photo shows it, that the
## photos of tiles that have unloaded are freed, that near tiles have their
## trees and water towers (as many as the tile holds) and road markings, and
## that the tree canopy map has reached the ground material (if the city has
## one).
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
## Every aerial photo texture seen so far: instance id -> WeakRef.
var _photo_refs := {}
var _expects_canopy := false


func _ready() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	for node_name in ["PlayerInput", "Crowd", "Encounters", "Hero"]:
		world.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	_city = world.get_node("City")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/tiles/%s/manifest.json" % _city.region))
	_expects_canopy = manifest is Dictionary and manifest.has("canopy")
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
	# Photos: shown on every loaded tile that has one, and gone with their tiles.
	var photos := 0
	var missing := 0
	for level in _city._levels.size():
		for tile in _city._levels[level]["tiles"]:
			if tile.node == null:
				continue
			var photo := _photo_of(tile.node)
			if photo:
				photos += 1
				_photo_refs[photo.get_instance_id()] = weakref(photo)
			elif _city._photos_enabled and tile.info.get("aerial"):
				missing += 1
	var leaked := -photos
	for ref: WeakRef in _photo_refs.values():
		if ref.get_ref():
			leaked += 1
	# Near tiles: their props drawn as MultiMeshes holding every one of them,
	# and road markings. Every spot with near tiles has streets and trees.
	var props := 0
	var water_towers := 0
	var with_markings := 0
	var miscounted := 0
	for tile in _city._levels[CityStreamer.LEVEL_NEAR]["tiles"]:
		if tile.node == null:
			continue
		var instances := 0
		for child in tile.node.get_children():
			if child is MultiMeshInstance3D and not String(child.name).ends_with("Shadows"):
				instances += child.multimesh.instance_count
				if child.name == "WaterTowers":
					water_towers += child.multimesh.instance_count
			elif child.name == "Markings":
				with_markings += 1
		if instances != tile.prop_count:
			miscounted += 1
		props += instances
	var near_ok: bool = loaded[CityStreamer.LEVEL_NEAR] == 0 or (props > 0 and with_markings > 0 and miscounted == 0)
	var canopy_ok: bool = _city.canopy_loaded or not _expects_canopy
	var ok := doubled == 0 and holes == 0 and missing == 0 and leaked == 0 and near_ok and canopy_ok and _time < MAX_WAIT
	if not ok:
		_problems += 1
	print("%-24s %5.1fs  loaded %s  drawn %s  doubled %d  holes %d  photos %d (missing %d, leaked %d)  props %d (%d water towers, %d miscounted)  markings in %d  canopy %s  %s" % [
		SPOTS[_spot][0], _time, loaded, visible, doubled, holes, photos, missing, leaked, props, water_towers, miscounted,
		with_markings, "ok" if canopy_ok else "MISSING", "ok" if ok else "PROBLEM"])


## The aerial photo a tile's node is showing, or null.
func _photo_of(node: Node3D) -> Texture2D:
	for child in node.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			var photo: Texture2D = child.material_override.get_shader_parameter("aerial")
			if photo:
				return photo
	return null


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
