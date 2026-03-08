extends Node2D

## =============================================================================
## SCRIPT: THE ABYSSAL ARCHITECT (Director System)
## =============================================================================
## THEME: The Great Ascent - A journey from the crushing depths to the surface.
## CORE LOOP: 
##   1. Director seeds "The Colony" (Hubs & Vents).
##   2. Player routes Oxygen from Vents to Hubs to generate Data.
##   3. Resources are spent on Rocket Parts or protecting the colony.
##   4. Global Pressure rises, threatening to crush unprotected structures.
##
## DESIGN PHILOSOPHY:
## - AESTHETIC FLOW: Buildings should cluster naturally to look like a 
##   deliberate undersea habitat rather than a scattered grid.
## - RHYTHMIC PACING: Hubs are the "Anchor Points" of the colony. Vents are the 
##   "Satellites." The Director must ensure a pleasing ratio between them.
## - PRESSURE AS A GARDENER: Pressure isn't just difficulty; it's a force that
##   prunes the map, forcing the player to choose what to save and where to expand.
##
## KEY METRICS:
## - Hubs: Forced spawns (Mini Motorways style). High priority.
## - Vents: Organic spawns. Often cluster near Hubs for visual cohesion.
## - Map Expansion: Occurs when the Director "runs out of room" for the vision.
## =============================================================================

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

func _process(delta: float) -> void:
	# Pressure system
	pressure_ratio = GameData.current_pressure / GameData.MAX_PRESSURE
	increment = GameData.BASE_RATE * (1 + (pressure_ratio * pressure_ratio))
	
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
	
	if phase_number >= 3:
		trigger_fracture_wave()

func trigger_fracture_wave() -> void:
	SignalBus.fracture_wave.emit()
	SignalBus.camera_shake.emit(0.4, 6.0)
	
	await get_tree().create_timer(5.0).timeout
	SignalBus.camera_shake.emit(0.5, 8.0)
	
	_execute_fracture_wave()

func _execute_fracture_wave() -> void:
	var phase := GameData.current_pressure_phase
	
	# Guaranteed fractures scale with phase
	var guaranteed_pipe_fractures := _get_guaranteed_pipe_fractures(phase)
	var guaranteed_hub_fractures := _get_guaranteed_hub_fractures(phase)
	
	# Get all fracturable pipes and shuffle them
	var fracturable_pipes: Array = []
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if pipe is NewRoadTile and not pipe.is_fractured and not pipe.is_reinforced:
			fracturable_pipes.append(pipe)
			
	# Guarantee minimum fractures — prioritize outer/frontier zones
	fracturable_pipes.sort_custom(func(a, b): 
		return _zone_priority(a.my_zone) > _zone_priority(b.my_zone)
	)
	
	for pipe in fracturable_pipes.slice(0, guaranteed_pipe_fractures):
		pipe.fracture()
	
	# Remaining pipes still roll probability
	for pipe in fracturable_pipes.slice(guaranteed_pipe_fractures):
		pipe.on_check_fracture()
	
	# Hub fractures
	var fracturable_hubs: Array = []
	var hubs = get_tree().get_nodes_in_group("hubs")
	for hub in hubs:
		if not hub.is_fractured:
			fracturable_hubs.append(hub)
		
	for hub in fracturable_hubs.slice(0, guaranteed_hub_fractures):
		hub.fracture()

func _get_guaranteed_pipe_fractures(phase: int) -> int:
	var total_pipes = GameData.road_grid.size()
	
	# Never fracture more than a percentage of total pipes
	# Early game (20 pipes): phase 3 = max 2, phase 5 = max 4
	# Late game (200 pipes): phase 3 = 2, phase 10 = 20
	var raw_count: int
	match phase:
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

const VENT_CLUSTER_MAX: int = 4
const VENT_CLUSTER_RADIUS: int = 8    # Tiles — vents within this range belong to the same cluster
const VENT_CLUSTER_MIN_DIST: int = 8  # Minimum tile distance between cluster centers
const VENT_SPAWN_RADIUS: int = 5      # Search radius around a cluster center for new vent

