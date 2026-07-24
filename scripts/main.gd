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
@onready var full_reflect_check: CheckBox = $Root/Tabs/Cards/Editor/EffectRow/FullReflect
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
	_apply_ui_theme()
	_setup_options()
	_apply_help_tooltips()
	_refresh_second_effect_controls()
	_refresh_full_reflect_visibility()
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
	effect.item_selected.connect(func(_index): _apply_type_defaults(); _refresh_full_reflect_visibility(); _update_rarity_preview())
	second_effect.item_selected.connect(func(_index): _apply_type_defaults(); _refresh_full_reflect_visibility(); _update_rarity_preview())
	target.item_selected.connect(func(_index): _update_rarity_preview())
	second_target.item_selected.connect(func(_index): _update_rarity_preview())
	power.value_changed.connect(func(_v): _update_rarity_preview())
	second_power.value_changed.connect(func(_v): _update_rarity_preview())
	chance.value_changed.connect(func(_v): _update_rarity_preview())
	effect_mode.item_selected.connect(func(_index): _update_rarity_preview())
	weight1.value_changed.connect(func(_v): _update_rarity_preview())
	second_weight.value_changed.connect(func(_v): _update_rarity_preview())
	second_effect_enabled.toggled.connect(func(_enabled): _refresh_second_effect_controls(); _apply_type_defaults(); _refresh_full_reflect_visibility(); _update_rarity_preview())
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
	# 完全反射はチェックボックスで on/off する。反射効果を外した場合も
	# 古い "full_reflect" タグが残らないよう、効果データを基準に同期する。
	var tags: Array[String] = _parse_tags(tags_edit.text)
	var has_reflect := false
	for effect_entry: Dictionary in effects:
		if String(effect_entry.get("effect", "")) == "reflect":
			has_reflect = true
			break
	if has_reflect and full_reflect_check.button_pressed:
		if "full_reflect" not in tags:
			tags.append("full_reflect")
	else:
		tags.erase("full_reflect")
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
		"tags": tags,
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
	full_reflect_check.button_pressed = "full_reflect" in card.get("tags", [])
	_refresh_full_reflect_visibility()
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
	full_reflect_check.button_pressed = false
	_refresh_full_reflect_visibility()
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

func _refresh_full_reflect_visibility() -> void:
	# 反射を選んだときだけ「完全反射」チェックを見せる。
	var is_reflect: bool = _option_key(effect) == "reflect"
	if second_effect_enabled.button_pressed and _option_key(second_effect) == "reflect":
		is_reflect = true
	full_reflect_check.visible = is_reflect
	if not is_reflect:
		full_reflect_check.button_pressed = false

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

# ---- 見た目（バトル画面と揃えた明るいテーマ） -----------------------------
# バトル画面はコード側で独自に着色しているので、ここで作るテーマは root（ロビー／
# カード編集）だけに割り当て、バトル画面へは影響させない。

const INK := Color("#2b4650")          # 主要な文字色
const MUTED := Color("#6d8189")        # 補助文字・プレースホルダ
const PRIMARY := Color("#008f78")      # 主要ボタン（バトル画面と同じ緑）
const PRIMARY_HOVER := Color("#00a894")
const PRIMARY_PRESSED := Color("#007564")
const SURFACE := Color("#fbfffc")      # パネル面
const INPUT_BG := Color("#ffffff")     # 入力欄の背景
const INPUT_BORDER := Color("#bcdcd2") # 入力欄・パネルの枠
const FOCUS_BORDER := Color("#00a894") # フォーカス時の枠

func _apply_ui_theme() -> void:
	root.theme = _build_ui_theme()

