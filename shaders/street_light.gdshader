// Street lights from near city tiles' props (scripts/world/city_props.gd), on
// the mesh from PropMeshes.street_light(), which holds both styles. Per
// instance (the props' common layout):
//   transform        scales by the arm's length (x, z) and the pole's height
//                    (y), and moves to the pole's foot on the sidewalk
//   INSTANCE_CUSTOM  (yaw radians: the arm reaches along (sin, 0, cos) of it,
//                    style: 0 cobra-head or 1 post-top, seed 0..1, prop type)
//   COLOR.r          1 for a cobra-head on a wooden utility pole: no pole of
//                    its own, its height where its arm meets the wooden one
// Wooden utility poles (PropMeshes.utility_pole(), a MultiMesh of their own)
// come here too: their height is the pole's, the style their bits
// (CityTileDecoder.POLE_*: a transformer can, a pin on the top for a third
// wire), and the crossarm runs along the yaw, toward the street.
// A post-top's arm length is 0, which would fold the mesh flat, so this
// shader builds each vertex's position itself (skip_vertex_transform): it
// stretches the pole to its height and the arm to its length, folds away the
// other style's parts, turns the lamp to its yaw and moves it into place.
// Cobra-heads are DOT gray with a pale lens; post-tops dark green cast iron
// with a lantern of frosted glass; utility poles creosoted wood, gray-brown
// crossarms, pale gray insulators and a gray transformer can. At night (shaders/night.gdshaderinc) the
// lens and lantern glow, and the pole stands in its own pool of light. Far
// lamps' poles stay at least about a pixel wide, then shrink away (their
// glows, street_light_glow.gdshader, carry on further).
// Lighting is the shared toon model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes numbers them.
const int POLE = 0;
const int ARM = 1;
const int HOUSING = 2;
const int LENS = 3;
const int POST = 4;
const int LANTERN = 5;
const int CAP = 6;
const int WOOD = 7;
const int CROSSARM = 8;
const int INSULATOR = 9;
const int TOP_PIN = 10;
const int TRANSFORMER = 11;
const int HARDWARE = 12;

// Paint and glass, in sRGB.
const vec3 DOT_GRAY = vec3(0.56, 0.58, 0.58);
const vec3 HOUSING_GRAY = vec3(0.70, 0.71, 0.70);
const vec3 LENS_GLASS = vec3(0.82, 0.83, 0.80);
const vec3 CAST_IRON = vec3(0.13, 0.20, 0.16);
const vec3 FROSTED_GLASS = vec3(0.86, 0.86, 0.82);
const vec3 POLE_WOOD = vec3(0.35, 0.28, 0.22);
const vec3 CROSSARM_WOOD = vec3(0.47, 0.42, 0.35);
const vec3 INSULATOR_GRAY = vec3(0.74, 0.75, 0.73);
const vec3 TRANSFORMER_GRAY = vec3(0.56, 0.58, 0.58);
const vec3 GALVANIZED = vec3(0.50, 0.51, 0.50);

// The lamps' light, in sRGB: a cobra-head's warm white LED, a post-top's warmer glow.
uniform vec3 cobra_head_light : source_color = vec3(1.0, 0.84, 0.62);
uniform vec3 post_top_light : source_color = vec3(1.0, 0.76, 0.48);
uniform float lamp_glow = 2.5;
// Lamps shrink away between these distances from the camera (m).
uniform vec2 fade_distance = vec2(450.0, 650.0);
// Poles are at least this share of their distance wide (about a pixel).
uniform float pole_min_pixels = 0.0016;

varying flat float post_top;
// Street light where the lamp stands (night), and how far up the part this is.
varying flat vec3 pole_street_light;
varying float part_up;

void vertex() {
	float height = length(MODEL_MATRIX[1].xyz);
	float arm = length(MODEL_MATRIX[0].xyz);
	float yaw = INSTANCE_CUSTOM.x;
	int style = int(INSTANCE_CUSTOM.y + 0.5);
	post_top = style == 1 ? 1.0 : 0.0;
	int part = int(UV.x + 0.5);
	part_up = UV.y;
	vec3 base = MODEL_MATRIX[3].xyz;
	float distance_to_camera = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, base);

	vec3 v = VERTEX;
	if (part == POLE || part == POST || part == WOOD) {
		// Widened far away so it doesn't flicker, about the foot.
		v.xz *= max(1.0, pole_min_pixels * distance_to_camera / 0.1);
	}
	if (part > WOOD) {
		// A utility pole's fittings, in meters from its top.
		v.y += height;
	} else if (part == POLE || part >= POST) {
		v.y *= height;
	} else if (part == ARM) {
		v.z *= arm;
		v.y += height;
	} else {
		v.z += arm;
		v.y += height;
	}
	// The other style's parts fold away, a lamp's pole on a wooden one, and a
	// utility pole's pin and transformer where it has none.
	bool folded = part >= WOOD ? (part == TOP_PIN && (style & 2) == 0) || (part == TRANSFORMER && (style & 1) == 0)
			: (part >= POST) != (post_top > 0.5) || (part == POLE && COLOR.r > 0.5);
	if (folded) {
		v = vec3(0.0);
	}
	v *= 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);

	// Turn to the yaw (about +Y, as Godot's Basis turns: +z goes to (sin, cos)).
	float c = cos(yaw);
	float s = sin(yaw);
	v.xz = vec2(c * v.x + s * v.z, c * v.z - s * v.x);
	vec3 n = NORMAL;
	n.xz = vec2(c * n.x + s * n.z, c * n.z - s * n.x);
	VERTEX = (VIEW_MATRIX * vec4(base + v, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	pole_street_light = vec3(0.0);
	if (city_lights > 0.0) {
		pole_street_light = street_light_at(base.xz, distance_to_camera) * city_lights;
	}
}

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	int part = int(UV.x + 0.5);
	vec3 color;
	float occlusion = 1.0;
	float glass = 0.0;
	if (part == LENS) {
		color = srgb(LENS_GLASS);
		glass = 1.0;
	} else if (part == LANTERN) {
		color = srgb(FROSTED_GLASS);
		glass = 1.0;
	} else if (part == HOUSING) {
		color = srgb(HOUSING_GRAY);
	} else if (part == POST || part == CAP) {
		color = srgb(CAST_IRON);
		// The base a little darker.
		occlusion = mix(0.8, 1.0, smoothstep(0.0, 0.2, part_up));
	} else if (part == WOOD) {
		color = srgb(POLE_WOOD);
		occlusion = mix(0.8, 1.0, smoothstep(0.0, 0.15, part_up));
	} else if (part == CROSSARM) {
		color = srgb(CROSSARM_WOOD);
	} else if (part == INSULATOR || part == TOP_PIN) {
		color = srgb(INSULATOR_GRAY);
	} else if (part == TRANSFORMER) {
		color = srgb(TRANSFORMER_GRAY);
	} else if (part == HARDWARE) {
		color = srgb(GALVANIZED);
	} else {
		color = srgb(DOT_GRAY);
		occlusion = mix(0.85, 1.0, smoothstep(0.0, 0.1, part_up));
	}
	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion);
	toon_glint = glass * 0.5;
	if (city_lights > 0.0) {
		vec3 light = srgb(post_top > 0.5 ? post_top_light : cobra_head_light);
		EMISSION += light * (glass * lamp_glow * city_lights);
		// Lit by its own pool, and the head's underside by the lamp beside it.
		EMISSION += ALBEDO * pole_street_light * (1.0 - glass) * (1.0 - 0.6 * part_up);
	}
}
