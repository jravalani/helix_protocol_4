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
## SPAWN TIMING & INTERVALS
## =============================================================================

## Hub spawning
var min_vents_per_hub: int = 4        # Need at least 4 vents per hub
var hub_spawn_cooldown: float = 15.0  # Minimum time between hub spawns
var hub_cooldown_timer: float = 0.0
var hub_interval: float = 90.0
var hub_timer: float = 0.0
var hub_spawn_eta: String = ""

## Vent spawning (accelerates over time)
var vent_interval: float = 35.0
var vent_timer: float = 0.0
var vent_acceleration: float = 0.92      # Multiplier applied each spawn
var min_vent_interval: float = 6.0       # Fastest possible spawn rate


## =============================================================================
## SPAWN RADIUS RULES
## =============================================================================

var hub_base_radius: int = 4             # Base exclusion radius for hubs
var hub_radius_multiplier: int = 2       # Additional spacing multiplier
var vent_base_radius: int = 3            # Base exclusion radius for vents

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
	
	vent_timer = vent_interval
	hub_timer = hub_interval
	
	print("Current Map Size is ", GameData.current_map_size, " from ready function.")

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
	
	# Intro cooldown
	if intro_cooldown > 0:
		intro_cooldown -= delta
		return
	
	# HUB SPAWNING - Vent-driven logic
	if GameData.current_hub_count < GameData.MAX_HUBS:
		hub_timer -= delta
		
		if hub_timer <= 0:
			try_hub_spawn()
			hub_timer = calculate_dynamic_hub_interval()
				# Update debug display
		hub_spawn_eta = "%.1fs" % max(0, hub_timer)
	else:
		hub_timer = hub_interval
		hub_spawn_eta = "MAX"
	
	# VENT SPAWNING
	if GameData.current_vent_count < GameData.MAX_VENTS:
		vent_timer -= delta
		if vent_timer <= 0:
			try_vent_spawn()
			vent_timer = calculate_dynamic_vent_interval()
	else:
		vent_timer = vent_interval
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
	# Ignore the viewport/zoom math entirely. 
	# Use the pre-defined map size as the absolute truth.
	var bounds = GameData.current_map_size
	
	# If you want a safety buffer so things don't spawn on the very edge:
	var playable_bounds = bounds.grow(-camera_buffer) 
	
	print("Director: Canvas locked to GameData: ", playable_bounds)
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

func calculate_dynamic_vent_interval() -> float:
	var base_interval = 35.0
	
	var pressure_factor = GameData.current_pressure / GameData.MAX_PRESSURE
	var pressure_multiplier = 1.0 - (pressure_factor * 0.6)
	
	var total_backlog = clamp(GameData.total_hub_backlog, 8, 18)
	var backlog_multiplier = 1.0/ (1.0 - (total_backlog / 20.0))
	backlog_multiplier = clamp(backlog_multiplier, 0.5, 2.0)
	
	var avg_utilization = GameData.average_vent_utilization
	var utilization_multiplier = 1.0
	if avg_utilization > 0.8:
		utilization_multiplier = 0.6
	if avg_utilization > 0.6:
		utilization_multiplier = 0.8
	
	var final_interval = base_interval * pressure_multiplier * backlog_multiplier * utilization_multiplier
	return clamp(final_interval, min_vent_interval, 35.0)

func calculate_dynamic_hub_interval() -> float:
	var base = 90.0  # hubs are rarer early
	var current_vents = GameData.current_vent_count

	# Vent factor — more vents = hubs needed sooner
	var vent_factor = 1.0
	if current_vents <= 2:
		vent_factor = 1.5    # very slow early (135s)
	elif current_vents <= 4:
		vent_factor = 1.2    # slow (108s)
	elif current_vents <= 7:
		vent_factor = 1.0    # normal (90s)
	elif current_vents <= 12:
		vent_factor = 0.75   # faster (67s)
	elif current_vents <= 20:
		vent_factor = 0.55   # fast (49s)
	elif current_vents <= 35:
		vent_factor = 0.4    # very fast (36s)
	else:
		vent_factor = 0.3    # rapid (27s)

	# Backlog factor
	var total_backlog = GameData.total_hub_backlog
	var backlog_factor = 1.0
	if total_backlog > 50:
		backlog_factor = 1.8
	elif total_backlog > 30:
		backlog_factor = 1.5
	elif total_backlog > 15:
		backlog_factor = 1.2
	elif total_backlog < 10:
		backlog_factor = 0.85

	var final_interval = base * vent_factor * backlog_factor
	return clamp(final_interval, 20.0, 150.0)  # max 150s early game


