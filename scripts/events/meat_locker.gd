class_name MeatLocker
extends EventRoom
## THE MEAT LOCKER. A cold store: rows of clowns hung on hooks from the
## ceiling rails, swinging when you push through them. Not all of them are
## dead. Get close enough and the live ones drop off their hooks.

var _hanging: Array = []           # [clown, anchor body]
var _live: Array[Clown] = []
var _woken := false


func build() -> void:
	title = "The Meat Locker"
	concrete_room(Vector3(-5, 0, -12), Vector3(10, 3.8, 17), "concrete")
	# cold light, ceiling rails, a drain in the floor
	for z: float in [-9.0, -4.0, 1.0]:
		bulb(Vector3(0, 3.5, z), 2.0, 9.0, Color(0.6, 0.75, 1.0))
	for x: float in [-2.5, 0.0, 2.5]:
		solid(Vector3(x, 3.6, -3.5), Vector3(0.08, 0.1, 16.0), "metal", false)
	make_exit(Vector3(0, 0, 4.88), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 3.8))


func begin() -> void:
	var spots: Array[Vector3] = []
	for x: float in [-2.5, 0.0, 2.5]:
		for z: float in [-10.0, -7.6, -5.2, -2.8, -0.4]:
			spots.append(Vector3(x + randf_range(-0.15, 0.15), 0, z + randf_range(-0.3, 0.3)))
	spots.shuffle()
	# four are not dead: they stand among the hanging, still as meat
	for i in spots.size():
		var p := spots[i]
		if i < 4:
			var c := spawn(p, "clown", "room")
			c.rotation.y = randf_range(-0.4, 0.4)
			c.extra_pose = _hang_pose.bind(c)
			var b: RoomBrain = c.get_node("Brain")
			b.sight_range = 0.0            # not until it is close
			b.run_speed = 5.2
			_live.append(c)
		else:
			_hang(p)


## A dead one on a hook: its ragdoll hangs from the chest by a chain.
func _hang(p: Vector3) -> void:
	var c := Clown.new()
	add_child(c)
	c.position = p + Vector3.UP * 0.35
	c.rotation.y = randf_range(-PI, PI)
	await get_tree().physics_frame
	c.make_corpse()
	var chest: PhysicalBone3D = c.ragdoll.bones.get(&"Chest")
	if chest == null:
		return
	var anchor := StaticBody3D.new()
	anchor.collision_layer = 0
	add_child(anchor)
	var hook_at := chest.global_position + Vector3.UP * 0.12
	anchor.global_position = Vector3(hook_at.x, global_position.y + 3.55, hook_at.z)
	var joint := PinJoint3D.new()
	add_child(joint)
	joint.global_position = hook_at
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(chest)
	# the chain, drawn from the rail to the hook
	var chain := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = anchor.global_position.y - hook_at.y
	chain.mesh = cm
	chain.material_override = LevelArt._mat("wire")
	add_child(chain)
	chain.global_position = (anchor.global_position + hook_at) * 0.5
	c.gore.add_wound(&"Chest", hook_at + Vector3(0, -0.05, 0.1), 40.0)
	_hanging.append([c, chain, anchor])


## A live one pretending: head down, arms hanging limp.
func _hang_pose(c: Clown) -> void:
	if _woken:
		return
	c._turn("Neck", Vector3.RIGHT, 0.7)
	c._turn("Spine", Vector3.RIGHT, 0.15)


func _process(_delta: float) -> void:
	# chains follow the bodies as they swing
	for h: Array in _hanging:
		var c: Clown = h[0]
		if not is_instance_valid(c):
			continue
		var chest: PhysicalBone3D = c.ragdoll.bones.get(&"Chest")
		if chest == null:
			continue
		var chain: MeshInstance3D = h[1]
		var top: Vector3 = (h[2] as Node3D).global_position
		var hook := chest.global_position + Vector3.UP * 0.12
		chain.global_position = (top + hook) * 0.5
		var d := hook - top
		if d.length() > 0.01:
			var y := d.normalized()
			var x := y.cross(Vector3.FORWARD).normalized() if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
			chain.global_basis = Basis(x, y, x.cross(y))
	if _woken or player == null:
		return
	for c: Clown in _live:
		if is_instance_valid(c) and (c.dead or c.global_position.distance_to(player.global_position) < 3.2 or (c.get_node("Brain") as RoomBrain).hunting):
			_wake()
			break


func _wake() -> void:
	_woken = true
	for c: Clown in _live:
		if is_instance_valid(c) and not c.dead:
			var b: RoomBrain = c.get_node("Brain")
			b.sight_range = 30.0
			b.hunting = true
