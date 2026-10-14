extends Node
## Headless check of the hero's powers: drives scripted input through each move
## in the real city and prints what happened (speed, height, mode).
## Run: godot --headless --path . res://tests/hero_moves_test.tscn

## Manhattan's avenues run about 29 degrees east of north.
const AVENUE := Vector3(0.485, 0.0, -0.875)
## Start of a 700 m stretch of avenue with no buildings in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
## A spot in the Hudson River, west of Midtown (world meters).
const HUDSON := Vector3(-2200.0, 5.0, 0.0)

var _hero: Hero
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _stats := {}


func _ready() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	# No pedestrians or thugs here: this test is about movement only.
	world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = world.get_node("Hero")
	# Run before the hero each tick so the scripted input is used right away.
	process_physics_priority = -20
	_steps = [
		_step("wait for the ground to load", 20.0, Callable(), func() -> bool: return not _hero.frozen),
		_step("go to an open avenue", 1.0, func(_i: HeroInput, t: float) -> void:
			if t < 0.02:
				_teleport(OPEN_AVENUE)),
		_step("run along the avenue", 2.0, func(i: HeroInput, _t: float) -> void: _move(i, AVENUE)),
		_step("super speed", 4.0, func(i: HeroInput, _t: float) -> void:
			_move(i, AVENUE)
			i.sprint_held = true),
		_step("let go and stop", 2.0),
		_step("tap jump", 1.5, func(i: HeroInput, t: float) -> void: i.jump_held = t < 0.1),
		_step("charge super jump", 1.3, func(i: HeroInput, _t: float) -> void: i.jump_held = true),
		_step("super jump (release)", 2.0),
		_step("start flying", 1.0, func(i: HeroInput, t: float) -> void: i.fly_toggle_pressed = t < 0.02),
		_step("fly up", 2.0, func(i: HeroInput, _t: float) -> void: i.vertical = 1.0),
		_step("fly forward, boosting", 3.0, func(i: HeroInput, _t: float) -> void:
			i.stick = Vector2(0.0, -1.0)
			i.aim = AVENUE
			i.sprint_held = true),
		_step("hover", 2.0, func(i: HeroInput, _t: float) -> void: i.aim = AVENUE),
		_step("boost up into the ceiling", 9.0, func(i: HeroInput, _t: float) -> void:
			i.aim = AVENUE
			i.vertical = 1.0
			i.sprint_held = true),
		_step("stop flying and fall", 20.0, func(i: HeroInput, t: float) -> void: i.fly_toggle_pressed = t < 0.02,
			func() -> bool: return _time > 0.5 and _hero.is_on_floor()),
		_step("back to the open avenue", 1.0, func(_i: HeroInput, t: float) -> void:
			if t < 0.02:
				_teleport(OPEN_AVENUE)),
		_step("web swing from the ground", 1.6, _swing_input),
		_step("let go of the web", 0.4, func(i: HeroInput, _t: float) -> void: _move(i, AVENUE)),
		_step("second swing", 1.6, _swing_input),
		_step("let go again", 0.4, func(i: HeroInput, _t: float) -> void: _move(i, AVENUE)),
		_step("third swing", 1.6, _swing_input),
		_step("let go and land", 6.0, func(i: HeroInput, _t: float) -> void: _move(i, AVENUE),
			func() -> bool: return _hero.is_on_floor()),
		_step("drop into the Hudson", 4.0, func(_i: HeroInput, t: float) -> void:
			if t < 0.02:
				_teleport(HUDSON)),
		_step("swim", 2.0, func(i: HeroInput, _t: float) -> void: _move(i, Vector3.RIGHT)),
		_step("jump out of the water", 1.5, func(i: HeroInput, t: float) -> void: i.jump_held = t < 0.1),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)

	var world := _hero.world_position()
	_stats.max_speed = maxf(_stats.max_speed, _hero.velocity.length())
	_stats.max_height = maxf(_stats.max_height, world.y)
	_stats.min_height = minf(_stats.min_height, world.y)
	if not _stats.modes.has(_hero.mode.name):
		_stats.modes.append(_hero.mode.name)
	if _hero.is_on_wall():
		_stats.wall_ticks += 1

	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	print("%-28s %5.1fs  modes %-15s now %-7s speed %5.1f  max %5.1f  height %6.1f..%6.1f  wall %3d  at %s" % [
		step.name, _time, ",".join(_stats.modes), _hero.mode.name, _hero.velocity.length(),
		_stats.max_speed, _stats.min_height, _stats.max_height, _stats.wall_ticks, world.round()])
	if _index + 1 >= _steps.size():
		get_tree().quit()
		return
	_begin(_index + 1)


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	var y := _hero.world_position().y
	_stats = {max_speed = 0.0, max_height = y, min_height = y, modes = [], wall_ticks = 0}


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until}


func _swing_input(input: HeroInput, _t: float) -> void:
	_move(input, AVENUE)
	input.aim = AVENUE
	input.web_held = true


func _teleport(world_position: Vector3) -> void:
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _move(input: HeroInput, direction: Vector3) -> void:
	input.move = direction
	input.stick = Vector2(0.0, -1.0)
