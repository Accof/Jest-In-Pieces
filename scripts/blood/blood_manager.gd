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
## (Phase C, 25 Nov) the CPU droplets are drawn now (a MultiMesh of liquid
## quads, see _draw_drops), so there are more of them: the heavy drops are seen
## arcing to the floor and landing where their mark appears.
const MAX_DROPLETS := 400
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
@export var maximum_pool_radius := 0.5                        ## metres (25 Nov: 0.6 -> 0.5, "pools too large")
@export var pool_size := 0.7                                  ## every blood pool's radius is scaled by this (oil is not)
@export var maximum_active_spreading_pools := 8               ## beyond this the oldest spreading one settles at once
@export var surface_sampling_quality := 1                     ## 0 low, 1 medium, 2 high (grid spacing 0.12 / 0.085 / 0.065 m)
@export var maximum_stair_flow_steps := 3                     ## how many step edges blood will run down
@export var pool_work_ms := 2.5                               ## time a frame may spend setting up new pools (rays, flood, mesh)
@export var pool_slope_bias := 0.6
var _pools: Array[BloodPool] = []
var _sampling: Array[BloodPool] = []   # waiting for (or part way through) their rays
var _pool_material: ShaderMaterial
## (Phase C, 25 Nov) Spray you can see. A hit fires a PLUME (strings and drops
## of liquid thrown along the round, velocity-stretched, dying at the wall
## behind) and a HAZE (the fine red mist that hangs for a second and drifts).
## Both pooled GPUParticles3D; the plume and the drawn droplets share
## shaders/blood_liquid.gdshader and art/blood/fx_liquid_sheet.png. The old
## 48-dot puff is gone. BLOOD_NO_SPRAY=1 turns the drawing off (the marks stay).
const PLUMES := 8
const PLUMES_OIL := 3
const HAZES := 6
const HAZES_OIL := 2
const PLUME_SPEED_MIN := 4.0
const PLUME_SPEED_MAX := 9.0
const PLUME_LIFE := 0.45
static var draw_spray := OS.get_environment("BLOOD_NO_SPRAY") != "1"
var _plumes: Array[GPUParticles3D] = []
var _plumes_oil: Array[GPUParticles3D] = []
var _hazes: Array[GPUParticles3D] = []
var _hazes_oil: Array[GPUParticles3D] = []
var _plume_next := 0
var _haze_next := 0
var _liquid: ShaderMaterial
var _liquid_oil: ShaderMaterial
var _drop_mm: MultiMesh
var _drop_mmi: MultiMeshInstance3D
var sprays := 0                      # plumes fired (tests)

## (Phase D, 25 Nov) Drips that run. A heavy wall mark (a headshot's mass, a
## close impact) grows runs downward over RUN_TIME: a quad hung under the mark
## with shaders/blood_run.gdshader scrolling the drip mask's reveal channel,
## a glistening head on each run while it moves, a bead where it stops. RUNS
## live at once; the oldest is baked to a dripfield decal when its quad is
## needed again, so a dried run stays as a mark.
const RUNS := 24
const RUN_TIME := Vector2(3.0, 7.0)
var _runs: Array[MeshInstance3D] = []
var _run_t: Array[float] = []        # seconds since start (-1 = free)
var _run_dur: Array[float] = []
var _run_tint: Array[Color] = []
var _run_next := 0
var _run_mask: Texture2D
var runs_started := 0               # tests
var _oil_material: ShaderMaterial
## Oil puddles: permanent until clear() (a new floor).
var _oil_pools: Array[BloodPool] = []
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
	_build_spray()
	_build_runs()


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
	_clear_runs()
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
	_draw_drops()
	for g: GPUParticles3D in _plumes + _plumes_oil + _hazes + _hazes_oil:
		g.emitting = false


