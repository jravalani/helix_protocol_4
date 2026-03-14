extends Control

## ═══════════════════════════════════════════════════════════════
## HEXAGONAL SKILL TREE
## Rocket upgrade UI — deep ash + neon magenta theme.
## 5 upgrade nodes around a hexagonal frame, center launch hub,
## glow effects, tooltips, and progress bar.
## ═══════════════════════════════════════════════════════════════

# ── Palette ────────────────────────────────────────────────────
const COL_MAGENTA        := Color(1.0, 0.08, 0.58)
const COL_MAGENTA_BRIGHT := Color(1.0, 0.35, 0.72)
const COL_MAGENTA_DIM    := Color(0.45, 0.04, 0.26)
const COL_MAGENTA_GLOW   := Color(1.0, 0.08, 0.58, 0.12)
const COL_BG             := Color(0.05, 0.05, 0.07, 0.93)
const COL_PANEL_BG       := Color(0.07, 0.07, 0.09)
const COL_LOCKED_FILL    := Color(0.10, 0.10, 0.14)
const COL_LOCKED_BORDER  := Color(0.22, 0.22, 0.28)
const COL_NEXT_FILL      := Color(0.25, 0.06, 0.18)
const COL_NEXT_BORDER    := Color(0.65, 0.04, 0.34)
const COL_FRAME          := Color(0.16, 0.16, 0.20)
const COL_FRAME_ACCENT   := Color(0.28, 0.07, 0.18)
const COL_TEXT            := Color(0.92, 0.90, 0.95)
const COL_TEXT_DIM        := Color(0.45, 0.43, 0.50)

# ── Layout ─────────────────────────────────────────────────────
const HEX_RADIUS         := 220.0
const OUTER_HEX_RADIUS   := 270.0
const NODE_RADIUS         := 34.0
const SMALL_NODE_RADIUS   := 10.0
const CENTER_RADIUS       := 62.0
const LINE_W              := 2.5
const GLOW_W              := 14.0

# ── State ──────────────────────────────────────────────────────
var hex_center   := Vector2.ZERO
var hex_pts      : Array = []
var outer_pts    : Array = []
var edge_mids    : Array = []
var hovered_node := -1
var hover_close  := false
var hover_launch := false
var pulse        := 0.0
var font         : Font

## Maps pentagon vertex index (0-4 clockwise from top) to rocket upgrade phase.
var phase_map := [1, 2, 3, 4, 5]
const NUM_NODES := 5

# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	font = preload("res://Assets/Fonts/JetBrainsMono-ExtraBold.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP

	SignalBus.open_rocket_menu.connect(_on_open_rocket_menu)
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	ResourceManager.resources_updated.connect(func(_a, _b, _c): queue_redraw())

	_recalc()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recalc()

func _recalc() -> void:
	hex_center = Vector2(size.x / 2.0, size.y / 2.0 - 20.0)
	hex_pts.clear(); outer_pts.clear(); edge_mids.clear()
	for i in NUM_NODES:
		var a = deg_to_rad((360.0 / NUM_NODES) * i - 90.0)
		var d = Vector2(cos(a), sin(a))
		hex_pts.append(hex_center + d * HEX_RADIUS)
		outer_pts.append(hex_center + d * OUTER_HEX_RADIUS)
	for i in NUM_NODES:
		edge_mids.append((hex_pts[i] + hex_pts[(i + 1) % NUM_NODES]) / 2.0)

func _process(delta: float) -> void:
	if visible:
		pulse += delta
		queue_redraw()

# ═══════════════════════════════════════════════════════════════
# DRAWING  (back-to-front order)
# ═══════════════════════════════════════════════════════════════

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)

	_draw_bg_rings()
	_draw_outer_frame()
	_draw_radial_lines()
	_draw_hex_edges()
	_draw_edge_dots()
	_draw_nodes()
	_draw_center_hub()
	_draw_ui_chrome()

	if hovered_node >= 0 and hovered_node < NUM_NODES:
		_draw_tooltip()

# ── Background concentric rings ───────────────────────────────
func _draw_bg_rings() -> void:
	for i in range(4):
		var r = CENTER_RADIUS + 35.0 + i * 55.0
		draw_arc(hex_center, r, 0, TAU, 64, Color(COL_FRAME, 0.12), 1.0, true)

