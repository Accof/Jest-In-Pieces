extends Node
## Films a WitzSoldat in the bright sandbox: a walk cycle and a side-step
## from the side, carry and aim from the front, and three deaths a couple of
## seconds after. Saves /tmp/sa_*.png (needs a window) and prints joint angles.

var room: Node3D
var cam: Camera3D
var s: Clown
var vel := Vector3.ZERO
var moving := false


func _ready() -> void:
	_run()


func _physics_process(delta: float) -> void:
	if s and moving and is_instance_valid(s) and not s.dead:
		s.velocity = vel
		s.global_position += vel * delta


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/sa_%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _soldier(at: Vector3) -> Clown:
	var c := Clown.new()
	c.body = "witzsoldat"
	room.add_child(c)
	c.global_position = at
	c.give_rifle()
	c.always_pose = true
	c.set_process(true)
	return c


func _angles(c: Clown) -> String:
	var sk := c.skeleton
	var out := []
	for side: String in ["Left", "Right"]:
		var h := sk.get_bone_global_pose(sk.find_bone(side + "UpperLeg")).origin
		var k := sk.get_bone_global_pose(sk.find_bone(side + "LowerLeg")).origin
		var f := sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
		var thigh := (k - h).normalized()
		var hip_ang := rad_to_deg(atan2(thigh.z, -thigh.y))
		var knee_ang := rad_to_deg((k - h).angle_to(f - k))
		out.append("%s hip %+.0f knee %.0f" % [side[0], hip_ang, knee_ang])
		var sh := sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
		var el := sk.get_bone_global_pose(sk.find_bone(side + "LowerArm")).origin
		var wr := sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
		out.append("%s elbow %.0f" % [side[0], rad_to_deg((el - sh).angle_to(wr - el))])
	return ", ".join(out)


