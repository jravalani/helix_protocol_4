extends Control

## Survival Handbook - Minimalist Logistics Guide
@onready var tabs: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton

func _ready() -> void:
	# Ensure the menu works even if the game was paused
	process_mode = PROCESS_MODE_ALWAYS
	
	# Focus back button for immediate keyboard/controller support
	back_button.grab_focus()
	
	# Style the tabs dynamically to save time in the editor
	var font = preload("res://Assets/Fonts/JetBrainsMono-ExtraBold.ttf")
	tabs.add_theme_font_override("font", font)
	tabs.add_theme_font_size_override("font_size", 20)

func _on_tab_container_tab_changed(tab: int) -> void:
	# Quick audio feedback if your AudioManager is ready
	if AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("click", 1.0, -5.0)
	
	# Optional: Trigger a tiny glitch effect on the title label when switching
	_title_glitch()

func _title_glitch() -> void:
	var title = $MarginContainer/VBoxContainer/Header
	var tween = create_tween()
	title.modulate = Color(1, 0, 1) # ATLAS Magenta
	tween.tween_property(title, "modulate", Color.WHITE, 0.1)

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/title_screen.tscn")
