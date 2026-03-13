extends Node2D

## =============================================================================
## SCENE PRELOADS
## =============================================================================

@onready var rocket_scene: PackedScene = preload("res://Scenes/rocket.tscn")
@onready var research_hub_scene: PackedScene = preload("res://Scenes/hub3x2.tscn")
@onready var vent_scene: PackedScene = preload("res://Scenes/vent.tscn")

## =============================================================================
## NODE REFERENCES
## =============================================================================

@onready var camera_2d: Camera2D = $"../Camera2D"
@onready var line_2d: Line2D = $Line2D
@onready var entities: Node = $"../Entities"

## =============================================================================
## SPAWN SYSTEM CONFIGURATION
## =============================================================================

const MAX_SPAWN_POS_TRIES: int = 30

var use_dynamic_spawning: bool = true
var intro_cooldown: float = 3.0

## =============================================================================
## BUILDING SIZE DEFINITIONS
## =============================================================================

var hub_size: Vector2i = Vector2i(3, 2)
var vent_size: Vector2i = Vector2i(1, 1)
var rocket_size: Vector2i = Vector2i(3, 3)

## Hub rotation options (in radians)
var hub_rotation: Array = [0, PI/2, 3*PI/2]

## =============================================================================
## ZONE UNLOCK STATE
## =============================================================================
## Core + Inner always unlocked.
## Outer unlocks on Rocket Segment 1.
## Frontier unlocks on Rocket Segment 3.

var unlocked_zones: Array[GameData.Zone] = [GameData.Zone.CORE]

## =============================================================================
## CAMERA & VIEWPORT
## =============================================================================

@onready var camera_buffer: int = 1      # Padding around camera view
var screen_center: Vector2               # Cached center point

## =============================================================================
## PRESSURE SYSTEM
## =============================================================================

## Pressure increment calculation (quadratic scaling for late-game intensity)
## Formula: BASE_RATE * (1 + (pressure_ratio^2))
var pressure_ratio: float = 0.0
var increment: float = 0.0

## Hull shield degradation
var degradation_rate: float = 0.0
func _ready() -> void:
	await get_tree().process_frame
	screen_center = camera_2d.get_screen_center_position()
	get_camera_bounds()
	spawn_rocket()
	spawn_initial_colony()
	print("Current Map Size is ", GameData.current_map_size, " from ready function.")
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	SignalBus.spawn_hub_requested.connect(request_hub_spawn)
	SignalBus.spawn_vent_requested.connect(request_vent_spawn)

func _on_rocket_segment_purchased(phase: int) -> void:
	print("Director received rocket_segment_purchased: ", phase)
	match phase:
		1: unlock_zone(GameData.Zone.INNER)
		2: unlock_zone(GameData.Zone.OUTER)
		3: unlock_zone(GameData.Zone.FRONTIER)
	apply_segment_effects(phase)

func apply_segment_effects(phase: int) -> void:
	var data = GameData.ROCKET_UPGRADES.get(phase, {})

	# Shield boost
	if data.has("shield_boost"):
		GameData.current_hull_shield_level += data["shield_boost"]
		print("Hull shield boosted to level ", GameData.current_hull_shield_level)

	# Vent interval multiplier — stacks across segments
	if data.has("vent_interval_multiplier"):
		GameData.global_vent_interval_multiplier *= data["vent_interval_multiplier"]
		SignalBus.vent_interval_updated.emit()
		print("Vent interval multiplier now: ", GameData.global_vent_interval_multiplier)

	# Fracture chance reduction
	if data.has("fracture_chance_reduction"):
		GameData.rocket_fracture_reduction += data["fracture_chance_reduction"]
		print("Rocket fracture reduction now: ", GameData.rocket_fracture_reduction)

	# Hub rate window reduction
	if data.has("rate_window_reduction"):
		GameData.hub_rate_window -= data["rate_window_reduction"]
		GameData.hub_rate_window = max(20.0, GameData.hub_rate_window)
		print("Hub rate window now: ", GameData.hub_rate_window)

	# Pressure rate reduction
	if data.has("pressure_rate_reduction"):
		GameData.pressure_rate_multiplier *= (1.0 - data["pressure_rate_reduction"])
		print("Pressure rate multiplier now: ", GameData.pressure_rate_multiplier)

