class_name Stake
extends Node3D
## A sharpened iron-tipped stake fired from the stake gun. It goes straight
## through the first clown it meets, carries the body with it, and nails it to
## whatever wall it reaches. With no wall in reach the stake stays in the body.

const SPEED := 60.0          ## m/s in flight
const CARRY_SPEED := 22.0    ## m/s once it has a body on it
const MAX_CARRY := 9.0       ## metres it will drag a body looking for a wall
const LENGTH := 0.85
const ANCHOR := 0.38         ## where along the shaft (from the tip) the body sits
const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2

var vel := Vector3.ZERO
var shot_id := 0
var _travel := 0.0
var _carried := 0.0
var _clown: Clown
var _bone: PhysicalBone3D
var _anchor: AnimatableBody3D
var _joint: PinJoint3D
var _done := false
var _exclude: Array[RID] = []
static var _mesh: Mesh


## Fire a stake from `from` along `dir`. `parent` owns the level.
static func launch(parent: Node, from: Vector3, dir: Vector3, id: int) -> Stake:
	var s := Stake.new()
	parent.add_child(s)
	s.shot_id = id
	s.global_position = from
	s.vel = dir.normalized() * SPEED
	s._face(dir)
	return s


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _stake_mesh()
	mi.layers = 1 | 2
	add_child(mi)


func _face(dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT
	look_at(global_position + dir, up)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := vel * delta
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + step + step.normalized() * 0.05, LAYER_WORLD | LAYER_RAGDOLL)
	q.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.collider
		if c is PhysicalBone3D and c.has_meta(&"clown") and _clown == null:
			_skewer(c, hit.position)
			return
		if c is PhysicalBone3D:
			# another body in the way while carrying one: shove through it
			_exclude.append(c.get_rid())
		elif c is ExplosiveBarrel:
			c.shot(hit.position, vel.normalized(), 100.0)
			queue_free()
			return
		else:
			_embed(hit.position, hit.normal)
			return
	global_position += step
	_travel += step.length()
	if _clown:
		_carried += step.length()
		if _carried > MAX_CARRY:
			_release()
			return
		# the body is dragged hard: let it move that fast
		vel += Vector3.DOWN * 4.0 * delta
	else:
		vel += Vector3.DOWN * 1.5 * delta              # a slight drop over long range
	_face(vel)
	if _travel > 70.0:
		queue_free()


## Through the body: kill it, open entry and exit wounds, and take it along.
func _skewer(pb: PhysicalBone3D, at: Vector3) -> void:
	_clown = pb.get_meta(&"clown")
	_bone = pb
	var dir := vel.normalized()
	_clown.hit({
		collider = pb, position = at, direction = dir, damage = 500.0, impulse = 2.0,
		heavy = true, can_dismember = false, shot_id = shot_id, blood = 1.8, stake = true,
	})
	if not is_instance_valid(pb) or not pb.is_inside_tree():
		queue_free()
		return
	_clown.gore.add_wound(pb.bone_name, at + dir * 0.22, 70.0)       # out the back
	Blood.spawn_hit(at + dir * 0.25, dir, 2.2, _clown.mechanical)
	Blood.spawn_hit(at, -dir, 0.8, _clown.mechanical)
	# none of this body's other parts stop the stake now
	for b: PhysicalBone3D in _clown.ragdoll.bones.values():
		_exclude.append(b.get_rid())
	# the body hangs on the shaft a little behind the tip
	global_position = at + dir * ANCHOR
	_anchor = AnimatableBody3D.new()
	_anchor.sync_to_physics = false
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.02
	cs.shape = sp
	cs.disabled = true
	_anchor.add_child(cs)
	add_child(_anchor)
	_anchor.position = Vector3(0, 0, ANCHOR)
	_joint = PinJoint3D.new()
	get_parent().add_child(_joint)
	_joint.global_position = at
	_joint.node_a = _joint.get_path_to(_anchor)
	_joint.node_b = _joint.get_path_to(pb)
	pb.tree_exiting.connect(func() -> void:
		if is_instance_valid(_joint):
			_joint.queue_free())
	_clown.ragdoll.max_bone_speed = 40.0
	vel = dir * CARRY_SPEED


## Into the wall. If it has a body on it, the body stays nailed there.
func _embed(at: Vector3, normal: Vector3) -> void:
	_done = true
	var dir := vel.normalized()
	global_position = at + dir * 0.12
	if _clown:
		Blood.spawn_decal(at, normal, randf_range(0.7, 0.95), "impact", Vector3.ZERO, 1.0, 1.0, _clown.mechanical)
		var down := (Vector3.DOWN - normal * Vector3.DOWN.dot(normal)).normalized()
		if down.length() > 0.1:
			for i in 3:
				Blood.spawn_decal(at + down * (0.2 + i * 0.22), normal, 0.32, "drip", down, 1.0, 2.0, _clown.mechanical)
		Blood.spawn_hit(at - dir * 0.1, -normal, 1.6, _clown.mechanical)
		var rd := _clown.ragdoll
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if is_instance_valid(rd):
				rd.max_bone_speed = 9.0)
	else:
		get_tree().create_timer(90.0).timeout.connect(queue_free)


## Dragged as far as it goes without finding a wall: the stake stays in the
## body and the body drops.
func _release() -> void:
	_done = true
	if is_instance_valid(_joint):
		_joint.queue_free()
	if is_instance_valid(_anchor):
		_anchor.queue_free()
	if is_instance_valid(_clown):
		_clown.ragdoll.max_bone_speed = 9.0
	if is_instance_valid(_bone):
		var xf := global_transform
		get_parent().remove_child(self)
		_bone.add_child(self)
		global_transform = xf


static func _stake_mesh() -> Mesh:
	if _mesh:
		return _mesh
	# tip at the origin, shaft running back along +Z
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://art/level/timber.png")
	wood.albedo_color = Color(0.85, 0.7, 0.55)
	wood.roughness = 0.8
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.19, 0.18)
	iron.metallic = 0.8
	iron.roughness = 0.45
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.016
	shaft.bottom_radius = 0.018
	shaft.height = LENGTH - 0.12
	shaft.radial_segments = 8
	shaft.rings = 1
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.021
	tip.height = 0.14
	tip.radial_segments = 8
	tip.rings = 1
	var band := CylinderMesh.new()
	band.top_radius = 0.021
	band.bottom_radius = 0.021
	band.height = 0.03
	band.radial_segments = 8
	band.rings = 1
	var along := Basis(Vector3.RIGHT, PI * 0.5)        # cylinder Y -> +Z
	st.append_from(shaft, 0, Transform3D(along, Vector3(0, 0, 0.12 + (LENGTH - 0.12) * 0.5)))
	st.commit(am)
	am.surface_set_material(0, wood)
	var st2 := SurfaceTool.new()
	st2.append_from(tip, 0, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.07)))
	st2.append_from(band, 0, Transform3D(along, Vector3(0, 0, 0.15)))
	st2.append_from(band, 0, Transform3D(along, Vector3(0, 0, LENGTH - 0.03)))
	st2.commit(am)
	am.surface_set_material(1, iron)
	_mesh = am
	return _mesh
