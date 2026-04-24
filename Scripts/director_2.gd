extends Node2D

## =============================================================================
## SCENE PRELOADS
## =============================================================================

@onready var rocket_scene: PackedScene = preload("res://Scenes/rocket.tscn")
@onready var research_hub_scene: PackedScene = preload("res://Scenes/hub3x2.tscn")
@onready var vent_scene: PackedScene = preload("res://Scenes/vent.tscn")

const SpecialTileScene := preload("res://Scenes/special_tile.tscn")

## =============================================================================
## NODE REFERENCES
## =============================================================================

@onready var camera_2d: Camera2D = $"../Camera2D"
@onready var line_2d: Line2D = $Line2D
@onready var entities: Node = $"../Entities"

## =============================================================================
## SPAWN SYSTEM CONFIGURATION
## =============================================================================

const MAX_SPAWN_POS_TRIES: int = 30

var use_dynamic_spawning: bool = true
var intro_cooldown: float = 3.0

## =============================================================================
## BUILDING SIZE DEFINITIONS
## =============================================================================

var hub_size: Vector2i = Vector2i(3, 2)
var vent_size: Vector2i = Vector2i(1, 1)
var rocket_size: Vector2i = Vector2i(3, 3)

## Hub rotation options (in radians)
var hub_rotation: Array = [0, PI/2, 3*PI/2]

## =============================================================================
## ZONE UNLOCK STATE
## =============================================================================
## Core + Inner always unlocked.
## Outer unlocks on Rocket Segment 1.
## Frontier unlocks on Rocket Segment 3.

var unlocked_zones: Array[GameData.Zone] = [GameData.Zone.CORE]

## =============================================================================
## CAMERA & VIEWPORT
## =============================================================================

@onready var camera_buffer: int = 1      # Padding around camera view
var screen_center: Vector2               # Cached center point

## =============================================================================
## PRESSURE SYSTEM
## =============================================================================

## Pressure increment calculation (quadratic scaling for late-game intensity)
## Formula: BASE_RATE * (1 + (pressure_ratio^2))
var pressure_ratio: float = 0.0
var increment: float = 0.0

## Hull shield degradation
var degradation_rate: float = 0.0
var _game_over_triggered: bool = false

# ── Secondary Objectives ───────────────────────────────────────────────────────
# Up to two active objectives simultaneously. Each slot is a Dictionary:
#   { "objective": Objective, "tile": SpecialTile, "packets_needed": int, "pressure_threshold": float }
# Dual spawn probability scales with pressure phase (0% at p1 → 60% at p8+).
# When dual-spawning, one slot is always Positive category, one is Hazard.

enum Objective {
	NONE,
	BOOST_CORRIDOR,    # Keep Boost Corridor alive through the next wave → +150 data
	UNSTABLE_CONDUIT,  # Route 10 packets through Unstable Conduit → -10 pressure
	DEAD_ZONE,         # Clear the Dead Zone within 90s → +100 data
	PRESSURE_SINK,     # Maintain packet flow through Pressure Sink → reduces pressure rate
}

# Tile type → objective category
enum TileCategory { POSITIVE, HAZARD }
const TILE_CATEGORIES: Dictionary = {
	SpecialTile.Type.BOOST_CORRIDOR:   TileCategory.POSITIVE,
	SpecialTile.Type.PRESSURE_SINK:    TileCategory.POSITIVE,
	SpecialTile.Type.UNSTABLE_CONDUIT: TileCategory.HAZARD,
	SpecialTile.Type.DEAD_ZONE:        TileCategory.HAZARD,
}

var active_slots: Array = []           # Array of slot Dictionaries, max size 2
var _objective_packets_needed: int = 10
var _pressure_sink_threshold: float = 0.0

# ── Objective spawn control ────────────────────────────────────────────────────
var _recent_types: Array = []          # last 2 spawned types — no consecutive repeats
var _spawn_attempts: int = 0           # failed spawn attempts in current cycle
const MAX_SPAWN_ATTEMPTS: int = 3      # give up after this many fails in one cycle

# Dual spawn probability curve — linear 0% at phase 1 → 60% at phase 8, capped
func _dual_spawn_chance() -> float:
	var phase: int = GameData.current_pressure_phase
	return clampf(remap(float(phase), 1.0, 8.0, 0.0, 0.60), 0.0, 0.60)

# Legacy single-tile accessors used by fracture wave handler
var active_objective: Objective:
	get: return active_slots[0]["objective"] if active_slots.size() > 0 else Objective.NONE
var active_special_tile: SpecialTile:
	get: return active_slots[0]["tile"] if active_slots.size() > 0 else null


const RING_RADII: Array = [6, 6, 8, 8, 11, 11, 14, 14]

