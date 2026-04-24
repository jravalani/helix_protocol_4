# ============================================
# special_tile.gd
# ============================================

extends Node2D
class_name SpecialTile

enum Type {
	BOOST_CORRIDOR,
	PRESSURE_SINK,
	UNSTABLE_CONDUIT,
	DEAD_ZONE,
}

enum Phase {
	PRE_SPAWN,
	ACTIVE,
	DECAYING,
	EXPIRED,
}

# ── Patch ──────────────────────────────────
var cells: Array[Vector2i] = []
var origin: Vector2i

# ── State ──────────────────────────────────
var tile_type: Type
var is_connected: bool = false
var is_expired: bool = false
var packets_passed: int = 0
var _phase: Phase = Phase.PRE_SPAWN

var lifetime: float = -1.0
var _elapsed: float = 0.0
var _clear_cost: int = 0
var _slowdown_amount: float = 0.0

const DECAY_THRESHOLD: float = 8.0
const URGENT_THRESHOLD: float = 10.0

# ── Pressure Sink flow-rate tracking ───────
# Benefit is active only while packets flow above the threshold rate.
# A rolling window of packet timestamps drives the rate calculation.
# Grace period prevents flickering if packets arrive in bursts.
const SINK_FLOW_WINDOW:     float = 5.0   # seconds — rolling window size
const SINK_FLOW_THRESHOLD:  float = 2.0   # packets per window to stay active
const SINK_GRACE_PERIOD:    float = 2.5   # seconds before benefit drops after flow stops
const SINK_REDUCTION_BASE:  float = 0.10  # base 10% reduction at threshold
const SINK_REDUCTION_MAX:   float = 0.25  # cap at 25% reduction with heavy traffic

var _sink_packet_times:     Array[float] = []   # timestamps of recent packets
var _sink_benefit_active:   bool = false
var _sink_grace_timer:      float = 0.0
var _sink_current_reduction: float = 0.0        # currently applied multiplier delta

# ── Visuals ────────────────────────────────
var _cell_rects: Array = []
var _cell_materials: Array = []
var _border_lines: Array = []        # outer exposed edge segments
var _corner_brackets: Array = []     # L-bracket corner marks
var _glitch_tween: Tween = null
var _decay_tweens: Array = []
var _urgent_tween: Tween = null
var _led_tween: Tween = null

# ── Ghost visuals (pre-spawn only) ─────────
var _ghost_lines: Array = []

# ── Label nodes (defined in special_tile.tscn) ─
@onready var _label_node: Label       = $Labels/TitleLabel
@onready var _sub_label_node: Label   = $Labels/SubLabel
@onready var _timer_label_node: Label = $Labels/TimerLabel

# Cached base x for jitter
var _label_base_x: float = 0.0
var _sub_base_x: float   = 0.0

# ── Scramble chars ─────────────────────────
const _SCRAMBLE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjklmnpqrstuvwxyz0123456789#@!%?><|+-~"

# ── Fonts ──────────────────────────────────
# Only needed for the floating popup label — all other fonts are set in the .tscn
const FONT_EXTRABOLD: FontFile = preload("res://Assets/Fonts/JetBrainsMono-ExtraBold.ttf")

# ── Label font sizes (mirror what's in the .tscn, easy to tweak) ──
const LABEL_TITLE_SIZE: int  = 14
const LABEL_SUB_SIZE: int    = 9
const LABEL_TIMER_SIZE: int  = 12

# ── Config ─────────────────────────────────
const CELL_COUNT_RANGE: Dictionary = {
	Type.BOOST_CORRIDOR:   [6, 10],
	Type.PRESSURE_SINK:    [6, 10],
	Type.UNSTABLE_CONDUIT: [8, 14],
	Type.DEAD_ZONE:        [6, 11],
}

const WEIGHTS: Dictionary = {
	Type.BOOST_CORRIDOR:   0.6,
	Type.PRESSURE_SINK:    1.0,
	Type.UNSTABLE_CONDUIT: 0.3,
	Type.DEAD_ZONE:        8.0,
}

const COLORS: Dictionary = {
	Type.BOOST_CORRIDOR:   Color("00ff88"),
	Type.PRESSURE_SINK:    Color("00aaff"),
	Type.UNSTABLE_CONDUIT: Color("ff8800"),
	Type.DEAD_ZONE:        Color("cc1122"),
}

