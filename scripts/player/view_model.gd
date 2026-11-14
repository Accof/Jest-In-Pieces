class_name ViewModel
extends Node3D
## The player's hands and gun as seen in first person. Built from simple shapes
## and animated in code: sway, walking bob, recoil, slide and pump action,
## reloads and weapon swaps.
##
## Everything is authored at real size, then the whole thing is shrunk toward
## the camera. That looks identical on screen but keeps the gun inside the
## player's body, so it does not poke through walls.

const SHRINK := 0.45
const PISTOL := 0
const SHOTGUN := 1

## Seconds the reload animations take. The player script reads these.
const PISTOL_RELOAD := 1.55
const SHELL_TIME := 0.48
const SHELL_INTRO := 0.3
const SWAP_TIME := 0.3

var weapon := PISTOL
var slide_locked := false       # pistol ran dry: slide stays back until reloaded

var _guns: Array[Node3D] = []
var _pose: Array[Node3D] = []   # per gun: the node recoil and reload move
var _slide: Node3D
var _mag: Node3D
var _spare_mag: Node3D
var _pump: Node3D
var _shell: Node3D
var _left: Array[Node3D] = []   # per gun: the left arm
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D

var _time := 0.0
var _kick := 0.0                # recoil, decays
var _slide_back := 0.0
var _since_shot := 9.0
var _reload_t := -1.0           # >= 0 while reloading
var _swap_t := -1.0
var _swap_to := 0
var _bob := 0.0
var _bob_amount := 0.0
var _sway := Vector2.ZERO


func _ready() -> void:
	scale = Vector3.ONE * SHRINK
	_build_pistol()
	_build_shotgun()
	_guns[SHOTGUN].visible = false
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.omni_range = 7.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.075, 0.075)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	fm.albedo_texture = g
	q.material = fm
	_flash_mesh.mesh = q
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash_mesh)


# --- called by the player -------------------------------------------------------
func fire() -> void:
	_kick = 1.0
	_slide_back = 1.0
	_since_shot = 0.0
	var muzzle := _muzzle()
	_flash.position = muzzle
	_flash.light_energy = 5.0 if weapon == PISTOL else 9.0
	_flash_mesh.position = muzzle
	_flash_mesh.scale = Vector3.ONE * (1.0 if weapon == PISTOL else 1.8) * randf_range(0.8, 1.2)
	_flash_mesh.visible = true


func start_reload() -> void:
	_reload_t = 0.0


func stop_reload() -> void:
	_reload_t = -1.0


func reloading() -> bool:
	return _reload_t >= 0.0


func swap_to(w: int) -> void:
	if w == weapon and _swap_t < 0.0:
		return
	_swap_to = w
	_swap_t = 0.0
	_reload_t = -1.0


func swapping() -> bool:
	return _swap_t >= 0.0


## `speed` is how fast the player is walking; `look` is this frame's mouse movement.
func animate(delta: float, speed: float, look: Vector2) -> void:
	_time += delta
	_since_shot += delta
	_kick = move_toward(_kick, 0.0, delta * (7.0 if weapon == PISTOL else 3.2))
	_slide_back = move_toward(_slide_back, 0.0, delta * 14.0)
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 90.0)
	if _since_shot > 0.045:
		_flash_mesh.visible = false
	_bob_amount = move_toward(_bob_amount, clampf(speed / 4.5, 0.0, 1.4), delta * 6.0)
	_bob += delta * (5.0 + speed * 1.3)
	_sway = _sway.lerp(Vector2(clampf(-look.x * 0.0009, -0.05, 0.05), clampf(look.y * 0.0009, -0.05, 0.05)), clampf(delta * 9.0, 0.0, 1.0))
	if _reload_t >= 0.0:
		_reload_t += delta

	# Lower one gun, raise the other.
	var drop := 0.0
	if _swap_t >= 0.0:
		_swap_t += delta
		var half := SWAP_TIME * 0.5
		if _swap_t >= half and weapon != _swap_to:
			weapon = _swap_to
			_guns[PISTOL].visible = weapon == PISTOL
			_guns[SHOTGUN].visible = weapon == SHOTGUN
		drop = 1.0 - absf(_swap_t - half) / half
		if _swap_t >= SWAP_TIME:
			_swap_t = -1.0
			drop = 0.0

	# Whole-gun motion shared by both weapons: sway, bob, breathing, swap.
	var root := _guns[weapon]
	var bob := Vector3(sin(_bob) * 0.006, -absf(cos(_bob)) * 0.008, 0) * _bob_amount
	var breathe := Vector3(0, sin(_time * 1.6) * 0.0018, 0)
	root.position = bob + breathe + Vector3(_sway.x, _sway.y - drop * 0.35, 0)
	root.rotation = Vector3(-drop * 0.9 + _sway.y * 1.2, _sway.x * 1.5, _sway.x * 0.8)

	if weapon == PISTOL:
		_animate_pistol()
	else:
		_animate_shotgun()


