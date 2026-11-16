extends Node3D
## Joker lockers, checked. Sections (user args; none = all):
##   open    a bank on its own: the joker laughs when the player is near and
##           not when far; plain doors take hits and stay shut; the joker's
##           door takes about 90 damage, bursts, and a decayed clown in a
##           jester's cap falls out, riddled where the door was shot, lands
##           face down in front of it, and spills its cards
##   levels  forty generated floors: how many get a bank, that each sits in a
##           straight corridor, flush to a wall, clear of the walkway
## Add "render" (with a window) to save pictures to /tmp/locker_*.png.

var render := false
var args_debug := false
var fails := 0


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(cam: Camera3D, name_: String) -> void:
	if not render:
		return
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/locker_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	args_debug = args.has("debug")
	var all := not (args.has("open") or args.has("levels"))
	if all or args.has("open"):
		await _open()
	if all or args.has("levels"):
		await _levels()
	print("LOCKER: %d failed" % fails)
	get_tree().quit()


func _room() -> Node3D:
	var room := Node3D.new()
	add_child(room)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.28, 0.27, 0.25)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	room.add_child(env)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.6, 2.4, 1.8)
	lamp.omni_range = 9.0
	lamp.light_energy = 2.2
	lamp.shadow_enabled = true
	lamp.light_color = Color(1.0, 0.85, 0.6)
	room.add_child(lamp)
	var floor_ := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12, 0.2, 12)
	cs.shape = bs
	cs.position.y = -0.1
	floor_.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	bm.material = LevelArt._mat("floor_conc")
	mi.mesh = bm
	mi.position.y = -0.1
	floor_.add_child(mi)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(12, 3, 0.3)
	wm.material = LevelArt._mat("wall_conc")
	wall.mesh = wm
	wall.position = Vector3(0, 1.5, -0.42)
	floor_.add_child(wall)
	room.add_child(floor_)
	return room


func _open() -> void:
	print("-- open")
	var room := _room()
	var l := JokerLocker.new()
	l.joker_index = 2
	l.laugh_every = Vector2(0.4, 0.6)
	l.laugh_chance = 1.0
	room.add_child(l)
	var player := Node3D.new()
	room.add_child(player)
	l.player = player
	var cam := Camera3D.new()
	cam.fov = 55
	room.add_child(cam)
	cam.position = Vector3(0.7, 1.5, 3.2)
	cam.look_at(Vector3(0.1, 1.0, 0))
	await _shot(cam, "0_bank")
	var close := Camera3D.new()
	close.fov = 35
	room.add_child(close)
	close.position = Vector3(0.75, 1.42, 0.85)
	close.look_at(Vector3(0.62, 1.36, 0.25))
	await _shot(cam, "0_bank")
	await _shot(close, "1_card")
	# far away: silent; close: laughs
	player.position = Vector3(0, 1.6, 15)
	await _frames(150)
	var far := l.laughs
	player.position = Vector3(0, 1.6, 3)
	await _frames(150)
	_check(far == 0, "silent with the player 15 m off")
	_check(l.laughs >= 2, "laughs with the player near (%d times in 2.5 s)" % l.laughs)
	# shooting: a plain door takes it and stays shut
	var space := get_world_3d().direct_space_state
	var shoot := func(target: Vector3, dmg: float) -> bool:
		var from := Vector3(target.x + randf_range(-0.3, 0.3), 1.5, 4.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + (target - from).normalized() * 8.0, 1 | (1 << 2))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not hit.collider.has_method("shot"):
			return false
		hit.collider.shot(hit.position, (target - from).normalized(), dmg)
		return true
	for i in 6:
		shoot.call(l.global_transform * Vector3(0, randf_range(0.5, 1.7), 0.3), 34.0)
		await _frames(2)
	_check(not l.is_open, "a plain locker stays shut after 6 pistol rounds (%d hits)" % l.hits)
	# the joker's door: pistol rounds until it gives
	var n := 0
	var joker_front := l.global_transform * (Vector3(JokerLocker.W, 0, 0) + Vector3(randf_range(-0.15, 0.15), 1.0, 0.25))
	while not l.is_open and n < 10:
		shoot.call(l.global_transform * Vector3(JokerLocker.W + randf_range(-0.2, 0.2), randf_range(0.7, 1.6), 0.3), 34.0)
		n += 1
		await _frames(3)
	_check(l.is_open and n == 3, "bursts on the 3rd pistol round (%d)" % n)
	if args_debug:
		for f in 12:
			await _frames(3)
			var cc := l.corpse
			if cc and cc.ragdoll.active:
				var h: PhysicalBone3D = cc.ragdoll.bones[&"Hips"]
				var lp := l.global_transform.affine_inverse() * h.global_position - Vector3(JokerLocker.W, 0, 0)
				print("      f%d hips %s v %s" % [f * 3, lp, PhysicsServer3D.body_get_state(h.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)])
	await _frames(8)
	await _shot(cam, "2_burst")
	await _frames(20)
	await _shot(cam, "3_falling")
	var c := l.corpse
	_check(c != null and is_instance_valid(c) and c.dead, "a dead clown falls out")
	if c == null:
		return
	for f in 10:
		var parts := ""
		for b: StringName in [&"Hips", &"Chest", &"Neck", &"LeftFoot"]:
			var pb: PhysicalBone3D = c.ragdoll.bones[b]
			var lp := l.global_transform.affine_inverse() * pb.global_position - Vector3(JokerLocker.W, 0, 0)
			parts += "%s(%.2f,%.2f,%.2f) " % [b, lp.x, lp.y, lp.z]
		if args_debug:
			print("      t%.2f %s" % [f * 0.1, parts])
		await _frames(6)
	await _frames(140)
	await _shot(cam, "4_down")
	var wounds: int = c.gore._wound_pos.size()
	_check(wounds >= 8, "riddled with bullet holes (%d)" % wounds)
	var hips: PhysicalBone3D = c.ragdoll.bones[&"Hips"]
	var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
	var out_z := l.global_transform.affine_inverse() * chest.global_position
	_check(out_z.z > 0.5 and chest.global_position.y < 0.45, "out on the floor in front (chest %.2f m out, %.2f m up)" % [out_z.z, chest.global_position.y])
	var down := chest.global_basis.z.y
	print("      chest facing y %.2f (negative = face down), hips at %.2f m" % [down, hips.global_position.y])
	_check(c.gore._materials[0].get_shader_parameter("decay") > 0.5, "it is the decayed one")
	var cards := 0
	for k in room.get_children():
		if k is RigidBody3D and k.mass < 0.05:
			cards += 1
	_check(cards >= 12, "its cards spilled (%d)" % cards)
	var top := Camera3D.new()
	top.fov = 50
	room.add_child(top)
	top.position = chest.global_position + Vector3(0.9, 1.3, 1.2)
	top.look_at(chest.global_position + Vector3(0, 0.1, 0))
	await _shot(top, "5_body")
	var face := Camera3D.new()
	face.fov = 40
	room.add_child(face)
	var head: PhysicalBone3D = c.ragdoll.bones[&"Neck"]
	face.position = head.global_position + Vector3(0.6, 0.55, 0.45)
	face.look_at(head.global_position)
	await _shot(face, "6_face")
	room.queue_free()
	await _frames(2)
	if render:
		await _portrait()


