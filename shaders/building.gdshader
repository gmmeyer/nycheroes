// Buildings from tools/citygen/build_tiles.py.
// UV:  walls = (meters along the wall, meters above the ground); roofs = world x/z.
// UV2: x = facade style (0 brick, 1 prewar stone, 2 postwar concrete, 3 glass),
//      plus 4 on roofs (which may slope, so the normal can't tell);
//      y = per-building random seed in [0, 1).
shader_type spatial;

uniform vec3 roof_color : source_color = vec3(0.36, 0.36, 0.37);
uniform vec3 window_color : source_color = vec3(0.09, 0.12, 0.17);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Colors below are written in sRGB, like a color picker; lighting needs them linear.
vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 wall_color(int style, float seed) {
	if (style == 0) {
		return srgb(mix(vec3(0.55, 0.30, 0.22), vec3(0.68, 0.50, 0.40), fract(seed * 13.7)));
	}
	if (style == 1) {
		return srgb(mix(vec3(0.80, 0.74, 0.62), vec3(0.66, 0.60, 0.52), fract(seed * 7.3)));
	}
	if (style == 2) {
		return srgb(mix(vec3(0.72, 0.71, 0.68), vec3(0.52, 0.53, 0.54), fract(seed * 5.1)));
	}
	return srgb(mix(vec3(0.30, 0.42, 0.50), vec3(0.46, 0.53, 0.58), fract(seed * 3.9)));
}

void fragment() {
	int marked_style = int(UV2.x + 0.5);
	int style = marked_style % 4;
	float seed = UV2.y;

	if (marked_style >= 4) {
		ALBEDO = roof_color * mix(0.75, 1.15, fract(seed * 17.3));
		ROUGHNESS = 0.95;
		SPECULAR = 0.1;
	} else {
		bool glass = style == 3;
		float floor_height = mix(3.3, 4.2, fract(seed * 31.1));
		float bay_width = glass ? mix(1.5, 2.2, fract(seed * 11.3)) : mix(2.4, 3.6, fract(seed * 11.3));
		vec2 pane_size = glass ? vec2(0.9, 0.8) : (style == 0 ? vec2(0.42, 0.55) : vec2(0.5, 0.6));

		vec2 cell = vec2(UV.x / bay_width, UV.y / floor_height);
		vec2 from_center = abs(fract(cell) - 0.5) * 2.0;
		float pane = step(from_center.x, pane_size.x) * step(from_center.y, pane_size.y);
		// When windows shrink to a few pixels, fade to their average to avoid shimmer.
		vec2 cell_pixels = fwidth(cell);
		float detail = 1.0 - smoothstep(0.15, 0.5, max(cell_pixels.x, cell_pixels.y));
		float window = mix(pane_size.x * pane_size.y, pane, detail);

		float pane_shade = mix(0.5, hash(floor(cell) + seed * 91.0), detail);
		vec3 pane_color = window_color * mix(0.7, 1.5, pane_shade);
		ALBEDO = mix(wall_color(style, seed), pane_color, window);
		ROUGHNESS = mix(0.85, 0.2, window);
		SPECULAR = mix(0.1, 0.6, window);
	}
}
