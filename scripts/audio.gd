# audio.gd
# Autoloaded as "Audio". Single entry point for all sound playback.
#
# Design philosophy (decided with Samuel):
#   - Positional 2D audio for in-world sounds (firing, hits, explosions,
#     ram, engine, tracks, pickups) so spatial cues do the heavy lifting.
#   - Listener attached to the local player's tank, not the camera, so
#     "you" are always the loudest reference frame.
#   - +2 dB self-boost on the local player's own sounds — subtle weight
#     without breaking the "loud = close" rule.
#   - Pitch jitter on every play so simultaneous repeats don't stack into
#     a single muddy hit.
#   - Three buses (SFX, Music, UI) for clean volume control.

extends Node

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
const SELF_BOOST_DB: float = 2.0
const PITCH_JITTER:  float = 0.05  # ±5%
const VOLUME_JITTER: float = 1.0   # ±1 dB

const DEFAULT_MAX_DIST_PX: float = 1800.0  # arena diagonal ≈ 1470 px
const DEFAULT_ATTENUATION: float = 1.4

const _SETTINGS_PATH := "user://audio_settings.cfg"

# ---------------------------------------------------------------------------
# Stream catalog
# ---------------------------------------------------------------------------
const SFX_PATHS := {
	"tank_fire":      "res://assets/audio/sfx/tank_fire.mp3",
	"bullet_hit":     "res://assets/audio/sfx/bullet_hit.ogg",
	"explosion":      "res://assets/audio/sfx/explosion.mp3",
	"ram_impact":     "res://assets/audio/sfx/ram_impact.mp3",
	"wall_bump":      "res://assets/audio/sfx/wall_bump.mp3",
	"pickup_ammo":    "res://assets/audio/sfx/pickup_ammo.ogg",
	"pickup_health":  "res://assets/audio/sfx/pickup_health.ogg",
	"countdown_beep": "res://assets/audio/sfx/countdown_beep.ogg",
	"match_go":       "res://assets/audio/sfx/match_go.ogg",
	"victory":        "res://assets/audio/sfx/victory.mp3",
	"defeat":         "res://assets/audio/sfx/defeat.mp3",
}

const UI_PATHS := {
	"click":   "res://assets/audio/ui/click.ogg",
	"hover":   "res://assets/audio/ui/hover.ogg",
	"confirm": "res://assets/audio/ui/confirm.ogg",
	"back":    "res://assets/audio/ui/back.ogg",
	"error":   "res://assets/audio/ui/error.ogg",
}

const MUSIC_PATHS := {
	"lobby": "res://assets/audio/music/lobby.mp3",
	"arena": "res://assets/audio/music/arena.mp3",
}

