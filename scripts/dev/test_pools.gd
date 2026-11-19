extends Node3D
## Blood pools on real geometry. A test room: open floor, a bunker wall, a
## 4 cm door sill, a box of debris, a platform with five steps down (0.2 m
## rise, 0.25 m tread, like the maze's stairs) and a 10 degree slope.
## Checks: outlines differ; nothing goes through the wall or over the sill;
## blood follows the stair treads, runs down risers, never spans two heights;
## downhill spread; gradual growth that settles; merging; many pools at once;
## oil puddles. Add "render" (with a window) for /tmp/k/pools_*.png.

var fails := 0
var render := false
var space: PhysicsDirectSpaceState3D


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _box(centre: Vector3, size: Vector3, basis := Basis.IDENTITY, colour := Color(0.42, 0.4, 0.37)) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	bm.material = m
	mi.mesh = bm
	b.add_child(mi)
	add_child(b)
	b.global_transform = Transform3D(basis, centre)


func _floor_at(x: float, z: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 3.0, z), Vector3(x, -1.0, z), 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3(x, 0, z)


func _ready() -> void:
	render = OS.get_cmdline_user_args().has("render")
	_box(Vector3(0, -0.1, 0), Vector3(16, 0.2, 16))                       # floor, top at 0
	_box(Vector3(0, 1.5, -2.15), Vector3(9, 3, 0.3))                       # wall, face at z = -2
	_box(Vector3(0.85, 0.02, 0.0), Vector3(0.12, 0.04, 3.0), Basis.IDENTITY, Color(0.3, 0.25, 0.2))   # a 4 cm sill
	_box(Vector3(-1.6, 0.15, 0.6), Vector3(0.3, 0.3, 0.3), Basis.IDENTITY, Color(0.35, 0.28, 0.2))     # debris
	_box(Vector3(3.5, 0.6, 0.5), Vector3(1.0, 1.2, 2.0))                   # platform, top 1.2
	for k in 5:
		var top := 1.2 - 0.2 * (k + 1)
		_box(Vector3(4.125 + 0.25 * k, top * 0.5, 0.5), Vector3(0.25, top, 2.0))
	_box(Vector3(-4.2, 0.0, 3.0), Vector3(2.6, 0.3, 2.0), Basis(Vector3.BACK, deg_to_rad(-10.0)), Color(0.38, 0.36, 0.33))  # rises toward -x
	# a painted floor 4 mm up, visual only, like the circus rooms' sunbursts
	var paint := MeshInstance3D.new()
	var pq := PlaneMesh.new()
	pq.size = Vector2(4, 4)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.75, 0.6, 0.35)
	pq.material = pm
	paint.mesh = pq
	paint.position = Vector3(-2.0, 0.004, 0.6)
	add_child(paint)
	# a duckboard: drawn, with a box only blood sees (as the level makes them)
	_box(Vector3(-0.2, 0.035, 3.6), Vector3(2.4, 0.06, 0.4), Basis.IDENTITY, Color(0.3, 0.22, 0.14))
	var board: StaticBody3D = get_child(get_child_count() - 1)
	board.collision_layer = 1 << 5
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.025)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.12, 0.11, 0.1)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.ssr_enabled = true
	add_child(env)
	await get_tree().physics_frame
	await get_tree().physics_frame
	space = get_world_3d().direct_space_state
	await _run()
	print("POOLS: %d failed" % fails)
	get_tree().quit()


func _settle(pools: Array) -> float:
	var t := 0.0
	while t < 14.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var done := true
		for p: BloodPool in pools:
			if not p.settled:
				done = false
		if done:
			break
	return t


## Wet samples in the pool's own grid, as a set of offsets from its first source.
func _wet_mask(p: BloodPool) -> Dictionary:
	var out := {}
	var s: Vector3 = p.sources[0].pos
	for k in p.n * p.n:
		if p._v[k] < p.p_end:
			var gp := p._grid_pos(k % p.n, k / p.n)
			out[Vector2i(roundi((gp.x - s.x) / 0.05), roundi((gp.z - s.z) / 0.05))] = true
	return out


func _wet_points(p: BloodPool) -> Array:
	var out := []
	for k in p.n * p.n:
		if p._v[k] < p.p_end:
			var gp := p._grid_pos(k % p.n, k / p.n)
			gp.y = p._h[k]
			out.append(gp)
	return out