func is_area_clear(target_coord: Vector2i, area_size: Vector2i, camera_bounds: Rect2i, buffer: int = 0) -> bool:
	for x in range(-buffer, area_size.x + buffer):
		for y in range(-buffer, area_size.y + buffer):
			var current_tile = target_coord + Vector2i(x, y)
			
			if not camera_bounds.has_point(current_tile):
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

	# Zone bonus — on larger maps push buildings outward
	var zone_bonus := 0.0
	var map_stage = GameData.map_stages.find(GameData.current_map_size)
	if map_stage == -1:
		map_stage = 0

	if map_stage >= 2:
		var zone = GameData.get_zone_for_cell(tile)
		match zone:
			GameData.Zone.FRONTIER: zone_bonus = 80.0
			GameData.Zone.OUTER:    zone_bonus = 40.0
			GameData.Zone.INNER:    zone_bonus = 10.0
			GameData.Zone.CORE:     zone_bonus = 0.0
	elif map_stage == 1:
		var zone = GameData.get_zone_for_cell(tile)
		match zone:
			GameData.Zone.OUTER:    zone_bonus = 30.0
			GameData.Zone.INNER:    zone_bonus = 10.0
			_:                      zone_bonus = 0.0

	return base_score + zone_bonus + randf_range(0.001, 0.050)
	
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
	#Damage/destroy unprotected buildings?
	#Increase spawn rates?
	#Fracture pipes/roads?
	#Change the influence grid dynamics?
	#Force map expansion?
	if GameData.current_pressure_phase <= GameData.MAX_PRESSURE_PHASE:
		GameData.current_pressure_phase = phase_number
		SignalBus.pressure_phase_changed.emit(phase_number)
	print("----PHASE TRANSITION: ", phase_number, "----")
	
	if phase_number >= 3:
		trigger_fracture_wave()
	
	if phase_number >= 4:
		vent_interval *= 0.95
		print("Director: Logistics Boosted!")

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
	var candidate_tiles = calculate_candidate_tiles(screen_center, 3, 8, hub_size, 1)
	
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
	GameData.current_hub_count += 1
	
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
		GameData.current_vent_count += 1
		print("Spawned initial vent at: ", target_tile_for_vent)
	else:
		print("Cannot spawn initial vent - no candidates!")
#endregion

#region HubSpawning
func try_hub_spawn() -> void:
	# NEW SYSTEM
	var scored_tiles = []
	var map_stage = GameData.map_stages.find(GameData.current_map_size)
	if map_stage == -1:
		map_stage = 0
	
	var dynamic_min = 3 + (map_stage * 3)
	var dynamic_max = 8 + (map_stage * 4)
	
	dynamic_min = max(3, dynamic_min - 1)
	
	# get the candidate tiles
	var candidate_tiles = calculate_candidate_tiles(screen_center, dynamic_min, dynamic_max, hub_size, 1)

	# find score for each candidate tile
	for candidate in candidate_tiles:
		var score = score_tile(candidate)
		scored_tiles.append({
			"tile": candidate,
			"score": score
		})
	
	if scored_tiles.is_empty():
		print("No valid tiles.")
		if GameData.map_stages.find(GameData.current_map_size) < GameData.map_stages.size() - 1:
			GameData.increase_map_size()
			print("Increased Map Size.")
			print("New map size: ", GameData.current_map_size)
			print("New map stage index: ", GameData.map_stages.find(GameData.current_map_size))
			print("retry_max will be: ", 8 + (GameData.map_stages.find(GameData.current_map_size) * 4) + 8)
			try_hub_spawn()
			return
		else:
			print("Director: Map is completely saturated!")
			return

	# sort the tiles based on score
	scored_tiles.sort_custom(func (a, b) : return a.score > b.score)

	# spawn hub at the candidate tile
	var top_3_tiles = scored_tiles.slice(0, 3)
	
	if top_3_tiles.is_empty():
		print("Top 3 is empty!")
	var target_pos = top_3_tiles.pick_random()
	var target_tile = target_pos.tile
	spawn_hub_at(target_tile)
	
	
	## OLD SYSTEM
	## lets figure out the radius for position here
	#var map_stage = GameData.map_stages.find(GameData.current_map_size)
	#if map_stage == -1:
		#map_stage = 0
	#
	#var custom_spawn_radius = hub_base_radius + (map_stage * hub_radius_multiplier) + randi_range(-3, 1)
	#var hub_spawn_pos = select_spawn_pos(screen_center, custom_spawn_radius, hub_size)
	#
	#if hub_spawn_pos == Vector2i(-1, -1):
		## it means the director failed to find a spot even after 100 tries.
		## so we will increase the map size and try again.
		#if GameData.map_stages.find(GameData.current_map_size) < GameData.map_stages.size() - 1:
			#print("Out of space. Expanding Map")
			#GameData.increase_map_size()
			#
			#try_hub_spawn()
		#else:
			#print("Failed to spawn hub even at max map size.")
	#else:
		#spawn_hub_at(hub_spawn_pos)

