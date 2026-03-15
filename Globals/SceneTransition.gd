extends CanvasLayer

signal transition_finished

# ═════════════════════════════════════════════════════════════════════════════
# TRANSITION CONFIG
# Holds all timing and colour values in one place.
# Swap this out (or expose via @export) to change the whole feel of transitions
# without touching any logic below.
# ═════════════════════════════════════════════════════════════════════════════
class TransitionConfig:
	# Beam timings
	var panel_slide_in_time  := 0.40
	var panel_slide_out_time := 0.50
	var beam_fade_in_time    := 0.10
	var beam_hold_time       := 0.20
	var beam_fade_out_time   := 0.12
	# Fade timings
	var fade_out_time        := 0.55
	var fade_hold_time       := 0.10
	var fade_in_time         := 0.65
	# Launch timings
	var launch_hold_time     := 0.40
	var launch_fade_in_time  := 1.20
	# Colours
	var panel_color          := Color(0.055, 0.055, 0.072, 1.0)
	var flash_color          := Color(0.45,  0.00,  0.85,  0.00)
	var beam_glow_color      := Color(0.55,  0.00,  1.00,  1.00)
	var beam_core_color      := Color(0.92,  0.60,  1.00,  1.00)


# ═════════════════════════════════════════════════════════════════════════════
# TRANSITION TYPE ENUM
# Use SceneTransition.Type.BEAM / .FADE instead of raw strings "beam"/"fade".
# Catches typos at parse-time and gives autocomplete at every call site.
# ═════════════════════════════════════════════════════════════════════════════
enum Type { BEAM, FADE, ARMOUR }


# ═════════════════════════════════════════════════════════════════════════════
# BASE TRANSITION
# Every transition effect inherits from this inner class.
# To add a new effect: copy BeamTransition or FadeTransition, override play().
# ═════════════════════════════════════════════════════════════════════════════
class BaseTransition:
	var _owner  : CanvasLayer   # reference back to the singleton node
	var _cfg    : TransitionConfig
	var _W      : float
	var _H      : float

	func _init(owner: CanvasLayer, cfg: TransitionConfig, w: float, h: float) -> void:
		_owner = owner
		_cfg   = cfg
		_W     = w
		_H     = h

	# Override in subclasses. Must change the scene and await all animation.
	func play(scene_path: String) -> void:
		pass


