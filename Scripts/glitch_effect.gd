extends Control
class_name GlitchEffect

## Reusable glitch effect for UI elements
## Attach to Control nodes (pause menu, settings, game over screen, etc.)

## Configuration
@export var enable_glitches: bool = true
@export var glitch_interval: float = 0.4  # Time between glitch attempts
@export var glitch_chance: float = 0.3  # 30% chance per interval
@export var glitch_intensity: float = 1.0  # Multiplier for effect strength

## Targets - automatically finds these if not set
@export var glitch_targets: Array[Control] = []

## Internal
var glitch_timer: float = 0.0
var original_positions: Dictionary = {}
var original_colors: Dictionary = {}

func _ready() -> void:
	# Auto-detect targets if none specified
	if glitch_targets.is_empty():
		find_glitch_targets()
	
	# Store original positions and colors
	for target in glitch_targets:
		original_positions[target] = target.position
		if target is Label:
			original_colors[target] = target.get_theme_color("font_color", "Label")

func find_glitch_targets() -> void:
	# Find all Labels and Buttons in children
	for child in get_children():
		if child is Label or child is Button or child is Control:
			glitch_targets.append(child)
	
	# Also check grandchildren
	for child in get_children():
		for grandchild in child.get_children():
			if grandchild is Label or grandchild is Button:
				glitch_targets.append(grandchild)

func _process(delta: float) -> void:
	if not enable_glitches or glitch_targets.is_empty():
		return
	
	glitch_timer += delta
	if glitch_timer >= glitch_interval:
		glitch_timer = 0.0
		if randf() < glitch_chance:
			apply_random_glitch()

func apply_random_glitch() -> void:
	var glitch_type = randi() % 4
	
	match glitch_type:
		0:
			glitch_position_shift()
		1:
			glitch_opacity_flicker()
		2:
			glitch_color_shift()
		3:
			glitch_scale_pulse()

func glitch_position_shift() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	if not original_positions.has(target):
		return
	
	var shift = Vector2(
		randf_range(-5, 5) * glitch_intensity,
		randf_range(-3, 3) * glitch_intensity
	)
	var original_pos = original_positions[target]
	
	var tween = create_tween()
	tween.tween_property(target, "position", original_pos + shift, 0.05)
	tween.chain().tween_property(target, "position", original_pos, 0.05)

func glitch_opacity_flicker() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	var original_alpha = target.modulate.a
	
	var tween = create_tween()
	tween.tween_property(target, "modulate:a", 0.2, 0.03)
	tween.chain().tween_property(target, "modulate:a", original_alpha, 0.03)

func glitch_color_shift() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	
	# Shift to a random magenta variation
	var shifted_color = Color(
		randf_range(0.8, 1.0),
		randf_range(0.0, 0.3),
		randf_range(0.8, 1.0),
		1.0
	)
	var original_color = Color(1.0, 0.0, 1.0, 1.0)
	
	var tween = create_tween()
	tween.tween_property(target, "modulate", shifted_color, 0.05)
	tween.chain().tween_property(target, "modulate", original_color, 0.05)

func glitch_scale_pulse() -> void:
	if glitch_targets.is_empty():
		return
	
	var target = glitch_targets[randi() % glitch_targets.size()]
	
	var pulse_scale = Vector2(
		randf_range(0.95, 1.05),
		randf_range(0.95, 1.05)
	) * glitch_intensity
	
	var tween = create_tween()
	tween.tween_property(target, "scale", pulse_scale, 0.05)
	tween.chain().tween_property(target, "scale", Vector2.ONE, 0.05)

## Call this for heavy glitches (game over, critical errors)
func trigger_heavy_glitch() -> void:
	for i in range(5):
		apply_random_glitch()
		await get_tree().create_timer(0.1).timeout

## Call this to temporarily increase glitch frequency
func increase_glitch_intensity(duration: float = 5.0) -> void:
	var original_interval = glitch_interval
	var original_chance = glitch_chance
	
	glitch_interval = 0.2
	glitch_chance = 0.6
	
	await get_tree().create_timer(duration).timeout
	
	glitch_interval = original_interval
	glitch_chance = original_chance
