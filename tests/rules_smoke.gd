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

	# 事前に使った guard カードが、攻撃解決時にちゃんと適用されること。
	rules.new_match(players, deck, 24680)
	var guard_charm: Dictionary = {"id": "charm", "name": "護符", "type": "special", "target": "self", "effect": "guard", "power": 4}
	rules.state["players"]["1"]["hand"] = [deck[0].duplicate(true)]
	rules.state["players"]["2"]["hand"] = [guard_charm]
	rules.state["deck"] = []
	rules.state["turn"] = 1
	rules.play_card(2, "charm", 2)
	assert(int(rules.state["players"]["2"]["guard"]) == 4)
	rules.continue_after_result()
	assert(String(rules.state["phase"]) == "action")
	rules.play_card(1, "weapon", 2)
	var guarded_result: Dictionary = rules.pass_defense(2)
	assert(int(guarded_result["players"]["2"]["hp"]) == 34)
	assert(int(guarded_result["players"]["2"]["guard"]) == 0)

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

	# 敵全体攻撃に攻撃アップを重ねると、合算された威力（6+4=10）で全員を順番に攻撃する。
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
	var all_started: Dictionary = rules.play_action_cards(1, ["all", "abuff"], 0)
	assert(String(all_started["phase"]) == "defense")
	assert(int(all_started["pending_attack"]["target_peer_id"]) == 2)
	assert(int(all_started["pending_attack"]["power"]) == 10)
	rules.pass_defense(2)
	assert(int(rules.state["players"]["2"]["hp"]) == 30)
	var next_target: Dictionary = rules.continue_after_result()
	assert(String(next_target["phase"]) == "defense")
	assert(int(next_target["pending_attack"]["target_peer_id"]) == 3)
	rules.pass_defense(3)
	assert(int(rules.state["players"]["3"]["hp"]) == 30)
	var all_done: Dictionary = rules.continue_after_result()
	assert(String(all_done["phase"]) == "action")
	assert(int(all_done["turn"]) == 1)

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
	rules.state["players"]["2"]["hp"] = 38
	rules.state["players"]["3"]["hp"] = 0
	rules.state["players"]["3"]["alive"] = false
	rules.state["players"]["1"]["hand"] = [all_heal]
	rules.state["deck"] = []
	var healed_everyone: Dictionary = rules.play_card(1, "all_heal", 0)
	assert(String(healed_everyone["phase"]) == "result")
	assert(int(healed_everyone["players"]["1"]["hp"]) == 35)
	assert(int(healed_everyone["players"]["2"]["hp"]) == 38)
	assert(int(healed_everyone["players"]["3"]["hp"]) == 0)
	assert(String(healed_everyone["combat_view"]["result_text"]).ends_with("HP +5"))
	assert(int(healed_everyone["combat_view"]["target_peer_id"]) == 1)
	var second_heal_target: Dictionary = rules.continue_after_result()
	assert(String(second_heal_target["phase"]) == "defense")
	assert(int(second_heal_target["pending_attack"]["target_peer_id"]) == 2)
	var second_heal_result: Dictionary = rules.pass_defense(2)
	assert(int(second_heal_result["players"]["2"]["hp"]) == 40)
	var all_heal_done: Dictionary = rules.continue_after_result()
	assert(String(all_heal_done["phase"]) == "action")

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

	# 自分対象の回復も他人を選べる。通常防具は使えず、完全反射だけが使用者へ返す。
	rules.new_match(players, deck, 334)
	var targeted_heal: Dictionary = {"id": "targeted_heal", "name": "他人への祝福", "type": "miracle", "target": "self", "effect": "heal", "power": 5}
	var normal_guard: Dictionary = {"id": "normal_guard", "name": "普通の盾", "type": "armor", "target": "self", "effect": "guard", "power": 99, "tags": []}
	var full_reflect: Dictionary = {"id": "full_reflect", "name": "完全反射", "type": "armor", "target": "self", "effect": "reflect", "power": 1, "tags": ["full_reflect"]}
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
	assert(int(reflected_heal["players"]["1"]["hp"]) == 25)
	assert(int(reflected_heal["players"]["2"]["hp"]) == 20)
	assert(bool(reflected_heal["combat_view"]["reflected"]))

	rules.new_match(players, deck, 335)
	var reflected_attack: Dictionary = {"id": "reflected_attack", "name": "大剣", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10, "attribute": "none"}
	rules.state["players"]["1"]["hand"] = [reflected_attack]
	rules.state["players"]["2"]["hand"] = [full_reflect]
	rules.state["deck"] = []
	rules.play_card(1, "reflected_attack", 2)
	var fully_reflected_attack: Dictionary = rules.play_defense_cards(2, ["full_reflect"])
	assert(int(fully_reflected_attack["players"]["1"]["hp"]) == 30)
	assert(int(fully_reflected_attack["players"]["2"]["hp"]) == 40)

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
	assert(int(attack_and_guard_result["players"]["1"]["guard"]) == 0)
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
	assert(default_cards.size() == 83)
	var default_ids: Dictionary = {}
	var found_full_reflect := false
	var found_composite_attack := false
	var found_healing_armor := false
	var found_roulette := false
	for default_card: Dictionary in default_cards:
		assert(String(default_card.get("image_path", "")).is_empty())
		assert(not default_ids.has(String(default_card["id"])))
		if String(default_card.get("effect", "")) == "heal":
			assert(String(default_card.get("attribute", "")) == "none")
		if String(default_card.get("id", "")) == "builtin-056":
			found_full_reflect = "full_reflect" in default_card.get("tags", [])
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
	card_store.free()

	var battle_ui: Control = load("res://scripts/battle_ui.gd").new()
	assert(battle_ui._card_kind_label({"effect": "heal", "target": "all_players"}) == "全")
	assert(battle_ui._card_kind_label({"effect": "buff", "target": "enemy"}) == "攻＋")
	assert(battle_ui._chance_suffix({"chance": 75}) == " 75%")
	assert(battle_ui._card_kind_label(attack_and_guard) == "攻／守")
	assert(battle_ui._can_play_in_action(healing_armor))
	assert(not battle_ui._effects_for_context(healing_armor, "action").is_empty())
	assert(String(battle_ui._effects_for_context(healing_armor, "action")[0]["effect"]) == "heal")
	assert(String(battle_ui._effects_for_context(healing_armor, "defense")[0]["effect"]) == "guard")
	var reflect_only: Dictionary = {
		"type": "special", "effect": "reflect", "target": "self", "power": 0,
	}
	assert(not rules._can_play_in_action(reflect_only))
	assert(rules._effects_for_context(reflect_only, "action").is_empty())
	assert(not rules._effects_for_context(reflect_only, "defense").is_empty())
	assert(not battle_ui._can_play_in_action(reflect_only))
	assert(battle_ui._effects_for_context(reflect_only, "action").is_empty())
	assert(not battle_ui._effects_for_context(reflect_only, "defense").is_empty())
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
