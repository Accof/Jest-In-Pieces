class_name Gib
extends RigidBody3D
## A severed body part. Tumbles, drips while it flies, then leaves a small pool.

var _pooled := false
var _still := 0.0
var _age := 0.0
var _drip := 0.0


func setup(mesh: Mesh, shape: CollisionShape3D, body_mass: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.layers = 2
	add_child(mi)
	add_child(shape)
	mass = body_mass
	collision_layer = 1 << 3
	collision_mask = 1 | (1 << 3)
	angular_damp = 1.2
	linear_damp = 0.1
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm
	continuous_cd = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _pooled:
		set_physics_process(false)
		return
	_drip -= delta
	if _drip <= 0.0 and _age < 3.0:
		_drip = randf_range(0.08, 0.2)
		Blood.add_droplet(global_position, linear_velocity * 0.4 + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5)), randf_range(0.04, 0.09))
	_still = _still + delta if linear_velocity.length() < 0.25 else 0.0
	if _still > 0.5 or _age > 8.0:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.6, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.normal.y > 0.6:
			Blood.spawn_pool(hit.position, hit.normal, randf_range(0.14, 0.24))
		_pooled = true
