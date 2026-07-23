extends Control

@onready var root: VBoxContainer = $Root
@onready var tabs: TabContainer = $Root/Tabs
@onready var battle_screen: Control = $BattleScreen
@onready var host_button: Button = $Root/Tabs/Lobby/ConnectRow/HostButton
@onready var join_address: LineEdit = $Root/Tabs/Lobby/ConnectRow/JoinAddress
@onready var join_port: SpinBox = $Root/Tabs/Lobby/ConnectRow/JoinPort
@onready var join_button: Button = $Root/Tabs/Lobby/ConnectRow/JoinButton
@onready var submit_cards_button: Button = $Root/Tabs/Lobby/ActionRow/SubmitCardsButton
@onready var start_game_button: Button = $Root/Tabs/Lobby/ActionRow/StartGameButton
@onready var debug_bot_button: Button = $Root/Tabs/Lobby/ActionRow/DebugBotButton
@onready var network_info: RichTextLabel = $Root/Tabs/Lobby/NetworkInfo
@onready var players_list: ItemList = $Root/Tabs/Lobby/Players
@onready var card_list: ItemList = $Root/Tabs/Cards/CardList
@onready var name_edit: LineEdit = $Root/Tabs/Cards/Editor/Name
@onready var description_edit: TextEdit = $Root/Tabs/Cards/Editor/Description
@onready var choose_image_button: Button = $Root/Tabs/Cards/Editor/ImageRow/ChooseImageButton
@onready var image_name: Label = $Root/Tabs/Cards/Editor/ImageRow/ImageName
@onready var image_preview: TextureRect = $Root/Tabs/Cards/Editor/ImagePreview
@onready var image_file_dialog: FileDialog = $ImageFileDialog
@onready var card_type: OptionButton = $Root/Tabs/Cards/Editor/TypeRow/CardType
@onready var target: OptionButton = $Root/Tabs/Cards/Editor/TypeRow/Target
@onready var effect: OptionButton = $Root/Tabs/Cards/Editor/EffectRow/Effect
@onready var power: SpinBox = $Root/Tabs/Cards/Editor/NumberAttrRow/Power
@onready var attribute: OptionButton = $Root/Tabs/Cards/Editor/NumberAttrRow/Attribute
@onready var chance: SpinBox = $Root/Tabs/Cards/Editor/ProbabilityRow/Chance
@onready var effect_mode: OptionButton = $Root/Tabs/Cards/Editor/ProbabilityRow/EffectMode
@onready var weight1: SpinBox = $Root/Tabs/Cards/Editor/ProbabilityRow/Weight1
@onready var second_effect_enabled: CheckBox = $Root/Tabs/Cards/Editor/SecondEffectRow/Enabled
@onready var second_effect: OptionButton = $Root/Tabs/Cards/Editor/SecondEffectRow/Effect
@onready var second_target: OptionButton = $Root/Tabs/Cards/Editor/SecondEffectRow/Target
@onready var second_power: SpinBox = $Root/Tabs/Cards/Editor/SecondEffectRow/Power
@onready var second_weight: SpinBox = $Root/Tabs/Cards/Editor/SecondEffectRow/Weight
@onready var tags_edit: LineEdit = $Root/Tabs/Cards/Editor/Tags
@onready var save_card_button: Button = $Root/Tabs/Cards/Editor/SaveCardButton
@onready var rarity_label: Label = $Root/Tabs/Cards/Editor/RarityLabel
@onready var new_card_button: Button = $Root/Tabs/Cards/Editor/NewCardButton
@onready var delete_card_button: Button = $Root/Tabs/Cards/Editor/DeleteCardButton
@onready var player_name_edit: LineEdit = $Root/Tabs/Lobby/NameRow/PlayerName

var selected_card_id := ""
var selected_image_path := ""

# 表示は日本語、保存する内部値は英語キー。[キー, 表示ラベル] の順で持つ。
const TYPE_OPTIONS: Array = [["weapon", "武器"], ["armor", "防具"], ["miracle", "奇跡"], ["special", "特殊アイテム"]]
const TARGET_OPTIONS: Array = [["enemy", "敵1体"], ["self", "自分"], ["all_enemies", "敵全体"], ["all_players", "全員"]]
const EFFECT_OPTIONS: Array = [["attack", "攻撃"], ["buff", "攻撃力アップ"], ["guard", "防御"], ["reflect", "反射"], ["heal", "回復"], ["instant_death", "即死"]]
const EFFECT_MODE_OPTIONS: Array = [["all", "用途別に発動"], ["random_one", "どちらか一方"]]
const ATTRIBUTE_OPTIONS: Array = [["none", "無"], ["fire", "火"], ["water", "水"], ["wood", "木"], ["earth", "土"], ["light", "光"], ["dark", "闇"]]
const RARITY_LABELS: Dictionary = {"common": "コモン", "uncommon": "アンコモン", "rare": "レア", "legendary": "レジェンダリー"}

