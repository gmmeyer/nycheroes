// Buildings, drawn as stylized New York facades from per-building data
// (tools/citygen/facades.py and build_tiles.py). Per vertex:
//   UV    walls: (meters along the wall, meters above the building's base;
//         the walls' feet are sunk 1 m below the base); flat roofs: world
//         x/z; houses' pitched roofs: (meters along the eaves, meters up
//         the slope). Up close, flat roofs have parapets: the walls rise
//         PARAPET_HEIGHT above the roof, with inner faces.
//   UV2.x archetype + 64 * flags, a whole number (see the constants below).
//   UV2.y floor height in decimeters + the building's random seed (0..0.999).
// Each building type picks a palette and a window system (punched windows with
// lintels, arched loft windows, ribbon windows, curtain walls); street fronts
// add storefronts with awnings, fire escapes and cornices. Every detail is
// box-filtered or faded by its size on screen, so far away a facade settles
// into its average color instead of shimmering.
// Lighting is the shared toon model (toon.gdshaderinc); glass also reflects a
// simple sky. With an aerial photo (?aerial=1), roofs show it.
// At night (the time of day: shaders/night.gdshaderinc) a share of windows is
// lit, by building type and hour (offices empty out late, homes fill up in
// the evening; offices' glass walls in whole floors and runs of bays), shops,
// signs, lobbies and front doors glow, street lights light the feet of the
// walls, floodlights wash landmarks' setbacks, and glass reflects the night
// sky. Which windows are lit is a hash of the window, so it never changes as
// the camera moves; small windows settle into their floor's and building's
// average glow in the distance.
// Street walls in Times Square's sign district (the SIGNS flag) are covered,
// from above the shop fronts up to 40-60 m, in billboards and LED screens
// (sign_wall()): big screens and tall banners in dark steel, some ringed in
// neon or chasing bulbs, with a news ticker along the bottom of most walls,
// showing cartoon ads that change every few seconds. They glow by day and
// blaze at night, washing the facade above them in their colors; only SIGNS
// walls pay for any of it.
shader_type spatial;
render_mode ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/aerial.gdshaderinc"

// Building types (UV2.x % 64), in the order facades.py numbers them.
const int HOUSE = 0;
const int ROWHOUSE = 1;
const int WALKUP = 2;
const int PREWAR_APARTMENT = 3;
const int POSTWAR_APARTMENT = 4;
const int MODERN_RESIDENTIAL = 5;
const int PREWAR_OFFICE = 6;
const int MIDCENTURY_OFFICE = 7;
const int MODERN_OFFICE = 8;
const int LOFT = 9;
const int STORE = 10;
const int INDUSTRIAL = 11;
const int INSTITUTION = 12;
const int HOTEL = 13;
const int OTHER = 14;
const int UNKNOWN = 15;

// Flags (UV2.x / 64).
const int ROOF = 1;
const int FRONT = 2;
const int RETAIL = 4;
const int FIRE_ESCAPES = 8;
const int CORNICE = 16;
const int LANDMARK = 32;
const int PARAPET = 64;          // the wall's top PARAPET_HEIGHT stands above its roof
const int PARAPET_INSIDE = 128;  // the inner side of a parapet, facing the roof
const int SIGNS = 256;           // a street wall in Times Square's sign district: billboards
// Same as tools/citygen/facades.py.
const float PARAPET_HEIGHT = 1.0;

// Window systems.
const int PUNCHED = 0;   // separate windows in a masonry wall
const int ARCHED = 1;    // tall round-topped windows (cast-iron lofts)
const int RIBBON = 2;    // continuous horizontal bands of windows
const int CURTAIN = 3;   // all glass, with mullions and spandrel bands
const int FACTORY = 4;   // big steel windows with many small panes

// Wall surfaces.
const int BRICK = 0;
const int STONE = 1;
const int SIDING = 2;
const int SMOOTH = 3;

// Palettes, in sRGB.
const vec3 RED_BRICK[6] = vec3[](vec3(0.68, 0.35, 0.27), vec3(0.72, 0.42, 0.31), vec3(0.62, 0.31, 0.25),
		vec3(0.75, 0.47, 0.33), vec3(0.65, 0.38, 0.30), vec3(0.58, 0.31, 0.26));
const vec3 BROWNSTONE[4] = vec3[](vec3(0.53, 0.37, 0.30), vec3(0.58, 0.42, 0.33), vec3(0.48, 0.33, 0.27),
		vec3(0.62, 0.45, 0.35));
const vec3 BUFF_BRICK[4] = vec3[](vec3(0.80, 0.70, 0.55), vec3(0.85, 0.77, 0.63), vec3(0.76, 0.65, 0.50),
		vec3(0.80, 0.69, 0.52));
const vec3 WHITE_BRICK[3] = vec3[](vec3(0.86, 0.84, 0.78), vec3(0.90, 0.88, 0.83), vec3(0.80, 0.78, 0.72));
const vec3 LIMESTONE[4] = vec3[](vec3(0.89, 0.83, 0.70), vec3(0.85, 0.78, 0.64), vec3(0.91, 0.87, 0.78),
		vec3(0.80, 0.74, 0.60));
// Landmark stone: pale gray Indiana limestone; gray, pink and dark granite;
// cream and ivory glazed terracotta.
const vec3 LANDMARK_LIMESTONE[3] = vec3[](vec3(0.86, 0.83, 0.76), vec3(0.82, 0.80, 0.74), vec3(0.89, 0.87, 0.81));
const vec3 GRANITE[3] = vec3[](vec3(0.72, 0.71, 0.68), vec3(0.75, 0.64, 0.58), vec3(0.55, 0.54, 0.52));
const vec3 TERRACOTTA[3] = vec3[](vec3(0.93, 0.89, 0.78), vec3(0.91, 0.86, 0.74), vec3(0.95, 0.92, 0.84));
const vec3 CAST_IRON[5] = vec3[](vec3(0.91, 0.88, 0.80), vec3(0.80, 0.79, 0.74), vec3(0.66, 0.73, 0.66),
		vec3(0.71, 0.76, 0.81), vec3(0.86, 0.79, 0.63));
const vec3 SIDING_PAINT[6] = vec3[](vec3(0.90, 0.88, 0.83), vec3(0.76, 0.82, 0.86), vec3(0.80, 0.83, 0.71),
		vec3(0.87, 0.81, 0.68), vec3(0.70, 0.75, 0.78), vec3(0.91, 0.84, 0.70));
const vec3 STUCCO[5] = vec3[](vec3(0.86, 0.82, 0.73), vec3(0.76, 0.76, 0.73), vec3(0.92, 0.91, 0.87),
		vec3(0.90, 0.84, 0.62), vec3(0.74, 0.79, 0.70));
const vec3 GLASS_DARK[4] = vec3[](vec3(0.27, 0.34, 0.42), vec3(0.24, 0.31, 0.36), vec3(0.30, 0.36, 0.44),
		vec3(0.28, 0.33, 0.37));
const vec3 GLASS_TOWER[5] = vec3[](vec3(0.30, 0.47, 0.58), vec3(0.27, 0.43, 0.47), vec3(0.36, 0.52, 0.64),
		vec3(0.40, 0.53, 0.57), vec3(0.26, 0.36, 0.45));
const vec3 SPANDREL[5] = vec3[](vec3(0.30, 0.36, 0.36), vec3(0.24, 0.26, 0.29), vec3(0.58, 0.65, 0.70),
		vec3(0.84, 0.85, 0.82), vec3(0.44, 0.38, 0.31));
const vec3 FRAME_PAINT[5] = vec3[](vec3(0.93, 0.92, 0.88), vec3(0.14, 0.14, 0.14), vec3(0.17, 0.25, 0.20),
		vec3(0.30, 0.23, 0.17), vec3(0.93, 0.92, 0.88));
const vec3 SHADES[4] = vec3[](vec3(0.92, 0.88, 0.76), vec3(0.95, 0.94, 0.90), vec3(0.82, 0.74, 0.60),
		vec3(0.72, 0.80, 0.86));
const vec3 AWNING[8] = vec3[](vec3(0.74, 0.20, 0.17), vec3(0.15, 0.47, 0.29), vec3(0.15, 0.24, 0.43),
		vec3(0.84, 0.47, 0.15), vec3(0.47, 0.15, 0.21), vec3(0.10, 0.45, 0.45), vec3(0.85, 0.65, 0.15),
		vec3(0.18, 0.18, 0.19));
const vec3 SIGN[6] = vec3[](vec3(0.12, 0.13, 0.15), vec3(0.62, 0.12, 0.12), vec3(0.10, 0.30, 0.20),
		vec3(0.92, 0.90, 0.84), vec3(0.12, 0.20, 0.40), vec3(0.88, 0.70, 0.18));
const vec3 CORNICE_PAINT[4] = vec3[](vec3(0.25, 0.29, 0.28), vec3(0.17, 0.17, 0.18), vec3(0.85, 0.80, 0.69),
		vec3(0.55, 0.36, 0.24));
const vec3 TRIM_STONE = vec3(0.90, 0.87, 0.79);
const vec3 MORTAR = vec3(0.80, 0.79, 0.75);
const vec3 IRON = vec3(0.12, 0.14, 0.14);
const vec3 AIR_CONDITIONER = vec3(0.80, 0.80, 0.76);
// Shop windows: dark glass up top, a warm lit interior lower down, and
// goods on display.
const vec3 SHOP_GLASS = vec3(0.20, 0.23, 0.26);
const vec3 SHOP_INTERIOR = vec3(0.66, 0.54, 0.38);
const vec3 GOODS[5] = vec3[](vec3(0.76, 0.32, 0.26), vec3(0.30, 0.50, 0.72), vec3(0.88, 0.76, 0.40),
		vec3(0.40, 0.62, 0.36), vec3(0.88, 0.87, 0.82));
const vec3 SHOP_LIGHT = vec3(1.0, 0.82, 0.55);
const vec3 METAL_DOOR = vec3(0.62, 0.63, 0.62);
// Lights in windows at night, in sRGB: incandescent, soft warm white, cool
// white (LEDs, offices' fluorescents), neutral white, a TV's blue; office
// lobbies; floodlights on landmarks.
const vec3 LAMP_WARM = vec3(1.0, 0.70, 0.40);
const vec3 LAMP_SOFT = vec3(1.0, 0.84, 0.62);
const vec3 LAMP_COOL = vec3(0.84, 0.90, 0.96);
const vec3 LAMP_NEUTRAL = vec3(1.0, 0.88, 0.68);
const vec3 TV_BLUE = vec3(0.45, 0.58, 1.0);
const vec3 LOBBY_LIGHT = vec3(1.0, 0.88, 0.68);
const vec3 FLOODLIGHT = vec3(1.0, 0.86, 0.62);

// Times Square's screens, in sRGB: cartoon-bright ad colors (hot pink, cyan,
// yellow, violet, orange, green, blue, red), neon tubes, the dark steel
// between screens, and the news ticker's band and letters.
const vec3 AD_COLORS[8] = vec3[](vec3(1.00, 0.16, 0.56), vec3(0.08, 0.78, 1.00), vec3(1.00, 0.84, 0.08),
		vec3(0.58, 0.22, 1.00), vec3(1.00, 0.44, 0.06), vec3(0.18, 0.92, 0.36), vec3(0.12, 0.32, 1.00),
		vec3(1.00, 0.12, 0.16));
