extends Button

@onready var hover_style: StyleBoxFlat = get_theme_stylebox("hover")
var hum_tween: Tween

func _on_mouse_entered():
	
	
	#win scence
	WinSceneData.pipe_tiles     = 45
	WinSceneData.peak_pressure  = 2.51
	WinSceneData.data_collected = 24991
	WinSceneData.repair_reserve = 3
	
	SceneTransition.transition_to("res://Scenes/win_scene.tscn", SceneTransition.Type.ARMOUR)
	
	#loose scence
	#WinSceneData.pipe_tiles     = 33 
	#WinSceneData.peak_pressure  = 8.4
	#WinSceneData.data_collected = 12000
	#WinSceneData.survival_time  = 240.0    
	#WinSceneData.failure_cause = "PRESSURE OVERLOAD"
	#SceneTransition.transition_to("res://Scenes/LoseScene.tscn", SceneTransition.Type.ARMOUR)
	AudioManager.play_ui("button_hover", 0.2)
	# Create a pulsing effect on the border color
	hum_tween = create_tween().set_loops()
	hum_tween.tween_property(hover_style, "border_color", Color("ff00ff"), 0.8)
	hum_tween.tween_property(hover_style, "border_color", Color("700070"), 0.8)
	
	# Scale up slightly
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_mouse_exited():
	if hum_tween:
		hum_tween.kill()
	
	# Scale back to normal
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
