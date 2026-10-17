class_name CityStreamer
extends Node3D
## Streams the city around the camera from a three-level tile tree, built by
## tools/citygen/build_tiles.py into data/tiles/<region>/:
##   lod0: 500 m tiles, full detail, with collision, walking lanes, road
##         markings, trees, rooftop water towers, street lights, street
##         furniture, parked cars, and the lanes and tracks traffic and
##         trains run on
##   lod1: 1 km tiles, simplified
##   lod2: 4 km tiles, coarse, out to the horizon
## Tiles of every level also carry woods seen from afar, as clumps of crowns.
## A level's tiles load when their parent tile is near the camera. A tile is
## drawn until all its children have loaded; then the children are drawn
## instead, so there's never doubled-up or missing geometry. Collision comes
## from lod0 tiles whether or not they're drawn.
## Web builds fetch tiles over HTTP from tiles/<region>/ next to index.html
## (tools/build_web.ps1 copies them there).
## Buildings and ground are drawn by their own shaders (stylized facades from
## the tiles' per-building data), and so are road markings; trees, water
## towers, street lights, street furniture and parked cars are a few
## MultiMeshes per tile (CityProps). Signal poles and traffic keep time by one
## clock (TrafficSignals; the signal_clock shader global, set here). At
## night (city_lights, from TimeOfDay) street lights glow, and their pools of
## light go into a map around the camera that the shaders look up
## (StreetLightMap). The manifest's citywide
## tree canopy map (how much of each 16 m square is under trees) loads once at
## the start; the ground shader paints woods from it on parks and yards, out
## past where tree props draw, under the clumps of crowns. For comparison,
## ?aerial=1 on the page URL (--aerial=1 on desktop) drapes the city's aerial
## photos over the ground and roofs of tiles marked "aerial" in the manifest
## (aerial/<level>/<i>_<j>.jpg, fetched once the tile is built; web builds
## need tools/build_web.ps1 -Aerial); ?aerial_shadow=0.75&aerial_brightness=0.7
## tune their look (see shaders/aerial.gdshaderinc). ?tree_shadows=0 leaves
## out trees' shadows, for slower machines (they're about a third of what
## trees cost). On desktop, --tiles=DIR reads the tiles from DIR/<region>/
## instead (e.g. a copy with a few tiles rebuilt, for tests), and so does a
## tiles folder next to the executable; the editor reads data/tiles.
## Otherwise desktop builds stream the tiles from the public site like the web
## build (TILES_URL; --tiles_url=URL for another server), and keep each tile
## and the canopy map in user://tiles/<build>/<region>/, so places visited once
## load from disk after that. A new build of the tiles (the manifest's build
## id) starts a new cache and deletes the old one; without a network, the last
## build's cache is played from. Desktop builds also decode tiles on worker
## threads (WorkerThreadPool: reading the cache, unpacking, and laying out
## arrays and collision faces), making their meshes, nodes and collision on
## the main thread within the same per-frame budget; --decode_threads=0
## decodes on the main thread instead, as the web build does.

signal initial_load_finished(seconds: float)
## A near tile's driving lanes (world-space polylines, see
## CityTileDecoder.SURFACE_TRAFFIC) loaded, or unloaded (both empty).
signal traffic_lanes_changed(key: Vector2i, lanes: Array[PackedVector3Array], info: PackedFloat32Array)
## A near tile's el tracks (its decoded trains surface with world-space
## points, see CityTileDecoder.SURFACE_TRAINS) loaded, or unloaded (empty).
signal train_tracks_changed(key: Vector2i, tracks: Dictionary)

const LEVEL_NEAR := 0
const LEVEL_COUNT := 3
const UPDATE_INTERVAL := 0.25
const MAX_ATTEMPTS := 3
## A tile that failed is asked for again after this long times its failures.
const RETRY_MSEC := 1500
## Desktop builds: where tiles stream from, and where they're kept.
const TILES_URL := "https://nycheroes.party/tiles/"
const CACHE_ROOT := "user://tiles/"
## Desktop builds: a download that has taken this long is given up on (s); a
## big tile over a slow connection takes a while, but the manifest doesn't,
## and without it the game can't start (or play from the cache offline).
const REQUEST_TIMEOUT := 120.0
const MANIFEST_TIMEOUT := 10.0
## Desktop builds: tiles decoding on worker threads at once, at most.
const MAX_DECODES := 4
## Mesh surfaces without collision.
const NO_COLLISION: Array[int] = [CityTileDecoder.SURFACE_MARKINGS, CityTileDecoder.SURFACE_FRONTS]
## Physics layer 1, "world".
const COLLISION_LAYER := 1
## Physics layer 5, "water": raised lakes' surfaces, which nothing collides
## with but heroes look for to know where the water is.
const WATER_LAYER := 16
## Added to the camera distance when ordering downloads, so nearby detail
## arrives first and coarse tiles follow.
const LEVEL_PRIORITY: Array[float] = [0.0, 400.0, 1500.0]
## Added on top for a tile's aerial photo, so geometry nearby comes first.
const PHOTO_PRIORITY := 300.0
## Road markings stop drawing once their tile's center is this far from the
## camera (m); shaders/markings.gdshader fades the paint out before that.
const MARKINGS_RANGE := 1100.0
## Rowhouse fronts' railings, fences, shrubs and awnings stop drawing beyond
## this (their tile's center from the camera, m), where they're specks
## (Quality shortens it on phones and tablets: fronts_range).
const FRONTS_RANGE := 600.0
## How busy near tiles' sidewalks are (busyness_at()) is kept in squares this
## big (m), from what each kind of prop there counts for (by prop type): shops'
## signs and awnings, subway stairs, LinkNYC kiosks, bus stops, newsstands
## and the plazas' tables, planters, kiosks and bike docks.
const BUSY_CELL := 25.0
const BUSY_WEIGHTS := {
	CityTileDecoder.PROP_BUS_SHELTER: 1.0, CityTileDecoder.PROP_LINKNYC: 2.0, CityTileDecoder.PROP_BENCH: 0.5,
	CityTileDecoder.PROP_SUBWAY_ENTRANCE: 8.0, CityTileDecoder.PROP_NEWSSTAND: 2.0,
	CityTileDecoder.PROP_SHOP_SIGN: 1.0, CityTileDecoder.PROP_AWNING: 0.5, CityTileDecoder.PROP_BIKE_DOCK: 0.5,
	CityTileDecoder.PROP_PLAZA_TABLE: 0.5, CityTileDecoder.PROP_PLANTER: 0.5, CityTileDecoder.PROP_KIOSK: 2.0,
}

