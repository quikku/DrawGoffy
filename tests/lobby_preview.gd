extends SceneTree

func _init() -> void:
	call_deferred("_render_preview")

func _render_preview() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var tabs: TabContainer = main.get_node("Root/Tabs")
	tabs.current_tab = 0
	var name_edit: LineEdit = main.get_node("Root/Tabs/Lobby/NameRow/PlayerName")
	name_edit.text = "うんち"
	var address: LineEdit = main.get_node("Root/Tabs/Lobby/ConnectRow/JoinAddress")
	address.text = "192.168.1.20"
	var players: ItemList = main.get_node("Root/Tabs/Lobby/Players")
	players.add_item("うんち / peer 1")
	players.add_item("ぺけねデヴ / peer 87213641")
	players.add_item("友人その2 / peer 45120037")
	var log: RichTextLabel = main.get_node("Root/Tabs/Lobby/NetworkInfo")
	log.add_text("ホストを開始しました。ポート 32145\n")
	log.add_text("UPnP 成功。外部IP 203.0.113.7 を参加者へ伝えてください。\n")
	log.add_text("ぺけねデヴ が参加しました。\n")
	log.add_text("対戦用の共有カード: 24枚\n")
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	var image: Image = root.get_viewport().get_texture().get_image()
	var error: Error = image.save_png("res://tests/lobby_preview.png")
	assert(error == OK)
	print("lobby_preview: PASS")
	main.free()
	quit()