const vec3 NEON[5] = vec3[](vec3(1.0, 0.22, 0.70), vec3(0.20, 0.92, 1.0), vec3(1.0, 0.88, 0.25),
		vec3(0.45, 1.0, 0.30), vec3(1.0, 0.40, 0.12));
const vec3 SIGN_STEEL = vec3(0.10, 0.10, 0.12);
const vec3 SCREEN_OFF = vec3(0.05, 0.05, 0.06);
const vec3 AD_NIGHT_BLUE = vec3(0.03, 0.04, 0.12);
const vec3 TICKER_BAND = vec3(0.02, 0.03, 0.09);
const vec3 TICKER_TEXT[3] = vec3[](vec3(1.0, 0.76, 0.22), vec3(0.95, 0.96, 1.0), vec3(0.35, 0.95, 1.0));
// Letter-like glyphs as seven-segment codes (bits: 1 top, 2 upper right,
// 4 lower right, 8 bottom, 16 lower left, 32 upper left, 64 middle): A b C d
// E F H J L o P S U y O 2.
const int GLYPHS[16] = int[](119, 124, 57, 94, 121, 113, 118, 30, 56, 92, 115, 109, 62, 110, 63, 91);
// What a screen shows (screen()).
const int AD_GRADIENT = 0;  // a slow color gradient with a big pulsing disc and a line of text
const int AD_TEXT = 1;      // lines of big blocky text typing themselves out
const int AD_BURST = 2;     // a turning sunburst behind a disc
const int AD_WAVES = 3;     // wavy color bands rolling up, with a headline
const int AD_WORD = 4;      // one huge glowing word on night blue
const int AD_PRODUCT = 5;   // a cartoon can, bobbing (tall screens)
const int AD_COLUMN = 6;    // letters stacked down a vertical banner

// Roofs, in sRGB: tar, silver coating, membrane, gravel, shingles.
const vec3 ROOF_TAR = vec3(0.30, 0.29, 0.29);
const vec3 ROOF_SILVER = vec3(0.70, 0.71, 0.70);
const vec3 ROOF_MEMBRANE = vec3(0.74, 0.73, 0.70);
const vec3 ROOF_GRAVEL = vec3(0.56, 0.54, 0.50);
const vec3 ROOF_SHINGLES[3] = vec3[](vec3(0.36, 0.31, 0.29), vec3(0.40, 0.39, 0.38), vec3(0.47, 0.29, 0.24));

// Far tiles (lod1, lod2) set this: their walls are merged blocks with no
// street-front flags, so every wall gets windows.
uniform bool merged_blocks = false;
// How mirror-like glass is overall (each building type scales it).
uniform float glass_reflection : hint_range(0.0, 2.0) = 1.3;
// The sky that glass reflects, in sRGB: overhead, at the horizon, and the
// city below the horizon.
uniform vec3 reflect_zenith : source_color = vec3(0.36, 0.58, 0.85);
uniform vec3 reflect_horizon : source_color = vec3(0.80, 0.87, 0.92);
uniform vec3 reflect_ground : source_color = vec3(0.30, 0.32, 0.36);
// Walls get less sky light low down in the street canyons: ambient light at
// the base, rising to full by this height (m).
uniform float canyon_occlusion : hint_range(0.0, 1.0) = 0.85;
uniform float canyon_height = 25.0;
// Lit shop windows glow a little even by day.
uniform float shop_glow = 0.35;
// How far tiny far-off window grids are pulled toward their average color.
uniform float distance_calm : hint_range(0.0, 1.0) = 0.6;
// Night: how bright lit windows, shop windows (times their day glow), lit
// signs, lobbies and front doors are.
uniform float window_glow = 1.0;
uniform float shop_night_glow = 5.0;
uniform float sign_glow = 1.2;
uniform float lobby_glow = 1.4;
// Street lights reach this high up the walls (m above the building's base).
uniform vec2 street_light_reach = vec2(3.0, 13.0);
// Landmarks' setbacks from this high (m) up are floodlit from the roof below,
// fading out over floodlight_reach meters up the wall.
uniform float floodlight_min_height = 40.0;
uniform float floodlight_reach = 28.0;
uniform float floodlight_strength = 1.3;
// Times Square's billboards and screens (SIGNS walls): how bright they are by
// day and at night, their neon tubes' extra glow, how high the screens go
// (m above the base, picked per building in this range, or less where the
// wall is lower), how far their colored light washes up the facade above
// them at night (m), and how fast the news tickers run (m/s).
uniform float sign_day_glow = 1.1;
uniform float sign_night_glow = 1.4;
uniform float neon_glow = 2.2;
uniform vec2 sign_top_range = vec2(40.0, 60.0);
uniform float sign_wash_reach = 16.0;
uniform float ticker_speed = 4.5;
// What glass reflects at dusk and at night, in sRGB: overhead, at the
// horizon, and the city below.
uniform vec3 dusk_reflect_zenith : source_color = vec3(0.30, 0.38, 0.62);
uniform vec3 dusk_reflect_horizon : source_color = vec3(0.98, 0.70, 0.52);
uniform vec3 dusk_reflect_ground : source_color = vec3(0.30, 0.27, 0.30);
uniform vec3 night_reflect_zenith : source_color = vec3(0.03, 0.05, 0.12);
uniform vec3 night_reflect_horizon : source_color = vec3(0.30, 0.21, 0.22);
uniform vec3 night_reflect_ground : source_color = vec3(0.13, 0.10, 0.09);

// Moments of the wall height at the vertices (see wall_top_distance).
varying vec4 wall_moments;
// UV2 decoded into whole numbers in the vertex shader: (archetype + 64 *
// flags, floor height in dm, seed in 1024ths). Interpolation can nudge a
// value by a millionth, which a hash would blow up into per-pixel noise, so
// fragments round them back.
varying vec3 building_data;

struct Facade {
	vec3 wall;          // main wall color (linear)
	vec3 trim;          // lintels, sills, coping, string courses
	vec3 frame;         // window frames and mullions
	vec3 glass;         // glass, before reflections
	vec3 accent;        // spandrels, shutters, balcony slabs
	vec3 base;          // the stone base of prewar buildings
	vec3 cornice;       // cornice color
	int windows;        // PUNCHED, ARCHED, RIBBON, CURTAIN or FACTORY
	int surface;        // BRICK, STONE, SIDING or SMOOTH
	float bay;          // window spacing (m)
	float window_width; // m
	float window_height; // fraction of the floor height
	float sill;         // window bottom above the floor, fraction of the floor height
	float frame_width;  // m
	float mullion;      // curtain and ribbon walls: mullion width (m)
	float spandrel;     // curtain walls: opaque band at each floor (m)
	float reflect;      // how mirror-like the glass is
	float front_open;   // share of bays with windows on street fronts
	float side_open;    // ... and on side and back walls (lot lines are blank)
	float base_floors;  // floors in the stone base
	float shades;       // share of windows with a shade pulled down
	float air_conditioners; // share of windows with an air conditioner
	float balconies;    // share of bay columns with balconies
	bool lintels;
	bool piers;         // windows stacked in vertical strips between piers
	bool shutters;
};

struct Surface {
	vec3 albedo;
	vec3 emission;      // light of its own (shop windows)
	float glass;        // how much of the pixel is reflective glass
};

// A random number per building (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed * 1024.0 + salt * 3.7, salt * 13.1 + 7.0));
}

int pick(float r, int count) {
	return min(int(r * float(count)), count - 1);
}