## Where a loaded tile's aerial photo is: NONE if it has none (or photos are
## off), WANTED until it's requested, then LOADING, then SHOWN or FAILED.
## FAILED tiles stay plain until they unload and load again.
enum Photo { NONE, WANTED, LOADING, SHOWN, FAILED }
## Launch options that tune the photos' look, and the shader parameters they set.
const PHOTO_OPTIONS := {"aerial_shadow": "aerial_shadow_softening", "aerial_brightness": "aerial_brightness"}

@export var region := "nyc"
## Tiles of each level load once their parent tile is within this distance of
## the camera (the top level, which has no parent, within its own distance).
@export var load_distances: Array[float] = [700.0, 1500.0, 30000.0]
## Loaded tiles are kept until this far past their distance, so they don't flicker.
@export var unload_margin := 300.0
## Near tiles (with collision and walking lanes) also load within this
## distance of each extra focus.
@export var extra_focus_radius := 350.0
@export var max_requests := 6
## Time per frame spent turning downloaded tiles into meshes.
@export var build_budget_msec := 6.0
## Buildings in full-detail tiles; coarser tiles get a copy with merged_blocks
## set, since their merged blocks have no street fronts marked.
@export var building_material: Material
@export var ground_material: Material
@export var water_material: Material
## Road paint (shaders/markings.gdshader).
@export var markings_material: Material
## Trees (all kinds) and rooftop water towers (shaders/tree.gdshader and
## water_tower.gdshader).
@export var tree_material: Material
@export var water_tower_material: Material
## Street lights, their glows at night, and their pools of light in the
## street light map (shaders/street_light.gdshader, street_light_glow.gdshader
## and street_light_pool.gdshader).
@export var street_light_material: Material
@export var street_light_glow_material: Material
@export var street_light_pool_material: Material
## Street furniture, small and large (shaders/street_furniture.gdshader).
@export var street_furniture_material: Material
## Cars, parked (near tiles' props) and moving (traffic draws its own
## MultiMesh with it and PropMeshes.car()): shaders/car.gdshader, whose
## header has the instance layout.
@export var car_material: Material

var loaded_counts: Array[int] = [0, 0, 0]
## World positions that need the ground loaded around them besides the
## camera's: other players' heroes on the host, so thugs near them have
## streets to stand on.
var extra_foci: Array[Vector3] = []
## Time the last tile took to turn into meshes and collision, in milliseconds.
var last_build_msec := 0.0
## Trees, water towers, street lights, furniture and parked cars in loaded
## near tiles.
var prop_count := 0
## Loaded tiles that are showing their aerial photo.
var photo_count := 0
## Time the last aerial photo took to decode and upload, in milliseconds.
var last_photo_msec := 0.0
## Whether the tree canopy map has loaded and gone to the ground material.
var canopy_loaded := false
## How far the city's lights are on (0..1, set by TimeOfDay): street lights'
## glows and their light map only draw while they are.
var city_lights := 0.0: set = set_city_lights

var _levels: Array[Dictionary] = []  # {name, size, tiles: Array[Tile], by_coord: {Vector2i: Tile}}
var _queue: Array[Array] = []  # [priority, tile, is_photo], sorted
var _ready_to_build: Array[Array] = []  # [tile, bytes]
var _ready_photos: Array[Array] = []  # [tile, node instance id, bytes]
var _photos_enabled := false
var _merged_building_material: ShaderMaterial
## The second batch of landmarks' own materials (the landmarks surface).
var landmark_material := _new_landmark_material()
## Churches' own material (the churches surface), and rowhouse fronts' small parts'.
## How far rowhouse fronts draw (m, see FRONTS_RANGE); set before tiles load.
var fronts_range := FRONTS_RANGE
var church_material := _new_material(preload("res://shaders/church.gdshader"))
var fronts_material := _new_material(preload("res://shaders/fronts.gdshader"))
## The waterfront landmarks' materials (the waterfront surface).
var waterfront_material := _new_material(preload("res://shaders/waterfront.gdshader"))
var _props: CityProps
var _light_map: StreetLightMap
var _in_flight := 0
var _base_url := ""  # when streaming (web, and desktop builds without tiles of their own)
var _build_id := ""  # the manifest's, for tile URLs
var _cache_dir := ""  # desktop builds streaming, once the manifest is in: user://tiles/<build>/<region>/
var _manifest_failures := 0
var _idle_requests: Array[HTTPRequest] = []
var _threaded := false  # decode tiles on worker threads
var _decode_tasks: Array[int] = []  # WorkerThreadPool tasks decoding a tile
var _decoded: Array[Array] = []  # [tile, surfaces], from the decode tasks
var _cleanup_tasks: Array[int] = []  # WorkerThreadPool tasks deleting old builds' caches
var _decoded_mutex := Mutex.new()
var _update_cooldown := 0.0
var _start_msec := 0
var _initial_load_done := false
var _load_build_msec := 0.0  # main thread time spent building tiles during the first load
var _load_longest_frame := 0.0  # the first load's longest frame (s)


