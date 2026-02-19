#extends Node2D
#
## NOTE: Add this signal to SignalBus.gd:
## signal camera_zoom_requested(zoom_level: int)
#
#@onready var workplace_scene = preload("res://Scenes/workplace.tscn")
#@onready var house_scene = preload("res://Scenes/house.tscn")
#@onready var building_timer: Timer = $BuildingTimer
#@onready var map_timer: Timer = $TemporaryMapTimer
#
#@export var playable_margin_cells: int = 1
#@export var spawn_buffer_cells: int = 0
#
## =============================================================================
## MINI MOTORWAYS-STYLE EARLY GAME (Precise Timeline - First 5 Minutes)
## KEY RULE: Houses of same color NEVER spawn near their workplace (scattered far away)
## =============================================================================
#var game_start_time: float = 0.0
#var structured_phase_active: bool = true
#
## Precise spawn schedule (time in seconds : action)
#const SPAWN_SCHEDULE = [
	## 0:00 - Bootstrap
	#{"time": 0, "type": "workplace", "color_ref": "new", "notes": "WP1"},
	#{"time": 0, "type": "house", "color_ref": "wp1", "notes": "House 1 for WP1"},
	#
	## 0:30 - Build up WP1
	#{"time": 30, "type": "house", "color_ref": "wp1", "notes": "House 2 for WP1"},
	#
	## 0:45 - WP2 anticipatory
	#{"time": 45, "type": "house", "color_ref": "wp2_anticipatory", "notes": "House 1 for WP2 (no WP yet)"},
	#
	## 0:55-0:65 - WP2 spawns
	#{"time": 60, "type": "workplace", "color_ref": "wp2_from_anticipatory", "notes": "WP2 (matches anticipatory)"},
	#
	## 1:30 - Mixed spawning
	#{"time": 90, "type": "house", "color_ref": "wp2", "notes": "House 2 for WP2"},
	#{"time": 90, "type": "house", "color_ref": "wp1_or_wp3_choice", "notes": "House 3 for WP1 OR House 1 for WP3"},
	#
	## 1:40 - Complement
	#{"time": 100, "type": "house", "color_ref": "wp1_or_wp3_complement", "notes": "Whichever skipped at 90s"},
	#
	## 2:00 - WP3 + zoom
	#{"time": 120, "type": "workplace", "color_ref": "new", "notes": "WP3 + camera zoom"},
	#{"time": 120, "type": "camera_zoom", "color_ref": "none", "notes": "Zoom out"},
	#
	## 2:30 - WP3 houses
	#{"time": 150, "type": "house", "color_ref": "wp3", "notes": "House 1 for WP3"},
	#{"time": 150, "type": "house", "color_ref": "wp3", "notes": "House 2 for WP3"},
	#
	## 3:00 - WP4 anticipatory
	#{"time": 180, "type": "house", "color_ref": "wp4_anticipatory", "notes": "House 1 for WP4"},
	#{"time": 185, "type": "house", "color_ref": "wp4_maybe", "notes": "House 2 for WP4 (50% chance)"},
	#
	## 3:15 - WP4 spawns
	#{"time": 195, "type": "workplace", "color_ref": "wp4_from_anticipatory", "notes": "WP4"},
	#
	## Continue to 5 minutes
	#{"time": 220, "type": "house", "color_ref": "underserved", "notes": "Random underserved"},
	#{"time": 240, "type": "house", "color_ref": "underserved", "notes": "Random underserved"},
	#{"time": 260, "type": "workplace", "color_ref": "new", "notes": "WP5"},
	#{"time": 280, "type": "house", "color_ref": "underserved", "notes": "Random underserved"},
#]
#
#const STRUCTURED_PHASE_END = 300.0  # 5 minutes
#
## State tracking for structured phase
#var next_schedule_index: int = 0
#var workplaces_spawned_count: int = 0
#var workplace_colors: Array[int] = []  # [wp1_color, wp2_color, wp3_color, ...]
#var wp2_anticipatory_color: int = -1
#var wp4_anticipatory_color: int = -1
#var wp1_or_wp3_first_choice: int = -1  # 1=wp1, 3=wp3
#var camera_zoomed: bool = false
#
## =============================================================================
## DEMAND-DRIVEN CONFIGURATION
## =============================================================================
#const TARGET_HOUSE_TO_WORKPLACE_RATIO = 5.5  # 3-4 houses per workplace
#const MAX_WORKPLACES = 12
#const MAX_HOUSES = 80  # Cap total houses to prevent overcrowding
#
## House clustering configuration
#const HOUSE_CLUSTER_VARIANCE = 4  # How tightly houses cluster near workplaces
#const HOUSE_FALLBACK_VARIANCE = 8  # If no workplace exists, use wider variance
#
## Workplace isolation — can be reduced dynamically when space is tight
##
## SPACE REQUIREMENTS VISUALIZATION:
## 
## 3×3 WORKPLACE with isolation=2:
## . . . . . . .   (7×7 cells = 448×448 px)
## . i i i i i .   i = isolation zone (workplace-only)
## . i W W W i .   W = workplace footprint (3×3)
## . i W W W i .   . = 1-cell buffer (no buildings/roads)
## . i W W W i .
## . i i i i i .
## . . . . . . .
##
## 1×1 HOUSE:
## . . .   (3×3 cells = 192×192 px)
## . H .   H = house footprint (1×1)
## . . .   . = 1-cell buffer (no buildings/roads)
##
#var dynamic_workplace_isolation: int = 2
#const MIN_WORKPLACE_ISOLATION: int = 1  
#const BASE_WORKPLACE_ISOLATION: int = 2 
#
## =============================================================================
## SPAWN TIMING
## =============================================================================
#const BASE_SPAWN_INTERVAL = 15.0  # Check for spawn every 15 seconds (slow, intentional)
#
## Progressive phases based on player score (AFTER 5 minute structured phase)
#const PHASE1_SCORE_THRESHOLD = 40      # Phase 1: Tutorial/Early game
#const PHASE2_SCORE_THRESHOLD = 150     # Phase 2: Mid game
#const PHASE3_SCORE_THRESHOLD = 300     # Phase 3: Late game
## Above 300: Endgame - player just manages existing infrastructure
#
#const HOUSES_PER_WORKPLACE_PHASE1_MIN = 2
#const HOUSES_PER_WORKPLACE_PHASE1_MAX = 3
#
#const HOUSES_PER_WORKPLACE_PHASE2_MIN = 3
#const HOUSES_PER_WORKPLACE_PHASE2_MAX = 5
#
#const HOUSES_PER_WORKPLACE_PHASE3_MIN = 4
#const HOUSES_PER_WORKPLACE_PHASE3_MAX = 6
#
#const HOUSES_PER_WORKPLACE_PHASE4_MIN = 5
#const HOUSES_PER_WORKPLACE_PHASE4_MAX = 8
#
## =============================================================================
## ADAPTIVE PACING SYSTEM
## Director monitors game "temperature" and adjusts spawning dynamically
## Slow game = inject chaos (outliers, distant houses)
## Fast game = let it naturally play out
## =============================================================================
#
## Game state metrics for pacing
#var total_backlog: int = 0
#var idle_houses_count: int = 0
#var houses_spawned_for_pending: Dictionary = {}
#
#const HOUSES_BEFORE_WORKPLACE = 3
#
#func calculate_game_metrics() -> void:
	#"""Update game state metrics"""
	#total_backlog = 0
	#idle_houses_count = 0
	#
	## Sum up all workplace backlogs
	#for building in GameData.building_grid.values():
		#if building is Workplace:
			#total_backlog += building.shipment_backlog
	#
	## Count idle houses (houses with color but no matching workplace)
	#update_color_counts()
	#for house in all_houses:
		#var has_matching_workplace = workplaces_per_color.get(house.color_id, 0) > 0
		#if not has_matching_workplace:
			#idle_houses_count += 1
