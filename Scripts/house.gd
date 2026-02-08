extends Building

@onready var driveway_marker: Marker2D = $DrivewayMarker
@onready var road_scene: PackedScene = preload("res://Scenes/road_tile.tscn")

var car_has_spawned: bool = false
var is_connected_to_workplace: bool = false # NEW: Logic flag

func _ready():
	cell_type = GameData.CELL_HOUSE
	super() # Registers footprint and entrance
	
	var my_id = GameData.get_cell_id(entrance_cell)
	GameData.astar.set_point_weight_scale(my_id, 10000000.0)
	
	SignalBus.map_changed.connect(_on_map_changed)
	SignalBus.delivery_requested.connect(_on_delivery_requested)
	
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
	# When roads are built/deleted, just update our "Online" status
	var my_id = GameData.get_cell_id(entrance_cell)
	
	# find the only cell where we allow connection from
	# 1. Get the world position of the marker and the house center
	var marker_global = driveway_marker.global_position
	var house_global = global_position # or GameData.map_to_global(entrance_cell)
	
	# 2. Calculate the direction vector in the world
	var dir_vec = (marker_global - house_global).normalized()
	
	# 3. Convert to a grid direction (e.g., (1, 0) or (0, -1))
	var driveway_direction = Vector2i(round(dir_vec.x), round(dir_vec.y))
	var target_road_cell = entrance_cell + driveway_direction
	
	# clean up all existing connections first
	var current_connections = GameData.astar.get_point_connections(my_id)
	for connection in current_connections:
		GameData.astar.disconnect_points(my_id, connection)
	
	# re-establish connection only if the road is there
	var cell_content = GameData.grid.get(target_road_cell)
	if cell_content != null and cell_content is NewRoadTile:
		var road_id = GameData.get_cell_id(target_road_cell)
		
		if GameData.astar.has_point(road_id):
			GameData.astar.connect_points(my_id, road_id)
	update_connection_status()

func _on_delivery_requested(target_cell: Vector2i) -> void:
	# LOGIC: "I heard a request. Am I busy? Am I even connected to the roads?"
	if car_has_spawned or not is_connected_to_workplace:
		return
	
	# If we are free and connected, try to path to THAT specific workplace
	var start_id = GameData.get_cell_id(entrance_cell)
	var end_id = GameData.get_cell_id(target_cell)
	
	if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
		var path = GameData.astar.get_id_path(start_id, end_id)
		if path.size() > 0:
			spawn_car_bounded_for(target_cell)
			car_has_spawned = true

# --- 2. THE CONNECTION CHECK (Replaces your old search loop) ---

func update_connection_status():
	"""Checks if there is ANY valid path to ANY workplace, but DOES NOT spawn a car."""
	var found_any_path = false
	
	if GameData.grid.is_empty():
		is_connected_to_workplace = false
		return

	for cell in GameData.grid:
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
	car_has_spawned = false
	# No need to search here! We just wait for the next Workplace Ping.
