# ============================================
# road_builder.gd
# ============================================

extends Node2D

class_name NewRoadBuilder

const DIRS := {
	Vector2i.UP: Vector2i.UP,
	Vector2i.DOWN: Vector2i.DOWN,
	Vector2i.LEFT: Vector2i.LEFT,
	Vector2i.RIGHT: Vector2i.RIGHT,
	Vector2i(1, 1): Vector2i(1, 1),
	Vector2i(1, -1): Vector2i(1, -1),
	Vector2i(-1, 1): Vector2i(-1, 1),
	Vector2i(-1, -1): Vector2i(-1, -1)
}

@onready var road_tile = preload("res://Scenes/road_tile.tscn")

# last_build_cell: the last real pipe cell built — used for handshake between real pipes
# anchor_cell: virtual start point for first drag — no pipe there, just draws the arm direction
var last_build_cell := Vector2i(-9999, -9999)
var last_remove_cell := Vector2i(-9999, -9999)
var anchor_cell := Vector2i(-9999, -9999)

var ghost_road: NewRoadTile

func _ready() -> void:
	SignalBus.building_spawned.connect(build_permanent_road)
	
	ghost_road = road_tile.instantiate()
	ghost_road.modulate = Color(1, 1, 1, 0.5)
	ghost_road.z_index = 10
	add_child(ghost_road)
	ghost_road.hide()

# Called on mouse press — sets virtual anchor (the click cell, no pipe built there)
func set_anchor(cell: Vector2i) -> void:
	anchor_cell = cell
	last_build_cell = Vector2i(-9999, -9999)

# Called on mouse release — clears all state
func reset() -> void:
	last_build_cell = Vector2i(-9999, -9999)
	anchor_cell = Vector2i(-9999, -9999)

func _update_ghost_visuals(ghost_cell: Vector2i) -> void:
	var mouse_cell = mouse_to_cell()
	var existing_building = GameData.building_grid.get(mouse_cell)

	if existing_building != null:
		ghost_road.modulate = Color(1, 0, 0, 0.5)
	else:
		ghost_road.modulate = Color(1, 1, 1, 0.5)
		ghost_road.manual_connections.clear()

	# Use last_build_cell if available, else fall back to anchor_cell
	# This makes the ghost show the arm direction from wherever the chain last was
	var arm_from := last_build_cell if last_build_cell != Vector2i(-9999, -9999) else anchor_cell
	if arm_from != Vector2i(-9999, -9999) and ghost_cell != arm_from:
		var dir_to_anchor = arm_from - ghost_cell
		if max(abs(dir_to_anchor.x), abs(dir_to_anchor.y)) <= 1:
			ghost_road.add_connection(dir_to_anchor)

	ghost_road.update_visuals()

func mouse_to_cell() -> Vector2i:
	var mouse_pos = get_global_mouse_position()
	return Vector2i(
		floor(mouse_pos.x / GameData.CELL_SIZE.x),
		floor(mouse_pos.y / GameData.CELL_SIZE.y)
	)

func build_road(cell: Vector2i) -> void:
	var building_at_cell = GameData.building_grid.get(cell)
	var was_entrance := false

	if building_at_cell != null:
		if building_at_cell is Building:
			if cell != building_at_cell.entrance_cell:
				return
			else:
				# Block vent entrances — they are not in A* and use driveway stub instead
				if building_at_cell is Vent:
					return
				was_entrance = true

	# 2. CREATE PIPE — only if cell is empty
	var current_road = GameData.road_grid.get(cell)

	if not current_road is NewRoadTile:
		if GameData.current_pipe_count <= 0:
			return

		ResourceManager.spend_tile()

		current_road = road_tile.instantiate()
		current_road.position = GameData.get_cell_center(cell)
		current_road.set_cell(cell)
		add_child(current_road)

		if was_entrance:
			current_road.is_entrance = true

		GameData.road_grid[cell] = current_road
		GameData.apply_influence(cell, "road")
		GameData.add_navigation_point(cell)

	# 3. HANDSHAKE — connect to previous real pipe OR draw arm toward anchor
	# Determine what to connect from: prefer last real pipe, fall back to anchor
	var connect_from := last_build_cell if last_build_cell != Vector2i(-9999, -9999) else anchor_cell

	if connect_from != Vector2i(-9999, -9999) and connect_from != cell:
		var dir_to_current = cell - connect_from
		if max(abs(dir_to_current.x), abs(dir_to_current.y)) <= 1:
			# Always add arm on current pipe pointing back toward connect_from
			current_road.add_connection(-dir_to_current)

			# Only do full two-way handshake + A* if connect_from has a real pipe
			var previous_road = GameData.road_grid.get(connect_from)
			if previous_road is NewRoadTile:
				previous_road.add_connection(dir_to_current)
				var id_a = GameData.get_cell_id(connect_from)
				var id_b = GameData.get_cell_id(cell)
				if not GameData.astar.are_points_connected(id_a, id_b):
					GameData.astar.connect_points(id_a, id_b)
			# If connect_from is just the anchor (no real pipe), no A* needed —
			# the arm on current_road is purely visual

	SignalBus.map_changed.emit.call_deferred()
	last_build_cell = cell

func build_road_line(target_cell: Vector2i) -> void:
	if last_build_cell == Vector2i(-9999, -9999):
		build_road(target_cell)
		return

	var diff = target_cell - last_build_cell
	var steps = max(abs(diff.x), abs(diff.y))

	for i in range(1, steps + 1):
		var lerp_t = float(i) / steps
		var intermediate = Vector2(last_build_cell).lerp(Vector2(target_cell), lerp_t).round()
		build_road(Vector2i(intermediate))

