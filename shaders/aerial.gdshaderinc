// Aerial photo draped over a city tile from above (see CityStreamer), shared
// by the ground and building shaders. The photo covers the tile's square plus
// a margin all round (roofs can overhang the tile); the tile's north-west
// corner is the mesh origin, so tile-local x/z map to UV directly. Each
// shader's vertex() sets aerial_uv = aerial_uv_of(VERTEX).

// Not source_color: for textures made at runtime it doesn't decode sRGB on
// the web (measured), so aerial_albedo() does it, the same everywhere.
// Anisotropic, since the ground is mostly seen at a slant.
uniform sampler2D aerial : filter_linear_mipmap_anisotropic, repeat_disable;
// Meters of ground the photo covers (the tile plus its margins), and the margin.
uniform float aerial_size = 500.0;
uniform float aerial_margin = 0.0;
// 0 draws the procedural colors, 1 the photo; set per tile once its photo loads.
uniform float aerial_strength = 0.0;
// The photo already has sunlight in it, so it's scaled down to work as albedo
// under the game's own sun.
uniform float aerial_brightness = 0.7;
// How much of the shadows baked into the photo to take out, so they don't
// double up with the game's own: 0 leaves them; 0.5 takes out half their
// depth (in stops); 1 would flatten them. Their sky-blue cast goes first.
uniform float aerial_shadow_softening : hint_range(0.0, 1.0) = 0.75;

varying vec2 aerial_uv;

// Linear luminance at and above which a photo pixel counts as sunlit (about
// 45% gray in sRGB), and at and below which it's in deep shadow (about 20%).
const float AERIAL_SUNLIT = 0.17;
const float AERIAL_DEEP_SHADOW = 0.03;
// Keeps the blackest pixels from being blown up into noise.
const float AERIAL_MAX_GAIN = 8.0;

vec2 aerial_uv_of(vec3 vertex) {
	return (vertex.xz + aerial_margin) / aerial_size;
}

// How much of the photo to use: none before it loads, or past the photo's edge
// (the odd big roof or bridge overhangs even the margin; the clamped edge
// would smear).
float aerial_amount(vec2 uv) {
	vec2 inside = step(vec2(-0.001), uv) * step(uv, vec2(1.001));
	return aerial_strength * inside.x * inside.y;
}

// The photo's color here as albedo, shadows softened. Call it outside any
// branch on per-pixel values, so mipmapping gets good derivatives.
vec3 aerial_albedo(vec2 uv) {
	if (aerial_strength <= 0.0) {
		return vec3(0.0);
	}
	vec3 photo = pow(texture(aerial, uv).rgb, vec3(2.2));
	float luminance = max(dot(photo, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
	// Shadows are lit by the blue sky alone, and brightened they'd look painted
	// blue, so they lose their color (it's mostly the sky's anyway).
	float shadow = 1.0 - smoothstep(AERIAL_DEEP_SHADOW, AERIAL_SUNLIT, luminance);
	photo = mix(photo, vec3(luminance), shadow * min(2.0 * aerial_shadow_softening, 1.0));
	// Brightens what's below sunlit by a power curve, compressing shadow depth.
	float gain = pow(AERIAL_SUNLIT / min(luminance, AERIAL_SUNLIT), aerial_shadow_softening);
	return photo * min(gain, AERIAL_MAX_GAIN) * aerial_brightness;
}
