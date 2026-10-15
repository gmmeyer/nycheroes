// The glow around a street light's head at night: a soft additive disc on a
// quad (PropMeshes.street_light_glow(), corners -1..1 in UV) turned to face
// the camera at the lamp's lens or lantern. Per instance, the same data as
// the lamps themselves (shaders/street_light.gdshader). CityProps only shows
// these while the city's lights are on.
// Far away a glow keeps at least glow_min_pixels across but gets dimmer as it
// widens, with the same light in all, so distant lamps become a calm
// glitter of dots instead of sub-pixel specks that flicker.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/night.gdshaderinc"

// The lamps' light (sRGB), as on the lamps.
uniform vec3 cobra_head_light : source_color = vec3(1.0, 0.84, 0.62);
uniform vec3 post_top_light : source_color = vec3(1.0, 0.76, 0.48);
// Radius up close (m), at least this many pixels, and strength.
uniform float glow_size = 1.1;
uniform float glow_min_pixels = 2.0;
uniform float glow_strength = 0.9;
// Glows fade out between these distances from the camera (m).
uniform vec2 fade_distance = vec2(1100.0, 1500.0);

varying vec3 glow;
varying vec2 corner;

void vertex() {
	float height = length(MODEL_MATRIX[1].xyz);
	float arm = length(MODEL_MATRIX[0].xyz);
	float yaw = INSTANCE_CUSTOM.x;
	bool post_top = INSTANCE_CUSTOM.y > 0.5;
	// The lens under a cobra-head's housing, or the middle of a post-top's lantern.
	vec3 head = MODEL_MATRIX[3].xyz + (post_top ? vec3(0.0, height * 0.87, 0.0)
			: vec3(sin(yaw) * (arm + 0.25), height - 0.22, cos(yaw) * (arm + 0.25)));
	vec3 center = (VIEW_MATRIX * vec4(head, 1.0)).xyz;
	float distance_to_camera = max(-center.z, 0.1);
	float pixel = 2.0 * distance_to_camera / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float radius = max(glow_size, glow_min_pixels * pixel);
	float energy = (glow_size * glow_size) / (radius * radius);
	float fade = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera);
	glow = srgb(post_top ? post_top_light : cobra_head_light) * (glow_strength * energy * fade * city_lights);
	corner = UV;
	// Pulled toward the camera a little, so the lamp's own head doesn't cut it.
	VERTEX = center * (1.0 - min(radius, 0.5 * distance_to_camera) / length(center)) + vec3(UV * radius, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r2 = dot(corner, corner);
	float falloff = max(1.0 - r2, 0.0);
	ALBEDO = glow * (falloff * falloff * (0.25 + 0.75 * exp(-8.0 * r2)));
}
