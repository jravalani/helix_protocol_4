# ============================================
# special_tile.gd
# ============================================
# A world-space tile that modifies A* weights and triggers
# effects when packets pass through connected pipes.
#
# Spawned by director_2.gd at pressure phase transitions.
# Removed when expired, completed, or the connected pipe fractures.
# ============================================

extends Node2D
class_name SpecialTile

enum Type {
	BOOST_CORRIDOR,    # 2x data per packet. Raises pressure while active.
	UNSTABLE_CONDUIT,  # Low weight (flood with packets), 5x fracture chance.
	DEAD_ZONE,         # Very high weight. A* avoids but can still route through.
	PRESSURE_SINK,     # Connected pipe instantly drops pressure 5pt. Slightly higher weight.
}

# ── State ──────────────────────────────────
var tile_type: Type
var cell: Vector2i
var is_connected: bool = false      # true once a player pipe connects to this cell
var is_expired: bool = false
var packets_passed: int = 0         # for UNSTABLE_CONDUIT objective tracking

# ── Per-type config ─────────────────────────
const WEIGHTS: Dictionary = {
	Type.BOOST_CORRIDOR:   0.5,   # attractive — packets flow through
	Type.UNSTABLE_CONDUIT: 0.3,   # very attractive — floods with traffic
	Type.DEAD_ZONE:        12.0,  # repulsive — A* avoids strongly
	Type.PRESSURE_SINK:    1.8,   # slightly avoided — mild throughput cost
}

const COLORS: Dictionary = {
	Type.BOOST_CORRIDOR:   Color("00ff88"),   # green
	Type.UNSTABLE_CONDUIT: Color("ff8800"),   # orange
	Type.DEAD_ZONE:        Color("880011"),   # dark red
	Type.PRESSURE_SINK:    Color("00aaff"),   # cyan-blue
}

const LABELS: Dictionary = {
	Type.BOOST_CORRIDOR:   "BOOST CORRIDOR",
	Type.UNSTABLE_CONDUIT: "UNSTABLE CONDUIT",
	Type.DEAD_ZONE:        "DEAD ZONE",
	Type.PRESSURE_SINK:    "PRESSURE SINK",
}

# BOOST_CORRIDOR: expires after next fracture wave
# UNSTABLE_CONDUIT: permanent until fractured
# DEAD_ZONE: expires when cleared (player spends data) or after 90s
# PRESSURE_SINK: one-use — triggers on first packet, then disappears

var lifetime: float = -1.0        # -1 = no timer expiry
var _elapsed: float = 0.0
var _pulse_tween: Tween

# Visual nodes created in _ready
var _bg_rect: ColorRect
var _label_node: Label
var _glow: PointLight2D

signal tile_connected(tile: SpecialTile)
signal tile_expired(tile: SpecialTile)
signal packet_passed_through(tile: SpecialTile)

# ── Lifecycle ──────────────────────────────

func setup(t: Type, c: Vector2i) -> void:
	tile_type = t
	cell = c
	position = GameData.get_cell_center(c)

	# Register in GameData so road_builder can query it
	GameData.special_tiles[c] = self

	# Set A* weight immediately — even before connection,
	# so the tile cell itself (if player builds on it) carries the weight.
	_apply_weight()

	if tile_type == Type.DEAD_ZONE:
		lifetime = 90.0

func _ready() -> void:
	_build_visuals()
	_start_pulse()

func _process(delta: float) -> void:
	if lifetime > 0:
		_elapsed += delta
		if _elapsed >= lifetime:
			expire()

# ── Connection API (called by new_road_builder) ────

## Called when the player builds a pipe onto or adjacent to this cell.
func on_pipe_connected() -> void:
	if is_connected or is_expired:
		return
	is_connected = true
	tile_connected.emit(self)
	_on_connected_effect()

## Called by packet.gd when a packet's path includes this cell.
func on_packet_through() -> void:
	if is_expired:
		return
	packets_passed += 1
	packet_passed_through.emit(self)
	_on_packet_effect()

# ── Per-type effects ───────────────────────

func _on_connected_effect() -> void:
	match tile_type:
		Type.PRESSURE_SINK:
			# Instant pressure drop on connect
			GameData.current_pressure = max(0.0, GameData.current_pressure - 5.0)
			_spawn_floating_label("-5 PRESSURE", COLORS[tile_type])
			await get_tree().create_timer(0.5).timeout
			expire()
		Type.BOOST_CORRIDOR:
			_spawn_floating_label("BOOST ACTIVE", COLORS[tile_type])
		Type.UNSTABLE_CONDUIT:
			_spawn_floating_label("CONDUIT LIVE", COLORS[tile_type])
		Type.DEAD_ZONE:
			_spawn_floating_label("ZONE ACTIVE", COLORS[tile_type])

