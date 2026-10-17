// The second batch of hand-made landmarks (tools/citygen/landmarks.py: the
// Guggenheim, the Public Library, St. Patrick's, the UN, Citigroup Center,
// the Hearst Tower, the Met, the Vessel, the Oculus, Yankee Stadium, the
// Unisphere, the Wonder Wheel, the Parachute Jump and Radio City's marquee;
// St. Patrick's carved work; the Pier 3 berm's meadow). Their faces with
// materials 41 to 59 and 62/63 come in each tile's landmarks surface
// (CityTileDecoder.SURFACE_LANDMARKS; the waterfront's, 60/61, have a
// shader of their own, waterfront.gdshader); faces in the first batch's materials
// (paving, plain stone, copper...) stay in the buildings surface, which
// shaders/building.gdshader paints. They have a shader of their own so the
// buildings' one stays small enough for browsers to compile quickly (ANGLE's
// D3D compiler takes minutes over one that holds both), and this one only
// compiles once a landmark comes into view.
//
// Per vertex, as in the buildings surface (see landmarks.py):
//   UV2.x material + 64 * flags (ROOF on roofs)
//   UV2.y param: on walls the face's width in dm * 4 + a variant
//   UV    walls: (m from the face's left corner seen from outside, m above
//         the landmark's ground) unless a material says otherwise; roofs:
//         local (x, y) in m
// Lighting is the shared toon model, like the buildings': glass reflects the
// sky, walls' feet catch the street lights, and at night windows, signs,
// rides and floodlights glow.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Materials (the archetype slot of UV2.x), as landmarks.py numbers them.
const int LM_GUGGENHEIM = 41;
const int LM_NYPL = 42;
const int LM_CATHEDRAL = 43;
const int LM_SLATE = 44;
const int LM_UN_GLASS = 45;
const int LM_UN_MARBLE = 46;
const int LM_CITIGROUP = 47;
const int LM_HEARST = 48;
const int LM_HEARST_BASE = 49;
const int LM_MET = 50;
const int LM_SKYLIGHT = 51;
const int LM_VESSEL = 52;
const int LM_WHITE_STEEL = 53;
const int LM_STADIUM = 54;
const int LM_PLAYFIELD = 55;
const int LM_UNISPHERE = 56;
const int LM_RIDE = 57;
const int LM_MARQUEE = 58;
const int LM_GOTHIC = 59;
const int LM_NYT = 62;
const int LM_MIDTOWN = 63;

// Flags (UV2.x / 64), as in building.gdshader.
const int ROOF = 1;

// Building types for the windows' lights (as in building.gdshader).
const int PREWAR_OFFICE = 6;
const int MIDCENTURY_OFFICE = 7;
const int MODERN_OFFICE = 8;
const int LOFT = 9;
const int STORE = 10;
const int INDUSTRIAL = 11;
const int INSTITUTION = 12;
const int HOTEL = 13;
const int OTHER = 14;

// Wall surfaces (wall_texture()).
const int BRICK = 0;
const int STONE = 1;
const int SIDING = 2;
const int SMOOTH = 3;

// Colors shared with building.gdshader, in sRGB.
const vec3 MORTAR = vec3(0.80, 0.79, 0.75);
const vec3 SHOP_LIGHT = vec3(1.0, 0.82, 0.55);
const vec3 ROOF_MEMBRANE = vec3(0.74, 0.73, 0.70);
const vec3 ROOF_GRAVEL = vec3(0.56, 0.54, 0.50);
const vec3 LM_GLASS = vec3(0.22, 0.28, 0.34);
const vec3 PAVING_STONE = vec3(0.70, 0.69, 0.66);
const vec3 GOLD_LEAF = vec3(1.00, 0.78, 0.30);
const vec3 FLOOD_WARM = vec3(1.0, 0.88, 0.70);
const vec3 FLOOD_COOL = vec3(0.86, 1.0, 0.96);
// Lights in windows at night, in sRGB: incandescent, soft warm white, cool
// white (LEDs, offices' fluorescents), neutral white, a TV's blue; office
// lobbies.
const vec3 LAMP_WARM = vec3(1.0, 0.70, 0.40);
const vec3 LAMP_SOFT = vec3(1.0, 0.84, 0.62);
const vec3 LAMP_COOL = vec3(0.84, 0.90, 0.96);
const vec3 LAMP_NEUTRAL = vec3(1.0, 0.88, 0.68);
const vec3 TV_BLUE = vec3(0.45, 0.58, 1.0);
const vec3 LOBBY_LIGHT = vec3(1.0, 0.88, 0.68);


// The dark steel round screens, in sRGB.
const vec3 SIGN_STEEL = vec3(0.10, 0.10, 0.12);

// How mirror-like glass is overall (each building type scales it).
uniform float glass_reflection : hint_range(0.0, 2.0) = 1.3;
// The sky that glass reflects, in sRGB: overhead, at the horizon, and the
// city below the horizon.
uniform vec3 reflect_zenith : source_color = vec3(0.36, 0.58, 0.85);
uniform vec3 reflect_horizon : source_color = vec3(0.80, 0.87, 0.92);
uniform vec3 reflect_ground : source_color = vec3(0.30, 0.32, 0.36);
// The same at dusk and at night (blended by night.gdshaderinc's globals): zenith,
// horizon, and the city below.
uniform vec3 dusk_reflect_zenith : source_color = vec3(0.30, 0.38, 0.62);
uniform vec3 dusk_reflect_horizon : source_color = vec3(0.98, 0.70, 0.52);
uniform vec3 dusk_reflect_ground : source_color = vec3(0.30, 0.27, 0.30);
uniform vec3 night_reflect_zenith : source_color = vec3(0.03, 0.05, 0.12);
uniform vec3 night_reflect_horizon : source_color = vec3(0.30, 0.21, 0.22);
uniform vec3 night_reflect_ground : source_color = vec3(0.13, 0.10, 0.09);
// Walls darken toward their feet in the street's shade.
uniform float canyon_occlusion : hint_range(0.0, 1.0) = 0.85;
uniform float canyon_height = 25.0;
// Night: how bright lit windows and lobbies are, how far up walls the street
// lights reach (m), how bright floodlit landmarks are.
uniform float window_glow = 1.0;
uniform float lobby_glow = 1.4;
uniform vec2 street_light_reach = vec2(3.0, 13.0);
uniform float landmark_flood = 1.0;

// Moments of the wall height at the vertices (see wall_top_distance).
varying vec4 wall_moments;
// UV2 decoded into whole numbers in the vertex shader: (material + 64 *
// flags, param). Fragments round them back.
varying vec2 landmark_data;

struct Surface {
	vec3 albedo;
	vec3 emission;      // light of its own
	float glass;        // how much of the pixel is reflective glass
};

// --- Helpers, as in building.gdshader ---

// A random number per building (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed * 1024.0 + salt * 3.7, salt * 13.1 + 7.0));
}

int pick(float r, int count) {
	return min(int(r * float(count)), count - 1);
}

// A smooth bump in time: up from a to b, down from c to d (hours).
float bump(float h, float a, float b, float c, float d) {
	return smoothstep(a, b, h) * (1.0 - smoothstep(c, d, h));
}

// The share of a building type's windows lit at this hour, before each
// building's and floor's own variety: homes busy in the evening and nearly
// dark before dawn, offices emptying after work (cleaners and lights left on
// keep some lit all night), hotels in between.
float occupancy(int archetype, float hours) {
	float h = hours < 6.0 ? hours + 24.0 : hours;  // 6..30, so the night is in one piece
	float home = 0.05 + 0.18 * bump(h, 6.0, 7.0, 8.0, 9.5) + 0.38 * bump(h, 16.5, 20.0, 23.0, 26.5);
	float work = 0.1 + 0.45 * bump(h, 6.5, 8.5, 17.0, 19.5) + 0.12 * bump(h, 6.5, 8.5, 19.5, 23.0);
	if (archetype >= PREWAR_OFFICE && archetype <= MODERN_OFFICE) {
		return work;
	}
	if (archetype == LOFT) {
		return mix(home, work, 0.4);
	}
	if (archetype == HOTEL) {
		return 0.1 + 0.75 * home;
	}
	if (archetype == STORE) {
		return 0.75 * home;  // flats over the shops
	}
	if (archetype == INSTITUTION) {
		return 0.12 + 0.3 * bump(h, 6.5, 8.0, 18.0, 21.0);
	}
	if (archetype == INDUSTRIAL || archetype == OTHER) {
		return 0.07;
	}
	return home;
}

