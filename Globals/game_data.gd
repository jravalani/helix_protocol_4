extends Node

#region Grid & Spatial

const CELL_SIZE  : Vector2 = Vector2(64, 64)
const MAX_WIDTH            = 52
const MAX_HEIGHT           = 38

var map_stages = [
	Rect2i(-10, -6, 20, 12),
	Rect2i(-13, -7, 26, 14),
	Rect2i(-16, -9, 32, 18),
	Rect2i(-20, -11, 40, 22)
]

#endregion

#region Building Limits

const MAX_VENTS  = 50
const MAX_HUBS   = 12
const START_SIZE = 20

const HUB_CAP_PER_STAGE = {
	0: 1,
	1: 4,
	2: 8,
	3: 11,
}

var current_hub_count  : int = 0
var current_vent_count : int = 0
var current_pipe_count : int = 50

#endregion

#region Zone System

enum Zone { CORE, INNER, OUTER, FRONTIER }

const ZONE_REINFORCE_COSTS = [150, 200, 250, 300]

var active_reinforcement_timer : SceneTreeTimer = null
var current_reinforced_zone    : int            = -1
var reinforcement_version      : int            = 0

#endregion

#region Pressure System

const MAX_PRESSURE : float = 100.0
const BASE_RATE    : float = 0.04
var MAX_PRESSURE_PHASE : int = 10

var current_pressure       : float = 0.0
var current_pressure_phase : int   = 0

var fracture_wave_active : bool = false
var wave_warning_enabled : bool = false

var global_vent_interval_multiplier : float = 1.0
var rocket_fracture_reduction       : float = 0.0
var hub_rate_window                 : float = 60.0
var pressure_rate_multiplier        : float = 1.0

#endregion

#region Upgrade System

const MAX_HUB_UPGRADES         : int = 3
const HUB_UPGRADE_COSTS              = [50, 100, 120]

const HUB_SPAWN_BASE_COST      : int = 100
const HUB_SPAWN_COST_INCREMENT : int = 20
const VENT_SPAWN_BASE_COST     : int = 10
const VENT_SPAWN_COST_INCREMENT : int = 5

var current_hub_spawn_cost  : int = HUB_SPAWN_BASE_COST
var current_vent_spawn_cost : int = VENT_SPAWN_BASE_COST

const MAX_PIPE_UPGRADES     : int = 3
const PIPE_UPGRADE_COSTS          = [150, 300, 450]
var current_pipe_upgrade_level    : int = 0

const MAX_HULL_SHIELD_UPGRADES : int = 4
const HULL_SHIELD_UPGRADE_COSTS    = [300, 500, 800, 1200]
var current_hull_shield_level      : int   = 1
var hull_schield_integrity         : float = 100.0

const SINGLE_PIPE_REPAIR_COST    : int = 5
var auto_repair_enabled          : bool = false
var data_reserve_for_auto_repairs : int = 0

#endregion

#region Economy & Progression

var lifetime_data_earned : int = 0
var total_data           : int = 0
var previous_threshold   : int = 0
var score_to_next_reward : int = 30

#endregion

#region System Metrics

var total_hub_backlog        : int   = 0
var total_backlog            : int   = 0
var average_vent_utilization : float = 0.0
var active_packet_count      : int   = 0
var metric_timer             : float = 0.0

#endregion

#region Rocket

var current_rocket_phase : int = 0

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
		"description": "Reduces pipe and hub fracture chance by 20%. Enables fracture wave early warning system.",
		"fracture_chance_reduction": 0.2,
		"enables_wave_warning": true
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

#endregion

#region Map State

var current_stage    : int      = 0
var current_map_size : Rect2i   = Rect2i(-10, -6, 20, 12)
var rocket_cell      : Vector2i = Vector2i(0, 0)

#endregion

#region Grid Data Structures

var road_grid        : Dictionary = {}
var fractured_pipes  : Dictionary = {}
var building_grid    : Dictionary = {}
var road_connections : Dictionary = {}
var influence_grid   : Dictionary = {}
var special_tiles    : Dictionary = {}   # cell → SpecialTile
var astar            : AStar2D    = AStar2D.new()

#endregion

#region Misc

var input_consumed : bool = false

#endregion

#region Lifecycle

func _ready() -> void:
	randomize()


func reset_to_defaults() -> void:
	# Map / Stage
	current_stage = 0
	current_map_size = Rect2i(-10, -6, 20, 12)
	rocket_cell = Vector2i(0, 0)

	# Building counts & costs
	current_hub_count = 0
	current_vent_count = 0
	current_pipe_count = 50
	current_hub_spawn_cost = HUB_SPAWN_BASE_COST
	current_vent_spawn_cost = VENT_SPAWN_BASE_COST

	# Upgrades
	current_pipe_upgrade_level = 0
	current_hull_shield_level = 1
	hull_schield_integrity = 100.0
	current_rocket_phase = 0

	# Pressure
	current_pressure = 0.0
	current_pressure_phase = 0
	fracture_wave_active = false
	wave_warning_enabled = false
	global_vent_interval_multiplier = 1.0
	rocket_fracture_reduction = 0.0
	hub_rate_window = 60.0
	pressure_rate_multiplier = 1.0

	# Economy
	total_data = 25000
	lifetime_data_earned = 0
	previous_threshold = 0
	score_to_next_reward = 30

	# Zone reinforcement
	current_reinforced_zone = -1
	reinforcement_version = 0
	active_reinforcement_timer = null

	# Auto repair
	auto_repair_enabled = false
	data_reserve_for_auto_repairs = 0

	# Grids
	road_grid.clear()
	fractured_pipes.clear()
	building_grid.clear()
	road_connections.clear()
	influence_grid.clear()
	special_tiles.clear()
	astar = AStar2D.new()

	# Metrics
	total_hub_backlog = 0
	total_backlog = 0
	average_vent_utilization = 0.0
	active_packet_count = 0
	metric_timer = 0.0

	# Input
	input_consumed = false


