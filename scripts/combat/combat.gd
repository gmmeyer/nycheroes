extends Node
## Resolves fights (autoload "Combat"): heroes hitting thugs, thugs hitting
## heroes, and the danger that sends pedestrians running.
##
## In co-op each thug runs in one player's game (see EncounterDirector), which
## has the final say on every hit on it. A player hitting a copy of a thug
## sees the hit at once and reports it to the game running the thug, which
## applies it and tells everyone else. Thugs hitting another player's hero are
## sent to that player, whose game owns their hero. What happens somewhere
## (hits, blood, danger) is told only to players whose hero is near it.
##
## Positions passed in are scene space (see WorldOrigin) unless named world_*;
## positions sent between games are always world space.

## Something violent happened; bystanders within `radius` should run.
signal danger(world_position: Vector3, radius: float)
## A heavy impact, for camera shake. Strength is 0..1.
signal impact(position: Vector3, strength: float)
signal thug_defeated(thug: Thug)

## Physics layers (bit values): 1 world, 2 heroes, 3 npcs, 4 ragdolls (and
## 5 water, CityStreamer.WATER_LAYER; 6 trains, Trains.COLLISION_LAYER).
const WORLD_LAYER := 1
const HERO_LAYER := 2
const NPC_LAYER := 4
const RAGDOLL_LAYER := 8
## At most this many thugs swing at a hero at once.
const MAX_ATTACKERS := 2
## Other players hear of what happens within this far of their hero (m): past
## where they have copies of thugs (EncounterDirector.FORGET_RANGE).
const NEAR_EVENTS := 600.0

var thugs: Array[Thug] = []
## Every hero in the game: ours, and copies of the other players' heroes.
var heroes: Array[Hero] = []
var defeated_count := 0
## Set by the CombatEffects node when it enters the scene.
var effects: CombatEffects

var _thugs_by_id := {}
var _attackers := {}  # hero instance id -> thugs swinging at it
var _hit_stop_end_msec := 0


func _process(_delta: float) -> void:
	if _hit_stop_end_msec > 0 and Time.get_ticks_msec() >= _hit_stop_end_msec:
		_hit_stop_end_msec = 0
		Engine.time_scale = 1.0


func register(thug: Thug) -> void:
	thugs.append(thug)
	_thugs_by_id[thug.net_id] = thug


func unregister(thug: Thug) -> void:
	thugs.erase(thug)
	if _thugs_by_id.get(thug.net_id) == thug:
		_thugs_by_id.erase(thug.net_id)


func thug_by_id(net_id: int) -> Thug:
	return _thugs_by_id.get(net_id)


func register_hero(hero: Hero) -> void:
	heroes.append(hero)


func unregister_hero(hero: Hero) -> void:
	heroes.erase(hero)
	_attackers.erase(hero.get_instance_id())


## Our hero hits every standing thug within `radius` of `center`. `push` is the
## knockback velocity; with `launch`, thugs go flying as ragdolls whatever
## their health. Returns how many thugs were hit.
func strike(center: Vector3, radius: float, damage: float, push: Vector3, launch: bool) -> int:
	var hits: Array = []
	for thug: Thug in thugs:
		if not thug.is_down() and thug.body_center().distance_to(center) <= radius:
			hits.append([thug, damage, push, launch])
	_hit_thugs(hits)
	if not hits.is_empty():
		raise_danger(WorldOrigin.to_world(center), 35.0)
		hit_stop(0.09 if launch else 0.04)
		if launch:
			impact.emit(center, 0.5)
	return hits.size()


## Our hero's ground slam: launches standing thugs away from `center`, harder
## the closer they are.
func shockwave(center: Vector3, radius: float, damage: float, launch_speed: float) -> void:
	var hits: Array = []
	for thug: Thug in thugs:
		if thug.is_down():
			continue
		var offset := thug.global_position - center
		offset.y = 0.0
		var distance := offset.length()
		if distance > radius:
			continue
		var away := offset / distance if distance > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var strength := launch_speed * (1.0 - 0.5 * distance / radius)
		hits.append([thug, damage, away * strength + Vector3.UP * strength * 0.6, damage > 0.0])
	_hit_thugs(hits)
	show_shockwave(WorldOrigin.to_world(center), radius)
	raise_danger(WorldOrigin.to_world(center), radius * 6.0)
	impact.emit(center, clampf(radius / 10.0, 0.3, 1.0))


## A thug's punch landing on a hero (decided by the game running the thug).
func hurt_hero(hero: Hero, damage: float, push: Vector3) -> void:
	if hero.is_remote():
		_hurt_our_hero.rpc_id(hero.remote_id, damage, push)
	else:
		hero.take_hit(damage, push)
	show_hero_blood(hero, push.normalized(), 0.4)
	raise_danger(hero.world_position(), 25.0)


func on_thug_down(thug: Thug, launch: Vector3) -> void:
	defeated_count += 1
	thug_defeated.emit(thug)
	if Net.is_online() and not thug.puppet:
		for id in players_near(WorldOrigin.to_world(thug.global_position)):
			_thug_down.rpc_id(id, thug.net_id, launch)


## Thugs ask before swinging, so only a couple attack a hero at once.
func request_attack(hero: Hero) -> bool:
	var key := hero.get_instance_id()
	var count: int = _attackers.get(key, 0)
	if count >= MAX_ATTACKERS:
		return false
	_attackers[key] = count + 1
	return true