# ── Outer decorative hex frame ────────────────────────────────
func _draw_outer_frame() -> void:
	for i in NUM_NODES:
		draw_line(outer_pts[i], outer_pts[(i + 1) % NUM_NODES], Color(COL_FRAME, 0.5), 2.0, true)
	for i in NUM_NODES:
		var dir_out = (outer_pts[i] - hex_center).normalized()
		draw_line(outer_pts[i], outer_pts[i] + dir_out * 8.0, Color(COL_FRAME, 0.7), 2.0)

# ── Radial spokes from center to vertices ─────────────────────
func _draw_radial_lines() -> void:
	for i in NUM_NODES:
		var ph = phase_map[i]
		var lit = ph != -1 and _unlocked(ph)
		if lit:
			draw_line(hex_center, hex_pts[i], COL_MAGENTA_GLOW, GLOW_W, true)
			draw_line(hex_center, hex_pts[i], Color(COL_MAGENTA, 0.25), 4.0, true)
			draw_line(hex_center, hex_pts[i], COL_MAGENTA_DIM, 1.5, true)
		else:
			draw_line(hex_center, hex_pts[i], Color(COL_FRAME, 0.35), 1.0, true)

# ── Inner hex edges connecting nodes ──────────────────────────
func _draw_hex_edges() -> void:
	for i in NUM_NODES:
		var j = (i + 1) % NUM_NODES
		if _edge_lit(i, j):
			draw_line(hex_pts[i], hex_pts[j], COL_MAGENTA_GLOW, GLOW_W, true)
			draw_line(hex_pts[i], hex_pts[j], Color(COL_MAGENTA, 0.35), 6.0, true)
			draw_line(hex_pts[i], hex_pts[j], COL_MAGENTA, LINE_W, true)
		else:
			draw_line(hex_pts[i], hex_pts[j], COL_FRAME, LINE_W, true)

# ── Small dots at edge midpoints ──────────────────────────────
func _draw_edge_dots() -> void:
	for i in NUM_NODES:
		var lit = _edge_lit(i, (i + 1) % NUM_NODES)
		var p = edge_mids[i]
		if lit:
			draw_circle(p, SMALL_NODE_RADIUS + 3.0, COL_MAGENTA_GLOW)
			draw_circle(p, SMALL_NODE_RADIUS, Color(COL_MAGENTA_DIM, 0.6))
			draw_arc(p, SMALL_NODE_RADIUS, 0, TAU, 24, COL_MAGENTA, 1.5, true)
		else:
			draw_circle(p, SMALL_NODE_RADIUS, COL_LOCKED_FILL)
			draw_arc(p, SMALL_NODE_RADIUS, 0, TAU, 24, COL_LOCKED_BORDER, 1.0, true)

# ── Main skill-node circles ──────────────────────────────────
func _draw_nodes() -> void:
	var cur = GameData.current_rocket_phase
	for i in NUM_NODES:
		var p   = hex_pts[i]
		var ph  = phase_map[i]

		var unlocked = _unlocked(ph)
		var is_next  = (ph == cur + 1)
		var hovered  = (hovered_node == i)

		if unlocked:
			var g = 6.0 + sin(pulse * 2.0) * 2.0
			draw_circle(p, NODE_RADIUS + g, COL_MAGENTA_GLOW)
			draw_circle(p, NODE_RADIUS + 3.0, Color(COL_MAGENTA, 0.15))
			draw_circle(p, NODE_RADIUS, Color(COL_MAGENTA_DIM, 0.85))
			draw_arc(p, NODE_RADIUS, 0, TAU, 48, COL_MAGENTA, 2.5, true)
			draw_arc(p, NODE_RADIUS - 5.0, 0, TAU, 48, Color(COL_MAGENTA, 0.25), 1.0, true)
			_text_c(_roman(ph), p + Vector2(0, 2), 18, COL_TEXT)
		elif is_next:
			var pa = 0.5 + sin(pulse * 3.0) * 0.3
			var hb = 1.3 if hovered else 1.0
			draw_circle(p, NODE_RADIUS + 4.0, Color(COL_MAGENTA, 0.06 * hb))
			draw_circle(p, NODE_RADIUS, COL_NEXT_FILL)
			draw_arc(p, NODE_RADIUS, 0, TAU, 48, Color(COL_NEXT_BORDER, pa * hb), 2.5, true)
			_text_c(_roman(ph), p + Vector2(0, 2), 18, Color(COL_TEXT, 0.7))
		else:
			var hb = 0.05 if hovered else 0.0
			draw_circle(p, NODE_RADIUS, Color(COL_LOCKED_FILL.r + hb, COL_LOCKED_FILL.g + hb, COL_LOCKED_FILL.b + hb))
			draw_arc(p, NODE_RADIUS, 0, TAU, 48, COL_LOCKED_BORDER, 2.0, true)
			_text_c(_roman(ph), p + Vector2(0, 2), 18, COL_TEXT_DIM)

		# Skill name label below node
		var label = GameData.ROCKET_UPGRADES[ph]["name"]
		_text_c(label, p + Vector2(0, NODE_RADIUS + 18), 11, COL_TEXT_DIM if not unlocked else Color(COL_TEXT, 0.7))

