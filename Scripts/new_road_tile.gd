extends Node2D
class_name NewRoadTile

# ─────────────────────────────────────────────
# Each connection direction gets its own pair of
# Line2Ds (base + outline) so textures, caps and
# UVs are all clean with zero join artifacts.
# Connector rings are spawned along each arm for
# a mechanical, engineered look:  ----O====O====O====O----
# ─────────────────────────────────────────────

@onready var burst_particle_effect: GPUParticles2D = $BurstParticleEffect

# arm_lines[Vector2i] = { "base": Line2D, "outline": Line2D, "upgrade": Line2D, "connectors": Array[Line2D] }
var arm_lines: Dictionary = {}

var cell: Vector2i
var manual_connections: Array[Vector2i] = []
var is_permanent: bool = false
var is_entrance: bool = false
var my_zone: GameData.Zone

var is_fractured: bool = false
var is_reinforced: bool = false

var zone_rates = {
	GameData.Zone.CORE:     0.001,  # Safest — heavily maintained
	GameData.Zone.INNER:    0.003,  # Moderate traffic, regular upkeep
	GameData.Zone.OUTER:    0.006,  # Less maintained, higher wear
	GameData.Zone.FRONTIER: 0.008   # Most dangerous — minimal infrastructure
}

# Pipe visual
const BASE_WIDTH    := 10.0
const OUTLINE_WIDTH := 36.0
const UPGRADE_WIDTH := 40.0

# Connector ring settings
const CONNECTOR_SPACING   := 16.0  # pixels between rings along the arm
const CONNECTOR_HALF_SIZE :=  5.0  # half-length of the perpendicular crossbar
const CONNECTOR_THICKNESS :=  2.5  # Line2D width of each ring

# Assign your texture here or leave null for solid color
var pipe_texture: Texture = null

func set_cell(c: Vector2i) -> void:
	cell = c
	my_zone = GameData.get_zone_for_cell(cell)

func get_cell() -> Vector2i:
	return cell

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if is_fractured:
				if GameData.total_data >= GameData.SINGLE_PIPE_REPAIR_COST:
					GameData.total_data -= GameData.SINGLE_PIPE_REPAIR_COST
					ResourceManager.resources_updated.emit(
						GameData.current_pipe_count,
						GameData.total_data,
						GameData.data_reserve_for_auto_repairs
					)
					repair()
					get_viewport().set_input_as_handled()
				else:
					_spawn_floating_label("Insufficient Data", Color("d946ef"))
			elif is_permanent:
				_spawn_floating_label("Pipe Online", Color("8b92a3"))
				get_viewport().set_input_as_handled()
			else:
				_spawn_floating_label("Pipe Online", Color("8b92a3"))
			


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
	for dir in arm_lines.keys():
		if not manual_connections.has(dir):
			_destroy_arm(dir)
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

	var outline    := _make_line2d(OUTLINE_WIDTH, "outline")
	var base       := _make_line2d(BASE_WIDTH,    "base")
	var upgrade    := _make_line2d(UPGRADE_WIDTH, "upgrade")
	var connectors := _spawn_connectors(direction)

	for line in [outline, base, upgrade]:
		line.add_point(Vector2.ZERO)
		line.add_point(end_pt)

	arm_lines[direction] = {
		"base":       base,
		"outline":    outline,
		"upgrade":    upgrade,
		"connectors": connectors
	}

	on_pipes_upgraded(GameData.current_pipe_upgrade_level)

func _destroy_arm(direction: Vector2i) -> void:
	if not arm_lines.has(direction):
		return
	arm_lines[direction]["base"].queue_free()
	arm_lines[direction]["outline"].queue_free()
	arm_lines[direction]["upgrade"].queue_free()
	for ring in arm_lines[direction]["connectors"]:
		ring.queue_free()
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
			l.z_index = 2
			l.default_color = Color("0f1318ff")
			l.material = CanvasItemMaterial.new()
			l.material.light_mode = CanvasItemMaterial.LIGHT_MODE_NORMAL
		"outline":
			l.z_index = 1
			l.default_color = Color("2e343eff")
		"upgrade":
			l.z_index = 0
			l.default_color = Color(0, 0, 0, 0)
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = mat

	add_child(l)
	return l

# ─────────────────────────────────────────────
# Connector rings
# Small perpendicular Line2Ds along the arm:
#   ----O====O====O====O----
# Skips the tile center and the arm tip so rings
# never overlap the joint or the end cap.
# ─────────────────────────────────────────────

func _spawn_connectors(direction: Vector2i) -> Array:
	var connectors: Array = []
	var length  := GameData.CELL_SIZE.x / 2.0
	var dir_vec := Vector2(direction).normalized()
	var perp    := Vector2(-dir_vec.y, dir_vec.x)  # 90° rotation

	# Start one step in, stop one step before the tip
	var i := 1
	while i * CONNECTOR_SPACING < length - 4.0:
		var pos  := dir_vec * i * CONNECTOR_SPACING
		var ring := Line2D.new()
		ring.width          = CONNECTOR_THICKNESS
		ring.default_color  = Color("3d4451")  # matches level-0 outline color
		ring.z_index        = 3                # above all pipe layers
		ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ring.end_cap_mode   = Line2D.LINE_CAP_ROUND
		ring.add_point(pos - perp * CONNECTOR_HALF_SIZE)
		ring.add_point(pos + perp * CONNECTOR_HALF_SIZE)
		add_child(ring)
		connectors.append(ring)
		i += 1

	return connectors

# ─────────────────────────────────────────────
# Upgrade visuals  (colours on every arm)
# ─────────────────────────────────────────────