func release_attack(hero: Hero) -> void:
	if is_instance_valid(hero):
		var key := hero.get_instance_id()
		_attackers[key] = maxi(_attackers.get(key, 0) - 1, 0)


## Freezes the action for a moment (real time) so hits feel heavy.
func hit_stop(seconds: float) -> void:
	Engine.time_scale = 0.05
	_hit_stop_end_msec = maxi(_hit_stop_end_msec, Time.get_ticks_msec() + int(seconds * 1000.0))


## Tells bystanders here and in every other player's game to run.
func raise_danger(world_position: Vector3, radius: float) -> void:
	danger.emit(world_position, radius)
	for id in players_near(world_position):
		_danger.rpc_id(id, world_position, radius)


func show_shockwave(world_position: Vector3, radius: float) -> void:
	if effects:
		effects.shockwave(WorldOrigin.to_local(world_position), radius)
	for id in players_near(world_position):
		_shockwave.rpc_id(id, world_position, radius)


## Blood from a hit hero, in every game (each draws it on its own copy of the hero).
func show_hero_blood(hero: Hero, direction: Vector3, amount: float) -> void:
	if effects:
		effects.blood_burst(hero.global_position + Vector3.UP * 1.3, direction, amount)
	for id in players_near(hero.world_position()):
		_hero_blood.rpc_id(id, hero.remote_id if hero.is_remote() else Net.local_id(), direction, amount)


## Hits made by our hero: [thug, damage, push, launch] each. Thugs we run take
## them for real (and everyone is told); copies show them at once, and the
## games running them are asked to apply them.
func _hit_thugs(hits: Array) -> void:
	var reports := {}  # player number -> [net id, damage, push, launch] each
	for hit: Array in hits:
		var thug: Thug = hit[0]
		if thug.puppet:
			reports.get_or_add(thug.run_by, []).append([thug.net_id, hit[1], hit[2], hit[3]])
		else:
			_tell_hit(thug, hit[2], hit[3], Net.local_id())  # before it can go down
		thug.take_hit(hit[1], hit[2], hit[3])
	var connected := Net.peers()
	for player: int in reports:
		if connected.has(player):
			_report_hits.rpc_id(player, reports[player])


func _tell_hit(thug: Thug, push: Vector3, launch: bool, attacker: int) -> void:
	for id in players_near(WorldOrigin.to_world(thug.global_position)):
		_thug_hit.rpc_id(id, thug.net_id, push, launch, attacker)


## The other players (connected to us) whose hero is within NEAR_EVENTS of a
## world position.
func players_near(world_position: Vector3) -> Array[int]:
	var near: Array[int] = []
	var connected := Net.peers()
	for hero in heroes:
		if hero.is_remote() and connected.has(hero.remote_id) \
				and hero.world_position().distance_to(world_position) < NEAR_EVENTS:
			near.append(hero.remote_id)
	return near


func _hero_of(player: int) -> Hero:
	for hero in heroes:
		if (hero.remote_id if hero.is_remote() else Net.local_id()) == player:
			return hero
	return null


## Another player hit thugs our game runs. [net id, damage, push, launch] each.
@rpc("any_peer", "call_remote", "reliable")
func _report_hits(reports: Array) -> void:
	var attacker := multiplayer.get_remote_sender_id()
	for report: Array in reports:
		var thug := thug_by_id(int(report[0]))
		if thug == null or thug.puppet or thug.is_down():
			continue
		_tell_hit(thug, report[2], bool(report[3]), attacker)
		thug.take_hit(float(report[1]), report[2], bool(report[3]))


## The game running a thug says someone hit it.
@rpc("any_peer", "call_remote", "reliable")
func _thug_hit(net_id: int, push: Vector3, launch: bool, attacker: int) -> void:
	var thug := thug_by_id(net_id)
	if attacker == Net.local_id() or thug == null or thug.is_down() or thug.run_by != multiplayer.get_remote_sender_id():
		return  # we showed our own hits already
	if effects:
		effects.blood_burst(thug.body_center(), push.normalized(), 1.5 if launch else 0.6)
	GameAudio.play(&"punch_heavy" if launch else &"punch", thug.body_center())


## The game running a thug says it went down.
@rpc("any_peer", "call_remote", "reliable")
func _thug_down(net_id: int, launch: Vector3) -> void:
	var thug := thug_by_id(net_id)
	if thug and thug.puppet and thug.run_by == multiplayer.get_remote_sender_id() and not thug.is_down():
		thug.go_down(launch)


## A thug (whichever game runs it) punched our hero.
@rpc("any_peer", "call_remote", "reliable")
func _hurt_our_hero(damage: float, push: Vector3) -> void:
	var hero := _hero_of(Net.local_id())
	if hero:
		hero.take_hit(damage, push)


@rpc("any_peer", "call_remote", "reliable")
func _hero_blood(player: int, direction: Vector3, amount: float) -> void:
	var hero := _hero_of(player)
	if hero and effects:
		effects.blood_burst(hero.global_position + Vector3.UP * 1.3, direction, amount)


@rpc("any_peer", "call_remote", "reliable")
func _shockwave(world_position: Vector3, radius: float) -> void:
	if effects:
		effects.shockwave(WorldOrigin.to_local(world_position), radius)


@rpc("any_peer", "call_remote", "unreliable")
func _danger(world_position: Vector3, radius: float) -> void:
	danger.emit(world_position, radius)
