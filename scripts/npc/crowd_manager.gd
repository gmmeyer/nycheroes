class_name CrowdManager
extends Node3D
## Keeps pedestrians on the sidewalks around the hero: spawns them out of
## sight, removes them once far away, and sends them running from danger.
## Times Square is busier: around its plazas there are plaza_crowd times as
## many, most of them on the plazas' own walking lanes.
## ?peds=N sets how many (default max_pedestrians).

const PEDESTRIAN_SCENE := preload("res://scenes/npc/pedestrian.tscn")
const UPDATE_INTERVAL := 0.5
## Above this height the street is too far below to bother with pedestrians.
const MAX_SPAWN_ALTITUDE := 150.0
## Closer than this, don't spawn where the camera can see.
const VISIBLE_SPAWN_DISTANCE := 90.0
## Times Square's sign district: meters along and across Manhattan's avenues
## from 46th Street and Broadway (tools/citygen/props.py's SIGN_ALONG and
## SIGN_ACROSS), where the plazas are. The crowd is thicker within
## PLAZA_REACH of it, and PLAZA_SPAWN_SHARE of newcomers start on lanes in it.
const SIGN_ALONG := Vector2(-330.0, 420.0)
const SIGN_ACROSS := Vector2(-120.0, 110.0)
const PLAZA_REACH := 60.0
const PLAZA_SPAWN_SHARE := 0.75

@export var city: CityStreamer
@export var hero: Hero
@export var max_pedestrians := 45
@export var spawn_range := Vector2(35.0, 130.0)
@export var despawn_distance := 170.0
@export var spawns_per_update := 6
## How many times as many pedestrians around Times Square.
@export var plaza_crowd := 1.5

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
	var above_street := center.y - city.ground_height_at(center, 0.5)
	var crowded := in_sign_district(center, PLAZA_REACH)
	var limit := roundi(max_pedestrians * (plaza_crowd if crowded else 1.0))
	if hero.frozen or not above_street <= MAX_SPAWN_ALTITUDE or pedestrians.size() >= limit:
		return
	var lanes := city.lanes_near(center, spawn_range.y)
	if lanes.is_empty():
		return
	var plaza_lanes: Array[PackedVector3Array] = []
	if crowded:
		for lane in lanes:
			if in_sign_district(lane[lane.size() / 2]):
				plaza_lanes.append(lane)

	# The first time, fill the streets at once; after that, trickle in out of view.
	var first_fill := not _filled_once
	_filled_once = true
	var budget := limit if first_fill else spawns_per_update
	var camera := get_viewport().get_camera_3d()
	for attempt in budget * (20 if first_fill else 4):
		if budget <= 0 or pedestrians.size() >= limit:
			break
		var pool := plaza_lanes if not plaza_lanes.is_empty() and randf() < PLAZA_SPAWN_SHARE else lanes
		var lane: PackedVector3Array = pool.pick_random()
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


## Whether a world position is in Times Square's sign district, or within
## `margin` meters of it.
static func in_sign_district(world_position: Vector3, margin := 0.0) -> bool:
	# Godot's x is east and z south; the avenues run 29 degrees east of north.
	var along := 0.485 * world_position.x - 0.875 * world_position.z
	var across := 0.875 * world_position.x + 0.485 * world_position.z
	return along >= SIGN_ALONG.x - margin and along <= SIGN_ALONG.y + margin \
			and across >= SIGN_ACROSS.x - margin and across <= SIGN_ACROSS.y + margin


func _on_danger(world_position: Vector3, radius: float) -> void:
	for pedestrian in pedestrians:
		if pedestrian.world_position.distance_to(world_position) < radius:
			pedestrian.scare(world_position)
