extends Node2D


@onready var camera_2d: Camera2D = $Camera2D
const CELL_SIZE = 64
var line_color = Color(0.8, 0.8, 0.8, 0.2)

func _ready():
	z_index = -10
	# Connect to the size_changed signal so the grid redraws if you resize the window
	get_viewport().size_changed.connect(queue_redraw)

func _draw() -> void:
	# Get the current viewport size
	var view_size = get_viewport().get_visible_rect().size
	# get camera center
	var center = camera_2d.get_screen_center_position()
	
	# calculate top left and bottom right
	var top_left = center - (view_size / 2)
	var bottom_right = center + (view_size / 2)
	
	# Calculate how many lines we need to fill the screen
	var start_x = floor(top_left.x / GameData.CELL_SIZE.x) * CELL_SIZE
	var start_y = floor(top_left.y / GameData.CELL_SIZE.y) * CELL_SIZE
	
	var end_x = floor(bottom_right.x / GameData.CELL_SIZE.x) * CELL_SIZE
	var end_y = floor(bottom_right.y / GameData.CELL_SIZE.y) * CELL_SIZE
	# Draw Vertical Lines
	# Start at the first visible pixel, end at the last, jumping by CELL_SIZE each time
	for x in range(start_x, end_x + CELL_SIZE, CELL_SIZE):
		# Now 'x' is already the correct pixel coordinate!
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), line_color)

	# Draw Horizontal Lines
	for y in range(start_y, end_y + CELL_SIZE, CELL_SIZE):
		# Now 'y' is already the correct pixel coordinate!
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), line_color)
	
	# Draw intersection points (Dots)
	var point_color = Color(1, 1, 1, 0.5) # Semi-transparent white
	for x in range(start_x, end_x + CELL_SIZE, CELL_SIZE):
		for y in range(start_y, end_y + CELL_SIZE, CELL_SIZE):
			# Draw a small circle at the exact coordinate
			draw_circle(Vector2(x, y), 2.0, point_color)
	
	# Optional: Draw Coordinate Labels
	var font = ThemeDB.get_fallback_font()
	var font_size = 12
	for x in range(start_x, end_x + CELL_SIZE, CELL_SIZE):
		for y in range(start_y, end_y + CELL_SIZE, CELL_SIZE):
			var grid_pos = Vector2i(x / CELL_SIZE, y / CELL_SIZE)
			draw_string(font, Vector2(x + 5, y + 15), str(grid_pos), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, point_color)
