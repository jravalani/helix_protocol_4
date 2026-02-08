# ============================================
# road_builder.gd
#
# ROLE: The "Worker" that modifies the world.
# RESPONSIBILITY: Handles mouse input, checks the GameData "Library" for obstacles,
# and places/removes RoadTile objects.
# ============================================

extends Node2D

class_name NewRoadBuilder

# we now use value from gamedata.gd
#const CELL_SIZE: Vector2 = Vector2(32, 32)

# Directions mapping to help with neighbor detection logic
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
	var mouse_cell = mouse_to_cell() # This is the cell the cursor is in
	var cell_type = GameData.grid.get(mouse_cell)
	if cell_type != null and not cell_type is NewRoadTile:
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
	# floor() creates clean boundaries at 0, 64, 128, etc.
	return Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)

func build_road(cell: Vector2i) -> void:
	# 1. THE GATEKEEPER CHECK
	var existing_stuff = GameData.grid.get(cell)
	var was_entrance := false
	
	# Check if the spot is taken by a String (HOUSE, BUILDING, ENTRANCE)
	# We use typeof because your grid holds both Objects (Roads) and Strings (Buildings)
	if existing_stuff != null and typeof(existing_stuff) == TYPE_STRING:
		if existing_stuff in [
			GameData.CELL_HOUSE,
			#GameData.CELL_HOUSE_ENTRANCE,
			GameData.CELL_BUILDING
		]:
			print("access denied: cell", cell, "belong to a building")
			return
		if existing_stuff == GameData.CELL_WORKPLACE_ENTRANCE:
			was_entrance = true

	# 2. Get or Create the road (Your existing logic)
	var current_road = GameData.grid.get(cell)
	
	if not current_road is NewRoadTile:
		current_road = road_tile.instantiate()
		current_road.position = GameData.get_cell_center(cell)
		current_road.set_cell(cell)
		add_child(current_road)
			
		if was_entrance:
			current_road.is_entrance = true
			
		GameData.grid[cell] = current_road
		GameData.add_navigation_point(cell)
	
	# 3. THE HANDSHAKE (Connection logic)
	if last_build_cell != Vector2i(-1, -1) and last_build_cell != cell:
		var previous_road = GameData.grid.get(last_build_cell)
		# Ensure the previous cell was actually a road, not a building we just skipped
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
	print("Signal emitted from roadbuilder")

	last_build_cell = cell


#func is_connection_allowed(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	#return true

func build_road_line(target_cell: Vector2i) -> void:
	if last_build_cell == Vector2i(-1, -1):
		build_road(target_cell)
		return

	# Calculate distance
	var diff = target_cell - last_build_cell
	var steps = max(abs(diff.x), abs(diff.y))
	
	# If steps > 1, we are skipping cells!
	# We loop through and build every intermediate tile.
	for i in range(1, steps + 1):
		var t = float(i) / steps
		# Lerp between the last anchor and the new target
		var intermediate = Vector2(last_build_cell).lerp(Vector2(target_cell), t).round()
		build_road(Vector2i(intermediate))

func remove_road(cell: Vector2i) -> void:
	var object_at_cell = GameData.grid.get(cell)
	
	# Use the new class name consistently
	if object_at_cell is NewRoadTile:
		if object_at_cell.is_permanent:
			return
		# 1. TELL NEIGHBORS TO DISCONNECT
		# We look at every connection this road had
		for dir in object_at_cell.manual_connections:
			var neighbor_cell = cell + dir
			var neighbor = GameData.grid.get(neighbor_cell)
			
			# If the neighbor exists and is a road, tell it to drop the connection
			if neighbor is NewRoadTile:
				neighbor.remove_connection(-dir)
		
		# 2. CLEAN UP ASTAR
		var id = GameData.get_cell_id(cell)
		if GameData.astar.has_point(id):
			GameData.astar.remove_point(id)
		
		# 3. ERASE FROM WORLD
		object_at_cell.queue_free()
		GameData.grid.erase(cell)
		
	SignalBus.map_changed.emit.call_deferred()
	print("Signal emitted from roadremover")
		
# --- Helper Functions for Clean Logic ---

func _connect_two_points(cell_a: Vector2i, cell_b: Vector2i):
	var road_a = GameData.grid.get(cell_a)
	var road_b = GameData.grid.get(cell_b)
	var dir_to_b = cell_b - cell_a
	
# VISUALS: Only call add_connection if the object is actually a Road node
	if road_a is NewRoadTile:
		road_a.add_connection(dir_to_b)
	if road_b is NewRoadTile:
		road_b.add_connection(-dir_to_b)
	
	var id_a = GameData.get_cell_id(cell_a)
	var id_b = GameData.get_cell_id(cell_b)
	
	#if not GameData.astar.are_points_connected(id_a, id_b):
		#GameData.astar.connect_points(id_a, id_b)
	# Ensure both points exist in AStar before connecting
	if GameData.astar.has_point(id_a) and GameData.astar.has_point(id_b):
		if not GameData.astar.are_points_connected(id_a, id_b):
			GameData.astar.connect_points(id_a, id_b)

func _connect_to_entrance(road_cell: Vector2i, entrance_cell: Vector2i, dir: Vector2i):
	var road = GameData.grid.get(road_cell)
	road.add_connection(dir)
	
	var id_road = GameData.get_cell_id(road_cell)
	var id_ent = GameData.get_cell_id(entrance_cell)
	if not GameData.astar.are_points_connected(id_road, id_ent):
		GameData.astar.connect_points(id_road, id_ent)