func _process(delta: float) -> void:
	# Pressure system
	pressure_ratio = GameData.current_pressure / GameData.MAX_PRESSURE
	increment = GameData.BASE_RATE * (1 + (pressure_ratio * pressure_ratio)) * GameData.pressure_rate_multiplier
	
	GameData.current_pressure += increment * delta
	GameData.current_pressure = min(GameData.MAX_PRESSURE, GameData.current_pressure)
	
	# Hull shield degrades with pressure
	degradation_rate = 0.05 * (GameData.current_pressure / 100)
	GameData.hull_schield_integrity -= degradation_rate * delta
	GameData.hull_schield_integrity = max(0, GameData.hull_schield_integrity)
	
	var target_phase = int(GameData.current_pressure / 10)
	target_phase = clamp(target_phase, 0, 10)
	
	if target_phase > GameData.current_pressure_phase:
		transition_to_phase(target_phase)
	
	if GameData.current_pressure >= 100:
		print("Meltdown Triggered!")
		SignalBus.game_over.emit()
#region Camera
#func get_camera_bounds() -> Rect2i:
	#var zoom = camera_2d.zoom
	#var viewport_size = get_viewport().get_visible_rect().size
	#
	#var visible_world_size = viewport_size / zoom
	#
	## calculating the top-left and bottom-right
	#var top_left = screen_center - (visible_world_size / 2)
	#var bottom_right = screen_center + (visible_world_size / 2)
	#
	## convert to grid coordinates
	#var grid_min = Vector2i(
		#floor(top_left.x / GameData.CELL_SIZE.x),
		#floor(top_left.y / GameData.CELL_SIZE.y)
	#)
	#
	#var grid_max = Vector2i(
		#floor(bottom_right.x / GameData.CELL_SIZE.x),
		#floor(bottom_right.y / GameData.CELL_SIZE.y)
	#)
	#
	## add the buffer for spawning
	#var bounds = Rect2i(grid_min, grid_max - grid_min).grow(-camera_buffer)
	#
	#print("Director here. I have detected the playable canvas. Its size is: ", bounds)
	#return bounds

func get_camera_bounds() -> Rect2i:
	var bounds = GameData.current_map_size
	# 1 cell padding left/right, 2 cell padding top/bottom
	var playable_bounds = Rect2i(
		bounds.position.x,
		bounds.position.y + 1,
		bounds.size.x,
		bounds.size.y - 3
	)
	return playable_bounds
#endregion

#region Rocket
# Spawn rocket at the dead center of the screen
func spawn_rocket() -> void:
	var rocket = rocket_scene.instantiate()
	var center_tile = Vector2i(
		floor(screen_center.x / GameData.CELL_SIZE.x),
		floor(screen_center.y / GameData.CELL_SIZE.y)
	)
	
	## offset the rocket so that its actual center is at the center
	#var rocket_offset = center_tile - Vector2i(2, 2)
	entities.add_child(rocket)
	rocket.global_position = Vector2(center_tile) * GameData.CELL_SIZE.x - Vector2(64, 64)
	rocket.register_building(rocket)
	GameData.apply_influence(center_tile, "rocket")
#endregion

#region Functions

#region Public API — called by ResourceManager

func request_hub_spawn() -> void:
	if GameData.current_hub_count >= GameData.MAX_HUBS:
		print("Director: Hub cap reached.")
		return
	try_hub_spawn()

func request_vent_spawn() -> void:
	if GameData.current_vent_count >= GameData.MAX_VENTS:
		print("Director: Vent cap reached.")
		return
	try_vent_spawn()

