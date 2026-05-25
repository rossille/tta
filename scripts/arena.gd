# arena.gd
# Spawns tanks, manages the match, handles win condition.
#
# Multiplayer startup sequence:
#   1. Every peer's _ready() sends _rpc_peer_ready() to the host.
#   2. Host counts ready peers. When all connected peers have checked in,
#      host calls _do_spawn_multiplayer() locally and sends _rpc_set_config()
#      to clients (call_remote only — host does NOT re-run via RPC).
#   3. Clients receive _rpc_set_config() and call _do_spawn_multiplayer().

extends Node2D

const TANK_SCENE          := preload("res://scenes/tank.tscn")
const AI_SCRIPT           := preload("res://scripts/tank_ai.gd")
const AMMO_PICKUP_SCENE   := preload("res://scenes/ammo_pickup.tscn")
const HEALTH_PICKUP_SCENE := preload("res://scenes/health_pickup.tscn")
const MapGenerator        := preload("res://scripts/map_generator.gd")

const TANK_COLORS := [
	Color(0.310, 0.765, 0.969),  # sky blue    — P1
	Color(1.000, 0.439, 0.263),  # deep orange — P2
	Color(0.400, 0.733, 0.416),  # medium green — AI
	Color(0.808, 0.576, 0.847),  # soft purple  — AI
]

const BARREL_COLORS := [
	Color(0.051, 0.278, 0.631),  # deep navy
	Color(0.749, 0.212, 0.047),  # dark burnt orange
	Color(0.106, 0.369, 0.125),  # dark forest green
	Color(0.290, 0.078, 0.549),  # deep violet
]

# Populated by the map generator each match
var _spawn_points:    Array = []
var _spawn_rotations: Array = []

# Node that holds all dynamically created inner walls
@onready var _walls_node:  Node2D = $Walls
@onready var _tracks_node: Node2D = $Tracks

var _tanks: Array = []
var _alive: int   = 0
var _ready_peers: Array = []
# Guards against _start_spawn() being entered more than once if a late
# (retried) _rpc_peer_ready arrives after we've already begun spawning.
var _spawn_started: bool = false
# Client side: flips true when the host acks our _rpc_peer_ready so the
# retry loop in _send_peer_ready_with_retry can stop.
var _peer_ready_acked: bool = false

# Ram damage cooldowns: "id_a:id_b" → seconds remaining
var _ram_cooldowns: Dictionary = {}

# Ammo pickup respawn timers: [seconds_remaining, ...]
var _pickup_respawn_timers: Array = []

# Health pickup: counts up to HEALTH_PICKUP_INTERVAL, then spawns one
var _health_spawn_timer: float = 0.0
var _health_pickup_active: bool = false

const PICKUP_MARGIN := 80.0   # keep pickups away from walls
const ARENA_W       := 1280.0
const ARENA_H       := 720.0

@onready var _hud: CanvasLayer         = $HUD
@onready var _nav_region: NavigationRegion2D = $NavRegion
@onready var _tank_spawner: MultiplayerSpawner = $TankSpawner


# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	Cursor.hide_cursor()
	Audio.play_music("arena", 1.5)
	# Wire the spawn function for tanks. The MultiplayerSpawner calls this
	# function on every peer (host first as the authority, then each guest
	# when it receives the replicated spawn message). Putting tank creation
	# under a spawner is what makes MovementSync/CombatSync actually
	# replicate between peers in Godot 4.6 production builds — manually
	# add_child'd nodes register their synchronizers without ever delivering
	# deltas, even with public_visibility=true and explicit
	# set_visibility_for(peer, true). See the debug log archived in this
	# repo's history for the smoking gun.
	_tank_spawner.spawn_function = _spawn_tank
	if Net.is_active():
		if Net.is_host():
			print("[ARENA] Host ready. player_info: ", Net.player_info)
			_register_peer_ready(1)
		else:
			print("[ARENA] Client ready, my_id=", Net.my_id(), " sending peer_ready to host")
			_send_peer_ready_with_retry()
	else:
		_spawn_solo()


