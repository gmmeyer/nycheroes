extends Node
## Headless check of the options menu's Go to box, in the real city:
## - Geo.to_world matches the tiles' projection (pyproj on PROJECTION in
##   tools/citygen/common.py) to the centimeter across the five boroughs.
## - AddressSearch reads GeoSearch's and Nominatim's answers, and takes a
##   typed latitude and longitude as it is.
## - The menu: a latitude and longitude typed into the box (the Empire State
##   Building's middle) and Go close the menu and take the hero there; once
##   the streets have loaded it stands on a sidewalk beside the building,
##   facing it, and can move. Somewhere off the map (Albany) keeps the menu
##   open and says so.
## - With --online, the real searches: an address and a ZIP code.
## Uses a settings file of its own, not the player's.
## Run: godot --headless --path . res://tests/address_test.tscn -- --solo=1 [--tiles=DIR] [--online]

const SETTINGS_FILE := "user://address_test_settings.cfg"
const MAX_LOAD_WAIT := 60.0
const MAX_LOOKUP_WAIT := 15.0
## pyproj's world positions (x, z) for these (lat, lon): Times Square, the
## Empire State Building, the Statue of Liberty, Staten Island, the Bronx and
## the city's northeast corner.
const PROJECTED: Array[Array] = [
	[40.7580, -73.9855, 0.0, 0.0],
	[40.748441, -73.985656, -13.1749, 1061.5187],
	[40.689249, -74.0445, -4987.2167, 7633.0261],
	[40.5795, -74.1502, -13944.7593, 19808.943],
	[40.8448, -73.8648, 10178.9011, -9646.1582],
	[40.9, -73.7, 24056.8775, -15808.429],
]
const EMPIRE_STATE := "40.748441, -73.985656"
## The Empire State Building's footprint is about 130 by 60 m: its sidewalks
## are this near its middle.
const BESIDE := 75.0

var _world: Game
var _city: CityStreamer
var _options: OptionsPanel
var _hero: Hero
var _checks: Array[String] = []
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Tester")  # (no name prompt)
	_check_projection()
	_check_parsing()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_options = _world.get_node("HUD/OptionsPanel")
	_hero = _world.get_node("Hero")
	if not await _wait_for_city():
		_check(false, "the city loaded at Times Square")
		_finish()
		return
	await _check_menu()
	if LaunchOptions.has("online"):
		await _check_online()
	_finish()


func _check_projection() -> void:
	var worst := 0.0
	for p in PROJECTED:
		var at := Geo.to_world(p[0], p[1])
		worst = maxf(worst, Vector2(at.x - p[2], at.z - p[3]).length())
	_check(worst < 0.01, "Geo.to_world matches the tiles' projection (worst %.4f m off)" % worst)


func _check_parsing() -> void:
	var geosearch := AddressSearch.parse_geosearch(JSON.stringify({"type": "FeatureCollection", "features": [
		{"geometry": {"type": "Point", "coordinates": [-73.985656, 40.748441]},
			"properties": {"name": "350 5 AVENUE", "borough": "Manhattan", "label": "350 5 AVENUE, New York, NY, USA"}}]}))
	_check(geosearch.get("label") == "350 5 AVENUE, Manhattan" and is_equal_approx(geosearch.get("lat", 0.0), 40.748441)
		and is_equal_approx(geosearch.get("lon", 0.0), -73.985656), "GeoSearch's best match read (%s)" % geosearch)
	_check(AddressSearch.parse_geosearch('{"type":"FeatureCollection","features":[]}').is_empty()
		and AddressSearch.parse_geosearch("<html>").is_empty(), "no match, or no JSON, is nothing found")
	var nominatim := AddressSearch.parse_nominatim(JSON.stringify([{"lat": "40.7192535", "lon": "-74.0022800",
		"display_name": "10013, Manhattan, New York County, New York, United States"}]))
	_check(nominatim.get("label") == "10013, Manhattan" and is_equal_approx(nominatim.get("lat", 0.0), 40.7192535),
		"Nominatim's ZIP code read (%s)" % nominatim)
	_check(AddressSearch.parse_nominatim("[]").is_empty(), "no ZIP code found is nothing found")
	var search := AddressSearch.new()
	add_child(search)
	var got: Array = []
	search.found.connect(func(at: Vector3, label: String) -> void: got.append([at, label]))
	search.search("  40.7484, -73.9857 ")
	_check(got.size() == 1 and (got[0][0] as Vector3).distance_to(Geo.to_world(40.7484, -73.9857)) < 0.01,
		"a typed latitude and longitude is found at once")
	search.queue_free()


