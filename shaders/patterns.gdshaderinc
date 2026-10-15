// Small pattern helpers shared by the city's shaders: hashes, value noise,
// sRGB colors, and anti-aliased stripes.
//
// The stripe helpers are box-filtered over the pixel's footprint (pass
// fwidth() of the coordinate), so a pattern blurs smoothly into its average
// color as it gets smaller than a pixel instead of shimmering.

// Colors in shader code are written in sRGB, like a color picker; lighting
// needs them linear.
vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

// Pseudo-random 0..1 from a position ("hash without sine", Dave Hoskins):
// no sin() of big numbers, which differs between GPUs.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Integral of a stripe pattern that is 1 on [0, width) of every unit period.
float stripe_integral(float x, float width) {
	return floor(x) * width + min(fract(x), width);
}

// Stripes of `width` (0..1 of the period) starting at x = 0, 1, 2...,
// averaged over a pixel `footprint` wide (all in periods).
float stripes(float x, float width, float footprint) {
	footprint = max(footprint, 1e-4);
	return (stripe_integral(x + 0.5 * footprint, width) - stripe_integral(x - 0.5 * footprint, width)) / footprint;
}

// Stripes `width` wide (0..1 of the period) centered on x = 0, 1, 2...
float centered_stripes(float x, float width, float footprint) {
	return stripes(x + 0.5 * width, width, footprint);
}

// 1 between a and b (a single band, not repeating), anti-aliased.
float band(float x, float a, float b, float footprint) {
	float half_aa = 0.5 * max(footprint, 1e-4);
	return clamp((min(x + half_aa, b) - max(x - half_aa, a)) / (2.0 * half_aa), 0.0, 1.0);
}

// How visible a detail `size` big is when a pixel covers `footprint` (same
// units): fully from about four pixels up, gone below one and a half. Small
// busy details look like noise long before they alias, so they leave early.
float visible(float size, float footprint) {
	return smoothstep(1.5, 4.0, size / max(footprint, 1e-5));
}
