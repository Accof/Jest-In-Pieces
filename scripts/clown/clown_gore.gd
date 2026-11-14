class_name ClownGore
extends Node
## Wounds on the body, bleeding and pooling, and limb loss.

const BODY_SHADER := preload("res://shaders/clown_body.gdshader")
const GIBS := preload("res://art/clown/clown_gibs.glb")
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

var clown: Clown
var hidden_mask := 0

var _materials: Array[ShaderMaterial] = []
var _wound_pos: Array[Vector4] = []
var _wound_fx: Array[Vector4] = []
var _wound_age: Array[float] = []
var _bleeds: Array = []         # {bone, local, amount, still, pooled, drip}
var _spurts: Array = []         # {bone, local, dir, left, next}
var _innards := {}              # region -> Node3D of exposed insides, shown once blown open
var _gutted := false
var _bleeding := false
var _bleed_time := 0.0
var _rng := RandomNumberGenerator.new()


func setup(c: Clown) -> void:
	clown = c
	_rng.randomize()
	var m := clown.mesh.mesh
	for i in m.get_surface_count():
		var src := m.surface_get_material(i) as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = BODY_SHADER
		if src:
			sm.set_shader_parameter("albedo_color", src.albedo_color)
			sm.set_shader_parameter("roughness", src.roughness)
			sm.set_shader_parameter("metallic", src.metallic)
			if src.albedo_texture:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("use_tex", true)
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


# --- shotgun damage -------------------------------------------------------------
## A close shotgun blast: bites a ragged hole out of the body at `world_pos`,
## showing what is inside, and throws meat out the far side.
## `size` is the hole radius in metres. `dir` is the way the shot was travelling.
func blast(bone: StringName, world_pos: Vector3, dir: Vector3, size: float) -> void:
	var region := &"head" if bone == &"Neck" else (&"chest" if bone == &"Chest" else &"belly")
	_show_innards(region)
	_add_wound_entry(bone, world_pos, size * 1.15, size * 0.45, size)
	if region != &"head":
		# The shot carries on through: a second, smaller hole out the back.
		_add_wound_entry(bone, world_pos + dir * 0.2, size * 0.9, size * 0.2, size * 0.7)
	set_process(true)
	Blood.spawn_hit(world_pos, dir, 1.8)
	Blood.spawn_hit(world_pos, -dir, 0.9)
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
func _hang_guts(pb: PhysicalBone3D, world_pos: Vector3, out: Vector3) -> void:
	var prev: PhysicsBody3D = pb
	var at := world_pos + out * 0.04
	var mesh := _gut_mesh()
	for i in 6:
		var link := GoreBit.make(mesh, 0.024, 0.08, 0.1)
		link.marks = i == 5
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


func _show_innards(region: StringName) -> void:
	if _innards.has(region):
		return
	var skel := clown.skeleton
	var bone := {&"head": "Head", &"chest": "Chest", &"belly": "Spine"}[region] as String
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skel.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	# Parts are laid out in skeleton space, then carried by the bone.
	holder.transform = skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse()
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
				Blood.add_droplet(from, out * force * _rng.randf_range(0.7, 1.15) + Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.1, 0.5), _rng.randf_range(-0.35, 0.35)), _rng.randf_range(0.04, 0.1))
			Blood.mist(from, out, 0.5 + 0.1 * sp.left)
	_spurts = _spurts.filter(func(sp: Dictionary) -> bool: return sp.left > 0)
	var space := clown.get_world_3d().direct_space_state
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
			Blood.add_droplet(pos, Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.5), _rng.randf_range(-0.4, 0.4)), _rng.randf_range(0.035, 0.08))
		# Once the wound stops moving near the floor, the pool starts there.
		b.still = b.still + delta if speed < 0.3 else 0.0
		if b.still > 0.4 or clown.ragdoll.is_settled:
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.1, pos + Vector3.DOWN * 0.7, LAYER_WORLD)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit.normal.y > 0.6:
				Blood.spawn_pool(hit.position, hit.normal, (0.2 + 0.24 * b.amount) * _rng.randf_range(0.9, 1.15))
				b.pooled = true
			elif clown.ragdoll.is_settled:
				b.pooled = true
	if not open and clown.ragdoll.is_settled and _spurts.is_empty():
		set_physics_process(false)


func _push_wounds() -> void:
	var pos := _wound_pos.duplicate()
	var fx := _wound_fx.duplicate()
	while pos.size() < MAX_WOUNDS:
		pos.append(Vector4.ZERO)
		fx.append(Vector4.ZERO)
	for sm in _materials:
		sm.set_shader_parameter("wound_count", _wound_pos.size())
		sm.set_shader_parameter("wounds", pos)
		sm.set_shader_parameter("wound_fx", fx)


# --- dismemberment ------------------------------------------------------------
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
	var gib_scene := GIBS.instantiate()
	var removed: Array = []
	var stump_pos := Vector3.ZERO
	for i in parts.size():
		var s := parts[i]
		var id := SEGMENTS.find(s)
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
		clown.get_parent().add_child(gib)
		gib.global_transform = xf
		if pb and clown.ragdoll.active:
			gib.linear_velocity = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		gib.apply_central_impulse(impulse * (0.35 if i == 0 else 0.12) + Vector3.UP * gib.mass * _rng.randf_range(0.5, 1.6))
		gib.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * gib.mass * 0.12)
		removed.append(bone_name)
	gib_scene.free()
	clown.ragdoll.remove_bones(removed)
	for sm in _materials:
		sm.set_shader_parameter("hidden_mask", hidden_mask)
	if removed.is_empty():
		return
	# The stump bleeds hard: a spurt now and a large pool where the body ends up.
	Blood.spawn_hit(stump_pos, impulse.normalized() if impulse.length() > 0.01 else Vector3.UP, 1.6)
	var parent_bone := _stump_parent(parts[0])
	var ppb: PhysicalBone3D = clown.ragdoll.bones.get(parent_bone)
	if ppb:
		_bleeds.append({bone = parent_bone, local = ppb.global_transform.affine_inverse() * stump_pos, amount = 1.5, still = 0.0, pooled = false, drip = 0.0})
		set_physics_process(true)


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


## Collision shape for a gib, matching the ragdoll bone it came from.
func _shape_for(bone: StringName, gib_origin: Vector3) -> CollisionShape3D:
	var d := _def(bone)
	var cs := CollisionShape3D.new()
	if d.has("box"):
		var b := BoxShape3D.new()
		b.size = d.box
		cs.shape = b
	elif d.has("sphere"):
		var sp := SphereShape3D.new()
		sp.radius = d.sphere
		cs.shape = sp
	else:
		var cp := CapsuleShape3D.new()
		cp.radius = d.cap[0]
		cp.height = d.cap[1]
		cs.shape = cp
		if d.cap[2] == "x":
			cs.rotation = Vector3(0, 0, PI * 0.5)
	cs.position = d.c - gib_origin
	return cs
