shader_type spatial;
// Sponsor banners. Each atlas holds AD rows banners stacked vertically.
// - Smooth (linear + mipmapped) sampling so small text doesn't sparkle as it shrinks,
//   then the 320x240 screen pixelates it like everything else.
// - Samples are kept inside their own banner's row at every mip level, so neighbouring
//   banners in the atlas never bleed in at a distance.
// - Same vertex snapping and per-vertex lighting as the rest of the PS1 look.
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float rows = 4.0;
uniform float max_lod = 3.0;      // don't go blurrier than 1/8 size
uniform vec2 snap_resolution = vec2(320.0, 240.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 grid = snap_resolution * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	float lod = clamp(textureQueryLod(tex, UV).y, 0.0, max_lod);
	vec2 texel = exp2(lod) / vec2(textureSize(tex, 0));
	float row = floor(clamp(UV.y, 0.0, 0.9999) * rows);
	vec2 uv = UV;
	uv.x = clamp(uv.x, texel.x * 0.5, 1.0 - texel.x * 0.5);
	uv.y = clamp(uv.y, row / rows + texel.y * 0.5, (row + 1.0) / rows - texel.y * 0.5);
	ALBEDO = textureLod(tex, uv, lod).rgb;
	ROUGHNESS = 1.0;
}