#
## House cluster tracking - remembers where houses of each color spawned
## Structure: {color_id: [cluster1_cells, cluster2_cells, ...]}
## Each cluster is an array of Vector2i positions
#var color_cluster_locations: Dictionary = {}
#const MAX_CLUSTERS_PER_COLOR = 2  # Allow 2 distinct clusters per color
#const CLUSTER_PROXIMITY_THRESHOLD = 8  # Houses within 8 cells = same cluster
#
#
#func get_game_phase() -> int:
	#"""Returns 1-4 based on player score"""
	#var current_score = GameData.player_score  # Assuming GameData tracks score
	#if current_score < PHASE1_SCORE_THRESHOLD:
		#return 1
	#elif current_score < PHASE2_SCORE_THRESHOLD:
		#return 2
	#elif current_score < PHASE3_SCORE_THRESHOLD:
		#return 3
	#else:
		#return 4  # Management phase
#
#
#func get_houses_per_workplace() -> int:
	#"""Returns how many houses to spawn based on current phase"""
	#var phase = get_game_phase()
	#match phase:
		#1:
			#return randi_range(HOUSES_PER_WORKPLACE_PHASE1_MIN, HOUSES_PER_WORKPLACE_PHASE1_MAX)
		#2:
			#return randi_range(HOUSES_PER_WORKPLACE_PHASE2_MIN, HOUSES_PER_WORKPLACE_PHASE2_MAX)
		#3:
			#return randi_range(HOUSES_PER_WORKPLACE_PHASE3_MIN, HOUSES_PER_WORKPLACE_PHASE3_MAX)
		#4:
			#return randi_range(HOUSES_PER_WORKPLACE_PHASE4_MIN, HOUSES_PER_WORKPLACE_PHASE4_MAX)
		#_:
			#return 3
#
#
#func register_house_to_cluster(color_id: int, position: Vector2i) -> void:
	#"""Track where a house of this color spawned for future clustering"""
	#if not color_cluster_locations.has(color_id):
		#color_cluster_locations[color_id] = []
	#
	## Find if this position is near an existing cluster
	#var added_to_cluster = false
	#for cluster in color_cluster_locations[color_id]:
		#for cluster_pos in cluster:
			#if position.distance_to(cluster_pos) <= CLUSTER_PROXIMITY_THRESHOLD:
				#cluster.append(position)
				#added_to_cluster = true
				#break
		#if added_to_cluster:
			#break
	#
	## If not near any cluster, create new cluster (if we haven't hit max)
	#if not added_to_cluster:
		#if color_cluster_locations[color_id].size() < MAX_CLUSTERS_PER_COLOR:
			#color_cluster_locations[color_id].append([position])
		#else:
			## Add to a random existing cluster
			#color_cluster_locations[color_id].pick_random().append(position)
#
#
#func get_cluster_spawn_target(color_id: int) -> Vector2i:
	#"""Get a spawn target near existing houses of this color"""
	#if not color_cluster_locations.has(color_id) or color_cluster_locations[color_id].is_empty():
		#return Vector2i.ZERO  # No existing cluster
	#
	## 70% chance: spawn near existing cluster
	## 30% chance: start a new cluster (if allowed)
	#var should_cluster = randf() < 0.7
	#
	#if should_cluster or color_cluster_locations[color_id].size() >= MAX_CLUSTERS_PER_COLOR:
		## Pick a random cluster and random house within it
		#var cluster = color_cluster_locations[color_id].pick_random()
		#var base_position = cluster.pick_random()
		#return base_position
	#else:
		## Start new cluster - return zero to signal random placement
		#return Vector2i.ZERO
#
#
#func count_houses_of_color(color_id: int) -> int:
	#"""Count how many houses exist of a specific color"""
	#var count = 0
	#for house in all_houses:
		#if house.color_id == color_id:
			#count += 1
	#return count
#
#
#func get_newest_workplace_color() -> int:
	#"""Get the color of the most recently spawned workplace"""
	#var workplaces = []
	#for building in GameData.building_grid.values():
		#if building is Workplace:
			#workplaces.append(building)
	#
	#if workplaces.is_empty():
		#return -1
	#
	## Return the last one (most recent)
	#return workplaces.back().color_id
#
#
#func pick_different_color_than(exclude1: int, exclude2: int = -1) -> int:
	#"""Pick a random color that isn't exclude1 or exclude2"""
	#var available_colors = []
	#for i in range(GameData.active_color_palette.size()):
		#if i != exclude1 and i != exclude2:
			#available_colors.append(i)
	#
	#if available_colors.is_empty():
		#return pick_house_color()  # Fallback
	#
	#return available_colors.pick_random()
#
#
#func _spawn_house_for_color_near_workplace(zone: Rect2i, color_id: int) -> bool:
	#"""Spawn a house of specific color near its workplace (or near existing houses of same color)"""
	## Try to find existing houses of this color for clustering
	#var cluster_target = get_cluster_spawn_target(color_id)
	#var target_cell: Vector2i
	#
	#if cluster_target != Vector2i.ZERO:
		## Spawn near existing houses
		#target_cell = cluster_target
		#print("  → Clustering: spawning near existing house at %s" % cluster_target)
	#else:
		## Try to spawn near workplace
		#var workplace_of_color = null
		#for building in GameData.building_grid.values():
			#if building is Workplace and building.color_id == color_id:
				#workplace_of_color = building
				#break
		#
		#if workplace_of_color:
			#target_cell = workplace_of_color.entrance_cell
		#else:
			## No workplace yet - random placement
			#target_cell = Vector2i(
				#zone.position.x + randi_range(0, zone.size.x),
				#zone.position.y + randi_range(0, zone.size.y)
			#)
	#
	#var success = spawn_building_with_color(house_scene, target_cell, zone, 4, color_id)
	#
	#if not success:
		#success = spawn_building_with_color(house_scene, target_cell, zone, 8, color_id)
	#
	## Register to cluster tracking on success
	#if success:
		## Find the actual spawn position (we don't know exact cell after variance)
		## We'll track it in finalize_building_spawn instead
		#pass
	#
	#return success
#
#
#func trigger_camera_zoom(zoom_level: int) -> void:
	#"""Trigger camera zoom out event"""
	#print("Director: 📷 CAMERA ZOOM OUT (level %d)" % zoom_level)
	## Emit signal for camera to zoom out
	#SignalBus.emit_signal("camera_zoom_requested", zoom_level)
#
#
## Outlier workplaces for map coverage
#const OUTLIER_EVERY_N_WORKPLACES = 4
#const OUTLIER_MIN_DIST = 15
#const OUTLIER_MAX_DIST = 25
#
#var all_houses: Array[Node2D] = []
#var pending_requests: Array[Node2D] = []
#
## =============================================================================
## COLOR BALANCING SYSTEM
## Track how many houses/workplaces exist per color to spawn intelligently
## =============================================================================
#var houses_per_color: Dictionary = {}  # {color_id: count}
#var workplaces_per_color: Dictionary = {}  # {color_id: count}
#var last_workplace_color: int = -1  # Track what color workplace spawned last
#
## =============================================================================
## ALWAYS-ANTICIPATORY SPAWNING SYSTEM
## Houses ALWAYS spawn first, then workplace spawns when conditions are met
## =============================================================================
#
## Anticipatory house requirements per color
#const MIN_HOUSES_BEFORE_WORKPLACE = 2  # Need at least 2 houses before workplace
#const IDEAL_HOUSES_BEFORE_WORKPLACE = 4  # Ideal: 4 houses waiting
#
## Workplace spawning triggers
#const TRIGGER_RATIO_EXCEEDED = "ratio"      # Ratio threshold hit
#const TRIGGER_ENOUGH_HOUSES = "houses"      # Enough anticipatory houses exist
#
#var pending_workplace_colors: Array[int] = []  # Colors with houses waiting for workplace
#var houses_per_pending_color: Dictionary = {}  # {color_id: house_count}
#
#func should_spawn_workplace() -> Dictionary:
	#"""Check if conditions are met to spawn a workplace. Returns {should_spawn: bool, trigger: String, color: int}"""
	#
	## Check: Ratio exceeded (need more workplaces for balance)
	#var current_workplace_count = get_workplace_count()
	#var current_ratio = calculate_current_ratio()
	#
	## Determine if this should be an outlier (WP4 and WP5 have a chance)
	#var is_outlier = false
	#if current_workplace_count == 3:  # Next spawn is WP4
		#is_outlier = randf() < 0.5  # 50% chance
	#elif current_workplace_count == 4:  # Next spawn is WP5
		#is_outlier = randf() < 0.5  # 50% chance
	#
	#if current_ratio >= TARGET_HOUSE_TO_WORKPLACE_RATIO and current_workplace_count < MAX_WORKPLACES:
		## Spawn workplace for color with most houses waiting
		#var best_color = get_color_with_most_houses()
		#if best_color != -1:
			#return {"should_spawn": true, "trigger": TRIGGER_RATIO_EXCEEDED, "color": best_color, "is_outlier": is_outlier}
	#
	## Check 3: Enough anticipatory houses exist for a color
	#for color in pending_workplace_colors:
		#var house_count = houses_per_pending_color.get(color, 0)
		#
		## If we have 4+ houses of this color and no workplace yet, spawn workplace
		#if house_count >= IDEAL_HOUSES_BEFORE_WORKPLACE:
			#update_color_counts()
			#var workplace_count = workplaces_per_color.get(color, 0)
			#
			#if workplace_count == 0:  # No workplace exists yet
				#return {"should_spawn": true, "trigger": TRIGGER_ENOUGH_HOUSES, "color": color, "is_outlier": is_outlier}
	#
	#return {"should_spawn": false, "trigger": "", "color": -1, "is_outlier": false}
