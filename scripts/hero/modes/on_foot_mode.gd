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

@export_group("Super speed ram")
## Running faster than this bowls over any thug in the way.
@export var ram_speed := 25.0
@export var ram_radius := 1.8

@export_group("Swimming")
@export var swim_speed := 5.0
@export var swim_super_speed := 25.0
@export var water_jump_speed := 16.0
## How far below the water's surface the hero's feet float.
@export var float_height := -1.2

## True while jump is held on the ground; charge goes 0..1 once it's a super jump.
var charging := false
var charge := 0.0

var _hold_time := 0.0
var _air_time := 0.0
var _web_cooldown := 0.0
var _scare_cooldown := 0.0
var _jump_handed_over := false


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	charging = _jump_handed_over
	charge = 0.0
	_jump_handed_over = false


func physics_update(delta: float) -> StringName:
	if hero.input.fly_toggle_pressed:
		return &"Flight"
	if hero.attack_pressed and hero.hurt_time <= 0.0 and not hero.is_in_water():
		return &"Melee" if hero.is_on_floor() else &"Dive"
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
	if hero.hurt_time > 0.0:
		wish = Vector3.ZERO  # staggered by a hit

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
	_ram(horizontal, delta)


## At super speed, thugs in the way get bowled over and bystanders scatter.
func _ram(horizontal: Vector3, delta: float) -> void:
	var speed := horizontal.length()
	if speed < ram_speed:
		return
	var direction := horizontal / speed
	var center := hero.global_position + direction * 0.8 + Vector3.UP
	Combat.strike(center, ram_radius, 100.0, direction * speed * 0.7 + Vector3.UP * speed * 0.35, true)
	_scare_cooldown -= delta
	if _scare_cooldown <= 0.0:
		_scare_cooldown = 0.3
		Combat.raise_danger(hero.world_position(), 14.0)


## Starts a jump as if jump had just been pressed on the ground: a tap jumps,
## holding charges a super jump. Other modes call this to hand a jump press
## over just before switching to OnFoot.
func begin_jump() -> void:
	charging = true
	_hold_time = 0.0
	_jump_handed_over = true


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
	var rise := (hero.water_level + float_height - hero.global_position.y) * 4.0
	var vertical := lerpf(hero.velocity.y, rise, 1.0 - exp(-6.0 * delta))
	if hero.jump_pressed:
		vertical = water_jump_speed
	hero.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	hero.face_toward(wish, 8.0 * delta)


static func _turn(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(angle, -max_angle, max_angle))
