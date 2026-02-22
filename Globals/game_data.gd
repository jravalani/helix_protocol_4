extends Node

const CELL_SIZE: Vector2 = Vector2(64, 64)
const START_SIZE = 20
const MAX_WIDTH = 52
const MAX_HEIGHT = 38

const MAX_PRESSURE: float = 100.0
const BASE_RATE: float = 0.025
var MAX_PRESSURE_PHASE: int = 4

const MAX_PIPE_UPGRADES: int = 3
const PIPE_UPGRADE_COSTS = [150, 300, 450]

const MAX_HULL_SHIELD_UPGRADES: int = 4
const HULL_SHIELD_UPGRADE_COSTS = [300, 500, 800, 1200]

## Building type constants
#enum BuildingType {
	#VENT,           # Oxygen source
	#RESEARCH_HUB,   # +50% data, -20% oxygen
	#DATA_CENTER,    # +100% data, +50% oxygen, fractures nearby pipes
	#RELAY_HUB,      # Speed boost, no data
	#ROCKET          # Final objective
#}

## Building type properties
#const BUILDING_TYPE_DATA = {
	#BuildingType.VENT: {
		#"name": "Vent",
		#"color": Color.CYAN,
		#"packet_interval": 5.0,
		#"packet_amount": 1
	#},
	#BuildingType.RESEARCH_HUB: {
		#"name": "Research Hub",
		#"color": Color.GREEN,
		#"data_multiplier": 1.5,
		#"oxygen_multiplier": 0.8
	#},
	#BuildingType.DATA_CENTER: {
		#"name": "Data Center",
		#"color": Color.MAGENTA,
		#"data_multiplier": 2.0,
		#"oxygen_multiplier": 1.5,
		#"fracture_radius": 5
	#},
	#BuildingType.RELAY_HUB: {
		#"name": "Relay Hub",
		#"color": Color.YELLOW,
		#"speed_boost": 1.5,
		#"oxygen_multiplier": 0.5
	#}
#}
var current_pressure: float = 0.0
var current_pressure_phase: int = 1

var current_pipe_upgrade_level: int = 0

var current_road_tiles: int = 25
var total_data: int = 0
var score_to_next_reward: int = 8

var current_hull_shield_level: int = 1
var hull_schield_integrity: float = 100.0

var map_stages = [
	Rect2i(-8, -4, 16, 8),
	Rect2i(-11, -6, 22, 12),
	Rect2i(-13, -7, 26, 14),
	Rect2i(-16, -9, 32, 18)
]
var current_stage = 0
var current_map_size = Rect2i(-8, -4, 16, 8)

# Grid dictionaries - store every cell status
# key: Vector2i (cell coordinates)
var road_grid: Dictionary = {}
var building_grid: Dictionary = {}
var road_connections: Dictionary = {}
var influence_grid: Dictionary = {}
var astar = AStar2D.new()


func _ready() -> void:
	pass

func is_road_cell_empty(cell: Vector2i) -> bool:
	# if the dictionary has that cell, then "no its not empty"
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

func remove_navigation_point(cell: Vector2i) -> void:
	var id = get_cell_id(cell)
	if astar.has_point(id):
		astar.remove_point(id)

# Map growth function
func increase_map_size() -> void:
	if current_stage < map_stages.size() - 1:
		current_stage += 1
		current_map_size = map_stages[current_stage]
		SignalBus.increase_map_size.emit(current_map_size)
	else:
		print("Max Capacity Reached")

func is_blocked_by_building(building: Variant, cell: Vector2i) -> bool:
	"""Check if a cell is blocked by a building (only entrance cells are navigable)"""
	# If there's no building, it's not blocked
	if not building is Building: 
		return false
	
	# For Vents (1x1), only allow navigation if this is the entrance cell
	if building is Vent:
		return cell != building.entrance_cell
	
	# For Hubs (multi-cell), only allow navigation if this is the entrance cell
	if building is Hub:
		return cell != building.entrance_cell
		
	# For any other Building, same rule applies
	return cell != building.entrance_cell

#region Tile Influence
func apply_influence(tile: Vector2i, type: String) -> void:
	var radius: int = 0
	var strength: int = 0
	var is_penalty: bool = false
	
	match type:
		"rocket":
			radius = 3
			strength = 100000
			is_penalty = true
		"hub":
			radius = 6 # Wide spacing for hubs
			strength = 100
			is_penalty = true
		"vent":
			radius = 2 # Tight clustering for vents
			strength = 80
			is_penalty = false # This is a BONUS!
		"road":
			radius = 2
			strength = 60
			is_penalty = false

	# apply certain strength on tile in radius
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var current_tile = tile + Vector2i(x, y)
			var dist = abs(x) + abs(y)
			
			if dist > radius:
				continue
				
			var falloff_value = float(radius - dist + 1 ) / radius
			var final_value = strength * falloff_value
			
			if is_penalty:
				final_value *= -1
			
			# max absolute value
			var current_score = influence_grid.get(current_tile, 0.0)
			var new_score: float
			if abs(final_value) > abs(current_score):
				new_score = final_value
			else:
				new_score = current_score
			
			influence_grid[current_tile] = new_score
#endregion

#region Hull Shield Multiplier
func get_hull_shield_multiplier() -> float:
	# every shield upgrade will increase current integrity by 20%
	var base_protection = current_hull_shield_level * 0.2
	
	# get current shield integrity and calculate the integrity factor
	# example at 10 minute mark if integriy is at 90 so 90/100 = 0.9 and upgrade at level 1
	# so the multiplier would be (1 - ( 0.2 * 0.9 ) ) = 0.82
	# as integrity degrades the shield multiplier value will decrease 
	var integrity_factor = hull_schield_integrity / 100.0
	
	return max(0.2, 1.0 - (base_protection * integrity_factor))
