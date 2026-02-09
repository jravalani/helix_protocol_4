#extends CanvasLayer
#
#@onready var fog_overlay: ColorRect = $FogOverlay
#
#@export var fog_border_top: int = 60
#@export var fog_border_bottom: int = 120
#@export var fog_border_left: int = 100
#@export var fog_border_right: int = 100
#@export var fog_color: Color = Color(0.1, 0.1, 0.1, 0.9)
#
#func _ready() -> void:
	#layer = 1
	#fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#
	## Setup Shader
	#var shader = Shader.new()
	#shader.code = """
#shader_type canvas_item;
#
#uniform vec2 viewport_size;
#uniform float border_top;
#uniform float border_bottom;
#uniform float border_left;
#uniform float border_right;
#uniform vec4 fog_color : source_color;
#
#void fragment() {
	#// UV goes from 0.0 to 1.0, convert to pixels
	#vec2 pixel_pos = UV * viewport_size;
	#
	#// Check if we're in any border area
	#bool in_border = pixel_pos.x < border_left || 
					 #pixel_pos.x > viewport_size.x - border_right ||
					 #pixel_pos.y < border_top || 
					 #pixel_pos.y > viewport_size.y - border_bottom;
	#
	#if (in_border) {
		#COLOR = fog_color; // Show fog in borders
	#} else {
		#discard; // Clear center (playable area)
	#}
#}
#"""
	#
	#var shader_material = ShaderMaterial.new()
	#shader_material.shader = shader
	#fog_overlay.material = shader_material
	#fog_overlay.material.set_shader_parameter("fog_color", fog_color)
	#
	#get_tree().root.size_changed.connect(_update_fog)
	#_update_fog()
#
#func _update_fog() -> void:
	#var viewport_size = get_viewport().get_visible_rect().size
	#fog_overlay.size = viewport_size
	#fog_overlay.position = Vector2.ZERO
	#
	#fog_overlay.material.set_shader_parameter("viewport_size", viewport_size)
	#fog_overlay.material.set_shader_parameter("border_top", float(fog_border_top))
	#fog_overlay.material.set_shader_parameter("border_bottom", float(fog_border_bottom))
	#fog_overlay.material.set_shader_parameter("border_left", float(fog_border_left))
	#fog_overlay.material.set_shader_parameter("border_right", float(fog_border_right))
#
## Optional: Set borders dynamically
#func set_borders(top: int, bottom: int, left: int, right: int) -> void:
	#fog_border_top = top
	#fog_border_bottom = bottom
	#fog_border_left = left
	#fog_border_right = right
	#_update_fog()


extends CanvasLayer

@onready var fog_overlay: ColorRect = $FogOverlay

@export var fog_border_top: int = 60
@export var fog_border_bottom: int = 120
@export var fog_border_left: int = 100
@export var fog_border_right: int = 100
@export var fog_color: Color = Color(0.1, 0.1, 0.1, 0.9)

func _ready() -> void:
	layer = 1
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Setup Shader
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 viewport_size;
uniform float border_top;
uniform float border_bottom;
uniform float border_left;
uniform float border_right;
uniform vec4 fog_color : source_color;
void fragment() {
	vec2 pixel_pos = UV * viewport_size;
	
	bool in_border = pixel_pos.x < border_left || 
	                 pixel_pos.x > viewport_size.x - border_right ||
	                 pixel_pos.y < border_top || 
	                 pixel_pos.y > viewport_size.y - border_bottom;
	
	if (in_border) {
		COLOR = fog_color;
	} else {
		discard;
	}
}
"""
	
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	fog_overlay.material = shader_material
	fog_overlay.material.set_shader_parameter("fog_color", fog_color)
	
	get_tree().root.size_changed.connect(_update_fog)
	_update_fog()

func _update_fog() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	fog_overlay.size = viewport_size
	fog_overlay.position = Vector2.ZERO
	
	fog_overlay.material.set_shader_parameter("viewport_size", viewport_size)
	fog_overlay.material.set_shader_parameter("border_top", float(fog_border_top))
	fog_overlay.material.set_shader_parameter("border_bottom", float(fog_border_bottom))
	fog_overlay.material.set_shader_parameter("border_left", float(fog_border_left))
	fog_overlay.material.set_shader_parameter("border_right", float(fog_border_right))

func set_borders(top: int, bottom: int, left: int, right: int) -> void:
	fog_border_top = top
	fog_border_bottom = bottom
	fog_border_left = left
	fog_border_right = right
	_update_fog()

# NEW: Get the playable area in grid cells
func get_playable_area_cells() -> Rect2i:
	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	
	if not camera:
		return Rect2i()  # No camera, return empty
	
	# Calculate playable area in screen pixels
	var playable_pixel_min = Vector2(fog_border_left, fog_border_top)
	var playable_pixel_max = Vector2(viewport_size.x - fog_border_right, viewport_size.y - fog_border_bottom)
	var playable_pixel_size = playable_pixel_max - playable_pixel_min
	
	# Convert screen pixels to world pixels
	var canvas_transform = get_viewport().get_canvas_transform()
	var inverse_transform = canvas_transform.affine_inverse()
	
	var world_min = inverse_transform * playable_pixel_min
	var world_max = inverse_transform * playable_pixel_max
	
	# Convert world pixels to grid cells
	var cell_size = GameData.CELL_SIZE.x
	var cell_min = Vector2i(floor(world_min.x / cell_size), floor(world_min.y / cell_size))
	var cell_max = Vector2i(floor(world_max.x / cell_size), floor(world_max.y / cell_size))
	
	return Rect2i(cell_min, cell_max - cell_min)
