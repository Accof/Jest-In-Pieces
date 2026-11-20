class_name ClownGore
extends Node
## Wounds on the body, bleeding and pooling, and limb loss.

const BODY_SHADER := preload("res://shaders/clown_body.gdshader")
const MAX_WOUNDS := 16
const LAYER_WORLD := 1
const LAYER_GIBS := 1 << 3

## Segment ids match clown_segments.json and the mesh's UV2 channel.
const SEGMENTS := [&"Pelvis", &"Torso", &"Head", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand", &"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot",
	&"RightUpperArm", &"RightLowerArm", &"RightHand", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]
## Which skeleton bone each segment's gib is positioned from.
const SEGMENT_BONE := {&"Pelvis": &"Hips", &"Torso": &"Spine", &"Head": &"Neck"}
const CHAIN := {"UpperArm": ["UpperArm", "LowerArm", "Hand"], "LowerArm": ["LowerArm", "Hand"], "Hand": ["Hand"],
	"UpperLeg": ["UpperLeg", "LowerLeg", "Foot"], "LowerLeg": ["LowerLeg", "Foot"], "Foot": ["Foot"]}

## A limb, the head or the legs came off as `gib` (the Klappersoldat moves its
## glowing eyes onto the head when it comes off).
signal part_severed(segment: StringName, gib: Node3D)

var clown: Clown
## Clockwork insides that turn while the body still runs: [node, axis, speed].
## Filled only on a mechanical body; whoever owns the body spins them.
var spin_parts: Array = []
var _mech_open := {}            # region -> how many times it has been torn into
var hidden_mask := 0
## Stump faces never to show: segments below the top of a cut.
var cap_mask := 0

var _materials: Array[ShaderMaterial] = []
var _wound_pos: Array[Vector4] = []
var _wound_fx: Array[Vector4] = []
var _wound_age: Array[float] = []
var _bleeds: Array = []         # {bone, local, amount, still, pooled, drip}
var _spurts: Array = []         # {bone, local, dir, left, next}
var _tunnels: Array[Vector4] = []      # rest-space point + radius
var _tunnel_dirs: Array[Vector4] = []  # rest-space direction + reach
var _innards := {}              # region -> Node3D of exposed insides, shown once blown open
var _cores: Array = []          # [a, b]: rest-space Vector4s, the channels heavy hits tore through the anatomy
## The old insides made of boxes and spheres instead of the real anatomy
## (ClownAnatomy): kept only to compare against.
static var procedural_innards := false
var _anat_mats: Array[ShaderMaterial] = []      # this body's anatomy: they carry its wounds
var _gutted := false
var _smear_last := {}           # bone -> last point smeared on a wall
var _bleeding := false
var _bleed_time := 0.0
var _rng := RandomNumberGenerator.new()
var mud_level := 0.0            # how muddy this one's uniform is (0..1)


func setup(c: Clown) -> void:
	clown = c
	_rng.randomize()
	# trench mud on the uniform, each man his own (the soldiers only)
	var mud := 0.0
	var mud_seed := 0.0
	if clown.spec.get("muddy", false):
		mud = _rng.randf_range(0.55, 1.0)
		mud_seed = _rng.randf_range(0.0, 100.0)
	mud_level = mud
	var m := clown.mesh.mesh
	for i in m.get_surface_count():
		var src := m.surface_get_material(i) as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = BODY_SHADER
		if src:
			sm.set_shader_parameter("albedo_color", src.albedo_color)
			sm.set_shader_parameter("roughness", src.roughness)
			sm.set_shader_parameter("metallic", src.metallic)
			# a body that is mostly cloth (a uniform): matte, whatever the
			# model's export said (Blender exports 0.5, which reads as satin)
			if clown.spec.has("surface") and not (src.resource_name in ["Gore", "BoneCore"]):
				var surf: Vector2 = clown.spec.surface
				sm.set_shader_parameter("roughness", surf.x)
				sm.set_shader_parameter("specular_amount", surf.y)
			if src.albedo_texture:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("use_tex", true)
			# a body with full PBR maps keeps them (spec.pbr: the dark WitzSoldat)
			if clown.spec.get("pbr", false):
				if src.roughness_texture:
					sm.set_shader_parameter("mr_tex", src.roughness_texture)
					sm.set_shader_parameter("use_mr", true)
				if src.normal_enabled and src.normal_texture:
					sm.set_shader_parameter("normal_tex", src.normal_texture)
					sm.set_shader_parameter("use_normal", true)
		sm.set_shader_parameter("rest_min", clown.spec.rest_min)
		sm.set_shader_parameter("rest_size", clown.spec.rest_size)
		if mud > 0.0 and not (src and src.resource_name in ["Gore", "BoneCore"]):
			sm.set_shader_parameter("mud_amount", mud)
			sm.set_shader_parameter("mud_seed", mud_seed)
			sm.set_shader_parameter("mud_hem", clown.spec.get("mud_hem", 0.66))
		if clown.mechanical:
			_mech_surface(sm, src)
		clown.mesh.set_surface_override_material(i, sm)
		_materials.append(sm)
	_push_wounds()


# --- wounds -------------------------------------------------------------------
func add_wound(bone: StringName, world_pos: Vector3, damage: float) -> void:
	var radius := clampf(0.022 + damage * 0.0005, 0.022, 0.06)
	var depth := clampf(0.006 + damage * 0.0003, 0.006, 0.022)
	_add_wound_entry(bone, world_pos, radius, depth, 0.0)
	var pb: PhysicalBone3D = clown.ragdoll.bones.get(bone)
	if pb:
		var amount := clampf(damage / 40.0, 0.25, 1.0) * (1.4 if bone == &"Neck" else 1.0)
		_bleeds.append({bone = bone, local = pb.global_transform.affine_inverse() * world_pos, amount = amount, still = 0.0, pooled = false, drip = 0.0})
		if _bleeds.size() > 10:
			_bleeds.pop_front()
	set_process(true)


## Where a point on the posed body sits on the un-posed body (rest space).
func rest_point(bone: StringName, world_pos: Vector3) -> Vector3:
	var skel := clown.skeleton
	var idx := skel.find_bone(bone)
	if idx < 0:
		return Vector3.ZERO
	var in_skel := skel.global_transform.affine_inverse() * world_pos
	return skel.get_bone_global_rest(idx) * (clown.ragdoll.bone_pose(idx).affine_inverse() * in_skel)


func _add_wound_entry(bone: StringName, world_pos: Vector3, radius: float, depth: float, hole: float) -> void:
	var skel := clown.skeleton
	var idx := skel.find_bone(bone)
	# Convert the hit point back to where it sits on the un-posed body.
	var in_skel := skel.global_transform.affine_inverse() * world_pos
	var rest_pos := skel.get_bone_global_rest(idx) * (clown.ragdoll.bone_pose(idx).affine_inverse() * in_skel)
	if _wound_pos.size() >= MAX_WOUNDS:
		# Drop the oldest ordinary wound first; blown-out holes are kept.
		var drop := 0
		for k in _wound_fx.size():
			if _wound_fx[k].w <= 0.0:
				drop = k
				break
		_wound_pos.remove_at(drop); _wound_fx.remove_at(drop); _wound_age.remove_at(drop)
	_wound_pos.append(Vector4(rest_pos.x, rest_pos.y, rest_pos.z, radius))
	_wound_fx.append(Vector4(depth, 0.0, _rng.randf() * 40.0, hole))
	_wound_age.append(0.0)
	_push_wounds()