class Tile:
	var level: int
	var i: int
	var j: int
	var size: float
	var info: Dictionary
	var node: Node3D
	var pending := false
	## Desktop builds: its last request was for the copy in the cache.
	var cached := false
	var failures := 0
	## After a failure, when it may be asked for again (Time.get_ticks_msec).
	var retry_msec := 0
	var parent: Tile
	var children: Array[Tile] = []
	## Sidewalk walking lanes (world-space polylines) and each one's bounds on
	## the ground (x, z), lod0 only, while loaded.
	var lanes: Array[PackedVector3Array] = []
	var lane_bounds: Array[Rect2] = []
	## Driving lanes (world-space polylines) and their info, lod0 only, while
	## loaded.
	var traffic_lanes: Array[PackedVector3Array] = []
	var traffic_info := PackedFloat32Array()
	## El tracks (the decoded trains surface, world-space), lod0 only, while
	## loaded.
	var train_tracks := {}
	## Trees, water towers, street lights, furniture and parked cars, lod0
	## only, while loaded.
	var prop_count := 0
	## How busy its sidewalks are, per BUSY_CELL square (rows of z), lod0 only,
	## while loaded.
	var busy := PackedFloat32Array()
	## The aerial photo's state for the current node.
	var photo := Photo.NONE

	func distance_to(x: float, z: float) -> float:
		var dx := maxf(maxf(i * size - x, 0.0), x - (i + 1) * size)
		var dz := maxf(maxf(j * size - z, 0.0), z - (j + 1) * size)
		return sqrt(dx * dx + dz * dz)


func _ready() -> void:
	add_to_group("floating")
	_start_msec = Time.get_ticks_msec()
	_photos_enabled = LaunchOptions.get_string("aerial") == "1"
	for option: String in PHOTO_OPTIONS:
		if LaunchOptions.has(option):
			for material: ShaderMaterial in [ground_material, building_material]:
				material.set_shader_parameter(PHOTO_OPTIONS[option], LaunchOptions.get_string(option).to_float())
	if building_material is ShaderMaterial:
		_merged_building_material = building_material.duplicate()
		_merged_building_material.set_shader_parameter("merged_blocks", true)
	_props = CityProps.new(tree_material, water_tower_material, street_light_material, street_light_glow_material,
		street_furniture_material, car_material)
	_props.tree_shadows = LaunchOptions.get_string("tree_shadows", "1") != "0"
	_light_map = StreetLightMap.new(street_light_pool_material)
	add_child(_light_map)
	_props.light_map = _light_map
	set_city_lights(city_lights)
	var web := OS.has_feature("web")
	if web:
		var page_dir := str(JavaScriptBridge.eval("location.href.split(/[?#]/)[0].replace(/[^/]*$/, '')"))
		_base_url = page_dir + "tiles/%s/" % region
	elif _streams():
		_base_url = LaunchOptions.get_string("tiles_url", TILES_URL).trim_suffix("/") + "/%s/" % region
	if not _base_url.is_empty():
		for n in max_requests:
			var request := HTTPRequest.new()
			# The browser's fetch already undoes any compression the host
			# applied (Cloudflare does); Godot would unzip it a second time.
			# Desktop builds unzip it themselves, and download on threads.
			request.accept_gzip = not web
			request.use_threads = not web
			add_child(request)
			_idle_requests.append(request)
	_threaded = not web and OS.get_processor_count() > 1 and LaunchOptions.get_string("decode_threads", "1") != "0"
	_load_file("manifest.json", _on_manifest_loaded)


func _exit_tree() -> void:
	for task in _decode_tasks + _cleanup_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_decode_tasks.clear()
	_cleanup_tasks.clear()


func _process(delta: float) -> void:
	# Signal poles and traffic follow the same clock (TrafficSignals).
	RenderingServer.global_shader_parameter_set("signal_clock", TrafficSignals.clock())
	if not _cleanup_tasks.is_empty():
		_finish_tasks(_cleanup_tasks)
	if not _initial_load_done:
		_load_longest_frame = maxf(_load_longest_frame, delta)
	if _levels.is_empty():
		return
	_update_cooldown -= delta
	if _update_cooldown <= 0.0:
		_update_cooldown = UPDATE_INTERVAL
		_update_wanted_tiles()
		_refresh_visibility()
		var camera := get_viewport().get_camera_3d()
		if camera:
			_light_map.follow(WorldOrigin.to_world(camera.global_position))
	while _in_flight < max_requests and not _queue.is_empty():
		var entry: Array = _queue.pop_front()
		var tile: Tile = entry[1]
		if not entry[2]:
			_request_tile(tile)
		elif tile.photo == Photo.WANTED:
			_request_photo(tile)
	_build_ready_tiles()


func set_city_lights(amount: float) -> void:
	city_lights = amount
	var on := amount > 0.0
	if _props == null or on == _props.lights_on:
		return
	# Only when they switch on or off: each near tile's glows show or hide.
	_props.lights_on = on
	_light_map.on = on
	get_tree().call_group(CityProps.GLOW_GROUP, "set_visible", on)


## Where street furniture shrinks away from the camera (m): small pieces
## and large ones (CityProps.small_furniture_fade). Takes effect for tiles
## built from then on, so set it before the city loads (Quality does).
func set_furniture_fade(small: Vector2, large: Vector2) -> void:
	_props.set_furniture_fade(small, large)


## How far woods' clumps of crowns draw, by tile level (CityProps.canopy_ranges;
## 0: not at all). Takes effect for tiles built from then on, so set it before
## the city loads (Quality does).
func set_canopy_ranges(ranges: Array[float]) -> void:
	_props.set_canopy_ranges(ranges)


## Where cars, parked and moving, shrink away from the camera (m;
## CityProps.car_fade). Parked cars' tiles built from then on draw them to
## match, so set it before the city loads (Quality does).
func set_car_fade(fade: Vector2) -> void:
	_props.set_car_fade(fade)


## Whether trees cast shadows (?tree_shadows=0 leaves them out; Quality):
## for tiles built from then on (refresh_detail() hides built tiles' shadows).
func set_tree_shadows(on: bool) -> void:
	_props.tree_shadows = on


## Brings the tiles already built up to date after Quality changed its
## preset while playing: how far their furniture, cars, rowhouse fronts and
## woods' crowns draw, and whether trees' shadows show. What a tile was built
## without (trees' shadows, far woods' crowns) comes when it's built again.
func refresh_detail() -> void:
	for level in _levels.size():
		for tile: Tile in _levels[level]["tiles"]:
			if tile.node == null:
				continue
			_props.refresh(tile.node, level)
			var fronts := tile.node.get_node_or_null(^"Fronts") as GeometryInstance3D
			if fronts:
				fronts.visibility_range_end = fronts_range


## The street light map's pools: one MultiMeshInstance2D per near tile with lamps.
func light_pool_count() -> int:
	return _light_map.get_child_count() if _light_map else 0