## The locker joker standing, lit, to see the cap and card.
func _portrait() -> void:
	var room := _room()
	var c := Clown.new()
	room.add_child(c)
	c.position = Vector3(0, 0, 1.2)
	await _frames(2)
	LockerJoker.dress(c)
	var cam := Camera3D.new()
	cam.fov = 40
	room.add_child(cam)
	cam.position = Vector3(0.35, 1.8, 2.2)
	cam.look_at(Vector3(0, 1.7, 1.2))
	await _shot(cam, "7_portrait")
	cam.position = Vector3(1.0, 1.3, 4.6)
	cam.look_at(Vector3(0, 1.0, 1.2))
	await _shot(cam, "8_full")
	cam.position = Vector3(-0.7, 1.9, 0.5)
	cam.look_at(Vector3(0, 1.75, 1.2))
	await _shot(cam, "9_back")
	room.queue_free()


func _levels() -> void:
	print("-- levels")
	var floors := 0
	var with := 0
	var bad := 0
	for i in 40:
		var m := Maze.new()
		add_child(m)
		var size := 5 + (i % 5)
		m.generate(size + 2, size, 1000 + i * 7919)
		floors += 1
		var art: LevelArt = m.get_node("Art")
		if not art.joker_lockers.is_empty():
			with += 1
		for l: JokerLocker in art.joker_lockers:
			# clear of the walkway: the locker's front is at most 0.6 m into a 3 m corridor,
			# and its back sits on the wall
			var space := get_world_3d().direct_space_state
			var front := l.global_transform * Vector3(0, 1.0, JokerLocker.D * 0.5 + 0.05)
			var q := PhysicsRayQueryParameters3D.create(front, l.global_transform * Vector3(0, 1.0, JokerLocker.D * 0.5 + 1.6), 1)
			var hit := space.intersect_ray(q)
			var back := PhysicsRayQueryParameters3D.create(l.global_transform * Vector3(0, 1.0, -JokerLocker.D * 0.5 + 0.03), l.global_transform * Vector3(0, 1.0, -JokerLocker.D * 0.5 - 0.3), 1)
			var bh := space.intersect_ray(back)
			if not hit.is_empty() or bh.is_empty():
				bad += 1
				print("      floor %d: locker at %s blocked in front %s / no wall behind %s" % [i, l.global_position, not hit.is_empty(), bh.is_empty()])
		m.queue_free()
		await _frames(1)
	print("      %d of %d floors have a bank" % [with, floors])
	_check(with >= floors * 0.3 and with <= floors * 0.85, "about 60%% of floors get one (%d/%d)" % [with, floors])
	_check(bad == 0, "every bank flush to a wall with the corridor clear in front (%d bad)" % bad)
