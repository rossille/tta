# lobby.gd
# Three panels:
#   PanelMain   — two-column layout: players left, AI right. Fixed header/footer.
#   PanelJoin   — browse/connect to a LAN game.
#   PanelClient — shown when connected to a remote host as a client.

extends Control

const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard"]

# Button effect tuning
const _BTN_HOVER_COLOR := Color(1.18, 1.08, 0.85, 1.0)
const _BTN_PRESS_COLOR := Color(0.78, 0.74, 0.70, 1.0)
const _BTN_PRESS_SCALE := Vector2(0.975, 0.975)
const _BTN_HOVER_DUR   := 0.10
const _BTN_PRESS_DUR   := 0.05
const _BTN_RELEASE_DUR := 0.12

var ICON_PLAYER: Texture2D
var ICON_AI:     Texture2D

# ---------------------------------------------------------------------------
# Panel references
# ---------------------------------------------------------------------------
@onready var _panel_main:   Control = $PanelMain
@onready var _panel_join:   Control = $PanelJoin
@onready var _panel_client: Control = $PanelClient

# Main panel
@onready var _player_list:      VBoxContainer = $PanelMain/Layout/Body/LeftCol/PlayerScroll/PlayerList
@onready var _player_count_lbl: Label         = $PanelMain/Layout/Body/LeftCol/PlayersHeader/PlayerCountLabel
@onready var _status_line:      Label         = $PanelMain/Layout/Body/LeftCol/StatusLine
@onready var _ai_list_vbox:     VBoxContainer = $PanelMain/Layout/Body/RightCol/AIScroll/AIList
@onready var _ai_empty_lbl:     Label         = $PanelMain/Layout/Body/RightCol/AIScroll/AIList/AIEmptyLabel
@onready var _add_ai_btn:       TextureButton = $PanelMain/Layout/Body/RightCol/AddAIBtn
@onready var _window_btn:       TextureButton = $PanelMain/Layout/Footer/BottomRow/WindowBtn
@onready var _window_btn_label: Label         = $PanelMain/Layout/Footer/BottomRow/WindowBtn/Label

# Client panel
@onready var _client_player_list: VBoxContainer = $PanelClient/VBox/PlayerList

# Join panel
@onready var _games_list:  VBoxContainer = $PanelJoin/VBox/GamesList
@onready var _join_status: Label         = $PanelJoin/VBox/Status
@onready var _manual_ip:   LineEdit      = $PanelJoin/VBox/ManualRow/IPField


# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	Cursor.show_cursor()
	Audio.play_music("lobby", 1.0)
	ICON_PLAYER = load("res://assets/icon_player.png")
	ICON_AI     = load("res://assets/icon_ai.png")

	_show_panel(_panel_main)
	_window_btn_label.text = "TOGGLE FULLSCREEN"

	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connected_to_server.connect(_on_connected_to_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.player_list_updated.connect(_refresh_player_list)
	LanDiscovery.games_updated.connect(_on_games_updated)

	# Wire hover/press effects on all static buttons
	for btn in [
		_add_ai_btn,
		$PanelMain/Layout/Footer/StartBtn,
		$PanelMain/Layout/Footer/BottomRow/JoinBtn,
		_window_btn,
		$PanelMain/Layout/Footer/BottomRow/QuitBtn,
		$PanelJoin/VBox/ManualRow/ManualJoinBtn,
		$PanelJoin/VBox/BackBtn,
		$PanelClient/VBox/QuitBtn,
	]:
		_wire_button_effects(btn)

	_start_hosting()


func _exit_tree() -> void:
	LanDiscovery.stop_broadcast()
	LanDiscovery.stop_listening()


# ---------------------------------------------------------------------------
# Panel switching
# ---------------------------------------------------------------------------
func _show_panel(panel: Control) -> void:
	_panel_main.visible   = panel == _panel_main
	_panel_join.visible   = panel == _panel_join
	_panel_client.visible = panel == _panel_client


# ---------------------------------------------------------------------------
# Hosting
# ---------------------------------------------------------------------------
func _start_hosting() -> void:
	var err := Net.host()
	if err != OK:
		push_warning("lobby: failed to start host (port in use?)")
		_status_line.text = "Failed to host (port in use?)"
		return
	LanDiscovery.start_broadcast(Net._local_player_name() + "'s game", Net.DEFAULT_PORT)
	_status_line.text = "Hosting · port %d" % Net.DEFAULT_PORT
	_refresh_player_list()


# ---------------------------------------------------------------------------
# Player list (left column) + AI list (right column)
# ---------------------------------------------------------------------------
func _total_players() -> int:
	return Net.player_info.size() + GameConfig.ai_list.size()


func _refresh_player_list() -> void:
	var is_client := _panel_client.visible

	if is_client:
		_refresh_client_list()
		return

	# --- Left column: human players ---
	for c in _player_list.get_children():
		c.queue_free()

	var ids := Net.player_info.keys()
	ids.sort()
	var my_id := Net.my_id()
	if ids.has(my_id):
		ids.erase(my_id)
		ids.push_front(my_id)

	for id in ids:
		var info: Dictionary = Net.player_info[id]
		var row := _make_player_row(info.get("name", "?"), id == my_id, false)
		_player_list.add_child(row)

	# Update player count badge
	_player_count_lbl.text = "%d / 4" % _total_players()

	# --- Right column: AI entries ---
	_refresh_ai_list()

	# Add AI button state
	_add_ai_btn.disabled = _total_players() >= 4


func _refresh_ai_list() -> void:
	for c in _ai_list_vbox.get_children():
		c.queue_free()

	if GameConfig.ai_list.is_empty():
		var lbl := Label.new()
		lbl.text = "No AI added"
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.45, 0.43, 0.36, 1))
		_ai_list_vbox.add_child(lbl)
		return

	for i in range(GameConfig.ai_list.size()):
		var entry: Dictionary = GameConfig.ai_list[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var icon := TextureRect.new()
		icon.texture = ICON_AI
		icon.custom_minimum_size = Vector2(20, 20)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon)

		var lbl := Label.new()
		lbl.text = "AI %d" % (i + 1)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.839, 0.812, 0.706, 1))
		row.add_child(lbl)

		var diff := OptionButton.new()
		for d in DIFFICULTY_NAMES:
			diff.add_item(d)
		diff.selected = entry.get("difficulty", 1)
		diff.custom_minimum_size = Vector2(80, 0)
		diff.item_selected.connect(_on_ai_difficulty_changed.bind(i))
		row.add_child(diff)

		var rm := Button.new()
		rm.text = "✕"
		rm.custom_minimum_size = Vector2(26, 26)
		rm.pressed.connect(_on_remove_ai_pressed.bind(i))
		row.add_child(rm)

		_ai_list_vbox.add_child(row)


func _refresh_client_list() -> void:
	for c in _client_player_list.get_children():
		c.queue_free()
	var ids := Net.player_info.keys()
	ids.sort()
	var my_id := Net.my_id()
	if ids.has(my_id):
		ids.erase(my_id)
		ids.push_front(my_id)
	for id in ids:
		var info: Dictionary = Net.player_info[id]
		var row := _make_player_row(info.get("name", "?"), id == my_id, false)
		_client_player_list.add_child(row)


func _make_player_row(player_name: String, is_local: bool, _is_ai: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = ICON_PLAYER
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = player_name + (" (you)" if is_local else "")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.839, 0.812, 0.706, 1))
	row.add_child(lbl)

	return row


func _on_peer_connected(_id: int) -> void:
	_refresh_player_list()

func _on_peer_disconnected(_id: int) -> void:
	_refresh_player_list()


# ---------------------------------------------------------------------------
# AI management
# ---------------------------------------------------------------------------
func _on_add_ai_pressed() -> void:
	if _total_players() >= 4:
		Audio.play_ui("error")
		return
	Audio.play_ui("click")
	GameConfig.ai_list.append({ "difficulty": 1 })
	_refresh_player_list()


func _on_remove_ai_pressed(index: int) -> void:
	Audio.play_ui("back")
	if index < GameConfig.ai_list.size():
		GameConfig.ai_list.remove_at(index)
	_refresh_player_list()


func _on_ai_difficulty_changed(value: int, index: int) -> void:
	if index < GameConfig.ai_list.size():
		GameConfig.ai_list[index]["difficulty"] = value


# ---------------------------------------------------------------------------
# Window / quit
# ---------------------------------------------------------------------------
func _on_window_btn_pressed() -> void:
	Audio.play_ui("click")
	WindowManager.toggle()

func _on_quit_pressed() -> void:
	Audio.play_ui("back")
	get_tree().quit()


# ---------------------------------------------------------------------------
# Join flow
# ---------------------------------------------------------------------------
func _on_join_pressed() -> void:
	Audio.play_ui("click")
	Net.disconnect_net()
	LanDiscovery.stop_broadcast()
	_show_panel(_panel_join)
	_join_status.text = "Searching for games on LAN..."
	_games_list_clear()
	LanDiscovery.start_listening()
	_on_games_updated(LanDiscovery.discovered)


