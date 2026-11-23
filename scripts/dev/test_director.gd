extends Node3D
## The Battlefield Director's foundation (Milestone 7), checked.
## Sections (user args; none = all):
##   tension   rises on notes (shots, blasts, damage), more for what is near
##             the player; holds while soldiers hunt him close by; decays to
##             nothing in quiet; the pacing mode follows it round the loop
##   local     alertness is a sector's own: a soldier in their lines who sees
##             the player raises THEIRS, not OURS; one who hears a shot
##             learns where the shot was, not where the player is; last_known
##             stays where it was learned when the player moves; it decays;
##             a body found raises the finder's sector toward the body
##   points    the floor's event points: every kind present, every one on the
##             path graph, holes out on the field, bays facing the field; a
##             point in front of the player in the open is visible, one behind
##             him is not
##   budget    can_spawn says no in COMBAT, past the live cap, past the floor
##             pool, inside the event gap, on a cooling event, with slow
##             frames - and says why; yes otherwise
##   seeded    two directors with the same seed and the same inputs make the
##             same choices; a different seed does not
##   overlay   hidden by default; F3 shows it; the text carries the state
##   godot --headless --fixed-fps 60 res://scenes/test_director.tscn [-- section...]

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
	var secs := ["tension", "local", "points", "budget", "seeded", "overlay"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("DIRECTOR: %d failed" % fails)
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


func _dir() -> FrontDirector:
	return game.director as FrontDirector


## Let the director tick `seconds` of its own clock (no real waiting).
func _tick(d: FrontDirector, seconds: float) -> void:
	var n := int(seconds / FrontDirector.TICK)
	for i in n:
		d.clock += FrontDirector.TICK
		d._since_event += FrontDirector.TICK
		d._evaluate(FrontDirector.TICK)


# --- tension ---------------------------------------------------------------------------
func _tension() -> void:
	print("-- tension")
	await _new_game(1916)
	var d := _dir()
	_check(d != null and d.is_in_group(&"director"), "the Front has a director, in the director group")
	if d == null:
		return
	# quiet all the soldiers so only our notes count
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	var pl: FpsPlayer = game.player
	_check(d.tension == 0.0 and d.mode == FrontDirector.Mode.UNEASY_QUIET, "it starts at tension 0, uneasy quiet")
	d.note("player_shot", pl.global_position, 1.0)
	var t1 := d.tension
	d.note("player_shot", pl.global_position + Vector3(0, 0, -55.0), 1.0)
	var t2 := d.tension
	_check(t1 > 0.0 and (t2 - t1) < t1 * 0.5, "a shot by him counts (%.1f); the same shot 55 m away counts less (+%.1f)" % [t1, t2 - t1])
	d.note("blast", pl.global_position + Vector3(6, 0, 0), 1.0)
	d.note("hurt", pl.global_position, 1.0)
	_tick(d, 0.5)
	_check(d.tension >= 20.0 and d.mode == FrontDirector.Mode.RISING, "a blast beside him and a wound: tension %.0f, RISING" % d.tension)
	for i in 6:
		d.note("enemy_shot", pl.global_position + Vector3(3, 0, -4), 1.0)
	d.note("blast", pl.global_position + Vector3(-5, 0, 2), 1.0)
	_tick(d, 0.5)
	_check(d.tension >= 50.0 and d.mode == FrontDirector.Mode.COMBAT, "a firefight: tension %.0f, COMBAT" % d.tension)
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("combat"), "in combat the director spawns nothing (%s)" % d.can_spawn(1).why)
	# then quiet
	_tick(d, 12.0)
	_check(d.mode == FrontDirector.Mode.RECOVERY and d.tension < 50.0, "12 quiet seconds later: tension %.0f, RECOVERY" % d.tension)
	_tick(d, 20.0)
	_check(d.mode == FrontDirector.Mode.UNEASY_QUIET and d.tension < 5.0, "and in another 20 it is quiet again (tension %.0f)" % d.tension)
	# a hunter close by holds it up without any shots
	var hunter: Clown = null
	for c: Clown in game.clowns:
		if not c.dead and not c.has_meta(&"mg_gunner") and c.get_node_or_null("Brain") is ClownBrain:
			hunter = c
			break
	if hunter:
		hunter.global_position = pl.global_position + Vector3(6, 0, 6)
		(hunter.get_node("Brain") as ClownBrain).mind = ClownBrain.Mind.HUNT
		_tick(d, 1.0)
		_check(d.threats == 1 and d.tension >= 18.0, "a soldier hunting him 8 m away: %d threat, tension held at %.0f with no shots" % [d.threats, d.tension])
		(hunter.get_node("Brain") as ClownBrain).mind = ClownBrain.Mind.IDLE


# --- local ------------------------------------------------------------------------------
func _local() -> void:
	print("-- local")
	await _new_game(1916)
	var d := _dir()
	if d == null:
		_check(false, "no director")
		return
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	var m := game.maze as FrontMaze
	var pl: FpsPlayer = game.player
	# a soldier of theirs, in their lines, sees the player (his own signal)
	var theirs: Clown = null
	var ours: Clown = null
	for c: Clown in game.clowns:
		if c.dead or c.has_meta(&"mg_gunner") or not (c.get_node_or_null("Brain") is ClownBrain):
			continue
		if d.sector_of(c.global_position) == FrontDirector.Sector.THEIRS and theirs == null:
			theirs = c
		elif d.sector_of(c.global_position) == FrontDirector.Sector.OURS and ours == null:
			ours = c
	_check(theirs != null and ours != null, "a soldier in their lines and one in ours")
	if theirs == null or ours == null:
		return
	_tick(d, 0.5)                                   # watch() connects the brains
	var seen_at: Vector3 = pl.global_position
	(theirs.get_node("Brain") as ClownBrain).alert(seen_at, true, true)
	_check(d.alert[FrontDirector.Sector.THEIRS] > 0.0 and d.alert[FrontDirector.Sector.OURS] == 0.0, "he saw the player: THEIRS %.0f, OURS %.0f - the other lines learn nothing" % [d.alert[FrontDirector.Sector.THEIRS], d.alert[FrontDirector.Sector.OURS]])
	_check(d.last_known[FrontDirector.Sector.THEIRS] == seen_at, "their last known is where he saw him")
	pl.global_position += Vector3(20, 0, 0)
	_tick(d, 1.0)
	_check(d.last_known[FrontDirector.Sector.THEIRS] == seen_at, "the player moved 20 m: their last known did not (no omniscience)")
	# one of ours hears a shot: he learns the shot's place, not the player's
	var shot_at: Vector3 = ours.global_position + Vector3(5, 0, 0)
	(ours.get_node("Brain") as ClownBrain).alert(shot_at, true, false)
	_check(d.last_known[FrontDirector.Sector.OURS] == shot_at and d.alert[FrontDirector.Sector.OURS] > 0.0 and d.alert[FrontDirector.Sector.OURS] < d.alert[FrontDirector.Sector.THEIRS], "one of ours heard a shot: OURS %.0f knows the shot's place, less than a sighting" % d.alert[FrontDirector.Sector.OURS])
	# decay
	var a0: float = d.alert[FrontDirector.Sector.THEIRS]
	_tick(d, FrontDirector.ALERT_HOLD + 30.0)
	_check(d.alert[FrontDirector.Sector.THEIRS] < a0 * 0.3, "no contact for %.0f s: THEIRS %.0f -> %.0f" % [FrontDirector.ALERT_HOLD + 30.0, a0, d.alert[FrontDirector.Sector.THEIRS]])
	# a body found: the finder's sector rises toward the body
	var victim: Clown = null
	for c: Clown in game.clowns:
		if c != ours and c != theirs and not c.dead and not c.has_meta(&"mg_gunner"):
			victim = c
			break
	if victim:
		victim.global_position = ours.global_position + Vector3(2.0, 0, 0)
		var chest: PhysicalBone3D = victim.ragdoll.bones.get(&"Chest")
		victim.hit({collider = chest, position = victim.global_position + Vector3.UP * 1.2, direction = Vector3.FORWARD, damage = 5000.0, impulse = 6.0, shot_id = 1, weapon = "Rifle", dist = 10.0})
		await _frames(2)
		var before: float = d.alert[FrontDirector.Sector.OURS]
		_tick(d, 0.5)
		_check(victim.dead and d.alert[FrontDirector.Sector.OURS] > before, "a body 2 m from one of ours: OURS %.0f -> %.0f" % [before, d.alert[FrontDirector.Sector.OURS]])


