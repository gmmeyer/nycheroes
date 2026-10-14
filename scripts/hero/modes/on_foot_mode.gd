class_name OnFootMode
extends HeroMode
## Running, super speed, jumps and charged super jumps, falling, and swimming.

@export_group("Running")
@export var run_speed := 9.0
@export var super_speed := 60.0
@export var acceleration := 45.0
## Acceleration above running speed, so super speed builds up.
@export var super_acceleration := 25.0
@export var braking := 60.0
## Turn rate in rad/s at running speed and at full super speed.
@export var turn_rate := 14.0
@export var super_turn_rate := 2.5

@export_group("Jumping")
@export var jump_speed := 12.0
@export var super_jump_min_speed := 30.0
@export var super_jump_max_speed := 80.0
## Extra forward speed a fully charged super jump adds toward the stick direction.
@export var super_jump_leap := 25.0
## Hold time from the start of a super jump charge to full power.
@export var charge_time := 1.0
## Letting go of jump sooner than this is a normal jump.
@export var tap_time := 0.18
@export var air_acceleration := 18.0
## Grace period for jumping just after running off a ledge.
@export var coyote_time := 0.12

@export_group("Swimming")
@export var swim_speed := 5.0
@export var swim_super_speed := 25.0
@export var water_jump_speed := 16.0
## Height the hero's feet float at (water surface is 0).
@export var float_height := -1.2

## True while jump is held on the ground; charge goes 0..1 once it's a super jump.
var charging := false
var charge := 0.0

var _hold_time := 0.0
var _air_time := 0.0
var _web_cooldown := 0.0


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	charging = false
	charge = 0.0


func physics_update(delta: float) -> StringName:
	if hero.input.fly_toggle_pressed:
		return &"Flight"
	if _wants_web(delta) and (hero.get_mode(&"Swing") as SwingMode).try_attach():
		return &"Swing"

	if hero.is_in_water():
		_swim(delta)
	elif hero.is_on_floor():
		_run(delta)
	else:
		_fall(delta)
	hero.move_and_slide()
	return &""


func _wants_web(delta: float) -> bool:
	# A press always tries; holding the button keeps retrying in the air.
	_web_cooldown -= delta
	var retry := hero.input.web_held and _web_cooldown <= 0.0 and not hero.is_on_floor()
	if hero.web_pressed or retry:
		_web_cooldown = 0.25
		return true
	return false


func _run(delta: float) -> void:
	_air_time = 0.0
	var input := hero.input
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	var speed := horizontal.length()
	var wish := input.move.limit_length(1.0)

	if charging and charge > 0.0:
		# Crouched for a super jump: plant the feet.
		horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)
	elif wish.length() > 0.05:
		var wish_dir := wish.normalized()
		var direction := horizontal / speed if speed > 0.5 else wish_dir
		var fast := clampf(inverse_lerp(run_speed, super_speed, speed), 0.0, 1.0)
		direction = _turn(direction, wish_dir, lerpf(turn_rate, super_turn_rate, fast) * delta)
		var target := (super_speed if input.sprint_held else run_speed) * wish.length()
		var rate := acceleration
		if target < speed:
			rate = braking
		elif speed >= run_speed:
			rate = super_acceleration
		horizontal = direction * move_toward(speed, target, rate * delta)
		hero.face_toward(direction)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)

	hero.velocity = Vector3(horizontal.x, 0.0, horizontal.z)
	_update_jump(delta)


func _update_jump(delta: float) -> void:
	if hero.jump_pressed:
		charging = true
		_hold_time = 0.0
	if not charging:
		return
	if hero.input.jump_held:
		_hold_time += delta
		charge = clampf((_hold_time - tap_time) / charge_time, 0.0, 1.0)
		return

	if _hold_time < tap_time:
		hero.velocity.y = jump_speed
	else:
		hero.velocity.y = lerpf(super_jump_min_speed, super_jump_max_speed, charge)
		hero.velocity += hero.input.move.limit_length(1.0) * charge * super_jump_leap
	charging = false
	charge = 0.0


func _fall(delta: float) -> void:
	_air_time += delta
	charging = false
	charge = 0.0
	if hero.jump_pressed and _air_time < coyote_time:
		hero.velocity.y = jump_speed

	# Steer a little, but never slow a fast jump down below its own speed.
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	var limit := maxf(horizontal.length(), run_speed)
	horizontal = (horizontal + hero.input.move.limit_length(1.0) * air_acceleration * delta).limit_length(limit)
	hero.velocity.x = horizontal.x
	hero.velocity.z = horizontal.z
	hero.velocity.y = maxf(hero.velocity.y - Hero.GRAVITY * delta, -Hero.MAX_FALL_SPEED)
	hero.face_toward(horizontal, 10.0 * delta)


func _swim(delta: float) -> void:
	charging = false
	charge = 0.0
	var input := hero.input
	var wish := input.move.limit_length(1.0)
	var top_speed := swim_super_speed if input.sprint_held else swim_speed
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z).move_toward(wish * top_speed, 30.0 * delta)

	# Bob back up to the surface, and leap out with jump.
	var rise := (float_height - hero.global_position.y) * 4.0
	var vertical := lerpf(hero.velocity.y, rise, 1.0 - exp(-6.0 * delta))
	if hero.jump_pressed:
		vertical = water_jump_speed
	hero.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	hero.face_toward(wish, 8.0 * delta)


static func _turn(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(angle, -max_angle, max_angle))
