// Paint on the streets: near city tiles' markings surface
// (tools/citygen/markings.py), long strips whose patterns are drawn here.
// Per vertex:
//   UV    meters along the strip (x: continuous along a line, so dashes line
//         up across pieces and tiles) and across it (y)
//   UV2.x kind: 10 solid white (stop lines, highway edge lines),
//         11 double yellow center line (a 0.45 m strip, UV.y -0.225..0.225:
//         two 0.15 m lines with a 0.15 m gap), 12 white dashed lane line
//         (3 m dashes, 9 m gaps), 13 high-visibility crosswalk (UV.y meters
//         from one curb: 0.6 m bars, 0.6 m gaps)
// Unpainted parts are discarded. The patterns are box-filtered over the
// pixel: a partly painted pixel blends paint into asphalt, so edges stay
// smooth, and dashes and bars smaller than a pixel settle into their average
// (paint at a lighter strength) instead of shimmering. Paint wears off in
// scuffs up close, and fades out in the distance.
// The strips sit a few centimeters above the road; vertex() also pulls them
// toward the camera by a little more than the depth buffer can tell apart at
// that distance, so they never flicker through the road, near or from the air.
// Lighting is the shared toon model (toon.gdshaderinc), facing up like the road.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

const int WHITE = 10;
const int YELLOW = 11;
const int DASHED = 12;
const int CROSSWALK = 13;

uniform vec3 white_paint : source_color = vec3(0.89, 0.88, 0.83);
uniform vec3 yellow_paint : source_color = vec3(0.96, 0.74, 0.22);
// What shows between and around the paint where a pixel is only partly
// painted: the ground shader's road color.
uniform vec3 asphalt : source_color = vec3(0.27, 0.28, 0.31);
// Paint fades out between these distances from the camera (m); past them its
// tile stops drawing it (CityStreamer.MARKINGS_RANGE).
uniform vec2 fade_distance = vec2(550.0, 700.0);
// Paint is lifted z m more (the road under it bends along a 20 m grid, so the
// gap between them varies by a few centimeters), then pulled toward the
// camera by x m plus y times its distance.
uniform vec3 depth_offset = vec3(0.02, 0.0015, 0.02);

// Tile-local position, for wear that differs from strip to strip.
varying vec2 tile_position;
varying float distance_fade;

void vertex() {
	tile_position = VERTEX.xz;
	VERTEX.y += depth_offset.z;
	// Pulled straight toward the camera, which moves it in depth only. (Tiles
	// are only ever moved, never turned, so world directions are mesh
	// directions.)
	vec3 to_camera = CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance_to_camera = length(to_camera);
	distance_fade = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	VERTEX += to_camera / max(distance_to_camera, 1e-3)
			* min(depth_offset.x + depth_offset.y * distance_to_camera, 0.5 * distance_to_camera);
}

void fragment() {
	int kind = int(UV2.x + 0.5);
	vec2 footprint = max(fwidth(UV), vec2(1e-4));
	// How much of this pixel is painted.
	float paint = distance_fade;
	if (kind == YELLOW) {
		paint *= 1.0 - band(UV.y, -0.075, 0.075, footprint.y);
	} else if (kind == DASHED) {
		paint *= stripes(UV.x / 12.0, 0.25, footprint.x / 12.0);
	} else if (kind == CROSSWALK) {
		paint *= stripes(UV.y / 1.2, 0.5, footprint.y / 1.2);
	}
	if (paint < 0.02) {
		discard;
	}
	// Worn paint: the asphalt shows through in scuffs and specks up close.
	float pixel = max(footprint.x, footprint.y);
	vec2 p = tile_position;
	float scuffs = smoothstep(0.6, 0.72, value_noise(p * 0.9 + 3.0) * 0.6 + value_noise(p * 4.5) * 0.4);
	paint *= 1.0 - 0.6 * scuffs * visible(0.3, pixel);

	vec3 color = kind == YELLOW ? yellow_paint : white_paint;
	color *= 0.95 + 0.07 * value_noise(p * 0.05);
	ALBEDO = mix(asphalt, color, paint);
	EMISSION = ALBEDO * toon_ambient(vec3(0.0, 1.0, 0.0), 1.0);
	toon_glint = 0.0;
}
