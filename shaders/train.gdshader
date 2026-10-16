// Subway cars (scripts/world/trains.gd): every car of every train is an
// instance of one MultiMesh of PropMeshes.train_car(), a car in meters at the
// B Division's size (its front toward +z, its left toward +x, the rails at
// y = 0). Per instance:
//   transform        its x and y columns (width, 0, 0) and (0, height, 0):
//                    the car's width and height over the mesh's (the A
//                    Division's are narrower and lower); its z column the
//                    car's heading times its length over the mesh's (0:
//                    no car); its origin on the rails under the car's
//                    middle. The shader turns the car to its heading (its
//                    left level, skip_vertex_transform), so the script
//                    writes no rotations.
//   INSTANCE_CUSTOM  (flags: 1 a cab at its front, 2 a cab at its back, 4 the
//                    front cab leads (headlights; a cab that doesn't shows
//                    red); its route bullet's letter (Trains.GLYPHS); a seed
//                    in 1024ths; doors a side)
//   COLOR            (the bullet's color, sRGB; 1 if its letter is black)
// Custom data and colors arrive as half floats: whole numbers survive.
// The look: stainless steel sides with sliding doors, tinted windows and a
// lit sign near each end showing the route bullet; a roof with air
// conditioners; cab ends dark round their windows, the bullet over them,
// headlights or red lights at the lower corners; other ends with a door; a
// dark underframe and trucks with their wheels. The windows glow a little
// by day and brightly at night (city_lights). Lighting is the shared toon
// model (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes.TrainPart numbers them.
const int SIDE = 0;
const int ROOF = 1;
const int END = 2;
const int UNDER = 3;
const int TRUCK = 4;
// Flags (INSTANCE_CUSTOM.x).
const int CAB_FRONT = 1;
const int CAB_BACK = 2;
const int LEADING = 4;
// The mesh's car: length, width, height (m).
const vec3 MESH_CAR = vec3(18.35, 3.05, 3.7);

// The route bullets' letters (Trains._glyph_texture()): glyph_count cells of
// 7 x 9 pixels side by side, a 5 x 7 letter in each.
uniform sampler2D glyphs : filter_linear, repeat_disable;
uniform float glyph_count = 21.0;
uniform vec3 steel : source_color = vec3(0.68, 0.7, 0.73);
uniform vec3 cab_color : source_color = vec3(0.12, 0.12, 0.13);
uniform vec3 glass_color : source_color = vec3(0.1, 0.12, 0.15);
uniform vec3 underframe : source_color = vec3(0.2, 0.2, 0.21);
uniform vec3 cabin_light : source_color = vec3(1.0, 0.94, 0.82);
// Lit windows' and signs' glow by day and at night; head- and taillights'.
uniform vec2 window_glow = vec2(0.06, 0.9);
uniform vec2 sign_glow = vec2(0.4, 1.6);
uniform vec2 headlight_glow = vec2(1.5, 7.0);
uniform vec2 taillight_glow = vec2(1.0, 4.0);

// The car's length, width and height (m), where this is on it (m, from its
// middle on the rails), and its flags, letter, seed and doors, bullet color.
varying flat vec3 car_size;
varying vec3 local;
varying flat vec4 item;
varying flat vec4 bullet;

void vertex() {
	vec3 along = MODEL_MATRIX[2].xyz;
	vec3 scale = vec3(MODEL_MATRIX[0].x, MODEL_MATRIX[1].y, length(along));
	car_size = MESH_CAR * scale.zxy;
	local = VERTEX * scale;
	item = INSTANCE_CUSTOM;
	bullet = COLOR;
	if (scale.z <= 0.0) {
		// No car: a point behind the camera, so its triangles are dropped.
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		// Its frame: along its heading, its left level.
		vec3 forward = along / scale.z;
		vec3 left = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
		vec3 up = cross(forward, left);
		vec3 world = MODEL_MATRIX[3].xyz + left * local.x + up * local.y + forward * local.z;
		vec3 n = NORMAL / scale;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(left * n.x + up * n.y + forward * n.z, 0.0)).xyz);
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

