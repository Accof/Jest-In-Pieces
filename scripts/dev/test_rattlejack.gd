extends Node
## The Rattlejack, checked. Sections (user args; none = all):
##   model   the body, the helmet, the Lewis gun, the bones
##   fire    on a real floor: bursts at about 9 rounds a second, pauses,
##           a reload, and how hard he hits the player (god mode)
##   deaths  in the gore sandbox, each staged death several times:
##           headshot, stagger (and against a wall), Death Rattle (with
##           clowns in the line of fire), and the immediate-ragdoll fallback
## Add "render" (with a window) for frames in /tmp/rj_*.png.

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
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/rj_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var all := not (args.has("model") or args.has("fire") or args.has("deaths") or args.has("film"))
	if all or args.has("model"):
		await _model()
	if all or args.has("fire"):
		await _fire()
	if all or args.has("deaths") or args.has("film"):
		await _deaths(args)
	print("RATTLEJACK: %d failed" % fails)
	get_tree().quit()


func _sandbox() -> Node3D:
	if game:
		game.queue_free()
		game = null
		await get_tree().process_frame
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	await get_tree().physics_frame
	return room


func _model() -> void:
	print("-- model")
	var room := await _sandbox()
	var r := Rattlejack.new()
	room.add_child(r)
	r.give_rifle()
	r.position = Vector3(0, 0, -3)
	for i in 5:
		await get_tree().physics_frame
	var sk := r.skeleton
	_check(r.spec.model.ends_with("rattlejack.glb"), "wears the Rattlejack model (%s)" % r.spec.model)
	_check(sk.get_bone_count() >= 21 and sk.find_bone("LeftFoot") >= 0 and sk.find_bone("Head") >= 0, "on the shared skeleton (%d bones)" % sk.get_bone_count())
	_check(r.has_helmet, "Brodie helmet on")
	_check(r.has_rifle and r._pan != null, "Lewis gun with its pan")
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var foot := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin
	print("      head %.2f m up, ankle %.2f m; %d physical bones; health %.0f" % [head.y - r.global_position.y, foot.y - r.global_position.y, r.ragdoll.bones.size(), r.max_health])
	_check(head.y - r.global_position.y > 1.5 and foot.y - r.global_position.y < 0.25, "stands about 1.9 m with the feet on the floor")
	_check(r.max_health <= 100.0 * 1.01, "no tougher than an ordinary soldier (%.0f)" % r.max_health)
	# the helmet comes off
	var neck: PhysicalBone3D = r.ragdoll.bones[&"Neck"]
	r.knock_off_helmet(Vector3(0, 0, -1), neck.global_position)
	_check(not r.has_helmet, "the helmet can be shot off")
	r.queue_free()
	await get_tree().physics_frame


func _fire() -> void:
	print("-- fire")
	if game == null:
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
	game.start_run()
	game.floor_number = 2
	game.next_floor()
	await get_tree().physics_frame
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await get_tree().physics_frame
	var player: FpsPlayer = game.player
	player.god_mode = false
	player.health = 100000.0
	var maze: Maze = game.maze
	# a straight corridor: the player at one end, the gunner some way down it
	var start: Vector2i = maze.start_cell
	var r: Rattlejack = game.spawn_rattlejack()
	var brain := r.get_node("Brain") as ClownBrain
	var spot := Vector3.INF
	for c: Vector2i in maze.cells_far_from(start, 1):
		var p := maze.cell_center(c)
		var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.3, p + Vector3.UP * 1.3, 1)
		var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		if get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty() and d > 5.0 and d < 11.0:
			spot = p
			break
	if spot == Vector3.INF:
		spot = player.global_position + Vector3(0, 0, 6)
	r.global_position = spot
	r.look_at(Vector3(player.global_position.x, spot.y, player.global_position.z), Vector3.UP, true)
	brain.pan_rounds = 30
	brain.rounds = 30
	var health0 := player.health
	var t := 0.0
	var burst_times: Array = []
	var shots_then := 0
	var in_burst := false
	var burst_start := 0.0
	var reloaded := false
	var rates: Array = []
	while t < 16.0:
		brain.alert(player.global_position)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		player.velocity = Vector3.ZERO
		if brain._lmg_t > 0.0 and not in_burst:
			in_burst = true
			burst_start = t
			shots_then = brain.shots_fired
		elif brain._lmg_t <= 0.0 and in_burst:
			in_burst = false
			var n := brain.shots_fired - shots_then
			var dur := t - burst_start
			burst_times.append([dur, n])
			if dur > 0.3:
				rates.append(n / dur)
		if r.reload_t > 0.0:
			reloaded = true
	var dmg := health0 - player.health
	print("      %d bursts %s; %d rounds; reloaded %s; %.0f damage to the player in 16 s (%.1f a second)" % [brain.bursts, str(burst_times), brain.shots_fired, reloaded, dmg, dmg / 16.0])
	_check(brain.bursts >= 2, "fires in bursts (%d)" % brain.bursts)
	var mean := 0.0
	for x: float in rates:
		mean += x
	mean /= maxf(rates.size(), 1)
	_check(mean > 7.5 and mean < 11.0, "about 9 rounds a second in a burst (%.1f)" % mean)
	_check(reloaded, "changes the pan when it runs dry")
	_check(dmg / 16.0 < 9.0 and dmg > 0.0, "dangerous but not murderous: under 9 damage a second at range (%.1f)" % (dmg / 16.0))
	r.queue_free()
	await get_tree().physics_frame


