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

	var duplicate_buff: Dictionary = {
		"id": "bot_buff",
		"name": "Botの攻撃支援",
		"type": "weapon",
		"target": "enemy",
		"effect": "buff",
		"power": 2,
	}
	GameRules.new_match(Net.players.values(), [weapon], 23456)
	GameRules.state["turn"] = 1
	GameRules.state["players"]["10000"]["hand"] = [
		weapon,
		duplicate_buff.duplicate(true),
		duplicate_buff.duplicate(true),
	]
	GameRules.state["deck"] = []
	Net._run_debug_bot_action(10000)
	assert(String(GameRules.state["phase"]) == "defense")
	assert(int(GameRules.state["pending_attack"]["power"]) == 11)
	assert(int(GameRules.state["pending_attack"]["attack_cards"].size()) == 3)

	# Botの試行が拒否されても、同じ手番を再試行し続けず行動終了へフォールバックする。
	GameRules.new_match(Net.players.values(), [weapon], 34567)
	GameRules.state["turn"] = 1
	GameRules.state["players"]["10000"]["hand"] = [weapon]
	GameRules.state["deck"] = []
	Net._publish_debug_bot_result(10000, GameRules.state.duplicate(true))
	assert(int(GameRules.state["turn"]) == 0)

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

	# 死亡した前回ターゲットを保持せず、生存中の相手へ自動で切り替える。
	var battle: Control = load("res://scenes/battle_ui.tscn").instantiate()
	add_child(battle)
	battle.selected_target_peer_id = 2
	var ui_weapon: Dictionary = {
		"id": "ui_weapon", "name": "UIの剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5,
	}
	var ui_state: Dictionary = {
		"turn": 0,
		"phase": "action",
		"player_order": [1, 2, 3],
		"pending_attack": {},
		"combat_view": {},
		"deck": [],
		"players": {
			"1": {"peer_id": 1, "name": "Host", "hp": 40, "alive": true, "hand": [ui_weapon], "learned_miracles": []},
			"2": {"peer_id": 2, "name": "Dead", "hp": 0, "alive": false, "hand": [], "learned_miracles": []},
			"3": {"peer_id": 3, "name": "Alive", "hp": 40, "alive": true, "hand": [], "learned_miracles": []},
		},
	}
	battle.show_state(ui_state)
	assert(int(battle.selected_target_peer_id) == 3)
	var ui_card_panel: PanelContainer = battle.card_panels["hand:0"]
	assert(ui_card_panel.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(battle.get_node("ActionButton").visible)
	assert(String(battle.get_node("ActionButton").text) == "ターンを終了")
	battle.queue_free()

	print("bot_smoke: PASS")
	Net.is_host = false
	Net.players.clear()
	GameRules.state.clear()
	get_tree().quit()
