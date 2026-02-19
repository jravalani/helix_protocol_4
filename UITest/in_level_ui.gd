extends Control

@onready var tile_label: Label = $MarginContainer/HBoxContainer/RoadTiles
@onready var score_label: Label = $MarginContainer/HBoxContainer/Score
@onready var speed_button: Button = $MarginContainer/HBoxContainer/SpeedButton
var is_fast_speed: bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Engine.time_scale = 1.0
	speed_button.text = "Speed: 1x"
	
	ResourceManager.resources_updated.connect(_on_resources_updated)
	
	tile_label.text = "Road Tiles: " + str(ResourceManager.current_road_tiles)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_resources_updated(tiles: int, score: int):
	tile_label.text = "Road Tiles: " + str(tiles)
	score_label.text = "Score: " + str(score)

func _on_build_road_button_pressed() -> void:
	print("Build Road Button Pressed!")
	SignalBus.build_road.emit()

func _on_rotate_house_button_pressed() -> void:
	print("Rotate House Button Pressed")
	SignalBus.rotate_house.emit()

func _on_roundabout_button_pressed() -> void:
	print("Roundabouts Button Pressed")


func _on_highway_pressed() -> void:
	print("Highway Button Pressed!")


func _on_speed_button_pressed() -> void:
	print("speed toggle")
	is_fast_speed = !is_fast_speed
	
	if is_fast_speed:
		Engine.time_scale = 4.0
		speed_button.text = "Speed: 4x"
		speed_button.modulate =  Color(1.5, 1.5, 1.5, 1.0)
	else:
		Engine.time_scale = 1.0
		speed_button.text = "Speed: 1x"
		speed_button.modulate = Color.WHITE
