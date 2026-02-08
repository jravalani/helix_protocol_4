extends Node2D
#
#noob AI for director
#1. spawn a building every 30-45 seconds.
#2. spawn a house nearby building every 20 seconds. 

@onready var workplace_scene = preload("res://Scenes/workplace.tscn")
@onready var house_scene = preload("res://Scenes/house.tscn")

@onready var building_timer: Timer = $BuildingTimer
@onready var map_timer: Timer = $TemporaryMapTimer

@export var temporary_spawn_radius = 5

func _ready() -> void:
	print("Center of screen: ", floor(get_viewport().size / GameData.CELL_SIZE.x) / 2)
	building_timer.start()
	map_timer.start()

func _on_building_timer_timeout() -> void:
	attempt_spawn()

func attempt_spawn() -> void:
	var center_of_screen_cell = Vector2i(0, 0)

	var random_offset = Vector2i(
		randi_range(-temporary_spawn_radius, temporary_spawn_radius),
		randi_range(-temporary_spawn_radius, temporary_spawn_radius)
	)
	var target_cell = center_of_screen_cell + random_offset
	spawn_building(target_cell)

	building_timer.start()

func spawn_building(cell: Vector2i) -> void:
	var scene = house_scene if randf() > 0.5 else workplace_scene
	var b = scene.instantiate()
	
	if is_area_clear(cell, b.grid_size):
		
		# 1. Get the pixel coordinate of the top-left of the 'cell'
		var origin = Vector2(cell) * GameData.CELL_SIZE.x
		
		# 2. Calculate the center based on grid_size
		# For 1x1: (1 * 64) / 2 = 32
		# For 3x3: (3 * 64) / 2 = 96
		# For 5x2: X=(5*64)/2=160, Y=(2*64)/2=64
		var offset = (Vector2(b.grid_size) * GameData.CELL_SIZE.x) / 2.0
		
		# 3. Apply it
		b.position = origin + offset
		$"../Entities".add_child(b)
		
		# If it's a workplace, you can set its unique speed here
		if b is Workplace: # Assuming you used 'class_name Workplace'
			b.shipment_interval = randf_range(5.0, 20.0)
			
		SignalBus.map_changed.emit.call_deferred()
		print("Spawned a ", b.grid_size, " building!")
		
		if randf() > 0.8:
			temporary_spawn_radius += 1
			print("Radius of spawn increased!! New Radius is: ", temporary_spawn_radius)
	else:
		# 4. If it doesn't fit, we must delete the "draft" to save memory
		print("Area blocked for size: ", b.grid_size)
		b.queue_free()

func is_area_clear(start_cell: Vector2i, size: Vector2i) -> bool:
	for x in range(-1, size.x + 1):
		for y in range(-1, size.y + 1):
			if GameData.grid.has(start_cell + Vector2i(x, y)):
				return false
	return true


func _on_temporary_map_timer_timeout() -> void:
	GameData.increase_map_size()
	map_timer.start()
