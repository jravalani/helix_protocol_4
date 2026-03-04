extends Node2D

@export var road_builder: NewRoadBuilder

var mouse_pos: Vector2
var grid_pos: Vector2i

var last_build_cell: Vector2i
var is_building_road: bool = false

func _ready() -> void:
	print("InputManager is ready!")
	print("RoadBuilder exists: ", road_builder != null)

func _process(delta: float) -> void:
	mouse_pos = get_global_mouse_position()
	grid_pos = Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)
	
	if is_building_road:
		update_road_ghost()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_building_road = true
			last_build_cell = Vector2i(-5000, -5000)  # ✅ FIXED - Reset to invalid
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			road_builder.remove_road(grid_pos)
	
	elif event is InputEventMouseButton and not event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_building_road = false
			last_build_cell = Vector2i(-5000, -5000)
			if road_builder.ghost_road:
				road_builder.ghost_road.hide()
	
	elif event is InputEventMouseMotion:
		if event.button_mask == 0:
			return
		
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and is_building_road:
			# First drag motion - build at starting cell
			if last_build_cell == Vector2i(-5000, -5000):
				road_builder.build_road(grid_pos)
				last_build_cell = grid_pos
			# Subsequent cells - only if moved to new cell
			elif grid_pos != last_build_cell:
				var target_pos = GameData.get_cell_center(grid_pos)
				var dist = mouse_pos.distance_to(target_pos)
				if dist < 24.0:
					road_builder.build_road(grid_pos)
					last_build_cell = grid_pos
		
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			road_builder.remove_road(grid_pos)

func update_road_ghost() -> void:
	if not road_builder or not road_builder.ghost_road:
		return
	
	if not road_builder.ghost_road.visible:
		# First time showing - snap to position
		var target_pos = GameData.get_cell_center(grid_pos)
		road_builder.ghost_road.global_position = target_pos
		road_builder.ghost_road.show()
	else:
		# Already visible - lerp smoothly
		var target_pos = GameData.get_cell_center(grid_pos)
		road_builder.ghost_road.global_position = road_builder.ghost_road.global_position.lerp(target_pos, 0.25)
	
	road_builder._update_ghost_visuals(grid_pos)