## Every floor triangle sits on the surface under it (no floating, no
## spanning two heights); returns the worst gap and the tallest floor triangle.
func _contact(p: BloodPool) -> Array:
	if p.mesh == null:
		return [0.0, 0.0, 0]
	var arr := p.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var worst := 0.0
	var tallest := 0.0
	var tri := 0
	for i in range(0, verts.size(), 3):
		if cols[i].a > 0.5:
			continue                              # a riser strip: vertical on purpose
		tri += 1
		var a := p.to_global(verts[i])
		var b := p.to_global(verts[i + 1])
		var c := p.to_global(verts[i + 2])
		tallest = maxf(tallest, maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)))
		if maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) > 0.05 and OS.get_cmdline_user_args().has("dbg"):
			print("      tall tri ", a, b, c)
		if tri % 7 != 0:
			continue
		var m := (a + b + c) / 3.0
		var q := PhysicsRayQueryParameters3D.create(m + Vector3.UP * 0.15, m + Vector3.DOWN * 0.3, 1)
		var hit := space.intersect_ray(q)
		var gap := 1.0 if hit.is_empty() else absf(m.y - BloodPool.LIFT - (hit.position as Vector3).y)
		worst = maxf(worst, gap)
	return [worst, tallest, tri]


func _run() -> void:
	# --- size: game pools are scaled down by pool_size (and capped); the
	# behaviour checks below run at full size, the sizes they were set up for
	var game_size := Blood.pool_size
	var p_small := _spawn(4.0, -3.0, 0.5)
	_check(absf(float(p_small.sources[0].r) - minf(0.5 * game_size, Blood.maximum_pool_radius)) < 0.001 and game_size < 1.0,
		"game pools are smaller: a 0.5 m pool comes out %.2f m (pool_size %.2f, at most %.2f m)" % [float(p_small.sources[0].r), game_size, Blood.maximum_pool_radius])
	Blood.clear()
	Blood.pool_size = 1.0
	Blood.maximum_pool_radius = 0.95
	# --- shape: two pools on open floor, the same size
	var p1 := _spawn(-1.0, 1.4, 0.5)
	var p2 := _spawn(-3.0, -0.8, 0.5)
	await _settle([p1, p2])
	var m1 := _wet_mask(p1)
	var m2 := _wet_mask(p2)
	var inter := 0
	for k in m1:
		if m2.has(k):
			inter += 1
	var iou := float(inter) / float(m1.size() + m2.size() - inter)
	print("      two open-floor pools: %d and %d wet samples, overlap of outlines %.2f" % [m1.size(), m2.size(), iou])
	_check(iou < 0.85, "two pools of the same size have different outlines (overlap %.2f)" % iou)
	var c1 := _contact(p1)
	_check(c1[0] < 0.012 and c1[1] < 0.02, "flat floor: lies on it (gap %.3f m, tallest triangle %.3f m)" % [c1[0], c1[1]])
	# --- a wall
	var pw := _spawn(-0.8, -1.75, 0.6)
	await _settle([pw])
	var through := false
	var xs := []
	var zs := []
	for wp: Vector3 in _wet_points(pw):
		xs.append(wp.x)
		zs.append(wp.z)
	var arr := pw.mesh.surface_get_arrays(0)
	for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
		if pw.to_global(v).z < -2.0 - 0.002:
			through = true
	var span_x: float = xs.max() - xs.min()
	var span_z: float = zs.max() - zs.min()
	print("      by the wall: %.2f m along it, %.2f m out from it, nearest blood %.3f m from the face" % [span_x, span_z, zs.min() + 2.0])
	_check(not through, "nothing goes into the wall")
	_check(span_x > span_z * 1.15, "stopped by the wall it spreads along it (%.2f x %.2f)" % [span_x, span_z])
	_check(zs.min() + 2.0 < 0.1, "and reaches the wall (%.3f m)" % (zs.min() + 2.0))
	# --- a 4 cm door sill
	var ps := _spawn(0.55, -0.2, 0.6)
	await _settle([ps])
	var past := 0
	var near_x := -9.0
	for wp: Vector3 in _wet_points(ps):
		if wp.x > 0.79:
			past += 1
		near_x = maxf(near_x, wp.x)
	print("      at the sill: furthest blood x %.2f (sill from 0.79), %d samples past it" % [near_x, past])
	_check(past == 0, "a 4 cm sill holds it back")
	# --- stairs: on the platform at the top edge
	# a small pool by the edge: a little runs over, no further than a step
	var small := _spawn(3.92, -0.25, 0.3)
	await _settle([small])
	var small_levels := {}
	for wp: Vector3 in _wet_points(small):
		small_levels[roundi(wp.y * 10.0)] = true
	print("      small pool at the top edge: heights reached (dm) %s" % str(small_levels.keys()))
	_check(not small_levels.has(8) and not small_levels.has(6), "a little blood does not run far down the stairs")
	# a big one: two bodies bleeding at the top edge
	var pt := _spawn(3.9, 0.85, 0.95)
	Blood.spawn_pool(_floor_at(3.75, 1.3), Vector3.UP, 0.9)
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle([pt])
	for f in 200:
		await get_tree().process_frame
		if pt.sampling_done() and pt.settled:
			break
	var by_level := {}
	for wp: Vector3 in _wet_points(pt):
		var lv := snappedi(roundi(wp.y * 10.0), 1)
		by_level[lv] = by_level.get(lv, 0) + 1
	var minv := {}
	for k in pt.n * pt.n:
		if pt._cls[k] == 0 and pt._v[k] < BloodPool.NEVER:
			var lv := roundi(pt._h[k] * 10.0)
			minv[lv] = snappedf(minf(float(minv.get(lv, 99.0)), pt._v[k]), 0.01)
	print("      stairs: earliest arrival by height %s (p_end %.2f, sources %d)" % [str(minv), pt.p_end, pt.sources.size()])
	var ct := _contact(pt)
	print("      stairs: wet samples by height %s; %d riser strips; worst gap %.3f m, tallest floor triangle %.3f m" % [str(by_level), pt.riser_quads, ct[0], ct[1]])
	_check(by_level.has(10) and by_level.has(8), "runs down onto the treads below (heights in dm: %s)" % str(by_level.keys()))
	_check(int(by_level.get(10, 0)) < int(by_level.get(12, 0)) and int(by_level.get(8, 0)) < int(by_level.get(10, 0)) and not by_level.has(2), "less on each step down, and not to the bottom")
	_check(pt.riser_quads > 0, "down the risers (%d strips)" % pt.riser_quads)
	_check(ct[0] < 0.012 and ct[1] < 0.03, "every part on its own tread: nothing floats or spans two steps (gap %.3f, tallest %.3f)" % [ct[0], ct[1]])
	# a pool at the foot of the stairs cannot climb them
	var pf := _spawn(5.45, 0.5, 0.6)
	await _settle([pf])
	var climbed := 0
	for wp: Vector3 in _wet_points(pf):
		if wp.y > 0.05:
			climbed += 1
	_check(climbed == 0, "a pool at the foot of the stairs does not climb them")
	# --- slope (rises toward -x)
	var top := _floor_at(-4.2, 3.0)
	Blood.spawn_pool(top, Vector3.UP, 0.55)
	var psl: BloodPool = Blood.pools().back()
	await _settle([psl])
	var down := 0.0
	var up := 0.0
	for wp: Vector3 in _wet_points(psl):
		down = maxf(down, wp.x - top.x)
		up = maxf(up, top.x - wp.x)
	print("      slope: %.2f m downhill, %.2f m uphill" % [down, up])
	_check(down > up * 1.12, "longer downhill than uphill on a 10 degree slope")
	var csl := _contact(psl)
	_check(csl[0] < 0.012, "lies on the slope (gap %.3f m)" % csl[0])
	# --- on a duckboard
	var pd := _spawn(-0.2, 3.6, 0.45)
	await _settle([pd])
	var on_board := 0
	var off_board := 0
	for wp: Vector3 in _wet_points(pd):
		if wp.y > 0.05:
			on_board += 1
		else:
			off_board += 1
	print("      duckboard: %d samples on the board, %d on the floor beside it" % [on_board, off_board])
	_check(on_board > 0, "blood lies on top of a duckboard, not under it")
	# --- gradual: a fresh pool, measured as it grows
	var pg := _spawn(1.6, 2.2, 0.7)
	var series := []
	var t := 0.0
	var settled_at := -1.0
	while t < 13.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if series.size() < int(t) + 1 and t >= series.size():
			series.append(snappedf(pg.progress, 0.01))
		if pg.settled and settled_at < 0.0:
			settled_at = t
	var p_final := pg.progress
	await get_tree().create_timer(1.0).timeout
	print("      growth (progress each second): %s; settled at %.1fs (expand %.1f + settle %.1f)" % [str(series), settled_at, pg.expand, pg.settle])
	_check(series.size() > 3 and series[1] < 0.75 and series[1] > 0.05, "starts small and grows over seconds")
	_check(settled_at > 0.0 and settled_at < pg.expand + pg.settle + 0.6, "settles")
	_check(pg.progress == p_final, "stays put once settled")
	# --- merging: a second body bleeding next to the first
	var before := Blood.pools().size()
	Blood.spawn_pool(_floor_at(1.95, 2.6), Vector3.UP, 0.5)
	await get_tree().process_frame
	_check(Blood.pools().size() == before and pg.sources.size() == 2, "a second source next to a pool joins it, one mesh (%d sources)" % pg.sources.size())
	for f in 120:
		await get_tree().process_frame
		if pg.sampling_done():
			break
	await _settle([pg])
	var grew_on := pg.p_end > 1.0
	_check(grew_on and pg.progress == pg.p_end, "and grows on from there (progress %.2f of %.2f)" % [pg.progress, pg.p_end])
	# --- oil
	var oil0 := Blood.oil_puddle_count()
	Blood.spawn_pool(_floor_at(-2.2, -1.0), Vector3.UP, 0.4, true)
	await get_tree().process_frame
	_check(Blood.oil_puddle_count() == oil0 + 1, "oil still makes an oil puddle")
	if render:
		await _render()
	# --- many at once
	var t0 := Time.get_ticks_usec()
	var worst := 0
	await get_tree().process_frame
	var many: Array = []
	for i in 25:
		many.append(_spawn(randf_range(-6.5, 2.4), randf_range(3.6, 6.5), randf_range(0.25, 0.7)))
	var frames := 0
	var all_done := false
	while not all_done and frames < 900:
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		worst = maxi(worst, Time.get_ticks_usec() - f0)
		frames += 1
		all_done = true
		for p: BloodPool in many:
			if is_instance_valid(p) and not p.sampling_done():
				all_done = false
	var rays := 0
	for p: BloodPool in many:
		if is_instance_valid(p):
			rays += p.rays_used

	print("      25 pools at once: %d rays in all, sampled over %d frames, longest frame %.1f ms (whole frame, headless)" % [rays, frames, worst / 1000.0])
	_check(worst < 40000, "25 pools at once without a long stall (%.1f ms)" % (worst / 1000.0))
	_check(Blood.pools().size() <= Blood.MAX_POOLS, "the pool cap holds (%d)" % Blood.pools().size())


