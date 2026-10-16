// Cars: parked cars from near city tiles' props (scripts/world/city_props.gd)
// and moving traffic, all on the one mesh from PropMeshes.car(). Per instance
// (the props' common layout; traffic fills its own MultiMesh the same way):
//   transform        basis diagonal (length, height, length): the car's size
//                    in meters; origin at its base point, the middle of its
//                    footprint on the road
//   INSTANCE_CUSTOM  (yaw radians: its front faces (sin, 0, cos) of it;
//                    model 0..8 (CityTileDecoder.CAR_*); seed 0..1; type: 15
//                    parked, 16 moving)
//   COLOR            (paint 0..11; light flags; wheel roll radians; 0)
// Paints (PAINT below): 0 white, 1 black, 2 silver, 3 mid gray, 4 dark gray,
// 5 dark blue, 6 red, 7 blue, 8 dark green, 9 beige, 10 brown, 11 orange;
// taxis are always taxi yellow, buses MTA white and blue, box trucks' boxes
// white. Light flags, bits, for moving cars (parked ones have none): 1
// driving (headlights at night, dim taillights), 2 braking (bright
// taillights), 4 left and 8 right turn signal (blinking), 16 taxi sign lit
// (available). The wheel roll grows as the car drives forward (distance over
// the wheel's radius, PropMeshes.CAR_WHEEL_RADII), kept within 0..TAU.
// Custom data and colors arrive as half floats: whole numbers survive, and
// seeds in whole 1024ths.
//
// The mesh only says which point of a car each vertex is (CUSTOM0, see
// PropMeshes); this shader builds each model from its row in the tables
// below, scaled to the instance's length and height (tiles vary sizes a
// little), turned to its yaw and moved into place (skip_vertex_transform,
// like the furniture). Every model is the same few parts: a body below the
// windows (its side profile round from the rear bumper over the trunk and
// hood to the front bumper), a cabin on it leaning in toward the roof, a
// tire across each axle with a wheel at each end, the box truck's box, the
// taxi's roof sign, and a dark contact shadow on the ground (cars cast no
// real shadows). Parts a model hasn't fold away. Cars shrink away between
// fade_distance from the camera, like the furniture.
//
// The look: toon-lit glossy paint, dark tinted glass with the sky in it (two
// bright streaks), dark wheel wells, wheels with silver hubs, headlights,
// taillights, grilles, bumpers and plates painted on, door seams and handles
// that fade to the paint with distance; a taxi's NYC badge and roof sign, the
// MTA bus's blue skirt, doors and destination sign, the box truck's ribbed
// box and roll-up door, a pickup's open bed. At night lights glow by their
// flags, and cars near a street light catch its light (night.gdshaderinc).
// Lighting is the shared toon model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes.Car numbers them. The faces round the body's
// outline and the cabin's are numbered like the outline point they end at
// (rear) or start from (front).
const int BODY_SIDE = 0;
const int REAR_LOW = 1;
const int REAR = 2;
const int REAR_TOP = 3;
const int DECK = 4;
const int HOOD = 5;
const int NOSE = 6;
const int FRONT = 7;
const int FRONT_LOW = 8;
const int CABIN_SIDE = 9;
const int REAR_WINDOW = 10;
const int ROOF = 11;
const int WINDSHIELD = 12;
const int TIRE = 13;
const int WHEEL = 14;
const int BOX = 15;
const int SIGN = 16;
const int SHADOW = 17;

// Models (CityTileDecoder.CAR_*).
const int SEDAN = 0;
const int HATCHBACK = 1;
const int SUV = 2;
const int MINIVAN = 3;
const int PICKUP = 4;
const int VAN = 5;
const int TAXI = 6;
const int BOX_TRUCK = 7;
const int BUS = 8;
const int MODEL_COUNT = 9;

// Light flags (COLOR.g).
const int DRIVING = 1;
const int BRAKING = 2;
const int LEFT_SIGNAL = 4;
const int RIGHT_SIGNAL = 8;
const int TAXI_AVAILABLE = 16;

// The models, in meters at the size the tiles give them (front toward +z,
// the middle of the footprint at z = 0, the road at y = 0). Heights of the
// body: the sill (its bottom edge), the deck at the back (trunk lid, bed
// rail), the belt (the windows' bottom edge) and the hood at the front.
// The cabin's profile: where the rear window starts on the deck, where the
// roof starts and ends, and where the windshield meets the hood. Corners:
// the bumpers' lower chamfer, the rear and the front top chamfers, and how
// far the cabin's sides lean in at the roof. Wheels: radius and axles; side
// windows only in front of a z (vans). Doors: the seams at the rear door's
// back edge, the B pillar and the front door's front edge (-9: none); the
// windshield's glass ends at a height (vans, buses). The box (box truck):
// its back and front, top and half width.
// (length, height, body half width, roof height)
const vec4 MODEL_SIZE[9] = vec4[](
		vec4(4.7, 1.45, 0.9, 1.45), vec4(4.2, 1.5, 0.88, 1.5), vec4(4.9, 1.75, 0.95, 1.75),
		vec4(5.1, 1.8, 0.98, 1.8), vec4(5.7, 1.85, 0.98, 1.85), vec4(5.6, 2.5, 1.0, 2.5),
		vec4(4.8, 1.5, 0.9, 1.5), vec4(7.5, 3.3, 1.12, 2.62), vec4(12.2, 3.2, 1.28, 3.12));
