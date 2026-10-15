// Trees from near city tiles' props (scripts/world/city_props.gd), on the
// unit mesh from PropMeshes.tree() (or its shadow stand-in), whose three
// shapes are a round broadleaf, a narrow one and a conifer. Per instance:
//   transform        scales the mesh to the tree's height (y) and crown width
//                    (x, z) and moves it to the foot of its trunk
//   COLOR            (trunk diameter m, 0, 0, 0)
//   INSTANCE_CUSTOM  (yaw radians, foliage tone 0..3, seed 0..1, prop type:
//                    0 round, 1 narrow, 2 conifer)
// Per vertex: UV = (0 trunk or 1 crown, 0..1 up the crown), UV2.x = a shade
// offset per crown blob; CUSTOM0 = (position, UV.y) and CUSTOM1 = (normal,
// UV2.x) of the narrow shape, CUSTOM2 and CUSTOM3 the same of the conifer.
// Each tree turns to its yaw, gets its real trunk's thickness, leans and
// squashes its crown a little by its seed, and sways in the wind. Crowns get their tone's color with a little
// per-tree variety, a soft gradient (darker underneath), and leaf clumps up
// close. Trees shrink away one by one between fade_distance from the camera,
// before their tile's trees stop drawing; their shadows sooner.
// Lighting is the shared toon model (toon.gdshaderinc); at night crowns near
// a street light catch its warm light underneath.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Foliage tones (tools/citygen PROP_TONE_*), in sRGB: mid green, light
// yellow-green (honeylocust, ginkgo), dark green (oaks, lindens, conifers),
// red-purple (purple-leaf plum, copper beech).
const vec3 FOLIAGE[4] = vec3[](vec3(0.38, 0.58, 0.22), vec3(0.60, 0.69, 0.28), vec3(0.26, 0.46, 0.22),
		vec3(0.41, 0.22, 0.27));
const vec3 BARK = vec3(0.50, 0.42, 0.34);

// Trees shrink away between these distances from the camera (m), and their
// shadows (cast by plain stand-ins, see CityProps) between these.
uniform vec2 fade_distance = vec2(650.0, 850.0);
uniform vec2 shadow_distance = vec2(450.0, 600.0);
// Sway at the top of the crown, as a share of the tree's height, and how fast.
uniform float wind_strength = 0.008;
uniform float wind_speed = 1.2;
uniform vec2 wind_direction = vec2(0.8, 0.6);
// Trunks are at least this thick (m), and at least about a pixel and a half
// (this share of their distance), so thin ones don't vanish.
uniform float trunk_min_width = 0.1;
uniform float trunk_min_pixels = 0.0025;
// ...and at most this share of the crown's width (the odd giant in the data).
uniform float trunk_max_share = 0.15;
// How much darker a crown's underside is than its top.
uniform float crown_shading : hint_range(0.0, 1.0) = 0.25;
// Night: how much street light the undersides of crowns (and trunks) catch.
uniform float street_light_catch = 1.0;

// (tone, seed in 1024ths): the same for the whole tree.
varying flat vec2 tree_data;
// Unit-mesh position (for leaf clumps), the tree's size in meters, and the
// shape's UV.y and UV2.x.
varying vec3 mesh_position;
varying flat vec2 tree_size;
varying vec2 crown_shading_data;
// Night: the street lights' light where the tree stands.
varying flat vec3 tree_street_light;

// A random number per tree (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

