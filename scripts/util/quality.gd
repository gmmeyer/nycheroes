class_name Quality
extends Node
## Graphics quality presets. Phones get "low", tablets "medium" and computers
## "high", the full look (which changes nothing at the start); the options
## menu's choice (Settings "quality": "auto" for the device's, or a preset)
## comes before that, and ?quality=low|medium|high (--quality=... on
## desktop) before both, for the session. Game calls set_launch_defaults()
## before the world's nodes start and adds this node, which applies the rest
## and keeps the 3-D resolution right as the window changes size.
## change_level() switches presets while playing (the options menu). With
## ?stats, it also logs memory use every few seconds ("[mem] ...").
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
##   cars gone by (m)    170             320             460
##   rowhouse fronts     250             400             600
##   (railings, fences,
##   by tile center, m)
##   woods' clumps of    none            4000, none in   6000, far
##   crowns, by tile                     far tiles       tiles' 9000
##   center (m)
##   fog density         0.00016         0.00013         0.0001
##   (dusk and night)
##   clear day's fog     1               0.8             0.5
##   (share; TimeOfDay)
##   pedestrians         12              24              45
##   (on busy streets)   12              24              up to 68
##   moving cars         35              90              180
##   trains on the els   2               3               4
##   gangs (thugs; most  1 (2-4; 6)      2 (3-4; 10)     2 (3-5; 16)
##   bodies left lying)
##
## "Lines" is the 3-D image's height in pixels (its width follows the screen;
## never more than the screen's own pixels): the HUD and touch buttons stay
## sharp. The tile distances are CityStreamer.load_distances; the fog hides
## where the city stops. Street furniture and cars (parked and moving) shrink
## away one by one before those distances (CityStreamer.set_furniture_fade()
## and set_car_fade()), and each tile's stop drawing past them, so phones
## draw them in fewer tiles. Without clumps of crowns, woods past the trees
## are only painted on the ground (CityStreamer.set_canopy_ranges()).
## ?fog=, ?peds=, ?traffic=, ?trains= and ?tree_shadows= still override their preset
## values.
##
## Switching presets while playing (change_level()) applies most of this at
## once: the 3-D resolution, antialiasing, shadows, fog, load distances,
## pedestrians, cars, trains and gangs, and how far tiles already built draw
## their furniture, cars, rowhouse fronts and woods' crowns. Tiles built
## under a lower preset get trees' shadows and far woods' crowns only when
## they're built again (as the hero moves on); they lose them at once.

enum Level { LOW, MEDIUM, HIGH }

