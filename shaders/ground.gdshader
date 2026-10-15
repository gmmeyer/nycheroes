// Ground and structures (bridges) from tools/citygen/build_tiles.py.
// UV2.x: 0 pavement, 1 road, 2 park, 3 seawall, 4 sand, 5 marsh,
//        6 concrete (curbs, bridge deck sides, columns, steel towers), 7 cable, 8 stone (towers).
//        Bridge deck tops are road.
// UV: world x/z on flat ground; (meters along, meters up) on walls.
// With an aerial photo, the flat ground kinds (pavement, road, park, sand,
// marsh) show it; built things (seawalls, concrete, cables, stone) don't.
// Close to the camera the ground goes back to its plain colors: the photo
// is blurry at eye level and has the morning's shadows baked in.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/aerial.gdshaderinc"

// The photo fades out between these distances from the camera (meters).
uniform vec2 aerial_near_fade = vec2(25.0, 110.0);
// The photos were taken in March, with bare trees and brown lawns; this much
// of a park's photo is recolored green (keeping its light and dark detail).
uniform float park_greening = 0.4;

uniform vec3 pavement_color : source_color = vec3(0.45, 0.44, 0.42);
uniform vec3 road_color : source_color = vec3(0.24, 0.24, 0.25);
uniform vec3 park_color : source_color = vec3(0.23, 0.40, 0.19);
uniform vec3 seawall_color : source_color = vec3(0.38, 0.36, 0.33);
uniform vec3 sand_color : source_color = vec3(0.80, 0.73, 0.57);
uniform vec3 marsh_color : source_color = vec3(0.36, 0.40, 0.26);
uniform vec3 concrete_color : source_color = vec3(0.52, 0.53, 0.55);
uniform vec3 cable_color : source_color = vec3(0.72, 0.74, 0.78);
uniform vec3 stone_color : source_color = vec3(0.66, 0.58, 0.47);

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

vec3 base_color(int kind) {
	if (kind == 1) {
		return road_color;
	}
	if (kind == 2) {
		return park_color;
	}
	if (kind == 3) {
		return seawall_color;
	}
	if (kind == 4) {
		return sand_color;
	}
	if (kind == 5) {
		return marsh_color;
	}
	if (kind == 6) {
		return concrete_color;
	}
	if (kind == 7) {
		return cable_color;
	}
	if (kind == 8) {
		return stone_color;
	}
	return pavement_color;
}

void vertex() {
	aerial_uv = aerial_uv_of(VERTEX);
}

void fragment() {
	int kind = int(UV2.x + 0.5);
	// Broad, soft variation so large areas don't look flat.
	float variation = value_noise(UV * 0.04) * 0.6 + value_noise(UV * 0.31) * 0.4;
	vec3 photo = aerial_albedo(aerial_uv);
	if (kind == 2) {
		float detail = clamp(dot(photo, vec3(0.2126, 0.7152, 0.0722)) / 0.08, 0.25, 1.2);
		photo = mix(photo, park_color * detail, park_greening);
	}
	bool photographed = kind <= 5 && kind != 3;
	float far_enough = smoothstep(aerial_near_fade.x, aerial_near_fade.y, length(VERTEX));
	ALBEDO = mix(base_color(kind) * mix(0.86, 1.1, variation), photo,
			photographed ? aerial_amount(aerial_uv) * far_enough : 0.0);
	ROUGHNESS = kind == 7 ? 0.45 : 0.95;
	// Matte: keeps the sky from reflecting blue off the pavement at low angles.
	SPECULAR = kind == 7 ? 0.5 : 0.1;
}
