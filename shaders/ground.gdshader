// Ground and structures (bridges) from tools/citygen/build_tiles.py, in the
// city's stylized look: clean, slightly saturated colors with a few bold
// details (sidewalk flags, asphalt patches, mottled grass, stone courses)
// that fade to their average color in the distance.
// UV2.x: 0 pavement, 1 road, 2 park, 3 seawall, 4 sand, 5 marsh,
//        6 concrete (curbs, bridge deck sides, columns, steel towers), 7 cable, 8 stone (towers),
//        9 yard (back yards, gardens, lawns around homes),
//        14 painted steel, 15 walkway, 16 track bed (the hand-made bridges,
//        tools/citygen/bridge_landmarks.py; and the els, tools/citygen/els.py),
//        20 shrubs (beds and hedges on planted medians, a low mound), 21 pavers
//        (pedestrian plazas), 22 Belgian block (cobbled streets).
//        Bridge deck tops are road.
// UV2.y: structures on the hand-made bridges carry palette + 8 * flags (the
//        bridge's colors: 1 Brooklyn, 2 Manhattan, 3 Hell Gate, 4 High Bridge;
//        flags 1 lattice: steel painted as an open truss, its UV.y 0..1 up
//        the band; 2 floodlit at night; 4 ballast: a track bed without
//        ties; 8 riveted: rows of rivets on the steel, and stiffeners on
//        plates); pavers' and Belgian blocks' direction: the angle (radians, in
//        UV space) their rows follow; shrubs' height above the ground (m)
//        (tools/citygen/ground_details.py); 0 everywhere else.
// UV: world x/z on flat ground; (meters along, meters up) on walls; walkways
//     and track beds (meters along, meters across; a track's from its middle).
// Parks, yards and marshes under trees (the citywide canopy map, see
// CityStreamer) read as woods seen from above past where the tree props
// draw, so wooded parks don't end where the near tiles do: round crowns in
// the trees' own tones, each bulging (its normal leans out, so the sun lights
// one side), dark gaps between them, stands of lighter and darker trees, and
// at a slant the ground behind trees hidden by them (from Top of the Rock,
// Central Park's canopy closes over most of its lawns); up close, just the
// trees' shade. Out there the woods' clumps of crowns (tiles' props, drawn
// by tree.gdshader) stand over them, and over wooded paths and lots.
// Lighting is the shared toon model (toon.gdshaderinc). At night (see
// shaders/night.gdshaderinc) street lights' pools light the ground near the
// camera; further out streets and sidewalks get the lamps' average glow, so
// the street grid glows from the air; bridges' main cables carry strings of
// lights; and Times Square's screens tint the streets around them.
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
const int STEEL = 14;
const int WALKWAY = 15;
const int RAIL = 16;
const int SHRUBS = 20;
const int PAVERS = 21;
const int COBBLES = 22;
const int BROOKLYN = 1;
const int HIGH_BRIDGE = 4;
const int LATTICE = 1;
const int FLOODLIT = 2;
const int BALLAST = 4;
const int RIVETS = 8;

// The hand-made bridges' palettes (sRGB), by UV2.y % 8: none (the els'
// weathered green-gray steel, tools/citygen/els.py), Brooklyn (Brooklyn
// Bridge Tan steel and cables gone gray-tan, buff granite towers and
// limestone anchorages, a promenade of weathered gray-brown planks),
// Manhattan (blue-gray steel, gray granite, gray cables), Hell Gate (Hell
// Gate Red, light granite), High Bridge (gray steel, weathered granite, brick
// walk). Toon light and tone mapping saturate them further in shade, so the
// paints are muted here (docs/REFERENCE.md).
const vec3 STEEL_COLORS[5] = vec3[](vec3(0.45, 0.49, 0.48), vec3(0.57, 0.55, 0.52), vec3(0.4, 0.48, 0.56),
		vec3(0.58, 0.23, 0.2), vec3(0.44, 0.49, 0.47));
const vec3 STONE_COLORS[5] = vec3[](vec3(0.76, 0.68, 0.53), vec3(0.71, 0.67, 0.6), vec3(0.68, 0.65, 0.61),
		vec3(0.72, 0.7, 0.65), vec3(0.62, 0.58, 0.52));