// The light in the window at `cell` (bay, floor) at night (linear, before
// city_lights and window_glow). Whether it's lit is a hash of the window (in
// offices, of a run of bays on a floor that's mostly lit or mostly dark), so
// it never changes as the camera moves, and windows switch on and off one by
// one as the hours pass. `cell_pixels` is how many pixels a window cell spans
// (across, up): once windows are only a few pixels, they become their floor's
// average light, and floors their building's, so the distance settles from a
// glitter into a steady glow. `up` is how far up the window this is (0..1).
vec3 window_light(int archetype, bool curtain, vec2 cell, float seed, vec2 cell_pixels, float up) {
	bool office = archetype >= PREWAR_OFFICE && archetype <= MODERN_OFFICE;
	float share = clamp(occupancy(archetype, clock_hours) * mix(0.55, 1.45, rnd(seed, 61.0)), 0.0, 1.0);
	float floor_hash = hash(vec2(cell.y * 1.37 + 0.5, seed * 293.0 + 11.0));
	float floor_share = office ? (floor_hash < 0.3 ? min(2.2 * share, 1.0) : 0.5 * share)
			: share * mix(0.7, 1.3, floor_hash);
	float building_share = office ? 0.3 * min(2.2 * share, 1.0) + 0.35 * share : share;
	// Offices are lit in runs of bays; homes in flats of two windows (offset
	// floor to floor), all one color.
	float run = office ? floor(cell.x / (2.0 + floor(rnd(seed, 62.0) * 4.0)))
			: floor((cell.x + step(0.5, hash(vec2(cell.y, seed * 37.0)))) * 0.5);
	float lit = step(hash(vec2(run * 0.71 + 0.3, cell.y) + seed * 91.3), floor_share);
	float c = hash(vec2(run, cell.y) + seed * 57.0 + 63.1);
	float brightness = mix(0.6, 1.25, hash(cell + seed * 57.0 + 71.7));
	vec3 color;
	vec3 average;
	if (office) {
		color = srgb(c < 0.5 ? LAMP_COOL : LAMP_NEUTRAL);
		average = mix(srgb(LAMP_NEUTRAL), srgb(LAMP_COOL), 0.5);
		brightness *= 0.8;
	} else {
		color = srgb(c < 0.6 ? LAMP_WARM : (c < 0.88 ? LAMP_SOFT : (c < 0.96 ? LAMP_COOL : TV_BLUE)));
		// (Far off, lit windows read as golden sparkle more than orange.)
		average = srgb(LAMP_SOFT) * 0.9;
		if (c >= 0.96) {
			// A TV: its picture changes a few times a second.
			brightness *= 0.45 + 0.55 * hash(vec2(floor(TIME * 2.5 + c * 40.0), c * 17.0));
		}
	}
	float window_detail = smoothstep(1.6, 3.5, min(cell_pixels.x, cell_pixels.y));
	float expected = mix(building_share, floor_share, smoothstep(1.2, 3.0, cell_pixels.y));
	// (The distant glow is kept under the windows' true average: spread over a
	// whole wall it would read as the wall lit, not its windows.)
	vec3 light = mix(average * (expected * 0.6), color * (lit * brightness), window_detail);
	if (office && curtain) {
		// Every floor glows a little from the lit core deep inside.
		light += srgb(LAMP_COOL) * 0.1;
	}
	// Ceiling lights: a little brighter toward the top of the window.
	return light * mix(0.8, 1.15, up);
}

// The foot and top of this fragment's wall triangle (UV.y meters), or
// (-1e4, 1e4) where they aren't known. A wall triangle's corners sit at just
// two heights, its foot b and its top t; the vertex shader passes the first
// four powers of the height, and since every fragment's interpolated moments
// m_k mix b^k and t^k with the same weights, b and t are the roots of
// x^2 - s x + p = 0, with s and p found from m1..m3. The fourth moment checks
// that there really were only two heights (wall polygons with steps
// triangulate into some triangles with three).
vec2 wall_span(vec4 m) {
	float variance = m.y - m.x * m.x;
	if (abs(variance) < 1e-10) {
		return vec2(-1e4, 1e4);
	}
	float s = (m.z - m.x * m.y) / variance;
	float p = s * m.x - m.y;
	float discriminant = s * s - 4.0 * p;
	if (discriminant < 0.0 || abs(m.w - (s * m.z - p * m.y)) > 0.01 * max(m.w, 1e-8)) {
		return vec2(-1e4, 1e4);
	}
	float root = sqrt(discriminant);
	return vec2(0.5 * (s - root), 0.5 * (s + root)) * 100.0 - 1.0;
}

// Meters from this fragment up to the top of its wall, or a big number where
// that isn't known (see wall_span()).
float wall_top_distance(vec4 m, float y) {
	return wall_span(m).y - y;
}

vec3 wall_texture(vec3 color, int surface, vec2 p, vec2 footprint) {
	if (surface == BRICK) {
		// Courses of brick with lighter mortar, each brick a little different.
		const float COURSE = 0.076;
		const float BRICK_LENGTH = 0.2;
		float detail = visible(COURSE, max(footprint.x, footprint.y));
		float row = p.y / COURSE;
		float shift = mod(floor(row), 2.0) * 0.5 * detail;
		float joints = max(stripes(row, 0.16, footprint.y / COURSE),
				stripes(p.x / BRICK_LENGTH + shift, 0.08, footprint.x / BRICK_LENGTH) * detail);
		float tint = (hash(vec2(floor(p.x / BRICK_LENGTH + shift), floor(row))) - 0.5) * 0.14 * detail;
		return mix(color * (1.0 + tint), mix(color, srgb(MORTAR), 0.45), joints * 0.55);
	}
	if (surface == STONE) {
		// Ashlar blocks with thin dark joints.
		const vec2 BLOCK = vec2(1.3, 0.62);
		float detail = visible(BLOCK.y, max(footprint.x, footprint.y));
		float row = p.y / BLOCK.y;
		float shift = mod(floor(row), 2.0) * 0.5 * detail;
		float joints = max(stripes(row, 0.03, footprint.y / BLOCK.y),
				stripes(p.x / BLOCK.x + shift, 0.015, footprint.x / BLOCK.x) * detail);
		float tint = (hash(vec2(floor(p.x / BLOCK.x + shift), floor(row))) - 0.5) * 0.06 * detail;
		return color * (1.0 + tint) * (1.0 - 0.28 * joints);
	}
	if (surface == SIDING) {
		// Clapboards: a shadow line under each board.
		const float BOARD = 0.2;
		float shadow = stripes(p.y / BOARD, 0.18, footprint.y / BOARD);
		return color * (1.0 - 0.22 * shadow);
	}
	return color;
}

// A bright ad color (linear) round the color wheel, h 0..1 (a formula, not a
// table: tables indexed per pixel compile slowly).
vec3 ad_color(float h) {
	return srgb(0.56 + 0.36 * cos(2.0 * PI * (h + vec3(0.0, 0.33, 0.67))));
}

// A seven-segment glyph (LETTERS) in its box: g runs 0..1 across and up the
// box, fg is the pixel's footprint in box units. Returns its coverage.
float glyph(int code, vec2 g, vec2 fg) {
	const vec2 STROKE = vec2(0.26, 0.15);  // stroke width across, height up (box units)
	float across = band(g.x, 0.0, 1.0, fg.x);
	float left = band(g.x, 0.0, STROKE.x, fg.x);
	float right = band(g.x, 1.0 - STROKE.x, 1.0, fg.x);
	float upper = band(g.y, 0.5, 1.0, fg.y);
	float lower = band(g.y, 0.0, 0.5, fg.y);
	float top = band(g.y, 1.0 - STROKE.y, 1.0, fg.y);
	float middle = band(g.y, 0.5 - 0.5 * STROKE.y, 0.5 + 0.5 * STROKE.y, fg.y);
	float bottom = band(g.y, 0.0, STROKE.y, fg.y);
	float on = max(max(float((code & 1) != 0) * top, float((code & 64) != 0) * middle), float((code & 8) != 0) * bottom) * across;
	on = max(on, (float((code & 32) != 0) * upper + float((code & 16) != 0) * lower) * left);
	on = max(on, (float((code & 2) != 0) * upper + float((code & 4) != 0) * lower) * right);
	return min(on, 1.0);
}


// A window grid fitted to a face `width` m wide: bays of about `bay` m, as
// many as fit, so piers land on the corners; floors `floor_height` m, each
// window from `sill` to `head` m above its floor. Returns (glass, the window
// columns' coverage, lines along the columns' edges, how far up its window)
// and the window's cell and the cells' size.
vec4 lm_grid(vec2 p, vec2 fp, float width, float bay, float window_width, float floor_height, float sill,
		float head, float edge_width, out vec2 cell, out vec2 cell_size) {
	float n = max(1.0, floor(width / bay + 0.5));
	float b = width > 0.5 ? width / n : bay;
	cell_size = vec2(b, floor_height);
	vec2 q = p / cell_size;
	vec2 fq = fp / cell_size;
	cell = floor(q);
	float w = min(window_width / b, 0.92);
	float column = centered_stripes(q.x - 0.5, w, fq.x);
	float rows = stripes(q.y - sill / floor_height, (head - sill) / floor_height, fq.y);
	float edges = 0.0;
	if (edge_width > 0.0) {
		edges = min(centered_stripes(q.x - 0.5 + 0.5 * w, edge_width / b, fq.x)
				+ centered_stripes(q.x - 0.5 - 0.5 * w, edge_width / b, fq.x), 1.0);
	}
	float up = clamp((p.y - cell.y * floor_height - sill) / max(head - sill, 0.1), 0.0, 1.0);
	return vec4(column * rows, column, edges, up);
}