#
#
#func get_color_with_most_houses() -> int:
	#"""Returns color_id with most houses (prioritize colors without workplaces)"""
	#update_color_counts()
	#
	#var best_color = -1
	#var max_houses = 0
	#
	#for color in houses_per_color.keys():
		#var house_count = houses_per_color[color]
		#var workplace_count = workplaces_per_color.get(color, 0)
		#
		## Prioritize colors with NO workplace
		#if workplace_count == 0 and house_count > max_houses:
			#max_houses = house_count
			#best_color = color
	#
	## If all colors have workplaces, pick color with most houses
	#if best_color == -1:
		#for color in houses_per_color.keys():
			#if houses_per_color[color] > max_houses:
				#max_houses = houses_per_color[color]
				#best_color = color
	#
	#return best_color
#
#
#func _ready() -> void:
	#game_start_time = Time.get_ticks_msec() / 1000.0
	#
	#print("=== DEMAND-DRIVEN DIRECTOR INITIALIZED ===")
	#print("Target ratio: %.1f houses per workplace" % TARGET_HOUSE_TO_WORKPLACE_RATIO)
	#print("Current map size: ", GameData.current_map_size)
#
	#if not building_timer.timeout.is_connected(_on_building_timer_timeout):
		#building_timer.timeout.connect(_on_building_timer_timeout)
#
	#SignalBus.delivery_requested.connect(_on_delivery_requested)
	#SignalBus.car_returned_home.connect(process_backlog)
	#SignalBus.map_changed.connect(_on_map_changed)
#
	#building_timer.wait_time = BASE_SPAWN_INTERVAL
	#setup_expansion_timer()
	#bootstrap_game()
	#building_timer.start()
#
#
## =============================================================================
## VALID SPAWN ZONE — single source of truth
## =============================================================================
#func get_valid_spawn_zone() -> Rect2i:
	#var camera = get_viewport().get_camera_2d()
	#if not camera:
		#push_warning("Director: get_valid_spawn_zone called before camera is ready.")
		#return Rect2i()
#
	#var map_rect = GameData.current_map_size
	#var spawn_rect = map_rect.grow(-(playable_margin_cells + spawn_buffer_cells))
#
	#var viewport_size = get_viewport().get_visible_rect().size
	#var canvas_xform = get_viewport().get_canvas_transform().affine_inverse()
	#var screen_world_min = canvas_xform * Vector2(100, 60)
	#var screen_world_max = canvas_xform * (viewport_size - Vector2(100, 120))
#
	#var screen_cell_min = Vector2i(
		#floor(screen_world_min.x / GameData.CELL_SIZE.x),
		#floor(screen_world_min.y / GameData.CELL_SIZE.x)
	#) + Vector2i(1, 1)
	#var screen_cell_max = Vector2i(
		#floor(screen_world_max.x / GameData.CELL_SIZE.x),
		#floor(screen_world_max.y / GameData.CELL_SIZE.x)
	#) - Vector2i(1, 1)
#
	#var visible_rect = Rect2i(screen_cell_min, screen_cell_max - screen_cell_min)
	#return spawn_rect.intersection(visible_rect)
#
#
## =============================================================================
## WORKPLACE COUNT — derived from GameData
## =============================================================================
#func get_workplace_count() -> int:
	#var unique_workplaces = {}
	#for building in GameData.building_grid.values():
		#if building is Workplace:
			## Use the building instance as the key to avoid counting same building multiple times
			#unique_workplaces[building] = true
	#return unique_workplaces.size()
#
#
## =============================================================================
## RATIO-BASED DEMAND CALCULATION
## =============================================================================
#func calculate_current_ratio() -> float:
	#var workplace_count = get_workplace_count()
	#if workplace_count == 0:
		#return INF  # Infinite ratio means we desperately need workplaces
	#return float(all_houses.size()) / float(workplace_count)
#
#
## =============================================================================
## SETUP
## =============================================================================
#func setup_expansion_timer() -> void:
	#map_timer.wait_time = 60
	#map_timer.one_shot = false
	#map_timer.start()
#
#
#func bootstrap_game() -> void:
	#"""Bootstrap spawns only WP1. Schedule handles all other spawning."""
	#var valid_spawn_zone = get_valid_spawn_zone()
	#if valid_spawn_zone.size == Vector2i.ZERO:
		#push_warning("Director: bootstrap_game got an empty spawn zone, skipping.")
		#return
#
	#var center = Vector2i(
		#valid_spawn_zone.position.x + valid_spawn_zone.size.x / 2,
		#valid_spawn_zone.position.y + valid_spawn_zone.size.y / 2
	#)
#
	#print("=== BOOTSTRAP START ===")
	#print("Bootstrap: spawn zone = %s, center = %s" % [valid_spawn_zone, center])
	#
	## Spawn only WP1 - schedule will handle House 1
	#if spawn_building_near(workplace_scene, center, valid_spawn_zone, 3):
		#print("Bootstrap: Workplace 1 spawned - schedule will handle houses")
		#await get_tree().process_frame
		#
		## Track WP1 color
		#for building in GameData.building_grid.values():
			#if building is Workplace:
				#workplace_colors.append(building.color_id)
				#workplaces_spawned_count = 1
				#print("Bootstrap: WP1 color is %d" % building.color_id)
				#break
		#
		## Advance schedule past WP1 spawn
		#next_schedule_index = 1  # Skip to House 1 spawn
	#else:
		#print("Bootstrap: Workplace 1 FAILED")
#
#
## =============================================================================
## DELIVERY SYSTEM
## =============================================================================
#func _on_map_changed() -> void:
	#await get_tree().process_frame
	#process_backlog()
#
#
#func _on_delivery_requested(requester: Node2D) -> void:
	#pending_requests.append(requester)
	#process_backlog()
#
#
## =============================================================================
## SCHEDULE PROCESSOR (for structured early game phase)
## =============================================================================
#func _process_schedule_item(item: Dictionary, zone: Rect2i) -> void:
	#"""Process a single schedule item based on its type and color_ref"""
	#match item["type"]:
		#"workplace":
			#await _spawn_scheduled_workplace(item, zone)
		#
		#"house":
			#await _spawn_scheduled_house(item, zone)
		#
		#"camera_zoom":
			#if not camera_zoomed:
				#trigger_camera_zoom(1)
				#camera_zoomed = true
				#print("Director: 📷 Camera zooming out")
#
#
#func _spawn_scheduled_workplace(item: Dictionary, zone: Rect2i) -> void:
	#"""Spawn a workplace according to schedule"""
	#var color_id = -1
	#
	#match item["color_ref"]:
		#"new":
			## Pick a new color not yet used
			#color_id = pick_unique_workplace_color()
		#
		#"wp2_from_anticipatory":
			## Use the color we picked for WP2's anticipatory house
			#color_id = wp2_anticipatory_color
			#if color_id == -1:
				#color_id = pick_unique_workplace_color()
		#
		#"wp4_from_anticipatory":
			## Use the color we picked for WP4's anticipatory house
			#color_id = wp4_anticipatory_color
			#if color_id == -1:
				#color_id = pick_unique_workplace_color()
	#
	#print("Director: 🏭 Spawning scheduled workplace (color %d): %s" % [color_id, item["notes"]])
	#
	#var success = await _spawn_workplace_with_color(zone, color_id)
	#
	#if success:
		#workplace_colors.append(color_id)
		#workplaces_spawned_count += 1
