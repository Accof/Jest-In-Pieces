class_name BloodPool
extends MeshInstance3D
## A pool of blood (or oil) that spreads over the real floor.
##
## When it is made it samples the level once: a grid of downward rays round
## its source (spread over a few frames by the Blood manager) gives the floor
## height and slope at each point, and which points are inside a wall or a
## box. A flood from the source(s) over that grid works out how soon the
## blood would reach each point:
##   - it cannot climb: a rise of more than CLIMB (a step, a door threshold,
##     a box) stops it;
##   - it runs downhill a little more readily than uphill;
##   - it can run down over a step edge (a drop of up to MAX_DROP), at most
##     `max_drops` times, and spreads less on the lower surface each time,
##     so a little blood does not make a lake at the bottom of the stairs;
##   - walls and boxes block it, so it goes round them and along them.
## Each source also has its own outline (an ellipse at a random angle, a few
## soft lobes, now and then a narrow tongue), so no two pools are alike.
##
## The mesh is built on the floor itself: flat quads where a grid cell sits
## on one surface; where a step edge or a wall runs through a cell, the cell
## is split at the edge (found by a few more rays), each side lies on its own
## surface, and a vertical strip runs down the riser between them. Nothing
## spans two heights, so nothing floats.
##
## (Samples just past the outline get an arrival a little after the end, so the
## edge is drawn as a smooth line between samples.)
## Every vertex carries the moment the blood reaches it (`UV2.x`, in units of
## progress) and how thick it can get there (`UV2.y`). The shader draws the
## pool up to `progress`, which the manager raises over the expansion time,
## so growing costs nothing but one instance parameter per frame.

const CLIMB := 0.025          ## a rise blood cannot flow over (m)
const MAX_DROP := 0.45        ## the largest step it will run down (m)
const SAMPLE_UP := 0.45       ## rays start this far above the source
const SAMPLE_DOWN := 1.35     ## and look this far below it
const NEVER := 1000.0
## Above the surface: clear of painted floor decals (the circus sunbursts
## lie 4 mm up) without visibly floating.
const LIFT := 0.011
## What blood lies on: the world, and visual-only floors such as trench
## duckboards (their own collision layer, which nothing else uses).
const SURFACES := 1 | (1 << 5)

var oil := false
var spacing := 0.08
var half := 0.8               ## half-width of the sampled square
var centre := Vector3.ZERO    ## world: middle of the sampled square, at the source's floor height
var n := 0                    ## samples per side
var cfg := {}                 ## the manager's settings

var _h := PackedFloat32Array()        # floor height (world y)
var _nrm := PackedVector3Array()
var _cls := PackedInt32Array()        # 0 floor, -1 nothing usable (void, too steep), -2 inside something solid
var _sampled := 0
enum Stage { SAMPLE, SOLVE, BUILD, DONE }
var stage := Stage.SAMPLE
var _built_once := false
# the flood, worked a slice at a time
var _src_i := 0
var _dist := PackedFloat32Array()
var _mult := PackedFloat32Array()
var _drops := PackedInt32Array()
var _heap: _Heap
var _src_start := -1
var _seed := 0.0
# the mesh, a few rows at a time
var _st: SurfaceTool
var _row := 0
var _tris := 0
var _risers := 0
var sources: Array = []               # {pos, r, shift, shape}
var _v := PackedFloat32Array()        # when the blood gets to each sample (progress units)
var _pot := PackedFloat32Array()      # how thick it can get there 0..1
## Per source: how far out each sample is, as a fraction of that source's own
## outline (1 = on its edge). Each vertex carries the four (CUSTOM0), and the
## shader draws every source's front only up to its own outline, so the edge is
## worked out per pixel from a smooth field: no stair-steps along the grid.
var _rel: Array = []
const FAR := 9.0                      ## "not reached" in a vertex's per-source fraction
var _cross := {}                      # edge key -> crossing result (rays cached)

var progress := 0.0
var p_end := 1.0
var _p_from := 0.0
var _t := 0.0
var expand := 5.0
var settle := 2.0
var settled := false
var age := 0.0
var born := 0.0
var wet_cells := 0                    ## tests: samples that end up wet
var riser_quads := 0                  ## tests: strips run down step faces
var rays_used := 0                    ## tests / budget


