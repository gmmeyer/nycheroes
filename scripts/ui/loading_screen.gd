class_name LoadingScreen
extends Control
## Covers the game while the city first loads, so it doesn't look frozen:
## the title, a bar for the tiles loaded so far (CityStreamer: loaded_counts
## and pending_count; it never goes back), what's happening, a spinner and a
## tip. Once the city has loaded and the hero stands on the ground (the hero
## isn't frozen any more), it fades out and goes. Game adds it under the
## NamePrompt, so a name can be picked meanwhile; the world draws behind it
## all along, so shaders are ready when it lifts.

## Gone this long after the city has loaded, even if the hero isn't down yet (s).
const AFTER_LOAD_LIMIT := 6.0
const FADE_TIME := 0.6
const BACKGROUND := Color(0.05, 0.06, 0.09)
const ACCENT := Color(0.85, 0.12, 0.12)
const TIPS: Array[String] = [
	"Shift: super speed. Run into thugs to bowl them over.",
	"Hold Space to charge a super jump.",
	"F to fly; Space and C go up and down.",
	"E or right mouse shoots a web to swing from.",
	"Punch in the air for a dive attack.",
	"M: play with everyone online, alone, or with friends.",
	"T steps the time of day on.",
	"O opens the options: graphics, sound, controls.",
]
const TOUCH_TIPS: Array[String] = [
	"The right side of the screen looks around.",
	"Hold jump to charge a super jump.",
	"The co-op button: play with everyone online, alone, or with friends.",
	"The gear opens the options: graphics, sound, controls.",
]
const TIP_TIME := 5.0

@export var city: CityStreamer
@export var hero: Hero

var _bar: ProgressBar
var _status: Label
var _tip: Label
var _spinner: Control
var _progress := 0.0
var _loaded_at := -1.0
var _time := 0.0
var _fading := false
var _tips := TIPS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	city.initial_load_finished.connect(func(_seconds: float) -> void: _loaded_at = _time, CONNECT_ONE_SHOT)


## Touch screens get tips about the on-screen controls.
func use_touch_layout() -> void:
	_tips = TOUCH_TIPS
	_tip.text = _tips[0]


func _process(delta: float) -> void:
	_time += delta
	_spinner.rotation += delta * 4.0
	if _fading:
		modulate.a = maxf(modulate.a - delta / FADE_TIME, 0.0)
		if modulate.a <= 0.0:
			queue_free()
		return
	var loaded := 0
	for n in city.loaded_counts:
		loaded += n
	var pending := city.pending_count()
	var fraction := float(loaded) / float(loaded + pending) if loaded + pending > 0 else 0.0
	if _loaded_at >= 0.0:
		fraction = 1.0
	# Never back (more tiles get asked for as it goes), and smoothly.
	_progress = maxf(_progress, minf(fraction, 0.99 if _loaded_at < 0.0 else 1.0))
	_bar.value = lerpf(_bar.value, _progress, 1.0 - exp(-6.0 * delta))
	if _loaded_at < 0.0:
		_status.text = "Getting the city ready..." if loaded == 0 else "Building New York  ·  %d tiles" % loaded
	else:
		_status.text = "Landing in Times Square..."
		if not hero.frozen or _time - _loaded_at > AFTER_LOAD_LIMIT:
			_fading = true
			mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.text = _tips[int(_time / TIP_TIME) % _tips.size()]


func _build() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The title up top and the progress low down: the name prompt, if it's
	# up, sits in the middle between them.
	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.12
	column.anchor_bottom = 0.9
	column.offset_left = -240.0
	column.offset_right = 240.0
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var title := Label.new()
	title.text = "NYC HEROES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", ACCENT)
	title.add_theme_constant_override("outline_size", 6)
	column.add_child(title)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)

	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, 10.0)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	back.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(_bar)

	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 10)
	column.add_child(status_row)
	_spinner = _Spinner.new()
	_spinner.custom_minimum_size = Vector2(18.0, 18.0)
	_spinner.pivot_offset = Vector2(9.0, 9.0)
	status_row.add_child(_spinner)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	status_row.add_child(_status)

	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 15)
	_tip.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.55))
	_tip.text = _tips[0]
	column.add_child(_tip)


## A ring with a gap, turned by the loading screen.
class _Spinner extends Control:
	func _draw() -> void:
		var center := size * 0.5
		draw_arc(center, size.x * 0.4, 0.0, TAU * 0.75, 24, LoadingScreen.ACCENT, 2.5, true)