#
#
#func _spawn_scheduled_house(item: Dictionary, zone: Rect2i) -> void:
	#"""Spawn a house according to schedule - SCATTERED if same color as workplace"""
	#var color_id = -1
	#var spawn_scattered = false  # Houses of same color as WP spawn FAR from WP
	#
	#match item["color_ref"]:
		#"wp1":
			#color_id = workplace_colors[0] if workplace_colors.size() > 0 else 0
			#spawn_scattered = true
		#
		#"wp2":
			#color_id = workplace_colors[1] if workplace_colors.size() > 1 else 0
			#spawn_scattered = true
		#
		#"wp3":
			#color_id = workplace_colors[2] if workplace_colors.size() > 2 else 0
			#spawn_scattered = true
		#
		#"wp2_anticipatory":
			## Pick a new color for WP2 (store it for later)
			#color_id = pick_unique_workplace_color()
			#wp2_anticipatory_color = color_id
			#spawn_scattered = false  # No workplace yet
		#
		#"wp4_anticipatory":
			## Pick a new color for WP4 (store it for later)
			#color_id = pick_unique_workplace_color()
			#wp4_anticipatory_color = color_id
			#spawn_scattered = false
		#
		#"wp4_maybe":
			## 50% chance to spawn this house
			#if randf() < 0.5:
				#color_id = wp4_anticipatory_color
				#spawn_scattered = false
			#else:
				#print("Director: Skipping optional WP4 house (50% chance)")
				#return
		#
		#"wp1_or_wp3_choice":
			## Choose randomly between WP1 house or WP3 anticipatory
			#if randf() < 0.5:
				#color_id = workplace_colors[0]  # WP1
				#wp1_or_wp3_first_choice = 1
				#spawn_scattered = true
			#else:
				#color_id = pick_unique_workplace_color()  # WP3 anticipatory
				#wp1_or_wp3_first_choice = 3
				#spawn_scattered = false
		#
		#"wp1_or_wp3_complement":
			## Spawn whichever wasn't chosen before
			#if wp1_or_wp3_first_choice == 1:
				#color_id = pick_unique_workplace_color()  # WP3 anticipatory
				#spawn_scattered = false
			#else:
				#color_id = workplace_colors[0]  # WP1
				#spawn_scattered = true
		#
		#"underserved":
			## Pick color with fewest houses
			#color_id = pick_house_color()
			## Check if this color has a workplace
			#update_color_counts()
			#spawn_scattered = workplaces_per_color.get(color_id, 0) > 0
	#
	#print("Director: 🏠 Spawning scheduled house (color %d, scattered: %s): %s" % [
		#color_id,
		#spawn_scattered,
		#item["notes"]
	#])
	#
	#await _spawn_house_for_color(zone, color_id, spawn_scattered)
#
#
#func pick_unique_workplace_color() -> int:
	#"""Pick a color not yet used by any workplace"""
	#var used_colors = workplace_colors.duplicate()
	#var available = []
	#
	#for i in range(GameData.active_color_palette.size()):
		#if not (i in used_colors):
			#available.append(i)
	#
	#if available.is_empty():
		#return randi() % GameData.active_color_palette.size()
	#
	#return available.pick_random()
#
#
#func _spawn_house_for_color(zone: Rect2i, color_id: int, scattered: bool) -> void:
	#"""Spawn a house of specific color, either scattered or near existing houses"""
	#var target_cell: Vector2i
	#
	#if scattered:
		## Spawn FAR from the workplace (routing challenge!)
		## Find the workplace of this color
		#var workplace_pos = Vector2i.ZERO
		#for building in GameData.building_grid.values():
			#if building is Workplace and building.color_id == color_id:
				#workplace_pos = building.entrance_cell
				#break
		#
		#if workplace_pos != Vector2i.ZERO:
			## Spawn on opposite side of map from workplace
			#var zone_center = Vector2i(
				#zone.position.x + zone.size.x / 2,
				#zone.position.y + zone.size.y / 2
			#)
			#var direction_from_center =Vector2(workplace_pos - zone_center).normalized()
			#var opposite_direction = -direction_from_center
			#
			## Spawn 15-25 cells away in opposite direction
			#var distance = randi_range(4, 8)
			#target_cell = zone_center + Vector2i(opposite_direction * distance)
			#
			#print("  → Scattering house FAR from workplace (dist: %d)" % distance)
		#else:
			## Fallback: random location
			#target_cell = Vector2i(
				#zone.position.x + randi_range(0, zone.size.x),
				#zone.position.y + randi_range(0, zone.size.y)
			#)
	#else:
		## Spawn near existing houses of this color (cluster)
		#var cluster_target = get_cluster_spawn_target(color_id)
		#if cluster_target != Vector2i.ZERO:
			#target_cell = cluster_target
			#print("  → Clustering near existing houses")
		#else:
			## Random location
			#target_cell = Vector2i(
				#zone.position.x + randi_range(0, zone.size.x),
				#zone.position.y + randi_range(0, zone.size.y)
			#)
	#
	#var success = spawn_building_with_color(house_scene, target_cell, zone, 8, color_id)
	#
	#if success:
		## Register to cluster
		#register_house_to_cluster(color_id, target_cell)
	#else:
		## Try wider variance
		#spawn_building_with_color(house_scene, target_cell, zone, 12, color_id)
#
#func process_backlog() -> void:
	#if all_houses.is_empty() or pending_requests.is_empty():
		#return
#
	## Loop backwards so we can safely remove satisfied requests
	#for i in range(pending_requests.size() - 1, -1, -1):
		#var requester = pending_requests[i] # This is the Workplace node
#
		## --- COLOR-BASED MATCHING ---
		## 1. Must match the workplace's color (Color match)
		## 2. Must be connected to roads (Connectivity check)
		## 3. Must have cars available (Capacity check)
		#var candidates = all_houses.filter(func(h):
			#return h.color_id == requester.color_id and h.is_connected_to_workplace and h.active_cars < h.max_cars
		#)
		#
		## If no houses of the right color are ready, skip this request for now
		#if candidates.is_empty():
			#continue
#
		## Sort specifically by distance to THIS requester
		#candidates.sort_custom(func(a, b):
			#return a.entrance_cell.distance_squared_to(requester.entrance_cell) < \
				   #b.entrance_cell.distance_squared_to(requester.entrance_cell)
		#)
#
		## Attempt dispatch from the closest valid house
		#var best_house = candidates[0]
		#if best_house.try_dispatch(requester.entrance_cell):
			#pending_requests.remove_at(i)
#
## =============================================================================
## WAVE-BASED SPAWN RHYTHM
## =============================================================================
#func _on_building_timer_timeout() -> void:
	#attempt_spawn()
	#
	## Use consistent spawn interval
	#building_timer.wait_time = BASE_SPAWN_INTERVAL
	#building_timer.start()
#
#
#func attempt_spawn() -> void:
	#var valid_spawn_zone = get_valid_spawn_zone()
	#if valid_spawn_zone.size == Vector2i.ZERO:
		#print("Director: No valid spawn zone available")
		#return
