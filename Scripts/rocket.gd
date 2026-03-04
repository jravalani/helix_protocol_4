extends Building
class_name Rocket

@onready var segment_1: Sprite2D = $Segment1  # Launchpad
@onready var segment_2: Sprite2D = $Segment2
@onready var segment_3: Sprite2D = $Segment3
@onready var segment_4: Sprite2D = $Segment4
@onready var segment_5: Sprite2D = $Segment5

@onready var shadow_1: Sprite2D = $Shadow1  # Launchpad shadow
@onready var shadow_2: Sprite2D = $Shadow2  # Cumulative: Launchpad + Part1
@onready var shadow_3: Sprite2D = $Shadow3  # Cumulative: Launchpad + Part1 + Part2
@onready var shadow_4: Sprite2D = $Shadow4  # Cumulative: Launchpad + Part1 + Part2 + Part3
@onready var shadow_5: Sprite2D = $Shadow5  # Cumulative: All parts

@onready var segment2_shadow_on_launchpad: Sprite2D = $Segment2_Shadow
@onready var segment3_shadow_on_launchpad: Sprite2D = $Segment3_Shadow
@onready var segment4_shadow_on_launchpad: Sprite2D = $Segment4_Shadow
@onready var segment5_shadow_on_launchpad: Sprite2D = $Segment5_Shadow

const SEGMENT_SCALE = Vector2(0.43, 0.43)
const SHADOW_SCALE = Vector2(0.42, 0.42)

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			print("Need to open the tech tree.")
			SignalBus.open_rocket_menu.emit()
			get_viewport().set_input_as_handled()

func _ready() -> void:
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	
	# Set shadow opacity to 60%
	shadow_1.modulate = Color(1, 1, 1, 0.6)
	shadow_2.modulate = Color(1, 1, 1, 0.6)
	shadow_3.modulate = Color(1, 1, 1, 0.6)
	shadow_4.modulate = Color(1, 1, 1, 0.6)
	shadow_5.modulate = Color(1, 1, 1, 0.6)
	
	# Set segment shadows on launchpad opacity to 60%
	segment2_shadow_on_launchpad.modulate = Color(1, 1, 1, 0.6)
	segment3_shadow_on_launchpad.modulate = Color(1, 1, 1, 0.6)
	segment4_shadow_on_launchpad.modulate = Color(1, 1, 1, 0.6)
	segment5_shadow_on_launchpad.modulate = Color(1, 1, 1, 0.6)
	
	# Initialize visuals based on current phase
	update_rocket_visuals(GameData.current_rocket_phase)

func _on_rocket_segment_purchased(next_phase: int) -> void:
	update_rocket_visuals(next_phase)
	
	# Animate the new segment
	if next_phase >= 1 and next_phase <= 5:
		_animate_new_segment(next_phase)
	
	# Trigger launch when phase 5 is complete
	if next_phase == 5:
		# Delay launch to let the animation finish
		await get_tree().create_timer(0.5).timeout
		launch_rocket()

func update_rocket_visuals(phase: int) -> void:
	# Show ALL segments up to current phase
	segment_1.visible = phase >= 1  # Launchpad always visible once built
	segment_2.visible = phase >= 2
	segment_3.visible = phase >= 3
	segment_4.visible = phase >= 4
	segment_5.visible = phase >= 5
	
	# Hide all ground shadows first
	shadow_1.visible = false
	shadow_2.visible = false
	shadow_3.visible = false
	shadow_4.visible = false
	shadow_5.visible = false
	
	# Hide all segment shadows on launchpad
	segment2_shadow_on_launchpad.visible = false
	segment3_shadow_on_launchpad.visible = false
	segment4_shadow_on_launchpad.visible = false
	segment5_shadow_on_launchpad.visible = false
	
	# Show only the appropriate cumulative shadow for current phase
	match phase:
		1: 
			shadow_1.visible = true  # Just launchpad
		2: 
			shadow_1.visible = true  # Launchpad stays
			shadow_2.visible = true  # Add cumulative shadow
			segment2_shadow_on_launchpad.visible = true
		3:
			shadow_1.visible = true
			shadow_3.visible = true
			segment2_shadow_on_launchpad.visible = true
			segment3_shadow_on_launchpad.visible = true
		4:
			shadow_1.visible = true
			shadow_4.visible = true
			segment2_shadow_on_launchpad.visible = true
			segment3_shadow_on_launchpad.visible = true
			segment4_shadow_on_launchpad.visible = true
		5:
			shadow_1.visible = true
			shadow_5.visible = true
			segment2_shadow_on_launchpad.visible = true
			segment3_shadow_on_launchpad.visible = true
			segment4_shadow_on_launchpad.visible = true
			segment5_shadow_on_launchpad.visible = true

