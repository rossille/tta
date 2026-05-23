# net.gd
# Autoloaded as "Net". Owns the ENet multiplayer peer and all connection
# lifecycle. Works transparently in single-player (no peer created → every
# node is its own authority).

extends Node

const DEFAULT_PORT := 7000
const MAX_PLAYERS  := 4

# Emitted on all peers
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connected_to_server
signal player_list_updated   # fired whenever player_info changes on any peer

# player_info[peer_id] = { "name": String }
var player_info: Dictionary = {}

var _peer: ENetMultiplayerPeer = null


# ---------------------------------------------------------------------------
# Connect multiplayer signals once at startup — never reconnect them
# ---------------------------------------------------------------------------
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------
func host(port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_peer = null
		return err

	multiplayer.multiplayer_peer = _peer

	# Register the host itself
	player_info[1] = { "name": _local_player_name() }
	return OK


# ---------------------------------------------------------------------------
# Join
# ---------------------------------------------------------------------------
func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		_peer = null
		return err

	multiplayer.multiplayer_peer = _peer
	return OK


# ---------------------------------------------------------------------------
# Disconnect / reset
# ---------------------------------------------------------------------------
func disconnect_net() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	_peer = null
	player_info.clear()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func is_host() -> bool:
	return multiplayer.is_server()


func is_active() -> bool:
	# A peer reference alone isn't enough — when a session ends (host quits,
	# socket dropped, etc.) ENet flips its internal `active` flag to false but
	# the Ref<MultiplayerPeer> stays put, so `multiplayer.has_multiplayer_peer()`
	# still reports true. Calling `get_unique_id()` / `is_server()` /
	# `is_multiplayer_authority()` on the peer in that state asserts and spams
	# "The multiplayer instance isn't currently active." every frame. Gate on
	# the connection status so callers only branch into multiplayer code paths
	# when the peer can actually answer those queries.
	if _peer == null:
		return false
	return _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func my_id() -> int:
	return multiplayer.get_unique_id()


func _local_player_name() -> String:
	return OS.get_environment("USER") if OS.get_environment("USER") != "" else "Player"


# ---------------------------------------------------------------------------
# Multiplayer callbacks
# ---------------------------------------------------------------------------
func _on_peer_connected(id: int) -> void:
	emit_signal("peer_connected", id)
	if is_host():
		# Small delay so the client's RPC receiver is ready before we call it
		await get_tree().create_timer(0.1).timeout
		_send_player_list.rpc_id(id, player_info)
		_request_player_name.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	player_info.erase(id)
	emit_signal("peer_disconnected", id)
	emit_signal("player_list_updated")


func _on_connected_to_server() -> void:
	emit_signal("connected_to_server")


func _on_connection_failed() -> void:
	disconnect_net()
	emit_signal("connection_failed")


# ---------------------------------------------------------------------------
# RPCs for player name exchange
# ---------------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func _request_player_name() -> void:
	_submit_player_name.rpc_id(1, my_id(), _local_player_name())


@rpc("any_peer", "call_remote", "reliable")
func _submit_player_name(id: int, name: String) -> void:
	player_info[id] = { "name": name }
	emit_signal("player_list_updated")
	_broadcast_player_list()


@rpc("authority", "call_remote", "reliable")
func _send_player_list(info: Dictionary) -> void:
	player_info = info
	emit_signal("player_list_updated")


func _broadcast_player_list() -> void:
	for id in multiplayer.get_peers():
		_send_player_list.rpc_id(id, player_info)
