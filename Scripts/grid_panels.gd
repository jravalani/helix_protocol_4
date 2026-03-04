extends Node2D

@onready var camera_2d: Camera2D = $"../Camera2D"

const CELL_SIZE = 64
const CELL_SIZE_VEC = Vector2(64, 64)
const PANEL_SIZE = 320  # 2x2 cells = one panel

# Industrial color scheme
var panel_line_color = Color(0.4, 0.45, 0.5, 0.3)  # Lighter, more metallic
var panel_corner_color = Color(0.5, 0.55, 0.6, 0.5)  # Corner rivets/bolts
var panel_fill_color = Color(0.32, 0.32, 0.32, 0.05)  # Subtle panel fill

func _ready():
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
	
	## Draw heatmap first (your existing code)
	#var drawn_count = 0
	#for tile in GameData.influence_grid:
		#var score = GameData.influence_grid[tile]
		#if abs(score) < 0.1:
			#continue
		#
		#var color: Color
		#if score > 0:
			#var intensity = clamp(score / 150.0, 0.0, 1.0)
			#color = Color(0.0, 0.5 + intensity * 0.5, 0.3 + intensity * 0.7)
		#else:
			#var intensity = clamp(abs(score) / 150.0, 0.0, 1.0)
			#color = Color(0.8 + intensity * 0.2, 0.3 - intensity * 0.3, 0.0)
		#
		#color.a = clamp(abs(score) / 150.0, 0.15, 0.6)
		#
		#var rect = Rect2(Vector2(tile) * CELL_SIZE_VEC, CELL_SIZE_VEC)
		#draw_rect(rect, color)
		#drawn_count += 1
	
	# Draw industrial panels (128x128)
	for x in range(start_x, end_x + PANEL_SIZE, PANEL_SIZE):
		for y in range(start_y, end_y + PANEL_SIZE, PANEL_SIZE):
			_draw_industrial_panel(Vector2(x, y))

func _draw_industrial_panel(top_left: Vector2) -> void:
	var panel_rect = Rect2(top_left, Vector2(PANEL_SIZE, PANEL_SIZE))
	
	# Seed random based on panel position (so it's consistent)
	var panel_seed = int(top_left.x / PANEL_SIZE) * 1000 + int(top_left.y / PANEL_SIZE)
	seed(panel_seed)
	
	# Base dirty metal
	draw_rect(panel_rect, Color(0.25, 0.23, 0.21, 0.5))
	
	# Random repair patches (different colored rectangles)
	var num_patches = randi() % 3  # 0-2 patches per panel
	for i in range(num_patches):
		var patch_size = Vector2(randf_range(20, 50), randf_range(20, 50))
		var patch_pos = top_left + Vector2(
			randf_range(10, PANEL_SIZE - patch_size.x - 10),
			randf_range(10, PANEL_SIZE - patch_size.y - 10)
		)
		# Slightly different colored patches (mismatched repairs)
		var patch_color = Color(
			randf_range(0.2, 0.35),
			randf_range(0.18, 0.3),
			randf_range(0.15, 0.25),
			0.4
		)
		draw_rect(Rect2(patch_pos, patch_size), patch_color)
		# Weld marks around patch
		draw_rect(Rect2(patch_pos, patch_size), Color(0.6, 0.4, 0.2, 0.6), false, 1.5)
	
	# Scratched, worn borders
	var border_color = Color(0.35, 0.3, 0.25, 0.6)
	draw_rect(panel_rect, border_color, false, 3.0)
	
	# Sparse rivets (scavenged parts)
	var rivet_color = Color(0.45, 0.4, 0.35, 0.7)
	var inset = 15.0
	draw_circle(top_left + Vector2(inset, inset), 4.0, rivet_color)
	draw_circle(top_left + Vector2(PANEL_SIZE - inset, PANEL_SIZE - inset), 4.0, rivet_color)