#
	#var elapsed_time = Time.get_ticks_msec() / 1000.0 - game_start_time
	#var current_workplace_count = get_workplace_count()
	#var current_house_count = all_houses.size()
	#
	## =================================================================
	## PHASE 1: STRUCTURED SCHEDULE (First 5 minutes)
	## Follow precise timeline with scattered same-color houses
	## =================================================================
	#if elapsed_time < STRUCTURED_PHASE_END:
		#print("\n=== STRUCTURED PHASE (%.1fs elapsed, Schedule: %d/%d) ===" % [
			#elapsed_time,
			#next_schedule_index,
			#SPAWN_SCHEDULE.size()
		#])
		#
		## Process all schedule items that are due
		#var spawned_something = false
		#while next_schedule_index < SPAWN_SCHEDULE.size():
			#var item = SPAWN_SCHEDULE[next_schedule_index]
			#
			## Check if it's time for this item
			#if elapsed_time >= item["time"]:
				#print("Director: ⏰ Processing schedule item %d: %s (%.1fs)" % [
					#next_schedule_index,
					#item["notes"],
					#item["time"]
				#])
				#
				#await _process_schedule_item(item, valid_spawn_zone)
				#next_schedule_index += 1
				#spawned_something = true
			#else:
				## Next item not ready yet
				#var wait_time = item["time"] - elapsed_time
				#print("Director: Next spawn in %.1fs: %s" % [wait_time, item["notes"]])
				#break
		#
		#if not spawned_something:
			#print("Director: Waiting for next schedule item...")
		#
		#return
	#
	## =================================================================
	## END OF STRUCTURED PHASE
	## =================================================================
	#if structured_phase_active:
		#structured_phase_active = false
		#print("\n=== STRUCTURED PHASE ENDED at %.1fs ===" % elapsed_time)
		#print("=== Switching to SCORE-BASED spawning ===")
	#
	## =================================================================
	## PHASE 2: SCORE-BASED SPAWNING (after 5 minutes)
	## =================================================================
	#var current_ratio = calculate_current_ratio()
	#
	#print("\n=== SCORE-BASED SPAWN ATTEMPT ===")
	#print("Houses: %d/%d | Workplaces: %d/%d | Ratio: %.2f | Target: %.2f" % [
		#current_house_count,
		#MAX_HOUSES,
		#current_workplace_count,
		#MAX_WORKPLACES,
		#current_ratio, 
		#TARGET_HOUSE_TO_WORKPLACE_RATIO
	#])
	#print("Pending colors: %s" % pending_workplace_colors)
	#print("Houses per pending: %s" % houses_per_pending_color)
#
	## Check if caps reached
	#if current_workplace_count >= MAX_WORKPLACES:
		#if current_house_count < MAX_HOUSES:
			#print("Director: MAX_WORKPLACES reached, spawning house")
			#_spawn_anticipatory_house(valid_spawn_zone)
		#return
	#
	#if current_house_count >= MAX_HOUSES:
		#print("Director: MAX_HOUSES reached, forcing workplace spawn")
		#var wp_decision = should_spawn_workplace()
		#if wp_decision["should_spawn"]:
			#await _spawn_workplace_for_color(valid_spawn_zone, wp_decision["color"], wp_decision["is_outlier"])
		#return
	#
	## Always-anticipatory logic
	#var wp_decision = should_spawn_workplace()
	#
	#if wp_decision["should_spawn"]:
		#print("Director: ⚡ WORKPLACE TRIGGER: %s (color: %d, outlier: %s)" % [
			#wp_decision["trigger"],
			#wp_decision["color"],
			#wp_decision["is_outlier"]
		#])
		#await _spawn_workplace_for_color(valid_spawn_zone, wp_decision["color"], wp_decision["is_outlier"])
	#else:
		#print("Director: Spawning anticipatory house")
		#_spawn_anticipatory_house(valid_spawn_zone)
#
#
## =============================================================================
## ALWAYS-ANTICIPATORY HOUSE SPAWNING
## Pick a color (prefer ones without workplace) and spawn a house
## =============================================================================
#func _spawn_anticipatory_house(zone: Rect2i) -> bool:
	## Pick which color to spawn house for
	#var target_color_id = pick_house_color()
	#
	## Track this color as pending if not already
	#if not (target_color_id in pending_workplace_colors):
		#pending_workplace_colors.append(target_color_id)
		#houses_per_pending_color[target_color_id] = 0
	#
	#houses_per_pending_color[target_color_id] += 1
	#
	#print("Director: Spawning anticipatory house for color %d (%d total for this color)" % [
		#target_color_id,
		#houses_per_pending_color[target_color_id]
	#])
	#
	## Try cluster-based spawn location
	#var cluster_target = get_cluster_spawn_target(target_color_id)
	#var target_cell: Vector2i
	#
	#if cluster_target != Vector2i.ZERO:
		#target_cell = cluster_target
		#print("  → Using cluster target: %s" % cluster_target)
	#else:
		## Random in zone (first house or new cluster)
		#target_cell = Vector2i(
			#zone.position.x + randi_range(0, zone.size.x),
			#zone.position.y + randi_range(0, zone.size.y)
		#)
	#
	#var success = spawn_building_with_color(house_scene, target_cell, zone, 6, target_color_id)
	#
	#if not success:
		#success = spawn_building_with_color(house_scene, target_cell, zone, 10, target_color_id)
	#
	#return success
#
#
#func pick_house_color() -> int:
	#"""Choose which color house to spawn (prefer colors without workplaces)"""
	#update_color_counts()
	#
	## Priority 1: Colors with NO workplace yet
	#var colors_without_workplace = []
	#for i in range(GameData.active_color_palette.size()):
		#if workplaces_per_color.get(i, 0) == 0:
			#colors_without_workplace.append(i)
	#
	#if not colors_without_workplace.is_empty():
		#return colors_without_workplace.pick_random()
	#
	## Priority 2: Color with fewest houses (balance demand)
	#var min_houses = INF
	#var best_color = 0
	#
	#for i in range(GameData.active_color_palette.size()):
		#var house_count = houses_per_color.get(i, 0)
		#if house_count < min_houses:
			#min_houses = house_count
			#best_color = i
	#
	#return best_color
#
#
#func _spawn_workplace_for_color(zone: Rect2i, color_id: int, is_outlier: bool) -> void:
	#"""Spawn a workplace of specific color (normal or outlier)"""
	#var success = false
	#
	#if is_outlier:
		## Spawn far away (outlier for WP4/WP5)
		#success = await _spawn_chaos_outlier_workplace_with_color(zone, color_id)
	#else:
		## Normal workplace placement
		#success = await _spawn_workplace_with_color(zone, color_id)
	#
	#if success:
		## Remove from pending queue
		#if color_id in pending_workplace_colors:
			#pending_workplace_colors.erase(color_id)
		#houses_per_pending_color.erase(color_id)
		#
		#workplaces_spawned_count += 1
		#
		#print("Director: ✓ Workplace (color %d) spawned! Houses are ready to deliver." % color_id)
	#else:
		#print("Director: ❌ Workplace spawn failed")
		#GameData.increase_map_size()
		#dynamic_workplace_isolation = max(MIN_WORKPLACE_ISOLATION, dynamic_workplace_isolation - 1)
#func _spawn_house_near_workplace(zone: Rect2i) -> bool:
	#"""Spawn a house using intelligent color selection and clustering"""
	#var workplaces: Array[Node2D] = []
	#for building in GameData.building_grid.values():
		#if building is Workplace:
			#if not (building in workplaces):  # Deduplicate
				#workplaces.append(building)
