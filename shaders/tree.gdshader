// Trees from near city tiles' props (scripts/world/city_props.gd), on the
// unit mesh from PropMeshes.tree() (or its shadow stand-in), whose three
// shapes are a round broadleaf, a narrow one and a conifer. Per instance:
//   transform        scales the mesh to the tree's height (y) and crown width
//                    (x, z) and moves it to the foot of its trunk
//   COLOR            (trunk diameter m, 0, 0, 0)
//   INSTANCE_CUSTOM  (yaw radians, foliage tone 0..3, seed 0..1, prop type:
//                    0 round, 1 narrow, 2 conifer)
// Per vertex: UV = (0 trunk or 1 crown, 0..1 up the crown), UV2 = (a shade
// offset per crown blob, the blob's number: 1..4, 0 on trunks and the shadow
// stand-ins); CUSTOM0 = (position, UV.y) and CUSTOM1 = (normal, UV2.x) of the
// narrow shape, CUSTOM2 and CUSTOM3 the same of the conifer.
// Each tree turns to its yaw, gets its real trunk's thickness, leans and
// squashes its crown a little by its seed, and sways in the wind. Its crown
// starts where a New York street tree's does: pruned clear of the sidewalk
// and of trucks in the street, higher up on big trees (the whole mesh is
// stretched up its trunk); each blob moves a little per tree, so no two
// crowns are alike. Up close a crown thins out into leaf clumps with sky
// between them, most at its outline and underside, solid again once the
// clumps are a few pixels. Crowns get their tone's color with a little
// per-tree variety, a soft gradient (only a little darker underneath, where
// light comes through the leaves), and leaf clumps up close. Trees shrink
// away one by one between fade_distance from the camera, before their tile's
// trees stop drawing; their shadows sooner. Beyond that the ground shader's
// woods carry on in the same greens.
// Lighting is the shared toon model (toon.gdshaderinc); at night crowns near
// a street light catch its warm light underneath.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Foliage tones (tools/citygen PROP_TONE_*), in sRGB: mid green (London
// plane, maples), light yellow-green (honeylocust, ginkgo), dark green (oaks,
// lindens), red-purple (purple-leaf plum, 'Crimson King' maple). Conifers
// (always the dark tone in the data) are a cooler blue-green. Keep the
// ground shader's woods colors in step.
const vec3 FOLIAGE[4] = vec3[](vec3(0.43, 0.60, 0.25), vec3(0.62, 0.72, 0.31), vec3(0.31, 0.50, 0.22),
		vec3(0.45, 0.25, 0.29));
const vec3 CONIFER = vec3(0.24, 0.42, 0.30);
const vec3 BARK = vec3(0.47, 0.42, 0.36);
// Where each shape's crown starts in the mesh (PropMeshes ROUND_BOTTOM,
// NARROW_BOTTOM, CONIFER_BOTTOM).
const float CROWN_BOTTOM[3] = float[](0.38, 0.22, 0.12);

// Trees shrink away between these distances from the camera (m), and their
// shadows (cast by plain stand-ins, see CityProps) between these.
uniform vec2 fade_distance = vec2(650.0, 850.0);
uniform vec2 shadow_distance = vec2(450.0, 600.0);
// Crowns start this share of a tree's height up (y; narrow trees three
// quarters of it), at least x meters (clear of a box truck in the street),
// at most z of the height (so young trees keep a crown). Conifers keep their
// low branches.
uniform vec3 crown_base = vec3(3.4, 0.4, 0.55);
// How far each blob moves about per tree, as a share of the crown's width
// (up and down half that; narrow trees and conifers less).
uniform float blob_jitter = 0.06;
// Gaps up close: how much of the crown is open where its surface is seen
// edge-on (its outline), and where it faces the camera, plus a little more
// underneath; and the size of the leaf clumps between the gaps (m).
uniform float crown_gaps_edge = 0.55;
uniform float crown_gaps_face = 0.12;
uniform float crown_gaps_under = 0.15;
uniform float leaf_clump_size = 0.75;
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
// How much darker a crown's underside is than its top, and how much daylight
// comes through its leaves there (a share of its color, glowing).
uniform float crown_shading : hint_range(0.0, 1.0) = 0.14;
uniform float leaf_glow : hint_range(0.0, 1.0) = 0.08;
// Night: how much street light the undersides of crowns (and trunks) catch.
uniform float street_light_catch = 1.0;

// (tone, seed in 1024ths, shape): the same for the whole tree.
varying flat vec3 tree_data;
// Unit-mesh position (for leaf clumps and gaps), the tree's size in meters,
// and the shape's UV.y and UV2.x.
varying vec3 mesh_position;
varying flat vec2 tree_size;
varying vec2 crown_shading_data;
// 1 on a crown's blobs (which thin out up close), 0 on trunks and stand-ins.
varying flat float crown_blob;
// Night: the street lights' light where the tree stands.
varying flat vec3 tree_street_light;

// A random number per tree (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

// Value noise in 3-D, 0..1.
float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	vec2 k = vec2(57.0, 113.0);
	vec2 c0 = i.xy + i.z * k;
	vec2 c1 = c0 + k;
	float lower = mix(mix(hash(c0), hash(c0 + vec2(1.0, 0.0)), u.x),
			mix(hash(c0 + vec2(0.0, 1.0)), hash(c0 + vec2(1.0, 1.0)), u.x), u.y);
	float upper = mix(mix(hash(c1), hash(c1 + vec2(1.0, 0.0)), u.x),
			mix(hash(c1 + vec2(0.0, 1.0)), hash(c1 + vec2(1.0, 1.0)), u.x), u.y);
	return mix(lower, upper, u.z);
}

