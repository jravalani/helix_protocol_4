extends CanvasLayer

## ═══════════════════════════════════════════════════════════════
## TOOLTIP MANAGER  (autoload singleton)
## Manages a single reusable tooltip instance.
## Usage from anywhere:
##   TooltipManager.show_tooltip(title, description, cost, anchor_node)
##   TooltipManager.hide_tooltip()
## ═══════════════════════════════════════════════════════════════

const TOOLTIP_SCENE := preload("res://Scenes/tooltip.tscn")

## Offset from the anchor node's top-right corner
const OFFSET := Vector2(8.0, 0.0)

## How far from screen edges to keep the tooltip
const SCREEN_MARGIN := 12.0

var _tooltip : PanelContainer = null

# ═══════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════

## Show a tooltip anchored near a Control node.
## p_cost: pass "UNLOCKED", "Cost: X Data", or "" to hide the cost line.
func show_tooltip(p_title: String, p_description: String, p_cost: String, anchor: Control) -> void:
	# Re-use existing instance or create a fresh one
	if _tooltip == null:
		_tooltip = TOOLTIP_SCENE.instantiate()
		add_child(_tooltip)

	_tooltip.setup(p_title, p_description, p_cost)
	_tooltip.visible = true

	# Wait one frame so the tooltip has laid out and has a valid size
	await get_tree().process_frame
	_position_tooltip(anchor)

## Hide and keep the instance alive for reuse.
func hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false

# ═══════════════════════════════════════════════════════════════
# POSITIONING
# ═══════════════════════════════════════════════════════════════

func _position_tooltip(anchor: Control) -> void:
	if _tooltip == null or not is_instance_valid(anchor):
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var tip_size      := _tooltip.size

	# Default: to the right of the anchor
	var anchor_global := anchor.get_global_rect()
	var pos := Vector2(
		anchor_global.position.x + anchor_global.size.x + OFFSET.x,
		anchor_global.position.y + OFFSET.y
	)

	# Flip left if it would overflow the right edge
	if pos.x + tip_size.x > viewport_size.x - SCREEN_MARGIN:
		pos.x = anchor_global.position.x - tip_size.x - OFFSET.x

	# Clamp vertically
	pos.y = clampf(pos.y, SCREEN_MARGIN, viewport_size.y - tip_size.y - SCREEN_MARGIN)

	# Clamp horizontally as a final safety net
	pos.x = clampf(pos.x, SCREEN_MARGIN, viewport_size.x - tip_size.x - SCREEN_MARGIN)

	_tooltip.position = pos