func _ready() -> void:
	add_to_group("director")
	await get_tree().process_frame
	screen_center = camera_2d.get_screen_center_position()
	get_camera_bounds()

	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	SignalBus.spawn_hub_requested.connect(request_hub_spawn)
	SignalBus.spawn_vent_requested.connect(request_vent_spawn)

	if SaveManager.is_loading:
		SaveManager.restore_game(self)
		_game_over_triggered = false
	else:
		GameData.reset_to_defaults()
		spawn_rocket()
		spawn_initial_colony()
		NotificationManager.notify("Colony initialised. Map size: " + str(GameData.current_map_size), NotificationManager.Type.INFO)
	
	await get_tree().create_timer(180.0).timeout
	_spawn_first_special_tile_with_tutorial()

func _spawn_first_special_tile_with_tutorial() -> void:
	# Slow the game down so the player can read the tutorial
	Engine.time_scale = 0.1

	# Notify the player about special tiles
	NotificationManager.notify(
		"A Special Tile has appeared on the map!\n" +
		"Special Tiles are bonus objectives that may reward you for routing packets through them.",
		NotificationManager.Type.OBJECTIVE,
		"SPECIAL TILE",
		40.0
	)

	# Spawn the tile
	_spawn_random_objective()

	# Restore time scale after a short real-time pause (10s real = 1s game at 0.1x)
	await get_tree().create_timer(2.0).timeout
	Engine.time_scale = 1.0
	var top_panel = get_tree().get_root().find_child("TopPanel", true, false)
	if top_panel and top_panel.has_method("sync_speed_button_state"):
		top_panel.sync_speed_button_state()

func _on_rocket_segment_purchased(phase: int) -> void:

	match phase:
		1: unlock_zone(GameData.Zone.INNER)
		2: unlock_zone(GameData.Zone.OUTER)
		3: unlock_zone(GameData.Zone.FRONTIER)
	apply_segment_effects(phase)

func apply_segment_effects(phase: int) -> void:
	var data = GameData.ROCKET_UPGRADES.get(phase, {})

	# Shield boost
	if data.has("shield_boost"):
		GameData.current_hull_shield_level += data["shield_boost"]
		NotificationManager.notify("Hull shield boosted to level " + str(GameData.current_hull_shield_level), NotificationManager.Type.INFO, "SHIELD UPGRADE")

	# Vent interval multiplier — stacks across segments
	if data.has("vent_interval_multiplier"):
		GameData.global_vent_interval_multiplier *= data["vent_interval_multiplier"]
		SignalBus.vent_interval_updated.emit()
		NotificationManager.notify("Vent spin rate increased.", NotificationManager.Type.INFO, "VENT UPGRADE")

	# Fracture chance reduction
	if data.has("fracture_chance_reduction"):
		GameData.rocket_fracture_reduction += data["fracture_chance_reduction"]
		NotificationManager.notify("Pipe fracture resistance improved.", NotificationManager.Type.INFO, "CONDUIT UPGRADE")

	# Hub rate window reduction
	if data.has("rate_window_reduction"):
		GameData.hub_rate_window -= data["rate_window_reduction"]
		GameData.hub_rate_window = max(20.0, GameData.hub_rate_window)
		NotificationManager.notify("Hub processing speed increased.", NotificationManager.Type.INFO, "HUB UPGRADE")

	# Pressure rate reduction
	if data.has("pressure_rate_reduction"):
		GameData.pressure_rate_multiplier *= (1.0 - data["pressure_rate_reduction"])
		NotificationManager.notify("Planetary pressure rate reduced.", NotificationManager.Type.INFO, "PRESSURE REGULATOR")
	
	if data.has("enables_wave_warning"):
		GameData.wave_warning_enabled = true
		NotificationManager.notify("Fracture wave early warning system online.", NotificationManager.Type.INFO, "WARNING SYSTEM")

func _process(delta: float) -> void:
	# Pressure system
	pressure_ratio = GameData.current_pressure / GameData.MAX_PRESSURE
	increment = GameData.BASE_RATE * (1 + (pressure_ratio * pressure_ratio)) * GameData.pressure_rate_multiplier
	
	GameData.current_pressure += increment * delta
	GameData.current_pressure = min(GameData.MAX_PRESSURE, GameData.current_pressure)
	
	# Hull shield degrades with pressure
	degradation_rate = 0.05 * (GameData.current_pressure / 100)
	GameData.hull_schield_integrity -= degradation_rate * delta
	GameData.hull_schield_integrity = max(0, GameData.hull_schield_integrity)
	
	var target_phase = int(GameData.current_pressure / 10)
	target_phase = clamp(target_phase, 0, 10)
	
	if target_phase > GameData.current_pressure_phase:
		transition_to_phase(target_phase)
	
	if GameData.current_pressure >= 100 and not GameData.fracture_wave_active:
		if not _game_over_triggered:
			_game_over_triggered = true
			NotificationManager.notify("Core meltdown imminent. Systems critical.", NotificationManager.Type.ERROR, "MELTDOWN")
			SignalBus.game_over.emit()
			WinSceneData.capture("PRESSURE OVERLOAD")
			await get_tree().create_timer(2.0).timeout
			SceneTransition.transition_to("res://Scenes/LoseScene.tscn", SceneTransition.Type.BEAM)

	_tick_objective_system(delta)

