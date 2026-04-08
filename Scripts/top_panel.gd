extends Control

@onready var pipe_label: Label = $MarginContainer/ParentHbox/HBoxContainer2/PipeCount
@onready var data_label: Label = $MarginContainer/ParentHbox/HBoxContainer3/DataLabel
@onready var reserve_label: Label = $MarginContainer/ParentHbox/HBoxContainer3/AutoReserve
@onready var pressure_label: Label = $MarginContainer/ParentHbox/HBoxContainer/Pressure

# Save button
var save_button: Button
var _save_feedback_label: Label
var _button_font: Font = preload("res://Assets/Fonts/JetBrainsMonoNL-SemiBold.ttf")

# Pause button
var pause_button: Button

# Fast-forward button
var fast_forward_button: Button
var fast_forward_active: bool = false
var _ff_normal_style: StyleBoxFlat
var _ff_active_style: StyleBoxFlat

# Current displayed values (what the user sees)
var displayed_pipe: float = 0.0
var displayed_data: float = 0.0
var displayed_reserve: float = 0.0

# Target values (where we want to count to)
var target_pipe: int = 0
var target_data: int = 0
var target_reserve: int = 0

# Animation settings
enum AnimationMode { LINEAR, EXPONENTIAL }
@export var animation_mode: AnimationMode = AnimationMode.EXPONENTIAL

# For LINEAR mode: counts per second
@export var linear_speed: float = 30.0

# For EXPONENTIAL mode: interpolation speed (higher = faster, try 5.0-15.0)
@export var exponential_speed: float = 5.0

# Timers for linear counting
var pipe_timer: float = 0.0
var data_timer: float = 0.0
var reserve_timer: float = 0.0

func _ready() -> void:
	ResourceManager.resources_updated.connect(_on_resources_updated)
	_create_save_button()
	_create_fast_forward_button()
	_create_pause_button()

	# Initialize to current game state
	displayed_pipe = float(GameData.current_pipe_count)
	target_pipe = GameData.current_pipe_count
	
	displayed_data = float(GameData.total_data)
	target_data = GameData.total_data
	
	displayed_reserve = float(GameData.data_reserve_for_auto_repairs)
	target_reserve = GameData.data_reserve_for_auto_repairs
	
	_update_labels()

func _process(delta: float) -> void:
	var needs_update = false
	
	if animation_mode == AnimationMode.LINEAR:
		needs_update = _process_linear(delta)
	else:
		needs_update = _process_exponential(delta)
	
	if needs_update:
		_update_labels()
	
	# Always update pressure
	pressure_label.text = "Pressure: %0.2f%%" % GameData.current_pressure

func _process_linear(delta: float) -> bool:
	var needs_update = false
	
	# Count pipe tiles
	if int(displayed_pipe) != target_pipe:
		pipe_timer += delta
		if pipe_timer >= (1.0 / linear_speed):
			pipe_timer = 0.0
			if displayed_pipe < target_pipe:
				displayed_pipe += 1
			else:
				displayed_pipe -= 1
			needs_update = true
	
	# Count data
	if int(displayed_data) != target_data:
		data_timer += delta
		if data_timer >= (1.0 / linear_speed):
			data_timer = 0.0
			if displayed_data < target_data:
				displayed_data += 1
			else:
				displayed_data -= 1
			needs_update = true
	
	# Count reserve
	if int(displayed_reserve) != target_reserve:
		reserve_timer += delta
		if reserve_timer >= (1.0 / linear_speed):
			reserve_timer = 0.0
			if displayed_reserve < target_reserve:
				displayed_reserve += 1
			else:
				displayed_reserve -= 1
			needs_update = true
	
	return needs_update