# --- a hole clean through ------------------------------------------------------------
## A shotgun at point blank: the charge goes through as one, and leaves a
## ragged hole right through the body that you can see daylight through.
## `dir` is the way the shot was travelling. Returns false if it has no room.
func punch_through(bone: StringName, world_pos: Vector3, dir: Vector3, radius: float) -> bool:
	if _tunnels.size() >= 4:
		return false
	var skel := clown.skeleton
	var idx := skel.find_bone(bone)
	var in_skel := skel.global_transform.affine_inverse() * world_pos
	var back := skel.get_bone_global_rest(idx) * clown.ragdoll.bone_pose(idx).affine_inverse()
	var rest_pos := back * in_skel
	var rest_dir := (back.basis * (skel.global_transform.basis.inverse() * dir)).normalized()
	_tunnels.append(Vector4(rest_pos.x, rest_pos.y, rest_pos.z, radius))
	_tunnel_dirs.append(Vector4(rest_dir.x, rest_dir.y, rest_dir.z, 0.32))
	for sm in _materials:
		var t := _tunnels.duplicate()
		var td := _tunnel_dirs.duplicate()
		while t.size() < 4:
			t.append(Vector4.ZERO)
			td.append(Vector4.ZERO)
		sm.set_shader_parameter("tunnel_count", _tunnels.size())
		sm.set_shader_parameter("tunnels", t)
		sm.set_shader_parameter("tunnel_dirs", td)
	# What was in the way inside goes too: the insides show round the rim,
	# but the middle is gone.
	var region := &"chest" if bone == &"Chest" else &"belly"
	_show_innards(region)
	_add_core(rest_pos - rest_dir * 0.32, rest_pos + rest_dir * 0.32, radius)
	var holder: Node3D = _innards[region]
	for part in (holder.get_children() if not _anat_region(holder) else []):
		var d: Vector3 = (part as Node3D).position - rest_pos
		var off := (d - rest_dir * d.dot(rest_dir)).length()
		if off < radius * 1.25:
			part.queue_free()
	# everything that was in there goes out the back
	var out := world_pos + dir * 0.28
	if clown.mechanical:
		_mech_tear(region, 1.0)
		MechFx.sparks(clown, world_pos, -dir, 1.6)
		MechFx.sparks(clown, out, dir, 1.6)
	Blood.spawn_hit(world_pos, -dir, 1.2, clown.mechanical)
	for k in 3:
		Blood.spawn_hit(out + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05)), (dir + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.1, 0.4), _rng.randf_range(-0.3, 0.3))).normalized(), 2.4, clown.mechanical)
	Blood.mist(out, dir, 2.0, clown.mechanical)
	_throw_chunks(out, dir, 9, false)
	var pb: PhysicalBone3D = clown.ragdoll.bones.get(bone)
	if pb:
		var inv := pb.global_transform.affine_inverse()
		for at: Vector3 in [world_pos, out]:
			_bleeds.append({bone = bone, local = inv * at, amount = 1.6, still = 0.0, pooled = false, drip = 0.0})
		_spurts.append({bone = bone, local = inv * out, dir = inv.basis * (dir + Vector3.UP * 0.3).normalized(), left = 6, next = 0.0})
		set_physics_process(true)
	set_process(true)
	return true


# --- shotgun damage -------------------------------------------------------------
## A close shotgun blast: bites a ragged hole out of the body at `world_pos`,
## showing what is inside, and throws meat out the far side.
## `size` is the hole radius in metres. `dir` is the way the shot was travelling.
func blast(bone: StringName, world_pos: Vector3, dir: Vector3, size: float) -> void:
	var region := &"head" if bone == &"Neck" else (&"chest" if bone == &"Chest" else &"belly")
	_show_innards(region)
	# the channel it tore: organs and all, from the entry to (for the trunk) the exit
	var rr := _rest_of(bone, world_pos, dir)
	# (not in the head: a face or crown hole has no exit, and a channel there
	# only empties the skull of what should show in it)
	if region != &"head":
		_add_core(rr[0] - rr[1] * 0.03, rr[0] + rr[1] * 0.24, size * 0.72)
	_add_wound_entry(bone, world_pos, size * 1.15, size * 0.45, size)
	if region != &"head":
		# The shot carries on through: a second, smaller hole out the back.
		_add_wound_entry(bone, world_pos + dir * 0.2, size * 0.9, size * 0.2, size * 0.7)
	set_process(true)
	if clown.mechanical:
		_mech_tear(region, size)
		MechFx.sparks(clown, world_pos, -dir, 1.4)
		MechFx.sound(clown, "spark", world_pos, -4.0)
	Blood.spawn_hit(world_pos, dir, 1.8, clown.mechanical)
	Blood.spawn_hit(world_pos, -dir, 0.9, clown.mechanical)
	_throw_chunks(world_pos, dir, 5 if region != &"head" else 4, region == &"head")
	var pb: PhysicalBone3D = clown.ragdoll.bones.get(bone)
	if pb:
		var inv := pb.global_transform.affine_inverse()
		_spurts.append({bone = bone, local = inv * world_pos, dir = inv.basis * (-dir + Vector3.UP * 0.6).normalized(), left = 7, next = 0.0})
		_bleeds.append({bone = bone, local = inv * world_pos, amount = 1.5, still = 0.0, pooled = false, drip = 0.0})
		set_physics_process(true)
		if region == &"belly" and not _gutted:
			_gutted = true
			_hang_guts(pb, world_pos, -dir)


func _throw_chunks(pos: Vector3, dir: Vector3, count: int, skull: bool) -> void:
	if clown.mechanical:
		_throw_debris(pos, dir, count, skull)
		return
	for i in count:
		var bone_bit := skull and i < 2
		var r := _rng.randf_range(0.022, 0.045)
		var g := GoreBit.make(_chunk_mesh(bone_bit), r, 0.12)
		clown.get_parent().add_child(g)
		g.global_position = pos + dir * 0.12 + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))
		g.scale = Vector3.ONE * (r / 0.03)
		g.linear_velocity = (dir * _rng.randf_range(2.0, 6.5) + Vector3.UP * _rng.randf_range(0.5, 3.5) + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)))
		g.angular_velocity = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12), _rng.randf_range(-12, 12))


## A loop of intestine spilling from a belly wound: a short chain of soft links
## pinned to the body, which hangs, swings and drags along the floor.
func _hang_guts(pb: PhysicsBody3D, world_pos: Vector3, out: Vector3, links: int = 6, keep: bool = false) -> void:
	var prev: PhysicsBody3D = pb
	var at := world_pos + out * 0.04
	var mesh: Mesh = _cable_mesh() if clown.mechanical else (ClownAnatomy.gut_link() if _anatomy_bones() else _gut_mesh())
	for i in links:
		var link := GoreBit.make(mesh, 0.018 if clown.mechanical else 0.024, 0.08, 0.1)
		link.oil = clown.mechanical
		link.marks = i == links - 1
		link.add_to_group(&"blast_movable")
		if keep:
			GoreBit._live.erase(link)        # never recycled while it is in use
		link.collision_mask = 1
		clown.get_parent().add_child(link)
		var next_at := at + out * 0.03 + Vector3.DOWN * 0.085
		link.global_position = (at + next_at) * 0.5
		var joint := PinJoint3D.new()
		clown.get_parent().add_child(joint)
		joint.global_position = at
		joint.node_a = joint.get_path_to(prev)
		joint.node_b = joint.get_path_to(link)
		link.tree_exiting.connect(joint.queue_free)
		prev = link
		at = next_at


## Where the insides were laid out: the plain clown's bones (rest, skeleton space).
const CLOWN_BONES := {"Head": Vector3(0, 1.615, 0.008), "Chest": Vector3(0, 1.26, 0), "Spine": Vector3(0, 1.08, 0)}


func _show_innards(region: StringName) -> void:
	if _innards.has(region):
		return
	if clown.mechanical:
		_show_machinery(region)
		return
	if not procedural_innards and ClownAnatomy.has_fit(clown.look):
		var holders: Array = []
		for part: String in ClownAnatomy.SHOWS[region]:
			var made := ClownAnatomy.build(clown.skeleton, clown.look, part)
			holders.append(made[0])
			for m: ShaderMaterial in made[1]:
				_anat_mats.append(m)
		_innards[region] = holders[0]
		_push_wounds()
		return
	var skel := clown.skeleton
	var bone := {&"head": "Head", &"chest": "Chest", &"belly": "Spine"}[region] as String
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skel.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	# Parts are laid out in the plain clown's skeleton space, then moved (and
	# scaled, for a body whose head is smaller) onto this body's bone, which
	# carries them. Without that, a body built differently has its brain
	# floating above a lower head (the Zornhauptmann's sits 10 cm lower).
	var rest := skel.get_bone_global_rest(skel.find_bone(bone))
	var ref: Vector3 = CLOWN_BONES[bone]
	var sc: float = (clown.spec.get("innards_scale", {}) as Dictionary).get(region, 1.0)
	var to_body := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), rest.origin - ref * sc)
	holder.transform = rest.affine_inverse() * to_body
	match region:
		&"chest":
			_part(holder, _blob_mesh(), _mat("meat"), Vector3(0, 1.39, -0.005), Vector3(0.145, 0.135, 0.09))
			for k in 6:                                    # ribs: hoops of bone round the meat
				var y := 1.285 + k * 0.042
				var rx := 0.150 + 0.012 * sin(k * 0.6)
				for a in 14:
					var ang := TAU * a / 14.0
					var p := Vector3(cos(ang) * rx, y - 0.012 * absf(cos(ang)), sin(ang) * 0.098)
					_part(holder, _box_mesh(), _mat("bone"), p, Vector3(0.036, 0.016, 0.014), Vector3(0, -ang + PI * 0.5, 0))
			_part(holder, _box_mesh(), _mat("bone"), Vector3(0, 1.39, 0.098), Vector3(0.03, 0.2, 0.014))    # breastbone
			_part(holder, _box_mesh(), _mat("bone"), Vector3(0, 1.39, -0.09), Vector3(0.035, 0.26, 0.03))   # spine
		&"belly":
			_part(holder, _blob_mesh(), _mat("meat"), Vector3(0, 1.14, -0.01), Vector3(0.135, 0.12, 0.085))
			for k in 11:                                   # coils of gut
				var p := Vector3(_rng.randf_range(-0.09, 0.09), _rng.randf_range(1.07, 1.22), _rng.randf_range(0.0, 0.085))
				_part(holder, _gut_mesh(), _mat("gut"), p, Vector3.ONE * _rng.randf_range(1.0, 1.5), Vector3(_rng.randf() * PI, _rng.randf() * PI, _rng.randf() * PI))
			_part(holder, _box_mesh(), _mat("bone"), Vector3(0, 1.15, -0.085), Vector3(0.035, 0.2, 0.03))
		&"head":
			_part(holder, _blob_mesh(), _mat("brain"), Vector3(0, 1.755, -0.005), Vector3(0.062, 0.07, 0.078))
			_part(holder, _blob_mesh(), _mat("meat"), Vector3(0, 1.67, 0.0), Vector3(0.055, 0.045, 0.07))
			for k in 5:                                    # splinters of skull round the edge
				var ang := _rng.randf() * TAU
				_part(holder, _box_mesh(), _mat("bone"), Vector3(cos(ang) * 0.06, _rng.randf_range(1.72, 1.82), sin(ang) * 0.075), Vector3(0.03, 0.022, 0.006), Vector3(_rng.randf() * PI, ang, 0))
	_innards[region] = holder


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = 2
	mi.transform = Transform3D(Basis.from_euler(rot).scaled(size), pos)
	parent.add_child(mi)