Facade facade_for(int archetype, float seed, bool landmark) {
	float r1 = rnd(seed, 1.0);
	float r2 = rnd(seed, 2.0);
	float r3 = rnd(seed, 3.0);
	float r4 = rnd(seed, 4.0);
	Facade f;
	f.wall = srgb(RED_BRICK[pick(r1, 6)]);
	f.trim = srgb(TRIM_STONE);
	f.frame = srgb(FRAME_PAINT[pick(r2, 5)]);
	f.glass = srgb(GLASS_DARK[pick(r3, 4)]);
	f.accent = f.trim;
	f.base = f.wall;
	f.cornice = srgb(CORNICE_PAINT[pick(r4, 4)]);
	f.windows = PUNCHED;
	f.surface = BRICK;
	f.bay = 2.2;
	f.window_width = 1.0;
	f.window_height = 0.46;
	f.sill = 0.26;
	f.frame_width = 0.07;
	f.mullion = 0.08;
	f.spandrel = 0.0;
	f.reflect = 0.4;
	f.front_open = 1.0;
	f.side_open = 0.15;
	f.base_floors = 0.0;
	f.shades = 0.5;
	f.air_conditioners = 0.0;
	f.balconies = 0.0;
	f.lintels = false;
	f.piers = false;
	f.shutters = false;

	if (archetype == HOUSE) {
		// Vinyl siding in pale colors, or brick; white trim, some shutters.
		if (r1 < 0.68) {
			f.wall = srgb(SIDING_PAINT[pick(r4, 6)]);
			f.surface = SIDING;
		} else {
			f.wall = srgb(r4 < 0.5 ? RED_BRICK[pick(r2, 6)] : BROWNSTONE[pick(r2, 4)]);
		}
		f.frame = srgb(FRAME_PAINT[0]);
		f.accent = srgb(r2 < 0.5 ? vec3(0.16, 0.26, 0.20) : vec3(0.15, 0.17, 0.22));
		f.bay = 3.0;
		f.window_width = 0.95;
		f.window_height = 0.42;
		f.sill = 0.28;
		f.side_open = 0.6;
		f.shutters = r3 < 0.4;
	} else if (archetype == ROWHOUSE) {
		// Brownstones and brick rowhouses: tall parlor windows, heavy lintels.
		if (r1 < 0.5) {
			f.wall = srgb(BROWNSTONE[pick(r4, 4)]);
			f.surface = STONE;
			f.trim = f.wall * 1.25;
		} else if (r1 < 0.9) {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]);
		} else {
			f.wall = srgb(LIMESTONE[pick(r4, 4)]);
			f.surface = STONE;
		}
		f.cornice = srgb(r2 < 0.6 ? CORNICE_PAINT[1] : CORNICE_PAINT[pick(r3, 4)]);
		f.bay = 1.9;
		f.window_width = 0.95;
		f.window_height = 0.5;
		f.sill = 0.24;
		f.side_open = 0.04;
		f.lintels = true;
		f.air_conditioners = 0.12;
	} else if (archetype == WALKUP) {
		// Tenements: red, brown, tan or painted brick with white trim.
		if (r1 < 0.45) {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]);
		} else if (r1 < 0.65) {
			f.wall = srgb(BROWNSTONE[pick(r4, 4)]) * 1.1;
		} else if (r1 < 0.88) {
			f.wall = srgb(BUFF_BRICK[pick(r4, 4)]);
		} else {
			f.wall = srgb(STUCCO[pick(r4, 5)]);
			f.surface = SMOOTH;
		}
		f.bay = 2.1;
		f.window_width = 0.92;
		f.window_height = 0.45;
		f.sill = 0.27;
		f.side_open = 0.1;
		f.lintels = true;
		f.air_conditioners = 0.22;
	} else if (archetype == PREWAR_APARTMENT) {
		// Brick over a limestone base, or all limestone.
		f.base = srgb(LIMESTONE[pick(r2, 4)]);
		if (r1 < 0.4) {
			f.wall = srgb(BUFF_BRICK[pick(r4, 4)]);
			f.base_floors = 2.0;
		} else if (r1 < 0.72) {
			f.wall = srgb(r4 < 0.5 ? RED_BRICK[pick(r3, 6)] : BROWNSTONE[pick(r3, 4)] * 1.15);
			f.base_floors = 2.0;
		} else {
			f.wall = f.base;
			f.surface = STONE;
			f.base_floors = 1.0;
		}
		f.cornice = f.base;
		f.trim = f.base * 1.04;
		f.bay = 2.3;
		f.window_width = 1.0;
		f.window_height = 0.45;
		f.sill = 0.27;
		f.side_open = 0.35;
		f.lintels = true;
		f.air_conditioners = 0.18;
	} else if (archetype == POSTWAR_APARTMENT) {
		// White, tan or red brick slabs with wide aluminum windows.
		if (r1 < 0.4) {
			f.wall = srgb(WHITE_BRICK[pick(r4, 3)]);
		} else if (r1 < 0.7) {
			f.wall = srgb(BUFF_BRICK[pick(r4, 4)]);
		} else {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]);
		}
		f.frame = srgb(r2 < 0.6 ? vec3(0.66, 0.68, 0.69) : vec3(0.27, 0.23, 0.19));
		f.accent = srgb(vec3(0.82, 0.81, 0.77));
		f.windows = r3 < 0.25 ? RIBBON : PUNCHED;
		f.bay = 3.0;
		f.window_width = 2.0;
		f.window_height = 0.43;
		f.sill = 0.3;
		f.side_open = 0.75;
		f.reflect = 0.4;
		f.balconies = r3 > 0.6 ? 0.45 : 0.0;
		f.air_conditioners = 0.12;
	} else if (archetype == MODERN_RESIDENTIAL) {
		// Floor-to-ceiling glass with white slab edges and glass balconies,
		// or a masonry grid with big windows.
		if (r1 < 0.7) {
			f.windows = CURTAIN;
			f.glass = srgb(GLASS_TOWER[pick(r3, 5)]);
			f.accent = srgb(r2 < 0.6 ? vec3(0.88, 0.88, 0.85) : vec3(0.55, 0.57, 0.58));
			f.frame = srgb(vec3(0.55, 0.58, 0.60));
			f.bay = 1.5;
			f.mullion = 0.07;
			f.spandrel = 0.4;
			f.reflect = 0.8;
			f.balconies = r4 < 0.5 ? 0.4 : 0.0;
		} else {
			f.wall = srgb(r4 < 0.5 ? BUFF_BRICK[pick(r2, 4)] : vec3(0.62, 0.62, 0.60));
			f.surface = r4 < 0.5 ? BRICK : SMOOTH;
			f.glass = srgb(GLASS_TOWER[pick(r3, 5)]) * 0.7;
			f.frame = srgb(vec3(0.22, 0.22, 0.23));
			f.bay = 3.0;
			f.window_width = 2.5;
			f.window_height = 0.72;
			f.sill = 0.1;
			f.reflect = 0.6;
		}
		f.side_open = 0.9;
		f.shades = 0.3;
	} else if (archetype == PREWAR_OFFICE) {
		// Masonry towers: windows in vertical strips between piers, with
		// dark spandrels, over a tall stone base.
		if (r1 < 0.5) {
			f.wall = srgb(LIMESTONE[pick(r4, 4)]);
			f.surface = STONE;
		} else if (r1 < 0.8) {
			f.wall = srgb(BUFF_BRICK[pick(r4, 4)]);
		} else if (r1 < 0.9) {
			f.wall = srgb(vec3(0.66, 0.66, 0.64));
			f.surface = STONE;
		} else {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]);
		}
		f.base = srgb(LIMESTONE[pick(r2, 4)]);
		f.trim = f.base;
		f.cornice = f.base;
		f.accent = srgb(r3 < 0.5 ? vec3(0.28, 0.26, 0.24) : vec3(0.42, 0.34, 0.28));
		f.frame = srgb(vec3(0.20, 0.20, 0.19));
		f.bay = 1.8;
		f.window_width = 1.0;
		f.window_height = 0.52;
		f.sill = 0.24;
		f.base_floors = 3.0;
		f.side_open = 0.6;
		f.piers = true;
		f.shades = 0.35;
	} else if (archetype == MIDCENTURY_OFFICE) {
		// International Style: a dark mullion grid with colored spandrels.
		if (r1 < 0.78) {
			f.windows = CURTAIN;
			f.accent = srgb(SPANDREL[pick(r4, 5)]);
			f.frame = srgb(r2 < 0.6 ? vec3(0.22, 0.23, 0.24) : vec3(0.64, 0.66, 0.68));
			f.glass = srgb(vec3(0.28, 0.35, 0.38));
			f.bay = 1.5;
			f.mullion = 0.1;
			f.spandrel = 1.1;
			f.reflect = 0.6;
		} else {
			f.wall = srgb(r4 < 0.5 ? WHITE_BRICK[pick(r2, 3)] : LIMESTONE[pick(r2, 4)]);
			f.surface = r4 < 0.5 ? BRICK : STONE;
			f.windows = RIBBON;
			f.frame = srgb(vec3(0.30, 0.31, 0.32));
			f.glass = srgb(vec3(0.20, 0.26, 0.29));
			f.bay = 1.5;
			f.window_height = 0.45;
			f.sill = 0.3;
			f.reflect = 0.5;
		}
		f.side_open = 0.85;
		f.shades = 0.3;
	} else if (archetype == MODERN_OFFICE) {
		// Glass towers with a fine silver grid.
		f.windows = CURTAIN;
		f.glass = srgb(GLASS_TOWER[pick(r1, 5)]);
		f.accent = f.glass * 0.7;
		f.frame = srgb(r2 < 0.7 ? vec3(0.66, 0.70, 0.73) : vec3(0.22, 0.24, 0.26));
		f.bay = 1.5;
		f.mullion = 0.06;
		f.spandrel = 0.7;
		f.reflect = 1.0;
		f.side_open = 1.0;
		f.shades = 0.2;
	} else if (archetype == LOFT) {
		// Cast iron painted cream, gray or pastel, with tall arched windows
		// between columns; or brick with stone trim.
		if (r1 < 0.6) {
			f.wall = srgb(CAST_IRON[pick(r4, 5)]);
			f.surface = SMOOTH;
			f.windows = r3 < 0.65 ? ARCHED : PUNCHED;
			f.trim = f.wall * 1.06;
			f.cornice = f.wall * 0.92;
			f.piers = true;
			f.accent = f.wall * 0.86;
		} else {
			f.wall = srgb(r4 < 0.6 ? RED_BRICK[pick(r3, 6)] : BROWNSTONE[pick(r3, 4)] * 1.15);
			f.lintels = true;
		}
		f.frame = srgb(r2 < 0.6 ? FRAME_PAINT[1] : FRAME_PAINT[2]);
		f.bay = 2.6;
		f.window_width = 1.55;
		f.window_height = 0.64;
		f.sill = 0.18;
		f.side_open = 0.12;
		f.shades = 0.3;
	} else if (archetype == STORE) {
		// Low shops: brick or stucco above the storefronts.
		if (r1 < 0.5) {
			f.wall = srgb(r4 < 0.6 ? RED_BRICK[pick(r3, 6)] : BUFF_BRICK[pick(r3, 4)]);
		} else {
			f.wall = srgb(STUCCO[pick(r4, 5)]);
			f.surface = SMOOTH;
		}
		f.bay = 3.0;
		f.window_width = 1.3;
		f.window_height = 0.42;
		f.sill = 0.3;
		f.side_open = 0.0;
	} else if (archetype == INDUSTRIAL) {
		// Warehouses and garages: brick or block, steel factory windows.
		if (r1 < 0.5) {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]) * 0.95;
		} else if (r1 < 0.75) {
			f.wall = srgb(vec3(0.60, 0.59, 0.55));
			f.surface = SMOOTH;
		} else {
			f.wall = srgb(r4 < 0.5 ? vec3(0.76, 0.71, 0.60) : vec3(0.50, 0.56, 0.50));
			f.surface = SMOOTH;
		}
		f.windows = FACTORY;
		f.frame = srgb(vec3(0.22, 0.26, 0.25));
		f.glass = srgb(vec3(0.33, 0.37, 0.38));
		f.bay = 4.0;
		f.window_width = 2.8;
		f.window_height = 0.48;
		f.sill = 0.3;
		f.front_open = 0.75;
		f.side_open = 0.3;
		f.shades = 0.0;
	} else if (archetype == INSTITUTION) {
		// Schools, hospitals, courthouses: civic brick or limestone, tall windows.
		if (r1 < 0.5) {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]);
		} else if (r1 < 0.8) {
			f.wall = srgb(LIMESTONE[pick(r4, 4)]);
			f.surface = STONE;
		} else {
			f.wall = srgb(BUFF_BRICK[pick(r4, 4)]);
		}
		f.base = srgb(LIMESTONE[pick(r2, 4)]);
		f.trim = f.base;
		f.cornice = f.base;
		f.frame = srgb(r2 < 0.5 ? FRAME_PAINT[0] : vec3(0.20, 0.22, 0.20));
		f.bay = 3.0;
		f.window_width = 1.4;
		f.window_height = 0.55;
		f.sill = 0.22;
		f.base_floors = 1.0;
		f.side_open = 0.6;
		f.lintels = true;
		f.shades = 0.3;
	} else if (archetype == HOTEL) {
		// Masonry with a stone base (landmark hotels always), or a glass tower.
		if (r1 < 0.5 || landmark) {
			f.wall = srgb(r4 < 0.5 ? LIMESTONE[pick(r3, 4)] : BUFF_BRICK[pick(r3, 4)]);
			f.surface = r4 < 0.5 ? STONE : BRICK;
			f.base = srgb(LIMESTONE[pick(r2, 4)]);
			f.base_floors = 2.0;
			f.lintels = true;
			f.cornice = f.base;
		} else {
			f.windows = CURTAIN;
			f.glass = srgb(GLASS_TOWER[pick(r3, 5)]);
			f.accent = srgb(vec3(0.75, 0.75, 0.73));
			f.frame = srgb(vec3(0.40, 0.42, 0.44));
			f.bay = 1.8;
			f.spandrel = 0.9;
			f.reflect = 0.8;
		}
		f.bay = max(f.bay, 2.0);
		f.window_width = 1.2;
		f.window_height = 0.42;
		f.sill = 0.3;
		f.side_open = 0.7;
		f.shades = 0.75;
		f.air_conditioners = 0.1;
	} else if (archetype == OTHER) {
		// Utilities, garages, terminals: plain walls, few windows.
		f.wall = srgb(r1 < 0.5 ? vec3(0.66, 0.65, 0.61) : RED_BRICK[pick(r4, 6)]);
		f.surface = r1 < 0.5 ? SMOOTH : BRICK;
		f.frame = srgb(vec3(0.25, 0.26, 0.26));
		f.bay = 4.0;
		f.window_width = 1.2;
		f.window_height = 0.35;
		f.sill = 0.35;
		f.front_open = 0.5;
		f.side_open = 0.2;
		f.shades = 0.0;
	}
	if (landmark && (archetype == PREWAR_OFFICE || archetype == PREWAR_APARTMENT || archetype == HOTEL
			|| archetype == INSTITUTION) && f.windows != CURTAIN) {
		// The old masonry landmarks are mostly faced in stone or terracotta
		// rather than brick. Every prewar office tower is: 70% pale limestone,
		// 30% ivory terracotta, so the Empire State, Chrysler and Woolworth
		// Buildings read light. Three in four of the others are: 60%
		// limestone, 25% terracotta, 15% granite.
		float r5 = rnd(seed, 5.0);
		bool office = archetype == PREWAR_OFFICE;
		if (office || r5 < 0.75) {
			if (r5 < (office ? 0.7 : 0.45)) {
				f.wall = srgb(LANDMARK_LIMESTONE[pick(r4, 3)]);
			} else if (office || r5 < 0.64) {
				f.wall = srgb(TERRACOTTA[pick(r4, 3)]);
			} else {
				f.wall = srgb(GRANITE[pick(r4, 3)]);
			}
			f.surface = STONE;
			f.base = archetype == INSTITUTION && r3 < 0.5 ? srgb(GRANITE[pick(r2, 3)]) : f.wall * 0.94;
			f.trim = f.wall * 1.05;
			f.cornice = f.trim;
			f.base_floors = max(f.base_floors, 1.0);
		}
		// Stone lintels on any punched masonry windows.
		f.lintels = f.lintels || (f.surface != SIDING && f.windows == PUNCHED);
	}
	return f;
}

