class_name ClownCar
extends EventRoom
## THE CLOWN CAR. A long garage with a tiny red car parked at the far end.
## Its door creaks open, and they keep coming out. And coming out.

const COUNT := 16
var _car: Node3D
var _left := COUNT
var _next := 1.2
var _started := false
var _door: Node3D


func build() -> void:
	title = "The Clown Car"
	concrete_room(Vector3(-3.5, 0, -12), Vector3(7, 3.6, 18))
	for z in range(-7, 6, 5):
		bulb(Vector3(0, 3.3, z), 2.0, 8.0)
	# a spotlight on the car, like a showroom
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.85, 0.7)
	sp.light_energy = 10.0
	sp.spot_range = 14.0
	sp.spot_angle = 28.0
	sp.shadow_enabled = true
	add_child(sp)
	sp.position = Vector3(0, 3.4, -5.0)
	sp.look_at(to_global(Vector3(0, 0.5, -10.0)), Vector3.UP)
	# the car: a little red body, a cab, four wheels, a door hanging open
	_car = Node3D.new()
	_car.position = Vector3(0, 0, -10)
	add_child(_car)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.06, 0.04)
	red.metallic = 0.4
	red.roughness = 0.4
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.03)
	_car_part(BoxMesh.new(), Vector3(1.6, 0.7, 2.4), Vector3(0, 0.6, 0), red)
	_car_part(BoxMesh.new(), Vector3(1.4, 0.6, 1.2), Vector3(0, 1.25, -0.2), red)
	_car_part(BoxMesh.new(), Vector3(1.42, 0.4, 1.0), Vector3(0, 1.3, -0.2), black)
	for p: Vector3 in [Vector3(-0.8, 0.3, 0.8), Vector3(0.8, 0.3, 0.8), Vector3(-0.8, 0.3, -0.8), Vector3(0.8, 0.3, -0.8)]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.3
		wheel.bottom_radius = 0.3
		wheel.height = 0.18
		var mi := _car_part(wheel, Vector3.ONE, p, black)
		mi.rotation.z = PI * 0.5
	_door = _car_part(BoxMesh.new(), Vector3(0.05, 0.6, 0.9), Vector3(0.82, 0.75, 0.3), red)
	# a horn, a flower, a big fixed grin painted on the front
	_car_part(SphereMesh.new(), Vector3(0.2, 0.2, 0.2), Vector3(0, 0.9, 1.22), _glow(Color(0.9, 0.85, 0.3)))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.5, 2.4)
	cs.shape = box
	cs.position = Vector3(0, 0.75, 0)
	body.add_child(cs)
	_car.add_child(body)
	make_exit(Vector3(0, 0, 5.88), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 4.6))


func _car_part(mesh: PrimitiveMesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is SphereMesh:
		(mesh as SphereMesh).radius = size.x * 0.5
		(mesh as SphereMesh).height = size.x
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	_car.add_child(mi)
	return mi


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	return m


func begin() -> void:
	_started = true
	var tw := create_tween()
	tw.tween_property(_door, "rotation:y", -1.6, 0.6).set_delay(0.8)


func _process(delta: float) -> void:
	if not _started or _left <= 0:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = randf_range(0.35, 0.7)
	_left -= 1
	# out of the door, a stumble, and straight for you
	var c := spawn(_car.position + Vector3(1.0, 0, 0.3), "clown", "room")
	c.rotation.y = PI * 0.5
	var b: RoomBrain = c.get_node("Brain")
	b.hunting = true
	b.run_speed = randf_range(3.8, 5.6)
	b.bounds = AABB(to_global(Vector3(-3.1, 0, -11.6)), Vector3(6.2, 4, 17.2))
	c.velocity = Vector3(3, 0, 0)


func enemy_died(c: Clown) -> void:
	if _left <= 0:
		super.enemy_died(c)
