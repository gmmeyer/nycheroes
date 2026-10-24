// Street name signs from near city tiles' props (scripts/world/city_props.gd,
// tools/citygen/street_signs.py): the green blades on posts at the corners,
// two to a post, and the bigger signs on traffic signals' mast arms, all
// with the real street's name, on the mesh from PropMeshes.street_sign().
// Per instance (the props' common layout):
//   transform        scales x and z by the sign's length and y by the height
//                    of its top, and moves it to its post's foot (or the
//                    spot under it on the arm)
//   INSTANCE_CUSTOM  (yaw radians: the blade runs along its +x; variant + 4 x
//                    (name >> 10); seed; prop type 26)
//   COLOR.r          name & 1023
// (The name is split so both parts survive half floats.) This shader folds
// away the parts of other variants, sizes the rest (the blade to its length
// and the variant's height, the post up to the blade, the hangers to the
// blade's ends), turns it to its yaw and moves it into place itself
// (skip_vertex_transform, like the furniture), and shrinks it away between
// fade distances from the camera.
//
// The name: white letters on the green, read left to right from either
// side, centered and squeezed to fit inside the margins, in a white border.
// The letters are drawn from two textures (street_signs.py): a signed
// distance field of the typeface's characters (street_glyphs), and a table
// of every name's characters and their pen positions (street_names); the
// character under a point is found by bisection over its name's positions,
// and it and its neighbors (whose letters may reach over) are sampled.
// Far away the letters blur to the average of the sign. At night the signs
// catch the street lights (night.gdshaderinc), and their reflective sheeting
// shines a little.
// Lighting is the shared toon model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, cull_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes.SignPart numbers them.
const int FACE = 0;
const int BACK = 1;
const int EDGE = 2;
const int POST = 3;
const int BRACKET = 4;
const int HANGER = 5;
// Variants (CityTileDecoder.STREET_SIGN_*).
const int OVERHEAD = 2;

// Sizes (m), as street_signs.py has them: a blade's height, its letters' em
// and the margin either side of the name; the same for mast arm signs; the
// gap between a post's two blades; and here, the signs' thickness, the
// hangers' height up to the arm and how far in from the sign's ends they are.
const float BLADE_HEIGHT = 0.36;
const float BLADE_EM = 0.25;
const float BLADE_MARGIN = 0.12;
const float OVERHEAD_HEIGHT = 0.5;
const float OVERHEAD_EM = 0.36;
const float OVERHEAD_MARGIN = 0.15;
const float BLADE_GAP = 0.04;
const float THICKNESS = 0.02;
const float HANGER_HEIGHT = 0.14;
const float HANGER_INSET = 0.2;
// The border: inset from the edge, its corners' radius and its width (m).
const float BORDER_INSET = 0.022;
const float BORDER_RADIUS = 0.03;
const float BORDER_WIDTH = 0.012;

// The glyph atlas and the names table, as street_signs.py builds them
// (pixels; slots): cells, a character's pen origin in its cell, pixels to the
// em, cells to a row, the distance field's spread either side of an edge;
// texels to a name, names to a row of the table, the pen's x in 1/256 em.
const vec2 GLYPH_CELL = vec2(64.0, 72.0);
const vec2 GLYPH_ORIGIN = vec2(8.0, 54.0);
const float GLYPH_EM = 48.0;
const int GLYPH_COLUMNS = 16;
const float DISTANCE_SPREAD = 6.0;
const int SLOTS = 32;
const int NAMES_PER_ROW = 64;
const float POSITION_SCALE = 256.0;
// The typeface's capitals' height (em), centered on the sign.
const float CAP_HEIGHT = 0.7;

// Paint, in sRGB: the city's sign green, the letters' white, the signs'
// aluminum edges and the galvanized posts.
const vec3 SIGN_GREEN = vec3(0.0, 0.42, 0.26);
const vec3 SIGN_WHITE = vec3(0.95, 0.96, 0.94);
const vec3 ALUMINUM = vec3(0.66, 0.68, 0.70);
const vec3 GALVANIZED = vec3(0.56, 0.58, 0.59);