// A classical cornice from z0 to z1: lip, frieze with brackets, dentils.
vec3 lm_cornice(vec3 color, vec2 p, vec2 fp, float z0, float z1) {
	float h = z1 - z0;
	float t = (p.y - z0) / h;
	float ft = fp.y / h;
	float brackets = centered_stripes(p.x / 1.1, 0.22, fp.x / 1.1);
	float dentils = stripes(p.x / 0.26, 0.5, fp.x / 0.26);
	float shade = band(t, -1.0, 0.18, ft) * 0.55 + band(t, 0.18, 0.62, ft) * mix(0.82, 1.08, brackets)
			+ band(t, 0.62, 0.78, ft) * mix(0.62, 1.0, dentils) + band(t, 0.78, 2.0, ft) * 1.12;
	return color * shade;
}

// The sky as glass sees it, in direction r (world space).
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

// --- Colors, words and tables ---

const vec3 GUGG_WHITE = vec3(0.89, 0.89, 0.87);     // painted concrete, white-gray
const vec3 MARBLE = vec3(0.76, 0.75, 0.72);         // Vermont and the UN's marble, weathered gray-beige
const vec3 CATHEDRAL_MARBLE = vec3(0.65, 0.62, 0.56);  // St. Patrick's Tuckahoe marble, weathered gray-tan
const vec3 SLATE_GRAY = vec3(0.37, 0.41, 0.43);
const vec3 UN_GREEN = vec3(0.32, 0.52, 0.53);       // the Secretariat's blue-green glass
const vec3 ALUMINUM = vec3(0.84, 0.85, 0.86);
const vec3 SILVER_GLASS = vec3(0.42, 0.50, 0.57);
const vec3 HEARST_GLASS = vec3(0.34, 0.45, 0.55);
const vec3 DIAGRID_STEEL = vec3(0.72, 0.74, 0.76);
const vec3 CAST_STONE = vec3(0.83, 0.79, 0.69);
const vec3 MET_LIMESTONE = vec3(0.86, 0.83, 0.75);
const vec3 COPPER_CLAD = vec3(0.64, 0.44, 0.33);    // the Vessel's copper-colored steel, weathered
const vec3 PAINT_WHITE = vec3(0.94, 0.94, 0.93);
const vec3 SEAT_BLUE = vec3(0.14, 0.26, 0.55);
const vec3 TURF = vec3(0.30, 0.55, 0.26);
const vec3 INFIELD_DIRT = vec3(0.68, 0.47, 0.32);
const vec3 STAINLESS = vec3(0.79, 0.81, 0.83);
const vec3 RIDE_BLUE = vec3(0.20, 0.38, 0.70);
const vec3 RIDE_RED = vec3(0.74, 0.16, 0.12);
const vec3 POOL_WATER = vec3(0.45, 0.72, 0.78);
const vec3 BRONZE = vec3(0.30, 0.24, 0.17);
// Letters as seven-segment codes (bits: 1 top, 2 upper right, 4 lower right,
// 8 bottom, 16 lower left, 32 upper left, 64 middle; 0 a space), one table
// looked up in one place: first sixteen letter-like glyphs for made-up words
// (A b C d E F H J L o P S U y O 2), then the words: YANKEE STADIUM from
// WORDS, WONDER WHEEL from WONDER, RADIO CITY MUSIC HALL (and RADIO CITY)
// from RADIO_CITY.
const int LETTERS[63] = int[](119, 124, 57, 94, 121, 113, 118, 30, 56, 92, 115, 109, 62, 110, 63, 91,
		110, 119, 55, 118, 121, 121, 0, 109, 120, 119, 94, 6, 62, 55,
		62, 63, 55, 94, 121, 80, 0, 62, 118, 121, 121, 56,
		80, 119, 94, 6, 63, 0, 57, 6, 120, 110, 0, 55, 62, 109, 6, 57, 0, 118, 119, 56, 56);
const int WORDS = 16;
const int WONDER = 30;
const int RADIO_CITY = 42;
// The Unisphere's continents (UNISPHERE_LAND in landmarks.py): 24 rows of 48
// cells 7.5 degrees square, from 90 N and 180 W; two words a row, bit k of the
// first for cell k, of the second for cell 32 + k.
const uint UNISPHERE_LAND[48] = uint[](0u, 0u, 4192256u, 32u, 2283700188u, 16382u, 4263927804u, 65535u,
		4269866944u, 10239u, 4286709632u, 2047u, 4286611328u, 1023u, 4085268224u, 255u, 4290774528u, 255u,
		4290780160u, 126u, 2143342592u, 100u, 1048698880u, 160u, 1040703488u, 1216u, 1007149056u, 0u,
		1577566208u, 3840u, 470007808u, 8064u, 201441280u, 3456u, 49152u, 0u, 16384u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
		0u, 0u, 0u, 0u);
// Hunt's facade at the Met: the entrance floor above the landmark's base (the
// steps' top in landmarks.py: Fifth Avenue's ground there + 3.2 m).
const float MET_FLOOR = 5.8;

// Whether the Unisphere has land at (degrees east, degrees north).
float unisphere_land(vec2 lonlat) {
	int col = clamp(int(floor((lonlat.x + 180.0) / 7.5)), 0, 47);
	int row = clamp(int(floor((90.0 - lonlat.y) / 7.5)), 0, 23);
	uint word = UNISPHERE_LAND[row * 2 + col / 32];
	return float((word >> uint(col % 32)) & 1u);
}

// How far inside an arched opening `w` wide a point is (m; negative outside):
// from `sill` up, its sides rising to `spring`, round-topped or pointed (an
// equilateral Gothic arch). q is m from the opening's middle, m up. One
// inset serves an opening and the frames stepping in around it.
float lm_arch_inset(vec2 q, float w, float sill, float spring, bool pointed) {
	float top = pointed ? w - max(length(q - vec2(-0.5 * w, spring)), length(q - vec2(0.5 * w, spring)))
			: 0.5 * w - length(q - vec2(0.0, spring));
	return min(q.y < spring ? 0.5 * w - abs(q.x) : top, q.y - sill);
}