# Shared meshes and materials for every clown's insides.
static var _cache := {}

static func _mat(kind: String) -> StandardMaterial3D:
	if not _cache.has(kind):
		var m := StandardMaterial3D.new()
		match kind:
			"bone":
				m.albedo_color = Color(0.74, 0.66, 0.54)
				m.roughness = 0.45
			"meat":
				m.albedo_color = Color(0.27, 0.02, 0.025)
				m.roughness = 0.18
			"gut":
				m.albedo_color = Color(0.52, 0.2, 0.2)
				m.roughness = 0.14
			"brain":
				m.albedo_color = Color(0.56, 0.33, 0.33)
				m.roughness = 0.2
			"chunk":
				m.albedo_color = Color(0.3, 0.025, 0.03)
				m.roughness = 0.2
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"shard":
				m.albedo_color = Color(0.74, 0.62, 0.52)
				m.roughness = 0.4
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_cache[kind] = m
	return _cache[kind]


static func _box_mesh() -> Mesh:
	if not _cache.has("box"):
		_cache["box"] = BoxMesh.new()
	return _cache["box"]


static func _blob_mesh() -> Mesh:
	if not _cache.has("blob"):
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		sp.radial_segments = 14
		sp.rings = 8
		_cache["blob"] = sp
	return _cache["blob"]


static func _gut_mesh() -> Mesh:
	if not _cache.has("gutmesh"):
		var c := CapsuleMesh.new()
		c.radius = 0.024
		c.height = 0.1
		c.radial_segments = 8
		c.rings = 3
		c.material = _mat("gut")
		_cache["gutmesh"] = c
	return _cache["gutmesh"]


## A lumpy scrap of meat (or a pale shard of skull) about 3cm across.
static func _chunk_mesh(bone_bit: bool) -> Mesh:
	var key := "chunk_bone" if bone_bit else "chunk"
	if not _cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11 if bone_bit else 5
		var pts: Array[Vector3] = []
		for i in 7:
			var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			pts.append(v * rng.randf_range(0.02, 0.036) * (Vector3(1.3, 0.35, 1.0) if bone_bit else Vector3.ONE))
		for a in pts.size():
			for b in range(a + 1, pts.size()):
				for c in range(b + 1, pts.size()):
					var n := (pts[b] - pts[a]).cross(pts[c] - pts[a]).normalized()
					# keep only faces on the outside of the lump
					var outside := true
					for o in pts.size():
						if o != a and o != b and o != c and (pts[o] - pts[a]).dot(n) > 0.0005:
							outside = false
					var tri := [pts[a], pts[b], pts[c]]
					if not outside:
						n = -n
						outside = true
						for o in pts.size():
							if o != a and o != b and o != c and (pts[o] - pts[a]).dot(n) > 0.0005:
								outside = false
						tri = [pts[a], pts[c], pts[b]]
					if outside:
						for v: Vector3 in [tri[0], tri[2], tri[1]]:
							st.set_normal(n)
							st.add_vertex(v)
		var mesh := st.commit()
		mesh.surface_set_material(0, _mat("shard" if bone_bit else "chunk"))
		_cache[key] = mesh
	return _cache[key]


func start_bleeding() -> void:
	_bleeding = true
	_bleed_time = 0.0
	set_physics_process(true)


func _process(delta: float) -> void:
	# Blood spreads through the cloth around each wound for a few seconds.
	var busy := false
	for i in _wound_age.size():
		if _wound_age[i] < 9.0:
			_wound_age[i] += delta
			var fx := _wound_fx[i]
			fx.y = 1.0 - exp(-_wound_age[i] / 3.0)
			_wound_fx[i] = fx
			busy = true
	if busy:
		_push_wounds()
	else:
		set_process(false)


func _physics_process(delta: float) -> void:
	if _impact_left > 0.0:
		_impacts(delta)
	if not _bleeding and _spurts.is_empty():
		return
	_bleed_time += delta
	# Arterial spurts: a jet from a blown-open wound, pulsing weaker each time.
	for sp: Dictionary in _spurts:
		sp.next -= delta
		var spb: PhysicalBone3D = clown.ragdoll.bones.get(sp.bone)
		if sp.left <= 0 or spb == null:
			continue
		if sp.next <= 0.0:
			sp.left -= 1
			sp.next = _rng.randf_range(0.38, 0.6)
			var from: Vector3 = spb.global_transform * sp.local
			var out: Vector3 = (spb.global_basis * sp.dir).normalized()
			var force: float = 1.2 + 0.55 * sp.left
			for k in 5 + sp.left:
				Blood.add_droplet(from, out * force * _rng.randf_range(0.7, 1.15) + Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.1, 0.5), _rng.randf_range(-0.35, 0.35)), _rng.randf_range(0.04, 0.1), clown.mechanical)
			Blood.mist(from, out, 0.5 + 0.1 * sp.left, clown.mechanical)
			if clown.mechanical and _rng.randf() < 0.5:
				MechFx.sparks(clown, from, out, 0.6)      # shorting out as the oil goes
	_spurts = _spurts.filter(func(sp: Dictionary) -> bool: return sp.left > 0)
	var space := clown.get_world_3d().direct_space_state
	# A bleeding body dragging its back down a wall leaves a smear behind it.
	if _bleed_time < 8.0 and not _wound_pos.is_empty():
		for bn: StringName in [&"Neck", &"Chest"]:
			var sb: PhysicalBone3D = clown.ragdoll.bones.get(bn)
			if sb == null:
				continue
			var back := -sb.global_basis.z
			var sq := PhysicsRayQueryParameters3D.create(sb.global_position, sb.global_position + back * 0.34, LAYER_WORLD)
			var wall := space.intersect_ray(sq)
			if wall.is_empty() or absf(wall.normal.y) > 0.4:
				_smear_last.erase(bn)
				continue
			if _smear_last.has(bn):
				var moved: Vector3 = wall.position - _smear_last[bn]
				if moved.length() < 0.1:
					continue
				Blood.spawn_decal(wall.position - moved * 0.5, wall.normal, _rng.randf_range(0.2, 0.3), "streak", moved, 1.0, clampf(moved.length() / 0.12, 1.0, 1.8), clown.mechanical)
			else:
				Blood.spawn_decal(wall.position, wall.normal, _rng.randf_range(0.3, 0.42), "impact", Vector3.ZERO, 1.0, 1.0, clown.mechanical)   # where it first hits
			_smear_last[bn] = wall.position
	var open := false
	for b: Dictionary in _bleeds:
		if b.pooled:
			continue
		var pb: PhysicalBone3D = clown.ragdoll.bones.get(b.bone)
		if pb == null:
			b.pooled = true
			continue
		open = true
		var pos: Vector3 = pb.global_transform * b.local
		var speed: float = (PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).length()
		# Drips while the body is still on its way down.
		b.drip -= delta
		if b.drip <= 0.0 and _bleed_time < 7.0:
			b.drip = _rng.randf_range(0.12, 0.4) / b.amount
			Blood.add_droplet(pos, Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.5), _rng.randf_range(-0.4, 0.4)), _rng.randf_range(0.035, 0.08), clown.mechanical)
		# Once the wound stops moving near the floor, the pool starts there.
		b.still = b.still + delta if speed < 0.3 else 0.0
		if b.still > 0.4 or clown.ragdoll.is_settled:
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.1, pos + Vector3.DOWN * 0.7, LAYER_WORLD)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit.normal.y > 0.6:
				Blood.spawn_pool(hit.position, hit.normal, (0.2 + 0.24 * b.amount) * _rng.randf_range(0.9, 1.15), clown.mechanical)
				b.pooled = true
			elif clown.ragdoll.is_settled:
				b.pooled = true
	if not open and clown.ragdoll.is_settled and _spurts.is_empty() and _impact_left <= 0.0:
		set_physics_process(false)


