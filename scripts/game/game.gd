extends Node3D
## Sets up a play session: places the hero (?spawn=x,y,z,yaw), lets it move once
## the ground under it has loaded, and toggles the free-fly debug camera with F1
## (starting with ?cam=... also starts in the free camera). ?demo plays a
## scripted tour of the powers instead of taking player input.
##
## Co-op: M opens the co-op menu; ?host hosts a game and ?join=CODE joins one
## (invite links use it). Players who join start next to the host's hero.

## Times Square, facing north up Broadway (world meters).
const DEFAULT_SPAWN := Vector3(0.0, 3.0, 60.0)

@export var hero: Hero
@export var hero_camera: ThirdPersonCamera
@export var free_camera: FreeFlyCamera
@export var player_input: PlayerInput
@export var city: CityStreamer
@export var encounters: EncounterDirector
@export var players: PlayerSync
@export var hud: CanvasLayer
@export var coop_panel: CoopPanel

var _free_camera_on := false


func _ready() -> void:
	var spawn := LaunchOptions.get_floats("spawn")
	var spawn_point := Vector3(spawn[0], spawn[1], spawn[2]) if spawn.size() >= 3 else DEFAULT_SPAWN
	hero.global_position = WorldOrigin.to_local(spawn_point)
	if spawn.size() >= 4:
		hero.facing = deg_to_rad(spawn[3])
	hero_camera.yaw = hero.facing
	_set_free_camera(LaunchOptions.has("cam"))
	players.placed_by_host.connect(_place_hero)
	coop_panel.toggled.connect(func(_open: bool) -> void: _update_controls())
	Net.state_changed.connect(_on_net_state_changed)
	if LaunchOptions.has("demo"):
		_start_demo()
	elif LaunchOptions.has("host"):
		Net.host()
	elif LaunchOptions.has("join"):
		Net.join(LaunchOptions.get_string("join"))


func _physics_process(_delta: float) -> void:
	if hero.frozen and city.has_collision_at(hero.world_position()):
		hero.frozen = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("coop_menu") and not coop_panel.is_typing():
		coop_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_free_camera"):
		if not _free_camera_on:
			free_camera.global_transform = hero_camera.camera.global_transform
			free_camera.sync_rotation()
		_set_free_camera(not _free_camera_on)


func _start_demo() -> void:
	player_input.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	var director := DemoDirector.new()
	director.hero = hero
	director.camera = hero_camera
	director.city = city
	director.encounters = encounters
	add_child(director)


## Moves our hero to a world position (the host does this when we join) and
## holds it there until the ground has loaded.
func _place_hero(world_position: Vector3, facing: float) -> void:
	hero.set_mode(&"OnFoot")
	hero.global_position = WorldOrigin.to_local(world_position)
	hero.velocity = Vector3.ZERO
	hero.facing = facing
	hero.frozen = true
	hero_camera.yaw = facing


func _on_net_state_changed() -> void:
	# Show what went wrong, e.g. a join link for a game that has ended.
	if Net.state == Net.State.OFFLINE and Net.error:
		coop_panel.open()


func _set_free_camera(on: bool) -> void:
	_free_camera_on = on
	free_camera.current = on
	hero_camera.camera.current = not on
	free_camera.set_process(on)
	free_camera.set_process_unhandled_input(on)
	hero_camera.set_process_unhandled_input(not on)
	WorldOrigin.focus = free_camera if on else hero
	_update_controls()


func _update_controls() -> void:
	player_input.enabled = not _free_camera_on and not coop_panel.visible
