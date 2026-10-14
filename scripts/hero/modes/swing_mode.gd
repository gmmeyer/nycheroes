class_name SwingMode
extends HeroMode
## Web swinging: shoot a web at a building ahead and above, swing on it like a
## pendulum while the web button is held, and let go to fly on with the momentum.
##
## The web sticks to a building wall beside the street, but the hero swings from
## a pivot above the street instead (like Spider-Man games do), so swings carry
## the hero along the street rather than into the wall.

## Height of the hand holding the web, above the hero's feet.
const HAND_HEIGHT := 1.4
## How far the hero's feet stay above the ground at the bottom of a swing.
const GROUND_CLEARANCE := 6.0
## Shortest web worth swinging on.
const MIN_ROPE := 8.0

@export var max_web_length := 120.0
## Anchors must be at least this far above the hand.
@export var min_anchor_height := 12.0
## How much of the web's sideways offset the pivot keeps (0 = straight above the path).
@export var sideways_keep := 0.0
## The web starts this much shorter than the distance, which yanks the hero into the swing.
@export var initial_reel := 0.85
## How hard the stick pumps the swing.
@export var pump_acceleration := 14.0
@export var max_speed := 60.0
## Extra speed on letting go: x = forward, y = up.
@export var release_boost := Vector2(4.0, 10.0)

## Pivot the hero swings from, and where the web visibly sticks to a building
## (scene space; both move with the floating origin).
var anchor := Vector3.ZERO
var web_point := Vector3.ZERO
var rope_length := 0.0


func _ready() -> void:
	WorldOrigin.shifted.connect(func(delta: Vector3) -> void:
		anchor -= delta
		web_point -= delta)


## Looks for a building ahead and above to stick a web to. Returns true if found.
func try_attach() -> bool:
	var space := hero.get_world_3d().direct_space_state
	var hand := hero.global_position + Vector3.UP * HAND_HEIGHT
	var forward := _swing_direction()
	var best_score := -INF
	# A wide fan: real buildings step back as they rise, so walls high enough
	# to swing from are often off to the side.
	for elevation: float in [55.0, 40.0, 70.0, 30.0]:
		for side: float in [0.0, -25.0, 25.0, -45.0, 45.0]:
			var flat := forward.rotated(Vector3.UP, deg_to_rad(side))
			var direction := flat * cos(deg_to_rad(elevation)) + Vector3.UP * sin(deg_to_rad(elevation))
			var query := PhysicsRayQueryParameters3D.create(hand, hand + direction * max_web_length, Hero.WORLD_LAYER)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var point: Vector3 = hit.position
			var offset := point - hand
			var ahead := offset.dot(forward)
			if offset.y < min_anchor_height or ahead < 5.0:
				continue
			var sideways := Vector3(offset.x, 0.0, offset.z) - forward * ahead
			var pivot := hand + forward * ahead + sideways * sideways_keep + Vector3.UP * offset.y
			# The bottom of the swing has to clear whatever is under the pivot.
			var longest := pivot.y - _floor_below(space, pivot) - HAND_HEIGHT - GROUND_CLEARANCE
			var rope := minf(hand.distance_to(pivot) * initial_reel, longest)
			if rope < MIN_ROPE:
				continue
			# Prefer webs about 50 m long, straight ahead, at a medium angle.
			var score := -absf(offset.length() - 50.0) * 0.5 - absf(side) * 0.3 - absf(elevation - 55.0) * 0.2
			if score > best_score:
				best_score = score
				web_point = point
				anchor = pivot
				rope_length = rope
	return best_score > -INF


func _floor_below(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1000.0, Hero.WORLD_LAYER))
	return hit.position.y if not hit.is_empty() else 0.0


## Horizontal direction to look for anchors: where the camera looks, leaning
## toward the direction of travel when moving fast.
func _swing_direction() -> Vector3:
	var aim := Vector3(hero.input.aim.x, 0.0, hero.input.aim.z)
	var forward := aim.normalized() if aim.length() > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, hero.facing)
	var travel := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	if travel.length() > 5.0:
		forward = forward.lerp(travel.normalized(), 0.5).normalized()
	return forward


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	if hero.is_on_floor():
		hero.velocity.y = 12.0  # hop off the ground into the swing


func physics_update(delta: float) -> StringName:
	var input := hero.input
	if input.fly_toggle_pressed:
		return &"Flight"
	if hero.attack_pressed:
		return &"Dive"
	if not input.web_held:
		_release()
		return &"OnFoot"

	var velocity := hero.velocity
	velocity.y -= Hero.GRAVITY * delta
	velocity += input.move.limit_length(1.0) * pump_acceleration * delta

	var hand := hero.global_position + Vector3.UP * HAND_HEIGHT
	var to_anchor := anchor - hand
	var distance := to_anchor.length()
	if distance > rope_length:
		# The web is taut: no moving away from the anchor, and reel in any slack
		# (quickly at first, e.g. when the swing starts from the ground).
		var toward := to_anchor / distance
		var inward_speed := velocity.dot(toward)
		var wanted := minf((distance - rope_length) * 4.0, 25.0)
		if inward_speed < wanted:
			velocity += toward * (wanted - inward_speed)
	hero.velocity = velocity.limit_length(max_speed)
	hero.move_and_slide()
	hero.face_toward(hero.velocity, 8.0 * delta)

	if hero.is_on_floor():
		return &"OnFoot"
	if hand.y > anchor.y - 1.0:
		# Swung up level with the anchor; the web would go slack, so let go.
		_release()
		return &"OnFoot"
	return &""


func _release() -> void:
	var flat := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	if flat.length() > 1.0:
		hero.velocity += flat.normalized() * release_boost.x
	hero.velocity.y += release_boost.y
