extends Control

@onready var launchpad: Sprite2D = $Launchpad
@onready var launchpad_shadow: Sprite2D = $LaunchpadShadow
@onready var title_label: Label = $MarginContainer/Title
@onready var options_button: Button = $MarginContainer2/HBoxContainer/Options
@onready var launch_button: Button = $MarginContainer2/HBoxContainer/Launch
@onready var abort_button: Button = $MarginContainer2/HBoxContainer/Abort

@onready var online_status: Label = $OnlineStatus
@onready var online_status_rect: ColorRect = $OnlineStatusColorRect

# Boot overlay
var boot_overlay: ColorRect

# Scan line variables
var scan_line: ColorRect
var scan_line_position: float = 0.0
var scan_speed: float = 600.0  # pixels per second
var is_scanning: bool = false

# Glitch variables
var glitch_timer: float = 0.0
var glitch_interval: float = 0.3  # time between potential glitches
var glitch_chance: float = 0.4  # 40% chance per interval
var original_title_position: Vector2
var original_launchpad_position: Vector2

# Reveal tracking
var launchpad_revealed: bool = false
var title_revealed: bool = false

var beep_timer: float = 0.0
var ui_ready: bool = false

func _ready():
	# Store original positions for glitch effect
	original_title_position = title_label.position
	original_launchpad_position = launchpad.position
	
	# Hide elements initially
	launchpad.modulate.a = 0.0
	launchpad_shadow.modulate.a = 0.0
	title_label.modulate.a = 0.0
	
	# Hide buttons initially
	options_button.modulate.a = 0.0
	launch_button.modulate.a = 0.0
	abort_button.modulate.a = 0.0
	
	# Hide status indicators initially
	online_status.modulate.a = 0.0
	online_status_rect.modulate.a = 0.0
	
	# Create boot overlay (full screen black)
	create_boot_overlay()
	
	# Create scan line (but keep it hidden initially)
	create_scan_line()
	scan_line.visible = false
	
	# Start the boot sequence
	boot_sequence()
	
	# Update status color
	update_status_color()

func create_boot_overlay():
	boot_overlay = ColorRect.new()
	boot_overlay.color = Color.BLACK
	boot_overlay.size = get_viewport_rect().size
	boot_overlay.position = Vector2.ZERO
	add_child(boot_overlay)
	# Move to top of draw order
	move_child(boot_overlay, get_child_count() - 1)

func boot_sequence():
	# Wait 1 second
	await get_tree().create_timer(1.0).timeout
	
	# Flicker the black overlay to light
	var tween = create_tween()
	
	# Multiple flickers
	tween.tween_property(boot_overlay, "modulate:a", 0.3, 0.05)
	tween.chain().tween_property(boot_overlay, "modulate:a", 1.0, 0.05)
	tween.chain().tween_property(boot_overlay, "modulate:a", 0.0, 0.08)
	tween.chain().tween_property(boot_overlay, "modulate:a", 0.7, 0.04)
	tween.chain().tween_property(boot_overlay, "modulate:a", 0.0, 0.1)
	
	# Wait for flicker to complete
	await tween.finished
	
	# Remove boot overlay
	boot_overlay.queue_free()
	
	# Start the scan
	scan_line.visible = true
	start_diagnostic_sweep()

func create_scan_line():
	scan_line = ColorRect.new()
	scan_line.color = Color(1.0, 0.0, 1.0, 0.6)  # Magenta with transparency
	scan_line.size = Vector2(get_viewport_rect().size.x, 3)
	scan_line.position = Vector2(0, 0)
	add_child(scan_line)
	# Move scan line to top of draw order
	move_child(scan_line, get_child_count() - 1)

func start_diagnostic_sweep():
	scan_line_position = 0.0
	is_scanning = true

