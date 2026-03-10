
extends Control

@export var margin_left: float = 300.0
@export var margin_right: float = 300.0
@export var margin_top: float = 200.0
@export var margin_bottom: float = 200.0

@export var pressure: float = 0.0 # 0..1

@onready var stripe_top: ColorRect = $OverlayUI/StripeTop
@onready var stripe_bottom: ColorRect = $OverlayUI/StripeBottom
@onready var stripe_left: ColorRect = $OverlayUI/StripeLeft
@onready var stripe_right: ColorRect = $OverlayUI/StripeRight

func _ready() -> void:
	update_stripes()
	get_viewport().size_changed.connect(update_stripes)

func _process(_delta: float) -> void:
	pressure = clamp(pressure, 0.0, 1.0)

	# all stripes share same material, so update one
	var mat := stripe_top.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("pulse_speed", lerp(1.2, 4.0, pressure))
		mat.set_shader_parameter("pulse_strength", lerp(0.15, 0.8, pressure))
		mat.set_shader_parameter("glow_strength", lerp(0.5, 1.4, pressure))

func update_stripes() -> void:
	var vp: Vector2 = get_viewport_rect().size

	var play_x: float = margin_left
	var play_y: float = margin_top
	var play_w: float = max(0.0, vp.x - margin_left - margin_right)
	var play_h: float = max(0.0, vp.y - margin_top - margin_bottom)

	# Top
	stripe_top.position = Vector2(0, 0)
	stripe_top.size = Vector2(vp.x, play_y)

	# Bottom
	stripe_bottom.position = Vector2(0, play_y + play_h)
	stripe_bottom.size = Vector2(vp.x, vp.y - (play_y + play_h))

	# Left
	stripe_left.position = Vector2(0, play_y)
	stripe_left.size = Vector2(play_x, play_h)

	# Right
	stripe_right.position = Vector2(play_x + play_w, play_y)
	stripe_right.size = Vector2(vp.x - (play_x + play_w), play_h)
