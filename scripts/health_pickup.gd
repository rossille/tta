# health_pickup.gd
# Restores a tank to full HP on collection. Stays until consumed.
# Visual: a sprite that pulses gently.
#
# Uses manual distance-based collection (same reason as bullets — client-owned
# tanks don't physics-simulate on the host, so body_entered never fires for them).

extends Area2D

signal collected

const COLLECT_RADIUS := 52.0

# Collection arc animation
const COLLECT_DURATION := 0.35   # seconds
const ARC_HEIGHT       := 60.0   # peak height of the parabola in pixels

var _age: float    = 0.0
var _is_auth: bool = false

# Collect animation state
var _collecting: bool   = false
var _collect_t: float   = 0.0
var _collect_start: Vector2
var _collect_tank: Node = null


func _ready() -> void:
	# Use Net.is_active() rather than has_multiplayer_peer() — see net.gd.
	_is_auth = not Net.is_active() or is_multiplayer_authority()
	monitoring = false


func _process(delta: float) -> void:
	if not _is_auth:
		return

	if _collecting:
		_collect_t += delta / COLLECT_DURATION
		if _collect_t >= 1.0:
			queue_free()
			return

		var t: float = _collect_t
		var target: Vector2 = _collect_tank.global_position if is_instance_valid(_collect_tank) \
			else _collect_start
		var base: Vector2 = _collect_start.lerp(target, t)

		var arc: float = sin(t * PI) * ARC_HEIGHT
		global_position = base + Vector2(0.0, -arc)

		var s: float = 1.0 - t
		scale = Vector2(s, s)
		return

	_age += delta
	var s: float = 1.0 + 0.12 * sin(_age * 4.0)
	scale = Vector2(s, s)

	# Manual collection check — works for both host-owned and client-owned tanks
	for body in get_parent().get_children():
		if not body.has_method("take_damage"):
			continue
		if body._dead:
			continue

		if global_position.distance_to(body.global_position) <= COLLECT_RADIUS:
			body.current_hp = body.max_hp
			body._update_hp_bar()
			emit_signal("collected")
			_collecting = true
			_collect_t = 0.0
			_collect_start = global_position
			_collect_tank = body
			return
