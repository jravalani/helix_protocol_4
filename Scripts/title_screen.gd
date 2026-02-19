extends Control


@export var main_scene: PackedScene = preload("res://Scenes/main.tscn")

func _on_play_button_pressed() -> void:
	print("Play button pressed")
	get_tree().change_scene_to_packed(main_scene)

func _on_how_to_play_button_pressed() -> void:
	pass # Replace with function body.
