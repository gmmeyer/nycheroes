class_name LedgeClimb
## Lets a CharacterBody3D walk up curbs and other low ledges, which
## move_and_slide alone treats as walls.

## The highest ledge that can be walked onto (meters); a curb is 0.15.
const MAX_HEIGHT := 0.35
## Ground steeper than this (normal's y) isn't something to stand on.
const MIN_FLOOR_NORMAL_Y := 0.7


## Call right after move_and_slide, with the velocity the body meant to move
## at before sliding. If a low ledge stopped it, lifts the body onto the ledge
## (when there's room above and ground to stand on), keeping the horizontal
## speed the ledge took away, so running over a curb doesn't stop the body.
## Returns true if it did.
static func climb(body: CharacterBody3D, intended: Vector3, delta: float) -> bool:
	var step := Vector3(intended.x, 0.0, intended.z) * delta
	if not body.is_on_wall() or step.length_squared() < 0.000001:
		return false
	var start := body.global_transform
	var up := Vector3.UP * MAX_HEIGHT
	if body.test_move(start, up):
		return false  # no room above
	var raised := start.translated(up)
	if body.test_move(raised, step):
		return false  # still blocked up there: a real wall
	var ahead := raised.translated(step)
	var landing := KinematicCollision3D.new()
	if not body.test_move(ahead, -up * 1.5, landing) or landing.get_normal().y < MIN_FLOOR_NORMAL_Y:
		return false  # nothing to stand on
	body.global_position = ahead.origin + landing.get_travel()
	# move_and_slide cut the speed into the ledge; carry on as if it weren't there.
	body.velocity.x = intended.x
	body.velocity.z = intended.z
	body.velocity.y = maxf(body.velocity.y, 0.0)
	return true
