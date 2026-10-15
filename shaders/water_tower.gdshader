// Rooftop water towers from near city tiles' props
// (scripts/world/city_props.gd), on the unit mesh from
// PropMeshes.water_tower(). Per instance:
//   transform        scales the mesh to the tower's height (y) and tank width
//                    (x, z) and moves it to where its legs stand
//   INSTANCE_CUSTOM  (yaw radians, tank: 0 wood or 1 steel, seed 0..1, 0)
// Per vertex: UV = (part, 0..1 up the part), UV2.x = around the tank (0..1).
// Wooden tanks are weathered cedar staves held by dark steel hoops, closer
// together toward the bottom where the water presses hardest; steel tanks are
// painted plates with welded seams. A ladder runs up one side. Details are
// box-filtered or fade with their size on screen, like the buildings'.
// Lighting is the shared toon model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, cull_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes numbers them.
const int TANK = 0;
const int TANK_BOTTOM = 1;
const int ROOF = 2;
const int FINIAL = 3;
const int STEEL = 4;
const int PLATFORM = 5;

// Shares of the tower's height, as in PropMeshes.water_tower().
const float TANK_SHARE = 0.44;

// Palettes, in sRGB: weathered cedar from silver-gray to new orange-brown;
// painted steel tanks; roofs; the stand's steel.
const vec3 WOOD[5] = vec3[](vec3(0.56, 0.47, 0.38), vec3(0.50, 0.43, 0.36), vec3(0.62, 0.56, 0.47),
		vec3(0.67, 0.48, 0.32), vec3(0.46, 0.39, 0.33));
const vec3 STEEL_PAINT[4] = vec3[](vec3(0.80, 0.80, 0.78), vec3(0.68, 0.70, 0.72), vec3(0.74, 0.72, 0.66),
		vec3(0.55, 0.60, 0.58));
const vec3 ROOF_COLOR[4] = vec3[](vec3(0.36, 0.31, 0.27), vec3(0.29, 0.28, 0.28), vec3(0.44, 0.37, 0.31),
		vec3(0.33, 0.36, 0.33));
const vec3 STAND[3] = vec3[](vec3(0.17, 0.17, 0.18), vec3(0.42, 0.25, 0.18), vec3(0.30, 0.31, 0.32));
const vec3 HOOP = vec3(0.16, 0.16, 0.17);
const vec3 BEAMS = vec3(0.31, 0.26, 0.22);

// Wooden staves' width and steel plates' size (m).
uniform float stave_width = 0.22;
uniform vec2 plate_size = vec2(2.4, 1.5);
// Hoops on a wooden tank, and how much closer together they get at the bottom.
uniform float hoop_count = 9.0;
uniform float hoop_crowding = 0.7;

// (wood 0 / steel 1, seed in 1024ths, width m, height m): the same for the
// whole tower.
varying flat vec4 tower_data;

float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

int pick(float r, int count) {
	return min(int(r * float(count)), count - 1);
}

void vertex() {
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	tower_data = vec4(floor(INSTANCE_CUSTOM.y + 0.5), floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5), width, height);
	// Turn to the tower's yaw (about +Y, as Godot's Basis turns).
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	VERTEX.xz = vec2(c * VERTEX.x + s * VERTEX.z, c * VERTEX.z - s * VERTEX.x);
	vec3 n = NORMAL;
	n.xz = vec2(c * n.x + s * n.z, c * n.z - s * n.x);
	// Godot turns normals by the instance's scale; dividing by its square
	// first leaves them turned by its inverse, as a stretched surface needs.
	NORMAL = n / vec3(width * width, height * height, width * width);
}

