class_name TrenchBattle
extends Node3D
## The battle going on round the player on a trench floor:
##  - gives the soldiers jobs (BattleDuty): riflemen on the fire steps firing
##    over the parapet, guards at the dugouts and junctions, runners (some
##    over the footbridges or along the top), patrols up on the top in the mist;
##  - the enemy across No Man's Land, made only of effects: rifle flashes far
##    off, flares that hang and drift down, machine-gun tracer going high over
##    the trenches. None of it can hurt anyone.
## The shells, the far machine gun and rifle sounds are TrenchAmbience's.

var maze: TrenchMaze
var player: Node3D
var rng := RandomNumberGenerator.new()
## What was handed out (tests): {frontline: n, guard: n, runner: n, patrol: n, bridge_runs: n}
var counts := {}
var duties: Array[BattleDuty] = []
## The fight out in No Man's Land (TrenchField).
var field: TrenchField
## The mist's weather: fog banks rolling across, heavy spells (TrenchFog).
var fog: TrenchFog
## Pacing: multiplies the gaps between the far side's fire, the field's
## shells and casualties (above 1 a lull, below 1 a flare-up).
var calm := 1.0
var _all: Array = []         # every clown on the floor (the game's own list)

# effects (tests count them)
var far_flashes := 0
var flares := 0
var tracer_bursts := 0
var _t_flash := 1.0
var _t_flare := 12.0
var _t_tracer := 6.0
var _flare_nodes: Array = []
var _glow: StandardMaterial3D
var _trace_mat: StandardMaterial3D


