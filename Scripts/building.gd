extends Area2D
class_name Building

@export var grid_size := Vector2i(3, 3)

# NEW: Export building type so it can be set per scene
#@export var building_type: GameData.BuildingType = GameData.BuildingType.VENT

@onready var entrance_marker: Marker2D = $EntranceMarker
@onready var sprite: Sprite2D = $Sprite2D

var cell_type: String = ""
var entrance_cell: Vector2i
var type_properties: Dictionary = {}
var top_left_px: Vector2

const CELL := 64
const HALF_CELL := 32

func _ready():
	#register_building()
	#apply_type_visuals()
	pass

func register_building(building: Node2D):
	if entrance_marker == null:
		entrance_marker = $EntranceMarker

	var step = GameData.CELL_SIZE.x
	if building is Vent:
		top_left_px = building.global_position - (Vector2(grid_size) * step / 2.0)
	else:
		top_left_px = building.global_position
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

#func set_building_type(type: GameData.BuildingType) -> void:
	#"""Set building type and load properties"""
	#building_type = type
	#type_properties = GameData.BUILDING_TYPE_DATA[type]
	#apply_type_visuals()

#func apply_type_visuals() -> void:
	#"""Apply visual style based on type"""
	## Load type properties if not already loaded
	#if type_properties.is_empty() and GameData.BUILDING_TYPE_DATA.has(building_type):
		#type_properties = GameData.BUILDING_TYPE_DATA[building_type]
	#
	#if sprite and type_properties.has("color"):
		#sprite.modulate = type_properties["color"]
		#
		## Add glow
		#if not has_node("PointLight2D"):
			#var light = PointLight2D.new()
			#light.energy = 1.5
			#light.color = type_properties["color"]
			#add_child(light)

func is_cell_an_entrance(cell: Vector2i) -> bool:
	var b = GameData.building_grid.get(cell)
	if b is Building:
		return b.entrance_cell == cell
	return false
