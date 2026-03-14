extends Node

## =============================================================================
## GRID & SPATIAL CONSTANTS
## =============================================================================

const CELL_SIZE: Vector2 = Vector2(64, 64)
const MAX_WIDTH = 52
const MAX_HEIGHT = 38

## Map expansion stages (progressive unlock areas)
var map_stages = [
	Rect2i(-10, -6, 20, 12),  # Stage 0: Starting area
	Rect2i(-13, -7, 26, 14),  # Stage 1: First expansion
	Rect2i(-16, -9, 32, 18),  # Stage 2: Second expansion
	Rect2i(-20, -11, 40, 22)  # Stage 3: Full map
]

## =============================================================================
## BUILDING LIMITS & COUNTS
## =============================================================================

const MAX_VENTS = 50
const MAX_HUBS = 12
const START_SIZE = 20

var current_hub_count: int = 0
var current_vent_count: int = 0
var current_pipe_count: int = 50

## =============================================================================
## ZONE SYSTEM
## =============================================================================

enum Zone {
	CORE,
	INNER,
	OUTER,
	FRONTIER
}

const ZONE_REINFORCE_COSTS = [150, 200, 250, 300]

var active_reinforcement_timer: SceneTreeTimer = null
var current_reinforced_zone: int = -1
var reinforcement_version: int = 0

## =============================================================================
## PRESSURE SYSTEM
## =============================================================================

const MAX_PRESSURE: float = 100.0
const BASE_RATE: float = 0.025
var MAX_PRESSURE_PHASE: int = 10

var current_pressure: float = 0.0
var current_pressure_phase: int = 0

var fracture_wave_active: bool = false

# ── Rocket Segment Passive Effects ──────────────────────────────
var global_vent_interval_multiplier: float = 1.0  # Segments 1 & 3 multiply by 0.8
var rocket_fracture_reduction: float = 0.0         # Segment 2 sets to 0.2
var hub_rate_window: float = 60.0                  # Segment 3 reduces to 40.0
var pressure_rate_multiplier: float = 1.0          # Segment 4 sets to 0.85

## =============================================================================
## UPGRADE SYSTEM
## =============================================================================

## Hub upgrades
const MAX_HUB_UPGRADES: int = 3
const HUB_UPGRADE_COSTS = [50, 100, 120]

## Spawn costs (scale per purchase)
const HUB_SPAWN_BASE_COST: int = 100
const HUB_SPAWN_COST_INCREMENT: int = 20
const VENT_SPAWN_BASE_COST: int = 10
const VENT_SPAWN_COST_INCREMENT: int = 5

var current_hub_spawn_cost: int = HUB_SPAWN_BASE_COST
var current_vent_spawn_cost: int = VENT_SPAWN_BASE_COST

## Pipe upgrades (increase capacity/flow)
const MAX_PIPE_UPGRADES: int = 3
const PIPE_UPGRADE_COSTS = [150, 300, 450]
var current_pipe_upgrade_level: int = 0

## Hull/Shield upgrades (protect against damage)
const MAX_HULL_SHIELD_UPGRADES: int = 4
const HULL_SHIELD_UPGRADE_COSTS = [300, 500, 800, 1200]
var current_hull_shield_level: int = 1
var hull_schield_integrity: float = 100.0

## Pipe repair costs
const SINGLE_PIPE_REPAIR_COST: int = 5
var auto_repair_enabled: bool = false
var data_reserve_for_auto_repairs: int = 0

## =============================================================================
## ECONOMY & PROGRESSION
## =============================================================================

var lifetime_data_earned: int = 0
var total_data: int = 25000
var previous_threshold: int = 0
var score_to_next_reward: int = 30

## =============================================================================
## SYSTEM METRICS (updated per frame)
## =============================================================================

var total_hub_backlog: int = 0
var total_backlog: int = 0
var average_vent_utilization: float = 0.0
var active_packet_count: int = 0

## =============================================================================
## MAP STATE
## =============================================================================

var current_stage: int = 0
var current_map_size: Rect2i = Rect2i(-10, -6, 20, 12)
var rocket_cell: Vector2i = Vector2i(0, 0)

## =============================================================================
## GRID DATA STRUCTURES
## =============================================================================
## All use Vector2i as keys for cell coordinates

var road_grid: Dictionary = {}           # Tracks built roads
var fractured_pipes: Dictionary = {}     # Tracks damaged pipes
var building_grid: Dictionary = {}       # Tracks placed buildings
var road_connections: Dictionary = {}    # Tracks road network connectivity
var influence_grid: Dictionary = {}      # Tracks zone influence

var astar: AStar2D = AStar2D.new()       # Pathfinding graph

## =============================================================================
## ROCKET 
## =============================================================================

var current_rocket_phase: int = 0

