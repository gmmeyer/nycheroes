class_name HeroAnimator
extends Node3D
## Draws the hero: follows it smoothly between physics ticks, turns and tilts
## the model to match the movement, and picks animations from the hero's state.

const BLEND_TIME := 0.18
const HARD_LANDING_SPEED := 35.0
## Height of the body's middle; the model tilts around it.
const PIVOT_HEIGHT := 0.9

@export var hero: Hero
@export var suit_color := Color(0.72, 0.06, 0.08)
@export var trim_color := Color(0.06, 0.1, 0.32)

var _player: AnimationPlayer
var _hand: BoneAttachment3D
var _yaw := 0.0
var _up := Vector3.UP
var _land_timer := 0.0
var _hard_landing := false


func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	_hand = BoneAttachment3D.new()
	_hand.bone_name = "DEF-hand.R"
	skeleton.add_child(_hand)
	_paint(find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D)
	hero.landed.connect(_on_landed)
	_yaw = hero.facing


## World position of the hand that shoots webs.
func hand_position() -> Vector3:
	return _hand.global_position


func _process(delta: float) -> void:
	_land_timer -= delta
	_yaw = lerp_angle(_yaw, hero.facing, 1.0 - exp(-14.0 * delta))
	# Blend and renormalize (Vector3.slerp errors when the vectors are nearly equal).
	var target_up := _target_up()
	var blended_up := _up.lerp(target_up, 1.0 - exp(-8.0 * delta))
	_up = blended_up.normalized() if blended_up.length_squared() > 0.000001 else target_up
	var basis := _tilt_to(_up) * Basis(Vector3.UP, _yaw)
	var pivot := hero.get_visual_position() + Vector3.UP * PIVOT_HEIGHT
	global_transform = Transform3D(basis, pivot - basis * (Vector3.UP * PIVOT_HEIGHT))
	var choice := _choose_animation()
	_play(choice[0], choice[1])


## Which way the body's head should point.
func _target_up() -> Vector3:
	match hero.mode.name:
		&"Flight":
			var speed := hero.velocity.length()
			if speed < 8.0:
				return Vector3.UP
			# Superhero pose: lean head-first into the direction of travel.
			var lean := clampf((speed - 8.0) / 25.0, 0.0, 0.92)
			return Vector3.UP.lerp(hero.velocity / speed, lean).normalized()
		&"Swing":
			var anchor := (hero.get_mode(&"Swing") as SwingMode).anchor
			return Vector3.UP.lerp((anchor - hero.global_position).normalized(), 0.8).normalized()
		_:
			var speed := hero.horizontal_speed()
			if hero.is_on_floor() and speed > 12.0:
				# Lean into super speed.
				var forward := Vector3(hero.velocity.x, 0.0, hero.velocity.z) / speed
				return Vector3.UP.lerp(forward, clampf((speed - 12.0) / 60.0, 0.0, 0.35)).normalized()
			return Vector3.UP


## Rotation that tips straight up onto `up` (a unit vector).
static func _tilt_to(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	var sine := axis.length()
	if sine < 0.01:
		# Too small an angle for a reliable axis: upright, or upside down.
		return Basis.IDENTITY if up.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis / sine, atan2(sine, up.y))


## Returns [animation name, playback speed].
func _choose_animation() -> Array:
	var speed := hero.horizontal_speed()
	match hero.mode.name:
		&"Flight":
			return [&"Jump", 0.6] if hero.velocity.length() > 8.0 else [&"Idle", 0.6]
		&"Swing":
			return [&"Jump", 1.0]
	var on_foot := hero.mode as OnFootMode
	if hero.is_in_water():
		return [&"Swim_Fwd", 1.0] if speed > 1.0 else [&"Swim_Idle", 1.0]
	if not hero.is_on_floor():
		return [&"Jump", 1.0]
	if (on_foot.charging and on_foot.charge > 0.0) or (_land_timer > 0.0 and _hard_landing):
		return [&"Crouch_Idle", 1.0]
	if _land_timer > 0.0:
		return [&"Jump_Land", 2.0]
	if speed < 0.5:
		return [&"Idle", 1.0]
	if speed < 4.0:
		return [&"Walk", speed / 1.6]
	if speed < 8.0:
		return [&"Jog_Fwd", speed / 4.5]
	return [&"Sprint", clampf(speed / 8.0, 1.0, 3.5)]


func _play(animation: StringName, speed_scale: float) -> void:
	if _player.current_animation != animation:
		_player.play(animation, BLEND_TIME)
	_player.speed_scale = speed_scale


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 8.0:
		return
	_hard_landing = impact_speed >= HARD_LANDING_SPEED
	_land_timer = 0.45 if _hard_landing else 0.25


func _paint(mesh: MeshInstance3D) -> void:
	# Surface 0 is the body (M_Main), surface 1 the joints (M_Joints).
	mesh.set_surface_override_material(0, _material(suit_color))
	mesh.set_surface_override_material(1, _material(trim_color))


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material
