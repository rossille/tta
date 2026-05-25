# education_overlay.gd
# Visual layer for the educational module. Two panels share the same overlay:
#   - LearnPanel: shows 3 multiplications, optionally with a close button
#                  (regular learn = closable, penalty review = locked).
#   - QuizPanel:  shows "a x b = ?" + a 10x10 grid of number buttons.
#
# This script is purely UI. All timing, state transitions, and pause control
# live in education_manager.gd. The overlay only emits signals and renders.
#
# process_mode = ALWAYS so the overlay keeps receiving input while the game
# tree is paused (the Education manager pauses the tree during overlays).

extends CanvasLayer

signal learn_closed
signal quiz_answered(answer: int)

@onready var _dimmer:      ColorRect = $Dimmer
@onready var _learn_panel: Control   = $LearnPanel
@onready var _quiz_panel:  Control   = $QuizPanel
@onready var _equation_labels: Array = [
	$LearnPanel/VBox/Equation1,
	$LearnPanel/VBox/Equation2,
	$LearnPanel/VBox/Equation3,
]
@onready var _close_btn:     Button       = $LearnPanel/VBox/CloseBtn
@onready var _forced_notice: Label        = $LearnPanel/VBox/ForcedNotice
@onready var _quiz_title:    Label        = $QuizPanel/VBox/QuestionLabel
@onready var _quiz_grid:     GridContainer = $QuizPanel/VBox/Grid

var _grid_built: bool = false
var _is_forced: bool = false


func _ready() -> void:
	# Keep input flowing while get_tree().paused is true.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Dimmer is set visible-by-default in the .tscn so it's easy to see while
	# editing the scene; hide it at runtime until a panel actually opens.
	_dimmer.visible = false
	_learn_panel.visible = false
	_quiz_panel.visible = false
	_close_btn.pressed.connect(_on_close_pressed)
	_build_grid()


# Build the 10x10 grid of answer buttons once, lazily.
func _build_grid() -> void:
	if _grid_built:
		return
	_quiz_grid.columns = EducationConfig.GRID_COLUMNS
	for n in range(EducationConfig.GRID_MIN, EducationConfig.GRID_MAX + 1):
		var btn := Button.new()
		btn.text = str(n)
		btn.custom_minimum_size = Vector2(54, 40)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_answer_btn_pressed.bind(n))
		_quiz_grid.add_child(btn)
	_grid_built = true


## Show the learn panel.
##   session: Array of equation dicts (a, b, result).
##   forced:  if true, the close button is hidden and a notice is shown.
func show_learn(session: Array, forced: bool) -> void:
	_is_forced = forced
	for i in range(_equation_labels.size()):
		var label: Label = _equation_labels[i]
		if i < session.size():
			var eq: Dictionary = session[i]
			label.text = "%d  x  %d  =  %d" % [eq.a, eq.b, eq.result]
			label.visible = true
		else:
			label.visible = false
	_close_btn.visible = not forced
	_forced_notice.visible = forced
	_dimmer.visible = true
	_learn_panel.visible = true
	_quiz_panel.visible = false
	Cursor.show_cursor()


## Show the quiz panel for a single equation.
func show_quiz(question: Dictionary) -> void:
	_quiz_title.text = "%d  x  %d  =  ?" % [question.a, question.b]
	_dimmer.visible = true
	_quiz_panel.visible = true
	_learn_panel.visible = false
	Cursor.show_cursor()


## Hide both panels (game returns to gameplay).
func hide_all() -> void:
	_dimmer.visible = false
	_learn_panel.visible = false
	_quiz_panel.visible = false
	Cursor.hide_cursor()


func _on_close_pressed() -> void:
	if _is_forced:
		return  # button shouldn't even be visible in this state, but be safe
	Audio.play_ui("click")
	learn_closed.emit()


func _on_answer_btn_pressed(value: int) -> void:
	quiz_answered.emit(value)
