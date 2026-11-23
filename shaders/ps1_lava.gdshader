shader_type spatial;
// Molten lava for the volcano level: unlit, slowly churning, banded into a few hot colours.
render_mode unshaded, cull_disabled, specular_disabled;

uniform vec2 snap_resolution = vec2(320.0, 240.0);

varying vec2 world_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 grid = snap_resolution * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	// chunky texels, so it matches the 64px textures everywhere else
	vec2 p = floor(world_xz * 2.0) / 2.0;
	vec2 flow = vec2(0.0, -TIME * 0.55);
	float n = value_noise(p * 0.11 + flow);
	n = n * 0.6 + value_noise(p * 0.27 - flow * 1.6 + n * 1.8) * 0.4;
	vec3 col = vec3(0.32, 0.02, 0.02);
	if (n > 0.36) col = vec3(0.72, 0.08, 0.02);
	if (n > 0.48) col = vec3(1.0, 0.3, 0.02);
	if (n > 0.6) col = vec3(1.0, 0.68, 0.08);
	if (n > 0.72) col = vec3(1.0, 0.95, 0.55);
	ALBEDO = col;
}
