# bullet.gd
# A bullet exists as a single replicated entity owned by the host.
#   - Host runs simulation: manual hit detection each frame against all tanks.
#   - Host position is replicated to clients via MultiplayerSynchronizer.
#   - When host queue_frees, MultiplayerSpawner removes it on all clients.
#
# Why manual hit detection instead of Area2D body_entered:
#   In multiplayer, client-owned tanks don't run move_and_slide() on the host
#   (only the owning peer does). Their physics body is not live on the host,
#   so Area2D signals never fire for them. Manual distance checks work against
#   replicated positions regardless of who owns the tank.

extends Area2D

@export var speed: float    = TankConfig.BULLET_SPEED
@export var lifetime: float = TankConfig.BULLET_LIFETIME
@export var damage: float   = TankConfig.BULLET_DAMAGE

# Replicated at spawn via SceneReplicationConfig (spawn = true)
var owner_id: int      = -1
var _velocity: Vector2 = Vector2.ZERO

var _age: float = 0.0

# Hit radius: bullet visual is ~4px, tank is 32x24px — use half-diagonal + bullet radius
const HIT_RADIUS := 26.0

# Trail
const TRAIL_INTERVAL : float = 0.018   # seconds between trail stamps
const TRAIL_FADE_TIME : float = 0.18   # seconds to fade out
const TRAIL_SIZE      : float = 3.0    # square stamp size in px
const TRAIL_COLOR     : Color = Color(1.0, 0.85, 0.2, 0.7)
var _trail_timer  : float = 0.0
var _trail_stamps : Array = []   # [{node, age}]

const EXPLOSION_SCENE  := preload("res://scripts/explosion.gd")
const TRAIL_FADER_SCENE := preload("res://scripts/trail_fader.gd")


func _ready() -> void:
	# Area2D collision is only used for wall detection (StaticBody2D — these ARE
	# live physics objects on every peer). Tank hit detection is manual (see below).
	# Gate on Net.is_active() rather than has_multiplayer_peer() so a closed-
	# but-not-nulled peer doesn't trip the is_multiplayer_authority() assert.
	var is_auth: bool = not Net.is_active() or is_multiplayer_authority()
	monitoring = is_auth
	if is_auth:
		body_entered.connect(_on_body_entered)


func launch(direction: Vector2) -> void:
	_velocity = direction.normalized() * speed


func _process(delta: float) -> void:
	# Trail runs on every peer
	_update_trail(delta)

	if Net.is_active() and not is_multiplayer_authority():
		return  # simulation is authority-only

	position += _velocity * delta
	_age += delta
	if _age >= lifetime:
		_explode()
		queue_free()
		return

	_check_tank_hits()


func _check_tank_hits() -> void:
	# Walk all tanks in the arena and test distance manually.
	# This works regardless of which peer owns the tank.
	var arena: Node = get_parent()
	for node in arena.get_children():
		if not node.has_method("take_damage"):
			continue
		if node.tank_id == owner_id:
			continue
		if node._dead:
			continue
		if global_position.distance_to(node.global_position) <= HIT_RADIUS:
			node.take_damage(damage)
			_explode()
			queue_free()
			return


func _update_trail(delta: float) -> void:
	# Fade existing stamps
	for i in range(_trail_stamps.size() - 1, -1, -1):
		var entry: Dictionary = _trail_stamps[i]
		if not is_instance_valid(entry.node):
			_trail_stamps.remove_at(i)
			continue
		var a: float = 1.0 - entry.age / TRAIL_FADE_TIME
		if a <= 0.0:
			entry.node.queue_free()
			_trail_stamps.remove_at(i)
		else:
			entry.node.modulate.a = a
			entry.age += delta

	# Stamp a new mark
	_trail_timer += delta
	if _trail_timer >= TRAIL_INTERVAL:
		_trail_timer = 0.0
		var stamp := ColorRect.new()
		stamp.size = Vector2(TRAIL_SIZE, TRAIL_SIZE)
		stamp.pivot_offset = Vector2(TRAIL_SIZE / 2.0, TRAIL_SIZE / 2.0)
		stamp.color = TRAIL_COLOR
		stamp.global_position = global_position - Vector2(TRAIL_SIZE / 2.0, TRAIL_SIZE / 2.0)
		get_parent().add_child(stamp)
		_trail_stamps.append({ "node": stamp, "age": 0.0 })


var _exploded: bool = false

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var explosion: Node2D = Node2D.new()
	explosion.set_script(EXPLOSION_SCENE)
	explosion.global_position = global_position
	get_parent().add_child.call_deferred(explosion)


func _exit_tree() -> void:
	# Catches the client-side removal driven by MultiplayerSpawner.
	# Must call _explode() synchronously: call_deferred on `self` here would
	# target a node that is about to be freed (the deferred queue runs after
	# the bullet has been removed/freed and silently drops the call), which is
	# why the explosion only used to appear on the host. _explode() itself
	# defers just the `add_child` call on the still-alive parent, so it's safe
	# to invoke from within _exit_tree.
	if not _exploded and get_parent() != null:
		_explode()

	# Hand off still-alive trail stamps to an independent fader node
	if _trail_stamps.is_empty() or get_parent() == null:
		return
	var fader: Node = Node.new()
	fader.set_script(TRAIL_FADER_SCENE)
	var parent := get_parent()
	# Must defer — parent may be busy during _exit_tree
	fader.set("stamps", _trail_stamps.duplicate())
	fader.set("fade_time", TRAIL_FADE_TIME)
	parent.add_child.call_deferred(fader)


func _on_body_entered(body: Node) -> void:
	# Only used for wall collisions — tanks are handled by _check_tank_hits
	if body is StaticBody2D:
		_explode()
		queue_free()
