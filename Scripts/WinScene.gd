## WinScene.gd
## Attach to WinScene.tscn root node.
extends Control

const MAIN_MENU_SCENE    := "res://Scenes/MainMenu.tscn"
const NEXT_MISSION_SCENE := "res://Scenes/GameScene.tscn"

# ── Stat card value labels ─────────────────────────────────────────
@onready var _pipe_value     : Label = $UILayer/StatsRow/StatCard1/VBox/CardValue
@onready var _pressure_value : Label = $UILayer/StatsRow/StatCard2/VBox/CardValue
@onready var _data_value     : Label = $UILayer/StatsRow/StatCard3/VBox/CardValue
@onready var _reserve_value  : Label = $UILayer/StatsRow/StatCard4/VBox/CardValue

# ── Rank block labels ──────────────────────────────────────────────
@onready var _rank_label : Label = $UILayer/RankBlock/VBox/RankLabel
@onready var _rank_desc  : Label = $UILayer/RankBlock/VBox/RankDesc

# ── Buttons ────────────────────────────────────────────────────────
@onready var _btn_menu : Button = $UILayer/ButtonRow/MainMenuButton
@onready var _btn_next : Button = $UILayer/ButtonRow/NextMissionButton

func _ready() -> void:
	_populate_stats()
	_populate_rank()
	_connect_buttons()

func _populate_stats() -> void:
	if not has_node("/root/WinSceneData"):
		return
	var d : Node = get_node("/root/WinSceneData")
	_pipe_value.text     = str(d.pipe_tiles)
	_pressure_value.text = "%.2f%%" % d.peak_pressure
	_data_value.text     = _format_data(d.data_collected)
	_reserve_value.text  = str(d.repair_reserve)

func _populate_rank() -> void:
	if not has_node("/root/WinSceneData"):
		return
	var d    : Node   = get_node("/root/WinSceneData")
	var rank : String = _calculate_rank(d.peak_pressure, d.repair_reserve)
	_rank_label.text = rank
	_rank_desc.text  = _rank_description(rank)

func _calculate_rank(pressure: float, reserve: int) -> String:
	if pressure < 1.5 and reserve >= 3:
		return "S-CLASS"
	elif pressure < 3.0 and reserve >= 1:
		return "A-CLASS"
	elif pressure < 5.0:
		return "B-CLASS"
	else:
		return "C-CLASS"

func _rank_description(rank: String) -> String:
	match rank:
		"S-CLASS": return "HULL INTEGRITY MAINTAINED  /  ZERO BREACHES"
		"A-CLASS": return "MINIMAL STRESS  /  SYSTEM STABLE"
		"B-CLASS": return "MODERATE STRAIN  /  MISSION SUCCESSFUL"
		_:         return "HIGH PRESSURE  /  BARELY CONTAINED"

func _connect_buttons() -> void:
	_btn_menu.pressed.connect(_on_main_menu)
	_btn_next.pressed.connect(_on_next_mission)

func _on_main_menu() -> void:
	SceneTransition.transition_to(MAIN_MENU_SCENE, SceneTransition.Type.BEAM)

func _on_next_mission() -> void:
	SceneTransition.transition_to(NEXT_MISSION_SCENE, SceneTransition.Type.BEAM)

func _format_data(val: int) -> String:
	if val >= 1000:
		return "%dK" % (val / 1000)
	return str(val)
