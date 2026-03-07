extends Node2D
@export var road_builder: NewRoadBuilder
var mouse_pos: Vector2
var grid_pos: Vector2i
var last_build_cell: Vector2i
var is_building_road: bool = false
var has_moved_after_press: bool = false
var grid_lines: Node2D
var t: Tween = null

func _ready() -> void:
	_draw_grid()
	grid_lines.visible = false

func _draw_grid() -> void:
	grid_lines = Node2D.new()
	add_child(grid_lines)
	var grid_color := Color("4a4a4a")
	var cell := GameData.CELL_SIZE
	var half_count := 60
	for x in range(-half_count, half_count + 1):
		var line := Line2D.new()
		line.width = 1
		line.default_color = grid_color
		line.add_point(Vector2(x * cell.x, -half_count * cell.y))
		line.add_point(Vector2(x * cell.x,  half_count * cell.y))
		grid_lines.add_child(line)
	for y in range(-half_count, half_count + 1):
		var line := Line2D.new()
		line.width = 1
		line.default_color = grid_color
		line.add_point(Vector2(-half_count * cell.x, y * cell.y))
		line.add_point(Vector2( half_count * cell.x, y * cell.y))
		grid_lines.add_child(line)

func _process(delta: float) -> void:
	mouse_pos = get_global_mouse_position()
	grid_pos = Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)
	if is_building_road and has_moved_after_press:
		update_road_ghost()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Query layer 2 for buildings (vents/hubs)
			var space := get_world_2d().direct_space_state
			var query := PhysicsPointQueryParameters2D.new()
			query.position = get_global_mouse_position()
			query.collision_mask = 2
			query.collide_with_areas = true
			query.collide_with_bodies = false
			var results := space.intersect_point(query)

			if results.size() > 0:
				var parent = results[0].collider.get_parent()
				if parent is Building:
					if grid_pos != parent.entrance_cell:
						return
				else:
					return  # unknown collider, block to be safe

			# Empty cell or entrance cell — allow road building
			is_building_road = true
			has_moved_after_press = false
			last_build_cell = Vector2i(-5000, -5000)
			grid_lines.modulate.a = 0
			grid_lines.visible = true
			t = create_tween()
			t.tween_property(grid_lines, "modulate:a", 1.0, 0.08)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			grid_lines.modulate.a = 0
			grid_lines.visible = true
			t = create_tween()
			t.tween_property(grid_lines, "modulate:a", 1.0, 0.08)

	elif event is InputEventMouseButton and not event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_building_road = false
			has_moved_after_press = false
			last_build_cell = Vector2i(-5000, -5000)
			grid_lines.visible = false
			if road_builder.ghost_road:
				road_builder.ghost_road.hide()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			t = create_tween()
			t.tween_property(grid_lines, "modulate:a", 0.0, 0.08)
			t.tween_callback(func(): grid_lines.visible = false).set_delay(0.08)

	elif event is InputEventMouseMotion:
		if event.button_mask == 0:
			return

		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and is_building_road:
			has_moved_after_press = true
			if last_build_cell == Vector2i(-5000, -5000):
				road_builder.build_road(grid_pos)
				last_build_cell = grid_pos
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
		var target_pos = GameData.get_cell_center(grid_pos)
		road_builder.ghost_road.global_position = target_pos
		road_builder.ghost_road.show()
	else:
		var target_pos = GameData.get_cell_center(grid_pos)
		road_builder.ghost_road.global_position = road_builder.ghost_road.global_position.lerp(target_pos, 0.25)
	road_builder._update_ghost_visuals(grid_pos)
