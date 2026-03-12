extends Building
class_name Vent

const DRIVEWAY_OFFSET := Vector2(0, 32)  # base offset, unrotated

# Zone-based send intervals (seconds per packet)
const INTERVAL_CORE     := 4.0
const INTERVAL_INNER    := 4.0
const INTERVAL_OUTER    := 3.0
const INTERVAL_FRONTIER := 2.0

@onready var driveway_marker: Marker2D = $DrivewayMarker
@onready var fan: Sprite2D = $Fan
@onready var max_capacity: int = 2

@onready var left_cloud: GPUParticles2D = $LeftCloud
@onready var right_cloud: GPUParticles2D = $RightCloud

var packet_scene = preload("res://Scenes/packet.tscn")

var is_connected_to_network: bool = false
var current_capacity: int = 0

var send_interval: float = INTERVAL_CORE
var send_timer: float = 0.0
var _notify_cooldown: float = 0.0

const BURST_DURATION   := 10.0
const BURST_MULTIPLIER := 1.5
var _burst_timer: float = 0.0
var _is_bursting: bool  = false

var fan_rotation_speed = 4.0
const FAN_BASE_SPEED := 4.0
var _fan_tween: Tween = null

var click_position: Vector2
var has_dragged: bool = false


func get_top_left_px(step: float) -> Vector2:
	return global_position - (Vector2(grid_size) * step / 2.0)

func _physics_process(delta: float) -> void:
	fan.rotation += fan_rotation_speed * delta

#func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	#if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_LEFT:
			#if event.is_pressed():
				#get_viewport().set_input_as_handled()
				#click_position = get_global_mouse_position()
				#has_dragged = false
			#else:
				#if not has_dragged:
					#print("Vent clicked (no drag) - rotating!")
					#rotate_45_degrees()
				#get_viewport().set_input_as_handled()
#
	#elif event is InputEventMouseMotion:
		#if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			#var current_pos = get_global_mouse_position()
			#if click_position.distance_to(current_pos) > 24.0:
				#has_dragged = true

func _ready():
	left_cloud.restart()
	right_cloud.restart()
	SignalBus.camera_shake.emit(0.25, 4.0)
	cell_type = "VENT"
	super()
	SignalBus.map_changed.connect(_on_map_changed)
	SignalBus.trigger_vent_burst.connect(_on_fracture_wave)

	await get_tree().process_frame

	var dir_vec = (driveway_marker.global_position - global_position).normalized()
	var driveway_direction = Vector2i(round(dir_vec.x), round(dir_vec.y))
	SignalBus.building_spawned.emit(entrance_cell, driveway_direction, get_instance_id())

	_set_interval_from_zone()
	send_timer = randf_range(0.0, send_interval)

	_on_map_changed()

func _set_interval_from_zone() -> void:
	var zone = GameData.get_zone_for_cell(entrance_cell)
	match zone:
		GameData.Zone.CORE:     send_interval = INTERVAL_CORE
		GameData.Zone.INNER:    send_interval = INTERVAL_INNER
		GameData.Zone.OUTER:    send_interval = INTERVAL_OUTER
		GameData.Zone.FRONTIER: send_interval = INTERVAL_FRONTIER
		_:                      send_interval = INTERVAL_CORE

func _process(delta: float) -> void:
	if not is_connected_to_network:
		return
	if _notify_cooldown > 0.0:
		_notify_cooldown -= delta
	# Burst countdown
	if _is_bursting:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_end_burst()
	send_timer -= delta
	if send_timer <= 0.0:
		send_timer = _current_interval()
		if current_capacity < max_capacity:
			_try_send_packet()

func _current_interval() -> float:
	return send_interval / BURST_MULTIPLIER if _is_bursting else send_interval

func _on_fracture_wave() -> void:
	_is_bursting = true
	_burst_timer = BURST_DURATION
	# Visual — tint fan/vent orange to signal instability
	var t := create_tween()
	t.tween_property(self, "modulate", Color(1.6, 0.2, 1.4, 1.0), 0.1)

func _end_burst() -> void:
	_is_bursting = false
	var t := create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.4)

func _try_send_packet() -> void:
	var best_hub: Hub = null
	var best_score: float = -1.0

	var driveway_cell = entrance_cell + get_driveway_direction()
	var my_id = GameData.get_cell_id(driveway_cell)  # ← driveway_cell, not entrance_cell

	for cell in GameData.building_grid:
		var building = GameData.building_grid[cell]
		if not building is Hub:
			continue
		if building.is_fractured or building.is_rate_limited:
			continue

		var hub_id = GameData.get_cell_id(building.entrance_cell)
		if not GameData.astar.has_point(my_id) or not GameData.astar.has_point(hub_id):
			continue

		var path = GameData.astar.get_id_path(my_id, hub_id)
		if path.size() < 2:
			continue

		var path_length: float = path.size()
		var score: float = (building.oxygen_backlog + 1.0) / path_length
		if score > best_score:
			best_score = score
			best_hub = building

	if best_hub == null:
		return

	_spawn_packet(best_hub)

