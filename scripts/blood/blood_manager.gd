extends Node
## Autoload "Blood": splatter decals, flying droplets, mist and growing pools.
## Everything is pooled and capped so a long fight cannot tank the frame rate.
##
## Every call takes an `oil` flag (last argument, default false). The
## Klappersoldat bleeds machine oil instead: near-black splats, dark spray,
## and oil puddles, which (unlike blood pools) are never recycled: they stay
## until the floor is cleared.

const LAYER_WORLD := 1
## (Phase D, 24 Nov) 320 was a ring with no fade, and Phase B spends 15-30 a
## hit: a shotgun fight wrapped it in a few shots and the first kill's marks
## popped out one by one. Now 1,200, and a slot is only taken from the small
## and the far marks first (the big splat you are looking at goes last); a
## mark that is taken is handed to a spare decal that fades over FADE_OUT so
## nothing pops. The renderer's per-view budget is 1,024 clustered elements
## (decals in the frustum plus lights): the 30 m distance fade keeps a fight's
## marks under it.
const MAX_DECALS := 1200
const SPARE_DECALS := 48
const FADE_OUT := 2.5
const RECYCLE_LOOK := 40           # slots inspected when the ring is full
const MAX_DROPLETS := 160
const MAX_POOLS := 28
const POOL_QUAD_RADIUS := 1.2          # metres; the largest pool that can form (kept for callers)
const DRY_TIME := 50.0                 # seconds for fresh blood to darken
const FRESH := Color(1, 1, 1, 1)
const DRIED := Color(0.55, 0.42, 0.40, 1)

var _tex := {}                          # kind -> Array of [albedo, normal, orm]
var _tex_oil := {}                      # the same, in oil
var _orm: Texture2D                     # the old set's single wet-look ORM
var _tint := PackedColorArray()         # each decal's own colour variation (drying lerps from it)
## The splatter library (tools/gen_blood_splatters.py, art/blood/splat/): 26
## variants in six kinds, each with its own colour, normal and roughness (ORM)
## maps. The first set (tools/gen_blood_textures.py: 10 variants, one shared
## glossy ORM) is kept and comes back with this switch.
@export var use_legacy_splatters := false
const SPLAT_KINDS := {spray = 6, impact = 5, small = 4, streak = 4, drip = 3, death = 4}
## (24 Nov, the blood overhaul's Phase A) The v2 library (tools/gen_blood_splatters_v2.py,
## art/blood/splat2/): built against Andrew's reference photographs - a gunshot's
## mist of thousands of specks, impacts with fingers and drips, cast-off arcs,
## drip fields, heavy masses, dragged streaks, single droplets. 1024 colour,
## 512 normal/ORM. `splat_version = 1` brings the old set back. The old kind
## names callers use map onto it (SPLAT2_MAP); castoff and dripfield wait for
## Phase B's placement. `SPLAT2_FILL` is how much of the texture's height each
## kind's shape fills, so a size asked for in metres is the shape's size.
const SPLAT2_KINDS := {mist = 6, impact = 6, castoff = 4, dripfield = 4, heavy = 4, streak = 4, small = 8}
const SPLAT2_MAP := {spray = "mist", drip = "small", death = "heavy", impact = "impact", streak = "streak", small = "small", mist = "mist", castoff = "castoff", dripfield = "dripfield", heavy = "heavy"}
const SPLAT2_FILL := {mist = 0.62, impact = 0.5, castoff = 0.75, dripfield = 0.8, heavy = 0.7, streak = 0.6, small = 0.55}
static var splat_version := 2
static var flat_decals := OS.get_environment("BLOOD_FLAT") == "1"   # dev: albedo only, to judge the normal/ORM maps' part
var _decals: Array[Decal] = []
var _born := PackedFloat32Array()
var _next := 0
var _spares: Array[Decal] = []       # (Phase D) decals that carry a recycled mark while it fades
var _fading: Array = []              # [[Decal, t]]
var recycled := 0                    # for the tests
var _dry_cursor := 0

var _drop_pos := PackedVector3Array()
var _drop_vel := PackedVector3Array()
var _drop_size := PackedFloat32Array()
var _drop_life := PackedFloat32Array()
var _drop_oil := PackedByteArray()
var _decal_oil := PackedByteArray()

