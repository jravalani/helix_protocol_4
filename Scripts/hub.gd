extends Building

class_name Hub

# ── Rate limit caps per 60s window ──────────────────────────────
const CAP_LEVEL_0 := 60
const CAP_LEVEL_1 := 70
const CAP_LEVEL_2 := 80
const CAP_LEVEL_3 := 90
const RATE_WINDOW  := 60.0

# ── Node References ─────────────────────────────────────────────
@onready var smoke_particle_effect1: GPUParticles2D = $SmokeParticleEffect
@onready var smoke_particle_effect2: GPUParticles2D = $SmokeParticleEffect2
@onready var left_cloud:             GPUParticles2D = $LeftCloud
@onready var right_cloud:            GPUParticles2D = $RightCloud

@onready var action_buttons: HBoxContainer = $CanvasLayer/HBoxContainer
@onready var repair_button:  Button        = $CanvasLayer/HBoxContainer/RepairButton
@onready var upgrade_button: Button        = $CanvasLayer/HBoxContainer/UpgradeButton

# ── State ────────────────────────────────────────────────────────
var upgrade_level:     int   = 0
var assigned_vents:    int   = 0
var oxygen_backlog:    int   = 0

var packets_this_window: int   = 0
var window_timer:        float = 0.0
var is_rate_limited:     bool  = false

var is_fractured:      bool  = false
var _dead_pulse_tween: Tween = null
var _rate_limit_tween: Tween = null
var _rate_limit_label: Label = null
var _rate_limit_label_tween: Tween = null
var _rate_limit_timer_label: Label = null

# ── Tutorial ──────────────────────────────────────────────────────
static var _hub_fracture_tutorial_shown: bool = false
static var _rate_limit_tutorial_shown: bool = false

# ── Popup ────────────────────────────────────────────────────────
const POPUP_OFFSET_Y: float = -60.0
var _popup_open:  bool  = false
var _popup_tween: Tween = null


# ════════════════════════════════════════════════════════════════
#region Lifecycle
# ════════════════════════════════════════════════════════════════

func _ready() -> void:
	if not SaveManager.is_loading:
		AudioManager.play_sfx("build_hub", 0.3, 5.0)
	left_cloud.restart()
	right_cloud.restart()

	cell_type = "HUB"
	window_timer = randf_range(0.0, GameData.hub_rate_window)

	action_buttons.hide()
	action_buttons.modulate.a = 0.0

	# Connect button signals
	repair_button.pressed.connect(_on_repair_button_pressed)
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)

	if not SaveManager.is_loading:
		SignalBus.camera_shake.emit(0.50, 6.0)
		SignalBus.building_spawned.emit(entrance_cell, Vector2i(-99, -99))
	SignalBus.check_fractures.connect(on_check_fracture)

func _process(delta: float) -> void:
	if is_fractured:
		return
	window_timer += delta
	if window_timer >= GameData.hub_rate_window:
		window_timer = 0.0
		packets_this_window = 0
		if is_rate_limited:
			is_rate_limited = false
			_stop_rate_limit_visual()

	# Update the cooldown countdown label in real time
	if is_rate_limited and _rate_limit_timer_label:
		var time_left := GameData.hub_rate_window - window_timer
		_rate_limit_timer_label.text = "%.1fs" % max(0.0, time_left)

	# Update popup position if open
	if _popup_open:
		var hub_screen_pos = get_global_transform_with_canvas().origin
		action_buttons.global_position = hub_screen_pos + Vector2(-20, -60)

#endregion


# ════════════════════════════════════════════════════════════════
#region Input
# ════════════════════════════════════════════════════════════════

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_toggle_popup()
			get_viewport().set_input_as_handled()

#endregion


# ════════════════════════════════════════════════════════════════
#region Popup
# ════════════════════════════════════════════════════════════════

func _toggle_popup() -> void:
	if _popup_open:
		_close_popup()
	else:
		_open_popup()

