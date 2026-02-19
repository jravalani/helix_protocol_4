extends Node2D

# =============================================================================
# SCRIPT: THE ABYSSAL ARCHITECT (Director System)
# =============================================================================
# THEME: The Great Ascent - A journey from the crushing depths to the surface.
# CORE LOOP: 
#   1. Director seeds "The Colony" (Hubs & Vents).
#   2. Player routes Oxygen from Vents to Hubs to generate Data.
#   3. Resources are spent on Rocket Parts or protecting the colony.
#   4. Global Pressure rises, threatening to crush unprotected structures.
#
# DESIGN PHILOSOPHY:
# - AESTHETIC FLOW: Buildings should cluster naturally to look like a 
#   deliberate undersea habitat rather than a scattered grid.
# - RHYTHMIC PACING: Hubs are the "Anchor Points" of the colony. Vents are the 
#   "Satellites." The Director must ensure a pleasing ratio between them.
# - PRESSURE AS A GARDENER: Pressure isn't just difficulty; it's a force that
#   prunes the map, forcing the player to choose what to save and where to expand.
#
# KEY METRICS:
# - Hubs: Forced spawns (Mini Motorways style). High priority.
# - Vents: Organic spawns. Often cluster near Hubs for visual cohesion.
# - Map Expansion: Occurs when the Director "runs out of room" for the vision.
# =============================================================================

const MAX_SPAWN_POS_TRIES: int = 100

# scene preloads
@onready var rocket_scene: PackedScene = preload("res://Scenes/rocket.tscn")
@onready var research_hub_scene: PackedScene = preload("res://Scenes/hub3x2.tscn")
@onready var vent_scene: PackedScene = preload("res://Scenes/vent.tscn")

# node references
@onready var camera_2d: Camera2D = $"../Camera2D"
@onready var line_2d: Line2D = $Line2D
@onready var entities: Node = $"../Entities"

# Camera buffer 
@onready var camera_buffer: int = 1

# spawn radius
var hub_base_radius: int = 4
var vent_base_radius: int = 3

var hub_interval: float = 60.0
var vent_interval: float = 20.0
var vent_acceleration: float = 0.92
var min_vent_interval: float = 8
var hub_timer: float = 0.0
var vent_timer: float = 0.0
var hub_rotation = [0, PI/2, 3*PI/2]
var hub_radius_multiplier: int = 2
var hub_size: Vector2i = Vector2i(3, 2)
var vent_size: Vector2i = Vector2i(1, 1)
var rocket_size: Vector2i = Vector2i(3, 3)

var intro_cooldown: float = 3


# pressure system
var increment = GameData.BASE_RATE * (1 + (GameData.current_pressure / GameData.MAX_PRESSURE))

# screen center
var screen_center: Vector2

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
	# every frame pressure increment will happen
	# at certain pressure levels game states would change
	GameData.current_pressure += increment * delta
	
	if GameData.current_pressure >= 40 and GameData.current_pressure_phase == 1:
		transition_to_phase(2)
	if GameData.current_pressure >= 70 and GameData.current_pressure_phase == 2:
		transition_to_phase(3)
	
	# every frame delta would be subtracted from hub interval and vent interval
	# when the timer <= 0 we spawn hub and vent and set their intervals
	if intro_cooldown > 0:
		intro_cooldown -= delta
		return
	
	hub_timer -= delta
	vent_timer -= delta
	
	if hub_timer <= 0:
		pass
		# spawn a hub
		try_hub_spawn()
		hub_timer += hub_interval
		vent_interval = max(min_vent_interval, vent_interval * vent_acceleration)
	if vent_timer <= 0:
		pass
		# spawn a vent
		try_vent_spawn()
		vent_timer += vent_interval

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
#endregion

#region Functions
func is_area_clear(target_coord: Vector2i, area_size: Vector2i, camera_bounds: Rect2i) -> bool:
	for x in range(area_size.x):
		for y in range(area_size.y):
			var current_tile = target_coord + Vector2i(x, y)
			
			if not camera_bounds.has_point(current_tile):
				return false
			
			if GameData.building_grid.has(current_tile) or GameData.road_grid.has(current_tile):
				return false
	return true

