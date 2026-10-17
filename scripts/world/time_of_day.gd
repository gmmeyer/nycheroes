class_name TimeOfDay
extends Node
## The clock, and the light that follows it: the sun's (at night, the moon's)
## direction, color and energy, the environment's ambient light (for the
## characters), fog and exposure, the sky's colors, and the project-wide
## shader globals the city's shaders read (shaders/night.gdshaderinc): night
## (0 by day .. 1 at night), dusk (the warmth of a low sun), city_lights (how
## far street lights, windows and signs are on) and clock_hours.
##
## The day is the scene as world.tscn sets it up (after LightingOverrides'
## launch options), captured at the start, so the default afternoon looks
## exactly as it always has. Dusk, dawn and night are keyframes here, blended
## in by the sun's elevation. The sun follows New York's arc on April 6
## (declination 6.5 degrees, solar noon at 12:59 daylight time), which puts it
## where the scene's sun is (azimuth 235, elevation 42) at the default 15:30;
## ?date picks another day's arc. A full moon follows the opposite arc, and
## takes over the one directional light once the sun is down.
##
## Launch options: ?time=HH:MM a fixed clock (default 15:30);
## ?date=MM-DD (or YYYY-MM-DD) the sun's arc on that day, on New York's clock
## (daylight saving time in summer), with T's dawn and dusk moved to match;
## ?daylength=MINUTES a running cycle, a whole day in that many real minutes;
## ?weather=overcast a gray day (default clear): the sky closes into a bright
## deck of gray cloud (sky.gdshader's overcast) over darker, more contrasty
## streets, the sun dims to a soft light with faint shadows, the shade fills
## in from the sky (the city materials' toon ambient), glass and water turn
## gray, and the fog thickens and grays;
## dusk and night follow with their own overcast looks (no moon or stars, the
## city's glow on the clouds).
## T (Game) steps on to the next of day, dusk, night and dawn, and the
## options menu goes to one (go_to()). With
## ?sun_dir=az,el (LightingOverrides) the sun keeps that direction while up.

## Where the clock starts without ?time: the scene's afternoon.
const DEFAULT_CLOCK := 15.5
## What T steps through, in the order they come: dawn, day, dusk, night.
const PRESETS: Array[float] = [6.75, 15.5, 19.15, 22.5]

## The sun's arc: New York's latitude and longitude, and the sun's declination
## and solar noon (hours) without ?date, solved so the sun stands at the
## scene's azimuth and elevation at DEFAULT_CLOCK (April 6's, to a minute).
const LATITUDE := 40.76
const LONGITUDE := -73.98
const DECLINATION := 6.546428
const SOLAR_NOON := 12.980544
## T's dawn and dusk stand where the sun is about this high (degrees); with
## ?date they move with it.
const PRESET_SUN_HEIGHT := 2.0
## The light turns from the sun to the moon at this sun elevation (degrees),
## when both are dark.
const MOON_TAKES_OVER := -1.0
## A clock running on its own re-lights the city once it's moved this far
## (hours: half a minute), and at most every MIN_INTERVAL seconds, not every
## frame (each re-light also re-renders the sky's reflections: about 0.4 ms
## on the web, measured).
const MIN_STEP := 1.0 / 120.0
const MIN_INTERVAL := 0.1