const TITLE_TEXTS: Dictionary = {
	Type.BOOST_CORRIDOR:   "BOOST CORRIDOR",
	Type.PRESSURE_SINK:    "PRESSURE SINK",
	Type.UNSTABLE_CONDUIT: "UNSTABLE CONDUIT",
	Type.DEAD_ZONE:        "DEAD ZONE",
}

# LED magenta pulse color
const LED_ACTIVE_COLOR:  Color = Color("cc44ff")
const LED_DIM_COLOR:     Color = Color("441155")
const BRACKET_LENGTH:    float = 6.0   # px length of each bracket arm

signal tile_connected(tile: SpecialTile)
signal tile_expired(tile: SpecialTile)
signal packet_passed_through(tile: SpecialTile)

# ── Setup ──────────────────────────────────

func pre_spawn(t: Type, seed_cell: Vector2i) -> void:
	tile_type = t
	origin = seed_cell

	var range_arr: Array = CELL_COUNT_RANGE[tile_type]
	cells = _flood_fill(seed_cell, range_arr[0])

	var sum: Vector2 = Vector2.ZERO
	for c in cells: sum += GameData.get_cell_center(c)
	position = sum / float(cells.size())

	_build_ghost_visuals()
	await get_tree().create_timer(randf_range(0.5, 1.5)).timeout
	_clear_ghost_visuals()
	setup(t, seed_cell)

func setup(t: Type, seed_cell: Vector2i) -> void:
	tile_type = t
	origin = seed_cell

	var range_arr: Array = CELL_COUNT_RANGE[tile_type]
	var target_count: int = randi_range(range_arr[0], range_arr[1])
	cells = _flood_fill(seed_cell, target_count)

	for c in cells:
		GameData.special_tiles[c] = self

	var sum: Vector2 = Vector2.ZERO
	for c in cells: sum += GameData.get_cell_center(c)
	position = sum / float(cells.size())

	match tile_type:
		Type.BOOST_CORRIDOR:
			lifetime = randf_range(55.0, 75.0)
		Type.PRESSURE_SINK:
			lifetime = randf_range(50.0, 70.0)
		Type.UNSTABLE_CONDUIT:
			lifetime = -1.0
		Type.DEAD_ZONE:
			lifetime = 90.0
			var area: int = cells.size()
			_slowdown_amount = clampf(remap(float(area), 3.0, 11.0, 0.2, 0.4), 0.2, 0.4)
			_clear_cost = clamp(int(remap(float(area), 3.0, 11.0, 50.0, 100.0)), 50, 100)

	_apply_weights()
	_build_visuals()

# ── Flood fill ─────────────────────────────