const vec3 CABLE_COLORS[5] = vec3[](vec3(0.8, 0.82, 0.85), vec3(0.5, 0.47, 0.44), vec3(0.56, 0.6, 0.64),
		vec3(0.5, 0.22, 0.2), vec3(0.44, 0.49, 0.47));
const vec3 WALKWAY_COLORS[5] = vec3[](vec3(0.55, 0.42, 0.3), vec3(0.52, 0.49, 0.45), vec3(0.55, 0.55, 0.52),
		vec3(0.5, 0.5, 0.48), vec3(0.6, 0.33, 0.25));
// A truss panel's length (m) per palette, for lattice-painted steel (the
// els': their girders' lattice, and the bracing under their tracks).
const float TRUSS_PANELS[5] = float[](2.4, 5.54, 7.5, 12.9, 7.0);

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
// The tree canopy map: how much of each square is under trees (0..1, a
// single channel, not a color), and the world x/z rectangle it covers
// (left, top, width, height in meters), set by CityStreamer once it loads.
uniform sampler2D canopy : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 canopy_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Woods seen from afar: round crowns on a jittered grid woods_crown meters
// apart, each in one of the trees' tones (shaders/tree.gdshader's FOLIAGE,
// in the shares tools/citygen/props.py gives canopy trees) times
// woods_albedo (crowns shade each other), with dark gaps (woods_gap)
// between them. Each crown's normal bulges by woods_bump, so the sun lights
// one side and leaves the other in shade, as on the trees; once crowns are a
// few pixels they calm to their average, darkened by woods_far_shade (the
// shaded sides a flat surface no longer has).
uniform float woods_albedo = 0.85;
uniform vec3 woods_gap : source_color = vec3(0.10, 0.19, 0.08);
uniform float woods_bump = 1.1;
uniform float woods_far_shade = 0.5;
// Crowns' spacing in the woods pattern, and the size of stands of lighter
// and darker trees (m).
uniform float woods_crown = 8.0;
uniform float woods_stand = 70.0;
// From these distances (m) woods go from the trees' shade on the grass to
// the full woods pattern; the tree props shrink away between 650 and 850.
uniform vec2 woods_distance = vec2(450.0, 800.0);
// Seen at a slant, trees hide the ground behind them: a wood's crowns (about
// woods_height m tall) cover the ground up to woods_height / tan(the view's
// angle down) beyond them, at most woods_reach m (so from Top of the Rock
// Central Park's lawns mostly disappear behind its trees, as they do).
uniform float woods_height = 12.0;
uniform float woods_reach = 220.0;
// How much darker (and a touch cooler) the grass in the trees' shade is, up close.
uniform float woods_shade : hint_range(0.0, 1.0) = 0.25;
// Sidewalk flags: size (m) and the street grid's angle (Manhattan's grid
// runs 29 degrees east of true north), so the joints line up with the curbs.
uniform float paving_size = 1.5;
uniform float paving_angle_degrees = 29.0;
// Night: the street lights' average light on streets and sidewalks out past
// the light map (linear, like the map's light times street_light_strength).
uniform vec3 street_light_average = vec3(0.16, 0.11, 0.06);
// Street light also shines off the ground a little whatever its color (a
// sheen), so pools read on dark asphalt too.
uniform float street_light_sheen = 0.04;
// Bridges' necklace lights along the main cables: spacing (m), color, glow.
uniform float cable_light_spacing = 4.0;
uniform vec3 cable_light_color : source_color = vec3(1.0, 0.92, 0.75);
uniform float cable_light_glow = 6.0;
// Times Square's screens light the streets and sidewalks around them at
// night, in slowly drifting colors: over its sign district (as in
// tools/citygen/props.py: meters along and across Manhattan's avenues from
// 46th Street and Broadway), fading out over sign_glow_fade meters around it.
uniform vec2 sign_district_along = vec2(-330.0, 420.0);
uniform vec2 sign_district_across = vec2(-120.0, 110.0);
uniform float sign_glow_fade = 60.0;
uniform float sign_glow_strength = 0.85;
// Ground details (tools/citygen/ground_details.py). Shrub beds: leafy
// clumps about shrub_clump meters across, each bulging by shrub_bump (the
// sun lights one side), in greens that change along the bed, with flowers
// in some stretches.
uniform vec3 shrubs_color : source_color = vec3(0.25, 0.42, 0.18);
uniform float shrub_clump = 0.55;
uniform float shrub_bump = 0.9;
// Pavers in pedestrian plazas: dark gray concrete (a touch warm, so they stay
// gray in the sky's blue light in shade), paver_size meters (along and across
// their rows), in running bond along the plaza.
uniform vec3 pavers_color : source_color = vec3(0.45, 0.43, 0.41);
uniform vec2 paver_size = vec2(0.6, 0.3);
// Belgian block: granite setts cobble_size meters (across the street, along
// it), in courses from curb to curb, with asphalt patches where the street
// was dug up.
uniform vec3 cobbles_color : source_color = vec3(0.45, 0.42, 0.39);
uniform vec2 cobble_size = vec2(0.3, 0.17);
// Floodlit structures at night (the Brooklyn Bridge's towers, the Manhattan
// Bridge's, the High Bridge's arches): light color and strength.
uniform vec3 floodlight_color : source_color = vec3(1.0, 0.88, 0.7);
uniform float floodlight_strength = 1.3;
// Lattice-painted steel: how dark the gaps between the members read (the
// shade inside a deck seen through its truss).
uniform float truss_gap_shade = 0.32;