## Hands jobs to the WitzSoldats on the floor and moves each to his place. The
## officer, the gunners, the clockwork men and the clowns keep to themselves.
## Nobody is put within `keep_clear` metres of where the player starts.
func assign(m: TrenchMaze, clowns: Array, seed_: int, start: Vector3, keep_clear := 14.0) -> void:
	maze = m
	_all = clowns
	rng.seed = seed_
	field = TrenchField.new()
	field.name = "Field"
	add_child(field)
	var art := m.get_node_or_null("Art") as TrenchArt
	if art:
		field.setup(m, art, seed_ + 77, player, get_tree().get_first_node_in_group(&"game"))
		fog = TrenchFog.new()
		fog.name = "Fog"
		add_child(fog)
		fog.setup(m, art, self, seed_ + 131)
	counts = {frontline = 0, guard = 0, runner = 0, patrol = 0, bridge_runs = 0}
	var men: Array = []
	for c in clowns:
		if c is Clown and (c.body in ["witzsoldat", "klappersoldat"] or c is Rattlejack) and c.get_node_or_null("Brain") != null:
			men.append(c)
	_shuffle(men)
	var far := func(p: Vector3) -> bool: return Vector3(p.x - start.x, 0, p.z - start.z).length() >= keep_clear
	# the places
	var fire: Array[Vector3] = []
	for c: Vector2i in m.bays:
		var p := Vector3((c.x + 0.5) * m.cell + rng.randf_range(-0.3, 0.3), 0, c.y * m.cell + TrenchMaze.EDGE + 0.45)
		p.y = m.floor_height(p)
		if far.call(p):
			fire.append(p)
	_shuffle(fire)
	var guards: Array = []        # [post, face, face_b]
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			var inward := Vector3(l.dir.x, 0, l.dir.y)
			var side := Vector3(l.dir.y, 0, l.dir.x)
			var p := m.cell_center(l.entrance) - inward * 0.5 + side * 0.6
			p.y = m.floor_height(p)
			if far.call(p):
				guards.append([p, side, -side])
	for c: Vector2i in m.kind:
		if m.kind[c] == "junction" and m.open_cells.has(c):
			var p := m.cell_center(c)
			if far.call(p):
				guards.append([p, Vector3(1, 0, 0), Vector3(0, 0, 1)])
	_shuffle(guards)
	var bridge_runs: Array = []
	for br: Dictionary in m.bridges:
		var a := m.cell_center(br.ends[0])
		var b := m.cell_center(br.ends[1])
		if m.path_cells(br.ends[0], br.ends[1]) < 9999 and far.call(a) and far.call(b):
			bridge_runs.append([a, b])
	_shuffle(bridge_runs)
	var trench_runs: Array = []
	var support: Array[Vector2i] = []
	var front: Array[Vector2i] = []
	for c: Vector2i in m.kind:
		if not m.open_cells.has(c) or m.bays.has(c):
			continue
		if m.kind[c] in ["support", "reserve"]:
			support.append(c)
		elif m.kind[c] == "fire":
			front.append(c)
	for i in 6:
		if support.is_empty() or front.is_empty():
			break
		var s: Vector2i = support[rng.randi() % support.size()]
		var f: Vector2i = front[rng.randi() % front.size()]
		if m.path_cells(s, f) < 9999 and far.call(m.cell_center(s)) and far.call(m.cell_center(f)):
			trench_runs.append([m.cell_center(s), m.cell_center(f)])
	var patrols: Array = []
	var tops: Array[Vector2i] = []
	for c: Vector2i in m.top_cells:
		tops.append(c)
	tops.sort()
	for i in 12:
		if tops.size() < 2:
			break
		var a: Vector2i = tops[rng.randi() % tops.size()]
		var b: Vector2i = tops[rng.randi() % tops.size()]
		var pa := m.cell_center(a)
		var pb := m.cell_center(b)
		if pa.distance_to(pb) >= 8.0 and m.path_cells(a, b) < 9999 and far.call(pa) and far.call(pb):
			patrols.append([pa, pb])
	_shuffle(patrols)
	# up on the open ground in front of the fire trench: riflemen behind what cover there is
	var top_fire: Array[Vector3] = []
	var front_tops: Array[Vector2i] = []
	for c: Vector2i in tops:
		if c.y <= TrenchMaze.FIRE_ROW - 2:
			front_tops.append(c)
	_shuffle(front_tops)
	for c: Vector2i in front_tops:
		var p := m.cell_center(c)
		if far.call(p) and top_fire.all(func(q: Vector3) -> bool: return q.distance_to(p) > 4.0):
			top_fire.append(p)
	# sentries up top where they look down into a trench
	var sentries: Array = []       # [post, face]
	for c: Vector2i in tops:
		for dir in Maze.DIRS:
			var t: Vector2i = c + dir * 2
			if m.open_cells.has(t) and not m.top_cells.has(t) and not m.bays.has(t):
				var p := m.cell_center(c)
				if far.call(p):
					sentries.append([p, Vector3(dir.x, 0, dir.y)])
				break
	_shuffle(sentries)
	# the marksman: up top, a long way from the start, watching back over the trenches
	var marks: Array = []
	var centre := Vector3(m.w * m.cell * 0.5, 0, m.d * m.cell * 0.5)
	for c: Vector2i in tops:
		var p := m.cell_center(c)
		var ds := Vector3(p.x - start.x, 0, p.z - start.z).length()
		if ds >= 28.0 and ds <= 60.0:
			var f := Vector3(start.x - p.x, 0, start.z - p.z).normalized().lerp(Vector3(centre.x - p.x, 0, centre.z - p.z).normalized(), 0.4).normalized()
			marks.append([p, f])
	_shuffle(marks)
	# climbing out and going back: from up in front of the fire trench to a support trench
	var climbs: Array = []
	for i in 30:
		if climbs.size() >= 4 or front_tops.is_empty() or support.is_empty():
			break
		var a: Vector2i = front_tops[rng.randi() % front_tops.size()]
		var b: Vector2i = support[rng.randi() % support.size()]
		if m.path_cells(a, b) < 9999 and far.call(m.cell_center(a)) and far.call(m.cell_center(b)):
			climbs.append([m.cell_center(a), m.cell_center(b)])
	# beats along the trenches, round the bends
	var beats: Array = []
	var trench_cells: Array[Vector2i] = []
	for c: Vector2i in m.open_cells:
		if not m.top_cells.has(c) and not (m.kind.get(c, "") in ["dugout", "gunpit", "op"]):
			trench_cells.append(c)
	trench_cells.sort()
	for i in 60:
		if beats.size() >= 6 or trench_cells.size() < 3:
			break
		var a: Vector2i = trench_cells[rng.randi() % trench_cells.size()]
		var b: Vector2i = trench_cells[rng.randi() % trench_cells.size()]
		var c2: Vector2i = trench_cells[rng.randi() % trench_cells.size()]
		var ab := m.path_cells(a, b)
		var bc := m.path_cells(b, c2)
		if ab >= 6 and ab <= 18 and bc >= 5 and bc <= 18 and far.call(m.cell_center(a)) and far.call(m.cell_center(b)) and far.call(m.cell_center(c2)):
			beats.append([m.cell_center(a), m.cell_center(b), m.cell_center(c2), m.cell_center(b)])
	_shuffle(beats)
	if OS.get_cmdline_user_args().has("battle_debug"):
		print("        places: fire %d, top_fire %d (front tops %d of %d tops), sentries %d, marks %d, guards %d, bridge runs %d, climbs %d, beats %d, patrols %d" % [fire.size(), top_fire.size(), front_tops.size(), tops.size(), sentries.size(), marks.size(), guards.size(), bridge_runs.size(), climbs.size(), beats.size(), patrols.size()])
	# who does what. Riflemen: one marksman, then the fire steps, the open
	# ground in front, runners and patrols. Gunners (the Lewis guns): the fire
	# steps and the top, looking down. Clubmen and the clockwork men: beats
	# (often in pairs), guard posts, runs. A few of each are left free.
	for k: String in ["marksman", "frontline", "top_rifle", "guard", "sentry", "runner", "patrol", "trench_patrol"]:
		counts[k] = 0
	counts.climb_runs = 0
	counts.pairs = 0
	var pair_with: BattleDuty = null
	var riflemen := men.filter(func(c: Clown) -> bool: return c.body == "witzsoldat" and c.has_rifle)
	# each kind of man takes the next job on his list (then the one after, if
	# that has no place left), so a floor gets a spread of them
	var lists := {
		rifleman = ["frontline", "top_rifle", "runner", "frontline", "top_rifle", "patrol", "sentry", "runner", "frontline", "free"],
		gunner = ["frontline", "sentry", "free"],
		clubman = ["trench_patrol", "runner", "guard", "free"],
		klapper = ["trench_patrol", "guard", "trench_patrol", "runner", "free"],
	}
	var next := {rifleman = 0, gunner = rng.randi() % 3, clubman = rng.randi() % 4, klapper = rng.randi() % 5}
	var make := func(job: String) -> BattleDuty:
		var d: BattleDuty = null
		match job:
			"frontline":
				if not fire.is_empty():
					d = BattleDuty.new(BattleDuty.Kind.FRONTLINE)
					d.post = fire.pop_back()
					d.face = Vector3(0, 0, -1)
			"top_rifle":
				if not top_fire.is_empty():
					d = BattleDuty.new(BattleDuty.Kind.TOP_RIFLE)
					d.post = top_fire.pop_back()
					d.face = Vector3(0, 0, -1)
			"sentry":
				if not sentries.is_empty():
					var se: Array = sentries.pop_back()
					d = BattleDuty.new(BattleDuty.Kind.SENTRY)
					d.post = se[0]
					d.face = se[1]
					d.face_b = (se[1] as Vector3).rotated(Vector3.UP, 1.2)
			"guard":
				if not guards.is_empty():
					var g: Array = guards.pop_back()
					d = BattleDuty.new(BattleDuty.Kind.GUARD)
					d.post = g[0]
					d.face = g[1]
					d.face_b = g[2]
			"runner":
				if not (bridge_runs.is_empty() and trench_runs.is_empty() and climbs.is_empty()):
					d = BattleDuty.new(BattleDuty.Kind.RUNNER)
					var r: Array
					if not climbs.is_empty() and (bridge_runs.is_empty() or counts.climb_runs <= counts.bridge_runs):
						r = climbs.pop_back()
						counts.climb_runs += 1
					elif not bridge_runs.is_empty():
						r = bridge_runs.pop_back()
						counts.bridge_runs += 1
					else:
						r = trench_runs.pop_back()
					d.route.assign(r)
					d.post = r[0]
			"patrol":
				if not patrols.is_empty():
					d = BattleDuty.new(BattleDuty.Kind.PATROL)
					var r: Array = patrols.pop_back()
					d.route.assign(r)
					d.post = r[0]
			"trench_patrol":
				if not beats.is_empty():
					d = BattleDuty.new(BattleDuty.Kind.TRENCH_PATROL)
					var r: Array = beats.pop_back()
					d.route.assign(r)
					d.post = r[0]
		return d
	for c: Clown in men:
		var brain := c.get_node("Brain") as ClownBrain
		var d: BattleDuty = null
		var kind_of := "clubman"
		if c is Rattlejack:
			kind_of = "gunner"
		elif c.body == "klappersoldat":
			kind_of = "klapper"
		elif c.has_rifle:
			kind_of = "rifleman"
		if pair_with != null and kind_of in ["klapper", "clubman", "rifleman"]:
			# the second of a pair: the same beat, a step or two behind
			d = BattleDuty.new(BattleDuty.Kind.TRENCH_PATROL)
			d.route.assign(pair_with.route)
			d.post = pair_with.post
			d.follow_delay = rng.randf_range(0.9, 1.6)
			d.leader = pair_with
			pair_with.follower = d
			counts.pairs += 1
			pair_with = null
		elif kind_of == "rifleman" and counts.marksman == 0 and riflemen.size() >= 3 and not marks.is_empty():
			var mk: Array = marks.pop_back()
			d = BattleDuty.new(BattleDuty.Kind.MARKSMAN)
			d.post = mk[0]
			d.face = mk[1]
			d.candidates = marks.slice(0, 12)
		else:
			var lst: Array = lists[kind_of]
			for k in lst.size():
				var job: String = lst[(next[kind_of] + k) % lst.size()]
				if job == "free":
					next[kind_of] += k + 1
					break
				d = make.call(job)
				if d != null:
					next[kind_of] += k + 1
					break
			if d != null and d.kind == BattleDuty.Kind.TRENCH_PATROL and rng.randf() < 0.5:
				pair_with = d               # the next man goes with him
		if d == null:
			continue
		counts[d.name_of()] += 1
		d.name = "Duty"
		c.add_child(d)
		d.attach(brain)
		var at := d.post
		if d.follow_delay > 0.0:
			at += Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		c.global_position = at
		c.global_position.y = m.floor_height(at)
		c.rotation.y = atan2(d.face.x, d.face.z)
		brain._wander_to = Vector3.INF
		duties.append(d)
	_place_marksman.call_deferred()