func _build_ui_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", INK)

	# パネル類（タブの中身の下地やログ・一覧の枠に使う）
	var surface_box: StyleBoxFlat = _flat(SURFACE, INPUT_BORDER, 1, 12, 10, 12)
	theme.set_stylebox("panel", "PanelContainer", surface_box)
	theme.set_stylebox("panel", "Panel", surface_box)

	# 主要ボタン（ホスト開始・参加・保存など）
	theme.set_stylebox("normal", "Button", _flat(PRIMARY, PRIMARY, 0, 9, 7, 14))
	theme.set_stylebox("hover", "Button", _flat(PRIMARY_HOVER, PRIMARY_HOVER, 0, 9, 7, 14))
	theme.set_stylebox("pressed", "Button", _flat(PRIMARY_PRESSED, PRIMARY_PRESSED, 0, 9, 7, 14))
	theme.set_stylebox("disabled", "Button", _flat(Color("#cbd6d1"), Color("#cbd6d1"), 0, 9, 7, 14))
	theme.set_stylebox("focus", "Button", _flat(Color(0, 0, 0, 0), FOCUS_BORDER, 2, 9, 7, 14))
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("#8b9a92"))

	# 入力欄（名前・説明・タグ・IP など）
	var input_box: StyleBoxFlat = _flat(INPUT_BG, INPUT_BORDER, 1, 8, 5, 9)
	var input_focus: StyleBoxFlat = _flat(INPUT_BG, FOCUS_BORDER, 2, 8, 5, 9)
	for input_type: String in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", input_type, input_box)
		theme.set_stylebox("focus", input_type, input_focus)
		theme.set_stylebox("read_only", input_type, _flat(Color("#eef4f1"), INPUT_BORDER, 1, 8, 5, 9))
		theme.set_color("font_color", input_type, INK)
		theme.set_color("font_readonly_color", input_type, MUTED)
		theme.set_color("caret_color", input_type, PRIMARY)
		theme.set_color("font_selected_color", input_type, Color.WHITE)
		theme.set_color("selection_color", input_type, Color(0.0, 0.56, 0.47, 0.35))
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("font_placeholder_color", "TextEdit", MUTED)

	# 選択肢ボタン（種類・対象・効果・属性…）は入力欄と同じ淡い見た目にして、
	# 主要ボタン（緑）と役割を見分けやすくする。
	theme.set_stylebox("normal", "OptionButton", _flat(INPUT_BG, INPUT_BORDER, 1, 8, 5, 9))
	theme.set_stylebox("hover", "OptionButton", _flat(Color("#eef8f4"), FOCUS_BORDER, 1, 8, 5, 9))
	theme.set_stylebox("pressed", "OptionButton", _flat(Color("#e3f3ee"), FOCUS_BORDER, 1, 8, 5, 9))
	theme.set_stylebox("disabled", "OptionButton", _flat(Color("#eef4f1"), INPUT_BORDER, 1, 8, 5, 9))
	theme.set_stylebox("focus", "OptionButton", _flat(Color(0, 0, 0, 0), FOCUS_BORDER, 2, 8, 5, 9))
	theme.set_color("font_color", "OptionButton", INK)
	theme.set_color("font_hover_color", "OptionButton", INK)
	theme.set_color("font_pressed_color", "OptionButton", INK)
	theme.set_color("font_focus_color", "OptionButton", INK)
	theme.set_color("font_disabled_color", "OptionButton", MUTED)

	# 数値入力（SpinBox は内部で LineEdit を使うので上の設定が効く）
	theme.set_color("font_color", "SpinBox", INK)

	# チェックボックス
	theme.set_color("font_color", "CheckBox", INK)
	theme.set_color("font_hover_color", "CheckBox", INK)
	theme.set_color("font_pressed_color", "CheckBox", INK)

	# タブ（ロビー / カード）
	theme.set_stylebox("panel", "TabContainer", _flat(SURFACE, INPUT_BORDER, 1, 12, 12, 12))
	theme.set_stylebox("tab_selected", "TabContainer", _flat(PRIMARY, PRIMARY, 0, 8, 7, 18))
	theme.set_stylebox("tab_unselected", "TabContainer", _flat(Color("#dcece7"), Color("#c7ddd6"), 1, 8, 7, 18))
	theme.set_stylebox("tab_hovered", "TabContainer", _flat(Color("#e9f5f0"), Color("#c7ddd6"), 1, 8, 7, 18))
	theme.set_stylebox("tabbar_background", "TabContainer", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_color("font_hovered_color", "TabContainer", INK)
	theme.set_font_size("font_size", "TabContainer", 17)

	# 一覧（カード一覧・プレイヤー一覧）
	theme.set_stylebox("panel", "ItemList", _flat(INPUT_BG, INPUT_BORDER, 1, 10, 6, 8))
	theme.set_stylebox("selected", "ItemList", _flat(PRIMARY, PRIMARY, 0, 7, 4, 6))
	theme.set_stylebox("selected_focus", "ItemList", _flat(PRIMARY, PRIMARY, 0, 7, 4, 6))
	theme.set_stylebox("hovered", "ItemList", _flat(Color("#e9f5f0"), Color(0, 0, 0, 0), 0, 7, 4, 6))
	theme.set_stylebox("cursor", "ItemList", _flat(Color(0, 0, 0, 0), PRIMARY, 1, 7, 4, 6))
	theme.set_stylebox("cursor_unfocused", "ItemList", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 7, 4, 6))
	theme.set_color("font_color", "ItemList", INK)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_hovered_color", "ItemList", INK)
	theme.set_constant("v_separation", "ItemList", 4)

	# ログ表示
	theme.set_color("default_color", "RichTextLabel", INK)

	# ドロップダウンのメニュー
	theme.set_stylebox("panel", "PopupMenu", _flat(SURFACE, INPUT_BORDER, 1, 10, 6, 6))
	theme.set_stylebox("hover", "PopupMenu", _flat(Color("#e9f5f0"), Color(0, 0, 0, 0), 0, 6, 4, 6))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", INK)

	return theme

