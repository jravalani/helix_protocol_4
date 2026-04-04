## ═══════════════════════════════════════════════════════════════════
##  LoseScene.gd
##  Attach to a Control node in your LoseScene.tscn
##
##  How to call from your game when player loses:
##    WinSceneData.pipe_tiles     = pipe_count
##    WinSceneData.peak_pressure  = max_pressure
##    WinSceneData.data_collected = total_data
##    WinSceneData.survival_time  = seconds_survived
##    WinSceneData.failure_cause  = "PRESSURE OVERLOAD"  # optional
##    SceneTransition.transition_to("res://Scenes/LoseScene.tscn", SceneTransition.Type.BEAM)
## ═══════════════════════════════════════════════════════════════════
extends Control

# ── Scene paths ───────────────────────────────────────────────────
const MAIN_MENU_SCENE := "res://Scenes/title_screen.tscn"
const GAME_SCENE      := "res://Scenes/title_screen.tscn"

# ── Colours — red/dark theme for failure ─────────────────────────
const C_BG        := Color(0.059, 0.051, 0.051, 1.0)
const C_RED       := Color(0.80,  0.13,  0.13,  1.0)
const C_RED_D     := Color(0.53,  0.10,  0.10,  1.0)
const C_PANEL     := Color(0.094, 0.059, 0.059, 1.0)
const C_BORDER    := Color(0.180, 0.125, 0.125, 1.0)
const C_TEXT_DIM  := Color(0.40,  0.27,  0.27,  1.0)
const C_FLASH     := Color(0.80,  0.0,   0.0,   0.0)

# ── Stats ─────────────────────────────────────────────────────────
var pipe_tiles     : int    = 0
var peak_pressure  : float  = 0.0
var data_collected : int    = 0
var survival_time  : float  = 0.0   # seconds
var failure_cause  : String = ""    # optional override

# ── Internal ──────────────────────────────────────────────────────
var _title_label  : Label
var _orbs         : Array[ColorRect] = []
var _anim_time    : float = 0.0
var _W : float
var _H : float

func _ready() -> void:
	_W = float(ProjectSettings.get_setting("display/window/size/viewport_width",  1920))
	_H = float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))

	# Pull from WinSceneData autoload (shared with win scene)
	if has_node("/root/WinSceneData"):
		var d : Node = get_node("/root/WinSceneData")
		pipe_tiles     = d.pipe_tiles
		peak_pressure  = d.peak_pressure
		data_collected = d.data_collected
		if d.get("survival_time"):
			survival_time = d.survival_time
		if d.get("failure_cause"):
			failure_cause = d.failure_cause

	_build_ui()

# ═══════════════════════ UI BUILD ════════════════════════════════
func _build_ui() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0

	# Background
	var bg      := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color    = C_BG
	var bg_mat  := ShaderMaterial.new()
	bg_mat.shader = _shader_background()
	bg.material = bg_mat
	add_child(bg)

	# Red vignette overlay — darker edges for dread feel
	var vign      := ColorRect.new()
	vign.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vign_mat  := ShaderMaterial.new()
	vign_mat.shader = _shader_vignette()
	vign.material = vign_mat
	add_child(vign)

	_spawn_orbs()
	_build_border_frame()

	# Status line
	var status := Label.new()
	status.text = "HELIX PROTOCOL  /  HULL INTEGRITY LOST"
	status.add_theme_color_override("font_color", C_TEXT_DIM)
	status.add_theme_font_size_override("font_size", 14)
	status.position = Vector2(_W * 0.5 - 200, 78)
	status.modulate.a = 0.0
	add_child(status)
	_fade_in_delayed(status, 0.3)

	# MISSION title
	_title_label = _make_label("MISSION", 72, C_RED, true)
	_title_label.position = Vector2(_W * 0.5 - 235, 112)
	_title_label.modulate.a = 0.0
	_title_label.scale = Vector2(1.1, 1.1)
	add_child(_title_label)
	_fade_in_delayed(_title_label, 0.45)
	_punch_in(_title_label, 0.45)

	# FAILED subtitle
	var sub := _make_label("FAILED", 32, C_RED_D, true)
	sub.position = Vector2(_W * 0.5 - 105, 200)
	sub.modulate.a = 0.0
	add_child(sub)
	_fade_in_delayed(sub, 0.60)

	# Divider
	var divider       := ColorRect.new()
	divider.color      = C_RED
	divider.size       = Vector2(_W * 0.55, 1)
	divider.position   = Vector2(_W * 0.5 - _W * 0.275, 255)
	divider.modulate.a = 0.0
	add_child(divider)
	_fade_in_delayed(divider, 0.75)

	_build_stats_grid()
	_build_cause_block()
	_build_buttons()