#region Camera
func get_camera_bounds() -> Rect2i:
	return GameData.get_playable_rect()
#endregion

#region Rocket
# Spawn rocket at the dead center of the screen
func spawn_rocket() -> void:
	var rocket = rocket_scene.instantiate()
	var center_tile = Vector2i(
		floor(screen_center.x / GameData.CELL_SIZE.x),
		floor(screen_center.y / GameData.CELL_SIZE.y)
	)
	
	## offset the rocket so that its actual center is at the center
	#var rocket_offset = center_tile - Vector2i(2, 2)
	entities.add_child(rocket)
	rocket.global_position = Vector2(center_tile) * GameData.CELL_SIZE.x - Vector2(64, 64)
	rocket.register_building(rocket)
	GameData.apply_influence(center_tile, "rocket")
#endregion

#region Functions

#region Public API — called by ResourceManager

func request_hub_spawn() -> void:
	if GameData.current_hub_count >= GameData.MAX_HUBS:
		NotificationManager.notify("Maximum hub capacity reached.", NotificationManager.Type.WARNING, "HUB CAP")
		return
	try_hub_spawn()

func request_vent_spawn() -> void:
	if GameData.current_vent_count >= GameData.MAX_VENTS:
		NotificationManager.notify("Maximum vent capacity reached.", NotificationManager.Type.WARNING, "VENT CAP")
		return
	try_vent_spawn()

func unlock_zone(zone: GameData.Zone) -> void:
	if zone not in unlocked_zones:
		unlocked_zones.append(zone)
		GameData.increase_map_size()
		NotificationManager.notify("Territory expanded. New sectors unlocked.", NotificationManager.Type.INFO, "MAP EXPANDED")
		SignalBus.zone_unlocked.emit(zone)

#endregion

func _is_tile_in_unlocked_zone(tile: Vector2i) -> bool:
	return GameData.get_zone_for_cell(tile) in unlocked_zones

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

	# Always enforce 1 tile gap at bottom for entrance access
	for x in range(0, area_size.x):
		var bottom_tile = target_coord + Vector2i(x, area_size.y)
		if not camera_bounds.has_point(bottom_tile):
			return false
		if GameData.building_grid.has(bottom_tile) or GameData.road_grid.has(bottom_tile):
			return false

	return true

func calculate_candidate_tiles(center: Vector2, min_dist: int, max_dist: int, size: Vector2i, buffer: int) -> Array:
	var candidates = []
	var center_tile = Vector2i(center / GameData.CELL_SIZE.x)
	var camera_bounds = get_camera_bounds()
	
	# check all tiles from min dist to max dist in a square
	for r in range(min_dist, max_dist):
		# calculate the 4 walls of the sqaure 
		var top_wall = center_tile.y - r
		var bottom_wall = center_tile.y + r
		var left_wall = center_tile.x - r
		var right_wall = center_tile.x + r
		
		# loop through the walls
		# top wall
		for x in range(left_wall, right_wall + 1):
			var t = Vector2i(x, top_wall)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		# bottom wall
		for x in range(left_wall, right_wall + 1):
			var t = Vector2i(x, bottom_wall)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		# left wall
		for y in range(top_wall, bottom_wall):
			var t = Vector2i(left_wall, y)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		# right wall
		for y in range(top_wall, bottom_wall):
			var t = Vector2i(right_wall, y)
			if is_area_clear(t, size, camera_bounds, buffer):
				candidates.append(t)
		
		if candidates.size() >= 15:
			break
	
	return candidates

## Ideal ring radius per cluster pair. Each pair of values covers 2 clusters per stage.
## Stage 0: radius 4, Stage 1: radius 7, Stage 2: radius 11, Stage 3: radius 14.
## Easy to tweak for playtesting — just change the values in this array.


func get_ideal_ring_radius() -> float:
	var index = min(vent_clusters.size(), RING_RADII.size() - 1)
	return float(RING_RADII[index])

