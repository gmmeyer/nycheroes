class_name TouchControls
extends Control
## On-screen controls for touch screens; Game adds them when Device says so.
##
## A floating stick on the left: it appears where the thumb lands in the left
## part of the screen, and follows a thumb that slides past its rim. Dragging
## anywhere else turns the camera. Buttons on the right:
##   PUNCH  attack (a dive attack in the air: the label then says DIVE)
##   JUMP   jump (hold for a super jump); while flying it's UP
##   DOWN   descend, while flying
##   WEB    web (hold to swing), not while flying
##   FLY    fly_toggle (lit while flying)
##   SPEED  super speed as a toggle (lit while on): it stays on until tapped
##          again or the stick has been let go for a moment
##   CO-OP  the co-op menu, and a full screen button where the browser can
## A finger holding WEB or JUMP that slides also turns the camera.
##
## Buttons press the same input actions as the keyboard (Input.action_press),
## so PlayerInput and the hero can't tell the difference; any number of
## fingers work at once. A quick tap stays pressed until PlayerInput has seen
## it (this node's physics step runs after PlayerInput's).
## While the co-op menu is open, the first finger on the screen works it like
## a mouse instead. Godot's own touch-to-mouse emulation is off: it would
## press the attack action (left mouse button) with every touch.

const STICK_RADIUS := 58.0
const KNOB_RADIUS := 26.0
## Share of the screen's width, from the left, where a touch grabs the stick.
const STICK_ZONE := 0.42
## Camera turn per UI pixel of drag (radians). UI pixels are CSS pixels on
## touch screens, about the same size on every phone.
const LOOK_SPEED := 0.0055
## A finger on WEB or JUMP that slides this far also turns the camera.
const BUTTON_LOOK_SLOP := 14.0
## Taps count this far outside a button's circle (the nearest button wins).
const HIT_SLOP := 12.0
## SPEED switches itself off once the stick has been let go this long (s).
const SPEED_IDLE_OFF := 0.8
## The airborne label (DIVE) shows after this long off the ground (s).
const AIR_LABEL_DELAY := 0.15
## How often to check the page for full screen and safe area changes (s).
const PAGE_POLL_INTERVAL := 0.5
const MARGIN := 14.0
## ThirdPersonCamera's pitch limits.
const MIN_PITCH := -1.4
const MAX_PITCH := 1.2

const FILL := Color(0.0, 0.0, 0.0, 0.38)
const FILL_PRESSED := Color(1.0, 1.0, 1.0, 0.38)
## GameHud.MARKER_COLOR, for buttons that are switched on.
const FILL_ON := Color(1.0, 0.35, 0.25, 0.6)
const RING := Color(1.0, 1.0, 1.0, 0.6)


class TouchButton:
	var id: StringName
	var label := ""
	var action: StringName
	## SPEED: each tap switches it on or off.
	var toggle := false
	## Sliding the finger also turns the camera.
	var drag_looks := false
	var center := Vector2.ZERO
	var radius := 30.0
	## Pill-shaped (co-op, full screen) instead of round.
	var rect := Rect2()
	var shown := true
	var on := false
	var touch := -1
	var touch_start := Vector2.ZERO

	func is_round() -> bool:
		return rect.size == Vector2.ZERO

	func distance_to(point: Vector2) -> float:
		if is_round():
			return point.distance_to(center) - radius
		var outside := Vector2(maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0),
			maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0))
		return outside.length() if outside != Vector2.ZERO else -1.0


var hero: Hero
var camera_rig: ThirdPersonCamera
var coop_panel: CoopPanel
## Turned on by a touch: Godot's mouse emulation stays on until that first
## finger lifts, so the mouse press it made is released too.
var started_by_touch := false
## The screen's notches and rounded corners, in UI pixels (left, top, right,
## bottom): the buttons and GameHud keep clear of them.
var safe_insets := Vector4.ZERO

