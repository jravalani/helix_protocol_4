extends Node2D

@onready var ignition_burst: GPUParticles2D = $IgnitionBurst
@onready var exhaust_flame: GPUParticles2D = $ExhaustFlame
@onready var exhaust_smoke: GPUParticles2D = $ExhaustSmoke
@onready var ground_smoke: GPUParticles2D = $GroundSmoke

# How long the sustained fire/smoke emitters run while the rocket ascends
const SUSTAIN_DURATION := 3.5

func play() -> void:
	# One-shot bursts fire immediately at ignition
	ignition_burst.emitting = true
	ground_smoke.emitting = true

	# Sustained plumes keep emitting for the full ascent
	exhaust_flame.emitting = true
	exhaust_smoke.emitting = true

	# Cut the sustained emitters once the rocket has cleared the pad
	await get_tree().create_timer(SUSTAIN_DURATION).timeout
	exhaust_flame.emitting = false
	exhaust_smoke.emitting = false

	# Wait for the last smoke particles to fully fade before cleanup
	await get_tree().create_timer(exhaust_smoke.lifetime + 0.5).timeout
	queue_free()
