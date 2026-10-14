class_name LaunchOptions
## Startup options, from the page URL on the web (index.html?cam=0,300,0,180,-20&stats)
## or from user args on desktop (godot -- --cam=0,300,0,180,-20 --stats).

static var _options := {}
static var _parsed := false


static func has(name: String) -> bool:
	_parse()
	return _options.has(name)


static func get_string(name: String, default := "") -> String:
	_parse()
	return _options.get(name, default)


## Comma-separated numbers, e.g. "1,2.5,3"; empty if the option isn't set.
static func get_floats(name: String) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for part in get_string(name).split(",", false):
		values.append(part.to_float())
	return values


static func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	var pairs: PackedStringArray
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("location.search"))
		pairs = query.trim_prefix("?").split("&", false)
	else:
		for arg in OS.get_cmdline_user_args():
			pairs.append(arg.trim_prefix("--"))
	for pair in pairs:
		var parts := pair.split("=", true, 1)
		_options[parts[0].uri_decode()] = parts[1].uri_decode() if parts.size() > 1 else ""
