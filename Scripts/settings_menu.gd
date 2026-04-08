extends Control

# Settings Menu with ATLAS glitch effects

signal close_settings

# UI References
@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderContainer/TitleLabel
@onready var master_slider: HSlider = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/AudioSection/MasterVolume/Slider
@onready var master_value_label: Label = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/AudioSection/MasterVolume/ValueLabel
@onready var music_slider: HSlider = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/AudioSection/MusicVolume/Slider
@onready var music_value_label: Label = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/AudioSection/MusicVolume/ValueLabel
@onready var sfx_slider: HSlider = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/AudioSection/SFXVolume/Slider
@onready var sfx_value_label: Label = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/AudioSection/SFXVolume/ValueLabel
@onready var fullscreen_checkbox: CheckBox = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/VideoSection/FullscreenToggle/CheckBox
@onready var vsync_checkbox: CheckBox = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/VideoSection/VsyncToggle/CheckBox
@onready var camera_shake_checkbox: CheckBox = $MarginContainer/VBoxContainer/SettingsScroll/SettingsContent/GameplaySection/CameraShakeToggle/CheckBox

# Glitch effect variables
var glitch_timer: float = 0.0
var glitch_interval: float = 0.6
var glitch_chance: float = 0.2
var glitch_targets: Array = []
var original_positions: Dictionary = {}

# Audio bus indices
const MASTER_BUS = 0
const MUSIC_BUS = 1
const SFX_BUS = 2
const AMBIENT_BUS = 3
const UI = 4
const CLICK_ALT = 5

func _ready() -> void:
	# Setup glitch targets
	glitch_targets = [title_label]
	
	# Store original positions
	for target in glitch_targets:
		original_positions[target] = target.position
	
	# Load saved settings
	load_settings()
	
	# Update UI
	update_volume_labels()
	
	# Hide initially
	hide()

func _process(delta: float) -> void:
	if not visible:
		return
	
	# Glitch effect
	glitch_timer += delta
	if glitch_timer >= glitch_interval:
		glitch_timer = 0.0
		if randf() < glitch_chance:
			apply_glitch()

func apply_glitch() -> void:
	var glitch_type = randi() % 3
	
	match glitch_type:
		0:
			glitch_position_shift()
		1:
			glitch_opacity_flicker()
		2:
			glitch_color_shift()

func glitch_position_shift() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	if not original_positions.has(target):
		return
	
	var shift = Vector2(randf_range(-3, 3), randf_range(-2, 2))
	var original_pos = original_positions[target]
	
	var tween = create_tween()
	tween.tween_property(target, "position", original_pos + shift, 0.05)
	tween.chain().tween_property(target, "position", original_pos, 0.05)

func glitch_opacity_flicker() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	var original_alpha = target.modulate.a
	
	var tween = create_tween()
	tween.tween_property(target, "modulate:a", 0.4, 0.03)
	tween.chain().tween_property(target, "modulate:a", original_alpha, 0.03)

func glitch_color_shift() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	
	var shifted_color = Color(
		randf_range(0.8, 1.0),
		randf_range(0.0, 0.2),
		randf_range(0.8, 1.0),
		1.0
	)
	var original_color = Color(1.0, 0.0, 1.0, 1.0)
	
	var tween = create_tween()
	tween.tween_property(target, "modulate", shifted_color, 0.05)
	tween.chain().tween_property(target, "modulate", original_color, 0.05)

func update_volume_labels() -> void:
	master_value_label.text = str(int(master_slider.value * 100)) + "%"
	music_value_label.text = str(int(music_slider.value * 100)) + "%"
	sfx_value_label.text = str(int(sfx_slider.value * 100)) + "%"

# Audio callbacks
func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(value))
	AudioServer.set_bus_mute(MASTER_BUS, value < 0.01)
	update_volume_labels()
	save_settings()

func _on_music_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(MUSIC_BUS, linear_to_db(value))
	AudioServer.set_bus_mute(MUSIC_BUS, value < 0.01)
	update_volume_labels()
	save_settings()

func _on_sfx_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(SFX_BUS, linear_to_db(value))
	AudioServer.set_bus_mute(SFX_BUS, value < 0.01)
	update_volume_labels()
	save_settings()

# Video callbacks
func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()

func _on_vsync_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	save_settings()

# Gameplay callbacks
func _on_camera_shake_toggled(toggled_on: bool) -> void:
	# GameData.enable_camera_shake = toggled_on
	save_settings()

# Button callbacks
func _on_close_button_pressed() -> void:
	close_settings.emit()
	hide()

func _on_back_button_pressed() -> void:
	close_settings.emit()
	hide()

func _on_reset_button_pressed() -> void:
	# Reset to defaults
	master_slider.value = 1.0
	music_slider.value = 0.8
	sfx_slider.value = 1.0
	fullscreen_checkbox.button_pressed = true
	vsync_checkbox.button_pressed = true
	camera_shake_checkbox.button_pressed = true
	
	# Apply defaults
	_on_master_volume_changed(1.0)
	_on_music_volume_changed(0.8)
	_on_sfx_volume_changed(1.0)
	_on_fullscreen_toggled(false)
	_on_vsync_toggled(true)
	_on_camera_shake_toggled(true)
	
	save_settings()

# Settings persistence
func save_settings() -> void:
	var config = ConfigFile.new()
	
	# Audio
	config.set_value("audio", "master_volume", master_slider.value)
	config.set_value("audio", "music_volume", music_slider.value)
	config.set_value("audio", "sfx_volume", sfx_slider.value)
	
	# Video
	config.set_value("video", "fullscreen", fullscreen_checkbox.button_pressed)
	config.set_value("video", "vsync", vsync_checkbox.button_pressed)
	
	# Gameplay
	config.set_value("gameplay", "camera_shake", camera_shake_checkbox.button_pressed)
	
	config.save("user://settings.cfg")

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err != OK:
		# No saved settings, use defaults
		return
	
	# Audio
	master_slider.value = config.get_value("audio", "master_volume", 1.0)
	music_slider.value = config.get_value("audio", "music_volume", 0.8)
	sfx_slider.value = config.get_value("audio", "sfx_volume", 1.0)
	
	# Video
	fullscreen_checkbox.button_pressed = config.get_value("video", "fullscreen", false)
	vsync_checkbox.button_pressed = config.get_value("video", "vsync", true)
	
	# Gameplay
	camera_shake_checkbox.button_pressed = config.get_value("gameplay", "camera_shake", true)
	
	# Apply loaded settings
	_on_master_volume_changed(master_slider.value)
	_on_music_volume_changed(music_slider.value)
	_on_sfx_volume_changed(sfx_slider.value)
	_on_fullscreen_toggled(fullscreen_checkbox.button_pressed)
	_on_vsync_toggled(vsync_checkbox.button_pressed)
	_on_camera_shake_toggled(camera_shake_checkbox.button_pressed)
