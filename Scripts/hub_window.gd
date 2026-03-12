extends Panel

@onready var pressure_visual: TextureProgressBar = $PressureVisual

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pressure_visual.value = GameData.current_pressure
