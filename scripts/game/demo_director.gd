class_name DemoDirector
extends Node
## Plays a scripted tour for recording videos: ?demo shows off the hero's
## powers, ?demo=fight a street fight. Drives the hero's input and the camera
## and captions each part. Prints "[demo] start" and "[demo] finished" so a
## recorder can follow.

## Manhattan's avenues run about 29 degrees east of north.
const AVENUE := Vector3(0.485, 0.0, -0.875)
## 6th Avenue just north of Times Square, with clear street ahead (world
## meters; dropped onto the street).
const START := Vector3(420.0, 30.0, -220.0)
const SETTLE_TIME := 1.0

@export var game: Game
@export var hero: Hero
@export var camera: ThirdPersonCamera
@export var city: CityStreamer
@export var encounters: EncounterDirector

var _shots: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _settle := SETTLE_TIME
var _avenue_yaw := atan2(-AVENUE.x, -AVENUE.z)
var _yaw := 0.0
var _pitch := -0.12
var _caption: Label


func _ready() -> void:
	process_physics_priority = -20  # before the hero reads its input
	game.place_hero(START, _avenue_yaw, true)
	_yaw = _avenue_yaw + 2.4
	camera.yaw = _yaw
	camera.pitch = _pitch
	encounters.max_gangs = 0  # only gangs the tour places itself
	if LaunchOptions.get_string("demo") == "fight":
		_yaw = _avenue_yaw
		camera.yaw = _yaw
		_shots = [
			_shot("Street thugs", 3.0, Callable(), _fight_camera, _spawn_gang_ahead.bind(14.0, 5)),
			_shot("Punch combos", 6.5, _punch_input, _punch_camera),
			_shot("Super jump", 2.6, _charge_and_jump_input, _jump_camera, _spawn_gang_ahead.bind(9.0, 6)),
			_shot("Dive slam", 2.5, _dive_input, _dive_camera),
			_shot("Super speed ram", 4.5, _super_speed_input, _ram_camera, _spawn_gang_ahead.bind(85.0, 5)),
			_shot("", 3.0, Callable(), _aftermath_camera),
			_shot("", 0.5),
		]
	else:
		_shots = [
			_shot("Manhattan at 1:1 scale", 3.5, Callable(), _intro_camera),
			_shot("Super speed", 5.0, _super_speed_input),
			_shot("Web swinging", 6.6, _swing_input, _swing_camera),
			_shot("Flight", 5.0, _flight_input, _flight_camera),
			_shot("", 3.0, Callable(), _look_around_camera),
			_shot("Superhero landing", 5.0, _landing_input, _landing_camera),
			_shot("Super jump", 6.0, _super_jump_input, _super_jump_camera),
			_shot("", 1.0),
		]
	_make_caption()


func _physics_process(delta: float) -> void:
	hero.input.clear()
	hero.input.aim = AVENUE
	if _index < 0:
		if hero.frozen or city.pending_count() > 0:
			return
		_settle -= delta
		if _settle <= 0.0:
			print("[demo] start")
			_begin(0)
		return
	if _index >= _shots.size():
		return

	var shot := _shots[_index]
	_time += delta
	if shot.input.is_valid():
		shot.input.call(hero.input, _time)
	if shot.camera.is_valid():
		shot.camera.call(_time)
	if _time >= shot.seconds:
		_begin(_index + 1)
		if _index >= _shots.size():
			print("[demo] finished")


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-3.0 * delta)
	camera.yaw = lerp_angle(camera.yaw, _yaw, blend)
	camera.pitch = lerpf(camera.pitch, _pitch, blend)
	# Captions fade in at the start of a shot and out near its end.
	var alpha := 0.0
	if _index >= 0 and _index < _shots.size():
		var seconds: float = _shots[_index].seconds
		alpha = smoothstep(0.0, 0.4, _time) * (1.0 - smoothstep(seconds - 0.5, seconds, _time))
	_caption.modulate.a = alpha


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	if _index < _shots.size():
		_caption.text = _shots[_index].caption
		if _shots[_index].start.is_valid():
			_shots[_index].start.call()


# --- Fight tour ---

func _spawn_gang_ahead(distance: float, count: int) -> void:
	var across := Vector3(AVENUE.z, 0.0, -AVENUE.x)
	encounters.spawn_gang(hero.world_position() + AVENUE * distance, count, across)


func _fight_camera(_t: float) -> void:
	_yaw = _avenue_yaw
	_pitch = -0.25


func _punch_input(input: HeroInput, t: float) -> void:
	input.attack_held = t < 5.8 and fmod(t, 0.3) < 0.12


func _punch_camera(t: float) -> void:
	_yaw = _avenue_yaw + 0.8 * smoothstep(0.0, 6.5, t)
	_pitch = -0.3


func _charge_and_jump_input(input: HeroInput, t: float) -> void:
	input.jump_held = t < 1.0


func _jump_camera(t: float) -> void:
	_yaw = _avenue_yaw
	_pitch = lerpf(-0.25, -0.65, smoothstep(1.0, 2.6, t))


func _dive_input(input: HeroInput, t: float) -> void:
	input.attack_held = t < 0.1
	input.aim = (Vector3.DOWN + AVENUE * 0.2).normalized()


func _dive_camera(_t: float) -> void:
	_pitch = -0.6


func _ram_camera(_t: float) -> void:
	_yaw = _avenue_yaw
	_pitch = -0.15


func _aftermath_camera(t: float) -> void:
	_yaw = _avenue_yaw + 2.6 * smoothstep(0.0, 3.0, t)
	_pitch = -0.35


# --- Powers tour ---


func _intro_camera(t: float) -> void:
	_yaw = _avenue_yaw + 2.4 * (1.0 - smoothstep(0.0, 3.5, t))


func _super_speed_input(input: HeroInput, t: float) -> void:
	_move(input)
	input.sprint_held = t > 0.8


func _swing_input(input: HeroInput, t: float) -> void:
	_move(input)
	input.web_held = fmod(t, 1.9) < 1.5


func _swing_camera(_t: float) -> void:
	_pitch = -0.05


func _flight_input(input: HeroInput, t: float) -> void:
	input.fly_toggle_pressed = t < 0.02
	input.stick = Vector2(0.0, -1.0)
	input.sprint_held = t > 0.4
	input.vertical = 0.35 if t < 2.0 else 0.0


func _flight_camera(_t: float) -> void:
	_pitch = -0.2


func _look_around_camera(t: float) -> void:
	_yaw = _avenue_yaw + 1.8 * smoothstep(0.0, 3.0, t)
	_pitch = -0.3


func _landing_input(input: HeroInput, t: float) -> void:
	input.fly_toggle_pressed = t < 0.02


func _landing_camera(_t: float) -> void:
	_yaw = _avenue_yaw
	_pitch = -0.7


func _super_jump_input(input: HeroInput, t: float) -> void:
	input.jump_held = t < 1.2
	if t > 1.2:
		_move(input)


func _super_jump_camera(t: float) -> void:
	_yaw = _avenue_yaw
	_pitch = lerpf(-0.1, -0.55, smoothstep(1.2, 3.5, t))


func _move(input: HeroInput) -> void:
	input.move = AVENUE
	input.stick = Vector2(0.0, -1.0)


func _shot(text: String, seconds: float, input := Callable(), camera_move := Callable(), start := Callable()) -> Dictionary:
	return {caption = text, seconds = seconds, input = input, camera = camera_move, start = start}


func _make_caption() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.offset_top = -110.0
	_caption.offset_bottom = -50.0
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.modulate.a = 0.0
	layer.add_child(_caption)
