// Expanding ring of a ground slam, drawn on a flat 1x1 plane that the effect
// scales up while fading `strength` to zero.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec3 color : source_color = vec3(0.95, 0.9, 0.8);
uniform float strength = 1.0;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float ring = smoothstep(0.62, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = color;
	ALPHA = ring * strength * 0.8;
}
