class_name GoreBit
extends RigidBody3D
## A small piece of gore: a meat chunk, a skull fragment or a link of gut.
## Leaves a blood mark where it first lands.

const MAX_LIVE := 70
static var _live: Array = []

var marks := true
var _marked := false
var _age := 0.0


static func make(mesh: Mesh, radius: float, body_mass: float, capsule_height: float = 0.0) -> GoreBit:
	var g := GoreBit.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.layers = 2
	g.add_child(mi)
	var cs := CollisionShape3D.new()
	if capsule_height > 0.0:
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = capsule_height
		cs.shape = cap
	else:
		var sp := SphereShape3D.new()
		sp.radius = radius
		cs.shape = sp
	g.add_child(cs)
	g.mass = body_mass
	g.collision_layer = 1 << 3
	g.collision_mask = 1
	g.angular_damp = 2.0
	g.linear_damp = 0.15
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.05
	g.physics_material_override = pm
	# Keep the total bounded: the oldest bits go first.
	_live = _live.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	while _live.size() >= MAX_LIVE:
		var old: GoreBit = _live.pop_front()
		old.queue_free()
	_live.append(g)
	return g


func _physics_process(delta: float) -> void:
	_age += delta
	if not marks or _marked:
		set_physics_process(false)
		return
	if _age > 0.15 and (linear_velocity.length() < 1.0 or _age > 4.0):
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.05, global_position + Vector3.DOWN * 0.35, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			Blood.spawn_decal(hit.position, hit.normal, randf_range(0.16, 0.32), "drip")
		_marked = true
