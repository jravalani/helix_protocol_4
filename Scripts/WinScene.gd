## WinScene.gd
extends Control

const MAIN_MENU_SCENE    := "res://Scenes/title_screen.tscn"
const NEXT_MISSION_SCENE := "res://Scenes/main.tscn"

# ── Stat card value labels ──────────────────────────────────────
@onready var _pipe_value     : Label = $UILayer/StatsRow/StatCard1/VBox/CardValue
@onready var _pressure_value : Label = $UILayer/StatsRow/StatCard2/VBox/CardValue
@onready var _data_value     : Label = $UILayer/StatsRow/StatCard3/VBox/CardValue
@onready var _reserve_value  : Label = $UILayer/StatsRow/StatCard4/VBox/CardValue

# ── Rank block labels ───────────────────────────────────────────
@onready var _rank_label : Label = $UILayer/RankBlock/VBox/RankLabel
@onready var _rank_desc  : Label = $UILayer/RankBlock/VBox/RankDesc

# ── Buttons ─────────────────────────────────────────────────────
@onready var _btn_menu : Button = $UILayer/ButtonRow/MainMenuButton
@onready var _btn_next : Button = $UILayer/ButtonRow/NextMissionButton

# ── Fade overlay ────────────────────────────────────────────────
@onready var _fade : ColorRect = $FadeOverlay

func _ready() -> void:
	# Fade in
	if _fade:
		_fade.modulate.a = 1.0
		var t := create_tween()
		t.tween_property(_fade, "modulate:a", 0.0, 1.2)

	_populate_stats()
	_populate_rank()
	_connect_buttons()

func _populate_stats() -> void:
	var d := _get_data()
	_pipe_value.text     = str(d.pipe_tiles)
	_pressure_value.text = "%.1f%%" % d.peak_pressure
	_data_value.text     = _format_data(d.data_collected)
	_reserve_value.text  = str(d.repair_reserve)

func _populate_rank() -> void:
	var d    := _get_data()
	var rank := _calculate_rank(d.peak_pressure, d.data_collected, d.pipe_tiles)
	_rank_label.text = rank
	_rank_desc.text  = _rank_description(rank)

## Rank based on peak pressure at time of win and data earned.
## Peak pressure reflects how close to failure the player got.
## S = escaped clean, C = barely made it out.
func _calculate_rank(pressure: float, data: int, pipes: int) -> String:
	if pressure < 40.0:
		return "S-CLASS"
	elif pressure < 60.0:
		return "A-CLASS"
	elif pressure < 80.0:
		return "B-CLASS"
	else:
		return "C-CLASS"

func _rank_description(rank: String) -> String:
	match rank:
		"S-CLASS": return "ESCAPED CLEAN  /  STATION NEVER THREATENED"
		"A-CLASS": return "CONTROLLED ESCAPE  /  PRESSURE MANAGED"
		"B-CLASS": return "CLOSE CALL  /  LAUNCHED UNDER PRESSURE"
		_:         return "BARELY ESCAPED  /  STATION WAS COLLAPSING"

func _connect_buttons() -> void:
	_btn_menu.pressed.connect(_on_main_menu)
	_btn_next.pressed.connect(_on_next_mission)

func _on_main_menu() -> void:
	SceneTransition.transition_to(MAIN_MENU_SCENE, SceneTransition.Type.BEAM)

func _on_next_mission() -> void:
	# Delete save so intro plays again on new game
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute("user://save.dat")
	SceneTransition.transition_to(NEXT_MISSION_SCENE, SceneTransition.Type.BEAM)

func _get_data() -> Node:
	if has_node("/root/WinSceneData"):
		return get_node("/root/WinSceneData")
	# Fallback — read live from GameData if autoload not populated
	var fallback := Node.new()
	fallback.set("pipe_tiles",     GameData.road_grid.size())
	fallback.set("peak_pressure",  GameData.current_pressure)
	fallback.set("data_collected", GameData.lifetime_data_earned)
	fallback.set("repair_reserve", GameData.data_reserve_for_auto_repairs)
	return fallback

func _format_data(val: int) -> String:
	if val >= 1000:
		return "%dK" % (val / 1000)
	return str(val)