## The body's gib meshes, ready to spawn. A look whose gibs come without images
## (spec.share_material: the dark WitzSoldat, whose 4K maps are stored once, in
## the body) gets the body's own textured material on them.
func _gib_scene() -> Node:
	var scene := (load(clown.spec.gibs) as PackedScene).instantiate()
	if clown.spec.get("share_material", false):
		var body_mat := clown.body_material()
		for mi: MeshInstance3D in scene.find_children("Gib_*", "MeshInstance3D", false, false):
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m and m != body_mat and m.resource_name == "Material":
					mi.mesh.surface_set_material(i, body_mat)
	return scene


## A point and a direction on `bone`, now, into the body's rest space.
func _rest_of(bone: StringName, world_pos: Vector3, dir: Vector3) -> Array:
	var skel := clown.skeleton
	var idx := skel.find_bone(bone)
	var back := skel.get_bone_global_rest(idx) * clown.ragdoll.bone_pose(idx).affine_inverse()
	var p := back * (skel.global_transform.affine_inverse() * world_pos)
	var d := (back.basis * (skel.global_transform.basis.inverse() * dir)).normalized()
	return [p, d]


func _anat_region(holder: Node3D) -> bool:
	return String(holder.name).begins_with("Anatomy_")


## Tear a channel through the anatomy (8 at most; the oldest goes first).
func _add_core(a: Vector3, b: Vector3, radius: float) -> void:
	_cores.append([Vector4(a.x, a.y, a.z, radius), Vector4(b.x, b.y, b.z, _rng.randf() * 50.0)])
	if _cores.size() > 8:
		_cores.pop_front()
	_push_wounds()


func _push_wounds() -> void:
	var pos := _wound_pos.duplicate()
	var fx := _wound_fx.duplicate()
	while pos.size() < MAX_WOUNDS:
		pos.append(Vector4.ZERO)
		fx.append(Vector4.ZERO)
	for sm in _materials + _anat_mats:
		sm.set_shader_parameter("wound_count", _wound_pos.size())
		sm.set_shader_parameter("wounds", pos)
		sm.set_shader_parameter("wound_fx", fx)
	if _anat_mats.is_empty():
		return
	var ca: Array[Vector4] = []
	var cb: Array[Vector4] = []
	for c: Array in _cores:
		ca.append(c[0])
		cb.append(c[1])
	while ca.size() < 8:
		ca.append(Vector4.ZERO)
		cb.append(Vector4.ZERO)
	for sm in _anat_mats:
		sm.set_shader_parameter("core_count", _cores.size())
		sm.set_shader_parameter("core_a", ca)
		sm.set_shader_parameter("core_b", cb)


# --- dismemberment ------------------------------------------------------------
# --- explosions --------------------------------------------------------------------
var _impact_left := 0.0
var _impact_clock := 0.0
var _impact_next := {}


## For the next `seconds`, a body part that slams into a wall or the floor
## at speed bursts blood across it.
func watch_impacts(seconds: float) -> void:
	_impact_left = maxf(_impact_left, seconds)
	set_physics_process(true)


func _impacts(delta: float) -> void:
	_impact_left -= delta
	_impact_clock += delta
	if not clown.ragdoll.active:
		return
	var space := clown.get_world_3d().direct_space_state
	for bn: StringName in [&"Chest", &"Hips", &"Neck", &"Spine", &"LeftUpperLeg", &"RightUpperLeg"]:
		var pb: PhysicalBone3D = clown.ragdoll.bones.get(bn)
		if pb == null or _impact_clock < float(_impact_next.get(bn, 0.0)):
			continue
		var v: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var sp := v.length()
		if sp < 3.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(pb.global_position, pb.global_position + v / sp * (0.28 + sp * delta * 2.0), LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		_impact_next[bn] = _impact_clock + 0.18
		var n: Vector3 = hit.normal
		var slide := v - n * v.dot(n)
		var size := clampf(0.4 + sp * 0.05, 0.45, 1.1)
		Blood.spawn_decal(hit.position, n, size, "impact", Vector3.ZERO, 1.0, 1.0, clown.mechanical)
		if slide.length() > 0.5:
			Blood.spawn_decal(hit.position + slide.normalized() * size * 0.5, n, size * 0.8, "streak", slide, 1.0, 1.6, clown.mechanical)
		Blood.spawn_hit(hit.position + n * 0.05, (n + slide.normalized() * 0.5).normalized(), clampf(sp / 6.0, 0.6, 1.8), clown.mechanical)


## Torn in half at the waist: the pelvis and each leg piece come away as
## separate gibs, like any other blown-off part, and the torso is left open at
## the bottom with its guts hanging out. `impulse` is the blast's push (m/s).
func cut_waist(impulse: Vector3) -> void:
	var parts: Array[StringName] = [&"Pelvis", &"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]
	var skel := clown.skeleton
	var gib_scene := _gib_scene()
	var xfs := {}
	var away := impulse.normalized() if impulse.length() > 0.01 else Vector3.UP
	var speed := impulse.length()
	var spawned: Array = []
	for s: StringName in parts:
		var bone_name: StringName = SEGMENT_BONE.get(s, s)
		var bi := skel.find_bone(bone_name)
		var src := gib_scene.get_node("Gib_" + String(s)) as MeshInstance3D
		var xf := skel.global_transform * clown.ragdoll.bone_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse() * Transform3D(Basis.IDENTITY, src.position)
		xfs[s] = xf
		var gib := Gib.new()
		gib.setup(src.mesh, _shape_for(bone_name, src.position), _mass_for(bone_name))
		gib.add_to_group(&"blast_movable")
		_mech_gib(gib, s)
		clown.get_parent().add_child(gib)
		gib.global_transform = xf
		part_severed.emit(s, gib)
		# thrown with the blast, each piece its own way, tumbling but not spinning wildly
		var scatter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.0), _rng.randf_range(-1, 1)) * speed * 0.3
		gib.linear_velocity = away * speed * _rng.randf_range(0.5, 0.9) + scatter
		gib.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _rng.randf_range(2.0, 6.0)
		spawned.append(gib)
	gib_scene.free()
	_no_self_collide(spawned)
	for s: StringName in parts:
		hidden_mask |= 1 << SEGMENTS.find(s)
		cap_mask |= 1 << SEGMENTS.find(s)
	for sm in _materials:
		sm.set_shader_parameter("hidden_mask", hidden_mask)
		sm.set_shader_parameter("cap_hide_mask", cap_mask)
	var legs: Array = [&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]
	clown.ragdoll.remove_bones(legs)
	# The hip bone stays (the ragdoll hangs off it) but shrinks to a stub of
	# meat at the bottom of the torso.
	var hips: PhysicalBone3D = clown.ragdoll.bones.get(&"Hips")
	if hips:
		for ch in hips.get_children():
			if ch is CollisionShape3D:
				var sp := SphereShape3D.new()
				sp.radius = 0.09
				ch.shape = sp
		hips.mass = 2.0
	# Everything that was inside spills: guts, blood, chunks both ways.
	var cut: Vector3 = xfs[&"Pelvis"].origin
	_show_innards(&"belly")
	if clown.mechanical:
		_mech_tear(&"belly", 1.0)
		for k in 3:
			MechFx.sparks(clown, cut, Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1), _rng.randf_range(-1, 1)), 1.6)
		MechFx.sound(clown, "failure", cut, 0.0)
	_add_wound_entry(&"Spine", cut + Vector3.UP * 0.12, 0.13, 0.06, 0.11)
	for i in 4:
		Blood.spawn_hit(cut, (impulse.normalized() + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0, 1), _rng.randf_range(-1, 1))).normalized(), 1.8, clown.mechanical)
	_throw_chunks(cut, impulse.normalized(), 7, false)
	set_process(true)


## Add a heavy, lasting bleed at a point on a bone (the open end of a torso).
func add_bleed(bone: StringName, world_pos: Vector3, amount: float) -> void:
	var pb: PhysicalBone3D = clown.ragdoll.bones.get(bone)
	if pb:
		_bleeds.append({bone = bone, local = pb.global_transform.affine_inverse() * world_pos, amount = amount, still = 0.0, pooled = false, drip = 0.0})


