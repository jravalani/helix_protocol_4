extends Node2D
class_name NewRoadTile

# ─────────────────────────────────────────────
# Each connection direction gets its own pair of
# Line2Ds (base + outline) so textures, caps and
# UVs are all clean with zero join artifacts.
# ─────────────────────────────────────────────

# arm_lines[Vector2i] = { "base": Line2D, "outline": Line2D }
var arm_lines: Dictionary = {}

var cell: Vector2i
var manual_connections: Array[Vector2i] = []
var is_permanent: bool = false
var is_entrance: bool = false
var my_zone: GameData.Zone

var is_fractured: bool = false
var is_reinforced: bool = false

var zone_rates = {
	GameData.Zone.CORE: 0.005,
	GameData.Zone.INNER: 0.002,
	GameData.Zone.OUTER: 0.004,
	GameData.Zone.FRONTIER: 0.005
}

# Pipe visual 
const BASE_WIDTH    := 10.0
const OUTLINE_WIDTH := 36.0
const UPGRADE_WIDTH := 40.0

# Assign your texture here or leave null for solid color
var pipe_texture: Texture = null

func set_cell(c: Vector2i) -> void:
	cell = c
	my_zone = GameData.get_zone_for_cell(cell)

func get_cell() -> Vector2i:
	return cell

func _ready() -> void:
	SignalBus.pipes_upgraded.connect(on_pipes_upgraded)
	SignalBus.check_fractures.connect(on_check_fracture)
	on_pipes_upgraded(GameData.current_pipe_upgrade_level)

# ─────────────────────────────────────────────
# Connection API  (same signatures as before)
# ─────────────────────────────────────────────

func has_connection_in_direction(direction: Vector2i) -> bool:
	return manual_connections.has(direction)

func get_connection_directions() -> Array[Vector2i]:
	return manual_connections.duplicate()

func add_connection(direction: Vector2i) -> void:
	if manual_connections.has(direction):
		return
	manual_connections.append(direction)
	_spawn_arm(direction)

func remove_connection(direction: Vector2i) -> void:
	if not manual_connections.has(direction):
		return
	manual_connections.erase(direction)
	_destroy_arm(direction)

# update_visuals kept for compatibility (ghost road uses it)
func update_visuals() -> void:
	# Destroy arms that are no longer in manual_connections
	for dir in arm_lines.keys():
		if not manual_connections.has(dir):
			_destroy_arm(dir)
	# Spawn arms that are missing
	for dir in manual_connections:
		if not arm_lines.has(dir):
			_spawn_arm(dir)

# ─────────────────────────────────────────────
# Arm spawn / destroy
# ─────────────────────────────────────────────

func _spawn_arm(direction: Vector2i) -> void:
	if arm_lines.has(direction):
		return

	var end_pt := Vector2(direction) * GameData.CELL_SIZE / 2.0

	var outline := _make_line2d(OUTLINE_WIDTH, "outline")
	var base    := _make_line2d(BASE_WIDTH,    "base")
	var upgrade := _make_line2d(UPGRADE_WIDTH, "upgrade")

	for line in [outline, base, upgrade]:
		line.add_point(Vector2.ZERO)
		line.add_point(end_pt)

	arm_lines[direction] = { "base": base, "outline": outline, "upgrade": upgrade }

	on_pipes_upgraded(GameData.current_pipe_upgrade_level)

func _destroy_arm(direction: Vector2i) -> void:
	if not arm_lines.has(direction):
		return
	arm_lines[direction]["base"].queue_free()
	arm_lines[direction]["outline"].queue_free()
	arm_lines[direction]["upgrade"].queue_free()
	arm_lines.erase(direction)

