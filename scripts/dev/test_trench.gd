extends Node
## The Drowned Trenches (TrenchMaze), checked. Sections (user args; none = all):
##   layouts   many seeds: every cell reachable, the trench parts all there,
##             no two trenches touching where they should not, route length,
##             trench length, build time
##   ground    the carved ground: collision matching the walked surface
##   game      in the game: floors 3, 6, 9 are trenches (2 and 4 are not),
##             overcast light there and the bunker dark back after, enemy
##             mix, the exit at the bunker door, the player walking the route
##             (duckboards, fire step) without catching or falling through
##   bodies    on a trench floor: deaths on duckboards, in water, on the
##             fire step, against a wall, a Carnival Curse: bodies settle on
##             the ground (not floating, not through it), blood pools
##   ambience  the player walks the route and wades the flooded stretch:
##             footsteps by surface (mud, duckboards, water), shells landing
##             far off (flash, boom), the music box plays near its dugout,
##             nothing of it hurts him; the dressing is all there (wire,
##             signs, clutter, the carnival things)
## Add "render" (with a window) for views in /tmp/tr_*.png; "ascii" prints a layout.

var render := false
var fails := 0


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/tr_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["layouts", "ground", "game", "bodies", "ambience", "views", "floor", "normals", "relief", "walls", "parallax", "section"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("TRENCH: %d failed" % fails)
	get_tree().quit()


func _make(seed_: int) -> TrenchMaze:
	var m := TrenchMaze.new()
	add_child(m)
	m.generate(0, 0, seed_)
	return m


func _layouts() -> void:
	print("-- layouts")
	var bad := 0
	var lengths: Array[float] = []
	var routes: Array[float] = []
	var times: Array[float] = []
	var missing := {}
	for s in 30:
		var t0 := Time.get_ticks_msec()
		var m := TrenchMaze.new()
		m.w = TrenchMaze.GRID_W
		m.d = TrenchMaze.GRID_D
		m.rng.seed = 1000 + s
		var ok := false
		for attempt in 40:
			m._reset()
			if m._layout():
				ok = true
				break
		times.append(Time.get_ticks_msec() - t0)
		if not ok:
			bad += 1
			m.free()
			continue
		lengths.append(m.open_cells.size() * m.cell)
		m._astar.clear()
		for c: Vector2i in m.open_cells:
			m._astar.add_point(m.idx(c), Vector2(c.x, c.y))
		for k: String in m.links:
			var p := k.split("|")
			m._astar.connect_points(int(p[0]), int(p[1]))
		routes.append(m._astar.get_id_path(m.idx(m.start_cell), m.idx(m.exit_cell)).size() * m.cell)
		for need: String in ["dugout", "gunpit", "op", "tree", "flood_junction"]:
			if not m.landmarks.any(func(l: Dictionary) -> bool: return l.kind == need):
				missing[need] = missing.get(need, 0) + 1
		# no stray contact: every pair of touching open cells is linked
		for c: Vector2i in m.open_cells:
			for dir in Maze.DIRS:
				if m.open_cells.has(c + dir) and not m.linked(c, c + dir):
					bad += 1
		if s == 0 and OS.get_cmdline_user_args().has("ascii"):
			print(m.ascii())
		m.free()
	print("      %d of 30 failed; trench %.0f-%.0f m (avg %.0f); start to exit %.0f-%.0f m; layout %.0f ms avg; missing %s" % [
		bad, lengths.min(), lengths.max(), _avg(lengths), routes.min(), routes.max(), _avg(times), missing])
	_check(bad == 0, "every layout made, every cell reachable, nothing touching unlinked")
	_check(_avg(lengths) >= 180.0 and _avg(lengths) <= 340.0, "about 2-3x a bunker floor of trench (%.0f m)" % _avg(lengths))
	_check(missing.get("dugout", 0) + missing.get("op", 0) + missing.get("tree", 0) < 6, "the landmarks are nearly always there (%s)" % missing)


func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


func _ground() -> void:
	print("-- ground")
	var t0 := Time.get_ticks_msec()
	var m := _make(77)
	print("      built in %d ms; %d x %d samples" % [Time.get_ticks_msec() - t0, m.hx, m.hz])
	if OS.get_cmdline_user_args().has("ascii"):
		print(m.ascii())
	await _frames(3)
	var space := m.get_world_3d().direct_space_state
	var worst := 0.0
	var depths: Array[float] = []
	for c: Vector2i in m.route:
		var p := m.cell_center(c)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			worst = 99.0
			continue
		worst = maxf(worst, absf((hit.position as Vector3).y - p.y))
		depths.append(m.ground_height(p.x + 3.0, p.z) - p.y)
	print("      collision vs floor_height along the route: worst %.3f m" % worst)
	_check(worst < 0.03, "the collision is the walked surface")
	m.queue_free()
	await _frames(2)


var game: Node3D


func _new_game(floor_: int) -> void:
	if game == null:
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await _frames(2)
		FpsPlayer.god_mode = true
	game.start_run()
	game.floor_number = floor_ - 1
	var t0 := Time.get_ticks_msec()
	game.next_floor()
	if game.maze is TrenchMaze:
		print("      trench floor built in %d ms" % (Time.get_ticks_msec() - t0))
	await _frames(3)


func _game() -> void:
	print("-- game")
	var kinds := []
	for f in [1, 2, 3, 4, 6]:
		await _new_game(f)
		kinds.append("%d:%s" % [game.floor_number, "trench" if game.maze is TrenchMaze else "bunker"])
		if f == 3:
			var env: Environment = game._world_env.environment
			_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and env.ambient_light_energy > 1.0, "overcast daylight on the trench floor")
			var counts := {}
			for c: Clown in game.clowns:
				counts[c.body] = counts.get(c.body, 0) + 1
			print("      floor 3 enemies: %s" % counts)
			var soldiers: int = game.clowns.filter(func(c: Clown) -> bool: return c.body != "clown").size()
			_check(soldiers >= game.clowns.size() * 0.6, "mostly soldiers (%d of %d)" % [soldiers, game.clowns.size()])
			var m: TrenchMaze = game.maze
			var ex: Vector3 = game._exit.global_position
			_check(m.is_open(m.cell_of(ex)) and absf(ex.y - m.floor_height(ex)) < 0.1, "the exit door stands on the floor in the end of the fire trench")
			await _walk(m)
		if f == 4:
			_check(game._world_env.environment == game._bunker_env, "back to the bunker's dark below ground")
	print("      floors: %s" % [kinds])
	_check(kinds == ["1:bunker", "2:bunker", "3:trench", "4:bunker", "6:trench"], "every third floor is the trenches")