func _spawn(x: float, z: float, r: float) -> BloodPool:
	Blood.spawn_pool(_floor_at(x, z), Vector3.UP, r)
	return Blood.pools().back()


func _render() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 3.0
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	lamp.position = Vector3(2.0, 2.6, 1.6)
	add_child(lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.light_color = Color(1.0, 0.8, 0.55)
	lamp2.light_energy = 2.0
	lamp2.omni_range = 7.0
	lamp2.position = Vector3(-2.5, 2.4, 1.0)
	add_child(lamp2)
	var lamp3 := OmniLight3D.new()
	lamp3.light_color = Color(1.0, 0.8, 0.55)
	lamp3.light_energy = 2.5
	lamp3.omni_range = 6.0
	lamp3.shadow_enabled = true
	lamp3.position = Vector3(6.3, 2.4, 1.6)
	add_child(lamp3)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.make_current()
	var views := [["stairs", Vector3(5.6, 2.3, 2.4), Vector3(4.2, 0.7, 0.5)], ["stairs_side", Vector3(5.9, 2.0, 2.4), Vector3(4.3, 0.8, 0.7)],
		["wall", Vector3(-0.2, 1.4, 0.6), Vector3(-0.8, 0.0, -1.7)], ["sill", Vector3(0.0, 1.3, 1.4), Vector3(0.6, 0.0, -0.2)],
		["open", Vector3(-2.0, 2.2, 3.3), Vector3(-2.0, 0.0, 0.6)], ["slope", Vector3(-2.2, 1.6, 4.6), Vector3(-4.2, 0.1, 3.0)]]
	for v: Array in views:
		cam.position = v[1]
		cam.look_at(v[2])
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/k/pools_%s.png" % v[0])
