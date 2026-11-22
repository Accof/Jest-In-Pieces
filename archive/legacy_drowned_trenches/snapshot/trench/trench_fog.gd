class_name TrenchFog
extends Node3D
## The weather of the mist on a trench floor (TrenchBattle makes it):
##
##  - Fog banks: now and then a dense white cloud rolls in off No Man's Land
##    on the wind, like smoke, crosses the lines and is gone. It hugs the
##    ground and pours down into the trenches as it crosses them (heavier
##    than the air). Drawn twice: as billowing puffs that follow the ground
##    down into the trenches (every renderer), and as density in the
##    ground mist's volume (Forward+), so being inside one is like being in
##    a cloud.
##  - Heaviness: the whole mist thickens and thins over minutes (thicker in
##    the battle's lulls, now and then a long heavy spell).
##
## Fair both ways: `visibility(a, b)` says how much of a sight line gets
## through the banks; the soldiers' eyes (ClownBrain) and the marksman use
## it, so a bank that hides them from the player hides the player from them.

const MAX_BANKS := 3
const PUFFS := 46

class Bank:
	var pos := Vector3.ZERO        ## the middle, on the ground
	var vel := Vector3.ZERO
	var radius := 18.0
	var height := 4.5              ## how high the cloud stands over the ground
	var density := 0.0             ## now (it swells in and thins out)
	var peak := 0.55
	var age := 0.0
	var seed_ := 0.0
	var mm: MultiMeshInstance3D
	var puffs: Array = []          ## [offset (xz, in radii), size, spin, y now, phase, where drawn]

var maze: TrenchMaze
var art: TrenchArt
var battle: TrenchBattle
var mist_mat: ShaderMaterial
var rng := RandomNumberGenerator.new()
var banks: Array[Bank] = []
## How thick the whole mist is now (×), and what it is heading for.
var heaviness := 1.0
var _heavy_want := 1.0
var _t_heavy := 50.0
var _t_bank := 25.0
var _puff_mat: StandardMaterial3D
var _quad: QuadMesh

# counters (tests)
var banks_made := 0
var heavy_spells := 0


func setup(m: TrenchMaze, a: TrenchArt, b: TrenchBattle, seed_: int) -> void:
	maze = m
	art = a
	battle = b
	rng.seed = seed_
	add_to_group(&"fog")
	if art.mist:
		mist_mat = art.mist.material as ShaderMaterial
	_puff_mat = StandardMaterial3D.new()
	_puff_mat.albedo_texture = load("res://art/level/fx_billow.png")
	_puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_puff_mat.billboard_keep_scale = true
	_puff_mat.vertex_color_use_as_albedo = true
	_puff_mat.disable_receive_shadows = true
	_puff_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puff_mat.proximity_fade_enabled = true        # soft where it meets the ground and the walls
	_puff_mat.proximity_fade_distance = 1.6
	_puff_mat.roughness = 1.0
	_puff_mat.albedo_color = Color(0.86, 0.87, 0.88)
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_t_bank = rng.randf_range(20.0, 45.0)
	_t_heavy = rng.randf_range(40.0, 90.0)


## A bank rolling in now (the director's, and the tests').
func roll_in(from_side := -1) -> Bank:
	if banks.size() >= MAX_BANKS:
		return null
	var w := maze.w * maze.cell
	var d := maze.d * maze.cell
	var b := Bank.new()
	b.radius = rng.randf_range(15.0, 24.0)
	b.height = rng.randf_range(3.5, 6.0)
	b.peak = rng.randf_range(0.45, 0.75)
	b.seed_ = rng.randf() * 100.0
	# off No Man's Land on the wind, mostly toward the lines, a little across
	var side := from_side if from_side >= 0 else rng.randi() % 3
	match side:
		0:   # straight in over the wire
			b.pos = Vector3(rng.randf_range(0.0, w), 0, -48.0 - b.radius)
			b.vel = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(1.0, 1.6))
		1:   # from the left, slanting in
			b.pos = Vector3(-b.radius - 8.0, 0, rng.randf_range(-30.0, d * 0.4))
			b.vel = Vector3(rng.randf_range(1.0, 1.5), 0, rng.randf_range(0.4, 0.9))
		_:   # from the right
			b.pos = Vector3(w + b.radius + 8.0, 0, rng.randf_range(-30.0, d * 0.4))
			b.vel = Vector3(-rng.randf_range(1.0, 1.5), 0, rng.randf_range(0.4, 0.9))
	b.pos.y = 0.0
	# its puffs
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = PUFFS
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _puff_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 50, 120))
	add_child(mi)
	b.mm = mi
	for i in PUFFS:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.95
		b.puffs.append([Vector2(cos(a), sin(a)) * r, rng.randf_range(5.0, 10.0), rng.randf_range(-0.25, 0.25), INF, rng.randf() * TAU, Vector3.ZERO])
	banks.append(b)
	banks_made += 1
	return b


