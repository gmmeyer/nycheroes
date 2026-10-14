// A pool of blood on the ground: a glossy dark red blob with a wavy edge.
// Drawn on a flat 1x1 plane; scale and rotate the instance for variety.
shader_type spatial;

uniform vec3 color : source_color = vec3(0.28, 0.01, 0.01);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float edge = 0.78 + 0.1 * sin(angle * 5.0) + 0.06 * sin(angle * 11.0 + 1.3) + 0.04 * sin(angle * 17.0 + 4.1);
	if (length(p) > edge) {
		discard;
	}
	ALBEDO = color;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