func _run() -> void:
	room = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	for n in room.get_children():
		if n is ExplosiveBarrel:
			n.queue_free()
	room.clowns.clear()
	var p: FpsPlayer = room.player
	p.view.visible = false
	cam = Camera3D.new()
	room.add_child(cam)
	cam.make_current()
	cam.fov = 50.0
	s = _soldier(Vector3(-3, 0, -4))
	s.rotation.y = PI * 0.5                    # facing +x
	# 1. walking across the room, filmed from the side
	vel = Vector3(1.4, 0, 0)
	s.walk_amount = 1.0
	moving = true
	await _frames(40)
	for i in 6:
		cam.global_position = s.global_position + Vector3(0, 1.0, 4.2)
		cam.look_at(s.global_position + Vector3.UP * 0.9)
		await _shot("walk_%d" % i)
		cam.global_position = s.global_position + Vector3(0, 0.3, 1.6)
		cam.look_at(s.global_position + Vector3.UP * 0.25)
		await _shot("feet_%d" % i)
		print("walk %d: %s" % [i, _angles(s)])
		await _frames(6)
	# 2. the walk the brain actually asks for while side-stepping: 0.42 of
	#    move speed, walk_amount set from speed the way the brain does
	s.global_position = Vector3(-1, 0, -4)
	s.rotation.y = 0.0                         # facing +z (toward the camera side), moving sideways
	vel = Vector3(1.26, 0, 0)
	s.walk_amount = clampf(1.26 / 3.0, 0.0, 1.0)
	await _frames(40)
	for i in 3:
		cam.global_position = s.global_position + Vector3(0, 1.0, 4.2)
		cam.look_at(s.global_position + Vector3.UP * 0.9)
		await _shot("strafe_%d" % i)
		print("strafe %d (walk_amount %.2f): %s" % [i, s.walk_amount, _angles(s)])
		await _frames(8)
	moving = false
	s.velocity = Vector3.ZERO
	s.walk_amount = 0.0
	# 3. standing, from the front and three-quarters: carry, then aim
	s.global_position = Vector3(0, 0, -4)
	s.rotation.y = 0.0
	await _frames(30)
	cam.global_position = s.global_position + Vector3(0, 1.3, 3.0)
	cam.look_at(s.global_position + Vector3.UP * 1.1)
	await _shot("carry_front")
	print("carry: %s" % _angles(s))
	cam.global_position = s.global_position + Vector3(2.2, 1.3, 2.2)
	cam.look_at(s.global_position + Vector3.UP * 1.1)
	await _shot("carry_34")
	s.aim_amount = 1.0
	s.aim_point = s.global_position + Vector3(0, 1.3, 8)
	await _frames(30)
	await _shot("aim_34")
	print("aim: %s" % _angles(s))
	cam.global_position = s.global_position + Vector3(0, 1.3, 3.0)
	cam.look_at(s.global_position + Vector3.UP * 1.1)
	await _shot("aim_front")
	cam.global_position = s.global_position + Vector3(-2.6, 1.4, 0.4)
	cam.look_at(s.global_position + Vector3(0, 1.35, 0.3))
	await _shot("aim_side")
	cam.global_position = s.global_position + Vector3(0, 0.3, 1.6)
	cam.look_at(s.global_position + Vector3.UP * 0.25)
	await _shot("feet_stand")
	# 3a. firing: the shot (kick, flash), then the bolt worked, from the side
	cam.global_position = s.global_position + Vector3(-2.2, 1.45, 1.2)
	cam.look_at(s.global_position + Vector3(0, 1.3, 0.4))
	s.fired()
	var fire_times := [0.0, 0.03, 0.08, 0.2, 0.45, 0.6, 0.75, 0.85, 1.0, 1.25, 1.45]
	var waited := 0.0
	for i in fire_times.size():
		var dt: float = fire_times[i] - waited
		await _frames(int(round(dt * 60.0)))
		waited = fire_times[i]
		await _shot("fire_%02d" % i)
	print("bolt cycle over at %.2fs, cycling now %s" % [0.3 + s.bolt_seconds, s.cycling()])
	# 3c. stepping back with the rifle lowered, from the side
	s.aim_amount = 0.25
	s.rotation.y = -PI * 0.5                  # facing -x, backing toward +x
	vel = Vector3(0.95, 0, 0)
	s.walk_amount = 0.7
	moving = true
	await _frames(30)
	for i in 6:
		cam.global_position = s.global_position + Vector3(0, 1.0, 4.0)
		cam.look_at(s.global_position + Vector3.UP * 0.9)
		await _shot("back_%d" % i)
		print("back %d: %s" % [i, _angles(s)])
		await _frames(7)
	moving = false
	s.velocity = Vector3.ZERO
	s.walk_amount = 0.0
	s.queue_free()
	# 3b. the club carrier: walking, then swinging
	var cl := Clown.new()
	cl.body = "witzsoldat"
	room.add_child(cl)
	cl.global_position = Vector3(-3, 0, -4)
	cl.give_club()
	cl.always_pose = true
	cl.set_process(true)
	cl.rotation.y = PI * 0.5
	s = cl
	vel = Vector3(1.4, 0, 0)
	cl.walk_amount = 1.0
	moving = true
	await _frames(40)
	for i in 4:
		cam.global_position = cl.global_position + Vector3(0, 1.0, 4.2)
		cam.look_at(cl.global_position + Vector3.UP * 0.9)
		await _shot("club_walk_%d" % i)
		await _frames(8)
	moving = false
	cl.velocity = Vector3.ZERO
	cl.walk_amount = 0.0
	await _frames(20)
	cam.global_position = cl.global_position + Vector3(1.2, 1.3, 3.0)
	cam.look_at(cl.global_position + Vector3.UP * 1.1)
	for i in 6:
		cl.attack_amount = sin(float(i) / 5.0 * PI)
		await _frames(3)
		await _shot("club_swing_%d" % i)
	cl.attack_amount = 0.0
	cl.queue_free()
	# 4. deaths: chest (pistol), head (pistol), shotgun; look 2.5s later
	var dead: Array[Clown] = []
	for i in 3:
		var c := _soldier(Vector3(-2.4 + i * 2.4, 0, -4))
		c.rotation.y = 0.0
		c.aim_amount = 1.0 if i == 1 else 0.0
		c.aim_point = c.global_position + Vector3(0, 1.3, 8)
		dead.append(c)
	await _frames(30)
	var ws := [FpsPlayer.WEAPONS[0], FpsPlayer.WEAPONS[0], FpsPlayer.WEAPONS[1]]
	for i in 3:
		var c := dead[i]
		var bone: StringName = [&"Chest", &"Neck", &"Chest"][i]
		var pb: PhysicalBone3D = c.ragdoll.bones[bone]
		var w: Dictionary = ws[i]
		var hits := 9 if i == 2 else 1
		for k in hits:
			c.hit({collider = pb, position = pb.global_position + Vector3(0, 0, 0.1), direction = Vector3(0, 0, -1),
				damage = w.damage * (5.0 if i == 0 else 1.0), impulse = w.impulse, heavy = w.heavy, can_dismember = false, shot_id = 900 + i})
	await _frames(150)
	cam.global_position = Vector3(0, 3.2, -0.6)
	cam.look_at(Vector3(0, 0.1, -4.6))
	await _shot("deaths")
	for i in 3:
		var hp: Vector3 = dead[i].ragdoll.bones[&"Hips"].global_position
		cam.global_position = hp + Vector3(0.0, 2.0, 1.2)
		cam.look_at(hp)
		await _shot("dead_%d" % i)
	get_tree().quit()
