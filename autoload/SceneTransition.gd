extends CanvasLayer

signal transition_finished

# ── Beam transition timing ────────────────────────────────────────────────────
const PANEL_SLIDE_IN_TIME  := 0.40
const PANEL_SLIDE_OUT_TIME := 0.50
const BEAM_FADE_IN_TIME    := 0.10
const BEAM_HOLD_TIME       := 0.20
const BEAM_FADE_OUT_TIME   := 0.12

# ── Fade transition timing ────────────────────────────────────────────────────
const FADE_OUT_TIME        := 0.55
const FADE_HOLD_TIME       := 0.10
const FADE_IN_TIME         := 0.65

# ── Launch reveal timing ──────────────────────────────────────────────────────
const LAUNCH_HOLD_TIME     := 0.40   # black hold before fade starts
const LAUNCH_FADE_IN_TIME  := 1.20   # gentle fade into menu

# ── Palette ───────────────────────────────────────────────────────────────────
const C_PANEL := Color(0.055, 0.055, 0.072, 1.0)
const C_FLASH := Color(0.45,  0.00,  0.85,  0.00)

# ── Shared nodes ──────────────────────────────────────────────────────────────
var _overlay      : ColorRect
var _overlay_mat  : ShaderMaterial

# ── Beam nodes ────────────────────────────────────────────────────────────────
var _top          : ColorRect
var _bot          : ColorRect
var _beam_glow    : ColorRect
var _beam_core    : ColorRect
var _screen_flash : ColorRect
var _beam_glow_mat : ShaderMaterial
var _beam_core_mat : ShaderMaterial

# ── Launch nodes ──────────────────────────────────────────────────────────────
var _launch_bg    : ColorRect

var _tween        : Tween
var _W : float
var _H : float
var _transitioning := false

# ═════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	layer        = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_W = float(ProjectSettings.get_setting("display/window/size/viewport_width",  1920))
	_H = float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	_build_shared()
	_build_beam_nodes()
	_build_launch_nodes()
	_hide_all()

# ═══════════════════════ PUBLIC API ══════════════════════════════════════════

func transition_to(scene_path: String, type: String = "beam") -> void:
	if _transitioning:
		return
	_transitioning = true
	match type:
		"beam":
			await _transition_beam(scene_path)
		"fade":
			await _transition_fade(scene_path)
		_:
			await _transition_beam(scene_path)
	_transitioning = false
	emit_signal("transition_finished")

func launch_reveal() -> void:
	if _transitioning:
		return
	_transitioning = true
	await _do_launch_reveal()
	_transitioning = false
	emit_signal("transition_finished")

func cover() -> void:
	_overlay.visible = true
	_overlay.color.a = 1.0

func uncover() -> void:
	var t := create_tween()
	t.tween_property(_overlay, "color:a", 0.0, FADE_IN_TIME)\
	 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	_overlay.visible = false

# ═══════════════════════ BEAM TRANSITION ═════════════════════════════════════
func _transition_beam(scene_path: String) -> void:
	_show_beam_nodes()
	await _beam_slide_in()
	await _beam_flash()
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await _beam_flash()
	await _beam_slide_out()
	_hide_all()
	_reset_beam()