# ─────────────────────────────────────────────────────────────────────────────
# BEAM TRANSITION
# ─────────────────────────────────────────────────────────────────────────────
class BeamTransition extends BaseTransition:
	var _top            : ColorRect
	var _bot            : ColorRect
	var _beam_glow      : ColorRect
	var _beam_core      : ColorRect
	var _screen_flash   : ColorRect
	var _beam_glow_mat  : ShaderMaterial
	var _beam_core_mat  : ShaderMaterial
	var _top_beam_mat   : ShaderMaterial
	var _bot_beam_mat   : ShaderMaterial
	var _top_armour_mat : ShaderMaterial
	var _bot_armour_mat : ShaderMaterial
	var _tween          : Tween

	func _init(owner: CanvasLayer, cfg: TransitionConfig, w: float, h: float) -> void:
		super(owner, cfg, w, h)
		_build_nodes()

	# ── Public ────────────────────────────────────────────────────────────────

	## use_armour: false = original dark slate panels, true = gunmetal blast shield
	func play(scene_path: String, use_armour: bool = false) -> void:
		_top.material = _top_armour_mat if use_armour else _top_beam_mat
		_bot.material = _bot_armour_mat if use_armour else _bot_beam_mat
		show_nodes()
		await _slide_in()
		await _flash()
		_owner.get_tree().change_scene_to_file(scene_path)
		await _owner.get_tree().process_frame
		await _owner.get_tree().process_frame
		await _flash()
		await _slide_out()
		hide_nodes()
		_reset()

	func show_nodes() -> void:
		for n : ColorRect in [_screen_flash, _top, _bot, _beam_glow, _beam_core]:
			n.visible = true

	func hide_nodes() -> void:
		for n : ColorRect in [_screen_flash, _top, _bot, _beam_glow, _beam_core]:
			n.visible = false

	# ── Animations ────────────────────────────────────────────────────────────
	func _slide_in() -> void:
		if _tween: _tween.kill()
		_tween = _owner.create_tween().set_parallel(true)
		_tween.tween_property(_top, "position:y", 0.0,       _cfg.panel_slide_in_time)\
			  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		_tween.tween_property(_bot, "position:y", _H * 0.5,  _cfg.panel_slide_in_time)\
			  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		await _tween.finished

	func _slide_out() -> void:
		if _tween: _tween.kill()
		_tween = _owner.create_tween().set_parallel(true)
		_tween.tween_property(_top, "position:y", -_H * 0.5 - 8, _cfg.panel_slide_out_time)\
			  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_bot, "position:y", _H,             _cfg.panel_slide_out_time)\
			  .set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		await _tween.finished

	func _flash() -> void:
		var t_in := _owner.create_tween().set_parallel(true)
		t_in.tween_method(func(v): _beam_glow_mat.set_shader_parameter("intensity", v),
						  0.0, 1.0, _cfg.beam_fade_in_time)
		t_in.tween_method(func(v): _beam_core_mat.set_shader_parameter("intensity", v),
						  0.0, 1.0, _cfg.beam_fade_in_time)
		t_in.tween_property(_screen_flash, "color:a", 0.25, _cfg.beam_fade_in_time)
		await t_in.finished
		await _owner.get_tree().create_timer(_cfg.beam_hold_time).timeout
		var t_out := _owner.create_tween().set_parallel(true)
		t_out.tween_method(func(v): _beam_glow_mat.set_shader_parameter("intensity", v),
						   1.0, 0.0, _cfg.beam_fade_out_time)
		t_out.tween_method(func(v): _beam_core_mat.set_shader_parameter("intensity", v),
						   1.0, 0.0, _cfg.beam_fade_out_time)
		t_out.tween_property(_screen_flash, "color:a", 0.0, _cfg.beam_fade_out_time)
		await t_out.finished

	func _reset() -> void:
		_top.position.y = -_H * 0.5 - 8
		_bot.position.y =  _H
		_screen_flash.color.a = 0.0
		_beam_glow_mat.set_shader_parameter("intensity", 0.0)
		_beam_core_mat.set_shader_parameter("intensity", 0.0)

	# ── Node builder ──────────────────────────────────────────────────────────
	func _build_nodes() -> void:
		_screen_flash       = ColorRect.new()
		_screen_flash.name  = "ScreenFlash"
		_screen_flash.size  = Vector2(_W, _H)
		_screen_flash.color = _cfg.flash_color
		_owner.add_child(_screen_flash)

		# Build both panel material variants upfront — swapped at play() time
		_top_beam_mat        = ShaderMaterial.new()
		_top_beam_mat.shader = _shader_panel_beam(false)
		_bot_beam_mat        = ShaderMaterial.new()
		_bot_beam_mat.shader = _shader_panel_beam(true)
		_top_armour_mat        = ShaderMaterial.new()
		_top_armour_mat.shader = _shader_panel_armour(false)
		_bot_armour_mat        = ShaderMaterial.new()
		_bot_armour_mat.shader = _shader_panel_armour(true)

		_top          = ColorRect.new()
		_top.name     = "BeamPanelTop"
		_top.size     = Vector2(_W, _H * 0.5 + 8)
		_top.position = Vector2(0, -_H * 0.5 - 8)
		_top.material = _top_beam_mat
		_owner.add_child(_top)

		_bot          = ColorRect.new()
		_bot.name     = "BeamPanelBot"
		_bot.size     = Vector2(_W, _H * 0.5 + 8)
		_bot.position = Vector2(0, _H)
		_bot.material = _bot_beam_mat
		_owner.add_child(_bot)

		var glow_h          := 120.0
		_beam_glow           = ColorRect.new()
		_beam_glow.name      = "BeamGlow"
		_beam_glow.size      = Vector2(_W, glow_h)
		_beam_glow.position  = Vector2(0, _H * 0.5 - glow_h * 0.5)
		_beam_glow_mat       = ShaderMaterial.new()
		_beam_glow_mat.shader = _shader_beam_glow()
		_beam_glow_mat.set_shader_parameter("beam_color", _cfg.beam_glow_color)
		_beam_glow_mat.set_shader_parameter("intensity",  0.0)
		_beam_glow.material  = _beam_glow_mat
		_owner.add_child(_beam_glow)

		var core_h          := 8.0
		_beam_core           = ColorRect.new()
		_beam_core.name      = "BeamCore"
		_beam_core.size      = Vector2(_W, core_h)
		_beam_core.position  = Vector2(0, _H * 0.5 - core_h * 0.5)
		_beam_core_mat       = ShaderMaterial.new()
		_beam_core_mat.shader = _shader_beam_core()
		_beam_core_mat.set_shader_parameter("beam_color", _cfg.beam_core_color)
		_beam_core_mat.set_shader_parameter("intensity",  0.0)
		_beam_core.material  = _beam_core_mat
		_owner.add_child(_beam_core)

	# ── Shaders ───────────────────────────────────────────────────────────────

	## Original dark slate panels with purple seam glow
	static func _shader_panel_beam(flip: bool) -> Shader:
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

	## Gunmetal blast shield panels with rivets, spine ridge, and corner brackets
	static func _shader_panel_armour(flip: bool) -> Shader:
		var s := Shader.new()
		s.code = """
shader_type canvas_item;
void fragment() {
	float seam_uv = %s;
	vec2  uv      = UV;

	// Hard left/right edge vignette
	float cx = smoothstep(0.0, 0.008, uv.x) * smoothstep(1.0, 0.992, uv.x);

	// Chamfered corners on inner (seam) edge
	float corner = smoothstep(0.06, 0.0, uv.x) + smoothstep(0.94, 1.0, uv.x);
	if (seam_uv > 1.0 - corner * 0.04) discard;

	// Base gunmetal colour
	vec3 col = vec3(0.110, 0.110, 0.115);

	// Gradient: darker at outer edge, lighter toward seam
	col += vec3(0.018) * seam_uv;
	col -= vec3(0.025) * (1.0 - seam_uv);

	// Horizontal blast shield bands
	col -= step(0.96, mod(uv.y * 5.0, 1.0)) * 0.022;
	col -= mod(floor(uv.y * 5.0), 2.0) * 0.007;

	// Rivet dots — two vertical columns
	float bolt_y = mod(uv.y * 10.0, 1.0);
	float bolt   = (step(abs(uv.x - 0.15), 0.006) + step(abs(uv.x - 0.85), 0.006))
				 * step(0.44, bolt_y) * step(bolt_y, 0.56);
	col += bolt * 0.12;

	// Centre spine ridge
	col += exp(-pow((uv.x - 0.5) / 0.06,  2.0)) * 0.030;
	col += exp(-pow((uv.x - 0.5) / 0.008, 2.0)) * 0.055;

	// Corner bracket hardware
	float br_x = min(uv.x, 1.0 - uv.x);
	float br_y = 1.0 - seam_uv;
	col += step(br_x, 0.04) * step(br_y, 0.06)  * 0.055;
	col += step(br_x, 0.04) * step(br_y, 0.004) * 0.040;

	// Diagonal scanlines (very faint)
	col -= step(0.82, mod((uv.x - uv.y) * 38.0, 1.0)) * 0.008;

	// Purple seam glow — tight at inner edge only
	col += vec3(0.30, 0.0, 0.50) * pow(seam_uv, 6.0) * 0.70;

	COLOR = vec4(col * cx, 1.0);
}
""" % ("UV.y" if flip else "1.0 - UV.y")
		return s

	static func _shader_beam_glow() -> Shader:
		var s := Shader.new()
		s.code = """
shader_type canvas_item;
uniform vec4  beam_color : source_color = vec4(0.55, 0.0, 1.0, 1.0);
uniform float intensity  : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d      = abs(UV.y - 0.5) * 2.0;
	float halo   = exp(-d * d * 5.0);
	float ripple = 0.93 + 0.07 * sin(UV.x * 55.0 + TIME * 9.0);
	COLOR = vec4(beam_color.rgb * halo * 3.0 * ripple, halo * intensity * 0.85);
}
"""
		return s

	static func _shader_beam_core() -> Shader:
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


