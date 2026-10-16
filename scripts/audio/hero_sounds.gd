class_name HeroSounds
extends Node3D
## A hero's sounds (a child of every hero: ours, and the copies of other
## players' heroes): footsteps in step with the run animation (on grass in
## parks, on boards on the piers), jumps and super jump launches, landings
## as heavy as the fall, the rush of air while flying, falling and swinging,
## super speed, webs, punches and dives, swimming, and getting hit. All of
## it is worked out from the hero's state, which copies get from the
## network too, so other players sound the same, from where they are (3-D,
## fading with distance). One-off sounds go through GameAudio; the loops
## (air, super speed, a super jump's charge) are this node's own players.

## Where in the run animations' loops the feet land, and the swim strokes
## come (fractions of the loop; measured from the mannequin's foot bones).
const STEPS := {&"Walk": [0.02, 0.52], &"Jog_Fwd": [0.02, 0.52], &"Sprint": [0.02, 0.55], &"Swim_Fwd": [0.1, 0.6]}
## Landing faster than this (m/s) thumps, faster than LAND_HEAVY thuds
## (Hero.SLAM_SPEED and up slams).
const LAND := 12.0
const LAND_HEAVY := 25.0
## Running faster than this (m/s) is super speed: footsteps patter, and the
## wind of it comes in.
const SUPER_SPEED := 14.0
## Heroes further from the listener than this (m) keep their loops quiet.
const LOOP_RANGE := 200.0
## Which surface is underfoot is looked up this often (s).
const SURFACE_INTERVAL := 0.3
## A loop that fades out keeps playing silently this long (s), so jump after
## jump doesn't restart it (on the web each start copies its buffer).
const LOOP_LINGER := 5.0

enum Loop { AIR_LOW, AIR_HIGH, SPEED, CHARGE }
const LOOP_SOUNDS: Array[StringName] = [&"air_low", &"air_high", &"speed_loop", &"charge_loop"]

var hero: Hero

var _animation: AnimationPlayer
var _loops: Array[LoopVoice] = []
var _mode := &""
var _grounded := true
var _in_water := false
var _punch_id := 0
var _hurt_time := 0.0
var _step_animation := &""
var _step_phase := 0.0
var _swing_rise := 0.0
var _zoom_ready := true
var _surface := &"step_concrete"
var _odd_step := false
var _surface_cooldown := 0.0


func _ready() -> void:
	hero = get_parent() as Hero
	if GameAudio.off():
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	SoundBank.load_all()
	# After the hero's own physics and PlayerSync's update of copies.
	process_physics_priority = 20
	hero.landed.connect(_on_landed)
	hero.hurt.connect(_on_hurt)
	var model := hero.get_node_or_null("Model")
	if model:
		_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for sound in LOOP_SOUNDS:
		var player := AudioStreamPlayer3D.new()
		var entry := SoundBank.entry(sound)
		var files := SoundBank.streams(sound)
		player.stream = files[0] if not files.is_empty() else null
		player.bus = &"SFX"
		player.unit_size = entry.get("unit", 6.0)
		player.max_distance = entry.get("reach", LOOP_RANGE)
		player.max_db = entry.get("db", 0.0)
		player.attenuation_filter_db = 0.0
		player.panning_strength = 0.8
		add_child(player)
		_loops.append(LoopVoice.new(player, entry.get("db", 0.0), LOOP_LINGER))


