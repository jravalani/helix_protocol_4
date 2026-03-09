extends Node2D

# ════════════════════════════════════════════════════════════════
#region Scene References
# ════════════════════════════════════════════════════════════════

@onready var rocket_scene:       PackedScene = preload("res://Scenes/rocket.tscn")
@onready var research_hub_scene: PackedScene = preload("res://Scenes/hub3x2.tscn")
@onready var vent_scene:         PackedScene = preload("res://Scenes/vent.tscn")

@onready var camera_2d: Camera2D = $"../Camera2D"
@onready var line_2d:   Line2D   = $Line2D
@onready var entities:  Node     = $"../Entities"

#endregion


# ════════════════════════════════════════════════════════════════
#region Configuration
# ════════════════════════════════════════════════════════════════

const MAX_SPAWN_POS_TRIES: int = 30

var use_dynamic_spawning: bool = true
var intro_cooldown: float = 5.0

## Footprint sizes in grid tiles for each building type.
var hub_size:    Vector2i = Vector2i(3, 2)
var vent_size:   Vector2i = Vector2i(1, 1)
var rocket_size: Vector2i = Vector2i(3, 3)

var hub_rotation: Array = [0, PI/2, 3*PI/2]

#endregion


# ════════════════════════════════════════════════════════════════
#region State
# ════════════════════════════════════════════════════════════════

## Zones available for building placement. Expands with rocket segments.
var unlocked_zones: Array[GameData.Zone] = [GameData.Zone.CORE]

var camera_buffer: int = 1
var screen_center: Vector2

## Pressure tracking — quadratic scaling: BASE_RATE * (1 + ratio²)
var pressure_ratio: float = 0.0
var increment:      float = 0.0

## Hull shield degrades continuously with pressure.
var degradation_rate: float = 0.0

#endregion


# ════════════════════════════════════════════════════════════════
#region Lifecycle
# ════════════════════════════════════════════════════════════════

func _ready() -> void:
	await get_tree().process_frame
	screen_center = camera_2d.get_screen_center_position()
	get_camera_bounds()
	spawn_rocket()
	spawn_initial_colony()
	print("Current Map Size is ", GameData.current_map_size, " from ready function.")
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	SignalBus.spawn_hub_requested.connect(request_hub_spawn)
	SignalBus.spawn_vent_requested.connect(request_vent_spawn)

## Ticks pressure, hull degradation, and phase transitions every frame.
func _process(delta: float) -> void:
	pressure_ratio = GameData.current_pressure / GameData.MAX_PRESSURE
	increment = GameData.BASE_RATE * (1 + (pressure_ratio * pressure_ratio)) * GameData.pressure_rate_multiplier

	GameData.current_pressure += increment * delta
	GameData.current_pressure = min(GameData.MAX_PRESSURE, GameData.current_pressure)

	degradation_rate = 0.05 * (GameData.current_pressure / 100)
	GameData.hull_schield_integrity -= degradation_rate * delta
	GameData.hull_schield_integrity = max(0, GameData.hull_schield_integrity)

	var target_phase = clamp(int(GameData.current_pressure / 10), 0, 10)
	if target_phase > GameData.current_pressure_phase:
		transition_to_phase(target_phase)

	if GameData.current_pressure >= 100:
		print("Meltdown Triggered!")
		SignalBus.game_over.emit()

#endregion


# ════════════════════════════════════════════════════════════════
#region Rocket Segments
# ════════════════════════════════════════════════════════════════

## Handles zone unlocks and passive effects when a rocket segment is purchased.
func _on_rocket_segment_purchased(phase: int) -> void:
	print("Director received rocket_segment_purchased: ", phase)
	match phase:
		1: unlock_zone(GameData.Zone.INNER)
		2: unlock_zone(GameData.Zone.OUTER)
		3: unlock_zone(GameData.Zone.FRONTIER)
	apply_segment_effects(phase)

## Reads the ROCKET_UPGRADES dictionary and applies all passive effects for the given phase.
func apply_segment_effects(phase: int) -> void:
	var data = GameData.ROCKET_UPGRADES.get(phase, {})

	if data.has("shield_boost"):
		GameData.current_hull_shield_level += data["shield_boost"]
		print("Hull shield boosted to level ", GameData.current_hull_shield_level)

	if data.has("vent_interval_multiplier"):
		GameData.global_vent_interval_multiplier *= data["vent_interval_multiplier"]
		SignalBus.vent_interval_updated.emit()
		print("Vent interval multiplier now: ", GameData.global_vent_interval_multiplier)

	if data.has("fracture_chance_reduction"):
		GameData.rocket_fracture_reduction += data["fracture_chance_reduction"]
		print("Rocket fracture reduction now: ", GameData.rocket_fracture_reduction)

	if data.has("rate_window_reduction"):
		GameData.hub_rate_window = max(20.0, GameData.hub_rate_window - data["rate_window_reduction"])
		print("Hub rate window now: ", GameData.hub_rate_window)

	if data.has("pressure_rate_reduction"):
		GameData.pressure_rate_multiplier *= (1.0 - data["pressure_rate_reduction"])
		print("Pressure rate multiplier now: ", GameData.pressure_rate_multiplier)

