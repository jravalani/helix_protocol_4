extends PathFollow2D
class_name Packet

@export var speed: float = 150
var target_hub_cell: Vector2i
var source_vent_cell: Vector2i
var source_vent: Vent
var is_delivered: bool = false

signal packet_delivered

func _ready():
	loop = false

func _process(delta):
	if progress_ratio < 1.0:
		progress += speed * delta
	else:
		deliver_to_hub()

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
	# 1. Always free up the Vent capacity no matter what
	if source_vent:
		source_vent.current_capacity = max(0, source_vent.current_capacity - 1)
	
	# 2. If it WASN'T delivered (e.g. road deleted), we must fix the Hub's in_flight
	# so the Hub knows it needs to re-order that oxygen.
	if not is_delivered:
		var hub = GameData.building_grid.get(target_hub_cell)
		if hub is Hub:
			hub.oxygen_in_flight = max(0, hub.oxygen_in_flight - 1)
			hub.update_ui()
