class_name ExplosiveBarrel
extends StaticBody3D
## A red fuel drum. Shoot it (or blow up one next to it) and it goes up.

const HEIGHT := 0.9
const RADIUS := 0.3
## Bullet damage it takes before it goes. One shotgun blast or two pistol shots.
@export var toughness := 30.0

var _hp := 0.0
var _lit := false
var _fuse := -1.0
var _leak: Array = []         # holes spitting flame before it goes
static var _mesh: Mesh


func _ready() -> void:
	_hp = toughness
	collision_layer = 1
	collision_mask = 0
	add_to_group(&"barrels")
	var mi := MeshInstance3D.new()
	mi.mesh = _drum_mesh()
	mi.position.y = HEIGHT * 0.5
	add_child(mi)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = HEIGHT
	cs.shape = cyl
	cs.position.y = HEIGHT * 0.5
	add_child(cs)


## Called by the player's shots. A hit that does not set it off punches a hole
## that sprays burning fuel; it goes up a moment later anyway.
func shot(at: Vector3, dir: Vector3, damage: float) -> void:
	if _lit:
		return
	_hp -= damage
	if _hp <= 0.0:
		ignite(0.05)
	else:
		ignite(randf_range(0.9, 1.6))
		_leak.append(to_local(at))


## Go up after `delay` seconds (another drum's blast lights it, or a hit).
func ignite(delay: float) -> void:
	if _fuse >= 0.0 and _fuse <= delay:
		return
	_fuse = delay
	set_process(true)


func _process(delta: float) -> void:
	if _fuse < 0.0:
		set_process(false)
		return
	_fuse -= delta
	for p: Vector3 in _leak:
		# a jet of flame from the hole while it builds
		if randf() < 0.5:
			var e := Explosion._mat("fire")
			var m := MeshInstance3D.new()
			m.mesh = Explosion._quad_mesh()
			m.material_override = e
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			get_parent().add_child(m)
			m.global_position = to_global(p)
			m.scale = Vector3.ONE * randf_range(0.15, 0.3)
			var tw := m.create_tween()
			tw.tween_property(m, "global_position", m.global_position + (to_global(p) - to_global(Vector3(0, p.y, 0))).normalized() * 0.6 + Vector3.UP * 0.3, 0.25)
			tw.parallel().tween_method(func(v: float) -> void: m.set_instance_shader_parameter(&"fade", v), 1.0, 0.0, 0.25)
			tw.tween_callback(m.queue_free)
	if _fuse <= 0.0:
		_explode()


func _explode() -> void:
	if _lit:
		return
	_lit = true
	Explosion.detonate(get_parent(), global_position)
	queue_free()


static func _drum_mesh() -> Mesh:
	if _mesh:
		return _mesh
	# Built by hand so the painted band wraps the side exactly once.
	var seg := 24
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := HEIGHT * 0.5
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var n0 := Vector3(sin(a0), 0, cos(a0))
		var n1 := Vector3(sin(a1), 0, cos(a1))
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		var quad := [[n0, u0, -h], [n1, u1, h], [n1, u1, -h], [n0, u0, -h], [n0, u0, h], [n1, u1, h]]
		for v: Array in quad:
			var n: Vector3 = v[0]
			side.set_normal(n)
			side.set_uv(Vector2(v[1], 0.5 - v[2] / HEIGHT))
			side.add_vertex(n * RADIUS + Vector3.UP * v[2])
	side.generate_tangents()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://art/level/barrel_red.png")
	m.normal_enabled = true
	m.normal_texture = load("res://art/level/barrel_red_n.png")
	m.metallic = 0.35
	m.roughness = 0.55
	var mesh := side.commit()
	mesh.surface_set_material(0, m)
	var caps := SurfaceTool.new()
	caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y: float in [h, -h]:
		var up := 1.0 if y > 0.0 else -1.0
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var pts := [Vector3(0, y, 0), Vector3(sin(a1), 0, cos(a1)) * RADIUS + Vector3.UP * y, Vector3(sin(a0), 0, cos(a0)) * RADIUS + Vector3.UP * y]
			if up > 0.0:
				pts = [pts[0], pts[2], pts[1]]
			for p: Vector3 in pts:
				caps.set_normal(Vector3.UP * up)
				caps.set_uv(Vector2(p.x, p.z) + Vector2(0.5, 0.5))
				caps.add_vertex(p)
	caps.commit(mesh)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.3, 0.06, 0.04)
	cm.albedo_texture = load("res://art/level/metal.png")
	cm.metallic = 0.5
	cm.roughness = 0.5
	mesh.surface_set_material(1, cm)
	_mesh = mesh
	return _mesh
