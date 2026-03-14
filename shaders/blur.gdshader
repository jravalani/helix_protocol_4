shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float blur_amount: hint_range(0.0, 20.0) = 10.0;

void fragment(){
	vec2 pixel_size = 1.0 / vec2(textureSize(SCREEN_TEXTURE, 0));
	vec4 color = vec4(0.0);
	
	float samples = 0.0;
	int range = int(blur_amount * 8.0); // Increased multiplier
	
	for(int x = -range; x <= range; x++){
		for(int y = -range; y <= range; y++){
			vec2 offset = vec2(float(x), float(y)) * pixel_size;
			color += texture(SCREEN_TEXTURE, SCREEN_UV + offset);
			samples += 1.0;
		}
	}
	
	COLOR = color / samples;
}