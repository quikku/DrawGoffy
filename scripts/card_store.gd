extends Node

signal active_deck_changed

const CARD_FILE := "user://cards.json"
const DECK_FILE := "user://decks.json"
const SHARED_IMAGE_DIR := "user://card_images"
const VALID_ATTRIBUTES: Array[String] = [
	"none", "fire", "water", "wood", "earth", "light", "dark",
]
const VALID_TYPES: Array[String] = ["weapon", "armor", "miracle", "special", "trade"]
const VALID_TARGETS: Array[String] = ["enemy", "self", "all_enemies", "all_players"]
const VALID_EFFECTS: Array[String] = [
	"attack", "buff", "guard", "reflect", "heal", "instant_death",
	"buy", "sell", "exchange",
]
const VALID_EFFECT_MODES: Array[String] = ["all", "random_one"]
const VALID_COST_RESOURCES: Array[String] = ["none", "gold", "mp", "hp"]
const VALID_SPECIAL_EFFECTS: Array[String] = [
	"", "double_attack", "attribute_change", "double_power", "attribute_erase",
]

var cards: Array[Dictionary] = []
var session_cards: Array[Dictionary] = []
var decks: Array[Dictionary] = []
var active_deck_id := ""

func _ready() -> void:
	load_cards()
	if cards.is_empty():
		cards = _default_cards()
	else:
		_add_missing_default_cards()
	for card in cards:
		_normalize_card(card)
		if String(card.get("id", "")).is_empty():
			card["id"] = _make_card_id()
	save_cards()
	load_decks()
	if decks.is_empty():
		create_deck("デフォルトデッキ", false)
	_set_valid_active_deck()
	save_decks()

func _add_missing_default_cards() -> void:
	var existing_names: Dictionary = {}
	for card: Dictionary in cards:
		existing_names[String(card.get("name", ""))] = true
	for default_card: Dictionary in _default_cards():
		if not existing_names.has(String(default_card["name"])):
			cards.append(default_card)

func load_cards() -> void:
	if not FileAccess.file_exists(CARD_FILE):
		cards = []
		return
	var text: String = FileAccess.get_file_as_string(CARD_FILE)
	var parsed: Variant = JSON.parse_string(text)
	cards.clear()
	if parsed is Array:
		for raw_card: Variant in parsed:
			if raw_card is Dictionary:
				var card: Dictionary = raw_card
				_normalize_card(card)
				cards.append(card)

func save_cards() -> void:
	var file: FileAccess = FileAccess.open(CARD_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(cards, "\t"))

func load_decks() -> void:
	decks.clear()
	active_deck_id = ""
	if not FileAccess.file_exists(DECK_FILE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DECK_FILE))
	if not (parsed is Dictionary):
		return
	active_deck_id = String(parsed.get("active_deck_id", ""))
	for raw_deck: Variant in parsed.get("decks", []):
		if not (raw_deck is Dictionary):
			continue
		var deck: Dictionary = raw_deck
		var unique_ids: Array[String] = []
		for raw_id: Variant in deck.get("card_ids", []):
			var card_id: String = String(raw_id)
			if (
				not card_id.is_empty()
				and card_id not in unique_ids
				and not _card_by_id(card_id).is_empty()
			):
				unique_ids.append(card_id)
		decks.append({
			"id": String(deck.get("id", _make_card_id())),
			"name": String(deck.get("name", "デッキ")),
			"card_ids": unique_ids,
		})

func save_decks() -> void:
	var file: FileAccess = FileAccess.open(DECK_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"active_deck_id": active_deck_id,
			"decks": decks,
		}, "\t"))

func create_deck(deck_name: String = "新しいデッキ", notify: bool = true) -> Dictionary:
	var deck: Dictionary = {
		"id": _make_card_id(),
		"name": deck_name.strip_edges() if not deck_name.strip_edges().is_empty() else "新しいデッキ",
		"card_ids": [],
	}
	decks.append(deck)
	active_deck_id = String(deck["id"])
	save_decks()
	if notify:
		active_deck_changed.emit()
	return deck

func rename_deck(deck_id: String, deck_name: String) -> bool:
	var clean_name: String = deck_name.strip_edges()
	if clean_name.is_empty():
		return false
	for deck: Dictionary in decks:
		if String(deck.get("id", "")) == deck_id:
			deck["name"] = clean_name
			save_decks()
			active_deck_changed.emit()
			return true
	return false

