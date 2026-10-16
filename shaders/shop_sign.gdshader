// Shop fronts from near city tiles' props (scripts/world/city_props.gd):
// signs and awnings on shops' street walls, on the mesh from
// PropMeshes.shop_fronts(). Per instance (the props' common layout):
//   transform        scales by the prop's width (x, z) and height (y) and
//                    moves it to its base on the wall
//   INSTANCE_CUSTOM  (yaw radians: its front faces (sin, 0, cos) of it, out of
//                    the wall; variant (CityTileDecoder.SIGN_* or AWNING_*);
//                    seed 0..1; prop type 17 sign, 18 awning)
//   COLOR.r          the shop's name (a row of the names texture), plus half
//                    an awning's reach out from the wall (m)
// The mesh holds every shape, each tagged with its type, the variants it's
// for, and how its x and z stretch (CUSTOM0, see PropMeshes); this shader
// folds away all but the instance's own, stretches that one to the prop's
// size, turns it to its yaw and moves it into place itself
// (skip_vertex_transform), like the street furniture's. Signs and awnings
// shrink away between fade_distance from the camera (CityProps sets it, a
// share of the large furniture's).
//
// The names are invented (no real brands): sign_names, a signed distance
// field of 64 names (tools/citygen/sign_names.py), so letters stay crisp up
// close and get outlines for free. The look: boards in a bold color with
// light letters, or light with colored letters, or dark with yellow ones;
// light boxes glow (softly by day, brightly at night), channel letters are
// cut out of their quad, standing off a plain fascia, and light up at night; blade signs carry their name up the panel;
// banners are vinyl with grommets. Awnings are cloth (some striped, the
// valance or dome carrying the shop's name) or ribbed aluminum, darker
// underneath, where shop windows light them at night. At night pieces near a
// street light catch its light (night.gdshaderinc). Lighting is the shared
// toon model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, cull_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes.ShopPart numbers them.
const int FACE = 0;
const int EDGE = 1;
const int LETTERS = 2;
const int LETTER_BACKS = 3;
const int CLOTH = 4;
const int VALANCE = 5;
const int ALUMINUM = 6;

const int TYPE_AWNING = 18;
// Variants (CityTileDecoder.SIGN_*, AWNING_*).
const int LIGHT_BOX = 1;
const int CHANNEL_LETTERS = 2;
const int BLADE = 3;
const int BANNER = 4;
const int ALUMINUM_AWNING = 1;
const int DOME = 2;
// As PropMeshes builds them: how x and z stretch (CUSTOM0.z, .w), a blade
// panel's gap from the wall (share of its width), a cloth awning's valance
// (share of its drop).
const int BY_WIDTH = 1;
const int BY_REACH = 2;
const float BLADE_GAP = 0.14;
const float VALANCE_SHARE = 0.25;
// The names texture (sign_names.py): two columns of 32 cells, each eight
// times as wide as tall; its bottom row says how wide each name is.
const vec2 NAME_CELLS = vec2(2.0, 32.0);
const float NAME_ASPECT = 8.0;

uniform sampler2D sign_names : filter_linear_mipmap, repeat_disable, hint_default_black;
// Signs and awnings shrink away between these distances from the camera (m).
uniform vec2 fade_distance = vec2(260.0, 360.0);
// Light boxes' and channel letters' glow by day and at night; boards are lit
// a little at night (gooseneck lamps).
uniform vec2 light_box_glow = vec2(0.25, 1.4);
uniform vec2 letters_glow = vec2(0.0, 1.6);
uniform float board_night_light = 0.35;
// Shop windows' light on awnings' undersides at night (sRGB).
uniform vec3 window_light : source_color = vec3(1.0, 0.82, 0.55);
// How much street light (night) the pieces catch.
uniform float street_light_catch = 1.0;

