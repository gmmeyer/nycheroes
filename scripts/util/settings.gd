extends Node
## Settings remembered between visits (the autoload "Settings"): the options
## menu's (OptionsPanel), the sound's mute switch (N), and co-op's "join the
## public game automatically" ("online_public"). Kept in user://settings.cfg
## (a ConfigFile, all under [settings]) and saved at every change.
##
## On the web, user:// is the browser's IndexedDB, which Godot writes to on
## its own a frame after a file changes (there's nothing to call). That
## usually takes a tenth of a second, but in a fresh browser session the
## first one waited 15-20 s behind Godot's own first files (measured in
## headless Chrome), and a page reloaded meanwhile lost the change. So the
## web build also keeps a copy of the file in localStorage
## ("nycheroes.settings", written at once), and reads that copy first.
## Desktop builds keep the file in the game's own folder (%APPDATA%\NYC
## Heroes, ~/Library/Application Support/NYC Heroes).
##
## Launch options (?quality=, ?mute=, ?stats, ?fog=, ...) win over saved
## values for the session, where each is read; changes made in the menu are
## applied and saved as usual. Earlier versions kept the mute switch in the
## browser's localStorage ("nycheroes.muted") on the web, and under [sound]
## in this file on desktop: the first start of this one moves it in here.
##
## Headless runs (the tests) keep settings in memory only, so a player's
## saved settings can't change a test (tests/options_test.gd gives Settings
## a file of its own, use_file()).
##
## Keys: muted, volume_master, volume_effects, volume_ambience (0..1),
## quality ("auto", "low", "medium", "high"), look_mouse and look_touch (look
## speed, times the usual), invert_y, show_stats, fullscreen (desktop),
## online_public, hero_appearance (validated versioned cosmetic profile).

## A setting changed (set_value), e.g. for nodes that follow it.
signal changed(key: String)

const PATH := "user://settings.cfg"
const SECTION := "settings"
## The web build's copy in localStorage.
const STORAGE_KEY := "nycheroes.settings"
const OLD_MUTED_STORAGE_KEY := "nycheroes.muted"

var _config := ConfigFile.new()
var _path := PATH


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		_path = ""
		return
	# In _init, not _ready: autoloads listed later (Net) may read settings
	# before this node is in the tree.
	_load()


## The saved value, or `default` if there's none.
func get_value(key: String, default: Variant = null) -> Variant:
	return _config.get_value(SECTION, key, default)


func has_value(key: String) -> bool:
	return _config.has_section_key(SECTION, key)


## Stores a value and saves the file at once; tells `changed` if it differs.
func set_value(key: String, value: Variant) -> void:
	if has_value(key):
		var old: Variant = _config.get_value(SECTION, key)
		if typeof(old) == typeof(value) and old == value:
			return
	_config.set_value(SECTION, key, value)
	_save()
	changed.emit(key)


## Reads settings from another file from now on (tests keep the player's own
## settings out of it this way).
func use_file(path: String) -> void:
	_path = path
	_config = ConfigFile.new()
	_load()


func _load() -> void:
	var error := ERR_FILE_NOT_FOUND
	if _uses_storage():
		# Storage can be off (private windows, blocked cookies).
		var text := str(JavaScriptBridge.eval(
			"(function () { try { return localStorage.getItem('%s') || ''; } catch (e) { return ''; } })()" % STORAGE_KEY, true))
		if not text.is_empty():
			error = _config.parse(text)
	if error != OK:
		error = _config.load(_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Couldn't read %s (error %d); starting from the usual settings." % [_path, error])
		_config = ConfigFile.new()
	_move_old_settings()


## The mute switch from where earlier versions kept it.
func _move_old_settings() -> void:
	var dirty := false
	if not has_value("muted"):
		var muted: Variant = null
		if _config.has_section_key("sound", "muted"):
			muted = bool(_config.get_value("sound", "muted"))
		elif OS.has_feature("web"):
			# Storage can be off (private windows, blocked cookies).
			var stored := str(JavaScriptBridge.eval(
				"(function () { try { return localStorage.getItem('%s') || ''; } catch (e) { return ''; } })()"
				% OLD_MUTED_STORAGE_KEY, true))
			if stored == "1" or stored == "0":
				muted = stored == "1"
		if muted != null:
			_config.set_value(SECTION, "muted", muted)
			dirty = true
	if _config.has_section("sound"):
		_config.erase_section("sound")
		dirty = true
	if dirty:
		_save()


func _save() -> void:
	if _path.is_empty():
		return  # (headless)
	if _uses_storage():
		JavaScriptBridge.eval("(function () { try { localStorage.setItem('%s', %s); } catch (e) {} })()"
			% [STORAGE_KEY, JSON.stringify(_config.encode_to_text())], true)
	var error := _config.save(_path)
	if error != OK:
		push_warning("Couldn't save the settings to %s (error %d)." % [_path, error])


## The web build's own settings (not a test's file) are copied to localStorage.
func _uses_storage() -> bool:
	return OS.has_feature("web") and _path == PATH