#
	#var target_color_id: int = -1
	#var spawn_near_workplace: Workplace = null
	#
	## PRIORITY 1: Serve pending workplace colors (anticipatory houses)
	#if not pending_workplace_colors.is_empty():
		#var oldest_pending = pending_workplace_colors[0]
		#var houses_for_color = houses_spawned_for_pending.get(oldest_pending, 0)
		#
		#if houses_for_color < HOUSES_BEFORE_WORKPLACE:
			#target_color_id = oldest_pending
			#houses_spawned_for_pending[oldest_pending] = houses_for_color + 1
			#print("Director: Spawning anticipatory house %d/%d for pending color %d" % [
				#houses_for_color + 1,
				#HOUSES_BEFORE_WORKPLACE,
				#target_color_id
			#])
		#else:
			#print("Director: Color %d has enough anticipatory houses (%d), spawning for other colors" % [
				#oldest_pending,
				#houses_for_color
			#])
	#
	## PRIORITY 2: Support recently spawned workplace
	#if target_color_id == -1 and last_workplace_color != -1:
		#target_color_id = last_workplace_color
		#last_workplace_color = -1
		#
		#for wp in workplaces:
			#if wp.color_id == target_color_id:
				#spawn_near_workplace = wp
				#break
		#
		#print("Director: Spawning support house for recently spawned workplace (color_id: %d)" % target_color_id)
	#
	## PRIORITY 3: Spawn for underserved existing workplaces
	#if target_color_id == -1 and not workplaces.is_empty():
		#update_color_counts()
		#var min_house_count = INF
		#
		#for wp in workplaces:
			#var wp_color = wp.color_id
			#var house_count = houses_per_color.get(wp_color, 0)
			#if house_count < min_house_count:
				#min_house_count = house_count
				#target_color_id = wp_color
				#spawn_near_workplace = wp
		#
		#print("Director: Spawning house for underserved workplace color %d (%d houses exist)" % [
			#target_color_id,
			#min_house_count
		#])
	#
	## PRIORITY 4: Start new anticipatory sequence
	#if target_color_id == -1:
		#var available_colors = []
		#for i in range(GameData.active_color_palette.size()):
			#if not (i in pending_workplace_colors):
				#available_colors.append(i)
		#
		#if available_colors.is_empty():
			#target_color_id = randi() % GameData.active_color_palette.size()
		#else:
			#target_color_id = available_colors.pick_random()
		#
		#pending_workplace_colors.append(target_color_id)
		#houses_spawned_for_pending[target_color_id] = 1
		#
		#print("Director: Starting anticipatory sequence for color %d (1/%d houses)" % [
			#target_color_id,
			#HOUSES_BEFORE_WORKPLACE
		#])
	#
	## Determine spawn location using clustering system
	#var target_cell: Vector2i
	#var cluster_target = get_cluster_spawn_target(target_color_id)
	#
	#if cluster_target != Vector2i.ZERO:
		## Spawn near existing houses of same color
		#target_cell = cluster_target
		#print("Director: Using cluster spawn near %s" % cluster_target)
	#elif spawn_near_workplace:
		## Spawn near workplace
		#target_cell = get_house_spawn_near_workplace(spawn_near_workplace, zone)
	#else:
		## Random location (first house of this color)
		#var zone_center = Vector2i(
			#zone.position.x + zone.size.x / 2,
			#zone.position.y + zone.size.y / 2
		#)
		#target_cell = zone_center
	#
	#var success = spawn_building_with_color(house_scene, target_cell, zone, HOUSE_CLUSTER_VARIANCE, target_color_id)
	#
	#if not success:
		#print("Director: House spawn failed, trying wider area")
		#success = spawn_building_with_color(house_scene, target_cell, zone, HOUSE_CLUSTER_VARIANCE * 2, target_color_id)
	#
	#return success
#
#
#func get_house_spawn_near_workplace(workplace: Workplace, zone: Rect2i) -> Vector2i:
	#"""Find a good spot for a house near a workplace, avoiding entrance blockage"""
	#var entrance = workplace.entrance_cell
	#
	## Find entrance direction by checking which cells belong to the workplace
	#var workplace_cells = []
	#for cell in GameData.building_grid.keys():
		#if GameData.building_grid[cell] == workplace:
			#workplace_cells.append(cell)
	#
	## Calculate workplace center
	#var center = Vector2i(0, 0)
	#for cell in workplace_cells:
		#center += cell
	#center /= workplace_cells.size()
	#
	## Entrance direction = from center to entrance
	#var entrance_dir = (entrance - center).sign()
	#
	## AVOID spawning in front of entrance (minimum 3 cells away in entrance direction)
	## Instead, spawn to the SIDES or BEHIND the workplace
	#
	#var safe_directions = [
		#Vector2i(entrance_dir.y, entrance_dir.x),    # Perpendicular right
		#Vector2i(-entrance_dir.y, -entrance_dir.x),  # Perpendicular left
		#Vector2i(-entrance_dir.x, -entrance_dir.y),  # Behind
	#]
	#
	#var offset_distance = randi_range(4, 6)
	#var chosen_dir = safe_directions.pick_random()
	#
	#return entrance + (chosen_dir * offset_distance)
#
#
#func update_color_counts() -> void:
	#"""Count how many houses and workplaces exist per color"""
	#houses_per_color.clear()
	#workplaces_per_color.clear()
	#
	## Count workplaces
	#for building in GameData.building_grid.values():
		#if building is Workplace:
			#var color = building.color_id
			#workplaces_per_color[color] = workplaces_per_color.get(color, 0) + 1
	#
	## Count houses
	#for house in all_houses:
		#var color = house.color_id
		#houses_per_color[color] = houses_per_color.get(color, 0) + 1
#
#
## =============================================================================
## WORKPLACE SPAWNING WITH OUTLIER LOGIC
## =============================================================================
#func _spawn_workplace(zone: Rect2i, current_workplace_count: int) -> bool:
	## Priority 1: Spawn workplace for oldest pending color (houses are waiting!)
	#if not pending_workplace_colors.is_empty():
		#var target_color = pending_workplace_colors[0]
		#var houses_ready = houses_spawned_for_pending.get(target_color, 0)
		#
		#if houses_ready >= HOUSES_BEFORE_WORKPLACE:
			#print("Director: Spawning workplace for pending color %d (%d houses waiting)" % [target_color, houses_ready])
			#
			## Remove from pending queue
			#pending_workplace_colors.remove_at(0)
			#houses_spawned_for_pending.erase(target_color)
			#
			## Spawn workplace with specific color
			#var success = await _spawn_workplace_with_color(zone, target_color)
			#
			#if success:
				#last_workplace_color = target_color  # Mark for support houses
			#
			#return success
	#
	## Priority 2: Standard workplace spawn (random color)
	## Every N workplaces, create an outlier for map coverage
	#var is_outlier = (current_workplace_count % OUTLIER_EVERY_N_WORKPLACES == 0) and current_workplace_count > 0
#
	#if is_outlier:
		#print("Director: Attempting OUTLIER workplace spawn")
		#return await _spawn_outlier_workplace(zone)
	#else:
		#print("Director: Attempting standard workplace spawn")
		#return await _spawn_random_workplace(zone)
#
#
#func _spawn_workplace_with_color(zone: Rect2i, color_id: int) -> bool:
	#"""Spawn a workplace with a specific color"""
	## Use the standard random workplace logic but with forced color
	#var mid_x = zone.position.x + zone.size.x / 2
	#var mid_y = zone.position.y + zone.size.y / 2
	#
	## Count buildings in each quadrant
	#var quadrant_counts = {
		#"NW": 0, "NE": 0, "SW": 0, "SE": 0
	#}
	#
	#for cell in GameData.building_grid.keys():
		#if zone.has_point(cell):
			#if cell.x < mid_x:
				#if cell.y < mid_y:
					#quadrant_counts["NW"] += 1
				#else:
					#quadrant_counts["SW"] += 1
			#else:
				#if cell.y < mid_y:
					#quadrant_counts["NE"] += 1
				#else:
					#quadrant_counts["SE"] += 1
	#
	## Find emptiest quadrant
	#var emptiest = "NW"
	#for q in quadrant_counts:
		#if quadrant_counts[q] < quadrant_counts[emptiest]:
			#emptiest = q
	#
	## Calculate target center for that quadrant
	#var target: Vector2i
	#match emptiest:
		#"NW":
			#target = Vector2i(zone.position.x + zone.size.x / 4, zone.position.y + zone.size.y / 4)
		#"NE":
			#target = Vector2i(mid_x + zone.size.x / 4, zone.position.y + zone.size.y / 4)
		#"SW":
			#target = Vector2i(zone.position.x + zone.size.x / 4, mid_y + zone.size.y / 4)
		#"SE":
			#target = Vector2i(mid_x + zone.size.x / 4, mid_y + zone.size.y / 4)
		#_:
			#target = Vector2i(mid_x, mid_y)
	#
	#var max_variance = max(min(zone.size.x, zone.size.y) / 2, 6)
	#
	#print("  → Spawning workplace with color_id %d at %s" % [color_id, target])
	#
	#var success = spawn_building_with_color(workplace_scene, target, zone, max_variance, color_id)
	#
	#if success:
		#await get_tree().process_frame
		#_track_last_workplace_color()
	#
	#return success
