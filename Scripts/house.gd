#extends Building
#
#class_name House
#
#@onready var driveway_marker: Marker2D = $DrivewayMarker
#
#var car_has_spawned: bool = false
#var is_connected_to_workplace: bool = false
#
#var active_cars: int = 0
#@export var max_cars: int = 2
#
#var time_alive: float = 0.0  # For Director tracking
#
#
## =============================================================================
## COLOR SYSTEM
## =============================================================================
#func assign_random_color() -> void:
	#"""Assign a random color from GameData's active palette"""
	#var color_data = GameData.get_random_color_from_palette()
	#set_building_color(color_data["color"], color_data["id"])
	#print("House assigned color_id: %d" % color_id)
#
#
#func _ready():
	#cell_type = "HOUSE"
	#
	## Only assign random color if director didn't already set one
	#if color_id == -1:
		#assign_random_color()
	#
	#super() # Registers footprint and entrance
	#
	#var my_id = GameData.get_cell_id(entrance_cell)
	#GameData.astar.set_point_weight_scale(my_id, 10000000.0)
	#
	#SignalBus.map_changed.connect(_on_map_changed)
	#
	## Wait one frame for AStar graph to register
	#await get_tree().process_frame
	#_on_map_changed()
	#
	#print("House spawned at: ", entrance_cell, " with color_id: ", color_id)
#
#
#func _process(delta: float) -> void:
	#time_alive += delta
#
#
#func rotate_45_degrees() -> void:
	#rotation_degrees += 45
	#if rotation_degrees >= 360:
		#rotation_degrees = 0
	#
	#_on_map_changed()
#
#
## =============================================================================
## CONNECTION MANAGEMENT
## =============================================================================
#func _on_map_changed() -> void:
	#var my_id = GameData.get_cell_id(entrance_cell)
	#
	## 1. Disconnect everything
	#var current_connections = GameData.astar.get_point_connections(my_id)
	#for connection in current_connections:
		#GameData.astar.disconnect_points(my_id, connection)
	#
	## 2. Find driveway direction
	#var marker_pos = driveway_marker.global_position
	#var house_pos = global_position
	#var dir_vec = (marker_pos - house_pos).normalized()
	#var driveway_direction = Vector2i(round(dir_vec.x), round(dir_vec.y))
	#
	## 3. Adjacent road cell
	#var adjacent_road_cell = entrance_cell + driveway_direction
	#
	## 4. Check for road
	#var cell_content = GameData.road_grid.get(adjacent_road_cell)
	#
	#if cell_content != null and cell_content.has_method("has_connection_in_direction"):
		#var road_tile = cell_content
		#var road_id = GameData.get_cell_id(adjacent_road_cell)
		#
		#if GameData.astar.has_point(road_id):
			#var opposite_direction = -driveway_direction
			#
			#if road_tile.has_connection_in_direction(opposite_direction):
				#GameData.astar.connect_points(my_id, road_id)
				#print("House at ", entrance_cell, " ✓ Connected to road")
			#else:
				#print("House at ", entrance_cell, " ✗ Road doesn't face house")
		#else:
			#print("House at ", entrance_cell, " Road not in AStar")
	#else:
		#print("House at ", entrance_cell, " No road at ", adjacent_road_cell)
	#
	## Update connection status
	#update_connection_status()
#
#
## =============================================================================
## DISPATCH LOGIC - COLOR MATCHING
## =============================================================================
#func try_dispatch(target_cell: Vector2i) -> bool:
	#"""Try to dispatch a car to target_cell (must match color)"""
	#if active_cars >= max_cars:
		#return false
	#
	## COLOR CHECK: Only dispatch to matching workplaces
	#var target_workplace = get_workplace_at_cell(target_cell)
	#if not target_workplace or target_workplace.color_id != color_id:
		#return false
	#
	#var start_id = GameData.get_cell_id(entrance_cell)
	#var end_id = GameData.get_cell_id(target_cell)
	#
	#if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
		#var path = GameData.astar.get_id_path(start_id, end_id)
		#if path.size() > 0:
			#active_cars += 1
			#
			#var delay = (active_cars - 1) * 0.5
			#
			#if delay <= 0:
				#spawn_car_bounded_for(target_cell)
			#else:
				#get_tree().create_timer(delay).timeout.connect(
					#func(): spawn_car_bounded_for(target_cell)
				#)
			#car_has_spawned = true
			#return true
	#
	#return false
#
#
#func update_connection_status():
	#"""Check if there's ANY valid path to ANY MATCHING-COLOR workplace"""
	#var was_connected = is_connected_to_workplace
	#var found_any_path = false
	#
	#if GameData.building_grid.is_empty():
		#is_connected_to_workplace = false
		#return
#
	#for cell in GameData.building_grid:
		#if cell == entrance_cell: 
			#continue 
		#
		#if is_cell_an_entrance(cell) and is_destination_a_workplace(cell):
			## COLOR FILTER: Only check matching workplaces
			#var workplace = get_workplace_at_cell(cell)
			#if not workplace or workplace.color_id != color_id:
				#continue
			#
			#var start_id = GameData.get_cell_id(entrance_cell)
			#var end_id = GameData.get_cell_id(cell)
			#
			#if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
				#var path = GameData.astar.get_id_path(start_id, end_id)
				#if path.size() > 0:
					#found_any_path = true
					#break
#
	#is_connected_to_workplace = found_any_path
	#
	#if was_connected != is_connected_to_workplace:
		#print("House at %s (color_id: %d) Connected: %s" % [
			#entrance_cell, 
			#color_id, 
			#is_connected_to_workplace
		#])
#
#
## =============================================================================
## HELPERS
## =============================================================================
#func get_workplace_at_cell(cell: Vector2i) -> Workplace:
	#"""Get the workplace instance at or adjacent to a cell"""
	#for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.ZERO]:
		#var check_cell = cell + dir
		#var building = GameData.building_grid.get(check_cell)
		#if building is Workplace:
			#return building
	#return null
#
#
#func spawn_car_bounded_for(target_cell: Vector2i) -> void:
	#var path_container = Path2D.new()
	#get_parent().add_child(path_container)
	#
	#var car_scene = load("res://Scenes/car.tscn")
	#var car = car_scene.instantiate()
	#car.arrived_home.connect(_on_car_returned)
	#
	#path_container.add_child(car)
	#
	#if car.has_method("setup_path"):
		#car.setup_path(entrance_cell, target_cell)
#
#
#func _on_car_returned() -> void:
	#active_cars -= 1
	#SignalBus.car_returned_home.emit()
