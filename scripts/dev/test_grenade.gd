extends Node
## The stick grenade: carried, brought up and thrown with the grenade key (real
## key events), its flight, bounces and roll, the fuse, one blast, damage by
## distance and behind cover, ragdolls, the player's own guns afterwards.
##   -- --render   pictures to /tmp/gren_*.png
##   -- --fp       first-person pictures of the throw (/tmp/gren_fp_*.png)
var room: Node3D
var p: FpsPlayer
var failed := 0
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		failed += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _shot(name: String, at: Vector3 = Vector3.INF, from: Vector3 = Vector3.INF) -> void:
	if not render:
		return
	var cam: Camera3D = null
	if at != Vector3.INF:
		cam = Camera3D.new()
		room.add_child(cam)
		cam.global_position = from
		cam.look_at(at)
		cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/gren_%s.png" % name)
	if cam:
		cam.queue_free()
		p.camera.make_current()


func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = p.grenade_key
	ev.physical_keycode = p.grenade_key
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _clown(pos: Vector3) -> Clown:
	var c := Clown.new()
	room.add_child(c)
	c.global_position = pos
	room.clowns.append(c)
	return c


func _bone(c: Clown, b: StringName) -> Vector3:
	return (c.ragdoll.bones[b] as PhysicalBone3D).global_position


## A grenade put down (not thrown) at `at`, going off `fuse` seconds later.
func _drop(at: Vector3, fuse: float) -> Grenade:
	var g := Grenade.throw(room, "frag", at, Vector3.ZERO, Vector3.ZERO)
	g.fuse_left = fuse
	return g