func unlock_zone(zone: GameData.Zone) -> void:
	if zone not in unlocked_zones:
		unlocked_zones.append(zone)
		GameData.increase_map_size()
		print("Map size after increase: ", GameData.current_map_size)
		SignalBus.zone_unlocked.emit(zone)

#endregion

func _is_tile_in_unlocked_zone(tile: Vector2i) -> bool:
	return GameData.get_zone_for_cell(tile) in unlocked_zones

func is_area_clear(target_coord: Vector2i, area_size: Vector2i, camera_bounds: Rect2i, buffer: int = 0) -> bool:
	for x in range(-buffer, area_size.x + buffer):
		for y in range(-buffer, area_size.y + buffer):
			var current_tile = target_coord + Vector2i(x, y)
			if not camera_bounds.has_point(current_tile):
				return false
			if not _is_tile_in_unlocked_zone(current_tile):
				return false
			if GameData.building_grid.has(current_tile) or GameData.road_grid.has(current_tile):
				return false
	return true

#func select_spawn_pos(from_center: Vector2, radius_in_tiles: int, for_size: Vector2i) -> Vector2i:
	# NEW SYSTEM
	# for vent:
	# select hub with least vents (partner tile)
	# create a list of candidate tiles (where vent could spawn)
	# calculate their scores based on certain parameteres
	# select the tile with the highest score and spawn the vent
	# vent must spawn no matter what!
	
	# for hub:
	# hubs are forced spawn to have the game progress
	# gather candidate tiles 
	# score them
	# spawn hub on the best one
	
	# OLD SYSTEM
	# send out a ping at a specific angle and distance from the center of the screen.
	# if that ping hits an obstacle, find different angle and try again.
	# this system requires no. of tries 
	#var camera_bounds = get_camera_bounds()
	#for i in range(MAX_SPAWN_POS_TRIES):
		#var random_angle = randf_range(0, TAU)
		#var direction = Vector2(cos(random_angle), sin(random_angle))
		#var target_pos = from_center + (direction * radius_in_tiles * GameData.CELL_SIZE.x)
		#
		#var target_tile = Vector2i(floor(target_pos / GameData.CELL_SIZE))
		#
		##line_2d.points = [from_center, target_pos]
		## check if the area is clear here for spawning hubs / vents
		#if is_area_clear(target_tile, for_size, camera_bounds):
			#return target_tile
	#print("Director failed to find a spot after ", MAX_SPAWN_POS_TRIES, "tries.")
	#return Vector2i(-1, -1)

func calculate_candidate_tiles(center: Vector2, min_dist: int, max_dist: int, size: Vector2i, buffer: int) -> Array:
	var candidates = []
	var center_tile = Vector2i(center / GameData.CELL_SIZE.x)
	var camera_bounds = get_camera_bounds()
	
	# check all tiles from min dist to max dist in a square
	for r in range(min_dist, max_dist):
		# calculate the 4 walls of the sqaure 
		var top_wall = center_tile.y - r
		var bottom_wall = center_tile.y + r
		var left_wall = center_tile.x - r
		var right_wall = center_tile.x + r
		
		# loop through the walls
		# top wall
		for x in range(left_wall, right_wall + 1):
			var t = Vector2i(x, top_wall)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		# bottom wall
		for x in range(left_wall, right_wall + 1):
			var t = Vector2i(x, bottom_wall)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		# left wall
		for y in range(top_wall, bottom_wall):
			var t = Vector2i(left_wall, y)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		# right wall
		for y in range(top_wall, bottom_wall):
			var t = Vector2i(right_wall, y)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		if candidates.size() >= 15:
			break
	
	return candidates

