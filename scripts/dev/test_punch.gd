extends Node
## Shotgun at point blank punches a hole clean through. Renders
## /tmp/punch_*.png: a standing clown with a hole (you should see the wall
## through it), from the front and at an angle, and the body after a real blast.

func _ready() -> void:
	_run()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/punch_%s.png" % name)


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
	var a: Clown = room.clowns[0]
	var b: Clown = room.clowns[1]
	a.global_position = Vector3(0, 0, -1.2)
	a.rotation.y = 0.0
	b.global_position = Vector3(1.4, 0, -1.4)
	b.rotation.y = 0.0
	for i in range(2, room.clowns.size()):
		(room.clowns[i] as Clown).global_position = Vector3(-6, 0, -9)
	p.global_position = Vector3(0, 0.05, 1.0)
	p.rotation.y = 0.0
	await _frames(20)
	# 1. straight onto a standing clown, no kill: is the hole see-through?
	var chest: Vector3 = a.ragdoll.bones[&"Chest"].global_position
	var ok := a.gore.punch_through(&"Chest", chest + Vector3(0, 0, 0.12), Vector3(0, 0, -1), a.punch_radius)
	print("punched: %s" % ok)
	p.camera.look_at(chest)
	p.view.visible = false
	await _shot("1_front")
	p.global_position = Vector3(0.6, 0.05, 0.6)
	p.look_at(Vector3(chest.x, p.global_position.y, chest.z))
	p.camera.look_at(chest)
	await _shot("2_angle")
	# 2. the real thing: shotgun, point blank, at the second clown's chest
	p.view.visible = true
	p.global_position = Vector3(1.4, 0.05, -0.1)
	p.rotation.y = 0.0
	p.select_weapon(FpsPlayer.SHOTGUN)
	await _frames(30)
	var c2: Vector3 = b.ragdoll.bones[&"Chest"].global_position
	p.camera.look_at(c2)
	p.fire()
	print("point-blank blast: tunnels=%d dead=%s" % [b.gore._tunnels.size(), b.dead])
	await _frames(70)
	var c3: Vector3 = b.ragdoll.bones[&"Chest"].global_position
	var cam := Camera3D.new()
	room.add_child(cam)
	cam.global_position = c3 + Vector3(0.0, 1.1, 0.25)
	cam.look_at(c3)
	cam.make_current()
	await _shot("3_body")
	# 3. at range it must not happen
	var far: Clown = room.clowns[2]
	far.global_position = Vector3(0, 0, -6.5)
	cam.queue_free()
	p.camera.make_current()
	p.global_position = Vector3(0, 0.05, 0.5)
	await _frames(40)
	p.camera.look_at(far.ragdoll.bones[&"Chest"].global_position)
	p.fire()
	print("blast at 7m: tunnels=%d" % far.gore._tunnels.size())
	get_tree().quit()
