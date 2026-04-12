shader_type canvas_item;

uniform float strength : hint_range(0.0, 20.0) = 0.0;
uniform float speed    : hint_range(0.5, 10.0) = 3.0;

void fragment() {
	vec2 uv = UV;
	float wave = sin(uv.y * 18.0 + TIME * speed) * (strength / 1000.0);
	uv.x += wave;
	COLOR = texture(TEXTURE, uv);
}
