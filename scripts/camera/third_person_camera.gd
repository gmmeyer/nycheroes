class_name ThirdPersonCamera
extends Node3D
## Orbit camera that follows a Hero. Click to capture the mouse (the options
## menu releases it, and so does Esc in the browser), then move the mouse or
## the right stick to look around. The options menu sets the look speed
## (look_mouse, times mouse_sensitivity and stick_sensitivity) and whether up
## and down are swapped (invert_y; TouchControls follows both too). Pulls
## back and widens the view at speed, and shakes on hard landings.

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
## The options menu's look speed and invert_y (-1 when swapped).
var _look_scale := 1.0
var _look_y := 1.0

@onready var spring_arm: SpringArm3D = $SpringArm
@onready var camera: Camera3D = $SpringArm/Camera


func _ready() -> void:
	spring_arm.add_excluded_object(target.get_rid())
	target.landed.connect(_on_target_landed)
	Combat.impact.connect(_on_impact)
	_read_look_settings()
	Settings.changed.connect(func(key: String) -> void:
		if key in ["look_mouse", "invert_y"]:
			_read_look_settings())


## The options menu's look speed for a mouse (or fingers: `touch`), times the usual.
static func look_speed(touch := false) -> float:
	return clampf(float(Settings.get_value("look_touch" if touch else "look_mouse", 1.0)), 0.1, 5.0)


## -1 when the options menu swaps looking up and down, else 1.
static func look_y_sign() -> float:
	return -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0


## Unit vector the camera looks along (without shake or shoulder offset).
func aim_direction() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var turn := mouse_sensitivity * _look_scale
		yaw -= event.relative.x * turn
		pitch = clampf(pitch - event.relative.y * turn * _look_y, -1.4, 1.2)


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var turn := stick_sensitivity * _look_scale * delta
	yaw -= stick.x * turn
	pitch = clampf(pitch - stick.y * turn * _look_y, -1.4, 1.2)

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


func _read_look_settings() -> void:
	_look_scale = look_speed()
	_look_y = look_y_sign()


func _on_target_landed(impact_speed: float) -> void:
	if impact_speed > HeroAnimator.HARD_LANDING_SPEED:
		_shake = maxf(_shake, clampf(impact_speed / 150.0, 0.0, 0.5))


func _on_impact(at: Vector3, strength: float) -> void:
	var falloff := clampf(1.0 - at.distance_to(global_position) / 60.0, 0.0, 1.0)
	_shake = maxf(_shake, strength * 0.4 * falloff)
