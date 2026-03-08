extends Building

class_name Hub

# ── Rate limit caps per 60s window, tweak here ──────────────────
const CAP_LEVEL_0 := 40
const CAP_LEVEL_1 := 50
const CAP_LEVEL_2 := 60
const CAP_LEVEL_3 := 70
const RATE_WINDOW  := 60.0  # seconds

@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoLabel
@onready var backlog_label: Label = $MarginContainer/VBoxContainer/BacklogLabel

@onready var smoke_particle_effect1: GPUParticles2D = $SmokeParticleEffect
@onready var smoke_particle_effect2: GPUParticles2D = $SmokeParticleEffect2

@onready var left_cloud: GPUParticles2D = $LeftCloud
@onready var right_cloud: GPUParticles2D = $RightCloud

var oxygen_backlog: int = 0
var upgrade_level: int = 0
var assigned_vents: int = 0

var packets_this_window: int = 0
var window_timer: float = 0.0
var is_rate_limited: bool = false

var is_fractured: bool = false
var _dead_pulse_tween: Tween = null

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_fractured:
				if GameData.total_data > 100:
					GameData.total_data -= 100
					ResourceManager.resources_updated.emit(
						GameData.current_pipe_count,
						GameData.total_data,
						GameData.data_reserve_for_auto_repairs
					)
					repair()
					get_viewport().set_input_as_handled()
				else:
					print("Insufficient Data")
					_spawn_floating_label("Insufficient Data!", Color("d946ef"))
			else:
				print("Hub is Online.")
				_spawn_floating_label("Hub Online.", Color("8b92a3"))

func _spawn_floating_label(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(-30, -40)
	label.self_modulate = Color(1, 1, 1, 1)
	add_child(label)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 30, 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8)
	t.tween_callback(label.queue_free).set_delay(0.8)

func _ready():
	left_cloud.restart()
	right_cloud.restart()

	SignalBus.camera_shake.emit(0.50, 6.0)
	SignalBus.building_spawned.emit(entrance_cell, Vector2i(-99, -99))

	cell_type = "HUB"
	# Stagger window timers so all hubs don't reset simultaneously
	window_timer = randf_range(0.0, RATE_WINDOW)

	update_ui()
	SignalBus.check_fractures.connect(on_check_fracture)

func _get_cap() -> int:
	match upgrade_level:
		0: return CAP_LEVEL_0
		1: return CAP_LEVEL_1
		2: return CAP_LEVEL_2
		3: return CAP_LEVEL_3
		_: return CAP_LEVEL_0

func _process(delta: float) -> void:
	if is_fractured:
		return
	window_timer += delta
	if window_timer >= RATE_WINDOW:
		window_timer = 0.0
		packets_this_window = 0
		is_rate_limited = false

func update_ui():
	backlog_label.text = "Backlog: %d" % oxygen_backlog

func receive_oxygen_packet() -> void:
	if is_fractured:
		return
	if is_rate_limited:
		# Hub is full for this window — reject, vent will handle cleanup via _exit_tree
		return

	oxygen_backlog = max(0, oxygen_backlog - 1)
	packets_this_window += 1
	ResourceManager.add_score()
	update_ui()
	#_hum()

	if packets_this_window >= _get_cap():
		is_rate_limited = true

#func _hum() -> void:
	#var t := create_tween()
	#t.tween_property(self, "scale", Vector2(1.04, 1.04), 0.07).set_ease(Tween.EASE_OUT)
	#t.tween_property(self, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_IN_OUT)



#region Fracture Check
func on_check_fracture() -> void:
	if is_fractured:
		return
	
	var chance = calculate_fracture_chance()
	if randf() < chance:
		fracture()

func calculate_fracture_chance() -> float:
	# fracture chance depends on both current pressure and hull integrity
	var base_chance = 0.03
	
	# first get the pressure modifier. this will be added to base chance
	var pressure_modifier = (GameData.current_pressure / 100.0) * 0.8 #should tinker with this number later on
	
	# shield multiplier increases or decreases the final_chance value depending on the current
	# shield integrity and the level of hull shield.
	var shield_multiplier = GameData.get_hull_shield_multiplier()
	var final_chance = (base_chance + pressure_modifier) * shield_multiplier
	
	return max(0.001, final_chance)


func fracture() -> void:
	is_fractured = true
	oxygen_backlog = 0
	packets_this_window = 0
	is_rate_limited = false

	# Flicker like losing power, then go dark
	var flicker := create_tween()
	for i in range(4):
		flicker.tween_property(self, "modulate", Color("4a0e1f"), 0.08)
		flicker.tween_property(self, "modulate", Color.WHITE, 0.06)
	flicker.tween_property(self, "modulate", Color("1a0a1f"), 0.2)

	await flicker.finished
	
	smoke_particle_effect1.emitting = false
	smoke_particle_effect2.emitting = false
	
	_start_dead_pulse()

func _start_dead_pulse() -> void:
	if not is_fractured:
		return
	_dead_pulse_tween = create_tween().set_loops()
	_dead_pulse_tween.tween_property(self, "modulate", Color("2d0a2d"), 1.2)
	_dead_pulse_tween.tween_property(self, "modulate", Color("1a0a1f"), 1.2)

func repair() -> void:
	is_fractured = false

	# Kill the dead pulse loop
	if _dead_pulse_tween:
		_dead_pulse_tween.kill()
		_dead_pulse_tween = null

	# Reboot flicker — accelerating back to life
	var reboot := create_tween()
	reboot.tween_property(self, "modulate", Color("4a0e1f"), 0.12)
	reboot.tween_property(self, "modulate", Color("1a0a1f"), 0.10)
	reboot.tween_property(self, "modulate", Color("6b1a4f"), 0.09)
	reboot.tween_property(self, "modulate", Color("1a0a1f"), 0.08)
	reboot.tween_property(self, "modulate", Color("a855f7"), 0.07)  # plum
	reboot.tween_property(self, "modulate", Color("1a0a1f"), 0.06)
	reboot.tween_property(self, "modulate", Color("d946ef"), 0.05)  # bright magenta flash
	reboot.tween_property(self, "modulate", Color.WHITE,     0.3)   # settle to normal

	await reboot.finished
	smoke_particle_effect1.restart()
	smoke_particle_effect2.restart()
#endregion
