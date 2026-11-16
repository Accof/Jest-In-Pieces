extends Node
## Dev: the title screen, filmed: /tmp/k/menu_*.png (needs a window).
func _ready() -> void:
	Engine.set_meta(&"test_save", true)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame
	var mm: MainMenu = game.main_menu
	print("menu visible %s, buttons %d, state %d" % [mm.visible, mm.buttons.size(), game.state])
	mm.hold_seconds = 1.0
	mm.fade_seconds = 1.0
	var t := 0.0
	var k := 0
	while k < 6:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 0.5 * k:
			get_viewport().get_texture().get_image().save_png("/tmp/k/menu_%d.png" % k)
			k += 1
	print("fades %d, now showing %d" % [mm.fades, mm.current])
	# hover the second button
	mm.buttons[1].grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/k/menu_focus.png")
	get_tree().quit()