func _open_popup() -> void:
	_popup_open = true
	_update_buttons()
	
	# Position buttons above the hub
	var hub_screen_pos = get_global_transform_with_canvas().origin
	action_buttons.global_position = hub_screen_pos + Vector2(-40, POPUP_OFFSET_Y)
	
	action_buttons.show()
	
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(action_buttons, "modulate:a", 1.0, 0.2)

func _close_popup() -> void:
	_popup_open = false
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(action_buttons, "modulate:a", 0.0, 0.15)
	await _popup_tween.finished
	action_buttons.hide()

func _update_buttons() -> void:
	repair_button.text     = "Repair (100)"
	repair_button.disabled = not is_fractured

	if upgrade_level >= GameData.MAX_HUB_UPGRADES:
		upgrade_button.text     = "Hub Maxed"
		upgrade_button.disabled = true
	else:
		var cost = GameData.HUB_UPGRADE_COSTS[upgrade_level]
		upgrade_button.text     = "Upgrade (%d)" % cost
		upgrade_button.disabled = GameData.total_data < cost

#endregion


# ════════════════════════════════════════════════════════════════
#region Button Callbacks
# ════════════════════════════════════════════════════════════════

func _on_repair_button_pressed() -> void:
	print("DEBUG: Repair button pressed callback triggered!")
	print("Repair pressed — is_fractured=", is_fractured, " data=", GameData.total_data)
	if not is_fractured:
		return
	if GameData.total_data >= 100:
		GameData.total_data -= 100
		ResourceManager.resources_updated.emit(
			GameData.current_pipe_count,
			GameData.total_data,
			GameData.data_reserve_for_auto_repairs
		)
		repair()
		_close_popup()
	else:
		_spawn_floating_label("Insufficient Data!", Color("d946ef"))

func _on_upgrade_button_pressed() -> void:
	print("DEBUG: Upgrade button pressed callback triggered!")
	if ResourceManager.upgrade_hub(self):
		_spawn_floating_label("Hub Upgraded!", Color("a855f7"))
		_update_buttons()
	else:
		_spawn_floating_label("Insufficient Data!", Color("d946ef"))

#endregion


# ════════════════════════════════════════════════════════════════
#region Packet Handling
# ════════════════════════════════════════════════════════════════

func _get_cap() -> int:
	match upgrade_level:
		0: return CAP_LEVEL_0
		1: return CAP_LEVEL_1
		2: return CAP_LEVEL_2
		3: return CAP_LEVEL_3
		_: return CAP_LEVEL_0

func receive_oxygen_packet() -> void:
	if is_fractured or is_rate_limited:
		return
	oxygen_backlog = max(0, oxygen_backlog - 1)
	packets_this_window += 1
	ResourceManager.add_score()

	if packets_this_window >= _get_cap():
		is_rate_limited = true
		_start_rate_limit_visual()

#endregion


# ════════════════════════════════════════════════════════════════
#region UI
# ════════════════════════════════════════════════════════════════

func _spawn_floating_label(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(-30, -40)
	label.self_modulate = Color(1, 1, 1, 1)
	add_child(label)
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 30, 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8)
	t.tween_callback(label.queue_free).set_delay(0.8)