func _check_menu() -> void:
	_options.open()
	_check(_options._address.is_visible_in_tree() and _options._page == 0, "the Go to box is on the Game page, shown first")
	# Off the map: Albany.
	_options._address.text = "42.6526, -73.7562"
	_options._address_go.pressed.emit()
	_check(_options.visible and _options._address_note.text.contains("isn't on the city's map"),
		"somewhere off the map keeps the menu open and says so (%s)" % _options._address_note.text)
	var chosen: Array = []
	_options.place_chosen.connect(func(at: Vector3) -> void: chosen.append(at), CONNECT_ONE_SHOT)
	_options._address.text = EMPIRE_STATE
	_options._address.text_submitted.emit(_options._address.text)  # (Enter)
	_check(not _options.visible and chosen.size() == 1, "Enter in the box closes the menu and goes there")
	_check(_hero.frozen, "the hero waits over the address while its streets load")
	var address := Geo.to_world(40.748441, -73.985656)
	var started := Time.get_ticks_msec()
	while _hero.frozen and Time.get_ticks_msec() - started < MAX_LOAD_WAIT * 1000.0:
		await _wait(0.25)
	await _wait(0.5)
	var at := _hero.world_position()
	var away := Vector2(at.x - address.x, at.z - address.z)
	var looking := _hero.forward()
	var facing := Vector2(looking.x, looking.z).normalized().dot(-away.normalized())
	_check(not _hero.frozen, "the hero can move once the streets there have loaded")
	_check(away.length() > 20.0 and away.length() < BESIDE,
		"it stands beside the Empire State Building, not in or on it (%.1f m from its middle)" % away.length())
	_check(at.y > 0.0 and at.y < 25.0, "on the ground, not a roof (%.1f m up)" % at.y)
	_check(facing > 0.9, "facing the building (%.2f)" % facing)
	_check(_hero.is_on_floor() or absf(_hero.velocity.y) < 1.0, "standing on the sidewalk, not falling")


func _check_online() -> void:
	var search := AddressSearch.new()
	add_child(search)
	for case: Array in [["350 5th Ave, Manhattan", Geo.to_world(40.748441, -73.985656), 50.0],
			["10013", Geo.to_world(40.7192535, -74.00228), 800.0]]:
		var got: Array = []
		search.found.connect(func(at: Vector3, label: String) -> void: got.append([at, label]), CONNECT_ONE_SHOT)
		search.failed.connect(func(message: String) -> void: got.append([Vector3.INF, message]), CONNECT_ONE_SHOT)
		search.search(case[0])
		var started := Time.get_ticks_msec()
		while got.is_empty() and Time.get_ticks_msec() - started < MAX_LOOKUP_WAIT * 1000.0:
			await _wait(0.1)
		for signal_name in ["found", "failed"]:
			for connection in search.get_signal_connection_list(signal_name):
				search.disconnect(signal_name, connection.callable)
		var ok: bool = not got.is_empty() and (got[0][0] as Vector3).distance_to(case[1]) < case[2]
		_check(ok, "online: \"%s\" found (%s)" % [case[0], got[0][1] if not got.is_empty() else "no answer"])
	search.queue_free()


func _wait_for_city() -> bool:
	var started := Time.get_ticks_msec()
	while _city.loaded_counts[0] == 0 or _city.pending_count() > 0 or _hero.frozen:
		await _wait(0.5)
		if Time.get_ticks_msec() - started > MAX_LOAD_WAIT * 1000.0:
			return false
	return true


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok      " if ok else "FAILED  ") + what)
	if not ok:
		_failed += 1


func _finish() -> void:
	print("\n".join(_checks))
	print("%d checks, %d failed" % [_checks.size(), _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	get_tree().paused = false
	get_tree().quit(1 if _failed else 0)