## Pools: geometry-aware (BloodPool, scripts/blood/blood_pool.gd). Each
## samples the floor round it once, works out where the blood can go, and is
## drawn on a mesh that lies on the real surfaces; growth runs in the shader.
@export_group("Blood pools")
@export var enable_organic_pool_shapes := true
@export var enable_geometry_aware_spreading := true
@export var enable_stair_flow := true
@export var enable_slope_bias := true
@export var enable_pool_merging := true
@export var enable_wet_reflections := true
@export var pool_expansion_duration := Vector2(3.0, 8.0)     ## seconds, by how much blood
@export var pool_settling_duration := Vector2(1.0, 3.0)
@export var shape_variation := 1.0                            ## 0: round pools
@export var edge_irregularity := 1.0
@export var maximum_pool_radius := 0.6                        ## metres
@export var pool_size := 0.7                                  ## every blood pool's radius is scaled by this (oil is not)
@export var maximum_active_spreading_pools := 8               ## beyond this the oldest spreading one settles at once
@export var surface_sampling_quality := 1                     ## 0 low, 1 medium, 2 high (grid spacing 0.12 / 0.085 / 0.065 m)
@export var maximum_stair_flow_steps := 3                     ## how many step edges blood will run down
@export var pool_work_ms := 2.5                               ## time a frame may spend setting up new pools (rays, flood, mesh)
@export var pool_slope_bias := 0.6
var _pools: Array[BloodPool] = []
var _sampling: Array[BloodPool] = []   # waiting for (or part way through) their rays
var _pool_material: ShaderMaterial
var _mist: Array[GPUParticles3D] = []
var _mist_oil: Array[GPUParticles3D] = []
var _oil_material: ShaderMaterial
## Oil puddles: permanent until clear() (a new floor).
var _oil_pools: Array[BloodPool] = []
var _mist_next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_splatters()
	for i in MAX_DECALS:
		var d := Decal.new()
		d.visible = false
		d.texture_orm = _orm
		d.normal_fade = 0.35
		d.upper_fade = 0.25
		d.lower_fade = 0.25
		d.cull_mask = 1                 # world only: never projected onto bodies
		d.distance_fade_enabled = true
		d.distance_fade_begin = 30.0
		d.distance_fade_length = 10.0
		add_child(d)
		_decals.append(d)
	_born.resize(MAX_DECALS)
	_tint.resize(MAX_DECALS)
	_decal_oil.resize(MAX_DECALS)
	for i in SPARE_DECALS:
		var d := Decal.new()
		d.visible = false
		d.normal_fade = 0.35
		d.upper_fade = 0.25
		d.lower_fade = 0.25
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 30.0
		d.distance_fade_length = 10.0
		add_child(d)
		_spares.append(d)
	_pool_material = ShaderMaterial.new()
	_pool_material.shader = load("res://shaders/blood_pool.gdshader")
	_pool_material.set_shader_parameter("noise_tex", load("res://art/blood/pool_noise.png"))
	_oil_material = _pool_material.duplicate()
	_oil_material.set_shader_parameter("thin_color", Color(0.055, 0.048, 0.036))
	_oil_material.set_shader_parameter("deep_color", Color(0.011, 0.010, 0.008))
	_oil_material.set_shader_parameter("dry_color", Color(0.03, 0.028, 0.022))
	_oil_material.set_shader_parameter("brown_color", Color(0.05, 0.045, 0.035))
	_oil_material.set_shader_parameter("sheen", 1.0)
	_apply_pool_settings()
	_mist = _build_mist(Color(0.2, 0.01, 0.012, 0.9))
	_mist_oil = _build_mist(Color(0.03, 0.027, 0.02, 0.92))


