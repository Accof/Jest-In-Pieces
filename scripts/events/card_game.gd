class_name CardGame
extends EventRoom
## THE CARD GAME. A low room, one bulb swinging over a table, a gramophone
## scratching in the corner. Clowns and WitzSoldats sit round a hand of cards.
## They have not looked up yet. Shoot first and they die in their chairs; wait,
## or get noticed, and they kick the table over and fight from behind it.

const SEATS := 5
const GRACE := 3.5                  ## seconds before someone looks up
var _table: RigidBody3D
var _chairs: Array[RigidBody3D] = []
var _seated: Array[Clown] = []
var _sit := {}                      # clown -> how far sat down (1 = in the chair)
var _flipped := false
var _bulb: OmniLight3D
var _bulb_node: Node3D
var _swing := 0.0


func build() -> void:
	title = "The Card Game"
	concrete_room(Vector3(-5, 0, -7), Vector3(10, 3.0, 11))
	# the bulb on its flex, which swings
	_bulb_node = Node3D.new()
	_bulb_node.position = Vector3(0, 3.0, -2.5)
	add_child(_bulb_node)
	_bulb = OmniLight3D.new()
	_bulb.light_color = Color(1.0, 0.72, 0.45)
	_bulb.light_energy = 3.2
	_bulb.omni_range = 9.0
	_bulb.shadow_enabled = true
	_bulb.light_volumetric_fog_energy = 2.5
	_bulb.position = Vector3(0, -0.9, 0)
	_bulb_node.add_child(_bulb)
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	glow.mesh = sm
	glow.material_override = _emissive(Color(1.0, 0.75, 0.45), 7.0)
	glow.position = Vector3(0, -0.9, 0)
	_bulb_node.add_child(glow)
	var flex := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.006
	fm.bottom_radius = 0.006
	fm.height = 0.85
	flex.mesh = fm
	flex.material_override = LevelArt._mat("wire")
	flex.position = Vector3(0, -0.43, 0)
	_bulb_node.add_child(flex)
	bulb(Vector3(-4.2, 2.4, 3.2), 0.8, 5.0)
	# the gramophone, crates, a stack of shells, a calendar girl poster
	solid(Vector3(3.8, 0.4, -6.0), Vector3(0.8, 0.8, 0.8), "planks_dark")
	var horn := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.22
	hm.bottom_radius = 0.02
	hm.height = 0.45
	horn.mesh = hm
	horn.material_override = LevelArt._mat("brass")
	horn.position = Vector3(3.8, 1.05, -5.85)
	horn.rotation = Vector3(-0.9, 0.5, 0)
	add_child(horn)
	solid(Vector3(-4.0, 0.35, -5.6), Vector3(0.7, 0.7, 0.7), "crate")
	solid(Vector3(-4.0, 1.0, -5.6), Vector3(0.55, 0.55, 0.55), "crate")
	_table = _rigid_box(Vector3(0, 0.76, -2.5), Vector3(1.6, 0.06, 1.6), "planks", 18.0)
	for p: Vector3 in [Vector3(-0.65, 0.37, -0.65), Vector3(0.65, 0.37, -0.65), Vector3(-0.65, 0.37, 0.65), Vector3(0.65, 0.37, 0.65)]:
		_box_on(_table, Vector3(0.06, 0.74, 0.06), p - Vector3(0, 0.76, 0), "wood")
	# cards, a pot of coins and bottles on the table (they go with it)
	for i in 14:
		var card := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.06, 0.003, 0.09)
		card.mesh = cm
		card.material_override = _plain(Color(0.9, 0.86, 0.78) if i % 3 else Color(0.6, 0.08, 0.06))
		card.position = Vector3(randf_range(-0.55, 0.55), 0.032, randf_range(-0.55, 0.55))
		card.rotation.y = randf() * TAU
		_table.add_child(card)
	for i in 3:
		var bottle := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.02
		bm.bottom_radius = 0.035
		bm.height = 0.28
		bottle.mesh = bm
		bottle.material_override = _plain(Color(0.12, 0.25, 0.1), 0.15)
		bottle.position = Vector3(randf_range(-0.4, 0.4), 0.17, randf_range(-0.4, 0.4))
		_table.add_child(bottle)
	var pot := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.1
	pm.bottom_radius = 0.12
	pm.height = 0.05
	pot.mesh = pm
	pot.material_override = LevelArt._mat("brass")
	pot.position = Vector3(0, 0.055, 0)
	_table.add_child(pot)
	_table.freeze = true                    # still, until it is kicked over
	make_exit(Vector3(0, 0, 3.88), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 2.9))


