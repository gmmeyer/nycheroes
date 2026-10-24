class_name Pedestrian
extends Node3D
## A bystander walking a sidewalk lane. Runs from fights, slams and heroes
## tearing past, and can't be hurt. Its position is kept in world space (see
## WorldOrigin) and turned into scene space every frame, so it isn't in the
## "floating" group.

const RUN_SPEED := 5.5
const CALM_DOWN_TIME := 9.0
## Step aside when a hero comes this close.
const DODGE_DISTANCE := 2.5
const MAX_SIDE_STEP := 2.5
## Running from danger, it keeps to its lane while the lane leads away (at
## least LEAVE_GAIN m further from the danger over the next LOOK_ALONG m of
## it). Where it doesn't (it ends, or turns back), it runs on off the lane:
## every STEER_INTERVAL s it looks FLEE_LOOK m ahead for walls and benches
## (a ray at KNEE height) and for a curb or step (ground more than
## STEP_HEIGHT higher or lower), and takes the first clear way of: straight
## away from the danger give or take its own FAN_OUT (so a crowd spreads),
## then FLEE_TURNS to either side of straight away (its own side first), up
## to square to it, but never doubling back on the way it's going: in a
## corner it would go back and forth. Where none is clear it stops, until the
## danger moves. It drops a crumb every TRAIL_SPACING m, and once calm walks
## back along them onto its lane. (Kept to its lane, it turned around at the
## end and back again every frame and sprinted in place: whole crowds of
## them at the ends of Times Square's plaza lanes.)
const LOOK_ALONG := 2.0
const LEAVE_GAIN := 0.5
const STEER_INTERVAL := 0.15
const FLEE_LOOK := 1.2
const KNEE := 0.3
const STEP_HEIGHT := 0.12
const FLEE_TURNS: Array[float] = [0.4, 0.8, 1.2, PI / 2.0]
const FAN_OUT := 0.25
const TRAIL_SPACING := 0.5
## Danger this far from the last is somewhere else (a cornered one looks again).
const THREAT_MOVED := 2.0
## Further from the camera than this, pose only MID_POSE_RATE times a second,
## and past SLOW_POSE_DISTANCE only FAR_POSE_RATE times (each new pose costs a
## skinning pass, see SkinWarmup; busy streets have dozens in view), at times
## of their own so they spread out ...
const MID_POSE_DISTANCE := 8.0
const MID_POSE_RATE := 30.0
const SLOW_POSE_DISTANCE := 25.0
const FAR_POSE_RATE := 12.0
## ... further than this, stop animating (too small to notice) ...
const ANIMATE_DISTANCE := 60.0
## ... and further than this, don't draw at all; nor behind a building (in
## the camera's view, checked again every HIDDEN_CHECK s while so: each one
## drawn is a few draw calls, and the crowd's spots ahead of the camera are
## often on the next street).
const VISIBLE_DISTANCE := 120.0
const DETAIL_CHECK := 0.5
const HIDDEN_CHECK := 0.2

var world_position := Vector3.ZERO
var hero: Hero

var _lane: PackedVector3Array
var _lengths := PackedFloat32Array()  # distance along the lane at each point
var _along := 0.0
var _segment := 0
var _heading := 1.0
var _side := 0.0
var _walk_speed := 1.4
var _panic := 0.0
var _threat := Vector3.ZERO
var _pause := 0.0
var _off_lane := false
## Where it's been since leaving its lane (world space, from the spot it left).
var _trail := PackedVector3Array()
## The way it's going off its lane (level, unit; zero while cornered).
var _run := Vector3.ZERO
var _steer_wait := 0.0
var _cornered := false
var _fan := randf_range(-FAN_OUT, FAN_OUT)
var _facing := 0.0
var _player: AnimationPlayer
var _detail_check := randf() * DETAIL_CHECK
var _warmup: SkinWarmup
var _slow_pose := false
## Poses a second while posing slowly.
var _pose_rate := FAR_POSE_RATE
var _pose_wait := randf() / FAR_POSE_RATE
var _pose_time := 0.0

@onready var _model: Node3D = $Model


func _ready() -> void:
	add_to_group("pedestrians")
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play(&"Walk", 1.0)
	_player.seek(randf() * 1.3)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warmup = SkinWarmup.add_to(_model, &"Idle")


## Places the pedestrian on `lane` (world-space polyline), `t` of the way along `segment`.
func setup(target: Hero, lane: PackedVector3Array, segment: int, t: float) -> void:
	hero = target
	_lane = lane
	_lengths.resize(lane.size())
	_lengths[0] = 0.0
	for i in range(1, lane.size()):
		_lengths[i] = _lengths[i - 1] + lane[i - 1].distance_to(lane[i])
	_segment = segment
	_along = _lengths[segment] + lane[segment].distance_to(lane[segment + 1]) * t
	_heading = 1.0 if randf() < 0.5 else -1.0
	_side = randf_range(-0.8, 0.8)
	_walk_speed = randf_range(1.1, 1.6)
	NpcLook.paint_pedestrian(_model)
	_move(0.0)
	_facing = _travel_yaw()
	_model.rotation.y = _facing


