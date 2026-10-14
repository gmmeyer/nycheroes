class_name EncounterDirector
extends Node3D
## Puts gangs of thugs on the streets around each hero, a couple at a time
## (preferably ahead of where the player is looking or heading, so they see
## them coming), and clears gangs and bodies away once every hero is far off.
## ?gangs=N sets how many gangs each hero gets.
##
## In co-op the host's game runs every thug. It tells each other player about
## the thugs near their hero: when one comes into range, where it is and what
## it's doing 20 times a second, and when it leaves range or is cleared away.
## In those players' games the thugs are copies that follow along.

const THUG_SCENE := preload("res://scenes/npc/thug.tscn")
const UPDATE_INTERVAL := 0.5
const MAX_SPAWN_ALTITUDE := 150.0
## Spacing between gang members along the sidewalk.
const SPACING := 1.6
## Gang members are placed on the ground found within this far above or
## below where they're asked to go (streets slope).
const GROUND_SEARCH := 6.0
## Players hear about thugs within this distance of their hero, and stop
## hearing about them past FORGET_RANGE.
const SHARE_RANGE := 400.0
const FORGET_RANGE := 500.0
const SHARE_INTERVAL := 0.05
## Numbers sent per thug in each update.
const STATE_SIZE := 9

@export var city: CityStreamer
## Our hero.
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
var _cooldowns := {}  # hero instance id -> seconds until that hero can get another gang
var _update_cooldown := 0.0
var _share_cooldown := 0.0
var _gang_count := 0
var _next_id := 1
var _shared := {}  # player number -> {thug net id: true}: the thugs that player has
var _was_authority := true


func _ready() -> void:
	if LaunchOptions.has("gangs"):
		max_gangs = int(LaunchOptions.get_string("gangs"))
	Combat.thug_defeated.connect(_on_thug_defeated)
	Net.state_changed.connect(_on_net_state_changed)
	Net.player_left.connect(func(id: int) -> void: _shared.erase(id))


func _process(delta: float) -> void:
	if not Net.is_authority():
		return
	if Net.is_online():
		_share_cooldown -= delta
		if _share_cooldown <= 0.0:
			_share_cooldown = SHARE_INTERVAL
			_share_thugs()
	_update_cooldown -= delta
	if _update_cooldown > 0.0:
		return
	_update_cooldown = UPDATE_INTERVAL
	_clear_far_gangs()
	for target in Combat.heroes:
		_spawn_near(target)


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


## Places a gang of `count` thugs in a line along `direction`, centered on a
## world position, after `target` (our hero if null). Used by the spawner,
## and by demos and tests.
func spawn_gang(world_center: Vector3, count: int, direction: Vector3, target: Hero = null) -> Array[Thug]:
	var gang: Array[Thug] = []
	for k in count:
		var spot := world_center + direction * (k - (count - 1) * 0.5) * SPACING
		var ground := city.ground_height_at(spot, GROUND_SEARCH)
		if ground > spot.y - GROUND_SEARCH:
			spot.y = ground
		var thug: Thug = THUG_SCENE.instantiate()
		thug.net_id = _next_id
		_next_id += 1
		add_child(thug)
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(target if target else hero, _gang_count, TAU * k / count + randf() * 0.5)
		gang.append(thug)
	_gangs.append(gang)
	_gang_count += 1
	return gang


func _clear_far_gangs() -> void:
	var centers: Array[Vector3] = []
	for target in Combat.heroes:
		centers.append(target.world_position())
	for gang: Array in _gangs.duplicate():
		var members: Array = gang.filter(func(thug: Thug) -> bool: return is_instance_valid(thug))
		var far: bool = members.all(func(thug: Thug) -> bool:
			var at := WorldOrigin.to_world(thug.global_position)
			return centers.all(func(center: Vector3) -> bool: return at.distance_to(center) > despawn_distance))
		if members.is_empty() or far:
			for thug: Thug in members:
				thug.queue_free()
			_gangs.erase(gang)


func _spawn_near(target: Hero) -> void:
	var key := target.get_instance_id()
	var cooldown: float = _cooldowns.get(key, 2.0) - UPDATE_INTERVAL
	_cooldowns[key] = cooldown
	var center := target.world_position()
	var above_street := center.y - city.ground_height_at(center, 0.5)
	if cooldown > 0.0 or target.frozen or not above_street < MAX_SPAWN_ALTITUDE or _gangs_near(center) >= max_gangs:
		return
	if _spawn_gang_near(target, center):
		_cooldowns[key] = respawn_delay


