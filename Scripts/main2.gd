extends Node2D

@onready var drone_hum: AudioStreamPlayer2D = $Drone
@onready var ambience_hum: AudioStreamPlayer2D = $Ambience
@onready var electric_hum: AudioStreamPlayer2D = $ElectricHum

var _thump_timer : float = 0.0
var _next_thump  : float = 0.0

func _ready() -> void:
	drone_hum.play()
	ambience_hum.play()
	electric_hum.play()
	MusicManager.play_game_music()
	_next_thump = randf_range(12.0, 16.0)

func _process(delta: float) -> void:
	_thump_timer += delta
	if _thump_timer >= _next_thump:
		_play_random_bg()
		_thump_timer = 0.0
		_next_thump = randf_range(12.0, 16.0)

func _play_random_bg() -> void:
	var sounds = [
		"bg_thud_1", "bg_thud_2", "bg_thud_3",
		"bg_thud_4", "bg_thud_5", "bg_thud_6", "bg_thud_7"
	]
	AudioManager.play_sfx(sounds[randi() % sounds.size()], 0.5)