#endregion


# ════════════════════════════════════════════════════════════════
#region Camera & Bounds
# ════════════════════════════════════════════════════════════════

## Returns the playable tile bounds derived from the current map size.
## Applies 1 cell padding on sides and 3 cells vertical padding to avoid UI overlap.
func get_camera_bounds() -> Rect2i:
	var bounds = GameData.current_map_size
	return Rect2i(
		bounds.position.x,
		bounds.position.y + 1,
		bounds.size.x,
		bounds.size.y - 3
	)

#endregion


# ════════════════════════════════════════════════════════════════
#region Zone Management
# ════════════════════════════════════════════════════════════════

## Unlocks a zone, expands the map, and emits the zone_unlocked signal.
func unlock_zone(zone: GameData.Zone) -> void:
	if zone not in unlocked_zones:
		unlocked_zones.append(zone)
		GameData.increase_map_size()
		print("Map size after increase: ", GameData.current_map_size)
		SignalBus.zone_unlocked.emit(zone)

## Returns true if the given tile falls within any currently unlocked zone.
func _is_tile_in_unlocked_zone(tile: Vector2i) -> bool:
	return GameData.get_zone_for_cell(tile) in unlocked_zones

#endregion


# ════════════════════════════════════════════════════════════════
#region Spawn Utilities
# ════════════════════════════════════════════════════════════════

## Returns true if all tiles in the area_size footprint at target_coord are
## clear of buildings, roads, map bounds, and locked zones.
## Buffer expands the checked area outward on all sides.
func is_area_clear(target_coord: Vector2i, area_size: Vector2i, camera_bounds: Rect2i, buffer: int = 0) -> bool:
	for x in range(-buffer, area_size.x + buffer):
		for y in range(-buffer, area_size.y + buffer):
			var current_tile = target_coord + Vector2i(x, y)
			if not camera_bounds.has_point(current_tile):
				return false
			if not _is_tile_in_unlocked_zone(current_tile):
				return false
			if GameData.building_grid.has(current_tile) or GameData.road_grid.has(current_tile):
				return false
	return true

## Scans a square ring pattern from min_dist to max_dist tiles from center,
## returning all clear tiles of the given size. Stops early at 15 candidates.
func calculate_candidate_tiles(center: Vector2, min_dist: int, max_dist: int, size: Vector2i, buffer: int) -> Array:
	var candidates = []
	var center_tile = Vector2i(center / GameData.CELL_SIZE.x)
	var camera_bounds = get_camera_bounds()

	for r in range(min_dist, max_dist):
		var top    = center_tile.y - r
		var bottom = center_tile.y + r
		var left   = center_tile.x - r
		var right  = center_tile.x + r

		for x in range(left, right + 1):
			if is_area_clear(Vector2i(x, top),    size, camera_bounds, buffer): candidates.append(Vector2i(x, top))
			if is_area_clear(Vector2i(x, bottom), size, camera_bounds, buffer): candidates.append(Vector2i(x, bottom))
		for y in range(top, bottom):
			if is_area_clear(Vector2i(left,  y), size, camera_bounds, buffer): candidates.append(Vector2i(left,  y))
			if is_area_clear(Vector2i(right, y), size, camera_bounds, buffer): candidates.append(Vector2i(right, y))

		if candidates.size() >= 15:
			break

	return candidates

## Scores a tile based on influence grid value, distance from rocket center,
## and a small random jitter to avoid deterministic clustering.
func score_tile(tile: Vector2i) -> float:
	var base_score = GameData.influence_grid.get(tile, 0.0)
	var map_half = Vector2(GameData.current_map_size.size) / 2.0
	var max_dist = min(map_half.x, map_half.y)
	var dist_from_center = Vector2(tile).distance_to(Vector2(GameData.rocket_cell))
	var edge_bonus = (dist_from_center / max(max_dist, 1.0)) * 60.0
	return base_score + edge_bonus + randf_range(0.001, 0.050)