func _flood_fill(seed: Vector2i, target: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [seed]
	var frontier: Array[Vector2i] = [seed]
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while result.size() < target and frontier.size() > 0:
		var idx: int = randi() % frontier.size()
		var current: Vector2i = frontier[idx]
		frontier.remove_at(idx)
		dirs.shuffle()
		for dir in dirs:
			var neighbor: Vector2i = current + dir
			if result.has(neighbor): continue
			if GameData.building_grid.has(neighbor): continue
			if GameData.special_tiles.has(neighbor): continue
			if GameData.get_zone_for_cell(neighbor) not in _get_unlocked_zones(): continue
			result.append(neighbor)
			frontier.append(neighbor)
			if result.size() >= target: break
	return result

func _get_unlocked_zones() -> Array:
	var directors: Array = get_tree().get_nodes_in_group("director")
	if directors.size() > 0 and directors[0].has_method("_is_tile_in_unlocked_zone"):
		return directors[0].unlocked_zones
	return [GameData.Zone.CORE, GameData.Zone.INNER]

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if lifetime > 0.0:
		_elapsed += delta
		_update_timer_label()
		var remaining: float = maxf(0.0, lifetime - _elapsed)

		if _elapsed >= lifetime:
			expire()
		elif remaining < DECAY_THRESHOLD and _phase == Phase.ACTIVE:
			_phase = Phase.DECAYING
			_start_decay_phase()
		elif remaining < URGENT_THRESHOLD and _phase == Phase.ACTIVE:
			_start_urgent_border_flash()

		if _phase == Phase.DECAYING:
			_update_label_instability(remaining)

	if tile_type == Type.PRESSURE_SINK and _phase == Phase.ACTIVE:
		_tick_sink_flow(delta)

# ── Ghost visuals (pre-spawn) ──────────────

func _build_ghost_visuals() -> void:
	var color: Color = COLORS[tile_type]
	var cell_size: Vector2 = Vector2(GameData.CELL_SIZE)
	var cell_set: Dictionary = {}
	for c in cells: cell_set[c] = true

	for c in cells:
		var world_pos: Vector2 = GameData.get_cell_center(c)
		var local_pos: Vector2 = world_pos - position
		var half: Vector2 = cell_size / 2.0
		var edges: Array = [
			[Vector2(-half.x, -half.y), Vector2( half.x, -half.y), Vector2i(0, -1)],
			[Vector2( half.x, -half.y), Vector2( half.x,  half.y), Vector2i(1,  0)],
			[Vector2( half.x,  half.y), Vector2(-half.x,  half.y), Vector2i(0,  1)],
			[Vector2(-half.x,  half.y), Vector2(-half.x, -half.y), Vector2i(-1, 0)],
		]
		for edge in edges:
			if cell_set.has(c + edge[2]): continue
			var line: Line2D = Line2D.new()
			line.default_color = Color(color.r, color.g, color.b, 0.18)
			line.width = 1.5
			line.z_index = 5
			line.add_point(local_pos + edge[0])
			line.add_point(local_pos + edge[1])
			add_child(line)
			_ghost_lines.append(line)

	for line in _ghost_lines:
		var gt: Tween = create_tween().set_loops()
		gt.tween_property(line, "default_color:a", 0.35, randf_range(0.18, 0.35))
		gt.tween_property(line, "default_color:a", 0.08, randf_range(0.12, 0.28))

func _clear_ghost_visuals() -> void:
	for line in _ghost_lines:
		if is_instance_valid(line): line.queue_free()
	_ghost_lines.clear()

# ── Visuals ────────────────────────────────

func _build_visuals() -> void:
	var color: Color = COLORS[tile_type]
	var cell_size: Vector2 = Vector2(GameData.CELL_SIZE)
	var glitch_shader: Shader = load("res://shaders/glitch.gdshader")

	# Cell fill rects with glitch shader
	for c in cells:
		var world_pos: Vector2 = GameData.get_cell_center(c)
		var local_pos: Vector2 = world_pos - position

		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = glitch_shader
		mat.set_shader_parameter("tint_color", color)
		mat.set_shader_parameter("overlay_opacity", 0.0)
		mat.set_shader_parameter("glitch_intensity", 0.9)
		mat.set_shader_parameter("speed", randf_range(2.0, 4.0))

		var rect: ColorRect = ColorRect.new()
		rect.size = cell_size
		rect.position = local_pos - cell_size / 2.0
		rect.material = mat
		rect.z_index = 6
		rect.color = Color(1, 1, 1, 1)
		add_child(rect)
		_cell_rects.append(rect)
		_cell_materials.append(mat)

	# Build outer border edges + corner brackets
	_build_border_and_brackets(color, cell_size)

	_setup_labels(color)
	_glitch_in()

# ── Border + corner brackets ───────────────
# Exposed outer edges are drawn as faint full-length lines.
# Each outer corner gets a bright L-bracket overlaid on top —
# this gives the "targeting / blueprint" look regardless of shape.

func _build_border_and_brackets(color: Color, cell_size: Vector2) -> void:
	var cell_set: Dictionary = {}
	for c in cells: cell_set[c] = true

	# Collect all outer corners: a corner exists at a cell vertex
	# where that vertex is exposed (not fully surrounded by cells).
	# We record each exposed edge segment for the faint full lines,
	# then find corner vertices from the edge endpoints.

	var glow_color: Color  = Color(color.r, color.g, color.b, 0.0)   # starts hidden, fades in
	var dim_color: Color   = Color(color.r, color.g, color.b, 0.0)

	# Edge definitions: [start_corner_offset, end_corner_offset, neighbor_dir]
	var edge_defs: Array = [
		[Vector2(-0.5, -0.5), Vector2( 0.5, -0.5), Vector2i(0, -1)],  # top
		[Vector2( 0.5, -0.5), Vector2( 0.5,  0.5), Vector2i(1,  0)],  # right
		[Vector2( 0.5,  0.5), Vector2(-0.5,  0.5), Vector2i(0,  1)],  # bottom
		[Vector2(-0.5,  0.5), Vector2(-0.5, -0.5), Vector2i(-1, 0)],  # left
	]

	# Collect all exposed edge segments as world vertex pairs
	var exposed_edges: Array = []
	for c in cells:
		var world_pos: Vector2 = GameData.get_cell_center(c)
		var local_pos: Vector2 = world_pos - position
		for ed in edge_defs:
			if cell_set.has(c + ed[2]): continue
			var p0: Vector2 = local_pos + ed[0] * cell_size
			var p1: Vector2 = local_pos + ed[1] * cell_size
			exposed_edges.append([p0, p1])

			# Faint full edge line
			var line: Line2D = Line2D.new()
			line.default_color = dim_color
			line.width = 1.5
			line.z_index = 7
			line.begin_cap_mode = Line2D.LINE_CAP_BOX
			line.end_cap_mode   = Line2D.LINE_CAP_BOX
			line.add_point(p0)
			line.add_point(p1)
			add_child(line)
			_border_lines.append(line)

	# Find corner vertices: points that appear an odd number of times
	# in the edge list are outer corners.
	var vertex_count: Dictionary = {}
	for seg in exposed_edges:
		for pt in [seg[0], seg[1]]:
			var key: String = "%.1f,%.1f" % [pt.x, pt.y]
			vertex_count[key] = vertex_count.get(key, 0) + 1

	var corners: Array = []
	for seg in exposed_edges:
		for pt in [seg[0], seg[1]]:
			var key: String = "%.1f,%.1f" % [pt.x, pt.y]
			if vertex_count[key] % 2 == 1 and pt not in corners:
				corners.append(pt)

	# Draw bracket arms at each outer corner.
	# For each corner, find its two connected exposed edge directions
	# and draw a short line along each.
	var edge_map: Dictionary = {}
	for seg in exposed_edges:
		for i in [0, 1]:
			var key: String = "%.1f,%.1f" % [seg[i].x, seg[i].y]
			if not edge_map.has(key): edge_map[key] = []
			edge_map[key].append(seg[1 - i])

	for corner in corners:
		var key: String = "%.1f,%.1f" % [corner.x, corner.y]
		if not edge_map.has(key): continue
		for neighbor in edge_map[key]:
			var dir: Vector2 = (neighbor - corner).normalized()
			var arm_end: Vector2 = corner + dir * BRACKET_LENGTH
			var bracket: Line2D = Line2D.new()
			bracket.default_color = glow_color
			bracket.width = 3.0
			bracket.z_index = 8
			bracket.begin_cap_mode = Line2D.LINE_CAP_BOX
			bracket.end_cap_mode   = Line2D.LINE_CAP_NONE
			bracket.add_point(corner)
			bracket.add_point(arm_end)
			add_child(bracket)
			_corner_brackets.append(bracket)

# ── Labels ─────────────────────────────────
# Visual hierarchy:
#   TitleLabel  — white, bold, largest   (type identity)
#   SubLabel    — vibrant tile color     (the actual effect — what player needs first)
#   TimerLabel  — dimmed to ~60%         (tertiary, peripheral)
#   LED         — magenta pulsing dot    (active status indicator)

func _setup_labels(color: Color) -> void:
	_label_node.text = TITLE_TEXTS[tile_type]
	_label_node.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_label_node.add_theme_color_override("font_outline_color", color)
	_label_node.add_theme_font_size_override("font_size", LABEL_TITLE_SIZE)
	_label_node.modulate.a = 0.0
	_label_base_x = _label_node.position.x

	match tile_type:
		Type.BOOST_CORRIDOR:   _sub_label_node.text = "1.5x DATA"
		Type.PRESSURE_SINK:    _sub_label_node.text = "FLOW TO REDUCE PRESSURE"
		Type.UNSTABLE_CONDUIT: _sub_label_node.text = "5x FRACTURE RATE"
		Type.DEAD_ZONE:        _sub_label_node.text = "-%d%% PKT SPEED  CLEAR: %d DATA" % [int(_slowdown_amount * 100), _clear_cost]
	_sub_label_node.add_theme_color_override("font_color", color)
	_sub_label_node.add_theme_font_size_override("font_size", LABEL_SUB_SIZE)
	_sub_label_node.modulate.a = 0.0
	_sub_base_x = _sub_label_node.position.x

	_timer_label_node.add_theme_color_override("font_color", color)
	_timer_label_node.add_theme_font_size_override("font_size", LABEL_TIMER_SIZE)
	_timer_label_node.modulate.a = 0.0
	_update_timer_label()

# ── Glitch in ──────────────────────────────

func _glitch_in() -> void:
	var color: Color = COLORS[tile_type]
	match tile_type:
		Type.DEAD_ZONE:        AudioManager.play_sfx("tile_dead_zone")
		Type.UNSTABLE_CONDUIT: AudioManager.play_sfx("tile_unstable_conduit")
		Type.PRESSURE_SINK:    AudioManager.play_sfx("tile_under_pressure")
		_:                     AudioManager.play_sfx("glitch_in")

	for mat in _cell_materials:
		var t: Tween = create_tween()
		t.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.0, 1.0, 0.03)
		t.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 1.0, 0.0, 0.03)
		t.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.0, 1.0, 0.02)
		t.tween_interval(0.04)
		t.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 1.0, 0.3, 0.05)
		t.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.3, 0.8, 0.04)
		t.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.8, 0.55, 0.06)

	# Faint edge lines fade in dimly
	for line in _border_lines:
		var lt: Tween = create_tween()
		lt.tween_interval(0.08)
		lt.tween_property(line, "default_color", Color(color.r, color.g, color.b, 0.25), 0.06)

	# Corner brackets snap in bright — the "targeting lock" feel
	for bracket in _corner_brackets:
		var bt: Tween = create_tween()
		bt.tween_interval(randf_range(0.06, 0.16))
		bt.tween_property(bracket, "default_color", Color(color.r, color.g, color.b, 1.0), 0.04)

	# Snap overshoot scale
	scale = Vector2(1.25, 1.25)
	var st: Tween = create_tween()
	st.tween_property(self, "scale", Vector2.ONE, 0.14)\
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Labels scramble in staggered
	_scramble_label_in(_label_node,      0.28)
	_scramble_label_in(_sub_label_node,  0.34)
	if lifetime > 0.0:
		_scramble_label_in(_timer_label_node, 0.40)

	var it: Tween = create_tween()
	it.tween_interval(0.4)
	it.tween_callback(_start_idle_glitch)
	it.tween_callback(func(): _phase = Phase.ACTIVE)