// A soft light band sweeping diagonally across glass, `period` meters apart:
// the cartoon shorthand for a reflection.
vec3 glass_sweep(vec2 p, float period, float detail) {
	float s = fract((p.x + 0.7 * p.y) / period);
	return vec3(0.05, 0.06, 0.07) * smoothstep(0.0, 0.06, s) * (1.0 - smoothstep(0.14, 0.22, s)) * detail;
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

// Ground-floor shops along a street front: a sign band, maybe an awning,
// big shop windows over a low bulkhead, and a door, store after store.
Surface storefront(vec2 p, vec2 footprint, float floor_height, float bay, float seed, vec3 wall, vec3 pier_color, float detail) {
	float store_width = bay * max(1.0, floor(6.2 / bay + 0.5));
	float store = floor(p.x / store_width);
	float sx = p.x - store * store_width;
	float r1 = hash(vec2(store, seed * 613.0));
	float r2 = hash(vec2(store + 0.5, seed * 613.0 + 7.0));
	float r3 = hash(vec2(store + 0.25, seed * 613.0 + 19.0));
	float top = min(floor_height, 4.4);
	float sign_height = clamp(top * 0.17, 0.45, 0.75);
	float sign_bottom = top - sign_height;
	bool has_awning = mix(0.45, r2, detail) < 0.55;
	float awning_bottom = sign_bottom - 0.85;
	float window_top = has_awning ? sign_bottom : sign_bottom - 0.12;
	const float BULKHEAD = 0.45;
	const float PIER = 0.4;
	float fx = footprint.x / store_width;
	float u = p.x / store_width;

	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	// Shop windows between piers, split by thin mullions, with a door.
	float piers = centered_stripes(u, PIER / store_width, fx);
	float mullions = centered_stripes(p.x / 1.55, 0.05 / 1.55, footprint.x / 1.55) * visible(0.05, footprint.x);
	float door = stripes(u - (store_width - PIER * 0.5 - 1.15) / store_width, 1.05 / store_width, fx);
	float glass_band = band(p.y, BULKHEAD, window_top, footprint.y);
	float door_band = band(p.y, 0.0, min(2.3, window_top), footprint.y);
	vec3 frame = srgb(vec3(0.16, 0.15, 0.14));
	float rise = clamp((p.y - BULKHEAD) / max(window_top - BULKHEAD, 0.5), 0.0, 1.0);
	vec3 interior = mix(srgb(SHOP_INTERIOR), srgb(SHOP_GLASS), smoothstep(0.2, 0.8, rise));
	float column = floor(p.x / 0.45);
	float goods = band(p.y - BULKHEAD, 0.0, 0.25 + 0.6 * hash(vec2(column, store + seed * 91.0)), footprint.y)
			* step(0.35, hash(vec2(column + 0.5, seed * 17.0))) * detail;
	interior = mix(interior, srgb(GOODS[pick(hash(vec2(column, seed * 5.0 + 3.3)), 5)]), goods);
	interior += glass_sweep(p, 2.6, detail);
	vec3 color = frame;
	float glass = glass_band * (1.0 - mullions);
	color = mix(color, interior, glass);
	color = mix(color, mix(srgb(SHOP_GLASS), srgb(SHOP_INTERIOR), 0.4), door * door_band);
	s.glass = max(glass, door * door_band) * (1.0 - piers);
	float lit_part = 1.0 - smoothstep(0.2, 0.8, rise);
	float glow = shop_glow * 0.3;
	float closed = 0.0;
	if (city_lights > 0.0) {
		// Night: shops glow bright, all the way up; late at night more and more
		// of them are shut behind roll-down gates (until early morning).
		glow *= 1.0 + shop_night_glow * city_lights;
		lit_part = mix(lit_part, 1.0, 0.6 * city_lights);
		float h = clock_hours < 6.0 ? clock_hours + 24.0 : clock_hours;
		float shut = 0.45 * bump(h, 21.0, 25.0, 29.0, 30.5) * city_lights;
		closed = mix(shut, step(hash(vec2(store + 0.75, seed * 613.0 + 29.0)), shut), detail);
		float gate = closed * band(p.y, -1.0, window_top, footprint.y) * (1.0 - piers);
		color = mix(color, srgb(METAL_DOOR) * (1.0 - 0.25 * stripes(p.y / 0.1, 0.35, footprint.y / 0.1)), gate);
		s.glass *= 1.0 - gate;
	}
	s.emission = srgb(SHOP_LIGHT) * glow * s.glass * lit_part * mix(0.7, 1.3, r3);
	// Sign band with a row of letters.
	vec3 sign_color = srgb(mix(vec3(0.4), SIGN[pick(r1, 6)], detail));
	float letters = stripes(sx / 0.32, 0.55, footprint.x / 0.32) * band(sx, store_width * 0.22, store_width * 0.78, footprint.x)
			* band(p.y, sign_bottom + sign_height * 0.3, sign_bottom + sign_height * 0.72, footprint.y) * detail;
	vec3 letter_color = dot(sign_color, vec3(0.33)) > 0.3 ? srgb(vec3(0.12)) : srgb(vec3(0.95, 0.93, 0.85));
	float sign_band = band(p.y, sign_bottom, top, footprint.y);
	color = mix(color, mix(sign_color, letter_color, letters), sign_band);
	if (city_lights > 0.0) {
		// Most signs are lit at night: a light box behind dark letters, or
		// light letters on a dark sign.
		float lit_sign = mix(0.7, step(hash(vec2(store + 0.6, seed * 613.0 + 41.0)), 0.7), detail) * (1.0 - 0.6 * closed);
		vec3 sign_light = mix(sign_color, letter_color, letters);
		s.emission += sign_light * (sign_glow * sign_band * lit_sign * city_lights);
	}
	// Awning: lit on its slope, a darker scalloped valance, its shadow below.
	if (has_awning) {
		float v = (p.y - awning_bottom) / 0.85;
		vec3 cloth = srgb(AWNING[pick(r3, 8)]);
		float striped = step(r1, 0.3) * stripes(p.x / 0.6, 0.5, footprint.x / 0.6) * detail;
		cloth = mix(cloth, srgb(vec3(0.93, 0.91, 0.85)), striped);
		cloth *= mix(0.62, 1.12, smoothstep(0.0, 1.0, v));
		float scallop_x = fract(p.x / 0.32) - 0.5;
		float scallop = length(vec2(scallop_x * 0.32, max(awning_bottom + 0.14 - p.y, 0.0))) < 0.15 ? 1.0 : 0.0;
		float awning = band(p.y, awning_bottom + 0.14, sign_bottom, footprint.y)
				+ band(p.y, awning_bottom, awning_bottom + 0.14, footprint.y) * mix(0.7, scallop, detail);
		float shadow = band(p.y, awning_bottom - 0.9, awning_bottom, footprint.y) * smoothstep(awning_bottom - 0.9, awning_bottom, p.y);
		color *= 1.0 - 0.45 * shadow;
		s.emission *= 1.0 - 0.6 * shadow;
		color = mix(color, cloth, clamp(awning, 0.0, 1.0));
		s.glass *= 1.0 - clamp(awning, 0.0, 1.0);
	}
	// Bulkhead under the windows, piers between stores, wall above.
	color = mix(color, frame * 1.4, band(p.y, -2.0, BULKHEAD, footprint.y) * (1.0 - door * door_band));
	color = mix(color, pier_color, piers);
	float above = band(p.y, top, 1e4, footprint.y);
	color = mix(color, wall, above);
	s.glass *= 1.0 - above;
	s.emission *= 1.0 - above;
	s.albedo = color;
	return s;
}

// Iron fire escapes on an old walk-up's street front: a balcony at every
// floor above the first, two bays wide, with a stair up to the next one.
// Returns the iron's coverage (x) and its shadow on the wall (y).
vec2 fire_escape(vec2 p, vec2 footprint, float floor_height, float bay, float sill, float seed, float detail, float below_top) {
	float stack_width = 2.0 * bay;
	float period = 4.0 * bay;
	float u = p.x / period + rnd(seed, 9.0);
	float in_stack = stripes(u, 0.5, footprint.x / period);
	float sx = fract(u) * period;
	float level = sill - 0.2;
	float rel = p.y - level;
	float floor_index = floor(rel / floor_height);
	float ry = rel - floor_index * floor_height;
	float fy = footprint.y / floor_height;
	float q = rel / floor_height;
	float slab = stripes(q, 0.1 / floor_height, fy);
	float rail = stripes(q - 0.9 / floor_height, 0.06 / floor_height, fy);
	float balusters = stripes(sx / 0.13, 0.22, footprint.x / 0.13) * stripes(q - 0.1 / floor_height, 0.8 / floor_height, fy);
	float posts = (band(sx, 0.0, 0.07, footprint.x) + band(sx, stack_width - 0.07, stack_width, footprint.x))
			* stripes(q, 0.96 / floor_height, fy);
	// The stair rises across the balcony to the one above.
	float run = min(stack_width - 0.9, floor_height * 0.85);
	float along = (sx - 0.45) / run;
	float stair_line = ry - 0.1 - along * floor_height;
	float stair = band(stair_line, -0.12, 0.12, max(footprint.y, footprint.x) * 1.5)
			* band(along, 0.0, 1.0, footprint.x / run) * detail;
	stair *= mix(0.6, 0.35 + 0.65 * stripes(ry / 0.22, 0.5, footprint.y / 0.22), detail);
	float iron = clamp(slab + rail + balusters * 0.9 + posts + stair, 0.0, 1.0);
	float shadow = smoothstep(floor_height - 0.8, floor_height, ry) * 0.35;
	// Only on floors above the first, and not past the top of the wall.
	float allowed = in_stack * step(1.0, floor_index) * step(level + floor_height * floor_index + 1.0, p.y + below_top);
	return vec2(iron, shadow) * allowed;
}

Surface facade(vec2 p, vec2 footprint, int archetype, int flags, float floor_height, float seed, float below_top) {
	bool landmark = (flags & LANDMARK) != 0;
	Facade f = facade_for(archetype, seed, landmark);
	bool front = (flags & FRONT) != 0 || merged_blocks;
	bool street = (flags & FRONT) != 0 && !merged_blocks;
	bool retail = street && ((flags & RETAIL) != 0 || archetype == STORE);
	float pixel = max(footprint.x, footprint.y);
	// Per-window variety and small parts fade out while windows are still
	// several pixels big, so the distance stays calm.
	float detail = smoothstep(5.0, 12.0, min(f.bay, floor_height) / pixel);
	float fine = visible(0.08, pixel);

	vec2 cell_size = vec2(f.bay, floor_height);
	vec2 q = p / cell_size;           // position in bays and floors
	vec2 fq = footprint / cell_size;  // pixel footprint in bays and floors
	vec2 cell = floor(q);
	float fy = p.y - cell.y * floor_height;  // meters above this floor
	float bx = p.x - (cell.x + 0.5) * f.bay; // meters from this bay's center
	float upper = band(p.y, floor_height, 1e5, footprint.y);

	// The wall itself, with a stone base and a darker water table.
	vec3 wall = wall_texture(f.wall, f.surface, p, footprint);
	if (f.base_floors > 0.0) {
		float base_top = f.base_floors * floor_height;
		float in_base = band(p.y, -2.0, base_top, footprint.y);
		vec3 base = wall_texture(f.base, STONE, p, footprint);
		base *= 1.0 - 0.25 * stripes(p.y / 0.55, 0.06, footprint.y / 0.55) * visible(0.55, footprint.y);
		wall = mix(wall, base, in_base);
		wall = mix(wall, f.trim * 1.05, band(p.y, base_top - 0.12, base_top + 0.22, footprint.y));
	}
	if (f.surface != SIDING) {
		wall = mix(wall, wall * 0.72, band(p.y, -2.0, 0.55, footprint.y));
	}
	// Broad weathering so big walls aren't flat.
	wall *= 0.94 + 0.12 * value_noise(p * vec2(0.12, 0.25) + seed * 71.0);

	// Which bays have windows (lot-line walls are mostly blank).
	float open = front ? f.front_open : f.side_open;
	float present = open >= 1.0 ? 1.0 : mix(open, step(rnd(seed, cell.x * 0.73 + 5.0), open), detail);

	// Per-window variety: glass tone, shades pulled down, air conditioners.
	float w1 = hash(cell + seed * 57.0);
	float w2 = hash(cell + seed * 57.0 + 17.3);
	float w3 = hash(cell + seed * 57.0 + 41.9);
	vec3 glass_color = f.glass * mix(1.0, mix(0.82, 1.18, w1), detail);

	vec3 color = wall;
	float glass = 0.0;
	// Night: how much of the pixel is window that glows when lit (glass, and
	// shades glowing through), and how far up the window it is.
	float glow = 0.0;
	float window_up = 0.5;
	if (f.windows == CURTAIN) {
		float mullions = centered_stripes(q.x, f.mullion / f.bay, fq.x);
		float spandrel = stripes(q.y, f.spandrel / floor_height, fq.y);
		float transoms = centered_stripes(q.y, f.mullion / floor_height, fq.y)
				+ centered_stripes(q.y - f.spandrel / floor_height, f.mullion / floor_height, fq.y);
		transoms = min(transoms, 1.0);
		float pane = (1.0 - mullions) * (1.0 - spandrel) * (1.0 - transoms);
		float blind = step(w2, f.shades) * step(1.0 - w3 * 0.45, (fy - f.spandrel) / max(floor_height - f.spandrel, 0.1)) * detail;
		vec3 pane_color = glass_color * mix(1.0, mix(0.9, 1.1, w3), detail) + glass_sweep(p, 9.0, detail);
		pane_color = mix(pane_color, srgb(SHADES[1]) * 0.8, blind * 0.6);
		color = mix(f.frame, f.accent, (1.0 - mullions) * spandrel);
		color = mix(color, pane_color, pane);
		glass = pane * (1.0 - blind * 0.5) + (1.0 - mullions) * spandrel * 0.6 * float(archetype == MODERN_OFFICE);
		glow = pane * (1.0 - 0.4 * blind);
		window_up = clamp((fy - f.spandrel) / max(floor_height - f.spandrel, 0.1), 0.0, 1.0);
	} else {
		float width = f.window_width;
		float height = f.window_height * floor_height;
		float sill = f.sill * floor_height;
		float frame = f.frame_width;
		float wx;
		float gx;
		if (f.windows == RIBBON) {
			wx = 1.0 - centered_stripes(q.x, f.mullion / f.bay, fq.x);
			gx = wx;
		} else {
			wx = centered_stripes(q.x - 0.5, width / f.bay, fq.x);
			gx = centered_stripes(q.x - 0.5, (width - 2.0 * frame) / f.bay, fq.x);
		}
		float wy = stripes(q.y - sill / floor_height, height / floor_height, fq.y);
		float gy = stripes(q.y - (sill + frame) / floor_height, (height - 2.0 * frame) / floor_height, fq.y);
		float window = wx * wy;
		float pane = gx * gy;
		if (f.windows == ARCHED) {
			// Round the tops: cut the corners outside a half circle.
			float radius = 0.5 * width;
			float center = sill + height - radius;
			float outside = smoothstep(radius - pixel, radius + pixel, length(vec2(bx, max(fy - center, 0.0)))) * detail;
			float outside_glass = smoothstep(radius - frame - pixel, radius - frame + pixel, length(vec2(bx, max(fy - center, 0.0)))) * detail;
			window *= 1.0 - outside;
			pane *= 1.0 - outside_glass;
		}
		if (f.windows == PUNCHED || f.windows == ARCHED) {
			// Double-hung sash: a meeting rail across the middle.
			float rail = centered_stripes(q.y - (sill + 0.55 * height) / floor_height, frame / floor_height, fq.y) * fine;
			pane *= 1.0 - rail;
		} else if (f.windows == FACTORY) {
			// Steel sash: a grid of small panes.
			float muntins = max(centered_stripes(p.x / 0.55, 0.1, footprint.x / 0.55),
					centered_stripes(p.y / 0.45, 0.12, footprint.y / 0.45));
			pane *= 1.0 - muntins * visible(0.45, pixel);
			glass_color *= mix(1.0, mix(0.6, 1.5, hash(floor(p / vec2(0.55, 0.45)) + seed)), detail * 0.5);
		}
		window *= present;
		pane *= present;
		if (f.lintels) {
			float lintel = centered_stripes(q.x - 0.5, (width + 0.26) / f.bay, fq.x)
					* stripes(q.y - (sill + height) / floor_height, 0.3 / floor_height, fq.y);
			float sill_stone = centered_stripes(q.x - 0.5, (width + 0.16) / f.bay, fq.x)
					* stripes(q.y - (sill - 0.1) / floor_height, 0.1 / floor_height, fq.y);
			color = mix(color, f.trim, (lintel + sill_stone) * present);
		}
		if (f.piers) {
			// Spandrels between stacked windows, piers between the stacks.
			float column = centered_stripes(q.x - 0.5, (width + 0.1) / f.bay, fq.x);
			color = mix(color * 1.04, mix(color, f.accent, 0.55), column * (1.0 - wy) * upper * present);
			if (archetype == LOFT) {
				color = mix(color, f.trim, stripes(q.y + 0.18 / floor_height, 0.36 / floor_height, fq.y));
			}
		}
		if (f.shutters) {
			float shutters = (centered_stripes(q.x - 0.5, (width + 0.9) / f.bay, fq.x)
					- centered_stripes(q.x - 0.5, (width + 0.06) / f.bay, fq.x)) * wy * present;
			color = mix(color, f.accent, shutters);
		}
		// Glass a little lighter toward the top, with a soft diagonal
		// reflection sweeping across the facade; shades pulled partway down.
		float t = (fy - sill) / height;
		vec3 pane_color = glass_color * mix(0.85, 1.2, clamp(t, 0.0, 1.0)) + glass_sweep(p, 3.2, detail);
		float shade = step(w2, f.shades) * step(1.0 - w3 * 0.7, t) * detail;
		vec3 shade_color = srgb(SHADES[pick(w1, 4)]);
		pane_color = mix(pane_color, shade_color, shade);
		color = mix(color, f.frame, window);
		color = mix(color, pane_color, pane);
		glass = pane * (1.0 - shade);
		glow = pane * (1.0 - 0.4 * shade);
		window_up = clamp(t, 0.0, 1.0);
		if (f.air_conditioners > 0.0) {
			float unit = step(w3, f.air_conditioners) * band(bx, -0.33, 0.33, footprint.x)
					* band(fy, sill + 0.02, sill + 0.42, footprint.y) * present * detail * upper;
			color = mix(color, srgb(AIR_CONDITIONER) * mix(0.82, 1.0, smoothstep(sill, sill + 0.42, fy)), unit);
			glass *= 1.0 - unit;
			glow *= 1.0 - unit;
		}
		// Balconies: a slab and railing at the bottom of each floor.
		if (f.balconies > 0.0) {
			float column = step(rnd(seed, cell.x * 0.37 + 23.0), f.balconies);
			float balcony = mix(f.balconies, column, detail) * upper
					* centered_stripes(q.x - 0.5, min(width + 0.6, f.bay) / f.bay, fq.x)
					* stripes(q.y, 1.1 / floor_height, fq.y);
			float slab = stripes(q.y, 0.2 / floor_height, fq.y);
			vec3 railing = mix(f.accent * 0.8, srgb(IRON) * 2.0, stripes(p.x / 0.14, 0.3, footprint.x / 0.14) * fine);
			color = mix(color, mix(railing, f.accent, slab), balcony * present);
			glow *= 1.0 - 0.5 * balcony * present;
		}
	}
	// Curtain-wall balconies (modern residential): glass railings, white slabs.
	if (f.windows == CURTAIN && f.balconies > 0.0) {
		float column = step(rnd(seed, floor(p.x / 4.5) * 0.37 + 23.0), f.balconies);
		float balcony = mix(f.balconies, column, detail) * upper * stripes(q.y, 1.1 / floor_height, fq.y);
		float slab = stripes(q.y, 0.25 / floor_height, fq.y);
		vec3 railing = mix(color, srgb(vec3(0.78, 0.86, 0.90)), 0.55);
		color = mix(color, mix(railing, f.accent, slab), balcony);
		glass *= 1.0 - balcony * 0.5;
		glow *= 1.0 - balcony * 0.5;
	}

	Surface s;
	s.emission = vec3(0.0);
	// Ground floor: shops, office lobbies, loading doors or front doors.
	float ground = 1.0 - upper;
	if (ground > 0.0) {
		vec3 ground_color = color;
		float ground_glass = glass;
		vec3 ground_emission = vec3(0.0);
		if (retail) {
			vec3 pier = f.surface == SIDING ? f.wall : mix(f.base_floors > 0.0 ? f.base : f.wall, f.trim, 0.3);
			Surface shop = storefront(p, footprint, floor_height, f.bay, seed, ground_color, pier, detail);
			ground_color = shop.albedo;
			ground_glass = shop.glass;
			ground_emission = shop.emission;
		} else if (street && (archetype == PREWAR_OFFICE || archetype == MIDCENTURY_OFFICE || archetype == MODERN_OFFICE
				|| (f.windows == CURTAIN))) {
			// Lobby: tall glass in a stone surround.
			float top = min(floor_height, 5.0) - 0.45;
			float lobby = band(p.y, 0.25, top, footprint.y) * (1.0 - centered_stripes(p.x / 1.6, 0.06, footprint.x / 1.6));
			vec3 surround = f.windows == CURTAIN ? srgb(vec3(0.62, 0.62, 0.60)) : f.base;
			ground_color = mix(surround, f.glass * 0.9, lobby);
			ground_color = mix(ground_color, color, band(p.y, top + 0.45, 1e4, footprint.y));
			ground_glass = lobby;
			if (city_lights > 0.0) {
				// Lit all night, brightest up by the ceiling.
				ground_emission = srgb(LOBBY_LIGHT) * (lobby * lobby_glow * city_lights * mix(0.7, 1.2, smoothstep(0.25, top, p.y)));
			}
		} else if (archetype == INDUSTRIAL && street) {
			// Roll-up loading doors.
			float slot = floor(p.x / (3.0 * f.bay));
			float has_door = mix(0.5, step(hash(vec2(slot, seed * 31.0)), 0.6), detail);
			float door = has_door * centered_stripes(p.x / (3.0 * f.bay) - 0.5, 3.4 / (3.0 * f.bay), footprint.x / (3.0 * f.bay))
					* band(p.y, 0.0, min(floor_height - 0.5, 4.0), footprint.y);
			vec3 metal = srgb(METAL_DOOR) * (1.0 - 0.2 * stripes(p.y / 0.12, 0.3, footprint.y / 0.12));
			ground_color = mix(wall, metal, door);
			ground_glass = 0.0;
		} else if (street) {
			// Front doors in some bays, in place of the window.
			float has_door = mix(0.0, step(rnd(seed, cell.x * 0.91 + 37.0), 0.22), detail);
			float door = has_door * band(bx, -0.6, 0.6, footprint.x) * band(p.y, -1.0, min(2.5, floor_height - 0.4), footprint.y);
			float door_glass = band(bx, -0.4, 0.4, footprint.x) * band(p.y, 1.4, 2.2, footprint.y);
			vec3 door_color = srgb(FRAME_PAINT[pick(w1, 4) + 1]) * 1.3;
			vec3 surround = mix(f.trim, door_color, band(bx, -0.5, 0.5, footprint.x) * band(p.y, -1.0, min(2.4, floor_height - 0.5), footprint.y));
			ground_color = mix(ground_color, mix(surround, f.glass, door_glass), door);
			ground_glass *= 1.0 - door;
			if (city_lights > 0.0) {
				// The hall light through the door's glass, and a lamp over the door.
				float lamp = has_door * (1.0 - smoothstep(0.0, 0.8, length(vec2(bx, p.y - min(2.75, floor_height - 0.3)))));
				ground_emission = srgb(LAMP_WARM) * ((door * door_glass * 1.2 + lamp * 0.35) * city_lights);
			}
		}
		color = mix(color, ground_color, ground);
		glass = mix(glass, ground_glass, ground);
		glow *= 1.0 - ground;
		s.emission = ground_emission * ground;
	}

	// Fire escapes on old walk-ups' street fronts.
	if (street && (flags & FIRE_ESCAPES) != 0) {
		vec2 escape = fire_escape(p, footprint, floor_height, f.bay, f.sill * floor_height, seed, detail, below_top);
		color *= 1.0 - escape.y;
		color = mix(color, srgb(IRON), escape.x);
		glass *= 1.0 - escape.x;
		glow *= 1.0 - escape.x;
	}

	// A parapet: the top of the wall, above the roof, is solid.
	if ((flags & PARAPET) != 0) {
		float solid = band(below_top, -1.0, PARAPET_HEIGHT, footprint.y);
		color = mix(color, f.windows == CURTAIN ? f.frame : wall, solid);
		glass *= 1.0 - solid;
		glow *= 1.0 - solid;
	}

	// Top of the wall: a cornice on prewar street fronts, else a plain coping.
	if (below_top < 4.0) {
		bool masonry = f.windows != CURTAIN;
		if (street && (flags & CORNICE) != 0) {
			float height = clamp(0.3 * floor_height, 0.8, 1.5) * (landmark ? 1.35 : 1.0);
			float t = below_top / height;
			float ft = footprint.y / height;
			float lip = band(t, -1.0, 0.13, ft);
			float underside = band(t, 0.13, 0.24, ft);
			float frieze = band(t, 0.24, 0.76, ft);
			float dentil_row = band(t, 0.76, 0.88, ft);
			float molding = band(t, 0.88, 1.0, ft);
			float brackets = centered_stripes(p.x / 1.2, 0.2, footprint.x / 1.2);
			float dentils = stripes(p.x / 0.24, 0.5, footprint.x / 0.24);
			vec3 shaded = f.cornice * (lip * 1.2 + underside * 0.5 + frieze * mix(0.82, 1.1, brackets)
					+ dentil_row * mix(0.62, 1.0, dentils) + molding * 0.86);
			float coverage = lip + underside + frieze + dentil_row + molding;
			float shadow = band(t, 1.0, 1.7, ft) * (1.0 - smoothstep(1.0, 1.7, t)) * 0.4;
			color *= 1.0 - shadow;
			color = mix(color, shaded / max(coverage, 1e-3), coverage);
			glass *= (1.0 - coverage) * (1.0 - shadow);
			glow *= 1.0 - coverage;
		} else if (masonry) {
			float coping = band(below_top, -1.0, 0.24, footprint.y);
			float shadow = band(below_top, 0.24, 0.4, footprint.y) * 0.3;
			color *= 1.0 - shadow;
			color = mix(color, f.trim * (f.surface == SIDING ? 0.9 : 1.0), coping);
			glass *= 1.0 - coping;
			glow *= 1.0 - coping;
		} else {
			float cap = band(below_top, -1.0, 0.5, footprint.y);
			color = mix(color, f.frame, cap);
			glass *= 1.0 - cap;
			glow *= 1.0 - cap;
		}
	}

	if (city_lights > 0.0 && glow > 0.0) {
		s.emission += window_light(archetype, f.windows == CURTAIN, cell, seed, cell_size / footprint, window_up)
				* (glow * window_glow * city_lights);
	}

	// Calm distance: once windows are only a few pixels, pull the grid toward
	// its average so far blocks don't turn into dotted noise.
	float calm = (1.0 - smoothstep(2.5, 7.0, min(f.bay, floor_height) / pixel)) * distance_calm;
	float coverage = f.windows == CURTAIN ? 1.0 - f.spandrel / floor_height
			: f.window_height * (f.windows == RIBBON ? 1.0 : f.window_width / f.bay) * (front ? f.front_open : f.side_open);
	color = mix(color, mix(wall, f.glass, coverage), calm);
	glass = mix(glass, coverage, calm);

	s.albedo = color;
	s.glass = glass * f.reflect;
	return s;
}

// The inside of a parapet, seen from the roof: plain wall under its coping.
Surface parapet_inside(vec2 p, vec2 footprint, int archetype, int flags, float seed, float below_top) {
	Facade f = facade_for(archetype, seed, (flags & LANDMARK) != 0);
	vec3 color = f.windows == CURTAIN ? f.frame : wall_texture(f.wall, f.surface, p, footprint) * 0.9;
	color = mix(color, f.trim, band(below_top, -1.0, 0.24, footprint.y));
	Surface s;
	s.albedo = color;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	return s;
}

// Times Square's signs (SIGNS walls). Everything is procedural (no textures),
// box-filtered by the pixel's footprint, and settles into each screen's
// average color, then the wall's, as screens get small on screen.

// An ad color (linear), by index (wrapping).
vec3 ad_color(int i) {
	return srgb(AD_COLORS[i % 8]);
}

// A seven-segment glyph (GLYPHS) in its box: g runs 0..1 across and up the
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

// A line of text `height` m tall; q is meters along it and up from its foot,
// `spaces` the share of letters left out (gaps between words), `salt` picks
// the words. Up close its letters are glyphs, from further away solid blocks
// (the blocky bars a sign's text reads as from down the street), then their
// average. Returns coverage.
float text_line(vec2 q, float height, float spaces, float salt, vec2 footprint) {
	float pitch = height * 0.8;
	float width = height * 0.6;
	float cell = floor(q.x / pitch);
	float h = hash(vec2(cell, salt));
	vec2 g = vec2((q.x - cell * pitch) / width, q.y / height);
	vec2 fg = footprint / vec2(width, height);
	float letter = step(spaces, h) * band(g.x, 0.0, 1.0, fg.x);
	float shape = mix(0.6, glyph(GLYPHS[pick(fract(h * 13.7), 16)], g, fg), smoothstep(5.0, 10.0, height / footprint.y));
	float line = band(q.y, 0.0, height, footprint.y);
	return line * mix(0.45 * (1.0 - spaces), letter * shape, smoothstep(1.5, 4.0, pitch / footprint.x));
}

// Rolling color bands: the n-th band's color.
vec3 wave_color(float n, vec3 c1, vec3 c2, vec3 c3) {
	float m = mod(n, 3.0);
	return m < 0.5 ? c1 : (m < 1.5 ? c2 : c3);
}

// What a screen `size` m big shows at `uv` (meters from its lower left
// corner), as light (linear): a cartoon ad, one of a few kinds, that changes
// every 6-12 s (blinking between slides) and now and then flashes a color
// across the whole screen. `id` picks everything. Once its shapes are only a
// few pixels it shows its average (also returned, as `average`).
vec3 screen(vec2 uv, vec2 size, float id, vec2 footprint, out vec3 average) {
	float r0 = hash(vec2(id, 5.1));
	float t = TIME + r0 * 47.0;
	float period = mix(6.0, 12.0, r0);
	float slide = floor(t / period);
	float since = t - slide * period;  // seconds into this slide
	float k1 = hash(vec2(id + 0.37, slide + 0.5));
	float k2 = hash(vec2(slide + 0.21, id * 1.31 + 2.0));
	float k3 = hash(vec2(k1 * 91.0 + 3.0, k2 * 37.0 + 1.0));
	int i1 = pick(k1, 8);
	vec3 c1 = ad_color(i1);
	vec3 c2 = ad_color(i1 + 1 + pick(k2, 7));
	vec3 c3 = ad_color(i1 + 1 + pick(k3, 7));
	vec3 white = vec3(1.0);
	// Dark ink on the light colors (cyan, yellow, green), white on the rest;
	// some slides are on night blue.
	vec3 ink = (i1 == 1 || i1 == 2 || i1 == 5) ? srgb(vec3(0.07, 0.07, 0.16)) : white;
	vec3 night_blue = srgb(AD_NIGHT_BLUE);
	bool dark = fract(k3 * 5.17) < 0.35;
	float pixel = max(footprint.x, footprint.y);
	float aspect = size.x / size.y;
	vec2 q = uv / size.y;       // in screen heights
	float px = pixel / size.y;  // a pixel, in screen heights
	float which = fract(k2 * 7.31 + k3);
	int kind;
	if (aspect < 0.7) {
		kind = which < 0.35 ? AD_PRODUCT : (which < 0.7 ? AD_COLUMN : (which < 0.85 ? AD_WAVES : AD_GRADIENT));
	} else {
		kind = pick(which, 5);
	}

	vec3 color;
	if (kind == AD_GRADIENT) {
		float g = 0.5 + 0.5 * sin((q.x * 0.7 + q.y * 1.3) * 2.4 - TIME * 0.8 + k1 * 6.3);
		vec3 tone_a = dark ? night_blue : c1;
		vec3 tone_b = dark ? c2 * 0.55 : c2;
		color = mix(tone_a, tone_b, g);
		vec2 center = vec2(mix(0.3, 0.7, k3) * aspect, 0.6);
		float radius = min(0.27, 0.36 * aspect) * (1.0 + 0.05 * sin(TIME * 2.6 + k2 * 6.3));
		float d = length(q - center);
		float disc = 1.0 - smoothstep(radius - px, radius + px, d);
		float ring = band(d, radius + 0.04, radius + 0.075, px);
		color = mix(mix(color, c3, disc), white, ring);
		float line = text_line(uv - size * vec2(0.08, 0.1), size.y * 0.12, 0.2, k3 * 50.0, footprint)
				* band(uv.x, size.x * 0.08, size.x * 0.92, footprint.x);
		color = mix(color, white, line);
		average = mix(mix(tone_a, tone_b, 0.5), c3, min(3.1 * radius * radius / aspect, 0.5)) + 0.06;
	} else if (kind == AD_TEXT) {
		// Three lines of text, typing themselves out line by line.
		vec3 back = dark ? night_blue : c1;
		ink = dark ? c1 : ink;
		color = back * mix(0.75, 1.0, q.y);
		float row = clamp(floor((0.93 - q.y) / 0.27), 0.0, 2.0);
		float height = size.y * (row == 0.0 ? 0.2 : 0.17);
		float typed = size.x * 0.07 + (since - 0.4 - 0.7 * row) * size.x * 0.9;
		float text = text_line(uv - vec2(size.x * 0.07, size.y * (0.66 - 0.27 * row)), height, 0.18, k1 * 31.0 + row * 7.0, footprint)
				* band(uv.x, size.x * 0.07, min(size.x * 0.93, typed), footprint.x);
		color = mix(color, ink, text);
		average = mix(back * 0.87, ink, 0.15);
	} else if (kind == AD_BURST) {
		vec2 d = q - vec2(0.5 * aspect, 0.5);
		float r = length(d);
		const float RAYS = 16.0 / 6.2832;
		float a = atan(d.y, d.x) * RAYS + TIME * (k3 < 0.5 ? 0.4 : -0.4);
		color = mix(c1, c2, stripes(a, 0.5, px / max(r, 1e-3) * RAYS));
		float radius = 0.3 * (1.0 + 0.06 * sin(TIME * 3.3 + k1 * 6.3));
		float disc = 1.0 - smoothstep(radius - px, radius + px, r);
		float ring = band(r, radius - 0.05, radius - 0.02, px);
		color = mix(mix(color, c3, disc), white, ring);
		average = mix(mix(c1, c2, 0.5), c3, min(0.28 / aspect, 0.5));
	} else if (kind == AD_WAVES) {
		float w = (q.y + 0.07 * sin(q.x * 5.0 + TIME * 1.4 + k1 * 6.3)) * 3.0 - TIME * 0.35;
		float n = floor(w + 0.5);
		float edge = smoothstep(-1.0, 1.0, (w - n) / max(px * 2.5, 1e-4));
		color = mix(wave_color(n - 1.0, c1, c2, c3), wave_color(n, c1, c2, c3), edge);
		float line = text_line(uv - size * vec2(0.1, 0.42), size.y * 0.16, 0.15, k2 * 60.0, footprint)
				* band(uv.x, size.x * 0.1, size.x * 0.9, footprint.x);
		color = mix(color, white, line);
		average = (c1 + c2 + c3) / 3.0 + 0.04;
	} else if (kind == AD_WORD) {
		// One huge word on night blue, glowing, over a colored bar.
		vec3 back = night_blue;
		color = back + c2 * (0.25 * (1.0 - smoothstep(0.0, 0.8 * aspect, length(q - vec2(0.5 * aspect, 0.5)))));
		float letters = 3.0 + floor(k3 * 4.0);
		float height = min(0.42, 0.85 * aspect / (letters * 0.8)) * size.y;
		float width = letters * height * 0.8 - height * 0.2;
		vec2 at = uv - vec2(0.5 * (size.x - width), 0.5 * size.y - 0.4 * height);
		float across = band(at.x, 0.0, width, footprint.x);
		float word = text_line(at, height, 0.0, k1 * 77.0, footprint) * across;
		color = mix(color, c1 * (1.15 + 0.15 * sin(TIME * 4.0 + k2 * 6.3)), word);
		color = mix(color, c3, across * band(at.y, -0.3 * height, -0.18 * height, footprint.y));
		average = mix(back + c2 * 0.1, c1, 0.5 * height * width / (size.x * size.y));
	} else if (kind == AD_PRODUCT) {
		// A cartoon can bobbing over a glowing gradient.
		color = mix(dark ? night_blue : c1 * 0.35, dark ? c1 * 0.5 : c1, clamp(q.y, 0.0, 1.0));
		vec2 center = vec2(0.5 * aspect, 0.5 + 0.02 * sin(TIME * 2.2 + k1 * 6.3));
		vec2 half_size = vec2(min(0.36 * aspect, 0.2), 0.3);
		float corner = half_size.x * 0.35;
		vec2 d = abs(q - center) - half_size + corner;
		float can = 1.0 - smoothstep(-px, px, length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - corner);
		vec3 body = mix(c2, c3, band(q.y - center.y, -0.1, 0.1, px));
		body = mix(body, white, 0.7 * band(q.x - center.x, -0.6 * half_size.x, -0.35 * half_size.x, px));
		color = mix(color, body, can);
		average = mix(dark ? c1 * 0.25 : c1 * 0.68, c2, min(2.4 * half_size.x * half_size.y / aspect, 0.6));
	} else {
		// AD_COLUMN: big letters down a banner, lighting up one by one.
		color = c1 * mix(0.6, 1.0, 0.5 + 0.5 * sin(q.y * 4.0 - TIME * 1.2));
		float width = size.x * 0.62;
		float height = width * 1.45;
		float pitch = height * 1.25;
		float cell = floor((size.y - uv.y) / pitch);  // letters from the top
		float bottom = size.y - cell * pitch - 0.5 * (pitch - height) - height;
		vec2 g = vec2((uv.x - 0.5 * (size.x - width)) / width, (uv.y - bottom) / height);
		float on = glyph(GLYPHS[pick(hash(vec2(cell, k1 * 59.0)), 16)], g, footprint / vec2(width, height))
				* step(0.0, bottom) * step(cell, (since - 0.3) * 3.0);
		color = mix(color, ink, on);
		average = mix(c1 * 0.8, ink, 0.2);
	}

	// Far off, the average; a blink between slides; now and then a flash.
	color = mix(average, color, smoothstep(0.5, 1.5, 0.1 * min(size.x, size.y) / pixel));
	float flash_time = TIME * 1.4 + r0 * 17.0;
	float flash = step(hash(vec2(floor(flash_time), id + 9.7)), 0.015) * (1.0 - fract(flash_time));
	flash *= flash;
	vec3 flash_color = (k3 < 0.5 ? white : c2) * 1.3;
	float blink = smoothstep(0.0, 0.25, since);
	average = mix(average, flash_color, flash) * blink;
	return mix(color, flash_color, flash) * blink;
}

// Which screen of a sign wall p is on: the band of screens from z0 to z1 is
// cut into bays along the wall (their width picked per building), some with a
// tall banner down one side, and each bay (or what the banner leaves) into
// tiers of one, two or three screens. Returns the screen's id and rectangle
// (lo, hi: wall meters, frame included).
float sign_layout(vec2 p, float z0, float z1, float seed, out vec2 lo, out vec2 hi) {
	float bay = mix(10.0, 20.0, rnd(seed, 81.0));
	float shift = rnd(seed, 82.0) * bay;
	float b = floor((p.x + shift) / bay);
	lo = vec2(b * bay - shift, z0);
	hi = vec2(lo.x + bay, z1);
	float h1 = hash(vec2(b, seed * 977.0 + 1.0));
	float h2 = hash(vec2(b, seed * 977.0 + 2.0));
	if (h1 < 0.35 && z1 - z0 > 9.0) {
		float banner = clamp(bay * 0.28, 3.0, 5.5);
		bool left = h2 < 0.5;
		float split = left ? lo.x + banner : hi.x - banner;
		if (left ? p.x < split : p.x >= split) {
			lo.x = left ? lo.x : split;
			hi.x = left ? split : hi.x;
			return b * 64.0 + 63.0;
		}
		lo.x = left ? split : lo.x;
		hi.x = left ? hi.x : split;
	}
	// Tiers from the bottom up; a thin one left at the top joins the one below.
	float tier = mix(7.0, 16.0, fract(h1 * 7.13 + h2));
	float full = floor((z1 - z0) / tier);
	float count = (z1 - z0) - full * tier < 0.5 * tier ? max(full, 1.0) : full + 1.0;
	float t = clamp(floor((p.y - z0) / tier), 0.0, count - 1.0);
	lo.y = z0 + t * tier;
	hi.y = t >= count - 1.0 ? z1 : lo.y + tier;
	float h3 = hash(vec2(b + t * 0.37, seed * 977.0 + 3.0));
	float width = hi.x - lo.x;
	float column = 0.0;
	if (h3 < 0.4 && width > 7.0) {
		float split = lo.x + width * (h3 < 0.2 ? 0.62 : 0.38);
		column = step(split, p.x);
		lo.x = column > 0.5 ? split : lo.x;
		hi.x = column > 0.5 ? hi.x : split;
	} else if (h3 < 0.6 && width > 10.0 && hi.y - lo.y > 6.0) {
		float third = width / 3.0;
		column = clamp(floor((p.x - lo.x) / third), 0.0, 2.0);
		lo.x += column * third;
		hi.x = lo.x + third;
	}
	return b * 64.0 + t * 4.0 + column;
}

// A sign wall's band of screens from z0 to z1 (UV.y): screens in dark steel,
// some outlined in neon or chasing marquee bulbs, and on most walls a news
// ticker along the bottom. `strength` is how bright they are now.
Surface billboards(vec2 p, vec2 footprint, float z0, float z1, float seed, float strength) {
	const float GAP = 0.35;  // half the steel between screens (m)
	float pixel = max(footprint.x, footprint.y);
	Surface s;
	s.albedo = srgb(SIGN_STEEL);
	s.emission = vec3(0.0);
	s.glass = 0.0;
	float bottom = z0;
	if (rnd(seed, 84.0) < 0.6 && z1 - z0 > 8.0) {
		bottom = z0 + 1.8;
		if (p.y < bottom) {
			// The ticker: letters scrolling along a dark band between lit edges.
			float foot = z0 + 0.2;
			float head = bottom - 0.2;
			float strip = band(p.y, foot, head, footprint.y);
			float edges = min(band(p.y, foot, foot + 0.07, footprint.y) + band(p.y, head - 0.07, head, footprint.y), 1.0);
			float height = (head - foot) * 0.58;
			float x = p.x + TIME * ticker_speed * mix(0.8, 1.25, rnd(seed, 87.0));
			float text = text_line(vec2(x, p.y - foot - 0.5 * (head - foot - height)), height, 0.16, seed * 613.0 + 5.0, footprint);
			vec3 light = mix(srgb(TICKER_BAND), srgb(TICKER_TEXT[pick(rnd(seed, 88.0), 3)]), text);
			light = mix(light, srgb(NEON[pick(rnd(seed, 89.0), 5)]), edges);
			s.emission = light * (strip * strength);
			s.albedo = mix(s.albedo, srgb(SCREEN_OFF), strip);
			return s;
		}
	}
	vec2 lo;
	vec2 hi;
	float id = sign_layout(p, bottom, z1, seed, lo, hi) * 0.618 + seed * 1031.0;
	vec2 size = max(hi - lo - 2.0 * GAP, vec2(0.3));
	float inside = band(p.x, lo.x + GAP, hi.x - GAP, footprint.x) * band(p.y, lo.y + GAP, hi.y - GAP, footprint.y);
	vec3 average;
	vec3 light = screen(p - lo - GAP, size, id, footprint, average) * mix(0.8, 1.15, hash(vec2(id, 8.3)));
	if (pixel < 0.016) {
		// Right up close, the LEDs' grid.
		float grid = max(stripes(p.x / 0.025, 0.3, footprint.x / 0.025), stripes(p.y / 0.025, 0.3, footprint.y / 0.025));
		light *= 1.0 - 0.5 * grid * visible(0.025, pixel);
	}
	s.emission = light * (inside * strength);
	s.albedo = mix(s.albedo, srgb(SCREEN_OFF), inside);
	// Neon tubes around some screens; chasing bulbs around a few.
	float tubes = hash(vec2(id, 3.3));
	if (tubes < 0.5) {
		bool bulbs = tubes < 0.15;
		float a = GAP - (bulbs ? 0.27 : 0.2);
		float c = GAP - 0.08;
		float outer = band(p.x, lo.x + a, hi.x - a, footprint.x) * band(p.y, lo.y + a, hi.y - a, footprint.y);
		float inner = band(p.x, lo.x + c, hi.x - c, footprint.x) * band(p.y, lo.y + c, hi.y - c, footprint.y);
		float tube = max(outer - inner, 0.0);
		vec3 neon = srgb(NEON[pick(fract(tubes * 9.7), 5)]);
		if (bulbs) {
			vec2 e = min(p - lo, hi - p);
			float chase = centered_stripes((e.x < e.y ? p.y : p.x) / 0.5 - TIME * 3.0, 0.5, pixel / 0.5);
			tube *= mix(0.25, 1.0, mix(0.5, chase, visible(0.5, pixel)));
			neon = srgb(vec3(1.0, 0.86, 0.58));
		}
		s.emission += neon * (tube * neon_glow * strength);
		s.albedo = mix(s.albedo, neon * 0.6, tube);
	}
	// Far off, once screens are a few pixels, the wall's average.
	vec3 wall_average = 0.6 * mix(ad_color(pick(rnd(seed, 85.0), 8)), ad_color(pick(rnd(seed, 86.0), 8)), 0.5);
	s.emission = mix(s.emission, wall_average * strength, 1.0 - smoothstep(2.0, 5.0, min(size.x, size.y) / pixel));
	return s;
}

// A street wall in Times Square's sign district: shops at street level, as on
// any street; billboards and screens from just above the shop fronts up to
// 40-60 m (or near the top of a lower wall); the facade above them and the
// shop fronts below washed in their colored light at night.
Surface sign_wall(vec2 p, vec2 footprint, int archetype, int flags, float floor_height, float seed, float below_top) {
	float z0 = min(floor_height, 4.4) + 0.6;
	float margin = ((flags & PARAPET) != 0 ? PARAPET_HEIGHT : 0.0) + ((flags & CORNICE) != 0 ? 2.2 : 0.8);
	float z1 = min(p.y + below_top - margin, mix(sign_top_range.x, sign_top_range.y, rnd(seed, 80.0)));
	float zone = z1 - z0 > 2.5 ? band(p.y, z0, z1, footprint.y) : 0.0;
	Surface s;
	s.albedo = vec3(0.0);
	s.emission = vec3(0.0);
	s.glass = 0.0;
	if (zone < 1.0) {
		s = facade(p, footprint, archetype, flags, floor_height, seed, below_top);
	}
	float strength = mix(sign_day_glow, sign_night_glow, max(night, city_lights));
	if (zone > 0.0) {
		Surface boards = billboards(p, footprint, z0, z1, seed, strength);
		s.albedo = mix(s.albedo, boards.albedo, zone);
		s.emission = mix(s.emission, boards.emission, zone);
		s.glass = mix(s.glass, boards.glass, zone);
	}
	if (city_lights > 0.0 && zone < 1.0 && z1 - z0 > 2.5) {
		float wash = p.y > z1 ? 1.0 - smoothstep(0.0, sign_wash_reach, p.y - z1) : 1.0 - smoothstep(0.0, 4.0, z0 - p.y);
		vec3 tint = mix(ad_color(pick(rnd(seed, 85.0), 8)), ad_color(pick(rnd(seed, 86.0), 8)),
				0.5 + 0.5 * sin(TIME * 0.5 + seed * 40.0));
		s.emission += s.albedo * tint * (1.5 * wash * wash * city_lights);
	}
	return s;
}

// Roofs: tar, silver coating, white membrane, gravel or shingles by building
// type, with seams, blotches, and the odd vent or skylight. Pitched roofs'
// uv runs along the eaves and up the slope, so shingle rows follow the eaves.
vec3 roof(vec2 xz, vec2 footprint, int archetype, float seed) {
	float r1 = rnd(seed, 51.0);
	vec3 base;
	int kind = 0;  // 0 rolled roofing, 1 gravel, 2 shingles
	if (archetype == HOUSE) {
		base = ROOF_SHINGLES[pick(r1, 3)];
		kind = 2;
	} else if (archetype <= PREWAR_APARTMENT || archetype == LOFT) {
		base = r1 < 0.45 ? ROOF_TAR : (r1 < 0.9 ? ROOF_SILVER : ROOF_MEMBRANE);
	} else if (archetype >= PREWAR_OFFICE && archetype <= MODERN_OFFICE) {
		base = r1 < 0.5 ? ROOF_GRAVEL : (r1 < 0.8 ? ROOF_MEMBRANE : ROOF_TAR);
		kind = r1 < 0.5 ? 1 : 0;
	} else {
		base = r1 < 0.5 ? ROOF_MEMBRANE : (r1 < 0.75 ? ROOF_GRAVEL : ROOF_SILVER);
		kind = (r1 >= 0.5 && r1 < 0.75) ? 1 : 0;
	}
	vec3 color = srgb(base) * (0.93 + 0.14 * rnd(seed, 52.0));
	float pixel = max(footprint.x, footprint.y);
	float blotches = value_noise(xz * 0.15 + seed * 40.0) * 0.6 + value_noise(xz * 0.6) * 0.4;
	color *= 0.9 + 0.2 * blotches;
	if (kind == 0) {
		float seams = stripes(xz.x / 0.95, 0.04, footprint.x / 0.95) * visible(0.95, pixel);
		color *= 1.0 - 0.12 * seams;
	} else if (kind == 1) {
		color *= 1.0 + (hash(floor(xz * 12.0)) - 0.5) * 0.25 * visible(0.08, pixel);
	} else {
		color *= 1.0 - 0.25 * stripes(xz.y / 0.2, 0.2, footprint.y / 0.2);
	}
	// Vents, hatches and skylights, each with a little shadow.
	const float CELL = 6.0;
	vec2 cell = floor(xz / CELL);
	float h = hash(cell + seed * 13.0);
	if (h < 0.12 && archetype != HOUSE) {
		vec2 local = xz - cell * CELL;
		vec2 size = vec2(1.2, 1.2) + vec2(hash(cell + 3.1), hash(cell + 5.7)) * 1.8;
		vec2 corner = vec2(0.5) + vec2(hash(cell + 7.3), hash(cell + 9.1)) * (CELL - size - 1.0);
		float box = band(local.x, corner.x, corner.x + size.x, footprint.x) * band(local.y, corner.y, corner.y + size.y, footprint.y);
		float shadow = band(local.x, corner.x + 0.25, corner.x + size.x + 0.35, footprint.x)
				* band(local.y, corner.y + 0.25, corner.y + size.y + 0.35, footprint.y);
		vec3 box_color = mix(color, h < 0.04 ? srgb(vec3(0.55, 0.66, 0.74)) : srgb(vec3(0.74, 0.74, 0.72)), 0.7);
		float fade = smoothstep(4.0, 10.0, size.x / pixel);
		color *= 1.0 - 0.35 * shadow * fade;
		color = mix(color, box_color, box * fade);
	}
	return color;
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

void vertex() {
	aerial_uv = aerial_uv_of(VERTEX);
	float h = (UV.y + 1.0) * 0.01;
	float h2 = h * h;
	wall_moments = vec4(h, h2, h2 * h, h2 * h2);
	float floor_dm = floor(UV2.y + 0.0005);
	building_data = vec3(floor(UV2.x + 0.5), floor_dm, floor(clamp(UV2.y - floor_dm, 0.0, 0.999) * 1024.0));
}

void fragment() {
	vec3 data = floor(building_data + 0.5);
	int code = int(data.x);
	int archetype = code % 64;
	int flags = code / 64;
	float floor_height = max(data.y * 0.1, 2.4);
	float seed = (data.z + 0.5) / 1024.0;
	if (archetype == UNKNOWN) {
		archetype = seed < 0.55 ? WALKUP : POSTWAR_APARTMENT;
	}
	vec2 footprint = max(fwidth(UV), vec2(1e-4));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 photo = aerial_albedo(aerial_uv);

	Surface s;
	float occlusion = 1.0;
	if ((flags & ROOF) != 0) {
		s.albedo = mix(roof(UV, footprint, archetype, seed), photo, aerial_amount(aerial_uv));
		s.emission = vec3(0.0);
		s.glass = 0.0;
	} else if ((flags & PARAPET_INSIDE) != 0) {
		s = parapet_inside(UV, footprint, archetype, flags, seed, wall_top_distance(wall_moments, UV.y));
	} else {
		float below_top = wall_top_distance(wall_moments, UV.y);
		if ((flags & SIGNS) != 0) {
			s = sign_wall(UV, footprint, archetype, flags, floor_height, seed, below_top);
		} else {
			s = facade(UV, footprint, archetype, flags, floor_height, seed, below_top);
		}
		occlusion = mix(canyon_occlusion, 1.0, smoothstep(0.0, canyon_height, UV.y));
	}

	// Glass reflects the sky, more at grazing angles.
	float n_dot_v = clamp(dot(world_normal, world_view), 0.0, 1.0);
	float fresnel = mix(0.3, 1.0, pow(1.0 - n_dot_v, 3.0));
	float mirror = clamp(s.glass * glass_reflection, 0.0, 1.0) * fresnel;
	vec3 reflection = sky_reflection(reflect(-world_view, world_normal)) * mirror;

	ALBEDO = toon_night_albedo(s.albedo * (1.0 - 0.6 * mirror));
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + s.emission + reflection;
	toon_glint = s.glass;

	if (city_lights > 0.0 && (flags & (ROOF | PARAPET_INSIDE)) == 0) {
		// Street lights on the feet of the walls near them.
		float reach = 1.0 - smoothstep(street_light_reach.x, street_light_reach.y, UV.y);
		if (reach > 0.0) {
			vec3 scene_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			EMISSION += ALBEDO * street_light_at(scene_position.xz, length(VERTEX)) * (reach * city_lights);
		}
		// Floodlights on landmarks' masonry setbacks, from the roof below.
		if ((flags & LANDMARK) != 0 && (archetype == PREWAR_OFFICE || archetype == PREWAR_APARTMENT
				|| archetype == HOTEL || archetype == INSTITUTION)) {
			vec2 span = wall_span(wall_moments);
			if (span.x > floodlight_min_height && span.y < 1e3) {
				float flood = 1.0 - smoothstep(0.0, floodlight_reach, UV.y - span.x);
				EMISSION += ALBEDO * srgb(FLOODLIGHT) * (floodlight_strength * flood * city_lights);
			}
		}
	}
}
