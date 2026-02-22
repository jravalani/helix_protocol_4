extends Node

signal resources_updated(tiles: int, data: int) # The "Messenger"

func _ready():
	# Emit initial values so UI starts correct
	resources_updated.emit(GameData.current_road_tiles, GameData.total_data)

func spend_tile() -> bool:
	if GameData.current_road_tiles > 0:
		GameData.current_road_tiles -= 1
		resources_updated.emit(GameData.current_road_tiles, GameData.total_data) # Notify UI
		return true
	return false

func refund_tile() -> void:
	GameData.current_road_tiles += 1
	resources_updated.emit(GameData.current_road_tiles, GameData.total_data) # Notify UI

func add_score() -> void:
	GameData.total_data += 1
	if GameData.total_data >= GameData.score_to_next_reward:
		grant_reward()
	resources_updated.emit(GameData.current_road_tiles, GameData.total_data) # Notify UI

func grant_reward() -> void:
	GameData.current_road_tiles += 10
	GameData.score_to_next_reward += 8
	# Signal is handled by the add_score function call above

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
		# if in future there need be a signal or anythin implement here.
		return true
	else:
		print("Not enough data to upgrade shield")
	return false