# Animation when new segment appears
func _animate_new_segment(phase: int) -> void:
	var segments = [segment_1, segment_2, segment_3, segment_4, segment_5]
	var shadows = [shadow_1, shadow_2, shadow_3, shadow_4, shadow_5]
	var segment_shadows_on_launchpad = [null, segment2_shadow_on_launchpad, segment3_shadow_on_launchpad, segment4_shadow_on_launchpad, segment5_shadow_on_launchpad]
	
	if phase > 0 and phase <= 5:
		var new_segment = segments[phase - 1]
		var new_shadow = shadows[phase - 1]
		
		# Start animation from 50% of normal scale
		new_segment.scale = SEGMENT_SCALE * 0.5
		new_shadow.scale = SHADOW_SCALE * 0.5
		
		# Tween to full scale
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(new_segment, "scale", SEGMENT_SCALE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(new_shadow, "scale", SHADOW_SCALE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		# Animate segment shadow on launchpad if it exists (phase 2-5)
		if phase >= 2:
			var segment_shadow = segment_shadows_on_launchpad[phase - 1]
			segment_shadow.scale = SHADOW_SCALE * 0.5
			tween.tween_property(segment_shadow, "scale", SHADOW_SCALE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func launch_rocket() -> void:
	print("Initiating Launch Sequence!")
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# SCALE UP the rocket parts (getting bigger as it comes toward camera)
	var final_scale = SEGMENT_SCALE * 3.0  # Grow to 3x size
	tween.tween_property(segment_2, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(segment_3, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(segment_4, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(segment_5, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Fade out the rocket parts as they pass the camera
	tween.tween_property(segment_2, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_property(segment_3, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_property(segment_4, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_property(segment_5, "modulate:a", 0.0, 3.0).set_delay(1.5)
	
	# Immediately hide shadows on launchpad
	segment2_shadow_on_launchpad.visible = false
	segment3_shadow_on_launchpad.visible = false
	segment4_shadow_on_launchpad.visible = false
	segment5_shadow_on_launchpad.visible = false
	
	# Move shadows up and left (100px each)
	var shadow_movement = Vector2(-100, -100)
	
	# Fade out and move ground shadows (2.5 seconds)
	tween.tween_property(shadow_5, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_5, "position", shadow_5.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	
	tween.tween_property(shadow_2, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_2, "position", shadow_2.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	
	tween.tween_property(shadow_3, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_3, "position", shadow_3.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	
	tween.tween_property(shadow_4, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_4, "position", shadow_4.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	
	# Hide shadows after fade completes
	tween.tween_callback(func():
		shadow_5.visible = false
		shadow_2.visible = false
		shadow_3.visible = false
		shadow_4.visible = false
		# Shadow_1 (launchpad) remains visible
	).set_delay(2.5)
	
	# When launch complete
	tween.finished.connect(_on_launch_complete)

func _on_launch_complete() -> void:
	print("Rocket has left the atmosphere!")
	print("You Win!")
	# segment_1 (launchpad) remains on the ground
