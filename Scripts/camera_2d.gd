extends Camera2D

@export var min_zoom: float = 0.1  # How far we can pull back
@export var max_zoom: float = 2.0   # How close we can stay
@export var zoom_smooth_speed: float = 0.05 # Try 0.1 for even slower

var zoom_step: float = 0.1

var target_zoom: Vector2 = Vector2(2.0, 2.0)

func _ready() -> void:
	zoom = target_zoom
	
	SignalBus.increase_map_size.connect(_on_map_size_changed)

func _process(delta: float) -> void:
	# 1. Linearly move the current zoom value toward the target value
	var new_z = move_toward(zoom.x, target_zoom.x, zoom_smooth_speed * delta)
	
	# 2. Apply the updated value to both axes
	if not is_equal_approx(zoom.x, new_z):
		zoom = Vector2(new_z, new_z)

func _on_map_size_changed(new_rect: Rect2i) -> void:
	# 1. Update Zoom (as we did before)
	var new_z = target_zoom.x - zoom_step
	new_z = max(new_z, min_zoom)
	target_zoom = Vector2(new_z, new_z)
	
	# 2. Update Position to Center
	# Calculate the center of the rect in grid units
	var grid_center = Vector2(new_rect.position) + (Vector2(new_rect.size) / 2.0)
	
	# Convert grid units to world pixels and move the camera
	global_position = grid_center * GameData.CELL_SIZE.x