## The marksman's place: of his candidates, the one with the most of the
## ground in view (25-70 m off, in his arc), once the collision is in.
func _place_marksman() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for d: BattleDuty in duties:
		if d.kind != BattleDuty.Kind.MARKSMAN or not is_instance_valid(d.clown):
			continue
		var best := -1
		var best_p := d.post
		var best_f := d.face
		var options: Array = [[d.post, d.face]]
		options.append_array(d.candidates)
		for o: Array in options:
			var p: Vector3 = o[0]
			var f: Vector3 = o[1]
			var eye := p + Vector3.UP * 1.5
			var n := 0
			var tried := 0
			for c: Vector2i in maze.open_cells:
				if (c.x + c.y) % 3 != 0:
					continue
				var q := maze.cell_center(c) + Vector3.UP * 1.55
				var dd := eye.distance_to(q)
				if dd < 25.0 or dd > 70.0 or Vector3(f.x, 0, f.z).dot(Vector3(q.x - eye.x, 0, q.z - eye.z).normalized()) < cos(deg_to_rad(75.0)):
					continue
				tried += 1
				var r := PhysicsRayQueryParameters3D.create(eye, q, 1)
				if space.intersect_ray(r).is_empty():
					n += 1
			if n > best:
				best = n
				best_p = p
				best_f = f
		d.post = best_p
		d.face = best_f
		d.view = best
		d.clown.global_position = best_p
		d.clown.global_position.y = maze.floor_height(best_p)
		d.clown.rotation.y = atan2(best_f.x, best_f.z)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# --- the enemy across No Man's Land: effects only ----------------------------------
func _ready() -> void:
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.albedo_color = Color(1.0, 0.86, 0.6)
	_glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trace_mat = StandardMaterial3D.new()
	_trace_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trace_mat.albedo_color = Color(1.0, 0.55, 0.28)
	_trace_mat.emission_enabled = true
	_trace_mat.emission = Color(1.0, 0.5, 0.25)
	_trace_mat.emission_energy_multiplier = 3.0


var steps := {}            ## the soldiers' footsteps heard (tests): surface -> count
var volleys := 0
var rattles := 0
var _t_volley := 20.0
var _stride := {}          # clown -> [distance since the last step, last position]


# --- pacing ------------------------------------------------------------------
## The battle's rhythm: a lull (the far side's fire thins out, the field's
## shells and casualties come slower, the ambience's guns too), the ordinary
## din, and now and then a flare-up. `calm` is what the rest read.
enum Pace { NORMAL, LULL, SURGE }
var pace := Pace.NORMAL
var pace_changes := 0
var _t_pace := 70.0
## Encounters sent across the player's way (tests count them).
var encounters := 0
var encounter_log: Array = []      ## [man, crossing point, player position then]
var _t_encounter := 35.0
var calls := 0
var screams := 0
var _t_call := 14.0
var _t_scream := 70.0


func _pace(delta: float) -> void:
	_t_pace -= delta
	if _t_pace <= 0.0:
		pace_changes += 1
		match pace:
			Pace.NORMAL:
				pace = Pace.LULL if rng.randf() < 0.6 else Pace.SURGE
			_:
				pace = Pace.NORMAL
		match pace:
			Pace.NORMAL:
				_t_pace = rng.randf_range(60.0, 120.0)
			Pace.LULL:
				_t_pace = rng.randf_range(30.0, 60.0)
			Pace.SURGE:
				_t_pace = rng.randf_range(20.0, 35.0)
	var want := {Pace.NORMAL: 1.0, Pace.LULL: 2.6, Pace.SURGE: 0.5}[pace] as float
	calm = move_toward(calm, want, delta * 0.4)
	var amb := maze.get_node_or_null("Art/Ambience")
	if amb:
		amb.calm = calm


func _process(delta: float) -> void:
	if maze == null:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	_pace(delta)
	_footsteps()
	_encounter(delta)
	_voices(delta)
	_t_volley -= delta
	if _t_volley <= 0.0:
		_t_volley = rng.randf_range(25.0, 50.0) * calm
		_volley()
	var w := maze.w * maze.cell
	_t_flash -= delta
	if _t_flash <= 0.0:
		_t_flash = rng.randf_range(0.4, 2.2) * calm * calm
		_far_flash(Vector3(rng.randf_range(-40.0, w + 40.0), rng.randf_range(0.6, 1.4), -rng.randf_range(85.0, 150.0)))
	_t_flare -= delta
	if _t_flare <= 0.0:
		_t_flare = rng.randf_range(14.0, 30.0) * calm
		_flare(Vector3(rng.randf_range(-10.0, w + 10.0), 0.0, -rng.randf_range(25.0, 60.0)))
	_t_tracer -= delta
	if _t_tracer <= 0.0:
		_t_tracer = rng.randf_range(7.0, 16.0) * calm
		_tracers(rng.randi_range(6, 14))
	for f: Array in _flare_nodes.duplicate():
		var n: Node3D = f[0]
		f[1] -= delta
		if f[1] <= 0.0 or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_flare_nodes.erase(f)
			continue
		var v: Vector3 = f[2]
		v.y = maxf(v.y - 9.8 * delta, -1.2)      # up, then under its parachute
		f[2] = v
		n.position += v * delta
		var l: OmniLight3D = n.get_child(0)
		l.light_energy = 2.2 * clampf(f[1] / 3.0, 0.0, 1.0) * (0.85 + 0.15 * sin(f[1] * 23.0))


