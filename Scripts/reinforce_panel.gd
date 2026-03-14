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
	update_button_labels()
	update_button_states()

func _get_cost(zone_id: int) -> int:
	var base_cost = GameData.ZONE_REINFORCE_COSTS[zone_id]
	# Apply 50% tax if switching from a different active zone
	if GameData.current_reinforced_zone != -1 and GameData.current_reinforced_zone != zone_id:
		return int(base_cost * 1.5)
	return base_cost

func update_button_labels() -> void:
	core_button.text = "Core (%d)" % _get_cost(0)
	inner_button.text = "Inner (%d)" % _get_cost(1)
	outer_button.text = "Outer (%d)" % _get_cost(2)
	frontier_button.text = "Frontier (%d)" % _get_cost(3)

func update_button_states() -> void:
	core_button.disabled = GameData.total_data < _get_cost(0)
	inner_button.disabled = GameData.total_data < _get_cost(1)
	outer_button.disabled = GameData.total_data < _get_cost(2)
	frontier_button.disabled = GameData.total_data < _get_cost(3)
	# Highlight the currently reinforced zone button so player knows which is active
	core_button.modulate     = Color("ff00ff") if GameData.current_reinforced_zone == 0 else Color.WHITE
	inner_button.modulate    = Color("ff00ff") if GameData.current_reinforced_zone == 1 else Color.WHITE
	outer_button.modulate    = Color("ff00ff") if GameData.current_reinforced_zone == 2 else Color.WHITE
	frontier_button.modulate = Color("ff00ff") if GameData.current_reinforced_zone == 3 else Color.WHITE

func _on_core_button_pressed():
	reinforce_core_pressed.emit()

func _on_inner_button_pressed():
	reinforce_inner_pressed.emit()

func _on_outer_button_pressed():
	reinforce_outer_pressed.emit()

func _on_frontier_button_pressed():
	reinforce_frontier_pressed.emit()
