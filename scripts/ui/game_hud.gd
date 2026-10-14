class_name GameHud
extends Control
## Player HUD: health bar, thugs taken down, a marker pointing to the nearest
## thug, and in co-op a marker for each other player and the game's status
## (markers sit at the screen edge when what they point at is off screen).

## Thugs closer than this and on screen don't need a marker.
const NEAR_ENOUGH := 35.0
## Other players have name tags; on screen and closer than this, that's enough.
const PLAYER_NEAR_ENOUGH := 120.0
const EDGE_MARGIN := 48.0
const MARKER_COLOR := Color(1.0, 0.35, 0.25)

@export var hero: Hero
@export var encounters: EncounterDirector
@export var players: PlayerSync

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
	_draw_coop_status()
	var thug := encounters.nearest_thug(hero.world_position())
	if thug:
		_draw_marker(thug.global_position + Vector3.UP * 2.2, "THUGS", MARKER_COLOR, NEAR_ENOUGH)
	for id: int in players.remote_heroes:
		var other: Hero = players.remote_heroes[id]
		_draw_marker(other.global_position + Vector3.UP * 2.6, Net.player_name(id).to_upper(),
			Net.player_color(id).lightened(0.35), PLAYER_NEAR_ENOUGH)


func _draw_coop_status() -> void:
	var line := ""
	var count := Net.peers().size() + 1
	var people := "%d player%s" % [count, "" if count == 1 else "s"]
	match Net.state:
		Net.State.CONNECTING:
			line = "Co-op: connecting..."
		Net.State.HOSTING:
			line = "Co-op: hosting room %s  ·  %s" % [Net.room_code, people]
		Net.State.JOINED:
			line = "Co-op: room %s  ·  %s" % [Net.room_code, people]
	if line:
		var width := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
		_text(Vector2(size.x - width - 24.0, 30.0), line, 16)


## A marker pointing at a scene position, labeled with the distance to it.
## Skipped when the spot is on screen and closer than `near_enough`.
func _draw_marker(target: Vector3, label: String, color: Color, near_enough: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or size.x < EDGE_MARGIN * 3.0 or size.y < EDGE_MARGIN * 3.0:
		return
	var distance := target.distance_to(hero.global_position)
	var behind := camera.is_position_behind(target)
	var point := camera.unproject_position(target)
	var area := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	var on_screen := not behind and area.has_point(point)
	if on_screen and distance < near_enough:
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
	draw_colored_polygon(PackedVector2Array([tip, point - direction * 6.0 + side * 10.0, point - direction * 6.0 - side * 10.0]), color)
	_text(point + Vector2(-34.0, 30.0) - direction * 10.0, "%s %d m" % [label, distance], 15, color)


func _text(at: Vector2, text: String, font_size: int, color := Color.WHITE) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color.BLACK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
