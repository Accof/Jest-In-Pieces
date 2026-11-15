extends Node
## Checks the SMG and god mode. Pass --render to save view-model images.
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/smg_%s.png" % name)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	var p: FpsPlayer = room.player
	p.select_weapon(FpsPlayer.SMG)
	await _wait(0.5)
	print("weapon=%d ammo=%d" % [p.weapon, p.ammo[p.weapon]])
	await _shot("0_idle")
	# hold the trigger for a second, aimed at the middle clown's chest
	var target: Clown = room.clowns[1]
	p.look_at(Vector3(target.global_position.x, p.global_position.y, target.global_position.z))
	var chest: Vector3 = target.ragdoll.bones[&"Chest"].global_position
	p.camera.look_at(chest)
	var shots := 0
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0 < 1000) if not render else shots < 6:
		var before := p.ammo[p.weapon]
		p.fire()
		if p.ammo[p.weapon] < before:
			shots += 1
		if shots == 4:
			await _shot("1_firing")
		await get_tree().physics_frame
	print("1s of fire: %d rounds, %d left, target dead=%s" % [shots, p.ammo[p.weapon], target.dead])
	p.reload()
	for st: Array in [[0.45, "2_mag_out"], [0.5, "3_new_mag"], [0.3, "4_bolt"], [0.8, "5_done"]]:
		await _wait(st[0])
		await _shot(st[1])
	print("after reload: ammo=%d reloading=%s" % [p.ammo[p.weapon], p.view.reloading()])
	# god mode
	FpsPlayer.god_mode = true
	var hp := p.health
	p.take_damage(500.0)
	print("god mode: health %.0f -> %.0f dead=%s" % [hp, p.health, p.dead])
	FpsPlayer.god_mode = false
	p.take_damage(10.0)
	print("god mode off: health now %.0f" % p.health)
	get_tree().quit()
