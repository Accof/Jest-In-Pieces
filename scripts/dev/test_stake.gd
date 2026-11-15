extends Node
## Stake gun: skewer and pin to a wall; bullet wear on head and chest.
## Pass --render to save images to /tmp/stake_*.png.
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/stake_%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	var p: FpsPlayer = room.player
	p.select_weapon(FpsPlayer.STAKE)
	await _frames(30)
	await _shot("0_idle")
	# 1. skewer the middle clown into the back wall
	var target: Clown = room.clowns[1]
	var chest: Vector3 = target.ragdoll.bones[&"Chest"].global_position
	p.look_at(Vector3(chest.x, p.global_position.y, chest.z))
	p.camera.look_at(chest)
	p.fire()
	await _frames(4)
	await _shot("1_fired")
	await _frames(40)
	await _shot("2_carried")
	await _frames(150)
	if render:
		var pc := Camera3D.new()
		room.add_child(pc)
		var tc0: Vector3 = target.ragdoll.bones[&"Chest"].global_position
		pc.global_position = tc0 + Vector3(1.4, 0.1, 2.0)
		pc.look_at(tc0 + Vector3.DOWN * 0.35)
		pc.make_current()
		await _shot("3_pinned")
		p.camera.make_current()
	var c2: Vector3 = target.ragdoll.bones[&"Chest"].global_position
	print("stake: target dead=%s, chest now z=%.2f (wall face at -9.25), chest height %.2f, carried %.1fm" % [target.dead, c2.z, c2.y, c2.distance_to(chest)])
	print("stake gun ammo after shot: %d, reloading=%s" % [p.ammo[FpsPlayer.STAKE], p.view.reloading()])
	await get_tree().create_timer(0.6 if not render else 0.1).timeout
	if render:
		for st: Array in [[0.5, "4_fetch"], [0.6, "5_rail"], [0.6, "6_pump"]]:
			await get_tree().create_timer(st[0]).timeout
			await _shot(st[1])
	await get_tree().create_timer(3.0).timeout
	print("after reload: ammo=%d" % p.ammo[FpsPlayer.STAKE])
	# 2. bullet wear: pistol rounds into one clown's head and another's chest
	p.select_weapon(FpsPlayer.PISTOL)
	await _frames(30)
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	var hc: Clown = room.clowns[0]
	var bc: Clown = room.clowns[2]
	var log := []
	for i in 7:
		var head: Vector3 = hc.ragdoll.bones[&"Neck"].global_position + Vector3.UP * 0.06
		p.shoot_ray(p.camera.global_position, (head - p.camera.global_position).normalized(), w, 1000 + i)
		await _frames(10)
		log.append(hc._wear_stage.get(&"Head", 0))
	print("head wear stage after each pistol round: ", log)
	log = []
	for i in 10:
		var ch: Vector3 = bc.ragdoll.bones[&"Chest"].global_position
		p.shoot_ray(p.camera.global_position, (ch - p.camera.global_position).normalized(), w, 2000 + i)
		await _frames(10)
		log.append(bc._wear_stage.get(&"Chest", 0))
	print("chest wear stage after each pistol round: ", log)
	if render:
		await _frames(60)
		var cam := Camera3D.new()
		room.add_child(cam)
		for pair: Array in [[hc, "7_head"], [bc, "8_chest"]]:
			var cl: Clown = pair[0]
			var hp: Vector3 = cl.ragdoll.bones[&"Neck" if pair[1] == "7_head" else &"Chest"].global_position
			cam.global_position = hp + Vector3(0.5, 0.7, 0.6)
			cam.look_at(hp)
			cam.make_current()
			await _shot(pair[1])
		var tc: Vector3 = target.ragdoll.bones[&"Chest"].global_position
		cam.global_position = tc + Vector3(1.6, 0.2, 2.2)
		cam.look_at(tc + Vector3.DOWN * 0.3)
		await _shot("9_pinned_close")
	get_tree().quit()