func score_tile(tile: Vector2i) -> float:
	var base_score = GameData.influence_grid.get(tile, 0.0)

	# Ring bonus: score tiles by how close they are to the ideal ring radius.
	# Tiles at the ideal radius score full ring_weight; drops off within tolerance.
	var dist_from_center = Vector2(tile).distance_to(Vector2(GameData.rocket_cell))
	var ideal_radius = get_ideal_ring_radius()
	const RING_TOLERANCE: float = 2.0
	const RING_WEIGHT: float = 80.0
	var ring_score = max(0.0, 1.0 - abs(dist_from_center - ideal_radius) / RING_TOLERANCE) * RING_WEIGHT

	return base_score + ring_score + randf_range(0.001, 0.050)

func transition_to_phase(phase_number: int) -> void:
	if GameData.current_pressure_phase <= GameData.MAX_PRESSURE_PHASE:
		GameData.current_pressure_phase = phase_number
		SignalBus.pressure_phase_changed.emit(phase_number)

	if phase_number >= 1:
		trigger_fracture_wave()

# ── Secondary Objective Timer ──────────────────────────────────────────────────

var _objective_timer: float = 0.0
var _next_objective_interval: float = 60.0  # first one after 60s

func _tick_objective_system(delta: float) -> void:
	if GameData.fracture_wave_active:
		return
	if GameData.current_pressure_phase < 1:
		return
	# Only spawn if all slots are empty
	if active_slots.size() > 0:
		return

	_objective_timer += delta
	if _objective_timer >= _next_objective_interval:
		_objective_timer = 0.0
		_spawn_random_objective()

func _weighted_pick_type(force_category: int = -1) -> SpecialTile.Type:
	var phase: int = GameData.current_pressure_phase
	var t: float = clampf((float(phase) - 1.0) / 9.0, 0.0, 1.0)

	# Weights: [BOOST_CORRIDOR, PRESSURE_SINK, UNSTABLE_CONDUIT, DEAD_ZONE]
	var weights: Array = [
		lerpf(50.0, 35.0, t),
		lerpf(2.0,  15.0, t),
		(lerpf(8.0, 20.0, t) if phase >= 4 else 0.0),
		(lerpf(6.0, 25.0, t) if phase >= 6 else 0.0),
	]

	var types: Array = [
		SpecialTile.Type.BOOST_CORRIDOR,
		SpecialTile.Type.PRESSURE_SINK,
		SpecialTile.Type.UNSTABLE_CONDUIT,
		SpecialTile.Type.DEAD_ZONE,
	]

	# Build exclusion set: recent types + wrong category if forced
	var eligible_total: float = 0.0
	for i in range(types.size()):
		var excluded: bool = weights[i] <= 0.0 or types[i] in _recent_types
		if force_category >= 0 and TILE_CATEGORIES[types[i]] != force_category:
			excluded = true
		if not excluded:
			eligible_total += weights[i]

	var use_exclusion: bool = eligible_total > 0.0

	var total: float = 0.0
	for i in range(types.size()):
		var w: float = weights[i]
		var excluded: bool = types[i] in _recent_types
		if force_category >= 0 and TILE_CATEGORIES[types[i]] != force_category:
			excluded = true
		if use_exclusion and excluded:
			w = 0.0
		total += w

	var roll: float = randf() * total
	var acc: float = 0.0
	for i in range(types.size()):
		var w: float = weights[i]
		var excluded: bool = types[i] in _recent_types
		if force_category >= 0 and TILE_CATEGORIES[types[i]] != force_category:
			excluded = true
		if use_exclusion and excluded:
			w = 0.0
		acc += w
		if roll <= acc:
			return types[i]

	# Fallback: ignore category/recent restrictions and just pick anything with weight
	for i in range(types.size()):
		if weights[i] > 0.0:
			return types[i]
	return SpecialTile.Type.BOOST_CORRIDOR

func _spawn_random_objective() -> void:
	var spawn_dual: bool = randf() < _dual_spawn_chance()

	if spawn_dual:
		# Force one positive, one hazard — pick positive first (rarer), hazard second
		var type_a: SpecialTile.Type = _weighted_pick_type(TileCategory.POSITIVE)
		var type_b: SpecialTile.Type = _weighted_pick_type(TileCategory.HAZARD)
		var cell_a: Vector2i = _find_special_tile_spawn_cell(type_a)
		var cell_b: Vector2i = _find_special_tile_spawn_cell(type_b)

		if cell_a == Vector2i(-9999, -9999) or cell_b == Vector2i(-9999, -9999):
			# Fall back to single spawn if dual placement fails
			spawn_dual = false
		else:
			_spawn_slot(type_a, cell_a)
			_spawn_slot(type_b, cell_b)
			_spawn_attempts = 0
			_next_objective_interval = randf_range(60.0, 180.0)
			return

	# Single spawn
	var tile_type: SpecialTile.Type = _weighted_pick_type()
	var spawn_cell: Vector2i = _find_special_tile_spawn_cell(tile_type)

	if spawn_cell == Vector2i(-9999, -9999):
		_spawn_attempts += 1
		if _spawn_attempts >= MAX_SPAWN_ATTEMPTS:
			_spawn_attempts = 0
			_next_objective_interval = randf_range(60.0, 180.0)
		else:
			_next_objective_interval = randf_range(15.0, 25.0)
		return

	_spawn_attempts = 0
	_next_objective_interval = randf_range(60.0, 180.0)
	_spawn_slot(tile_type, spawn_cell)

