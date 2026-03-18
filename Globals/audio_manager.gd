extends Node

## =============================================================================
## AUDIO MANAGER  (autoload singleton)
## Handles all SFX, UI, and ambient audio.
##
## Usage from anywhere:
##   AudioManager.play_sfx("build_hub")
##   AudioManager.play_ui("btn_click")
##   AudioManager.play_atlas(NotificationManager.Type.WARNING)
##   AudioManager.set_volume("SFX", 0.8)
## =============================================================================

# ── Bus names (must match your Audio Bus Layout exactly) ─────────────────────
const BUS_SFX     := "SFX"
const BUS_UI      := "UI"
const BUS_AMBIENT := "Ambient"

# ── Pool sizes — how many simultaneous sounds per category ───────────────────
const SFX_POOL_SIZE     := 8
const UI_POOL_SIZE      := 4
const AMBIENT_POOL_SIZE := 6

# ── Ambient loop player indices (into _ambient_pool) ─────────────────────────
const AMBIENT_PRESSURE  := 0   # atmospheric pressure hum — pitch scales with pressure
const AMBIENT_FACILITY  := 1   # background facility hum — constant
const AMBIENT_FRACTURE  := 2   # fracture wave rumble — plays during wave events
const AMBIENT_PACKETS_A := 3   # packet flow layer A — pitch 0.8 (low)
const AMBIENT_PACKETS_B := 4   # packet flow layer B — pitch 1.0 (mid)
const AMBIENT_PACKETS_C := 5   # packet flow layer C — pitch 1.3 (high)

# ── Player pools ─────────────────────────────────────────────────────────────
var _sfx_pool     : Array[AudioStreamPlayer] = []
var _ui_pool      : Array[AudioStreamPlayer] = []
var _ambient_pool : Array[AudioStreamPlayer] = []

# ── Sound registry — populated in _register_sounds() ─────────────────────────
# Keys map to AudioStream resources.
# All values are null until you assign real audio files.
# Replace null with: load("res://Audio/sfx/your_file.ogg")
var _sfx_sounds   : Dictionary = {}
var _ui_sounds    : Dictionary = {}
var _atlas_sounds : Dictionary = {}   # keyed by NotificationManager.Type int
var _ambient_sounds : Dictionary = {}


# =============================================================================
func _ready() -> void:
	_build_pools()
	_register_sounds()
	_connect_signals()


# ═══════════════════════ PUBLIC API ══════════════════════════════════════════

func play_sfx(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream = _sfx_sounds.get(key)
	if stream == null:
		return
	var player := _get_free_player(_sfx_pool)
	if player == null:
		return
	player.stream      = stream
	player.pitch_scale = pitch
	player.volume_db   = volume_db
	player.bus         = BUS_SFX
	player.play()


func play_ui(key: String, volume_linear: float = 1.0, pitch: float = 1.0) -> void:
	var stream = _ui_sounds.get(key)
	if stream == null:
		return
	var player := _get_free_player(_ui_pool)
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
	var player := _get_free_player(_ui_pool)
	if player == null:
		return
	player.stream      = stream
	player.pitch_scale = pitch
	player.volume_db   = volume_db
	player.bus         = BUS_UI
	player.play()


## Start an ambient loop by slot index.
## e.g. AudioManager.start_ambient(AudioManager.AMBIENT_FACILITY)
func start_ambient(slot: int, stream: AudioStream = null) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	var player := _ambient_pool[slot]
	if stream != null:
		player.stream = stream
	if player.stream == null:
		return
	player.bus    = BUS_AMBIENT
	player.play()


## Stop an ambient loop by slot index.
func stop_ambient(slot: int) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	_ambient_pool[slot].stop()


## Set the pitch of an ambient loop — used by MusicManager to swell
## pressure hum as GameData.current_pressure rises.
func set_ambient_pitch(slot: int, pitch: float) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	_ambient_pool[slot].pitch_scale = pitch


## Set the volume of an ambient loop (linear 0.0–1.0).
func set_ambient_volume(slot: int, volume_linear: float) -> void:
	if slot < 0 or slot >= _ambient_pool.size():
		return
	var clamped := clampf(volume_linear, 0.001, 1.0)
	_ambient_pool[slot].volume_db = linear_to_db(clamped)


## Set a bus volume (linear 0.0–1.0).
## e.g. AudioManager.set_volume("SFX", 0.5)
func set_volume(bus_name: String, volume_linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(volume_linear, 0.001, 1.0)))


