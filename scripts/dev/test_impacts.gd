extends Node3D
## Surface-aware impacts (Operation Drowned Front, Milestone 5), checked.
## Sections (user args; none = all):
##   classify  on the Front: the field is mud, a flooded shell hole is water, the
##             linings in the trench walls answer with their own material, and a
##             bunker's wall is concrete, its crates wood, its drums metal
##   bullets   the player's rounds into the world leave marks and debris; 400 in
##             one frame stay inside the budgets (decal ring, emitter pool, the
##             per-frame burst cap aggregates the rest); the next floor clears them
##   walk      a burst walked along the ground leaves its marks in order
##   enemy     a soldier's miss lands in the world and kicks up
##   blast     an explosion over water throws water, over the field throws mud
##   range     (with "render", Forward+) the material range: panels of every
##             surface shot at from one spot, /tmp/impacts_range.png and close-ups
##   godot --headless --fixed-fps 60 res://scenes/test_impacts.tscn [-- section... render]

var fails := 0
var game: Node3D
var render := false


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["classify", "bullets", "walk", "enemy", "blast", "range"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("IMPACTS: %d failed" % fails)
	get_tree().quit()


func _new_game(seed_: int, floor_: int = 3) -> void:
	if game:
		game.queue_free()
		await _frames(2)
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(1)
	seed(seed_)
	game.rng.seed = seed_
	game.start_run()
	FpsPlayer.god_mode = true
	game.floor_number = floor_ - 1
	game.next_floor()
	await _frames(3)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [game.player.get_rid()] if game and game.player else []
	return get_world_3d().direct_space_state.intersect_ray(q)


func _visible_decals() -> int:
	var n := 0
	for d: Decal in Impacts._decals:
		if d.visible:
			n += 1
	return n


func _emitting() -> int:
	var n := 0
	for p: CPUParticles3D in Impacts._emitters:
		if p.emitting:
			n += 1
	return n


# --- classify --------------------------------------------------------------------------
func _classify() -> void:
	print("-- classify")
	await _new_game(1916)
	var m := game.maze as FrontMaze
	_check(m != null, "floor 3 is the Front")
	if m == null:
		return
	var w := m.w * m.cell
	var z_mid := lerpf((m.their_row0 + TrenchMaze.GRID_D) * m.cell, m.our_row0 * m.cell, 0.5)
	# the open field, away from any hole
	var field := ""
	for i in 40:
		var p := Vector3(randf_range(4.0, w - 4.0), 0, z_mid + randf_range(-20.0, 20.0))
		var near_hole := false
		for cr: Vector4 in m.crater_list:
			if Vector2(p.x - cr.x, p.z - cr.y).length() < cr.z + 1.0:
				near_hole = true
		if near_hole:
			continue
		var h := _ray(p + Vector3.UP * 5.0, p + Vector3.DOWN * 5.0)
		if not h.is_empty():
			field = Impacts.classify(h)
			break
	_check(field == "mud", "the open field is mud (got '%s')" % field)
	# a flooded hole
	var water := ""
	for cr: Vector4 in m.crater_list:
		if cr.w < 0.7:
			continue
		var h := _ray(Vector3(cr.x, 10.0, cr.y), Vector3(cr.x, -10.0, cr.y))
		if not h.is_empty():
			water = Impacts.classify(h)
			break
	_check(water == "water", "the bottom of a flooded shell hole is water (got '%s')" % water)
	# the linings: from the middle of trench cells, out to the four walls
	var found := {}
	var cells: Array = m.open_cells.keys()
	cells.shuffle()
	for c: Vector2i in cells.slice(0, 160):
		var mid := Vector3((c.x + 0.5) * m.cell, 0, (c.y + 0.5) * m.cell)
		mid.y = m.floor_height(mid) + 0.8
		for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var h := _ray(mid, mid + d * 2.5)
			if h.is_empty():
				continue
			var s := Impacts.classify(h)
			found[s] = int(found.get(s, 0)) + 1
	var kinds := found.keys()
	kinds.sort()
	_check(found.has("wood") and found.has("sandbag") and (found.has("metal") or found.has("wattle")) and found.has("mud"),
		"the trench walls answer by their lining: %s" % str(found))
	# a bunker
	await _new_game(1916, 4)
	_check(not (game.maze is TrenchMaze), "floor 4 is a bunker")
	var bfound := {}
	var eye: Vector3 = game.player.global_position + Vector3.UP * 1.2
	for k in 48:
		var a := k * TAU / 48.0
		var h := _ray(eye, eye + Vector3(cos(a), -0.1, sin(a)) * 12.0)
		if h.is_empty():
			continue
		var s := Impacts.classify(h)
		bfound[s] = int(bfound.get(s, 0)) + 1
	_check(bfound.has("concrete"), "the bunker's walls are concrete: %s" % str(bfound))


# --- bullets ---------------------------------------------------------------------------
func _bullets() -> void:
	print("-- bullets")
	await _new_game(1916)
	var m := game.maze as FrontMaze
	var pl: FpsPlayer = game.player
	Impacts.clear()
	var before := Impacts.hits
	# one round into the ground in front of the player
	var from: Vector3 = pl.global_position + Vector3.UP * 1.6
	var dir := Vector3(0, -0.6, -1.0).normalized()
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.RIFLE]
	var hit := pl.shoot_ray(from, dir, w, 1)
	_check(not hit.is_empty() and Impacts.hits == before + 1 and _visible_decals() == 1, "a round into the world is reported (hits %d → %d), one mark" % [before, Impacts.hits])
	var used := 0
	for p: CPUParticles3D in Impacts._emitters:
		if p.global_position.distance_to(hit.position) < 0.5:
			used += 1
	_check(used >= 1, "and its debris flies (%d emitter(s) dispatched to it; it hit %s)" % [used, Impacts.classify(hit)])
	await _frames(2)
	# 400 rounds in one frame across the field: budgets hold
	var w0 := m.w * m.cell
	var zc := lerpf((m.their_row0 + TrenchMaze.GRID_D) * m.cell, m.our_row0 * m.cell, 0.5)
	var agg0: int = Impacts.aggregated
	var t0 := Time.get_ticks_usec()
	for i in 400:
		var p := Vector3(randf_range(2.0, w0 - 2.0), 30.0, zc + randf_range(-30.0, 30.0))
		var h := _ray(p, p + Vector3.DOWN * 60.0)
		if not h.is_empty():
			Impacts.bullet(h, Vector3.DOWN, w, 1.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(_visible_decals() <= Impacts.MAX_DECALS and _emitting() <= Impacts.EMITTERS and Impacts.aggregated > agg0,
		"400 rounds in a frame: %d marks (ring %d), %d emitters busy (pool %d), %d aggregated past the %d-a-frame burst cap, %.1f ms" % [_visible_decals(), Impacts.MAX_DECALS, _emitting(), Impacts.EMITTERS, Impacts.aggregated - agg0, Impacts.BURSTS_PER_FRAME, ms])
	_check(ms < 120.0, "and it cost under 120 ms headless (%.1f)" % ms)
	await _frames(3)
	# the next floor clears them
	game.next_floor()
	await _frames(3)
	_check(_visible_decals() == 0 and _emitting() == 0, "the next floor starts clean (%d marks, %d emitters)" % [_visible_decals(), _emitting()])


# --- walk ------------------------------------------------------------------------------
func _walk() -> void:
	print("-- walk")
	await _new_game(1916)
	var m := game.maze as FrontMaze
	Impacts.clear()
	var xs: Array[float] = []
	var base: Vector3 = game.player.global_position
	for i in 12:
		var p := Vector3(base.x - 5.0 + i * 0.9, base.y + 20.0, base.z - 6.0)
		var h := _ray(p, p + Vector3.DOWN * 60.0)
		if h.is_empty():
			continue
		Impacts.bullet(h, Vector3(0.3, -1.0, 0).normalized(), {name = "Maxim", damage = 60.0}, 1.6)
		await _frames(1)
	for d: Decal in Impacts._decals:
		if d.visible:
			xs.append(d.global_position.x)
	var ordered := xs.size() >= 10
	for i in range(1, xs.size()):
		if xs[i] < xs[i - 1]:
			ordered = false
	_check(ordered, "a burst walked along the field leaves %d marks in order" % xs.size())


# --- enemy -----------------------------------------------------------------------------
func _enemy() -> void:
	print("-- enemy")
	await _new_game(1916)
	var pl: FpsPlayer = game.player
	var brain: ClownBrain = null
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b is ClownBrain:
			brain = b
			break
	_check(brain != null, "a soldier with a brain")
	if brain == null:
		return
	Impacts.clear()
	var before := Impacts.hits
	var from: Vector3 = pl.global_position + Vector3(0, 1.4, -6.0)
	var to: Vector3 = pl.global_position + Vector3(0.8, 0.2, 1.5)      # past the player, into the ground
	brain._miss_lands(from, (to - from).normalized(), 30.0)
	_check(Impacts.hits == before + 1 and _visible_decals() == 1, "a soldier's miss lands and marks the ground (hits %d → %d)" % [before, Impacts.hits])


# --- blast -----------------------------------------------------------------------------
func _blast() -> void:
	print("-- blast")
	await _new_game(1916)
	var m := game.maze as FrontMaze
	var over_water := ""
	for cr: Vector4 in m.crater_list:
		if cr.w >= 0.7:
			over_water = Impacts.blast(Vector3(cr.x, m.ground_height(cr.x, cr.y) + cr.w * 0.35 + 0.5, cr.y), 2.5)
			break
	_check(over_water == "water", "a shell into a flooded hole throws water (got '%s')" % over_water)
	var w0 := m.w * m.cell
	var zc := lerpf((m.their_row0 + TrenchMaze.GRID_D) * m.cell, m.our_row0 * m.cell, 0.5)
	var over_mud := ""
	for i in 30:
		var p := Vector3(randf_range(4.0, w0 - 4.0), 0, zc + randf_range(-20.0, 20.0))
		var near_hole := false
		for cr: Vector4 in m.crater_list:
			if Vector2(p.x - cr.x, p.z - cr.y).length() < cr.z + 1.0:
				near_hole = true
		if near_hole:
			continue
		over_mud = Impacts.blast(Vector3(p.x, m.ground_height(p.x, p.z) + 0.5, p.z), 2.5)
		break
	_check(over_mud == "mud", "a shell into the field throws mud (got '%s')" % over_mud)


# --- range -----------------------------------------------------------------------------
## The material range (package D5): a row of panels, each a real collider with
## its surface, shot at from one spot with the player's rifle ray.
func _range() -> void:
	print("-- range")
	if not render:
		print("      (render only)")
		return
	if game:
		game.queue_free()
		await _frames(2)
	# a plain world: ground, light, the trench day's environment
	var env := WorldEnvironment.new()
	env.environment = TrenchArt.make_environment()
	env.camera_attributes = TrenchArt.make_camera_attributes()
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	TrenchArt.setup_sun(sun)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-50, 30, 0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var surfaces := ["mud", "earth", "wood", "concrete", "metal", "sandbag", "water"]
	var cols := {mud = Color(0.16, 0.13, 0.1), earth = Color(0.42, 0.36, 0.27), wood = Color(0.45, 0.33, 0.2), concrete = Color(0.55, 0.54, 0.5), metal = Color(0.3, 0.3, 0.32), sandbag = Color(0.4, 0.36, 0.26), water = Color(0.1, 0.12, 0.11)}
	for i in surfaces.size():
		var s: String = surfaces[i]
		var x := (i - 3) * 1.6
		var panel := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.4, 1.4, 0.2) if s != "water" else Vector3(1.4, 0.05, 1.4)
		panel.shape = bs
		panel.position = Vector3(x, 1.0, 0) if s != "water" else Vector3(x, 0.02, 0.5)
		panel.set_meta(&"surface", s)
		body.add_child(panel)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cols[s]
		mat.roughness = 0.2 if s == "water" else 0.85
		mat.metallic = 0.6 if s == "metal" else 0.0
		bm.material = mat
		mi.mesh = bm
		mi.position = panel.position
		add_child(mi)
		var lbl := Label3D.new()
		lbl.text = s
		lbl.font_size = 48
		lbl.position = Vector3(x, 2.0, 0.2)
		add_child(lbl)
	var floor_ := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(20, 0.1, 20)
	floor_.shape = fs
	floor_.position = Vector3(0, -0.05, 0)
	floor_.set_meta(&"surface", "earth")
	body.add_child(floor_)
	var fm := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = fs.size
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.3, 0.27, 0.22)
	fbm.material = fmat
	fm.mesh = fbm
	fm.position = floor_.position
	add_child(fm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6.5)
	cam.fov = 70.0
	add_child(cam)
	cam.current = true
	await _frames(20)
	# six rounds into each panel, from the camera
	var rounds := 0
	for i in surfaces.size():
		var s: String = surfaces[i]
		var x := (i - 3) * 1.6
		for k in 6:
			var target := Vector3(x + randf_range(-0.45, 0.45), 1.0 + randf_range(-0.45, 0.45), 0.1) if s != "water" else Vector3(x + randf_range(-0.45, 0.45), 0.05, 0.5 + randf_range(-0.45, 0.45))
			var from := cam.global_position
			var dir := (target - from).normalized()
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 20.0, 1)
			var h := get_world_3d().direct_space_state.intersect_ray(q)
			if h.is_empty():
				continue
			var got := Impacts.bullet(h, dir, {name = "Rifle", damage = 40.0}, 1.0)
			rounds += 1
			if k == 0:
				_check(got == s, "the %s panel answers as %s" % [s, got])
	await _frames(6)
	await _shot("impacts_range")
	for i: int in [0, 2, 3, 6]:
		var s: String = surfaces[i]
		var x := (i - 3) * 1.6
		cam.position = Vector3(x + 0.6, 1.3, 1.8) if s != "water" else Vector3(x + 0.6, 0.9, 1.9)
		cam.look_at(Vector3(x, 1.0, 0) if s != "water" else Vector3(x, 0.05, 0.5))
		for k in 3:
			var target := Vector3(x + randf_range(-0.4, 0.4), 1.0 + randf_range(-0.4, 0.4), 0.1) if s != "water" else Vector3(x + randf_range(-0.4, 0.4), 0.05, 0.5 + randf_range(-0.4, 0.4))
			var dir := (target - cam.global_position).normalized()
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * 20.0, 1)
			var h := get_world_3d().direct_space_state.intersect_ray(q)
			if not h.is_empty():
				Impacts.bullet(h, dir, {name = "Rifle", damage = 40.0}, 1.0)
		await _frames(4)
		await _shot("impacts_%s" % s)
	print("      %d rounds fired at the range" % rounds)


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/%s.png" % name_)
	print("      wrote /tmp/%s.png" % name_)
