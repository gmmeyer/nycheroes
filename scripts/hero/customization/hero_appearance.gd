class_name HeroAppearance
extends RefCounted
## Versioned, deliberately small cosmetic payload. Only known names and opaque
## RGB colors may cross the save/network boundary; no paths or resources load.
const KEY := "hero_appearance"
const VERSION := 1
const OPTIONS := {
	"suit": ["vector", "meridian", "velocity", "leotard", "longsleeve", "mech"],
	"cape": ["none", "short", "long", "split"],
	"hair": ["none", "crop", "swept", "curls", "crest", "ponytail"],
	"boots": ["ankle", "tall", "armored"],
	"headgear": ["none", "visor", "mask", "crown", "helmet"],
}
const LABELS := {
	"suit": ["Vector bodysuit", "Meridian bodysuit", "Velocity unitard", "Arc leotard", "Long-sleeve leotard", "Aegis mech suit"],
	"cape": ["No cape", "Shoulder cape", "Full cape", "Split cape"],
	"hair": ["Shaved", "Close crop", "Swept waves", "Coils", "High crest", "Ponytail"],
	"boots": ["Ankle boots", "Knee boots", "Armored boots"],
	"headgear": ["Open face", "Flight visor", "Eye mask", "Crest circlet", "Mech helmet"],
}
const DEFAULT := {"version": VERSION, "suit": "vector", "cape": "short", "hair": "swept", "boots": "tall", "headgear": "visor", "primary": "137f8c", "secondary": "13253b", "accent": "ffc66d", "skin": "b97a57", "hair_color": "261c26"}
const COLORS := ["primary", "secondary", "accent", "skin", "hair_color"]
const PALETTES := [
	["Harbor", "137f8c", "13253b", "ffc66d"],
	["Solar", "d88724", "291e3c", "f5e6ad"],
	["Orchid", "8449ac", "202e4d", "7fe5cc"],
	["Ember", "b84037", "232a35", "efc578"],
	["Glacier", "c9e5e6", "305579", "71ddff"],
	["Verdant", "34836b", "172a32", "d8e77c"],
]

static func sanitize(value: Variant) -> Dictionary:
	var result := DEFAULT.duplicate()
	if not value is Dictionary:
		return result
	# A future schema is not interpreted as the current schema.
	if value.has("version") and value.version != VERSION:
		return result
	for key: String in OPTIONS:
		if value.get(key) is String and value[key] in OPTIONS[key]:
			result[key] = value[key]
	for key: String in COLORS:
		var raw: Variant = value.get(key)
		if raw is String and raw.length() == 6 and Color.html_is_valid(raw):
			result[key] = raw.to_lower()
	return result

static func current() -> Dictionary:
	return sanitize(Settings.get_value(KEY, DEFAULT))

static func save(value: Dictionary) -> void:
	Settings.set_value(KEY, sanitize(value))

static func color(profile: Dictionary, key: String) -> Color:
	return Color.html("#" + str(profile[key]))

static func randomized() -> Dictionary:
	var result := DEFAULT.duplicate()
	for key: String in OPTIONS:
		result[key] = OPTIONS[key].pick_random()
	var palette: Array = PALETTES.pick_random()
	for i in 3:
		result[COLORS[i]] = palette[i + 1]
	result.skin = ["f0c7a5", "d39b75", "b97a57", "875438", "513326"].pick_random()
	result.hair_color = ["171a24", "38211d", "ad7843", "ded2b6", "793f79"].pick_random()
	return result
