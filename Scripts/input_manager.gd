extends Node2D

@export var road_builder: NewRoadBuilder

@onready var camera_2d: Camera2D = $"../Camera2D"

var mouse_pos: Vector2
var grid_pos: Vector2i
var last_build_cell: Vector2i = Vector2i(-9999, -9999)
var click_cell: Vector2i = Vector2i(-9999, -9999)
var is_building_road: bool = false
var has_moved_after_press: bool = false
var t: Tween = null

var _dragging_vent: Vent = null
var _last_vent_drag_dir: Vector2i = Vector2i(-9999, -9999)

var _grid_color := Color("4a4a4a")
var _grid_line_width := 1.5

func _ready() -> void:
	visible = false
	SignalBus.increase_map_size.connect(func(_new_size: Rect2i): _redraw_grid())

func _redraw_grid() -> void:
	await get_tree().create_timer(1.5).timeout
	queue_redraw()

func _draw() -> void:
	var cell := GameData.CELL_SIZE
	var playable = GameData.get_playable_rect()
	for x in range(playable.position.x, playable.end.x + 1):
		draw_line(
			Vector2(x * cell.x, playable.position.y * cell.y),
			Vector2(x * cell.x, playable.end.y * cell.y),
			_grid_color, _grid_line_width
		)
	for y in range(playable.position.y, playable.end.y + 1):
		draw_line(
			Vector2(playable.position.x * cell.x, y * cell.y),
			Vector2(playable.end.x * cell.x, y * cell.y),
			_grid_color, _grid_line_width
		)

func _process(_delta: float) -> void:
	mouse_pos = get_global_mouse_position()
	grid_pos = Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)
	if is_building_road and has_moved_after_press:
		update_road_ghost()

func _is_in_playable_bounds(tile: Vector2i) -> bool:
	return GameData.get_playable_rect().has_point(tile)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:

			var building = GameData.building_grid.get(grid_pos)
			if building is Vent:
				_dragging_vent = building
				_last_vent_drag_dir = building.get_driveway_direction()
				get_viewport().set_input_as_handled()
				return

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
			modulate.a = 0
			visible = true
			t = create_tween()
			t.tween_property(self, "modulate:a", 1.0, 0.08)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			modulate.a = 0
			visible = true
			t = create_tween()
			t.tween_property(self, "modulate:a", 1.0, 0.08)

	elif event is InputEventMouseButton and not event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_vent = null
			_last_vent_drag_dir = Vector2i(-9999, -9999)
			is_building_road = false
			has_moved_after_press = false
			last_build_cell = Vector2i(-9999, -9999)
			click_cell = Vector2i(-9999, -9999)
			road_builder.reset()
			visible = false
			if road_builder.ghost_road:
				road_builder.ghost_road.hide()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			road_builder.last_remove_cell = Vector2i(-9999, -9999)
			t = create_tween()
			t.tween_property(self, "modulate:a", 0.0, 0.08)
			t.tween_callback(func(): visible = false).set_delay(0.08)

	elif event is InputEventMouseMotion:
		if event.button_mask == 0:
			return

		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:

			if _dragging_vent != null:
				var drag_vec = mouse_pos - _dragging_vent.global_position
				if drag_vec.length() > 16.0:
					var angle = drag_vec.angle()
					var snapped = round(angle / (PI / 4.0)) * (PI / 4.0)
					var snapped_dir = Vector2(cos(snapped), sin(snapped)).normalized()
					var new_dir = Vector2i(round(snapped_dir.x), round(snapped_dir.y))
					if new_dir != _last_vent_drag_dir:
						_last_vent_drag_dir = new_dir
						_rebuild_vent_stub(_dragging_vent, new_dir)
				get_viewport().set_input_as_handled()
				return

			if is_building_road:
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
				if tile is NewRoadTile and not tile.is_permanent and not tile.is_fractured and not tile.just_repaired:
					var target_pos = GameData.get_cell_center(grid_pos)
					var dist = mouse_pos.distance_to(target_pos)
					if dist < 20:
						road_builder.remove_road(grid_pos)
						road_builder.last_remove_cell = grid_pos

func _rebuild_vent_stub(vent: Vent, new_dir: Vector2i) -> void:
	var old_driveway_cell = vent.entrance_cell + vent.get_driveway_direction()
	var new_driveway_cell = vent.entrance_cell + new_dir
	var old_stub = GameData.road_grid.get(old_driveway_cell)

	if old_driveway_cell != new_driveway_cell and old_stub is NewRoadTile:
		if old_stub.is_permanent and old_stub.owner_id == vent.get_instance_id():
			for old_dir in old_stub.manual_connections.duplicate():
				var old_neighbor = GameData.road_grid.get(old_driveway_cell + old_dir)
				if old_neighbor is NewRoadTile:
					old_neighbor.remove_connection(-old_dir)
			var old_id = GameData.get_cell_id(old_driveway_cell)
			if GameData.astar.has_point(old_id):
				GameData.astar.remove_point(old_id)
			old_stub.queue_free()
			GameData.road_grid.erase(old_driveway_cell)
		elif old_stub.is_permanent:
			old_stub.remove_connection(-vent.get_driveway_direction())
		else:
			old_stub.remove_connection(-vent.get_driveway_direction())

	vent.set_driveway_direction(new_dir)
	SignalBus.building_spawned.emit(vent.entrance_cell, new_dir, vent.get_instance_id())
	vent._on_map_changed()

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