## Now and then (not too often, never while one is under way) a man on a
## round of his duty is sent across the player's way a little ahead of him:
## through a junction or a stretch of trench he has not got to yet, out of
## sight, along the real trenches from wherever the man is (never from behind
## the player, never from nowhere). He walks through and goes back to his
## duty; if he sees the player on the way, it is a fight.
func _encounter(delta: float) -> void:
	_t_encounter -= delta
	if _t_encounter > 0.0 or player == null:
		return
	_t_encounter = rng.randf_range(30.0, 60.0) * clampf(calm, 0.7, 1.6)
	for d: BattleDuty in duties:
		if is_instance_valid(d) and not d.detour.is_empty():
			return                                   # one at a time
	if maze.on_top(player.global_position):
		return
	var pc := maze.cell_of(player.global_position)
	var to_exit := maze.path_cells(pc, maze.exit_cell)
	var head := player.global_position + Vector3.UP * 1.6
	var space := get_world_3d().direct_space_state
	var crossings: Array[Vector2i] = []
	for c: Vector2i in maze.open_cells:
		if maze.top_cells.has(c) or maze.kind.get(c, "") in ["dugout", "gunpit", "op"]:
			continue
		var pd := maze.path_cells(pc, c)
		if pd < 7 or pd > 16 or maze.path_cells(c, maze.exit_cell) >= to_exit:
			continue                                 # ahead of him, 10-24 m on
		var q := PhysicsRayQueryParameters3D.create(head, maze.cell_center(c) + Vector3.UP * 1.4, 1)
		if space.intersect_ray(q).is_empty():
			continue                                 # in his sight now: no
		crossings.append(c)
	if crossings.is_empty():
		return
	crossings.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return int(maze.kind.get(a, "") == "junction") > int(maze.kind.get(b, "") == "junction"))
	var x: Vector2i = crossings[0] if rng.randf() < 0.6 else crossings[rng.randi() % crossings.size()]
	# who: a man on a round (not one at a post), out of sight, not behind the player
	var best: BattleDuty = null
	var best_d := 9999
	for d: BattleDuty in duties:
		if not is_instance_valid(d) or not is_instance_valid(d.clown) or d.clown.dead or d.brain.mind != ClownBrain.Mind.IDLE:
			continue
		if not (d.kind in [BattleDuty.Kind.RUNNER, BattleDuty.Kind.TRENCH_PATROL, BattleDuty.Kind.PATROL]) or d.leader != null:
			continue
		var mc := maze.cell_of(d.clown.global_position)
		var md := maze.path_cells(mc, x)
		if md < 4 or md > 26 or maze.path_cells(mc, pc) <= maze.path_cells(x, pc):
			continue                                 # he would come through the player
		var q := PhysicsRayQueryParameters3D.create(head, d.clown.global_position + Vector3.UP * 1.4, 1)
		if space.intersect_ray(q).is_empty():
			continue
		if md < best_d:
			best_d = md
			best = d
	if best == null:
		return
	# through the crossing and on a cell or two the far side of it
	var beyond := x
	for dir in Maze.DIRS:
		var n: Vector2i = x + dir
		if maze.linked(x, n) and maze.path_cells(pc, n) > maze.path_cells(pc, x) and maze.path_cells(maze.cell_of(best.clown.global_position), n) > maze.path_cells(maze.cell_of(best.clown.global_position), x):
			beyond = n
			break
	best.detour.assign([maze.cell_center(x), maze.cell_center(beyond)])
	encounters += 1
	encounter_log.append([best, maze.cell_center(x), player.global_position])


## Voices: a man somewhere off along the trenches calling to another (out of
## sight, 12-40 m), and screams from out in No Man's Land, far, now and then.
func _voices(delta: float) -> void:
	if player == null:
		return
	_t_call -= delta
	if _t_call <= 0.0:
		_t_call = rng.randf_range(14.0, 32.0) * calm
		var pick: Array[BattleDuty] = []
		for d: BattleDuty in duties:
			if is_instance_valid(d) and is_instance_valid(d.clown) and not d.clown.dead and d.brain.mind == ClownBrain.Mind.IDLE:
				var dd := d.clown.global_position.distance_to(player.global_position)
				if dd > 12.0 and dd < 40.0:
					pick.append(d)
		if not pick.is_empty():
			var d: BattleDuty = pick.pick_random()
			calls += 1
			SfxSynth.play(d.clown, "shout", d.clown.global_position + Vector3.UP * 1.6, -5.0, rng.randf_range(0.78, 1.12), 7.0, 55.0)
	_t_scream -= delta
	if _t_scream <= 0.0:
		_t_scream = rng.randf_range(60.0, 140.0) * calm
		scream(Vector3(player.global_position.x + rng.randf_range(-40.0, 40.0), 0.5, -rng.randf_range(45.0, 90.0)), -12.0)


## A man screaming out there (a wounded man in No Man's Land).
func scream(at: Vector3, db := -8.0) -> void:
	screams += 1
	SfxSynth.play(self, "scream", at, db, rng.randf_range(0.85, 1.1), 20.0, 250.0)