## One staged death. Returns what was measured.
func _one(room: Node3D, kind: String, at: Vector3, zone: StringName, wall_behind := false, name_ := "") -> Dictionary:
	var r := Rattlejack.new()
	room.add_child(r)
	r.give_rifle()
	r.position = at
	var wall: StaticBody3D
	if wall_behind:
		wall = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(3, 2.5, 0.2)
		cs.shape = bx
		wall.add_child(cs)
		room.add_child(wall)
		wall.global_position = at + Vector3(0, 1.25, -0.75)
	for i in 12:
		await get_tree().physics_frame
	var deaths := [0]
	r.died.connect(func(_c: Clown) -> void: deaths[0] += 1)
	r.force_death = kind
	r.aim_amount = 1.0
	r.health = 20.0
	var front := r.global_basis.z
	var pb: PhysicalBone3D = r.ragdoll.bones[&"Neck" if zone == &"Neck" else &"Chest"]
	if render and name_ != "":
		r.aim_point = r.global_position + r.global_basis.z * 6.0 + Vector3.UP * 1.0
		for f in 20:
			r.aim_amount = 1.0
			await get_tree().process_frame
		await _shot(name_ + "_aim")
	var helmet_before := r.has_helmet
	r.hit({collider = pb, position = pb.global_position + front * 0.1 + Vector3.UP * (0.12 if zone == &"Neck" else 0.0), direction = -front, damage = 30.0, impulse = 10.0, weapon = "Pistol"})
	var out := {kind = kind, dead_at_once = r.dead, ragdoll_at_once = r.ragdoll.active, dying = r.dying, deaths = 0}
	var sk := r.skeleton
	var t := 0.0
	var hips_min_before := 9.0
	var hips_at_handover := -1.0
	var head_back := 0.0
	var chest0 := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Chest"))).basis
	var knee_angles := {"Left": [9.0, -9.0], "Right": [9.0, -9.0]}
	var ankle_angles := {"Left": [9.0, -9.0], "Right": [9.0, -9.0]}
	var hips_v_before := Vector3.ZERO
	var hips_v_after := Vector3.ZERO
	var last_hips := Vector3.ZERO
	var rounds_after := 0
	var rounds_at := 0
	var gun_hand := 0.0
	var gun_hand0 := -1.0
	var feet_through_wall := false
	var frame := 0
	var watch := ["Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Hips"]
	var last_pts: Array = []
	var move_before := 0.0
	var move_after := 0.0
	var after_frames := 0
	while t < 4.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		frame += 1
		var pts: Array = []
		for b: String in watch:
			var bi := sk.find_bone(b)
			pts.append(sk.global_transform * (r.ragdoll.bone_pose(bi).origin if r.ragdoll.active else sk.get_bone_global_pose(bi).origin))
		if not last_pts.is_empty():
			var mv := 0.0
			for k in pts.size():
				mv = maxf(mv, (pts[k] as Vector3).distance_to(last_pts[k]))
			if not r.handed_over:
				move_before = mv
			elif after_frames < 3:
				after_frames += 1
				move_after = maxf(move_after, mv)
		last_pts = pts
		var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
		if r.ragdoll.active:
			hips = r.ragdoll.bones[&"Hips"].global_position
		var hv := (hips - last_hips) / dt if last_hips != Vector3.ZERO else Vector3.ZERO
		last_hips = hips
		if not r.handed_over and not r._collapsing:
			hips_min_before = minf(hips_min_before, hips.y - at.y)
		if not r.handed_over:
			hips_v_before = hv
			# the head against the chest: how far back it snapped
			var hb := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).basis
			var cb := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Chest"))).basis
			var up_h := hb.y.normalized()
			var fwd := cb.z.normalized()
			head_back = maxf(head_back, -up_h.dot(fwd))
			for side: String in ["Left", "Right"]:
				var a := sk.get_bone_pose_rotation(sk.find_bone(side + "LowerLeg")).get_euler().x
				knee_angles[side][0] = minf(knee_angles[side][0], a)
				knee_angles[side][1] = maxf(knee_angles[side][1], a)
				var f := sk.get_bone_pose_rotation(sk.find_bone(side + "Foot")).get_euler().x
				ankle_angles[side][0] = minf(ankle_angles[side][0], f)
				ankle_angles[side][1] = maxf(ankle_angles[side][1], f)
				if wall_behind:
					var fp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
					if fp.z < wall.global_position.z + 0.1:
						feet_through_wall = true
			rounds_at = r.rattle_rounds
		elif hips_at_handover < 0.0:
			hips_at_handover = hips.y - at.y
			hips_v_after = hv
		elif kind == "rattle":
			rounds_after = r.rattle_rounds - rounds_at
			if r._rifle and is_instance_valid(r._rifle) and r._gun_hand != null and is_instance_valid(r._gun_hand):
				var hand := r.ragdoll.bones[StringName("RightHand")] as PhysicalBone3D
				var d := r._rifle.global_position.distance_to(hand.global_position)
				if gun_hand0 < 0.0:
					gun_hand0 = d
				gun_hand = maxf(gun_hand, absf(d - gun_hand0))
		if render and name_ != "" and frame % 4 == 0 and t < (2.6 if kind == "headshot" else 1.8):
			await _shot("%s_%03d" % [name_, frame])
	out.deaths = deaths[0]
	out.handover = r.handover_at
	out.pose_error = maxf(move_after - move_before, 0.0)
	out.move_before = move_before
	out.move_after = move_after
	out.hips_at_handover = hips_at_handover
	out.hips_min_before = hips_min_before
	out.head_back = head_back
	out.steps = r.steps_taken
	out.max_lean = r.max_lean
	out.foot_slip = r.foot_slip
	out.fall = r.fall_dir
	out.front = front
	out.helmet_off = helmet_before and not r.has_helmet
	out.knees = [knee_angles.Left[1] - knee_angles.Left[0], knee_angles.Right[1] - knee_angles.Right[0]]
	out.ankles = [ankle_angles.Left[1] - ankle_angles.Left[0], ankle_angles.Right[1] - ankle_angles.Right[0]]
	out.v_before = hips_v_before.length()
	out.v_after = hips_v_after.length()
	out.rattle_rounds = r.rattle_rounds
	out.rounds_after = rounds_after
	out.rattle_hits = r.rattle_hits
	out.gun_hand = gun_hand
	out.through_wall = feet_through_wall
	var xs := []
	var zs := []
	var drops := []
	var loads := []
	for e: Array in r.sway_log:
		xs.append(e[1])
		zs.append(e[2])
		drops.append(e[3])
		loads.append(e[4])
	out.sway_x = (xs.max() - xs.min()) if not xs.is_empty() else 0.0
	out.sway_z = (zs.max() - zs.min()) if not zs.is_empty() else 0.0
	out.drop_range = (drops.max() - drops.min()) if not drops.is_empty() else 0.0
	out.load_swaps = 0
	for i in range(1, loads.size()):
		if signf(loads[i]) != signf(loads[i - 1]):
			out.load_swaps += 1
	r.queue_free()
	if wall:
		wall.queue_free()
	await get_tree().physics_frame
	return out


