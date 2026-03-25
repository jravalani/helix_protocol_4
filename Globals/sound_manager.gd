extends Node

## SFX manager — loads pre-exported MP3 files from res://sounds/.
## To regenerate the MP3s, run: python3 tools/export_sounds.py
## Frequently-triggered sounds get a polyphonic pool so overlapping plays don't cut off.

const POLY_COUNT := 4

# _players[name] = Array[AudioStreamPlayer]  (pool)
var _players: Dictionary = {}
var _poly_idx: Dictionary = {}


func _ready() -> void:
	_register("packet_delivered", load("res://sounds/packet_delivered.mp3"), 1)
	_register("pipe_place",       load("res://sounds/pipe_place.mp3"),       POLY_COUNT)
	_register("fracture_wave",    load("res://sounds/fracture_wave.mp3"),    1)
	_register("rocket_launch",    load("res://sounds/rocket_launch.mp3"),    1)
	_register("packet_spawned",   load("res://sounds/packet_spawned.mp3"),   POLY_COUNT)
	_register("pipe_fracture",    load("res://sounds/pipe_fracture.mp3"),    POLY_COUNT)
	_register("hub_fracture",     load("res://sounds/hub_fracture.mp3"),     1)


func play(sound_name: String, volume_db: float = 0.0) -> void:
	var pool: Array = _players.get(sound_name, [])
	if pool.is_empty():
		return
	var idx: int = _poly_idx.get(sound_name, 0)
	var player: AudioStreamPlayer = pool[idx % pool.size()]
	player.volume_db = volume_db
	player.play()
	_poly_idx[sound_name] = idx + 1


# ═══════════════════════════════════════════
# Registration
# ═══════════════════════════════════════════

func _register(snd_name: String, stream: AudioStream, pool_size: int) -> void:
	var pool: Array = []
	for i in range(pool_size):
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Master"
		add_child(p)
		pool.append(p)
	_players[snd_name] = pool