# Client side. Repeatedly fires _rpc_peer_ready at the host until the host
# acks via _rpc_peer_ready_ack. Without retries, a single packet that
# arrives at the host before the host's /root/Main exists (e.g. while the
# host is still finalising change_scene_to_file in a production build with
# different timing than the dev machine) is silently dropped, and the
# whole startup hangs — observed on the Linux guest where the host stays
# stuck at "outer walls only".
func _send_peer_ready_with_retry() -> void:
	# Cap at ~10s so we don't loop forever if the host genuinely died.
	for attempt in range(50):
		if _peer_ready_acked:
			return
		_rpc_peer_ready.rpc_id(1)
		await get_tree().create_timer(0.2).timeout
	if not _peer_ready_acked:
		push_warning("[ARENA] Client never received peer_ready ack from host")


# Find the tank owned by this peer (the human player on this machine).
# Returns null if none found (all-AI match, or before spawn finishes).
func _find_local_player_tank() -> Node:
	for t in _tanks:
		if not is_instance_valid(t):
			continue
		if t.control_mode != t.ControlMode.PLAYER:
			continue
		if Net.is_active():
			if t.is_multiplayer_authority():
				return t
		else:
			if t.player_index == 0:
				return t
	return null


## Public accessor for the local player's tank, used by external systems
## (e.g. the EducationManager). Same semantics as _find_local_player_tank.
func get_local_player_tank() -> Node:
	return _find_local_player_tank()


func _attach_audio_listener() -> void:
	var local := _find_local_player_tank()
	if local != null:
		Audio.set_listener(local)


# ---------------------------------------------------------------------------
# Solo spawn
# ---------------------------------------------------------------------------
func _spawn_solo() -> void:
	_generate_map([])
	# Wait for the navmesh bake to complete, then one extra physics frame for
	# the NavigationServer to sync the result to the map (iteration_id goes
	# from 0 to 1 on that frame).
	await _nav_region.bake_finished
	await get_tree().physics_frame
	var ai_count: int = GameConfig.ai_list.size()
	var total: int = min(GameConfig.num_players + ai_count, 4)
	for i in range(total):
		var is_player: bool = i < GameConfig.num_players
		var tank := _create_tank(i, is_player, i)
		if not is_player:
			var ai_index: int = i - GameConfig.num_players
			var ai_diff: int = GameConfig.ai_list[ai_index].get("difficulty", 1)
			var ai := AI_SCRIPT.new()
			ai.difficulty = ai_diff
			tank.add_child(ai)
		add_child(tank)
		_tanks.append(tank)
	_alive = _tanks.size()
	_connect_death_signals()
	_spawn_all_pickups()
	_attach_audio_listener()
	_register_player_tank_with_education()
	Audio.play_sfx("match_go")