func remove_road(cell: Vector2i) -> void:
	var object_at_cell = GameData.road_grid.get(cell)

	if object_at_cell is NewRoadTile:
		if object_at_cell.is_fractured:
			return
		if object_at_cell.is_permanent:
			return

		ResourceManager.refund_tile()

		for dir in object_at_cell.manual_connections.duplicate():
			var neighbor_cell = cell + dir
			var neighbor = GameData.road_grid.get(neighbor_cell)
			if neighbor is NewRoadTile:
				neighbor.remove_connection(-dir)
				# If neighbor is a permanent stub, also disconnect A*
				if neighbor.is_permanent:
					var id_stub = GameData.get_cell_id(neighbor_cell)
					var id_cell = GameData.get_cell_id(cell)
					if GameData.astar.are_points_connected(id_stub, id_cell):
						GameData.astar.disconnect_points(id_stub, id_cell, true)

		var id = GameData.get_cell_id(cell)
		if GameData.astar.has_point(id):
			GameData.astar.remove_point(id)

		object_at_cell.queue_free()
		GameData.remove_road_influence(cell)
		GameData.road_grid.erase(cell)

	SignalBus.map_changed.emit.call_deferred()

# --- Helper Functions ---

func _connect_two_points(cell_a: Vector2i, cell_b: Vector2i) -> void:
	var road_a = GameData.road_grid.get(cell_a)
	var road_b = GameData.road_grid.get(cell_b)
	var dir_to_b = cell_b - cell_a

	if road_a is NewRoadTile:
		road_a.add_connection(dir_to_b)
	if road_b is NewRoadTile:
		road_b.add_connection(-dir_to_b)

	var id_a = GameData.get_cell_id(cell_a)
	var id_b = GameData.get_cell_id(cell_b)

	if GameData.astar.has_point(id_a) and GameData.astar.has_point(id_b):
		if not GameData.astar.are_points_connected(id_a, id_b):
			GameData.astar.connect_points(id_a, id_b)

func _connect_to_entrance(road_cell: Vector2i, entrance_cell: Vector2i, dir: Vector2i) -> void:
	var road = GameData.road_grid.get(road_cell)
	if road:
		road.add_connection(dir)

	var id_road = GameData.get_cell_id(road_cell)
	var id_ent = GameData.get_cell_id(entrance_cell)
	if GameData.astar.has_point(id_road) and GameData.astar.has_point(id_ent):
		if not GameData.astar.are_points_connected(id_road, id_ent):
			GameData.astar.connect_points(id_road, id_ent)

func build_permanent_road(cell: Vector2i, direction: Vector2i, creator_id: int = -1) -> void:

	# Hub case — just register entrance cell in A*, no stub needed
	if direction == Vector2i(-99, -99):
		if not GameData.road_grid.get(cell) is NewRoadTile:
			var current_road = road_tile.instantiate()
			current_road.position = GameData.get_cell_center(cell)
			current_road.set_cell(cell)
			current_road.is_permanent = true
			current_road.owner_id = creator_id # Initialize owner here too
			add_child(current_road)
			GameData.road_grid[cell] = current_road
			GameData.add_navigation_point(cell)
		SignalBus.map_changed.emit.call_deferred()
		return

	# Vent case — driveway stub, entrance cell never in A*
	var driveway_cell = cell + direction

	# 1. Teardown logic: Only clear the cell IF it is a permanent stub OWNED by this building
	var old_stub = GameData.road_grid.get(driveway_cell)
	if old_stub is NewRoadTile:
		if old_stub.is_permanent:
			if old_stub.owner_id == creator_id:
				# It is MY stub. Clear it so I can move it.
				old_stub.manual_connections.clear()
				for dir in old_stub.arm_lines.keys().duplicate():
					old_stub._destroy_arm(dir)
				var old_id = GameData.get_cell_id(driveway_cell)
				var old_conns = GameData.astar.get_point_connections(old_id)
				for conn_id in old_conns:
					GameData.astar.disconnect_points(old_id, conn_id, true)
				
				old_stub.queue_free()
				GameData.road_grid.erase(driveway_cell)
			else:
				# It belongs to another building! 
				# Don't delete it. Just connect to it and exit early.
				old_stub.add_connection(-direction)
				return 
		else:
			# It's a player pipe!
			ResourceManager.refund_tile()
			old_stub.remove_connection(-direction)

	# 2. Create/Update tile at driveway_cell
	var current_road = GameData.road_grid.get(driveway_cell)
	if not current_road is NewRoadTile:
		current_road = road_tile.instantiate()
		current_road.position = GameData.get_cell_center(driveway_cell)
		current_road.set_cell(driveway_cell)
		current_road.is_permanent = true 
		current_road.owner_id = creator_id # SET the name tag here
		add_child(current_road)
		GameData.road_grid[driveway_cell] = current_road
		GameData.add_navigation_point(driveway_cell)

	# Connect visual arm back to building
	current_road.add_connection(-direction)

	# Connect to any existing pipe neighbor outward
	var neighbor_cell = driveway_cell + direction
	var neighbor = GameData.road_grid.get(neighbor_cell)
	if neighbor is NewRoadTile:
		var id_stub = GameData.get_cell_id(driveway_cell)
		var id_neighbor = GameData.get_cell_id(neighbor_cell)
		if GameData.astar.has_point(id_stub) and GameData.astar.has_point(id_neighbor):
			if not GameData.astar.are_points_connected(id_stub, id_neighbor):
				GameData.astar.connect_points(id_stub, id_neighbor)

	SignalBus.map_changed.emit.call_deferred()
