// Pedestrians and thugs: the shared mannequin dressed in bands (NpcLook picks
// each one's clothes). From the ground up: shoes, then trousers or a skirt
// (with bare legs or tights below a skirt or shorts), a shirt or coat with
// long or short sleeves, skin on the hands, neck and face, and hair. Thugs
// keep their gang's color on the joints (the mannequin's second surface).
// Per vertex, where it sits in the T-pose the mesh was modeled in (NpcLook
// writes it): UV = (reach out from the middle |x|, height), UV2 = (front-back
// z, 1 on the joints). The Compatibility renderer skins the mesh before this
// shader runs, so VERTEX is already posed; cutting the bands on the rest pose
// keeps the clothes in place in any pose, a ragdoll's too.
shader_type spatial;

uniform vec3 top_color : source_color = vec3(0.2);
uniform vec3 bottom_color : source_color = vec3(0.15, 0.18, 0.28);
// Between a skirt's or shorts' hem and the shoes: bare legs or tights.
uniform vec3 legs_color : source_color = vec3(0.8, 0.6, 0.45);
uniform vec3 shoe_color : source_color = vec3(0.06);
uniform vec3 skin_color : source_color = vec3(0.8, 0.6, 0.45);
uniform vec3 hair_color : source_color = vec3(0.06);
// The joints in this color where its alpha is 1 (thugs' gang color).
uniform vec4 joint_color : source_color = vec4(0.0);
// Rest-pose heights (m) of the top's hem, the bottom's hem and the shoes' top,
// and how far out along the arm the sleeves reach (the hands start at 0.72).
uniform vec4 cuts = vec4(0.95, 0.1, 0.1, 0.7);
// Hairline height at the forehead and at the nape; above 1.83 m, bald.
uniform vec2 hairline = vec2(1.76, 1.62);

void fragment() {
	float reach = UV.x;
	float height = UV.y;
	vec3 color = height > cuts.z ? legs_color : shoe_color;
	color = height > cuts.y ? bottom_color : color;
	color = height > cuts.x ? top_color : color;
	color = reach > cuts.w ? skin_color : color;
	// The collar rises out toward the shoulders.
	color = height > 1.5 + 0.4 * max(reach - 0.06, 0.0) ? skin_color : color;
	// The hairline runs from the nape up over the ears (z about 0) to the forehead.
	color = height > mix(hairline.y, hairline.x, smoothstep(-0.08, 0.05, UV2.x)) ? hair_color : color;
	color = UV2.y * joint_color.a > 0.5 ? joint_color.rgb : color;
	ALBEDO = color;
	ROUGHNESS = 0.65;
}
