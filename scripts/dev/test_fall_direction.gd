extends Node3D
## Which way a man goes over when shot (24 Nov 2026, Andrew: the rifleman
## "falls forward most times ... I prefer if he were to slump back"). Lines
## up riflemen in their aim and in the cover crouch, and clubmen, shoots each
## in the head or the chest from the front, and after four seconds reads
## where the head lies against the feet along the way he faced: behind is
## "back", ahead "forward". Prints the shares and checks the rifleman goes
## back more often than not.
##   godot --headless --fixed-fps 60 --path . res://scenes/test_fall_direction.tscn

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("   %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	var floor_ := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 0.2, 200)
	cs.shape = bs
	floor_.add_child(cs)
	floor_.position.y = -0.1
	floor_.collision_layer = 1
	add_child(floor_)
	await _run()


func _run() -> void:
	print("-- fall direction")
	for kind: String in ["rifle aim, head", "rifle aim, chest", "rifle crouch, head", "rifle walking, head", "club, head"]:
		seed(1917)
		var res := await _batch(kind, 24)
		print("      %-22s back %2d  forward %2d  side %2d" % [kind, res.back, res.forward, res.side])
		if kind.begins_with("rifle"):
			_check(res.back > res.forward, "%s: more go back than forward (%d v %d)" % [kind, res.back, res.forward])
		else:
			_check(res.back + res.forward + res.side == 24, "%s: all accounted for" % kind)
	print("FALL: %d failed" % fails)
	get_tree().quit()


func _batch(kind: String, n: int) -> Dictionary:
	var men: Array[Clown] = []
	for i in n:
		var c := Clown.new()
		c.body = "witzsoldat" if kind.begins_with("rifle") else "clown"
		add_child(c)
		c.global_position = Vector3(-30.0 + 2.6 * i, 0, 0)
		c.rotation.y = 0.0
		if kind.begins_with("rifle"):
			c.give_rifle()
		else:
			c.give_club()
		c.always_pose = true
		c.set_process(true)
		men.append(c)
	await _frames(10)
	for c in men:
		c.walk_amount = 1.0 if kind.begins_with("rifle walking") else 0.0
		c.drive_phase = kind.begins_with("rifle walking")
		if kind.begins_with("rifle crouch"):
			c.aim_amount = 0.3
			c.crouch_amount = 1.0
		elif kind.begins_with("rifle"):
			c.aim_amount = 1.0 if not kind.begins_with("rifle walking") else 0.0
		c.aim_point = c.global_position + c.global_basis.z * 8.0 + Vector3.UP * 1.3
	await _frames(70)
	var faces: Array[Vector3] = []
	var feet: Array[Vector3] = []
	for c in men:
		faces.append(c.global_basis.z.normalized())
		feet.append(c.global_position)
		var bone := &"Neck" if kind.ends_with("head") else &"Chest"
		var pb: PhysicalBone3D = c.ragdoll.bones[bone]
		var vel := c.global_basis.z * (1.6 if kind.begins_with("rifle walking") else 0.0)
		c.velocity = vel
		c.hit({collider = pb, position = pb.global_position + c.global_basis.z * 0.1, direction = -c.global_basis.z, damage = 300.0,
			impulse = 4.0, heavy = false, can_dismember = false, shot_id = 9})
	await _frames(240)
	var res := {back = 0, forward = 0, side = 0}
	for i in men.size():
		var c := men[i]
		var head: Vector3 = (c.ragdoll.bones[&"Neck"] as PhysicalBone3D).global_position
		var hips: Vector3 = (c.ragdoll.bones[&"Hips"] as PhysicalBone3D).global_position
		var d := head - hips
		d.y = 0.0
		var along := d.dot(faces[i])
		if d.length() < 0.25:
			res.side += 1
		elif along < -0.15:
			res.back += 1
		elif along > 0.15:
			res.forward += 1
		else:
			res.side += 1
		c.queue_free()
	await _frames(5)
	return res
