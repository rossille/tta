# tank.gd
# Drives a single tank.
#
# Multiplayer authority model:
#   Movement  — simulated on owning peer; position/rotation/velocity replicated.
#   Firing    — owning peer checks ammo > 0, sends request to host.
#               Host deducts ammo, spawns bullet (replicated via MultiplayerSpawner).
#   Ammo      — ammo_count lives on host (CombatSync authority=1), replicated to all.
#   Damage    — take_damage() on host; current_hp replicated.
#   Ram       — host-side proximity detection in arena.gd.

extends CharacterBody2D

enum ControlMode { PLAYER, AI }

@export var control_mode: ControlMode = ControlMode.PLAYER
@export var player_index: int = 0

var tank_id: int = 0

# ---------------------------------------------------------------------------
# Movement parameters
# ---------------------------------------------------------------------------
@export var max_forward_speed: float      = TankConfig.MAX_FORWARD_SPEED
@export var max_reverse_speed: float      = TankConfig.MAX_REVERSE_SPEED
@export var acceleration: float           = TankConfig.ACCELERATION
@export var reverse_acceleration: float   = TankConfig.REVERSE_ACCELERATION
@export var friction: float               = TankConfig.FRICTION
@export var turn_rate_rad_per_sec: float  = TankConfig.TURN_RATE_RAD_PER_SEC
@export var turn_rate_scales_with_speed: bool = TankConfig.TURN_RATE_SCALES_WITH_SPEED

# ---------------------------------------------------------------------------
# Firing / health parameters
# ---------------------------------------------------------------------------
@export var fire_cooldown: float      = TankConfig.FIRE_COOLDOWN
@export var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
@export var max_hp: float             = TankConfig.MAX_HP

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal died(tank: Node)

# ---------------------------------------------------------------------------
# State — combat vars replicated via CombatSync (authority = host)
# ---------------------------------------------------------------------------
var _speed: float         = 0.0
var _fire_timer: float    = 0.0
var current_hp: float     = 100.0
var _dead: bool           = false
var ammo_count: int       = TankConfig.START_AMMO

var _last_drawn_hp: float   = -1.0
var _last_drawn_ammo: int   = -1
# True once this peer has applied the destroyed-tank visuals. Drives a
# once-only branch in _process so every peer reacts to the replicated _dead
# flag exactly once (host sets it locally; clients receive it via CombatSync).
var _death_applied: bool    = false

# AI inputs — written each frame by tank_ai.gd
var ai_throttle: float = 0.0
var ai_turn: float     = 0.0
var ai_fire: bool      = false

# ---------------------------------------------------------------------------
# Track marks
# ---------------------------------------------------------------------------
# Set by arena.gd at spawn time
var tracks_node: Node2D = null

const MUZZLE_FLASH_SCENE    := preload("res://scripts/muzzle_flash.gd")
const WRECK_FIRE_SCENE      := preload("res://scripts/wreck_fire.gd")
const DESTROYED_TEXTURE     := preload("res://assets/tank_destroyed.png")

const TRACK_STAMP_DIST:  float = 6.0    # stamp every N pixels travelled
const TRACK_FADE_TIME:   float = 1.0    # seconds until a stamp is fully transparent
const TRACK_MAX_STAMPS:  int   = 600    # hard cap to avoid unbounded growth
const TRACK_W:           float = 4.0    # width of each tread mark
const TRACK_H:           float = 10.0   # length of each tread mark
const TRACK_TREAD_OFFSET:float = 10.0   # lateral offset from tank centre (left/right)
const TRACK_COLOR:       Color = Color(0.0, 0.0, 0.0, 0.18)

var _track_dist_accum: float = 0.0
var _track_stamps: Array = []   # Array of ColorRect nodes

# ---------------------------------------------------------------------------
# UI nodes
# ---------------------------------------------------------------------------
@onready var _body_sprite:   Sprite2D  = $Body
@onready var _barrel_sprite: Sprite2D  = $Barrel
@onready var _hp_bar_node:  Node2D    = $HealthBar
@onready var _hp_bar_drain: ColorRect = $HealthBar/Drain
@onready var _hp_bar_fill:  ColorRect = $HealthBar/Fill
@onready var _ammo_pips:    Node2D    = $HealthBar/AmmoPips

const HP_BAR_WIDTH:  float   = 40.0
const HP_BAR_OFFSET: Vector2 = Vector2(-20.0, -40.0)  # shifted up to make room for pips
const DRAIN_SPEED:   float   = 60.0

