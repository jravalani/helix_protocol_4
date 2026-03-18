extends Node

## =============================================================================
## MUSIC MANAGER  (autoload singleton)
## Hub-count reactive music using Generative Spacing.
##
## Philosophy:
##   Ambient drone + fan hum are the constant foundation.
##   Music tracks are EVENTS — they play once when hub count crosses a
##   threshold, then silence returns until the next threshold is crossed.
##   This ties the music directly to player progression rather than time,
##   and prevents ear fatigue across a 45 minute session.
##
## Music map:
##   0–2  hubs → CALM       → tranquil.ogg
##   3–5  hubs → TENSE      → background_ambience.ogg
##   6–9  hubs → CRITICAL   → eerie.ogg
##   10+  hubs → EMERGENCY  → eerie.ogg
##   Segment 5 → OPTIMISTIC → optimistic.ogg  (rocket fully built)
##
## Usage:
##   MusicManager.play_game_music()  ← call when game scene loads
##   MusicManager.play_win_music()   ← called automatically on segment 5
##   MusicManager.stop_music()       ← call on lose scene
## =============================================================================

# ── Music stages ──────────────────────────────────────────────────────────────
enum MusicStage { NONE, MENU, CALM, TENSE, CRITICAL, EMERGENCY, OPTIMISTIC }

# ── Timing ────────────────────────────────────────────────────────────────────
const CROSSFADE_TIME := 5.0   # seconds to crossfade between tracks

# ── Hub count thresholds per music stage ──────────────────────────────────────
const STAGE_THRESHOLDS := {
	MusicStage.CALM      : 2,   # was 0 — now waits for 2nd hub
	MusicStage.TENSE     : 3,
	MusicStage.CRITICAL  : 6,
	MusicStage.EMERGENCY : 10,
}

# ── A/B players for crossfading ───────────────────────────────────────────────
var _player_a      : AudioStreamPlayer
var _player_b      : AudioStreamPlayer
var _active_player : AudioStreamPlayer

# ── State ─────────────────────────────────────────────────────────────────────
var _current_stage : MusicStage = MusicStage.NONE
var _is_in_game    : bool       = false
var _tween         : Tween

# ── Music registry ────────────────────────────────────────────────────────────
# Tracks play ONCE per stage change then return to ambient-only silence.
# Replace null with load("res://Audio/music/...") once files are ready.
var _tracks : Dictionary = {
	MusicStage.MENU       : null,
	MusicStage.CALM       : load("res://Audio/music/tranquil.ogg"),
	MusicStage.TENSE      : load("res://Audio/music/background_ambience.ogg"),
	MusicStage.CRITICAL   : load("res://Audio/music/eerie.ogg"),
	MusicStage.EMERGENCY  : load("res://Audio/music/eerie.ogg"),
	MusicStage.OPTIMISTIC : load("res://Audio/music/optimistic.ogg"),
}


# =============================================================================
func _ready() -> void:
	_build_players()
	# Music stage changes on hub placement
	SignalBus.spawn_hub_requested.connect(_on_hub_spawned)
	# Win music on rocket completion
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)


func _process(delta: float) -> void:
	if not _is_in_game:
		return
	# Ambient pressure hum still reacts to pressure continuously
	_update_pressure_ambient()


# ═══════════════════════ PUBLIC API ══════════════════════════════════════════

## Call when gameplay begins (after scene load).
func play_game_music() -> void:
	_is_in_game    = true
	_current_stage = MusicStage.NONE
	AudioManager.start_ambient(AudioManager.AMBIENT_FACILITY)
	AudioManager.start_ambient(AudioManager.AMBIENT_PRESSURE)
	AudioManager.start_ambient(AudioManager.AMBIENT_PACKETS_A)
	AudioManager.start_ambient(AudioManager.AMBIENT_PACKETS_B)
	AudioManager.start_ambient(AudioManager.AMBIENT_PACKETS_C)


## Called automatically when rocket segment 5 is purchased.
## Optimistic plays once — carries the player to the launch button.
## Facility hum keeps running — the base is still operational.
func play_win_music() -> void:
	_is_in_game = false
	AudioManager.stop_ambient(AudioManager.AMBIENT_PRESSURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_FRACTURE)
	_play_once(MusicStage.OPTIMISTIC)


## Call on lose scene — fades everything out completely.
func stop_music(fade_time: float = 2.0) -> void:
	_is_in_game = false
	AudioManager.stop_ambient(AudioManager.AMBIENT_PRESSURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_FACILITY)
	AudioManager.stop_ambient(AudioManager.AMBIENT_FRACTURE)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_A)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_B)
	AudioManager.stop_ambient(AudioManager.AMBIENT_PACKETS_C)
	_fade_out_active(fade_time)


