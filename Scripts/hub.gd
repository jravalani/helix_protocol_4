extends Building

class_name Hub

@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoLabel
@onready var backlog_label: Label = $MarginContainer/VBoxContainer/BacklogLabel
@onready var request_interval: float = 2
@onready var oxygen_demand_per_timer: int = 1


var oxygen_backlog: int = 0
var oxygen_in_flight: int = 0
var max_oxygen_capacity: int = 10
var request_timer: Timer

var assigned_vents: int = 0

var is_fractured: bool = false


func _ready():
	cell_type = "HUB"
	
	setup_request_timer()
	update_ui()
	
	SignalBus.check_fractures.connect(on_check_fracture)

func setup_request_timer():
	request_timer = Timer.new()
	request_timer.wait_time = request_interval
	request_timer.timeout.connect(_on_request_timer_timeout)
	add_child(request_timer)
	request_timer.start()

func update_ui():
	backlog_label.text = "Backlog: %d" % oxygen_backlog

func _on_request_timer_timeout():
	# On timer timeout, hub will demand for oxygen, currently it will demand 1
	# but later on we will add the burst demands as well.
	oxygen_backlog += oxygen_demand_per_timer
	var net_demand = oxygen_backlog - oxygen_in_flight
	
	if net_demand > 0:
		var vents = get_tree().get_nodes_in_group("vents")
		var candidates = []
		
		for vent in vents:
			if vent.get_current_capacity() < vent.get_max_capacity():
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
			
			while vent.get_current_capacity() < vent.get_max_capacity() and net_demand > 0:
				# over here add the burst chances. pressure dependent.
				vent.send_oxygen_packet_to(self)
				oxygen_in_flight += 1
				net_demand -= 1
				
			if net_demand <= 0:
				break
	
	# Interval for the next request
	request_timer.wait_time = request_interval
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