## A smashed knee: the end of the thigh bone through the skin at the front,
## the splintered top of the shin beside it, raw meat round both, and a hole
## that keeps bleeding.
func show_broken_knee(side: String) -> void:
	if clown.mechanical:
		_mech_broken_knee(side)
		return
	var skel := clown.skeleton
	var s := 1.0 if side == "Left" else -1.0
	var knee: Vector3 = skel.get_bone_global_rest(skel.find_bone(side + "LowerLeg")).origin
	for pair: Array in [[side + "UpperLeg", true], [side + "LowerLeg", false]]:
		var att := BoneAttachment3D.new()
		att.bone_name = pair[0]
		skel.add_child(att)
		var holder := Node3D.new()
		att.add_child(holder)
		holder.transform = skel.get_bone_global_rest(skel.find_bone(pair[0])).affine_inverse()
		if _anatomy_bones():
			_broken_knee_bones(holder, side, s, knee, pair[1])
		elif pair[1]:
			# femur end: driven forward and down out through the front of the knee
			var p0 := knee + Vector3(s * 0.01, 0.07, -0.01)
			var p1 := knee + Vector3(s * 0.025, -0.045, 0.17)
			_part_between(holder, _mat("bone"), p0, p1, 0.036)
			_part(holder, _blob_mesh(), _mat("bone"), p1, Vector3(0.03, 0.026, 0.03))           # the knuckle of it
			for k in 3:
				var q := p1 + Vector3(_rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.02, 0.02), _rng.randf_range(0.0, 0.02))
				_part_between(holder, _mat("bone"), q, q + Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(-0.04, 0.02), _rng.randf_range(0.02, 0.05)), 0.008)
			_part(holder, _blob_mesh(), _mat("meat"), knee + Vector3(s * 0.015, 0.0, 0.085), Vector3(0.05, 0.05, 0.04))
			_part(holder, _blob_mesh(), _mat("meat"), p1 + Vector3(0, 0.01, -0.03), Vector3(0.03, 0.03, 0.03))
		else:
			# shin top: snapped, splintered, out through the side
			var p0 := knee + Vector3(s * 0.03, -0.1, 0.0)
			var p1 := knee + Vector3(s * 0.14, -0.02, 0.07)
			_part_between(holder, _mat("bone"), p0, p1, 0.028)
			for k in 2:
				_part_between(holder, _mat("bone"), p1, p1 + Vector3(s * _rng.randf_range(0.01, 0.04), _rng.randf_range(-0.02, 0.04), _rng.randf_range(-0.02, 0.03)), 0.007)
			_part(holder, _blob_mesh(), _mat("meat"), knee + Vector3(s * 0.07, -0.06, 0.03), Vector3(0.045, 0.05, 0.04))

	# the skin torn open round it, and blood that keeps coming
	var bi := skel.find_bone(side + "LowerLeg")
	var world := skel.global_transform * clown.ragdoll.bone_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	var front := world * (knee + Vector3(s * 0.02, 0.0, 0.06))
	_add_wound_entry(StringName(side + "LowerLeg"), front, 0.075, 0.03, 0.035)
	_add_wound_entry(StringName(side + "LowerLeg"), world * (knee + Vector3(s * 0.065, -0.05, 0.02)), 0.05, 0.02, 0.02)
	add_bleed(StringName(side + "LowerLeg"), front, 1.3)
	Blood.spawn_hit(front, (world.basis * Vector3(0, 0.3, 1)).normalized(), 1.6, clown.mechanical)
	set_process(true)
	set_physics_process(true)
	_bleeding = true


## The knee's real bones, out of place: the end of the femur driven forward
## out through the front, the condyles first; the shin snapped below its top,
## the splintered end out through the side. Raw meat round both.
func _broken_knee_bones(holder: Node3D, side: String, s: float, knee: Vector3, femur: bool) -> void:
	var mats := ClownAnatomy.exposed_materials()
	if femur:
		var length := _bone_length(side, "Femur")
		var joint := knee + Vector3(s * 0.02, -0.015, 0.11)
		var mi := ClownAnatomy.piece_node(side + "Femur_Dist", joint, knee + Vector3(s * 0.005, 0.35, -0.04), length, 0.06, mats)
		if mi:
			holder.add_child(mi)
		_part(holder, _chunk_mesh(false), ClownAnatomy.exposed("muscle"), knee + Vector3(s * 0.015, 0.0, 0.075), Vector3(0.05, 0.05, 0.04) * 33.0)
	else:
		var length := _bone_length(side, "Shin")
		var info := ClownAnatomy.piece(side + "Shin_Prox")
		var p1 := knee + Vector3(s * 0.12, -0.04, 0.06)
		var from := knee + Vector3(s * 0.01, -0.03, 0.0)
		var dir := (p1 - from).normalized()
		var reach: float = info.get("kept", 0.1) * length / maxf(info.get("length", 0.38), 0.01)
		var mi := ClownAnatomy.piece_node(side + "Shin_Prox", p1 - dir * reach, p1, length, 0.05, mats)
		if mi:
			holder.add_child(mi)
		_part(holder, _chunk_mesh(false), ClownAnatomy.exposed("muscle"), knee + Vector3(s * 0.07, -0.06, 0.03), Vector3(0.045, 0.05, 0.04) * 33.0)


## A length of bone running from `a` to `b` (rest space of the holder).
func _part_between(parent: Node3D, mat: Material, a: Vector3, b: Vector3, thick: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh()
	mi.material_override = mat
	mi.layers = 2
	var y := (b - a)
	var len := y.length()
	y = y.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x * thick, y * len, z * thick * 0.85), (a + b) * 0.5)
	parent.add_child(mi)


func segment_of(bone: StringName) -> StringName:
	return &"Head" if bone == &"Neck" else bone


func can_sever(bone: StringName) -> bool:
	var seg := segment_of(bone)
	if seg in [&"Hips", &"Spine", &"Chest"]:
		return false
	return (hidden_mask >> SEGMENTS.find(seg)) & 1 == 0


## Blow off the limb that `bone` belongs to, along with everything below it.
func sever(bone: StringName, impulse: Vector3) -> void:
	var seg := String(segment_of(bone))
	var parts: Array[StringName] = []
	if seg == "Head":
		parts = [&"Head"]
	else:
		var side := "Left" if seg.begins_with("Left") else "Right"
		for p: String in CHAIN[seg.trim_prefix(side)]:
			parts.append(StringName(side + p))
	var skel := clown.skeleton
	var gib_scene := _gib_scene()
	var removed: Array = []
	var spawned: Array = []
	var stump_pos := Vector3.ZERO
	for i in parts.size():
		var s := parts[i]
		var id := SEGMENTS.find(s)
		if i > 0:
			cap_mask |= 1 << id              # only the top of the cut gets a stump face
		if (hidden_mask >> id) & 1 == 1:
			continue
		hidden_mask |= 1 << id
		var bone_name: StringName = SEGMENT_BONE.get(s, s)
		var bi := skel.find_bone(bone_name)
		var src := gib_scene.get_node("Gib_" + String(s)) as MeshInstance3D
		var pb: PhysicalBone3D = clown.ragdoll.bones.get(bone_name)
		var xf := skel.global_transform * clown.ragdoll.bone_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse() * Transform3D(Basis.IDENTITY, src.position)
		if i == 0:
			stump_pos = xf.origin
		var gib := Gib.new()
		gib.setup(src.mesh, _shape_for(bone_name, src.position), _mass_for(bone_name))
		_mech_gib(gib, s)
		clown.get_parent().add_child(gib)
		gib.global_transform = xf
		if i == 0:
			_gib_bone(gib, s, src)
		part_severed.emit(s, gib)
		if pb and clown.ragdoll.active:
			gib.linear_velocity = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		gib.apply_central_impulse(impulse * (0.35 if i == 0 else 0.12) + Vector3.UP * gib.mass * _rng.randf_range(0.5, 1.6))
		gib.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * gib.mass * 0.12)
		removed.append(bone_name)
		spawned.append(gib)
	if not removed.is_empty():
		_stump_bone(parts[0], gib_scene)
	gib_scene.free()
	_no_self_collide(spawned)
	clown.ragdoll.remove_bones(removed)
	for sm in _materials:
		sm.set_shader_parameter("hidden_mask", hidden_mask)
		sm.set_shader_parameter("cap_hide_mask", cap_mask)
	if removed.is_empty():
		return
	if clown.mechanical:
		_mech_stump(parts[0], stump_pos, impulse, spawned[0] if not spawned.is_empty() else null)
	# The stump bleeds hard: a spurt now and a large pool where the body ends up.
	Blood.spawn_hit(stump_pos, impulse.normalized() if impulse.length() > 0.01 else Vector3.UP, 1.6, clown.mechanical)
	var parent_bone := _stump_parent(parts[0])
	var ppb: PhysicalBone3D = clown.ragdoll.bones.get(parent_bone)
	if ppb:
		_bleeds.append({bone = parent_bone, local = ppb.global_transform.affine_inverse() * stump_pos, amount = 1.5, still = 0.0, pooled = false, drip = 0.0})
		set_physics_process(true)


## Pieces cut from the same body start out overlapping at the joints; left to
## collide they would kick each other apart. They only hit the world.
func _no_self_collide(gibs: Array) -> void:
	for a in gibs.size():
		for b in range(a + 1, gibs.size()):
			(gibs[a] as PhysicsBody3D).add_collision_exception_with(gibs[b])


