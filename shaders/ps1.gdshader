shader_type spatial;
// PS1-style material: vertex-coloured, Gouraud (per-vertex) lit, and vertices snapped
// to the low-res pixel grid so geometry jitters ("wobbles") as the camera moves.
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform vec4 albedo : source_color = vec4(1.0);  // multiplies the vertex colour (for imported models)
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 grid = snap_resolution * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb) * albedo.rgb;
	ROUGHNESS = 1.0;
	EMISSION = emission_color * emission_energy;
}
