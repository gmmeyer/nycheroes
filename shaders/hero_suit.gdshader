shader_type spatial;
render_mode cull_back;
uniform vec4 primary : source_color;
uniform vec4 secondary : source_color;
uniform vec4 accent : source_color;
uniform vec4 skin_color : source_color;
uniform int suit_style = 0;
uniform float boot_height = 0.5;
uniform bool joints = false;
void fragment() {
 // UV2 stores rest-pose x and height, so fabric patterns deform with the skin.
 float x = abs(UV2.x);
 float y = UV2.y;
 vec3 fabric = primary.rgb;
 float stripe = 0.0;
 if (suit_style == 0) {
  stripe = 1.0 - smoothstep(0.025, 0.035, abs(y - (1.20 + x * 0.72)));
  if (y < 1.17 + x * 0.55 && y > 0.94) fabric = secondary.rgb;
 } else if (suit_style == 1) {
  if (x > 0.085) fabric = secondary.rgb;
  stripe = 1.0 - smoothstep(0.012, 0.020, abs(x - 0.09));
 } else if (suit_style == 2) {
  if (x > 0.1) fabric = secondary.rgb;
  stripe = 1.0 - smoothstep(0.018, 0.026, abs(y - 1.2));
 } else if (suit_style == 3 || suit_style == 4) {
  stripe = 1.0 - smoothstep(0.022, 0.032, abs(y - (1.25 + x * 0.45)));
 } else {
  fabric = secondary.rgb;
  stripe = 1.0 - smoothstep(0.018, 0.028, abs(x - 0.075));
 }
 fabric = mix(fabric, accent.rgb, stripe);
 if (joints) fabric *= 0.68;
 bool bare = y > 1.525 || x > 0.75;
 if (suit_style == 2) bare = bare || (x > 0.235 && y > 1.25) || (y < 0.73);
 if (suit_style == 3 || suit_style == 4) {
  bare = bare || y < (0.82 + min(x, 0.19) * 0.88);
  if (suit_style == 3) bare = bare || (x > 0.225 && y > 1.25);
 }
 if (bare) fabric = skin_color.rgb;
 if (y < boot_height) fabric = secondary.rgb;
 if (abs(y - boot_height) < 0.022) fabric = accent.rgb;
 ALBEDO = fabric;
 ROUGHNESS = bare && y >= boot_height ? 0.85 : 0.57;
 METALLIC = suit_style == 5 && !bare ? 0.35 : 0.0;
}
