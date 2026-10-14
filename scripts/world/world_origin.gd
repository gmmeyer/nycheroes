extends Node
## Floating origin for the 1:1 scale city (autoload "WorldOrigin").
##
## Godot uses 32-bit floats, so things far from (0, 0, 0) start to jitter.
## When the focus node drifts more than SHIFT_DISTANCE from the origin, every
## node in the "floating" group is moved back by the same amount and `offset`
## grows by it. World position = local position + offset.

signal shifted(delta: Vector3)

const SHIFT_DISTANCE := 1500.0
## Shifts are whole multiples of this, so tile positions stay exact.
const SHIFT_STEP := 500.0

var offset := Vector3.ZERO
var focus: Node3D


## Runs before other physics so bodies are moved between ticks, not mid-step.
func _physics_process(_delta: float) -> void:
	if focus == null:
		return
	var p := focus.global_position
	if Vector2(p.x, p.z).length() < SHIFT_DISTANCE:
		return
	shift(Vector3(snappedf(p.x, SHIFT_STEP), 0.0, snappedf(p.z, SHIFT_STEP)))


## Moves the scene origin by `delta`: everything floating moves back by it.
func shift(delta: Vector3) -> void:
	offset += delta
	for node in get_tree().get_nodes_in_group("floating"):
		(node as Node3D).global_position -= delta
	shifted.emit(delta)


func to_world(local: Vector3) -> Vector3:
	return local + offset


func to_local(world: Vector3) -> Vector3:
	return world - offset
