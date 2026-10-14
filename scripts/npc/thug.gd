class_name Thug
extends CharacterBody3D
## A street thug. Hangs around with its gang until a hero comes near, then
## surrounds the hero and attacks (only a couple at a time; see Combat).
## Goes down as a ragdoll and leaves a pool of blood.

enum State { IDLE, CHASE, PUNCH, RECOVER, STAGGER, DOWN }

const RUN_SPEED := 6.5
const ACCELERATION := 30.0
const NOTICE_RANGE := 40.0
const GIVE_UP_RANGE := 90.0
## A hero further above or below than this can't be reached; wait underneath.
const REACH_HEIGHT := 4.0
const ATTACK_RANGE := 1.9
const SURROUND_RADIUS := 1.7
const WAIT_RADIUS := 6.0
const PUNCH_DAMAGE := 6.0
## Seconds from the start of a punch to when it lands; it can be dodged until then.
const PUNCH_HIT_TIME := 0.45
const RECOVER_TIME := 0.4
const STAGGER_TIME := 0.5
const BLOOD_POOL_DELAY := 1.2

var hero: Hero
var health := 100.0
var state := State.IDLE
## Where around the hero this thug tries to stand (radians).
var surround_angle := 0.0

var _timer := 0.0
var _cooldown := 0.0
var _has_attack_slot := false
var _facing := 0.0
var _down_time := 0.0
var _pooled := false
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _ragdoll: PhysicalBoneSimulator3D
## Each ragdoll body's position relative to this node, as of the last tick.
var _bone_offsets: Array[Vector3] = []

@onready var _model: Node3D = $Model


func _ready() -> void:
	add_to_group("floating")
	Combat.register(self)
	WorldOrigin.shifted.connect(_on_origin_shifted)
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	_cooldown = randf_range(0.5, 2.0)
	_facing = randf() * TAU
	_model.rotation.y = _facing
	_play(&"Idle")
	_player.seek(randf() * 2.0)


func _exit_tree() -> void:
	Combat.unregister(self)
	_release_attack_slot()


func setup(target: Hero, gang: int, angle: float) -> void:
	hero = target
	surround_angle = angle
	NpcLook.paint_thug($Model, gang)


func is_down() -> bool:
	return state == State.DOWN


func body_center() -> Vector3:
	return global_position + Vector3.UP


func take_hit(damage: float, push: Vector3, launch: bool) -> void:
	if state == State.DOWN:
		return
	health -= damage
	_release_attack_slot()
	if Combat.effects:
		Combat.effects.blood_burst(body_center(), push.normalized(), 1.5 if launch else 0.6)
	if launch or health <= 0.0:
		_go_down(push if launch else push + Vector3.UP * 3.0)
		return
	state = State.STAGGER
	_timer = STAGGER_TIME
	velocity = push
	_play(&"Hit_Head" if randf() < 0.5 else &"Hit_Chest", 1.0, 0.05, true)


func _physics_process(delta: float) -> void:
	if state == State.DOWN:
		_update_down(delta)
		return
	_timer -= delta
	_cooldown -= delta
	var to_hero := hero.global_position - global_position
	var flat := Vector3(to_hero.x, 0.0, to_hero.z)
	var distance := flat.length()
	var reachable := absf(to_hero.y) < REACH_HEIGHT and hero.can_be_attacked()
	var desired := Vector3.ZERO

	match state:
		State.IDLE:
			if distance < NOTICE_RANGE:
				state = State.CHASE
		State.CHASE:
			_face(flat)
			if distance > GIVE_UP_RANGE:
				state = State.IDLE
			elif reachable and distance < ATTACK_RANGE and _cooldown <= 0.0 and Combat.request_attack():
				_has_attack_slot = true
				state = State.PUNCH
				_timer = PUNCH_HIT_TIME
				_play(&"Punch_Jab" if randf() < 0.5 else &"Punch_Cross", 1.3, 0.1, true)
			else:
				desired = _surround_velocity(reachable)
		State.PUNCH:
			_face(flat)
			if _timer <= 0.0:
				_land_punch(flat, distance, reachable)
				state = State.RECOVER
				_timer = RECOVER_TIME
		State.RECOVER:
			if _timer <= 0.0:
				state = State.CHASE
				_cooldown = randf_range(1.2, 2.6)
				_release_attack_slot()
		State.STAGGER:
			if _timer <= 0.0:
				state = State.CHASE

	# Steer toward the desired velocity; staggered thugs slide to a stop.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(desired, (8.0 if state == State.STAGGER else ACCELERATION) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
	else:
		velocity.y -= Hero.GRAVITY * delta
	move_and_slide()
	if state == State.IDLE or state == State.CHASE:
		_animate_movement(horizontal.length())
	_model.rotation.y = lerp_angle(_model.rotation.y, _facing, 1.0 - exp(-10.0 * delta))


