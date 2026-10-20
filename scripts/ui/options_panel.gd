class_name OptionsPanel
extends Control
## The options menu: O opens and closes it (Esc too in the desktop builds;
## a gamepad's Start), and so do the gear button on touch screens and the
## HUD's Options button. Four pages:
##   Hero      saved costume, hair, headgear and colors with a live preview
##   Game      graphics quality (Auto, Low, Medium, High), time of day, full
##             screen, FPS and stats, joining the public game automatically
##   Sound     Master, Effects and Ambience volumes, and the sound switch (N)
##   Controls  look speed (mouse, or fingers on touch screens), up and down
##             swapped, and what the keys (or touch buttons) do
## Changes apply at once and are remembered (Settings; a slider saves once
## it stops moving). Its Co-op button opens the co-op menu instead: one menu
## at a time. In single player the game pauses while it's open (the sound
## goes on); in co-op it doesn't (Net.state).
##
## Looks like CoopPanel: a dark panel over the dimmed game, which a click
## closes. Works with the mouse, keys (Tab or arrows, Enter or Space) and
## gamepads, and fingers (TouchControls sends the first one as a mouse). It
## frees the mouse while open; closing it with a click (Resume, or the game
## around it) captures it again, as do keys in the desktop builds; in the
## browser the next click does (browsers only lock the pointer for a click).
## On touch screens (use_touch_layout) its buttons are tall enough to tap, it
## keeps clear of the screen's notches, and its page scrolls when the screen
## is too short to show all of it.

signal toggled(open: bool)

const WIDTH := 690.0
const NOTE_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const KEY_COLOR := Color(1.0, 0.9, 0.6)
## A slider saves its setting once it has stood still this long (s).
const SAVE_DELAY := 0.4
## How often the open menu checks for changes made elsewhere (N, T, the
## browser leaving full screen).
const REFRESH_INTERVAL := 0.25
const PAGE_NAMES: Array[String] = ["Game", "Hero", "Sound", "Controls"]
const LEVEL_NAMES: Array[String] = ["Low", "Medium", "High"]
const TIME_NAMES: Array[String] = ["Dawn", "Day", "Dusk", "Night"]
const VOLUME_NAMES := {"volume_master": "Master volume", "volume_effects": "Effects", "volume_ambience": "Ambience"}
const KEYS: Array[Array] = [
	["W A S D", "move"],
	["Mouse", "look around (click the game first)"],
	["Left mouse", "punch; in the air, a dive attack (hold W to call it off)"],
	["Space", "jump; hold for a super jump"],
	["Shift", "super speed"],
	["F", "fly; Space and C go up and down"],
	["E, right mouse", "web swing (hold)"],
	["M", "co-op"],
	["O", "options (this menu)"],
	["N", "sound off and on"],
	["T", "time of day"],
	["F1", "free camera (wheel: its speed)"],
]
const DESKTOP_KEYS: Array[Array] = [
	["Esc", "options too"],
	["F11", "full screen"],
]
const TOUCH_HELP: Array[Array] = [
	["Left side", "move: the stick follows your thumb"],
	["Drag elsewhere", "look around"],
	["PUNCH", "punch; DIVE in the air (push the stick up to call it off)"],
	["JUMP", "hold for a super jump; UP while flying"],
	["WEB", "hold to swing"],
	["FLY", "fly; DOWN goes down"],
	["SPEED", "super speed, on and off"],
	["CO-OP", "play with friends"],
]

## Set by Game.
var coop_panel: CoopPanel
var quality: Quality
var time_of_day: TimeOfDay
## The ?stats text (DebugHud): "Show FPS and stats" shows and hides it.
var debug_label: Control

var _touch := false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _page := 0
var _quality_buttons: Array[Button] = []  # auto, low, medium, high
var _quality_note: Label
## A preset was picked here this session (over ?quality).
var _quality_picked := false
var _time_buttons: Array[Button] = []
var _fullscreen: Button
var _stats: Button
var _public: Button
var _sound: Button
var _invert: Button
var _sliders := {}  # setting key -> HSlider
var _resume: Button
var _paused_game := false
var _recapture := false
var _refresh_cooldown := 0.0
var _unsaved := {}  # setting key -> value
var _save_at := 0
var _fits_left := 0