# ─────────────────────────────────────────────────────────────────────────────
# FADE TRANSITION
# ─────────────────────────────────────────────────────────────────────────────
class FadeTransition extends BaseTransition:
	var _overlay     : ColorRect
	var _overlay_mat : ShaderMaterial

	func _init(owner: CanvasLayer, cfg: TransitionConfig, w: float, h: float) -> void:
		super(owner, cfg, w, h)
		_build_nodes()

	# ── Public ────────────────────────────────────────────────────────────────
	func play(scene_path: String) -> void:
		_overlay.visible = true
		_overlay_mat.set_shader_parameter("progress", 0.0)
		var t_out := _owner.create_tween()
		t_out.tween_method(
			func(v: float): _overlay_mat.set_shader_parameter("progress", v),
			0.0, 1.0, _cfg.fade_out_time
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await t_out.finished
		await _owner.get_tree().create_timer(_cfg.fade_hold_time).timeout
		_owner.get_tree().change_scene_to_file(scene_path)
		await _owner.get_tree().process_frame
		await _owner.get_tree().process_frame
		var t_in := _owner.create_tween()
		t_in.tween_method(
			func(v: float): _overlay_mat.set_shader_parameter("progress", v),
			1.0, 0.0, _cfg.fade_in_time
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await t_in.finished
		_overlay.visible = false
		_overlay_mat.set_shader_parameter("progress", 0.0)

	func hide_node() -> void:
		_overlay.visible = false

	func show_covered() -> void:
		_overlay.visible = true
		_overlay.color.a = 1.0

	func uncover() -> void:
		var t := _owner.create_tween()
		t.tween_property(_overlay, "color:a", 0.0, _cfg.fade_in_time)\
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await t.finished
		_overlay.visible = false

	# ── Node builder ──────────────────────────────────────────────────────────
	func _build_nodes() -> void:
		_overlay         = ColorRect.new()
		_overlay.name    = "FadeOverlay"
		_overlay.size    = Vector2(_W, _H)
		_overlay.color   = Color(0.0, 0.0, 0.0, 0.0)
		_overlay_mat     = ShaderMaterial.new()
		_overlay_mat.shader = _shader_fade_overlay()
		_overlay_mat.set_shader_parameter("progress", 0.0)
		_overlay.material = _overlay_mat
		_owner.add_child(_overlay)

	# ── Shader ────────────────────────────────────────────────────────────────
	static func _shader_fade_overlay() -> Shader:
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


# ─────────────────────────────────────────────────────────────────────────────
# LAUNCH TRANSITION
# ─────────────────────────────────────────────────────────────────────────────
class LaunchTransition extends BaseTransition:
	var _launch_bg : ColorRect

	func _init(owner: CanvasLayer, cfg: TransitionConfig, w: float, h: float) -> void:
		super(owner, cfg, w, h)
		_build_nodes()

	# ── Public ────────────────────────────────────────────────────────────────

	## Pure clean fade — black hold then smooth dissolve into the first scene.
	## Beam is reserved for in-game transitions only.
	func play(_scene_path: String = "") -> void:
		_launch_bg.visible = true
		_launch_bg.color.a = 1.0
		await _owner.get_tree().create_timer(_cfg.launch_hold_time).timeout
		var t := _owner.create_tween()
		t.tween_property(_launch_bg, "color:a", 0.0, _cfg.launch_fade_in_time)\
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await t.finished
		_launch_bg.visible = false

	func hide_node() -> void:
		_launch_bg.visible = false

	# ── Node builder ──────────────────────────────────────────────────────────
	func _build_nodes() -> void:
		_launch_bg       = ColorRect.new()
		_launch_bg.name  = "LaunchBg"
		_launch_bg.size  = Vector2(_W, _H)
		_launch_bg.color = Color(0.0, 0.0, 0.0, 1.0)
		_owner.add_child(_launch_bg)


# ═════════════════════════════════════════════════════════════════════════════
# SINGLETON — thin dispatcher, owns config and all transition instances
# ═════════════════════════════════════════════════════════════════════════════
var cfg            := TransitionConfig.new()

var _beam          : BeamTransition
var _fade          : FadeTransition
var _launch        : LaunchTransition

# Lookup table — add new Type entries and matching instances here only.
var _registry      : Dictionary  # Type -> BaseTransition

var _transitioning := false
var _W             : float
var _H             : float


func _ready() -> void:
	layer        = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_W = float(ProjectSettings.get_setting("display/window/size/viewport_width",  1920))
	_H = float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))

	# Instantiate each effect — they self-register their nodes onto this CanvasLayer.
	_fade   = FadeTransition.new(self, cfg, _W, _H)
	_beam   = BeamTransition.new(self, cfg, _W, _H)
	_launch = LaunchTransition.new(self, cfg, _W, _H)

	# Register in the dispatch table. To add a new type:
	#   1. Add an entry to the Type enum above.
	#   2. Create a new XxxTransition inner class.
	#   3. Instantiate it here and add it to _registry.
	_registry = {
		Type.BEAM   : _beam,
		Type.FADE   : _fade,
		Type.ARMOUR : _beam,   # reuses BeamTransition — material swap happens inside play()
	}

	_hide_all()