func score_tile(tile: Vector2i) -> float:
	var base_score = GameData.influence_grid.get(tile, 0.0)

	# Push toward the edges of the current map.
	# Tiles further from the rocket (map center) score higher.
	var map = GameData.current_map_size
	var map_half = Vector2(map.size) / 2.0
	var max_dist = min(map_half.x, map_half.y)
	var dist_from_center = Vector2(tile).distance_to(Vector2(GameData.rocket_cell))
	var edge_bonus = (dist_from_center / max(max_dist, 1.0)) * 60.0

	return base_score + edge_bonus + randf_range(0.001, 0.050)
	
	## OLD SYSTEM
	#var final_score: int = 0
	#
	#match type:
		#"hub":
			#if is_near_road(tile, 2):
				#final_score += 50
			## Hubs check a wide area for penalties to stay spread out
			#final_score -= get_building_proximity_penalty(tile, 6)
			#
		#"vent":
			#if is_near_road(tile, 2):
				#final_score += 30
			## Vents get a bonus for being near other vents
			#final_score += get_building_proximity_bonus(tile, 3)
			## Vents check a smaller area for penalties so they can be closer to hubs
			#final_score -= get_building_proximity_penalty(tile, 4)
			#
	#return final_score

#func is_near_road(candidate: Vector2i, radius: int) -> bool:
	#for x in range(-radius, radius + 1):
		#for y in range(-radius, radius + 1):
			#var check_tile = candidate + Vector2i(x, y)
			#if GameData.road_grid.has(check_tile):
				#return true
	#return false
#
#func get_building_proximity_penalty(candidate: Vector2i, radius: int) -> int:
	#var total_penalty: int = 0
	#for x in range(-radius, radius + 1):
		#for y in range(-radius, radius + 1):
			#var check_tile = candidate + Vector2i(x, y)
			#
			#if GameData.building_grid.has(check_tile):
				#var building = GameData.building_grid[check_tile]
				## Hubs are a huge obstacle, Vents are a small obstacle
				#if building.is_in_group("hubs"):
					#total_penalty += 100 
				#else:
					#total_penalty += 20 
	#return total_penalty
#
#func get_building_proximity_bonus(candidate: Vector2i, radius: int) -> int:
	#var total_bonus: int = 0
	#for x in range(-radius, radius + 1):
		#for y in range(-radius, radius + 1):
			#var check_tile = candidate + Vector2i(x, y)
			#
			#if GameData.building_grid.has(check_tile):
				#var building = GameData.building_grid[check_tile]
				#
				## Vents like to be near other vents (Clustering)
				#if building.is_in_group("vents"):
					#total_bonus += 40
					#
				## Hubs don't really get bonuses from being near things, 
				## but could add a bonus for being near specific resources here later!
					#
	#return total_bonus

func transition_to_phase(phase_number: int) -> void:
	if GameData.current_pressure_phase <= GameData.MAX_PRESSURE_PHASE:
		GameData.current_pressure_phase = phase_number
		SignalBus.pressure_phase_changed.emit(phase_number)
	print("----PHASE TRANSITION: ", phase_number, "----")
	
	if phase_number >= 1:
		trigger_fracture_wave()

func trigger_fracture_wave() -> void:
	GameData.fracture_wave_active = true
	SignalBus.fracture_wave.emit()
	SignalBus.camera_shake.emit(0.4, 6.0)
	
	await get_tree().create_timer(5.0).timeout
	SignalBus.camera_shake.emit(0.5, 8.0)
	
	_execute_fracture_wave()
	
	await get_tree().create_timer(10.0).timeout
	GameData.fracture_wave_active = false

## Dispatches fracture effects based on current pressure phase.
## Pipes always fracture. Hubs join at phase 3. Slowdown/burst added from phase 5.
func _execute_fracture_wave() -> void:
	var phase := GameData.current_pressure_phase

	_apply_pipe_fractures(phase)

	if phase >= 3:
		_apply_hub_fractures(phase)

	if phase >= 5 and phase < 8:
		if randi() % 2 == 0:
			SignalBus.trigger_packet_slowdown.emit()
		else:
			SignalBus.trigger_vent_burst.emit()

	if phase >= 8:
		SignalBus.trigger_packet_slowdown.emit()
		SignalBus.trigger_vent_burst.emit()

