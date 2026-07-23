extends Node

func _ready() -> void:
	Net.is_host = true
	Net.players = {
		1: {"peer_id": 1, "name": "Host"},
		10000: {"peer_id": 10000, "name": "デバッグ敵 1", "is_bot": true},
	}
	var weapon: Dictionary = {
		"id": "bot_weapon",
		"name": "Botの剣",
		"type": "weapon",
		"target": "enemy",
		"effect": "attack",
		"power": 7,
		"rarity": "common",
	}
	GameRules.new_match(Net.players.values(), [weapon], 12345)
	GameRules.state["turn"] = 1
	GameRules.state["players"]["10000"]["hand"] = [weapon]
	GameRules.state["deck"] = []
	Net._run_debug_bot_action(10000)
	assert(String(GameRules.state["phase"]) == "defense")
	assert(int(GameRules.state["pending_attack"]["attacker_peer_id"]) == 10000)
	assert(int(GameRules.state["pending_attack"]["target_peer_id"]) == 1)

	var armor: Dictionary = {
		"id": "bot_armor",
		"name": "Botの盾",
		"type": "armor",
		"target": "self",
		"effect": "guard",
		"power": 4,
	}
	GameRules.new_match(Net.players.values(), [weapon], 54321)
	GameRules.state["turn"] = 1
	GameRules.state["players"]["10000"]["hand"] = [armor]
	GameRules.state["players"]["10000"]["learned_miracles"] = []
	GameRules.state["deck"] = [weapon]
	Net._run_debug_bot_action(10000)
	assert(int(GameRules.state["players"]["10000"]["hand"].size()) == 2)
	assert(int(GameRules.state["turn"]) == 0)
	print("bot_smoke: PASS")
	Net.is_host = false
	Net.players.clear()
	GameRules.state.clear()
	get_tree().quit()
