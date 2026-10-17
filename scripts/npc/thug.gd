class_name Thug
extends CharacterBody3D
## A street thug. Hangs around with its gang until a hero comes near, then
## surrounds that hero and attacks (only a couple at a time; see Combat).
## Goes down as a ragdoll and leaves a pool of blood.
##
## In co-op each thug runs in one game: the game of the player who put its
## gang down (see EncounterDirector). In the other players' games it's a copy
## (`puppet`) that follows that game's updates; hits on a copy show at once and
## go to that game to be applied (see Combat). When that player leaves, the
## host's game takes its copies over (take_over).

enum State { IDLE, CHASE, PUNCH, RECOVER, STAGGER, DOWN }

## Animations, in the order they're numbered when sent to other players.
const ANIMATIONS: Array[StringName] = [&"Idle", &"Walk", &"Jog_Fwd", &"Punch_Jab", &"Punch_Cross", &"Hit_Head", &"Hit_Chest"]
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
## Further from the camera than this, stop animating (too small to notice, and
## each animated character costs GPU time in browsers; see SkinWarmup).
const ANIMATE_DISTANCE := 60.0

## The hero this thug is after (or, while idle, the one its gang was put near).
var hero: Hero
var health := 100.0
var state := State.IDLE
var gang := 0
## Where around the hero this thug tries to stand (radians).
var surround_angle := 0.0
## The same number in every player's game (given out by the game running it).
var net_id := 0
## A copy of a thug another player's game runs (set before adding to the scene).
var puppet := false
## Copies: the player whose game runs this thug (its updates come from there,
## and our hits on it go there).
var run_by := 0
## Holds still while set: a thug taken over where our game hasn't loaded the
## ground yet (see EncounterDirector).
var frozen := false
## What's playing, for copies: index into ANIMATIONS, speed, and how many
## times an animation has restarted (so copies restart it too).
var anim_index := 0
var anim_speed := 1.0
var anim_restarts := 0

var _timer := 0.0
var _cooldown := 0.0
var _attack_slot: Hero
var _facing := 0.0
var _down_time := 0.0
var _pooled := false
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _ragdoll: PhysicalBoneSimulator3D
## Each ragdoll body's position relative to this node, as of the last tick.
var _bone_offsets: Array[Vector3] = []
# Copies only: the running game's updates, and until when (msec) a hit shown here
# plays out before they take over the animation again.
var _snapshots: SnapshotBuffer
var _shown_restarts := -1
var _local_animation_until := 0
var _detail_check := randf() * 0.5

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
	SkinWarmup.add_to(_model)
	if puppet:
		_snapshots = SnapshotBuffer.new()


func _exit_tree() -> void:
	Combat.unregister(self)
	_release_attack_slot()


func setup(target: Hero, gang_index: int, angle: float) -> void:
	hero = target
	gang = gang_index
	surround_angle = angle
	NpcLook.paint_thug($Model, gang, net_id)


## Sets up a thug as another game described it: a copy from what the game
## running it sent when it came into range, or one handed over to us (the host)
## from a player who left.
func setup_described(gang_index: int, facing: float, health_left: float, down: bool) -> void:
	gang = gang_index
	_facing = facing
	_model.rotation.y = facing
	health = health_left
	NpcLook.paint_thug($Model, gang, net_id)
	if down:
		go_down(Vector3.ZERO, false)


## Our game runs this thug from now on: the player whose game ran it left, and
## we're the host (it was our copy, or another player's handed over). It picks
## its own fight.
func take_over() -> void:
	puppet = false
	run_by = 0
	_snapshots = null
	if state != State.DOWN:
		state = State.IDLE
		velocity = Vector3.ZERO
		surround_angle = randf() * TAU
		_cooldown = randf_range(0.5, 1.5)


## Copies only: player `id`'s game runs this thug now (it took it over), and
## its updates are timed by that game's clock.
func follow_new_runner(id: int) -> void:
	if puppet:
		run_by = id
		_snapshots = SnapshotBuffer.new()
		_shown_restarts = -1


func is_down() -> bool:
	return state == State.DOWN


func facing() -> float:
	return _facing


func body_center() -> Vector3:
	return global_position + Vector3.UP


## Where the thug is on the ground (scene space): under its feet, or where its
## body lies once it's down (the ragdoll may have flown).
func ground_position() -> Vector3:
	if _ragdoll:
		var hips := _ragdoll.get_node_or_null("DEF-hips") as Node3D
		if hips:
			return Vector3(hips.global_position.x, global_position.y, hips.global_position.z)
	return global_position


func take_hit(damage: float, push: Vector3, launch: bool) -> void:
	if state == State.DOWN:
		return
	health -= damage
	_release_attack_slot()
	if Combat.effects:
		Combat.effects.blood_burst(body_center(), push.normalized(), 1.5 if launch else 0.6)
	GameAudio.play(&"punch_heavy" if launch else &"punch", body_center())
	if launch or health <= 0.0:
		go_down(push if launch else push + Vector3.UP * 3.0)
		return
	_play(&"Hit_Head" if randf() < 0.5 else &"Hit_Chest", 1.0, 0.05, true)
	if randf() < 0.5:
		GameAudio.play(&"thug_hurt", body_center())
	if puppet:
		_local_animation_until = Time.get_ticks_msec() + int(STAGGER_TIME * 1000.0)
		return
	state = State.STAGGER
	_timer = STAGGER_TIME
	velocity = push


