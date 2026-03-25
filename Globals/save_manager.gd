extends Node

const SAVE_PATH = "user://savegame.save"

var is_loading: bool = false
var _pending_save_data: Dictionary = {}

# Scene preloads for entity restoration
var _rocket_scene: PackedScene = preload("res://Scenes/rocket.tscn")
var _hub_scene: PackedScene = preload("res://Scenes/hub3x2.tscn")
var _vent_scene: PackedScene = preload("res://Scenes/vent.tscn")
var _road_tile_scene: PackedScene = preload("res://Scenes/road_tile.tscn")


# ═════════════════════════════════════════════════════════════════
#region Vector2i / Rect2i Helpers
# ═════════════════════════════════════════════════════════════════

static func vec2i_to_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


static func key_to_vec2i(s: String) -> Vector2i:
	var parts = s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


static func vec2_to_array(v: Vector2) -> Array:
	return [v.x, v.y]


static func array_to_vec2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func rect2i_to_dict(r: Rect2i) -> Dictionary:
	return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


static func dict_to_rect2i(d: Dictionary) -> Rect2i:
	return Rect2i(int(d["x"]), int(d["y"]), int(d["w"]), int(d["h"]))

#endregion


# ═════════════════════════════════════════════════════════════════
#region Public API
# ═════════════════════════════════════════════════════════════════

func save_game() -> bool:
	var data = {}
	data["game_data"] = _serialize_game_data()
	data["entities"] = _serialize_entities()
	data["director2"] = _serialize_director2()

	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Failed to open save file — %s" % FileAccess.get_open_error())
		NotificationManager.notify("UPLINK FAILURE — DISK ACCESS DENIED", NotificationManager.Type.ERROR, "SAVE ERROR")
		return false
	file.store_string(json)
	file.close()
	print("SaveManager: Game saved to %s" % SAVE_PATH)
	return true


func load_game() -> void:
	if not has_save():
		NotificationManager.notify("No archive found.", NotificationManager.Type.WARNING, "NO SAVE")
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: Failed to open save file for reading")
		NotificationManager.notify("UPLINK FAILURE — DISK ACCESS DENIED", NotificationManager.Type.ERROR, "LOAD ERROR")
		return

	var raw = file.get_as_text()
	file.close()

	var data = JSON.parse_string(raw)
	if data == null:
		push_error("SaveManager: Failed to parse save JSON")
		NotificationManager.notify("ARCHIVE CORRUPT — LOAD FAILED", NotificationManager.Type.ERROR, "LOAD ERROR")
		return

	# Store data for after scene reload
	_pending_save_data = data
	is_loading = true

	# Reset and apply game data BEFORE scene transition
	GameData.reset_to_defaults()
	_deserialize_game_data(data["game_data"])

	# Transition to main scene
	SceneTransition.transition_to("res://Scenes/main.tscn", SceneTransition.Type.ARMOUR)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
		print("SaveManager: Save file deleted")

#endregion


# ═════════════════════════════════════════════════════════════════
#region Restore (called by Director2._ready when is_loading)
# ═════════════════════════════════════════════════════════════════

func restore_game(director: Node2D) -> void:
	if _pending_save_data.is_empty():
		is_loading = false
		return

	var entities_node = director.get_node("../Entities")
	var road_builder = director.get_node("../RoadBuilder")

	_restore_entities(_pending_save_data.get("entities", {}), entities_node, road_builder)
	_restore_director2(_pending_save_data.get("director2", {}), director)
	_rebuild_astar()
	_rebuild_influence()

	_pending_save_data = {}
	is_loading = false

	SignalBus.map_changed.emit()
	ResourceManager.resources_updated.emit(
		GameData.current_pipe_count,
		GameData.total_data,
		GameData.data_reserve_for_auto_repairs
	)
	NotificationManager.notify("Mission state restored.", NotificationManager.Type.INFO, "SAVE LOADED")

#endregion


# ═════════════════════════════════════════════════════════════════
#region GameData Serialization
# ═════════════════════════════════════════════════════════════════