func _spawn_slot(tile_type: SpecialTile.Type, spawn_cell: Vector2i) -> void:
	_recent_types.append(tile_type)
	if _recent_types.size() > 2:
		_recent_types.pop_front()

	var st: SpecialTile = SpecialTileScene.instantiate()
	entities.add_child(st)
	st.setup(tile_type, spawn_cell)

	st.tile_connected.connect(_on_objective_tile_connected)
	st.tile_expired.connect(_on_objective_tile_expired)
	st.packet_passed_through.connect(_on_objective_packet_through)

	var slot: Dictionary = {
		"objective": _type_to_objective(tile_type),
		"tile": st,
		"packets_needed": 10,
		"pressure_threshold": GameData.current_pressure + 15.0 if tile_type == SpecialTile.Type.PRESSURE_SINK else 0.0,
	}
	active_slots.append(slot)

func _type_to_objective(t: SpecialTile.Type) -> Objective:
	match t:
		SpecialTile.Type.BOOST_CORRIDOR:   return Objective.BOOST_CORRIDOR
		SpecialTile.Type.PRESSURE_SINK:    return Objective.PRESSURE_SINK
		SpecialTile.Type.UNSTABLE_CONDUIT: return Objective.UNSTABLE_CONDUIT
		SpecialTile.Type.DEAD_ZONE:        return Objective.DEAD_ZONE
	return Objective.NONE

func _find_slot(tile: SpecialTile) -> Dictionary:
	for slot in active_slots:
		if slot["tile"] == tile:
			return slot
	return {}

func _find_special_tile_spawn_cell(tile_type: SpecialTile.Type) -> Vector2i:
	# Just find a valid seed cell — flood fill in SpecialTile handles the shape growth
	var bounds: Rect2i = get_camera_bounds()
	var candidates: Array[Vector2i] = []
	var require_empty: bool = (tile_type == SpecialTile.Type.PRESSURE_SINK)

	for x in range(bounds.position.x, bounds.end.x):
		for y in range(bounds.position.y, bounds.end.y):
			var c: Vector2i = Vector2i(x, y)
			if GameData.building_grid.has(c): continue
			if GameData.special_tiles.has(c): continue
			if require_empty and GameData.road_grid.has(c): continue
			if GameData.get_zone_for_cell(c) not in unlocked_zones: continue
			candidates.append(c)

	if candidates.is_empty():
		return Vector2i(-9999, -9999)

	if require_empty:
		# Pressure Sink: prefer far from existing pipes
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_near: bool = false
			var b_near: bool = false
			for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if GameData.road_grid.has(a + dir): a_near = true
				if GameData.road_grid.has(b + dir): b_near = true
			return int(a_near) < int(b_near)
		)
	else:
		# Others: prefer near existing pipes
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_near: bool = false
			var b_near: bool = false
			for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if GameData.road_grid.has(a + dir): a_near = true
				if GameData.road_grid.has(b + dir): b_near = true
			return int(b_near) < int(a_near)
		)

	var pool_size: int = max(1, candidates.size() / 2)
	return candidates.slice(0, pool_size).pick_random()

# ── Objective signal handlers ──────────────────────────────────────────────────

func _on_objective_tile_connected(tile: SpecialTile) -> void:
	var slot: Dictionary = _find_slot(tile)
	if slot.is_empty(): return
	# Pressure Sink no longer completes on connection — flow mechanic handles it
	# (kept as a hook for future objective variants)

func _on_objective_packet_through(tile: SpecialTile) -> void:
	pass

func _on_objective_tile_expired(tile: SpecialTile) -> void:
	var slot: Dictionary = _find_slot(tile)
	if slot.is_empty(): return
	match slot["objective"]:
		Objective.BOOST_CORRIDOR:
			NotificationManager.notify("Objective Expired.",
				NotificationManager.Type.OBJECTIVE, "OBJECTIVE")
		Objective.DEAD_ZONE:
			NotificationManager.notify("Dead Zone persisted. 200 data drained.",
				NotificationManager.Type.OBJECTIVE, "OBJECTIVE")
			GameData.total_data = max(0, GameData.total_data - 200)
		_:
			NotificationManager.notify("Objective expired.", NotificationManager.Type.OBJECTIVE, "OBJECTIVE")
	_remove_slot(slot)

