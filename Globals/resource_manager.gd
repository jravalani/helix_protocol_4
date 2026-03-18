extends Node

signal resources_updated(tiles: int, data: int, reserve: int) # The "Messenger"

func _ready():
	# Emit initial values so UI starts correct
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI

func spend_tile() -> bool:
	if GameData.current_pipe_count > 0:
		GameData.current_pipe_count -= 1
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		return true
	return false

func refund_tile() -> void:
	GameData.current_pipe_count += 1
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI

func add_score() -> void:
	GameData.total_data += 1
	GameData.lifetime_data_earned += 1
	if GameData.lifetime_data_earned >= GameData.score_to_next_reward:
		grant_reward()
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI

func grant_reward() -> void:
	GameData.current_pipe_count += 6
	
	# Calculate current gap and grow it
	var growth_factor = 1.2  # 20% increase each time
	var current_gap = GameData.score_to_next_reward - GameData.previous_threshold
	
	GameData.previous_threshold = GameData.score_to_next_reward
	GameData.score_to_next_reward += int(current_gap * growth_factor)
	
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
#region pipe upgrades
func upgrade_pipes() -> bool:
	if GameData.current_pipe_upgrade_level >= GameData.MAX_PIPE_UPGRADES:
		# have a 'maxed out' logo on the button; lock the button
		NotificationManager.notify("Pipe network is fully upgraded.", NotificationManager.Type.WARNING, "PIPES MAXED")
		return false
	
	var cost = GameData.PIPE_UPGRADE_COSTS[GameData.current_pipe_upgrade_level]
	
	if GameData.total_data >= cost:
		GameData.total_data -= cost
		GameData.current_pipe_upgrade_level += 1
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		# send a global signal here.
		SignalBus.pipes_upgraded.emit(GameData.current_pipe_upgrade_level)
		return true
	else:
		NotificationManager.notify("Insufficient data to upgrade pipes. Need " + str(cost) + ".", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")
	return false
#endregion

#region hull shield upgrades
func upgrade_hull_shield() -> bool:
	if GameData.current_hull_shield_level >= GameData.MAX_HULL_SHIELD_UPGRADES:
		# maxed out
		NotificationManager.notify("Hull shield is at maximum capacity.", NotificationManager.Type.WARNING, "SHIELD MAXED")
		return false
	
	var cost = GameData.HULL_SHIELD_UPGRADE_COSTS[GameData.current_hull_shield_level]
	
	if GameData.total_data >= cost:
		GameData.total_data -= cost
		GameData.current_hull_shield_level += 1
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		# if in future there need be a signal or anythin implement here.
		return true
	else:
		NotificationManager.notify("Insufficient data to upgrade shield. Need " + str(cost) + ".", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")
	return false
#endregion

#region reinforce
func reinforce_zone(zone_id: int) -> void:
	var cost = GameData.ZONE_REINFORCE_COSTS[zone_id]
	var final_cost = cost
	
	if GameData.current_reinforced_zone != -1 and GameData.current_reinforced_zone != zone_id:
		final_cost = cost * 1.5
		NotificationManager.notify("Zone switch penalty applied. Cost increased by 50%.", NotificationManager.Type.WARNING, "ZONE TAX")
	
	if GameData.total_data >= final_cost:
		GameData.total_data -= final_cost
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		clear_zone_reinforcement(GameData.current_reinforced_zone)
		await get_tree().process_frame
		reinforce_pipes(zone_id)
	else:
		NotificationManager.notify("Insufficient data to reinforce " + GameData.Zone.keys()[zone_id] + " zone.", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")

func reinforce_pipes(zone_id: int) -> void:
	GameData.reinforcement_version += 1
	var my_version = GameData.reinforcement_version
	GameData.current_reinforced_zone = zone_id
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if pipe.my_zone == zone_id:
			pipe.reinforce()
	
	NotificationManager.notify(GameData.Zone.keys()[zone_id] + " zone reinforced for 180 seconds.", NotificationManager.Type.INFO, "ZONE REINFORCED")

	GameData.active_reinforcement_timer = get_tree().create_timer(180.0)
	
	GameData.active_reinforcement_timer.timeout.connect(_on_reinforcement_timer_timeout.bind(zone_id, my_version))

func _on_reinforcement_timer_timeout(zone_id: int, version: int) -> void:
	if GameData.current_reinforced_zone == zone_id and GameData.reinforcement_version == version:
		clear_zone_reinforcement(zone_id)
		GameData.current_reinforced_zone = -1
		GameData.active_reinforcement_timer = null
		NotificationManager.notify(GameData.Zone.keys()[zone_id] + " zone reinforcement has expired.", NotificationManager.Type.WARNING, "REINFORCEMENT EXPIRED")

func clear_zone_reinforcement(zone_id) -> void:
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid.get(cell)
		
		if pipe.my_zone == zone_id:
			pipe.remove_reinforcement()

#func repair_zone(zone_id: int) -> void:
	#var cost = GameData.ZONE_REPAIR_COSTS[zone_id]
	#
	#if GameData.total_data >= cost:
		#GameData.total_data -= cost
		#execute_mass_repairs(zone_id)
	#else:
		#print("Insufficient Data.")
#
#func execute_mass_repairs(zone_id: int) -> void:
	#for cell in GameData.road_grid:
		#var pipe = GameData.road_grid.get(cell)
		#if pipe.my_zone == zone_id:
			#pipe.repair()
#endregion

#region repairs
func reserve_data_for_auto_repairs() -> void:
	if GameData.total_data >= 100:
		GameData.data_reserve_for_auto_repairs += 100
		GameData.total_data -= 100
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
	else:
		NotificationManager.notify("Insufficient data to reserve for auto-repairs. Need 100.", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")

func process_auto_repair() -> void:
	if not GameData.auto_repair_enabled or GameData.fractured_pipes.is_empty():
		return
	
	var repair_cost = GameData.SINGLE_PIPE_REPAIR_COST * 1.1
	var cells_to_fix = GameData.fractured_pipes.keys()
	
	for cell in cells_to_fix:
		if GameData.data_reserve_for_auto_repairs >= repair_cost:
			var pipe = GameData.fractured_pipes[cell]
			
			GameData.data_reserve_for_auto_repairs -= repair_cost
			pipe.repair()
			
			resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
		else:
			NotificationManager.notify("Auto-repair reserve depleted. Refill to continue repairs.", NotificationManager.Type.WARNING, "REPAIR RESERVE EMPTY")
			break
#endregion

#region hub upgrades
func upgrade_hub(hub: Hub) -> bool:
	if hub.upgrade_level >= GameData.MAX_HUB_UPGRADES:
		NotificationManager.notify("This hub is fully upgraded.", NotificationManager.Type.WARNING, "HUB MAXED")
		return false

	var cost = GameData.HUB_UPGRADE_COSTS[hub.upgrade_level]

	if GameData.total_data >= cost:
		GameData.total_data -= cost
		hub.upgrade_level += 1
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
		NotificationManager.notify("Hub upgraded to level " + str(hub.upgrade_level) + ".", NotificationManager.Type.INFO, "HUB UPGRADED")
		return true
	else:
		NotificationManager.notify("Insufficient data to upgrade hub. Need " + str(cost) + ".", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")
		return false
#endregion

func refund_hub() -> void:
	GameData.total_data += GameData.current_hub_spawn_cost - GameData.HUB_SPAWN_COST_INCREMENT
	GameData.current_hub_spawn_cost -= GameData.HUB_SPAWN_COST_INCREMENT
	GameData.current_hub_count -= 1
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)

#region building spawns
func spawn_hub() -> bool:
	var stage_cap: int = GameData.HUB_CAP_PER_STAGE.get(GameData.current_stage, GameData.MAX_HUBS)
	
	if GameData.current_hub_count >= stage_cap:
		if GameData.current_stage < 3:
			NotificationManager.notify(
				"Hub limit reached. Upgrade rocket to expand territory. Next limit: " + 
				str(GameData.HUB_CAP_PER_STAGE.get(GameData.current_stage + 1, GameData.MAX_HUBS)),
				NotificationManager.Type.WARNING, "HUB CAP"
			)
		else:
			NotificationManager.notify("Maximum hub capacity reached.", NotificationManager.Type.WARNING, "HUB CAP")
		return false
	
	if GameData.total_data < GameData.current_hub_spawn_cost:
		NotificationManager.notify("Insufficient data to deploy hub. Need " + str(GameData.current_hub_spawn_cost) + ".", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")
		return false
	
	GameData.total_data -= GameData.current_hub_spawn_cost
	GameData.current_hub_spawn_cost += GameData.HUB_SPAWN_COST_INCREMENT
	GameData.current_hub_count += 1
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
	
	SignalBus.spawn_hub_requested.emit()
	return true

func spawn_vent() -> bool:
	if GameData.current_vent_count >= GameData.MAX_VENTS:
		NotificationManager.notify("Maximum vent capacity reached.", NotificationManager.Type.WARNING, "VENT CAP")
		return false
	
	if GameData.total_data < GameData.current_vent_spawn_cost:
		NotificationManager.notify("Insufficient data to deploy vent. Need " + str(GameData.current_vent_spawn_cost) + ".", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")
		return false
	
	GameData.total_data -= GameData.current_vent_spawn_cost
	GameData.current_vent_spawn_cost += GameData.VENT_SPAWN_COST_INCREMENT
	GameData.current_vent_count += 1
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
	
	SignalBus.spawn_vent_requested.emit()
	return true

#endregion
func upgrade_rocket_phase() -> bool:
	var next_phase = GameData.current_rocket_phase + 1
	
	if not GameData.ROCKET_UPGRADES.has(next_phase):
		NotificationManager.notify("Rocket is fully upgraded. Prepare for launch.", NotificationManager.Type.INFO, "ROCKET MAXED")
		return false
	
	var data = GameData.ROCKET_UPGRADES[next_phase]
	var cost = data["cost"]
	
	if GameData.total_data >= cost:
		GameData.total_data -= cost
		GameData.current_rocket_phase = next_phase
		
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		
		SignalBus.rocket_segment_purchased.emit(GameData.current_rocket_phase)
		
		NotificationManager.notify("Rocket upgraded: " + data["name"] + ".", NotificationManager.Type.INFO, "ROCKET UPGRADED")
		return true
	else:
		NotificationManager.notify("Insufficient data to upgrade rocket. Need " + str(cost) + ".", NotificationManager.Type.WARNING, "INSUFFICIENT DATA")
		return false
#endregion
