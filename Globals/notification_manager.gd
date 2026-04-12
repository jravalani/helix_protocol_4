extends CanvasLayer

enum Type { INFO, WARNING, ERROR, OBJECTIVE }

const NOTIFICATION_SCENE := preload("res://Scenes/notification.tscn")
const MAX_NOTIFICATIONS := 5

@onready var container: VBoxContainer = $MarginContainer/VBoxContainer

func _ready() -> void:
	SignalBus.notify_player.connect(_on_notify_player)

func _on_notify_player(message: String, type: int) -> void:
	notify(message, type as Type)

## Public API — call this from anywhere.
func notify(message: String, type: Type = Type.INFO, title: String = "") -> void:
	# Remove oldest immediately if at cap
	while container.get_child_count() >= MAX_NOTIFICATIONS:
		var oldest = container.get_child(0)
		oldest.get_parent().remove_child(oldest)
		oldest.queue_free()

	var n := NOTIFICATION_SCENE.instantiate()
	container.add_child(n)
	n.setup(message, type, title)