func is_panicking() -> bool:
	return _panic > 0.0


## Something dangerous happened at `from_world`: run the other way.
func scare(from_world: Vector3) -> void:
	if _panic <= 0.0 and visible and randf() < 0.3:
		GameAudio.play(&"scream", global_position + Vector3.UP * 1.6)  # (one in a few seconds, at most)
	_panic = CALM_DOWN_TIME + randf() * 3.0
	if from_world.distance_to(_threat) > THREAT_MOVED:
		_cornered = false
	_threat = from_world
	_pause = 0.0


func _process(delta: float) -> void:
	var speed := _walk(delta)
	var from_hero := world_position - hero.world_position()
	from_hero.y = 0.0
	if from_hero.length() < DODGE_DISTANCE and not _off_lane:
		var across := _across()
		_side = clampf(_side + signf(from_hero.dot(across) + 0.01) * 3.0 * delta, -MAX_SIDE_STEP, MAX_SIDE_STEP)

	if speed > 0.0:
		_facing = lerp_angle(_facing, _travel_yaw(), 1.0 - exp(-8.0 * delta))
	_model.rotation.y = _facing
	_animate(speed)
	if _slow_pose:
		_pose_time += delta
		_pose_wait -= delta
		if _pose_wait <= 0.0:
			_pose_wait += 1.0 / _pose_rate
			if _player.active and _player.can_process():
				_player.advance(_pose_time)
			_pose_time = 0.0
	_update_detail(delta)


## Walks, or runs from danger, for `delta` s. Returns the speed (m/s).
func _walk(delta: float) -> float:
	var speed := 0.0
	if _panic > 0.0:
		_panic -= delta
		speed = RUN_SPEED
		if not _off_lane and not _flee_along_lane():
			_off_lane = true
			_trail = PackedVector3Array([world_position])
			_run = Vector3.ZERO
			_steer_wait = 0.0
			_cornered = false
	elif _pause > 0.0:
		_pause -= delta
	else:
		speed = _walk_speed
		if randf() < delta * 0.02:
			_pause = randf_range(2.0, 6.0)  # stop for a moment now and then
	if is_instance_valid(_warmup) and _warmup.holding:
		speed = 0.0  # stand still while the pose is held (see SkinWarmup)
	if _off_lane:
		return _walk_off_lane(speed, delta)
	_move(speed * delta)
	return speed


## Running from danger on its lane: turns whichever way along it leads
## further away, and returns whether that way leads away enough to take.
func _flee_along_lane() -> bool:
	var here := _from_threat(_along)
	var ahead := _from_threat(_along + LOOK_ALONG * _heading)
	var behind := _from_threat(_along - LOOK_ALONG * _heading)
	if behind > ahead:
		_heading = -_heading
		ahead = behind
	return ahead > here + LEAVE_GAIN


## Off its lane, for `delta` s at `speed`: running from danger, or once calm
## walking back the way it came and onto its lane. Returns the speed (m/s).
func _walk_off_lane(speed: float, delta: float) -> float:
	if speed <= 0.0:
		return 0.0
	if _panic > 0.0:
		_steer_wait -= delta
		if _steer_wait <= 0.0:
			_steer_wait = STEER_INTERVAL
			_steer()
		if _run == Vector3.ZERO:
			return 0.0  # cornered
		world_position += _run * speed * delta
		if world_position.distance_to(_trail[_trail.size() - 1]) >= TRAIL_SPACING:
			_trail.append(world_position)
	else:
		var step := speed * delta
		while step > 0.0 and not _trail.is_empty():
			var to := _trail[_trail.size() - 1] - world_position
			var length := to.length()
			if length > step:
				world_position += to * (step / length)
				_run = Vector3(to.x, 0.0, to.z).normalized()
				break
			world_position = _trail[_trail.size() - 1]
			_trail.remove_at(_trail.size() - 1)
			step -= length
		if _trail.is_empty():
			_off_lane = false  # back where it left the lane
			_move(0.0)
			return speed
	position = WorldOrigin.to_local(world_position)
	return speed


