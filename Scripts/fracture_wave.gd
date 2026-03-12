extends Node2D

const RING_COUNT := 3
const RING_DELAY := 0.15
const START_RADIUS := 1200.0
const RING_POINTS := 64
const DURATION := 3.0
const NOISE_AMOUNT := 25.0

func _ready() -> void:
	SignalBus.fracture_wave.connect(spawn_wave)

func spawn_wave() -> void:
	SignalBus.ui_wake_up.emit()
	# Camera shake at wave start
	SignalBus.camera_shake.emit(0.5, 8.0)
	
	for i in range(RING_COUNT):
		await get_tree().create_timer(i * RING_DELAY).timeout
		_spawn_wave_group()

func _spawn_wave_group() -> void:
	var container := Node2D.new()
	container.global_position = Vector2.ZERO + Vector2(GameData.CELL_SIZE)
	add_child(container)

	# ── Layer 1: outer soft haze ring ──
	_add_ring(container, START_RADIUS + 60.0, 18.0, Color("1a0a1f55"), false)

	# ── Layer 2: main energy band ──
	_add_ring(container, START_RADIUS, 6.0, Color("2d0a2dcc"), true)

	# ── Layer 3: inner crack line ──
	_add_ring(container, START_RADIUS - 40.0, 2.0, Color("ff00ffaa"), false)

	# ── Radial lightning cracks ──
	_add_lightning_cracks(container)

	# Scale contract to center
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(container, "scale", Vector2(0.0, 0.0), DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Fade in last 30% of travel
	t.tween_property(container, "modulate:a", 0.0, DURATION * 0.3)\
		.set_delay(DURATION * 0.7)\
		.set_trans(Tween.TRANS_QUAD)

	# Second shake when wave arrives at center
	t.tween_callback(func(): 
		SignalBus.camera_shake.emit(0.4, 6.0)
		SignalBus.fracture_wave_impact.emit()  # triggers heat haze
	).set_delay(DURATION)

	t.tween_callback(container.queue_free).set_delay(DURATION + 0.1)

func _add_ring(container: Node2D, radius: float, width: float, color: Color, noisy: bool) -> void:
	var ring := Line2D.new()
	ring.width = width
	ring.default_color = color
	ring.z_index = 100
	ring.begin_cap_mode = Line2D.LINE_CAP_NONE
	ring.end_cap_mode = Line2D.LINE_CAP_NONE
	ring.joint_mode = Line2D.LINE_JOINT_ROUND

	for i in range(RING_POINTS + 1):
		var angle := (float(i) / float(RING_POINTS)) * TAU
		var r := radius
		if noisy:
			r += randf_range(-NOISE_AMOUNT, NOISE_AMOUNT)
		ring.add_point(Vector2(cos(angle), sin(angle)) * r)

	# Color shift from deep plum to magenta over duration
	var ct := create_tween()
	ct.tween_property(ring, "default_color", Color("ff00ff"), DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	container.add_child(ring)

func _add_lightning_cracks(container: Node2D) -> void:
	var crack_count := 8
	for i in range(crack_count):
		var angle := (float(i) / float(crack_count)) * TAU + randf_range(-0.2, 0.2)
		var dir := Vector2(cos(angle), sin(angle))

		var crack := Line2D.new()
		crack.width = 1.5
		crack.default_color = Color("e0aaff99")
		crack.z_index = 101
		crack.begin_cap_mode = Line2D.LINE_CAP_ROUND
		crack.end_cap_mode = Line2D.LINE_CAP_ROUND

		# Crack extends inward from the ring edge
		var start := dir * START_RADIUS
		var end := dir * (START_RADIUS - randf_range(60.0, 140.0))
		crack.add_point(start)
		crack.add_point(end)
		container.add_child(crack)

		# Flicker the crack on and off
		_flicker_crack(crack)

func _flicker_crack(crack: Line2D) -> void:
	var flicker_count := randi_range(3, 6)
	var t := create_tween()
	for i in range(flicker_count):
		t.tween_property(crack, "modulate:a", randf_range(0.3, 1.0), 0.08)
		t.tween_property(crack, "modulate:a", 0.0, 0.08)
