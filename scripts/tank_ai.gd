# tank_ai.gd
# Attached as a child Node of a tank. Each physics frame writes
# ai_throttle, ai_turn, and ai_fire onto the parent tank.
#
# State machine:
#   ROAM       — drive toward a random waypoint
#   HUNT_AMMO  — ammo is low; drive toward nearest ammo pickup
#   AIM        — rotate toward nearest enemy and close in
#   FIRE       — shoot while aligned, keep moving
#
# Difficulty affects:
#   REACT_TIME        — seconds before noticing an enemy
#   AIM_TOLERANCE     — angular error allowed before firing
#   MOVE_SPEED_SCALE  — throttle fraction while aiming/firing
#   WAYPOINT_TIMEOUT  — seconds before giving up on a stuck waypoint
#   TURN_RATE_SCALE   — fraction of max turn rate used
#   LOSE_INTEREST     — probability/s of forgetting the target
#   FIRE_SUPPRESS     — probability/s of hesitating before firing
#   AMMO_HUNT_THRESHOLD — ammo count at or below which the AI hunts for ammo

extends Node

enum State { ROAM, HUNT_AMMO, HUNT_HEALTH, AIM, FIRE }

# --- Difficulty tables (index 0=Easy, 1=Medium, 2=Hard) ---
const REACT_TIME: Array         = [3.5,  1.5,  0.4]
const AIM_TOLERANCE: Array      = [0.6,  0.35, 0.15]
const MOVE_SPEED_SCALE: Array   = [0.25, 0.45, 0.70]
const WAYPOINT_TIMEOUT: Array   = [4.0,  2.5,  1.5]
const TURN_RATE_SCALE: Array    = [0.35, 0.65, 1.00]
const LOSE_INTEREST_RATE: Array = [0.6,  0.2,  0.0]
const FIRE_SUPPRESS_RATE: Array = [0.7,  0.3,  0.0]

# Ammo count at or below which the AI drops everything to hunt a pickup.
# Easy AI panics early (≤4), Hard AI stays calm until nearly empty (≤1).
const AMMO_HUNT_THRESHOLD: Array = [4, 2, 1]

@export var difficulty: int = 1

var _nav_agent: NavigationAgent2D = null
var _state: State = State.ROAM
var _prev_combat_state: State = State.ROAM
var _waypoint: Vector2 = Vector2.ZERO
var _react_timer: float = 0.0
var _waypoint_timer: float = 0.0
var _lose_interest_timer: float = 0.0
var _tank: CharacterBody2D = null

var _nav_ready: bool = false   # true once the agent is in the tree and has a valid map

# Unstuck detection
var _last_position: Vector2    = Vector2.ZERO
var _stuck_timer: float        = 0.0
const STUCK_CHECK_INTERVAL     := 1.0    # check every N seconds
const STUCK_MOVE_THRESHOLD     := 20.0   # must move at least this many px to not be stuck
const STUCK_ESCAPE_DURATION    := 0.8    # seconds to reverse when stuck detected
var _escape_timer: float       = 0.0
var _escape_dir: Vector2       = Vector2.ZERO  # world direction to reverse toward

const ARENA_MARGIN     := 60.0
const ARENA_W          := 1280.0
const ARENA_H          := 720.0
const WAYPOINT_ARRIVE_DIST := 40.0
const PICKUP_ARRIVE_DIST   := 30.0


func _ready() -> void:
	_tank = get_parent()
	_pick_waypoint()
	_react_timer = randf_range(0.0, REACT_TIME[difficulty])
	_last_position = _tank.global_position

	# Create the NavigationAgent2D. We must defer add_child because _ready()
	# fires while the tank's parent is still processing its own add_child call,
	# and Godot forbids adding children synchronously in that window.
	# _nav_ready is set to true via tree_entered so _physics_process never
	# touches the agent before it is fully in the scene tree.
	_nav_agent = NavigationAgent2D.new()
	_nav_agent.path_desired_distance = 20.0
	_nav_agent.target_desired_distance = 30.0
	_nav_agent.avoidance_enabled = false

	# Connect signals before adding to tree so we don't miss the first event.
	_nav_agent.tree_entered.connect(_on_nav_agent_tree_entered)

	_tank.add_child.call_deferred(_nav_agent)


func _on_nav_agent_tree_entered() -> void:
	# Assign the correct navigation map and wait until the NavigationServer has
	# synced the baked polygon to it (iteration_id > 0) before enabling the agent.
	var nav_region := _tank.get_parent().get_node_or_null("NavRegion") as NavigationRegion2D
	if nav_region != null:
		_nav_agent.set_navigation_map(nav_region.get_navigation_map())
	else:
		push_warning("[AI] Could not find NavRegion — agent will use default map")
	_wait_for_map.call_deferred()