func _serialize_game_data() -> Dictionary:
	return {
		"current_stage": GameData.current_stage,
		"current_map_size": rect2i_to_dict(GameData.current_map_size),
		"current_hub_count": GameData.current_hub_count,
		"current_vent_count": GameData.current_vent_count,
		"current_pipe_count": GameData.current_pipe_count,
		"current_hub_spawn_cost": GameData.current_hub_spawn_cost,
		"current_vent_spawn_cost": GameData.current_vent_spawn_cost,
		"current_pipe_upgrade_level": GameData.current_pipe_upgrade_level,
		"current_hull_shield_level": GameData.current_hull_shield_level,
		"hull_schield_integrity": GameData.hull_schield_integrity,
		"current_pressure": GameData.current_pressure,
		"current_pressure_phase": GameData.current_pressure_phase,
		"fracture_wave_active": GameData.fracture_wave_active,
		"wave_warning_enabled": GameData.wave_warning_enabled,
		"global_vent_interval_multiplier": GameData.global_vent_interval_multiplier,
		"rocket_fracture_reduction": GameData.rocket_fracture_reduction,
		"hub_rate_window": GameData.hub_rate_window,
		"pressure_rate_multiplier": GameData.pressure_rate_multiplier,
		"total_data": GameData.total_data,
		"lifetime_data_earned": GameData.lifetime_data_earned,
		"previous_threshold": GameData.previous_threshold,
		"score_to_next_reward": GameData.score_to_next_reward,
		"current_rocket_phase": GameData.current_rocket_phase,
		"rocket_cell": vec2i_to_key(GameData.rocket_cell),
		"auto_repair_enabled": GameData.auto_repair_enabled,
		"data_reserve_for_auto_repairs": GameData.data_reserve_for_auto_repairs,
		"current_reinforced_zone": GameData.current_reinforced_zone,
		"reinforcement_version": GameData.reinforcement_version,
	}


func _deserialize_game_data(data: Dictionary) -> void:
	GameData.current_stage = int(data["current_stage"])
	GameData.current_map_size = dict_to_rect2i(data["current_map_size"])
	GameData.current_hub_count = int(data["current_hub_count"])
	GameData.current_vent_count = int(data["current_vent_count"])
	GameData.current_pipe_count = int(data["current_pipe_count"])
	GameData.current_hub_spawn_cost = int(data["current_hub_spawn_cost"])
	GameData.current_vent_spawn_cost = int(data["current_vent_spawn_cost"])
	GameData.current_pipe_upgrade_level = int(data["current_pipe_upgrade_level"])
	GameData.current_hull_shield_level = int(data["current_hull_shield_level"])
	GameData.hull_schield_integrity = float(data["hull_schield_integrity"])
	GameData.current_pressure = float(data["current_pressure"])
	GameData.current_pressure_phase = int(data["current_pressure_phase"])
	GameData.fracture_wave_active = bool(data["fracture_wave_active"])
	GameData.wave_warning_enabled = bool(data["wave_warning_enabled"])
	GameData.global_vent_interval_multiplier = float(data["global_vent_interval_multiplier"])
	GameData.rocket_fracture_reduction = float(data["rocket_fracture_reduction"])
	GameData.hub_rate_window = float(data["hub_rate_window"])
	GameData.pressure_rate_multiplier = float(data["pressure_rate_multiplier"])
	GameData.total_data = int(data["total_data"])
	GameData.lifetime_data_earned = int(data["lifetime_data_earned"])
	GameData.previous_threshold = int(data["previous_threshold"])
	GameData.score_to_next_reward = int(data["score_to_next_reward"])
	GameData.current_rocket_phase = int(data["current_rocket_phase"])
	GameData.rocket_cell = key_to_vec2i(data["rocket_cell"])
	GameData.auto_repair_enabled = bool(data["auto_repair_enabled"])
	GameData.data_reserve_for_auto_repairs = int(data["data_reserve_for_auto_repairs"])
	GameData.current_reinforced_zone = int(data["current_reinforced_zone"])
	GameData.reinforcement_version = int(data["reinforcement_version"])

#endregion


# ═════════════════════════════════════════════════════════════════
#region Entity Serialization
# ═════════════════════════════════════════════════════════════════