func setup(pos: Vector3, radius: float, is_oil: bool, settings: Dictionary, sample_spacing: float) -> void:
	oil = is_oil
	cfg = settings
	spacing = sample_spacing
	half = clampf(radius * 1.6 + 0.2, 0.35, maxf(float(cfg.max_pool_radius), radius) * 1.5)
	n = int(ceil(half * 2.0 / spacing)) + 1
	half = (n - 1) * spacing * 0.5
	centre = pos
	_h.resize(n * n)
	_nrm.resize(n * n)
	_cls.resize(n * n)
	_cls.fill(-1)
	_sampled = 0
	_seed = randf() * 50.0
	sources = []
	_add_source(pos, radius, 0.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = 2
	set_instance_shader_parameter("progress", 0.0)
	set_instance_shader_parameter("seed", randf() * 10.0)
	set_instance_shader_parameter("fade", 1.0)
	set_instance_shader_parameter("age", 0.0)
	born = Time.get_ticks_msec() / 1000.0


func sampling_done() -> bool:
	return stage == Stage.DONE


## Do as much of the pool's setting-up as fits before `deadline_us`: the
## rays, then the flood, then the mesh. Returns true when there is nothing
## left to do.
func work(space: PhysicsDirectSpaceState3D, deadline_us: int) -> bool:
	var iters := 0
	while stage != Stage.DONE:
		iters += 1
		if iters % 8 == 0 and Time.get_ticks_usec() > deadline_us:
			return false
		match stage:
			Stage.SAMPLE:
				_sample_one(space)
				if _sampled >= n * n:
					_begin_solve()
			Stage.SOLVE:
				_solve_step()
			Stage.BUILD:
				_build_row(space)
	return true


func _sample_one(space: PhysicsDirectSpaceState3D) -> void:
	var k := _sampled
	var p := _grid_pos(k % n, k / n)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, centre.y + SAMPLE_UP, p.z), Vector3(p.x, centre.y - SAMPLE_DOWN, p.z), SURFACES)
	q.hit_from_inside = true
	var hit := space.intersect_ray(q)
	rays_used += 1
	if hit.is_empty():
		_cls[k] = -1
	elif (hit.normal as Vector3) == Vector3.ZERO or (hit.position as Vector3).y > centre.y + SAMPLE_UP - 0.01:
		_cls[k] = -2                                   # the ray started inside a wall or a box
	elif (hit.normal as Vector3).y < 0.7:
		_cls[k] = -1                                   # too steep to hold blood
	else:
		_cls[k] = 0
		_h[k] = (hit.position as Vector3).y
		_nrm[k] = hit.normal
	_sampled += 1


## Another body (or wound) bleeding into this pool: it spreads from there too,
## starting now, into the same mesh (no second pool on top).
func feed(pos: Vector3, radius: float, space: PhysicsDirectSpaceState3D) -> void:
	for s: Dictionary in sources:
		if (s.pos as Vector3).distance_to(pos) < 0.35:
			s.r = minf(sqrt(float(s.r) * float(s.r) + radius * radius * 0.6), half * 0.9)
			if _sampled >= n * n:
				_begin_solve()
			return
	if sources.size() >= 4:
		var s: Dictionary = sources.back()
		s.r = minf(sqrt(float(s.r) * float(s.r) + radius * radius * 0.5), half * 0.9)
	else:
		_add_source(pos, minf(radius, half * 0.9), progress)
	if _sampled >= n * n:
		_begin_solve()


## Whether a new pool at `pos` should feed this one instead.
func covers(pos: Vector3) -> bool:
	return absf(pos.x - centre.x) < half * 0.7 and absf(pos.z - centre.z) < half * 0.7 and absf(pos.y - centre.y) < 0.25


func _restart() -> void:
	_p_from = progress
	_t = 0.0
	settled = false


