extends Node2D

@export var road_builder: NewRoadBuilder

var mouse_pos: Vector2
var grid_pos: Vector2i
var last_build_cell: Vector2i = Vector2i(-9999, -9999)
var click_cell: Vector2i = Vector2i(-9999, -9999)
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
	var bounds = GameData.current_map_size
	var playable = Rect2i(
		bounds.position.x,
		bounds.position.y + 1,
		bounds.size.x,
		bounds.size.y - 3
	)

	for x in range(playable.position.x, playable.end.x + 1):
		var line := Line2D.new()
		line.width = 1
		line.default_color = grid_color
		line.add_point(Vector2(x * cell.x, playable.position.y * cell.y))
		line.add_point(Vector2(x * cell.x, playable.end.y * cell.y))
		grid_lines.add_child(line)

	for y in range(playable.position.y, playable.end.y + 1):
		var line := Line2D.new()
		line.width = 1
		line.default_color = grid_color
		line.add_point(Vector2(playable.position.x * cell.x, y * cell.y))
		line.add_point(Vector2(playable.end.x * cell.x, y * cell.y))
		grid_lines.add_child(line)

func _process(_delta: float) -> void:
	mouse_pos = get_global_mouse_position()
	grid_pos = Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)
	if is_building_road and has_moved_after_press:
		update_road_ghost()

func _is_in_playable_bounds(tile: Vector2i) -> bool:
	var bounds = GameData.current_map_size
	var playable = Rect2i(
		bounds.position.x + 1,
		bounds.position.y + 2,
		bounds.size.x - 2,
		bounds.size.y - 4
	)
	return playable.has_point(tile)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
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
					return

			var current_mouse := get_global_mouse_position()
			grid_pos = Vector2i(
				floor(current_mouse.x / GameData.CELL_SIZE.x),
				floor(current_mouse.y / GameData.CELL_SIZE.y)
			)

			if not _is_in_playable_bounds(grid_pos):
				return

			click_cell = grid_pos
			is_building_road = true
			has_moved_after_press = false
			last_build_cell = Vector2i(-9999, -9999)
			var clicked_tile = GameData.road_grid.get(click_cell)
			if clicked_tile is NewRoadTile:
				click_cell = Vector2i(-9999, -9999)
			road_builder.set_anchor(grid_pos)
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
			last_build_cell = Vector2i(-9999, -9999)
			click_cell = Vector2i(-9999, -9999)
			road_builder.reset()
			grid_lines.visible = false
			if road_builder.ghost_road:
				road_builder.ghost_road.hide()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			road_builder.last_remove_cell = Vector2i(-9999, -9999)
			t = create_tween()
			t.tween_property(grid_lines, "modulate:a", 0.0, 0.08)
			t.tween_callback(func(): grid_lines.visible = false).set_delay(0.08)

	elif event is InputEventMouseMotion:
		if event.button_mask == 0:
			return

		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and is_building_road:
			has_moved_after_press = true
			if grid_pos != last_build_cell and grid_pos != click_cell:
				var target_pos = GameData.get_cell_center(grid_pos)
				var dist = mouse_pos.distance_to(target_pos)
				if dist < 28 and _is_in_playable_bounds(grid_pos):
					road_builder.build_road(grid_pos)
					last_build_cell = grid_pos

		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if grid_pos != road_builder.last_remove_cell:
				var tile = GameData.road_grid.get(grid_pos)
				if tile is NewRoadTile and not tile.is_permanent:
					road_builder.remove_road(grid_pos)
					road_builder.last_remove_cell = grid_pos

func update_road_ghost() -> void:
	if not road_builder or not road_builder.ghost_road:
		return
	var target_pos = GameData.get_cell_center(grid_pos)
	if not road_builder.ghost_road.visible:
		road_builder.ghost_road.global_position = target_pos
		road_builder.ghost_road.show()
	else:
		road_builder.ghost_road.global_position = road_builder.ghost_road.global_position.lerp(target_pos, 0.25)
	road_builder._update_ghost_visuals(grid_pos)
