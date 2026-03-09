
extends CanvasLayer

signal transition_finished

const PANEL_SLIDE_IN_TIME  := 0.40  # how fast panels slam shut
const PANEL_SLIDE_OUT_TIME := 0.50  # how fast panels open
const BEAM_FADE_IN_TIME    := 0.10  # beam appears
const BEAM_HOLD_TIME       := 0.20  # beam stays visible
const BEAM_FADE_OUT_TIME   := 0.12  # beam disappears

var _top_panel    : ColorRect
var _bottom_panel : ColorRect
var _beam_glow    : ColorRect
var _beam_core    : ColorRect
var _screen_flash : ColorRect

var _beam_glow_mat : ShaderMaterial
var _beam_core_mat : ShaderMaterial

var _tween        : Tween
var _transitioning : bool = false

var _W : float
var _H : float

func _ready() -> void:
	layer        = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_W = float(ProjectSettings.get_setting("display/window/size/viewport_width",  1920))
	_H = float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	_build_ui()
	_hide_all()

func _build_ui() -> void:
	_screen_flash          = ColorRect.new()
	_screen_flash.size     = Vector2(_W, _H)
	_screen_flash.position = Vector2.ZERO
	_screen_flash.color    = Color(0.45, 0.0, 0.85, 0.0)
	add_child(_screen_flash)

	_top_panel          = ColorRect.new()
	_top_panel.size     = Vector2(_W, _H * 0.5 + 8)
	_top_panel.position = Vector2(0, -_H * 0.5 - 8)
	_top_panel.color    = Color(0.055, 0.055, 0.072, 1.0)
	var top_mat         = ShaderMaterial.new()
	top_mat.shader      = _make_panel_shader(false)
	_top_panel.material = top_mat
	add_child(_top_panel)

	_bottom_panel          = ColorRect.new()
	_bottom_panel.size     = Vector2(_W, _H * 0.5 + 8)
	_bottom_panel.position = Vector2(0, _H)
	_bottom_panel.color    = Color(0.055, 0.055, 0.072, 1.0)
	var bot_mat            = ShaderMaterial.new()
	bot_mat.shader         = _make_panel_shader(true)
	_bottom_panel.material = bot_mat
	add_child(_bottom_panel)

	var glow_h            = 120.0
	_beam_glow            = ColorRect.new()
	_beam_glow.size       = Vector2(_W, glow_h)
	_beam_glow.position   = Vector2(0, _H * 0.5 - glow_h * 0.5)
	_beam_glow_mat        = ShaderMaterial.new()
	_beam_glow_mat.shader = _make_glow_shader()
	_beam_glow_mat.set_shader_parameter("beam_color", Color(0.55, 0.0, 1.0, 1.0))
	_beam_glow_mat.set_shader_parameter("intensity",  0.0)
	_beam_glow.material   = _beam_glow_mat
	add_child(_beam_glow)

	var core_h            = 8.0
	_beam_core            = ColorRect.new()
	_beam_core.size       = Vector2(_W, core_h)
	_beam_core.position   = Vector2(0, _H * 0.5 - core_h * 0.5)
	_beam_core_mat        = ShaderMaterial.new()
	_beam_core_mat.shader = _make_core_shader()
	_beam_core_mat.set_shader_parameter("beam_color", Color(0.92, 0.60, 1.0, 1.0))
	_beam_core_mat.set_shader_parameter("intensity",  0.0)
	_beam_core.material   = _beam_core_mat
	add_child(_beam_core)

func transition_to(scene_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_show_all()
	await _slide_in()
	await _flash_beam()
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await _flash_beam()
	await _slide_out()
	_hide_all()
	_reset()
	_transitioning = false
	emit_signal("transition_finished")

func _slide_in() -> void:
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_top_panel,    "position:y", 0.0,      PANEL_SLIDE_IN_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tween.tween_property(_bottom_panel, "position:y", _H * 0.5, PANEL_SLIDE_IN_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	await _tween.finished

func _slide_out() -> void:
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_top_panel,    "position:y", -_H * 0.5 - 8, PANEL_SLIDE_OUT_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bottom_panel, "position:y", _H,             PANEL_SLIDE_OUT_TIME)\
		  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await _tween.finished

func _flash_beam() -> void:
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

func _show_all() -> void:
	for n in [_screen_flash, _top_panel, _bottom_panel, _beam_glow, _beam_core]:
		n.visible = true

func _hide_all() -> void:
	for n in [_screen_flash, _top_panel, _bottom_panel, _beam_glow, _beam_core]:
		n.visible = false

func _reset() -> void:
	_top_panel.position.y    = -_H * 0.5 - 8
	_bottom_panel.position.y = _H
	_beam_glow_mat.set_shader_parameter("intensity", 0.0)
	_beam_core_mat.set_shader_parameter("intensity", 0.0)
	_screen_flash.color.a    = 0.0

func _make_panel_shader(flip: bool) -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	float seam_uv = %s;
	float diag = mod((UV.x - UV.y) * 36.0, 1.0);
	float scan  = step(0.78, diag) * 0.022;
	vec3 col = vec3(0.050, 0.052, 0.070);
	col += vec3(0.010) * seam_uv;
	float seam_glow = pow(seam_uv, 3.5);
	col += vec3(0.42, 0.02, 0.68) * seam_glow;
	float bevel = step(0.997, mod(UV.x * 4.0, 1.0)) * 0.035;
	col -= bevel;
	float cx = smoothstep(0.0, 0.025, UV.x) * smoothstep(1.0, 0.975, UV.x);
	col -= scan;
	COLOR = vec4(col * cx, 1.0);
}
""" % ("uv.y" if flip else "1.0 - uv.y")
	return s

func _make_glow_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform vec4  beam_color : source_color = vec4(0.55, 0.0, 1.0, 1.0);
uniform float intensity  : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d     = abs(UV.y - 0.5) * 2.0;
	float halo  = exp(-d * d * 5.0);
	float ripple = 0.93 + 0.07 * sin(UV.x * 55.0 + TIME * 9.0);
	vec3  col   = beam_color.rgb * halo * 3.0 * ripple;
	float alpha = halo * intensity * 0.85;
	COLOR = vec4(col, alpha);
}
"""
	return s

func _make_core_shader() -> Shader:
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
	float alpha   = core * intensity;
	COLOR = vec4(col, alpha);
}
"""
	return s