func _process_exponential(delta: float) -> bool:
	var needs_update = false
	var snap_threshold = 0.5
	
	# Exponential ease for pipe count
	if abs(displayed_pipe - target_pipe) > snap_threshold:
		displayed_pipe = lerp(displayed_pipe, float(target_pipe), exponential_speed * delta)
		needs_update = true
	elif int(displayed_pipe) != target_pipe:
		displayed_pipe = float(target_pipe)
		needs_update = true
	
	# Exponential ease for data
	if abs(displayed_data - target_data) > snap_threshold:
		displayed_data = lerp(displayed_data, float(target_data), exponential_speed * delta)
		needs_update = true
	elif int(displayed_data) != target_data:
		displayed_data = float(target_data)
		needs_update = true
	
	# Exponential ease for reserve
	if abs(displayed_reserve - target_reserve) > snap_threshold:
		displayed_reserve = lerp(displayed_reserve, float(target_reserve), exponential_speed * delta)
		needs_update = true
	elif int(displayed_reserve) != target_reserve:
		displayed_reserve = float(target_reserve)
		needs_update = true
	
	return needs_update

func _update_labels() -> void:
	pipe_label.text = "Pipe Tiles: " + str(int(displayed_pipe))
	data_label.text = "Data: " + str(int(displayed_data))
	reserve_label.text = "Repair Reserve: " + str(int(displayed_reserve))

func _on_resources_updated(tiles: int, score: int, reserve: int):
	# Just update the targets - the animation will catch up
	target_pipe = tiles
	target_data = score
	target_reserve = reserve


# ═══════════════════════════════════════════════════════════════
# UPLINK (Save) Button
# ═══════════════════════════════════════════════════════════════

func _create_save_button() -> void:
	# Create a styled save button anchored to the top-right
	save_button = Button.new()
	save_button.text = "UPLINK"
	save_button.custom_minimum_size = Vector2(120, 36)

	# Style it as a small industrial panel chip
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.06, 0.08, 0.10, 0.9)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color("4a5568")
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4

	var hover_style = normal_style.duplicate()
	hover_style.border_color = Color("ff00ff")

	var pressed_style = normal_style.duplicate()
	pressed_style.border_color = Color("00ff88")

	# Focus style matches normal so the outline resets properly
	var focus_style = normal_style.duplicate()

	save_button.add_theme_stylebox_override("normal", normal_style)
	save_button.add_theme_stylebox_override("hover", hover_style)
	save_button.add_theme_stylebox_override("pressed", pressed_style)
	save_button.add_theme_stylebox_override("focus", focus_style)
	if _button_font:
		save_button.add_theme_font_override("font", _button_font)
	save_button.add_theme_font_size_override("font_size", 18)
	save_button.add_theme_color_override("font_color", Color("c8ff00"))
	save_button.add_theme_color_override("font_hover_color", Color("ffaa00"))

	# Position near center-right of the top bar
	save_button.layout_mode = 1
	save_button.anchors_preset = Control.PRESET_CENTER_TOP
	save_button.position = Vector2(600, 14)

	save_button.pressed.connect(_on_save_pressed)
	add_child(save_button)


# ═══════════════════════════════════════════════════════════════
# FAST-FORWARD Button 
# ═══════════════════════════════════════════════════════════════

func _create_fast_forward_button() -> void:
	fast_forward_button = Button.new()
	fast_forward_button.text = "▶▶"
	fast_forward_button.custom_minimum_size = Vector2(36, 36)

	# Normal (inactive) style
	_ff_normal_style = StyleBoxFlat.new()
	_ff_normal_style.bg_color = Color(0.06, 0.08, 0.10, 0.9)
	_ff_normal_style.border_width_left = 2
	_ff_normal_style.border_width_top = 2
	_ff_normal_style.border_width_right = 2
	_ff_normal_style.border_width_bottom = 2
	_ff_normal_style.border_color = Color("4a5568")
	_ff_normal_style.content_margin_left = 8
	_ff_normal_style.content_margin_right = 8
	_ff_normal_style.content_margin_top = 4
	_ff_normal_style.content_margin_bottom = 4

	# Active (highlighted) style — bright border to indicate fast-forward is on
	_ff_active_style = _ff_normal_style.duplicate()
	_ff_active_style.border_color = Color("00ff88")

	var hover_style = _ff_normal_style.duplicate()
	hover_style.border_color = Color("ff00ff")

	var pressed_style = _ff_normal_style.duplicate()
	pressed_style.border_color = Color("00ff88")

	var focus_style = _ff_normal_style.duplicate()

	fast_forward_button.add_theme_stylebox_override("normal", _ff_normal_style)
	fast_forward_button.add_theme_stylebox_override("hover", hover_style)
	fast_forward_button.add_theme_stylebox_override("pressed", pressed_style)
	fast_forward_button.add_theme_stylebox_override("focus", focus_style)
	if _button_font:
		fast_forward_button.add_theme_font_override("font", _button_font)
	fast_forward_button.add_theme_font_size_override("font_size", 18)
	fast_forward_button.add_theme_color_override("font_color", Color("c8ff00"))
	fast_forward_button.add_theme_color_override("font_hover_color", Color("ffaa00"))

	fast_forward_button.layout_mode = 1
	fast_forward_button.anchors_preset = Control.PRESET_CENTER_TOP
	fast_forward_button.position = Vector2(740, 14)

	fast_forward_button.pressed.connect(_on_fast_forward_pressed)
	add_child(fast_forward_button)