# ── Center hub — rocket icon + launch ─────────────────────────
func _draw_center_hub() -> void:
	var ready = GameData.current_rocket_phase >= 5
	var hov   = hover_launch and ready

	# Outer glow when all segments complete
	if ready:
		var g = 10.0 + sin(pulse * 2.5) * 4.0
		draw_circle(hex_center, CENTER_RADIUS + g, COL_MAGENTA_GLOW)
		draw_circle(hex_center, CENTER_RADIUS + 4.0, Color(COL_MAGENTA, 0.12))

	# Fill
	var fill = COL_PANEL_BG
	if hov:
		fill = Color(fill.r + 0.04, fill.g + 0.04, fill.b + 0.04)
	draw_circle(hex_center, CENTER_RADIUS, fill)

	# Borders
	var bc = COL_MAGENTA if ready else COL_FRAME_ACCENT
	draw_arc(hex_center, CENTER_RADIUS, 0, TAU, 64, bc, 3.0, true)
	draw_arc(hex_center, CENTER_RADIUS - 8.0, 0, TAU, 64, Color(bc, 0.25), 1.0, true)

	# Rocket icon (simple triangle + exhaust nubs)
	var rp = hex_center + Vector2(0, -14)
	var rs = 16.0
	var rc = COL_MAGENTA if ready else COL_TEXT_DIM

	# Fuselage
	draw_colored_polygon(PackedVector2Array([
		rp + Vector2(0, -rs),
		rp + Vector2(-rs * 0.45, rs * 0.5),
		rp + Vector2(rs * 0.45, rs * 0.5)
	]), rc)
	# Left fin
	draw_colored_polygon(PackedVector2Array([
		rp + Vector2(-rs * 0.35, rs * 0.5),
		rp + Vector2(-rs * 0.55, rs * 0.85),
		rp + Vector2(-rs * 0.15, rs * 0.5)
	]), COL_MAGENTA_DIM if ready else Color(COL_TEXT_DIM, 0.5))
	# Right fin
	draw_colored_polygon(PackedVector2Array([
		rp + Vector2(rs * 0.15, rs * 0.5),
		rp + Vector2(rs * 0.55, rs * 0.85),
		rp + Vector2(rs * 0.35, rs * 0.5)
	]), COL_MAGENTA_DIM if ready else Color(COL_TEXT_DIM, 0.5))

	# LAUNCH text
	_text_c("LAUNCH", hex_center + Vector2(0, 34), 14, rc)

# ── Title, data counter, progress bar, close button ──────────
func _draw_ui_chrome() -> void:
	# Title
	draw_string(font, Vector2(40, 55), "SKILL TREE", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, COL_MAGENTA)
	draw_line(Vector2(40, 65), Vector2(225, 65), Color(COL_MAGENTA, 0.3), 1.0)

	# Data counter
	draw_string(font, Vector2(40, 110), "DATA:", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TEXT_DIM)
	draw_string(font, Vector2(40, 142), str(GameData.total_data), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COL_MAGENTA)

	# Phase label
	var phase_text = "Phase: %d / 5" % GameData.current_rocket_phase
	draw_string(font, Vector2(40, 175), phase_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_DIM)

	# ── Progress bar ──
	var bw = 460.0; var bh = 28.0
	var bx = (size.x - bw) / 2.0; var by = size.y - 55.0
	var prog = clampf(float(GameData.current_rocket_phase) / 5.0, 0.0, 1.0)

	draw_rect(Rect2(bx, by, bw, bh), Color(0.08, 0.08, 0.10))
	draw_rect(Rect2(bx, by, bw, bh), COL_FRAME, false, 1.5)
	if prog > 0:
		draw_rect(Rect2(bx, by, bw * prog, bh), COL_MAGENTA_DIM)
		draw_line(Vector2(bx, by), Vector2(bx + bw * prog, by), COL_MAGENTA, 1.0)

	var bar_label = "ROCKET COMPLETION: %d / 5 SEGMENTS" % GameData.current_rocket_phase
	_text_c(bar_label, Vector2(size.x / 2.0, by + bh / 2.0 + 5.0), 12, COL_TEXT)


