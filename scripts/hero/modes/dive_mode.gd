class_name DiveMode
extends HeroMode
## Dive attack from the air (attack while jumping, flying or swinging): rocket
## at a thug the camera looks toward (or failing that, one below the hero), or
## down where the camera looks, and land with a ground slam.

@export var dive_speed := 55.0
@export var search_range := 150.0
## How far off the camera's aim (degrees) a thug can be and still be dived at.
@export var search_angle := 55.0
## How far off straight down (degrees) a thug can be to count as below the hero.
@export var below_angle := 50.0

var _direction := Vector3.DOWN


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	hero.slam_pending = true
	var target := _find_target()
	if target:
		_direction = (target.global_position - hero.global_position).normalized()
	else:
		var flat_aim := Vector3(hero.input.aim.x, 0.0, hero.input.aim.z)
		_direction = Vector3.DOWN
		if flat_aim.length() > 0.01:
			_direction = (Vector3.DOWN + flat_aim.normalized() * 0.35).normalized()
	hero.face_toward(_direction)


func physics_update(_delta: float) -> StringName:
	hero.velocity = _direction * dive_speed
	hero.move_and_slide()
	if hero.is_in_water():
		hero.slam_pending = false
		return &"OnFoot"
	if hero.is_on_floor() or hero.is_on_wall() or hero.is_on_ceiling():
		return &"OnFoot"  # Hero slams on landing; off a wall, it slams when it hits the ground
	return &""


func _find_target() -> Thug:
	var aimed := _closest_to(hero.input.aim, search_angle)
	return aimed if aimed else _closest_to(Vector3.DOWN, below_angle)


## The standing thug below the hero closest in angle to `direction`, within `max_angle` degrees.
func _closest_to(direction: Vector3, max_angle: float) -> Thug:
	var best: Thug = null
	var best_angle := deg_to_rad(max_angle)
	for thug in Combat.thugs:
		if thug.is_down():
			continue
		var offset := thug.global_position - hero.global_position
		if offset.y > -1.0 or offset.length() > search_range:
			continue  # only thugs below, within range
		var angle := direction.angle_to(offset)
		if angle < best_angle:
			best_angle = angle
			best = thug
	return best