## Load the splatter library (or, with use_legacy_splatters, the first set).
func _load_splatters() -> void:
	_tex = {}
	_tex_oil = {}
	_orm = load("res://art/blood/splat_orm.png")
	if use_legacy_splatters:
		for spec in [["impact", 3], ["spray", 3], ["drip", 2], ["streak", 2]]:
			var list := []
			for i in spec[1]:
				var base := "res://art/blood/splat_%s_%d" % [spec[0], i]
				list.append([load(base + ".png"), load(base + "_n.png"), _orm])
			_tex[spec[0]] = list
			var oil := []
			for i in spec[1]:
				oil.append([load("res://art/oil/splat_%s_%d.png" % [spec[0], i]), list[i][1], _orm])
			_tex_oil[spec[0]] = oil
		_tex["small"] = _tex["spray"]; _tex_oil["small"] = _tex_oil["spray"]
		_tex["death"] = _tex["impact"]; _tex_oil["death"] = _tex_oil["impact"]
	elif splat_version == 2:
		# oil has no textures of its own in v2: the same shapes, modulated near-black
		for kind: String in SPLAT2_KINDS:
			var list := []
			for i in int(SPLAT2_KINDS[kind]):
				var base := "res://art/blood/splat2/splat_%s_%d" % [kind, i]
				list.append([load(base + ".png"), load(base + "_n.png"), load(base + "_orm.png")])
			_tex[kind] = list
			_tex_oil[kind] = list
	else:
		for kind: String in SPLAT_KINDS:
			var list := []
			var oil := []
			for i in int(SPLAT_KINDS[kind]):
				var base := "res://art/blood/splat/splat_%s_%d" % [kind, i]
				var n: Texture2D = load(base + "_n.png")
				var o: Texture2D = load(base + "_orm.png")
				list.append([load(base + ".png"), n, o])
				oil.append([load("res://art/oil/splat/splat_%s_%d.png" % [kind, i]), n, o])
			_tex[kind] = list
			_tex_oil[kind] = oil


func clear() -> void:
	for d in _decals:
		d.visible = false
	for e: Array in _fading:
		(e[0] as Decal).visible = false
		_spares.append(e[0])
	_fading.clear()
	for p in _pools:
		if is_instance_valid(p):
			p.queue_free()
	_pools.clear()
	for p in _oil_pools:
		if is_instance_valid(p):
			p.queue_free()
	_oil_pools.clear()
	_sampling.clear()
	_drop_pos.clear(); _drop_vel.clear(); _drop_size.clear(); _drop_life.clear(); _drop_oil.clear()


# --- splatter -----------------------------------------------------------------
## A bullet passing through flesh at `pos` travelling along `dir`.
## `amount` 0..2 scales how much blood comes out. `zone` ("head", "" …) and
## `weapon` let the v2 placement pick the regime (Phase B).
func spawn_hit(pos: Vector3, dir: Vector3, amount: float = 1.0, oil := false, zone := "", weapon := "", shot_id := -1) -> void:
	dir = dir.normalized()
	_burst(pos, dir, amount, oil)
	if splat_version == 2 and not use_legacy_splatters:
		_place_gunshot(pos, dir, amount, oil, zone, weapon, shot_id)
		for i in 3 + int(amount * 7.0):
			var v := dir * _rng.randf_range(0.8, 4.2) + Vector3.UP * _rng.randf_range(0.3, 2.6) + _rand_unit() * 1.3
			add_droplet(pos, v, _rng.randf_range(0.05, 0.13), oil)
		return
	# Exit spray onto whatever is behind the target.
	var rays := 2 + int(amount * 4.0)
	for i in rays:
		var d := (dir + _rand_unit() * 0.42).normalized()
		var hit := _ray(pos + d * 0.05, pos + d * (2.4 + 2.2 * amount))
		if hit.is_empty():
			continue
		var dist: float = pos.distance_to(hit.position)
		var size := _rng.randf_range(0.2, 0.5) * (0.55 + 0.6 * amount) * clampf(1.25 - dist * 0.16, 0.45, 1.0)
		_splat_on(hit.position, hit.normal, d, size, oil)
	# A little back spatter toward the shooter.
	for i in 1 + int(amount):
		var d := (-dir + _rand_unit() * 0.7).normalized()
		var hit := _ray(pos + d * 0.05, pos + d * 1.6)
		if not hit.is_empty():
			spawn_decal(hit.position, hit.normal, _rng.randf_range(0.08, 0.2), "drip", Vector3.ZERO, 1.0, 1.0, oil)
	# Heavy drops that arc away and land on the floor.
	for i in 3 + int(amount * 7.0):
		var v := dir * _rng.randf_range(0.8, 4.2) + Vector3.UP * _rng.randf_range(0.3, 2.6) + _rand_unit() * 1.3
		add_droplet(pos, v, _rng.randf_range(0.05, 0.13), oil)


# --- Phase B: placement by physics (24 Nov) ----------------------------------------------
## How much the one big exit mark grows with the distance the blood flew: the
## fan widens. `GUN_MIST_BASE` + amount + distance × `GUN_MIST_PER_M`, in metres.
const GUN_MIST_BASE := 0.42
const GUN_MIST_PER_M := 0.2
const GUN_MIST_MAX := 1.7
var _last_shot := -1               # a shotgun's pellets share one big mark


