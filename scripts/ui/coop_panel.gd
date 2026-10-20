class_name CoopPanel
extends Control
## The co-op menu (M). In the public game (which the game joins by itself, see
## Net) it says so and how many are playing, with Leave (play alone), Host a
## private game and Join with a code; otherwise it offers the public game, and
## hosting a private game to send friends its link or room code, or joining a
## friend's game with theirs. Shows who's playing (and, in a private game,
## hosting), and the room's code and link to everyone in the game (and,
## quietly, when the co-op server has been gone for a few seconds). Dims the
## game behind it and takes the mouse while open. On touch screens
## (use_touch_layout) it gets a Close button and bigger buttons, and the room
## code box becomes a browser text box, so the phone's keyboard comes up. In a
## computer's browser it also links to the Windows and Mac versions
## (download.html, next to the game's page; tools/build_web.ps1 puts it there).

signal toggled(open: bool)

const WIDTH := 460.0
const ERROR_COLOR := Color(1.0, 0.55, 0.45)
## The players line names this many at most (the public game can have dozens).
const MAX_NAMES := 12

var _status: Label
var _reconnecting: Label
var _public_button: Button
var _host_button: Button
var _join_row: HBoxContainer
var _code_edit: LineEdit
var _invite: VBoxContainer
var _room: Label
var _room_code: Label
var _link_edit: LineEdit
var _players: Label
var _leave_button: Button
var _panel: PanelContainer
var _column: VBoxContainer
var _close_button: Button
var _hint: Label
var _download: LinkButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	Net.state_changed.connect(_refresh)
	Net.player_joined.connect(func(_id: int) -> void: _refresh())
	Net.player_left.connect(func(_id: int) -> void: _refresh())
	Net.host_changed.connect(func(_id: int) -> void: _refresh())
	Net.reconnecting_changed.connect(_refresh)
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


## Set up for fingers: a Close button instead of the M hint, buttons
## and boxes tall enough to tap, a tighter fit for phones' short screens, and
## the room code typed into a browser text box (WebTextField) in the browser.
func use_touch_layout() -> void:
	_close_button.visible = true
	_hint.visible = false
	_download.visible = false  # (no use on a phone or tablet)
	_column.add_theme_constant_override("separation", 9)
	(_panel.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(16.0)
	var tappable: Array = [_close_button, _public_button, _host_button, _leave_button]
	tappable.append_array(_join_row.get_children())
	tappable.append_array(_link_edit.get_parent().get_children())
	for control: Control in tappable:
		control.custom_minimum_size.y = 44.0
	if OS.has_feature("web"):
		var field := WebTextField.new()
		field.line_edit = _code_edit
		add_child(field)


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
	var public := Net.wants_public()  # (also looking for it, or waiting to try again)
	var count := Net.peers().size() + 1
	_public_button.visible = offline
	_public_button.text = "Try the public game again" if public else "Join the public game"
	_host_button.visible = offline or public
	_join_row.visible = offline or public
	_invite.visible = Net.is_online()
	_players.visible = Net.is_online()
	_reconnecting.visible = Net.is_reconnecting()
	_leave_button.visible = not offline or public
	_leave_button.text = "Leave (play alone)" if public else "Leave game"  # (the others play on)
	_status.remove_theme_color_override("font_color")
	match state:
		Net.State.OFFLINE:
			if public:
				_status.text = "Couldn't reach the public game; it'll be tried again in a while. You're playing alone meanwhile."
			elif Net.error:
				_status.text = Net.error
				_status.add_theme_color_override("font_color", ERROR_COLOR)
			else:
				_status.text = "You're playing alone. Join the public game with everyone playing online, or host a private game and send your friends the link, or join a friend's game with their room code."
		Net.State.CONNECTING:
			_status.text = "Joining the public game..." if public else "Connecting..."
		Net.State.HOSTING, Net.State.JOINED when Net.is_public:
			_status.text = "Everyone playing online is here, in the public game. Leave to play alone, or host a private game for just your friends."
		Net.State.HOSTING:
			_status.text = "You're hosting. Friends can join with the room code or the link."
		Net.State.JOINED:
			_status.text = "You're in %s's game. Friends can join with the room code or the link too." \
				% Net.player_name(Net.host_id)
	if Net.is_public:
		_room.text = "Public game  ·  %d player%s" % [count, "" if count == 1 else "s"]
		_room_code.text = "Room code: %s" % Net.room_code
	else:
		_room.text = "Room code: %s" % Net.room_code
	_room_code.visible = Net.is_public
	_link_edit.text = Net.invite_link()
	var names: Array[String] = []
	var everyone: Array = [Net.local_id()] + Array(Net.peers())
	for id: int in everyone.slice(0, MAX_NAMES):
		var notes: Array[String] = []
		if id == Net.local_id():
			notes.append("you")
		if id == Net.host_id and not Net.is_public:
			notes.append("host")
		names.append(Net.player_name(id) + (" (%s)" % ", ".join(notes) if notes else ""))
	if everyone.size() > MAX_NAMES:
		names.append("and %d more" % (everyone.size() - MAX_NAMES))
	_players.text = "Players: " + ", ".join(names)


func _build() -> void:
	var panel := PanelContainer.new()
	_panel = panel
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
	_column = column
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := Label.new()
	title.text = "CO-OP"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.visible = false  # touch screens only (no M or Esc there)
	_close_button.pressed.connect(close)
	title_row.add_child(_close_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH - 44.0, 0.0)
	column.add_child(_status)

	_reconnecting = Label.new()
	_reconnecting.text = "Reconnecting to the co-op server... (you're still playing together)"
	_reconnecting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reconnecting.custom_minimum_size = Vector2(WIDTH - 44.0, 0.0)
	_reconnecting.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
	_reconnecting.add_theme_font_size_override("font_size", 13)
	column.add_child(_reconnecting)

	_invite = VBoxContainer.new()
	_invite.add_theme_constant_override("separation", 8)
	column.add_child(_invite)
	_room = Label.new()
	_room.add_theme_font_size_override("font_size", 22)
	_invite.add_child(_room)
	_room_code = Label.new()  # (under the public game's name)
	_invite.add_child(_room_code)
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

	_public_button = Button.new()
	_public_button.pressed.connect(Net.join_public)
	column.add_child(_public_button)

	_host_button = Button.new()
	_host_button.text = "Host a private game"
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
	join_button.text = "Join with code"
	join_button.pressed.connect(func() -> void: Net.join(_code_edit.text))
	_join_row.add_child(join_button)


	_hint = Label.new()
	_hint.text = "M closes this menu"
	_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
	_hint.add_theme_font_size_override("font_size", 13)
	column.add_child(_hint)

	_download = LinkButton.new()
	_download.text = "Get the game for Windows or Mac"
	_download.add_theme_font_size_override("font_size", 13)
	_download.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	_download.visible = OS.has_feature("web") and not Device.is_mobile()
	_download.pressed.connect(func() -> void:
		OS.shell_open(str(JavaScriptBridge.eval("location.href.split(/[?#]/)[0].replace(/[^/]*$/, '')")) + "download.html"))
	column.add_child(_download)


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