## Dusk (evening), dawn and night. Colors are sRGB, as in the editor. The
## day's values come from the scene. below_color is the sky under the
## horizon, which matches the fog. A low sun keeps the sky blue overhead, a
## pale horizon with a warm band under the sun (sky.gdshader), gold light and
## blue shade. The night's AgX contrast and white are the scene's, so the
## night looks the same whatever dusk and an overcast set.
const DUSK := {
	"light_color": Color(1.0, 0.68, 0.36),
	"fog_color": Color(0.78, 0.76, 0.75),
	"fog": 1.0,
	"ambient_color": Color(0.62, 0.68, 0.88),
	"ambient_energy": 0.55,
	"exposure": 1.25,
	"agx_contrast": 1.25,
	"zenith_color": Color(0.24, 0.56, 1.06),
	"horizon_color": Color(0.86, 0.78, 0.68),
	"below_color": Color(0.78, 0.76, 0.75),
	"sun_color": Color(1.0, 0.60, 0.30),
	"sun_glow": 1.0,
	"cloud_lit": Color(1.0, 0.82, 0.62),
	"cloud_shade": Color(0.58, 0.58, 0.68),
}
const DAWN := {
	"light_color": Color(1.0, 0.74, 0.48),
	"fog_color": Color(0.80, 0.77, 0.78),
	"fog": 1.0,
	"ambient_color": Color(0.64, 0.70, 0.90),
	"ambient_energy": 0.55,
	"exposure": 1.25,
	"agx_contrast": 1.25,
	"zenith_color": Color(0.26, 0.56, 1.04),
	"horizon_color": Color(0.88, 0.80, 0.76),
	"below_color": Color(0.80, 0.77, 0.78),
	"sun_color": Color(1.0, 0.66, 0.42),
	"sun_glow": 0.9,
	"cloud_lit": Color(1.0, 0.84, 0.76),
	"cloud_shade": Color(0.60, 0.60, 0.72),
}
const NIGHT := {
	"light_color": Color(0.55, 0.66, 1.0),
	"fog_color": Color(0.10, 0.11, 0.17),
	"fog": 1.0,
	"ambient_color": Color(0.50, 0.58, 0.85),
	"ambient_energy": 0.55,
	"exposure": 1.15,
	"agx_contrast": 1.05,
	"agx_white": 16.29,
	"zenith_color": Color(0.015, 0.03, 0.085),
	"horizon_color": Color(0.10, 0.12, 0.22),
	"below_color": Color(0.10, 0.11, 0.17),
	"sun_color": Color(1.0, 0.55, 0.28),
	"sun_glow": 0.0,
	"cloud_lit": Color(0.20, 0.23, 0.32),
	"cloud_shade": Color(0.06, 0.07, 0.11),
}
## Overcast: the day, dusk, dawn and night looks under a closed gray sky,
## used instead of the scene's day and the keyframes above. below_color
## matches the fog here too, and the horizon fades into it. The 3-D buffer
## clamps at 1 before tone mapping, so no sky gets brighter than what AgX
## makes of 1: AgX white 2 (its minimum) lifts that for the bright deck,
## and lower exposure and more AgX contrast darken the streets under it.
const OVERCAST := {
	"light_color": Color(0.96, 0.97, 1.0),
	"fog_color": Color(0.92, 0.93, 0.95),
	"fog": OVERCAST_FOG,
	"ambient_color": Color(0.80, 0.82, 0.86),
	"ambient_energy": 0.7,
	"exposure": 0.9,
	"agx_contrast": 1.3,
	"agx_white": 2.0,
	"zenith_color": Color(1.30, 1.32, 1.36),
	"horizon_color": Color(0.92, 0.93, 0.95),
	"below_color": Color(0.92, 0.93, 0.95),
	"sun_color": Color(1.0, 0.97, 0.92),
	"sun_glow": 0.0,
	"cloud_lit": Color(1.22, 1.23, 1.25),
	"cloud_shade": Color(0.68, 0.70, 0.75),
}
const OVERCAST_DUSK := {
	"light_color": Color(1.0, 0.78, 0.62),
	"fog_color": Color(0.54, 0.50, 0.52),
	"fog": OVERCAST_FOG,
	"ambient_color": Color(0.68, 0.66, 0.74),
	"ambient_energy": 0.6,
	"exposure": 1.1,
	"agx_contrast": 1.3,
	"zenith_color": Color(0.30, 0.31, 0.37),
	"horizon_color": Color(0.54, 0.50, 0.52),
	"below_color": Color(0.54, 0.50, 0.52),
	"sun_color": Color(1.0, 0.62, 0.40),
	"sun_glow": 0.0,
	"cloud_lit": Color(0.58, 0.50, 0.50),
	"cloud_shade": Color(0.31, 0.30, 0.35),
}
const OVERCAST_DAWN := {
	"light_color": Color(1.0, 0.82, 0.72),
	"fog_color": Color(0.56, 0.53, 0.57),
	"fog": OVERCAST_FOG,
	"ambient_color": Color(0.70, 0.69, 0.78),
	"ambient_energy": 0.6,
	"exposure": 1.1,
	"agx_contrast": 1.3,
	"zenith_color": Color(0.32, 0.33, 0.40),
	"horizon_color": Color(0.56, 0.53, 0.57),
	"below_color": Color(0.56, 0.53, 0.57),
	"sun_color": Color(1.0, 0.70, 0.55),
	"sun_glow": 0.0,
	"cloud_lit": Color(0.60, 0.55, 0.58),
	"cloud_shade": Color(0.33, 0.32, 0.38),
}
const OVERCAST_NIGHT := {
	"light_color": Color(0.55, 0.66, 1.0),
	"fog_color": Color(0.15, 0.13, 0.15),
	"fog": OVERCAST_FOG,
	"ambient_color": Color(0.56, 0.56, 0.72),
	"ambient_energy": 0.55,
	"exposure": 1.15,
	"agx_contrast": 1.05,
	"agx_white": 16.29,
	"zenith_color": Color(0.05, 0.05, 0.07),
	"horizon_color": Color(0.15, 0.13, 0.15),
	"below_color": Color(0.15, 0.13, 0.15),
	"sun_color": Color(1.0, 0.55, 0.28),
	"sun_glow": 0.0,
	"cloud_lit": Color(0.13, 0.12, 0.14),
	"cloud_shade": Color(0.07, 0.07, 0.09),
}
## Overcast: the sun's (and moon's) energy and shadows' strength as a share
## of a clear day's, and how much thicker the fog is than at dusk.
const OVERCAST_SUN_ENERGY := 0.3
const OVERCAST_SHADOW_OPACITY := 0.6
const OVERCAST_FOG := 1.3
## Overcast: uniforms of the city's materials (the toon ambient of
## toon.gdshaderinc: the gray sky fills in the shade, and walls get less
## bounce from the dull streets, less still at their feet in the canyons,
## and what sees little sky (narrow streets, under decks) is darker still, as
## all the light is the sky's; building glass's reflections) and the ocean's (its sky reflection and
## depth), wherever a material has them. Colors replace, numbers scale.
const OVERCAST_MATERIALS := {
	"ambient_sky": Color(0.80, 0.82, 0.86),
	"ambient_ground": Color(0.50, 0.50, 0.50),
	"ambient_energy": 1.12,
	"ambient_wall_bounce": 0.4,
	"canyon_occlusion": 0.65,
	"sky_light": Vector2(0.95, 0.85),
	"reflect_zenith": Color(0.60, 0.63, 0.68),
	"reflect_horizon": Color(0.77, 0.79, 0.82),
	"sky_tint": Color(0.50, 0.53, 0.57),
	"deep_color": Color(0.05, 0.11, 0.13),
}
## Dusk and dawn as the city's glass and the water reflect them (building and
## landmark glass, the ocean's sky), set once at the start: blue overhead and
## the pale horizon of the DUSK sky, not orange all round.
const DUSK_MATERIALS := {
	"dusk_reflect_zenith": Color(0.30, 0.46, 0.78),
	"dusk_reflect_horizon": Color(0.90, 0.80, 0.70),
	"dusk_sky_tint": Color(0.52, 0.48, 0.47),
}
## The sky material's uniforms the keyframes set.
const SKY_KEYS: Array[String] = ["zenith_color", "horizon_color", "below_color", "sun_color", "sun_glow",
	"cloud_lit", "cloud_shade"]