func _ready() -> void:
	_setup_options()
	_refresh_second_effect_controls()
	_connect_signals()
	_refresh_cards()
	_log("カードはイラスト画像込みでホストへ送り、ホストが全員へ配り直します。")

func _setup_options() -> void:
	_fill_options(card_type, TYPE_OPTIONS)
	_fill_options(target, TARGET_OPTIONS)
	_fill_options(effect, EFFECT_OPTIONS)
	_fill_options(second_effect, EFFECT_OPTIONS)
	_fill_options(second_target, TARGET_OPTIONS)
	_fill_options(effect_mode, EFFECT_MODE_OPTIONS)
	_fill_options(attribute, ATTRIBUTE_OPTIONS)

func _fill_options(option: OptionButton, pairs: Array) -> void:
	option.clear()
	for pair: Array in pairs:
		option.add_item(String(pair[1]))
		option.set_item_metadata(option.item_count - 1, String(pair[0]))

func _option_key(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))

func _connect_signals() -> void:
	host_button.pressed.connect(func(): Net.host(int(join_port.value), player_name_edit.text.strip_edges()))
	join_button.pressed.connect(func(): Net.join(join_address.text.strip_edges(), int(join_port.value), player_name_edit.text.strip_edges()))
	submit_cards_button.pressed.connect(func(): Net.send_my_cards(CardStore.export_cards_with_images()))
	start_game_button.pressed.connect(Net.start_game)
	debug_bot_button.pressed.connect(Net.add_debug_bot)
	save_card_button.pressed.connect(_save_current_card)
	new_card_button.pressed.connect(_clear_editor)
	delete_card_button.pressed.connect(_delete_current_card)
	choose_image_button.pressed.connect(func(): image_file_dialog.popup_centered_ratio(0.8))
	image_file_dialog.file_selected.connect(_on_image_selected)
	card_type.item_selected.connect(func(_index): _apply_type_defaults(); _update_rarity_preview())
	effect.item_selected.connect(func(_index): _apply_type_defaults(); _update_rarity_preview())
	second_effect.item_selected.connect(func(_index): _apply_type_defaults(); _update_rarity_preview())
	target.item_selected.connect(func(_index): _update_rarity_preview())
	second_target.item_selected.connect(func(_index): _update_rarity_preview())
	power.value_changed.connect(func(_v): _update_rarity_preview())
	second_power.value_changed.connect(func(_v): _update_rarity_preview())
	chance.value_changed.connect(func(_v): _update_rarity_preview())
	effect_mode.item_selected.connect(func(_index): _update_rarity_preview())
	weight1.value_changed.connect(func(_v): _update_rarity_preview())
	second_weight.value_changed.connect(func(_v): _update_rarity_preview())
	second_effect_enabled.toggled.connect(func(_enabled): _refresh_second_effect_controls(); _apply_type_defaults(); _update_rarity_preview())
	card_list.item_selected.connect(_load_card_at)
	Net.status_changed.connect(_log)
	Net.players_changed.connect(_refresh_players)
	Net.cards_synced.connect(func(cards): _log("対戦用の共有カード: %d枚" % cards.size()))
	Net.game_state_synced.connect(_show_game_state)
	battle_screen.card_play_requested.connect(Net.submit_play)
	battle_screen.defense_cards_requested.connect(Net.submit_defense)
	battle_screen.pass_defense_requested.connect(Net.pass_defense)
	battle_screen.pray_requested.connect(Net.submit_pray)
	battle_screen.leave_requested.connect(_leave_battle)