func pending_count() -> int:
	return _in_flight + _queue.size() + _ready_to_build.size() + _ready_photos.size() + _decode_tasks.size() \
		+ _decoded.size()


## True once the ground at this world position can be stood on: its lod0 tile
## has loaded with collision, or there's no tile there at all (open water).
func has_collision_at(world_position: Vector3) -> bool:
	if _levels.is_empty():
		return false
	var tile := _tile_at(LEVEL_NEAR, world_position)
	return tile == null or tile.node != null


## Sidewalk lanes (world-space polylines) of loaded tiles that come within
## about `radius` of a world position (their bounds do).
func lanes_near(world_position: Vector3, radius: float) -> Array[PackedVector3Array]:
	var found: Array[PackedVector3Array] = []
	if _levels.is_empty():
		return found
	var size: float = _levels[LEVEL_NEAR]["size"]
	var by_coord: Dictionary = _levels[LEVEL_NEAR]["by_coord"]
	var around := Rect2(world_position.x - radius, world_position.z - radius, radius * 2.0, radius * 2.0)
	for j in range(floori(around.position.y / size), floori(around.end.y / size) + 1):
		for i in range(floori(around.position.x / size), floori(around.end.x / size) + 1):
			var tile: Tile = by_coord.get(Vector2i(i, j))
			if tile == null or tile.lanes.is_empty():
				continue
			for n in tile.lanes.size():
				if tile.lane_bounds[n].intersects(around, true):
					found.append(tile.lanes[n])
	return found


## How busy the sidewalks around a world position are: what the shops, subway
## stairs and the like in its BUSY_CELL square and `reach` squares around it
## count for (BUSY_WEIGHTS), from the loaded near tiles. About 1 a shop; a
## shopping street scores 20-60 with the 3x3 squares of reach 1.
func busyness_at(world_position: Vector3, reach := 1) -> float:
	if _levels.is_empty():
		return 0.0
	var by_coord: Dictionary = _levels[LEVEL_NEAR]["by_coord"]
	var cells := roundi(_levels[LEVEL_NEAR]["size"] / BUSY_CELL)
	var x := floori(world_position.x / BUSY_CELL)
	var z := floori(world_position.z / BUSY_CELL)
	var total := 0.0
	var i := floori(float(x) / cells)
	var j := floori(float(z) / cells)
	var lx := x - i * cells
	var lz := z - j * cells
	if lx >= reach and lz >= reach and lx < cells - reach and lz < cells - reach:
		# All in one tile (most of the time): no lookups per square.
		var tile: Tile = by_coord.get(Vector2i(i, j))
		if tile == null or tile.busy.is_empty():
			return 0.0
		for cz in range(lz - reach, lz + reach + 1):
			for cx in range(lx - reach, lx + reach + 1):
				total += tile.busy[cz * cells + cx]
		return total
	for cz in range(z - reach, z + reach + 1):
		for cx in range(x - reach, x + reach + 1):
			var tile: Tile = by_coord.get(Vector2i(floori(float(cx) / cells), floori(float(cz) / cells)))
			if tile and not tile.busy.is_empty():
				total += tile.busy[posmod(cz, cells) * cells + posmod(cx, cells)]
	return total


## Driving lanes of every loaded near tile: {Vector2i(i, j): [lanes, info]}
## (see traffic_lanes_changed).
func traffic_lanes() -> Dictionary:
	var found := {}
	if _levels.is_empty():
		return found
	for tile: Tile in _levels[LEVEL_NEAR]["tiles"]:
		if not tile.traffic_lanes.is_empty():
			found[Vector2i(tile.i, tile.j)] = [tile.traffic_lanes, tile.traffic_info]
	return found


## El tracks of every loaded near tile: {Vector2i(i, j): tracks} (see
## train_tracks_changed).
func train_tracks() -> Dictionary:
	var found := {}
	if _levels.is_empty():
		return found
	for tile: Tile in _levels[LEVEL_NEAR]["tiles"]:
		if not tile.train_tracks.is_empty():
			found[Vector2i(tile.i, tile.j)] = tile.train_tracks
	return found


## Height of the first surface (ground, roof or bridge) straight down from
## `search_from` meters above a world position (from the sky by default), or
## NAN if nothing there has loaded with collision yet.
func ground_height_at(world_position: Vector3, search_from := INF) -> float:
	var start_y := minf(world_position.y + search_from, WorldOrigin.CEILING + 50.0)
	var top := WorldOrigin.to_local(Vector3(world_position.x, start_y, world_position.z))
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (start_y + 100.0), COLLISION_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else NAN


func _tile_at(level: int, world_position: Vector3) -> Tile:
	var size: float = _levels[level]["size"]
	var coord := Vector2i(floori(world_position.x / size), floori(world_position.z / size))
	return _levels[level]["by_coord"].get(coord)


func _on_manifest_loaded(bytes: PackedByteArray) -> void:
	var manifest = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
	var valid: bool = typeof(manifest) == TYPE_DICTIONARY and manifest.has("levels")
	if _caches():
		if valid:
			_start_cache(manifest, bytes)
		else:
			# Offline (or the server is): play from the tiles kept last time,
			# else ask once more, past any cache.
			manifest = _cached_manifest()
			valid = manifest != null
			if valid:
				push_warning("Couldn't reach %s; playing from the tiles kept from build %s." % [_base_url, manifest.get("build", "")])
			elif _manifest_failures < 1:
				_manifest_failures += 1
				get_tree().create_timer(RETRY_MSEC / 1000.0).timeout.connect(
					_load_file.bind("manifest.json", _on_manifest_loaded, "?retry=%d" % _manifest_failures))
				return
	if not valid:
		push_error("City manifest for '%s' is missing or out of date. Run tools/citygen/build_tiles.py." % region)
		return
	_build_id = str(manifest.get("build", ""))
	for level in manifest.levels.size():
		var data: Dictionary = manifest.levels[level]
		var size := float(data.tile_size)
		var tiles: Array[Tile] = []
		var by_coord := {}
		for tile_info: Dictionary in data.tiles:
			var tile := Tile.new()
			tile.level = level
			tile.i = int(tile_info.i)
			tile.j = int(tile_info.j)
			tile.size = size
			tile.info = tile_info
			tiles.append(tile)
			by_coord[Vector2i(tile.i, tile.j)] = tile
		_levels.append({"name": data.name, "size": size, "tiles": tiles, "by_coord": by_coord,
			"aerial_margin": float(data.get("aerial_margin", 0.0))})
	if manifest.has("canopy"):
		_in_flight += 1
		var cached := _is_cached(manifest.canopy.file)
		_load_file(manifest.canopy.file, _on_canopy_loaded.bind(manifest.canopy, cached), "", cached)
	# Link each tile to the tile one level up that contains it.
	for level in range(_levels.size() - 1):
		var ratio := int(round(_levels[level + 1]["size"] / _levels[level]["size"]))
		for tile: Tile in _levels[level]["tiles"]:
			var parent: Tile = _levels[level + 1]["by_coord"].get(Vector2i(floori(float(tile.i) / ratio), floori(float(tile.j) / ratio)))
			if parent:
				tile.parent = parent
				parent.children.append(tile)


