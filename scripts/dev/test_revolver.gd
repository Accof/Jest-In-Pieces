extends Node
## The Tripo revolver next to the procedural pistol: both fire and hurt
## clowns, switching works (by the 7 and 1 keys), ammunition and reloads are
## separate, the revolver is one shot per pull, kicks the view up and comes
## back, and its flash is at its own muzzle. Pass --render for
## /tmp/revolver_*.png (idle, fired, mid-reload, the pistol for comparison).
var render := false
var failed := 0


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


## Checks that depend on real time: skipped when rendering (the software
## renderer runs at a few frames a second).
func _timed(ok: bool, what: String) -> void:
	if render:
		print("   --    %s (not timed when rendering)" % what)
		return
	_check(ok, what)


func _check(ok: bool, what: String) -> void:
	print("   %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/revolver_%s.png" % name_)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	_player._unhandled_input(e)


var _player: FpsPlayer


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for n in room.get_children():
		if n is ExplosiveBarrel:
			n.queue_free()
	var p: FpsPlayer = room.player
	_player = p
	var clowns: Array[Clown] = []
	for c: Clown in room.clowns:
		clowns.append(c)
	# two clowns side by side in front, the rest out of the way
	for i in clowns.size():
		var c := clowns[i]
		if i < 2:
			c.global_position = Vector3(-0.9 + i * 1.8, 0, -4.0)
			c.rotation.y = 0.0
		else:
			c.global_position = Vector3(7, 0, -9 - i)
	p.global_position = Vector3(0, 0.05, 1.5)
	p.rotation.y = 0.0
	await _frames(30)

	# --- the pistol as it was
	var pw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	_check(pw.name == "Pistol" and pw.damage == 34.0 and pw.cooldown == 0.22 and pw.mag == 17 and pw.spread == 0.0 and pw.impulse == 14.0 and not pw.has("semi"), "pistol stats unchanged")
	_check(p.weapon == FpsPlayer.PISTOL and p.ammo[FpsPlayer.PISTOL] == 17 and p.ammo[FpsPlayer.REVOLVER] == 6, "start: pistol in hand, 17 in the pistol, 6 in the revolver")
	await _shot("3_pistol")
	var a: Clown = clowns[0]
	var b: Clown = clowns[1]
	p.camera.look_at(a.ragdoll.bones[&"Chest"].global_position)
	var ha := a.health
	p.fire()
	await _frames(10)
	var pistol_dmg := ha - a.health
	_check(p.ammo[FpsPlayer.PISTOL] == 16 and p.ammo[FpsPlayer.REVOLVER] == 6, "a pistol shot uses a pistol round only")
	_check(pistol_dmg > 0.0, "the pistol hurts a clown (%.0f)" % pistol_dmg)

	# --- to the revolver by its key
	_key(KEY_7)
	await _wait(ViewModel.SWAP_TIME + 0.1)
	_check(p.weapon == FpsPlayer.REVOLVER and p.view.weapon == ViewModel.REVOLVER, "7 selects the revolver")
	var shown := 0
	for gi in p.view._guns.size():
		if p.view._guns[gi].visible:
			shown += 1
	_check(shown == 1 and p.view._guns[ViewModel.REVOLVER].visible, "only the revolver is shown")
	var meshes := p.view._guns[ViewModel.REVOLVER].find_children("*", "MeshInstance3D", true, false)
	var tex_ok := false
	for mi: MeshInstance3D in meshes:
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		tex_ok = m != null and m.albedo_texture != null and m.normal_texture != null and m.roughness_texture != null and m.metallic_texture != null
	_check(meshes.size() == 1 and tex_ok, "the revolver is the Tripo mesh with its colour, normal and metal/rough textures (no procedural hands)")
	# placement: lower right, ahead of the eye, barrel along the view
	var cam := p.camera
	var muzzle_cam := cam.to_local(p.view._rev_muzzle.global_position)
	var model := p.view._rev_model
	var barrel_dir := cam.global_basis.inverse() * (model.global_basis * Vector3.RIGHT).normalized()
	print("      muzzle in camera space %s, barrel direction %s" % [muzzle_cam, barrel_dir])
	_check(muzzle_cam.x > 0.0 and muzzle_cam.y < 0.0 and muzzle_cam.z < -0.1 and muzzle_cam.z > -0.4, "the gun sits low on the right, in front of the eye and inside the body (no clipping)")
	_check(barrel_dir.dot(Vector3.FORWARD) > 0.99, "the barrel points where the player looks")
	await _shot("0_idle")

	# --- a revolver shot
	p.camera.look_at(b.ragdoll.bones[&"Chest"].global_position)
	var pitch0 := p.camera.rotation.x
	var hb := b.health
	p.fire()
	await get_tree().process_frame
	var kicked := p.view._kick
	var flash_at := p.view._flash_mesh.global_position
	_timed(p.view._flash_mesh.visible and flash_at.distance_to(p.view._rev_muzzle.global_position) < 0.002, "the flash is at the revolver's muzzle")
	if render:
		p.view._since_shot = -20.0                   # hold the flash for the slow software frames
		p.view._flash.light_energy = 10.0
		p.view._flash_mesh.visible = true
	await _shot("1_fired")
	await _frames(4)
	var climbed := p.camera.rotation.x - pitch0
	await _frames(10)
	var rev_dmg := hb - b.health if not b.dead else hb
	_check(p.ammo[FpsPlayer.REVOLVER] == 5 and p.ammo[FpsPlayer.PISTOL] == 16, "a revolver shot uses a revolver round only")
	_check(rev_dmg > pistol_dmg, "the revolver hits harder than the pistol (%.0f vs %.0f)" % [rev_dmg, pistol_dmg])
	_timed(climbed > deg_to_rad(1.0), "the view kicks up (%.1f deg)" % rad_to_deg(climbed))
	_timed(kicked > 0.9, "the gun recoils in the hand")
	await _wait(0.9)
	_timed(absf(p.camera.rotation.x - pitch0) < deg_to_rad(0.3), "and settles back on target (%.2f deg off)" % rad_to_deg(p.camera.rotation.x - pitch0))
	# one shot per pull: a second pull during the cooldown is not a second shot
	var before := p.ammo[FpsPlayer.REVOLVER]
	p.fire()
	await _frames(2)
	p.fire()
	await _wait(0.6)
	_check(before - p.ammo[FpsPlayer.REVOLVER] == 1, "a second pull 30 ms later is not a second shot (fired %d)" % (before - p.ammo[FpsPlayer.REVOLVER]))
	# about two shots a second when pulled as fast as it allows
	p.camera.rotation.x = 0.0
	var t0 := Time.get_ticks_msec()
	var n0 := p.ammo[FpsPlayer.REVOLVER]
	while p.ammo[FpsPlayer.REVOLVER] > 1 and Time.get_ticks_msec() - t0 < 3000:
		p.fire()
		await get_tree().physics_frame
	var shots := n0 - p.ammo[FpsPlayer.REVOLVER]
	var rate := (shots - 1) / maxf((Time.get_ticks_msec() - t0) / 1000.0, 0.01)
	print("      %d shots, about %.1f a second" % [shots, rate])
	_timed(rate > 1.6 and rate < 2.4, "about two shots a second")

	# --- reloads are separate
	await _wait(0.6)
	var pistol_before := p.ammo[FpsPlayer.PISTOL]
	p.camera.rotation.x = 0.0
	p.reload()
	_check(p.view.reloading(), "the revolver reloads")
	await _wait(1.0)
	await _shot("2_reload")
	_check(p.ammo[FpsPlayer.REVOLVER] == 1, "not loaded yet a second in")
	await _wait(2.2)
	_check(p.ammo[FpsPlayer.REVOLVER] == 6 and not p.view.reloading(), "six in after about three seconds")
	_check(p.ammo[FpsPlayer.PISTOL] == pistol_before, "the pistol's magazine is untouched by the revolver's reload")
	# fire one, then swap away mid-reload: the reload is abandoned, nothing changes
	p.fire()
	await _wait(0.6)
	p.reload()
	await _wait(0.5)
	_key(KEY_1)
	await _wait(ViewModel.SWAP_TIME + 0.1)
	_check(p.weapon == FpsPlayer.PISTOL and p.ammo[FpsPlayer.REVOLVER] == 5, "1 goes back to the pistol; the half-done revolver reload is abandoned")
	# the pistol empties and reloads on its own count
	while p.ammo[FpsPlayer.PISTOL] > 0:
		p.fire()
		await get_tree().physics_frame
	p.reload()
	await _wait(ViewModel.PISTOL_RELOAD + 0.2)
	_check(p.ammo[FpsPlayer.PISTOL] == 17 and p.ammo[FpsPlayer.REVOLVER] == 5, "the pistol reloads to 17; the revolver still has 5")
	# the pistol still repeats when held (only the revolver is semi)
	_check(not FpsPlayer.WEAPONS[FpsPlayer.PISTOL].get("semi", false) and FpsPlayer.WEAPONS[FpsPlayer.REVOLVER].get("semi", false), "only the revolver is one shot per pull")
	print("REVOLVER: %d failed" % failed)
	get_tree().quit()