func _on_games_updated(games: Array) -> void:
	if not _panel_join.visible:
		return
	_games_list_clear()
	if games.is_empty():
		var lbl := Label.new()
		lbl.text = "(no games found)"
		lbl.add_theme_color_override("font_color", Color(0.739, 0.712, 0.606, 1))
		_games_list.add_child(lbl)
		return
	for g in games:
		var btn := TextureButton.new()
		btn.texture_normal = load("res://assets/btn_normal.png")
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.ignore_texture_size = true
		btn.custom_minimum_size = Vector2(0, 52)
		btn.pressed.connect(_connect_to.bind(g["ip"], g["port"]))

		var lbl := Label.new()
		lbl.text = "%s  —  %s:%d" % [g["name"], g["ip"], g["port"]]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.add_theme_color_override("font_color", Color(0.839, 0.812, 0.706, 1))
		lbl.add_theme_font_size_override("font_size", 14)
		btn.add_child(lbl)
		_games_list.add_child(btn)
		_wire_button_effects(btn)


func _games_list_clear() -> void:
	for c in _games_list.get_children():
		c.queue_free()


func _on_manual_join_pressed() -> void:
	Audio.play_ui("confirm")
	var ip := _manual_ip.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	_connect_to(ip, Net.DEFAULT_PORT)


func _connect_to(ip: String, port: int) -> void:
	_join_status.text = "Connecting to %s:%d..." % [ip, port]
	LanDiscovery.stop_listening()
	var err := Net.join(ip, port)
	if err != OK:
		_join_status.text = "Connection error."


func _on_connected_to_server() -> void:
	_show_panel(_panel_client)
	_refresh_player_list()


func _on_connection_failed() -> void:
	_join_status.text = "Connection failed. Try again."
	LanDiscovery.start_listening()


func _on_back_to_main_pressed() -> void:
	Audio.play_ui("back")
	Net.disconnect_net()
	LanDiscovery.stop_listening()
	_show_panel(_panel_main)
	_start_hosting()


# ---------------------------------------------------------------------------
# Start game
# ---------------------------------------------------------------------------
func _on_start_pressed() -> void:
	if Net.is_active() and not Net.is_host():
		return
	Audio.play_ui("confirm")
	LanDiscovery.stop_broadcast()
	_load_arena.rpc()


@rpc("authority", "call_local", "reliable")
func _load_arena() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ---------------------------------------------------------------------------
# Button hover/press effects — heated metal hover, tactile press
# ---------------------------------------------------------------------------
func _wire_button_effects(button: TextureButton) -> void:
	button.set_meta("hovering", false)
	button.set_meta("pressed_state", false)
	button.resized.connect(func(): button.pivot_offset = button.size / 2.0)
	button.mouse_entered.connect(_btn_set_hover.bind(button, true))
	button.mouse_exited.connect(_btn_set_hover.bind(button, false))
	button.button_down.connect(_btn_set_pressed.bind(button, true))
	button.button_up.connect(_btn_set_pressed.bind(button, false))


func _btn_set_hover(button: TextureButton, hovering: bool) -> void:
	button.set_meta("hovering", hovering)
	Audio.play_ui("hover")
	_btn_update_visual(button, _BTN_HOVER_DUR)


func _btn_set_pressed(button: TextureButton, pressed: bool) -> void:
	button.set_meta("pressed_state", pressed)
	_btn_update_visual(button, _BTN_PRESS_DUR if pressed else _BTN_RELEASE_DUR)


func _btn_update_visual(button: TextureButton, duration: float) -> void:
	var hovering: bool = button.get_meta("hovering", false)
	var pressed:  bool = button.get_meta("pressed_state", false)

	var target_color: Color
	var target_scale: Vector2
	if pressed:
		target_color = _BTN_PRESS_COLOR
		target_scale = _BTN_PRESS_SCALE
	elif hovering:
		target_color = _BTN_HOVER_COLOR
		target_scale = Vector2.ONE
	else:
		target_color = Color(1, 1, 1, 1)
		target_scale = Vector2.ONE

	if button.has_meta("active_tween"):
		var prev = button.get_meta("active_tween")
		if prev != null and is_instance_valid(prev) and prev.is_running():
			prev.kill()

	var tw := create_tween().set_parallel(true)
	tw.tween_property(button, "modulate", target_color, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "scale", target_scale, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	button.set_meta("active_tween", tw)