func _physics_process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	_update()
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func _update() -> void:
	var mode: StringName = hero.mode.name if hero.mode else &""
	var grounded := hero.grounded()
	var in_water := hero.is_in_water()
	var melee := hero.get_mode(&"Melee") as MeleeMode
	if hero.frozen or not GameAudio.can_play():
		# Nothing happens while frozen (or silent); catch up without sounds.
		_mode = mode
		_grounded = grounded
		_in_water = in_water
		_punch_id = melee.punch_id
		_hurt_time = hero.hurt_time
		for loop in _loops:
			loop.target = 0.0
		return
	var at := hero.global_position
	if mode != _mode:
		_mode_changed(_mode, mode)
		_mode = mode

	# Leaving the ground: a jump, or a super jump's launch.
	if _grounded and not grounded and not in_water and mode == &"OnFoot":
		var rise := hero.velocity.y
		if rise > 20.0:
			var power := inverse_lerp(20.0, 80.0, minf(rise, 80.0))
			GameAudio.play(&"launch", at, lerpf(-6.0, 0.0, power))
			GameAudio.play(&"debris", at, lerpf(-12.0, -4.0, power))
		elif rise > 3.0:
			GameAudio.play(&"jump", at)
	# Into and out of the water.
	if in_water and not _in_water and hero.velocity.y < -6.0:
		GameAudio.play(&"splash", at, lerpf(-6.0, 2.0, clampf(-hero.velocity.y / 60.0, 0.0, 1.0)))
	elif _in_water and not in_water and hero.velocity.y > 5.0:
		GameAudio.play(&"splash", at, -6.0, 1.2)
	_grounded = grounded
	_in_water = in_water

	# Each punch whooshes; the last of a combo is heavier.
	if melee.punch_id != _punch_id:
		_punch_id = melee.punch_id
		if mode == &"Melee":
			if melee.step >= MeleeMode.COMBO.size() - 1:
				GameAudio.play(&"whoosh_heavy", at + Vector3.UP)
				if randf() < 0.5:
					GameAudio.play(&"hero_effort", at + Vector3.UP * 1.5)
			else:
				GameAudio.play(&"whoosh_punch", at + Vector3.UP)

	# Copies of other players' heroes: a hit shows as a fresh stagger.
	if hero.is_remote() and hero.hurt_time > _hurt_time + 0.05:
		_on_hurt(0.0)
	_hurt_time = hero.hurt_time

	# The bottom of a swing.
	var speed := hero.velocity.length()
	if mode == &"Swing":
		var rise := hero.velocity.y
		if _swing_rise < 0.0 and rise >= 0.0 and speed > 12.0:
			GameAudio.play(&"whoosh_swing", at, lerpf(-6.0, 0.0, clampf((speed - 12.0) / 40.0, 0.0, 1.0)))
			if randf() < 0.4:
				GameAudio.play(&"creak", at + Vector3.UP * 1.5)
		_swing_rise = rise

	# Breaking into super speed.
	var flat_speed := hero.horizontal_speed()
	var running := grounded and mode == &"OnFoot" and not in_water
	if running and flat_speed > 30.0 and _zoom_ready:
		_zoom_ready = false
		GameAudio.play(&"zoom", at)
	elif flat_speed < 20.0:
		_zoom_ready = true

	_update_loop_targets(mode, speed, flat_speed, running, grounded, in_water)


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_update_loops(delta)
	GameAudio.cost_usec += Time.get_ticks_usec() - start


func _update_loops(delta: float) -> void:
	if not hero.frozen and GameAudio.can_play():
		_footsteps(delta)
	var near := hero.global_position.distance_squared_to(GameAudio.listener()) < LOOP_RANGE * LOOP_RANGE
	for loop in _loops:
		if near and GameAudio.can_play():
			loop.update(delta, 6.0)
		else:
			loop.silence()


func _update_loop_targets(mode: StringName, speed: float, flat_speed: float, running: bool, grounded: bool,
		in_water: bool) -> void:
	# Air rushing past: off the ground, flying (even slowly), swinging or diving.
	var in_air := (not grounded and not in_water) or mode == &"Flight" or mode == &"Swing" or mode == &"Dive"
	_loops[Loop.AIR_LOW].target = smoothstep(6.0, 45.0, speed) if in_air else 0.0
	_loops[Loop.AIR_HIGH].target = smoothstep(40.0, 150.0, speed) if in_air else 0.0
	_loops[Loop.AIR_LOW].pitch = 0.8 + 0.5 * smoothstep(6.0, 80.0, speed)
	_loops[Loop.AIR_HIGH].pitch = 0.9 + 0.35 * smoothstep(40.0, 150.0, speed)
	_loops[Loop.SPEED].target = smoothstep(SUPER_SPEED, 60.0, flat_speed) if running else 0.0
	_loops[Loop.SPEED].pitch = 0.85 + 0.5 * smoothstep(SUPER_SPEED, 60.0, flat_speed)
	var on_foot := hero.get_mode(&"OnFoot") as OnFootMode
	var charging := mode == &"OnFoot" and on_foot.charging and on_foot.charge > 0.0
	_loops[Loop.CHARGE].target = 0.35 + 0.65 * on_foot.charge if charging else 0.0
	_loops[Loop.CHARGE].pitch = 0.6 + 0.9 * on_foot.charge