# Loops (engine, tracks) — same SFX paths but marked so we set stream.loop=true
const LOOP_NAMES := ["engine_idle", "tracks"]
const LOOP_PATHS := {
	"engine_idle": "res://assets/audio/sfx/engine_idle.mp3",
	"tracks":      "res://assets/audio/sfx/tracks.mp3",
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _cache: Dictionary       = {}    # name → AudioStream
var _music_player: AudioStreamPlayer  # global music player
var _current_music_name: String = ""
var _bus_indices: Dictionary = {}    # bus name → index (cached)


# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Cache bus indices once
	for bus_name in ["Master", "SFX", "Music", "UI"]:
		_bus_indices[bus_name] = AudioServer.get_bus_index(bus_name)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	_load_settings()


# ---------------------------------------------------------------------------
# Stream lookup (with loop flag applied once on first load)
# ---------------------------------------------------------------------------
func _get_stream(stream_name: String) -> AudioStream:
	if stream_name in _cache:
		return _cache[stream_name]

	var path: String = (
		SFX_PATHS.get(stream_name, "")
		if SFX_PATHS.has(stream_name)
		else UI_PATHS.get(stream_name, "")
		if UI_PATHS.has(stream_name)
		else MUSIC_PATHS.get(stream_name, "")
		if MUSIC_PATHS.has(stream_name)
		else LOOP_PATHS.get(stream_name, "")
	)
	if path == "":
		push_warning("Audio: unknown stream name '%s'" % stream_name)
		return null

	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("Audio: failed to load '%s'" % path)
		return null

	# Loop flag for streams that should repeat (music + engine/tracks loops)
	var should_loop := stream_name in MUSIC_PATHS or stream_name in LOOP_NAMES
	if should_loop:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true

	_cache[stream_name] = stream
	return stream


# ---------------------------------------------------------------------------
# Public API — one-shots
# ---------------------------------------------------------------------------

## Play a positional in-world SFX. `opts`:
##   - is_own:        bool, default false. Applies +2 dB self-boost.
##   - volume_db:     base volume, default 0.0
##   - pitch_jitter:  ± fraction, default 0.05 (5%)
##   - volume_jitter: ± dB, default 1.0
##   - max_distance:  attenuation distance in px, default 1800
##   - attenuation:   exponent, default 1.4
##   - parent:        Node to parent the player under, default current scene
func play_sfx_2d(stream_name: String, world_pos: Vector2, opts: Dictionary = {}) -> AudioStreamPlayer2D:
	var stream := _get_stream(stream_name)
	if stream == null:
		return null

	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.position = world_pos
	player.bus = "SFX"
	player.max_distance = float(opts.get("max_distance", DEFAULT_MAX_DIST_PX))
	player.attenuation  = float(opts.get("attenuation",  DEFAULT_ATTENUATION))

	var base_db: float = float(opts.get("volume_db", 0.0))
	if opts.get("is_own", false):
		base_db += SELF_BOOST_DB
	var v_jitter: float = float(opts.get("volume_jitter", VOLUME_JITTER))
	player.volume_db = base_db + randf_range(-v_jitter, v_jitter)

	var p_jitter: float = float(opts.get("pitch_jitter", PITCH_JITTER))
	player.pitch_scale = 1.0 + randf_range(-p_jitter, p_jitter)

	var parent: Node = opts.get("parent", get_tree().current_scene)
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player


## Play a non-positional SFX (countdown, victory, defeat, match-go).
func play_sfx(stream_name: String, opts: Dictionary = {}) -> AudioStreamPlayer:
	var stream := _get_stream(stream_name)
	if stream == null:
		return null

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = float(opts.get("volume_db", 0.0))
	var p_jitter: float = float(opts.get("pitch_jitter", PITCH_JITTER))
	player.pitch_scale = 1.0 + randf_range(-p_jitter, p_jitter)

	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player


## UI clicks / button feedback — routed via the UI bus so they're not affected
## by SFX volume slider.
func play_ui(stream_name: String) -> void:
	var stream := _get_stream(stream_name)
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "UI"
	player.pitch_scale = 1.0 + randf_range(-0.04, 0.04)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ---------------------------------------------------------------------------
# Loops attached to a moving node (engine + tracks on each tank)
# ---------------------------------------------------------------------------

## Returns an AudioStreamPlayer2D child of `parent` playing `stream_name` on loop.
## Caller is responsible for updating volume/pitch each frame and freeing it.
func attach_loop_to(parent: Node2D, stream_name: String, opts: Dictionary = {}) -> AudioStreamPlayer2D:
	var stream := _get_stream(stream_name)
	if stream == null:
		return null

	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = float(opts.get("volume_db", -20.0))
	player.pitch_scale = float(opts.get("pitch_scale", 1.0))
	player.max_distance = float(opts.get("max_distance", DEFAULT_MAX_DIST_PX))
	player.attenuation  = float(opts.get("attenuation",  DEFAULT_ATTENUATION))
	parent.add_child(player)
	player.play()
	return player


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------
func play_music(stream_name: String, fade_seconds: float = 1.0) -> void:
	if _current_music_name == stream_name and _music_player.playing:
		return
	var stream := _get_stream(stream_name)
	if stream == null:
		return

	if fade_seconds > 0.0 and _music_player.playing:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -40.0, fade_seconds)
		await tw.finished

	_music_player.stream = stream
	_music_player.volume_db = 0.0
	_music_player.play()
	_current_music_name = stream_name


func stop_music(fade_seconds: float = 1.0) -> void:
	if not _music_player.playing:
		return
	if fade_seconds > 0.0:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -40.0, fade_seconds)
		await tw.finished
	_music_player.stop()
	_current_music_name = ""


# ---------------------------------------------------------------------------
# Listener
# ---------------------------------------------------------------------------

## Attach an AudioListener2D to `node`. Pass null to detach.
## Existing listener (if any) is freed first.
func set_listener(node: Node2D) -> void:
	# Find and free any existing listener
	for n in get_tree().get_nodes_in_group("tta_audio_listener"):
		if is_instance_valid(n):
			n.queue_free()
	if node == null:
		return

	var listener := AudioListener2D.new()
	listener.add_to_group("tta_audio_listener")
	node.add_child(listener)
	listener.make_current()


# ---------------------------------------------------------------------------
# Bus volume — settings UI
# ---------------------------------------------------------------------------
func get_bus_volume_db(bus_name: String) -> float:
	var idx: int = _bus_indices.get(bus_name, -1)
	if idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(idx)


func set_bus_volume_db(bus_name: String, db: float) -> void:
	var idx: int = _bus_indices.get(bus_name, -1)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, clamp(db, -60.0, 6.0))
	_save_settings()


## Convert a 0..1 slider value to a perceptual dB curve.
## 0 → muted, 0.5 → -12 dB, 1.0 → 0 dB. Linear sliders sound bad; this is
## the standard "log" mapping audio engineers use.
static func linear_to_db_curve(linear: float) -> float:
	if linear <= 0.001:
		return -60.0
	return linear_to_db(linear)


static func db_curve_to_linear(db: float) -> float:
	if db <= -40.0:
		return 0.0
	return db_to_linear(db)


# ---------------------------------------------------------------------------
# Settings persistence
# ---------------------------------------------------------------------------
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return
	for bus_name in ["Master", "SFX", "Music", "UI"]:
		if cfg.has_section_key("audio", bus_name):
			var db: float = float(cfg.get_value("audio", bus_name))
			var idx: int = _bus_indices.get(bus_name, -1)
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, db)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in ["Master", "SFX", "Music", "UI"]:
		var idx: int = _bus_indices.get(bus_name, -1)
		if idx < 0:
			continue
		cfg.set_value("audio", bus_name, AudioServer.get_bus_volume_db(idx))
	cfg.save(_SETTINGS_PATH)
