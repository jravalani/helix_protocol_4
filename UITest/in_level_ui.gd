extends Control

@onready var pressure_phase_label: Label = $PanelContainer/VBoxContainer/PressurePhase
@onready var backlog_debug: Label = $PanelContainer/VBoxContainer/BacklogDebug
@onready var avg_vent_util: Label = $PanelContainer/VBoxContainer/AverageVentUtilization
@onready var shield_health_debug: Label = $PanelContainer/VBoxContainer/ShieldHealth
@onready var director_timers: Label = $PanelContainer/VBoxContainer/DirectorTimers
@onready var hub_stats: Label = $PanelContainer/VBoxContainer/HubStats
@onready var current_hub_count: Label = $PanelContainer/VBoxContainer/CurrentHubCount
@onready var current_vent_count: Label = $PanelContainer/VBoxContainer/CurrentVentCount
@onready var reinforce_panel_container: PanelContainer = %PanelContainer

# Buttons
@onready var pipe_button: Button        = %UpgradePipes
@onready var data_reserve_button: Button = %DataReserve
@onready var hull_shield_button: Button  = %HullShield
@onready var vent_button: Button         = %SpawnVent
@onready var hub_button: Button          = %SpawnHub
@onready var auto_repair_button: Button  = %AutoRepair

var panel_open := false

# ── Tooltip data ─────────────────────────────────────────────────
const TOOLTIPS := {
	"vent": {
		"title": "Spawn Vent",
		"desc": "Deploy a new vent node to increase oxygen throughput across the network.",
		"cost": "Scales with vent count"
	},
	"hub": {
		"title": "Spawn Hub",
		"desc": "Add a new hub to expand packet routing capacity. Backlog builds if hubs are overwhelmed.",
		"cost": "Scales with hub count"
	},
	"pipes": {
		"title": "Upgrade Pipes",
		"desc": "Increase pipe capacity and flow rate. Higher tiers handle more pressure before fracturing.",
		"cost": "Fixed cost per tier"
	},
	"hull_shield": {
		"title": "Hull Shield",
		"desc": "Reinforce the station hull. Reduces damage taken from pressure spikes and breaches.",
		"cost": "Fixed cost per tier"
	},
	"reinforce": {
		"title": "Reinforce Zone",
		"desc": "Selectively reinforce a pressure zone to reduce its vulnerability to fractures.",
		"cost": "Variable by zone"
	},
	"data_reserve": {
		"title": "Data Reserve",
		"desc": "Allocate data into the repair reserve pool, used by auto repair drones.",
		"cost": "Free — transfers from Data"
	},
	"auto_repair": {
		"title": "Auto Repair",
		"desc": "Toggle automated repair drones. Drains your reserve data to fix fractured pipes instantly.",
		"cost": "Requires: Repair Reserve"
	}
}

# ── Signal handlers for reinforce buttons ────────────────────────

func _on_reinforce_core() -> void:
	ResourceManager.reinforce_zone(0)

func _on_reinforce_inner() -> void:
	ResourceManager.reinforce_zone(1)

func _on_reinforce_outer() -> void:
	ResourceManager.reinforce_zone(2)

func _on_reinforce_frontier() -> void:
	ResourceManager.reinforce_zone(3)

func _ready() -> void:
	reinforce_panel_container.reinforce_core_pressed.connect(_on_reinforce_core)
	reinforce_panel_container.reinforce_inner_pressed.connect(_on_reinforce_inner)
	reinforce_panel_container.reinforce_outer_pressed.connect(_on_reinforce_outer)
	reinforce_panel_container.reinforce_frontier_pressed.connect(_on_reinforce_frontier)

	update_hub_debug_info()
	update_button_labels()
	_connect_tooltips()