func _on_fast_forward_pressed() -> void:
	fast_forward_button.release_focus()
	fast_forward_active = !fast_forward_active

	if fast_forward_active:
		fast_forward_button.add_theme_stylebox_override("normal", _ff_active_style)
		fast_forward_button.add_theme_stylebox_override("focus", _ff_active_style)
	else:
		fast_forward_button.add_theme_stylebox_override("normal", _ff_normal_style)
		fast_forward_button.add_theme_stylebox_override("focus", _ff_normal_style)


# ═══════════════════════════════════════════════════════════════
# PAUSE Button
# ═══════════════════════════════════════════════════════════════

func _create_pause_button() -> void:
	pause_button = Button.new()
	pause_button.text = "▶"
	pause_button.custom_minimum_size = Vector2(36, 36)

	# Style it to match the UPLINK button
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.06, 0.08, 0.10, 0.9)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color("4a5568")
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4

	var hover_style = normal_style.duplicate()
	hover_style.border_color = Color("ff00ff")

	var pressed_style = normal_style.duplicate()
	pressed_style.border_color = Color("00ff88")

	# Focus style matches normal so the outline resets properly
	var focus_style = normal_style.duplicate()

	pause_button.add_theme_stylebox_override("normal", normal_style)
	pause_button.add_theme_stylebox_override("hover", hover_style)
	pause_button.add_theme_stylebox_override("pressed", pressed_style)
	pause_button.add_theme_stylebox_override("focus", focus_style)
	if _button_font:
		pause_button.add_theme_font_override("font", _button_font)
	pause_button.add_theme_font_size_override("font_size", 18)
	pause_button.add_theme_color_override("font_color", Color("c8ff00"))
	pause_button.add_theme_color_override("font_hover_color", Color("ffaa00"))

	# Position to the right of the UPLINK button
	pause_button.layout_mode = 1
	pause_button.anchors_preset = Control.PRESET_CENTER_TOP
	pause_button.position = Vector2(-825, 14)

	pause_button.pressed.connect(_on_pause_pressed)
	add_child(pause_button)


func _on_pause_pressed() -> void:
	AudioManager.play_sfx("upgrade", 1.0, -5.0)
	pause_button.release_focus()
	var pause_menu = get_parent().get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.show_pause_menu()


func _on_save_pressed() -> void:
	AudioManager.play_sfx("upgrade", 1.0, -5.0)
	save_button.release_focus()
	var success = SaveManager.save_game()
	if success:
		_show_save_feedback("STATE ARCHIVED", Color("c8ff00"))
	else:
		_show_save_feedback("UPLINK FAILURE", Color("ff4444"))


func _show_save_feedback(text: String, color: Color) -> void:
	if _save_feedback_label and is_instance_valid(_save_feedback_label):
		_save_feedback_label.queue_free()

	_save_feedback_label = Label.new()
	_save_feedback_label.text = text
	_save_feedback_label.add_theme_color_override("font_color", color)
	if _button_font:
		_save_feedback_label.add_theme_font_override("font", _button_font)
	_save_feedback_label.add_theme_font_size_override("font_size", 20)
	_save_feedback_label.position = Vector2(save_button.position.x - 40, save_button.position.y + 44)
	add_child(_save_feedback_label)

	var tw = create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_save_feedback_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_save_feedback_label.queue_free)
