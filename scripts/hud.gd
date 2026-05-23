# hud.gd
# Minimal overlay: hidden during play, shows winner + rematch/quit buttons.
# In multiplayer, only the host sees Rematch; scene transitions are broadcast
# to all peers via RPC so everyone moves together.

extends CanvasLayer

@onready var _panel:        Control = $Panel
@onready var _winner_label: Label   = $Panel/VBox/WinnerLabel
@onready var _rematch_btn:  Button  = $Panel/VBox/RematchBtn
@onready var _continue_btn: Button  = $Panel/VBox/ContinueBtn

signal continued


func _ready() -> void:
	_panel.visible = false


func show_winner(winner_name: String) -> void:
	_winner_label.text = winner_name + "\nWINS!"
	# Only the host can trigger a rematch — hide the button for clients
	_rematch_btn.visible = not Net.is_active() or Net.is_host()
	_panel.visible = true
	# Show the OS cursor so the player can click the menu buttons.
	Cursor.show_cursor()


func _on_continue_pressed() -> void:
	_panel.visible = false
	# Back to watching gameplay — hide the cursor again.
	Cursor.hide_cursor()
	emit_signal("continued")


func _on_rematch_pressed() -> void:
	if Net.is_active():
		_rpc_goto.rpc("res://scenes/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_lobby_pressed() -> void:
	if Net.is_active():
		_rpc_goto.rpc("res://scenes/lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


@rpc("authority", "call_local", "reliable")
func _rpc_goto(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