## Adds the "options_menu" action: O (and Esc in the desktop builds, where
## it reaches the game; browsers keep it for leaving the pointer lock and
## full screen) and a gamepad's Start.
static func add_action() -> void:
	if InputMap.has_action(&"options_menu"):
		return
	InputMap.add_action(&"options_menu")
	var keys: Array[Key] = [KEY_O]
	if not Device.is_web():
		keys.append(KEY_ESCAPE)
	for keycode in keys:
		var key := InputEventKey.new()
		key.physical_keycode = keycode
		InputMap.action_add_event(&"options_menu", key)
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	InputMap.action_add_event(&"options_menu", start)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS  # (it pauses the game)
	visible = false
	_build()
	resized.connect(_fit)
	Net.state_changed.connect(func() -> void:
		if _paused_game and Net.state != Net.State.OFFLINE:
			_set_paused(false))  # co-op goes on


## Opens the menu; `by_key` puts the keyboard's focus on it.
func open(by_key := false) -> void:
	if visible:
		return
	visible = true
	_recapture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_paused(true)
	_refresh()
	_refresh_sliders()
	_fit()
	_fits_left = 2  # (wrapped notes know their height after a layout pass)
	if by_key:
		_tabs[_page].grab_focus()
	toggled.emit(true)


## Closes the menu. `by_pointer`: with a click or tap, which may capture the
## mouse again in the browser too.
func close(by_pointer := false, recapture := true) -> void:
	if not visible:
		return
	visible = false
	_save_now()
	get_viewport().gui_release_focus()
	_set_paused(false)
	if recapture and _recapture and (by_pointer or not Device.is_web()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(false)


func toggle(by_key := false) -> void:
	if visible:
		close()
	else:
		open(by_key)


## Set up for fingers: taller rows and buttons, the touch buttons' help
## instead of the keys', and the finger's look speed.
func use_touch_layout() -> void:
	if _touch:
		return
	_touch = true
	for child in get_children():
		child.free()
	_pages.clear()
	_tabs.clear()
	_quality_buttons.clear()
	_time_buttons.clear()
	_sliders.clear()
	_build()
	if visible:
		_refresh()
		_refresh_sliders()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"options_menu") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"coop_menu"):
		_open_coop()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# A gamepad's Start or B (keys come through _unhandled_key_input).
	if visible and event is InputEventJoypadButton \
			and (event.is_action_pressed(&"options_menu") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# A click on the dimmed game around it closes the menu, as the button
	# comes up (closed while it's down, the hero would punch).
	if event is InputEventMouseButton:
		if not event.pressed:
			close(true)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.45))


func _process(delta: float) -> void:
	if not visible:
		return
	if _fits_left > 0:
		_fits_left -= 1
		_fit()
	if not _unsaved.is_empty() and Time.get_ticks_msec() >= _save_at:
		_save_now()
	_refresh_cooldown -= delta
	if _refresh_cooldown <= 0.0:
		_refresh_cooldown = REFRESH_INTERVAL
		_refresh()


func _set_paused(on: bool) -> void:
	if on and Net.state == Net.State.OFFLINE and not get_tree().paused:
		get_tree().paused = true
		_paused_game = true
	elif not on and _paused_game:
		_paused_game = false
		get_tree().paused = false


func _open_coop() -> void:
	close(false, false)
	if coop_panel:
		coop_panel.open()


