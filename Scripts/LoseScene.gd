## LoseScene.gd
## Attach to LoseScene.tscn root node.
## Reads stats from WinSceneData autoload and populates node labels.
extends Control

const MAIN_MENU_SCENE := "res://Scenes/main.tscn"
const GAME_SCENE      := "res://Scenes/main.tscn"


# ── Stat card value labels ─────────────────────────────────────────
@onready var _pipe_value     : Label = $UILayer/StatsRow/StatCard1/VBox/CardValue
@onready var _pressure_value : Label = $UILayer/StatsRow/StatCard2/VBox/CardValue
@onready var _data_value     : Label = $UILayer/StatsRow/StatCard3/VBox/CardValue
@onready var _time_value     : Label = $UILayer/StatsRow/StatCard4/VBox/CardValue

# ── Cause block labels ─────────────────────────────────────────────
@onready var _cause_value : Label = $UILayer/CauseBlock/VBox/CauseValue
@onready var _cause_desc  : Label = $UILayer/CauseBlock/VBox/CauseDesc

# ── Buttons ────────────────────────────────────────────────────────
@onready var _btn_menu     : Button = $UILayer/ButtonRow/MainMenuButton
@onready var _btn_try_again: Button = $UILayer/ButtonRow/TryAgainButton

func _ready() -> void:
	_populate_stats()
	_populate_cause()
	_connect_buttons()

func _populate_stats() -> void:
	if not has_node("/root/WinSceneData"):
		return
	var d : Node = get_node("/root/WinSceneData")
	_pipe_value.text     = str(d.pipe_tiles)
	_pressure_value.text = "%.2f%%" % d.peak_pressure
	_data_value.text     = _format_data(d.data_collected)
	_time_value.text     = _format_time(d.survival_time) if d.get("survival_time") else "0s"

func _populate_cause() -> void:
	if not has_node("/root/WinSceneData"):
		return
	var d     : Node   = get_node("/root/WinSceneData")
	var cause : String = d.failure_cause if d.get("failure_cause") and d.failure_cause != "" \
						 else _determine_cause(d.peak_pressure, d.pipe_tiles)
	_cause_value.text = cause
	_cause_desc.text  = _cause_description(cause)

func _determine_cause(pressure: float, pipes: int) -> String:
	if pressure >= 8.0:
		return "PRESSURE OVERLOAD"
	elif pressure >= 5.0:
		return "HULL BREACH"
	elif pipes < 10:
		return "INSUFFICIENT PIPES"
	else:
		return "SYSTEM FAILURE"

func _cause_description(cause: String) -> String:
	match cause:
		"PRESSURE OVERLOAD":  return "PRESSURE EXCEEDED SAFE THRESHOLD  /  HULL DESTROYED"
		"HULL BREACH":        return "SHIELD INTEGRITY DEPLETED  /  BREACH UNCONTAINED"
		"INSUFFICIENT PIPES": return "PIPE NETWORK INCOMPLETE  /  FLOW UNMANAGED"
		_:                    return "CRITICAL SYSTEM ERROR  /  MISSION ABORTED"

func _connect_buttons() -> void:
	_btn_menu.pressed.connect(_on_main_menu)
	_btn_try_again.pressed.connect(_on_try_again)

func _on_main_menu() -> void:
	SceneTransition.transition_to(MAIN_MENU_SCENE, SceneTransition.Type.BEAM)

func _on_try_again() -> void:
	SceneTransition.transition_to(GAME_SCENE, SceneTransition.Type.BEAM)

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
		return "%dm%ds" % [m, s]
	return "%ds" % s