# ── Tooltip for hovered skill node ────────────────────────────
func _draw_tooltip() -> void:
	var ph  = phase_map[hovered_node]
	var upg = GameData.ROCKET_UPGRADES[ph]
	var np  = hex_pts[hovered_node]

	var tw = 260.0; var th = 100.0
	var off = Vector2(50, -30)
	if np.x > hex_center.x + 40:
		off.x = -(tw + 15)
	var tp = np + off
	tp.x = clampf(tp.x, 10, size.x - tw - 10)
	tp.y = clampf(tp.y, 10, size.y - th - 10)

	draw_rect(Rect2(tp, Vector2(tw, th)), Color(0.04, 0.04, 0.06, 0.95))
	draw_rect(Rect2(tp, Vector2(tw, th)), COL_MAGENTA_DIM, false, 1.5)

	# Name
	draw_string(font, tp + Vector2(12, 24), upg["name"], HORIZONTAL_ALIGNMENT_LEFT, int(tw - 24), 16, COL_MAGENTA)
	# Description (multi-line)
	draw_multiline_string(font, tp + Vector2(12, 46), upg["description"], HORIZONTAL_ALIGNMENT_LEFT, tw - 24, 11, -1, COL_TEXT_DIM)
	# Cost / status
	if _unlocked(ph):
		draw_string(font, tp + Vector2(12, th - 10), "UNLOCKED", HORIZONTAL_ALIGNMENT_LEFT, int(tw - 24), 13, COL_MAGENTA)
	else:
		var ct = "Cost: %d Data" % upg["cost"]
		var cc = COL_TEXT if GameData.total_data >= upg["cost"] else Color(1.0, 0.3, 0.3)
		draw_string(font, tp + Vector2(12, th - 10), ct, HORIZONTAL_ALIGNMENT_LEFT, int(tw - 24), 13, cc)

# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════

func _unlocked(phase: int) -> bool:
	return phase >= 1 and phase <= GameData.current_rocket_phase

func _edge_lit(i: int, j: int) -> bool:
	return _unlocked(phase_map[i]) and _unlocked(phase_map[j])

func _roman(phase: int) -> String:
	match phase:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
	return "?"

func _text_c(text: String, pos: Vector2, sz: int, col: Color) -> void:
	var ts = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	draw_string(font, Vector2(pos.x - ts.x / 2.0, pos.y + sz * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz, col)

# ═══════════════════════════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _update_hover(mp: Vector2) -> void:
	hovered_node = -1; hover_close = false; hover_launch = false

	for i in NUM_NODES:
		if hex_pts.size() > i and hex_pts[i].distance_to(mp) <= NODE_RADIUS + 4.0:
			hovered_node = i
			return

	if hex_center.distance_to(mp) <= CENTER_RADIUS:
		hover_launch = true
		return

	if Vector2(size.x - 48, 42).distance_to(mp) <= 18.0:
		hover_close = true

func _handle_click(mp: Vector2) -> void:
	# Close
	if Vector2(size.x - 48, 42).distance_to(mp) <= 18.0:
		_close(); return

	# Launch
	if hex_center.distance_to(mp) <= CENTER_RADIUS:
		if GameData.current_rocket_phase >= 5:
			SignalBus.launch_rocket_requested.emit()
			_close()
		return

	# Skill nodes
	for i in NUM_NODES:
		if hex_pts.size() > i and hex_pts[i].distance_to(mp) <= NODE_RADIUS + 4.0:
			_click_node(i); return

	# Clicked empty space — close the tree
	_close()

func _click_node(idx: int) -> void:
	var ph = phase_map[idx]
	if ph != GameData.current_rocket_phase + 1:
		return
	if ResourceManager.upgrade_rocket_phase():
		print("Rocket upgraded to phase: ", GameData.current_rocket_phase)
	else:
		print("Insufficient data to upgrade.")

# ═══════════════════════════════════════════════════════════════
# OPEN / CLOSE  (with fade)
# ═══════════════════════════════════════════════════════════════

func _close() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tw.tween_callback(func():
		self.hide()
		self.modulate = Color(1, 1, 1, 1)
	)

func _on_open_rocket_menu() -> void:
	self.modulate = Color(1, 1, 1, 0)
	self.show()
	var tw = create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.2)
	queue_redraw()

func _on_rocket_segment_purchased(to_phase: int) -> void:
	queue_redraw()
	if to_phase >= 5:
		print("All segments complete! Launch ready.")
