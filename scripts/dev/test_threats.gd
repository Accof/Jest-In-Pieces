extends Node3D
## The Drowned Front's core combat hazards (Milestone 6), checked.
## Sections (user args; none = all):
##   nests     the machine guns are on their fire row, facing our lines, with a
##             clear view over the parapet; their arcs leave a flank; each has
##             a live gunner behind it
##   fire      a standing player in the open in a gun's arc is fired on: real
##             rays - rounds hit the ground (Impacts) and the player (counted,
##             god mode); behind the lip of a shell hole, crouched, the gun
##             loses him and the hits stop; rounds cracking past press on him
##             (suppression rises, then eases)
##   pauses    a minute under fire has pauses in it: bursts, a belt change, a
##             boil-over - the longest gap is seconds, a window
##   crew      the gunner shot dead silences the gun and leaves the piece to be
##             taken; the mechanism shot to pieces jams it
##   shells    a salvo whistles for 2.4 s before each shell, never aims within
##             7.5 m of the player, lands in the fair zone, puts nearby soldiers'
##             heads down; between salvos there is a lull
##   crouch    a soldier's eye reads the crouch: standing behind a chest-high
##             wall you are seen, crouched you are not
##   look      (with "render", Forward+) /tmp/threats_nest.png: a gun on their parapet
##             firing at the player out on the field; /tmp/threats_shell.png: a shell landing
##   godot --headless --fixed-fps 60 res://scenes/test_threats.tscn [-- section... render]

var fails := 0
var game: Node3D


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
	var secs := ["nests", "fire", "pauses", "crew", "shells", "crouch", "look"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("THREATS: %d failed" % fails)
	get_tree().quit()


func _new_game(seed_: int) -> void:
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
	game.floor_number = 2
	game.next_floor()
	await _frames(3)


func _threats() -> FrontThreats:
	return game.threats as FrontThreats


## No fog banks: these sections are about the guns, not the weather.
func _clear_sky() -> void:
	var atm: FrontAtmosphere = get_tree().get_first_node_in_group(&"fog")
	if atm and atm.front_fog is FrontFog:
		(atm.front_fog as FrontFog).clear_banks()
		atm.front_fog.set_physics_process(false)
		atm.front_fog.set_process(false)
	if atm:
		atm.smoke_patches.clear()                 # the drifting shell-hole smoke thins sight too


## Put the player on open ground `dist` m in front of a nest, in its arc -
## on the flat, not down a shell hole (slides sideways to find flat ground).
var _stand_side := {}
func _stand_before(mg: FrontMg, dist: float, side := 0.0) -> void:
	var pl: FpsPlayer = game.player
	var m := game.maze as FrontMaze
	var key := "%s/%.0f/%.1f" % [mg.name, dist, side]
	if not _stand_side.has(key):
		var best := side
		for k in 14:
			var try_side: float = side + (k * 1.2 if k % 2 == 0 else -(k + 1) * 1.2)
			var p: Vector3 = mg.global_position + mg.facing * dist + mg.facing.cross(Vector3.UP) * try_side
			var in_hole := false
			for cr: Vector4 in m.crater_list:
				if Vector2(p.x - cr.x, p.z - cr.y).length() < cr.z + 0.8:
					in_hole = true
			if in_hole:
				continue
			# and the gun must be able to see a man standing there
			p.y = m.ground_height(p.x, p.z) + 0.1
			pl.global_position = p
			if mg._sees_target():
				best = try_side
				break
		_stand_side[key] = best
	var at: Vector3 = mg.global_position + mg.facing * dist + mg.facing.cross(Vector3.UP) * float(_stand_side[key])
	at.y = m.ground_height(at.x, at.z) + 0.1
	pl.global_position = at
	pl.velocity = Vector3.ZERO


## The nest to shoot at in the fire tests: the one on the fire row proper
## (an OP's gun sits out in a sap, with the sap's own mound about it).
func _main_nest(th: FrontThreats) -> FrontMg:
	var best: FrontMg = th.nests[0]
	for mg in th.nests:
		if mg.global_position.z < best.global_position.z:
			best = mg
	return best


## A shell hole deep enough to hide a crouched man, in front of a nest.
func _hole_before(mg: FrontMg) -> Vector4:
	var m := game.maze as FrontMaze
	var best := Vector4.ZERO
	var best_d := INF
	for cr: Vector4 in m.crater_list:
		if cr.w < 1.1 or cr.z < 2.6:
			continue
		var p := Vector3(cr.x, 0, cr.y)
		var rel := p - mg.global_position
		var d := rel.length()
		if d < 14.0 or d > 60.0:
			continue
		if mg.facing.dot(rel.normalized()) < 0.8:
			continue
		if d < best_d:
			best_d = d
			best = cr
	return best


# --- nests -----------------------------------------------------------------------------
func _nests() -> void:
	print("-- nests")
	await _new_game(1916)
	var th := _threats()
	_check(th != null and th.nests.size() >= 1, "the Front has machine guns (%d)" % (th.nests.size() if th else 0))
	if th == null or th.nests.is_empty():
		return
	var m := game.maze as FrontMaze
	var fire_z := (m.their_row0 + TrenchMaze.GRID_D - TrenchMaze.FIRE_ROW) * m.cell + 1.5
	for mg in th.nests:
		var on_row: bool = absf(mg.global_position.z - fire_z) < m.cell * 2.0 or str(m.kind.get(m.cell_of(mg.global_position - mg.facing * 2.5), "")) == "op"
		var faces_us := mg.facing.z > 0.9
		var above := mg.global_position.y > m.ground_height(mg.global_position.x, mg.global_position.z) - 0.05
		# a clear view from the muzzle to a man 30 m out
		var to := mg.global_position + mg.facing * 30.0
		to.y = m.ground_height(to.x, to.z) + 1.2
		var q := PhysicsRayQueryParameters3D.create(mg.muzzle(), to, 1)
		q.exclude = [mg.gun.get_rid()]
		var clear := get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		_check(on_row and faces_us and above and clear, "%s at %s: on their fire row, facing our lines, on the lip, clear view 30 m out" % [mg.name, mg.global_position.snapped(Vector3.ONE * 0.1)])
		_check(mg.gunner != null and not mg.gunner.dead and mg.gunner.global_position.distance_to(mg.global_position) < 3.0, "%s has a live gunner %.1f m behind it" % [mg.name, mg.gunner.global_position.distance_to(mg.global_position) if mg.gunner else -1.0])
	if th.nests.size() >= 2:
		var dx := absf(th.nests[0].global_position.x - th.nests[1].global_position.x)
		_check(dx >= FrontThreats.NEST_SPACING, "the two guns are %.0f m apart: the field has a flank" % dx)
	# the arc: a point far out to the side is outside it
	var mg0 := th.nests[0]
	var side_pt: Vector3 = mg0.global_position + mg0.facing.cross(Vector3.UP) * 40.0 + mg0.facing * 10.0
	_check(not mg0._in_arc(side_pt + Vector3.UP) and mg0._in_arc(mg0.global_position + mg0.facing * 40.0 + Vector3.UP), "the traverse (%.0f°) covers the field ahead, not the flank" % rad_to_deg(FrontMg.TRAVERSE))


# --- fire ------------------------------------------------------------------------------
func _fire() -> void:
	print("-- fire")
	await _new_game(1916)
	var th := _threats()
	if th == null or th.nests.is_empty():
		_check(false, "no nests")
		return
	var mg := _main_nest(th)
	var pl: FpsPlayer = game.player
	# a second gun must not muddy the count
	for other in th.nests:
		if other != mg:
			other.jammed = true
	_clear_sky()
	_stand_before(mg, 32.0)
	var seen_in := -1.0
	for i in 60 * 3:
		await get_tree().physics_frame
		_stand_before(mg, 32.0)
		if mg._sees_target():
			seen_in = i / 60.0
			break
	_check(seen_in >= 0.0, "a man standing in the open 32 m in front of the gun is seen (within %.1f s)" % seen_in)
	var hits0 := Impacts.hits
	var on0 := mg.hits_on_player
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while frames < 60 * 14 and (mg.hits_on_player == on0 or mg.rounds_fired < 12):
		await get_tree().physics_frame
		frames += 1
		_stand_before(mg, 32.0)                       # keep him there (the game would move him)
	_check(mg.rounds_fired > 0 and mg.bursts > 0, "the gun fires at him: %d rounds in %d bursts within %.1f s" % [mg.rounds_fired, mg.bursts, frames / 60.0])
	_check(Impacts.hits > hits0, "rounds that miss land in the world (%d impacts)" % (Impacts.hits - hits0))
	_check(mg.hits_on_player > on0, "and rounds that find him are real rays into his body (%d hits)" % (mg.hits_on_player - on0))
	_check(pl.suppress_events > 0 and pl.suppression > 0.0, "rounds cracking past press on him (suppression %.2f after %d near passes)" % [pl.suppression, pl.suppress_events])
	var s0 := pl.suppression
	mg.jammed = true                                  # fire stops
	for i in 60 * 3:
		await get_tree().physics_frame
	_check(pl.suppression < s0 and s0 > 0.0, "and it eases off when the fire stops (%.2f → %.2f in 3 s)" % [s0, pl.suppression])
	mg.jammed = false
	# down into a hole, crouched: lost
	var cr := _hole_before(mg)
	_check(cr != Vector4.ZERO, "a shell hole deep enough to hide in lies in front of the gun")
	if cr != Vector4.ZERO:
		var m := game.maze as FrontMaze
		var at := Vector3(cr.x, 0, cr.y)
		at.y = m.floor_height(at) + 0.05
		pl.global_position = at
		pl.velocity = Vector3.ZERO
		pl.crouch = 1.0
		await _frames(3)
		var seen := mg._sees_target()
		var on1 := mg.hits_on_player
		for i in 60 * 6:
			await get_tree().physics_frame
			pl.global_position = at
			pl.velocity = Vector3.ZERO
			pl.crouch = 1.0
		_check(not seen and mg.hits_on_player == on1, "crouched on the floor of a %.1f m hole %.0f m out he is not seen and takes no hits in 6 s (state %s)" % [cr.w, at.distance_to(mg.global_position), FrontMg.State.keys()[mg.state]])
		pl.crouch = 0.0


# --- pauses ----------------------------------------------------------------------------
func _pauses() -> void:
	print("-- pauses")
	await _new_game(1916)
	var th := _threats()
	if th == null or th.nests.is_empty():
		_check(false, "no nests")
		return
	var mg := _main_nest(th)
	for other in th.nests:
		if other != mg:
			other.jammed = true
	_clear_sky()
	_stand_before(mg, 45.0)
	var gaps: Array[float] = []
	var last_round := mg.rounds_fired
	var gap := 0.0
	for i in 60 * 75:
		await get_tree().physics_frame
		_stand_before(mg, 45.0)
		if mg.rounds_fired != last_round:
			if gap > 0.5:
				gaps.append(gap)
			gap = 0.0
			last_round = mg.rounds_fired
		else:
			gap += 1.0 / 60.0
	var longest := 0.0
	for g in gaps:
		longest = maxf(longest, g)
	_check(mg.bursts >= 6 and gaps.size() >= 5, "75 s under fire: %d rounds in %d bursts, %d pauses" % [mg.rounds_fired, mg.bursts, gaps.size()])
	_check(mg.reloads >= 1 or mg.overheats >= 1, "the belt ran out (%d) or the jacket boiled (%d)" % [mg.reloads, mg.overheats])
	_check(longest >= 3.0, "the longest pause was %.1f s: a window to move" % longest)


# --- crew ------------------------------------------------------------------------------
func _crew() -> void:
	print("-- crew")
	await _new_game(1916)
	var th := _threats()
	if th == null or th.nests.is_empty():
		_check(false, "no nests")
		return
	var mg := _main_nest(th)
	for other in th.nests:
		if other != mg:
			other.jammed = true
	_clear_sky()
	_stand_before(mg, 40.0)
	for i in 60 * 6:
		await get_tree().physics_frame
		_stand_before(mg, 40.0)
	var before := mg.rounds_fired
	_check(before > 0, "the gun was firing (%d rounds)" % before)
	# the gunner shot
	var g := mg.gunner
	var chest: PhysicalBone3D = g.ragdoll.bones.get(&"Chest")
	g.hit({collider = chest, position = g.global_position + Vector3.UP * 1.2, direction = Vector3.FORWARD, damage = 5000.0, impulse = 6.0, shot_id = 1, weapon = "Rifle", dist = 10.0})
	await _frames(3)
	_check(g.dead and not mg.alive(), "the gunner shot dead: the nest is dead")
	var after := mg.rounds_fired
	for i in 60 * 5:
		await get_tree().physics_frame
		_stand_before(mg, 40.0)
	_check(mg.rounds_fired == after, "and the gun is silent (no rounds in 5 s)")
	_check(mg.gun.active and mg.gun.leave_ok and mg.gun.player == game.player, "the piece can be taken ([E] on it)")
	# a second nest: the mechanism shot to pieces
	if th.nests.size() >= 2:
		var mg2: FrontMg = th.nests[0] if th.nests[0] != mg else th.nests[1]
		mg2.jammed = false
		for i in 12:
			mg2.gun.shot(mg2.muzzle(), Vector3.FORWARD, 60.0)
		_check(mg2.jammed and not mg2.alive(), "a gun shot %d times with the rifle jams" % 12)


# --- shells ----------------------------------------------------------------------------
func _shells() -> void:
	print("-- shells")
	await _new_game(1916)
	var th := _threats()
	var art := th.artillery if th else null
	_check(art != null and art.next_in() >= FrontArtillery.FIRST.x - 1.0, "the guns hold their fire for the first %.0f-%.0f s (next salvo in %.0f s)" % [FrontArtillery.FIRST.x, FrontArtillery.FIRST.y, art.next_in() if art else -1.0])
	if art == null:
		return
	var m := game.maze as FrontMaze
	var pl: FpsPlayer = game.player
	# the player in the middle of the field, a soldier near where the shells will fall
	var w := m.w * m.cell
	var zc := lerpf((m.their_row0 + TrenchMaze.GRID_D) * m.cell, m.our_row0 * m.cell, 0.5)
	pl.global_position = Vector3(w * 0.5, m.ground_height(w * 0.5, zc) + 0.1, zc)
	var centre := Vector3(w * 0.5 + 14.0, 0, zc)
	var sentinel: Clown = null
	for c: Clown in game.clowns:
		if not c.dead and not c.has_meta(&"mg_gunner"):
			sentinel = c
			break
	if sentinel:
		sentinel.global_position = centre + Vector3(3.0, 0, 0)
		sentinel.global_position.y = m.ground_height(sentinel.global_position.x, sentinel.global_position.z)
	var warnings: Array = []
	var landings: Array = []
	art.shell_coming.connect(func(at: Vector3, in_s: float) -> void: warnings.append([at, Engine.get_physics_frames() / 60.0, in_s]))
	art.shell_landed.connect(func(at: Vector3) -> void: landings.append([at, Engine.get_physics_frames() / 60.0]))
	var fired_from: Vector3 = pl.global_position
	var misses0: int = sentinel.get_node("Brain").near_misses if sentinel else 0
	art.salvo_now(centre)
	for i in 60 * 20:
		await get_tree().physics_frame
		pl.global_position = fired_from
		pl.velocity = Vector3.ZERO
		if art._salvo_left == 0 and art._pending.is_empty() and i > 60 * 3:
			break
	_check(warnings.size() >= FrontArtillery.SALVO.x and landings.size() == warnings.size(), "a salvo: %d shells whistled, %d landed" % [warnings.size(), landings.size()])
	var lead_ok := true
	var clear_ok := true
	var zone_ok := true
	var near := 0
	for k in mini(warnings.size(), landings.size()):
		var wa: Array = warnings[k]
		var la: Array = landings[k]
		if la[1] - wa[1] < FrontArtillery.WHISTLE - 0.15:
			lead_ok = false
		var d := Vector2(la[0].x - fired_from.x, la[0].z - fired_from.z).length()
		if d < FrontArtillery.CLEAR - 0.01:
			clear_ok = false
		if d < FrontArtillery.NEAR:
			near += 1
		if la[0].z < art.z_min - 0.01 or la[0].z > art.z_max + 0.01:
			zone_ok = false
	_check(lead_ok, "every shell gave at least %.1f s of whistle before it landed" % FrontArtillery.WHISTLE)
	_check(clear_ok, "none landed within %.1f m of where the player stood" % FrontArtillery.CLEAR)
	_check(near <= 1, "at most one of the salvo came near him (%d within %.0f m)" % [near, FrontArtillery.NEAR])
	_check(zone_ok, "all in the fair zone (z %.0f..%.0f: the field and the two front parapets)" % [art.z_min, art.z_max])
	if sentinel:
		_check(sentinel.get_node("Brain").near_misses > misses0 or sentinel.dead, "the soldier near the fall got his head down (near misses %d → %d%s)" % [misses0, sentinel.get_node("Brain").near_misses, ", or was killed" if sentinel.dead else ""])
	_check(art.next_in() >= FrontArtillery.LULL.x - 0.5, "then a lull: the next salvo in %.0f s (at least %.0f)" % [art.next_in(), FrontArtillery.LULL.x])


# --- crouch ----------------------------------------------------------------------------
func _crouch() -> void:
	print("-- crouch")
	await _new_game(1916)
	var pl: FpsPlayer = game.player
	var brain: ClownBrain = null
	var soldier: Clown = null
	for c: Clown in game.clowns:
		if not c.dead and not c.has_meta(&"mg_gunner") and c.get_node_or_null("Brain") is ClownBrain:
			soldier = c
			brain = c.get_node("Brain")
			break
	_check(brain != null, "a soldier")
	if brain == null:
		return
	brain.set_physics_process(false)
	# a flat spot out on the field, a chest-high wall between them
	var m := game.maze as FrontMaze
	var w := m.w * m.cell
	var zc := lerpf((m.their_row0 + TrenchMaze.GRID_D) * m.cell, m.our_row0 * m.cell, 0.5)
	var base := Vector3(w * 0.5, 0, zc)
	base.y = m.ground_height(base.x, base.z)
	soldier.global_position = base + Vector3(0, 0, -8.0)
	soldier.global_position.y = m.ground_height(soldier.global_position.x, soldier.global_position.z)
	pl.global_position = base + Vector3(0, 0.1, 8.0)
	pl.velocity = Vector3.ZERO
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.0, 1.35, 0.3)
	cs.shape = bs
	wall.add_child(cs)
	game._world.add_child(wall)
	wall.global_position = base + Vector3(0, 1.35 * 0.5 + 0.1, 0)
	await _frames(2)
	brain.sight_range = 100.0
	pl.crouch = 0.0
	var standing := brain._sees_player()
	pl.crouch = 1.0
	var crouched := brain._sees_player()
	_check(standing and not crouched, "behind a 1.35 m wall: standing (eye %.2f) he is seen, crouched (eye %.2f) he is not" % [FpsPlayer.STAND_EYE, FpsPlayer.CROUCH_EYE])
	pl.crouch = 0.0
	wall.queue_free()


# --- look ------------------------------------------------------------------------------
func _look() -> void:
	print("-- look")
	if not OS.get_cmdline_user_args().has("render"):
		print("      (render only)")
		return
	await _new_game(1916)
	var th := _threats()
	if th == null or th.nests.is_empty():
		return
	_clear_sky()
	var mg := _main_nest(th)
	for other in th.nests:
		if other != mg:
			other.jammed = true
	var pl: FpsPlayer = game.player
	_stand_before(mg, 30.0, 6.0)
	pl.visible = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	var eye: Vector3 = mg.global_position + mg.facing * 9.0 + mg.facing.cross(Vector3.UP) * -3.0 + Vector3.UP * 1.3
	cam.global_position = eye
	cam.look_at(mg.global_position + Vector3.UP * 0.5)
	cam.current = true
	await _frames(20)
	# catch it mid-burst
	for i in 60 * 6:
		await get_tree().physics_frame
		_stand_before(mg, 30.0, 6.0)
		if mg._in_burst > 2:
			break
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/threats_nest.png")
	print("      wrote /tmp/threats_nest.png (%d rounds so far)" % mg.rounds_fired)
	# a shell on the field, seen from our side
	var m := game.maze as FrontMaze
	var w := m.w * m.cell
	var zc := lerpf((m.their_row0 + TrenchMaze.GRID_D) * m.cell, m.our_row0 * m.cell, 0.5)
	var at := Vector3(w * 0.5, 0, zc)
	at.y = m.ground_height(at.x, at.z)
	cam.global_position = at + Vector3(6.0, 1.6, 14.0)
	cam.look_at(at + Vector3.UP * 1.5)
	mg.jammed = true
	await _frames(10)
	Explosion.detonate(game._world, at, "shell")
	await _frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/threats_shell.png")
	print("      wrote /tmp/threats_shell.png")
