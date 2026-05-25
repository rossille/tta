# education_manager.gd
# Drives the educational module's state machine, pauses/unpauses the game
# tree around overlays, and rewards/penalizes the local player.
#
# Activation rules (checked at _ready and on every peer connect/disconnect):
#   - EducationConfig.ENABLED must be true
#   - Must be in real solo: Net.is_host() AND only one entry in Net.player_info
#
# If a guest connects mid-match, the module deactivates immediately:
# any open overlay is hidden, the game is unpaused, and no further session
# will trigger. (We don't try to reactivate later, even if the guest leaves.)
#
# State machine:
#   IDLE              -> count gameplay seconds, then start a session
#   LEARNING          -> learn overlay open, game paused, wait for close
#   WAITING_QUIZ      -> game unpaused, count seconds, then open quiz
#   QUIZ              -> quiz overlay open, game paused, wait for answer
#   PENALTY_REVIEW    -> learn overlay locked open, game paused, fixed timer
#   PENALTY_WAITING   -> game unpaused, count seconds, then retry quiz
#
# Note: the manager runs in PROCESS_MODE_ALWAYS so its timer keeps ticking
# during the paused PENALTY_REVIEW state. Each state explicitly tests
# get_tree().paused to advance the right timer.

extends Node

## Emitted when a revival quiz ends (whether the player answered correctly
## or not). arena._check_win() awaits this before declaring the winner.
signal revival_resolved

enum State {
	DISABLED,        # Feature off (toggle, or not in solo)
	IDLE,            # Counting down to next session
	LEARNING,        # Learn overlay open (closable)
	WAITING_QUIZ,    # Free play before quiz
	QUIZ,            # Quiz overlay open
	PENALTY_REVIEW,  # Forced review overlay (locked)
	PENALTY_WAITING, # Free play before retry quiz
	REVIVAL_QUIZ,    # Player just died — answer correctly to be revived
}

@export var overlay_scene: PackedScene

var _state: int = State.DISABLED
var _timer: float = 0.0
var _current_session: Array = []
var _current_question: Dictionary = {}
var _overlay: CanvasLayer = null
var _revival_tank: Node = null   # tank awaiting revival (REVIVAL_QUIZ state)


func _ready() -> void:
	# Keep ticking even when get_tree().paused is true so the
	# PENALTY_REVIEW timer can advance during the paused overlay.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not EducationConfig.ENABLED:
		# Module disabled at config level. We don't even instantiate the overlay.
		_state = State.DISABLED
		return

	# Instantiate and add the overlay as a child so it lives & dies with us.
	if overlay_scene == null:
		push_warning("EducationManager: overlay_scene not assigned")
		_state = State.DISABLED
		return
	_overlay = overlay_scene.instantiate() as CanvasLayer
	add_child(_overlay)
	_overlay.learn_closed.connect(_on_learn_closed)
	_overlay.quiz_answered.connect(_on_quiz_answered)

	# Net is an autoload; its signals are stable across the match.
	# We use peer_connected to deactivate if a guest joins mid-match.
	Net.peer_connected.connect(_on_peer_connected)

	# Decide initial state based on current solo-ness.
	if _is_solo_match():
		_enter_idle()
		# Death signal is connected later by arena via register_player_tank(),
		# once the tank is actually spawned.
	else:
		_state = State.DISABLED


# ---------------------------------------------------------------------------
# Solo detection
# ---------------------------------------------------------------------------
# "Real solo" = I'm the host AND no other peer is in player_info.
# The lobby auto-hosts on launch (see lobby.gd:_start_hosting), so
# Net.is_active() is true even for a 1-player + AI match — we cannot
# use it alone. We must check the actual player count.
func _is_solo_match() -> bool:
	if not Net.is_host():
		return false
	return Net.player_info.size() <= 1


func _on_peer_connected(_id: int) -> void:
	# A guest joined: shut everything down.
	if _state == State.DISABLED:
		return
	_force_deactivate()


func _force_deactivate() -> void:
	# Close any open overlay and unpause, then mark disabled forever.
	if _overlay != null:
		_overlay.hide_all()
	if get_tree().paused:
		get_tree().paused = false
	_state = State.DISABLED


## Called by the arena when the match ends (win or loss screen shown).
## Disables the module for the remainder of this scene instance.
func stop() -> void:
	_force_deactivate()


# ---------------------------------------------------------------------------
# Death hook
# ---------------------------------------------------------------------------

## Called by arena._register_player_tank_with_education() right after spawn,
## once the local player's tank node is guaranteed to exist.
func register_player_tank(tank: Node) -> void:
	if _state == State.DISABLED:
		return
	if tank.has_signal("died") and not tank.died.is_connected(_on_tank_died):
		tank.died.connect(_on_tank_died)


