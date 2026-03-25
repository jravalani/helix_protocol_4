extends Control

@onready var launchpad: Sprite2D = $Launchpad
@onready var launchpad_shadow: Sprite2D = $LaunchpadShadow
@onready var title_label: Label = $MarginContainer/Title
@onready var options_button: Button = $MarginContainer2/HBoxContainer/Options
@onready var launch_button: Button = $MarginContainer2/HBoxContainer/Launch
@onready var abort_button: Button = $MarginContainer2/HBoxContainer/Abort

# Save/Load buttons (created dynamically)
var resume_button: Button
var erase_button: Button
var confirm_overlay: ColorRect
var button_scene: PackedScene = preload("res://Scenes/button.tscn")

@onready var online_status: Label = $OnlineStatus
@onready var online_status_rect: ColorRect = $OnlineStatusColorRect

@onready var ambience_hum: AudioStreamPlayer2D = $Ambience
@onready var drone_hum: AudioStreamPlayer2D = $Drone
@onready var thump_sound: AudioStreamPlayer2D = $Thump
@onready var electric_hum: AudioStreamPlayer2D = $ElectricHum
@onready var flicker: AudioStreamPlayer2D = $Flicker
@onready var beep: AudioStreamPlayer2D = $Beep
@onready var thump_timer: Timer = $ThumpTimer

# Boot overlay
var boot_overlay: ColorRect

# Glitch variables
var glitch_timer: float = 0.0
var glitch_interval: float = 0.3  # time between potential glitches
var glitch_chance: float = 0.4  # 40% chance per interval
var original_title_position: Vector2
var original_launchpad_position: Vector2
var original_launchpad_shadow_position: Vector2

var beep_timer: float = 0.0
var ui_ready: bool = false

func _ready():
	flicker.play()
	# Store original positions for glitch effect
	original_title_position = title_label.position
	original_launchpad_position = launchpad.position
	original_launchpad_shadow_position = launchpad_shadow.position

	# Rename Launch to Boot Colony
	launch_button.text = "Boot Colony"

	# Create save/load buttons
	_create_save_buttons()

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
	
	# Reveal elements immediately
	reveal_launchpad()
	await get_tree().create_timer(0.2).timeout
	reveal_title()
	await get_tree().create_timer(0.3).timeout
	reveal_ui()

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

func _process(delta):
	# Glitch effect (runs continuously)
	glitch_timer += delta
	if glitch_timer >= glitch_interval:
		glitch_timer = 0.0
		if randf() < glitch_chance:
			apply_glitch()
	
	if ui_ready:
		beep_timer += delta
		# Calculate interval: 2 seconds at 0 pressure, 0.4 seconds at 100 pressure
		var interval = remap(GameData.current_pressure, 0, 100, 2.0, 0.4)
		
		if beep_timer >= interval:
			beep_timer = 0.0
			play_visual_beep()

