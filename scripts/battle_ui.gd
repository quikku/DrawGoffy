extends Control

signal card_play_requested(card_ids: Array, target_peer_id: int)
signal defense_cards_requested(card_ids: Array[String])
signal pass_defense_requested
signal pray_requested
signal pass_action_requested
signal purchase_response_requested(accept: bool)
signal exchange_requested(card_id: String, hp: int, mp: int, gold: int)
signal leave_requested

@onready var top_bar: PanelContainer = $TopBar
@onready var leave_button: Button = $TopBar/TopRow/LeaveButton
@onready var own_status: PanelContainer = $OwnStatus
@onready var own_status_label: Label = $OwnStatus/Label
@onready var selection_arrow: Label = $SelectionArrow
@onready var target_status: PanelContainer = $TargetStatus
@onready var target_status_label: Label = $TargetStatus/Label
@onready var selected_card_panel: PanelContainer = $SelectedCard
@onready var selected_card_art: TextureRect = $SelectedCard/Row/Art
@onready var selected_card_no_art: Label = $SelectedCard/Row/Art/NoArt
@onready var selected_card_name: Label = $SelectedCard/Row/Details/Name
@onready var selected_card_description: Label = $SelectedCard/Row/Details/Description
@onready var selected_card_value: Label = $SelectedCard/Row/Details/Value
@onready var attack_stack: Control = $AttackCards
@onready var defense_cards_view: Control = $DefenseCards
@onready var attack_total_panel: PanelContainer = $AttackTotalPanel
@onready var attack_total: Label = $AttackTotalPanel/Label
@onready var defense_total_panel: PanelContainer = $DefenseTotalPanel
@onready var defense_total: Label = $DefenseTotalPanel/Label
@onready var card_use_button: Button = $CardUseButton
@onready var opponents: VBoxContainer = $Opponents
@onready var hover_detail_header: PanelContainer = $HoverDetailHeader
@onready var hover_card_detail: PanelContainer = $HoverCardDetail
@onready var hover_card_art: TextureRect = $HoverCardDetail/Margin/Row/Art
@onready var hover_card_no_art: Label = $HoverCardDetail/Margin/Row/Art/NoArt
@onready var hover_card_name: Label = $HoverCardDetail/Margin/Row/Details/Name
@onready var hover_card_attribute_value: Label = $HoverCardDetail/Margin/Row/Details/ValueRow/AttributeValue
@onready var hover_card_price_badge: PanelContainer = $HoverCardDetail/Margin/Row/Details/ValueRow/PriceBadge
@onready var hover_card_price: Label = $HoverCardDetail/Margin/Row/Details/ValueRow/PriceBadge/Price
@onready var hover_card_description: Label = $HoverCardDetail/Margin/Row/Details/Description
@onready var center_message: Label = $CenterMessage
@onready var exchange_panel: PanelContainer = $ExchangePanel
@onready var exchange_values_panel: PanelContainer = $ExchangePanel/Margin/Content/ValuesPanel
@onready var exchange_hp_value: Label = $ExchangePanel/Margin/Content/ValuesPanel/Values/Hp
@onready var exchange_mp_value: Label = $ExchangePanel/Margin/Content/ValuesPanel/Values/Mp
@onready var exchange_gold_value: Label = $ExchangePanel/Margin/Content/ValuesPanel/Values/Gold
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_label: Label = $ResultPanel/Result
@onready var action_button: Button = $ActionButton
@onready var pass_defense_button: Button = $PassDefenseButton
@onready var hand_panel: PanelContainer = $HandPanel
@onready var hand: Control = $HandPanel/Margin/Scroll/Hand
@onready var bottom_bar: PanelContainer = $BottomBar
@onready var bottom_status: Label = $BottomBar/Status

var state: Dictionary = {}
var selected_card: Dictionary = {}
var selected_hand_panel: PanelContainer
var selected_target_peer_id := 0
var card_panels: Dictionary = {}
var target_buttons: Dictionary = {}
var selected_defense_panels: Array[PanelContainer] = []
var selected_defense_cards: Array[Dictionary] = []
# 行動フェーズの攻撃は、攻撃カード＋攻撃アップを重ねて選べる（防御の複数選択と同様）。
var selected_action_panels: Array[PanelContainer] = []
var selected_action_cards: Array[Dictionary] = []
var hovered_card_id := ""
var exchange_total := 0
var exchange_mp := 0
var exchange_gold := 0

func _ready() -> void:
	_apply_theme()
	leave_button.pressed.connect(func(): leave_requested.emit())
	action_button.pressed.connect(_request_action_fallback)
	card_use_button.pressed.connect(_request_card_zone)
	pass_defense_button.pressed.connect(_request_secondary_action)
	$ExchangePanel/Margin/Content/Plus10Row/Mp.pressed.connect(
		_adjust_exchange.bind("mp", 10)
	)
	$ExchangePanel/Margin/Content/Plus1Row/Mp.pressed.connect(
		_adjust_exchange.bind("mp", 1)
	)
	$ExchangePanel/Margin/Content/Minus1Row/Mp.pressed.connect(
		_adjust_exchange.bind("mp", -1)
	)
	$ExchangePanel/Margin/Content/Minus10Row/Mp.pressed.connect(
		_adjust_exchange.bind("mp", -10)
	)
	$ExchangePanel/Margin/Content/Plus10Row/Gold.pressed.connect(
		_adjust_exchange.bind("gold", 10)
	)
	$ExchangePanel/Margin/Content/Plus1Row/Gold.pressed.connect(
		_adjust_exchange.bind("gold", 1)
	)
	$ExchangePanel/Margin/Content/Minus1Row/Gold.pressed.connect(
		_adjust_exchange.bind("gold", -1)
	)
	$ExchangePanel/Margin/Content/Minus10Row/Gold.pressed.connect(
		_adjust_exchange.bind("gold", -10)
	)

func _set_mouse_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_mouse_ignore(child)

func show_state(incoming_state: Dictionary) -> void:
	var old_phase: String = String(state.get("phase", ""))
	state = incoming_state
	selected_card = {}
	selected_hand_panel = null
	selected_defense_panels.clear()
	selected_defense_cards.clear()
	selected_action_panels.clear()
	selected_action_cards.clear()
	exchange_panel.hide()
	_refresh_players()
	_refresh_hand()
	_refresh_message()
	_refresh_selected_card()
	_animate_state_transition(old_phase, String(state.get("phase", "action")))