# --- splatter -----------------------------------------------------------------
## A bullet passing through flesh at `pos` travelling along `dir`.
## `amount` 0..2 scales how much blood comes out. `zone` ("head", "" …) and
## `weapon` let the v2 placement pick the regime (Phase B).
## (25 Nov, after Andrew's test: "too much spray on every single shot ... it
## sprayed on a wall on the other side of the room") A hit is one of three
## tiers, by WHERE it landed before how hard:
##   head  - zone "head" (and the gore module's own big events: a severing, a
##           stump, a skull opening - amount >= 1.3 with no weapon named):
##           the plume, the haze, the full set of marks, 2.6 m reach.
##   body  - the torso: a modest exit spray, 1.6 m reach, one mist mark and a
##           few drops, a faint puff; a wall farther than that gets nothing,
##           the drops just arc to the floor.
##   limb  - arms, legs, hands, feet: a small mark and a couple of drops.
## A shotgun's pellets share one spray and one mark per shot; the 5th pellet
## of a shot on the same body (a close charge) adds the impact mass.
const TIER_REACH := {head = 2.6, body = 1.6, limb = 1.2}
var _shot_pellets := 0


## Zones: "head", "limb", "" (the torso), or "splash" - a bleeding body hitting
## a surface: the caller placed the mark, this is only the drops thrown.
func hit_tier(amount: float, zone: String, weapon: String) -> String:
	if zone == "head" or (weapon == "" and zone != "splash" and amount >= 1.3):
		return "head"
	if zone == "limb":
		return "limb"
	return "body"


## (25 Nov, his second test: "still too much spurt in general from the body
## and limbs. Also it shouldn't happen all the time. Too many different
## incoherent decals painting the same area") A body or limb hit does not
## always throw blood, and when it does it is ONE mark: a round that goes
## through (amount >= 0.9: rifle, revolver, Maxim) throws an exit mist 7 times
## in 10; a limb 4 in 10; pistol, SMG and single pellets stay in the body and
## throw nothing on the wall. The small plume comes half the time at most, no
## haze; the drops arc to the floor and stamp only there, never over the mist.
static var BODY_MARK_CHANCE := 0.7       # static vars so the tests can pin them
static var BODY_PLUME_CHANCE := 0.5
static var LIMB_MARK_CHANCE := 0.4
static var LIMB_PLUME_CHANCE := 0.3


func spawn_hit(pos: Vector3, dir: Vector3, amount: float = 1.0, oil := false, zone := "", weapon := "", shot_id := -1) -> void:
	dir = dir.normalized()
	var tier := hit_tier(amount, zone, weapon)
	var pellet := shot_id >= 0 and shot_id == _last_shot
	var through := amount >= 0.9 or weapon.containsn("shotgun")
	var mark := true
	var plume := true
	if zone == "splash":
		mark = false
		plume = _rng.randf() < BODY_PLUME_CHANCE
	elif tier == "body":
		mark = through and _rng.randf() < BODY_MARK_CHANCE
		plume = through and _rng.randf() < BODY_PLUME_CHANCE
	elif tier == "limb":
		mark = _rng.randf() < LIMB_MARK_CHANCE
		plume = _rng.randf() < LIMB_PLUME_CHANCE
	if not pellet and plume:
		_burst(pos, dir, amount, oil, tier)
	if splat_version == 2 and not use_legacy_splatters:
		_place_gunshot(pos, dir, amount, oil, tier, weapon, shot_id, mark)
		if pellet:
			return
		if tier == "head":
			# (Phase C) a few of the plume's drops are real: they fly with it,
			# land and stamp where it would have; and the heavy drops arc away
			for i in 3 + int(amount * 4.0):
				var v := dir * _rng.randf_range(PLUME_SPEED_MIN, PLUME_SPEED_MAX) + _rand_unit() * 0.9
				add_droplet(pos, v, _rng.randf_range(0.04, 0.09), oil)
			for i in 2 + int(amount * 4.0):
				var v := dir * _rng.randf_range(0.8, 3.0) + Vector3.UP * _rng.randf_range(0.3, 2.2) + _rand_unit() * 1.1
				add_droplet(pos, v, _rng.randf_range(0.05, 0.13), oil)
		else:
			# a body or limb: one or two drops that fall to the floor
			for i in (1 if tier == "limb" or not plume else 2):
				var v := dir * _rng.randf_range(0.6, 2.0) + Vector3.UP * _rng.randf_range(0.2, 1.4) + _rand_unit() * 0.8
				add_droplet(pos, v, _rng.randf_range(0.05, 0.1), oil, true)
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
var _last_shot := -1               # a shotgun's pellets share one big mark


