extends Node2D

"""
1. keeps track of what the player is currently trying to do.
example build road, remove road etc.
2. listens to the signal bus to change the mode when player clicks a UI icon.
3. after listening to the signal it then calls the function for the same
tool.
"""
@export var road_builder: NewRoadBuilder

var current_mode = "NONE"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	SignalBus.build_road.connect(_on_build_road)
	SignalBus.rotate_house.connect(_on_rotate_house)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if current_mode == "NONE":
		if road_builder and road_builder.ghost_road:
			road_builder.ghost_road.hide()
		return
	
	var mouse_pos = get_global_mouse_position()
	var grid_pos = Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x), 
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
		)
	
	match current_mode:
		"ROAD":
			# tell road builder to move ghost
			# if mouse actually clicks, build
			# if right click is held, remove
			handle_road_logic(grid_pos, mouse_pos)
		"ROTATE":
			# stop road functions
			handle_house_rotation(grid_pos, mouse_pos)

func _on_build_road() -> void:
	print("I am input manager and I have received the signal 
	from road build button to build roads!")
	current_mode = "ROAD"

func _on_rotate_house() -> void:
	print("I am input manager and  I have received the signal
	from rotate house button to rotate house!")
	current_mode = "ROTATE"

func handle_road_logic(grid_pos: Vector2i, mouse_pos: Vector2) -> void:
	road_builder.ghost_road.show()
	var target_pos = GameData.get_cell_center(grid_pos)
	
	road_builder.ghost_road.global_position = road_builder.ghost_road.global_position.lerp(target_pos, 0.25)
	road_builder._update_ghost_visuals(grid_pos)
	
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and road_builder.last_build_cell == Vector2i(-1, -1):
		road_builder.build_road(grid_pos)
		road_builder.last_build_cell = grid_pos
	
	# handle building logic (left drag)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if grid_pos != road_builder.last_build_cell:
			var dist_to_cell_center = mouse_pos.distance_to(target_pos)
			if dist_to_cell_center < 24.0:
				road_builder.build_road_line(grid_pos)
	
	# handle removing logic (right drag)
	elif  Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		road_builder.remove_road(grid_pos)
	
	# if no buttons are pressed, reset the last build cell
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		road_builder.last_build_cell = Vector2i(-1, -1)
		road_builder.ghost_road.hide()

func handle_house_rotation(grid_pos: Vector2i, mouse_pos: Vector2) -> void:
	if Input.is_action_just_pressed("left_click"):
		var space_state = get_world_2d().direct_space_state
		
		# Use point query instead of raycast for top-down grid detection
		var query = PhysicsPointQueryParameters2D.new()
		query.position = mouse_pos  # mouse_pos is already in world coords from get_global_mouse_position()
		query.collide_with_areas = true
		query.collision_mask = 2  # Layer 2 for houses
		
		var result = space_state.intersect_point(query)
		print("Point query at: ", mouse_pos, " Result: ", result)
		
		if result.size() > 0:
			var hit_node = result[0].collider
			print("Hit node: ", hit_node.name)
			if hit_node.has_method("rotate_45_degrees"):
				hit_node.rotate_45_degrees()
			else:
				print("Node doesn't have rotate_45_degrees method")
	
