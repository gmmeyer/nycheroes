// Ground and structures (bridges) from tools/citygen/build_tiles.py, in the
// city's stylized look: clean, slightly saturated colors with a few bold
// details (sidewalk flags, asphalt patches, mottled grass, stone courses)
// that fade to their average color in the distance.
// UV2.x: 0 pavement, 1 road, 2 park, 3 seawall, 4 sand, 5 marsh,
//        6 concrete (curbs, bridge deck sides, columns, steel towers), 7 cable, 8 stone (towers),
//        9 yard (back yards, gardens, lawns around homes).
//        Bridge deck tops are road.
// UV: world x/z on flat ground; (meters along, meters up) on walls.
// Lighting is the shared toon model (toon.gdshaderinc).
// With an aerial photo (?aerial=1), the flat ground kinds (pavement, road,
// park, sand, marsh) show it; built things (seawalls, concrete, cables,
// stone) don't. Close to the camera the ground goes back to its own colors:
// the photo is blurry at eye level and has the morning's shadows baked in.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/aerial.gdshaderinc"

const int PAVEMENT = 0;
const int ROAD = 1;
const int PARK = 2;
const int SEAWALL = 3;
const int SAND = 4;
const int MARSH = 5;
const int CONCRETE = 6;
const int CABLE = 7;
const int STONE = 8;
const int YARD = 9;

// The photo fades out between these distances from the camera (meters).
uniform vec2 aerial_near_fade = vec2(25.0, 110.0);
// The photos were taken in March, with bare trees and brown lawns; this much
// of a park's photo is recolored green (keeping its light and dark detail).
uniform float park_greening = 0.4;

uniform vec3 pavement_color : source_color = vec3(0.53, 0.52, 0.49);
uniform vec3 road_color : source_color = vec3(0.27, 0.28, 0.31);
uniform vec3 park_color : source_color = vec3(0.36, 0.55, 0.26);
uniform vec3 seawall_color : source_color = vec3(0.58, 0.56, 0.51);
uniform vec3 sand_color : source_color = vec3(0.89, 0.80, 0.60);
uniform vec3 marsh_color : source_color = vec3(0.50, 0.55, 0.32);
uniform vec3 concrete_color : source_color = vec3(0.77, 0.75, 0.70);
uniform vec3 cable_color : source_color = vec3(0.80, 0.82, 0.85);
uniform vec3 stone_color : source_color = vec3(0.76, 0.68, 0.53);
uniform vec3 yard_color : source_color = vec3(0.42, 0.56, 0.30);
// Sidewalk flags: size (m) and the street grid's angle (Manhattan's grid
// runs 29 degrees east of true north), so the joints line up with the curbs.
uniform float paving_size = 1.5;
uniform float paving_angle_degrees = 29.0;

vec3 base_color(int kind) {
	if (kind == ROAD) {
		return road_color;
	}
	if (kind == PARK) {
		return park_color;
	}
	if (kind == SEAWALL) {
		return seawall_color;
	}
	if (kind == SAND) {
		return sand_color;
	}
	if (kind == MARSH) {
		return marsh_color;
	}
	if (kind == CONCRETE) {
		return concrete_color;
	}
	if (kind == CABLE) {
		return cable_color;
	}
	if (kind == STONE) {
		return stone_color;
	}
	if (kind == YARD) {
		return yard_color;
	}
	return pavement_color;
}

// Stone or concrete blocks in courses (seawalls, bridge towers), on walls.
float block_joints(vec2 p, vec2 footprint, vec2 block, float joint) {
	float detail = visible(block.y, max(footprint.x, footprint.y));
	float row = p.y / block.y;
	float shift = mod(floor(row), 2.0) * 0.5 * detail;
	return max(stripes(row, joint / block.y, footprint.y / block.y),
			stripes(p.x / block.x + shift, joint / block.x, footprint.x / block.x) * detail);
}

