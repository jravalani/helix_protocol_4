extends ColorRect

@onready var mat: ShaderMaterial = material

func _ready() -> void:
	mat.set_shader_parameter("strength", 0.0)
	SignalBus.fracture_wave_impact.connect(on_fracture_wave)

func on_fracture_wave() -> void:
	var t := create_tween()
	# Ramp up fast
	t.tween_method(
		func(v: float): mat.set_shader_parameter("strength", v),
		0.0,
		1.0,
		0.2
	)
	# Hold briefly
	t.tween_interval(0.3)
	# Fade out slowly
	t.tween_method(
		func(v: float): mat.set_shader_parameter("strength", v),
		1.0,
		0.0,
		1.5
	)
