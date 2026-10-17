class_name FlightMode
extends HeroMode
## Free flight: the stick steers relative to where the camera looks, Space/C
## climb and descend, Shift boosts. Descending onto the ground lands.

@export var cruise_speed := 33.0
@export var boost_speed := 150.0
## Sustained boost builds to 187.5 m/s over six seconds of actual flight.
@export var sustained_boost_multiplier := 1.25
@export var boost_ramp_seconds := 6.0
@export var acceleration := 40.0
@export var boost_acceleration := 100.0
## How quickly the hero comes to a hover with no input (per second).
@export var hover_damping := 2.5

var _boost_time := 0.0


func enter(_previous: StringName) -> void:
	_boost_time = 0.0
	hero.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func exit() -> void:
	_boost_time = 0.0
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED


func physics_update(delta: float) -> StringName:
	var input := hero.input
	if input.fly_toggle_pressed:
		return &"OnFoot"
	if hero.attack_pressed:
		return &"Dive"

	var forward := input.aim
	var right := forward.cross(Vector3.UP).normalized()
	var wish := forward * -input.stick.y + right * input.stick.x + Vector3.UP * input.vertical
	if wish.length() > 0.05:
		var boosting := input.sprint_held
		# Don't charge while hovering or pushing into a wall. Releasing boost
		# starts the next run at the normal boost speed.
		if boosting and hero.velocity.dot(wish.normalized()) > cruise_speed:
			_boost_time = minf(_boost_time + delta, boost_ramp_seconds)
		else:
			_boost_time = 0.0
		var ramp := clampf(_boost_time / maxf(boost_ramp_seconds, 0.001), 0.0, 1.0)
		var speed := boost_speed * lerpf(1.0, sustained_boost_multiplier, ramp) if boosting else cruise_speed
		var target := wish.limit_length(1.0) * speed
		hero.velocity = hero.velocity.move_toward(target, (boost_acceleration if boosting else acceleration) * delta)
	else:
		_boost_time = 0.0
		hero.velocity *= exp(-hover_damping * delta)
	hero.move_and_slide()

	var flat := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	hero.face_toward(flat if flat.length() > 2.0 else forward, 6.0 * delta)
	if input.vertical < 0.0 and _touching_ground():
		return &"OnFoot"
	return &""


func _touching_ground() -> bool:
	for i in hero.get_slide_collision_count():
		if hero.get_slide_collision(i).get_normal().y > 0.7:
			return true
	return false