## A gunshot's forward spatter: the cone's centre ray finds the surface behind
## the man; ONE mist decal lands there, sized by the distance flown and the
## hit's amount, stretched along the travel's projection (a shallow angle
## draws the fan out), the fan's wide end away from the shooter. Close or hard
## hits put an impact on top (the mass); a headshot a heavy with its drips.
## A handful of small drops are re-raycast round it, a little back spatter
## toward the shooter, a few drops on the floor beneath. A shotgun's pellets
## share the one big mark (the first pellet of a shot places it).
func _place_gunshot(pos: Vector3, dir: Vector3, amount: float, oil: bool, tier: String, weapon: String, shot_id: int, mark := true) -> void:
	var pellet := shot_id >= 0 and shot_id == _last_shot
	if shot_id >= 0:
		if pellet:
			_shot_pellets += 1
		else:
			_last_shot = shot_id
			_shot_pellets = 1
	var head := tier == "head"
	var limb := tier == "limb"
	var shotgun := weapon.containsn("shotgun")
	var d := (dir + _rand_unit() * 0.05).normalized()
	var reach: float = TIER_REACH[tier]
	if shotgun:
		reach = maxf(reach, 2.2)
	var hit := _ray(pos + d * 0.05, pos + d * reach) if mark else {}
	if not hit.is_empty() and not pellet:
		var n: Vector3 = (hit.normal as Vector3).normalized()
		var dist: float = pos.distance_to(hit.position)
		var facing: float = absf(d.dot(n))
		var along: Vector3 = d - n * d.dot(n)
		# the mark: a body shot's exit mist is 0.35-0.7 m, a headshot's up to
		# 1.3 m; it thins with distance rather than growing
		var size: float
		if head:
			size = clampf(0.5 + 0.25 * amount, 0.5, 0.9)
		elif limb:
			size = clampf(0.22 + 0.12 * amount, 0.22, 0.4)
		else:
			size = clampf(0.3 + 0.2 * amount, 0.3, 0.6)
		size *= 1.0 - 0.3 * clampf((dist - 0.8) / 1.8, 0.0, 1.0)
		if shotgun:
			size = minf(size * 1.3, 1.0)          # the whole charge's fan, placed by its first pellet
		var stretch := 1.0 + (1.0 - facing) * 1.6
		if facing < 0.45 and along.length() > 0.05 and not limb:
			# a graze along the surface: a dragged streak, and the mist beyond it
			spawn_decal(hit.position, n, size * 0.6, "streak", along, 1.0, 1.0 + (1.0 - facing) * 1.2, oil)
		spawn_decal(hit.position, n, size, "mist", along if along.length() > 0.08 else Vector3.ZERO, 1.0 / sqrt(stretch), sqrt(stretch), oil)
		# the mass: a headshot's heavy that drips, close and hard an impact
		if head and amount >= 0.8:
			spawn_decal(hit.position + along.normalized() * 0.04, n, clampf(0.4 + 0.2 * amount, 0.4, 0.7), "heavy", Vector3.ZERO, 1.0, 1.0, oil)
		elif head or (not limb and dist < 0.9 and amount >= 1.2):
			spawn_decal(hit.position, n, clampf(0.25 + 0.2 * amount, 0.25, 0.55), "impact", Vector3.ZERO, 1.0, 1.0, oil)
		# a headshot's small drops: a ring round the mark, outside the mist,
		# not on it (a body or limb is its one mark and nothing else)
		var drops := 4 + int(amount * 2.0) if head else 0
		for i in drops:
			var dd := (d + _rand_unit() * _rng.randf_range(0.3, 0.55)).normalized()
			var h2 := _ray(pos + dd * 0.05, pos + dd * (reach + 0.1))
			if not h2.is_empty():
				var sl: Vector3 = dd - h2.normal * dd.dot(h2.normal)
				spawn_decal(h2.position, h2.normal, _rng.randf_range(0.03, 0.07) * (1.0 + 0.2 * amount), "small", sl, 1.0, 1.0 + sl.length() * 1.5, oil)
	elif not hit.is_empty() and pellet:
		# one more pellet of the same shot: a drop in the fan, no second mark;
		# the fifth on one body is a close charge - the mass goes on
		var dd := (d + _rand_unit() * 0.3).normalized()
		var h2 := _ray(pos + dd * 0.05, pos + dd * reach)
		if not h2.is_empty():
			spawn_decal(h2.position, h2.normal, _rng.randf_range(0.03, 0.08), "small", Vector3.ZERO, 1.0, 1.0, oil)
		if _shot_pellets == 5 and not limb:
			var n: Vector3 = (hit.normal as Vector3).normalized()
			spawn_decal(hit.position, n, 0.45, "impact", Vector3.ZERO, 1.0, 1.0, oil)
	if pellet:
		return
	# back spatter toward the shooter: a headshot's small mist and a few drops
	if head:
		var bd := (-d + _rand_unit() * 0.5).normalized()
		var bh := _ray(pos + bd * 0.05, pos + bd * 1.8)
		if not bh.is_empty():
			var bal: Vector3 = bd - bh.normal * bd.dot(bh.normal)
			spawn_decal(bh.position, bh.normal, _rng.randf_range(0.22, 0.4) * (0.8 + 0.4 * amount), "mist", bal, 1.0, 1.0, oil)
	var back := 1 + int(amount * 2.0) if head else 0
	for i in back:
		var bd2 := (-d + _rand_unit() * 0.8).normalized()
		var bh2 := _ray(pos + bd2 * 0.05, pos + bd2 * 1.6)
		if not bh2.is_empty():
			spawn_decal(bh2.position, bh2.normal, _rng.randf_range(0.03, 0.07), "small", Vector3.ZERO, 1.0, 1.0, oil)
	# drops straight down onto the floor beneath the wound
	var floor_drops := 2 + int(amount * 2.0) if head else (0 if limb else 1)
	for i in floor_drops:
		var fd := (Vector3.DOWN + _rand_unit() * 0.32).normalized()
		var fh := _ray(pos, pos + fd * 2.6)
		if not fh.is_empty():
			spawn_decal(fh.position, fh.normal, _rng.randf_range(0.03, 0.08), "small", Vector3.ZERO, 1.0, 1.0, oil)


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
	# (25 Nov) a gib's arc is 0.5-0.8 m, a tumbling body's up to 1.1 (was 0.8-1.7)
	var size := clampf(0.3 + 0.35 * amount + best_d * 0.15, 0.3, 1.1)
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
## `floor_only`: the drop stamps where it lands on a floor but not on a wall
## (a body shot's drops must not paint a second set of marks over its mist).
func add_droplet(pos: Vector3, vel: Vector3, size: float = 0.07, oil := false, floor_only := false) -> void:
	if _drop_pos.size() >= MAX_DROPLETS:
		return
	_drop_pos.append(pos); _drop_vel.append(vel); _drop_size.append(size); _drop_life.append(4.0)
	_drop_oil.append((1 if oil else 0) | (2 if floor_only else 0))


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
	# (Phase D) a heavy on a wall runs; a close impact on a wall half the time
	if absf(y.y) < 0.6 and (kind == "heavy" or (kind == "impact" and _rng.randf() < 0.5)):
		start_run(pos, y, size * (1.0 if kind == "heavy" else 0.7), _tint[slot], oil)


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
	_tick_runs(delta)
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
			if (_drop_oil[i] & 2) == 0 or absf(hit.normal.y) > 0.6:
				spawn_decal(hit.position, hit.normal, s * 1.2, "drip", along, 1.0, 1.0 + slant * 0.8, (_drop_oil[i] & 1) == 1)
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
	_draw_drops()