## Get a bus volume as linear (0.0–1.0).
func get_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


## Mute / unmute a bus.
func set_mute(bus_name: String, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, muted)


# ═══════════════════════ SIGNAL CONNECTIONS ═══════════════════════════════════

func _connect_signals() -> void:
	# ATLAS notification sounds — fire on every notify_player signal
	SignalBus.notify_player.connect(_on_notify_player)

	# Building sounds
	SignalBus.spawn_hub_requested.connect(_on_hub_spawned)
	SignalBus.spawn_vent_requested.connect(_on_vent_spawned)
	SignalBus.pipes_upgraded.connect(_on_pipes_upgraded)
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)


func _on_notify_player(message: String, type: int) -> void:
	play_atlas(type)


func _on_hub_spawned() -> void:
	play_sfx("build_hub")


func _on_vent_spawned() -> void:
	play_sfx("build_vent")


func _on_pipes_upgraded(_level: int) -> void:
	play_sfx("upgrade")


func _on_rocket_segment_purchased(_phase: int) -> void:
	play_sfx("rocket_upgrade")


# ═══════════════════════ SOUND REGISTRY ══════════════════════════════════════
## Register all audio streams here.
## Replace null with load("res://Audio/...") once you have audio files.
## Keys are stable strings — never change them once set,
## other scripts reference them by name.