## Groups all existing vents into clusters.
## Two vents are in the same cluster if they are within VENT_CLUSTER_RADIUS tiles of each other.
func get_vent_clusters() -> Array:
	var vents = get_tree().get_nodes_in_group("vents")
	var clusters: Array = []

	for vent in vents:
		var vent_cell = GameData.world_to_cell(vent.global_position)
		var added = false

		for cluster in clusters:
			for member_cell in cluster:
				if vent_cell.distance_to(member_cell) <= VENT_CLUSTER_RADIUS:
					cluster.append(vent_cell)
					added = true
					break
			if added:
				break

		if not added:
			clusters.append([vent_cell])

	return clusters

## Returns the center tile of a cluster (average of all member positions).
func get_cluster_center(cluster: Array) -> Vector2i:
	var sum = Vector2i.ZERO
	for cell in cluster:
		sum += cell
	return sum / cluster.size()

## Finds the first cluster that still has room for more vents.
func find_open_cluster(clusters: Array) -> Array:
	for cluster in clusters:
		if cluster.size() < VENT_CLUSTER_MAX:
			return cluster
	return []

## Finds a new cluster center far enough from all existing clusters.
func find_new_cluster_center(clusters: Array) -> Vector2i:
	var camera_bounds = get_camera_bounds()
	var existing_centers: Array = []
	for cluster in clusters:
		existing_centers.append(get_cluster_center(cluster))

	var scored_tiles = []

	for x in range(camera_bounds.position.x, camera_bounds.end.x):
		for y in range(camera_bounds.position.y, camera_bounds.end.y):
			var tile = Vector2i(x, y)

			if not is_area_clear(tile, vent_size, camera_bounds, 0):
				continue

			# Must be far enough from all existing cluster centers
			var too_close = false
			for center in existing_centers:
				if tile.distance_to(center) < VENT_CLUSTER_MIN_DIST:
					too_close = true
					break
			if too_close:
				continue

			scored_tiles.append({
				"tile": tile,
				"score": score_tile(tile)
			})

	if scored_tiles.is_empty():
		print("Director: No valid new cluster center found.")
		return Vector2i(-1, -1)

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	return scored_tiles.slice(0, 3).pick_random().tile

func try_vent_spawn() -> void:
	var clusters = get_vent_clusters()
	var camera_bounds = get_camera_bounds()
	var spawn_center: Vector2i

	var open_cluster = find_open_cluster(clusters)

	if not open_cluster.is_empty():
		# Spawn near the existing open cluster's center
		spawn_center = get_cluster_center(open_cluster)
		print("Director: Spawning vent near existing cluster at ", spawn_center)
	else:
		# All clusters full — find a new center far from existing ones
		spawn_center = find_new_cluster_center(clusters)
		if spawn_center == Vector2i(-1, -1):
			print("Director: No room for a new vent cluster.")
			return
		print("Director: Starting new vent cluster at ", spawn_center)

	# Find candidate tiles within spawn radius of the center, clamped to current map bounds
	var scored_tiles = []
	for x in range(spawn_center.x - VENT_SPAWN_RADIUS, spawn_center.x + VENT_SPAWN_RADIUS + 1):
		for y in range(spawn_center.y - VENT_SPAWN_RADIUS, spawn_center.y + VENT_SPAWN_RADIUS + 1):
			var tile = Vector2i(x, y)
			if tile.distance_to(spawn_center) > VENT_SPAWN_RADIUS:
				continue
			if not camera_bounds.has_point(tile):
				continue
			if not is_area_clear(tile, vent_size, camera_bounds, 0):
				continue
			scored_tiles.append({
				"tile": tile,
				"score": score_tile(tile)
			})

	if scored_tiles.is_empty():
		print("Director: No valid vent tiles near cluster center ", spawn_center)
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile = scored_tiles.slice(0, 3).pick_random().tile
	spawn_vent_at(target_tile)

func spawn_vent_at(vent_position: Vector2i) -> void:
	var vent = vent_scene.instantiate()
	entities.add_child(vent)
	vent.position = Vector2(vent_position) * GameData.CELL_SIZE.x + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
	#BuildingSpawnEffect.create_at(vent.position, get_parent(), vent_size)
	vent.register_building(vent)
	GameData.apply_influence(vent_position, "vent")
#endregion