func on_pipes_upgraded(level: int) -> void:
	var outline_color: Color
	var outline_mod:   Color
	var upgrade_color: Color
	var ring_color:    Color

	match level:
		0:
			outline_color = Color("2a2f3a")
			outline_mod   = Color(1.0, 1.0, 1.0, 1.0)
			upgrade_color = Color(0, 0, 0, 0)
			ring_color    = Color("2a2f3a")
		1:
			outline_color = Color("1e3a45")  # dark muted steel blue
			outline_mod   = Color(1.0, 1.0, 1.0, 1.0)
			upgrade_color = Color("162d38")  # barely visible cyan tint
			ring_color    = Color("2a5a6a")  # dim steel blue rings

		2:
			outline_color = Color("2d1f3a")  # dark muted plum
			outline_mod   = Color(1.0, 1.0, 1.0, 1.0)
			upgrade_color = Color("1f1428")  # very dark plum glow
			ring_color    = Color("4a2a5a")  # dim plum rings

		3:
			outline_color = Color("2a3a3a")  # dark desaturated teal
			outline_mod   = Color(1.0, 1.0, 1.0, 1.0)
			upgrade_color = Color("1a2a2a")  # barely there glow
			ring_color    = Color("4a3a5a")  # dark muted plum rings

	for arm in arm_lines.values():
		arm["outline"].default_color = outline_color
		arm["outline"].self_modulate = outline_mod
		arm["upgrade"].default_color = upgrade_color
		for ring in arm["connectors"]:
			ring.default_color = ring_color
# ─────────────────────────────────────────────
# Fracture
# ─────────────────────────────────────────────

func on_check_fracture() -> void:
	if is_fractured:
		return
	if is_permanent:
		return
	if randf() < calculate_fracture_chance():
		fracture()

func calculate_fracture_chance(
	pressure: float = GameData.current_pressure,
	shield_multiplier: float = GameData.get_hull_shield_multiplier()
) -> float:
	var base_chance: float = zone_rates.get(my_zone, 0.04)
	var pressure_modifier := (pressure / 100.0) * 0.8
	return max(0.005, (base_chance + pressure_modifier) * shield_multiplier)

func fracture() -> void:
	if is_reinforced:
		return
		
	if is_permanent:
		return

	if GameData.auto_repair_enabled and GameData.data_reserve_for_auto_repairs > GameData.SINGLE_PIPE_REPAIR_COST * 1.1:
		GameData.data_reserve_for_auto_repairs -= GameData.SINGLE_PIPE_REPAIR_COST * 1.1
		return

	var cell_hash := GameData.get_cell_id(cell)
	is_fractured = true

	# Shake
	var shake_tween = create_tween()
	for i in range(5):
		var offset = Vector2(randf_range(-5, 5), randf_range(-5, 5))
		shake_tween.tween_property(self, "position", position + offset, 0.05)
		shake_tween.tween_property(self, "position", position, 0.05)

	burst_particle_effect.restart()

	# Deep plum-crimson sustained fracture color — on theme, not jarring red
	modulate = Color("4a0e1f")

	# Rings go dark/damaged
	for arm in arm_lines.values():
		for ring in arm["connectors"]:
			ring.default_color = Color("2d0a12")

	GameData.astar.set_point_disabled(cell_hash, true)
	GameData.fractured_pipes[cell] = self

func repair() -> void:
	if GameData.fractured_pipes.has(cell):
		GameData.fractured_pipes.erase(cell)

	var cell_hash := GameData.get_cell_id(cell)
	is_fractured = false
	GameData.astar.set_point_disabled(cell_hash, false)

	_play_repair_animation()

func _play_repair_animation() -> void:
	# 1. Flash bright magenta — the repair hit moment
	modulate = Color("d946ef")

	# 2. Rings light up one by one outward
	var all_rings: Array = []
	for arm in arm_lines.values():
		all_rings.append_array(arm["connectors"])

	var ring_delay := 0.08
	for i in range(all_rings.size()):
		var ring: Line2D = all_rings[i]
		var t := create_tween()
		t.tween_interval(i * ring_delay)
		t.tween_property(ring, "default_color", Color("f0abfc"), 0.05)  # flash bright pink
		t.tween_property(ring, "default_color", _get_ring_color_for_level(), 0.2)  # settle to upgrade color

	# 3. After rings finish, fade modulate back to white
	var total_ring_time := all_rings.size() * ring_delay + 0.25
	var fade := create_tween()
	fade.tween_interval(total_ring_time * 0.5)  # start fading halfway through ring sequence
	fade.tween_property(self, "modulate", Color.WHITE, 0.4)
	
	await fade.finished
	_spawn_floating_label("Repaired!", Color("d946EF"))

func _get_ring_color_for_level() -> Color:
	match GameData.current_pipe_upgrade_level:
		0: return Color("3d4451")
		1: return Color("38bdf8")
		2: return Color("d946ef")
		3: return Color("f0abfc")
		_: return Color("3d4451")

# ─────────────────────────────────────────────
# Reinforce
# ─────────────────────────────────────────────

func reinforce() -> void:
	is_reinforced = true
	if is_fractured:
		repair()
	modulate = Color(0.4, 0.9, 1.0, 1.0)

func remove_reinforcement() -> void:
	is_reinforced = false
	if not is_fractured:
		modulate = Color.WHITE


func _spawn_floating_label(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(-20, -30)
	label.self_modulate = Color(1, 1, 1, 1)
	add_child(label)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 30, 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8)
	t.tween_callback(label.queue_free).set_delay(0.8)
