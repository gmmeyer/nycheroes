extends Node
## Standalone render smoke test. Saves only to a test file, leaving the user's
## costume untouched. --variant=mech|leotard|vector --screenshot=ABSOLUTE_PATH
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.use_file("user://customization_preview.cfg")
	var profile := HeroAppearance.DEFAULT.duplicate()
	var variant := LaunchOptions.get_string("variant", "vector")
	profile.suit = variant
	if variant == "mech":
		profile.headgear = "helmet"
		profile.boots = "armored"
		profile.cape = "split"
	if variant == "leotard":
		profile.headgear = "crown"
		profile.hair = "curls"
		profile.primary = "8449ac"
		profile.cape = "long"
	HeroAppearance.save(profile)
	OptionsPanel.add_action()
	var options := OptionsPanel.new()
	add_child(options)
	if Device.wants_touch_controls():
		options.use_touch_layout()
	options.open()
	options._show_page(1)
	await get_tree().create_timer(1.0, true).timeout
	var page := options._pages[1] as HeroCustomizationPage
	if LaunchOptions.has("turn"):
		(page.find_child("TurnSlider", true, false) as HSlider).value = LaunchOptions.get_string("turn").to_float()
	if LaunchOptions.has("pose"):
		var pose := page.find_child("PoseChoice", true, false) as OptionButton
		var index := ["Idle", "Walk", "Sprint", "Jump"].find(LaunchOptions.get_string("pose"))
		pose.select(maxi(index, 0))
		pose.item_selected.emit(maxi(index, 0))
	await get_tree().create_timer(1.0, true).timeout
	RenderingServer.force_draw(false)
	if LaunchOptions.has("screenshot"):
		var path := LaunchOptions.get_string("screenshot")
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved customization preview: ", path)
		get_tree().quit()