func _save_current_card() -> void:
	var entered_effect: String = _option_key(effect)
	var entered_target: String = _option_key(target)
	var effects: Array = [{
		"effect": entered_effect,
		"power": int(power.value),
		"target": entered_target,
		"chance": 100,
		"weight": int(weight1.value),
	}]
	if second_effect_enabled.button_pressed:
		effects.append({
			"effect": _option_key(second_effect),
			"power": int(second_power.value),
			"target": _option_key(second_target),
			"chance": 100,
			"weight": int(second_weight.value),
		})
	var card: Dictionary = {
		"id": selected_card_id,
		"name": name_edit.text.strip_edges(),
		"description": description_edit.text.strip_edges(),
		"image_path": selected_image_path,
		"type": _option_key(card_type),
		"target": entered_target,
		"effect": entered_effect,
		"power": int(power.value),
		"attribute": _option_key(attribute),
		"chance": int(chance.value),
		"effect_mode": _option_key(effect_mode),
		"effects": effects,
		"tags": _parse_tags(tags_edit.text),
	}
	var saved: Dictionary = CardStore.upsert_card(card)
	selected_card_id = String(saved["id"])
	_refresh_cards()
	var msg: String = "%s を保存。レアリティ: %s" % [saved["name"], _rarity_label(String(saved["rarity"]))]
	if String(saved.get("effect", "")) != entered_effect:
		msg += "（効果「%s」→「%s」に自動変更）" % [_label_for(EFFECT_OPTIONS, entered_effect), _label_for(EFFECT_OPTIONS, String(saved["effect"]))]
	if String(saved.get("target", "")) != entered_target:
		msg += "（対象「%s」→「%s」に自動変更）" % [_label_for(TARGET_OPTIONS, entered_target), _label_for(TARGET_OPTIONS, String(saved["target"]))]
	_log(msg)
	for index in range(CardStore.cards.size()):
		if String(CardStore.cards[index].get("id", "")) == selected_card_id:
			card_list.select(index)
			_load_card_at(index)
			break

func _delete_current_card() -> void:
	if selected_card_id.is_empty():
		return
	CardStore.delete_card(selected_card_id)
	_clear_editor()
	_refresh_cards()
	_log("カードを削除しました。")

func _refresh_cards() -> void:
	card_list.clear()
	for card in CardStore.cards:
		card_list.add_item("%s [%s] %s %d" % [
			card["name"], _rarity_label(String(card["rarity"])), _kind_summary(card), int(card["power"])
		])
	delete_card_button.disabled = selected_card_id.is_empty()

func _label_for(pairs: Array, key: String) -> String:
	for pair: Array in pairs:
		if String(pair[0]) == key:
			return String(pair[1])
	return key

func _rarity_label(rarity: String) -> String:
	return String(RARITY_LABELS.get(rarity, rarity))

func _kind_summary(card: Dictionary) -> String:
	var labels: Array[String] = []
	for effect_entry: Dictionary in card.get("effects", [{
		"effect": card.get("effect", ""),
		"target": card.get("target", ""),
	}]):
		var label: String = _label_for(EFFECT_OPTIONS, String(effect_entry.get("effect", "")))
		if String(effect_entry.get("target", "")) == "all_enemies":
			label += "/敵全体"
		elif String(effect_entry.get("target", "")) == "all_players":
			label += "/全員"
		labels.append(label)
	var separator := " / " if (
		String(card.get("effect_mode", "all")) == "random_one"
		or _uses_contextual_roles(card)
	) else "＋"
	var summary: String = separator.join(labels)
	if int(card.get("chance", 100)) < 100:
		summary += " %d%%" % int(card.get("chance", 100))
	return summary

func _uses_contextual_roles(card: Dictionary) -> bool:
	var has_action_role := false
	var has_defense_role := false
	for effect_entry: Dictionary in card.get("effects", []):
		var effect_name: String = String(effect_entry.get("effect", ""))
		if effect_name in ["attack", "buff", "heal", "instant_death"]:
			has_action_role = true
		elif effect_name in ["guard", "reflect"]:
			has_defense_role = true
	return has_action_role and has_defense_role

func _refresh_players(players: Array) -> void:
	players_list.clear()
	for player in players:
		players_list.add_item("%s / peer %s" % [player.get("name", "Player"), player.get("peer_id", "?")])

