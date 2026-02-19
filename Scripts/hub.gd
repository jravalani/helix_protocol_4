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


func _ready():
	cell_type = "HUB"
	
	setup_request_timer()
	update_ui()

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
	update_ui()
