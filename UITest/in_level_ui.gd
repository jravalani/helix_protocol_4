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


@onready var vent_button: Button = $MarginContainer2/FlowContainer/SpawnVent
@onready var hub_button: Button = $MarginContainer2/FlowContainer/SpawnHub

var is_fast_speed: bool = false

func _ready() -> void:
	update_hub_debug_info()
	update_button_labels()

func _process(delta: float) -> void:
	pressure_phase_label.text = "Pressure Phase: " + str(GameData.current_pressure_phase)
	current_hub_count.text = "Total Hubs: " + str(GameData.current_hub_count)
	current_vent_count.text = "Total Vents: " + str(GameData.current_vent_count)
	backlog_debug.text = "Total Backlog: %d" % GameData.total_hub_backlog
	avg_vent_util.text = "Avg Vent Utilization: %0.2f" % GameData.average_vent_utilization
	shield_health_debug.text = "Shield Integrity: %0.1f%%" % GameData.hull_schield_integrity

	var director = get_node_or_null("/root/Main/Director")
	if director:
		director_timers.text = "Hubs: %d/%d | Vents: %d/%d" % [
			GameData.current_hub_count, GameData.MAX_HUBS,
			GameData.current_vent_count, GameData.MAX_VENTS
		]

func update_hub_debug_info():
	var hub_info_text = "--- ACTIVE HUBS (%d) ---\n" % get_tree().get_nodes_in_group("hubs").size()

	for hub in get_tree().get_nodes_in_group("hubs"):
		if hub is Hub:
			var pos = hub.entrance_cell
			var backlog = hub.oxygen_backlog
			var packets = hub.packets_this_window
			var cap = hub._get_cap()
			var window_left = Hub.RATE_WINDOW - hub.window_timer

			hub_info_text += "ID: %s | Backlog: %d | Window: %d/%d (resets in %.1fs)\n" % [
				pos, backlog, packets, cap, window_left
			]

			if hub.is_rate_limited:
				hub_info_text += "  >> [RATE LIMITED]\n"
			if hub.is_fractured:
				hub_info_text += "  >> [FRACTURED - OFFLINE]\n"

	hub_stats.text = hub_info_text

func update_button_labels() -> void:
	var hub_cost = GameData.HUB_SPAWN_BASE_COST + (GameData.current_hub_count * GameData.HUB_SPAWN_COST_INCREMENT)
	var vent_cost = GameData.VENT_SPAWN_BASE_COST + (GameData.current_vent_count * GameData.VENT_SPAWN_COST_INCREMENT)
	
	vent_button.text = "+Vent (%d)" % vent_cost
	hub_button.text = "+Hub (%d)" % hub_cost

func _on_spawn_hub_pressed() -> void:
	ResourceManager.spawn_hub()
	update_button_labels()

func _on_spawn_vent_pressed() -> void:
	ResourceManager.spawn_vent()
	update_button_labels()

func _on_upgrade_pipes_pressed() -> void:
	ResourceManager.upgrade_pipes()

func _on_hull_shield_pressed() -> void:
	ResourceManager.upgrade_hull_shield()

func _on_repair_zone_pressed(zone_id: int) -> void:
	ResourceManager.reinforce_zone(zone_id)

func _on_data_reserve_pressed() -> void:
	ResourceManager.reserve_data_for_auto_repairs()

func _on_auto_repair_toggled(toggled_on: bool) -> void:
	GameData.auto_repair_enabled = toggled_on
	if toggled_on:
		auto_repair_button.modulate = Color(0.2, 1.0, 0.2)
	else:
		auto_repair_button.modulate = Color(1.0, 1.0, 1.0)

func _on_one_sec_timer_timeout() -> void:
	update_hub_debug_info()
	if GameData.auto_repair_enabled:
		ResourceManager.process_auto_repair()

func _on_tech_tree_pressed() -> void:
	SignalBus.open_rocket_menu.emit()
