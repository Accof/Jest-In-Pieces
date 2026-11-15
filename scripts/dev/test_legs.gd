extends Node
## Knee shots and broken legs. Pass --render for /tmp/legs_*.png.
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/legs_%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	await get_tree().physics_frame
	var p: FpsPlayer = room.player
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	var cam := Camera3D.new()
	room.add_child(cam)
	# 1. pistol round to the knee of a standing clown
	var c: Clown = room.clowns[1]
	var sk := c.skeleton
	var knee: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftLowerLeg")).origin
	var from := p.camera.global_position
	var aim_at := knee + Vector3.DOWN * 0.05
	var hit := p.shoot_ray(from, (aim_at - from).normalized(), w, 1)
	print("knee ray hit ", hit.get("collider").name if not hit.is_empty() else "nothing", " at %.2fm from the knee" % (hit.position.distance_to(knee) if not hit.is_empty() else -1.0))
	print("knee shot: broken=%s downed=%s dead=%s health=%.0f" % [c.broken_leg, c.downed, c.dead, c.health])
	cam.global_position = c.global_position + Vector3(0.5, 1.7, 2.1)
	cam.look_at(c.global_position + Vector3.UP * 0.3)
	cam.make_current()
	await _frames(20)
	await _shot("0_falling")
	await _frames(70)
	await _shot("1_writhing")
	var t := 0.0
	var went_up := -1.0
	var kneel_saved := false
	while t < 8.0:
		await _frames(1)
		t += 1.0 / 60.0
		if c._down_stage == 1 and not kneel_saved and c._down_t > 0.6:
			kneel_saved = true
			cam.global_position = c.global_position + Vector3(1.8, 1.0, 1.6)
			cam.look_at(c.global_position + Vector3.UP * 0.6)
			await _shot("2_kneeling")
		if not c.downed and went_up < 0.0:
			went_up = t
	print("got back up after %.1fs: downed=%s broken_leg=%s" % [went_up + 1.5, c.downed, c.broken_leg])
	# 2. limping: walk it forward by hand and look
	c.walk_amount = 1.0
	for k in 3:
		for f in 12:
			c.velocity = c.global_basis.z * 1.1
			c.global_position += c.velocity / 60.0
			await _frames(1)
		cam.global_position = c.global_position + c.global_basis.x * 2.4 + Vector3.UP * 1.0
		cam.look_at(c.global_position + Vector3.UP * 0.9)
		await _shot("3_limp_%d" % k)
	c.velocity = Vector3.ZERO
	# 3. shot again while limping: dies, with the knee bent wrong
	var chest: Vector3 = c.ragdoll.bones[&"Chest"].global_position
	for i in 4:
		p.shoot_ray(p.camera.global_position, (chest - p.camera.global_position).normalized(), w, 10 + i)
	await _frames(150)
	var lo: PhysicalBone3D = c.ragdoll.bones[&"LeftLowerLeg"]
	var up: PhysicalBone3D = c.ragdoll.bones[&"LeftUpperLeg"]
	print("killed while limping: dead=%s; broken knee angle %.0f deg" % [c.dead, rad_to_deg(up.global_basis.y.angle_to(lo.global_basis.y))])
	# 4. shotgun to the legs of five clowns: how many lose the leg, how many break it
	var sg: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.SHOTGUN]
	var lost := 0
	var broke := 0
	var others: Array = room.clowns.filter(func(o): return o != c)
	for o: Clown in others:
		var thigh: Vector3 = o.skeleton.global_transform * o.skeleton.get_bone_global_pose(o.skeleton.find_bone("RightLowerLeg")).origin
		var sid: int = 500 + others.find(o)
		for k in 9:
			if not o.ragdoll.bones.has(&"RightLowerLeg"):
				break
			o.hit({collider = o.ragdoll.bones[&"RightLowerLeg"], position = thigh, direction = Vector3(0, 0, -1), damage = 16.0, impulse = 16.0, heavy = true, can_dismember = true, shot_id = sid})
		if (o.gore.hidden_mask >> ClownGore.SEGMENTS.find(&"RightLowerLeg")) & 1 == 1:
			lost += 1
		elif o.broken_leg != "":
			broke += 1
	print("shotgun to the shin x%d: %d legs blown off, %d broken" % [others.size(), lost, broke])
	if render:
		await _frames(30)
		cam.global_position = Vector3(0, 1.8, -1.2)
		cam.look_at(Vector3(0, 0.3, -4.8))
		await _shot("4_shotgun_legs")
	get_tree().quit()
