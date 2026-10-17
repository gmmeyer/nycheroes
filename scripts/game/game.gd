class_name Game
extends Node3D
## Sets up a play session: places the hero (?spawn=x,y,z,yaw; without one, on
## the ground at Times Square), lets it move once the ground under it has
## loaded, and toggles the free-fly debug camera with F1 (starting with
## ?cam=... also starts in the free camera). ?demo plays a scripted tour
## instead of taking player input (see DemoDirector).
##
## Co-op: once the city has loaded, the game joins the public game (see Net),
## so players online see each other without doing anything; they keep their
## own start. Not with ?solo=1 (play alone), a free camera or a screenshot,
## nor when nobody's playing (headless runs, browsers driven by scripts) unless
## ?public=1, nor where the player turned it off (the "online_public" setting).
## M opens the co-op menu; ?host hosts a private game and ?join=CODE joins one
## (invite links use it). Players who join a private game start next to the
## host's hero.
## T steps the time of day on to the next of dawn, day, dusk and night
## (TimeOfDay; ?time=HH:MM and ?daylength=MINUTES set the clock).
## Sound is the Audio node's (GameAudio): N switches it off and on.
## O opens the options menu (OptionsPanel; Esc too in the desktop builds), as
## do the HUD's Options button and the touch gear; one menu shows at a time.
##
## Phones and tablets: touch screens get on-screen controls (TouchControls;
## ?touch=1 or ?touch=0 forces them on or off, see Device), and a graphics
## quality preset is picked for the device (Quality; ?quality=low|medium|high),
## unless the options menu has picked one.
##
## Desktop builds: F11 switches full screen on and off (remembered, like the
## options menu's switch). --screenshot=PATH
## saves the screen to PATH (PNG) a few seconds after the city has loaded
## (--screenshot_delay=SECONDS, default 5), logs the frame times meanwhile,
## and quits: for checking builds.

## Times Square, facing north up Broadway (world meters; dropped onto the ground).
const DEFAULT_SPAWN := Vector3(0.0, 15.0, 0.0)
## Physics ticks to wait for new collision to show up before giving up on
## finding the ground (over open water there is none).
const DROP_TRIES := 30
## --screenshot waits this long after the city has loaded (s).
const SCREENSHOT_DELAY := 5.0

@export var hero: Hero
@export var hero_camera: ThirdPersonCamera
@export var free_camera: FreeFlyCamera
@export var player_input: PlayerInput
@export var city: CityStreamer
@export var encounters: EncounterDirector
@export var players: PlayerSync
@export var hud: CanvasLayer
@export var coop_panel: CoopPanel
@export var time_of_day: TimeOfDay

var _free_camera_on := false
var _drop_to_ground := false
var _drop_tries := 0
var _touch_controls: TouchControls
var _options: OptionsPanel


func _enter_tree() -> void:
	# Before the city and crowd start and read their launch options.
	Quality.set_launch_defaults()


func _ready() -> void:
	var spawn := LaunchOptions.get_floats("spawn")
	var facing := deg_to_rad(spawn[3]) if spawn.size() >= 4 else hero.facing
	if spawn.size() >= 3:
		place_hero(Vector3(spawn[0], spawn[1], spawn[2]), facing)
	else:
		place_hero(DEFAULT_SPAWN, facing, true)
	_set_free_camera(LaunchOptions.has("cam"))
	players.placed_by_host.connect(place_hero)
	coop_panel.toggled.connect(func(_open: bool) -> void: _update_controls())
	Net.state_changed.connect(_on_net_state_changed)
	var quality := Quality.new()
	quality.name = "Quality"
	add_child(quality)
	quality.apply(time_of_day.sun, get_world_3d().environment, city, get_node("Crowd") as CrowdManager, encounters,
		get_node_or_null("Traffic") as Traffic, get_node_or_null("Trains") as Trains, time_of_day)
	_add_options(quality)
	if not Device.is_web() and bool(Settings.get_value("fullscreen", false)) and not LaunchOptions.has("screenshot"):
		Device.set_fullscreen(true)
	if Device.wants_touch_controls() and not LaunchOptions.has("demo"):
		_add_touch_controls(false)
	if LaunchOptions.has("demo"):
		_start_demo()
	elif LaunchOptions.has("host"):
		Net.host()
	elif LaunchOptions.has("join"):
		Net.join(LaunchOptions.get_string("join"))
	elif _plays_public():
		# Once the city is there: joining doesn't hold up its loading.
		encounters.hold_for_public = true
		city.initial_load_finished.connect(func(_seconds: float) -> void:
			Net.start_public()
			encounters.hold_for_public = false, CONNECT_ONE_SHOT)
	if LaunchOptions.has("screenshot") and not Device.is_web():
		_take_screenshot(LaunchOptions.get_string("screenshot"))


func _physics_process(_delta: float) -> void:
	if not hero.frozen or not city.has_collision_at(hero.world_position()):
		return
	if _drop_to_ground:
		var ground := city.ground_height_at(hero.world_position())
		_drop_tries += 1
		if is_nan(ground) and _drop_tries < DROP_TRIES:
			return  # the tile's collision is still being set up
		if not is_nan(ground):
			hero.global_position.y = ground + 0.05
		_drop_to_ground = false
	hero.frozen = false


