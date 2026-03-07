shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 10.0) = 3.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Distortion wave
    float wave_x = sin(uv.y * 20.0 + TIME * speed) * strength * 0.008;
    float wave_y = cos(uv.x * 15.0 + TIME * speed * 0.8) * strength * 0.005;
    
    vec2 distorted_uv = uv + vec2(wave_x, wave_y);
    COLOR = texture(SCREEN_TEXTURE, distorted_uv);
}