func _update_wanted_tiles() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var focus := WorldOrigin.to_world(camera.global_position)
	var now := Time.get_ticks_msec()
	# Height counts too, so flying high doesn't load street-level detail.
	var height := maxf(focus.y, 0.0)
	_queue.clear()
	for level in _levels.size():
		var limit: float = load_distances[mini(level, load_distances.size() - 1)]
		for tile: Tile in _levels[level]["tiles"]:
			# A tile is wanted when its parent is near (or itself, at the top level).
			var anchor: Tile = tile.parent if tile.parent else tile
			var distance := Vector2(anchor.distance_to(focus.x, focus.z), height).length()
			var extra := _extra_focus_distance(tile) if level == LEVEL_NEAR else INF
			if tile.node == null:
				if ((distance < limit or extra < extra_focus_radius) and not tile.pending
						and tile.failures < MAX_ATTEMPTS and now >= tile.retry_msec):
					_queue.append([minf(tile.distance_to(focus.x, focus.z), extra) + LEVEL_PRIORITY[level], tile, false])
			elif distance > limit + unload_margin and extra > extra_focus_radius + unload_margin:
				_unload(tile)
			elif tile.photo == Photo.WANTED:
				_queue.append([tile.distance_to(focus.x, focus.z) + LEVEL_PRIORITY[level] + PHOTO_PRIORITY, tile, true])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _extra_focus_distance(tile: Tile) -> float:
	var nearest := INF
	for focus in extra_foci:
		nearest = minf(nearest, tile.distance_to(focus.x, focus.z))
	return nearest


func _refresh_visibility() -> void:
	for tile: Tile in _levels[_levels.size() - 1]["tiles"]:
		_show(tile)
	# Tiles whose parent level has no tile there have nobody to show them.
	for level in range(_levels.size() - 1):
		for tile: Tile in _levels[level]["tiles"]:
			if tile.parent == null:
				_show(tile)


## Draws a tile, or its children instead once they're all ready.
func _show(tile: Tile) -> void:
	var use_children := _children_ready(tile)
	if tile.node:
		tile.node.visible = not use_children
	for child in tile.children:
		if use_children:
			_show(child)
		else:
			_hide(child)


func _hide(tile: Tile) -> void:
	if tile.node:
		tile.node.visible = false
	for child in tile.children:
		_hide(child)


func _children_ready(tile: Tile) -> bool:
	if tile.children.is_empty():
		return false
	for child in tile.children:
		if child.node == null and not _children_ready(child):
			return false
	return true


func _request_tile(tile: Tile) -> void:
	tile.pending = true
	_in_flight += 1
	# The build's id keeps browsers from mixing in tiles cached from an older
	# build; a retry skips past whatever is cached.
	var query := "?b=%s" % _build_id
	if tile.failures > 0:
		query += "&retry=%d" % tile.failures
	# Desktop builds keep what they download: a tile kept from before is read
	# (by the decode, on a worker thread) instead, unless it was the one that
	# just failed.
	var file := _tile_file(tile)
	tile.cached = tile.failures == 0 and _is_cached(file)
	if tile.cached:
		_on_tile_loaded.call_deferred(PackedByteArray(), tile)
		return
	_load_file(file, _on_tile_loaded.bind(tile), query)


func _tile_file(tile: Tile) -> String:
	return "%s/%d_%d.nyct" % [_levels[tile.level]["name"], tile.i, tile.j]


func _on_tile_loaded(bytes: PackedByteArray, tile: Tile) -> void:
	_in_flight -= 1
	_ready_to_build.append([tile, bytes])


func _request_photo(tile: Tile) -> void:
	tile.photo = Photo.LOADING
	_in_flight += 1
	_load_file("aerial/%s/%d_%d.jpg" % [_levels[tile.level]["name"], tile.i, tile.j],
		_on_photo_loaded.bind(tile, tile.node.get_instance_id()))


func _on_photo_loaded(bytes: PackedByteArray, tile: Tile, node_id: int) -> void:
	_in_flight -= 1
	_ready_photos.append([tile, node_id, bytes])


