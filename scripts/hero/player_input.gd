class_name PlayerInput
extends Node
## Feeds keyboard, mouse and gamepad input to the local Hero every physics tick.
## Runs before the hero (negative physics priority).

@export var hero: Hero
@export var camera_rig: ThirdPersonCamera

var enabled := true


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	var input := hero.input
	if not enabled:
		input.clear()
		return
	input.stick = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input.move = Basis(Vector3.UP, camera_rig.yaw) * Vector3(input.stick.x, 0.0, input.stick.y)
	input.aim = camera_rig.aim_direction()
	input.vertical = Input.get_axis("descend", "jump")
	input.jump_held = Input.is_action_pressed("jump")
	input.sprint_held = Input.is_action_pressed("sprint")
	input.web_held = Input.is_action_pressed("web")
	input.attack_held = Input.is_action_pressed("attack")
	if Input.is_action_just_pressed("fly_toggle"):
		input.fly_toggle_pressed = true