uniform sampler2D street_glyphs : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform sampler2D street_names : filter_nearest, repeat_disable, hint_default_black;
// Signs shrink away between these distances from the camera (m); CityProps
// sets them.
uniform vec2 fade_distance = vec2(180.0, 260.0);
// How much street light (night) the signs catch, and how much their faces'
// reflective sheeting shines at night (times night).
uniform float street_light_catch = 1.0;
uniform float night_shine = 0.15;

// (variant, name, length m, 0).
varying flat vec4 item;
// Street light where the sign is (night).
varying flat vec3 item_light;
// Where this is in the sign's frame (m): x along the blade from its middle,
// y up from its bottom edge.
varying vec3 local_position;

void vertex() {
	int type = int(INSTANCE_CUSTOM.w + 0.5);
	float code = floor(INSTANCE_CUSTOM.y + 0.5);
	int variant = int(mod(code, 4.0) + 0.5);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float distance_to_camera = distance(camera, base);
	float shown = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	// Only the variant's own parts (CUSTOM0: type, variant bits).
	if (int(CUSTOM0.x + 0.5) != type || ((int(CUSTOM0.y + 0.5) >> variant) & 1) == 0) {
		shown = 0.0;
	}
	if (shown <= 0.0) {
		// Folded away: a point behind the camera, so its triangles are dropped.
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		float top = length(MODEL_MATRIX[1].xyz);
		float len = length(MODEL_MATRIX[0].xyz);
		float yaw = INSTANCE_CUSTOM.x;
		float name = floor(code / 4.0) * 1024.0 + floor(COLOR.r + 0.5);
		float h = variant == OVERHEAD ? OVERHEAD_HEIGHT : BLADE_HEIGHT;
		float bottom = top - h;
		int part = int(UV.x + 0.5);
		vec3 scale = vec3(len, h, THICKNESS);
		vec3 v = VERTEX * scale + vec3(0.0, bottom, 0.0);
		if (part == POST) {
			scale = vec3(1.0, bottom, 1.0);
			v = VERTEX * scale;
		} else if (part == BRACKET) {
			scale = vec3(1.0, BLADE_GAP, 1.0);
			v = VERTEX * scale + vec3(0.0, bottom, 0.0);
		} else if (part == HANGER) {
			// Built at the blade's ends (x = -0.5 or 0.5), up from its top.
			scale = vec3(1.0, HANGER_HEIGHT, 1.0);
			v = vec3(VERTEX.x + sign(VERTEX.x) * (0.5 * len - HANGER_INSET - 0.5),
					top + (VERTEX.y - 1.0) * HANGER_HEIGHT, VERTEX.z);
		}
		local_position = vec3(v.x, v.y - bottom, v.z);

		// Turn to the yaw (about +Y, as Godot's Basis turns: +z goes to (sin, cos)).
		float c = cos(yaw);
		float s = sin(yaw);
		vec3 turned = vec3(c * v.x + s * v.z, v.y, c * v.z - s * v.x);
		// Normals of a stretched shape follow the inverse of its stretch.
		vec3 n = NORMAL / scale;
		n = vec3(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
		VERTEX = (VIEW_MATRIX * vec4(base + turned * shown, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

		item = vec4(float(variant), name, len, 0.0);
		item_light = vec3(0.0);
		if (city_lights > 0.0 && !IN_SHADOW_PASS) {
			item_light = street_light_at(base.xz, distance_to_camera) * city_lights;
		}
	}
}

// A distance field's coverage, anti-aliased over a pixel (d < 0 inside).
float fill(float d) {
	return clamp(0.5 - d / max(fwidth(d), 1e-5), 0.0, 1.0);
}

float box_distance(vec2 p, vec2 center, vec2 half_size) {
	vec2 q = abs(p - center) - half_size;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// The pen's x (em) in a texel of the names table.
float pen_x(vec4 texel) {
	return (floor(texel.g * 255.0 + 0.5) * 256.0 + floor(texel.b * 255.0 + 0.5)) / POSITION_SCALE;
}

// How much of the name `name` (an id in the names table) covers the point
// `p` (m, from the middle of a face `size` m big's bottom edge), its letters
// `em` m to the em and squeezed to fit between `margin`s.
float name_coverage(int name, vec2 p, vec2 size, float em, float margin) {
	ivec2 first = ivec2((name % NAMES_PER_ROW) * SLOTS, name / NAMES_PER_ROW);
	// The slots past the end hold the name's width.
	float width = pen_x(texelFetch(street_names, first + ivec2(SLOTS - 1, 0), 0));
	float squeeze = min(1.0, max(size.x - 2.0 * margin, 0.01) / max(width * em, 0.01));
	// Em from the name's start along its baseline, capitals centered.
	vec2 t = vec2(p.x / (squeeze * em) + 0.5 * width, (p.y - 0.5 * size.y) / em + 0.5 * CAP_HEIGHT);
	vec2 t_dx = dFdx(t);
	vec2 t_dy = dFdy(t);
	float pixel = max(length(t_dx), length(t_dy));  // em
	if (t.x < -0.3 || t.x > width + 0.3 || t.y < -0.4 || t.y > 1.0) {
		return 0.0;
	}
	// The last character whose pen position is at or before t.
	int lo = 0;
	int hi = SLOTS - 1;
	for (int i = 0; i < 5; i++) {
		int mid = (lo + hi + 1) / 2;
		if (pen_x(texelFetch(street_names, first + ivec2(mid, 0), 0)) <= t.x) {
			lo = mid;
		} else {
			hi = mid - 1;
		}
	}
	// It and its neighbors, whose letters may reach over.
	vec2 atlas = vec2(textureSize(street_glyphs, 0));
	vec2 grad_x = t_dx * vec2(GLYPH_EM, -GLYPH_EM) / atlas;
	vec2 grad_y = t_dy * vec2(GLYPH_EM, -GLYPH_EM) / atlas;
	float d = 0.0;
	for (int i = max(lo - 1, 0); i <= min(lo + 1, SLOTS - 1); i++) {
		vec4 texel = texelFetch(street_names, first + ivec2(i, 0), 0);
		int glyph = int(texel.r * 255.0 + 0.5) - 1;
		vec2 at = GLYPH_ORIGIN + vec2(t.x - pen_x(texel), -t.y) * GLYPH_EM;
		if (glyph < 0 || any(lessThan(at, vec2(0.5))) || any(greaterThan(at, GLYPH_CELL - 0.5))) {
			continue;
		}
		vec2 cell = vec2(float(glyph % GLYPH_COLUMNS), float(glyph / GLYPH_COLUMNS)) * GLYPH_CELL;
		d = max(d, textureGrad(street_glyphs, (cell + at) / atlas, grad_x, grad_y).r);
	}
	// The field runs 0.5 over DISTANCE_SPREAD atlas pixels: smooth it over a
	// screen pixel, and blur it to the letters' average once they're tiny.
	float per_pixel = pixel * GLYPH_EM * 0.5 / DISTANCE_SPREAD;
	float ink = clamp((d - 0.5) / max(per_pixel, 1e-4) + 0.5, 0.0, 1.0);
	return mix(ink, 0.3, smoothstep(0.12, 0.4, pixel));
}

void fragment() {
	int part = int(UV.x + 0.5);
	int variant = int(item.x + 0.5);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 color = srgb(GALVANIZED);
	float shine = 0.0;
	float glint = 0.1;

	if (part == FACE || part == BACK) {
		bool overhead = variant == OVERHEAD;
		vec2 size = vec2(item.z, overhead ? OVERHEAD_HEIGHT : BLADE_HEIGHT);
		// Left to right as seen from either side.
		vec2 p = vec2(part == FACE ? local_position.x : -local_position.x, local_position.y);
		vec2 q = p - vec2(0.0, 0.5 * size.y);
		float ring = box_distance(q, vec2(0.0), 0.5 * size - BORDER_INSET - BORDER_RADIUS) - BORDER_RADIUS;
		float border = fill(abs(ring) - 0.5 * BORDER_WIDTH);
		float letters = name_coverage(int(item.y + 0.5), p, size, overhead ? OVERHEAD_EM : BLADE_EM,
				overhead ? OVERHEAD_MARGIN : BLADE_MARGIN);
		color = mix(srgb(SIGN_GREEN), srgb(SIGN_WHITE), max(border, letters));
		shine = 1.0;
		glint = 0.0;
	} else if (part == EDGE) {
		color = srgb(ALUMINUM);
	}

	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, 1.0);
	toon_glint = glint;
	if (city_lights > 0.0) {
		EMISSION += ALBEDO * item_light * street_light_catch;
	}
	EMISSION += ALBEDO * (night_shine * shine * night);
}
