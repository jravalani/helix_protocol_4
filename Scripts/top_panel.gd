extends Control

@onready var pipe_label: Label = $MarginContainer/ParentHbox/HBoxContainer2/PipeCount
@onready var data_label: Label = $MarginContainer/ParentHbox/HBoxContainer2/HBoxContainer3/DataLabel
@onready var reserve_label: Label = $MarginContainer/ParentHbox/HBoxContainer2/HBoxContainer3/AutoReserve
@onready var pressure_label: Label = $MarginContainer/ParentHbox/HBoxContainer2/HBoxContainer/Pressure

@onready var pause_button: Button = %PauseButton
@onready var speed_up_button: Button = %SpeedUpButton
@onready var uplink_button: Button = %UplinkButton

var _save_feedback_label: Label
var _button_font: Font = preload("res://Assets/Fonts/JetBrainsMonoNL-SemiBold.ttf")

var is_fast_speed: bool = false

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

	# Initialize to current game state
	displayed_pipe = float(GameData.current_pipe_count)
	target_pipe = GameData.current_pipe_count

	displayed_data = float(GameData.total_data)
	target_data = GameData.total_data

	displayed_reserve = float(GameData.data_reserve_for_auto_repairs)
	target_reserve = GameData.data_reserve_for_auto_repairs

	_update_labels()

	# Speed-up is hidden until the tutorial reaches the WAIT_FOR_DATA step
	speed_up_button.hide()
	speed_up_button.disabled = true
	
	# Up-link is hidden until the tutorial reaches the SAVE_GAME step
	uplink_button.hide()
	uplink_button.disabled = true

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

	if int(displayed_pipe) != target_pipe:
		pipe_timer += delta
		if pipe_timer >= (1.0 / linear_speed):
			pipe_timer = 0.0
			if displayed_pipe < target_pipe:
				displayed_pipe += 1
			else:
				displayed_pipe -= 1
			needs_update = true

	if int(displayed_data) != target_data:
		data_timer += delta
		if data_timer >= (1.0 / linear_speed):
			data_timer = 0.0
			if displayed_data < target_data:
				displayed_data += 1
			else:
				displayed_data -= 1
			needs_update = true

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

	if abs(displayed_pipe - target_pipe) > snap_threshold:
		displayed_pipe = lerp(displayed_pipe, float(target_pipe), exponential_speed * delta)
		needs_update = true
	elif int(displayed_pipe) != target_pipe:
		displayed_pipe = float(target_pipe)
		needs_update = true

	if abs(displayed_data - target_data) > snap_threshold:
		displayed_data = lerp(displayed_data, float(target_data), exponential_speed * delta)
		needs_update = true
	elif int(displayed_data) != target_data:
		displayed_data = float(target_data)
		needs_update = true

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
	target_pipe = tiles
	target_data = score
	target_reserve = reserve


# ═══════════════════════════════════════════════════════════════
# PAUSE Button
# ═══════════════════════════════════════════════════════════════

func _on_pause_pressed() -> void:
	AudioManager.play_sfx("upgrade", 1.0, -5.0)
	pause_button.release_focus()
	var pause_menu = get_parent().get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.show_pause_menu()


# ═══════════════════════════════════════════════════════════════
# SPEED UP Button
# ═══════════════════════════════════════════════════════════════

## Called by in_level_ui when the tutorial reaches WAIT_FOR_DATA.
func unlock_speed_button() -> void:
	speed_up_button.show()
	speed_up_button.disabled = false

## Called externally (e.g. hub repair restore) to sync button state
## after time_scale has been changed outside this script.
func sync_speed_button_state() -> void:
	is_fast_speed = false
	speed_up_button.text = ">"
	speed_up_button.modulate = Color(1.0, 1.0, 1.0)

func _on_speed_up_pressed() -> void:
	speed_up_button.release_focus()
	# Don't interfere while the tutorial slow-mo is active
	if Engine.time_scale == 0.25:
		return
	is_fast_speed = not is_fast_speed
	if is_fast_speed:
		Engine.time_scale = 2.0
		speed_up_button.text = ">>"
		speed_up_button.modulate = Color(1.0, 0.8, 0.2)
	else:
		Engine.time_scale = 1.0
		speed_up_button.text = ">"
		speed_up_button.modulate = Color(1.0, 1.0, 1.0)


# ═══════════════════════════════════════════════════════════════
# UPLINK Button
# ═══════════════════════════════════════════════════════════════

func unlock_uplink_button() -> void:
	uplink_button.show()
	uplink_button.disabled = false

func _on_uplink_pressed() -> void:
	AudioManager.play_sfx("upgrade", 1.0, -5.0)
	uplink_button.release_focus()
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
	_save_feedback_label.position = Vector2(uplink_button.position.x - 40, uplink_button.position.y + 44)
	add_child(_save_feedback_label)

	var tw = create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_save_feedback_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_save_feedback_label.queue_free)
