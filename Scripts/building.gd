extends Area2D

class_name Building

# @export_enum("HOUSE", "BUILDING") var building_type: String = "BUILDING"
@export var grid_size := Vector2i(3, 3)

@onready var entrance_marker: Marker2D = $EntranceMarker

var cell_type: String = ""
var entrance_cell: Vector2i

const CELL := 64
const HALF_CELL := 32

func _ready():
	register_building()
	print("global position of building in xy: ", global_position.x, global_position.y)

#func register_building():
	#var grid_step = GameData.CELL_SIZE.x 
	#
	## Calculate the building's physical extents
	## We multiply grid_size (e.g., 3x3) by grid_step (64) to get total pixels
	#var half_offset = (Vector2(grid_size) * grid_step) / 2.0
	#
	## Find the top-left corner (start_cell)
	## We subtract the half_offset from the center (global_position)
	#var top_left_pos = global_position - half_offset
	#
	#var start_cell = Vector2i(
		#floor(top_left_pos.x / grid_step),
		#floor(top_left_pos.y / grid_step)
	#)
	#
	## Calculate the entrance cell relative to the global position
	#var global_entrance_pos = global_position + entrance_marker.position
	#entrance_cell = Vector2i(
		#floor(global_entrance_pos.x / grid_step),
		#floor(global_entrance_pos.y / grid_step)
	#)
	#
	## 3. Register the footprint
	#for x in range(grid_size.x):
		#for y in range(grid_size.y):
			#var current_cell = start_cell + Vector2i(x, y)
			#print("Claiming cell: ", current_cell)
			#
			#if current_cell == entrance_cell:
				#if cell_type == GameData.CELL_HOUSE:
					#GameData.grid[current_cell] = GameData.CELL_HOUSE_ENTRANCE
				#else:
					#GameData.grid[current_cell] = GameData.CELL_WORKPLACE_ENTRANCE
			#else:
				#GameData.grid[current_cell] = cell_type
				#
	#print("Registered building type '", cell_type, "' at ", start_cell)
	#GameData.add_navigation_point(entrance_cell)

func register_building():
	var step = GameData.CELL_SIZE.x
	
	# Get the top-left corner by subtracting half the building's size in pixels.
	var top_left_px = global_position - (Vector2(grid_size) * step / 2.0)

	# Just divide by 64. No offsets, no half-cells.
	var start_cell = Vector2i(floor(top_left_px.x / step), floor(top_left_px.y / step))
	
	# Where is the marker? Just divide its global pos by 64.
	var ent_pos = entrance_marker.global_position
	entrance_cell = Vector2i(floor(ent_pos.x / step), floor(ent_pos.y / step))
	
	# 3. Register footprint
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var current_cell = start_cell + Vector2i(x, y)

			if current_cell == entrance_cell:
				GameData.grid[current_cell] = (
					GameData.CELL_HOUSE_ENTRANCE
					if cell_type == GameData.CELL_HOUSE
					else GameData.CELL_WORKPLACE_ENTRANCE
				)
			else:
				GameData.grid[current_cell] = cell_type

	print("Registered building type '", cell_type, "' at ", start_cell, " with entrance at ", entrance_cell)
	GameData.add_navigation_point(entrance_cell)


func is_cell_an_entrance(cell: Vector2i) -> bool:
	var data = GameData.grid.get(cell)
	if data == null: return false
	
	# Check State A: The String Label
	if typeof(data) == TYPE_STRING and data == GameData.CELL_WORKPLACE_ENTRANCE:
		return true
		
	# Check State B: The Paved Road
	if data is NewRoadTile and data.is_entrance:
		return true
		
	return false

func is_destination_a_workplace(check_cell: Vector2i) -> bool:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor_data = GameData.grid.get(check_cell + dir)
		
		# 1. First, check if the neighbor is actually a String
		if typeof(neighbor_data) == TYPE_STRING:
			# 2. Now it is safe to compare String to String
			if neighbor_data == GameData.CELL_BUILDING:
				return true
				
	return false
