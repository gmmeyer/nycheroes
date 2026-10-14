class_name Hero
extends CharacterBody3D
## A superhero that runs, super-speeds, super-jumps, flies, web-swings and fights.
##
## Movement modes are child HeroMode nodes (OnFoot, Flight, Swing, Melee, Dive,
## KnockedOut); the active one drives `velocity` from `input` each physics tick.
## Everything another player would need to see (mode, velocity, facing, web
## anchor, health) is plain state, so it can be synced over the network later.

signal mode_changed(mode_name: StringName)
## Emitted on touching down, with the downward speed just before impact.
signal landed(impact_speed: float)
signal hurt(damage: float)

const GRAVITY := 30.0
const MAX_FALL_SPEED := 95.0
const WORLD_LAYER := 1
## Below this height the hero is in the water (sea level is 0, land is 2 m up).
const WATER_LINE := -0.6
const MAX_HEALTH := 100.0
## Health comes back after this long without being hit.
const REGEN_DELAY := 4.0
const REGEN_RATE := 15.0
## Landing faster than this slams the ground, hurling thugs nearby.
const SLAM_SPEED := 35.0
## How long a hit staggers the hero.
const HURT_TIME := 0.35

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


func _ready() -> void:
	add_to_group("floating")
	WorldOrigin.shifted.connect(_on_origin_shifted)
	for child in get_children():
		if child is HeroMode:
			child.hero = self
			_modes[child.name] = child
	set_mode(&"OnFoot")
	_prev_position = global_position


func _physics_process(delta: float) -> void:
	_prev_position = global_position
	if frozen:
		return
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

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
		if fall_speed >= SLAM_SPEED or slam_pending:
			_slam(maxf(fall_speed, 60.0) if slam_pending else fall_speed)
	if on_floor:
		slam_pending = false
	_was_on_floor = on_floor


func set_mode(mode_name: StringName) -> void:
	var previous: StringName = mode.name if mode else &""
	if mode:
		mode.exit()
	mode = _modes[mode_name]
	mode.enter(previous)
	mode_changed.emit(mode_name)


func get_mode(mode_name: StringName) -> HeroMode:
	return _modes[mode_name]


## Position to draw at: blended between physics ticks so motion stays smooth
## at any frame rate.
func get_visual_position() -> Vector3:
	return _prev_position.lerp(global_position, Engine.get_physics_interpolation_fraction())


func world_position() -> Vector3:
	return WorldOrigin.to_world(global_position)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func is_in_water() -> bool:
	return global_position.y < WATER_LINE


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


## A hard landing: the faster the fall, the wider the blast.
func _slam(impact_speed: float) -> void:
	var power := clampf(inverse_lerp(SLAM_SPEED, MAX_FALL_SPEED, impact_speed), 0.0, 1.0)
	Combat.shockwave(global_position, lerpf(5.0, 11.0, power), 100.0, lerpf(14.0, 26.0, power))


func _on_origin_shifted(delta: Vector3) -> void:
	_prev_position -= delta