func _wait_for_map() -> void:
	var map_rid := _nav_agent.get_navigation_map()
	while NavigationServer2D.map_get_iteration_id(map_rid) == 0:
		await get_tree().physics_frame
	_nav_ready = true





func _physics_process(delta: float) -> void:
	if not is_instance_valid(_tank) or _tank._dead:
		return

	_check_unstuck(delta)
	if _escape_timer > 0.0:
		_escape_timer -= delta
		# Steer toward the escape direction (away from the stuck position) and
		# reverse. Do NOT call _navigate_toward here — that could steer us back
		# into the wall we're stuck against.
		_steer_toward(_escape_dir)
		_tank.ai_throttle = 1.0   # +1.0 = reverse in tank convention
		_tank.ai_fire = false
		return

	var needs_ammo: bool   = _tank.ammo_count <= AMMO_HUNT_THRESHOLD[difficulty]
	var ammo_pickup        := _find_nearest_ammo_pickup()
	var health_pickup      := _find_health_pickup()
	var wants_health: bool = health_pickup != null

	# Priority: health > ammo > combat
	if wants_health and _state != State.HUNT_HEALTH:
		if _state == State.AIM or _state == State.FIRE:
			_prev_combat_state = _state
		else:
			_prev_combat_state = State.ROAM
		_state = State.HUNT_HEALTH

	elif not wants_health and _state == State.HUNT_HEALTH:
		_state = _prev_combat_state
		if _state == State.ROAM:
			_pick_waypoint()

	elif needs_ammo and ammo_pickup != null and _state != State.HUNT_AMMO and _state != State.HUNT_HEALTH:
		if _state == State.AIM or _state == State.FIRE:
			_prev_combat_state = _state
		else:
			_prev_combat_state = State.ROAM
		_state = State.HUNT_AMMO

	elif not needs_ammo and _state == State.HUNT_AMMO:
		_state = _prev_combat_state
		if _state == State.ROAM:
			_pick_waypoint()

	var target := _find_nearest_target()

	match _state:
		State.ROAM:
			_do_roam(delta, target)
		State.HUNT_AMMO:
			_do_hunt_ammo(delta, ammo_pickup)
		State.HUNT_HEALTH:
			_do_hunt_ammo(delta, health_pickup)  # same steering logic
		State.AIM:
			_do_aim(delta, target)
		State.FIRE:
			_do_fire(delta, target)


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

func _do_roam(delta: float, target: Node) -> void:
	_tank.ai_fire = false

	_waypoint_timer -= delta
	if _waypoint_timer <= 0.0:
		_pick_waypoint()

	if (_waypoint - _tank.global_position).length() < WAYPOINT_ARRIVE_DIST:
		_pick_waypoint()

	_navigate_toward(_waypoint)
	_tank.ai_throttle = -1.0

	if target != null:
		_react_timer -= delta
		if _react_timer <= 0.0:
			_state = State.AIM
			_lose_interest_timer = _random_interest_duration()
	else:
		_react_timer = REACT_TIME[difficulty]


func _do_hunt_ammo(delta: float, pickup: Node) -> void:
	_tank.ai_fire = false

	if pickup == null:
		# Pickup disappeared — fall back to roaming
		_state = State.ROAM
		_pick_waypoint()
		return

	var dist: float = _tank.global_position.distance_to(pickup.global_position)
	if dist < PICKUP_ARRIVE_DIST:
		_tank.ai_throttle = -0.5
		_navigate_toward(pickup.global_position)
		return

	_navigate_toward(pickup.global_position)
	_tank.ai_throttle = -1.0


func _do_aim(delta: float, target: Node) -> void:
	_tank.ai_fire = false

	if target == null:
		_return_to_roam()
		return

	_lose_interest_timer -= delta
	if _lose_interest_timer <= 0.0:
		_return_to_roam()
		return

	var dir_to_target: Vector2 = _tank.global_position.direction_to(target.global_position)
	# Navigate around walls toward enemy, but aim directly at them for shooting
	_navigate_toward(target.global_position)
	_tank.ai_throttle = -MOVE_SPEED_SCALE[difficulty]

	if abs(_angle_to_direction(dir_to_target)) < AIM_TOLERANCE[difficulty] \
			and _has_clear_shot(target):
		_state = State.FIRE