// A wall of the second batch (see the material list in landmarks.py).
// `below_top` is m from here to the top of the wall where known, `scene` the
// fragment's position in the scene (its y the height above sea level). Like
// building.gdshader's landmark_wall(), each material only sets numbers and
// cheap patterns; the
// heavy helpers (the wall's texture, an arched opening, a cornice, lit
// windows, a letter, a line of text) are called once each, after the
// materials, so the shader stays small enough to compile quickly.
Surface landmark_wall_2(int material, int variant, vec2 p, vec2 fp, float width, float below_top, vec3 scene) {
	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	float pixel = max(fp.x, fp.y);

	// The wall's stone.
	vec3 base = MARBLE;
	int surface = STONE;
	if (material == LM_GUGGENHEIM) {
		base = variant == 3 ? vec3(0.82, 0.79, 0.71) : GUGG_WHITE;
		surface = variant == 3 ? STONE : SMOOTH;
	} else if (material == LM_HEARST_BASE) {
		base = CAST_STONE;
	} else if (material == LM_MET) {
		base = MET_LIMESTONE;
	} else if (material == LM_STADIUM) {
		base = vec3(0.86, 0.83, 0.75);
	} else if (material == LM_CITIGROUP) {
		base = variant == 3 ? vec3(0.46, 0.39, 0.34) : ALUMINUM;
		surface = variant == 3 ? STONE : SMOOTH;
	} else if (material == LM_CATHEDRAL || material == LM_GOTHIC) {
		base = CATHEDRAL_MARBLE;
	} else if (material != LM_NYPL) {
		surface = SMOOTH;
	}
	vec3 stone = wall_texture(srgb(base), surface, p, fp);
	vec3 color = stone;

	// What the shared helpers below draw (nothing unless a material asks).
	vec2 arch_q = vec2(0.0);       // an arched opening: point relative to it,
	vec3 arch = vec3(0.0);         // its width, sill and springing
	bool pointed = false;
	vec2 cornice = vec2(0.0);      // a cornice from .x to .y m up
	float lit = 0.0;               // office windows lit at night: coverage,
	vec2 cell = vec2(0.0);         // the window's cell and the cells' size
	vec2 cell_size = vec2(1.0);
	float up = 0.5;
	float seed = 0.5;
	int word = -1;                 // a letter (its place in LETTERS), its box's lower
	vec2 letter_q = vec2(0.0);     // left and height, its color and glow
	float letter_h = 1.0;
	vec3 letter_color = vec3(1.0);
	float letter_glow = 0.0;
	float text_h = 0.0;            // a line of text: height, start, salt, color, glow
	vec2 text_q = vec2(0.0);
	float text_salt = 0.0;
	vec3 text_color = vec3(0.0);
	float text_glow = 0.0;
	float glazed = 1.0;            // a pointed opening's glass (0: open stonework)
	float flood = 0.0;             // floodlit at night, this strongly
	vec3 flood_color = srgb(FLOOD_WARM);

	if (material == LM_GUGGENHEIM) {
		color = stone * (0.97 + 0.04 * value_noise(p * vec2(0.3, 0.8)));
		if (variant == 0) {
			if (width > 60.0) {
				// Far away the rotunda is one frustum: its glass strips painted on.
				float strip = (1.0 - band(fract((p.y - 1.85) / 5.1), 0.22, 1.0, fp.y / 5.1)) * step(4.4, p.y);
				color = mix(color, srgb(vec3(0.20, 0.23, 0.26)), strip);
				s.emission = srgb(LAMP_SOFT) * (strip * 1.5 * city_lights);
			} else if (width < 20.0 && p.y < 8.0) {
				// The museum's name along the bridge.
				text_h = p.x > 1.0 && p.x < width - 1.0 ? 0.75 : 0.0;
				text_q = vec2(p.x - 1.0, p.y - 4.9);
				text_salt = 31.0;
				text_color = srgb(vec3(0.25, 0.22, 0.18));
			}
			flood = 0.45;
		} else if (variant == 1) {
			// The glass strips between the bands, the ramps' light behind them at night.
			float mullion = centered_stripes(p.x / 1.6, 0.06, fp.x / 1.6);
			color = mix(srgb(vec3(0.17, 0.20, 0.24)), stone * 0.8, mullion);
			s.glass = 0.8 * (1.0 - mullion);
			s.emission = srgb(LAMP_SOFT) * ((1.0 - mullion) * 1.8 * city_lights);
		} else if (variant == 2) {
			// Plain walls with a band of windows each floor.
			float pane = band(fract(p.y / 4.2), 0.45, 0.8, fp.y / 4.2) * step(1.0, p.y)
					* (1.0 - centered_stripes(p.x / 1.5, 0.08, fp.x / 1.5));
			color = mix(color, srgb(vec3(0.20, 0.24, 0.28)), pane);
			s.glass = pane * 0.8;
			s.emission = srgb(LAMP_NEUTRAL) * (pane * 0.5 * city_lights);
			flood = 0.25;
		} else {
			// The annex: a limestone grid, a window in each square.
			vec4 g = lm_grid(p, fp, width, 1.55, 1.15, 3.9, 0.5, 3.4, 0.0, cell, cell_size);
			color = mix(stone, srgb(LM_GLASS), g.x);
			s.glass = g.x * 0.8;
			lit = g.x;
			up = g.w;
			seed = 0.3;
		}
	} else if (material == LM_NYPL) {
		float light = 0.0;
		if (variant == 0) {
			// A granite plinth, the rusticated ground floor, tall arched windows on
			// the main floor between pilasters, small ones above, the cornice.
			color *= mix(0.78, 1.0, band(p.y, 1.1, 1e4, fp.y));
			color *= 1.0 - 0.25 * stripes(p.y / 0.75, 0.06, fp.y / 0.75) * band(p.y, 1.1, 7.5, fp.y);
			float bay = width / max(1.0, floor(width / 6.6 + 0.5));
			float x = mod(p.x, bay) - 0.5 * bay;
			arch_q = vec2(x, p.y);
			arch = vec3(2.5, 8.2, 14.2);
			float pane = max(band(x, -0.8, 0.8, fp.x) * band(p.y, 16.6, 19.4, fp.y), band(x, -0.7, 0.7, fp.x) * band(p.y, 2.4, 5.6, fp.y));
			color = mix(color, stone * 1.06, band(abs(x), 0.5 * bay - 0.55, 0.5 * bay + 0.1, fp.x) * band(p.y, 7.5, 20.3, fp.y));
			color = mix(color, srgb(LM_GLASS), pane);
			s.glass = pane * 0.8;
			light = pane * 0.6;
			cornice = vec2(20.3, 22.4);
		} else if (variant == 1) {
			// The portico: three arched doorways.
			float x = p.x - 0.5 * width;
			arch_q = vec2(x - clamp(floor(x / 9.3 + 0.5), -1.0, 1.0) * 9.3, p.y);
			arch = vec3(4.6, 1.8, 9.6);
			cornice = vec2(13.9, 16.0);
		} else {
			// Columns, the entablature, the attic: fluted where narrow.
			color *= 1.0 - 0.1 * stripes(p.x / 0.32, 0.35, fp.x / 0.32) * visible(0.32, pixel) * step(width, 8.0);
		}
		s.emission = srgb(LAMP_SOFT) * (light * city_lights);
		flood = 0.9;
	} else if (material == LM_CATHEDRAL || material == LM_GOTHIC) {
		// Weathered marble: blotchy, grimier low down.
		color = stone * (0.9 + 0.14 * value_noise(p * vec2(0.45, 0.2))) * mix(0.8, 1.0, smoothstep(0.0, 8.0, p.y));
		pointed = true;
		if (material == LM_GOTHIC) {
			if (variant == 1) {
				// Pinnacles, crockets, gablets: carved leaves in courses.
				color *= 1.0 - 0.22 * stripes(p.y / 0.7, 0.3, fp.y / 0.7) * visible(0.7, pixel);
			} else if (variant == 2) {
				// Stained glass seen from outside, dark and muted, in stone tracery:
				// the rose window (7.9 m: sixteen lights round a quatrefoil) on the
				// central front, elsewhere lights between mullions and transoms.
				// (Mullions across and transoms up; on the rose, spokes across and
				// rings up, in polar coordinates.)
				vec2 q = vec2(p.x - 0.5 * width, p.y - 26.0);
				bool rose = width > 12.0;
				float r = length(q) / 3.95;
				vec2 t = rose ? vec2(atan(q.y, q.x) / PI * 8.0, r * 2.7 - 0.9) : vec2(q.x / 1.05 + 0.5, p.y / 2.4);
				vec2 ft = rose ? vec2(pixel / max(r * 3.95, 0.2) * 2.5, 2.7 * pixel / 3.95) : fp / vec2(1.05, 2.4);
				float tracery = max(centered_stripes(t.x, 0.14, ft.x) * step(0.33, r * float(rose) + float(!rose)),
						stripes(t.y, 0.1, ft.y)) + (rose ? step(0.97, r) : 0.0);
				float pane = floor(t.x) + 17.0 * floor(t.y);
				float h = hash(vec2(pane, 3.7));
				vec3 glass = srgb(mix(mix(vec3(0.11, 0.12, 0.19), vec3(0.22, 0.11, 0.12), step(0.55, h)), vec3(0.20, 0.17, 0.11), step(0.85, h)));
				color = mix(glass, color * 0.8, tracery);
				s.glass = 0.4 * (1.0 - tracery);
				s.emission = glass * ((1.0 - tracery) * 3.0 * city_lights);
			} else if (variant == 3) {
				// A portal's back: bronze doors in panels; over them the tympanum
				// with a row of niches.
				float x = p.x - 0.5 * width;
				float door_h = width > 12.0 ? 5.0 : 3.8;
				float door = band(abs(x), -1.0, width > 12.0 ? 1.7 : 1.15, fp.x) * step(p.y, door_h);
				vec3 bronze = srgb(BRONZE) * (1.0 - 0.35 * centered_stripes(x / 0.85, 0.08, fp.x / 0.85));
				color = mix(color * 0.8, bronze, door);
				arch_q = vec2(mod(x, 1.4) - 0.7, p.y);
				arch = vec3(0.8, door_h + 0.9, door_h + 2.3);
				glazed = 0.0;
			}
		} else if (variant <= 1) {
			// Bays between buttresses, a pointed window in each: the aisles' low
			// ones, the clerestory's tall ones over the triforium's arcade.
			float bay = width / max(1.0, floor(width / 7.2 + 0.5));
			float x = mod(p.x, bay) - 0.5 * bay;
			float buttress = band(abs(x), 0.5 * bay - 0.7, 0.5 * bay + 0.1, fp.x);
			color = mix(color, stone * 1.08, buttress);
			color *= 1.0 - 0.18 * band(abs(x), 0.5 * bay - 0.95, 0.5 * bay - 0.7, fp.x);
			arch_q = vec2(x, p.y);
			if (variant == 0) {
				arch = vec3(min(2.6, bay * 0.4), 5.5, 13.0);
				color *= mix(0.85, 1.0, band(p.y, 1.4, 1e4, fp.y));
			} else {
				arch = vec3(min(3.6, bay * 0.55), 23.5, 28.6);
				float arcade = band(p.y, 20.9, 22.6, fp.y) * stripes(p.x / 0.9, 0.5, fp.x / 0.9) * (1.0 - buttress);
				color = mix(color, stone * 0.55, arcade * 0.7 * visible(0.9, pixel));
			}
		} else if (variant == 2) {
			// The central wall and its gable: a cornice under the gable, and in
			// it a wheel of blind tracery (three foils in a ring).
			vec2 q = vec2(p.x - 0.5 * width, p.y - 40.2);
			float r = length(q);
			float foil = min(min(abs(r - 2.9), abs(length(q - vec2(0.0, 1.1)) - 1.0)),
					min(abs(length(q - vec2(0.95, -0.55)) - 1.0), abs(length(q - vec2(-0.95, -0.55)) - 1.0)));
			color *= mix(1.0, mix(0.7, 1.05, band(foil, -1.0, 0.16, pixel)), step(r, 3.1) * step(34.5, p.y));
		} else if (p.y < 41.6) {
			// The towers: string courses; four small lancets a side under the
			// battlement.
			float x = p.x - 0.5 * width;
			color *= 1.0 - 0.2 * stripes((p.y - 1.0) / 10.2, 0.03, fp.y / 10.2);
			arch_q = vec2(mod(x + 3.1, 1.55) - 0.775, p.y);
			arch = vec3(0.85 * step(abs(x), 3.1), 31.0, 37.6);
		} else if (p.y < 59.0) {
			// The lanterns: tall paired openings in each face.
			float side = width / 8.0;
			float x = mod(p.x, side) - 0.5 * side;
			arch_q = vec2(abs(x) - 0.75, p.y);
			arch = vec3(0.95, 44.5, 53.0);
			glazed = 0.0;
		} else {
			// The spires: tiers of pierced tracery between moldings (u: the share
			// across a face, so the openings narrow with it).
			color *= 1.0 - 0.2 * stripes((p.y - 59.0) / 3.3, 0.08, fp.y / 3.3);
			arch_q = vec2(mod(p.x, 1.2) - 0.6, mod(p.y - 59.0, 3.3));
			arch = vec3(0.5, 0.55, 2.2);
			glazed = 0.0;
		}
		flood = 1.0;
	} else if (material == LM_NYT || material == LM_MIDTOWN) {
		// Building-specific grids; fine rods/mullions filter to their average
		// coverage at distance instead of sparkling or vanishing on LOD swaps.
		bool nyt = material == LM_NYT;
		bool bronze = !nyt && variant == 0;
		bool lever = !nyt && variant == 1;
		float floor_h = nyt ? 4.05 : (lever ? 3.75 : 3.9);
		float bay = nyt ? 1.5 : (bronze ? 1.4 : (lever ? 1.5 : 2.8));
		cell_size = vec2(bay, floor_h);
		cell = floor(p / cell_size);
		vec3 tint = nyt ? vec3(0.29, 0.38, 0.42) : (bronze ? vec3(0.22, 0.18, 0.12) :
				(lever ? vec3(0.16, 0.37, 0.35) : vec3(0.25, 0.28, 0.28)));
		vec3 frame = bronze ? vec3(0.30, 0.23, 0.14) : (lever ? ALUMINUM : vec3(0.77, 0.76, 0.72));
		float piers = centered_stripes(p.x / bay, (!nyt && !bronze && !lever) ? 0.24 : 0.07, fp.x / bay);
		float spandrel = stripes(p.y / floor_h, lever ? 0.38 : 0.22, fp.y / floor_h);
		vec3 glass = srgb(tint) * mix(1.0, 0.90 + 0.16 * hash(cell), visible(bay, pixel));
		color = mix(mix(glass, srgb(frame) * (lever || bronze ? 0.52 : 0.88), spandrel), srgb(frame), piers);
		float covered = max(piers, spandrel);
		if (nyt && variant == 0) {
			float rods = stripes(p.y / 0.45, 0.28, fp.y / 0.45);
			color = mix(color, srgb(vec3(0.85, 0.84, 0.80)), rods * 0.78);
			covered = max(covered, rods * 0.78);
		} else if (!nyt && !bronze && !lever) {
			float mech = max(band(p.y, 110.0, 118.0, fp.y), band(p.y, 227.0, 1e4, fp.y));
			float louvers = stripes(p.y / 0.6, 0.5, fp.y / 0.6);
			color = mix(color, srgb(frame) * (0.50 + 0.25 * louvers), mech);
			covered = max(covered, mech);
		}
		s.glass = (1.0 - covered) * (bronze ? 0.55 : 0.85);
		lit = 1.0 - covered;
		up = fract(p.y / floor_h);
		seed = nyt ? 0.42 : (bronze ? 0.25 : 0.62);
	} else if (material == LM_UN_GLASS) {
		// Blue-green glass in a thin aluminum grid; the mechanical floors behind
		// grilles; the lobby's glass at the foot.
		float floor_h = 3.84;
		float mech = min(band(p.y, 19.2, 23.0, fp.y) + band(p.y, 57.6, 61.4, fp.y) + band(p.y, 103.7, 107.5, fp.y)
				+ band(p.y, 146.4, 1e4, fp.y), 1.0);
		float lobby = 1.0 - band(p.y, 6.2, 1e4, fp.y);
		cell_size = vec2(1.22, floor_h);
		cell = floor(p / cell_size);
		float mullion = centered_stripes(p.x / 1.22, 0.07, fp.x / 1.22);
		float spandrel = stripes(p.y / floor_h, 0.28, fp.y / floor_h);
		vec3 glass = srgb(UN_GREEN) * mix(1.0, mix(0.9, 1.08, hash(cell)), visible(1.22, pixel));
		color = mix(mix(glass, glass * 0.55, spandrel), srgb(ALUMINUM) * 0.9, mullion);
		s.glass = 0.85 * (1.0 - mullion) * (1.0 - 0.8 * mech);
		float slats = stripes(p.x / 0.35, 0.5, fp.x / 0.35) * visible(0.35, pixel);
		color = mix(color, srgb(vec3(0.55, 0.60, 0.58)) * (1.0 - 0.3 * slats), mech);
		float column = centered_stripes(p.x / 6.0, 0.12, fp.x / 6.0);
		color = mix(color, mix(srgb(LM_GLASS), srgb(MARBLE) * 0.8, column), lobby);
		s.emission = srgb(LOBBY_LIGHT) * ((1.0 - column) * lobby * lobby_glow * city_lights);
		lit = (1.0 - spandrel) * (1.0 - mullion) * (1.0 - mech) * (1.0 - lobby);
		up = fract(p.y / floor_h);
		seed = 0.71;
	} else if (material == LM_UN_MARBLE) {
		color = stone * (0.97 + 0.04 * value_noise(p * 0.2))
				* (1.0 - 0.06 * max(stripes(p.y / 2.0, 0.02, fp.y / 2.0), stripes(p.x / 1.5, 0.02, fp.x / 1.5)) * visible(1.5, pixel));
		if (variant == 1) {
			// Translucent glass between marble piers, glowing at night.
			float pane = (1.0 - band(mod(p.x, 4.5), 0.0, 1.4, fp.x)) * band(p.y, 0.5, 1e4, fp.y);
			float bars = stripes(p.y / 1.6, 0.06, fp.y / 1.6);
			color = mix(color, mix(srgb(vec3(0.70, 0.78, 0.74)), color * 0.8, bars), pane);
			s.glass = pane * 0.5;
			s.emission = srgb(LAMP_SOFT) * (pane * (1.0 - bars) * 1.2 * city_lights);
		} else if (variant == 2) {
			// The Conference Building's ribbon windows.
			float pane = band(fract(p.y / 4.6), 0.35, 0.9, fp.y / 4.6) * step(0.8, p.y)
					* (1.0 - centered_stripes(p.x / 1.8, 0.07, fp.x / 1.8));
			color = mix(color, srgb(vec3(0.22, 0.30, 0.32)), pane);
			s.glass = pane * 0.8;
			cell_size = vec2(1.8, 4.6);
			cell = floor(p / cell_size);
			lit = pane;
			seed = 0.37;
		}
		flood = 0.35;
	} else if (material == LM_CITIGROUP) {
		if (variant == 0) {
			// Bands of aluminum and silvered glass.
			cell_size = vec2(1.5, 3.75);
			cell = floor(p / cell_size);
			float ribbon = band(fract(p.y / 3.75), 0.42, 0.88, fp.y / 3.75);
			float mullion = centered_stripes(p.x / 1.5, 0.05, fp.x / 1.5);
			vec3 glass = srgb(SILVER_GLASS) * mix(1.0, mix(0.92, 1.08, hash(cell)), visible(1.5, pixel));
			color = mix(stone, mix(glass, stone * 0.8, mullion), ribbon);
			s.glass = 0.45 + 0.45 * ribbon;
			lit = ribbon * (1.0 - mullion);
			seed = 0.55;
		} else if (variant == 1) {
			// The crown's slope: aluminum louvers, glowing white at night.
			color = stone * (1.0 - 0.18 * stripes(p.y / 0.8, 0.35, fp.y / 0.8) * visible(0.8, pixel));
			s.glass = 0.6;
			s.emission = color * (1.6 * landmark_flood * city_lights);
		} else if (variant == 2) {
			// Stilts and core, the lobby glass at the foot.
			float lobby = 1.0 - band(p.y, 8.0, 1e4, fp.y);
			color = mix(stone * (0.92 - 0.1 * stripes(p.x / 1.2, 0.05, fp.x / 1.2)), srgb(LM_GLASS), lobby * 0.8);
			s.glass = 0.5;
			s.emission = srgb(LOBBY_LIGHT) * (lobby * lobby_glow * city_lights);
		} else {
			// St. Peter's dark granite.
			flood = 0.4;
		}
	} else if (material == LM_HEARST) {
		// Blue-gray glass behind the diagrid: diagonals (u: m from the face's
		// middle) rising half a module each four-floor tier (16.4 m) from the
		// 10th floor, nodes on the corners every other tier, and ring beams.
		cell_size = vec2(1.5, 4.1);
		cell = floor(p / cell_size);
		float mullion = max(centered_stripes(p.x / 1.5, 0.04, fp.x / 1.5), stripes(p.y / 4.1, 0.07, fp.y / 4.1));
		vec3 glass = srgb(HEARST_GLASS) * mix(1.0, mix(0.92, 1.08, hash(cell)), visible(1.5, pixel));
		color = mix(glass, srgb(DIAGRID_STEEL) * 0.6, mullion * 0.7);
		float members = 0.0;
		if (variant == 0) {
			float n = max(1.0, floor(width / 12.5 + 0.5));
			float module_w = width / n;
			float t = (p.y - 34.0) / 16.4;
			float x = p.x / module_w + (mod(n, 2.0) < 0.5 ? 0.0 : 0.5);
			float f = fp.x / module_w + 0.5 * fp.y / 16.4;
			float w = 1.1 / module_w;
			members = max(max(centered_stripes(x - 0.5 * t, w, f), centered_stripes(x + 0.5 * t, w, f)),
					centered_stripes(t, 0.9 / 16.4, fp.y / 16.4)) * step(33.5, p.y);
		}
		color = mix(color, srgb(DIAGRID_STEEL), members);
		s.glass = mix(0.85 - 0.4 * mullion, 0.5, members);
		lit = (1.0 - members) * (1.0 - mullion);
		up = fract(p.y / 4.1);
		seed = 0.83;
	} else if (material == LM_HEARST_BASE) {
		if (variant == 1) {
			// The clerestory between the old base and the tower.
			float mullion = centered_stripes(p.x / 3.0, 0.12, fp.x / 3.0);
			color = mix(srgb(HEARST_GLASS) * 0.8, srgb(DIAGRID_STEEL), mullion);
			s.glass = 0.8 * (1.0 - mullion);
			s.emission = srgb(LOBBY_LIGHT) * ((1.0 - mullion) * 0.9 * city_lights);
		} else if (width < 3.5) {
			// A pylon: its sculpture group at the third floor.
			float figure = band(p.y, 9.0, 15.5, fp.y) * band(abs(p.x - 0.5 * width), -1.0, 0.45 * width, fp.x)
					* (0.6 + 0.4 * value_noise(p * 2.5));
			color = mix(color, stone * 0.75, figure);
			flood = 0.5;
		} else {
			// Windows in bays over arched openings; the cornice.
			float bay = width / max(1.0, floor(width / 3.6 + 0.5));
			float x = mod(p.x, bay) - 0.5 * bay;
			float pane = band(x, -0.75, 0.75, fp.x) * band(fract((p.y - 5.0) / 3.4), 0.2, 0.85, fp.y / 3.4) * band(p.y, 5.0, 18.6, fp.y);
			color *= 1.0 - 0.2 * stripes(p.y / 0.7, 0.06, fp.y / 0.7) * (1.0 - band(p.y, 4.8, 1e4, fp.y));
			color = mix(color, srgb(LM_GLASS), pane);
			s.glass = pane * 0.7;
			s.emission = srgb(LAMP_NEUTRAL) * (pane * 0.4 * city_lights);
			arch_q = vec2(x, p.y);
			arch = vec3(2.2, -1.0, 3.2);
			cornice = vec2(19.0, 21.0);
			flood = 0.5;
		}
	} else if (material == LM_MET) {
		if (variant == 1) {
			// Hunt's facade: three great arched entrances, framed, glazed in a grid.
			float x = p.x - 0.5 * width;
			float ax = x - clamp(floor(x / 17.0 + 0.5), -1.0, 1.0) * 17.0;
			color = mix(color, stone * 1.06, band(abs(ax), 3.7, 4.6, fp.x) * band(p.y, MET_FLOOR, MET_FLOOR + 14.3, fp.y));
			// The wall in shadow behind each pair of columns.
			color *= 1.0 - 0.28 * band(abs(abs(abs(x) - 17.5) - 8.0), -1.0, 2.0, fp.x) * step(MET_FLOOR, p.y) * step(p.y, MET_FLOOR + 16.8);
			arch_q = vec2(ax, p.y);
			arch = vec3(7.4, MET_FLOOR, MET_FLOOR + 10.0);
			cornice = vec2(MET_FLOOR + 16.8, MET_FLOOR + 19.6);
			flood = 1.1;
		} else if (variant == 0) {
			// The wings: a rusticated base, pilasters, tall windows, the cornice.
			float bay = width / max(1.0, floor(width / 6.0 + 0.5));
			float x = mod(p.x, bay) - 0.5 * bay;
			color *= 1.0 - 0.22 * stripes(p.y / 0.8, 0.06, fp.y / 0.8) * (1.0 - band(p.y, 7.0, 1e4, fp.y));
			color = mix(color, stone * 1.07, band(abs(x), 0.5 * bay - 0.6, 0.5 * bay + 0.1, fp.x) * band(p.y, 7.0, 21.0, fp.y));
			float pane = min(band(x, -1.1, 1.1, fp.x) * band(p.y, 9.0, 17.5, fp.y) + band(x, -0.8, 0.8, fp.x) * band(p.y, 3.0, 5.6, fp.y), 1.0);
			color = mix(color, srgb(LM_GLASS), pane);
			s.glass = pane * 0.7;
			cornice = vec2(21.0, 23.0);
			flood = 0.7;
		} else {
			// Plain walls; columns (narrow) fluted.
			color *= 1.0 - 0.08 * stripes(p.x / 0.35, 0.4, fp.x / 0.35) * visible(0.35, pixel) * step(width, 8.0);
			flood = 0.8;
		}
	} else if (material == LM_SKYLIGHT) {
		// Glass in white mullions, lit from inside at night.
		float grid = max(centered_stripes(p.x / 1.8, 0.07, fp.x / 1.8), centered_stripes(p.y / 2.2, 0.06, fp.y / 2.2));
		color = mix(srgb(vec3(0.30, 0.38, 0.44)), srgb(PAINT_WHITE) * 0.9, grid);
		s.glass = 0.85 * (1.0 - grid);
		s.emission = srgb(vec3(1.0, 0.95, 0.85)) * ((1.0 - grid) * 1.4 * city_lights);
	} else if (material == LM_VESSEL) {
		// Copper-clad flights of stairs crossing in a honeycomb (u: cells around,
		// a flight climbing half a cell a level), open between; the far side
		// shows through the openings.
		float level = p.y / 2.9;
		float f = fp.x + 0.5 * fp.y / 2.9;
		float flights = max(centered_stripes(p.x + 0.5 * level, 0.32, f), centered_stripes(p.x - 0.5 * level, 0.32, f));
		vec3 copper = srgb(COPPER_CLAD) * (0.9 + 0.15 * value_noise(p * vec2(4.0, 1.0)))
				* (1.0 - 0.2 * stripes(p.y / 0.18, 0.4, fp.y / 0.18) * visible(0.18, pixel));
		// Through the openings: the flights across the bowl, lit or in shade.
		vec3 beyond = srgb(COPPER_CLAD) * (variant == 1 ? 0.6 : mix(0.3, 0.55, hash(floor(vec2(p.x * 2.0 + level, level)))));
		color = mix(beyond, copper, flights);
		s.glass = 0.35 * flights;
		flood = 0.35;
	} else if (material == LM_WHITE_STEEL) {
		color = srgb(PAINT_WHITE) * (0.95 + 0.05 * value_noise(p * 0.5));
		s.glass = 0.35;
		if (variant == 1) {
			// The frieze: white lattice arches hung from a band, against the shade.
			float d = min(below_top, 3.2);
			float x = (fract(p.x / 2.4) - 0.5) * 2.4;
			float lattice = max(max(1.0 - band(d, 0.7, 1e4, fp.y), centered_stripes(p.x / 2.4, 0.1, fp.x / 2.4)),
					band(length(vec2(abs(x) - 1.2, d - 0.7)), 1.0, 1.2, pixel) * step(0.7, d));
			color = mix(srgb(vec3(0.20, 0.21, 0.23)), color, lattice);
		}
		s.emission = color * (0.5 * landmark_flood * city_lights);
	} else if (material == LM_STADIUM) {
		if (variant <= 1) {
			// Limestone with tall arched openings; YANKEE STADIUM in gold over the
			// main entrance.
			float bay = width / max(1.0, floor(width / 8.0 + 0.5));
			float x = mod(p.x, bay) - 0.5 * bay;
			arch_q = vec2(x, p.y);
			arch = vec3(min(4.6, bay * 0.6), 2.0, 13.0);
			color = mix(color, stone * 1.08, band(p.y, 17.0, 18.0, fp.y));
			if (variant == 1) {
				float q = p.x - 0.5 * width + 7.0 * 1.95;
				int i = int(floor(q / 1.95));
				word = (i >= 0 && i < 14) ? WORDS + i : -1;
				letter_q = vec2(q - float(i) * 1.95, p.y - 19.0);
				letter_h = 2.4;
				letter_color = srgb(GOLD_LEAF);
				letter_glow = 0.8 * city_lights;
			}
			flood = 0.55;
		} else if (variant == 2) {
			// The stands' risers: rows of blue seats.
			color = mix(srgb(vec3(0.55, 0.55, 0.53)), srgb(SEAT_BLUE), stripes(p.y / 0.85, 0.55, fp.y / 0.85));
		} else if (width < 5.0) {
			color = srgb(SIGN_STEEL);
		} else {
			// The video board: a dark frame round a picture that changes every 6 s.
			float frame = 1.0 - band(p.x, 0.8, width - 0.8, fp.x) * band(below_top, 0.8, 17.2, fp.y);
			float slide = floor(TIME / 6.0);
			vec3 picture = mix(ad_color(hash(vec2(slide, 3.0))), ad_color(hash(vec2(slide, 7.0))),
					smoothstep(0.3, 0.7, fract(p.x / width + 0.2 * sin(TIME * 0.5))));
			color = mix(picture, srgb(SIGN_STEEL), frame);
			s.emission = picture * ((1.0 - frame) * (0.5 + 1.5 * city_lights));
			text_h = frame < 0.5 ? 3.0 : 0.0;
			text_q = vec2(p.x - 3.0, 12.0 - below_top);
			text_salt = slide;
			text_color = vec3(1.0);
			text_glow = 0.5 + 1.5 * city_lights;
		}
	} else if (material == LM_UNISPHERE) {
		color = srgb(STAINLESS) * (0.92 + 0.08 * value_noise(p * 0.3));
		s.glass = 0.7;
		if (variant >= 1) {
			// uv: degrees east and north. Plates over the land (rigidized steel);
			// painted on a whole globe, the oceans are the dark lattice.
			float land = variant == 2 ? 1.0 : unisphere_land(p);
			float grid = max(centered_stripes(p.x / 20.0, 0.03, fp.x / 20.0), centered_stripes(p.y / 20.0, 0.04, fp.y / 20.0));
			color = mix(mix(srgb(vec3(0.10, 0.13, 0.17)), srgb(STAINLESS), grid), color * 1.03, land);
			s.glass = mix(0.5 * grid, 0.75, land);
		}
		flood = 0.45;
		flood_color = srgb(FLOOD_COOL);
	} else if (material == LM_RIDE) {
		if (variant == 3) {
			// The Wonder Wheel's cars (u: 10 m per kind: fixed white, red and blue
			// swinging ones) and its sign.
			float kind = floor(p.x / 10.0);
			float x = p.x - kind * 10.0;
			if (kind > 2.5) {
				color = srgb(vec3(0.10, 0.10, 0.12));
				float q = x - 6.0 + 6.0 * 0.95;
				int i = int(floor(q / 0.95));
				word = (i >= 0 && i < 12 && width > 6.0) ? WONDER + i : -1;
				letter_q = vec2(q - float(i) * 0.95, p.y - 0.4);
				letter_h = 1.2;
				letter_color = srgb(vec3(1.0, 0.55, 0.12));
				letter_glow = 0.6 + 3.0 * city_lights;
			} else {
				vec3 body = kind < 0.5 ? srgb(PAINT_WHITE) : (kind < 1.5 ? srgb(RIDE_RED) : srgb(RIDE_BLUE));
				vec3 trim = kind < 0.5 ? srgb(vec3(0.85, 0.20, 0.15)) : srgb(vec3(0.98, 0.82, 0.20));
				float window = band(p.y, 1.0, 1.9, fp.y) * band(x, 0.25, 1.95, fp.x);
				color = mix(body, trim, min(band(p.y, -1.0, 0.35, fp.y) + band(p.y, 2.1, 9.0, fp.y), 1.0));
				color = mix(color, srgb(vec3(0.15, 0.18, 0.22)), window);
				s.glass = window * 0.7;
				s.emission = srgb(LAMP_WARM) * (window * 0.8 * city_lights);
			}
		} else {
			color = (variant == 0 ? srgb(PAINT_WHITE) : (variant == 1 ? srgb(RIDE_BLUE) : srgb(RIDE_RED)))
					* (0.93 + 0.07 * value_noise(p * 2.0));
			s.glass = 0.25;
			if (variant != 1) {
				// At night bulbs chase along the wheel's members (p.y: m along them);
				// the Parachute Jump's LEDs roll in colored waves up the tower.
				float on = variant == 2 ? 1.0 : centered_stripes(p.y / 0.9, 0.3, fp.y / 0.9);
				float hue = variant == 2 ? scene.y * 0.02 - TIME * 0.12 : floor(p.y / 0.9) * 0.37 + floor(TIME * 2.0) * 0.25;
				vec3 led = 0.5 + 0.5 * cos(2.0 * PI * (fract(hue) + vec3(0.0, 0.33, 0.67)));
				s.emission = srgb(led) * (on * (variant == 2 ? 1.6 : 2.5) * city_lights);
			}
		}
	} else if (material == LM_MARQUEE) {
		if (variant == 0) {
			// The marquee: a dark band edged in red, bulbs chasing round the
			// corner, the hall's name in white light.
			float q = p.y - 4.4;
			float edge = 1.0 - band(q, 0.4, 2.6, fp.y);
			float bulbs = centered_stripes(p.x / 0.5, 0.45, fp.x / 0.5) * step(0.45, fract(p.x / 1.5 - TIME * 1.5)) * edge;
			color = mix(srgb(vec3(0.07, 0.07, 0.08)), srgb(vec3(0.62, 0.10, 0.09)), edge);
			s.emission = srgb(vec3(1.0, 0.85, 0.55)) * (bulbs * (0.3 + 3.0 * city_lights));
			float x = mod(p.x, 27.0) - 2.5;
			int i = int(floor(x / 1.05));
			word = (i >= 0 && i < 21) ? RADIO_CITY + i : -1;
			letter_q = vec2(x - float(i) * 1.05, q - 0.85);
			letter_h = 1.3;
			letter_color = vec3(0.95);
			letter_glow = 0.6 + 3.5 * city_lights;
		} else {
			// The vertical sign: RADIO CITY stacked in red neon, a gold rim.
			color = srgb(vec3(0.18, 0.08, 0.07));
			if (width > 3.0) {
				float rim = 1.0 - band(p.x, 0.2, width - 0.2, fp.x) * band(p.y, 0.2, 17.8, fp.y);
				color = mix(color, srgb(vec3(0.85, 0.70, 0.35)), rim);
				s.emission = srgb(vec3(1.0, 0.8, 0.4)) * (rim * 1.5 * city_lights);
				int i = int(floor((18.0 - p.y) / 1.8));
				word = (i >= 0 && i < 10) ? RADIO_CITY + i : -1;
				letter_q = vec2(p.x - 1.7, p.y - (16.2 - float(i) * 1.8) - 0.1);
				letter_h = 1.6;
				letter_color = srgb(vec3(1.0, 0.16, 0.12));
				letter_glow = 0.8 + 4.0 * city_lights;
			}
		}
	}

	// The shared helpers, once each.
	if (arch.x > 0.0) {
		// An arched opening (dark glass, or bronze doors under a glazed head;
		// a Gothic portal steps in twice to its doors).
		float inset = lm_arch_inset(arch_q, arch.x, arch.y, arch.z, pointed);
		float open = clamp(inset / pixel + 0.5, 0.0, 1.0);
		vec3 glass = srgb(pointed ? vec3(0.12, 0.12, 0.15) : LM_GLASS);
		if (material == LM_NYPL && variant == 1) {
			glass = mix(srgb(BRONZE), srgb(LM_GLASS), step(7.4, p.y));
		} else if (material == LM_MET || material == LM_STADIUM) {
			float grid = max(centered_stripes(arch_q.x / 1.25, 0.08, fp.x / 1.25), centered_stripes(p.y / 1.6, 0.06, fp.y / 1.6));
			glass = mix(glass, stone * 0.6, grid);
		}
		if (pointed) {
			// Gothic openings get a molded frame; niches and pierced tracery are
			// open, not glazed.
			color *= 1.0 - 0.3 * band(inset, -0.4, -0.15, pixel);
		}
		color = mix(color, glass, open);
		s.glass = max(s.glass, open * (pointed ? 0.4 * glazed : 0.6));
		s.emission += srgb(pointed ? LAMP_WARM : SHOP_LIGHT) * (open * (pointed ? 0.35 * glazed : 0.8) * city_lights);
	}
	if (cornice.y > cornice.x) {
		color = mix(color, lm_cornice(stone, p, fp, cornice.x, cornice.y), band(p.y, cornice.x, cornice.y, fp.y));
	}
	if (lit > 0.0 && city_lights > 0.0) {
		s.emission += window_light(MODERN_OFFICE, true, cell, seed, cell_size / fp, up) * (lit * window_glow * city_lights);
	}
	if (word >= 0 || text_h > 0.0) {
		// A letter of a word, or of a line of text (a face has one or the other,
		// so glyph() is compiled once). A line of text's letters are made up,
		// some left out for the gaps between words; up close they're glyphs,
		// from further away solid blocks (the bars a sign's text reads as from
		// down the street), then their average.
		vec2 box = vec2(letter_h * 0.62, letter_h);
		vec2 g = letter_q / box;
		vec2 fg = fp / box;
		int index = min(word, 62);
		float pitch = text_h * 0.8;
		float h = 0.0;
		if (text_h > 0.0) {
			float cell = floor(text_q.x / pitch);
			h = hash(vec2(cell, text_salt));
			g = vec2((text_q.x - cell * pitch) / (text_h * 0.6), text_q.y / text_h);
			fg = fp / vec2(text_h * 0.6, text_h);
			index = pick(fract(h * 13.7), 16);
			letter_color = text_color;
			letter_glow = text_glow;
		}
		float cover = glyph(LETTERS[max(index, 0)], g, fg);
		if (text_h > 0.0) {
			cover = band(text_q.y, 0.0, text_h, fp.y) * mix(0.45 * 0.88, step(0.12, h) * band(g.x, 0.0, 1.0, fg.x)
					* mix(0.6, cover, smoothstep(5.0, 10.0, text_h / fp.y)), smoothstep(1.5, 4.0, pitch / fp.x)) * 0.9;
		} else {
			s.glass = max(s.glass, cover * 0.5);
		}
		color = mix(color, letter_color, cover);
		s.emission += letter_color * (cover * letter_glow);
	}
	s.emission += color * flood_color * (flood * landmark_flood * city_lights);
	s.albedo = color;
	return s;
}