## Walk the player along the whole route by input-free velocity: he should
## follow the floor (duckboards, slopes) and never fall through or stick.
func _walk(m: TrenchMaze) -> void:
	var p: FpsPlayer = game.player
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	p.global_position = m.cell_center(m.route[0]) + Vector3.UP * 0.2
	var stuck := 0
	var worst_off := 0.0
	var reached := 0
	_key(KEY_W, true)
	for i in range(1, m.route.size()):
		var target := m.cell_center(m.route[i])
		var t := 0.0
		while t < 2.5:
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.35:
				break
			p.rotation.y = atan2(-to.x, -to.z)        # walk at it (forward is -Z)
			await get_tree().physics_frame
			t += 1.0 / 60.0
			worst_off = maxf(worst_off, absf(p.global_position.y - m.floor_height(p.global_position)))
		if t >= 2.5:
			stuck += 1
		else:
			reached += 1
	_key(KEY_W, false)
	print("      walked the route: %d of %d cells reached, %d stuck, worst height off the walked surface %.2f m" % [reached, m.route.size() - 1, stuck, worst_off])
	_check(stuck == 0, "the player walks the whole route, start to exit")
	_check(worst_off < 0.5, "and stays on the ground (%.2f m)" % worst_off)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _bodies() -> void:
	print("-- bodies")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	game.player.global_position = m.cell_center(m.start_cell) + Vector3.UP * 0.2
	# spots: on a duckboard, in water, on a fire step, against a wall
	var spots := {}
	for d: Dictionary in m.duckboards:
		if d.sunk == 0.0 and not spots.has("duckboard"):
			spots["duckboard"] = ((d.a as Vector3) + (d.b as Vector3)) * 0.5
	for wa: Dictionary in m.water:
		var cells: Array = wa.cells
		spots["water"] = m.cell_center(cells[0])
		break
	for c: Vector2i in m.bays:
		var r := m._rect(c)
		spots["fire step"] = Vector3(r.get_center().x, 0, r.position.y + 0.3)
		break
	for c: Vector2i in m.open_cells:
		if m.wall(c, Vector2i(1, 0)) == "earth":
			var r := m._rect(c)
			spots["earth wall"] = Vector3(r.end.x - 0.35, 0, r.get_center().y)
			break
	var kinds := ["witzsoldat", "clown", "rattlejack", "klappersoldat"]
	var i := 0
	var victims := {}
	for name_: String in spots:
		var p: Vector3 = spots[name_]
		p.y = m.floor_height(p)
		var c: Clown
		match kinds[i % kinds.size()]:
			"rattlejack": c = game.spawn_rattlejack()
			"klappersoldat": c = game.spawn_klapper()
			_: c = game._spawn_clown(kinds[i % kinds.size()] == "witzsoldat", false)
		c.global_position = p
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
		victims[name_] = c
		i += 1
	await _frames(20)
	for name_: String in victims:
		var c: Clown = victims[name_]
		var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
		var dir := Vector3(randf_range(-1, 1), -0.1, randf_range(-1, 1)).normalized()
		c.hit({collider = chest, position = chest.global_position - dir * 0.1, direction = dir, damage = 500.0, impulse = 18.0, shot_id = randi()})
	# and a Carnival Curse on a WitzSoldat in the middle of a trench
	var cc: Clown = game._spawn_clown(true, false)
	var cp := m.cell_center(m.route[m.route.size() / 2])
	cc.global_position = cp
	await _frames(15)
	var cursed: bool = cc.begin_curse({}, cc.global_position + Vector3.UP * 1.3, -cc.global_basis.z)
	await _frames(60 * 6)
	for name_: String in victims:
		var c: Clown = victims[name_]
		_report(m, name_, c)
	_check(cursed, "the curse takes a WitzSoldat in the trench")
	if is_instance_valid(cc):
		_report(m, "cursed", cc)
		var info: Dictionary = cc.get_meta(&"curse", {})
		_check(info.get("handover_at", -1.0) > 2.0, "the execution ran to the ragdoll (%.2f s)" % info.get("handover_at", -1.0))
	print("      blood pools %d" % Blood.pools().size())
	_check(Blood.pools().size() >= 2, "blood pools on the trench floor")


