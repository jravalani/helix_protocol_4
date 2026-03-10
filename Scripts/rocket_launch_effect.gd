extends Node2D

@onready var fire_burst: GPUParticles2D = $FireBurst
@onready var smoke_ring: GPUParticles2D = $SmokeRing

func play() -> void:
	fire_burst.emitting = true
	smoke_ring.emitting = true
	
	# Self-destruct after longest-lived particles finish
	await get_tree().create_timer(smoke_ring.lifetime + 0.5).timeout
	queue_free()
