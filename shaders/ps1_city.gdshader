shader_type spatial;
// Night-city props (level 5). Unlit, with PS1 vertex snapping.
// Vertex alpha = 1: solid body, which can have procedural lit windows.
// Vertex alpha < 1: a neon tube; the alpha value sets when it pulses.
render_mode unshaded, specular_disabled;

uniform bool windows = false;
uniform vec2 window_cell = vec2(3.0, 4.0);   // metres per window
uniform vec2 snap_resolution = vec2(320.0, 240.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 grid = snap_resolution * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 window_colour(float h) {
	if (h < 0.5) return vec3(1.0, 0.68, 0.28);   // warm room light
	if (h < 0.72) return vec3(0.25, 0.9, 1.0);   // cyan screens
	if (h < 0.9) return vec3(1.0, 0.22, 0.72);   // pink
	return vec3(0.85, 0.88, 1.0);
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (COLOR.a < 0.95) {
		col *= 0.86 + 0.14 * sin(TIME * 2.4 + COLOR.a * 37.0);
	} else if (windows && abs(world_normal.y) < 0.5) {
		bool x_face = abs(world_normal.x) > abs(world_normal.z);
		vec2 coord = vec2(x_face ? world_pos.z : world_pos.x, world_pos.y) / window_cell;
		vec2 cell = floor(coord);
		vec2 f = coord - cell;
		float h = hash(cell + (x_face ? 3.7 : 11.3));
		float lit = step(h, 0.34) * step(0.2, f.x) * step(f.x, 0.8) * step(0.3, f.y) * step(f.y, 0.8);
		// far away the windows are under a pixel, so blend to their average to stop shimmer
		float far = smoothstep(0.3, 0.8, max(fwidth(coord.x), fwidth(coord.y)));
		vec3 near_light = window_colour(hash(cell + 5.1)) * lit;
		col += mix(near_light, vec3(0.12, 0.08, 0.14), far);
	}
	ALBEDO = col;
}
