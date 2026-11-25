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
	# pin the body/limb chances for the deterministic checks; 1c tests the odds
	# a splash (a bleeding body hitting a wall; the gore module placed the
	# mark): no mark from here, drops only
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.0, -2.9), Vector3(0, 0.3, 1).normalized(), 1.5, false, "splash")
	await _frames(2)
	_check(_count("mist") == 0 and _count("heavy") == 0, "a splash adds no mark of its own")
	Blood.BODY_MARK_CHANCE = 1.0
	Blood.BODY_PLUME_CHANCE = 1.0
	Blood.LIMB_MARK_CHANCE = 1.0
	Blood.LIMB_PLUME_CHANCE = 1.0
	# 1. a rifle chest hit, 1.5 m from the wall: one mist of the right size, a
	#    few small drops, no mass; back spatter and floor drops
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.3, -1.5), Vector3(0, -0.05, -1).normalized(), 1.0, false, "", "Rifle", 11)
	await _frames(2)
	var mists := _count("mist")
	var smalls := _count("small")
	_check(mists == 1, "rifle at 1.5 m: one mist on the wall and no second mark over it: %d" % mists)
	_check(_count("impact") == 0 and _count("heavy") == 0, "rifle at 1.5 m: no mass, it is a mist")
	_check(smalls >= 1 and smalls <= 3, "rifle: a drop or two beneath, none on the wall (%d)" % smalls)
	var big := 0.0
	for e in _decals():
		if _kind(e.tex) == "mist" and e.pos.z < -2.5:
			big = maxf(big, maxf(e.size.x, e.size.z) * Blood.SPLAT2_FILL.mist)
	_check(big >= 0.4 and big <= 0.75, "rifle body mist on the wall is %.2f m across (0.4-0.75: a body shot, not a headshot)" % big)
	var total := _decals().size()
	_check(total <= 4, "a rifle body hit spends at most 4 decals (%d)" % total)
	var wall_marks := 0
	for e in _decals():
		if e.pos.z < -2.5:
			wall_marks += 1
	_check(wall_marks == 1, "and exactly one of them is on the wall (%d)" % wall_marks)
	# 1b. (25 Nov) tiers: a body shot reaches 1.6 m and no farther - a wall
	#     across the room gets nothing; a limb shot is small; a headshot has
	#     the reach and the mass
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.3, -0.6), Vector3(0, -0.05, -1).normalized(), 1.6, false, "", "Rifle", 15)
	await _frames(2)
	var far_wall := 0
	for e in _decals():
		if e.pos.z < -2.5:
			far_wall += 1
	_check(far_wall == 0, "a rifle body shot 2.4 m from the wall marks nothing on it (%d)" % far_wall)
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.3, -0.6), Vector3(0, -0.05, -1).normalized(), 1.6, false, "head", "Rifle", 16)
	await _frames(2)
	far_wall = 0
	for e in _decals():
		if e.pos.z < -2.5:
			far_wall += 1
	_check(far_wall >= 3 and _count("heavy") == 1, "the same shot to the head reaches it: %d marks and the heavy" % far_wall)
	Blood.clear()
	Blood.spawn_hit(Vector3(0, 1.0, -2.0), Vector3(0, -0.05, -1).normalized(), 1.6, false, "limb", "Rifle", 17)
	await _frames(2)
	big = 0.0
	for e in _decals():
		if _kind(e.tex) == "mist":
			big = maxf(big, maxf(e.size.x, e.size.z) * Blood.SPLAT2_FILL.mist)
	_check(big > 0.0 and big <= 0.42 and _decals().size() <= 2, "a limb hit: a small mist (%.2f m) and at most 2 decals (%d)" % [big, _decals().size()])
	# 1c. the odds: a pistol round stays in the body - no wall mark, no plume;
	#     rifle body shots mark the wall about 7 times in 10, limbs 4 in 10
	Blood.BODY_MARK_CHANCE = 0.7
	Blood.BODY_PLUME_CHANCE = 0.5
	Blood.LIMB_MARK_CHANCE = 0.4
	Blood.LIMB_PLUME_CHANCE = 0.3
	Blood.clear()
	var sp0: int = Blood.sprays
	for k in 40:
		Blood.spawn_hit(Vector3(0, 1.3, -2.0), Vector3(0, -0.05, -1).normalized(), 0.3 + 0.015 * k, false, "", "Pistol", 100 + k)
	await _frames(2)
	wall_marks = 0
	for e in _decals():
		if e.pos.z < -2.5:
			wall_marks += 1
	_check(wall_marks == 0 and Blood.sprays == sp0, "40 pistol body hits: nothing on the wall, no plume (%d marks, %d plumes)" % [wall_marks, Blood.sprays - sp0])
	Blood.clear()
	sp0 = Blood.sprays
	for k in 100:
		Blood.spawn_hit(Vector3(0, 1.3, -2.0), Vector3(0, -0.05, -1).normalized(), 1.6, false, "", "Rifle", 200 + k)
	await _frames(2)
	var rifle_mists := _count("mist")
	_check(rifle_mists >= 55 and rifle_mists <= 85, "100 rifle body hits: about 70 exit mists (%d)" % rifle_mists)
	_check(Blood.sprays - sp0 >= 35 and Blood.sprays - sp0 <= 65, "and about 50 small plumes (%d)" % (Blood.sprays - sp0))
	Blood.clear()
	for k in 100:
		Blood.spawn_hit(Vector3(0, 1.0, -2.2), Vector3(0, -0.05, -1).normalized(), 1.6, false, "limb", "Rifle", 300 + k)
	await _frames(2)
	var limb_mists := _count("mist")
	_check(limb_mists >= 25 and limb_mists <= 55, "100 limb hits: about 40 small marks (%d)" % limb_mists)
	Blood.BODY_MARK_CHANCE = 1.0
	Blood.BODY_PLUME_CHANCE = 1.0
	Blood.LIMB_MARK_CHANCE = 1.0
	Blood.LIMB_PLUME_CHANCE = 1.0
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
	_check(_decals().size() <= 24, "and the whole charge spends at most 24 decals (%d)" % _decals().size())
	_check(_count("impact") == 1, "eight pellets on one body is a close charge: the impact mass goes on (%d)" % _count("impact"))
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
	# 8b. (Phase C) spray: a hit fires a plume and a haze; the plume's life is
	#     cut to the wall behind; the droplets are drawn while they fly and
	#     gone from the draw when they have landed
	Blood.clear()
	await _frames(2)
	var sprays0: int = Blood.sprays
	Blood.spawn_hit(Vector3(0, 1.3, -1.7), Vector3(0, -0.05, -1), 1.0, false, "", "Rifle", 77)
	_check(Blood.sprays == sprays0 + 1, "a rifle hit fires one plume (%d)" % (Blood.sprays - sprays0))
	var last_plume: GPUParticles3D = Blood._plumes[(Blood._plume_next - 1 + Blood.PLUMES) % Blood.PLUMES]
	_check(last_plume.emitting and last_plume.lifetime < 0.32 and last_plume.lifetime > 0.1, "the body plume is emitting and lives only to the wall 1.3 m behind (%.2f s)" % last_plume.lifetime)
	var pm0 := last_plume.process_material as ParticleProcessMaterial
	_check(pm0.initial_velocity_max <= 5.0 and last_plume.amount_ratio <= 0.36, "a body plume is slow and sparse (%.0f m/s, ratio %.2f)" % [pm0.initial_velocity_max, last_plume.amount_ratio])
	var last_haze: GPUParticles3D = Blood._hazes[(Blood._haze_next - 1 + Blood.HAZES) % Blood.HAZES]
	_check(not last_haze.emitting, "a body shot has no haze")
	await _frames(1)
	var drawn: int = Blood._drop_mm.visible_instance_count
	_check(drawn >= 1 and drawn <= 2 and drawn == Blood._drop_pos.size(), "its drop or two is drawn, one quad each (%d)" % drawn)
	await _frames(240)
	var wall_after := 0
	for e in _decals():
		if e.pos.z < -2.5 and absf(e.up.y) < 0.5:       # on the wall (a decal's Y is its projection axis, the surface normal)
			wall_after += 1
	_check(wall_after == 1, "and when they have landed the wall still has its one mark (%d)" % wall_after)
	# a headshot's droplets: many, some flying with the plume
	Blood.spawn_hit(Vector3(0, 1.6, -1.7), Vector3(0, -0.05, -1), 1.4, false, "head", "Revolver", 81)
	last_haze = Blood._hazes[(Blood._haze_next - 1 + Blood.HAZES) % Blood.HAZES]
	_check(last_haze.emitting and last_haze.lifetime > 1.0, "a headshot's haze hangs for over a second (%.1f s)" % last_haze.lifetime)
	await _frames(1)
	drawn = Blood._drop_mm.visible_instance_count
	_check(drawn >= 8 and drawn == Blood._drop_pos.size(), "a headshot's droplets are drawn, one quad each (%d)" % drawn)
	var fast := 0
	for v: Vector3 in Blood._drop_vel:
		if v.length() >= Blood.PLUME_SPEED_MIN * 0.8:
			fast += 1
	_check(fast >= 2, "some of them fly with the plume, fast enough to draw as strings (%d)" % fast)
	await _frames(240)
	_check(Blood._drop_mm.visible_instance_count == 0, "and the draw is empty once they have all landed (%d)" % Blood._drop_mm.visible_instance_count)
	# the spray into open air: the plume lives its full span
	Blood.spawn_hit(Vector3(0, 1.3, 6.0), Vector3(0, 0.3, 1), 1.0, false, "head", "Rifle", 78)
	last_plume = Blood._plumes[(Blood._plume_next - 1 + Blood.PLUMES) % Blood.PLUMES]
	pm0 = last_plume.process_material as ParticleProcessMaterial
	_check(is_equal_approx(last_plume.lifetime, Blood.PLUME_LIFE) and pm0.initial_velocity_max == Blood.PLUME_SPEED_MAX, "into open air a headshot's plume lives its full %.2f s at %.0f m/s" % [last_plume.lifetime, pm0.initial_velocity_max])
	# pellets share one spray
	var s0: int = Blood.sprays
	for k in 6:
		Blood.spawn_hit(Vector3(0, 1.3, 6.0), Vector3(0, 0.3, 1), 0.5, false, "", "Trench Shotgun", 79)
	_check(Blood.sprays == s0 + 1, "six pellets of one shot fire one spray, not six (%d)" % (Blood.sprays - s0))
	last_haze = Blood._hazes[(Blood._haze_next - 1 + Blood.HAZES) % Blood.HAZES]
	s0 = Blood.sprays
	Blood.spawn_hit(Vector3(0, 1.0, 6.0), Vector3(0, 0.3, 1), 1.6, false, "limb", "Rifle", 80)
	_check(Blood.sprays == s0 + 1 and Blood._hazes[(Blood._haze_next - 1 + Blood.HAZES) % Blood.HAZES] == last_haze, "a limb hit: a few strings and no haze")

	# 9. (Phase D) persistence: a big mark placed first outlives 1,300 small
	#    ones that follow; recycling takes the small and the far first; a
	#    recycled mark fades on a spare instead of popping
	Blood.clear()
	Blood.spawn_decal(Vector3(0, 1.2, -2.99), Vector3(0, 0, 1), 1.2, "mist", Vector3.UP)
	var first: Decal = null
	for d: Decal in Blood._decals:
		if d.visible:
			first = d
	Blood.recycled = 0
	for i in 1300:
		Blood.spawn_decal(Vector3(randf_range(-6, 6), 0.0, randf_range(-2.5, 6)), Vector3.UP, randf_range(0.03, 0.1), "small")
	await _frames(2)
	_check(first != null and first.visible and first.texture_albedo.resource_path.contains("mist"), "the 1.2 m mist placed first is still there after 1,300 small drops")
	_check(Blood.recycled >= 100 and Blood.recycled <= 160, "about a hundred small drops were recycled for them (%d)" % Blood.recycled)
	_check(Blood._fading.size() > 0 and Blood._fading.size() <= Blood.SPARE_DECALS, "recycled marks are fading on spares (%d)" % Blood._fading.size())
	var visible := 0
	for d: Decal in Blood._decals:
		if d.visible:
			visible += 1
	_check(visible == Blood.MAX_DECALS, "the pool is full and every slot shows a mark (%d)" % visible)
	await _frames(int(Blood.FADE_OUT * 60) + 10)
	_check(Blood._fading.is_empty() and Blood._spares.size() == Blood.SPARE_DECALS, "and the fades finished, spares all back (%d)" % Blood._spares.size())
	print("BLOOD: %d failed" % fails)
	get_tree().quit()
