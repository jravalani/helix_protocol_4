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

var launch_effect_scene = preload("res://ParticleEffects/rocket_launch_effect.tscn")
const HAZE_SHADER = preload("res://shaders/rocket_haze.gdshader")

var _haze_materials: Array[ShaderMaterial] = []

func _apply_haze_shader() -> void:
	var segs = [segment_2, segment_3, segment_4, segment_5]
	_haze_materials.clear()
	for seg in segs:
		var mat := ShaderMaterial.new()
		mat.shader = HAZE_SHADER
		mat.set_shader_parameter("strength", 0.0)
		mat.set_shader_parameter("speed", 3.0)
		seg.material = mat
		_haze_materials.append(mat)

func _ramp_haze(target_strength: float, duration: float) -> void:
	for mat in _haze_materials:
		var tw := create_tween()
		tw.tween_method(func(v: float): mat.set_shader_parameter("strength", v),
			mat.get_shader_parameter("strength"), target_strength, duration)

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			print("Need to open the tech tree.")
			SignalBus.open_rocket_menu.emit()
			get_viewport().set_input_as_handled()

func _ready() -> void:
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	SignalBus.launch_rocket_requested.connect(_on_launch_requested)
	
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
	
	# Phase 5 just completes the rocket — launch is triggered by the skill tree LAUNCH button

#func _input(event: InputEvent) -> void:
	#if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		#launch_rocket()

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
	# ── Phase 1: Pre-launch buildup (3 seconds) ──────────────────
	_apply_haze_shader()

	# Spawn launch effect early for smoke/particles
	var launch_effect = launch_effect_scene.instantiate()
	launch_effect.global_position = global_position + Vector2(128, 128)
	get_parent().add_child(launch_effect)
	launch_effect.play()

	# Ramp haze wobble up over 2.5s — heat building in the engines
	_ramp_haze(12.0, 2.5)

	# Escalating camera shakes — engines powering up
	SignalBus.camera_shake.emit(0.4, 4.0)
	await get_tree().create_timer(0.8).timeout
	SignalBus.camera_shake.emit(0.5, 7.0)
	await get_tree().create_timer(0.8).timeout
	SignalBus.camera_shake.emit(0.6, 11.0)
	await get_tree().create_timer(0.9).timeout

	# ── Phase 2: Liftoff ─────────────────────────────────────────
	# One final massive shake at ignition
	SignalBus.camera_shake.emit(0.8, 18.0)

	# Kill haze — rocket is gone, no more heat distortion needed
	_ramp_haze(0.0, 0.5)

	var tween = create_tween()
	tween.set_parallel(true)

	# Scale up (coming toward camera)
	var final_scale = SEGMENT_SCALE * 3.0
	tween.tween_property(segment_2, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(segment_3, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(segment_4, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(segment_5, "scale", final_scale, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Fade out as they pass camera
	tween.tween_property(segment_2, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_property(segment_3, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_property(segment_4, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_property(segment_5, "modulate:a", 0.0, 3.0).set_delay(1.5)

	# Shadows
	segment2_shadow_on_launchpad.visible = false
	segment3_shadow_on_launchpad.visible = false
	segment4_shadow_on_launchpad.visible = false
	segment5_shadow_on_launchpad.visible = false

	var shadow_movement = Vector2(-100, -100)
	tween.tween_property(shadow_5, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_5, "position", shadow_5.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(shadow_2, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_2, "position", shadow_2.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(shadow_3, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_3, "position", shadow_3.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(shadow_4, "modulate:a", 0.0, 2.5)
	tween.tween_property(shadow_4, "position", shadow_4.position + shadow_movement, 2.5).set_trans(Tween.TRANS_QUAD)

	tween.tween_callback(func():
		shadow_5.visible = false
		shadow_2.visible = false
		shadow_3.visible = false
		shadow_4.visible = false
	).set_delay(2.5)

	tween.finished.connect(_on_launch_complete, CONNECT_ONE_SHOT)

func _on_launch_requested() -> void:
	if GameData.current_rocket_phase >= 5:
		# 1-second delay so the player sees the rocket before liftoff
		await get_tree().create_timer(1.0).timeout
		launch_rocket()

func _on_launch_complete() -> void:
	WinSceneData.capture()
	SceneTransition.transition_to("res://Scenes/WinScene.tscn", SceneTransition.Type.BEAM)
