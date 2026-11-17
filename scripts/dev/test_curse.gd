extends Node
## Carnival Curse, checked. Sections (user args; none = all):
##   charge    on a real floor: player kills charge it to READY at 10 and stop
##             there; friendly-fire kills, curse kills and repeated deaths do
##             not count; the HUD says so
##   aim       charged: no target / a wall / a corpse / an immune enemy under
##             the crosshair: nothing thrown, nothing spent; one head in the
##             air at a time; a head that hits a wall or runs out of time
##             keeps the charge; a target dead before it lands keeps it
##   play      on a real floor, through the player: aim, Q, the head flies,
##             the execution, the charge spent, the AI stopped, the other
##             clowns carrying on, the player free to move
##   bodies    the execution on a clown, a WitzSoldat, a Rattlejack (no Death
##             Rattle), a Zornhauptmann (no Last Defiance) and a
##             Klappersoldat (oil and sparks, no blood): the phases in order,
##             each arm broken in turn and kept, the neck, the stillness, the
##             ragdoll from the broken pose without a snap, stable after
##   walls     next to a wall, under a low ceiling: nothing in or through it
##   repeat    ten in a row: nothing left behind
## Add "render" (with a window) for frames in /tmp/cc_*.png.

var render := false
var fails := 0
var game: Node3D


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/cc_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["charge", "aim", "play", "bodies", "walls", "edges", "repeat"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("CURSE: %d failed" % fails)
	get_tree().quit()


func _floor() -> void:
	for n in get_children():
		if n.name == "Room":
			n.queue_free()
	if game == null:
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
	seed(4242)
	game.rng.seed = 4242
	game.start_run()
	game.floor_number = 2
	game.next_floor()
	await get_tree().physics_frame


func _kill(c: Clown, extra := {}) -> void:
	var pb: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
	var info := {collider = pb, position = pb.global_position, direction = -c.global_basis.z, damage = 500.0, impulse = 10.0, weapon = "Pistol", shot_id = randi()}
	info.merge(extra, true)
	c.hit(info)


func _charge() -> void:
	print("-- charge")
	await _floor()
	var p: FpsPlayer = game.player
	var cc := p.curse
	_check(cc != null and cc.kills == 0 and cc.charges == 0, "a new run starts empty")
	var living: Array = game.clowns.filter(func(c: Clown) -> bool: return not c.dead)
	while living.size() < 14:
		var c := game._spawn_clown(false, false) as Clown
		c.global_position = game.maze.cell_center(game.maze.start_cell) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		living.append(c)
	await get_tree().physics_frame
	for i in 5:
		_kill(living[i])
	await get_tree().physics_frame
	_check(cc.kills == 5 and cc._label.text.contains("5/10"), "five kills: 5/10 (%s)" % cc._label.text)
	# not the player's: a Rattlejack's dying burst, a dying officer's last shot
	_kill(living[5], {friendly = true, weapon = "Lewis Gun"})
	_kill(living[6], {friendly = true, weapon = "Pistol"})
	await get_tree().physics_frame
	_check(cc.kills == 5, "kills by someone else do not count (%d)" % cc.kills)
	# the same death reported twice; a corpse shot again
	cc.on_kill(living[0])
	_kill(living[1])
	await get_tree().physics_frame
	_check(cc.kills == 5, "the same body never counts twice (%d)" % cc.kills)
	for i in range(7, 11):
		_kill(living[i])
	await get_tree().physics_frame
	_check(cc.kills == 9 and cc.charges == 0 and cc._label.text.contains("9/10"), "nine: 9/10 (%s)" % cc._label.text)
	_kill(living[11])
	await get_tree().physics_frame
	_check(cc.charges == 1 and cc._label.text.contains("READY") and cc._label.text.contains("[Q]"), "ten: READY, with the key (%s)" % cc._label.text)
	_kill(living[12])
	_kill(living[13])
	await get_tree().physics_frame
	_check(cc.charges == 1 and cc.kills == 0, "full: more kills do not stack (%d charge, %d kills)" % [cc.charges, cc.kills])
	# a curse kill does not charge it again
	cc.charges = 0
	cc.kills = 0
	var v := game._spawn_clown(true, false) as Clown
	v.global_position = game.maze.cell_center(game.maze.start_cell) + Vector3(0.5, 0, 0.5)
	await get_tree().physics_frame
	v.begin_curse({}, v.global_position + Vector3.UP * 1.3, -v.global_basis.z)
	await get_tree().physics_frame
	_check(cc.kills == 0, "a Carnival Curse kill does not count towards the next (%d)" % cc.kills)


## Point the player's view at a world point.
func _look(p: FpsPlayer, at: Vector3) -> void:
	var flat := Vector3(at.x - p.global_position.x, 0, at.z - p.global_position.z)
	p.rotation = Vector3(0, atan2(-flat.x, -flat.z), 0)
	var cam := p.camera.global_position
	p.camera.rotation.x = atan2(at.y - cam.y, flat.length())


func _sandbox() -> Node3D:
	if game:
		game.queue_free()
		game = null
		await get_tree().process_frame
	for n in get_children():
		if n.name == "Room":
			n.queue_free()
	await get_tree().process_frame
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	room.name = "Room"
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	await get_tree().physics_frame
	return room


func _player(room: Node3D) -> FpsPlayer:
	for n in room.find_children("*", "FpsPlayer", true, false):
		return n
	return null


func _make(room: Node3D, kind: String, at: Vector3) -> Clown:
	var c: Clown
	match kind:
		"rattlejack":
			c = Rattlejack.new()
		"zornhauptmann":
			c = Zornhauptmann.new()
		"klappersoldat":
			c = Klappersoldat.new()
		_:
			c = Clown.new()
			if kind == "witzsoldat":
				c.body = "witzsoldat"
	room.add_child(c)
	c.position = at
	match kind:
		"witzsoldat", "rattlejack":
			c.give_rifle()
		"zornhauptmann":
			(c as Zornhauptmann).give_officer_kit()
		"clown":
			c.give_gun()
	return c


func _aim() -> void:
	print("-- aim")
	var room := await _sandbox()
	var p := _player(room)
	var cc := p.curse
	p.global_position = Vector3(0, 0, 2.0)
	var c := _make(room, "witzsoldat", Vector3(0, 0, -3))
	c.rotation.y = 0.0
	for i in 8:
		await get_tree().physics_frame
	cc.charges = 0
	_look(p, c.global_position + Vector3.UP * 1.3)
	await get_tree().process_frame
	_check(not cc.activate() and cc.projectile == null, "not charged: nothing")
	cc.charges = 1
	# at the floor in front of him: no target
	_look(p, p.global_position + Vector3(0, 0, -2.0))
	await get_tree().process_frame
	_check(not cc.activate() and cc.charges == 1 and cc.shots == 0, "nothing under the crosshair: nothing thrown, nothing spent")
	# an immune one
	_look(p, c.global_position + Vector3.UP * 1.3)
	c.curse_immune = true
	await get_tree().process_frame
	_check(cc.aim_target == null and cc.aim_block == "immune", "an immune enemy is not a target (crosshair shows it)")
	_check(not cc.activate() and cc.charges == 1 and cc.shots == 0, "immune: nothing thrown, nothing spent")
	c.curse_immune = false
	await get_tree().process_frame
	_check(cc.aim_target == c, "a living enemy under the crosshair is a target")
	# thrown; a second one while it is in the air
	_check(cc.activate() and cc.projectile != null, "Q throws the head")
	_check(not cc.activate() and cc.shots == 1, "one head in the air at a time")
	# a wall drops in front of him while it flies
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4, 3, 0.3)
	cs.shape = bx
	wall.add_child(cs)
	room.add_child(wall)
	wall.global_position = Vector3(0, 1.5, -1.0)
	var t := 0.0
	while is_instance_valid(cc.projectile) and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(cc.last_result == "wall" and cc.charges == 1 and not c.dead, "hits a wall: it shatters there, the charge is kept (%s)" % cc.last_result)
	wall.queue_free()
	await get_tree().physics_frame
	# the target goes before it lands: dies to something else
	_look(p, c.global_position + Vector3.UP * 1.3)
	await get_tree().process_frame
	cc.activate()
	await get_tree().physics_frame
	_kill(c)
	t = 0.0
	while is_instance_valid(cc.projectile) and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(cc.charges == 1 and not c.executing, "the target died before it landed: the charge is kept (%s)" % cc.last_result)
	# a corpse under the crosshair is not a target
	await get_tree().physics_frame
	_look(p, c.ragdoll.bones[&"Chest"].global_position)
	await get_tree().process_frame
	_check(cc.aim_target == null and not cc.activate() and cc.charges == 1, "a body on the floor is not a target")
	# out of time: a live one, and it ducks away (moved off far) as it flies
	var c2 := _make(room, "clown", Vector3(1.0, 0, -6))
	for i in 6:
		await get_tree().physics_frame
	_look(p, c2.global_position + Vector3.UP * 1.3)
	await get_tree().process_frame
	cc.activate()
	await get_tree().physics_frame
	c2.global_position = Vector3(40, 0, 40)
	t = 0.0
	while is_instance_valid(cc.projectile) and t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(cc.charges == 1 and not c2.dead, "it misses (runs out of time): the charge is kept (%s)" % cc.last_result)
	c2.queue_free()
	await get_tree().physics_frame