func delete_deck(deck_id: String) -> bool:
	if decks.size() <= 1:
		return false
	for index: int in range(decks.size()):
		if String(decks[index].get("id", "")) == deck_id:
			decks.remove_at(index)
			_set_valid_active_deck()
			save_decks()
			active_deck_changed.emit()
			return true
	return false

func set_active_deck(deck_id: String) -> bool:
	for deck: Dictionary in decks:
		if String(deck.get("id", "")) == deck_id:
			active_deck_id = deck_id
			save_decks()
			active_deck_changed.emit()
			return true
	return false

func active_deck() -> Dictionary:
	for deck: Dictionary in decks:
		if String(deck.get("id", "")) == active_deck_id:
			return deck
	return {}

func add_card_to_deck(deck_id: String, card_id: String) -> bool:
	for deck: Dictionary in decks:
		if String(deck.get("id", "")) != deck_id:
			continue
		var card_ids: Array = deck.get("card_ids", [])
		if card_id in card_ids or _card_by_id(card_id).is_empty():
			return false
		card_ids.append(card_id)
		deck["card_ids"] = card_ids
		save_decks()
		if deck_id == active_deck_id:
			active_deck_changed.emit()
		return true
	return false

func remove_card_from_deck(deck_id: String, card_id: String) -> bool:
	for deck: Dictionary in decks:
		if String(deck.get("id", "")) != deck_id:
			continue
		var card_ids: Array = deck.get("card_ids", [])
		var index: int = card_ids.find(card_id)
		if index < 0:
			return false
		card_ids.remove_at(index)
		deck["card_ids"] = card_ids
		save_decks()
		if deck_id == active_deck_id:
			active_deck_changed.emit()
		return true
	return false

func active_deck_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var deck: Dictionary = active_deck()
	for raw_id: Variant in deck.get("card_ids", []):
		var card: Dictionary = _card_by_id(String(raw_id))
		if not card.is_empty():
			result.append(card)
	return result

func export_active_deck_with_images() -> Array:
	return _pack_cards_with_images(active_deck_cards())

func _card_by_id(card_id: String) -> Dictionary:
	for card: Dictionary in cards:
		if String(card.get("id", "")) == card_id:
			return card
	return {}

func _set_valid_active_deck() -> void:
	for deck: Dictionary in decks:
		if String(deck.get("id", "")) == active_deck_id:
			return
	active_deck_id = String(decks[0].get("id", "")) if not decks.is_empty() else ""

func upsert_card(card: Dictionary) -> Dictionary:
	_normalize_card(card)
	card["rarity"] = auto_rarity(card)
	if String(card.get("id", "")).is_empty():
		card["id"] = _make_card_id()
	for index in range(cards.size()):
		if cards[index].get("id") == card["id"]:
			cards[index] = card
			save_cards()
			if String(card["id"]) in active_deck().get("card_ids", []):
				active_deck_changed.emit()
			return card
	cards.append(card)
	save_cards()
	return card

func clear_session() -> void:
	session_cards.clear()

func _upsert_session_card(card: Dictionary) -> Dictionary:
	_normalize_card(card)
	card["rarity"] = auto_rarity(card)
	if String(card.get("id", "")).is_empty():
		card["id"] = _make_card_id()
	for index in range(session_cards.size()):
		if (
			session_cards[index].get("id") == card["id"]
			and int(session_cards[index].get("owner_peer_id", 0))
				== int(card.get("owner_peer_id", 0))
		):
			session_cards[index] = card
			return card
	session_cards.append(card)
	return card

func _make_card_id() -> String:
	return "%d-%d" % [int(Time.get_unix_time_from_system()), randi()]

func delete_card(card_id: String) -> bool:
	for index in range(cards.size()):
		if String(cards[index].get("id", "")) == card_id:
			cards.remove_at(index)
			save_cards()
			var active_changed := false
			for deck: Dictionary in decks:
				var card_ids: Array = deck.get("card_ids", [])
				if card_id in card_ids:
					card_ids.erase(card_id)
					deck["card_ids"] = card_ids
					if String(deck.get("id", "")) == active_deck_id:
						active_changed = true
			save_decks()
			if active_changed:
				active_deck_changed.emit()
			return true
	return false

func import_cards(incoming: Array) -> void:
	for card in incoming:
		if card is Dictionary:
			upsert_card(card)

func export_cards_with_images() -> Array:
	return _pack_cards_with_images(cards)

func export_session_cards_with_images() -> Array:
	return _pack_cards_with_images(session_cards)

