extends Node
## Every event room, played by a crude bot. Pass --render for /tmp/ev_*.png,
## and "--only=mg_nest" (etc.) to run one.
var render := false
var game: Node3D
var p: FpsPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/ev_%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.start_run()
	await _frames(2)
	p = game.player
	var doors := get_tree().get_nodes_in_group(&"event_doors").filter(func(d): return not d.is_exit)
	print("event doors on floor 1: %d, kinds %s" % [doors.size(), doors.map(func(d): return d.kind)])
	# keep the floor's own clowns out of it
	for c: Clown in game.clowns:
		c.process_mode = Node.PROCESS_MODE_DISABLED
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	for kind in ["mg_nest", "high_wire", "clown_car", "meat_locker"]:
		if only != "" and kind != only:
			continue
		var d: EventDoor = doors[0] if not doors.is_empty() else null
		if d == null:
			print("no door!")
			break
		d.used = false
		d.set_kind(kind)
		p.global_position = d.global_position + d.global_basis.z * 0.9
		game.events.enter(d)
		await get_tree().create_timer(1.2).timeout
		var room: EventRoom = game.events.room
		print("== %s: inside=%s, exit locked=%s, player at %s" % [kind, p.in_event, room.exit_door.locked, room.to_local(p.global_position).snapped(Vector3.ONE * 0.1)])
		match kind:
			"mg_nest": await _play_nest(room)
			_: await _play_room(room, kind)
		print("   finished=%s kills=%d tickets=%d health=%.0f exit locked=%s" % [room.done, room.kills, game.run_tickets, p.health, room.exit_door.locked])
		await get_tree().create_timer(2.4).timeout
		if game.state == game.State.UPGRADE:
			print("   prize: an upgrade to pick")
			game._pick_upgrade(0)
		room.exit_door.use(p)
		await get_tree().create_timer(1.2).timeout
		print("   back out: in_event=%s, %.1fm from the door" % [p.in_event, p.global_position.distance_to(d.global_position)])
	FpsPlayer.god_mode = false
	get_tree().quit()


func _play_nest(room: MgNest) -> void:
	room.gun.use(p)
	print("   mounted=%s" % (p.mount == room.gun))
	if render:
		await get_tree().create_timer(9.0).timeout
		room.gun.yaw = 0.05
		room.gun.pitch = -0.02
		await _shot("nest_0")
		if "--quick" in OS.get_cmdline_user_args():
			room._finish()
	var t := 0.0
	var shot_saved := false
	while not room.done and t < 140.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		# aim at the nearest living runner, lead it a little, hold the trigger
		var best: Clown = null
		var bd := INF
		for e: Clown in room.enemies:
			if is_instance_valid(e) and not e.dead:
				var dd := e.global_position.distance_to(p.global_position)
				if dd < bd:
					bd = dd
					best = e
		if best and not room.gun.overheated:
			var at := best.global_position + Vector3.UP * 1.1 + best.velocity * 0.1
			var to := at - room.gun._pivot.global_position
			var base := room.gun.global_basis.get_euler().y
			room.gun.yaw = clampf(wrapf(atan2(-to.x, -to.z) - base, -PI, PI), -MountedGun.TRAVERSE, MountedGun.TRAVERSE)
			room.gun.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), MountedGun.ELEVATION.x, MountedGun.ELEVATION.y)
			room.gun.trigger()
		if render and not shot_saved and room.kills >= 6:
			shot_saved = true
			await _shot("nest_firing")
	print("   nest: %.0fs, %d killed, %d breached, gun heat %.2f" % [t, room.kills, room._breached, room.gun.heat])
	await _frames(30)
	room.gun.use(p)
	print("   ripped off: weapon=%d ammo=%d" % [p.weapon, p.ammo[FpsPlayer.MAXIM]])
	await _frames(40)
	await _shot("maxim_carried")


func _play_room(room: EventRoom, kind: String) -> void:
	var t := 0.0
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.SHOTGUN if kind == "clown_car" else FpsPlayer.PISTOL]
	var cd := 0.0
	var saved := 0
	if kind == "meat_locker":
		# walk in among them
		for f in 120:
			p.global_position += Vector3(0, 0, -0.06).rotated(Vector3.UP, room.global_rotation.y)
			await get_tree().physics_frame
	if render:
		if kind == "high_wire":
			p.camera.look_at(room.to_global(Vector3(0, HighWire.H, 0)))
		await _shot("%s_0" % kind)
	while not room.done and t < 60.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		cd -= 1.0 / 60.0
		if cd > 0.0:
			continue
		var target: Clown = null
		for e: Clown in room.enemies:
			if is_instance_valid(e) and not e.dead:
				target = e
				break
		if target == null:
			continue
		cd = 0.5 if kind == "high_wire" else 0.35
		var aim: Vector3 = target.ragdoll.bones[&"Chest"].global_position
		p.camera.look_at(aim)
		var sid := randi()
		for i in w.pellets:
			var spread := Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), randf_range(-0.03, 0.03)) if w.pellets > 1 else Vector3.ZERO
			p.shoot_ray(p.camera.global_position, ((aim - p.camera.global_position).normalized() + spread).normalized(), w, sid)
		if render and saved < 2 and room.kills >= (1 if saved == 0 else 3):
			await _frames(25 if kind == "high_wire" else 8)
			await _shot("%s_%d" % [kind, saved + 1])
			saved += 1
	print("   %s: %.0fs" % [kind, t])
	for e: Clown in room.enemies:
		if is_instance_valid(e) and not e.dead:
			var b := e.get_node_or_null("Brain")
			print("   still alive: %.1fm away, downed=%s crawling=%s hunting=%s brain_on=%s" % [e.global_position.distance_to(p.global_position), e.downed, e.crawling, b.hunting if b else "-", b.process_mode != Node.PROCESS_MODE_DISABLED if b else "-"])
