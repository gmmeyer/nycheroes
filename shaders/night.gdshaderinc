// Time of day and the city's own lights, for the city's shaders
// (toon.gdshaderinc includes it). Project-wide shader globals (project.godot),
// set by TimeOfDay (scripts/world/time_of_day.gd) and StreetLightMap:
//   night        0 by day .. 1 at night, when the moon and the night sky light
//                the city
//   dusk         0..1, the warmth of a low sun at dusk and dawn
//   city_lights  0..1, how far street lights, windows and signs are on (they
//                come on around sunset)
//   clock_hours  the clock (0..24): who's home, who's still at the office
// By day all three amounts are 0, and every shader then skips its night code,
// so the day looks exactly as it did before there was a night.
//
// Street lights' pools of light on the ground come from a map around the
// camera (StreetLightMap): the pools drawn from above, 2 m a pixel. Ground,
// paint, the feet of walls and tree crowns look it up at their scene x/z with
// street_light_at(), so whatever stands near a lamp is lit by it, without a
// real light or a decal per lamp.

global uniform float night;
global uniform float dusk;
global uniform float city_lights;
global uniform float clock_hours;
global uniform sampler2D street_light_map : filter_linear;
// The map's square in scene x/z: (left, top, width, height); width 0 until
// it's first drawn.
global uniform vec4 street_light_rect;

// The map holds light in 0..1; it's scaled up by this.
uniform float street_light_strength = 4.0;
// It only holds the near tiles' lamps, so it fades out between these
// distances from the camera (m); the ground shader puts the lamps' average on
// streets further out (street_light_far()).
uniform vec2 street_light_range = vec2(420.0, 650.0);

// Street lights' light (linear) at scene position xz, `distance_to_camera`
// meters from the camera.
vec3 street_light_at(vec2 xz, float distance_to_camera) {
	if (street_light_rect.z <= 0.0) {
		return vec3(0.0);
	}
	vec2 uv = (xz - street_light_rect.xy) / street_light_rect.zw;
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float near = 1.0 - smoothstep(street_light_range.x, street_light_range.y, distance_to_camera);
	return textureLod(street_light_map, uv, 0.0).rgb * (street_light_strength * near * inside.x * inside.y);
}

// How much of the lamps' average light streets get instead of the map, at
// this distance from the camera (0 near, 1 far).
float street_light_far(float distance_to_camera) {
	return smoothstep(street_light_range.x, street_light_range.y, distance_to_camera);
}