func _on_packet_effect() -> void:
	match tile_type:
		Type.BOOST_CORRIDOR:
			# Award bonus data and nudge pressure up
			GameData.total_data += 5
			GameData.current_pressure = min(GameData.MAX_PRESSURE,
				GameData.current_pressure + 0.3)

		Type.UNSTABLE_CONDUIT:
			# Fracture chance handled in new_road_tile via multiplier.
			# Nothing extra needed here — the weight does the work.
			pass

		Type.PRESSURE_SINK:
			# Shouldn't fire (expires on connect) but guard anyway
			pass

		Type.DEAD_ZONE:
			# Packets that brave the dead zone lose data
			GameData.total_data = max(0, GameData.total_data - 2)

# ── Called by director_2 when a fracture wave hits ─

func on_fracture_wave() -> void:
	match tile_type:
		Type.BOOST_CORRIDOR:
			# Wave destroys the corridor
			_spawn_floating_label("CORRIDOR LOST", Color("ff4444"))
			expire()
		Type.UNSTABLE_CONDUIT:
			# Wave doesn't expire it — but the underlying pipe likely fractures
			pass

# ── Called by player spending data to clear Dead Zone ─

func try_clear_dead_zone() -> bool:
	if tile_type != Type.DEAD_ZONE:
		return false
	const CLEAR_COST: int = 50
	if GameData.total_data < CLEAR_COST:
		_spawn_floating_label("Need 50 Data", Color("ff4444"))
		return false
	GameData.total_data -= CLEAR_COST
	_spawn_floating_label("ZONE CLEARED", Color("00ff88"))
	expire()
	return true

# ── Weight ─────────────────────────────────

func _apply_weight() -> void:
	var id: int = GameData.get_cell_id(cell)
	if GameData.astar.has_point(id):
		GameData.astar.set_point_weight_scale(id, WEIGHTS[tile_type])

func _clear_weight() -> void:
	var id: int = GameData.get_cell_id(cell)
	if GameData.astar.has_point(id):
		GameData.astar.set_point_weight_scale(id, 1.0)

# ── Expiry ─────────────────────────────────

func expire() -> void:
	if is_expired:
		return
	is_expired = true
	_clear_weight()
	GameData.special_tiles.erase(cell)
	tile_expired.emit(self)
	if _pulse_tween:
		_pulse_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_callback(queue_free)

# ── Visuals ────────────────────────────────

func _build_visuals() -> void:
	var color: Color = COLORS[tile_type]
	var half: Vector2 = Vector2(GameData.CELL_SIZE) / 2.0

	# ── Background fill ──────────────────────────────────────────────
	_bg_rect = ColorRect.new()
	_bg_rect.size = Vector2(GameData.CELL_SIZE)
	_bg_rect.position = -half
	_bg_rect.color = Color(color.r, color.g, color.b, 0.12)
	_bg_rect.z_index = 5
	add_child(_bg_rect)

	# ── Animated dashed border ───────────────────────────────────────
	# Four corners as two crossing Line2Ds (corner brackets)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var bracket: Line2D = Line2D.new()
		bracket.default_color = Color(color.r, color.g, color.b, 0.9)
		bracket.width = 2.5
		bracket.z_index = 7
		bracket.begin_cap_mode = Line2D.LINE_CAP_ROUND
		bracket.end_cap_mode = Line2D.LINE_CAP_ROUND
		var cx: float = corner.x * half.x
		var cy: float = corner.y * half.y
		var arm: float = 10.0
		bracket.add_point(Vector2(cx, cy + corner.y * -arm))
		bracket.add_point(Vector2(cx, cy))
		bracket.add_point(Vector2(cx + corner.x * -arm, cy))
		add_child(bracket)

	# ── Glow ring (expands outward and loops) ────────────────────────
	var ring: Line2D = Line2D.new()
	ring.default_color = Color(color.r, color.g, color.b, 0.5)
	ring.width = 1.5
	ring.z_index = 6
	ring.begin_cap_mode = Line2D.LINE_CAP_NONE
	ring.end_cap_mode = Line2D.LINE_CAP_NONE
	const RING_PTS: int = 32
	for i in range(RING_PTS + 1):
		var angle: float = (float(i) / RING_PTS) * TAU
		ring.add_point(Vector2(cos(angle), sin(angle)) * 18.0)
	add_child(ring)

	# Animate ring scale expanding outward
	var ring_tween: Tween = create_tween().set_loops()
	ring_tween.tween_property(ring, "scale", Vector2(2.2, 2.2), 1.2)\
		.from(Vector2(0.6, 0.6)).set_trans(Tween.TRANS_SINE)
	ring_tween.tween_property(ring, "modulate:a", 0.0, 0.4)
	ring_tween.tween_property(ring, "modulate:a", 0.5, 0.0)

	# ── Center icon ──────────────────────────────────────────────────
	_draw_icon(tile_type, color)

	# ── Label above tile ─────────────────────────────────────────────
	_label_node = Label.new()
	_label_node.text = LABELS[tile_type]
	_label_node.add_theme_font_size_override("font_size", 10)
	_label_node.add_theme_color_override("font_color", color)
	_label_node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label_node.add_theme_constant_override("outline_size", 3)
	_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_node.position = Vector2(-48, -half.y - 18)
	_label_node.custom_minimum_size = Vector2(96, 0)
	_label_node.z_index = 8
	add_child(_label_node)

