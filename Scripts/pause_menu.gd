extends Control

## Pause Menu (Glitch logic removed)

@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

# Settings menu reference
var settings_menu_scene = preload("res://Scenes/settings_menu.tscn")
var settings_menu_instance = null

func _ready() -> void:
	# PROCESS_MODE_ALWAYS is critical so the menu works while get_tree().paused is true
	process_mode = PROCESS_MODE_ALWAYS 
	
	# Fix SignalBus connection: ensure function name matches
	if SignalBus.has_signal("open_pause_menu"):
		SignalBus.open_pause_menu.connect(show_pause_menu)
	
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if settings_menu_instance and settings_menu_instance.visible:
			_close_settings()
		elif visible:
			_on_resume_button_pressed()
		else:
			# If the menu is hidden and ESC is pressed, trigger the pause
			show_pause_menu()
			
		get_viewport().set_input_as_handled()

func show_pause_menu() -> void:
	show()
	get_tree().paused = true
	resume_button.grab_focus() # Good practice for keyboard/controller support

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
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/title_screen.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
