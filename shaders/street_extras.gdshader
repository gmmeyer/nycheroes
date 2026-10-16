// Sidewalk sheds, the bike share's docks and plaza furniture from near city
// tiles' props (scripts/world/city_props.gd): sheds' sections on the mesh
// from PropMeshes.sidewalk_shed(), docks, their kiosks, cafe tables,
// planters and food kiosks on street_furniture_extra(). Laid out and drawn
// like the street furniture (shaders/street_furniture.gdshader), in a
// shader of its own: added to that one, these parts made Chrome on Windows
// compile it twice as long (0.9 to 1.3-1.7 s; the D3D compiler's time grows
// with about the square of a shader's code), while this one takes about a
// fifth of a second. Per instance (the props' common layout):
//   transform        scales by the piece's width (x, z) and height (y) and
//                    moves it to its base
//   INSTANCE_CUSTOM  (yaw radians: its front faces (sin, 0, cos) of it; variant;
//                    seed 0..1; prop type 19..23)
//   COLOR.r          a shed's reach out from the wall (m): its depth (z)
//                    stretches to that, not to its width
// Each mesh holds its pieces' shapes, tagged per vertex (CUSTOM0: type,
// variant bits, the size it's built at); this shader folds away every shape
// but the instance's own, scales that one to the piece's size, turns it to
// its yaw and moves it into place itself (skip_vertex_transform). Pieces
// shrink away between fade distances from the camera, sooner for the small
// ones (docks, tables, planters) and sheds (CityProps sets them).
//
// The look: sheds in painted plywood sheets (hunter green, a few white,
// black or blue) on steel posts, stenciled warnings along the parapet, lamps
// under the deck (lit by day, brighter at night, lighting the sidewalk
// under them); the bike share's generic blue bikes (no names or marks), a
// share of each section's docks empty, a green light on each dock, the
// kiosk's map; bistro tables and chairs in green, silver or red, canvas
// umbrellas, planters of shrubs and flowers, food kiosks with their window
// and menus lit at night. At night pieces near a street light catch its
// light (night.gdshaderinc). Lighting is the shared toon model
// (toon.gdshaderinc).
shader_type spatial;
render_mode ambient_light_disabled, cull_disabled, skip_vertex_transform;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts (UV.x), as PropMeshes.Extra numbers them.
const int SHED_PLYWOOD = 0;
const int SHED_DECK = 1;
const int SHED_CEILING = 2;
const int STEEL = 3;
const int DOCK = 4;
const int DOCK_BASE = 5;
const int DOCK_PANEL = 6;
const int BIKE = 7;
const int BIKE_TIRE = 8;
const int BIKE_SEAT = 9;
const int SOLAR_PANEL = 10;
const int TABLE = 11;
const int CHAIR = 12;
const int CHAIR_LEGS = 13;
const int UMBRELLA = 14;
const int PLANTER = 15;
const int PLANTS = 16;
const int FOOD_KIOSK = 17;
const int KIOSK_WINDOW = 18;
const int KIOSK_ROOF = 19;
const int KIOSK_CEILING = 20;

// Prop types (CityTileDecoder.PROP_*).
const int TYPE_SHED = 19;
const int TYPE_BIKE_DOCK = 20;
const int TYPE_KIOSK = 23;

// As PropMeshes builds them: a shed's reach out from the wall
// (PropMeshes.SHED_DEPTH), the docks' spacing (CityTileDecoder.DOCK_SPACING).
const float SHED_DEPTH = 2.5;
const float DOCK_SPACING = 0.8;

const vec3 STAINLESS = vec3(0.64, 0.66, 0.68);
const vec3 SHARE_BIKE_BLUE = vec3(0.14, 0.40, 0.74);

// Pieces shrink away between these distances from the camera (m): small ones
// (docks, tables, planters) and large ones (kiosks), as CityProps sets the
// street furniture's.
uniform vec2 small_fade_distance = vec2(180.0, 260.0);
uniform vec2 large_fade_distance = vec2(420.0, 580.0);
// Sheds, a little sooner (CityProps.SHED_FADE_SHARE).
uniform vec2 shed_fade_distance = vec2(330.0, 450.0);
// The lamps under sidewalk sheds (sRGB), lit by day too (dimmer), and food
// kiosks' light at night.
uniform vec3 shed_light : source_color = vec3(0.92, 0.96, 1.0);
uniform vec2 shed_glow = vec2(0.6, 2.4);
uniform vec3 kiosk_light : source_color = vec3(1.0, 0.86, 0.62);
// The share of a section's docks holding a bike: from this, up to all.
uniform float dock_fill = 0.45;
// How much street light (night) the pieces catch.
uniform float street_light_catch = 1.0;