// (type, variant, seed in 1024ths, name).
varying flat vec4 item;
// Street light where the piece is (night).
varying flat vec3 item_light;
// Where this is in the piece's own frame (m), and a face's size (m; UV2
// runs 0..1 across it).
varying vec3 local_position;
varying vec2 face_size;

// A random number per piece (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

// A color from hue, saturation and value (all 0..1).
vec3 hsv(float h, float s, float v) {
	vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), rgb, s);
}

void vertex() {
	int variant = int(INSTANCE_CUSTOM.y + 0.5);
	int type = int(INSTANCE_CUSTOM.w + 0.5);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float distance_to_camera = distance(camera, base);
	float shown = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	// Only the piece's own shape (CUSTOM0: type, variant bits).
	if (int(CUSTOM0.x + 0.5) != type || ((int(CUSTOM0.y + 0.5) >> variant) & 1) == 0) {
		shown = 0.0;
	}
	if (shown <= 0.0) {
		// Folded away: a point behind the camera, so its triangles are dropped.
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		float height = length(MODEL_MATRIX[1].xyz);
		float width = length(MODEL_MATRIX[0].xyz);
		float yaw = INSTANCE_CUSTOM.x;
		// Custom data arrives as half floats; whole 1024ths survive that exactly.
		float seed = floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5);
		float name = floor(COLOR.r + 0.01);
		float reach = fract(COLOR.r + 0.01) * 2.0;
		int part = int(UV.x + 0.5);
		int x_rule = int(CUSTOM0.z + 0.5);
		int z_rule = int(CUSTOM0.w + 0.5);
		vec3 scale = vec3(x_rule == BY_WIDTH ? width : 1.0, height,
				z_rule == BY_WIDTH ? width : (z_rule == BY_REACH ? reach : 1.0));
		vec3 v = VERTEX * scale;
		local_position = v;
		face_size = vec2(width, height);
		if (type != TYPE_AWNING && variant == BLADE) {
			face_size.x = width * (1.0 - BLADE_GAP);
		} else if (part == VALANCE) {
			face_size.y = height * VALANCE_SHARE;
		} else if (part == CLOTH || part == ALUMINUM) {
			face_size.y = length(vec2(reach, height));
		}

		// Turn to the yaw (about +Y, as Godot's Basis turns: +z goes to (sin, cos)).
		float c = cos(yaw);
		float s = sin(yaw);
		vec3 turned = vec3(c * v.x + s * v.z, v.y, c * v.z - s * v.x);
		// Normals of a stretched shape follow the inverse of its stretch.
		vec3 n = NORMAL / scale;
		n = vec3(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
		VERTEX = (VIEW_MATRIX * vec4(base + turned * shown, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

		item = vec4(float(type), float(variant), seed, name);
		item_light = vec3(0.0);
		if (city_lights > 0.0 && !IN_SHADOW_PASS) {
			item_light = street_light_at(base.xz, distance_to_camera) * city_lights;
		}
	}
}

// The name `name` (a row of sign_names) written on a face `size` m big at
// uv (0..1 across it), as big as fits inside `margin` m of its edges:
// (the letters' coverage, their outline's: the letters grown by about a
// sixteenth of their height).
vec2 name_coverage(float name, vec2 uv, vec2 size, vec2 margin) {
	float width = texelFetch(sign_names, ivec2(int(name), textureSize(sign_names, 0).y - 1), 0).r;
	vec2 area = max(size - 2.0 * margin, vec2(0.01));
	// Meters per cell height: the name's width fits the area's, the cell's
	// height the area's.
	float cell = min(area.y, area.x / max(width * NAME_ASPECT, 0.5));
	vec2 q = (uv - 0.5) * size / cell;
	vec2 at = clamp(vec2(0.5 + q.x / NAME_ASPECT, 0.5 - q.y), 0.0, 1.0);
	float inside = step(abs(q.x), 0.5 * NAME_ASPECT * width + 0.15) * step(abs(q.y), 0.5);
	vec2 corner = vec2(floor(name / NAME_CELLS.y), mod(name, NAME_CELLS.y));
	float d = texture(sign_names, (corner + at) / NAME_CELLS).r;
	float aa = max(fwidth(d), 0.01);
	return vec2(smoothstep(0.5 - aa, 0.5 + aa, d), smoothstep(0.3 - aa, 0.3 + aa, d)) * inside;
}

void fragment() {
	int part = int(UV.x + 0.5);
	int type = int(item.x + 0.5);
	int variant = int(item.y + 0.5);
	float seed = item.z;
	vec2 uv = UV2;
	vec2 p = uv * face_size;
	vec2 footprint = max(fwidth(p), vec2(1e-4));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bool awning = type == TYPE_AWNING;

	// The shop's colors: a sign's face, its letters and their outline; an
	// awning's cloth. Bold color with light letters, light with colored
	// letters, dark with yellow or white letters, or yellow with red.
	float scheme = rnd(seed, 1.0);
	float hue = rnd(seed, 2.0);
	// Reds, yellows and blues are the commonest.
	hue = hue < 0.5 ? (hue < 0.25 ? 0.0 : 0.62) : (hue < 0.62 ? 0.12 : hue);
	vec3 bold = hsv(hue, mix(0.6, 0.8, rnd(seed, 3.0)), mix(0.55, 0.78, rnd(seed, 4.0)));
	vec3 light = vec3(0.93, 0.91, 0.85);
	vec3 face = bold;
	vec3 ink = light;
	vec3 rim = bold * 0.4;
	if (scheme > 0.42 && scheme <= 0.68) {
		face = light;
		ink = bold * 0.8;
		rim = light;
	} else if (scheme > 0.68 && scheme <= 0.88) {
		face = vec3(0.10, 0.10, 0.11);
		ink = rnd(seed, 5.0) < 0.5 ? vec3(0.98, 0.82, 0.25) : light;
		rim = face;
	} else if (scheme > 0.88) {
		face = vec3(0.96, 0.80, 0.20);
		ink = vec3(0.78, 0.14, 0.12);
		rim = light;
	}
	vec3 color = srgb(face);
	float glint = 0.0;
	float occlusion = 1.0;
	vec3 glow = vec3(0.0);
	// Lit at night: boards a little, light boxes and letters a lot.
	float lit = board_night_light * city_lights;
	float name = item.w;

	// Where the shop's name goes, if anywhere: a sign's face (up a blade
	// sign's panel, reading from the bottom), channel letters' quads, an
	// awning's valance or a dome's lower front. One name_coverage() call for
	// all of them (see "Shader compile time" in docs/ROADMAP.md).
	bool sign_face = !awning && (part == FACE || part == LETTERS || part == LETTER_BACKS);
	bool dome_front = awning && variant == DOME && part == CLOTH && uv.y < 0.5;
	vec2 text_uv = uv;
	vec2 text_size = face_size;
	vec2 margin = vec2(0.12, 0.1) * min(face_size.y, 1.2);
	if (variant == BLADE && !awning) {
		text_uv = vec2(uv.y, 1.0 - uv.x);
		text_size = face_size.yx;
		margin = vec2(0.1, 0.08) * face_size.x;
	} else if (variant == CHANNEL_LETTERS && !awning) {
		margin = vec2(0.0);
	} else if (part == VALANCE) {
		margin = vec2(0.15, 0.02);
	} else if (dome_front) {
		text_uv.y = uv.y * 2.0;
		text_size.y = face_size.y * 0.5;
		margin = vec2(0.3, 0.06);
	}
	vec2 text = sign_face || part == VALANCE || dome_front ? name_coverage(name, text_uv, text_size, margin) : vec2(0.0);
	bool pale_fascia = rnd(seed, 9.0) >= 0.6;

	if (sign_face && variant == CHANNEL_LETTERS && part == LETTERS) {
		// Letters alone, cut out, standing off a plain fascia.
		if (text.x < 0.5) {
			discard;
		}
		color = srgb(pale_fascia ? bold * 0.75 : (scheme > 0.68 && scheme <= 0.88 ? ink : mix(bold, light, 0.25)));
		lit = mix(letters_glow.x, letters_glow.y, city_lights);
		glint = 0.2;
	} else if (sign_face && variant == CHANNEL_LETTERS) {
		// The fascia (over the painted sign band): dark, or pale stone.
		color = srgb(pale_fascia ? vec3(0.72, 0.70, 0.65) : vec3(0.11, 0.11, 0.12));
		lit = 0.0;
	} else if (sign_face) {
		// A frame round the face (a banner's hem, with grommets).
		vec2 edge = min(p, face_size - p);
		float frame = 1.0 - band(min(edge.x, edge.y), variant == BANNER ? 0.05 : 0.04, 1e3, max(footprint.x, footprint.y));
		vec3 board = variant == BANNER ? (scheme < 0.5 ? light : vec3(0.95, 0.85, 0.25)) : face;
		vec3 letters = variant == BANNER ? (scheme < 0.5 ? bold * 0.8 : vec3(0.75, 0.12, 0.10)) : ink;
		color = mix(srgb(board), srgb(rim), text.y * float(rim != face));
		color = mix(color, srgb(letters), text.x);
		color = mix(color, srgb(variant == BANNER ? board * 0.85 : rim * 0.8 + 0.05), frame);
		if (variant == BANNER) {
			vec2 hole = min(p, face_size - p) - 0.06;
			color = mix(color, srgb(vec3(0.6)), 1.0 - smoothstep(0.012, 0.02, length(hole)));
			// Creases in the vinyl.
			color *= 1.0 - 0.06 * value_noise(p * vec2(1.5, 4.0) + seed);
		} else if (variant == LIGHT_BOX) {
			// Lit from inside.
			lit = mix(light_box_glow.x, light_box_glow.y, city_lights);
			glint = 0.4;
		}
	} else if (!awning) {
		// Edges and brackets: painted metal.
		color = srgb(variant == BLADE || variant == LIGHT_BOX ? vec3(0.16, 0.16, 0.17) : rim * 0.8 + 0.05);
		glint = 0.15;
		lit = 0.0;
	} else {
		// Awnings: cloth in the shop's bold color (dark ones for domes), a
		// third of them striped; aluminum white, cream, bronze or green.
		vec3 cloth = variant == DOME && rnd(seed, 6.0) < 0.5 ? vec3(0.09, 0.09, 0.10) : bold * 0.85;
		float striped = step(rnd(seed, 7.0), 0.3) * float(variant != DOME)
				* stripes(local_position.x / 0.5, 0.5, footprint.x / 0.5);
		cloth = mix(cloth, light, striped);
		if (variant == ALUMINUM_AWNING) {
			float r = rnd(seed, 8.0);
			cloth = r < 0.4 ? vec3(0.88, 0.88, 0.85) : (r < 0.6 ? vec3(0.86, 0.80, 0.64)
					: (r < 0.8 ? vec3(0.35, 0.24, 0.16) : vec3(0.20, 0.36, 0.25)));
			// Ribs across the slope.
			cloth *= 1.0 - 0.18 * centered_stripes(local_position.x / 0.12, 0.25, footprint.x / 0.12);
			text = vec2(0.0);
		}
		color = srgb(cloth);
		// The shop's name, dark on stripes, else light.
		color = mix(color, srgb(striped > 0.5 ? vec3(0.12) : light), text.x);
		lit = 0.0;
		if (!FRONT_FACING) {
			// Underneath: darker, and lit by the shop windows at night.
			color *= 0.7;
			glow += color * srgb(window_light) * (0.9 * city_lights);
		}
		occlusion = mix(0.75, 1.0, uv.y);
	}

	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + glow + color * lit;
	toon_glint = glint;
	if (city_lights > 0.0) {
		EMISSION += ALBEDO * item_light * street_light_catch;
	}
}