## Shows what's set now (N, T or the browser may have changed some).
func _refresh() -> void:
	if _quality_buttons.is_empty():
		return
	var chosen := Quality.choice()
	var lit := chosen
	if Quality.set_by_launch_option() and not _quality_picked:
		lit = Quality.level_name()
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(Quality.CHOICES[i] == lit)
	var device := "%s on this %s" % [LEVEL_NAMES[Quality.device_level()], Quality.device_name()]
	if Quality.set_by_launch_option() and not _quality_picked:
		_quality_note.text = "%s for this visit (?quality=%s in the address). Auto is %s." % [
			LEVEL_NAMES[Quality.level()], Quality.level_name(), device]
	else:
		_quality_note.text = "Auto is %s. Changes apply at once; trees' shadows and far woods catch up as new streets load." % device
	if time_of_day:
		var phase := ["dawn", "day", "dusk", "night"].find(time_of_day.phase_name())
		for i in _time_buttons.size():
			_time_buttons[i].set_pressed_no_signal(i == phase)
	_set_toggle(_fullscreen, Device.is_fullscreen())
	_set_toggle(_stats, debug_label != null and debug_label.visible)
	_set_toggle(_public, bool(Settings.get_value("online_public", true)))
	_set_toggle(_sound, not GameAudio.is_muted())
	_set_toggle(_invert, ThirdPersonCamera.look_y_sign() < 0.0)


func _refresh_sliders() -> void:
	for key: String in _sliders:
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal(roundf(float(Settings.get_value(key, 1.0)) * 100.0))
		_show_value(slider)


func _choose_quality(choice: String) -> void:
	_quality_picked = true
	Settings.set_value("quality", choice)
	var level := Quality.device_level() if choice == "auto" else Quality.NAMES.find(choice) as Quality.Level
	if quality:
		quality.change_level(level)
	_refresh()


func _set_volume(key: String, share: float) -> void:
	# Heard at once; saved once the slider stands still.
	var bus := AudioServer.get_bus_index(SoundSettings.VOLUMES[key])
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, SoundSettings.volume_db(share))
	_save_later(key, share)


func _save_later(key: String, value: Variant) -> void:
	_unsaved[key] = value
	_save_at = Time.get_ticks_msec() + int(SAVE_DELAY * 1000.0)


func _save_now() -> void:
	for key: String in _unsaved:
		Settings.set_value(key, _unsaved[key])
	_unsaved.clear()


func _show_page(index: int) -> void:
	_page = index
	for i in _pages.size():
		_pages[i].visible = i == index
		_tabs[i].set_pressed_no_signal(i == index)
	_scroll.scroll_vertical = 0
	_fits_left = 2


## Sizes the panel to its tallest page (so the tabs stay put), and the
## page's scrolling to the screen, clear of notches on touch screens.
func _fit() -> void:
	if _panel == null or not is_inside_tree():
		return
	var area := Rect2(Vector2.ZERO, size)
	if _touch:
		var insets := Device.safe_area_css() * (Device.pixel_ratio() / get_window().content_scale_factor)
		area = Rect2(area.position + Vector2(insets.x, insets.y), area.size - Vector2(insets.x + insets.z, insets.y + insets.w))
	area = area.grow(-8.0)
	var width := minf(WIDTH, area.size.x)
	var content := 0.0
	for page in _pages:
		content = maxf(content, page.get_combined_minimum_size().y)
	_scroll.custom_minimum_size = Vector2(0.0, content)
	_panel.custom_minimum_size = Vector2(width, 0.0)
	var extra := _panel.get_combined_minimum_size().y - area.size.y
	if extra > 0.0:
		_scroll.custom_minimum_size.y = maxf(content - extra, 60.0)
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = (area.position + (area.size - _panel.size) * 0.5).floor()


