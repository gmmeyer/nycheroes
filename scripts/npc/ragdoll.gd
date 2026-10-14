class_name Ragdoll
extends RefCounted
## Turns the mannequin (Quaternius UAL skeleton) into a physics ragdoll: builds
## capsule bodies for the main bones, joins them, and lets physics take over
## from the current animation pose.

## [bone, bone the capsule reaches toward ("" = head, fixed length), radius, mass,
##  joint swing limit, joint twist limit (degrees)]. The first part is the root.
const PARTS := [
	["DEF-hips", "DEF-spine.002", 0.14, 10.0, 0.0, 0.0],
	["DEF-spine.002", "DEF-neck", 0.15, 10.0, 25.0, 20.0],
	["DEF-head", "", 0.11, 4.0, 40.0, 30.0],
	["DEF-upper_arm.L", "DEF-forearm.L", 0.055, 2.5, 70.0, 30.0],
	["DEF-forearm.L", "DEF-hand.L", 0.045, 1.5, 70.0, 10.0],
	["DEF-upper_arm.R", "DEF-forearm.R", 0.055, 2.5, 70.0, 30.0],
	["DEF-forearm.R", "DEF-hand.R", 0.045, 1.5, 70.0, 10.0],
	["DEF-thigh.L", "DEF-shin.L", 0.075, 6.0, 60.0, 15.0],
	["DEF-shin.L", "DEF-foot.L", 0.055, 3.5, 70.0, 10.0],
	["DEF-thigh.R", "DEF-shin.R", 0.075, 6.0, 60.0, 15.0],
	["DEF-shin.R", "DEF-foot.R", 0.055, 3.5, 70.0, 10.0],
]
const HEAD_LENGTH := 0.24


## Builds the ragdoll under `skeleton`, starts it from the current pose and
## throws it with `velocity`. Returns the simulator node.
static func start(skeleton: Skeleton3D, velocity: Vector3, spin := 6.0) -> PhysicalBoneSimulator3D:
	var simulator := PhysicalBoneSimulator3D.new()
	skeleton.add_child(simulator)
	for part in PARTS:
		simulator.add_child(_make_bone(skeleton, part))
	simulator.physical_bones_start_simulation()
	for bone in simulator.get_children():
		var body := bone as PhysicalBone3D
		body.linear_velocity = velocity * randf_range(0.85, 1.15)
		body.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spin
	return simulator


static func _make_bone(skeleton: Skeleton3D, part: Array) -> PhysicalBone3D:
	var bone_index := skeleton.find_bone(part[0])
	var rest := skeleton.get_bone_global_rest(bone_index)
	# Where the capsule ends, in the bone's own space (bones point along +Y).
	var tip := Vector3(0.0, HEAD_LENGTH, 0.0)
	if part[1] != "":
		tip = rest.affine_inverse() * skeleton.get_bone_global_rest(skeleton.find_bone(part[1])).origin
	var half := tip.length() * 0.5
	var radius: float = part[2]

	# Same layout as the editor's "Create Physical Skeleton": the body sits
	# halfway along the bone, looking down it, with the joint at the bone's head.
	var up := Vector3.UP if not Vector3.UP.cross(tip).is_zero_approx() else Vector3.BACK
	var basis := Basis.looking_at(tip, up)
	var body := PhysicalBone3D.new()
	body.name = part[0]
	body.bone_name = part[0]
	body.body_offset = Transform3D(basis, basis * Vector3(0.0, 0.0, -half))
	body.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, half))
	body.mass = part[3]
	body.friction = 0.8
	body.linear_damp = 0.1
	body.angular_damp = 0.8
	body.collision_layer = Combat.RAGDOLL_LAYER
	body.collision_mask = Combat.WORLD_LAYER
	if part[4] > 0.0:
		body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		body.set("joint_constraints/swing_span", part[4])
		body.set("joint_constraints/twist_span", part[5])

	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(half * 2.0, radius * 2.0 + 0.01)
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	# Capsules run along their Y axis; turn it to run down the bone (-Z here).
	shape.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3.ZERO)
	body.add_child(shape)
	return body
