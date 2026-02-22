extends Node2D
@onready var camera_2d: Camera2D = $Camera2D
const CELL_SIZE = 64
const CELL_SIZE_VEC = Vector2(64, 64)
var line_color = Color(0.8, 0.8, 0.8, 0.2)

func _ready():
	z_index = -10
	# Connect to the size_changed signal so the grid redraws if you resize the window
	get_viewport().size_changed.connect(queue_redraw)


func _process(_delta):
	get_tree().create_timer(10.0).timeout.connect(queue_redraw)

func _draw() -> void:
	var view_size = get_viewport().get_visible_rect().size
	var center = camera_2d.get_screen_center_position()
	var top_left = center - (view_size / 2)
	var bottom_right = center + (view_size / 2)
	var start_x = int(floor(top_left.x / CELL_SIZE)) * CELL_SIZE
	var start_y = int(floor(top_left.y / CELL_SIZE)) * CELL_SIZE
	var end_x = int(floor(bottom_right.x / CELL_SIZE)) * CELL_SIZE
	var end_y = int(floor(bottom_right.y / CELL_SIZE)) * CELL_SIZE
	
	## DEBUG: Print camera and viewport info
	#print("=== DEBUG INFO ===")
	#print("Camera position: ", camera_2d.global_position)
	#print("Camera center: ", center)
	#print("View size: ", view_size)
	#print("Visible range X: ", top_left.x, " to ", bottom_right.x)
	#print("Visible range Y: ", top_left.y, " to ", bottom_right.y)
	#print("Influence grid size: ", GameData.influence_grid.size())
	
	# Draw heatmap FIRST (so it appears behind grid lines)
	var drawn_count = 0
	var positive_count = 0
	var negative_count = 0
	var max_positive = 0.0
	var max_negative = 0.0
	
	for tile in GameData.influence_grid:
		var score = GameData.influence_grid[tile]
		if abs(score) < 0.1:
			continue
		
		if score > 0:
			positive_count += 1
			max_positive = max(max_positive, score)
		else:
			negative_count += 1
			max_negative = min(max_negative, score)
		
		# Smoother color gradient
		var color: Color
		if score > 0:
			# Positive: Blue to Green gradient
			var intensity = clamp(score / 150.0, 0.0, 1.0)
			color = Color(0.0, 0.5 + intensity * 0.5, 0.3 + intensity * 0.7)
		else:
			# Negative: Orange to Red gradient
			var intensity = clamp(abs(score) / 150.0, 0.0, 1.0)
			color = Color(0.8 + intensity * 0.2, 0.3 - intensity * 0.3, 0.0)
		
		color.a = clamp(abs(score) / 150.0, 0.15, 0.6)
		
		var rect = Rect2(Vector2(tile) * CELL_SIZE_VEC, CELL_SIZE_VEC)
		draw_rect(rect, color)
		drawn_count += 1
	
	#print("Drew ", drawn_count, " heatmap tiles | Positive: ", positive_count, " (max: ", max_positive, ") | Negative: ", negative_count, " (min: ", max_negative, ")")
	
	
	# Draw grid lines
	for x in range(start_x, end_x + CELL_SIZE, CELL_SIZE):
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), line_color)
	for y in range(start_y, end_y + CELL_SIZE, CELL_SIZE):
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), line_color)
	
	# Draw grid points and labels
	var point_color = Color(1, 1, 1, 0.5)
	var font = ThemeDB.get_fallback_font()
	var font_size = 12
	for x in range(start_x, end_x + CELL_SIZE, CELL_SIZE):
		for y in range(start_y, end_y + CELL_SIZE, CELL_SIZE):
			draw_circle(Vector2(x, y), 2.0, point_color)
			var grid_pos = Vector2i(x / CELL_SIZE, y / CELL_SIZE)
			draw_string(font, Vector2(x + 5, y + 15), str(grid_pos), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, point_color)
