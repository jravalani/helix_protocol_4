extends Node2D

@onready var bay_window: Panel = $"../CanvasLayer/HubWindow"
@onready var bottom_panel: Control = $"../CanvasLayer/InLevelUI"

# Settings
var idle_timer: float = 0.0
var is_faded: bool = false
const IDLE_THRESHOLD: float = 30.0  # Seconds before fading
const FADE_DURATION: float = 0.5   # How long the fade animation takes

func _input(event: InputEvent) -> void:
	# If the mouse moves or clicks, reset the timer and wake up the UI
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		idle_timer = 0.0
		if is_faded:
			_fade_ui(1.0) # Fade back in (Opaque)

func _ready() -> void:
	SignalBus.ui_wake_up.connect(func(): _fade_ui(1.0))
	SignalBus.fracture_wave_impact.connect(_on_wave_impact)


func _process(delta: float) -> void:
	# Only increment the timer if the UI is currently visible
	if not is_faded:
		idle_timer += delta
		if idle_timer >= IDLE_THRESHOLD:
			_fade_ui(0.0) # Fade out (Transparent)

func _fade_ui(target_alpha: float) -> void:
	is_faded = (target_alpha == 0.0)
	
	# Create a tween to animate the 'modulate' alpha channel
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	if bay_window:
		tween.tween_property(bay_window, "modulate:a", target_alpha, FADE_DURATION)
	
	if bottom_panel:
		tween.tween_property(bottom_panel, "modulate:a", target_alpha, FADE_DURATION)

func _on_wave_impact() -> void:
	## 1. Force the UI to wake up if it was faded
	#_fade_ui(1.0)
	
	# 2. Create the "Surge" flash effect
	var flash_tween = create_tween().set_parallel(true)
	
	# We use 'modulate' to overdrive the brightness (requires Raw Color/HDR)
	# If not using HDR, just flash to a bright magenta
	var surge_color = Color(2.0, 0.5, 2.0, 1.0) # Overbright magenta
	
	for panel in [bottom_panel, bay_window]:
		if panel:
			# Flash bright...
			flash_tween.tween_property(panel, "modulate", surge_color, 0.1)\
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			# ...then fade back to normal
			flash_tween.chain().tween_property(panel, "modulate", Color.WHITE, 0.5)\
				.set_trans(Tween.TRANS_SINE)

	var shake_tween = create_tween()
	for i in range(4):
		var random_offset = Vector2(randf_range(-5, 5), randf_range(-5, 5))
		shake_tween.tween_property(bottom_panel, "position", bottom_panel.position + random_offset, 0.05)
		shake_tween.tween_property(bottom_panel, "position", bottom_panel.position, 0.05)