func _complete_slot(slot: Dictionary, message: String, bonus_data: int) -> void:
	if bonus_data > 0:
		GameData.total_data += bonus_data
	NotificationManager.notify(message, NotificationManager.Type.OBJECTIVE, "OBJECTIVE COMPLETE")
	_remove_slot(slot)

func _remove_slot(slot: Dictionary) -> void:
	active_slots.erase(slot)

func trigger_fracture_wave() -> void:
	GameData.fracture_wave_active = true

	if GameData.wave_warning_enabled:
		MusicManager.stop_music(1.0)        # fade out music as warning starts
		AudioManager.play_sfx("fracture_wave_warning")
		await get_tree().create_timer(11.0).timeout
	else:
		# No warning — music cuts at exact moment wave appears
		MusicManager.stop_music(0.5)

	SignalBus.fracture_wave.emit()
	SignalBus.camera_shake.emit(0.4, 6.0)
	await get_tree().create_timer(5.0).timeout
	SignalBus.camera_shake.emit(0.5, 8.0)
	_execute_fracture_wave()

	# Check objectives after wave — Boost Corridor completes if still alive, others get wave notification
	for slot in active_slots.duplicate():
		if not is_instance_valid(slot["tile"]) or slot["tile"].is_expired:
			continue
		if slot["objective"] == Objective.BOOST_CORRIDOR:
			_complete_slot(slot, "Boost Corridor survived the wave! +150 data.", 150)
		else:
			slot["tile"].on_fracture_wave()

	await get_tree().create_timer(10.0).timeout
	GameData.fracture_wave_active = false
	
	# Resume music evaluation after wave ends
	MusicManager.play_game_music()

## Dispatches fracture effects based on current pressure phase.
## Pipes always fracture. Hubs join at phase 3. Slowdown/burst added from phase 5.
func _execute_fracture_wave() -> void:
	var phase: int = GameData.current_pressure_phase

	_apply_pipe_fractures(phase)

	if phase >= 3:
		_apply_hub_fractures(phase)

	if phase >= 5 and phase < 8:
		if randi() % 2 == 0:
			SignalBus.trigger_packet_slowdown.emit()
		else:
			SignalBus.trigger_vent_burst.emit()

	if phase >= 8:
		SignalBus.trigger_packet_slowdown.emit()
		SignalBus.trigger_vent_burst.emit()

## Fractures pipes sorted by zone priority. Outer/frontier pipes break first.
## Builds connected chains from fracturable pipes, then fractures whole chains.
## Guarantees at least one neighbor always remains visible after fracture.
func _apply_pipe_fractures(phase: int) -> void:
	var fracturable_set: Dictionary = {}
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if pipe is NewRoadTile and not pipe.is_fractured and not pipe.is_reinforced:
			fracturable_set[cell] = pipe

	# Build chains via DFS within fracturable pipes only
	var chains: Array = []
	var visited: Dictionary = {}
	for cell in fracturable_set:
		if visited.has(cell):
			continue
		var chain: Array = []
		var stack: Array = [cell]
		while stack.size() > 0:
			var c = stack.pop_back()
			if visited.has(c):
				continue
			visited[c] = true
			chain.append(fracturable_set[c])
			var pipe = fracturable_set[c]
			for dir in pipe.manual_connections:
				var neighbor_cell = c + dir
				if fracturable_set.has(neighbor_cell) and not visited.has(neighbor_cell):
					stack.append(neighbor_cell)
		chains.append(chain)

	# Only keep chains of 2+ pipes
	var valid_chains: Array = chains.filter(func(ch): return ch.size() >= 2)

	# Sort chains by zone priority of their first pipe — frontier first
	valid_chains.sort_custom(func(a, b):
		return _zone_priority(a[0].my_zone) > _zone_priority(b[0].my_zone)
	)

	var guaranteed = _get_guaranteed_pipe_fractures(phase)
	var fractured_count = 0
	const MAX_CHAIN_FRACTURE := 4
	for chain in valid_chains:
		if fractured_count >= guaranteed:
			break
		# Pick a random slice of up to MAX_CHAIN_FRACTURE pipes, minimum 2
		var max_start = max(0, chain.size() - MAX_CHAIN_FRACTURE)
		var start = randi() % (max_start + 1)
		var slice = chain.slice(start, start + MAX_CHAIN_FRACTURE)
		if slice.size() < 2:
			slice = chain.slice(0, 2)
		var notified_tiles: Array = []
		for pipe in slice:
			pipe.fracture()
			# Notify any special tile occupying this pipe's cell
			var pipe_cell: Vector2i = Vector2i(pipe.position / GameData.CELL_SIZE.x)
			if GameData.special_tiles.has(pipe_cell):
				var st = GameData.special_tiles[pipe_cell]
				if is_instance_valid(st) and st not in notified_tiles and st.tile_type == SpecialTile.Type.UNSTABLE_CONDUIT:
					notified_tiles.append(st)
					st.on_pipe_fractured_under()
		fractured_count += 1

