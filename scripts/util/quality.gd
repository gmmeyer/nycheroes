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
##   cars gone by (m)    170             320             460
##   rowhouse fronts     250             400             600
##   (railings, fences,
##   by tile center, m)
##   woods' clumps of    none            4000, none in   6000, far
##   crowns, by tile                     far tiles       tiles' 9000
##   center (m)
##   fog density         0.00016         0.00013         0.0001
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
		"car_fade": Vector2(120.0, 170.0),
		"fronts_range": 250.0,
		"canopy_ranges": [0.0, 0.0, 0.0],
		"fog_density": 0.00016,
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
		"load_distances": [500.0, 1100.0, 12000.0],
		"furniture_fade": [Vector2(150.0, 220.0), Vector2(360.0, 500.0)],
		"car_fade": Vector2(220.0, 320.0),
		"fronts_range": 400.0,
		"canopy_ranges": [4000.0, 4000.0, 0.0],
		"fog_density": 0.00013,
		"pedestrians": 24,
		"busy_crowd": 1.0,
		"cars": 90,
		"trains": 3,
		"gangs": 2,
		"gang_size": Vector2i(3, 4),
		"bodies": 10,
	},
}
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
## no tree shadows and fewer pedestrians, cars and trains below "high".
static func set_launch_defaults() -> void:
	if level() == Level.HIGH:
		return
	var preset: Dictionary = PRESETS[level()]
	LaunchOptions.set_default("tree_shadows", "0")
	LaunchOptions.set_default("peds", str(preset.pedestrians))
	LaunchOptions.set_default("traffic", str(preset.cars))
	LaunchOptions.set_default("trains", str(preset.trains))


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
		if Device.is_web():
			JavaScriptBridge.eval(STRETCHED_BLIT_FIX, true)
		sun.shadow_enabled = _preset.shadows
		if _preset.shadows:
			sun.directional_shadow_mode = _preset.shadow_mode
			sun.directional_shadow_max_distance = _preset.shadow_distance
		RenderingServer.directional_shadow_atlas_set_size(_preset.shadow_atlas, true)
		var distances: Array[float] = []
		distances.assign(_preset.load_distances)
		city.load_distances = distances
		city.set_furniture_fade(_preset.furniture_fade[0], _preset.furniture_fade[1])
		city.set_car_fade(_preset.car_fade)
		city.fronts_range = _preset.fronts_range
		var canopy: Array[float] = []
		canopy.assign(_preset.canopy_ranges)
		city.set_canopy_ranges(canopy)
		if environment and not LaunchOptions.has("fog"):
			environment.fog_density = _preset.fog_density
		crowd.busy_crowd = _preset.busy_crowd
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