func _play() -> void:
	print("-- play")
	await _floor()
	var p: FpsPlayer = game.player
	var cc := p.curse
	# two clowns in the open ahead: one to curse, one to carry on
	var m: Maze = game.maze
	var spot := Vector3.INF
	for cell: Vector2i in m.cells_far_from(m.start_cell, 1):
		var at := m.cell_center(cell)
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.5, at + Vector3.UP * 1.3, 1)
		var d := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length()
		if get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty() and d > 4.0 and d < 9.0:
			spot = at
			break
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await get_tree().physics_frame
	var a: Clown = game._spawn_clown(true, false)
	a.global_position = spot
	var b: Clown = game._spawn_clown(false, false)
	b.global_position = spot + Vector3(0.8, 0, 0.8)
	game.remaining = 2
	for i in 6:
		await get_tree().physics_frame
	p.god_mode = true
	cc.charges = 1
	_look(p, a.ragdoll.bones[&"Chest"].global_position)
	await get_tree().process_frame
	await get_tree().process_frame
	var deaths := [0]
	a.died.connect(func(_c: Clown) -> void: deaths[0] += 1)
	var ab := a.get_node("Brain") as ClownBrain
	var bb := b.get_node("Brain") as ClownBrain
	bb.alert(p.global_position)
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	p._unhandled_input(key)
	_check(cc.projectile != null, "pressing Q throws the head (%s)" % ("aiming at him" if cc.aim_target == a else "no target"))
	var t := 0.0
	var b_moved := 0.0
	var b0 := b.global_position
	var p0 := p.global_position
	while t < 3.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	b_moved = b.global_position.distance_to(b0)
	print("      result %s; target dead %s, executed %s, deaths %d; charge %d; other clown moved %.2f m; remaining %d" % [cc.last_result, a.dead, cc.executions, deaths[0], cc.charges, b_moved, game.remaining])
	_check(cc.last_result == "executed" and cc.executions == 1 and cc.charges == 0, "it lands: the execution, the charge spent")
	_check(deaths[0] == 1, "counted once (%d)" % deaths[0])
	_check(not ab.is_physics_processing(), "his brain has stopped")
	_check(b_moved > 0.3 and not b.dead, "the other clown carries on (%.2f m)" % b_moved)
	# the player can move all the while
	_check(not p.cinematic, "no cinematic: the player keeps the controls")


