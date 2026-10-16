class_name PlayerSync
extends Node
## The other players in co-op. Shows a copy of each one's hero, moved to match
## what their game sends 20 times a second (drawn a little in the past, so it
## moves smoothly in between), and sends our hero's state to them. The host
## (whoever it is now: see Net) also places players who join next to its hero,
## and keeps the ground loaded around every hero so its thugs have streets to
## stand on.

## The host put our hero next to its own (world position).
signal placed_by_host(world_position: Vector3, facing: float)

const HERO_SCENE := preload("res://scenes/hero/hero.tscn")
const SEND_INTERVAL := 0.05
## Modes, in the order they're numbered when sent.
const MODES: Array[StringName] = [&"OnFoot", &"Flight", &"Swing", &"Melee", &"Dive", &"KnockedOut"]
const GROUNDED := 1
const FROZEN := 2
const CHARGING := 4
const IN_WATER := 8
## Joining players appear this far to the side of the host's hero (meters).
const JOIN_SPACING := 3.0

## Our hero.
@export var hero: Hero
@export var city: CityStreamer

## Copies of the other players' heroes, by player number.
var remote_heroes := {}
var _snapshots := {}  # player number -> SnapshotBuffer
var _send_cooldown := 0.0


func _ready() -> void:
	# After the heroes' own physics, so copies are placed for this tick's drawing.
	process_physics_priority = 10
	Net.player_joined.connect(_add_player)
	Net.player_left.connect(_remove_player)
	Net.state_changed.connect(_on_net_state_changed)
	Net.host_changed.connect(func(id: int) -> void: set_multiplayer_authority(id, false))


func _physics_process(delta: float) -> void:
	if not Net.is_online():
		return
	_send_cooldown -= delta
	if _send_cooldown <= 0.0:
		_send_cooldown = SEND_INTERVAL
		_hero_state.rpc(_encode(hero))
	var foci: Array[Vector3] = []
	for id: int in remote_heroes:
		var copy: Hero = remote_heroes[id]
		_follow(copy, _snapshots[id])
		foci.append(copy.world_position())
	city.extra_foci = foci if Net.is_authority() else ([] as Array[Vector3])


func _encode(source: Hero) -> Array:
	var on_foot := source.get_mode(&"OnFoot") as OnFootMode
	var melee := source.get_mode(&"Melee") as MeleeMode
	var swing := source.get_mode(&"Swing") as SwingMode
	var flags := (GROUNDED if source.is_on_floor() else 0) | (FROZEN if source.frozen else 0) \
		| (CHARGING if on_foot.charging else 0) | (IN_WATER if source.is_in_water() else 0)
	return [Time.get_ticks_msec(), source.world_position(), source.velocity, source.facing,
		MODES.find(source.mode.name), flags, on_foot.charge, source.health, source.hurt_time,
		melee.step, melee.punch_id, WorldOrigin.to_world(swing.anchor), WorldOrigin.to_world(swing.web_point)]


## Moves a copy to where its player's hero was a moment ago.
func _follow(copy: Hero, snapshots: SnapshotBuffer) -> void:
	if snapshots.is_empty():
		return
	var sample := snapshots.sample()
	var older: Array = sample[0]
	var newer: Array = sample[1]
	var weight: float = sample[2]
	var latest := newer if weight >= 0.5 else older
	var was_grounded := copy.remote_grounded
	var fall_speed := -copy.velocity.y
	copy.global_position = WorldOrigin.to_local((older[1] as Vector3).lerp(newer[1], weight))
	copy.velocity = (older[2] as Vector3).lerp(newer[2], weight)
	copy.facing = lerp_angle(older[3], newer[3], weight)
	copy.set_mode(MODES[clampi(latest[4], 0, MODES.size() - 1)], false)
	var flags: int = latest[5]
	copy.remote_grounded = flags & GROUNDED != 0
	copy.frozen = flags & FROZEN != 0
	copy.remote_in_water = flags & IN_WATER != 0
	var on_foot := copy.get_mode(&"OnFoot") as OnFootMode
	on_foot.charging = flags & CHARGING != 0
	on_foot.charge = latest[6]
	copy.health = latest[7]
	copy.hurt_time = latest[8]
	var melee := copy.get_mode(&"Melee") as MeleeMode
	melee.step = clampi(latest[9], 0, MeleeMode.COMBO.size() - 1)
	melee.punch_id = latest[10]
	var swing := copy.get_mode(&"Swing") as SwingMode
	swing.anchor = WorldOrigin.to_local((older[11] as Vector3).lerp(newer[11], weight))
	swing.web_point = WorldOrigin.to_local((older[12] as Vector3).lerp(newer[12], weight))
	if copy.remote_grounded and not was_grounded:
		copy.landed.emit(fall_speed)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _hero_state(state: Array) -> void:
	var snapshots: SnapshotBuffer = _snapshots.get(multiplayer.get_remote_sender_id())
	if snapshots and state.size() == 13:
		snapshots.push(float(state[0]), state)


@rpc("authority", "call_remote", "reliable")
func _place(world_position: Vector3, facing: float) -> void:
	placed_by_host.emit(world_position, facing)


func _add_player(id: int) -> void:
	if remote_heroes.has(id):
		return
	var copy: Hero = HERO_SCENE.instantiate()
	copy.remote_id = id
	copy.frozen = true
	copy.name = "Player%d" % id
	(copy.get_node("Model") as HeroAnimator).suit_color = Net.player_color(id)
	add_child(copy)
	copy.add_child(_name_tag(id))
	remote_heroes[id] = copy
	_snapshots[id] = SnapshotBuffer.new()
	if Net.state == Net.State.HOSTING and Net.is_newcomer(id):
		# Beside our hero, a few meters apart per player.
		var right := Vector3(cos(hero.facing), 0.0, -sin(hero.facing))
		_place.rpc_id(id, hero.world_position() + right * JOIN_SPACING * remote_heroes.size(), hero.facing)


func _remove_player(id: int) -> void:
	var copy: Hero = remote_heroes.get(id)
	if copy:
		Combat.unregister_hero(copy)  # right away: nothing more is sent to this player
		copy.queue_free()
	remote_heroes.erase(id)
	_snapshots.erase(id)


func _on_net_state_changed() -> void:
	if not Net.is_online():
		for id: int in remote_heroes.keys():
			_remove_player(id)
		city.extra_foci = [] as Array[Vector3]
	# Our suit takes our player color, so everyone sees the same colors.
	var animator := hero.get_node("Model") as HeroAnimator
	animator.set_colors(Net.player_color(Net.local_id()), animator.trim_color)


func _name_tag(id: int) -> Label3D:
	var tag := Label3D.new()
	tag.text = Net.player_name(id)
	tag.position = Vector3.UP * 2.3
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = Net.player_color(id).lightened(0.35)
	return tag
