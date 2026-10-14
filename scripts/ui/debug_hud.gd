extends Label
## Debug overlay: frame rate, camera position, tile streaming, and render stats.
## Add ?stats to the page URL (--stats on desktop) to also log them to the console.

const ORIGIN_LAT := 40.7580
const ORIGIN_LON := -73.9855
const METERS_PER_DEGREE := 111320.0
const REFRESH_INTERVAL := 0.25
const LOG_INTERVAL := 2.0

@export var city: CityStreamer
@export var camera: FreeFlyCamera

var _refresh_cooldown := 0.0
var _log_cooldown := 0.0
var _log_stats := false


func _ready() -> void:
	_log_stats = LaunchOptions.has("stats")


func _process(delta: float) -> void:
	_refresh_cooldown -= delta
	if _refresh_cooldown > 0.0:
		return
	_refresh_cooldown = REFRESH_INTERVAL

	var world := WorldOrigin.to_world(camera.global_position)
	var lat := ORIGIN_LAT - world.z / METERS_PER_DEGREE
	var lon := ORIGIN_LON + world.x / (METERS_PER_DEGREE * cos(deg_to_rad(ORIGIN_LAT)))
	var render := "FPS %d  ·  %d draw calls  ·  %.2fM triangles" % [
		int(Engine.get_frames_per_second()),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6]
	var tiles := "Tiles: %d near, %d far, %d loading" % [
		city.loaded_counts[CityStreamer.LOD_NEAR], city.loaded_counts[CityStreamer.LOD_FAR], city.pending_count()]
	var position_line := "%.0f m/s  ·  altitude %.0f m  ·  %.5f, %.5f" % [camera.current_speed, world.y, lat, lon]
	text = "\n".join([render, position_line, tiles,
		"Click to look  ·  WASD move  ·  Space/C up/down  ·  Shift boost  ·  Wheel speed"])

	if _log_stats:
		_log_cooldown -= REFRESH_INTERVAL
		if _log_cooldown <= 0.0:
			_log_cooldown = LOG_INTERVAL
			print("[stats] %s | %s | world %s" % [render, tiles, world.round()])