// The screens' light (linear, before city_lights) on flat ground at world x/z.
vec3 sign_glow(vec2 xz) {
	// Godot's x is east and z south; the avenues run 29 degrees east of north.
	vec2 m = vec2(0.485 * xz.x - 0.875 * xz.y, 0.875 * xz.x + 0.485 * xz.y);
	vec2 lo = vec2(sign_district_along.x, sign_district_across.x);
	vec2 hi = vec2(sign_district_along.y, sign_district_across.y);
	float outside = length(max(max(lo - m, m - hi), 0.0));
	float amount = 1.0 - smoothstep(0.0, sign_glow_fade, outside);
	if (amount <= 0.0) {
		return vec3(0.0);
	}
	// Soft pink and cyan patches drifting across the street, with amber
	// washes, over the white of all the screens together.
	float n = value_noise(xz * 0.03 + vec2(TIME * 0.07, -TIME * 0.05));
	float n2 = value_noise(xz * 0.011 - vec2(TIME * 0.03, 0.0) + 17.0);
	vec3 color = mix(srgb(vec3(1.0, 0.35, 0.68)), srgb(vec3(0.3, 0.72, 1.0)), smoothstep(0.2, 0.8, n));
	color = mix(color, srgb(vec3(1.0, 0.72, 0.3)), 0.6 * smoothstep(0.45, 0.85, n2));
	return mix(color, vec3(0.9), 0.2) * (amount * sign_glow_strength);
}