func _ambience() -> void:
	print("-- ambience")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var amb: TrenchAmbience = m.get_node("Art/Ambience")
	var art: TrenchArt = m.get_node("Art")
	var p: FpsPlayer = game.player
	var hp := p.health
	FpsPlayer.god_mode = false
	await _walk(m)
	# and through the water
	for wa: Dictionary in m.water:
		var cells: Array = wa.cells
		p.global_position = m.cell_center(cells[0]) + Vector3.UP * 0.2
		await _frames(5)
		_key(KEY_W, true)
		for i in 90:
			var to := m.cell_center(cells[mini(1, cells.size() - 1)]) - p.global_position
			if Vector2(to.x, to.z).length() < 0.3:
				to = m.cell_center(cells[0]) - p.global_position
			p.rotation.y = atan2(-to.x, -to.z)
			await get_tree().physics_frame
		_key(KEY_W, false)
		break
	# stand by the music box a while
	if art.music_box != Vector3.INF:
		amb._t_tune = 0.5
		p.global_position = m.cell_center(m.cell_of(art.music_box)) + Vector3.UP * 0.2
		await _frames(60)
	print("      steps %s; shells %d (flashes %d); tunes %d; health %.0f -> %.0f" % [amb.steps, amb.booms, amb.flashes, amb.tunes, hp, p.health])
	_check(amb.steps.get("mud", 0) + amb.steps.get("wood", 0) > 20, "footsteps along the trench (mud and duckboards)")
	_check(amb.steps.get("wood", 0) > 5, "duckboards sound like wood")
	_check(amb.steps.get("water", 0) > 0 or m.water.is_empty(), "wading the flooded stretch splashes")
	_check(amb.booms > 0 and amb.flashes > 0, "the guns far off: flashes and booms")
	_check(art.music_box == Vector3.INF or amb.tunes > 0, "the music box plays when you are by it")
	_check(p.health >= hp, "none of it hurts")
	FpsPlayer.god_mode = true
	var counts := {}
	for mmi in art.find_children("*", "MultiMeshInstance3D", false, false):
		counts[mmi.name] = (mmi as MultiMeshInstance3D).multimesh.instance_count
	print("      dressing: %s" % counts)
	_check(art.get_node_or_null("Wire") != null and art.get_node_or_null("Balloon") != null, "wire in No Man's Land, a red balloon caught on it")
	_check(art.find_children("*", "Label3D", false, false).size() >= 4, "signs at the junctions (%d)" % art.find_children("*", "Label3D", false, false).size())
	_check(counts.get("crates", 0) >= 4 and counts.get("helmets", 0) + counts.get("tins", 0) > 3, "clutter about the place")


func _report(m: TrenchMaze, name_: String, c: Clown) -> void:
	var lowest := 9.0
	var hips := 9.0
	var under := 0.0
	for bn: StringName in c.ragdoll.bones:
		var pb: PhysicalBone3D = c.ragdoll.bones[bn]
		var g := m.floor_height(pb.global_position)
		var off := pb.global_position.y - g
		lowest = minf(lowest, off)
		if bn == &"Hips":
			hips = off
		under = minf(under, off)
	var speed := 0.0
	for pb: PhysicalBone3D in c.ragdoll.bones.values():
		speed = maxf(speed, pb.linear_velocity.length())
	print("      %s (%s): hips %.2f m above the walked surface, lowest bone %.2f, moving %.2f m/s" % [name_, c.body, hips, lowest, speed])
	# slumped against the sloping earth wall a body can end up sitting: allow more there
	var top := 0.8 if name_ == "earth wall" else 0.6
	_check(hips > -0.12 and hips < top and lowest > -0.2, "%s: lying on the ground, not floating or through it" % name_)
	_check(speed < 0.3, "%s: at rest" % name_)


