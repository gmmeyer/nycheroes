class_name EncounterDirector
extends Node3D
## Puts gangs of thugs on the streets around our hero, a couple at a time
## (preferably ahead of where the player is looking or heading, so they see
## them coming), and clears gangs and bodies away once every hero is far off.
## ?gangs=N sets how many gangs may be about a hero.
##
## In co-op every game runs the gangs it put down around its own hero, and
## puts none down where enough gangs are about already, whoever runs them. It
## tells each other player about its thugs near their hero: when one comes
## into range, where it is and what it's doing 20 times a second, and when it
## leaves range or is cleared away. In their games those thugs are copies
## (Thug.puppet, Thug.run_by) that follow along; hits on a copy go to the game
## running it (see Combat). So a game runs the thugs near its own hero, and
## any that stayed with another player's hero it left behind, for which it
## keeps the ground around that hero loaded (CityStreamer.extra_foci): players
## far apart cost each other no more than their heroes' states. (When the host
## ran every thug, seven players across the city tripled its physics time and
## took 160 MB more, and each moving player made it stream tiles: see ROADMAP
## step 5.)
##
## When a player leaves the room, the host's game takes their thugs over, so
## fights carry on (the new host's, if the host left): its copies become
## thugs it runs, and every other player hands it their copies (thugs it may
## never have heard of). Thugs keep their numbers: each game numbers its own
## k * ID_STRIDE + its player number, with k starting from the clock (so a
## newcomer given a departed player's number doesn't use theirs again) and
## above every number it has seen.

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
## Numbers sent per thug in each update (its number goes separately).
const STATE_SIZE := 8
## Thug numbers are k * ID_STRIDE + the number of the player whose game made
## the thug (more than there can be players).
const ID_STRIDE := 16
## A game's first k is the clock's seconds (wrapping after this many) times
## IDS_PER_SECOND: later games start above the numbers earlier ones give out,
## unless those make thugs faster than that.
const CLOCK_WRAP := 1 << 24
const IDS_PER_SECOND := 4
## The host waits this long (seconds) for a player's copies before telling
## them which thugs there are, once it has taken over a departed player's.
const HANDOVER_WAIT := 3.0

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

var _gangs: Array[Array] = []  # the gangs we run
var _bodies: Array[Thug] = []
var _spawn_cooldown := 2.0  # seconds until our hero can get another gang
var _update_cooldown := 0.0
var _share_cooldown := 0.0
var _gang_count := 0
var _next_id := 1  # k for our next thug number (see ID_STRIDE)
var _shared := {}  # player number -> {thug net id: true}: the thugs of ours that player has
var _told := {}  # thug net id -> true: thugs of ours some player has had
var _left: Array[int] = []  # players who just left the room, whose thugs the host takes over
var _awaiting := {}  # (host) player number -> msec: until then, wait for their copies before sharing
var _handed := {}  # (host) player number -> msec: when their copies last came
var _handovers := {}  # player number -> copies they handed over before we knew we're the host
var _handover: Array = []  # copies of departed players' thugs, for the host
var _handover_due := false  # (players) _handover is still to go to the host


func _ready() -> void:
	if LaunchOptions.has("gangs"):
		max_gangs = int(LaunchOptions.get_string("gangs"))
	_next_id = (int(Time.get_unix_time_from_system()) % CLOCK_WRAP) * IDS_PER_SECOND + 1
	Combat.thug_defeated.connect(_on_thug_defeated)
	Net.state_changed.connect(_on_net_state_changed)
	Net.left_room.connect(_on_left_room)
	Net.readmitted.connect(_on_readmitted)
	Net.player_left.connect(func(id: int) -> void: _shared.erase(id))


