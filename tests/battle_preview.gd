extends SceneTree

func _init() -> void:
	call_deferred("_render_preview")

func _render_preview() -> void:
	var battle: Control = load("res://scenes/battle_ui.tscn").instantiate()
	root.add_child(battle)
	var sample_cards: Array = [
		{"id": "1", "name": "石つぶて", "description": "燃える石が尾を引き、狙った相手へまっすぐ飛んでいく。長めのフレーバーテキスト表示確認用。", "type": "weapon", "target": "enemy", "effect": "attack", "power": 8, "attribute": "fire", "image_path": ""},
		{"id": "2", "name": "銀の剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 12, "attribute": "water", "image_path": ""},
		{"id": "3", "name": "木の盾", "type": "armor", "target": "self", "effect": "guard", "power": 10, "attribute": "water", "image_path": ""},
		{"id": "4", "name": "炎の盾", "type": "armor", "target": "self", "effect": "reflect", "power": 16, "attribute": "fire", "image_path": ""},
		{"id": "5", "name": "祝福の水", "type": "miracle", "target": "self", "effect": "heal", "power": 12, "attribute": "light", "image_path": ""},
		{"id": "6", "name": "鉄の槍", "type": "weapon", "target": "enemy", "effect": "attack", "power": 7, "attribute": "wood", "image_path": ""},
		{"id": "7", "name": "黒い鎧", "type": "armor", "target": "self", "effect": "guard", "power": 14, "attribute": "earth", "image_path": ""},
		{"id": "8", "name": "風の刃", "type": "weapon", "target": "enemy", "effect": "attack", "power": 9, "attribute": "light", "image_path": ""},
		{"id": "9", "name": "閃光", "type": "weapon", "target": "enemy", "effect": "attack", "power": 11, "attribute": "dark", "image_path": ""},
		{"id": "10", "name": "小盾", "type": "armor", "target": "self", "effect": "guard", "power": 5, "attribute": "none", "image_path": ""},
	]
	var learned_miracles: Array = [
		{"id": "m1", "name": "覚えた祝福", "description": "使用済みの奇跡", "type": "miracle", "target": "self", "effect": "heal", "power": 12, "image_path": ""},
		{"id": "m2", "name": "覚えた閃光", "description": "使用済みの奇跡", "type": "miracle", "target": "enemy", "effect": "attack", "power": 8, "image_path": ""},
	]
	var preview_attack: Dictionary = sample_cards[0].duplicate(true)
	preview_attack["power"] = 14
	var preview_defense: Dictionary = sample_cards[2].duplicate(true)
	preview_defense["power"] = 8
	var sample_state: Dictionary = {
		"turn": 0,
		"phase": "result",
		"player_order": [1, 2, 3],
		"pending_attack": {},
		"combat_view": {
			"status": "resolved",
			"attacker_peer_id": 1,
			"attacker_name": "うんち",
			"target_peer_id": 2,
			"target_name": "ペけねデヴ",
			"attack_card": preview_attack,
			"defense_cards": [preview_defense],
			"attack_power": 14,
			"defense_power": 8,
			"damage": 6,
		},
		"deck": [1, 2, 3, 4, 5],
		"players": {
			"1": {"peer_id": 1, "name": "うんち", "hp": 40, "alive": true, "hand": sample_cards, "learned_miracles": learned_miracles},
			"2": {"peer_id": 2, "name": "ペけねデヴ", "hp": 40, "alive": true, "hand": [], "learned_miracles": []},
			"3": {"peer_id": 3, "name": "友人その2", "hp": 31, "alive": true, "hand": [], "learned_miracles": []},
		},
		"log": ["ゲームを開始しました。", "うんちの番です。"],
	}
	battle.show_state(sample_state)
	await process_frame
	assert(is_equal_approx(
		battle.get_node("ResultPanel").position.x,
		battle.get_node("TargetStatus").position.x
	))
	await create_timer(0.45).timeout
	var image: Image = root.get_viewport().get_texture().get_image()
	var error: Error = image.save_png("res://tests/battle_preview.png")
	assert(error == OK)
	# 使用カードが増えた場合だけ、固定領域内でカード同士を重ねて表示する。
	sample_state["combat_view"]["attack_cards"] = [
		preview_attack,
		sample_cards[5],
		sample_cards[7],
		sample_cards[8],
	]
	sample_state["combat_view"]["attack_power"] = 41
	sample_state["combat_view"]["damage"] = 0
	sample_state["combat_view"]["defense_cards"] = [
		preview_defense,
		sample_cards[3],
		sample_cards[6],
		sample_cards[9],
	]
	sample_state["combat_view"]["defense_power"] = 43
	battle.show_state(sample_state)
	await create_timer(0.45).timeout
	var attack_cards_view: Control = battle.get_node("AttackCards")
	assert(attack_cards_view.get_child_count() == 4)
	assert(attack_cards_view.get_child(1).position.y < attack_cards_view.get_child(0).size.y)
	var defense_cards_view: Control = battle.get_node("DefenseCards")
	assert(defense_cards_view.get_child_count() == 4)
	assert(defense_cards_view.get_child(1).position.y < defense_cards_view.get_child(0).size.y)
	assert(not battle.get_node("CenterMessage").visible)
	assert(not battle.get_node("HoverDetailHeader").visible)
	image = root.get_viewport().get_texture().get_image()
	error = image.save_png("res://tests/battle_safe_preview.png")
	assert(error == OK)
	sample_state["combat_view"] = {
		"status": "action",
		"attacker_peer_id": 1,
		"attacker_name": "うんち",
		"target_peer_id": 1,
		"target_name": "うんち",
		"attack_card": sample_cards[4],
		"defense_cards": [],
		"attack_power": 12,
		"defense_power": 0,
		"damage": -1,
		"result_text": "HP +12",
		"arrow_direction": "right",
		"hide_arrow": true,
	}
	battle.show_state(sample_state)
	await process_frame
	assert(is_equal_approx(
		battle.get_node("ResultPanel").position.x,
		battle.get_node("OwnStatus").position.x
	))
	await create_timer(0.45).timeout
	image = root.get_viewport().get_texture().get_image()
	error = image.save_png("res://tests/battle_self_preview.png")
	assert(error == OK)
	sample_state["phase"] = "action"
	sample_state["pending_attack"] = {}
	sample_state["combat_view"] = {}
	battle.show_state(sample_state)
	battle._select_card(sample_cards[0])
	assert(battle.get_node("CardUseButton").visible)
	assert(is_equal_approx(battle.get_node("CardUseButton").position.x, 18.0))
	assert(not battle.get_node("ActionButton").visible)
	assert(not bool(battle.card_panels["hand:2"].get_meta("card_usable")))
	var disabled_armor_style: StyleBoxFlat = battle.card_panels["hand:2"].get_theme_stylebox("panel")
	assert(disabled_armor_style.bg_color.is_equal_approx(Color("#d5ddd9")))
	battle._show_hover_card(sample_cards[0])
	await process_frame
	await create_timer(0.45).timeout
	assert(battle.get_node("HoverCardDetail").visible)
	var hover_art: TextureRect = battle.get_node("HoverCardDetail/Margin/Row/Art")
	assert(is_equal_approx(hover_art.custom_minimum_size.x, hover_art.custom_minimum_size.y))
	var hand_art: TextureRect = battle.get_node("HandPanel/Margin/Scroll/Hand").get_child(0).get_child(0).get_child(0)
	assert(is_equal_approx(hand_art.custom_minimum_size.x, hand_art.custom_minimum_size.y))
	image = root.get_viewport().get_texture().get_image()
	error = image.save_png("res://tests/battle_hover_preview.png")
	assert(error == OK)
	var card_requests: Array = []
	battle.card_play_requested.connect(func(card_ids: Array, target_peer_id: int):
		card_requests.append([card_ids, target_peer_id])
	)
	battle.get_node("CardUseButton").pressed.emit()
	assert(card_requests.size() == 1)
	assert(card_requests[0][0] == ["1"])
	sample_state["phase"] = "defense"
	sample_state["pending_attack"] = {
		"attacker_peer_id": 2,
		"attacker_name": "ぺけねデヴ",
		"target_peer_id": 1,
		"target_name": "うんち",
		"power": 8,
		"attribute": "fire",
	}
	sample_state["combat_view"] = {
		"status": "defending",
		"attacker_peer_id": 2,
		"attacker_name": "ぺけねデヴ",
		"target_peer_id": 1,
		"target_name": "うんち",
		"attack_card": sample_cards[0],
		"defense_cards": [],
		"attack_power": 8,
		"defense_power": 0,
		"damage": 0,
	}
	battle.show_state(sample_state)
	assert(battle.get_node("CardUseButton").visible)
	assert(is_equal_approx(battle.get_node("CardUseButton").position.x, 420.0))
	assert(battle.get_node("CardUseButton").tooltip_text == "防具なしで受ける")
	assert(bool(battle.card_panels["hand:2"].get_meta("card_usable")))
	assert(not bool(battle.card_panels["hand:3"].get_meta("card_usable")))
	assert(not bool(battle.card_panels["hand:4"].get_meta("card_usable")))
	battle._select_card(sample_cards[3], battle.card_panels["hand:3"])
	assert(battle.selected_defense_cards.is_empty())
	var pass_requests: Array = []
	battle.pass_defense_requested.connect(func(): pass_requests.append(true))
	battle.get_node("CardUseButton").pressed.emit()
	assert(pass_requests.size() == 1)
	assert(not battle.get_node("PassDefenseButton").visible)
	var defense_requests: Array = []
	battle.defense_cards_requested.connect(func(card_ids: Array[String]):
		defense_requests.append(card_ids)
	)
	battle.selected_defense_cards.append(sample_cards[2])
	battle.get_node("CardUseButton").pressed.emit()
	assert(defense_requests.size() == 1)
	assert(defense_requests[0] == ["3"])

	# 攻撃・攻＋が1枚もない自分のターンだけ「祈る」を表示する。
	sample_state["phase"] = "action"
	sample_state["turn"] = 0
	sample_state["pending_attack"] = {}
	sample_state["combat_view"] = {}
	sample_state["players"]["1"]["hand"] = [sample_cards[4]]
	sample_state["players"]["1"]["learned_miracles"] = []
	battle.show_state(sample_state)
	assert(battle.get_node("ActionButton").visible)
	assert(String(battle.get_node("ActionButton").text).begins_with("祈る"))
	var pray_requests: Array = []
	battle.pray_requested.connect(func(): pray_requests.append(true))
	battle.get_node("ActionButton").pressed.emit()
	assert(pray_requests.size() == 1)

	# 「自分」対象の回復は選択直後は自分を向き、対象を選び直せば他人へ送れる。
	card_requests.clear()
	battle._select_card(sample_cards[4], battle.card_panels["hand:0"])
	assert(int(battle.selected_target_peer_id) == 1)
	battle._select_target(2)
	battle.get_node("CardUseButton").pressed.emit()
	assert(card_requests.size() == 1)
	assert(int(card_requests[0][1]) == 2)
	print("battle_preview: PASS")
	battle.free()
	quit()