# --- pistol ---------------------------------------------------------------------
const P_HOME := Vector3(0.125, -0.125, -0.54)
const P_LEFT_HOME := Vector3(-0.015, -0.085, 0.01)

func _animate_pistol() -> void:
	var pose := _pose[PISTOL]
	var left := _left[PISTOL]
	var k := _kick * _kick
	var pos := P_HOME + Vector3(0, 0.012 * k, 0.03 * k)
	var rot := Vector3(deg_to_rad(9.0) * k, 0, deg_to_rad(randf_range(-0.6, 0.6)) * k)
	var slide := maxf(_slide_back, 1.0 if slide_locked else 0.0)
	var mag_pos := Vector3.ZERO
	var mag_visible := true
	var left_pos := P_LEFT_HOME
	var left_rot := Vector3.ZERO
	var spare := false
	if _reload_t >= 0.0:
		var t := _reload_t
		# 0.00-0.22  tip the gun over to get at the magazine
		# 0.22-0.50  old magazine drops free, support hand goes for a new one
		# 0.50-0.98  new magazine comes up and is pushed home
		# 0.98-1.20  hand back on the gun, slide released if it was locked
		# 1.20-1.55  back on target
		var tilt := smoothstep(0.0, 0.22, t) * (1.0 - smoothstep(1.2, PISTOL_RELOAD, t))
		pos += Vector3(-0.03, 0.035, 0.03) * tilt
		rot += Vector3(deg_to_rad(16.0), deg_to_rad(12.0), deg_to_rad(-32.0)) * tilt
		if t < 0.5:
			var fall := smoothstep(0.22, 0.5, t)
			mag_pos = Vector3(0, -0.3 * fall * fall, 0.03 * fall)
			mag_visible = t < 0.48
		elif t < 0.98:
			var up := smoothstep(0.55, 0.92, t)
			mag_pos = Vector3(0, -0.17 * (1.0 - up), 0.0)
			mag_visible = t > 0.6
			spare = false
		var away := smoothstep(0.18, 0.4, t) * (1.0 - smoothstep(0.55, 0.9, t))
		left_pos = P_LEFT_HOME + Vector3(-0.06, -0.3, 0.1) * away
		# as the magazine goes in, the hand is under the grip pushing up
		var seat := smoothstep(0.6, 0.92, t) * (1.0 - smoothstep(0.98, 1.15, t))
		left_pos += Vector3(0.015, -0.045 * (1.0 - smoothstep(0.86, 0.94, t)), 0.0) * seat
		left_rot = Vector3(0, 0, deg_to_rad(-20.0)) * seat
		pos += Vector3(0, 0.012, 0) * (smoothstep(0.9, 0.95, t) - smoothstep(0.95, 1.05, t))   # the bump as it seats
		if slide_locked and t > 1.1:
			slide = 1.0 - smoothstep(1.1, 1.16, t)
			pos += Vector3(0, 0, -0.008) * (smoothstep(1.12, 1.16, t) - smoothstep(1.16, 1.3, t))
	pose.position = pos
	pose.rotation = rot
	_slide.position.z = 0.045 * slide
	_mag.position = mag_pos
	_mag.visible = mag_visible
	_spare_mag.visible = spare
	left.position = left_pos
	left.rotation = left_rot


