// Ocean surface: a few moving sine waves for the normal and a Fresnel sky tint.
// Each wave fades out once it gets too small on screen, to avoid shimmer.
shader_type spatial;

uniform vec3 deep_color : source_color = vec3(0.03, 0.13, 0.20);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.68, 0.82);
// World position of the scene origin (WorldOrigin.offset), so waves don't jump on shifts.
uniform vec2 origin_offset = vec2(0.0);

varying vec2 world_xz;

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
	vec2 slope = wave_slope(world_xz, pixel_size, vec2(1.0, 0.3), 23.0, 0.25, 4.0)
			+ wave_slope(world_xz, pixel_size, vec2(-0.4, 1.0), 11.0, 0.12, 2.8)
			+ wave_slope(world_xz, pixel_size, vec2(0.7, -0.8), 5.3, 0.05, 1.9)
			+ wave_slope(world_xz, pixel_size, vec2(-1.0, -0.2), 2.1, 0.02, 1.2);

	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = deep_color;
	EMISSION = sky_tint * fresnel * 0.5;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
}
