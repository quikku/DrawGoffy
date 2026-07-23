extends Node

const START_HP := 40
const HAND_SIZE := 9
const MAX_CARD_COUNT := 18
const VALID_ATTRIBUTES: Array[String] = [
	"none", "fire", "water", "wood", "earth", "light", "dark",
]

var state: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func new_match(players: Array, deck: Array, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	state = {
		"seed": seed_value,
		"turn": 0,
		"phase": "action",
		"players": {},
		"player_order": [],
		"pending_attack": {},
		"multi_attack_queue": {},
		"pending_counter_attack": {},
		"combat_view": {},
		"deck": _build_draw_pile(deck),
		"discard": [],
		"log": ["シード値: %s" % seed_value],
		"multi_support_queue": {},
	}
	for raw_player: Variant in players:
		if not (raw_player is Dictionary):
			continue
		var player: Dictionary = raw_player
		var peer_id: int = int(player.get("peer_id", 1))
		state["player_order"].append(peer_id)
		state["players"][str(peer_id)] = {
			"peer_id": peer_id,
			"name": String(player.get("name", "プレイヤー%s" % peer_id)),
			"hp": START_HP,
			"alive": true,
			"hand": [],
			"learned_miracles": [],
			"guard": 0,
			"guard_attribute": "none",
			"reflect": false,
		}
		_draw_to_hand(peer_id)
	return state.duplicate(true)

func play_card(actor_peer_id: int, card_id: String, target_peer_id: int) -> Dictionary:
	if state.is_empty():
		return {}
	if String(state.get("phase", "action")) == "defense":
		# 防御フェーズでは、属性条件を満たす防具だけを扱う。
		return play_defense_cards(actor_peer_id, [card_id])
	# 行動フェーズは常に「カードのセット」として扱う（攻撃＋攻撃アップなど）。
	return play_action_cards(actor_peer_id, [card_id], target_peer_id)

# 行動フェーズにカードのセットを出す。攻撃カードは1枚まで、攻撃アップは何枚でも
# 重ねられ（単独でも攻撃になる）、威力は合算される。攻撃以外は1枚だけ単発で出す。
func play_action_cards(actor_peer_id: int, card_ids: Array, target_peer_id: int) -> Dictionary:
	if state.is_empty():
		return {}
	if String(state.get("phase", "action")) != "action":
		return state.duplicate(true)
	var actor: Dictionary = _player(actor_peer_id)
	if actor.is_empty() or not bool(actor.get("alive", false)) or actor_peer_id != _current_peer_id():
		return state.duplicate(true)
	if card_ids.is_empty():
		return state.duplicate(true)
	var seen: Dictionary = {}
	var entries: Array = []
	for raw_id: Variant in card_ids:
		var cid: String = String(raw_id)
		if seen.has(cid):
			return state.duplicate(true)
		seen[cid] = true
		var preview: Dictionary = _find_in_hand(actor, cid)
		var learned := false
		if preview.is_empty():
			preview = _find_learned_miracle(actor, cid)
			learned = not preview.is_empty()
		if preview.is_empty() or not _can_play_in_action(preview):
			return state.duplicate(true)
		entries.append({"id": cid, "preview": preview, "learned": learned})
	var attack_entries: Array = []
	var buff_entries: Array = []
	var other_entries: Array = []
	for entry: Dictionary in entries:
		var preview: Dictionary = entry["preview"]
		if _card_has_context_effect(preview, "attack", "action"):
			attack_entries.append(entry)
		elif _card_has_context_effect(preview, "buff", "action"):
			buff_entries.append(entry)
		else:
			other_entries.append(entry)
	# 攻撃カードは1枚まで。攻撃・攻撃アップに他の効果は混ぜられない。
	if attack_entries.size() > 1:
		return state.duplicate(true)
	if not attack_entries.is_empty() or not buff_entries.is_empty():
		if not other_entries.is_empty():
			return state.duplicate(true)
		return _play_offensive(actor_peer_id, attack_entries, buff_entries, target_peer_id)
	# 攻撃を含まないなら、回復・防御・反射などを1枚だけ単発で出す。
	if entries.size() != 1:
		return state.duplicate(true)
	return _play_single_effect(actor_peer_id, other_entries[0], target_peer_id)

# 手札／習得奇跡からカードを取り出し、消費（捨て札 or 奇跡習得）して返す。
# 習得済み奇跡は消費されず複製を返す。山札からの補充は呼び出し側でまとめて行う。
func _consume_card(actor: Dictionary, entry: Dictionary) -> Dictionary:
	if bool(entry.get("learned", false)):
		return (entry["preview"] as Dictionary).duplicate(true)
	var card: Dictionary = _take_from_hand(actor, String(entry["id"]))
	if String(card.get("type", "")) == "miracle":
		actor["learned_miracles"].append(card.duplicate(true))
	else:
		state["discard"].append(card)
	return card

func _play_offensive(actor_peer_id: int, attack_entries: Array, buff_entries: Array, target_peer_id: int) -> Dictionary:
	var actor: Dictionary = _player(actor_peer_id)
	var owned_before: int = _owned_card_count(actor)
	# 攻撃カードがあればそれを主役に、無ければ最初の攻撃アップを主役にする。
	# 主役から属性と対象（敵1体／敵全体）を決める。威力は全カードの合計。
	var primary_preview: Dictionary = attack_entries[0]["preview"] if not attack_entries.is_empty() else buff_entries[0]["preview"]
	var primary_effect_name: String = "attack" if not attack_entries.is_empty() else "buff"
	var primary_effect: Dictionary = _first_context_effect(primary_preview, "action", primary_effect_name)
	var card_target: String = String(primary_effect.get("target", primary_preview.get("target", "enemy")))
	# 光は他属性の代わりになる。光以外の属性が複数混ざった時だけ無属性化する。
	var offensive_previews: Array = []
	for attr_entry: Dictionary in (attack_entries + buff_entries):
		offensive_previews.append(attr_entry["preview"])
	var card_attribute: String = _combined_offensive_attribute(offensive_previews)
	# 敵1体を狙うなら、カードを消費する前に対象の生存を確認する。
	if card_target != "all_enemies":
		var single_target: Dictionary = _player(target_peer_id)
		if single_target.is_empty() or not bool(single_target.get("alive", false)):
			return state.duplicate(true)
	var offensive_cards: Array = []
	var ordinary_cards_consumed := 0
	var miracle_cards_used := 0
	for entry: Dictionary in (attack_entries + buff_entries):
		if String(entry["preview"].get("type", "")) == "miracle":
			miracle_cards_used += 1
		elif not bool(entry.get("learned", false)):
			ordinary_cards_consumed += 1
		offensive_cards.append(_consume_card(actor, entry))
	_draw_to_hand(actor_peer_id)
	_draw_until_owned_count(
		actor_peer_id,
		owned_before - ordinary_cards_consumed + miracle_cards_used
	)
	var total_power := 0
	var card_names: Array = []
	for played_card: Dictionary in offensive_cards:
		total_power += _nominal_offensive_power(played_card)
		card_names.append(String(played_card.get("name", "")))
	card_attribute = _combined_offensive_attribute(offensive_cards)
	var combo_name: String = "＋".join(card_names)
	var strike_card: Dictionary = offensive_cards[0].duplicate(true)
	strike_card["power"] = total_power
	strike_card["attribute"] = card_attribute
	if card_target == "all_enemies":
		var mt_targets: Array = []
		for raw_id: Variant in state.get("player_order", []):
			var p: Dictionary = _player(int(raw_id))
			if not p.is_empty() and int(p["peer_id"]) != actor_peer_id and bool(p.get("alive", false)):
				mt_targets.append(int(p["peer_id"]))
		if mt_targets.is_empty():
			state["log"].append("%sは%sを使ったが、対象がいなかった。" % [actor["name"], combo_name])
			_advance_turn()
		else:
			state["multi_attack_queue"] = {
				"card": strike_card,
				"card_name": combo_name,
				"attack_cards": offensive_cards.duplicate(true),
				"attacker_peer_id": actor_peer_id,
				"index": 0,
				"targets": mt_targets,
			}
			_start_next_multi_attack()
		return state.duplicate(true)
	_start_attack_for_target(actor_peer_id, target_peer_id, offensive_cards, combo_name)
	return state.duplicate(true)

func _nominal_offensive_power(card: Dictionary) -> int:
	var values: Array[int] = []
	for effect_entry: Dictionary in _effects_for_context(card, "action"):
		if String(effect_entry.get("effect", "")) in ["attack", "buff"]:
			values.append(int(effect_entry.get("power", 0)))
	if String(card.get("effect_mode", "all")) == "random_one":
		var strongest := 0
		for value: int in values:
			strongest = maxi(strongest, value)
		return strongest
	var total := 0
	for value: int in values:
		total += value
	return total

func _start_attack_for_target(
	actor_peer_id: int,
	target_peer_id: int,
	attack_cards: Array,
	combo_name: String
) -> void:
	var actor: Dictionary = _player(actor_peer_id)
	var target: Dictionary = _player(target_peer_id)
	if actor.is_empty() or target.is_empty() or not bool(target.get("alive", false)):
		state["phase"] = "result"
		return
	var attack_power := 0
	var active_side_effects: Array = []
	var active_cards: Array = []
	var active_attributes: Array = []
	for raw_card: Variant in attack_cards:
		if not (raw_card is Dictionary):
			continue
		var card: Dictionary = raw_card
		var rolled_effects: Array = _roll_card_effects(card, "action")
		if rolled_effects.is_empty():
			continue
		var card_contributed := false
		for effect_entry: Dictionary in rolled_effects:
			if String(effect_entry.get("effect", "")) in ["attack", "buff"]:
				attack_power += int(effect_entry.get("power", 0))
				card_contributed = true
			else:
				var side_effect: Dictionary = effect_entry.duplicate(true)
				side_effect["_card"] = card.duplicate(true)
				active_side_effects.append(side_effect)
		if card_contributed:
			active_cards.append(card.duplicate(true))
			active_attributes.append(_normalize_attribute(card.get("attribute", "none")))
	var card_attribute: String = _combined_attribute_values(active_attributes)
	var strike_card: Dictionary = attack_cards[0].duplicate(true)
	strike_card["power"] = attack_power
	strike_card["attribute"] = card_attribute
	if attack_power <= 0:
		var result_parts: Array[String] = []
		for effect_entry: Dictionary in active_side_effects:
			var text: String = _apply_effect_entry(actor, target, effect_entry, false)
			if not text.is_empty():
				result_parts.append(text)
		state["combat_view"] = {
			"status": "support_resolved",
			"attacker_peer_id": actor_peer_id,
			"attacker_name": String(actor.get("name", "")),
			"target_peer_id": target_peer_id,
			"target_name": String(target.get("name", "")),
			"attack_card": strike_card,
			"attack_cards": attack_cards.duplicate(true),
			"defense_cards": [],
			"attack_power": 0,
			"defense_power": 0,
			"damage": 0,
			"result_text": "・".join(result_parts) if not result_parts.is_empty() else "ミス",
			"hide_arrow": false,
		}
		state["log"].append("%sの%sは攻撃効果が発動しなかった。" % [actor["name"], combo_name])
		state["phase"] = "result"
		_update_alive_players()
		return
	var is_self_attack: bool = actor_peer_id == target_peer_id
	state["phase"] = "defense"
	state["pending_attack"] = {
		"attacker_peer_id": actor_peer_id,
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"card_name": combo_name,
		"card": strike_card,
		"attack_cards": attack_cards.duplicate(true),
		"active_attack_cards": active_cards,
		"side_effects": active_side_effects,
		"power": attack_power,
		"attribute": card_attribute,
		"effect": "attack",
		"arrow_direction": "left" if is_self_attack else "right",
	}
	state["combat_view"] = {
		"status": "defending",
		"attacker_peer_id": actor_peer_id,
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"attack_card": strike_card,
		"attack_cards": attack_cards.duplicate(true),
		"defense_cards": [],
		"attack_power": attack_power,
		"attack_attribute": card_attribute,
		"defense_power": 0,
		"defense_attribute": "none",
		"damage": 0,
		"arrow_direction": "left" if is_self_attack else "right",
		"hide_arrow": false,
	}
	state["log"].append("%sが%sで%sを攻撃（威力%d）。防御を選択中。" % [
		actor["name"], combo_name, target["name"], attack_power,
	])
	if is_self_attack:
		_resolve_pending_attack([])

func _play_single_effect(actor_peer_id: int, entry: Dictionary, target_peer_id: int) -> Dictionary:
	var actor: Dictionary = _player(actor_peer_id)
	var preview: Dictionary = entry["preview"]
	var action_effect: Dictionary = _first_context_effect(preview, "action")
	var card_target: String = String(action_effect.get("target", preview.get("target", "self")))
	if card_target != "all_players":
		var selected_target: Dictionary = _player(target_peer_id)
		if selected_target.is_empty() or not bool(selected_target.get("alive", false)):
			return state.duplicate(true)
	var owned_before: int = _owned_card_count(actor)
	var is_miracle: bool = String(preview.get("type", "")) == "miracle"
	var ordinary_cards_consumed: int = 0 if is_miracle or bool(entry.get("learned", false)) else 1
	var card: Dictionary = _consume_card(actor, entry)
	_draw_to_hand(actor_peer_id)
	_draw_until_owned_count(
		actor_peer_id,
		owned_before - ordinary_cards_consumed + (1 if is_miracle else 0)
	)
	if card_target == "all_players":
		var support_targets: Array = []
		for raw_peer_id: Variant in state.get("player_order", []):
			var recipient: Dictionary = _player(int(raw_peer_id))
			if not recipient.is_empty() and bool(recipient.get("alive", false)):
				support_targets.append(int(recipient["peer_id"]))
		state["multi_support_queue"] = {
			"attacker_peer_id": actor_peer_id,
			"card": card.duplicate(true),
			"targets": support_targets,
			"index": 0,
		}
		_start_next_multi_support()
		return state.duplicate(true)
	_start_support_for_target(actor_peer_id, target_peer_id, card)
	return state.duplicate(true)

func _start_support_for_target(actor_peer_id: int, target_peer_id: int, card: Dictionary) -> void:
	var actor: Dictionary = _player(actor_peer_id)
	var target: Dictionary = _player(target_peer_id)
	if actor.is_empty() or target.is_empty() or not bool(target.get("alive", false)):
		state["phase"] = "result"
		state["pending_attack"] = {}
		return
	var action_effect: Dictionary = _first_context_effect(card, "action")
	var action_power: int = int(action_effect.get("power", card.get("power", 0)))
	var action_effect_name: String = String(action_effect.get("effect", card.get("effect", "")))
	state["phase"] = "defense"
	state["pending_attack"] = {
		"attacker_peer_id": actor_peer_id,
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"card_name": String(card.get("name", "")),
		"card": card.duplicate(true),
		"power": action_power,
		"attribute": String(card.get("attribute", "none")),
		"effect": action_effect_name,
		"arrow_direction": "left" if actor_peer_id == target_peer_id else "right",
	}
	state["combat_view"] = {
		"status": "support_pending",
		"attacker_peer_id": actor_peer_id,
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"attack_card": card.duplicate(true),
		"attack_cards": [card.duplicate(true)],
		"defense_cards": [],
		"attack_power": action_power,
		"attack_attribute": String(card.get("attribute", "none")),
		"defense_power": 0,
		"defense_attribute": "none",
		"damage": -1,
		"arrow_direction": "left" if actor_peer_id == target_peer_id else "right",
		"hide_arrow": actor_peer_id == target_peer_id,
	}
	if actor_peer_id == target_peer_id:
		_resolve_pending_support([])
	else:
		state["log"].append("%sが%sへ%sを使用。完全反射を選択中。" % [
			actor.get("name", ""), target.get("name", ""), card.get("name", ""),
		])

func _resolve_pending_support(defense_cards: Array) -> void:
	var pending: Dictionary = state.get("pending_attack", {})
	var actor: Dictionary = _player(int(pending.get("attacker_peer_id", 0)))
	var original_target: Dictionary = _player(int(pending.get("target_peer_id", 0)))
	var card: Dictionary = pending.get("card", {})
	if actor.is_empty() or original_target.is_empty() or card.is_empty():
		state["pending_attack"] = {}
		state["phase"] = "result"
		return
	var reflected := false
	for defense_card: Dictionary in defense_cards:
		for defense_effect: Dictionary in _roll_card_effects(defense_card, "defense"):
			if String(defense_effect.get("effect", "")) == "reflect" and _is_full_reflect_card(defense_card):
				reflected = true
			elif String(defense_effect.get("effect", "")) in ["heal", "guard", "instant_death"]:
				_apply_effect_entry(original_target, original_target, defense_effect, false, defense_card)
	var receiver: Dictionary = actor if reflected else original_target
	var result_parts: Array[String] = []
	var rolled_effects: Array = _roll_card_effects(card, "action")
	for effect_entry: Dictionary in rolled_effects:
		var effect_result: String = _apply_effect_entry(actor, original_target, effect_entry, reflected, card)
		if not effect_result.is_empty():
			result_parts.append(effect_result)
	var result_text: String = "・".join(result_parts) if not result_parts.is_empty() else "ミス"
	if reflected:
		state["log"].append("%sが%sを完全反射し、%sへ返した。" % [
			original_target.get("name", ""), card.get("name", ""), actor.get("name", ""),
		])
	state["combat_view"] = {
		"status": "support_resolved",
		"attacker_peer_id": int(actor.get("peer_id", 0)),
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": int(receiver.get("peer_id", 0)),
		"target_name": String(receiver.get("name", "")),
		"original_target_peer_id": int(original_target.get("peer_id", 0)),
		"attack_card": card.duplicate(true),
		"attack_cards": [card.duplicate(true)],
		"defense_cards": defense_cards.duplicate(true),
		"attack_power": int(pending.get("power", card.get("power", 0))),
		"attack_attribute": String(card.get("attribute", "none")),
		"defense_power": 0,
		"defense_attribute": "none",
		"damage": -1,
		"result_text": result_text,
		"reflected": reflected,
		"arrow_direction": "left" if reflected else String(pending.get("arrow_direction", "right")),
		"hide_arrow": int(receiver.get("peer_id", 0)) == int(actor.get("peer_id", 0)),
	}
	state["pending_attack"] = {}
	state["phase"] = "result"

func _apply_effect_entry(
	actor: Dictionary,
	selected_target: Dictionary,
	effect_entry: Dictionary,
	reflected: bool,
	source_card: Dictionary = {}
) -> String:
	var receiver: Dictionary = selected_target
	var effect_index: int = int(effect_entry.get("_index", 0))
	var effect_target: String = String(effect_entry.get("target", source_card.get("target", "self")))
	var random_mode: bool = String(source_card.get("effect_mode", "all")) == "random_one"
	if not random_mode and effect_index > 0 and effect_target == "self":
		receiver = actor
	if reflected and int(receiver.get("peer_id", 0)) == int(selected_target.get("peer_id", 0)):
		receiver = actor
	var effect_name: String = String(effect_entry.get("effect", ""))
	var power: int = int(effect_entry.get("power", 0))
	var hp_before: int = int(receiver.get("hp", 0))
	match effect_name:
		"attack", "buff":
			receiver["hp"] = maxi(0, int(receiver.get("hp", 0)) - maxi(0, power))
			_update_alive_players()
			return "%s %dダメージ" % [receiver.get("name", ""), hp_before - int(receiver.get("hp", 0))]
		"instant_death":
			receiver["hp"] = 0
			_update_alive_players()
			return "%s 即死" % receiver.get("name", "")
		"heal":
			receiver["hp"] = clampi(int(receiver.get("hp", 0)) + power, 0, START_HP)
			_update_alive_players()
			return "%s HP %s" % [
				receiver.get("name", ""),
				_signed_number(int(receiver.get("hp", 0)) - hp_before),
			]
		"guard":
			if power >= int(receiver.get("guard", 0)):
				receiver["guard"] = power
				receiver["guard_attribute"] = _normalize_attribute(source_card.get("attribute", "none"))
			return "%s 防御+%d" % [receiver.get("name", ""), power]
		"reflect":
			if power >= int(receiver.get("guard", 0)):
				receiver["guard"] = power
				receiver["guard_attribute"] = _normalize_attribute(source_card.get("attribute", "none"))
			receiver["reflect"] = true
			return "%s 反射準備" % receiver.get("name", "")
	return ""

func pass_defense(actor_peer_id: int) -> Dictionary:
	if String(state.get("phase", "")) != "defense":
		return state.duplicate(true)
	var pending: Dictionary = state.get("pending_attack", {})
	if int(pending.get("target_peer_id", 0)) != actor_peer_id:
		return state.duplicate(true)
	_resolve_pending_attack([])
	return state.duplicate(true)

func pass_action(actor_peer_id: int) -> Dictionary:
	if String(state.get("phase", "")) != "action" or actor_peer_id != _current_peer_id():
		return state.duplicate(true)
	var actor: Dictionary = _player(actor_peer_id)
	if actor.is_empty() or not bool(actor.get("alive", false)):
		return state.duplicate(true)
	state["log"].append("%sは行動できず、ターンを終了。" % actor["name"])
	_advance_turn()
	return state.duplicate(true)

func pray(actor_peer_id: int) -> Dictionary:
	if state.is_empty() or String(state.get("phase", "")) != "action":
		return state.duplicate(true)
	var actor: Dictionary = _player(actor_peer_id)
	if actor.is_empty() or not bool(actor.get("alive", false)) or actor_peer_id != _current_peer_id():
		return state.duplicate(true)
	if _has_offensive_card(actor):
		return state.duplicate(true)
	var drew_card: bool = _draw_one_card(actor_peer_id)
	if drew_card:
		state["log"].append("%sが祈り、カードを1枚引いた。" % actor["name"])
	else:
		state["log"].append("%sが祈ったが、カードは増えなかった。" % actor["name"])
	state["combat_view"] = {}
	_advance_turn()
	return state.duplicate(true)

func play_defense_cards(actor_peer_id: int, card_ids: Array) -> Dictionary:
	var pending: Dictionary = state.get("pending_attack", {})
	if String(state.get("phase", "")) != "defense" or int(pending.get("target_peer_id", 0)) != actor_peer_id:
		return state.duplicate(true)
	var defender: Dictionary = _player(actor_peer_id)
	var hand_copy: Array = defender.get("hand", []).duplicate(true)
	var defense_cards: Array = []
	for raw_card_id: Variant in card_ids:
		var card_id: String = String(raw_card_id)
		var found_index := -1
		for index: int in range(hand_copy.size()):
			if (
				String(hand_copy[index].get("id", "")) == card_id
				and can_respond_with_card(pending, hand_copy[index])
			):
				found_index = index
				break
		if found_index < 0:
			return state.duplicate(true)
		defense_cards.append(hand_copy.pop_at(found_index))
	if defense_cards.is_empty():
		return state.duplicate(true)
	defender["hand"] = hand_copy
	for defense_card: Dictionary in defense_cards:
		state["discard"].append(defense_card)
	_draw_to_hand(actor_peer_id)
	_resolve_pending_attack(defense_cards)
	return state.duplicate(true)

func _resolve_pending_attack(defense_cards: Array) -> void:
	var pending: Dictionary = state.get("pending_attack", {})
	if String(pending.get("effect", "attack")) not in ["attack", "buff"]:
		_resolve_pending_support(defense_cards)
		return
	var attacker: Dictionary = _player(int(pending.get("attacker_peer_id", 0)))
	var target: Dictionary = _player(int(pending.get("target_peer_id", 0)))
	if attacker.is_empty() or target.is_empty():
		state["phase"] = "action"
		state["pending_attack"] = {}
		return
	var attack_power: int = int(pending.get("power", 0))
	var attack_attribute: String = _normalize_attribute(pending.get("attribute", "none"))
	var defense_power := 0
	var defense_attributes: Array[String] = []
	var counter_power := 0
	var counter_cards: Array = []
	var defense_side_effects: Array = []
	var has_reflect := false
	var has_full_reflect := false
	var stored_guard: int = int(target.get("guard", 0))
	if stored_guard > 0:
		var stored_attribute: String = _normalize_attribute(target.get("guard_attribute", "none"))
		if _attribute_can_defend(attack_attribute, stored_attribute):
			defense_power += stored_guard
			defense_attributes.append(stored_attribute)
			if bool(target.get("reflect", false)):
				has_reflect = true
			state["log"].append("%sの事前の防御準備（%d）が発動。" % [target["name"], stored_guard])
		else:
			state["log"].append("%sの事前の防御準備は属性が合わず発動しなかった。" % target["name"])
	target["guard"] = 0
	target["guard_attribute"] = "none"
	target["reflect"] = false
	for raw_card: Variant in defense_cards:
		if raw_card is Dictionary:
			var defense_card: Dictionary = raw_card
			var dc_attribute: String = _normalize_attribute(defense_card.get("attribute", "none"))
			for effect_entry: Dictionary in _roll_card_effects(defense_card, "defense"):
				var dc_effect: String = String(effect_entry.get("effect", "guard"))
				var dc_power: int = int(effect_entry.get("power", 0))
				match dc_effect:
					"attack":
						counter_power += dc_power
						if defense_card not in counter_cards:
							counter_cards.append(defense_card)
					"guard":
						defense_power += dc_power
						defense_attributes.append(dc_attribute)
					"reflect":
						defense_power += dc_power
						defense_attributes.append(dc_attribute)
						has_reflect = true
						if _is_full_reflect_card(defense_card):
							has_full_reflect = true
					"heal", "instant_death":
						var defense_side_effect: Dictionary = effect_entry.duplicate(true)
						defense_side_effect["_card"] = defense_card
						defense_side_effects.append(defense_side_effect)
	if has_full_reflect:
		defense_power = maxi(defense_power, attack_power)
	var defense_attribute: String = _combined_defense_attribute(defense_attributes)
	var damage: int = maxi(0, attack_power - defense_power)
	if attack_attribute == "dark" and damage > 0:
		damage = int(target.get("hp", 0))
		target["hp"] = 0
	else:
		target["hp"] = int(target["hp"]) - damage
	if defense_cards.is_empty():
		if stored_guard > 0:
			state["log"].append("%sは事前の防御で受け、%dダメージ。" % [target["name"], damage])
		else:
			state["log"].append("%sは防御せず、%dダメージ。" % [target["name"], damage])
	else:
		state["log"].append("%sは防具%d枚で防御し、%dダメージ。" % [target["name"], defense_cards.size(), damage])
	if has_reflect:
		var reflected_damage: int = attack_power if has_full_reflect else mini(attack_power, defense_power)
		attacker["hp"] = int(attacker["hp"]) - reflected_damage
		state["log"].append("%sへ%dダメージを反射。" % [attacker["name"], reflected_damage])
	for defense_side_effect: Dictionary in defense_side_effects:
		_apply_effect_entry(
			target,
			target,
			defense_side_effect,
			false,
			defense_side_effect.get("_card", {})
		)
	for side_effect: Dictionary in pending.get("side_effects", []):
		var side_card: Dictionary = side_effect.get("_card", {})
		_apply_effect_entry(attacker, target, side_effect, has_full_reflect, side_card)
	if not defense_cards.is_empty():
		if counter_power > 0:
			var counter_card: Dictionary = {}
			var counter_names: Array = []
			for raw_card: Variant in counter_cards:
				if counter_card.is_empty():
					counter_card = (raw_card as Dictionary).duplicate(true)
				counter_names.append(String(raw_card.get("name", "反撃")))
			state["pending_counter_attack"] = {
				"attacker_peer_id": int(target["peer_id"]),
				"attacker_name": String(target["name"]),
				"target_peer_id": int(attacker["peer_id"]),
				"target_name": String(attacker["name"]),
				"power": counter_power,
				"card": counter_card,
				"card_name": "・".join(counter_names),
				"arrow_direction": "right",
			}
			state["log"].append("%sが反撃の準備！" % target["name"])
	state["combat_view"] = {
		"status": "resolved",
		"attacker_peer_id": int(pending.get("attacker_peer_id", 0)),
		"attacker_name": String(attacker["name"]),
		"target_peer_id": int(target["peer_id"]),
		"target_name": String(target["name"]),
		"attack_card": pending.get("card", {}).duplicate(true),
		"attack_cards": pending.get("attack_cards", [pending.get("card", {})]).duplicate(true),
		"defense_cards": defense_cards.duplicate(true),
		"attack_power": attack_power,
		"attack_attribute": attack_attribute,
		"defense_power": defense_power,
		"defense_attribute": defense_attribute,
		"damage": damage,
		"arrow_direction": String(pending.get("arrow_direction", "right")),
		"hide_arrow": false,
	}
	state["phase"] = "result"
	state["pending_attack"] = {}
	_update_alive_players()

func continue_after_result() -> Dictionary:
	if String(state.get("phase", "")) != "result":
		return state.duplicate(true)
	if _check_game_over():
		return state.duplicate(true)
	var counter: Dictionary = state.get("pending_counter_attack", {})
	if not counter.is_empty():
		state["pending_counter_attack"] = {}
		_start_counter_attack(counter)
		return state.duplicate(true)
	var support_queue: Dictionary = state.get("multi_support_queue", {})
	if not support_queue.is_empty():
		support_queue["index"] = int(support_queue.get("index", 0)) + 1
		_start_next_multi_support()
		return state.duplicate(true)
	var queue: Dictionary = state.get("multi_attack_queue", {})
	if not queue.is_empty():
		queue["index"] = int(queue.get("index", 0)) + 1
		_start_next_multi_attack()
		return state.duplicate(true)
	state["phase"] = "action"
	_advance_turn()
	return state.duplicate(true)

func _resolve_card(actor: Dictionary, target: Dictionary, card: Dictionary) -> void:
	var effect: String = String(card.get("effect", "attack"))
	var power: int = int(card.get("power", 0))
	match effect:
		"heal":
			target["hp"] = clampi(int(target["hp"]) + power, 0, START_HP)
			if power < 0:
				state["log"].append("%sの%sで%sがダメージ。" % [actor["name"], card["name"], target["name"]])
			elif int(target.get("peer_id", 0)) == int(actor.get("peer_id", 0)):
				state["log"].append("%sが%sでHP回復。" % [actor["name"], card["name"]])
			else:
				state["log"].append("%sの%sで%sがHP回復。" % [actor["name"], card["name"], target["name"]])
		"guard":
			if power >= int(target.get("guard", 0)):
				target["guard"] = power
				target["guard_attribute"] = _normalize_attribute(card.get("attribute", "none"))
			state["log"].append("%sの%sで%sが防御準備。" % [actor["name"], card["name"], target["name"]])
		"reflect":
			if power >= int(target.get("guard", 0)):
				target["guard"] = power
				target["guard_attribute"] = _normalize_attribute(card.get("attribute", "none"))
			target["reflect"] = true
			state["log"].append("%sの%sで%sが反射準備。" % [actor["name"], card["name"], target["name"]])
	_update_alive_players()

func _signed_number(value: int) -> String:
	return "+%d" % value if value >= 0 else str(value)

func _normalize_attribute(raw_attribute: Variant) -> String:
	var attribute: String = String(raw_attribute)
	return attribute if attribute in VALID_ATTRIBUTES else "none"

func _card_effects(card: Dictionary) -> Array:
	var effects: Variant = card.get("effects", [])
	if effects is Array and not effects.is_empty():
		return effects
	return [{
		"effect": String(card.get("effect", "attack")),
		"power": int(card.get("power", 0)),
		"target": String(card.get("target", "enemy")),
		"chance": 100,
		"weight": 1,
	}]

func _card_has_effect(card: Dictionary, effect_name: String) -> bool:
	for effect_entry: Dictionary in _card_effects(card):
		if String(effect_entry.get("effect", "")) == effect_name:
			return true
	return false

func _effects_for_context(card: Dictionary, context: String) -> Array:
	var effects: Array = _card_effects(card)
	var preferred_names: Array[String] = []
	var fallback_names: Array[String] = []
	if context == "action":
		preferred_names = ["attack", "buff", "heal", "instant_death"]
		fallback_names = ["guard", "reflect"]
	elif context == "defense":
		preferred_names = ["guard", "reflect"]
		if String(card.get("type", "")) == "armor":
			fallback_names = ["attack"]
	else:
		return effects
	var preferred: Array = []
	var fallback: Array = []
	for effect_entry: Dictionary in effects:
		var effect_name: String = String(effect_entry.get("effect", ""))
		if effect_name in preferred_names:
			preferred.append(effect_entry)
		elif effect_name in fallback_names:
			fallback.append(effect_entry)
	return preferred if not preferred.is_empty() else fallback

func _card_has_context_effect(card: Dictionary, effect_name: String, context: String) -> bool:
	for effect_entry: Dictionary in _effects_for_context(card, context):
		if String(effect_entry.get("effect", "")) == effect_name:
			return true
	return false

func _first_context_effect(card: Dictionary, context: String, effect_name: String = "") -> Dictionary:
	var effects: Array = _effects_for_context(card, context)
	for effect_entry: Dictionary in effects:
		if effect_name.is_empty() or String(effect_entry.get("effect", "")) == effect_name:
			return effect_entry
	return effects[0] if not effects.is_empty() else {}

func _can_play_in_action(card: Dictionary) -> bool:
	if String(card.get("type", "")) != "armor":
		return not _effects_for_context(card, "action").is_empty()
	for effect_entry: Dictionary in _card_effects(card):
		if String(effect_entry.get("effect", "")) in ["attack", "buff", "heal", "instant_death"]:
			return true
	return false

func _roll_card_effects(card: Dictionary, context: String = "all") -> Array:
	if rng.randi_range(1, 100) > clampi(int(card.get("chance", 100)), 0, 100):
		return []
	var effects: Array = _effects_for_context(card, context)
	if effects.is_empty():
		return []
	var candidates: Array = []
	if String(card.get("effect_mode", "all")) == "random_one":
		var total_weight := 0
		for effect_entry: Dictionary in effects:
			total_weight += maxi(1, int(effect_entry.get("weight", 1)))
		if total_weight <= 0:
			return []
		var pick: int = rng.randi_range(1, total_weight)
		var running := 0
		for index: int in range(effects.size()):
			var effect_entry: Dictionary = effects[index]
			running += maxi(1, int(effect_entry.get("weight", 1)))
			if pick <= running:
				var chosen: Dictionary = effect_entry.duplicate(true)
				chosen["_index"] = index
				candidates.append(chosen)
				break
	else:
		for index: int in range(effects.size()):
			var copied: Dictionary = (effects[index] as Dictionary).duplicate(true)
			copied["_index"] = index
			candidates.append(copied)
	var activated: Array = []
	for effect_entry: Dictionary in candidates:
		if rng.randi_range(1, 100) <= clampi(int(effect_entry.get("chance", 100)), 0, 100):
			activated.append(effect_entry)
	return activated

func _combined_offensive_attribute(cards: Array) -> String:
	if cards.is_empty():
		return "none"
	var combined := ""
	var has_light := false
	for card: Dictionary in cards:
		var attribute: String = _normalize_attribute(card.get("attribute", "none"))
		if attribute == "light":
			has_light = true
			continue
		if combined.is_empty():
			combined = attribute
		elif attribute != combined:
			return "none"
	if not combined.is_empty():
		return combined
	return "light" if has_light else "none"

func _combined_attribute_values(attributes: Array) -> String:
	if attributes.is_empty():
		return "none"
	var combined := ""
	var has_light := false
	for raw_attribute: Variant in attributes:
		var attribute: String = _normalize_attribute(raw_attribute)
		if attribute == "light":
			has_light = true
			continue
		if combined.is_empty():
			combined = attribute
		elif combined != attribute:
			return "none"
	return combined if not combined.is_empty() else ("light" if has_light else "none")

func _combined_defense_attribute(attributes: Array[String]) -> String:
	if attributes.is_empty():
		return "none"
	var combined: String = attributes[0]
	for attribute: String in attributes:
		if attribute != combined:
			return "mixed"
	return combined

func can_defend_with_card(attack_attribute: String, card: Dictionary) -> bool:
	return (
		not _effects_for_context(card, "defense").is_empty()
		and _attribute_can_defend(
			_normalize_attribute(attack_attribute),
			_normalize_attribute(card.get("attribute", "none"))
		)
	)

func can_respond_with_card(pending: Dictionary, card: Dictionary) -> bool:
	if String(pending.get("effect", "attack")) in ["attack", "buff"]:
		return can_defend_with_card(String(pending.get("attribute", "none")), card)
	return _is_full_reflect_card(card)

func _is_full_reflect_card(card: Dictionary) -> bool:
	var tags: Array = card.get("tags", [])
	return (
		_card_has_effect(card, "reflect")
		and "full_reflect" in tags
	)

func _attribute_can_defend(attack_attribute: String, defense_attribute: String) -> bool:
	match _normalize_attribute(attack_attribute):
		"none", "dark":
			return true
		"fire":
			return defense_attribute in ["water", "light"]
		"water":
			return defense_attribute in ["fire", "light"]
		"wood":
			return defense_attribute in ["earth", "light"]
		"earth":
			return defense_attribute in ["wood", "light"]
		"light":
			return false
	return false

func _build_draw_pile(deck: Array) -> Array:
	var pile: Array = []
	for card: Variant in deck:
		if not (card is Dictionary):
			continue
		var copies: int = 8
		match String(card.get("rarity", "common")):
			"uncommon":
				copies = 5
			"rare":
				copies = 3
			"legendary":
				copies = 1
		for _i in range(copies):
			pile.append((card as Dictionary).duplicate(true))
	for index: int in range(pile.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temporary: Variant = pile[index]
		pile[index] = pile[swap_index]
		pile[swap_index] = temporary
	return pile

func _draw_to_hand(peer_id: int) -> void:
	var player: Dictionary = _player(peer_id)
	while player["hand"].size() < HAND_SIZE and _owned_card_count(player) < MAX_CARD_COUNT:
		if not _draw_one_card(peer_id):
			break

func _draw_until_owned_count(peer_id: int, target_count: int) -> void:
	var player: Dictionary = _player(peer_id)
	var capped_target: int = mini(MAX_CARD_COUNT, target_count)
	while _owned_card_count(player) < capped_target:
		if not _draw_one_card(peer_id):
			break

func _draw_one_card(peer_id: int) -> bool:
	var player: Dictionary = _player(peer_id)
	if player.is_empty() or _owned_card_count(player) >= MAX_CARD_COUNT:
		return false
	if state["deck"].is_empty():
		if state["discard"].is_empty():
			return false
		state["deck"] = state["discard"].duplicate()
		state["discard"] = []
		for index: int in range(state["deck"].size() - 1, 0, -1):
			var swap_index: int = rng.randi_range(0, index)
			var temporary: Variant = state["deck"][index]
			state["deck"][index] = state["deck"][swap_index]
			state["deck"][swap_index] = temporary
		state["log"].append("山札が尽きたので捨て札をシャッフルして補充。")
	if state["deck"].is_empty():
		return false
	player["hand"].append(state["deck"].pop_back())
	return true

func _owned_card_count(player: Dictionary) -> int:
	return player.get("hand", []).size() + player.get("learned_miracles", []).size()

func _has_offensive_card(player: Dictionary) -> bool:
	for zone_name: String in ["hand", "learned_miracles"]:
		for raw_card: Variant in player.get(zone_name, []):
			if (
				raw_card is Dictionary
				and (
					_card_has_context_effect(raw_card, "attack", "action")
					or _card_has_context_effect(raw_card, "buff", "action")
				)
			):
				return true
	return false

func _take_from_hand(player: Dictionary, card_id: String) -> Dictionary:
	for index in range(player["hand"].size()):
		if String(player["hand"][index].get("id", "")) == card_id:
			return player["hand"].pop_at(index)
	return {}

func _find_in_hand(player: Dictionary, card_id: String) -> Dictionary:
	for raw_card: Variant in player.get("hand", []):
		if raw_card is Dictionary:
			var card: Dictionary = raw_card
			if String(card.get("id", "")) == card_id:
				return card
	return {}

func _find_learned_miracle(player: Dictionary, card_id: String) -> Dictionary:
	for raw_card: Variant in player.get("learned_miracles", []):
		if raw_card is Dictionary:
			var card: Dictionary = raw_card
			if String(card.get("id", "")) == card_id:
				return card
	return {}

func _start_counter_attack(counter: Dictionary) -> void:
	var attacker_peer_id: int = int(counter.get("attacker_peer_id", 0))
	var target_peer_id: int = int(counter.get("target_peer_id", 0))
	var attacker: Dictionary = _player(attacker_peer_id)
	var target: Dictionary = _player(target_peer_id)
	if attacker.is_empty() or not bool(attacker.get("alive", false)) \
			or target.is_empty() or not bool(target.get("alive", false)):
		var queue: Dictionary = state.get("multi_attack_queue", {})
		if not queue.is_empty():
			queue["index"] = int(queue.get("index", 0)) + 1
			_start_next_multi_attack()
		else:
			state["phase"] = "action"
			_advance_turn()
		return
	var power: int = int(counter.get("power", 0))
	var card: Dictionary = counter.get("card", {})
	state["phase"] = "defense"
	state["pending_attack"] = {
		"attacker_peer_id": attacker_peer_id,
		"attacker_name": String(attacker.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"card_name": String(counter.get("card_name", "反撃")),
		"card": card,
		"power": power,
		"attribute": String(card.get("attribute", "none")),
		"arrow_direction": "right",
	}
	state["combat_view"] = {
		"status": "defending",
		"attacker_peer_id": attacker_peer_id,
		"attacker_name": String(attacker.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"attack_card": card,
		"defense_cards": [],
		"attack_power": power,
		"attack_attribute": _normalize_attribute(card.get("attribute", "none")),
		"defense_power": 0,
		"defense_attribute": "none",
		"damage": 0,
		"arrow_direction": "right",
		"hide_arrow": false,
	}
	state["log"].append("%sが%sへ反撃（攻撃力 %d）！防御を選択中。" % [
		attacker.get("name", ""), target.get("name", ""), power
	])

func _start_next_multi_attack() -> void:
	var queue: Dictionary = state.get("multi_attack_queue", {})
	var attacker_peer_id: int = int(queue.get("attacker_peer_id", 0))
	var card: Dictionary = queue.get("card", {})
	var combo_name: String = String(queue.get("card_name", card.get("name", "")))
	var queue_attack_cards: Array = queue.get("attack_cards", [])
	var targets: Array = queue.get("targets", [])
	var index: int = int(queue.get("index", 0))
	while index < targets.size():
		var t: Dictionary = _player(int(targets[index]))
		if not t.is_empty() and bool(t.get("alive", false)):
			break
		index += 1
	queue["index"] = index
	if index >= targets.size():
		state["multi_attack_queue"] = {}
		state["phase"] = "action"
		_advance_turn()
		return
	var target_peer_id: int = int(targets[index])
	var cards_for_target: Array = queue_attack_cards if not queue_attack_cards.is_empty() else [card]
	_start_attack_for_target(attacker_peer_id, target_peer_id, cards_for_target, combo_name)
	state["log"].append("全体効果を%d/%d人目へ判定。" % [index + 1, targets.size()])

func _start_next_multi_support() -> void:
	var queue: Dictionary = state.get("multi_support_queue", {})
	var attacker_peer_id: int = int(queue.get("attacker_peer_id", 0))
	var card: Dictionary = queue.get("card", {})
	var targets: Array = queue.get("targets", [])
	var index: int = int(queue.get("index", 0))
	while index < targets.size():
		var target: Dictionary = _player(int(targets[index]))
		if not target.is_empty() and bool(target.get("alive", false)):
			break
		index += 1
	queue["index"] = index
	if index >= targets.size():
		state["multi_support_queue"] = {}
		state["phase"] = "action"
		_advance_turn()
		return
	_start_support_for_target(attacker_peer_id, int(targets[index]), card)
	state["log"].append("%sを%d/%d人目へ処理。" % [
		card.get("name", ""), index + 1, targets.size(),
	])

func _advance_turn() -> void:
	var ids: Array = state.get("player_order", [])
	if ids.is_empty():
		return
	for _i in range(ids.size()):
		state["turn"] = (int(state["turn"]) + 1) % ids.size()
		var current: Dictionary = _player(int(ids[int(state["turn"])]))
		if bool(current.get("alive", false)):
			return

func _current_peer_id() -> int:
	var ids: Array = state.get("player_order", [])
	if ids.is_empty():
		return 0
	return int(ids[int(state.get("turn", 0)) % ids.size()])

func drop_player(peer_id: int) -> Dictionary:
	if state.is_empty():
		return {}
	var player: Dictionary = _player(peer_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return state.duplicate(true)
	player["alive"] = false
	player["hp"] = 0
	state["log"].append("%sが切断した。" % player.get("name", "プレイヤー"))
	var pending: Dictionary = state.get("pending_attack", {})
	if String(state.get("phase", "")) == "defense" and int(pending.get("target_peer_id", 0)) == peer_id:
		_resolve_pending_attack([])
	elif String(state.get("phase", "")) == "action":
		if _check_game_over():
			return state.duplicate(true)
		if _current_peer_id() == peer_id:
			_advance_turn()
	return state.duplicate(true)

func _check_game_over() -> bool:
	if String(state.get("phase", "")) == "game_over":
		return true
	var alive_players: Array = []
	for key: Variant in state["players"].keys():
		var player: Dictionary = state["players"][key]
		if bool(player.get("alive", false)):
			alive_players.append(player)
	if alive_players.size() > 1:
		return false
	state["phase"] = "game_over"
	state["pending_attack"] = {}
	state["pending_counter_attack"] = {}
	state["multi_attack_queue"] = {}
	if alive_players.size() == 1:
		state["winner_name"] = String(alive_players[0].get("name", "勝者"))
		state["log"].append("%sの勝利！" % state["winner_name"])
	else:
		state["winner_name"] = ""
		state["log"].append("生存者なし。引き分け。")
	return true

func _update_alive_players() -> void:
	for key: Variant in state["players"].keys():
		var player: Dictionary = state["players"][key]
		if int(player["hp"]) <= 0:
			player["hp"] = 0
			player["alive"] = false

func _player(peer_id: int) -> Dictionary:
	return state.get("players", {}).get(str(peer_id), {})