# ── Scramble label in ──────────────────────

func _scramble_label_in(lbl: Label, delay: float) -> void:
	if not is_instance_valid(lbl): return
	var target: String = lbl.text
	if target.is_empty(): return

	var ft: Tween = create_tween()
	ft.tween_interval(delay)
	ft.tween_property(lbl, "modulate:a", 1.0, 0.04)

	var resolve_step: float = 0.30 / float(max(target.length(), 1))
	var st: Tween = create_tween()
	st.tween_interval(delay + 0.04)

	for i in range(target.length()):
		var char_idx: int = i
		st.tween_callback(func():
			if not is_instance_valid(lbl): return
			var inner: Tween = create_tween()
			for _s in range(randi_range(3, 6)):
				inner.tween_callback(func():
					if not is_instance_valid(lbl): return
					var display: String = target.substr(0, char_idx)
					display += _SCRAMBLE_CHARS[randi() % _SCRAMBLE_CHARS.length()]
					for k in range(char_idx + 1, target.length()):
						display += target[k] if randf() > 0.6 else _SCRAMBLE_CHARS[randi() % _SCRAMBLE_CHARS.length()]
					lbl.text = display
				)
				inner.tween_interval(0.04)
			inner.tween_callback(func():
				if is_instance_valid(lbl): lbl.text = target
			)
		)
		st.tween_interval(resolve_step)

	st.tween_callback(func():
		if is_instance_valid(lbl): lbl.text = target
	)

