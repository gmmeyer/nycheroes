class_name GameHud
extends Control
## Player HUD: health bar, thugs taken down, a marker pointing to the nearest
## thug, and in co-op a marker for each other player (markers sit at the
## screen edge when what they point at is off screen), the game's status and
## short notices ("Player 2 is now the host"), plus the aerial photos' credit
## while any are shown. An Options button in the top right corner opens the
## options menu with a click (touch screens have TouchControls' gear instead).

## The Options button was clicked.
signal options_requested

## Thugs closer than this and on screen don't need a marker.
const NEAR_ENOUGH := 35.0
## Other players have name tags; on screen and closer than this, that's enough.
const PLAYER_NEAR_ENOUGH := 120.0
const EDGE_MARGIN := 48.0
## On touch screens, markers keep this far from the right edge, off the buttons.
const TOUCH_BUTTONS_WIDTH := 100.0
const MARKER_COLOR := Color(1.0, 0.35, 0.25)
## Co-op notices show for this long (seconds).
const NOTICE_TIME := 6.0
const NOTICE_COLOR := Color(1.0, 0.9, 0.45)
## The license (CC BY 4.0) asks for this whenever the photos are shown.
const AERIAL_CREDIT := "Aerial imagery: NYC OTI / NYS Orthoimagery Program 2024 (CC BY 4.0)"

@export var hero: Hero
@export var encounters: EncounterDirector
@export var players: PlayerSync
@export var city: CityStreamer

## Set on touch screens (by Game): the health bar moves to the top left, out
## of the thumbs' way, and the HUD keeps clear of the screen's notches and of
## the touch buttons in the top right.
var touch_controls: TouchControls:
	set(value):
		touch_controls = value
		if _options_button:
			_options_button.visible = value == null

var _font: Font
var _notices: Array = []  # [text, msec when it goes]
var _options_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	Net.left_room.connect(func(id: int) -> void:
		if Net.is_online():
			notify("%s left" % Net.player_name(id)))
	Net.host_changed.connect(func(id: int) -> void:
		if Net.is_online():  # the host left, or the server named another (not: we joined, or left)
			notify("You're the host now" if id == Net.local_id() else "%s is now the host" % Net.player_name(id)))
	_add_options_button()


## Shows a line near the top of the screen for a few seconds.
func notify(text: String) -> void:
	_notices.append([text, Time.get_ticks_msec() + int(NOTICE_TIME * 1000.0)])


## The notices showing now.
func current_notices() -> PackedStringArray:
	var now := Time.get_ticks_msec()
	_notices = _notices.filter(func(notice: Array) -> bool: return notice[1] > now)
	return PackedStringArray(_notices.map(func(notice: Array) -> String: return notice[0]))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bar := Rect2(24.0, size.y - 44.0, 260.0, 18.0)
	if touch_controls:
		var insets := touch_controls.safe_insets
		bar = Rect2(insets.x + 20.0, insets.y + 32.0, 180.0, 14.0)
	draw_rect(bar.grow(3.0), Color(0.0, 0.0, 0.0, 0.55))
	var health := hero.health / Hero.MAX_HEALTH
	var fill := Color(0.85, 0.15, 0.12).lerp(Color(0.2, 0.8, 0.3), health)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), fill)
	_text(bar.position + Vector2(0.0, -8.0), "HEALTH", 14)
	_text(Vector2(bar.end.x + 24.0, bar.end.y - 2.0), "Thugs down: %d" % Combat.defeated_count, 18)
	if hero.mode.name == &"KnockedOut":
		_text(Vector2(size.x * 0.5 - 110.0, size.y * 0.35), "KNOCKED OUT", 40, MARKER_COLOR)
	_draw_coop_status()
	if city and city.photo_count > 0:
		var width := _font.get_string_size(AERIAL_CREDIT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		var at := Vector2(size.x - width - 16.0, size.y - 12.0)
		if touch_controls:  # bottom middle, between the thumbs
			at = Vector2((size.x - width) * 0.5, size.y - touch_controls.safe_insets.w - 8.0)
		_text(at, AERIAL_CREDIT, 12, Color(1.0, 1.0, 1.0, 0.8))
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
	if Net.is_reconnecting():  # (the game goes on meanwhile)
		line += "  ·  reconnecting..."
	if line:
		var width := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
		var at := Vector2(size.x - width - 24.0, 30.0)
		if _options_button and _options_button.visible:  # (left of it)
			at.x -= _options_button.size.x + 4.0
		if touch_controls:  # under the co-op button
			at = Vector2(size.x - touch_controls.safe_insets.z - width - 16.0, touch_controls.safe_insets.y + 78.0)
		_text(at, line, 16)
	# Notices: centered, under the debug text in the top left.
	var y := maxf(size.y * 0.2, 130.0)
	for text in current_notices():
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x
		_text(Vector2((size.x - width) * 0.5, y), text, 22, NOTICE_COLOR)
		y += 30.0


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
	if touch_controls:
		# Clear of notches, and left of the column of touch buttons.
		var insets := touch_controls.safe_insets + Vector4(0.0, 0.0, TOUCH_BUTTONS_WIDTH, 0.0)
		area = Rect2(area.position + Vector2(insets.x, insets.y), area.size - Vector2(insets.x + insets.z, insets.y + insets.w))
	var on_screen := not behind and area.has_point(point)
	if on_screen and distance < near_enough:
		return

	var center := area.get_center()  # the screen's middle, less any notches
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


## A small button in the top right corner: "OPTIONS  O". It never takes the
## keyboard's focus (Space would press it), and works as the mouse button
## goes down: the menu is open by the time the hero would read it as a punch.
func _add_options_button() -> void:
	_options_button = Button.new()
	_options_button.name = "OptionsButton"
	_options_button.text = "OPTIONS  ·  O"
	_options_button.focus_mode = Control.FOCUS_NONE
	_options_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_options_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_options_button.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal": Color(0.0, 0.0, 0.0, 0.38), "hover": Color(0.2, 0.32, 0.55, 0.85),
			"pressed": Color(1.0, 1.0, 1.0, 0.38)}[state]
		box.border_color = Color(1.0, 1.0, 1.0, 0.6)
		box.set_border_width_all(1)
		box.set_corner_radius_all(14)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 5.0
		box.content_margin_bottom = 5.0
		_options_button.add_theme_stylebox_override(state, box)
	# Pinned 16 px from the right edge, growing leftwards to fit its text.
	_options_button.anchor_left = 1.0
	_options_button.anchor_right = 1.0
	_options_button.offset_left = -16.0
	_options_button.offset_right = -16.0
	_options_button.offset_top = 14.0
	_options_button.offset_bottom = 14.0
	_options_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_options_button.pressed.connect(options_requested.emit)
	_options_button.visible = touch_controls == null
	add_child(_options_button)


func _text(at: Vector2, text: String, font_size: int, color := Color.WHITE) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color.BLACK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
