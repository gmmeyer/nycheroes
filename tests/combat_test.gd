extends Node
## Headless check of fights: thugs attacking, punch combos, dive slams, super
## speed rams, panicking pedestrians, getting knocked out, and ragdolls holding
## still through a world origin shift. Prints what happened at each step.
## Run: godot --headless --path . res://tests/combat_test.tscn

const AVENUE := Vector3(0.485, 0.0, -0.875)
## Start of a long stretch of 6th Avenue with nothing in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _gang: Array[Thug] = []
var _hips_before := Vector3.ZERO


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	process_physics_priority = -20
	_steps = [
		_step("wait for the ground", 20.0, Callable(), func() -> bool: return not _hero.frozen),
		_step("thugs walk up and attack", 6.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
				_spawn_gang(OPEN_AVENUE + AVENUE * 8.0, 4)),
		_step("punch combos", 6.0, func(i: HeroInput, t: float) -> void:
			i.aim = AVENUE
			i.attack_held = fmod(t, 0.3) < 0.12),
		_step("charge a super jump", 1.1, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_spawn_gang(_hero.world_position() + AVENUE * 12.0, 4)
			i.jump_held = true),
		_step("rise", 1.5, func(i: HeroInput, _t: float) -> void: i.aim = (AVENUE - Vector3.UP).normalized()),
		_step("dive attack", 4.0, func(i: HeroInput, t: float) -> void:
			i.aim = (AVENUE * 0.3 - Vector3.UP).normalized()
			i.attack_held = t < 0.1,
			func() -> bool: return _time > 0.5 and _hero.is_on_floor() and _hero.mode.name == &"OnFoot"),
		_step("super speed ram", 4.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
				_spawn_gang(OPEN_AVENUE + AVENUE * 90.0, 4)
			i.move = AVENUE
			i.stick = Vector2(0.0, -1.0)
			i.sprint_held = true),
		_step("ragdolls hold through a shift", 0.2, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_hips_before = _corpse_hips_world()
				WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))),
		_step("get knocked out", 8.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE + AVENUE * 200.0)
				_spawn_gang(_hero.world_position() + AVENUE * 3.0, 3)
				_hero.health = 10.0,
			func() -> bool: return _hero.mode.name == &"KnockedOut"),
		_step("get back up", 5.0, Callable(), func() -> bool: return _hero.mode.name == &"OnFoot"),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_index = 0
	var step := _steps[_index]
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)
	_time += delta
	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	_report(step.name)
	_index += 1
	_time = 0.0
	if _index >= _steps.size():
		get_tree().quit()


func _report(step_name: String) -> void:
	var standing := Combat.thugs.filter(func(thug: Thug) -> bool: return not thug.is_down()).size()
	var panicking := get_tree().get_nodes_in_group("pedestrians").filter(
		func(p: Pedestrian) -> bool: return p.is_panicking()).size()
	var extra := ""
	if step_name.begins_with("ragdolls"):
		extra = "  corpse hips moved %.2f m (world)" % _hips_before.distance_to(_corpse_hips_world())
	print("%-30s %5.1fs  mode %-10s health %3d  thugs standing %d  down %2d  pedestrians %d (%d panicking)  hero %s%s" % [
		step_name, _time, _hero.mode.name, int(_hero.health), standing, Combat.defeated_count,
		get_tree().get_node_count_in_group("pedestrians"), panicking, _hero.world_position().round(), extra])


func _spawn_gang(world_center: Vector3, count: int) -> void:
	for k in count:
		var thug: Thug = THUG_SCENE.instantiate()
		add_child(thug)
		var spot := world_center + Vector3(AVENUE.z, 0.0, -AVENUE.x) * (k - (count - 1) * 0.5) * 1.6
		spot.y = _hero.world_position().y  # the same street as the hero
		var ground := _city.ground_height_at(spot, 6.0)
		if not is_nan(ground):
			spot.y = ground
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(_hero, k, TAU * k / count)
		_gang.append(thug)


func _corpse_hips_world() -> Vector3:
	for thug in _gang:
		if is_instance_valid(thug) and thug.is_down():
			var hips := thug.find_child("DEF-hips", true, false) as Node3D
			if hips:
				return WorldOrigin.to_world(hips.global_position)
	return Vector3.ZERO


## Moves the hero to a world position, standing on the ground there if there is any.
func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until}