func _do_fire(delta: float, target: Node) -> void:
	if target == null:
		_return_to_roam()
		_tank.ai_fire = false
		return

	_lose_interest_timer -= delta
	if _lose_interest_timer <= 0.0:
		_return_to_roam()
		_tank.ai_fire = false
		return

	var dir_to_target: Vector2 = _tank.global_position.direction_to(target.global_position)
	_navigate_toward(target.global_position)
	_tank.ai_throttle = -MOVE_SPEED_SCALE[difficulty]

	if abs(_angle_to_direction(dir_to_target)) < AIM_TOLERANCE[difficulty] \
			and _has_clear_shot(target):
		var suppressed: bool = randf() < FIRE_SUPPRESS_RATE[difficulty] * delta
		_tank.ai_fire = not suppressed
	else:
		_tank.ai_fire = false
		_state = State.AIM


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _navigate_toward(target_pos: Vector2) -> void:
	if _nav_ready and _nav_agent != null and _nav_agent.is_inside_tree():
		# Set the destination. The NavigationServer updates the path during its
		# own sync step, which runs before _physics_process each frame, so
		# get_next_path_position() is always one frame fresh — no need for
		# velocity_computed (that signal only fires with avoidance enabled).
		_nav_agent.target_position = target_pos
		if not _nav_agent.is_navigation_finished():
			var next := _nav_agent.get_next_path_position()
			_steer_toward(_tank.global_position.direction_to(next))
			return

	# Fallback: straight line (used before the map is ready).
	_steer_toward(_tank.global_position.direction_to(target_pos))


func _has_clear_shot(target: Node) -> bool:
	# Raycast on the wall layer (layer 2) from barrel tip to target centre.
	# If any wall is hit before reaching the target, the shot is blocked.
	var space := _tank.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		_tank.global_position,
		target.global_position,
		2  # collision_mask = layer 2 (walls only)
	)
	query.exclude = [_tank.get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _check_unstuck(delta: float) -> void:
	# Only check when we're supposed to be moving
	if _state == State.ROAM or _state == State.HUNT_AMMO or \
	   _state == State.HUNT_HEALTH or _state == State.AIM or _state == State.FIRE:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_CHECK_INTERVAL:
			var moved: float = _tank.global_position.distance_to(_last_position)
			_last_position = _tank.global_position
			_stuck_timer = 0.0
			if moved < STUCK_MOVE_THRESHOLD:
				# Stuck — reverse directly away from the arena centre-wall direction.
				# Use the tank's current forward axis flipped so we back straight out,
				# regardless of where the random waypoint is.
				_escape_dir = -_tank.transform.x
				_escape_timer = STUCK_ESCAPE_DURATION
				# Pick a new waypoint for after the escape so normal nav resumes cleanly.
				_pick_waypoint()


func _return_to_roam() -> void:
	_state = State.ROAM
	_react_timer = REACT_TIME[difficulty]
	_pick_waypoint()


func _steer_toward(world_dir: Vector2) -> void:
	var forward: Vector2 = _tank.transform.x
	var cross: float = forward.cross(world_dir)
	if abs(cross) < 0.05:
		_tank.ai_turn = 0.0
	elif cross > 0.0:
		_tank.ai_turn = TURN_RATE_SCALE[difficulty]
	else:
		_tank.ai_turn = -TURN_RATE_SCALE[difficulty]


func _angle_to_direction(world_dir: Vector2) -> float:
	return _tank.transform.x.angle_to(world_dir)


func _random_interest_duration() -> float:
	match difficulty:
		0: return randf_range(1.0, 3.0)
		1: return randf_range(3.0, 6.0)
		_: return 9999.0


func _find_nearest_target() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in _tank.get_parent().get_children():
		if node == _tank:
			continue
		if not node.has_method("take_damage"):
			continue
		if node._dead:
			continue
		var d: float = _tank.global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


func _find_health_pickup() -> Node:
	for node in _tank.get_parent().get_children():
		if not node is Area2D:
			continue
		var s = node.get_script()
		if s and s.resource_path.ends_with("health_pickup.gd"):
			return node
	return null


func _find_nearest_ammo_pickup() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in _tank.get_parent().get_children():
		if not node is Area2D:
			continue
		var s = node.get_script()
		if not s or not s.resource_path.ends_with("ammo_pickup.gd"):
			continue
		var d: float = _tank.global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


func _pick_waypoint() -> void:
	_waypoint = Vector2(
		randf_range(ARENA_MARGIN, ARENA_W - ARENA_MARGIN),
		randf_range(ARENA_MARGIN, ARENA_H - ARENA_MARGIN)
	)
	_waypoint_timer = WAYPOINT_TIMEOUT[difficulty]
