extends Control

## ═══════════════════════════════════════════════════════════════
## TECH TREE — scene-based UI
## Handles: layout, state, signals, button wiring.
## Drawing (lines/frame/animations) → DrawingLayer (hex_drawing.gd)
## Tooltips → TooltipManager autoload
## ═══════════════════════════════════════════════════════════════

# ── Layout constants ───────────────────────────────────────────
const HEX_RADIUS       := 220.0
const OUTER_HEX_RADIUS := 270.0
const NUM_NODES        := 5

# Button half-size to center buttons on hex points (80×53 button scene)
const BTN_HALF := Vector2(40.0, 26.5)

# Maps node index (0–4) to rocket upgrade phase (1–5)
var phase_map : Array[int] = [1, 2, 3, 4, 5]

# ── Hex geometry — read by hex_drawing.gd ─────────────────────
var hex_center : Vector2 = Vector2.ZERO

var hex_pts   : Array[Vector2] = []
var outer_pts : Array[Vector2] = []
var edge_mids : Array[Vector2] = []

# ── Node references ────────────────────────────────────────────
@onready var drawing_layer  : Control     = $DrawingLayer
@onready var close_btn      : Button      = $UILayer/CloseButton
@onready var center_hub     : Button      = $UILayer/CenterHub
@onready var progress_bar   : ProgressBar = $UILayer/ProgressBarContainer/RocketProgressBar
@onready var progress_label : Label       = $UILayer/ProgressBarContainer/ProgressLabel

#rings
@onready var outer_ring: Sprite2D = $DrawingLayer/OuterRing
@onready var inner_ring: Sprite2D = $DrawingLayer/InnerRing

var skill_nodes : Array[Button] = []
var skill_names : Array[Label]  = []

var _ready_done := false

var rotation_speed: float = 0.01
# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	skill_nodes = [
		$UILayer/SkillNodes/SkillNode1,
		$UILayer/SkillNodes/SkillNode2,
		$UILayer/SkillNodes/SkillNode3,
		$UILayer/SkillNodes/SkillNode4,
		$UILayer/SkillNodes/SkillNode5,
	]
	skill_names = [
		$UILayer/SkillNameLabels/SkillName1,
		$UILayer/SkillNameLabels/SkillName2,
		$UILayer/SkillNameLabels/SkillName3,
		$UILayer/SkillNameLabels/SkillName4,
		$UILayer/SkillNameLabels/SkillName5,
	]

	for i in NUM_NODES:
		if skill_nodes[i] == null:
			push_error("tech_tree.gd: skill_nodes[%d] is null — check scene node name." % i)
		if skill_names[i] == null:
			push_error("tech_tree.gd: skill_names[%d] is null — check scene node name." % i)

	# ── Signal bus ────────────────────────────────────────────
	SignalBus.open_rocket_menu.connect(_on_open_rocket_menu)
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)
	ResourceManager.resources_updated.connect(func(_a, _b, _c): _refresh_ui())

	# ── Buttons ───────────────────────────────────────────────
	close_btn.pressed.connect(_close)
	center_hub.pressed.connect(_on_hub_pressed)

	for i in NUM_NODES:
		var idx := i
		skill_nodes[i].pressed.connect(func(): _click_node(idx))
		skill_nodes[i].mouse_entered.connect(func(): _on_node_hover_enter(idx))
		skill_nodes[i].mouse_exited.connect(_on_node_hover_exit)

	_ready_done = true
	_recalc()
	_refresh_ui()


func _physics_process(delta: float) -> void:
	outer_ring.rotation += rotation_speed * delta
	inner_ring.rotation -= rotation_speed * delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _ready_done:
		_recalc()

# ═══════════════════════════════════════════════════════════════
# LAYOUT
# ═══════════════════════════════════════════════════════════════

func _recalc() -> void:
	hex_center = Vector2(size.x / 2.0, size.y / 2.0 - 20.0)
	hex_pts.clear()
	outer_pts.clear()
	edge_mids.clear()

	for i in NUM_NODES:
		var a := deg_to_rad((360.0 / NUM_NODES) * i - 90.0)
		var d := Vector2(cos(a), sin(a))
		hex_pts.append(hex_center + d * HEX_RADIUS)
		outer_pts.append(hex_center + d * OUTER_HEX_RADIUS)
	for i in NUM_NODES:
		edge_mids.append((hex_pts[i] + hex_pts[(i + 1) % NUM_NODES]) / 2.0)
	drawing_layer.queue_redraw()

# ═══════════════════════════════════════════════════════════════
# UI STATE
# ═══════════════════════════════════════════════════════════════

func _refresh_ui() -> void:
	var cur := GameData.current_rocket_phase
	progress_bar.value  = cur
	progress_label.text = "ROCKET COMPLETION: %d / 5 SEGMENTS" % cur

	for i in NUM_NODES:
		var ph      : int  = phase_map[i]
		var unlocked       := _unlocked(ph)
		var is_next        := (ph == cur + 1)

		skill_nodes[i].disabled = not is_next and not unlocked
		skill_names[i].text     = GameData.ROCKET_UPGRADES[ph]["name"]
		skill_names[i].modulate.a = 0.7 if unlocked else 1.0

	var all_done := cur >= 5
	center_hub.disabled = not all_done
	center_hub.text     = "▲\nLAUNCH" if all_done else "▲\n—"

	drawing_layer.queue_redraw()

# ═══════════════════════════════════════════════════════════════
# HELPERS  (also read by hex_drawing.gd)
# ═══════════════════════════════════════════════════════════════

func _unlocked(phase: int) -> bool:
	return phase >= 1 and phase <= GameData.current_rocket_phase

func _edge_lit(i: int, j: int) -> bool:
	return _unlocked(phase_map[i]) and _unlocked(phase_map[j])

# ═══════════════════════════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

# ═══════════════════════════════════════════════════════════════
# BUTTON HANDLERS
# ═══════════════════════════════════════════════════════════════

func _click_node(idx: int) -> void:
	var ph : int = phase_map[idx]
	if ph != GameData.current_rocket_phase + 1:
		return
	if ResourceManager.upgrade_rocket_phase():
		print("Rocket upgraded to phase: ", GameData.current_rocket_phase)
	else:
		print("Insufficient data to upgrade.")

func _on_hub_pressed() -> void:
	if GameData.current_rocket_phase >= 5:
		SignalBus.launch_rocket_requested.emit()
		_close()

func _on_node_hover_enter(idx: int) -> void:
	var ph  : int        = phase_map[idx]
	var upg : Dictionary = GameData.ROCKET_UPGRADES[ph]

	var cost_text : String
	if _unlocked(ph):
		cost_text = "UNLOCKED"
	else:
		cost_text = "Cost: %d Data" % upg["cost"]

	TooltipManager.show_tooltip(upg["name"], upg["description"], cost_text, skill_nodes[idx])

func _on_node_hover_exit() -> void:
	TooltipManager.hide_tooltip()

# ═══════════════════════════════════════════════════════════════
# OPEN / CLOSE
# ═══════════════════════════════════════════════════════════════

func _close() -> void:
	TooltipManager.hide_tooltip()
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tw.tween_callback(func():
		self.hide()
		self.modulate = Color(1, 1, 1, 1)
	)

func _on_open_rocket_menu() -> void:
	#_refresh_ui()
	#self.modulate = Color(1, 1, 1, 0)
	self.show()
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.2)

func _on_rocket_segment_purchased(to_phase: int) -> void:
	_refresh_ui()
	if to_phase >= 5:
		print("All segments complete! Launch ready.")