func _process(delta):
	if is_scanning:
		# Move scan line down
		scan_line_position += scan_speed * delta
		scan_line.position.y = scan_line_position
		
		# Check if scan line has passed the launchpad (reveal it)
		if not launchpad_revealed and scan_line_position > launchpad.position.y - 100:
			reveal_launchpad()
			launchpad_revealed = true
		
		# Check if scan line has passed the title (reveal it)
		if not title_revealed and scan_line_position > title_label.position.y:
			reveal_title()
			title_revealed = true
		
		# Check if scan is complete
		if scan_line_position > get_viewport_rect().size.y:
			complete_scan()
	
	# Glitch effect (runs continuously after scan)
	if not is_scanning:
		glitch_timer += delta
		if glitch_timer >= glitch_interval:
			glitch_timer = 0.0
			if randf() < glitch_chance:
				apply_glitch()
	
	if not is_scanning and ui_ready:
		beep_timer += delta
		# Calculate interval: 2 seconds at 0 pressure, 0.4 seconds at 100 pressure
		var interval = remap(GameData.current_pressure, 0, 100, 2.0, 0.4)
		
		if beep_timer >= interval:
			beep_timer = 0.0
			play_visual_beep()

func reveal_launchpad():
	# Flicker effect for launchpad
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Flicker in
	tween.tween_property(launchpad, "modulate:a", 1.0, 0.1)
	tween.tween_property(launchpad_shadow, "modulate:a", 0.6, 0.1)
	
	# Add some flicker
	tween.chain().tween_property(launchpad, "modulate:a", 0.3, 0.05)
	tween.chain().tween_property(launchpad, "modulate:a", 1.0, 0.05)
	tween.chain().tween_property(launchpad, "modulate:a", 0.5, 0.03)
	tween.chain().tween_property(launchpad, "modulate:a", 1.0, 0.03)

func reveal_title():
	# Flicker effect for title
	var tween = create_tween()
	
	# Flicker in
	tween.tween_property(title_label, "modulate:a", 1.0, 0.1)
	tween.chain().tween_property(title_label, "modulate:a", 0.4, 0.05)
	tween.chain().tween_property(title_label, "modulate:a", 1.0, 0.05)
	tween.chain().tween_property(title_label, "modulate:a", 0.6, 0.03)
	tween.chain().tween_property(title_label, "modulate:a", 1.0, 0.03)

func complete_scan():
	is_scanning = false
	scan_line.queue_free()
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(options_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(launch_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(abort_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(online_status, "modulate:a", 1.0, 0.5)
	tween.tween_property(online_status_rect, "modulate:a", 1.0, 0.5)
	
	await tween.finished   # <-- wait for fade-in to complete
	ui_ready = true

func update_status_color():
	var pressure = GameData.current_pressure
	var status_color: Color
	
	if pressure < 30:
		status_color = Color("#00ff00")  # Green
	elif pressure < 50:
		status_color = Color("#00ff00")  # Green
	elif pressure < 70:
		status_color = Color("#ffff00")  # Yellow
	elif pressure < 85:
		status_color = Color("#ff8800")  # Orange
	else:
		status_color = Color("#ff0000")  # Red
	
	online_status_rect.color = status_color

func play_visual_beep() -> void:
	update_status_color()

	var pulse_tween = create_tween()

	pulse_tween.tween_property(online_status_rect, "modulate:a", 1.0, 0.0)
	pulse_tween.chain().tween_interval(0.5)
	pulse_tween.chain().tween_property(online_status_rect, "modulate:a", 0.0, 0.0)

func apply_glitch():
	# Random glitch type
	var glitch_type = randi() % 3
	
	match glitch_type:
		0:  # Position shift
			glitch_position_shift()
		1:  # Opacity flicker
			glitch_opacity_flicker()
		2:  # Color shift
			glitch_color_shift()

func glitch_position_shift():
	# Randomly shift title or launchpad
	var target = [title_label, launchpad][randi() % 2]
	var shift = Vector2(randf_range(-5, 5), randf_range(-3, 3))
	var original_pos = original_title_position if target == title_label else original_launchpad_position
	
	var tween = create_tween()
	tween.tween_property(target, "position", original_pos + shift, 0.05)
	tween.chain().tween_property(target, "position", original_pos, 0.05)

func glitch_opacity_flicker():
	# Quick opacity flicker on title
	var tween = create_tween()
	tween.tween_property(title_label, "modulate:a", 0.3, 0.03)
	tween.chain().tween_property(title_label, "modulate:a", 1.0, 0.03)

func glitch_color_shift():
	# Slight color shift in the magenta
	var shifted_color = Color(1.0, randf_range(0.0, 0.2), 1.0, 1.0)
	var original_color = Color(1.0, 0.0, 1.0, 1.0)
	
	var tween = create_tween()
	tween.tween_property(title_label, "modulate", shifted_color, 0.05)
	tween.chain().tween_property(title_label, "modulate", original_color, 0.05)
