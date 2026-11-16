class_name MessTable
extends Node3D
## A table in a side room with two or three of them sat round it: cards, a
## bottle, a lamp. They do not look up until they hear or see something, or
## one of them is hit, and even then it takes them a moment to get out of
## their chairs. Shot sitting down, they slump forward onto the table.

const SLOTS := [Vector3(-0.33, 0, 0.8), Vector3(0.33, 0, -0.8), Vector3(0.33, 0, 0.8), Vector3(-0.33, 0, -0.8)]
const NOTICE_RANGE := 5.0          ## a player in the open this close is seen
const STAND_TIME := 0.55

var player: FpsPlayer
var _seats: Array = []             # {clown, k, chair, wait, standing}
var _alerted := false
var _notice := 0.0
var _lamp: OmniLight3D


func _ready() -> void:
	_build()


## Sit a clown (already given its brain) at seat `i`.
func seat(c: Clown, i: int) -> void:
	var slot: Vector3 = SLOTS[i % SLOTS.size()]
	var at := to_global(slot)
	c.global_position = Vector3(at.x, global_position.y, at.z)
	var to_table := global_position - c.global_position
	c.rotation.y = atan2(to_table.x, to_table.z)
	c.aim_amount = 0.0
	c.velocity = Vector3.ZERO
	c.walk_amount = 0.0
	c.run_amount = 0.0
	c.extra_pose = _pose.bind(c)
	c.set_meta(&"seated", true)
	var brain := c.get_node_or_null("Brain")
	if brain:
		brain.set_physics_process.call_deferred(false)
	# the chair behind it
	var chair := RigidBody3D.new()
	chair.mass = 6.0
	chair.collision_layer = 1
	chair.collision_mask = 1 | (1 << 2) | (1 << 3)
	chair.freeze = true
	add_child(chair)
	chair.global_position = c.global_position - to_table.normalized() * 0.1 + Vector3.UP * 0.45
	chair.rotation.y = c.rotation.y
	_box(chair, Vector3(0.44, 0.05, 0.42), Vector3.ZERO, "planks_dark", true)
	_box(chair, Vector3(0.44, 0.5, 0.05), Vector3(0, 0.27, -0.2), "planks_dark", true)
	for x: float in [-0.19, 0.19]:
		for z: float in [-0.18, 0.18]:
			_box(chair, Vector3(0.04, 0.45, 0.04), Vector3(x, -0.24, z), "planks_dark", false)
	c.hurt.connect(func(_x: Clown) -> void: _alert())
	c.died.connect(_on_died)
	_seats.append({clown = c, k = 1.0, chair = chair, wait = -1.0, standing = false})


func _process(delta: float) -> void:
	_lamp.light_energy = 2.2 * (0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.021))
	if _seats.is_empty():
		return
	if not _alerted:
		for s: Dictionary in _seats:
			var c: Clown = s.clown
			if not is_instance_valid(c) or c.dead:
				continue
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b and b.mind != ClownBrain.Mind.IDLE:
				_alert()
				break
		if not _alerted and player and is_instance_valid(player) and _sees_player():
			_notice += delta
			if _notice > 0.8:
				_alert()
		else:
			_notice = maxf(_notice - delta, 0.0)
	for s: Dictionary in _seats:
		var c: Clown = s.clown
		if not is_instance_valid(c) or c.dead or s.k <= 0.0:
			continue
		# Sitting still: the brain is off, so nothing else clears what it last
		# set. Without this the legs kept walking under the table.
		c.velocity = Vector3.ZERO
		c.walk_amount = 0.0
		c.run_amount = 0.0
		if s.wait >= 0.0:
			s.wait -= delta
			if s.wait < 0.0:
				s.standing = true
				var chair: RigidBody3D = s.chair
				chair.freeze = false
				chair.apply_central_impulse((chair.global_position - global_position).normalized() * 9.0 + Vector3.UP * 4.0)
				c.remove_meta(&"seated")
		if s.standing:
			s.k = move_toward(s.k, 0.0, delta / STAND_TIME)
			# pushes the chair back and steps out from the table
			c.global_position += (c.global_position - global_position).normalized() * delta * 0.5
			if s.k <= 0.0:
				c.extra_pose = Callable()
				var b := c.get_node_or_null("Brain") as ClownBrain
				if b:
					b.set_physics_process(true)
					if player:
						b.alert(player.global_position)


func _sees_player() -> bool:
	var eye := global_position + Vector3.UP * 1.2
	var to := player.global_position + Vector3.UP * 1.4
	if eye.distance_to(to) > NOTICE_RANGE:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Something happened: they get up, each in their own time.
