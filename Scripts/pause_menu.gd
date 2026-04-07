extends Control

## Pause Menu with ATLAS glitch effects (Synced with Title Scene)

@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
@onready var hint_label: Label = $CenterContainer/VBoxContainer/HintLabel

# Glitch variables
var glitch_timer: float = 0.0
var glitch_interval: float = 0.5
var glitch_chance: float = 0.25

# Position tracking for the Title-style position shift
@onready var original_title_position = title_label.position
# If you want to glitch the whole button container like the "Launchpad"
@onready var button_container = $CenterContainer/VBoxContainer
@onready var original_container_position = button_container.position

# Settings menu reference
var settings_menu_scene = preload("res://Scenes/settings_menu.tscn")
var settings_menu_instance = null

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # Ensure glitches run while paused
	hide()

func _process(delta: float) -> void:
	if not visible:
		return
	
	glitch_timer += delta
	if glitch_timer >= glitch_interval:
		glitch_timer = 0.0
		if randf() < glitch_chance:
			apply_glitch()

func apply_glitch() -> void:
	var glitch_type = randi() % 3
	
	match glitch_type:
		0: # Position shift (Title Scene style)
			glitch_position_shift()
		1: # Opacity flicker
			glitch_opacity_flicker()
		2: # Color shift (ATLAS Magenta style)
			glitch_color_shift()

func glitch_position_shift() -> void:
	# Randomly pick between Title or the Button Container
	var is_title = randi() % 2 == 0
	var shift = Vector2(randf_range(-5, 5), randf_range(-3, 3))
	
	var tween = create_tween()
	# Ensure tween works during pause
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	if is_title:
		tween.tween_property(title_label, "position", original_title_position + shift, 0.05)
		tween.chain().tween_property(title_label, "position", original_title_position, 0.05)
	else:
		# Glitch the entire VBoxContainer (similar to the Launchpad logic)
		tween.tween_property(button_container, "position", original_container_position + shift, 0.05)
		tween.chain().tween_property(button_container, "position", original_container_position, 0.05)

func glitch_opacity_flicker() -> void:
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	# Quick flicker on title - matching Title Scene timing
	tween.tween_property(title_label, "modulate:a", 0.3, 0.03)
	tween.chain().tween_property(title_label, "modulate:a", 1.0, 0.03)

func glitch_color_shift() -> void:
	# Using the Title Scene's specific Magenta spectrum
	var shifted_color = Color(1.0, randf_range(0.0, 0.2), 1.0, 1.0)
	var original_color = Color(1.0, 0.0, 1.0, 1.0) # ATLAS Base Magenta
	
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	tween.tween_property(title_label, "modulate", shifted_color, 0.05)
	tween.chain().tween_property(title_label, "modulate", original_color, 0.05)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if settings_menu_instance and settings_menu_instance.visible:
			# Close settings if open
			_close_settings()
		else:
			# Resume game
			_on_resume_button_pressed()
		get_viewport().set_input_as_handled()

func show_pause_menu() -> void:
	show()
	get_tree().paused = true

func hide_pause_menu() -> void:
	hide()
	get_tree().paused = false

# Button callbacks
func _on_resume_button_pressed() -> void:
	hide_pause_menu()

func _on_settings_button_pressed() -> void:
	if not settings_menu_instance:
		settings_menu_instance = settings_menu_scene.instantiate()
		add_child(settings_menu_instance)
		settings_menu_instance.close_settings.connect(_close_settings)
	
	settings_menu_instance.show()

func _close_settings() -> void:
	if settings_menu_instance:
		settings_menu_instance.hide()

func _on_main_menu_button_pressed() -> void:
	# Reset game state
	get_tree().paused = false
	# Change to main menu scene
	get_tree().change_scene_to_file("res://Scenes/title_screen.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