func _serialize_entities() -> Dictionary:
	var result = {
		"rocket": null,
		"hubs": [],
		"vents": [],
		"pipes": []
	}

	# Deduplicate buildings (multiple cells → same node)
	var seen_buildings = {}
	for cell in GameData.building_grid:
		var building = GameData.building_grid[cell]
		if not is_instance_valid(building):
			continue
		var bid = building.get_instance_id()
		if seen_buildings.has(bid):
			continue
		seen_buildings[bid] = true

		if building is Rocket:
			result["rocket"] = {
				"position": vec2_to_array(building.position),
				"entrance_cell": vec2i_to_key(building.entrance_cell),
			}
		elif building is Hub:
			result["hubs"].append({
				"position": vec2_to_array(building.position),
				"rotation": building.rotation,
				"entrance_cell": vec2i_to_key(building.entrance_cell),
				"upgrade_level": building.upgrade_level,
				"is_fractured": building.is_fractured,
				"oxygen_backlog": building.oxygen_backlog,
				"packets_this_window": building.packets_this_window,
				"window_timer": building.window_timer,
				"is_rate_limited": building.is_rate_limited,
			})
		elif building is Vent:
			result["vents"].append({
				"position": vec2_to_array(building.position),
				"rotation": building.rotation,
				"entrance_cell": vec2i_to_key(building.entrance_cell),
				"send_interval": building.send_interval,
				"driveway_marker_rotation": building.driveway_marker.rotation_degrees,
				"is_bursting": building._is_bursting,
				"burst_timer": building._burst_timer,
			})

	# Serialize pipes
	var seen_pipes = {}
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if not pipe is NewRoadTile:
			continue
		if not is_instance_valid(pipe):
			continue
		var pid = pipe.get_instance_id()
		if seen_pipes.has(pid):
			continue
		seen_pipes[pid] = true

		var connections = []
		for dir in pipe.manual_connections:
			connections.append(vec2i_to_key(dir))

		result["pipes"].append({
			"cell": vec2i_to_key(pipe.cell),
			"connections": connections,
			"is_fractured": pipe.is_fractured,
			"is_reinforced": pipe.is_reinforced,
			"is_permanent": pipe.is_permanent,
			"is_entrance": pipe.is_entrance,
			"owner_id": pipe.owner_id,
		})

	return result

#endregion


# ═════════════════════════════════════════════════════════════════
#region Entity Restoration
# ═════════════════════════════════════════════════════════════════

func _restore_entities(data: Dictionary, entities_node: Node, road_builder: Node) -> void:
	# 1. Restore rocket
	if data.has("rocket") and data["rocket"] != null:
		var rd = data["rocket"]
		var rocket = _rocket_scene.instantiate()
		if rocket:
			entities_node.add_child(rocket)
			rocket.position = array_to_vec2(rd["position"])
			rocket.register_building(rocket)
		else:
			push_warning("SaveManager: Failed to instantiate rocket scene")

	# 2. Restore hubs
	for hd in data.get("hubs", []):
		var hub = _hub_scene.instantiate()
		if not hub:
			push_warning("SaveManager: Failed to instantiate hub scene, skipping")
			continue
		entities_node.add_child(hub)
		hub.position = array_to_vec2(hd["position"])
		hub.rotation = float(hd["rotation"])
		hub.register_building(hub)

		# Restore per-instance state
		hub.upgrade_level = int(hd["upgrade_level"])
		hub.oxygen_backlog = int(hd["oxygen_backlog"])
		hub.packets_this_window = int(hd["packets_this_window"])
		hub.window_timer = float(hd["window_timer"])
		hub.is_rate_limited = bool(hd["is_rate_limited"])

		# Restore fractured state + visuals
		if bool(hd["is_fractured"]):
			hub.is_fractured = true
			hub.smoke_particle_effect1.emitting = false
			hub.smoke_particle_effect2.emitting = false
			hub.modulate = Color("1a0a1f")
			hub._start_dead_pulse()

	# 3. Restore vents
	for vd in data.get("vents", []):
		var vent = _vent_scene.instantiate()
		if not vent:
			push_warning("SaveManager: Failed to instantiate vent scene, skipping")
			continue
		entities_node.add_child(vent)
		vent.position = array_to_vec2(vd["position"])
		vent.rotation = float(vd["rotation"])

		# driveway_marker is @onready — available after add_child triggers _ready (before await)
		vent.driveway_marker.rotation_degrees = float(vd["driveway_marker_rotation"])

		vent.register_building(vent)

		# Restore per-instance state
		vent.send_interval = float(vd["send_interval"])
		vent._is_bursting = bool(vd["is_bursting"])
		vent._burst_timer = float(vd["burst_timer"])
		# Reset capacity since in-flight packets are discarded
		vent.current_capacity = 0

	# 4. Restore pipes
	for pd in data.get("pipes", []):
		var cell = key_to_vec2i(pd["cell"])
		var pipe = _road_tile_scene.instantiate()
		if not pipe:
			push_warning("SaveManager: Failed to instantiate road tile at %s, skipping" % pd["cell"])
			continue
		pipe.position = GameData.get_cell_center(cell)
		pipe.set_cell(cell)
		pipe.is_permanent = bool(pd["is_permanent"])
		pipe.is_entrance = bool(pd.get("is_entrance", false))
		pipe.owner_id = int(pd["owner_id"])
		pipe.is_reinforced = bool(pd["is_reinforced"])

		road_builder.add_child(pipe)

		# Add visual connection arms
		for conn_key in pd["connections"]:
			var dir = key_to_vec2i(conn_key)
			pipe.add_connection(dir)

		GameData.road_grid[cell] = pipe

		# Fractured state + visuals
		if bool(pd["is_fractured"]):
			pipe.is_fractured = true
			pipe.modulate = Color("4a0e1f")
			for arm in pipe.arm_lines.values():
				for ring in arm["connectors"]:
					ring.default_color = Color("2d0a12")
			GameData.fractured_pipes[cell] = pipe

		# Reinforced visuals
		if pipe.is_reinforced and not pipe.is_fractured:
			pipe.modulate = Color(0.4, 0.9, 1.0, 1.0)

