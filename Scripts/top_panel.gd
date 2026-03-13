extends Control

@onready var pipe_label: Label = $MarginContainer/ParentHbox/HBoxContainer2/PipeCount
@onready var data_label: Label = $MarginContainer/ParentHbox/HBoxContainer3/DataLabel
@onready var reserve_label: Label = $MarginContainer/ParentHbox/HBoxContainer3/AutoReserve
@onready var pressure_label: Label = $MarginContainer/ParentHbox/HBoxContainer/Pressure
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
