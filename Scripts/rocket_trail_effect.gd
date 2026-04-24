extends Node2D

@onready var core_flame: GPUParticles2D = $CoreFlame
@onready var outer_glow: GPUParticles2D = $OuterGlow

func play() -> void:
	core_flame.emitting = true
	outer_glow.emitting = true

func stop() -> void:
	core_flame.emitting = false
	outer_glow.emitting = false
	# Let existing particles finish naturally before freeing
	await get_tree().create_timer(outer_glow.lifetime + 0.2).timeout
	queue_free()
