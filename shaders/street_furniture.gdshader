// Street furniture from near city tiles' props (scripts/world/city_props.gd):
// hydrants, benches, litter baskets, bike racks and parking meters on the
// small mesh from PropMeshes.street_furniture_small(); bus shelters, LinkNYC
// kiosks, subway entrances, traffic signals and newsstands on the large one;
// sidewalk sheds, the bike share's docks and plaza furniture on a third
// (street_furniture_extra()).
// Per instance (the props' common layout):
//   transform        scales by the piece's width (x, z) and height (y) and
//                    moves it to its base on the sidewalk
//   INSTANCE_CUSTOM  (yaw radians: its front faces (sin, 0, cos) of it, toward
//                    the street; variant; seed 0..1; prop type 5..14, 19..23)
//   COLOR.r          a traffic signal's phase offset (0..1 of its cycle), a
//                    sidewalk shed's reach out from the wall (m)
// Each mesh holds all its pieces' shapes, tagged per vertex (CUSTOM0: type,
// variant bits, the size it's built at; see PropMeshes). This shader folds
// away every shape but the instance's own, scales that one to the piece's
// size, turns it to its yaw and moves it into place itself
// (skip_vertex_transform, like the street lights). Pieces shrink away
// between fade distances from the camera, sooner for the small ones.
//
// The look: toon-lit painted steel, cartoon glass (sky-blue with bright
// streaks, not see-through), ads and screens made of simple shapes, wire mesh
// and perforations that fade to their average color with distance. Lights:
// traffic signals cycle green, yellow and red on the signals' shared clock
// (the signal_clock global, TrafficSignals: crossing approaches half a cycle
// apart, so traffic stops where the poles show red), with a pedestrian
// signal that shows the walking person while the crossing traffic is green;
// subway globes (green entrance, red exit), kiosk screens and shelter ads
// glow a little by day and more at night, when shelters and newsstands are
// lit inside, and so are sidewalk sheds' undersides and food kiosks'
// windows. Bike docks hold a bike in most docks (each section its own
// share). Signal lenses and globes stay at least light_min_pixels across
// far away. A subway stair's opening shows steps going down into the dark:
// the view ray is traced through it to the steps and walls below the
// sidewalk (no geometry there). At night pieces near a street light catch its
// light (night.gdshaderinc).
// Lighting is the shared toon model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, cull_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes.Furniture numbers them.
const int HYDRANT = 0;
const int HYDRANT_CAP = 1;
const int BASKET = 2;
const int BASKET_FILL = 3;
const int COMPACTOR = 4;
const int COMPACTOR_DOOR = 5;
const int SOLAR_PANEL = 6;
const int BIKE_RACK = 7;
const int METER = 8;
const int METER_FACE = 9;
const int METER_SIGN = 10;
const int BENCH = 11;
const int STEEL = 12;
const int ROOF = 13;
const int CEILING = 14;
const int GLASS = 15;
const int AD_BOX = 16;
const int POSTER = 17;
const int LINK = 18;
const int LINK_FRONT = 19;
const int SCREEN = 20;
const int STAIRWELL = 21;
const int RAILING = 22;
const int LAMP_POST = 23;
const int GLOBE = 24;
const int SIGNAL_POLE = 25;
const int SIGNAL_HEAD = 26;
const int SIGNAL_FACE = 27;
const int SIGNAL_LAMP = 28;
const int WALK_LAMP = 29;
const int STREET_SIGN = 30;
const int NEWSSTAND = 31;
const int NEWSSTAND_ROOF = 32;
const int MAGAZINES = 33;
const int BENCH_END = 34;
const int SHED_PLYWOOD = 35;
const int SHED_DECK = 36;
const int SHED_CEILING = 37;
const int SHED_STEEL = 38;
const int DOCK = 39;
const int DOCK_BASE = 40;
const int DOCK_PANEL = 41;
const int BIKE = 42;
const int BIKE_TIRE = 43;
const int BIKE_SEAT = 44;
const int TABLE = 45;
const int CHAIR = 46;
const int CHAIR_LEGS = 47;
const int UMBRELLA = 48;
const int PLANTER = 49;
const int PLANTS = 50;
const int FOOD_KIOSK = 51;
const int KIOSK_WINDOW = 52;
const int KIOSK_ROOF = 53;

// Prop types (CityTileDecoder.PROP_*).
const int TYPE_BUS_SHELTER = 6;
const int TYPE_TRAFFIC_SIGNAL = 10;
const int TYPE_NEWSSTAND = 14;
const int TYPE_SHED = 19;
const int TYPE_BIKE_DOCK = 20;
const int TYPE_KIOSK = 23;

// As PropMeshes builds them: a signal's lens spacing, a subway stair's
// opening (m).
const float LAMP_SPACING = 0.35;
const vec2 STAIR_HALF = vec2(2.1, 0.9);
// The stairs' rise per run, and a step's depth (m).
const float STAIR_SLOPE = 0.62;
const float TREAD = 0.29;
// A sidewalk shed's reach out from the wall as built (PropMeshes.SHED_DEPTH),
// and the bike docks' spacing (CityTileDecoder.DOCK_SPACING).
const float SHED_DEPTH = 2.5;
const float DOCK_SPACING = 0.8;

// Paint, in sRGB.
const vec3 HYDRANT_PAINT[3] = vec3[](vec3(0.74, 0.75, 0.77), vec3(0.78, 0.15, 0.11), vec3(0.95, 0.76, 0.17));
const vec3 HYDRANT_CAPS[6] = vec3[](vec3(0.80, 0.16, 0.12), vec3(0.36, 0.37, 0.39), vec3(0.90, 0.90, 0.88),
		vec3(0.95, 0.76, 0.17), vec3(0.80, 0.16, 0.12), vec3(0.74, 0.75, 0.77));