func _register_sounds() -> void:
	# ── SFX ──────────────────────────────────────────────────────────────────
	_sfx_sounds = {
		# Building
		"build_hub"       : null,   # res://Audio/sfx/build_hub.ogg
		"build_vent"      : null,   # res://Audio/sfx/build_vent.ogg
		"build_pipe"      : load("res://Audio/sfx/socket_connect.ogg"),
		"remove_pipe"   : load("res://Audio/sfx/socket_disconnect.ogg"),
		"demolish"        : null,   # res://Audio/sfx/demolish.ogg
		# Damage & failure
		"pipe_fracture"   : null,   # res://Audio/sfx/pipe_fracture.ogg
		"pipe_burst"      : null,   # res://Audio/sfx/pipe_burst.ogg
		"hub_malfunction" : null,   # res://Audio/sfx/hub_malfunction.ogg
		"vent_fail"       : null,   # res://Audio/sfx/vent_fail.ogg
		# Repair
		"repair"          : null,   # res://Audio/sfx/repair.ogg
		# Upgrades
		"upgrade"         : null,   # res://Audio/sfx/upgrade.ogg
		"rocket_upgrade"  : null,   # res://Audio/sfx/rocket_upgrade.ogg
		# Events
		"fracture_wave"   : load("res://Audio/sfx/fracture_wave.mp3"),
		"fracture_wave_impact": load("res://Audio/sfx/fracture_wave_impact.mp3"),
		"fracture_wave_warning": load("res://Audio/sfx/fracture_warning.ogg"),
		"zone_reinforce"  : null,   # res://Audio/sfx/zone_reinforce.ogg
		"reward_granted"  : null,   # res://Audio/sfx/reward_granted.ogg
		"bg_thud_1" : load("res://Audio/sfx/thud1.ogg"),
		"bg_thud_2" : load("res://Audio/sfx/thud2.ogg"),
		"bg_thud_3" : load("res://Audio/sfx/thud3.ogg"),
		"bg_thud_4" : load("res://Audio/sfx/thud4.ogg"),
		"bg_thud_5" : load("res://Audio/sfx/thud5.ogg"),
		"bg_thud_6" : load("res://Audio/sfx/thud6.ogg"),
		"bg_thud_7" : load("res://Audio/sfx/thud7.ogg"),
	}

	# ── UI ────────────────────────────────────────────────────────────────────
	_ui_sounds = {
		"button_click"    : load("res://Audio/ui/button_click.ogg"),   # res://Audio/ui/btn_click.ogg
		"button_hover"    : load("res://Audio/ui/button_hover.wav"),   # res://Audio/ui/btn_hover.ogg
		"menu_open"       : load("res://Audio/ui/notification_open.ogg"),   # res://Audio/ui/menu_open.ogg
		"menu_close"      : load("res://Audio/ui/notification_close.ogg"),   # res://Audio/ui/menu_close.ogg
		"pause"           : null,   # res://Audio/ui/pause.ogg
		"error"           : load("res://Audio/ui/error.ogg"),
		"button_heavy"    : load("res://Audio/ui/heavy_thump.ogg"),
	}

	# ── ATLAS AI notification sounds ──────────────────────────────────────────
	# Keyed by NotificationManager.Type int values (0 = INFO, 1 = WARNING, 2 = ERROR)
	_atlas_sounds = {
		0 : load("res://Audio/ui/notification_open.ogg"),   # INFO    res://Audio/ui/atlas_info.ogg
		1 : load("res://Audio/ui/error.ogg"),   # WARNING res://Audio/ui/atlas_warning.ogg
		2 : load("res://Audio/ui/error.ogg"),   # ERROR   res://Audio/ui/atlas_error.ogg
	}

	# ── Ambient loops ─────────────────────────────────────────────────────────
	_ambient_sounds = {
		AMBIENT_PRESSURE  : null,                                          # res://Audio/ambient/pressure_hum.ogg
		AMBIENT_FACILITY  : null,                                          # res://Audio/ambient/facility_hum.ogg
		AMBIENT_FRACTURE  : null,                                          # res://Audio/ambient/fracture_rumble.ogg
		AMBIENT_PACKETS_A : load("res://Audio/sfx/harmonic_hum.ogg"),         # low layer   pitch 0.8
		AMBIENT_PACKETS_B : load("res://Audio/sfx/harmonic_hum.ogg"),         # mid layer   pitch 1.0
		AMBIENT_PACKETS_C : load("res://Audio/sfx/harmonic_hum.ogg"),         # high layer  pitch 1.3
	}

	# Assign ambient streams to their pool players
	for slot in _ambient_sounds:
		var stream = _ambient_sounds[slot]
		if stream != null and slot < _ambient_pool.size():
			_ambient_pool[slot].stream = stream

	# Set pitch variation on packet layers so they sound distinct
	_ambient_pool[AMBIENT_PACKETS_A].pitch_scale = 0.6
	_ambient_pool[AMBIENT_PACKETS_B].pitch_scale = 0.7
	_ambient_pool[AMBIENT_PACKETS_C].pitch_scale = 0.8

	# Start all packet layers at zero volume — MusicManager scales them
	_ambient_pool[AMBIENT_PACKETS_A].volume_db = -80.0
	_ambient_pool[AMBIENT_PACKETS_B].volume_db = -80.0
	_ambient_pool[AMBIENT_PACKETS_C].volume_db = -80.0


# ═══════════════════════ NODE BUILDERS ═══════════════════════════════════════

func _build_pools() -> void:
	_sfx_pool     = _make_pool(SFX_POOL_SIZE,     "SFX_")
	_ui_pool      = _make_pool(UI_POOL_SIZE,       "UI_")
	_ambient_pool = _make_pool(AMBIENT_POOL_SIZE,  "Ambient_")

	# Ambient players loop by default
	for p in _ambient_pool:
		p.bus = BUS_AMBIENT


func _make_pool(size: int, prefix: String) -> Array[AudioStreamPlayer]:
	var pool : Array[AudioStreamPlayer] = []
	for i in size:
		var p := AudioStreamPlayer.new()
		p.name = prefix + str(i)
		add_child(p)
		pool.append(p)
	return pool


# ═══════════════════════ HELPERS ═════════════════════════════════════════════

## Returns the first player in the pool that is not currently playing.
## Returns null if all players are busy (sound is skipped — never blocks).
func _get_free_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return null
