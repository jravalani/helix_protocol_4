extends Building
class_name Vent

const DRIVEWAY_OFFSET := Vector2(0, 32)  # base offset, unrotated


@onready var driveway_marker: Marker2D = $DrivewayMarker
@onready var fan: Sprite2D = $Fan
@onready var max_capacity: int = 2


@onready var left_cloud: GPUParticles2D = $LeftCloud
@onready var right_cloud: GPUParticles2D = $RightCloud

var packet_scene = preload("res://Scenes/packet.tscn")

var is_connected_to_network: bool = false
var current_capacity: int = 0

var shipment_queue: Array[Node2D] = []
var spawn_timer: float = 0.0
var spawn_interval: float = 0.6

var fan_rotation_speed = 4.0

var click_position: Vector2
var has_dragged: bool = false


func get_top_left_px(step: float) -> Vector2:
	return global_position - (Vector2(grid_size) * step / 2.0)

func _physics_process(delta: float) -> void:
	fan.rotation += fan_rotation_speed * delta

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				# Remember where we clicked
				get_viewport().set_input_as_handled() 
				click_position = get_global_mouse_position()
				has_dragged = false
			else:
				# Released - only rotate if we didn't drag
				if not has_dragged:
					print("Vent clicked (no drag) - rotating!")
					rotate_45_degrees()
				get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion:
		# If mouse moved more than a small threshold, it's a drag
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var current_pos = get_global_mouse_position()
			if click_position.distance_to(current_pos) > 5.0:  # 10 pixel threshold
				has_dragged = true

func _ready():
	left_cloud.restart()
	right_cloud.restart()
	SignalBus.camera_shake.emit(0.25, 4.0)
	cell_type = "VENT"
	super()
	SignalBus.map_changed.connect(_on_map_changed)
	
	await get_tree().process_frame  # wait for marker to be positioned
	
	var dir_vec = (driveway_marker.global_position - global_position).normalized()
	var driveway_direction = Vector2i(round(dir_vec.x), round(dir_vec.y))
	SignalBus.building_spawned.emit(entrance_cell, driveway_direction)
	
	_on_map_changed()
	
	

func _process(delta: float) -> void:
	if shipment_queue.size() > 0:
		spawn_timer -= delta
		if spawn_timer <= 0:
			var next_hub = shipment_queue.pop_front()
			_spawn_packet(next_hub)
			spawn_timer = spawn_interval

func get_driveway_direction() -> Vector2i:
	var rotated := DRIVEWAY_OFFSET.rotated(deg_to_rad(driveway_marker.rotation_degrees))
	return Vector2i(round(rotated.normalized().x), round(rotated.normalized().y))

func rotate_45_degrees() -> void:
	driveway_marker.rotation_degrees += 45
	if driveway_marker.rotation_degrees >= 360:
		driveway_marker.rotation_degrees = 0

	# Strip the arm on the old neighbor that was pointing back at the stub
	var stub = GameData.road_grid.get(entrance_cell)
	if stub is NewRoadTile:
		for old_dir in stub.manual_connections.duplicate():
			var old_neighbor = GameData.road_grid.get(entrance_cell + old_dir)
			if old_neighbor is NewRoadTile:
				old_neighbor.remove_connection(-old_dir)

	var driveway_direction = get_driveway_direction()

	# Disconnect old A* connections
	var my_id = GameData.get_cell_id(entrance_cell)
	var connections = GameData.astar.get_point_connections(my_id)
	for conn_id in connections:
		GameData.astar.disconnect_points(my_id, conn_id, true)

	SignalBus.building_spawned.emit(entrance_cell, driveway_direction)
	_on_map_changed()

func _on_map_changed():
	var my_id = GameData.get_cell_id(entrance_cell)
	if not GameData.astar.has_point(my_id):
		return
	update_connection_status()

func update_connection_status():
	"""Check if there is a valid A* path to any hub."""
	var was_connected = is_connected_to_network
	is_connected_to_network = false
	
	if GameData.building_grid.is_empty():
		return
	
	for cell in GameData.building_grid:
		var building = GameData.building_grid[cell]
		if building is Hub:
			var start_id = GameData.get_cell_id(entrance_cell)
			var end_id = GameData.get_cell_id(building.entrance_cell)
			if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
				var path = GameData.astar.get_id_path(start_id, end_id)
				if path.size() > 0:
					is_connected_to_network = true
					break
	
	if was_connected != is_connected_to_network:
		print("Vent at %s connected to network: %s" % [entrance_cell, is_connected_to_network])

func can_send_oxygen_packet_to(requester: Node2D) -> bool:
	if current_capacity < max_capacity and is_connected_to_network:
		current_capacity += 1
		shipment_queue.append(requester)
		return true
	return false


func _spawn_packet(requester: Node2D) -> void:
	var target_cell = requester.entrance_cell
	var path_container = Path2D.new()
	get_parent().add_child(path_container)
	var oxygen_packet = packet_scene.instantiate()
	path_container.add_child(oxygen_packet)
	oxygen_packet.global_position = global_position
	oxygen_packet.setup_path(self, entrance_cell, target_cell)

func get_max_capacity() -> int:
	return max_capacity

func get_current_capacity() -> int:
	return current_capacity
