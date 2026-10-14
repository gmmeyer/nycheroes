extends MeshInstance3D
## Draws the web from the hero's hand to its anchor while swinging.
## The mesh is a 1 m tall cylinder along Y, stretched between the two points.

@export var hero: Hero
@export var animator: HeroAnimator


func _process(_delta: float) -> void:
	visible = hero.mode.name == &"Swing"
	if not visible:
		return
	var from := animator.hand_position()
	var to := (hero.get_mode(&"Swing") as SwingMode).web_point
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var y := (to - from) / length
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	global_transform = Transform3D(Basis(x, y * length, x.cross(y)), (from + to) * 0.5)
