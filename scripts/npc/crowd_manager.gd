class_name CrowdManager
extends Node3D
## Keeps pedestrians on the sidewalks around the hero: spawns them out of
## sight, removes them once far away, and sends them running from danger.
## They walk where the shops are: each newcomer starts at one of a few random
## spots on the walking lanes nearby, the likelier the busier the city is
## there (CityStreamer.busyness_at(): shops, subway stairs, newsstands,
## plazas), and ahead of the camera rather than behind it (while the streets
## first fill, where it sees). Around busy streets there are up to busy_crowd
## times as many. Times Square is busier still: around its plazas there are
## plaza_crowd times as many, most of them on the plazas' own walking lanes.
## ?peds=N sets how many (default max_pedestrians).

const PEDESTRIAN_SCENE := preload("res://scenes/npc/pedestrian.tscn")
const UPDATE_INTERVAL := 0.5
## Above this height the street is too far below to bother with pedestrians.
const MAX_SPAWN_ALTITUDE := 150.0
## Closer than this, don't spawn where the camera can see.
const VISIBLE_SPAWN_DISTANCE := 90.0
## A newcomer's spot is one of this many random ones, each as likely as
## BUSY_BASE plus how busy it is there (busyness_at(): about 1 a shop, 20-60
## on shopping streets, 0-5 on others), times AHEAD_WEIGHT if it's ahead of
## the camera (within about 60 degrees of where it looks), or SEEN_WEIGHT if
## the camera sees it while the streets first fill.
const CHOICES := 10
const BUSY_BASE := 4.0
const AHEAD_COS := 0.5
const AHEAD_WEIGHT := 2.0
const SEEN_WEIGHT := 8.0
## How busy the streets around the hero are (busyness_at() over 7x7 squares,
## per 3x3) where busy_crowd applies in full.
const BUSY_FULL := 30.0
## Times Square's sign district: meters along and across Manhattan's avenues
## from 46th Street and Broadway (tools/citygen/props.py's SIGN_ALONG and
## SIGN_ACROSS), where the plazas are. The crowd is thicker within
## PLAZA_REACH of it, and PLAZA_SPAWN_SHARE of newcomers start on lanes in it.
const SIGN_ALONG := Vector2(-330.0, 420.0)
const SIGN_ACROSS := Vector2(-120.0, 110.0)
const PLAZA_REACH := 60.0
const PLAZA_SPAWN_SHARE := 0.75
## With ?stats, how often the crowd is logged (s).
const LOG_INTERVAL := 2.0

@export var city: CityStreamer
@export var hero: Hero
@export var max_pedestrians := 45
@export var spawn_range := Vector2(35.0, 130.0)
@export var despawn_distance := 170.0
@export var spawns_per_update := 6
## How many times as many pedestrians around busy streets (Quality: fewer on
## phones and tablets), and around Times Square.
@export var busy_crowd := 1.5
@export var plaza_crowd := 1.5

var pedestrians: Array[Pedestrian] = []
var _cooldown := 0.0
var _filled_once := false
var _limit := 0
var _log_stats := false
var _log_cooldown := 0.0


func _ready() -> void:
	if LaunchOptions.has("peds"):
		max_pedestrians = int(LaunchOptions.get_string("peds"))
	_log_stats = LaunchOptions.has("stats")
	Combat.danger.connect(_on_danger)