## Fractures pipes sorted by zone priority. Outer/frontier pipes break first.
## Builds connected chains from fracturable pipes, then fractures whole chains.
## Guarantees at least one neighbor always remains visible after fracture.
func _apply_pipe_fractures(phase: int) -> void:
	var fracturable_set: Dictionary = {}
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if pipe is NewRoadTile and not pipe.is_fractured and not pipe.is_reinforced:
			fracturable_set[cell] = pipe

	# Build chains via DFS within fracturable pipes only
	var chains: Array = []
	var visited: Dictionary = {}
	for cell in fracturable_set:
		if visited.has(cell):
			continue
		var chain: Array = []
		var stack: Array = [cell]
		while stack.size() > 0:
			var c = stack.pop_back()
			if visited.has(c):
				continue
			visited[c] = true
			chain.append(fracturable_set[c])
			var pipe = fracturable_set[c]
			for dir in pipe.manual_connections:
				var neighbor_cell = c + dir
				if fracturable_set.has(neighbor_cell) and not visited.has(neighbor_cell):
					stack.append(neighbor_cell)
		chains.append(chain)

	# Only keep chains of 2+ pipes
	var valid_chains: Array = chains.filter(func(ch): return ch.size() >= 2)

	# Sort chains by zone priority of their first pipe — frontier first
	valid_chains.sort_custom(func(a, b):
		return _zone_priority(a[0].my_zone) > _zone_priority(b[0].my_zone)
	)

	var guaranteed = _get_guaranteed_pipe_fractures(phase)
	var fractured_count = 0
	for chain in valid_chains:
		if fractured_count >= guaranteed:
			break
		for pipe in chain:
			pipe.fracture()
		fractured_count += 1

## Fractures a guaranteed number of hubs based on phase.
func _apply_hub_fractures(phase: int) -> void:
	var fracturable_hubs: Array = []
	for hub in get_tree().get_nodes_in_group("hubs"):
		if not hub.is_fractured:
			fracturable_hubs.append(hub)
	for hub in fracturable_hubs.slice(0, _get_guaranteed_hub_fractures(phase)):
		hub.fracture()

func _get_guaranteed_pipe_fractures(phase: int) -> int:
	var total_pipes = GameData.road_grid.size()
	
	# Never fracture more than a percentage of total pipes
	# Early game (20 pipes): phase 3 = max 2, phase 5 = max 4
	# Late game (200 pipes): phase 3 = 2, phase 10 = 20
	var raw_count: int
	match phase:
		1:  raw_count = 1
		2:  raw_count = 2
		3:  raw_count = 2
		4:  raw_count = 3
		5:  raw_count = 4
		6:  raw_count = 5
		7:  raw_count = 9
		8:  raw_count = 11
		9:  raw_count = 15
		10: raw_count = 20
		_:  raw_count = 0

	# Cap at 25% of total pipes so early game isn't destroyed
	var max_allowed = max(1, int(total_pipes * 0.25))
	return min(raw_count, max_allowed)

func _get_guaranteed_hub_fractures(phase: int) -> int:
	match phase:
		3: return 1  
		4: return 2
		5: return 2   
		6: return 2
		7: return 3
		8: return 3
		9: return 4
		10: return 5
		_: return 0

func _zone_priority(zone: GameData.Zone) -> int:
	# Frontier pipes fracture first, core last
	match zone:
		GameData.Zone.FRONTIER: return 4
		GameData.Zone.OUTER:    return 3
		GameData.Zone.INNER:    return 2
		GameData.Zone.CORE:     return 1
		_: return 0
#endregion

