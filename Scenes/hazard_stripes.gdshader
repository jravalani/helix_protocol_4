shader_type canvas_item;

uniform vec4 stripe_color : source_color = vec4(1.0, 0.0, 1.0, 1.0); // #ff00ff
uniform float stripe_opacity = 0.18;
uniform float stripe_spacing = 60.0; // pixels
uniform float stripe_width   = 4.0;  // pixels
uniform float angle_degrees  = 45.0;
uniform float speed          = 50.0; // pixels/sec

uniform float ash_opacity    = 0.06; // slight darkening in non-playable area

void fragment() {
    // Screen-space pixels (reliable for ColorRect)
    vec2 screen_px = SCREEN_UV * vec2(1920.0, 1080.0);

    float a = radians(angle_degrees);
    vec2 dir = vec2(cos(a), sin(a));

    float t = dot(screen_px, dir) + TIME * speed;
    float m = mod(t, stripe_spacing);

    float dist = abs(m - stripe_spacing * 0.5);
    float half_w = stripe_width * 0.5;

    float aa = max(fwidth(dist), 1.0);
    float stripe = 1.0 - smoothstep(half_w - aa, half_w + aa, dist);

    // Dark “ash” base + magenta stripes on top
    vec3 base = vec3(0.0); // transparent-ish black
    vec3 ash  = mix(base, vec3(0.06, 0.06, 0.075), ash_opacity);

    vec3 col = mix(ash, stripe_color.rgb, stripe * stripe_opacity);

    // Output with alpha so it overlays nicely
    COLOR = vec4(col, 0.65);
}