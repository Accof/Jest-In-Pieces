class_name MountedGun
extends StaticBody3D
## A water-cooled heavy machine gun on a tripod. [E] to take it; the mouse
## swings it (within its traverse), held fire hoses the field. It heats up:
## keep the trigger down too long and it boils and stops until it cools.
## When the nest is won it can be ripped off the mount and carried.

signal ripped_off

const TRAVERSE := deg_to_rad(55.0)      ## left/right from straight ahead
const ELEVATION := Vector2(deg_to_rad(-14.0), deg_to_rad(18.0))
const HEAT_PER_SHOT := 0.028
const COOL_RATE := 0.22                  ## heat lost per second (faster while not firing)
const OVERHEAT_RESUME := 0.35

var player: FpsPlayer
var floor_y := 0.0                       ## where the gunner stands
var active := false                      ## the event is running: it can be manned
var can_rip := false                     ## the event is won: it can be taken
var heat := 0.0
var overheated := false
var yaw := 0.0
var pitch := 0.0
var _cooldown := 0.0
var _shot_id := 50000
var _rounds := 0
var _pivot: Node3D                       ## swings with the aim
var _muzzle: Node3D
var _flash: OmniLight3D
var _steam_t := 0.0
var _kick := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.45, 1.1)
	cs.shape = box
	cs.position = Vector3(0, 0.25, -0.2)
	add_child(cs)
	_build_tripod()
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.42, 0)
	add_child(_pivot)
	MountedGun.build_gun(_pivot)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.0, -1.18)
	_pivot.add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 7.0
	_flash.light_energy = 0.0
	_muzzle.add_child(_flash)


func prompt() -> String:
	if player and player.mount == self:
		if overheated:
			return "OVERHEATED - let it cool"
		return "[E] Let go" if not active else ""
	if can_rip:
		return "[E] Rip it off the mount"
	if active:
		return "[E] Man the gun"
	return ""


func use(p: Node) -> void:
	player = p
	if can_rip:
		_rip()
		return
	if not active or player.mount:
		return
	yaw = 0.0
	pitch = 0.0
	var stand := Transform3D(global_basis, global_position + global_basis.z * 0.72)
	stand.origin.y = floor_y + 0.02
	player.take_mount(self, stand)


func can_leave() -> bool:
	return not active                       # no stepping away mid-wave


func released() -> void:
	pass


func look(rel: Vector2) -> void:
	yaw = clampf(yaw - rel.x, -TRAVERSE, TRAVERSE)
	pitch = clampf(pitch - rel.y, ELEVATION.x, ELEVATION.y)


## Called every physics frame the trigger is held.
func trigger() -> void:
	if overheated or _cooldown > 0.0 or player == null:
		return
	_cooldown = FpsPlayer.MOUNTED_MG.cooldown
	_fire()


func _fire() -> void:
	var w: Dictionary = FpsPlayer.MOUNTED_MG
	var from := _muzzle.global_position
	var aim := -_pivot.global_basis.z
	var s := deg_to_rad(w.spread) * (1.0 + heat * 1.5)
	var dir := (aim + _pivot.global_basis.x * randfn(0.0, s * 0.5) + _pivot.global_basis.y * randfn(0.0, s * 0.5)).normalized()
	_shot_id += 1
	_rounds += 1
	var hit := player.shoot_ray(from, dir, w, _shot_id)
	var end: Vector3 = hit.position if not hit.is_empty() else from + dir * 120.0
	if _rounds % 3 == 0:
		_tracer(from, end)
	if not hit.is_empty() and not (hit.collider is PhysicalBone3D):
		_dust(hit.position, hit.normal)
	heat = minf(heat + HEAT_PER_SHOT, 1.0)
	if heat >= 1.0:
		overheated = true
	_flash.light_energy = 6.0
	_kick = 1.0
	player.shake(0.06)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	var firing := player != null and player.mount == self and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	heat = maxf(heat - delta * COOL_RATE * (0.5 if firing else 1.6), 0.0)
	if overheated and heat <= OVERHEAT_RESUME:
		overheated = false
	if player and player.mount == self:
		# the body turns with the gun; the camera rides behind the sights
		var base := global_basis.get_euler().y
		player.rotation.y = base + yaw
		player.camera.rotation.x = pitch
		player.camera.rotation.z = 0.0
	_kick = move_toward(_kick, 0.0, delta * 18.0)
	_pivot.rotation = Vector3(pitch + 0.02 * _kick * randf_range(0.5, 1.0), yaw + randf_range(-0.004, 0.004) * _kick, 0)
	_pivot.position.z = 0.025 * _kick
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 120.0)
	# the water jacket boils over when it is hot
	if heat > 0.7:
		_steam_t -= delta
		if _steam_t <= 0.0:
			_steam_t = 0.12
			_steam()


## Pull the gun off the tripod and keep it (250 rounds left on the belt).
func _rip() -> void:
	can_rip = false
	player.ammo[FpsPlayer.MAXIM] = FpsPlayer.WEAPONS[FpsPlayer.MAXIM].mag
	player.select_weapon(FpsPlayer.MAXIM)
	player.ammo_changed.emit()
	_pivot.visible = false
	player.shake(0.3)
	ripped_off.emit()


func _tracer(from: Vector3, to: Vector3) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25)
	mat.emission_energy_multiplier = 4.0
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var a := from.lerp(to, randf_range(0.0, 0.3))
	im.surface_add_vertex(a)
	im.surface_add_vertex(a.lerp(to, 0.35))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