## Whether one of the loops (Loop) can be heard (for tests).
func loop_on(loop: Loop) -> bool:
	return _loops[loop].on and _loops[loop].gain >= LoopVoice.SILENT


## A footstep (or swim stroke) each time the run animation's loop passes
## where a foot lands.
func _footsteps(delta: float) -> void:
	_surface_cooldown -= delta
	var swimming := hero.is_in_water()
	var stepping := hero.mode.name == &"OnFoot" and (hero.grounded() or swimming) and hero.horizontal_speed() > 0.6
	var animation: StringName = _animation.assigned_animation if _animation else &""
	var length := _animation.current_animation_length if _animation else 0.0
	if not stepping or not STEPS.has(animation) or length <= 0.0:
		_step_animation = &""
		return
	var phase := _animation.current_animation_position / length
	if animation == _step_animation:
		for contact: float in STEPS[animation]:
			var crossed := (_step_phase < contact and contact <= phase) if phase >= _step_phase \
				else (contact > _step_phase or contact <= phase)
			if crossed:
				_step(swimming)
	_step_animation = animation
	_step_phase = phase


func _step(swimming: bool) -> void:
	var at := hero.global_position
	if swimming:
		GameAudio.play(&"swim", at)
		return
	if _surface_cooldown <= 0.0:
		_surface_cooldown = SURFACE_INTERVAL
		_surface = _surface_at(hero.world_position())
	var speed := hero.horizontal_speed()
	if speed > SUPER_SPEED:
		# Every other step: a patter under the wind of it.
		_odd_step = not _odd_step
		if _odd_step:
			GameAudio.play(_surface, at, -5.0, 1.15)
	elif speed < 3.0:
		GameAudio.play(_surface, at, -5.0)  # walking
	else:
		GameAudio.play(_surface, at)


## Grass in parks, boards on piers and boardwalks, else concrete (roofs too).
func _surface_at(world_position: Vector3) -> StringName:
	var spot := Soundscape.shared().sample(world_position)
	if world_position.y - spot.a > 4.0:
		return &"step_concrete"  # up on a roof or a bridge
	if spot.r > 0.55:
		return &"step_grass"
	if spot.g > 0.45 and world_position.y < 8.0:
		return &"step_wood"
	return &"step_concrete"


func _mode_changed(from: StringName, to: StringName) -> void:
	var at := hero.global_position
	match to:
		&"Swing":
			GameAudio.play(&"thwip", at + Vector3.UP * SwingMode.HAND_HEIGHT)
			if randf() < 0.5:
				GameAudio.play(&"creak", at + Vector3.UP * SwingMode.HAND_HEIGHT, -3.0)
		&"Dive":
			GameAudio.play(&"dive", at)
		&"Flight":
			GameAudio.play(&"takeoff", at)
		&"KnockedOut":
			GameAudio.play(&"body_fall", at)
			GameAudio.play(&"hero_hurt", at + Vector3.UP, 3.0, 0.9)
	if from == &"Swing" and to != &"Dive":
		GameAudio.play(&"web_release", at + Vector3.UP * SwingMode.HAND_HEIGHT)
	elif from == &"KnockedOut":
		GameAudio.play(&"powerup", at)


func _on_landed(impact_speed: float) -> void:
	if hero.frozen or not GameAudio.can_play():
		return
	var at := hero.global_position
	if impact_speed >= Hero.SLAM_SPEED or hero.slam_pending or _mode == &"Dive":
		var power := clampf(inverse_lerp(Hero.SLAM_SPEED, Hero.MAX_FALL_SPEED, impact_speed), 0.0, 1.0)
		GameAudio.play(&"slam", at, lerpf(-4.0, 0.0, power))
		GameAudio.play(&"debris", at, lerpf(-6.0, 0.0, power))
	elif impact_speed >= LAND_HEAVY:
		GameAudio.play(&"land_heavy", at)
		GameAudio.play(&"debris", at, -8.0)
	elif impact_speed >= LAND:
		GameAudio.play(&"land", at)
	elif impact_speed >= 4.0:
		GameAudio.play(_surface_at(hero.world_position()), at, -1.0, 0.9)


func _on_hurt(_damage: float) -> void:
	if not GameAudio.can_play():
		return
	var chest := hero.global_position + Vector3.UP * 1.3
	GameAudio.play(&"punch", chest, -2.0)
	if randf() < 0.7:
		GameAudio.play(&"hero_hurt", chest)
