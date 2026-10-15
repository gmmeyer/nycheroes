// Buildings, drawn as stylized New York facades from per-building data
// (tools/citygen/facades.py and build_tiles.py). Per vertex:
//   UV    walls: (meters along the wall, meters above the building's base;
//         the walls' feet are sunk 1 m below the base); roofs: world x/z.
//   UV2.x archetype + 64 * flags, a whole number (see the constants below).
//   UV2.y floor height in decimeters + the building's random seed (0..0.999).
// Each building type picks a palette and a window system (punched windows with
// lintels, arched loft windows, ribbon windows, curtain walls); street fronts
// add storefronts with awnings, fire escapes and cornices. Every detail is
// box-filtered or faded by its size on screen, so far away a facade settles
// into its average color instead of shimmering.
// Lighting is the shared toon model (toon.gdshaderinc); glass also reflects a
// simple sky. With an aerial photo (?aerial=1), roofs show it.
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
		if (r1 < 0.5) {
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
	if (landmark) {
		// Landmarks get stone lintels on any punched masonry windows.
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

// Meters from this fragment up to the top of its wall, or a big number where
// that isn't known. A wall triangle's corners sit at just two heights, its
// foot b and its top t; the vertex shader passes the first four powers of the
// height, and since every fragment's interpolated moments m_k mix b^k and t^k
// with the same weights, b and t are the roots of x^2 - s x + p = 0, with s
// and p found from m1..m3. The fourth moment checks that there really were
// only two heights (wall polygons with steps triangulate into some
// triangles with three).
float wall_top_distance(vec4 m, float y) {
	float variance = m.y - m.x * m.x;
	if (abs(variance) < 1e-10) {
		return 1e4;
	}
	float s = (m.z - m.x * m.y) / variance;
	float p = s * m.x - m.y;
	float discriminant = s * s - 4.0 * p;
	if (discriminant < 0.0 || abs(m.w - (s * m.z - p * m.y)) > 0.01 * max(m.w, 1e-8)) {
		return 1e4;
	}
	float top = 0.5 * (s + sqrt(discriminant));
	return top * 100.0 - 1.0 - y;
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
	s.emission = srgb(SHOP_LIGHT) * shop_glow * 0.3 * s.glass * (1.0 - smoothstep(0.2, 0.8, rise)) * mix(0.7, 1.3, r3);
	// Sign band with a row of letters.
	vec3 sign_color = srgb(mix(vec3(0.4), SIGN[pick(r1, 6)], detail));
	float letters = stripes(sx / 0.32, 0.55, footprint.x / 0.32) * band(sx, store_width * 0.22, store_width * 0.78, footprint.x)
			* band(p.y, sign_bottom + sign_height * 0.3, sign_bottom + sign_height * 0.72, footprint.y) * detail;
	vec3 letter_color = dot(sign_color, vec3(0.33)) > 0.3 ? srgb(vec3(0.12)) : srgb(vec3(0.95, 0.93, 0.85));
	float sign_band = band(p.y, sign_bottom, top, footprint.y);
	color = mix(color, mix(sign_color, letter_color, letters), sign_band);
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
		if (f.air_conditioners > 0.0) {
			float unit = step(w3, f.air_conditioners) * band(bx, -0.33, 0.33, footprint.x)
					* band(fy, sill + 0.02, sill + 0.42, footprint.y) * present * detail * upper;
			color = mix(color, srgb(AIR_CONDITIONER) * mix(0.82, 1.0, smoothstep(sill, sill + 0.42, fy)), unit);
			glass *= 1.0 - unit;
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
		}
		color = mix(color, ground_color, ground);
		glass = mix(glass, ground_glass, ground);
		s.emission = ground_emission * ground;
	}

	// Fire escapes on old walk-ups' street fronts.
	if (street && (flags & FIRE_ESCAPES) != 0) {
		vec2 escape = fire_escape(p, footprint, floor_height, f.bay, f.sill * floor_height, seed, detail, below_top);
		color *= 1.0 - escape.y;
		color = mix(color, srgb(IRON), escape.x);
		glass *= 1.0 - escape.x;
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
		} else if (masonry) {
			float coping = band(below_top, -1.0, 0.24, footprint.y);
			float shadow = band(below_top, 0.24, 0.4, footprint.y) * 0.3;
			color *= 1.0 - shadow;
			color = mix(color, f.trim * (f.surface == SIDING ? 0.9 : 1.0), coping);
			glass *= 1.0 - coping;
		} else {
			float cap = band(below_top, -1.0, 0.5, footprint.y);
			color = mix(color, f.frame, cap);
			glass *= 1.0 - cap;
		}
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

// Roofs: tar, silver coating, white membrane, gravel or shingles by building
// type, with seams, blotches, and the odd vent or skylight.
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
	vec3 sky = mix(reflect_horizon, reflect_zenith, smoothstep(0.0, 0.65, r.y));
	return mix(reflect_ground, sky, smoothstep(-0.1, 0.03, r.y));
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
	} else {
		float below_top = wall_top_distance(wall_moments, UV.y);
		s = facade(UV, footprint, archetype, flags, floor_height, seed, below_top);
		occlusion = mix(canyon_occlusion, 1.0, smoothstep(0.0, canyon_height, UV.y));
	}

	// Glass reflects the sky, more at grazing angles.
	float n_dot_v = clamp(dot(world_normal, world_view), 0.0, 1.0);
	float fresnel = mix(0.3, 1.0, pow(1.0 - n_dot_v, 3.0));
	float mirror = clamp(s.glass * glass_reflection, 0.0, 1.0) * fresnel;
	vec3 reflection = sky_reflection(reflect(-world_view, world_normal)) * mirror;

	ALBEDO = s.albedo * (1.0 - 0.6 * mirror);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + s.emission + reflection;
	toon_glint = s.glass;
}