func spawn_hub_at(position: Vector2i) -> void:
	var hub = research_hub_scene.instantiate()
	entities.add_child(hub)
	hub.position = position * GameData.CELL_SIZE.x
	#BuildingSpawnEffect.create_at(hub.position, get_parent(), hub_size)
	hub.register_building(hub)
	var hub_center_cell = position + Vector2i(1, 1)
	GameData.apply_influence(hub_center_cell, "hub")
	GameData.current_hub_count += 1
#endregion

#region VentSpawning
func try_vent_spawn() -> void:
	# lets figure out the radius for position here
	var map_stage = GameData.map_stages.find(GameData.current_map_size)
	
	if map_stage == -1:
		map_stage = 0
	
	# we want the vents to spawn relative to hubs
	var available_hubs = get_tree().get_nodes_in_group("hubs")
	
	if available_hubs.is_empty():
		return
	
	var candidate = []
	
	for hub in available_hubs:
		candidate.append({
			"node": hub,
			"assigned_vents": hub.assigned_vents
		})
	
	candidate.sort_custom(func (a, b): return a.assigned_vents < b.assigned_vents)
	
	var hub_with_lowest_vents = candidate[0].node
	var center = hub_with_lowest_vents.entrance_marker.global_position
	
	# NEW SYSTEM
	# once the center is set (we find the center from the above code)
	# find candidate tiles around that center in a dynamic radius
	var dynamic_min = 4 + (map_stage * 2)
	var dynamic_max = 8 + (map_stage * 3)
	
	dynamic_min = max(3, dynamic_min - 1)
	
	var scored_tiles = []
	var candidate_tiles = calculate_candidate_tiles(center, dynamic_min, dynamic_max, vent_size, 0)
	
	for candidate_tile in candidate_tiles:
		var score = score_tile(candidate_tile)
		
		if score < -5000:
			continue
		
		scored_tiles.append({
			"tile": candidate_tile,
			"score": score
		})
	
	if scored_tiles.is_empty():
		print("Director: Can't spawn vent in this call. Skipping")
		return
	
	# sort the candidates based on their score
	scored_tiles.sort_custom(func (a, b) : return a.score > b.score)
	
	# select the top 3 
	var top_3_tiles = scored_tiles.slice(0, 3)
	
	# pick one in random and spawn the vent at that position
	var target_pos = top_3_tiles.pick_random()
	var target_tile = target_pos.tile
	
	hub_with_lowest_vents.assigned_vents += 1
	
	spawn_vent_at(target_tile)
	
	## OLD SYSTEM
	#var vent_spawn_pos = select_spawn_pos(center, custom_spawn_radius, vent_size)
	#
	#if vent_spawn_pos != Vector2i(-1, -1):
		#hub_with_lowest_vents.assigned_vents += 1
		#spawn_vent_at(vent_spawn_pos, hub_with_lowest_vents)

func spawn_vent_at(vent_position: Vector2i) -> void:
	var vent = vent_scene.instantiate()
	entities.add_child(vent)
	vent.position = Vector2(vent_position) * GameData.CELL_SIZE.x + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
	#BuildingSpawnEffect.create_at(vent.position, get_parent(), vent_size)
	vent.register_building(vent)
	GameData.apply_influence(vent_position, "vent")
	GameData.current_vent_count += 1
#endregion