// (sill, deck, belt, hood heights)
const vec4 MODEL_BODY[9] = vec4[](
		vec4(0.3, 1.0, 0.96, 0.8), vec4(0.28, 0.98, 0.95, 0.78), vec4(0.42, 1.12, 1.08, 0.98),
		vec4(0.32, 1.0, 0.98, 0.86), vec4(0.5, 1.22, 1.22, 1.15), vec4(0.42, 1.0, 1.05, 0.98),
		vec4(0.3, 1.0, 0.96, 0.8), vec4(0.55, 1.12, 1.4, 1.25), vec4(0.36, 1.2, 1.2, 1.12));
// (rear window's base, roof's back, roof's front, windshield's base z)
const vec4 MODEL_CABIN[9] = vec4[](
		vec4(-1.25, -0.6, 0.45, 1.15), vec4(-1.9, -1.7, 0.25, 0.95), vec4(-2.25, -2.08, 0.5, 1.25),
		vec4(-2.38, -2.26, 0.85, 1.75), vec4(-0.55, -0.45, 0.6, 1.25), vec4(-2.7, -2.66, 1.3, 2.05),
		vec4(-1.3, -0.62, 0.48, 1.2), vec4(1.62, 1.68, 2.75, 3.12), vec4(-5.98, -5.93, 5.97, 6.02));
// (bumper chamfer, rear top chamfer, front top chamfer, cabin lean)
const vec4 MODEL_SHAPE[9] = vec4[](
		vec4(0.12, 0.12, 0.2, 0.14), vec4(0.1, 0.14, 0.2, 0.14), vec4(0.12, 0.12, 0.18, 0.12),
		vec4(0.12, 0.12, 0.2, 0.12), vec4(0.14, 0.06, 0.12, 0.1), vec4(0.1, 0.06, 0.16, 0.06),
		vec4(0.12, 0.12, 0.2, 0.14), vec4(0.1, 0.05, 0.12, 0.06), vec4(0.12, 0.06, 0.06, 0.04));
// (wheel radius, rear axle z, front axle z, side windows from z)
const vec4 MODEL_WHEELS[9] = vec4[](
		vec4(0.33, -1.38, 1.42, -9.0), vec4(0.31, -1.27, 1.28, -9.0), vec4(0.37, -1.5, 1.42, -9.0),
		vec4(0.35, -1.55, 1.5, -9.0), vec4(0.4, -1.75, 1.85, -9.0), vec4(0.36, -1.8, 1.85, 1.15),
		vec4(0.33, -1.4, 1.45, -9.0), vec4(0.48, -2.0, 2.65, -9.0), vec4(0.5, -3.3, 3.6, -9.0));
// (rear door's back edge, B pillar, front door's front edge z, windshield glass top)
const vec4 MODEL_DOORS[9] = vec4[](
		vec4(-1.0, -0.05, 1.05, 9.0), vec4(-1.05, -0.15, 0.85, 9.0), vec4(-1.15, -0.1, 1.0, 9.0),
		vec4(-0.75, 0.35, 1.35, 9.0), vec4(-0.5, 0.3, 1.3, 9.0), vec4(-0.15, 1.15, 2.1, 1.95),
		vec4(-1.0, -0.05, 1.05, 9.0), vec4(-9.0, 1.72, 2.95, 9.0), vec4(-9.0, -9.0, -9.0, 2.85));
// (box's back z, front z, top, half width; 0: no box)
const vec4 MODEL_BOX[9] = vec4[](
		vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0),
		vec4(-3.75, 1.5, 3.3, 1.2), vec4(0.0));
// The taxi's roof sign: half its width, its height, half its length (m).
const vec3 SIGN_SIZE = vec3(0.11, 0.3, 0.45);
// Wheels stand this far out of the body's sides (m).
const float WHEEL_OUT = 0.015;
// The contact shadow reaches this far past the body's sides and ends (m).
const vec2 SHADOW_MARGIN = vec2(0.08, 0.12);

// Paint, in sRGB (see the header).
const vec3 PAINT[12] = vec3[](vec3(0.92, 0.92, 0.9), vec3(0.19, 0.19, 0.21), vec3(0.72, 0.74, 0.77),
		vec3(0.5, 0.52, 0.55), vec3(0.33, 0.34, 0.37), vec3(0.13, 0.2, 0.4), vec3(0.78, 0.14, 0.13),
		vec3(0.2, 0.42, 0.78), vec3(0.15, 0.34, 0.24), vec3(0.8, 0.73, 0.6), vec3(0.44, 0.29, 0.19),
		vec3(0.93, 0.5, 0.13));
