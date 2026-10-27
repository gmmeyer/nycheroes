// Two bars' buildings (tools/citygen/landmarks.py): the Eagle (554 West
// 28th Street: red brick, its windows, belt courses and corbelled bands,
// roll-down gates, the roof deck's fence) and the Cock (93 Second Avenue:
// whitewashed brick with brown window hoods, the bar's storefront with its
// "I love NY" doors, the window with the neon rooster, the fire escape).
// Their faces (materials 64 and up in landmarks.py, the PLACE flag taken
// off) come in each tile's places surface (CityTileDecoder.SURFACE_PLACES),
// laid out like the landmarks surface (see landmark.gdshader). A shader of
// their own, compiled only once one is in view.
//
// Per vertex:
//   UV2.x material + 64 * flags (ROOF on roofs)
//   UV2.y param: the face's width in dm * 4 + a variant
//   UV    walls: (m from the face's left corner seen from outside, m above
//         the building's ground); panels: (m from their left, m up from
//         their foot); roofs: local (x, y) in m
// Lighting is the shared toon model; glass reflects the sky; at night the
// windows glow, and the neon always does.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Materials (UV2.x % 64), as landmarks.py numbers them less PLACES.
const int BRICK = 0;      // 0 the Eagle's front, 1 red brick, 2 the Cock's whitewashed front, 3 whitewashed brick
const int SHOPFRONT = 1;  // 0 a roll-down gate, 1 a black door, 2 an "I love NY" door, 3 a shop window
const int PAINT = 2;      // 0 black, 1 brown, 2 gray stone and roofing, 3 ironwork (seen through)
const int NEON = 3;       // a red neon tube
const int FENCE = 4;      // the Eagle's roof deck: 0 its black mesh windscreen

// Flags (UV2.x / 64), as in building.gdshader.
const int ROOF = 1;

// Colors, in sRGB.
const vec3 RED_BRICK = vec3(0.56, 0.28, 0.21);
const vec3 MORTAR = vec3(0.66, 0.62, 0.57);
const vec3 WHITEWASH = vec3(0.86, 0.85, 0.81);
const vec3 STONE = vec3(0.62, 0.61, 0.58);
const vec3 BLACK_PAINT = vec3(0.05, 0.05, 0.06);
const vec3 BROWN_PAINT = vec3(0.34, 0.22, 0.15);
const vec3 GATE_METAL = vec3(0.55, 0.56, 0.56);
const vec3 WINDOW_GLASS = vec3(0.16, 0.19, 0.23);
const vec3 HEART_RED = vec3(0.85, 0.12, 0.13);
const vec3 NEON_RED = vec3(1.0, 0.10, 0.14);
const vec3 LAMP_WARM = vec3(1.0, 0.70, 0.40);
const vec3 BAR_LIGHT = vec3(1.0, 0.38, 0.30);

// The Eagle's front, 7.4 m wide: its three windows upstairs (m from the
// left), their sills and heads (m up).
const vec3 EAGLE_WINDOWS = vec3(1.27, 3.61, 5.91);  // middles
const float EAGLE_WINDOW_HALF = 0.41;
const vec2 EAGLE_WINDOW_Z = vec2(4.24, 6.14);
// The Cock's front, 7.3 m wide: three windows a floor, floors of 3.3 m over
// the 4 m storefront.
const vec3 COCK_WINDOWS = vec3(1.25, 3.65, 6.05);
const float COCK_WINDOW_HALF = 0.47;
const float COCK_SHOP = 4.0;
const float COCK_FLOOR = 3.3;

// As in landmark.gdshader: how mirror-like glass is, the sky it reflects by
// day, at dusk and at night (blended by night.gdshaderinc's globals), and
// how walls darken toward their feet and catch the street lights.
uniform float glass_reflection : hint_range(0.0, 2.0) = 1.3;
uniform vec3 reflect_zenith : source_color = vec3(0.36, 0.58, 0.85);
uniform vec3 reflect_horizon : source_color = vec3(0.80, 0.87, 0.92);
uniform vec3 reflect_ground : source_color = vec3(0.30, 0.32, 0.36);
uniform vec3 dusk_reflect_zenith : source_color = vec3(0.30, 0.38, 0.62);
uniform vec3 dusk_reflect_horizon : source_color = vec3(0.98, 0.70, 0.52);
uniform vec3 dusk_reflect_ground : source_color = vec3(0.30, 0.27, 0.30);
uniform vec3 night_reflect_zenith : source_color = vec3(0.03, 0.05, 0.12);
uniform vec3 night_reflect_horizon : source_color = vec3(0.30, 0.21, 0.22);
uniform vec3 night_reflect_ground : source_color = vec3(0.13, 0.10, 0.09);
uniform float canyon_occlusion : hint_range(0.0, 1.0) = 0.85;
uniform float canyon_height = 25.0;
uniform float window_glow = 1.0;
uniform vec2 street_light_reach = vec2(3.0, 13.0);

