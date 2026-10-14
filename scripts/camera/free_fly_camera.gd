class_name FreeFlyCamera
extends Camera3D
## Debug camera for flying around the city.
##
## Click to look around (Esc releases the mouse), WASD to move, Space/E up,
## C/Q down, Shift for a speed boost, mouse wheel to change speed, arrow keys
## to turn. Ctrl is avoided because Ctrl+W closes the browser tab.
## Start pose: ?cam=x,y,z,yaw,pitch (world meters, degrees).

@export var speed := 80.0
@export var min_speed := 5.0
@export var max_speed := 3000.0
@export var boost := 5.0
@export var mouse_sensitivity := 0.0025
@export var turn_speed := 1.5

## Actual movement speed this frame, in m/s.
var current_speed := 0.0

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	add_to_group("floating")
	WorldOrigin.focus = self
	_yaw = rotation.y
	_pitch = rotation.x
	var pose := LaunchOptions.get_floats("cam")
	if pose.size() >= 3:
		global_position = WorldOrigin.to_local(Vector3(pose[0], pose[1], pose[2]))
	if pose.size() >= 5:
		_yaw = deg_to_rad(pose[3])
		_pitch = deg_to_rad(pose[4])
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				speed = minf(speed * 1.25, max_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				speed = maxf(speed / 1.25, min_speed)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_apply_rotation()


func _process(delta: float) -> void:
	var turn := Vector2(_axis(KEY_LEFT, KEY_RIGHT), _axis(KEY_UP, KEY_DOWN))
	if turn != Vector2.ZERO:
		_yaw += turn.x * turn_speed * delta
		_pitch += turn.y * turn_speed * delta
		_apply_rotation()

	var direction := global_basis * Vector3(_axis(KEY_D, KEY_A), 0.0, _axis(KEY_S, KEY_W))
	direction.y += clampf(_axis(KEY_SPACE, KEY_C) + _axis(KEY_E, KEY_Q), -1.0, 1.0)
	current_speed = 0.0
	if direction.length_squared() > 0.0:
		current_speed = speed * (boost if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		global_position += direction.normalized() * current_speed * delta


func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))


func _apply_rotation() -> void:
	_pitch = clampf(_pitch, -1.55, 1.55)
	rotation = Vector3(_pitch, _yaw, 0.0)