func _alert() -> void:
	if _alerted:
		return
	_alerted = true
	for s: Dictionary in _seats:
		if s.wait < 0.0 and not s.standing:
			s.wait = randf_range(0.6, 1.5)


func _on_died(c: Clown) -> void:
	for s: Dictionary in _seats:
		if s.clown != c:
			continue
		if s.k > 0.5:
			# dead in the chair: the chest goes forward onto the table
			c.set_meta(&"seated", true)
			_slump.call_deferred(c)
		s.k = 0.0


func _slump(c: Clown) -> void:
	if not is_instance_valid(c) or not c.ragdoll:
		return
	c.ragdoll.let_go()
	var fwd := (global_position - c.global_position)
	fwd.y = 0.0
	fwd = fwd.normalized()
	for n: StringName in [&"Spine", &"Chest", &"Neck"]:
		var pb: PhysicalBone3D = c.ragdoll.bones.get(n)
		if pb:
			pb.linear_velocity += fwd * randf_range(1.4, 2.2) + Vector3.DOWN * 0.4


## The sitting pose, laid over the living one, scaled by how seated it is.
func _pose(c: Clown) -> void:
	var k := 0.0
	for s: Dictionary in _seats:
		if s.clown == c:
			k = s.k
	if k <= 0.001:
		return
	k = k * k * (3.0 - 2.0 * k)
	c._model.position.y -= 0.47 * k
	for side: String in ["Left", "Right"]:
		c._turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-88.0) * k)
		c._turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(88.0) * k)
	c._turn("Spine", Vector3.RIGHT, deg_to_rad(12.0) * k)
	c._turn("Neck", Vector3.RIGHT, deg_to_rad(20.0) * k)
	if c.has_rifle or k < 0.5:
		return
	# elbows on the table, hands in front of it
	var sk := c.skeleton
	var to_skel := sk.global_transform.affine_inverse()
	var top := to_skel * (global_position + Vector3.UP * 0.8)
	for sd: float in [1.0, -1.0]:
		var side := "Left" if sd > 0.0 else "Right"
		var shoulder := sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
		c.reach(side, Vector3(sd * 0.16, top.y, 0.4), shoulder + Vector3(sd * 0.4, -0.4, -0.2))


func _build() -> void:
	# the table: a slab on four legs, one collider
	var top := 0.76
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.3, 0.06, 0.82)
	cs.shape = bs
	cs.position = Vector3(0, top - 0.03, 0)
	body.add_child(cs)
	add_child(body)
	_box(self, Vector3(1.3, 0.06, 0.82), Vector3(0, top - 0.03, 0), "planks_dark", false)
	for x: float in [-0.58, 0.58]:
		for z: float in [-0.34, 0.34]:
			_box(self, Vector3(0.06, top - 0.06, 0.06), Vector3(x, (top - 0.06) * 0.5, z), "planks_dark", false)
	# a hand of cards each, a pile in the middle, a bottle, mugs
	var card := StandardMaterial3D.new()
	card.albedo_color = Color(0.86, 0.82, 0.72)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.5, 0.06, 0.05)
	for i in 7:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.06, 0.004, 0.09)
		m.mesh = b
		m.material_override = card if i % 3 else red
		m.position = Vector3(randf_range(-0.4, 0.4), top + 0.003 + i * 0.001, randf_range(-0.25, 0.25))
		m.rotation.y = randf() * TAU
		add_child(m)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.15, 0.3, 0.12, 0.7)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var bottle := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.04
	cm.height = 0.28
	bottle.mesh = cm
	bottle.material_override = glass
	bottle.position = Vector3(0.12, top + 0.14, 0.05)
	add_child(bottle)
	for x: float in [-0.45, 0.4]:
		var mug := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.04
		mm.bottom_radius = 0.035
		mm.height = 0.09
		mug.mesh = mm
		mug.material_override = LevelArt._mat("iron")
		mug.position = Vector3(x, top + 0.045, randf_range(-0.2, 0.2))
		add_child(mug)
	# a hurricane lamp hanging over it
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.7, 0.4)
	_lamp.light_energy = 2.2
	_lamp.omni_range = 4.5
	_lamp.shadow_enabled = true
	_lamp.position = Vector3(0, 1.75, 0)
	add_child(_lamp)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	bulb.mesh = sm
	bulb.material_override = LevelArt._mat("bulb_hot")
	bulb.position = _lamp.position + Vector3.UP * 0.05
	add_child(bulb)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat_key: String, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = LevelArt._mat(mat_key)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		parent.add_child(cs)
