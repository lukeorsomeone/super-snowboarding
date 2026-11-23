shader_type spatial;
// PS1-style terrain: three tiling 64px textures picked per pixel with an ordered dither
// (no smooth blending, like old consoles), per-vertex lighting and vertex snapping.
// Vertex colour carries the surface weights: R = rock, G = groomed track, B = ramp ice.
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform sampler2D offpiste_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D track_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_nearest_mipmap, repeat_enable;
// Optional 4th surface (beach sand along the shore). Vertex alpha = 1 - shore weight, so
// levels that don't use it (alpha 1) are unchanged.
uniform sampler2D shore_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 shore_tint = vec3(1.0);
// Optional textured jumps (sky level: sand) instead of just tinting the kickers.
uniform sampler2D ramp_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_ramp_tex = false;
uniform vec3 ramp_tex_tint = vec3(1.0);
uniform float tile_size = 8.0;          // metres covered by one 64px tile
uniform float rock_tile_size = 11.0;
uniform vec3 ice_tint : source_color = vec3(0.78, 0.9, 1.0);
uniform vec2 snap_resolution = vec2(320.0, 240.0);
// Recolouring for other themes (defaults leave the snow textures untouched).
uniform float desaturate = 0.0;          // 1 = grey out the texture before tinting
uniform vec3 offpiste_tint = vec3(1.0);
uniform vec3 track_tint = vec3(1.0);
uniform vec3 rock_tint = vec3(1.0);
// Moving water (beach level): the track texture scrolls downhill and wobbles a little.
uniform vec2 track_scroll = vec2(0.0);   // tiles per second
uniform float track_wobble = 0.0;

varying vec2 world_xz;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 grid = snap_resolution * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
}

float dither(vec2 uv) {
	// Threshold from a 4x4 Bayer matrix, locked to the texture's own pixel grid.
	vec2 texel = floor(uv * 64.0);
	int idx = int(mod(texel.x, 4.0)) + int(mod(texel.y, 4.0)) * 4;
	return (BAYER[idx] + 0.5) / 16.0;
}

void fragment() {
	vec2 uv = world_xz / tile_size;
	float t = dither(uv);
	vec3 col = texture(offpiste_tex, uv).rgb;
	vec3 tint = offpiste_tint;
	if (1.0 - COLOR.a > t) {
		col = texture(shore_tex, uv).rgb;
		tint = shore_tint;
	}
	if (COLOR.g > t) {
		vec2 tuv = uv + track_scroll * TIME;
		tuv.x += sin(tuv.y * 6.2832 + TIME * 1.7) * track_wobble;
		col = texture(track_tex, tuv).rgb;
		tint = track_tint;
	}
	if (COLOR.r > t) {
		col = texture(rock_tex, world_xz / rock_tile_size).rgb;
		tint = rock_tint;
	}
	bool on_ramp = use_ramp_tex && COLOR.b > t;
	if (on_ramp) {
		col = texture(ramp_tex, uv).rgb;
		tint = ramp_tex_tint;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), on_ramp ? 0.0 : desaturate) * tint;
	if (!use_ramp_tex) {
		col = mix(col, col * ice_tint * 1.1, COLOR.b);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
