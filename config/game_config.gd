# game_config.gd
# Autoloaded as "GameConfig". Carries lobby choices into the arena scene.

extends Node

# Number of human players (used in solo mode; in multiplayer derived from Net.player_info)
var num_players: int = 1

# List of AI opponents. Each entry is a Dictionary: { "difficulty": int }
# difficulty: 0 = easy, 1 = medium, 2 = hard
var ai_list: Array = []

# Multiplayer: peer_id → spawn slot index (0-based).
# Populated by the host in arena.gd before any RPC, then sent to clients.
# Empty in solo mode.
var peer_slots: Dictionary = {}