## The low sun's energy, as a share of the day's.
const DUSK_SUN_ENERGY := 1.15
## The moon: its light's color (sRGB) and energy.
const MOON_COLOR := Color(0.55, 0.66, 1.0)
const MOON_ENERGY := 0.2

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## Told how far the city's lights are on (its lamps' glow and light map);
## its materials turn gray with an overcast.
@export var city: CityStreamer
## Its water turns gray with an overcast.
@export var ocean: GeometryInstance3D
## How long T takes to get to the next time of day (s).
@export var transition_seconds := 2.0

## The time of day, in hours (0..24).
var clock := DEFAULT_CLOCK
## A running cycle's length (real minutes per day), or 0 for a fixed clock.
var day_length := 0.0
## The current amounts (see the shader globals above).
var night := 0.0
var dusk := 0.0
var city_lights := 0.0
## The weather (?weather): "clear" or "overcast", and how overcast (0..1).
var weather := "clear"
var overcast := 0.0
## The sun's arc (see DECLINATION; ?date changes it).
var declination := DECLINATION
var solar_noon := SOLAR_NOON

var _day := {}
## The preset's fog density (see _keep_fog()); 0 until it's known, or with ?fog.
var _fog := 0.0
var _presets: Array[float] = PRESETS.duplicate()
var _sky: ShaderMaterial
var _sun_pinned := false
var _applied_clock := INF
var _since_applied := 0.0
## A T transition: where it started, how far it goes (hours) and how far along it is (0..1).
var _transition_from := 0.0
var _transition_hours := 0.0
var _transition := 1.0