# --- helpers ------------------------------------------------------------------
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().find_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return space.intersect_ray(q)


func _rand_unit() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).limit_length(1.0)


# --- Phase D: drips that run (25 Nov) --------------------------------------------------
func _build_runs() -> void:
	_run_mask = load("res://art/blood/splat2/drip_mask.png")
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, -0.5, 0.0)        # hangs from its top edge
	for i in RUNS:
		var m := MeshInstance3D.new()
		m.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/blood_run.gdshader")
		mat.set_shader_parameter("mask", _run_mask)
		m.material_override = mat
		m.visible = false
		m.layers = 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_runs.append(m)
		_run_t.append(-1.0)
		_run_dur.append(1.0)
		_run_tint.append(Color.WHITE)


## Start runs under a wall mark of `size` metres at `pos` on a wall with
## `normal`. The quad is `width` wide and runs down `height`.
func start_run(pos: Vector3, normal: Vector3, size: float, tint: Color, oil := false) -> void:
	if use_legacy_splatters or splat_version != 2:
		return
	normal = normal.normalized()
	if absf(normal.y) > 0.6:
		return
	runs_started += 1
	var i := _run_next
	_run_next = (_run_next + 1) % RUNS
	if _run_t[i] >= 0.0:
		_bake_run(i)
	var m := _runs[i]
	var width := clampf(size * 0.65, 0.18, 0.6)       # narrower than the mass: the runs come out of it, not beside it
	var height := clampf(size * 1.4, 0.3, 0.9)
	var up := Vector3.UP - normal * normal.dot(Vector3.UP)
	if up.length() < 0.01:
		return
	up = up.normalized()
	var right := up.cross(normal).normalized()
	# the quad faces +Z in its own space; its Y is up; it hangs from pos
	m.global_transform = Transform3D(Basis(right * width, up * height, normal), pos + normal * 0.006 + up * size * 0.1)      # the first of each run is under the mass
	var mat := m.material_override as ShaderMaterial
	# a different slice of the eight runs each time, 3-6 of them across the width
	mat.set_shader_parameter("uv_scale", Vector2(_rng.randf_range(0.4, 0.75), clampf(height / 0.9, 0.5, 1.0)))
	mat.set_shader_parameter("uv_offset", Vector2(_rng.randf(), 0.0))
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("wet", 1.0)
	if oil:
		mat.set_shader_parameter("deep", Color(0.012, 0.011, 0.01))
		mat.set_shader_parameter("thin", Color(0.06, 0.055, 0.045))
	else:
		mat.set_shader_parameter("deep", Color(0.040, 0.003, 0.004))
		mat.set_shader_parameter("thin", Color(0.20, 0.012, 0.009))
	mat.set_shader_parameter("tint", tint)
	_run_tint[i] = tint
	_run_t[i] = 0.0
	_run_dur[i] = _rng.randf_range(RUN_TIME.x, RUN_TIME.y)
	m.visible = true