func _process(delta: float) -> void:
	if maze == null:
		return
	var calm := battle.calm if battle else 1.0
	# heaviness: thicker in the lulls, and now and then a long heavy spell
	_t_heavy -= delta
	if _t_heavy <= 0.0:
		if _heavy_want > 1.2:
			_heavy_want = 1.0
			_t_heavy = rng.randf_range(80.0, 180.0)
		else:
			_heavy_want = rng.randf_range(1.8, 2.6)
			_t_heavy = rng.randf_range(40.0, 90.0)
			heavy_spells += 1
	var want := _heavy_want * (1.0 + clampf(calm - 1.0, 0.0, 1.6) * 0.35)
	heaviness = move_toward(heaviness, want, delta * 0.02)
	# banks: more often in the lulls
	_t_bank -= delta
	if _t_bank <= 0.0:
		_t_bank = rng.randf_range(70.0, 150.0) / clampf(calm, 0.6, 2.0)
		roll_in()
	var w := maze.w * maze.cell
	var d := maze.d * maze.cell
	for b in banks.duplicate():
		b.age += delta
		b.pos += b.vel * delta
		# swells in over half a minute; thins once it is past the lines
		var gone: bool = b.pos.z > d + b.radius or b.pos.x < -b.radius - 30.0 or b.pos.x > w + b.radius + 30.0
		var fade_in := clampf(b.age / 30.0, 0.0, 1.0)
		b.density = move_toward(b.density, 0.0 if gone else b.peak * fade_in, delta * 0.03)
		if gone and b.density <= 0.001:
			b.mm.queue_free()
			banks.erase(b)
			continue
		_draw_bank(b, delta)
	_upload()


## The puffs: each rides along with the bank at its place in it, at its own
## height over whatever ground is under it. Crossing a trench, it pours down
## in (quickly) and climbs out the far side (slowly), so the cloud seems to
## sink into the trenches and well out of them.
func _draw_bank(b: Bank, delta: float) -> void:
	var mm := b.mm.multimesh
	var t := Time.get_ticks_msec() * 0.001
	for i in b.puffs.size():
		var p: Array = b.puffs[i]
		var off: Vector2 = p[0]
		var swirl := Vector2(sin(t * 0.07 + p[4]), cos(t * 0.05 + p[4] * 1.3)) * 0.06
		var at := b.pos + Vector3((off.x + swirl.x) * b.radius, 0, (off.y + swirl.y) * b.radius)
		var g := maze.floor_height(at) if _inside(at) else art.height_at(at.x, at.z)
		var size: float = p[1] * (0.8 + 0.2 * b.radius / 20.0)
		var y_want := g + size * 0.28
		var y: float = p[3]
		if y == INF:
			y = y_want
		y = move_toward(y, y_want, delta * (2.4 if y_want < y else 0.6))
		p[3] = y
		p[5] = Vector3(at.x, y, at.z)
		var edge := 1.0 - smoothstep(0.55, 1.0, off.length())
		var a := clampf(b.density / 0.6, 0.0, 1.0) * (0.25 + 0.5 * edge) * heaviness_alpha()
		var basis := Basis(Vector3.BACK, p[2] * t + p[4]).scaled(Vector3.ONE * size)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(at.x, y, at.z)))
		mm.set_instance_color(i, Color(1, 1, 1, a))


func heaviness_alpha() -> float:
	return clampf(0.8 + (heaviness - 1.0) * 0.15, 0.8, 1.1)


func _inside(at: Vector3) -> bool:
	var lo := maze.origin
	return at.x > lo.x + 0.5 and at.z > lo.y + 0.5 and at.x < lo.x + (maze.hx - 2) * TrenchMaze.RES and at.z < lo.y + (maze.hz - 2) * TrenchMaze.RES


func _upload() -> void:
	if mist_mat == null:
		return
	mist_mat.set_shader_parameter("density_scale", heaviness)
	var a := PackedVector4Array()
	var bb := PackedVector4Array()
	a.resize(MAX_BANKS)
	bb.resize(MAX_BANKS)
	for i in MAX_BANKS:
		if i < banks.size():
			var b := banks[i]
			a[i] = Vector4(b.pos.x, b.pos.y, b.pos.z, b.radius)
			bb[i] = Vector4(b.height, b.density, b.seed_, 0.0)
		else:
			a[i] = Vector4(0, -1000, 0, 0.0)
			bb[i] = Vector4.ZERO
	mist_mat.set_shader_parameter("bank_count", banks.size())
	mist_mat.set_shader_parameter("bank_a", a)
	mist_mat.set_shader_parameter("bank_b", bb)


## How thick the banks are at `p` (the same shape as the shader's, without
## the billows): 0 clear .. about 0.75 in the heart of a thick one.
func density_at(p: Vector3) -> float:
	var total := 0.0
	for b in banks:
		var dxz := Vector2(p.x - b.pos.x, p.z - b.pos.z).length() / b.radius
		if dxz >= 1.0:
			continue
		var core := 1.0 - smoothstep(0.35, 1.0, dxz)
		var g := maze.floor_height(p) if _inside(p) else art.height_at(p.x, p.z)
		var top := maxf(g, 0.0) + b.height
		var v := 1.0 - smoothstep(top - b.height * 0.5, top, p.y)
		total += b.density * core * v
	return total


## How much of a sight line from `a` to `b` gets through the banks (1 clear,
## 0 nothing): Beer-Lambert along it, sampled every couple of metres.
func visibility(a: Vector3, b: Vector3) -> float:
	if banks.is_empty():
		return 1.0
	var d := a.distance_to(b)
	var n := clampi(int(d / 2.0), 2, 24)
	var tau := 0.0
	for i in n:
		tau += density_at(a.lerp(b, (i + 0.5) / n)) * (d / n)
	return exp(-tau * 0.22)
