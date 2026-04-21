extends Camera2D

var _shake_tween: Tween = null
var _base_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	# 1. Connect first so we don't miss any signals
	SignalBus.increase_map_size.connect(increase_camera_bounds)
	SignalBus.camera_shake.connect(shake)
	SignalBus.camera_zoom.connect(zoom_by_multiplier)
	# 2. Call it once to set the starting view
	increase_camera_bounds(GameData.current_map_size)

func increase_camera_bounds(new_map_size: Rect2i) -> void:
	print("Camera received new map size: ", new_map_size)
	# --- FIXED LINE BELOW ---
	# We "grab" the screen size right when we need it
	var viewport_size = get_viewport_rect().size
	
	# 1. Convert Grid Size to a Vector2 of Pixels
	var pixel_map_size = Vector2(new_map_size.size) * GameData.CELL_SIZE.x
	
	# 2. Calculate ratios
	var zoom_x = viewport_size.x / pixel_map_size.x
	var zoom_y = viewport_size.y / pixel_map_size.y
	
	# 3. Choose the best fit
	var final_zoom_val = min(zoom_x, zoom_y) * 0.95
	var target_zoom = Vector2(final_zoom_val, final_zoom_val)

	# 4. Animate
	var tween = create_tween()
	tween.set_parallel(true) # This lets zoom and position happen at once
	tween.tween_property(self, "zoom", target_zoom, 1.2).set_trans(Tween.TRANS_SINE)
	
	# 5. Center the camera so it doesn't just zoom into the top-left corner
	var map_center_pixels = Vector2(new_map_size.get_center()) * GameData.CELL_SIZE.x
	tween.tween_property(self, "position", map_center_pixels, 1.2).set_trans(Tween.TRANS_SINE)

	# 6. Update Limits (The "Walls")
	limit_left = new_map_size.position.x * GameData.CELL_SIZE.x
	limit_top = new_map_size.position.y * GameData.CELL_SIZE.x
	limit_right = limit_left + int(pixel_map_size.x)
	limit_bottom = limit_top + int(pixel_map_size.y)

func shake(duration: float, strength: float) -> void:
	# Kill any existing shake so they don't stack
	if _shake_tween:
		_shake_tween.kill()
		offset = _base_offset

	_shake_tween = create_tween()
	var elapsed := 0.0
	var steps := int(duration / 0.05)  # one shake step every 50ms

	for i in range(steps):
		var remaining := 1.0 - (float(i) / float(steps))
		var current_strength := strength * remaining  # decays over time
		var rand_offset := Vector2(
			randf_range(-current_strength, current_strength),
			randf_range(-current_strength, current_strength)
		)
		_shake_tween.tween_property(self, "offset", rand_offset, 0.05)

# Settle back to base offset cleanly
	_shake_tween.tween_property(self, "offset", _base_offset, 0.05)

func zoom_by_multiplier(multiplier: float, duration: float) -> void:
	var target := zoom * multiplier
	var tw := create_tween()
	tw.tween_property(self, "zoom", target, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
