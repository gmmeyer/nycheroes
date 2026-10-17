extends Node
## Headless costume regression: save boundaries, actual menu signals, skinned
## body data, accessory attachments through movement, and co-op isolation.
## godot --headless --path . res://tests/customization_test.tscn -- --solo=1
const SAVE := "user://customization_test.cfg"
var failures := 0
func _ready() -> void:
	_run()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", message)
func _run() -> void:
	Settings.use_file(SAVE)
	HeroAppearance.save(HeroAppearance.DEFAULT)
	var profile := HeroAppearance.DEFAULT.duplicate()
	profile.suit = "mech"
	profile.cape = "split"
	profile.hair = "curls"
	profile.headgear = "helmet"
	profile.boots = "armored"
	profile.primary = "4aabc1"
	HeroAppearance.save(profile)
	Settings.use_file(SAVE)
	check(HeroAppearance.current() == profile, "all cosmetic fields survive file reload")
	var stored := ConfigFile.new()
	stored.load(SAVE)
	var browser_copy := ConfigFile.new()
	check(browser_copy.parse(stored.encode_to_text()) == OK and HeroAppearance.sanitize(browser_copy.get_value("settings", HeroAppearance.KEY)) == profile,
		"the browser storage ConfigFile text round-trip preserves every cosmetic field")
	var bad := {"version": 1, "suit": "res://bad.tscn", "cape": [], "primary": "ffffff00", "skin": 7, "unknown": "ignored", "hair_color": "ABCDEF"}
	var clean := HeroAppearance.sanitize(bad)
	check(clean.suit == "vector" and clean.cape == "short" and clean.primary == "137f8c" and clean.skin == "b97a57" and clean.hair_color == "abcdef" and not clean.has("unknown"), "malformed fields fall back; valid RGB normalized; unknown keys removed")
	check(HeroAppearance.sanitize({"primary": "-12345", "accent": "+12345"}).primary == HeroAppearance.DEFAULT.primary
		and HeroAppearance.sanitize({"accent": "+12345"}).accent == HeroAppearance.DEFAULT.accent, "signed hexadecimal numbers are rejected as colors")
	check(HeroAppearance.sanitize(null) == HeroAppearance.DEFAULT and HeroAppearance.sanitize({"version": 999, "suit": "mech"}) == HeroAppearance.DEFAULT, "non-dictionaries and future versions fall back")
	Settings.set_value(HeroAppearance.KEY, bad)
	Settings.use_file(SAVE)
	check(HeroAppearance.current() == clean, "malformed saved cosmetics are sanitized on reload")
	HeroAppearance.save(profile)
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	hero.frozen = true
	add_child(hero)
	var animator := hero.get_node("Model") as HeroAnimator
	check(animator.appearance == profile and animator.outfit.profile == profile, "local hero starts with its saved costume")
	var page := HeroCustomizationPage.create(false)
	add_child(page)
	var choice: OptionButton = page._choices.suit
	choice.item_selected.emit(3)
	check(HeroAppearance.current().suit == "leotard" and animator.appearance.suit == "leotard" and page.outfit.profile.suit == "leotard", "menu choice saves and updates live hero and preview")
	var color: ColorPickerButton = page._colors.skin
	color.color_changed.emit(Color("704529"))
	page._flush_color()
	check(HeroAppearance.current().skin == "704529" and animator.outfit.profile.skin == "704529", "color picker persists opaque skin color")
	page.hide()
	await get_tree().process_frame
	check(page._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not page._animation.active,
		"hidden dressing room stops rendering and animating")
	page.show()
	var original: Node3D = HeroCustomizationPage.CHARACTER.instantiate()
	var original_mesh := original.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	for surface in original_mesh.mesh.get_surface_count():
		var before := original_mesh.mesh.surface_get_arrays(surface)
		var after := animator.outfit._body.mesh.surface_get_arrays(surface)
		check(before[Mesh.ARRAY_BONES] == after[Mesh.ARRAY_BONES] and before[Mesh.ARRAY_WEIGHTS] == after[Mesh.ARRAY_WEIGHTS]
			and before[Mesh.ARRAY_VERTEX] == after[Mesh.ARRAY_VERTEX], "body surface %d retains original skin weights and geometry" % surface)
	original.free()
	var skeleton := hero.find_child("Skeleton3D", true, false) as Skeleton3D
	var animation := hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for key: String in HeroAppearance.OPTIONS:
		if key == "hair":
			profile.headgear = "none"
		for value: String in HeroAppearance.OPTIONS[key]:
			profile[key] = value
			animator.set_appearance(profile)
			await get_tree().process_frame
			var draws := 2
			for mesh: MeshInstance3D in animator.outfit.find_children("*", "MeshInstance3D", true, false):
				draws += mesh.mesh.get_surface_count()
			check(draws <= 36, "%s=%s bounded accessory draw surfaces (%d)" % [key, value, draws])
	profile.suit = "mech"
	animator.set_appearance(profile)
	for pose: String in ["Idle", "Sprint", "Jump", "Punch_L", "Death01"]:
		if not animation.has_animation(pose):
			continue
		animator.set_process(false)
		animation.play(pose)
		animation.advance(0.2)
		await get_tree().process_frame
		for attachment: BoneAttachment3D in animator.outfit.get_children():
			var bone := skeleton.find_bone(attachment.bone_name)
			check(attachment.transform.is_equal_approx(skeleton.get_bone_global_pose(bone)), "%s: %s accessory follows animated bone" % [pose, attachment.bone_name])
	var sync := PlayerSync.new()
	sync.hero = hero
	add_child(sync)
	var remote: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	remote.remote_id = 42
	remote.frozen = true
	sync.add_child(remote)
	sync.remote_heroes[42] = remote
	check(sync._apply_remote_appearance(42, profile) and (remote.get_node("Model") as HeroAnimator).appearance == profile, "validated remote costume applies")
	var oversized := {}
	for i in 17:
		oversized[str(i)] = "ignored"
	check(not sync._apply_remote_appearance(42, oversized), "oversized cosmetic dictionaries are rejected")
	check(sync._apply_remote_appearance(42, bad) and (remote.get_node("Model") as HeroAnimator).appearance == clean,
		"remote malformed fields use the same safe defaults as saved cosmetics")
	sync._apply_remote_appearance(42, profile)
	check(not sync._apply_remote_appearance(99, profile), "unknown peers cannot allocate costume instances")
	var remote_before: Dictionary = (remote.get_node("Model") as HeroAnimator).appearance.duplicate()
	HeroAppearance.save(HeroAppearance.DEFAULT)
	check((remote.get_node("Model") as HeroAnimator).appearance == remote_before, "local edits do not overwrite a remote player's costume")
	sync._on_net_state_changed()
	check(animator.appearance == HeroAppearance.DEFAULT, "network state changes preserve local cosmetics")
	page.free()
	sync.free()
	hero.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("CUSTOMIZATION_TEST failures=", failures)
	get_tree().quit(1 if failures else 0)
