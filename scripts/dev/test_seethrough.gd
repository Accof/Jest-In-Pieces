extends Node
## See-through walls: every pixel is painted with how far away the drawn
## surface is, and a physics ray through the same pixel says how far the
## nearest solid thing is. Drawn further away than the solid wall means the
## wall has a hole in its picture you can see through. Walks the camera around
## every open cell. Saves the worst views to /tmp/see_*.png (and *_d.png).

var game: Node3D


func _ready() -> void:
	_run()


func _run() -> void:
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	var args := OS.get_cmdline_user_args()
	var floor_no := int(args[0]) if args.size() > 0 else 3
	game.start_run()
	game.floor_number = floor_no - 1
	game.next_floor()
	for i in 3:
		await get_tree().physics_frame
	for c: Clown in game.clowns:
		c.queue_free()
	game.player.visible = false
	game.player.view.visible = false
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.glow_enabled = false
		env.adjustment_enabled = false
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	var probe := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.flip_faces = true
	probe.mesh = quad
	probe.extra_cull_margin = 16384.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/dev/depth_probe.gdshader")
	probe.material_override = mat
	cam.add_child(probe)
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	var m: Maze = game.maze
	var vp := get_viewport()
	var size := Vector2(vp.get_visible_rect().size)
	var views := 0
	var bad_views := 0
	var worst: Array = []
	var cells_bad := {}
	for z in m.d:
		for x in m.w:
			var cell := Vector2i(x, z)
			if not m.is_open(cell):
				continue
			var cc := m.cell_center(cell)
			if x == 0:
				print("  row %d  views %d bad %d" % [z, views, bad_views])
			var spots: Array[Vector3] = [Vector3.ZERO]
			if args.has("full"):
				spots.append_array([Vector3(1.0, 0, 0), Vector3(-1.0, 0, 0), Vector3(0, 0, 1.0), Vector3(0, 0, -1.0)])
			for o: Vector3 in spots:
				var foot := cc + o
				var eye := Vector3(foot.x, m.floor_height(foot) + 1.6, foot.z)
				for k in (8 if o == Vector3.ZERO else 4):
					var yaw := k * TAU / (8.0 if o == Vector3.ZERO else 4.0)
					cam.global_position = eye
					cam.look_at(eye + Vector3(sin(yaw), -0.05, cos(yaw)))
					await get_tree().process_frame
					await get_tree().process_frame
					var img := vp.get_texture().get_image()
					views += 1
					var n := 0
					var q := PhysicsRayQueryParameters3D.new()
					q.collision_mask = 1
					for gy in range(3, int(size.y) - 3, 8):
						for gx in range(3, int(size.x) - 3, 8):
							var px := Vector2(gx + 0.5, gy + 0.5)
							var c := img.get_pixel(gx, gy)
							var drawn := (roundf(c.r * 255.0) + c.g) / 4.0
							q.from = cam.project_ray_origin(px)
							q.to = q.from + cam.project_ray_normal(px) * 40.0
							var hit := space.intersect_ray(q)
							if hit.is_empty() or (hit.collider as Node).get_parent() != m:
								continue   # props (tables, crates) are not solid boxes to look at
							var solid: float = (hit.position as Vector3).distance_to(q.from)
							if drawn > solid * 1.2 + 0.6:
								n += 1
								if bad_views < 2 and n < 6:
									var co: CollisionObject3D = hit.collider
									var sh: Shape3D = co.shape_owner_get_shape(co.shape_find_owner(hit.shape), 0)
									var sxf: Transform3D = co.global_transform * co.shape_owner_get_transform(co.shape_find_owner(hit.shape))
									print("      px %s drawn %.2f solid %.2f hit %s normal %s  shape %s at %s  top %.2f" % [px, drawn, solid, hit.position, hit.normal, sh.size if sh is BoxShape3D else sh, sxf.origin, m.top_height()])
					if n >= 3:
						if bad_views < 6:
							img.save_png("/tmp/see_%de%d_d.png" % [floor_no, bad_views])
							probe.visible = false
							await get_tree().process_frame
							await get_tree().process_frame
							vp.get_texture().get_image().save_png("/tmp/see_%de%d.png" % [floor_no, bad_views])
							probe.visible = true
							print("   early %d: %d px cell %d,%d %s yaw %d" % [bad_views, n, x, z, o, k])
						elif args.has("quick"):
							get_tree().quit()
							return
						bad_views += 1
						cells_bad[cell] = true
						worst.append([n, img, "cell %d,%d spot %s yaw %d" % [x, z, o, k], eye, yaw])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	probe.visible = false
	for i in mini(worst.size(), 10):
		print("   %3d px  %s" % [worst[i][0], worst[i][2]])
		(worst[i][1] as Image).save_png("/tmp/see_%dw%d_d.png" % [floor_no, i])
		var eye: Vector3 = worst[i][3]
		cam.global_position = eye
		cam.look_at(eye + Vector3(sin(worst[i][4]), -0.05, cos(worst[i][4])))
		await get_tree().process_frame
		await get_tree().process_frame
		vp.get_texture().get_image().save_png("/tmp/see_%dw%d.png" % [floor_no, i])
	print("SEETHROUGH floor %d (%s): %d of %d views, %d cells" % [game.floor_number, m.theme, bad_views, views, cells_bad.size()])
	get_tree().quit()
