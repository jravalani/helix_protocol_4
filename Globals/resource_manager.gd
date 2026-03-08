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
	if GameData.total_data >= GameData.score_to_next_reward:
		grant_reward()
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI

func grant_reward() -> void:
	GameData.current_pipe_count += 5
	GameData.score_to_next_reward += 30
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI

#region pipe upgrades
func upgrade_pipes() -> bool:
	if GameData.current_pipe_upgrade_level >= GameData.MAX_PIPE_UPGRADES:
		# have a 'maxed out' logo on the button; lock the button
		print("Pipes at max Upgrade level!")
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
		print("Not enough data to upgrade pipes")
	return false
#endregion

#region hull shield upgrades
func upgrade_hull_shield() -> bool:
	if GameData.current_hull_shield_level >= GameData.MAX_HULL_SHIELD_UPGRADES:
		# maxed out
		print("Shield at max capacity!")
		return false
	
	var cost = GameData.HULL_SHIELD_UPGRADE_COSTS[GameData.current_hull_shield_level]
	
	if GameData.total_data >= cost:
		GameData.total_data -= cost
		GameData.current_hull_shield_level += 1
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		# if in future there need be a signal or anythin implement here.
		return true
	else:
		print("Not enough data to upgrade shield")
	return false
#endregion

#region reinforce
func reinforce_zone(zone_id: int) -> void:
	var cost = GameData.ZONE_REINFORCE_COSTS[zone_id]
	var final_cost = cost
	
	if GameData.current_reinforced_zone != -1 and GameData.current_reinforced_zone != zone_id:
		final_cost = cost * 1.5
		print("Taxed on switching reinforcement zone midway.")
	
	if GameData.total_data >= final_cost:
		GameData.total_data -= final_cost
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		clear_zone_reinforcement(GameData.current_reinforced_zone)
		await get_tree().process_frame
		reinforce_pipes(zone_id)
	else:
		print("Insufficient Data to Reinforce: ", GameData.Zone.keys()[zone_id])

func reinforce_pipes(zone_id: int) -> void:
	GameData.reinforcement_version += 1
	var my_version = GameData.reinforcement_version
	GameData.current_reinforced_zone = zone_id
	for cell in GameData.road_grid:
		var pipe = GameData.road_grid[cell]
		if pipe.my_zone == zone_id:
			pipe.reinforce()
	
	print("Zone: ", GameData.Zone.keys()[zone_id], "Reinforced!")

	GameData.active_reinforcement_timer = get_tree().create_timer(180.0)
	
	GameData.active_reinforcement_timer.timeout.connect(_on_reinforcement_timer_timeout.bind(zone_id, my_version))

func _on_reinforcement_timer_timeout(zone_id: int, version: int) -> void:
	if GameData.current_reinforced_zone == zone_id and GameData.reinforcement_version == version:
		clear_zone_reinforcement(zone_id)
		GameData.current_reinforced_zone = -1
		GameData.active_reinforcement_timer = null
		print("Zone: ", GameData.Zone.keys()[zone_id], "Reinforcement Expired!")

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
		print("Insufficient Data!")

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
			print("Auto Repair Reserve Empty!")
			break
#endregion

#region building spawns
func spawn_hub() -> bool:
	if GameData.current_hub_count >= GameData.MAX_HUBS:
		print("Hub cap reached.")
		return false
	
	if GameData.total_data < GameData.current_hub_spawn_cost:
		print("Insufficient data to spawn hub. Need %d, have %d" % [GameData.current_hub_spawn_cost, GameData.total_data])
		return false
	
	GameData.total_data -= GameData.current_hub_spawn_cost
	GameData.current_hub_spawn_cost += GameData.HUB_SPAWN_COST_INCREMENT
	GameData.current_hub_count += 1
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
	
	var director = get_node_or_null("/root/Main/Director")
	if director:
		director.request_hub_spawn()
		return true
	
	print("Director not found.")
	return false

func spawn_vent() -> bool:
	if GameData.current_vent_count >= GameData.MAX_VENTS:
		print("Vent cap reached.")
		return false
	
	if GameData.total_data < GameData.current_vent_spawn_cost:
		print("Insufficient data to spawn vent. Need %d, have %d" % [GameData.current_vent_spawn_cost, GameData.total_data])
		return false
	
	GameData.total_data -= GameData.current_vent_spawn_cost
	GameData.current_vent_spawn_cost += GameData.VENT_SPAWN_COST_INCREMENT
	GameData.current_vent_count += 1
	resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs)
	
	var director = get_node_or_null("/root/Main/Director")
	if director:
		director.request_vent_spawn()
		return true
	
	print("Director not found.")
	return false
#endregion
func upgrade_rocket_phase() -> bool:
	var next_phase = GameData.current_rocket_phase + 1
	
	if not GameData.ROCKET_UPGRADES.has(next_phase):
		print("Rocket at max phase.")
		return false
	
	var data = GameData.ROCKET_UPGRADES[next_phase]
	var cost = data["cost"]
	
	if GameData.total_data >= cost:
		GameData.total_data -= cost
		GameData.current_rocket_phase = next_phase
		
		# handle all the upgrades here.
		# handle all the upgrades here.
	var director = get_node_or_null("/root/Main/Director")
	if director:
		match next_phase:
			1: director.unlock_zone(GameData.Zone.INNER)
			2: director.unlock_zone(GameData.Zone.OUTER)
			3: director.unlock_zone(GameData.Zone.FRONTIER)
		
		resources_updated.emit(GameData.current_pipe_count, GameData.total_data, GameData.data_reserve_for_auto_repairs) # Notify UI
		
		SignalBus.rocket_segment_purchased.emit(GameData.current_rocket_phase)
		
		print("Rocket upgraded to: ", data["name"])
		return true
	else:
		print("Insufficient Data!")
		return false
#endregion
