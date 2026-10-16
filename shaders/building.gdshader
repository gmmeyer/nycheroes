// Buildings, drawn as stylized New York facades from per-building data
// (tools/citygen/facades.py and build_tiles.py). Per vertex:
//   UV    walls: (meters along the wall, meters above the building's base;
//         the walls' feet are sunk 1 m below the base); flat roofs: world
//         x/z; houses' pitched roofs: (meters along the eaves, meters up
//         the slope). Up close, flat roofs have parapets: the walls rise
//         PARAPET_HEIGHT above the roof, with inner faces.
//   UV2.x archetype + 64 * flags, a whole number (see the constants below).
//   UV2.y floor height in decimeters + the building's random seed (0..0.999);
//         on walls plus 64 * the sky they see (tools/citygen/shade.py:
//         darker at their feet down narrow, tall streets; see vertex()).
// Each building type picks a palette and a window system (punched windows with
// lintels, arched loft windows, ribbon windows, curtain walls); street fronts
// add storefronts with awnings, fire escapes and cornices (rows' and
// tenements' deep and bracketed). Masonry buildings carry a wall material
// from facades.py (brownstone, red, brown or buff brick, limestone, paint,
// siding; MATERIAL field), picked by borough, era and historic district, and
// the shader picks each building's shade of it; without one (far merged
// blocks, older tiles) the type's own mix decides. Palettes are tuned against
// photos (docs/REFERENCE.md): muted, weathered masonry and dark glass. Every
// detail is box-filtered or faded by its size on screen, so far away a facade
// settles into its average color instead of shimmering.
// Rowhouses' and walk-ups' stoops (tools/citygen/fronts.py: steps, cheek
// walls, the doorway on the landing; FRONT_PART faces) are painted by
// stoop(): stone treads and risers, cheek walls (or the curbs under iron
// railings, which shaders/fronts.gdshader paints), double doors under a
// transom in a stone surround, lit at night. The walls of a house with a
// stoop (STOOP) have no front door of their own. Rows' deep cornices
// (fronts.py) are FRONT walls, painted like the cornices on the walls.
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
// from above the shop fronts up to 40-60 m, in big LED screens (sign_zone()):
// fitted to each face in columns and tiers, with tall banners, set in black
// cladding with dark gaps, a few ringed in neon or chasing bulbs, with a news
// ticker along the bottom of most walls; One Times Square's walls are a stack
// of screens to the top, and some towers carry more screens higher up. They
// show ads that change every few seconds, most drawn like softly lit photos
// (cartoon portraits, landscapes, film posters), glow by day and blaze at
// night, washing the facade above them in their colors. Times Square's TKTS
// steps glow red and its plazas have granite benches (plaza_piece()). Only
// SIGNS faces pay for any of it.
// Hand-made landmarks (tools/citygen/landmarks.py: the Empire State, Chrysler
// and Woolworth Buildings, One World Trade Center, the Flatiron, 30 Rock,
// Grand Central, the Statue of Liberty) carry their own materials (archetype
// 16 and up): landmark_wall() and landmark_roof() paint limestone piers and
// aluminum spandrels, Nirosta arches with triangular windows, curtain walls,
// terracotta, copper, granite, the torch's gold and Grand Central's clock, and
// light their crowns at night.
// Browsers on Windows compile this through ANGLE with the D3D compiler, which
// inlines every call and slows with the square of the code: the heavy
// helpers (facade_for(), window_light(), the screens' text_line()) are each
// called from one place, wall_texture() from few, the painters passing along
// what they need. See "Shader compile time" in docs/ROADMAP.md.
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
const int MATERIAL = 512;        // flags / MATERIAL % 8: the wall material (MAT_*)
const int STOOP = 4096;          // the building has a stoop: its front door is up there
const int FRONT_PART = 8192;     // flags / FRONT_PART: the part of a stoop this face is (0: none)
// Same as tools/citygen/facades.py.
const float PARAPET_HEIGHT = 1.0;
// The lowest a street canyon reaches up a wall (m; tools/citygen/shade.py's).
const float CANYON_TOP = 8.0;

// Wall materials (facades.py picks one per building by borough, era and
// historic district; MAT_AUTO leaves it to the type's own mix).
const int MAT_AUTO = 0;
const int MAT_BROWNSTONE = 1;
const int MAT_RED_BRICK = 2;
const int MAT_BUFF_BRICK = 3;
const int MAT_LIMESTONE = 4;
const int MAT_BROWN_BRICK = 5;
const int MAT_PAINTED = 6;
const int MAT_SIDING = 7;

// Parts of a stoop (tools/citygen/fronts.py), and its measures (same there).
const int STEPS = 1;       // treads and landing; UV = (m across from its left side, m out from the wall)
const int STOOP_SIDE = 2;  // a cheek wall's outside, down to the ground; UV = (m out from the wall, m above the landing)
const int CHEEK = 3;       // a cheek wall's inside, above the steps; the same UV
const int DOORWAY = 4;     // the front door on the landing; UV = (m across from its left edge, m above the landing)
const int AREAWAY = 5;     // the wall or fence along the front yard; UV = (m along it, m above the ground)
const float STOOP_LANDING = 1.2;  // the landing's depth (m)
const float STEP_RISE = 0.19;
const float STEP_RUN = 0.28;
const float CHEEK_HEIGHT = 0.85;  // the cheek walls' height above the steps
const float DOORWAY_HEIGHT = 3.0;
const float AREAWAY_HEIGHT = 0.8;

// Landmark materials (archetype 16 and up), as tools/citygen/landmarks.py numbers them.
const int LM_FIRST = 16;
const int LM_PLAIN_STONE = 16;
const int LM_PAVING = 17;
const int LM_ESB_BASE = 18;
const int LM_ESB_SHAFT = 19;
const int LM_ESB_CROWN = 20;
const int LM_ESB_MAST = 21;
const int LM_ANTENNA = 22;
const int LM_CHRYSLER_SHAFT = 23;
const int LM_CHRYSLER_CROWN = 24;
const int LM_STEEL = 25;
const int LM_WTC_PODIUM = 26;
const int LM_WTC_GLASS = 27;
const int LM_WTC_SPIRE = 28;
const int LM_FLATIRON = 29;
const int LM_WOOLWORTH = 30;
const int LM_COPPER = 31;
const int LM_LIBERTY = 32;
const int LM_GOLD = 33;
const int LM_PEDESTAL = 34;
const int LM_FORT = 35;
const int LM_GC_FACADE = 36;
const int LM_GC_SCULPTURE = 37;
const int LM_CLOCK = 38;
const int LM_ROCK_SHAFT = 39;
const int LM_WTC_RING = 40;

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

// Palettes, in sRGB. Measured against photos (docs/REFERENCE.md): weathered
// masonry is darker and much less saturated than its name suggests, and the
// toon light and tone mapping saturate dark warm colors further (about twice
// over in shade), so bricks sit at about 0.2-0.25 saturation here and
// brownstone and stone lower.
// Deep red brick, weathered.
const vec3 RED_BRICK[6] = vec3[](vec3(0.60, 0.47, 0.46), vec3(0.56, 0.44, 0.44), vec3(0.64, 0.52, 0.50),
		vec3(0.54, 0.43, 0.43), vec3(0.59, 0.48, 0.47), vec3(0.55, 0.45, 0.44));
// Dark brown and red-brown brick (Bronx apartments, Upper West Side, DUMBO).
const vec3 BROWN_BRICK[5] = vec3[](vec3(0.48, 0.40, 0.38), vec3(0.54, 0.45, 0.41), vec3(0.45, 0.39, 0.37),
		vec3(0.57, 0.48, 0.44), vec3(0.50, 0.44, 0.41));
// Chocolate-brown sandstone.
const vec3 BROWNSTONE[5] = vec3[](vec3(0.52, 0.47, 0.44), vec3(0.57, 0.51, 0.49), vec3(0.48, 0.44, 0.42),
		vec3(0.60, 0.55, 0.52), vec3(0.54, 0.49, 0.48));
// Buff, tan and "blond" brick (Ridgewood, the Grand Concourse).
const vec3 BUFF_BRICK[5] = vec3[](vec3(0.70, 0.62, 0.51), vec3(0.74, 0.66, 0.55), vec3(0.66, 0.58, 0.47),
		vec3(0.71, 0.63, 0.52), vec3(0.65, 0.60, 0.51));
const vec3 WHITE_BRICK[3] = vec3[](vec3(0.77, 0.76, 0.72), vec3(0.81, 0.80, 0.76), vec3(0.71, 0.70, 0.66));
// Limestone and cream.
const vec3 LIMESTONE[5] = vec3[](vec3(0.74, 0.70, 0.63), vec3(0.70, 0.66, 0.58), vec3(0.78, 0.75, 0.68),
		vec3(0.66, 0.63, 0.57), vec3(0.75, 0.69, 0.59));
// Landmark stone: pale gray Indiana limestone; gray, pink and dark granite;
// cream and ivory glazed terracotta.
const vec3 LANDMARK_LIMESTONE[3] = vec3[](vec3(0.77, 0.75, 0.69), vec3(0.73, 0.71, 0.66), vec3(0.81, 0.79, 0.74));
const vec3 GRANITE[3] = vec3[](vec3(0.66, 0.65, 0.62), vec3(0.69, 0.60, 0.55), vec3(0.50, 0.49, 0.47));
const vec3 TERRACOTTA[3] = vec3[](vec3(0.83, 0.80, 0.71), vec3(0.81, 0.77, 0.67), vec3(0.85, 0.83, 0.76));
const vec3 CAST_IRON[5] = vec3[](vec3(0.86, 0.83, 0.76), vec3(0.74, 0.73, 0.69), vec3(0.60, 0.67, 0.61),
		vec3(0.65, 0.70, 0.75), vec3(0.80, 0.74, 0.60));
const vec3 SIDING_PAINT[6] = vec3[](vec3(0.85, 0.83, 0.78), vec3(0.70, 0.76, 0.80), vec3(0.74, 0.77, 0.66),
		vec3(0.81, 0.76, 0.64), vec3(0.64, 0.69, 0.72), vec3(0.86, 0.79, 0.66));
// Painted brick and stucco.
const vec3 STUCCO[5] = vec3[](vec3(0.80, 0.77, 0.69), vec3(0.69, 0.69, 0.66), vec3(0.86, 0.85, 0.81),
		vec3(0.82, 0.76, 0.58), vec3(0.67, 0.72, 0.64));
const vec3 GLASS_DARK[4] = vec3[](vec3(0.23, 0.29, 0.35), vec3(0.20, 0.26, 0.30), vec3(0.26, 0.31, 0.38),
		vec3(0.24, 0.28, 0.31));
// Towers' glass: dark blue-green and gray (it reflects the sky on top).
const vec3 GLASS_TOWER[5] = vec3[](vec3(0.20, 0.29, 0.35), vec3(0.18, 0.27, 0.28), vec3(0.25, 0.33, 0.41),
		vec3(0.27, 0.32, 0.35), vec3(0.15, 0.20, 0.25));
const vec3 SPANDREL[5] = vec3[](vec3(0.27, 0.32, 0.32), vec3(0.21, 0.23, 0.26), vec3(0.48, 0.54, 0.58),
		vec3(0.70, 0.71, 0.68), vec3(0.40, 0.35, 0.29));
const vec3 FRAME_PAINT[5] = vec3[](vec3(0.90, 0.89, 0.85), vec3(0.14, 0.14, 0.14), vec3(0.17, 0.25, 0.20),
		vec3(0.30, 0.23, 0.17), vec3(0.90, 0.89, 0.85));
const vec3 SHADES[4] = vec3[](vec3(0.92, 0.88, 0.76), vec3(0.95, 0.94, 0.90), vec3(0.82, 0.74, 0.60),
		vec3(0.72, 0.80, 0.86));
const vec3 AWNING[8] = vec3[](vec3(0.74, 0.20, 0.17), vec3(0.15, 0.47, 0.29), vec3(0.15, 0.24, 0.43),
		vec3(0.84, 0.47, 0.15), vec3(0.47, 0.15, 0.21), vec3(0.10, 0.45, 0.45), vec3(0.85, 0.65, 0.15),
		vec3(0.18, 0.18, 0.19));
const vec3 SIGN[6] = vec3[](vec3(0.12, 0.13, 0.15), vec3(0.62, 0.12, 0.12), vec3(0.10, 0.30, 0.20),
		vec3(0.92, 0.90, 0.84), vec3(0.12, 0.20, 0.40), vec3(0.88, 0.70, 0.18));
const vec3 CORNICE_PAINT[4] = vec3[](vec3(0.25, 0.29, 0.28), vec3(0.17, 0.17, 0.18), vec3(0.80, 0.77, 0.68),
		vec3(0.45, 0.32, 0.24));
const vec3 TRIM_STONE = vec3(0.82, 0.79, 0.72);
// Front doors: varnished oak, black, dark green, oxblood, gray-blue.
const vec3 DOOR_PAINT[5] = vec3[](vec3(0.36, 0.22, 0.13), vec3(0.11, 0.11, 0.12), vec3(0.13, 0.24, 0.18),
		vec3(0.38, 0.12, 0.11), vec3(0.24, 0.29, 0.34));
// Concrete and cast stone (later stoops).
const vec3 CONCRETE = vec3(0.64, 0.63, 0.60);
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

// Times Square's screens, in sRGB: bright ad colors (hot pink, cyan, yellow,
// violet, orange, green, blue, red), a little muted, as most real ads are
// photos; neon tubes, the dark steel between screens, and the news ticker's
// band and letters.
const vec3 AD_COLORS[8] = vec3[](vec3(0.81, 0.31, 0.55), vec3(0.34, 0.76, 0.89), vec3(0.94, 0.84, 0.39),
		vec3(0.52, 0.31, 0.77), vec3(0.84, 0.51, 0.28), vec3(0.43, 0.87, 0.53), vec3(0.23, 0.35, 0.76),
		vec3(0.80, 0.27, 0.30));
const vec3 NEON[5] = vec3[](vec3(1.0, 0.22, 0.70), vec3(0.20, 0.92, 1.0), vec3(1.0, 0.88, 0.25),
		vec3(0.45, 1.0, 0.30), vec3(1.0, 0.40, 0.12));