func _tick_runs(delta: float) -> void:
	for i in RUNS:
		if _run_t[i] < 0.0:
			continue
		_run_t[i] += delta
		var mat := _runs[i].material_override as ShaderMaterial
		var t: float = clampf(_run_t[i] / _run_dur[i], 0.0, 1.0)
		# fast at first, slowing as the blood thins: 1 - (1 - t)^2
		mat.set_shader_parameter("progress", 1.0 - (1.0 - t) * (1.0 - t))
		if _run_t[i] > _run_dur[i]:
			var dry: float = clampf((_run_t[i] - _run_dur[i]) / DRY_TIME, 0.0, 1.0)
			mat.set_shader_parameter("tint", _run_tint[i].lerp(_run_tint[i] * DRIED, dry))
			mat.set_shader_parameter("wet", 1.0 - dry)


## A run's quad is needed again: what it left stays as a dripfield decal.
func _bake_run(i: int) -> void:
	var m := _runs[i]
	var xf := m.global_transform
	var height := xf.basis.y.length()
	var width := xf.basis.x.length()
	var normal := xf.basis.z.normalized()
	spawn_decal(xf.origin - xf.basis.y.normalized() * height * 0.5, normal, maxf(height, width) * 0.9, "dripfield", Vector3.UP, width / maxf(height, 0.01), 1.0, false)
	m.visible = false
	_run_t[i] = -1.0


