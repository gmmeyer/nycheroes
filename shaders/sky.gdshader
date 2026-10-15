// Stylized sky: a clean blue gradient that pales toward the horizon, a warm
// glow and disk for the sun, and soft cartoon clouds lit from the sun's side.
// Below the horizon it's the fog color, so the ocean's far edge fades into it.
// TimeOfDay (scripts/world/time_of_day.gd) sets its colors through the day,
// and the sun's and moon's directions. At dusk and dawn a warm band glows
// along the horizon under the sun; at night the city's orange glow rises along
// the horizon and lights the clouds from below, the moon lights their edges,
// and stars come out above the glow (anti-aliased: each at least a pixel and
// a half wide, dimmer when widened, so they never shimmer).
// It doesn't use TIME, so the engine renders its reflections only once (and
// again when the time of day changes).
shader_type sky;

#include "res://shaders/patterns.gdshaderinc"

// The time of day (see shaders/night.gdshaderinc).
global uniform float night;
global uniform float dusk;

uniform vec3 zenith_color : source_color = vec3(0.28, 0.52, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.86, 0.93);
// Under the horizon; keep it equal to the environment's fog color.
uniform vec3 below_color : source_color = vec3(0.76, 0.83, 0.90);
// Higher pushes the deep blue closer to the horizon.
uniform float gradient_power : hint_range(0.1, 2.0) = 0.5;
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
// Sun disk radius and glow strength.
uniform float sun_size_degrees = 1.2;
uniform float sun_glow = 0.6;
// Share of the sky covered by clouds, their size, and their colors on the
// sunny and shaded sides.
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.38;
uniform float cloud_scale = 1.6;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.68, 0.74, 0.88);
// Toward the sun and the moon (world space: x east, y up, z south), set by
// TimeOfDay; these are the scene's afternoon.
uniform vec3 sun_direction = vec3(-0.6088, 0.6691, 0.4263);
uniform vec3 moon_direction = vec3(0.6088, -0.6691, -0.4263);
// Dusk and dawn: the warm band along the horizon, brightest under the sun.
uniform float dusk_band = 0.4;
// Night: the city's glow along the horizon (and under the clouds), and how
// high it reaches (in sin(elevation)).
uniform vec3 city_glow : source_color = vec3(0.95, 0.55, 0.28);
uniform float city_glow_strength = 0.22;
uniform float city_glow_height = 0.07;
// Stars: share of sky cells with one, their brightness and size.
uniform float star_density : hint_range(0.0, 1.0) = 0.3;
uniform float star_brightness = 2.5;
uniform float star_size_degrees = 0.06;
// The moon: drawn larger than life, with a soft halo.
uniform float moon_size_degrees = 1.5;
uniform vec3 moon_color : source_color = vec3(0.97, 0.96, 0.88);
uniform float moon_brightness = 2.0;
uniform float moon_glow = 0.25;

float cloud_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), u.x),
			mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Cloud density, 0..1 (four octaves of noise).
float clouds(vec2 p) {
	return cloud_noise(p) * 0.55 + cloud_noise(p * 2.1 + 3.7) * 0.28
			+ cloud_noise(p * 4.3 + 9.1) * 0.12 + cloud_noise(p * 8.9 + 1.3) * 0.05;
}

// Stars around direction d (linear color): at most one in each cell of a
// grid on the faces of a cube around the sky, at a random spot in its cell
// away from the cell's edges (so no star is cut off). `pixel` is the angle a
// pixel spans (radians).
vec3 stars(vec3 d, float pixel) {
	const float CELLS = 72.0;
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = d.yz / a.x;
		face = d.x > 0.0 ? 1.0 : 2.0;
	} else if (a.y >= a.z) {
		uv = d.xz / a.y;
		face = d.y > 0.0 ? 3.0 : 4.0;
	} else {
		uv = d.xy / a.z;
		face = d.z > 0.0 ? 5.0 : 6.0;
	}
	vec2 cell = floor((uv * 0.5 + 0.5) * CELLS);
	vec2 salt = vec2(face * 131.7, face * 71.3);
	if (hash(cell + salt) > star_density) {
		return vec3(0.0);
	}
	vec2 spot = (cell + 0.25 + 0.5 * vec2(hash(cell + salt + 17.3), hash(cell + salt + 41.1))) / CELLS * 2.0 - 1.0;
	vec3 star;
	if (face < 2.5) {
		star = vec3(sign(d.x), spot);
	} else if (face < 4.5) {
		star = vec3(spot.x, sign(d.y), spot.y);
	} else {
		star = vec3(spot, sign(d.z));
	}
	float distance_to_star = length(normalize(star) - d);
	// Mostly faint, a few bright; a little bluer or warmer.
	float r = hash(cell + salt + 5.5);
	float brightness = 0.08 + 0.92 * r * r * r * r;
	float size = radians(star_size_degrees) * mix(0.7, 1.3, r);
	float radius = max(size, 1.5 * pixel);
	float energy = (size * size) / (radius * radius);
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.72), hash(cell + salt + 9.9));
	return tint * (star_brightness * brightness * energy * exp(-2.5 * distance_to_star * distance_to_star / (radius * radius)));
}