func _process(delta: float) -> void:
	metric_timer += delta
	if metric_timer >= 1.0:
		update_system_metrics()
		metric_timer = 0.0

#endregion

#region System Metrics

func update_system_metrics() -> void:
	total_hub_backlog = 0
	var hubs = get_tree().get_nodes_in_group("hubs")
	for hub in hubs:
		if "oxygen_backlog" in hub:
			total_hub_backlog += hub.oxygen_backlog

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

	active_packet_count = get_tree().get_nodes_in_group("packets").size()

#endregion

#region Road Grid

func is_road_cell_empty(cell: Vector2i) -> bool:
	return not road_grid.has(cell)


func set_road_cell(cell: Vector2i, type: String) -> void:
	road_grid[cell] = type


func remove_road_cell(cell: Vector2i) -> void:
	road_grid.erase(cell)

#endregion

#region Coordinate Helpers

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(pos.x / GameData.CELL_SIZE.x),
		floori(pos.y / GameData.CELL_SIZE.y)
	)


func get_cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) * CELL_SIZE) + (CELL_SIZE / 2.0)

#endregion

#region Road Connections

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
		for dir in road_connections[cell]:
			var neighbor = cell + dir
			if road_connections.has(neighbor):
				road_connections[neighbor].erase(-dir)
		road_connections.erase(cell)

#endregion

#region Pathfinding

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
	if b_a is Building and b_b is Building:
		return
	var id_a = get_cell_id(cell_a)
	var id_b = get_cell_id(cell_b)
	if astar.has_point(id_a) and astar.has_point(id_b):
		astar.connect_points(id_a, id_b)


func remove_navigation_point(cell: Vector2i) -> void:
	var id = get_cell_id(cell)
	if astar.has_point(id):
		astar.remove_point(id)

#endregion

#region Map Growth

func increase_map_size() -> void:
	if current_stage < map_stages.size() - 1:
		current_stage += 1
		current_map_size = map_stages[current_stage]
		SignalBus.increase_map_size.emit(current_map_size)
	else:
		print("Max Capacity Reached")


func get_playable_rect() -> Rect2i:
	var bounds     = current_map_size
	var pad_left   = 0
	var pad_right  = 0
	var pad_top    = 0
	var pad_bottom = 0
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

#endregion

#region Tile Influence

func apply_influence(tile: Vector2i, type: String) -> void:
	var radius     : int   = 0
	var strength   : float = 0.0
	var is_penalty : bool  = false

	match type:
		"rocket":
			radius     = 3
			strength   = 100000.0
			is_penalty = true
		"hub":
			radius     = 6
			strength   = 120.0
			is_penalty = true
		"road":
			radius     = 2
			strength   = 20.0
			is_penalty = false
		_:
			return

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var current_tile = tile + Vector2i(x, y)
			var dist         = abs(x) + abs(y)
			if dist > radius:
				continue
			var falloff_value = float(radius - dist + 1) / float(radius)
			var final_value   = strength * falloff_value
			if is_penalty:
				final_value *= -1.0
			influence_grid[current_tile] = influence_grid.get(current_tile, 0.0) + final_value


func remove_road_influence(tile: Vector2i) -> void:
	const radius   : int   = 2
	const strength : float = 20.0
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var current_tile = tile + Vector2i(x, y)
			var dist         = abs(x) + abs(y)
			if dist > radius:
				continue
			var falloff_value = float(radius - dist + 1) / float(radius)
			influence_grid[current_tile] = influence_grid.get(current_tile, 0.0) - (strength * falloff_value)

#endregion

#region Hull Shield

func get_hull_shield_multiplier() -> float:
	var base_protection  = current_hull_shield_level * 0.2
	var integrity_factor = hull_schield_integrity / 100.0
	var shield_mult      = max(0.2, 1.0 - (base_protection * integrity_factor))
	return max(0.1, shield_mult - rocket_fracture_reduction)

#endregion

#region Persistence