func _build() -> void:
	var panel := PanelContainer.new()
	_panel = panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16.0 if _touch else 22.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.theme = _theme()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10 if _touch else 14)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	column.add_child(title_row)
	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 22 if _touch else 26)
	title.custom_minimum_size.x = 130.0 if _touch else 150.0
	title_row.add_child(title)
	var tab_row := title_row
	if _touch:
		tab_row = HBoxContainer.new()
		tab_row.add_theme_constant_override("separation", 6)
		column.add_child(tab_row)
	var tab_group := ButtonGroup.new()
	for i in PAGE_NAMES.size():
		var tab := _segment(PAGE_NAMES[i])
		tab.button_group = tab_group
		tab.custom_minimum_size.x = 0.0
		tab.pressed.connect(_show_page.bind(i))
		tab_row.add_child(tab)
		_tabs.append(tab)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for page in [_game_page(), HeroCustomizationPage.create(_touch), _sound_page(), _controls_page()]:
		pages.add_child(page)
		_pages.append(page)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	var coop := Button.new()
	coop.text = "Co-op..."
	coop.pressed.connect(_open_coop)
	footer.add_child(coop)
	var hint := _note("" if _touch else ("O or Esc closes this menu" if not Device.is_web() else "O closes this menu"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)
	_resume = Button.new()
	_resume.text = "Resume"
	_resume.pressed.connect(close.bind(true))
	footer.add_child(_resume)
	if _touch:
		for button: Button in [coop, _resume]:
			button.custom_minimum_size.y = 44.0
	_show_page(_page)


func _game_page() -> VBoxContainer:
	var page := _page_box()
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in Quality.CHOICES.size():
		var button := _segment("Auto" if i == 0 else LEVEL_NAMES[i - 1])
		button.button_group = group
		button.pressed.connect(_choose_quality.bind(Quality.CHOICES[i]))
		levels.add_child(button)
		_quality_buttons.append(button)
	_row(page, "Graphics", levels)
	_quality_note = _note("")
	_quality_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_quality_note)
	var times := HBoxContainer.new()
	times.add_theme_constant_override("separation", 6)
	for i in TIME_NAMES.size():
		var button := _segment(TIME_NAMES[i])
		button.toggle_mode = true
		button.pressed.connect(func() -> void:
			if time_of_day:
				time_of_day.go_to(i)
			_refresh_cooldown = 0.0)
		times.add_child(button)
		_time_buttons.append(button)
	_row(page, "Time of day", times)
	_fullscreen = _switch(func(on: bool) -> void:
		Device.set_fullscreen(on)
		if not Device.is_web():
			Settings.set_value("fullscreen", on)
		_refresh_cooldown = 0.3)  # (then shows what the browser did)
	_row(page, "Full screen", _fullscreen).visible = Device.can_fullscreen()
	_stats = _switch(func(on: bool) -> void:
		Settings.set_value("show_stats", on)
		if debug_label:
			debug_label.visible = on)
	_row(page, "Show FPS and stats", _stats)
	_public = _switch(func(on: bool) -> void: Settings.set_value("online_public", on))
	_row(page, "Join the public game automatically", _public)
	return page


func _sound_page() -> VBoxContainer:
	var page := _page_box()
	for key: String in VOLUME_NAMES:
		var slider := _slider(0.0, 100.0, 1.0, func(value: float) -> void: _set_volume(key, value / 100.0))
		_sliders[key] = slider
		_row(page, VOLUME_NAMES[key], slider.get_parent())
	_sound = _switch(func(on: bool) -> void:
		if on == GameAudio.is_muted():
			GameAudio.toggle_mute())
	_row(page, "Sound" if _touch else "Sound (N)", _sound)
	return page


func _controls_page() -> VBoxContainer:
	var page := _page_box()
	var key := "look_touch" if _touch else "look_mouse"
	var slider := _slider(25.0, 300.0, 5.0, func(value: float) -> void: _save_later(key, value / 100.0))
	_sliders[key] = slider
	_row(page, "Look speed", slider.get_parent())
	_invert = _switch(func(on: bool) -> void: Settings.set_value("invert_y", on))
	_row(page, "Swap looking up and down", _invert)
	var help := GridContainer.new()
	help.columns = 2
	help.add_theme_constant_override("h_separation", 16)
	help.add_theme_constant_override("v_separation", 3)
	var lines: Array[Array] = []
	lines.assign(TOUCH_HELP if _touch else KEYS + (DESKTOP_KEYS if not Device.is_web() else []))
	for line in lines:
		var name := Label.new()
		name.text = line[0]
		name.add_theme_color_override("font_color", KEY_COLOR)
		name.add_theme_font_size_override("font_size", 14)
		help.add_child(name)
		var what := Label.new()
		what.text = line[1]
		what.add_theme_font_size_override("font_size", 14)
		what.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
		help.add_child(what)
	var heading := _note("TOUCH CONTROLS" if _touch else "KEYS")
	page.add_child(heading)
	page.add_child(help)
	return page


