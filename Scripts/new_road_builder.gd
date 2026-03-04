# ============================================
# road_builder.gd
# ============================================

extends Node2D

class_name NewRoadBuilder

const DIRS := {
	Vector2i.UP: Vector2i.UP,
	Vector2i.DOWN: Vector2i.DOWN,
	Vector2i.LEFT: Vector2i.LEFT,
	Vector2i.RIGHT: Vector2i.RIGHT,
	Vector2i(1, 1): Vector2i(1, 1),
	Vector2i(1, -1): Vector2i(1, -1),
	Vector2i(-1, 1): Vector2i(-1, 1),
	Vector2i(-1, -1): Vector2i(-1, -1)
}

@onready var road_tile = preload("res://Scenes/road_tile.tscn")

var last_build_cell := Vector2i(-1, -1)
var last_remove_cell := Vector2i(-1, -1)

var ghost_road: NewRoadTile

func _ready() -> void:
	ghost_road = road_tile.instantiate()
	ghost_road.modulate = Color(1, 1, 1, 0.5)
	ghost_road.z_index = 10
	add_child(ghost_road)
	ghost_road.hide()
	
func _update_ghost_visuals(ghost_cell: Vector2i):
	var mouse_cell = mouse_to_cell() 
	
	# CHANGE: Check building_grid for obstacles and road_grid for existing roads
	var existing_building = GameData.building_grid.get(mouse_cell)
	var existing_road = GameData.road_grid.get(mouse_cell)
	
	if existing_building != null:
		ghost_road.modulate = Color(1, 0, 0, 0.5) # Red for "Blocked"
	else:
		ghost_road.modulate = Color(1, 1, 1, 0.5) # Normal ghost
		ghost_road.manual_connections.clear()

	if last_build_cell != Vector2i(-1, -1) and ghost_cell != last_build_cell:
		var dir_to_anchor = last_build_cell - ghost_cell
		if max(abs(dir_to_anchor.x), abs(dir_to_anchor.y)) <= 1:
			ghost_road.add_connection(dir_to_anchor)
			
	ghost_road.update_visuals()

func mouse_to_cell() -> Vector2i:
	var mouse_pos = get_global_mouse_position()
	return Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)

func build_road(cell: Vector2i) -> void:
	print("=== BUILD_ROAD START ===")
	print("Cell: ", cell)
	
	# 1. THE GATEKEEPER CHECK (Now checking building_grid)
	var building_at_cell = GameData.building_grid.get(cell)
	print("Building at cell: ", building_at_cell)
	
	var was_entrance := false
	
	if building_at_cell != null:
		print("Building exists, checking if it's a Building type...")
		if building_at_cell is Building:
			if cell != building_at_cell.entrance_cell:
				print("ACCESS DENIED: cell belongs to building body")
				return
			else:
				print("This is an entrance cell, allowing road")
				was_entrance = true
	else:
		print("No building at this cell")
	
	# 2. Get or Create the road (Now using road_grid)
	var current_road = GameData.road_grid.get(cell)
	print("Current road at cell: ", current_road)
	
	if not current_road is NewRoadTile:
		print("No road exists yet, checking resources...")
		
		if GameData.current_pipe_count > 0:
			print("Resources available, creating road...")
			
			ResourceManager.spend_tile()
			
			current_road = road_tile.instantiate()
			print("Road instantiated: ", current_road)
			
			current_road.position = GameData.get_cell_center(cell)
			print("Road position: ", current_road.position)
			
			current_road.set_cell(cell)
			add_child(current_road)
			print("Road added as child")
				
			if was_entrance:
				current_road.is_entrance = true
				
			# CHANGE: Save to road_grid
			GameData.road_grid[cell] = current_road
			GameData.apply_influence(cell, "road")
			GameData.add_navigation_point(cell)
			print("ROAD CREATED SUCCESSFULLY!")
		else:
			print("Out of Tiles")
			return
	else:
		print("Road already exists at this cell")
	
	# 3. THE HANDSHAKE (Connection logic using road_grid)
	if last_build_cell != Vector2i(-1, -1) and last_build_cell != cell:
		var previous_road = GameData.road_grid.get(last_build_cell)
		if previous_road is NewRoadTile:
			var dir_to_current = cell - last_build_cell
			if max(abs(dir_to_current.x), abs(dir_to_current.y)) <= 1:
				previous_road.add_connection(dir_to_current)
				current_road.add_connection(-dir_to_current)
				
				var id_a = GameData.get_cell_id(last_build_cell)
				var id_b = GameData.get_cell_id(cell)
				if not GameData.astar.are_points_connected(id_a, id_b):
					GameData.astar.connect_points(id_a, id_b)
	
	SignalBus.map_changed.emit.call_deferred()
	last_build_cell = cell
	print("=== BUILD_ROAD END ===")

func build_road_line(target_cell: Vector2i) -> void:
	if last_build_cell == Vector2i(-1, -1):
		build_road(target_cell)
		return

	var diff = target_cell - last_build_cell
	var steps = max(abs(diff.x), abs(diff.y))
	
	for i in range(1, steps + 1):
		var t = float(i) / steps
		var intermediate = Vector2(last_build_cell).lerp(Vector2(target_cell), t).round()
		build_road(Vector2i(intermediate))

func remove_road(cell: Vector2i) -> void:
	# CHANGE: Look in road_grid
	var object_at_cell = GameData.road_grid.get(cell)
	
	if object_at_cell is NewRoadTile:
		
		if object_at_cell.is_fractured:
			return
		
		if object_at_cell.is_permanent:
			return
		
		ResourceManager.refund_tile()
		
		for dir in object_at_cell.manual_connections:
			var neighbor_cell = cell + dir
			var neighbor = GameData.road_grid.get(neighbor_cell)
			
			if neighbor is NewRoadTile:
				neighbor.remove_connection(-dir)
		
		var id = GameData.get_cell_id(cell)
		if GameData.astar.has_point(id):
			GameData.astar.remove_point(id)
		
		object_at_cell.queue_free()
		# CHANGE: Erase from road_grid
		GameData.road_grid.erase(cell)
		
	SignalBus.map_changed.emit.call_deferred()
		
# --- Helper Functions ---

func _connect_two_points(cell_a: Vector2i, cell_b: Vector2i):
	# CHANGE: Use road_grid
	var road_a = GameData.road_grid.get(cell_a)
	var road_b = GameData.road_grid.get(cell_b)
	var dir_to_b = cell_b - cell_a
	
	if road_a is NewRoadTile:
		road_a.add_connection(dir_to_b)
	if road_b is NewRoadTile:
		road_b.add_connection(-dir_to_b)
	
	var id_a = GameData.get_cell_id(cell_a)
	var id_b = GameData.get_cell_id(cell_b)
	
	if GameData.astar.has_point(id_a) and GameData.astar.has_point(id_b):
		if not GameData.astar.are_points_connected(id_a, id_b):
			GameData.astar.connect_points(id_a, id_b)

func _connect_to_entrance(road_cell: Vector2i, entrance_cell: Vector2i, dir: Vector2i):
	# CHANGE: Use road_grid
	var road = GameData.road_grid.get(road_cell)
	if road:
		road.add_connection(dir)
	
	var id_road = GameData.get_cell_id(road_cell)
	var id_ent = GameData.get_cell_id(entrance_cell)
	if GameData.astar.has_point(id_road) and GameData.astar.has_point(id_ent):
		if not GameData.astar.are_points_connected(id_road, id_ent):
			GameData.astar.connect_points(id_road, id_ent)