## A gunshot's forward spatter: the cone's centre ray finds the surface behind
## the man; ONE mist decal lands there, sized by the distance flown and the
## hit's amount, stretched along the travel's projection (a shallow angle
## draws the fan out), the fan's wide end away from the shooter. Close or hard
## hits put an impact on top (the mass); a headshot a heavy with its drips.
## A handful of small drops are re-raycast round it, a little back spatter
## toward the shooter, a few drops on the floor beneath. A shotgun's pellets
## share the one big mark (the first pellet of a shot places it).
func _place_gunshot(pos: Vector3, dir: Vector3, amount: float, oil: bool, zone: String, weapon: String, shot_id: int) -> void:
	var pellet := shot_id >= 0 and shot_id == _last_shot
	if shot_id >= 0:
		_last_shot = shot_id
	var head := zone == "head"
	var d := (dir + _rand_unit() * 0.05).normalized()
	var reach := 2.6 + 3.0 * amount
	var hit := _ray(pos + d * 0.05, pos + d * reach)
	if not hit.is_empty() and not pellet:
		var n: Vector3 = (hit.normal as Vector3).normalized()
		var dist: float = pos.distance_to(hit.position)
		var facing: float = absf(d.dot(n))
		var along: Vector3 = d - n * d.dot(n)
		var size := clampf(GUN_MIST_BASE + 0.35 * amount + dist * GUN_MIST_PER_M, 0.45, GUN_MIST_MAX)
		if head:
			size *= 1.25
		var shotgun := weapon.containsn("shotgun")
		if shotgun:
			size = minf(size * 1.6, GUN_MIST_MAX)          # the whole charge's fan, placed by its first pellet
			amount = maxf(amount, 1.2)
		var stretch := 1.0 + (1.0 - facing) * 1.6
		if facing < 0.45 and along.length() > 0.05:
			# a graze along the surface: a dragged streak, and the mist beyond it
			spawn_decal(hit.position, n, size * 0.6, "streak", along, 1.0, 1.0 + (1.0 - facing) * 1.2, oil)
		spawn_decal(hit.position, n, size, "mist", along if along.length() > 0.08 else Vector3.ZERO, 1.0 / sqrt(stretch), sqrt(stretch), oil)
		# the mass: close or hard, an impact on the mist; a headshot, a heavy that drips
		if head and amount >= 0.8 and dist < 2.6:
			spawn_decal(hit.position + along.normalized() * 0.04, n, clampf(0.5 + 0.3 * amount, 0.5, 0.95), "heavy", Vector3.ZERO, 1.0, 1.0, oil)
		elif (dist < 1.3 and amount >= 0.8) or amount >= 1.3:
			spawn_decal(hit.position, n, clampf(0.28 + 0.3 * amount, 0.3, 0.7), "impact", Vector3.ZERO, 1.0, 1.0, oil)
		# small drops re-raycast round the mark, inside the fan
		for i in 4 + int(amount * 5.0):
			var dd := (d + _rand_unit() * 0.32).normalized()
			var h2 := _ray(pos + dd * 0.05, pos + dd * (reach * 0.9))
			if not h2.is_empty():
				var sl: Vector3 = dd - h2.normal * dd.dot(h2.normal)
				spawn_decal(h2.position, h2.normal, _rng.randf_range(0.03, 0.09) * (1.0 + 0.4 * amount), "small", sl, 1.0, 1.0 + sl.length() * 1.5, oil)
	elif not hit.is_empty() and pellet:
		# one more pellet of the same shot: a drop or two in the fan, no second mark
		for i in 2:
			var dd := (d + _rand_unit() * 0.3).normalized()
			var h2 := _ray(pos + dd * 0.05, pos + dd * reach)
			if not h2.is_empty():
				spawn_decal(h2.position, h2.normal, _rng.randf_range(0.03, 0.08), "small", Vector3.ZERO, 1.0, 1.0, oil)
	if pellet:
		return
	# back spatter toward the shooter: a small mist and a few drops
	var bd := (-d + _rand_unit() * 0.5).normalized()
	var bh := _ray(pos + bd * 0.05, pos + bd * 1.8)
	if not bh.is_empty():
		var bal: Vector3 = bd - bh.normal * bd.dot(bh.normal)
		spawn_decal(bh.position, bh.normal, _rng.randf_range(0.22, 0.4) * (0.8 + 0.4 * amount), "mist", bal, 1.0, 1.0, oil)
	for i in 1 + int(amount * 2.0):
		var bd2 := (-d + _rand_unit() * 0.8).normalized()
		var bh2 := _ray(pos + bd2 * 0.05, pos + bd2 * 1.6)
		if not bh2.is_empty():
			spawn_decal(bh2.position, bh2.normal, _rng.randf_range(0.03, 0.07), "small", Vector3.ZERO, 1.0, 1.0, oil)
	# drops straight down onto the floor beneath the wound
	for i in 2 + int(amount * 2.0):
		var fd := (Vector3.DOWN + _rand_unit() * 0.32).normalized()
		var fh := _ray(pos, pos + fd * 2.6)
		if not fh.is_empty():
			spawn_decal(fh.position, fh.normal, _rng.randf_range(0.04, 0.1), "small", Vector3.ZERO, 1.0, 1.0, oil)