## One execution in the sandbox; returns the measurements.
## The odd cases: one arm already off; a drum going off beside him mid-curse;
## the body freed mid-curse; on a stair step.
func _edges() -> void:
	print("-- edges")
	var room := await _sandbox()
	# one arm gone: the other still breaks, the neck still goes, he still falls
	Blood.clear()
	var c := _make(room, "witzsoldat", Vector3(0, 0, -3))
	for i in 12:
		await get_tree().physics_frame
	c.gore.sever(&"LeftUpperArm", Vector3(-2, 1, 0))
	await _frames(2)
	_check(c.begin_curse({}, c.global_position + Vector3.UP * 1.3, -c.global_basis.z), "one-armed: the curse takes him")
	var m := c.get_node_or_null("Marionette") as Marionette
	var t := 0.0
	while is_instance_valid(m) and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var info: Dictionary = c.get_meta(&"curse", {})
	print("      one arm: hand-over at %.2f s, %d cracks" % [info.get("handover_at", -1.0), info.get("cracks", -1)])
	_check(info.get("handover_at", -1.0) > 2.0 and c.ragdoll.active and not c.executing, "one-armed: the whole execution, then the ragdoll")
	_check(info.get("cracks", 0) == 2, "one-armed: a crack for the arm he has and the neck, none for the missing one")
	c.queue_free()
	await _frames(2)
	# an explosion mid-curse cuts him loose at once
	c = _make(room, "clown", Vector3(0, 0, -3))
	for i in 12:
		await get_tree().physics_frame
	c.begin_curse({}, c.global_position + Vector3.UP * 1.3, -c.global_basis.z)
	await _frames(60)
	c.caught_in_blast(c.global_position + Vector3(1.2, 0.3, 0), 4.0)
	await _frames(3)
	print("      blast at 1.0 s: ragdoll %s, executing %s, marionette %s" % [c.ragdoll.active, c.executing, c.get_node_or_null("Marionette") != null])
	_check(c.ragdoll.active and not c.executing, "a blast mid-curse hands him to the ragdoll at once")
	await _frames(60)
	_check(get_tree().get_nodes_in_group(&"curse_vfx").is_empty(), "nothing of the curse lingers after the blast")
	c.queue_free()
	await _frames(2)
	# freed mid-curse (floor change, despawn): nothing left behind, no errors
	c = _make(room, "rattlejack", Vector3(0, 0, -3))
	for i in 12:
		await get_tree().physics_frame
	c.begin_curse({}, c.global_position + Vector3.UP * 1.3, -c.global_basis.z)
	await _frames(70)
	c.queue_free()
	await _frames(40)                                   # the impact dust lives 1.4 s on its own
	_check(get_tree().get_nodes_in_group(&"curse_vfx").is_empty(), "freed mid-curse: the strings and light go with him")