func _process(delta: float) -> void:
	if _handover_due and Net.peers().has(Net.host_id):
		_handover_due = false
		_hand_over.rpc_id(Net.host_id, _handover)
		_handover = []
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
	for thug in Combat.thugs:
		if thug.frozen and city.has_collision_at(WorldOrigin.to_world(thug.global_position)):
			thug.frozen = false
	_spawn_near_hero()
	city.extra_foci = _foci()


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
		thug.net_id = _next_id * ID_STRIDE + Net.local_id() % ID_STRIDE
		_next_id += 1
		add_child(thug)
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(target if target else hero, _gang_count, TAU * k / count + randf() * 0.5)
		gang.append(thug)
	_gangs.append(gang)
	_gang_count += 1
	return gang


## Our gangs go once every hero is far off (other players' too: one may still
## be fighting a gang we left behind).
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


func _spawn_near_hero() -> void:
	_spawn_cooldown -= UPDATE_INTERVAL
	var center := hero.world_position()
	var above_street := center.y - city.ground_height_at(center, 0.5)
	if _spawn_cooldown > 0.0 or hero.frozen or not above_street < MAX_SPAWN_ALTITUDE or _gangs_near(center) >= max_gangs:
		return
	if _spawn_gang_near(hero, center):
		_spawn_cooldown = respawn_delay


## Gangs with someone still standing within reach of a world position: ours,
## and other players' we have copies of.
func _gangs_near(center: Vector3) -> int:
	var gangs := {}
	for thug in Combat.thugs:
		if not thug.is_down() and WorldOrigin.to_world(thug.global_position).distance_to(center) < despawn_distance:
			gangs[Vector2i(thug.run_by if thug.puppet else 0, thug.gang)] = true
	return gangs.size()


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


## Where the player is likely looking: the camera's direction.
func _ahead_of(target: Hero) -> Vector3:
	var ahead := target.forward()
	var camera := get_viewport().get_camera_3d()
	if camera:
		ahead = -camera.global_basis.z
	return Vector3(ahead.x, 0.0, ahead.z).normalized()


## Other players' heroes our thugs are near (thugs that stayed with them, or
## that we took over): the ground around them stays loaded for those thugs.
func _foci() -> Array[Vector3]:
	var foci: Array[Vector3] = []
	for other in Combat.heroes:
		if not other.is_remote():
			continue
		var at := other.world_position()
		for thug in Combat.thugs:
			if not thug.puppet and WorldOrigin.to_world(thug.global_position).distance_to(at) < despawn_distance:
				foci.append(at)
				break
	return foci


## Tells each other player about our thugs near their hero.
func _share_thugs() -> void:
	var now := Time.get_ticks_msec()
	var connected := Net.peers()
	for player in Combat.heroes:
		if not player.is_remote() or not connected.has(player.remote_id):
			continue
		if _awaiting.has(player.remote_id):
			if now < _awaiting[player.remote_id]:
				continue
			_awaiting.erase(player.remote_id)
		var first := not _shared.has(player.remote_id)
		var known: Dictionary = _shared.get_or_add(player.remote_id, {})
		var center := player.world_position()
		var arrivals: Array = []
		var leaving := PackedInt32Array()
		var ids := PackedInt32Array()
		var states := PackedFloat32Array()
		var present := {}
		for thug in Combat.thugs:
			if thug.puppet:
				continue
			present[thug.net_id] = true
			var at := WorldOrigin.to_world(thug.global_position)
			var distance := at.distance_to(center)
			if known.has(thug.net_id):
				if distance > FORGET_RANGE:
					known.erase(thug.net_id)
					leaving.append(thug.net_id)
				elif not thug.is_down():
					ids.append(thug.net_id)
					states.append_array([at.x, at.y, at.z, thug.facing(), thug.health,
						thug.anim_index, thug.anim_speed, thug.anim_restarts])
			elif distance < SHARE_RANGE:
				known[thug.net_id] = true
				_told[thug.net_id] = true
				arrivals.append(_describe(thug))
		for net_id: int in known.keys():
			if not present.has(net_id):
				known.erase(net_id)
				leaving.append(net_id)
		if first or not arrivals.is_empty():
			_add_thugs.rpc_id(player.remote_id, arrivals, first)
		if not leaving.is_empty():
			_remove_thugs.rpc_id(player.remote_id, leaving)
		if not ids.is_empty():
			_thug_states.rpc_id(player.remote_id, now, ids, states)