func _draw_icon(type: Type, color: Color) -> void:
	var icon: Line2D = Line2D.new()
	icon.default_color = Color(color.r, color.g, color.b, 0.95)
	icon.width = 2.5
	icon.z_index = 8
	icon.begin_cap_mode = Line2D.LINE_CAP_ROUND
	icon.end_cap_mode = Line2D.LINE_CAP_ROUND
	icon.joint_mode = Line2D.LINE_JOINT_ROUND

	match type:
		Type.BOOST_CORRIDOR:
			# Arrow pointing right — speed, flow
			icon.add_point(Vector2(-10, 0))
			icon.add_point(Vector2(6, 0))
			add_child(icon)
			var head: Line2D = Line2D.new()
			head.default_color = icon.default_color
			head.width = 2.5
			head.begin_cap_mode = Line2D.LINE_CAP_ROUND
			head.end_cap_mode = Line2D.LINE_CAP_ROUND
			head.add_point(Vector2(2, -6))
			head.add_point(Vector2(10, 0))
			head.add_point(Vector2(2, 6))
			head.z_index = 8
			add_child(head)
			return

		Type.UNSTABLE_CONDUIT:
			# Lightning bolt
			icon.add_point(Vector2(4, -12))
			icon.add_point(Vector2(-2, -1))
			icon.add_point(Vector2(4, -1))
			icon.add_point(Vector2(-4, 12))

		Type.DEAD_ZONE:
			# X mark
			icon.add_point(Vector2(-8, -8))
			icon.add_point(Vector2(8, 8))
			add_child(icon)
			var cross: Line2D = Line2D.new()
			cross.default_color = icon.default_color
			cross.width = 2.5
			cross.begin_cap_mode = Line2D.LINE_CAP_ROUND
			cross.end_cap_mode = Line2D.LINE_CAP_ROUND
			cross.add_point(Vector2(8, -8))
			cross.add_point(Vector2(-8, 8))
			cross.z_index = 8
			add_child(cross)
			return

		Type.PRESSURE_SINK:
			# Downward arrow (pressure going down)
			icon.add_point(Vector2(0, -10))
			icon.add_point(Vector2(0, 6))
			add_child(icon)
			var head: Line2D = Line2D.new()
			head.default_color = icon.default_color
			head.width = 2.5
			head.begin_cap_mode = Line2D.LINE_CAP_ROUND
			head.end_cap_mode = Line2D.LINE_CAP_ROUND
			head.add_point(Vector2(-6, 2))
			head.add_point(Vector2(0, 10))
			head.add_point(Vector2(6, 2))
			head.z_index = 8
			add_child(head)
			return

	add_child(icon)

func _start_pulse() -> void:
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_bg_rect, "color:a", 0.28, 0.9)\
		.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_bg_rect, "color:a", 0.08, 0.9)\
		.set_trans(Tween.TRANS_SINE)

func _spawn_floating_label(text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 9)
	label.position = Vector2(-24, -40)
	add_child(label)
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 28, 0.9)
	t.tween_property(label, "modulate:a", 0.0, 0.9)
	t.tween_callback(label.queue_free).set_delay(0.9)
