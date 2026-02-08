extends Node2D


@onready var playable_area: ColorRect = $PlayableArea

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	SignalBus.increase_map_size.connect(update_map_visuals)
	update_map_visuals(GameData.current_map_size)

func update_map_visuals(new_rect: Rect2i) -> void:
	# 1. Logic: Use the passed rect IF it exists, otherwise use GameData
	var grid_rect = new_rect if new_rect != null else GameData.current_map_size
	
	# 2. Grab the cell size (ensuring it's a number, not a Vector)
	var cell_size = GameData.CELL_SIZE.x 
	
	# 3. The Math
	var pixel_pos = Vector2(grid_rect.position) * cell_size
	var pixel_size = Vector2(grid_rect.size) * cell_size
	
	# 4. Apply
	playable_area.position = pixel_pos
	playable_area.size = pixel_size
	
	print("Map Visuals Updated to Size: ", pixel_size)