func _clear_children(parent: Node) -> void:
	# シグナル処理中に free() すると解放済みノードへ触って落ちるため、
	# ツリーから外してから queue_free する。
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _refresh_players() -> void:
	_clear_children(opponents)
	target_buttons.clear()
	var my_id: int = multiplayer.get_unique_id()
	var players: Dictionary = state.get("players", {})
	var mine: Dictionary = players.get(str(my_id), {})
	own_status_label.text = "●  %s　HP %d　MP %d　¥ %d" % [
		mine.get("name", "プレイヤー"),
		int(mine.get("hp", 0)),
		int(mine.get("mp", 20)),
		int(mine.get("gold", 20)),
	]
	for raw_peer_id: Variant in state.get("player_order", []):
		var peer_id: int = int(raw_peer_id)
		var player: Dictionary = players.get(str(peer_id), {})
		var button := Button.new()
		button.custom_minimum_size = Vector2(402, 48)
		var self_suffix: String = "（自分）" if peer_id == my_id else ""
		button.text = "●  %s%s　HP %d　MP %d　¥ %d" % [
			player.get("name", "Player"),
			self_suffix,
			int(player.get("hp", 0)),
			int(player.get("mp", 20)),
			int(player.get("gold", 20)),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not bool(player.get("alive", true))
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_color_override("font_color", Color("#384b54"))
		button.add_theme_color_override("font_hover_color", Color("#008f78"))
		button.add_theme_color_override("font_pressed_color", Color("#008f78"))
		button.add_theme_color_override("font_disabled_color", Color("#89938f"))
		button.pressed.connect(_select_target.bind(peer_id))
		opponents.add_child(button)
		target_buttons[peer_id] = button
	var selected_target: Dictionary = state.get("players", {}).get(
		str(selected_target_peer_id),
		{}
	)
	if (
		not target_buttons.has(selected_target_peer_id)
		or not bool(selected_target.get("alive", false))
	):
		selected_target_peer_id = my_id
		for raw_peer_id: Variant in state.get("player_order", []):
			var peer_id: int = int(raw_peer_id)
			var candidate: Dictionary = state.get("players", {}).get(str(peer_id), {})
			if (
				peer_id != my_id
				and target_buttons.has(peer_id)
				and bool(candidate.get("alive", false))
			):
				selected_target_peer_id = peer_id
				break
	_update_target_highlight()

func _refresh_hand() -> void:
	_clear_children(hand)
	hovered_card_id = ""
	hover_card_detail.hide()
	card_panels.clear()
	var my_id: int = multiplayer.get_unique_id()
	var mine: Dictionary = state.get("players", {}).get(str(my_id), {})
	for raw_card: Variant in mine.get("hand", []):
		if raw_card is Dictionary:
			_add_card(raw_card, false)
	for raw_card: Variant in mine.get("learned_miracles", []):
		if raw_card is Dictionary:
			_add_card(raw_card, true)
	_layout_hand_cards()

func _add_card(card: Dictionary, learned: bool) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(102, 126)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(94, 94)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture: Texture2D = _load_card_texture(String(card.get("image_path", "")))
	if texture:
		art.texture = texture
	else:
		var no_art := Label.new()
		no_art.text = "絵なし"
		no_art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_art.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		no_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(no_art)
	panel.set_meta("card_border_color", _card_border_color(card))
	panel.set_meta("learned", learned)
	var card_is_usable: bool = _can_use_card_now(card)
	panel.set_meta("card_usable", card_is_usable)
	var value_label := Label.new()
	value_label.text = "%s%s" % [
		"★" if learned else "",
		_hand_card_value_text(card),
	]
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", _attribute_color(card))
	box.add_child(art)
	box.add_child(value_label)
	panel.add_child(box)
	# クリックは親PanelContainerで一元処理する。子Controlが入力を止めると、
	# カードの縁だけ反応して中央部分を選べない状態になる。
	_set_mouse_ignore(box)
	hand.add_child(panel)
	var panel_key: String = "%s:%s" % ["learned" if learned else "hand", card_panels.size()]
	card_panels[panel_key] = panel
	panel.gui_input.connect(_on_card_panel_input.bind(card, panel, card_is_usable))
	panel.mouse_entered.connect(_show_hover_card.bind(card, panel))
	panel.mouse_exited.connect(_hide_hover_card.bind(String(card.get("id", "")), panel))
	_set_card_style(panel, false, not card_is_usable)

func _layout_hand_cards() -> void:
	var panels: Array[Node] = hand.get_children()
	if panels.is_empty():
		return
	var card_width := 102.0
	var normal_step := 109.0
	var available_width := 790.0
	var step: float = normal_step
	if card_width + normal_step * (panels.size() - 1) > available_width:
		step = maxf(24.0, (available_width - card_width) / maxf(1.0, panels.size() - 1))
	for index: int in range(panels.size()):
		var panel: Control = panels[index]
		panel.position = Vector2(index * step, 0)
		panel.z_index = index
		panel.set_meta("base_z_index", index)

func _on_card_panel_input(event: InputEvent, card: Dictionary, panel: PanelContainer, usable: bool) -> void:
	var selecting_merchandise: bool = (
		String(state.get("phase", "")) == "action"
		and not selected_action_cards.is_empty()
		and _is_trade_sell(selected_action_cards[0])
		and not bool(panel.get_meta("learned", false))
	)
	if not usable and not selecting_merchandise:
		return
	var clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var tapped: bool = event is InputEventScreenTouch and event.pressed
	if clicked or tapped:
		_select_card(card, panel)

func _show_hover_card(card: Dictionary, panel: PanelContainer = null) -> void:
	hovered_card_id = String(card.get("id", ""))
	if panel:
		panel.z_index = 1000
	hover_card_name.text = String(card.get("name", "名無し"))
	hover_card_attribute_value.text = _card_value_text(card)
	hover_card_attribute_value.add_theme_color_override("font_color", _attribute_color(card))
	hover_card_price.text = "¥%d" % int(card.get("price", 0))
	hover_card_price_badge.visible = card.has("price")
	hover_card_description.text = String(card.get("description", ""))
	var texture: Texture2D = _load_card_texture(String(card.get("image_path", "")))
	hover_card_art.texture = texture
	hover_card_no_art.visible = texture == null
	hover_card_detail.add_theme_stylebox_override("panel", _rounded_style(
		Color("#e9ffd8"),
		_card_border_color(card),
		3
	))
	hover_card_detail.show()

func _hide_hover_card(card_id: String, panel: PanelContainer = null) -> void:
	if panel:
		panel.z_index = int(panel.get_meta("base_z_index", panel.z_index))
	if hovered_card_id == card_id:
		hovered_card_id = ""
		hover_card_detail.hide()

func _select_card(card: Dictionary, panel: PanelContainer = null) -> void:
	if String(state.get("phase", "action")) == "defense":
		if not _can_use_card_now(card):
			return
		var previous_defense_panels: Array[PanelContainer] = selected_defense_panels.duplicate()
		var previous_defense_cards: Array[Dictionary] = selected_defense_cards.duplicate()
		var selected_index: int = selected_defense_panels.find(panel)
		if selected_index >= 0:
			selected_defense_panels.remove_at(selected_index)
			selected_defense_cards.remove_at(selected_index)
		else:
			var selecting_reflect: bool = _card_has_effect(card, "reflect")
			if (
				not selected_defense_cards.is_empty()
				and (
					_card_has_effect(selected_defense_cards[0], "reflect") != selecting_reflect
					or selecting_reflect
				)
			):
				# 防具と反射は併用不可。反射も1枚だけなので新しい選択へ切り替える。
				selected_defense_panels.clear()
				selected_defense_cards.clear()
			selected_defense_panels.append(panel)
			selected_defense_cards.append(card)
		if not _can_afford_cards(selected_defense_cards):
			selected_defense_panels = previous_defense_panels
			selected_defense_cards = previous_defense_cards
			bottom_status.text = "選んだ防具の使用コストが足りません"
		elif selected_defense_cards != previous_defense_cards:
			_play_sfx("card_deselect" if selected_index >= 0 else "card_select", -3.0)
		for card_id: Variant in card_panels.keys():
			var defense_panel: PanelContainer = card_panels[card_id]
			_set_card_style(defense_panel, defense_panel in selected_defense_panels, false)
		_refresh_selected_card()
		_refresh_message()
		return
	# 行動フェーズ: 攻撃系（攻撃／攻撃アップ）は重ねて選べる。それ以外は単独選択。
	var previous_action_panels: Array[PanelContainer] = selected_action_panels.duplicate()
	var previous_action_cards: Array[Dictionary] = selected_action_cards.duplicate()
	var selecting_sell: bool = _is_trade_sell(card)
	var sell_selected: bool = (
		not selected_action_cards.is_empty()
		and _is_trade_sell(selected_action_cards[0])
	)
	if selecting_sell or sell_selected:
		if selecting_sell:
			selected_action_panels = [panel]
			selected_action_cards = [card]
		else:
			var already_selected: int = selected_action_panels.find(panel)
			if already_selected >= 1:
				selected_action_panels.remove_at(already_selected)
				selected_action_cards.remove_at(already_selected)
			elif (
				not bool(panel.get_meta("learned", false))
				and selected_action_cards.size() - 1
					< maxi(1, int(selected_action_cards[0].get("power", 1)))
			):
				selected_action_panels.append(panel)
				selected_action_cards.append(card)
		selected_card = selected_action_cards[0]
		selected_hand_panel = selected_action_panels[0]
		for card_id: Variant in card_panels.keys():
			var trade_select_panel: PanelContainer = card_panels[card_id]
			_set_card_style(
				trade_select_panel,
				trade_select_panel in selected_action_panels,
				false
			)
		_refresh_selected_card()
		_refresh_message()
		_refresh_exchange_panel()
		if selected_action_cards != previous_action_cards:
			_play_sfx(
				"card_deselect" if selected_action_cards.size() < previous_action_cards.size() else "card_select",
				-3.0
			)
		return
	var offensive: bool = _is_offensive(card)
	var already: int = selected_action_panels.find(panel)
	if already >= 0:
		selected_action_panels.remove_at(already)
		selected_action_cards.remove_at(already)
	elif not offensive:
		# 回復・防御・反射などは1枚だけ。選択をこのカードに置き換える。
		selected_action_panels.clear()
		selected_action_cards.clear()
		selected_action_panels.append(panel)
		selected_action_cards.append(card)
	else:
		# 直前まで攻撃以外を選んでいたら、いったん選択をクリアしてから攻撃系を積む。
		if not selected_action_cards.is_empty() and not _is_offensive(selected_action_cards[0]):
			selected_action_panels.clear()
			selected_action_cards.clear()
		if (
			_card_has_context_effect(card, "buff", "action")
			and not _card_has_context_effect(card, "attack", "action")
		):
			for selected_action_card: Dictionary in selected_action_cards:
				if (
					_card_has_context_effect(selected_action_card, "attack", "action")
					and _action_target(selected_action_card) in ["all_enemies", "all_players"]
				):
					# 重ねられない組み合わせはクリックを拒否せず、
					# 直前の全体攻撃を外して、今押した攻＋だけへ選択を切り替える。
					selected_action_panels.clear()
					selected_action_cards.clear()
					break
		# 攻撃カードは1枚まで。既に攻撃カードがあれば入れ替える。
		if _card_has_effect(card, "attack"):
			for index: int in range(selected_action_cards.size() - 1, -1, -1):
				if _card_has_effect(selected_action_cards[index], "attack"):
					selected_action_panels.remove_at(index)
					selected_action_cards.remove_at(index)
			if _action_target(card) in ["all_enemies", "all_players"]:
				for index: int in range(selected_action_cards.size() - 1, -1, -1):
					if _card_has_context_effect(selected_action_cards[index], "buff", "action"):
						selected_action_panels.remove_at(index)
						selected_action_cards.remove_at(index)
		selected_action_panels.append(panel)
		selected_action_cards.append(card)
	if not _can_afford_cards(selected_action_cards):
		selected_action_panels = previous_action_panels
		selected_action_cards = previous_action_cards
		bottom_status.text = "選んだカードの使用コストが足りません"
	elif selected_action_cards != previous_action_cards:
		_play_sfx(
			"card_deselect" if already >= 0 else "card_select",
			-3.0
		)
	selected_card = _primary_action_card()
	selected_hand_panel = selected_action_panels[0] if not selected_action_panels.is_empty() else null
	if (
		not selected_card.is_empty()
		and not _is_offensive(selected_card)
		and _action_target(selected_card) == "self"
	):
		selected_target_peer_id = multiplayer.get_unique_id()
		_update_target_highlight()
	for card_id: Variant in card_panels.keys():
		var current_panel: PanelContainer = card_panels[card_id]
		_set_card_style(current_panel, current_panel in selected_action_panels, false)
	_refresh_selected_card()
	_refresh_message()
	_refresh_exchange_panel()

func _is_offensive(card: Dictionary) -> bool:
	return (
		_card_has_context_effect(card, "attack", "action")
		or _card_has_context_effect(card, "buff", "action")
	)

func _is_trade_buy(card: Dictionary) -> bool:
	return _card_has_context_effect(card, "buy", "action")

func _is_trade_sell(card: Dictionary) -> bool:
	return _card_has_context_effect(card, "sell", "action")

func _is_exchange(card: Dictionary) -> bool:
	return _card_has_context_effect(card, "exchange", "action")

func _primary_action_card() -> Dictionary:
	for card: Dictionary in selected_action_cards:
		if _is_trade_buy(card) or _is_trade_sell(card):
			return card
	# 攻撃カードがあればそれを主役に、無ければ先頭を主役にする。
	for card: Dictionary in selected_action_cards:
		if _card_has_effect(card, "attack"):
			return card
	return selected_action_cards[0] if not selected_action_cards.is_empty() else {}

func _select_target(peer_id: int) -> void:
	selected_target_peer_id = peer_id
	_play_sfx("card_select", -6.0, 0.94)
	_update_target_highlight()
	_refresh_selected_card()
	_refresh_message()

func _update_target_highlight() -> void:
	for raw_peer_id: Variant in target_buttons.keys():
		var peer_id: int = int(raw_peer_id)
		var button: Button = target_buttons[peer_id]
		button.add_theme_stylebox_override("normal", _rounded_style(
			Color("#fff7f1") if peer_id == selected_target_peer_id else Color("#f5f1ed"),
			Color("#f16f5b") if peer_id == selected_target_peer_id else Color("#9caaa5"),
			2 if peer_id == selected_target_peer_id else 1
		))

func _request_selected_card() -> void:
	if String(state.get("phase", "")) == "purchase":
		purchase_response_requested.emit(true)
		return
	if String(state.get("phase", "action")) == "defense":
		if selected_defense_cards.is_empty():
			bottom_status.text = "防具を選ぶか「防御せず受ける」を押してください"
			return
		var card_ids: Array[String] = []
		for defense_card: Dictionary in selected_defense_cards:
			card_ids.append(String(defense_card.get("id", "")))
		defense_cards_requested.emit(card_ids)
		return
	if selected_action_cards.is_empty():
		bottom_status.text = "手札からカードを選んでください"
		return
	var my_id: int = multiplayer.get_unique_id()
	var primary: Dictionary = _primary_action_card()
	if _is_exchange(primary):
		exchange_requested.emit(
			String(primary.get("id", "")),
			exchange_total - exchange_mp - exchange_gold,
			exchange_mp,
			exchange_gold
		)
		return
	var card_target: String = _action_target(primary)
	var target_peer_id: int = selected_target_peer_id
	if (_is_trade_buy(primary) or _is_trade_sell(primary)) and target_peer_id == my_id:
		bottom_status.text = "取引する相手を選んでください"
		return
	if (
		_is_trade_sell(primary)
		and (
			selected_action_cards.size() < 2
			or selected_action_cards.size() - 1 > maxi(1, int(primary.get("power", 1)))
		)
	):
		bottom_status.text = "「売る」と、上限以内で売りつける手札を選んでください"
		return
	if card_target in ["all_enemies", "all_players"]:
		target_peer_id = 0
	elif _is_offensive(primary):
		if selected_target_peer_id == 0:
			bottom_status.text = "攻撃する相手を選んでください"
			return
		target_peer_id = selected_target_peer_id
	elif target_peer_id == 0:
		target_peer_id = my_id
	var card_ids: Array = []
	for action_card: Dictionary in selected_action_cards:
		card_ids.append(String(action_card.get("id", "")))
	card_play_requested.emit(card_ids, target_peer_id)

func _request_card_zone() -> void:
	if String(state.get("phase", "")) == "purchase":
		purchase_response_requested.emit(true)
		return
	if String(state.get("phase", "action")) == "defense":
		if selected_defense_cards.is_empty():
			pass_defense_requested.emit()
		else:
			_request_selected_card()
		return
	_request_selected_card()

func _request_secondary_action() -> void:
	if String(state.get("phase", "")) == "purchase":
		purchase_response_requested.emit(false)
	else:
		pass_defense_requested.emit()

func _refresh_exchange_panel() -> void:
	var primary: Dictionary = _primary_action_card()
	var active: bool = (
		String(state.get("phase", "action")) == "action"
		and not primary.is_empty()
		and _is_exchange(primary)
	)
	exchange_panel.visible = active
	if not active:
		return
	var mine: Dictionary = state.get("players", {}).get(
		str(multiplayer.get_unique_id()), {}
	)
	var exchange_hp: int = int(mine.get("hp", 0))
	exchange_mp = int(mine.get("mp", 0))
	exchange_gold = int(mine.get("gold", 0))
	var cost: Dictionary = (
		primary.get("cost", {}) if primary.get("cost", {}) is Dictionary else {}
	)
	var amount: int = clampi(int(cost.get("amount", 0)), 0, 99)
	match String(cost.get("resource", "none")):
		"hp":
			exchange_hp -= amount
		"mp":
			exchange_mp -= amount
		"gold":
			exchange_gold -= amount
	exchange_total = exchange_hp + exchange_mp + exchange_gold
	_update_exchange_values()

func _adjust_exchange(resource: String, amount: int) -> void:
	var next_mp: int = exchange_mp + (amount if resource == "mp" else 0)
	var next_gold: int = exchange_gold + (amount if resource == "gold" else 0)
	var next_hp: int = exchange_total - next_mp - next_gold
	if (
		next_hp < 0 or next_hp > 99
		or next_mp < 0 or next_mp > 99
		or next_gold < 0 or next_gold > 99
	):
		return
	exchange_mp = next_mp
	exchange_gold = next_gold
	_update_exchange_values()

func _update_exchange_values() -> void:
	exchange_hp_value.text = "HP %d" % (exchange_total - exchange_mp - exchange_gold)
	exchange_mp_value.text = "MP %d" % exchange_mp
	exchange_gold_value.text = "¥ %d" % exchange_gold

func _request_action_fallback() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var mine: Dictionary = state.get("players", {}).get(str(my_id), {})
	if not _has_offensive_card(mine):
		pray_requested.emit()
	else:
		pass_action_requested.emit()

func _refresh_message() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var phase: String = String(state.get("phase", "action"))
	var pending: Dictionary = state.get("pending_attack", {})
	var is_my_defense: bool = phase == "defense" and int(pending.get("target_peer_id", 0)) == my_id
	var purchase: Dictionary = state.get("pending_purchase", {})
	var is_my_purchase: bool = (
		phase == "purchase"
		and int(purchase.get("buyer_peer_id", 0)) == my_id
	)
	pass_defense_button.visible = false
	pass_defense_button.text = "防御せず受ける"
	result_panel.visible = phase == "result"
	center_message.hide()
	action_button.visible = false
	if phase == "game_over":
		var winner: String = String(state.get("winner_name", ""))
		pass_defense_button.visible = false
	elif is_my_purchase:
		var offered_cards: Array = purchase.get("cards", [])
		var offer_price: int = int(purchase.get("price", 0))
		pass_defense_button.visible = true
		pass_defense_button.text = "買わない"
		var offered_names: Array[String] = []
		for offered_card: Dictionary in offered_cards:
			offered_names.append(String(offered_card.get("name", "カード")))
		center_message.text = "%s\n%d枚まとめて¥%dで買いますか？" % [
			"・".join(offered_names), offered_cards.size(), offer_price,
		]
		center_message.show()
		action_button.text = "購入確認中"
		action_button.disabled = true
	elif phase == "purchase":
		action_button.text = "購入選択を待っています"
		action_button.disabled = true
	elif is_my_defense:
		var selected_power: int = 0
		var selected_attributes: Array[String] = []
		for defense_card: Dictionary in selected_defense_cards:
			for effect_entry: Dictionary in _effects_for_context(defense_card, "defense"):
				if String(effect_entry.get("effect", "")) == "guard":
					selected_power += int(effect_entry.get("power", 0))
					selected_attributes.append(String(defense_card.get("attribute", "none")))
		var attack_attribute: String = String(pending.get("attribute", "none"))
		var defense_attribute: String = _combined_attribute_names(selected_attributes)
		action_button.text = "選んだ防具で守る"
		action_button.disabled = false
	elif phase == "defense":
		action_button.text = "待機中"
		action_button.disabled = true
	elif phase == "result":
		action_button.text = "結果表示中"
		action_button.disabled = true
	else:
		var current_peer_id: int = _current_turn_peer_id()
		if current_peer_id == my_id:
			var mine: Dictionary = state.get("players", {}).get(str(my_id), {})
			action_button.visible = selected_action_cards.is_empty()
			if not _has_offensive_card(mine):
				action_button.text = (
					"祈る（カード上限）"
					if _owned_card_count(mine) >= 18
					else "祈る（カードを1枚引く）"
				)
			else:
				action_button.text = "ターンを終了"
			action_button.disabled = false
		else:
			action_button.text = "待機中"
			action_button.disabled = true
	if phase == "game_over":
		var winner: String = String(state.get("winner_name", ""))
		bottom_status.text = "対戦終了　%s　山札 %d枚" % [
			"勝者: %s" % winner if not winner.is_empty() else "引き分け",
			state.get("deck", []).size(),
		]
	else:
		bottom_status.text = "%s の番　山札 %d枚" % [_player_name(_current_turn_peer_id()), state.get("deck", []).size()]
	_refresh_card_use_zone(phase, is_my_defense)

func _refresh_card_use_zone(phase: String, is_my_defense: bool) -> void:
	var purchase: Dictionary = state.get("pending_purchase", {})
	var is_my_purchase: bool = (
		phase == "purchase"
		and int(purchase.get("buyer_peer_id", 0)) == multiplayer.get_unique_id()
	)
	var can_play_selected_card: bool = (
		phase == "action"
		and not selected_card.is_empty()
		and _can_use_card_now(selected_card)
		and _can_afford_cards(selected_action_cards)
	)
	card_use_button.visible = can_play_selected_card or is_my_defense or is_my_purchase
	if not card_use_button.visible:
		return
	if is_my_purchase:
		var mine: Dictionary = state.get("players", {}).get(
			str(multiplayer.get_unique_id()), {}
		)
		var price: int = int(purchase.get("price", 0))
		var card_limit_reached: bool = (
			_owned_card_count(mine) + purchase.get("cards", []).size() > 18
		)
		card_use_button.disabled = (
			int(mine.get("gold", 0)) < price
			or card_limit_reached
		)
		card_use_button.text = "¥%dで買う" % price
		card_use_button.tooltip_text = (
			"カード所持上限です"
			if card_limit_reached
			else (
				"¥が足りません"
				if card_use_button.disabled
				else "提示されたカードを購入"
			)
		)
	elif is_my_defense:
		var pending_effect: String = String(state.get("pending_attack", {}).get("effect", "attack"))
		var is_trade_defense: bool = pending_effect in ["buy", "sell"]
		card_use_button.text = (
			("完全反射を使う" if not selected_defense_cards.is_empty() else "取引を受ける")
			if is_trade_defense
			else "カードを使う"
		)
		card_use_button.disabled = not _can_afford_cards(selected_defense_cards)
		card_use_button.position.x = 420.0
		card_use_button.size.x = 350.0
		if pending_effect not in ["attack", "buff"]:
			card_use_button.tooltip_text = (
				"反射を確定"
				if not selected_defense_cards.is_empty()
				else "そのまま受ける"
			)
		else:
			card_use_button.tooltip_text = (
				"防御を確定"
				if not selected_defense_cards.is_empty()
				else "防具なしで受ける"
			)
	else:
		card_use_button.text = "カードを使う"
		card_use_button.disabled = not _can_afford_cards(selected_action_cards)
		card_use_button.position.x = 18.0
		card_use_button.size.x = 342.0
		card_use_button.tooltip_text = "クリックして発動"

func _refresh_selected_card() -> void:
	_clear_children(defense_cards_view)
	_clear_children(attack_stack)
	attack_total_panel.hide()
	defense_total_panel.hide()
	# 合成した1枚は出さない。攻撃側のカードは1枚ずつ縦に積んで見せる。
	selected_card_panel.visible = false
	var phase: String = String(state.get("phase", "action"))
	var combat: Dictionary = state.get("combat_view", {})
	var showing_combat: bool = phase in ["defense", "result"] and not combat.is_empty()
	var attacker_cards: Array = []
	if phase == "purchase":
		attacker_cards = state.get("pending_purchase", {}).get("cards", [])
	elif showing_combat:
		attacker_cards = combat.get("attack_cards", [])
		if attacker_cards.is_empty() and not (combat.get("attack_card", {}) as Dictionary).is_empty():
			attacker_cards = [combat.get("attack_card")]
	elif not selected_action_cards.is_empty():
		attacker_cards = selected_action_cards
	elif not selected_card.is_empty():
		attacker_cards = [selected_card]
	var has_selection: bool = not attacker_cards.is_empty()
	target_status.visible = has_selection
	if not has_selection:
		selection_arrow.visible = false
		result_panel.hide()
		return
	var primary: Dictionary = _primary_of(attacker_cards)
	# 攻撃側のカードを1枚ずつ積む（合成しない）。
	var summed_power := 0
	var offensive_count := 0
	for raw_card: Variant in attacker_cards:
		if raw_card is Dictionary:
			var card: Dictionary = raw_card
			var card_view: PanelContainer = _make_combat_card(card)
			attack_stack.add_child(card_view)
			summed_power += int(card.get("power", 0))
			if _is_offensive(card):
				offensive_count += 1
	_layout_combat_stack(attack_stack)
	# 攻撃なら合計威力を別枠で表示（合成ではなく足し算の結果）。
	if offensive_count > 0:
		var atk_attribute: String = String(combat.get("attack_attribute", "none")) if showing_combat else _combined_action_attribute()
		var total_power: int = int(combat.get("attack_power", summed_power)) if showing_combat else summed_power
		attack_total.text = "攻撃合計 %d" % total_power
		attack_total.add_theme_color_override("font_color", _attribute_color({"attribute": atk_attribute}))
		attack_total_panel.show()
	var target_peer_id: int
	var hide_arrow := false
	var arrow_direction := "right"
	if phase == "purchase":
		var purchase: Dictionary = state.get("pending_purchase", {})
		target_peer_id = int(purchase.get("seller_peer_id", 0))
		hide_arrow = false
		arrow_direction = "right"
	elif showing_combat:
		own_status_label.text = "●  %s" % combat.get("attacker_name", "攻撃者")
		target_peer_id = int(combat.get("target_peer_id", 0))
		hide_arrow = bool(combat.get("hide_arrow", false))
		arrow_direction = String(combat.get("arrow_direction", "right"))
	else:
		var sel_target: String = _action_target(primary)
		if sel_target in ["all_enemies", "all_players"]:
			target_peer_id = 0
			hide_arrow = sel_target == "all_players"
			arrow_direction = "right"
		elif not _is_offensive(primary):
			target_peer_id = selected_target_peer_id
			arrow_direction = "left" if target_peer_id == multiplayer.get_unique_id() else "right"
		else:
			target_peer_id = selected_target_peer_id
			arrow_direction = "left" if target_peer_id == multiplayer.get_unique_id() else "right"
	selection_arrow.visible = not hide_arrow
	selection_arrow.text = "←" if arrow_direction == "left" else "→"
	var is_all_enemies: bool = not showing_combat and _action_target(primary) == "all_enemies"
	var is_all_players: bool = not showing_combat and _action_target(primary) == "all_players"
	if is_all_enemies:
		target_status_label.text = "●  全"
	elif is_all_players:
		target_status_label.text = "●  （全）"
	else:
		target_status_label.text = "●  %s" % _player_name(target_peer_id)
	var defenses: Array = combat.get("defense_cards", []) if showing_combat else []
	if phase == "defense" and not selected_defense_cards.is_empty():
		defenses = selected_defense_cards
	var defense_index := 0
	var defense_power := 0
	for raw_card: Variant in defenses:
		if raw_card is Dictionary:
			var defense_view: PanelContainer = _make_combat_card(raw_card)
			defense_cards_view.add_child(defense_view)
			for effect_entry: Dictionary in _effects_for_context(raw_card, "defense"):
				if String(effect_entry.get("effect", "")) == "guard":
					defense_power += int(effect_entry.get("power", 0))
			_animate_defense_card(defense_view, defense_index)
			defense_index += 1
	_layout_combat_stack(defense_cards_view)
	if phase == "defense" or (showing_combat and not defenses.is_empty()):
		var pending_effect: String = String(state.get("pending_attack", {}).get("effect", "attack"))
		var is_support_response: bool = (
			pending_effect not in ["attack", "buff"]
			or String(combat.get("status", "")) in ["support_pending", "support_resolved"]
		)
		if is_support_response:
			defense_total.text = "反射" if not defenses.is_empty() else "反射なし"
		else:
			defense_total.text = (
				"反射"
				if not defenses.is_empty() and _card_has_effect(defenses[0], "reflect")
				else "防御合計 %d" % defense_power
			)
		defense_total_panel.show()
	if phase == "result":
		_place_result_at_receiver(combat)
		if String(combat.get("status", "")) in ["action", "support_resolved", "trade_result"]:
			result_label.text = String(combat.get("result_text", "発動"))
			if _card_has_effect(primary, "heal"):
				result_label.add_theme_color_override(
					"font_color",
					Color("#ff5a57") if _card_has_negative_heal(primary) else Color("#72e08f")
				)
			else:
				result_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			var damage: int = int(combat.get("damage", 0))
			result_label.text = "無事" if damage == 0 else "%d\nダメージ" % damage
			result_label.add_theme_color_override("font_color", Color("#72e08f") if damage == 0 else Color("#ff5a57"))
		result_panel.show()

func _primary_of(cards: Array) -> Dictionary:
	for raw_card: Variant in cards:
		if raw_card is Dictionary and _card_has_effect(raw_card, "attack"):
			return raw_card
	for raw_card: Variant in cards:
		if raw_card is Dictionary:
			return raw_card
	return {}

func _place_result_at_receiver(combat: Dictionary) -> void:
	var attacker_peer_id: int = int(combat.get("attacker_peer_id", 0))
	var target_peer_id: int = int(combat.get("target_peer_id", 0))
	var receiver_status: Control = own_status if target_peer_id == attacker_peer_id else target_status
	result_panel.position.x = receiver_status.position.x
	result_panel.size.x = receiver_status.size.x

func _show_card_detail(card: Dictionary) -> void:
	selected_card_name.text = String(card.get("name", "名無し"))
	selected_card_description.text = ""
	selected_card_description.hide()
	selected_card_value.text = _card_value_text(card, false)
	selected_card_value.add_theme_color_override("font_color", _attribute_color(card))
	var texture: Texture2D = _load_card_texture(String(card.get("image_path", "")))
	selected_card_art.texture = texture
	selected_card_no_art.visible = texture == null

func _make_combat_card(card: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(322, 88)
	panel.add_theme_stylebox_override("panel", _rounded_style(
		Color("#eefaeb"), _card_border_color(card), 3
	))
	var row := HBoxContainer.new()
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(76, 76)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _load_card_texture(String(card.get("image_path", "")))
	if art.texture == null:
		var no_art := Label.new()
		no_art.text = "絵なし"
		no_art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_art.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.add_child(no_art)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = String(card.get("name", "防具"))
	name_label.clip_text = true
	name_label.add_theme_color_override("font_color", Color("#335a83"))
	name_label.add_theme_font_size_override("font_size", 18)
	var value := Label.new()
	value.text = _hand_card_value_text(card)
	value.clip_text = true
	value.add_theme_color_override("font_color", _attribute_color(card))
	value.add_theme_font_size_override("font_size", 21)
	details.add_child(name_label)
	details.add_child(value)
	row.add_child(art)
	row.add_child(details)
	row.add_child(_make_price_badge(card))
	panel.add_child(row)
	# 場に出したカードは説明を常設せず、手札と同じホバー詳細へ集約する。
	_set_mouse_ignore(row)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_show_hover_card.bind(card, panel))
	panel.mouse_exited.connect(_hide_hover_card.bind(String(card.get("id", "")), panel))
	return panel

func _make_price_badge(card: Dictionary) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(46, 46)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style: StyleBoxFlat = _rounded_style(
		Color("#fff6b8"), Color("#e7cc58"), 1
	)
	badge_style.set_corner_radius_all(23)
	badge.add_theme_stylebox_override("panel", badge_style)
	var price_label := Label.new()
	price_label.text = "¥%d" % int(card.get("price", 0))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.add_theme_color_override("font_color", Color("#40535b"))
	price_label.add_theme_font_size_override("font_size", 16)
	badge.add_child(price_label)
	return badge

func _layout_combat_stack(stack: Control) -> void:
	var cards: Array[Node] = stack.get_children()
	if cards.is_empty():
		return
	var card_height := 88.0
	var normal_step := 96.0
	var available_height: float = stack.size.y
	if available_height <= 0.0:
		available_height = 220.0
	var step: float = normal_step
	if card_height + normal_step * (cards.size() - 1) > available_height:
		step = maxf(16.0, (available_height - card_height) / maxf(1.0, cards.size() - 1))
	for index: int in range(cards.size()):
		var card: Control = cards[index]
		card.position = Vector2(0, index * step)
		card.z_index = index
		card.set_meta("base_z_index", index)

func _can_use_card_now(card: Dictionary) -> bool:
	var my_id: int = multiplayer.get_unique_id()
	var phase: String = String(state.get("phase", "action"))
	if not _can_afford_cards([card]):
		return false
	if phase == "defense":
		var pending: Dictionary = state.get("pending_attack", {})
		if int(pending.get("target_peer_id", 0)) != my_id:
			return false
		if _can_respond_to_pending(pending, card):
			return true
		if (
			String(pending.get("effect", "attack")) in ["attack", "buff"]
			and not _card_has_effect(card, "reflect")
			and not _effects_for_context(card, "defense").is_empty()
		):
			var mine: Dictionary = state.get("players", {}).get(str(my_id), {})
			for hand_card: Dictionary in mine.get("hand", []):
				if String(hand_card.get("special_effect", "")) == "attribute_erase":
					return true
		return false
	if phase != "action":
		return false
	return (
		_current_turn_peer_id() == my_id
		and _can_play_in_action(card)
		and _can_afford_cards([card])
	)

func _can_afford_cards(cards: Array) -> bool:
	var my_id: int = multiplayer.get_unique_id()
	var mine: Dictionary = state.get("players", {}).get(str(my_id), {})
	if mine.is_empty():
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
		if int(mine.get(resource, 0)) < int(totals[resource]):
			return false
	return true

func _can_respond_to_pending(pending: Dictionary, card: Dictionary) -> bool:
	if _card_has_effect(card, "reflect"):
		var tags: Array = card.get("tags", [])
		if "full_reflect" in tags or "all_reflect" in tags:
			return true
		var incoming: Dictionary = pending.get("card", {})
		if String(incoming.get("type", "")) == "miracle":
			return "miracle_reflect" in tags
		return (
			String(pending.get("effect", "attack")) in ["attack", "buff"]
			and ("attack_reflect" in tags or "miracle_reflect" not in tags)
			and _attribute_can_defend(
				(
					"none"
					if String(card.get("special_effect", "")) == "attribute_erase"
					else String(pending.get("attribute", "none"))
				),
				String(card.get("attribute", "none"))
			)
		)
	if String(pending.get("effect", "attack")) in ["attack", "buff"]:
		return (
			not _effects_for_context(card, "defense").is_empty()
			and (
				String(card.get("special_effect", "")) == "attribute_erase"
				or _attribute_can_defend(
					String(pending.get("attribute", "none")),
					String(card.get("attribute", "none"))
				)
			)
		)
	return false

func _owned_card_count(player: Dictionary) -> int:
	return player.get("hand", []).size() + player.get("learned_miracles", []).size()

func _has_offensive_card(player: Dictionary) -> bool:
	for zone_name: String in ["hand", "learned_miracles"]:
		for raw_card: Variant in player.get(zone_name, []):
			if (
				raw_card is Dictionary
				and _is_offensive(raw_card)
				and _can_afford_cards([raw_card])
			):
				return true
	return false

func _animate_state_transition(old_phase: String, new_phase: String) -> void:
	_animate_hand()
	if new_phase == "defense" and old_phase != "defense":
		_animate_slide_in(selected_card_panel, -46.0)
		selection_arrow.modulate.a = 0.35
		var arrow_tween: Tween = create_tween()
		arrow_tween.set_loops(3)
		arrow_tween.tween_property(selection_arrow, "modulate:a", 1.0, 0.18)
		arrow_tween.tween_property(selection_arrow, "modulate:a", 0.35, 0.18)
	if new_phase == "result":
		_animate_result_panel()

func _animate_result_panel() -> void:
	await get_tree().process_frame
	var combat: Dictionary = state.get("combat_view", {})
	_play_result_sfx(combat)
	result_panel.pivot_offset = result_panel.size * 0.5
	result_panel.scale = Vector2(0.62, 0.62)
	result_panel.modulate.a = 0.0
	var result_tween: Tween = create_tween().set_parallel(true)
	result_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	result_tween.tween_property(result_panel, "scale", Vector2.ONE, 0.34)
	result_tween.tween_property(result_panel, "modulate:a", 1.0, 0.2)
	if int(combat.get("damage", 0)) > 0:
		_shake_defender(int(combat.get("target_peer_id", 0)))

func _play_result_sfx(combat: Dictionary) -> void:
	var status: String = String(combat.get("status", ""))
	var attack_cards: Array = combat.get("attack_cards", [])
	var primary: Dictionary = _primary_of(attack_cards)
	var defense_cards: Array = combat.get("defense_cards", [])
	if status == "trade_result":
		_play_sfx("gold_gain", -3.0)
		return
	if not defense_cards.is_empty() and _card_has_effect(defense_cards[0], "reflect"):
		_play_sfx("reflect", -2.0)
		return
	if _card_has_effect(primary, "instant_death") or _target_was_defeated(combat):
		_play_sfx("death", -2.0)
		return
	if _card_has_effect(primary, "heal"):
		_play_sfx("heal", -2.0)
		return
	if int(combat.get("damage", 0)) > 0 or _card_has_effect(primary, "attack") or _card_has_effect(primary, "buff"):
		_play_sfx("attack_start", -1.0)

func _play_sfx(cue: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", cue, volume_db, pitch_scale)

func _target_was_defeated(combat: Dictionary) -> bool:
	var target_peer_id: int = int(combat.get("target_peer_id", 0))
	var target: Dictionary = state.get("players", {}).get(str(target_peer_id), {})
	if target.is_empty():
		return false
	return not bool(target.get("alive", true))

func _animate_hand() -> void:
	var delay := 0.0
	for child: Control in hand.get_children():
		child.pivot_offset = child.size * 0.5
		child.scale = Vector2(0.9, 0.9)
		child.modulate.a = 0.0
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(child, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		tween.tween_property(child, "modulate:a", 1.0, 0.16).set_delay(delay)
		delay += 0.025

func _animate_slide_in(control: Control, offset_x: float) -> void:
	# アニメ中に再度呼ばれても基準位置がずれないよう、初回位置を控えておく。
	if not control.has_meta("base_position"):
		control.set_meta("base_position", control.position)
	var final_position: Vector2 = control.get_meta("base_position")
	control.position = final_position + Vector2(offset_x, 0.0)
	control.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "position", final_position, 0.26)
	tween.tween_property(control, "modulate:a", 1.0, 0.18)

func _animate_defense_card(control: Control, index: int) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.92, 0.92)
	control.modulate.a = 0.0
	var delay: float = index * 0.09
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	tween.tween_property(control, "modulate:a", 1.0, 0.16).set_delay(delay)

func _shake_defender(peer_id: int) -> void:
	var combat: Dictionary = state.get("combat_view", {})
	var attacker_peer_id: int = int(combat.get("attacker_peer_id", 0))
	var control: Control = own_status if peer_id == attacker_peer_id else target_status
	if control == null:
		return
	if not control.has_meta("shake_origin_x"):
		control.set_meta("shake_origin_x", control.position.x)
	var origin_x: float = control.get_meta("shake_origin_x")
	var tween: Tween = create_tween()
	for offset: float in [10.0, -9.0, 7.0, -5.0, 0.0]:
		tween.tween_property(control, "position:x", origin_x + offset, 0.045)

func _current_turn_peer_id() -> int:
	var order: Array = state.get("player_order", [])
	if order.is_empty():
		return 0
	return int(order[int(state.get("turn", 0)) % order.size()])

func _player_name(peer_id: int) -> String:
	return String(state.get("players", {}).get(str(peer_id), {}).get("name", "相手"))

func _card_effects(card: Dictionary) -> Array:
	var effects: Variant = card.get("effects", [])
	if effects is Array and not effects.is_empty():
		return effects
	return [{
		"effect": String(card.get("effect", "attack")),
		"power": int(card.get("power", 0)),
		"target": String(card.get("target", "enemy")),
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

func _action_target(card: Dictionary) -> String:
	var action_effects: Array = _effects_for_context(card, "action")
	for effect_entry: Dictionary in action_effects:
		if String(effect_entry.get("effect", "")) == "attack":
			return String(effect_entry.get("target", card.get("target", "enemy")))
	if not action_effects.is_empty():
		return String(action_effects[0].get("target", card.get("target", "self")))
	return String(card.get("target", "self"))

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

func _only_healing_effects(card: Dictionary) -> bool:
	for effect_entry: Dictionary in _card_effects(card):
		if String(effect_entry.get("effect", "")) != "heal":
			return false
	return true

func _card_has_negative_heal(card: Dictionary) -> bool:
	for effect_entry: Dictionary in _card_effects(card):
		if (
			String(effect_entry.get("effect", "")) == "heal"
			and int(effect_entry.get("power", 0)) < 0
		):
			return true
	return false

func _card_kind_label(card: Dictionary) -> String:
	var labels: Array[String] = []
	for effect_entry: Dictionary in _card_effects(card):
		var effect: String = String(effect_entry.get("effect", ""))
		var target: String = String(effect_entry.get("target", card.get("target", "")))
		var label := ""
		if target == "all_enemies":
			label = "全"
		elif target == "all_players":
			label = "（全）"
		elif effect == "reflect" and _is_full_reflect(card):
			label = "完反"
		else:
			label = _effect_short_label(effect)
		if label not in labels:
			labels.append(label)
	if String(card.get("effect_mode", "all")) == "random_one":
		return "抽:%s" % "／".join(labels)
	return ("／" if _uses_contextual_roles(card) else "＋").join(labels)

func _uses_contextual_roles(card: Dictionary) -> bool:
	var has_action_role := false
	var has_defense_role := false
	for effect_entry: Dictionary in _card_effects(card):
		var effect_name: String = String(effect_entry.get("effect", ""))
		if effect_name in ["attack", "buff", "heal", "instant_death"]:
			has_action_role = true
		elif effect_name in ["guard", "reflect"]:
			has_defense_role = true
	return has_action_role and has_defense_role

func _card_border_color(card: Dictionary) -> Color:
	return Color("#e0574f") if String(card.get("type", "")) == "miracle" else Color("#9caaa5")

func _is_full_reflect(card: Dictionary) -> bool:
	return _card_has_effect(card, "reflect") and "full_reflect" in card.get("tags", [])

func _effect_short_label(effect: String) -> String:
	match effect:
		"attack":
			return "攻"
		"buff":
			return "攻＋"
		"guard":
			return "守"
		"reflect":
			return "反"
		"heal":
			return "癒"
		"instant_death":
			return "死"
		"buy":
			return "買"
		"sell":
			return "売"
		"exchange":
			return "両替"
	return "特"

func _attribute_label(card: Dictionary) -> String:
	return _attribute_label_from_name(String(card.get("attribute", "none")))

func _card_value_text(card: Dictionary, _show_price: bool = false) -> String:
	if _is_trade_buy(card):
		return "買う%d枚" % maxi(1, int(card.get("power", 1)))
	if _is_trade_sell(card):
		return "売る最大%d枚" % maxi(1, int(card.get("power", 1)))
	if _is_exchange(card):
		return "両替"
	var parts: Array[String] = []
	var effects: Array = _card_effects(card)
	var random_mode: bool = String(card.get("effect_mode", "all")) == "random_one"
	for effect_index: int in range(effects.size()):
		var effect_entry: Dictionary = effects[effect_index]
		var effect: String = String(effect_entry.get("effect", ""))
		var part: String = "完反" if (effect == "reflect" and _is_full_reflect(card)) else _effect_short_label(effect)
		if effect not in ["instant_death", "reflect"]:
			part += " %d" % int(effect_entry.get("power", 0))
		if random_mode:
			part += " %d%%" % _random_effect_percent(card, effect_index)
		parts.append(part)
	var separator := " / " if random_mode or _uses_contextual_roles(card) else "＋"
	var special_suffix: String = _special_effect_label(card)
	if not special_suffix.is_empty():
		special_suffix = "　特殊:%s" % special_suffix
	return "%s%s%s%s" % [
		separator.join(parts),
		"" if random_mode else _chance_suffix(card),
		special_suffix,
		_cost_suffix(card),
	]

func _special_effect_label(card: Dictionary) -> String:
	match String(card.get("special_effect", "")):
		"double_attack":
			return "2回攻撃"
		"attribute_change":
			return "属性変更:%s" % _attribute_label_from_name(
				String(card.get("special_attribute", "none"))
			)
		"double_power":
			return "攻撃力倍"
		"attribute_erase":
			return "属性消し"
	return ""

func _random_effect_percent(card: Dictionary, effect_index: int) -> int:
	var effects: Array = _card_effects(card)
	if effect_index < 0 or effect_index >= effects.size():
		return 0
	var total_weight := 0
	for effect_entry: Dictionary in effects:
		total_weight += maxi(1, int(effect_entry.get("weight", 1)))
	if total_weight <= 0:
		return 0
	var effect_entry: Dictionary = effects[effect_index]
	var card_chance: float = clampi(int(card.get("chance", 100)), 0, 100) / 100.0
	var effect_chance: float = clampi(int(effect_entry.get("chance", 100)), 0, 100) / 100.0
	var branch_chance: float = maxi(1, int(effect_entry.get("weight", 1))) / float(total_weight)
	return int(round(100.0 * card_chance * branch_chance * effect_chance))

func _hand_card_value_text(card: Dictionary) -> String:
	if _is_trade_buy(card):
		return "買%d" % maxi(1, int(card.get("power", 1)))
	if _is_trade_sell(card):
		return "売≤%d" % maxi(1, int(card.get("power", 1)))
	if _is_exchange(card):
		return "両替"
	var parts: Array[String] = []
	var effects: Array = _card_effects(card)
	for effect_index: int in range(effects.size()):
		var effect_entry: Dictionary = effects[effect_index]
		var effect_name: String = String(effect_entry.get("effect", ""))
		var target_name: String = String(effect_entry.get("target", card.get("target", "")))
		var label: String
		if target_name == "all_enemies":
			label = "全"
		elif target_name == "all_players":
			label = "（全）"
		elif effect_name == "reflect" and _is_full_reflect(card):
			label = "完反"
		else:
			label = _effect_short_label(effect_name)
		if effect_name not in ["instant_death", "reflect"]:
			label += str(int(effect_entry.get("power", 0)))
		if String(card.get("effect_mode", "all")) == "random_one":
			label += " %d%%" % _random_effect_percent(card, effect_index)
		parts.append(label)
	var separator: String = (
		"／"
		if String(card.get("effect_mode", "all")) == "random_one" or _uses_contextual_roles(card)
		else "＋"
	)
	return "%s%s%s" % [
		separator.join(parts),
		"" if String(card.get("effect_mode", "all")) == "random_one" else _chance_suffix(card),
		_cost_suffix(card),
	]

func _cost_suffix(card: Dictionary) -> String:
	var cost: Dictionary = card.get("cost", {}) if card.get("cost", {}) is Dictionary else {}
	var amount: int = int(cost.get("amount", 0))
	if amount <= 0:
		return ""
	match String(cost.get("resource", "none")):
		"gold":
			return " ¥%d" % amount
		"mp":
			return " MP%d" % amount
		"hp":
			return " HP%d" % amount
	return ""

func _chance_suffix(card: Dictionary) -> String:
	var chance: int = clampi(int(card.get("chance", 100)), 0, 100)
	return " %d%%" % chance if chance < 100 else ""

func _attribute_label_from_name(attribute: String) -> String:
	match attribute:
		"fire":
			return "火"
		"water":
			return "水"
		"wood":
			return "木"
		"earth":
			return "土"
		"light":
			return "光"
		"dark":
			return "闇"
		"mixed":
			return "複合"
	return "無"

func _combined_attribute_names(attributes: Array[String]) -> String:
	if attributes.is_empty():
		return "none"
	var combined: String = attributes[0]
	for attribute: String in attributes:
		if attribute != combined:
			return "mixed"
	return combined

func _combined_action_attribute() -> String:
	if selected_action_cards.is_empty():
		return "none"
	var combined := ""
	var has_light := false
	for card: Dictionary in selected_action_cards:
		var attribute: String = String(card.get("attribute", "none"))
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

func _attribute_can_defend(attack_attribute: String, defense_attribute: String) -> bool:
	match attack_attribute:
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

func _attribute_color(card: Dictionary) -> Color:
	if _only_healing_effects(card):
		if _card_has_negative_heal(card):
			return Color("#e04444")
		return Color("#20a464")
	match String(card.get("attribute", "none")):
		"fire":
			return Color("#ff5a57")
		"water":
			return Color("#5877ff")
		"wood":
			return Color("#ff9f1c")
		"earth":
			return Color("#7894a8")
		"light":
			return Color("#d3c900")
		"dark":
			return Color("#a95adf")
	return Color("#40535b")

func _load_card_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _apply_theme() -> void:
	top_bar.add_theme_stylebox_override("panel", _rounded_style(Color("#008f78"), Color("#008f78"), 0))
	bottom_bar.add_theme_stylebox_override("panel", _rounded_style(Color("#008f78"), Color("#008f78"), 0))
	hand_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.02, 0.52, 0.45, 0.22), Color("#008f78"), 0))
	own_status.add_theme_stylebox_override("panel", _rounded_style(Color("#f5f1ed"), Color("#a3aaa7"), 1))
	own_status_label.add_theme_color_override("font_color", Color("#007e68"))
	target_status.add_theme_stylebox_override("panel", _rounded_style(Color("#f5f1ed"), Color("#a3aaa7"), 1))
	target_status_label.add_theme_color_override("font_color", Color("#334cbb"))
	attack_total_panel.add_theme_stylebox_override("panel", _rounded_style(Color("#ecffe4"), Color("#52675d"), 3))
	defense_total_panel.add_theme_stylebox_override("panel", _rounded_style(Color("#ecffe4"), Color("#52675d"), 3))
	defense_total.add_theme_color_override("font_color", Color("#40535b"))
	hover_detail_header.add_theme_stylebox_override("panel", _rounded_style(Color("#f5f1ed"), Color("#738a84"), 1))
	hover_detail_header.get_node("Label").add_theme_color_override("font_color", Color("#40535b"))
	hover_card_name.add_theme_color_override("font_color", Color("#335a83"))
	hover_card_description.add_theme_color_override("font_color", Color("#40535b"))
	hover_card_no_art.add_theme_color_override("font_color", Color("#738a84"))
	var hover_price_style: StyleBoxFlat = _rounded_style(
		Color("#fff6b8"), Color("#e7cc58"), 1
	)
	hover_price_style.set_corner_radius_all(23)
	hover_card_price_badge.add_theme_stylebox_override("panel", hover_price_style)
	hover_card_price.add_theme_color_override("font_color", Color("#40535b"))
	selected_card_panel.add_theme_stylebox_override("panel", _rounded_style(Color("#d9ffd4"), Color("#35aa80"), 3))
	selected_card_name.add_theme_color_override("font_color", Color("#335a83"))
	selected_card_description.add_theme_color_override("font_color", Color("#40535b"))
	selected_card_value.add_theme_color_override("font_color", Color("#526ea2"))
	center_message.add_theme_color_override("font_color", Color("#007f76"))
	exchange_panel.add_theme_stylebox_override("panel", _rounded_style(
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		0
	))
	exchange_values_panel.add_theme_stylebox_override("panel", _rounded_style(
		Color("#f5f1ed"),
		Color("#a3aaa7"),
		1
	))
	for value_label: Label in [exchange_hp_value, exchange_mp_value, exchange_gold_value]:
		value_label.add_theme_color_override("font_color", Color("#40535b"))
	var exchange_buttons: Array[Button] = [
		$ExchangePanel/Margin/Content/Plus10Row/Mp,
		$ExchangePanel/Margin/Content/Plus10Row/Gold,
		$ExchangePanel/Margin/Content/Plus1Row/Mp,
		$ExchangePanel/Margin/Content/Plus1Row/Gold,
		$ExchangePanel/Margin/Content/Minus1Row/Mp,
		$ExchangePanel/Margin/Content/Minus1Row/Gold,
		$ExchangePanel/Margin/Content/Minus10Row/Mp,
		$ExchangePanel/Margin/Content/Minus10Row/Gold,
	]
	for exchange_button: Button in exchange_buttons:
		exchange_button.add_theme_stylebox_override("normal", _rounded_style(
			Color("#d3bd38"), Color("#f4df73"), 3
		))
		exchange_button.add_theme_stylebox_override("hover", _rounded_style(
			Color("#dfc947"), Color("#fff09a"), 3
		))
		exchange_button.add_theme_stylebox_override("pressed", _rounded_style(
			Color("#bca72d"), Color("#f4df73"), 3
		))
		exchange_button.add_theme_color_override("font_color", Color("#fff6bb"))
		exchange_button.add_theme_color_override("font_hover_color", Color.WHITE)
		exchange_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	result_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.12, 0.14, 0.15, 0.9), Color("#ffffff"), 0))
	action_button.add_theme_stylebox_override("normal", _rounded_style(Color("#008e8a"), Color("#007c77"), 1))
	action_button.add_theme_stylebox_override("hover", _rounded_style(Color("#00a39d"), Color("#007c77"), 2))
	action_button.add_theme_stylebox_override("pressed", _rounded_style(Color("#007c77"), Color("#00635f"), 2))
	action_button.add_theme_color_override("font_color", Color.WHITE)
	action_button.add_theme_color_override("font_hover_color", Color.WHITE)
	action_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	card_use_button.add_theme_stylebox_override("normal", _rounded_style(
		Color(0.9, 1.0, 0.97, 0.0),
		Color(0.9, 1.0, 0.97, 0.0),
		0
	))
	card_use_button.add_theme_stylebox_override("hover", _rounded_style(
		Color(0.9, 1.0, 0.97, 0.18),
		Color(0.75, 1.0, 0.92, 0.32),
		1
	))
	card_use_button.add_theme_stylebox_override("pressed", _rounded_style(
		Color(0.9, 1.0, 0.97, 0.28),
		Color(0.65, 0.95, 0.86, 0.52),
		2
	))
	pass_defense_button.add_theme_stylebox_override("normal", _rounded_style(Color("#f3eee8"), Color("#738a84"), 1))
	pass_defense_button.add_theme_color_override("font_color", Color("#40535b"))
	bottom_status.add_theme_color_override("font_color", Color.WHITE)

func _set_card_style(panel: PanelContainer, selected: bool, disabled: bool) -> void:
	disabled = disabled or not bool(panel.get_meta("card_usable", true))
	# 未選択時は奇跡だけ赤枠。その他は共通色で、選択中はピンクで上書きする。
	var card_border_color: Color = panel.get_meta("card_border_color", Color("#9caaa5"))
	var fill := Color("#fff4c9")
	var border := Color("#f26f9e") if selected else card_border_color
	if disabled:
		fill = Color("#d5ddd9")
		if not selected:
			border = Color("#b7c1bc")
	var style: StyleBoxFlat = _rounded_style(fill, border, 4 if selected else 2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

func _rounded_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
