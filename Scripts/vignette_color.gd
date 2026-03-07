extends ColorRect

@onready var mat: ShaderMaterial = material

var phase_tints = {
	0: Color(0.0, 0.0, 0.0, 0.0),      # invisible
	1: Color(0.0, 0.0, 0.0, 0.0),      # invisible
	2: Color(0.1, 0.05, 0.0, 0.05),    # barely warm
	3: Color(0.15, 0.05, 0.0, 0.08),   # slight amber
	4: Color(0.2, 0.05, 0.0, 0.12),    # warm amber
	5: Color(0.25, 0.02, 0.02, 0.18),  # amber to crimson
	6: Color(0.3, 0.0, 0.0, 0.22),     # crimson
	7: Color(0.35, 0.0, 0.0, 0.28),    # deep crimson
	8: Color(0.4, 0.0, 0.0, 0.32),     # oppressive
	9: Color(0.45, 0.0, 0.0, 0.38),    # suffocating
	10: Color(0.5, 0.0, 0.0, 0.45),    # critical
}

var phase_vignettes = {
	0: 0.0, 1: 0.0, 2: 0.0,
	3: 0.1, 4: 0.2, 5: 0.35,
	6: 0.5, 7: 0.6, 8: 0.7,
	9: 0.8, 10: 0.9
}

func _ready() -> void:
	SignalBus.pressure_phase_changed.connect(on_phase_changed)

func on_phase_changed(phase: int) -> void:
	var target_tint: Color = phase_tints.get(phase, Color(0,0,0,0))
	var target_vignette: float = phase_vignettes.get(phase, 0.0)
	
	var t := create_tween()
	t.set_parallel(true)
	t.tween_method(
		func(c: Color): mat.set_shader_parameter("tint_color", c),
		mat.get_shader_parameter("tint_color"),
		target_tint,
		3.0  # slow lerp over 3 seconds
	)
	t.tween_method(
		func(v: float): mat.set_shader_parameter("vignette_strength", v),
		mat.get_shader_parameter("vignette_strength"),
		target_vignette,
		3.0
	)
