# lan_discovery.gd
# Autoloaded as "LanDiscovery".
# Host: broadcasts presence via UDP every BROADCAST_INTERVAL seconds.
# Client: listens for broadcasts and builds a list of discovered games.

extends Node

const BROADCAST_PORT     := 9999
const BROADCAST_INTERVAL := 1.0
const GAME_ID            := "TANKGAME"

# Discovered game entry: { "name": String, "ip": String, "port": int, "time": float }
signal games_updated(games: Array)

var discovered: Array = []   # Array of dicts

var _udp_broadcast: PacketPeerUDP = null  # host sends on this
var _udp_listen: PacketPeerUDP    = null  # client listens on this
var _broadcast_timer: float       = 0.0
var _broadcast_name: String       = ""
var _broadcast_port: int          = 0
var _is_broadcasting: bool        = false
var _is_listening: bool           = false

const STALE_TIMEOUT := 4.0   # remove a game if not seen for this many seconds


# ---------------------------------------------------------------------------
# Host API
# ---------------------------------------------------------------------------
func start_broadcast(game_name: String, game_port: int) -> void:
	_broadcast_name = game_name
	_broadcast_port = game_port
	_is_broadcasting = true
	_broadcast_timer = 0.0

	_udp_broadcast = PacketPeerUDP.new()
	_udp_broadcast.set_broadcast_enabled(true)
	_udp_broadcast.bind(0)   # OS picks source port


func stop_broadcast() -> void:
	_is_broadcasting = false
	if _udp_broadcast:
		_udp_broadcast.close()
		_udp_broadcast = null


# ---------------------------------------------------------------------------
# Client API
# ---------------------------------------------------------------------------
func start_listening() -> void:
	_is_listening = true
	discovered.clear()

	_udp_listen = PacketPeerUDP.new()
	# Allow multiple sockets on same port (for two instances on same machine)
	_udp_listen.bind(BROADCAST_PORT, "0.0.0.0")


func stop_listening() -> void:
	_is_listening = false
	if _udp_listen:
		_udp_listen.close()
		_udp_listen = null
	discovered.clear()


# ---------------------------------------------------------------------------
# Process
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _is_broadcasting:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_send_broadcast()

	if _is_listening:
		_poll_listen()
		_expire_stale(delta)


func _send_broadcast() -> void:
	var msg := "%s:%s:%d" % [GAME_ID, _broadcast_name, _broadcast_port]
	var bytes := msg.to_utf8_buffer()
	_udp_broadcast.set_dest_address("255.255.255.255", BROADCAST_PORT)
	_udp_broadcast.put_packet(bytes)


func _poll_listen() -> void:
	while _udp_listen.get_available_packet_count() > 0:
		var packet := _udp_listen.get_packet()
		var sender_ip := _udp_listen.get_packet_ip()
		var msg := packet.get_string_from_utf8()
		_parse_packet(msg, sender_ip)


func _parse_packet(msg: String, sender_ip: String) -> void:
	# Expected format: TANKGAME:<name>:<port>
	var parts := msg.split(":")
	if parts.size() < 3 or parts[0] != GAME_ID:
		return
	var game_name := parts[1]
	var game_port := parts[2].to_int()
	if game_port <= 0:
		return

	# Update existing or add new
	var found := false
	for entry in discovered:
		if entry["ip"] == sender_ip and entry["port"] == game_port:
			entry["time"] = 0.0   # reset stale timer
			found = true
			break

	if not found:
		discovered.append({
			"name": game_name,
			"ip":   sender_ip,
			"port": game_port,
			"time": 0.0
		})
		emit_signal("games_updated", discovered)


func _expire_stale(delta: float) -> void:
	var changed := false
	for entry in discovered:
		entry["time"] += delta
	var before := discovered.size()
	discovered = discovered.filter(func(e): return e["time"] < STALE_TIMEOUT)
	if discovered.size() != before:
		emit_signal("games_updated", discovered)