func _add_source(pos: Vector3, radius: float, shift: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var var_: float = cfg.shape_variation
	var shape := {
		aspect = 1.0 + var_ * rng.randf_range(0.1, 0.7),
		turn = rng.randf() * TAU,
		lobes = [],
		tongues = [],
	}
	for k in [2, 3, 4, 5]:
		shape.lobes.append([k, var_ * rng.randf_range(0.0, 0.16) / (0.6 * k), rng.randf() * TAU])
	for i in rng.randi_range(0, 2):
		shape.tongues.append([rng.randf() * TAU, var_ * rng.randf_range(0.2, 0.55), rng.randf_range(0.1, 0.2)])
	sources.append({pos = pos, r = radius, shift = shift, shape = shape})


## The outline: how far out the blood goes in direction `a`, relative to its
## radius (ellipse, lobes, tongues; area kept about the same).
static func _reach(shape: Dictionary, a: float) -> float:
	var asp: float = shape.aspect
	var t: float = a - float(shape.turn)
	var ea := sqrt(asp)
	var eb := 1.0 / ea
	var m := ea * eb / sqrt(pow(eb * cos(t), 2.0) + pow(ea * sin(t), 2.0))
	var l := 1.0
	for lb: Array in shape.lobes:
		l += float(lb[1]) * cos(float(lb[0]) * a - float(lb[2]))
	var tg := 1.0
	for t2: Array in shape.tongues:
		var d := angle_difference(a, float(t2[0]))
		tg += float(t2[1]) * exp(-pow(d / float(t2[2]), 2.0))
	return maxf(m * l * tg, 0.25)


func _grid_pos(i: int, j: int) -> Vector3:
	return Vector3(centre.x - half + i * spacing, centre.y, centre.z - half + j * spacing)


## The flood: for each source, Dijkstra over the grid with the costs above;
## then each sample's arrival is the earliest over the sources. Worked a slice
## at a time (see work()).
func _begin_solve() -> void:
	var count := n * n
	_v.resize(count)
	_v.fill(NEVER)
	_pot.resize(count)
	_pot.fill(0.0)
	_rel = []
	for i in 4:
		var r := PackedFloat32Array()
		r.resize(count)
		r.fill(FAR)
		_rel.append(r)
	wet_cells = 0
	_src_i = 0
	_src_start = -1
	stage = Stage.SOLVE


const _NB := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]


func _solve_step() -> void:
	if _src_i >= sources.size():
		_end_solve()
		return
	var s: Dictionary = sources[_src_i]
	var count := n * n
	if _src_start < 0:
		_src_start = _start_sample(s.pos)
		if _src_start < 0:
			_src_i += 1
			return
		_dist.resize(count)
		_dist.fill(INF)
		_mult.resize(count)
		_mult.fill(1.0)
		_drops.resize(count)
		_drops.fill(0)
		_heap = _Heap.new()
		_dist[_src_start] = 0.0
		_heap.push(0.0, _src_start)
	var slope_bias: float = cfg.slope_bias if cfg.slope_bias_on else 0.0
	var max_drops: int = cfg.max_drops if cfg.stair_flow else 0
	var limit: float = float(s.r) * 2.6
	# a handful of nodes per call
	for step in 6:
		if _heap.empty():
			break
		var top := _heap.pop()
		var d0: float = top[0]
		var u: int = top[1]
		if d0 > _dist[u]:
			continue
		if d0 > limit:
			_heap = _Heap.new()
			break
		var ui := u % n
		var uj := u / n
		for nb: Array in _NB:
			var wi: int = ui + nb[0]
			var wj: int = uj + nb[1]
			if wi < 0 or wj < 0 or wi >= n or wj >= n:
				continue
			var w := wj * n + wi
			if _cls[w] != 0:
				continue
			var diag: bool = nb[0] != 0 and nb[1] != 0
			if diag and _cls[uj * n + wi] != 0 and _cls[wj * n + ui] != 0:
				continue                                   # no squeezing between two blocked samples
			var length := spacing * (1.4142 if diag else 1.0)
			var dh := _h[w] - _h[u]
			var cost := length
			var m := _mult[u]
			var dr := _drops[u]
			if dh > CLIMB:
				continue                                   # it cannot climb a step or a sill
			elif dh < -CLIMB:
				if dr >= max_drops or -dh > MAX_DROP:
					continue
				# over the edge and down the face: easier at a few places along
				# the edge than elsewhere, so it runs over in narrow tongues,
				# not as one sheet
				var gp := _grid_pos(wi, wj)
				cost += 0.03 + (-dh) * 0.15 + 0.2 * smoothstep(0.35, 0.6, _lane(gp.x + gp.z * 0.37, _seed))
				m *= 1.3                                   # a thinner run below
				dr += 1
			else:
				var fall := clampf(-dh / length, -0.5, 0.5)
				cost *= clampf(1.0 - slope_bias * fall * 2.5, 0.55, 1.8)
			var nd := d0 + cost * m
			if nd < _dist[w]:
				_dist[w] = nd
				_mult[w] = m
				_drops[w] = dr
				_heap.push(nd, w)
	if _heap.empty():
		_finish_source(s)
		_src_i += 1
		_src_start = -1


