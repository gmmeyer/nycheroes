class_name EncounterDirector
extends Node3D
## Puts gangs of thugs on the streets around the hero, a couple at a time
## (preferably ahead of the camera, so the player sees them coming), and clears
## gangs and bodies away once the hero is far off. ?gangs=N sets how many.

const THUG_SCENE := preload("res://scenes/npc/thug.tscn")
const UPDATE_INTERVAL := 0.5
const MAX_SPAWN_ALTITUDE := 150.0
## Spacing between gang members along the sidewalk.
const SPACING := 1.6

@export var city: CityStreamer
@export var hero: Hero
@export var max_gangs := 2
@export var gang_size := Vector2i(3, 5)
@export var spawn_range := Vector2(55.0, 110.0)
@export var despawn_distance := 250.0
@export var respawn_delay := 5.0
## Oldest bodies are removed beyond this many.
@export var max_bodies := 16

var _gangs: Array[Array] = []
var _bodies: Array[Thug] = []
var _cooldown := 2.0
var _update_cooldown := 0.0
var _gang_count := 0


func _ready() -> void:
	if LaunchOptions.has("gangs"):
		max_gangs = int(LaunchOptions.get_string("gangs"))
	Combat.thug_defeated.connect(_on_thug_defeated)


func _process(delta: float) -> void:
	_cooldown -= delta
	_update_cooldown -= delta
	if _update_cooldown > 0.0:
		return
	_update_cooldown = UPDATE_INTERVAL

	var center := hero.world_position()
	for gang: Array in _gangs.duplicate():
		var members: Array = gang.filter(func(thug: Thug) -> bool: return is_instance_valid(thug))
		var far: bool = members.all(func(thug: Thug) -> bool:
			return WorldOrigin.to_world(thug.global_position).distance_to(center) > despawn_distance)
		if members.is_empty() or far:
			for thug: Thug in members:
				thug.queue_free()
			_gangs.erase(gang)

	if _cooldown <= 0.0 and not hero.frozen and center.y < MAX_SPAWN_ALTITUDE and _active_gangs() < max_gangs:
		if _spawn_gang(center):
			_cooldown = respawn_delay


## The standing thug nearest to a world position, or null.
func nearest_thug(world_position: Vector3) -> Thug:
	var best: Thug = null
	var best_distance := INF
	for thug in Combat.thugs:
		if thug.is_down():
			continue
		var distance := WorldOrigin.to_world(thug.global_position).distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = thug
	return best


func _active_gangs() -> int:
	var count := 0
	for gang: Array in _gangs:
		if gang.any(func(thug: Thug) -> bool: return is_instance_valid(thug) and not thug.is_down()):
			count += 1
	return count


func _spawn_gang(center: Vector3) -> bool:
	var lanes := city.lanes_near(center, spawn_range.y)
	if lanes.is_empty():
		return false
	var camera := get_viewport().get_camera_3d()
	var ahead := -camera.global_basis.z if camera else Vector3.FORWARD
	ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
	for attempt in 40:
		var lane: PackedVector3Array = lanes.pick_random()
		var segment := randi() % (lane.size() - 1)
		var along := lane[segment + 1] - lane[segment]
		var point := lane[segment].lerp(lane[segment + 1], randf())
		var offset := point - center
		offset.y = 0.0
		var distance := offset.length()
		if distance < spawn_range.x or distance > spawn_range.y:
			continue
		if attempt < 30 and ahead.dot(offset / distance) < 0.3:
			continue  # prefer somewhere the player is looking

		spawn_gang(point, randi_range(gang_size.x, gang_size.y), along.normalized())
		return true
	return false


## Places a gang of `count` thugs in a line along `direction`, centered on a
## world position. Used by the spawner, and by demos and tests.
func spawn_gang(world_center: Vector3, count: int, direction: Vector3) -> Array[Thug]:
	var gang: Array[Thug] = []
	for k in count:
		var spot := world_center + direction * (k - (count - 1) * 0.5) * SPACING
		var thug: Thug = THUG_SCENE.instantiate()
		add_child(thug)
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(hero, _gang_count, TAU * k / count + randf() * 0.5)
		gang.append(thug)
	_gangs.append(gang)
	_gang_count += 1
	return gang


func _on_thug_defeated(thug: Thug) -> void:
	_bodies.append(thug)
	while _bodies.size() > max_bodies:
		var oldest: Thug = _bodies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