#
#
#func _spawn_outlier_workplace(zone: Rect2i) -> bool:
	## Push workplace far from center to encourage map expansion
	#var zone_center = Vector2i(
		#zone.position.x + zone.size.x / 2,
		#zone.position.y + zone.size.y / 2
	#)
#
	#var dist = randi_range(OUTLIER_MIN_DIST, OUTLIER_MAX_DIST)
	#var directions = [
		#Vector2i(dist, randi_range(-dist / 2, dist / 2)),   # right
		#Vector2i(-dist, randi_range(-dist / 2, dist / 2)),  # left
		#Vector2i(randi_range(-dist / 2, dist / 2), dist),   # down
		#Vector2i(randi_range(-dist / 2, dist / 2), -dist),  # up
	#]
	#var target = zone_center + directions.pick_random()
#
	#if spawn_building_near(workplace_scene, target, zone, 8):
		#print("Director: OUTLIER workplace spawned near ", target)
		## Track the color of this new workplace
		#await get_tree().process_frame
		#_track_last_workplace_color()
		#return true
	#else:
		#print("Director: Outlier failed, falling back to random workplace")
		#return await _spawn_random_workplace(zone)
#
#
#func _spawn_chaos_outlier_workplace(zone: Rect2i) -> bool:
	#"""Spawn an outlier VERY far away when game is too calm"""
	#var zone_center = Vector2i(
		#zone.position.x + zone.size.x / 2,
		#zone.position.y + zone.size.y / 2
	#)
	#
	## Much further than standard outliers
	#var dist = randi_range(OUTLIER_MAX_DIST + 5, OUTLIER_MAX_DIST + 15)
	#var directions = [
		#Vector2i(dist, randi_range(-dist / 3, dist / 3)),
		#Vector2i(-dist, randi_range(-dist / 3, dist / 3)),
		#Vector2i(randi_range(-dist / 3, dist / 3), dist),
		#Vector2i(randi_range(-dist / 3, dist / 3), -dist),
	#]
	#var target = zone_center + directions.pick_random()
	#
	#print("Director: 🌪️ CHAOS OUTLIER target: %s (dist: %d)" % [target, dist])
	#
	#if spawn_building_near(workplace_scene, target, zone, 10):
		#print("Director: 🌪️ CHAOS OUTLIER spawned successfully!")
		#await get_tree().process_frame
		#_track_last_workplace_color()
		#return true
	#else:
		#print("Director: Chaos outlier failed, expanding map")
		#GameData.increase_map_size()
		#return false
#
#
#func _spawn_chaos_outlier_workplace_with_color(zone: Rect2i, color_id: int) -> bool:
	#"""Spawn a chaos outlier with specific color"""
	#var zone_center = Vector2i(
		#zone.position.x + zone.size.x / 2,
		#zone.position.y + zone.size.y / 2
	#)
	#
	#var dist = randi_range(OUTLIER_MAX_DIST + 5, OUTLIER_MAX_DIST + 15)
	#var directions = [
		#Vector2i(dist, randi_range(-dist / 3, dist / 3)),
		#Vector2i(-dist, randi_range(-dist / 3, dist / 3)),
		#Vector2i(randi_range(-dist / 3, dist / 3), dist),
		#Vector2i(randi_range(-dist / 3, dist / 3), -dist),
	#]
	#var target = zone_center + directions.pick_random()
	#
	#print("Director: 🌪️ CHAOS OUTLIER (color %d) target: %s (dist: %d)" % [color_id, target, dist])
	#
	#if spawn_building_with_color(workplace_scene, target, zone, 10, color_id):
		#print("Director: 🌪️ CHAOS OUTLIER spawned!")
		#await get_tree().process_frame
		#return true
	#else:
		#print("Director: Chaos outlier failed")
		#GameData.increase_map_size()
		#return false
#
#
#func _spawn_random_workplace(zone: Rect2i) -> bool:
	## SMART PLACEMENT: Try to find areas with fewer buildings first
	## Divide zone into quadrants and pick the emptiest one
	#
	#var mid_x = zone.position.x + zone.size.x / 2
	#var mid_y = zone.position.y + zone.size.y / 2
	#
	## Count buildings in each quadrant
	#var quadrant_counts = {
		#"NW": 0, "NE": 0, "SW": 0, "SE": 0
	#}
	#
	#for cell in GameData.building_grid.keys():
		#if zone.has_point(cell):
			#if cell.x < mid_x:
				#if cell.y < mid_y:
					#quadrant_counts["NW"] += 1
				#else:
					#quadrant_counts["SW"] += 1
			#else:
				#if cell.y < mid_y:
					#quadrant_counts["NE"] += 1
				#else:
					#quadrant_counts["SE"] += 1
	#
	## Find emptiest quadrant
	#var emptiest = "NW"
	#for q in quadrant_counts:
		#if quadrant_counts[q] < quadrant_counts[emptiest]:
			#emptiest = q
	#
	## Calculate target center for that quadrant
	#var target: Vector2i
	#match emptiest:
		#"NW":
			#target = Vector2i(zone.position.x + zone.size.x / 4, zone.position.y + zone.size.y / 4)
		#"NE":
			#target = Vector2i(mid_x + zone.size.x / 4, zone.position.y + zone.size.y / 4)
		#"SW":
			#target = Vector2i(zone.position.x + zone.size.x / 4, mid_y + zone.size.y / 4)
		#"SE":
			#target = Vector2i(mid_x + zone.size.x / 4, mid_y + zone.size.y / 4)
		#_:
			#target = Vector2i(mid_x, mid_y)
	#
	## Use larger variance for 3×3 workplaces - they need more space to find a spot
	## With isolation=2, workplaces need 7×7 cells, so we need to search widely
	#var max_variance = max(min(zone.size.x, zone.size.y) / 2, 6)  # At least 6 cells variance
	#
	#print("  → _spawn_random_workplace: targeting %s quadrant at %s (variance=%d)" % [emptiest, target, max_variance])
	#print("  → Quadrant densities: NW=%d, NE=%d, SW=%d, SE=%d" % [
		#quadrant_counts["NW"], quadrant_counts["NE"], 
		#quadrant_counts["SW"], quadrant_counts["SE"]
	#])
	#print("  → Workplace needs %d×%d cells (isolation=%d)" % [
		#3 + 2 * dynamic_workplace_isolation,
		#3 + 2 * dynamic_workplace_isolation,
		#dynamic_workplace_isolation
	#])
	#
	#var success = spawn_building_near(workplace_scene, target, zone, max_variance)
	#if success:
		## Track the color of this new workplace
		#await get_tree().process_frame
		#_track_last_workplace_color()
	#return success
#
#
#func _track_last_workplace_color() -> void:
	#"""Find the most recently spawned workplace and store its color"""
	#var newest_workplace: Workplace = null
	#for building in GameData.building_grid.values():
		#if building is Workplace:
			#if not newest_workplace or building.time_alive < 0.5:  # Just spawned
				#newest_workplace = building
	#
	#if newest_workplace:
		#last_workplace_color = newest_workplace.color_id
		#print("Director: Tracking new workplace color_id: %d" % last_workplace_color)
#
#
## =============================================================================
## SPAWN HELPERS
## =============================================================================
#func spawn_building_near(scene: PackedScene, target: Vector2i, zone: Rect2i, variance: int) -> bool:
	#var b = scene.instantiate()
	#var b_size = b.grid_size
	#var is_wp = b is Workplace
#
	## Scale attempts with variance
	#var attempts = clampi(variance * 2, 1, 10)
	#
	#var building_type = "Workplace" if is_wp else "House"
	#print("  → spawn_building_near: %s | target=%s | variance=%d | attempts=%d" % [building_type, target, variance, attempts])
#
	#for attempt in range(attempts):
		#var rand_offset = Vector2i(randi_range(-variance, variance), randi_range(-variance, variance))
		#var cell = target + rand_offset
#
		#if is_area_clear(cell, b_size, zone, is_wp):
			#finalize_building_spawn(b, cell)
			#print("  → ✓ %s spawned at %s (attempt %d/%d)" % [building_type, cell, attempt + 1, attempts])
			#return true
		#else:
			#if attempt < 3 or attempt == attempts - 1:  # Log first 3 and last attempt
				#print("  → ✗ Cell %s blocked (attempt %d/%d)" % [cell, attempt + 1, attempts])