func _start_sample(sp: Vector3) -> int:
	var si := clampi(int(round((sp.x - (centre.x - half)) / spacing)), 0, n - 1)
	var sj := clampi(int(round((sp.z - (centre.z - half)) / spacing)), 0, n - 1)
	var start := sj * n + si
	if _cls[start] == 0:
		return start
	# the source landed on an edge sample: the nearest floor sample at its height
	var best := -1
	var bd := INF
	for k in n * n:
		if _cls[k] == 0 and absf(_h[k] - sp.y) < 0.15:
			var gp := _grid_pos(k % n, k / n)
			var d := Vector2(gp.x - sp.x, gp.z - sp.z).length()
			if d < bd:
				bd = d
				best = k
	return best


## Shape it, and keep the volume: blood stopped by a wall or a step spreads
## further the other way.
func _finish_source(s: Dictionary) -> void:
	var count := n * n
	var sp: Vector3 = s.pos
	var r: float = s.r
	var wanted := PI * r * r
	var area := 0.0
	var reach := PackedFloat32Array()
	reach.resize(count)
	var x0 := centre.x - half - sp.x
	var z0 := centre.z - half - sp.z
	for k in count:
		if _dist[k] < INF:
			var a := atan2(z0 + (k / n) * spacing, x0 + (k % n) * spacing)
			reach[k] = r * _reach(s.shape, a)
			if _dist[k] < reach[k]:
				area += spacing * spacing
	var scale := clampf(sqrt(wanted / maxf(area, spacing * spacing)), 1.0, 2.0) if cfg.geometry else 1.0
	# the flood steps in 8 directions, so on open floor its distance is the
	# "octile" one and a round pool comes out an octagon (the square pools).
	# Scale each sample's distance by straight-line / octile from the source:
	# exact on open floor, and still longer round walls and down steps.
	var si := _src_start % n
	var sj := _src_start / n
	var rel_s: PackedFloat32Array = _rel[_src_i]
	for k in count:
		if _dist[k] >= INF:
			continue
		var di := absf(float(k % n - si))
		var dj := absf(float(k / n - sj))
		var octile := maxf(di, dj) + 0.41421 * minf(di, dj)
		var straight := sqrt(di * di + dj * dj) / octile if octile > 0.0 else 1.0
		var rel := _dist[k] * straight / (reach[k] * scale)
		rel_s[k] = minf(rel, FAR)
		# past its own outline the arrival keeps rising (steeply), so the edge
		# is a smooth line between samples, not the grid's steps, and a later
		# source pushing progress on hardly moves this one's edge
		if rel < 1.6:
			var v := float(s.shift) + (rel if rel < 1.0 else 1.0 + (rel - 1.0) * 8.0)
			if v < _v[k]:
				_v[k] = v
			_pot[k] = maxf(_pot[k], 1.0 - rel)