func serialize() -> Dictionary:
	return {
		"current_stage": current_stage,
		"current_map_size": SaveManager.rect2i_to_dict(current_map_size),
		"current_hub_count": current_hub_count,
		"current_vent_count": current_vent_count,
		"current_pipe_count": current_pipe_count,
		"current_hub_spawn_cost": current_hub_spawn_cost,
		"current_vent_spawn_cost": current_vent_spawn_cost,
		"current_pipe_upgrade_level": current_pipe_upgrade_level,
		"current_hull_shield_level": current_hull_shield_level,
		"hull_schield_integrity": hull_schield_integrity,
		"current_pressure": current_pressure,
		"current_pressure_phase": current_pressure_phase,
		"fracture_wave_active": fracture_wave_active,
		"wave_warning_enabled": wave_warning_enabled,
		"global_vent_interval_multiplier": global_vent_interval_multiplier,
		"rocket_fracture_reduction": rocket_fracture_reduction,
		"hub_rate_window": hub_rate_window,
		"pressure_rate_multiplier": pressure_rate_multiplier,
		"total_data": total_data,
		"lifetime_data_earned": lifetime_data_earned,
		"previous_threshold": previous_threshold,
		"score_to_next_reward": score_to_next_reward,
		"current_rocket_phase": current_rocket_phase,
		"rocket_cell": SaveManager.vec2i_to_key(rocket_cell),
		"auto_repair_enabled": auto_repair_enabled,
		"data_reserve_for_auto_repairs": data_reserve_for_auto_repairs,
		"current_reinforced_zone": current_reinforced_zone,
		"reinforcement_version": reinforcement_version,
	}


func deserialize(d: Dictionary) -> void:
	current_stage                    = int(d["current_stage"])
	current_map_size                 = SaveManager.dict_to_rect2i(d["current_map_size"])
	current_hub_count                = int(d["current_hub_count"])
	current_vent_count               = int(d["current_vent_count"])
	current_pipe_count               = int(d["current_pipe_count"])
	current_hub_spawn_cost           = int(d["current_hub_spawn_cost"])
	current_vent_spawn_cost          = int(d["current_vent_spawn_cost"])
	current_pipe_upgrade_level       = int(d["current_pipe_upgrade_level"])
	current_hull_shield_level        = int(d["current_hull_shield_level"])
	hull_schield_integrity           = float(d["hull_schield_integrity"])
	current_pressure                 = float(d["current_pressure"])
	current_pressure_phase           = int(d["current_pressure_phase"])
	fracture_wave_active             = bool(d["fracture_wave_active"])
	wave_warning_enabled             = bool(d["wave_warning_enabled"])
	global_vent_interval_multiplier  = float(d["global_vent_interval_multiplier"])
	rocket_fracture_reduction        = float(d["rocket_fracture_reduction"])
	hub_rate_window                  = float(d["hub_rate_window"])
	pressure_rate_multiplier         = float(d["pressure_rate_multiplier"])
	total_data                       = int(d["total_data"])
	lifetime_data_earned             = int(d["lifetime_data_earned"])
	previous_threshold               = int(d["previous_threshold"])
	score_to_next_reward             = int(d["score_to_next_reward"])
	current_rocket_phase             = int(d["current_rocket_phase"])
	rocket_cell                      = SaveManager.key_to_vec2i(d["rocket_cell"])
	auto_repair_enabled              = bool(d["auto_repair_enabled"])
	data_reserve_for_auto_repairs    = int(d["data_reserve_for_auto_repairs"])
	current_reinforced_zone          = int(d["current_reinforced_zone"])
	reinforcement_version            = int(d["reinforcement_version"])


func rebuild_astar() -> void:
	astar = AStar2D.new()

	var seen := {}
	for cell in building_grid:
		var building = building_grid[cell]
		if not is_instance_valid(building):
			continue
		var bid = building.get_instance_id()
		if seen.has(bid):
			continue
		seen[bid] = true
		add_navigation_point(building.entrance_cell)

	for cell in road_grid:
		add_navigation_point(cell)

	for cell in road_grid:
		var pipe = road_grid[cell]
		if not pipe is NewRoadTile:
			continue
		for dir in pipe.manual_connections:
			var neighbor_cell = cell + dir
			var id_a = get_cell_id(cell)
			var id_b = get_cell_id(neighbor_cell)
			if astar.has_point(id_a) and astar.has_point(id_b):
				if not astar.are_points_connected(id_a, id_b):
					astar.connect_points(id_a, id_b)

	for cell in fractured_pipes:
		var cell_hash = get_cell_id(cell)
		if astar.has_point(cell_hash):
			astar.set_point_disabled(cell_hash, true)


func rebuild_influence() -> void:
	influence_grid.clear()
	apply_influence(rocket_cell, "rocket")

	var seen := {}
	for cell in building_grid:
		var building = building_grid[cell]
		if not is_instance_valid(building):
			continue
		var bid = building.get_instance_id()
		if seen.has(bid):
			continue
		seen[bid] = true
		if building is Hub:
			var tile = Vector2i(
				floor(building.position.x / CELL_SIZE.x),
				floor(building.position.y / CELL_SIZE.y)
			)
			apply_influence(tile + Vector2i(1, 1), "hub")

	for cell in road_grid:
		apply_influence(cell, "road")

#endregion


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


func is_blocked_by_building(building: Variant, cell: Vector2i) -> bool:
	if not building is Building:
		return false
	return cell != building.entrance_cell

#endregion
