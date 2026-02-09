extends Node

const CELL_SIZE: Vector2 = Vector2(64, 64)

const START_SIZE = 20
const MAX_WIDTH = 52
const MAX_HEIGHT = 38

var map_zoom_iterations = 0

var current_map_size = Rect2i(-16, -9, 32, 18)

# this dictionary will store every cell status.
# key: vectow2i (cell coordinates)
var road_grid: Dictionary = {}
var building_grid: Dictionary = {}

var road_connections: Dictionary = {}

var astar = AStar2D.new()

func is_road_cell_empty(cell: Vector2i) -> bool:
	# if the dictoinary has that cell, then "no its not empty"
	return not road_grid.has(cell)

func set_road_cell(cell: Vector2i, type: String) -> void:
	road_grid[cell] = type

func remove_road_cell(cell: Vector2i) -> void:
	road_grid.erase(cell)

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
	var b_a = building_grid.get(cell_a)
	var b_b = building_grid.get(cell_b)

	# NEW RULE: You cannot connect two buildings directly.
	# At least one of the cells MUST be a road.
	if b_a is Building and b_b is Building:
		return 
	# Standard connection logic follows...

	var id_a = get_cell_id(cell_a)
	var id_b = get_cell_id(cell_b)
	if astar.has_point(id_a) and astar.has_point(id_b):
		astar.connect_points(id_a, id_b)

# Map growth function
func increase_map_size() -> void:
	if current_map_size.size.x < MAX_WIDTH:
		map_zoom_iterations += 1
		print(map_zoom_iterations)
		current_map_size = current_map_size.grow(1)
		SignalBus.increase_map_size.emit(current_map_size)

func is_blocked_by_house(building: Variant, cell: Vector2i) -> bool:
	# If there's no building, it's not blocked
	if not building is Building: 
		return false
	
	# If it's a House, we only allow navigation if this specific cell is the entrance
	if building is House:
		return cell != building.entrance_cell
		
	return false