func _clear_runs() -> void:
	for i in RUNS:
		_runs[i].visible = false
		_run_t[i] = -1.0


# --- Phase C: spray you can see (25 Nov) ----------------------------------------------
func _liquid_material(oil: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blood_liquid.gdshader")
	m.set_shader_parameter("sheet", load("res://art/blood/fx_liquid_sheet.png"))
	if oil:
		m.set_shader_parameter("deep", Color(0.012, 0.011, 0.01))
		m.set_shader_parameter("thin", Color(0.07, 0.065, 0.05))
	return m


func _build_spray() -> void:
	_liquid = _liquid_material(false)
	_liquid_oil = _liquid_material(true)
	# the drawn droplets: one quad per CPU drop, Y along its travel
	_drop_mm = MultiMesh.new()
	_drop_mm.transform_format = MultiMesh.TRANSFORM_3D
	_drop_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_drop_mm.mesh = q
	_drop_mm.instance_count = MAX_DROPLETS
	_drop_mm.visible_instance_count = 0
	_drop_mmi = MultiMeshInstance3D.new()
	_drop_mmi.multimesh = _drop_mm
	_drop_mmi.material_override = _liquid
	_drop_mmi.custom_aabb = AABB(Vector3(-400, -100, -400), Vector3(800, 200, 800))
	_drop_mmi.layers = 2
	_drop_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drop_mmi)
	for i in PLUMES:
		_plumes.append(_make_plume(false))
	for i in PLUMES_OIL:
		_plumes_oil.append(_make_plume(true))
	for i in HAZES:
		_hazes.append(_make_haze(false))
	for i in HAZES_OIL:
		_hazes_oil.append(_make_haze(true))


## The plume: 220 strings and drops thrown along the round in a 12 degree
## cone at 4-9 m/s, under gravity, each aligned to its own velocity.
func _make_plume(oil: bool) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.spread = 12.0
	pm.initial_velocity_min = PLUME_SPEED_MIN
	pm.initial_velocity_max = PLUME_SPEED_MAX
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.6
	pm.scale_min = 0.55
	pm.scale_max = 1.5
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.particle_flag_align_y = true
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.alpha_curve = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.11)
	var g := GPUParticles3D.new()
	g.process_material = pm
	g.draw_pass_1 = quad
	g.material_override = _liquid_oil if oil else _liquid
	g.amount = 220
	g.lifetime = PLUME_LIFE
	g.one_shot = true
	g.explosiveness = 0.86
	g.randomness = 0.35
	g.emitting = false
	g.layers = 2
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	add_child(g)
	return g


## The haze: the fine mist that hangs after a hit - slow soft puffs, low
## alpha, a little turbulence, settling slowly.
func _make_haze(oil: bool) -> GPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.025, 0.02, 1.0) if oil else Color(0.34, 0.02, 0.016, 1.0)
	mat.albedo_texture = load("res://art/blood/fx_haze.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	quad.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.spread = 38.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -0.35, 0)
	pm.damping_min = 2.5
	pm.damping_max = 4.5
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.2))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.08, Color(1, 1, 1, 0.11))
	fade.add_point(0.5, Color(1, 1, 1, 0.07))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	var g := GPUParticles3D.new()
	g.process_material = pm
	g.draw_pass_1 = quad
	g.amount = 160
	g.lifetime = 1.4
	g.one_shot = true
	g.explosiveness = 0.9
	g.randomness = 0.3
	g.emitting = false
	g.layers = 2
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	add_child(g)
	return g


## A puff of fine blood spray.
## Under 1.2 it is a body-class puff (a spurt's beat: slow, no haze); 1.2 and
## over the head-class burst (a skull going).
func mist(pos: Vector3, dir: Vector3, amount: float = 1.0, oil := false) -> void:
	_burst(pos, dir, amount, oil, "head" if amount >= 1.2 else "body")


## The plume and the haze of one hit. The plume's life is cut to the wall
## behind (GPU particles cannot collide here): a ray along the round finds it
## and the strings die as they reach it; the Phase B marks are already there.
## The tier sets the plume's speed, span and count: a headshot's 4-9 m/s for
## 0.45 s (up to 4 m into open air) with the haze; a body shot's 2.5-5 m/s for
## 0.32 s (1.6 m), no haze; a limb's 2-4 m/s, a few strings, no haze.
var probe: Callable                  # tests: called (tier, amount) for every plume


func _burst(pos: Vector3, dir: Vector3, amount: float, oil := false, tier := "head") -> void:
	sprays += 1
	if probe.is_valid():
		probe.call(tier, amount)
	if not draw_spray:
		return
	dir = dir.normalized()
	var smin := PLUME_SPEED_MIN
	var smax := PLUME_SPEED_MAX
	var span := PLUME_LIFE
	var ratio := clampf(0.3 + amount * 0.45, 0.2, 1.0)
	var haze_ratio := clampf(0.3 + amount * 0.4, 0.2, 1.0)
	if tier == "body":
		smin = 2.5; smax = 5.0; span = 0.32
		ratio = clampf(0.12 + amount * 0.08, 0.12, 0.25)
		haze_ratio = 0.0
	elif tier == "limb":
		smin = 2.0; smax = 4.0; span = 0.28
		ratio = 0.08
		haze_ratio = 0.0
	var plumes := _plumes_oil if oil else _plumes
	var p := plumes[_plume_next % plumes.size()]
	_plume_next = (_plume_next + 1) % plumes.size()
	var pm := p.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = smin
	pm.initial_velocity_max = smax
	var reach := smax * span
	var hit := _ray(pos + dir * 0.03, pos + dir * reach)
	var life := span
	if not hit.is_empty():
		var dist: float = pos.distance_to(hit.position)
		life = clampf(dist / (smin + (smax - smin) * 0.8), 0.06, span)
	p.global_position = pos
	pm.direction = dir
	p.lifetime = life
	p.amount_ratio = ratio
	p.restart()
	p.emitting = true
	if haze_ratio <= 0.0:
		return
	var hazes := _hazes_oil if oil else _hazes
	var h := hazes[_haze_next % hazes.size()]
	_haze_next = (_haze_next + 1) % hazes.size()
	h.global_position = pos + dir * 0.1
	(h.process_material as ParticleProcessMaterial).direction = dir
	h.amount_ratio = haze_ratio
	h.restart()
	h.emitting = true


## Draw the CPU droplets: a quad each, Y along its travel, longer the faster
## it goes (a falling drop is a drop; a spurt is a string).
func _draw_drops() -> void:
	if _drop_mm == null:
		return
	var n := _drop_pos.size()
	if not draw_spray:
		_drop_mm.visible_instance_count = 0
		return
	_drop_mm.visible_instance_count = n
	for i in n:
		var v := _drop_vel[i]
		var speed := v.length()
		var ay := v / speed if speed > 0.05 else Vector3.UP
		var ax := ay.cross(Vector3.FORWARD if absf(ay.z) < 0.9 else Vector3.RIGHT).normalized()
		var az := ax.cross(ay)
		var s := _drop_size[i]
		var w := s * 0.3
		var l := clampf(speed * 0.025, s * 0.8, 0.25)
		var b := Basis(ax * w, ay * l, az * w)
		_drop_mm.set_instance_transform(i, Transform3D(b, _drop_pos[i]))
		# the frame: drops for a slow one, strings for a fast one (sheet rows 0-1 / 2-3)
		var frame := ((i * 7) % 8 + (8 if speed > 2.5 else 0)) / 16.0 + 0.01
		_drop_mm.set_instance_custom_data(i, Color(0.0, 0.0, frame, float(_drop_oil[i] & 1)))