func _build_ready_tiles() -> void:
	var deadline := Time.get_ticks_usec() + int(build_budget_msec * 1000.0)
	var changed := false
	if _threaded:
		_start_decodes()
	while Time.get_ticks_usec() < deadline:
		var tile: Tile
		var surfaces: Variant  # Array[Dictionary], or null if the tile is broken
		var build_start := Time.get_ticks_usec()
		if _threaded:
			_decoded_mutex.lock()
			var item: Array = _decoded.pop_front() if not _decoded.is_empty() else []
			_decoded_mutex.unlock()
			if item.is_empty():
				break
			tile = item[0]
			surfaces = item[1]
		else:
			if _ready_to_build.is_empty():
				break
			var item: Array = _ready_to_build.pop_front()
			tile = item[0]
			surfaces = _decode(_tile_file(tile), item[1], int(tile.info.raw_bytes), tile.cached, tile.level == LEVEL_NEAR)
		tile.pending = false
		if surfaces == null and tile.cached:
			# Our copy was broken (and is gone now): download it right away
			# (a failure counted skips the cache).
			tile.failures += 1
			_request_tile(tile)
			continue
		if surfaces == null:
			# A failed download, or a stale copy (say, cached at the edge just
			# after the site was updated): an update asks again a little later,
			# a few times.
			tile.failures += 1
			tile.retry_msec = Time.get_ticks_msec() + RETRY_MSEC * tile.failures
			if tile.failures >= MAX_ATTEMPTS:
				push_error("Giving up on tile %s %d_%d" % [_levels[tile.level]["name"], tile.i, tile.j])
			continue
		var node := _build_tile_node(tile, surfaces)
		last_build_msec = (Time.get_ticks_usec() - build_start) / 1000.0
		_load_build_msec += last_build_msec
		node.visible = false  # _refresh_visibility decides
		add_child(node)
		tile.node = node
		loaded_counts[tile.level] += 1
		if not tile.traffic_lanes.is_empty():
			traffic_lanes_changed.emit(Vector2i(tile.i, tile.j), tile.traffic_lanes, tile.traffic_info)
		if not tile.train_tracks.is_empty():
			train_tracks_changed.emit(Vector2i(tile.i, tile.j), tile.train_tracks)
		changed = true
		if _photos_enabled and tile.info.get("aerial"):
			tile.photo = Photo.WANTED
			# Queued now so the city never looks done before the photo is
			# asked for; the next update sorts it in.
			_queue.append([INF, tile, true])
	if changed:
		_refresh_visibility()
	# A photo takes longer to decode than a tile to build (about 7 ms for a
	# lod0 one on the web), so at most one a frame, if tiles left time.
	while not _ready_photos.is_empty() and Time.get_ticks_usec() < deadline:
		if _apply_photo(_ready_photos.pop_front()):
			break

	if not _initial_load_done and pending_count() == 0 and loaded_counts.any(func(n: int) -> bool: return n > 0):
		_initial_load_done = true
		var seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
		print("[city] %s ready in %.1f s: %d near, %d mid, %d far tiles (%.0f ms building them on the main thread%s; longest frame %.0f ms)" % [
			region, seconds, loaded_counts[0], loaded_counts[1], loaded_counts[2], _load_build_msec,
			", decoded on worker threads" if _threaded else "", _load_longest_frame * 1000.0])
		initial_load_finished.emit(seconds)


## A tile's surfaces (CityTileDecoder.decode_unpacked() without meshes,
## which the main thread makes), with `faces` for those a near tile collides
## with, from its download, or from its copy in the cache (`cached`), which
## is replaced by the next download if it's broken; a good download goes into
## the cache. Null if the tile is broken. Runs on a worker thread on desktop.
func _decode(file: String, bytes: PackedByteArray, raw_bytes: int, cached: bool, near: bool) -> Variant:
	if cached:
		bytes = FileAccess.get_file_as_bytes(_cache_dir + file)
	var data := CityTileDecoder.unpack(bytes, raw_bytes)
	if data.is_empty():
		if cached:
			DirAccess.remove_absolute(_cache_dir + file)
		return null
	if not cached:
		_store(file, bytes)
	var surfaces := CityTileDecoder.decode_unpacked(data, false)
	if near:
		for surface in surfaces:
			if surface.has("arrays") and surface.kind not in NO_COLLISION:
				surface.faces = CityTileDecoder.faces(surface.arrays)
	return surfaces


## Hands downloaded tiles to worker threads to decode, a few at a time.
func _start_decodes() -> void:
	_finish_tasks(_decode_tasks)
	while _decode_tasks.size() < MAX_DECODES and not _ready_to_build.is_empty():
		var item: Array = _ready_to_build.pop_front()
		var tile: Tile = item[0]
		_decode_tasks.append(WorkerThreadPool.add_task(_decode_task.bind(
			tile, _tile_file(tile), item[1], int(tile.info.raw_bytes), tile.cached, tile.level == LEVEL_NEAR), false, "city tile"))


func _decode_task(tile: Tile, file: String, bytes: PackedByteArray, raw_bytes: int, cached: bool, near: bool) -> void:
	var surfaces: Variant = _decode(file, bytes, raw_bytes, cached, near)
	_decoded_mutex.lock()
	_decoded.append([tile, surfaces])
	_decoded_mutex.unlock()