func _start_idle_glitch() -> void:
	if _cell_materials.is_empty(): return
	_glitch_tween = create_tween().set_loops()
	for mat in _cell_materials:
		var base: float = randf_range(0.45, 0.65)
		_glitch_tween.tween_method(
			func(v: float): mat.set_shader_parameter("glitch_intensity", v),
			base, base * 0.35, 1.0)
		_glitch_tween.tween_method(
			func(v: float): mat.set_shader_parameter("glitch_intensity", v),
			base * 0.35, base, 1.0)

# ── Urgent border flash (10s warning) ──────
# Entire border flashes once per second rapidly

func _start_urgent_border_flash() -> void:
	if _urgent_tween: return  # already running
	var color: Color = COLORS[tile_type]
	_urgent_tween = create_tween().set_loops()
	_urgent_tween.tween_callback(func():
		for bracket in _corner_brackets:
			if is_instance_valid(bracket):
				bracket.default_color = Color(1.0, 1.0, 1.0, 1.0)  # flash white
		for line in _border_lines:
			if is_instance_valid(line):
				line.default_color = Color(color.r, color.g, color.b, 0.8)
	)
	_urgent_tween.tween_interval(0.08)
	_urgent_tween.tween_callback(func():
		for bracket in _corner_brackets:
			if is_instance_valid(bracket):
				bracket.default_color = Color(color.r, color.g, color.b, 1.0)
		for line in _border_lines:
			if is_instance_valid(line):
				line.default_color = Color(color.r, color.g, color.b, 0.25)
	)
	_urgent_tween.tween_interval(0.92)

