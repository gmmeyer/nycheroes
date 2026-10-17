shader_type spatial;
render_mode cull_disabled;
uniform vec4 cape_color : source_color;
uniform vec4 trim_color : source_color;
uniform float motion = 0.0;
void vertex() {
 float tail = UV.y * UV.y;
 VERTEX.z -= tail * (0.06 * sin(TIME * 3.4 + UV.y * 5.0 + UV.x * 2.0) + motion * 0.55);
 VERTEX.x += tail * 0.025 * sin(TIME * 2.1 + UV.y * 3.0);
}
void fragment() {
 float border = step(0.955, UV.y) + step(UV.x, 0.035) + step(0.965, UV.x);
 ALBEDO = mix(cape_color.rgb, trim_color.rgb, min(border, 1.0));
 ROUGHNESS = 0.88;
}
