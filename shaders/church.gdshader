// Churches (tools/citygen/churches.py): houses of worship in stone or brick,
// Gothic (pointed arches), Romanesque (round arches) or modern (tall narrow
// windows). Walls have no floors: tall windows of stained glass between
// buttresses, in stages up very tall walls, under a corbel table at the
// eaves; a gable facing the street has the portal (wooden doors in a deep
// arch) and a rose window; towers rise in stages to a belfry with louvered
// openings, some with a clock that keeps the game's time. Roofs and spires
// are slate, some copper or stone. At night some churches' windows glow.
// Each tile's churches come in a surface of their own
// (CityTileDecoder.SURFACE_CHURCHES), so this small shader adds nothing to
// building.gdshader's compile time (see "Shader compile time" in
// docs/ROADMAP.md): it only sets numbers per part and calls each heavy
// helper (the masonry, an opening's arch, the stained glass) once.
//
// Per vertex (see churches.py):
//   UV    walls: (m from the face's middle, to the right seen from outside;
//         m above the church's ground); pitched roofs: (m along the eaves,
//         m up the slope); flat roofs: world x/z; spires and pinnacles: (m
//         from the middle of the face's base, m up the slope)
//   UV2.x part + 16 * flags + 1024 * the face's width in dm
//   UV2.y the wall's top in dm (gable ends: the eaves; spires: the slope's
//         length) + the church's seed (0..0.999)
// Flags: FRONT (1, the wall faces a street), the kind * 2, the material * 8.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts, kinds and materials, as churches.py numbers them.
const int WALL = 0;
const int GABLE = 1;
const int TOWER = 2;
const int ROOF = 3;
const int FLAT_ROOF = 4;
const int SPIRE = 5;
const int PINNACLE = 6;
const int FRONT = 1;
const int GOTHIC = 1;
const int ROMANESQUE = 2;
const int MODERN = 3;
const int BROWNSTONE = 0;
const int GRAY_STONE = 1;
const int LIMESTONE = 2;
const int RED_BRICK = 3;
const int BUFF_BRICK = 4;
// What fills an opening.
const int GLASS = 0;
const int LOUVERS = 1;
const int DOORS = 2;

// Colors, in sRGB: each material's range of shades (weathered: stone in
// the city is grayer than in the quarry), trim stone on brick, mortar, roofs.
const vec3 BROWNSTONE_LOW = vec3(0.46, 0.40, 0.36);
const vec3 BROWNSTONE_HIGH = vec3(0.53, 0.46, 0.41);
const vec3 GRAY_STONE_LOW = vec3(0.55, 0.54, 0.51);
const vec3 GRAY_STONE_HIGH = vec3(0.64, 0.61, 0.56);
const vec3 LIMESTONE_LOW = vec3(0.68, 0.66, 0.61);
const vec3 LIMESTONE_HIGH = vec3(0.76, 0.73, 0.67);
const vec3 RED_BRICK_LOW = vec3(0.54, 0.42, 0.39);
const vec3 RED_BRICK_HIGH = vec3(0.62, 0.48, 0.44);
const vec3 BUFF_BRICK_LOW = vec3(0.67, 0.60, 0.50);
const vec3 BUFF_BRICK_HIGH = vec3(0.74, 0.67, 0.56);
const vec3 TRIM_STONE = vec3(0.76, 0.73, 0.67);
const vec3 MORTAR = vec3(0.78, 0.77, 0.73);
const vec3 SLATE_LOW = vec3(0.29, 0.31, 0.35);
const vec3 SLATE_HIGH = vec3(0.37, 0.38, 0.41);
const vec3 COPPER = vec3(0.47, 0.62, 0.56);
const vec3 TILE_RED = vec3(0.52, 0.34, 0.29);
const vec3 SHINGLE_GRAY = vec3(0.38, 0.36, 0.34);
const vec3 ROOF_TAR = vec3(0.30, 0.29, 0.29);
const vec3 LEAD = vec3(0.10, 0.10, 0.11);
const vec3 LOUVER = vec3(0.30, 0.30, 0.31);
const vec3 CLOCK_FACE = vec3(0.90, 0.88, 0.80);
const vec3 IRON = vec3(0.12, 0.13, 0.13);
// Stained glass seen from outside by day: dark, with muted jewel tints,
// behind protective glazing that catches the sky.
const vec3 GLASS_DARK = vec3(0.21, 0.23, 0.28);
const vec3 GLASS_BLUE = vec3(0.24, 0.30, 0.44);
const vec3 GLASS_RED = vec3(0.42, 0.24, 0.24);
const vec3 GLASS_AMBER = vec3(0.47, 0.41, 0.26);
const vec3 GLAZING = vec3(0.55, 0.60, 0.66);
// ... and lit from inside at night.
const vec3 GLASS_LIT = vec3(1.0, 0.72, 0.42);

