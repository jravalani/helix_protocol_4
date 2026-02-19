extends Building
class_name Vent

@onready var driveway_marker: Marker2D = $DrivewayMarker
@onready var max_capacity: int = 2

var packet_scene = preload("res://Scenes/packet.tscn")

var is_connected_to_network: bool = false
var current_capacity: int = 0


var shipment_queue: Array[Node2D] = []
var spawn_timer: float = 0.0
var spawn_interval: float = 0.6

func _ready():
	cell_type = "VENT"
	super() # Registers footprint and entrance
	
	# Listen for road changes
	SignalBus.map_changed.connect(_on_map_changed)
	
	# Check connection after one frame (A* must be ready)
	await get_tree().process_frame
	_on_map_changed()

func _process(delta: float) -> void:
	if shipment_queue.size() > 0:
		spawn_timer -= delta
		if spawn_timer <= 0:
			var next_hub = shipment_queue.pop_front()
			_spawn_packet(next_hub)
			spawn_timer = spawn_interval

func rotate_45_degrees() -> void:
	rotation_degrees += 45
	if rotation_degrees >= 360:
		rotation_degrees = 0
	_on_map_changed()

func _on_map_changed():
	"""Connect vent to road network if a road is placed in front of its driveway."""
	var my_id = GameData.get_cell_id(entrance_cell)
	
	# 1. Disconnect any old connections
	for conn in GameData.astar.get_point_connections(my_id):
		GameData.astar.disconnect_points(my_id, conn)
	
	# 2. Determine driveway direction
	var marker_pos = driveway_marker.global_position
	var vent_pos = global_position
	var dir_vec = (marker_pos - vent_pos).normalized()
	var driveway_direction = Vector2i(round(dir_vec.x), round(dir_vec.y))
	
	# 3. Adjacent cell in that direction
	var adjacent_road_cell = entrance_cell + driveway_direction
	var road_tile = GameData.road_grid.get(adjacent_road_cell)
	
	# 4. If there's a road, check if it has a connection facing the vent
	if road_tile != null and road_tile.has_method("has_connection_in_direction"):
		var road_id = GameData.get_cell_id(adjacent_road_cell)
		if GameData.astar.has_point(road_id):
			var opposite_direction = -driveway_direction
			if road_tile.has_connection_in_direction(opposite_direction):
				GameData.astar.connect_points(my_id, road_id)
				print("Vent at ", entrance_cell, " ✓ Connected to road")
			else:
				print("Vent at ", entrance_cell, " ✗ Road doesn't face vent")
		else:
			print("Vent at ", entrance_cell, " Road not in A*")
	else:
		print("Vent at ", entrance_cell, " No road at ", adjacent_road_cell)
	
	# 5. Update overall network connectivity
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

func send_oxygen_packet_to(requester: Node2D) -> bool:
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
