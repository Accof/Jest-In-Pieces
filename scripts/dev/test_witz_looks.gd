extends Node
## The WitzSoldat's two looks (the original and the dark one): that each new
## soldier gets one at random, half and half, and that the two are the same
## soldier in everything but the model.
##   godot --path . res://scenes/test_witz_looks.tscn [-- --render]
## --render also films both looks side by side (stand, walk, aim, after a fight)
## to /tmp/witz_looks_*.png. Prints "WITZ LOOKS: n failed".

var failed := 0
var game: Node3D
const VISUAL := ["model", "gibs", "helmet", "rest_min", "rest_size", "helmet_center", "helmet_size", "pbr", "share_material"]


func _check(ok: bool, what: String) -> void:
	print("   %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1


func _ready() -> void:
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.rng.seed = 1917
	game.start_run()
	await get_tree().physics_frame
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns = [] as Array[Clown]
	await get_tree().physics_frame

	print("the roll")
	var n := 20000
	var dark := 0
	for i in n:
		if Clown.pick_look("witzsoldat") == "witzsoldat_dark":
			dark += 1
	var share := float(dark) / n
	_check(absf(share - 0.5) < 0.015, "half and half over %d rolls (dark %.3f)" % [n, share])
	var runs := 0
	var longest := 0
	var last := ""
	for i in 2000:
		var l := Clown.pick_look("witzsoldat")
		runs = runs + 1 if l == last else 1
		longest = maxi(longest, runs)
		last = l
	_check(longest < 20, "each roll its own (longest run of one look in 2000: %d)" % longest)
	var others := true
	for b in ["clown", "rattlejack", "zornhauptmann", "klappersoldat"]:
		for i in 50:
			others = others and Clown.pick_look(b) == b
	_check(others, "every other body keeps its one look")

	print("twenty soldiers spawned the game's way")
	var counts := {"witzsoldat": 0, "witzsoldat_dark": 0}
	var models_ok := true
	var spawned: Array[Clown] = []
	var at: Vector3 = game.maze.cell_center(game.maze.route[1])
	for i in 20:
		var c: Clown = game._spawn_clown(true, false)
		c.global_position = at + Vector3((i % 5) * 1.2 - 2.4, 0, float(i / 5) * 1.2)
		c.process_mode = Node.PROCESS_MODE_DISABLED
		counts[c.look] = counts.get(c.look, 0) + 1
		models_ok = models_ok and c.body == "witzsoldat" and String(c.spec.model).contains("/" + c.look + "/") and c.spec.gibs.contains(c.look)
		spawned.append(c)
	print("     looks: ", counts)
	_check(counts.witzsoldat > 0 and counts.witzsoldat_dark > 0, "both looks among 20 (%d original, %d dark)" % [counts.witzsoldat, counts.witzsoldat_dark])
	_check(models_ok, "each wears its own look's model and gibs, and is still body \"witzsoldat\"")
	for c in spawned:
		c.queue_free()
	game.clowns = [] as Array[Clown]
	await get_tree().physics_frame

	print("the same soldier: one of each, made identically")
	var pair: Array[Clown] = []
	for look in ["witzsoldat", "witzsoldat_dark"]:
		game.rng.seed = 77
		seed(77)
		var c := Clown.new()
		c.max_health = 100.0 * (1.0 + 0.1 * (game.floor_number - 1))
		c.body = "witzsoldat"
		c.look = look
		game._world.add_child(c)
		c.give_rifle()
		var brain := ClownBrain.new()
		brain.maze = game.maze
		brain.player = game.player
		brain.others = game.clowns
		brain.move_speed = game.rng.randf_range(2.8, 3.5) + 0.06 * game.floor_number
		brain.run_speed = minf(game.rng.randf_range(4.9, 5.8) + 0.1 * game.floor_number, 6.8)
		brain.rifleman()
		brain.name = "Brain"
		c.add_child(brain)
		c.process_mode = Node.PROCESS_MODE_DISABLED
		pair.append(c)
	var a: Clown = pair[0]
	var b: Clown = pair[1]
	a.global_position = at + Vector3(-0.7, 0, 0)
	b.global_position = at + Vector3(0.7, 0, 0)
	await get_tree().physics_frame
	_check(_props_differ(a, b, ["look", "spec"]).is_empty(), "every setting on the soldier the same %s" % str(_props_differ(a, b, ["look", "spec"])))
	_check(_props_differ(a.get_node("Brain"), b.get_node("Brain"), []).is_empty(), "every setting on its brain the same (sight, range, speeds, rifle) %s" % str(_props_differ(a.get_node("Brain"), b.get_node("Brain"), [])))
	var spec_diff := []
	for k in a.spec.keys() + b.spec.keys():
		if not (k in VISUAL) and a.spec.get(k) != b.spec.get(k) and not (k in spec_diff):
			spec_diff.append(k)
	_check(spec_diff.is_empty(), "the body spec the same but for the look's own keys %s" % str(spec_diff))
	_check(a.health == b.health and a.max_health == b.max_health, "same health (%.0f / %.0f)" % [a.health, b.health])
	# the hitboxes: the same bones, shapes within a few centimetres
	var names_a := a.ragdoll.bones.keys()
	var names_b := b.ragdoll.bones.keys()
	names_a.sort()
	names_b.sort()
	_check(names_a == names_b, "the same %d hit bones" % names_a.size())
	# the hitboxes follow each model's own limbs (the dark soldier's sleeves hang
	# 5 cm further back in his T-pose, his forearms 2 cm longer), so the trunk and
	# head must match closely and the limbs within a hand's breadth
	var trunk_worst := 0.0
	var limb_worst := 0.0
	var size_worst := 0.0
	var report := []
	for bn in names_a:
		var pa: PhysicalBone3D = a.ragdoll.bones[bn]
		var pb: PhysicalBone3D = b.ragdoll.bones[bn]
		var d := (pa.global_position - a.global_position).distance_to(pb.global_position - b.global_position)
		report.append("%s %.1f" % [bn, d * 100])
		if String(bn) in ["Hips", "Spine", "Chest", "Neck"]:
			trunk_worst = maxf(trunk_worst, d)
		else:
			limb_worst = maxf(limb_worst, d)
		size_worst = maxf(size_worst, absf(_shape_size(pa) - _shape_size(pb)))
	print("     hitbox centres apart (cm): ", ", ".join(report))
	_check(trunk_worst < 0.03, "trunk and head hitboxes in the same places (within %.1f cm)" % (trunk_worst * 100))
	_check(limb_worst < 0.1, "limb hitboxes on each model's own limbs, close to the other's (within %.1f cm)" % (limb_worst * 100))
	_check(size_worst < 0.04, "hitboxes the same size (within %.1f cm)" % (size_worst * 100))
	# the rifle where the other's is, aimed
	for c: Clown in pair:
		c.process_mode = Node.PROCESS_MODE_INHERIT
		c.always_pose = true
		c.set_process(true)
		c.aim_amount = 1.0
		c.aim_point = c.global_position + c.global_basis.z * 8.0 + Vector3.UP * 1.3
	for f in 30:
		await get_tree().physics_frame
	var ma: Vector3 = a._muzzle.global_position - a.global_position
	var mb: Vector3 = b._muzzle.global_position - b.global_position
	print("     muzzle (aimed) %s / %s" % [ma, mb])
	_check(ma.distance_to(mb) < 0.02, "muzzle in the same place when aimed (%.1f cm apart)" % (ma.distance_to(mb) * 100))
	var grip := []
	for c: Clown in pair:
		var sk := c.skeleton
		var rh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
		var lh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin
		var r := c._rifle.global_transform
		grip.append([r.affine_inverse() * rh, r.affine_inverse() * lh])
	var gd: float = maxf((grip[0][0] as Vector3).distance_to(grip[1][0]), (grip[0][1] as Vector3).distance_to(grip[1][1]))
	print("     hands on the rifle: %s / %s" % [grip[0], grip[1]])
	_check(gd < 0.05, "hands at the same places on the rifle (within %.1f cm)" % (gd * 100))
	if "--render" in OS.get_cmdline_user_args():
		await _film(pair, "aim")
	for c: Clown in pair:
		c.aim_amount = 0.0
		c.always_pose = false
		c.process_mode = Node.PROCESS_MODE_DISABLED

	print("shot the same way")
	for c: Clown in pair:
		c.process_mode = Node.PROCESS_MODE_INHERIT
	var hp := []
	for c: Clown in pair:
		seed(5)
		var pbn: PhysicalBone3D = c.ragdoll.bones[&"Spine"]
		c.hit({collider = pbn, position = pbn.global_position + c.global_basis.z * 0.12, direction = -c.global_basis.z, damage = 30.0,
			impulse = 2.0, heavy = false, can_dismember = false, shot_id = 101})
		hp.append(c.health)
	_check(hp[0] == hp[1] and hp[0] < a.max_health, "a body shot takes the same off each (%.0f, %.0f)" % [hp[0], hp[1]])
	var helmets := []
	for c: Clown in pair:
		helmets.append(c.has_helmet)
	_check(helmets[0] and helmets[1], "both wear a helmet")
	# a heavy blast to the chest: a hole, the anatomy behind it, then an arm off
	for c: Clown in pair:
		var ch := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(&"Chest")).origin
		c.gore.blast(&"Chest", ch + c.global_basis.z * 0.13, -c.global_basis.z, 0.09)
		c.gore.sever(&"LeftLowerArm", c.global_basis.x * 2.0 + Vector3.UP)
	await get_tree().physics_frame
	for c: Clown in pair:
		_check(not c.gore._anat_mats.is_empty(), "%s: a blast opens it onto its anatomy (%d anatomy materials)" % [c.look, c.gore._anat_mats.size()])
		_check(c._segment_gone("LeftLowerArm"), "%s: the forearm comes off" % c.look)
	var gibs_ok := true
	var gib_tex := []
	for node in game._world.get_parent().get_children() + game._world.get_children():
		if node is Gib:
			var mi := (node as Gib).get_child(0) as MeshInstance3D
			if mi and mi.mesh:
				var textured := false
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
					if m and m.albedo_texture:
						textured = true
				gib_tex.append(textured)
	_check(gib_tex.size() >= 2 and not (false in gib_tex), "every gib textured (%s)" % str(gib_tex))
	# (under his own dust and mud: Clown._grime_helmet)
	var hm := b._helmet.get_surface_override_material(0) as ShaderMaterial
	_check(hm != null and hm.get_shader_parameter("use_tex") and hm.get_shader_parameter("use_mr") and hm.get_shader_parameter("use_normal") \
			and hm.get_shader_parameter("albedo_tex") == b.body_material().albedo_texture, "the dark helmet wears the body's colour, metal/roughness and normal maps")
	var sm := b.mesh.get_surface_override_material(0) as ShaderMaterial
	_check(sm.get_shader_parameter("use_mr") and sm.get_shader_parameter("use_normal"), "the dark body draws its metal/roughness and normal maps")
	var sa := a.mesh.get_surface_override_material(0) as ShaderMaterial
	_check(not sa.get_shader_parameter("use_mr") and not sa.get_shader_parameter("use_normal"), "the original body draws as before (no PBR maps switched on)")
	# then killed: a head shot, the same way
	var died := []
	for c: Clown in pair:
		var got := [false]
		c.died.connect(func(_c: Clown) -> void: got[0] = true)
		seed(9)
		var pbn: PhysicalBone3D = c.ragdoll.bones[&"Neck"]
		c.hit({collider = pbn, position = pbn.global_position + c.global_basis.z * 0.1, direction = -c.global_basis.z, damage = 200.0,
			impulse = 6.0, heavy = true, can_dismember = false, shot_id = 102})
		died.append(got)
	for f in 90:
		await get_tree().physics_frame
	for i in 2:
		var c: Clown = pair[i]
		_check(died[i][0] and c.health <= 0.0, "%s: killed by a head shot" % c.look)
		_check(c.ragdoll.active, "%s: goes over into the ragdoll" % c.look)
		_check(c.look == ["witzsoldat", "witzsoldat_dark"][i] and String(c.spec.model).contains("/" + c.look + "/"), "%s: keeps its look dead" % c.look)
	if "--render" in OS.get_cmdline_user_args():
		await _film(pair, "dead")
	print("WITZ LOOKS: %d failed" % failed)
	get_tree().quit()


