class_name DemoDirector
extends Node
## Plays a scripted tour for recording videos: ?demo shows off the hero's
## powers, ?demo=fight a street fight, ?demo=city flies the free camera over
## the city. Drives the hero's input and the camera and captions each part.
## Prints "[demo] start" and "[demo] finished" so a recorder can follow, and
## "[demo] pause" / "[demo] resume" around waits for the city to load (a
## recorder can pause, so the video has no loading pop-in).

## Manhattan's avenues run about 29 degrees east of north.
const AVENUE := Vector3(0.485, 0.0, -0.875)
## 6th Avenue just north of Times Square, with clear street ahead (world
## meters; dropped onto the street).
const START := Vector3(420.0, 30.0, -220.0)
const SETTLE_TIME := 1.0
## City tour: after a jump, the camera holds still this long once every tile
## has loaded, before the shot rolls.
const LOADED_SETTLE := 0.6

@export var game: Game
@export var hero: Hero
@export var camera: ThirdPersonCamera
@export var city: CityStreamer
@export var encounters: EncounterDirector
## The city tour's camera.
@export var free_camera: FreeFlyCamera
## The city tour sets the clock for its dusk and night shots.
@export var time_of_day: TimeOfDay

var _shots: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _settle := SETTLE_TIME
var _avenue_yaw := atan2(-AVENUE.x, -AVENUE.z)
var _yaw := 0.0
var _pitch := -0.12
var _caption: Label
## City tour: the current flight ({from, to}: [world position, yaw, pitch],
## with yaw and pitch in degrees, like ?cam), and how long the city has been
## loaded while holding before it.
var _flight := {}
var _holding := false
var _loaded_time := 0.0


func _ready() -> void:
	process_physics_priority = -20  # before the hero reads its input
	game.place_hero(START, _avenue_yaw, true)
	_yaw = _avenue_yaw + 2.4
	camera.yaw = _yaw
	camera.pitch = _pitch
	encounters.max_gangs = 0  # only gangs the tour places itself
	if LaunchOptions.get_string("demo") == "city":
		_shots = [
			_flight_shot("New York City at 1:1 scale", 7.0, [381, 6, -150, -29, 4], [440, 160, -255, -29, -15], true),
			_flight_shot("Every building from the city's own data", 7.0,
					[300, 220, 760, 134, -12], [330, 240, 1300, 55, -12]),
			_flight_shot("3.4 million trees", 7.0, [1150, 340, -800, -29, -32], [1550, 340, -2100, -29, -32]),
			_flight_shot("Brownstone Brooklyn", 6.0, [500, 75, 9750, -30, -26], [700, 75, 9400, -30, -26]),
			_flight_shot("Houses with real roofs in Queens", 6.0, [11700, 60, 5050, -30, -22], [11850, 60, 4800, -30, -22]),
			_flight_shot("Rooftop water towers", 6.0, [-850, 85, 2350, -45, -30], [-600, 85, 2150, -45, -30]),
			_flight_shot("Crosswalks, street lights, street trees", 6.0, [420, 2.5, -220, -29, -3], [452, 2.5, -278, -29, -3], true),
			_flight_shot("Sunset", 8.0, [2805, 120, 798, 95, -4], [2650, 110, 760, 88, -3], false, [18.6, 20.1]),
			_flight_shot("Night falls: lit windows, floodlit towers", 7.0,
					[0, 400, 1600, 0, -32], [0, 330, 1300, 0, -38], false, [22.5, 22.5]),
			_flight_shot("Bridges strung with lights", 7.0,
					[-1462, 45, 6233, -47, 0], [-1300, 50, 6080, -47, 0], false, [22.5, 22.5]),
			_flight_shot("545,000 street lights", 6.0, [420, 2.5, -220, -29, -3], [452, 2.5, -278, -29, -3], true, [22.5, 22.5]),
			_shot("", 0.5),
		]
	elif LaunchOptions.get_string("demo") == "fight":
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
	if _holding:
		_hold(delta)
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
		if _holding:
			_caption.text = ""


# --- City tour ---

## A shot flying the free camera from one pose to another ([x, y, z, yaw,
## pitch]: world meters and degrees). With `low`, the heights are above the
## ground at the start instead of above sea level. `clock` ([from, to], in
## hours) runs the time of day along with it; without, it's day.
func _flight_shot(text: String, seconds: float, from: Array, to: Array, low := false, clock := []) -> Dictionary:
	return _shot(text, seconds, Callable(), _fly, _jump.bind(from, to, low, clock))


## Starts a flight: jumps the camera to its start and holds until the city
## there has loaded.
func _jump(from: Array, to: Array, low: bool, clock: Array) -> void:
	if not free_camera.current:
		game.use_free_camera(true)
		free_camera.set_process(false)  # the tour moves it
	# The camera jumps a moment after the pause, so a recorder has stopped.
	_flight = {from = from, to = to, low = low, lift = 0.0, wait = 0.25,
			clock = clock if not clock.is_empty() else [TimeOfDay.DEFAULT_CLOCK, TimeOfDay.DEFAULT_CLOCK]}
	_holding = true
	_loaded_time = 0.0
	print("[demo] pause")


func _hold(delta: float) -> void:
	if _flight.wait > 0.0:
		_flight.wait -= delta
		return
	_place_camera(0.0)
	if city.pending_count() > 0:
		_loaded_time = 0.0
		return
	_loaded_time += delta
	if _loaded_time < LOADED_SETTLE:
		return
	if _flight.low and _flight.lift == 0.0:
		var start := Vector3(_flight.from[0], 0.0, _flight.from[2])
		var ground := city.ground_height_at(start)
		_flight.lift = ground if not is_nan(ground) else 0.0
		_place_camera(0.0)
	_holding = false
	_caption.text = _shots[_index].caption
	print("[demo] resume")


func _fly(t: float) -> void:
	_place_camera(smoothstep(0.0, 1.0, t / _shots[_index].seconds))


func _place_camera(blend: float) -> void:
	var from: Array = _flight.from
	var to: Array = _flight.to
	var position := Vector3(from[0], from[1], from[2]).lerp(Vector3(to[0], to[1], to[2]), blend)
	position.y += _flight.lift
	free_camera.global_position = WorldOrigin.to_local(position)
	free_camera.rotation = Vector3(deg_to_rad(lerpf(from[4], to[4], blend)),
			lerp_angle(deg_to_rad(from[3]), deg_to_rad(to[3]), blend), 0.0)
	var clock: float = lerpf(_flight.clock[0], _flight.clock[1], blend)
	if time_of_day and not is_equal_approx(clock, time_of_day.clock):
		time_of_day.set_clock(clock)


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
