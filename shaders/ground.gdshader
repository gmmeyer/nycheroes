// Ground from tools/citygen/build_tiles.py.
// UV2.x: 0 pavement, 1 road, 2 park, 3 seawall.
// UV: world x/z on flat ground; (meters along, meters up) on seawalls.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 pavement_color : source_color = vec3(0.45, 0.44, 0.42);
uniform vec3 road_color : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 park_color : source_color = vec3(0.23, 0.40, 0.19);
uniform vec3 seawall_color : source_color = vec3(0.38, 0.36, 0.33);

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

void fragment() {
	int kind = int(UV2.x + 0.5);
	if (kind == 3) {
		ALBEDO = seawall_color;
	} else {
		vec3 base = kind == 1 ? road_color : (kind == 2 ? park_color : pavement_color);
		// Broad, soft variation so large areas don't look flat.
		float variation = value_noise(UV * 0.04) * 0.6 + value_noise(UV * 0.31) * 0.4;
		ALBEDO = base * mix(0.86, 1.1, variation);
	}
	ROUGHNESS = 0.95;
	// Matte: keeps the sky from reflecting blue off the pavement at low angles.
	SPECULAR = 0.1;
}