func _run() -> void:
	room = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	p = room.player
	FpsPlayer.god_mode = true
	await _frames(5)
	if "--boom" in OS.get_cmdline_user_args():
		render = true
		p.camera.rotation.x = -0.15
		_drop(p.global_position + Vector3(0.3, 0.05, -5.0), 0.3)
		var n0 := Explosion.detonations
		while Explosion.detonations == n0:
			await get_tree().physics_frame
		for st: Array in [[0.05, "b1"], [0.35, "b2"], [1.0, "b3"], [2.2, "b4"]]:
			var t2 := 0.0
			while t2 < float(st[0]):
				await get_tree().process_frame
				t2 += get_process_delta_time()
			await _shot(String(st[1]))
		get_tree().quit()
		return
	if "--fp" in OS.get_cmdline_user_args():
		await _fp()
		get_tree().quit()
		return

	print("== carried, brought up, thrown (key %s)" % OS.get_keycode_string(p.grenade_key))
	_check(p.grenade_count() == 3 and int(Grenade.TYPES.frag.max_carry) == 5, "starts with 3 (%d), carries up to 5" % p.grenade_count())
	_check(p.give_grenades(9) == 2 and p.grenade_count() == 5, "picking up more stops at 5 (%d)" % p.grenade_count())
	p.grenades.frag = 3
	var gun := p.weapon
	_key(true)
	await _wait(0.15)
	_check(p.view.grenade_state() == "draw", "the key down: one comes up in the right hand (%s)" % p.view.grenade_state())
	await _wait(0.4)
	_check(p.view.grenade_state() == "held" and p.grenade_count() == 3, "held while the key is down, none used yet (%s, %d)" % [p.view.grenade_state(), p.grenade_count()])
	var ammo0: int = p.ammo[p.weapon]
	p.fire()
	await _frames(2)
	_check(p.ammo[p.weapon] == ammo0, "the gun does not fire with a grenade in hand")
	var eye := p.camera.global_position
	_key(false)
	var t_rel := -1.0
	var tt := 0.0
	while p.grenades_thrown.is_empty() and tt < 1.0:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
	t_rel = tt
	_check(p.grenades_thrown.size() == 1 and p.grenade_count() == 2, "the key up: thrown (%.2f s later), one used (%d left)" % [t_rel, p.grenade_count()])
	var g: Grenade = p.grenades_thrown[0]
	var start := g.global_position
	var axis := Vector2(start.x - p.global_position.x, start.z - p.global_position.z).length()
	_check(axis > 0.36, "it leaves the hand clear of the player's body (%.2f m from its axis; the capsule is 0.3)" % axis)
	_check(p.weapon == gun, "the gun stays selected")
	# its flight: an arc, bounces, a roll, then still
	var apex := start.y
	var first_ground := Vector3.INF
	var lowest := INF
	var behind_wall := false
	var t := 0.0
	var rest_at := -1.0
	var flight: Array[Vector3] = []
	var blasts0 := Explosion.detonations
	var exploded_t := -1.0
	var bounces_seen := 0
	while t < 4.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(g) or g.state == Grenade.State.EXPLODED:
			if exploded_t < 0.0:
				exploded_t = t
			continue
		var at := g.global_position
		flight.append(at)
		apex = maxf(apex, at.y)
		lowest = minf(lowest, at.y)
		behind_wall = behind_wall or at.z < -9.25 or absf(at.x) > 6.25
		if first_ground == Vector3.INF and g.bounces > 0:
			first_ground = at
		if rest_at < 0.0 and t > 1.0 and g.linear_velocity.length() < 0.05:
			rest_at = t
		bounces_seen = g.bounces
		if int(t * 60.0) % 20 == 0:
			print("      t %.2f  pos %s  v %.2f  w %.2f  bounces %d" % [t, at, g.linear_velocity.length(), g.angular_velocity.length(), g.bounces])
	await _frames(2)
	print("      thrown from %s: apex %.2f m, first bounce at %s (%.1f m out), %d bounces, still after %.2f s" % [start, apex, first_ground, Vector2(first_ground.x - start.x, first_ground.z - start.z).length() if first_ground != Vector3.INF else -1.0, bounces_seen, rest_at])
	_check(apex > start.y + 0.25 and apex < start.y + 3.0, "an arc: up %.2f m over the throw" % (apex - start.y))
	_check(first_ground != Vector3.INF and Vector2(first_ground.x - start.x, first_ground.z - start.z).length() > 6.0, "a full throw carries (%.1f m to its first bounce)" % (Vector2(first_ground.x - start.x, first_ground.z - start.z).length() if first_ground != Vector3.INF else 0.0))
	_check(not behind_wall and lowest > -0.05, "never through the wall or the floor (lowest %.3f m)" % lowest)
	_check(rest_at > 0.0 and rest_at < 4.0, "bounces, rolls and settles before it goes off (still at %.2f s)" % rest_at)
	_check(exploded_t > 0.0 and absf((exploded_t + t_rel) - (t_rel + 4.0)) < 0.06, "goes off 4 s after leaving the hand (%.2f s)" % exploded_t)
	await _frames(30)
	_check(Explosion.detonations - blasts0 == 1 and not is_instance_valid(g), "one blast, and the grenade is gone (%d blasts)" % (Explosion.detonations - blasts0))
	_check(p.view.grenade_state() == "", "the hand is back on the gun (%s)" % p.view.grenade_state())
	await _shot("1_after", first_ground, first_ground + Vector3(1.5, 1.6, 2.5))

	print("== the underhand toss (a tap)")
	_key(true)
	await _frames(4)
	_key(false)
	tt = 0.0
	while p.grenades_thrown.size() < 2 and tt < 1.5:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
	_check(p.grenades_thrown.size() == 2 and p.grenade_count() == 1, "a tap throws one too (%d left)" % p.grenade_count())
	var g2: Grenade = p.grenades_thrown[1]
	var s2 := g2.global_position
	var land2 := Vector3.INF
	t = 0.0
	while t < 3.5 and is_instance_valid(g2):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if land2 == Vector3.INF and g2.bounces > 0:
			land2 = g2.global_position
	var d2 := Vector2(land2.x - s2.x, land2.z - s2.z).length() if land2 != Vector3.INF else -1.0
	_check(d2 > 1.5 and d2 < 5.5, "underhand: a short toss (%.1f m to its first bounce)" % d2)
	if is_instance_valid(g2):
		g2.explode()
		var n0 := Explosion.detonations
		g2.explode()                             # a second call: nothing
		_check(Explosion.detonations == n0, "a second detonation call does nothing")
	await _wait(0.6)

	print("== none left")
	p.grenades.frag = 0
	var thrown0 := p.grenades_thrown.size()
	_key(true)
	await _wait(0.5)
	_check(p.view.grenade_state() == "", "with none left the key does nothing (%s)" % p.view.grenade_state())
	_key(false)
	await _wait(0.4)
	_check(p.grenades_thrown.size() == thrown0, "and nothing is thrown")
	p.grenades.frag = 3

	print("== the guns afterwards")
	var ok_guns := true
	for w in [FpsPlayer.PISTOL, FpsPlayer.SHOTGUN, FpsPlayer.STAKE, FpsPlayer.RIFLE]:
		p.select_weapon(w)
		await _wait(0.8)
		var a0: int = p.ammo[w]
		p.fire()
		await _wait(0.5)
		var fired: bool = p.ammo[w] < a0
		print("      %s: fired %s (%d -> %d)" % [FpsPlayer.WEAPONS[w].name, fired, a0, p.ammo[w]])
		ok_guns = ok_guns and fired and p.weapon == w
	_check(ok_guns, "pistol, shotgun, crossbow and rifle still select and fire")
	p.select_weapon(FpsPlayer.PISTOL)
	await _wait(0.6)
	p.reload()
	await _wait(2.0)
	_check(p.ammo[FpsPlayer.PISTOL] == p.mag_of(FpsPlayer.PISTOL), "and reload (%d)" % p.ammo[FpsPlayer.PISTOL])

	print("== damage: by distance, behind cover, many at once")
	p.global_position = Vector3(0, 0.05, 3.5)
	var centre := Vector3(-2.0, 0.05, -3.0)
	var dists := [0.9, 1.8, 2.7, 3.6, 4.5, 6.2]
	var ring: Array[Clown] = []
	for i in dists.size():
		var a := TAU * float(i) / float(dists.size())
		var c := _clown(centre + Vector3(cos(a), 0, sin(a)) * float(dists[i]))
		ring.append(c)
	# one more 2.7 m off, behind a slab of wall
	var cover_at := Vector3(3.2, 0.05, -3.0)
	var hid := _clown(cover_at + Vector3(2.7, 0, 0))
	var slab := StaticBody3D.new()
	var scs := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(0.3, 2.4, 1.6)
	scs.shape = sb
	slab.add_child(scs)
	var smi := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = sb.size
	smi.mesh = sbm
	slab.add_child(smi)
	room.add_child(slab)
	slab.global_position = cover_at + Vector3(1.3, 1.2, 0)
	var open := _clown(cover_at + Vector3(0, 0, 2.7))           # the same distance, nothing between
	await _frames(15)
	var starts := {}
	for c in ring + [hid, open]:
		starts[c] = _bone(c, &"Hips")
	var hp0 := p.health
	FpsPlayer.god_mode = false
	_drop(centre + Vector3.UP * 0.05, 0.3)
	_drop(cover_at + Vector3.UP * 0.05, 0.3)
	await _wait(0.45)
	var peak := 0.0
	for i in 150:
		await get_tree().physics_frame
		for c in ring + [hid, open]:
			if c.dead and c.ragdoll.active:
				for pb: PhysicalBone3D in c.ragdoll.bones.values():
					peak = maxf(peak, pb.linear_velocity.length())
	FpsPlayer.god_mode = true
	var lost: Array[float] = []
	for i in ring.size():
		var c := ring[i]
		var l := c.max_health - maxf(c.health, 0.0) if not c.dead else c.max_health
		lost.append(l)
		print("      %.1f m: %s, health %.0f" % [dists[i], "dead" if c.dead else "alive", c.health])
	_check(ring[0].dead and ring[1].dead, "dead close in (0.9 m and 1.8 m)")
	_check(not ring[4].dead and not ring[5].dead, "alive further out (4.5 m, 6.2 m)")
	var falling := true
	for i in range(1, ring.size()):
		falling = falling and lost[i] <= lost[i - 1] + 0.01
	_check(falling and lost[5] == 0.0 and lost[4] > 0.0, "the damage falls off with distance (lost %s)" % [lost.map(func(x: float) -> int: return int(x))])
	var lost_open := open.max_health - maxf(open.health, 0.0) if not open.dead else open.max_health
	var lost_hid := hid.max_health - maxf(hid.health, 0.0) if not hid.dead else hid.max_health
	print("      2.7 m in the open: %s %.0f;  2.7 m behind the wall: %s %.0f" % ["dead" if open.dead else "alive", open.health, "dead" if hid.dead else "alive", hid.health])
	_check(lost_hid < lost_open * 0.5, "a wall between takes most of it (%.0f lost behind it, %.0f in the open)" % [lost_hid, lost_open])
	var far := 0.0
	for c in ring + [hid, open]:
		if c.dead:
			far = maxf(far, Vector2(_bone(c, &"Hips").x - starts[c].x, _bone(c, &"Hips").z - starts[c].z).length())
	_check(peak < 14.0 and far < 5.0, "the dead are thrown, not launched (fastest bone %.1f m/s, furthest %.1f m)" % [peak, far])
	var calm := true
	for c in ring + [hid, open]:
		if c.dead:
			for pb: PhysicalBone3D in c.ragdoll.bones.values():
				calm = calm and pb.linear_velocity.length() < 1.5 and is_finite(pb.global_position.x)
	_check(calm, "and settle (every bone of every corpse slow again 2.5 s later)")
	var gibs := false
	for c in ring:
		gibs = gibs or c.gore.hidden_mask != 0
	_check(gibs, "the closest come apart (limbs off)")
	_check(p.health == hp0, "the player 7 m away is not hurt (%.0f -> %.0f)" % [hp0, p.health])
	await _shot("2_ring", centre, centre + Vector3(3.5, 3.0, 5.0))
	# the player's own grenade at their feet
	FpsPlayer.god_mode = false
	p.health = p.stats.max_health
	var hp1 := p.health
	_drop(p.global_position + Vector3(1.2, 0.05, 0), 0.2)
	await _wait(0.5)
	FpsPlayer.god_mode = true
	_check(p.health < hp1 and p.health > 0.0, "a grenade at your own feet hurts you too (%.0f -> %.0f)" % [hp1, p.health])
	p.health = p.stats.max_health

	print("GRENADE: %d failed" % failed)
	get_tree().quit()


