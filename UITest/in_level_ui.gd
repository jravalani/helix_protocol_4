extends Control

@onready var auto_repair_button: Button = %AutoRepair

# Add these @onready references for your new debug labels
@onready var pressure_phase_label: Label = $PanelContainer/VBoxContainer/PressurePhase
@onready var backlog_debug: Label = $PanelContainer/VBoxContainer/BacklogDebug
@onready var avg_vent_util: Label = $PanelContainer/VBoxContainer/AverageVentUtilization
@onready var shield_health_debug: Label = $PanelContainer/VBoxContainer/ShieldHealth
@onready var director_timers: Label = $PanelContainer/VBoxContainer/DirectorTimers
@onready var hub_stats: Label = $PanelContainer/VBoxContainer/HubStats
@onready var current_hub_count: Label = $PanelContainer/VBoxContainer/CurrentHubCount
@onready var current_vent_count: Label = $PanelContainer/VBoxContainer/CurrentVentCount
@onready var reinforce_panel_container: PanelContainer = %PanelContainer

@onready var vent_button: Button = %SpawnVent
@onready var hub_button: Button = %SpawnHub

var is_fast_speed: bool = false
var panel_open := false

# Signal handlers for reinforce buttons (moved before _ready)
func _on_reinforce_core() -> void:
	ResourceManager.reinforce_zone(0)

func _on_reinforce_inner() -> void:
	ResourceManager.reinforce_zone(1)

func _on_reinforce_outer() -> void:
	ResourceManager.reinforce_zone(2)

func _on_reinforce_frontier() -> void:
	ResourceManager.reinforce_zone(3)

func _ready() -> void:
	# Connect all reinforce panel signals
	reinforce_panel_container.reinforce_core_pressed.connect(_on_reinforce_core)
	reinforce_panel_container.reinforce_inner_pressed.connect(_on_reinforce_inner)
	reinforce_panel_container.reinforce_outer_pressed.connect(_on_reinforce_outer)
	reinforce_panel_container.reinforce_frontier_pressed.connect(_on_reinforce_frontier)
	
	update_hub_debug_info()
	update_button_labels()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if panel_open:
			# Check if click is outside the panel
			var panel_rect = reinforce_panel_container.get_global_rect()
			var click_pos = event.position
			
			if not panel_rect.has_point(click_pos):
				_on_reinforce_zone_panel_pressed()  # Close the panel
				get_viewport().set_input_as_handled()  # Prevent the click from doing anything else

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
	
	# Update button states every frame based on current data
	update_button_states()
	
	if panel_open:
		reinforce_panel_container.update_button_states()
		
func update_button_states() -> void:
	var hub_cost = GameData.HUB_SPAWN_BASE_COST + (GameData.current_hub_count * GameData.HUB_SPAWN_COST_INCREMENT)
	var vent_cost = GameData.VENT_SPAWN_BASE_COST + (GameData.current_vent_count * GameData.VENT_SPAWN_COST_INCREMENT)
	
	vent_button.disabled = GameData.total_data < vent_cost
	hub_button.disabled = GameData.total_data < hub_cost

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

func _on_reinforce_zone_panel_pressed() -> void:
	var tween = create_tween()
	
	if panel_open:
		# Close: slide down
		tween.tween_property(reinforce_panel_container, "position:y", 136, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		panel_open = false
	else:
		# Open: slide up
		tween.tween_property(reinforce_panel_container, "position:y", -326, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		panel_open = true

func _on_reinforce_zone_pressed(zone_id: int) -> void:
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
