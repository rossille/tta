# cursor.gd
# Autoloaded as "Cursor". Manages the OS mouse cursor and a custom red targeting
# reticle that follows the mouse on top of everything.
#
#   hide_cursor() — in-game: hide OS cursor and reticle (clean view for aiming).
#   show_cursor() — in menus/lobby/pause: show the OS cursor (and reticle) so
#                   the player can click UI elements easily.

extends CanvasLayer

const COLOR       := Color(0.85, 0.08, 0.08, 1.0)
const COLOR_INNER := Color(0.85, 0.08, 0.08, 0.5)
const R_OUTER     := 18.0   # outer circle radius
const R_INNER     := 9.0    # inner circle radius
const R_DOT       := 2.0    # centre dot radius
const CROSS_GAP   := 5.0    # gap around centre before line starts
const CROSS_LEN   := 12.0   # length of each crosshair arm
const LINE_W      := 1.5

var _draw_node: Node2D


func _ready() -> void:
	layer = 128  # always on top
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_draw_node()
	# First scene is the lobby (a menu) — start with the OS cursor visible.
	show_cursor()


## Hide the custom reticle and the OS cursor entirely (use in-game).
func hide_cursor() -> void:
	if is_instance_valid(_draw_node):
		_draw_node.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


## Show the OS cursor and the custom reticle (use in menus/lobby/pause).
func show_cursor() -> void:
	if is_instance_valid(_draw_node):
		_draw_node.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _create_draw_node() -> void:
	_draw_node = Node2D.new()
	var script := GDScript.new()
	script.source_code = """
extends Node2D
const COLOR       = Color(0.85, 0.08, 0.08, 1.0)
const COLOR_INNER = Color(0.85, 0.08, 0.08, 0.5)
const R_OUTER  = 18.0
const R_INNER  = 9.0
const R_DOT    = 2.0
const CROSS_GAP = 5.0
const CROSS_LEN = 12.0
const LINE_W   = 1.5
func _draw() -> void:
	# Outer circle
	draw_arc(Vector2.ZERO, R_OUTER, 0, TAU, 48, COLOR, LINE_W)
	# Inner circle
	draw_arc(Vector2.ZERO, R_INNER, 0, TAU, 32, COLOR_INNER, LINE_W)
	# Centre dot
	draw_circle(Vector2.ZERO, R_DOT, COLOR)
	# Crosshair arms (gap around centre)
	draw_line(Vector2(-CROSS_GAP, 0), Vector2(-CROSS_GAP - CROSS_LEN, 0), COLOR, LINE_W)
	draw_line(Vector2( CROSS_GAP, 0), Vector2( CROSS_GAP + CROSS_LEN, 0), COLOR, LINE_W)
	draw_line(Vector2(0, -CROSS_GAP), Vector2(0, -CROSS_GAP - CROSS_LEN), COLOR, LINE_W)
	draw_line(Vector2(0,  CROSS_GAP), Vector2(0,  CROSS_GAP + CROSS_LEN), COLOR, LINE_W)
"""
	script.reload()
	_draw_node.set_script(script)
	add_child(_draw_node)


func _process(_delta: float) -> void:
	if is_instance_valid(_draw_node) and _draw_node.visible:
		_draw_node.position = get_viewport().get_mouse_position()
		_draw_node.queue_redraw()