const vec3 TAXI_YELLOW = vec3(0.98, 0.76, 0.1);
const vec3 BUS_WHITE = vec3(0.92, 0.93, 0.94);
const vec3 MTA_BLUE = vec3(0.06, 0.3, 0.63);
const vec3 BOX_WHITE = vec3(0.93, 0.93, 0.91);
const vec3 TRIM = vec3(0.11, 0.11, 0.12);
const vec3 RUBBER = vec3(0.1, 0.1, 0.11);
const vec3 HUB = vec3(0.74, 0.75, 0.77);
const vec3 GLASS_DARK = vec3(0.09, 0.12, 0.16);
const vec3 GLASS_SKY = vec3(0.52, 0.65, 0.78);
const vec3 HEADLIGHT = vec3(0.86, 0.88, 0.9);
const vec3 TAILLIGHT = vec3(0.62, 0.07, 0.07);
const vec3 PLATE = vec3(0.95, 0.85, 0.5);
// Ad colors for the taxi's sign and some trucks' boxes.
const vec3 BRIGHT[6] = vec3[](vec3(0.95, 0.3, 0.25), vec3(0.2, 0.62, 0.9), vec3(0.55, 0.3, 0.8),
		vec3(0.15, 0.7, 0.5), vec3(0.98, 0.5, 0.65), vec3(0.12, 0.16, 0.3));

// Cars shrink away between these distances from the camera (m); CityProps
// sets them (and the tiles' ranges to match).
uniform vec2 fade_distance = vec2(320.0, 460.0);
// The contact shadow is lifted this much (m) and pulled toward the camera by
// x m plus y times its distance, so it stays over the road and its paint.
uniform vec3 shadow_offset = vec3(0.03, 0.002, 0.04);
// How dark the contact shadow is (of the road's ambient light): the middle
// under the car, and its edge.
uniform vec2 shadow_darkness = vec2(0.45, 0.7);
// Lights' glow (multiplies their color): headlights by day (running
// lights) and at night; taillights driving at night and braking; turn
// signals; the taxi's sign by day and at night.
uniform vec2 headlight_glow = vec2(0.3, 4.0);
uniform vec2 taillight_glow = vec2(1.2, 4.0);
uniform float signal_glow = 3.0;
uniform vec2 sign_glow = vec2(0.6, 2.2);
// Turn signals blink this many times a second.
uniform float blink_rate = 1.5;
// How much street light (night) cars catch.
uniform float street_light_catch = 1.0;

// (model, paint, light flags, seed in 1024ths): the same for the whole car.
varying flat vec4 car;
// Street light where the car stands (night).
varying flat vec3 car_light;
// Where this is in the car's own frame, at its model's size (m).
varying vec3 local_position;

// A random number per car (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

int pick(float r, int count) {
	return min(int(r * float(count)), count - 1);
}

// A point (z, y) of a model's outline, numbered as PropMeshes builds it:
// round the body from the rear bumper's bottom (0) over the deck, belt and
// hood to the front bumper's bottom (9), the cabin from the rear window's
// base over the roof to the windshield's base (10..13), and the middle of a
// body side (14).
vec2 outline(int model, int id) {
	vec4 size = MODEL_SIZE[model];
	vec4 body = MODEL_BODY[model];
	vec4 cabin = MODEL_CABIN[model];
	vec4 shape = MODEL_SHAPE[model];
	float back = -0.5 * size.x;
	float front = 0.5 * size.x;
	if (id == 0) {
		return vec2(back + shape.x, body.x);
	} else if (id == 1) {
		return vec2(back, body.x + shape.x);
	} else if (id == 2) {
		return vec2(back, body.y - shape.y);
	} else if (id == 3) {
		return vec2(back + shape.y, body.y);
	} else if (id == 4 || id == 10) {
		return vec2(cabin.x, body.z);
	} else if (id == 5 || id == 13) {
		return vec2(cabin.w, body.z);
	} else if (id == 6) {
		return vec2(front - shape.z, body.w);
	} else if (id == 7) {
		return vec2(front, body.w - shape.z);
	} else if (id == 8) {
		return vec2(front, body.x + shape.x);
	} else if (id == 9) {
		return vec2(front - shape.x, body.x);
	} else if (id == 11) {
		return vec2(cabin.y, size.w);
	} else if (id == 12) {
		return vec2(cabin.z, size.w);
	}
	return vec2(0.5 * (cabin.x + cabin.w), 0.5 * (body.x + body.z));
}

