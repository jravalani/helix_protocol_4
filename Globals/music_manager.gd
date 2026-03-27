extends Node

#region Constants

enum MusicStage { NONE, MENU, CALM, TENSE, CRITICAL, EMERGENCY, OPTIMISTIC }

const CROSSFADE_TIME = 5.0

const STAGE_THRESHOLDS = {
	MusicStage.CALM      : 2,
	MusicStage.TENSE     : 3,
	MusicStage.CRITICAL  : 6,
	MusicStage.EMERGENCY : 10,
}

#endregion

#region Variables

var _player_a      : AudioStreamPlayer
var _player_b      : AudioStreamPlayer
var _active_player : AudioStreamPlayer

var _current_stage : MusicStage = MusicStage.NONE
var _is_in_game    : bool       = false
var _tween         : Tween

var _tracks : Dictionary = {
	MusicStage.MENU       : null,
	MusicStage.CALM       : null,
	MusicStage.TENSE      : null,
	MusicStage.CRITICAL   : null,
	MusicStage.EMERGENCY  : null,
	MusicStage.OPTIMISTIC : load("res://Audio/music/optimistic.ogg"),
}

#endregion

#region Lifecycle

func _ready() -> void:
	_build_players()
	SignalBus.spawn_hub_requested.connect(_on_hub_spawned)
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)


func _process(_delta: float) -> void:
	if not _is_in_game:
		return
	_update_pressure_ambient()

#endregion

#region Public API

func play_game_music() -> void:
	_is_in_game    = true
	_current_stage = MusicStage.NONE
	AudioManager.start_ambient(AudioManager.AMBIENT_FACILITY)
	AudioManager.start_ambient(AudioManager.AMBIENT_PRESSURE)
	AudioManager.start_ambient(AudioManager.AMBIENT_PACKETS_A)
	AudioManager.start_ambient(AudioManager.AMBIENT_PACKETS_B)
	AudioManager.start_ambient(AudioManager.AMBIENT_PACKETS_C)
	AudioManager.start_ambient(AudioManager.AMBIENT_VENT_A)
	AudioManager.start_ambient(AudioManager.AMBIENT_VENT_B)
	AudioManager.start_ambient(AudioManager.AMBIENT_HUB_A)
	AudioManager.start_ambient(AudioManager.AMBIENT_HUB_B)
	AudioManager.start_ambient(AudioManager.AMBIENT_STEAM_A)
	AudioManager.start_ambient(AudioManager.AMBIENT_STEAM_B)


func play_win_music() -> void:
	_play_once(MusicStage.OPTIMISTIC)
	_is_in_game = false
	AudioManager.stop_ambient(AudioManager.AMBIENT_PRESSURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_FRACTURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_B)
	#AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_C)
	AudioManager.stop_ambient(AudioManager.AMBIENT_VENT_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_VENT_B)
	AudioManager.stop_ambient(AudioManager.AMBIENT_HUB_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_HUB_B)



func stop_music(fade_time: float = 2.0) -> void:
	_is_in_game = false
	AudioManager.stop_ambient(AudioManager.AMBIENT_PRESSURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_FACILITY)
	AudioManager.stop_ambient(AudioManager.AMBIENT_FRACTURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_B)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_C)
	AudioManager.stop_ambient(AudioManager.AMBIENT_VENT_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_VENT_B)
	AudioManager.stop_ambient(AudioManager.AMBIENT_HUB_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_HUB_B)
	AudioManager.stop_ambient(AudioManager.AMBIENT_STEAM_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_STEAM_B)
	_fade_out_active(fade_time)


func on_fracture_wave(active: bool) -> void:
	if active:
		AudioManager.start_ambient(AudioManager.AMBIENT_FRACTURE)
	else:
		AudioManager.stop_ambient(AudioManager.AMBIENT_FRACTURE)

#endregion

#region Signal Handlers

func _on_hub_spawned() -> void:
	_evaluate_hub_stage()


func _on_rocket_segment_purchased(phase: int) -> void:
	if phase == 5:
		play_win_music()

#endregion

#region Hub Stage Logic

