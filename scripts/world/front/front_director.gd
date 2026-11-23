class_name FrontDirector
extends Node
## The Battlefield Director's foundation (Operation Drowned Front, Milestone
## 7, package C4): it keeps two separate measures, chooses pacing from them,
## knows the floor's event points, holds the budgets and cooldowns, and logs
## every decision so it can be read back. It spawns nothing yet - the event
## catalogue is Milestone 8; this is the judgement it will use.
##
## TENSION (0–100) is the player's own weather: recent shots about him, his
## shots, blasts, damage taken, enemies hunting him close by. It rises on
## events and decays with quiet.
##
## ALERTNESS is LOCAL: one value per sector (our lines / No Man's Land /
## their lines), fed only by what a soldier in that sector actually saw or
## heard (the brains' own `alerted` signal, which fires from their own sight
## and hearing), by a body a soldier finds, and nothing else. A loud fight in
## our lines does not tell their lines where you are; `last_known` is where
## someone last saw or heard you, not where you are. It decays with time
## since contact. There is no global flag that says "the player is here".
##
## PACING: UNEASY_QUIET, RISING, COMBAT, RECOVERY - and in COMBAT the spawn
## budget is closed so the fight that exists can resolve.
##
## EVENT POINTS come from the geometry: patrol runs along trench lines,
## bridges, fire bays facing the field, dugouts, OPs, shell-hole clusters,
## each checked reachable (on the path graph) and later checked against the
## player's view cone before use (no pop-in). All choice goes through one
## seeded RNG, so a seed and a sequence of inputs give the same decisions.

enum Mode { UNEASY_QUIET, RISING, COMBAT, RECOVERY }
enum Sector { OURS, FIELD, THEIRS }

const TICK := 0.5                       ## seconds between evaluations (no per-frame scanning)
const TENSION_DECAY := 5.0              ## per second, after QUIET_AFTER seconds without an event
const QUIET_AFTER := 4.0
const ALERT_DECAY := 1.6                ## per second, after ALERT_HOLD seconds without contact in that sector
const ALERT_HOLD := 20.0
const THREAT_RANGE := 22.0              ## a hunting soldier this close is an immediate threat
const MAX_LIVE := 6                     ## director soldiers alive at once (the per-floor pool below)
const FLOOR_POOL := 18                  ## director soldiers in a floor, all told
const EVENT_GAP := 12.0                 ## seconds between any two events
const PERF_GATE_MS := 22.0              ## no spawning while frames are slower than this (smoothed)
const VIEW_HALF_ANGLE := 52.0           ## degrees: the player's cone an event point must be outside of, or hidden in
const TENSION_WEIGHTS := {
	player_shot = 4.0, enemy_shot = 3.0, mg_round = 1.2, blast = 14.0, hurt = 10.0, near_miss = 2.5,
}

var maze: FrontMaze
var player: FpsPlayer
var game: Node
var rng := RandomNumberGenerator.new()
var enabled := true
var tension := 0.0
var alert := {Sector.OURS: 0.0, Sector.FIELD: 0.0, Sector.THEIRS: 0.0}
var last_known := {}                    ## sector -> Vector3: where that sector last saw or heard the player
var last_contact := {}                  ## sector -> seconds (director clock) of the last contact
var mode := Mode.UNEASY_QUIET
var threats := 0                        ## hunting soldiers within THREAT_RANGE at the last tick
var points: Array = []                  ## {kind, pos, cell, dir, sector, route_cells, extra}
var cooldowns := {}                     ## event name -> seconds left
var spawned_total := 0
var live: Array = []                    ## director soldiers alive (Clown)
var log: Array = []                     ## {t, what, detail}
var clock := 0.0
var _last_event_t := -1000.0
var _last_event_gap := 0.0
var _since_event := 1000.0
var _tick_t := 0.0
var _recovery_t := 0.0
var _frame_ms := 16.0
var _connected_brains := {}
var _found_bodies := {}
var verbose := OS.get_cmdline_user_args().has("director_log")   ## print the log as it is written
var auto_events := true               ## the tick picks events itself (tests turn it off and call run_event)
var spawn_soldier: Callable           ## Game's: a WitzSoldat with a rifle, in the world and in game.clowns
var active: Array = []                ## {name, soldiers: Array[Clown], duties, born, point, cosmetic}
var events_run := {}                  ## name -> times
const CATALOGUE := {
	# weights by mode: [UNEASY_QUIET, RISING, COMBAT, RECOVERY]; men; cooldown s
	silhouette = {weights = [0.5, 0.2, 0.0, 0.4], men = 1, cooldown = 45.0},
	reinforce = {weights = [0.3, 0.4, 0.0, 0.4], men = 3, cooldown = 90.0},
	parapet = {weights = [0.2, 0.4, 0.0, 0.2], men = 3, cooldown = 70.0},
	# (M9) catalogue 4-6, 9-10
	investigate = {weights = [0.3, 0.6, 0.0, 0.6], men = 2, cooldown = 60.0},   # only with a sector alerted
	mg_sector = {weights = [0.3, 0.3, 0.0, 0.3], men = 0, cooldown = 50.0},
	shellfire = {weights = [0.15, 0.35, 0.0, 0.25], men = 0, cooldown = 80.0},
	smoke = {weights = [0.2, 0.4, 0.0, 0.3], men = 0, cooldown = 100.0},       # only by the field
	aftermath = {weights = [0.25, 0.15, 0.0, 0.35], men = 2, cooldown = 120.0},
}
const INVESTIGATE_ALERT := 15.0        ## a sector this alert, with a fresh last-known, sends men to look
const INVESTIGATE_FRESH := 40.0        ## ...seconds
const SHELL_RELOCATE := 12.0           ## a shell this near a frontline man moves him to another bay
const CORPSE_CAP := 6                  ## aftermath bodies kept on the floor at once
var corpses: Array = []
var squads: Array = []                 ## Squad per group event
const FIRST_EVENT_AFTER := 20.0        ## seconds into the floor before anything happens
var despawn_far := 150.0               ## a director soldier this far from the player, unseen...
const DESPAWN_AFTER := 90.0            ## ...for this long is taken off the floor
var _overlay: CanvasLayer
var _overlay_label: Label
var seed_value := 0
var z_field_min := 0.0
var z_field_max := 0.0


func setup(m: FrontMaze, p: FpsPlayer, g: Node, seed_: int, spawn := Callable()) -> void:
	maze = m
	player = p
	game = g
	spawn_soldier = spawn
	if "threats" in g and g.threats != null and g.threats.artillery != null:
		g.threats.artillery.shell_landed.connect(_on_shell_landed)
	rng.seed = seed_
	seed_value = seed_
	add_to_group(&"director")
	z_field_min = (m.their_row0 + TrenchMaze.GRID_D) * m.cell
	z_field_max = m.our_row0 * m.cell
	_collect_points()
	_log("setup", "seed %d, %d event points" % [seed_, points.size()])
	_make_overlay()


