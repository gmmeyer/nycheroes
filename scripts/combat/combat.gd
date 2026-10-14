extends Node
## Resolves fights (autoload "Combat"): heroes hitting thugs, thugs hitting
## heroes, and the danger that sends pedestrians running. Every hit is decided
## here, in one place, which in co-op will run on the host.
##
## Positions passed in are scene space (see WorldOrigin) unless named world_*.

## Something violent happened; bystanders within `radius` should run.
signal danger(world_position: Vector3, radius: float)
## A heavy impact, for camera shake. Strength is 0..1.
signal impact(position: Vector3, strength: float)
signal thug_defeated(thug: Thug)

## Physics layers (bit values): 1 world, 2 heroes, 3 npcs, 4 ragdolls.
const WORLD_LAYER := 1
const HERO_LAYER := 2
const NPC_LAYER := 4
const RAGDOLL_LAYER := 8
## At most this many thugs swing at a hero at once.
const MAX_ATTACKERS := 2

var thugs: Array[Thug] = []
var defeated_count := 0
## Set by the CombatEffects node when it enters the scene.
var effects: CombatEffects

var _attackers := 0
var _hit_stop_end_msec := 0


func _process(_delta: float) -> void:
	if _hit_stop_end_msec > 0 and Time.get_ticks_msec() >= _hit_stop_end_msec:
		_hit_stop_end_msec = 0
		Engine.time_scale = 1.0


func register(thug: Thug) -> void:
	thugs.append(thug)


func unregister(thug: Thug) -> void:
	thugs.erase(thug)


## Hits every standing thug within `radius` of `center`. `push` is the knockback
## velocity; with `launch`, thugs go flying as ragdolls whatever their health.
## Returns how many thugs were hit.
func strike(center: Vector3, radius: float, damage: float, push: Vector3, launch: bool) -> int:
	var hits := 0
	for thug: Thug in thugs.duplicate():
		if thug.is_down() or thug.body_center().distance_to(center) > radius:
			continue
		thug.take_hit(damage, push, launch)
		hits += 1
	if hits > 0:
		danger.emit(WorldOrigin.to_world(center), 35.0)
		hit_stop(0.09 if launch else 0.04)
		if launch:
			impact.emit(center, 0.5)
	return hits


## A ground slam: launches standing thugs away from `center`, harder the closer they are.
func shockwave(center: Vector3, radius: float, damage: float, launch_speed: float) -> void:
	for thug: Thug in thugs.duplicate():
		if thug.is_down():
			continue
		var offset := thug.global_position - center
		offset.y = 0.0
		var distance := offset.length()
		if distance > radius:
			continue
		var away := offset / distance if distance > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var strength := launch_speed * (1.0 - 0.5 * distance / radius)
		thug.take_hit(damage, away * strength + Vector3.UP * strength * 0.6, damage > 0.0)
	if effects:
		effects.shockwave(center, radius)
	danger.emit(WorldOrigin.to_world(center), radius * 6.0)
	impact.emit(center, clampf(radius / 10.0, 0.3, 1.0))


## A thug's punch landing on a hero.
func hurt_hero(hero: Hero, damage: float, push: Vector3) -> void:
	hero.take_hit(damage, push)
	if effects:
		effects.blood_burst(hero.global_position + Vector3.UP * 1.3, push.normalized(), 0.4)
	danger.emit(hero.world_position(), 25.0)


func on_thug_down(thug: Thug) -> void:
	defeated_count += 1
	thug_defeated.emit(thug)


## Thugs ask before swinging, so only a couple attack at once.
func request_attack() -> bool:
	if _attackers >= MAX_ATTACKERS:
		return false
	_attackers += 1
	return true


func release_attack() -> void:
	_attackers = maxi(_attackers - 1, 0)


## Freezes the action for a moment (real time) so hits feel heavy.
func hit_stop(seconds: float) -> void:
	Engine.time_scale = 0.05
	_hit_stop_end_msec = maxi(_hit_stop_end_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
