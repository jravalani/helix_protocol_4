extends PathFollow2D
class_name Packet

@onready var packet_line: Line2D = $PacketLine2D
@onready var packet_light: PointLight2D = $PacketLight

@export var speed: float = 120.0
var _base_speed: float = 120.0
var _speed_multiplier: float = 1.0

# Speed per pipe upgrade level — tweak here
const SPEED_PER_LEVEL := [120.0, 150.0, 185.0, 225.0]

var target_hub_cell: Vector2i
var source_vent_cell: Vector2i          # vent's driveway cell (A* endpoint)
var source_vent: Vent
var returning: bool = false             # true = heading back toward vent
var _path_cells: Array[Vector2i] = []

const TAIL_STEPS: int    = 8
const TAIL_DISTANCE: float = 20.0
const PACKET_WIDTH: float  = 10.0

# ── Dual-lane system ─────────────────────────────────────────────
# Outbound (vent→hub) rides the left lane (+offset perpendicular to path)
# Returning (hub→vent) rides the right lane (-offset perpendicular to path)
const LANE_OFFSET: float = 5.0

var _outbound_gradient: Gradient
var _returning_gradient: Gradient

func _ready() -> void:
	loop = false
	_base_speed = SPEED_PER_LEVEL[clamp(GameData.current_pipe_upgrade_level, 0, 3)]
	speed = _base_speed
	SignalBus.trigger_packet_slowdown.connect(_on_fracture_wave)
	SignalBus.pipes_upgraded.connect(_on_pipes_upgraded)

	# Outbound gradient — cyan/electric blue (active data transmission)
	_outbound_gradient = Gradient.new()
	_outbound_gradient.offsets = PackedFloat32Array([0.0, 0.91, 1.0])
	_outbound_gradient.colors = PackedColorArray([
		Color(0.02, 0.06, 0.15, 1.0),   # dark blue tail
		Color(0.0, 0.75, 0.92, 1.0),    # bright cyan body
		Color(0.85, 1.0, 1.0, 1.0)      # white-cyan head
	])

	# Returning gradient — amber/gold (payload delivered, heading home)
	_returning_gradient = Gradient.new()
	_returning_gradient.offsets = PackedFloat32Array([0.0, 0.91, 1.0])
	_returning_gradient.colors = PackedColorArray([
		Color(0.15, 0.08, 0.02, 1.0),   # dark amber tail
		Color(0.92, 0.55, 0.05, 1.0),   # warm amber body
		Color(1.0, 0.95, 0.85, 1.0)     # white-gold head
	])

	_apply_lane_visuals()

func _on_pipes_upgraded(level: int) -> void:
	_base_speed = SPEED_PER_LEVEL[clamp(level, 0, 3)]
	speed = _base_speed * _speed_multiplier

func apply_slowdown(multiplier: float) -> void:
	_speed_multiplier = multiplier
	speed = _base_speed * _speed_multiplier
	packet_line.modulate = Color(1.6, 0.2, 1.4, packet_line.modulate.a)

func restore_speed() -> void:
	_speed_multiplier = 1.0
	speed = _base_speed
	packet_line.modulate = Color(1.0, 1.0, 1.0, packet_line.modulate.a)

func _on_fracture_wave() -> void:
	apply_slowdown(0.7)

var _exploding: bool = false

func _process(delta: float) -> void:
	if _exploding:
		return
	if progress_ratio < 1.0:
		progress += speed * delta
		_update_visuals()
	else:
		_on_arrival()

func _update_visuals() -> void:
	packet_line.clear_points()

	var curve: Curve2D = get_parent().curve
	if not curve:
		return

	var total_length: float = curve.get_baked_length()

	# Sample world positions along the curve for the tail
	var samples: Array[Vector2] = []
	for i in range(TAIL_STEPS + 1):
		var t: float = float(i) / float(TAIL_STEPS)
		var sample_progress: float = progress - TAIL_DISTANCE * (1.0 - t)
		sample_progress = clamp(sample_progress, 0.0, total_length)
		samples.append(curve.sample_baked(sample_progress))

	# Build lane-offset points from per-sample tangent
	var last_tangent: Vector2 = Vector2.RIGHT
	for i in range(samples.size()):
		var tangent: Vector2
		if i < samples.size() - 1:
			tangent = samples[i + 1] - samples[i]
		elif i > 0:
			tangent = samples[i] - samples[i - 1]
		else:
			tangent = last_tangent

		if tangent.length_squared() > 0.001:
			tangent = tangent.normalized()
			last_tangent = tangent
		else:
			tangent = last_tangent

		# Left perpendicular in Godot 2D (Y-down)
		# No sign flip needed — reversed tangent on the return path
		# naturally places the returning packet on the opposite side.
		var left_perp: Vector2 = Vector2(tangent.y, -tangent.x)
		var offset_pos: Vector2 = samples[i] + left_perp * LANE_OFFSET
		packet_line.add_point(to_local(offset_pos))

	# Offset the light to match the lane
	# With rotates=true, local -Y always points left-of-travel,
	# which is the correct side for both directions.
	packet_light.position = Vector2(0, -LANE_OFFSET)

# ════════════════════════════════════════════════════════════════
#region Path Building
# ════════════════════════════════════════════════════════════════

