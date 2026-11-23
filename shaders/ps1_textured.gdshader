shader_type spatial;
// PS1-style textured material (used for the sponsor banners): nearest-filtered texture,
// per-vertex lighting and vertex snapping to the 320x240 grid.
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform sampler2D tex : source_color, filter_nearest_mipmap;
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
	ALBEDO = texture(tex, UV).rgb;
	ROUGHNESS = 1.0;
}
