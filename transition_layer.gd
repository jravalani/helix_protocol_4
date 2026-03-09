extends CanvasLayer

@onready var root: Control = $Root
@onready var anim: AnimationPlayer = $Root/AnimationPlayer

var next_scene_path: String = ""
var busy: bool = false

func _ready() -> void:
	root.visible = false
	anim.animation_finished.connect(_on_animation_finished)

func go_to(scene_path: String) -> void:
	if busy:
		return

	busy = true
	next_scene_path = scene_path
	root.visible = true
	anim.play("close")

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "close":
		get_tree().change_scene_to_file(next_scene_path)
		anim.play("open")
	elif anim_name == "open":
		root.visible = false
		busy = false