func _on_tank_died(_tank: Node) -> void:
	if _state == State.DISABLED:
		return
	# If the normal quiz cycle is mid-flight, suspend it by going straight
	# to REVIVAL_QUIZ. The cycle won't resume — after a revival or a failed
	# attempt we return to IDLE and start fresh.
	_revival_tank = _tank

	# Build a single-equation session for the revival question (no learn phase).
	var session: Array = MultiplicationQuiz.generate_session(
		EducationConfig.TABLES,
		EducationConfig.MULTIPLIER_MIN,
		EducationConfig.MULTIPLIER_MAX,
		1
	)
	_current_session  = session
	_current_question = MultiplicationQuiz.pick_question(session)
	_state = State.REVIVAL_QUIZ

	# Close any overlay that was open (e.g. normal quiz was showing).
	# The game is already effectively over for the player (they're dead), but
	# we still pause so the remaining tanks freeze while the question is up.
	_overlay.hide_all()
	_overlay.show_quiz(_current_question)
	get_tree().paused = true


# ---------------------------------------------------------------------------
# Tick — drive whichever timer matches the current state
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _state == State.DISABLED:
		return

	var paused: bool = get_tree().paused

	match _state:
		State.IDLE:
			# Count gameplay seconds only.
			if not paused:
				_timer += delta
				if _timer >= EducationConfig.SESSION_INTERVAL:
					_start_learning()

		State.LEARNING:
			# Waiting for the player to press the close button.
			pass

		State.WAITING_QUIZ:
			if not paused:
				_timer += delta
				if _timer >= EducationConfig.DELAY_BEFORE_QUIZ:
					_start_quiz()

		State.QUIZ:
			# Waiting for the player to click a number.
			pass

		State.PENALTY_REVIEW:
			# Overlay is open, game is paused. We tick during pause.
			if paused:
				_timer += delta
				if _timer >= EducationConfig.PENALTY_REVIEW_DURATION:
					_end_penalty_review()

		State.PENALTY_WAITING:
			if not paused:
				_timer += delta
				if _timer >= EducationConfig.PENALTY_DELAY_BEFORE_RETRY:
					_start_quiz()


# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------
func _enter_idle() -> void:
	_state = State.IDLE
	_timer = 0.0


func _start_learning() -> void:
	_current_session = MultiplicationQuiz.generate_session(
		EducationConfig.TABLES,
		EducationConfig.MULTIPLIER_MIN,
		EducationConfig.MULTIPLIER_MAX,
		EducationConfig.EQUATIONS_PER_SESSION
	)
	_state = State.LEARNING
	_timer = 0.0
	_overlay.show_learn(_current_session, false)
	get_tree().paused = true


func _on_learn_closed() -> void:
	if _state != State.LEARNING:
		return
	_overlay.hide_all()
	get_tree().paused = false
	_state = State.WAITING_QUIZ
	_timer = 0.0


func _start_quiz() -> void:
	_current_question = MultiplicationQuiz.pick_question(_current_session)
	_state = State.QUIZ
	_timer = 0.0
	_overlay.show_quiz(_current_question)
	get_tree().paused = true


func _on_quiz_answered(answer: int) -> void:
	match _state:
		State.QUIZ:
			if MultiplicationQuiz.is_correct(_current_question, answer):
				_on_correct_answer()
			else:
				_on_wrong_answer()
		State.REVIVAL_QUIZ:
			if MultiplicationQuiz.is_correct(_current_question, answer):
				_on_revival_correct()
			else:
				_on_revival_wrong()


func _on_correct_answer() -> void:
	# Pickup-ammo SFX doubles as our victory chime: it's joyful and
	# thematically perfect (the player literally just earned ammo).
	Audio.play_sfx("pickup_ammo")

	# Grant ammo to the local player's tank, if it exists & is alive.
	var arena: Node = get_parent()
	if arena != null and arena.has_method("get_local_player_tank"):
		var tank: Node = arena.call("get_local_player_tank")
		if tank != null and tank.has_method("add_ammo"):
			tank.add_ammo(EducationConfig.AMMO_REWARD)

	# Hide the quiz overlay but keep the game paused for 1 second so the
	# player's mind can transition back to the game before tanks start moving.
	_overlay.hide_all()
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false
	_enter_idle()


func _on_wrong_answer() -> void:
	Audio.play_ui("error")
	_state = State.PENALTY_REVIEW
	_timer = 0.0
	# Re-open the learn overlay, but locked (no close button).
	# Game is already paused from the quiz overlay; we keep it paused.
	_overlay.show_learn(_current_session, true)


func _end_penalty_review() -> void:
	_overlay.hide_all()
	get_tree().paused = false
	_state = State.PENALTY_WAITING
	_timer = 0.0


# ---------------------------------------------------------------------------
# Revival outcomes
# ---------------------------------------------------------------------------
func _on_revival_correct() -> void:
	Audio.play_sfx("pickup_ammo")
	if is_instance_valid(_revival_tank) and _revival_tank.has_method("revive"):
		_revival_tank.revive()
	_revival_tank = null
	_overlay.hide_all()
	revival_resolved.emit()
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false
	_enter_idle()


func _on_revival_wrong() -> void:
	Audio.play_ui("error")
	_revival_tank = null
	_overlay.hide_all()
	get_tree().paused = false
	revival_resolved.emit()
	_enter_idle()