## Blood flung off something bloody moving fast (a severed limb, a swung club,
## a tumbling body): an arc on the nearest surface in the plane of its motion.
## `vel` is the thing's velocity; the arc's tangent follows it.
func cast_off(pos: Vector3, vel: Vector3, amount: float = 1.0, oil := false) -> void:
	if splat_version != 2 or use_legacy_splatters or vel.length() < 2.0:
		return
	var m := vel.normalized()
	# surfaces beside the path: a ring of rays round the motion
	var best := {}
	var best_d := 9.0
	for i in 6:
		var a := TAU * (i + _rng.randf()) / 6.0
		var side := m.cross(Vector3.UP).normalized() if absf(m.y) < 0.9 else Vector3.RIGHT
		var up := side.cross(m).normalized()
		var rd := (side * cos(a) + up * sin(a) + m * 0.3).normalized()
		var h := _ray(pos, pos + rd * 1.4)
		if not h.is_empty():
			var dd: float = pos.distance_to(h.position)
			if dd < best_d:
				best_d = dd
				best = h
	if best.is_empty():
		return
	var n: Vector3 = best.normal.normalized()
	var along: Vector3 = m - n * m.dot(n)
	var size := clampf(0.8 + 0.4 * amount + best_d * 0.3, 0.8, 1.7)
	spawn_decal(best.position, n, size, "castoff", along, 1.0, 1.0, oil)


## A wall beside a body bleeding out against it: drops that ran (Phase B's
## volume regime). Placed once per bleed by the gore module.
func drip_field(pos: Vector3, normal: Vector3, size: float, oil := false) -> void:
	if splat_version != 2 or use_legacy_splatters:
		return
	spawn_decal(pos, normal, size, "dripfield", Vector3.UP, 1.0, 1.0, oil)


## (Phase D) The slot for a new mark: the ring's next if it is free; else, of
## the next RECYCLE_LOOK slots, the one that matters least - small before big,
## far from the camera before near - so the splat in front of you goes last.
func _pick_slot() -> int:
	if not _decals[_next].visible:
		return _next
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var best := _next
	var best_score := INF
	for k in RECYCLE_LOOK:
		var i := (_next + k) % MAX_DECALS
		var d := _decals[i]
		if not d.visible:
			return i
		var score: float = maxf(d.size.x, d.size.z)
		if cam != null and cam.global_position.distance_to(d.global_position) < 25.0:
			score += 2.0
		if score < best_score:
			best_score = score
			best = i
	return best


## The mark a recycled slot held goes on a spare decal and fades out.
func _hand_to_spare(d: Decal) -> void:
	recycled += 1
	if _spares.is_empty():
		return
	var sp: Decal = _spares.pop_back()
	sp.texture_albedo = d.texture_albedo
	sp.texture_normal = d.texture_normal
	sp.texture_orm = d.texture_orm
	sp.global_transform = d.global_transform
	sp.size = d.size
	sp.modulate = d.modulate
	sp.visible = true
	_fading.append([sp, 0.0])


## A single falling drop, for wounds that keep bleeding.
func add_droplet(pos: Vector3, vel: Vector3, size: float = 0.07, oil := false) -> void:
	if _drop_pos.size() >= MAX_DROPLETS:
		return
	_drop_pos.append(pos); _drop_vel.append(vel); _drop_size.append(size); _drop_life.append(4.0)
	_drop_oil.append(1 if oil else 0)


