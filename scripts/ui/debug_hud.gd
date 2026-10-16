extends Label
## Debug overlay: frame rate, hero (or free camera) status and position, the
## time of day, tile streaming, and controls. Add ?stats to the page URL (--stats on desktop) to
## also log it to the console.

const ORIGIN_LAT := 40.7580
const ORIGIN_LON := -73.9855
const METERS_PER_DEGREE := 111320.0
const REFRESH_INTERVAL := 0.25
const LOG_INTERVAL := 2.0
const HERO_HELP := "WASD move  ·  Left mouse punch (in the air: dive attack)  ·  Space jump (hold: super jump)  ·  Shift super speed  ·  F fly (Space/C up/down)  ·  E / right mouse web swing  ·  M co-op  ·  T time of day  ·  N mute  ·  F1 free camera"
const FREE_CAMERA_HELP := "Free camera: WASD move  ·  Space/C up/down  ·  Shift boost  ·  Wheel speed  ·  T time of day  ·  N mute  ·  F1 back to hero"

@export var city: CityStreamer
@export var hero: Hero
@export var free_camera: FreeFlyCamera
@export var time_of_day: TimeOfDay

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

	var free := free_camera.current
	var world := WorldOrigin.to_world(free_camera.global_position if free else hero.global_position)
	var lat := ORIGIN_LAT - world.z / METERS_PER_DEGREE
	var lon := ORIGIN_LON + world.x / (METERS_PER_DEGREE * cos(deg_to_rad(ORIGIN_LAT)))
	var speed := free_camera.current_speed if free else hero.velocity.length()
	var who := "Free camera" if free else String(hero.mode.name)
	if not free and hero.frozen:
		who = "Waiting for ground"

	var render := "FPS %d  ·  %d draw calls  ·  %.2fM triangles  ·  %d MB textures" % [
		int(Engine.get_frames_per_second()),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6)]
	var status := "%s  ·  %.0f m/s (%.0f km/h)  ·  altitude %.0f m  ·  %.5f, %.5f  ·  %s %s" % [
		who, speed, speed * 3.6, world.y, lat, lon, time_of_day.clock_text(), time_of_day.phase_name()]
	var tiles := "Tiles: %d near, %d mid, %d far, %d loading  ·  %d props  ·  last tile build %.1f ms  ·  %d photos (last %.0f ms)" % [
		city.loaded_counts[0], city.loaded_counts[1], city.loaded_counts[2],
		city.pending_count(), city.prop_count, city.last_build_msec, city.photo_count, city.last_photo_msec]
	var standing := Combat.thugs.filter(func(thug: Thug) -> bool: return not thug.is_down()).size()
	var people := "Pedestrians %d  ·  thugs %d standing, %d down  ·  health %d" % [
		get_tree().get_node_count_in_group("pedestrians"), standing, Combat.defeated_count, int(hero.health)]
	var traffic := get_node_or_null("../../Traffic") as Traffic
	if traffic:
		people += "  ·  %d cars (%.2f ms)" % [traffic.car_count, traffic.update_msec]
	tiles += "  ·  " + people
	text = "\n".join([render, status, tiles, FREE_CAMERA_HELP if free else HERO_HELP])

	if _log_stats:
		_log_cooldown -= REFRESH_INTERVAL
		if _log_cooldown <= 0.0:
			_log_cooldown = LOG_INTERVAL
			print("[stats] %s | %s | %s | world %s" % [render, status, tiles, world.round()])
