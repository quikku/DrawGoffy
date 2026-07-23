extends SceneTree

func _init() -> void:
	call_deferred("_render_preview")

func _render_preview() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var tabs: TabContainer = main.get_node("Root/Tabs")
	tabs.current_tab = 1
	await process_frame
	await process_frame
	var editor: VBoxContainer = main.get_node("Root/Tabs/Cards/Editor")
	var delete_button: Button = editor.get_node("DeleteCardButton")
	var viewport_bottom: float = root.get_viewport().get_visible_rect().end.y
	assert(delete_button.get_global_rect().end.y <= viewport_bottom)
	assert(editor.get_node("ProbabilityRow").visible)
	assert(editor.get_node("SecondEffectRow").visible)
	await create_timer(0.25).timeout
	var image: Image = root.get_viewport().get_texture().get_image()
	var error: Error = image.save_png("res://tests/main_preview.png")
	assert(error == OK)
	print("main_preview: PASS")
	main.free()
	quit()