func _splat_on(pos: Vector3, normal: Vector3, travel: Vector3, size: float, oil := false) -> void:
	var facing: float = absf(travel.dot(normal))
	var along := (travel - normal * travel.dot(normal))
	if facing < 0.5 and along.length() > 0.05:
		# Glancing hit: the blood smears along the surface.
		spawn_decal(pos, normal, size * 1.1, "streak", along, 1.0, lerpf(2.2, 1.3, facing * 2.0), oil)
	elif size > 0.3:
		spawn_decal(pos, normal, size, "impact", Vector3.ZERO, 1.0, 1.0, oil)
	elif size < 0.2:
		spawn_decal(pos, normal, size * 1.3, "small", along, 1.0, 1.0, oil)
	else:
		spawn_decal(pos, normal, size * 1.3, "spray", along, 1.0, 1.0, oil)


## Place one decal. `along` (optional) points the texture's "up" along the surface.
func spawn_decal(pos: Vector3, normal: Vector3, size: float, kind: String, along: Vector3 = Vector3.ZERO, stretch_x: float = 1.0, stretch_z: float = 1.0, oil := false) -> void:
	var slot := _pick_slot()
	var d := _decals[slot]
	if d.visible:
		_hand_to_spare(d)
	_born[slot] = Time.get_ticks_msec() / 1000.0
	_decal_oil[slot] = 1 if oil else 0
	_next = (slot + 1) % MAX_DECALS
	if kind == "impact" and size >= 0.6:
		kind = "death"                  # a body's worth: the broad death splatters
	if splat_version == 2 and not use_legacy_splatters:
		if kind == "drip":
			size *= 0.5                                # a landed drop is a drop, not a saucer
		kind = SPLAT2_MAP.get(kind, kind)
		size /= float(SPLAT2_FILL.get(kind, 0.6))      # the shape is `size` across, not the texture
		# on a wall the kinds with drips hang them downward: the texture's up
		# is the world's up there (a mist keeps the travel direction: it is
		# the fan of the shot, and a shot straight at a wall fans every way)
		if kind in ["impact", "heavy", "dripfield", "streak"] and absf(normal.normalized().y) < 0.6:
			along = Vector3.UP
	var set_: Dictionary = _tex_oil if oil else _tex
	var pair: Array = set_[kind][_rng.randi() % set_[kind].size()]
	d.texture_albedo = pair[0]
	d.texture_normal = pair[1] if not flat_decals else null
	# (Phase B) v2 decals carry no ORM: a wet roughness turned a lamp into a
	# broad highlight that washed the colour out of every mass; the surface's
	# own roughness stays, the blood keeps its colour
	d.texture_orm = (pair[2] if splat_version != 2 else null) if not flat_decals else null
	# each one a little different: size, angle, and a shade darker, redder or browner
	size *= _rng.randf_range(0.88, 1.14)
	if along.length() > 0.01:
		along = along.rotated(normal.normalized(), _rng.randf_range(-0.18, 0.18))
	var shade := _rng.randf_range(0.82, 1.06)
	var brown := _rng.randf_range(0.0, 0.12)
	_tint[slot] = Color(shade, shade * (1.0 + brown * 1.6), shade * (1.0 + brown * 0.6), 1.0) if not oil else (Color(0.12, 0.11, 0.1, 1.0) if splat_version == 2 else FRESH)
	var y := normal.normalized()
	var z := along - y * along.dot(y)
	if z.length() < 0.01:
		z = y.cross(_rand_unit())
		if z.length() < 0.01:
			z = y.cross(Vector3.RIGHT)
	z = -z.normalized()                 # texture "up" is the decal's -Z
	var x := y.cross(z).normalized()
	d.size = Vector3(size * stretch_x, (clampf(0.1 + 0.2 * size, 0.12, 0.4) if splat_version == 2 else 0.3), size * stretch_z)
	d.global_transform = Transform3D(Basis(x, y, z), pos)
	d.modulate = _tint[slot]
	d.visible = true


# --- pools --------------------------------------------------------------------
func _apply_pool_settings() -> void:
	for m: ShaderMaterial in [_pool_material, _oil_material]:
		m.set_shader_parameter("edge_irregularity", edge_irregularity if enable_organic_pool_shapes else 0.25)
		m.set_shader_parameter("wet_reflections", enable_wet_reflections)