func _ready() -> void:
	var env := world_environment.environment
	_sky = env.sky.sky_material as ShaderMaterial if env.sky else null
	_sun_pinned = LaunchOptions.has("sun_dir")
	_day = {
		"light_color": sun.light_color,
		"light_energy": sun.light_energy,
		"fog_color": env.fog_light_color,
		"fog": Quality.clear_fog(),
		"ambient_color": env.ambient_light_color,
		"ambient_energy": env.ambient_light_energy,
		"exposure": env.tonemap_exposure,
		"agx_contrast": env.tonemap_agx_contrast,
		"agx_white": env.tonemap_agx_white,
	}
	if _sky:
		for key in SKY_KEYS:
			var value: Variant = _sky_value(key)
			if value != null:  # (headless, shaders have no defaults)
				_day[key] = value
	var time := LaunchOptions.get_string("time")
	if not time.is_empty():
		clock = parse_clock(time)
	var date := LaunchOptions.get_string("date")
	if not date.is_empty():
		_set_date(date)
	day_length = maxf(LaunchOptions.get_string("daylength", "0").to_float(), 0.0)
	for material in _city_materials():
		for key: String in DUSK_MATERIALS:
			if _material_value(material, key) != null:
				material.set_shader_parameter(key, DUSK_MATERIALS[key])
	if LaunchOptions.get_string("weather") == "overcast":
		_set_overcast()
	_apply()
	if not LaunchOptions.has("fog"):
		_keep_fog.call_deferred()


func _process(delta: float) -> void:
	if _transition < 1.0:
		_transition = minf(_transition + delta / transition_seconds, 1.0)
		clock = fposmod(_transition_from + _transition_hours * smoothstep(0.0, 1.0, _transition), 24.0)
		_apply()
	elif day_length > 0.0:
		clock = fposmod(clock + delta * 24.0 / (day_length * 60.0), 24.0)
		_since_applied += delta
		if _since_applied >= MIN_INTERVAL and absf(clock - _applied_clock) >= MIN_STEP:
			_apply()


## Sets the clock (hours) right away, e.g. for a scripted tour.
func set_clock(hours: float) -> void:
	_transition = 1.0
	clock = fposmod(hours, 24.0)
	_apply()


