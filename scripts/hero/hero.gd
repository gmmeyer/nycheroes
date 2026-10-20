class_name Hero
extends CharacterBody3D
## A superhero that runs, super-speeds, super-jumps, flies, web-swings and fights.
##
## Movement modes are child HeroMode nodes (OnFoot, Flight, Swing, Melee, Dive,
## KnockedOut); the active one drives `velocity` from `input` each physics tick.
## Everything another player needs to see (mode, velocity, facing, web anchor,
## health) is plain state. In co-op, other players' heroes are copies whose
## state PlayerSync sets from the network instead (`remote_id` is set).

signal mode_changed(mode_name: StringName)
## Emitted on touching down, with the downward speed just before impact.
signal landed(impact_speed: float)
signal hurt(damage: float)

const GRAVITY := 30.0
const MAX_FALL_SPEED := 95.0
const WORLD_LAYER := 1
## This far below the water's surface, the hero is in the water.
const WATER_LINE := -0.6
## How far above and below the hero to look for a raised lake's surface.
const WATER_PROBE := 4.0
const MAX_HEALTH := 100.0
## Health comes back after this long without being hit.
const REGEN_DELAY := 4.0
const REGEN_RATE := 15.0
## Landing faster than this slams the ground, hurling thugs nearby.
const SLAM_SPEED := 35.0
## How long a hit staggers the hero.
const HURT_TIME := 0.35
## Stepping up a curb eases the drawn hero (and camera) up at this speed (m/s)
## instead of popping up in one tick.
const STEP_EASE_SPEED := 2.5

var input := HeroInput.new()
## Yaw the hero faces, in radians (0 = north, which is -Z).
var facing := 0.0
var mode: HeroMode
## Physics waits until the ground under the spawn point has loaded.
var frozen := true
var health := MAX_HEALTH
## Seconds left of being staggered by a hit.
var hurt_time := 0.0
## Set by a dive attack: the next landing slams, however slow it is.
var slam_pending := false
## For a copy of another player's hero: that player's number (0 for our own).
var remote_id := 0
## For a copy: whether that player's hero is on the ground.
var remote_grounded := false
## For a copy: whether that player's hero is in the water.
var remote_in_water := false
## Height of the water surface around the hero: a raised lake's, or sea level (0).
var water_level := 0.0

# Input edges for this tick, worked out from `input`.
var jump_pressed := false
var web_pressed := false
var attack_pressed := false

var _modes := {}
var _prev_jump := false
var _prev_web := false
var _prev_attack := false
var _prev_position := Vector3.ZERO
var _was_on_floor := false
var _regen_delay := 0.0
var _step_offset := 0.0  # height still to ease up after stepping onto a curb (m)


func _ready() -> void:
	add_to_group("floating")
	Combat.register_hero(self)
	WorldOrigin.shifted.connect(_on_origin_shifted)
	for child in get_children():
		if child is HeroMode:
			child.hero = self
			_modes[child.name] = child
	set_mode(&"OnFoot")
	_prev_position = global_position


func _exit_tree() -> void:
	Combat.unregister_hero(self)


func _physics_process(delta: float) -> void:
	_prev_position = global_position
	_step_offset = move_toward(_step_offset, 0.0, STEP_EASE_SPEED * delta)
	if frozen or is_remote():
		return
	water_level = _find_water_level()
	jump_pressed = input.jump_held and not _prev_jump
	web_pressed = input.web_held and not _prev_web
	attack_pressed = input.attack_held and not _prev_attack
	_prev_jump = input.jump_held
	_prev_web = input.web_held
	_prev_attack = input.attack_held
	hurt_time = maxf(hurt_time - delta, 0.0)
	_regen_delay -= delta
	if _regen_delay <= 0.0:
		health = minf(health + REGEN_RATE * delta, MAX_HEALTH)

	var fall_speed := -velocity.y
	var next := mode.physics_update(delta)
	input.fly_toggle_pressed = false
	if next != &"" and next != mode.name:
		set_mode(next)
	if global_position.y > WorldOrigin.CEILING:
		global_position.y = WorldOrigin.CEILING
		velocity.y = minf(velocity.y, 0.0)

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
		if fall_speed >= SLAM_SPEED or slam_pending:
			_slam(maxf(fall_speed, 60.0) if slam_pending else fall_speed)
	if on_floor:
		slam_pending = false
	_was_on_floor = on_floor


## Switches movement mode. Copies of other players' heroes skip the modes' own
## setup (`run_hooks` false): they only show the mode.
func set_mode(mode_name: StringName, run_hooks := true) -> void:
	if mode and mode.name == mode_name and not run_hooks:
		return
	var previous: StringName = mode.name if mode else &""
	if mode and run_hooks:
		mode.exit()
	mode = _modes[mode_name]
	if run_hooks:
		mode.enter(previous)
	mode_changed.emit(mode_name)


func get_mode(mode_name: StringName) -> HeroMode:
	return _modes[mode_name]


## Position to draw at: blended between physics ticks so motion stays smooth
## at any frame rate.
func get_visual_position() -> Vector3:
	var position := _prev_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
	return position + Vector3.DOWN * _step_offset


## Moved up a curb this tick (LedgeClimb): draw the rise smoothly.
func eased_step(rise: float) -> void:
	_prev_position.y += rise
	_step_offset += rise


func world_position() -> Vector3:
	return WorldOrigin.to_world(global_position)


func is_remote() -> bool:
	return remote_id != 0


## On the ground (works for copies of other players' heroes too).
func grounded() -> bool:
	return remote_grounded if is_remote() else is_on_floor()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func is_in_water() -> bool:
	return remote_in_water if is_remote() else global_position.y < water_level + WATER_LINE


func can_be_attacked() -> bool:
	return not frozen and mode.name != &"KnockedOut"


## Turns `facing` toward a horizontal direction, at most max_step radians.
func face_toward(direction: Vector3, max_step := INF) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	facing = rotate_toward(facing, atan2(-direction.x, -direction.z), max_step)


## Hit by a thug: lose health, get knocked back, and go down at zero.
func take_hit(damage: float, push: Vector3) -> void:
	if not can_be_attacked() or mode.name == &"Dive":
		return
	health = maxf(health - damage, 0.0)
	hurt_time = HURT_TIME
	_regen_delay = REGEN_DELAY
	velocity += push
	hurt.emit(damage)
	if health <= 0.0:
		set_mode(&"KnockedOut")


## The surface of a raised lake just above or below the hero, else sea level.
func _find_water_level() -> float:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * WATER_PROBE,
		global_position + Vector3.DOWN * WATER_PROBE, CityStreamer.WATER_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else 0.0


## A hard landing: the faster the fall, the wider the blast.
func _slam(impact_speed: float) -> void:
	var power := clampf(inverse_lerp(SLAM_SPEED, MAX_FALL_SPEED, impact_speed), 0.0, 1.0)
	Combat.shockwave(global_position, lerpf(5.0, 11.0, power), 100.0, lerpf(14.0, 26.0, power))


func _on_origin_shifted(delta: Vector3) -> void:
	_prev_position -= delta