## What another game needs to set a thug up: [net id, world position,
## facing, gang, health, down].
func _describe(thug: Thug) -> Array:
	return [thug.net_id, WorldOrigin.to_world(thug.global_position), thug.facing(), thug.gang, thug.health, thug.is_down()]


## A thug as another game described it: a copy of one player `runner`'s game
## runs, or (runner 0) one we run from now on.
func _spawn_thug(description: Array, runner: int) -> Thug:
	var thug: Thug = THUG_SCENE.instantiate()
	thug.net_id = int(description[0])
	thug.puppet = runner != 0
	thug.run_by = runner
	add_child(thug)
	thug.global_position = WorldOrigin.to_local(description[1])
	thug.setup_described(int(description[3]), float(description[2]), float(description[4]), bool(description[5]))
	return thug


## Keeps our own numbering above every thug and gang we've seen, so the thugs
## and gangs we make get new numbers.
func _saw(net_id: int, gang: int) -> void:
	_next_id = maxi(_next_id, net_id / ID_STRIDE + 1)
	_gang_count = maxi(_gang_count, gang + 1)


func _remove(thug: Thug) -> void:
	Combat.unregister(thug)  # right away, so a new thug can't be confused with it
	thug.queue_free()


## Another game's thugs came into range: descriptions (see _describe). `only`
## comes with its first word to us (a new host's too): these are all the thugs
## it runs around us, so copies of any others of its go.
@rpc("any_peer", "call_remote", "reliable")
func _add_thugs(arrivals: Array, only: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if only:
		var listed := {}
		for data: Array in arrivals:
			listed[int(data[0])] = true
		for thug in Combat.thugs.duplicate():
			if thug.puppet and thug.run_by == sender and not listed.has(thug.net_id):
				_remove(thug)
	for data: Array in arrivals:
		_saw(int(data[0]), int(data[3]))
		var thug := Combat.thug_by_id(int(data[0]))
		if thug == null:
			_spawn_thug(data, sender)
		elif thug.puppet and thug.run_by != sender:
			thug.follow_new_runner(sender)  # (taken over from a player who left)


@rpc("any_peer", "call_remote", "reliable")
func _remove_thugs(net_ids: PackedInt32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	for net_id in net_ids:
		var thug := Combat.thug_by_id(net_id)
		if thug and thug.puppet and thug.run_by == sender:
			_remove(thug)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _thug_states(sender_msec: int, net_ids: PackedInt32Array, states: PackedFloat32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	for k in mini(net_ids.size(), states.size() / STATE_SIZE):
		var thug := Combat.thug_by_id(net_ids[k])
		var s := k * STATE_SIZE
		if thug and thug.puppet and thug.run_by == sender and not thug.is_down():
			thug.push_snapshot(sender_msec, Vector3(states[s], states[s + 1], states[s + 2]), states[s + 3],
				states[s + 4], int(states[s + 5]), states[s + 6], int(states[s + 7]))


## Leaving a room (or not getting into one), copies of other players' thugs
## go; ours stay, and stay ours in a room we go into.
func _on_net_state_changed() -> void:
	_shared.clear()
	if Net.is_online():
		return
	_told.clear()
	_left.clear()
	_awaiting.clear()
	_handed.clear()
	_handovers.clear()
	_handover.clear()
	_handover_due = false
	for thug in Combat.thugs.duplicate():
		if thug.puppet:
			_remove(thug)


## A player left the room: the host takes over the thugs their game ran, once
## we know who hosts now (the server says in the same message).
func _on_left_room(id: int) -> void:
	if _left.is_empty():
		_take_over_left.call_deferred()
	_left.append(id)


func _take_over_left() -> void:
	var left := _left.duplicate()
	_left.clear()
	if not Net.is_online():
		return
	var orphans := Combat.thugs.filter(func(thug: Thug) -> bool: return thug.puppet and left.has(thug.run_by))
	if Net.host_id != Net.local_id():
		# The host takes them: it gets our copies, and its updates run on its
		# own clock. (Copies that came before we knew it was the host were for
		# nothing.)
		_handovers.clear()
		for thug: Thug in orphans:
			thug.follow_new_runner(Net.host_id)
			_handover.append(_describe(thug))
		_handover_due = true
		return
	# We run them now, and the others' copies are on their way (_hand_over).
	# Until a player's come (or HANDOVER_WAIT passes), we hold off telling them
	# which thugs there are. (Copies we had for the old host are among ours.)
	_handover.clear()
	_handover_due = false
	var now := Time.get_ticks_msec()
	for id in Net.peers():
		if not _handovers.has(id) and now - int(_handed.get(id, -100000)) > HANDOVER_WAIT * 1000.0:
			_awaiting[id] = now + int(HANDOVER_WAIT * 1000.0)
	for thug: Thug in orphans:
		_saw(thug.net_id, thug.gang)
		_run(thug)
	for id: int in _handovers:
		_adopt(_handovers[id])
	_handovers.clear()
	_shared.clear()
	_regroup()
	print("[encounters] took over %d thugs of player %s" % [orphans.size(), ", ".join(left.map(str))])


## The room let us go for a moment (our socket to the signaling server
## dropped), so the host took over our thugs that anyone had: ours of those
## go (its copies come instead), and so do copies of others' (the others
## connect to us again, and tell us about theirs).
func _on_readmitted() -> void:
	for thug in Combat.thugs.duplicate():
		if thug.puppet or _told.has(thug.net_id):
			_remove(thug)
	_told.clear()
	_shared.clear()


## Our game runs this thug from now on. It waits where it is until we have
## the ground under it (its game may have run it far from us).
func _run(thug: Thug) -> void:
	thug.take_over()
	if not thug.is_down() and not city.has_collision_at(WorldOrigin.to_world(thug.global_position)):
		thug.frozen = true


## A player's copies (descriptions, see _describe), handed to the host:
## thugs we hadn't heard of join ours, and ones they saw go down go down here
## too (their hit may have gone to the player who left as they left).
func _adopt(thugs: Array) -> void:
	for data: Array in thugs:
		_saw(int(data[0]), int(data[3]))
		var thug := Combat.thug_by_id(int(data[0]))
		if thug == null:
			_run(_spawn_thug(data, 0))
		elif bool(data[5]) and not thug.is_down():
			thug.go_down(Vector3.ZERO)


## Our gangs and bodies, from the thugs we run now (after taking some over).
func _regroup() -> void:
	var gangs := {}
	for thug in Combat.thugs:
		if thug.puppet:
			continue
		gangs.get_or_add(thug.gang, []).append(thug)
		if thug.is_down() and not _bodies.has(thug):
			_bodies.append(thug)
	_gangs.assign(gangs.values())


## To the host: a player's copies of the thugs of players who left, to carry
## on with (sent even when there are none, so the host needn't wait).
@rpc("any_peer", "call_remote", "reliable")
func _hand_over(thugs: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_handed[sender] = Time.get_ticks_msec()
	if Net.state != Net.State.HOSTING or not _left.is_empty():
		# The server's word that we're the host (or that the player left) is
		# on its way.
		_handovers.get_or_add(sender, []).append_array(thugs)
		return
	_adopt(thugs)
	_regroup()
	_awaiting.erase(sender)


func _on_thug_defeated(thug: Thug) -> void:
	if thug.puppet:
		return  # the game running it clears bodies away
	_bodies.append(thug)
	while _bodies.size() > max_bodies:
		var oldest: Thug = _bodies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