vec3 base_color(int kind, int palette) {
	if (palette > 0 || (kind >= STEEL && kind < SHRUBS)) {
		// The hand-made bridges' structures.
		int p = clamp(palette, 0, 4);
		if (kind == STEEL) {
			return srgb(STEEL_COLORS[p]);
		}
		if (kind == STONE) {
			return srgb(STONE_COLORS[p]);
		}
		if (kind == CABLE) {
			return srgb(CABLE_COLORS[p]);
		}
		if (kind == WALKWAY) {
			return srgb(WALKWAY_COLORS[p]);
		}
		if (kind == RAIL) {
			return srgb(vec3(0.45, 0.42, 0.39));  // ballast
		}
		if (kind == CONCRETE) {
			return srgb(STEEL_COLORS[p]) * 0.7;  // floors among the steel
		}
	}
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
	if (kind == SHRUBS) {
		return shrubs_color;
	}
	if (kind == PAVERS) {
		return pavers_color;
	}
	if (kind == COBBLES) {
		return cobbles_color;
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

// Blocks `size` meters (along a row, across rows) in rows along x of q (in
// meters), each row shifted by half a block or, with `jitter`, more at
// random; joints `joint` meters wide. Returns (how much joint 0..1, the
// block's tone -1..1), both fading out as blocks get smaller than a few pixels.
vec2 courses(vec2 q, vec2 size, float joint, float pixel, float jitter) {
	float row = floor(q.y / size.y);
	float x = q.x / size.x + mix(0.5 * mod(row, 2.0), hash(vec2(row, 7.1)), jitter);
	float detail = visible(size.y, pixel);
	float joints = max(centered_stripes(q.y / size.y, joint / size.y, pixel / size.y),
			centered_stripes(x, joint / size.x, pixel / size.x));
	return vec2(joints, (hash(vec2(floor(x), row)) - 0.5) * 2.0) * detail;
}

// Shrub beds on planted medians: leafy clumps bulging out of the hedge, dark
// between them and toward the ground, with flowers in some stretches.
// `rise` is the height above the ground; `face` the surface's own (flat)
// world normal; `normal` (world) bulges with the clumps.
vec3 shrubs(vec2 p, float rise, vec3 face, vec3 color, inout vec3 normal) {
	// Up a hedge's steep side, the leaves wrap around: in as far as it rises.
	float steep = smoothstep(0.3, 0.6, length(face.xz));
	p -= normalize(face.xz + vec2(1e-5, 0.0)) * (rise * steep);
	vec2 footprint = max(fwidth(p), vec2(1e-4));
	float pixel = sqrt(footprint.x * footprint.y);
	// Boxwood, yew and privet greens, changing along the bed; darker low down.
	vec3 leaf = color * mix(vec3(0.85, 0.95, 0.95), vec3(1.1, 1.06, 0.85), value_noise(p * 0.11 + 5.0));
	leaf *= mix(0.55, 1.0, smoothstep(0.0, 0.45, rise));
	float detail = visible(shrub_clump, pixel);
	if (detail <= 0.0) {
		return leaf * 0.8;
	}
	vec2 q = p / shrub_clump;
	vec2 home = floor(q);
	float nearest = 9.0;
	vec2 offset = vec2(0.0);
	float pick = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = home + vec2(float(i), float(j));
			vec2 center = cell + 0.5 + (vec2(hash(cell + 3.7), hash(cell + 11.9)) - 0.5) * 0.8;
			vec2 d = (q - center) / mix(0.6, 0.85, hash(cell + 29.3));
			float r = length(d);
			if (r < nearest) {
				nearest = r;
				offset = d;
				pick = hash(cell + 51.7);
			}
		}
	}
	float inside = 1.0 - smoothstep(0.7, 1.0, nearest);
	vec3 c = mix(leaf * 0.45, leaf * mix(0.85, 1.15, pick), inside);
	// A speckle of leaves catching the light.
	c *= 1.0 + (hash(floor(p * 9.0)) - 0.5) * 0.3 * visible(0.11, pixel);
	// Flowers in some stretches: dots of one color on the clumps.
	float flowering = smoothstep(0.58, 0.68, value_noise(p / 9.0 + 21.0));
	if (flowering > 0.0) {
		vec2 cell = floor(p * 4.0);
		vec2 spot = fract(p * 4.0) - 0.5 - (vec2(hash(cell + 1.7), hash(cell + 5.1)) - 0.5) * 0.5;
		float bloom = (1.0 - smoothstep(0.12, 0.3, length(spot))) * step(0.45, hash(cell + 9.3)) * inside;
		float which = value_noise(p / 9.0 + 40.0);
		vec3 flower = which < 0.35 ? vec3(0.95, 0.42, 0.6) : (which < 0.5 ? vec3(0.9, 0.2, 0.18)
				: (which < 0.65 ? vec3(0.98, 0.85, 0.3) : vec3(0.95, 0.95, 0.92)));
		c = mix(c, srgb(flower), bloom * flowering * visible(0.25, pixel));
	}
	normal = normalize(normal + vec3(offset.x, 0.0, offset.y) * (shrub_bump * inside * detail));
	return mix(leaf * 0.8, c, detail);
}