func _pack_cards_with_images(source: Array) -> Array:
	var result: Array = []
	for card: Dictionary in source:
		var packed: Dictionary = card.duplicate(true)
		var path: String = String(packed.get("image_path", ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			packed["image_name"] = path.get_file()
			packed["image_b64"] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(path))
		result.append(packed)
	return result

func receive_cards_from_peer(incoming: Array, peer_id: int) -> Array:
	var normalized: Array = []
	for raw_card: Variant in incoming:
		if not (raw_card is Dictionary):
			continue
		var card: Dictionary = (raw_card as Dictionary).duplicate(true)
		if String(card.get("id", "")).is_empty():
			card["id"] = _make_card_id()
		if card.has("image_b64") and card.has("image_name"):
			var bytes: PackedByteArray = Marshalls.base64_to_raw(String(card["image_b64"]))
			var extension: String = String(card["image_name"]).get_extension().to_lower()
			if extension.is_empty():
				extension = "png"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARED_IMAGE_DIR))
			# カードID基準の共通パスに保存すると、ホストとクライアントで同じ
			# image_path が同じ画像を指す（対戦状態にはこのパスがそのまま入る）。
			var image_path: String = "%s/%s.%s" % [SHARED_IMAGE_DIR, String(card["id"]).validate_filename(), extension]
			var file: FileAccess = FileAccess.open(image_path, FileAccess.WRITE)
			if file:
				file.store_buffer(bytes)
				card["image_path"] = image_path
		card.erase("image_b64")
		card.erase("image_name")
		card["owner_peer_id"] = int(card.get("owner_peer_id", peer_id))
		normalized.append(_upsert_session_card(card))
	return normalized

func replace_cards_from_peer(incoming: Array, peer_id: int) -> Array:
	for index: int in range(session_cards.size() - 1, -1, -1):
		if int(session_cards[index].get("owner_peer_id", 0)) == peer_id:
			session_cards.remove_at(index)
	return receive_cards_from_peer(incoming, peer_id)

func remove_session_cards_from_peer(peer_id: int) -> void:
	for index: int in range(session_cards.size() - 1, -1, -1):
		if int(session_cards[index].get("owner_peer_id", 0)) == peer_id:
			session_cards.remove_at(index)

func auto_rarity(card: Dictionary) -> String:
	var effect_scores: Array[float] = []
	var effect_weights: Array[int] = []
	var tags: Array = card.get("tags", []) if card.get("tags", []) is Array else []
	for effect_entry: Dictionary in _effects_for_card(card):
		var effect_name: String = String(effect_entry.get("effect", "attack"))
		var effect_score: float
		if effect_name == "reflect":
			# 反射は数値を持たず、種類ごとの固定値だけで評価する。
			if "full_reflect" in tags or "all_reflect" in tags:
				effect_score = 35.0
			elif "miracle_reflect" in tags:
				effect_score = 22.0
			else:
				effect_score = 12.0
		elif effect_name == "exchange":
			effect_score = 8.0
		elif effect_name in ["buy", "sell"]:
			effect_score = 5.0 + maxi(1, int(effect_entry.get("power", 1))) * 5.0
		else:
			effect_score = float(absi(int(effect_entry.get("power", 0))))
		match effect_name:
			"instant_death":
				effect_score += 60.0
			"buff":
				effect_score += 10.0
			"guard":
				effect_score += 8.0
			"heal":
				effect_score += 6.0
		if effect_name in ["attack", "buff"]:
			match String(effect_entry.get("attribute", card.get("attribute", "none"))):
				"light":
					effect_score += 8.0
				"dark":
					effect_score += 12.0
		if String(effect_entry.get("target", card.get("target", ""))) in ["all_enemies", "all_players"]:
			effect_score += 15.0
		var special_effect: String = String(card.get("special_effect", ""))
		if effect_name in ["attack", "buff"]:
			if special_effect == "attribute_change":
				match String(card.get("special_attribute", "none")):
					"light":
						effect_score += 8.0
					"dark":
						effect_score += 12.0
			if special_effect in ["double_attack", "double_power"]:
				effect_score *= 2.0
		effect_score *= clampi(int(effect_entry.get("chance", 100)), 0, 100) / 100.0
		effect_scores.append(effect_score)
		effect_weights.append(maxi(1, int(effect_entry.get("weight", 1))))
	var score := 0.0
	if String(card.get("effect_mode", "all")) == "random_one":
		var total_weight := 0
		for weight: int in effect_weights:
			total_weight += weight
		if total_weight > 0:
			for index: int in range(effect_scores.size()):
				score += effect_scores[index] * effect_weights[index] / float(total_weight)
	else:
		for effect_score: float in effect_scores:
			score += effect_score
	# 奇跡の再利用性は、複合効果の数にかかわらずカード1枚につき1回だけ加点する。
	if String(card.get("type", "")) == "miracle":
		score += 12.0
	if String(card.get("special_effect", "")) == "attribute_erase":
		score += 8.0
	var cost: Dictionary = card.get("cost", {}) if card.get("cost", {}) is Dictionary else {}
	var cost_discount: int = (
		clampi(int(cost.get("amount", 0)), 0, 99)
		if String(cost.get("resource", "none")) in ["gold", "mp", "hp"]
		else 0
	)
	var final_score: int = int(round(
		score * clampi(int(card.get("chance", 100)), 0, 100) / 100.0
	)) - cost_discount
	if final_score >= 60:
		return "禁忌"
	if final_score >= 45:
		return "legendary"
	if final_score >= 30:
		return "rare"
	if final_score >= 16:
		return "uncommon"
	return "common"

