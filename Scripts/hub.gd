extends Building

class_name Hub

@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoLabel
@onready var backlog_label: Label = $MarginContainer/VBoxContainer/BacklogLabel
@onready var base_request_interval: float = 6.0
@onready var request_interval: float = 2.0  # Will be updated dynamically
@onready var oxygen_demand_per_timer: int = 1


var oxygen_backlog: int = 0
var oxygen_in_flight: int = 0
var max_oxygen_capacity: int = 10
var request_timer: Timer

var assigned_vents: int = 0

var is_fractured: bool = false

var utilization_responsiveness := 0.2
var min_interval := 2.0
var max_interval := 8.0


func _ready():
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
	"""
	Demand based on BOTH total vents (gentle pressure) 
	AND connected vents (reward for connecting).
	"""
	var base = base_request_interval
	
	var vents = get_tree().get_nodes_in_group("vents")
	var total_vents = vents.size()
	var connected_vents = 0
	
	for vent in vents:
		if vent.is_connected_to_network:
			connected_vents += 1
	
	# 1. BASE DEMAND: Scales with total vents (gentle pressure to connect)
	# This makes demand increase even if vents aren't connected
	var base_demand_multiplier = 1.0
	
	if total_vents <= 3:
		base_demand_multiplier = 1.1
	elif total_vents <= 8:
		base_demand_multiplier = 1.0
	elif total_vents <= 15:
		base_demand_multiplier = 0.85
	elif total_vents <= 25:
		base_demand_multiplier = 0.7
	elif total_vents <= 40:
		base_demand_multiplier = 0.55
	else:
		base_demand_multiplier = 0.4
	
	# 2. CONNECTION BONUS: If you connect vents, you handle demand better
	# This is the REWARD for connecting
	var connection_ratio = float(connected_vents) / max(1, total_vents)
	var connection_bonus = 1.0
	
	if connection_ratio > 0.8:
		connection_bonus = 1.1   # 10% slower requests (breathing room!)
	elif connection_ratio > 0.6:
		connection_bonus = 1.0   # Normal
	elif connection_ratio < 0.4:
		connection_bonus = 0.85  # 15% FASTER (punishment for not connecting!)
	
	# 3. Backlog regulation (always present)
	var backlog_multiplier = 1.0
	if oxygen_backlog > 20:
		backlog_multiplier = 1.4
	elif oxygen_backlog > 12:
		backlog_multiplier = 1.2
	
	var final_interval = base * base_demand_multiplier * connection_bonus * backlog_multiplier
	
	return clamp(final_interval, 2.0, 8.0)
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
	
	if connected_vents > 10:
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
	var base_chance = 0.02
	
	# first get the pressure modifier. this will be added to base chance
	var pressure_modifier = (GameData.current_pressure / 100.0) * 0.8 #should tinker with this number later on
	
	# shield multiplier increases or decreases the final_chance value depending on the current
	# shield integrity and the level of hull shield.
	var shield_multiplier = GameData.get_hull_shield_multiplier()
	var final_chance = (base_chance + pressure_modifier) * shield_multiplier
	
	return max(0.001, final_chance)

func fracture() -> void:
	is_fractured = true
	request_timer.stop()
	print("Hub integrity failed. Shutting Down.")
		
	modulate = Color(1.0, 0.3, 0.3, 0.7)
	print("Failed Integrity Hub is at: ", position / GameData.CELL_SIZE.x)
	
	# emit a signal here if in future we decide to add something related to hub failure.

func repair() -> void:
	is_fractured = false
	request_timer.start()
	modulate = Color.WHITE
	
	# emit a signal here if in futute we decide to start something related to hub repair.

#endregion
