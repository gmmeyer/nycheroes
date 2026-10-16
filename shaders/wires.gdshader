// Overhead wires on the streets lined with utility poles, from near city
// tiles' props (scripts/world/city_props.gd), on the mesh from
// PropMeshes.wires(): six wires, each a strip of quads, UV = (0..1 along it,
// -1 or 1 across), UV2.x its number. Per instance (the props' common layout,
// see PROP_WIRE in tools/citygen/common.py):
//   transform        scales by the span's length along the ground (x, z) and
//                    its pole's height (y), and moves to the pole's foot
//   COLOR.r          how far the far end is above the pole's top (m): the
//                    next pole's top, or the point on a house's wall
//   INSTANCE_CUSTOM  (yaw radians: the span runs along (sin, 0, cos) of it,
//                    CityTileDecoder.WIRE_* bits, seed 0..1, prop type)
// A span strings a line's wires from one pole to the next: bare primaries on
// the crossarm's ends (and on the pole's top on three-phase lines), the
// black secondary below them, phone and cable TV lower down. A service drop
// is one wire from the secondary down to a house, a down guy one straight
// wire from under the crossarm to its anchor in the sidewalk, in a yellow
// guard at the bottom. Each wire sags in a
// parabola and is a ribbon turned to face the camera, at least
// wire_min_pixels wide, so it never breaks up; between fade_distance's
// distances it thins out to nothing. No lighting, no shadows: thin dark lines
// against the sky, darker at night.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled;

// Where the wires hang, in meters from the pole's top (PropMeshes.utility_pole()):
// the primaries on the crossarm's insulators, PRIMARY_REACH either side of the
// pole, the third on the pin on its top, the secondary and drops from its
// bracket, phone and cable TV lower down.
const float PRIMARY_Y = -0.2;
const float PRIMARY_REACH = 0.95;
const float PIN_Y = 0.16;
const float SECONDARY_Y = -1.6;
const float PHONE_Y = -4.1;
const float CABLE_Y = -4.6;
const float GUY_Y = -0.55;
// A guy's yellow guard reaches this far up it from the anchor (m).
const float GUARD_LENGTH = 2.4;

global uniform float night;

// Wires thin out and are gone between these distances from the camera (m).
uniform vec2 fade_distance = vec2(210.0, 290.0);
uniform float wire_min_pixels = 1.0;
uniform vec3 cable_color : source_color = vec3(0.09, 0.09, 0.1);
uniform vec3 primary_color : source_color = vec3(0.34, 0.35, 0.35);
uniform vec3 guard_color : source_color = vec3(0.93, 0.76, 0.16);
uniform float night_darkening : hint_range(0.0, 1.0) = 0.75;

varying flat float bare;
varying flat float guy;
// Meters along the wire from its far end (a guy's anchor).
varying float from_end;

void vertex() {
	float span = length(MODEL_MATRIX[0].xyz);
	float top = length(MODEL_MATRIX[1].xyz);
	float rise = COLOR.r;
	float yaw = INSTANCE_CUSTOM.x;
	int kind = int(INSTANCE_CUSTOM.y + 0.5);
	int wire = int(UV2.x + 0.5);
	// This wire's height at the near pole and the far end (from the pole's
	// top), its offset across the span, its sag (a share of the span) and
	// its radius (m).
	float start_y = PRIMARY_Y;
	float end_y = PRIMARY_Y;
	float across = 0.0;
	float sag = 0.012;
	float radius = 0.008;
	bool shown = true;
	bare = 0.0;
	guy = 0.0;
	if ((kind & 4) != 0) {
		start_y = GUY_Y;
		end_y = 0.0;
		sag = 0.0;
		radius = 0.012;
		shown = wire == 0;
		guy = 1.0;
	} else if ((kind & 1) != 0) {
		start_y = SECONDARY_Y;
		end_y = 0.0;
		sag = 0.03;
		radius = 0.011;
		shown = wire == 0;
	} else if (wire == 0 || wire == 2) {
		across = wire == 0 ? -PRIMARY_REACH : PRIMARY_REACH;
		bare = 1.0;
	} else if (wire == 1) {
		start_y = PIN_Y;
		end_y = PIN_Y;
		bare = 1.0;
		shown = (kind & 2) != 0;
	} else {
		start_y = wire == 3 ? SECONDARY_Y : (wire == 4 ? PHONE_Y : CABLE_Y);
		end_y = start_y;
		sag = wire == 3 ? 0.022 : 0.016;
		radius = wire == 4 ? 0.026 : 0.016;
	}
	vec3 along = vec3(sin(yaw), 0.0, cos(yaw));
	vec3 side = vec3(along.z, 0.0, -along.x);
	vec3 base = MODEL_MATRIX[3].xyz + side * across;
	vec3 from = base + vec3(0.0, top + start_y, 0.0);
	vec3 to = base + along * span + vec3(0.0, top + rise + end_y, 0.0);
	float t = UV.x;
	float dip = 4.0 * sag * span;
	vec3 p = mix(from, to, t) - vec3(0.0, dip * t * (1.0 - t), 0.0);
	vec3 tangent = to - from - vec3(0.0, dip * (1.0 - 2.0 * t), 0.0);
	from_end = (1.0 - t) * length(to - from);

	// A ribbon facing the camera, at least wire_min_pixels wide, thinning
	// out with distance.
	vec3 to_camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz - p;
	float distance_to_camera = length(to_camera);
	vec3 width_way = cross(tangent, to_camera);
	width_way /= max(length(width_way), 1e-6);
	float pixel = 2.0 * distance_to_camera / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float half_width = max(radius, 0.5 * wire_min_pixels * pixel);
	half_width *= 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	if (!shown) {
		half_width = 0.0;
	}
	VERTEX = (VIEW_MATRIX * vec4(p + width_way * (half_width * UV.y), 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec3 color = guy > 0.5 && from_end < GUARD_LENGTH ? guard_color : mix(cable_color, primary_color, bare);
	ALBEDO = color * (1.0 - night_darkening * night);
}