#endregion


# ════════════════════════════════════════════════════════════════
#region Initial Colony
# ════════════════════════════════════════════════════════════════

## Spawns the rocket at the world center tile.
func spawn_rocket() -> void:
	var rocket = rocket_scene.instantiate()
	var center_tile = Vector2i(
		floor(screen_center.x / GameData.CELL_SIZE.x),
		floor(screen_center.y / GameData.CELL_SIZE.y)
	)
	entities.add_child(rocket)
	rocket.global_position = Vector2(center_tile) * GameData.CELL_SIZE.x - Vector2(64, 64)
	rocket.register_building(rocket)
	GameData.apply_influence(center_tile, "rocket")

## Spawns the starting hub and vent to kick off the first run.
## Hub placed via scoring system; vent placed near the hub.
func spawn_initial_colony() -> void:
	var scored_tiles = []
	var candidate_tiles = calculate_candidate_tiles(screen_center, 3, 12, hub_size, 1)
	print("Initial hub candidates found: ", candidate_tiles.size())

	for candidate in candidate_tiles:
		var score = score_tile(candidate)
		scored_tiles.append({ "tile": candidate, "score": score })
		if scored_tiles.size() < 3:
			print("Candidate: ", candidate, " Score: ", score)

	if scored_tiles.is_empty():
		print("Cannot spawn initial colony hub - no candidates!")
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile_for_hub = scored_tiles.pick_random().tile
	print("Selected hub tile: ", target_tile_for_hub)

	var research_hub = research_hub_scene.instantiate()
	entities.add_child(research_hub)
	research_hub.position = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
	research_hub.register_building(research_hub)
	GameData.apply_influence(target_tile_for_hub + Vector2i(1, 1), "hub")

	var vent_scored_tiles = []
	var vent_candidates = calculate_candidate_tiles(Vector2(target_tile_for_hub * GameData.CELL_SIZE.x), 6, 12, vent_size, 0)
	print("Initial vent candidates found: ", vent_candidates.size())

	for candidate in vent_candidates:
		vent_scored_tiles.append({ "tile": candidate, "score": score_tile(candidate) })

	if not vent_scored_tiles.is_empty():
		vent_scored_tiles.sort_custom(func(a, b): return a.score > b.score)
		var target_tile_for_vent = vent_scored_tiles.pick_random().tile
		var vent_1 = vent_scene.instantiate()
		entities.add_child(vent_1)
		vent_1.position = Vector2(target_tile_for_vent * GameData.CELL_SIZE.x) + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
		vent_1.register_building(vent_1)
		GameData.apply_influence(target_tile_for_vent, "vent")
		vent_clusters.append({ "center": target_tile_for_vent, "count": 1 })
		print("Spawned initial vent at: ", target_tile_for_vent)
	else:
		print("Cannot spawn initial vent - no candidates!")

#endregion


# ════════════════════════════════════════════════════════════════
#region Hub Spawning
# ════════════════════════════════════════════════════════════════

## Entry point called by ResourceManager when the player buys a hub.
func request_hub_spawn() -> void:
	if GameData.current_hub_count >= GameData.MAX_HUBS:
		print("Director: Hub cap reached.")
		return
	try_hub_spawn()

## Scans all playable tiles, scores them, and spawns a hub at the best candidate.
## Falls back to buffer=0 if no tiles found with buffer=1.
func try_hub_spawn() -> void:
	var camera_bounds = get_camera_bounds()
	var scored_tiles = _collect_hub_candidates(camera_bounds, 1)

	if scored_tiles.is_empty():
		scored_tiles = _collect_hub_candidates(camera_bounds, 0)

	if scored_tiles.is_empty():
		print("Director: No valid hub tiles in current map. Player needs to unlock more zones.")
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	spawn_hub_at(scored_tiles.slice(0, 3).pick_random().tile)

## Collects and scores all clear hub-sized tiles within bounds at the given buffer.
func _collect_hub_candidates(camera_bounds: Rect2i, buffer: int) -> Array:
	var scored_tiles = []
	for x in range(camera_bounds.position.x, camera_bounds.end.x):
		for y in range(camera_bounds.position.y, camera_bounds.end.y):
			var tile = Vector2i(x, y)
			if is_area_clear(tile, hub_size, camera_bounds, buffer):
				scored_tiles.append({ "tile": tile, "score": score_tile(tile) })
	return scored_tiles

