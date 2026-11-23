shader_type canvas_item;
// A slanted band of light that sweeps across text (used on the studio intro).

uniform float shine_x = -100.0;   // band position in the node's local pixels
uniform float width = 9.0;
uniform float strength = 0.9;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR * texture(TEXTURE, UV);
	float d = abs((local_pos.x + local_pos.y * 0.6) - shine_x);
	float band = 1.0 - step(width, d);   // hard-edged, pixel-art friendly
	c.rgb = mix(c.rgb, vec3(1.0), band * strength);
	COLOR = c;
}
