class_name LockerJoker
extends RefCounted
## The clown in the locker. It has been in there a long time: the greasepaint
## soured to a grey-green pallor, black mould blooming through the costume,
## a brown tide-mark up the legs. Not one of the circus troupe: it wears a
## court jester's three-pointed cap, its bells gone green, and it died with a
## joker card clenched in its teeth. When it falls out, the rest of its deck
## comes fluttering after it.
##
## Placeholder: the cap and cards are code-built (art/locker/*.png).

const PLUM := Color(0.3, 0.1, 0.2)
const MUSTARD := Color(0.5, 0.38, 0.13)
const BRASS := Color(0.42, 0.4, 0.22)


static func dress(c: Clown) -> void:
	for sm: ShaderMaterial in c.gore._materials:
		sm.set_shader_parameter("decay", 1.0)
		sm.set_shader_parameter("blood_color", Vector3(0.17, 0.035, 0.02))   # old blood, gone brown
	var sk := c.skeleton
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	var to_head := sk.get_bone_global_rest(sk.find_bone("Head")).affine_inverse()
	var hat := Node3D.new()
	att.add_child(hat)
	hat.transform = to_head
	_cap(hat)
	_mouth_card(hat)


## The jester's cap, built in skeleton (rest) space on top of the head.
static func _cap(hat: Node3D) -> void:
	var plum := _mat(PLUM, 0.0, 0.9)
	var mustard := _mat(MUSTARD, 0.0, 0.9)
	var brass := _mat(BRASS, 0.7, 0.45)
	var crown := Vector3(0, 1.815, -0.01)
	var dome := SphereMesh.new()
	dome.radius = 0.1
	dome.height = 0.1
	dome.is_hemisphere = true
	dome.material = plum
	_put(hat, dome, Transform3D(Basis(Vector3.RIGHT, -0.12).scaled(Vector3(1.0, 0.9, 1.08)), crown))
	var band := TorusMesh.new()
	band.inner_radius = 0.093
	band.outer_radius = 0.112
	band.material = mustard
	_put(hat, band, Transform3D(Basis(Vector3.RIGHT, -0.12).scaled(Vector3(1.0, 1.0, 1.08)), crown + Vector3(0, 0.005, 0)))
	# three floppy points: out to each side and up off the back, drooping
	var starts := [[Vector3(0.07, 0.05, 0.0), Vector3(1.0, 1.1, 0.1)], [Vector3(-0.07, 0.05, 0.0), Vector3(-1.0, 1.1, 0.1)], [Vector3(0.0, 0.07, -0.05), Vector3(0.0, 1.3, -0.8)]]
	for i in 3:
		var p: Vector3 = crown + starts[i][0]
		var d: Vector3 = (starts[i][1] as Vector3).normalized()
		var r := 0.042
		var seg := 0.07
		for k in 4:
			var cm := CylinderMesh.new()
			cm.bottom_radius = r
			cm.top_radius = r * 0.7
			cm.height = seg
			cm.radial_segments = 10
			cm.rings = 1
			cm.material = plum if (i + k) % 2 == 0 else mustard
			var mid := p + d * seg * 0.5
			_put(hat, cm, Transform3D(_along_y(d), mid))
			p += d * seg * 0.92
			r *= 0.7
			# the weight of the bell pulls the tip over and down
			d = (d + Vector3(d.x, 0, d.z).normalized() * 0.25 + Vector3.DOWN * 0.75).normalized()
		var bell := SphereMesh.new()
		bell.radius = 0.019
		bell.height = 0.036
		bell.material = brass
		_put(hat, bell, Transform3D(Basis.IDENTITY, p + d * 0.012))


## A joker card bitten between the teeth, sticking out and down.
static func _mouth_card(hat: Node3D) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(0.058, 0.082)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://art/locker/joker_card.png")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	q.material = m
	var along := Vector3(0.12, -0.55, 1.0).normalized()       # the card's length, out of the mouth
	var side := Vector3.UP.cross(along).normalized()
	var b := Basis(side, along, side.cross(along)).rotated(along, 0.25)
	_put(hat, q, Transform3D(b, Vector3(0.01, 1.655, 0.085) + along * 0.035))


static func _put(parent: Node3D, mesh: Mesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.layers = 2
	parent.add_child(mi)
	return mi


static func _along_y(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


static func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


## Its old wounds have long since soaked the costume through.
static func soak(c: Clown) -> void:
	var g := c.gore
	for k in g._wound_fx.size():
		var f: Vector4 = g._wound_fx[k]
		f.y = randf_range(0.7, 1.0)
		g._wound_fx[k] = f
	g._push_wounds()


## Falling out of the locker: stiff for a moment (it has been stood in there
## a long time), pitching forward from the ankles, then folding as it lands.
static func profile_pitch_out() -> Dictionary:
	return {
		support = [Vector2(0, 0.0)],
		legs = [Vector2(0, 0.8), Vector2(0.6, 0.6), Vector2(1.1, 0)],
		spine = [Vector2(0, 0.8), Vector2(0.6, 0.55), Vector2(1.1, 0)],
		neck = [Vector2(0, 0.2), Vector2(0.4, 0)],
		arms = [Vector2(0, 0.25), Vector2(0.4, 0)],
		drift = 0.0, drift_time = 0.1,
	}


## The rest of its deck, fluttering out after it.
static func spill_cards(c: Clown, fwd: Vector3) -> void:
	var back := StandardMaterial3D.new()
	back.albedo_texture = load("res://art/locker/card_back.png")
	back.roughness = 0.85
	var face := StandardMaterial3D.new()
	face.albedo_texture = load("res://art/locker/joker_card.png")
	face.roughness = 0.85
	var chest: PhysicalBone3D = c.ragdoll.bones.get(&"Chest")
	var from := chest.global_position if chest else c.global_position + Vector3.UP * 1.3
	var parent := c.get_parent()
	for i in 16:
		var body := RigidBody3D.new()
		body.collision_layer = 1 << 3
		body.collision_mask = 1
		body.mass = 0.02
		body.linear_damp = 3.5               # paper: it floats down rather than falls
		body.angular_damp = 1.5
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.063, 0.004, 0.088)
		cs.shape = box
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.063, 0.0015, 0.088)
		bm.material = face if i % 5 == 0 else back
		mi.mesh = bm
		mi.layers = 2
		body.add_child(mi)
		parent.add_child(body)
		body.global_position = from + Vector3(randf_range(-0.15, 0.15), randf_range(-0.3, 0.15), randf_range(-0.05, 0.1))
		body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		body.linear_velocity = fwd * randf_range(1.0, 3.0) + Vector3(randf_range(-1, 1), randf_range(0.3, 2.0), randf_range(-1, 1))
		body.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		# settle and stop simulating once they are on the floor
		body.get_tree().create_timer(6.0).timeout.connect(func() -> void:
			if is_instance_valid(body):
				body.freeze = true)