// Tinted glass with the sky in it, a bright streak across (linear color).
vec3 glass(vec3 p) {
	float q = (p.z + 0.8 * p.y) / 1.9;
	float streak = band(fract(q), 0.1, 0.22, fwidth(q));
	return mix(glass_color, srgb(vec3(0.52, 0.65, 0.78)), 0.18 + 0.25 * streak);
}

// The route bullet at q (m, across and up from its middle, as seen from the
// outside), `radius` big: (the disc's coverage, its letter's).
vec2 route_bullet(vec2 q, float radius) {
	float disc = fill(length(q) - radius);
	// The letter's 5 x 7 pixels fill the disc's middle.
	vec2 pixel = vec2(2.5 + q.x / radius * 4.0, 3.5 - q.y / radius * 4.4);
	vec2 uv = vec2((item.y * 7.0 + 1.0 + pixel.x) / (glyph_count * 7.0), (1.0 + pixel.y) / 9.0);
	float inside = step(0.0, pixel.x) * step(pixel.x, 5.0) * step(0.0, pixel.y) * step(pixel.y, 7.0);
	float letter = smoothstep(0.3, 0.6, textureLod(glyphs, uv, 0.0).r) * inside;
	return vec2(disc, letter * disc);
}

void fragment() {
	int part = int(UV.x + 0.5);
	int flags = int(item.x + 0.5);
	vec3 p = local;
	float half_length = 0.5 * car_size.x;
	float pixel = max(length(fwidth(p)), 1e-4);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float seed = floor(item.z * 1024.0 + 0.5);
	vec3 color = steel * (0.97 + 0.05 * hash(vec2(seed, 1.3)));
	vec3 glow = vec3(0.0);
	float glint = 0.25;
	vec3 lit = cabin_light * mix(window_glow.x, window_glow.y, city_lights);
	vec3 letter_color = bullet.a > 0.5 ? vec3(0.0) : vec3(1.0);

	if (part == SIDE) {
		// Doors evenly along the car, windows between them.
		float pitch = car_size.x * 0.98 / item.w;
		float from_door = (fract((p.z + 0.49 * car_size.x) / pitch) - 0.5) * pitch;
		float door = fill(abs(from_door) - 0.64) * fill(abs(p.y - 2.07) - 0.96);
		// (A post halfway between doors.)
		float window = fill(abs(p.y - 2.33) - 0.4) * fill(0.8 - abs(from_door)) * fill(abs(p.z) - half_length + 0.75)
				* fill(abs(from_door) - pitch * 0.5 + 0.05);
		float door_window = door * fill(abs(abs(from_door) - 0.33) - 0.2) * fill(abs(p.y - 2.4) - 0.36);
		// Fluted below the windows, the doors a little darker, their seams.
		float fluting = centered_stripes(p.z / 0.12, 0.3, fwidth(p.z) / 0.12) * visible(0.06, pixel) * step(p.y, 1.88);
		color *= (1.0 - 0.08 * fluting * (1.0 - door)) * (1.0 - 0.1 * door);
		color *= 1.0 - 0.5 * door * fill(abs(from_door) - 0.012) * visible(0.03, pixel);
		float pane = max(window, door_window);
		color = mix(color, glass(p), pane);
		glow += lit * pane;
		glint = mix(glint, 1.0, pane);
		// The sign near each end: the bullet and an amber line beside it
		// (read from outside: across runs toward the car's back on its left).
		vec2 q = vec2(-sign(p.x) * (p.z - sign(p.z) * (half_length - 0.95)), p.y - 2.36);
		float panel = fill(box_distance(q, vec2(0.0), vec2(0.42, 0.16)));
		vec2 disc = route_bullet(q - vec2(-0.24, 0.0), 0.13);
		float text = fill(box_distance(q, vec2(0.12, 0.0), vec2(0.2, 0.035))) * visible(0.05, pixel);
		vec3 sign_color = mix(mix(vec3(0.02), srgb(vec3(1.0, 0.6, 0.15)), text), srgb(bullet.rgb), disc.x);
		sign_color = mix(sign_color, letter_color, disc.y);
		color = mix(color, sign_color, panel);
		glow += sign_color * panel * max(text, disc.x) * mix(sign_glow.x, sign_glow.y, city_lights);
	} else if (part == ROOF) {
		// Air conditioners toward each end.
		float unit = fill(box_distance(vec2(p.x, abs(p.z)), vec2(0.0, half_length - 3.0), vec2(0.85, 1.4)));
		color = mix(color * 0.9, srgb(vec3(0.5, 0.52, 0.54)), unit);
	} else if (part == END) {
		bool front = p.z > 0.0;
		vec2 q = vec2(sign(p.z) * p.x, p.y);
		if ((flags & (front ? CAB_FRONT : CAB_BACK)) != 0) {
			// A cab: windows either side of the door's, the bullet over them,
			// lights at the lower corners.
			color = cab_color;
			float windows = fill(box_distance(q, vec2(0.0, 2.45), vec2(1.15, 0.52)))
					* fill(0.06 - abs(abs(q.x) - 0.42));
			color = mix(color, glass(p), windows);
			glow += lit * windows * 0.6;
			glint = mix(glint, 1.0, windows);
			vec2 disc = route_bullet(q - vec2(0.0, 3.25), 0.2);
			color = mix(mix(color, srgb(bullet.rgb), disc.x), letter_color, disc.y);
			glow += srgb(bullet.rgb) * (disc.x - disc.y) * mix(sign_glow.x, sign_glow.y, city_lights) * 0.5;
			bool leading = front && (flags & LEADING) != 0;
			float head = fill(length(vec2(abs(q.x) - 0.95, q.y - 1.3)) - 0.1);
			float tail = fill(length(vec2(abs(q.x) - 1.22, q.y - 1.3)) - 0.075);
			color = mix(mix(color, vec3(0.85), head), srgb(vec3(0.5, 0.05, 0.04)), tail);
			glow += srgb(vec3(1.0, 0.95, 0.85)) * head * (leading ? mix(headlight_glow.x, headlight_glow.y, city_lights) : 0.0);
			glow += srgb(vec3(1.0, 0.1, 0.06)) * tail * (leading ? 0.0 : mix(taillight_glow.x, taillight_glow.y, city_lights));
		} else {
			// Between cars: a door with a window in a dark frame.
			float door = fill(box_distance(q, vec2(0.0, 2.05), vec2(0.45, 1.0)));
			float frame = fill(box_distance(q, vec2(0.0, 2.1), vec2(0.62, 1.15))) - door;
			float window = fill(box_distance(q, vec2(0.0, 2.45), vec2(0.25, 0.4)));
			color = mix(mix(color, vec3(0.03), frame), color * 0.85, door);
			color = mix(color, glass(p), window);
			glow += lit * window;
		}
	} else if (part == UNDER) {
		// Equipment boxes along the underframe.
		color = underframe * (1.0 - 0.25 * stripes(p.z / 1.7, 0.08, fwidth(p.z) / 1.7));
		glint = 0.05;
	} else {
		// A truck: its frame, a wheel at each end on each side.
		color = underframe * 0.7;
		float truck = sign(p.z) * 0.354 * car_size.x;
		float wheel = fill(length(vec2(abs(p.z - truck) - 1.05, p.y - 0.43)) - 0.42);
		color = mix(color, srgb(vec3(0.32, 0.31, 0.3)), wheel * step(1.2, abs(p.x)));
		glint = 0.05;
	}

	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, 1.0) + glow;
	toon_glint = glint;
}
