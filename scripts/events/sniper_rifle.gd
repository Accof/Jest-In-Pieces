class_name SniperRifle
extends StaticBody3D
## A scoped bolt-action rifle on a bipod, resting on a balcony rail. [E] to
## take it; the mouse swings it, the right mouse button looks down the scope,
## the left fires. One round, then the bolt has to be worked.

signal fired(hit: Dictionary)

const TRAVERSE := deg_to_rad(70.0)
const ELEVATION := Vector2(deg_to_rad(-62.0), deg_to_rad(28.0))
const FOV_OPEN := 72.0
const FOV_SCOPE := 13.0
const BOLT_TIME := 1.05
const ROUND := {name = "Rifle", damage = 260.0, pellets = 1, spread = 0.0, impulse = 5.0, heavy = false, can_dismember = false, cooldown = BOLT_TIME, falloff = 400.0, mag = 1}

var player: FpsPlayer
var floor_y := 0.0
var yaw := 0.0
var pitch := 0.0
var zoom := 0.0                      ## 0 = over the top of the scope, 1 = looking through it
var rounds_fired := 0
var hold_scope := false              ## tests: act as if the right button were held
var _bolt := 0.0                     ## time left working the bolt
var _last_trigger_frame := -10
var _shot_id := 70000
var _pivot: Node3D
var _bolt_handle: Node3D
var _flash: OmniLight3D
var _kick := 0.0
var _overlay: CanvasLayer
var _scope: Control


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 1.2)
	cs.shape = box
	cs.position = Vector3(0, 0.12, -0.2)
	add_child(cs)
	_pivot = Node3D.new()
	add_child(_pivot)
	_build_rifle()
	for n in _pivot.get_children():
		(n as Node3D).position.z -= 0.22
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.5)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0, 0.05, -1.05)
	_pivot.add_child(_flash)
	_overlay = CanvasLayer.new()
	_overlay.layer = 5
	_overlay.visible = false
	add_child(_overlay)
	_scope = Control.new()
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.draw.connect(_draw_scope)
	_overlay.add_child(_scope)


func prompt() -> String:
	if player and player.mount == self:
		if _bolt > 0.0:
			return "working the bolt..."
		return "[RMB] scope   [LMB] fire   [E] let go"
	return "[E] Take the rifle"


func use(p: Node) -> void:
	player = p
	if player.mount:
		return
	var stand := Transform3D(global_basis, global_position + global_basis.z * 0.8)
	stand.origin.y = floor_y + 0.02
	player.take_mount(self, stand)
	# the eye sits just over the scope
	pitch = clampf(pitch, ELEVATION.x, ELEVATION.y)


func can_leave() -> bool:
	return true


func released() -> void:
	zoom = 0.0
	_overlay.visible = false
	if player:
		player.camera.fov = 80.0


func look(rel: Vector2) -> void:
	var k := player.camera.fov / 80.0 if player else 1.0     # finer through the glass
	yaw = clampf(yaw - rel.x * k, -TRAVERSE, TRAVERSE)
	pitch = clampf(pitch - rel.y * k, ELEVATION.x, ELEVATION.y)


## Called every physics frame the trigger is held: a bolt gun fires once per pull.
func trigger() -> void:
	var f := Engine.get_physics_frames()
	var fresh := f - _last_trigger_frame > 1
	_last_trigger_frame = f
	if not fresh or _bolt > 0.0 or player == null:
		return
	_fire()


func _fire() -> void:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	# a little sway when firing from the hip, none through the scope
	var s := deg_to_rad(2.2) * (1.0 - zoom)
	dir = (dir + cam.global_basis.x * randfn(0.0, s) + cam.global_basis.y * randfn(0.0, s)).normalized()
	_shot_id += 1
	rounds_fired += 1
	var ignore: Array[RID] = [get_rid()]
	var hit := player.shoot_ray(from, dir, ROUND, _shot_id, ignore)
	_bolt = BOLT_TIME
	_kick = 1.0
	_flash.light_energy = 5.0
	player.shake(0.12)
	fired.emit(hit)


func _physics_process(delta: float) -> void:
	var mounted := player != null and player.mount == self
	var want := 1.0 if mounted and (hold_scope or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) else 0.0
	zoom = move_toward(zoom, want, delta * 6.0)
	if mounted:
		var base := global_basis.get_euler().y
		player.rotation.y = base + yaw
		player.camera.rotation.x = pitch - _kick * 0.05
		player.camera.rotation.z = 0.0
		player.camera.fov = lerpf(FOV_OPEN, FOV_SCOPE, smoothstep(0.0, 1.0, zoom))
		_overlay.visible = zoom > 0.55
		_scope.queue_redraw()
	_bolt = maxf(_bolt - delta, 0.0)
	_kick = move_toward(_kick, 0.0, delta * 5.0)
	_pivot.rotation = Vector3(pitch + _kick * 0.08, yaw, 0)
	_pivot.position.z = 0.04 * _kick
	# the bolt: up, back, forward, down
	var b := 1.0 - _bolt / BOLT_TIME if _bolt > 0.0 else 1.0
	var lift := sin(clampf((b - 0.15) / 0.7, 0.0, 1.0) * PI)
	_bolt_handle.rotation.z = -1.2 * lift
	_bolt_handle.position.z = 0.02 + 0.09 * sin(clampf((b - 0.3) / 0.45, 0.0, 1.0) * PI)
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 80.0)
	# through the glass the rifle is not in the way
	# nor when you look right down past it
	_pivot.visible = zoom < 0.5 and pitch > deg_to_rad(-38.0)


