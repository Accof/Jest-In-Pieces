class_name Explosion
extends Node3D
## A fuel drum going up: flash, fireball, smoke, sparks, a scorch mark, and a
## shock wave that throws everything nearby. Clowns decide for themselves how
## badly they come apart (Clown.caught_in_blast).

const RADIUS := 6.5          ## metres of reach for damage and the shock wave
const PLAYER_DAMAGE := 85.0  ## at point blank; falls off with distance
const LAYER_WORLD := 1
const TEX := "res://art/level/"

var _t := 0.0
var _light: OmniLight3D
var _puffs: Array = []       # [node, vel, life, age, size0, size1, kind]
var _sparks: Array = []      # [node, vel, life]
static var _mats := {}
static var _quad: QuadMesh
static var _spark_mesh: BoxMesh


## Blow up at `pos`. `parent` is the node that owns the level.
static func detonate(parent: Node, pos: Vector3) -> Explosion:
	var e := Explosion.new()
	parent.add_child(e)
	e.global_position = pos
	e._go()
	return e


func _go() -> void:
	var tree := get_tree()
	# light: a white-hot flash fading to orange
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.light_energy = 16.0
	_light.omni_range = 14.0
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = true
	_light.light_volumetric_fog_energy = 4.0
	_light.position = Vector3.UP * 0.8
	add_child(_light)
	# fireball, then smoke that lingers
	for i in 16:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.1, 1.2), randf_range(-1, 1)).normalized()
		_puff("fire", Vector3.UP * 0.6 + dir * randf_range(0.0, 0.4), dir * randf_range(2.0, 6.5), randf_range(0.35, 0.7), randf_range(0.5, 0.9), randf_range(1.6, 2.8))
	for i in 14:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		_puff("smoke", Vector3.UP * 0.7 + dir * randf_range(0.2, 0.8), dir * randf_range(0.6, 2.2) + Vector3.UP * 0.6, randf_range(3.5, 6.0), randf_range(0.8, 1.4), randf_range(2.6, 4.2))
	for i in 40:
		var s := MeshInstance3D.new()
		s.mesh = _spark()
		s.material_override = _mat("spark")
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		s.position = Vector3.UP * 0.6
		var v := Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)).normalized() * randf_range(5.0, 15.0)
		_sparks.append([s, v, randf_range(0.4, 1.3)])
	_debris()
	_scorch()
	_shake_player()
	_hurt_player()
	# everyone in reach: clowns, other drums (chain reactions)
	for c in tree.get_nodes_in_group(&"clowns"):
		if is_instance_valid(c) and c.has_method("caught_in_blast"):
			c.caught_in_blast(global_position + Vector3.UP * 0.5, RADIUS)
	for b in tree.get_nodes_in_group(&"barrels"):
		if is_instance_valid(b) and b.global_position.distance_to(global_position) < RADIUS * 0.6:
			b.ignite(randf_range(0.12, 0.35))
	# loose bodies and gore get thrown too
	for n in tree.get_nodes_in_group(&"blast_movable"):
		if n is RigidBody3D and is_instance_valid(n):
			var to: Vector3 = n.global_position - global_position
			var s: float = clampf(1.0 - to.length() / RADIUS, 0.0, 1.0)
			if s > 0.0:
				n.apply_central_impulse((to.normalized() + Vector3.UP * 0.6) * n.mass * 12.0 * s)
	# every clown in earshot comes looking
	var game := tree.get_first_node_in_group(&"game")
	if game and game.has_method("noise_at"):
		game.noise_at(global_position, 6)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 16.0 * exp(-_t * 6.0) + 3.0 * maxf(0.0, 1.0 - _t / 1.2) * (0.8 + 0.2 * sin(_t * 40.0))
	_light.light_color = Color(1.0, lerpf(0.75, 0.45, minf(_t * 2.0, 1.0)), lerpf(0.45, 0.15, minf(_t * 2.0, 1.0)))
	if _t > 1.3 and _light.visible:
		_light.visible = false
	var alive := false
	for p: Array in _puffs:
		if not is_instance_valid(p[0]):
			continue
		var node: MeshInstance3D = p[0]
		p[3] += delta
		var k: float = p[3] / p[2]
		if k >= 1.0:
			node.queue_free()
			continue
		alive = true
		var vel: Vector3 = p[1]
		vel *= exp(-delta * (5.0 if p[6] == "fire" else 1.6))
		if p[6] == "smoke":
			vel += Vector3.UP * 0.5 * delta
		p[1] = vel
		node.position += vel * delta
		node.scale = Vector3.ONE * lerpf(p[4], p[5], 1.0 - pow(1.0 - k, 3.0))
		var a := (1.0 - k) if p[6] == "fire" else sin(k * PI) * 0.75
		node.set_instance_shader_parameter(&"fade", a)
	for s: Array in _sparks:
		if not is_instance_valid(s[0]):
			continue
		var node: MeshInstance3D = s[0]
		s[2] -= delta
		if s[2] <= 0.0:
			node.queue_free()
			continue
		alive = true
		var v: Vector3 = s[1]
		v += Vector3.DOWN * 9.8 * delta
		v *= exp(-delta * 0.8)
		s[1] = v
		node.position += v * delta
		if v.length() > 0.1:
			node.look_at(node.global_position + v, Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.RIGHT)
		node.scale = Vector3(1, 1, clampf(v.length() * 0.6, 1.0, 6.0))
	if not alive and _t > 1.5:
		queue_free()