func _beam_slide_in() -> void:
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_top, "position:y", 0.0,      PANEL_SLIDE_IN_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tween.tween_property(_bot, "position:y", _H * 0.5, PANEL_SLIDE_IN_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	await _tween.finished

func _beam_slide_out() -> void:
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_top, "position:y", -_H * 0.5 - 8, PANEL_SLIDE_OUT_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bot, "position:y", _H,             PANEL_SLIDE_OUT_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await _tween.finished

func _beam_flash() -> void:
	var t_in := create_tween().set_parallel(true)
	t_in.tween_method(func(v): _beam_glow_mat.set_shader_parameter("intensity", v),
					  0.0, 1.0, BEAM_FADE_IN_TIME)
	t_in.tween_method(func(v): _beam_core_mat.set_shader_parameter("intensity", v),
					  0.0, 1.0, BEAM_FADE_IN_TIME)
	t_in.tween_property(_screen_flash, "color:a", 0.25, BEAM_FADE_IN_TIME)
	await t_in.finished
	await get_tree().create_timer(BEAM_HOLD_TIME).timeout
	var t_out := create_tween().set_parallel(true)
	t_out.tween_method(func(v): _beam_glow_mat.set_shader_parameter("intensity", v),
					   1.0, 0.0, BEAM_FADE_OUT_TIME)
	t_out.tween_method(func(v): _beam_core_mat.set_shader_parameter("intensity", v),
					   1.0, 0.0, BEAM_FADE_OUT_TIME)
	t_out.tween_property(_screen_flash, "color:a", 0.0, BEAM_FADE_OUT_TIME)
	await t_out.finished

# ═══════════════════════ FADE TRANSITION ═════════════════════════════════════
func _transition_fade(scene_path: String) -> void:
	_overlay.visible = true
	_overlay_mat.set_shader_parameter("progress", 0.0)
	var t_out := create_tween()
	t_out.tween_method(
		func(v : float): _overlay_mat.set_shader_parameter("progress", v),
		0.0, 1.0, FADE_OUT_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t_out.finished
	await get_tree().create_timer(FADE_HOLD_TIME).timeout
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	var t_in := create_tween()
	t_in.tween_method(
		func(v : float): _overlay_mat.set_shader_parameter("progress", v),
		1.0, 0.0, FADE_IN_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t_in.finished
	_overlay.visible = false
	_overlay_mat.set_shader_parameter("progress", 0.0)

# ═══════════════════════ LAUNCH REVEAL ═══════════════════════════════════════
## Pure clean fade — black hold then smooth dissolve into menu.
## Beam is reserved for in-game transitions only.
func _do_launch_reveal() -> void:
	_launch_bg.visible = true
	_launch_bg.color.a = 1.0

	# Short hold — game feels intentional, not rushed
	await get_tree().create_timer(LAUNCH_HOLD_TIME).timeout

	# Smooth fade out — menu gently appears from black
	var t := create_tween()
	t.tween_property(_launch_bg, "color:a", 0.0, LAUNCH_FADE_IN_TIME)\
	 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished

	_launch_bg.visible = false

# ═══════════════════════ NODE BUILDERS ═══════════════════════════════════════
func _build_shared() -> void:
	_overlay         = ColorRect.new()
	_overlay.size    = Vector2(_W, _H)
	_overlay.color   = Color(0.0, 0.0, 0.0, 0.0)
	_overlay_mat     = ShaderMaterial.new()
	_overlay_mat.shader = _shader_fade_overlay()
	_overlay_mat.set_shader_parameter("progress", 0.0)
	_overlay.material = _overlay_mat
	add_child(_overlay)

func _build_beam_nodes() -> void:
	_screen_flash       = ColorRect.new()
	_screen_flash.size  = Vector2(_W, _H)
	_screen_flash.color = C_FLASH
	add_child(_screen_flash)

	_top           = ColorRect.new()
	_top.size      = Vector2(_W, _H * 0.5 + 8)
	_top.position  = Vector2(0, -_H * 0.5 - 8)
	_top.color     = C_PANEL
	var top_mat    = ShaderMaterial.new()
	top_mat.shader = _shader_panel(false)
	_top.material  = top_mat
	add_child(_top)

	_bot           = ColorRect.new()
	_bot.size      = Vector2(_W, _H * 0.5 + 8)
	_bot.position  = Vector2(0, _H)
	_bot.color     = C_PANEL
	var bot_mat    = ShaderMaterial.new()
	bot_mat.shader = _shader_panel(true)
	_bot.material  = bot_mat
	add_child(_bot)

	var glow_h         := 120.0
	_beam_glow          = ColorRect.new()
	_beam_glow.size     = Vector2(_W, glow_h)
	_beam_glow.position = Vector2(0, _H * 0.5 - glow_h * 0.5)
	_beam_glow_mat      = ShaderMaterial.new()
	_beam_glow_mat.shader = _shader_beam_glow()
	_beam_glow_mat.set_shader_parameter("beam_color", Color(0.55, 0.0, 1.0, 1.0))
	_beam_glow_mat.set_shader_parameter("intensity",  0.0)
	_beam_glow.material = _beam_glow_mat
	add_child(_beam_glow)

	var core_h         := 8.0
	_beam_core          = ColorRect.new()
	_beam_core.size     = Vector2(_W, core_h)
	_beam_core.position = Vector2(0, _H * 0.5 - core_h * 0.5)
	_beam_core_mat      = ShaderMaterial.new()
	_beam_core_mat.shader = _shader_beam_core()
	_beam_core_mat.set_shader_parameter("beam_color", Color(0.92, 0.60, 1.0, 1.0))
	_beam_core_mat.set_shader_parameter("intensity",  0.0)
	_beam_core.material = _beam_core_mat
	add_child(_beam_core)

func _build_launch_nodes() -> void:
	_launch_bg       = ColorRect.new()
	_launch_bg.size  = Vector2(_W, _H)
	_launch_bg.color = Color(0.0, 0.0, 0.0, 1.0)
	add_child(_launch_bg)

# ═══════════════════════ HELPERS ═════════════════════════════════════════════
func _show_beam_nodes() -> void:
	for n : ColorRect in [_screen_flash, _top, _bot, _beam_glow, _beam_core]:
		n.visible = true

func _hide_all() -> void:
	for n : ColorRect in [_overlay, _screen_flash, _top, _bot,
						  _beam_glow, _beam_core, _launch_bg]:
		n.visible = false

func _reset_beam() -> void:
	_top.position.y = -_H * 0.5 - 8
	_bot.position.y =  _H
	_screen_flash.color.a = 0.0
	_beam_glow_mat.set_shader_parameter("intensity", 0.0)
	_beam_core_mat.set_shader_parameter("intensity", 0.0)

# ═══════════════════════ SHADERS ═════════════════════════════════════════════
func _shader_fade_overlay() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float diag = mod((UV.x - UV.y) * 36.0, 1.0);
	float scan = step(0.78, diag) * 0.06 * progress;
	vec3 col = mix(vec3(0.0), vec3(0.04, 0.0, 0.07), progress * 0.6);
	col -= scan;
	COLOR = vec4(col, progress);
}
"""
	return s

func _shader_panel(flip: bool) -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
void fragment() {
	float seam_uv = %s;
	float diag = mod((UV.x - UV.y) * 36.0, 1.0);
	float scan  = step(0.78, diag) * 0.022;
	vec3 col = vec3(0.050, 0.052, 0.070);
	col += vec3(0.010) * seam_uv;
	col += vec3(0.42, 0.02, 0.68) * pow(seam_uv, 3.5);
	col -= step(0.997, mod(UV.x * 4.0, 1.0)) * 0.035 + scan;
	float cx = smoothstep(0.0, 0.025, UV.x) * smoothstep(1.0, 0.975, UV.x);
	COLOR = vec4(col * cx, 1.0);
}
""" % ("UV.y" if flip else "1.0 - UV.y")
	return s

func _shader_beam_glow() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform vec4  beam_color : source_color = vec4(0.55, 0.0, 1.0, 1.0);
uniform float intensity  : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d     = abs(UV.y - 0.5) * 2.0;
	float halo  = exp(-d * d * 5.0);
	float ripple = 0.93 + 0.07 * sin(UV.x * 55.0 + TIME * 9.0);
	COLOR = vec4(beam_color.rgb * halo * 3.0 * ripple, halo * intensity * 0.85);
}
"""
	return s

func _shader_beam_core() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform vec4  beam_color : source_color = vec4(0.92, 0.60, 1.0, 1.0);
uniform float intensity  : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d       = abs(UV.y - 0.5) * 2.0;
	float core    = pow(1.0 - d, 8.0);
	float flicker = 0.88 + 0.12 * sin(UV.x * 130.0 - TIME * 22.0);
	float pulse   = 0.90 + 0.10 * sin(TIME * 35.0);
	vec3  col     = mix(beam_color.rgb, vec3(1.0), core * 0.65) * 4.0 * flicker * pulse;
	COLOR         = vec4(col, core * intensity);
}
"""
	return s