func _draw_scope() -> void:
	var sz := _scope.size
	var c := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.46
	var black := Color(0, 0, 0, 1)
	# everything outside the glass is black: a ring of quads from the circle out
	var n := 64
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var q0 := c + Vector2(cos(a0), sin(a0)) * sz.length()
		var q1 := c + Vector2(cos(a1), sin(a1)) * sz.length()
		_scope.draw_colored_polygon(PackedVector2Array([p0, q0, q1, p1]), black)
	# a soft dark edge inside the glass
	for k in 6:
		_scope.draw_arc(c, r - k * 3.0, 0, TAU, 96, Color(0, 0, 0, 0.5 - k * 0.08), 4.0)
	# reticle: thick posts, fine cross, a dot
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	_scope.draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.18, 0), ink, 5.0)
	_scope.draw_line(c + Vector2(r * 0.18, 0), c + Vector2(r, 0), ink, 5.0)
	_scope.draw_line(c + Vector2(0, r * 0.18), c + Vector2(0, r), ink, 5.0)
	_scope.draw_line(c + Vector2(-r * 0.18, 0), c + Vector2(r * 0.18, 0), ink, 1.2)
	_scope.draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.18), ink, 1.2)
	_scope.draw_circle(c, 2.2, Color(0.75, 0.1, 0.08))
	if _bolt > 0.0:
		_scope.draw_rect(Rect2(c + Vector2(-60, r * 0.6), Vector2(120 * (1.0 - _bolt / BOLT_TIME), 5)), Color(0.9, 0.7, 0.3, 0.8))


func _build_rifle() -> void:
	var steel := MountedGun._mat(Color(0.1, 0.1, 0.1), 0.4, 0.8)
	var wood := LevelArt._mat("wood")
	var brass := MountedGun._mat(Color(0.5, 0.38, 0.16), 0.35, 0.9)
	var add := func(mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material, parent: Node3D = _pivot) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation = rot
		parent.add_child(mi)
		return mi
	var box := func(size: Vector3) -> BoxMesh:
		var b := BoxMesh.new()
		b.size = size
		return b
	var cyl := func(r: float, h: float) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r
		c.height = h
		c.radial_segments = 14
		return c
	# stock and fore-end
	add.call(box.call(Vector3(0.06, 0.09, 0.62)), Vector3(0, -0.03, -0.12), Vector3.ZERO, wood)
	add.call(box.call(Vector3(0.055, 0.14, 0.26)), Vector3(0, -0.07, 0.3), Vector3(-0.12, 0, 0), wood)
	# receiver and barrel
	add.call(cyl.call(0.022, 0.24), Vector3(0, 0.03, 0.02), Vector3(PI * 0.5, 0, 0), steel)
	add.call(cyl.call(0.011, 0.72), Vector3(0, 0.03, -0.55), Vector3(PI * 0.5, 0, 0), steel)
	# the scope on its rings
	add.call(cyl.call(0.022, 0.34), Vector3(0, 0.1, -0.02), Vector3(PI * 0.5, 0, 0), steel)
	add.call(cyl.call(0.03, 0.07), Vector3(0, 0.1, -0.2), Vector3(PI * 0.5, 0, 0), steel)
	add.call(cyl.call(0.027, 0.05), Vector3(0, 0.1, 0.16), Vector3(PI * 0.5, 0, 0), steel)
	for z: float in [-0.08, 0.06]:
		add.call(box.call(Vector3(0.03, 0.06, 0.02)), Vector3(0, 0.065, z), Vector3.ZERO, brass)
	# bolt handle (it works when you fire)
	_bolt_handle = Node3D.new()
	_bolt_handle.position = Vector3(0.022, 0.035, 0.02)
	_pivot.add_child(_bolt_handle)
	add.call(cyl.call(0.006, 0.07), Vector3(0.035, 0, 0), Vector3(0, 0, PI * 0.5), steel, _bolt_handle)
	add.call(SphereMesh.new(), Vector3(0.07, 0, 0), Vector3.ZERO, steel, _bolt_handle).scale = Vector3.ONE * 0.025
	# bipod legs to the rail
	for sd: float in [-1.0, 1.0]:
		add.call(cyl.call(0.007, 0.22), Vector3(sd * 0.05, -0.1, -0.5), Vector3(0.2, 0, sd * 0.3), steel)