func _end_solve() -> void:
	var new_end := 0.0
	for s: Dictionary in sources:
		new_end = maxf(new_end, float(s.shift) + 1.0)
	wet_cells = 0
	for k in n * n:
		if _v[k] < new_end:
			wet_cells += 1
	if _built_once:
		_restart()                      # fed: grow on from here to the new end
	p_end = new_end
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var sh := [NEVER, NEVER, NEVER, NEVER]
	for i in sources.size():
		sh[i] = float(sources[i].shift)
	set_instance_shader_parameter("shifts", Vector4(sh[0], sh[1], sh[2], sh[3]))
	_row = 0
	_tris = 0
	_risers = 0
	stage = Stage.BUILD


# --- the mesh -----------------------------------------------------------------------
func _build_row(space: PhysicsDirectSpaceState3D) -> void:
	if _row < n - 1:
		var j := _row
		riser_quads = _risers
		for i in n - 1:
			var cs: Array[int] = [j * n + i, j * n + i + 1, (j + 1) * n + i + 1, (j + 1) * n + i]
			var any := false
			for c in cs:
				if _cls[c] == 0 and _v[c] < p_end + 1.6:
					any = true
			if not any:
				continue
			_tris += _cell(_st, space, i, j, cs)
		_risers = riser_quads
		_row += 1
		return
	riser_quads = _risers
	mesh = _st.commit() if _tris > 0 else null
	_st = null
	_built_once = true
	stage = Stage.DONE


## One grid cell. Corners on the same surface: one quad. Otherwise the cell
## is split where the surface changes, each part on its own surface, and a
## riser strip between two floor levels.
func _cell(st: SurfaceTool, space: PhysicsDirectSpaceState3D, i: int, j: int, cs: Array[int]) -> int:
	# which surface each corner is on: group floor corners by height
	var grp: Array[int] = [-1, -1, -1, -1]
	var levels: Array[float] = []
	for k in 4:
		var c := cs[k]
		if _cls[c] != 0:
			continue
		var found := -1
		for g in levels.size():
			if absf(_h[c] - levels[g]) <= CLIMB * 1.6:
				found = g
		if found < 0:
			levels.append(_h[c])
			found = levels.size() - 1
		grp[k] = found
	if levels.is_empty():
		return 0
	var all_same := true
	for k in 4:
		if grp[k] != 0:
			all_same = false
	if all_same:
		_vert(st, cs[0], Vector3.ZERO, false)
		_vert(st, cs[1], Vector3.ZERO, false)
		_vert(st, cs[2], Vector3.ZERO, false)
		_vert(st, cs[0], Vector3.ZERO, false)
		_vert(st, cs[2], Vector3.ZERO, false)
		_vert(st, cs[3], Vector3.ZERO, false)
		return 2
	# walk the cell's edge: corners, and a crossing wherever the surface changes
	var ring: Array = []                 # [point, group, v, pot, normal]
	var crossings: Array = []            # floor-to-floor crossings: [upper point, lower point, v_up, v_low, pot]
	for k in 4:
		var a := cs[k]
		var b := cs[(k + 1) % 4]
		if grp[k] >= 0:
			ring.append([_pos(a), grp[k], _v[a], _pot[a], _nrm[a], a])
		if grp[k] == grp[(k + 1) % 4]:
			continue
		var x := _crossing(space, a, b)
		if x.is_empty():
			continue
		if grp[k] >= 0:
			ring.append([x.pa, grp[k], _v[a], _pot[a], _nrm[a], a])
		if grp[(k + 1) % 4] >= 0:
			ring.append([x.pb, grp[(k + 1) % 4], _v[b], _pot[b], _nrm[b], b])
		if grp[k] >= 0 and grp[(k + 1) % 4] >= 0:
			var a_up := _h[a] > _h[b]
			crossings.append([x.pa if a_up else x.pb, x.pb if a_up else x.pa, _v[a] if a_up else _v[b], _v[b] if a_up else _v[a], _pot[a] if a_up else _pot[b], a if a_up else b, b if a_up else a])
	var count := 0
	for g in levels.size():
		var poly: Array = []
		for p: Array in ring:
			if p[1] == g:
				poly.append(p)
		if poly.size() < 3:
			continue
		for t in range(1, poly.size() - 1):
			_vtx(st, poly[0])
			_vtx(st, poly[t])
			_vtx(st, poly[t + 1])
			count += 1
	# a strip down the face of the step, where the blood runs over the edge
	if crossings.size() == 2 and cfg.stair_flow:
		var c0: Array = crossings[0]
		var c1: Array = crossings[1]
		var face: Vector3 = (c0[1] as Vector3) - (c0[0] as Vector3)
		var out := Vector3(face.x, 0, face.z)
		var along := (c1[0] as Vector3) - (c0[0] as Vector3)
		var nrm := Vector3.UP.cross(along).normalized()
		if out.length() > 0.0005 and nrm.dot(out) < 0.0:
			nrm = -nrm
		# it only runs down from above, never up from below
		var top0: float = c0[2]
		var top1: float = c1[2]
		# and only where it really ran over: the tread below was reached
		# from here (a short drop), not a ledge it can never run down
		var bot0: float = float(c0[3]) if float(c0[3]) < p_end and float(c0[3]) >= top0 else NEVER
		var bot1: float = float(c1[3]) if float(c1[3]) < p_end and float(c1[3]) >= top1 else NEVER
		var drop_h := (c0[0] as Vector3).y - (c0[1] as Vector3).y
		if (bot0 < NEVER or bot1 < NEVER) and drop_h <= MAX_DROP + 0.01:
			var up0: Vector3 = c0[0]
			var up1: Vector3 = c1[0]
			var lo0 := Vector3(up0.x, (c0[1] as Vector3).y, up0.z)
			var lo1 := Vector3(up1.x, (c1[1] as Vector3).y, up1.z)
			var pot: float = minf(float(c0[4]), float(c1[4])) * 0.6
			var quad := [[up0, -1, top0, pot, nrm, c0[5]], [up1, -1, top1, pot, nrm, c1[5]],
				[lo1, -1, bot1, pot, nrm, c1[6] if bot1 < NEVER else -1], [lo0, -1, bot0, pot, nrm, c0[6] if bot0 < NEVER else -1]]
			for t: Array in [[0, 1, 2], [0, 2, 3]]:
				for q: int in t:
					_vtx(st, quad[q], true)
			riser_quads += 1
			count += 2
	return count