# ── Decay phase ────────────────────────────

func _start_decay_phase() -> void:
	if _glitch_tween:
		_glitch_tween.kill()
		_glitch_tween = null
	if _urgent_tween:
		_urgent_tween.kill()
		_urgent_tween = null

	for mat in _cell_materials:
		var dt: Tween = create_tween().set_loops()
		dt.tween_method(
			func(v: float): mat.set_shader_parameter("glitch_intensity", v),
			0.5, 2.0, 0.25)
		dt.tween_method(
			func(v: float): mat.set_shader_parameter("glitch_intensity", v),
			2.0, 0.5, 0.25)
		_decay_tweens.append(dt)

	# Timer turns red
	if is_instance_valid(_timer_label_node):
		_timer_label_node.add_theme_color_override("font_color", Color("ff4444"))

# ── Label instability (per frame during decay) ─

func _update_label_instability(remaining: float) -> void:
	var t: float = clampf(1.0 - remaining / DECAY_THRESHOLD, 0.0, 1.0)
	var jitter: float = t * t * 2.5

	if is_instance_valid(_label_node):
		_label_node.modulate.a  = randf_range(lerpf(1.0, 0.55, t), 1.0)
		_label_node.position.x  = _label_base_x + randf_range(-jitter, jitter)

	if is_instance_valid(_sub_label_node):
		_sub_label_node.modulate.a = randf_range(lerpf(0.9, 0.35, t), 0.9)
		_sub_label_node.position.x = _sub_base_x + randf_range(-jitter * 0.6, jitter * 0.6)

	if is_instance_valid(_timer_label_node):
		_timer_label_node.modulate.a = randf_range(lerpf(1.0, 0.4, t), 1.0)

# ── Glitch out ─────────────────────────────

