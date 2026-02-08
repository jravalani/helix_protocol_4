extends Node2D
class_name NewRoadTile

@onready var road_base: Line2D = $RoadBase
@onready var road_outline: Line2D = $RoadOutline

var cell: Vector2i
var manual_connections: Array[Vector2i] = []
var is_permanent: bool = false
var is_entrance: bool = false

func set_cell(c : Vector2i):
	cell = c
	
func get_cell() -> Vector2i:
	return cell

func _ready() -> void:
	#SignalBus.on_road_updated.connect(_on_road_updated)
	
	road_base.position = Vector2.ZERO
	road_outline.position = Vector2.ZERO
	
	# THE FIX: Force all outlines to a lower layer than all bases
	road_outline.z_index = 0
	road_base.z_index = 1

func add_connection(direction: Vector2i) -> void:
	if not manual_connections.has(direction):
		manual_connections.append(direction)
		update_visuals()

func remove_connection(direction: Vector2i) -> void:
	if manual_connections.has(direction):
		manual_connections.erase(direction)
		update_visuals()

func update_visuals() -> void:
	# clear everythin
	road_base.clear_points()
	road_outline.clear_points()
	
	if manual_connections.is_empty():
		_draw_independent_segment(Vector2(-2,0), Vector2(2,0))
		return
	
	# draw each arm independently
	for direction in manual_connections:
		var start_point = Vector2.ZERO
		var end_point = Vector2(direction) * GameData.CELL_SIZE / 2.0
		
		_draw_independent_segment(start_point, end_point)

## Helper to draw a segment without connecting it to the previous one
func _draw_independent_segment(start: Vector2, end: Vector2):
	
	road_outline.add_point(start)
	road_outline.add_point(end)
	
	road_base.add_point(start)
	road_base.add_point(end)
