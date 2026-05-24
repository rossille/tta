# debug_log.gd
# Autoloaded as "DebugLog". Provides a Net-aware logger that funnels every
# call into one file on the host, so we can correlate guest and host events
# while debugging multiplayer issues across machines.
#
# Usage from anywhere:
#   DebugLog.l("something happened: %s" % some_value)
#
# Behaviour:
#   - Locally echoed to stdout via print() so a debug build still shows the
#     message in its terminal / console wrapper.
#   - On the host (or in solo play) the message is written immediately to
#     user://debug.log.
#   - On a guest, the message is forwarded to the host over a reliable RPC;
#     the host appends it to the same file tagged with the sender's peer id.
#
# File path on each platform (this is what `user://` globalises to):
#   macOS:   ~/Library/Application Support/Godot/app_userdata/TankArena/debug.log
#   Linux:   ~/.local/share/godot/app_userdata/TankArena/debug.log
#   Windows: %APPDATA%\Godot\app_userdata\TankArena\debug.log
#
# The file is truncated at startup so each run has a clean log — copy it
# aside if you need to keep history across runs. The absolute path is also
# printed once at startup so you can find it quickly.

extends Node

const LOG_FILE := "user://debug.log"

var _file: FileAccess = null
var _opened: bool = false


func _ready() -> void:
	_open_file()


func _open_file() -> void:
	if _opened:
		return
	_opened = true
	_file = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	if _file == null:
		push_error("[DebugLog] could not open " + LOG_FILE)
		return
	var abs_path: String = ProjectSettings.globalize_path(LOG_FILE)
	_file.store_string("=== TankArena debug log started at %s ===\n  path: %s\n" % [
		Time.get_datetime_string_from_system(),
		abs_path,
	])
	_file.flush()
	print("[DebugLog] writing to ", abs_path)


# Public API. Call this from anywhere.
func l(msg: String) -> void:
	# Local stdout echo first so we never lose a message if the RPC fails.
	print("[DBG] ", msg)
	if Net.is_active() and not Net.is_host():
		_rpc_to_host.rpc_id(1, msg)
	else:
		var peer_id: int = Net.my_id() if Net.is_active() else 0
		_write(peer_id, msg)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_to_host(msg: String) -> void:
	_write(multiplayer.get_remote_sender_id(), msg)


func _write(peer_id: int, msg: String) -> void:
	if _file == null:
		return
	_file.store_string("%s [peer %d] %s\n" % [
		Time.get_time_string_from_system(),
		peer_id,
		msg,
	])
	_file.flush()