// The tank's side: staves and hoops, or plates and seams; a ladder.
vec3 tank_wall(vec3 wall, bool steel, float seed, vec2 p, vec2 footprint) {
	float pixel = max(footprint.x, footprint.y);
	vec3 color = wall;
	if (steel) {
		float row = p.y / plate_size.y;
		float shift = mod(floor(row), 2.0) * 0.5;
		float seams = max(centered_stripes(row, 0.03 / plate_size.y, footprint.y / plate_size.y),
				centered_stripes(p.x / plate_size.x + shift, 0.02 / plate_size.x, footprint.x / plate_size.x));
		color *= 1.0 - 0.18 * seams;
		// Rust streaks running down from the seams.
		float streaks = value_noise(vec2(p.x * 1.5, p.y * 0.2 + seed)) * smoothstep(0.6, 0.0, fract(row));
		color = mix(color, srgb(vec3(0.50, 0.33, 0.24)), 0.25 * streaks * visible(0.6, pixel));
	} else {
		// Staves, each a little different, with dark joints.
		float stave = floor(p.x / stave_width);
		float detail = visible(stave_width, pixel);
		color *= 1.0 + (hash(vec2(stave, seed)) - 0.5) * 0.18 * detail;
		color *= 1.0 - 0.22 * centered_stripes(p.x / stave_width, 0.08, footprint.x / stave_width);
		// Weathering: darker streaks down the staves, darker toward the bottom.
		float streaks = value_noise(vec2(p.x * 0.9, p.y * 0.15 + seed * 7.0));
		color *= mix(1.0, 0.82 + 0.25 * streaks, detail) * mix(0.85, 1.0, smoothstep(0.0, 1.5, p.y));
		// Hoops, spaced by a curve that crowds them toward the bottom.
		float tank_height = tower_data.w * TANK_SHARE;
		float t = clamp(p.y / tank_height, 0.0, 1.0);
		float u = hoop_count * pow(t, hoop_crowding);
		float hoop_width = 0.06 / tank_height * hoop_count * hoop_crowding * pow(max(t, 0.02), hoop_crowding - 1.0);
		float hoops = centered_stripes(u - 0.5, min(hoop_width, 0.5), fwidth(u));
		color = mix(color, srgb(HOOP) * 1.3, hoops);
	}
	// A ladder up one side: two rails and rungs.
	float around = p.x - (rnd(seed, 9.0) * 0.6 + 0.2) * tower_data.z * PI;
	float rails = band(abs(around), 0.2, 0.25, footprint.x);
	float rungs = band(abs(around), 0.0, 0.25, footprint.x) * centered_stripes(p.y / 0.3, 0.12, footprint.y / 0.3);
	color = mix(color, srgb(HOOP), clamp(rails + rungs, 0.0, 1.0) * visible(0.25, pixel));
	return color;
}

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bool steel = tower_data.x > 0.5;
	float seed = tower_data.y;
	float width = tower_data.z;
	float height = tower_data.w;
	int part = int(UV.x + 0.5);
	vec3 wall = steel ? srgb(STEEL_PAINT[pick(rnd(seed, 1.0), 4)]) : srgb(WOOD[pick(rnd(seed, 1.0), 5)]);
	wall *= mix(0.92, 1.08, rnd(seed, 2.0));
	vec3 color;
	float occlusion = 1.0;
	if (part == TANK) {
		// Meters around and up the tank.
		vec2 p = vec2(UV2.x * PI * width, UV.y * height * TANK_SHARE);
		color = tank_wall(wall, steel, seed, p, max(fwidth(p), vec2(1e-4)));
		occlusion = mix(0.8, 1.0, UV.y);
	} else if (part == TANK_BOTTOM) {
		color = wall * 0.7;
		occlusion = 0.6;
	} else if (part == ROOF) {
		color = steel ? wall * 0.9 : srgb(ROOF_COLOR[pick(rnd(seed, 3.0), 4)]);
		// Boards or seams running up to the peak, and a darker edge.
		float boards = UV2.x * width * PI / 0.5;
		color *= 1.0 - 0.15 * centered_stripes(boards, 0.08, fwidth(boards));
		color *= mix(0.75, 1.0, smoothstep(0.0, 0.12, UV.y));
	} else if (part == FINIAL) {
		color = srgb(HOOP) * 1.4;
	} else if (part == PLATFORM) {
		float beams = UV.y * 3.0;
		color = srgb(BEAMS) * (1.0 - 0.25 * centered_stripes(beams, 0.1, fwidth(beams)));
		occlusion = 0.7;
	} else {
		color = srgb(STAND[pick(rnd(seed, 4.0), 3)]);
		occlusion = 0.8;
	}
	// The undersides (tank bottom, roof eaves) face down: back faces of the
	// double-sided roof show its inside, which is in shade.
	if (!FRONT_FACING) {
		color *= 0.6;
	}
	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion);
	toon_glint = steel && part == TANK ? 0.15 : 0.0;
}
