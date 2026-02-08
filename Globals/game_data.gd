extends Node

const CELL_SIZE: Vector2 = Vector2(64, 64)

const CELL_BUILDING = "BUILDING"
const CELL_WORKPLACE_ENTRANCE = "WORKPLACE_ENTRANCE"
const CELL_HOUSE_ENTRANCE = "HOUSE_ENTRANCE"
const CELL_HOUSE = "HOUSE"
const CELL_ROAD = "ROAD"

# this dictionary will store every cell status.
# key: vectow2i (cell coordinates)
var grid: Dictionary = {}

var road_connections: Dictionary = {}

var astar = AStar2D.new()

func is_cell_empty(cell: Vector2i) -> bool:
	# if the dictoinary has that cell, then "no its not empty"
	return not grid.has(cell)

func set_cell(cell: Vector2i, type: String) -> void:
	grid[cell] = type

func remove_cell(cell: Vector2i) -> void:
	grid.erase(cell)

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(pos.x / GameData.CELL_SIZE.x),
		floori(pos.y / GameData.CELL_SIZE.y)
	)

func get_cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) * CELL_SIZE) + (CELL_SIZE / 2.0)

func add_road_connection(cell_a: Vector2i, cell_b: Vector2i) -> void:
	var dir_a_to_b = cell_b - cell_a
	var dir_b_to_a = cell_a - cell_b
	
	if not road_connections.has(cell_a): road_connections[cell_a] = []
	if not road_connections.has(cell_b): road_connections[cell_b] = []
	
	if not dir_a_to_b in road_connections[cell_a]:
		road_connections[cell_a].append(dir_a_to_b)
	if not dir_b_to_a in road_connections[cell_b]:
		road_connections[cell_b].append(dir_b_to_a)

func remove_road_connections(cell: Vector2i) -> void:
	if road_connections.has(cell):
		# Tell neighbors this cell is gone
		for dir in road_connections[cell]:
			var neighbor = cell + dir
			if road_connections.has(neighbor):
				var opposite_dir = -dir
				road_connections[neighbor].erase(opposite_dir)
		road_connections.erase(cell)


func print_grid_state():
	print("--- CURRENT GRID DATA ---")
	for cell in grid:
		var value = grid[cell]
		# If the value is a node (like a road), we print its name
		# If it's a string (like "building"), we print that string
		var display_value = value.name if value is Node else str(value)
		print("Cell ", cell, ": ", display_value)
	print("-------------------------")
	

# A* Logic

# Add this version to handle markers/off-grid points
func get_position_id(pos: Vector2) -> int:
	return str(pos).hash()

func add_marker_point(pos: Vector2) -> void:
	var id = get_position_id(pos)
	if not astar.has_point(id):
		astar.add_point(id, pos)

func get_cell_id(cell: Vector2) -> int:
	return str(cell).hash()

func add_navigation_point(cell: Vector2i) -> void:
	var id = get_cell_id(cell)
	if not astar.has_point(id):
		astar.add_point(id, get_cell_center(cell))

func connect_navigation_points(cell_a: Vector2i, cell_b: Vector2i) -> void:
	# THE BARRIER LOGIC:
	# If either cell is a HOUSE, we do NOT allow them to connect to neighbors.
	# This prevents other cars from finding a path through the house.
	if grid.get(cell_a) == CELL_HOUSE or grid.get(cell_b) == CELL_HOUSE:
		return 

	var id_a = get_cell_id(cell_a)
	var id_b = get_cell_id(cell_b)
	if astar.has_point(id_a) and astar.has_point(id_b):
		astar.connect_points(id_a, id_b)