## Puts the sun on New York's arc for "MM-DD" or "YYYY-MM-DD" (this year if
## none), on daylight saving time from the second Sunday in March to the first
## Sunday in November, and moves T's dawn and dusk with its sunrise and sunset.
## The sun's position is the Astronomical Almanac's low-precision one (good to
## about a minute, 1950-2050), at noon in New York.
func _set_date(text: String) -> void:
	var parts := text.split("-")
	if parts.size() < 2:
		push_warning("?date=%s: expected MM-DD or YYYY-MM-DD" % text)
		return
	var year: int = parts[0].to_int() if parts.size() > 2 else Time.get_date_dict_from_system().year
	var month := parts[-2].to_int()
	var day := parts[-1].to_int()
	# Days from 2000-01-01 12:00 UTC to 17:00 UTC that day.
	var noon := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 17})
	var days := noon / 86400.0 - 10957.5
	var mean_longitude := 280.460 + 0.9856474 * days
	var anomaly := deg_to_rad(357.528 + 0.9856003 * days)
	var longitude := deg_to_rad(mean_longitude + 1.915 * sin(anomaly) + 0.020 * sin(2.0 * anomaly))
	var obliquity := deg_to_rad(23.439 - 0.0000004 * days)
	declination = rad_to_deg(asin(sin(obliquity) * sin(longitude)))
	var right_ascension := rad_to_deg(atan2(cos(obliquity) * sin(longitude), cos(longitude)))
	var equation_of_time := 4.0 * wrapf(mean_longitude - right_ascension, -180.0, 180.0)  # minutes
	var utc_offset := -4.0 if _daylight_saving(year, month, day) else -5.0
	solar_noon = 12.0 - LONGITUDE / 15.0 - equation_of_time / 60.0 + utc_offset
	var longer := _half_day(declination) - _half_day(DECLINATION)
	var later := solar_noon - SOLAR_NOON
	_presets = [PRESETS[0] + later - longer, PRESETS[1], PRESETS[2] + later + longer, PRESETS[3]]


## Moves on to the next of dawn, day, dusk and night, over transition_seconds.
func step_forward() -> void:
	var next := _presets[0]
	for preset in _presets:
		if preset > clock + 0.01:
			next = preset
			break
	_transition_from = clock
	_transition_hours = fposmod(next - clock, 24.0)
	_transition = 0.0


## Goes to dawn, day, dusk or night (0..3, the order T steps through them)
## the short way round, over transition_seconds; at once while the game is
## paused (the options menu).
func go_to(preset: int) -> void:
	var target := _presets[clampi(preset, 0, _presets.size() - 1)]
	if not can_process():
		set_clock(target)
		return
	_transition_from = clock
	_transition_hours = wrapf(target - clock, -12.0, 12.0)
	_transition = 0.0


## Quality changed its preset while playing: the haze of dusk and night
## (see _keep_fog(); not with ?fog) and a clear day's share of it.
func set_quality_fog(density: float) -> void:
	_day["fog"] = Quality.clear_fog()
	if _fog > 0.0:
		_fog = density
	_apply()


## The clock as HH:MM.
func clock_text() -> String:
	var minutes := int(clock * 60.0 + 0.5) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Day, dusk, night or dawn, by the sun's height.
func phase_name() -> String:
	var elevation := sun_position(clock).y
	if elevation > 6.0:
		return "day"
	if elevation < -6.0:
		return "night"
	return "dawn" if clock < 12.0 else "dusk"


## Hours from "HH:MM" (or "HH", "HH.5").
static func parse_clock(text: String) -> float:
	var parts := text.split(":")
	var hours := parts[0].to_float()
	if parts.size() > 1:
		hours += parts[1].to_float() / 60.0
	return fposmod(hours, 24.0)