// UV2 decoded into whole numbers in the vertex shader: (material + 64 *
// flags, param). Fragments round them back.
varying vec2 landmark_data;

vec3 sky_reflection(vec3 r) {
	vec3 zenith = reflect_zenith;
	vec3 horizon = reflect_horizon;
	vec3 ground = reflect_ground;
	if (dusk > 0.0 || night > 0.0) {
		zenith = mix(mix(zenith, dusk_reflect_zenith, dusk), night_reflect_zenith, night);
		horizon = mix(mix(horizon, dusk_reflect_horizon, dusk), night_reflect_horizon, night);
		ground = mix(mix(ground, dusk_reflect_ground, dusk), night_reflect_ground, night);
	}
	vec3 sky = mix(horizon, zenith, smoothstep(0.0, 0.65, r.y));
	return mix(ground, sky, smoothstep(-0.1, 0.03, r.y));
}

// Running bond brick: the brick's own shade (0.9..1.1) where `mortar` is 0.
vec2 brickwork(vec2 p, vec2 fp) {
	vec2 size = vec2(0.2, 0.076);
	float row = floor(p.y / size.y);
	float x = p.x / size.x + 0.5 * mod(row, 2.0);
	float mortar = max(centered_stripes(x, 0.08, fp.x / size.x), stripes(p.y / size.y, 0.14, fp.y / size.y));
	mortar *= visible(size.y, max(fp.x, fp.y));
	return vec2(mix(0.88, 1.1, hash(vec2(floor(x), row))), mortar);
}

// A rectangle's coverage, antialiased: x in [a.x, b.x], y in [a.y, b.y].
float box(vec2 p, vec2 a, vec2 b, vec2 fp) {
	return band(p.x, a.x, b.x, fp.x) * band(p.y, a.y, b.y, fp.y);
}

// Distance to the segment ab.
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Signed distance to a heart, its tip at the origin, about 1.2 wide and 1.1 tall.
float heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return length(p - vec2(0.25, 0.75)) - 0.35355;
	}
	vec2 a = p - vec2(0.0, 1.0);
	vec2 b = p - 0.5 * max(p.x + p.y, 0.0);
	return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

// "I love NY" in a unit square (x right, y up): the slab serif I and the
// heart over NY, as the bar paints it on its doors. x: the letters' white,
// y: the heart's red.
vec2 i_love_ny(vec2 q, float aa) {
	float s = 0.065;
	float d = segment(q, vec2(0.25, 0.58), vec2(0.25, 0.94));
	d = min(d, segment(q, vec2(0.15, 0.94), vec2(0.35, 0.94)));
	d = min(d, segment(q, vec2(0.15, 0.58), vec2(0.35, 0.58)));
	d = min(d, segment(q, vec2(0.14, 0.08), vec2(0.14, 0.44)));
	d = min(d, segment(q, vec2(0.14, 0.44), vec2(0.42, 0.08)));
	d = min(d, segment(q, vec2(0.42, 0.08), vec2(0.42, 0.44)));
	d = min(d, segment(q, vec2(0.55, 0.44), vec2(0.7, 0.27)));
	d = min(d, segment(q, vec2(0.85, 0.44), vec2(0.7, 0.27)));
	d = min(d, segment(q, vec2(0.7, 0.27), vec2(0.7, 0.08)));
	float letters = 1.0 - smoothstep(s - aa, s + aa, d);
	float h = heart((q - vec2(0.68, 0.55)) / 0.36) * 0.36;
	return vec2(letters, 1.0 - smoothstep(-aa, aa, h));
}

void vertex() {
	landmark_data = vec2(floor(UV2.x + 0.5), floor(UV2.y + 0.0005));
}