## Run to this thug's spot around the hero, or a wider ring when the hero is out of reach.
func _surround_velocity(reachable: bool) -> Vector3:
	var radius := SURROUND_RADIUS if reachable else WAIT_RADIUS
	var spot := hero.global_position + Vector3(sin(surround_angle), 0.0, cos(surround_angle)) * radius
	var to_spot := spot - global_position
	to_spot.y = 0.0
	if to_spot.length() < 0.3:
		return Vector3.ZERO
	return to_spot.normalized() * minf(RUN_SPEED, to_spot.length() * 4.0)


func _land_punch(flat: Vector3, distance: float, reachable: bool) -> void:
	var forward := Vector3(-sin(_facing), 0.0, -cos(_facing))
	if not reachable or distance > ATTACK_RANGE + 0.4 or forward.dot(flat.normalized()) < 0.5:
		return  # the hero got out of the way
	# Push along the ground only: lifting the hero would cancel a super jump charge.
	Combat.hurt_hero(hero, PUNCH_DAMAGE, forward * 5.0)


func _go_down(launch: Vector3) -> void:
	state = State.DOWN
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_player.pause()
	_ragdoll = Ragdoll.start(_skeleton, launch)
	Combat.on_thug_down(self)


func _update_down(delta: float) -> void:
	_down_time += delta
	_bone_offsets.clear()
	for bone in _ragdoll.get_children():
		_bone_offsets.append((bone as Node3D).global_position - global_position)
	if not _pooled and _down_time > BLOOD_POOL_DELAY and Combat.effects:
		_pooled = true
		var hips := _ragdoll.get_node_or_null("DEF-hips") as Node3D
		Combat.effects.blood_pool(hips.global_position if hips else global_position)


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		_facing = atan2(-direction.x, -direction.z)


func _animate_movement(speed: float) -> void:
	if speed < 0.3:
		_play(&"Idle")
	elif speed < 3.5:
		_play(&"Walk", speed / 1.6)
	else:
		_play(&"Jog_Fwd", speed / 4.5)


func _play(animation: StringName, speed := 1.0, blend := 0.2, restart := false) -> void:
	if restart or _player.assigned_animation != animation:
		_player.play(animation, blend)
		if restart:
			_player.seek(0.0, true)
	_player.speed_scale = speed


func _release_attack_slot() -> void:
	if _has_attack_slot:
		_has_attack_slot = false
		Combat.release_attack()


func _on_origin_shifted(delta: Vector3) -> void:
	# The thug node moves with the "floating" group. Ragdoll bodies are simulated
	# in world space, so move any that didn't follow along.
	if _ragdoll == null:
		return
	var bones := _ragdoll.get_children()
	for i in mini(bones.size(), _bone_offsets.size()):
		var body := bones[i] as PhysicalBone3D
		if (body.global_position - global_position).distance_to(_bone_offsets[i]) > delta.length() * 0.5:
			body.global_position -= delta