func _pool_cfg() -> Dictionary:
	return {
		shape_variation = shape_variation if enable_organic_pool_shapes else 0.0,
		max_pool_radius = maximum_pool_radius,
		stair_flow = enable_stair_flow and enable_geometry_aware_spreading,
		max_drops = maximum_stair_flow_steps,
		slope_bias_on = enable_slope_bias and enable_geometry_aware_spreading,
		slope_bias = pool_slope_bias,
		geometry = enable_geometry_aware_spreading,
	}


## Start (or feed) a pool on the floor at `pos`. `radius` is about how far it
## will spread on open floor (walls, steps and slopes reshape it).
func spawn_pool(pos: Vector3, normal: Vector3, radius: float, oil := false) -> void:
	if oil:
		spawn_oil_puddle(pos, normal, radius)
		return
	radius = minf(radius * pool_size, maximum_pool_radius)
	if enable_pool_merging:
		for p in _pools:
			if is_instance_valid(p) and p.covers(pos):
				p.feed(pos, radius, _space())
				if not p.sampling_done() and not _sampling.has(p):
					_sampling.append(p)
				return
	if _pools.size() >= MAX_POOLS:
		var old: BloodPool = _pools.pop_front()
		_sampling.erase(old)
		if is_instance_valid(old):
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void:
				if is_instance_valid(old):
					old.set_instance_shader_parameter("fade", v), 1.0, 0.0, 2.0)
			tw.tween_callback(old.queue_free)
	_pools.append(_new_pool(pos, radius, false))


## A puddle of machine oil: the same spreading, oil's look. Permanent: no
## cap and never faded; only clear() (the floor being torn down) removes
## them. One landing on an existing puddle feeds that one.
func spawn_oil_puddle(pos: Vector3, normal: Vector3, radius: float) -> void:
	radius = minf(radius, 0.95)                 # oil puddles keep their old size
	for p in _oil_pools:
		if is_instance_valid(p) and p.covers(pos):
			p.feed(pos, radius, _space())
			if not p.sampling_done() and not _sampling.has(p):
				_sampling.append(p)
			set_process(true)
			return
	_oil_pools.append(_new_pool(pos, radius, true))


func _new_pool(pos: Vector3, radius: float, oil: bool) -> BloodPool:
	var p := BloodPool.new()
	add_child(p)
	p.global_transform = Transform3D(Basis.IDENTITY, pos)
	p.material_override = _oil_material if oil else _pool_material
	# coarser sampling far from the camera
	var spacing: float = [0.12, 0.085, 0.065][clampi(surface_sampling_quality, 0, 2)]
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		spacing *= 1.0 + clampf((cam.global_position.distance_to(pos) - 12.0) / 20.0, 0.0, 0.6)
	p.setup(pos, radius, oil, _pool_cfg(), spacing)
	# a big pool takes longer to spread
	var size := clampf((radius - 0.15) / maxf(maximum_pool_radius - 0.15, 0.01), 0.0, 1.0)
	p.expand = lerpf(pool_expansion_duration.x, pool_expansion_duration.y, size) * _rng.randf_range(0.85, 1.15) * (0.7 if oil else 1.0)
	p.settle = _rng.randf_range(pool_settling_duration.x, pool_settling_duration.y)
	_sampling.append(p)
	set_process(true)
	return p


## How many oil puddles there are (tests).
func oil_puddle_count() -> int:
	return _oil_pools.size()


## The blood pools there are now (tests).
func pools() -> Array[BloodPool]:
	return _pools


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().find_world_3d().direct_space_state


func _update_pools(delta: float) -> void:
	# sampling: a shared ray budget per frame, oldest request first
	var deadline := Time.get_ticks_usec() + int(pool_work_ms * 1000.0)
	while Time.get_ticks_usec() < deadline and not _sampling.is_empty():
		var p: BloodPool = _sampling[0]
		if not is_instance_valid(p):
			_sampling.pop_front()
			continue
		if p.work(_space(), deadline):
			_sampling.pop_front()
		else:
			break
	# growing: only so many at once; the oldest beyond the cap settles at once
	var spreading := 0
	for list: Array[BloodPool] in [_pools, _oil_pools]:
		for i in range(list.size() - 1, -1, -1):
			var p := list[i]
			if not is_instance_valid(p) or not p.sampling_done():
				continue
			if not p.settled:
				spreading += 1
				if spreading > maximum_active_spreading_pools:
					p._t = p.expand + p.settle
				p.advance(delta)
			elif p.age < 1.0 and not p.oil:
				# drying, a little at a time
				p.age = minf((Time.get_ticks_msec() / 1000.0 - p.born) / DRY_TIME, 1.0)
				if Engine.get_process_frames() % 30 == 0:
					p.set_instance_shader_parameter("age", p.age)