func _glitch_out() -> void:
	AudioManager.play_sfx("glitch_out")
	if _glitch_tween:  _glitch_tween.kill()
	if _urgent_tween:  _urgent_tween.kill()
	if _led_tween:     _led_tween.kill()

	for dt in _decay_tweens:
		if dt: dt.kill()
	_decay_tweens.clear()

	for mat in _cell_materials:
		var gt: Tween = create_tween()
		gt.tween_method(func(v: float): mat.set_shader_parameter("glitch_intensity", v), 0.5, 1.0, 0.03)
		gt.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.55, 1.0, 0.03)
		gt.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 1.0, 0.0, 0.02)
		gt.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.0, 0.9, 0.02)
		gt.tween_method(func(v: float): mat.set_shader_parameter("overlay_opacity", v), 0.9, 0.0, 0.04)

	for line in _border_lines:
		var lt: Tween = create_tween()
		lt.tween_interval(0.06)
		lt.tween_property(line, "default_color:a", 0.0, 0.04)

	for bracket in _corner_brackets:
		var bt: Tween = create_tween()
		bt.tween_interval(randf_range(0.0, 0.06))
		bt.tween_property(bracket, "default_color:a", 0.0, 0.03)

	_collapse_label(_label_node,       0.00, 0.06)
	_collapse_label(_sub_label_node,   0.03, 0.05)
	_collapse_label(_timer_label_node, 0.05, 0.04)

	var ct: Tween = create_tween().set_parallel(true)
	ct.tween_property(self, "scale", Vector2(0.0, 0.0), 0.18)\
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	ct.tween_property(self, "modulate:a", 0.0, 0.12)
	ct.tween_callback(queue_free).set_delay(0.2)

func _collapse_label(lbl: Label, delay: float, duration: float) -> void:
	if not is_instance_valid(lbl): return
	var original: String = lbl.text
	var ct: Tween = create_tween()
	ct.tween_interval(delay)
	ct.tween_callback(func():
		if not is_instance_valid(lbl): return
		var scrambled: String = ""
		for ch in original:
			scrambled += _SCRAMBLE_CHARS[randi() % _SCRAMBLE_CHARS.length()] if randf() > 0.4 else ch
		lbl.text = scrambled
	)
	ct.tween_interval(duration * 0.5)
	ct.tween_property(lbl, "modulate:a", 0.0, duration * 0.5)

# ── Timer ──────────────────────────────────

func _update_timer_label() -> void:
	if not is_instance_valid(_timer_label_node): return
	if lifetime < 0.0:
		_timer_label_node.text = ""
		return
	var remaining: float = maxf(0.0, lifetime - _elapsed)
	_timer_label_node.text = "%ds" % ceili(remaining)

# ── Connection API ─────────────────────────

func on_pipe_connected() -> void:
	if is_connected or is_expired: return
	is_connected = true
	tile_connected.emit(self)

func on_pipe_fractured_under() -> void:
	if tile_type == Type.UNSTABLE_CONDUIT:
		expire()

func on_packet_through(packet: Node) -> void:
	if is_expired: return
	packets_passed += 1
	packet_passed_through.emit(self)
	_on_packet_effect(packet)

func _on_packet_effect(packet: Node) -> void:
	_pulse_visuals()
	match tile_type:
		Type.BOOST_CORRIDOR:
			if packets_passed % 2 == 0:
				GameData.total_data += 1
		Type.PRESSURE_SINK:
			_sink_packet_times.append(_elapsed)
		Type.DEAD_ZONE:
			if packet.has_method("apply_slowdown"):
				packet.apply_slowdown(1.0 - _slowdown_amount)

# ── Traffic pulse ──────────────────────────

func _pulse_visuals() -> void:
	for mat in _cell_materials:
		var current_opacity: float = mat.get_shader_parameter("overlay_opacity")
		var pt: Tween = create_tween()
		pt.tween_method(
			func(v: float): mat.set_shader_parameter("overlay_opacity", v),
			current_opacity, 0.9, 0.04)
		pt.tween_method(
			func(v: float): mat.set_shader_parameter("overlay_opacity", v),
			0.9, 0.55, 0.08)

	# Sub label (the effect value) spikes bright on packet — "under load"
	if is_instance_valid(_sub_label_node):
		var base_color: Color = COLORS[tile_type]
		var bright: Color = base_color.lightened(0.4)
		var pt: Tween = create_tween()
		pt.tween_callback(func(): _sub_label_node.add_theme_color_override("font_color", bright))
		pt.tween_interval(0.07)
		pt.tween_callback(func(): _sub_label_node.add_theme_color_override("font_color", base_color))

# ── Pressure Sink flow-rate system ─────────
# Tracks packets in a rolling window. Applies a scaled pressure_rate_multiplier
# reduction while flow is above threshold, with a grace period before dropping.