#
	#b.queue_free()
	#print("  → ❌ %s spawn FAILED after %d attempts" % [building_type, attempts])
	#return false
#
#
#func spawn_building_with_color(scene: PackedScene, target: Vector2i, zone: Rect2i, variance: int, color_id: int) -> bool:
	#"""Spawn a building with a specific color (used for houses and workplaces)"""
	#var b = scene.instantiate()
	#var b_size = b.grid_size
	#var is_wp = b is Workplace
#
	## Scale attempts with variance
	#var attempts = clampi(variance * 2, 1, 10)
	#
	#var building_type = "Workplace" if is_wp else "House"
	#print("  → spawn_building_with_color: %s (color_id: %d) | target=%s | variance=%d | attempts=%d" % [building_type, color_id, target, variance, attempts])
#
	#for attempt in range(attempts):
		#var rand_offset = Vector2i(randi_range(-variance, variance), randi_range(-variance, variance))
		#var cell = target + rand_offset
#
		#if is_area_clear(cell, b_size, zone, is_wp):
			## Set the color BEFORE finalizing spawn
			#var color_data = GameData.active_color_palette[color_id]
			#b.set_building_color(color_data, color_id)
			#
			#finalize_building_spawn(b, cell)
			#print("  → ✓ %s (color_id: %d) spawned at %s (attempt %d/%d)" % [building_type, color_id, cell, attempt + 1, attempts])
			#return true
		#else:
			#if attempt < 3 or attempt == attempts - 1:  # Log first 3 and last attempt
				#print("  → ✗ Cell %s blocked (attempt %d/%d)" % [cell, attempt + 1, attempts])
#
	#b.queue_free()
	#print("  → ❌ %s (color_id: %d) spawn FAILED after %d attempts" % [building_type, color_id, attempts])
	#return false
#
#
#func finalize_building_spawn(b: Node2D, cell: Vector2i) -> void:
	#var origin = Vector2(cell) * 64.0
	#var offset = (Vector2(b.grid_size) * 64.0) / 2.0
#
	#b.position = origin + offset
	#
	## Random rotation in 4 cardinal directions (0°, 90°, 180°, 270°)
	#var rotations = [0, PI/2, PI, 3*PI/2]
	#b.rotation = rotations.pick_random()
	#
	#$"../Entities".add_child(b)
#
	#if b is House:
		#all_houses.append(b)
		#b.tree_exited.connect(func(): all_houses.erase(b))
		#
		## Track house location for clustering
		#if b.color_id != -1:
			#register_house_to_cluster(b.color_id, cell)
#
	#SignalBus.map_changed.emit.call_deferred()
#
#
#func is_area_clear(start_cell: Vector2i, size: Vector2i, constraint_rect: Rect2i, is_workplace: bool) -> bool:
	#var building_rect = Rect2i(start_cell, size)
	#if not constraint_rect.encloses(building_rect):
		#if is_workplace and size.x > 1:  # Only log for multi-cell workplaces
			#print("    ✗ Workplace footprint %s not enclosed by constraint %s" % [building_rect, constraint_rect])
		#return false
#
	## MINI MOTORWAYS COLLISION LOGIC:
	## 
	## For WORKPLACES (3x3):
	##   - Must maintain isolation distance from OTHER workplaces (dynamic_workplace_isolation)
	##   - Can be near houses (houses don't block workplaces beyond footprint)
	##   - Total area needed: (3 + 2×isolation) × (3 + 2×isolation)
	##     With isolation=2: 7×7 cells = 448×448 pixels
	##     With isolation=1: 5×5 cells = 320×320 pixels
	## 
	## For HOUSES (1x1):
	##   - Only need immediate footprint clear (radius 1)
	##   - Total area needed: 3×3 cells = 192×192 pixels
	##   - Can cluster near workplaces
	#
	#if is_workplace:
		## Workplace clearance check
		## Check the isolation radius for OTHER workplaces
		#for x in range(-dynamic_workplace_isolation, size.x + dynamic_workplace_isolation):
			#for y in range(-dynamic_workplace_isolation, size.y + dynamic_workplace_isolation):
				#var check_cell = start_cell + Vector2i(x, y)
				#
				#if GameData.building_grid.has(check_cell):
					#var existing = GameData.building_grid[check_cell]
					## Only block if there's another workplace nearby
					#if existing is Workplace:
						#if size.x > 1:  # Log for workplaces
							#print("    ✗ Another workplace at %s blocks spawn at %s (isolation=%d)" % [check_cell, start_cell, dynamic_workplace_isolation])
						#return false
		#
		## Check immediate footprint + 1 cell buffer for any buildings (can't overlap with houses)
		#for x in range(-1, size.x + 1):
			#for y in range(-1, size.y + 1):
				#var check_cell = start_cell + Vector2i(x, y)
				#if GameData.building_grid.has(check_cell):
					#if size.x > 1:  # Log for workplaces
						#print("    ✗ Building at %s blocks workplace footprint at %s" % [check_cell, start_cell])
					#return false
				#if GameData.road_grid.has(check_cell):
					#if size.x > 1:  # Log for workplaces
						#print("    ✗ Road at %s blocks workplace footprint at %s" % [check_cell, start_cell])
					#return false
	#else:
		## House clearance check
		#
		## CRITICAL: Check if house would block a workplace entrance
		## Scan nearby cells for workplace entrances and reject if too close
		#const ENTRANCE_SAFE_DISTANCE = 3  # Houses must be 3+ cells from any workplace entrance
		#
		#for x_offset in range(-ENTRANCE_SAFE_DISTANCE, ENTRANCE_SAFE_DISTANCE + 1):
			#for y_offset in range(-ENTRANCE_SAFE_DISTANCE, ENTRANCE_SAFE_DISTANCE + 1):
				#var check_cell = start_cell + Vector2i(x_offset, y_offset)
				#
				## Check if this cell is a workplace entrance
				#if GameData.building_grid.has(check_cell):
					#var building = GameData.building_grid[check_cell]
					#if building is Workplace and building.entrance_cell == check_cell:
						#print("    ✗ House at %s would block workplace entrance at %s (within %d cells)" % [
							#start_cell,
							#check_cell,
							#ENTRANCE_SAFE_DISTANCE
						#])
						#return false
		#
		## 80% chance: tight packing (no moat) - just check the exact footprint
		## 20% chance: standard moat spacing
		#var use_tight_packing = randf() < 0.8
		#
		#if use_tight_packing:
			## Tight packing: only check the exact footprint (no buffer)
			#for x in range(0, size.x):
				#for y in range(0, size.y):
					#var check_cell = start_cell + Vector2i(x, y)
					#
					## Can't overlap with other buildings
					#if GameData.building_grid.has(check_cell):
						#return false
					## Can't overlap with roads
					#if GameData.road_grid.has(check_cell):
						#return false
		#else:
			## Standard spacing: check with 1-cell moat
			#for x in range(-1, size.x + 1):
				#for y in range(-1, size.y + 1):
					#var check_cell = start_cell + Vector2i(x, y)
					#
					## Houses blocked by ANY building in immediate vicinity
					#if GameData.building_grid.has(check_cell):
						#return false
					## And by roads
					#if GameData.road_grid.has(check_cell):
						#return false
#
	#return true
#
#
## =============================================================================
## MAP EXPANSION — density-reactive
## =============================================================================
#func _on_temporary_map_timer_timeout() -> void:
	#var map_rect = GameData.current_map_size
	#var total_cells = max(map_rect.size.x * map_rect.size.y, 1)
	#var density = float(GameData.building_grid.size()) / float(total_cells)
#
	## Dense map expands sooner; sparse map waits longer
	#map_timer.wait_time = lerp(30.0, 90.0, density)
#
	#print("=== MAP EXPANDING === density=%.2f next_expansion_in=%.1fs" % [density, map_timer.wait_time])
	#GameData.increase_map_size()
	#print("New map size: ", GameData.current_map_size)
#
	#if Time.get_ticks_msec() / 1000.0 >= 1200:
		#map_timer.stop()
		#print("Director: Map reached expansion time limit")
