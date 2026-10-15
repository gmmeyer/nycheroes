// Stylized ("toon") lighting shared by the city's shaders: a warm sun with a
// soft edge between lit and shaded faces, crisp cast shadows, and a cool sky /
// warm ground ambient in place of the environment's flat ambient (so shadows
// read blue and walls catch a little warm bounce).
//
// Use it in a spatial shader with render_mode ambient_light_disabled, and in
// fragment():
//   EMISSION += ALBEDO * toon_ambient(world_normal, occlusion);
//   toon_glint = 1.0 where the surface is glass (sun glints), else 0.0.
// The sun itself comes through light() below.

// Ambient light from the sky (faces pointing up) and bounced off the ground
// (faces pointing down); walls get the mix.
uniform vec3 ambient_sky : source_color = vec3(0.66, 0.72, 0.86);
uniform vec3 ambient_ground : source_color = vec3(0.85, 0.75, 0.65);
uniform float ambient_energy = 0.75;
// Extra fill on walls (up to this much more at vertical), standing in for
// the light that sunlit streets and facades bounce into the shade.
uniform float ambient_wall_bounce = 0.5;
// Width of the soft edge between sunlit and shaded faces, in N.L units.
uniform float toon_softness : hint_range(0.0, 1.0) = 0.1;
// How much plain Lambert falloff is kept on the sunlit side, so lit faces at
// different angles still differ (0 = every lit face the same).
uniform float toon_lambert : hint_range(0.0, 1.0) = 0.4;
// The shadow map's soft edge is squeezed into this range to crisp it up.
uniform vec2 shadow_edge = vec2(0.2, 0.8);
// Sun glints on glass: strength and tightness.
uniform float glint_strength = 3.0;
uniform float glint_power = 400.0;

varying float toon_glint;

vec3 toon_ambient(vec3 world_normal, float occlusion) {
	vec3 hemisphere = mix(ambient_ground, ambient_sky, world_normal.y * 0.5 + 0.5);
	float bounce = 1.0 + ambient_wall_bounce * (1.0 - abs(world_normal.y));
	return hemisphere * (ambient_energy * occlusion * bounce);
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float lit = smoothstep(-toon_softness, toon_softness, n_dot_l);
	float falloff = mix(1.0, clamp(n_dot_l, 0.0, 1.0), toon_lambert);
	float shadow = smoothstep(shadow_edge.x, shadow_edge.y, ATTENUATION);
	// LIGHT_COLOR carries a factor of PI for physically based models.
	DIFFUSE_LIGHT += LIGHT_COLOR * (lit * falloff * shadow / PI);
	if (toon_glint > 0.0) {
		float highlight = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), glint_power);
		SPECULAR_LIGHT += LIGHT_COLOR * (smoothstep(0.2, 0.6, highlight) * glint_strength * toon_glint * shadow * lit / PI);
	}
}
