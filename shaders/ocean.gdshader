// Ocean surface: a few moving sine waves for the normal and a Fresnel sky tint.
// Each wave fades out once it gets too small on screen, to avoid shimmer, and
// broad patches of calmer and choppier water break up their regular stripes.
// Toward the edge of the plane the ocean fades fully into the fog (which
// matches the sky below the horizon), so the edge never shows.
// With the time of day (shaders/night.gdshaderinc) it takes on the low sun's
// warmth at dusk; at night it goes dark, the moon (the one light at night)
// glitters on the waves, and the city's lights shine faintly off it at
// grazing angles.
shader_type spatial;

global uniform float night;
global uniform float dusk;
global uniform float city_lights;

uniform vec3 deep_color : source_color = vec3(0.04, 0.10, 0.13);
uniform vec3 sky_tint : source_color = vec3(0.34, 0.40, 0.46);
// How much the waves' strength varies from patch to patch (0 = uniform).
uniform float patchiness : hint_range(0.0, 1.0) = 0.8;
// World position of the scene origin (WorldOrigin.offset), so waves don't jump on shifts.
uniform vec2 origin_offset = vec2(0.0);
// The environment's fog (set by ocean.gd, linear color), and the distance
// range over which the ocean fades out completely.
uniform vec3 fog_color = vec3(0.45, 0.55, 0.69);
uniform float fog_density = 0.00005;
uniform float fade_start = 24000.0;
uniform float fade_end = 38000.0;
// The water's color and the sky in it, at dusk and at night; the city's
// lights at grazing angles at night.
uniform vec3 dusk_sky_tint : source_color = vec3(0.95, 0.66, 0.52);
uniform vec3 night_deep_color : source_color = vec3(0.01, 0.03, 0.06);
uniform vec3 night_sky_tint : source_color = vec3(0.10, 0.13, 0.24);
uniform vec3 city_light_tint : source_color = vec3(1.0, 0.62, 0.32);
uniform float city_light_strength = 0.25;

varying vec2 world_xz;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + origin_offset;
}

// Slope (dh/dx, dh/dz) of one wave: direction, wavelength (m), amplitude (m), speed (m/s).
// pixel_size is the ground size of one screen pixel, in meters.
vec2 wave_slope(vec2 p, float pixel_size, vec2 direction, float wavelength, float amplitude, float speed) {
	float k = 6.2831853 / wavelength;
	vec2 d = normalize(direction);
	float fade = 1.0 - smoothstep(0.1, 0.35, pixel_size / wavelength);
	return d * (fade * k * amplitude * cos(k * (dot(d, p) - speed * TIME)));
}

void fragment() {
	vec2 footprint = fwidth(world_xz);
	float pixel_size = max(footprint.x, footprint.y);
	vec2 slope = wave_slope(world_xz, pixel_size, vec2(1.0, 0.3), 23.0, 0.07, 4.0)
			+ wave_slope(world_xz, pixel_size, vec2(-0.4, 1.0), 11.0, 0.05, 2.8)
			+ wave_slope(world_xz, pixel_size, vec2(0.7, -0.8), 5.3, 0.03, 1.9)
			+ wave_slope(world_xz, pixel_size, vec2(-1.0, -0.2), 2.1, 0.012, 1.2);
	slope *= 1.0 - patchiness * value_noise(world_xz * 0.006 + vec2(TIME * 0.01, 0.0));

	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	vec3 deep = deep_color;
	vec3 tint = sky_tint;
	if (dusk > 0.0 || night > 0.0) {
		deep = mix(deep_color, night_deep_color, night);
		tint = mix(mix(sky_tint, dusk_sky_tint, dusk), night_sky_tint, night);
	}
	ALBEDO = deep;
	EMISSION = tint * fresnel * 0.5;
	if (city_lights > 0.0) {
		EMISSION += city_light_tint * (city_light_strength * city_lights * fresnel * (0.6 + 0.4 * value_noise(world_xz * 0.05)));
	}
	ROUGHNESS = 0.2;
	SPECULAR = 0.5;

	// The same exponential fog the environment applies, plus the fade-out.
	float distance = length(VERTEX);
	float fog = 1.0 - exp(-distance * fog_density);
	FOG = vec4(fog_color, max(fog, smoothstep(fade_start, fade_end, distance)));
}
