class_name CrowdManager
extends Node3D
## Keeps pedestrians on the sidewalks around the hero: spawns them out of
## sight, removes them once far away, and sends them running from danger.
## ?peds=N sets how many (default max_pedestrians).

const PEDESTRIAN_SCENE := preload("res://scenes/npc/pedestrian.tscn")
const UPDATE_INTERVAL := 0.5
## Above this height the street is too far below to bother with pedestrians.
const MAX_SPAWN_ALTITUDE := 150.0
## Closer than this, don't spawn where the camera can see.
const VISIBLE_SPAWN_DISTANCE := 90.0

@export var city: CityStreamer
@export var hero: Hero
@export var max_pedestrians := 45
@export var spawn_range := Vector2(35.0, 130.0)
@export var despawn_distance := 170.0
@export var spawns_per_update := 6

var pedestrians: Array[Pedestrian] = []
var _cooldown := 0.0
var _filled_once := false


func _ready() -> void:
	if LaunchOptions.has("peds"):
		max_pedestrians = int(LaunchOptions.get_string("peds"))
	Combat.danger.connect(_on_danger)


func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = UPDATE_INTERVAL

	var center := hero.world_position()
	for pedestrian in pedestrians.duplicate():
		if pedestrian.world_position.distance_to(center) > despawn_distance:
			pedestrians.erase(pedestrian)
			pedestrian.queue_free()
	if hero.frozen or center.y > MAX_SPAWN_ALTITUDE or pedestrians.size() >= max_pedestrians:
		return
	var lanes := city.lanes_near(center, spawn_range.y)
	if lanes.is_empty():
		return

	# The first time, fill the streets at once; after that, trickle in out of view.
	var first_fill := not _filled_once
	_filled_once = true
	var budget := max_pedestrians if first_fill else spawns_per_update
	var camera := get_viewport().get_camera_3d()
	for attempt in budget * (20 if first_fill else 4):
		if budget <= 0 or pedestrians.size() >= max_pedestrians:
			break
		var lane: PackedVector3Array = lanes.pick_random()
		var segment := randi() % (lane.size() - 1)
		var t := randf()
		var point := lane[segment].lerp(lane[segment + 1], t)
		var distance := point.distance_to(center)
		if distance < spawn_range.x or distance > spawn_range.y:
			continue
		if not first_fill and distance < VISIBLE_SPAWN_DISTANCE and camera \
				and camera.is_position_in_frustum(WorldOrigin.to_local(point)):
			continue
		var pedestrian: Pedestrian = PEDESTRIAN_SCENE.instantiate()
		add_child(pedestrian)
		pedestrian.setup(hero, lane, segment, t)
		pedestrians.append(pedestrian)
		budget -= 1


func _on_danger(world_position: Vector3, radius: float) -> void:
	for pedestrian in pedestrians:
		if pedestrian.world_position.distance_to(world_position) < radius:
			pedestrian.scare(world_position)
