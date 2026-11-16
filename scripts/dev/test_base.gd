extends Node
## The base and the loop round it: title -> base -> each station -> a run
## (tables with seated clowns) -> death -> back to base -> new game wipe.
## Pass --render for /tmp/base_*.png (needs a window).
var render := false
var game: Node3D


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/base_%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _look(from: Vector3, at: Vector3) -> void:
	var p: FpsPlayer = game.player
	p.global_position = from - Vector3.UP * 1.65
	p.look_at(Vector3(at.x, p.global_position.y, at.z))
	p.camera.look_at(at)


func _use_at(at: Vector3) -> String:
	# stand in front of it, look at it, read the prompt, press E
	var p: FpsPlayer = game.player
	var u: Object = p._usable()
	var prompt: String = u.prompt() if u else "(nothing)"
	p._use()
	return prompt


func _run() -> void:
	game = _test_game_scene().instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.new_game(true)                           # start clean
	print("title: state=%d (MENU=0)" % game.state)
	game.save.tickets = 100
	game.go_base()
	await _frames(10)
	var b: Base = game.base
	print("base: state=%d (BASE=4) player at %s" % [game.state, game.player.global_position.snapped(Vector3.ONE * 0.1)])
	await _shot("0_wake")
	# 1. the fortune teller
	_look(Vector3(5.4, 1.65, 3.5), Vector3(6.6, 1.4, 4.7))
	await _frames(2)
	print("fortune prompt: %s" % game.player._usable().prompt())
	game.player._use()
	print("fortune: %s, tickets now %d" % [str(game.save.fortune.get("kind", "")), int(game.save.tickets)])
	await _frames(30)
	await _shot("1_fortune")
	# 2. the quartermaster
	_look(Vector3(-5.3, 1.65, -1.0), Vector3(-6.4, 1.0, -1.0))
	await _frames(2)
	print("shop prompt: %s" % game.player._usable().prompt())
	game.player._use()
	print("shop open: state=%d (SHOP=5)" % game.state)
	await _shot("2_shop")
	game._buy_perk(0)
	print("bought Thick Skin: perks=%s tickets=%d" % [str(game.save.perks), int(game.save.tickets)])
	game.close_shop()
	await _frames(5)
	_look(Vector3(-4.0, 1.65, -1.0), Vector3(-7.0, 1.6, -1.0))
	await _shot("3_quartermaster")
	# 3. the armoury: start with the rifle
	_look(Vector3(6.6, 1.65, -4.6), Vector3(6.6, 1.7, -5.8))
	await _frames(2)
	print("rack prompt: %s" % game.player._usable().prompt())
	game.player._use()
	print("start weapon: %d" % int(game.save.start_weapon))
	_look(Vector3(4.8, 1.8, -2.2), Vector3(4.8, 1.8, -5.9))
	await _shot("4_armoury")
	# 4. the boards
	_look(Vector3(3.2, 2.0, 0.6), Vector3(7.9, 2.0, 0.6))
	await _shot("5_stats")
	_look(Vector3(-4.0, 2.0, 1.2), Vector3(-4.0, 2.0, 5.9))
	await _shot("6_trophies")
	_look(Vector3(2.5, 1.9, 3.2), Vector3(0.0, 1.0, -1.0))
	await _shot("7_room")
	_look(Vector3(0.0, 1.8, -2.5), Vector3(0.0, 1.5, -5.9))
	await _shot("8_door")
	# 5. through the door
	_look(Vector3(0.0, 1.65, -4.9), Vector3(0.0, 1.2, -5.9))
	await _frames(2)
	print("door prompt: %s" % game.player._usable().prompt())
	game.player._use()
	await _frames(20)
	print("run: state=%d floor=%d weapon=%d taken=%s fortune cleared=%s" % [game.state, game.floor_number, game.player.weapon, str(game.taken), str(game.save.fortune.is_empty())])
	# the tables
	var tables: Array = []
	for n in game.world().get_children():
		if n is MessTable:
			tables.append(n)
	var seated := 0
	for t in tables:
		seated += (t as MessTable)._seats.size()
	print("tables=%d seated=%d clowns=%d remaining=%d" % [tables.size(), seated, game.clowns.size(), game.remaining])
	if not tables.is_empty():
		var t: MessTable = tables[0]
		# seated legs must hold still: sample the knee over a second
		var sat: Clown = t._seats[0].clown
		var sk := sat.skeleton
		var knees: Array[float] = []
		for f in 6:
			await _frames(10)
			knees.append(sk.get_bone_pose_rotation(sk.find_bone("LeftLowerLeg")).get_euler().x)
		print("seated knee over 1s: min %.3f max %.3f rad (should not move); walk_amount=%.2f" % [knees.min(), knees.max(), sat.walk_amount])
		var victim: Clown = t._seats[0].clown
		var other: Clown = t._seats[1].clown
		var tp := t.global_position
		if render:
			var cam := Camera3D.new()
			game.world().add_child(cam)
			cam.global_position = tp + (t.global_basis.x * 1.9 + Vector3.UP * 1.5)
			cam.look_at(tp + Vector3.UP * 0.7)
			cam.make_current()
			await _shot("9_table")
		var pb: PhysicalBone3D = victim.ragdoll.bones[&"Neck"]
		victim.hit({collider = pb, position = pb.global_position, direction = (tp - pb.global_position).normalized(), damage = 300.0, impulse = 6.0, shot_id = 4242, weapon = "Pistol"})
		await _frames(100)
		var chest: Vector3 = victim.ragdoll.bones[&"Chest"].global_position
		print("seated kill: dead=%s chest %.2fm from the table centre, %.2fm up; the other: standing=%s brain on=%s" % [victim.dead, Vector2(chest.x - tp.x, chest.z - tp.z).length(), chest.y - tp.y, t._seats[1].standing, other.get_node("Brain").is_physics_processing()])
		await _shot("10_slumped")
		game.player.camera.make_current()
	print("stats so far: %s" % str(game.save.stats))
	# 6. die, see the screen, back to base
	FpsPlayer.god_mode = false
	game.player.take_damage(9999.0)
	await _frames(5)
	print("dead: state=%d (DEAD=3) history=%s trophies=%s" % [game.state, str(game.save.history), str(game.save.trophies)])
	await _shot("11_dead")
	# (test only) enough on the books to win most of the trophies
	for k: String in ["headshots", "blown_up", "staked", "soldiers", "limbs", "through", "best_pierce", "knockdowns", "seated", "golds"]:
		game.save.stats[k] = 99
	game.save.total_kills = 600
	game.save.best_floor = 6
	game.go_base()
	await _frames(10)
	print("back at base: state=%d trophies=%d/%d tickets=%d" % [game.state, game.save.trophies.size(), Records.TROPHIES.size(), int(game.save.tickets)])
	_look(Vector3(-4.0, 2.0, 3.0), Vector3(-4.0, 2.0, 5.9))
	await _shot("12b_trophies_won")
	_look(Vector3(-5.8, 2.1, 4.6), Vector3(-5.8, 2.2, 5.9))
	await _shot("12c_trophies_close")
	_look(Vector3(3.2, 2.0, 0.6), Vector3(7.9, 2.0, 0.6))
	await _shot("12_stats_after")
	# 7. new game: confirm screen, then wiped
	game._show_menu()
	game.new_game()
	print("confirm screen: state=%d (CONFIRM=6)" % game.state)
	await _shot("13_confirm")
	game.new_game(true)
	print("wiped: tickets=%d kills=%d trophies=%s stats=%s" % [int(game.save.tickets), int(game.save.total_kills), str(game.save.trophies), str(game.save.stats)])
	get_tree().quit()


## The game scene, set to use a throwaway save so a test never touches yours.
func _test_game_scene() -> PackedScene:
	Engine.set_meta(&"test_save", true)
	return load("res://scenes/game.tscn")