## Real bone ends at a cut (ClownAnatomy joint pieces, BodyParts3D): the end of
## the bone above poking out of the stump, the top of the bone below out of the
## severed limb. Not on clockwork bodies or with the old procedural innards.
func _anatomy_bones() -> bool:
	return not clown.mechanical and not procedural_innards and ClownAnatomy.has_fit(clown.look)


func _bone_length(side: String, piece: String) -> float:
	var skel := clown.skeleton
	var span: Array = ClownAnatomy.SPANS[piece.get_slice("_", 0)]
	var a := skel.find_bone(side + span[0])
	var b := skel.find_bone(side + span[1])
	if a < 0 or b < 0:
		return 0.3
	return skel.get_bone_global_rest(a).origin.distance_to(skel.get_bone_global_rest(b).origin)


func _limb_radius(gib_scene: Node, seg: String) -> float:
	var src := gib_scene.get_node_or_null("Gib_" + seg) as MeshInstance3D
	if src == null:
		return 0.04
	var sz := src.mesh.get_aabb().size
	var v := [sz.x, sz.y, sz.z]
	v.sort()
	return v[1] * 0.5


func _stump_bone(seg: StringName, gib_scene: Node) -> void:
	if not _anatomy_bones():
		return
	var s := String(seg)
	if s == "Head":
		_neck_stump()
		return
	var side := "Left" if s.begins_with("Left") else "Right"
	var piece: String = ClownAnatomy.STUMP_PIECE.get(s.trim_prefix(side), "")
	if piece == "":
		return
	var skel := clown.skeleton
	var parent := String(_stump_parent(seg))
	var joint: Vector3 = skel.get_bone_global_rest(skel.find_bone(s)).origin
	var top: Vector3 = skel.get_bone_global_rest(skel.find_bone(parent)).origin
	var dir := (joint - top).normalized()
	var att := BoneAttachment3D.new()
	att.bone_name = parent
	skel.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	holder.transform = skel.get_bone_global_rest(skel.find_bone(parent)).affine_inverse()
	# the joint end stands a little proud of the cap
	var mi := ClownAnatomy.piece_node(side + piece, joint + dir * 0.012, top, _bone_length(side, piece), _limb_radius(gib_scene, parent), ClownAnatomy.exposed_materials())
	if mi:
		holder.add_child(mi)


func _gib_bone(gib: Gib, seg: StringName, src: MeshInstance3D) -> void:
	if not _anatomy_bones():
		return
	var s := String(seg)
	if s == "Head":
		return
	var side := "Left" if s.begins_with("Left") else "Right"
	var piece: String = ClownAnatomy.GIB_PIECE.get(s.trim_prefix(side), "")
	if piece == "":
		return
	var skel := clown.skeleton
	var span: Array = ClownAnatomy.SPANS[piece.get_slice("_", 0)]
	var joint: Vector3 = skel.get_bone_global_rest(skel.find_bone(side + span[0])).origin
	var below: Vector3 = skel.get_bone_global_rest(skel.find_bone(side + span[1])).origin
	var sz := src.mesh.get_aabb().size
	var v := [sz.x, sz.y, sz.z]
	v.sort()
	# the gib's own space is rest space less the piece's offset
	var mi := ClownAnatomy.piece_node(side + piece, joint - src.position - (below - joint).normalized() * 0.012, below - src.position,
		_bone_length(side, piece), v[1] * 0.5, ClownAnatomy.exposed_materials())
	if mi:
		gib.add_child(mi)


## The head off: the neck's vertebrae standing out of the top of the trunk.
func _neck_stump() -> void:
	var skel := clown.skeleton
	var built: Array = ClownAnatomy.build(skel, clown.look, "neck")
	if built.is_empty():
		return
	# the neck bone went with the head: the trunk carries it
	var holder: Node3D = built[0]
	(holder.get_parent() as BoneAttachment3D).bone_name = &"Chest"
	holder.transform = skel.get_bone_global_rest(skel.find_bone(&"Chest")).affine_inverse() * ClownAnatomy.fit(clown.look, "neck")
	for m: ShaderMaterial in built[1]:
		m.set_shader_parameter("show_all", true)
		m.set_shader_parameter("breaks", false)
		m.set_shader_parameter("blood_amount", 0.6)


func _stump_parent(seg: StringName) -> StringName:
	var s := String(seg)
	if s == "Head" or s.ends_with("UpperArm"):
		return &"Chest"
	if s.ends_with("UpperLeg"):
		return &"Hips"
	var side := "Left" if s.begins_with("Left") else "Right"
	var up := {"LowerArm": "UpperArm", "Hand": "LowerArm", "LowerLeg": "UpperLeg", "Foot": "LowerLeg"}
	return StringName(side + up[s.trim_prefix(side)])


func _def(bone: StringName) -> Dictionary:
	for d: Dictionary in ClownRagdoll.defs():
		if d.n == bone:
			return d
	return {}


func _mass_for(bone: StringName) -> float:
	return _def(bone).get("m", 1.0)


