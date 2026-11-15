extends Node
## Bolt-action rifle: one round through a line of four clowns. Pass --render
## for /tmp/rifle_*.png (idle, bolt being worked, reload).
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/rifle_%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for n in room.get_children():
		if n is ExplosiveBarrel:
			n.queue_free()
	var p: FpsPlayer = room.player
	var pierced := [0]
	p.pierced.connect(func(n: int) -> void: pierced[0] = n)
	p.select_weapon(FpsPlayer.RIFLE)
	# four in a line straight down the room, one behind the other
	for i in room.clowns.size():
		var c: Clown = room.clowns[i]
		if i < 4:
			c.global_position = Vector3(0.05 * (i % 2), 0, -2.5 - i * 1.4)
			c.rotation.y = 0.0
		else:
			c.global_position = Vector3(6, 0, -9)
	p.global_position = Vector3(0, 0.05, 1.5)
	p.rotation.y = 0.0
	await _frames(30)
	await _shot("0_idle")
	var chest: Vector3 = (room.clowns[0] as Clown).ragdoll.bones[&"Chest"].global_position
	p.camera.look_at(chest)
	p.fire()
	await _frames(1)
	var before := p.ammo[FpsPlayer.RIFLE]
	p.fire()
	print("fired again during the bolt: %s" % (p.ammo[FpsPlayer.RIFLE] != before))
	await _shot("1_fired")
	await _frames(22)
	await _shot("2_bolt_up_back")
	await _frames(60)
	var dead := 0
	for i in 4:
		if (room.clowns[i] as Clown).dead:
			dead += 1
	print("one round: %d of 4 in the line dead, pierced=%d, ammo=%d" % [dead, pierced[0], p.ammo[FpsPlayer.RIFLE]])
	await _shot("3_after")
	# empty it and reload
	for k in 4:
		await get_tree().create_timer(1.2).timeout
		p.fire()
	await get_tree().create_timer(1.2).timeout
	p.camera.rotation.x = 0.0
	p.reload()
	for st: Array in [[0.55, "4_clip"], [0.6, "5_thumb"], [0.6, "6_flick"]]:
		await get_tree().create_timer(st[0]).timeout
		await _shot(st[1])
	await get_tree().create_timer(1.2).timeout
	print("after reload: ammo=%d reloading=%s" % [p.ammo[FpsPlayer.RIFLE], p.view.reloading()])
	get_tree().quit()