# --- points ----------------------------------------------------------------------------
func _points() -> void:
	print("-- points")
	await _new_game(1916)
	var d := _dir()
	var m := game.maze as FrontMaze
	var kinds := {}
	var off_graph := 0
	for pt: Dictionary in d.points:
		kinds[pt.kind] = int(kinds.get(pt.kind, 0)) + 1
		if pt.kind != "holes" and not m._astar.has_point(m.idx(pt.cell)):
			off_graph += 1
	_check(kinds.has("patrol") and kinds.has("bay") and kinds.has("bridge") and kinds.has("holes") and (kinds.has("dugout") or kinds.has("op")), "event points by kind: %s" % str(kinds))
	_check(off_graph == 0, "every trench point is on the path graph (%d were not)" % off_graph)
	var bays_face := true
	var holes_field := true
	for pt: Dictionary in d.points:
		if pt.kind == "bay" and absf(pt.dir.z) < 0.9:
			bays_face = false
		if pt.kind == "holes" and (pt.pos.z <= d.z_field_min or pt.pos.z >= d.z_field_max):
			holes_field = false
	_check(bays_face and holes_field, "bays face across the field; hole clusters lie out on it")
	# visibility: in front in the open vs behind
	var pl: FpsPlayer = game.player
	var zc := lerpf(d.z_field_min, d.z_field_max, 0.5)
	var w := m.w * m.cell
	pl.global_position = Vector3(w * 0.5, m.ground_height(w * 0.5, zc) + 0.1, zc)
	pl.rotation.y = 0.0
	pl.camera.rotation = Vector3.ZERO
	await _frames(2)
	var fwd := -pl.camera.global_basis.z
	var ahead: Vector3 = pl.global_position + fwd * 12.0
	ahead.y = m.ground_height(ahead.x, ahead.z)
	var behind: Vector3 = pl.global_position - fwd * 12.0
	behind.y = m.ground_height(behind.x, behind.z)
	_check(d.visible_to_player(ahead) and not d.visible_to_player(behind), "a point 12 m ahead in the open is visible to him; 12 m behind is not")
	var hidden := d.pick_points("bay", -1, 25.0, 200.0, true)
	var all := d.pick_points("bay", -1, 0.0, 1000.0, false)
	_check(hidden.size() <= all.size() and all.size() == kinds.get("bay", 0), "pick_points filters by distance and sight (%d of %d bays pass from mid-field)" % [hidden.size(), all.size()])


# --- budget ----------------------------------------------------------------------------
func _budget() -> void:
	print("-- budget")
	await _new_game(1916)
	var d := _dir()
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	_tick(d, FrontDirector.EVENT_GAP + 1.0)
	_check(d.can_spawn(2).ok, "quiet, nothing booked: can spawn (%s)" % str(d.can_spawn(2)))
	d.enabled = false
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why == "director off", "director off: %s" % d.can_spawn(1).why)
	d.enabled = true
	d.book("test", 2, 30.0)
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("event gap"), "just after an event: %s" % d.can_spawn(1).why)
	_tick(d, FrontDirector.EVENT_GAP + 1.0)
	_check(not d.can_spawn(1, "test").ok and d.can_spawn(1, "test").why.begins_with("test cooling"), "the same event again: %s" % d.can_spawn(1, "test").why)
	_check(d.can_spawn(1, "other").ok, "a different event: fine")
	d.live = [game.player, game.player, game.player, game.player, game.player, game.player]
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("live cap"), "six director soldiers alive: %s" % d.can_spawn(1).why)
	d.live = []
	d.spawned_total = FrontDirector.FLOOR_POOL
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("floor pool"), "the floor's pool spent: %s" % d.can_spawn(1).why)
	d.spawned_total = 0
	d._frame_ms = 40.0
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("frames"), "frames at 40 ms: %s" % d.can_spawn(1).why)
	d._frame_ms = 16.0
	_check(d.can_spawn(1).ok, "and all clear again")


# --- seeded ----------------------------------------------------------------------------
func _seeded() -> void:
	print("-- seeded")
	await _new_game(1916)
	var d := _dir()
	var a := FrontDirector.new()
	add_child(a)
	a.setup(game.maze as FrontMaze, game.player, game, 777)
	var b := FrontDirector.new()
	add_child(b)
	b.setup(game.maze as FrontMaze, game.player, game, 777)
	var c := FrontDirector.new()
	add_child(c)
	c.setup(game.maze as FrontMaze, game.player, game, 778)
	var pa: Array = []
	var pb: Array = []
	var pc: Array = []
	for i in 3:
		pa.append(a.pick_points("bay", -1, 0.0, 1000.0, false).map(func(p: Dictionary) -> Vector2i: return p.cell))
		pb.append(b.pick_points("bay", -1, 0.0, 1000.0, false).map(func(p: Dictionary) -> Vector2i: return p.cell))
		pc.append(c.pick_points("bay", -1, 0.0, 1000.0, false).map(func(p: Dictionary) -> Vector2i: return p.cell))
	_check(pa == pb, "the same seed, the same inputs: the same orderings, three times over")
	_check(pa != pc, "a different seed: a different order")
	a.queue_free()
	b.queue_free()
	c.queue_free()
	_check(d.log.size() >= 1 and d.log[0].what == "setup", "the log opens with the setup line: %s" % d.log[0].detail)


# --- overlay ---------------------------------------------------------------------------
func _overlay() -> void:
	print("-- overlay")
	await _new_game(1916)
	var d := _dir()
	_check(not d._overlay.visible, "the overlay is hidden by default")
	d.toggle_overlay()
	var txt := d.overlay_text()
	_check(d._overlay.visible and txt.contains("tension") and txt.contains("alert") and txt.contains("mode") and txt.contains("pool") and txt.contains("exit"), "F3 shows it; it carries mode, tension, alertness, pool and exit state")
	d.toggle_overlay()
	_check(not d._overlay.visible, "and hides it again")