## Collision shape for a gib: a copy of the ragdoll bone's own shape, so it
## fits whichever body it came from.
func _shape_for(bone: StringName, gib_origin: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var pb: PhysicalBone3D = clown.ragdoll.bones.get(bone)
	var src: CollisionShape3D = null
	if pb:
		for ch in pb.get_children():
			if ch is CollisionShape3D and ch != clown._helmet_hitbox:
				src = ch
				break
	if src:
		cs.shape = src.shape
		cs.basis = src.basis
	else:
		var sp := SphereShape3D.new()
		sp.radius = 0.08
		cs.shape = sp
	cs.position = clown.ragdoll.centres.get(bone, gib_origin) - gib_origin
	return cs


# --- clockwork bodies (the Klappersoldat) -------------------------------------------
# The same wounds, holes, stumps and gibs as flesh, but what shows inside is
# machinery: brass gears, springs, pistons, a riveted housing, wires; it
# leaks machine oil and sparks instead of bleeding. Nothing here runs for a
# body that is not `mechanical`.

## Make one body surface clockwork: the uniform in field grey, stump faces in
## oily steel round a brass core, wounds soaking with oil, torn edges showing
## bare metal and frayed cloth rather than meat.
func _mech_surface(sm: ShaderMaterial, src: BaseMaterial3D) -> void:
	var kind := src.resource_name if src else ""
	if kind == "Gore":
		sm.set_shader_parameter("use_tex", false)
		sm.set_shader_parameter("albedo_color", Color(0.12, 0.115, 0.1))
		sm.set_shader_parameter("metallic", 0.75)
		sm.set_shader_parameter("roughness", 0.32)
	elif kind == "BoneCore":
		sm.set_shader_parameter("use_tex", false)
		sm.set_shader_parameter("albedo_color", Color(0.62, 0.45, 0.2))
		sm.set_shader_parameter("metallic", 0.9)
		sm.set_shader_parameter("roughness", 0.35)
	elif kind == "Scalp":
		sm.set_shader_parameter("use_tex", false)
		sm.set_shader_parameter("albedo_color", Color(0.14, 0.13, 0.12))
		sm.set_shader_parameter("metallic", 0.7)
	elif clown.spec.has("texture"):
		sm.set_shader_parameter("albedo_tex", load(clown.spec.texture))
		sm.set_shader_parameter("use_tex", true)
		sm.set_shader_parameter("albedo_color", Color.WHITE)
	sm.set_shader_parameter("blood_color", Color(0.035, 0.032, 0.026))
	sm.set_shader_parameter("hole_color", Color(0.008, 0.008, 0.007))
	sm.set_shader_parameter("meat_color", Color(0.17, 0.16, 0.14))
	sm.set_shader_parameter("inside_color", Color(0.08, 0.072, 0.06))
	if clown.spec.has("cut_min"):
		sm.set_shader_parameter("cut_min", clown.spec.cut_min)
		sm.set_shader_parameter("cut_max", clown.spec.cut_max)


## Torn into again: the first time a riveted inner panel shows through the
## cloth; the next (or one big blast) rips the panel away and the gears,
## springs and wiring behind it are open to see.
func _mech_tear(region: StringName, size: float) -> void:
	var n: int = _mech_open.get(region, 0) + 1
	_mech_open[region] = n
	if not _innards.has(region):
		return
	var holder: Node3D = _innards[region]
	if (n >= 2 or size >= 0.1) and holder.has_meta(&"panel"):
		var panel: Variant = holder.get_meta(&"panel")
		holder.remove_meta(&"panel")
		if is_instance_valid(panel):
			var at: Vector3 = (panel as Node3D).global_position
			(panel as Node3D).queue_free()
			_throw_debris(at, (at - clown.ragdoll.bones[&"Chest"].global_position if clown.ragdoll.bones.has(&"Chest") else Vector3.UP).normalized(), 3, false)
			MechFx.sound(clown, "clatter", at, -2.0)


## How far into the clockwork a region is open: 0 shut, 1 the panel, 2 the gears.
func mech_stage(region: StringName) -> int:
	if not _innards.has(region):
		return 0
	return 1 if (_innards[region] as Node3D).has_meta(&"panel") else 2


func _show_machinery(region: StringName) -> void:
	var skel := clown.skeleton
	var bone := {&"head": "Head", &"chest": "Chest", &"belly": "Spine"}[region] as String
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skel.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	holder.transform = skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse()
	var C := Clockwork
	match region:
		&"chest":
			# the housing: steel hoops where the ribs would be, round a spine of iron
			for k in 5:
				var y := 1.29 + k * 0.045
				var rx := 0.15 + 0.01 * sin(k * 0.7)
				for a in 12:
					var ang := TAU * a / 12.0
					var p := Vector3(cos(ang) * rx, y, sin(ang) * 0.1)
					C.part(holder, C.box(), C.mat("steel"), p, Vector3(0.042, 0.012, 0.01), Vector3(0, -ang + PI * 0.5, 0))
			C.part(holder, C.box(), C.mat("iron"), Vector3(0, 1.39, -0.09), Vector3(0.04, 0.27, 0.03))
			C.part(holder, C.box(), C.mat("iron"), Vector3(0, 1.39, 0.0), Vector3(0.2, 0.2, 0.16))     # the dark of the case behind
			_spin(C.gear_at(holder, Vector3(0.035, 1.405, 0.03), 0.15, Vector3.BACK, 16), Vector3.BACK, 1.3)
			_spin(C.gear_at(holder, Vector3(-0.065, 1.445, 0.045), 0.085, Vector3.BACK, 10, "steel"), Vector3.BACK, -2.4)
			_spin(C.gear_at(holder, Vector3(-0.05, 1.335, 0.04), 0.1, Vector3.BACK, 12), Vector3.BACK, -1.95)
			_spin(C.gear_at(holder, Vector3(0.075, 1.32, 0.05), 0.06, Vector3.BACK, 8, "steel"), Vector3.BACK, 3.2)
			C.part(holder, C.spring(7.0), C.mat("steel"), Vector3(0.095, 1.44, 0.02), Vector3(0.045, 0.1, 0.045))
			C.span(holder, C.mat("brass"), Vector3(0.035, 1.405, -0.05), Vector3(0.035, 1.405, 0.06), 0.012)   # axles
			C.span(holder, C.mat("brass"), Vector3(-0.05, 1.335, -0.05), Vector3(-0.05, 1.335, 0.06), 0.01)
			C.cable(holder, C.mat("wire_red"), Vector3(-0.11, 1.47, 0.03), Vector3(0.1, 1.3, 0.05), 0.03, 0.007)
			C.cable(holder, C.mat("wire_black"), Vector3(-0.1, 1.31, 0.05), Vector3(0.11, 1.46, 0.035), 0.025, 0.007)
			var panel := Node3D.new()
			holder.add_child(panel)
			C.part(panel, C.box(), C.mat("panel"), Vector3(0, 1.39, 0.085), Vector3(0.21, 0.19, 0.012))
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				C.part(panel, C.ball(), C.mat("brass"), Vector3(corner.x * 0.09, 1.39 + corner.y * 0.08, 0.093), Vector3.ONE * 0.012)
			holder.set_meta(&"panel", panel)
		&"belly":
			C.part(holder, C.box(), C.mat("iron"), Vector3(0, 1.15, -0.085), Vector3(0.036, 0.2, 0.03))
			C.part(holder, C.box(), C.mat("iron"), Vector3(0, 1.14, -0.01), Vector3(0.19, 0.16, 0.13))
			for sx: float in [-0.055, 0.055]:          # the pistons that carry the hips
				C.span(holder, C.mat("iron"), Vector3(sx, 1.06, 0.02), Vector3(sx, 1.15, 0.02), 0.03)
				C.span(holder, C.mat("steel"), Vector3(sx, 1.14, 0.02), Vector3(sx, 1.23, 0.02), 0.016)
			_spin(C.gear_at(holder, Vector3(0.0, 1.15, 0.045), 0.11, Vector3.BACK, 12), Vector3.BACK, -1.6)
			_spin(C.gear_at(holder, Vector3(0.06, 1.1, 0.04), 0.07, Vector3.BACK, 9, "steel"), Vector3.BACK, 2.5)
			C.part(holder, C.spring(5.0), C.mat("steel"), Vector3(-0.03, 1.1, 0.04), Vector3(0.06, 0.07, 0.06), Vector3(0, 0, PI * 0.5))
			C.cable(holder, C.mat("wire_black"), Vector3(-0.09, 1.2, 0.04), Vector3(0.08, 1.07, 0.05), 0.03, 0.008)
			C.cable(holder, C.mat("copper"), Vector3(0.09, 1.21, 0.03), Vector3(-0.07, 1.08, 0.05), 0.02, 0.005)
			var panel := Node3D.new()
			holder.add_child(panel)
			C.part(panel, C.box(), C.mat("panel"), Vector3(0, 1.145, 0.078), Vector3(0.19, 0.15, 0.012))
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				C.part(panel, C.ball(), C.mat("brass"), Vector3(corner.x * 0.08, 1.145 + corner.y * 0.06, 0.086), Vector3.ONE * 0.011)
			holder.set_meta(&"panel", panel)
		&"head":
			# an iron skull frame, its works, and the wiring to the eyes
			C.part(holder, C.ball(), C.mat("iron"), Vector3(0, 1.735, 0.03), Vector3(0.15, 0.15, 0.17))
			for k in 3:
				C.span(holder, C.mat("steel"), Vector3(-0.07, 1.68 + k * 0.04, 0.06), Vector3(0.07, 1.68 + k * 0.04, 0.06), 0.008)
			_spin(C.gear_at(holder, Vector3(0.03, 1.76, 0.085), 0.05, Vector3.BACK, 10), Vector3.BACK, 2.8)
			_spin(C.gear_at(holder, Vector3(-0.025, 1.725, 0.09), 0.04, Vector3.BACK, 8, "steel"), Vector3.BACK, -3.5)
			C.cable(holder, C.mat("wire_red"), Vector3(-0.05, 1.7, 0.05), Vector3(0.0, 1.65, 0.02), 0.01, 0.005)
			C.cable(holder, C.mat("wire_red"), Vector3(0.05, 1.7, 0.05), Vector3(0.0, 1.65, 0.02), 0.01, 0.005)
			C.span(holder, C.mat("steel"), Vector3(0, 1.6, 0.0), Vector3(0, 1.69, 0.02), 0.03)      # the neck post
	_innards[region] = holder


func _spin(node: Node3D, axis: Vector3, speed: float) -> void:
	spin_parts.append([node, axis, speed])


## Debris instead of meat: brass gears, springs, scraps of sheet metal, and
## (from the head) shards of the porcelain face.
func _throw_debris(pos: Vector3, dir: Vector3, count: int, porcelain: bool) -> void:
	var C := Clockwork
	for i in count:
		var mesh: Mesh
		var mat: Material
		var r := _rng.randf_range(0.018, 0.034)
		var pick := _rng.randi() % 4
		if porcelain and i < 3:
			mesh = C.shard(_rng.randi() % 6); mat = C.mat("porcelain"); r = _rng.randf_range(0.022, 0.04)
		elif pick == 0 or pick == 1:
			mesh = C.gear(8 + _rng.randi() % 8); mat = C.mat("brass" if pick == 0 else "steel")
		elif pick == 2:
			mesh = C.spring(4.0); mat = C.mat("steel")
		else:
			mesh = C.shard(10 + _rng.randi() % 6); mat = C.mat("panel")
		var g := GoreBit.make(mesh, r * 0.7, 0.08)
		g.oil = true
		(g.get_child(0) as MeshInstance3D).material_override = mat
		(g.get_child(0) as MeshInstance3D).scale = Vector3.ONE * r * 2.0
		clown.get_parent().add_child(g)
		g.global_position = pos + dir * 0.1 + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))
		g.linear_velocity = dir * _rng.randf_range(2.0, 6.0) + Vector3.UP * _rng.randf_range(0.8, 3.5) + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
		g.angular_velocity = Vector3(_rng.randf_range(-15, 15), _rng.randf_range(-15, 15), _rng.randf_range(-15, 15))


static func _cable_mesh() -> Mesh:
	if not _cache.has("cablemesh"):
		var c := CapsuleMesh.new()
		c.radius = 0.012
		c.height = 0.1
		c.radial_segments = 6
		c.rings = 2
		c.material = Clockwork.mat("wire_black")
		_cache["cablemesh"] = c
	return _cache["cablemesh"]