// The ball field at Yankee Stadium. uv: m from home plate toward second base
// (center field), m to its left. Mowed turf, the skinned infield arc (29 m
// from the pitcher's rubber), the grass diamond inside the base paths (27.4 m),
// the mound, home plate's circle, the warning track before the fences (97 m
// down the lines, 124 m to center), the foul lines.
vec3 ballfield(vec2 p, vec2 fp) {
	float pixel = max(fp.x, fp.y);
	float r = length(p);
	float angle = atan(p.y, p.x);
	vec3 grass = srgb(TURF) * (0.92 + 0.1 * value_noise(p * 0.15));
	float mow = stripes((p.x + p.y) / 9.0, 0.5, (fp.x + fp.y) / 9.0) + stripes((p.x - p.y) / 9.0, 0.5, (fp.x + fp.y) / 9.0);
	grass *= 0.94 + 0.05 * mow * visible(4.5, pixel);
	vec2 rubber = vec2(18.4, 0.0);
	float diamond = abs(p.x - 19.4) + abs(p.y);
	float arc = (1.0 - smoothstep(28.9 - pixel, 28.9 + pixel, length(p - rubber))) * step(abs(angle), 0.9) * step(0.0, p.x);
	float grass_diamond = 1.0 - smoothstep(18.0 - pixel, 18.0 + pixel, diamond);
	float paths = band(diamond, 18.0, 20.0, pixel);
	float plate = 1.0 - smoothstep(3.9 - pixel, 3.9 + pixel, r);
	float mound = 1.0 - smoothstep(2.7 - pixel, 2.7 + pixel, length(p - rubber));
	float c = cos(2.0 * clamp(angle, -0.785, 0.785));
	float fence = 97.0 + 27.0 * c * c;
	float track = band(r, fence - 4.6, fence + 1.5, pixel) * step(abs(angle), 0.8);
	float dirt = max(max(arc * (1.0 - grass_diamond), paths * step(abs(angle), 0.8)), max(max(plate, mound), track));
	vec3 color = mix(grass, srgb(INFIELD_DIRT) * (0.95 + 0.08 * value_noise(p * 0.7)), clamp(dirt, 0.0, 1.0));
	float chalk = (1.0 - smoothstep(0.06, 0.06 + pixel, abs(abs(p.y) - p.x) * 0.7071)) * step(0.0, p.x) * step(r, fence);
	return mix(color, vec3(0.92), chalk * visible(0.12, pixel));
}

