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
@onready var tech_tree: Button = %TechTree
@onready var reinforce_zone: Button = %ReinforceZonePanel


var panel_open := false

# ── Tutorial state ────────────────────────────────────────────────
enum TutorialStep { CONNECT_PIPES, WAIT_FOR_DATA, EXPAND_VENT, PLACE_HUB, SAVE_GAME, DONE }
var tutorial_step: TutorialStep = TutorialStep.CONNECT_PIPES
# ── Tooltip data ─────────────────────────────────────────────────
var TOOLTIPS := {
	"vent": {
		"title": "Spawn Vent",
		"desc": "Deploy a new vent node to generate more packets.",
		"cost": ""
	},
	"hub": {
		"title": "Spawn Hub",
		"desc": "Add a new hub to generate more data.",
		"cost": ""
	},
	"pipes": {
		"title": "Upgrade Pipes",
		"desc": "Increase pipe capacity and flow rate. Higher tiers increase packet speeds.",
		"cost": ""
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
		"cost": "100"
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

	# ── Tutorial: create objective label ─────────────────────────
	# ── Tutorial: fire opening objective as a permanent notification ──
	NotificationManager.notify(
		"Connect the Vent to the Hub with Pipes to start your network.\nBuild pipes by left click and drawing on the grid.",
		NotificationManager.Type.OBJECTIVE,
		"OBJECTIVE",
		40
	)

	# ── Tutorial: hide + disable all economy buttons until player progresses ──
	hub_button.hide();          hub_button.disabled          = true
	vent_button.hide();         vent_button.disabled         = true
	pipe_button.hide();         pipe_button.disabled         = true
	hull_shield_button.hide();  hull_shield_button.disabled  = true
	data_reserve_button.hide(); data_reserve_button.disabled = true
	auto_repair_button.hide();  auto_repair_button.disabled  = true
	tech_tree.hide(); tech_tree.disabled = true
	reinforce_zone.hide(); reinforce_zone.disabled = true

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

	_tick_tutorial()
	update_button_states()

	if panel_open:
		reinforce_panel_container.update_button_states()

func _tick_tutorial() -> void:
	if tutorial_step == TutorialStep.DONE:
		return

	match tutorial_step:
		TutorialStep.CONNECT_PIPES:
			# Advance once the first packet reaches a hub (total_data > 0)
			if GameData.total_data > 0:
				tutorial_step = TutorialStep.WAIT_FOR_DATA
				vent_button.show()
				vent_button.disabled = false
				# Unlock 2x speed now — player will likely be waiting for data to build up
				var top_panel = get_node_or_null("/root/Main/CanvasLayer/TopPanel")
				if top_panel and top_panel.has_method("unlock_speed_button"):
					top_panel.unlock_speed_button()
				NotificationManager.notify(
					"Network is live! Data is flowing.\nWait for enough Data to afford a Vent.",
					NotificationManager.Type.OBJECTIVE,
					"NETWORK LIVE",
					30.0
				)
				NotificationManager.notify(
					"Tip: Use the >> button to speed up time while you wait for Data to accumulate.",
					NotificationManager.Type.INFO,
					"SPEED UP",
					20.0
				)

		TutorialStep.WAIT_FOR_DATA:
			if GameData.total_data >= GameData.current_vent_spawn_cost:
				tutorial_step = TutorialStep.EXPAND_VENT
				NotificationManager.notify(
					"You can afford a Vent! Deploy one using the Spawn Vent button.\nExpand your network to increase Data flow.",
					NotificationManager.Type.OBJECTIVE,
					"DEPLOY A VENT",
					30.0
				)

		# --- MODIFIED STEP ---
		TutorialStep.EXPAND_VENT:
			if GameData.current_vent_count >= 2:
				tutorial_step = TutorialStep.PLACE_HUB # Move to Hub placement instead of DONE
				hub_button.show()
				hub_button.disabled = false
				NotificationManager.notify(
					"Expand your reach. Place a secondary Hub Node to stabilize the sector.",
					NotificationManager.Type.OBJECTIVE,
					"FINAL LINK",
					30.0
				)

		# --- NEW STEP ---
		TutorialStep.PLACE_HUB:
			if GameData.current_hub_count >= 1: # Assuming they start with 1
				tutorial_step = TutorialStep.SAVE_GAME
		
		TutorialStep.SAVE_GAME:
			var top_panel = get_node_or_null("/root/Main/CanvasLayer/TopPanel")
			if top_panel and top_panel.has_method("unlock_speed_button"):
				top_panel.unlock_uplink_button()
			tutorial_step = TutorialStep.DONE
			_unlock_full_game()
			NotificationManager.notify(
				"Save the game state by clicking the up-link button.\nThat is the only way to save the game on your system.",
				NotificationManager.Type.OBJECTIVE,
				"SAVE GAME",
				30.0
			)

func _unlock_full_game() -> void:
	# 1. Finalize State
	tutorial_step = TutorialStep.DONE
	
	# 2. Safety: Reset time scale 
	# (In case they finished during the 10s repair window)
	Engine.time_scale = 1.0
	var top_panel = get_node_or_null("/root/Main/CanvasLayer/TopPanel")
	if top_panel and top_panel.has_method("sync_speed_button_state"):
		top_panel.sync_speed_button_state()
	
	# 3. Reveal and Enable All Gameplay Systems
	# Consolidating the list of buttons you previously had in EXPAND_VENT
	var gameplay_buttons = [
		hub_button,
		pipe_button,
		hull_shield_button,
		data_reserve_button,
		auto_repair_button,
		tech_tree,
		reinforce_zone
	]
	
	for btn in gameplay_buttons:
		if btn:
			btn.show()
			btn.disabled = false
	
	# 4. Final Success Notification
	# Using the Magenta 'OBJECTIVE' type for the final milestone
	NotificationManager.notify(
		"Network established. All systems are now online.\nManage pressure, expand carefully, and survive.",
		NotificationManager.Type.OBJECTIVE,
		"STATION ONLINE",
		30.0
	)

func update_button_states() -> void:
	var hub_cost  = GameData.HUB_SPAWN_BASE_COST  + (GameData.current_hub_count  * GameData.HUB_SPAWN_COST_INCREMENT)
	var vent_cost = GameData.VENT_SPAWN_BASE_COST + (GameData.current_vent_count * GameData.VENT_SPAWN_COST_INCREMENT)

	var hub_maxed    = GameData.current_hub_count >= GameData.MAX_HUBS
	var vent_maxed   = GameData.current_vent_count >= GameData.MAX_VENTS
	var pipes_maxed  = GameData.current_pipe_upgrade_level >= GameData.MAX_PIPE_UPGRADES
	var shield_maxed = GameData.current_hull_shield_level >= GameData.MAX_HULL_SHIELD_UPGRADES

	# During tutorial, only update states for buttons that are visible/unlocked.
	# Buttons that are still hidden stay hidden — don't re-enable them here.
	if tutorial_step == TutorialStep.DONE or tutorial_step == TutorialStep.PLACE_HUB:
		hub_button.disabled         = hub_maxed    or GameData.total_data < hub_cost
		pipe_button.disabled        = pipes_maxed  or GameData.total_data < GameData.PIPE_UPGRADE_COSTS[min(GameData.current_pipe_upgrade_level, GameData.MAX_PIPE_UPGRADES - 1)]
		hull_shield_button.disabled = shield_maxed or GameData.total_data < GameData.HULL_SHIELD_UPGRADE_COSTS[min(GameData.current_hull_shield_level, GameData.MAX_HULL_SHIELD_UPGRADES - 1)]
		data_reserve_button.disabled = false
		auto_repair_button.disabled = GameData.data_reserve_for_auto_repairs <= 0 and not GameData.auto_repair_enabled

	if tutorial_step != TutorialStep.CONNECT_PIPES:
		vent_button.disabled = vent_maxed or GameData.total_data < vent_cost

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