# ---------------------------------------------------------------------------
# Multiplayer: peer ready handshake
#
# Clients call _rpc_peer_ready on the host in a retry loop. Each receipt
# triggers a _rpc_peer_ready_ack back to the sender so the loop can stop.
# Re-receiving _rpc_peer_ready after spawn has already started is a no-op
# (idempotent), so a stray late retry can't restart spawning.
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _rpc_peer_ready() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	_register_peer_ready(sender_id)
	# Ack so the client's retry loop terminates.
	_rpc_peer_ready_ack.rpc_id(sender_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_peer_ready_ack() -> void:
	_peer_ready_acked = true


func _register_peer_ready(peer_id: int) -> void:
	if _spawn_started:
		# A late retry that arrived after we already started spawning. Safe
		# to ignore — the ack RPC sent by _rpc_peer_ready will still cause
		# the sender to stop retrying.
		return

	if peer_id not in _ready_peers:
		_ready_peers.append(peer_id)

	var expected := Net.player_info.keys()
	print("[ARENA] peer_ready from ", peer_id, " | ready=", _ready_peers, " | expected=", expected)

	var all_ready := true
	for pid in expected:
		if pid not in _ready_peers:
			all_ready = false
			break

	if all_ready:
		_spawn_started = true
		_start_spawn()


func _start_spawn() -> void:
	# Build slot assignments
	var peers := Net.player_info.keys()
	peers.sort()
	var slot := 0
	GameConfig.peer_slots.clear()
	for peer_id in peers:
		GameConfig.peer_slots[peer_id] = slot
		slot += 1

	var ai_count: int = min(GameConfig.ai_list.size(), 4 - peers.size())
	# Trim ai_list to fit within the 4-player cap
	var ai_list_trimmed: Array = GameConfig.ai_list.slice(0, ai_count)

	# Generate the map on the host; collect wall segments to send to clients
	var wall_segments: Array = _generate_map([])

	# Send config + wall data to clients
	_rpc_set_config.rpc(
		GameConfig.peer_slots,
		ai_list_trimmed,
		wall_segments,
		_spawn_points,
		_spawn_rotations
	)

	# Wait for the navmesh bake, then one extra physics frame for the
	# NavigationServer to sync the result before spawning.
	await _nav_region.bake_finished
	await get_tree().physics_frame
	# Host spawns directly
	_do_spawn_multiplayer(GameConfig.peer_slots, ai_list_trimmed)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_config(peer_slots: Dictionary, ai_list: Array,
		wall_segments: Array, spawn_pts: Array, spawn_rots: Array) -> void:
	# Runs on clients only
	print("[ARENA] Client received _rpc_set_config: slots=", peer_slots, " ai=", ai_list)
	GameConfig.peer_slots = peer_slots
	GameConfig.ai_list    = ai_list
	# Build the map from the host's data so all clients are identical
	_build_walls_from_segments(wall_segments)
	_spawn_points    = spawn_pts
	_spawn_rotations = spawn_rots
	# Bake the navmesh on this client and wait for it to finish before spawning
	# so that NavigationAgent2D nodes start with a valid navigation map.
	_bake_navmesh()
	await _nav_region.bake_finished
	await get_tree().physics_frame
	_do_spawn_multiplayer(peer_slots, ai_list)


# ---------------------------------------------------------------------------
# Map generation
# ---------------------------------------------------------------------------

# Generates inner walls, populates _spawn_points/_spawn_rotations,
# returns the raw segment array (Array of [x,y,w,h] int arrays) for RPC.
func _generate_map(_unused: Array) -> Array:
	var gen := MapGenerator.new()
	var result: Dictionary = gen.generate(_walls_node)
	_spawn_points    = result["spawn_points"]
	_spawn_rotations = result["spawn_rotations"]

	# Collect segment data for RPC — find CollisionShape2D by type, not name
	var segments: Array = []
	for child in _walls_node.get_children():
		if not child is StaticBody2D:
			continue
		var cshape: CollisionShape2D = null
		for sub in child.get_children():
			if sub is CollisionShape2D:
				cshape = sub
				break
		if cshape == null:
			continue
		var rect_shape: RectangleShape2D = cshape.shape
		segments.append([child.position.x, child.position.y,
		                 rect_shape.size.x, rect_shape.size.y])

	# Bake navmesh now that all walls are in the scene tree
	_bake_navmesh()
	return segments


func _bake_navmesh() -> void:
	var nav_poly := NavigationPolygon.new()

	# Walkable outline = full arena interior (between the border walls)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(16, 16),
		Vector2(1264, 16),
		Vector2(1264, 704),
		Vector2(16, 704),
	]))

	# Agent radius matches half the tank's narrow dimension
	nav_poly.agent_radius = 14.0

	# SOURCE_GEOMETRY_GROUPS_EXPLICIT scans all nodes in the named group
	# regardless of tree depth, covering both border walls (direct children of
	# Main) and generated inner walls (grandchildren under $Walls).
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_poly.source_geometry_group_name = "nav_wall"
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS

	_nav_region.navigation_polygon = nav_poly

	# Async at runtime — callers must await bake_finished then one physics_frame
	# before spawning tanks, so the NavigationServer has synced the result.
	_nav_region.bake_navigation_polygon()


func _build_walls_from_segments(segments: Array) -> void:
	# Clear any existing generated walls
	for child in _walls_node.get_children():
		child.queue_free()

	# Use the same builder the host uses during generation so clients see the
	# textured wall sprite rather than a placeholder ColorRect.
	for seg in segments:
		var pos := Vector2(seg[0], seg[1])
		var sz  := Vector2(seg[2], seg[3])
		MapGenerator.build_wall_at(_walls_node, pos, sz)


