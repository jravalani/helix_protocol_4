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
var source_vent_cell: Vector2i
var source_vent: Vent
var is_delivered: bool = false
var _fading_out: bool = false
var _waiting_to_free: bool = false

signal packet_delivered

const TAIL_STEPS    := 8
const TAIL_DISTANCE := 20.0
const PACKET_WIDTH  := 10.0

func _ready() -> void:
	loop = false
	# Base speed driven by current pipe upgrade level
	_base_speed = SPEED_PER_LEVEL[clamp(GameData.current_pipe_upgrade_level, 0, 3)]
	speed = _base_speed
	SignalBus.trigger_packet_slowdown.connect(_on_fracture_wave)
	SignalBus.pipes_upgraded.connect(_on_pipes_upgraded)

func _on_pipes_upgraded(level: int) -> void:
	_base_speed = SPEED_PER_LEVEL[clamp(level, 0, 3)]
	speed = _base_speed * _speed_multiplier

func apply_slowdown(multiplier: float) -> void:
	_speed_multiplier = multiplier
	speed = _base_speed * _speed_multiplier
	# Tint the packet orange-red to signal slowdown
	packet_line.modulate = Color(1.6, 0.2, 1.4, packet_line.modulate.a)

func restore_speed() -> void:
	_speed_multiplier = 1.0
	speed = _base_speed
	packet_line.modulate = Color(1.0, 1.0, 1.0, packet_line.modulate.a)

func _on_fracture_wave() -> void:
	apply_slowdown(0.7)

func _process(delta: float) -> void:
	if progress_ratio < 1.0:
		progress += speed * delta
		_update_visuals()
	else:
		deliver_to_hub()

func _update_visuals() -> void:
	packet_line.clear_points()
	
	var curve: Curve2D = get_parent().curve
	if not curve:
		return
	
	var total_length := curve.get_baked_length()
	
	# Sample from tail → head so Line2D draws tail first (thin end)
	for i in range(TAIL_STEPS + 1):
		var t := float(i) / float(TAIL_STEPS)
		var sample_progress := progress - TAIL_DISTANCE * (1.0 - t)
		sample_progress = clamp(sample_progress, 0.0, total_length)
		
		var world_pos := curve.sample_baked(sample_progress)
		packet_line.add_point(to_local(world_pos))
	
	# Light stays at head (this node's position is already the head)
	packet_light.position = Vector2.ZERO

func setup_path(vent_node: Vent, start_cell: Vector2i, end_cell: Vector2i):
	source_vent = vent_node
	"""Set up A* path with left‑lane offset (opposite of cars)."""
	source_vent_cell = start_cell
	target_hub_cell = end_cell
	
	var start_id = GameData.get_cell_id(start_cell)
	var end_id = GameData.get_cell_id(end_cell)
	
	# Safety checks
	if not (GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id)):
		print("⚠️ Packet: A* points missing for path from %s to %s" % [start_cell, end_cell])
		get_parent().queue_free()
		return
	
	var path_points = GameData.astar.get_point_path(start_id, end_id)
	
	if path_points.size() < 2:
		print("⚠️ Packet: No valid path from %s to %s" % [start_cell, end_cell])
		get_parent().queue_free()
		return
	
	# Build curve with lane offset (left lane = -6)
	var new_curve = Curve2D.new()
	#var lane_offset_dist = -6.0  # Negative = left lane
	
	for i in range(path_points.size()):
		var current_point = path_points[i]
		#var offset = Vector2.ZERO
		#
		#if i < path_points.size() - 1:
			#var next_point = path_points[i + 1]
			##var direction = (next_point - current_point).normalized()
			## Left lane: perpendicular vector rotated clockwise (x,y) -> (-y,x)
			##var left_dir = Vector2(-direction.y, direction.x)
			##offset = left_dir * lane_offset_dist
		#else:
			## Last point – use previous direction to keep offset consistent
			#var prev_point = path_points[i - 1]
			##var direction = (current_point - prev_point).normalized()
			##var left_dir = Vector2(-direction.y, direction.x)
			##offset = left_dir * lane_offset_dist
		
		new_curve.add_point(current_point)
	
	get_parent().curve = new_curve
	progress = 0

func deliver_to_hub():
	"""Deliver oxygen to the target hub."""
	var hub = GameData.building_grid.get(target_hub_cell)
	
	if hub and hub is Hub:
		hub.receive_oxygen_packet()
		packet_delivered.emit()
		is_delivered = true
		print("Packet delivered to hub at %s" % target_hub_cell)
	else:
		print("⚠️ Packet: No hub found at %s" % target_hub_cell)
	
	# Clean up the Path2D container (which also removes this packet)
	get_parent().queue_free()

func _exit_tree() -> void:
	# Free up vent capacity
	if source_vent:
		source_vent.current_capacity = max(0, source_vent.current_capacity - 1)
		source_vent.notify_capacity_freed()