void vertex() {
	int model = clamp(int(INSTANCE_CUSTOM.y + 0.5), 0, MODEL_COUNT - 1);
	int part = int(UV.x + 0.5);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float distance_to_camera = distance(camera, base);
	float shown = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	// Parts this model hasn't (and no contact shadow in a shadow map).
	if ((part == SIGN && model != TAXI) || (part == BOX && MODEL_BOX[model].w <= 0.0)
			|| (part == SHADOW && IN_SHADOW_PASS)) {
		shown = 0.0;
	}
	if (shown <= 0.0) {
		// Folded away (a part the model hasn't, or too far): a point behind
		// the camera, so its triangles are dropped.
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		vec4 size = MODEL_SIZE[model];
		vec4 body = MODEL_BODY[model];
		vec4 wheels = MODEL_WHEELS[model];
		float side = CUSTOM0.z;
		vec3 v;
		vec3 n = NORMAL;
		if (part <= WINDSHIELD) {
			// A point of the outline, on this side; the cabin leans in toward
			// its roof.
			vec2 p = outline(model, int(CUSTOM0.x + 0.5));
			float lean = 0.0;
			if (part >= CABIN_SIDE) {
				lean = MODEL_SHAPE[model].w * clamp((p.y - body.z) / (size.w - body.z), 0.0, 1.0);
			}
			v = vec3(side * (size.z - lean), p.y, p.x);
			if (part == BODY_SIDE) {
				n = vec3(side, 0.0, 0.0);
			} else if (part == CABIN_SIDE) {
				n = vec3(side * (size.w - body.z), MODEL_SHAPE[model].w, 0.0);
			} else {
				// Faces round the outline face out of it: the outline runs
				// clockwise in (z, y), so outward is its direction turned right.
				int from = part <= DECK ? part - 1 : part;
				vec2 d = outline(model, from + 1) - outline(model, from);
				n = vec3(0.0, d.x, -d.y);
			}
		} else if (part <= WHEEL) {
			// Round the axle, turned by the wheels' roll (the top goes forward).
			float axle = CUSTOM0.x > 0.5 ? wheels.z : wheels.y;
			float angle = TAU * CUSTOM0.y / 8.0 + COLOR.b;
			vec2 around = vec2(sin(angle), cos(angle));
			v = vec3(side * (size.z + WHEEL_OUT), wheels.x * (1.0 + around.y), axle + wheels.x * around.x);
			n = part == TIRE ? vec3(0.0, around.y, around.x) : vec3(side, 0.0, 0.0);
		} else if (part == BOX) {
			// The box sits on the deck.
			vec4 box = MODEL_BOX[model];
			v = mix(vec3(-box.w, body.y, box.x), vec3(box.w, box.z, box.y), CUSTOM0.xyz);
		} else if (part == SIGN) {
			// On the middle of the roof.
			vec4 cabin = MODEL_CABIN[model];
			vec3 middle = vec3(0.0, size.w, 0.5 * (cabin.y + cabin.z));
			v = middle + mix(vec3(-SIGN_SIZE.x, 0.0, -SIGN_SIZE.z), SIGN_SIZE, CUSTOM0.xyz);
		} else {
			v = vec3(CUSTOM0.x * (size.z + SHADOW_MARGIN.x), shadow_offset.x, CUSTOM0.y * (0.5 * size.x + SHADOW_MARGIN.y));
			n = vec3(0.0, 1.0, 0.0);
		}
		local_position = v;

		// The instance's size over the model's, then turned to the yaw (about
		// +Y, as Godot's Basis turns: +z goes to (sin, cos)).
		float stretch = length(MODEL_MATRIX[0].xyz) / size.x;
		vec3 scale = vec3(stretch, length(MODEL_MATRIX[1].xyz) / size.y, stretch);
		v *= scale * shown;
		n /= scale;
		float yaw = INSTANCE_CUSTOM.x;
		float c = cos(yaw);
		float s = sin(yaw);
		vec3 turned = vec3(c * v.x + s * v.z, v.y, c * v.z - s * v.x);
		n = vec3(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
		vec3 world = base + turned;
		if (part == SHADOW) {
			// Pulled toward the camera, which moves it in depth only.
			vec3 to_camera = camera - world;
			float d = length(to_camera);
			world += to_camera / max(d, 1e-3) * min(shadow_offset.y * d + shadow_offset.z, 0.5 * d);
		}
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

		// Custom data arrives as half floats; whole 1024ths survive that exactly.
		car = vec4(float(model), floor(COLOR.r + 0.5), floor(COLOR.g + 0.5), floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5));
		car_light = vec3(0.0);
		if (city_lights > 0.0 && !IN_SHADOW_PASS) {
			car_light = street_light_at(base.xz, distance_to_camera) * city_lights;
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

// How far (m) q is inside the outline's edge from a to b (the outline runs
// clockwise in (z, y), so inside is to the right).
float inside_edge(vec2 q, vec2 a, vec2 b) {
	vec2 d = normalize(b - a);
	return dot(q - a, vec2(d.y, -d.x));
}

// Tinted glass with the sky in it: lighter where it faces up, with two
// bright streaks across. Returns sRGB-free (linear) color.
vec3 glass(vec3 p, vec3 world_normal, float seed) {
	vec3 color = mix(srgb(GLASS_DARK), srgb(GLASS_SKY), clamp(0.15 + 0.5 * world_normal.y, 0.0, 0.6));
	float q = (p.z + 0.9 * p.y + 0.4 * p.x) / 1.7 + rnd(seed, 6.0);
	float streaks = max(band(fract(q), 0.1, 0.2, fwidth(q)), band(fract(q), 0.27, 0.31, fwidth(q)));
	return mix(color, srgb(vec3(0.82, 0.88, 0.94)), 0.3 * streaks);
}

// How much of a cabin side is window at q (z, y), 0..1: inside the cabin's
// outline by a frame (wider at the back, the C pillar), but the B pillar and
// a van's cargo walls; a bus has a row of windows.
float side_window(int model, vec2 q) {
	float belt = MODEL_BODY[model].z;
	float roof = MODEL_SIZE[model].w;
	float top_frame = model == BUS ? 0.42 : 0.07;
	float inside = min(q.y - belt - 0.05, roof - top_frame - q.y);
	inside = min(inside, min(inside_edge(q, outline(model, 10), outline(model, 11)) - 0.12,
			inside_edge(q, outline(model, 12), outline(model, 13)) - 0.07));
	inside = min(inside, abs(q.x - MODEL_DOORS[model].y) - 0.06);
	inside = min(inside, q.x - MODEL_WHEELS[model].w);
	if (model == BUS) {
		float pane = (0.5 - abs(fract(q.x / 1.45) - 0.5)) * 1.45;
		inside = min(inside, pane - 0.05);
	}
	return fill(-inside);
}

// A bus's doors on its right (-x) side, front and middle: 0..1 at q (z, y).
float bus_door(vec2 q) {
	float door = min(box_distance(q, vec2(4.85, 1.65), vec2(0.6, 1.25)), box_distance(q, vec2(0.2, 1.65), vec2(0.6, 1.25)));
	return fill(door);
}

void fragment() {
	int part = int(UV.x + 0.5);
	int model = int(car.x + 0.5);
	int flags = int(car.z + 0.5);
	float seed = car.w;
	vec3 p = local_position;
	vec4 size = MODEL_SIZE[model];
	vec4 body = MODEL_BODY[model];
	vec4 shape = MODEL_SHAPE[model];
	vec4 wheels = MODEL_WHEELS[model];
	vec4 doors = MODEL_DOORS[model];
	float pixel = max(length(fwidth(p)), 1e-4);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The left side is +x (the car faces +z).
	bool left = p.x > 0.0;

	vec3 paint = srgb(PAINT[clamp(int(car.y + 0.5), 0, 11)]);
	if (model == TAXI) {
		paint = srgb(TAXI_YELLOW);
	} else if (model == BUS) {
		paint = srgb(BUS_WHITE);
	}
	paint *= mix(0.94, 1.05, rnd(seed, 1.0));
	vec3 color = paint;
	float occlusion = 1.0;
	float glint = 0.35;
	vec3 glow = vec3(0.0);
	// Day 0 .. night 1, for lights.
	float dark = city_lights;
	float blink = step(0.5, fract(TIME * blink_rate + seed / 1024.0));
	bool signal_on = blink > 0.5 && (left ? (flags & LEFT_SIGNAL) != 0 : (flags & RIGHT_SIGNAL) != 0);

	if (part == SHADOW) {
		// Darkest in the middle under the car, its edge a little lighter;
		// it's lit only by the sky (the road's ambient light).
		vec2 q = abs(UV2 - 0.5) * 2.0;
		float middle = smoothstep(0.55, 0.85, max(q.x, q.y));
		vec3 road = srgb(vec3(0.27, 0.28, 0.31));
		ALBEDO = vec3(0.0);
		EMISSION = road * toon_ambient(vec3(0.0, 1.0, 0.0), 1.0) * mix(shadow_darkness.x, shadow_darkness.y, middle);
		if (city_lights > 0.0) {
			EMISSION += road * car_light * (0.4 * shadow_darkness.y);
		}
		toon_glint = 0.0;
	} else {
		if (part == BODY_SIDE) {
			// Dark wheel wells over the wheels.
			float well = 1e6;
			for (int i = 0; i < 2; i++) {
				float axle = i == 0 ? wheels.y : wheels.z;
				well = min(well, length(p.zy - vec2(axle, wheels.x)) - wheels.x - 0.07);
			}
			// Door seams and handles, fading with distance.
			float detail = visible(0.06, pixel);
			float seams = 1e6;
			for (int i = 0; i < 3; i++) {
				float z = i == 0 ? doors.x : (i == 1 ? doors.y : doors.z);
				seams = min(seams, abs(p.z - z) - 0.008);
			}
			seams = max(seams, max(body.x + 0.04 - p.y, p.y - body.z + 0.01));
			color *= 1.0 - 0.45 * fill(seams) * detail;
			// A handle toward the back of each door.
			float handles = min(box_distance(p.zy, vec2(doors.y + 0.22, body.z - 0.1), vec2(0.08, 0.018)),
					box_distance(p.zy, vec2(doors.x + 0.22, body.z - 0.1), vec2(0.08, 0.018)));
			color = mix(color, color * 0.55, fill(handles) * detail);
			if (model == TAXI) {
				// The NYC taxi badge on the front doors: black, a yellow "T",
				// then white lettering (read front to back on either side).
				vec2 q = p.zy - vec2(doors.y + 0.5, body.z - 0.25);
				q.x *= left ? -1.0 : 1.0;
				float badge = box_distance(q, vec2(0.0), vec2(0.32, 0.11)) - 0.02;
				color = mix(color, srgb(TRIM), fill(badge));
				float tee = min(box_distance(q, vec2(-0.2, 0.055), vec2(0.075, 0.022)), box_distance(q, vec2(-0.2, -0.005), vec2(0.022, 0.08)));
				float lettering = visible(0.05, pixel);
				color = mix(color, srgb(TAXI_YELLOW), fill(tee) * lettering);
				float letters = fill(box_distance(q, vec2(0.08, 0.0), vec2(0.18, 0.045)))
						* stripes((q.x + 0.1) / 0.09, 0.72, fwidth(q.x) / 0.09);
				color = mix(color, srgb(vec3(0.95)), letters * lettering);
			} else if (model == BUS) {
				// MTA blue skirt; doors on the right side.
				color = mix(color, srgb(MTA_BLUE), fill(body.z - 0.12 - p.y));
				if (!left) {
					float door = bus_door(p.zy);
					color = mix(color, glass(p, world_normal, seed), door * fill(abs(fract((p.z + 0.4) / 0.6) - 0.5) * 0.6 - 0.27));
					color = mix(color, srgb(TRIM), door * (1.0 - fill(abs(fract((p.z + 0.4) / 0.6) - 0.5) * 0.6 - 0.27)));
				}
			} else if (model == BOX_TRUCK && p.z < MODEL_BOX[model].y) {
				// The chassis under the box: a dark frame and a fuel tank.
				color = srgb(vec3(0.2, 0.2, 0.21));
				color = mix(color, srgb(vec3(0.6, 0.62, 0.64)), fill(box_distance(p.zy, vec2(-0.6, 0.85), vec2(0.5, 0.18))));
				glint = 0.1;
			}
			color = mix(color, srgb(vec3(0.04, 0.04, 0.05)), fill(well));
			occlusion = mix(0.75, 1.0, smoothstep(body.x, body.x + 0.3, p.y));
		} else if (part == CABIN_SIDE) {
			float window = side_window(model, p.zy);
			if (model == BUS) {
				if (!left) {
					window = max(window, bus_door(p.zy));
				}
				color = mix(color, srgb(MTA_BLUE), fill(abs(p.y - (size.w - 0.28)) - 0.06));
			} else {
				// A black B pillar between the windows.
				float pillar = max(abs(p.z - doors.y) - 0.07, max(body.z + 0.05 - p.y, p.y - size.w + 0.08));
				color = mix(color, srgb(TRIM), fill(pillar));
			}
			color = mix(color, glass(p, world_normal, seed), window);
			glint = mix(0.35, 1.0, window);
		} else if (part == WINDSHIELD || part == REAR_WINDOW) {
			// Glass inside a frame; the cabin narrows toward the roof.
			float rise = clamp((p.y - body.z) / (size.w - body.z), 0.0, 1.0);
			float half_width = size.z - shape.w * rise;
			bool front = part == WINDSHIELD;
			float frame = front ? 0.08 : (model == PICKUP ? 0.25 : 0.1);
			float top = front ? min(size.w - 0.06, doors.w) : size.w - (model == PICKUP ? 0.18 : 0.07);
			float inside = min(min(half_width - frame - abs(p.x), p.y - body.z - 0.05), top - p.y);
			float window = fill(-inside);
			if (!front && (model == VAN || model == BOX_TRUCK)) {
				// A van's back doors: two small windows. The box truck's cab
				// has none (it's behind the box).
				window = model == VAN ? fill(box_distance(vec2(abs(p.x), p.y), vec2(0.5, 1.8), vec2(0.32, 0.3))) : 0.0;
				color *= 1.0 - 0.45 * fill(abs(p.x) - 0.008) * visible(0.06, pixel);
			} else if (!front && model == BUS) {
				window = fill(box_distance(p.xy, vec2(0.0, 2.45), vec2(1.05, 0.4)));
			}
			color = mix(color, glass(p, world_normal, seed), window);
			glint = mix(0.35, 1.0, window);
			if (front && model == BUS) {
				// The destination sign over the windshield, amber letters.
				float sign = fill(box_distance(p.xy, vec2(0.0, 2.98), vec2(1.0, 0.09)));
				float letters = band(fract(p.x / 0.12), 0.15, 0.75, fwidth(p.x / 0.12)) * band(p.x, -0.85, 0.5, fwidth(p.x))
						* band(p.y, 2.94, 3.02, fwidth(p.y));
				vec3 amber = srgb(vec3(1.0, 0.62, 0.12));
				color = mix(color, mix(srgb(TRIM), amber, letters * visible(0.05, pixel)), sign);
				glow += amber * sign * letters * mix(1.0, 3.0, dark);
			}
		} else if (part == ROOF) {
			if (model == SUV || model == MINIVAN) {
				// Roof rails.
				float rails = abs(abs(p.x) - (size.z - shape.w - 0.12)) - 0.025;
				color = mix(color, srgb(TRIM), fill(rails) * visible(0.05, pixel));
			} else if (model == BUS) {
				// The air conditioner's housing.
				color = mix(color, srgb(vec3(0.7, 0.72, 0.74)), fill(box_distance(p.xz, vec2(0.0, -3.8), vec2(0.8, 1.3))));
			}
		} else if (part == DECK && model == PICKUP && p.z < MODEL_CABIN[model].x - 0.02) {
			// The open bed: dark ribbed floor inside the rails and tailgate.
			float rim = min(size.z - 0.08 - abs(p.x), min(p.z + 0.5 * size.x - 0.08, MODEL_CABIN[model].x - 0.1 - p.z));
			float ribs = centered_stripes(p.x / 0.16, 0.3, fwidth(p.x) / 0.16) * visible(0.08, pixel);
			color = mix(color, srgb(vec3(0.16, 0.16, 0.17)) * (1.0 - 0.3 * ribs), fill(-rim));
			glint = 0.1;
		} else if (part == HOOD && model == BUS) {
			color = srgb(MTA_BLUE);
		} else if (part >= NOSE && part <= FRONT_LOW) {
			// The front: headlights (at the bus's bottom corners), a grille
			// between them, a bumper and a plate below.
			float top = body.w - shape.z;
			float light_y = model == BUS ? 0.65 : top - 0.01;
			vec2 q = vec2(abs(p.x), p.y);
			float lamp = box_distance(q, vec2(size.z - 0.27, light_y), vec2(0.17, 0.065)) - 0.02;
			float turn = box_distance(q, vec2(size.z - 0.05, light_y), vec2(0.03, 0.06));
			float grille_top = model == BUS ? 0.0 : top - 0.03;
			float grille = box_distance(q, vec2(0.0, 0.5 * (grille_top + body.x + shape.x + 0.08)),
					vec2(size.z - 0.5, 0.5 * (grille_top - body.x - shape.x - 0.08)));
			float bumper = body.x + shape.x + 0.08 - p.y;
			float detail = visible(0.05, pixel);
			if (model == BUS) {
				color = srgb(MTA_BLUE);
			}
			color = mix(color, srgb(TRIM) * (1.0 - 0.4 * centered_stripes(p.y / 0.05, 0.4, fwidth(p.y) / 0.05) * detail),
					fill(grille));
			color = mix(color, mix(color, srgb(vec3(0.2, 0.2, 0.22)), 0.7), fill(bumper));
			color = mix(color, srgb(vec3(0.94)), fill(box_distance(p.xy, vec2(0.0, body.x + shape.x + 0.04), vec2(0.15, 0.06))) * detail);
			float lit = (flags & DRIVING) != 0 ? mix(headlight_glow.x, headlight_glow.y, dark) : 0.0;
			color = mix(color, srgb(HEADLIGHT), fill(lamp));
			glow += srgb(vec3(1.0, 0.95, 0.85)) * fill(lamp) * lit;
			vec3 amber = srgb(vec3(1.0, 0.6, 0.1));
			color = mix(color, amber * 0.8, fill(turn));
			glow += amber * fill(turn) * (signal_on ? signal_glow : 0.0);
			glint = max(glint, fill(lamp));
		} else if (part >= REAR_LOW && part <= REAR_TOP) {
			// The back: taillights, a bumper and a plate.
			vec2 q = vec2(abs(p.x), p.y);
			float light_y = body.y - shape.y - 0.1;
			float lamp = box_distance(q, vec2(size.z - 0.2, light_y), vec2(0.15, 0.08)) - 0.02;
			float turn = box_distance(q, vec2(size.z - 0.43, light_y), vec2(0.06, 0.05));
			float bumper = body.x + shape.x + 0.08 - p.y;
			float detail = visible(0.05, pixel);
			if (model == BUS) {
				color = mix(color, srgb(MTA_BLUE), fill(body.z - 0.12 - p.y));
			}
			color = mix(color, mix(color, srgb(vec3(0.2, 0.2, 0.22)), 0.7), fill(bumper));
			color = mix(color, srgb(PLATE), fill(box_distance(p.xy, vec2(0.0, body.x + shape.x + 0.2), vec2(0.15, 0.075))) * detail);
			vec3 red = srgb(vec3(1.0, 0.1, 0.06));
			float lit = (flags & BRAKING) != 0 ? taillight_glow.y : ((flags & DRIVING) != 0 ? taillight_glow.x * dark : 0.0);
			color = mix(color, srgb(TAILLIGHT), fill(lamp));
			glow += red * fill(lamp) * lit;
			vec3 amber = srgb(vec3(1.0, 0.6, 0.1));
			color = mix(color, amber * 0.7, fill(turn));
			glow += amber * fill(turn) * (signal_on ? signal_glow : 0.0);
			glint = max(glint, fill(lamp));
		} else if (part == TIRE) {
			color = srgb(RUBBER);
			glint = 0.0;
			occlusion = 0.7;
		} else if (part == WHEEL) {
			// The tire's sidewall round a silver hub with five holes.
			vec2 q = (UV2 - 0.5) * 2.0;
			float r = length(q);
			// Turns round the hub, and how much of a turn a pixel covers (from
			// q, which has no seam where atan() jumps).
			float turns = atan(q.y, q.x) * 5.0 / TAU;
			float turns_footprint = length(fwidth(q)) / max(r, 0.05) * 5.0 / TAU;
			float holes = band(fract(turns), 0.25, 0.75, turns_footprint) * band(r, 0.24, 0.5, fwidth(r)) * visible(0.04, pixel);
			vec3 hub = srgb(model == BOX_TRUCK || model == BUS ? vec3(0.6, 0.62, 0.64) : HUB);
			color = mix(srgb(RUBBER), hub * (1.0 - 0.6 * holes), fill(r - 0.6));
			color *= 1.0 - 0.3 * fill(0.12 - r);
			glint = 0.3 * fill(r - 0.6);
		} else if (part == BOX) {
			// White, ribbed sides with a rail top and bottom; a roll-up door at
			// the back; some carry a colored band.
			color = srgb(BOX_WHITE) * mix(0.95, 1.03, rnd(seed, 2.0));
			vec3 box_normal = abs(NORMAL);
			float detail = visible(0.06, pixel);
			vec2 face = UV2;
			if (abs(p.x) > MODEL_BOX[model].w - 0.01) {
				float ribs = centered_stripes(p.z / 0.6, 0.06, fwidth(p.z) / 0.6);
				color *= 1.0 - 0.18 * ribs * detail;
				if (rnd(seed, 3.0) < 0.45) {
					vec3 band_color = srgb(BRIGHT[pick(rnd(seed, 4.0), 6)]);
					color = mix(color, band_color, fill(abs(p.y - 2.3) - 0.35) * fill(abs(p.z + 1.1) - 2.2));
				}
			} else if (p.z < MODEL_BOX[model].x + 0.01) {
				float ribs = centered_stripes(p.y / 0.2, 0.12, fwidth(p.y) / 0.2);
				color *= 1.0 - 0.22 * ribs * detail;
				color = mix(color, srgb(vec3(0.3, 0.31, 0.32)), fill(abs(p.x) - 0.04) * fill(abs(p.y - 1.45) - 0.12) * detail);
			}
			float rails = min(abs(p.y - MODEL_BOX[model].z) - 0.06, abs(p.y - body.y) - 0.06);
			color = mix(color, srgb(vec3(0.55, 0.56, 0.58)), fill(rails) * step(p.y, MODEL_BOX[model].z - 0.005));
			glint = 0.15;
		} else if (part == SIGN) {
			// The taxi's roof sign: an ad down each side, the lamp at each end;
			// lit while the taxi is available.
			bool lit = (flags & TAXI_AVAILABLE) != 0;
			vec2 q = UV2;
			if (abs(p.x) > SIGN_SIZE.x - 0.005) {
				vec3 ad = srgb(BRIGHT[pick(rnd(seed, 5.0), 6)]);
				color = mix(ad, srgb(vec3(0.96)), band(q.y, 0.35, 0.65, fwidth(q.y)) * band(fract(q.x * 5.0), 0.1, 0.8, fwidth(q.x) * 5.0)
						* band(q.x, 0.15, 0.85, fwidth(q.x)));
				color = mix(srgb(TRIM), color, band(q.x, 0.03, 0.97, fwidth(q.x)) * band(q.y, 0.08, 0.92, fwidth(q.y)));
				glow += color * mix(sign_glow.x, sign_glow.y, dark) * (lit ? 1.0 : 0.25 * dark);
			} else if (abs(p.y - size.w - SIGN_SIZE.y) > 0.005) {
				vec3 lamp = srgb(vec3(1.0, 0.9, 0.55));
				color = mix(srgb(TRIM), lamp, fill(box_distance(q, vec2(0.5), vec2(0.36, 0.3))));
				glow += lamp * fill(box_distance(q, vec2(0.5), vec2(0.36, 0.3))) * (lit ? mix(sign_glow.x, sign_glow.y, dark) * 1.5 : 0.0);
			} else {
				color = srgb(TRIM);
			}
			glint = 0.3;
		}
		if (part == HOOD || part == ROOF || part == DECK) {
			// Glossy paint catches the sky on top (so dark cars still read as
			// cars from above).
			color = mix(color, srgb(GLASS_SKY), 0.12 * smoothstep(0.6, 0.95, world_normal.y));
		}

		ALBEDO = toon_night_albedo(color);
		EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + glow;
		toon_glint = glint;
		if (city_lights > 0.0) {
			// Street light, more near the ground.
			EMISSION += ALBEDO * car_light * (street_light_catch * (1.0 - 0.5 * smoothstep(0.0, 2.0, p.y)));
		}
	}
}