## Render only: normal-map orientation through the mud shader. Textures
## made the way tools/gen_trench_textures.py makes them (OpenGL: red = -dh/du,
## green = +dh/drow, i.e. tilted toward the top of the image) from a known
## slope, compressed to two channels as the import does, on the ground up
## top, the trench floor and walls facing each way; the shader's world normal
## (debug_view) must lean away from the uphill side.
func _normals() -> void:
	if not render:
		return
	print("-- normals")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	add_child(cam)
	cam.make_current()
	var ramps := {"u": _ramp_tex(true), "row": _ramp_tex(false)}
	var shader: Shader = load("res://shaders/mud_terrain.gdshader" if not OS.get_cmdline_user_args().has("oldshader") else "res://shaders/zz_old_mud.gdshader")
	# surfaces: name, centre, outward normal, which world axis the texture's u
	# runs along, which way image-down (row) runs, floor mask, distance from edge
	var surfaces := [
		["ground", Vector3(0, 0, 0), Vector3.UP, Vector3.RIGHT, Vector3.BACK, 0.0, 1.0],
		["floor", Vector3(0, 0, 0), Vector3.UP, Vector3.RIGHT, Vector3.BACK, 1.0, 0.0],
		["wall +x", Vector3(0, 0, 0), Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, 0.0, 0.2],
		["wall -x", Vector3(0, 0, 0), Vector3.LEFT, Vector3.BACK, Vector3.DOWN, 0.0, 0.2],
		["wall +z", Vector3(0, 0, 0), Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 0.0, 0.2],
		["wall -z", Vector3(0, 0, 0), Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN, 0.0, 0.2],
	]
	var bad := 0
	var lines := []
	var bimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	bimg.fill(Color.BLACK)
	var black := ImageTexture.create_from_image(bimg)
	for sf: Array in surfaces:
		for ramp: String in ramps:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			for k in ["wall_n", "rocks_n", "firm_n", "floor_n"]:
				mat.set_shader_parameter(k, ramps[ramp])
			mat.set_shader_parameter("noise_tex", black)        # no puddles over the test surface
			mat.set_shader_parameter("floor_scan", sf[0] == "floor")
			mat.set_shader_parameter("floor_depth", 0.0)
			mat.set_shader_parameter("debug_view", 1)
			var mi := MeshInstance3D.new()
			mi.mesh = _quad(sf[2], Color(0.0, sf[5], sf[6] * 0.5, 0.5))
			mi.material_override = mat
			add_child(mi)
			var out: Vector3 = sf[2]
			cam.global_position = out * 3.0
			cam.look_at(Vector3.ZERO, Vector3.FORWARD if absf(out.y) > 0.9 else Vector3.UP)
			await _frames(3 if not lines.is_empty() else 30)   # the first waits for the shader to compile
			await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2).srgb_to_linear()
			var nrm := Vector3(c.r, c.g, c.b) * 2.0 - Vector3.ONE
			# uphill: along u for the u ramp, along image-down for the row ramp
			var uphill: Vector3 = sf[3] if ramp == "u" else sf[4]
			var lean := nrm.dot(uphill)
			var faces := nrm.dot(out)
			var ok := lean < -0.1 and faces > 0.5
			if not ok:
				bad += 1
			lines.append("%s, slope along %s: normal (%.2f, %.2f, %.2f), toward uphill %.2f, outward %.2f %s" % [sf[0], ramp, nrm.x, nrm.y, nrm.z, lean, faces, "" if ok else "  <- WRONG"])
			mi.queue_free()
			await _frames(1)
	# the props' shader (pbr_object): a board (grain along it) and an iron
	# sheet (rust running down), faces each way. Expected (u, v) per face, as
	# the shader maps them with variation off: the uphill side is +u for a
	# slope along u, +v (down the image) for a slope down the rows.
	var obj_shader: Shader = load("res://shaders/pbr_object.gdshader")
	var props := [
		["board +z", true, Vector3.BACK, Vector3.UP, Vector3.RIGHT],
		["board -z", true, Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
		["board +y", true, Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		["board +x", true, Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		["iron +z", false, Vector3.BACK, Vector3.RIGHT, Vector3.DOWN],
		["iron -x", false, Vector3.LEFT, Vector3.BACK, Vector3.DOWN],
		["iron +y", false, Vector3.UP, Vector3.RIGHT, Vector3.BACK],
	]
	for pr: Array in props:
		for ramp: String in ramps:
			var mat := ShaderMaterial.new()
			mat.shader = obj_shader
			mat.set_shader_parameter("normal_tex", ramps[ramp])
			mat.set_shader_parameter("noise_tex", black)
			mat.set_shader_parameter("grain", pr[1])
			mat.set_shader_parameter("vary", false)
			mat.set_shader_parameter("debug_view", 1)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			mi.mesh = bm
			mi.scale = Vector3(2.0, 0.6, 0.3) if pr[1] else Vector3(1.4, 2.0, 0.4)
			mi.material_override = mat
			add_child(mi)
			var out: Vector3 = pr[2]
			cam.size = 0.1
			cam.global_position = out * 3.0
			cam.look_at(Vector3.ZERO, Vector3.FORWARD if absf(out.y) > 0.9 else Vector3.UP)
			await _frames(30 if pr == props[0] and ramp == "u" else 3)
			await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2).srgb_to_linear()
			var nrm := Vector3(c.r, c.g, c.b) * 2.0 - Vector3.ONE
			var uphill: Vector3 = pr[3] if ramp == "u" else pr[4]
			var lean := nrm.dot(uphill)
			var faces := nrm.dot(out)
			var ok := lean < -0.1 and faces > 0.5
			if not ok:
				bad += 1
			lines.append("%s, slope along %s: normal (%.2f, %.2f, %.2f), toward uphill %.2f, outward %.2f %s" % [pr[0], ramp, nrm.x, nrm.y, nrm.z, lean, faces, "" if ok else "  <- WRONG"])
			mi.queue_free()
			await _frames(1)
	for l: String in lines:
		print("      " + l)
	_check(bad == 0, "raised detail leans away from the uphill side, and faces out, on every surface (%d wrong)" % bad)
	env.queue_free()
	cam.queue_free()


## Render only: raised and recessed detail lit. A normal map of three
## domes and a groove (encoded as the generator does, compressed like the
## import) on a patch of ground and a wall, a low sun from the right: the
## domes should be lit on their right, the groove's right-hand bank in shade
## (/tmp/tr_relief.png; "oldshader" uses shaders/zz_old_mud.gdshader).
func _relief() -> void:
	if not render:
		return
	print("-- relief")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.25, 0.25)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var tex := _relief_tex()
	var gimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	gimg.fill(Color(0.55, 0.5, 0.45))
	var grey := ImageTexture.create_from_image(gimg)
	var bimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	bimg.fill(Color.BLACK)
	var black := ImageTexture.create_from_image(bimg)
	var path := "res://shaders/mud_terrain.gdshader" if not OS.get_cmdline_user_args().has("oldshader") else "res://shaders/zz_old_mud.gdshader"
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for k in ["churned", "sludge", "wall", "firm"]:
		mat.set_shader_parameter(k + "_n", tex)
		mat.set_shader_parameter(k + "_a", grey)
	mat.set_shader_parameter("noise_tex", black)
	mat.set_shader_parameter("floor_scan", false)
	mat.set_shader_parameter("mud_tile", 2.0)
	mat.set_shader_parameter("wall_tile", 2.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	add_child(cam)
	cam.make_current()
	var shots := []
	for out: Vector3 in [Vector3.UP, Vector3.BACK, Vector3.LEFT]:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(out, Color(0.0, 0.0, 0.5 if out == Vector3.UP else 0.1, 0.5))
		mi.material_override = mat
		# the patch lines up with one texture tile
		mi.position = Vector3(1, 0, 1) if out == Vector3.UP else (Vector3(1, -1, 0) if out == Vector3.BACK else Vector3(0, -1, 1))
		add_child(mi)
		# a low sun from the right of the view (and a little from above)
		var right := Vector3.RIGHT if out == Vector3.UP else (Vector3.RIGHT if out == Vector3.BACK else Vector3.FORWARD)
		var up := Vector3.FORWARD if out == Vector3.UP else Vector3.UP
		var toward_light := (right * 0.85 + out * 0.45 + up * 0.25).normalized()
		sun.look_at_from_position(Vector3.ZERO, -toward_light, Vector3.UP if absf(toward_light.y) < 0.95 else Vector3.RIGHT)
		cam.global_position = mi.position + out * 3.0
		cam.look_at(mi.position, up)
		await _frames(30 if shots.is_empty() else 4)
		await get_tree().process_frame
		shots.append(get_viewport().get_texture().get_image())
		mi.queue_free()
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var sheet := Image.create(w * shots.size(), h, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png("/tmp/tr_relief%s.png" % ("_old" if OS.get_cmdline_user_args().has("oldshader") else ""))
	env.queue_free()
	sun.queue_free()
	cam.queue_free()


## Three raised domes and a sunken groove, as a normal map.
func _relief_tex() -> Texture2D:
	var n := 128
	var hgt := PackedFloat32Array()
	hgt.resize(n * n)
	for y in n:
		for x in n:
			var v := 0.0
			for d: Vector3 in [Vector3(0.25, 0.3, 0.13), Vector3(0.7, 0.28, 0.1), Vector3(0.3, 0.75, 0.12)]:
				var r := Vector2(x / float(n) - d.x, y / float(n) - d.y).length() / d.z
				v += maxf(0.0, 1.0 - r * r)
			var gx := x / float(n) - 0.72
			if absf(y / float(n) - 0.72) < 0.18:
				v -= maxf(0.0, 1.0 - (gx * gx) / (0.06 * 0.06))     # the groove, running down the image
			hgt[x + y * n] = v
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var gxx := (hgt[(x + 1) % n + y * n] - hgt[(x - 1 + n) % n + y * n]) * 0.5 * n / 6.0
			var gyy := (hgt[x + ((y + 1) % n) * n] - hgt[x + ((y - 1 + n) % n) * n]) * 0.5 * n / 6.0
			var nn := Vector3(-gxx, gyy, 1.0).normalized()       # as tools/gen_trench_textures.py: nx = -gx, ny = +gy
			img.set_pixel(x, y, Color(nn.x * 0.5 + 0.5, nn.y * 0.5 + 0.5, nn.z * 0.5 + 0.5))
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)
	return ImageTexture.create_from_image(img)


## A normal map of a plain slope, encoded as the texture generator does
## (OpenGL), compressed to two channels like the import.
func _ramp_tex(along_u: bool) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var k := 0.6
	var nrm := Vector3(-k, 0.0, 1.0) if along_u else Vector3(0.0, k, 1.0)
	nrm = nrm.normalized()
	img.fill(Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)
	return ImageTexture.create_from_image(img)


## A 2 m quad through the origin facing `out`, with vertex colour `col`.
func _quad(out: Vector3, col: Color) -> Mesh:
	var a := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := out.cross(a).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(out)
	st.set_color(col)
	var p := [-a - b, a - b, a + b, -a + b]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.add_vertex(p[i])
	var m := st.commit()
	return m


## Render only: the walls and the ground up top in the game's light, with the
## current shader and (if shaders/zz_old_mud.gdshader is there) the old one
## (/tmp/tr_walls_<view>_new|old.png).
func _walls() -> void:
	if not render:
		return
	print("-- walls")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 70.0
	var mats := _mud_mats(m)
	var k := m.route.size() / 2
	var p := m.cell_center(m.route[k])
	var shots := {
		"trench": [p + Vector3.UP * 1.65, m.cell_center(m.route[k + 2]) + Vector3.UP * 1.2],
		"wall": [p + Vector3.UP * 1.3, p + Vector3(0.0, 1.0, -1.0)],
		"earth": [p + Vector3.UP * 1.3, p + Vector3(0.0, 1.0, -1.0)],
		"top": [Vector3(m.w * m.cell * 0.5, 2.2, m.d * m.cell * 0.6), Vector3(m.w * m.cell * 0.5 + 4.0, 0.0, m.d * m.cell * 0.6 - 6.0)],
	}
	# a bare earth wall, seen across the trench
	for c: Vector2i in m.open_cells:
		var hit := false
		for dir in Maze.DIRS:
			if m.wall(c, dir) == "earth" and m.wall(c, -dir) == "earth" and m.kind[c] == "comm":
				var cc := m.cell_center(c)
				shots["earth"] = [cc + Vector3(-dir.x, 0, -dir.y) * 0.55 + Vector3.UP * 1.4, cc + Vector3(dir.x, 0, dir.y) * 1.2 + Vector3.UP * 0.9]
				hit = true
				break
		if hit:
			break
	var old_path := "res://shaders/zz_old_mud.gdshader"
	var versions := ["new"]
	if ResourceLoader.exists(old_path):
		versions.append("old")
	for v: String in versions:
		for sm in mats:
			sm.shader = load("res://shaders/mud_terrain.gdshader" if v == "new" else old_path)
		for name_: String in shots:
			cam.global_position = shots[name_][0]
			cam.look_at(shots[name_][1])
			await _frames(30 if name_ == "trench" else 4)
			await _shot("walls_%s_%s" % [name_, v])


func _mud_mats(m: TrenchMaze) -> Array[ShaderMaterial]:
	var mats: Array[ShaderMaterial] = []
	for mi in m.get_node("Art").get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm.shader.resource_path.contains("mud") and not mats.has(sm):
				mats.append(sm)
	return mats


## Parallax on the trench floor. Two checks:
##  - depth: with the height map flat at the bottom (everything 4.5 cm deep),
##    the parallaxed floor must look like the same floor lowered 4.5 cm
##    without parallax, seen from steep to grazing (the views compared pixel
##    by pixel);
##  - in the trench: down the longest straight stretch at five pitches, with
##    and without parallax (/tmp/tr_pom_<pitch>_on|off.png), for the eye.
func _parallax() -> void:
	if not render:
		return
	print("-- parallax")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var flat_img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	flat_img.fill(Color(1.0, 1.0, 0.0))                  # AO 1, roughness 1, height 0: all at the bottom
	var flat := ImageTexture.create_from_image(flat_img)
	var nimg := Image.create(8, 8, false, Image.FORMAT_RGB8)
	nimg.fill(Color(0.5, 0.5, 1.0))
	var nflat := ImageTexture.create_from_image(nimg)
	var checker := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var c := ((x / 16) + (y / 16)) % 2
			checker.set_pixel(x, y, Color(0.9, 0.2, 0.1) if c == 0 else Color(0.1, 0.3, 0.9))
	checker.generate_mipmaps()
	var check := ImageTexture.create_from_image(checker)
	var bimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	bimg.fill(Color.BLACK)
	var black := ImageTexture.create_from_image(bimg)
	var mats := []
	for pom in [true, false]:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/mud_terrain.gdshader")
		mat.set_shader_parameter("floor_a", check)
		mat.set_shader_parameter("floor_n", nflat)
		mat.set_shader_parameter("floor_ard", flat)
		mat.set_shader_parameter("noise_tex", black)
		mat.set_shader_parameter("floor_depth", 0.045 if pom else 0.0)
		mat.set_shader_parameter("floor_parallax_range", 1000.0)
		mat.set_shader_parameter("floor_water", -1.0)
		mat.set_shader_parameter("debug_view", 3)
		mats.append(mat)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	var worst := 0.0
	for pitch_deg in [80.0, 60.0, 40.0, 25.0, 17.0]:
		var imgs := []
		for i in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _quad(Vector3.UP, Color(1.0, 1.0, 0.0, 0.5))
			mi.scale = Vector3(6, 1, 6)
			mi.material_override = mats[mini(i, 1)]
			mi.position = Vector3(0, -0.045 if i == 1 else 0.0, 0)      # 0 parallax; 1 no parallax, lowered; 2 no parallax, not lowered (control)
			add_child(mi)
			var pitch := deg_to_rad(pitch_deg)
			cam.global_position = Vector3(0.3, 0.6 * sin(pitch) + 0.1, 0.6 * cos(pitch) + 0.2)
			cam.look_at(Vector3(0.3, 0.0, 0.2))
			await _frames(30 if imgs.is_empty() and pitch_deg == 80.0 else 4)
			await get_tree().process_frame
			imgs.append(get_viewport().get_texture().get_image())
			mi.queue_free()
			await _frames(1)
		var frac := _img_diff(imgs[0], imgs[1])
		var control := _img_diff(imgs[0], imgs[2])
		worst = maxf(worst, frac if pitch_deg >= 25.0 else 0.0)
		print("      looking %2d deg down: parallaxed vs really lowered 4.5 cm: %.1f%% of pixels differ (vs not lowered at all: %.1f%%)" % [int(pitch_deg), frac * 100.0, control * 100.0])
		if pitch_deg >= 25.0 and control < 0.05:
			worst = 1.0                     # the parallax did nothing visible: the check means nothing
	_check(worst < 0.04, "parallax puts the surface where the height map says, from steep to low angles (worst %.1f%%)" % (worst * 100.0))
	env.queue_free()
	cam.queue_free()
	# in the trench, down the longest straight run
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var best: Array = []
	for name_: String in m.trenches:
		var cells: Array = m.trenches[name_]
		var run: Array = []
		for c: Vector2i in cells:
			if run.size() >= 2 and (c - (run.back() as Vector2i)) != ((run.back() as Vector2i) - (run[run.size() - 2] as Vector2i)):
				run = [run.back()]
			if not run.is_empty() and ((c - (run.back() as Vector2i)).length_squared() != 1):
				run = []
			run.append(c)
			if run.size() > best.size():
				best = run.duplicate()
	var a0 := m.cell_center(best[0])
	var a1 := m.cell_center(best.back())
	var dir := (a1 - a0)
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3.ZERO
	var cam2 := Camera3D.new()
	cam2.fov = 75.0
	add_child(cam2)
	cam2.make_current()
	var gm := _mud_mats(m)
	print("      longest straight stretch: %d cells (%.1f m)" % [best.size(), best.size() * m.cell])
	# the duckboards hide most of the floor: lift them out for these views
	for n in ["db_slats", "db_runners"]:
		var node := m.get_node_or_null("Art/" + n)
		if node:
			node.visible = false
	for pitch_deg in [3.0, 10.0, 20.0, 35.0, 60.0]:
		for pom in [true, false]:
			for sm in gm:
				sm.set_shader_parameter("floor_depth", 0.045 if pom else 0.0)
			cam2.global_position = a0 + side + Vector3.UP * 1.65 - dir * 0.3
			cam2.look_at(cam2.global_position + dir * cos(deg_to_rad(pitch_deg)) + Vector3.DOWN * sin(deg_to_rad(pitch_deg)))
			await _frames(30 if pitch_deg == 3.0 and pom else 3)
			await _shot("pom_%02d_%s" % [int(pitch_deg), "on" if pom else "off"])
	for sm in gm:
		sm.set_shader_parameter("floor_depth", 0.045)
	cam2.queue_free()


func _img_diff(a: Image, b: Image) -> float:
	var diff := 0
	var tot := 0
	for y in range(a.get_height() / 4, a.get_height() * 3 / 4, 2):
		for x in range(a.get_width() / 4, a.get_width() * 3 / 4, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			tot += 1
			if absf(ca.r - cb.r) + absf(ca.b - cb.b) > 0.5:
				diff += 1
	return float(diff) / maxf(tot, 1)


## Render only: representative stretches for the materials, at eye height:
## a fire bay (sandbags, boards, fire step), an iron-lined support stretch,
## a bare earth communication trench, the slumped stretch, a duckboard close
## up, a sandbag wall close up (/tmp/tr_sec_*.png).
func _section() -> void:
	if not render:
		return
	print("-- section")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 72.0
	var shots := {}
	# looking along a trench from cell c toward the next in its trench list
	var along := func(c: Vector2i, name_: String) -> void:
		for t: String in m.trenches:
			var cells: Array = m.trenches[t]
			var i := cells.find(c)
			if i >= 0 and i + 2 < cells.size():
				shots[name_] = [m.cell_center(c) + Vector3.UP * 1.62, m.cell_center(cells[i + 2]) + Vector3.UP * 1.1]
				return
	for c: Vector2i in m.bays:
		if m.wall(c, Vector2i(0, 1)) != "" or true:
			along.call(c, "bay")
			break
	for c: Vector2i in m.open_cells:
		if not shots.has("iron") and (m.wall(c, Vector2i(0, 1)) == "iron" or m.wall(c, Vector2i(0, -1)) == "iron"):
			along.call(c, "iron")
		if not shots.has("earth") and m.kind[c] == "comm" and m.wall(c, Vector2i(1, 0)) == "earth":
			along.call(c, "earth")
		if not shots.has("slump") and m.collapsed.has(c):
			var p := m.cell_center(c)
			for dir in Maze.DIRS:
				if m.open_cells.has(c - dir):
					var back := m.cell_center(c - dir)
					shots["slump"] = [back + Vector3.UP * 1.62 - Vector3(dir.x, 0, dir.y) * 0.5, p + Vector3.UP * 0.6]
					break
		for dir in Maze.DIRS:
			if not shots.has("bags") and m.wall(c, dir) == "sandbag" and m.kind[c] in ["fire", "traverse", "sap"]:
				var p := m.cell_center(c)
				shots["bags"] = [p - Vector3(dir.x, 0, dir.y) * 0.45 + Vector3.UP * 1.2, p + Vector3(dir.x, 0, dir.y) * 0.8 + Vector3.UP * 0.8]
	var d: Dictionary = m.duckboards[m.duckboards.size() / 2]
	var mid: Vector3 = ((d.a as Vector3) + (d.b as Vector3)) * 0.5
	shots["boards"] = [mid + Vector3(0.35, 1.0, 0.35), mid]
	for name_: String in shots:
		cam.global_position = shots[name_][0]
		cam.look_at(shots[name_][1])
		await _frames(40 if name_ == shots.keys()[0] else 4)
		await _shot("sec_" + name_)
	print("      shots: %s" % [shots.keys()])


## Render only: the trench floor close up (eye height down the trench, the
## ground at your feet, a flooded stretch), with the scanned mud and, for
## comparison, the old procedural sludge (/tmp/tr_floor_*_new|old.png).
func _floor() -> void:
	if not render:
		return
	print("-- floor")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 70.0
	var mats: Array[ShaderMaterial] = []
	for mi in m.get_node("Art").get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm.shader.resource_path.ends_with("mud_terrain.gdshader") and not mats.has(sm):
				mats.append(sm)
	# a stretch with no duckboards (the flooded side trench or a dugout stub), and the main route
	var bare := m.route[m.route.size() / 2]
	for c: Vector2i in m.open_cells:
		if m.kind[c] in ["gunpit"]:
			bare = c
			break
	var flood := m.start_cell
	for wa: Dictionary in m.water:
		flood = (wa.cells as Array)[0]
		break
	var k := m.route.size() / 3
	var shots := {
		"eye": [m.cell_center(m.route[k]) + Vector3.UP * 1.65, m.cell_center(m.route[k + 3]) + Vector3.UP * 0.2],
		"feet": [m.cell_center(bare) + Vector3(0.2, 1.6, 0.6), m.cell_center(bare) + Vector3(0.0, 0.0, -0.4)],
		"low": [m.cell_center(bare) + Vector3(-0.5, 0.45, 0.5), m.cell_center(bare) + Vector3(0.6, 0.0, -0.5)],
		"flood": [m.cell_center(flood) + Vector3(0.3, 1.6, 0.9), m.cell_center(flood) + Vector3(0, 0, -0.8)],
	}
	for scan in [true, false]:
		for sm in mats:
			sm.set_shader_parameter("floor_scan", scan)
		for name_: String in shots:
			cam.global_position = shots[name_][0]
			cam.look_at(shots[name_][1])
			await _frames(3)
			await _shot("floor_%s_%s" % [name_, "new" if scan else "old"])


func _views() -> void:
	if not render:
		return
	print("-- views")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	var keep: Clown = null
	for c: Clown in game.clowns:
		if keep == null and c.body == "witzsoldat":
			keep = c
		else:
			c.queue_free()
	game.clowns.clear()
	if keep:
		game.clowns.append(keep)
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.far = 500.0
	cam.fov = 75.0
	await _frames(30)
	var mid := Vector3(m.w * m.cell * 0.5, 0, m.d * m.cell * 0.5)
	cam.global_position = mid + Vector3(-20, 45, 45)
	cam.look_at(mid)
	await _frames(2)
	await _shot("top")
	var i := 0
	var picks := [m.start_cell, m.route[m.route.size() / 4], m.route[m.route.size() / 2], m.route[m.route.size() * 3 / 4], m.route[m.route.size() - 3]]
	for c: Vector2i in picks:
		var k := m.route.find(c)
		var p := m.cell_center(c) + Vector3.UP * 1.65
		cam.global_position = p
		var look := m.cell_center(m.route[mini(k + 3, m.route.size() - 1)]) + Vector3.UP * 1.4
		if Vector2(look.x - p.x, look.z - p.z).length() < 0.5:
			look = p + Vector3(1, -0.1, 0)
		cam.look_at(look)
		await _frames(2)
		await _shot("eye_%d" % i)
		i += 1
	# over the parapet from a fire step, into No Man's Land
	for c: Vector2i in m.bays:
		var r := m._rect(c)
		cam.global_position = Vector3(r.get_center().x, m.floor_height(Vector3(r.get_center().x, 0, r.position.y + 0.25)) + 1.65, r.position.y + 0.3)
		cam.look_at(cam.global_position + Vector3(0.3, 0.05, -1))
		await _frames(2)
		await _shot("nml")
		break
	# into a dugout from its door
	var art: TrenchArt = m.get_node("Art")
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			var ent := m.cell_center(l.entrance)
			cam.global_position = ent + Vector3.UP * 1.5 - Vector3(l.dir.x, 0, l.dir.y) * 0.6
			cam.look_at(m.cell_center(l.cell) + Vector3(l.dir.x, 0, l.dir.y) * 0.8 + Vector3.UP * 0.8)
			await _frames(2)
			await _shot("dugout")
			break
	# the music box's dugout, if there is one
	if art.music_box != Vector3.INF:
		var room := m.cell_center(m.cell_of(art.music_box))
		var away := (room - art.music_box)
		away.y = 0.0
		cam.global_position = art.music_box + away.normalized() * 1.1 + Vector3.UP * 0.6
		cam.look_at(art.music_box + Vector3.UP * 0.3)
		await _frames(2)
		await _shot("musicbox")
	# the porcelain head in the mud
	for mmi in art.find_children("porcelain_head", "MultiMeshInstance3D", false, false):
		var at: Vector3 = (mmi as MultiMeshInstance3D).multimesh.get_instance_transform(0).origin
		var c := m.cell_of(at)
		cam.global_position = m.cell_center(c) + Vector3.UP * 1.0 + (m.cell_center(c) - at).normalized() * 0.3
		cam.look_at(at)
		await _frames(2)
		await _shot("head")
	# out over the wire from high up behind the parapet
	cam.global_position = Vector3(m.w * m.cell * 0.5, 3.0, 9.0)
	cam.look_at(Vector3(m.w * m.cell * 0.5, 0.0, -15.0))
	await _frames(2)
	await _shot("wire")
	# a soldier in a trench, from 6 m: can he be seen?
	for c: Clown in game.clowns:
		if is_instance_valid(c) and c.body == "witzsoldat":
			var at := c.global_position
			var cc := m.cell_of(at)
			var k := m.route.find(cc)
			var from := at + Vector3(4, 1.6, 0)
			for dir in Maze.DIRS:
				var n: Vector2i = cc + dir * 3
				if m.open_cells.has(n) and m.open_cells.has(cc + dir) and m.open_cells.has(cc + dir * 2):
					from = m.cell_center(n) + Vector3.UP * 1.6
					break
			cam.global_position = from
			cam.look_at(at + Vector3.UP * 1.1)
			await _frames(2)
			await _shot("enemy")
			break