## The soldiers' boots, near enough to hear: squelching in the mud, knocking on
## the duckboards and the footbridges (a creak under the weight), splashing.
func _footsteps() -> void:
	if player == null:
		return
	var all := _all.duplicate()
	if field:
		for s: FieldSoldier in field.men:
			if is_instance_valid(s):
				all.append(s.clown)
	for c in all:
		if not is_instance_valid(c) or c.dead:
			_stride.erase(c)
			continue
		var at: Vector3 = c.global_position
		if at.distance_squared_to(player.global_position) > 28.0 * 28.0:
			_stride[c] = [0.0, at]
			continue
		var st: Array = _stride.get(c, [0.0, at])
		var moved := Vector2(at.x - st[1].x, at.z - st[1].z).length()
		st[1] = at
		if moved > 1.0:
			moved = 0.0
		st[0] += moved
		_stride[c] = st
		var stride := 0.85 if c.run_amount > 0.5 else 0.65
		if st[0] < stride:
			continue
		st[0] = 0.0
		var on_bridge := not maze.bridge_at(at + Vector3.UP * 0.2).is_empty()
		var surf := "bridge" if on_bridge else maze.surface_at(at)
		steps[surf] = steps.get(surf, 0) + 1
		if on_bridge:
			SfxSynth.play(self, "bridge_step", at, -6.0, rng.randf_range(0.85, 1.1), 5.0, 35.0)
			if rng.randf() < 0.3:
				SfxSynth.play(self, "timber_creak", at, -12.0, rng.randf_range(0.9, 1.25), 5.0, 35.0)
		else:
			SfxSynth.play(self, "fs_" + surf, at + Vector3.UP * 0.05, -12.0 if surf != "water" else -9.0, rng.randf_range(0.85, 1.05), 5.0, 30.0)
		if rng.randf() < 0.05:
			rattles += 1
			SfxSynth.play(self, "metal_rattle", at + Vector3.UP * 1.0, -18.0, rng.randf_range(1.1, 1.5), 4.0, 22.0)   # his kit


## A volley from their line: a ragged string of rifle shots and flashes.
func _volley() -> void:
	volleys += 1
	var w := maze.w * maze.cell
	var centre := Vector3(rng.randf_range(0.0, w), 1.0, -rng.randf_range(90.0, 140.0))
	for i in rng.randi_range(5, 10):
		var at := centre + Vector3(rng.randf_range(-25.0, 25.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-6.0, 6.0))
		get_tree().create_timer(rng.randf_range(0.0, 1.4)).timeout.connect(func() -> void:
			if is_inside_tree():
				_far_flash(at)
				SfxSynth.play(self, "rifle_far", at.lerp(player.global_position if player else at, 0.6), -10.0, rng.randf_range(0.85, 1.1), 30.0, 400.0))


## A rifle or a machine gun firing over there: a pinprick of light, the crack later.
func _far_flash(at: Vector3) -> void:
	far_flashes += 1
	var q := QuadMesh.new()
	q.size = Vector2.ONE * rng.randf_range(0.5, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _glow
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	get_tree().create_timer(0.07).timeout.connect(mi.queue_free)


## A star shell: up from their line, hangs, drifts down, lighting the mist.
func _flare(at: Vector3) -> void:
	flares += 1
	var n := Node3D.new()
	add_child(n)
	n.position = at + Vector3(0, 1.0, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(0.95, 0.92, 0.8)
	l.light_energy = 2.2
	l.omni_range = 40.0
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 2.0
	n.add_child(l)
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.35
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _glow
	n.add_child(mi)
	_flare_nodes.append([n, rng.randf_range(9.0, 13.0), Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(24.0, 30.0), rng.randf_range(0.0, 2.0))])


## Their machine gun searching high: tracer passing well over the trenches.
func _tracers(n: int) -> void:
	tracer_bursts += 1
	var w := maze.w * maze.cell
	var from := Vector3(rng.randf_range(-20.0, w + 20.0), 1.0, -rng.randf_range(90.0, 130.0))
	var aim := Vector3(rng.randf_range(0.0, w), rng.randf_range(6.0, 14.0), maze.d * maze.cell + 30.0)
	for i in n:
		get_tree().create_timer(i * 0.11).timeout.connect(_one_tracer.bind(from, aim + Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-1.0, 1.0), 0)))


func _one_tracer(from: Vector3, to: Vector3) -> void:
	if not is_inside_tree():
		return
	var dir := (to - from).normalized()
	var b := BoxMesh.new()
	b.size = Vector3(0.05, 0.05, 2.2)
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = _trace_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	mi.look_at(from + dir, Vector3.UP)
	var tw := create_tween()
	var t := from.distance_to(to) / 260.0
	tw.tween_property(mi, "global_position", to, t)
	tw.tween_callback(mi.queue_free)