// The ground details' kinds (shrubs, pavers, Belgian block); `extra`
// (UV2.y) is shrubs' height, or the direction pavers' rows and the cobbled
// street run. `face` is the surface's own world normal.
vec3 ground_detail(int kind, vec2 p, float extra, vec2 footprint, vec3 face, vec3 color, inout vec3 normal) {
	if (kind == SHRUBS) {
		return shrubs(p, extra, face, color, normal);
	}
	float angle = extra;
	float pixel = max(footprint.x, footprint.y);
	vec2 d = vec2(cos(angle), sin(angle));
	vec2 q = vec2(dot(p, d), dot(p, vec2(-d.y, d.x)));  // meters along and across the rows
	if (kind == PAVERS) {
		vec2 b = courses(q, paver_size, 0.012, pixel, 0.0);
		return color * (1.0 + 0.07 * b.y) * (1.0 - 0.3 * b.x);
	}
	// Belgian block: courses across the street, one after another along it;
	// setts a little different in gray, pink and brown.
	vec2 b = courses(q.yx, cobble_size, 0.035, pixel, 0.8);
	float tint = hash(floor(vec2(q.y / cobble_size.x, q.x / cobble_size.y)) + 13.1) * visible(cobble_size.y, pixel);
	vec3 setts = color * mix(vec3(1.0), mix(vec3(1.06, 0.98, 0.94), vec3(0.94, 0.98, 1.04), tint), 0.8)
			* (1.0 + 0.13 * b.y) * (1.0 - 0.5 * b.x);
	float patches = smoothstep(0.64, 0.68, value_noise(p * 0.06 + 3.7));
	return mix(setts, road_color * (1.0 + (value_noise(p * 4.0) - 0.5) * 0.1 * visible(0.25, pixel)), patches);
}

// The trees' foliage tones (shaders/tree.gdshader's FOLIAGE and CONIFER, in
// sRGB): mid, dark, light, conifer, red; and the share of a wood's crowns in
// each (props.py's CANOPY_TONES, with conifers' patches).
const vec3 WOODS_TONES[5] = vec3[](vec3(0.40, 0.47, 0.32), vec3(0.31, 0.40, 0.26), vec3(0.49, 0.56, 0.34),
		vec3(0.24, 0.34, 0.29), vec3(0.38, 0.24, 0.26));
const float WOODS_SHARES[5] = float[](0.5, 0.28, 0.11, 0.08, 0.03);

// Parks, yards and marshes under trees: shade up close, woods seen from
// above further away. `cover` is the canopy map's 0..1 at canopy_uv;
// `ray` runs from the camera to here (world); canopy_dx and canopy_dy are
// canopy_uv's screen derivatives; `normal` (world) bulges with the crowns.
vec3 woods(vec3 color, vec2 p, vec2 footprint, float cover, vec2 canopy_uv, vec2 canopy_dx, vec2 canopy_dy,
		vec3 ray, inout vec3 normal) {
	float far = smoothstep(woods_distance.x, woods_distance.y, length(ray));
	float amount = smoothstep(0.1, 0.7, cover);
	float seen = amount;
	if (far > 0.0) {
		// The most canopy toward the camera within the crowns' reach (see
		// woods_height), at two points along the way...
		float across = max(length(ray.xz), 1e-3);
		float reach = min(woods_height * across / max(-ray.y, 1.0), woods_reach);
		vec2 back = -ray.xz * (reach / across) / canopy_rect.zw;
		float hidden = max(textureGrad(canopy, canopy_uv + back * 0.45, canopy_dx, canopy_dy).r,
				textureGrad(canopy, canopy_uv + back, canopy_dx, canopy_dy).r);
		// ...and a line of sight skimming `reach` meters over ground that's
		// that much under crowns (a crown about every 2 woods_crown) gets
		// through to the ground (1 - cover) to the power of the crowns it passes.
		float crowns_passed = 1.0 + far * reach / (2.0 * woods_crown);
		seen = smoothstep(0.1, 0.7, 1.0 - pow(1.0 - mix(cover, max(cover, hidden), far), crowns_passed));
	}
	if (seen <= 0.0) {
		return color;
	}
	vec3 shaded = color * (1.0 - woods_shade) * vec3(0.9, 1.0, 1.02);
	color = mix(color, shaded, amount);
	if (far <= 0.0) {
		return color;
	}
	vec3 average = vec3(0.0);
	for (int k = 0; k < 5; k++) {
		average += srgb(WOODS_TONES[k]) * WOODS_SHARES[k];
	}
	average = mix(woods_gap, average * woods_albedo, 0.8);
	// Stands of lighter and darker trees, big enough to show from anywhere.
	float stand = value_noise(p / woods_stand + 3.1) * 0.6 + value_noise(p / (woods_stand * 0.37) + 9.4) * 0.4;
	vec3 stand_tint = mix(vec3(0.74, 0.78, 0.9), vec3(1.2, 1.12, 0.84), smoothstep(0.3, 0.7, stand));
	vec3 woods_color = average * stand_tint * woods_far_shade;
	vec3 bulge = vec3(0.0, 1.0, 0.0);
	// Crowns stay while they're a few pixels across, even where the ground is
	// seen at a slant and they're squeezed thin (their edges then blur over
	// the squeezed pixel instead of flickering).
	float detail = visible(woods_crown, sqrt(footprint.x * footprint.y));
	if (detail > 0.0) {
		// The nearest crown, measured in crown radii, so big crowns take more ground.
		vec2 q = p / woods_crown;
		vec2 home = floor(q);
		float nearest = 9.0;
		vec2 offset = vec2(0.0);
		vec3 pick = vec3(0.0);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 cell = home + vec2(float(i), float(j));
				vec2 center = cell + 0.5 + (vec2(hash(cell), hash(cell + 17.3)) - 0.5) * 0.7;
				float radius = mix(0.5, 0.72, hash(cell + 41.9));
				vec2 d = (q - center) / radius;
				float r = length(d);
				if (r < nearest) {
					nearest = r;
					offset = d;
					pick = vec3(hash(cell + 63.1), hash(cell + 87.7), radius);
				}
			}
		}
		int tone = 0;
		float share = 0.0;
		for (int k = 0; k < 4; k++) {
			share += WOODS_SHARES[k];
			tone = pick.x >= share ? k + 1 : tone;
		}
		vec3 crown = srgb(WOODS_TONES[tone]) * stand_tint * (woods_albedo * mix(0.85, 1.12, pick.y));
		float blur = max(footprint.x, footprint.y) / (woods_crown * pick.z);
		float inside = 1.0 - smoothstep(1.0 - max(0.15, blur), 1.0, nearest);
		woods_color = mix(woods_color, mix(woods_gap, crown, inside), detail);
		// A dome: its normal leans out toward the crown's edge.
		vec3 dome = vec3(offset.x * woods_bump, sqrt(max(1.0 - nearest * nearest, 0.0)) + 0.1, offset.y * woods_bump);
		bulge = normalize(mix(bulge, normalize(dome), detail * inside));
	}
	float woods_amount = seen * far;
	normal = normalize(mix(normal, bulge, woods_amount));
	return mix(color, woods_color, woods_amount);
}

