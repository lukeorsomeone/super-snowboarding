shader_type canvas_item;
// Presents the 320x240 game image. Always applies PS1-style 15-bit colour with ordered
// (Bayer) dithering. Optional "old TV" extras, each adjustable (Screen.gd sets them per
// screen mode): plastic bezel, screen curvature, scanlines, aperture-grille mask,
// vignette and glass glare.

uniform sampler2D screen_tex : filter_nearest;
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec2 game_res = vec2(320.0, 240.0);
uniform float color_levels = 32.0;
uniform bool show_bezel = true;
uniform float curvature = 0.07;
uniform float scanline_strength = 0.35;
uniform float mask_strength = 0.07;
uniform float vignette_strength = 1.0;
uniform float glare_strength = 0.035;
uniform vec3 bezel_color : source_color = vec3(0.16, 0.16, 0.18);

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * rect_size;

	// 4:3 screen. With the bezel it's inset and a little above centre (room for the badge);
	// without it, it fills the window height.
	float fill = show_bezel ? 0.84 : 1.0;
	float sh = rect_size.y * fill;
	float sw = sh * 4.0 / 3.0;
	if (sw > rect_size.x * fill) {
		sw = rect_size.x * fill;
		sh = sw * 0.75;
	}
	vec2 center = vec2(rect_size.x * 0.5, rect_size.y * (show_bezel ? 0.465 : 0.5));
	vec2 local = (p - center) / vec2(sw, sh);
	vec2 uv2 = local * 2.0;
	vec2 curved = uv2 * (1.0 + curvature * (uv2.yx * uv2.yx));
	vec2 suv = curved * 0.5 + 0.5;

	float glass = show_bezel
		? rounded_box(p - center, vec2(sw, sh) * 0.5 + 8.0, sh * 0.06)
		: rounded_box(p - center, vec2(sw, sh) * 0.5, 0.0);
	vec3 col;
	if (glass > 0.0) {
		if (show_bezel) {
			// moulded plastic bezel with a bevelled lip around the glass
			col = bezel_color * (1.08 - 0.3 * UV.y);
			float lip = smoothstep(22.0, 0.0, glass);
			float edge = smoothstep(3.0, 0.0, glass);
			col += vec3(0.07) * lip * (local.y < 0.0 ? 0.35 : 1.0);
			col *= 1.0 - 0.6 * edge;
			col += (hash(floor(p)) - 0.5) * 0.02;
		} else {
			col = vec3(0.0);   // plain black bars
		}
	} else if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
		col = show_bezel ? vec3(0.012, 0.014, 0.018) : vec3(0.0);
	} else {
		vec2 px = suv * game_res;
		vec2 cell = floor(px);
		vec3 c = texture(screen_tex, (cell + 0.5) / game_res).rgb;

		// 15-bit colour with 4x4 ordered dithering (the PlayStation look, kept in every mode)
		int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
		float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
		c = clamp(floor(c * (color_levels - 1.0) + threshold + 0.5) / (color_levels - 1.0), 0.0, 1.0);

		// scanlines (brightness boost compensates for the dark gaps)
		float row = fract(px.y);
		float scan = 1.0 - scanline_strength * pow(abs(row - 0.5) * 2.0, 2.0);
		c *= scan * (1.0 + scanline_strength * 0.34);

		// aperture-grille RGB mask
		vec3 mask = vec3(1.0 - mask_strength);
		mask[int(mod(p.x, 3.0))] = 1.0 + mask_strength;
		c *= mask;

		// vignette towards the edges
		vec2 v = suv * (1.0 - suv);
		c *= mix(1.0, clamp(pow(v.x * v.y * 15.0, 0.25), 0.0, 1.0), vignette_strength);
		col = c;
	}
	if (glass <= 0.0) {
		// faint glare on the glass
		col += vec3(glare_strength) * smoothstep(0.7, 0.0, length(uv2 - vec2(-0.55, -0.6)));
	}
	COLOR = vec4(col, 1.0);
}