func setup_path(vent_node: Vent, start_cell: Vector2i, end_cell: Vector2i) -> void:
	source_vent = vent_node
	source_vent_cell = start_cell
	target_hub_cell = end_cell
	returning = false

	if not _build_forward_path():
		get_parent().queue_free()


func _build_forward_path() -> bool:
	_deregister_path_tiles()

	var start_id = GameData.get_cell_id(source_vent_cell)
	var end_id   = GameData.get_cell_id(target_hub_cell)

	if not (GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id)):
		return false

	var path_points = GameData.astar.get_point_path(start_id, end_id)
	if path_points.size() < 2:
		return false

	var new_curve = Curve2D.new()
	# Prepend vent position so the packet visually exits from inside the vent
	if source_vent and is_instance_valid(source_vent):
		new_curve.add_point(source_vent.global_position)
	for pt in path_points:
		new_curve.add_point(pt)

	get_parent().curve = new_curve
	progress = 0

	_register_path_tiles(path_points)
	return true


func _build_return_path() -> bool:
	_deregister_path_tiles()

	var start_id = GameData.get_cell_id(target_hub_cell)
	var end_id   = GameData.get_cell_id(source_vent_cell)

	if not (GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id)):
		return false

	var path_points = GameData.astar.get_point_path(start_id, end_id)
	if path_points.size() < 2:
		return false

	var new_curve = Curve2D.new()
	for pt in path_points:
		new_curve.add_point(pt)
	# Append vent position so the packet visually enters the vent
	if source_vent and is_instance_valid(source_vent):
		new_curve.add_point(source_vent.global_position)

	get_parent().curve = new_curve
	progress = 0

	_register_path_tiles(path_points)
	return true


func _register_path_tiles(path_points: PackedVector2Array) -> void:
	_path_cells.clear()
	for pt in path_points:
		var c: Vector2i = GameData.world_to_cell(pt)
		var tile = GameData.road_grid.get(c)
		if tile is NewRoadTile:
			_path_cells.append(c)
			tile.on_packet_entered()
		var st: SpecialTile = GameData.special_tiles.get(c) as SpecialTile
		if st:
			st.on_packet_through(self)


func _deregister_path_tiles() -> void:
	for c in _path_cells:
		var tile = GameData.road_grid.get(c)
		if tile is NewRoadTile:
			tile.on_packet_exited()
	_path_cells.clear()

#endregion


# ════════════════════════════════════════════════════════════════
#region Arrival Handling
# ════════════════════════════════════════════════════════════════

func _on_arrival() -> void:
	if returning:
		_arrive_at_vent()
	else:
		_arrive_at_hub()


func _arrive_at_hub() -> void:
	var hub = GameData.building_grid.get(target_hub_cell)

	# Rate-limited → explode (vent will respawn a replacement)
	if hub and hub is Hub and hub.is_rate_limited:
		_explode()
		return

	# Hub fractured or gone → destroy so vent can respawn with a valid hub
	if not hub or not hub is Hub or hub.is_fractured:
		get_parent().queue_free()
		return

	# Score
	hub.receive_oxygen_packet()

	# Flip direction — head back to vent
	returning = true
	_apply_lane_visuals()
	if not _build_return_path():
		get_parent().queue_free()


func _arrive_at_vent() -> void:
	# Validate hub is still worth looping to
	var hub = GameData.building_grid.get(target_hub_cell)
	if not hub or not hub is Hub or hub.is_fractured:
		get_parent().queue_free()
		return

	# Flip direction — head back to hub
	returning = false
	_apply_lane_visuals()
	if not _build_forward_path():
		get_parent().queue_free()

#endregion


# ════════════════════════════════════════════════════════════════
#region Destruction
# ════════════════════════════════════════════════════════════════

# ── Lane visual helpers ──────────────────────────────────────────

func _apply_lane_visuals() -> void:
	if returning:
		packet_line.gradient = _returning_gradient
		packet_light.color = Color(1.0, 0.7, 0.2)   # warm amber glow
	else:
		packet_line.gradient = _outbound_gradient
		packet_light.color = Color(0.3, 0.8, 1.0)   # cyan glow

func _explode() -> void:
	_exploding = true
	set_process(false)
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(packet_line, "modulate", Color(2.0, 0.4, 0.1, 1.0), 0.05)
	t.tween_property(packet_light, "energy", 4.0, 0.05)
	t.tween_property(packet_line, "scale", Vector2(2.5, 2.5), 0.08)
	await get_tree().create_timer(0.08).timeout
	var t2: Tween = create_tween().set_parallel(true)
	t2.tween_property(packet_line, "scale", Vector2(0.0, 0.0), 0.18)
	t2.tween_property(packet_line, "modulate:a", 0.0, 0.18)
	t2.tween_property(packet_light, "energy", 0.0, 0.18)
	await get_tree().create_timer(0.2).timeout
	get_parent().queue_free()


func _exit_tree() -> void:
	_deregister_path_tiles()
	# Free up vent capacity so it can respawn a replacement
	if source_vent and is_instance_valid(source_vent):
		source_vent.current_capacity = max(0, source_vent.current_capacity - 1)
		source_vent.notify_capacity_freed()

#endregion
