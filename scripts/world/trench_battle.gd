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
	counts = {frontline = 0, guard = 0, runner = 0, patrol = 0, bridge_runs = 0}
	var men: Array = []
	for c in clowns:
		if c is Clown and c.body == "witzsoldat" and c.get_node_or_null("Brain") != null:
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
	# who does what: about four in ten on the step, the rest shared out
	var n := men.size()
	var want := {
		frontline = int(round(n * 0.4)),
		guard = int(round(n * 0.15)),
		runner = int(round(n * 0.15)),
		patrol = int(round(n * 0.15)),
	}
	for c: Clown in men:
		var brain := c.get_node("Brain") as ClownBrain
		var d: BattleDuty = null
		if counts.frontline < want.frontline and c.has_rifle and not fire.is_empty():
			d = BattleDuty.new(BattleDuty.Kind.FRONTLINE)
			d.post = fire.pop_back()
			d.face = Vector3(0, 0, -1)
		elif counts.guard < want.guard and not guards.is_empty():
			var g: Array = guards.pop_back()
			d = BattleDuty.new(BattleDuty.Kind.GUARD)
			d.post = g[0]
			d.face = g[1]
			d.face_b = g[2]
		elif counts.runner < want.runner and not (bridge_runs.is_empty() and trench_runs.is_empty()):
			d = BattleDuty.new(BattleDuty.Kind.RUNNER)
			var r: Array
			if not bridge_runs.is_empty():
				r = bridge_runs.pop_back()
				counts.bridge_runs += 1
			else:
				r = trench_runs.pop_back()
			d.route.assign(r)
			d.post = r[0]
		elif counts.patrol < want.patrol and not patrols.is_empty():
			d = BattleDuty.new(BattleDuty.Kind.PATROL)
			var r: Array = patrols.pop_back()
			d.route.assign(r)
			d.post = r[0]
		if d == null:
			continue
		counts[d.name_of()] += 1
		d.name = "Duty"
		c.add_child(d)
		d.attach(brain)
		c.global_position = d.post
		c.global_position.y = m.floor_height(d.post)
		c.rotation.y = atan2(d.face.x, d.face.z)
		brain._wander_to = Vector3.INF
		duties.append(d)


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
var _t_volley := 20.0
var _stride := {}          # clown -> [distance since the last step, last position]


func _process(delta: float) -> void:
	if maze == null:
		return
	_footsteps()
	_t_volley -= delta
	if _t_volley <= 0.0:
		_t_volley = rng.randf_range(25.0, 50.0)
		_volley()
	var w := maze.w * maze.cell
	_t_flash -= delta
	if _t_flash <= 0.0:
		_t_flash = rng.randf_range(0.4, 2.2)
		_far_flash(Vector3(rng.randf_range(-40.0, w + 40.0), rng.randf_range(0.6, 1.4), -rng.randf_range(85.0, 150.0)))
	_t_flare -= delta
	if _t_flare <= 0.0:
		_t_flare = rng.randf_range(14.0, 30.0)
		_flare(Vector3(rng.randf_range(-10.0, w + 10.0), 0.0, -rng.randf_range(25.0, 60.0)))
	_t_tracer -= delta
	if _t_tracer <= 0.0:
		_t_tracer = rng.randf_range(7.0, 16.0)
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


## The soldiers' boots, near enough to hear: squelching in the mud, knocking on
## the duckboards and the footbridges (a creak under the weight), splashing.
func _footsteps() -> void:
	if player == null:
		return
	for c in _all:
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
