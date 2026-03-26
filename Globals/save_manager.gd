extends Node

const SAVE_PATH = "user://savegame.save"

var is_loading: bool = false
var _pending_save_data: Dictionary = {}

# ═════════════════════════════════════════════════════════════════
#region Vector2i / Rect2i Helpers
# ═════════════════════════════════════════════════════════════════

func vec2i_to_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


func key_to_vec2i(s: String) -> Vector2i:
	var parts = s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func vec2_to_array(v: Vector2) -> Array:
	return [v.x, v.y]


func array_to_vec2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func rect2i_to_dict(r: Rect2i) -> Dictionary:
	return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


func dict_to_rect2i(d: Dictionary) -> Rect2i:
	return Rect2i(int(d["x"]), int(d["y"]), int(d["w"]), int(d["h"]))

#endregion


# ═════════════════════════════════════════════════════════════════
#region Public API
# ═════════════════════════════════════════════════════════════════

func save_game() -> bool:
	var data = {}
	data["game_data"] = GameData.serialize()
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
	GameData.deserialize(data["game_data"])

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
	GameData.rebuild_astar()
	GameData.rebuild_influence()

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
			result["hubs"].append(building.get_save_data())
		elif building is Vent:
			result["vents"].append(building.get_save_data())

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

		result["pipes"].append(pipe.get_save_data())

	return result

#endregion


# ═════════════════════════════════════════════════════════════════
#region Entity Restoration
# ═════════════════════════════════════════════════════════════════

func _restore_entities(data: Dictionary, entities_node: Node, road_builder: Node) -> void:
	# 1. Restore rocket
	if data.has("rocket") and data["rocket"] != null:
		var rd = data["rocket"]
		var rocket = EntityFactory.create_rocket(entities_node)
		if rocket:
			rocket.position = array_to_vec2(rd["position"])
			rocket.register_building(rocket)

	# 2. Restore hubs
	for hd in data.get("hubs", []):
		var hub = EntityFactory.create_hub(entities_node)
		if not hub:
			continue
		hub.position = array_to_vec2(hd["position"])
		hub.rotation = float(hd["rotation"])
		hub.register_building(hub)
		hub.restore_from_data(hd)

	# 3. Restore vents
	for vd in data.get("vents", []):
		var vent = EntityFactory.create_vent(entities_node)
		if not vent:
			continue
		vent.position = array_to_vec2(vd["position"])
		vent.rotation = float(vd["rotation"])
		vent.register_building(vent)
		vent.restore_from_data(vd)

	# 4. Restore pipes
	for pd in data.get("pipes", []):
		var cell = key_to_vec2i(pd["cell"])
		var pipe = EntityFactory.create_pipe(road_builder, cell)
		if not pipe:
			continue
		GameData.road_grid[cell] = pipe
		pipe.restore_from_data(pd)

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


