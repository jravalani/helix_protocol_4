extends Control

# Path to your main game scene - adjust if different
const NEXT_SCENE = "res://Scenes/main.tscn"

@onready var crawl_text = $CrawlContainer/SubViewport/CrawlText
@onready var fade_overlay = $FadeOverlay
@onready var skip_label = $SkipLabel

var scroll_tween: Tween
var is_transitioning := false

func _ready():
	# Start fully visible fade overlay, then fade it out (fade in effect)
	fade_overlay.modulate.a = 1.0
	var fade_in = create_tween()
	fade_in.tween_property(fade_overlay, "modulate:a", 0.0, 1.5)
	fade_in.tween_callback(_start_crawl)
	# Pulse the skip label
	var skip_tween = create_tween().set_loops()
	skip_tween.tween_property(skip_label, "modulate:a", 0.2, 1.2)
	skip_tween.tween_property(skip_label, "modulate:a", 1.0, 1.2)

func _start_crawl():
	# Scroll the text upward over 24 seconds
	scroll_tween = create_tween()
	scroll_tween.tween_property(crawl_text, "position:y", -1400.0, 24.0)\
		.set_trans(Tween.TRANS_LINEAR)
	# Fire fade-out when last line is nearly off screen (2s before scroll ends)
	var fade_timer = create_tween()
	fade_timer.tween_interval(21.0)
	fade_timer.tween_callback(_go_to_next_scene)

func _input(event):
	if is_transitioning:
		return
	var pressed = false
	if event is InputEventKey and event.pressed:
		pressed = true
	if event is InputEventMouseButton and event.pressed:
		pressed = true
	if pressed:
		_go_to_next_scene()

func _go_to_next_scene():
	if is_transitioning:
		return
	is_transitioning = true
	# Stop the crawl if still running
	if scroll_tween and scroll_tween.is_running():
		scroll_tween.kill()
	# Fade to black then switch scene
	var fade_out = create_tween()
	fade_out.tween_property(fade_overlay, "modulate:a", 1.0, 0.6)
	fade_out.tween_callback(func():
		get_tree().change_scene_to_file(NEXT_SCENE)
	)