# ── Stats grid ────────────────────────────────────────────────────
func _build_stats_grid() -> void:
	var labels := ["PIPE TILES", "PEAK PRESSURE", "DATA SALVAGED", "SURVIVAL TIME"]
	var values := [
		str(pipe_tiles),
		"%.2f%%" % peak_pressure,
		_format_data(data_collected),
		_format_time(survival_time)
	]
	var units  := ["LAID", "CRITICAL", "RECOVERED", "ELAPSED"]

	var grid_w  := _W * 0.58
	var card_w  := (grid_w - 30.0) / 4.0
	var card_h  := 100.0
	var start_x := _W * 0.5 - grid_w * 0.5
	var start_y := 274.0

	for i in range(4):
		var cx := start_x + i * (card_w + 10.0)

		var card := ColorRect.new()
		card.color    = C_PANEL
		card.size     = Vector2(card_w, card_h)
		card.position = Vector2(cx, start_y)
		card.modulate.a = 0.0
		add_child(card)

		# Top accent line
		var accent := ColorRect.new()
		accent.color    = Color(C_RED.r, C_RED.g, C_RED.b, 0.22)
		accent.size     = Vector2(card_w, 2)
		accent.position = Vector2(cx, start_y)
		add_child(accent)

		var border := _make_border_rect(cx, start_y, card_w, card_h)
		add_child(border)

		var lbl := _make_label(labels[i], 10, C_TEXT_DIM, false)
		lbl.position = Vector2(cx + 10, start_y + 14)
		add_child(lbl)

		var val := _make_label(values[i], 26, C_RED, true)
		val.position = Vector2(cx + 10, start_y + 34)
		add_child(val)

		var unit := _make_label(units[i], 10, C_RED_D, false)
		unit.position = Vector2(cx + 10, start_y + 76)
		add_child(unit)

		var delay := 0.82 + i * 0.08
		for n : CanvasItem in [card, accent, border, lbl, val, unit]:
			_fade_in_delayed(n, delay)

# ── Cause block ───────────────────────────────────────────────────
func _build_cause_block() -> void:
	var cause     := failure_cause if failure_cause != "" else _determine_cause()
	var cause_y   := 403.0
	var block_w   := 420.0
	var block_x   := _W * 0.5 - block_w * 0.5

	var bg := ColorRect.new()
	bg.color    = Color(0.070, 0.030, 0.030, 1.0)
	bg.size     = Vector2(block_w, 88)
	bg.position = Vector2(block_x, cause_y)
	bg.modulate.a = 0.0
	add_child(bg)

	var border := _make_border_rect(block_x, cause_y, block_w, 88)
	border.modulate.a = 0.0
	add_child(border)

	var clbl := _make_label("FAILURE CAUSE", 10, C_TEXT_DIM, false)
	clbl.position = Vector2(block_x + block_w * 0.5 - 65, cause_y + 14)
	clbl.modulate.a = 0.0
	add_child(clbl)

	var cval := _make_label(cause, 28, C_RED, true)
	cval.position = Vector2(block_x + block_w * 0.5 - _estimate_label_width(cause, 28) * 0.5, cause_y + 30)
	cval.modulate.a = 0.0
	add_child(cval)

	var cdesc := _make_label(_cause_description(cause), 10, C_RED_D, false)
	cdesc.position = Vector2(block_x + 20, cause_y + 70)
	cdesc.modulate.a = 0.0
	add_child(cdesc)

	for n : CanvasItem in [bg, border, clbl, cval, cdesc]:
		_fade_in_delayed(n, 1.12)

# ── Buttons ───────────────────────────────────────────────────────
func _build_buttons() -> void:
	var btn_y  := 528.0
	var btn_w  := 200.0
	var total  := btn_w * 2 + 16.0
	var bx     := _W * 0.5 - total * 0.5

	var btn_data := [
		["MAIN MENU", C_TEXT_DIM, _on_main_menu],
		["TRY AGAIN",  C_RED,     _on_try_again],
	]

	for i in range(btn_data.size()):
		var btn := Button.new()
		btn.text = btn_data[i][0]
		btn.size = Vector2(btn_w, 44)
		btn.position = Vector2(bx + i * (btn_w + 16), btn_y)
		btn.add_theme_color_override("font_color",         btn_data[i][1])
		btn.add_theme_color_override("font_hover_color",   C_RED)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", 14)
		btn.modulate.a = 0.0
		btn.pressed.connect(btn_data[i][2])
		add_child(btn)
		_fade_in_delayed(btn, 1.28 + i * 0.08)

# ── Border frame ──────────────────────────────────────────────────
func _build_border_frame() -> void:
	var t := 3.0
	var m := 18.0
	var segs := [
		[Vector2(m, m),            Vector2(_W - m * 2, t)],
		[Vector2(m, _H - m - t),   Vector2(_W - m * 2, t)],
		[Vector2(m, m),            Vector2(t, _H - m * 2)],
		[Vector2(_W - m - t, m),   Vector2(t, _H - m * 2)],
	]
	for seg in segs:
		var r := ColorRect.new()
		r.color    = C_BORDER
		r.position = seg[0]
		r.size     = seg[1]
		add_child(r)
	# Corner hardware
	for cx in [m - 4, _W - m - 14]:
		for cy in [m - 4, _H - m - 14]:
			var sq := ColorRect.new()
			sq.color    = Color(0.22, 0.14, 0.14, 1.0)
			sq.size     = Vector2(18, 18)
			sq.position = Vector2(cx, cy)
			add_child(sq)