## Moves our hero to a world position (the host does this when we join) and
## holds it there until the ground has loaded. With `drop`, the height isn't
## known: the hero then lands on whatever is below.
func place_hero(world_position: Vector3, facing: float, drop := false) -> void:
	hero.set_mode(&"OnFoot")
	hero.global_position = WorldOrigin.to_local(world_position)
	hero.velocity = Vector3.ZERO
	hero.facing = facing
	hero.frozen = true
	hero_camera.yaw = facing
	_drop_to_ground = drop
	_drop_tries = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and _touch_controls == null and Device.touch_allowed() \
			and not LaunchOptions.has("demo"):
		_add_touch_controls(true)  # a touch screen the browser didn't tell us about
	if event.is_action_pressed("options_menu") and not coop_panel.is_typing() and not LaunchOptions.has("demo"):
		coop_panel.close()
		_options.toggle(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("coop_menu") and not coop_panel.is_typing():
		_options.close(false, false)
		coop_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_of_day") and not coop_panel.is_typing():
		time_of_day.step_forward()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_free_camera"):
		if not _free_camera_on:
			free_camera.global_transform = hero_camera.camera.global_transform
			free_camera.sync_rotation()
		_set_free_camera(not _free_camera_on)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11 \
			and not Device.is_web():
		var on := not Device.is_fullscreen()
		Device.set_fullscreen(on)
		Settings.set_value("fullscreen", on)
		get_viewport().set_input_as_handled()


## Whether this session joins the public game (see the top). Only games that
## connect over WebRTC meet other players there (desktop builds without the
## extension don't); ?public=1 joins anyway (tests over ENet meet each other).
func _plays_public() -> bool:
	if LaunchOptions.has("solo") and LaunchOptions.get_string("solo") != "0":
		return false
	if LaunchOptions.has("public"):
		return LaunchOptions.get_string("public") != "0"
	if LaunchOptions.has("cam") or LaunchOptions.has("screenshot") or DisplayServer.get_name() == "headless":
		return false
	if Device.is_web():
		# (Headless Chrome, which the page checks use, doesn't set webdriver.)
		return JavaScriptBridge.eval("navigator.webdriver === true || navigator.userAgent.includes('HeadlessChrome')") != true
	return Net.uses_webrtc()


func _start_demo() -> void:
	player_input.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	var director := DemoDirector.new()
	director.game = self
	director.hero = hero
	director.camera = hero_camera
	director.city = city
	director.encounters = encounters
	director.free_camera = free_camera
	director.time_of_day = time_of_day
	add_child(director)


func _take_screenshot(path: String) -> void:
	var load_seconds: float = await city.initial_load_finished
	var frames := PackedFloat64Array()
	var delay := LaunchOptions.get_string("screenshot_delay", str(SCREENSHOT_DELAY)).to_float()
	var until := Time.get_ticks_msec() + int(delay * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		frames.append(get_process_delta_time() * 1000.0)
	await RenderingServer.frame_post_draw
	var saved := get_viewport().get_texture().get_image().save_png(path)
	var total := 0.0
	var worst := 0.0
	for msec in frames:
		total += msec
		worst = maxf(worst, msec)
	print("[screenshot] %s %s: the city loaded in %.1f s; then %d frames, %.2f ms on average, %.1f ms at worst, %d draw calls" % [
		"saved" if saved == OK else "couldn't save", path, load_seconds, frames.size(), total / maxf(frames.size(), 1),
		worst, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	get_tree().quit()


func _on_net_state_changed() -> void:
	# Show what went wrong, e.g. a join link for a game that has ended.
	if Net.state == Net.State.OFFLINE and Net.error:
		_options.close(false, false)
		coop_panel.open()


## Switches between the hero's camera and the free-fly camera.
func use_free_camera(on: bool) -> void:
	_set_free_camera(on)


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
	player_input.enabled = not _free_camera_on and not coop_panel.visible and not (_options and _options.visible)


## The options menu, over the co-op menu in the HUD (only one shows at a time).
func _add_options(quality: Quality) -> void:
	OptionsPanel.add_action()
	_options = OptionsPanel.new()
	_options.name = "OptionsPanel"
	_options.coop_panel = coop_panel
	_options.quality = quality
	_options.time_of_day = time_of_day
	_options.debug_label = hud.get_node_or_null("DebugLabel") as Control
	hud.add_child(_options)
	_options.toggled.connect(func(_open: bool) -> void: _update_controls())
	var game_hud := hud.get_node_or_null("GameHud") as GameHud
	if game_hud:
		game_hud.options_requested.connect(func() -> void:
			coop_panel.close()
			_options.open())


## On-screen controls for touch screens. The UI is then measured in CSS
## pixels, which browsers keep about the same physical size on every phone.
func _add_touch_controls(started_by_touch: bool) -> void:
	get_window().content_scale_factor = Device.touch_ui_scale()
	_touch_controls = TouchControls.new()
	_touch_controls.name = "TouchControls"
	_touch_controls.hero = hero
	_touch_controls.camera_rig = hero_camera
	_touch_controls.coop_panel = coop_panel
	_touch_controls.options_panel = _options
	_touch_controls.started_by_touch = started_by_touch
	hud.add_child(_touch_controls)
	hud.move_child(_touch_controls, coop_panel.get_index())  # under the co-op menu
	var game_hud := hud.get_node_or_null("GameHud") as GameHud
	if game_hud:
		game_hud.touch_controls = _touch_controls
	coop_panel.use_touch_layout()
	_options.use_touch_layout()
	var debug_label := hud.get_node_or_null("DebugLabel") as Label
	if debug_label:
		# Small, under the health bar (shown with ?stats or the options menu's switch).
		debug_label.add_theme_font_size_override("font_size", 10)
		debug_label.position = Vector2(_touch_controls.safe_insets.x + 20.0, _touch_controls.safe_insets.y + 56.0)
	Device.set_page_touch_mode(true)