const ROCKET_UPGRADES = {
	1: {
		"name": "Structural Frame",
		"cost": 300,
		"description": "Reinforces hull. Vents spin 20% faster.",
		"shield_boost": 1,
		"vent_interval_multiplier": 0.8
	},
	2: {
		"name": "Conduit Amplifier",
		"cost": 500,
		"description": "Reduces pipe and hub fracture chance by 20%.",
		"fracture_chance_reduction": 0.2
	},
	3: {
		"name": "Oxygen Overdrive",
		"cost": 800,
		"description": "Vents spin 20% faster. Hubs process requests faster.",
		"vent_interval_multiplier": 0.8,
		"rate_window_reduction": 20.0
	},
	4: {
		"name": "Pressure Regulator",
		"cost": 1200,
		"description": "Slows planetary pressure gain by 15%. Further reinforces hull.",
		"pressure_rate_reduction": 0.15,
		"shield_boost": 1
	},
	5: {
		"name": "Launch Control",
		"cost": 1500,
		"description": "Final phase: Prepare for launch.",
		"is_final": true
	}
}

var metric_timer := 0.0

var input_consumed: bool = false

func _ready() -> void:
	randomize()

func _process(delta: float) -> void:
	metric_timer += delta
	if metric_timer >= 1.0:
		update_system_metrics()
		metric_timer = 0.0

func update_system_metrics() -> void:
	"""Calculate global system metrics once per second."""
	# Calculate total hub backlog
	total_hub_backlog = 0
	var hubs = get_tree().get_nodes_in_group("hubs")
	for hub in hubs:
		if "oxygen_backlog" in hub:
			total_hub_backlog += hub.oxygen_backlog

	# Calculate average vent utilization
	var vents = get_tree().get_nodes_in_group("vents")
	if vents.size() > 0:
		var total_util = 0.0
		for vent in vents:
			if vent.has_method("get_current_capacity") and vent.has_method("get_max_capacity"):
				var max_cap = vent.get_max_capacity()
				if max_cap > 0:
					total_util += float(vent.get_current_capacity()) / max_cap
		average_vent_utilization = total_util / vents.size()
	else:
		average_vent_utilization = 0.0

	# Count active packets
	active_packet_count = get_tree().get_nodes_in_group("packets").size()

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

func get_cell_id(cell: Vector2i) -> int:
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

func get_playable_rect() -> Rect2i:
	var bounds = current_map_size
	var pad_left   := 0
	var pad_right  := 0
	var pad_top    := 0
	var pad_bottom := 0
	match current_stage:
		1:
			pad_left  = 1
			pad_right = 1
		2:
			pad_left   = 1
			pad_right  = 1
			pad_bottom = 1
		3:
			pad_left   = 1
			pad_right  = 1
			pad_top    = 1
			pad_bottom = 1
	return Rect2i(
		bounds.position.x + pad_left,
		bounds.position.y + 1 + pad_top,
		bounds.size.x - pad_left - pad_right,
		bounds.size.y - 3 - pad_top - pad_bottom
	)

func is_blocked_by_building(building: Variant, cell: Vector2i) -> bool:
	if not building is Building:
		return false
	return cell != building.entrance_cell

#region Tile Influence
func apply_influence(tile: Vector2i, type: String) -> void:
	var radius: int = 0
	var strength: float = 0.0
	var is_penalty: bool = false

	match type:
		"rocket":
			radius = 3
			strength = 100000.0
			is_penalty = true
		"hub":
			radius = 6
			strength = 120.0
			is_penalty = true
		"road":
			radius = 2
			strength = 20.0
			is_penalty = false
		_:
			return  # Unknown type, do nothing

	# Additive stacking — each new building adds to existing influence
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var current_tile = tile + Vector2i(x, y)
			var dist = abs(x) + abs(y)

			if dist > radius:
				continue

			var falloff_value = float(radius - dist + 1) / float(radius)
			var final_value = strength * falloff_value

			if is_penalty:
				final_value *= -1.0

			influence_grid[current_tile] = influence_grid.get(current_tile, 0.0) + final_value

func remove_road_influence(tile: Vector2i) -> void:
	const radius: int = 2
	const strength: float = 20.0

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var current_tile = tile + Vector2i(x, y)
			var dist = abs(x) + abs(y)

			if dist > radius:
				continue

			var falloff_value = float(radius - dist + 1) / float(radius)
			influence_grid[current_tile] = influence_grid.get(current_tile, 0.0) - (strength * falloff_value)
#endregion

#region Hull Shield Multiplier
func get_hull_shield_multiplier() -> float:
	var base_protection = current_hull_shield_level * 0.2
	var integrity_factor = hull_schield_integrity / 100.0
	var shield_mult = max(0.2, 1.0 - (base_protection * integrity_factor))
	# Segment 2 passive: subtract flat fracture chance reduction
	return max(0.1, shield_mult - rocket_fracture_reduction)

#region Zone
func get_zone_for_cell(cell: Vector2i) -> Zone:
	var distance = Vector2(cell).distance_to(Vector2(rocket_cell))

	if distance < 6:
		return Zone.CORE
	elif distance < 11:
		return Zone.INNER
	elif distance < 14:
		return Zone.OUTER
	else:
		return Zone.FRONTIER
#endregion