## Called by your fracture wave system when a wave starts / ends.
func on_fracture_wave(active: bool) -> void:
	if active:
		AudioManager.start_ambient(AudioManager.AMBIENT_FRACTURE)
	else:
		AudioManager.stop_ambient(AudioManager.AMBIENT_FRACTURE)


# ═══════════════════════ SIGNAL HANDLERS =====================================

func _on_hub_spawned() -> void:
	_evaluate_hub_stage()


func _on_rocket_segment_purchased(phase: int) -> void:
	if phase == 5:
		play_win_music()


# ═══════════════════════ HUB STAGE LOGIC =====================================

func _evaluate_hub_stage() -> void:
	var hubs      := GameData.current_hub_count
	var new_stage : MusicStage

	if hubs >= STAGE_THRESHOLDS[MusicStage.EMERGENCY]:
		new_stage = MusicStage.EMERGENCY
	elif hubs >= STAGE_THRESHOLDS[MusicStage.CRITICAL]:
		new_stage = MusicStage.CRITICAL
	elif hubs >= STAGE_THRESHOLDS[MusicStage.TENSE]:
		new_stage = MusicStage.TENSE
	else:
		new_stage = MusicStage.CALM

	# Only trigger music if the stage actually changed
	if new_stage != _current_stage:
		_current_stage = new_stage
		_play_once(new_stage)


# ═══════════════════════ PRESSURE AMBIENT ====================================

func _update_pressure_ambient() -> void:
	# Pitch: 0.9 at pressure 0 → 1.3 at pressure 100
	var t     := GameData.current_pressure / GameData.MAX_PRESSURE
	var pitch := lerpf(0.9, 1.3, t)
	AudioManager.set_ambient_pitch(AudioManager.AMBIENT_PRESSURE, pitch)

	# Volume swells in gradually from 20% pressure onward
	var vol := clampf(lerpf(0.0, 1.0, (t - 0.2) / 0.8), 0.0, 1.0)
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PRESSURE, vol)

	# Packet flow layers — each fades in at different packet count thresholds
	# Layer A (low)  : fades in  0–5  packets
	# Layer B (mid)  : fades in  5–15 packets
	# Layer C (high) : fades in 15–30 packets
	var count := GameData.active_packet_count
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PACKETS_A, clampf(count / 5.0,           0.001, 1.0))
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PACKETS_B, clampf((count - 5.0) / 10.0,  0.001, 1.0))
	AudioManager.set_ambient_volume(AudioManager.AMBIENT_PACKETS_C, clampf((count - 15.0) / 15.0, 0.001, 1.0))

# ═══════════════════════ PLAYBACK ============================================

## Core of Generative Spacing — plays a track once then fades back to silence.
## The next music cue won't happen until the hub count crosses a new threshold.
func _play_once(stage: MusicStage) -> void:
	var stream = _tracks.get(stage)
	if stream == null:
		return

	# Pick the inactive player as incoming
	var incoming := _player_b if _active_player == _player_a else _player_a
	incoming.stream    = stream
	incoming.volume_db = -80.0
	incoming.bus       = "Music"
	incoming.play()

	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)

	# Fade incoming up
	_tween.tween_property(incoming, "volume_db",
		-5.0, CROSSFADE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Fade outgoing down
	if _active_player and _active_player.playing:
		var outgoing := _active_player
		_tween.tween_property(outgoing, "volume_db",
			-80.0, CROSSFADE_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await _tween.finished
		outgoing.stop()

	_active_player = incoming

	# Track plays to its natural end then fades back to ambient-only silence
	await incoming.finished
	if _active_player == incoming and _is_in_game:
		_fade_out_active(CROSSFADE_TIME)


func _fade_out_active(duration: float = CROSSFADE_TIME) -> void:
	if _active_player == null or not _active_player.playing:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target := _active_player
	_tween.tween_property(target, "volume_db",
		-80.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _tween.finished
	target.stop()


# ═══════════════════════ NODE BUILDERS =======================================

func _build_players() -> void:
	_player_a      = AudioStreamPlayer.new()
	_player_a.name = "MusicPlayerA"
	_player_a.bus  = "Music"
	_player_a.volume_db = -20.0
	add_child(_player_a)

	_player_b      = AudioStreamPlayer.new()
	_player_b.name = "MusicPlayerB"
	_player_b.bus  = "Music"
	_player_b.volume_db = -20.0
	add_child(_player_b)

	_active_player = _player_a
