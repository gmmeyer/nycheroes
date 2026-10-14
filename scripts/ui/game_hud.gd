class_name GameHud
extends Control
## Player HUD: health bar, thugs taken down, and a marker pointing to the
## nearest thug (at the screen edge when it's off screen).

## Thugs closer than this and on screen don't need a marker.
const NEAR_ENOUGH := 35.0
const EDGE_MARGIN := 48.0
const MARKER_COLOR := Color(1.0, 0.35, 0.25)

@export var hero: Hero
@export var encounters: EncounterDirector

var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bar := Rect2(24.0, size.y - 44.0, 260.0, 18.0)
	draw_rect(bar.grow(3.0), Color(0.0, 0.0, 0.0, 0.55))
	var health := hero.health / Hero.MAX_HEALTH
	var fill := Color(0.85, 0.15, 0.12).lerp(Color(0.2, 0.8, 0.3), health)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), fill)
	_text(bar.position + Vector2(0.0, -8.0), "HEALTH", 14)
	_text(Vector2(bar.end.x + 24.0, bar.end.y - 2.0), "Thugs down: %d" % Combat.defeated_count, 18)
	if hero.mode.name == &"KnockedOut":
		_text(Vector2(size.x * 0.5 - 110.0, size.y * 0.35), "KNOCKED OUT", 40, MARKER_COLOR)
	_draw_thug_marker()


func _draw_thug_marker() -> void:
	var camera := get_viewport().get_camera_3d()
	var thug := encounters.nearest_thug(hero.world_position())
	if camera == null or thug == null or size.x < EDGE_MARGIN * 3.0 or size.y < EDGE_MARGIN * 3.0:
		return
	var head := thug.global_position + Vector3.UP * 2.2
	var distance := head.distance_to(hero.global_position)
	var behind := camera.is_position_behind(head)
	var point := camera.unproject_position(head)
	var area := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	var on_screen := not behind and area.has_point(point)
	if on_screen and distance < NEAR_ENOUGH:
		return

	var center := size * 0.5
	var direction := (point - center).normalized()
	if behind:
		direction = -direction
	if not on_screen:
		# Slide out from the middle of the screen to its edge.
		var reach := minf(
			absf((area.size.x * 0.5) / direction.x) if absf(direction.x) > 0.001 else INF,
			absf((area.size.y * 0.5) / direction.y) if absf(direction.y) > 0.001 else INF)
		point = center + direction * reach
	var side := Vector2(-direction.y, direction.x)
	var tip := point + direction * 14.0
	draw_colored_polygon(PackedVector2Array([tip, point - direction * 6.0 + side * 10.0, point - direction * 6.0 - side * 10.0]), MARKER_COLOR)
	_text(point + Vector2(-34.0, 30.0) - direction * 10.0, "THUGS %d m" % distance, 15, MARKER_COLOR)


func _text(at: Vector2, text: String, font_size: int, color := Color.WHITE) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color.BLACK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