## Fractures a guaranteed number of hubs based on phase.
func _apply_hub_fractures(phase: int) -> void:
	var fracturable_hubs: Array = []
	for hub in get_tree().get_nodes_in_group("hubs"):
		if not hub.is_fractured:
			fracturable_hubs.append(hub)
	for hub in fracturable_hubs.slice(0, _get_guaranteed_hub_fractures(phase)):
		hub.fracture()

func _get_guaranteed_pipe_fractures(phase: int) -> int:
	var total_pipes = GameData.road_grid.size()
	
	# Never fracture more than a percentage of total pipes
	# Early game (20 pipes): phase 3 = max 2, phase 5 = max 4
	# Late game (200 pipes): phase 3 = 2, phase 10 = 20
	var raw_count: int
	match phase:
		1:  raw_count = 1
		2:  raw_count = 2
		3:  raw_count = 2
		4:  raw_count = 3
		5:  raw_count = 4
		6:  raw_count = 5
		7:  raw_count = 9
		8:  raw_count = 11
		9:  raw_count = 15
		10: raw_count = 20
		_:  raw_count = 0

	# Cap at 25% of total pipes so early game isn't destroyed
	var max_allowed = max(1, int(total_pipes * 0.25))
	return min(raw_count, max_allowed)

func _get_guaranteed_hub_fractures(phase: int) -> int:
	match phase:
		3: return 1  
		4: return 2
		5: return 2   
		6: return 2
		7: return 3
		8: return 3
		9: return 4
		10: return 5
		_: return 0

func _zone_priority(zone: GameData.Zone) -> int:
	# Frontier pipes fracture first, core last
	match zone:
		GameData.Zone.FRONTIER: return 4
		GameData.Zone.OUTER:    return 3
		GameData.Zone.INNER:    return 2
		GameData.Zone.CORE:     return 1
		_: return 0
#endregion

#region First Colony
func spawn_initial_colony() -> void:
	"""
	Spawn 1 research-hub and 1 vent at the start of the game to let the player get going.
	"""
	# First we spawn a hub using the new scoring system
	var scored_tiles = []
	var candidate_tiles = calculate_candidate_tiles(screen_center, 3, 12, hub_size, 1)
	

	
	# Score each candidate
	for candidate in candidate_tiles:
		var score = score_tile(candidate)
		scored_tiles.append({
			"tile": candidate,
			"score": score
		})

	
	if scored_tiles.is_empty():
		NotificationManager.notify("No valid spawn location for initial hub.", NotificationManager.Type.ERROR, "SPAWN ERROR")
		return
	
	# Sort and pick LEAST NEGATIVE tile for hub (highest score)
	scored_tiles.sort_custom(func (a, b): return a.score > b.score)
	var target_tile_for_hub = scored_tiles.pick_random().tile

	
	# Instantiate the hub
	var research_hub = research_hub_scene.instantiate()
	entities.add_child(research_hub)
	research_hub.position = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
	research_hub.register_building(research_hub)
	
	var hub_center_cell = target_tile_for_hub + Vector2i(1, 1)
	GameData.apply_influence(hub_center_cell, "hub")
	
	# Now spawn a vent near the hub
	var hub_world_pos = Vector2(target_tile_for_hub * GameData.CELL_SIZE.x)
	var vent_scored_tiles = []
	var vent_candidates = calculate_candidate_tiles(hub_world_pos, 6, 12, vent_size, 0)
	

	
	# Score vent candidates
	for candidate in vent_candidates:
		var score = score_tile(candidate)
		vent_scored_tiles.append({
			"tile": candidate,
			"score": score
		})
	
	if not vent_scored_tiles.is_empty():
		vent_scored_tiles.sort_custom(func (a, b): return a.score > b.score)
		var target_tile_for_vent = vent_scored_tiles.pick_random().tile
		
		var vent_1 = vent_scene.instantiate()
		entities.add_child(vent_1)
		vent_1.position = Vector2(target_tile_for_vent * GameData.CELL_SIZE.x) + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
		vent_1.register_building(vent_1)
		GameData.apply_influence(target_tile_for_vent, "vent")
		vent_clusters.append({ "center": target_tile_for_vent, "count": 1 })

	else:
		NotificationManager.notify("No valid spawn location for initial vent.", NotificationManager.Type.ERROR, "SPAWN ERROR")