func suggested_price(card: Dictionary) -> int:
	# 既存データに価格が無い場合だけ使う移行用の基準値。
	# 価格そのものはカード固有の編集可能な値で、レアリティとは独立して保存する。
	match auto_rarity(card):
		"禁忌":
			return 20
		"legendary":
			return 15
		"rare":
			return 10
		"uncommon":
			return 5
	return 1

func _normalize_card(card: Dictionary) -> void:
	card["id"] = String(card.get("id", ""))
	card["name"] = String(card.get("name", "名無しのカード"))
	card["description"] = String(card.get("description", ""))
	card["image_path"] = String(card.get("image_path", ""))
	card["type"] = String(card.get("type", "weapon"))
	card["target"] = String(card.get("target", "enemy"))
	card["effect"] = String(card.get("effect", "attack"))
	card["power"] = int(card.get("power", 10))
	card["attribute"] = String(card.get("attribute", "none"))
	if card["attribute"] not in VALID_ATTRIBUTES:
		card["attribute"] = "none"
	card["tags"] = card.get("tags", []) if card.get("tags", []) is Array else []
	# 価格機能の初版でタグとして保存した取引カードを、新しい種類・効果へ移行する。
	if "trade_buy" in card["tags"]:
		card["type"] = "trade"
		card["effect"] = "buy"
		card["effects"] = []
	elif "trade_sell" in card["tags"]:
		card["type"] = "trade"
		card["effect"] = "sell"
		card["effects"] = []
	if card["id"] == "builtin-056" and "full_reflect" not in card["tags"]:
		card["tags"].append("full_reflect")
	card.erase("condition")
	if card["type"] not in VALID_TYPES:
		card["type"] = "weapon"
	# 旧「multi_attack」効果は「対象＝敵全体の攻撃」に読み替える。
	if card["effect"] == "multi_attack":
		card["effect"] = "attack"
		card["target"] = "all_enemies"
	if card["effect"] not in VALID_EFFECTS:
		card["effect"] = "attack"
	if card["effect"] in ["buy", "sell", "exchange"]:
		card["type"] = "trade"
		card["target"] = "self" if card["effect"] == "exchange" else "enemy"
		card["attribute"] = "none"
		card["power"] = 0 if card["effect"] == "exchange" else maxi(1, card["power"])
	if card["target"] not in VALID_TARGETS:
		card["target"] = "self"
	card["chance"] = clampi(int(card.get("chance", 100)), 0, 100)
	var raw_cost: Variant = card.get("cost", {})
	var cost: Dictionary = raw_cost if raw_cost is Dictionary else {}
	var cost_resource: String = String(cost.get("resource", "none"))
	if cost_resource not in VALID_COST_RESOURCES:
		cost_resource = "none"
	var cost_amount: int = clampi(int(cost.get("amount", 0)), 0, 99)
	if cost_resource == "none" or cost_amount == 0:
		cost_resource = "none"
		cost_amount = 0
	card["cost"] = {"resource": cost_resource, "amount": cost_amount}
	card["effect_mode"] = String(card.get("effect_mode", "all"))
	if card["effect_mode"] not in VALID_EFFECT_MODES:
		card["effect_mode"] = "all"
	var normalized_effects: Array = []
	for raw_effect: Variant in _effects_for_card(card):
		if not (raw_effect is Dictionary):
			continue
		var effect_entry: Dictionary = (raw_effect as Dictionary).duplicate(true)
		effect_entry["effect"] = String(effect_entry.get("effect", card["effect"]))
		if effect_entry["effect"] not in VALID_EFFECTS:
			effect_entry["effect"] = "attack"
		effect_entry["power"] = int(effect_entry.get("power", card["power"]))
		if effect_entry["effect"] == "reflect":
			# 反射は数値を持たず、対象カードを丸ごと返す。
			effect_entry["power"] = 0
		elif effect_entry["effect"] == "exchange":
			effect_entry["power"] = 0
		elif effect_entry["effect"] in ["buy", "sell"]:
			effect_entry["power"] = maxi(1, effect_entry["power"])
		effect_entry["target"] = String(effect_entry.get("target", card["target"]))
		if effect_entry["target"] not in VALID_TARGETS:
			effect_entry["target"] = card["target"]
		effect_entry["chance"] = clampi(int(effect_entry.get("chance", 100)), 0, 100)
		effect_entry["weight"] = maxi(1, int(effect_entry.get("weight", 1)))
		normalized_effects.append(effect_entry)
	if normalized_effects.is_empty():
		normalized_effects.append({
			"effect": card["effect"],
			"power": card["power"],
			"target": card["target"],
			"chance": 100,
			"weight": 1,
		})
	card["effects"] = normalized_effects
	var primary_effect: Dictionary = normalized_effects[0]
	card["effect"] = String(primary_effect["effect"])
	card["power"] = int(primary_effect["power"])
	card["target"] = String(primary_effect["target"])
	if card["effect"] in ["buy", "sell", "exchange"]:
		card["type"] = "trade"
		card["target"] = "self" if card["effect"] == "exchange" else "enemy"
		card["attribute"] = "none"
	# 回復だけのカードは属性相性に関与しない。
	var has_non_heal := false
	for effect_entry: Dictionary in normalized_effects:
		if String(effect_entry.get("effect", "")) != "heal":
			has_non_heal = true
	if not has_non_heal:
		card["attribute"] = "none"
	card["special_effect"] = String(card.get("special_effect", ""))
	var has_attack_role := false
	var has_defense_role: bool = card["type"] == "armor"
	for effect_entry: Dictionary in normalized_effects:
		var role_effect: String = String(effect_entry.get("effect", ""))
		if role_effect in ["attack", "buff"]:
			has_attack_role = true
		if role_effect in ["guard", "reflect"]:
			has_defense_role = true
	var allowed_specials: Array[String] = [""]
	if has_attack_role:
		allowed_specials.append_array(["double_attack", "attribute_change", "double_power"])
	if has_defense_role:
		allowed_specials.append("attribute_erase")
	if card["special_effect"] not in allowed_specials:
		card["special_effect"] = ""
	card["special_attribute"] = String(card.get("special_attribute", "none"))
	if card["special_attribute"] not in VALID_ATTRIBUTES:
		card["special_attribute"] = "none"
	if card["special_effect"] != "attribute_change":
		card["special_attribute"] = "none"
	card["rarity"] = auto_rarity(card)
	card["price"] = clampi(
		int(card.get("price", suggested_price(card))),
		0,
		99
	)

