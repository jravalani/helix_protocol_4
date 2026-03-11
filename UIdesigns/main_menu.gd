extends Control

func _on_launch_mission_pressed():
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_tech_tree_pressed():
	get_tree().change_scene_to_file("res://scenes/TechTree.tscn")

func _on_settings_pressed():
	pass

func _on_quit_pressed():
	get_tree().quit()
