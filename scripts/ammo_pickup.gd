# ammo_pickup.gd
# An ammo pickup. Spawned and owned by the host; replicated to clients via
# MultiplayerSpawner (position synced, so teleports are visible everywhere).
#
# Uses manual distance-based collection — body_entered is unreliable for
# client-owned tanks since they don't physics-simulate on the host.

extends Area2D

signal collected(pickup: Node)

const MARGIN         := 80.0
const ARENA_W        := 1280.0
const ARENA_H        := 720.0
const COLLECT_RADIUS := 52.0

# Collection arc animation
const COLLECT_DURATION := 0.35   # seconds
const ARC_HEIGHT       := 60.0   # peak height of the parabola in pixels

var _age: float            = 0.0
var _relocate_timer: float = 0.0
var _is_auth: bool         = false

# Set by arena.gd at spawn time — returns a navmesh-safe random position
var position_provider: Callable = func() -> Vector2: \
	return Vector2(randf_range(MARGIN, ARENA_W - MARGIN), randf_range(MARGIN, ARENA_H - MARGIN))

# Collect animation state
var _collecting: bool   = false
var _collect_t: float   = 0.0          # 0..1 progress
var _collect_start: Vector2            # world pos at moment of collection
var _collect_tank: Node = null         # reference to the collecting tank


func _ready() -> void:
	# Use Net.is_active() rather than has_multiplayer_peer() — see net.gd.
	_is_auth = not Net.is_active() or is_multiplayer_authority()
	monitoring = false   # collection handled manually below
	if _is_auth:
		_relocate_timer = TankConfig.AMMO_RELOCATE_TIME


func _process(delta: float) -> void:
	if not _is_auth:
		return

	if _collecting:
		_collect_t += delta / COLLECT_DURATION
		if _collect_t >= 1.0:
			queue_free()
			return

		# Linear interpolation between start and the tank's current position
		var t: float = _collect_t
		var target: Vector2 = _collect_tank.global_position if is_instance_valid(_collect_tank) \
			else _collect_start
		var base: Vector2 = _collect_start.lerp(target, t)

		# Parabolic arc: lift perpendicular to the direction of travel
		# Use world-up (negative Y = up in screen space) for the arc
		var arc: float = sin(t * PI) * ARC_HEIGHT
		global_position = base + Vector2(0.0, -arc)

		# Shrink as it arrives
		var s: float = 1.0 - t
		scale = Vector2(s, s)
		rotation = _age + t * TAU   # spin faster during flight
		return

	_age += delta
	rotation = _age * 1.5
	var s: float = 1.0 + 0.15 * sin(_age * 3.0)
	scale = Vector2(s, s)

	# Relocation timer
	_relocate_timer -= delta
	if _relocate_timer <= 0.0:
		_relocate_timer = TankConfig.AMMO_RELOCATE_TIME
		position = position_provider.call()

	# Manual collection check
	for body in get_parent().get_children():
		if not body.has_method("add_ammo"):
			continue
		if body._dead:
			continue
		if body.ammo_count >= TankConfig.MAX_AMMO:
			continue
		if global_position.distance_to(body.global_position) <= COLLECT_RADIUS:
			body.add_ammo(TankConfig.AMMO_PER_PICKUP)
			emit_signal("collected", self)
			_collecting = true
			_collect_t = 0.0
			_collect_start = global_position
			_collect_tank = body
			return
