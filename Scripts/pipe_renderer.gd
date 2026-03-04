extends Node2D

@onready var master_case: Line2D = $MasterCase
@onready var master_outline: Line2D = $MasterOutline
@onready var master_caps: Line2D = $MasterCaps
@onready var master_fracture: Line2D = $MasterFracture

func _ready() -> void:
	SignalBus.map_changed.connect(request_redraw)
	
	# Configuration for seamless lines
	for line in [master_case, master_caps, master_outline]:
		line.begin_cap_mode = Line2D.LINE_CAP_NONE
		line.end_cap_mode = Line2D.LINE_CAP_NONE
		line.joint_mode = Line2D.LINE_JOINT_ROUND
	
	# Configuration for the Pill Ends
	master_caps.begin_cap_mode = Line2D.LINE_CAP_ROUND
	master_caps.end_cap_mode = Line2D.LINE_CAP_ROUND
	master_caps.width = master_case.width
	master_caps.texture = master_case.texture # Ensure it uses your 3-stop gradient

func request_redraw() -> void:
	update_network.call_deferred()
func update_network() -> void:
	for line in [master_case, master_outline, master_caps, master_fracture]:
		line.clear_points()
	
	var road_cells = GameData.road_grid.keys()
	var segments = _get_segments(road_cells)
	
	for segment in segments:
		for i in range(segment.size()):
			var cell = segment[i]
			var pos = GameData.get_cell_center(cell)
			var road_data = GameData.road_grid.get(cell)
			
			if road_data and road_data.is_fractured:
				# Add to the "Broken" line instead of the main line
				master_fracture.add_point(pos)
				# We add INF to the main lines so there is a "gap" where the break is
				master_case.add_point(Vector2.INF)
				master_outline.add_point(Vector2.INF)
			else:
				# Normal pipe drawing
				master_case.add_point(pos)
				master_outline.add_point(pos)
				master_fracture.add_point(Vector2.INF) # Gap in the red line

			if road_data and road_data.manual_connections.size() <= 1:
				_draw_pill_cap(pos)
		
		# Break all lines at the end of the segment
		for line in [master_case, master_outline, master_fracture]:
			line.add_point(Vector2.INF)

func _draw_pill_cap(pos: Vector2) -> void:
	# Placing two points near each other with ROUND CAPS creates a circle
	master_caps.add_point(pos)
	master_caps.add_point(pos + Vector2(0.1, 0))
	master_caps.add_point(Vector2.INF)

# THE MISSING FUNCTION:
func _get_segments(cells: Array) -> Array:
	var segments = []
	var visited = {}
	
	for cell in cells:
		if visited.has(cell): continue
		
		var current_path = []
		var stack = [cell]
		
		while stack.size() > 0:
			var c = stack.pop_back()
			if visited.has(c): continue
			
			visited[c] = true
			current_path.append(c)
			
			# Check neighbors using your manual_connections 
			# to ensure we follow the actual pipe path
			var road_data = GameData.road_grid.get(c)
			if road_data:
				for dir in road_data.manual_connections:
					var neighbor = c + dir
					if GameData.road_grid.has(neighbor) and not visited.has(neighbor):
						stack.append(neighbor)
		
		if current_path.size() > 0:
			segments.append(current_path)
			
	return segments
