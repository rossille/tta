# pause_menu.gd
# In-game pause overlay. Toggled by ESC.
# Does NOT use get_tree().paused — tanks keep simulating in the background
# (pausing in multiplayer would desync). The menu is purely visual/input.

extends CanvasLayer

@onready var _panel:          Control = $Panel
@onready var _fullscreen_btn: Button  = $Panel/VBox/FullscreenBtn
@onready var _master_slider:  HSlider = $Panel/VBox/VolumeSection/MasterRow/MasterSlider
@onready var _sfx_slider:     HSlider = $Panel/VBox/VolumeSection/SfxRow/SfxSlider
@onready var _music_slider:   HSlider = $Panel/VBox/VolumeSection/MusicRow/MusicSlider

# Suppress the slider's value_changed callback while we're populating values
# from the AudioServer at startup (so we don't re-save settings on load).
var _populating: bool = false


func _ready() -> void:
	_panel.visible = false
	# Process even when the game scene is "paused" (process_mode always)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_populate_volume_sliders()


func _populate_volume_sliders() -> void:
	_populating = true
	_master_slider.value = Audio.db_curve_to_linear(Audio.get_bus_volume_db("Master"))
	_sfx_slider.value    = Audio.db_curve_to_linear(Audio.get_bus_volume_db("SFX"))
	_music_slider.value  = Audio.db_curve_to_linear(Audio.get_bus_volume_db("Music"))
	_populating = false


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
	Audio.play_ui("back")
	_set_visible(false)


func _on_fullscreen_pressed() -> void:
	Audio.play_ui("click")
	WindowManager.toggle()
	_fullscreen_btn.text = "Windowed" if WindowManager.is_fullscreen() else "Fullscreen"


func _on_quit_pressed() -> void:
	Audio.play_ui("back")
	get_tree().quit()


# ---------------------------------------------------------------------------
# Volume sliders (0..1 linear → dB curve handled in Audio singleton)
# ---------------------------------------------------------------------------
func _on_master_changed(linear: float) -> void:
	if _populating: return
	Audio.set_bus_volume_db("Master", Audio.linear_to_db_curve(linear))

func _on_sfx_changed(linear: float) -> void:
	if _populating: return
	Audio.set_bus_volume_db("SFX", Audio.linear_to_db_curve(linear))

func _on_music_changed(linear: float) -> void:
	if _populating: return
	Audio.set_bus_volume_db("Music", Audio.linear_to_db_curve(linear))