// Walls darken toward their feet in the street's shade (as building.gdshader's).
uniform float canyon_occlusion : hint_range(0.0, 1.0) = 0.85;
uniform float canyon_height = 25.0;
// Night: how bright lit stained glass is, how far up the walls street lights reach (m).
uniform float glass_glow = 1.2;
uniform vec2 street_light_reach = vec2(3.0, 13.0);

// UV2 decoded in the vertex shader: (part + 16 * flags, width in dm, top in
// dm, seed); one value per face, so not interpolated.
varying flat vec4 church_data;

struct Surface {
	vec3 albedo;
	vec3 emission;
};

// A random number per church (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed * 1024.0 + salt * 3.7, salt * 13.1 + 7.0));
}

// A church's wall color (linear): its shade of the material, picked by r.
vec3 stone_color(int material, float r) {
	vec3 low = material == BROWNSTONE ? BROWNSTONE_LOW : (material == GRAY_STONE ? GRAY_STONE_LOW
			: (material == LIMESTONE ? LIMESTONE_LOW : (material == RED_BRICK ? RED_BRICK_LOW : BUFF_BRICK_LOW)));
	vec3 high = material == BROWNSTONE ? BROWNSTONE_HIGH : (material == GRAY_STONE ? GRAY_STONE_HIGH
			: (material == LIMESTONE ? LIMESTONE_HIGH : (material == RED_BRICK ? RED_BRICK_HIGH : BUFF_BRICK_HIGH)));
	return srgb(mix(low, high, r));
}

// Courses of brick, or blocks of stone (gray stone's rougher and more varied).
vec3 masonry(vec3 color, int material, vec2 p, vec2 fp) {
	bool brick = material >= RED_BRICK;
	vec2 block = brick ? vec2(0.2, 0.076) : (material == GRAY_STONE ? vec2(0.8, 0.42) : vec2(1.1, 0.52));
	float detail = visible(block.y, max(fp.x, fp.y));
	float row = p.y / block.y;
	float shift = mod(floor(row), 2.0) * (0.5 + 0.2 * hash(vec2(floor(row), 3.1))) * detail;
	float joints = max(stripes(row, brick ? 0.16 : 0.05, fp.y / block.y),
			stripes(p.x / block.x + shift, brick ? 0.08 : 0.03, fp.x / block.x) * detail);
	float tint = (hash(vec2(floor(p.x / block.x + shift), floor(row))) - 0.5) * (material == GRAY_STONE ? 0.22 : 0.1) * detail;
	color *= 1.0 + tint;
	return brick ? mix(color, mix(color, srgb(MORTAR), 0.45), joints * 0.55) : color * (1.0 - 0.3 * joints);
}

// How far inside an arched opening `w` wide a point is (m; negative
// outside): from `sill` up, its sides rising to `spring`, then a pointed
// (equilateral) arch, a round one, or (modern) a flat head there. q is m
// from the opening's middle, m up.
float arch_inset(vec2 q, float w, float sill, float spring, int kind) {
	float head = kind == GOTHIC ? w - max(length(q - vec2(-0.5 * w, spring)), length(q - vec2(0.5 * w, spring)))
			: (kind == ROMANESQUE ? 0.5 * w - length(q - vec2(0.0, spring)) : spring - q.y);
	return min(q.y < spring ? 0.5 * w - abs(q.x) : head, q.y - sill);
}