func _process(delta: float) -> void:
	if _log_stats:
		_log_cooldown -= delta
		if _log_cooldown <= 0.0:
			_log_cooldown = LOG_INTERVAL
			print("[crowd] %d pedestrians (%d in sight), up to %d here" % [pedestrians.size(), _count_in_sight(), _limit])
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
	var limit := _limit_at(center)
	_limit = limit
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
	var eye := Vector2.ZERO
	var heading := Vector2.ZERO
	if camera:
		var at := WorldOrigin.to_world(camera.global_position)
		eye = Vector2(at.x, at.z)
		heading = Vector2(-camera.global_basis.z.x, -camera.global_basis.z.z)
		heading = heading.normalized() if heading.length() > 0.1 else Vector2.ZERO
	var choices: Array[Array] = []  # [lane, segment, t, weight]
	var total := 0.0
	for attempt in budget * CHOICES * (8 if first_fill else 2):
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
		var seen := camera != null and _sees(camera, point)
		if seen and not first_fill and distance < VISIBLE_SPAWN_DISTANCE:
			continue
		var weight := BUSY_BASE + city.busyness_at(point)
		var to := Vector2(point.x, point.z) - eye
		if seen and first_fill:
			weight *= SEEN_WEIGHT
		elif to.dot(heading) > AHEAD_COS * to.length():
			weight *= AHEAD_WEIGHT
		choices.append([lane, segment, t, weight])
		total += weight
		if choices.size() == CHOICES:
			_add(choices, total)
			choices.clear()
			total = 0.0
			budget -= 1
	if not choices.is_empty() and budget > 0 and pedestrians.size() < limit:
		_add(choices, total)


## Adds a pedestrian at one of `choices` ([lane, segment, t, weight] each),
## picked by weight (`total` is theirs).
func _add(choices: Array[Array], total: float) -> void:
	var roll := randf() * total
	var choice: Array = choices[choices.size() - 1]
	for candidate in choices:
		roll -= candidate[3]
		if roll < 0.0:
			choice = candidate
			break
	var pedestrian: Pedestrian = PEDESTRIAN_SCENE.instantiate()
	add_child(pedestrian)
	pedestrian.setup(hero, choice[0], choice[1], choice[2])
	pedestrians.append(pedestrian)


## Whether the camera sees someone standing at a world position: near enough
## to be drawn, in its view and not behind a building.
func _sees(camera: Camera3D, world_point: Vector3) -> bool:
	var head := WorldOrigin.to_local(world_point) + Vector3.UP * 1.5
	if not camera.is_position_in_frustum(head) or camera.global_position.distance_to(head) > Pedestrian.VISIBLE_DISTANCE:
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, head, CityStreamer.COLLISION_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Whether a world position is in Times Square's sign district, or within
## `margin` meters of it.
static func in_sign_district(world_position: Vector3, margin := 0.0) -> bool:
	# Godot's x is east and z south; the avenues run 29 degrees east of north.
	var along := 0.485 * world_position.x - 0.875 * world_position.z
	var across := 0.875 * world_position.x + 0.485 * world_position.z
	return along >= SIGN_ALONG.x - margin and along <= SIGN_ALONG.y + margin \
			and across >= SIGN_ACROSS.x - margin and across <= SIGN_ACROSS.y + margin


## Changes how many pedestrians there are (Quality, while playing): more
## come in over the next updates, out of sight; fewer leave at once, the
## furthest from the hero first.
func set_max_pedestrians(count: int) -> void:
	max_pedestrians = maxi(count, 0)
	var center := hero.world_position()
	var limit := _limit_at(center)
	_limit = limit
	_cooldown = 0.0
	if pedestrians.size() <= limit:
		return
	pedestrians.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool:
		return a.world_position.distance_squared_to(center) < b.world_position.distance_squared_to(center))
	while pedestrians.size() > limit:
		pedestrians.pop_back().queue_free()


## How many pedestrians there may be around a world position: more around
## busy streets, and more again around Times Square's plazas.
func _limit_at(center: Vector3) -> int:
	if in_sign_district(center, PLAZA_REACH):
		return roundi(max_pedestrians * plaza_crowd)
	var busy := clampf(city.busyness_at(center, 3) * (9.0 / 49.0) / BUSY_FULL, 0.0, 1.0)
	return roundi(max_pedestrians * lerpf(1.0, busy_crowd, busy))


## How many pedestrians the camera sees (for ?stats).
func _count_in_sight() -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0
	var seen := 0
	for pedestrian in pedestrians:
		if _sees(camera, pedestrian.world_position):
			seen += 1
	return seen


func _on_danger(world_position: Vector3, radius: float) -> void:
	for pedestrian in pedestrians:
		if pedestrian.world_position.distance_to(world_position) < radius:
			pedestrian.scare(world_position)
