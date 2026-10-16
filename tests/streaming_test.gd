extends Node
## Headless check of city streaming across the five boroughs: at each spot,
## waits for tiles to finish loading, then checks that no tile is drawn
## together with an ancestor or descendant (doubled-up geometry) and that the
## ground around the camera is covered by some drawn tile (no holes). Also
## checks that every loaded tile with an aerial photo shows it, that the
## photos of tiles that have unloaded are freed, that near tiles have their
## trees, water towers, street lights and street furniture (as many as the
## tile holds), the street lights' glows, and road markings, that each near
## tile's small and large furniture MultiMeshes hold exactly the pieces of
## their types in the tile's file (and its parked cars' MultiMesh exactly its
## parked cars), that each near tile with street lights, bus shelters or
## newsstands has its pools in the street light map (and none are left of
## tiles that have gone), and that the tree canopy map has reached the ground
## material (if the city has one).
## Run: godot --headless --path . res://tests/streaming_test.tscn

## Street furniture's and parked cars' MultiMeshes and the prop types each
## holds.
const FURNITURE_GROUPS := {
	"SmallFurniture": [CityTileDecoder.PROP_HYDRANT, CityTileDecoder.PROP_BENCH, CityTileDecoder.PROP_LITTER_BASKET,
		CityTileDecoder.PROP_BIKE_RACK, CityTileDecoder.PROP_PARKING_METER],
	"LargeFurniture": [CityTileDecoder.PROP_BUS_SHELTER, CityTileDecoder.PROP_LINKNYC,
		CityTileDecoder.PROP_SUBWAY_ENTRANCE, CityTileDecoder.PROP_TRAFFIC_SIGNAL, CityTileDecoder.PROP_NEWSSTAND],
	"ParkedCars": [CityTileDecoder.PROP_PARKED_CAR],
}

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
## Furniture per type in each near tile's file, by tile: Vector2i -> {type: count}.
var _furniture_in_file := {}


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
	# Near tiles: their props drawn as MultiMeshes holding every one of them
	# (furniture checked against the tile's file), street lights with as many
	# glows, their pools (and lit furniture's) in the light map, and road
	# markings. Every spot with near tiles has streets, trees and street lights.
	var props := 0
	var water_towers := 0
	var street_lights := 0
	var furniture := 0
	var parked_cars := 0
	var with_markings := 0
	var with_pools := 0
	var miscounted := 0
	var furniture_miscounted := 0
	for tile in _city._levels[CityStreamer.LEVEL_NEAR]["tiles"]:
		if tile.node == null:
			continue
		var instances := 0
		var lamps := 0
		var glows := 0
		for child in tile.node.get_children():
			if child is MultiMeshInstance3D and String(child.name) in CityProps.GROUP_NAMES:
				instances += child.multimesh.instance_count
				if child.name == "WaterTowers":
					water_towers += child.multimesh.instance_count
				elif child.name == "StreetLights":
					lamps = child.multimesh.instance_count
				elif child.name == "ParkedCars":
					parked_cars += child.multimesh.instance_count
			elif child.name == CityProps.GLOW_NAME:
				glows = child.multimesh.instance_count
			elif child.name == "Markings":
				with_markings += 1
		if instances != tile.prop_count or glows != lamps:
			miscounted += 1
		var pieces := _check_furniture(tile)
		if pieces < 0:
			furniture_miscounted += 1
		else:
			furniture += pieces
		props += instances
		street_lights += lamps
		var in_file: Dictionary = _furniture_in_file.get(Vector2i(tile.i, tile.j), {})
		var lit: int = in_file.get(CityTileDecoder.PROP_BUS_SHELTER, 0) + in_file.get(CityTileDecoder.PROP_NEWSSTAND, 0)
		with_pools += 1 if lamps > 0 or lit > 0 else 0
	var pools: int = _city.light_pool_count()
	var near_ok: bool = loaded[CityStreamer.LEVEL_NEAR] == 0 or (props > 0 and street_lights > 0
			and with_markings > 0 and miscounted == 0)
	near_ok = near_ok and pools == with_pools and furniture_miscounted == 0
	var canopy_ok: bool = _city.canopy_loaded or not _expects_canopy
	var ok := doubled == 0 and holes == 0 and missing == 0 and leaked == 0 and near_ok and canopy_ok and _time < MAX_WAIT
	if not ok:
		_problems += 1
	print("%-24s %5.1fs  loaded %s  drawn %s  doubled %d  holes %d  photos %d (missing %d, leaked %d)  props %d (%d water towers, %d street lights, %d furniture, %d parked cars, %d miscounted, %d furniture or cars miscounted)  light pools in %d of %d  markings in %d  canopy %s  %s" % [
		SPOTS[_spot][0], _time, loaded, visible, doubled, holes, photos, missing, leaked, props, water_towers, street_lights,
		furniture - parked_cars, parked_cars, miscounted, furniture_miscounted, pools, with_pools, with_markings,
		"ok" if canopy_ok else "MISSING", "ok" if ok else "PROBLEM"])


## Checks a near tile's furniture MultiMeshes against its file: each holds
## exactly as many pieces of each of its types as the file has. Returns how
## many pieces they hold, or -1 if they're off.
func _check_furniture(tile) -> int:
	var key := Vector2i(tile.i, tile.j)
	if not _furniture_in_file.has(key):
		var counts := {}
		var path: String = _city._local_dir() + "%s/%d_%d.nyct" % [_city._levels[tile.level]["name"], tile.i, tile.j]
		for surface in CityTileDecoder.decode(FileAccess.get_file_as_bytes(path), int(tile.info.raw_bytes)):
			if surface.kind == CityTileDecoder.SURFACE_PROPS:
				for uv2: Vector2 in surface.uv2:
					var type := roundi(uv2.x)
					counts[type] = counts.get(type, 0) + 1
		_furniture_in_file[key] = counts
	var in_file: Dictionary = _furniture_in_file[key]
	var total := 0
	for group: String in FURNITURE_GROUPS:
		var drawn := {}
		var node := tile.node.get_node_or_null(group) as MultiMeshInstance3D
		if node:
			# Each instance's type is the last of its CityProps.STRIDE floats.
			var buffer := node.multimesh.buffer
			for k in node.multimesh.instance_count:
				var type := roundi(buffer[k * CityProps.STRIDE + CityProps.STRIDE - 1])
				drawn[type] = drawn.get(type, 0) + 1
		for type: int in drawn:
			if not type in FURNITURE_GROUPS[group]:
				push_error("Tile %s: a %s holds prop type %d" % [tile.node.name, group, type])
				return -1
		for type: int in FURNITURE_GROUPS[group]:
			if drawn.get(type, 0) != in_file.get(type, 0):
				push_error("Tile %s: %d pieces of type %d drawn, %d in the file" % [
					tile.node.name, drawn.get(type, 0), type, in_file.get(type, 0)])
				return -1
			total += drawn.get(type, 0)
	return total


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