// A roof of the second batch: slate, skylights, copper cladding, a ball field,
// seats, a fountain pool, white concrete, steel; paving otherwise.
Surface landmark_roof_2(int material, int variant, vec2 p, vec2 fp) {
	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	float pixel = max(fp.x, fp.y);
	vec3 color;
	if (material == LM_SLATE) {
		// Slates in courses (on pitched roofs uv runs along the eaves and up).
		float course = floor(p.y / 0.32);
		float joints = max(stripes(p.y / 0.32, 0.12, fp.y / 0.32), stripes(p.x / 0.5 + 0.5 * mod(course, 2.0), 0.06, fp.x / 0.5))
				* visible(0.32, pixel);
		color = srgb(SLATE_GRAY) * (0.92 + 0.12 * value_noise(p * 0.6)) * (1.0 - 0.2 * joints);
	} else if (material == LM_SKYLIGHT) {
		// Rows of skylights in gray roofing, in blocks.
		vec2 block = floor(p / vec2(21.0, 16.0));
		float glass = band(fract(p.x / 7.0), 0.15, 0.45, fp.x / 7.0) * step(0.35, hash(block + 5.3))
				* band(fract(p.y / 16.0), 0.08, 0.92, fp.y / 16.0);
		float frames = centered_stripes(p.y / 2.0, 0.06, fp.y / 2.0);
		color = mix(srgb(ROOF_GRAVEL) * (0.95 + 0.1 * hash(block)), mix(srgb(vec3(0.42, 0.52, 0.58)), srgb(PAINT_WHITE) * 0.8, frames), glass);
		s.glass = glass * 0.8;
		s.emission = srgb(LAMP_SOFT) * (glass * 0.4 * city_lights);
	} else if (material == LM_PLAYFIELD) {
		if (variant == 0) {
			// The ball field, under the stadium's lights at night.
			color = ballfield(p, fp);
			s.emission = color * (0.7 * city_lights);
		} else if (variant == 1) {
			// Seats in rows, aisles of concrete.
			float seats = stripes(p.x / 0.55, 0.75, fp.x / 0.55) * stripes(p.y / 0.85, 0.6, fp.y / 0.85);
			color = mix(srgb(vec3(0.52, 0.52, 0.50)), srgb(SEAT_BLUE), mix(0.45, seats, visible(0.55, pixel)));
		} else if (variant == 2) {
			// A fountain pool: rippling water, jets of foam round its edge, lit at night.
			float r = length(p);
			color = srgb(POOL_WATER) * (0.88 + 0.16 * value_noise(p * 0.35 + vec2(TIME * 0.3, 0.0)));
			float jets = band(r, 44.0, 46.0, pixel) * centered_stripes(atan(p.y, p.x) / (2.0 * PI) * 48.0, 0.4, pixel / max(r, 1.0) * 7.6);
			color = mix(color, vec3(0.95), jets * (0.7 + 0.3 * sin(TIME * 3.0 + r)));
			s.glass = 0.6 * (1.0 - jets);
			s.emission = mix(srgb(vec3(0.5, 0.8, 1.0)), vec3(1.0), jets) * ((0.3 + jets) * city_lights);
		} else {
			// A meadow: long grasses, lighter and yellower in patches.
			color = mix(srgb(vec3(0.33, 0.47, 0.22)), srgb(vec3(0.50, 0.53, 0.30)), 0.7 * value_noise(p * 0.12));
		}
	} else if (material == LM_GUGGENHEIM || material == LM_WHITE_STEEL) {
		color = srgb(GUGG_WHITE) * 0.95;
	} else if (material == LM_CATHEDRAL || material == LM_GOTHIC) {
		color = srgb(CATHEDRAL_MARBLE) * 0.95;
	} else if (material == LM_VESSEL) {
		color = srgb(COPPER_CLAD) * (0.9 + 0.12 * value_noise(p * 2.0));
		s.glass = 0.3;
	} else if (material == LM_UNISPHERE) {
		color = srgb(STAINLESS);
		s.glass = 0.7;
	} else {
		// Paving slabs on terraces and decks.
		float joints = max(stripes(p.x / 1.2, 0.04, fp.x / 1.2), stripes(p.y / 1.2, 0.04, fp.y / 1.2)) * visible(1.2, pixel);
		color = srgb(PAVING_STONE) * (0.92 + 0.12 * value_noise(p * 0.4)) * (1.0 - 0.18 * joints);
	}
	s.albedo = color;
	return s;
}

