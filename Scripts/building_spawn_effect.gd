extends Node2D
class_name BuildingSpawnEffect

# Call this as a one-shot effect when building spawns
static func create_at(pos: Vector2, parent: Node, building_size: Vector2 = Vector2(64, 64)) -> void:
	var effect = BuildingSpawnEffect.new()
	effect.global_position = pos
	parent.add_child(effect)
	effect.play_effect(building_size)

func play_effect(building_size: Vector2) -> void:
	_create_smoke_burst(building_size)
	_create_dust_cloud(building_size)
	_create_impact_flash(building_size)
	
	# Auto-cleanup after effect finishes
	await get_tree().create_timer(2.0).timeout
	queue_free()

# ─────────────────────────────────────────────
# Main smoke rising upward
# ─────────────────────────────────────────────
func _create_smoke_burst(building_size: Vector2) -> void:
	var smoke = GPUParticles2D.new()
	smoke.name = "SmokeBurst"
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 0.8  # Most particles spawn at once
	
	# More particles for bigger buildings
	var particle_count = int(building_size.x / 8)
	smoke.amount = clamp(particle_count, 8, 20)
	smoke.lifetime = 1.5
	
	var material = ParticleProcessMaterial.new()
	
	# Emit upward from base of building
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(building_size.x * 0.4, 4, 0)
	material.direction = Vector3(0, -1, 0)  # Upward
	material.spread = 25.0
	
	# Speed
	material.initial_velocity_min = 40.0
	material.initial_velocity_max = 80.0
	
	# Gravity (negative = rise)
	material.gravity = Vector3(0, -30, 0)
	material.damping_min = 1.0
	material.damping_max = 2.0
	
	# Scale up as smoke rises
	material.scale_min = 0.5
	material.scale_max = 1.0
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0, 0.3))
	scale_curve.add_point(Vector2(0.5, 1.0))
	scale_curve.add_point(Vector2(1, 1.5))
	material.scale_curve = scale_curve
	
	# Color: gray smoke fading out
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.6, 0.6, 0.65, 0.8))  # Gray
	gradient.add_point(0.5, Color(0.5, 0.5, 0.55, 0.5))
	gradient.add_point(1.0, Color(0.4, 0.4, 0.45, 0.0))  # Fade out
	material.color_ramp = gradient
	
	# Turbulence for organic look
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 3.0
	material.turbulence_noise_scale = 2.0
	
	smoke.process_material = material
	
	# Smoke texture - soft cloud
	smoke.texture = _create_smoke_texture()
	
	add_child(smoke)

# ─────────────────────────────────────────────
# Dust spreading outward on ground
# ─────────────────────────────────────────────
func _create_dust_cloud(building_size: Vector2) -> void:
	var dust = GPUParticles2D.new()
	dust.name = "DustCloud"
	dust.emitting = true
	dust.one_shot = true
	dust.explosiveness = 1.0  # All at once
	dust.amount = int(building_size.x / 4)
	dust.lifetime = 0.8
	
	var material = ParticleProcessMaterial.new()
	
	# Emit radially outward
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 8.0
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0  # All directions
	
	# Fast burst outward
	material.initial_velocity_min = 60.0
	material.initial_velocity_max = 120.0
	material.radial_accel_min = -30.0
	material.radial_accel_max = -50.0
	
	# Gravity pulls down
	material.gravity = Vector3(0, 80, 0)
	material.damping_min = 5.0
	material.damping_max = 10.0
	
	# Small particles
	material.scale_min = 0.3
	material.scale_max = 0.8
	
	# Color: brown/gray dust
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.5, 0.45, 0.4, 0.9))  # Brown dust
	gradient.add_point(0.3, Color(0.45, 0.4, 0.35, 0.6))
	gradient.add_point(1.0, Color(0.4, 0.35, 0.3, 0.0))
	material.color_ramp = gradient
	
	dust.process_material = material
	dust.texture = _create_smoke_texture()
	
	add_child(dust)

# ─────────────────────────────────────────────
# Flash effect on impact
# ─────────────────────────────────────────────
func _create_impact_flash(building_size: Vector2) -> void:
	var flash = Sprite2D.new()
	flash.name = "ImpactFlash"
	
	# Create white flash texture
	var img = Image.create(int(building_size.x), int(building_size.y), false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	flash.texture = ImageTexture.create_from_image(img)
	
	# Center it
	flash.offset = -building_size / 2
	
	# Animate: bright → fade out
	flash.modulate = Color(1.5, 1.5, 1.5, 0.6)
	
	add_child(flash)
	
	# Fade out quickly
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.15)
	tween.tween_callback(flash.queue_free)

# ─────────────────────────────────────────────
# Helper: Create smoke texture
# ─────────────────────────────────────────────
func _create_smoke_texture() -> GradientTexture2D:
	var texture = GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.WHITE)
	gradient.add_point(0.7, Color(1, 1, 1, 0.5))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	texture.gradient = gradient
	
	return texture