## Lets go of worker thread tasks that have finished.
static func _finish_tasks(tasks: Array[int]) -> void:
	for n in range(tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(tasks[n]):
			WorkerThreadPool.wait_for_task_completion(tasks[n])
			tasks.remove_at(n)


func _build_tile_node(tile: Tile, surfaces: Array[Dictionary]) -> Node3D:
	var near := tile.level == LEVEL_NEAR
	var node := Node3D.new()
	node.name = "%s_%d_%d" % [_levels[tile.level]["name"], tile.i, tile.j]
	node.position = Vector3(tile.i * tile.size, 0.0, tile.j * tile.size)
	var body: StaticBody3D = null
	if near:
		body = StaticBody3D.new()
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = 0
		node.add_child(body)
	for surface in surfaces:
		if surface.kind == CityTileDecoder.SURFACE_LANES:
			tile.lanes.clear()
			tile.lane_bounds.clear()
			for lane: PackedVector3Array in surface.lanes:
				var bounds := Rect2(lane[0].x + node.position.x, lane[0].z + node.position.z, 0.0, 0.0)
				for p in lane.size():
					var point := lane[p] + node.position
					lane[p] = point
					bounds = bounds.expand(Vector2(point.x, point.z))
				tile.lanes.append(lane)
				tile.lane_bounds.append(bounds)
			continue
		if surface.kind == CityTileDecoder.SURFACE_TRAFFIC:
			tile.traffic_lanes.clear()
			for lane: PackedVector3Array in surface.lanes:
				for p in lane.size():
					lane[p] += node.position
				tile.traffic_lanes.append(lane)
			tile.traffic_info = surface.info
			continue
		if surface.kind == CityTileDecoder.SURFACE_TRAINS:
			for track: PackedVector3Array in surface.tracks:
				for p in track.size():
					track[p] += node.position
			tile.train_tracks = surface
			continue
		if surface.kind == CityTileDecoder.SURFACE_WATER:
			node.add_child(_water_node(surface, near))
			continue
		if surface.kind == CityTileDecoder.SURFACE_PROPS:
			tile.prop_count = _props.add_to(node, surface, tile.level)
			prop_count += tile.prop_count
			if near:
				tile.busy = _busy_squares(surface, tile.size)
			continue
		if surface.kind == CityTileDecoder.SURFACE_MARKINGS:
			# Paint on the road, without collision or shadows.
			var markings := MeshInstance3D.new()
			markings.name = "Markings"
			markings.mesh = CityTileDecoder.mesh(surface)
			markings.material_override = markings_material
			markings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			markings.visibility_range_end = MARKINGS_RANGE
			node.add_child(markings)
			continue
		if surface.kind == CityTileDecoder.SURFACE_FRONTS:
			# Railings, fences, shrubs and awnings: no collision, and only up close;
			# no shadows (thin, and the sun's splits would draw them up to four
			# more times).
			var fronts := MeshInstance3D.new()
			fronts.name = "Fronts"
			fronts.mesh = CityTileDecoder.mesh(surface)
			fronts.material_override = fronts_material
			fronts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fronts.visibility_range_end = fronts_range
			node.add_child(fronts)
			continue
		var is_buildings: bool = surface.kind == CityTileDecoder.SURFACE_BUILDINGS
		var instance := MeshInstance3D.new()
		instance.mesh = CityTileDecoder.mesh(surface)
		instance.material_override = _building_material(tile.level) if is_buildings else ground_material
		if surface.kind == CityTileDecoder.SURFACE_LANDMARKS:
			instance.material_override = landmark_material
		elif surface.kind == CityTileDecoder.SURFACE_CHURCHES:
			instance.material_override = church_material
		elif surface.kind == CityTileDecoder.SURFACE_WATERFRONT:
			instance.material_override = waterfront_material
		var casts_shadow: bool = near and surface.kind != CityTileDecoder.SURFACE_GROUND
		if not casts_shadow:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
		if body:
			var shape := CollisionShape3D.new()
			shape.shape = _collision_shape(surface, instance.mesh)
			body.add_child(shape)
	return node


## A near tile's surface's collision, from its faces (see _decode()).
static func _collision_shape(surface: Dictionary, mesh: Mesh) -> Shape3D:
	if not surface.has("faces"):
		return mesh.create_trimesh_shape()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(surface.faces)
	return shape


## Gives the ground material the tree canopy map: a grayscale PNG, how much
## of each `pixel`-meter square is under trees, north up, its top-left corner
## at world (min_x, min_z). Ground UVs are world x/z, so the shader samples it
## straight from them. Decoding it takes a while (once, while the city loads).
func _on_canopy_loaded(bytes: PackedByteArray, info: Dictionary, cached: bool) -> void:
	_in_flight -= 1
	var start := Time.get_ticks_usec()
	var image := Image.new()
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
		push_warning("Couldn't load the tree canopy map; parks will be plain.")
		if cached:
			DirAccess.remove_absolute(_cache_dir + info.file)  # the next start downloads it again
		return
	if not cached:
		_store(info.file, bytes)
	# Coverage, not color: one linear channel, mipmapped for the far ground.
	image.convert(Image.FORMAT_R8)
	image.generate_mipmaps()
	var size := Vector2(image.get_width(), image.get_height()) * float(info.pixel)
	ground_material.set_shader_parameter("canopy", ImageTexture.create_from_image(image))
	ground_material.set_shader_parameter("canopy_rect", Vector4(float(info.min_x), float(info.min_z), size.x, size.y))
	canopy_loaded = true
	print("[city] canopy map %dx%d decoded in %.0f ms" % [image.get_width(), image.get_height(), (Time.get_ticks_usec() - start) / 1000.0])


## Drapes a downloaded aerial photo ([tile, node instance id, bytes]) over its
## tile's ground, bridges and roofs. Returns whether it decoded one; photos
## for tiles that have unloaded (or reloaded) since are dropped unopened.
func _apply_photo(item: Array) -> bool:
	var tile: Tile = item[0]
	if tile.node == null or tile.node.get_instance_id() != item[1]:
		return false
	var bytes: PackedByteArray = item[2]
	if bytes.is_empty():
		tile.photo = Photo.FAILED
		return false
	var start := Time.get_ticks_usec()
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK:
		push_warning("Couldn't decode the aerial photo for tile %s" % tile.node.name)
		tile.photo = Photo.FAILED
		return true
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	# The tile gets its own copies of the shared materials, holding its photo;
	# they (and the photo) are freed with the tile's node.
	var shared_buildings := _building_material(tile.level)
	var ground := ground_material.duplicate() as ShaderMaterial
	var buildings := shared_buildings.duplicate() as ShaderMaterial
	var margin: float = _levels[tile.level]["aerial_margin"]
	for material: ShaderMaterial in [ground, buildings]:
		material.set_shader_parameter("aerial", texture)
		material.set_shader_parameter("aerial_size", tile.size + 2.0 * margin)
		material.set_shader_parameter("aerial_margin", margin)
		material.set_shader_parameter("aerial_strength", 1.0)
	for child in tile.node.get_children():
		var instance := child as MeshInstance3D
		if instance == null:
			continue
		# Water keeps the shared water material.
		if instance.material_override == ground_material:
			instance.material_override = ground
		elif instance.material_override == shared_buildings:
			instance.material_override = buildings
	tile.photo = Photo.SHOWN
	photo_count += 1
	last_photo_msec = (Time.get_ticks_usec() - start) / 1000.0
	return true


static func _new_landmark_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/landmark.gdshader")
	return material


static func _new_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _building_material(level: int) -> Material:
	if level == LEVEL_NEAR or _merged_building_material == null:
		return building_material
	return _merged_building_material


## A near tile's busy squares (see busyness_at()) from its props, which are
## sorted by type.
func _busy_squares(props: Dictionary, size: float) -> PackedFloat32Array:
	var cells := roundi(size / BUSY_CELL)
	var squares := PackedFloat32Array()
	squares.resize(cells * cells)
	var positions: PackedVector3Array = props.positions
	var count := positions.size()
	if count == 0:
		return squares
	var uv2: PackedVector2Array = props.uv2
	var columns := Image.create_from_data(2, count, false, Image.FORMAT_RF, uv2.to_byte_array())
	var types := columns.get_region(Rect2i(0, 0, 1, count)).get_data().to_float32_array()
	for kind: int in BUSY_WEIGHTS:
		var weight: float = BUSY_WEIGHTS[kind]
		for k in range(types.bsearch(kind - 0.5), types.bsearch(kind + 0.5)):
			var p := positions[k]
			squares[clampi(floori(p.z / BUSY_CELL), 0, cells - 1) * cells + clampi(floori(p.x / BUSY_CELL), 0, cells - 1)] += weight
	return squares


## A raised lake's surface, which heroes can find (but not stand on) up close.
func _water_node(surface: Dictionary, near: bool) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.mesh = CityTileDecoder.mesh(surface)
	instance.material_override = water_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if near:
		var body := StaticBody3D.new()
		body.collision_layer = WATER_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = _collision_shape(surface, instance.mesh)
		body.add_child(shape)
		instance.add_child(body)
	return instance


func _unload(tile: Tile) -> void:
	tile.node.queue_free()
	tile.node = null
	tile.lanes.clear()
	tile.lane_bounds.clear()
	if not tile.traffic_lanes.is_empty():
		tile.traffic_lanes.clear()
		tile.traffic_info = PackedFloat32Array()
		traffic_lanes_changed.emit(Vector2i(tile.i, tile.j), tile.traffic_lanes, tile.traffic_info)
	if not tile.train_tracks.is_empty():
		tile.train_tracks = {}
		train_tracks_changed.emit(Vector2i(tile.i, tile.j), tile.train_tracks)
	prop_count -= tile.prop_count
	tile.prop_count = 0
	tile.busy = PackedFloat32Array()
	loaded_counts[tile.level] -= 1
	if tile.photo == Photo.SHOWN:
		photo_count -= 1
	tile.photo = Photo.NONE


## Loads a file from the tile directory (or the server, or with `cached`, the
## cache) and calls on_loaded(bytes) when done; bytes is empty on failure. The
## query only goes on requests to the server.
func _load_file(file: String, on_loaded: Callable, query := "", cached := false) -> void:
	if cached or _base_url.is_empty():
		on_loaded.call_deferred(FileAccess.get_file_as_bytes((_cache_dir if cached else _local_dir()) + file))
		return
	var request: HTTPRequest = _idle_requests.pop_back()
	var callback := _on_request_completed.bind(request, file, on_loaded)
	request.request_completed.connect(callback, CONNECT_ONE_SHOT)
	if not OS.has_feature("web"):
		request.timeout = MANIFEST_TIMEOUT if file == "manifest.json" else REQUEST_TIMEOUT
	if request.request(_base_url + file + query) != OK:
		request.request_completed.disconnect(callback)
		_idle_requests.append(request)
		push_warning("Couldn't request %s" % file)
		on_loaded.call_deferred(PackedByteArray())


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest, file: String, on_loaded: Callable) -> void:
	_idle_requests.append(request)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Failed to load %s (result %d, HTTP %d)" % [file, result, code])
		body = PackedByteArray()
	on_loaded.call(body)