# ---------------------------------------------------------------------------
# Spawn tanks
#
# Tanks are routed through a MultiplayerSpawner (see $TankSpawner in
# main.tscn, plus _spawn_tank below). Without the spawner, Godot 4.6's
# MultiplayerSynchronizer never actually delivers position/HP deltas
# between peers — public_visibility=true and explicit set_visibility_for
# both turn out to be insufficient for manually-added nodes. The spawner
# performs the SceneMultiplayer registration that makes synchronizers
# tied to spawned nodes actually replicate; that's why bullets, ammo
# pickups, and health pickups (all under spawners) have always synced.
# ---------------------------------------------------------------------------
func _do_spawn_multiplayer(peer_slots: Dictionary, ai_list: Array) -> void:
	print("[ARENA] _do_spawn_multiplayer on peer ", Net.my_id(), " slots=", peer_slots)
	var expected_tank_count: int = peer_slots.size() + ai_list.size()

	if Net.is_host():
		# Host fires the spawner once per tank. _spawn_tank runs on every
		# peer (host immediately via call-local, guests once the spawn
		# message arrives over the wire), so each peer ends up with a
		# fully configured instance plus the spawner registration that
		# makes delta sync work.
		var peers := peer_slots.keys()
		peers.sort()
		for peer_id in peers:
			_tank_spawner.spawn({
				"slot": peer_slots[peer_id],
				"peer_id": peer_id,
				"is_ai": false,
				"ai_index": -1,
			})
		var ai_start: int = peer_slots.size()
		for i in range(ai_list.size()):
			_tank_spawner.spawn({
				"slot": ai_start + i,
				"peer_id": 1,
				"is_ai": true,
				"ai_index": i,
			})

	# All peers wait for every tank to materialize through the spawner.
	# 10s deadline guards against a stuck spawn so we don't hang forever.
	var deadline_ms: int = Time.get_ticks_msec() + 10000
	while _tanks.size() < expected_tank_count and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	if _tanks.size() < expected_tank_count:
		push_warning("[ARENA] tank spawn timeout: have %d / expected %d" % [
			_tanks.size(), expected_tank_count
		])

	_alive = _tanks.size()

	if Net.is_host():
		_connect_death_signals()
		_spawn_all_pickups()

	# Every peer attaches its own audio listener to its own player tank.
	_attach_audio_listener()
	Audio.play_sfx("match_go")


# Spawn function for $TankSpawner. The spawner calls this on every peer
# with the same data dictionary, then adds the returned node to its
# spawn_path (which is the arena root). Authority is set BEFORE return
# so the synchronizers see the correct value the moment they enter the
# tree.
func _spawn_tank(data: Dictionary) -> Node:
	var slot: int = int(data.get("slot", 0))
	var peer_id: int = int(data.get("peer_id", 1))
	var is_ai: bool = bool(data.get("is_ai", false))
	var ai_index: int = int(data.get("ai_index", -1))

	var my_id: int = multiplayer.get_unique_id() if Net.is_active() else 0
	var is_mine: bool = (not is_ai) and Net.is_active() and (peer_id == my_id)

	var tank: CharacterBody2D = _create_tank(slot, is_mine, peer_id)
	if is_ai:
		tank.name = "Tank_AI_%d" % ai_index
		tank.control_mode = tank.ControlMode.AI
	else:
		tank.name = "Tank_%d" % peer_id

	# Host-owned tanks (peer_id == 1, including AI) keep the scene default
	# authority of 1 across every node — see the long comment above the
	# function header for why we never touch a synchronizer that's already
	# correctly authoritative. Guest-owned tanks override the tank itself
	# plus MovementSync; CombatSync stays at the scene default (host=1).
	if peer_id != 1:
		tank.set_multiplayer_authority(peer_id, false)
		tank.get_node("MovementSync").set_multiplayer_authority(peer_id)

	# Only the host runs AI logic. Attach the AI controller before the
	# spawner adds the tank to the tree; the AI script becomes a child of
	# the (still out-of-tree) tank and joins the tree alongside it.
	if Net.is_host() and is_ai and ai_index >= 0 and ai_index < GameConfig.ai_list.size():
		var ai_entry: Dictionary = GameConfig.ai_list[ai_index]
		var ai := AI_SCRIPT.new()
		ai.difficulty = ai_entry.get("difficulty", 1)
		tank.add_child(ai)

	_tanks.append(tank)
	DebugLog.l("spawned %s | tank.auth=%d MovementSync.auth=%d CombatSync.auth=%d is_authority=%s" % [
		tank.name,
		tank.get_multiplayer_authority(),
		tank.get_node("MovementSync").get_multiplayer_authority(),
		tank.get_node("CombatSync").get_multiplayer_authority(),
		str(tank.is_multiplayer_authority()),
	])
	return tank


# ---------------------------------------------------------------------------
# Ammo pickup management (host only)
# ---------------------------------------------------------------------------
func _spawn_all_pickups() -> void:
	for i in range(TankConfig.AMMO_PICKUP_COUNT):
		_spawn_pickup(i)


