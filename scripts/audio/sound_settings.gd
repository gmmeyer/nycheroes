class_name SoundSettings
## Remembers whether the sound is off between visits: in the browser's
## localStorage on the web (synchronous, so a tab closed right after still
## keeps it), else in user://settings.cfg. ?mute=1 / ?mute=0 (--mute=1 on
## desktop) overrides it for one session without saving.

const STORAGE_KEY := "nycheroes.muted"
const CONFIG_PATH := "user://settings.cfg"


static func load_muted() -> bool:
	var forced := LaunchOptions.get_string("mute")
	if forced == "1" or forced == "0":
		return forced == "1"
	if OS.has_feature("web"):
		# Storage can be off (private windows, blocked cookies): then it's on.
		var stored: Variant = JavaScriptBridge.eval(
			"(function () { try { return localStorage.getItem('%s') || ''; } catch (e) { return ''; } })()" % STORAGE_KEY, true)
		return str(stored) == "1"
	var config := ConfigFile.new()
	return config.load(CONFIG_PATH) == OK and bool(config.get_value("sound", "muted", false))


static func save_muted(muted: bool) -> void:
	if LaunchOptions.has("mute"):
		return  # a one-off from the launch options
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function () { try { localStorage.setItem('%s', '%s'); } catch (e) {} })()"
			% [STORAGE_KEY, "1" if muted else "0"], true)
		return
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # keep whatever else is in there
	config.set_value("sound", "muted", muted)
	config.save(CONFIG_PATH)
