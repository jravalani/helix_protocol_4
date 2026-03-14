extends PanelContainer

## ═══════════════════════════════════════════════════════════════
## TOOLTIP
## Configured by TooltipManager after instancing.
## Call setup() to populate content.
## ═══════════════════════════════════════════════════════════════

@onready var title_label : Label = $VBoxContainer/Title
@onready var desc_label  : Label = $VBoxContainer/Description
@onready var cost_label  : Label = $VBoxContainer/Cost

func setup(p_title: String, p_description: String, p_cost: String) -> void:
	title_label.text = p_title
	desc_label.text  = p_description
	cost_label.text  = p_cost

	# Tint cost label based on content
	if p_cost == "UNLOCKED":
		cost_label.add_theme_color_override("font_color", Color(1.0, 0.08, 0.58, 1))
	elif p_cost.begins_with("Cost:"):
		# Red if not affordable — TooltipManager passes the right string,
		# color is set here based on a prefix the caller can add.
		# Default to normal white; caller can override after setup() if needed.
		cost_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.95, 1))
