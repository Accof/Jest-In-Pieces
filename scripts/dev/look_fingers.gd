extends Node3D
## Every enemy body's hands, open and curled round a grip: /tmp/fingers_<model>_<pose>.png
## (and the bone list, to check the finger bones came in).

const MODELS := ["clown/clown", "witzsoldat/witzsoldat", "rattlejack/rattlejack", "zornhauptmann/zornhauptmann", "klappersoldat/klappersoldat"]


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.25, 0.28)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.make_current()
	for m: String in MODELS:
		var body: Node3D = (load("res://art/%s.glb" % m) as PackedScene).instantiate()
		add_child(body)
		var sk: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
		print(m, ": ", sk.get_bone_count(), " bones; LeftIndex1 ", sk.find_bone("LeftIndex1"), " RightThumb3 ", sk.find_bone("RightThumb3"))
		for side: String in ["Left", "Right"]:
			for pose: String in ["open", "grip"]:
				ClownHands.pose(sk, side, 0.0 if pose == "open" else 1.0, 0.0 if pose == "open" else 1.0)
			ClownHands.pose(sk, side, 0.0, 0.0)
		await get_tree().process_frame
		for side: String in ["Left", "Right"]:
			var hb := sk.find_bone(side + "Hand")
			for pose: String in ["open", "grip"]:
				ClownHands.pose(sk, side, 0.0 if pose == "open" else 1.0, 0.0 if pose == "open" else 1.0)
				await get_tree().process_frame
				var hx := sk.global_transform * sk.get_bone_global_pose(hb)
				var c := hx * Vector3(0, 0.09, 0)
				var palm := hx.basis.x.normalized() * (-1.0 if side == "Left" else 1.0)
				for view: String in ["back", "side", "palm", "tips"]:
					var off: Vector3 = {"back": -palm, "side": hx.basis.z.normalized(), "palm": (palm - hx.basis.z.normalized() * 0.5).normalized(),
						"tips": (hx.basis.y.normalized() + palm * 0.4).normalized()}[view] * 0.45
					cam.global_position = c + off
					cam.look_at(c, hx.basis.y.normalized() if view != "tips" else -palm)
					await get_tree().process_frame
					await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("/tmp/fingers_%s_%s_%s_%s.png" % [m.get_file(), side, pose, view])
		body.queue_free()
		await get_tree().process_frame
	get_tree().quit()