void vertex() {
	float h = (UV.y + 1.0) * 0.01;
	float h2 = h * h;
	wall_moments = vec4(h, h2, h2 * h, h2 * h2);
	landmark_data = vec2(floor(UV2.x + 0.5), floor(UV2.y + 0.0005));
}

void fragment() {
	vec2 data = floor(landmark_data + 0.5);
	int code = int(data.x);
	int material = code % 64;
	int flags = code / 64;
	int param = int(data.y);
	vec2 footprint = max(fwidth(UV), vec2(1e-4));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 scene_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	Surface s;
	float occlusion = 1.0;
	// Materials whose walls' UV.y is the height above the ground.
	bool height_uv = material != LM_WHITE_STEEL && material != LM_UNISPHERE && material != LM_RIDE;
	bool roof = (flags & ROOF) != 0;
	if (roof) {
		s = landmark_roof_2(material, param % 4, UV, footprint);
	} else {
		s = landmark_wall_2(material, param % 4, UV, footprint, float(param / 4) * 0.1,
				wall_top_distance(wall_moments, UV.y), scene_position);
		occlusion = height_uv ? mix(canyon_occlusion, 1.0, smoothstep(0.0, canyon_height, UV.y)) : 1.0;
	}

	// Glass reflects the sky, more at grazing angles.
	float n_dot_v = clamp(dot(world_normal, world_view), 0.0, 1.0);
	float fresnel = mix(0.3, 1.0, pow(1.0 - n_dot_v, 3.0));
	float mirror = clamp(s.glass * glass_reflection, 0.0, 1.0) * fresnel;
	vec3 reflection = sky_reflection(reflect(-world_view, world_normal)) * mirror;

	ALBEDO = toon_night_albedo(s.albedo * (1.0 - 0.6 * mirror));
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + s.emission + reflection;
	toon_glint = s.glass;

	// Street lights on the feet of the walls near them.
	if (city_lights > 0.0 && !roof && height_uv) {
		float reach = 1.0 - smoothstep(street_light_reach.x, street_light_reach.y, UV.y);
		if (reach > 0.0) {
			EMISSION += ALBEDO * street_light_at(scene_position.xz, length(VERTEX)) * (reach * city_lights);
		}
	}
}