#endregion


# ═════════════════════════════════════════════════════════════════
#region Director2 Serialization
# ═════════════════════════════════════════════════════════════════

func _serialize_director2() -> Dictionary:
	var director = _get_director()
	if director == null:
		return {}

	var zones = []
	for z in director.unlocked_zones:
		zones.append(int(z))

	var clusters = []
	for c in director.vent_clusters:
		clusters.append({
			"center": vec2i_to_key(c["center"]),
			"count": c["count"]
		})

	return {
		"unlocked_zones": zones,
		"vent_clusters": clusters,
	}


func _restore_director2(data: Dictionary, director: Node2D) -> void:
	if data.is_empty():
		return

	# Restore unlocked zones
	director.unlocked_zones.clear()
	for z in data.get("unlocked_zones", [0]):
		director.unlocked_zones.append(z as GameData.Zone)

	# Restore vent clusters
	director.vent_clusters.clear()
	for c in data.get("vent_clusters", []):
		director.vent_clusters.append({
			"center": key_to_vec2i(c["center"]),
			"count": int(c["count"])
		})


func _get_director() -> Node2D:
	var tree = get_tree()
	if tree == null:
		return null
	var main = tree.root.get_node_or_null("Main")
	if main == null:
		return null
	return main.get_node_or_null("Director")

#endregion


# ═════════════════════════════════════════════════════════════════
#region Post-Load Rebuilds
# ═════════════════════════════════════════════════════════════════

func _rebuild_astar() -> void:
	GameData.astar = AStar2D.new()

	# Add navigation points for all building entrances
	var seen = {}
	for cell in GameData.building_grid:
		var building = GameData.building_grid[cell]
		if not is_instance_valid(building):
			continue
		var bid = building.get_instance_id()
		if seen.has(bid):
			continue
		seen[bid] = true
		GameData.add_navigation_point(building.entrance_cell)

	# Add navigation points for all road tiles
	for cell in GameData.road_grid:
		GameData.add_navigation_point(cell)

	# Connect adjacent road tiles based on manual_connections
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if not pipe is NewRoadTile:
			continue
		for dir in pipe.manual_connections:
			var neighbor_cell = cell + dir
			var id_a = GameData.get_cell_id(cell)
			var id_b = GameData.get_cell_id(neighbor_cell)
			if GameData.astar.has_point(id_a) and GameData.astar.has_point(id_b):
				if not GameData.astar.are_points_connected(id_a, id_b):
					GameData.astar.connect_points(id_a, id_b)

	# Disable fractured pipe points in A*
	for cell in GameData.fractured_pipes:
		var cell_hash = GameData.get_cell_id(cell)
		if GameData.astar.has_point(cell_hash):
			GameData.astar.set_point_disabled(cell_hash, true)


func _rebuild_influence() -> void:
	GameData.influence_grid.clear()

	# Rocket influence
	GameData.apply_influence(GameData.rocket_cell, "rocket")

	# Building influence
	var seen = {}
	for cell in GameData.building_grid:
		var building = GameData.building_grid[cell]
		if not is_instance_valid(building):
			continue
		var bid = building.get_instance_id()
		if seen.has(bid):
			continue
		seen[bid] = true
		if building is Hub:
			var tile = Vector2i(
				floor(building.position.x / GameData.CELL_SIZE.x),
				floor(building.position.y / GameData.CELL_SIZE.y)
			)
			var center = tile + Vector2i(1, 1)
			GameData.apply_influence(center, "hub")

	# Road influence
	for cell in GameData.road_grid:
		GameData.apply_influence(cell, "road")

#endregion