var _font: Font
var _buttons: Array[TouchButton] = []
var _by_id := {}
var _by_touch := {}  # touch index -> TouchButton
var _to_release: Array[TouchButton] = []
var _stick_touch := -1
var _stick_center := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _stick_home := Vector2.ZERO
var _stick_idle := 0.0
var _look_touch := -1
var _menu_touch := -1
var _mode := &""
var _airborne := false
var _air_time := 0.0
var _can_fullscreen := false
var _fullscreen := false
var _page_poll := 0.0
var _portrait := false
var _pill_style: StyleBoxFlat
var _pill_style_pressed: StyleBoxFlat


func _ready() -> void:
	resized.connect(_layout)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_physics_priority = -5  # after PlayerInput (-10) has read the input
	_font = ThemeDB.fallback_font
	_pill_style = _pill(FILL)
	_pill_style_pressed = _pill(FILL_PRESSED)
	_add(&"punch", "PUNCH", &"attack")
	_add(&"jump", "JUMP", &"jump", false, true)
	_add(&"down", "DOWN", &"descend")
	_add(&"web", "WEB", &"web", false, true)
	_add(&"fly", "FLY", &"fly_toggle")
	_add(&"speed", "SPEED", &"sprint", true)
	_add(&"coop", "CO-OP", &"")
	_add(&"fullscreen", "", &"")
	if not started_by_touch:
		Input.emulate_mouse_from_touch = false
	coop_panel.toggled.connect(_on_coop_toggled)
	_can_fullscreen = Device.can_fullscreen()
	_poll_page()
	_update_hero_state(0.0)
	_layout()


func _notification(what: int) -> void:
	# Fingers that lift while the page is in the background never tell us.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed:
			_touch_down(touch.index, touch.position)
		else:
			_touch_up(touch.index, touch.position)
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag:
		_touch_drag(drag.index, drag.position, drag.relative)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_hero_state(delta)
	var speed: TouchButton = _by_id[&"speed"]
	_stick_idle = _stick_idle + delta if _stick_touch == -1 else 0.0
	if speed.on and _stick_idle > SPEED_IDLE_OFF:
		_set_toggle(speed, false)
	_page_poll -= delta
	if _page_poll <= 0.0:
		_page_poll = PAGE_POLL_INTERVAL
		_poll_page()


func _physics_process(_delta: float) -> void:
	for button in _to_release:
		if button.touch == -1:
			Input.action_release(button.action)
	_to_release.clear()


func _touch_down(index: int, at: Vector2) -> void:
	if coop_panel.visible:
		if _menu_touch == -1:
			_menu_touch = index
			_send_mouse_motion(at, Vector2.ZERO)
			_send_mouse_button(at, true)
		return
	var button := _button_at(at)
	if button:
		_press(button, index, at)
	elif at.x < size.x * STICK_ZONE and _stick_touch == -1:
		_stick_touch = index
		var reach := STICK_RADIUS + 6.0
		_stick_center = Vector2(clampf(at.x, safe_insets.x + reach, size.x - reach),
			clampf(at.y, reach, size.y - safe_insets.w - reach))
		_move_stick(at)
	elif _look_touch == -1:
		_look_touch = index


func _touch_up(index: int, at: Vector2) -> void:
	if started_by_touch:
		started_by_touch = false
		Input.emulate_mouse_from_touch = false
	if index == _menu_touch:
		_menu_touch = -1
		_send_mouse_button(at, false)
	if index == _stick_touch:
		_stick_touch = -1
		_set_stick(Vector2.ZERO)
		queue_redraw()
	if index == _look_touch:
		_look_touch = -1
	var button: TouchButton = _by_touch.get(index)
	if button:
		_release(button)


func _touch_drag(index: int, at: Vector2, relative: Vector2) -> void:
	if index == _menu_touch:
		_send_mouse_motion(at, relative)
	elif index == _stick_touch:
		_move_stick(at)
	elif index == _look_touch:
		_look(relative)
	elif _look_touch == -1 and _by_touch.has(index):
		var button: TouchButton = _by_touch[index]
		if button.drag_looks and at.distance_to(button.touch_start) > BUTTON_LOOK_SLOP:
			_look_touch = index


func _look(relative: Vector2) -> void:
	camera_rig.yaw -= relative.x * LOOK_SPEED
	camera_rig.pitch = clampf(camera_rig.pitch - relative.y * LOOK_SPEED, MIN_PITCH, MAX_PITCH)