// Stained glass at q (m), lead lines between small panes of muted color.
vec3 stained_glass(vec2 q, vec2 fp, float seed) {
	vec2 pane = vec2(0.32, 0.42);
	vec2 cell = floor(q / pane);
	float h = hash(cell + seed * 37.0);
	vec3 tint = srgb(h < 0.35 ? GLASS_BLUE : (h < 0.55 ? GLASS_RED : (h < 0.7 ? GLASS_AMBER : GLASS_DARK)));
	float detail = visible(pane.x, max(fp.x, fp.y));
	vec3 color = mix(srgb(GLASS_DARK), tint, 0.6 * detail);
	float lead = max(stripes(q.x / pane.x, 0.1, fp.x / pane.x), stripes(q.y / pane.y, 0.08, fp.y / pane.y)) * detail;
	return mix(mix(color, srgb(LEAD), lead * 0.7), srgb(GLAZING), 0.12);
}

// A wall, a gable end or a tower's wall. `wall` is its stone's color,
// `textured` its masonry at p.
Surface church_wall(int part, vec2 p, vec2 fp, float width, float top, int kind, int material, float seed,
		bool front, vec3 wall, vec3 textured) {
	float pixel = max(fp.x, fp.y);
	bool traditional = kind != MODERN;
	float arch = kind == GOTHIC ? 0.87 : (kind == ROMANESQUE ? 0.5 : 0.0);  // an arch's rise, per m of width
	vec3 trim = material >= RED_BRICK ? srgb(TRIM_STONE) : wall * 1.12;
	vec3 color = textured;
	// A stone base course, and the corbel table under the eaves.
	color = mix(color, trim * 0.82, band(p.y, -2.0, 0.6, fp.y));
	float eaves = band(p.y, top - 0.55, 1e4, fp.y) * float(part == WALL && traditional);
	float corbels = stripes(p.x / 0.6, 0.5, fp.x / 0.6) * band(p.y, top - 0.55, top - 0.3, fp.y) * visible(0.3, pixel);
	color = mix(color, trim * (1.0 - 0.45 * corbels), eaves);

	// The opening this pixel belongs to: its middle (m across), width, sill,
	// where its arch springs, and what fills it. Each part only sets these
	// numbers; one arch_inset() below draws whichever it is.
	float ox = 0.0;
	float ow = 0.0;
	float sill = 0.0;
	float spring = 0.0;
	int fill = GLASS;
	float buttress = 0.0;
	float buttress_shadow = 0.0;
	// The portal: in the middle of a street gable or tower, or of a long
	// street wall's middle bay.
	float portal_x = 0.0;
	float portal_width = clamp((part == TOWER ? 0.42 : 0.28) * width, 1.8, 3.4);
	// The clock (half the traditional towers), under the belfry.
	float belfry = clamp(0.2 * top, 3.5, 6.5);
	float clock_radius = min(0.3 * width, 1.3);
	float clock_y = top - belfry - clock_radius - 0.6;
	bool clock = part == TOWER && traditional && width >= 3.0 && rnd(seed, 8.0) < 0.5;
	if (part == WALL) {
		// Tall windows between buttresses, bays fitted to the wall, in stages
		// up a very tall one.
		float count = max(1.0, floor(width / (kind == MODERN ? 2.6 : (kind == GOTHIC ? 4.2 : 3.6)) + 0.5));
		float bay = width / count;
		float u = (p.x + 0.5 * width) / bay;
		ox = (floor(u) + 0.5) * bay - 0.5 * width;
		float stages = max(1.0, floor(top / 13.0 + 0.3));
		float stage_height = top / stages;
		float base = clamp(floor(p.y / stage_height), 0.0, stages - 1.0) * stage_height;
		ow = kind == MODERN ? min(0.8, 0.3 * bay) : min((kind == GOTHIC ? 0.42 : 0.36) * bay, 2.2);
		sill = base + clamp(0.22 * stage_height, 1.6, 3.5);
		// A side door in the middle bay of a long street wall.
		front = front && width > 8.0 && floor(u) == floor(0.5 * count);
		portal_x = ox;
		portal_width = min(0.6 * bay, 2.4);
		sill = front ? max(sill, portal_width * 1.75 + 1.2) : sill;
		float head = base + stage_height - clamp(0.12 * stage_height, 0.8, 2.0);
		spring = head - arch * ow;
		ow *= step(1.6, width) * step(sill + 1.0, spring);
		// Buttresses at the bays' edges, stepping back halfway up.
		float side = (fract(u + 0.5) - 0.5) * bay;  // m from the nearest bay's edge
		float half_width = 0.34 - 0.08 * step(0.5 * top, p.y);
		float below_eaves = band(p.y, -2.0, top - 0.7, fp.y) * float(traditional);
		buttress = band(abs(side), -1.0, half_width, fp.x) * below_eaves;
		buttress_shadow = band(side, half_width, half_width + 0.25, fp.x) * below_eaves;
	} else if (part == GABLE) {
		// Above the portal, a tall window (modern), else the rose window
		// (painted below); buttresses at the corners.
		ow = kind == MODERN ? min(1.0, 0.12 * width) : 0.0;
		sill = (front ? portal_width * 1.75 + 0.4 : 0.0) + 1.2;
		spring = top + 0.15 * width;
		buttress = float(traditional) * band(0.5 * width - abs(p.x), -1.0, 0.45, fp.x);
	} else {
		// A tower: the belfry's louvered openings at the top, a narrow window
		// in each stage under it (and the clock), piers at the corners.
		bool in_belfry = p.y > top - belfry;
		float bay = width / (width < 4.0 ? 1.0 : 2.0);
		float stage = 7.0;
		float base = floor(p.y / stage) * stage;
		ox = in_belfry ? (floor((p.x + 0.5 * width) / bay) + 0.5) * bay - 0.5 * width : 0.0;
		ow = in_belfry ? min(0.5 * bay, 1.6) : min(0.75, 0.2 * width);
		sill = in_belfry ? top - belfry + 0.5 : base + 2.0;
		float head = in_belfry ? top - 0.6 : base + 5.5;
		spring = head - arch * ow;
		fill = in_belfry ? LOUVERS : GLASS;
		ow *= max(step(head, (clock ? clock_y - clock_radius : top - belfry) - 0.4), float(in_belfry));
		buttress = float(traditional && width > 3.0) * band(0.5 * width - abs(p.x), -1.0, 0.45, fp.x);
		// String courses at the belfry's sill and between stages.
		float course = band(p.y, top - belfry - 0.25, top - belfry, fp.y)
				+ stripes(p.y / stage, 0.25 / stage, fp.y / stage) * step(p.y, top - belfry);
		color = mix(color, trim, clamp(course, 0.0, 1.0) * float(traditional));
	}
	float portal_top = min(portal_width * 1.75 + 0.4, max(top * 0.6, 3.0));
	if (front && p.y < portal_top + 0.4 && abs(p.x - portal_x) < portal_width) {
		// Double doors under an arch (a lintel on modern churches).
		ox = portal_x;
		ow = portal_width;
		sill = -2.0;
		spring = portal_top - arch * ow;
		fill = DOORS;
	}
	// Buttresses: lighter, their shadow on the wall beside them.
	color *= 1.0 - 0.3 * buttress_shadow;
	color = mix(color, mix(color, trim, 0.35) * 1.06, buttress);

	// The opening (one arch per pixel), its surround and its reveal's shadow.
	vec2 q = vec2(p.x - ox, p.y);
	float inset = ow > 0.0 ? arch_inset(q, ow, sill, spring, kind) : -1.0;
	float opening = smoothstep(-0.5 * pixel, 0.5 * pixel, inset);
	float surround = (smoothstep(-0.5 * pixel, 0.5 * pixel, inset + (traditional ? 0.22 : 0.08)) - opening)
			* (1.0 - buttress);
	float reveal = (1.0 - smoothstep(0.0, 0.16, inset)) * opening;
	color = mix(color, trim, surround);

	// The rose window: a wheel of tracery in a stone ring, on the gable at
	// the eaves.
	float rose = 0.0;
	float tracery = 0.0;
	vec2 glass_q = q;
	if (part == GABLE && traditional) {
		float radius = min(0.2 * width, 3.0);
		glass_q = p - vec2(0.0, max(top - 0.2 * radius, (front ? portal_top : 0.0) + radius + 1.0));
		float d = length(glass_q);
		rose = 1.0 - smoothstep(radius - 0.5 * pixel, radius + 0.5 * pixel, d);
		float spokes = centered_stripes(atan(glass_q.y, glass_q.x) / 0.5236, 0.12, pixel / max(d, 0.05) / 0.5236)
				* step(0.32 * radius, d);
		tracery = max(max(band(d, radius - 0.28, 1e4, pixel), band(d, 0.28 * radius, 0.36 * radius, pixel)), spokes) * rose;
		color = mix(color, trim, band(d, radius, radius + 0.25, pixel));
	}

	// What fills the openings.
	vec3 inside;
	float glass = 0.0;
	if (fill == DOORS) {
		// Wooden doors: planks, a seam down the middle, iron straps.
		vec3 wood = srgb(mix(vec3(0.34, 0.20, 0.14), vec3(0.42, 0.13, 0.11), step(0.6, rnd(seed, 7.0))));
		float planks = stripes(q.x / 0.16, 0.12, fp.x / 0.16) * visible(0.16, pixel);
		float seam = band(q.x, -0.03, 0.03, fp.x);
		float straps = (band(q.y, 0.7, 0.8, fp.y) + band(q.y, 2.0, 2.1, fp.y)) * visible(0.1, pixel);
		inside = mix(wood * (1.0 - 0.25 * planks), srgb(IRON), max(seam, straps));
	} else if (fill == LOUVERS) {
		// Louvers: slats with the dark belfry behind.
		float slats = stripes(q.y / 0.24, 0.45, fp.y / 0.24);
		inside = mix(srgb(LEAD) * 1.5, srgb(LOUVER), mix(0.45, slats, visible(0.12, pixel)));
	} else {
		inside = vec3(0.0);
		glass = max(opening, rose);
		// A mullion up the middle of wide windows.
		tracery = max(tracery, band(q.x, -0.05, 0.05, fp.x) * step(1.2, ow) * step(q.y, spring) * opening);
	}
	vec3 stained = stained_glass(glass_q, fp, seed);
	inside = mix(inside, stained, glass);
	inside = mix(inside, trim * 0.9, tracery);
	color = mix(color, inside * (1.0 - 0.45 * reveal), max(opening, rose));

	if (clock) {
		// The clock's hands keep the game's time.
		vec2 c = p - vec2(0.0, clock_y);
		float d = length(c);
		float hour = clock_hours / 12.0 * 6.2832;
		float minute = fract(clock_hours) * 6.2832;
		vec2 hd = vec2(sin(hour), cos(hour));
		vec2 md = vec2(sin(minute), cos(minute));
		float hands = max(band(abs(dot(c, vec2(hd.y, -hd.x))), -1.0, 0.06, pixel) * band(dot(c, hd), -0.1, 0.55 * clock_radius, pixel),
				band(abs(dot(c, vec2(md.y, -md.x))), -1.0, 0.04, pixel) * band(dot(c, md), -0.1, 0.85 * clock_radius, pixel));
		vec3 dial = mix(srgb(CLOCK_FACE), srgb(IRON), max(hands, band(d, clock_radius - 0.12, clock_radius, pixel)));
		color = mix(color, dial, 1.0 - smoothstep(clock_radius - pixel, clock_radius, d));
		color = mix(color, trim, band(d, clock_radius, clock_radius + 0.2, pixel));
	}

	Surface s;
	s.albedo = color;
	s.emission = vec3(0.0);
	if (city_lights > 0.0) {
		// Evening services: some churches' windows glow, warm through the colors.
		float h = clock_hours < 6.0 ? clock_hours + 24.0 : clock_hours;
		float lit = step(rnd(seed, 9.0), 0.5) * smoothstep(16.5, 17.5, h) * (1.0 - smoothstep(21.5, 22.5, h));
		s.emission = (stained * 2.0 + srgb(GLASS_LIT) * 0.25) * (glass * (1.0 - tracery) * lit * glass_glow * city_lights);
	}
	return s;
}

