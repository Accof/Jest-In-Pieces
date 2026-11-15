class_name GalleryTarget
extends AnimatableBody3D
## A plywood cutout on a hinge at its foot. Flips up, stays a moment, drops
## back. Hit while up: it scores (double in the head) and slams down with a
## shower of splinters.

const W := 0.62
const H := 1.24
var gallery: ShootingGallery
var kind := "clown"
var state := 0                     # 0 down, 1 rising, 2 up, 3 falling
var _angle := -PI * 0.5            # 0 = upright, -PI/2 = flat behind cover
var _up_for := 1.5
var _t := 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
static var _mats := {}


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_mesh = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W, H)
	_mesh.mesh = qm
	add_child(_mesh)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W * 0.85, H * 0.95, 0.04)
	_shape.shape = box
	add_child(_shape)
	_apply()


func pop(k: String, up_for: float) -> void:
	kind = k
	_mesh.material_override = _mat(k)
	_up_for = up_for
	state = 1


func drop() -> void:
	if state != 0:
		state = 3


func _process(delta: float) -> void:
	match state:
		1:
			_angle = move_toward(_angle, 0.0, delta * 9.0)
			if _angle >= 0.0:
				state = 2
				_t = 0.0
		2:
			_t += delta
			if _t > _up_for:
				state = 3
		3:
			_angle = move_toward(_angle, -PI * 0.5, delta * 7.0)
			if _angle <= -PI * 0.5:
				state = 0
	_apply()


func _apply() -> void:
	# hinge along the bottom edge: the board stands on it or lies back flat
	var b := Basis(Vector3.RIGHT, _angle)
	var centre := b * Vector3(0, H * 0.5, 0)
	_mesh.transform = Transform3D(b, centre)
	_shape.transform = Transform3D(b, centre)


func shot(at: Vector3, dir: Vector3, _damage: float) -> void:
	if state == 0 or state == 3 or _angle < -0.6:
		return
	var local := to_local(at)
	var head := local.y > H * 0.66 * cos(_angle)
	if gallery:
		gallery.scored(kind, head)
	state = 3
	_angle -= 0.25
	# splinters and a puff of sawdust
	for i in 4:
		var g := GoreBit.make(_splinter(), 0.01, 0.02)
		g.marks = false
		get_parent().add_child(g)
		g.global_position = at
		g.linear_velocity = (dir + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 1.0), randf_range(-0.6, 0.6))) * randf_range(2.0, 4.0)
	var m := MeshInstance3D.new()
	m.mesh = Explosion._quad_mesh()
	m.material_override = Explosion._mat("smoke")
	get_parent().add_child(m)
	m.global_position = at
	m.scale = Vector3.ONE * 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * 0.6, 0.4)
	tw.parallel().tween_method(func(v: float) -> void: m.set_instance_shader_parameter(&"fade", v), 0.6, 0.0, 0.4)
	tw.tween_callback(m.queue_free)


static var _splinter_mesh: BoxMesh
static func _splinter() -> Mesh:
	if _splinter_mesh == null:
		_splinter_mesh = BoxMesh.new()
		_splinter_mesh.size = Vector3(0.012, 0.012, 0.07)
		_splinter_mesh.material = LevelArt._mat("wood")
	return _splinter_mesh


static func _mat(k: String) -> Material:
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://art/level/target_%s.png" % k)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.85
		_mats[k] = m
	return _mats[k]
