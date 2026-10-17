class_name HeroCustomizationPage
extends VBoxContainer
## Live, isolated 3D dressing room. Choices save through Settings (desktop
## ConfigFile and synchronous browser localStorage), shared with the real hero.
const CHARACTER := preload("res://assets/characters/mannequin/mannequin.glb")
var profile := HeroAppearance.current()
var outfit: HeroOutfit
var _choices := {}
var _colors := {}
var _viewport: SubViewport
var _character: Node3D
var _animation: AnimationPlayer
var _pending_color := false
var _save_delay := 0.0
var _touch := false

static func create(touch: bool) -> HeroCustomizationPage:
	var page := HeroCustomizationPage.new()
	page._touch = touch
	return page

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var intro := Label.new()
	intro.text = "YOUR HERO  /  Original suits. Your colors."
	intro.add_theme_color_override("font_color", Color("f1cf91"))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var content: BoxContainer = VBoxContainer.new() if _touch else HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	add_child(content)
	_build_preview(content)
	var editor := VBoxContainer.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.add_theme_constant_override("separation", 7)
	content.add_child(editor)
	for key: String in HeroAppearance.OPTIONS:
		var row := HBoxContainer.new()
		editor.add_child(row)
		var label := Label.new()
		label.text = {"suit": "Suit", "cape": "Cape", "hair": "Hair", "boots": "Boots", "headgear": "Headgear"}[key]
		label.custom_minimum_size.x = 74
		row.add_child(label)
		var choice := OptionButton.new()
		choice.name = key.capitalize() + "Choice"
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.custom_minimum_size.y = 42 if _touch else 32
		for text: String in HeroAppearance.LABELS[key]:
			choice.add_item(text)
		choice.item_selected.connect(func(index: int) -> void:
			profile[key] = HeroAppearance.OPTIONS[key][index]
			_save())
		row.add_child(choice)
		_choices[key] = choice
	var palettes := OptionButton.new()
	palettes.name = "PaletteChoice"
	palettes.add_item("Choose a color palette…")
	for palette: Array in HeroAppearance.PALETTES:
		palettes.add_item(palette[0])
	palettes.item_selected.connect(func(index: int) -> void:
		if index > 0:
			for i in 3:
				profile[HeroAppearance.COLORS[i]] = HeroAppearance.PALETTES[index - 1][i + 1]
			_save()
			palettes.select(0))
	editor.add_child(palettes)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 7)
	editor.add_child(swatches)
	for key: String in HeroAppearance.COLORS:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatches.add_child(column)
		var label := Label.new()
		label.text = {"primary": "Suit", "secondary": "Trim", "accent": "Accent", "skin": "Skin", "hair_color": "Hair"}[key]
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		var picker := ColorPickerButton.new()
		picker.name = key.capitalize() + "Color"
		picker.custom_minimum_size = Vector2(38, 38)
		picker.edit_alpha = false
		picker.tooltip_text = "Choose " + label.text.to_lower() + " color"
		picker.color_changed.connect(func(color: Color) -> void:
			profile[key] = color.to_html(false)
			_pending_color = true
			_save_delay = 0.15)
		picker.popup_closed.connect(_flush_color)
		column.add_child(picker)
		_colors[key] = picker
	var actions := HBoxContainer.new()
	editor.add_child(actions)
	for caption: String in ["Randomize", "Reset"]:
		var button := Button.new()
		button.text = caption
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			profile = HeroAppearance.randomized() if caption == "Randomize" else HeroAppearance.DEFAULT.duplicate()
			_save())
		actions.add_child(button)
	var note := Label.new()
	note.text = "Saved automatically on this device. Your outfit is shared in co-op.\nHelmet hides hair; all pieces follow your animations."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(0.74, 0.8, 0.87)
	add_child(note)
	Settings.changed.connect(_on_setting_changed)
	visibility_changed.connect(_sync_preview_visibility)
	_sync_preview_visibility()
	_refresh()

func _build_preview(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 220
	parent.add_child(column)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(220, 290 if not _touch else 235)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(container)
	_viewport = SubViewport.new()
	_viewport.name = "HeroPreview"
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(220, 290 if not _touch else 235)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101d2c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c1d8f4")
	env.ambient_light_energy = 0.65
	env_node.environment = env
	world.add_child(env_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, -35, 0)
	key.light_energy = 1.8
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 140, 0)
	rim.light_color = Color("70c9df")
	rim.light_energy = 0.8
	world.add_child(rim)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.13, 3.5)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.32
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.98, 0))
	_character = CHARACTER.instantiate()
	_character.rotation.y = -0.28
	world.add_child(_character)
	var skeleton := _character.find_child("Skeleton3D", true, false) as Skeleton3D
	var body := _character.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	outfit = HeroOutfit.new()
	outfit.name = "Outfit"
	skeleton.add_child(outfit)
	outfit.setup(skeleton, body, profile)
	_animation = _character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_animation.play("Idle")
	var controls := HBoxContainer.new()
	column.add_child(controls)
	var rotate := HSlider.new()
	rotate.name = "TurnSlider"
	rotate.min_value = -180
	rotate.max_value = 180
	rotate.value = -16
	rotate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate.tooltip_text = "Turn your hero"
	rotate.value_changed.connect(func(value: float) -> void: _character.rotation.y = deg_to_rad(value))
	controls.add_child(rotate)
	var pose := OptionButton.new()
	pose.name = "PoseChoice"
	pose.tooltip_text = "Preview an animation"
	for caption: String in ["Idle", "Walk", "Sprint", "Jump"]:
		pose.add_item(caption)
	pose.item_selected.connect(func(index: int) -> void:
		_animation.play(["Idle", "Walk", "Sprint", "Jump"][index], 0.2)
		camera.size = 3.0 if index >= 2 else 2.32
		outfit.set_motion(30.0 if index >= 2 else 0.0))
	controls.add_child(pose)

func _sync_preview_visibility() -> void:
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
		_animation.active = is_visible_in_tree()

func _process(delta: float) -> void:
	if _pending_color:
		_save_delay -= delta
		if _save_delay <= 0.0:
			_flush_color()

func _flush_color() -> void:
	if _pending_color:
		_pending_color = false
		_save()

func _save() -> void:
	_pending_color = false
	HeroAppearance.save(profile)
	_refresh()

func _on_setting_changed(key: String) -> void:
	if key == HeroAppearance.KEY:
		var saved := HeroAppearance.current()
		if saved != profile:
			profile = saved
			_refresh()

func _refresh() -> void:
	for key: String in _choices:
		(_choices[key] as OptionButton).select(HeroAppearance.OPTIONS[key].find(profile[key]))
	for key: String in _colors:
		(_colors[key] as ColorPickerButton).color = HeroAppearance.color(profile, key)
	if outfit:
		outfit.apply(profile)