func _move_stick(at: Vector2) -> void:
	var offset := at - _stick_center
	if offset.length() > STICK_RADIUS:
		# The stick follows a thumb that slides past its rim.
		_stick_center = at - offset.normalized() * STICK_RADIUS
		offset = at - _stick_center
	_stick_knob = at
	_set_stick(offset / STICK_RADIUS)
	queue_redraw()


## Presses the movement actions like an analog stick (x right, y down/back).
func _set_stick(value: Vector2) -> void:
	_axis(&"move_left", &"move_right", value.x)
	_axis(&"move_forward", &"move_back", value.y)


func _axis(negative: StringName, positive: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_press(positive, value)
		Input.action_release(negative)
	elif value < 0.0:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _press(button: TouchButton, index: int, at: Vector2) -> void:
	button.touch = index
	button.touch_start = at
	_by_touch[index] = button
	match button.id:
		&"coop":
			_send_action(&"coop_menu")
		&"fullscreen":
			Device.request_fullscreen()
		_:
			if button.toggle:
				_set_toggle(button, not button.on)
			else:
				Input.action_press(button.action)
	queue_redraw()


func _release(button: TouchButton) -> void:
	_by_touch.erase(button.touch)
	button.touch = -1
	if button.action != &"" and not button.toggle:
		_to_release.append(button)
	queue_redraw()


func _set_toggle(button: TouchButton, on: bool) -> void:
	button.on = on
	if on:
		Input.action_press(button.action)
	else:
		Input.action_release(button.action)
	queue_redraw()


## Lets go of everything (the co-op menu opened, or a button disappeared).
func _release_all() -> void:
	for button in _buttons:
		if button.touch != -1:
			_release(button)
		if button.on:
			_set_toggle(button, false)
	if _stick_touch != -1:
		_stick_touch = -1
		_set_stick(Vector2.ZERO)
	_look_touch = -1
	queue_redraw()


## Sends an action the way a key press would (Game opens the co-op menu on it).
func _send_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _send_mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	# Straight to the menu: Input would also press the attack action.
	get_viewport().push_input.call_deferred(event, true)


func _send_mouse_motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = at
	event.global_position = at
	event.relative = relative
	get_viewport().push_input.call_deferred(event, true)


func _on_coop_toggled(open: bool) -> void:
	if open:
		_release_all()
	visible = not open


## Labels and which buttons show follow what the hero is doing.
func _update_hero_state(delta: float) -> void:
	var mode: StringName = hero.mode.name if hero.mode else &""
	_air_time = 0.0 if hero.is_on_floor() or hero.is_in_water() else _air_time + delta
	var airborne := _air_time > AIR_LABEL_DELAY and mode != &"Melee"
	if mode == _mode and airborne == _airborne:
		return
	_mode = mode
	_airborne = airborne
	var flying := mode == &"Flight"
	(_by_id[&"punch"] as TouchButton).label = "DIVE" if airborne or flying else "PUNCH"
	(_by_id[&"jump"] as TouchButton).label = "UP" if flying else "JUMP"
	(_by_id[&"fly"] as TouchButton).on = flying
	_show(&"down", flying)
	_show(&"web", not flying)
	queue_redraw()


func _show(id: StringName, shown: bool) -> void:
	var button: TouchButton = _by_id[id]
	if button.shown and not shown and button.touch != -1:
		_release(button)
	button.shown = shown


func _poll_page() -> void:
	var insets := Device.safe_area_css() * (Device.pixel_ratio() / get_window().content_scale_factor)
	var fullscreen := Device.is_fullscreen()
	if insets != safe_insets or fullscreen != _fullscreen:
		safe_insets = insets
		_fullscreen = fullscreen
		_layout()


func _layout() -> void:
	if _buttons.is_empty():
		return  # resized before _ready made them
	var portrait := size.y > size.x
	if portrait != _portrait:
		# Turned: fingers that lifted over the page's "turn your phone"
		# overlay never reached the game.
		_portrait = portrait
		_release_all()
	var right := size.x - safe_insets.z - MARGIN
	var bottom := size.y - safe_insets.w - MARGIN
	# A thumb's arc around PUNCH in the bottom right corner.
	var punch := Vector2(right - 44.0, bottom - 44.0)
	_place(&"punch", punch, 44.0)
	_place(&"jump", punch + Vector2(-104.0, 8.0), 36.0)
	_place(&"down", punch + Vector2(-190.0, 8.0), 32.0)
	_place(&"web", punch + Vector2(6.0, -100.0), 36.0)
	_place(&"speed", punch + Vector2(-88.0, -84.0), 31.0)
	_place(&"fly", punch + Vector2(-14.0, -182.0), 31.0)
	# Co-op in the top right corner, full screen to its left.
	var top := safe_insets.y + 10.0
	var coop := Rect2(size.x - safe_insets.z - 12.0 - 84.0, top, 84.0, 44.0)
	(_by_id[&"coop"] as TouchButton).rect = coop
	var fullscreen: TouchButton = _by_id[&"fullscreen"]
	fullscreen.rect = Rect2(coop.position.x - 10.0 - 44.0, top, 44.0, 44.0)
	fullscreen.shown = _can_fullscreen and not _fullscreen
	_stick_home = Vector2(safe_insets.x + MARGIN + 30.0 + STICK_RADIUS, bottom - 20.0 - STICK_RADIUS)
	queue_redraw()


func _place(id: StringName, center: Vector2, radius: float) -> void:
	var button: TouchButton = _by_id[id]
	button.center = center
	button.radius = radius


func _add(id: StringName, label: String, action: StringName, toggle := false, drag_looks := false) -> void:
	var button := TouchButton.new()
	button.id = id
	button.label = label
	button.action = action
	button.toggle = toggle
	button.drag_looks = drag_looks
	_buttons.append(button)
	_by_id[id] = button


func _button_at(at: Vector2) -> TouchButton:
	var best: TouchButton = null
	var best_distance := HIT_SLOP
	for button in _buttons:
		if not button.shown or button.touch != -1:
			continue
		var distance := button.distance_to(at)
		if distance < best_distance:
			best = button
			best_distance = distance
	return best


func _draw() -> void:
	_draw_stick()
	for button in _buttons:
		if button.shown:
			_draw_button(button)


func _draw_stick() -> void:
	if _stick_touch == -1:
		# Where the stick usually goes, faintly.
		draw_arc(_stick_home, STICK_RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.22), 2.0, true)
		draw_circle(_stick_home, KNOB_RADIUS * 0.8, Color(1.0, 1.0, 1.0, 0.12), true, -1.0, true)
		return
	draw_circle(_stick_center, STICK_RADIUS, Color(0.0, 0.0, 0.0, 0.25), true, -1.0, true)
	draw_arc(_stick_center, STICK_RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.45), 2.5, true)
	draw_circle(_stick_knob, KNOB_RADIUS, Color(1.0, 1.0, 1.0, 0.55), true, -1.0, true)