#region First Colony
func spawn_initial_colony() -> void:
	"""
	Spawn 1 research-hub and 1 vent at the start of the game to let the player get going.
	"""
	# First we spawn a hub using the new scoring system
	var scored_tiles = []
	var candidate_tiles = calculate_candidate_tiles(screen_center, 3, 12, hub_size, 1)
	
	print("Initial hub candidates found: ", candidate_tiles.size())
	
	# Score each candidate
	for candidate in candidate_tiles:
		var score = score_tile(candidate)
		scored_tiles.append({
			"tile": candidate,
			"score": score
		})
		if scored_tiles.size() < 3:  # Debug first few
			print("Candidate: ", candidate, " Score: ", score)
	
	if scored_tiles.is_empty():
		print("Cannot spawn initial colony hub - no candidates!")
		return
	
	# Sort and pick LEAST NEGATIVE tile for hub (highest score)
	scored_tiles.sort_custom(func (a, b): return a.score > b.score)
	var target_tile_for_hub = scored_tiles.pick_random().tile
	print("Selected hub tile: ", target_tile_for_hub)
	
	# Instantiate the hub
	var research_hub = research_hub_scene.instantiate()
	entities.add_child(research_hub)
	research_hub.position = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
	research_hub.register_building(research_hub)
	
	var hub_center_cell = target_tile_for_hub + Vector2i(1, 1)
	GameData.apply_influence(hub_center_cell, "hub")
	
	# Now spawn a vent near the hub
	var hub_world_pos = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
	var vent_scored_tiles = []
	var vent_candidates = calculate_candidate_tiles(hub_world_pos, 6, 12, vent_size, 0)
	
	print("Initial vent candidates found: ", vent_candidates.size())
	
	# Score vent candidates
	for candidate in vent_candidates:
		var score = score_tile(candidate)
		vent_scored_tiles.append({
			"tile": candidate,
			"score": score
		})
	
	if not vent_scored_tiles.is_empty():
		vent_scored_tiles.sort_custom(func (a, b): return a.score > b.score)
		var target_tile_for_vent = vent_scored_tiles.pick_random().tile
		
		var vent_1 = vent_scene.instantiate()
		entities.add_child(vent_1)
		vent_1.position = Vector2(target_tile_for_vent * GameData.CELL_SIZE.x) + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
		vent_1.register_building(vent_1)
		GameData.apply_influence(target_tile_for_vent, "vent")
		vent_clusters.append({ "center": target_tile_for_vent, "count": 1 })
		print("Spawned initial vent at: ", target_tile_for_vent)
	else:
		print("Cannot spawn initial vent - no candidates!")
#endregion

#region HubSpawning
func try_hub_spawn() -> void:
	var scored_tiles = []
	var camera_bounds = get_camera_bounds()

	# Scan every tile in the current map bounds
	for x in range(camera_bounds.position.x, camera_bounds.end.x):
		for y in range(camera_bounds.position.y, camera_bounds.end.y):
			var tile = Vector2i(x, y)
			if is_area_clear(tile, hub_size, camera_bounds, 1):
				scored_tiles.append({
					"tile": tile,
					"score": score_tile(tile)
				})

	if scored_tiles.is_empty():
		print("Director: No valid hub tiles in current map. Player needs to unlock more zones.")
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile = scored_tiles.slice(0, 3).pick_random().tile
	spawn_hub_at(target_tile)

func spawn_hub_at(position: Vector2i) -> void:
	var hub = research_hub_scene.instantiate()
	entities.add_child(hub)
	hub.position = position * GameData.CELL_SIZE.x
	#BuildingSpawnEffect.create_at(hub.position, get_parent(), hub_size)
	hub.register_building(hub)
	var hub_center_cell = position + Vector2i(1, 1)
	GameData.apply_influence(hub_center_cell, "hub")
#endregion

#region VentSpawning

const VENT_CLUSTER_MAX: int = 5
const VENT_SPAWN_RADIUS: int = 5
const VENT_SPAWN_RADIUS_MAX: int = 10

## Fixed cluster registry — centers are set once and never change.
## Each entry: { "center": Vector2i, "count": int }
var vent_clusters: Array = []

func get_dynamic_cluster_min_dist_for_stage(stage: int) -> int:
	match stage:
		0: return 6
		1: return 7
		2: return 8
		3: return 9
		_: return 6

func get_dynamic_cluster_min_dist() -> int:
	return get_dynamic_cluster_min_dist_for_stage(GameData.current_stage)