#endregion

#region HubSpawning
func try_hub_spawn() -> void:
	var scored_tiles = []
	var camera_bounds = get_camera_bounds()

	# First try with buffer 1 — preferred spacing
	for x in range(camera_bounds.position.x, camera_bounds.end.x):
		for y in range(camera_bounds.position.y, camera_bounds.end.y):
			var tile = Vector2i(x, y)
			if is_area_clear(tile, hub_size, camera_bounds, 1):
				scored_tiles.append({
					"tile": tile,
					"score": score_tile(tile)
				})

	# Fallback — no space with buffer 1, try buffer 0
	if scored_tiles.is_empty():
		#NotificationManager.notify("Limited space — placing hub in tight quarters.", NotificationManager.Type.INFO, "HUB SPAWN")
		for x in range(camera_bounds.position.x, camera_bounds.end.x):
			for y in range(camera_bounds.position.y, camera_bounds.end.y):
				var tile = Vector2i(x, y)
				if is_area_clear(tile, hub_size, camera_bounds, 0):
					scored_tiles.append({
						"tile": tile,
						"score": score_tile(tile)
					})

	if scored_tiles.is_empty():
		ResourceManager.refund_hub()
		NotificationManager.notify("No valid hub locations. Expand your territory.", NotificationManager.Type.WARNING, "HUB SPAWN")
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile = scored_tiles.slice(0, 3).pick_random().tile
	spawn_hub_at(target_tile)

func spawn_hub_at(position: Vector2i) -> void:
	var hub = research_hub_scene.instantiate()
	entities.add_child(hub)
	hub.position = position * GameData.CELL_SIZE.x
	#BuildingSpawnEffect.create_at(hub.position, get_parent(), hub_size)
	hub.register_building(hub)
	var hub_center_cell = position + Vector2i(1, 1)
	GameData.apply_influence(hub_center_cell, "hub")
#endregion

#region VentSpawning

const VENT_CLUSTER_MAX: int = 5
const VENT_SPAWN_RADIUS: int = 5
const VENT_SPAWN_RADIUS_MAX: int = 10

## Fixed cluster registry — centers are set once and never change.
## Each entry: { "center": Vector2i, "count": int }
var vent_clusters: Array = []

func get_dynamic_cluster_min_dist_for_stage(stage: int) -> int:
	match stage:
		0: return 6
		1: return 7
		2: return 8
		3: return 9
		_: return 6

func get_dynamic_cluster_min_dist() -> int:
	return get_dynamic_cluster_min_dist_for_stage(GameData.current_stage)

## Returns the first cluster that still has room, or empty dict if all full.
func find_open_cluster() -> Dictionary:
	for cluster in vent_clusters:
		if cluster["count"] < VENT_CLUSTER_MAX:
			return cluster
	return {}

## Finds a new cluster center, falling back to previous stage distances if needed.
## Returns Vector2i(-9999, -9999) if no center found even at stage 0 distance.
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

			scored_tiles.sort_custom(func(a, b): return a.score > b.score)
			return scored_tiles.slice(0, 3).pick_random().tile

	NotificationManager.notify("Map capacity reached. Expand your territory.", NotificationManager.Type.WARNING, "MAP FULL")
	return Vector2i(-9999, -9999)

func try_vent_spawn() -> void:

	var camera_bounds = get_camera_bounds()
	var spawn_center: Vector2i

	var open_cluster = find_open_cluster()

	if not open_cluster.is_empty():
		spawn_center = open_cluster["center"]

	else:
		spawn_center = find_new_cluster_center()
		if spawn_center == Vector2i(-9999, -9999):
			return
		vent_clusters.append({ "center": spawn_center, "count": 0 })


	# Find candidate tiles within spawn radius, expanding if needed
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


	if scored_tiles.is_empty():
		NotificationManager.notify("No valid vent locations available.", NotificationManager.Type.WARNING, "VENT SPAWN")
		return

	scored_tiles.sort_custom(func(a, b): return a.score > b.score)
	var target_tile = scored_tiles.slice(0, 3).pick_random().tile

	for cluster in vent_clusters:
		if cluster["center"] == spawn_center:
			cluster["count"] += 1
			break

	spawn_vent_at(target_tile)

func spawn_vent_at(vent_position: Vector2i) -> void:
	var vent = vent_scene.instantiate()
	entities.add_child(vent)
	vent.position = Vector2(vent_position) * GameData.CELL_SIZE.x + Vector2(GameData.CELL_SIZE.x / 2, GameData.CELL_SIZE.x / 2)
	#BuildingSpawnEffect.create_at(vent.position, get_parent(), vent_size)
	vent.register_building(vent)
	GameData.apply_influence(vent_position, "vent")
#endregion
