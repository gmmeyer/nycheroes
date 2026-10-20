class_name NamePrompt
extends Control
## Asks for the player's name: the first time the game starts (Game, unless
## nobody's there to answer), and from the co-op menu's Change name. The name
## is kept (the setting "player_name") and shown to the other players over
## our hero and in their menus (see Net.player_name, PlayerSync). The first
## time, the box starts with a made-up name, so Play goes straight on; later,
## Cancel (or Esc) keeps the old one. Dims the game and takes the mouse while
## open; on touch screens the box is a browser text box (WebTextField), so the
## phone's keyboard comes up.

signal toggled(open: bool)

const WIDTH := 400.0
## Made-up names to start from: one of these and a number.
const SUGGESTIONS: Array[String] = ["Hero", "Comet", "Falcon", "Nova", "Bolt", "Spark", "Titan", "Shadow", "Blaze",
	"Echo", "Atlas", "Raven", "Jet", "Storm", "Vector", "Pulse"]

var _edit: LineEdit
var _cancel: Button
var _play: Button
var _title: Label
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


## Whether the player has never picked a name.
static func needs_name() -> bool:
	return Net.local_name().is_empty()


func open() -> void:
	if visible:
		return
	var first := needs_name()
	_title.text = "WHAT'S YOUR HERO NAME?" if first else "CHANGE YOUR NAME"
	_edit.text = _suggestion() if first else Net.local_name()
	_cancel.visible = not first
	_play.text = "Play" if first else "Save"
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	toggled.emit(true)
	if not OS.has_feature("web") or not Device.wants_touch_controls():
		_edit.grab_focus.call_deferred()
		_edit.select_all.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	get_viewport().gui_release_focus()
	toggled.emit(false)


## True while it's open, so keys typed aren't game controls.
func is_typing() -> bool:
	return visible


## Bigger buttons and a browser text box, for fingers (see the top).
func use_touch_layout() -> void:
	for control: Control in [_edit, _cancel, _play]:
		control.custom_minimum_size.y = 44.0
	if OS.has_feature("web"):
		var field := WebTextField.new()
		field.line_edit = _edit
		field.capitals = false
		add_child(field)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and _cancel.visible:
		close()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55))


func _accept() -> void:
	var picked := Net.clean_name(_edit.text)
	if picked.is_empty():
		picked = _suggestion()
	Settings.set_value("player_name", picked)
	close()


static func _suggestion() -> String:
	return "%s%d" % [SUGGESTIONS.pick_random(), randi_range(10, 999)]


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(22.0)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.theme = CoopPanel._theme()
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_title)
	var note := Label.new()
	note.text = "Other players see it over your hero."
	note.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	column.add_child(note)

	_edit = LineEdit.new()
	_edit.max_length = Net.NAME_LENGTH
	_edit.placeholder_text = "Your name"
	_edit.add_theme_font_size_override("font_size", 20)
	_edit.text_submitted.connect(func(_text: String) -> void: _accept())
	column.add_child(_edit)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.pressed.connect(close)
	buttons.add_child(_cancel)
	_play = Button.new()
	_play.pressed.connect(_accept)
	buttons.add_child(_play)