# --- inputs ----------------------------------------------------------------------------
## Something happened. `kind` is one of TENSION_WEIGHTS' keys (anything else
## is logged only). Tension is about the player, so what happened far from
## him weighs less.
func note(kind: String, at: Vector3, amount := 1.0) -> void:
	if not is_instance_valid(player):
		return
	var w: float = float(TENSION_WEIGHTS.get(kind, 0.0)) * amount
	if w > 0.0:
		var d := at.distance_to(player.global_position)
		var near := clampf(1.0 - (d - 8.0) / 50.0, 0.15, 1.0)
		tension = clampf(tension + w * near, 0.0, 100.0)
		_since_event = 0.0


## A soldier's own `alerted`: he saw (firsthand) or heard the player at
## `where`. Only HIS sector learns - and it learns `where`, not the truth.
func _on_brain_alerted(where: Vector3, firsthand: bool, brain: ClownBrain) -> void:
	if brain == null or not is_instance_valid(brain) or brain.clown == null:
		return
	if brain.has_meta(&"director_told"):
		brain.remove_meta(&"director_told")      # the director's own word: not news
		return
	var sec := sector_of(brain.clown.global_position)
	var gain := 28.0 if firsthand else 12.0
	alert[sec] = clampf(float(alert[sec]) + gain, 0.0, 100.0)
	last_known[sec] = where
	last_contact[sec] = clock
	_log("alert", "%s %s at %s by %s" % [Sector.keys()[sec], "saw" if firsthand else "heard", where.snapped(Vector3.ONE), brain.clown.name])


## Watch a soldier: his sightings and hearings feed his sector's alertness.
func watch(c: Clown) -> void:
	var b := c.get_node_or_null("Brain") as ClownBrain
	if b == null or _connected_brains.has(b):
		return
	_connected_brains[b] = true
	b.alerted.connect(_on_brain_alerted.bind(b))


func sector_of(pos: Vector3) -> int:
	if pos.z < z_field_min:
		return Sector.THEIRS
	if pos.z > z_field_max:
		return Sector.OURS
	return Sector.FIELD


# --- the tick --------------------------------------------------------------------------
func _process(delta: float) -> void:
	if maze == null or player == null:
		return
	clock += delta
	_since_event += delta
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.05)
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK
	_evaluate(TICK)
	if _overlay and _overlay.visible:
		_overlay_label.text = overlay_text()


func _evaluate(dt: float) -> void:
	# soldiers: watch new ones, count the hunters close by, find bodies
	threats = 0
	var live_now: Array = []
	if "clowns" in game:
		for c: Clown in game.clowns:
			if not is_instance_valid(c):
				continue
			watch(c)
			if c.dead:
				continue
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b and b.mind == ClownBrain.Mind.HUNT and c.global_position.distance_to(player.global_position) < THREAT_RANGE:
				threats += 1
		_bodies_found()
	for c in live:
		if is_instance_valid(c) and not c.dead:
			live_now.append(c)
	live = live_now
	# tension: threats hold it up, quiet lets it down
	tension = maxf(tension, minf(threats * 18.0, 70.0))
	if _since_event > QUIET_AFTER and threats == 0:
		tension = maxf(tension - TENSION_DECAY * dt, 0.0)
	# alertness: decays per sector after a hold
	for sec in alert.keys():
		if clock - float(last_contact.get(sec, -1000.0)) > ALERT_HOLD:
			alert[sec] = maxf(float(alert[sec]) - ALERT_DECAY * dt, 0.0)
	# cooldowns
	for k in cooldowns.keys():
		cooldowns[k] = maxf(float(cooldowns[k]) - dt, 0.0)
	# pacing
	var was := mode
	match mode:
		Mode.UNEASY_QUIET:
			if tension >= 50.0 or threats >= 2:
				mode = Mode.COMBAT
			elif tension >= 20.0:
				mode = Mode.RISING
		Mode.RISING:
			if tension >= 50.0 or threats >= 2:
				mode = Mode.COMBAT
			elif tension < 12.0:
				mode = Mode.UNEASY_QUIET
		Mode.COMBAT:
			if tension < 35.0 and threats == 0:
				mode = Mode.RECOVERY
				_recovery_t = 0.0
		Mode.RECOVERY:
			_recovery_t += dt
			if tension >= 50.0 or threats >= 2:
				mode = Mode.COMBAT
			elif _recovery_t > 12.0 and tension < 20.0:
				mode = Mode.UNEASY_QUIET
	if mode != was:
		_log("mode", "%s -> %s (tension %.0f, threats %d)" % [Mode.keys()[was], Mode.keys()[mode], tension, threats])
	_lifecycle()
	_select()


## A soldier walking past one of the player's kills learns something is
## wrong - his sector's alertness rises a little, toward the body, not the
## player.
func _bodies_found() -> void:
	for c: Clown in game.clowns:
		if not is_instance_valid(c) or not c.dead or _found_bodies.has(c):
			continue
		for other: Clown in game.clowns:
			if other == c or not is_instance_valid(other) or other.dead:
				continue
			if other.global_position.distance_to(c.global_position) < 4.0:
				_found_bodies[c] = true
				var sec := sector_of(other.global_position)
				alert[sec] = clampf(float(alert[sec]) + 10.0, 0.0, 100.0)
				if not last_known.has(sec):
					last_known[sec] = c.global_position
				last_contact[sec] = clock
				_log("body", "%s found %s" % [other.name, c.name])
				break


# --- budgets ---------------------------------------------------------------------------
## May an event spawn `n` soldiers now? The reasons it may not are the design.
func can_spawn(n: int, event := "") -> Dictionary:
	var why := ""
	if not enabled:
		why = "director off"
	elif mode == Mode.COMBAT:
		why = "combat: let the fight resolve"
	elif live.size() + n > MAX_LIVE:
		why = "live cap %d/%d" % [live.size(), MAX_LIVE]
	elif spawned_total + n > FLOOR_POOL:
		why = "floor pool %d/%d" % [spawned_total, FLOOR_POOL]
	elif _since_event < EVENT_GAP:
		why = "event gap %.0f s left" % (EVENT_GAP - _since_event)
	elif event != "" and float(cooldowns.get(event, 0.0)) > 0.0:
		why = "%s cooling %.0f s" % [event, float(cooldowns[event])]
	elif _frame_ms > PERF_GATE_MS:
		why = "frames at %.0f ms" % _frame_ms
	return {ok = why == "", why = why}


## An event has been placed: book it against the budgets.
func book(event: String, n: int, cooldown: float, soldiers: Array = []) -> void:
	spawned_total += n
	for c in soldiers:
		live.append(c)
		if c is Clown:
			watch(c)
	cooldowns[event] = cooldown
	_since_event = 0.0
	_log("event", "%s x%d (pool %d/%d, live %d)" % [event, n, spawned_total, FLOOR_POOL, live.size()])


