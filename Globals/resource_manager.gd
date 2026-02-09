extends Node

signal resources_updated(tiles: int, score: int) # The "Messenger"

var current_road_tiles: int = 15
var total_score: int = 0
var score_to_next_reward: int = 6

func _ready():
	# Emit initial values so UI starts correct
	resources_updated.emit(current_road_tiles, total_score)

func spend_tile() -> bool:
	if current_road_tiles > 0:
		current_road_tiles -= 1
		resources_updated.emit(current_road_tiles, total_score) # Notify UI
		return true
	return false

func refund_tile() -> void:
	current_road_tiles += 1
	resources_updated.emit(current_road_tiles, total_score) # Notify UI

func add_score() -> void:
	total_score += 1
	if total_score >= score_to_next_reward:
		grant_reward()
	resources_updated.emit(current_road_tiles, total_score) # Notify UI

func grant_reward() -> void:
	current_road_tiles += 10
	score_to_next_reward += 8
	# Signal is handled by the add_score function call above
