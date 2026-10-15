class_name Quality
extends Node
## Graphics quality presets. Phones get "low", tablets "medium" and computers
## "high", the full look (which changes nothing); ?quality=low|medium|high
## (--quality=... on desktop) picks one. Game calls set_launch_defaults()
## before the world's nodes start and adds this node, which applies the rest
## and keeps the 3-D resolution right as the window changes size. With ?stats,
## it also logs memory use every few seconds ("[mem] ...").
##
##                       low             medium          high
##   3-D resolution      540 lines       720 lines       full
##   antialiasing        off             MSAA 2x         MSAA 4x
##   sun shadows         off             2 splits, 300 m 4 splits, 1500 m
##   shadow map          1024            2048            4096
##   tree shadows        off             off             on
##   tiles lod0/1/2 (m)  350/800/7000    500/1100/12000  700/1500/30000
##   street furniture    90/300          220/500         260/580
##   gone by (m, small/
##   large pieces)
##   fog density         0.00016         0.0001          0.00005
##   pedestrians         12              24              45
##   gangs (thugs; most  1 (2-4; 6)      2 (3-4; 10)     2 (3-5; 16)
##   bodies left lying)
##
## "Lines" is the 3-D image's height in pixels (its width follows the screen;
## never more than the screen's own pixels): the HUD and touch buttons stay
## sharp. The tile distances are CityStreamer.load_distances; the fog hides
## where the city stops. Street furniture shrinks away piece by piece before
## those distances (CityStreamer.set_furniture_fade()), and each tile's stops
## drawing past them, so phones draw it in fewer tiles.
## ?fog=, ?peds= and ?tree_shadows= still override their preset values.

enum Level { LOW, MEDIUM, HIGH }

const NAMES: Array[String] = ["low", "medium", "high"]
const PRESETS := {
	Level.LOW: {
		"render_height": 540.0,
		"msaa": Viewport.MSAA_DISABLED,
		"shadows": false,
		"shadow_atlas": 1024,
		"load_distances": [350.0, 800.0, 7000.0],
		"furniture_fade": [Vector2(60.0, 90.0), Vector2(220.0, 300.0)],
		"fog_density": 0.00016,
		"pedestrians": 12,
		"gangs": 1,
		"gang_size": Vector2i(2, 4),
		"bodies": 6,
	},
	Level.MEDIUM: {
		"render_height": 720.0,
		"msaa": Viewport.MSAA_2X,
		"shadows": true,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"shadow_distance": 300.0,
		"shadow_atlas": 2048,
		"load_distances": [500.0, 1100.0, 12000.0],
		"furniture_fade": [Vector2(150.0, 220.0), Vector2(360.0, 500.0)],
		"fog_density": 0.0001,
		"pedestrians": 24,
		"gangs": 2,
		"gang_size": Vector2i(3, 4),
		"bodies": 10,
	},
}
## Never render 3-D at less than this share of the screen's pixels.
const MIN_RENDER_SCALE := 0.25
const MEMORY_LOG_INTERVAL := 5.0

static var _level := -1
static var _reason := ""

var _preset := {}
var _memory_log_cooldown := 0.0
var _log_memory := false


## The preset in use: from ?quality, else from the device.
static func level() -> Level:
	if _level < 0:
		var asked := LaunchOptions.get_string("quality")
		if asked in NAMES:
			_level = NAMES.find(asked)
			_reason = "?quality"
		elif Device.is_mobile():
			_level = Level.LOW if Device.is_phone() else Level.MEDIUM
			_reason = "phone" if Device.is_phone() else "tablet"
		else:
			_level = Level.HIGH
			_reason = "computer"
	return _level as Level


static func level_name() -> String:
	return NAMES[level()]


## Launch options that other nodes read when they start (call before they do):
## no tree shadows and fewer pedestrians below "high".
static func set_launch_defaults() -> void:
	if level() == Level.HIGH:
		return
	var preset: Dictionary = PRESETS[level()]
	LaunchOptions.set_default("tree_shadows", "0")
	LaunchOptions.set_default("peds", str(preset.pedestrians))


## Applies the preset to the world's nodes (after they've started).
func apply(sun: DirectionalLight3D, environment: Environment, city: CityStreamer,
		crowd: CrowdManager, encounters: EncounterDirector) -> void:
	_log_memory = LaunchOptions.has("stats")
	if level() != Level.HIGH:
		_preset = PRESETS[level()]
		var root := get_tree().root
		root.msaa_3d = _preset.msaa
		root.size_changed.connect(_update_render_scale)
		_update_render_scale()
		sun.shadow_enabled = _preset.shadows
		if _preset.shadows:
			sun.directional_shadow_mode = _preset.shadow_mode
			sun.directional_shadow_max_distance = _preset.shadow_distance
		RenderingServer.directional_shadow_atlas_set_size(_preset.shadow_atlas, true)
		var distances: Array[float] = []
		distances.assign(_preset.load_distances)
		city.load_distances = distances
		city.set_furniture_fade(_preset.furniture_fade[0], _preset.furniture_fade[1])
		if environment and not LaunchOptions.has("fog"):
			environment.fog_density = _preset.fog_density
		encounters.max_gangs = _preset.gangs
		encounters.gang_size = _preset.gang_size
		encounters.max_bodies = _preset.bodies
	var root := get_tree().root
	print("[quality] %s (%s): 3-D %s, MSAA %s, shadows %s, tiles %s, %d pedestrians, %d gang(s)" % [
		level_name(), _reason,
		"%dx%d" % [roundi(root.size.x * root.scaling_3d_scale), roundi(root.size.y * root.scaling_3d_scale)],
		["off", "2x", "4x", "8x"][root.msaa_3d], "on" if sun.shadow_enabled else "off",
		"/".join(city.load_distances.map(func(d: float) -> String: return str(int(d)))),
		crowd.max_pedestrians, encounters.max_gangs])


func _process(delta: float) -> void:
	if not _log_memory:
		set_process(false)
		return
	_memory_log_cooldown -= delta
	if _memory_log_cooldown > 0.0:
		return
	_memory_log_cooldown = MEMORY_LOG_INTERVAL
	var heap := 0.0
	if Device.is_web():
		heap = float(str(JavaScriptBridge.eval(
			"(typeof engine === 'object' && engine.rtenv && engine.rtenv.HEAP8) ? engine.rtenv.HEAP8.length : 0", true)))
	print("[mem] video %d MB (textures %d, buffers %d), wasm heap %d MB" % [
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6),
		int(heap / 1e6)])


## Renders 3-D at about the preset's number of lines, whatever the screen.
func _update_render_scale() -> void:
	var root := get_tree().root
	var lines := float(mini(root.size.x, root.size.y))
	if lines <= 0.0:
		return
	root.scaling_3d_scale = clampf(_preset.render_height / lines, MIN_RENDER_SCALE, 1.0)
