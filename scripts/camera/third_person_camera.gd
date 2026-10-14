class_name ThirdPersonCamera
extends Node3D
## Orbit camera that follows a Hero. Click to capture the mouse (Esc releases
## it), then move the mouse or the right stick to look around. Pulls back and
## widens the view at speed, and shakes on hard landings.

@export var target: Hero
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 2.5
## Look-at height above the hero's feet, and how far right of the hero to sit.
@export var height := 1.6
@export var shoulder_offset := 0.5
@export var base_fov := 70.0
@export var max_fov := 90.0

var yaw := 0.0
var pitch := -0.15

var _distance := 4.5
var _shake := 0.0

@onready var spring_arm: SpringArm3D = $SpringArm
@onready var camera: Camera3D = $SpringArm/Camera


func _ready() -> void:
	spring_arm.add_excluded_object(target.get_rid())
	target.landed.connect(_on_target_landed)
	Combat.impact.connect(_on_impact)


## Unit vector the camera looks along (without shake or shoulder offset).
func aim_direction() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.4, 1.2)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= stick.x * stick_sensitivity * delta
	pitch = clampf(pitch - stick.y * stick_sensitivity * delta, -1.4, 1.2)

	var speed := target.velocity.length()
	var distance := 4.5
	match target.mode.name:
		&"Flight":
			distance = 7.0
		&"Swing":
			distance = 7.5
	distance += clampf(speed / 60.0, 0.0, 1.0) * 2.0
	_distance = lerpf(_distance, distance, 1.0 - exp(-3.0 * delta))

	global_position = target.get_visual_position() + Vector3.UP * height
	rotation = Vector3(pitch, yaw, 0.0)
	spring_arm.spring_length = _distance
	spring_arm.position = Vector3(shoulder_offset, 0.0, 0.0)
	var fov := lerpf(base_fov, max_fov, clampf((speed - 10.0) / 70.0, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-4.0 * delta))

	_shake = maxf(_shake - delta, 0.0)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * _shake


func _on_target_landed(impact_speed: float) -> void:
	if impact_speed > HeroAnimator.HARD_LANDING_SPEED:
		_shake = maxf(_shake, clampf(impact_speed / 150.0, 0.0, 0.5))


func _on_impact(at: Vector3, strength: float) -> void:
	var falloff := clampf(1.0 - at.distance_to(global_position) / 60.0, 0.0, 1.0)
	_shake = maxf(_shake, strength * 0.4 * falloff)