const NAMES: Array[String] = ["low", "medium", "high"]
## The options menu's choices (Settings "quality"): "auto" is the device's preset.
const CHOICES: Array[String] = ["auto", "low", "medium", "high"]
const PRESETS := {
	Level.LOW: {
		"render_height": 540.0,
		"msaa": Viewport.MSAA_DISABLED,
		"shadows": false,
		"shadow_atlas": 1024,
		"tree_shadows": false,
		"load_distances": [350.0, 800.0, 7000.0],
		"furniture_fade": [Vector2(60.0, 90.0), Vector2(220.0, 300.0)],
		"car_fade": Vector2(120.0, 170.0),
		"fronts_range": 250.0,
		"canopy_ranges": [0.0, 0.0, 0.0],
		"fog_density": 0.00016,
		"clear_fog": 1.0,
		"pedestrians": 12,
		"busy_crowd": 1.0,
		"cars": 35,
		"trains": 2,
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
		"tree_shadows": false,
		"load_distances": [500.0, 1100.0, 12000.0],
		"furniture_fade": [Vector2(150.0, 220.0), Vector2(360.0, 500.0)],
		"car_fade": Vector2(220.0, 320.0),
		"fronts_range": 400.0,
		"canopy_ranges": [4000.0, 4000.0, 0.0],
		"fog_density": 0.00013,
		"clear_fog": 0.8,
		"pedestrians": 24,
		"busy_crowd": 1.0,
		"cars": 90,
		"trains": 3,
		"gangs": 2,
		"gang_size": Vector2i(3, 4),
		"bodies": 10,
	},
	# The scene's own values (world.tscn, the project settings and the
	# scripts' defaults), only applied when switching to "high" while playing.
	# tests/options_test.gd checks they still match.
	Level.HIGH: {
		"render_height": 0.0,  # full
		"msaa": -1,  # the project's (rendering/anti_aliasing/quality/msaa_3d: 4x)
		"shadows": true,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"shadow_distance": 1500.0,
		"shadow_atlas": -1,  # the project's (4096)
		"tree_shadows": true,
		"load_distances": [700.0, 1500.0, 30000.0],
		"furniture_fade": [Vector2(180.0, 260.0), Vector2(420.0, 580.0)],
		"car_fade": Vector2(320.0, 460.0),
		"fronts_range": 600.0,
		"canopy_ranges": [6000.0, 6000.0, 9000.0],
		"fog_density": 0.0001,
		"clear_fog": 0.5,
		"pedestrians": 45,
		"busy_crowd": 1.5,
		"cars": 180,
		"trains": 4,
		"gangs": 2,
		"gang_size": Vector2i(3, 5),
		"bodies": 16,
	},
}
## Launch options that other nodes read when they start, which presets below
## "high" give defaults (unless the page URL or command line has them).
const LAUNCH_DEFAULTS: Array[String] = ["tree_shadows", "peds", "traffic", "trains"]
## Never render 3-D at less than this share of the screen's pixels.
const MIN_RENDER_SCALE := 0.25
## After drawing a scaled-down 3-D image, Godot's Compatibility renderer
## copies its depth and stencil to the full-size screen. Chrome on Windows
## (ANGLE on Direct3D 11) stretches stencil on the CPU, which stalled every
## frame: low and medium ran at a quarter of high's frame rate. Nothing drawn
## after the 3-D image reads that stencil, so stretched copies leave it out.
const STRETCHED_BLIT_FIX := """(function () {
	if (typeof WebGL2RenderingContext === 'undefined' || window.nycStretchedBlitFix) return;
	window.nycStretchedBlitFix = true;
	var proto = WebGL2RenderingContext.prototype;
	var blit = proto.blitFramebuffer;
	proto.blitFramebuffer = function (x0, y0, x1, y1, dx0, dy0, dx1, dy1, mask, filter) {
		if ((mask & 0x400) && (x1 - x0 !== dx1 - dx0 || y1 - y0 !== dy1 - dy0)) {
			mask &= ~0x400;
			if (!mask) return;
		}
		blit.call(this, x0, y0, x1, y1, dx0, dy0, dx1, dy1, mask, filter);
	};
})();"""
const MEMORY_LOG_INTERVAL := 5.0

static var _level := -1
static var _reason := ""
## Launch options (LAUNCH_DEFAULTS) the page URL or command line gave.
static var _given := {}
static var _given_known := false

var _preset := {}
var _memory_log_cooldown := 0.0
var _log_memory := false
var _sun: DirectionalLight3D
var _environment: Environment
var _city: CityStreamer
var _crowd: CrowdManager
var _encounters: EncounterDirector
var _traffic: Traffic
var _trains: Trains
var _time_of_day: TimeOfDay


## The preset in use: from ?quality, else the options menu's choice, else
## from the device.
static func level() -> Level:
	if _level < 0:
		var asked := LaunchOptions.get_string("quality")
		var chosen := choice()
		if asked in NAMES:
			_level = NAMES.find(asked)
			_reason = "?quality"
		elif chosen in NAMES:
			_level = NAMES.find(chosen)
			_reason = "options"
		else:
			_level = device_level()
			_reason = device_name()
	return _level as Level


static func level_name() -> String:
	return NAMES[level()]


## The options menu's choice: "auto" or a preset's name.
static func choice() -> String:
	var chosen := str(Settings.get_value("quality", "auto"))
	return chosen if chosen in CHOICES else "auto"


## The preset this device gets by itself ("auto").
static func device_level() -> Level:
	if Device.is_mobile():
		return Level.LOW if Device.is_phone() else Level.MEDIUM
	return Level.HIGH


static func device_name() -> String:
	if Device.is_mobile():
		return "phone" if Device.is_phone() else "tablet"
	return "computer"


## Whether ?quality (--quality) picks the preset this session.
static func set_by_launch_option() -> bool:
	return LaunchOptions.get_string("quality") in NAMES


## How much of the preset's fog a clear day has (TimeOfDay).
static func clear_fog() -> float:
	return PRESETS[level()].clear_fog


## Launch options that other nodes read when they start (call before they do):
## no tree shadows and fewer pedestrians, cars and trains below "high".
static func set_launch_defaults() -> void:
	if not _given_known:
		_given_known = true
		for option in LAUNCH_DEFAULTS:
			if LaunchOptions.has(option):
				_given[option] = true
	if level() == Level.HIGH:
		return
	var preset: Dictionary = PRESETS[level()]
	LaunchOptions.set_default("tree_shadows", "0")
	LaunchOptions.set_default("peds", str(preset.pedestrians))
	LaunchOptions.set_default("traffic", str(preset.cars))
	LaunchOptions.set_default("trains", str(preset.trains))