func _one(room: Node3D, kind: String, at: Vector3, name_ := "") -> Dictionary:
	Blood.clear()
	var c := _make(room, kind, at)
	for i in 12:
		await get_tree().physics_frame
	var deaths := [0]
	c.died.connect(func(_x: Clown) -> void: deaths[0] += 1)
	var sk := c.skeleton
	var hips0 := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin).y - at.y
	var ok := c.begin_curse({}, c.global_position + Vector3.UP * 1.3 + c.global_basis.z * 0.12, -c.global_basis.z)
	var m := c.get_node_or_null("Marionette") as Marionette
	var out := {accepted = ok, dead = c.dead, executing = c.executing, ragdoll = c.ragdoll.active, deaths = 0}
	if m == null:
		return out
	out.order = m.arm_order.duplicate()
	var t := 0.0
	var phases: Array = []
	var hips_min_standing := 9.0
	var arm_at := {}
	var neck_at := {}
	var pause_move := 0.0
	var last := {}
	var hips_at_handover := -1.0
	var after_handover := {}
	var max_speed := 0.0
	var lowest := 9.0
	var rattle0 := (c as Rattlejack).rattle_rounds if c is Rattlejack else 0
	var shots0 := (c as Zornhauptmann).pistol_shots if c is Zornhauptmann else 0
	var frame := 0
	var watch := ["Head", "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "Chest", "LeftFoot", "RightFoot"]
	while t < 7.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		frame += 1
		var ph: String = m.phase if is_instance_valid(m) else "gone"
		if phases.is_empty() or phases[phases.size() - 1] != ph:
			phases.append(ph)
		var pts := {}
		for b: String in watch:
			var bi := sk.find_bone(b)
			pts[b] = sk.global_transform * (c.ragdoll.bone_pose(bi).origin if c.ragdoll.active else sk.get_bone_global_pose(bi).origin)
		var hips := sk.global_transform * (c.ragdoll.bone_pose(sk.find_bone("Hips")).origin if c.ragdoll.active else sk.get_bone_global_pose(sk.find_bone("Hips")).origin)
		if not c.ragdoll.active:
			hips_min_standing = minf(hips_min_standing, hips.y - at.y) if ph != "collapse" else hips_min_standing
			for side: String in ["Left", "Right"]:
				arm_at[side + "%.1f" % snappedf(t, 0.1)] = _elbow(c, side)
				arm_at["hand" + side + "%.1f" % snappedf(t, 0.1)] = _hand_local(c, side)
			neck_at["%.1f" % snappedf(t, 0.1)] = _neck(c)
			if ph == "pause" and not last.is_empty():
				for b: String in watch:
					pause_move = maxf(pause_move, (pts[b] as Vector3).distance_to(last[b]))
		elif hips_at_handover < 0.0:
			hips_at_handover = hips.y - at.y
		else:
			if m and is_instance_valid(m) and after_handover.is_empty() and t > m.handover_at + 0.35:
				after_handover = {neck = _neck(c), left = _elbow(c, "Left"), right = _elbow(c, "Right")}
			for pb: PhysicalBone3D in c.ragdoll.bones.values():
				max_speed = maxf(max_speed, pb.linear_velocity.length())
				lowest = minf(lowest, pb.global_position.y - at.y)
		last = pts
		if render and name_ != "" and frame % 4 == 0 and t < 4.0:
			await _shot("%s_%03d" % [name_, frame])
	out.deaths = deaths[0]
	out.phases = phases
	out.hips0 = hips0
	out.standing = hips_min_standing
	out.pause_move = pause_move
	var res: Dictionary = c.get_meta(&"curse", {})
	out.handover = res.get("handover_at", -1.0)
	out.hips_at_handover = hips_at_handover
	out.pose_error = res.get("pose_error", -1.0)
	out.arm_at = arm_at
	out.neck_at = neck_at
	out.after = after_handover
	out.max_speed = max_speed
	out.lowest = lowest
	out.cracks = res.get("cracks", -1)
	out.vfx_left = get_tree().get_nodes_in_group(&"curse_vfx").size()
	out.marionette_gone = not is_instance_valid(m)
	out.executing_after = c.executing
	out.rattle = ((c as Rattlejack).rattle_rounds - rattle0) if c is Rattlejack else 0
	out.defiance = (c as Zornhauptmann).defiance_outcome if c is Zornhauptmann else ""
	out.zshots = ((c as Zornhauptmann).pistol_shots - shots0) if c is Zornhauptmann else 0
	out.pools = Blood.pools().size()
	out.oil = Blood.oil_puddle_count()
	out.settled = c.ragdoll.is_settled or c.ragdoll.limp
	c.queue_free()
	await get_tree().physics_frame
	return out


## How bent an elbow is (radians between the upper arm and the forearm),
## and which way: positive is the wrong way (the forearm swung behind the
## line of the upper arm, away from the chest's front).
func _elbow(c: Clown, side: String) -> float:
	var sk := c.skeleton
	var g := func(n: String) -> Vector3:
		var bi := sk.find_bone(n)
		return sk.global_transform * (c.ragdoll.bone_pose(bi).origin if c.ragdoll.active else sk.get_bone_global_pose(bi).origin)
	var sh: Vector3 = g.call(side + "UpperArm")
	var el: Vector3 = g.call(side + "LowerArm")
	var wr: Vector3 = g.call(side + "Hand")
	return (el - sh).angle_to(wr - el)


## Where a hand is, against the chest (chest's own frame): how far an arm has
## been wrenched shows as how far this moves.
func _hand_local(c: Clown, side: String) -> Vector3:
	var sk := c.skeleton
	var bp := func(n: String) -> Transform3D:
		var bi := sk.find_bone(n)
		return sk.global_transform * (c.ragdoll.bone_pose(bi) if c.ragdoll.active else sk.get_bone_global_pose(bi))
	var chest: Transform3D = bp.call("Chest")
	return chest.affine_inverse() * (bp.call(side + "Hand") as Transform3D).origin


## How far the head is knocked over sideways against the chest (radians).
func _neck(c: Clown) -> float:
	var sk := c.skeleton
	var bp := func(n: String) -> Transform3D:
		var bi := sk.find_bone(n)
		return sk.global_transform * (c.ragdoll.bone_pose(bi) if c.ragdoll.active else sk.get_bone_global_pose(bi))
	var head: Transform3D = bp.call("Head")
	var chest: Transform3D = bp.call("Chest")
	var neck: Transform3D = bp.call("Neck")
	var up_head := (head.basis * Vector3(0, 1, 0)).normalized()
	var up_chest := (neck.origin - chest.origin).normalized()
	return up_head.angle_to(up_chest)


func _bodies() -> void:
	print("-- bodies")
	var room := await _sandbox()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(1.8, 1.5, -1.2)
	cam.look_at(Vector3(0, 1.1, -3.0))
	var kinds := ["witzsoldat", "rattlejack", "zornhauptmann", "clown", "klappersoldat"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			kinds = [a.substr(5)]
	if OS.get_cmdline_user_args().has("front"):
		cam.global_position = Vector3(0.6, 1.5, -0.6)
		cam.look_at(Vector3(0, 1.15, -3.0))
	for kind: String in kinds:
		var o := await _one(room, kind, Vector3(0, 0, -3), kind if render else "")
		if not o.accepted:
			_check(false, "%s: the curse takes him" % kind)
			continue
		var first: String = o.order[0]
		var second: String = o.order[1]
		var e1_before: float = o.arm_at.get(first + "0.4", 0.0)
		var e1_after: float = o.arm_at.get(first + "1.1", 0.0)
		var e1_late: float = o.arm_at.get(first + "2.2", 0.0)
		var e2_mid: float = o.arm_at.get(second + "1.0", 0.0)
		var e2_after: float = o.arm_at.get(second + "1.7", 0.0)
		var e2_late: float = o.arm_at.get(second + "2.2", 0.0)
		var n_before: float = o.neck_at.get("1.6", 0.0)
		var n_after: float = o.neck_at.get("2.2", 0.0)
		print("      %s: phases %s; standing hips >= %.2f (from %.2f); arm %s %.0f -> %.0f -> %.0f deg, arm %s %.0f -> %.0f -> %.0f deg; neck %.0f -> %.0f deg; still in the pause %.4f m; ragdoll at %.2f s (hips %.2f m), pose error %.3f m; after: neck %.0f deg, elbows %.0f/%.0f deg; fastest bone %.1f m/s, lowest %.2f m; %d cracks; deaths %d; pools %d, oil %d; vfx left %d" % [
			kind, str(o.phases), o.standing, o.hips0, first, rad_to_deg(e1_before), rad_to_deg(e1_after), rad_to_deg(e1_late), second, rad_to_deg(e2_mid), rad_to_deg(e2_after), rad_to_deg(e2_late),
			rad_to_deg(n_before), rad_to_deg(n_after), o.pause_move, o.handover, o.hips_at_handover, o.pose_error,
			rad_to_deg(o.after.get("neck", 0.0)), rad_to_deg(o.after.get("left", 0.0)), rad_to_deg(o.after.get("right", 0.0)), o.max_speed, o.lowest, o.cracks, o.deaths, o.pools, o.oil, o.vfx_left]
		)
		_check(o.dead and o.executing and not o.ragdoll and o.deaths == 1, "%s: dead and counted at once, still standing, not a ragdoll" % kind)
		_check(o.phases.slice(0, 6) == ["seizure", "arm1", "arm2", "neck", "pause", "collapse"], "%s: the phases in order" % kind)
		_check(o.standing > o.hips0 - 0.12, "%s: on his feet until the collapse (hips %.2f of %.2f)" % [kind, o.standing, o.hips0])
		var h1a: Vector3 = o.arm_at.get("hand" + first + "0.4", Vector3.ZERO)
		var h1b: Vector3 = o.arm_at.get("hand" + first + "1.1", Vector3.ZERO)
		var h1c: Vector3 = o.arm_at.get("hand" + first + "2.2", Vector3.ZERO)
		var h2a: Vector3 = o.arm_at.get("hand" + second + "1.0", Vector3.ZERO)
		var h2b: Vector3 = o.arm_at.get("hand" + second + "1.7", Vector3.ZERO)
		var h2c: Vector3 = o.arm_at.get("hand" + second + "2.2", Vector3.ZERO)
		print("        hands moved: first %.2f m (then %.3f m more), second %.2f m before its turn, %.2f m in it (then %.3f m more)" % [h1a.distance_to(h1b), h1b.distance_to(h1c), h1a.distance_to(h2a) if false else (o.arm_at.get("hand" + second + "0.4", Vector3.ZERO) as Vector3).distance_to(h2a), h2a.distance_to(h2b), h2b.distance_to(h2c)])
		_check(h1a.distance_to(h1b) > 0.3 and h1b.distance_to(h1c) < 0.06, "%s: the first arm is wrenched into its shape and stays there" % kind)
		_check(h2a.distance_to(h2b) > 0.3 and h2b.distance_to(h2c) < 0.06, "%s: then the second, and both stay" % kind)
		_check(n_after > n_before + 0.7, "%s: the neck snaps over (%.0f deg)" % [kind, rad_to_deg(n_after)])
		_check(o.pause_move < 0.004, "%s: utterly still in the pause (%.4f m)" % [kind, o.pause_move])
		_check(o.handover > 2.3 and o.handover < 3.1 and o.hips_at_handover > 0.45, "%s: the ragdoll takes him on the way down, at %.2f s" % [kind, o.handover])
		_check(o.pose_error < 0.05, "%s: no snap into the ragdoll (%.3f m)" % [kind, o.pose_error])
		_check(o.after.get("neck", 0.0) > 0.6, "%s: the ragdoll keeps the broken neck (%.0f deg)" % [kind, rad_to_deg(o.after.get("neck", 0.0))])
		_check(o.max_speed < 9.0 and o.lowest > -0.25, "%s: stable: nothing flung (%.1f m/s), nothing through the floor" % [kind, o.max_speed])
		_check(o.cracks >= 3, "%s: a crack for each arm and the neck (%d)" % [kind, o.cracks])
		_check(o.marionette_gone and o.vfx_left == 0 and not o.executing_after, "%s: everything cleaned up" % kind)
		match kind:
			"rattlejack":
				_check(o.rattle == 0, "Rattlejack: no Death Rattle, the gun silent (%d rounds)" % o.rattle)
			"zornhauptmann":
				_check(o.defiance == "" and o.zshots == 0, "Zornhauptmann: no Last Defiance, no last shot")
			"klappersoldat":
				_check(o.pools == 0, "Klappersoldat: oil, not blood (%d pools, %d oil)" % [o.pools, o.oil])
	cam.queue_free()


func _walls() -> void:
	print("-- walls")
	var room := await _sandbox()
	var worst := -9.0
	for side: float in [1.0, -1.0]:
		for gap: float in [0.35, 0.6]:
			var wall := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(0.3, 2.6, 4.0)
			cs.shape = bx
			wall.add_child(cs)
			room.add_child(wall)
			var at := Vector3(0, 0, -3)
			var face_x := at.x + side * gap
			wall.global_position = Vector3(face_x + side * 0.15, 1.3, -3)
			# and a low ceiling
			var ceil_ := StaticBody3D.new()
			var cs2 := CollisionShape3D.new()
			var bx2 := BoxShape3D.new()
			bx2.size = Vector3(4, 0.2, 4)
			cs2.shape = bx2
			ceil_.add_child(cs2)
			room.add_child(ceil_)
			ceil_.global_position = Vector3(0, 2.25, -3)
			var c := _make(room, "witzsoldat", at)
			for i in 10:
				await get_tree().physics_frame
			c.begin_curse({}, c.global_position + Vector3.UP * 1.3, -c.global_basis.z)
			var deep := -9.0
			var t := 0.0
			while t < 5.0:
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
				for pb: PhysicalBone3D in c.ragdoll.bones.values():
					deep = maxf(deep, (pb.global_position.x - face_x) * side)
				var sk := c.skeleton
				if not c.ragdoll.active:
					for b: String in ["LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm"]:
						var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
						deep = maxf(deep, (p.x - face_x) * side)
			print("      wall %.2f m to his %s, ceiling at 2.25 m: deepest %.2f m past the wall face" % [gap, "left" if side > 0 else "right", deep])
			worst = maxf(worst, deep)
			c.queue_free()
			wall.queue_free()
			ceil_.queue_free()
			await get_tree().physics_frame
	_check(worst < 0.08, "beside a wall: his arms are kept in, nothing goes in or through it (%.2f m)" % worst)


func _repeat() -> void:
	print("-- repeat")
	var room := await _sandbox()
	var before := 0
	for i in 10:
		var c := _make(room, "bare", Vector3(0, 0, -3))         # nothing to drop: dropped guns stay in the world, as always
		for f in 6:
			await get_tree().physics_frame
		c.begin_curse({}, c.global_position + Vector3.UP * 1.3, -c.global_basis.z)
		for f in 240:
			await get_tree().physics_frame
		c.queue_free()
		for f in 3:
			await get_tree().physics_frame
		if i == 1:
			before = get_tree().get_node_count()
	var after := get_tree().get_node_count()
	print("      nodes after two: %d, after ten: %d" % [before, after])
	_check(after <= before + 10 and get_tree().get_nodes_in_group(&"curse_vfx").is_empty(), "ten in a row leave nothing behind (%d -> %d nodes)" % [before, after])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