# Pip appearance
const PIP_W:     float  = 3.0
const PIP_H:     float  = 5.0
const PIP_GAP:   float  = 1.0
const PIP_ON:    Color  = Color(1.0, 0.9, 0.1, 1.0)   # bright yellow
const PIP_OFF:   Color  = Color(0.25, 0.25, 0.25, 1.0) # dark gray

var _pip_rects: Array = []

# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------
var _engine_player: AudioStreamPlayer2D
var _tracks_player: AudioStreamPlayer2D
var _audio_prev_pos: Vector2 = Vector2.ZERO
var _audio_smooth_speed: float = 0.0   # estimated speed for remote-peer audio


# ---------------------------------------------------------------------------
# Ready / process
# ---------------------------------------------------------------------------
func _ready() -> void:
	current_hp = max_hp
	ammo_count = TankConfig.START_AMMO
	_build_pip_ui()
	_update_hp_bar()
	_update_ammo_pips()
	_audio_prev_pos = global_position
	_setup_audio_loops()


func _setup_audio_loops() -> void:
	# Engine and tracks are positional loops attached to the tank, so every
	# peer hears every tank (attenuated by listener distance).
	_engine_player = Audio.attach_loop_to(self, "engine_idle", {
		"volume_db":   -22.0,
		"pitch_scale": 0.9,
		"max_distance": 1200.0,
		"attenuation": 1.6,
	})
	_tracks_player = Audio.attach_loop_to(self, "tracks", {
		"volume_db":   -60.0,   # silent until we actually move
		"max_distance": 900.0,
		"attenuation": 1.8,
	})


func _build_pip_ui() -> void:
	for i in range(TankConfig.MAX_AMMO):
		var pip := ColorRect.new()
		pip.size = Vector2(PIP_W, PIP_H)
		pip.position = Vector2(i * (PIP_W + PIP_GAP), 0.0)
		pip.color = PIP_OFF
		_ammo_pips.add_child(pip)
		_pip_rects.append(pip)



func _process(delta: float) -> void:
	_hp_bar_node.global_position = global_position + HP_BAR_OFFSET

	if current_hp != _last_drawn_hp:
		if _last_drawn_hp > 0.0 and current_hp < _last_drawn_hp:
			_flash_hit()
		_update_hp_bar()

	if ammo_count != _last_drawn_ammo:
		_update_ammo_pips()

	if _hp_bar_drain.size.x > _hp_bar_fill.size.x:
		_hp_bar_drain.size.x = max(
			_hp_bar_fill.size.x,
			_hp_bar_drain.size.x - DRAIN_SPEED * delta
		)

	_update_tracks(delta)
	_update_audio_loops(delta)

	# _dead is driven by the host and replicated via CombatSync; every peer
	# applies the destroyed-tank visuals the first frame it observes the flag.
	if _dead and not _death_applied:
		_apply_death_visuals()


func _update_audio_loops(delta: float) -> void:
	# Estimate speed from observed position deltas. Works on every peer
	# regardless of authority (the owning peer's _speed isn't replicated).
	var d: Vector2 = global_position - _audio_prev_pos
	_audio_prev_pos = global_position
	# Use the typed math variants (maxf/clampf/lerpf) so the strict-typing
	# warnings don't fire — the untyped overloads return Variant.
	var instant_speed: float = d.length() / maxf(delta, 0.0001)
	_audio_smooth_speed = lerpf(_audio_smooth_speed, instant_speed, clampf(delta * 6.0, 0.0, 1.0))

	if _dead:
		if _engine_player and _engine_player.playing:
			_engine_player.stop()
		if _tracks_player and _tracks_player.playing:
			_tracks_player.stop()
		return

	# Engine: quiet idle at -22 dB, ramps to -10 dB at full throttle.
	# Pitch sweeps from 0.9 to 1.35 with speed for the classic rev feel.
	var speed_norm: float = clampf(_audio_smooth_speed / max_forward_speed, 0.0, 1.0)
	if _engine_player:
		_engine_player.volume_db  = lerpf(-22.0, -10.0, speed_norm)
		_engine_player.pitch_scale = lerpf(0.9, 1.35, speed_norm)

	# Tracks: only audible when actually rolling.
	if _tracks_player:
		var target_db: float = -10.0 if _audio_smooth_speed > 18.0 else -60.0
		_tracks_player.volume_db = move_toward(_tracks_player.volume_db, target_db, 60.0 * delta)


# ---------------------------------------------------------------------------
# Physics — owning peer only
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Net.is_active() rejects closed-but-not-nulled peers — see net.gd.
	# Only call is_multiplayer_authority() when the peer can actually answer.
	if Net.is_active() and not is_multiplayer_authority():
		return

	_handle_rotation(delta)
	_handle_throttle(delta)
	_apply_velocity()
	move_and_slide()
	_sync_speed_after_slide()
	_handle_firing(delta)


