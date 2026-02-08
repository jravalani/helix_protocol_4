extends Node2D

const CELL_SIZE = 64
var line_color = Color(0.8, 0.8, 0.8, 0.2)

func _ready():
	z_index = -10
	# Connect to the size_changed signal so the grid redraws if you resize the window
	get_viewport().size_changed.connect(queue_redraw)

func _draw() -> void:
	# Get the current viewport size
	var view_size = get_viewport().get_visible_rect().size
	
	# Calculate how many lines we need to fill the screen
	var columns = int(view_size.x / CELL_SIZE) + 1
	var rows = int(view_size.y / CELL_SIZE) + 1
	
	# Draw Vertical Lines
	for i in range(columns):
		var x = i * CELL_SIZE
		draw_line(Vector2(x, 0), Vector2(x, view_size.y), line_color)
		
	# Draw Horizontal Lines
	for i in range(rows):
		var y = i * CELL_SIZE
		draw_line(Vector2(0, y), Vector2(view_size.x, y), line_color)
