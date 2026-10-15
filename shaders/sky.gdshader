// Stylized sky: a clean blue gradient that pales toward the horizon, a warm
// glow and disk for the sun, and soft cartoon clouds lit from the sun's side.
// Below the horizon it's the fog color, so the ocean's far edge fades into it.
// It doesn't use TIME, so the engine renders its reflections only once.
shader_type sky;

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

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Cloud density, 0..1 (four octaves of noise).
float clouds(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.1 + 3.7) * 0.28
			+ value_noise(p * 4.3 + 9.1) * 0.12 + value_noise(p * 8.9 + 1.3) * 0.05;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(-0.5, 0.6, 0.6));
	float up = max(d.y, 0.0);
	vec3 color = mix(horizon_color, zenith_color, pow(up, gradient_power));
	float toward_sun = max(dot(d, sun), 0.0);
	// A wide warm haze and a tighter glow around the sun.
	color += sun_color * (pow(toward_sun, 8.0) * 0.12 + pow(toward_sun, 90.0) * sun_glow);

	if (d.y > 0.0) {
		// Projected onto a flat cloud layer, stretched a little along the wind.
		vec2 p = d.xz / (d.y + 0.15) * cloud_scale * vec2(1.0, 1.6);
		float density = clouds(p);
		float edge = 1.0 - cloud_cover;
		float cover = smoothstep(edge, edge + 0.06, density);
		// Lit where the cloud thins out toward the sun.
		float toward = clouds(p + normalize(sun.xz + vec2(1e-4)) * 0.12);
		float lit = clamp((density - toward) * 9.0 + 0.55, 0.0, 1.0);
		vec3 cloud = mix(cloud_shade, cloud_lit, lit);
		cloud = mix(cloud, horizon_color, 1.0 - smoothstep(0.0, 0.3, d.y));
		color = mix(color, cloud, cover * smoothstep(0.02, 0.18, d.y));
	}

	float disk = smoothstep(cos(radians(sun_size_degrees)), cos(radians(sun_size_degrees * 0.8)), toward_sun);
	color = mix(color, sun_color * 4.0, disk);
	color = mix(color, below_color, smoothstep(0.0, -0.04, d.y));
	COLOR = color;
}
