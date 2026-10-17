class_name HeroAnimator
extends Node3D
## Draws the hero: follows it smoothly between physics ticks, turns and tilts
## the model to match the movement, and picks animations from the hero's state.

const BLEND_TIME := 0.18
const HARD_LANDING_SPEED := 35.0
## Height of the body's middle; the model tilts around it.
const PIVOT_HEIGHT := 0.9

@export var hero: Hero

var _player: AnimationPlayer
var _hand: BoneAttachment3D
var _yaw := 0.0
var _up := Vector3.UP
var _land_timer := 0.0
var _hard_landing := false
var _punch_id := -1
var outfit: HeroOutfit
var appearance: Dictionary = {}


func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	_hand = BoneAttachment3D.new()
	_hand.bone_name = "DEF-hand.R"
	skeleton.add_child(_hand)
	var body := find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	outfit = HeroOutfit.new()
	outfit.name = "Outfit"
	skeleton.add_child(outfit)
	if appearance.is_empty():
		appearance = HeroAppearance.current() if hero.remote_id == 0 else HeroAppearance.DEFAULT.duplicate()
	outfit.setup(skeleton, body, appearance)
	if hero.remote_id == 0:
		Settings.changed.connect(_appearance_changed)
	SkinWarmup.add_to(self)
	hero.landed.connect(_on_landed)
	_yaw = hero.facing


## Network identities are shown by name tags; cosmetics belong to the player.
func set_appearance(value: Dictionary) -> void:
	appearance = HeroAppearance.sanitize(value)
	if outfit:
		outfit.apply(appearance)


func _appearance_changed(key: String) -> void:
	if key == HeroAppearance.KEY:
		set_appearance(HeroAppearance.current())


## World position of the hand that shoots webs.
func hand_position() -> Vector3:
	return _hand.global_position


func _process(delta: float) -> void:
	if outfit:
		outfit.set_motion(hero.velocity.length())
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
	_play(choice[0], choice[1], choice.size() > 2 and choice[2])


## Which way the body's head should point.
func _target_up() -> Vector3:
	match hero.mode.name:
		&"Flight", &"Dive":
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
			if hero.grounded() and speed > 12.0:
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


## Returns [animation name, playback speed, restart from the beginning?].
func _choose_animation() -> Array:
	var speed := hero.horizontal_speed()
	match hero.mode.name:
		&"Flight":
			return [&"Jump", 0.6] if hero.velocity.length() > 8.0 else [&"Idle", 0.6]
		&"Swing", &"Dive":
			return [&"Jump", 1.0]
		&"KnockedOut":
			return [&"Death01", 1.0]
		&"Melee":
			var melee := hero.mode as MeleeMode
			var punch := melee.current_punch()
			var new_punch := melee.punch_id != _punch_id
			_punch_id = melee.punch_id
			return [punch.animation, punch.speed, new_punch]
	var on_foot := hero.mode as OnFootMode
	if hero.is_in_water():
		return [&"Swim_Fwd", 1.0] if speed > 1.0 else [&"Swim_Idle", 1.0]
	if hero.hurt_time > 0.0:
		return [&"Hit_Chest", 1.0]
	if not hero.grounded():
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


func _play(animation: StringName, speed_scale: float, restart := false) -> void:
	# assigned_animation (not current_animation) so one-shots like Death01 hold their last frame.
	if restart or _player.assigned_animation != animation:
		_player.play(animation, 0.05 if restart else BLEND_TIME)
		if restart:
			_player.seek(0.0, true)
	_player.speed_scale = speed_scale


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 8.0:
		return
	_hard_landing = impact_speed >= HARD_LANDING_SPEED
	_land_timer = 0.45 if _hard_landing else 0.25