func _process(delta: float) -> void:
	_update_pools(delta)
	# recycled marks fading out
	for k in range(_fading.size() - 1, -1, -1):
		var e: Array = _fading[k]
		e[1] += delta
		var sp: Decal = e[0]
		var m: Color = sp.modulate
		m.a = clampf(1.0 - float(e[1]) / FADE_OUT, 0.0, 1.0)
		sp.modulate = m
		if e[1] >= FADE_OUT:
			sp.visible = false
			_spares.append(sp)
			_fading.remove_at(k)
	# Darken a few decals each frame as the blood dries.
	var now := Time.get_ticks_msec() / 1000.0
	for i in 12:
		_dry_cursor = (_dry_cursor + 1) % MAX_DECALS
		var d := _decals[_dry_cursor]
		if d.visible and _decal_oil[_dry_cursor] == 0:      # oil does not dry
			d.modulate = _tint[_dry_cursor].lerp(_tint[_dry_cursor] * DRIED, clampf((now - _born[_dry_cursor]) / DRY_TIME, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _drop_pos.size():
		var p := _drop_pos[i]
		var v := _drop_vel[i] + Vector3.DOWN * 9.8 * delta
		var q := p + v * delta
		var hit := _ray(p, q)
		_drop_life[i] -= delta
		if not hit.is_empty():
			var s := _drop_size[i]
			var along: Vector3 = v - hit.normal * v.dot(hit.normal)
			var slant: float = clampf(along.length() / maxf(v.length(), 0.01), 0.0, 1.0)
			spawn_decal(hit.position, hit.normal, s * 2.2, "drip", along, 1.0, 1.0 + slant * 0.8, _drop_oil[i] == 1)
			_drop_life[i] = 0.0
		if _drop_life[i] <= 0.0:
			var last := _drop_pos.size() - 1
			_drop_pos[i] = _drop_pos[last]; _drop_vel[i] = _drop_vel[last]
			_drop_size[i] = _drop_size[last]; _drop_life[i] = _drop_life[last]; _drop_oil[i] = _drop_oil[last]
			_drop_pos.resize(last); _drop_vel.resize(last); _drop_size.resize(last); _drop_life.resize(last); _drop_oil.resize(last)
		else:
			_drop_pos[i] = q
			_drop_vel[i] = v
			i += 1


# --- helpers ------------------------------------------------------------------
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().find_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return space.intersect_ray(q)


func _rand_unit() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).limit_length(1.0)


func _build_mist(colour: Color) -> Array[GPUParticles3D]:
	var list: Array[GPUParticles3D] = []
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	for i in 6:
		var pm := ParticleProcessMaterial.new()
		pm.spread = 32.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 6.5
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.4
		pm.scale_max = 1.6
		pm.damping_min = 1.0
		pm.damping_max = 3.0
		pm.color_ramp = ramp
		var g := GPUParticles3D.new()
		g.process_material = pm
		g.draw_pass_1 = quad
		g.amount = 48
		g.lifetime = 0.55
		g.one_shot = true
		g.explosiveness = 0.95
		g.emitting = false
		g.layers = 2
		add_child(g)
		list.append(g)
	return list


## A puff of fine blood spray.
func mist(pos: Vector3, dir: Vector3, amount: float = 1.0, oil := false) -> void:
	_burst(pos, dir, amount, oil)


func _burst(pos: Vector3, dir: Vector3, amount: float, oil := false) -> void:
	var list := _mist_oil if oil else _mist
	var g := list[_mist_next % list.size()]
	_mist_next = (_mist_next + 1) % list.size()
	g.global_position = pos
	(g.process_material as ParticleProcessMaterial).direction = dir
	g.amount_ratio = clampf(0.35 + amount * 0.45, 0.2, 1.0)
	g.restart()
	g.emitting = true