func _shape_size(pb: PhysicalBone3D) -> float:
	for ch in pb.get_children():
		if ch is CollisionShape3D:
			var s: Shape3D = (ch as CollisionShape3D).shape
			if s is CapsuleShape3D:
				return (s as CapsuleShape3D).height + (s as CapsuleShape3D).radius
			if s is BoxShape3D:
				return (s as BoxShape3D).size.length()
			if s is SphereShape3D:
				return (s as SphereShape3D).radius * 2.0
	return 0.0


## Exported and script settings that differ between two nodes (skipping `skip`).
func _props_differ(x: Object, y: Object, skip: Array) -> Array:
	var out := []
	for p in x.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or p.name in skip:
			continue
		var vx = x.get(p.name)
		var vy = y.get(p.name)
		if typeof(vx) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME] and vx != vy:
			out.append("%s: %s / %s" % [p.name, vx, vy])
	return out


func _film(pair: Array[Clown], tag: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45
	var mid: Vector3 = (pair[0].global_position + pair[1].global_position) * 0.5
	var fwd: Vector3 = pair[0].global_basis.z
	for view in [["front", fwd * 3.4 + Vector3.UP * 1.3], ["side", pair[0].global_basis.x * 3.4 + fwd * 0.6 + Vector3.UP * 1.3]]:
		cam.global_position = mid + view[1]
		cam.look_at(mid + Vector3.UP * (1.0 if tag != "dead" else 0.3))
		cam.make_current()
		for f in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/witz_looks_%s_%s.png" % [tag, view[0]])
	cam.queue_free()