## Goes down as a ragdoll thrown by `launch`. `counts` is false for bodies
## that were already down before this game heard of them.
func go_down(launch: Vector3, counts := true) -> void:
	state = State.DOWN
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_release_attack_slot()
	_player.pause()
	_ragdoll = Ragdoll.start(_skeleton, launch)
	if counts:
		Combat.on_thug_down(self, launch)
		GameAudio.play(&"thug_down", body_center())
		# The body hits the ground about when a throw upward this fast comes back down.
		var rise := maxf(launch.y, 0.0)
		GameAudio.play_later(&"body_fall", (rise + sqrt(rise * rise + 20.0)) / 9.8, self)


func _process(delta: float) -> void:
	_detail_check -= delta
	if _detail_check > 0.0:
		return
	_detail_check = 0.5
	var camera := get_viewport().get_camera_3d()
	if camera:
		_player.active = global_position.distance_to(camera.global_position) < ANIMATE_DISTANCE


## A copy's update from the game running it (world position).
func push_snapshot(sender_msec: float, world_position: Vector3, facing_angle: float, health_left: float,
		animation: int, speed: float, restarts: int) -> void:
	_snapshots.push(sender_msec, [world_position, facing_angle, health_left, animation, speed, restarts])


func _physics_process(delta: float) -> void:
	if state == State.DOWN:
		_update_down(delta)
		return
	if puppet:
		_follow_updates(delta)
		return
	if frozen:
		return
	_timer -= delta
	_cooldown -= delta
	if state == State.IDLE:
		var target := _nearest_hero()
		if target:
			hero = target
			state = State.CHASE
			if randf() < 0.5:
				GameAudio.play(&"thug_shout", body_center())  # (one of a gang at a time)
	elif not is_instance_valid(hero):
		hero = null
		_release_attack_slot()
		state = State.IDLE

	var desired := Vector3.ZERO
	if state != State.IDLE:
		var to_hero := hero.global_position - global_position
		var flat := Vector3(to_hero.x, 0.0, to_hero.z)
		var distance := flat.length()
		var reachable := absf(to_hero.y) < REACH_HEIGHT and hero.can_be_attacked()
		match state:
			State.CHASE:
				_face(flat)
				if distance > GIVE_UP_RANGE:
					state = State.IDLE
				elif reachable and distance < ATTACK_RANGE and _cooldown <= 0.0 and Combat.request_attack(hero):
					_attack_slot = hero
					state = State.PUNCH
					_timer = PUNCH_HIT_TIME
					_play(&"Punch_Jab" if randf() < 0.5 else &"Punch_Cross", 1.3, 0.1, true)
					_punch_sound()
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
	var intended := velocity
	move_and_slide()
	LedgeClimb.climb(self, intended, delta)
	if state == State.IDLE or state == State.CHASE:
		_animate_movement(horizontal.length())
	_model.rotation.y = lerp_angle(_model.rotation.y, _facing, 1.0 - exp(-10.0 * delta))


## The closest hero within notice range that can be attacked, or null.
func _nearest_hero() -> Hero:
	var best: Hero = null
	var best_distance := NOTICE_RANGE
	for candidate in Combat.heroes:
		if not candidate.can_be_attacked():
			continue
		var offset := candidate.global_position - global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


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


## A copy follows the running game's updates, drawn a little in the past so it
## moves smoothly between them.
func _follow_updates(delta: float) -> void:
	if _snapshots.is_empty():
		return
	var sample := _snapshots.sample()
	var older: Array = sample[0]
	var newer: Array = sample[1]
	var weight: float = sample[2]
	global_position = WorldOrigin.to_local((older[0] as Vector3).lerp(newer[0], weight))
	_facing = lerp_angle(older[1], newer[1], weight)
	health = minf(health, newer[2])
	var restarts: int = newer[5]
	if Time.get_ticks_msec() >= _local_animation_until:
		var restart := _shown_restarts >= 0 and restarts != _shown_restarts
		_play(ANIMATIONS[clampi(newer[3], 0, ANIMATIONS.size() - 1)], newer[4], 0.05 if restart else 0.2, restart)
		if restart and (newer[3] == 3 or newer[3] == 4):  # Punch_Jab, Punch_Cross
			_punch_sound()
	_shown_restarts = restarts
	_model.rotation.y = lerp_angle(_model.rotation.y, _facing, 1.0 - exp(-10.0 * delta))


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
			anim_restarts += 1
	_player.speed_scale = speed
	anim_index = maxi(ANIMATIONS.find(animation), 0)
	anim_speed = speed


## A punch swinging: a whoosh, and now and then a grunt.
func _punch_sound() -> void:
	GameAudio.play(&"whoosh_punch", body_center(), -4.0, 0.85)
	if randf() < 0.35:
		GameAudio.play(&"thug_effort", body_center())


func _release_attack_slot() -> void:
	if is_instance_valid(_attack_slot):
		Combat.release_attack(_attack_slot)
	_attack_slot = null


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
