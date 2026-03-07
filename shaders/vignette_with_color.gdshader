shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Vignette — darkens edges
    vec2 uv = UV - 0.5;
    float vignette = 1.0 - dot(uv, uv) * vignette_strength * 4.0;
    vignette = clamp(vignette, 0.0, 1.0);
    
    // Tint + vignette combined
    vec4 tint = tint_color;
    tint.a *= (1.0 - vignette);
    
    COLOR = tint;
}