vec3 flat_ground(int kind, vec2 p, vec2 footprint, vec3 color) {
	float pixel = max(footprint.x, footprint.y);
	if (kind == PAVEMENT) {
		// Square concrete flags along the street grid, each a little different.
		float angle = radians(paving_angle_degrees);
		vec2 g = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle))) * p / paving_size;
		float gf = pixel / paving_size;
		float joints = max(centered_stripes(g.x, 0.02, gf), centered_stripes(g.y, 0.02, gf));
		float tint = (hash(floor(g + 0.5)) - 0.5) * 0.08 * visible(paving_size, pixel);
		return color * (1.0 + tint) * (1.0 - 0.3 * joints);
	}
	if (kind == ROAD) {
		// Asphalt with patched areas and a fine grain up close.
		float patches = smoothstep(0.55, 0.6, value_noise(p * 0.07 + 13.0));
		float grain = (value_noise(p * 4.0) - 0.5) * 0.1 * visible(0.25, pixel);
		return color * (1.0 + 0.1 * patches + grain);
	}
	if (kind == PARK) {
		// Mottled grass: soft-edged light and dark patches.
		float n = value_noise(p * 0.05) * 0.65 + value_noise(p * 0.21) * 0.35;
		float light = smoothstep(0.58, 0.64, n);
		float dark = 1.0 - smoothstep(0.34, 0.4, n);
		vec3 grass = color * (1.0 + 0.16 * light - 0.18 * dark);
		grass *= 1.0 + (value_noise(p * 2.3) - 0.5) * 0.12 * visible(0.4, pixel);
		return grass;
	}
	if (kind == SAND) {
		float ripples = sin(p.x * 1.3 + value_noise(p * 0.3) * 6.0) * 0.5 + 0.5;
		return color * (1.0 - 0.06 * ripples * visible(0.6, pixel)) * (0.95 + 0.1 * value_noise(p * 0.05));
	}
	if (kind == MARSH) {
		float wet = smoothstep(0.55, 0.62, value_noise(p * 0.08 + 5.0));
		return mix(color, color * vec3(0.7, 0.8, 0.85), wet);
	}
	if (kind == YARD) {
		// Lawns, with patios and paths in places and darker shrubs.
		float n = value_noise(p * 0.11 + 31.0);
		float paved = smoothstep(0.66, 0.7, n);
		float shrubs = 1.0 - smoothstep(0.26, 0.3, value_noise(p * 0.35 + 7.0));
		vec3 lawn = color * (1.0 - 0.22 * shrubs) * (1.0 + (value_noise(p * 2.0) - 0.5) * 0.1 * visible(0.4, pixel));
		return mix(lawn, pavement_color * 0.95, paved);
	}
	return color;
}

vec3 wall_surface(int kind, vec2 p, vec2 footprint, vec3 color) {
	if (kind == SEAWALL) {
		return color * (1.0 - 0.3 * block_joints(p, footprint, vec2(1.4, 0.7), 0.03));
	}
	if (kind == STONE) {
		return color * (1.0 - 0.28 * block_joints(p, footprint, vec2(1.8, 0.9), 0.03));
	}
	if (kind == CONCRETE) {
		// Formwork panels, faintly.
		float panels = max(centered_stripes(p.x / 2.4, 0.01, footprint.x / 2.4), centered_stripes(p.y / 1.2, 0.02, footprint.y / 1.2));
		return color * (1.0 - 0.12 * panels);
	}
	return color;
}

void vertex() {
	aerial_uv = aerial_uv_of(VERTEX);
}

void fragment() {
	int kind = int(UV2.x + 0.5);
	vec2 footprint = max(fwidth(UV), vec2(1e-4));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 photo = aerial_albedo(aerial_uv);

	// Broad, soft variation so large areas don't look flat.
	float variation = value_noise(UV * 0.04) * 0.6 + value_noise(UV * 0.31) * 0.4;
	vec3 color = base_color(kind) * mix(0.92, 1.06, variation);
	if (world_normal.y > 0.7) {
		color = flat_ground(kind, UV, footprint, color);
	} else {
		color = wall_surface(kind, UV, footprint, color);
	}

	if (kind == PARK) {
		float detail = clamp(dot(photo, vec3(0.2126, 0.7152, 0.0722)) / 0.08, 0.25, 1.2);
		photo = mix(photo, park_color * detail, park_greening);
	}
	bool photographed = (kind <= MARSH && kind != SEAWALL) || kind == YARD;
	float far_enough = smoothstep(aerial_near_fade.x, aerial_near_fade.y, length(VERTEX));
	ALBEDO = mix(color, photo, photographed ? aerial_amount(aerial_uv) * far_enough : 0.0);
	EMISSION = ALBEDO * toon_ambient(world_normal, 1.0);
	toon_glint = kind == CABLE ? 0.3 : 0.0;
}