func _tick_sink_flow(delta: float) -> void:
	# Purge timestamps outside the rolling window
	var cutoff: float = _elapsed - SINK_FLOW_WINDOW
	while _sink_packet_times.size() > 0 and _sink_packet_times[0] < cutoff:
		_sink_packet_times.pop_front()

	var flow_count: float = float(_sink_packet_times.size())
	var is_flowing: bool = flow_count >= SINK_FLOW_THRESHOLD

	if is_flowing:
		_sink_grace_timer = SINK_GRACE_PERIOD
		# Scale reduction: SINK_REDUCTION_BASE at threshold, up to SINK_REDUCTION_MAX
		var flow_t: float = clampf(
			(flow_count - SINK_FLOW_THRESHOLD) / (SINK_FLOW_WINDOW * 2.0 - SINK_FLOW_THRESHOLD),
			0.0, 1.0)
		var target_reduction: float = lerpf(SINK_REDUCTION_BASE, SINK_REDUCTION_MAX, flow_t)

		if not _sink_benefit_active:
			_sink_benefit_active = true
			_sink_current_reduction = target_reduction
			GameData.pressure_rate_multiplier *= (1.0 - _sink_current_reduction)
			_update_sink_label(true, flow_count)
		elif abs(target_reduction - _sink_current_reduction) > 0.005:
			# Reapply at new rate — undo old, apply new
			GameData.pressure_rate_multiplier /= (1.0 - _sink_current_reduction)
			_sink_current_reduction = target_reduction
			GameData.pressure_rate_multiplier *= (1.0 - _sink_current_reduction)
			_update_sink_label(true, flow_count)
	else:
		if _sink_benefit_active:
			_sink_grace_timer -= delta
			if _sink_grace_timer <= 0.0:
				_sink_benefit_active = false
				GameData.pressure_rate_multiplier /= (1.0 - _sink_current_reduction)
				_sink_current_reduction = 0.0
				_update_sink_label(false, 0.0)

func _update_sink_label(active: bool, flow_count: float) -> void:
	if not is_instance_valid(_sub_label_node): return
	if active:
		var pct: int = int(_sink_current_reduction * 100.0)
		_sub_label_node.text = "-%d%% PRESSURE RATE" % pct
	else:
		_sub_label_node.text = "FLOW TO REDUCE PRESSURE"

# ── Wave interaction ───────────────────────

func on_fracture_wave() -> void:
	match tile_type:
		Type.BOOST_CORRIDOR:
			expire()
		Type.UNSTABLE_CONDUIT:
			expire()

# ── Dead Zone clear ────────────────────────

func try_clear_dead_zone() -> bool:
	if tile_type != Type.DEAD_ZONE: return false
	if GameData.total_data < _clear_cost:
		_spawn_floating_label("Need %d Data" % _clear_cost, Color("ff4444"))
		return false
	GameData.total_data -= _clear_cost
	_spawn_floating_label("ZONE CLEARED", Color("00ff88"))
	expire()
	return true

# ── Weights ────────────────────────────────

func _apply_weights() -> void:
	for c in cells:
		var id: int = GameData.get_cell_id(c)
		if GameData.astar.has_point(id):
			GameData.astar.set_point_weight_scale(id, WEIGHTS[tile_type])

func _clear_weights() -> void:
	for c in cells:
		var id: int = GameData.get_cell_id(c)
		if GameData.astar.has_point(id):
			GameData.astar.set_point_weight_scale(id, 1.0)

# ── Expiry ─────────────────────────────────

func expire() -> void:
	if is_expired: return
	is_expired = true
	_phase = Phase.EXPIRED
	_clear_weights()

	if tile_type == Type.PRESSURE_SINK and _sink_benefit_active:
		GameData.pressure_rate_multiplier /= (1.0 - _sink_current_reduction)
		_sink_benefit_active = false
		_sink_current_reduction = 0.0

	for c in cells:
		GameData.special_tiles.erase(c)

	tile_expired.emit(self)
	_glitch_out()

# ── Floating label ─────────────────────────

func _spawn_floating_label(text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT_EXTRABOLD)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.position = Vector2(-30.0, -50.0)
	add_child(label)
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 32.0, 1.0)
	t.tween_property(label, "modulate:a", 0.0, 1.0)
	t.tween_callback(label.queue_free).set_delay(1.0)
