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
	for kind in ["mg_nest", "shooting_gallery", "card_game", "high_wire", "clown_car", "meat_locker"]:
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
			"shooting_gallery": await _play_gallery(room)
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
	var cd_l := 0.0
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
		var lazy := "--lazy" in OS.get_cmdline_user_args()
		if lazy and int(t * 60) % 300 == 0:
			print("   t=%.0f in_trench=%d leave_ok=%s queue=%d alive=%d running=%s" % [room._t, room._in_trench, room.gun.leave_ok, room._queue.size(), room.enemies.filter(func(e: Clown) -> bool: return is_instance_valid(e) and not e.dead).size(), room._running])
		if lazy and room._in_trench < 4 and p.mount:
			continue
		if lazy and p.mount:
			p._use()
			print("   let go: mount=%s weapon=%d" % [p.mount, p.weapon])
			p.select_weapon(FpsPlayer.SHOTGUN)
		if lazy:
			cd_l -= 1.0 / 60.0
			if best and cd_l <= 0.0:
				cd_l = 0.85
				var sw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.SHOTGUN]
				var aim2 := best.global_position + Vector3.UP * 1.2
				p.look_at(Vector3(aim2.x, p.global_position.y, aim2.z))
				for k in 9:
					var sp := Vector3(randfn(0, 0.04), randfn(0, 0.04), randfn(0, 0.04))
					p.shoot_ray(p.camera.global_position, ((aim2 - p.camera.global_position).normalized() + sp).normalized(), sw, 90000 + int(t * 100) * 10 + k)
			continue
		if best and not room.gun.overheated:
			var at := best.global_position + Vector3.UP * 1.1 + best.velocity * 0.1
			var to := at - p.camera.global_position
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


func _play_gallery(room: ShootingGallery) -> void:
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	var t := 0.0
	var cd := 0.0
	var saved := 0
	while not room.done and t < 60.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		cd -= 1.0 / 60.0
		if cd > 0.0:
			continue
		var aim := Vector3.INF
		for s: Array in room._soldiers:
			var c: Clown = s[0]
			if is_instance_valid(c) and not c.dead and c.crouch_amount < 0.3:
				aim = c.ragdoll.bones[&"Neck"].global_position + Vector3.UP * 0.05
		if aim == Vector3.INF:
			for tg: GalleryTarget in room._targets:
				if tg.state == 2 and tg.kind != "civilian":
					aim = tg.to_global(Vector3(0, GalleryTarget.H * 0.78, 0))
					break
		if aim == Vector3.INF:
			continue
		cd = 0.3
		p.camera.look_at(aim)
		p.shoot_ray(p.camera.global_position, (aim - p.camera.global_position).normalized(), w, randi())
		if render and saved == 0 and t > 8.0:
			saved = 1
			await _shot("shooting_gallery_1")
	print("   gallery: score %d, soldier kills %d" % [room.score, room.kills])


func _play_room(room: EventRoom, kind: String) -> void:
	var t := 0.0
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.SHOTGUN if kind == "clown_car" else FpsPlayer.PISTOL]
	var cd := 0.0
	var saved := 0
	var shots_since_kill := 0
	var last_kills := 0
	if kind == "high_wire" and "--fall_log" in OS.get_cmdline_user_args():
		_log_falls(room)
	if kind == "meat_locker":
		# walk in among them
		for f in 120:
			p.global_position += Vector3(0, 0, -0.06).rotated(Vector3.UP, room.global_rotation.y)
			await get_tree().physics_frame
	if render and kind == "card_game":
		p.camera.look_at(room.to_global(Vector3(0, 0.9, -2.5)))
		await _shot("card_game_seated")
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
		# a hanging body in the way: side-step, like a player would
		shots_since_kill += 1
		if room.kills != last_kills:
			last_kills = room.kills
			shots_since_kill = 0
		if shots_since_kill > 8:
			shots_since_kill = 0
			p.global_position += p.global_basis.x * randf_range(-0.8, 0.8)
		# in the meat locker the hanging bodies get in the way: go for the head
		var aim: Vector3 = target.ragdoll.bones[&"Neck" if kind == "meat_locker" else &"Chest"].global_position
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


## Follow the first body off the wire: height and fall speed of the hips.
func _log_falls(room: EventRoom) -> void:
	var c: Clown = null
	while c == null:
		await get_tree().physics_frame
		for e: Clown in room.enemies:
			if is_instance_valid(e) and e.dead and e.ragdoll and e.global_position.y > room.global_position.y + 8.0:
				c = e
	var hips: PhysicalBone3D = c.ragdoll.bones[&"Hips"]
	var t := 0.0
	var y0 := hips.global_position.y
	while t < 2.6:
		var v := hips.linear_velocity
		print("   fall t=%.2f y=%.2f vy=%.1f  (free fall would be %.1f)" % [t, hips.global_position.y - room.global_position.y, v.y, -9.8 * t])
		for k in 6:
			await get_tree().physics_frame
		t += 0.1