## First-person pictures: held, wound up, let go, following through, and the HUD.
func _fp() -> void:
	render = true
	p.camera.rotation.x = -0.05
	await _wait(0.6)
	await _shot("fp_0_gun")
	_key(true)
	await _wait(0.12)
	await _shot("fp_1_drawing")
	await _wait(0.5)
	await _shot("fp_2_held")
	_key(false)
	# (the shots themselves take two frames each: the times are when each is taken)
	var t := 0.0
	for st: Array in [[0.06, "3_wind"], [0.16, "4_wound"], [0.24, "5_forward"], [0.3, "6_release"], [0.4, "7_follow"], [0.55, "8_away"], [0.85, "9_back"]]:
		while t < float(st[0]):
			await get_tree().process_frame
			t += get_process_delta_time()
		await _shot("fp_" + String(st[1]))
		t += 2.0 / 60.0
	await _wait(1.0)
	await _shot("fp_10_flying")
	var n0 := Explosion.detonations
	while Explosion.detonations == n0:
		await get_tree().physics_frame
	for st: Array in [[0.03, "11_flash"], [0.25, "12_burst"], [0.9, "13_smoke"], [2.5, "14_drifting"], [5.0, "15_clearing"]]:
		var t2 := 0.0
		while t2 < float(st[0]):
			await get_tree().process_frame
			t2 += get_process_delta_time()
		await _shot("fp_" + String(st[1]))
		t2 += 2.0 / 60.0
	print("FP done")
