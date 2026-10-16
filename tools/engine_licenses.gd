extends SceneTree
## Writes the Godot engine's license and its third-party components' licenses
## to a text file, for the desktop downloads (tools/build_desktop.ps1).
## Run: godot --headless --path . --script res://tools/engine_licenses.gd -- <file>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := FileAccess.open(args[0], FileAccess.WRITE) if not args.is_empty() else null
	if out == null:
		push_error("usage: --script res://tools/engine_licenses.gd -- <file>")
		quit(1)
		return
	out.store_string("Godot Engine %s (https://godotengine.org)\n\n%s\n" % [
		Engine.get_version_info().string, Engine.get_license_text()])
	out.store_string("\nThird-party components of the engine:\n")
	for part: Dictionary in Engine.get_copyright_info():
		out.store_string("\n%s\n" % part.name)
		for piece: Dictionary in part.parts:
			out.store_string("  %s: %s\n" % [", ".join(piece.copyright), piece.license])
	var licenses := Engine.get_license_info()
	for name: String in licenses:
		out.store_string("\n---- %s ----\n\n%s\n" % [name, licenses[name]])
	quit()
