extends Node
## Headless check of explosive drums: grades of gore by distance, bodies thrown,
## a clown torn in half that crawls and then dies. Pass --render to save images.
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _shot(name: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/blast_%s.png" % name)
	print("saved ", name)


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	# replace the sandbox line-up with one ring of clowns at known distances
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	await get_tree().physics_frame
	var centre := Vector3(0, 0, -4.5)
	var barrel := ExplosiveBarrel.new()
	room.add_child(barrel)
	barrel.position = centre
	var dists := [0.9, 1.6, 2.3, 3.0, 3.8, 4.8, 6.0]
	var clowns: Array[Clown] = []
	for i in dists.size():
		var a := -PI * 0.5 + (i - 3) * 0.55
		var c := Clown.new()
		room.add_child(c)
		c.position = centre + Vector3(cos(a), 0, sin(a)) * dists[i]
		c.rotation.y = randf() * TAU
		if i == 2:
			c.crawl_chance = 1.0
		else:
			c.crawl_chance = 0.0
		clowns.append(c)
		room.clowns.append(c)
	var start := {}
	for c in clowns:
		start[c] = c.global_position
	room.player.position = Vector3(0, 0.05, 1.6)
	for f in 20:
		await get_tree().physics_frame
	if render:
		room.player.camera.look_at(centre + Vector3.UP * 0.6)
		await _shot("0_before")
	var hp: float = room.player.health
	barrel.shot(barrel.global_position + Vector3(0, 0.5, 0.3), Vector3(0, 0, -1), 50.0)
	for f in 6:
		await get_tree().physics_frame
	if render:
		await _shot("1_boom")
	for f in 90:
		await get_tree().physics_frame
	if render:
		await _shot("2_after")
	for i in clowns.size():
		var c := clowns[i]
		var hips: PhysicalBone3D = c.ragdoll.bones.get(&"Chest")
		var moved: float = (hips.global_position - start[c]).length() if hips else 0.0
		print("%.1fm: dead=%s crawling=%s health=%.0f limbs_off=%d head_open=%s chest moved %.1fm" % [dists[i], c.dead, c.crawling, c.health, _count_bits(c.gore.hidden_mask), c._head_open, moved])
	print("player health %.0f -> %.0f" % [hp, room.player.health])
	# the crawler: does it move, and does it die by itself?
	var cr := clowns[2]
	if cr.crawling:
		var p0 := cr.global_position
		var crawler: ClownCrawler = cr.get_node("Crawler")
		for f in 240:
			await get_tree().physics_frame
		var fastest := 0.0
		var far := 0.0
		var n_gibs := 0
		for g in room.get_children():
			if g is Gib:
				n_gibs += 1
				fastest = maxf(fastest, g.linear_velocity.length())
				far = maxf(far, g.global_position.distance_to(centre))
		print("gibs: %d, fastest still moving %.2f m/s, furthest %.1fm from the drum" % [n_gibs, fastest, far])
		print("crawler moved %.2fm in 4s, still alive=%s, decals so far=%d" % [cr.global_position.distance_to(p0), not cr.dead, Blood._decals.size()])
		if render:
			var cam := Camera3D.new()
			cam.fov = 55
			room.add_child(cam)
			cam.make_current()
			for k in 6:
				var f3 := crawler._forward()
				var side := f3.cross(Vector3.UP)
				var views := [cr.global_position + side * 1.5 + Vector3.UP * 0.55 + f3 * 0.3, cr.global_position - f3 * 1.3 - side * 0.9 + Vector3.UP * 1.1]
				cam.global_position = views[0 if k < 3 else 1]
				cam.look_at(cr.global_position + Vector3.UP * 0.15 + f3 * 0.25)
				await _shot("crawl_%d" % k)
				for f in 14:
					await get_tree().physics_frame
		crawler.life = crawler.t + 1.0
		for f in 120:
			await get_tree().physics_frame
		print("after its time ran out: dead=%s" % cr.dead)
	get_tree().quit()


func _count_bits(m: int) -> int:
	var n := 0
	while m:
		n += m & 1
		m >>= 1
	return n
