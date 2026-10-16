// The glow around moving cars' headlights and taillights at night: a soft
// additive disc on a quad per light (Traffic's glow mesh: corners -1..1 in
// UV, UV2.x which light: 0 and 1 the headlights, left and right, 2 and 3 the
// taillights), turned to the camera at the light, on the same instances as
// the cars (shaders/car.gdshader's layout: basis diagonal (length, height,
// length), INSTANCE_CUSTOM (yaw, model, seed, type), COLOR (paint, light
// flags, wheel roll, 0)). Headlights shine forward and taillights back, so
// each glows only toward the side it faces; taillights are dim while driving
// and bright while braking. Traffic only draws these while the city's lights
// are on. Far away a glow keeps at least glow_min_pixels across, dimmer as it
// widens, so night traffic reads as streams of white and red dots.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/night.gdshaderinc"

const int DRIVING = 1;
const int BRAKING = 2;
const int MODEL_COUNT = 9;
// Per model (CityTileDecoder.CAR_*), as shaders/car.gdshader builds them:
// (length, height, half the width between the lights, headlights' height),
// and the taillights' height.
const vec4 LIGHTS[9] = vec4[](
		vec4(4.7, 1.45, 0.66, 0.66), vec4(4.2, 1.5, 0.64, 0.66), vec4(4.9, 1.75, 0.7, 0.85),
		vec4(5.1, 1.8, 0.72, 0.76), vec4(5.7, 1.85, 0.72, 0.95), vec4(5.6, 2.5, 0.74, 0.8),
		vec4(4.8, 1.5, 0.66, 0.66), vec4(7.5, 3.3, 0.86, 0.9), vec4(12.2, 3.2, 1.0, 0.6));
const float TAIL_HEIGHT[9] = float[](0.86, 0.86, 1.0, 0.95, 1.05, 0.9, 0.86, 1.0, 1.0);

// Headlights' and taillights' light (sRGB).
uniform vec3 headlight_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec3 taillight_color : source_color = vec3(1.0, 0.12, 0.06);
// Radius up close (m), at least this many pixels, and strength.
uniform float glow_size = 0.45;
uniform float glow_min_pixels = 1.6;
uniform float glow_strength = 0.8;
// Taillights' strength driving and braking (of glow_strength).
uniform vec2 taillight_strength = vec2(0.35, 1.0);
// Glows fade out between these distances from the camera (m), like the cars.
uniform vec2 fade_distance = vec2(320.0, 460.0);

varying vec3 glow;
varying vec2 corner;

void vertex() {
	int model = clamp(int(INSTANCE_CUSTOM.y + 0.5), 0, MODEL_COUNT - 1);
	int flags = int(COLOR.g + 0.5);
	int light = int(UV2.x + 0.5);
	vec4 size = LIGHTS[model];
	// The instance's size over the model's (cars grow in and shrink away).
	float stretch = length(MODEL_MATRIX[0].xyz) / size.x;
	bool front = light < 2;
	float side = (light == 0 || light == 2) ? -1.0 : 1.0;
	vec3 local = vec3(side * size.z, front ? size.w : TAIL_HEIGHT[model], (front ? 0.5 : -0.5) * size.x + (front ? 0.05 : -0.05));
	local *= stretch;
	float yaw = INSTANCE_CUSTOM.x;
	float c = cos(yaw);
	float s = sin(yaw);
	vec3 forward = vec3(s, 0.0, c);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 world = base + vec3(c * local.x + s * local.z, local.y, c * local.z - s * local.x);
	vec3 camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	vec3 to_camera = normalize(camera - world);
	// Each light faces its own way.
	float facing = smoothstep(-0.1, 0.5, dot(to_camera, front ? forward : -forward));
	float strength = front ? ((flags & DRIVING) != 0 ? 1.0 : 0.0)
			: ((flags & BRAKING) != 0 ? taillight_strength.y : ((flags & DRIVING) != 0 ? taillight_strength.x : 0.0));
	vec3 center = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	float distance_to_camera = max(-center.z, 0.1);
	float pixel = 2.0 * distance_to_camera / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float radius = max(glow_size * stretch, glow_min_pixels * pixel);
	float energy = (glow_size * glow_size) / (radius * radius);
	float fade = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	glow = srgb(front ? headlight_color : taillight_color) * (glow_strength * strength * facing * energy * fade * city_lights);
	corner = UV;
	if (dot(glow, vec3(1.0)) <= 0.0) {
		VERTEX = vec3(0.0, 0.0, 1.0);  // dark: behind the camera, dropped
	} else {
		// Pulled toward the camera a little, so the car's own body doesn't cut it.
		VERTEX = center * (1.0 - min(radius, 0.5 * distance_to_camera) / length(center)) + vec3(UV * radius, 0.0);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r2 = dot(corner, corner);
	float falloff = max(1.0 - r2, 0.0);
	ALBEDO = glow * (falloff * falloff * (0.25 + 0.75 * exp(-8.0 * r2)));
}