// The hand-made bridges' flat structures: walkways (planks across a wooden
// promenade, brick paving, or concrete slabs) and track beds (ballast, ties, rails). `p` is
// (meters along, meters across), world x/z on ballast-only beds.
vec3 structure_flat(int kind, int palette, int flags, vec2 p, vec2 footprint, vec3 color) {
	float pixel = max(footprint.x, footprint.y);
	if (kind == WALKWAY) {
		if (palette == HIGH_BRIDGE) {
			// Brick pavers in pairs, alternating direction (0.2 m squares).
			vec2 q = p / 0.2;
			vec2 cell = floor(q);
			float joints = max(centered_stripes(q.x, 0.08, footprint.x / 0.2), centered_stripes(q.y, 0.08, footprint.y / 0.2));
			float split = mod(cell.x + cell.y, 2.0) < 0.5 ? centered_stripes(q.y + 0.5, 0.08, footprint.y / 0.2)
					: centered_stripes(q.x + 0.5, 0.08, footprint.x / 0.2);
			float detail = visible(0.1, pixel);
			float tint = (hash(floor(q * vec2(1.0, 2.0))) - 0.5) * 0.16 * detail;
			return color * (1.0 + tint) * (1.0 - 0.35 * max(joints, split) * detail);
		}
		if (palette != BROOKLYN) {
			// Concrete slabs with joints across, every 3 m.
			float slab = p.x / 3.0;
			float joints = centered_stripes(slab, 0.01, footprint.x / 3.0);
			float tint = (hash(vec2(floor(slab), 9.1)) - 0.5) * 0.08 * visible(3.0, pixel);
			return color * (1.0 + tint) * (1.0 - 0.3 * joints);
		}
		// Boards laid across, each a little different, dark seams between.
		float board = p.x / 0.15;
		float seams = centered_stripes(board, 0.1, footprint.x / 0.15);
		float detail = visible(0.15, pixel);
		float tint = (hash(vec2(floor(board), 3.7)) - 0.5) * 0.22 * detail;
		float worn = value_noise(p * vec2(0.3, 1.5)) * 0.12;
		return color * (1.0 + tint - worn) * (1.0 - 0.45 * seams * detail);
	}
	if (kind == RAIL) {
		float detail = visible(0.6, pixel);
		vec3 ballast = color * (0.85 + 0.3 * value_noise(p * 7.0) * visible(0.15, pixel) + 0.1 * value_noise(p * 0.4));
		if ((flags & BALLAST) != 0) {
			return ballast;
		}
		// Ties every 0.6 m, standard gauge rails (1.435 m) on them.
		float ties = stripes(p.x / 0.6 + 0.2, 0.4, footprint.x / 0.6) * band(abs(p.y), 0.0, 1.3, footprint.y);
		vec3 bed = mix(ballast, srgb(vec3(0.33, 0.26, 0.2)), ties * mix(0.4, 1.0, detail));
		float rails = band(abs(p.y), 0.68, 0.78, footprint.y);
		return mix(bed, srgb(vec3(0.62, 0.62, 0.64)), rails * mix(0.3, 1.0, visible(0.1, footprint.y)));
	}
	return color;
}

