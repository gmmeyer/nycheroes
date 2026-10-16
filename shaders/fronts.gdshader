// The small parts of rowhouse fronts (tools/citygen/fronts.py): stoops'
// iron railings and yards' iron fences (pickets and rails painted on a
// panel, the gaps between them cut out, so the street shows through), iron
// newel and fence posts, brick fence posts under stone pyramid caps, shrubs,
// and striped metal door awnings. They come in each near tile's fronts
// surface (CityTileDecoder.SURFACE_FRONTS), so building.gdshader, the big
// one, doesn't grow for them (see "Shader compile time" in docs/ROADMAP.md);
// this one is small, and the panels are drawn from both sides.
//
// Per vertex (see fronts.py):
//   UV    railings and fences: (m along, m above their foot); posts and
//         shrubs: (m around, m above the ground); awnings: (m across, m up
//         the slope from the front edge, the valance below 0, the sides
//         below -0.3)
//   UV2.x part + 16 * variant (a railing's height in dm, an awning's color)
//   UV2.y the house's seed (0..0.999)
shader_type spatial;
render_mode ambient_light_disabled, cull_disabled;

#include "res://shaders/patterns.gdshaderinc"
#include "res://shaders/toon.gdshaderinc"

// Parts, as fronts.py numbers them.
const int IRON_PANEL = 0;
const int IRON = 1;
const int POST = 2;
const int SHRUB = 3;
const int AWNING = 4;
const float POST_HEIGHT = 1.15;  // fronts.py's: where a brick post's cap starts

// Colors, in sRGB.
const vec3 IRON_PAINT = vec3(0.11, 0.12, 0.12);
const vec3 BUFF_POST = vec3(0.70, 0.61, 0.49);
const vec3 BROWN_POST = vec3(0.49, 0.38, 0.33);
const vec3 RED_POST = vec3(0.57, 0.42, 0.38);
const vec3 MORTAR = vec3(0.78, 0.77, 0.73);
const vec3 CAP_STONE = vec3(0.86, 0.85, 0.81);
const vec3 LEAF_DARK = vec3(0.17, 0.25, 0.14);
const vec3 LEAF_LIGHT = vec3(0.32, 0.43, 0.22);
const vec3 AWNING_WHITE = vec3(0.90, 0.90, 0.86);
const vec3 AWNING_GREEN = vec3(0.22, 0.40, 0.29);
const vec3 AWNING_RED = vec3(0.60, 0.20, 0.17);
const vec3 AWNING_BROWN = vec3(0.42, 0.29, 0.20);
const vec3 AWNING_BLUE = vec3(0.22, 0.30, 0.46);

// Low things by the street sit in its shade (as building.gdshader's walls' feet).
uniform float canyon_occlusion : hint_range(0.0, 1.0) = 0.85;

// UV2 decoded in the vertex shader: (part + 16 * variant, seed); one value per face.
varying flat vec2 front_data;

void vertex() {
	front_data = vec2(floor(UV2.x + 0.5), UV2.y);
}

void fragment() {
	int code = int(front_data.x + 0.5);
	int part = code % 16;
	int variant = code / 16;
	float seed = front_data.y;
	vec2 p = UV;
	vec2 fp = max(fwidth(UV), vec2(1e-4));
	float pixel = max(fp.x, fp.y);
	vec3 color = srgb(IRON_PAINT);
	if (part == IRON_PANEL) {
		// Pickets every 12 cm between a bottom rail and a top rail; the
		// rest is cut out. Far off, the pickets thin out to nothing.
		float height = float(variant) * 0.1;
		float pickets = centered_stripes(p.x / 0.12, 0.22, fp.x / 0.12);
		float rails = max(band(p.y, -1.0, 0.045, fp.y), band(p.y, height - 0.055, 1e4, fp.y));
		if (max(pickets, rails) < 0.5) {
			discard;
		}
		color *= 1.0 + 0.25 * band(p.y, height - 0.055, 1e4, fp.y);
	} else if (part == POST) {
		// Brick (buff, brown or red by house) under a white stone cap.
		float r = hash(vec2(seed * 977.0, 5.0));
		vec3 brick = srgb(r < 0.45 ? BUFF_POST : (r < 0.75 ? BROWN_POST : RED_POST));
		float row = p.y / 0.076;
		float joints = max(stripes(row, 0.16, fp.y / 0.076),
				stripes(p.x / 0.21 + 0.5 * mod(floor(row), 2.0), 0.08, fp.x / 0.21) * visible(0.076, pixel));
		color = mix(brick, srgb(MORTAR), joints * 0.4);
		color = mix(color, srgb(CAP_STONE), band(p.y, POST_HEIGHT - 0.08, 1e4, fp.y));
	} else if (part == SHRUB) {
		// Leaves in clumps, lighter on top.
		float leaves = value_noise(p * vec2(4.0, 5.0) + seed * 97.0) * 0.7 + value_noise(p * 11.0) * 0.3;
		color = srgb(mix(LEAF_DARK, LEAF_LIGHT, leaves)) * mix(0.85, 1.1, smoothstep(0.2, 1.2, p.y));
		color *= mix(0.9, 1.1, hash(vec2(seed * 61.0, float(variant))));
	} else if (part == AWNING) {
		// Aluminum in white and a color, in stripes across, ribbed down the
		// slope; a scalloped valance in the color.
		vec3 paint = srgb(variant == 0 ? AWNING_GREEN : (variant == 1 ? AWNING_RED
				: (variant == 2 ? AWNING_BROWN : AWNING_BLUE)));
		float stripe = stripes(p.x / 0.36, 0.5, fp.x / 0.36);
		color = mix(srgb(AWNING_WHITE), paint, stripe);
		color *= 1.0 - 0.15 * stripes(p.y / 0.07, 0.3, fp.y / 0.07) * visible(0.07, pixel) * step(0.0, p.y);
		float scallop = length(vec2((fract(p.x / 0.2) - 0.5) * 0.2, min(p.y + 0.1, 0.0)));
		if (p.y < 0.0 && p.y > -0.2 && scallop > 0.1) {
			discard;
		}
		color = mix(color, paint, step(p.y, 0.0));
	}

	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = toon_night_albedo(color);
	EMISSION = ALBEDO * toon_ambient(world_normal, canyon_occlusion);
	toon_glint = 0.0;
	if (city_lights > 0.0) {
		// Street lights on whatever stands near them.
		vec3 scene_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		EMISSION += ALBEDO * street_light_at(scene_position.xz, length(VERTEX)) * city_lights;
	}
}