func get_driveway_direction() -> Vector2i:
	var rotated := DRIVEWAY_OFFSET.rotated(deg_to_rad(driveway_marker.rotation_degrees))
	return Vector2i(round(rotated.normalized().x), round(rotated.normalized().y))

func set_driveway_direction(new_dir: Vector2i) -> void:
	var angle = Vector2(new_dir).angle()
	driveway_marker.rotation_degrees = rad_to_deg(angle - Vector2(DRIVEWAY_OFFSET).angle())

#func rotate_45_degrees() -> void:
	#var old_direction = get_driveway_direction()  # snapshot BEFORE rotating
	#var old_driveway_cell = entrance_cell + old_direction
#
	## Teardown old driveway stub
	#var old_stub = GameData.road_grid.get(old_driveway_cell)
	#if old_stub is NewRoadTile:
		## Remove visual arms from neighbors
		#for old_dir in old_stub.manual_connections.duplicate():
			#var old_neighbor = GameData.road_grid.get(old_driveway_cell + old_dir)
			#if old_neighbor is NewRoadTile:
				#old_neighbor.remove_connection(-old_dir)
		## Remove A* connections
		#var old_id = GameData.get_cell_id(old_driveway_cell)
		#var old_conns = GameData.astar.get_point_connections(old_id)
		#for conn_id in old_conns:
			#GameData.astar.disconnect_points(old_id, conn_id, true)
		## Destroy the tile entirely
		#old_stub.queue_free()
		#GameData.road_grid.erase(old_driveway_cell)
#
	#driveway_marker.rotation_degrees += 45
	#if driveway_marker.rotation_degrees >= 360:
		#driveway_marker.rotation_degrees = 0
#
	#var driveway_direction = get_driveway_direction()
	#SignalBus.building_spawned.emit(entrance_cell, driveway_direction)
	#_on_map_changed()

func _on_map_changed():
	var driveway_cell = entrance_cell + get_driveway_direction()
	var my_id = GameData.get_cell_id(driveway_cell)
	if not GameData.astar.has_point(my_id):
		return
	update_connection_status()

func update_connection_status():
	var was_connected = is_connected_to_network
	is_connected_to_network = false

	if GameData.building_grid.is_empty():
		return

	var driveway_cell = entrance_cell + get_driveway_direction()
	var start_id = GameData.get_cell_id(driveway_cell)

	for cell in GameData.building_grid:
		var building = GameData.building_grid[cell]
		if building is Hub:
			var end_id = GameData.get_cell_id(building.entrance_cell)
			if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
				var path = GameData.astar.get_id_path(start_id, end_id)
				if path.size() > 0:
					is_connected_to_network = true
					break

	if was_connected and not is_connected_to_network:
		send_timer = send_interval
		print("Vent at %s disconnected from network" % entrance_cell)
	elif not was_connected and is_connected_to_network:
		send_timer = randf_range(0.5, 1.5)
		print("Vent at %s reconnected to network" % entrance_cell)

func notify_capacity_freed() -> void:
	if _notify_cooldown > 0.0:
		return
	if is_connected_to_network and current_capacity < max_capacity:
		_notify_cooldown = 0.2
		_try_send_packet()

func _spawn_packet(target_hub: Hub) -> void:
	current_capacity += 1
	var driveway_cell = entrance_cell + get_driveway_direction()
	var path_container = Path2D.new()
	get_parent().add_child.call_deferred(path_container)
	var oxygen_packet = packet_scene.instantiate()
	path_container.add_child(oxygen_packet)
	oxygen_packet.global_position = global_position  # still spawns visually from vent
	oxygen_packet.setup_path(self, driveway_cell, target_hub.entrance_cell)  # ← driveway_cell
	_on_packet_spawned()

func _on_packet_spawned() -> void:
	var glow := create_tween()
	glow.tween_property(self, "modulate", Color(1.4, 1.4, 1.6, 1.0), 0.08)
	glow.tween_property(self, "modulate", Color.WHITE, 0.35)
	if _fan_tween:
		_fan_tween.kill()
	_fan_tween = create_tween()
	_fan_tween.tween_method(func(v): fan_rotation_speed = v, fan_rotation_speed, FAN_BASE_SPEED * 3.5, 0.1)
	_fan_tween.tween_method(func(v): fan_rotation_speed = v, FAN_BASE_SPEED * 3.5, FAN_BASE_SPEED, 0.8)

func get_max_capacity() -> int:
	return max_capacity

func get_current_capacity() -> int:
	return current_capacity