func _make_line2d(width: float, layer: String) -> Line2D:
	var l := Line2D.new()
	l.width = width
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode   = Line2D.LINE_CAP_ROUND
	l.joint_mode     = Line2D.LINE_JOINT_ROUND

	if pipe_texture:
		l.texture      = pipe_texture
		l.texture_mode = Line2D.LINE_TEXTURE_STRETCH

	match layer:
		"base":
			l.z_index = 1
			l.default_color = Color("0f1318ff")  # dark metallic base (lighter than before)
			l.material = CanvasItemMaterial.new()
			l.material.light_mode = CanvasItemMaterial.LIGHT_MODE_NORMAL 
		"outline":
			l.z_index = 0
			l.default_color = Color("2e343eff")  # medium gray outline (more visible)
		"upgrade":
			l.z_index = -1
			l.default_color = Color(0, 0, 0, 0)  # invisible until upgraded
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = mat

	add_child(l)
	return l
	
# ─────────────────────────────────────────────
# Upgrade visuals  (colours on every arm)
# ─────────────────────────────────────────────

func on_pipes_upgraded(level: int) -> void:
	var outline_color:   Color
	var outline_mod:     Color
	var upgrade_color:   Color

	match level:
		0:
			outline_color  = Color("3d4451")
			outline_mod    = Color(1.0, 1.0, 1.0, 1.0)
			upgrade_color  = Color(0, 0, 0, 0)        # invisible at level 0
		1:
			outline_color  = Color("5a6978")
			outline_mod    = Color(1.2, 1.2, 1.2, 1.0)
			upgrade_color  = Color("38bdf8")          # cyan blue (matches launchpad)
		2:
			outline_color  = Color("8b92a3")
			outline_mod    = Color(1.5, 1.5, 1.5, 1.0)
			upgrade_color  = Color("d946ef")          # magenta/pink (matches launchpad rings)
		3:
			outline_color  = Color("e0e7ff")
			outline_mod    = Color(2.0, 2.0, 2.0, 1.0)
			upgrade_color  = Color("f0abfc")          # bright pink glow
		_:
			outline_color  = Color("3d4451")
			outline_mod    = Color(1.0, 1.0, 1.0, 1.0)
			upgrade_color  = Color(0, 0, 0, 0)

	for arm in arm_lines.values():
		arm["outline"].default_color  = outline_color
		arm["outline"].self_modulate  = outline_mod
		arm["upgrade"].default_color  = upgrade_color

# ─────────────────────────────────────────────
# Fracture
# ─────────────────────────────────────────────

func on_check_fracture() -> void:
	if is_fractured:
		return
	if randf() < calculate_fracture_chance():
		fracture()

func calculate_fracture_chance() -> float:
	var base_chance: float = zone_rates.get(my_zone, 0.04)
	var pressure_modifier := (GameData.current_pressure / 100.0) * 0.8
	var shield_multiplier := GameData.get_hull_shield_multiplier()
	return max(0.005, (base_chance + pressure_modifier) * shield_multiplier)

func fracture() -> void:
	if is_reinforced:
		return

	if GameData.auto_repair_enabled and GameData.data_reserve_for_auto_repairs > GameData.SINGLE_PIPE_REPAIR_COST * 1.1:
		GameData.data_reserve_for_auto_repairs -= GameData.SINGLE_PIPE_REPAIR_COST * 1.1
		return

	var cell_hash := GameData.get_cell_id(cell)
	is_fractured = true
	modulate = Color(1.0, 0.2, 0.2, 0.8)  # Darker red for fracture (more visible on dark bg)
	GameData.astar.set_point_disabled(cell_hash, true)
	GameData.fractured_pipes[cell] = self

func repair() -> void:
	if GameData.fractured_pipes.has(cell):
		GameData.fractured_pipes.erase(cell)

	var cell_hash := GameData.get_cell_id(cell)
	is_fractured = false
	modulate = Color.WHITE
	GameData.astar.set_point_disabled(cell_hash, false)

# ─────────────────────────────────────────────
# Reinforce
# ─────────────────────────────────────────────

func reinforce() -> void:
	is_reinforced = true
	if is_fractured:
		repair()
	modulate = Color(0.4, 0.9, 1.0, 1.0)  # Brighter cyan for reinforcement

func remove_reinforcement() -> void:
	is_reinforced = false
	if not is_fractured:
		modulate = Color.WHITE
