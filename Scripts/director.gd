extends Node2D

@onready var workplace_scene = preload("res://Scenes/workplace.tscn")
@onready var house_scene = preload("res://Scenes/house.tscn")
@onready var building_timer: Timer = $BuildingTimer
@onready var map_timer: Timer = $TemporaryMapTimer

@export var playable_margin_cells: int = 2
@export var spawn_buffer_cells: int = 1

var all_houses: Array[Node2D] = []
var pending_requests: Array[Node2D] = []

func _ready() -> void:
	print("=== INITIAL STATE ===")
	print("Current map size: ", GameData.current_map_size)
	print("Building timer wait time: ", building_timer.wait_time)
	print("Building timer autostart: ", building_timer.autostart)
	
	# Make sure timer is connected
	if not building_timer.timeout.is_connected(_on_building_timer_timeout):
		building_timer.timeout.connect(_on_building_timer_timeout)
		print("Connected building timer")
	
	building_timer.start()
	print("Building timer started")
	
	map_timer.start()
	
	SignalBus.delivery_requested.connect(_on_delivery_requested)
	SignalBus.car_returned_home.connect(process_backlog)
	SignalBus.map_changed.connect(_on_map_changed)

func _on_map_changed() -> void:
	await get_tree().process_frame
	process_backlog()

func _on_delivery_requested(requester: Node2D) -> void:
	pending_requests.append(requester)
	process_backlog()

func process_backlog() -> void:
	if all_houses.is_empty() or pending_requests.is_empty():
		return

	# 1. Get all houses that have at least one car free
	var houses_to_check = all_houses.filter(func(h):
		return h.is_connected_to_workplace and h.active_cars < h.max_cars
	)

	for i in range(pending_requests.size() - 1, -1, -1):
		var target_cell = pending_requests[i].entrance_cell
		
		# 2. Sort so we always try the closest house first
		houses_to_check.sort_custom(func(a, b):
			return a.entrance_cell.distance_squared_to(target_cell) < b.entrance_cell.distance_squared_to(target_cell)
		)
		
		for house in houses_to_check:
			# 3. Try to dispatch. 
			# Inside try_dispatch, active_cars will increase.
			if house.try_dispatch(target_cell):
				pending_requests.remove_at(i)
				
				# 4. ONLY erase if the house is now truly full
				if house.active_cars >= house.max_cars:
					houses_to_check.erase(house)
				
				# We found a house for this request, move to the next request
				break

func _on_building_timer_timeout() -> void:
	print("\n>>> BUILDING TIMER FIRED <<<")
	attempt_spawn()

func attempt_spawn() -> void:
	var map_rect = GameData.current_map_size
	var spawn_rect = map_rect.grow(-(playable_margin_cells + spawn_buffer_cells))
	
	var camera = get_viewport().get_camera_2d()
	if not camera: return

	# 1. Get the Viewport and its inverse transform
	# This lets us translate "Screen Pixels" back into "World Coordinates"
	var viewport_size = get_viewport().get_visible_rect().size
	var canvas_xform = get_viewport().get_canvas_transform().affine_inverse()

	# 2. Define the exact Screen Pixels of your "Fog Hole"
	# These MUST match the export variables in your fog_of_war.gd
	var hole_min_screen = Vector2(100, 60) # left, top
	var hole_max_screen = viewport_size - Vector2(100, 120) # right, bottom

	# 3. Convert those screen points to World Coordinates
	var screen_world_min = canvas_xform * hole_min_screen
	var screen_world_max = canvas_xform * hole_max_screen
	
	# 4. Convert World Coordinates to Grid Cells (and add the 1-cell safety margin)
	var screen_cell_min = Vector2i(floor(screen_world_min.x / GameData.CELL_SIZE.x), floor(screen_world_min.y / GameData.CELL_SIZE.x)) + Vector2i(1, 1)
	var screen_cell_max = Vector2i(floor(screen_world_max.x / GameData.CELL_SIZE.x), floor(screen_world_max.y / GameData.CELL_SIZE.x)) - Vector2i(1, 1)
	
	var visible_rect = Rect2i(screen_cell_min, screen_cell_max - screen_cell_min)
	
	# 5. Intersection: Area that is BOTH Unlocked and Inside the Fog Hole
	var valid_spawn_zone = spawn_rect.intersection(visible_rect)

	# ... rest of your instantiation logic ...
	var scene = house_scene if randf() > 0.5 else workplace_scene
	var b = scene.instantiate()
	var b_size = b.grid_size

	# Ensure the building's FOOTPRINT fits inside the zone
	var max_x = valid_spawn_zone.end.x - b_size.x
	var max_y = valid_spawn_zone.end.y - b_size.y

	if max_x < valid_spawn_zone.position.x or max_y < valid_spawn_zone.position.y:
		b.queue_free()
		building_timer.start()
		return

	var target_cell = Vector2i(randi_range(valid_spawn_zone.position.x, max_x), randi_range(valid_spawn_zone.position.y, max_y))
	finalize_building_spawn(b, target_cell, valid_spawn_zone)
	building_timer.start()

func finalize_building_spawn(b: Node2D, cell: Vector2i, valid_zone: Rect2i) -> void:
	# Use the custom zone check to ensure it's still visible
	if is_area_clear_custom(cell, b.grid_size, valid_zone):
		var origin = Vector2(cell) * 64.0
		var offset = (Vector2(b.grid_size) * 64.0) / 2.0
		
		b.position = origin + offset
		$"../Entities".add_child(b)
		
		if b is House:
			all_houses.append(b)
			b.tree_exited.connect(func(): all_houses.erase(b))
		
		if b is Workplace:
			b.shipment_interval = randf_range(5.0, 20.0)
			
		SignalBus.map_changed.emit.call_deferred()
	else:
		b.queue_free()

func is_area_clear_custom(start_cell: Vector2i, size: Vector2i, constraint_rect: Rect2i) -> bool:
	# Ensure the building footprint is entirely inside the valid zone
	var building_rect = Rect2i(start_cell, size)
	if not constraint_rect.encloses(building_rect):
		return false
		
	# Check for overlaps with other buildings
	for x in range(-1, size.x + 1):
		for y in range(-1, size.y + 1):
			if GameData.building_grid.has(start_cell + Vector2i(x, y)):
				return false
			if GameData.road_grid.has(start_cell + Vector2i(x, y)):
				return false
	return true

func _on_temporary_map_timer_timeout() -> void:
	print("=== MAP EXPANDING ===")
	GameData.increase_map_size()
	print("New map size: ", GameData.current_map_size)
	map_timer.start()
