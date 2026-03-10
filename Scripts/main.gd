extends Node2D
@onready var camera_2d: Camera2D = $Camera2D

const CELL_SIZE = 64
const CELL_SIZE_VEC = Vector2(64, 64)
const PANEL_SIZE = 192  # 2x2 cells = one panel

# Industrial color scheme
var panel_line_color = Color(0.4, 0.45, 0.5, 0.3)  # Lighter, more metallic
var panel_corner_color = Color(0.5, 0.55, 0.6, 0.5)  # Corner rivets/bolts
var panel_fill_color = Color(0.32, 0.32, 0.32, 0.05)  # Subtle panel fill

func _ready():
	
	await SceneTransition.launch_reveal()
	z_index = 1
	get_viewport().size_changed.connect(queue_redraw)

func _process(_delta):
	get_tree().create_timer(10.0).timeout.connect(queue_redraw)

func _draw() -> void:
	var view_size = get_viewport().get_visible_rect().size
	var center = camera_2d.get_screen_center_position()
	var top_left = center - (view_size / 2)
	var bottom_right = center + (view_size / 2)
	
	var start_x = int(floor(top_left.x / PANEL_SIZE)) * PANEL_SIZE
	var start_y = int(floor(top_left.y / PANEL_SIZE)) * PANEL_SIZE
	var end_x = int(ceil(bottom_right.x / PANEL_SIZE)) * PANEL_SIZE
	var end_y = int(ceil(bottom_right.y / PANEL_SIZE)) * PANEL_SIZE
	
	# Draw heatmap first (your existing code)
	var drawn_count = 0
	for tile in GameData.influence_grid:
		var score = GameData.influence_grid[tile]
		if abs(score) < 0.1:
			continue
		
		var color: Color
		if score > 0:
			var intensity = clamp(score / 150.0, 0.0, 1.0)
			color = Color(0.0, 0.5 + intensity * 0.5, 0.3 + intensity * 0.7)
		else:
			var intensity = clamp(abs(score) / 150.0, 0.0, 1.0)
			color = Color(0.8 + intensity * 0.2, 0.3 - intensity * 0.3, 0.0)
		
		color.a = clamp(abs(score) / 150.0, 0.15, 0.6)
		
		var rect = Rect2(Vector2(tile) * CELL_SIZE_VEC, CELL_SIZE_VEC)
		draw_rect(rect, color)
		drawn_count += 1
	
	# Draw industrial panels (128x128)
	for x in range(start_x, end_x + PANEL_SIZE, PANEL_SIZE):
		for y in range(start_y, end_y + PANEL_SIZE, PANEL_SIZE):
			_draw_industrial_panel(Vector2(x, y))

func _draw_industrial_panel(top_left: Vector2) -> void:
	var panel_rect = Rect2(top_left, Vector2(PANEL_SIZE, PANEL_SIZE))
	
	# 1. Subtle panel background
	draw_rect(panel_rect, panel_fill_color)
	
	# 2. Panel border (thicker lines)
	var border_width = 2.0
	# Top
	draw_line(top_left, top_left + Vector2(PANEL_SIZE, 0), panel_line_color, border_width)
	# Left
	draw_line(top_left, top_left + Vector2(0, PANEL_SIZE), panel_line_color, border_width)
	# Right
	draw_line(top_left + Vector2(PANEL_SIZE, 0), top_left + Vector2(PANEL_SIZE, PANEL_SIZE), panel_line_color, border_width)
	# Bottom
	draw_line(top_left + Vector2(0, PANEL_SIZE), top_left + Vector2(PANEL_SIZE, PANEL_SIZE), panel_line_color, border_width)
	
	# 3. Corner rivets/bolts (industrial detail)
	var rivet_radius = 3.0
	var rivet_inset = 8.0
	
	# Top-left corner
	draw_circle(top_left + Vector2(rivet_inset, rivet_inset), rivet_radius, panel_corner_color)
	# Top-right corner
	draw_circle(top_left + Vector2(PANEL_SIZE - rivet_inset, rivet_inset), rivet_radius, panel_corner_color)
	# Bottom-left corner
	draw_circle(top_left + Vector2(rivet_inset, PANEL_SIZE - rivet_inset), rivet_radius, panel_corner_color)
	# Bottom-right corner
	draw_circle(top_left + Vector2(PANEL_SIZE - rivet_inset, PANEL_SIZE - rivet_inset), rivet_radius, panel_corner_color)
	
	# 4. Optional: Diagonal corner chamfers (more industrial feel)
	var chamfer_size = 12.0
	var chamfer_color = Color(0.35, 0.35, 0.35, 0.15)
	
	# Top-left chamfer
	var tl_chamfer = PackedVector2Array([
		top_left,
		top_left + Vector2(chamfer_size, 0),
		top_left + Vector2(0, chamfer_size)
	])
	draw_colored_polygon(tl_chamfer, chamfer_color)
	
	# Top-right chamfer
	var tr_chamfer = PackedVector2Array([
		top_left + Vector2(PANEL_SIZE, 0),
		top_left + Vector2(PANEL_SIZE - chamfer_size, 0),
		top_left + Vector2(PANEL_SIZE, chamfer_size)
	])
	draw_colored_polygon(tr_chamfer, chamfer_color)
	
	# Bottom-left chamfer
	var bl_chamfer = PackedVector2Array([
		top_left + Vector2(0, PANEL_SIZE),
		top_left + Vector2(chamfer_size, PANEL_SIZE),
		top_left + Vector2(0, PANEL_SIZE - chamfer_size)
	])
	draw_colored_polygon(bl_chamfer, chamfer_color)
	
	# Bottom-right chamfer
	var br_chamfer = PackedVector2Array([
		top_left + Vector2(PANEL_SIZE, PANEL_SIZE),
		top_left + Vector2(PANEL_SIZE - chamfer_size, PANEL_SIZE),
		top_left + Vector2(PANEL_SIZE, PANEL_SIZE - chamfer_size)
	])
	draw_colored_polygon(br_chamfer, chamfer_color)