func _puff(kind: String, at: Vector3, vel: Vector3, life: float, s0: float, s1: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _quad_mesh()
	m.material_override = _mat(kind)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.rotation.z = randf() * TAU
	add_child(m)
	m.position = at
	m.scale = Vector3.ONE * s0
	_puffs.append([m, vel, life, 0.0, s0, s1, kind])


## Torn pieces of the drum, flung out hot.
func _debris() -> void:
	for i in 7:
		var g := RigidBody3D.new()
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(randf_range(0.15, 0.4), 0.02, randf_range(0.12, 0.3))
		b.material = _mat("shard")
		mi.mesh = b
		g.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		g.add_child(cs)
		g.mass = 1.5
		g.collision_layer = 1 << 3
		g.collision_mask = 1
		get_parent().add_child(g)
		g.global_position = global_position + Vector3.UP * randf_range(0.2, 0.9)
		g.linear_velocity = Vector3(randf_range(-1, 1), randf_range(0.4, 1.5), randf_range(-1, 1)).normalized() * randf_range(5.0, 11.0)
		g.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
		get_tree().create_timer(25.0).timeout.connect(func() -> void:
			if is_instance_valid(g):
				g.queue_free())


## Burn marks on the floor, and on any wall close enough.
func _scorch() -> void:
	var space := get_world_3d().direct_space_state
	var dirs := [Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]
	for d: Vector3 in dirs:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, global_position + Vector3.UP * 0.6 + d * 3.0, LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dec := Decal.new()
		dec.texture_albedo = load(TEX + "fx_scorch.png")
		var dist: float = (hit.position - (global_position + Vector3.UP * 0.6)).length()
		var size := lerpf(3.6, 1.6, dist / 3.0)
		dec.size = Vector3(size, 0.6, size)
		dec.cull_mask = 1
		dec.albedo_mix = 0.95
		get_parent().add_child(dec)
		dec.global_position = hit.position
		var n: Vector3 = hit.normal
		var right := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		dec.global_basis = Basis(right, n, right.cross(n)).rotated(n, randf() * TAU)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


func _shake_player() -> void:
	var p := _player()
	if p and p.has_method("shake"):
		var d := p.global_position.distance_to(global_position)
		p.shake(clampf(1.4 - d / 14.0, 0.15, 1.2))


func _hurt_player() -> void:
	var p := _player()
	if p == null or not p.has_method("take_damage"):
		return
	var eye := p.global_position + Vector3.UP * 1.0
	var d := eye.distance_to(global_position + Vector3.UP * 0.5)
	if d > RADIUS:
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, eye, LAYER_WORLD)
	q.exclude = []
	var blocked := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	var s := pow(1.0 - d / RADIUS, 1.4) * (0.3 if blocked else 1.0)
	p.take_damage(PLAYER_DAMAGE * s, (eye - global_position).normalized())


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


static func _spark() -> BoxMesh:
	if _spark_mesh == null:
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3(0.018, 0.018, 0.08)
	return _spark_mesh


static func _mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"fire", "smoke":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/fx_puff.gdshader")
			sm.set_shader_parameter("tex", load(TEX + ("fx_fire.png" if kind == "fire" else "fx_smoke.png")))
			sm.set_shader_parameter("emissive", 6.0 if kind == "fire" else 0.0)
			m = sm
		"spark":
			var s := StandardMaterial3D.new()
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.albedo_color = Color(1.0, 0.75, 0.35)
			s.emission_enabled = true
			s.emission = Color(1.0, 0.6, 0.2)
			s.emission_energy_multiplier = 8.0
			m = s
		"shard":
			var s := StandardMaterial3D.new()
			s.albedo_texture = load(TEX + "barrel_red.png")
			s.metallic = 0.5
			s.roughness = 0.6
			s.albedo_color = Color(0.5, 0.45, 0.4)
			m = s
	_mats[kind] = m
	return m