func _handle_rotation(delta: float) -> void:
	var turn_input: float = ai_turn if control_mode == ControlMode.AI \
		else Input.get_axis("tank_turn_left", "tank_turn_right")

	if turn_input == 0.0:
		return

	var rate := turn_rate_rad_per_sec
	if turn_rate_scales_with_speed:
		rate *= abs(_speed) / max_forward_speed

	rotation += turn_input * rate * delta


func _handle_throttle(delta: float) -> void:
	var throttle: float = ai_throttle if control_mode == ControlMode.AI \
		else Input.get_axis("tank_forward", "tank_reverse")

	if throttle < 0.0:
		_speed = move_toward(_speed, max_forward_speed, acceleration * delta)
	elif throttle > 0.0:
		if _speed > 0.0:
			_speed = move_toward(_speed, 0.0, friction * delta)
		else:
			_speed = move_toward(_speed, -max_reverse_speed, reverse_acceleration * delta)
	else:
		_speed = move_toward(_speed, 0.0, friction * delta)


func _apply_velocity() -> void:
	velocity = transform.x * _speed


func _sync_speed_after_slide() -> void:
	# After move_and_slide() the engine may have removed the wall-normal component
	# of velocity. Re-project back onto the tank's forward axis so _speed stays
	# consistent — head-on hits kill speed, glancing hits reduce it proportionally.
	_speed = velocity.dot(transform.x)