func _load_card_at(index: int) -> void:
	if index < 0 or index >= CardStore.cards.size():
		return
	var card: Dictionary = CardStore.cards[index]
	selected_card_id = String(card["id"])
	selected_image_path = String(card["image_path"])
	name_edit.text = String(card["name"])
	description_edit.text = String(card["description"])
	_select_option(card_type, String(card["type"]))
	_select_option(target, String(card["target"]))
	_select_option(effect, String(card["effect"]))
	power.value = int(card["power"])
	_select_option(attribute, String(card["attribute"]))
	chance.value = int(card.get("chance", 100))
	_select_option(effect_mode, String(card.get("effect_mode", "all")))
	var effects: Array = card.get("effects", [])
	weight1.value = int(effects[0].get("weight", 1)) if not effects.is_empty() else 1
	second_effect_enabled.button_pressed = effects.size() > 1
	if effects.size() > 1:
		var second: Dictionary = effects[1]
		_select_option(second_effect, String(second.get("effect", "heal")))
		_select_option(second_target, String(second.get("target", "self")))
		second_power.value = int(second.get("power", 5))
		second_weight.value = int(second.get("weight", 1))
	_refresh_second_effect_controls()
	tags_edit.text = ",".join(card["tags"])
	# 種別に応じた対象の有効/無効などを、読み込んだ内容に合わせて整える。
	_apply_type_defaults()
	_update_rarity_preview()
	_refresh_image_preview()
	delete_card_button.disabled = false

func _clear_editor() -> void:
	selected_card_id = ""
	selected_image_path = ""
	name_edit.clear()
	description_edit.clear()
	tags_edit.clear()
	power.value = 10
	chance.value = 100
	weight1.value = 1
	second_effect_enabled.button_pressed = false
	second_power.value = 5
	second_weight.value = 1
	_select_option(effect_mode, "all")
	_select_option(second_effect, "heal")
	_select_option(second_target, "self")
	_refresh_second_effect_controls()
	image_preview.texture = null
	image_name.text = "画像なし"
	card_type.select(0)
	_apply_type_defaults()
	_select_option(attribute, "none")
	_update_rarity_preview()
	delete_card_button.disabled = true

func _show_game_state(state: Dictionary) -> void:
	root.hide()
	battle_screen.show()
	battle_screen.show_state(state)

func _on_image_selected(path: String) -> void:
	selected_image_path = path
	_refresh_image_preview()

func _refresh_image_preview() -> void:
	image_preview.texture = null
	if selected_image_path.is_empty() or not FileAccess.file_exists(selected_image_path):
		image_name.text = "画像なし"
		return
	var loaded_image: Image = Image.load_from_file(selected_image_path)
	if loaded_image == null or loaded_image.is_empty():
		image_name.text = "画像を読み込めません"
		return
	image_preview.texture = ImageTexture.create_from_image(loaded_image)
	image_name.text = "%s（送信時に画像本体も送ります）" % selected_image_path.get_file()

func _apply_type_defaults() -> void:
	target.disabled = false
	var all_heal: bool = _option_key(effect) == "heal"
	if second_effect_enabled.button_pressed and _option_key(second_effect) != "heal":
		all_heal = false
	if all_heal:
		_select_option(attribute, "none")
	attribute.disabled = all_heal

func _refresh_second_effect_controls() -> void:
	var enabled: bool = second_effect_enabled.button_pressed
	second_effect.disabled = not enabled
	second_target.disabled = not enabled
	second_power.editable = enabled
	second_weight.editable = enabled

func _update_rarity_preview() -> void:
	var temp: Dictionary = {
		"power": int(power.value),
		"effect": _option_key(effect),
		"target": _option_key(target),
		"chance": int(chance.value),
		"effect_mode": _option_key(effect_mode),
		"effects": [{
			"effect": _option_key(effect),
			"power": int(power.value),
			"target": _option_key(target),
			"weight": int(weight1.value),
		}],
	}
	if second_effect_enabled.button_pressed:
		temp["effects"].append({
			"effect": _option_key(second_effect),
			"power": int(second_power.value),
			"target": _option_key(second_target),
			"weight": int(second_weight.value),
		})
	var rarity: String = CardStore.auto_rarity(temp)
	rarity_label.text = "レアリティ: %s" % _rarity_label(rarity)

func _leave_battle() -> void:
	Net.close()
	battle_screen.hide()
	root.show()

func _parse_tags(text: String) -> Array[String]:
	var result: Array[String] = []
	for part in text.split(",", false):
		var tag: String = part.strip_edges()
		if not tag.is_empty():
			result.append(tag)
	return result

func _select_option(option: OptionButton, value: String) -> void:
	# 内部キー（metadata）で一致させる。表示ラベルは日本語なので比較には使わない。
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == value:
			option.select(index)
			return

func _log(message: String) -> void:
	# add_text は BBCode を解釈しないので、カード名やプレイヤー名を安全に表示できる。
	network_info.add_text("%s\n" % message)
	network_info.scroll_to_line(network_info.get_line_count() - 1)