// A roof, a spire or a pinnacle. `textured` is the wall's masonry at p.
vec3 church_roof(int part, vec2 p, vec2 fp, int kind, int material, float seed, vec3 textured) {
	float pixel = max(fp.x, fp.y);
	float r = rnd(seed, 21.0);
	if (part == FLAT_ROOF) {
		return srgb(ROOF_TAR) * (0.9 + 0.2 * value_noise(p * 0.3 + seed * 40.0));
	}
	bool brick = material >= RED_BRICK;
	bool stone = part == PINNACLE || (part == SPIRE && !brick && kind != MODERN && rnd(seed, 22.0) < 0.4);
	if (stone) {
		// Stone spires and pinnacles, in the walls' stone (trim stone on brick).
		vec3 color = brick ? srgb(TRIM_STONE) : textured * 1.04;
		return color * (1.0 - 0.15 * band(fract(p.y / 3.0), 0.0, 0.12, fp.y / 3.0) * float(part == SPIRE));
	}
	// Slate mostly; copper gone green on some spires; red tile; modern asphalt.
	vec3 base = srgb(mix(SLATE_LOW, SLATE_HIGH, rnd(seed, 23.0)));
	if (kind == MODERN) {
		base = srgb(r < 0.6 ? SHINGLE_GRAY : TILE_RED);
	} else if (part == SPIRE && r < 0.2) {
		base = srgb(COPPER);
	} else if (r > 0.88) {
		base = srgb(TILE_RED);
	}
	// Courses of slates (or seams of copper) running along the eaves, staggered.
	float row = p.y / 0.32;
	float detail = visible(0.32, pixel);
	float lines = stripes(row, 0.14, fp.y / 0.32);
	float joints = stripes(p.x / 0.4 + 0.5 * mod(floor(row), 2.0), 0.1, fp.x / 0.4) * detail;
	float tint = (hash(vec2(floor(p.x / 0.4 + 0.5 * mod(floor(row), 2.0)), floor(row)) + seed) - 0.5) * 0.12 * detail;
	vec3 color = base * (1.0 + tint) * (1.0 - 0.25 * max(lines, joints));
	color *= 0.92 + 0.12 * value_noise(p * vec2(0.2, 0.5) + seed * 50.0);
	return color;
}