const vec3 SIGN_CLADDING = vec3(0.045, 0.045, 0.055);
const vec3 SIGN_BEZEL = vec3(0.18, 0.18, 0.20);
const vec3 SCREEN_OFF = vec3(0.05, 0.05, 0.06);
const vec3 AD_NIGHT_BLUE = vec3(0.035, 0.04, 0.07);
const vec3 TICKER_BAND = vec3(0.03, 0.03, 0.035);
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
const int AD_PORTRAIT = 7;  // a cartoon portrait, head and shoulders, lit like a photo
const int AD_SCENE = 8;     // a landscape photo: sky, a low sun, ridges, a shore
const int AD_POSTER = 9;    // a film poster: a rim-lit figure, light rays, a title
// The kinds wide and tall screens pick from (repeats make a kind likelier).
const int WIDE_ADS[10] = int[](AD_PORTRAIT, AD_PORTRAIT, AD_SCENE, AD_SCENE, AD_POSTER, AD_POSTER, AD_WORD, AD_WAVES,
		AD_GRADIENT, AD_TEXT);
const int TALL_ADS[8] = int[](AD_PRODUCT, AD_PRODUCT, AD_COLUMN, AD_POSTER, AD_POSTER, AD_PORTRAIT, AD_WAVES, AD_GRADIENT);
// Portraits' skin tones and hair, in sRGB.
const vec3 SKIN[5] = vec3[](vec3(0.96, 0.80, 0.69), vec3(0.88, 0.67, 0.52), vec3(0.76, 0.55, 0.40),
		vec3(0.55, 0.37, 0.26), vec3(0.40, 0.26, 0.19));
const vec3 HAIR[5] = vec3[](vec3(0.10, 0.08, 0.07), vec3(0.32, 0.19, 0.10), vec3(0.86, 0.70, 0.40),
		vec3(0.62, 0.24, 0.12), vec3(0.95, 0.45, 0.66));
// How a sign wall's screens are laid out (sign_layout()).
const int LAYOUT_BAND = 0;   // columns of tiers, with a banner on some faces
const int LAYOUT_STACK = 1;  // screens piled one above the other
const int LAYOUT_ROW = 2;    // one tier
// Times Square's own faces: on SIGNS faces the FRONT_PART field says which
// (tools/citygen/times_square.py; 0 is an ordinary sign wall).
const int SIGN_TOWER = 1;   // a sign wall with screens up to its top (One Times Square)
const int TKTS_STEPS = 2;   // the TKTS booth's red glass steps: risers, and treads (ROOF)
const int TKTS_BOOTH = 3;   // the booth's glass sides and back
const int PLAZA_BENCH = 4;  // a granite bench: sides, and seat (ROOF)
const int CORNER_SCREEN = 5;  // a drum of screens around a building corner; steel top and bottom (ROOF)
const float DRUM_HEIGHT = 14.0;  // the drum's (times_square.py's CORNER_DRUMS)
const float TKTS_HEIGHT = 4.9;   // the top step (m)
const float TKTS_RISERS = 27.0;
// The steps' red glass and the benches' granite, in sRGB.
const vec3 TKTS_RED = vec3(0.86, 0.09, 0.11);
const vec3 BENCH_GRANITE = vec3(0.74, 0.73, 0.70);

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
// the base, rising to full by this height (m). Walls with their own sky
// baked in (vertex()) use that instead.
uniform float canyon_occlusion : hint_range(0.0, 1.0) = 0.85;
uniform float canyon_height = 25.0;
// Lit shop windows glow a little even by day.
uniform float shop_glow = 0.35;
// How far tiny far-off window grids are pulled toward their average color
// (little: their box-filtered floors and windows keep the far city's
// texture, as in photos from Top of the Rock).
uniform float distance_calm : hint_range(0.0, 1.0) = 0.1;
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
uniform float sign_day_glow = 0.85;
uniform float sign_night_glow = 1.4;
uniform float neon_glow = 2.2;
uniform vec2 sign_top_range = vec2(40.0, 60.0);
uniform float sign_wash_reach = 16.0;
uniform float ticker_speed = 4.5;
// How brightly the TKTS steps glow at night (by day a little).
uniform float tkts_glow = 1.6;
// What glass reflects at dusk and at night, in sRGB: overhead, at the
// horizon, and the city below.
uniform vec3 dusk_reflect_zenith : source_color = vec3(0.30, 0.38, 0.62);
uniform vec3 dusk_reflect_horizon : source_color = vec3(0.98, 0.70, 0.52);
uniform vec3 dusk_reflect_ground : source_color = vec3(0.30, 0.27, 0.30);
uniform vec3 night_reflect_zenith : source_color = vec3(0.03, 0.05, 0.12);
uniform vec3 night_reflect_horizon : source_color = vec3(0.30, 0.21, 0.22);
uniform vec3 night_reflect_ground : source_color = vec3(0.13, 0.10, 0.09);
// Landmarks at night: the Empire State's tower lights (from the 72nd floor up,
// the crown, the mast; bottom to top, the colors change with the occasion),
// how bright floodlit landmarks are, and the Statue of Liberty's torch.
uniform vec3 esb_lights_low : source_color = vec3(1.0, 0.95, 0.86);
uniform vec3 esb_lights_mid : source_color = vec3(1.0, 0.95, 0.86);
uniform vec3 esb_lights_top : source_color = vec3(1.0, 0.98, 0.94);
uniform float landmark_flood = 1.0;
uniform float torch_glow = 4.0;

// Moments of the wall height at the vertices (see wall_span()).
varying vec4 wall_moments;
// The same for uv.x: where sign walls' faces start and end (sign_zone()).
varying vec4 wall_x_moments;
// UV2 decoded into whole numbers in the vertex shader: (archetype + 64 *
// flags, floor height in dm, seed in 1024ths). Every face has one value, so
// it isn't interpolated (flat): interpolating codes in the millions (stoop
// parts' flags) put some pixels off by one, into another building type's
// palette; fragments still round them, to be safe.
varying flat vec3 building_data;
// A wall's ambient light at its foot, and the height above the building's
// base (m) by which it's back to full (see vertex()).
varying vec2 canyon_shade;

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

// A wall of `material` (MAT_*): its color (linear), the shade picked by r.
vec3 material_wall(int material, float r) {
	if (material == MAT_BROWNSTONE) {
		return srgb(BROWNSTONE[pick(r, 5)]);
	} else if (material == MAT_BUFF_BRICK) {
		return srgb(BUFF_BRICK[pick(r, 5)]);
	} else if (material == MAT_LIMESTONE) {
		return srgb(LIMESTONE[pick(r, 5)]);
	} else if (material == MAT_BROWN_BRICK) {
		return srgb(BROWN_BRICK[pick(r, 5)]);
	} else if (material == MAT_PAINTED) {
		return srgb(STUCCO[pick(r, 5)]);
	} else if (material == MAT_SIDING) {
		return srgb(SIDING_PAINT[pick(r, 6)]);
	}
	return srgb(RED_BRICK[pick(r, 6)]);
}

// The surface of a wall of `material`.
int material_surface(int material) {
	return material == MAT_BROWNSTONE || material == MAT_LIMESTONE ? STONE
			: (material == MAT_PAINTED ? SMOOTH : (material == MAT_SIDING ? SIDING : BRICK));
}

// Lintels, sills and coping for a wall of `material`: carved from the same
// brownstone (a little lighter, so they read), limestone on brick (or
// brownstone on old red brick), white on painted walls and siding.
vec3 material_trim(int material, vec3 wall, float r) {
	if (material == MAT_BROWNSTONE || material == MAT_LIMESTONE) {
		return wall * 1.12;
	} else if (material == MAT_PAINTED || material == MAT_SIDING) {
		return srgb(FRAME_PAINT[0]);
	} else if (material == MAT_RED_BRICK && r < 0.3) {
		return srgb(BROWNSTONE[pick(fract(r * 7.3), 5)]);
	}
	return srgb(TRIM_STONE);
}

// The type's own mix of materials, for buildings without one (far merged
// blocks, older tiles): the cut points of BROWNSTONE, RED_BRICK, BUFF_BRICK,
// LIMESTONE and BROWN_BRICK in r; past the last, PAINTED.
int mixed_material(float r, float brownstone, float red, float buff, float limestone, float brown) {
	return r < brownstone ? MAT_BROWNSTONE : (r < red ? MAT_RED_BRICK : (r < buff ? MAT_BUFF_BRICK
			: (r < limestone ? MAT_LIMESTONE : (r < brown ? MAT_BROWN_BRICK : MAT_PAINTED))));
}