## Applies the preset to the world's nodes (after they've started).
func apply(sun: DirectionalLight3D, environment: Environment, city: CityStreamer,
		crowd: CrowdManager, encounters: EncounterDirector, traffic: Traffic = null, trains: Trains = null,
		time_of_day: TimeOfDay = null) -> void:
	_sun = sun
	_environment = environment
	_city = city
	_crowd = crowd
	_encounters = encounters
	_traffic = traffic
	_trains = trains
	_time_of_day = time_of_day
	_log_memory = LaunchOptions.has("stats")
	get_tree().root.size_changed.connect(_update_render_scale)
	if level() != Level.HIGH:
		_apply_preset(false)
	_log()


## Switches to another preset while playing (the options menu). See the
## notes at the top for what changes at once.
func change_level(new_level: Level) -> void:
	if new_level == level():
		return
	_level = new_level
	_reason = "options"
	_apply_preset(true)
	_log()


func _apply_preset(live: bool) -> void:
	_preset = PRESETS[level()]
	var root := get_tree().root
	var msaa: int = _preset.msaa
	if msaa < 0:
		msaa = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", Viewport.MSAA_4X))
	root.msaa_3d = msaa as Viewport.MSAA
	_update_render_scale()
	if Device.is_web() and level() != Level.HIGH:
		JavaScriptBridge.eval(STRETCHED_BLIT_FIX, true)
	_sun.shadow_enabled = _preset.shadows
	if _preset.shadows:
		_sun.directional_shadow_mode = _preset.shadow_mode
		_sun.directional_shadow_max_distance = _preset.shadow_distance
	var atlas: int = _preset.shadow_atlas
	if atlas < 0:
		atlas = int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096))
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	var distances: Array[float] = []
	distances.assign(_preset.load_distances)
	_city.load_distances = distances
	_city.set_furniture_fade(_preset.furniture_fade[0], _preset.furniture_fade[1])
	_city.set_car_fade(_preset.car_fade)
	_city.fronts_range = _preset.fronts_range
	var canopy: Array[float] = []
	canopy.assign(_preset.canopy_ranges)
	_city.set_canopy_ranges(canopy)
	if _environment and not LaunchOptions.has("fog"):
		_environment.fog_density = _preset.fog_density
	_crowd.busy_crowd = _preset.busy_crowd
	_encounters.max_gangs = _preset.gangs
	_encounters.gang_size = _preset.gang_size
	_encounters.max_bodies = _preset.bodies
	if not live:
		return  # (the rest was read from the launch options as the nodes started)
	if not _given.has("tree_shadows"):
		_city.set_tree_shadows(_preset.tree_shadows)
	_city.refresh_detail()
	if _time_of_day:
		_time_of_day.set_quality_fog(_preset.fog_density)
	if not _given.has("peds"):
		_crowd.set_max_pedestrians(_preset.pedestrians)
	if _traffic and not _given.has("traffic"):
		_traffic.set_max_cars(_preset.cars)
	if _trains and not _given.has("trains"):
		_trains.set_max_trains(_preset.trains)


func _log() -> void:
	var root := get_tree().root
	print("[quality] %s (%s): 3-D %s, MSAA %s, shadows %s, tiles %s, %d pedestrians, %d gang(s)" % [
		level_name(), _reason,
		"%dx%d" % [roundi(root.size.x * root.scaling_3d_scale), roundi(root.size.y * root.scaling_3d_scale)],
		["off", "2x", "4x", "8x"][root.msaa_3d], "on" if _sun.shadow_enabled else "off",
		"/".join(_city.load_distances.map(func(d: float) -> String: return str(int(d)))),
		_crowd.max_pedestrians, _encounters.max_gangs])


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


## Renders 3-D at about the preset's number of lines, whatever the screen
## (all of them on "high").
func _update_render_scale() -> void:
	var root := get_tree().root
	var lines := float(mini(root.size.x, root.size.y))
	var height: float = _preset.get("render_height", 0.0)
	if lines <= 0.0 or height <= 0.0:
		if _preset:
			root.scaling_3d_scale = 1.0
		return
	root.scaling_3d_scale = clampf(height / lines, MIN_RENDER_SCALE, 1.0)