func _page_box() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6 if _touch else 10)
	return page


## A row: a name on the left, then `control`. Returns the row.
func _row(page: VBoxContainer, label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name := Label.new()
	name.text = label
	name.custom_minimum_size.x = 200.0 if _touch else 280.0
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name)
	if not control is Button:  # (switches keep their size)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	page.add_child(row)
	return row


## A button that stays lit while chosen (one of a group, or a page tab).
func _segment(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.theme_type_variation = &"SegmentButton"
	button.custom_minimum_size = Vector2(74.0, 44.0 if _touch else 34.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return button


## An On/Off button; `on_toggled` gets its new state.
func _switch(on_toggled: Callable) -> Button:
	var button := _segment("Off")
	button.toggled.connect(func(on: bool) -> void:
		button.text = "On" if on else "Off"
		on_toggled.call(on))
	return button


func _set_toggle(button: Button, on: bool) -> void:
	if button:
		button.set_pressed_no_signal(on)
		button.text = "On" if on else "Off"


## A slider (percent) with its value shown after it, in a box of their own
## (the slider's parent).
func _slider(from: float, to: float, step: float, on_changed: Callable) -> HSlider:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 44.0 if _touch else 30.0
	box.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 52.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		_show_value(slider)
		on_changed.call(new_value))
	return slider


func _show_value(slider: HSlider) -> void:
	(slider.get_parent().get_child(1) as Label).text = "%d%%" % roundi(slider.value)


func _note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.add_theme_color_override("font_color", NOTE_COLOR)
	note.add_theme_font_size_override("font_size", 13)
	return note


## CoopPanel's buttons, page tabs and segments that light up when chosen,
## and sliders big enough for a thumb.
func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15 if _touch else 16
	var colors := {
		"Button": {"normal": Color(0.2, 0.32, 0.55), "hover": Color(0.26, 0.4, 0.66),
			"pressed": Color(0.14, 0.24, 0.42), "disabled": Color(0.2, 0.2, 0.22)},
		"SegmentButton": {"normal": Color(0.17, 0.19, 0.25), "hover": Color(0.23, 0.26, 0.34),
			"pressed": Color(0.26, 0.42, 0.72), "hover_pressed": Color(0.3, 0.47, 0.78), "disabled": Color(0.2, 0.2, 0.22)},
	}
	theme.set_type_variation(&"SegmentButton", &"Button")
	for type: String in colors:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = colors[type].get(state, colors[type].get("pressed", Color(0, 0, 0, 0)))
			if state == "focus":
				box.draw_center = false
				box.border_color = Color(1.0, 1.0, 1.0, 0.6)
				box.set_border_width_all(1)
			box.set_corner_radius_all(5)
			box.content_margin_left = 14.0
			box.content_margin_right = 14.0
			box.content_margin_top = 7.0
			box.content_margin_bottom = 7.0
			theme.set_stylebox(state, type, box)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color(0.3, 0.5, 0.85)
	var lit := track.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.38, 0.58, 0.92)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", lit)
	var grabber := 26 if _touch else 18
	theme.set_icon("grabber", "HSlider", _dot(grabber, Color(0.92, 0.94, 1.0)))
	theme.set_icon("grabber_highlight", "HSlider", _dot(grabber, Color.WHITE))
	theme.set_icon("grabber_disabled", "HSlider", _dot(grabber, Color(0.5, 0.5, 0.5)))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1.0, 1.0, 1.0, 0.6)
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(5)
	theme.set_stylebox("focus", "HSlider", focus)
	return theme


## A round grabber for the sliders.
static func _dot(diameter: int, color: Color) -> ImageTexture:
	var image := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var radius := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var edge := radius - Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			image.set_pixel(x, y, Color(color, clampf(edge, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
