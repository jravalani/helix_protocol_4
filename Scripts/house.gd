extends Building

class_name House

@onready var driveway_marker: Marker2D = $DrivewayMarker
@onready var road_scene: PackedScene = preload("res://Scenes/road_tile.tscn")

var car_has_spawned: bool = false
var is_connected_to_workplace: bool = false # NEW: Logic flag

var active_cars: int = 0
@export var max_cars: int = 2

func _ready():
	cell_type = "HOUSE"
	super() # Registers footprint and entrance
	
	var my_id = GameData.get_cell_id(entrance_cell)
	GameData.astar.set_point_weight_scale(my_id, 10000000.0)
	
	SignalBus.map_changed.connect(_on_map_changed)
	#SignalBus.delivery_requested.connect(_on_delivery_requested)
	
	# WAIT one frame so the AStar graph can register the new driveway point
	# before we check if we are connected!
	await get_tree().process_frame
	_on_map_changed()
	
	print("House spawned at: ", global_position, " on Layer: ", collision_layer)

func rotate_45_degrees() -> void:
	
	# 2. Perform the rotation on the parent
	rotation_degrees += 45
	if rotation_degrees >= 360:
		rotation_degrees = 0
	
	# update the a* logic after rotating!
	_on_map_changed()

# --- 1. THE SIGNAL HANDLERS ---

func _on_map_changed() -> void:
	var my_id = GameData.get_cell_id(entrance_cell)
	
	# 1. DISCONNECT EVERYTHING
	var current_connections = GameData.astar.get_point_connections(my_id)
	for connection in current_connections:
		GameData.astar.disconnect_points(my_id, connection)
	
	# 2. Find the driveway direction
	var marker_pos = driveway_marker.global_position
	var house_pos = global_position
	var dir_vec = (marker_pos - house_pos).normalized()
	var driveway_direction = Vector2i(round(dir_vec.x), round(dir_vec.y))
	
	# 3. The adjacent road cell (next to entrance)
	var adjacent_road_cell = entrance_cell + driveway_direction
	
	# 4. Check if there's a road there
	var cell_content = GameData.road_grid.get(adjacent_road_cell)
	
	if cell_content != null and cell_content is NewRoadTile:
		var road_tile = cell_content as NewRoadTile
		var road_id = GameData.get_cell_id(adjacent_road_cell)
		
		if GameData.astar.has_point(road_id):
			# KEY CHECK: Does the road have a visual connection pointing BACK to the house?
			var opposite_direction = -driveway_direction
			
			if road_tile.has_connection_in_direction(opposite_direction):
				# Road is visually connected to the house!
				GameData.astar.connect_points(my_id, road_id)
				print("House at ", entrance_cell, " ✓ Connected to road at ", adjacent_road_cell)
			else:
				# Road exists but doesn't face the house
				print("House at ", entrance_cell, " ✗ Road doesn't face house")
				print("  Driveway faces: ", driveway_direction)
				print("  Road connections: ", road_tile.get_connection_directions())
		else:
			print("House at ", entrance_cell, " Road not in AStar")
	else:
		print("House at ", entrance_cell, " No road at ", adjacent_road_cell)
	
	update_connection_status()

## How It Works:
#
#**Example 1: Perpendicular Highway (Should NOT connect)**
#```
#House entrance: (5, 5), driveway faces RIGHT (+1, 0)
#Highway at: (6, 5)
#Highway connections: [(0, -1), (0, 1)]  // UP and DOWN only
#
#Check: Does highway have connection (-1, 0)? NO
#Result: ✗ Not connected!
#```
#
#**Example 2: Aligned Road (Should connect)**
#```
#House entrance: (5, 5), driveway faces RIGHT (+1, 0)
#Road at: (6, 5)  
#Road connections: [(-1, 0), (1, 0)]  // LEFT and RIGHT
#
#Check: Does road have connection (-1, 0)? YES
#Result: ✓ Connected!
	
func try_dispatch(target_cell: Vector2i) -> bool:
	# LOGIC: "I heard a request. Am I busy? Am I even connected to the roads?"
	if active_cars >= max_cars or not is_connected_to_workplace:
		return false
	
	# If we are free and connected, try to path to THAT specific workplace
	var start_id = GameData.get_cell_id(entrance_cell)
	var end_id = GameData.get_cell_id(target_cell)
	
	if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
		var path = GameData.astar.get_id_path(start_id, end_id)
		if path.size() > 0:
			active_cars += 1
			
			var delay = (active_cars - 1) * 0.5
			
			if delay <= 0:
				spawn_car_bounded_for(target_cell)
			else:
				get_tree().create_timer(delay).timeout.connect(
					func(): spawn_car_bounded_for(target_cell)
				)
			car_has_spawned = true
			return true
			
	return false

# --- 2. THE CONNECTION CHECK (Replaces your old search loop) ---

func update_connection_status():
	"""Checks if there is ANY valid path to ANY workplace, but DOES NOT spawn a car."""
	var was_connected = is_connected_to_workplace
	var found_any_path = false
	
	if GameData.building_grid.is_empty():
		is_connected_to_workplace = false
		return

	for cell in GameData.building_grid:
		if cell == entrance_cell: continue 
		
		if is_cell_an_entrance(cell) and is_destination_a_workplace(cell):
			var start_id = GameData.get_cell_id(entrance_cell)
			var end_id = GameData.get_cell_id(cell)
			
			if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
				var path = GameData.astar.get_id_path(start_id, end_id)
				if path.size() > 0:
					found_any_path = true
					break # We found at least one path, that's enough!

	is_connected_to_workplace = found_any_path
	print("House at ", entrance_cell, " Connected: ", is_connected_to_workplace)

# --- 3. THE ACTION (Only handles spawning) ---

func spawn_car_bounded_for(target_cell: Vector2i) -> void:
	var path_container = Path2D.new()
	get_parent().add_child(path_container)
	
	var car_scene = load("res://Scenes/car.tscn")
	var car = car_scene.instantiate()
	car.arrived_home.connect(_on_car_returned)
	
	path_container.add_child(car)
	
	if car.has_method("setup_path"):
		car.setup_path(entrance_cell, target_cell)
		
func _on_car_returned() -> void:
	active_cars -= 1
	SignalBus.car_returned_home.emit()
	# No need to search here! We just wait for the next Workplace Ping.