// (type, variant, seed in 1024ths, 0).
varying flat vec4 item;
// Street light where the piece stands (night).
varying flat vec3 item_light;
// Where this is in the piece's own frame (m).
varying vec3 local_position;
// The face's size (m), for patterns in meters.
varying vec2 face_size;

// A random number per piece (and salt).
float rnd(float seed, float salt) {
	return hash(vec2(seed + salt * 3.7, salt * 13.1 + 7.0));
}

// A bright paint (sRGB) for umbrellas, flowers and kiosks: a hue from r, some
// of them pale. Worked out, not looked up: dynamically indexed constant
// arrays cost the D3D compiler (see "Shader compile time" in docs/ROADMAP.md).
vec3 bright_paint(float r) {
	vec3 hue = clamp(abs(mod(r * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return mix(vec3(0.92), hue, fract(r * 7.3) < 0.2 ? 0.25 : 0.7) * 0.9;
}

void vertex() {
	int variant = int(INSTANCE_CUSTOM.y + 0.5);
	int type = int(INSTANCE_CUSTOM.w + 0.5);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float distance_to_camera = distance(camera, base);
	vec2 fade = type >= 20 && type <= 22 ? small_fade_distance : (type == TYPE_SHED ? shed_fade_distance : large_fade_distance);
	float shown = 1.0 - smoothstep(fade.x, fade.y, distance_to_camera);
	// Custom data arrives as half floats; whole 1024ths survive that exactly.
	float seed = floor(INSTANCE_CUSTOM.z * 1024.0 + 0.5);
	int part = int(UV.x + 0.5);
	// Only the piece's own shape (CUSTOM0: type, variant bits).
	if (int(CUSTOM0.x + 0.5) != type || ((int(CUSTOM0.y + 0.5) >> variant) & 1) == 0) {
		shown = 0.0;
	}
	if (type == TYPE_BIKE_DOCK && part >= BIKE && part <= BIKE_SEAT) {
		// Empty docks: each section holds its own share of bikes.
		float dock = floor(VERTEX.x / DOCK_SPACING + 8.0);
		if (rnd(seed + dock * 0.37, 31.0) > mix(dock_fill, 1.0, rnd(seed, 30.0))) {
			shown = 0.0;
		}
	}
	if (shown <= 0.0) {
		// Folded away (another shape's vertex, an empty dock, or too far): a
		// point behind the camera, so its triangles are dropped.
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		float height = length(MODEL_MATRIX[1].xyz);
		float width = length(MODEL_MATRIX[0].xyz);
		float yaw = INSTANCE_CUSTOM.x;
		vec3 scale = vec3(width / CUSTOM0.w, height / CUSTOM0.z, width / CUSTOM0.w);
		if (type == TYPE_SHED) {
			scale.z = COLOR.r / SHED_DEPTH;
		}
		vec3 v = VERTEX * scale;
		local_position = v;
		face_size = CUSTOM1.xy;

		// Turn to the yaw (about +Y, as Godot's Basis turns: +z goes to (sin, cos)).
		float c = cos(yaw);
		float s = sin(yaw);
		vec3 turned = vec3(c * v.x + s * v.z, v.y, c * v.z - s * v.x);
		// Normals of a stretched shape follow the inverse of its stretch.
		vec3 n = NORMAL / scale;
		n = vec3(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
		VERTEX = (VIEW_MATRIX * vec4(base + turned * shown, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

		item = vec4(float(type), float(variant), seed, 0.0);
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
	// Lit at night from inside (under a shed, in a kiosk), and how much.
	float inside = 0.0;

	if (part == SHED_PLYWOOD || part == SHED_DECK || part == STEEL && type == TYPE_SHED) {
		// Painted plywood in 4 x 8 ft sheets (the deck's top bare), and
		// stenciled warnings along the parapet; steel posts and beams in the
		// same paint. Hunter green, or the odd white, black or blue shed.
		vec3 paint = srgb(variant == 0 ? vec3(0.20, 0.37, 0.25) : (variant == 1 ? vec3(0.85, 0.85, 0.82)
				: (variant == 2 ? vec3(0.15, 0.15, 0.16) : vec3(0.18, 0.30, 0.52))));
		vec2 q = vec2(p.x / 2.44, p.y / 1.22);
		float seams = max(centered_stripes(q.x, 0.02, footprint.x / 2.44), centered_stripes(q.y, 0.02, footprint.y / 1.22));
		color = part == SHED_DECK ? srgb(vec3(0.50, 0.46, 0.40)) : paint;
		color *= 1.0 - 0.25 * seams * float(part != STEEL);
		if (part == SHED_PLYWOOD) {
			float words = band(fract(p.x / 6.1 + rnd(seed, 32.0)), 0.08, 0.5, footprint.x / 6.1)
					* band(p.y, 0.42, 0.6, footprint.y) * stripes(p.x / 0.17, 0.65, footprint.x / 0.17);
			color = mix(color, srgb(vec3(0.92)), 0.8 * words * visible(0.17, pixel));
		}
		glint = part == STEEL ? 0.2 : 0.0;
		inside = 0.6;
	} else if (part == SHED_CEILING) {
		// The deck's underside, painted white, with a lamp every few meters.
		color = srgb(vec3(0.78, 0.78, 0.74));
		float lamps = band(fract(local_position.x / 3.0 + 0.5), 0.42, 0.58, footprint.x / 3.0)
				* band(local_position.z, 0.9, 1.3, footprint.y);
		color = mix(color, srgb(shed_light), lamps);
		glow += srgb(shed_light) * lamps * mix(shed_glow.x, shed_glow.y, city_lights);
		inside = 1.0;
	} else if (part == STEEL) {
		// An umbrella's pole.
		glint = 0.3;
	} else if (part == DOCK || part == DOCK_BASE || part == DOCK_PANEL) {
		color = part == DOCK_BASE ? srgb(vec3(0.30, 0.31, 0.33)) : srgb(vec3(0.56, 0.58, 0.60));
		if (part == DOCK_PANEL && variant == 1) {
			// The kiosk's map, under a blue band, and its screen.
			color = mix(srgb(vec3(0.86, 0.85, 0.80)), srgb(SHARE_BIKE_BLUE), band(uv.y, 0.9, 1.0, footprint.y / face_size.y));
			color = mix(color, srgb(vec3(0.10, 0.12, 0.14)), fill(box_distance(uv, vec2(0.5, 0.42), vec2(0.3, 0.08))));
		} else if (part == DOCK_PANEL) {
			// A dock's light: green, a bike to take.
			float lamp = fill(length((uv - vec2(0.5, 0.82)) * face_size) - 0.025);
			color = mix(color, srgb(vec3(0.3, 0.95, 0.4)), lamp);
			glow += srgb(vec3(0.3, 0.95, 0.4)) * lamp * mix(0.6, 2.0, city_lights);
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
		float angle = atan(q.y, q.x) * 1.91;
		float spokes = centered_stripes(angle, 0.12, fwidth(angle)) * band(r, 0.0, 0.85, w) * visible(0.01, pixel);
		if (max(max(tire, band(r, 0.0, 0.18, w)), spokes * 0.8) < 0.5) {
			discard;
		}
		color = mix(srgb(vec3(0.62)), srgb(vec3(0.07)), tire);
	} else if (part == SOLAR_PANEL) {
		vec2 cells = vec2(uv.x * 4.0, uv.y * 3.0);
		float grid = max(centered_stripes(cells.x, 0.06, fwidth(cells.x)), centered_stripes(cells.y, 0.06, fwidth(cells.y)));
		color = mix(srgb(vec3(0.10, 0.14, 0.30)), srgb(vec3(0.62, 0.64, 0.68)), grid);
		glint = 1.0;
	} else if (part == TABLE || part == CHAIR || part == CHAIR_LEGS) {
		if (part == CHAIR_LEGS) {
			float keep = max(max(band(uv.x, 0.0, 0.1, footprint.x / face_size.x), band(uv.x, 0.9, 1.0, footprint.x / face_size.x)),
					band(uv.y, 0.92, 1.0, footprint.y / face_size.y));
			if (keep < 0.5) {
				discard;
			}
		}
		// Green, silver or red.
		float r = rnd(seed, 34.0);
		color = srgb(r < 0.55 ? vec3(0.20, 0.38, 0.26) : (r < 0.8 ? vec3(0.66, 0.68, 0.70) : vec3(0.72, 0.16, 0.14)));
		glint = 0.2;
		occlusion = mix(0.75, 1.0, smoothstep(0.0, 0.5, local_position.y));
	} else if (part == UMBRELLA) {
		// Canvas in panels, every other one a little darker.
		color = srgb(bright_paint(rnd(seed, 35.0))) * (1.0 - 0.12 * stripes(uv.x * 8.0, 0.5, fwidth(uv.x) * 8.0));
	} else if (part == PLANTER) {
		// Concrete, charcoal or wood.
		float r = rnd(seed, 36.0);
		color = srgb(r < 0.4 ? vec3(0.66, 0.64, 0.60) : (r < 0.75 ? vec3(0.28, 0.29, 0.30) : vec3(0.56, 0.43, 0.30)));
		occlusion = mix(0.7, 1.0, smoothstep(0.0, 0.5, local_position.y));
	} else if (part == PLANTS) {
		// Leafy clumps and flowers.
		vec3 w = local_position * 9.0 + seed;
		float leaves = value_noise(w.xz + w.y * 0.7);
		color = mix(srgb(vec3(0.24, 0.42, 0.16)), srgb(vec3(0.48, 0.64, 0.26)), leaves);
		float flowers = step(0.7, hash(floor(w.xz * 1.5 - w.y))) * step(0.5, leaves) * visible(0.05, pixel);
		color = mix(color, srgb(bright_paint(rnd(seed, 37.0))), flowers * 0.9);
		occlusion = mix(0.7, 1.0, leaves);
	} else if (part == FOOD_KIOSK || part == KIOSK_ROOF) {
		// Painted, with a pale stripe round the booth.
		color = srgb(bright_paint(rnd(seed, part == KIOSK_ROOF ? 38.0 : 39.0)));
		color = mix(color, vec3(0.9), 0.6 * band(p.y, 0.3, 0.42, footprint.y) * float(part == FOOD_KIOSK));
		inside = 0.3;
	} else if (part == KIOSK_WINDOW) {
		// The serving window, a menu board either side, a counter.
		color = srgb(bright_paint(rnd(seed, 39.0)));
		float window = fill(box_distance(p, vec2(face_size.x * 0.5, 1.55), vec2(0.6, 0.45)));
		vec2 menu_q = vec2(abs(p.x - face_size.x * 0.5) - 0.95, p.y - 1.55);
		float menu = fill(box_distance(menu_q, vec2(0.0), vec2(0.25, 0.4)));
		vec3 counter_light = srgb(vec3(0.75, 0.62, 0.45));
		float lines = stripes(menu_q.y / 0.09, 0.45, footprint.y / 0.09) * band(abs(menu_q.x), 0.0, 0.18, footprint.x);
		color = mix(color, mix(srgb(vec3(0.92, 0.90, 0.84)), srgb(vec3(0.15)), lines * visible(0.09, pixel)), menu);
		color = mix(color, counter_light, window);
		color = mix(color, srgb(STAINLESS), fill(box_distance(p, vec2(face_size.x * 0.5, 1.07), vec2(0.7, 0.03))));
		glow += (counter_light * window + color * menu * 0.5) * mix(0.15, 1.2, city_lights);
		inside = 1.0;
	} else if (part == KIOSK_CEILING) {
		color = srgb(vec3(0.82, 0.84, 0.86));
		glow += srgb(kiosk_light) * 1.2 * city_lights;
		inside = 1.0;
	}

	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, occlusion) + glow;
	toon_glint = glint;
	if (city_lights > 0.0) {
		// Street light from below, more near the ground; under sheds their
		// lamps, in kiosks theirs.
		EMISSION += ALBEDO * item_light * (street_light_catch * (1.0 - 0.6 * smoothstep(0.0, 5.0, local_position.y)));
		if (type == TYPE_SHED) {
			EMISSION += ALBEDO * srgb(shed_light) * (0.6 * inside * city_lights * (1.0 - smoothstep(2.6, 3.3, local_position.y)));
		} else if (type == TYPE_KIOSK) {
			EMISSION += ALBEDO * srgb(kiosk_light) * (0.5 * inside * city_lights);
		}
	}
}