void vertex() {
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	// Custom data arrives as half floats; whole 1024ths survive that exactly.
	float seed = floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5);
	tree_data = vec2(floor(INSTANCE_CUSTOM.y + 0.5), seed);
	tree_size = vec2(width, height);
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	crown_shading_data = vec2(UV.y, UV2.x);
	if (INSTANCE_CUSTOM.w > 1.5) {
		v = CUSTOM2.xyz;
		n = CUSTOM3.xyz;
		crown_shading_data = vec2(CUSTOM2.w, CUSTOM3.w);
	} else if (INSTANCE_CUSTOM.w > 0.5) {
		v = CUSTOM0.xyz;
		n = CUSTOM1.xyz;
		crown_shading_data = vec2(CUSTOM0.w, CUSTOM1.w);
	}
	mesh_position = v;
	float up = crown_shading_data.x;
	float distance_to_camera = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, MODEL_MATRIX[3].xyz);
	tree_street_light = vec3(0.0);
	if (city_lights > 0.0 && !IN_SHADOW_PASS) {
		tree_street_light = street_light_at(MODEL_MATRIX[3].xz, distance_to_camera) * city_lights;
	}

	bool crown = UV.x > 0.5;
	if (crown) {
		// Crowns a little oval, some wider one way than the other.
		float squash = (rnd(seed, 1.0) - 0.5) * 0.24;
		v.xz *= vec2(1.0 + squash, 1.0 - squash);
	} else {
		// The real trunk's diameter (no more than a share of the crown's
		// width), over the mesh's (PropMeshes.TRUNK_RADIUS of the crown's width).
		float trunk = min(COLOR.r, trunk_max_share * width);
		trunk = max(trunk, max(trunk_min_width, trunk_min_pixels * distance_to_camera));
		v.xz *= trunk / (0.08 * width);
	}
	// A slight lean, more toward the top.
	vec2 lean = (vec2(rnd(seed, 2.0), rnd(seed, 3.0)) - 0.5) * 0.08;
	v.xz += lean * v.y * height / width;

	// Turn to the tree's yaw (about +Y, as Godot's Basis turns).
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	v.xz = vec2(c * v.x + s * v.z, c * v.z - s * v.x);
	n.xz = vec2(c * n.x + s * n.z, c * n.z - s * n.x);

	if (crown) {
		// Wind: the whole crown sways, its top most, with a quicker flutter.
		float phase = TIME * wind_speed + rnd(seed, 4.0) * 6.2832;
		float gust = sin(phase) * 0.7 + sin(phase * 2.3 + mesh_position.y * 5.0) * 0.3;
		v.xz += wind_direction * (gust * wind_strength * up * up * height / width);
	}

	// Far trees, and sooner their shadows, shrink to their base, measured from
	// the main camera (in the shadow pass too).
	v *= 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	if (IN_SHADOW_PASS) {
		v *= 1.0 - smoothstep(shadow_distance.x, shadow_distance.y, distance_to_camera);
	}

	VERTEX = v;
	// Godot turns normals by the instance's scale; dividing by its square
	// first leaves them turned by its inverse, as a stretched surface needs.
	NORMAL = n / vec3(width * width, height * height, width * width);
}

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float seed = tree_data.y;
	vec3 color;
	float occlusion;
	if (UV.x < 0.5) {
		// Bark, with faint ridges up close.
		float around = atan(mesh_position.z, mesh_position.x) * tree_size.x * 0.12;
		float ridges = centered_stripes(around / 0.08, 0.3, fwidth(around) / 0.08);
		color = srgb(BARK) * mix(0.8, 1.15, rnd(seed, 5.0)) * (1.0 - 0.15 * ridges);
		occlusion = 0.9;
	} else {
		int tone = clamp(int(tree_data.x), 0, 3);
		color = srgb(FOLIAGE[tone]);
		// Each tree a little lighter or darker, warmer or cooler.
		color *= mix(0.86, 1.12, rnd(seed, 6.0));
		color *= mix(vec3(1.06, 1.0, 0.84), vec3(0.94, 1.0, 1.1), rnd(seed, 7.0));
		// Each blob a touch different, so the lumps read.
		color *= 1.0 + 0.06 * crown_shading_data.y;
		// Soft gradient: the underside darker, the top catching more sky.
		float up = smoothstep(0.0, 0.95, crown_shading_data.x);
		color *= mix(1.0 - crown_shading, 1.05, up);
		occlusion = mix(0.8, 1.05, up);
		// Leaf clumps up close, gone once they're a few pixels.
		vec3 p = mesh_position * vec3(tree_size.x, tree_size.y, tree_size.x);
		vec2 q = vec2(p.x + 0.6 * p.y, p.z - 0.8 * p.y) / 1.1;
		float clumps = value_noise(q + seed);
		color *= 1.0 + (clumps - 0.5) * 0.24 * visible(1.1, length(fwidth(q)) * 1.1);
	}
	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion);
	toon_glint = 0.0;
	if (city_lights > 0.0) {
		float under = UV.x < 0.5 ? 1.0 : 1.0 - smoothstep(0.0, 0.8, crown_shading_data.x);
		EMISSION += ALBEDO * tree_street_light * (street_light_catch * under);
	}
}