## Instantiates a hub at the given tile position and registers it.
func spawn_hub_at(position: Vector2i) -> void:
	var hub = research_hub_scene.instantiate()
	entities.add_child(hub)
	hub.position = position * GameData.CELL_SIZE.x
	hub.register_building(hub)
	GameData.apply_influence(position + Vector2i(1, 1), "hub")

#endregion


# ════════════════════════════════════════════════════════════════
#region Vent Spawning
# ════════════════════════════════════════════════════════════════

const VENT_CLUSTER_MAX:      int = 5
const VENT_SPAWN_RADIUS:     int = 5
const VENT_SPAWN_RADIUS_MAX: int = 10

## Fixed cluster registry — centers are set on creation and never drift.
## Each entry: { "center": Vector2i, "count": int }
var vent_clusters: Array = []

## Returns the minimum distance between cluster centers for a given map stage.
func get_dynamic_cluster_min_dist_for_stage(stage: int) -> int:
	match stage:
		0: return 6
		1: return 7
		2: return 8
		3: return 9
		_: return 6

## Returns the min cluster distance for the current map stage.
func get_dynamic_cluster_min_dist() -> int:
	return get_dynamic_cluster_min_dist_for_stage(GameData.current_stage)

## Returns the first cluster with remaining capacity, or empty dict if all are full.
func find_open_cluster() -> Dictionary:
	for cluster in vent_clusters:
		if cluster["count"] < VENT_CLUSTER_MAX:
			return cluster
	return {}

## Finds a valid new cluster center by scanning the map.
## Falls back through previous stage distances if the current one yields nothing.
## Emits notify_player_expand and returns (-9999,-9999) if no center is possible.
func find_new_cluster_center() -> Vector2i:
	var camera_bounds = get_camera_bounds()

	for stage in range(GameData.current_stage, -1, -1):
		var min_dist = get_dynamic_cluster_min_dist_for_stage(stage)
		var scored_tiles = []

		for x in range(camera_bounds.position.x, camera_bounds.end.x):
			for y in range(camera_bounds.position.y, camera_bounds.end.y):
				var tile = Vector2i(x, y)
				if not is_area_clear(tile, vent_size, camera_bounds, 0):
					continue
				var too_close = false
				for cluster in vent_clusters:
					if tile.distance_to(cluster["center"]) < min_dist:
						too_close = true
						break
				if too_close:
					continue
				scored_tiles.append({ "tile": tile, "score": score_tile(tile) })

		if not scored_tiles.is_empty():
			print("Director: Found cluster center at stage ", stage, " dist ", min_dist)
			scored_tiles.sort_custom(func(a, b): return a.score > b.score)
			return scored_tiles.slice(0, 3).pick_random().tile

	print("Director: Map is full. Player needs to expand.")
	SignalBus.notify_player_expand.emit()
	return Vector2i(-9999, -9999)

## Entry point called by ResourceManager when the player buys a vent.
func request_vent_spawn() -> void:
	if GameData.current_vent_count >= GameData.MAX_VENTS:
		print("Director: Vent cap reached.")
		return
	try_vent_spawn()

## Spawns a vent into an open cluster or creates a new cluster if all are full.
## Expands search radius progressively if the cluster center area is densely occupied.
func try_vent_spawn() -> void:
	print("try_vent_spawn called. Clusters: ", vent_clusters.size())
	var camera_bounds = get_camera_bounds()
	var spawn_center: Vector2i

	var open_cluster = find_open_cluster()
	if not open_cluster.is_empty():
		spawn_center = open_cluster["center"]
		print("Director: Spawning vent in cluster at ", spawn_center, " (", open_cluster["count"], "/", VENT_CLUSTER_MAX, ")")
	else:
		spawn_center = find_new_cluster_center()
		if spawn_center == Vector2i(-9999, -9999):
			return
		vent_clusters.append({ "center": spawn_center, "count": 0 })
		print("Director: New cluster registered at ", spawn_center)

	var scored_tiles = []
	var search_radius = VENT_SPAWN_RADIUS

	while scored_tiles.is_empty() and search_radius <= VENT_SPAWN_RADIUS_MAX:
		for x in range(spawn_center.x - search_radius, spawn_center.x + search_radius + 1):
			for y in range(spawn_center.y - search_radius, spawn_center.y + search_radius + 1):
				var tile = Vector2i(x, y)
				if tile.distance_to(spawn_center) > search_radius:
					continue
				if not camera_bounds.has_point(tile):
					continue
				if not is_area_clear(tile, vent_size, camera_bounds, 0):
					continue
				scored_tiles.append({ "tile": tile, "score": score_tile(tile) })
		if scored_tiles.is_empty():
			search_radius += 1
			print("Director: Expanding vent search radius to ", search_radius)

	if scored_tiles.is_empty():
		print("Director: No valid vent tiles near cluster center ", spawn_center)
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile = scored_tiles.slice(0, 3).pick_random().tile

	for cluster in vent_clusters:
		if cluster["center"] == spawn_center:
			cluster["count"] += 1
			break

	spawn_vent_at(target_tile)

