# window_manager.gd
# Autoloaded as "WindowManager".
# Owns fullscreen/windowed toggling and handles the F11 shortcut globally.

extends Node

# Windowed size used when switching out of fullscreen
const WINDOWED_SIZE := Vector2i(1280, 720)


func _ready() -> void:
	# Process input even when the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F11:
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	var win := get_window()
	if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		win.mode = Window.MODE_WINDOWED
		win.size = WINDOWED_SIZE
		# Centre the window on screen
		var screen_size := DisplayServer.screen_get_size()
		win.position = (screen_size - WINDOWED_SIZE) / 2
	else:
		win.mode = Window.MODE_FULLSCREEN


func is_fullscreen() -> bool:
	var mode := get_window().mode
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN
