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
	var names := {}
	for mi: MeshInstance3D in meshes:
		names[String(mi.name)] = true
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if String(mi.name) == "Frame":
			tex_ok = m != null and m.albedo_texture != null and m.normal_texture != null and m.roughness_texture != null and m.metallic_texture != null
	var parts_ok := true
	for n in ["Frame", "BarrelAssembly", "Cylinder", "Extractor", "Hammer", "Trigger", "Round_1", "Round_6", "Case_1", "Case_6"]:
		parts_ok = parts_ok and names.has(n)
	_check(p.view._rv_parts and parts_ok, "the revolver is the parts model: frame, barrel, cylinder, extractor, hammer, trigger, six rounds and six cases")
	_check(tex_ok, "the frame keeps the Tripo colour, normal and metal/rough textures (no procedural hands)")
	var vis_rounds := 0
	var vis_cases := 0
	for c in 6:
		vis_rounds += int(p.view._rv_rounds[c].visible)
		vis_cases += int(p.view._rv_cases[c].visible)
	_check(vis_rounds == 6 and vis_cases == 0, "six live rounds in the cylinder, no fired cases")
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
	_check(p.view.rv_index == 1 and p.view._rv_cases[0].visible and not p.view._rv_rounds[0].visible, "the fired chamber now holds a fired case")
	_check(absf(p.view._rv_cyl.rotation.x - PI / 3.0) < 0.02, "the cylinder turned one chamber (%.1f deg)" % rad_to_deg(p.view._rv_cyl.rotation.x))
	_timed(absf(p.view._rv_barrel.rotation.z) < 0.001 and absf(p.view._rv_hammer.rotation.z) < 0.01, "barrel shut, hammer down after the shot")
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
	var spent_before := get_tree().get_nodes_in_group("spent_brass").size()
	p.reload()
	_check(p.view.reloading(), "the revolver reloads")
	await _wait(0.56)
	await _shot("2_open")
	var open_deg := rad_to_deg(p.view._rv_barrel.rotation.z)
	_check(open_deg < -55.0, "the barrel has broken open on its hinge (%.0f deg)" % open_deg)
	var frame_still := p.view._rev_model.find_child("Frame", true, false) as Node3D
	_check(frame_still.position.is_zero_approx() and frame_still.rotation.is_zero_approx(), "the frame does not move: the barrel turns on the pin")
	var spent := p.view.rv_spent
	var in_gun := 0
	for c in 6:
		in_gun += int(p.view._rv_rounds[c].visible) + int(p.view._rv_cases[c].visible)
	_check(spent.size() == 6 and get_tree().get_nodes_in_group("spent_brass").size() == spent_before + 6, "the extractor threw all six out of the cylinder (%d bodies)" % spent.size())
	_timed(in_gun == 0, "nothing left in the cylinder just after the throw")
	var near := 9.0
	for sb in spent:
		if is_instance_valid(sb):
			near = minf(near, sb.global_position.distance_to(p.camera.global_position))
	_check(near > 0.25 and near < 1.2, "the brass is out in the world at full size, in front of the player (%.2f m)" % near)
	await _wait(0.9)
	await _shot("4_loading")
	_check(p.ammo[FpsPlayer.REVOLVER] == 1, "not loaded yet a second and a half in")
	var going_in := 0
	for c in 6:
		going_in += int(p.view._rv_rounds[c].visible)
	_check(going_in > 0 and going_in < 6, "the new rounds are going in one at a time (%d in)" % going_in)
	await _wait(0.72)
	await _shot("5_closing")
	await _wait(1.1)
	_check(p.ammo[FpsPlayer.REVOLVER] == 6 and not p.view.reloading(), "six in after about three seconds")
	var all_live := true
	for c in 6:
		all_live = all_live and p.view.rv_live[c] and p.view._rv_rounds[c].visible and not p.view._rv_cases[c].visible
	_check(all_live and absf(p.view._rv_barrel.rotation.z) < 0.001 and absf(p.view._rv_ext.position.x) < 0.0001, "shut again with six live rounds, extractor home")
	var landed := 0
	for sb in spent:
		if is_instance_valid(sb) and sb.global_position.y < 0.6 and sb.global_position.y > -0.2:
			landed += 1
	_check(landed >= 4, "the brass fell to the floor (%d of 6)" % landed)
	_check(p.ammo[FpsPlayer.PISTOL] == pistol_before, "the pistol's magazine is untouched by the revolver's reload")
	# fire one, then swap away mid-reload: the reload is abandoned, nothing changes
	p.fire()
	await _wait(0.6)
	p.reload()
	await _wait(0.5)
	_key(KEY_1)
	await _wait(ViewModel.SWAP_TIME + 0.1)
	_check(p.weapon == FpsPlayer.PISTOL and p.ammo[FpsPlayer.REVOLVER] == 5, "1 goes back to the pistol; the half-done revolver reload is abandoned")
	var live_n := 0
	for c in 6:
		live_n += int(p.view.rv_live[c])
	_check(live_n == 5 and absf(p.view._rv_barrel.rotation.z) < 0.001, "the revolver's chambers still say five live, one fired, and it is shut")
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