func _random_safe_position() -> Vector2:
	# Retry until the candidate lands on the navmesh (i.e. not inside a wall).
	# The navmesh is baked with agent_radius=14, so any point it returns is
	# guaranteed to be reachable. We compare the snapped point to the candidate:
	# if they're within 4px the candidate is clear of walls.
	var map_rid := _nav_region.get_navigation_map()
	# If the navmesh hasn't completed its first sync yet, skip the check —
	# pickups spawned at match start are unlikely to land inside a wall anyway.
	if NavigationServer2D.map_get_iteration_id(map_rid) == 0:
		return Vector2(
			randf_range(PICKUP_MARGIN, ARENA_W - PICKUP_MARGIN),
			randf_range(PICKUP_MARGIN, ARENA_H - PICKUP_MARGIN)
		)
	for _i in range(50):
		var candidate := Vector2(
			randf_range(PICKUP_MARGIN, ARENA_W - PICKUP_MARGIN),
			randf_range(PICKUP_MARGIN, ARENA_H - PICKUP_MARGIN)
		)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, candidate)
		if candidate.distance_to(snapped) < 4.0:
			return candidate
	# Fallback: dead centre of the arena
	return Vector2(ARENA_W / 2.0, ARENA_H / 2.0)


func _spawn_pickup(slot: int) -> void:
	var pickup: Area2D = AMMO_PICKUP_SCENE.instantiate()
	pickup.position = _random_safe_position()
	pickup.position_provider = _random_safe_position
	pickup.collected.connect(_on_pickup_collected.bind(slot))
	add_child(pickup, true)


func _on_pickup_collected(pickup: Node, slot: int) -> void:
	while _pickup_respawn_timers.size() <= slot:
		_pickup_respawn_timers.append(0.0)
	_pickup_respawn_timers[slot] = TankConfig.AMMO_RESPAWN_TIME


func _spawn_health_pickup() -> void:
	var pickup: Area2D = HEALTH_PICKUP_SCENE.instantiate()
	pickup.position = _random_safe_position()
	pickup.collected.connect(_on_health_collected)
	_health_pickup_active = true
	add_child(pickup, true)


func _on_health_collected() -> void:
	_health_pickup_active = false
	_health_spawn_timer = 0.0


# ---------------------------------------------------------------------------
# Debug shortcuts
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_P:
			for tank in _tanks:
				if is_instance_valid(tank) and not tank._dead \
						and tank.control_mode == tank.ControlMode.AI:
					tank.take_damage(9999.0)


# ---------------------------------------------------------------------------
# Periodic debug snapshot of Tank_1 (the host's tank). One log line per
# second per peer, funnelled to the host's debug.log via the DebugLog
# autoload. Each peer reports the position/rotation it currently sees plus
# the synchronizer authority state so we can tell at a glance whether the
# host is broadcasting and whether the guests are receiving.
# ---------------------------------------------------------------------------
var _dbg_log_timer: float = 0.0

func _process(delta: float) -> void:
	if not Net.is_active():
		return
	_dbg_log_timer += delta
	if _dbg_log_timer < 1.0:
		return
	_dbg_log_timer = 0.0

	var host_tank: Node = get_node_or_null("Tank_1")
	if host_tank == null:
		DebugLog.l("Tank_1 not found in tree")
		return
	var mv: MultiplayerSynchronizer = host_tank.get_node_or_null("MovementSync")
	if mv == null:
		DebugLog.l("Tank_1.MovementSync missing")
		return
	# On the host, also report visibility for every connected peer so we can
	# tell whether MovementSync thinks the guest is a valid sync target.
	var extra := ""
	if Net.is_host():
		var peers := multiplayer.get_peers()
		var vis_parts: Array = []
		for pid in peers:
			vis_parts.append("%d:%s" % [pid, str(mv.get_visibility_for(pid))])
		extra = " | peers=%s public_vis=%s interval=%.3f" % [
			str(vis_parts),
			str(mv.public_visibility),
			mv.replication_interval,
		]
	DebugLog.l("Tank_1 pos=(%.0f,%.0f) rot=%.2f | tank.auth=%d MovementSync.auth=%d is_authority=%s%s" % [
		host_tank.position.x, host_tank.position.y, host_tank.rotation,
		host_tank.get_multiplayer_authority(),
		mv.get_multiplayer_authority(),
		str(host_tank.is_multiplayer_authority()),
		extra,
	])


