extends Camera2D

# We don't necessarily need these as variables at the top anymore 
# if we calculate them fresh inside the function!

func _ready() -> void:
	# 1. Connect first so we don't miss any signals
	SignalBus.increase_map_size.connect(increase_camera_bounds)
	
	# 2. Call it once to set the starting view
	increase_camera_bounds(GameData.current_map_size)

func increase_camera_bounds(new_map_size: Rect2i) -> void:
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