# --- event points ----------------------------------------------------------------------
func _collect_points() -> void:
	points.clear()
	var m := maze
	var on_graph := func(c: Vector2i) -> bool: return m._astar.has_point(m.idx(c)) and m.path_cells(c, m.start_cell) < 9999
	# patrol runs: stretches of a trench line, 5+ cells, by trench name
	for tname in m.trenches.keys():
		var cells: Array = m.trenches[tname]
		if cells.size() < 5:
			continue
		var a: Vector2i = cells[0]
		var b: Vector2i = cells[cells.size() - 1]
		if not on_graph.call(a) or not on_graph.call(b):
			continue
		var pa := m.cell_center(a)
		var pb := m.cell_center(b)
		points.append({kind = "patrol", pos = pa, cell = a, dir = (pb - pa).normalized(), sector = sector_of(pa), extra = {to = pb, cells = cells.size(), trench = tname}})
	# bridges and ramps: a crossing has two ends on the graph
	for br: Dictionary in m.bridges:
		var p: Vector3 = (br.a + br.b) * 0.5
		points.append({kind = "bridge", pos = p, cell = br.cell, dir = Vector3(br.dir.x, 0, br.dir.y), sector = sector_of(p), extra = {a = br.a, b = br.b, ends = br.ends}})
	for rp: Dictionary in m.assault_ramps:
		var c: Vector2i = rp.cell if rp.has("cell") else Vector2i(-1, -1)
		var p: Vector3 = m.cell_center(c) if c != Vector2i(-1, -1) else Vector3.INF
		if p != Vector3.INF:
			points.append({kind = "ramp", pos = p, cell = c, dir = Vector3(0, 0, float(m.facing.get(c, 1))), sector = sector_of(p), extra = {}})
	# fire bays facing the field, dugouts, OPs
	for c: Vector2i in m.open_cells.keys():
		var k: String = m.kind.get(c, "")
		if k == "fire" and m.bays.has(c) and on_graph.call(c):
			var p := m.cell_center(c)
			points.append({kind = "bay", pos = p, cell = c, dir = Vector3(0, 0, float(m.facing.get(c, 1))), sector = sector_of(p), extra = {}})
		elif k == "dugout" and on_graph.call(c):
			var p := m.cell_center(c)
			points.append({kind = "dugout", pos = p, cell = c, dir = Vector3.ZERO, sector = sector_of(p), extra = {}})
		elif k == "op" and on_graph.call(c):
			var p := m.cell_center(c)
			points.append({kind = "op", pos = p, cell = c, dir = Vector3(0, 0, float(m.facing.get(c, 1))), sector = sector_of(p), extra = {}})
	# shell-hole clusters out on the field: the deep ones, in threes
	var deep: Array = []
	for cr: Vector4 in m.crater_list:
		if cr.w >= 1.1 and cr.y > z_field_min + 6.0 and cr.y < z_field_max - 6.0:
			deep.append(cr)
	for cr: Vector4 in deep:
		var near := 0
		for o: Vector4 in deep:
			if o != cr and Vector2(o.x - cr.x, o.y - cr.y).length() < 9.0:
				near += 1
		if near >= 2:
			var p := Vector3(cr.x, m.ground_height(cr.x, cr.y), cr.y)
			points.append({kind = "holes", pos = p, cell = m.cell_of(p), dir = Vector3.ZERO, sector = Sector.FIELD, extra = {radius = cr.z, depth = cr.w}})
	# route distance for each (how far along the player's way it is)
	for pt: Dictionary in points:
		var c: Vector2i = pt.cell
		pt.route_cells = m.path_cells(m.start_cell, c) if m._astar.has_point(m.idx(c)) else 9999


## Event points of `kind`, in `sector` (or any), at least `min_d` from the
## player and not in his sight: outside his view cone, or hidden from his
## eye. The order is shuffled by the director's own RNG.
func pick_points(kind: String, sector := -1, min_d := 25.0, max_d := 120.0, need_hidden := true) -> Array:
	var out: Array = []
	for pt: Dictionary in points:
		if pt.kind != kind:
			continue
		if sector >= 0 and pt.sector != sector:
			continue
		var d: float = pt.pos.distance_to(player.global_position)
		if d < min_d or d > max_d:
			continue
		if need_hidden and visible_to_player(pt.pos):
			continue
		out.append(pt)
	# a seeded shuffle: the same seed and inputs give the same order
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


## Would the player see something appear at `pos`: inside his view cone and
## with a clear line from his eye to it (a man's chest height there)?
func visible_to_player(pos: Vector3) -> bool:
	if not is_instance_valid(player):
		return false
	var eye: Vector3 = player.global_position + Vector3.UP * player.eye_height()
	var to := pos + Vector3.UP * 1.2 - eye
	var fwd := -player.camera.global_basis.z if player.camera else -player.global_basis.z
	if to.length() < 0.5:
		return true
	if rad_to_deg(fwd.angle_to(to.normalized())) > VIEW_HALF_ANGLE:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, pos + Vector3.UP * 1.2, FpsPlayer.LAYER_WORLD)
	q.exclude = [player.get_rid()]
	return get_tree().root.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- the events (Milestone 8: the first three of the catalogue) -------------------------
## Every tick: is there room for something, and if so what. The weights are
## the pacing's; the point is whatever the geometry offers out of sight.
func _select() -> void:
	if not enabled or not auto_events or spawn_soldier.is_null() or clock < FIRST_EVENT_AFTER:
		return
	var total := 0.0
	var options: Array = []
	for name_ in CATALOGUE.keys():
		var e: Dictionary = CATALOGUE[name_]
		var w: float = e.weights[mode]
		if w <= 0.0:
			continue
		if not can_spawn(e.men, name_).ok:
			continue
		if name_ == "investigate" and _alerted_sector() < 0:
			continue
		if name_ == "smoke" and not _by_the_field():
			continue
		options.append([name_, w])
		total += w
	if options.is_empty():
		return
	var r := rng.randf() * total
	for o: Array in options:
		r -= o[1]
		if r <= 0.0:
			run_event(o[0])
			return