func _build_pistol() -> void:
	var root := Node3D.new()
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var poly := _mat(Color(0.07, 0.07, 0.075), 0.55, 0.0)
	var steel := _mat(Color(0.16, 0.16, 0.17), 0.3, 0.7)
	# Frame, with the long dust cover and rail of a long-slide pistol.
	_box(pose, Vector3(0.030, 0.024, 0.200), Vector3(0, -0.006, -0.022), Vector3.ZERO, poly)
	_box(pose, Vector3(0.022, 0.006, 0.055), Vector3(0, -0.021, -0.085), Vector3.ZERO, poly)      # rail
	# Grip, raked back.
	_box(pose, Vector3(0.031, 0.118, 0.052), Vector3(0, -0.068, 0.072), Vector3(18, 0, 0), poly)
	_box(pose, Vector3(0.032, 0.020, 0.026), Vector3(0, -0.018, 0.094), Vector3(18, 0, 0), poly)   # beavertail
	# Trigger guard and trigger.
	_box(pose, Vector3(0.012, 0.005, 0.058), Vector3(0, -0.048, 0.012), Vector3.ZERO, poly)
	_box(pose, Vector3(0.012, 0.034, 0.005), Vector3(0, -0.033, -0.017), Vector3.ZERO, poly)
	_box(pose, Vector3(0.006, 0.020, 0.005), Vector3(0, -0.028, 0.018), Vector3(-18, 0, 0), poly)
	# Slide: long, square, with rear serrations and sights.
	_slide = Node3D.new()
	pose.add_child(_slide)
	_box(_slide, Vector3(0.029, 0.026, 0.262), Vector3(0, 0.019, -0.028), Vector3.ZERO, steel)
	for i in 6:
		_box(_slide, Vector3(0.0305, 0.020, 0.0025), Vector3(0, 0.019, 0.060 + i * 0.006), Vector3.ZERO, poly)
	_box(_slide, Vector3(0.016, 0.006, 0.008), Vector3(0, 0.035, 0.092), Vector3.ZERO, poly)       # rear sight
	_box(_slide, Vector3(0.004, 0.005, 0.006), Vector3(0, 0.0345, -0.150), Vector3.ZERO, poly)     # front sight
	_box(_slide, Vector3(0.0295, 0.010, 0.040), Vector3(0, 0.024, -0.02), Vector3.ZERO, _mat(Color(0.12, 0.12, 0.13), 0.3, 0.8))   # ejection port
	# Barrel, fixed, showing at the muzzle.
	_cyl(pose, 0.0065, 0.03, Vector3(0, 0.02, -0.158), Vector3(90, 0, 0), _mat(Color(0.02, 0.02, 0.02), 0.4, 0.6))
	# Magazine in the grip, and a spare carried by the support hand.
	_mag = Node3D.new()
	pose.add_child(_mag)
	var mag_mat := _mat(Color(0.05, 0.05, 0.055), 0.45, 0.3)
	_box(_mag, Vector3(0.024, 0.118, 0.034), Vector3(0, -0.07, 0.073), Vector3(18, 0, 0), mag_mat)
	_box(_mag, Vector3(0.031, 0.010, 0.050), Vector3(0, -0.130, 0.092), Vector3(18, 0, 0), poly)
	_spare_mag = Node3D.new()
	pose.add_child(_spare_mag)
	_spare_mag.visible = false
	# Right hand, wrapped round the grip, part of the gun so it recoils with it.
	_hand(pose, Vector3(0, -0.062, 0.082), Vector3(0.085, -0.30, 0.42), false)
	# Left hand, cupped under and round the right.
	var left := Node3D.new()
	pose.add_child(left)
	_hand(left, Vector3(-0.012, -0.066, 0.062), Vector3(-0.30, -0.30, 0.34), true)
	_left.append(left)


# --- shotgun --------------------------------------------------------------------
const S_HOME := Vector3(0.15, -0.155, -0.42)

func _animate_shotgun() -> void:
	var pose := _pose[SHOTGUN]
	var left := _left[SHOTGUN]
	var k := _kick * _kick
	var pos := S_HOME + Vector3(0, 0.02 * k, 0.07 * k)
	var rot := Vector3(deg_to_rad(11.0) * k, deg_to_rad(-1.5) * k, 0)
	# Pump: racked back and forward a moment after each shot.
	var pump := 0.0
	if _since_shot > 0.2 and _since_shot < 0.62:
		pump = sin((_since_shot - 0.2) / 0.42 * PI)
	var shell_vis := false
	var left_pos := Vector3(0, 0, 0.085 * pump)
	if _reload_t >= 0.0:
		var t := _reload_t
		var tilt := smoothstep(0.0, SHELL_INTRO, t)
		pos += Vector3(-0.02, 0.05, 0.04) * tilt
		rot += Vector3(deg_to_rad(20.0), deg_to_rad(8.0), deg_to_rad(38.0)) * tilt
		if t > SHELL_INTRO:
			# One shell at a time: hand down for a shell, up to the port, thumb it in.
			var c := fposmod(t - SHELL_INTRO, SHELL_TIME) / SHELL_TIME
			var reach := sin(clampf(c / 0.55, 0.0, 1.0) * PI)
			left_pos = Vector3(0.02, -0.02, 0.2) + Vector3(-0.05, -0.22, 0.08) * reach
			shell_vis = c > 0.3 and c < 0.92
			if c > 0.78:
				left_pos += Vector3(0, 0.012, -0.03) * sin((c - 0.78) / 0.22 * PI)
		else:
			left_pos = Vector3(0.02, -0.02, 0.2) * tilt
	pose.position = pos
	pose.rotation = rot
	_pump.position.z = 0.085 * pump
	left.position = left_pos
	_shell.visible = shell_vis


