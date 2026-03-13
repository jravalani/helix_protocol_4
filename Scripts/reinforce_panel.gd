extends PanelContainer

signal reinforce_core_pressed
signal reinforce_inner_pressed
signal reinforce_outer_pressed
signal reinforce_frontier_pressed

@onready var core_button: Button = $VBoxContainer/CoreButton
@onready var inner_button: Button = $VBoxContainer/InnerButton
@onready var outer_button: Button = $VBoxContainer/OuterButton
@onready var frontier_button: Button = $VBoxContainer/FrontierButton

func _ready() -> void:
	update_button_labels()

func _process(delta: float) -> void:
	update_button_states()

func update_button_labels() -> void:
	core_button.text = "Core (%d)" % GameData.ZONE_REINFORCE_COSTS[0]
	inner_button.text = "Inner (%d)" % GameData.ZONE_REINFORCE_COSTS[1]
	outer_button.text = "Outer (%d)" % GameData.ZONE_REINFORCE_COSTS[2]
	frontier_button.text = "Frontier (%d)" % GameData.ZONE_REINFORCE_COSTS[3]

func update_button_states() -> void:
	core_button.disabled = GameData.total_data < GameData.ZONE_REINFORCE_COSTS[0]
	inner_button.disabled = GameData.total_data < GameData.ZONE_REINFORCE_COSTS[1]
	outer_button.disabled = GameData.total_data < GameData.ZONE_REINFORCE_COSTS[2]
	frontier_button.disabled = GameData.total_data < GameData.ZONE_REINFORCE_COSTS[3]

func _on_core_button_pressed():
	reinforce_core_pressed.emit()

func _on_inner_button_pressed():
	reinforce_inner_pressed.emit()

func _on_outer_button_pressed():
	reinforce_outer_pressed.emit()

func _on_frontier_button_pressed():
	reinforce_frontier_pressed.emit()
