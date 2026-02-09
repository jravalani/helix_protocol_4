extends PathFollow2D

@export var speed: float = 100.0
var target_building: Vector2i
var starting_building: Vector2i
var is_returning: bool = false

signal arrived_home

func _ready():
	# For testing: We will start moving as soon as we are born
	# loops = false ensures the car doesn't go in circles forever
	loop = false 

func _process(delta):
	# Progress is a built-in property of PathFollow2D
	# Adding to it moves the car along the curve
	if progress_ratio < 1.0:
		progress += speed * delta
	else:
		if is_returning == false:
			print("Car arrived at: ", target_building)
			# find workplace and tell it to lower the shipment backlog count
			var workplace = GameData.building_grid.get(target_building)
			if workplace:
				print("Found building: ", workplace.name)
				workplace.fulfill_request()
			else:
				print("Grid is empty on this cell!")
			
			# head back home
			is_returning = true
			setup_path(target_building, starting_building)
		else:
			arrived_home.emit()
			ResourceManager.add_score()
			get_parent().queue_free()

## THE GPS REQUEST: This is where the AStar map is used
func setup_path(start_cell: Vector2i, end_cell: Vector2i):
	
	starting_building = start_cell
	target_building = end_cell
	
	var start_id = GameData.get_cell_id(start_cell)
	var end_id = GameData.get_cell_id(end_cell) 
	
	var path_points = GameData.astar.get_point_path(start_id, end_id) 
	
	if path_points.size() > 1: 
		var new_curve = Curve2D.new() 
		var lane_offset_dist = 6.0 # Pixels to the right
		
		for i in range(path_points.size()):
			var current_point = path_points[i]
			var offset = Vector2.ZERO
			
			# We calculate direction based on the NEXT point to know where "right" is
			if i < path_points.size() - 1:
				var next_point = path_points[i+1]
				var direction = (next_point - current_point).normalized()
				
				# The "Abacus" Trick: Perpendicular vector for Right-Hand Traffic
				# (x, y) -> (-y, x) rotates 90 degrees clockwise in Godot's 2D space
				var right_dir = Vector2(-direction.y, direction.x)
				offset = right_dir * lane_offset_dist
			else:
				# For the very last point, use the direction from the previous point 
				# so the offset remains consistent at the destination
				var prev_point = path_points[i-1]
				var direction = (current_point - prev_point).normalized()
				var right_dir = Vector2(-direction.y, direction.x)
				offset = right_dir * lane_offset_dist
				
			new_curve.add_point(current_point + offset) 
			
		get_parent().curve = new_curve 
		progress = 0
