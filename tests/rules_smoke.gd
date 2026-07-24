extends SceneTree

func _init() -> void:
	var rules: Node = load("res://scripts/game_rules.gd").new()
	var players: Array = [
		{"peer_id": 1, "name": "Host"},
		{"peer_id": 2, "name": "Guest"},
	]
	var deck: Array = [
		{"id": "weapon", "name": "剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10, "rarity": "common"},
		{"id": "armor", "name": "盾", "type": "armor", "target": "self", "effect": "guard", "power": 4, "rarity": "common"},
	]
	rules.new_match(players, deck, 12345)
	assert(int(rules.state["players"]["1"]["hp"]) == 40)
	assert(int(rules.state["players"]["1"]["mp"]) == 20)
	assert(int(rules.state["players"]["1"]["gold"]) == 20)
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	var invalid_defense: Dictionary = {"id": "bad_weapon", "name": "防御不可の剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 99}
	rules.state["players"]["2"]["hand"] = [invalid_defense, deck[1].duplicate(true)]
	rules.state["deck"] = []

	var after_attack: Dictionary = rules.play_card(1, "weapon", 2)
	assert(after_attack["phase"] == "defense")
	assert(int(after_attack["players"]["2"]["hp"]) == 40)
	var rejected_defense: Dictionary = rules.play_defense_cards(2, ["bad_weapon"])
	assert(String(rejected_defense["phase"]) == "defense")
	assert(int(rejected_defense["players"]["2"]["hp"]) == 40)

	var after_defense: Dictionary = rules.play_card(2, "armor", 2)
	assert(after_defense["phase"] == "result")
	assert(int(after_defense["players"]["2"]["hp"]) == 34)
	assert(int(after_defense["combat_view"]["damage"]) == 6)
	assert(int(after_defense["combat_view"]["defense_cards"].size()) == 1)
	var after_result: Dictionary = rules.continue_after_result()
	assert(after_result["phase"] == "action")
	assert(int(after_result["turn"]) == 1)

	# 通常コストは指定リソースだけで支払い、不足時は選択・使用できない。
	rules.new_match(players, deck, 12346)
	var costly_weapon: Dictionary = {
		"id": "costly_weapon", "name": "MP剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5,
		"cost": {"resource": "mp", "amount": 21},
	}
	rules.state["players"]["1"]["hand"] = [costly_weapon]
	rules.state["deck"] = []
	var rejected_cost: Dictionary = rules.play_action_cards(1, ["costly_weapon"], 2)
	assert(String(rejected_cost["phase"]) == "action")
	assert(int(rejected_cost["players"]["1"]["mp"]) == 20)
	assert(int(rejected_cost["players"]["1"]["hp"]) == 40)
	assert(int(rejected_cost["players"]["1"]["hand"].size()) == 1)
	var prayer_with_unaffordable_attack: Dictionary = rules.pray(1)
	assert(int(prayer_with_unaffordable_attack["turn"]) == 1)

	# 支払い可能ならコストを引いて発動する。別リソースへの肩代わりはしない。
	rules.new_match(players, deck, 12347)
	costly_weapon["cost"]["amount"] = 20
	rules.state["players"]["1"]["hand"] = [costly_weapon]
	rules.state["deck"] = []
	var paid_attack: Dictionary = rules.play_action_cards(1, ["costly_weapon"], 2)
	assert(String(paid_attack["phase"]) == "defense")
	assert(int(paid_attack["players"]["1"]["mp"]) == 0)
	assert(int(paid_attack["players"]["1"]["hp"]) == 40)

	# HPちょうどのコストも支払い可能。攻撃解決後に使用者が脱落する。
	rules.new_match(players, deck, 12348)
	var lethal_cost_weapon: Dictionary = {
		"id": "lethal_cost", "name": "命の一撃", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5,
		"cost": {"resource": "hp", "amount": 5},
	}
	rules.state["players"]["1"]["hp"] = 5
	rules.state["players"]["1"]["hand"] = [lethal_cost_weapon]
	rules.state["deck"] = []
	rules.play_action_cards(1, ["lethal_cost"], 2)
	assert(int(rules.state["players"]["1"]["hp"]) == 0)
	assert(bool(rules.state["players"]["1"]["alive"]))
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 35)
	assert(not bool(rules.state["players"]["1"]["alive"]))

	# 自己回復カードでも、HPコストで0になった使用者は回復せず脱落する。
	rules.new_match(players, deck, 12349)
	var lethal_cost_heal: Dictionary = {
		"id": "lethal_heal", "name": "命の回復", "type": "special",
		"target": "self", "effect": "heal", "power": 20,
		"cost": {"resource": "hp", "amount": 5},
	}
	rules.state["players"]["1"]["hp"] = 5
	rules.state["players"]["1"]["hand"] = [lethal_cost_heal]
	rules.state["deck"] = []
	var lethal_heal_result: Dictionary = rules.play_action_cards(1, ["lethal_heal"], 1)
	assert(String(lethal_heal_result["phase"]) == "result")
	assert(int(lethal_heal_result["players"]["1"]["hp"]) == 0)
	assert(not bool(lethal_heal_result["players"]["1"]["alive"]))

	# 防具にも使用コストを適用する。
	rules.new_match(players, deck, 12350)
	var basic_cost_attack: Dictionary = {
		"id": "cost_attack", "name": "剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 10,
	}
	var costly_armor: Dictionary = {
		"id": "cost_armor", "name": "金の盾", "type": "armor",
		"target": "self", "effect": "guard", "power": 10,
		"cost": {"resource": "gold", "amount": 21},
	}
	rules.state["players"]["1"]["hand"] = [basic_cost_attack]
	rules.state["players"]["2"]["hand"] = [costly_armor]
	rules.state["deck"] = []
	rules.play_action_cards(1, ["cost_attack"], 2)
	var rejected_armor: Dictionary = rules.play_defense_cards(2, ["cost_armor"])
	assert(String(rejected_armor["phase"]) == "defense")
	assert(int(rejected_armor["players"]["2"]["gold"]) == 20)
	costly_armor["cost"]["amount"] = 20
	rules.state["players"]["2"]["hand"] = [costly_armor]
	var paid_armor: Dictionary = rules.play_defense_cards(2, ["cost_armor"])
	assert(String(paid_armor["phase"]) == "result")
	assert(int(paid_armor["players"]["2"]["gold"]) == 0)
	assert(int(paid_armor["players"]["2"]["hp"]) == 40)

	rules.new_match(players, deck, 12349)
	rules.state["turn"] = 1
	var miracle: Dictionary = {"id": "miracle", "name": "祝福", "type": "miracle", "target": "self", "effect": "heal", "power": 3}
	rules.state["players"]["2"]["hand"] = [miracle]
	rules.state["deck"] = []
	for miracle_draw_index: int in range(12):
		var miracle_draw_card: Dictionary = deck[0].duplicate(true)
		miracle_draw_card["id"] = "miracle_draw_%d" % miracle_draw_index
		rules.state["deck"].append(miracle_draw_card)
	rules.state["players"]["2"]["hp"] = 30
	var after_miracle: Dictionary = rules.play_card(2, "miracle", 2)
	assert(int(after_miracle["players"]["2"]["learned_miracles"].size()) == 1)
	assert(String(after_miracle["players"]["2"]["learned_miracles"][0]["id"]) == "miracle")
	assert(rules._owned_card_count(after_miracle["players"]["2"]) == 10)
	assert(bool(after_miracle["combat_view"]["hide_arrow"]))
	rules.continue_after_result()
	rules.state["turn"] = 1
	var after_reuse: Dictionary = rules.play_card(2, "miracle", 2)
	assert(int(after_reuse["players"]["2"]["hp"]) == 36)
	assert(int(after_reuse["players"]["2"]["learned_miracles"].size()) == 1)
	assert(rules._owned_card_count(after_reuse["players"]["2"]) == 11)

	# 攻撃・攻＋が無い時は祈って1枚引ける。攻＋も攻撃カードと同様に祈りを禁止する。
	rules.new_match(players, deck, 4242)
	var support_only: Dictionary = {"id": "support_only", "name": "休憩", "type": "special", "target": "self", "effect": "heal", "power": 2}
	var prayer_draw: Dictionary = {"id": "prayer_draw", "name": "祈りの成果", "type": "weapon", "target": "enemy", "effect": "attack", "power": 3}
	rules.state["players"]["1"]["hand"] = [support_only]
	rules.state["players"]["1"]["learned_miracles"] = []
	rules.state["deck"] = [prayer_draw]
	var after_prayer: Dictionary = rules.pray(1)
	assert(int(after_prayer["players"]["1"]["hand"].size()) == 2)
	assert(int(after_prayer["turn"]) == 1)

	rules.new_match(players, deck, 4343)
	var prayer_blocking_buff: Dictionary = {"id": "prayer_buff", "name": "攻撃支援", "type": "weapon", "target": "enemy", "effect": "buff", "power": 2}
	rules.state["players"]["1"]["hand"] = [prayer_blocking_buff]
	rules.state["players"]["1"]["learned_miracles"] = []
	rules.state["deck"] = [prayer_draw]
	var rejected_prayer: Dictionary = rules.pray(1)
	assert(int(rejected_prayer["players"]["1"]["hand"].size()) == 1)
	assert(int(rejected_prayer["turn"]) == 0)

	# 山札の複製は同じカードIDを持つ。同一IDの攻＋も所持枚数までは同時使用できる。
	rules.new_match(players, deck, 4344)
	var duplicate_weapon: Dictionary = {
		"id": "duplicate_weapon", "name": "剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5,
	}
	var duplicate_buff: Dictionary = {
		"id": "duplicate_buff", "name": "攻撃支援", "type": "weapon",
		"target": "enemy", "effect": "buff", "power": 2,
	}
	rules.state["players"]["1"]["hand"] = [
		duplicate_weapon,
		duplicate_buff.duplicate(true),
		duplicate_buff.duplicate(true),
	]
	rules.state["deck"] = []
	var duplicate_combo: Dictionary = rules.play_action_cards(
		1,
		["duplicate_weapon", "duplicate_buff", "duplicate_buff"],
		2
	)
	assert(String(duplicate_combo["phase"]) == "defense")
	assert(int(duplicate_combo["pending_attack"]["power"]) == 9)
	assert(int(duplicate_combo["pending_attack"]["attack_cards"].size()) == 3)

	# 通常手札＋習得済み奇跡は18枚が上限。上限でも祈り自体はターン終了として成立する。
	rules.new_match(players, deck, 4444)
	var full_hand: Array = []
	for prayer_index: int in range(18):
		full_hand.append({
			"id": "support_%d" % prayer_index,
			"name": "補助",
			"type": "special",
			"target": "self",
			"effect": "heal",
			"power": 1,
		})
	rules.state["players"]["1"]["hand"] = full_hand
	rules.state["players"]["1"]["learned_miracles"] = []
	rules.state["deck"] = [prayer_draw]
	var capped_prayer: Dictionary = rules.pray(1)
	assert(rules._owned_card_count(capped_prayer["players"]["1"]) == 18)
	assert(int(capped_prayer["turn"]) == 1)

	rules.new_match(players, deck, 4545)
	var capped_miracle: Dictionary = {"id": "capped_miracle", "name": "満杯の奇跡", "type": "miracle", "target": "self", "effect": "heal", "power": 1}
	rules.state["players"]["1"]["hand"] = full_hand.slice(0, 17)
	rules.state["players"]["1"]["learned_miracles"] = [capped_miracle]
	rules.state["deck"] = [prayer_draw]
	var after_capped_miracle: Dictionary = rules.play_card(1, "capped_miracle", 1)
	assert(rules._owned_card_count(after_capped_miracle["players"]["1"]) == 18)

	rules.new_match(players, deck, 54321)
	var armor_two: Dictionary = {"id": "armor_two", "name": "小盾", "type": "armor", "target": "self", "effect": "guard", "power": 6}
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["players"]["2"]["hand"] = [deck[1].duplicate(true), armor_two]
	rules.state["deck"] = []
	rules.play_card(1, "weapon", 2)
	var safe_result: Dictionary = rules.play_defense_cards(2, ["armor", "armor_two"])
	assert(int(safe_result["combat_view"]["damage"]) == 0)
	assert(int(safe_result["combat_view"]["defense_power"]) == 10)
	assert(int(safe_result["combat_view"]["defense_cards"].size()) == 2)

	rules.new_match(players, deck, 98765)
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["deck"] = []
	var self_attack: Dictionary = rules.play_card(1, "weapon", 1)
	assert(String(self_attack["phase"]) == "result")
	assert(int(self_attack["players"]["1"]["hp"]) == 30)
	assert(String(self_attack["combat_view"]["arrow_direction"]) == "left")
	assert(int(self_attack["combat_view"]["defense_cards"].size()) == 0)

	# HP が尽きたら game_over になり勝者が決まること。
	rules.new_match(players, deck, 13579)
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["players"]["2"]["hp"] = 5
	rules.state["deck"] = []
	rules.play_card(1, "weapon", 2)
	rules.pass_defense(2)
	assert(not bool(rules.state["players"]["2"]["alive"]))
	var game_over_state: Dictionary = rules.continue_after_result()
	assert(String(game_over_state["phase"]) == "game_over")
	assert(String(game_over_state["winner_name"]) == "Host")

	# 切断されたプレイヤーの番でもゲームが止まらないこと。
	rules.new_match([
		{"peer_id": 1, "name": "Host"},
		{"peer_id": 2, "name": "Guest"},
		{"peer_id": 3, "name": "Guest2"},
	], deck, 11111)
	var dropped: Dictionary = rules.drop_player(1)
	assert(not bool(dropped["players"]["1"]["alive"]))
	assert(String(dropped["phase"]) == "action")
	assert(int(dropped["turn"]) != 0)

	var fire_with_water: Dictionary = _attribute_battle(rules, players, "fire", ["water"])
	assert(int(fire_with_water["combat_view"]["damage"]) == 6)
	assert(String(fire_with_water["combat_view"]["defense_attribute"]) == "water")
	var fire_with_fire: Dictionary = _attribute_battle(rules, players, "fire", ["fire"])
	assert(String(fire_with_fire["phase"]) == "defense")
	assert(int(fire_with_fire["players"]["2"]["hp"]) == 40)
	assert(int(fire_with_fire["players"]["2"]["hand"].size()) == 1)
	var fire_with_light: Dictionary = _attribute_battle(rules, players, "fire", ["light"])
	assert(int(fire_with_light["combat_view"]["damage"]) == 6)
	var wood_with_earth: Dictionary = _attribute_battle(rules, players, "wood", ["earth"])
	assert(int(wood_with_earth["combat_view"]["damage"]) == 6)
	var mixed_defense: Dictionary = _attribute_battle(rules, players, "fire", ["water", "light"])
	assert(String(mixed_defense["combat_view"]["defense_attribute"]) == "mixed")
	assert(int(mixed_defense["combat_view"]["defense_power"]) == 8)
	assert(int(mixed_defense["combat_view"]["damage"]) == 2)
	var light_attack: Dictionary = _attribute_battle(rules, players, "light", ["water"])
	assert(String(light_attack["phase"]) == "defense")
	assert(int(light_attack["players"]["2"]["hand"].size()) == 1)
	var none_attack: Dictionary = _attribute_battle(rules, players, "none", ["fire"])
	assert(int(none_attack["combat_view"]["damage"]) == 6)
	var dark_attack: Dictionary = _attribute_battle(rules, players, "dark", ["water"])
	assert(int(dark_attack["combat_view"]["damage"]) == 40)
	assert(int(dark_attack["players"]["2"]["hp"]) == 0)
	var blocked_dark: Dictionary = _attribute_battle(rules, players, "dark", ["water"], 4)
	assert(int(blocked_dark["combat_view"]["damage"]) == 0)
	assert(int(blocked_dark["players"]["2"]["hp"]) == 40)

	# 属性消しは光・闇を無属性化し、同時に出した任意属性の防具も有効にする。
	rules.new_match(players, deck, 20260729)
	var light_special_attack: Dictionary = {
		"id": "light_special", "name": "光撃", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 10, "attribute": "light",
	}
	var erase_armor: Dictionary = {
		"id": "erase_armor", "name": "属性消し", "type": "armor",
		"target": "self", "effect": "guard", "power": 4, "attribute": "fire",
		"special_effect": "attribute_erase",
	}
	var extra_armor: Dictionary = {
		"id": "extra_armor", "name": "追加防具", "type": "armor",
		"target": "self", "effect": "guard", "power": 3, "attribute": "fire",
	}
	rules.state["players"]["1"]["hand"] = [light_special_attack]
	rules.state["players"]["2"]["hand"] = [erase_armor, extra_armor]
	rules.state["deck"] = []
	rules.play_card(1, "light_special", 2)
	var erased_light: Dictionary = rules.play_defense_cards(
		2,
		["erase_armor", "extra_armor"]
	)
	assert(String(erased_light["combat_view"]["attack_attribute"]) == "none")
	assert(int(erased_light["combat_view"]["defense_power"]) == 7)
	assert(int(erased_light["combat_view"]["damage"]) == 3)
	rules.new_match(players, deck, 20260730)
	var dark_special_attack: Dictionary = light_special_attack.duplicate(true)
	dark_special_attack["id"] = "dark_special"
	dark_special_attack["attribute"] = "dark"
	rules.state["players"]["1"]["hand"] = [dark_special_attack]
	rules.state["players"]["2"]["hand"] = [erase_armor]
	rules.state["deck"] = []
	rules.play_card(1, "dark_special", 2)
	var erased_dark: Dictionary = rules.play_defense_cards(2, ["erase_armor"])
	assert(int(erased_dark["combat_view"]["damage"]) == 6)
	assert(int(erased_dark["players"]["2"]["hp"]) == 34)

	# 攻撃＋攻撃アップを2枚重ねて出すと、威力が合算される。
	rules.new_match(players, deck, 20260723)
	var buff_card: Dictionary = {"id": "buff", "name": "力の秘薬", "type": "weapon", "target": "enemy", "effect": "buff", "power": 5, "attribute": "water"}
	var buff_weapon: Dictionary = {"id": "bw", "name": "剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10, "attribute": "fire"}
	rules.state["players"]["1"]["hand"] = [buff_card.duplicate(true), buff_weapon.duplicate(true)]
	rules.state["deck"] = []
	var combined: Dictionary = rules.play_action_cards(1, ["bw", "buff"], 2)
	assert(String(combined["phase"]) == "defense")
	assert(int(combined["pending_attack"]["power"]) == 15)
	assert(String(combined["pending_attack"]["attribute"]) == "none")
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 25)

	# 攻撃セットは奇跡だけなら奇跡扱い。通常カードが1枚でも混ざれば通常扱い。
	rules.new_match(players, deck, 20260724)
	var miracle_weapon: Dictionary = {
		"id": "miracle_weapon", "name": "奇跡の剣", "type": "miracle",
		"target": "enemy", "effect": "attack", "power": 4,
	}
	var miracle_buff: Dictionary = {
		"id": "miracle_buff", "name": "奇跡の後押し", "type": "miracle",
		"target": "enemy", "effect": "buff", "power": 2,
	}
	rules.state["players"]["1"]["hand"] = [
		miracle_weapon.duplicate(true),
		buff_card.duplicate(true),
	]
	rules.state["deck"] = []
	var mixed_attack: Dictionary = rules.play_action_cards(1, ["miracle_weapon", "buff"], 2)
	assert(not bool(mixed_attack["pending_attack"]["is_miracle"]))
	rules.new_match(players, deck, 20260724)
	rules.state["players"]["1"]["hand"] = [
		miracle_weapon.duplicate(true),
		miracle_buff.duplicate(true),
	]
	rules.state["deck"] = []
	var pure_miracle_attack: Dictionary = rules.play_action_cards(
		1,
		["miracle_weapon", "miracle_buff"],
		2
	)
	assert(bool(pure_miracle_attack["pending_attack"]["is_miracle"]))

	# 攻撃力倍はセット全体へ乗算し、複数枚なら重ねた枚数ぶん倍化する。
	rules.new_match(players, deck, 20260726)
	var double_weapon: Dictionary = {
		"id": "double_weapon", "name": "倍の剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5,
		"special_effect": "double_power",
	}
	var double_buff: Dictionary = {
		"id": "double_buff", "name": "倍の加護", "type": "weapon",
		"target": "enemy", "effect": "buff", "power": 5,
		"special_effect": "double_power",
	}
	rules.state["players"]["1"]["hand"] = [double_weapon, double_buff]
	rules.state["deck"] = []
	var quadrupled_attack: Dictionary = rules.play_action_cards(
		1,
		["double_weapon", "double_buff"],
		2
	)
	assert(int(quadrupled_attack["pending_attack"]["power"]) == 40)

	# 属性変更は発動したカードだけが有効で、後に出したカードが優先される。
	rules.new_match(players, deck, 20260727)
	var base_attack: Dictionary = {
		"id": "base_attack", "name": "火の剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5, "attribute": "fire",
	}
	var earth_change: Dictionary = {
		"id": "earth_change", "name": "土変更", "type": "weapon",
		"target": "enemy", "effect": "buff", "power": 2, "attribute": "none",
		"special_effect": "attribute_change", "special_attribute": "earth",
	}
	var water_change: Dictionary = {
		"id": "water_change", "name": "水変更", "type": "weapon",
		"target": "enemy", "effect": "buff", "power": 2, "attribute": "none",
		"special_effect": "attribute_change", "special_attribute": "water",
	}
	rules.state["players"]["1"]["hand"] = [base_attack, earth_change, water_change]
	rules.state["deck"] = []
	var changed_attack: Dictionary = rules.play_action_cards(
		1,
		["base_attack", "earth_change", "water_change"],
		2
	)
	assert(String(changed_attack["pending_attack"]["attribute"]) == "water")
	rules.new_match(players, deck, 20260728)
	var failed_double: Dictionary = double_buff.duplicate(true)
	failed_double["id"] = "failed_double"
	failed_double["chance"] = 0
	rules.state["players"]["1"]["hand"] = [base_attack.duplicate(true), failed_double]
	rules.state["deck"] = []
	var failed_special_attack: Dictionary = rules.play_action_cards(
		1,
		["base_attack", "failed_double"],
		2
	)
	assert(int(failed_special_attack["pending_attack"]["power"]) == 5)

	# 2回攻撃は1枚につき追加1回。追加攻撃からは再増殖せず、攻撃ごとに防御を挟む。
	rules.new_match(players, deck, 20260729)
	var repeat_weapon: Dictionary = {
		"id": "repeat_weapon", "name": "連撃剣", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 5,
		"special_effect": "double_attack",
	}
	rules.state["players"]["1"]["hand"] = [repeat_weapon]
	rules.state["deck"] = []
	rules.play_action_cards(1, ["repeat_weapon"], 2)
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 35)
	rules.continue_after_result()
	assert(String(rules.state["phase"]) == "defense")
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 30)
	var repeat_done: Dictionary = rules.continue_after_result()
	assert(String(repeat_done["phase"]) == "action")
	assert(int(repeat_done["turn"]) == 1)

	# 2枚重ねると合計3回で止まる。
	rules.new_match(players, deck, 20260730)
	var repeat_buff: Dictionary = {
		"id": "repeat_buff", "name": "追撃加護", "type": "weapon",
		"target": "enemy", "effect": "buff", "power": 0,
		"special_effect": "double_attack",
	}
	rules.state["players"]["1"]["hand"] = [repeat_weapon, repeat_buff]
	rules.state["deck"] = []
	rules.play_action_cards(1, ["repeat_weapon", "repeat_buff"], 2)
	for strike_index: int in range(3):
		assert(String(rules.state["phase"]) == "defense")
		rules.pass_defense(2)
		if strike_index < 2:
			rules.continue_after_result()
	assert(int(rules.state["players"]["2"]["hp"]) == 25)
	rules.continue_after_result()
	assert(int(rules.state["turn"]) == 1)

	# 全体2回攻撃は全対象を1周したあと、同じ対象列をもう1周する。
	var repeat_players: Array = players.duplicate(true)
	repeat_players.append({"peer_id": 3, "name": "Third"})
	rules.new_match(repeat_players, deck, 20260732)
	var repeat_all: Dictionary = repeat_weapon.duplicate(true)
	repeat_all["id"] = "repeat_all"
	repeat_all["target"] = "all_enemies"
	rules.state["players"]["1"]["hand"] = [repeat_all]
	rules.state["deck"] = []
	rules.play_action_cards(1, ["repeat_all"], 2)
	for global_strike: int in range(4):
		assert(String(rules.state["phase"]) == "defense")
		var defending_peer: int = int(rules.state["pending_attack"]["target_peer_id"])
		rules.pass_defense(defending_peer)
		if global_strike < 3:
			rules.continue_after_result()
	assert(int(rules.state["players"]["2"]["hp"]) == 30)
	assert(int(rules.state["players"]["3"]["hp"]) == 30)
	rules.continue_after_result()
	assert(int(rules.state["turn"]) == 1)

	# 光は攻撃の属性合成ではワイルドカード。他属性と重ねると、その属性になる。
	assert(rules._combined_offensive_attribute([
		{"attribute": "light"},
		{"attribute": "fire"},
	]) == "fire")
	assert(rules._combined_offensive_attribute([
		{"attribute": "water"},
		{"attribute": "light"},
	]) == "water")
	assert(rules._combined_offensive_attribute([
		{"attribute": "light"},
		{"attribute": "light"},
	]) == "light")
	assert(rules._combined_offensive_attribute([
		{"attribute": "fire"},
		{"attribute": "light"},
		{"attribute": "water"},
	]) == "none")

	rules.new_match(players, deck, 20260726)
	var light_weapon: Dictionary = {"id": "light_weapon", "name": "光剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10, "attribute": "light"}
	var fire_buff: Dictionary = {"id": "fire_buff", "name": "火の加護", "type": "weapon", "target": "enemy", "effect": "buff", "power": 5, "attribute": "fire"}
	rules.state["players"]["1"]["hand"] = [light_weapon, fire_buff]
	rules.state["deck"] = []
	var light_wildcard_attack: Dictionary = rules.play_action_cards(1, ["light_weapon", "fire_buff"], 2)
	assert(String(light_wildcard_attack["pending_attack"]["attribute"]) == "fire")

	# 攻撃アップは単独でも攻撃カードとして使える。
	rules.new_match(players, deck, 20260724)
	rules.state["players"]["1"]["hand"] = [buff_card.duplicate(true)]
	rules.state["deck"] = []
	var buff_alone: Dictionary = rules.play_action_cards(1, ["buff"], 2)
	assert(String(buff_alone["phase"]) == "defense")
	assert(int(buff_alone["pending_attack"]["power"]) == 5)
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 35)

	# 攻撃カードは1回の攻撃に1枚まで。2枚重ねようとすると弾かれ、何も消費しない。
	rules.new_match(players, deck, 20260725)
	var weapon_b: Dictionary = {"id": "bw2", "name": "剣2", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10}
	rules.state["players"]["1"]["hand"] = [buff_weapon.duplicate(true), weapon_b.duplicate(true)]
	rules.state["deck"] = []
	var two_attacks: Dictionary = rules.play_action_cards(1, ["bw", "bw2"], 2)
	assert(String(two_attacks["phase"]) == "action")
	assert(int(rules.state["players"]["1"]["hand"].size()) == 2)

	# 敵全体攻撃には攻撃アップを重ねられない。弾かれたセットは何も消費しない。
	var trio: Array = [
		{"peer_id": 1, "name": "A"},
		{"peer_id": 2, "name": "B"},
		{"peer_id": 3, "name": "C"},
	]
	rules.new_match(trio, deck, 111)
	var all_card: Dictionary = {"id": "all", "name": "嵐", "type": "weapon", "target": "all_enemies", "effect": "attack", "power": 6}
	var all_buff: Dictionary = {"id": "abuff", "name": "強風", "type": "weapon", "target": "all_enemies", "effect": "buff", "power": 4}
	rules.state["players"]["1"]["hand"] = [all_card.duplicate(true), all_buff.duplicate(true)]
	rules.state["deck"] = []
	var rejected_all_buff: Dictionary = rules.play_action_cards(1, ["all", "abuff"], 0)
	assert(String(rejected_all_buff["phase"]) == "action")
	assert(int(rejected_all_buff["players"]["1"]["hand"].size()) == 2)
	var rejected_buff_alone: Dictionary = rules.play_action_cards(1, ["abuff"], 0)
	assert(String(rejected_buff_alone["phase"]) == "action")
	assert(int(rejected_buff_alone["players"]["1"]["hand"].size()) == 2)
	var all_started: Dictionary = rules.play_action_cards(1, ["all"], 0)
	assert(String(all_started["phase"]) == "defense")
	assert(int(all_started["pending_attack"]["target_peer_id"]) == 2)
	assert(int(all_started["pending_attack"]["power"]) == 6)
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 34)
	var next_target: Dictionary = rules.continue_after_result()
	assert(String(next_target["phase"]) == "defense")
	assert(int(next_target["pending_attack"]["target_peer_id"]) == 3)
	rules.pass_defense(3)
	assert(int(rules.state["players"]["3"]["hp"]) == 34)
	var all_done: Dictionary = rules.continue_after_result()
	assert(String(all_done["phase"]) == "action")
	assert(int(all_done["turn"]) == 1)

	# 攻＋は（全）攻撃にも使用不可。使用者自身への（全）攻撃は防御なしで即座に解決する。
	rules.new_match(players, deck, 112)
	var everyone_attack: Dictionary = {
		"id": "everyone_attack", "name": "無差別攻撃", "type": "weapon",
		"target": "all_players", "effect": "attack", "power": 5,
	}
	var everyone_buff: Dictionary = {
		"id": "everyone_buff", "name": "無差別強化", "type": "weapon",
		"target": "all_players", "effect": "buff", "power": 3,
	}
	rules.state["players"]["1"]["hand"] = [
		everyone_attack.duplicate(true),
		everyone_buff.duplicate(true),
	]
	rules.state["deck"] = []
	var rejected_everyone_buff: Dictionary = rules.play_action_cards(
		1,
		["everyone_attack", "everyone_buff"],
		0
	)
	assert(String(rejected_everyone_buff["phase"]) == "action")
	assert(int(rejected_everyone_buff["players"]["1"]["hand"].size()) == 2)
	var everyone_started: Dictionary = rules.play_action_cards(1, ["everyone_attack"], 0)
	assert(String(everyone_started["phase"]) == "result")
	assert(int(everyone_started["players"]["1"]["hp"]) == 35)
	assert(int(everyone_started["combat_view"]["defense_cards"].size()) == 0)
	var everyone_other_pending: Dictionary = rules.continue_after_result()
	assert(String(everyone_other_pending["phase"]) == "defense")
	assert(int(everyone_other_pending["pending_attack"]["target_peer_id"]) == 2)
	rules.pass_defense(2)
	var everyone_done: Dictionary = rules.continue_after_result()
	assert(int(everyone_done["players"]["2"]["hp"]) == 35)
	assert(String(everyone_done["phase"]) == "action")

	# 全体回復は、自分を含む生存者全員を最大HPまでの範囲で回復する。
	rules.new_match(trio, deck, 222)
	var all_heal: Dictionary = {
		"id": "all_heal",
		"name": "恵みの雨",
		"type": "miracle",
		"target": "all_players",
		"effect": "heal",
		"power": 5,
	}
	rules.state["players"]["1"]["hp"] = 30
	rules.state["players"]["2"]["hp"] = 98
	rules.state["players"]["3"]["hp"] = 0
	rules.state["players"]["3"]["alive"] = false
	rules.state["players"]["1"]["hand"] = [all_heal]
	rules.state["deck"] = []
	var healed_everyone: Dictionary = rules.play_card(1, "all_heal", 0)
	assert(String(healed_everyone["phase"]) == "result")
	assert(int(healed_everyone["players"]["1"]["hp"]) == 35)
	assert(int(healed_everyone["players"]["2"]["hp"]) == 98)
	assert(int(healed_everyone["players"]["3"]["hp"]) == 0)
	assert(String(healed_everyone["combat_view"]["result_text"]).ends_with("HP +5"))
	assert(int(healed_everyone["combat_view"]["target_peer_id"]) == 1)
	var second_heal_target: Dictionary = rules.continue_after_result()
	assert(String(second_heal_target["phase"]) == "defense")
	assert(int(second_heal_target["pending_attack"]["target_peer_id"]) == 2)
	var second_heal_result: Dictionary = rules.pass_defense(2)
	assert(int(second_heal_result["players"]["2"]["hp"]) == 99)
	var all_heal_done: Dictionary = rules.continue_after_result()
	assert(String(all_heal_done["phase"]) == "action")

	# （全）の途中で使用者が倒れても全対象の処理を完了し、最後に勝敗判定する。
	rules.new_match(players, deck, 223)
	var all_death: Dictionary = {
		"id": "all_death",
		"name": "全滅",
		"type": "special",
		"target": "all_players",
		"effect": "instant_death",
		"power": 0,
	}
	rules.state["players"]["1"]["hand"] = [all_death]
	rules.state["players"]["2"]["hand"] = []
	rules.state["deck"] = []
	var first_all_death: Dictionary = rules.play_card(1, "all_death", 0)
	assert(int(first_all_death["players"]["1"]["hp"]) == 0)
	assert(String(first_all_death["phase"]) == "result")
	var second_all_death_pending: Dictionary = rules.continue_after_result()
	assert(String(second_all_death_pending["phase"]) == "defense")
	assert(int(second_all_death_pending["pending_attack"]["target_peer_id"]) == 2)
	rules.pass_defense(2)
	var all_death_done: Dictionary = rules.continue_after_result()
	assert(int(all_death_done["players"]["2"]["hp"]) == 0)
	assert(String(all_death_done["phase"]) == "game_over")
	assert(String(all_death_done.get("winner_name", "")) == "")

	# 「全」は効果を問わず敵全員へ適用する。
	rules.new_match(trio, deck, 224)
	var enemy_all_death: Dictionary = {
		"id": "enemy_all_death",
		"name": "敵だけ全滅",
		"type": "special",
		"target": "all_enemies",
		"effect": "instant_death",
		"power": 0,
	}
	rules.state["players"]["1"]["hand"] = [enemy_all_death]
	rules.state["players"]["2"]["hand"] = []
	rules.state["players"]["3"]["hand"] = []
	rules.state["deck"] = []
	var enemy_all_first: Dictionary = rules.play_card(1, "enemy_all_death", 0)
	assert(String(enemy_all_first["phase"]) == "defense")
	assert(int(enemy_all_first["pending_attack"]["target_peer_id"]) == 2)
	rules.pass_defense(2)
	var enemy_all_second: Dictionary = rules.continue_after_result()
	assert(int(enemy_all_second["pending_attack"]["target_peer_id"]) == 3)
	rules.pass_defense(3)
	var enemy_all_done: Dictionary = rules.continue_after_result()
	assert(int(enemy_all_done["players"]["1"]["hp"]) == 40)
	assert(int(enemy_all_done["players"]["2"]["hp"]) == 0)
	assert(int(enemy_all_done["players"]["3"]["hp"]) == 0)
	assert(String(enemy_all_done["phase"]) == "game_over")
	assert(String(enemy_all_done["winner_name"]) == "A")

	# 回復の負数はダメージになる。HPは0未満にならず、倒れたプレイヤーも更新される。
	rules.new_match(trio, deck, 333)
	var all_damage_heal: Dictionary = {
		"id": "all_damage_heal",
		"name": "痛い雨",
		"type": "miracle",
		"target": "all_players",
		"effect": "heal",
		"power": -6,
	}
	rules.state["players"]["1"]["hp"] = 10
	rules.state["players"]["2"]["hp"] = 4
	rules.state["players"]["3"]["hp"] = 20
	rules.state["players"]["1"]["hand"] = [all_damage_heal]
	rules.state["deck"] = []
	var damaged_everyone: Dictionary = rules.play_card(1, "all_damage_heal", 0)
	assert(int(damaged_everyone["players"]["1"]["hp"]) == 4)
	assert(int(damaged_everyone["players"]["2"]["hp"]) == 4)
	assert(String(damaged_everyone["combat_view"]["result_text"]).ends_with("HP -6"))
	rules.continue_after_result()
	var damaged_second: Dictionary = rules.pass_defense(2)
	assert(int(damaged_second["players"]["2"]["hp"]) == 0)
	assert(not bool(damaged_second["players"]["2"]["alive"]))
	rules.continue_after_result()
	var damaged_third: Dictionary = rules.pass_defense(3)
	assert(int(damaged_third["players"]["3"]["hp"]) == 14)
	rules.continue_after_result()

	# 自分対象の回復も他人を選べる。通常防具は使えず、全反射だけが使用者へ返す。
	rules.new_match(players, deck, 334)
	var targeted_heal: Dictionary = {"id": "targeted_heal", "name": "他人への祝福", "type": "miracle", "target": "self", "effect": "heal", "power": 5}
	var normal_guard: Dictionary = {"id": "normal_guard", "name": "普通の盾", "type": "armor", "target": "self", "effect": "guard", "power": 99, "tags": []}
	var full_reflect: Dictionary = {"id": "full_reflect", "name": "全反射", "type": "armor", "target": "self", "effect": "reflect", "power": 0, "tags": ["full_reflect"]}
	rules.state["players"]["1"]["hp"] = 20
	rules.state["players"]["2"]["hp"] = 20
	rules.state["players"]["1"]["hand"] = [targeted_heal]
	rules.state["players"]["2"]["hand"] = [normal_guard, full_reflect]
	rules.state["deck"] = []
	var pending_heal: Dictionary = rules.play_card(1, "targeted_heal", 2)
	assert(String(pending_heal["phase"]) == "defense")
	assert(int(pending_heal["pending_attack"]["target_peer_id"]) == 2)
	var rejected_heal_guard: Dictionary = rules.play_defense_cards(2, ["normal_guard"])
	assert(String(rejected_heal_guard["phase"]) == "defense")
	assert(int(rejected_heal_guard["players"]["2"]["hand"].size()) == 2)
	var reflected_heal: Dictionary = rules.play_defense_cards(2, ["full_reflect"])
	assert(int(reflected_heal["players"]["1"]["hp"]) == 20)
	assert(int(reflected_heal["players"]["2"]["hp"]) == 20)
	assert(bool(reflected_heal["combat_view"]["reflected"]))
	var returned_heal: Dictionary = rules.continue_after_result()
	assert(String(returned_heal["phase"]) == "defense")
	assert(int(returned_heal["pending_attack"]["target_peer_id"]) == 1)
	var returned_heal_result: Dictionary = rules.pass_defense(1)
	assert(int(returned_heal_result["players"]["1"]["hp"]) == 25)

	rules.new_match(players, deck, 335)
	var reflected_attack: Dictionary = {"id": "reflected_attack", "name": "大剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10, "attribute": "none"}
	rules.state["players"]["1"]["hand"] = [reflected_attack]
	rules.state["players"]["2"]["hand"] = [full_reflect]
	rules.state["deck"] = []
	rules.play_card(1, "reflected_attack", 2)
	var fully_reflected_attack: Dictionary = rules.play_defense_cards(2, ["full_reflect"])
	assert(int(fully_reflected_attack["players"]["1"]["hp"]) == 40)
	assert(int(fully_reflected_attack["players"]["2"]["hp"]) == 40)
	var returned_attack: Dictionary = rules.continue_after_result()
	assert(String(returned_attack["phase"]) == "defense")
	assert(int(returned_attack["pending_attack"]["target_peer_id"]) == 1)
	var returned_attack_result: Dictionary = rules.pass_defense(1)
	assert(int(returned_attack_result["players"]["1"]["hp"]) == 30)

	# 防具と反射は同時使用不可。反射には数値がなく、返ったカードは再反射できる。
	rules.new_match(players, deck, 336)
	var attack_reflect: Dictionary = {
		"id": "attack_reflect", "name": "攻撃反射", "type": "armor",
		"target": "self", "effect": "reflect", "power": 999, "attribute": "none",
		"tags": ["attack_reflect"],
	}
	rules.state["players"]["1"]["hand"] = [reflected_attack, attack_reflect.duplicate(true)]
	rules.state["players"]["2"]["hand"] = [normal_guard, attack_reflect.duplicate(true)]
	rules.state["deck"] = []
	rules.play_card(1, "reflected_attack", 2)
	var rejected_mix: Dictionary = rules.play_defense_cards(2, ["normal_guard", "attack_reflect"])
	assert(String(rejected_mix["phase"]) == "defense")
	assert(int(rejected_mix["players"]["2"]["hand"].size()) == 2)
	rules.play_defense_cards(2, ["attack_reflect"])
	var first_return: Dictionary = rules.continue_after_result()
	assert(int(first_return["pending_attack"]["target_peer_id"]) == 1)
	rules.play_defense_cards(1, ["attack_reflect"])
	var second_return: Dictionary = rules.continue_after_result()
	assert(int(second_return["pending_attack"]["target_peer_id"]) == 2)
	var reflection_chain_result: Dictionary = rules.pass_defense(2)
	assert(int(reflection_chain_result["players"]["2"]["hp"]) == 30)

	# 全体攻撃の反射は、残り全員への攻撃が終わってから解決する。
	var three_players: Array = [
		{"peer_id": 1, "name": "Host"},
		{"peer_id": 2, "name": "Guest"},
		{"peer_id": 3, "name": "Third"},
	]
	rules.new_match(three_players, deck, 337)
	var all_reflected_attack: Dictionary = {
		"id": "all_reflected", "name": "全体攻撃", "type": "weapon",
		"target": "all_enemies", "effect": "attack", "power": 10, "attribute": "none",
	}
	rules.state["players"]["1"]["hand"] = [all_reflected_attack]
	rules.state["players"]["2"]["hand"] = [attack_reflect]
	rules.state["players"]["3"]["hand"] = []
	rules.state["deck"] = []
	rules.play_card(1, "all_reflected", 0)
	rules.play_defense_cards(2, ["attack_reflect"])
	var next_aoe_target: Dictionary = rules.continue_after_result()
	assert(int(next_aoe_target["pending_attack"]["target_peer_id"]) == 3)
	rules.pass_defense(3)
	var delayed_reflection: Dictionary = rules.continue_after_result()
	assert(int(delayed_reflection["pending_attack"]["target_peer_id"]) == 1)
	assert(int(delayed_reflection["players"]["3"]["hp"]) == 30)

	# 攻撃反射と奇跡反射は、カード種別が一致するときだけ使用できる。
	var miracle_reflect: Dictionary = {
		"id": "miracle_reflect", "name": "奇跡反射", "type": "armor",
		"target": "self", "effect": "reflect", "power": 0, "tags": ["miracle_reflect"],
	}
	var attack_pending: Dictionary = {"effect": "attack", "card": reflected_attack}
	var miracle_pending: Dictionary = {"effect": "heal", "card": targeted_heal}
	assert(rules.can_respond_with_card(attack_pending, attack_reflect))
	assert(not rules.can_respond_with_card(attack_pending, miracle_reflect))
	assert(not rules.can_respond_with_card(miracle_pending, attack_reflect))
	assert(rules.can_respond_with_card(miracle_pending, miracle_reflect))
	assert(rules.can_respond_with_card(miracle_pending, full_reflect))
	var mixed_pending: Dictionary = {
		"effect": "attack",
		"is_miracle": false,
		"attribute": "none",
		"card": {"type": "miracle", "effect": "attack", "attribute": "none"},
	}
	var pure_miracle_pending: Dictionary = mixed_pending.duplicate(true)
	pure_miracle_pending["is_miracle"] = true
	assert(rules.can_respond_with_card(mixed_pending, attack_reflect))
	assert(not rules.can_respond_with_card(mixed_pending, miracle_reflect))
	assert(not rules.can_respond_with_card(pure_miracle_pending, attack_reflect))
	assert(rules.can_respond_with_card(pure_miracle_pending, miracle_reflect))
	var fire_pending: Dictionary = {
		"effect": "attack", "attribute": "fire",
		"card": {"type": "weapon", "effect": "attack", "attribute": "fire"},
	}
	var fire_reflect: Dictionary = attack_reflect.duplicate(true)
	fire_reflect["attribute"] = "fire"
	var water_reflect: Dictionary = attack_reflect.duplicate(true)
	water_reflect["attribute"] = "water"
	var light_reflect: Dictionary = attack_reflect.duplicate(true)
	light_reflect["attribute"] = "light"
	assert(not rules.can_respond_with_card(fire_pending, fire_reflect))
	assert(rules.can_respond_with_card(fire_pending, water_reflect))
	assert(rules.can_respond_with_card(fire_pending, light_reflect))
	assert(rules._reflected_attribute(fire_pending, water_reflect) == "none")
	assert(rules._reflected_attribute(fire_pending, light_reflect) == "fire")
	assert(rules._reflected_attribute(fire_pending, full_reflect) == "fire")
	assert(rules._reflected_attribute(fire_pending, miracle_reflect) == "fire")
	rules.new_match(players, deck, 20260731)
	var erase_reflect: Dictionary = attack_reflect.duplicate(true)
	erase_reflect["id"] = "erase_reflect"
	erase_reflect["attribute"] = "fire"
	erase_reflect["special_effect"] = "attribute_erase"
	rules.state["players"]["1"]["hand"] = [light_special_attack]
	rules.state["players"]["2"]["hand"] = [erase_reflect]
	rules.state["deck"] = []
	rules.play_card(1, "light_special", 2)
	assert(rules.can_respond_with_card(rules.state["pending_attack"], erase_reflect))
	rules.play_defense_cards(2, ["erase_reflect"])
	var erased_reflection: Dictionary = rules.continue_after_result()
	assert(String(erased_reflection["pending_attack"]["attribute"]) == "none")

	# 攻防カードは、自分の行動では攻撃、相手の攻撃中は防具として使い分ける。
	rules.new_match(players, deck, 5001)
	var attack_and_guard: Dictionary = {
		"id": "attack_and_guard", "name": "攻防一体", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 10, "attribute": "none",
		"chance": 100, "effect_mode": "all",
		"effects": [
			{"effect": "attack", "power": 10, "target": "enemy", "chance": 100, "weight": 1},
			{"effect": "guard", "power": 6, "target": "self", "chance": 100, "weight": 1},
		],
	}
	rules.state["players"]["1"]["hand"] = [attack_and_guard]
	rules.state["deck"] = []
	rules.play_card(1, "attack_and_guard", 2)
	var attack_and_guard_result: Dictionary = rules.pass_defense(2)
	assert(int(attack_and_guard_result["players"]["2"]["hp"]) == 30)
	assert(not attack_and_guard_result["players"]["1"].has("guard"))
	rules.new_match(players, deck, 50011)
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["players"]["2"]["hand"] = [attack_and_guard]
	rules.state["deck"] = []
	rules.play_card(1, "weapon", 2)
	var attack_and_guard_defense: Dictionary = rules.play_defense_cards(2, ["attack_and_guard"])
	assert(int(attack_and_guard_defense["players"]["2"]["hp"]) == 36)
	assert(int(attack_and_guard_defense["combat_view"]["defense_power"]) == 6)

	# 癒やしの鎧は、自分の行動では回復アイテム、相手の攻撃中は防具として使う。
	rules.new_match(players, deck, 5002)
	var healing_armor: Dictionary = {
		"id": "healing_armor", "name": "癒やしの鎧", "type": "armor",
		"target": "self", "effect": "guard", "power": 8, "attribute": "none",
		"chance": 100, "effect_mode": "all",
		"effects": [
			{"effect": "guard", "power": 8, "target": "self", "chance": 100, "weight": 1},
			{"effect": "heal", "power": 5, "target": "self", "chance": 100, "weight": 1},
		],
	}
	rules.state["players"]["1"]["hand"] = [healing_armor]
	rules.state["players"]["1"]["hp"] = 30
	rules.state["deck"] = []
	var healing_armor_action: Dictionary = rules.play_card(1, "healing_armor", 1)
	assert(int(healing_armor_action["players"]["1"]["hp"]) == 35)
	assert(String(healing_armor_action["combat_view"]["status"]) == "support_resolved")
	assert(int(healing_armor_action["combat_view"]["attack_power"]) == 5)
	rules.new_match(players, deck, 50021)
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["players"]["2"]["hand"] = [healing_armor]
	rules.state["players"]["2"]["hp"] = 30
	rules.state["deck"] = []
	rules.play_card(1, "weapon", 2)
	var healing_armor_result: Dictionary = rules.play_defense_cards(2, ["healing_armor"])
	assert(int(healing_armor_result["players"]["2"]["hp"]) == 28)

	# 全体攻撃の命中率は対象ごとに振り直す。固定seedで片方だけ命中するケースを探す。
	var probabilistic_attack: Dictionary = {
		"id": "probabilistic_attack", "name": "五分五分の嵐", "type": "weapon",
		"target": "all_enemies", "effect": "attack", "power": 10, "attribute": "none",
		"chance": 50, "effect_mode": "all",
		"effects": [{"effect": "attack", "power": 10, "target": "all_enemies", "chance": 100, "weight": 1}],
	}
	var split_seed := 0
	for candidate_seed: int in range(1, 1000):
		rules.rng.seed = candidate_seed
		var first_hit: bool = not rules._roll_card_effects(probabilistic_attack).is_empty()
		var second_hit: bool = not rules._roll_card_effects(probabilistic_attack).is_empty()
		if first_hit != second_hit:
			split_seed = candidate_seed
			break
	assert(split_seed > 0)
	rules.new_match(trio, deck, 5003)
	rules.state["players"]["1"]["hand"] = [probabilistic_attack]
	rules.state["deck"] = []
	rules.rng.seed = split_seed
	var probability_step: Dictionary = rules.play_card(1, "probabilistic_attack", 0)
	if String(probability_step["phase"]) == "defense":
		probability_step = rules.pass_defense(2)
	probability_step = rules.continue_after_result()
	if String(probability_step["phase"]) == "defense":
		probability_step = rules.pass_defense(3)
	rules.continue_after_result()
	var damaged_targets := 0
	for probability_peer_id: int in [2, 3]:
		if int(rules.state["players"][str(probability_peer_id)]["hp"]) == 30:
			damaged_targets += 1
	assert(damaged_targets == 1)

	# 防具側の発動率も1枚ずつ判定。0%なら防御値が高くても発動しない。
	rules.new_match(players, deck, 5004)
	var failing_armor: Dictionary = {
		"id": "failing_armor", "name": "不発の盾", "type": "armor",
		"target": "self", "effect": "guard", "power": 99, "attribute": "none",
		"chance": 0, "effects": [{"effect": "guard", "power": 99, "target": "self"}],
	}
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["players"]["2"]["hand"] = [failing_armor]
	rules.state["deck"] = []
	rules.play_card(1, "weapon", 2)
	var failed_armor_result: Dictionary = rules.play_defense_cards(2, ["failing_armor"])
	assert(int(failed_armor_result["players"]["2"]["hp"]) == 30)
	assert(int(failed_armor_result["combat_view"]["defense_power"]) == 0)

	# ランダム1効果は比率で選択。1:5なら十分な試行で即死がおよそ6分の1になる。
	var roulette: Dictionary = {
		"id": "roulette", "name": "ロシアンルーレット", "type": "special",
		"target": "self", "effect": "instant_death", "power": 0,
		"chance": 100, "effect_mode": "random_one",
		"effects": [
			{"effect": "instant_death", "power": 0, "target": "self", "chance": 100, "weight": 1},
			{"effect": "heal", "power": 30, "target": "self", "chance": 100, "weight": 5},
		],
	}
	rules.rng.seed = 6006
	var death_count := 0
	var heal_count := 0
	for _roulette_index: int in range(600):
		var rolled_roulette: Array = rules._roll_card_effects(roulette)
		assert(rolled_roulette.size() == 1)
		if String(rolled_roulette[0].get("effect", "")) == "instant_death":
			death_count += 1
		else:
			heal_count += 1
	assert(death_count >= 70 and death_count <= 130)
	assert(death_count + heal_count == 600)

	var card_store: Node = load("res://scripts/card_store.gd").new()
	var default_cards: Array[Dictionary] = card_store._default_cards()
	assert(default_cards.size() == 86)
	var default_ids: Dictionary = {}
	var found_full_reflect := false
	var found_composite_attack := false
	var found_healing_armor := false
	var found_roulette := false
	for default_card: Dictionary in default_cards:
		assert(String(default_card.get("image_path", "")).is_empty())
		assert(default_card.has("price"))
		assert(int(default_card.get("price", -1)) >= 0)
		assert(not default_ids.has(String(default_card["id"])))
		if String(default_card.get("effect", "")) == "heal":
			assert(String(default_card.get("attribute", "")) == "none")
		if String(default_card.get("id", "")) == "builtin-056":
			found_full_reflect = "full_reflect" in default_card.get("tags", [])
		if String(default_card.get("effect", "")) == "reflect":
			assert(int(default_card.get("power", -1)) == 0)
		if String(default_card.get("id", "")) == "builtin-081":
			found_composite_attack = int(default_card.get("effects", []).size()) == 2
		if String(default_card.get("id", "")) == "builtin-082":
			found_healing_armor = int(default_card.get("effects", []).size()) == 2
		if String(default_card.get("id", "")) == "builtin-083":
			found_roulette = (
				String(default_card.get("effect_mode", "")) == "random_one"
				and int(default_card.get("effects", [])[0].get("weight", 0)) == 1
				and int(default_card.get("effects", [])[1].get("weight", 0)) == 5
			)
		default_ids[String(default_card["id"])] = true
	assert(found_full_reflect)
	assert(found_composite_attack)
	assert(found_healing_armor)
	assert(found_roulette)
	var invalid_attribute_card: Dictionary = {"attribute": "wind"}
	card_store._normalize_card(invalid_attribute_card)
	assert(String(invalid_attribute_card["attribute"]) == "none")
	var wood_attribute_card: Dictionary = {"attribute": "wood"}
	card_store._normalize_card(wood_attribute_card)
	assert(String(wood_attribute_card["attribute"]) == "wood")
	var normalized_composite: Dictionary = {
		"type": "special",
		"chance": 150,
		"effect_mode": "random_one",
		"effects": [
			{"effect": "instant_death", "power": 0, "target": "self", "chance": -5, "weight": 1},
			{"effect": "heal", "power": 30, "target": "self", "chance": 120, "weight": 5},
		],
	}
	card_store._normalize_card(normalized_composite)
	assert(int(normalized_composite["chance"]) == 100)
	assert(String(normalized_composite["effect_mode"]) == "random_one")
	assert(int(normalized_composite["effects"].size()) == 2)
	assert(int(normalized_composite["effects"][0]["chance"]) == 0)
	assert(int(normalized_composite["effects"][1]["chance"]) == 100)

	# 旧 multi_attack は「攻撃＋対象＝敵全体」に読み替えられる。
	var legacy_multi: Dictionary = {"type": "weapon", "effect": "multi_attack", "power": 6}
	card_store._normalize_card(legacy_multi)
	assert(String(legacy_multi["effect"]) == "attack")
	assert(String(legacy_multi["target"]) == "all_enemies")

	# 種類にかかわらず任意の効果と対象を持てる。
	var special_item: Dictionary = {"type": "special", "effect": "guard", "power": 5}
	card_store._normalize_card(special_item)
	assert(String(special_item["effect"]) == "guard")
	var special_buff: Dictionary = {"type": "special", "effect": "buff", "power": 5}
	card_store._normalize_card(special_buff)
	assert(String(special_buff["effect"]) == "buff")
	assert(String(special_buff["target"]) == "enemy")

	# 攻撃アップでも自分対象などを保持できる。
	var buff_weapon_norm: Dictionary = {"type": "weapon", "effect": "buff", "target": "self", "power": 5}
	card_store._normalize_card(buff_weapon_norm)
	assert(String(buff_weapon_norm["target"]) == "self")
	var invalid_armor_special: Dictionary = {
		"type": "armor", "effect": "guard", "special_effect": "double_attack",
	}
	card_store._normalize_card(invalid_armor_special)
	assert(String(invalid_armor_special["special_effect"]) == "")
	var valid_attack_special: Dictionary = {
		"type": "weapon", "effect": "attack",
		"special_effect": "attribute_change", "special_attribute": "water",
	}
	card_store._normalize_card(valid_attack_special)
	assert(String(valid_attack_special["special_effect"]) == "attribute_change")
	assert(String(valid_attack_special["special_attribute"]) == "water")
	var valid_armor_special: Dictionary = {
		"type": "armor", "effect": "guard", "special_effect": "attribute_erase",
	}
	card_store._normalize_card(valid_armor_special)
	assert(String(valid_armor_special["special_effect"]) == "attribute_erase")
	var paid_card: Dictionary = {
		"type": "weapon", "effect": "attack",
		"cost": {"resource": "mp", "amount": 12},
	}
	card_store._normalize_card(paid_card)
	assert(String(paid_card["cost"]["resource"]) == "mp")
	assert(int(paid_card["cost"]["amount"]) == 12)
	var invalid_cost: Dictionary = {
		"type": "weapon", "effect": "attack",
		"cost": {"resource": "souls", "amount": 999},
	}
	card_store._normalize_card(invalid_cost)
	assert(String(invalid_cost["cost"]["resource"]) == "none")
	assert(int(invalid_cost["cost"]["amount"]) == 0)
	var priced_card: Dictionary = {
		"type": "weapon", "effect": "attack", "power": 12, "price": 7,
	}
	card_store._normalize_card(priced_card)
	assert(int(priced_card["price"]) == 7)
	var migrated_price_card: Dictionary = {
		"type": "weapon", "effect": "attack", "power": 12,
	}
	card_store._normalize_card(migrated_price_card)
	assert(int(migrated_price_card["price"]) >= 1)
	var excessive_price_card: Dictionary = {
		"type": "weapon", "effect": "attack", "price": 999,
	}
	card_store._normalize_card(excessive_price_card)
	assert(int(excessive_price_card["price"]) == 99)

	# 売買は専用の種類・効果として正規化し、旧タグ形式も移行する。
	var legacy_buy: Dictionary = {
		"type": "special", "effect": "heal", "power": 0, "tags": ["trade_buy"],
	}
	card_store._normalize_card(legacy_buy)
	assert(String(legacy_buy["type"]) == "trade")
	assert(String(legacy_buy["effect"]) == "buy")
	assert(int(legacy_buy["power"]) == 1)

	# 「買う」は数値枚をまとめてランダム提示し、全購入か全辞退だけを選ぶ。
	var buy_card: Dictionary = {
		"id": "buy", "name": "買う", "type": "trade", "target": "enemy",
		"effect": "buy", "power": 2, "price": 5,
	}
	var shop_item: Dictionary = {
		"id": "shop_item", "name": "商品", "type": "weapon", "target": "enemy",
		"effect": "attack", "power": 4, "price": 7,
	}
	var free_miracle: Dictionary = {
		"id": "free_miracle", "name": "無料の奇跡", "type": "miracle",
		"target": "self", "effect": "heal", "power": 4, "price": 20,
	}
	rules.new_match(players, deck, 3001)
	rules.state["players"]["1"]["hand"] = [buy_card]
	rules.state["players"]["2"]["hand"] = [shop_item, free_miracle]
	var purchase_offer: Dictionary = rules.play_action_cards(1, ["buy"], 2)
	assert(String(purchase_offer["phase"]) == "defense")
	assert(String(purchase_offer["pending_attack"]["effect"]) == "buy")
	assert(not rules.can_respond_with_card(purchase_offer["pending_attack"], attack_reflect))
	assert(rules.can_respond_with_card(purchase_offer["pending_attack"], full_reflect))
	purchase_offer = rules.pass_defense(2)
	assert(String(purchase_offer["phase"]) == "purchase")
	assert(int(purchase_offer["pending_purchase"]["price"]) == 7)
	assert(int(purchase_offer["pending_purchase"]["cards"].size()) == 2)
	var purchase_result: Dictionary = rules.resolve_purchase(1, true)
	assert(String(purchase_result["phase"]) == "result")
	assert(int(purchase_result["players"]["1"]["gold"]) == 13)
	assert(int(purchase_result["players"]["2"]["gold"]) == 27)
	assert(purchase_result["players"]["2"]["hand"].is_empty())
	rules.new_match(players, deck, 3011)
	rules.state["players"]["1"]["hand"] = [buy_card]
	rules.state["players"]["2"]["hand"] = [shop_item, free_miracle]
	rules.play_action_cards(1, ["buy"], 2)
	rules.pass_defense(2)
	var declined_purchase: Dictionary = rules.resolve_purchase(1, false)
	assert(int(declined_purchase["players"]["1"]["gold"]) == 20)
	assert(int(declined_purchase["players"]["2"]["hand"].size()) == 2)

	# 「買う」を完全反射すると、反射した側が元の使用者から買う効果になる。
	var reflected_shop_item: Dictionary = shop_item.duplicate(true)
	reflected_shop_item["id"] = "reflected_shop_item"
	reflected_shop_item["price"] = 6
	rules.new_match(players, deck, 3021)
	rules.state["deck"] = []
	rules.state["players"]["1"]["hand"] = [buy_card, reflected_shop_item]
	rules.state["players"]["2"]["hand"] = [full_reflect.duplicate(true)]
	rules.play_action_cards(1, ["buy"], 2)
	var reflected_buy: Dictionary = rules.play_defense_cards(2, ["full_reflect"])
	assert(String(reflected_buy["phase"]) == "result")
	var returned_buy: Dictionary = rules.continue_after_result()
	assert(String(returned_buy["phase"]) == "defense")
	assert(int(returned_buy["pending_attack"]["target_peer_id"]) == 1)
	var returned_purchase: Dictionary = rules.pass_defense(1)
	assert(String(returned_purchase["phase"]) == "purchase")
	assert(int(returned_purchase["pending_purchase"]["buyer_peer_id"]) == 2)
	assert(int(returned_purchase["pending_purchase"]["seller_peer_id"]) == 1)
	assert(String(returned_purchase["pending_purchase"]["cards"][0].get("id", "")) == "reflected_shop_item")
	var reflected_purchase_result: Dictionary = rules.resolve_purchase(2, true)
	assert(int(reflected_purchase_result["players"]["1"]["gold"]) == 26)
	assert(int(reflected_purchase_result["players"]["2"]["gold"]) == 14)
	assert(String(reflected_purchase_result["players"]["2"]["hand"][0].get("id", "")) == "reflected_shop_item")

	# 「売る」は数値を最大枚数として、それ以下の任意枚数を強制売却できる。
	var sell_card: Dictionary = {
		"id": "sell", "name": "売る", "type": "trade", "target": "enemy",
		"effect": "sell", "power": 2, "price": 5,
	}
	var forced_item: Dictionary = {
		"id": "forced_item", "name": "押し売り品", "type": "weapon",
		"target": "enemy", "effect": "attack", "power": 1, "price": 7,
	}
	var forced_item_2: Dictionary = {
		"id": "forced_item_2", "name": "押し売り品2", "type": "armor",
		"target": "self", "effect": "guard", "power": 1, "price": 4,
	}
	rules.new_match(players, deck, 3002)
	rules.state["players"]["1"]["hand"] = [sell_card, forced_item, forced_item_2]
	rules.state["players"]["2"]["hand"] = []
	rules.state["players"]["2"]["gold"] = 2
	rules.state["players"]["2"]["mp"] = 3
	rules.state["players"]["2"]["hp"] = 20
	var forced_sale: Dictionary = rules.play_action_cards(
		1, ["sell", "forced_item", "forced_item_2"], 2
	)
	assert(String(forced_sale["phase"]) == "defense")
	assert(String(forced_sale["pending_attack"]["effect"]) == "sell")
	forced_sale = rules.pass_defense(2)
	assert(String(forced_sale["phase"]) == "result")
	assert(int(forced_sale["players"]["1"]["gold"]) == 31)
	assert(int(forced_sale["players"]["2"]["gold"]) == 0)
	assert(int(forced_sale["players"]["2"]["mp"]) == 0)
	assert(int(forced_sale["players"]["2"]["hp"]) == 14)
	assert(String(forced_sale["players"]["2"]["hand"][0].get("id", "")) == "forced_item")
	assert(String(forced_sale["players"]["2"]["hand"][1].get("id", "")) == "forced_item_2")
	rules.new_match(players, deck, 3012)
	rules.state["players"]["1"]["hand"] = [sell_card, forced_item, forced_item_2]
	rules.state["players"]["2"]["hand"] = []
	var partial_sale: Dictionary = rules.play_action_cards(
		1, ["sell", "forced_item"], 2
	)
	partial_sale = rules.pass_defense(2)
	assert(String(partial_sale["phase"]) == "result")
	assert(int(partial_sale["players"]["2"]["hand"].size()) == 1)

	# 「売る」の完全反射は商品を元の手札へ返し、代金だけを逆向きに徴収する。
	rules.new_match(players, deck, 3022)
	rules.state["deck"] = []
	rules.state["players"]["1"]["hand"] = [sell_card, forced_item]
	rules.state["players"]["2"]["hand"] = [full_reflect.duplicate(true)]
	rules.play_action_cards(1, ["sell", "forced_item"], 2)
	var reflected_sale: Dictionary = rules.play_defense_cards(2, ["full_reflect"])
	assert(String(reflected_sale["phase"]) == "result")
	assert(bool(reflected_sale["combat_view"]["reflected"]))
	var returned_sale: Dictionary = rules.continue_after_result()
	assert(String(returned_sale["phase"]) == "defense")
	assert(int(returned_sale["pending_attack"]["target_peer_id"]) == 1)
	var reflected_sale_result: Dictionary = rules.pass_defense(1)
	assert(String(reflected_sale_result["phase"]) == "result")
	assert(int(reflected_sale_result["players"]["1"]["gold"]) == 13)
	assert(int(reflected_sale_result["players"]["2"]["gold"]) == 27)
	assert(reflected_sale_result["players"]["1"]["hand"].size() == 1)
	assert(String(reflected_sale_result["players"]["1"]["hand"][0].get("id", "")) == "forced_item")
	assert(reflected_sale_result["players"]["2"]["hand"].is_empty())

	# 両替は合計を保てば自由配分でき、HP 0も有効（効果成立後に脱落）。
	var exchange_card: Dictionary = {
		"id": "exchange", "name": "両替", "type": "trade", "target": "self",
		"effect": "exchange", "power": 999, "price": 5,
	}
	card_store._normalize_card(exchange_card)
	assert(int(exchange_card["power"]) == 0)
	rules.new_match(players, deck, 3003)
	rules.state["players"]["1"]["hand"] = [exchange_card]
	var exchange_result: Dictionary = rules.play_exchange(1, "exchange", 0, 30, 50)
	assert(int(exchange_result["players"]["1"]["hp"]) == 0)
	assert(int(exchange_result["players"]["1"]["mp"]) == 30)
	assert(int(exchange_result["players"]["1"]["gold"]) == 50)
	assert(not bool(exchange_result["players"]["1"]["alive"]))
	assert(String(exchange_result["phase"]) == "game_over")

	# 廃止された対象（all / ally）は self に丸められる。
	var bad_target: Dictionary = {"type": "miracle", "effect": "heal", "target": "all", "power": 4}
	card_store._normalize_card(bad_target)
	assert(String(bad_target["target"]) == "self")
	var all_heal_card: Dictionary = {"type": "miracle", "effect": "heal", "target": "all_players", "power": 4}
	card_store._normalize_card(all_heal_card)
	assert(String(all_heal_card["target"]) == "all_players")
	var attributed_heal: Dictionary = {"type": "miracle", "effect": "heal", "attribute": "fire", "power": -4}
	card_store._normalize_card(attributed_heal)
	assert(String(attributed_heal["attribute"]) == "none")

	# 敵全体の攻撃はレアリティが上乗せされる（6 + 15 = 21 → アンコモン、単体なら 6 でコモン）。
	assert(card_store.auto_rarity({"effect": "attack", "power": 6, "target": "all_enemies"}) == "uncommon")
	assert(card_store.auto_rarity({"effect": "attack", "power": 6, "target": "enemy"}) == "common")
	assert(card_store.auto_rarity({"effect": "heal", "power": 5, "target": "all_players"}) == "uncommon")
	# 発動率・属性・反射種別・奇跡加点・重み付き抽選を仕様どおりスコアへ反映する。
	assert(card_store.auto_rarity({"effect": "instant_death", "power": 0}) == "禁忌")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 100, "chance": 50,
	}) == "legendary")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 100,
		"effects": [{"effect": "attack", "power": 100, "chance": 50, "weight": 1}],
	}) == "legendary")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 8, "attribute": "light",
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 4, "attribute": "dark",
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "reflect", "power": 999, "tags": ["attack_reflect"],
	}) == "common")
	assert(card_store.auto_rarity({
		"effect": "reflect", "power": 0, "tags": ["miracle_reflect"],
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "reflect", "power": 0, "tags": ["full_reflect"],
	}) == "rare")
	assert(card_store.auto_rarity({
		"type": "miracle", "effect": "heal", "power": 10,
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 10, "special_effect": "double_power",
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 10, "special_effect": "double_attack",
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 20,
		"cost": {"resource": "mp", "amount": 5},
	}) == "common")
	assert(card_store.auto_rarity({
		"effect": "attack", "power": 4, "special_effect": "attribute_change",
		"special_attribute": "dark",
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"type": "armor", "effect": "guard", "power": 0,
		"special_effect": "attribute_erase",
	}) == "uncommon")
	assert(card_store.auto_rarity({
		"effect": "attack",
		"effect_mode": "random_one",
		"effects": [
			{"effect": "attack", "power": 10, "chance": 100, "weight": 1},
			{"effect": "instant_death", "power": 0, "chance": 100, "weight": 1},
		],
	}) == "rare")
	var rarity_pile: Array = rules._build_draw_pile([
		{"id": "common", "rarity": "common"},
		{"id": "forbidden", "rarity": "禁忌"},
	])
	assert(rarity_pile.size() == 8)
	for rarity_card: Dictionary in rarity_pile:
		assert(String(rarity_card.get("rarity", "")) != "禁忌")
	# 無限山札は引いても候補が減らず、同じカードを再び引ける。
	rules.new_match(players, [{"id": "infinite", "rarity": "legendary"}], 20260731)
	var infinite_deck_size: int = rules.state["deck"].size()
	rules.state["players"]["1"]["hand"] = []
	for draw_index: int in range(12):
		assert(rules._draw_one_card(1))
		assert(rules.state["deck"].size() == infinite_deck_size)
		assert(String(rules.state["players"]["1"]["hand"].pop_back().get("id", "")) == "infinite")
	# 同じカードIDでも所有者が違えば共通デッキに両方残り、再送時はその人の分だけ置換する。
	card_store.session_cards.clear()
	card_store.replace_cards_from_peer([{"id": "shared", "name": "A"}], 1)
	card_store.replace_cards_from_peer([{"id": "shared", "name": "B"}], 2)
	assert(card_store.session_cards.size() == 2)
	card_store.replace_cards_from_peer([{"id": "new", "name": "C"}], 1)
	assert(card_store.session_cards.size() == 2)
	for session_card: Dictionary in card_store.session_cards:
		if int(session_card.get("owner_peer_id", 0)) == 1:
			assert(String(session_card.get("id", "")) == "new")
	card_store.free()

	var battle_ui: Control = load("res://scripts/battle_ui.gd").new()
	assert(battle_ui._card_kind_label({"effect": "attack", "target": "all_enemies"}) == "全")
	assert(battle_ui._card_kind_label({"effect": "heal", "target": "all_players"}) == "（全）")
	assert(battle_ui._card_kind_label({"effect": "buff", "target": "enemy"}) == "攻＋")
	assert(battle_ui._hand_card_value_text({
		"effect": "attack", "target": "enemy", "power": 6,
	}) == "攻6")
	assert(battle_ui._hand_card_value_text({
		"effect": "attack", "target": "all_enemies", "power": 6,
	}) == "全6")
	assert(battle_ui._hand_card_value_text({
		"effect": "heal", "target": "self", "power": 5,
	}) == "癒5")
	assert(battle_ui._card_border_color({"type": "miracle"}) == Color("#e0574f"))
	assert(battle_ui._card_border_color({"type": "weapon"}) == Color("#9caaa5"))
	var compact_combat_card: PanelContainer = battle_ui._make_combat_card({
		"id": "hoverable", "name": "とても長い説明を持つカード",
		"description": "この説明は場のカード本体には常設しない。",
		"type": "weapon", "effect": "attack", "target": "enemy", "power": 6, "price": 7,
	})
	var compact_row: HBoxContainer = compact_combat_card.get_child(0)
	var compact_details: VBoxContainer = compact_row.get_child(1)
	assert(compact_details.get_child_count() == 2)
	assert(compact_row.get_child_count() == 3)
	assert(String(compact_row.get_child(2).get_child(0).text) == "¥7")
	assert(compact_row.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(compact_combat_card.mouse_entered.get_connections().size() == 1)
	compact_combat_card.free()
	assert("特殊:2回攻撃" in battle_ui._card_value_text({
		"effect": "attack", "power": 5, "special_effect": "double_attack",
	}))
	var hover_cost_card := {
		"effect": "attack", "power": 5,
		"cost": {"resource": "mp", "amount": 5},
	}
	assert("MP5" not in battle_ui._card_value_text(hover_cost_card))
	assert(battle_ui._cost_hover_text(hover_cost_card) == "消費MP5")
	assert(battle_ui._chance_suffix({"chance": 75}) == " 75%")
	assert(battle_ui._card_kind_label(attack_and_guard) == "攻／守")
	assert(battle_ui._can_play_in_action(healing_armor))
	assert(not battle_ui._effects_for_context(healing_armor, "action").is_empty())
	assert(String(battle_ui._effects_for_context(healing_armor, "action")[0]["effect"]) == "heal")
	assert(String(battle_ui._effects_for_context(healing_armor, "defense")[0]["effect"]) == "guard")
	var reflect_only: Dictionary = {
		"type": "special", "effect": "reflect", "target": "self", "power": 0,
	}
	var guard_only: Dictionary = {
		"type": "special", "effect": "guard", "target": "self", "power": 5,
	}
	assert(not rules._can_play_in_action(reflect_only))
	assert(rules._effects_for_context(reflect_only, "action").is_empty())
	assert(not rules._effects_for_context(reflect_only, "defense").is_empty())
	assert(not rules._can_play_in_action(guard_only))
	assert(rules._effects_for_context(guard_only, "action").is_empty())
	assert(not rules._effects_for_context(guard_only, "defense").is_empty())
	assert(not battle_ui._can_play_in_action(reflect_only))
	assert(battle_ui._effects_for_context(reflect_only, "action").is_empty())
	assert(not battle_ui._effects_for_context(reflect_only, "defense").is_empty())
	assert(not battle_ui._can_play_in_action(guard_only))
	assert(battle_ui._effects_for_context(guard_only, "action").is_empty())
	assert(not battle_ui._effects_for_context(guard_only, "defense").is_empty())
	assert(battle_ui._random_effect_percent(roulette, 0) == 17)
	assert(battle_ui._random_effect_percent(roulette, 1) == 83)
	assert("死 17%" in battle_ui._card_value_text(roulette))
	assert("癒 30 83%" in battle_ui._card_value_text(roulette))
	battle_ui.selected_action_cards.append({"attribute": "light"})
	battle_ui.selected_action_cards.append({"attribute": "earth"})
	assert(battle_ui._combined_action_attribute() == "earth")
	var negative_heal_color: Color = battle_ui._attribute_color({"effect": "heal", "power": -5})
	assert(negative_heal_color.r > negative_heal_color.g)
	battle_ui.free()

	print("rules_smoke: PASS")
	rules.free()
	quit()

func _attribute_battle(
		rules: Node,
		players: Array,
		attack_attribute: String,
		defense_attributes: Array[String],
		attack_power: int = 10
) -> Dictionary:
	rules.new_match(players, [], 777)
	var weapon: Dictionary = {
		"id": "attribute_weapon",
		"name": "属性攻撃",
		"type": "weapon",
		"target": "enemy",
		"effect": "attack",
		"power": attack_power,
		"attribute": attack_attribute,
	}
	var armors: Array = []
	var armor_ids: Array[String] = []
	for index: int in range(defense_attributes.size()):
		var armor_id := "attribute_armor_%d" % index
		armors.append({
			"id": armor_id,
			"name": "属性防具",
			"type": "armor",
			"target": "self",
			"effect": "guard",
			"power": 4,
			"attribute": defense_attributes[index],
		})
		armor_ids.append(armor_id)
	rules.state["players"]["1"]["hand"] = [weapon]
	rules.state["players"]["2"]["hand"] = armors
	rules.state["deck"] = []
	rules.play_card(1, "attribute_weapon", 2)
	return rules.play_defense_cards(2, armor_ids) if not armor_ids.is_empty() else rules.pass_defense(2)