func _connect_tooltips() -> void:
	var _connect = func(btn: Button, key: String) -> void:
		btn.mouse_entered.connect(func():
			TooltipManager.show_tooltip(
				TOOLTIPS[key]["title"],
				TOOLTIPS[key]["desc"],
				TOOLTIPS[key]["cost"],
				btn
			)
		)
		btn.mouse_exited.connect(func(): TooltipManager.hide_tooltip())

	_connect.call(vent_button,         "vent")
	_connect.call(hub_button,          "hub")
	_connect.call(pipe_button,         "pipes")
	_connect.call(hull_shield_button,  "hull_shield")
	_connect.call(data_reserve_button, "data_reserve")
	_connect.call(auto_repair_button,  "auto_repair")

	# ReinforceZonePanel button is accessed via its unique name
	var reinforce_btn = get_node_or_null("%ReinforceZonePanel")
	if reinforce_btn:
		_connect.call(reinforce_btn, "reinforce")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if panel_open:
			var panel_rect = reinforce_panel_container.get_global_rect()
			if not panel_rect.has_point(event.position):
				_on_reinforce_zone_panel_pressed()
				get_viewport().set_input_as_handled()

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

	update_button_states()

	if panel_open:
		reinforce_panel_container.update_button_states()

func update_button_states() -> void:
	var hub_cost  = GameData.HUB_SPAWN_BASE_COST  + (GameData.current_hub_count  * GameData.HUB_SPAWN_COST_INCREMENT)
	var vent_cost = GameData.VENT_SPAWN_BASE_COST + (GameData.current_vent_count * GameData.VENT_SPAWN_COST_INCREMENT)

	var hub_maxed    = GameData.current_hub_count >= GameData.MAX_HUBS
	var vent_maxed   = GameData.current_vent_count >= GameData.MAX_VENTS
	var pipes_maxed  = GameData.current_pipe_upgrade_level >= GameData.MAX_PIPE_UPGRADES
	var shield_maxed = GameData.current_hull_shield_level >= GameData.MAX_HULL_SHIELD_UPGRADES

	vent_button.disabled        = vent_maxed   or GameData.total_data < vent_cost
	hub_button.disabled         = hub_maxed    or GameData.total_data < hub_cost
	pipe_button.disabled        = pipes_maxed  or GameData.total_data < GameData.PIPE_UPGRADE_COSTS[min(GameData.current_pipe_upgrade_level, GameData.MAX_PIPE_UPGRADES - 1)]
	hull_shield_button.disabled = shield_maxed or GameData.total_data < GameData.HULL_SHIELD_UPGRADE_COSTS[min(GameData.current_hull_shield_level, GameData.MAX_HULL_SHIELD_UPGRADES - 1)]

	auto_repair_button.disabled = GameData.data_reserve_for_auto_repairs <= 0 and not GameData.auto_repair_enabled

func update_hub_debug_info():
	var hub_info_text = "--- ACTIVE HUBS (%d) ---\n" % get_tree().get_nodes_in_group("hubs").size()
	for hub in get_tree().get_nodes_in_group("hubs"):
		if hub is Hub:
			var pos        = hub.entrance_cell
			var backlog    = hub.oxygen_backlog
			var packets    = hub.packets_this_window
			var cap        = hub._get_cap()
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
	var hub_cost  = GameData.HUB_SPAWN_BASE_COST  + (GameData.current_hub_count  * GameData.HUB_SPAWN_COST_INCREMENT)
	var vent_cost = GameData.VENT_SPAWN_BASE_COST + (GameData.current_vent_count * GameData.VENT_SPAWN_COST_INCREMENT)
	vent_button.text = "+Vent (%d)" % vent_cost
	hub_button.text  = "+Hub (%d)"  % hub_cost

# ── Button callbacks ─────────────────────────────────────────────

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
		tween.tween_property(reinforce_panel_container, "position:y", 136, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		panel_open = false
	else:
		tween.tween_property(reinforce_panel_container, "position:y", -326, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		panel_open = true

func _on_reinforce_zone_pressed(zone_id: int) -> void:
	ResourceManager.reinforce_zone(zone_id)

func _on_data_reserve_pressed() -> void:
	ResourceManager.reserve_data_for_auto_repairs()

func _on_auto_repair_toggled(toggled_on: bool) -> void:
	GameData.auto_repair_enabled = toggled_on
	if toggled_on:
		auto_repair_button.modulate = Color(0.2, 1.0, 0.4)
		auto_repair_button.text = "Auto Repair [ON]"
	else:
		auto_repair_button.modulate = Color(1.0, 1.0, 1.0)
		auto_repair_button.text = "Auto Repair"

func _on_one_sec_timer_timeout() -> void:
	update_hub_debug_info()
	if GameData.auto_repair_enabled:
		ResourceManager.process_auto_repair()

func _on_tech_tree_pressed() -> void:
	SignalBus.open_rocket_menu.emit()