const vec3 WIRE_GREEN = vec3(0.30, 0.52, 0.33);
const vec3 SUBWAY_GREEN = vec3(0.17, 0.38, 0.25);
const vec3 STAINLESS = vec3(0.64, 0.66, 0.68);
const vec3 DARK_STEEL = vec3(0.24, 0.26, 0.29);
const vec3 SIGNAL_BLACK = vec3(0.10, 0.10, 0.11);
const vec3 POLE_GRAY = vec3(0.56, 0.58, 0.57);
const vec3 SIGN_GREEN = vec3(0.0, 0.42, 0.26);
const vec3 NEWSSTAND_GREEN = vec3(0.13, 0.43, 0.27);
// Sidewalk sheds' paint: hunter green, and the odd white, black or blue one.
const vec3 SHED_PAINT[4] = vec3[](vec3(0.16, 0.30, 0.20), vec3(0.85, 0.85, 0.82), vec3(0.15, 0.15, 0.16),
		vec3(0.18, 0.30, 0.52));
const vec3 SHARE_BIKE_BLUE = vec3(0.14, 0.40, 0.74);
// Plaza tables and chairs: green, silver or red.
const vec3 BISTRO[3] = vec3[](vec3(0.20, 0.38, 0.26), vec3(0.66, 0.68, 0.70), vec3(0.72, 0.16, 0.14));
// Ads and magazine covers pick from these.
const vec3 BRIGHT[8] = vec3[](vec3(0.95, 0.30, 0.25), vec3(0.98, 0.72, 0.15), vec3(0.20, 0.62, 0.90),
		vec3(0.55, 0.30, 0.80), vec3(0.15, 0.75, 0.55), vec3(0.98, 0.50, 0.65), vec3(0.12, 0.16, 0.30),
		vec3(0.96, 0.94, 0.88));

// Pieces shrink away between these distances from the camera (m): small ones
// (hydrants, benches, baskets, bike racks, meters) and large ones.
// CityProps sets them (and the tiles' ranges to match).
uniform vec2 small_fade_distance = vec2(180.0, 260.0);
uniform vec2 large_fade_distance = vec2(420.0, 580.0);
// Signal lenses and subway globes stay at least this many pixels across, but
// grow at most this many times.
uniform float light_min_pixels = 1.6;
uniform float light_max_growth = 4.0;
// The signals' clock (s; TrafficSignals.clock(), set every frame by
// CityStreamer).
global uniform float signal_clock;
// As TrafficSignals has them (traffic goes by its numbers, so these must
// match): a traffic signal's cycle (s); the shares of it that are green and
// yellow (red the rest); when the walking person comes on, and the shares it
// and then the flashing hand last.
const float SIGNAL_CYCLE = 60.0;
const vec2 SIGNAL_LIGHTS = vec2(0.43, 0.05);
const vec3 SIGNAL_WALK = vec3(0.5, 0.18, 0.22);
// Glow of lights by day and at night (multiplies their color).
uniform vec2 signal_glow = vec2(1.6, 3.0);
uniform vec2 globe_glow = vec2(0.5, 2.2);
uniform vec2 screen_glow = vec2(0.45, 0.9);
uniform vec2 poster_glow = vec2(0.25, 1.0);
// Shelters' and newsstands' lights at night (sRGB), and a stairwell's lamps.
uniform vec3 shelter_light : source_color = vec3(0.86, 0.93, 1.0);
uniform vec3 newsstand_light : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 stair_light : source_color = vec3(1.0, 0.90, 0.72);
// The lamps under sidewalk sheds, lit by day too (dimmer).
uniform vec3 shed_light : source_color = vec3(0.92, 0.96, 1.0);
uniform vec2 shed_glow = vec2(0.6, 2.4);
// The share of a section's docks holding a bike: from this, up to all.
uniform float dock_fill = 0.45;
// How much street light (night) the pieces catch.
uniform float street_light_catch = 1.0;

// (type, variant, seed in 1024ths, signal: lit lens 0 red, 1 yellow, 2 green,
// plus 4 x the walk sign: 0 hand, 1 walking person, 2 flashing hand).
varying flat vec4 item;
// Street light where the piece stands (night).
varying flat vec3 item_light;
// Where this is in the piece's own frame (m), and the camera.
varying vec3 local_position;
varying flat vec3 local_camera;
// The face's size (m), for patterns in meters.
varying vec2 face_size;

// A random number per piece (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

int pick(float r, int count) {
	return min(int(r * float(count)), count - 1);
}