func _start_rate_limit_visual() -> void:
	# Pulse the hub red-orange
	if _rate_limit_tween:
		_rate_limit_tween.kill()
	_rate_limit_tween = create_tween().set_loops()
	_rate_limit_tween.tween_property(self, "modulate", Color(1.8, 0.3, 0.3, 1.0), 0.4)
	_rate_limit_tween.tween_property(self, "modulate", Color(1.0, 0.6, 0.2, 1.0), 0.4)

	# One-time tutorial notification for first rate limit event
	if not _rate_limit_tutorial_shown:
		_rate_limit_tutorial_shown = true
		NotificationManager.notify(
			"Hub is rate limited — it has processed too many packets this window.\nIt will recover automatically. Build another Hub to share the load.",
			NotificationManager.Type.WARNING,
			"HUB RATE LIMITED",
			30.0
		)
	# Permanent label centered on top of the hub until rate limit clears
	if _rate_limit_label:
		_rate_limit_label.queue_free()
	_rate_limit_label = Label.new()
	_rate_limit_label.text = "RATE LIMITED"
	_rate_limit_label.add_theme_color_override("font_color", Color("ff2222"))
	_rate_limit_label.add_theme_font_override("font", load("res://Assets/Fonts/JetBrainsMono-ExtraBold.ttf"))
	_rate_limit_label.add_theme_font_size_override("font_size", 22)
	add_child(_rate_limit_label)

	# Wait one frame for the label to have a valid size, then center it on the hub
	# Hub is 3x2 tiles = 192x128px. Center horizontally, sit on top vertically.
	await get_tree().process_frame
	var hub_width := 192.0
	_rate_limit_label.position = Vector2(
		(hub_width - _rate_limit_label.size.x) / 2.0,
		-_rate_limit_label.size.y - 4.0
	)

	# Pulse the label alpha so it doesn't feel static
	if _rate_limit_label_tween:
		_rate_limit_label_tween.kill()
	_rate_limit_label_tween = create_tween().set_loops()
	_rate_limit_label_tween.tween_property(_rate_limit_label, "modulate:a", 0.4, 0.6)
	_rate_limit_label_tween.tween_property(_rate_limit_label, "modulate:a", 1.0, 0.6)

	# Cooldown timer label — shows seconds until rate limit clears
	if _rate_limit_timer_label:
		_rate_limit_timer_label.queue_free()
	_rate_limit_timer_label = Label.new()
	_rate_limit_timer_label.add_theme_color_override("font_color", Color("ff8844"))
	_rate_limit_timer_label.add_theme_font_override("font", load("res://Assets/Fonts/JetBrainsMono-ExtraBold.ttf"))
	_rate_limit_timer_label.add_theme_font_size_override("font_size", 18)
	add_child(_rate_limit_timer_label)
	await get_tree().process_frame
	_rate_limit_timer_label.position = Vector2(
		(hub_width - _rate_limit_timer_label.size.x) / 2.0,
		-_rate_limit_label.size.y - _rate_limit_timer_label.size.y - 8.0
	)

func _stop_rate_limit_visual() -> void:
	if _rate_limit_tween:
		_rate_limit_tween.kill()
		_rate_limit_tween = null
	if _rate_limit_label_tween:
		_rate_limit_label_tween.kill()
		_rate_limit_label_tween = null
	if _rate_limit_label:
		_rate_limit_label.queue_free()
		_rate_limit_label = null
	if _rate_limit_timer_label:
		_rate_limit_timer_label.queue_free()
		_rate_limit_timer_label = null
	var restore := create_tween()
	restore.tween_property(self, "modulate", Color.WHITE, 0.3)

#endregion


# ════════════════════════════════════════════════════════════════
#region Fracture
# ════════════════════════════════════════════════════════════════

func on_check_fracture() -> void:
	if is_fractured:
		return
	if randf() < calculate_fracture_chance():
		fracture()

func calculate_fracture_chance() -> float:
	var base_chance       = 0.03
	var pressure_modifier = (GameData.current_pressure / 100.0) * 0.8
	var shield_multiplier = GameData.get_hull_shield_multiplier()
	return max(0.001, (base_chance + pressure_modifier) * shield_multiplier)

func fracture() -> void:
	is_fractured        = true
	oxygen_backlog      = 0
	packets_this_window = 0
	is_rate_limited     = false
	if _rate_limit_tween:
		_rate_limit_tween.kill()
		_rate_limit_tween = null
	if _rate_limit_label_tween:
		_rate_limit_label_tween.kill()
		_rate_limit_label_tween = null
	if _rate_limit_label:
		_rate_limit_label.queue_free()
		_rate_limit_label = null
	if _rate_limit_timer_label:
		_rate_limit_timer_label.queue_free()
		_rate_limit_timer_label = null

	var flicker := create_tween()
	for i in range(4):
		flicker.tween_property(self, "modulate", Color("4a0e1f"), 0.08)
		flicker.tween_property(self, "modulate", Color.WHITE,     0.06)
	flicker.tween_property(self, "modulate", Color("1a0a1f"), 0.2)
	await flicker.finished

	smoke_particle_effect1.emitting = false
	smoke_particle_effect2.emitting = false
	_start_dead_pulse()

	# ── Tutorial: first hub fracture ─────────────────────────────
	if not _hub_fracture_tutorial_shown:
		_hub_fracture_tutorial_shown = true
		_show_hub_fracture_tutorial()

