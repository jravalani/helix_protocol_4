extends Node2D
class_name ScanSweep

## Reusable ATLAS diagnostic scan sweep effect
## Used for spawning buildings, revealing UI elements, etc.

signal sweep_complete
signal sweep_reached_target

## Configuration
@export var sweep_speed: float = 800.0  # pixels per second
@export var scan_line_thickness: float = 3.0
@export var scan_line_color: Color = Color(1.0, 0.0, 1.0, 0.6)  # Magenta
@export var target_position: Vector2 = Vector2.ZERO  # Where the sweep needs to reach
@export var auto_start: bool = false

## Internal state
var scan_line: ColorRect
var is_sweeping: bool = false
var start_y: float = 0.0
var current_y: float = 0.0
var target_reached: bool = false

func _ready() -> void:
	create_scan_line()
	
	if auto_start:
		start_sweep()

func create_scan_line() -> void:
	scan_line = ColorRect.new()
	scan_line.color = scan_line_color
	scan_line.size = Vector2(get_viewport_rect().size.x * 2, scan_line_thickness)
	scan_line.position = Vector2(-get_viewport_rect().size.x / 2, 0)
	add_child(scan_line)

func start_sweep(from_y: float = 0.0) -> void:
	start_y = from_y
	current_y = from_y
	scan_line.position.y = start_y
	is_sweeping = true
	target_reached = false

func _process(delta: float) -> void:
	if not is_sweeping:
		return
	
	# Move scan line down
	current_y += sweep_speed * delta
	scan_line.position.y = current_y
	
	# Check if we've reached the target position
	if not target_reached and current_y >= target_position.y:
		target_reached = true
		sweep_reached_target.emit()
	
	# Check if sweep is complete (off screen or past a certain point)
	if current_y > get_viewport_rect().size.y:
		complete_sweep()

func complete_sweep() -> void:
	is_sweeping = false
	sweep_complete.emit()
	# Clean up after a short delay
	await get_tree().create_timer(0.1).timeout
	queue_free()

## Quick spawn for building reveals
static func create_for_building(spawn_position: Vector2, parent: Node, building_size: Vector2i = Vector2i(1, 1)) -> ScanSweep:
	var sweep = ScanSweep.new()
	parent.add_child(sweep)
	
	# Position the sweep effect
	sweep.global_position = Vector2.ZERO
	sweep.target_position = spawn_position
	
	# Faster sweep for buildings
	sweep.sweep_speed = 1200.0
	
	# Calculate start position (slightly above the spawn point)
	var start_offset = building_size.y * GameData.CELL_SIZE.y + 100
	sweep.start_sweep(spawn_position.y - start_offset)
	
	return sweep
