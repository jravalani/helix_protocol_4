shader_type canvas_item;

// ─────────────────────────────────────────────────────────────
// glitch.gdshader
// Parallel-world window glitch effect for SpecialTile cells.
// Samples SCREEN_TEXTURE so roads and packets show through.
// All distortion is contained within the cell UV space.
// ─────────────────────────────────────────────────────────────

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Tint color — set per tile type from GDScript
uniform vec4 tint_color : source_color = vec4(0.0, 1.0, 0.53, 1.0);

// Overall opacity — keeps roads/packets readable underneath
uniform float overlay_opacity : hint_range(0.0, 1.0) = 0.55;

// Glitch intensity — animate from GDScript to pulse the effect
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.6;

uniform float speed : hint_range(0.1, 8.0) = 2.5;

// ── Pseudo-random hash ────────────────────────────────────────
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

// ── Main fragment ─────────────────────────────────────────────
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 local_uv = UV;  // 0..1 within this cell

	float t = TIME * speed;
	float intensity = glitch_intensity;

	// ── Scanline block shift ──────────────────────────────────
	// Divide the cell into horizontal bands. Each band randomly
	// shifts its screen UV horizontally — like a VHS tracking error.
	float band_count = 12.0;
	float band = floor(local_uv.y * band_count);
	float band_time = floor(t * 3.0);  // changes a few times per second

	float band_rand = hash(vec2(band, band_time));
	float shift_chance = step(0.65, band_rand);  // ~35% of bands shift at any moment
	float shift_amount = (hash(vec2(band + 0.5, band_time)) - 0.5) * 0.018 * intensity;
	uv.x += shift_amount * shift_chance;

	// ── Chromatic aberration ──────────────────────────────────
	// Separate RGB channels slightly — stronger at edges of cell
	float edge_dist = 2.0 * max(abs(local_uv.x - 0.5), abs(local_uv.y - 0.5));
	float aberration = 0.004 * intensity * (0.5 + edge_dist);

	vec4 col_r = texture(SCREEN_TEXTURE, uv + vec2( aberration, 0.0));
	vec4 col_g = texture(SCREEN_TEXTURE, uv);
	vec4 col_b = texture(SCREEN_TEXTURE, uv + vec2(-aberration, 0.0));

	vec4 screen_sample = vec4(col_r.r, col_g.g, col_b.b, col_g.a);

	// ── Noise flicker ─────────────────────────────────────────
	// Fast per-pixel noise that flickers at ~8fps
	float noise_time = floor(t * 8.0);
	float noise = hash(local_uv * vec2(37.0, 19.0) + vec2(noise_time));
	float noise_mask = step(0.92, noise) * intensity;  // ~8% of pixels flicker

	// Flicker either brightens or darkens
	float flicker_dir = step(0.5, hash(vec2(noise_time, 1.0))) * 2.0 - 1.0;
	screen_sample.rgb += noise_mask * flicker_dir * 0.35;

	// ── Horizontal tear lines ─────────────────────────────────
	// Occasional single-pixel bright lines crossing the cell
	float tear_time = floor(t * 2.0);
	float tear_y = hash1(tear_time);
	float tear_width = 0.015;
	float tear_mask = step(1.0 - tear_width, abs(local_uv.y - tear_y) < tear_width
		? 0.0 : 1.0) * intensity;
	// Simpler: bright line near tear_y
	float tear = smoothstep(tear_width, 0.0, abs(local_uv.y - tear_y)) * intensity * 0.6;
	screen_sample.rgb += tint_color.rgb * tear;

	// ── Tint overlay ──────────────────────────────────────────
	// Blend the tint color on top of the distorted screen sample
	// so the cell reads as "belonging" to this tile type
	float tint_strength = 0.28 * intensity;
	screen_sample.rgb = mix(screen_sample.rgb, tint_color.rgb, tint_strength);

	// ── Vignette within cell ──────────────────────────────────
	// Slightly darken the edges of each cell to frame the effect
	float vignette = 1.0 - smoothstep(0.35, 0.5, edge_dist) * 0.5;
	screen_sample.rgb *= vignette;

	// ── Final alpha ───────────────────────────────────────────
	// overlay_opacity controls how much the effect sits over the world
	// Roads and packets remain visible underneath
	COLOR = vec4(screen_sample.rgb, overlay_opacity);
}