// Painted steel on walls: plain plates with faint seams, or (lattice) an open
// truss's chords, posts and crossed diagonals over the deep shade behind,
// along a band whose UV.y runs 0..1 from its foot to its top. Riveted steel
// (the els') has rows of rivet heads catching the light: along the middle of
// a lattice's chords, or on plates down stiffeners every 1.5 m (a shadow
// beside each) and in a row over each seam.
vec3 steel_wall(int palette, int flags, vec2 p, vec2 footprint, vec3 color) {
	// Rivet heads every 0.15 m along a row.
	float heads = centered_stripes(p.x / 0.15, 0.4, footprint.x / 0.15);
	float rivets = 0.0;
	float shade;
	if ((flags & LATTICE) != 0) {
		float panel = TRUSS_PANELS[clamp(palette, 0, 4)];
		float q = p.x / panel;
		float fq = footprint.x / panel;
		float r = p.y;
		float chords = max(band(r, -1.0, 0.14, footprint.y), band(r, 0.86, 2.0, footprint.y));
		float posts = centered_stripes(q, 0.07, fq);
		float f = fract(q);
		float d = min(abs(r - f), abs(r - (1.0 - f)));
		float aa = max(max(fq, footprint.y), 1e-4);
		float diagonals = 1.0 - smoothstep(0.05 - aa, 0.05 + aa, d);
		float member = max(max(chords, posts), diagonals);
		// Too small to see: the average of steel and shade.
		member = mix(0.5, member, visible(panel * 0.3, footprint.x));
		shade = mix(truss_gap_shade, 1.0, member);
		rivets = heads * max(band(r, 0.05, 0.09, footprint.y), band(r, 0.91, 0.95, footprint.y));
	} else {
		float seams = max(centered_stripes(p.x / 3.0, 0.015, footprint.x / 3.0), centered_stripes(p.y / 1.5, 0.02, footprint.y / 1.5));
		shade = 1.0 - 0.12 * seams;
		if ((flags & RIVETS) != 0) {
			float stiffener = centered_stripes(p.x / 1.5, 0.08, footprint.x / 1.5);
			float shadow = centered_stripes(p.x / 1.5 - 0.055, 0.03, footprint.x / 1.5);
			shade *= 1.0 + 0.1 * stiffener - 0.35 * shadow * visible(0.05, footprint.x);
			float down = centered_stripes(p.x / 1.5, 0.025, footprint.x / 1.5) * centered_stripes(p.y / 0.15, 0.4, footprint.y / 0.15);
			rivets = max(down, centered_stripes(p.y / 1.5 - 0.07, 0.03, footprint.y / 1.5) * heads);
		}
	}
	if ((flags & RIVETS) != 0) {
		shade *= 1.0 + 0.35 * rivets * visible(0.06, max(footprint.x, footprint.y));
	}
	return color * shade;
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
	// The woods' crowns bulge the normal the light sees.
	vec3 shading_normal = world_normal;
	vec3 photo = aerial_albedo(aerial_uv);
	// Sampled here, outside any branch, so its mipmaps get good derivatives.
	vec2 canopy_uv = (UV - canopy_rect.xy) / canopy_rect.zw;
	float cover = texture(canopy, canopy_uv).r;
	vec2 canopy_dx = dFdx(canopy_uv);
	vec2 canopy_dy = dFdy(canopy_uv);

	// Broad, soft variation so large areas don't look flat.
	float variation = value_noise(UV * 0.04) * 0.6 + value_noise(UV * 0.31) * 0.4;
	// Bridge structures' palette and flags (ground details use UV2.y otherwise).
	int structure_code = kind >= SHRUBS ? 0 : int(UV2.y + 0.5);
	int palette = structure_code % 8;
	int structure_flags = structure_code / 8;
	vec3 color = base_color(kind, palette) * mix(0.92, 1.06, variation);
	if (kind >= SHRUBS) {
		// Ground details, on any slope (shrubs mound up).
		vec3 face = normalize((INV_VIEW_MATRIX * vec4(cross(dFdx(VERTEX), dFdy(VERTEX)), 0.0)).xyz);
		face *= sign(dot(face, world_normal) + 1e-5);  // the surface's own normal, out of it
		color = ground_detail(kind, UV, UV2.y, footprint, face, color, shading_normal);
		NORMAL = normalize((VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz);
	} else if (kind >= STEEL) {
		color = kind == STEEL ? steel_wall(palette, structure_flags, UV, footprint, color)
				: structure_flat(kind, palette, structure_flags, UV, footprint, color);
	} else if (world_normal.y > 0.7) {
		color = flat_ground(kind, UV, footprint, color);
		if (kind == PARK || kind == YARD || kind == MARSH) {
			vec3 ray = (INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz;
			color = woods(color, UV, footprint, cover, canopy_uv, canopy_dx, canopy_dy, ray, shading_normal);
			if (shading_normal != world_normal) {
				NORMAL = normalize((VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz);
			}
		}
	} else {
		color = wall_surface(kind, UV, footprint, color);
	}

	if (kind == PARK) {
		float detail = clamp(dot(photo, vec3(0.2126, 0.7152, 0.0722)) / 0.08, 0.25, 1.2);
		photo = mix(photo, park_color * detail, park_greening);
	}
	bool photographed = (kind <= MARSH && kind != SEAWALL) || kind == YARD || kind >= SHRUBS;
	float far_enough = smoothstep(aerial_near_fade.x, aerial_near_fade.y, length(VERTEX));
	ALBEDO = toon_night_albedo(mix(color, photo, photographed ? aerial_amount(aerial_uv) * far_enough : 0.0));
	EMISSION = ALBEDO * toon_ambient(shading_normal, 1.0);
	toon_glint = kind == CABLE ? 0.3 : (kind == STEEL ? 0.12 : 0.0);

	if (city_lights > 0.0) {
		float distance_to_camera = length(VERTEX);
		vec3 scene_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 lamps = street_light_at(scene_position.xz, distance_to_camera);
		bool street = kind == ROAD || kind == PAVEMENT || kind == PAVERS || kind == COBBLES;
		if (street) {
			lamps += street_light_average * street_light_far(distance_to_camera);
		}
		// Walls (curbs, seawalls, bridges' sides) catch less of it, and no sheen.
		bool level = world_normal.y > 0.7;
		EMISSION += (level ? ALBEDO + street_light_sheen : ALBEDO * 0.6) * lamps * city_lights;
		if (level && street) {
			// Times Square's screens (flat ground's UV is its world x/z).
			EMISSION += (ALBEDO + street_light_sheen) * sign_glow(UV) * city_lights;
		}
		if (kind == CABLE && UV.y < 1.01) {
			// A main cable (its four faces each run 0..1 across): bulbs along it,
			// down the middle of each face, a glowing line in the distance.
			float bulbs = centered_stripes(UV.x / cable_light_spacing, 0.12, footprint.x / cable_light_spacing)
					* band(UV.y, 0.3, 0.7, footprint.y);
			EMISSION += cable_light_color * (bulbs * cable_light_glow * city_lights);
		}
		if ((structure_flags & FLOODLIT) != 0) {
			EMISSION += ALBEDO * floodlight_color * (floodlight_strength * city_lights);
		}
	}
}