## A smashed knee joint: the steel thigh rod snapped and driven out through
## the front, the knee's gear cracked, wires torn loose; oil and sparks.
func _mech_broken_knee(side: String) -> void:
	var skel := clown.skeleton
	var s := 1.0 if side == "Left" else -1.0
	var knee: Vector3 = skel.get_bone_global_rest(skel.find_bone(side + "LowerLeg")).origin
	var C := Clockwork
	for pair: Array in [[side + "UpperLeg", true], [side + "LowerLeg", false]]:
		var att := BoneAttachment3D.new()
		att.bone_name = pair[0]
		skel.add_child(att)
		var holder := Node3D.new()
		att.add_child(holder)
		holder.transform = skel.get_bone_global_rest(skel.find_bone(pair[0])).affine_inverse()
		if pair[1]:
			var p0 := knee + Vector3(s * 0.01, 0.08, -0.01)
			var p1 := knee + Vector3(s * 0.025, -0.04, 0.16)
			C.span(holder, C.mat("steel"), p0, p1, 0.022)
			C.part(holder, C.shard(3), C.mat("steel"), p1, Vector3.ONE * 0.03, Vector3(0.4, 0.2, 0))
			C.cable(holder, C.mat("wire_red"), knee + Vector3(0, 0.03, 0.05), knee + Vector3(s * 0.05, -0.06, 0.12), 0.03, 0.006)
			C.cable(holder, C.mat("wire_black"), knee + Vector3(-s * 0.02, 0.02, 0.05), knee + Vector3(-s * 0.01, -0.08, 0.1), 0.02, 0.006)
		else:
			C.gear_at(holder, knee + Vector3(s * 0.08, -0.02, 0.0), 0.07, Vector3.RIGHT, 10)
			C.span(holder, C.mat("iron"), knee + Vector3(s * 0.02, -0.12, 0.0), knee + Vector3(s * 0.12, -0.03, 0.06), 0.02)
	var bi := skel.find_bone(side + "LowerLeg")
	var world := skel.global_transform * clown.ragdoll.bone_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	var front := world * (knee + Vector3(s * 0.02, 0.0, 0.06))
	_add_wound_entry(StringName(side + "LowerLeg"), front, 0.075, 0.03, 0.035)
	add_bleed(StringName(side + "LowerLeg"), front, 0.8)
	Blood.spawn_hit(front, (world.basis * Vector3(0, 0.3, 1)).normalized(), 1.0, true)
	MechFx.sparks(clown, front, (world.basis * Vector3(0, 0.3, 1)).normalized(), 1.5)
	MechFx.sound(clown, "grind", front, 0.0)
	set_process(true)
	set_physics_process(true)
	_bleeding = true


## A broken forearm: the bones snapped halfway down and a jagged end of one
## through the skin (a snapped steel rod and torn wiring on a clockwork
## body), a little meat round it, and it bleeds.
func show_broken_arm(side: String) -> void:
	var skel := clown.skeleton
	var elbow: Vector3 = skel.get_bone_global_rest(skel.find_bone(side + "LowerArm")).origin
	var wrist: Vector3 = skel.get_bone_global_rest(skel.find_bone(side + "Hand")).origin
	var along := (wrist - elbow).normalized()
	var mid := elbow.lerp(wrist, 0.45)
	var up := Vector3.UP
	var back := along.cross(up).normalized() * (1.0 if side == "Left" else -1.0)
	var att := BoneAttachment3D.new()
	att.bone_name = side + "LowerArm"
	skel.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	holder.transform = skel.get_bone_global_rest(skel.find_bone(side + "LowerArm")).affine_inverse()
	var out := (up * 0.8 + back * 0.6).normalized()
	var p0 := mid - along * 0.035
	var p1 := mid + out * 0.075 + along * 0.02
	if clown.mechanical:
		var C := Clockwork
		C.span(holder, C.mat("steel"), p0, p1, 0.016)
		C.part(holder, C.shard(2), C.mat("steel"), p1, Vector3.ONE * 0.022, Vector3(0.3, 0.5, 0))
		C.cable(holder, C.mat("wire_red"), mid, mid + out * 0.05 - along * 0.05, 0.02, 0.005)
	elif _anatomy_bones():
		# the forearm snapped midway: the top half's splintered end out through the skin
		var elbow_up := elbow - along * 0.0
		var piece := side + "Forearm_Prox"
		var info := ClownAnatomy.piece(piece)
		var length := _bone_length(side, "Forearm")
		var dir := (p1 - elbow_up).normalized()
		var reach: float = info.get("kept", 0.07) * length / maxf(info.get("length", 0.24), 0.01)
		var mi := ClownAnatomy.piece_node(piece, p1 - dir * reach, p1, length, 0.035, ClownAnatomy.exposed_materials())
		if mi:
			holder.add_child(mi)
		_part(holder, _chunk_mesh(false), ClownAnatomy.exposed("muscle"), mid + out * 0.03, Vector3(0.035, 0.03, 0.035) * 33.0)
	else:
		_part_between(holder, _mat("bone"), p0, p1, 0.02)
		for k in 3:
			var q := p1 + Vector3(_rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.01, 0.01))
			_part_between(holder, _mat("bone"), q, q + out * _rng.randf_range(0.01, 0.025) + along * _rng.randf_range(-0.015, 0.015), 0.006)
		_part(holder, _blob_mesh(), _mat("meat"), mid + out * 0.03, Vector3(0.035, 0.03, 0.035))
	var bi := skel.find_bone(side + "LowerArm")
	var world := skel.global_transform * clown.ragdoll.bone_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	var at := world * (mid + out * 0.035)
	_add_wound_entry(StringName(side + "LowerArm"), at, 0.05, 0.02, 0.02)
	add_bleed(StringName(side + "LowerArm"), at, 0.9)
	Blood.spawn_hit(at, (world.basis * out).normalized(), 1.0, clown.mechanical)
	if clown.mechanical:
		MechFx.sparks(clown, at, (world.basis * out).normalized(), 1.0)
		MechFx.sound(clown, "grind", at, -3.0)
	set_process(true)
	set_physics_process(true)
	_bleeding = true


## A gib off a clockwork body: field-grey cloth, an oily steel stump face
## round a brass core, and it drips oil.
func _mech_gib(gib: Gib, _seg: StringName) -> void:
	if not clown.mechanical:
		return
	gib.oil = true
	var mi := gib.get_child(0) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		var kind := src.resource_name if src else ""
		var m: StandardMaterial3D
		if kind == "Gore":
			m = Clockwork.mat("iron")
		elif kind == "BoneCore":
			m = Clockwork.mat("brass")
		elif clown.spec.has("texture"):
			if not _cache.has("mech_cloth"):
				var c := StandardMaterial3D.new()
				c.albedo_texture = load(clown.spec.texture)
				c.roughness = 0.85
				c.cull_mode = BaseMaterial3D.CULL_DISABLED
				_cache["mech_cloth"] = c
			m = _cache["mech_cloth"]
		else:
			continue                      # the body's own textured surface
		mi.set_surface_override_material(i, m)


## Where a limb came off a clockwork body: the stub of its rod sticking out,
## two torn wires hanging, a burst of sparks and a spray of oil.
func _mech_stump(seg: StringName, stump_pos: Vector3, impulse: Vector3, gib: Node3D) -> void:
	var skel := clown.skeleton
	var parent_bone := _stump_parent(seg)
	var bone_name: StringName = SEGMENT_BONE.get(seg, seg)
	var joint: Vector3 = skel.get_bone_global_rest(skel.find_bone(bone_name)).origin
	var parent_rest: Vector3 = skel.get_bone_global_rest(skel.find_bone(parent_bone)).origin
	var out := (joint - parent_rest).normalized()
	var att := BoneAttachment3D.new()
	att.bone_name = parent_bone
	skel.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	holder.transform = skel.get_bone_global_rest(skel.find_bone(parent_bone)).affine_inverse()
	var C := Clockwork
	C.span(holder, C.mat("steel"), joint - out * 0.04, joint + out * 0.05, 0.022)
	C.part(holder, C.shard(5), C.mat("steel"), joint + out * 0.05, Vector3.ONE * 0.028)
	var side := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	C.cable(holder, C.mat("wire_red"), joint + side * 0.015, joint + out * 0.07 + side * 0.03, 0.04, 0.006)
	C.cable(holder, C.mat("wire_black"), joint - side * 0.015, joint + out * 0.06 - side * 0.025, 0.05, 0.006)
	var away := impulse.normalized() if impulse.length() > 0.01 else Vector3.UP
	MechFx.sparks(clown, stump_pos, away, 2.0)
	MechFx.sparks(clown, stump_pos, -away + Vector3.UP, 1.2)
	MechFx.sound(clown, "spark", stump_pos, 0.0)
	MechFx.sound(clown, "clatter", stump_pos, -3.0)
	Blood.mist(stump_pos, away, 1.6, true)
	# a few more spits of sparks from the torn wires over the next second
	for k in 3:
		get_tree().create_timer(0.2 + 0.3 * k).timeout.connect(func() -> void:
			if is_instance_valid(holder) and holder.is_inside_tree():
				MechFx.sparks(clown, holder.global_transform * (joint + out * 0.05), out, 0.5))
	if gib and is_instance_valid(gib):
		MechFx.sparks(clown, gib.global_position, -away, 0.8)