# ---------------------------------------------------------------------------
# Firing — owning peer detects input and ammo, host deducts + spawns bullet
# ---------------------------------------------------------------------------
func _handle_firing(delta: float) -> void:
	if _fire_timer > 0.0:
		_fire_timer -= delta

	var wants_fire: bool = ai_fire if control_mode == ControlMode.AI \
		else Input.is_action_just_pressed("tank_fire")

	# Check ammo on the owning peer using replicated ammo_count
	if not wants_fire or _fire_timer > 0.0 or ammo_count <= 0:
		return

	_fire_timer = fire_cooldown
	_spawn_muzzle_flash()
	Audio.play_sfx_2d("tank_fire", global_position, { "is_own": _is_local_player() })

	if Net.is_active() and not Net.is_host():
		_rpc_request_fire.rpc_id(1, global_position, transform.x, tank_id)
	else:
		_do_fire(global_position, transform.x, tank_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_fire(pos: Vector2, dir: Vector2, tid: int) -> void:
	# Runs on host — validate ammo then spawn
	_do_fire(pos, dir, tid)


func _do_fire(pos: Vector2, dir: Vector2, tid: int) -> void:
	# Only deduct ammo if we have some (double-check on host side)
	if ammo_count <= 0:
		return
	ammo_count -= 1
	_do_spawn_bullet(pos, dir, tid)


func _do_spawn_bullet(pos: Vector2, dir: Vector2, tid: int) -> void:
	var bullet: Area2D = bullet_scene.instantiate()
	bullet.position = pos + dir * 26.0
	bullet.rotation = dir.angle()
	bullet.owner_id = tid
	bullet.launch(dir)
	get_parent().add_child(bullet, true)


# ---------------------------------------------------------------------------
# Ammo — granted by host when tank overlaps a pickup
# ---------------------------------------------------------------------------
func add_ammo(amount: int) -> void:
	ammo_count = min(ammo_count + amount, TankConfig.MAX_AMMO)


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------
func take_damage(amount: float) -> void:
	if _dead:
		return
	current_hp = max(0.0, current_hp - amount)
	_update_hp_bar()
	# Bullet-hit ping plays on the combat-authority peer; remote peers hear it
	# via the death/visual replication path below for the explosion sound only.
	Audio.play_sfx_2d("bullet_hit", global_position, {
		"is_own": _is_local_player(),
	})
	if current_hp <= 0.0:
		# Combat authority (host in multiplayer, local peer in solo) flips the
		# replicated _dead flag and notifies the arena. The destroyed-tank
		# visuals fire on every peer from _process when it observes _dead.
		_dead = true
		emit_signal("died", self)


func _update_hp_bar() -> void:
	if not is_inside_tree():
		return
	_last_drawn_hp = current_hp
	var ratio: float  = current_hp / max_hp
	var fill_w: float = ratio * HP_BAR_WIDTH
	_hp_bar_fill.size.x = fill_w
	if _hp_bar_drain.size.x < _hp_bar_fill.size.x:
		_hp_bar_drain.size.x = fill_w
	if ratio > 0.5:
		_hp_bar_fill.color = Color(1.0 - (ratio - 0.5) * 2.0, 1.0, 0.0)
	else:
		_hp_bar_fill.color = Color(1.0, ratio * 2.0, 0.0)


func _update_ammo_pips() -> void:
	if not is_inside_tree():
		return
	_last_drawn_ammo = ammo_count
	for i in range(_pip_rects.size()):
		_pip_rects[i].color = PIP_ON if i < ammo_count else PIP_OFF


func _update_tracks(delta: float) -> void:
	if tracks_node == null or _dead:
		return

	# Fade all existing stamps
	for i in range(_track_stamps.size() - 1, -1, -1):
		var stamp: ColorRect = _track_stamps[i]
		if not is_instance_valid(stamp):
			_track_stamps.remove_at(i)
			continue
		var a: float = stamp.modulate.a - delta / TRACK_FADE_TIME
		if a <= 0.0:
			stamp.queue_free()
			_track_stamps.remove_at(i)
		else:
			stamp.modulate.a = a

	# Stamp when the tank has moved enough
	_track_dist_accum += abs(_speed) * delta
	if _track_dist_accum >= TRACK_STAMP_DIST:
		_track_dist_accum = 0.0
		_stamp_tracks()


func _stamp_tracks() -> void:
	if tracks_node == null:
		return

	# Enforce cap — remove oldest pair first
	while _track_stamps.size() >= TRACK_MAX_STAMPS:
		var oldest: ColorRect = _track_stamps.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	# Left and right tread positions in world space
	var right_dir: Vector2 = transform.y   # tank's local Y = lateral axis
	var offsets := [right_dir * -TRACK_TREAD_OFFSET, right_dir * TRACK_TREAD_OFFSET]

	for offset in offsets:
		var stamp := ColorRect.new()
		stamp.size = Vector2(TRACK_W, TRACK_H)
		stamp.pivot_offset = stamp.size / 2.0
		stamp.color = TRACK_COLOR
		stamp.modulate.a = 1.0
		# Position and rotate in world space
		stamp.global_position = global_position + offset - stamp.pivot_offset
		stamp.rotation = rotation
		tracks_node.add_child(stamp)
		_track_stamps.append(stamp)


func _flash_hit() -> void:
	var tween := create_tween()
	tween.tween_property(_body_sprite, "modulate", Color(1.0, 0.2, 0.2, 1.0), 0.04)
	tween.tween_property(_body_sprite, "modulate", Color.WHITE, 0.12)


func _spawn_muzzle_flash() -> void:
	var flash: Node2D = Node2D.new()
	flash.set_script(MUZZLE_FLASH_SCENE)
	# Barrel tip: 40px forward from tank centre, rotated with the tank
	flash.global_position = global_position + transform.x * 40.0
	flash.global_rotation = global_rotation
	get_parent().add_child(flash)


func _apply_death_visuals() -> void:
	# Runs once on every peer the first frame `_dead` is observed (set locally
	# by the combat-authority peer in take_damage and replicated to the rest
	# via CombatSync). Pure presentation — no game-state mutation here.
	_death_applied = true
	set_physics_process(false)
	# Note: we don't disable _process anymore — _update_audio_loops needs to
	# tick to silence the engine/tracks loops, which it does when `_dead`.
	_hp_bar_node.visible = false
	_barrel_sprite.visible = false
	_body_sprite.texture = DESTROYED_TEXTURE
	_body_sprite.scale = Vector2(0.041 / 0.6, 0.031 / 0.6)
	_body_sprite.modulate = Color.WHITE   # clear any player colour tint
	_spawn_wreck_fire()
	# Big death boom — positional so spectators hear where it happened.
	Audio.play_sfx_2d("explosion", global_position, {
		"is_own": _is_local_player(),
		"volume_db": 2.0,
		"max_distance": 2400.0,
	})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _is_local_player() -> bool:
	# Solo mode: the local player is whichever PLAYER-controlled tank exists
	# at the player_index. With a single human player, that's player_index == 0.
	if not Net.is_active():
		return control_mode == ControlMode.PLAYER and player_index == 0
	# Multiplayer: the local player is whoever owns the movement authority
	# on this tank. AI tanks are host-owned but are not "the local player"
	# for audio-boost purposes unless this peer is the host AND solo-host.
	return control_mode == ControlMode.PLAYER and is_multiplayer_authority()


func _spawn_wreck_fire() -> void:
	var fire: Node2D = Node2D.new()
	fire.set_script(WRECK_FIRE_SCENE)
	add_child(fire)   # parented to tank so it stays on the wreck