## Gangs with someone still standing within reach of a world position.
func _gangs_near(center: Vector3) -> int:
	var count := 0
	for gang: Array in _gangs:
		if gang.any(func(thug: Thug) -> bool:
				return is_instance_valid(thug) and not thug.is_down() \
					and WorldOrigin.to_world(thug.global_position).distance_to(center) < despawn_distance):
			count += 1
	return count


func _spawn_gang_near(target: Hero, center: Vector3) -> bool:
	var lanes := city.lanes_near(center, spawn_range.y)
	if lanes.is_empty():
		return false
	var ahead := _ahead_of(target)
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

		spawn_gang(point, randi_range(gang_size.x, gang_size.y), along.normalized(), target)
		return true
	return false


## Where a hero's player is likely looking: the camera's direction for ours,
## the way the hero is heading (or facing) for other players'.
func _ahead_of(target: Hero) -> Vector3:
	var ahead := target.forward()
	var camera := get_viewport().get_camera_3d()
	if not target.is_remote() and camera:
		ahead = -camera.global_basis.z
	elif target.horizontal_speed() > 1.0:
		ahead = target.velocity
	return Vector3(ahead.x, 0.0, ahead.z).normalized()


## On the host: tells each other player about the thugs near their hero.
func _share_thugs() -> void:
	var now := Time.get_ticks_msec()
	var connected := Net.peers()
	for player in Combat.heroes:
		if not player.is_remote() or not connected.has(player.remote_id):
			continue
		var known: Dictionary = _shared.get_or_add(player.remote_id, {})
		var center := player.world_position()
		var arrivals: Array = []
		var leaving := PackedInt32Array()
		var states := PackedFloat32Array()
		var present := {}
		for thug in Combat.thugs:
			present[thug.net_id] = true
			var at := WorldOrigin.to_world(thug.global_position)
			var distance := at.distance_to(center)
			if known.has(thug.net_id):
				if distance > FORGET_RANGE:
					known.erase(thug.net_id)
					leaving.append(thug.net_id)
				elif not thug.is_down():
					states.append_array([thug.net_id, at.x, at.y, at.z, thug.facing(), thug.health,
						thug.anim_index, thug.anim_speed, thug.anim_restarts])
			elif distance < SHARE_RANGE:
				known[thug.net_id] = true
				arrivals.append([thug.net_id, at, thug.facing(), thug.gang, thug.health, thug.is_down()])
		for net_id: int in known.keys():
			if not present.has(net_id):
				known.erase(net_id)
				leaving.append(net_id)
		if not arrivals.is_empty():
			_add_thugs.rpc_id(player.remote_id, arrivals)
		if not leaving.is_empty():
			_remove_thugs.rpc_id(player.remote_id, leaving)
		if not states.is_empty():
			_thug_states.rpc_id(player.remote_id, now, states)


## Thugs came into range: [net id, world position, facing, gang, health, down] each.
@rpc("authority", "call_remote", "reliable")
func _add_thugs(arrivals: Array) -> void:
	for data: Array in arrivals:
		if Combat.thug_by_id(int(data[0])):
			continue
		var thug: Thug = THUG_SCENE.instantiate()
		thug.net_id = int(data[0])
		thug.puppet = true
		add_child(thug)
		thug.global_position = WorldOrigin.to_local(data[1])
		thug.setup_copy(int(data[3]), float(data[2]), float(data[4]), bool(data[5]))


@rpc("authority", "call_remote", "reliable")
func _remove_thugs(net_ids: PackedInt32Array) -> void:
	for net_id in net_ids:
		var thug := Combat.thug_by_id(net_id)
		if thug:
			Combat.unregister(thug)
			thug.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func _thug_states(sender_msec: int, states: PackedFloat32Array) -> void:
	for k in range(0, states.size() - STATE_SIZE + 1, STATE_SIZE):
		var thug := Combat.thug_by_id(int(states[k]))
		if thug and thug.puppet and not thug.is_down():
			thug.push_snapshot(sender_msec, Vector3(states[k + 1], states[k + 2], states[k + 3]), states[k + 4],
				states[k + 5], int(states[k + 6]), states[k + 7], int(states[k + 8]))


## Joining someone's game, or leaving it, swaps which thugs are around: our
## own, or copies of the host's.
func _on_net_state_changed() -> void:
	_shared.clear()
	if Net.is_authority() == _was_authority:
		return
	_was_authority = Net.is_authority()
	for thug in Combat.thugs.duplicate():
		Combat.unregister(thug)  # right away, so new thugs can reuse its number
		thug.queue_free()
	_gangs.clear()
	_bodies.clear()


func _on_thug_defeated(thug: Thug) -> void:
	if not Net.is_authority():
		return  # the host clears bodies away
	_bodies.append(thug)
	while _bodies.size() > max_bodies:
		var oldest: Thug = _bodies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