func _local_dir() -> String:
	if LaunchOptions.has("tiles"):
		return LaunchOptions.get_string("tiles").path_join(region) + "/"
	if OS.has_feature("editor"):
		return "res://data/tiles/%s/" % region
	return OS.get_executable_path().get_base_dir().path_join("tiles/%s/" % region)


## Whether a desktop build streams its tiles from a server (--tiles_url, or
## none of the tile folders _local_dir() looks in).
func _streams() -> bool:
	if LaunchOptions.has("tiles_url"):
		return true
	if LaunchOptions.has("tiles") or OS.has_feature("editor"):
		return false
	return not FileAccess.file_exists(_local_dir() + "manifest.json")


## Whether this game keeps the tiles it downloads (desktop builds streaming).
func _caches() -> bool:
	return not _base_url.is_empty() and not OS.has_feature("web")


func _is_cached(file: String) -> bool:
	return not _cache_dir.is_empty() and FileAccess.file_exists(_cache_dir + file)


## Keeps a good download in the cache (desktop builds streaming; may run on a
## worker thread). A file cut short (a full disk, a crash) fails its check
## when it's read back and is downloaded again.
func _store(file: String, bytes: PackedByteArray) -> void:
	if _cache_dir.is_empty():
		return
	var out := FileAccess.open(_cache_dir + file, FileAccess.WRITE)
	if out:
		out.store_buffer(bytes)


## The manifest came from the server: tiles go into its build's cache, which
## gets a copy of the manifest for playing offline. Other builds' tiles are no
## use any more, so their caches are deleted (on a worker thread).
func _start_cache(manifest: Dictionary, bytes: PackedByteArray) -> void:
	var build := str(manifest.get("build", "")).validate_filename()
	if build.is_empty():
		build = "unversioned"
	_cache_dir = CACHE_ROOT.path_join(build).path_join(region) + "/"
	for level: Dictionary in manifest.levels:
		DirAccess.make_dir_recursive_absolute(_cache_dir + str(level.name))
	_store("manifest.json", bytes)
	for other in DirAccess.get_directories_at(CACHE_ROOT):
		if other != build:
			print("[city] deleting the tiles kept from build %s" % other)
			_cleanup_tasks.append(WorkerThreadPool.add_task(_remove_tree.bind(CACHE_ROOT.path_join(other)), false,
				"old city tiles"))


## Without the server: the manifest kept with the newest build's tiles (whose
## cache this game then plays from), or null if there's none.
func _cached_manifest() -> Variant:
	var newest := ""
	for build in DirAccess.get_directories_at(CACHE_ROOT):
		var path := CACHE_ROOT.path_join(build).path_join(region).path_join("manifest.json")
		if FileAccess.file_exists(path) and (newest.is_empty()
				or FileAccess.get_modified_time(path) > FileAccess.get_modified_time(newest)):
			newest = path
	if newest.is_empty():
		return null
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(newest))
	if typeof(manifest) != TYPE_DICTIONARY or not manifest.has("levels"):
		return null
	_cache_dir = newest.get_base_dir() + "/"
	return manifest


static func _remove_tree(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