void vertex() {
	int variant = int(INSTANCE_CUSTOM.y + 0.5);
	int type = int(INSTANCE_CUSTOM.w + 0.5);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float distance_to_camera = distance(camera, base);
	bool small = type == 5 || type == 8 || (type >= 11 && type <= 13) || (type >= 20 && type <= 22);
	vec2 fade = small ? small_fade_distance : large_fade_distance;
	float shown = 1.0 - smoothstep(fade.x, fade.y, distance_to_camera);
	// Only the piece's own shape (CUSTOM0: type, variant bits).
	if (int(CUSTOM0.x + 0.5) != type || ((int(CUSTOM0.y + 0.5) >> variant) & 1) == 0) {
		shown = 0.0;
	}
	if (type == TYPE_BIKE_DOCK && UV.x > float(BIKE) - 0.5 && UV.x < float(BIKE_SEAT) + 0.5) {
		// Empty docks: each section holds its own share of bikes.
		float section = floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5);
		float dock = floor(VERTEX.x / DOCK_SPACING + 8.0);
		if (rnd(section + dock * 0.37, 31.0) > mix(dock_fill, 1.0, rnd(section, 30.0))) {
			shown = 0.0;
		}
	}
	if (shown <= 0.0) {
		// Folded away (another shape's vertex, or too far): a point behind
		// the camera, so its triangles are dropped. Shapes' vertices are
		// together in the mesh, so neighbors take the same branch.
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		float height = length(MODEL_MATRIX[1].xyz);
		float width = length(MODEL_MATRIX[0].xyz);
		float yaw = INSTANCE_CUSTOM.x;
		// Custom data arrives as half floats; whole 1024ths survive that exactly.
		float seed = floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5);
		int part = int(UV.x + 0.5);
		vec3 scale = vec3(width / CUSTOM0.w, height / CUSTOM0.z, width / CUSTOM0.w);
		if (type == TYPE_SHED) {
			scale.z = COLOR.r / SHED_DEPTH;
		}
		vec3 v = VERTEX * scale;
		float signal_state = 0.0;
		if (type == TYPE_TRAFFIC_SIGNAL) {
			// Where this pole is in its cycle (TrafficSignals.phase()).
			float phase = fract(signal_clock / SIGNAL_CYCLE + COLOR.r);
			float lens = phase < SIGNAL_LIGHTS.x ? 2.0 : (phase < SIGNAL_LIGHTS.x + SIGNAL_LIGHTS.y ? 1.0 : 0.0);
			float since = fract(phase - SIGNAL_WALK.x);
			float walk = since < SIGNAL_WALK.y ? 1.0 : (since < SIGNAL_WALK.y + SIGNAL_WALK.z ? 2.0 : 0.0);
			signal_state = lens + 4.0 * walk;
			// The lit lens is built at the top (red) one.
			if (part == SIGNAL_LAMP) {
				v.y -= lens * LAMP_SPACING * scale.y;
			}
		}
		if (CUSTOM1.w > 0.0 && !IN_SHADOW_PASS) {
			// A light that stays a pixel or two across, about its center.
			vec3 pivot = CUSTOM1.xyz * scale;
			if (part == SIGNAL_LAMP) {
				pivot.y -= mod(signal_state, 4.0) * LAMP_SPACING * scale.y;
			}
			float pixel = 2.0 * distance_to_camera / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
			v = pivot + (v - pivot) * clamp(light_min_pixels * pixel / (2.0 * CUSTOM1.w), 1.0, light_max_growth);
		}
		local_position = v;
		face_size = CUSTOM1.w > 0.0 ? vec2(1.0) : CUSTOM1.xy;

		// Turn to the yaw (about +Y, as Godot's Basis turns: +z goes to (sin, cos)).
		float c = cos(yaw);
		float s = sin(yaw);
		vec3 turned = vec3(c * v.x + s * v.z, v.y, c * v.z - s * v.x);
		// Normals of a stretched shape follow the inverse of its stretch.
		vec3 n = NORMAL / scale;
		n = vec3(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
		VERTEX = (VIEW_MATRIX * vec4(base + turned * shown, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

		vec3 to_camera = camera - base;
		local_camera = vec3(c * to_camera.x - s * to_camera.z, to_camera.y, s * to_camera.x + c * to_camera.z);
		item = vec4(float(type), float(variant), seed, signal_state);
		item_light = vec3(0.0);
		if (city_lights > 0.0 && !IN_SHADOW_PASS) {
			item_light = street_light_at(base.xz, distance_to_camera) * city_lights;
		}
	}
}

// A distance field's coverage, anti-aliased over a pixel (d < 0 inside).
float fill(float d) {
	return clamp(0.5 - d / max(fwidth(d), 1e-5), 0.0, 1.0);
}

float box_distance(vec2 p, vec2 center, vec2 half_size) {
	vec2 q = abs(p - center) - half_size;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// An invented ad on a poster or screen (uv 0..1 across it, `size` m): a
// gradient, a big round "product", a headline and a logo bar, in colors
// picked by `s`.
vec3 ad_art(vec2 uv, vec2 size, float s) {
	vec3 back = srgb(BRIGHT[pick(rnd(s, 1.0), 8)]);
	vec3 accent = srgb(BRIGHT[pick(rnd(s, 2.0), 8)]);
	if (distance(back, accent) < 0.2) {
		accent = vec3(1.0) - back * 0.6;
	}
	vec3 color = back * mix(1.15, 0.7, uv.y);
	vec2 p = uv * size;
	// The product: a disc, or a tall can, or a pair of stripes.
	float shape = rnd(s, 3.0);
	vec2 center = vec2(0.5, 0.55) * size;
	float d = shape < 0.4 ? length(p - center) - 0.3 * size.x
			: (shape < 0.75 ? box_distance(p, center, vec2(0.16, 0.3) * size.x) - 0.05 * size.x
			: abs(p.y - center.y + (p.x - center.x) * 0.6) - 0.08 * size.y);
	color = mix(color, accent, fill(d));
	// A highlight on it.
	color = mix(color, vec3(1.0), 0.35 * fill(length(p - center + vec2(0.1, -0.12) * size.x) - 0.06 * size.x));
	// Headline: a row of white word blocks near the top.
	float word = floor(uv.x * 5.0);
	float line = band(uv.y, 0.84, 0.9, fwidth(uv.y)) * band(fract(uv.x * 5.0), 0.08, 0.75 + 0.2 * rnd(s + word, 4.0), fwidth(uv.x) * 5.0);
	color = mix(color, vec3(0.97), line * band(uv.x, 0.08, 0.92, fwidth(uv.x)));
	// Logo bar at the bottom.
	color = mix(color, srgb(BRIGHT[pick(rnd(s, 5.0), 8)]) * 0.9, band(uv.y, 0.06, 0.14, fwidth(uv.y)) * band(uv.x, 0.3, 0.7, fwidth(uv.x)));
	return color;
}

// What shows through a subway stair's opening at `p` (the piece's frame,
// m), looking along `dir`: steps going down from the open end (+x) and the
// tiled walls either side, darker the deeper they are; past the far end the
// stairs go on under the sidewalk, into the dark. Returns linear color.
vec3 stairwell(vec3 p, vec3 dir) {
	// The steps' slope: y = -(STAIR_HALF.x - x) * STAIR_SLOPE.
	float down = dir.y - STAIR_SLOPE * dir.x;
	float t_steps = down < -1e-4 ? (STAIR_SLOPE * (p.x - STAIR_HALF.x) - p.y) / down : 1e6;
	float t_wall = abs(dir.z) > 1e-4 ? (sign(dir.z) * STAIR_HALF.y - p.z) / dir.z : 1e6;
	float t = min(t_steps, t_wall);
	vec3 hit = p + dir * t;
	float depth = max(-hit.y, 0.0);
	vec3 color;
	if (t_wall < t_steps) {
		// Cream tiles with gray grout, and a handrail above the steps.
		vec2 q = vec2(hit.x / 0.15, hit.y / 0.075);
		vec2 w = fwidth(q);
		float grout = max(centered_stripes(q.x, 0.08, w.x), centered_stripes(q.y, 0.08, w.y));
		color = srgb(vec3(0.86, 0.83, 0.74)) * (1.0 - 0.25 * grout);
		float above = hit.y + (STAIR_HALF.x - hit.x) * STAIR_SLOPE;
		color = mix(color, srgb(vec3(0.30, 0.31, 0.32)), band(above, 0.82, 0.9, fwidth(above)));
		color *= 0.8;
	} else {
		// Concrete treads with a pale nosing at each edge.
		float n = (STAIR_HALF.x - hit.x) / TREAD;
		float nosing = stripes(n, 0.14, fwidth(n));
		color = srgb(vec3(0.58, 0.57, 0.55)) * (1.0 - 0.3 * stripes(n + 0.5, 0.35, fwidth(n)));
		color = mix(color, srgb(vec3(0.80, 0.76, 0.52)), nosing * 0.8);
	}
	// Darker going down, and under the sidewalk past the far end.
	float shade = exp(-depth * 0.45) * mix(1.0, 0.25, smoothstep(-STAIR_HALF.x + 0.2, -STAIR_HALF.x - 0.6, hit.x));
	return color * shade;
}

void fragment() {
	int part = int(UV.x + 0.5);
	int type = int(item.x + 0.5);
	int variant = int(item.y + 0.5);
	float seed = item.z;
	vec2 uv = UV2;
	vec2 p = UV2 * face_size;
	vec2 footprint = max(fwidth(p), vec2(1e-4));
	float pixel = max(footprint.x, footprint.y);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 color = srgb(STAINLESS);
	float occlusion = 1.0;
	float glint = 0.0;
	vec3 glow = vec3(0.0);
	// Lit inside at night (shelters and newsstands), and how much.
	float inside = 0.0;

	if (part == HYDRANT || part == HYDRANT_CAP) {
		// Silver, red or yellow, with caps that stand out.
		float r = rnd(seed, 1.0);
		int body = r < 0.55 ? 0 : (r < 0.8 ? 1 : 2);
		color = part == HYDRANT ? srgb(HYDRANT_PAINT[body])
				: srgb(HYDRANT_CAPS[body * 2 + (rnd(seed, 2.0) < 0.65 ? 0 : 1)]);
		color *= mix(0.9, 1.08, rnd(seed, 3.0));
		glint = body == 0 ? 0.25 : 0.12;
	} else if (part == BASKET) {
		// Diamond wire mesh with solid bands, the dark inside showing through.
		vec2 d = vec2(p.x + p.y, p.x - p.y) / 0.07;
		vec2 w = fwidth(d);
		float wires = max(centered_stripes(d.x, 0.2, w.x), centered_stripes(d.y, 0.2, w.y));
		float rims = max(max(band(p.y, 0.84, 0.92, footprint.y), band(p.y, 0.0, 0.05, footprint.y)),
				band(p.y, 0.43, 0.46, footprint.y));
		vec3 wire = srgb(WIRE_GREEN);
		color = mix(wire * 0.3, wire, max(wires * 0.9, rims));
		if (!FRONT_FACING) {
			color *= 0.7;
		}
		occlusion = mix(0.6, 1.0, uv.y);
	} else if (part == BASKET_FILL) {
		// A black liner full of paper and cups.
		float n = value_noise(local_position.xz * 16.0 + seed);
		color = mix(srgb(vec3(0.13, 0.13, 0.14)), srgb(vec3(0.86, 0.84, 0.78)), smoothstep(0.55, 0.65, n));
		color = mix(color, srgb(vec3(0.75, 0.25, 0.18)), smoothstep(0.82, 0.86, value_noise(local_position.xz * 9.0 + seed * 3.0)));
		occlusion = 0.8;
	} else if (part == COMPACTOR || part == COMPACTOR_DOOR) {
		color = rnd(seed, 1.0) < 0.6 ? srgb(vec3(0.17, 0.36, 0.27)) : srgb(vec3(0.50, 0.56, 0.62));
		if (part == COMPACTOR_DOOR) {
			// The hopper's pull-down door and its handle.
			float door = fill(box_distance(uv, vec2(0.5, 0.66), vec2(0.36, 0.13)));
			color = mix(color, color * 0.45, door);
			color = mix(color, srgb(STAINLESS), fill(box_distance(uv, vec2(0.5, 0.76), vec2(0.2, 0.012))));
		}
		occlusion = mix(0.75, 1.0, smoothstep(0.0, 0.3, local_position.y));
	} else if (part == SOLAR_PANEL) {
		vec2 cells = vec2(uv.x * 4.0, uv.y * 3.0);
		float grid = max(centered_stripes(cells.x, 0.06, fwidth(cells.x)), centered_stripes(cells.y, 0.06, fwidth(cells.y)));
		color = mix(srgb(vec3(0.10, 0.14, 0.30)), srgb(vec3(0.62, 0.64, 0.68)), grid);
		glint = 1.0;
	} else if (part == BIKE_RACK) {
		color = rnd(seed, 1.0) < 0.65 ? srgb(vec3(0.62, 0.64, 0.66)) : srgb(vec3(0.15, 0.16, 0.17));
		glint = 0.3;
	} else if (part == METER || part == METER_FACE) {
		color = srgb(vec3(0.50, 0.53, 0.55));
		if (part == METER_FACE) {
			// Screen, keypad and card slot.
			float screen = fill(box_distance(uv, vec2(0.5, 0.72), vec2(0.34, 0.1)));
			color = mix(color, srgb(vec3(0.10, 0.22, 0.24)), screen);
			vec2 keys = vec2(uv.x * 4.0 - 0.5, (uv.y - 0.32) * 18.0);
			float buttons = band(uv.y, 0.32, 0.5, footprint.y) * band(uv.x, 0.2, 0.8, footprint.x)
					* (1.0 - max(centered_stripes(keys.x, 0.35, fwidth(keys.x)), centered_stripes(keys.y, 0.35, fwidth(keys.y))));
			color = mix(color, srgb(vec3(0.85, 0.85, 0.82)), buttons * visible(0.04, pixel));
			color = mix(color, srgb(vec3(0.95, 0.75, 0.15)), fill(box_distance(uv, vec2(0.5, 0.2), vec2(0.2, 0.025))));
			if (city_lights > 0.0) {
				glow += srgb(vec3(0.4, 0.8, 0.9)) * screen * 0.6 * city_lights;
			}
		}
		occlusion = mix(0.75, 1.0, smoothstep(0.0, 0.4, local_position.y));
	} else if (part == METER_SIGN) {
		// Blue, with a white border and a big P.
		color = srgb(vec3(0.10, 0.30, 0.66));
		vec2 q = (uv - 0.5) * face_size;
		float border = 1.0 - fill(box_distance(q, vec2(0.0), face_size * 0.5 - 0.025));
		float stem = fill(box_distance(q, vec2(-0.04, 0.0), vec2(0.022, 0.08)));
		float bowl = fill(abs(length((q - vec2(-0.01, 0.035)) * vec2(1.0, 1.3)) - 0.04) - 0.016) * step(-0.04, q.x);
		color = mix(color, vec3(0.95), max(border, max(stem, bowl)));
	} else if (part == BENCH || part == BENCH_END) {
		if (part == BENCH_END) {
			// Two legs rising into an armrest, and a rail under the seat.
			float keep = max(max(band(uv.x, 0.0, 0.12, footprint.x / face_size.x), band(uv.x, 0.86, 1.0, footprint.x / face_size.x)),
					max(band(uv.y, 0.88, 1.0, footprint.y / face_size.y), band(uv.y, 0.58, 0.7, footprint.y / face_size.y)));
			if (keep < 0.5) {
				discard;
			}
		}
		// Perforated steel.
		color = srgb(vec3(0.60, 0.64, 0.68));
		vec2 holes = p / 0.035;
		float dots = fill(length(fract(holes) - 0.5) - 0.22) * visible(0.035, pixel);
		color *= 1.0 - 0.45 * dots;
		glint = 0.15;
		occlusion = mix(0.7, 1.0, smoothstep(0.0, 0.4, local_position.y));
	} else if (part == STEEL) {
		color = type == TYPE_BUS_SHELTER ? srgb(STAINLESS) : srgb(DARK_STEEL);
		glint = 0.25;
		inside = 1.0;
	} else if (part == ROOF) {
		color = srgb(vec3(0.55, 0.58, 0.61));
		inside = 0.3;
	} else if (part == CEILING) {
		color = srgb(vec3(0.82, 0.84, 0.86));
		inside = 1.0;
		if (city_lights > 0.0) {
			glow += srgb(type == TYPE_NEWSSTAND ? newsstand_light : shelter_light) * 1.2 * city_lights;
		}
	} else if (part == GLASS) {
		// Cartoon glass: the sky's light, paler up high, two bright streaks.
		color = mix(srgb(vec3(0.42, 0.55, 0.62)), srgb(vec3(0.72, 0.83, 0.90)), uv.y);
		float q = (p.x + p.y * 0.7) / 2.6 + rnd(seed, 6.0);
		float streaks = max(band(fract(q), 0.1, 0.17, fwidth(q)), band(fract(q), 0.22, 0.25, fwidth(q)));
		color = mix(color, vec3(0.95), 0.4 * streaks);
		// Steel frame around it, and mullions between panes.
		float panes = max(round(face_size.x / 1.35), 1.0);
		float across = uv.x * panes;
		float frame = max(centered_stripes(across, 0.05 * panes / face_size.x, fwidth(across)),
				1.0 - band(p.y, 0.05, face_size.y - 0.05, footprint.y));
		color = mix(color, srgb(type == TYPE_BUS_SHELTER ? STAINLESS : DARK_STEEL), frame);
		glint = 1.0 - frame;
		inside = 1.0;
		if (type == TYPE_BUS_SHELTER && city_lights > 0.0) {
			// The lit shelter seen through its glass.
			glow += srgb(shelter_light) * (0.12 * city_lights * (1.0 - frame));
		}
	} else if (part == AD_BOX) {
		color = srgb(DARK_STEEL);
		glint = 0.2;
	} else if (part == POSTER || part == SCREEN) {
		bool screen = part == SCREEN;
		// Screens change ad every 8 s; posters stay.
		float slide = screen ? floor(TIME / 8.0 + rnd(seed, 7.0) * 8.0) : 0.0;
		// Each side of a shelter's ad panel or a kiosk its own ad.
		float side = type == TYPE_NEWSSTAND ? 0.0 : 11.0 * step(local_position.x, type == TYPE_BUS_SHELTER ? 1.99 : 0.0);
		vec3 art = ad_art(uv, face_size, seed + slide * 37.0 + side);
		float bezel = screen ? band(uv.x, 0.04, 0.96, footprint.x) * band(uv.y, 0.03, 0.97, footprint.y) : 1.0;
		color = mix(srgb(SIGNAL_BLACK), art * (screen ? 0.3 : 0.8), bezel);
		vec2 strength = screen ? screen_glow : poster_glow;
		glow += art * bezel * mix(strength.x, strength.y, city_lights);
		glint = 0.5;
	} else if (part == LINK || part == LINK_FRONT) {
		color = srgb(vec3(0.58, 0.60, 0.63));
		glint = 0.25;
		if (part == LINK_FRONT) {
			// The tablet, and a dark strip down the edge.
			float tablet = fill(box_distance(p, vec2(face_size.x * 0.5, 1.15), vec2(0.13, 0.1)));
			color = mix(color, srgb(SIGNAL_BLACK), max(tablet, 0.6 * band(uv.x, 0.4, 0.6, footprint.x / face_size.x)));
		}
		occlusion = mix(0.8, 1.0, smoothstep(0.0, 0.5, local_position.y));
	} else if (part == STAIRWELL) {
		// A granite coping round three sides; the stairs inside are lit by
		// their own light (not the sun).
		vec2 edge = STAIR_HALF - abs(local_position.xz);
		float coping = 1.0 - band(min(edge.y, local_position.x + STAIR_HALF.x), 0.1, 10.0, length(fwidth(local_position.xz)));
		vec3 dir = normalize(local_position - local_camera);
		vec3 below = stairwell(local_position, dir);
		color = mix(vec3(0.0), srgb(vec3(0.55, 0.54, 0.52)), coping);
		vec3 lit = toon_ambient(vec3(0.0, 1.0, 0.0), 1.0) * 1.2 + srgb(stair_light) * (0.6 * city_lights);
		glow += below * lit * (1.0 - coping);
		occlusion = 0.9;
	} else if (part == RAILING) {
		// Bars between a top and a bottom rail, posts every so often; the
		// gaps are cut out (bars too thin to see go with them).
		float bars = centered_stripes(p.x / 0.12, 0.2, footprint.x / 0.12);
		float posts = centered_stripes(p.x / (face_size.x / max(round(face_size.x / 1.4), 1.0)), 0.06, footprint.x);
		float rails = max(band(p.y, face_size.y - 0.07, face_size.y, footprint.y), band(p.y, 0.04, 0.1, footprint.y));
		float solid = max(max(bars, posts), max(rails, 1.0 - band(p.x, 0.04, face_size.x - 0.04, footprint.x)));
		if (solid < 0.5) {
			discard;
		}
		color = srgb(SUBWAY_GREEN);
		glint = 0.15;
	} else if (part == LAMP_POST) {
		color = srgb(SUBWAY_GREEN);
		occlusion = mix(0.75, 1.0, smoothstep(0.0, 0.4, local_position.y));
		glint = 0.3;
	} else if (part == GLOBE) {
		// Green for an entrance, red for exit only; brighter toward the
		// middle, so it reads round.
		vec3 tint = variant == 1 ? srgb(vec3(1.0, 0.22, 0.16)) : srgb(vec3(0.30, 0.95, 0.45));
		float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		color = mix(tint, vec3(1.0), 0.25 * facing);
		glow += mix(tint, vec3(1.0), 0.3 * facing * facing) * mix(globe_glow.x, globe_glow.y, city_lights)
				* mix(0.35, 1.2, facing * facing);
		glint = 1.0;
	} else if (part == SIGNAL_POLE) {
		color = srgb(POLE_GRAY);
		occlusion = mix(0.8, 1.0, smoothstep(0.0, 0.6, local_position.y));
		glint = 0.2;
	} else if (part == SIGNAL_HEAD || part == SIGNAL_FACE) {
		color = srgb(SIGNAL_BLACK);
		if (part == SIGNAL_FACE) {
			// Three dark lenses (red, yellow, green), each under a visor's rim.
			vec2 q = uv * face_size;
			for (int i = 0; i < 3; i++) {
				vec2 center = vec2(face_size.x * 0.5, face_size.y - 0.18 - LAMP_SPACING * float(i));
				float r = length(q - center);
				vec3 off = i == 0 ? vec3(0.30, 0.05, 0.04) : (i == 1 ? vec3(0.30, 0.20, 0.03) : vec3(0.04, 0.24, 0.15));
				color = mix(color, srgb(vec3(0.22)), fill(abs(r - 0.135) - 0.012));
				color = mix(color, srgb(off), fill(r - 0.11));
			}
			glint = 0.6;
		}
	} else if (part == SIGNAL_LAMP) {
		// The lit lens: red, yellow or green.
		int lens = int(mod(item.w, 4.0) + 0.5);
		vec3 lamp = lens == 0 ? srgb(vec3(1.0, 0.16, 0.10)) : (lens == 1 ? srgb(vec3(1.0, 0.62, 0.06)) : srgb(vec3(0.20, 1.0, 0.62)));
		float disc = fill(length(uv - 0.5) - 0.44);
		color = mix(srgb(SIGNAL_BLACK), mix(lamp, vec3(1.0), 0.3), disc);
		glow += lamp * disc * mix(signal_glow.x, signal_glow.y, city_lights);
	} else if (part == WALK_LAMP) {
		// The walking person (white), or the raised hand (orange; flashing
		// before the light turns).
		int walk = int(floor(item.w / 4.0) + 0.5);
		vec2 q = uv;
		float symbol;
		vec3 lamp;
		if (walk == 1) {
			float d = length(q - vec2(0.53, 0.8)) - 0.075;
			d = min(d, segment_distance(q, vec2(0.52, 0.66), vec2(0.48, 0.42)) - 0.055);
			d = min(d, segment_distance(q, vec2(0.48, 0.42), vec2(0.36, 0.16)) - 0.04);
			d = min(d, segment_distance(q, vec2(0.48, 0.42), vec2(0.62, 0.18)) - 0.04);
			d = min(d, segment_distance(q, vec2(0.51, 0.62), vec2(0.36, 0.48)) - 0.035);
			d = min(d, segment_distance(q, vec2(0.51, 0.62), vec2(0.66, 0.5)) - 0.035);
			symbol = fill(d);
			lamp = srgb(vec3(0.92, 0.96, 1.0));
		} else {
			float d = box_distance(q, vec2(0.5, 0.4), vec2(0.15, 0.14)) - 0.03;
			for (int i = 0; i < 4; i++) {
				float x = 0.37 + 0.087 * float(i);
				d = min(d, segment_distance(q, vec2(x, 0.45), vec2(x, 0.7 + (i == 1 || i == 2 ? 0.05 : 0.0))) - 0.03);
			}
			d = min(d, segment_distance(q, vec2(0.62, 0.36), vec2(0.74, 0.52)) - 0.03);
			symbol = fill(d);
			if (walk == 2 && fract(signal_clock) > 0.5) {
				symbol = 0.0;
			}
			lamp = srgb(vec3(1.0, 0.50, 0.10));
		}
		color = mix(srgb(SIGNAL_BLACK), lamp, symbol);
		glow += lamp * symbol * mix(signal_glow.x, signal_glow.y, city_lights) * 0.8;
	} else if (part == STREET_SIGN) {
		// Green, white border, a street name in white.
		color = srgb(SIGN_GREEN);
		float border = 1.0 - band(p.x, 0.03, face_size.x - 0.03, footprint.x) * band(p.y, 0.03, face_size.y - 0.03, footprint.y);
		float letter = floor(p.x / 0.11);
		float letters = band(p.y, 0.09, 0.21 + 0.03 * step(0.7, rnd(seed + letter, 8.0)), footprint.y)
				* band(fract(p.x / 0.11), 0.15, 0.8, footprint.x / 0.11)
				* band(p.x, 0.2, 0.2 + 0.11 * floor(8.0 + rnd(seed, 9.0) * 5.0), footprint.x)
				* step(0.12, rnd(seed + letter, 10.0));
		color = mix(color, vec3(0.95), max(border, letters * visible(0.1, pixel)));
	} else if (part == NEWSSTAND) {
		// Stainless panels with seams.
		color = srgb(STAINLESS) * (1.0 - 0.2 * centered_stripes(p.x / 0.6, 0.03, footprint.x / 0.6));
		glint = 0.3;
		inside = 0.3;
	} else if (part == NEWSSTAND_ROOF) {
		color = srgb(NEWSSTAND_GREEN);
		inside = 0.2;
	} else if (part == MAGAZINES) {
		// Rows of covers on racks: a color each, a white title band.
		vec2 cell = p / vec2(0.22, 0.31);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		vec3 cover = srgb(BRIGHT[pick(rnd(seed + id.x * 7.0 + id.y * 31.0, 11.0), 8)]);
		cover = mix(cover, vec3(0.95), band(f.y, 0.72, 0.86, fwidth(cell.y)) * 0.8);
		float gaps = 1.0 - band(f.x, 0.05, 0.95, fwidth(cell.x)) * band(f.y, 0.1, 0.97, fwidth(cell.y));
		float detail = visible(0.22, pixel);
		vec3 average = srgb(vec3(0.62, 0.52, 0.5));
		color = mix(average, mix(cover, srgb(DARK_STEEL), gaps), detail);
		inside = 1.0;
		if (city_lights > 0.0) {
			glow += color * srgb(newsstand_light) * 0.8 * city_lights;
		}
	} else if (part == SHED_PLYWOOD || part == SHED_DECK || part == SHED_STEEL && type == TYPE_SHED) {
		// Painted plywood in 4 x 8 ft sheets (the deck's top bare and
		// weathered), and stenciled warnings along the parapet; steel
		// posts and beams in the same paint.
		vec3 paint = srgb(SHED_PAINT[min(variant, 3)]);
		vec2 q = vec2(p.x / 2.44, p.y / 1.22);
		float seams = max(centered_stripes(q.x, 0.02, footprint.x / 2.44), centered_stripes(q.y, 0.02, footprint.y / 1.22));
		color = part == SHED_DECK ? srgb(vec3(0.50, 0.46, 0.40)) * mix(0.8, 1.1, value_noise(p * 1.7 + seed)) : paint;
		color *= 1.0 - 0.25 * seams * float(part != SHED_STEEL);
		if (part == SHED_PLYWOOD && local_position.y > 3.0) {
			float words = band(fract(p.x / 6.1 + rnd(seed, 32.0)), 0.08, 0.5, footprint.x / 6.1)
					* band(p.y, 0.42, 0.6, footprint.y) * stripes(p.x / 0.17, 0.65, footprint.x / 0.17);
			color = mix(color, srgb(vec3(0.92)), 0.8 * words * visible(0.17, pixel));
		}
		glint = part == SHED_STEEL ? 0.2 : 0.0;
		inside = 0.6;
	} else if (part == SHED_CEILING) {
		// The deck's underside, with a lamp every few meters.
		color = srgb(SHED_PAINT[min(variant, 3)]) * 0.9;
		float lamps = band(fract(local_position.x / 3.0 + 0.5), 0.42, 0.58, footprint.x / 3.0)
				* band(local_position.z, 0.9, 1.3, footprint.y);
		color = mix(color, srgb(shed_light), lamps);
		glow += srgb(shed_light) * lamps * mix(shed_glow.x, shed_glow.y, city_lights);
		inside = 1.0;
	} else if (part == SHED_STEEL) {
		// An umbrella's pole.
		color = srgb(STAINLESS);
		glint = 0.3;
	} else if (part == DOCK || part == DOCK_BASE || part == DOCK_PANEL) {
		color = part == DOCK_BASE ? srgb(vec3(0.30, 0.31, 0.33)) : srgb(vec3(0.56, 0.58, 0.60));
		if (part == DOCK_PANEL) {
			// A dock's light (green: a bike is there to take), or the
			// kiosk's map and screen.
			if (variant == 1) {
				color = mix(srgb(vec3(0.86, 0.85, 0.80)), srgb(SHARE_BIKE_BLUE), band(uv.y, 0.9, 1.0, footprint.y / face_size.y));
				color = mix(color, srgb(vec3(0.10, 0.12, 0.14)), fill(box_distance(uv, vec2(0.5, 0.42), vec2(0.3, 0.08))));
			} else {
				float lamp = fill(length((uv - vec2(0.5, 0.82)) * face_size) - 0.025);
				color = mix(color, srgb(vec3(0.3, 0.95, 0.4)), lamp);
				glow += srgb(vec3(0.3, 0.95, 0.4)) * lamp * mix(0.6, 2.0, city_lights);
			}
		}
		glint = 0.2;
	} else if (part == BIKE || part == BIKE_SEAT) {
		color = part == BIKE_SEAT ? srgb(vec3(0.08)) : srgb(SHARE_BIKE_BLUE) * mix(0.9, 1.1, rnd(seed, 33.0));
		glint = 0.3;
	} else if (part == BIKE_TIRE) {
		// A tire round a hub and spokes, cut out of the square.
		vec2 q = uv * 2.0 - 1.0;
		float r = length(q);
		float w = fwidth(r);
		float tire = band(r, 0.84, 1.0, w);
		float spokes = centered_stripes(atan(q.y, q.x) * 1.91, 0.12, fwidth(atan(q.y, q.x) * 1.91)) * band(r, 0.0, 0.85, w)
				* visible(0.01, pixel);
		float hub = band(r, 0.0, 0.18, w);
		if (max(max(tire, hub), spokes * 0.8) < 0.5) {
			discard;
		}
		color = mix(srgb(vec3(0.62)), srgb(vec3(0.07)), tire);
	} else if (part == TABLE || part == CHAIR || part == CHAIR_LEGS) {
		if (part == CHAIR_LEGS) {
			float keep = max(max(band(uv.x, 0.0, 0.1, footprint.x / face_size.x), band(uv.x, 0.9, 1.0, footprint.x / face_size.x)),
					band(uv.y, 0.92, 1.0, footprint.y / face_size.y));
			if (keep < 0.5) {
				discard;
			}
		}
		float r = rnd(seed, 34.0);
		color = srgb(BISTRO[r < 0.55 ? 0 : (r < 0.8 ? 1 : 2)]);
		glint = 0.2;
		occlusion = mix(0.75, 1.0, smoothstep(0.0, 0.5, local_position.y));
	} else if (part == UMBRELLA) {
		// Canvas in panels, every other one a little darker.
		vec3 canvas = srgb(BRIGHT[pick(rnd(seed, 35.0), 8)]) * 0.85;
		color = canvas * (1.0 - 0.12 * stripes(uv.x * 8.0, 0.5, fwidth(uv.x) * 8.0));
	} else if (part == PLANTER) {
		float r = rnd(seed, 36.0);
		color = r < 0.4 ? srgb(vec3(0.62, 0.60, 0.56)) : (r < 0.75 ? srgb(vec3(0.20, 0.21, 0.22)) : srgb(vec3(0.45, 0.32, 0.22)));
		occlusion = mix(0.7, 1.0, smoothstep(0.0, 0.5, local_position.y));
	} else if (part == PLANTS) {
		// Leafy clumps and flowers.
		vec3 w = local_position * 9.0 + seed;
		float leaves = value_noise(w.xz + w.y * 0.7);
		color = mix(srgb(vec3(0.16, 0.30, 0.12)), srgb(vec3(0.36, 0.52, 0.20)), leaves);
		float flowers = step(0.78, value_noise(w.xz * 1.9 - w.y)) * visible(0.05, pixel);
		color = mix(color, srgb(BRIGHT[pick(rnd(seed, 37.0), 6)]), flowers * 0.9);
		occlusion = mix(0.7, 1.0, leaves);
	} else if (part == FOOD_KIOSK || part == KIOSK_ROOF) {
		color = srgb(BRIGHT[pick(rnd(seed, part == KIOSK_ROOF ? 38.0 : 39.0), 7)]) * 0.85;
		color = mix(color, vec3(0.9), 0.6 * band(p.y, 0.3, 0.42, footprint.y) * float(part == FOOD_KIOSK));
		inside = 0.3;
	} else if (part == KIOSK_WINDOW) {
		// The serving window, a menu board on either side, a counter.
		color = srgb(BRIGHT[pick(rnd(seed, 39.0), 7)]) * 0.85;
		float window = fill(box_distance(p, vec2(face_size.x * 0.5, 1.55), vec2(0.6, 0.45)));
		vec2 menu_q = vec2(abs(p.x - face_size.x * 0.5) - 0.95, p.y - 1.55);
		float menu = fill(box_distance(menu_q, vec2(0.0), vec2(0.25, 0.4)));
		vec3 inside_color = srgb(vec3(0.75, 0.62, 0.45));
		color = mix(color, ad_art(vec2(0.5) + menu_q / vec2(0.5, 0.8), vec2(0.5, 0.8), seed), menu);
		color = mix(color, inside_color, window);
		color = mix(color, srgb(STAINLESS), fill(box_distance(p, vec2(face_size.x * 0.5, 1.07), vec2(0.7, 0.03))));
		glow += (inside_color * window + color * menu * 0.5) * mix(0.15, 1.2, city_lights);
		inside = 1.0;
	}

	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + glow;
	toon_glint = glint;
	if (city_lights > 0.0) {
		// Street light from below, more near the ground; shelters and
		// newsstands lit inside.
		EMISSION += ALBEDO * item_light * (street_light_catch * (1.0 - 0.6 * smoothstep(0.0, 5.0, local_position.y)));
		if (type == TYPE_BUS_SHELTER) {
			EMISSION += ALBEDO * srgb(shelter_light) * (0.7 * inside * city_lights);
		} else if (type == TYPE_SHED) {
			// Under the shed, its lamps.
			EMISSION += ALBEDO * srgb(shed_light) * (0.6 * inside * city_lights * (1.0 - smoothstep(2.6, 3.3, local_position.y)));
		} else if (type == TYPE_KIOSK) {
			EMISSION += ALBEDO * srgb(newsstand_light) * (0.5 * inside * city_lights);
		} else if (type == TYPE_NEWSSTAND) {
			EMISSION += ALBEDO * srgb(newsstand_light) * (0.7 * inside * city_lights);
		}
	}
}
