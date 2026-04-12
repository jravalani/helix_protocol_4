## LoseScene.gd
extends Control

const MAIN_MENU_SCENE := "res://Scenes/MainMenu.tscn"
const GAME_SCENE      := "res://Scenes/main.tscn"

# ── Stat card value labels ──────────────────────────────────────
@onready var _pipe_value     : Label = $UILayer/StatsRow/StatCard1/VBox/CardValue
@onready var _pressure_value : Label = $UILayer/StatsRow/StatCard2/VBox/CardValue
@onready var _data_value     : Label = $UILayer/StatsRow/StatCard3/VBox/CardValue
@onready var _time_value     : Label = $UILayer/StatsRow/StatCard4/VBox/CardValue

# ── Cause block labels ──────────────────────────────────────────
@onready var _cause_value : Label = $UILayer/CauseBlock/VBox/CauseValue
@onready var _cause_desc  : Label = $UILayer/CauseBlock/VBox/CauseDesc

# ── Buttons ─────────────────────────────────────────────────────
@onready var _btn_menu      : Button = $UILayer/ButtonRow/MainMenuButton
@onready var _btn_try_again : Button = $UILayer/ButtonRow/TryAgainButton

# ── Fade overlay ────────────────────────────────────────────────
@onready var _fade : ColorRect = $FadeOverlay

func _ready() -> void:
	# Fade in
	if _fade:
		_fade.modulate.a = 1.0
		var t := create_tween()
		t.tween_property(_fade, "modulate:a", 0.0, 1.2)

	_populate_stats()
	_populate_cause()
	_connect_buttons()

func _populate_stats() -> void:
	var d := _get_data()
	_pipe_value.text     = str(d.pipe_tiles)
	_pressure_value.text = "%.1f%%" % d.peak_pressure
	_data_value.text     = _format_data(d.data_collected)
	_time_value.text     = _format_time(d.survival_time) if d.get("survival_time") else "0s"

func _populate_cause() -> void:
	var d     := _get_data()
	var cause : String = ""
	if d.get("failure_cause") and d.failure_cause != "":
		cause = d.failure_cause
	else:
		cause = _determine_cause(d.peak_pressure, d.pipe_tiles)
	_cause_value.text = cause
	_cause_desc.text  = _cause_description(cause)

## Determine cause from actual pressure percentage (0–100)
func _determine_cause(pressure: float, pipes: int) -> String:
	if pressure >= 90.0:
		return "PRESSURE OVERLOAD"
	elif pressure >= 70.0:
		return "HULL BREACH"
	elif pipes < 10:
		return "INSUFFICIENT NETWORK"
	else:
		return "SYSTEM FAILURE"

func _cause_description(cause: String) -> String:
	match cause:
		"PRESSURE OVERLOAD":     return "STATION PRESSURE EXCEEDED LIMIT  /  HULL DESTROYED"
		"HULL BREACH":           return "SHIELD INTEGRITY DEPLETED  /  BREACH UNCONTAINED"
		"INSUFFICIENT NETWORK":  return "PIPE NETWORK TOO SPARSE  /  DATA FLOW COLLAPSED"
		_:                       return "CRITICAL SYSTEM ERROR  /  MISSION ABORTED"

func _connect_buttons() -> void:
	_btn_menu.pressed.connect(_on_main_menu)
	_btn_try_again.pressed.connect(_on_try_again)

func _on_main_menu() -> void:
	SceneTransition.transition_to(MAIN_MENU_SCENE, SceneTransition.Type.BEAM)

func _on_try_again() -> void:
	# Delete save so it starts fresh
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute("user://save.dat")
	SceneTransition.transition_to(GAME_SCENE, SceneTransition.Type.BEAM)

func _get_data() -> Node:
	if has_node("/root/WinSceneData"):
		return get_node("/root/WinSceneData")
	# Fallback — read live from GameData if autoload not populated
	var fallback := Node.new()
	fallback.set("pipe_tiles",     GameData.road_grid.size())
	fallback.set("peak_pressure",  GameData.current_pressure)
	fallback.set("data_collected", GameData.lifetime_data_earned)
	fallback.set("repair_reserve", GameData.data_reserve_for_auto_repairs)
	fallback.set("survival_time",  0.0)
	fallback.set("failure_cause",  "")
	return fallback

func _format_data(val: int) -> String:
	if val >= 1000:
		return "%dK" % (val / 1000)
	return str(val)

func _format_time(seconds: float) -> String:
	if seconds <= 0:
		return "0s"
	var m : int = int(seconds) / 60
	var s : int = int(seconds) % 60
	if m > 0:
		return "%dm %ds" % [m, s]
	return "%ds" % s