# ---------------------------------------------------------------------------
# Host-side ram damage detection + pickup respawn ticks
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if Net.is_active() and not Net.is_host():
		return

	# Tick health pickup spawn interval (runs even when tanks array is empty)
	if not _health_pickup_active:
		_health_spawn_timer += delta
		if _health_spawn_timer >= TankConfig.HEALTH_PICKUP_INTERVAL:
			_health_spawn_timer = 0.0
			_spawn_health_pickup()

	if _tanks.is_empty():
		return

	# Tick ammo pickup respawn timers
	for slot in range(_pickup_respawn_timers.size()):
		if _pickup_respawn_timers[slot] > 0.0:
			_pickup_respawn_timers[slot] -= delta
			if _pickup_respawn_timers[slot] <= 0.0:
				_pickup_respawn_timers[slot] = 0.0
				_spawn_pickup(slot)

	# Purge freed or dead tanks from the array so we never touch a stale reference
	_tanks = _tanks.filter(func(t): return is_instance_valid(t) and not t._dead)

	# Tick down all pair cooldowns
	for key in _ram_cooldowns.keys():
		_ram_cooldowns[key] -= delta
		if _ram_cooldowns[key] <= 0.0:
			_ram_cooldowns.erase(key)

	# Check every unique pair of live tanks
	for i in range(_tanks.size()):
		var a: CharacterBody2D = _tanks[i]
		for j in range(i + 1, _tanks.size()):
			var b: CharacterBody2D = _tanks[j]

			# Skip if still on cooldown for this pair
			var pair_key: String = "%d:%d" % [a.tank_id, b.tank_id]
			if _ram_cooldowns.has(pair_key):
				continue

			# Tank body is 32x24 — 36px threshold covers actual contact
			var dist: float = a.global_position.distance_to(b.global_position)
			if dist > 47.0:
				continue

			# Relative approach speed along the axis between the two tanks
			var axis: Vector2 = (b.global_position - a.global_position).normalized()
			var rel_speed: float = (a.velocity - b.velocity).dot(axis)
			# rel_speed > 0 means A is closing on B
			if rel_speed < TankConfig.RAM_MIN_SPEED:
				continue

			var dmg: float = rel_speed * TankConfig.RAM_DAMAGE_FACTOR
			a.take_damage(dmg)
			b.take_damage(dmg)
			_ram_cooldowns[pair_key] = TankConfig.RAM_COOLDOWN


# ---------------------------------------------------------------------------
# Tank factory
# ---------------------------------------------------------------------------
func _create_tank(slot: int, is_player: bool, _peer_id: int) -> CharacterBody2D:
	var tank: CharacterBody2D = TANK_SCENE.instantiate()
	var idx: int = slot % _spawn_points.size()
	tank.position = _spawn_points[idx]
	tank.rotation = _spawn_rotations[idx]
	tank.tank_id      = slot
	tank.control_mode = tank.ControlMode.PLAYER if is_player else tank.ControlMode.AI

	var body: Sprite2D   = tank.get_node("Body")
	var barrel: Sprite2D = tank.get_node("Barrel")
	body.modulate   = TANK_COLORS[slot   % TANK_COLORS.size()]
	barrel.modulate = BARREL_COLORS[slot % BARREL_COLORS.size()]
	tank.tracks_node = _tracks_node

	if is_player:
		_add_player_indicator(tank)

	# Solo AI difficulty is now handled in _spawn_solo directly (per-AI entry)
	# Nothing to do here for the solo AI case.

	return tank


func _add_player_indicator(tank: CharacterBody2D) -> void:
	var indicator := Node2D.new()

	# Build a dotted circle using short Line2D arcs
	const RADIUS    := 28.0
	const SEGMENTS  := 8      # number of dots around the circle
	const ARC_FRAC  := 0.55   # fraction of each segment that is solid (rest is gap)
	const DOT_W     := 2.0
	const COLOR     := Color(1.0, 1.0, 1.0, 0.75)

	for i in range(SEGMENTS):
		var angle_start: float = (TAU / SEGMENTS) * i
		var angle_end: float   = angle_start + (TAU / SEGMENTS) * ARC_FRAC
		var steps: int = 4
		var arc := Line2D.new()
		arc.width = DOT_W
		arc.default_color = COLOR
		arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arc.end_cap_mode   = Line2D.LINE_CAP_ROUND
		for s in range(steps + 1):
			var a: float = lerp(angle_start, angle_end, float(s) / steps)
			arc.add_point(Vector2(cos(a), sin(a)) * RADIUS)
		indicator.add_child(arc)

	# Attach a tiny inline script that rotates the indicator each frame
	var rot_script := GDScript.new()
	rot_script.source_code = """
extends Node2D
func _process(delta):
	rotation += 0.6 * delta
"""
	rot_script.reload()
	indicator.set_script(rot_script)

	tank.add_child(indicator)


