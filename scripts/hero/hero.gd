class_name Hero
extends CharacterBody3D
## A superhero that runs, super-speeds, super-jumps, flies and web-swings.
##
## Movement modes are child HeroMode nodes (OnFoot, Flight, Swing); the active
## one drives `velocity` from `input` each physics tick. Everything another
## player would need to see (mode, velocity, facing, web anchor) is plain state,
## so it can be synced over the network later.

signal mode_changed(mode_name: StringName)
## Emitted on touching down, with the downward speed just before impact.
signal landed(impact_speed: float)

const GRAVITY := 30.0
const MAX_FALL_SPEED := 95.0
const WORLD_LAYER := 1
## Below this height the hero is in the water (sea level is 0, land is 2 m up).
const WATER_LINE := -0.6

var input := HeroInput.new()
## Yaw the hero faces, in radians (0 = north, which is -Z).
var facing := 0.0
var mode: HeroMode
## Physics waits until the ground under the spawn point has loaded.
var frozen := true

# Input edges for this tick, worked out from `input`.
var jump_pressed := false
var web_pressed := false

var _modes := {}
var _prev_jump := false
var _prev_web := false
var _prev_position := Vector3.ZERO
var _was_on_floor := false


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
	_prev_jump = input.jump_held
	_prev_web = input.web_held

	var fall_speed := -velocity.y
	var next := mode.physics_update(delta)
	input.fly_toggle_pressed = false
	if next != &"" and next != mode.name:
		set_mode(next)

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
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


func is_in_water() -> bool:
	return global_position.y < WATER_LINE


## Turns `facing` toward a horizontal direction, at most max_step radians.
func face_toward(direction: Vector3, max_step := INF) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	facing = rotate_toward(facing, atan2(-direction.x, -direction.z), max_step)


func _on_origin_shifted(delta: Vector3) -> void:
	_prev_position -= delta
