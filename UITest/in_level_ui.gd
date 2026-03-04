extends Control

@onready var auto_repair_button: Button = $MarginContainer2/FlowContainer/AutoRepair

# Add these @onready references for your new debug labels
@onready var pressure_phase_label: Label = $PanelContainer/VBoxContainer/PressurePhase
@onready var backlog_debug: Label = $PanelContainer/VBoxContainer/BacklogDebug
@onready var avg_vent_util: Label = $PanelContainer/VBoxContainer/AverageVentUtilization
@onready var shield_health_debug: Label = $PanelContainer/VBoxContainer/ShieldHealth
@onready var director_timers: Label = $PanelContainer/VBoxContainer/DirectorTimers
@onready var hub_stats: Label = $PanelContainer/VBoxContainer/HubStats
@onready var current_hub_count: Label = $PanelContainer/VBoxContainer/CurrentHubCount
@onready var current_vent_count: Label = $PanelContainer/VBoxContainer/CurrentVentCount

var is_fast_speed: bool = false
# Called when the node enters the scene tree for the first time.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Existing pressure updates
	pressure_phase_label.text = "Pressure Phase: " + str(GameData.current_pressure_phase)
	
	current_hub_count.text = "Total Hubs: " + str(GameData.current_hub_count)
	current_vent_count.text = "Total Vents: " + str(GameData.current_vent_count) 

	# New System Metrics for Debugging
	# Shows the total backlog the Director uses for dynamic intervals
	backlog_debug.text = "Total Backlog: %d" % GameData.total_hub_backlog 
	
	# Shows how hard the Vents are working (0.0 to 1.0)
	avg_vent_util.text = "Avg Vent Utilization: %0.2f" % GameData.average_vent_utilization 
	
	# Shows remaining shield health before base fracture chances apply
	shield_health_debug.text = "Shield Integrity: %0.1f%%" % GameData.hull_schield_integrity 
	
	# Track the Director's internal timers (if you have a reference to the Director node)
	# This helps see if spawns are stuck or working too fast
	var director = get_node_or_null("/root/Main/Director") # Update path as needed
	if director:
		director_timers.text = "Next Vent: %.1fs | Next Hub: %s" % [
		director.vent_timer,
		director.hub_spawn_eta
	]

func update_hub_debug_info():
	var hub_info_text = "--- ACTIVE HUBS (%d) ---\n" % get_tree().get_nodes_in_group("hubs").size()
	
	# Use the group to ensure we only process each building once
	for hub in get_tree().get_nodes_in_group("hubs"):
		if hub is Hub:
			# Grid location (the 3x2 anchor point)
			var pos = hub.entrance_cell 
			
			# Current request speed (affected by pressure/backlog logic)
			var interval = hub.request_interval
			
			# Current status
			var backlog = hub.oxygen_backlog
			var in_flight = hub.oxygen_in_flight
			
			# Formatting the string for the debug label
			hub_info_text += "ID: %s | Interval: %0.2fs | Backlog: %d | InFlight: %d\n" % [
				pos, interval, backlog, in_flight
			]
			
			# Visual warning if a Hub is near failure
			if hub.is_fractured:
				hub_info_text += "  >> [FRACTURED - OFFLINE]\n"
	
	hub_stats.text = hub_info_text


func _on_upgrade_pipes_pressed() -> void:
	ResourceManager.upgrade_pipes()

func _on_hull_shield_pressed() -> void:
	ResourceManager.upgrade_hull_shield()

func _on_repair_zone_pressed(zone_id: int) -> void:
	ResourceManager.reinforce_zone(zone_id)

func _on_data_reserve_pressed() -> void:
	ResourceManager.reserve_data_for_auto_repairs()

#func _on_speed_button_pressed() -> void:
	#print("speed toggle")
	#is_fast_speed = !is_fast_speed
	#
	#if is_fast_speed:
		#Engine.time_scale = 4.0
		#speed_button.text = "Speed: 4x"
		#speed_button.modulate =  Color(1.5, 1.5, 1.5, 1.0)
	#else:
		#Engine.time_scale = 1.0
		#speed_button.text = "Speed: 1x"
		#speed_button.modulate = Color.WHITE

func _on_auto_repair_toggled(toggled_on: bool) -> void:
	GameData.auto_repair_enabled = toggled_on
	
	# Green for "Active/Safe", Red or White for "Off/Danger"
	if toggled_on:
		auto_repair_button.modulate = Color(0.2, 1.0, 0.2) # Soft Green
	else:
		auto_repair_button.modulate = Color(1.0, 1.0, 1.0) # Reset to Default


func _on_one_sec_timer_timeout() -> void:
	update_hub_debug_info()
	if GameData.auto_repair_enabled:
		ResourceManager.process_auto_repair()


func _on_tech_tree_pressed() -> void:
	SignalBus.open_rocket_menu.emit()