## The sun's (azimuth, elevation) in degrees at this clock: azimuth clockwise
## from north. With `opposite`, the full moon's, across the sky from it.
func sun_position(hours: float, opposite := false) -> Vector2:
	var hour_angle := deg_to_rad(15.0 * (hours - solar_noon + (12.0 if opposite else 0.0)))
	var tilt := deg_to_rad(-declination if opposite else declination)
	var latitude := deg_to_rad(LATITUDE)
	var elevation := asin(sin(latitude) * sin(tilt) + cos(latitude) * cos(tilt) * cos(hour_angle))
	var azimuth := atan2(-sin(hour_angle) * cos(tilt),
		cos(latitude) * sin(tilt) - sin(latitude) * cos(tilt) * cos(hour_angle))
	return Vector2(fposmod(rad_to_deg(azimuth), 360.0), rad_to_deg(elevation))


## Hours from solar noon until the sun is down to PRESET_SUN_HEIGHT, on the
## arc with this declination (degrees).
static func _half_day(tilt_degrees: float) -> float:
	var latitude := deg_to_rad(LATITUDE)
	var tilt := deg_to_rad(tilt_degrees)
	var cos_angle := (sin(deg_to_rad(PRESET_SUN_HEIGHT)) - sin(latitude) * sin(tilt)) / (cos(latitude) * cos(tilt))
	return rad_to_deg(acos(clampf(cos_angle, -1.0, 1.0))) / 15.0


## Whether New York's clocks are on daylight saving time on that day.
static func _daylight_saving(year: int, month: int, day: int) -> bool:
	if month != 3 and month != 11:
		return month > 3 and month < 11
	var first := Time.get_datetime_dict_from_unix_time(
		Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 1}))
	var first_sunday: int = 1 + (7 - int(first.weekday)) % 7
	return day >= first_sunday + 7 if month == 3 else day < first_sunday


## Unit vector toward a body at (azimuth, elevation) degrees: x east, y up, z south.
static func direction_to(position: Vector2) -> Vector3:
	var azimuth := deg_to_rad(position.x)
	var elevation := deg_to_rad(position.y)
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))


func _apply() -> void:
	_applied_clock = clock
	_since_applied = 0.0
	var sun_at := sun_position(clock)
	var moon_at := sun_position(clock, true)
	var elevation := sun_at.y
	night = _ramp(2.0, -9.0, elevation)
	dusk = _ramp(20.0, 4.0, elevation) * _ramp(-11.0, -3.0, elevation)
	city_lights = _ramp(8.0, -4.0, elevation)
	var look := _look(dusk, night, clock < 12.0)

	var sun_direction := direction_to(sun_at)
	if elevation > MOON_TAKES_OVER:
		if not _sun_pinned:
			sun.rotation = LightingOverrides.sun_rotation(sun_at.x, sun_at.y)
		# The light shines along its -z axis: the sky's sun is exactly where it is.
		sun_direction = sun.global_basis.z.normalized()
		sun.light_color = look.light_color
		sun.light_energy = (_day.light_energy * lerpf(1.0, DUSK_SUN_ENERGY, dusk) * _ramp(MOON_TAKES_OVER, 3.0, elevation)
			* lerpf(1.0, OVERCAST_SUN_ENERGY, overcast))
	else:
		sun.rotation = LightingOverrides.sun_rotation(moon_at.x, moon_at.y)
		sun.light_color = MOON_COLOR
		sun.light_energy = (MOON_ENERGY * _ramp(MOON_TAKES_OVER, -8.0, elevation) * _ramp(-3.0, 8.0, moon_at.y)
			* lerpf(1.0, OVERCAST_SUN_ENERGY, overcast))

	var env := world_environment.environment
	env.fog_light_color = look.fog_color
	if _fog > 0.0:
		env.fog_density = _fog * look.fog
	env.ambient_light_color = look.ambient_color
	env.ambient_light_energy = look.ambient_energy
	env.tonemap_exposure = look.exposure
	env.tonemap_agx_contrast = look.agx_contrast
	env.tonemap_agx_white = look.agx_white
	if _sky:
		for key in SKY_KEYS:
			if look.has(key):
				_sky.set_shader_parameter(key, look[key])
		_sky.set_shader_parameter("sun_direction", sun_direction)
		_sky.set_shader_parameter("moon_direction", direction_to(moon_at))

	RenderingServer.global_shader_parameter_set("night", night)
	RenderingServer.global_shader_parameter_set("dusk", dusk)
	RenderingServer.global_shader_parameter_set("city_lights", city_lights)
	RenderingServer.global_shader_parameter_set("clock_hours", clock)
	if city:
		city.city_lights = city_lights


