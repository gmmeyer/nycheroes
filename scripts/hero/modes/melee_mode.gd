class_name MeleeMode
extends HeroMode
## Punch combos. Each punch lunges at the nearest thug the player is steering
## (or looking) toward; keep pressing attack to chain a jab, a cross, and a
## super-strength blow that sends the thug flying.

## Per punch: animation, playback speed, seconds until it lands, seconds until
## the next punch can follow, damage, knockback speed, whether it launches.
const COMBO := [
	{animation = &"Punch_Jab", speed = 2.2, impact = 0.16, length = 0.36, damage = 50.0, push = 6.0, launch = false},
	{animation = &"Punch_Cross", speed = 2.2, impact = 0.18, length = 0.4, damage = 50.0, push = 8.0, launch = false},
	{animation = &"Punch_Cross", speed = 1.5, impact = 0.26, length = 0.55, damage = 100.0, push = 30.0, launch = true},
]

@export var lunge_range := 9.0
@export var lunge_speed := 30.0
## The lunge stops this far from the target.
@export var reach := 1.3
@export var hit_radius := 1.8
## How far off the steering direction (degrees) a thug can be and still be targeted.
@export var target_angle := 80.0
## With nobody in that direction, turn to any thug this close.
@export var any_direction_range := 5.0

## Which punch of the combo is playing.
var step := 0
## Goes up by one with every punch, so the animator knows to restart.
var punch_id := 0

var _time := 0.0
var _struck := false
var _queued := false
var _target: Thug


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	step = 0
	_start_punch()


func current_punch() -> Dictionary:
	return COMBO[step]


func physics_update(delta: float) -> StringName:
	var punch: Dictionary = COMBO[step]
	_time += delta
	if hero.attack_pressed:
		_queued = true
	if hero.input.fly_toggle_pressed:
		return &"Flight"
	if hero.jump_pressed:
		(hero.get_mode(&"OnFoot") as OnFootMode).begin_jump()
		return &"OnFoot"
	if hero.hurt_time > 0.0:
		return &"OnFoot"

	var lunge := Vector3.ZERO
	if _target and not _target.is_down():
		var to_target := _target.global_position - hero.global_position
		to_target.y = 0.0
		hero.face_toward(to_target)
		var gap := to_target.length() - reach
		if gap > 0.0 and not _struck:
			lunge = to_target.normalized() * minf(lunge_speed, gap / maxf(punch.impact - _time, delta))
	var vertical := 0.0 if hero.is_on_floor() else hero.velocity.y - Hero.GRAVITY * delta
	hero.velocity = Vector3(lunge.x, vertical, lunge.z)
	hero.move_and_slide()
	LedgeClimb.climb(hero, Vector3(lunge.x, vertical, lunge.z), delta)

	if not _struck and _time >= punch.impact:
		_struck = true
		var forward := hero.forward()
		var push: Vector3 = forward * punch.push + Vector3.UP * (punch.push * 0.4 if punch.launch else 1.5)
		Combat.strike(hero.global_position + forward + Vector3.UP * 1.1, hit_radius, punch.damage, push, punch.launch)
	if _time >= punch.length:
		if _queued and step < COMBO.size() - 1:
			step += 1
			_start_punch()
			return &""
		return &"OnFoot"
	return &""


func _start_punch() -> void:
	_time = 0.0
	_struck = false
	_queued = false
	punch_id += 1
	_target = _find_target()


## The thug to punch: the best one within lunge range in the direction the
## player is steering (or the camera looks when not steering); failing that,
## whoever is closest, if they're within arm's reach of a quick turn.
func _find_target() -> Thug:
	var aim := hero.input.move if hero.input.move.length() > 0.2 else hero.input.aim
	aim = Vector3(aim.x, 0.0, aim.z).normalized()
	var best: Thug = null
	var best_score := INF
	var nearest: Thug = null
	var nearest_distance := any_direction_range
	for thug in Combat.thugs:
		if thug.is_down():
			continue
		var offset := thug.global_position - hero.global_position
		if absf(offset.y) > 2.5:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = thug
		var angle := aim.angle_to(offset) if distance > 0.1 else 0.0
		if distance > lunge_range or angle > deg_to_rad(target_angle):
			continue
		var score := distance + angle * 4.0
		if score < best_score:
			best_score = score
			best = thug
	return best if best else nearest
