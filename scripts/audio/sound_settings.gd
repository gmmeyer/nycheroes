class_name SoundSettings
## The sound's settings, kept by Settings between visits: whether it's
## switched off (N, the touch speaker button, the options menu), and the
## options menu's volumes for the Master bus, Effects (the SFX bus: the hero
## and fights) and Ambience (the city, cars and trains). ?mute=1 / ?mute=0
## (--mute=1 on desktop) overrides the switch for the session. A volume is a
## share (0..1), squared on its way to the bus, so half way sounds about half
## as loud (-12 dB).

const MUTED := "muted"
const VOLUMES := {"volume_master": &"Master", "volume_effects": &"SFX", "volume_ambience": &"Ambience"}
## A volume of 0 sets the bus this low (dB).
const SILENT_DB := -80.0


static func load_muted() -> bool:
	var forced := LaunchOptions.get_string("mute")
	if forced == "1" or forced == "0":
		return forced == "1"
	return bool(Settings.get_value(MUTED, false))


static func save_muted(muted: bool) -> void:
	Settings.set_value(MUTED, muted)


## A volume setting (one of VOLUMES' keys), 0..1.
static func volume(key: String) -> float:
	return clampf(float(Settings.get_value(key, 1.0)), 0.0, 1.0)


## Sets the buses' volumes from the settings.
static func apply_volumes() -> void:
	for key: String in VOLUMES:
		var bus := AudioServer.get_bus_index(VOLUMES[key])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, volume_db(volume(key)))


static func volume_db(share: float) -> float:
	return linear_to_db(share * share) if share > 0.0 else SILENT_DB