func _build_shotgun() -> void:
	var root := Node3D.new()
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var steel := _mat(Color(0.15, 0.15, 0.16), 0.32, 0.75)
	var wood := _mat(Color(0.30, 0.15, 0.07), 0.5, 0.0)
	_box(pose, Vector3(0.042, 0.062, 0.24), Vector3(0, 0, 0.02), Vector3.ZERO, steel)                 # receiver
	_cyl(pose, 0.013, 0.52, Vector3(0, 0.018, -0.36), Vector3(90, 0, 0), steel)                        # barrel
	_cyl(pose, 0.012, 0.40, Vector3(0, -0.014, -0.30), Vector3(90, 0, 0), steel)                       # magazine tube
	_box(pose, Vector3(0.006, 0.008, 0.006), Vector3(0, 0.034, -0.61), Vector3.ZERO, steel)            # bead sight
	_box(pose, Vector3(0.04, 0.07, 0.30), Vector3(0, -0.035, 0.27), Vector3(-10, 0, 0), wood)          # stock
	_box(pose, Vector3(0.034, 0.075, 0.045), Vector3(0, -0.062, 0.115), Vector3(22, 0, 0), wood)       # grip
	_box(pose, Vector3(0.012, 0.005, 0.07), Vector3(0, -0.048, 0.055), Vector3.ZERO, steel)            # trigger guard
	_pump = Node3D.new()
	pose.add_child(_pump)
	_box(_pump, Vector3(0.046, 0.044, 0.15), Vector3(0, -0.014, -0.24), Vector3.ZERO, wood)            # fore-end
	_hand(pose, Vector3(0, -0.07, 0.125), Vector3(0.09, -0.30, 0.48), false)
	var left := Node3D.new()
	pose.add_child(left)
	_hand(left, Vector3(-0.004, -0.04, -0.24), Vector3(-0.28, -0.30, 0.20), true)
	_shell = Node3D.new()
	left.add_child(_shell)
	_cyl(_shell, 0.011, 0.062, Vector3(0.012, -0.012, -0.262), Vector3(90, 0, 0), _mat(Color(0.55, 0.06, 0.05), 0.5, 0.0))
	_cyl(_shell, 0.0115, 0.014, Vector3(0.012, -0.012, -0.224), Vector3(90, 0, 0), _mat(Color(0.75, 0.6, 0.25), 0.3, 0.9))
	_shell.visible = false
	_left.append(left)


func _muzzle() -> Vector3:
	var local := Vector3(0, 0.02, -0.19) if weapon == PISTOL else Vector3(0, 0.018, -0.64)
	return to_local(_pose[weapon].to_global(local))


# --- building blocks ------------------------------------------------------------
## A bare hand gripping something at `at`, with a sleeved forearm running to `elbow`.
func _hand(parent: Node3D, at: Vector3, elbow: Vector3, is_left: bool) -> void:
	var skin := _mat(Color(0.66, 0.48, 0.39), 0.7, 0.0)
	var sleeve := _mat(Color(0.10, 0.11, 0.16), 0.95, 0.0)
	var cuff := _mat(Color(0.06, 0.065, 0.10), 0.9, 0.0)
	var s := -1.0 if is_left else 1.0
	var hand := Node3D.new()
	hand.position = at
	parent.add_child(hand)
	# back of the hand against the side of the grip
	_box(hand, Vector3(0.022, 0.082, 0.058), Vector3(s * 0.027, 0.0, 0.006), Vector3(18, 0, 0), skin)
	# four fingers wrapped across the front, one above the other
	for i in 4:
		var y := 0.024 - i * 0.021
		_box(hand, Vector3(0.062, 0.0185, 0.022), Vector3(s * 0.002, y, -0.036 + y * 0.32), Vector3(18, 0, s * 4.0), skin)
	_box(hand, Vector3(0.020, 0.022, 0.066), Vector3(-s * 0.025, 0.038, -0.010), Vector3(8, 0, 0), skin)     # thumb
	_box(hand, Vector3(0.060, 0.046, 0.046), Vector3(s * 0.012, -0.030, 0.044), Vector3(18, 0, 0), skin)     # heel of the hand
	var wrist := at + Vector3(s * 0.016, -0.045, 0.065)
	_limb(parent, wrist.lerp(elbow, 0.06), elbow, 0.037, sleeve)
	_limb(parent, wrist, wrist.lerp(elbow, 0.05), 0.030, skin)
	_limb(parent, wrist.lerp(elbow, 0.06), wrist.lerp(elbow, 0.13), 0.040, cuff)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, rot_deg, mat)


func _cyl(parent: Node3D, radius: float, length: float, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	return _add(parent, mesh, pos, rot_deg, mat)


func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = from.distance_to(to) + radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 3
	var mi := _add(parent, mesh, (from + to) * 0.5, Vector3.ZERO, mat)
	var y := (to - from).normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	mi.basis = Basis(x, y, x.cross(y))


func _add(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = 2                                           # keeps blood decals off the gun
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