# ═══════════════════════ PUBLIC API ══════════════════════════════════════════

## Transition to a new scene using the specified effect type.
## Usage: SceneTransition.transition_to("res://scenes/Game.tscn", SceneTransition.Type.FADE)
func transition_to(scene_path: String, type: Type = Type.BEAM) -> void:
	if _transitioning:
		return
	_transitioning = true
	match type:
		Type.ARMOUR:
			await _beam.play(scene_path, true)
		_:
			var effect : BaseTransition = _registry.get(type, _beam)
			await effect.play(scene_path)
	_transitioning = false
	emit_signal("transition_finished")


## Play the one-time startup reveal (black screen fades into the first scene).
func launch_reveal() -> void:
	if _transitioning:
		return
	_transitioning = true
	await _launch.play()
	_transitioning = false
	emit_signal("transition_finished")


## Instantly cover the screen with black (useful before manual scene switches).
func cover() -> void:
	_fade.show_covered()


## Fade the cover back out.
func uncover() -> void:
	await _fade.uncover()


# ═════════════════════════════════════════════════════════════════════════════
# PRIVATE HELPERS
# ═════════════════════════════════════════════════════════════════════════════

func _hide_all() -> void:
	_fade.hide_node()
	_beam.hide_nodes()
	_launch.hide_node()