## The day's look blended toward dusk (or dawn, in the morning), then night;
## with an overcast, its own looks.
func _look(dusk_amount: float, night_amount: float, morning: bool) -> Dictionary:
	var warm := _blend(DAWN if morning else DUSK, OVERCAST_DAWN if morning else OVERCAST_DUSK, overcast)
	var dark := _blend(NIGHT, OVERCAST_NIGHT, overcast)
	var look := {}
	for key: String in _day:
		var value: Variant = _day[key]
		if OVERCAST.has(key):
			value = lerp(value, OVERCAST[key], overcast)
		if warm.has(key):
			value = lerp(value, warm[key], dusk_amount)
		if dark.has(key):
			value = lerp(value, dark[key], night_amount)
		look[key] = value
	return look


## Keyframe `a` blended toward `b` (the same keys) by t.
static func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if t <= 0.0:
		return a
	var out := {}
	for key: String in a:
		out[key] = lerp(a[key], b[key], t)
	return out


## Turns the day overcast (see OVERCAST...): the sky's deck of cloud, faint
## shadows, the materials' gray ambient (and thicker fog: OVERCAST_FOG).
func _set_overcast() -> void:
	weather = "overcast"
	overcast = 1.0
	if _sky:
		_sky.set_shader_parameter("overcast", overcast)
	sun.shadow_opacity = lerpf(1.0, OVERCAST_SHADOW_OPACITY, overcast)
	for material in _city_materials():
		for key: String in OVERCAST_MATERIALS:
			var value: Variant = _material_value(material, key)
			if value == null:
				continue
			var target: Variant = OVERCAST_MATERIALS[key]
			material.set_shader_parameter(key, lerp(value, target if target is Color else value * target, overcast))


## Takes the fog Quality's preset has set (after every node's _ready) as the
## haze of dusk and night, which each look scales ("fog": thinner on a clear
## day, Quality.clear_fog(); thicker overcast, OVERCAST_FOG).
func _keep_fog() -> void:
	_fog = world_environment.environment.fog_density
	_apply()


## The city's materials and the ocean's (the ones DUSK_MATERIALS and
## OVERCAST_MATERIALS set).
func _city_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	if city:
		for material in [city.building_material, city.ground_material, city.markings_material, city.tree_material,
				city.water_tower_material, city.street_light_material, city.street_furniture_material, city.car_material,
				city.landmark_material, city.church_material, city.fronts_material,
				city.waterfront_material]:
			if material is ShaderMaterial:
				materials.append(material)
	if ocean and ocean.material_override is ShaderMaterial:
		materials.append(ocean.material_override)
	return materials


## The sky material's value of a uniform (its shader's default if never set),
## as a Color for colors.
func _sky_value(key: String) -> Variant:
	return _material_value(_sky, key)


## A material's value of a uniform (its shader's default if never set; null
## if it has none), as a Color for colors.
static func _material_value(material: ShaderMaterial, key: String) -> Variant:
	var value: Variant = material.get_shader_parameter(key)
	if value == null and material.shader:
		value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)
	if value is Vector3:
		value = Color(value.x, value.y, value.z)
	return value


## 0 at `from`, 1 at `to` (either way round), smooth in between.
static func _ramp(from: float, to: float, x: float) -> float:
	var t := clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
