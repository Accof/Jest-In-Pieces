class_name FarFigures
extends Node3D
## A few soldiers far off on the skyline, walking in a file from one point to
## another, then gone for a while before the next party crosses. Dark shapes
## only: helmets, packs, a rifle slung. Not in the fight, no collision.

var art: TrenchArt
var from: Vector3
var to: Vector3
var rng := RandomNumberGenerator.new()
var _men: Array[Node3D] = []
var _t := 0.0
var _wait := 0.0
var _speed := 1.25
var _len := 1.0


func setup(a: TrenchArt, p0: Vector3, p1: Vector3, count: int, mat: Material, seed_: int) -> void:
	art = a
	from = p0
	to = p1
	rng.seed = seed_
	_len = from.distance_to(to)
	for i in count:
		var m := _man(mat)
		add_child(m)
		_men.append(m)
	_t = rng.randf_range(0.0, _len)          # some already on their way
	_place()


func _man(mat: Material) -> Node3D:
	var root := Node3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.24
	body.height = 1.45
	body.radial_segments = 6
	body.rings = 2
	var helmet := CylinderMesh.new()
	helmet.top_radius = 0.06
	helmet.bottom_radius = 0.24
	helmet.height = 0.14
	helmet.radial_segments = 8
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	head.radial_segments = 6
	head.rings = 3
	var pack := BoxMesh.new()
	pack.size = Vector3(0.36, 0.4, 0.2)
	var rifle := BoxMesh.new()
	rifle.size = Vector3(0.04, 1.2, 0.05)
	for part: Array in [[body, Vector3(0, 0.78, 0), Basis()], [head, Vector3(0, 1.58, 0), Basis()],
			[helmet, Vector3(0, 1.66, 0), Basis()], [pack, Vector3(0, 1.1, -0.22), Basis()],
			[rifle, Vector3(0.12, 1.2, -0.12), Basis(Vector3.FORWARD, 0.35)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position = part[1]
		mi.basis = part[2]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			visible = true
			_t = 0.0
			if rng.randf() < 0.5:
				var tmp := from
				from = to
				to = tmp
		return
	_t += _speed * delta
	if _t > _len + 6.0:
		visible = false
		_wait = rng.randf_range(40.0, 120.0)
		return
	_place()


func _place() -> void:
	var dir := (to - from).normalized()
	for i in _men.size():
		var d := clampf(_t - i * 2.2, 0.0, _len)
		var p := from + dir * d
		var bob := absf(sin((_t - i * 2.2) * 3.4)) * 0.05
		p.y = art.height_at(p.x, p.z) + bob - 0.05
		_men[i].global_position = p
		_men[i].look_at(p + dir, Vector3.UP)
		_men[i].visible = _t - i * 2.2 > 0.0 and _t - i * 2.2 < _len