## Where the surface changes between two neighbouring samples: a wall (from a
## floor sample, a sideways ray finds the wall face), or a step edge (found by
## halving the gap with downward rays). Cached, so each edge is solved once.
func _crossing(space: PhysicsDirectSpaceState3D, a: int, b: int) -> Dictionary:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if _cross.has(key):
		var x: Dictionary = _cross[key]
		if x.is_empty() or a < b:
			return x
		return {pa = x.pb, pb = x.pa}
	# solved once, from the lower index to the higher, and handed back the
	# right way round for the caller
	if a > b:
		var flip := _crossing(space, b, a)
		return {pa = flip.pb, pb = flip.pa} if not flip.is_empty() else flip
	var pa := _pos(a)
	var pb := _pos(b)
	var out := {}
	if _cls[a] == 0 and _cls[b] == 0:
		# a step: halve the gap three times
		var lo := 0.0
		var hi := 1.0
		var ha := _h[a]
		for it in 3:
			var mid := (lo + hi) * 0.5
			var mp := pa.lerp(pb, mid)
			var q := PhysicsRayQueryParameters3D.create(Vector3(mp.x, centre.y + SAMPLE_UP, mp.z), Vector3(mp.x, centre.y - SAMPLE_DOWN, mp.z), SURFACES)
			q.hit_from_inside = true
			var hit := space.intersect_ray(q)
			rays_used += 1
			var hm: float = (hit.position as Vector3).y if not hit.is_empty() and (hit.normal as Vector3) != Vector3.ZERO else NAN
			if not is_nan(hm) and absf(hm - ha) <= CLIMB * 1.6:
				lo = mid
			else:
				hi = mid
		var t := (lo + hi) * 0.5
		var cp := pa.lerp(pb, t)
		out = {pa = Vector3(cp.x, _h[a], cp.z), pb = Vector3(cp.x, _h[b], cp.z)}
	else:
		var valid := a if _cls[a] == 0 else b
		var other := b if valid == a else a
		var pv := _pos(valid)
		var po := _pos(other)
		var cp := pv.lerp(po, 0.5)
		if _cls[other] == -2:
			var q := PhysicsRayQueryParameters3D.create(pv + Vector3.UP * 0.03, Vector3(po.x, pv.y + 0.03, po.z), 1)
			var hit := space.intersect_ray(q)
			rays_used += 1
			if not hit.is_empty():
				var hp: Vector3 = hit.position
				cp = Vector3(hp.x, pv.y, hp.z) + (pv - po).normalized() * 0.004
		cp.y = pv.y
		out = {pa = cp, pb = cp}
	_cross[key] = out
	return out


