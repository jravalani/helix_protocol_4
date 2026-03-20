extends Node

#region Constants

const BUS_SFX     = "SFX"
const BUS_UI      = "UI"
const BUS_AMBIENT = "Ambient"

const SFX_POOL_SIZE     = 8
const UI_POOL_SIZE      = 4
const AMBIENT_POOL_SIZE = 12

const AMBIENT_PRESSURE  = 0
const AMBIENT_FACILITY  = 1
const AMBIENT_FRACTURE  = 2
const AMBIENT_PACKETS_A = 3
const AMBIENT_PACKETS_B = 4
const AMBIENT_PACKETS_C = 5
const AMBIENT_VENT_A    = 6
const AMBIENT_VENT_B    = 7
const AMBIENT_HUB_A     = 8
const AMBIENT_HUB_B     = 9
const AMBIENT_STEAM_A   = 10
const AMBIENT_STEAM_B   = 11

#endregion

#region Variables

var _sfx_pool     : Array[AudioStreamPlayer] = []
var _ui_pool      : Array[AudioStreamPlayer] = []
var _ambient_pool : Array[AudioStreamPlayer] = []

var _sfx_sounds     : Dictionary = {}
var _ui_sounds      : Dictionary = {}
var _atlas_sounds   : Dictionary = {}
var _ambient_sounds : Dictionary = {}

#endregion

#region Lifecycle

func _ready() -> void:
	_build_pools()
	_register_sounds()
	_connect_signals()

#endregion

#region Public API

func play_sfx(key: String, pitch: float = 1.0, volume_db: float = 0.0, bus: String = BUS_SFX) -> void:
	var stream = _sfx_sounds.get(key)
	if stream == null:
		return
	var player = _get_free_player(_sfx_pool)
	if player == null:
		return
	player.stream      = stream
	player.pitch_scale = pitch
	player.volume_db   = volume_db
	player.bus         = bus
	player.play()


func play_ui(key: String, volume_linear: float = 1.0, pitch: float = 1.0) -> void:
	var stream = _ui_sounds.get(key)
	if stream == null:
		return
	var player = _get_free_player(_ui_pool)
	if player == null:
		return
	player.stream      = stream
	player.pitch_scale = pitch
	player.volume_db   = linear_to_db(clampf(volume_linear, 0.001, 1.0))
	player.bus         = BUS_UI
	player.play()


func play_atlas(type: int, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream = _atlas_sounds.get(type)
	if stream == null:
		return
	var player = _get_free_player(_ui_pool)
	if player == null:
		return
	player.stream      = stream
	player.pitch_scale = pitch
	player.volume_db   = volume_db
	player.bus         = BUS_UI
	player.play()


func start_ambient(slot: int, stream: AudioStream = null) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	var player = _ambient_pool[slot]
	if stream != null:
		player.stream = stream
	if player.stream == null:
		return
	player.bus = BUS_AMBIENT
	player.play()


func stop_ambient(slot: int) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	_ambient_pool[slot].stop()


func set_ambient_pitch(slot: int, pitch: float) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	_ambient_pool[slot].pitch_scale = pitch


func set_ambient_volume(slot: int, volume_linear: float) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	_ambient_pool[slot].volume_db = linear_to_db(clampf(volume_linear, 0.001, 1.0))


func set_volume(bus_name: String, volume_linear: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(volume_linear, 0.001, 1.0)))


func get_volume(bus_name: String) -> float:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func set_mute(bus_name: String, muted: bool) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, muted)

#endregion

#region Signals

func _connect_signals() -> void:
	SignalBus.notify_player.connect(_on_notify_player)


func _on_notify_player(_message: String, type: int) -> void:
	play_atlas(type)

#endregion

#region Sound Registry

