extends PanelContainer

## Notification types — controls color and icon
enum Type { INFO, WARNING, ERROR }

@onready var icon: Label = $MarginContainer/HBoxContainer/IconLabel
@onready var title: Label = $MarginContainer/HBoxContainer/VBoxContainer/Title
@onready var message: Label = $MarginContainer/HBoxContainer/VBoxContainer/Message
@onready var close_button: Button = $MarginContainer/HBoxContainer/CloseButton

const COLOR_INFO    := Color("#00ccff")
const COLOR_WARNING := Color("#ffaa00")
const COLOR_ERROR   := Color("#ff3333")

const ICON_INFO    := "i"
const ICON_WARNING := "!"
const ICON_ERROR   := "!!"

const AUTO_DISMISS_TIME := 10.0

var _type: Type = Type.INFO

## Call this right after instancing to configure the notification.
func setup(p_message: String, p_type: Type = Type.INFO, p_title: String = "") -> void:
	_type = p_type

	# Title fallback
	var display_title := p_title
	if display_title.is_empty():
		match p_type:
			Type.INFO:    display_title = "INFO"
			Type.WARNING: display_title = "WARNING"
			Type.ERROR:   display_title = "ERROR"

	title.text   = display_title
	message.text = p_message

	_apply_style(p_type)

func _ready() -> void:
	close_button.pressed.connect(_dismiss)
	modulate.a = 0.0
	_animate_in()

func _apply_style(p_type: Type) -> void:
	var color := COLOR_INFO
	match p_type:
		Type.WARNING: color = COLOR_WARNING
		Type.ERROR:   color = COLOR_ERROR

	# Icon
	icon.text = ICON_INFO
	match p_type:
		Type.WARNING: icon.text = ICON_WARNING
		Type.ERROR:   icon.text = ICON_ERROR

	icon.add_theme_color_override("font_color", color)
	title.add_theme_color_override("font_color", color)
	close_button.add_theme_color_override("font_color", color)

	# Swap border color on the panel stylebox
	var style := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style:
		style.border_color = color
		style.shadow_color = Color(color.r, color.g, color.b, 0.3)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 2)
		add_theme_stylebox_override("panel", style)

func _animate_in() -> void:
	AudioManager.play_ui("menu_open", 0.5)
	var t := create_tween()
	# Slide in from the right and fade in
	position.x += 40
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.2)
	t.tween_property(self, "position:x", position.x - 40, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(AUTO_DISMISS_TIME)
	t.tween_callback(_dismiss)

func _dismiss() -> void:
	AudioManager.play_ui("menu_close", 0.5)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_property(self, "position:x", position.x + 40, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(queue_free)