## Run `name` now, if the floor offers a place for it out of the player's
## sight. Returns {ok, why, soldiers, point}. The budgets are booked here.
func run_event(name_: String) -> Dictionary:
	if not CATALOGUE.has(name_) or spawn_soldier.is_null():
		return {ok = false, why = "no such event or no spawner", soldiers = [], point = null}
	var e: Dictionary = CATALOGUE[name_]
	var r: Dictionary
	match name_:
		"silhouette": r = _ev_silhouette()
		"reinforce": r = _ev_reinforce(e.men)
		"parapet": r = _ev_parapet(e.men)
		"investigate": r = _ev_investigate(e.men)
		"mg_sector": r = _ev_mg_sector()
		"shellfire": r = _ev_shellfire()
		"smoke": r = _ev_smoke()
		"aftermath": r = _ev_aftermath(e.men)
	if not r.ok:
		_log("no-event", "%s: %s" % [name_, r.why])
		return r
	var soldiers: Array = r.soldiers
	for c: Clown in soldiers:
		c.set_meta(&"director_event", name_)
	var ev := {name = name_, soldiers = soldiers, born = clock, point = r.point, cosmetic = r.get("cosmetic", false), unseen_for = 0.0, lasts = float(r.get("lasts", 0.0)), squad = r.get("squad", null)}
	active.append(ev)
	if ev.squad != null:
		squads.append(ev.squad)
	events_run[name_] = int(events_run.get(name_, 0)) + 1
	book(name_, soldiers.size(), e.cooldown, soldiers)
	return r


## Events end when their men are dead, or when they have been far from the
## player and out of his sight for long enough: then the men are taken off
## the floor (never in view). Nothing of this touches a required-kill count:
## a SURVIVAL floor has none.
func _lifecycle() -> void:
	for ev: Dictionary in active.duplicate():
		if ev.soldiers.is_empty():
			# an event of no men (a gun's bursts, a salvo, a smoke bank) lasts its while
			if clock - float(ev.born) >= float(ev.lasts):
				active.erase(ev)
				_log("event-over", "%s: done" % ev.name)
			continue
		var alive: Array = []
		for c in ev.soldiers:
			if is_instance_valid(c) and not c.dead:
				alive.append(c)
		if alive.is_empty():
			active.erase(ev)
			if ev.squad != null:
				squads.erase(ev.squad)
			_log("event-over", "%s: all down" % ev.name)
			continue
		if ev.squad != null:
			var said: String = (ev.squad as Squad).tick(rng, maze)
			if said != "":
				_log("squad", "%s: %s" % [ev.name, said])
		_arrivals(ev)
		var far_unseen := true
		for c: Clown in alive:
			if c.global_position.distance_to(player.global_position) < despawn_far or visible_to_player(c.global_position):
				far_unseen = false
				break
		ev.unseen_for = float(ev.unseen_for) + TICK if far_unseen else 0.0
		if float(ev.unseen_for) >= DESPAWN_AFTER:
			for c: Clown in alive:
				_remove_soldier(c)
			active.erase(ev)
			if ev.squad != null:
				squads.erase(ev.squad)
			_log("event-over", "%s: far and unseen %.0f s, taken off" % [ev.name, ev.unseen_for])


func _remove_soldier(c: Clown) -> void:
	if "clowns" in game:
		game.clowns.erase(c)
	live.erase(c)
	c.queue_free()


## A WitzSoldat put at `at`, facing `face`, with duty `d` (attached as the
## legacy battle does it), out of the player's sight.
func _make_man(at: Vector3, face: Vector3, d: BattleDuty) -> Clown:
	var c: Clown = spawn_soldier.call()
	if c == null:
		return null
	if not c.has_rifle:
		c.give_rifle()
	var brain := c.get_node("Brain") as ClownBrain
	d.name = "Duty"
	c.add_child(d)
	d.attach(brain)
	c.global_position = at
	c.rotation.y = atan2(face.x, face.z)
	brain._wander_to = Vector3.INF
	watch(c)
	return c


## In or beside a wire belt's band - gaps included, so a patrol never stands
## in a gap and shoulders the men who must cross there into the wire.
func _near_wire(p: Vector3) -> bool:
	for b: Dictionary in maze.wire_belts:
		if p.x < b.x0 - 1.5 or p.x > b.x1 + 1.5:
			continue
		var band: Vector2 = maze.belt_band(b)
		if p.z >= band.x - 1.5 and p.z <= band.y + 1.5:
			return true
	return false


## A bay's fire step: at the front wall, facing the field.
func _fire_step(b: Dictionary) -> Vector3:
	var at := _stand(b.pos)
	var f: int = int(maze.facing.get(b.cell, 1))
	at.z = (b.cell.y + 1) * maze.cell - 0.45 if f == 1 else b.cell.y * maze.cell + 0.45
	at.y = maze.floor_height(at)
	return at


## Reinforcements that have reached the bays take up the frontline there:
## the beat duty is swapped for a FRONTLINE one at the man's post (only
## while he is still unaware; an alerted man is the brain's).
func _arrivals(ev: Dictionary) -> void:
	for c: Clown in ev.soldiers:
		if not is_instance_valid(c) or c.dead or not c.has_meta(&"reinforce_post"):
			continue
		var post: Vector3 = c.get_meta(&"reinforce_post")
		var brain := c.get_node("Brain") as ClownBrain
		var old := c.get_node_or_null("Duty") as BattleDuty
		if old == null or brain.mind != ClownBrain.Mind.IDLE:
			continue
		var flat := post - c.global_position
		flat.y = 0.0
		if flat.length() > 3.0:
			continue
		var d := BattleDuty.new(c.get_meta(&"arrive_kind", BattleDuty.Kind.FRONTLINE) as BattleDuty.Kind)
		d.post = post
		d.face = c.get_meta(&"reinforce_face")
		d.face_b = d.face.rotated(Vector3.UP, 2.4)
		if old.leader != null:
			old.leader.follower = null
		old.name = "OldDuty"
		old.queue_free()
		d.name = "Duty"
		c.add_child(d)
		d.attach(brain)
		c.remove_meta(&"reinforce_post")
		if ev.squad != null:
			var sq := ev.squad as Squad
			var i := sq.members.find(old)
			if i >= 0:
				sq.members[i] = d
		_log("arrive", "%s: a man takes %s at %s" % [ev.name, d.name_of(), post.snapped(Vector3.ONE)])


## Ground to stand on at a point on the top: the field or a trench floor.
func _stand(p: Vector3) -> Vector3:
	return Vector3(p.x, maze.floor_height(p), p.z)


## 1. A lone soldier, a silhouette in the haze: a patrol along the top (the
## field, or the ground among the trenches), 30–75 m from the player, from a
## place he cannot see, along top cells that join, clear of the wire and
## its gaps.
const SIL_RANGE := Vector2(30.0, 75.0)
func _ev_silhouette() -> Dictionary:
	var tops: Array = []
	for c: Vector2i in maze.top_cells.keys():
		var p := maze.cell_center(c)
		var d := p.distance_to(player.global_position)
		if d < SIL_RANGE.x or d > SIL_RANGE.y or _near_wire(p):
			continue
		tops.append(c)
	if tops.size() < 2:
		return {ok = false, why = "no top ground %d-%d m out" % [int(SIL_RANGE.x), int(SIL_RANGE.y)], soldiers = [], point = null}
	# a seeded shuffle, then the first hidden start with a route of 3-4 joined cells
	for i in range(tops.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = tops[i]
		tops[i] = tops[j]
		tops[j] = t
	for start: Vector2i in tops.slice(0, 40):
		var ps := maze.cell_center(start)
		if visible_to_player(ps):
			continue
		var route: Array[Vector3] = [_stand(ps)]
		var cur := start
		for leg in 3:
			var best := Vector2i(-1, -1)
			var best_d := 0.0
			for cand: Vector2i in tops.slice(0, 60):
				if cand == cur or route.has(_stand(maze.cell_center(cand))):
					continue
				var dd := maze.cell_center(cand).distance_to(maze.cell_center(cur))
				if dd >= 6.0 and dd <= 16.0 and maze.path_cells(cur, cand) < 9999 and dd > best_d:
					best = cand
					best_d = dd
			if best == Vector2i(-1, -1):
				break
			route.append(_stand(maze.cell_center(best)))
			cur = best
		if route.size() < 3:
			continue
		var d := BattleDuty.new(BattleDuty.Kind.PATROL)
		d.route.assign(route)
		d.post = route[0]
		var face := (route[1] - route[0]).normalized()
		var man := _make_man(route[0], face, d)
		if man == null:
			return {ok = false, why = "no soldier", soldiers = [], point = null}
		_log("spawn", "silhouette at %s, %.0f m out, %d legs" % [route[0].snapped(Vector3.ONE), route[0].distance_to(player.global_position), route.size()])
		return {ok = true, why = "", soldiers = [man], point = {kind = "top", pos = route[0], route = route}}
	return {ok = false, why = "no hidden start with a joined route", soldiers = [], point = null}


## 2. Reinforcements: a file of men from a dugout or a trench well away,
## over a footbridge or along the trench to fire bays, where they take the
## frontline duty (rifles over the parapet). A leader walks the beat, the
## others follow a step behind; the paths are the brains' own.
func _ev_reinforce(n: int) -> Dictionary:
	var starts := pick_points("dugout", -1, 30.0, 200.0, true) + pick_points("patrol", -1, 30.0, 200.0, true)
	var bays := pick_points("bay", -1, 25.0, 200.0, true)
	if starts.is_empty() or bays.is_empty():
		return {ok = false, why = "no hidden dugout/trench start or bay", soldiers = [], point = null}
	for st: Dictionary in starts.slice(0, 12):
		# the nearest bays on the same side, reachable by trench
		var dest: Dictionary = {}
		var best_d := INF
		for b: Dictionary in bays:
			if b.sector != st.sector:
				continue
			var dd: float = b.pos.distance_to(st.pos)
			if dd >= 10.0 and dd < best_d and maze.path_cells(st.cell, b.cell) < 9999:
				best_d = dd
				dest = b
		if dest.is_empty():
			continue
		# over a footbridge only when it is a short cut on the trench graph
		# (start -> one end, deck, other end -> bay shorter than the way round):
		# never a stroll out on the top for its own sake
		var route: Array[Vector3] = [_stand(st.pos)]
		var direct: int = maze.path_cells(st.cell, dest.cell)
		for br: Dictionary in pick_points("bridge", st.sector, 0.0, 1000.0, false):
			var ends: Array = br.extra.ends
			var e0: Vector2i = ends[0]
			var e1: Vector2i = ends[1]
			for o in 2:
				var ea := e0 if o == 0 else e1
				var eb := e1 if o == 0 else e0
				var to_a: int = maze.path_cells(st.cell, ea)
				var from_b: int = maze.path_cells(eb, dest.cell)
				if to_a < 9999 and from_b < 9999 and to_a + 1 + from_b < direct:
					route.append((br.extra.a if o == 0 else br.extra.b) as Vector3)
					route.append((br.extra.b if o == 0 else br.extra.a) as Vector3)
					break
			if route.size() > 1:
				break
		route.append(_stand(dest.pos))
		# their posts on arrival: the bay and the ones beside it
		var posts: Array[Vector3] = []
		var faces: Array[Vector3] = []
		for b: Dictionary in [dest] + bays:
			if posts.size() >= n:
				break
			if b.sector != dest.sector or absf(b.pos.z - dest.pos.z) > maze.cell * 1.5 or absf(b.pos.x - dest.pos.x) > maze.cell * 3.0:
				continue
			var at := _fire_step(b)
			if posts.has(at):
				continue
			posts.append(at)
			faces.append(Vector3(0, 0, float(maze.facing.get(b.cell, 1))))
		var men: Array = []
		var leader: BattleDuty = null
		for i in n:
			var d := BattleDuty.new(BattleDuty.Kind.TRENCH_PATROL)
			d.route.assign(route)
			d.post = route[0]
			if leader != null:
				d.follow_delay = 0.9 + 0.7 * i
				d.leader = leader
				leader.follower = d if leader.follower == null else leader.follower
			var at: Vector3 = route[0] + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)) * (1 if i > 0 else 0)
			var man := _make_man(at, (route[1] - route[0]).normalized(), d)
			if man == null:
				break
			man.set_meta(&"reinforce_post", posts[mini(i, posts.size() - 1)])
			man.set_meta(&"reinforce_face", faces[mini(i, faces.size() - 1)])
			men.append(man)
			if leader == null:
				leader = d
		if men.is_empty():
			return {ok = false, why = "no soldier", soldiers = [], point = null}
		_log("spawn", "reinforce x%d from %s (%s) to a bay %.0f m on, %s" % [men.size(), st.pos.snapped(Vector3.ONE), st.kind, best_d, "by a bridge" if route.size() > 2 else "by the trench"])
		var sq := Squad.new("reinforce", _duties_of(men), route[0], (route[0] - route[1]).normalized())
		return {ok = true, why = "", soldiers = men, point = {kind = st.kind, pos = st.pos, route = route, dest = dest.pos}, squad = sq}
	return {ok = false, why = "no start with a reachable bay on its side", soldiers = [], point = null}


## 3. A parapet firefight: two or three of theirs at adjacent fire bays of
## their line, rifles over the parapet, firing across No Man's Land -
## COSMETIC rounds (the frontline duty's effects: flash, crack, tracer; no
## ray, no damage - J7), where the player cannot see them appear.
func _ev_parapet(n: int) -> Dictionary:
	var bays := pick_points("bay", Sector.THEIRS, 30.0, 200.0, true)
	if bays.is_empty():
		bays = pick_points("bay", Sector.OURS, 30.0, 200.0, true)
	if bays.is_empty():
		return {ok = false, why = "no hidden bay 30 m off", soldiers = [], point = null}
	var first: Dictionary = bays[0]
	var group: Array = [first]
	for b: Dictionary in bays:
		if group.size() >= n:
			break
		if b != first and b.sector == first.sector and absf(b.pos.z - first.pos.z) < maze.cell * 1.5 and absf(b.pos.x - first.pos.x) <= maze.cell * 3.0:
			group.append(b)
	var men: Array = []
	for b: Dictionary in group:
		var d := BattleDuty.new(BattleDuty.Kind.FRONTLINE)
		var at := _fire_step(b)
		d.post = at
		d.face = Vector3(0, 0, float(maze.facing.get(b.cell, 1)))
		var man := _make_man(at, d.face, d)
		if man == null:
			break
		men.append(man)
	if men.is_empty():
		return {ok = false, why = "no soldier", soldiers = [], point = null}
	_log("spawn", "parapet x%d at %s, %.0f m off, cosmetic fire" % [men.size(), first.pos.snapped(Vector3.ONE), first.pos.distance_to(player.global_position)])
	var back := _stand(first.pos) - Vector3(0, 0, float(maze.facing.get(first.cell, 1))) * maze.cell * 2.0
	var sq := Squad.new("parapet", _duties_of(men), back, Vector3(0, 0, float(maze.facing.get(first.cell, 1))))
	return {ok = true, why = "", soldiers = men, point = first, cosmetic = true, squad = sq}


func _duties_of(men: Array) -> Array:
	var out: Array = []
	for c: Clown in men:
		var d := c.get_node_or_null("Duty")
		if d:
			out.append(d)
	return out


## A sector with a fresh last-known worth sending men to, or -1.
func _alerted_sector() -> int:
	var best := -1
	var best_a := INVESTIGATE_ALERT
	for sec in alert.keys():
		if float(alert[sec]) >= best_a and last_known.get(sec, Vector3.INF) != Vector3.INF and clock - float(last_contact.get(sec, -1e9)) <= INVESTIGATE_FRESH:
			best = sec
			best_a = float(alert[sec])
	return best


## The player out on the field, or at our parapet about to go.
func _by_the_field() -> bool:
	var z := player.global_position.z
	return z >= z_field_min - 6.0 and z <= z_field_max + 14.0


## 4. A patrol investigating: two men from a hidden trench point 20–45 m from
## the sector's last-known, told where the noise was (not where the player
## is): the brains' own hunt-blind to the spot, then the search, then back
## to the beat they were given. A squad: the first to see passes the word.
func _ev_investigate(n: int) -> Dictionary:
	var sec := _alerted_sector()
	if sec < 0:
		return {ok = false, why = "no sector alerted with a fresh last-known", soldiers = [], point = null}
	var lk: Vector3 = last_known[sec]
	var starts: Array = pick_points("patrol", -1, 20.0, 200.0, true) + pick_points("dugout", -1, 20.0, 200.0, true)
	var lk_cell := maze.cell_of(lk)
	var best: Dictionary = {}
	var best_d := INF
	for st: Dictionary in starts:
		var d: float = st.pos.distance_to(lk)
		if d < 20.0 or d > 45.0 or st.pos.distance_to(player.global_position) < 20.0:
			continue
		var cells: int = maze.path_cells(st.cell, lk_cell)
		if cells >= 9999:
			continue
		if d < best_d:
			best_d = d
			best = st
	if best.is_empty():
		return {ok = false, why = "no hidden start 20-45 m from the last-known with a path", soldiers = [], point = null}
	var men: Array = []
	var leader: BattleDuty = null
	var beat: Array[Vector3] = [_stand(best.pos)]
	if best.kind == "patrol":
		beat.append(_stand(best.extra.to))
	for i in n:
		var d := BattleDuty.new(BattleDuty.Kind.TRENCH_PATROL)
		d.route.assign(beat)
		d.post = beat[0]
		if leader != null:
			d.follow_delay = 1.0 + 0.8 * i
			d.leader = leader
			leader.follower = d if leader.follower == null else leader.follower
		var at: Vector3 = beat[0] + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)) * (1 if i > 0 else 0)
		var man := _make_man(at, (lk - beat[0]).normalized(), d)
		if man == null:
			break
		men.append(man)
		if leader == null:
			leader = d
	if men.is_empty():
		return {ok = false, why = "no soldier", soldiers = [], point = null}
	# told where the noise was: not firsthand, not startled - he walks to look
	for c: Clown in men:
		var b := c.get_node("Brain") as ClownBrain
		var d := c.get_node("Duty") as BattleDuty
		d.told_hops = 1
		b.set_meta(&"director_told", true)
		b.alert(lk, false, false)
	_log("spawn", "investigate x%d from %s (%s), %.0f m from %s's last-known %s" % [men.size(), best.pos.snapped(Vector3.ONE), best.kind, best_d, Sector.keys()[sec], lk.snapped(Vector3.ONE)])
	var sq := Squad.new("investigate", _duties_of(men), beat[0], (lk - beat[0]).normalized())
	return {ok = true, why = "", soldiers = men, point = best, squad = sq}


## 5. A Maxim working over a plausible sector: a nest that is idle (not on
## the player) fires 3–5 bursts at a shell-hole cluster or a stretch of the
## field in its arc, 25 m or more from the player. Its rounds are the real
## thing (the gun's own rays), so the point is kept well off him.
func _ev_mg_sector() -> Dictionary:
	if not ("threats" in game) or game.threats == null:
		return {ok = false, why = "no threats", soldiers = [], point = null}
	var nests: Array = game.threats.nests
	if nests.is_empty():
		return {ok = false, why = "no nests", soldiers = [], point = null}
	var order: Array = nests.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var targets: Array = pick_points("holes", Sector.FIELD, 25.0, 200.0, false)
	for mg: FrontMg in order:
		if not mg.alive() or mg.state != FrontMg.State.IDLE:
			continue
		var cands: Array = targets.duplicate()
		for k in 6:
			var yaw := rng.randf_range(-FrontMg.TRAVERSE * 0.8, FrontMg.TRAVERSE * 0.8)
			var p: Vector3 = mg.global_position + mg.facing.rotated(Vector3.UP, yaw) * rng.randf_range(25.0, 70.0)
			p.y = maze.ground_height(p.x, p.z) + 0.6
			cands.append({pos = p, kind = "field"})
		for t: Dictionary in cands:
			var at: Vector3 = t.pos
			if at.distance_to(player.global_position) < 25.0:
				continue
			var n := rng.randi_range(3, 5)
			if mg.engage(at, n):
				_log("spawn", "mg_sector: %s works over %s (%s), %d bursts, %.0f m from the player" % [mg.name, at.snapped(Vector3.ONE), t.kind, n, at.distance_to(player.global_position)])
				return {ok = true, why = "", soldiers = [], point = {kind = t.kind, pos = at}, cosmetic = false, lasts = n * 3.5}
	return {ok = false, why = "no idle nest with a sector in its arc", soldiers = [], point = null}


## 6. Shellfire near men the player can watch: a salvo centred 8–12 m from a
## group of the director's (or the garrison's) soldiers 30–90 m off, in
## front of the player. The artillery keeps its own fairness (never within
## 7.5 m of the player); the men duck (the brains' near_miss), hunt the
## blast's way, and a frontline man within 12 m moves to another bay.
func _ev_shellfire() -> Dictionary:
	if not ("threats" in game) or game.threats == null or game.threats.artillery == null:
		return {ok = false, why = "no artillery", soldiers = [], point = null}
	var art: FrontArtillery = game.threats.artillery
	var cands: Array = []
	for c in game.clowns:
		if not is_instance_valid(c) or c.dead:
			continue
		var d: float = c.global_position.distance_to(player.global_position)
		if d < 30.0 or d > 90.0 or not art._in_zone(c.global_position):
			continue
		var to: Vector3 = c.global_position - player.global_position
		var fwd: Vector3 = -player.camera.global_basis.z if player.camera else -player.global_basis.z
		if rad_to_deg(fwd.angle_to(to)) > 70.0:
			continue
		cands.append(c)
	if cands.is_empty():
		return {ok = false, why = "no soldiers 30-90 m off in front of the player", soldiers = [], point = null}
	var c: Clown = cands[rng.randi() % cands.size()]
	var a := rng.randf() * TAU
	var centre: Vector3 = c.global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(8.0, 12.0)
	art.salvo_now(centre)
	_log("spawn", "shellfire: a salvo centred %s, %.0f m from %s, %.0f m from the player" % [centre.snapped(Vector3.ONE), centre.distance_to(c.global_position), c.name, centre.distance_to(player.global_position)])
	return {ok = true, why = "", soldiers = [], point = {kind = "salvo", pos = centre}, cosmetic = false, lasts = 30.0}


## 9. A smoke bank rolled across the field on the player's lane, from their
## side toward ours: the Maxims lose him in it (visibility is the one
## function); a crossing to make or a breath to take.
func _ev_smoke() -> Dictionary:
	if not _by_the_field():
		return {ok = false, why = "the player is not by the field", soldiers = [], point = null}
	var atmos := get_tree().get_first_node_in_group(&"fog")
	if atmos == null or not ("front_fog" in atmos) or atmos.front_fog == null:
		return {ok = false, why = "no front fog", soldiers = [], point = null}
	var fog = atmos.front_fog
	var b = fog.roll_across(player.global_position.x, z_field_min, z_field_max, player.global_position)
	if b == null:
		return {ok = false, why = "the banks are full, all thick and near", soldiers = [], point = null}
	_log("spawn", "smoke: a bank %s across the lane at x %.0f from %s, radius %.0f" % ["steered" if b.age > 0.0 else "rolled", player.global_position.x, b.pos.snapped(Vector3.ONE), b.radius])
	return {ok = true, why = "", soldiers = [], point = {kind = "bank", pos = b.pos}, cosmetic = true, lasts = 90.0, bank_vel = b.vel}


## 10. Aftermath: a post hit before the player gets there - scorch and
## craters' worth of impact decals at a hidden bay or pit 30 m or more off,
## two bodies, and two men running from it along the trench to a place
## 15–30 m on, where they stop and keep their heads down (GUARD).
func _ev_aftermath(n: int) -> Dictionary:
	var sites: Array = pick_points("bay", -1, 30.0, 200.0, true) + pick_points("op", -1, 30.0, 200.0, true)
	if sites.is_empty():
		return {ok = false, why = "no hidden bay/OP 30 m off", soldiers = [], point = null}
	var site: Dictionary = sites[0]
	var at := _stand(site.pos)
	# where they run to: a trench point 15-30 m on by path, hidden or not (they are running)
	var far: Dictionary = {}
	var far_d := 0.0
	for pt: Dictionary in pick_points("patrol", site.sector, 0.0, 1000.0, false) + pick_points("dugout", site.sector, 0.0, 1000.0, false):
		var d: float = pt.pos.distance_to(site.pos)
		if d < 15.0 or d > 30.0:
			continue
		var cells: int = maze.path_cells(site.cell, pt.cell)
		if cells >= 9999:
			continue
		if d > far_d:
			far_d = d
			far = pt
	if far.is_empty():
		return {ok = false, why = "nowhere to run to 15-30 m along the trench", soldiers = [], point = null}
	# the marks of the shell that did it
	Impacts.blast(at + Vector3.UP * 0.2, 3.0)
	# the dead
	var bodies := 0
	for i in 2:
		if corpses.size() >= CORPSE_CAP:
			break
		var c: Clown = spawn_soldier.call()
		if c == null:
			break
		if "clowns" in game:
			game.clowns.erase(c)            # a body, not an enemy
		var b := c.get_node_or_null("Brain")
		if b:
			b.queue_free()
		c.global_position = at + Vector3(rng.randf_range(-1.2, 1.2), 0.35, rng.randf_range(-0.8, 0.8))
		c.rotation.y = rng.randf() * TAU
		c.set_meta(&"director_event", "aftermath")
		corpses.append(c)
		c.call_deferred("make_corpse")
		bodies += 1
	# the living, running
	var men: Array = []
	var dest := _stand(far.pos)
	for i in n:
		var d := BattleDuty.new(BattleDuty.Kind.RUNNER)
		var r1: Array[Vector3] = [dest]
		d.route = r1
		d.post = at
		var start: Vector3 = at + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)) * (1 if i > 0 else 0)
		var man := _make_man(start, (dest - at).normalized(), d)
		if man == null:
			break
		man.set_meta(&"reinforce_post", dest + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)))
		man.set_meta(&"reinforce_face", (at - dest).normalized())
		man.set_meta(&"arrive_kind", BattleDuty.Kind.GUARD)
		var b := man.get_node("Brain") as ClownBrain
		b.suppression = 1.0
		men.append(man)
	if men.is_empty():
		return {ok = false, why = "no soldier", soldiers = [], point = null}
	_log("spawn", "aftermath at %s (%s): %d bodies, %d running %.0f m to %s" % [at.snapped(Vector3.ONE), site.kind, bodies, men.size(), far_d, dest.snapped(Vector3.ONE)])
	var sq := Squad.new("aftermath", _duties_of(men), dest, (at - dest).normalized())
	sq.withdraw_chance = 0.0            # they have withdrawn already
	return {ok = true, why = "", soldiers = men, point = site, squad = sq}


## A shell down: a frontline man of the director's within SHELL_RELOCATE
## moves to another bay on his side, 4–14 m away (the brains' near_miss has
## already put his head down).
func _on_shell_landed(at: Vector3) -> void:
	for ev: Dictionary in active:
		for c in ev.soldiers:
			if not is_instance_valid(c) or c.dead:
				continue
			var d := c.get_node_or_null("Duty") as BattleDuty
			if d == null or d.kind != BattleDuty.Kind.FRONTLINE:
				continue
			if c.global_position.distance_to(at) > SHELL_RELOCATE:
				continue
			var sec := sector_of(c.global_position)
			var best: Dictionary = {}
			var best_d := INF
			for b: Dictionary in pick_points("bay", sec, 0.0, 1000.0, false):
				var bd: float = b.pos.distance_to(c.global_position)
				if bd < 4.0 or bd > 14.0 or b.pos.distance_to(at) < 6.0:
					continue
				if bd < best_d:
					best_d = bd
					best = b
			if best.is_empty():
				continue
			d.relocate(_fire_step(best), Vector3(0, 0, float(maze.facing.get(best.cell, 1))))
			_log("relocate", "%s: %s moves %.0f m to another bay after a shell" % [ev.name, c.name, best_d])


# --- the overlay (development only, hidden by default; F3) -----------------------------
func _make_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	_overlay.visible = false
	_overlay_label = Label.new()
	_overlay_label.position = Vector2(12, 40)
	_overlay_label.add_theme_font_size_override("font_size", 13)
	_overlay_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.8))
	_overlay_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay_label.add_theme_constant_override("outline_size", 3)
	_overlay.add_child(_overlay_label)
	add_child(_overlay)


func toggle_overlay() -> void:
	_overlay.visible = not _overlay.visible
	if _overlay.visible:
		_overlay_label.text = overlay_text()


func overlay_text() -> String:
	var tiers := {near = 0, mid = 0, far = 0}
	var alive := 0
	if "clowns" in game:
		for c: Clown in game.clowns:
			if not is_instance_valid(c) or c.dead:
				continue
			alive += 1
			var d := c.global_position.distance_to(player.global_position)
			if d < 30.0:
				tiers.near += 1
			elif d < 80.0:
				tiers.mid += 1
			else:
				tiers.far += 1
	var cd := ""
	for k in cooldowns.keys():
		if float(cooldowns[k]) > 0.0:
			cd += "%s %.0fs  " % [k, float(cooldowns[k])]
	var exit_state := "open" if ("exit_open" in game and game.exit_open) else "closed"
	var cs := can_spawn(1)
	return ("DIRECTOR %s   seed %d   objective %s   region %s\n" % ["on" if enabled else "OFF", seed_value, "SURVIVAL" if ("objective" in game and game.objective == 1) else "ELIMINATION", Sector.keys()[sector_of(player.global_position)]]
		+ "mode %s   tension %3.0f   threats %d   since event %.0fs\n" % [Mode.keys()[mode], tension, threats, _since_event]
		+ "alert  ours %3.0f   field %3.0f   theirs %3.0f   last known: %s\n" % [alert[Sector.OURS], alert[Sector.FIELD], alert[Sector.THEIRS], _lk_text()]
		+ "enemies alive %d  (near %d / mid %d / far %d)   director live %d   pool %d/%d\n" % [alive, tiers.near, tiers.mid, tiers.far, live.size(), spawned_total, FLOOR_POOL]
		+ "spawn: %s   cooldowns: %s\n" % ["yes" if cs.ok else cs.why, cd if cd != "" else "-"]
		+ "events: %s\n" % _events_text()
		+ "frame %.1f ms   fps %d   exit %s   points %d\n" % [_frame_ms, Engine.get_frames_per_second(), exit_state, points.size()]
		+ "F3 overlay  F4 director on/off  F5 force the next event")


func _events_text() -> String:
	if active.is_empty():
		return "-"
	var s := ""
	for ev: Dictionary in active:
		if ev.soldiers.is_empty():
			var p: Vector3 = ev.point.pos
			s += "%s %.0fs @ %.0f m   " % [ev.name, clock - float(ev.born), p.distance_to(player.global_position)]
			continue
		var alive := 0
		for c in ev.soldiers:
			if is_instance_valid(c) and not c.dead:
				alive += 1
		s += "%s x%d %.0fs%s %s   " % [ev.name, alive, clock - float(ev.born), " [cosmetic fire]" if ev.cosmetic else " [live]", _where_text(ev)]
	return s


## Where an event's men are from the player: distance and a clock bearing
## (12 = straight ahead), and whether any is in view.
func _where_text(ev: Dictionary) -> String:
	if not is_instance_valid(player):
		return ""
	var nearest := INF
	var np := Vector3.ZERO
	var seen := false
	for c in ev.soldiers:
		if not is_instance_valid(c) or c.dead:
			continue
		var d: float = c.global_position.distance_to(player.global_position)
		if d < nearest:
			nearest = d
			np = c.global_position
		if visible_to_player(c.global_position):
			seen = true
	if nearest == INF:
		return ""
	var fwd := -player.camera.global_basis.z if player.camera else -player.global_basis.z
	fwd.y = 0.0
	var to := np - player.global_position
	to.y = 0.0
	var ang := rad_to_deg(atan2(fwd.cross(to.normalized()).y, fwd.normalized().dot(to.normalized())))
	# clockwise from ahead: 12, 1, 2 ... (ang > 0 is to the left here)
	var hour := int(round(-ang / 30.0)) % 12
	if hour <= 0:
		hour += 12
	return "@ %.0f m, %d o'clock%s" % [nearest, hour, ", IN VIEW" if seen else ""]


func _lk_text() -> String:
	var s := ""
	for sec in last_known.keys():
		s += "%s %s  " % [Sector.keys()[sec].to_lower(), (last_known[sec] as Vector3).snapped(Vector3.ONE)]
	return s if s != "" else "-"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			toggle_overlay()
		elif event.keycode == KEY_F4:
			enabled = not enabled
			_log("toggle", "director %s" % ("on" if enabled else "off"))
		elif event.keycode == KEY_F5:
			force_event()


## Development: place the next event now - the gap and the cooldowns waived,
## the live cap and the pool kept, the hidden-placement rule kept. Cycles
## through the catalogue so each press shows a different one.
var _force_i := 0
func force_event() -> void:
	if spawn_soldier.is_null() or not is_instance_valid(player):
		return
	var names: Array = CATALOGUE.keys()
	for k in names.size():
		var name_: String = names[(_force_i + k) % names.size()]
		var e: Dictionary = CATALOGUE[name_]
		if live.size() + int(e.men) > MAX_LIVE or spawned_total + int(e.men) > FLOOR_POOL:
			continue
		_since_event = EVENT_GAP
		cooldowns.erase(name_)
		var r: Dictionary = run_event(name_)
		_force_i = (_force_i + k + 1) % names.size()
		_log("forced", "%s: %s" % [name_, "placed" if r.ok else r.why])
		return
	_log("forced", "nothing fits: live %d/%d, pool %d/%d" % [live.size(), MAX_LIVE, spawned_total, FLOOR_POOL])


func _log(what: String, detail: String) -> void:
	log.append({t = clock, what = what, detail = detail})
	if verbose:
		print("[director %6.1f] %s: %s" % [clock, what, detail])
	if log.size() > 400:
		log.pop_front()