func _pos(k: int) -> Vector3:
	var p := _grid_pos(k % n, k / n)
	p.y = _h[k] if _cls[k] == 0 else centre.y
	return p


func _vert(st: SurfaceTool, k: int, _off: Vector3, _riser: bool) -> void:
	_vtx(st, [_pos(k), 0, _v[k], _pot[k], _nrm[k], k])


func _vtx(st: SurfaceTool, p: Array, riser := false) -> void:
	var nrm: Vector3 = p[4]
	if nrm == Vector3.ZERO:
		nrm = Vector3.UP
	var wp: Vector3 = p[0]
	st.set_normal(nrm)
	st.set_uv(Vector2(wp.x, wp.z))
	st.set_uv2(Vector2(minf(float(p[2]), NEVER), float(p[3])))
	st.set_color(Color(1, 1, 1, 1.0 if riser else 0.0))
	var k: int = p[5] if p.size() > 5 else -1
	if k >= 0 and _rel.size() == 4:
		st.set_custom(0, Color(_rel[0][k], _rel[1][k], _rel[2][k], _rel[3][k]))
	else:
		st.set_custom(0, Color(FAR, FAR, FAR, FAR))
	st.add_vertex(to_local(wp + nrm * LIFT))


# --- growing ---------------------------------------------------------------------------
## Grow toward p_end: fast, then slower, then settled. Returns true once it is.
func advance(delta: float) -> bool:
	if settled or not sampling_done():
		return settled
	_t += delta
	var total := expand + settle
	var u := clampf(_t / total, 0.0, 1.0)
	# most of it inside the expansion time, the last few percent creeping on through the settle
	var k := expand / total
	var e := 1.0 - pow(1.0 - u, 2.6 + 1.5 * (1.0 - k))
	progress = lerpf(_p_from, p_end, e)
	set_instance_shader_parameter("progress", progress)
	if u >= 1.0:
		settled = true
	return settled


## Smooth 1-D value noise along an edge (where blood runs over most easily).
static func _lane(x: float, seed_: float) -> float:
	var t := x * 3.2 + seed_ * 7.1
	var i := floorf(t)
	var f := t - i
	f = f * f * (3.0 - 2.0 * f)
	var a := fposmod(sin(i * 127.1 + seed_ * 3.7) * 43758.5453, 1.0)
	var b := fposmod(sin((i + 1.0) * 127.1 + seed_ * 3.7) * 43758.5453, 1.0)
	return lerpf(a, b, f)


## A min-heap of [priority, index].
class _Heap:
	var p := PackedFloat32Array()
	var v := PackedInt32Array()

	func empty() -> bool:
		return p.is_empty()

	func push(pri: float, val: int) -> void:
		p.append(pri)
		v.append(val)
		var i := p.size() - 1
		while i > 0:
			var par := (i - 1) / 2
			if p[par] <= p[i]:
				break
			var tp := p[par]
			p[par] = p[i]
			p[i] = tp
			var tv := v[par]
			v[par] = v[i]
			v[i] = tv
			i = par

	func pop() -> Array:
		var out := [p[0], v[0]]
		var last := p.size() - 1
		p[0] = p[last]
		v[0] = v[last]
		p.resize(last)
		v.resize(last)
		var i := 0
		var size := p.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < size and p[l] < p[m]:
				m = l
			if r < size and p[r] < p[m]:
				m = r
			if m == i:
				break
			var tp := p[m]
			p[m] = p[i]
			p[i] = tp
			var tv := v[m]
			v[m] = v[i]
			v[i] = tv
			i = m
		return out
