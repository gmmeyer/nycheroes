// The waterfront landmarks (tools/citygen/landmarks.py: the St. George and
// Whitehall ferry terminals with their slips, Chelsea Piers' sheds and the
// golf range's poles, Brooklyn Bridge Park's Pier 2 roofs, the slips' timber
// racks, the marina's docks and boats, the Staten Island ferries). Their
// faces with materials 60 and up come in each tile's waterfront surface
// (CityTileDecoder.SURFACE_WATERFRONT), laid out like the landmarks surface
// (see landmark.gdshader). They have a shader of their own, compiled only once
// they're in view, so the landmarks' one stays small enough to compile
// quickly.
//
// Per vertex:
//   UV2.x material + 64 * flags (ROOF on roofs)
//   UV2.y param: on walls the face's width in dm * 4 + a variant
//   UV    walls: (m along the face, m above the landmark's ground); roofs:
//         local (x, y) in m
// Lighting is the shared toon model; glass reflects the sky; at night the
// terminals' glass and the boats' and panels' windows glow.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Materials (the archetype slot of UV2.x), as landmarks.py numbers them.
const int PIERSIDE = 60;  // 0 glass curtain wall, 1 brick, 2 metal panels with windows, 3 white steel
const int TIMBER = 61;    // 0 fender racks, 1 decking, 2 a boat, 3 a Staten Island ferry

// Flags (UV2.x / 64), as in building.gdshader.
const int ROOF = 1;

// Colors, in sRGB.
const vec3 ALUMINUM = vec3(0.84, 0.85, 0.86);
const vec3 TERMINAL_GLASS = vec3(0.27, 0.34, 0.40);
const vec3 DARK_GLASS = vec3(0.22, 0.28, 0.34);
const vec3 PANELS = vec3(0.76, 0.78, 0.79);
const vec3 BRICK = vec3(0.47, 0.26, 0.20);
const vec3 MORTAR = vec3(0.62, 0.58, 0.53);
const vec3 PAINT_WHITE = vec3(0.94, 0.94, 0.93);
const vec3 SIGN_BLUE = vec3(0.06, 0.22, 0.55);
const vec3 WOOD = vec3(0.46, 0.41, 0.34);
const vec3 DECK_BOARDS = vec3(0.42, 0.36, 0.29);
const vec3 FERRY_ORANGE = vec3(0.86, 0.42, 0.13);
const vec3 BOOT_STRIPE = vec3(0.10, 0.12, 0.16);
const vec3 METAL_ROOF = vec3(0.60, 0.62, 0.63);
const vec3 LAMP_SOFT = vec3(1.0, 0.84, 0.62);
const vec3 LOBBY_LIGHT = vec3(1.0, 0.88, 0.68);

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
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 scene = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Height above the water (the tide's mark, the boats' bands).
	float h = scene.y;

	vec3 color;
	vec3 emission = vec3(0.0);
	float glass = 0.0;
	if (roof) {
		// Metal roofing; decking, weathered; boats' decks white.
		color = srgb(material == PIERSIDE ? METAL_ROOF : (variant == 1 ? DECK_BOARDS : PAINT_WHITE));
		color *= material == TIMBER && variant == 1 ? 0.85 + 0.2 * value_noise(p * vec2(0.4, 3.0)) : 1.0;
		glass = material == PIERSIDE ? 0.3 : 0.0;
	} else if (material == PIERSIDE && variant != 3) {
		// A glass curtain wall in an aluminum grid (the waiting rooms' lights
		// behind it at night), metal panels with a band of windows every 4.5 m
		// (one grid, the panels its wide rails), or brick in courses, grimy
		// toward the water.
		bool panels = variant == 2;
		bool brick = variant == 1;
		vec2 size = brick ? vec2(0.2, 0.076) : (panels ? vec2(2.0, 4.5) : vec2(1.6, 3.3));
		vec2 cell = floor(p / size);
		float shift = brick ? 0.5 * mod(cell.y, 2.0) : 0.0;
		float frame = max(centered_stripes(p.x / size.x + shift, brick ? 0.1 : 0.07, fp.x / size.x),
				stripes(p.y / size.y - (panels ? 0.75 : 0.0), panels ? 0.7 : (brick ? 0.16 : 0.06), fp.y / size.y));
		float tint = mix(0.9, 1.1, hash(cell + vec2(shift, 0.0)));
		vec3 pane = srgb(brick ? BRICK : (panels ? DARK_GLASS : TERMINAL_GLASS)) * tint;
		vec3 rails = srgb(brick ? MORTAR : (panels ? PANELS : ALUMINUM)) * (brick ? 0.85 : 1.0);
		color = mix(pane, rails, frame * (brick ? visible(0.076, max(fp.x, fp.y)) : 1.0));
		color *= brick ? mix(0.7, 1.0, smoothstep(1.0, 5.0, h)) : 1.0;
		glass = brick ? 0.0 : 0.85 * (1.0 - frame);
		float lit = brick ? 0.0 : (1.0 - frame) * (panels ? step(0.55, tint) * 0.8 : 0.5);
		emission = srgb(panels ? LAMP_SOFT : LOBBY_LIGHT) * (lit * window_glow * city_lights);
	} else if (material == PIERSIDE) {
		// White-painted steel; along a canopy's fascia (long faces whose uv.y
		// runs up from the fascia's foot) the words in big blue letters, as
		// blocks (as text reads from across the plaza).
		color = srgb(PAINT_WHITE) * 0.95;
		glass = 0.3;
		float x = p.x / 0.62;
		float letters = step(25.0, width) * step(p.y, 1.2) * band(p.y, 0.2, 0.9, fp.y)
				* band(fract(x), 0.12, 0.82, fp.x / 0.62) * step(0.15, hash(vec2(floor(x), 17.0)));
		color = mix(color, srgb(SIGN_BLUE), letters);
		emission = srgb(SIGN_BLUE) * (letters * 0.6 * city_lights);
	} else if (variant <= 1) {
		// Timber: piles side by side in the racks, plain boards on the docks'
		// edges; darker and greener where the tide wets them.
		float wood = variant == 0 ? centered_stripes(p.x / 0.4, 0.84, fp.x / 0.4) : 1.0;
		color = srgb(WOOD) * (0.8 + 0.3 * value_noise(p * vec2(1.5, 0.4))) * mix(0.62, 1.0, wood);
		color = mix(color * vec3(0.55, 0.62, 0.55), color, smoothstep(0.6, 2.2, h));
	} else {
		// Boats: white topsides (a ferry's orange, a white line at its main
		// deck) over a dark boot stripe at the waterline; above, cabins and
		// decks with bands of windows, lit at night.
		bool ferry = variant == 3;
		float deck = ferry ? 4.5 : 1.5;
		float rows = ferry ? 3.0 : 1.2;
		float window = band(ferry ? fract((h - deck) / rows) : (h - 1.4) / rows, 0.35, 0.8, fp.y / rows) * step(deck, h)
				* (1.0 - centered_stripes(p.x / 1.4, 0.12, fp.x / 1.4));
		color = mix(srgb(ferry ? FERRY_ORANGE : PAINT_WHITE), srgb(BOOT_STRIPE), 1.0 - smoothstep(0.25, 0.4, h));
		color = mix(color, srgb(PAINT_WHITE), ferry ? 1.0 - smoothstep(0.1, 0.3, abs(h - deck)) : 0.0);
		color = mix(color, srgb(vec3(0.12, 0.14, 0.18)), window);
		glass = 0.25 + 0.5 * window;
		emission = srgb(LAMP_SOFT) * (window * 0.8 * city_lights);
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