void vertex() {
	float code = floor(UV2.x + 0.5);
	float top_dm = floor(UV2.y + 0.0005);
	church_data = vec4(mod(code, 1024.0), floor(code / 1024.0 + 0.0001), top_dm, clamp(UV2.y - top_dm, 0.0, 0.999));
}

void fragment() {
	vec3 data = floor(church_data.xyz + 0.5);
	int code = int(data.x);
	int part = code % 16;
	int flags = code / 16;
	int kind = (flags / 2) % 4;
	int material = (flags / 8) % 8;
	float width = data.y * 0.1;
	float top = data.z * 0.1;
	float seed = church_data.w;
	vec2 fp = max(fwidth(UV), vec2(1e-4));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// The wall's stone and its masonry, worked out once for every part.
	vec3 wall = stone_color(material, rnd(seed, 1.0));
	vec3 textured = masonry(wall, material, UV, fp);
	textured *= 0.94 + 0.12 * value_noise(UV * vec2(0.12, 0.25) + seed * 71.0);

	Surface s;
	s.emission = vec3(0.0);
	float occlusion = 1.0;
	bool walls = part <= TOWER;
	if (walls) {
		s = church_wall(part, UV, fp, width, top, kind, material, seed, (flags & FRONT) != 0, wall, textured);
		occlusion = mix(canyon_occlusion, 1.0, smoothstep(0.0, canyon_height, UV.y));
	} else {
		s.albedo = church_roof(part, UV, fp, kind, material, seed, textured);
	}

	ALBEDO = toon_night_albedo(s.albedo);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + s.emission;
	toon_glint = 0.0;

	// Street lights on the feet of the walls near them.
	if (city_lights > 0.0 && walls) {
		float reach = 1.0 - smoothstep(street_light_reach.x, street_light_reach.y, UV.y);
		if (reach > 0.0) {
			vec3 scene_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			EMISSION += ALBEDO * street_light_at(scene_position.xz, length(VERTEX)) * (reach * city_lights);
		}
	}
}
