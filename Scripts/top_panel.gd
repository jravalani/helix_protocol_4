extends Control


@onready var pipe_label: Label = $MarginContainer/HBoxContainer/PipeCount
@onready var data_label: Label = $MarginContainer/HBoxContainer/DataLabel
@onready var reserve_label: Label = $MarginContainer/HBoxContainer/AutoReserve
@onready var pressure_label: Label = $MarginContainer/HBoxContainer/Pressure

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	
	ResourceManager.resources_updated.connect(_on_resources_updated)
	
	pipe_label.text = "Pipe Count: " + str(GameData.current_pipe_count)
	data_label.text = "Data: " + str(GameData.total_data)
	reserve_label.text = "Auto Repair Data: " + str(GameData.data_reserve_for_auto_repairs)
	pressure_label.text = "Pressure: %0.1f%%" % GameData.current_pressure

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pressure_label.text = "Pressure: %0.1f%%" % GameData.current_pressure 

func _on_resources_updated(tiles: int, score: int, reserve: int):
	pipe_label.text = "Road Tiles: " + str(tiles)
	data_label.text = "Data: " + str(score)
	reserve_label.text = "Auto Repair Data: " + str(reserve)