func _show_hub_fracture_tutorial() -> void:
	Engine.time_scale = 0.25
	NotificationManager.notify(
		"A hub has gone offline! Right-click the Hub to open its menu,\nthen press Repair (100 Data).",
		NotificationManager.Type.WARNING,
		"HUB OFFLINE",
		30.0
	)
	# Restore time scale once repaired — or after 10 real-time seconds
	# so a player who can't afford repair isn't stuck in slow-mo forever.
	var elapsed: float = 0.0
	while is_fractured:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed >= 10.0:
			break
	Engine.time_scale = 1.0
	var top_panel = get_tree().get_root().find_child("TopPanel", true, false)
	if top_panel and top_panel.has_method("sync_speed_button_state"):
		top_panel.sync_speed_button_state()

func _start_dead_pulse() -> void:
	if not is_fractured:
		return
	_dead_pulse_tween = create_tween().set_loops()
	_dead_pulse_tween.tween_property(self, "modulate", Color("2d0a2d"), 1.2)
	_dead_pulse_tween.tween_property(self, "modulate", Color("1a0a1f"), 1.2)

func repair() -> void:
	is_fractured = false
	if _dead_pulse_tween:
		_dead_pulse_tween.kill()
		_dead_pulse_tween = null
	
	AudioManager.play_sfx("hub_repair", 1.0, -5.0)

	var reboot := create_tween()
	reboot.tween_property(self, "modulate", Color("4a0e1f"), 0.12)
	reboot.tween_property(self, "modulate", Color("1a0a1f"), 0.10)
	reboot.tween_property(self, "modulate", Color("6b1a4f"), 0.09)
	reboot.tween_property(self, "modulate", Color("1a0a1f"), 0.08)
	reboot.tween_property(self, "modulate", Color("a855f7"), 0.07)
	reboot.tween_property(self, "modulate", Color("1a0a1f"), 0.06)
	reboot.tween_property(self, "modulate", Color("d946ef"), 0.05)
	reboot.tween_property(self, "modulate", Color.WHITE,     0.30)
	await reboot.finished

	smoke_particle_effect1.restart()
	smoke_particle_effect2.restart()

#endregion


# ════════════════════════════════════════════════════════════════
#region Save / Restore
# ════════════════════════════════════════════════════════════════

func get_save_data() -> Dictionary:
	return {
		"position":           SaveManager.vec2_to_array(position),
		"rotation":           rotation,
		"entrance_cell":      SaveManager.vec2i_to_key(entrance_cell),
		"upgrade_level":      upgrade_level,
		"is_fractured":       is_fractured,
		"oxygen_backlog":     oxygen_backlog,
		"packets_this_window": packets_this_window,
		"window_timer":       window_timer,
		"is_rate_limited":    is_rate_limited,
	}


func restore_from_data(d: Dictionary) -> void:
	upgrade_level       = int(d["upgrade_level"])
	oxygen_backlog      = int(d["oxygen_backlog"])
	packets_this_window = int(d["packets_this_window"])
	window_timer        = float(d["window_timer"])
	is_rate_limited     = bool(d["is_rate_limited"])

	if bool(d["is_fractured"]):
		is_fractured                    = true
		smoke_particle_effect1.emitting = false
		smoke_particle_effect2.emitting = false
		modulate                        = Color("1a0a1f")
		_start_dead_pulse()

#endregion
