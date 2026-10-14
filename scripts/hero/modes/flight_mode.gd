class_name FlightMode
extends HeroMode
## Free flight: the stick steers relative to where the camera looks, Space/C
## climb and descend, Shift boosts. Descending onto the ground lands.

@export var cruise_speed := 30.0
@export var boost_speed := 150.0
@export var acceleration := 40.0
@export var boost_acceleration := 100.0
## How quickly the hero comes to a hover with no input (per second).
@export var hover_damping := 2.5


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func exit() -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED


func physics_update(delta: float) -> StringName:
	var input := hero.input
	if input.fly_toggle_pressed:
		return &"OnFoot"

	var forward := input.aim
	var right := forward.cross(Vector3.UP).normalized()
	var wish := forward * -input.stick.y + right * input.stick.x + Vector3.UP * input.vertical
	if wish.length() > 0.05:
		var boosting := input.sprint_held
		var target := wish.limit_length(1.0) * (boost_speed if boosting else cruise_speed)
		hero.velocity = hero.velocity.move_toward(target, (boost_acceleration if boosting else acceleration) * delta)
	else:
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
