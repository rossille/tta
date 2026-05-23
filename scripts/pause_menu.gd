# pause_menu.gd
# In-game pause overlay. Toggled by ESC.
# Does NOT use get_tree().paused — tanks keep simulating in the background
# (pausing in multiplayer would desync). The menu is purely visual/input.

extends CanvasLayer

@onready var _panel:        Control = $Panel
@onready var _fullscreen_btn: Button = $Panel/VBox/FullscreenBtn


func _ready() -> void:
	_panel.visible = false
	# Process even when the game scene is "paused" (process_mode always)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_set_visible(not _panel.visible)


func _set_visible(visible: bool) -> void:
	_panel.visible = visible
	if visible:
		_fullscreen_btn.text = "Windowed" if WindowManager.is_fullscreen() else "Fullscreen"
		# Show the OS cursor so the player can click menu buttons easily.
		Cursor.show_cursor()
	else:
		# Back to gameplay — hide the cursor again.
		Cursor.hide_cursor()


func _on_resume_pressed() -> void:
	_set_visible(false)


func _on_fullscreen_pressed() -> void:
	WindowManager.toggle()
	_fullscreen_btn.text = "Windowed" if WindowManager.is_fullscreen() else "Fullscreen"


func _on_quit_pressed() -> void:
	get_tree().quit()