## A puff of dirt where a round hits the ground.
func _dust(at: Vector3, normal: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = Explosion._quad_mesh()
	m.material_override = Explosion._mat("smoke")
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(m)
	m.global_position = at + normal * 0.15
	m.scale = Vector3.ONE * 0.3
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * 0.9, 0.5)
	tw.parallel().tween_property(m, "global_position", m.global_position + normal * 0.4 + Vector3.UP * 0.2, 0.5)
	tw.parallel().tween_method(func(v: float) -> void: m.set_instance_shader_parameter(&"fade", v), 0.8, 0.0, 0.5)
	tw.tween_callback(m.queue_free)


func _steam() -> void:
	var m := MeshInstance3D.new()
	m.mesh = Explosion._quad_mesh()
	m.material_override = Explosion._mat("smoke")
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(m)
	m.global_position = _pivot.global_transform * Vector3(0, 0.1, -0.55)
	m.scale = Vector3.ONE * 0.15
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * 0.6, 0.8)
	tw.parallel().tween_property(m, "global_position", m.global_position + Vector3.UP * 0.7, 0.8)
	tw.parallel().tween_method(func(v: float) -> void: m.set_instance_shader_parameter(&"fade", v), 0.5, 0.0, 0.8)
	tw.tween_callback(m.queue_free)


func _build_tripod() -> void:
	var steel := _mat(Color(0.12, 0.13, 0.11), 0.5, 0.7)
	for a: float in [0.0, 2.2, 4.1]:
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.022
		cm.height = 0.6
		cm.material = steel
		leg.mesh = cm
		var out := Vector3(sin(a), 0, cos(a))
		leg.position = Vector3(0, 0.2, 0) + out * 0.2
		leg.basis = Basis(out.cross(Vector3.UP).normalized(), 0.6)
		add_child(leg)
	var head := MeshInstance3D.new()
	var hb := CylinderMesh.new()
	hb.top_radius = 0.06
	hb.bottom_radius = 0.07
	hb.height = 0.12
	hb.material = steel
	head.mesh = hb
	head.position = Vector3(0, 0.37, 0)
	add_child(head)


static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## The gun itself, barrel along -Z from the pivot (used here and, smaller, in
## the player's hands).
static func build_gun(parent: Node3D) -> void:
	var steel := _mat(Color(0.14, 0.15, 0.13), 0.45, 0.75)
	var brass := _mat(Color(0.5, 0.38, 0.16), 0.35, 0.9)
	var wood := _mat(Color(0.3, 0.16, 0.07), 0.6, 0.0)
	var dark := _mat(Color(0.04, 0.04, 0.04), 0.6, 0.3)
	var add := func(mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation = rot
		parent.add_child(mi)
	var box := func(size: Vector3) -> BoxMesh:
		var b := BoxMesh.new()
		b.size = size
		return b
	var cyl := func(r: float, h: float) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r
		c.height = h
		c.radial_segments = 16
		return c
	# receiver box, water jacket with its fluting, muzzle booster
	add.call(box.call(Vector3(0.16, 0.16, 0.42)), Vector3(0, 0, 0.0), Vector3.ZERO, steel)
	add.call(cyl.call(0.075, 0.62), Vector3(0, 0.0, -0.52), Vector3(PI * 0.5, 0, 0), brass)
	for k in 5:
		add.call(cyl.call(0.079, 0.02), Vector3(0, 0.0, -0.28 - k * 0.12), Vector3(PI * 0.5, 0, 0), steel)
	add.call(cyl.call(0.03, 0.14), Vector3(0, 0.0, -0.9), Vector3(PI * 0.5, 0, 0), dark)
	add.call(cyl.call(0.04, 0.08), Vector3(0, 0.0, -1.0), Vector3(PI * 0.5, 0, 0), steel)
	# filler cap and steam hose
	add.call(cyl.call(0.022, 0.04), Vector3(0, 0.085, -0.35), Vector3.ZERO, steel)
	add.call(cyl.call(0.012, 0.3), Vector3(0.09, -0.06, -0.65), Vector3(PI * 0.5, 0, 0.2), dark)
	# rear: spade grips and the thumb trigger
	add.call(box.call(Vector3(0.22, 0.03, 0.03)), Vector3(0, -0.02, 0.24), Vector3.ZERO, steel)
	for sd: float in [-1.0, 1.0]:
		add.call(cyl.call(0.022, 0.13), Vector3(sd * 0.1, -0.02, 0.27), Vector3(0, 0, 0), wood)
	# sights, ammo box on the side and the belt running into the feed
	add.call(box.call(Vector3(0.03, 0.06, 0.02)), Vector3(0, 0.11, 0.12), Vector3.ZERO, steel)
	add.call(box.call(Vector3(0.012, 0.05, 0.012)), Vector3(0, 0.1, -0.84), Vector3.ZERO, steel)
	add.call(box.call(Vector3(0.12, 0.2, 0.26)), Vector3(0.2, -0.12, -0.02), Vector3.ZERO, _mat(Color(0.2, 0.22, 0.14), 0.7, 0.2))
	add.call(box.call(Vector3(0.09, 0.012, 0.05)), Vector3(0.11, 0.03, -0.02), Vector3(0, 0, -0.5), _mat(Color(0.35, 0.28, 0.15), 0.8, 0.0))
