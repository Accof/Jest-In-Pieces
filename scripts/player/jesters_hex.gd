class_name JestersHex
extends Node3D
## The Carnival Curse's projectile: a small cracked porcelain clown head with
## hollow eyes, a red nose and a grin, spinning as it flies, two red ribbons
## trailing, a faint violet glow. A real projectile: it steps along its path
## through the physics each frame, stops at the first wall, and tells the
## curse what it struck. It drifts a little after its target (it is cursed),
## but never through anything.

const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2
const RADIUS := 0.055
const TURN := 3.5               ## rad/s it bends toward the target
const TRAIL := 14

var vel := Vector3.ZERO
var life := 2.0
var target: Clown
var curse: CarnivalCurse
var _head: Node3D
var _light: OmniLight3D
var _trail: Array[Vector3] = []
var _im: ImmediateMesh
var _spin := Vector3.ZERO
var _done := false
var _exclude: Array[RID] = []


static func launch(parent: Node, from: Vector3, at: Vector3, tgt: Clown, c: CarnivalCurse) -> JestersHex:
	var h := JestersHex.new()
	h.curse = c
	h.target = tgt
	h.life = c.projectile_lifetime
	parent.add_child(h)
	h.global_position = from
	h.vel = (at - from).normalized() * c.projectile_speed
	if c.player:
		h._exclude.append(c.player.get_rid())
	return h


func _ready() -> void:
	add_to_group(&"curse_vfx")
	_head = Node3D.new()
	add_child(_head)
	var porcelain := StandardMaterial3D.new()
	porcelain.albedo_color = Color(0.93, 0.91, 0.87)
	porcelain.roughness = 0.18
	porcelain.metallic_specular = 0.8
	porcelain.emission_enabled = true
	porcelain.emission = Color(0.45, 0.2, 0.55)
	porcelain.emission_energy_multiplier = 0.25
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.01, 0.015)
	dark.roughness = 0.9
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.04, 0.05)
	red.roughness = 0.3
	_ball(porcelain, Vector3.ZERO, Vector3(1.0, 1.12, 0.95) * RADIUS)
	for sx: float in [-1.0, 1.0]:
		_ball(dark, Vector3(sx * 0.42, 0.22, 0.78) * RADIUS, Vector3(0.24, 0.3, 0.12) * RADIUS)        # hollow eyes
		_box(dark, Vector3(sx * 0.42, 0.62, 0.62) * RADIUS, Vector3(0.35, 0.05, 0.05) * RADIUS, Vector3(0, 0, -sx * 0.4))   # brows
	_ball(red, Vector3(0, -0.05, 1.0) * RADIUS, Vector3.ONE * 0.2 * RADIUS)                              # nose
	for k in 7:                                                                                         # the grin
		var a := lerpf(-0.9, 0.9, k / 6.0)
		_box(dark, Vector3(sin(a) * 0.55, -0.42 + 0.14 * (1.0 - cos(a)), cos(a) * 0.82) * RADIUS, Vector3(0.14, 0.05, 0.04) * RADIUS, Vector3(0, a, 0))
	_box(dark, Vector3(-0.35, 0.65, 0.6) * RADIUS, Vector3(0.03, 0.4, 0.03) * RADIUS, Vector3(0.3, 0, 0.5))   # a crack
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.25, 0.9)
	_light.light_energy = 0.9
	_light.omni_range = 1.6
	add_child(_light)
	_im = ImmediateMesh.new()
	var ribbons := MeshInstance3D.new()
	ribbons.mesh = _im
	ribbons.top_level = true
	ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.vertex_color_use_as_albedo = true
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbons.material_override = rm
	add_child(ribbons)
	ribbons.global_transform = Transform3D.IDENTITY
	_spin = Vector3(randf_range(-2, 2), randf_range(5, 8), randf_range(-2, 2))


func _ball(mat: Material, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	sm.material = mat
	mi.mesh = sm
	mi.transform = Transform3D(Basis.IDENTITY.scaled(size), pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(mi)


func _box(mat: Material, pos: Vector3, size: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 2.0
	bm.material = mat
	mi.mesh = bm
	mi.transform = Transform3D(Basis.from_euler(rot).scaled(size), pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(mi)


func _physics_process(delta: float) -> void:
	if _done:
		return
	life -= delta
	if life <= 0.0:
		_end("missed", global_position, Vector3.UP)
		return
	# drifting after its target, a little
	if target and is_instance_valid(target) and not target.dead:
		var chest: PhysicalBone3D = target.ragdoll.bones.get(&"Chest")
		if chest:
			var want := (chest.global_position - global_position).normalized() * vel.length()
			var ang := vel.angle_to(want)
			if ang > 0.0001:
				vel = vel.slerp(want, minf(TURN * delta / ang, 1.0))
	var step := vel * delta
	var from := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + step + step.normalized() * RADIUS, LAYER_WORLD | LAYER_RAGDOLL)
	q.exclude = _exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.collider
		if c is PhysicalBone3D and (c as Node).has_meta(&"clown"):
			var clown := (c as Node).get_meta(&"clown") as Clown
			if curse and is_instance_valid(curse) and curse.struck(clown, hit.position, vel.normalized()):
				_done = true
				queue_free()
				return
			_end("invalid", hit.position, hit.normal)
			return
		_end("wall", hit.position, hit.normal)
		return
	global_position += step
	_head.rotation += _spin * delta
	_trail.push_front(global_position)
	if _trail.size() > TRAIL:
		_trail.pop_back()
	_draw_ribbons()


## Two thin red ribbons streaming behind, fluttering.
func _draw_ribbons() -> void:
	_im.clear_surfaces()
	if _trail.size() < 2:
		return
	var tt := Time.get_ticks_msec() * 0.001
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in 2:
		var off := Vector3(0.025 if r == 0 else -0.025, 0.0, 0.0)
		for i in _trail.size() - 1:
			var a := _trail[i]
			var b := _trail[i + 1]
			var u0 := float(i) / TRAIL
			var u1 := float(i + 1) / TRAIL
			var side := Vector3.UP * 0.012
			var wob0 := Vector3(0, sin(tt * 18.0 + i * 0.9 + r * 2.0) * 0.02 * u0, 0)
			var wob1 := Vector3(0, sin(tt * 18.0 + (i + 1) * 0.9 + r * 2.0) * 0.02 * u1, 0)
			var c0 := Color(0.65, 0.04, 0.06, 0.75 * (1.0 - u0))
			var c1 := Color(0.65, 0.04, 0.06, 0.75 * (1.0 - u1))
			var p0 := a + off + wob0
			var p1 := b + off + wob1
			_im.surface_set_color(c0)
			_im.surface_add_vertex(p0 - side)
			_im.surface_add_vertex(p0 + side)
			_im.surface_set_color(c1)
			_im.surface_add_vertex(p1 + side)
			_im.surface_set_color(c0)
			_im.surface_add_vertex(p0 - side)
			_im.surface_set_color(c1)
			_im.surface_add_vertex(p1 + side)
			_im.surface_add_vertex(p1 - side)
	_im.surface_end()


## It did not take: a wall, a corpse, out of time. It shatters; the curse
## keeps its charge.
func _end(why: String, at: Vector3, normal: Vector3) -> void:
	_done = true
	if curse and is_instance_valid(curse):
		curse.missed(why)
	SfxSynth.play(get_parent(), "porcelain", at, -6.0, 1.15)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 16
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -7.0, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.01)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.9, 0.86)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	p.add_to_group(&"curse_vfx")
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	queue_free()
