extends Node3D
## Test room for ragdolls and blood. Builds itself in code so there is nothing
## to wire up in the editor: open scenes/gore_sandbox.tscn and press play.

var player: FpsPlayer
var clowns: Array[Clown] = []
var _spawns := [Vector3(-1.6, 0, -4.0), Vector3(0.0, 0, -5.0), Vector3(1.6, 0, -4.0), Vector3(3.2, 0, -6.5), Vector3(-3.2, 0, -6.5), Vector3(-4.6, 0, -3.2)]


func _ready() -> void:
	_build_room()
	player = FpsPlayer.new()
	add_child(player)
	player.position = Vector3(0, 0.05, 1.5)
	player.reset_requested.connect(reset)
	player.flashlight.visible = false
	reset()


func reset() -> void:
	for c in clowns:
		if is_instance_valid(c):
			c.queue_free()
	clowns.clear()
	for n in get_children():
		if n is Gib or n is GoreBit or n is PinJoint3D or n is ExplosiveBarrel or n is Explosion or n is Decal or n is RigidBody3D or n is AnimatableBody3D:
			n.queue_free()
	Blood.clear()
	for p: Vector3 in _spawns:
		var c := Clown.new()
		add_child(c)
		c.position = p
		clowns.append(c)
	# fuel drums among them: shoot one
	for p: Vector3 in [Vector3(-0.8, 0, -4.7), Vector3(2.4, 0, -5.9), Vector3(-3.9, 0, -5.0)]:
		var b := ExplosiveBarrel.new()
		add_child(b)
		b.position = p


func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.33, 0.38)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssr_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.42, 0.41, 0.39)
	floor_mat.roughness = 0.85
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.5, 0.47, 0.42)
	wall_mat.roughness = 0.9
	_slab(Vector3(0, -0.25, -4), Vector3(16, 0.5, 16), floor_mat)
	_slab(Vector3(0, 2, -9.5), Vector3(16, 4, 0.5), wall_mat)
	_slab(Vector3(-6.5, 2, -4), Vector3(0.5, 4, 16), wall_mat)
	_slab(Vector3(6.5, 2, -4), Vector3(0.5, 4, 16), wall_mat)
	_slab(Vector3(2.4, 0.5, -7.5), Vector3(1.2, 1.0, 1.2), wall_mat)
	for p: Vector3 in [Vector3(-2.5, 3.4, -3), Vector3(2.5, 3.4, -6), Vector3(0, 3.2, 0.5)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 9.0
		l.light_energy = 2.2
		l.light_color = Color(1.0, 0.93, 0.82)
		l.shadow_enabled = true
		add_child(l)


func _slab(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
