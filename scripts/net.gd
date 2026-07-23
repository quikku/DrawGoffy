extends Node

signal status_changed(message: String)
signal players_changed(players: Array)
signal cards_synced(cards: Array)
signal game_state_synced(state: Dictionary)

const DEFAULT_PORT := 32145
const MAX_PLAYERS := 8

var players: Dictionary = {}
var is_host := false
var upnp: UPNP
var upnp_thread: Thread
var mapped_port := 0
var next_bot_peer_id := 10000
var bot_action_pending := false
var result_continue_pending := false
var my_player_name: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): status_changed.emit("接続に失敗した。IP/ポート/開放を確認。"))
	multiplayer.server_disconnected.connect(func(): status_changed.emit("ホストから切断された。"))

func host(port: int = DEFAULT_PORT, player_name: String = "") -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		status_changed.emit("ホスト開始に失敗: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_player_name = player_name.strip_edges().left(20) if not player_name.strip_edges().is_empty() else "ホスト"
	players = {1: {"peer_id": 1, "name": my_player_name}}
	CardStore.clear_session()
	GameRules.state.clear()
	_try_upnp(port)
	_emit_players()
	status_changed.emit("ホスト開始。ポート %s（UPnPの結果は後で表示されます）" % port)

func join(address: String, port: int = DEFAULT_PORT, player_name: String = "") -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		status_changed.emit("参加開始に失敗: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	CardStore.clear_session()
	GameRules.state.clear()
	my_player_name = player_name.strip_edges().left(20) if not player_name.strip_edges().is_empty() else ""
	status_changed.emit("%s:%s に接続中。" % [address, port])

func _on_connected_to_server() -> void:
	status_changed.emit("ホストに接続した。")
	if not my_player_name.is_empty():
		_set_player_name.rpc_id(1, my_player_name)

func close() -> void:
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
		upnp_thread = null
	if upnp and mapped_port > 0:
		upnp.delete_port_mapping(mapped_port, "UDP")
		mapped_port = 0
	multiplayer.multiplayer_peer = null
	is_host = false
	bot_action_pending = false
	result_continue_pending = false
	players.clear()
	CardStore.clear_session()
	GameRules.state.clear()

func _exit_tree() -> void:
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
		upnp_thread = null

func send_my_cards(cards: Array) -> void:
	if is_host:
		var received: Array = CardStore.receive_cards_from_peer(cards, 1)
		_broadcast_cards()
		status_changed.emit("自分のカードを%d枚、画像込みで登録しました。" % received.size())
	else:
		_submit_cards.rpc_id(1, cards)
		status_changed.emit("カードと画像をホストへ送信中です。")

func start_game() -> void:
	if not is_host:
		return
	# ホスト自身のカードは未送信でも自動でセッションへ登録する（重複はID一致で吸収）。
	CardStore.receive_cards_from_peer(CardStore.export_cards_with_images(), 1)
	_broadcast_cards()
	if CardStore.session_cards.is_empty():
		status_changed.emit("カードが1枚もないため開始できません。")
		return
	var seed_value: int = randi()
	var state: Dictionary = GameRules.new_match(players.values(), CardStore.session_cards, seed_value)
	_publish_game_state(state)

func add_debug_bot() -> void:
	if not is_host:
		status_changed.emit("デバッグ敵はホストだけが追加できます。")
		return
	if not GameRules.state.is_empty():
		status_changed.emit("デバッグ敵はゲーム開始前に追加してください。")
		return
	if players.size() >= MAX_PLAYERS:
		status_changed.emit("これ以上プレイヤーを追加できません。")
		return
	var bot_number: int = 1
	for player: Variant in players.values():
		if player is Dictionary and bool(player.get("is_bot", false)):
			bot_number += 1
	var bot_peer_id: int = next_bot_peer_id
	next_bot_peer_id += 1
	players[bot_peer_id] = {
		"peer_id": bot_peer_id,
		"name": "デバッグ敵 %d" % bot_number,
		"is_bot": true,
	}
	_sync_players.rpc(players.values())
	_emit_players()
	status_changed.emit("ランダム行動するデバッグ敵を追加しました。")

func submit_play(card_ids: Array, target_peer_id: int) -> void:
	if is_host:
		var state: Dictionary = GameRules.play_action_cards(1, card_ids, target_peer_id)
		_publish_game_state(state)
	else:
		_submit_play.rpc_id(1, card_ids, target_peer_id)

func submit_pray() -> void:
	var actor_peer_id: int = 1 if is_host else multiplayer.get_unique_id()
	if is_host:
		_publish_game_state(GameRules.pray(actor_peer_id))
	else:
		_submit_pray.rpc_id(1)

func pass_defense() -> void:
	var actor_peer_id: int = 1 if is_host else multiplayer.get_unique_id()
	if is_host:
		var state: Dictionary = GameRules.pass_defense(actor_peer_id)
		_publish_game_state(state)
	else:
		_pass_defense.rpc_id(1)

func submit_defense(card_ids: Array[String]) -> void:
	var actor_peer_id: int = 1 if is_host else multiplayer.get_unique_id()
	if is_host:
		_publish_game_state(GameRules.play_defense_cards(actor_peer_id, card_ids))
	else:
		_submit_defense.rpc_id(1, card_ids)

func _try_upnp(port: int) -> void:
	# UPNP.discover はブロッキングなので、UI を止めないよう別スレッドで実行する。
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
	upnp_thread = Thread.new()
	upnp_thread.start(_upnp_thread_main.bind(port))

func _upnp_thread_main(port: int) -> void:
	var worker: UPNP = UPNP.new()
	var message: String
	var new_mapped_port := 0
	var discover_error: int = worker.discover(2000, 2, "InternetGatewayDevice")
	if discover_error != OK:
		message = "UPnP未検出。必要なら手動でUDP %sを開放。" % port
	else:
		var gateway: UPNPDevice = worker.get_gateway()
		if not gateway or not gateway.is_valid_gateway():
			message = "UPnPゲートウェイなし。必要なら手動でUDP %sを開放。" % port
		else:
			var map_error: int = worker.add_port_mapping(port, port, String(ProjectSettings.get_setting("application/config/name")), "UDP")
			if map_error == OK:
				new_mapped_port = port
				message = "UPnPでUDP %sを自動開放した。外部IP: %s" % [port, worker.query_external_address()]
			else:
				message = "UPnP開放失敗。必要なら手動でUDP %sを開放。" % port
	_apply_upnp_result.call_deferred(worker, new_mapped_port, message)

func _apply_upnp_result(worker: UPNP, new_mapped_port: int, message: String) -> void:
	upnp = worker
	mapped_port = new_mapped_port
	status_changed.emit(message)

@rpc("any_peer", "reliable")
func _set_player_name(name: String) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["name"] = name.strip_edges().left(20)
		_sync_players.rpc(players.values())
		_emit_players()

@rpc("any_peer", "reliable")
func _submit_cards(cards: Array) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var received: Array = CardStore.receive_cards_from_peer(cards, sender)
	_cards_received.rpc_id(sender, received.size())
	_broadcast_cards()

@rpc("authority", "reliable")
func _cards_received(count: int) -> void:
	status_changed.emit("ホストがカードを%d枚受領しました。画像も全員へ配布されます。" % count)

@rpc("any_peer", "reliable")
func _submit_play(card_ids: Array, target_peer_id: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var state: Dictionary = GameRules.play_action_cards(sender, card_ids, target_peer_id)
	_publish_game_state(state)

@rpc("any_peer", "reliable")
func _submit_pray() -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_publish_game_state(GameRules.pray(sender))

@rpc("any_peer", "reliable")
func _pass_defense() -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var state: Dictionary = GameRules.pass_defense(sender)
	_publish_game_state(state)

@rpc("any_peer", "reliable")
func _submit_defense(card_ids: Array[String]) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_publish_game_state(GameRules.play_defense_cards(sender, card_ids))

@rpc("authority", "reliable")
func _sync_cards(cards: Array) -> void:
	CardStore.clear_session()
	CardStore.receive_cards_from_peer(cards, 1)
	cards_synced.emit(CardStore.session_cards)

@rpc("authority", "reliable")
func _sync_players(incoming_players: Array) -> void:
	players.clear()
	for raw_player: Variant in incoming_players:
		if raw_player is Dictionary:
			var player: Dictionary = raw_player
			players[int(player["peer_id"])] = player
	_emit_players()

@rpc("authority", "reliable")
func _sync_game_state(incoming_state: Dictionary) -> void:
	GameRules.state = incoming_state
	game_state_synced.emit(incoming_state)

func _publish_game_state(state: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer():
		_sync_game_state.rpc(state)
	game_state_synced.emit(state)
	call_deferred("_schedule_result_continue")
	call_deferred("_schedule_debug_bot")

func _schedule_result_continue() -> void:
	if not is_host or result_continue_pending or String(GameRules.state.get("phase", "")) != "result":
		return
	result_continue_pending = true
	await get_tree().create_timer(1.9).timeout
	result_continue_pending = false
	if String(GameRules.state.get("phase", "")) == "result":
		_publish_game_state(GameRules.continue_after_result())

func _schedule_debug_bot() -> void:
	if not is_host or bot_action_pending or GameRules.state.is_empty():
		return
	if String(GameRules.state.get("phase", "")) not in ["action", "defense"]:
		return
	var actor_peer_id: int = _active_actor_peer_id()
	if actor_peer_id == 0 or not bool(players.get(actor_peer_id, {}).get("is_bot", false)):
		return
	bot_action_pending = true
	await get_tree().create_timer(0.7).timeout
	bot_action_pending = false
	if actor_peer_id != _active_actor_peer_id():
		return
	_run_debug_bot_action(actor_peer_id)

func _active_actor_peer_id() -> int:
	if String(GameRules.state.get("phase", "action")) == "defense":
		return int(GameRules.state.get("pending_attack", {}).get("target_peer_id", 0))
	var order: Array = GameRules.state.get("player_order", [])
	if order.is_empty():
		return 0
	return int(order[int(GameRules.state.get("turn", 0)) % order.size()])

func _run_debug_bot_action(bot_peer_id: int) -> void:
	var bot: Dictionary = GameRules.state.get("players", {}).get(str(bot_peer_id), {})
	if bot.is_empty() or not bool(bot.get("alive", false)):
		return
	var hand: Array = bot.get("hand", [])
	if String(GameRules.state.get("phase", "action")) == "defense":
		var armors: Array = []
		for raw_card: Variant in hand:
			if (
				raw_card is Dictionary
				and GameRules.can_respond_with_card(
					GameRules.state.get("pending_attack", {}),
					raw_card
				)
			):
				armors.append(raw_card)
		if not armors.is_empty() and randi_range(0, 99) < 70:
			armors.shuffle()
			var defense_ids: Array[String] = []
			var use_count: int = randi_range(1, mini(3, armors.size()))
			for index: int in range(use_count):
				defense_ids.append(String(armors[index]["id"]))
			_publish_game_state(GameRules.play_defense_cards(bot_peer_id, defense_ids))
		else:
			_publish_game_state(GameRules.pass_defense(bot_peer_id))
		return
	var attack_cards: Array = []
	var buff_cards: Array = []
	var support_cards: Array = []
	var action_cards: Array = hand.duplicate()
	action_cards.append_array(bot.get("learned_miracles", []))
	for raw_card: Variant in action_cards:
		if not (raw_card is Dictionary) or not GameRules._can_play_in_action(raw_card):
			continue
		if GameRules._card_has_context_effect(raw_card, "attack", "action"):
			attack_cards.append(raw_card)
		elif GameRules._card_has_context_effect(raw_card, "buff", "action"):
			buff_cards.append(raw_card)
		else:
			support_cards.append(raw_card)
	# 攻撃カード（あれば1枚）に、手札の攻撃アップを全部重ねて撃つ。
	# 攻撃系が無ければ、回復などの補助カードを1枚出す。
	var card_ids: Array = []
	var primary: Dictionary = {}
	if not attack_cards.is_empty():
		primary = attack_cards[randi_range(0, attack_cards.size() - 1)]
		card_ids.append(String(primary["id"]))
		for buff_card: Dictionary in buff_cards:
			card_ids.append(String(buff_card["id"]))
	elif not buff_cards.is_empty():
		primary = buff_cards[0]
		for buff_card: Dictionary in buff_cards:
			card_ids.append(String(buff_card["id"]))
	elif not support_cards.is_empty():
		primary = support_cards[randi_range(0, support_cards.size() - 1)]
		card_ids.append(String(primary["id"]))
	else:
		_publish_game_state(GameRules.pray(bot_peer_id))
		return
	var target_peer_id: int = bot_peer_id
	if (
		(
			GameRules._card_has_context_effect(primary, "attack", "action")
			or GameRules._card_has_context_effect(primary, "buff", "action")
		)
		and String(
			GameRules._first_context_effect(primary, "action").get(
				"target",
				primary.get("target", "enemy")
			)
		) != "all_enemies"
	):
		var targets: Array[int] = []
		for raw_peer_id: Variant in GameRules.state.get("player_order", []):
			var peer_id: int = int(raw_peer_id)
			var target: Dictionary = GameRules.state.get("players", {}).get(str(peer_id), {})
			if peer_id != bot_peer_id and bool(target.get("alive", false)):
				targets.append(peer_id)
		if targets.is_empty():
			_publish_game_state(GameRules.pass_action(bot_peer_id))
			return
		target_peer_id = targets[randi_range(0, targets.size() - 1)]
	_publish_game_state(GameRules.play_action_cards(bot_peer_id, card_ids, target_peer_id))

func _broadcast_cards() -> void:
	_sync_cards.rpc(CardStore.export_session_cards_with_images())
	cards_synced.emit(CardStore.session_cards)

func _emit_players() -> void:
	players_changed.emit(players.values())

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	players[peer_id] = {"peer_id": peer_id, "name": "Player %s" % peer_id}
	_sync_players.rpc(players.values())
	_broadcast_cards()
	_emit_players()

func _on_peer_disconnected(peer_id: int) -> void:
	if players.has(peer_id):
		players.erase(peer_id)
	_emit_players()
	if is_host:
		_sync_players.rpc(players.values())
		if not GameRules.state.is_empty():
			_publish_game_state(GameRules.drop_player(peer_id))
