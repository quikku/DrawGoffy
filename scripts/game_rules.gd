extends Node

const START_HP := 40
const MAX_HP := 99
const START_MP := 20
const MAX_MP := 99
const START_GOLD := 20
const MAX_GOLD := 99
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
		"repeat_attack_queue": {},
		"pending_counter_attack": {},
		"pending_reflections": [],
		"pending_purchase": {},
		"cost_death_peers": {},
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
			"mp": START_MP,
			"gold": START_GOLD,
			"alive": true,
			"hand": [],
			"learned_miracles": [],
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
	var entries: Array = []
	# カードIDはカード種類のIDであり、山札内の実体ごとに一意ではない。
	# 同じIDのカードを複数持てるため、ID重複ではなく所持枚数で検証する。
	var available_hand: Array = actor.get("hand", []).duplicate()
	var available_miracles: Array = actor.get("learned_miracles", []).duplicate()
	for raw_id: Variant in card_ids:
		var cid: String = String(raw_id)
		var preview: Dictionary = {}
		var learned := false
		for index: int in range(available_hand.size()):
			if String(available_hand[index].get("id", "")) == cid:
				preview = available_hand.pop_at(index)
				break
		if preview.is_empty():
			for index: int in range(available_miracles.size()):
				if String(available_miracles[index].get("id", "")) == cid:
					preview = available_miracles.pop_at(index)
					learned = true
					break
		if preview.is_empty():
			return state.duplicate(true)
		entries.append({"id": cid, "preview": preview, "learned": learned})
	var buy_entries: Array = entries.filter(func(entry: Dictionary) -> bool:
		return _card_has_context_effect(entry["preview"], "buy", "action")
	)
	var sell_entries: Array = entries.filter(func(entry: Dictionary) -> bool:
		return _card_has_context_effect(entry["preview"], "sell", "action")
	)
	var exchange_entries: Array = entries.filter(func(entry: Dictionary) -> bool:
		return _card_has_context_effect(entry["preview"], "exchange", "action")
	)
	if buy_entries.size() == 1 and entries.size() == 1:
		return _play_buy(actor_peer_id, buy_entries[0], target_peer_id)
	if sell_entries.size() == 1 and entries.size() >= 2:
		var merchandise_entries: Array = []
		for entry: Dictionary in entries:
			if entry != sell_entries[0]:
				merchandise_entries.append(entry)
		return _play_sell(
			actor_peer_id, sell_entries[0], merchandise_entries, target_peer_id
		)
	# 両替は配分値を伴う専用リクエストで確定する。
	if (
		not buy_entries.is_empty()
		or not sell_entries.is_empty()
		or not exchange_entries.is_empty()
	):
		return state.duplicate(true)
	for entry: Dictionary in entries:
		if not _can_play_in_action(entry["preview"]):
			return state.duplicate(true)
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
		return _play_offensive(actor_peer_id, attack_entries, buff_entries, entries, target_peer_id)
	# 攻撃を含まないなら、回復・防御・反射などを1枚だけ単発で出す。
	if entries.size() != 1:
		return state.duplicate(true)
	return _play_single_effect(actor_peer_id, other_entries[0], target_peer_id)

func _play_buy(actor_peer_id: int, trade_entry: Dictionary, target_peer_id: int) -> Dictionary:
	var buyer: Dictionary = _player(actor_peer_id)
	var seller: Dictionary = _player(target_peer_id)
	if (
		buyer.is_empty() or seller.is_empty()
		or actor_peer_id == target_peer_id
		or not bool(seller.get("alive", false))
		or seller.get("hand", []).is_empty()
	):
		return state.duplicate(true)
	var trade_card: Dictionary = trade_entry["preview"]
	if not _pay_card_costs(buyer, [trade_card]):
		return state.duplicate(true)
	_consume_card(buyer, trade_entry)
	_draw_one_card(actor_peer_id)
	_start_trade_defense(
		actor_peer_id,
		target_peer_id,
		trade_card,
		{"offer_count": maxi(1, int(trade_card.get("power", 1)))}
	)
	return state.duplicate(true)

