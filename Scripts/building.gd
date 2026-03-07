extends Area2D
class_name Building

@export var grid_size := Vector2i(3, 3)

@onready var entrance_marker: Marker2D = $EntranceMarker

var cell_type: String = ""
var entrance_cell: Vector2i
var type_properties: Dictionary = {}
var top_left_px: Vector2

const CELL := 64
const HALF_CELL := 32

func _ready():
	pass

# Override in child classes for different positioning logic
func get_top_left_px(step: float) -> Vector2:
	return global_position

func register_building(building: Node2D):
	if entrance_marker == null:
		entrance_marker = $EntranceMarker

	var step = GameData.CELL_SIZE.x
	top_left_px = building.get_top_left_px(step)

	var start_cell = Vector2i(floor(top_left_px.x / step), floor(top_left_px.y / step))

	var ent_pos = entrance_marker.global_position
	entrance_cell = Vector2i(floor(ent_pos.x / step), floor(ent_pos.y / step))

	# Register footprint
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var current_cell = start_cell + Vector2i(x, y)
			GameData.building_grid[current_cell] = self

	print("Registered %s at %s" % [type_properties.get("name", "Building"), start_cell])
	GameData.add_navigation_point(entrance_cell)

func get_entrance_cell() -> Vector2i:
	return entrance_cell

func is_cell_an_entrance(cell: Vector2i) -> bool:
	var b = GameData.building_grid.get(cell)
	if b is Building:
		return b.entrance_cell == cell
	return false