func select_spawn_pos(from_center: Vector2, radius_in_tiles: int, for_size: Vector2i) -> Vector2i:
	# send out a ping at a specific angle and distance from the center of the screen.
	# if that ping hits an obstacle, find different angle and try again.
	# this system requires no. of tries 
	# lets start with 100
	var camera_bounds = get_camera_bounds()
	for i in range(MAX_SPAWN_POS_TRIES):
		var random_angle = randf_range(0, TAU)
		var direction = Vector2(cos(random_angle), sin(random_angle))
		var target_pos = from_center + (direction * radius_in_tiles * GameData.CELL_SIZE.x)
		
		var target_tile = Vector2i(floor(target_pos / GameData.CELL_SIZE))
		
		#line_2d.points = [from_center, target_pos]
		# check if the area is clear here for spawning hubs / vents
		if is_area_clear(target_tile, for_size, camera_bounds):
			return target_tile
	print("Director failed to find a spot after ", MAX_SPAWN_POS_TRIES, "tries.")
	return Vector2i(-1, -1)

func transition_to_phase(phase_number: int) -> void:
	if GameData.current_pressure_phase < GameData.MAX_PRESSURE_PHASE:
		GameData.current_pressure_phase = phase_number
	
	match GameData.current_pressure_phase:
		2:
			print("Director: Pressure Critical. Phase 2 initiated!")
		3:
			print("Director: Hull Integrity Failing. Phase 3 initiated!")
	
#endregion

#region First Colony
func spawn_initial_colony() -> void:
	"""
	Spawn 1 research-hub and 1 vent at the start of the game to let the player get going.
	"""
	# first we spawn a hub.
	var target_tile_for_hub = select_spawn_pos(screen_center, hub_base_radius, hub_size)
	
	if target_tile_for_hub != Vector2i(-1, -1):
		# instantiate the hub scene at the tile.
		var research_hub = research_hub_scene.instantiate()
		entities.add_child(research_hub)
		research_hub.position = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
		research_hub.register_building(research_hub)
		# now we will spawn 2 vents near the hub
		var hub_center = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
		
		var target_tile_for_vent_1 = select_spawn_pos(hub_center, vent_base_radius, vent_size)
		
		if target_tile_for_vent_1 != Vector2i(-1, -1):
			var vent_1 = vent_scene.instantiate()
			entities.add_child(vent_1)
			vent_1.position = Vector2(target_tile_for_vent_1 * GameData.CELL_SIZE.x) + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
			vent_1.register_building(vent_1)
	else:
		print("Cannot spawn initial colony hub!")
#endregion

#region HubSpawning

func try_hub_spawn() -> void:
	# lets figure out the radius for position here
	var map_stage = GameData.map_stages.find(GameData.current_map_size)
	if map_stage == -1:
		map_stage = 0
	
	var custom_spawn_radius = hub_base_radius + (map_stage * hub_radius_multiplier) + randi_range(-3, 1)
	var hub_spawn_pos = select_spawn_pos(screen_center, custom_spawn_radius, hub_size)
	
	if hub_spawn_pos == Vector2i(-1, -1):
		# it means the director failed to find a spot even after 100 tries.
		# so we will increase the map size and try again.
		if GameData.map_stages.find(GameData.current_map_size) < GameData.map_stages.size() - 1:
			print("Out of space. Expanding Map")
			GameData.increase_map_size()
			
			try_hub_spawn()
		else:
			print("Failed to spawn hub even at max map size.")
	else:
		spawn_hub_at(hub_spawn_pos)

func spawn_hub_at(position: Vector2i) -> void:
	var hub = research_hub_scene.instantiate()
	entities.add_child(hub)
	hub.position = position * GameData.CELL_SIZE.x
	hub.register_building(hub)
#endregion

#region VentSpawning

func try_vent_spawn() -> void:
	# lets figure out the radius for position here
	var map_stage = GameData.map_stages.find(GameData.current_map_size)
	
	if map_stage == -1:
		map_stage = 0
	
	var custom_spawn_radius = vent_base_radius + (map_stage * 1.5) + randi_range(-3, 1)
	
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
	var center = hub_with_lowest_vents.global_position
	var vent_spawn_pos = select_spawn_pos(center, custom_spawn_radius, vent_size)
	
	if vent_spawn_pos != Vector2i(-1, -1):
		hub_with_lowest_vents.assigned_vents += 1
		spawn_vent_at(vent_spawn_pos, hub_with_lowest_vents)

func spawn_vent_at(vent_position: Vector2, hub: Node2D) -> void:
	var vent = vent_scene.instantiate()
	entities.add_child(vent)
	vent.position = vent_position * GameData.CELL_SIZE.x + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
	vent.register_building(vent)
#endregion
