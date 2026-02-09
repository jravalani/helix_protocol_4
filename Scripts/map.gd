extends Node2D
@onready var playable_area: ColorRect = $BackgroundBoundary/PlayableArea
@onready var background_boundary: ColorRect = $BackgroundBoundary

# Size of the dark border in PIXELS (stays constant on screen)
@export var fog_border_pixels: int = 100  # Adjust this value

func _ready() -> void:
	# Dark gloomy overlay
	background_boundary.color = Color(0, 0, 0, 0.8)  # Dark and gloomy
	background_boundary.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	
	# The transparent hole (playable area)
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	playable_area.material = mat
	playable_area.color = Color.WHITE
	
	SignalBus.increase_map_size.connect(update_map_visuals)
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	setup_outer_frame()
	update_map_visuals(GameData.current_map_size)

func setup_outer_frame() -> void:
	# Cover the entire viewport
	var viewport_size = get_viewport_rect().size
	background_boundary.size = viewport_size
	background_boundary.position = -viewport_size / 2.0

func _on_viewport_resized() -> void:
	# Recalculate when window is resized
	update_map_visuals(GameData.current_map_size)

func update_map_visuals(new_rect: Rect2i) -> void:
	# Get current viewport size
	var viewport_size = get_viewport_rect().size
	
	# Update background to cover viewport
	background_boundary.size = viewport_size
	background_boundary.position = -viewport_size / 2.0
	
	# The playable area is the viewport MINUS the fixed fog border
	var playable_size = viewport_size - Vector2(fog_border_pixels * 2, fog_border_pixels * 2)
	
	# Center it in the viewport
	playable_area.position = Vector2(fog_border_pixels, fog_border_pixels)
	playable_area.size = playable_size
	
	queue_redraw()

func _draw() -> void:
	# Optional: Draw frames at the edge of the fog
	var viewport_size = get_viewport_rect().size
	var half_size = viewport_size / 2.0
	
	# Outer edge (at viewport edge)
	var outer_rect = Rect2(-half_size, viewport_size)
	draw_rect(outer_rect, Color(1, 1, 1, 0.2), false, 2.0)
	
	# Inner edge (where playable area starts)
	var inner_pos = -half_size + Vector2(fog_border_pixels, fog_border_pixels)
	var inner_size = viewport_size - Vector2(fog_border_pixels * 2, fog_border_pixels * 2)
	var inner_rect = Rect2(inner_pos, inner_size)
	draw_rect(inner_rect, Color(1, 1, 1, 0.6), false, 3.0)