func _draw_button(button: TouchButton) -> void:
	var pressed := button.touch != -1
	var center := button.center
	if button.is_round():
		var fill := FILL_PRESSED if pressed else (FILL_ON if button.on else FILL)
		draw_circle(center, button.radius, fill, true, -1.0, true)
		draw_arc(center, button.radius - 1.0, 0.0, TAU, 40, RING, 2.5, true)
	else:
		draw_style_box(_pill_style_pressed if pressed else _pill_style, button.rect)
		center = button.rect.get_center()
	if button.id == &"fullscreen":
		_draw_fullscreen_icon(center)
		return
	var font_size := 15 if button.radius >= 40.0 else 13
	var width := _font.get_string_size(button.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at := center + Vector2(-width * 0.5, font_size * 0.36)
	draw_string_outline(_font, at, button.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 3, Color.BLACK)
	draw_string(_font, at, button.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)


## Four corner brackets.
func _draw_fullscreen_icon(center: Vector2) -> void:
	var r := 9.0
	var arm := 6.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var tip: Vector2 = center + corner * r
		draw_polyline(PackedVector2Array([tip - Vector2(corner.x * arm, 0.0), tip, tip - Vector2(0.0, corner.y * arm)]),
			Color.WHITE, 2.5, true)


static func _pill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(22)
	box.border_color = RING
	box.set_border_width_all(2)
	box.anti_aliasing = true
	return box