func _begin_purchase_from_pending(pending: Dictionary) -> void:
	var buyer_peer_id: int = int(pending.get("attacker_peer_id", 0))
	var seller_peer_id: int = int(pending.get("target_peer_id", 0))
	var buyer: Dictionary = _player(buyer_peer_id)
	var seller: Dictionary = _player(seller_peer_id)
	var trade_card: Dictionary = pending.get("card", {})
	if buyer.is_empty() or seller.is_empty() or seller.get("hand", []).is_empty():
		_finish_failed_trade(pending, "購入対象なし")
		return
	var payload: Dictionary = pending.get("trade_payload", {})
	var offer_count: int = mini(
		maxi(1, int(payload.get("offer_count", trade_card.get("power", 1)))),
		seller["hand"].size()
	)
	var available_indices: Array[int] = []
	for index: int in range(seller["hand"].size()):
		available_indices.append(index)
	for index: int in range(available_indices.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temporary: int = available_indices[index]
		available_indices[index] = available_indices[swap_index]
		available_indices[swap_index] = temporary
	var offers: Array = []
	var total_price := 0
	for index: int in range(offer_count):
		var card_index: int = available_indices[index]
		var offered_card: Dictionary = seller["hand"][card_index]
		var offered_price: int = (
			0
			if String(offered_card.get("type", "")) == "miracle"
			else clampi(int(offered_card.get("price", 0)), 0, MAX_GOLD)
		)
		offers.append({
			"card_index": card_index,
			"card": offered_card.duplicate(true),
			"price": offered_price,
		})
		total_price += offered_price
	var offered_cards: Array = []
	for offer: Dictionary in offers:
		offered_cards.append((offer["card"] as Dictionary).duplicate(true))
	state["pending_purchase"] = {
		"buyer_peer_id": buyer_peer_id,
		"seller_peer_id": seller_peer_id,
		"offers": offers,
		"cards": offered_cards,
		"price": total_price,
	}
	state["pending_attack"] = {}
	state["phase"] = "purchase"
	state["log"].append("%sが%sのカード%d枚を買おうとしている。" % [
		buyer.get("name", ""), seller.get("name", ""), offer_count,
	])

func _start_trade_defense(
	attacker_peer_id: int,
	target_peer_id: int,
	trade_card: Dictionary,
	trade_payload: Dictionary
) -> void:
	var attacker: Dictionary = _player(attacker_peer_id)
	var target: Dictionary = _player(target_peer_id)
	var trade_effect: String = String(_first_context_effect(
		trade_card, "action"
	).get("effect", trade_card.get("effect", "")))
	state["phase"] = "defense"
	state["pending_attack"] = {
		"attacker_peer_id": attacker_peer_id,
		"attacker_name": String(attacker.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"card_name": String(trade_card.get("name", "")),
		"card": trade_card.duplicate(true),
		"attack_cards": [trade_card.duplicate(true)],
		"power": int(trade_card.get("power", 0)),
		"attribute": "none",
		"effect": trade_effect,
		"is_miracle": false,
		"arrow_direction": "right",
		"trade_payload": trade_payload.duplicate(true),
	}
	state["combat_view"] = {
		"status": "trade_pending",
		"attacker_peer_id": attacker_peer_id,
		"attacker_name": String(attacker.get("name", "")),
		"target_peer_id": target_peer_id,
		"target_name": String(target.get("name", "")),
		"attack_card": trade_card.duplicate(true),
		"attack_cards": [trade_card.duplicate(true)],
		"defense_cards": [],
		"attack_power": 0,
		"defense_power": 0,
		"damage": 0,
		"arrow_direction": "right",
		"hide_arrow": false,
	}
	state["log"].append("%sが%sへ%sを使用。完全反射を選択中。" % [
		attacker.get("name", ""), target.get("name", ""), trade_card.get("name", ""),
	])

func _resolve_pending_trade(defense_cards: Array) -> void:
	var pending: Dictionary = state.get("pending_attack", {})
	var attacker: Dictionary = _player(int(pending.get("attacker_peer_id", 0)))
	var target: Dictionary = _player(int(pending.get("target_peer_id", 0)))
	var trade_card: Dictionary = pending.get("card", {})
	if attacker.is_empty() or target.is_empty() or trade_card.is_empty():
		_finish_failed_trade(pending, "取引失敗")
		return
	var reflected := false
	var reflecting_card: Dictionary = {}
	for defense_card: Dictionary in defense_cards:
		for defense_effect: Dictionary in _roll_card_effects(defense_card, "defense"):
			if (
				String(defense_effect.get("effect", "")) == "reflect"
				and _is_full_reflect_card(defense_card)
			):
				reflected = true
				reflecting_card = defense_card
	if reflected:
		_queue_reflection(pending, reflecting_card)
		state["log"].append("%sが%sを完全反射し、%sへ返した。" % [
			target.get("name", ""), trade_card.get("name", ""), attacker.get("name", ""),
		])
		state["combat_view"] = {
			"status": "trade_result",
			"attacker_peer_id": int(attacker.get("peer_id", 0)),
			"attacker_name": String(attacker.get("name", "")),
			"target_peer_id": int(target.get("peer_id", 0)),
			"target_name": String(target.get("name", "")),
			"attack_card": trade_card.duplicate(true),
			"attack_cards": [trade_card.duplicate(true)],
			"defense_cards": defense_cards.duplicate(true),
			"damage": 0,
			"reflected": true,
			"result_text": "完全反射",
			"arrow_direction": "left",
			"hide_arrow": false,
		}
		state["pending_attack"] = {}
		state["phase"] = "result"
		return
	match String(pending.get("effect", "")):
		"buy":
			_begin_purchase_from_pending(pending)
		"sell":
			_finish_sell_from_pending(pending)
		_:
			_finish_failed_trade(pending, "取引失敗")

func _finish_failed_trade(pending: Dictionary, result_text: String) -> void:
	var attacker: Dictionary = _player(int(pending.get("attacker_peer_id", 0)))
	var target: Dictionary = _player(int(pending.get("target_peer_id", 0)))
	var trade_card: Dictionary = pending.get("card", {})
	state["combat_view"] = {
		"status": "trade_result",
		"attacker_peer_id": int(pending.get("attacker_peer_id", 0)),
		"attacker_name": String(attacker.get("name", "")),
		"target_peer_id": int(pending.get("target_peer_id", 0)),
		"target_name": String(target.get("name", "")),
		"attack_card": trade_card.duplicate(true),
		"attack_cards": [trade_card.duplicate(true)],
		"defense_cards": [],
		"damage": 0,
		"result_text": result_text,
		"hide_arrow": false,
	}
	state["pending_attack"] = {}
	state["phase"] = "result"

func resolve_purchase(buyer_peer_id: int, accept: bool) -> Dictionary:
	if String(state.get("phase", "")) != "purchase":
		return state.duplicate(true)
	var pending: Dictionary = state.get("pending_purchase", {})
	if int(pending.get("buyer_peer_id", 0)) != buyer_peer_id:
		return state.duplicate(true)
	var buyer: Dictionary = _player(buyer_peer_id)
	var seller: Dictionary = _player(int(pending.get("seller_peer_id", 0)))
	var price: int = clampi(int(pending.get("price", 0)), 0, MAX_GOLD)
	var offers: Array = pending.get("offers", [])
	var bought := false
	var valid_offer := not offers.is_empty()
	var offered_indices: Array[int] = []
	for raw_offer: Variant in offers:
		if not (raw_offer is Dictionary):
			valid_offer = false
			break
		var offer: Dictionary = raw_offer
		var card_index: int = int(offer.get("card_index", -1))
		if (
			card_index < 0
			or card_index >= seller.get("hand", []).size()
			or card_index in offered_indices
			or String(seller["hand"][card_index].get("id", ""))
				!= String(offer.get("card", {}).get("id", ""))
		):
			valid_offer = false
			break
		offered_indices.append(card_index)
	if (
		accept
		and not buyer.is_empty()
		and not seller.is_empty()
		and int(buyer.get("gold", 0)) >= price
		and valid_offer
		and _owned_card_count(buyer) + offers.size() <= MAX_CARD_COUNT
	):
		buyer["gold"] = int(buyer.get("gold", 0)) - price
		seller["gold"] = mini(MAX_GOLD, int(seller.get("gold", 0)) + price)
		offered_indices.sort()
		offered_indices.reverse()
		var bought_cards: Array = []
		for card_index: int in offered_indices:
			bought_cards.push_front(seller["hand"].pop_at(card_index))
		buyer["hand"].append_array(bought_cards)
		bought = true
		state["log"].append("%sが%sからカード%d枚を¥%dで買った。" % [
			buyer.get("name", ""), seller.get("name", ""), bought_cards.size(), price,
		])
	elif accept and int(buyer.get("gold", 0)) < price:
		state["log"].append("%sは金が足りず購入できなかった。" % buyer.get("name", ""))
	else:
		state["log"].append("%sは購入を断った。" % buyer.get("name", ""))
	state["combat_view"] = {
		"status": "trade_result",
		"attacker_peer_id": buyer_peer_id,
		"attacker_name": String(buyer.get("name", "")),
		"target_peer_id": int(pending.get("seller_peer_id", 0)),
		"target_name": String(seller.get("name", "")),
		"result_text": "購入成立" if bought else "購入せず",
		"attack_card": (
			(pending.get("cards", [])[0] as Dictionary).duplicate(true)
			if not pending.get("cards", []).is_empty()
			else {}
		),
		"attack_cards": pending.get("cards", []).duplicate(true),
		"defense_cards": [],
		"damage": 0,
		"hide_arrow": true,
	}
	state["pending_purchase"] = {}
	state["phase"] = "result"
	return state.duplicate(true)

func _play_sell(
	actor_peer_id: int,
	trade_entry: Dictionary,
	merchandise_entries: Array,
	target_peer_id: int
) -> Dictionary:
	var seller: Dictionary = _player(actor_peer_id)
	var buyer: Dictionary = _player(target_peer_id)
	if (
		seller.is_empty() or buyer.is_empty()
		or actor_peer_id == target_peer_id
		or not bool(buyer.get("alive", false))
		or merchandise_entries.is_empty()
		or merchandise_entries.size() > maxi(1, int(trade_entry["preview"].get("power", 1)))
		or _owned_card_count(buyer) + merchandise_entries.size() > MAX_CARD_COUNT
	):
		return state.duplicate(true)
	for merchandise_entry: Dictionary in merchandise_entries:
		if bool(merchandise_entry.get("learned", false)) or merchandise_entry == trade_entry:
			return state.duplicate(true)
	var trade_card: Dictionary = trade_entry["preview"]
	if not _pay_card_costs(seller, [trade_card]):
		return state.duplicate(true)
	_consume_card(seller, trade_entry)
	var merchandise_ids: Array[String] = []
	for merchandise_entry: Dictionary in merchandise_entries:
		merchandise_ids.append(String(merchandise_entry.get("id", "")))
	_draw_one_card(actor_peer_id)
	_start_trade_defense(
		actor_peer_id,
		target_peer_id,
		trade_card,
		{
			"merchandise_ids": merchandise_ids,
			"merchandise_owner_peer_id": actor_peer_id,
			"merchandise_count": merchandise_ids.size(),
		}
	)
	return state.duplicate(true)

func _finish_sell_from_pending(pending: Dictionary) -> void:
	var seller_peer_id: int = int(pending.get("attacker_peer_id", 0))
	var buyer_peer_id: int = int(pending.get("target_peer_id", 0))
	var seller: Dictionary = _player(seller_peer_id)
	var buyer: Dictionary = _player(buyer_peer_id)
	var payload: Dictionary = pending.get("trade_payload", {})
	if seller.is_empty() or buyer.is_empty():
		_finish_failed_trade(pending, "売却失敗")
		return
	var merchandise_count: int = maxi(1, int(payload.get("merchandise_count", 1)))
	var merchandise_cards: Array = []
	var merchandise_owner_peer_id: int = int(payload.get(
		"merchandise_owner_peer_id", seller_peer_id
	))
	var reflected_sale: bool = merchandise_owner_peer_id != seller_peer_id
	if reflected_sale:
		# 押し売りの反射は商品を移動しない。選ばれたカードは元の持ち主へ戻り、
		# 売却額だけを反射された側から完全反射した側へ逆向きに支払う。
		var original_owner: Dictionary = _player(merchandise_owner_peer_id)
		var hand_copy: Array = original_owner.get("hand", []).duplicate()
		for raw_id: Variant in payload.get("merchandise_ids", []):
			var found_index := -1
			for index: int in range(hand_copy.size()):
				if String(hand_copy[index].get("id", "")) == String(raw_id):
					found_index = index
					break
			if found_index < 0:
				_finish_failed_trade(pending, "返却カードなし")
				return
			merchandise_cards.append(hand_copy.pop_at(found_index))
	else:
		if _owned_card_count(buyer) + merchandise_count > MAX_CARD_COUNT:
			_finish_failed_trade(pending, "相手のカード上限")
			return
		var hand_copy: Array = seller.get("hand", []).duplicate()
		var selected_indices: Array[int] = []
		for raw_id: Variant in payload.get("merchandise_ids", []):
			var found_index := -1
			for index: int in range(hand_copy.size()):
				if String(hand_copy[index].get("id", "")) == String(raw_id):
					found_index = index
					break
			if found_index < 0:
				_finish_failed_trade(pending, "売るカードなし")
				return
			hand_copy[found_index] = {}
			selected_indices.append(found_index)
		selected_indices.sort()
		selected_indices.reverse()
		for card_index: int in selected_indices:
			merchandise_cards.push_front(seller["hand"].pop_at(card_index))
	if merchandise_cards.is_empty():
		_finish_failed_trade(pending, "売るカードなし")
		return
	var price := 0
	for merchandise: Dictionary in merchandise_cards:
		price += clampi(int(merchandise.get("price", 0)), 0, MAX_GOLD)
	if not reflected_sale:
		buyer["hand"].append_array(merchandise_cards)
	_pay_forced_amount(buyer, price)
	seller["gold"] = mini(MAX_GOLD, int(seller.get("gold", 0)) + price)
	state["log"].append(
		"%sが%sの押し売りを反射。カード%d枚を返し、¥%dを受け取った。" % [
			seller.get("name", ""), buyer.get("name", ""), merchandise_cards.size(), price,
		]
		if reflected_sale
		else "%sが%sへカード%d枚を¥%dで売りつけた。" % [
			seller.get("name", ""), buyer.get("name", ""), merchandise_cards.size(), price,
		]
	)
	state["combat_view"] = {
		"status": "trade_result",
		"attacker_peer_id": seller_peer_id,
		"attacker_name": String(seller.get("name", "")),
		"target_peer_id": buyer_peer_id,
		"target_name": String(buyer.get("name", "")),
		"attack_card": merchandise_cards[0].duplicate(true),
		"attack_cards": merchandise_cards.duplicate(true),
		"defense_cards": [],
		"damage": 0,
		"result_text": (
			"完全反射　カード返却／¥%d徴収" % price
			if reflected_sale
			else "¥%dで押し売り" % price
		),
		"hide_arrow": false,
	}
	state["pending_attack"] = {}
	state["phase"] = "result"
	_update_alive_players()
	_check_game_over()

func play_exchange(
	actor_peer_id: int,
	card_id: String,
	new_hp: int,
	new_mp: int,
	new_gold: int
) -> Dictionary:
	if String(state.get("phase", "")) != "action" or actor_peer_id != _current_peer_id():
		return state.duplicate(true)
	var actor: Dictionary = _player(actor_peer_id)
	var card: Dictionary = _find_in_hand(actor, card_id)
	var card_cost: Dictionary = (
		card.get("cost", {}) if card.get("cost", {}) is Dictionary else {}
	)
	var cost_amount: int = (
		clampi(int(card_cost.get("amount", 0)), 0, 99)
		if String(card_cost.get("resource", "none")) in ["gold", "mp", "hp"]
		else 0
	)
	var exchange_total: int = (
		int(actor.get("hp", 0))
		+ int(actor.get("mp", 0))
		+ int(actor.get("gold", 0))
		- cost_amount
	)
	if (
		actor.is_empty()
		or card.is_empty()
		or not bool(actor.get("alive", false))
		or not _card_has_context_effect(card, "exchange", "action")
		or new_hp < 0 or new_hp > MAX_HP
		or new_mp < 0 or new_mp > MAX_MP
		or new_gold < 0 or new_gold > MAX_GOLD
		or new_hp + new_mp + new_gold
			!= exchange_total
		or not _pay_card_costs(actor, [card])
	):
		return state.duplicate(true)
	var entry: Dictionary = {"id": card_id, "preview": card, "learned": false}
	_consume_card(actor, entry)
	_draw_one_card(actor_peer_id)
	actor["hp"] = new_hp
	actor["mp"] = new_mp
	actor["gold"] = new_gold
	state["combat_view"] = {
		"status": "trade_result",
		"attacker_peer_id": actor_peer_id,
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": actor_peer_id,
		"target_name": String(actor.get("name", "")),
		"attack_card": card.duplicate(true),
		"attack_cards": [card.duplicate(true)],
		"defense_cards": [],
		"damage": 0,
		"result_text": "HP%d / MP%d / ¥%d" % [new_hp, new_mp, new_gold],
		"hide_arrow": true,
	}
	state["log"].append("%sが両替し、HP%d・MP%d・¥%dにした。" % [
		actor.get("name", ""), new_hp, new_mp, new_gold,
	])
	state["phase"] = "result"
	_update_alive_players()
	_check_game_over()
	return state.duplicate(true)

func _pay_forced_amount(player: Dictionary, amount: int) -> void:
	var remaining: int = maxi(0, amount)
	for resource: String in ["gold", "mp", "hp"]:
		if remaining <= 0:
			break
		var available: int = maxi(0, int(player.get(resource, 0)))
		var paid: int = mini(available, remaining)
		player[resource] = available - paid
		remaining -= paid
	if remaining > 0:
		player["hp"] = 0

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

func _play_offensive(
	actor_peer_id: int,
	attack_entries: Array,
	buff_entries: Array,
	offensive_entries: Array,
	target_peer_id: int
) -> Dictionary:
	var actor: Dictionary = _player(actor_peer_id)
	var owned_before: int = _owned_card_count(actor)
	# 攻撃カードがあればそれを主役に、無ければ最初の攻撃アップを主役にする。
	# 主役から属性と対象（敵1体／敵全体）を決める。威力は全カードの合計。
	var primary_preview: Dictionary = attack_entries[0]["preview"] if not attack_entries.is_empty() else buff_entries[0]["preview"]
	var primary_effect_name: String = "attack" if not attack_entries.is_empty() else "buff"
	var primary_effect: Dictionary = _first_context_effect(primary_preview, "action", primary_effect_name)
	var card_target: String = String(primary_effect.get("target", primary_preview.get("target", "enemy")))
	var includes_buff := false
	for offensive_entry: Dictionary in offensive_entries:
		if _card_has_context_effect(offensive_entry["preview"], "buff", "action"):
			includes_buff = true
			break
	# 攻撃アップは敵全体攻撃には使用できない。複合カード内の攻＋も同様に弾く。
	if card_target in ["all_enemies", "all_players"] and includes_buff:
		return state.duplicate(true)
	# 光は他属性の代わりになる。光以外の属性が複数混ざった時だけ無属性化する。
	var offensive_previews: Array = []
	for attr_entry: Dictionary in offensive_entries:
		offensive_previews.append(attr_entry["preview"])
	var card_attribute: String = _combined_offensive_attribute(offensive_previews)
	# 敵1体を狙うなら、カードを消費する前に対象の生存を確認する。
	if card_target not in ["all_enemies", "all_players"]:
		var single_target: Dictionary = _player(target_peer_id)
		if single_target.is_empty() or not bool(single_target.get("alive", false)):
			return state.duplicate(true)
	if not _pay_card_costs(actor, offensive_previews):
		return state.duplicate(true)
	var offensive_cards: Array = []
	var ordinary_cards_consumed := 0
	var miracle_cards_used := 0
	for entry: Dictionary in offensive_entries:
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
	if card_target in ["all_enemies", "all_players"]:
		var mt_targets: Array = []
		for raw_id: Variant in state.get("player_order", []):
			var p: Dictionary = _player(int(raw_id))
			if (
				not p.is_empty()
				and bool(p.get("alive", false))
				and (card_target == "all_players" or int(p["peer_id"]) != actor_peer_id)
			):
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
	combo_name: String,
	allow_repeat_setup: bool = true
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
	var extra_attack_count := 0
	for active_card: Dictionary in active_cards:
		match String(active_card.get("special_effect", "")):
			"double_attack":
				extra_attack_count += 1
			"double_power":
				attack_power *= 2
			"attribute_change":
				card_attribute = _normalize_attribute(
					active_card.get("special_attribute", "none")
				)
	if allow_repeat_setup and extra_attack_count > 0:
		var global_queue: Dictionary = state.get("multi_attack_queue", {})
		if not global_queue.is_empty():
			global_queue["rounds_remaining"] = extra_attack_count
		else:
			state["repeat_attack_queue"] = {
				"attacker_peer_id": actor_peer_id,
				"target_peer_id": target_peer_id,
				"attack_cards": attack_cards.duplicate(true),
				"card_name": combo_name,
				"remaining": extra_attack_count,
			}
	var strike_card: Dictionary = attack_cards[0].duplicate(true)
	strike_card["power"] = attack_power
	strike_card["attribute"] = card_attribute
	var attack_is_miracle := not attack_cards.is_empty()
	for attack_card: Dictionary in attack_cards:
		if String(attack_card.get("type", "")) != "miracle":
			attack_is_miracle = false
			break
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
		"is_miracle": attack_is_miracle,
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
	if card_target not in ["all_enemies", "all_players"]:
		var selected_target: Dictionary = _player(target_peer_id)
		if selected_target.is_empty() or not bool(selected_target.get("alive", false)):
			return state.duplicate(true)
	if not _pay_card_costs(actor, [preview]):
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
	if card_target in ["all_enemies", "all_players"]:
		var support_targets: Array = []
		for raw_peer_id: Variant in state.get("player_order", []):
			var recipient: Dictionary = _player(int(raw_peer_id))
			if (
				not recipient.is_empty()
				and bool(recipient.get("alive", false))
				and (card_target == "all_players" or int(recipient["peer_id"]) != actor_peer_id)
			):
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
		"is_miracle": String(card.get("type", "")) == "miracle",
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
		state["log"].append("%sが%sへ%sを使用。反射を選択中。" % [
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
	var reflecting_card: Dictionary = {}
	var using_reflection: bool = (
		not defense_cards.is_empty()
		and _response_kind(defense_cards[0]) == "reflect"
	)
	for defense_card: Dictionary in defense_cards:
		for defense_effect: Dictionary in _roll_card_effects(defense_card, "defense"):
			if using_reflection and String(defense_effect.get("effect", "")) != "reflect":
				continue
			if (
				String(defense_effect.get("effect", "")) == "reflect"
				and _reflect_can_return(defense_card, pending)
			):
				reflected = true
				reflecting_card = defense_card
			elif String(defense_effect.get("effect", "")) in ["heal", "guard", "instant_death"]:
				_apply_effect_entry(original_target, original_target, defense_effect, false, defense_card)
	var result_parts: Array[String] = []
	if reflected:
		_queue_reflection(pending, reflecting_card)
	else:
		var rolled_effects: Array = _roll_card_effects(card, "action")
		for effect_entry: Dictionary in rolled_effects:
			var effect_result: String = _apply_effect_entry(actor, original_target, effect_entry, false, card)
			if not effect_result.is_empty():
				result_parts.append(effect_result)
	var result_text: String = (
		"反射"
		if reflected
		else ("・".join(result_parts) if not result_parts.is_empty() else "ミス")
	)
	if reflected:
		state["log"].append("%sが%sを反射し、%sへ返した。" % [
			original_target.get("name", ""), card.get("name", ""), actor.get("name", ""),
		])
	state["combat_view"] = {
		"status": "support_resolved",
		"attacker_peer_id": int(actor.get("peer_id", 0)),
		"attacker_name": String(actor.get("name", "")),
		"target_peer_id": int(original_target.get("peer_id", 0)),
		"target_name": String(original_target.get("name", "")),
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
		"hide_arrow": int(original_target.get("peer_id", 0)) == int(actor.get("peer_id", 0)),
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
			receiver["hp"] = clampi(int(receiver.get("hp", 0)) + power, 0, MAX_HP)
			_update_alive_players()
			return "%s HP %s" % [
				receiver.get("name", ""),
				_signed_number(int(receiver.get("hp", 0)) - hp_before),
			]
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
			if String(hand_copy[index].get("id", "")) == card_id:
				found_index = index
				break
		if found_index < 0:
			return state.duplicate(true)
		defense_cards.append(hand_copy.pop_at(found_index))
	if defense_cards.is_empty():
		return state.duplicate(true)
	var response_kind: String = _response_kind(defense_cards[0])
	if response_kind == "reflect" and defense_cards.size() != 1:
		# 反射は他の防具だけでなく、別の反射とも重ねず1枚だけで使う。
		return state.duplicate(true)
	for defense_card: Dictionary in defense_cards:
		if _response_kind(defense_card) != response_kind:
			# 防具と反射は同時に使用できない。
			return state.duplicate(true)
	var attack_response: bool = String(pending.get("effect", "attack")) in ["attack", "buff"]
	var has_attribute_erase := false
	for defense_card: Dictionary in defense_cards:
		if String(defense_card.get("special_effect", "")) == "attribute_erase":
			has_attribute_erase = true
			break
	for defense_card: Dictionary in defense_cards:
		if can_respond_with_card(pending, defense_card):
			continue
		if (
			not attack_response
			or not has_attribute_erase
			or response_kind == "reflect"
			or _effects_for_context(defense_card, "defense").is_empty()
		):
			return state.duplicate(true)
	if not _pay_card_costs(defender, defense_cards):
		return state.duplicate(true)
	defender["hand"] = hand_copy
	for defense_card: Dictionary in defense_cards:
		state["discard"].append(defense_card)
	_draw_to_hand(actor_peer_id)
	_resolve_pending_attack(defense_cards)
	return state.duplicate(true)

func _resolve_pending_attack(defense_cards: Array) -> void:
	var pending: Dictionary = state.get("pending_attack", {})
	if String(pending.get("effect", "")) in ["buy", "sell"]:
		_resolve_pending_trade(defense_cards)
		return
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
	var reflecting_card: Dictionary = {}
	var using_reflection: bool = (
		not defense_cards.is_empty()
		and _response_kind(defense_cards[0]) == "reflect"
	)
	var rolled_defenses: Array = []
	var attribute_erased := false
	for defense_card: Dictionary in defense_cards:
		var rolled_effects: Array = _roll_card_effects(defense_card, "defense")
		rolled_defenses.append({"card": defense_card, "effects": rolled_effects})
		if (
			not rolled_effects.is_empty()
			and String(defense_card.get("special_effect", "")) == "attribute_erase"
		):
			attribute_erased = true
	if attribute_erased:
		attack_attribute = "none"
		pending["attribute"] = "none"
	for rolled_defense: Dictionary in rolled_defenses:
		var defense_card: Dictionary = rolled_defense["card"]
		if (
			not attribute_erased
			and not _attribute_can_defend(
				attack_attribute,
				_normalize_attribute(defense_card.get("attribute", "none"))
			)
			and _response_kind(defense_card) != "reflect"
		):
			continue
		if defense_card is Dictionary:
			var dc_attribute: String = _normalize_attribute(defense_card.get("attribute", "none"))
			for effect_entry: Dictionary in rolled_defense["effects"]:
				var dc_effect: String = String(effect_entry.get("effect", "guard"))
				var dc_power: int = int(effect_entry.get("power", 0))
				if using_reflection and dc_effect != "reflect":
					continue
				match dc_effect:
					"attack":
						counter_power += dc_power
						if defense_card not in counter_cards:
							counter_cards.append(defense_card)
					"guard":
						defense_power += dc_power
						defense_attributes.append(dc_attribute)
					"reflect":
						has_reflect = true
						reflecting_card = defense_card
					"heal", "instant_death":
						var defense_side_effect: Dictionary = effect_entry.duplicate(true)
						defense_side_effect["_card"] = defense_card
						defense_side_effects.append(defense_side_effect)
	var defense_attribute: String = _combined_defense_attribute(defense_attributes)
	var damage: int = 0 if has_reflect else maxi(0, attack_power - defense_power)
	if attack_attribute == "dark" and damage > 0:
		damage = int(target.get("hp", 0))
		target["hp"] = 0
	else:
		target["hp"] = int(target["hp"]) - damage
	if defense_cards.is_empty():
		state["log"].append("%sは防御せず、%dダメージ。" % [target["name"], damage])
	else:
		state["log"].append("%sは防具%d枚で防御し、%dダメージ。" % [target["name"], defense_cards.size(), damage])
	if has_reflect:
		_queue_reflection(pending, reflecting_card)
		state["log"].append("%sが%sを%sへそのまま返した。" % [
			target["name"], pending.get("card_name", "カード"), attacker["name"],
		])
	for defense_side_effect: Dictionary in defense_side_effects:
		_apply_effect_entry(
			target,
			target,
			defense_side_effect,
			false,
			defense_side_effect.get("_card", {})
		)
	for side_effect: Dictionary in pending.get("side_effects", []):
		if not has_reflect:
			var side_card: Dictionary = side_effect.get("_card", {})
			_apply_effect_entry(attacker, target, side_effect, false, side_card)
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
		"reflected": has_reflect,
		"arrow_direction": String(pending.get("arrow_direction", "right")),
		"hide_arrow": false,
	}
	state["phase"] = "result"
	state["pending_attack"] = {}
	_update_alive_players()

func continue_after_result() -> Dictionary:
	if String(state.get("phase", "")) != "result":
		return state.duplicate(true)
	var support_queue: Dictionary = state.get("multi_support_queue", {})
	var attack_queue: Dictionary = state.get("multi_attack_queue", {})
	var repeat_queue: Dictionary = state.get("repeat_attack_queue", {})
	# 全対象カードの途中では一時的に生存者が1人以下になっても、残り対象の処理を優先する。
	if support_queue.is_empty() and attack_queue.is_empty() and repeat_queue.is_empty() and _check_game_over():
		return state.duplicate(true)
	var counter: Dictionary = state.get("pending_counter_attack", {})
	if not counter.is_empty():
		state["pending_counter_attack"] = {}
		_start_counter_attack(counter)
		return state.duplicate(true)
	if not support_queue.is_empty():
		support_queue["index"] = int(support_queue.get("index", 0)) + 1
		_start_next_multi_support()
		return state.duplicate(true)
	if not attack_queue.is_empty():
		attack_queue["index"] = int(attack_queue.get("index", 0)) + 1
		_start_next_multi_attack()
		return state.duplicate(true)
	if not repeat_queue.is_empty():
		var remaining: int = int(repeat_queue.get("remaining", 0))
		if remaining > 0:
			repeat_queue["remaining"] = remaining - 1
			_start_attack_for_target(
				int(repeat_queue.get("attacker_peer_id", 0)),
				int(repeat_queue.get("target_peer_id", 0)),
				repeat_queue.get("attack_cards", []),
				String(repeat_queue.get("card_name", "")),
				false
			)
			return state.duplicate(true)
		state["repeat_attack_queue"] = {}
	if _start_next_reflection():
		return state.duplicate(true)
	if _check_game_over():
		return state.duplicate(true)
	state["phase"] = "action"
	_advance_turn()
	return state.duplicate(true)

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
		preferred_names = [
			"attack", "buff", "heal", "instant_death",
			"buy", "sell", "exchange",
		]
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
		if String(effect_entry.get("effect", "")) in [
			"attack", "buff", "heal", "instant_death",
			"buy", "sell", "exchange",
		]:
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
		and (
			String(card.get("special_effect", "")) == "attribute_erase"
			or _attribute_can_defend(
				_normalize_attribute(attack_attribute),
				_normalize_attribute(card.get("attribute", "none"))
			)
		)
	)

func can_respond_with_card(pending: Dictionary, card: Dictionary) -> bool:
	if _card_has_effect(card, "reflect"):
		return _reflect_can_return(card, pending)
	if String(pending.get("effect", "attack")) in ["attack", "buff"]:
		return can_defend_with_card(String(pending.get("attribute", "none")), card)
	return false

func _response_kind(card: Dictionary) -> String:
	return "reflect" if _card_has_effect(card, "reflect") else "armor"

func _reflect_can_return(card: Dictionary, pending: Dictionary) -> bool:
	if not _card_has_effect(card, "reflect"):
		return false
	var tags: Array = card.get("tags", [])
	if "full_reflect" in tags or "all_reflect" in tags:
		return true
	var incoming_card: Dictionary = pending.get("card", {})
	var incoming_is_miracle: bool = bool(pending.get(
		"is_miracle",
		String(incoming_card.get("type", "")) == "miracle"
	))
	if incoming_is_miracle:
		return "miracle_reflect" in tags
	return (
		String(pending.get("effect", "attack")) in ["attack", "buff"]
		and ("attack_reflect" in tags or "miracle_reflect" not in tags)
		and _attribute_can_defend(
			(
				"none"
				if String(card.get("special_effect", "")) == "attribute_erase"
				else _normalize_attribute(pending.get("attribute", "none"))
			),
			_normalize_attribute(card.get("attribute", "none"))
		)
	)

func _is_full_reflect_card(card: Dictionary) -> bool:
	var tags: Array = card.get("tags", [])
	return (
		_card_has_effect(card, "reflect")
		and "full_reflect" in tags
	)

func _reflected_attribute(pending: Dictionary, reflecting_card: Dictionary) -> String:
	var original_attribute: String = _normalize_attribute(pending.get("attribute", "none"))
	var tags: Array = reflecting_card.get("tags", [])
	if (
		"full_reflect" in tags
		or "all_reflect" in tags
		or "miracle_reflect" in tags
		or _normalize_attribute(reflecting_card.get("attribute", "none")) == "light"
	):
		return original_attribute
	return "none"

func _queue_reflection(pending: Dictionary, reflecting_card: Dictionary) -> void:
	var reflected: Dictionary = pending.duplicate(true)
	var previous_attacker_id: int = int(pending.get("attacker_peer_id", 0))
	var previous_target_id: int = int(pending.get("target_peer_id", 0))
	var previous_attacker: Dictionary = _player(previous_attacker_id)
	var previous_target: Dictionary = _player(previous_target_id)
	reflected["attacker_peer_id"] = previous_target_id
	reflected["attacker_name"] = String(previous_target.get("name", ""))
	reflected["target_peer_id"] = previous_attacker_id
	reflected["target_name"] = String(previous_attacker.get("name", ""))
	reflected["arrow_direction"] = (
		"left" if String(pending.get("arrow_direction", "right")) == "right" else "right"
	)
	reflected["is_reflection"] = true
	reflected["reflection_depth"] = int(pending.get("reflection_depth", 0)) + 1
	reflected["attribute"] = _reflected_attribute(pending, reflecting_card)
	var reflections: Array = state.get("pending_reflections", [])
	if bool(pending.get("is_reflection", false)):
		reflections.push_front(reflected)
	else:
		reflections.append(reflected)
	state["pending_reflections"] = reflections

func _start_next_reflection() -> bool:
	var reflections: Array = state.get("pending_reflections", [])
	while not reflections.is_empty():
		var pending: Dictionary = reflections.pop_front()
		state["pending_reflections"] = reflections
		var attacker: Dictionary = _player(int(pending.get("attacker_peer_id", 0)))
		var target: Dictionary = _player(int(pending.get("target_peer_id", 0)))
		if (
			attacker.is_empty() or target.is_empty()
			or not bool(attacker.get("alive", false))
			or not bool(target.get("alive", false))
		):
			continue
		state["pending_attack"] = pending
		state["phase"] = "defense"
		var card: Dictionary = pending.get("card", {})
		var is_support: bool = String(pending.get("effect", "attack")) not in ["attack", "buff"]
		state["combat_view"] = {
			"status": "support_pending" if is_support else "defending",
			"attacker_peer_id": int(pending.get("attacker_peer_id", 0)),
			"attacker_name": String(attacker.get("name", "")),
			"target_peer_id": int(pending.get("target_peer_id", 0)),
			"target_name": String(target.get("name", "")),
			"attack_card": card.duplicate(true),
			"attack_cards": pending.get("attack_cards", [card]).duplicate(true),
			"defense_cards": [],
			"attack_power": int(pending.get("power", 0)),
			"attack_attribute": String(pending.get("attribute", "none")),
			"defense_power": 0,
			"defense_attribute": "none",
			"damage": -1 if is_support else 0,
			"arrow_direction": String(pending.get("arrow_direction", "left")),
			"hide_arrow": false,
			"is_reflection": true,
		}
		state["log"].append("反射された%sが%sへ返る。防御を選択中。" % [
			pending.get("card_name", card.get("name", "カード")), target.get("name", ""),
		])
		return true
	state["pending_reflections"] = reflections
	return false

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
			"禁忌":
				copies = 0
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
		return false
	var draw_index: int = rng.randi_range(0, state["deck"].size() - 1)
	player["hand"].append(state["deck"][draw_index].duplicate(true))
	return true

func _owned_card_count(player: Dictionary) -> int:
	return player.get("hand", []).size() + player.get("learned_miracles", []).size()

func _has_offensive_card(player: Dictionary) -> bool:
	for zone_name: String in ["hand", "learned_miracles"]:
		for raw_card: Variant in player.get(zone_name, []):
			if (
				raw_card is Dictionary
				and _can_afford_card_costs(player, [raw_card])
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
		var rounds_remaining: int = int(queue.get("rounds_remaining", 0))
		if rounds_remaining > 0:
			queue["rounds_remaining"] = rounds_remaining - 1
			queue["index"] = 0
			_start_next_multi_attack()
			return
		state["multi_attack_queue"] = {}
		if not _start_next_reflection():
			if not _check_game_over():
				state["phase"] = "action"
				_advance_turn()
		return
	var target_peer_id: int = int(targets[index])
	var cards_for_target: Array = queue_attack_cards if not queue_attack_cards.is_empty() else [card]
	var first_strike: bool = index == 0 and not queue.has("rounds_remaining")
	_start_attack_for_target(
		attacker_peer_id, target_peer_id, cards_for_target, combo_name, first_strike
	)
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
		if not _start_next_reflection():
			if not _check_game_over():
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
	state["repeat_attack_queue"] = {}
	state["pending_reflections"] = []
	state["cost_death_peers"] = {}
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
		if (
			int(player["hp"]) <= 0
			or bool(state.get("cost_death_peers", {}).get(str(player.get("peer_id", 0)), false))
		):
			player["hp"] = 0
			player["alive"] = false

func _can_afford_card_costs(player: Dictionary, cards: Array) -> bool:
	var totals: Dictionary = {"gold": 0, "mp": 0, "hp": 0}
	for raw_card: Variant in cards:
		if not (raw_card is Dictionary):
			continue
		var raw_cost: Variant = raw_card.get("cost", {})
		var cost: Dictionary = raw_cost if raw_cost is Dictionary else {}
		var resource: String = String(cost.get("resource", "none"))
		if resource in totals:
			totals[resource] = int(totals[resource]) + clampi(int(cost.get("amount", 0)), 0, 99)
	for resource: String in totals:
		if int(player.get(resource, 0)) < int(totals[resource]):
			return false
	return true

func _pay_card_costs(player: Dictionary, cards: Array) -> bool:
	if not _can_afford_card_costs(player, cards):
		return false
	var totals: Dictionary = {"gold": 0, "mp": 0, "hp": 0}
	for raw_card: Variant in cards:
		if not (raw_card is Dictionary):
			continue
		var raw_cost: Variant = raw_card.get("cost", {})
		var cost: Dictionary = raw_cost if raw_cost is Dictionary else {}
		var resource: String = String(cost.get("resource", "none"))
		if resource in totals:
			totals[resource] = int(totals[resource]) + clampi(int(cost.get("amount", 0)), 0, 99)
	for resource: String in totals:
		player[resource] = int(player.get(resource, 0)) - int(totals[resource])
	if int(totals["gold"]) + int(totals["mp"]) + int(totals["hp"]) > 0:
		state["log"].append("%sがコストを支払った（¥%d / MP%d / HP%d）。" % [
			player.get("name", ""),
			int(totals["gold"]),
			int(totals["mp"]),
			int(totals["hp"]),
		])
	if int(player.get("hp", 0)) <= 0:
		state["cost_death_peers"][str(player.get("peer_id", 0))] = true
	return true

func _player(peer_id: int) -> Dictionary:
	return state.get("players", {}).get(str(peer_id), {})