## Returns the first cluster that still has room, or empty dict if all full.
func find_open_cluster() -> Dictionary:
	for cluster in vent_clusters:
		if cluster["count"] < VENT_CLUSTER_MAX:
			return cluster
	return {}

## Finds a new cluster center, falling back to previous stage distances if needed.
## Returns Vector2i(-9999, -9999) if no center found even at stage 0 distance.
func find_new_cluster_center() -> Vector2i:
	var camera_bounds = get_camera_bounds()

	for stage in range(GameData.current_stage, -1, -1):
		var min_dist = get_dynamic_cluster_min_dist_for_stage(stage)
		var scored_tiles = []

		for x in range(camera_bounds.position.x, camera_bounds.end.x):
			for y in range(camera_bounds.position.y, camera_bounds.end.y):
				var tile = Vector2i(x, y)
				if not is_area_clear(tile, vent_size, camera_bounds, 0):
					continue
				var too_close = false
				for cluster in vent_clusters:
					if tile.distance_to(cluster["center"]) < min_dist:
						too_close = true
						break
				if too_close:
					continue
				scored_tiles.append({ "tile": tile, "score": score_tile(tile) })

		if not scored_tiles.is_empty():
			print("Director: Found cluster center at stage ", stage, " dist ", min_dist)
			scored_tiles.sort_custom(func(a, b): return a.score > b.score)
			return scored_tiles.slice(0, 3).pick_random().tile

	print("Director: Map is full. Player needs to expand.")
	SignalBus.notify_player_expand.emit()
	return Vector2i(-9999, -9999)

func try_vent_spawn() -> void:
	print("try_vent_spawn called. Clusters: ", vent_clusters.size())
	var camera_bounds = get_camera_bounds()
	var spawn_center: Vector2i

	var open_cluster = find_open_cluster()

	if not open_cluster.is_empty():
		spawn_center = open_cluster["center"]
		print("Director: Spawning vent in cluster at ", spawn_center, " (", open_cluster["count"], "/", VENT_CLUSTER_MAX, ")")
	else:
		spawn_center = find_new_cluster_center()
		if spawn_center == Vector2i(-9999, -9999):
			return
		vent_clusters.append({ "center": spawn_center, "count": 0 })
		print("Director: New cluster registered at ", spawn_center)

	# Find candidate tiles within spawn radius, expanding if needed
	var scored_tiles = []
	var search_radius = VENT_SPAWN_RADIUS

	while scored_tiles.is_empty() and search_radius <= VENT_SPAWN_RADIUS_MAX:
		for x in range(spawn_center.x - search_radius, spawn_center.x + search_radius + 1):
			for y in range(spawn_center.y - search_radius, spawn_center.y + search_radius + 1):
				var tile = Vector2i(x, y)
				if tile.distance_to(spawn_center) > search_radius:
					continue
				if not camera_bounds.has_point(tile):
					continue
				if not is_area_clear(tile, vent_size, camera_bounds, 0):
					continue
				scored_tiles.append({ "tile": tile, "score": score_tile(tile) })
		if scored_tiles.is_empty():
			search_radius += 1
			print("Director: Expanding vent search radius to ", search_radius)

	if scored_tiles.is_empty():
		print("Director: No valid vent tiles near cluster center ", spawn_center)
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile = scored_tiles.slice(0, 3).pick_random().tile

	for cluster in vent_clusters:
		if cluster["center"] == spawn_center:
			cluster["count"] += 1
			break

	spawn_vent_at(target_tile)

func spawn_vent_at(vent_position: Vector2i) -> void:
	var vent = vent_scene.instantiate()
	entities.add_child(vent)
	vent.position = Vector2(vent_position) * GameData.CELL_SIZE.x + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
	#BuildingSpawnEffect.create_at(vent.position, get_parent(), vent_size)
	vent.register_building(vent)
	GameData.apply_influence(vent_position, "vent")
#endregion
