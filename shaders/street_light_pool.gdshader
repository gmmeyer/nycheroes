// A street light's pool of light on the ground, drawn from above into the
// street light map (scripts/world/street_light_map.gd) that the city's
// shaders look up at night. Additive, so overlapping pools add up. Per
// instance (a MultiMesh 2D per near tile, see CityProps): the transform moves
// the quad (PropMeshes.light_pool(), corners -1..1) to the lamp's foot, in
// world meters (x east, y south); INSTANCE_CUSTOM = (yaw radians, arm length
// m, pole height m, style: 0 cobra-head, 1 post-top).
// The pool is centered under the lamp's head, out over the street on the arm,
// and wider for taller poles; brightest under the lamp, soft to its edge.
// Colors are linear light, as the map holds them (0..1 each; the shaders
// scale it by street_light_strength).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec3 cobra_head_pool = vec3(0.32, 0.18, 0.07);
uniform vec3 post_top_pool = vec3(0.30, 0.15, 0.05);
// A pool's radius: this many meters per meter of pole height, plus this.
uniform float reach_per_height = 1.25;
uniform float reach = 1.5;

varying vec2 corner;
varying vec3 light;

void vertex() {
	float yaw = INSTANCE_CUSTOM.x;
	float arm = INSTANCE_CUSTOM.y;
	float height = INSTANCE_CUSTOM.z;
	corner = VERTEX;
	VERTEX = VERTEX * (height * reach_per_height + reach) + vec2(sin(yaw), cos(yaw)) * arm;
	light = INSTANCE_CUSTOM.w > 0.5 ? post_top_pool : cobra_head_pool;
}

void fragment() {
	float r2 = dot(corner, corner);
	float falloff = max(1.0 - r2, 0.0);
	COLOR = vec4(light * (falloff * falloff * (0.45 + 0.55 * exp(-5.0 * r2))), 1.0);
}