void fragment() {
	vec2 data = floor(landmark_data + 0.5);
	int code = int(data.x);
	int material = code % 64;
	bool roof = (code / 64) % 2 == ROOF;
	int variant = int(data.y) % 4;
	float width = float(int(data.y) / 4) * 0.1;
	vec2 p = UV;
	vec2 fp = max(fwidth(UV), vec2(1e-4));
	float pixel = max(fp.x, fp.y);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 scene = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 color;
	vec3 emission = vec3(0.0);
	float glass = 0.0;
	if (material == PAINT && variant == 3) {
		// Ironwork seen through: bars between rails on railings, slats on
		// gratings (roofs); the rest isn't there.
		float iron = roof ? stripes(p.x / 0.06, 0.4, fp.x / 0.06)
				: max(centered_stripes(p.x / 0.12, 0.2, fp.x / 0.12), band(p.y, 0.0, 0.06, fp.y));
		if (iron < 0.5 * visible(0.12, pixel) + 0.02) {
			discard;
		}
		color = srgb(BLACK_PAINT) * 1.4;
	} else if (roof) {
		// Roofing: gray membrane with its seams.
		float seams = stripes(p.x / 1.0, 0.03, fp.x / 1.0) * visible(1.0, pixel);
		color = srgb(vec3(0.60, 0.59, 0.56)) * (0.9 + 0.15 * value_noise(p * 0.5)) * (1.0 - 0.2 * seams);
		if (material == PAINT && variant == 0) {
			color = srgb(BLACK_PAINT);
		} else if (material == PAINT && variant == 1) {
			color = srgb(BROWN_PAINT);
		}
	} else if (material == BRICK) {
		bool eagle = variant == 0;
		bool cock = variant == 2;
		bool whitewashed = variant >= 2;
		vec2 b = brickwork(p, fp);
		vec3 brick = srgb(RED_BRICK) * b.x * (0.92 + 0.12 * value_noise(p * vec2(0.6, 1.5)));
		color = mix(brick, srgb(MORTAR), b.y);
		if (whitewashed) {
			// Peeling: the red brick shows through in patches, most just above
			// the storefront.
			float peel = smoothstep(0.86, 0.92, value_noise(p * vec2(1.1, 0.8)) + 0.2 * value_noise(p * 5.0)
					+ 0.12 * (1.0 - smoothstep(0.0, 1.5, p.y - COCK_SHOP)));
			vec3 white = srgb(WHITEWASH) * (0.94 + 0.08 * value_noise(p * 2.0)) * mix(1.0, 0.9, b.y);
			color = mix(white, color, peel * 0.85);
		}
		// Grime toward the street.
		color *= mix(0.82, 1.0, smoothstep(0.0, 2.5, p.y));
		if (eagle) {
			float k = width / 7.4;
			// Stone belt courses: over the ground floor, through the windows'
			// middles, along their heads; the coping on top.
			float stone = band(p.y, 4.0, 4.18, fp.y) + band(p.y, 5.28, 5.37, fp.y) + band(p.y, 6.14, 6.24, fp.y)
					+ band(p.y, 7.93, 8.1, fp.y);
			// Corbelled bands: rows of brick stepping out (light tops, shadowed between).
			float corbel = (band(p.y, 4.18, 4.33, fp.y) + band(p.y, 6.52, 6.72, fp.y))
					* stripes(p.x / 0.22, 0.45, fp.x / 0.22);
			color = mix(color, color * 0.55, corbel * visible(0.22, pixel));
			color = mix(color, srgb(STONE) * (0.9 + 0.12 * value_noise(p * 3.0)), min(stone, 1.0));
			// The pilasters' edges.
			float pilaster = band(p.x, 0.34 * k, 0.4 * k, fp.x) + band(p.x, width - 0.4 * k, width - 0.34 * k, fp.x);
			color *= 1.0 - 0.35 * pilaster * step(p.y, 7.93);
			// The windows: dark sashes in black frames, the top sash's rail.
			vec3 mids = EAGLE_WINDOWS * k;
			float window = 0.0;
			float frame = 0.0;
			float lit = 0.0;
			for (int w = 0; w < 3; w++) {
				float m = mids[w];
				float open = box(p, vec2(m - EAGLE_WINDOW_HALF * k, EAGLE_WINDOW_Z.x), vec2(m + EAGLE_WINDOW_HALF * k, EAGLE_WINDOW_Z.y), fp);
				window += open;
				frame += open - box(p, vec2(m - EAGLE_WINDOW_HALF * k + 0.07, EAGLE_WINDOW_Z.x + 0.07),
						vec2(m + EAGLE_WINDOW_HALF * k - 0.07, EAGLE_WINDOW_Z.y - 0.07), fp);
				lit += open * step(0.3, hash(vec2(float(w), 3.0)));
			}
			frame += band(abs(p.y - 5.2), 0.0, 0.04, fp.y) * window;
			vec3 pane = srgb(WINDOW_GLASS) * (0.9 + 0.2 * value_noise(p * 2.0));
			color = mix(color, mix(pane, srgb(BLACK_PAINT) * 2.0, min(frame, 1.0)), min(window, 1.0));
			glass = 0.8 * (min(window, 1.0) - min(frame, 1.0));
			emission = srgb(BAR_LIGHT) * (glass * min(lit, 1.0) * 0.9 * window_glow * city_lights);
		} else if (cock) {
			float k = width / 7.3;
			// Brown storefront paint below its fascia (behind the storefront's
			// parts), then four floors of windows: brown hoods over them,
			// brown sills, an air conditioner in some.
			float shop = 1.0 - band(p.y, COCK_SHOP - 0.05, 1e4, fp.y);
			float level = (p.y - COCK_SHOP) / COCK_FLOOR;
			float floor_ = floor(level);
			float z = fract(level) * COCK_FLOOR;
			vec3 mids = COCK_WINDOWS * k;
			float h = COCK_WINDOW_HALF * k;
			float window = 0.0;
			float trim = 0.0;    // hoods and sills
			float sash = 0.0;    // frames and the meeting rail
			float ac = 0.0;      // air conditioners
			float lit = 0.0;
			for (int w = 0; w < 3; w++) {
				vec2 q = vec2(p.x - mids[w], z);
				float r = hash(vec2(float(w), floor_ + 11.0));
				float open = box(q, vec2(-h, 0.85), vec2(h, 2.65), fp);
				window += open;
				trim += box(q, vec2(-h - 0.16, 2.65), vec2(h + 0.16, 2.97), fp) + box(q, vec2(-h - 0.06, 0.74), vec2(h + 0.06, 0.85), fp);
				sash += open - box(q, vec2(-h + 0.06, 0.91), vec2(h - 0.06, 2.59), fp) + open * band(abs(q.y - 1.76), 0.0, 0.035, fp.y);
				ac += step(0.72, r) * box(q, vec2(-0.32, 0.92), vec2(0.32, 1.3), fp);
				lit += open * step(0.45, r);
			}
			float upstairs = step(0.0, level) * step(level, 4.0);
			window = min(window, 1.0) * upstairs;
			vec3 brown = srgb(BROWN_PAINT) * (0.9 + 0.2 * value_noise(p * 4.0));
			brown *= 1.0 - 0.4 * band(z, 2.65, 2.72, fp.y);  // the hoods' shadowed undersides
			color = mix(color, brown, min(trim, 1.0) * upstairs);
			vec3 pane = srgb(WINDOW_GLASS) * (0.85 + 0.25 * value_noise(p * 2.0));
			vec3 inside = mix(mix(pane, srgb(BROWN_PAINT) * 1.3, min(sash, 1.0)), srgb(vec3(0.78, 0.78, 0.76)), min(ac, 1.0));
			color = mix(color, inside, window);
			glass = 0.75 * window * (1.0 - min(sash + ac, 1.0));
			emission = srgb(LAMP_WARM) * (glass * min(lit, 1.0) * 0.8 * window_glow * city_lights);
			color = mix(color, srgb(BROWN_PAINT), shop);
		}
	} else if (material == SHOPFRONT) {
		if (variant == 0) {
			// A roll-down gate: corrugated slats, a bar at its foot, grime.
			float slats = stripes(p.y / 0.075, 0.5, fp.y / 0.075) * visible(0.075, pixel);
			color = srgb(GATE_METAL) * (0.85 + 0.15 * slats) * (0.9 + 0.15 * value_noise(p * vec2(0.8, 3.0)));
			color *= mix(0.7, 1.0, smoothstep(0.0, 1.2, p.y));
			color = mix(color, srgb(GATE_METAL) * 0.5, band(p.y, 0.0, 0.1, fp.y));
			glass = 0.15;
		} else if (variant == 1) {
			// A black door, or a pair (wide openings) with glass in their tops.
			float pair = step(1.2, width);
			float u = pair > 0.5 ? fract(p.x / (width * 0.5)) * width * 0.5 : p.x;
			float w = pair > 0.5 ? width * 0.5 : width;
			float pane = box(vec2(u, p.y), vec2(0.15, 1.3), vec2(w - 0.15, 2.9), fp) * pair;
			color = mix(srgb(BLACK_PAINT), srgb(WINDOW_GLASS) * 0.9, pane);
			// Notices taped up inside.
			color = mix(color, srgb(vec3(0.85, 0.84, 0.8)), pane * box(vec2(u, p.y), vec2(0.3, 1.7), vec2(0.62, 2.1), fp));
			glass = 0.15 + 0.6 * pane;
			emission = srgb(BAR_LIGHT) * (pane * 0.2 * city_lights);
		} else if (variant == 2) {
			// "I love NY" twice, in white with a red heart, on black.
			float rows = clamp(floor(3.2 / max(width, 0.4) + 0.5), 1.0, 2.0);
			float cell_h = 3.2 / rows;
			float side = min(width, cell_h) * 0.92;
			vec2 cell = vec2(p.x, mod(p.y, cell_h));
			vec2 q = (cell - vec2((width - side) * 0.5, (cell_h - side) * 0.5)) / side;
			vec2 mark = i_love_ny(q, pixel / side * 1.2) * step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
			color = mix(srgb(BLACK_PAINT), srgb(vec3(0.92, 0.92, 0.9)), mark.x);
			color = mix(color, srgb(HEART_RED), mark.y);
			glass = 0.1;
		} else {
			// The bar's window: dark glass, a paper notice or two, a red glow
			// inside at night.
			color = srgb(WINDOW_GLASS) * 0.7;
			float notice = box(p, vec2(0.1, 1.55), vec2(0.38, 1.95), fp) + box(p, vec2(0.45, 1.6), vec2(0.62, 1.85), fp);
			color = mix(color, srgb(vec3(0.88, 0.86, 0.8)), min(notice, 1.0));
			glass = 0.85 * (1.0 - min(notice, 1.0));
			emission = srgb(BAR_LIGHT) * (glass * 0.12 * city_lights);
		}
	} else if (material == PAINT) {
		color = variant == 0 ? srgb(BLACK_PAINT) : (variant == 1 ? srgb(BROWN_PAINT) * (0.9 + 0.2 * value_noise(p * 3.0))
				: srgb(STONE) * (0.92 + 0.1 * value_noise(p * 2.0)));
		glass = variant == 0 ? 0.15 : 0.0;
	} else if (material == NEON) {
		color = srgb(NEON_RED);
		emission = srgb(NEON_RED) * (1.6 + 2.4 * city_lights);
	} else {
		// The roof deck's windscreen: black mesh on the fence, a little
		// lighter where the sky shows through it.
		float weave = max(stripes(p.x / 0.05, 0.5, fp.x / 0.05), stripes(p.y / 0.05, 0.5, fp.y / 0.05));
		color = srgb(vec3(0.14, 0.14, 0.15)) * mix(1.25, 0.8, weave * visible(0.05, pixel));
	}

	// Glass reflects the sky, more at grazing angles.
	float n_dot_v = clamp(dot(world_normal, world_view), 0.0, 1.0);
	float fresnel = mix(0.3, 1.0, pow(1.0 - n_dot_v, 3.0));
	float mirror = clamp(glass * glass_reflection, 0.0, 1.0) * fresnel;
	vec3 reflection = sky_reflection(reflect(-world_view, world_normal)) * mirror;
	float occlusion = roof ? 1.0 : mix(canyon_occlusion, 1.0, smoothstep(0.0, canyon_height, UV.y));

	ALBEDO = toon_night_albedo(color * (1.0 - 0.6 * mirror));
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + emission + reflection;
	toon_glint = glass;

	// Street lights on the feet of the walls near them.
	if (city_lights > 0.0 && !roof) {
		float reach = 1.0 - smoothstep(street_light_reach.x, street_light_reach.y, UV.y);
		if (reach > 0.0) {
			EMISSION += ALBEDO * street_light_at(scene.xz, length(VERTEX)) * (reach * city_lights);
		}
	}
}