func _register_sounds() -> void:
	_sfx_sounds = {
		"click_a"               : load("res://Audio/sfx/bass_thum_short.ogg"),
		"build_hub"             : load("res://Audio/sfx/build.wav"),
		"build_vent"            : load("res://Audio/sfx/build.wav"),
		"build_pipe"            : load("res://Audio/sfx/socket_connect.ogg"),
		"remove_pipe"           : load("res://Audio/sfx/socket_disconnect.ogg"),
		"hub_repair"            : load("res://Audio/sfx/hub_repair.ogg"),
		"pipe_fracture"         : null,
		"pipe_burst"            : null,
		"hub_malfunction"       : null,
		"vent_fail"             : null,
		"repair"                : load("res://Audio/sfx/normal_upgrade.mp3"),
		"upgrade"               : load("res://Audio/sfx/normal_upgrade.mp3"),
		"rocket_upgrade"        : load("res://Audio/sfx/rocket_upgrade.mp3"),
		"fracture_wave"         : load("res://Audio/sfx/fracture_wave.mp3"),
		"fracture_wave_impact"  : load("res://Audio/sfx/fracture_wave_impact.mp3"),
		"fracture_wave_warning" : load("res://Audio/sfx/fracture_warning.ogg"),
		"zone_reinforce"        : load("res://Audio/sfx/reinforce.ogg"),
		"reward_granted"        : null,
		"bg_thud_1"             : load("res://Audio/sfx/thud1.ogg"),
		"bg_thud_2"             : load("res://Audio/sfx/thud2.ogg"),
		"bg_thud_3"             : load("res://Audio/sfx/thud3.ogg"),
		"bg_thud_4"             : load("res://Audio/sfx/thud4.ogg"),
		"bg_thud_5"             : load("res://Audio/sfx/thud5.ogg"),
		"bg_thud_6"             : load("res://Audio/sfx/thud6.ogg"),
		"bg_thud_7"             : load("res://Audio/sfx/thud7.ogg"),
	}

	_ui_sounds = {
		"button_click" : load("res://Audio/ui/button_click.ogg"),
		"button_hover" : load("res://Audio/ui/button_hover.wav"),
		"menu_open"    : load("res://Audio/ui/notification_open.ogg"),
		"menu_close"   : load("res://Audio/ui/notification_close.ogg"),
		"pause"        : null,
		"error"        : load("res://Audio/ui/error.ogg"),
		"button_heavy" : load("res://Audio/ui/launch_button.wav"),
	}

	_atlas_sounds = {
		0 : load("res://Audio/ui/notification_open.ogg"),
		1 : load("res://Audio/ui/error.ogg"),
		2 : load("res://Audio/ui/error.ogg"),
	}

	_ambient_sounds = {
		AMBIENT_PRESSURE  : null,
		AMBIENT_FACILITY  : null,
		AMBIENT_FRACTURE  : null,
		AMBIENT_PACKETS_A : load("res://Audio/sfx/harmonic_hum.ogg"),
		AMBIENT_PACKETS_B : load("res://Audio/sfx/harmonic_hum.ogg"),
		AMBIENT_PACKETS_C : load("res://Audio/sfx/harmonic_hum.ogg"),
		AMBIENT_VENT_A    : load("res://Audio/sfx/vent_hiss.ogg"),
		AMBIENT_VENT_B    : load("res://Audio/sfx/vent_hiss.ogg"),
		AMBIENT_HUB_A     : load("res://Audio/sfx/hub_bleeps.ogg"),
		AMBIENT_HUB_B     : load("res://Audio/sfx/hub_bleeps.ogg"),
		AMBIENT_STEAM_A   : load("res://Audio/sfx/pipe_fracture.mp3"),
		AMBIENT_STEAM_B   : load("res://Audio/sfx/pipe_fracture.mp3"),
	}

	for slot in _ambient_sounds:
		var stream = _ambient_sounds[slot]
		if stream != null and slot < _ambient_pool.size():
			_ambient_pool[slot].stream = stream

	_ambient_pool[AMBIENT_PACKETS_A].pitch_scale = 0.3
	_ambient_pool[AMBIENT_PACKETS_B].pitch_scale = 0.4
	_ambient_pool[AMBIENT_PACKETS_C].pitch_scale = 0.5
	_ambient_pool[AMBIENT_PACKETS_A].volume_db   = -80.0
	_ambient_pool[AMBIENT_PACKETS_B].volume_db   = -80.0
	_ambient_pool[AMBIENT_PACKETS_C].volume_db   = -80.0

	_ambient_pool[AMBIENT_VENT_A].pitch_scale = 0.9
	_ambient_pool[AMBIENT_VENT_B].pitch_scale = 1.1
	_ambient_pool[AMBIENT_VENT_A].volume_db   = -20.0
	_ambient_pool[AMBIENT_VENT_B].volume_db   = -20.0

	_ambient_pool[AMBIENT_HUB_A].pitch_scale = 0.9
	_ambient_pool[AMBIENT_HUB_B].pitch_scale = 1.1
	_ambient_pool[AMBIENT_HUB_A].volume_db   = -20.0
	_ambient_pool[AMBIENT_HUB_B].volume_db   = -20.0

	_ambient_pool[AMBIENT_STEAM_A].pitch_scale = 0.9
	_ambient_pool[AMBIENT_STEAM_B].pitch_scale = 1.1
	_ambient_pool[AMBIENT_STEAM_A].volume_db   = -20.0
	_ambient_pool[AMBIENT_STEAM_B].volume_db   = -20.0

#endregion

#region Pool Builders

func _build_pools() -> void:
	_sfx_pool     = _make_pool(SFX_POOL_SIZE,    "SFX_")
	_ui_pool      = _make_pool(UI_POOL_SIZE,      "UI_")
	_ambient_pool = _make_pool(AMBIENT_POOL_SIZE, "Ambient_")
	for p in _ambient_pool:
		p.bus = BUS_AMBIENT


func _make_pool(size: int, prefix: String) -> Array[AudioStreamPlayer]:
	var pool : Array[AudioStreamPlayer] = []
	for i in size:
		var p = AudioStreamPlayer.new()
		p.name = prefix + str(i)
		add_child(p)
		pool.append(p)
	return pool


func _get_free_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return null

#endregion
