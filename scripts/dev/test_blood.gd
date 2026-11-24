extends Node3D
## The blood overhaul's placement (Phase B, 24 Nov 2026): a wall and a floor,
## the regimes fired at them through the real Blood autoload, and what lands
## counted by kind and measured. No rendering.
##   godot --headless --fixed-fps 60 --path . res://scenes/test_blood.tscn

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("   %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _box(size: Vector3, at: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = at
	b.collision_layer = 1
	add_child(b)


## The visible decals, as [kind, size (the shape's, metres), position, normal-ish].
func _decals() -> Array:
	var out := []
	for i in Blood._decals.size():
		var d: Decal = Blood._decals[i]
		if d.visible:
			out.append({tex = d.texture_albedo.resource_path, size = d.size, pos = d.global_position, up = d.global_basis.y})
	return out


func _kind(tex: String) -> String:
	for k in Blood.SPLAT2_KINDS:
		if tex.contains("splat_%s_" % k):
			return k
	return "?"


func _count(kind: String) -> int:
	var n := 0
	for e in _decals():
		if _kind(e.tex) == kind:
			n += 1
	return n


func _ready() -> void:
	_box(Vector3(40, 0.2, 40), Vector3(0, -0.1, 0))          # floor
	_box(Vector3(40, 6, 0.2), Vector3(0, 3, -3.1))           # wall at z = -3
	await _frames(3)
	await _run()


func _run() -> void:
	print("-- blood placement")
	Blood._rng.seed = 7
	# 1. a rifle chest hit, 1.5 m from the wall: one mist of the right size, a
	#    few small drops, no mass; back spatter and floor drops
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.3, -1.5), Vector3(0, -0.05, -1).normalized(), 1.0, false, "", "Rifle", 11)
	await _frames(2)
	var mists := _count("mist")
	var smalls := _count("small")
	_check(mists >= 1 and mists <= 2, "rifle at 1.5 m: one mist on the wall (+ a back-spatter mist at most): %d" % mists)
	_check(_count("impact") == 0 and _count("heavy") == 0, "rifle at 1.5 m: no mass, it is a mist")
	_check(smalls >= 4, "rifle: small drops round it, behind and beneath (%d)" % smalls)
	var big := 0.0
	for e in _decals():
		if _kind(e.tex) == "mist" and e.pos.z < -2.5:
			big = maxf(big, maxf(e.size.x, e.size.z) * Blood.SPLAT2_FILL.mist)
	_check(big >= 0.8 and big <= 1.5, "rifle mist on the wall is %.2f m across (0.8-1.5 by distance and amount)" % big)
	var total := _decals().size()
	_check(total <= 24, "a rifle hit spends at most 24 decals (%d)" % total)
	# 2. a revolver headshot close to the wall: heavy with drips on the mist,
	#    the heavy's up along the world's up
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.6, -2.2), Vector3(0.05, -0.1, -1).normalized(), 1.4, false, "head", "Revolver", 12)
	await _frames(2)
	_check(_count("heavy") == 1, "revolver headshot at 0.8 m: a heavy mass on the wall (%d)" % _count("heavy"))
	var up_ok := true
	for e in _decals():
		if _kind(e.tex) == "heavy":
			up_ok = up_ok and e.up.dot(Vector3(0, 0, 1)) > 0.9 and absf(e.up.y) < 0.2      # projected onto the wall, drips hanging down (texture up = world up = decal -Z)
	_check(up_ok, "the heavy sits flat on the wall")
	# 3. a shotgun's pellets share one mark
	Blood.clear()
	for k in 8:
		Blood.spawn_hit(Vector3(randf_range(-0.1, 0.1), 1.2 + randf_range(-0.1, 0.1), -1.0), Vector3(randf_range(-0.05, 0.05), -0.1, -1).normalized(), 0.5, false, "", "Trench Shotgun", 13)
	await _frames(2)
	var wall_mists := 0
	for e in _decals():
		if _kind(e.tex) == "mist" and e.pos.z < -2.5:
			wall_mists += 1
	_check(wall_mists == 1, "eight pellets of one shot: one fan on the wall, not eight (%d)" % wall_mists)
	_check(_decals().size() <= 40, "and the whole charge spends at most 40 decals (%d)" % _decals().size())
	# 4. a graze along the wall: a streak
	Blood.clear()
	Blood.spawn_hit(Vector3(-0.5, 1.2, -2.85), Vector3(0.95, -0.05, -0.3).normalized(), 1.0, false, "", "Rifle", 14)
	await _frames(2)
	_check(_count("streak") >= 1, "a graze along the wall leaves a streak (%d)" % _count("streak"))
	# 5. cast-off: a fast thing passing the wall throws an arc on it
	Blood.clear()
	Blood.cast_off(Vector3(0, 1.0, -2.4), Vector3(3.0, 1.0, -1.0), 1.0)
	await _frames(2)
	_check(_count("castoff") == 1, "cast-off beside the wall: one arc (%d)" % _count("castoff"))
	Blood.clear()
	Blood.cast_off(Vector3(0, 3.0, 5.0), Vector3(3.0, 1.0, -1.0), 1.0)
	await _frames(2)
	_check(_count("castoff") == 0, "cast-off with nothing within reach: nothing")
	# 6. drip field on a wall
	Blood.clear()
	Blood.drip_field(Vector3(0, 1.1, -2.99), Vector3(0, 0, 1), 1.0)
	await _frames(2)
	_check(_count("dripfield") == 1, "a drip field placed (%d)" % _count("dripfield"))
	# 7. every decal re-raycast: none floating in the air (within 0.25 m of the wall or the floor)
	Blood.clear()
	for i in 6:
		Blood.spawn_hit(Vector3(randf_range(-2, 2), randf_range(0.8, 1.6), randf_range(-2.4, -0.6)), Vector3(randf_range(-0.4, 0.4), randf_range(-0.5, 0.1), -1).normalized(), randf_range(0.5, 1.5), false, "", "Rifle", 20 + i)
	await _frames(2)
	var floating := 0
	for e in _decals():
		var p: Vector3 = e.pos
		if absf(p.z + 3.0) > 0.25 and absf(p.y) > 0.25:
			floating += 1
	_check(floating == 0, "no decal floats: all on the wall or the floor (%d of %d off)" % [floating, _decals().size()])
	# 8. depth by size
	var depth_ok := true
	for e in _decals():
		var sz: float = maxf(e.size.x, e.size.z)
		if e.size.y > 0.41 or e.size.y < 0.11:
			depth_ok = false
	_check(depth_ok, "decal depth stays 0.12-0.4 m (by size)")
	print("BLOOD: %d failed" % fails)
	get_tree().quit()