func _connect_death_signals() -> void:
	for t in _tanks:
		if not t.died.is_connected(_on_tank_died):
			t.died.connect(_on_tank_died)


# ---------------------------------------------------------------------------
# Death + win condition
# ---------------------------------------------------------------------------
func _on_tank_died(tank: Node) -> void:
	_alive -= 1
	_check_win()


func _check_win() -> void:
	if _alive > 1:
		return
	await get_tree().create_timer(3.0).timeout

	# If a revival quiz is currently open, wait for it to resolve before
	# deciding whether the match is over. The player may still answer
	# correctly and come back to life during the 3-second window.
	var mgr: Node = get_node_or_null("EducationManager")
	if mgr != null and mgr.get("_state") == mgr.State.REVIVAL_QUIZ:
		await mgr.revival_resolved

	# Re-count living tanks: a revival may have happened.
	var living: Array = []
	for t in _tanks:
		if is_instance_valid(t) and not t._dead:
			living.append(t)
	if living.size() > 1:
		# More than one tank alive again — match continues.
		_alive = living.size()
		return

	var winner_name := "Nobody"
	var winner_tank: Node = null
	for t in _tanks:
		if is_instance_valid(t) and not t._dead:
			winner_tank = t
			var idx: int = _tanks.find(t)
			if Net.is_active():
				for peer_id in GameConfig.peer_slots:
					if GameConfig.peer_slots[peer_id] == idx:
						winner_name = Net.player_info.get(peer_id, {}).get("name", "Player")
						break
				if winner_name == "Nobody":
					winner_name = "AI %d" % (idx - GameConfig.peer_slots.size() + 1)
			else:
				if idx < GameConfig.num_players:
					winner_name = "Player %d" % (idx + 1)
				else:
					winner_name = "AI %d" % (idx - GameConfig.num_players + 1)
				
			break

	# Pause the winner tank until the player decides what to do
	if is_instance_valid(winner_tank):
		winner_tank.set_physics_process(false)

	if not _hud.continued.is_connected(_on_continued):
		_hud.continued.connect(_on_continued.bind(winner_tank))

	_stop_education()

	if Net.is_active():
		_rpc_show_winner.rpc(winner_name)
	else:
		_hud.show_winner(winner_name)
		_play_outcome_sting(winner_name)


func _on_continued(winner_tank: Node) -> void:
	if is_instance_valid(winner_tank):
		winner_tank.set_physics_process(true)
		winner_tank.set_process(true)


@rpc("authority", "call_local", "reliable")
func _rpc_show_winner(winner_name: String) -> void:
	_hud.show_winner(winner_name)
	_play_outcome_sting(winner_name)


# Stop the educational module when the match ends so no overlay can pop up
# over the win/loss screen or during the post-game tank "walk-around".
func _stop_education() -> void:
	var mgr: Node = get_node_or_null("EducationManager")
	if mgr != null and mgr.has_method("stop"):
		mgr.stop()


func _register_player_tank_with_education() -> void:
	var mgr: Node = get_node_or_null("EducationManager")
	if mgr == null or not mgr.has_method("register_player_tank"):
		return
	var tank: Node = _find_local_player_tank()
	if tank != null:
		mgr.register_player_tank(tank)


# Plays victory or defeat based on whether the local player won.
func _play_outcome_sting(winner_name: String) -> void:
	var won := _local_player_won(winner_name)
	# Music ducks under the sting
	Audio.stop_music(0.4)
	if won:
		Audio.play_sfx("victory")
	else:
		Audio.play_sfx("defeat")


func _local_player_won(winner_name: String) -> bool:
	if Net.is_active():
		var my_name: String = Net.player_info.get(Net.my_id(), {}).get("name", "")
		return my_name != "" and winner_name == my_name
	# Solo: the human player is always Player 1
	return winner_name == "Player 1"