## Instantiates a vent at the given tile position and registers it.
func spawn_vent_at(vent_position: Vector2i) -> void:
	var vent = vent_scene.instantiate()
	entities.add_child(vent)
	vent.position = Vector2(vent_position) * GameData.CELL_SIZE.x + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
	vent.register_building(vent)
	GameData.apply_influence(vent_position, "vent")

#endregion


# ════════════════════════════════════════════════════════════════
#region Pressure & Fracture Waves
# ════════════════════════════════════════════════════════════════

## Advances the pressure phase and triggers a fracture wave if phase >= 3.
func transition_to_phase(phase_number: int) -> void:
	if GameData.current_pressure_phase <= GameData.MAX_PRESSURE_PHASE:
		GameData.current_pressure_phase = phase_number
		SignalBus.pressure_phase_changed.emit(phase_number)
	print("----PHASE TRANSITION: ", phase_number, "----")
	if phase_number >= 3:
		trigger_fracture_wave()

## Emits the fracture wave signal, waits for visual travel time, then applies damage.
## Sets fracture_wave_active for the duration so new packets spawn pre-slowed.
func trigger_fracture_wave() -> void:
	GameData.fracture_wave_active = true
	SignalBus.fracture_wave.emit()
	SignalBus.camera_shake.emit(0.4, 6.0)
	await get_tree().create_timer(5.0).timeout
	SignalBus.camera_shake.emit(0.5, 8.0)
	_execute_fracture_wave()
	await get_tree().create_timer(10.0).timeout
	GameData.fracture_wave_active = false

## Applies guaranteed and probabilistic fractures to pipes and hubs.
## Outer/frontier pipes are prioritized. Scale is based on current pressure phase.
func _execute_fracture_wave() -> void:
	var phase                     := GameData.current_pressure_phase
	var guaranteed_pipe_fractures := _get_guaranteed_pipe_fractures(phase)
	var guaranteed_hub_fractures  := _get_guaranteed_hub_fractures(phase)

	var fracturable_pipes: Array = []
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if pipe is NewRoadTile and not pipe.is_fractured and not pipe.is_reinforced:
			fracturable_pipes.append(pipe)

	fracturable_pipes.sort_custom(func(a, b):
		return _zone_priority(a.my_zone) > _zone_priority(b.my_zone)
	)

	for pipe in fracturable_pipes.slice(0, guaranteed_pipe_fractures):
		pipe.fracture()
	for pipe in fracturable_pipes.slice(guaranteed_pipe_fractures):
		pipe.on_check_fracture()

	var fracturable_hubs: Array = []
	for hub in get_tree().get_nodes_in_group("hubs"):
		if not hub.is_fractured:
			fracturable_hubs.append(hub)
	for hub in fracturable_hubs.slice(0, guaranteed_hub_fractures):
		hub.fracture()

## Returns the number of guaranteed pipe fractures for the given pressure phase.
## Capped at 25% of total pipes to protect early game runs.
func _get_guaranteed_pipe_fractures(phase: int) -> int:
	var raw_count: int
	match phase:
		3:  raw_count = 2
		4:  raw_count = 3
		5:  raw_count = 4
		6:  raw_count = 5
		7:  raw_count = 9
		8:  raw_count = 11
		9:  raw_count = 15
		10: raw_count = 20
		_:  raw_count = 0
	return min(raw_count, max(1, int(GameData.road_grid.size() * 0.25)))

## Returns the number of guaranteed hub fractures for the given pressure phase.
func _get_guaranteed_hub_fractures(phase: int) -> int:
	match phase:
		3:  return 1
		4:  return 2
		5:  return 2
		6:  return 2
		7:  return 3
		8:  return 3
		9:  return 4
		10: return 5
		_:  return 0

## Returns fracture priority for a zone — frontier fractures first, core last.
func _zone_priority(zone: GameData.Zone) -> int:
	match zone:
		GameData.Zone.FRONTIER: return 4
		GameData.Zone.OUTER:    return 3
		GameData.Zone.INNER:    return 2
		GameData.Zone.CORE:     return 1
		_:                      return 0

#endregion