// The moon's disk (rgb) and coverage (a) around direction d, with darker seas.
vec4 moon(vec3 d, float pixel) {
	float radius = radians(moon_size_degrees);
	vec3 offset = d - moon_direction;
	float distance_to_moon = length(offset);
	float disk = 1.0 - smoothstep(radius - pixel, radius + pixel, distance_to_moon);
	if (disk <= 0.0) {
		return vec4(0.0);
	}
	// Coordinates across the disk (-1..1), from two directions square to the moon's.
	vec3 across = normalize(cross(moon_direction, vec3(0.0, 1.0, 0.0)));
	vec2 q = vec2(dot(offset, across), dot(offset, cross(across, moon_direction))) / radius;
	float seas = smoothstep(0.45, 0.6, value_noise(q * 2.2 + 4.0) * 0.7 + value_noise(q * 5.0 + 1.0) * 0.3);
	// A little darker toward the rim.
	float limb = 1.0 - 0.25 * dot(q, q);
	return vec4(moon_color * (moon_brightness * limb * (1.0 - 0.28 * seas)), disk);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = sun_direction;
	float up = max(d.y, 0.0);
	vec3 color = mix(horizon_color, zenith_color, pow(up, gradient_power));
	float toward_sun = max(dot(d, sun), 0.0);
	// A wide warm haze and a tighter glow around the sun.
	color += sun_color * (pow(toward_sun, 8.0) * 0.12 + pow(toward_sun, 90.0) * sun_glow) * (1.0 - night);
	// The light that lights the clouds: the sun, the moon at night.
	vec3 light = sun;
	float pixel = 0.0;
	if (dusk > 0.0) {
		// A warm band along the horizon, brightest under the sun.
		float under_sun = dot(normalize(d.xz + vec2(1e-5)), normalize(sun.xz + vec2(1e-5))) * 0.5 + 0.5;
		float low = pow(1.0 - up, 8.0);
		color += sun_color * (dusk_band * dusk * low * mix(0.2, 1.0, under_sun * under_sun));
	}
	if (night > 0.0) {
		light = normalize(mix(sun, moon_direction, night));
		float glow = exp(-up / city_glow_height);
		color += city_glow * (city_glow_strength * night * glow);
		if (!AT_CUBEMAP_PASS && d.y > 0.0) {
			pixel = length(fwidth(d));
			color += stars(d, pixel) * (night * (1.0 - smoothstep(0.0, 0.7, glow)));
			vec4 moon_disk = moon(d, pixel);
			color = mix(color, moon_disk.rgb, moon_disk.a * night);
		}
		// The moon's halo.
		color += moon_color * (pow(max(dot(d, moon_direction), 0.0), 300.0) * moon_glow * night);
	}

	if (d.y > 0.0) {
		// Projected onto a flat cloud layer, stretched a little along the wind.
		vec2 p = d.xz / (d.y + 0.15) * cloud_scale * vec2(1.0, 1.6);
		float density = clouds(p);
		float edge = 1.0 - cloud_cover;
		float cover = smoothstep(edge, edge + 0.06, density);
		// Lit where the cloud thins out toward the sun.
		float toward = clouds(p + normalize(light.xz + vec2(1e-4)) * 0.12);
		float lit = clamp((density - toward) * 9.0 + 0.55, 0.0, 1.0);
		vec3 cloud = mix(cloud_shade, cloud_lit, lit);
		cloud = mix(cloud, horizon_color, 1.0 - smoothstep(0.0, 0.3, d.y));
		if (night > 0.0) {
			// Lit from below by the city, most near the horizon.
			cloud += city_glow * (city_glow_strength * night * mix(0.35, 1.0, 1.0 - smoothstep(0.05, 0.5, d.y)));
		}
		color = mix(color, cloud, cover * smoothstep(0.02, 0.18, d.y));
	}

	float disk = smoothstep(cos(radians(sun_size_degrees)), cos(radians(sun_size_degrees * 0.8)), toward_sun);
	color = mix(color, sun_color * 4.0, disk);
	color = mix(color, below_color, smoothstep(0.0, -0.04, d.y));
	COLOR = color;
}