void vertex() {
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	int shape = clamp(int(INSTANCE_CUSTOM.w + 0.5), 0, 2);
	// Custom data arrives as half floats; whole 1024ths survive that exactly.
	float seed = floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5);
	tree_data = vec3(floor(INSTANCE_CUSTOM.y + 0.5), seed, float(shape));
	tree_size = vec2(width, height);
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	crown_shading_data = vec2(UV.y, UV2.x);
	if (shape == 2) {
		v = CUSTOM2.xyz;
		n = CUSTOM3.xyz;
		crown_shading_data = vec2(CUSTOM2.w, CUSTOM3.w);
	} else if (shape == 1) {
		v = CUSTOM0.xyz;
		n = CUSTOM1.xyz;
		crown_shading_data = vec2(CUSTOM0.w, CUSTOM1.w);
	}
	bool crown = UV.x > 0.5;
	float blob = crown ? UV2.y : 0.0;
	crown_blob = step(0.5, blob);
	if (blob > 0.5) {
		// Each blob a little off its place, and further out or in from the
		// trunk (which widens or narrows it too), differently in every tree.
		float amount = blob_jitter * (shape == 0 ? 1.0 : (shape == 1 ? 0.6 : 0.25));
		vec3 nudge = vec3(rnd(seed, 10.0 + blob), rnd(seed, 20.0 + blob), rnd(seed, 30.0 + blob)) - 0.5;
		v.xz *= 1.0 + (rnd(seed, 40.0 + blob) - 0.5) * 3.0 * amount;
		v += nudge * vec3(2.0, 1.0, 2.0) * amount;
	}
	mesh_position = v;
	float up = crown_shading_data.x;
	float distance_to_camera = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, MODEL_MATRIX[3].xyz);
	tree_street_light = vec3(0.0);
	if (city_lights > 0.0 && !IN_SHADOW_PASS) {
		tree_street_light = street_light_at(MODEL_MATRIX[3].xz, distance_to_camera) * city_lights;
	}

	// The crown moves up (or down) to start at its base: below the mesh's
	// crown bottom the trunk stretches, above it the crown squashes.
	float bottom = CROWN_BOTTOM[shape];
	float base = bottom;
	if (shape < 2) {
		float share = crown_base.y * (shape == 1 ? 0.75 : 1.0);
		base = clamp(max(crown_base.x / height, share), bottom, max(crown_base.z, bottom));
	}
	float stretch = v.y < bottom ? base / bottom : (1.0 - base) / (1.0 - bottom);
	v.y = v.y < bottom ? v.y * stretch : base + (v.y - bottom) * stretch;
	n.y /= stretch;

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
		// Meters in the tree, for the leaf clumps and the gaps between them.
		vec3 p = mesh_position * vec3(tree_size.x, tree_size.y, tree_size.x);
		if (crown_blob > 0.5) {
			// Gaps, where the clumps are big enough on screen not to flicker:
			// most where the surface turns away (the outline) and underneath.
			float detail = visible(leaf_clump_size, length(fwidth(p)));
			if (detail > 0.0) {
				float edge = 1.0 - abs(dot(normalize(NORMAL), VIEW));
				float under = 1.0 - smoothstep(0.0, 0.5, crown_shading_data.x);
				float open = mix(crown_gaps_face, crown_gaps_edge, edge * edge) + crown_gaps_under * under;
				float leaves = value_noise3(p / leaf_clump_size + seed * 0.37);
				if (leaves < open * detail) {
					discard;
				}
			}
		}
		int tone = clamp(int(tree_data.x), 0, 3);
		color = srgb(tree_data.z > 1.5 && tone != 3 ? CONIFER : FOLIAGE[tone]);
		// Each tree a little lighter or darker, warmer or cooler.
		color *= mix(0.88, 1.12, rnd(seed, 6.0));
		color *= mix(vec3(1.06, 1.0, 0.84), vec3(0.94, 1.0, 1.1), rnd(seed, 7.0));
		// Each blob a touch different, so the lumps read.
		color *= 1.0 + 0.07 * crown_shading_data.y;
		// Soft gradient: the underside a little darker, the top catching more sky.
		float up = smoothstep(0.0, 0.95, crown_shading_data.x);
		color *= mix(1.0 - crown_shading, 1.05, up);
		occlusion = mix(0.9, 1.05, up);
		// Leaf clumps up close, gone once they're a few pixels.
		vec2 q = vec2(p.x + 0.6 * p.y, p.z - 0.8 * p.y) / 1.1;
		float clumps = value_noise(q + seed);
		color *= 1.0 + (clumps - 0.5) * 0.24 * visible(1.1, length(fwidth(q)) * 1.1);
	}
	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion);
	if (UV.x > 0.5) {
		// Daylight through the leaves, most underneath.
		EMISSION += ALBEDO * (leaf_glow * (1.0 - night) * (1.0 - 0.6 * crown_shading_data.x));
	}
	toon_glint = 0.0;
	if (city_lights > 0.0) {
		float under = UV.x < 0.5 ? 1.0 : 1.0 - smoothstep(0.0, 0.8, crown_shading_data.x);
		EMISSION += ALBEDO * tree_street_light * (street_light_catch * under);
	}
}