func _flat(fill: Color, border: Color, border_width: int, radius: int, margin_v: int, margin_h: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box

func _apply_help_tooltips() -> void:
	# 用語が硬めなので、マウスを乗せると意味が出るよう補足を付ける。
	player_name_edit.tooltip_text = "対戦相手に表示される名前です。"
	host_button.tooltip_text = "自分がホスト（親）になって部屋を開きます。"
	join_button.tooltip_text = "ホストのIPとポートを入力してから押すと部屋に参加します。"
	submit_cards_button.tooltip_text = "作ったカードを画像ごとホストへ送ります。"
	start_game_button.tooltip_text = "ホスト用。全員のカードが集まったら押すとバトルが始まります。"
	debug_bot_button.tooltip_text = "動作確認用。ランダムに行動する練習相手を1体追加します。"
	name_edit.tooltip_text = "カードの名前。"
	description_edit.tooltip_text = "カードに書く説明・フレーバーテキスト。"
	card_type.tooltip_text = "武器・防具・奇跡・特殊のどれかを選びます。"
	target.tooltip_text = "効果が誰に向くか（敵1体・自分・敵全体・全員）。"
	effect.tooltip_text = "カードの効果（攻撃・防御・回復など）。"
	full_reflect_check.tooltip_text = "オンにすると攻撃だけでなく、奇跡・即死などサポート系も含めて全部を跳ね返す「完全反射」になります。"
	power.tooltip_text = "効果の強さ。攻撃なら威力、回復なら回復量。"
	attribute.tooltip_text = "属性。防御できる相手や相性に影響します（回復のみは属性なし）。"
	chance.tooltip_text = "この効果が発動する確率（%）。"
	effect_mode.tooltip_text = "効果を2つ持つとき、両方出すか・どちらか一方を抽選するか。"
	weight1.tooltip_text = "「どちらか一方」を選んだときの、効果1が出やすさの比率。"
	second_effect_enabled.tooltip_text = "1枚のカードに2つ目の効果を持たせます。"
	second_weight.tooltip_text = "「どちらか一方」のときの効果2の比率。"
	tags_edit.tooltip_text = "カンマ区切りのタグ（例: full_reflect）。分類や特殊挙動に使います。"