func _deaths(args: Array) -> void:
	print("-- deaths")
	var room := await _sandbox()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(2.6, 1.4, -1.4)
	cam.look_at(Vector3(0, 0.9, -3.0))
	if args.has("film"):
		cam.global_position = Vector3(1.9, 1.25, -1.9)
		cam.look_at(Vector3(0, 0.95, -3.0))
		for k: String in ["headshot", "stagger", "rattle"]:
			await _one(room, k, Vector3(0, 0, -3), &"Neck" if k == "headshot" else &"Chest", false, "film_" + k)
		return
	# the odds of a Death Rattle on an ordinary fatal shot
	var n_rattle := 0
	for i in 300:
		var r := Rattlejack.new()
		r.death_rattle_chance = 0.3
		if randf() < r.death_rattle_chance:
			n_rattle += 1
		r.free()
	# headshots
	var falls: Array = []
	for i in 4:
		var o := await _one(room, "headshot", Vector3(0, 0, -3), &"Neck", false, "head%d" % i if i == 0 else "")
		print("      headshot %d: handover %.2fs (hips %.2f m up), head snapped back %.2f, helmet off %s, steps %d, lean %.2f, pelvis sway %.3f x %.3f m, knee drop range %.3f m, load swaps %d, knees %.2f/%.2f rad, ankles %.2f/%.2f rad, foot off its spot %.3f m, frame move %.3f -> %.3f m, hips speed %.2f -> %.2f m/s, fell %s" % [
			i, o.handover, o.hips_at_handover, o.head_back, o.helmet_off, o.steps, o.max_lean, o.sway_x, o.sway_z, o.drop_range, o.load_swaps,
			o.knees[0], o.knees[1], o.ankles[0], o.ankles[1], o.foot_slip, o.move_before, o.move_after, o.v_before, o.v_after, o.fall])
		_check(o.dead_at_once and not o.ragdoll_at_once and o.dying == "headshot", "headshot %d: dead at once, not straight to ragdoll" % i)
		_check(o.deaths == 1, "headshot %d: the kill counted exactly once (%d)" % [i, o.deaths])
		_check(o.head_back > 0.3, "headshot %d: the head snaps back (%.2f)" % [i, o.head_back])
		_check(o.handover > 0.9 and o.handover < 2.7, "headshot %d: stays up a second or two, then a slow fold (%.2fs)" % [i, o.handover])
		_check(o.hips_min_before > 0.75, "headshot %d: on his feet until the knees go (hips at least %.2f m)" % [i, o.hips_min_before])
		_check(o.hips_at_handover > 0.45, "headshot %d: the ragdoll takes over mid-fall, not on the floor (hips %.2f m)" % [i, o.hips_at_handover])
		_check(o.sway_x + o.sway_z > 0.04 and o.drop_range > 0.02, "headshot %d: the pelvis sways and drops (%.3f, %.3f)" % [i, o.sway_x + o.sway_z, o.drop_range])
		_check(o.knees[0] > 0.05 and o.knees[1] > 0.05 and o.ankles[0] > 0.03 and o.ankles[1] > 0.03, "headshot %d: knees and ankles work too" % i)
		_check(o.foot_slip < 0.03, "headshot %d: planted feet do not slide (%.3f m)" % [i, o.foot_slip])
		_check(o.pose_error < 0.06, "headshot %d: no snap into the ragdoll (%.3f m)" % [i, o.pose_error])
		_check(o.v_after > 0.2, "headshot %d: still falling as physics takes it (%.2f m/s)" % [i, o.v_after])
		falls.append(o.fall)
	var spread := 0.0
	for a: Vector3 in falls:
		for b: Vector3 in falls:
			spread = maxf(spread, a.angle_to(b))
	_check(spread > 0.8, "headshot: falls go different ways (widest apart %.0f deg)" % rad_to_deg(spread))
	# stagger, in the open and with a wall close behind
	for i in 3:
		var wall := i == 2
		var o := await _one(room, "stagger", Vector3(0, 0, -3), &"Chest", wall, "stagger%d" % i if i == 0 else "")
		print("      stagger %d%s: handover %.2fs, steps %d, hips %.2f m up, fell %s, frame moves %.3f -> %.3f m, feet through wall %s" % [i, " (wall behind)" if wall else "", o.handover, o.steps, o.hips_at_handover, o.fall, o.move_before, o.move_after, o.through_wall])
		_check(o.dead_at_once and o.dying == "stagger" and o.deaths == 1, "stagger %d: dead at once, staged, counted once" % i)
		if wall:
			_check(not o.through_wall and o.handover < 1.2, "stagger by a wall: no stepping through it, down sooner (%.2fs)" % o.handover)
		else:
			_check(o.steps >= 1 and o.handover > 0.5 and o.handover < 1.75, "stagger %d: unsteady steps back, then down (%d steps, %.2fs)" % [i, o.steps, o.handover])
			_check((o.fall as Vector3).dot(-(o.front as Vector3)) > 0.0, "stagger %d: goes over backwards-ish" % i)
		_check(o.pose_error < 0.06, "stagger %d: no snap into the ragdoll (%.3f m)" % [i, o.pose_error])
	# Death Rattle, with two clowns standing in front of the muzzle
	var hits_total := 0
	var victims_hurt := 0
	var victims_dead := 0
	for i in 2:
		var victims: Array[Clown] = []
		for k in 2:
			var v := Clown.new()
			room.add_child(v)
			v.position = Vector3(-0.15 + 0.3 * k, 0, -0.3 + 1.2 * k)
			v.rotation.y = PI
			victims.append(v)
		for f in 3:
			await get_tree().physics_frame
		var h0: Array = victims.map(func(v: Clown) -> float: return v.health)
		var o := await _one(room, "rattle", Vector3(0, 0, -3.5), &"Chest", false, "rattle%d" % i if i == 0 else "")
		print("      rattle %d: %d rounds (%d after the ragdoll took him), %d into clowns, gun drifted %.3f m from the hand, handover %.2fs" % [i, o.rattle_rounds, o.rounds_after, o.rattle_hits, o.gun_hand, o.handover])
		_check(o.dead_at_once and o.dying == "rattle" and o.deaths == 1, "rattle %d: dead at once, firing, counted once" % i)
		_check(o.handover >= 0.15 and o.handover <= 0.7, "rattle %d: ragdoll after a fraction of a second (%.2fs)" % [i, o.handover])
		_check(o.rounds_after >= 1, "rattle %d: keeps firing as the ragdoll falls (%d)" % [i, o.rounds_after])
		_check(o.gun_hand < 0.06, "rattle %d: the gun stays in the hand through the ragdoll (%.3f m)" % [i, o.gun_hand])
		hits_total += o.rattle_hits
		for k in victims.size():
			var v := victims[k]
			if is_instance_valid(v):
				if v.health < h0[k] or v.dead:
					victims_hurt += 1
				if v.dead:
					victims_dead += 1
				v.queue_free()
		await get_tree().physics_frame
	print("      rattle odds: %d of 300 kills; %d rounds into clowns, %d clowns hit, %d killed" % [n_rattle, hits_total, victims_hurt, victims_dead])
	_check(n_rattle > 60 and n_rattle < 120, "Death Rattle on about 30%% of kills (%d of 300)" % n_rattle)
	_check(victims_hurt >= 1, "Death Rattle rounds hit clowns in the way (%d)" % victims_hurt)
	# fallback: a blast is straight to ragdoll
	var r := Rattlejack.new()
	room.add_child(r)
	r.give_rifle()
	r.position = Vector3(0, 0, -3)
	for f in 8:
		await get_tree().physics_frame
	var chest: PhysicalBone3D = r.ragdoll.bones[&"Chest"]
	r.health = 5.0
	r.hit({collider = chest, position = chest.global_position, direction = Vector3(0, 0, -1), damage = 90.0, impulse = 20.0, heavy = true, can_dismember = true, shot_id = 5, weapon = "Shotgun", dist = 2.0})
	_check(r.dead and r.ragdoll.active and r.dying == "" and r.death_kind == "ragdoll", "a heavy blast goes straight to ragdoll")
	r.queue_free()
	await get_tree().physics_frame