Facade facade_for(int archetype, float seed, bool landmark, int material) {
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

	// The wall material of the types that take one (or else their own mix of
	// materials), and its wall color, surface and trim, worked out once up
	// here rather than in each type's branch, so each material helper is
	// inlined once (see "Shader compile time" in docs/ROADMAP.md). Prewar
	// offices' mix by default; lofts' brick is red or brown by r4.
	vec4 mix_cuts = vec4(0.0, 0.17, 0.48, 0.83);
	float mix_last = 1.0;
	float mix_r = r1;
	if (archetype == ROWHOUSE) {
		mix_cuts = vec4(0.08, 0.39, 0.63, 0.68);
		mix_last = 0.9;
	} else if (archetype == WALKUP) {
		mix_cuts = vec4(0.05, 0.43, 0.64, 0.64);
		mix_last = 0.89;
	} else if (archetype == PREWAR_APARTMENT) {
		mix_cuts = vec4(0.0, 0.22, 0.51, 0.67);
	} else if (archetype == LOFT) {
		mix_cuts = vec4(0.0, 0.6, 0.6, 0.6);
		mix_r = r4;
	}
	int m = material != MAT_AUTO ? material
			: mixed_material(mix_r, mix_cuts.x, mix_cuts.y, mix_cuts.z, mix_cuts.w, mix_last);
	bool loft = archetype == LOFT;
	vec3 m_wall = material_wall(m, loft ? r3 : r4);
	int m_surface = material_surface(m);
	vec3 m_trim = material_trim(m, m_wall, loft ? r2 : r3);

	if (archetype == HOUSE) {
		// Vinyl siding in pale colors, or brick; white trim, some shutters.
		if (r1 < 0.68) {
			f.wall = srgb(SIDING_PAINT[pick(r4, 6)]);
			f.surface = SIDING;
		} else {
			f.wall = srgb(r4 < 0.5 ? RED_BRICK[pick(r2, 6)] : BROWN_BRICK[pick(r2, 5)]);
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
		// Brownstones, limestones and brick rows: tall parlor windows, heavy
		// lintels, cornices painted dark (or light on buff brick).
		f.wall = m_wall;
		f.surface = m_surface;
		f.trim = m_trim;
		f.cornice = srgb(m == MAT_BUFF_BRICK || m == MAT_PAINTED ? (r2 < 0.6 ? CORNICE_PAINT[2] : vec3(0.62, 0.63, 0.62))
				: (r2 < 0.6 ? CORNICE_PAINT[1] : CORNICE_PAINT[pick(r3, 4)]));
		if (m == MAT_BROWNSTONE && r2 >= 0.6) {
			f.cornice = f.wall * 0.8;  // carved in the same stone
		}
		if (m == MAT_SIDING) {
			f.frame = srgb(FRAME_PAINT[0]);
		}
		f.bay = 1.9;
		f.window_width = 0.95;
		f.window_height = 0.5;
		f.sill = 0.24;
		f.side_open = 0.04;
		f.lintels = m != MAT_SIDING;
		f.air_conditioners = 0.12;
	} else if (archetype == WALKUP) {
		// Tenements: red, brown, tan or painted brick with stone trim.
		f.wall = m_wall;
		f.surface = m_surface;
		f.trim = m_trim;
		f.bay = 2.1;
		f.window_width = 0.92;
		f.window_height = 0.45;
		f.sill = 0.27;
		f.side_open = 0.1;
		f.lintels = true;
		f.air_conditioners = 0.22;
	} else if (archetype == PREWAR_APARTMENT) {
		// Brick over a limestone base, or all limestone.
		f.base = srgb(LIMESTONE[pick(r2, 5)]);
		f.wall = m_wall;
		f.surface = m_surface;
		if (m == MAT_LIMESTONE) {
			f.base = f.wall;
			f.base_floors = 1.0;
		} else if ((m == MAT_RED_BRICK || m == MAT_BROWN_BRICK) && r3 < 0.45) {
			f.base = f.wall * 0.9;  // a plain brick base
			f.base_floors = 1.0;
		} else {
			f.base_floors = 2.0;
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
		// White, tan, red or brown brick slabs with wide aluminum windows.
		if (r1 < 0.3) {
			f.wall = srgb(WHITE_BRICK[pick(r4, 3)]);
		} else if (r1 < 0.6) {
			f.wall = srgb(BUFF_BRICK[pick(r4, 5)]);
		} else if (r1 < 0.85) {
			f.wall = srgb(RED_BRICK[pick(r4, 6)]);
		} else {
			f.wall = srgb(BROWN_BRICK[pick(r4, 5)]);
		}
		f.frame = srgb(r2 < 0.6 ? vec3(0.62, 0.64, 0.65) : vec3(0.27, 0.23, 0.19));
		f.accent = srgb(vec3(0.76, 0.75, 0.71));
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
			f.accent = srgb(r2 < 0.6 ? vec3(0.80, 0.80, 0.77) : vec3(0.50, 0.52, 0.53));
			f.frame = srgb(vec3(0.50, 0.53, 0.55));
			f.bay = 1.5;
			f.mullion = 0.07;
			f.spandrel = 0.4;
			f.reflect = 0.7;
			f.balconies = r4 < 0.5 ? 0.4 : 0.0;
		} else {
			f.wall = srgb(r4 < 0.5 ? BUFF_BRICK[pick(r2, 5)] : vec3(0.56, 0.56, 0.54));
			f.surface = r4 < 0.5 ? BRICK : SMOOTH;
			f.glass = srgb(GLASS_TOWER[pick(r3, 5)]) * 0.8;
			f.frame = srgb(vec3(0.22, 0.22, 0.23));
			f.bay = 3.0;
			f.window_width = 2.5;
			f.window_height = 0.72;
			f.sill = 0.1;
			f.reflect = 0.55;
		}
		f.side_open = 0.9;
		f.shades = 0.3;
	} else if (archetype == PREWAR_OFFICE) {
		// Masonry towers: windows in vertical strips between piers, with
		// dark spandrels, over a tall stone base: limestone and cream brick
		// mostly, some gray stone, red and brown brick.
		f.wall = m_wall;
		f.surface = m_surface;
		if (m == MAT_LIMESTONE && r3 > 0.75) {
			f.wall = srgb(vec3(0.62, 0.62, 0.60));  // gray granite or sandstone
		}
		f.base = srgb(LIMESTONE[pick(r2, 5)]);
		f.trim = f.base;
		f.cornice = f.base;
		f.accent = srgb(r3 < 0.5 ? vec3(0.28, 0.26, 0.24) : vec3(0.40, 0.33, 0.28));
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
			f.frame = srgb(r2 < 0.6 ? vec3(0.22, 0.23, 0.24) : vec3(0.58, 0.60, 0.62));
			f.glass = srgb(vec3(0.22, 0.28, 0.31));
			f.bay = 1.5;
			f.mullion = 0.1;
			f.spandrel = 1.1;
			f.reflect = 0.5;
		} else {
			f.wall = srgb(r4 < 0.5 ? WHITE_BRICK[pick(r2, 3)] : LIMESTONE[pick(r2, 5)]);
			f.surface = r4 < 0.5 ? BRICK : STONE;
			f.windows = RIBBON;
			f.frame = srgb(vec3(0.30, 0.31, 0.32));
			f.glass = srgb(vec3(0.18, 0.23, 0.26));
			f.bay = 1.5;
			f.window_height = 0.45;
			f.sill = 0.3;
			f.reflect = 0.45;
		}
		f.side_open = 0.85;
		f.shades = 0.3;
	} else if (archetype == MODERN_OFFICE) {
		// Glass towers with a fine silver or dark grid.
		f.windows = CURTAIN;
		f.glass = srgb(GLASS_TOWER[pick(r1, 5)]);
		f.accent = f.glass * 0.7;
		f.frame = srgb(r2 < 0.6 ? vec3(0.58, 0.62, 0.65) : vec3(0.20, 0.22, 0.24));
		f.bay = 1.5;
		f.mullion = 0.06;
		f.spandrel = 0.7;
		f.reflect = 0.75;
		f.side_open = 1.0;
		f.shades = 0.2;
	} else if (archetype == LOFT) {
		// Cast iron painted cream, gray or pastel, with tall arched windows
		// between columns; or brick with stone trim (deep red and brown in
		// the old warehouse districts).
		if (material == MAT_AUTO && r1 < 0.6) {
			f.wall = srgb(CAST_IRON[pick(r4, 5)]);
			f.surface = SMOOTH;
			f.windows = r3 < 0.65 ? ARCHED : PUNCHED;
			f.trim = f.wall * 1.06;
			f.cornice = f.wall * 0.92;
			f.piers = true;
			f.accent = f.wall * 0.86;
		} else {
			f.wall = m_wall;
			f.surface = m_surface;
			f.trim = m_trim;
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
			f.wall = srgb(r4 < 0.6 ? RED_BRICK[pick(r3, 6)] : BUFF_BRICK[pick(r3, 5)]);
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
		if (material != MAT_AUTO) {
			f.wall = m_wall;
			f.surface = m_surface;
		} else if (r1 < 0.5) {
			f.wall = srgb(r4 < 0.6 ? RED_BRICK[pick(r3, 6)] : BROWN_BRICK[pick(r3, 5)]);
		} else if (r1 < 0.75) {
			f.wall = srgb(vec3(0.56, 0.55, 0.52));
			f.surface = SMOOTH;
		} else {
			f.wall = srgb(r4 < 0.5 ? vec3(0.68, 0.64, 0.55) : vec3(0.47, 0.52, 0.47));
			f.surface = SMOOTH;
		}
		f.windows = FACTORY;
		f.frame = srgb(vec3(0.22, 0.26, 0.25));
		f.glass = srgb(vec3(0.30, 0.34, 0.35));
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
			f.wall = srgb(r4 < 0.7 ? RED_BRICK[pick(r3, 6)] : BROWN_BRICK[pick(r3, 5)]);
		} else if (r1 < 0.8) {
			f.wall = srgb(LIMESTONE[pick(r4, 5)]);
			f.surface = STONE;
		} else {
			f.wall = srgb(BUFF_BRICK[pick(r4, 5)]);
		}
		f.base = srgb(LIMESTONE[pick(r2, 5)]);
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
			f.wall = srgb(r4 < 0.5 ? LIMESTONE[pick(r3, 5)] : BUFF_BRICK[pick(r3, 5)]);
			f.surface = r4 < 0.5 ? STONE : BRICK;
			f.base = srgb(LIMESTONE[pick(r2, 5)]);
			f.base_floors = 2.0;
			f.lintels = true;
			f.cornice = f.base;
		} else {
			f.windows = CURTAIN;
			f.glass = srgb(GLASS_TOWER[pick(r3, 5)]);
			f.accent = srgb(vec3(0.68, 0.68, 0.66));
			f.frame = srgb(vec3(0.38, 0.40, 0.42));
			f.bay = 1.8;
			f.spandrel = 0.9;
			f.reflect = 0.65;
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
		f.wall = srgb(r1 < 0.5 ? vec3(0.60, 0.59, 0.56) : RED_BRICK[pick(r4, 6)]);
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
		// Buildings read light. Three in four of the others are too, most in
		// limestone (the Waldorf Astoria among them): 90% limestone, 6%
		// terracotta, 4% granite.
		float r5 = rnd(seed, 5.0);
		bool office = archetype == PREWAR_OFFICE;
		if (office || r5 < 0.75) {
			if (r5 < (office ? 0.7 : 0.675)) {
				f.wall = srgb(LANDMARK_LIMESTONE[pick(r4, 3)]);
			} else if (office || r5 < 0.72) {
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

// A pixel's lit window, if any: window_light()'s arguments and how much of
// the pixel glows (0: none). facade() and landmark_wall() fill it in and
// fragment() adds the light, so window_light() is inlined once (see "Shader
// compile time" in docs/ROADMAP.md).
struct WindowLight {
	int archetype;
	bool curtain;
	vec2 cell;
	float seed;
	vec2 cell_pixels;
	float up;
	float amount;
};

WindowLight no_window_light() {
	WindowLight w;
	w.archetype = 0;
	w.curtain = false;
	w.cell = vec2(0.0);
	w.seed = 0.0;
	w.cell_pixels = vec2(1.0);
	w.up = 0.0;
	w.amount = 0.0;
	return w;
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

// A wall's facade: `f` is the building's (facade_for()), `wall` its wall
// texture (wall_texture() of f.wall and f.surface at p); `lights` its lit
// window at night.
Surface facade(Facade f, vec3 wall, vec2 p, vec2 footprint, int archetype, int flags, float floor_height, float seed,
		float below_top, out WindowLight lights) {
	bool landmark = (flags & LANDMARK) != 0;
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
		} else if (street && (archetype == MIDCENTURY_OFFICE || archetype == MODERN_OFFICE || f.windows == CURTAIN)) {
			// Lobby: tall glass in a stone surround (masonry offices have doors
			// and windows instead, like DUMBO's lofts between their few shops).
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
		} else if (street && (flags & STOOP) == 0) {
			// Front doors in some bays, in place of the window (houses with a
			// stoop have theirs up on its landing: stoop()).
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
		if (street && (flags & CORNICE) != 0 && (archetype == ROWHOUSE || archetype == WALKUP)) {
			// Rows' and tenements' deep cornices (pressed metal or stone): a
			// crown molding and fascia over a shadowed soffit, big scroll
			// brackets across a frieze with modillions, a deep shadow below.
			float height = clamp(0.36 * floor_height, 1.0, 1.6);
			float t = below_top / height;
			float ft = footprint.y / height;
			const float SPACING = 1.25;
			float bx = (fract(p.x / SPACING) - 0.5) * SPACING;  // m from the nearest bracket's middle
			float half_width = mix(0.15, 0.07, clamp((t - 0.32) / 0.63, 0.0, 1.0));  // a console, narrowing down
			float bracket = band(bx, -half_width, half_width, footprint.x) * band(t, 0.32, 0.95, ft);
			float bracket_shadow = band(bx, half_width, half_width + 0.09, footprint.x) * band(t, 0.36, 0.99, ft);
			float crown = band(t, -1.0, 0.12, ft);
			float fascia = band(t, 0.12, 0.32, ft);
			float soffit = band(t, 0.32, 0.42, ft);
			float frieze = band(t, 0.42, 1.0, ft);
			float modillions = stripes(p.x / 0.31, 0.45, footprint.x / 0.31) * band(t, 0.42, 0.52, ft);
			float coverage = crown + fascia + soffit + frieze;
			vec3 shaded = f.cornice * (crown * 1.25 + fascia * 1.02 + soffit * 0.42
					+ frieze * mix(0.74, 0.5, modillions)) / max(coverage, 1e-3);
			shaded = mix(shaded * (1.0 - 0.4 * bracket_shadow), f.cornice * mix(1.12, 0.9, t), bracket);
			float drop = 0.7 / height;
			float shadow = band(t, 1.0, 1.0 + drop, ft) * (1.0 - smoothstep(1.0, 1.0 + drop, t)) * 0.5;
			color *= 1.0 - shadow;
			color = mix(color, shaded, coverage);
			glass *= (1.0 - coverage) * (1.0 - shadow);
			glow *= 1.0 - coverage;
		} else if (street && (flags & CORNICE) != 0) {
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

	lights = no_window_light();
	if (city_lights > 0.0 && glow > 0.0) {
		lights.archetype = archetype;
		lights.curtain = f.windows == CURTAIN;
		lights.cell = cell;
		lights.seed = seed;
		lights.cell_pixels = cell_size / footprint;
		lights.up = window_up;
		lights.amount = glow * window_glow * city_lights;
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
// `f` and `wall` as for facade().
Surface parapet_inside(Facade f, vec3 wall, vec2 footprint, float below_top) {
	vec3 color = f.windows == CURTAIN ? f.frame : wall * 0.9;
	color = mix(color, f.trim, band(below_top, -1.0, 0.24, footprint.y));
	Surface s;
	s.albedo = color;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	return s;
}

// The stone of a stoop: `f` is the house's facade (facade_for()).
vec3 stoop_stone(Facade f, int archetype, int material, float seed) {
	float r = rnd(seed, 31.0);
	vec3 stone = f.trim;
	if (material == MAT_BROWNSTONE || material == MAT_LIMESTONE) {
		stone = f.wall;
	} else if (material == MAT_SIDING || r < (archetype == WALKUP ? 0.5 : 0.25)) {
		stone = srgb(CONCRETE);
	} else if (material != MAT_PAINTED && r < 0.55) {
		stone = srgb(BROWNSTONE[pick(fract(r * 5.7), 5)]);
	}
	return stone;
}

// A stoop (tools/citygen/fronts.py): steps up to the parlor floor between
// cheek walls, the front door on its landing, and the wall along the front
// yard. Brownstone and limestone houses' stoops are their own stone; brick
// rows' are brownstone, their trim stone or cast concrete. Under iron
// railings the cheek walls are low curbs, and under iron fences the yard's
// wall (fronts.py makes them lower; the iron is in the fronts surface). The
// doorway: double doors with glass panes under a transom, in a stone
// surround with a hood; at night the glass glows and a lamp lights the
// landing.
// `textured` is stoop_stone()'s wall_texture() as STONE at p (treads: at
// p * (0.6, 1)).
Surface stoop(Facade f, vec3 textured, int part, vec2 p, vec2 fp, int material, float seed) {
	float pixel = max(fp.x, fp.y);
	float detail = smoothstep(4.0, 10.0, 0.3 / pixel);
	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	if (part == STEPS) {
		// Treads catching the light, risers in their shade, a bright nose.
		float u = (p.y - STOOP_LANDING) / STEP_RUN;
		float fu = fp.y / STEP_RUN;
		float steps = band(p.y, STOOP_LANDING, 1e4, fp.y);
		float riser = stripes(u, 0.4, fu) * steps;
		float nose = stripes(u - 0.93, 0.07, fu) * steps;
		vec3 color = textured * 1.04;
		color *= 1.0 - 0.3 * riser + 0.12 * nose;
		s.albedo = color;
		return s;
	}
	if (part == STOOP_SIDE || part == CHEEK) {
		// Height above the steps' line (the landing, then down the steps).
		float h = p.y + max(p.x - STOOP_LANDING, 0.0) * (STEP_RISE / STEP_RUN);
		float above = band(h, 0.0, 1e4, fp.y);
		vec3 color = textured;
		// The body under the steps: courses of stone, darker toward the ground.
		color *= 1.0 - 0.25 * stripes(p.y / 0.38, 0.06, fp.y / 0.38) * visible(0.38, pixel) * (1.0 - above);
		color *= mix(0.86, 1.0, smoothstep(-2.5, -0.5, p.y)) * mix(1.0, 0.92, above * float(part == CHEEK));
		float cap = band(h, CHEEK_HEIGHT - 0.11, 1e4, fp.y);
		float under_cap = band(h, CHEEK_HEIGHT - 0.17, CHEEK_HEIGHT - 0.11, fp.y);
		// A solid cheek wall under a molded coping; brownstones carry a sunken
		// panel. (A curb under a railing is too low for either.)
		float panel = (band(h, 0.3, 0.34, fp.y) + band(h, CHEEK_HEIGHT - 0.3, CHEEK_HEIGHT - 0.26, fp.y))
				* float(material == MAT_BROWNSTONE) * detail;
		color = mix(color, color * (1.0 - 0.25 * panel) * mix(1.0, 0.7, under_cap) * mix(1.0, 1.14, cap), above);
		s.albedo = color;
		return s;
	}
	if (part == AREAWAY) {
		// A stone wall under a coping (a fence's curb is too low for one).
		float h = p.y;
		vec3 color = textured;
		color *= mix(0.84, 1.0, smoothstep(-0.2, 0.25, h));
		float cap = band(h, AREAWAY_HEIGHT - 0.1, 1e4, fp.y);
		float under_cap = band(h, AREAWAY_HEIGHT - 0.15, AREAWAY_HEIGHT - 0.1, fp.y);
		color *= mix(1.0, 0.7, under_cap) * mix(1.0, 1.14, cap);
		s.albedo = color;
		return s;
	}
	// The doorway: 1.5 m wide (fronts.DOORWAY_WIDTH), DOORWAY_HEIGHT tall.
	const float WIDTH = 1.5;
	const float PILASTER = 0.17;
	const float OPENING_TOP = 2.6;
	vec3 surround = textured * 1.04;
	float x = p.x - 0.5 * WIDTH;  // m from the middle
	float opening = band(x, -0.5 * WIDTH + PILASTER, 0.5 * WIDTH - PILASTER, fp.x) * band(p.y, -1.0, OPENING_TOP, fp.y);
	vec3 door = srgb(DOOR_PAINT[pick(rnd(seed, 33.0), 5)]);
	vec3 glass = f.glass * 0.8;
	// Two leaves with glass panes over raised panels, a transom above.
	float leaves = band(p.y, -1.0, 2.22, fp.y);
	float transom = band(p.y, 2.3, 2.52, fp.y) * band(x, -0.5 * WIDTH + PILASTER + 0.06, 0.5 * WIDTH - PILASTER - 0.06, fp.x);
	float lx = abs(x);  // m from the meeting stiles
	float panes = band(lx, 0.09, 0.5 * WIDTH - PILASTER - 0.09, fp.x) * band(p.y, 1.12, 2.06, fp.y) * detail;
	float raised = (band(lx, 0.09, 0.5 * WIDTH - PILASTER - 0.09, fp.x) * band(p.y, 0.2, 0.92, fp.y)
			- band(lx, 0.13, 0.5 * WIDTH - PILASTER - 0.13, fp.x) * band(p.y, 0.24, 0.88, fp.y)) * detail;
	float stile = band(lx, -1.0, 0.012, fp.x) * leaves * detail;
	vec3 color = mix(door, glass, panes);
	color *= 1.0 + 0.25 * raised - 0.5 * stile;
	color = mix(mix(door * 0.7, glass, transom), color, leaves);
	// The hood: a crown over a fascia, its shadow on the surround below.
	float hood = band(p.y, OPENING_TOP + 0.06, 1e4, fp.y);
	float crown = band(p.y, DOORWAY_HEIGHT - 0.1, 1e4, fp.y);
	float hood_shadow = band(p.y, OPENING_TOP - 0.12, OPENING_TOP + 0.06, fp.y) * (1.0 - opening);
	surround *= mix(1.0, 1.12, hood) * mix(1.0, 1.18, crown) * (1.0 - 0.35 * hood_shadow);
	color = mix(surround, color, opening);
	color = mix(color, color * 0.75, band(p.y, OPENING_TOP - 0.05, OPENING_TOP, fp.y) * opening);
	float lit_glass = (panes * leaves + transom) * opening;
	s.albedo = color;
	s.glass = lit_glass * 0.5;
	if (city_lights > 0.0) {
		// The hall light through the glass, and a lamp over the door.
		float lamp = 1.0 - smoothstep(0.0, 0.9, length(vec2(x, p.y - OPENING_TOP - 0.25)));
		s.emission = srgb(LAMP_WARM) * ((lit_glass * 1.3 + lamp * 0.4) * city_lights);
	}
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

// A line of text on a screen: text_line()'s arguments (q, height, spaces,
// salt), how much of it shows (cover: 0 for none) and its ink. The ad kinds
// in screen() each set one, and one text_line() call after them draws it, so
// text_line() is inlined once there (see "Shader compile time" in
// docs/ROADMAP.md).
struct TextLine {
	vec2 q;
	float height;
	float spaces;
	float salt;
	float cover;
	vec3 ink;
};

TextLine text_spec(vec2 q, float height, float spaces, float salt, float cover, vec3 ink) {
	TextLine t;
	t.q = q;
	t.height = height;
	t.spaces = spaces;
	t.salt = salt;
	t.cover = cover;
	t.ink = ink;
	return t;
}

// One word of `letters` letters, `height` m tall, centered on `middle` (m
// from the screen's lower left corner, like uv), in `ink`.
TextLine word(vec2 uv, vec2 middle, float height, float letters, float salt, vec2 footprint, vec3 ink) {
	float width = letters * height * 0.8 - height * 0.2;
	vec2 at = uv - middle + vec2(0.5 * width, 0.5 * height);
	return text_spec(at, height, 0.0, salt, band(at.x, 0.0, width, footprint.x), ink);
}

// Rolling color bands: the n-th band's color.
vec3 wave_color(float n, vec3 c1, vec3 c2, vec3 c3) {
	float m = mod(n, 3.0);
	return m < 0.5 ? c1 : (m < 1.5 ? c2 : c3);
}

// An ellipse (center c, radii r) at q: its coverage, anti-aliased over a
// pixel px wide (all in the same units).
float ellipse(vec2 q, vec2 c, vec2 r, float px) {
	float edge = px / min(r.x, r.y);
	return 1.0 - smoothstep(1.0 - edge, 1.0 + edge, length((q - c) / r));
}

// Soft studio light on a rounded shape at d (the position in its radii), lit
// from the left (side -1) or the right (1): never darker than half.
float studio_light(vec2 d, float side) {
	vec3 n = vec3(d, sqrt(max(1.0 - dot(d, d), 0.0)));
	return 0.5 + 0.6 * max(dot(n, normalize(vec3(side * 0.65, 0.45, 0.6))), 0.0);
}

// A standing figure's silhouette, `height` tall with its feet at `foot`
// (screen heights, like q): head, shoulders, body, legs apart. Returns coverage.
float figure(vec2 q, vec2 foot, float height, float px) {
	vec2 f = (q - foot) / height;
	float fpx = px / height;
	float head = ellipse(f, vec2(0.0, 0.9), vec2(0.06, 0.075), fpx);
	float neck = band(f.x, -0.025, 0.025, fpx) * band(f.y, 0.76, 0.86, fpx);
	float shoulders = ellipse(f, vec2(0.0, 0.76), vec2(0.15, 0.05), fpx);
	float half_width = mix(0.085, 0.15, smoothstep(0.42, 0.76, f.y));
	float body = band(f.x, -half_width, half_width, fpx) * band(f.y, 0.4, 0.77, fpx);
	float legs = band(abs(f.x) - 0.035 - 0.07 * (0.42 - f.y), -0.03, 0.03, fpx) * band(f.y, 0.0, 0.44, fpx);
	return max(max(head, neck), max(max(shoulders, body), legs));
}

// What a screen `size` m big shows at `uv` (meters from its lower left
// corner), as light (linear): an ad that changes every 6-12 s (blinking
// between slides) and now and then flashes a color across the whole screen.
// Most are drawn like photos, softly lit: a cartoon portrait, a landscape, a
// film poster; others are bold graphics: a giant glowing word, a sunburst,
// rolling waves, typed-out text, a can, letters down a banner. `id` picks
// everything. Once its shapes are only a few pixels it shows its average
// (also returned, as `average`).
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
	// half the slides are on night blue.
	vec3 ink = (i1 == 1 || i1 == 2 || i1 == 5) ? srgb(vec3(0.07, 0.07, 0.16)) : white;
	vec3 night_blue = srgb(AD_NIGHT_BLUE);
	bool dark = fract(k3 * 5.17) < 0.5;
	float pixel = max(footprint.x, footprint.y);
	float aspect = size.x / size.y;
	vec2 q = uv / size.y;       // in screen heights
	float px = pixel / size.y;  // a pixel, in screen heights
	float which = fract(k2 * 7.31 + k3);
	int kind = aspect < 0.7 ? TALL_ADS[pick(which, 8)] : WIDE_ADS[pick(which, 10)];
	float side = k2 < 0.5 ? -1.0 : 1.0;  // where the light comes from, in photos

	vec3 color;
	TextLine text = text_spec(vec2(0.0), 1.0, 0.0, 0.0, 0.0, white);
	float bar = 0.0;  // AD_WORD's colored bar, over its word
	if (kind == AD_PORTRAIT) {
		// Head and shoulders, softly lit as in a studio, on a soft gradient,
		// with the brand's word beside it (wide screens) or below.
		bool wide = aspect > 1.25;
		float fx = wide ? (k3 < 0.5 ? 0.3 : 0.7) * aspect : 0.5 * aspect;
		float scale = wide ? 1.0 : clamp(aspect * 1.3, 0.6, 1.0);
		vec3 back = dark ? mix(night_blue, c2 * 0.3, q.y)
				: mix(c1 * 0.3, c2 * 0.6, smoothstep(-0.2, 1.2, q.y + 0.2 * sin(q.x * 1.7 + k1 * 6.3)));
		vec3 skin = srgb(SKIN[pick(fract(k1 * 3.7), 5)]);
		vec3 hair = srgb(HAIR[pick(fract(k2 * 5.3), 5)]);
		vec3 shirt = mix(c3, white, 0.15);
		vec2 head_c = vec2(fx + 0.008 * sin(TIME * 0.6 + k1 * 6.3), wide ? 0.6 : 0.64);
		vec2 head_r = vec2(0.14, 0.185) * scale;
		vec2 hd = (q - head_c) / head_r;
		vec2 body_c = vec2(fx, head_c.y - 0.62 * scale);
		vec2 body_r = vec2(0.42, 0.36) * scale;
		color = back;
		// Hair behind the head; the neck, the shoulders over it, the head; the fringe.
		float hair_back = ellipse(q, head_c + vec2(-side * 0.01, 0.03) * scale, head_r * vec2(1.18, 1.08), px);
		color = mix(color, hair * studio_light(hd * 0.85, side), hair_back);
		float neck = band(q.x, fx - 0.06 * scale, fx + 0.06 * scale, px) * band(q.y, body_c.y, head_c.y - 0.1 * scale, px);
		color = mix(color, skin * (side * (q.x - fx) > 0.0 ? 0.9 : 0.62), neck);
		float body = ellipse(q, body_c, body_r, px);
		color = mix(color, shirt * studio_light((q - body_c) / body_r, side), body);
		float head = ellipse(q, head_c, head_r, px);
		color = mix(color, skin * studio_light(hd, side), head);
		float fringe = head * smoothstep(-0.05, 0.05, hd.y - 0.42 + 0.3 * side * hd.x);
		color = mix(color, hair * studio_light(hd, side), fringe);
		// Eyes, blinking now and then, and a smile.
		float open = step(0.05, fract(TIME * 0.23 + k3 * 7.0));
		vec2 eye = vec2(abs(q.x - head_c.x), q.y);
		float eyes = ellipse(eye, vec2(0.055 * scale, head_c.y), vec2(0.022, 0.014 * open + 0.003) * scale, px);
		color = mix(color, srgb(vec3(0.08, 0.06, 0.06)), eyes * head);
		float mouth = ellipse(q, head_c - vec2(0.0, 0.095 * scale), vec2(0.04, 0.012) * scale, px);
		color = mix(color, skin * srgb(vec3(0.72, 0.32, 0.32)), mouth * head);
		// Rim light on the shadowed side.
		float rim = smoothstep(0.8, 1.0, length(hd)) * max(-side * hd.x / max(length(hd), 1e-3), 0.0) * head;
		color += c2 * (0.6 * rim);
		// The brand.
		float height = (wide ? 0.13 : 0.09) * size.y;
		float letters = wide ? 3.0 + floor(k1 * 3.0) : 3.0 + floor(k1 * 2.0);
		vec2 middle = wide ? vec2((fx < 0.5 * aspect ? 0.75 : 0.25) * aspect, 0.5) : vec2(0.5 * aspect, 0.1);
		text = word(uv, middle * size.y, height, letters, k3 * 41.0, footprint, dark ? c1 : white);
		average = mix(mix(back, shirt, 0.25), skin, min(0.3 * scale * scale / aspect, 0.3));
	} else if (kind == AD_SCENE) {
		// A travel "photo", slowly panning: sky, a low sun, hazy ridges, a
		// shore with glints, and a headline across the sky.
		bool sunset = k3 < 0.5;
		vec3 zenith = srgb(sunset ? vec3(0.24, 0.20, 0.50) : vec3(0.20, 0.44, 0.86));
		vec3 horizon = srgb(sunset ? vec3(1.0, 0.56, 0.32) : vec3(0.74, 0.87, 1.0));
		float x = q.x + TIME * 0.015 + k1 * 10.0;
		color = mix(horizon, zenith, smoothstep(0.3, 1.0, q.y));
		vec2 sun = vec2(mix(0.25, 0.75, k2) * aspect, 0.56);
		float to_sun = length(q - sun);
		color += srgb(sunset ? vec3(1.0, 0.72, 0.38) : vec3(1.0, 0.97, 0.9)) * (0.45 * exp(-to_sun * 6.0)
				+ 0.8 * (1.0 - smoothstep(0.065 - px, 0.065 + px, to_sun)));
		float far_ridge = 0.42 + 0.06 * sin(x * 3.1) + 0.03 * sin(x * 7.7 + 1.3);
		float near_ridge = 0.29 + 0.05 * sin(x * 4.3 + 2.0) + 0.025 * sin(x * 11.0);
		vec3 far_hills = mix(horizon, srgb(sunset ? vec3(0.40, 0.22, 0.42) : vec3(0.32, 0.46, 0.62)), 0.6);
		vec3 near_hills = srgb(sunset ? vec3(0.13, 0.08, 0.17) : vec3(0.16, 0.36, 0.22));
		color = mix(color, far_hills, smoothstep(far_ridge + px, far_ridge - px, q.y));
		color = mix(color, near_hills, smoothstep(near_ridge + px, near_ridge - px, q.y));
		float glints = stripes(q.y * 40.0 + sin(x * 9.0 + TIME) * 0.6, 0.15, px * 40.0) * (1.0 - smoothstep(0.0, 0.25, abs(q.x - sun.x)));
		vec3 water = mix(zenith, horizon, 0.45) * 0.75 + horizon * (0.5 * glints);
		color = mix(color, water, smoothstep(0.16 + px, 0.16 - px, q.y));
		text = text_spec(uv - size * vec2(0.08, 0.84), size.y * 0.1, 0.18, k2 * 70.0,
				band(uv.x, size.x * 0.08, size.x * 0.75, footprint.x), white);
		average = mix(mix(horizon, zenith, 0.5), near_hills, 0.3) + 0.03;
	} else if (kind == AD_POSTER) {
		// A film poster: a dark figure against a glow, light rays behind, a
		// big glowing title below.
		vec2 d = (q - vec2(0.5 * aspect, 0.6)) / vec2(max(aspect, 0.5), 1.0);
		color = srgb(vec3(0.02, 0.02, 0.035)) + c1 * (0.75 * exp(-3.0 * length(d)));
		vec2 from = q - vec2(0.5 * aspect, 1.1);
		const float RAYS = 18.0 / 6.2832;
		float rays = stripes(atan(from.y, from.x) * RAYS + TIME * 0.03, 0.4, px / max(length(from), 1e-3) * RAYS);
		color += c1 * (0.14 * rays * smoothstep(0.2, 1.0, q.y));
		float height = min(0.72, 1.15 * aspect);
		vec2 foot = vec2(0.5 * aspect, 0.2);
		color = mix(color, srgb(vec3(0.03, 0.03, 0.04)), figure(q, foot, height, px));
		float letters = clamp(floor(0.8 * aspect / 0.08), 3.0, 7.0);
		float title_height = min(0.1, 0.85 * aspect / (letters * 0.8)) * size.y;
		text = word(uv, vec2(0.5 * size.x, 0.1 * size.y), title_height, letters, k1 * 23.0, footprint, mix(c3, white, 0.5) * 1.2);
		average = srgb(vec3(0.03)) + c1 * 0.22;
	} else if (kind == AD_GRADIENT) {
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
		text = text_spec(uv - size * vec2(0.08, 0.1), size.y * 0.12, 0.2, k3 * 50.0,
				band(uv.x, size.x * 0.08, size.x * 0.92, footprint.x), white);
		average = mix(mix(tone_a, tone_b, 0.5), c3, min(3.1 * radius * radius / aspect, 0.5)) + 0.06;
	} else if (kind == AD_TEXT) {
		// Three lines of text, typing themselves out line by line.
		vec3 back = dark ? night_blue : c1;
		ink = dark ? c1 : ink;
		color = back * mix(0.75, 1.0, q.y);
		float row = clamp(floor((0.93 - q.y) / 0.27), 0.0, 2.0);
		float height = size.y * (row == 0.0 ? 0.2 : 0.17);
		float typed = size.x * 0.07 + (since - 0.4 - 0.7 * row) * size.x * 0.9;
		text = text_spec(uv - vec2(size.x * 0.07, size.y * (0.66 - 0.27 * row)), height, 0.18, k1 * 31.0 + row * 7.0,
				band(uv.x, size.x * 0.07, min(size.x * 0.93, typed), footprint.x), ink);
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
		text = text_spec(uv - size * vec2(0.1, 0.42), size.y * 0.16, 0.15, k2 * 60.0,
				band(uv.x, size.x * 0.1, size.x * 0.9, footprint.x), white);
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
		text = text_spec(at, height, 0.0, k1 * 77.0, across, c1 * (1.15 + 0.15 * sin(TIME * 4.0 + k2 * 6.3)));
		bar = across * band(at.y, -0.3 * height, -0.18 * height, footprint.y);
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

	// The kind's line of text, then AD_WORD's bar over it.
	color = mix(color, text.ink, text_line(text.q, text.height, text.spaces, text.salt, footprint) * text.cover);
	color = mix(color, c3, bar);

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

// Which screen of a sign wall p is on, within the zone from lo0 to hi0 (wall
// meters). On a face of known `width` (whose uv.x starts at its left corner;
// `facing` tells the building's faces apart), the zone is cut into columns
// across it; elsewhere (width 0) into bays that run on along the building. LAYOUT_BAND: columns 13-30 m wide (per
// building), some faces with a tall banner at one end, each column cut into
// tiers 9-22 m high, a few tiers into two screens side by side. LAYOUT_STACK:
// screens 5-14 m high piled one above the other, as wide as the zone (One
// Times Square). LAYOUT_ROW: one tier. Returns the screen's id and rectangle
// (lo, hi: wall meters, gaps included).
float sign_layout(vec2 p, vec2 lo0, vec2 hi0, float width, float facing, float seed, int layout, out vec2 lo, out vec2 hi) {
	float salt = seed * 977.0 + (width > 0.0 ? facing * 0.731 : 0.0);
	float id;
	lo = lo0;
	hi = hi0;
	if (width > 0.0) {
		float banner_odds = hash(vec2(salt, 4.0));
		if (layout == LAYOUT_BAND && hi0.y - lo0.y > 12.0 && hi0.x - lo0.x > 16.0 && banner_odds < 0.45) {
			float banner = clamp((hi0.x - lo0.x) * 0.16, 3.5, 7.0);
			bool left = fract(banner_odds * 7.7) < 0.5;
			float split = left ? lo0.x + banner : hi0.x - banner;
			if (left ? p.x < split : p.x >= split) {
				lo.x = left ? lo0.x : split;
				hi.x = left ? split : hi0.x;
				return salt + 63.0;
			}
			lo.x = left ? split : lo0.x;
			hi.x = left ? hi0.x : split;
		}
		float target = layout == LAYOUT_STACK ? 26.0 : mix(13.0, 30.0, rnd(seed, 81.0));
		float n = max(1.0, floor((hi.x - lo.x) / target + 0.5));
		float column_width = (hi.x - lo.x) / n;
		float c = clamp(floor((p.x - lo.x) / column_width), 0.0, n - 1.0);
		lo.x += c * column_width;
		hi.x = lo.x + column_width;
		id = salt + c * 7.0;
	} else {
		float bay = mix(14.0, 28.0, rnd(seed, 81.0));
		float shift = rnd(seed, 82.0) * bay;
		float b = floor((p.x + shift) / bay);
		lo.x = b * bay - shift;
		hi.x = lo.x + bay;
		id = salt + b * 7.0;
	}
	if (layout == LAYOUT_STACK) {
		// Up from the bottom; a thin one left at the top joins the one below.
		float y = lo0.y;
		for (int k = 0; k < 16; k++) {
			float h = mix(5.0, 14.0, hash(vec2(id + float(k), 2.3)));
			bool last = y + h > hi0.y - 3.0;
			if (last || p.y < y + h) {
				lo.y = y;
				hi.y = last ? hi0.y : y + h;
				id += float(k) * 13.0;
				break;
			}
			y += h;
		}
		return id;
	}
	float count = layout == LAYOUT_ROW ? 1.0 : max(1.0, floor((hi0.y - lo0.y) / mix(9.0, 22.0, hash(vec2(id, 1.7))) + 0.5));
	float tier = (hi0.y - lo0.y) / count;
	float t = clamp(floor((p.y - lo0.y) / tier), 0.0, count - 1.0);
	lo.y = lo0.y + t * tier;
	hi.y = lo.y + tier;
	id += t * 3.0;
	float pair = hash(vec2(id, 3.1));
	float w = hi.x - lo.x;
	if (pair < 0.3 && w > 12.0) {
		float split = lo.x + w * (pair < 0.15 ? 0.62 : 0.38);
		bool right = p.x >= split;
		lo.x = right ? split : lo.x;
		hi.x = right ? hi.x : split;
		id += right ? 1.0 : 0.0;
	}
	return id;
}

// A sign wall's screens in the zone from lo0 to hi0 (see sign_layout()), set
// in black cladding with dark gaps between them, each in a thin bezel, a few
// ringed in neon or chasing bulbs; bands on most walls have a news ticker
// along the bottom. `strength` is how bright they are now.
Surface billboards(vec2 p, vec2 footprint, vec2 lo0, vec2 hi0, float width, float facing, float seed, int layout, float strength) {
	const float BEZEL = 0.12;
	float gap = mix(0.45, 1.0, rnd(seed, 91.0));  // half the cladding between screens (m)
	float pixel = max(footprint.x, footprint.y);
	Surface s;
	s.albedo = srgb(SIGN_CLADDING);
	s.emission = vec3(0.0);
	s.glass = 0.0;
	vec2 screens_lo = lo0;
	if (layout == LAYOUT_BAND && rnd(seed, 84.0) < 0.6 && hi0.y - lo0.y > 8.0) {
		float bottom = lo0.y + 1.8;
		screens_lo.y = bottom;
		if (p.y < bottom) {
			// The ticker: letters scrolling along a dark band between lit edges.
			float foot = lo0.y + 0.2;
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
	float id = sign_layout(p, screens_lo, hi0, width, facing, seed, layout, lo, hi) * 0.618 + seed * 1031.0;
	vec2 size = max(hi - lo - 2.0 * gap, vec2(0.3));
	float inside = band(p.x, lo.x + gap, hi.x - gap, footprint.x) * band(p.y, lo.y + gap, hi.y - gap, footprint.y);
	float bezel = band(p.x, lo.x + gap - BEZEL, hi.x - gap + BEZEL, footprint.x)
			* band(p.y, lo.y + gap - BEZEL, hi.y - gap + BEZEL, footprint.y);
	vec3 average;
	vec3 light = screen(p - lo - gap, size, id, footprint, average) * mix(0.85, 1.1, hash(vec2(id, 8.3)));
	if (pixel < 0.016) {
		// Right up close, the LEDs' grid.
		float grid = max(stripes(p.x / 0.025, 0.3, footprint.x / 0.025), stripes(p.y / 0.025, 0.3, footprint.y / 0.025));
		light *= 1.0 - 0.5 * grid * visible(0.025, pixel);
	}
	s.emission = light * (inside * strength);
	s.albedo = mix(mix(s.albedo, srgb(SIGN_BEZEL), bezel), srgb(SCREEN_OFF), inside);
	// Neon tubes around a few screens; chasing bulbs around fewer.
	float tubes = hash(vec2(id, 3.3));
	if (tubes < 0.22) {
		bool bulbs = tubes < 0.07;
		float a = gap - BEZEL - (bulbs ? 0.3 : 0.2);
		float c = gap - BEZEL - 0.06;
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
	vec3 wall_average = 0.5 * mix(ad_color(pick(rnd(seed, 85.0), 8)), ad_color(pick(rnd(seed, 86.0), 8)), 0.5);
	s.emission = mix(s.emission, wall_average * strength, 1.0 - smoothstep(2.0, 5.0, min(size.x, size.y) / pixel));
	return s;
}

// Where a sign wall's screens are (sign_zone()), for sign_wall().
struct SignZone {
	vec2 lo;       // the zone of screens this pixel is in or under (wall meters)
	vec2 hi;
	float z0;      // the main band of screens, whose light washes the wall at night
	float z1;
	float width;   // the face's width, 0 where it isn't known
	float facing;  // which way the face looks (one of 16 compass sectors)
	float cover;   // how much of the pixel the zone covers
	int layout;
};

// A street wall in Times Square's sign district: shops at street level, as on
// any street; above them screens up to 40-60 m (or near the top of a lower
// wall), on One Times Square (SIGN_TOWER) a stack of screens up to its top,
// and on some tall towers a row of screens near the top or a stack up one
// edge of a face. `face`: the face's span in uv.x (see wall_span()); faces at
// least 6 m wide start at 0 (build_tiles' SIGN_FACE_MIN), so their screens
// fit them. `normal`: the wall's (world).
SignZone sign_zone(vec2 p, vec2 footprint, int flags, float floor_height, float seed, float below_top, vec2 face, vec3 normal) {
	SignZone zone;
	bool tower = flags / FRONT_PART == SIGN_TOWER;
	zone.width = abs(face.x) < 0.3 && face.y >= 6.0 && face.y < 1e3 ? face.y : 0.0;
	zone.facing = floor(atan(normal.z, normal.x) * (16.0 / 6.2832) + 8.0);
	float parapet = (flags & PARAPET) != 0 ? PARAPET_HEIGHT : 0.0;
	float margin = parapet + (tower ? 0.6 : ((flags & CORNICE) != 0 ? 2.2 : 0.8));
	float top = p.y + below_top;  // the wall's top (far up where it isn't known)
	zone.z0 = min(floor_height, 4.4) + 0.6;
	zone.z1 = tower ? top - margin : min(top - margin, mix(sign_top_range.x, sign_top_range.y, rnd(seed, 80.0)));
	// The face's corners keep a strip of cladding.
	float edge = mix(0.5, 1.3, rnd(seed, 90.0));
	float width = zone.width;
	zone.lo = vec2(width > 0.0 ? edge : -1e4, zone.z0);
	zone.hi = vec2(width > 0.0 ? width - edge : 1e4, zone.z1);
	zone.layout = tower ? LAYOUT_STACK : LAYOUT_BAND;
	if (!tower && below_top < 1e3 && top - margin > zone.z1 + 24.0 && p.y > zone.z1 + 1.0) {
		// Higher up on tall towers, some have a row of screens near the top,
		// some a stack up one edge.
		float r = rnd(seed, 95.0);
		if (r < 0.35) {
			zone.lo.y = top - margin - mix(8.0, 14.0, rnd(seed, 96.0));
			zone.hi.y = top - margin;
			zone.layout = LAYOUT_ROW;
		} else if (r < 0.65 && width >= 16.0) {
			float column = mix(7.0, 11.0, rnd(seed, 97.0));
			zone.lo = vec2(rnd(seed, 98.0) < 0.5 ? edge : width - edge - column, zone.z1 + mix(2.0, 8.0, rnd(seed, 99.0)));
			zone.hi = vec2(zone.lo.x + column, min(top - margin, zone.lo.y + mix(24.0, 60.0, rnd(seed, 100.0))));
			zone.layout = LAYOUT_STACK;
		} else {
			zone.hi.y = zone.lo.y;
		}
	}
	zone.cover = zone.hi.y - zone.lo.y > 2.5
			? band(p.y, zone.lo.y, zone.hi.y, footprint.y) * band(p.x, zone.lo.x - edge, zone.hi.x + edge, footprint.x) : 0.0;
	return zone;
}

// A sign wall's screens (see sign_zone()) over its facade `s`, and at night
// the facade above the main band and the shop fronts below washed in their
// colored light.
Surface sign_wall(Surface s, vec2 p, vec2 footprint, float seed, SignZone zone) {
	float strength = mix(sign_day_glow, sign_night_glow, max(night, city_lights));
	if (zone.cover > 0.0) {
		Surface boards = billboards(p, footprint, zone.lo, zone.hi, zone.width, zone.facing, seed, zone.layout, strength);
		s.albedo = mix(s.albedo, boards.albedo, zone.cover);
		s.emission = mix(s.emission, boards.emission, zone.cover);
		s.glass = mix(s.glass, boards.glass, zone.cover);
	}
	if (city_lights > 0.0 && zone.cover < 1.0 && zone.z1 - zone.z0 > 2.5) {
		float wash = p.y > zone.z1 ? 1.0 - smoothstep(0.0, sign_wash_reach, p.y - zone.z1) : 1.0 - smoothstep(0.0, 4.0, zone.z0 - p.y);
		vec3 tint = mix(ad_color(pick(rnd(seed, 85.0), 8)), ad_color(pick(rnd(seed, 86.0), 8)),
				0.5 + 0.5 * sin(TIME * 0.5 + seed * 40.0));
		s.emission += s.albedo * tint * (1.5 * wash * wash * city_lights);
	}
	return s;
}

// The corner drum's screen (CORNER_SCREEN), `p` m around the drum and up from
// the building's ground: an invented cola brand, always on, a white ribbon
// swooping around it over red, bubbles rising, the brand's word twice around;
// every 9 s, bubbles rising through dark red instead. Steel bands at its top
// and bottom. `strength` as for billboards().
Surface corner_screen(vec2 p, vec2 footprint, float below_top, float strength) {
	float y = DRUM_HEIGHT - below_top;  // m up the drum
	float pixel = max(footprint.x, footprint.y);
	Surface s;
	s.albedo = srgb(SIGN_CLADDING);
	s.emission = vec3(0.0);
	s.glass = 0.0;
	float screen = band(y, 0.6, DRUM_HEIGHT - 0.6, footprint.y);
	vec3 red = srgb(vec3(0.82, 0.04, 0.08));
	vec3 white = vec3(1.0);
	float wave = 5.2 + 2.2 * sin(p.x * 0.35 - TIME * 0.9) + 0.6 * sin(p.x * 0.9 + TIME * 0.4);
	float ribbon = band(y - wave, -0.7, 0.7, footprint.y * 1.5);
	float stripe = band(y - wave, -0.12, 0.08, footprint.y);
	float column = floor(p.x / 1.3);
	float r = hash(vec2(column, 4.2));
	float rise = fract(r - TIME * mix(0.05, 0.12, r)) * (DRUM_HEIGHT + 2.0) - 1.0;
	float size = mix(0.12, 0.35, hash(vec2(column, 9.1)));
	float bubble = band(length(vec2(fract(p.x / 1.3) * 1.3 - 0.65, y - rise)), size - 0.06, size, pixel) * visible(size, pixel);
	vec3 color;
	if (mod(floor(TIME / 9.0), 2.0) < 0.5) {
		color = mix(red * mix(0.75, 1.05, y / DRUM_HEIGHT), white, ribbon);
		color = mix(color, red, stripe * ribbon);
		color = mix(color, white * 0.9, bubble * 0.8);
		float x = mod(p.x, 13.5);
		color = mix(color, white, text_line(vec2(x - 1.5, y - 9.0), 3.2, 0.0, 17.0, footprint) * band(x, 1.5, 11.5, footprint.x));
	} else {
		color = srgb(vec3(0.16, 0.0, 0.02)) + red * (0.3 * (1.0 - y / DRUM_HEIGHT));
		color = mix(mix(color, mix(red, white, 0.5), bubble), red * 1.2, ribbon * 0.5);
	}
	color = mix(red * 0.85, color, visible(1.5, pixel));
	s.emission = color * (screen * strength);
	s.albedo = mix(s.albedo, srgb(SCREEN_OFF), screen);
	return s;
}

// Times Square's own pieces (tools/citygen/times_square.py), by part: the
// TKTS booth's red glass steps (treads are flagged ROOF, with world x/z uv;
// risers are walls, uv.y m above the square), lit from inside, glowing at
// night; the booth's glass sides, with the steps' edges glowing through, and
// its back with the ticket windows; the plazas' granite benches; the corner
// drum (corner_screen()). `face` as in sign_zone().
Surface plaza_piece(int part, vec2 p, vec2 footprint, int flags, float below_top, vec2 face) {
	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	bool top = (flags & ROOF) != 0;
	float lit = max(night, city_lights);
	float pixel = max(footprint.x, footprint.y);
	vec3 red = srgb(TKTS_RED);
	if (part == TKTS_STEPS) {
		if (top) {
			// Glass treads in panels, glossy, lit from below (less than the risers,
			// so the steps read as steps).
			float across = 0.875 * p.x + 0.485 * p.y;  // world x/z, meters across the avenues
			float seams = centered_stripes(across / 1.5, 0.04, pixel / 1.5);
			s.albedo = red * (0.8 - 0.3 * seams);
			s.glass = 0.4;
			s.emission = red * ((0.08 + 0.22 * tkts_glow * lit) * (1.0 - 0.6 * seams));
		} else {
			// Risers, the brightest part at night, under a steel nosing.
			float rise = TKTS_HEIGHT / TKTS_RISERS;
			float nosing = band(fract(p.y / rise), 0.8, 1.0, footprint.y / rise) * visible(rise, footprint.y);
			s.albedo = mix(red * 1.1, srgb(vec3(0.20, 0.20, 0.22)), nosing);
			s.emission = red * ((0.35 + tkts_glow * lit) * (1.0 - nosing));
		}
	} else if (part == TKTS_BOOTH) {
		// Dark glass in steel mullions.
		float mullions = centered_stripes(p.x / 1.5, 0.05, footprint.x / 1.5);
		s.albedo = mix(srgb(vec3(0.15, 0.10, 0.11)), srgb(vec3(0.34, 0.34, 0.36)), mullions);
		s.glass = 0.6 * (1.0 - mullions);
		if (face.y - face.x > 2.0 && face.y < 1e3) {
			// The back, under the top step: ticket windows, the steps glowing above.
			float windows = band(p.y, 0.9, 2.4, footprint.y) * band(fract(p.x / 2.2), 0.12, 0.88, footprint.x / 2.2)
					* band(p.x, 0.8, face.y - 0.8, footprint.x);
			s.albedo = mix(s.albedo, srgb(vec3(0.55, 0.50, 0.40)), windows);
			s.glass *= 1.0 - windows;
			s.emission = srgb(LOBBY_LIGHT) * (windows * (0.25 + 1.4 * lit)) + red * (0.7 * lit * band(p.y, 2.8, TKTS_HEIGHT, footprint.y));
		} else {
			// A side: each step's edge glows through the glass.
			float step_edge = 1.0 - smoothstep(0.0, 0.22, below_top);
			s.emission = red * ((0.25 + tkts_glow * lit) * step_edge + 0.35 * lit * (1.0 - step_edge));
		}
	} else if (part == CORNER_SCREEN) {
		s.albedo = srgb(SIGN_CLADDING);
		if (!top) {
			s = corner_screen(p, footprint, below_top, mix(sign_day_glow, sign_night_glow, lit));
		}
	} else {
		// PLAZA_BENCH: speckled granite, the seat a little lighter.
		float speckle = value_noise(p * 7.0) * visible(0.15, pixel);
		s.albedo = srgb(BENCH_GRANITE) * (top ? 1.06 : 0.9) * (1.0 - 0.18 * speckle);
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

// --- Hand-made landmarks (tools/citygen/landmarks.py) ---
// Their faces carry a landmark material in the archetype slot (16 and up),
// and UV2.y's whole part is a param: on walls the face's width in dm * 4 + a
// variant. UV is (m from the face's left corner, m above the landmark's
// ground) unless a material says otherwise. Each material is painted here;
// windows fit each face exactly (piers on the corners), and at night offices
// light up like the data buildings' while crowns, the statue and the torch
// are floodlit.

// The Empire State: limestone, aluminum spandrels, the chrome-nickel steel
// strips running up beside every column of windows.
const vec3 ESB_LIMESTONE = vec3(0.86, 0.82, 0.72);
const vec3 ESB_ALUMINUM = vec3(0.60, 0.62, 0.65);
const vec3 ESB_STEEL = vec3(0.93, 0.94, 0.96);
const vec3 LM_GLASS = vec3(0.22, 0.28, 0.34);
// The Chrysler Building: white and gray brick, Nirosta steel.
const vec3 CHRYSLER_WHITE = vec3(0.91, 0.90, 0.86);
const vec3 CHRYSLER_GRAY = vec3(0.50, 0.51, 0.54);
const vec3 NIROSTA = vec3(0.70, 0.73, 0.78);
// One World Trade Center: blue-gray glass, silver mullions, prismatic fins.
const vec3 WTC_GLASS_COLOR = vec3(0.34, 0.48, 0.60);
const vec3 WTC_MULLION = vec3(0.66, 0.70, 0.74);
// Stone and terracotta.
const vec3 FLATIRON_STONE = vec3(0.73, 0.71, 0.66);
const vec3 WOOLWORTH_CREAM = vec3(0.94, 0.90, 0.80);
const vec3 GC_LIMESTONE = vec3(0.88, 0.84, 0.75);
const vec3 ROCK_LIMESTONE = vec3(0.87, 0.83, 0.74);
const vec3 STONY_CREEK = vec3(0.82, 0.74, 0.68);   // the pedestal's pink granite
const vec3 FORT_GRANITE = vec3(0.64, 0.63, 0.60);
const vec3 PAVING_STONE = vec3(0.70, 0.69, 0.66);
// Copper gone green, the statue's lighter verdigris, the torch's gold leaf.
const vec3 VERDIGRIS = vec3(0.40, 0.68, 0.58);
const vec3 LIBERTY_GREEN = vec3(0.47, 0.74, 0.64);
const vec3 GOLD_LEAF = vec3(1.00, 0.78, 0.30);
// Grand Central's Tiffany clock: opalescent face, colored ring.
const vec3 CLOCK_FACE = vec3(0.98, 0.94, 0.80);
const vec3 CLOCK_RING[3] = vec3[](vec3(0.80, 0.22, 0.16), vec3(0.95, 0.72, 0.20), vec3(0.18, 0.36, 0.62));
const vec3 FLOOD_WARM = vec3(1.0, 0.88, 0.70);
const vec3 FLOOD_COOL = vec3(0.86, 1.0, 0.96);

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

// The Empire State's tower lights' color at this height.
vec3 esb_light(float height) {
	return height < 315.0 ? esb_lights_low : (height < 342.5 ? esb_lights_mid : esb_lights_top);
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

// A wall of a landmark (see the material list in landmarks.py). The windowed
// walls share one grid painter fed by a few numbers per material, so the
// heavier helpers (wall_texture, storefront) appear once each here; `lights`
// is the lit window, if any, as for facade().
Surface landmark_wall(int material, int variant, vec2 p, vec2 fp, float width, vec3 world_normal,
		out WindowLight lights) {
	lights = no_window_light();
	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	float pixel = max(fp.x, fp.y);
	float salt = float(material) * 0.0371;

	// The wall's stone or brick.
	vec3 base = srgb(PAVING_STONE);
	int surface = SMOOTH;
	float scale = 1.0;
	if (material <= LM_ESB_CROWN) {
		base = srgb(ESB_LIMESTONE);
		surface = STONE;
	} else if (material == LM_CHRYSLER_SHAFT) {
		base = srgb(CHRYSLER_WHITE);
		surface = BRICK;
	} else if (material == LM_FLATIRON) {
		base = srgb(FLATIRON_STONE);
		surface = STONE;
	} else if (material == LM_WOOLWORTH) {
		base = srgb(WOOLWORTH_CREAM);
		surface = STONE;
	} else if (material == LM_ROCK_SHAFT) {
		base = srgb(ROCK_LIMESTONE);
		surface = STONE;
	} else if (material == LM_PEDESTAL) {
		base = srgb(STONY_CREEK);
		surface = STONE;
	} else if (material == LM_FORT) {
		base = srgb(FORT_GRANITE);
		surface = STONE;
		scale = 0.7;
	} else if (material == LM_GC_FACADE) {
		base = srgb(GC_LIMESTONE);
		surface = STONE;
	}
	vec3 stone = wall_texture(base, surface, p * scale, fp * scale);
	vec3 color = stone;

	// Windowed walls: piers between columns of windows, fitted to the face.
	float bay = 0.0;
	float window = 1.0;
	float floor_height = 3.8;
	float sill = 0.8;
	float head = 3.0;
	float edge_width = 0.0;
	vec3 column = stone;     // between a column's windows (spandrels)
	vec3 edge = stone;       // lines along the columns' edges
	vec3 glass = srgb(LM_GLASS);
	float column_glass = 0.0;  // how reflective the spandrels are
	float shops = 0.0;       // storefronts up to this height
	float lobby = 0.0;       // lobby glass up to this height
	int occupant = PREWAR_OFFICE;
	if (material == LM_ESB_SHAFT || material == LM_ESB_BASE) {
		stone *= 0.95 + 0.08 * value_noise(p * vec2(0.07, 0.02));
		bool lower = material == LM_ESB_BASE;
		bay = lower ? 3.1 : 2.6;
		window = lower ? 1.9 : 1.2;
		floor_height = lower ? 5.0 : 3.81;
		sill = lower ? 1.0 : 0.85;
		head = lower ? 4.1 : 3.05;
		edge_width = lower ? 0.0 : 0.1;
		column = srgb(ESB_ALUMINUM);
		edge = srgb(ESB_STEEL);
		column_glass = 0.3;
		shops = lower ? 5.0 : 0.0;
	} else if (material == LM_ESB_CROWN) {
		// Aluminum fins up the crown's walls, narrow windows between.
		bay = 1.6;
		window = 0.55;
		sill = 0.6;
		head = 3.2;
		column = mix(stone, srgb(ESB_STEEL) * 0.9, 0.8);
		column_glass = 0.5;
	} else if (material == LM_CHRYSLER_SHAFT) {
		bay = 1.9;
		window = 1.05;
		floor_height = 3.7;
		sill = 0.9;
		head = 2.95;
		// Gray brick between a column's windows, and down the corners.
		float corners = min(band(p.x, -1.0, 0.9, fp.x) + band(p.x, width - 0.9, width + 1.0, fp.x), 1.0);
		stone = mix(stone, srgb(CHRYSLER_GRAY), corners * 0.8);
		column = mix(stone, srgb(CHRYSLER_GRAY), 0.85);
		shops = 5.0;
	} else if (material == LM_FLATIRON && variant != 1) {
		// Bay windows bow out along the long sides; rusticated lower floors;
		// string courses.
		stone *= width > 30.0 ? 0.94 + 0.07 * sin(p.x * (2.0 * PI / 6.4)) : 1.0;
		stone *= 1.0 - 0.25 * stripes(p.y / 0.62, 0.08, fp.y / 0.62) * (1.0 - band(p.y, 15.0, 1e4, fp.y));
		stone = mix(stone, stone * 1.08, stripes((p.y - 14.8) / 22.2, 0.5 / 22.2, fp.y / 22.2));
		bay = 1.6;
		window = 0.95;
		floor_height = 3.7;
		sill = 0.85;
		head = 2.9;
		column = stone;
		shops = 4.6;
	} else if (material == LM_WOOLWORTH) {
		// Spandrels with blue and gold ornament; a shadow line down the piers.
		float ornament = stripes(p.x / 0.36, 0.5, fp.x / 0.36) * visible(0.36, pixel);
		column = mix(srgb(vec3(0.88, 0.83, 0.71)), srgb(vec3(0.52, 0.62, 0.74)), ornament * 0.35);
		edge = stone * 0.8;
		edge_width = 0.12;
		bay = 1.75;
		window = 1.1;
		floor_height = 3.9;
		sill = 0.7;
		head = 3.2;
		shops = 6.0;
	} else if (material == LM_ROCK_SHAFT) {
		stone *= 0.96 + 0.06 * value_noise(p * vec2(0.05, 0.02));
		column = srgb(vec3(0.30, 0.27, 0.24));
		bay = 1.6;
		window = 0.85;
		sill = 0.8;
		head = 3.1;
		lobby = 7.0;
	} else if (material == LM_WTC_GLASS) {
		// A curtain wall: glass, slim mullions, a band at each floor's slab.
		stone = srgb(WTC_MULLION);
		column = srgb(WTC_MULLION);
		glass = srgb(WTC_GLASS_COLOR);
		bay = 1.52;
		window = 1.45;
		floor_height = 4.0;
		sill = 0.4;
		head = 4.0;
		column_glass = 0.4;
		occupant = MODERN_OFFICE;
	}

	if (bay > 0.0) {
		vec2 cell;
		vec2 size;
		vec4 g = lm_grid(p, fp, width, bay, window, floor_height, sill, head, edge_width, cell, size);
		float detail = smoothstep(5.0, 12.0, min(size.x, size.y) / pixel);
		vec3 pane = glass * mix(1.0, mix(0.8, 1.2, hash(cell + salt * 97.0)), detail)
				+ glass_sweep(p, occupant == MODERN_OFFICE ? 16.0 : 6.0, detail);
		color = mix(stone, column, g.y);
		color = mix(color, pane, g.x);
		color = mix(color, edge, g.z * 0.9);
		s.glass = g.x * 0.9 + g.z * 0.5 + (g.y - g.x) * column_glass + (1.0 - g.y) * column_glass * 0.5;
		float lit = g.x;
		vec3 after_dark = vec3(0.0);
		float ground = 0.0;
		if (shops > 0.0 && p.y < shops + 0.2) {
			Surface shop = storefront(p, fp, shops, size.x, salt, color, stone * 0.92, detail);
			ground = 1.0 - band(p.y, shops, 1e4, fp.y);
			color = mix(color, shop.albedo, ground);
			s.glass = mix(s.glass, shop.glass, ground);
			after_dark = shop.emission * ground;
		} else if (lobby > 0.0 && p.y < lobby + 0.2) {
			ground = 1.0 - band(p.y, lobby, 1e4, fp.y);
			float hall = band(p.y, 0.3, lobby - 0.6, fp.y) * (1.0 - centered_stripes(p.x / 2.4, 0.12, fp.x / 2.4));
			color = mix(color, mix(stone, glass, hall), ground);
			s.glass = mix(s.glass, hall * 0.8, ground);
			after_dark = srgb(LOBBY_LIGHT) * (hall * lobby_glow * city_lights * ground);
		}
		lit *= 1.0 - ground;
		if (city_lights > 0.0 && lit > 0.0) {
			lights.archetype = occupant;
			lights.curtain = occupant == MODERN_OFFICE;
			lights.cell = cell;
			lights.seed = salt;
			lights.cell_pixels = size / fp;
			lights.up = g.w;
			lights.amount = lit * window_glow * city_lights;
		}
		s.emission = after_dark;
	} else if (material == LM_FLATIRON) {
		color = lm_cornice(stone * 1.04, p, fp, 81.6, 83.4);
	} else if (material == LM_ESB_MAST) {
		// Aluminum ribs; the drum between the wings (variant 1) in strips of glass.
		vec3 metal = srgb(vec3(0.66, 0.68, 0.72));
		float ribs = stripes(p.x / 0.9, 0.3, fp.x / 0.9);
		color = metal * (1.0 - 0.2 * ribs) * (0.95 + 0.1 * smoothstep(342.0, 380.0, p.y));
		float windows = band(p.y, 371.0, 376.6, fp.y) * stripes(p.x / 1.15, 0.7, fp.x / 1.15);
		if (variant == 1) {
			windows = max(windows, stripes(p.x / 1.5, 0.45, fp.x / 1.5) * (1.0 - stripes(p.y / 3.8, 0.12, fp.y / 3.8)));
		}
		color = mix(color, srgb(LM_GLASS), windows);
		s.glass = 0.55 + 0.35 * windows;
		s.emission = srgb(LAMP_SOFT) * (windows * 1.2 * city_lights);
	} else if (material == LM_ANTENNA) {
		vec3 steel = srgb(vec3(0.52, 0.53, 0.55));
		float lattice = max(stripes((p.x + p.y) / 1.4, 0.16, length(fp) / 1.4), stripes((p.x - p.y) / 1.4, 0.16, length(fp) / 1.4));
		color = mix(steel * 0.7, steel * 1.25, lattice * visible(0.3, pixel));
		s.glass = 0.2;
		// Aircraft warning lights, blinking (the lower ones only at night).
		float blink = step(0.45, fract(TIME * 0.5));
		float lamps = band(p.y, 441.4, 443.2, fp.y) + (band(p.y, 418.0, 419.0, fp.y) + band(p.y, 400.0, 401.0, fp.y)) * city_lights;
		s.emission = srgb(vec3(1.0, 0.1, 0.05)) * (lamps * blink * 6.0 * max(city_lights, 0.2));
	} else if (material == LM_CHRYSLER_CROWN) {
		// UV: m from the face's middle, m above the arch's springing; the
		// arch's radius is the param's width. Triangular windows radiate
		// around each arch like a sunburst, between steel ribs.
		float radius = width;
		float r = length(p);
		float a = atan(max(p.y, 0.0), p.x);
		float n = max(6.0, floor(PI * radius / 1.9));
		float cells = a / PI * n;
		float fcell = length(fp) / max(r, 0.5) / PI * n;
		float r_in = radius - 3.0;
		float r_out = radius - 0.4;
		float t = (r - r_in) / (r_out - r_in);
		float ft = length(fp) / (r_out - r_in);
		float half_width = 0.42 * (1.0 - clamp(t, 0.0, 1.0));
		float above = step(0.0, p.y);
		// Far off, once the triangles are a few pixels, their average (they
		// fill 42% of their band), so the crown still glows at night.
		float exact = band(fract(cells) - 0.5, -half_width, half_width, fcell);
		float pane = band(t, 0.0, 1.0, ft) * above * mix(0.42, exact, visible(1.5, pixel));
		float ribs = centered_stripes(cells, 0.1, fcell) * above + stripes(p.x / 1.1, 0.12, fp.x / 1.1) * (1.0 - above);
		float rim = band(r, radius - 0.35, radius + 1.0, length(fp)) * above;
		vec3 steel = srgb(NIROSTA) * (0.9 + 0.12 * ribs + 0.12 * rim);
		color = mix(steel, srgb(vec3(0.08, 0.09, 0.12)), pane);
		s.glass = mix(0.55, 0.15, pane);
		s.emission = srgb(vec3(1.0, 0.97, 0.90)) * (pane * 4.0 * city_lights) + steel * (0.4 * landmark_flood * city_lights);
	} else if (material == LM_STEEL) {
		color = srgb(NIROSTA) * (0.92 + 0.1 * stripes(p.x / 0.5, 0.3, fp.x / 0.5));
		s.glass = 0.7;
		s.emission = color * (0.35 * landmark_flood * city_lights);
	} else if (material == LM_WTC_PODIUM) {
		float fin = stripes(p.x / 1.52, 0.42, fp.x / 1.52);
		color = mix(srgb(vec3(0.52, 0.60, 0.66)), srgb(vec3(0.82, 0.86, 0.90)), fin);
		color *= 0.94 + 0.08 * value_noise(vec2(p.x * 0.05, p.y * 0.3));
		s.glass = 0.75;
		s.emission = color * (0.22 * city_lights);
		// The lobby, glass from the street up 15 m.
		float hall = 1.0 - band(p.y, 15.0, 1e4, fp.y);
		if (hall > 0.0) {
			float mullions = min(centered_stripes(p.x / 3.0, 0.05, fp.x / 3.0) + band(p.y, 7.3, 7.6, fp.y), 1.0);
			color = mix(color, mix(srgb(LM_GLASS) * 1.2, srgb(WTC_MULLION), mullions), hall);
			s.glass = mix(s.glass, 0.9 * (1.0 - mullions), hall);
			s.emission = mix(s.emission, srgb(LOBBY_LIGHT) * ((1.0 - mullions) * lobby_glow * city_lights), hall);
		}
	} else if (material == LM_WTC_SPIRE || material == LM_WTC_RING) {
		color = srgb(vec3(0.88, 0.89, 0.90));
		if (material == LM_WTC_RING) {
			// Open steelwork: diagonal members against the dark inside.
			float members = max(stripes((p.x + p.y) / 3.0, 0.14, length(fp) / 3.0), stripes((p.x - p.y) / 3.0, 0.14, length(fp) / 3.0));
			members = max(members, band(p.y, 425.0, 427.0, fp.y) + band(p.y, 416.0, 417.6, fp.y));
			color = mix(srgb(vec3(0.16, 0.18, 0.21)), color, min(members, 1.0));
		}
		s.glass = 0.35;
		// The beacon at the very top.
		float beacon = band(p.y, 537.5, 542.0, fp.y);
		s.emission = vec3(1.0) * beacon * (2.0 + 6.0 * city_lights) * (0.6 + 0.4 * sin(TIME * 2.0));
	} else if (material == LM_COPPER) {
		float seams = stripes(p.x / 0.6, 0.12, fp.x / 0.6) * visible(0.6, pixel);
		color = srgb(VERDIGRIS) * (0.9 + 0.18 * value_noise(vec2(p.x * 0.8, p.y * 0.15))) * (1.0 - 0.15 * seams);
		s.glass = 0.1;
	} else if (material == LM_LIBERTY) {
		color = srgb(LIBERTY_GREEN) * (0.9 + 0.14 * value_noise(p * vec2(0.7, 0.12)) + 0.05 * value_noise(p * 3.0));
		if (variant == 1) {
			// The tablet: JULY IV MDCCLXXVI.
			float text = text_line(vec2(p.x - 0.4, p.y - 3.25), 0.62, 0.15, 17.0, fp) * band(p.x, 0.4, 3.75, fp.x);
			color = mix(color, color * 0.55, text);
		}
		s.glass = 0.08;
	} else if (material == LM_GOLD) {
		color = srgb(GOLD_LEAF) * (0.85 + 0.3 * value_noise(p * vec2(2.0, 1.2)));
		s.glass = 0.6;
		float flicker = 0.9 + 0.1 * sin(TIME * 7.0 + p.y * 3.0);
		s.emission = color * 0.35 + srgb(vec3(1.0, 0.62, 0.18)) * (torch_glow * city_lights * flicker);
	} else if (material == LM_PEDESTAL || material == LM_FORT) {
		color = stone * (0.93 + 0.1 * value_noise(p * 0.3));
		if (variant == 1) {
			// A loggia's back wall: dark openings over a balustrade.
			float opening = band(p.y, 32.2, 37.0, fp.y) * (1.0 - centered_stripes(p.x / 2.0, 0.3, fp.x / 2.0));
			color = mix(color * 0.85, color * 0.3, opening);
		}
	} else if (material == LM_GC_FACADE || material == LM_GC_SCULPTURE) {
		float light = 0.0;  // glass lit from inside at night
		if (material == LM_GC_SCULPTURE) {
			color = srgb(vec3(0.82, 0.80, 0.74)) * (0.9 + 0.15 * value_noise(p * 0.8));
		} else if (variant == 2) {
			// A gable end of the concourse: a great lunette window.
			vec2 d = vec2(p.x - width * 0.5, p.y - 33.3);
			float r = length(d);
			float pane = 1.0 - smoothstep(6.4 - pixel, 6.4 + pixel, r);
			float bars = max(centered_stripes(atan(d.y, d.x) / PI * 9.0, 0.08, pixel / max(r, 0.5) * 3.0),
					stripes(r / 1.6, 0.08, pixel / 1.6));
			color = mix(stone, mix(srgb(LM_GLASS), srgb(vec3(0.30, 0.32, 0.30)), bars), pane);
			s.glass = pane * (1.0 - bars) * 0.8;
			light = s.glass;
		} else {
			float x = p.x - width * 0.5;
			// Rusticated base.
			color *= 1.0 - 0.3 * stripes(p.y / 0.7, 0.07, fp.y / 0.7) * (1.0 - band(p.y, 7.5, 1e4, fp.y));
			if (variant == 1 && abs(x) < 20.0) {
				// The three great windows, paired columns between them.
				float ax = x - floor(x / 13.0 + 0.5) * 13.0;
				float top = 21.5 + sqrt(max(4.6 * 4.6 - ax * ax, 0.0));
				float pane = band(ax, -4.6, 4.6, fp.x) * band(p.y, 8.0, top, fp.y);
				float grid = max(centered_stripes(ax / 1.15, 0.1, fp.x / 1.15), centered_stripes(p.y / 1.6, 0.08, fp.y / 1.6));
				float columns = (band(abs(ax), 5.2, 6.3, fp.x) + band(abs(ax), 6.7, 7.8, fp.x) * step(abs(x), 16.0))
						* band(p.y, 7.5, 26.2, fp.y);
				vec3 fluted = stone * (1.04 - 0.12 * stripes(p.x / 0.22, 0.4, fp.x / 0.22));
				color = mix(color, fluted * 1.05, min(columns, 1.0));
				color = mix(color, mix(srgb(LM_GLASS) * 1.1, srgb(vec3(0.28, 0.30, 0.28)), grid), pane);
				s.glass = pane * (1.0 - grid) * 0.8;
				light = s.glass;
				// The doors under the windows.
				float door = band(ax, -2.2, 2.2, fp.x) * band(p.y, -1.0, 5.6, fp.y);
				color = mix(color, srgb(vec3(0.24, 0.20, 0.16)), door);
				light += door * 0.8;
			} else {
				// The wings: two rows of tall windows.
				float wx = centered_stripes(x / 4.4 - 0.5, 2.0 / 4.4, fp.x / 4.4);
				float pane = wx * (band(p.y, 9.5, 14.2, fp.y) + band(p.y, 17.4, 23.0, fp.y));
				color = mix(color, srgb(LM_GLASS), pane);
				s.glass = pane * 0.8;
				light = pane * 0.6;
			}
			// Entablature, cornice and attic.
			color = mix(color, stone * 1.07, band(p.y, 26.2, 26.6, fp.y));
			color = mix(color, lm_cornice(stone, p, fp, 26.6, 28.0), band(p.y, 26.6, 28.0, fp.y));
			color *= 1.0 - 0.18 * band(p.y, 28.0, 28.6, fp.y);
		}
		s.emission = srgb(SHOP_LIGHT) * (light * 1.1 * city_lights);
	} else if (material == LM_CLOCK) {
		// UV: m right of and above the clock's center. The hands keep the game's time.
		float r = length(p);
		float a = atan(p.x, p.y);  // clockwise from 12
		color = srgb(CLOCK_FACE);
		float ring = band(r, 1.55, 2.1, pixel);
		color = mix(color, srgb(CLOCK_RING[int(mod(floor((a + PI) / (PI / 6.0)), 3.0))]), ring);
		float marks = band(r, 1.18, 1.5, pixel) * centered_stripes(a / (PI / 6.0), 0.12, pixel / max(r, 0.3) / (PI / 6.0));
		float hours = mod(clock_hours, 12.0);
		vec2 hour_hand = vec2(sin(hours / 12.0 * 2.0 * PI), cos(hours / 12.0 * 2.0 * PI));
		vec2 minute_hand = vec2(sin(fract(clock_hours) * 2.0 * PI), cos(fract(clock_hours) * 2.0 * PI));
		float hand = band(abs(p.x * hour_hand.y - p.y * hour_hand.x), -1.0, 0.07, pixel) * band(dot(p, hour_hand), -0.15, 0.95, pixel);
		hand = max(hand, band(abs(p.x * minute_hand.y - p.y * minute_hand.x), -1.0, 0.045, pixel) * band(dot(p, minute_hand), -0.2, 1.4, pixel));
		hand = max(max(hand, 1.0 - smoothstep(0.1, 0.1 + pixel, r)), marks);
		color = mix(color, srgb(vec3(0.12, 0.10, 0.08)), hand);
		s.glass = 0.3;
		s.emission = color * (1.0 - hand) * (1.4 * city_lights) * (1.0 - ring * 0.4);
	}

	// Floodlights at night.
	if (city_lights > 0.0) {
		vec3 flood = vec3(0.0);
		if (material <= LM_ESB_MAST && material != LM_PAVING) {
			// The Empire State's tower lights, from the 72nd floor up.
			float strength = material == LM_ESB_MAST ? 2.2 : (material == LM_ESB_CROWN || material == LM_PLAIN_STONE ? 1.6 : 1.0);
			flood = esb_light(p.y) * (strength * step(266.0, p.y));
		} else if (material == LM_ANTENNA) {
			flood = esb_light(400.0) * 0.6;
		} else if (material == LM_WTC_SPIRE || material == LM_WTC_RING) {
			flood = vec3(1.1);
		} else if (material == LM_FLATIRON) {
			flood = srgb(FLOOD_WARM) * (0.8 * smoothstep(70.0, 82.0, p.y));
		} else if (material == LM_WOOLWORTH) {
			// From the tower's shoulders up.
			flood = srgb(FLOOD_WARM) * (0.45 * smoothstep(110.0, 130.0, p.y) + 0.9 * smoothstep(170.0, 185.0, p.y));
		} else if (material == LM_COPPER) {
			flood = srgb(FLOOD_WARM) * (1.2 * step(150.0, p.y));
		} else if (material == LM_LIBERTY) {
			// Floodlit from the fort below: faces turned down and out catch the most.
			flood = srgb(FLOOD_COOL) * (0.9 * (0.35 + 0.65 * clamp(0.6 - world_normal.y, 0.0, 1.0)));
		} else if (material == LM_PEDESTAL || material == LM_FORT) {
			flood = srgb(FLOOD_WARM) * (material == LM_FORT ? 0.4 : 0.6);
		} else if (material == LM_GC_FACADE || material == LM_GC_SCULPTURE) {
			flood = srgb(FLOOD_WARM) * mix(1.0, 0.55, clamp(p.y / 40.0, 0.0, 1.0));
		} else if (material == LM_ROCK_SHAFT) {
			flood = srgb(vec3(1.0, 0.96, 0.9)) * smoothstep(236.0, 248.0, p.y);
		} else if (material == LM_WTC_GLASS) {
			// The observatory floors near the top.
			s.emission += srgb(LAMP_COOL) * (0.8 * s.glass * step(384.0, p.y) * city_lights);
		}
		s.emission += color * flood * (landmark_flood * city_lights);
	}
	s.albedo = color;
	return s;
}

// A landmark's roof: paving, copper, steel, the statue's copper or gold.
Surface landmark_roof(int material, vec2 p, vec2 fp) {
	Surface s;
	s.emission = vec3(0.0);
	s.glass = 0.0;
	float pixel = max(fp.x, fp.y);
	vec3 color;
	if (material == LM_COPPER) {
		color = srgb(VERDIGRIS) * (0.9 + 0.18 * value_noise(p * 0.5));
	} else if (material == LM_STEEL || material == LM_CHRYSLER_CROWN || material == LM_ESB_MAST) {
		color = srgb(NIROSTA) * 0.9;
		s.glass = 0.6;
	} else if (material == LM_LIBERTY) {
		color = srgb(LIBERTY_GREEN) * (0.9 + 0.14 * value_noise(p * 0.7));
		s.emission = color * srgb(FLOOD_COOL) * (0.45 * landmark_flood * city_lights);
	} else if (material == LM_GOLD) {
		color = srgb(GOLD_LEAF);
		s.glass = 0.6;
		s.emission = color * 0.35 + srgb(vec3(1.0, 0.62, 0.18)) * (torch_glow * city_lights);
	} else if (material == LM_PEDESTAL || material == LM_FORT) {
		color = wall_texture(srgb(material == LM_FORT ? FORT_GRANITE : STONY_CREEK), STONE, p, fp);
	} else {
		// Paving slabs on terraces and decks.
		float joints = max(stripes(p.x / 1.2, 0.04, fp.x / 1.2), stripes(p.y / 1.2, 0.04, fp.y / 1.2)) * visible(1.2, pixel);
		color = srgb(PAVING_STONE) * (0.92 + 0.12 * value_noise(p * 0.4)) * (1.0 - 0.18 * joints);
	}
	s.albedo = color;
	return s;
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
	float x = (UV.x + 1.0) * 0.01;
	float x2 = x * x;
	wall_x_moments = vec4(x, x2, x2 * x, x2 * x2);
	// Walls' sky (tools/citygen/shade.py) in UV2.y's high bits, 64 * (share +
	// 16 * reach): the share of the sky the wall's foot doesn't see (15ths)
	// and how high up the street canyon reaches (CANYON_TOP * exp2((reach - 1)
	// * 0.68) m); landmarks' faces (whose UV2.y is a param) and older tiles
	// have none, and get canyon_occlusion up to canyon_height.
	float code = floor(UV2.x + 0.5);
	float baked = mod(code, 64.0) < float(LM_FIRST) ? floor(UV2.y / 64.0) : 0.0;
	float rest = UV2.y - 64.0 * baked;
	float floor_dm = floor(rest + 0.0005);
	building_data = vec3(code, floor_dm, floor(clamp(rest - floor_dm, 0.0, 0.999) * 1024.0));
	canyon_shade = baked >= 16.0
			? vec2(mix(sky_light.x, sky_light.y, mod(baked, 16.0) / 15.0), CANYON_TOP * exp2((floor(baked / 16.0) - 1.0) * 0.68))
			: vec2(canyon_occlusion, canyon_height);
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

	// The foot and top of this wall triangle, and on Times Square's sign walls
	// the face's span across (wall_span()), worked out once here for all the
	// painters below (see "Shader compile time" in docs/ROADMAP.md).
	vec2 span = wall_span(wall_moments);
	float below_top = span.y - UV.y;  // m up to the top of the wall (big where unknown)
	vec2 face = vec2(-1e4, 1e4);
	if ((flags & SIGNS) != 0) {
		face = wall_span(wall_x_moments);
	}

	Surface s;
	// Walls' sky light, less low down in a street canyon (vertex()).
	float canyon = mix(canyon_shade.x, 1.0, smoothstep(0.0, canyon_shade.y, UV.y));
	float occlusion = 1.0;
	WindowLight lights = no_window_light();
	bool landmark = archetype >= LM_FIRST;
	if (landmark) {
		// UV2.y's whole part: the face's width in dm * 4 + a variant.
		int param = int(data.y);
		if ((flags & ROOF) != 0) {
			s = landmark_roof(archetype, UV, footprint);
		} else {
			s = landmark_wall(archetype, param % 4, UV, footprint, float(param / 4) * 0.1, world_normal, lights);
			bool height_uv = archetype != LM_CHRYSLER_CROWN && archetype != LM_CLOCK && archetype != LM_LIBERTY
					&& archetype != LM_GOLD;
			occlusion = height_uv ? canyon : 1.0;
		}
	} else if ((flags & SIGNS) != 0 && flags >= 2 * FRONT_PART) {
		// Times Square's own pieces: the TKTS steps, benches, the corner drum.
		s = plaza_piece(flags / FRONT_PART, UV, footprint, flags, below_top, face);
		occlusion = (flags & ROOF) != 0 ? 1.0 : canyon;
	} else if ((flags & ROOF) != 0 && (flags < FRONT_PART || (flags & SIGNS) != 0)) {
		// Roofs (a stoop's treads are flagged ROOF too, but painted by stoop()).
		s.albedo = mix(roof(UV, footprint, archetype, seed), photo, aerial_amount(aerial_uv));
		s.emission = vec3(0.0);
		s.glass = 0.0;
	} else {
		// Walls, parapets' inner faces and stoops share one facade_for() and
		// one wall_texture() call, so each is inlined once.
		int part = flags / FRONT_PART;
		bool stoop_part = part > 0 && (flags & SIGNS) == 0;
		int material = (flags / MATERIAL) % 8;
		Facade f = facade_for(archetype, seed, (flags & LANDMARK) != 0 && !stoop_part, material);
		vec3 stone = f.wall;
		int surface = f.surface;
		vec2 scale = vec2(1.0);
		if (stoop_part) {
			stone = stoop_stone(f, archetype, material, seed);
			surface = STONE;
			scale = part == STEPS ? vec2(0.6, 1.0) : vec2(1.0);
		}
		vec3 textured = wall_texture(stone, surface, UV * scale, footprint * scale);
		if (stoop_part) {
			s = stoop(f, textured, part, UV, footprint, material, seed);
			occlusion = canyon_shade.x;
		} else if ((flags & PARAPET_INSIDE) != 0) {
			s = parapet_inside(f, textured, footprint, below_top);
		} else {
			// Sign walls paint their facade only where the screens leave it showing.
			bool signs = (flags & SIGNS) != 0;
			SignZone zone;
			zone.cover = 0.0;
			if (signs) {
				zone = sign_zone(UV, footprint, flags, floor_height, seed, below_top, face, world_normal);
			}
			s.albedo = vec3(0.0);
			s.emission = vec3(0.0);
			s.glass = 0.0;
			if (zone.cover < 1.0) {
				s = facade(f, textured, UV, footprint, archetype, flags, floor_height, seed, below_top, lights);
			}
			if (signs) {
				s = sign_wall(s, UV, footprint, seed, zone);
				lights.amount *= 1.0 - zone.cover;  // as sign_wall() mixes the facade's light
			}
			occlusion = canyon;
		}
	}

	if (lights.amount > 0.0) {
		s.emission += window_light(lights.archetype, lights.curtain, lights.cell, lights.seed, lights.cell_pixels, lights.up)
				* lights.amount;
	}

	// Glass reflects the sky, more at grazing angles.
	float n_dot_v = clamp(dot(world_normal, world_view), 0.0, 1.0);
	float fresnel = mix(0.3, 1.0, pow(1.0 - n_dot_v, 3.0));
	float mirror = clamp(s.glass * glass_reflection, 0.0, 1.0) * fresnel;
	vec3 reflection = sky_reflection(reflect(-world_view, world_normal)) * mirror;

	ALBEDO = toon_night_albedo(s.albedo * (1.0 - 0.6 * mirror));
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + s.emission + reflection;
	toon_glint = s.glass;

	// Street lights reach landmarks' walls whose UV.y is the height above ground.
	bool lit_feet = !landmark || archetype == LM_ESB_BASE || archetype == LM_CHRYSLER_SHAFT || archetype == LM_WTC_PODIUM
			|| archetype == LM_FLATIRON || archetype == LM_WOOLWORTH || archetype == LM_FORT || archetype == LM_GC_FACADE
			|| archetype == LM_ROCK_SHAFT;
	if (city_lights > 0.0 && (flags & (ROOF | PARAPET_INSIDE)) == 0 && lit_feet) {
		// Street lights on the feet of the walls near them.
		float reach = 1.0 - smoothstep(street_light_reach.x, street_light_reach.y, UV.y);
		if (reach > 0.0) {
			vec3 scene_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			EMISSION += ALBEDO * street_light_at(scene_position.xz, length(VERTEX)) * (reach * city_lights);
		}
		// Floodlights on landmarks' masonry setbacks, from the roof below.
		if ((flags & LANDMARK) != 0 && (archetype == PREWAR_OFFICE || archetype == PREWAR_APARTMENT
				|| archetype == HOTEL || archetype == INSTITUTION)) {
			if (span.x > floodlight_min_height && span.y < 1e3) {
				float flood = 1.0 - smoothstep(0.0, floodlight_reach, UV.y - span.x);
				EMISSION += ALBEDO * srgb(FLOODLIGHT) * (floodlight_strength * flood * city_lights);
			}
		}
	}
}