## Picks the way to run off the lane (see FLEE_TURNS), and stands it on the ground.
func _steer() -> void:
	if _cornered:
		return
	var space := get_world_3d().direct_space_state
	var ground := _ground_at(space, world_position)
	if not is_nan(ground):
		world_position.y = ground
	var away := world_position - _threat
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(-sin(_facing), 0.0, -cos(_facing))
	away = away.normalized()
	var side := 1.0 if away.cross(_run).y >= 0.0 else -1.0  # keep turning the way it has been
	var ways: Array[Vector3] = [away.rotated(Vector3.UP, _fan)]
	for turn in FLEE_TURNS:
		ways.append(away.rotated(Vector3.UP, turn * side))
		ways.append(away.rotated(Vector3.UP, -turn * side))
	for way in ways:
		if way.dot(_run) > -0.01 and _clear(space, way):
			_run = way
			return
	_run = Vector3.ZERO
	_cornered = true


## Whether it can run FLEE_LOOK m `way` from where it is.
func _clear(space: PhysicsDirectSpaceState3D, way: Vector3) -> bool:
	var from := WorldOrigin.to_local(world_position) + Vector3.UP * KNEE
	var query := PhysicsRayQueryParameters3D.create(from, from + way * FLEE_LOOK, CityStreamer.COLLISION_LAYER)
	if not space.intersect_ray(query).is_empty():
		return false
	var ground := _ground_at(space, world_position + way * FLEE_LOOK)
	return not is_nan(ground) and absf(ground - world_position.y) <= STEP_HEIGHT


## Height of whatever's underfoot at a world position (within a meter of its
## height), or NAN.
static func _ground_at(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var top := WorldOrigin.to_local(at) + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 2.0, CityStreamer.COLLISION_LAYER)
	var hit := space.intersect_ray(query)
	return NAN if hit.is_empty() else WorldOrigin.to_world(hit.position).y


func _update_detail(delta: float) -> void:
	_detail_check -= delta
	if _detail_check > 0.0:
		return
	_detail_check = DETAIL_CHECK
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := global_position.distance_to(camera.global_position)
	var shown := distance < VISIBLE_DISTANCE
	var chest := global_position + Vector3.UP * 1.2
	if shown and camera.is_position_in_frustum(chest):
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, chest, CityStreamer.COLLISION_LAYER)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and camera.global_position.distance_to(hit.position) < distance - 1.0:
			shown = false
			_detail_check = HIDDEN_CHECK
	visible = shown
	_player.active = shown and distance < ANIMATE_DISTANCE
	var slow := distance > MID_POSE_DISTANCE
	_pose_rate = FAR_POSE_RATE if distance > SLOW_POSE_DISTANCE else MID_POSE_RATE
	if slow != _slow_pose:
		_slow_pose = slow
		_pose_time = 0.0
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if slow \
				else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


func _move(distance: float) -> void:
	var total := _lengths[_lengths.size() - 1]
	_along += distance * _heading
	if _along >= total or _along <= 0.0:
		_along = clampf(_along, 0.0, total)
		_heading = -_heading  # end of the lane: turn around
	while _segment < _lane.size() - 2 and _along > _lengths[_segment + 1]:
		_segment += 1
	while _segment > 0 and _along < _lengths[_segment]:
		_segment -= 1
	var segment_length := maxf(_lengths[_segment + 1] - _lengths[_segment], 0.001)
	var point := _lane[_segment].lerp(_lane[_segment + 1], (_along - _lengths[_segment]) / segment_length)
	world_position = point + _across() * _side
	position = WorldOrigin.to_local(world_position)


func _tangent() -> Vector3:
	return (_lane[_segment + 1] - _lane[_segment]).normalized()


## How far (level) the point `along` m along the lane is from the danger.
func _from_threat(along: float) -> float:
	along = clampf(along, 0.0, _lengths[_lengths.size() - 1])
	var k := clampi(_lengths.bsearch(along) - 1, 0, _lane.size() - 2)
	var segment_length := maxf(_lengths[k + 1] - _lengths[k], 0.001)
	var point := _lane[k].lerp(_lane[k + 1], (along - _lengths[k]) / segment_length)
	return Vector2(point.x - _threat.x, point.z - _threat.z).length()


## Level and a meter long, so the step to the side stays the same on steep
## bits of lane: the TKTS steps' risers (18 cm up over 10 cm) shrank it by
## half, and people walking up or down jumped sideways at every step.
func _across() -> Vector3:
	var tangent := _tangent()
	return Vector3(-tangent.z, 0.0, tangent.x).normalized()


func _travel_yaw() -> float:
	var direction := _run if _off_lane else _tangent() * _heading
	return atan2(-direction.x, -direction.z)


func _animate(speed: float) -> void:
	if speed <= 0.0:
		_play(&"Idle", 1.0)
	elif speed < 3.0:
		_play(&"Walk", speed / 1.4)
	else:
		_play(&"Sprint", 0.85)


func _play(animation: StringName, speed: float) -> void:
	if _player.assigned_animation != animation:
		_player.play(animation, 0.25)
	_player.speed_scale = speed
