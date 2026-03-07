extends Building

class_name Hub

@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoLabel
@onready var backlog_label: Label = $MarginContainer/VBoxContainer/BacklogLabel

@onready var request_interval: float = 2.0  # Will be updated dynamically
@onready var oxygen_demand_per_timer: int = 1


@onready var smoke_particle_effect1: GPUParticles2D = $SmokeParticleEffect
@onready var smoke_particle_effect2: GPUParticles2D = $SmokeParticleEffect2

@onready var left_cloud: GPUParticles2D = $LeftCloud
@onready var right_cloud: GPUParticles2D = $RightCloud

var oxygen_backlog: int = 0
var oxygen_in_flight: int = 0
var max_oxygen_capacity: int = 10
var request_timer: Timer

var assigned_vents: int = 0

var is_fractured: bool = false

var utilization_responsiveness := 0.2

var base_request_interval: float = 15.0  # was 6.0
var min_interval: float = 4.0            
var max_interval: float = 20.0           

var _dead_pulse_tween: Tween = null

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			#check for fractured
			if is_fractured:
				#check if total data is more than cost
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
					# some sound effect or anything an alert from notification UI
			else:
				print("Hub is Online.")
				_spawn_floating_label("Hub Online.", Color("8b92a3"))


func _spawn_floating_label(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(-30, -40)  # local space, above hub center
	label.self_modulate = Color(1, 1, 1, 1)  # ignore parent modulate
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
	request_interval *= randf_range(0.85, 1.15)
	request_interval = calculate_dynamic_request_interval()
	
	setup_request_timer()
	update_ui()
	
	SignalBus.check_fractures.connect(on_check_fracture)

func setup_request_timer():
	request_timer = Timer.new()
	request_timer.wait_time = request_interval
	request_timer.timeout.connect(_on_request_timer_timeout)
	add_child(request_timer)
	request_timer.start(randf_range(0.0, request_interval))

func update_ui():
	backlog_label.text = "Backlog: %d" % oxygen_backlog

func calculate_dynamic_request_interval() -> float:
	var vents = get_tree().get_nodes_in_group("vents")
	var connected_vents = 0
	
	for vent in vents:
		if vent.is_connected_to_network:
			connected_vents += 1
	
	# Demand driven purely by connected vents
	# More connections = faster requests = busier network
	var connection_multiplier = 1.0
	if connected_vents <= 1:
		connection_multiplier = 1.5    # barely any supply — slow (30s)
	elif connected_vents <= 3:
		connection_multiplier = 1.2    # getting started (24s)
	elif connected_vents <= 6:
		connection_multiplier = 1.0    # normal (20s)
	elif connected_vents <= 12:
		connection_multiplier = 0.75   # well connected (15s)
	elif connected_vents <= 20:
		connection_multiplier = 0.55   # busy network (11s)
	else:
		connection_multiplier = 0.4    # bustling (8s)
	
	# Backlog regulation — if hub is drowning, slow down requests
	var backlog_multiplier = 1.0
	if oxygen_backlog > 20:
		backlog_multiplier = 1.4
	elif oxygen_backlog > 12:
		backlog_multiplier = 1.2
	
	var final_interval = base_request_interval * connection_multiplier * backlog_multiplier
	return clamp(final_interval, min_interval, max_interval)

func _on_request_timer_timeout():
	# On timer timeout, hub will demand for oxygen, currently it will demand 1
	# but later on we will add the burst demands as well.
	var vents = get_tree().get_nodes_in_group("vents")
	var total_vents = vents.size()
	var connected_vents = 0
	
	for vent in vents:
		if vent.is_connected_to_network:
			connected_vents += 1
	
	var oxygen_demand = 1
	
	if connected_vents > 1:
		var r = randf()
		if r < 0.12:          # 12% chance
			oxygen_demand = 3
		elif r < 0.35:        # 23% chance (0.12 to 0.35)
			oxygen_demand = 2
	# else: 65% chance for oxygen_demand = 1
	
	oxygen_backlog += oxygen_demand
	var net_demand = oxygen_backlog - oxygen_in_flight
	
	if net_demand > 0:
		var candidates = []
		
		for vent in vents:
			if vent.is_connected_to_network and vent.get_current_capacity() < vent.get_max_capacity():
				var start_id = GameData.get_cell_id(vent.entrance_cell)
				var end_id = GameData.get_cell_id(entrance_cell)
				
				if GameData.astar.has_point(start_id) and GameData.astar.has_point(end_id):
					var path = GameData.astar.get_id_path(start_id, end_id)
					if path.size() > 0:
						candidates.append({
							"node": vent,
							"distance": path.size()
						})
		
		candidates.sort_custom(func(a, b): return a.distance < b.distance)
		
		for entry in candidates:
			var vent = entry.node
			
			while net_demand > 0 and vent.can_send_oxygen_packet_to(self):
				oxygen_in_flight += 1
				net_demand -= 1
				
			if net_demand <= 0:
				break
	
	# Interval for the next request
	var base_interval = calculate_dynamic_request_interval()

	# --- Utilization Feedback ---
	var target_util = lerp(0.5, 0.7, GameData.current_pressure / 100.0)
	var current_util = GameData.average_vent_utilization

	var error = target_util - current_util

	# Small multiplicative adjustment
	var factor := 1.0

	if error > 0:
		# UNDER-utilized → push harder
		factor = 1.0 - error * 0.35
	else:
		# OVER-utilized → relax slowly
		factor = 1.0 - error * 0.15

	factor = clamp(factor, 0.8, 1.2)

	request_interval = lerp(request_interval, base_interval * factor, 0.3)
	request_interval = clamp(request_interval, min_interval, max_interval)
	request_timer.wait_time = request_interval
	request_timer.start()
	update_ui()

func receive_oxygen_packet() -> void:
	if is_fractured:
		return
	
	oxygen_backlog = max(0, oxygen_backlog - 1)
	oxygen_in_flight = max(0, oxygen_in_flight - 1)
	ResourceManager.add_score()
	update_ui()
	

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
	oxygen_in_flight = 0
	request_timer.stop()

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
	request_timer.start()
	
	smoke_particle_effect1.restart()
	smoke_particle_effect2.restart()
#endregion
