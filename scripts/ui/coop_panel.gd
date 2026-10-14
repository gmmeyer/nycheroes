class_name CoopPanel
extends Control
## The co-op menu (M): host a game and send friends its link or room code, or
## join a friend's game with theirs. Shows who's playing. Dims the game behind
## it and takes the mouse while open.

signal toggled(open: bool)

const WIDTH := 460.0
const ERROR_COLOR := Color(1.0, 0.55, 0.45)

var _status: Label
var _host_button: Button
var _join_row: HBoxContainer
var _code_edit: LineEdit
var _invite: VBoxContainer
var _room: Label
var _link_edit: LineEdit
var _players: Label
var _leave_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	Net.state_changed.connect(_refresh)
	Net.player_joined.connect(func(_id: int) -> void: _refresh())
	Net.player_left.connect(func(_id: int) -> void: _refresh())
	_refresh()


func open() -> void:
	if visible:
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	get_viewport().gui_release_focus()
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## True while typing in the menu, so its keys aren't game controls.
func is_typing() -> bool:
	return visible and get_viewport().gui_get_focus_owner() is LineEdit


func _gui_input(event: InputEvent) -> void:
	# A click on the dimmed game behind closes the menu.
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.45))


func _refresh() -> void:
	if _status == null:
		return
	var state := Net.state
	var offline := state == Net.State.OFFLINE
	_host_button.visible = offline
	_join_row.visible = offline
	_invite.visible = state == Net.State.HOSTING
	_players.visible = Net.is_online()
	_leave_button.visible = not offline
	_leave_button.text = "Stop hosting" if state == Net.State.HOSTING else "Leave game"
	_status.remove_theme_color_override("font_color")
	match state:
		Net.State.OFFLINE:
			if Net.error:
				_status.text = Net.error
				_status.add_theme_color_override("font_color", ERROR_COLOR)
			else:
				_status.text = "Play together: host a game and send your friends the link, or join a friend's game with their room code."
		Net.State.CONNECTING:
			_status.text = "Connecting..."
		Net.State.HOSTING:
			_status.text = "You're hosting. Friends can join with the room code or the link."
			_room.text = "Room code: %s" % Net.room_code
			_link_edit.text = Net.invite_link()
		Net.State.JOINED:
			_status.text = "You're in room %s." % Net.room_code
	var names: Array[String] = [Net.player_name(Net.local_id()) + " (you)"]
	for id in Net.peers():
		names.append(Net.player_name(id))
	_players.text = "Players: " + ", ".join(names)


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(22.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.theme = _theme()
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "CO-OP"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH - 44.0, 0.0)
	column.add_child(_status)

	_host_button = Button.new()
	_host_button.text = "Host a game"
	_host_button.pressed.connect(Net.host)
	column.add_child(_host_button)

	_join_row = HBoxContainer.new()
	_join_row.add_theme_constant_override("separation", 8)
	column.add_child(_join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Room code"
	_code_edit.max_length = 8
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(func(text: String) -> void:
		var caret := _code_edit.caret_column
		_code_edit.text = text.to_upper()
		_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(_text: String) -> void: Net.join(_code_edit.text))
	_join_row.add_child(_code_edit)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(func() -> void: Net.join(_code_edit.text))
	_join_row.add_child(join_button)

	_invite = VBoxContainer.new()
	_invite.add_theme_constant_override("separation", 8)
	column.add_child(_invite)
	_room = Label.new()
	_room.add_theme_font_size_override("font_size", 22)
	_invite.add_child(_room)
	var link_row := HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 8)
	_invite.add_child(link_row)
	_link_edit = LineEdit.new()
	_link_edit.editable = false
	_link_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_row.add_child(_link_edit)
	var copy_button := Button.new()
	copy_button.text = "Copy link"
	copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Net.invite_link())
		copy_button.text = "Copied")
	link_row.add_child(copy_button)

	_players = Label.new()
	_players.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_players.custom_minimum_size = Vector2(WIDTH - 44.0, 0.0)
	column.add_child(_players)

	_leave_button = Button.new()
	_leave_button.pressed.connect(func() -> void: Net.leave())
	column.add_child(_leave_button)

	var hint := Label.new()
	hint.text = "M or Esc closes this menu"
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
	hint.add_theme_font_size_override("font_size", 13)
	column.add_child(hint)


## Buttons that stand out from the dark panel.
static func _theme() -> Theme:
	var theme := Theme.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {
			"normal": Color(0.2, 0.32, 0.55), "hover": Color(0.26, 0.4, 0.66),
			"pressed": Color(0.14, 0.24, 0.42), "disabled": Color(0.2, 0.2, 0.22)}.get(state, Color(0, 0, 0, 0))
		if state == "focus":
			box.draw_center = false
			box.border_color = Color(1.0, 1.0, 1.0, 0.6)
			box.set_border_width_all(1)
		box.set_corner_radius_all(5)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 7.0
		box.content_margin_bottom = 7.0
		theme.set_stylebox(state, "Button", box)
	return theme