# ── Floating orbs ─────────────────────────────────────────────────
func _spawn_orbs() -> void:
	var positions := [
		Vector2(0.08, 0.22), Vector2(0.06, 0.48), Vector2(0.13, 0.72),
		Vector2(0.88, 0.28), Vector2(0.91, 0.58), Vector2(0.84, 0.80),
		Vector2(0.16, 0.86), Vector2(0.74, 0.14)
	]
	for p in positions:
		var orb      := ColorRect.new()
		orb.color     = Color(0.80, 0.13, 0.13, 0.70)
		var sz        := randf_range(4.0, 9.0)
		orb.size      = Vector2(sz, sz)
		orb.position  = Vector2(_W * p.x, _H * p.y)
		_orbs.append(orb)
		add_child(orb)

# ═══════════════════════ ANIMATION ════════════════════════════════
func _process(delta: float) -> void:
	_anim_time += delta
	for i in range(_orbs.size()):
		var orb := _orbs[i]
		orb.position.y += sin(_anim_time * 1.1 + i * 0.9) * delta * 3.0
		orb.modulate.a  = 0.35 + sin(_anim_time * 0.7 + i) * 0.25

func _fade_in_delayed(node: CanvasItem, delay: float) -> void:
	node.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(node, "modulate:a", 1.0, 0.35)\
	 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)\
	 .set_delay(delay)

func _punch_in(node: CanvasItem, delay: float) -> void:
	node.scale = Vector2(1.15, 1.15)
	var t := create_tween()
	t.tween_property(node, "scale", Vector2(1.0, 1.0), 0.45)\
	 .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)\
	 .set_delay(delay)

# ═══════════════════════ BUTTON CALLBACKS ═════════════════════════
func _on_main_menu() -> void:
	SceneTransition.transition_to(MAIN_MENU_SCENE, SceneTransition.Type.BEAM)

func _on_try_again() -> void:
	SceneTransition.transition_to(GAME_SCENE, SceneTransition.Type.BEAM)

# ═══════════════════════ HELPERS ══════════════════════════════════
func _determine_cause() -> String:
	if peak_pressure >= 8.0:
		return "PRESSURE OVERLOAD"
	elif peak_pressure >= 5.0:
		return "HULL BREACH"
	elif pipe_tiles < 10:
		return "INSUFFICIENT PIPES"
	else:
		return "SYSTEM FAILURE"

func _cause_description(cause: String) -> String:
	match cause:
		"PRESSURE OVERLOAD":  return "PRESSURE EXCEEDED SAFE THRESHOLD  /  HULL DESTROYED"
		"HULL BREACH":        return "SHIELD INTEGRITY DEPLETED  /  BREACH UNCONTAINED"
		"INSUFFICIENT PIPES": return "PIPE NETWORK INCOMPLETE  /  FLOW UNMANAGED"
		_:                    return "CRITICAL SYSTEM ERROR  /  MISSION ABORTED"

func _format_data(val: int) -> String:
	if val >= 1000:
		return "%dK" % (val / 1000)
	return str(val)

func _format_time(seconds: float) -> String:
	if seconds <= 0:
		return "0s"
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	if m > 0:
		return "%dm%ds" % [m, s]
	return "%ds" % s

func _estimate_label_width(text: String, size: int) -> float:
	return text.length() * size * 0.55

func _make_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _make_border_rect(x: float, y: float, w: float, h: float) -> Node2D:
	var root := Node2D.new()
	root.position = Vector2.ZERO
	var t := 1.0
	var segs := [
		[Vector2(x, y),       Vector2(w, t)],
		[Vector2(x, y+h-t),   Vector2(w, t)],
		[Vector2(x, y),       Vector2(t, h)],
		[Vector2(x+w-t, y),   Vector2(t, h)],
	]
	for seg in segs:
		var r := ColorRect.new()
		r.color    = C_BORDER
		r.position = seg[0]
		r.size     = seg[1]
		root.add_child(r)
	return root

# ═══════════════════════ SHADERS ══════════════════════════════════
func _shader_background() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
void fragment() {
	vec3 col = vec3(0.059, 0.051, 0.051);
	float diag = mod((UV.x - UV.y) * 36.0, 1.0);
	col -= step(0.78, diag) * 0.007;
	COLOR = vec4(col, 1.0);
}
"""
	return s

func _shader_vignette() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = dot(uv * vec2(0.9, 1.0), uv * vec2(0.9, 1.0));
	float vig = smoothstep(0.3, 1.5, d) * 0.65;
	COLOR = vec4(0.15, 0.0, 0.0, vig);
}
"""
	return s