func begin() -> void:
	var bodies := ["witzsoldat", "clown", "witzsoldat", "clown", "clown"]
	for i in SEATS:
		var a := TAU * (i + 0.5) / SEATS + PI          # nobody has their back fully to the door
		var seat := Vector3(sin(a), 0, cos(a)) * 1.25 + Vector3(0, 0, -2.5)
		var c := spawn(seat, bodies[i], "room", bodies[i] == "clown" and i == 3)
		var to_table := Vector3(0, 0, -2.5) - seat
		c.rotation.y = atan2(to_table.x, to_table.z)
		var b: RoomBrain = c.get_node("Brain")
		b.sight_range = 0.0                             # eyes on their cards
		b.bounds = AABB(to_global(Vector3(-4.6, 0, -6.6)), Vector3(9.2, 4, 10.2))
		c.extra_pose = _seated_pose.bind(c)
		_sit[c] = 1.0
		_seated.append(c)
		var chair := _rigid_box(seat - to_table.normalized() * 0.12 + Vector3(0, 0.45, 0), Vector3(0.45, 0.05, 0.45), "planks_dark", 6.0)
		_box_on(chair, Vector3(0.45, 0.5, 0.05), Vector3(0, 0.27, 0.22), "planks_dark")
		chair.rotation.y = c.rotation.y + PI
		chair.freeze = true
		_chairs.append(chair)
		c.hurt.connect(func(_x: Clown) -> void: _react())


func _process(delta: float) -> void:
	_t += delta
	_swing += delta
	_bulb_node.rotation.z = sin(_swing * 1.3) * (0.18 if not _flipped else 0.45)
	_bulb_node.rotation.x = sin(_swing * 0.9) * 0.08
	_bulb.light_energy = 3.2 * (0.9 + 0.1 * sin(_swing * 23.0))
	if not _flipped and _t > GRACE:
		_react()
	for c: Clown in _sit:
		if is_instance_valid(c) and not c.dead and _flipped:
			_sit[c] = move_toward(_sit[c], 0.0, delta * 3.0)


## Somebody looked up (or got shot): the table goes over, the riflemen get
## down behind it, the clowns come at you.
func _react() -> void:
	if _flipped:
		return
	_flipped = true
	_table.freeze = false
	var to_door := (to_global(Vector3(0, 0, 3)) - _table.global_position).normalized()
	_table.apply_central_impulse((to_door + Vector3.UP * 1.4) * _table.mass * 3.2)
	_table.apply_torque_impulse(to_door.cross(Vector3.DOWN) * _table.mass * 1.6)
	for ch: RigidBody3D in _chairs:
		ch.freeze = false
		ch.apply_central_impulse(Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)) * ch.mass * 1.5)
	for c: Clown in _seated:
		if not is_instance_valid(c) or c.dead:
			continue
		var b: RoomBrain = c.get_node("Brain")
		b.sight_range = 30.0
		b.hunting = true
		if c.body == "witzsoldat":
			# into cover behind the table, then shoot over it
			b.mode = "rifle"
			var behind := Vector3(randf_range(-1.0, 1.0), 0, -3.8)
			b.waypoints = [to_global(behind)] as Array[Vector3]
			b.run_speed = 3.0
		else:
			b.run_speed = randf_range(3.9, 4.6)


## Sitting at the table: hips on the chair, knees bent, hands on the table.
func _seated_pose(c: Clown) -> void:
	var k: float = _sit.get(c, 0.0)
	if k <= 0.001:
		return
	c._model.position.y -= 0.47 * k
	for side: String in ["Left", "Right"]:
		c._turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-88.0) * k)
		c._turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(88.0) * k)
	c._turn("Spine", Vector3.RIGHT, deg_to_rad(10.0) * k)
	c._turn("Neck", Vector3.RIGHT, deg_to_rad(22.0) * k)            # looking at the cards
	if c.has_rifle:
		return                                                     # its hands are on the rifle
	if k > 0.5:
		var sk := c.skeleton
		var to_skel := sk.global_transform.affine_inverse()
		var table_top := to_skel * (_table.global_position + Vector3.UP * 0.05)
		for sd: float in [1.0, -1.0]:
			var side := "Left" if sd > 0.0 else "Right"
			var shoulder := sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
			var hand := Vector3(sd * 0.18, table_top.y, 0.42)
			c.reach(side, hand, shoulder + Vector3(sd * 0.4, -0.4, -0.2))


func enemy_died(c: Clown) -> void:
	_sit.erase(c)
	if enemies.all(func(e: Clown) -> bool: return not is_instance_valid(e) or e.dead):
		var quick := not _flipped or _t < GRACE + 1.0
		complete({success = true, upgrade = true, tickets = 8 + (4 if quick else 0), heal = 25.0,
			line = "THE CARD GAME\nYou took the pot%s" % ("   before they could stand" if quick else "")})


func _rigid_box(pos: Vector3, size: Vector3, mat_key: String, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = 1 << 3
	rb.collision_mask = 1 | (1 << 2) | (1 << 3)
	add_child(rb)
	rb.position = pos
	_box_on(rb, size, Vector3.ZERO, mat_key)
	return rb


func _box_on(rb: Node3D, size: Vector3, pos: Vector3, mat_key: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = LevelArt._mat(mat_key)
	mi.position = pos
	rb.add_child(mi)
	if rb is CollisionObject3D:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = pos
		rb.add_child(cs)


static func _plain(c: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m
