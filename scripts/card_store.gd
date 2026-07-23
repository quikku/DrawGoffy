extends Node

const CARD_FILE := "user://cards.json"
const SHARED_IMAGE_DIR := "user://card_images"
const VALID_ATTRIBUTES: Array[String] = [
	"none", "fire", "water", "wood", "earth", "light", "dark",
]
const VALID_TYPES: Array[String] = ["weapon", "armor", "miracle", "special"]
const VALID_TARGETS: Array[String] = ["enemy", "self", "all_enemies", "all_players"]
const VALID_EFFECTS: Array[String] = ["attack", "buff", "guard", "reflect", "heal", "instant_death"]
const VALID_EFFECT_MODES: Array[String] = ["all", "random_one"]

var cards: Array[Dictionary] = []
var session_cards: Array[Dictionary] = []

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

func upsert_card(card: Dictionary) -> Dictionary:
	_normalize_card(card)
	card["rarity"] = auto_rarity(card)
	if String(card.get("id", "")).is_empty():
		card["id"] = _make_card_id()
	for index in range(cards.size()):
		if cards[index].get("id") == card["id"]:
			cards[index] = card
			save_cards()
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
		if session_cards[index].get("id") == card["id"]:
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

func auto_rarity(card: Dictionary) -> String:
	var effect_scores: Array[int] = []
	for effect_entry: Dictionary in _effects_for_card(card):
		var effect_score: int = absi(int(effect_entry.get("power", 0)))
		match String(effect_entry.get("effect", "attack")):
			"instant_death":
				effect_score += 45
			"reflect":
				effect_score += 18
			"buff":
				effect_score += 10
			"guard":
				effect_score += 8
			"heal":
				effect_score += 6
		if String(effect_entry.get("target", card.get("target", ""))) in ["all_enemies", "all_players"]:
			effect_score += 15
		effect_scores.append(effect_score)
	var score := 0
	if String(card.get("effect_mode", "all")) == "random_one":
		for effect_score: int in effect_scores:
			score = maxi(score, effect_score)
	else:
		for effect_score: int in effect_scores:
			score += effect_score
	score = int(round(score * clampi(int(card.get("chance", 100)), 0, 100) / 100.0))
	if score >= 45:
		return "legendary"
	if score >= 30:
		return "rare"
	if score >= 16:
		return "uncommon"
	return "common"

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
	if card["target"] not in VALID_TARGETS:
		card["target"] = "self"
	card["chance"] = clampi(int(card.get("chance", 100)), 0, 100)
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
	# 回復だけのカードは属性相性に関与しない。
	var has_non_heal := false
	for effect_entry: Dictionary in normalized_effects:
		if String(effect_entry.get("effect", "")) != "heal":
			has_non_heal = true
	if not has_non_heal:
		card["attribute"] = "none"
	card["rarity"] = auto_rarity(card)

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
	return [
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
		_builtin_card("034", "全員で押す", "敵全員へ向かう攻撃を後押しする。", "weapon", "all_enemies", "buff", 3, "none"),
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
		_builtin_card("051", "鏡の盾", "受け止めた力をそのまま返す。", "armor", "self", "reflect", 10, "none"),
		_builtin_card("052", "磨いたお盆", "顔が映るくらい磨いてある。", "armor", "self", "reflect", 6, "light"),
		_builtin_card("053", "水鏡", "静かな水面が攻撃を映す。", "armor", "self", "reflect", 8, "water"),
		_builtin_card("054", "オウム返し", "やられた分だけ言い返す。", "armor", "self", "reflect", 7, "wood"),
		_builtin_card("055", "反射する溶岩", "かなり危険な鏡。", "armor", "self", "reflect", 11, "fire"),
		_builtin_card("056", "黒い鏡", "回復や支援まで使用者へ返す完全反射。", "armor", "self", "reflect", 5, "dark", ["full_reflect"]),
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
	]

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