func reveal_ui():
	# Start ambient audio loops
	ambience_hum.play()
	drone_hum.play()
	electric_hum.play()
	#start_random_timer()

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(options_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(launch_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(abort_button, "modulate:a", 1.0, 0.5)
	if resume_button:
		tween.tween_property(resume_button, "modulate:a", 1.0, 0.5)
	if erase_button:
		tween.tween_property(erase_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(online_status, "modulate:a", 1.0, 0.5)
	tween.tween_property(online_status_rect, "modulate:a", 1.0, 0.5)

	await tween.finished   # <-- wait for fade-in to complete
	beep.play()
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
	# Randomly shift title or launchpad (with shadow)
	var is_title = randi() % 2 == 0
	var shift = Vector2(randf_range(-5, 5), randf_range(-3, 3))
	
	var tween = create_tween()
	
	if is_title:
		# Glitch the title
		tween.tween_property(title_label, "position", original_title_position + shift, 0.05)
		tween.chain().tween_property(title_label, "position", original_title_position, 0.05)
	else:
		# Glitch the launchpad and shadow together
		tween.set_parallel(true)
		tween.tween_property(launchpad, "position", original_launchpad_position + shift, 0.05)
		tween.tween_property(launchpad_shadow, "position", original_launchpad_shadow_position + shift, 0.05)
		
		tween.chain().set_parallel(true)
		tween.chain().tween_property(launchpad, "position", original_launchpad_position, 0.05)
		tween.chain().tween_property(launchpad_shadow, "position", original_launchpad_shadow_position, 0.05)

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


func _on_launch_pressed() -> void:
	AudioManager.play_ui("button_heavy")
	SceneTransition.transition_to("res://Scenes/main.tscn", SceneTransition.Type.ARMOUR)


func _on_options_pressed() -> void:
	AudioManager.play_sfx("upgrade", 1.0, -5.0)


# ═══════════════════════════════════════════════════════════════
# SAVE / LOAD UI
# ═══════════════════════════════════════════════════════════════

func _create_save_buttons() -> void:
	var hbox = $MarginContainer2/HBoxContainer

	# Only show save-related buttons if a save exists
	if not SaveManager.has_save():
		return

	# Resume Mission button
	resume_button = button_scene.instantiate()
	resume_button.text = "Resume"
	resume_button.custom_minimum_size = Vector2(200, 0)
	resume_button.add_theme_font_size_override("font_size", 32)
	resume_button.modulate.a = 0.0
	resume_button.pressed.connect(_on_resume_pressed)
	hbox.add_child(resume_button)
	hbox.move_child(resume_button, launch_button.get_index() + 1)

	# Erase Log button
	erase_button = button_scene.instantiate()
	erase_button.text = "Erase Log"
	erase_button.custom_minimum_size = Vector2(200, 0)
	erase_button.add_theme_font_size_override("font_size", 32)
	erase_button.modulate.a = 0.0
	erase_button.pressed.connect(_on_erase_pressed)
	hbox.add_child(erase_button)
	hbox.move_child(erase_button, resume_button.get_index() + 1)


func _on_resume_pressed() -> void:
	AudioManager.play_ui("button_heavy")
	SaveManager.load_game()


func _on_erase_pressed() -> void:
	AudioManager.play_sfx("upgrade", 1.0, -5.0)
	_show_erase_confirm()


func _show_erase_confirm() -> void:
	# Fullscreen semi-transparent overlay
	confirm_overlay = ColorRect.new()
	confirm_overlay.color = Color(0.04, 0.06, 0.08, 0.85)
	confirm_overlay.size = get_viewport_rect().size
	confirm_overlay.position = Vector2.ZERO
	add_child(confirm_overlay)

	# Warning label
	var label = Label.new()
	label.text = "PURGE SAVE DATA?\nTHIS CANNOT BE UNDONE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("ff4444"))
	var font = load("res://Assets/Fonts/JetBrainsMonoNL-SemiBold.ttf")
	if font:
		label.add_theme_font_override("font", font)
	label.position = Vector2(get_viewport_rect().size.x / 2 - 250, get_viewport_rect().size.y / 2 - 80)
	label.size = Vector2(500, 80)
	confirm_overlay.add_child(label)

	# Confirm button
	var confirm_btn = button_scene.instantiate()
	confirm_btn.text = "Confirm"
	confirm_btn.custom_minimum_size = Vector2(180, 0)
	confirm_btn.add_theme_font_size_override("font_size", 28)
	confirm_btn.position = Vector2(get_viewport_rect().size.x / 2 - 200, get_viewport_rect().size.y / 2 + 20)
	confirm_btn.pressed.connect(_on_erase_confirmed)
	confirm_overlay.add_child(confirm_btn)

	# Abort button
	var abort_btn = button_scene.instantiate()
	abort_btn.text = "Abort"
	abort_btn.custom_minimum_size = Vector2(180, 0)
	abort_btn.add_theme_font_size_override("font_size", 28)
	abort_btn.position = Vector2(get_viewport_rect().size.x / 2 + 20, get_viewport_rect().size.y / 2 + 20)
	abort_btn.pressed.connect(_on_erase_cancelled)
	confirm_overlay.add_child(abort_btn)

	# Fade in
	confirm_overlay.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(confirm_overlay, "modulate:a", 1.0, 0.2)


func _on_erase_confirmed() -> void:
	SaveManager.delete_save()
	AudioManager.play_sfx("upgrade", 1.0, -5.0)
	_close_confirm()
	# Remove the save buttons since save no longer exists
	if resume_button:
		resume_button.queue_free()
		resume_button = null
	if erase_button:
		erase_button.queue_free()
		erase_button = null


func _on_erase_cancelled() -> void:
	AudioManager.play_ui("button_click")
	_close_confirm()


func _close_confirm() -> void:
	if confirm_overlay:
		var tw = create_tween()
		tw.tween_property(confirm_overlay, "modulate:a", 0.0, 0.15)
		await tw.finished
		confirm_overlay.queue_free()
		confirm_overlay = null
