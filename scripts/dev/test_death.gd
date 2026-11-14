extends Node
## Headless check of the death reactions: prints a timeline of pelvis height,
## head position and speed for a headshot, a body shot and a shotgun blast.

func _ready() -> void:
	_run()

func _run() -> void:
	var scene: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(scene)
	for i in 5:
		await get_tree().physics_frame
	var player: FpsPlayer = scene.player
	var cases := [
		["HEADSHOT (pistol)", 0, Vector3(0, 1.74, 0), 1],
		["BODY SHOT (pistol x4)", 0, Vector3(0, 1.35, 0), 4],
		["SHOTGUN to chest", 1, Vector3(0, 1.35, 0), 1],
		["SHOTGUN to left thigh", 1, Vector3(0.1, 0.75, 0), 1],
		["SHOTGUN to head", 1, Vector3(0, 1.74, 0), 1],
		["SHOTGUN to right forearm", 1, Vector3(-0.27, 1.0, 0), 1],
	]
	for ci in cases.size():
		var c: Clown = scene.clowns[ci]
		var target: Vector3 = c.global_position + cases[ci][2]
		var from := target + Vector3(0.0, 0.25, 3.0)
		var w: Dictionary = FpsPlayer.WEAPONS[cases[ci][1]]
		print("\n== ", cases[ci][0], " ==")
		var start_hips: Vector3 = c.ragdoll.bones[&"Hips"].global_position
		for s in cases[ci][3]:
			for p in w.pellets:
				var d := (target - from).normalized()
				if w.pellets > 1:
					d = (d + Vector3(randfn(0, 0.008), randfn(0, 0.008), 0)).normalized()
				player.shoot_ray(from, d, w, 100 + ci * 10 + s)
			await get_tree().physics_frame
		print("dead=", c.dead, " health=", snappedf(c.health, 0.1), " hidden_mask=", c.gore.hidden_mask)
		var peak := 0.0
		for f in 420:
			await get_tree().physics_frame
			var hips: PhysicalBone3D = c.ragdoll.bones.get(&"Hips")
			var head: PhysicalBone3D = c.ragdoll.bones.get(&"Neck")
			var v: Vector3 = PhysicsServer3D.body_get_state(hips.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			peak = max(peak, v.length())
			if f in [2, 8, 15, 24, 36, 48, 60, 75, 90, 110, 130, 160, 200, 260, 330, 419]:
				var hp := hips.global_position - start_hips
				print("t=%.2f  pelvis y=%.2f drift=%.2f  speed=%.2f  head y=%s  limp=%s settled=%s" % [f / 60.0, hips.global_position.y, Vector2(hp.x, hp.z).length(), v.length(),
					("%.2f" % head.global_position.y) if head else "gone", c.ragdoll.limp, c.ragdoll.is_settled])
		print("peak pelvis speed %.2f m/s, gibs=%d" % [peak, scene.get_children().filter(func(n): return n is Gib).size()])
	var blood: Node = get_node("/root/Blood")
	print("\npools=", blood._pools.size(), " decals=", blood._decals.filter(func(d): return d.visible).size())
	# freeze keeps the pose
	var c0: Clown = scene.clowns[0]
	var hb: PhysicalBone3D = c0.ragdoll.bones[&"Neck"]
	var before: Vector3 = (hb.global_transform * hb.body_offset.affine_inverse()).origin
	c0.ragdoll.freeze()
	await get_tree().physics_frame
	await get_tree().process_frame
	var after: Vector3 = (c0.skeleton.global_transform * c0.skeleton.get_bone_global_pose(c0.skeleton.find_bone("Neck"))).origin
	print("freeze head moved by ", snappedf(before.distance_to(after), 0.001), " m; frozen head height ", snappedf(after.y, 0.01), " active=", c0.ragdoll.active)
	get_tree().quit()