func _evaluate_hub_stage() -> void:
	var hubs      = GameData.current_hub_count
	var new_stage : MusicStage

	if hubs >= STAGE_THRESHOLDS[MusicStage.EMERGENCY]:
		new_stage = MusicStage.EMERGENCY
	elif hubs >= STAGE_THRESHOLDS[MusicStage.CRITICAL]:
		new_stage = MusicStage.CRITICAL
	elif hubs >= STAGE_THRESHOLDS[MusicStage.TENSE]:
		new_stage = MusicStage.TENSE
	else:
		new_stage = MusicStage.CALM

	if new_stage != _current_stage:
		_current_stage = new_stage
		_play_once(new_stage)

#endregion

#region Ambient Updates

func _update_pressure_ambient() -> void:
	var t     = GameData.current_pressure / GameData.MAX_PRESSURE
	var pitch = lerpf(0.9, 1.3, t)
	AudioManager.set_ambient_pitch(AudioManager.AMBIENT_PRESSURE, pitch)

	var vol = clampf(lerpf(0.0, 1.0, (t - 0.2) / 0.8), 0.0, 1.0)
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PRESSURE, vol)

	var count = GameData.active_packet_count
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PACKETS_A, clampf(count / 5.0,            0.001, 0.6))
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PACKETS_B, clampf((count - 5.0) / 10.0,  0.001, 0.5))
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PACKETS_C, clampf((count - 15.0) / 15.0, 0.001, 0.4))

	var vents = float(GameData.current_vent_count)
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_VENT_A, clampf(vents / 5.0,          0.001, 1.0))
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_VENT_B, clampf((vents - 5.0) / 10.0, 0.001, 1.0))

	var hubs = float(GameData.current_hub_count)
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_HUB_A, clampf(hubs / 5.0,          0.001, 1.0))
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_HUB_B, clampf((hubs - 5.0) / 10.0, 0.001, 1.0))

	var fractured = float(GameData.fractured_pipes.size())
	if fractured <= 0.0:
		AudioManager._ambient_pool[AudioManager.AMBIENT_STEAM_A].volume_db = -80.0
		AudioManager._ambient_pool[AudioManager.AMBIENT_STEAM_B].volume_db = -80.0
	else:
		var vol_a = lerpf(-20.0, -10.0, clampf((fractured - 1.0) / 3.0, 0.0, 1.0))
		var vol_b = lerpf(-30.0, -10.0, clampf((fractured - 3.0) / 2.0, 0.0, 1.0))
		AudioManager._ambient_pool[AudioManager.AMBIENT_STEAM_A].volume_db = vol_a
		AudioManager._ambient_pool[AudioManager.AMBIENT_STEAM_B].volume_db = vol_b

#endregion

#region Playback

func _play_once(stage: MusicStage) -> void:
	var stream = _tracks.get(stage)
	if stream == null:
		return

	var incoming = _player_b if _active_player == _player_a else _player_a
	incoming.stream    = stream
	incoming.volume_db = -80.0
	incoming.bus       = "Music"
	incoming.play()

	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)

	_tween.tween_property(incoming, "volume_db",
		-5.0, CROSSFADE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _active_player and _active_player.playing:
		var outgoing = _active_player
		_tween.tween_property(outgoing, "volume_db",
			-80.0, CROSSFADE_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await _tween.finished
		outgoing.stop()

	_active_player = incoming

	await incoming.finished
	if _active_player == incoming and _is_in_game:
		_fade_out_active(CROSSFADE_TIME)


func _fade_out_active(duration: float = CROSSFADE_TIME) -> void:
	if _active_player == null or not _active_player.playing:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target = _active_player
	_tween.tween_property(target, "volume_db",
		-80.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _tween.finished
	target.stop()

#endregion

#region Node Builders

func _build_players() -> void:
	_player_a           = AudioStreamPlayer.new()
	_player_a.name      = "MusicPlayerA"
	_player_a.bus       = "Music"
	_player_a.volume_db = -20.0
	add_child(_player_a)

	_player_b           = AudioStreamPlayer.new()
	_player_b.name      = "MusicPlayerB"
	_player_b.bus       = "Music"
	_player_b.volume_db = -20.0
	add_child(_player_b)

	_active_player = _player_a

#endregion