func _effects_for_card(card: Dictionary) -> Array:
	var effects: Variant = card.get("effects", [])
	if effects is Array and not effects.is_empty():
		return effects
	return [{
		"effect": String(card.get("effect", "attack")),
		"power": int(card.get("power", 10)),
		"target": String(card.get("target", "enemy")),
		"chance": 100,
		"weight": 1,
	}]

func _default_cards() -> Array[Dictionary]:
	var defaults: Array[Dictionary] = [
		_builtin_card("001", "石つぶて", "小さいが扱いやすい一撃。", "weapon", "enemy", "attack", 8, "none"),
		_builtin_card("002", "錆びた剣", "切れ味より勢いで斬る。", "weapon", "enemy", "attack", 10, "none"),
		_builtin_card("003", "長い棒", "思ったより遠くまで届く。", "weapon", "enemy", "attack", 6, "none"),
		_builtin_card("004", "投げレンガ", "建材としても武器としても雑に強い。", "weapon", "enemy", "attack", 12, "earth"),
		_builtin_card("005", "鉄のフライパン", "いい音が鳴る。", "weapon", "enemy", "attack", 9, "none"),
		_builtin_card("006", "二度見パンチ", "一度見てからもう一度殴る。", "weapon", "enemy", "attack", 7, "none"),
		_builtin_card("007", "火炎びん", "割れた場所がよく燃える。", "weapon", "enemy", "attack", 11, "fire"),
		_builtin_card("008", "赤熱の剣", "刃が赤くなるまで温めた。", "weapon", "enemy", "attack", 14, "fire"),
		_builtin_card("009", "小さな火事", "小さいのでたぶん大丈夫。", "weapon", "all_enemies", "attack", 5, "fire"),
		_builtin_card("010", "熱湯", "取り扱い注意。", "weapon", "enemy", "attack", 8, "water"),
		_builtin_card("011", "水圧カッター", "水も速ければ刃になる。", "weapon", "enemy", "attack", 13, "water"),
		_builtin_card("012", "突然の大雨", "全員まとめてずぶ濡れ。", "weapon", "all_enemies", "attack", 6, "water"),
		_builtin_card("013", "丸太スイング", "持ち上げられれば強い。", "weapon", "enemy", "attack", 15, "wood"),
		_builtin_card("014", "トゲつき枝", "地味に痛い。", "weapon", "enemy", "attack", 7, "wood"),
		_builtin_card("015", "暴れるツタ", "敵全員の足元に絡みつく。", "weapon", "all_enemies", "attack", 5, "wood"),
		_builtin_card("016", "岩石ハンマー", "ほぼ岩。柄だけが良心。", "weapon", "enemy", "attack", 16, "earth"),
		_builtin_card("017", "砂かけ", "目を開けていられない。", "weapon", "enemy", "attack", 5, "earth"),
		_builtin_card("018", "局地的地震", "自分の周り以外が揺れる。", "weapon", "all_enemies", "attack", 7, "earth"),
		_builtin_card("019", "懐中電灯ビーム", "目に直接当ててはいけない。", "weapon", "enemy", "attack", 5, "light"),
		_builtin_card("020", "聖なるハリセン", "いい音と一緒に邪気を払う。", "weapon", "enemy", "attack", 8, "light"),
		_builtin_card("021", "まぶしすぎる朝", "全員が強制的に起こされる。", "weapon", "all_enemies", "attack", 3, "light"),
		_builtin_card("022", "黒い針", "小さな傷から闇が入る。", "weapon", "enemy", "attack", 30, "dark"),
		_builtin_card("023", "呪いの封筒", "開けた相手はだいたい後悔する。", "weapon", "enemy", "attack", 45, "dark"),
		_builtin_card("024", "深夜二時", "全員の判断力が落ちる時間。", "weapon", "all_enemies", "attack", 15, "dark"),
		_builtin_card("025", "嵐の一撃", "敵全員へ順番に攻撃する。", "weapon", "all_enemies", "attack", 6, "none"),
		_builtin_card("026", "ちゃぶ台返し", "敵全員の予定を台無しにする。", "weapon", "all_enemies", "attack", 8, "none"),
		_builtin_card("027", "力の秘薬", "攻撃に重ねて威力を足せる。", "weapon", "enemy", "buff", 5, "none"),
		_builtin_card("028", "追いしょうゆ", "なぜか攻撃のキレが増す。", "weapon", "enemy", "buff", 3, "water"),
		_builtin_card("029", "予備の火薬", "火属性の攻撃に足したい。", "weapon", "enemy", "buff", 6, "fire"),
		_builtin_card("030", "よくしなる柄", "木属性の攻撃をもうひと押し。", "weapon", "enemy", "buff", 4, "wood"),
		_builtin_card("031", "重たい先端", "重さはだいたい正義。", "weapon", "enemy", "buff", 7, "earth"),
		_builtin_card("032", "スポットライト", "主役の一撃を派手にする。", "weapon", "enemy", "buff", 4, "light"),
		_builtin_card("033", "不穏なささやき", "攻撃に嫌な感じを足す。", "weapon", "enemy", "buff", 20, "dark"),
		_builtin_card("034", "みんなで押す", "狙った相手への攻撃をみんなで後押しする。", "weapon", "enemy", "buff", 3, "none"),
		_builtin_card("035", "木の盾", "素朴で頼れる盾。", "armor", "self", "guard", 10, "none"),
		_builtin_card("036", "鍋のふた", "取っ手が握りやすい。", "armor", "self", "guard", 6, "none"),
		_builtin_card("037", "分厚い辞書", "知識と紙の厚みで防ぐ。", "armor", "self", "guard", 8, "none"),
		_builtin_card("038", "段ボール要塞", "雨さえ降らなければ完璧。", "armor", "self", "guard", 12, "none"),
		_builtin_card("039", "防火エプロン", "水と光の代わりにはならない。", "armor", "self", "guard", 7, "fire"),
		_builtin_card("040", "炎のマント", "燃えているので近寄りにくい。", "armor", "self", "guard", 11, "fire"),
		_builtin_card("041", "水の膜", "熱を受け流す薄い壁。", "armor", "self", "guard", 7, "water"),
		_builtin_card("042", "巨大な氷", "溶けるまではかなり硬い。", "armor", "self", "guard", 13, "water"),
		_builtin_card("043", "木製バリケード", "岩を受け止めるための柵。", "armor", "self", "guard", 8, "wood"),
		_builtin_card("044", "竹の鎧", "軽くて意外と丈夫。", "armor", "self", "guard", 12, "wood"),
		_builtin_card("045", "土の壁", "植物の勢いをどっしり止める。", "armor", "self", "guard", 9, "earth"),
		_builtin_card("046", "石室", "閉じこもると声がよく響く。", "armor", "self", "guard", 14, "earth"),
		_builtin_card("047", "光のカーテン", "多くの属性攻撃をやわらげる。", "armor", "self", "guard", 6, "light"),
		_builtin_card("048", "天使の非常口", "危ないときだけ光る。", "armor", "self", "guard", 10, "light"),
		_builtin_card("049", "闇色のコート", "暗い場所では見つかりにくい。", "armor", "self", "guard", 8, "dark"),
		_builtin_card("050", "影の押し入れ", "中に隠れてやり過ごす。", "armor", "self", "guard", 12, "dark"),
		_builtin_card("051", "鏡の盾", "攻撃カードを使った相手へそのまま返す。", "armor", "self", "reflect", 0, "none", ["attack_reflect"]),
		_builtin_card("052", "磨いたお盆", "攻撃カードを使った相手へそのまま返す。", "armor", "self", "reflect", 0, "light", ["attack_reflect"]),
		_builtin_card("053", "水鏡", "奇跡カードを使った相手へそのまま返す。", "armor", "self", "reflect", 0, "water", ["miracle_reflect"]),
		_builtin_card("054", "オウム返し", "奇跡カードを使った相手へそのまま返す。", "armor", "self", "reflect", 0, "wood", ["miracle_reflect"]),
		_builtin_card("055", "反射する溶岩", "攻撃カードを使った相手へそのまま返す。", "armor", "self", "reflect", 0, "fire", ["attack_reflect"]),
		_builtin_card("056", "黒い鏡", "種類を問わず、カードを使った相手へそのまま返す。", "armor", "self", "reflect", 0, "dark", ["full_reflect"]),
		_builtin_card("057", "祝福の水", "覚えると何度でもHPを回復できる。", "miracle", "self", "heal", 12, "none"),
		_builtin_card("058", "ばんそうこう", "奇跡と呼ぶには少し地味。", "miracle", "self", "heal", 5, "none"),
		_builtin_card("059", "よく寝た", "睡眠はだいたいの問題を解決する。", "miracle", "self", "heal", 9, "none"),
		_builtin_card("060", "森の休憩所", "木陰でひと息つく。", "miracle", "self", "heal", 10, "none"),
		_builtin_card("061", "大地のぬくもり", "地面から元気を分けてもらう。", "miracle", "self", "heal", 14, "none"),
		_builtin_card("062", "朝日の祝福", "今日はなんとかなる気がする。", "miracle", "self", "heal", 16, "none"),
		_builtin_card("063", "闇の休息", "誰にも見つからず静かに休む。", "miracle", "self", "heal", 8, "none"),
		_builtin_card("064", "気合いで治す", "理屈はないが少し元気になる。", "miracle", "self", "heal", 7, "none"),
		_builtin_card("065", "天からたらい", "古典的だが避けにくい奇跡。", "miracle", "enemy", "attack", 9, "none"),
		_builtin_card("066", "プチ落雷", "小規模でも雷は雷。", "miracle", "enemy", "attack", 11, "light"),
		_builtin_card("067", "燃える予言", "書かれた未来が燃え上がる。", "miracle", "enemy", "attack", 10, "fire"),
		_builtin_card("068", "洪水の予告", "予告だけでは終わらない。", "miracle", "all_enemies", "attack", 5, "water"),
		_builtin_card("069", "森の総意", "木々が全員まとめて怒る。", "miracle", "all_enemies", "attack", 5, "wood"),
		_builtin_card("070", "小さな終末", "名前ほど小さくない終末。", "miracle", "enemy", "attack", 45, "dark"),
		_builtin_card("071", "非常食", "賞味期限は見なかったことにする。", "special", "self", "heal", 6, "none"),
		_builtin_card("072", "高級おにぎり", "具が二種類入っている。", "special", "self", "heal", 10, "none"),
		_builtin_card("073", "あやしい栄養剤", "元気にはなる。たぶん。", "special", "self", "heal", 13, "none"),
		_builtin_card("074", "予備バッテリー", "光る攻撃を少し強くする。", "special", "enemy", "buff", 4, "light"),
		_builtin_card("075", "ポケットの砂糖", "攻撃前のすばやい補給。", "special", "enemy", "buff", 5, "none"),
		_builtin_card("076", "最後の一本", "ここぞという時まで取っておいた。", "special", "enemy", "buff", 8, "fire"),
		_builtin_card("077", "みんなで休憩", "生きている全員がひと息つく。", "miracle", "all_players", "heal", 5, "none"),
		_builtin_card("078", "恵みの雨", "敵味方の区別なく全員を潤す。", "miracle", "all_players", "heal", 8, "none"),
		_builtin_card("079", "世界樹のおすそわけ", "生きている全員へ生命力を配る。", "miracle", "all_players", "heal", 12, "none"),
		_builtin_card("080", "救急箱を回す", "全員で順番に手当てする。", "special", "all_players", "heal", 6, "none"),
		{
			"id": "builtin-081", "name": "攻防一体", "description": "自分のターンは攻撃、相手の攻撃には防具として使える。",
			"image_path": "", "type": "weapon", "target": "enemy", "effect": "attack", "power": 10,
			"attribute": "none", "chance": 85, "effect_mode": "all", "tags": ["builtin"],
			"effects": [
				{"effect": "attack", "power": 10, "target": "enemy", "chance": 100, "weight": 1},
				{"effect": "guard", "power": 6, "target": "self", "chance": 100, "weight": 1},
			],
		},
		{
			"id": "builtin-082", "name": "癒やしの鎧", "description": "自分のターンは回復、相手の攻撃には防具として使える。",
			"image_path": "", "type": "armor", "target": "self", "effect": "guard", "power": 8,
			"attribute": "light", "chance": 80, "effect_mode": "all", "tags": ["builtin"],
			"effects": [
				{"effect": "guard", "power": 8, "target": "self", "chance": 100, "weight": 1},
				{"effect": "heal", "power": 5, "target": "self", "chance": 100, "weight": 1},
			],
		},
		{
			"id": "builtin-083", "name": "ロシアンルーレット", "description": "6分の1で即死。それ以外ならHPを30回復。",
			"image_path": "", "type": "special", "target": "self", "effect": "instant_death", "power": 0,
			"attribute": "none", "chance": 100, "effect_mode": "random_one", "tags": ["builtin"],
			"effects": [
				{"effect": "instant_death", "power": 0, "target": "self", "chance": 100, "weight": 1},
				{"effect": "heal", "power": 30, "target": "self", "chance": 100, "weight": 5},
			],
		},
		{
			"id": "builtin-084", "name": "買う",
			"description": "相手の手札から1枚を提示し、合計価格ぶんの金でまとめて買える。",
			"image_path": "", "type": "trade", "target": "enemy", "effect": "buy", "power": 1,
			"attribute": "none", "chance": 100, "effect_mode": "all",
			"tags": ["builtin"], "price": 5,
		},
		{
			"id": "builtin-085", "name": "売る",
			"description": "自分の手札1枚を相手へ強制的に売り、価格ぶんの金を受け取る。",
			"image_path": "", "type": "trade", "target": "enemy", "effect": "sell", "power": 1,
			"attribute": "none", "chance": 100, "effect_mode": "all",
			"tags": ["builtin"], "price": 5,
		},
		{
			"id": "builtin-086", "name": "両替",
			"description": "HP・MP・金の合計を保ったまま、好きな配分へ振り分ける。",
			"image_path": "", "type": "trade", "target": "self", "effect": "exchange", "power": 0,
			"attribute": "none", "chance": 100, "effect_mode": "all",
			"tags": ["builtin"], "price": 5,
		},
	]
	for card: Dictionary in defaults:
		_normalize_card(card)
	return defaults

func _builtin_card(
	id_suffix: String,
	card_name: String,
	card_description: String,
	card_type: String,
	card_target: String,
	card_effect: String,
	card_power: int,
	card_attribute: String,
	extra_tags: Array = []
) -> Dictionary:
	return {
		"id": "builtin-%s" % id_suffix,
		"name": card_name,
		"description": card_description,
		"image_path": "",
		"type": card_type,
		"target": card_target,
		"effect": card_effect,
		"power": card_power,
		"attribute": card_attribute,
		"tags": ["builtin"] + extra_tags,
	}
