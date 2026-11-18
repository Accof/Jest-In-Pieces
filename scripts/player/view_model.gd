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
const SMG := 2
const STAKE := 3
const MAXIM := 4
const RIFLE := 5
const REVOLVER := 6

## Seconds the reload animations take. The player script reads these.
const PISTOL_RELOAD := 1.55
const SHELL_TIME := 0.48
const SHELL_INTRO := 0.3
const SWAP_TIME := 0.3
const SMG_RELOAD := 1.9
const SMG_SEAT := 1.12          # the new magazine clicks home
const STAKE_RELOAD := 2.9
const STAKE_SEAT := 1.5         # the new stake is on the rail
const RIFLE_CYCLE := 0.95       # working the bolt after a shot
const RIFLE_RELOAD := 2.5       # bolt open, a stripper clip of five thumbed in, bolt shut
const RIFLE_SEAT := 1.55        # the rounds are in the magazine
const REVOLVER_RELOAD := 3.0    # broken open, the extractor throws everything out, six in, snapped shut
const REVOLVER_SEAT := 2.35     # the rounds are in (the frame snaps shut)

var weapon := PISTOL
var slide_locked := false       # pistol ran dry: slide stays back until reloaded

var _guns: Array[Node3D] = []
var _pose: Array[Node3D] = []   # per gun: the node recoil and reload move
var _slide: Node3D
var _mag: Node3D
var _spare_mag: Node3D
var _pump: Node3D
var _shell: Node3D
var _smg_mag: Node3D
var _smg_bolt: Node3D
var _stake_loaded: Node3D
var _stake_in_hand: Node3D
var _stake_lever: Node3D
var _gauge_needle: Node3D
var _rifle_bolt: Node3D
var _rifle_rhand: Node3D
var _rifle_clip: Node3D
var _cycle_t := -1.0            # >= 0 while the bolt is being worked after a shot
var stake_ready := true         # set by the player: is a stake on the rail
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
	_build_smg()
	_build_stake()
	_build_maxim()
	_build_rifle()
	_build_revolver()
	for gi in range(1, _guns.size()):
		_guns[gi].visible = false
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
	_flash.light_energy = [5.0, 9.0, 4.0, 1.5, 8.0, 8.0, 10.0][weapon]
	_flash_mesh.position = muzzle
	_flash_mesh.scale = Vector3.ONE * [1.0, 1.8, 0.9, 2.4, 2.2, 2.0, 1.9][weapon] * randf_range(0.7, 1.25)
	if weapon == RIFLE:
		_cycle_t = 0.0
	if weapon == REVOLVER:
		_revolver_fired()
	_flash_mesh.rotation.z = randf() * TAU
	if weapon == SMG or weapon == MAXIM:
		_jitter = Vector2(randf_range(-1, 1), randf_range(-0.3, 1))
	_flash_mesh.visible = true


## A double-action pull has started: the shot comes `length` seconds later.
func start_pull(length: float) -> void:
	if weapon == REVOLVER and _rv_parts:
		_rv_pull_t = 0.0
		_rv_pull_len = maxf(length, 0.001)
		_rv_turn()


func cancel_pull() -> void:
	_rv_pull_t = -1.0


func start_reload() -> void:
	_reload_t = 0.0
	if weapon == REVOLVER:
		_revolver_reset_reload()


func stop_reload() -> void:
	_reload_t = -1.0
	_revolver_reset_reload()


func reloading() -> bool:
	return _reload_t >= 0.0


func swap_to(w: int) -> void:
	if w == weapon and _swap_t < 0.0:
		return
	_swap_to = w
	_swap_t = 0.0
	_reload_t = -1.0
	_revolver_reset_reload()


func swapping() -> bool:
	return _swap_t >= 0.0


## `speed` is how fast the player is walking; `look` is this frame's mouse movement.
func animate(delta: float, speed: float, look: Vector2) -> void:
	_time += delta
	_since_shot += delta
	_kick = move_toward(_kick, 0.0, delta * [7.0, 3.2, 14.0, 2.2, 11.0, 3.0, 3.6][weapon])
	if _cycle_t >= 0.0:
		_cycle_t += delta
		if _cycle_t > RIFLE_CYCLE:
			_cycle_t = -1.0
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
			for gi in _guns.size():
				_guns[gi].visible = gi == weapon
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
	elif weapon == SHOTGUN:
		_animate_shotgun()
	elif weapon == SMG:
		_animate_smg()
	elif weapon == STAKE:
		_animate_stake()
	elif weapon == RIFLE:
		_animate_rifle()
	elif weapon == REVOLVER:
		_animate_revolver()
	else:
		_animate_maxim()


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


# --- submachine gun --------------------------------------------------------------
# A WW1 trench gun: wooden stock, a tube receiver with a perforated barrel
# jacket, and a long magazine sticking out of the left side.
const Q_HOME := Vector3(0.155, -0.16, -0.40)
const Q_LEFT_HOME := Vector3.ZERO
var _jitter := Vector2.ZERO

func _animate_smg() -> void:
	var pose := _pose[SMG]
	var left := _left[SMG]
	var k := _kick * _kick
	# each round shoves it back and a little up and sideways; sustained fire
	# makes it buck about
	var pos := Q_HOME + Vector3(0.004 * _jitter.x * k, 0.008 * k, 0.03 * k)
	var rot := Vector3(deg_to_rad(4.5 + 2.0 * _jitter.y) * k, deg_to_rad(1.4 * _jitter.x) * k, deg_to_rad(1.0 * _jitter.x) * k)
	var bolt := _slide_back
	var mag_pos := Vector3.ZERO
	var mag_visible := true
	var left_pos := Q_LEFT_HOME
	var left_rot := Vector3.ZERO
	if _reload_t >= 0.0:
		var t := _reload_t
		# 0.00-0.25  roll the gun so the magazine comes up into view
		# 0.25-0.62  support hand to the magazine, pull it out sideways, drop it
		# 0.62-1.12  hand away for a fresh one, back, push it home
		# 1.12-1.30  hand back on the jacket
		# 1.30-1.55  rack the bolt
		# 1.55-1.90  back on target
		var tilt := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(1.55, SMG_RELOAD, t))
		pos += Vector3(-0.035, 0.04, 0.035) * tilt
		rot += Vector3(deg_to_rad(10.0), deg_to_rad(14.0), deg_to_rad(28.0)) * tilt
		var at_mag := Vector3(-0.1, 0.05, 0.06)            # left hand, holding the end of the magazine
		if t < 0.62:
			var grab := smoothstep(0.22, 0.42, t)
			var pull := smoothstep(0.42, 0.58, t)
			left_pos = at_mag * grab + Vector3(-0.09, -0.02, 0) * pull
			mag_pos = Vector3(-0.09, -0.02, 0) * pull
			mag_visible = t < 0.6
		elif t < 1.12:
			var away := 1.0 - smoothstep(0.62, 0.82, t) + smoothstep(0.82, 0.98, t)
			away = clampf(away, 0.0, 1.0)
			var push := smoothstep(0.98, 1.1, t)
			var out := Vector3(-0.09, -0.02, 0) * (1.0 - push)
			left_pos = at_mag + out + Vector3(-0.08, -0.32, 0.12) * (1.0 - away)
			mag_pos = out + Vector3(-0.08, -0.32, 0.12) * (1.0 - away)
			mag_visible = t > 0.8
			pos += Vector3(0.006, 0, 0) * (smoothstep(1.07, 1.1, t) - smoothstep(1.1, 1.16, t))      # the knock as it seats
		else:
			left_pos = at_mag * (1.0 - smoothstep(1.12, 1.3, t))
		bolt = maxf(bolt, smoothstep(1.3, 1.4, t) * (1.0 - smoothstep(1.45, 1.5, t)))
		pos += Vector3(0, 0, 0.012) * (smoothstep(1.45, 1.5, t) - smoothstep(1.5, 1.62, t))
	pose.position = pos
	pose.rotation = rot
	_smg_bolt.position.z = 0.05 * bolt
	_smg_mag.position = mag_pos
	_smg_mag.visible = mag_visible
	left.position = left_pos
	left.rotation = left_rot


func _build_smg() -> void:
	var root := Node3D.new()
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var steel := _mat(Color(0.14, 0.14, 0.15), 0.35, 0.75)
	var dark := _mat(Color(0.03, 0.03, 0.03), 0.6, 0.2)
	var wood := _mat(Color(0.33, 0.18, 0.08), 0.55, 0.0)
	# receiver tube and barrel jacket, with rows of cooling holes
	_cyl(pose, 0.018, 0.27, Vector3(0, 0.012, -0.05), Vector3(90, 0, 0), steel)
	_cyl(pose, 0.021, 0.21, Vector3(0, 0.012, -0.29), Vector3(90, 0, 0), steel)
	for i in 7:
		for side: float in [-1.0, 0.0, 1.0]:
			var a := side * 0.9
			_box(pose, Vector3(0.008, 0.008, 0.016), Vector3(sin(a) * 0.0205, 0.012 + cos(a) * 0.0205, -0.215 - i * 0.024), Vector3(0, 0, -rad_to_deg(a)), dark)
	_cyl(pose, 0.007, 0.035, Vector3(0, 0.012, -0.415), Vector3(90, 0, 0), dark)                    # muzzle
	_box(pose, Vector3(0.004, 0.012, 0.006), Vector3(0, 0.038, -0.385), Vector3.ZERO, steel)        # front sight
	_box(pose, Vector3(0.018, 0.012, 0.012), Vector3(0, 0.034, 0.03), Vector3.ZERO, steel)          # rear sight
	_cyl(pose, 0.02, 0.012, Vector3(0, 0.012, 0.085), Vector3(90, 0, 0), steel)                    # end cap
	# wooden stock in one piece: fore-end under the receiver, wrist, butt
	_box(pose, Vector3(0.044, 0.036, 0.2), Vector3(0, -0.018, -0.07), Vector3.ZERO, wood)
	_box(pose, Vector3(0.038, 0.07, 0.07), Vector3(0, -0.045, 0.1), Vector3(24, 0, 0), wood)
	_box(pose, Vector3(0.042, 0.085, 0.26), Vector3(0, -0.06, 0.25), Vector3(-6, 0, 0), wood)
	_box(pose, Vector3(0.044, 0.09, 0.012), Vector3(0, -0.07, 0.38), Vector3(-6, 0, 0), steel)      # butt plate
	_box(pose, Vector3(0.012, 0.005, 0.06), Vector3(0, -0.044, 0.04), Vector3.ZERO, steel)         # trigger guard
	_box(pose, Vector3(0.005, 0.02, 0.005), Vector3(0, -0.032, 0.035), Vector3(-15, 0, 0), steel)  # trigger
	# magazine well on the left, and the magazine itself
	_box(pose, Vector3(0.03, 0.034, 0.036), Vector3(-0.028, 0.012, -0.12), Vector3.ZERO, steel)
	_smg_mag = Node3D.new()
	pose.add_child(_smg_mag)
	_box(_smg_mag, Vector3(0.13, 0.026, 0.03), Vector3(-0.1, 0.012, -0.12), Vector3(0, 0, 6), _mat(Color(0.09, 0.09, 0.1), 0.45, 0.6))
	_box(_smg_mag, Vector3(0.012, 0.03, 0.034), Vector3(-0.163, 0.006, -0.12), Vector3(0, 0, 6), steel)
	# the bolt handle on the right, which flicks back with every shot
	_smg_bolt = Node3D.new()
	pose.add_child(_smg_bolt)
	_box(_smg_bolt, Vector3(0.026, 0.008, 0.008), Vector3(0.026, 0.016, 0.0), Vector3.ZERO, steel)
	_cyl(_smg_bolt, 0.007, 0.012, Vector3(0.04, 0.016, 0.0), Vector3(0, 0, 90), steel)
	# hands: right on the wrist of the stock, left round the jacket
	_hand(pose, Vector3(0, -0.06, 0.11), Vector3(0.09, -0.30, 0.48), false)
	var left := Node3D.new()
	pose.add_child(left)
	_hand(left, Vector3(-0.004, -0.022, -0.16), Vector3(-0.28, -0.30, 0.20), true)
	_left.append(left)


# --- stake gun --------------------------------------------------------------------
# A compressed-air stake launcher: a long open rail with the stake lying on it,
# a brass air tank underneath with a pressure gauge, a pump lever, a heavy
# wooden stock. One stake at a time, slow to load.
const K_HOME := Vector3(0.15, -0.165, -0.38)

func _animate_stake() -> void:
	var pose := _pose[STAKE]
	var left := _left[STAKE]
	var k := _kick * _kick
	var pos := K_HOME + Vector3(0, 0.03 * k, 0.11 * k)
	var rot := Vector3(deg_to_rad(14.0) * k, deg_to_rad(-2.0) * k, 0)
	var left_pos := Vector3.ZERO
	var loaded := stake_ready
	var in_hand := false
	var slide := 0.0
	var lever := 0.0
	var needle := 1.0 if stake_ready else 0.15
	if _reload_t >= 0.0:
		var t := _reload_t
		# 0.00-0.30  tip the muzzle up, rail toward you
		# 0.30-0.95  hand down for a stake from the belt and back up with it
		# 0.95-1.50  lay it on the rail and slide it forward till it locks
		# 1.50-2.40  three strokes of the pump lever: the gauge climbs
		# 2.40-2.90  back on target
		var tilt := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(2.4, STAKE_RELOAD, t))
		pos += Vector3(-0.04, 0.05, 0.05) * tilt
		rot += Vector3(deg_to_rad(16.0), deg_to_rad(16.0), deg_to_rad(24.0)) * tilt
		var rail := Vector3(0.0, 0.07, 0.05)                 # where the hand lays the stake down
		if t < 0.95:
			var down := sin(clampf((t - 0.3) / 0.65, 0.0, 1.0) * PI)
			left_pos = rail * smoothstep(0.75, 0.95, t) + Vector3(-0.06, -0.35, 0.15) * down
			in_hand = t > 0.62
			loaded = false
		elif t < STAKE_SEAT:
			var push := smoothstep(1.1, 1.45, t)
			left_pos = rail + Vector3(0, 0, -0.16) * push
			in_hand = false
			loaded = true
			slide = 1.0 - push
		elif t < 2.4:
			var c := clampf((t - STAKE_SEAT) / 0.9, 0.0, 1.0)
			lever = absf(sin(c * PI * 3.0))
			left_pos = Vector3(0.0, -0.05, -0.02) + Vector3(0, -0.07, 0.02) * lever
			needle = 0.15 + 0.85 * c
		else:
			left_pos = Vector3(0.0, -0.05, -0.02) * (1.0 - smoothstep(2.4, 2.65, t))
	pose.position = pos
	pose.rotation = rot
	left.position = left_pos
	_stake_loaded.visible = loaded
	_stake_loaded.position.z = 0.18 * slide
	_stake_in_hand.visible = in_hand
	_stake_lever.rotation.x = deg_to_rad(-38.0) * lever
	_gauge_needle.rotation.x = lerpf(2.2, -2.2, needle)


func _build_stake() -> void:
	var root := Node3D.new()
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var steel := _mat(Color(0.13, 0.13, 0.14), 0.4, 0.75)
	var brass := _mat(Color(0.55, 0.4, 0.17), 0.35, 0.9)
	var wood := _mat(Color(0.28, 0.15, 0.07), 0.6, 0.0)
	var stake_wood := _mat(Color(0.5, 0.36, 0.22), 0.8, 0.0)
	var iron := _mat(Color(0.18, 0.17, 0.16), 0.45, 0.8)
	# the rail: two side bars and a floor, open on top
	_box(pose, Vector3(0.05, 0.012, 0.62), Vector3(0, 0.0, -0.27), Vector3.ZERO, steel)
	for side: float in [-1.0, 1.0]:
		_box(pose, Vector3(0.008, 0.03, 0.62), Vector3(side * 0.024, 0.015, -0.27), Vector3.ZERO, steel)
	_box(pose, Vector3(0.06, 0.05, 0.03), Vector3(0, 0.012, -0.585), Vector3.ZERO, steel)          # muzzle block
	_box(pose, Vector3(0.06, 0.06, 0.1), Vector3(0, 0.0, 0.05), Vector3.ZERO, steel)               # breech / valve
	_cyl(pose, 0.012, 0.03, Vector3(0, 0.04, 0.05), Vector3.ZERO, brass)                           # valve cap
	# brass air tank under the rail, banded, with a gauge on its side
	_cyl(pose, 0.032, 0.36, Vector3(0, -0.05, -0.2), Vector3(90, 0, 0), brass)
	for z: float in [-0.05, -0.35]:
		_cyl(pose, 0.034, 0.012, Vector3(0, -0.05, z), Vector3(90, 0, 0), steel)
	_cyl(pose, 0.022, 0.012, Vector3(-0.038, -0.02, 0.0), Vector3(0, 0, 90), steel)               # gauge body
	_cyl(pose, 0.018, 0.004, Vector3(-0.045, -0.02, 0.0), Vector3(0, 0, 90), _mat(Color(0.85, 0.82, 0.72), 0.6, 0.0))   # face
	_gauge_needle = Node3D.new()
	_gauge_needle.position = Vector3(-0.048, -0.02, 0.0)
	pose.add_child(_gauge_needle)
	_box(_gauge_needle, Vector3(0.002, 0.014, 0.002), Vector3(0, 0.006, 0), Vector3.ZERO, _mat(Color(0.6, 0.05, 0.03), 0.5, 0.0))
	_cyl(pose, 0.006, 0.12, Vector3(0.03, -0.02, 0.06), Vector3(70, 0, 0), _mat(Color(0.08, 0.07, 0.06), 0.9, 0.0))   # hose
	# pump lever under the tank, hinged at the front
	_stake_lever = Node3D.new()
	_stake_lever.position = Vector3(0, -0.085, -0.3)
	pose.add_child(_stake_lever)
	_box(_stake_lever, Vector3(0.02, 0.014, 0.26), Vector3(0, 0, 0.13), Vector3.ZERO, steel)
	_box(_stake_lever, Vector3(0.03, 0.03, 0.07), Vector3(0, -0.01, 0.2), Vector3.ZERO, wood)
	# stock, grip, trigger
	_box(pose, Vector3(0.045, 0.08, 0.3), Vector3(0, -0.05, 0.25), Vector3(-8, 0, 0), wood)
	_box(pose, Vector3(0.036, 0.08, 0.05), Vector3(0, -0.07, 0.12), Vector3(22, 0, 0), wood)
	_box(pose, Vector3(0.012, 0.005, 0.06), Vector3(0, -0.04, 0.07), Vector3.ZERO, steel)
	# the stake on the rail, iron point at the muzzle
	_stake_loaded = Node3D.new()
	pose.add_child(_stake_loaded)
	_cyl(_stake_loaded, 0.014, 0.5, Vector3(0, 0.024, -0.29), Vector3(90, 0, 0), stake_wood)
	_cyl(_stake_loaded, 0.0, 0.08, Vector3(0, 0.024, -0.58), Vector3(-90, 0, 0), iron).mesh.top_radius = 0.0
	(_stake_loaded.get_child(1) as MeshInstance3D).mesh.bottom_radius = 0.017
	# right hand on the grip; left hand under the tank, carrying the next stake
	_hand(pose, Vector3(0, -0.07, 0.13), Vector3(0.09, -0.30, 0.48), false)
	var left := Node3D.new()
	pose.add_child(left)
	_hand(left, Vector3(-0.004, -0.07, -0.12), Vector3(-0.28, -0.32, 0.22), true)
	_stake_in_hand = Node3D.new()
	left.add_child(_stake_in_hand)
	_cyl(_stake_in_hand, 0.014, 0.5, Vector3(0, -0.04, -0.3), Vector3(90, 0, 0), stake_wood)
	_stake_in_hand.visible = false
	_left.append(left)


# --- the Maxim, torn off its mount ------------------------------------------------
# Carried at the hip: right hand on a spade grip, left under the water jacket,
# bucking hard with every round.
const X_HOME := Vector3(0.2, -0.26, -0.22)

func _animate_maxim() -> void:
	var pose := _pose[MAXIM]
	var k := _kick * _kick
	pose.position = X_HOME + Vector3(0.008 * _jitter.x * k, 0.012 * k, 0.05 * k)
	pose.rotation = Vector3(deg_to_rad(3.0) + deg_to_rad(4.0 + 3.0 * _jitter.y) * k, deg_to_rad(5.0) + deg_to_rad(2.5 * _jitter.x) * k, deg_to_rad(2.0 * _jitter.x) * k)


func _build_maxim() -> void:
	var root := Node3D.new()
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 0.6
	pose.add_child(holder)
	MountedGun.build_gun(holder)
	for mi in holder.get_children():
		if mi is MeshInstance3D:
			mi.layers = 2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a leather sling over the shoulder, and the hands
	_box(pose, Vector3(0.02, 0.006, 0.5), Vector3(-0.06, 0.05, 0.1), Vector3(-40, 20, 0), _mat(Color(0.25, 0.16, 0.08), 0.8, 0.0))
	_hand(pose, Vector3(0.07, -0.05, 0.19), Vector3(0.1, -0.3, 0.5), false)
	var left := Node3D.new()
	pose.add_child(left)
	_hand(left, Vector3(-0.01, -0.09, -0.3), Vector3(-0.3, -0.32, 0.12), true)
	_left.append(left)
	root.visible = false


# --- the bolt-action rifle --------------------------------------------------------
# Long, wooden, a turned-down bolt handle on the right. After every shot the
# right hand goes up to the bolt: up, back (the case flies), forward, down.
const R_HOME := Vector3(0.105, -0.155, -0.5)
const R_BOLT_KNOB := Vector3(0.055, 0.022, 0.07)    # where the right hand takes the bolt

func _animate_rifle() -> void:
	var pose := _pose[RIFLE]
	var left := _left[RIFLE]
	var k := _kick * _kick
	var pos := R_HOME + Vector3(0, 0.012 * k, 0.045 * k)
	var rot := Vector3(deg_to_rad(7.0) * k, 0, 0)
	var lift := 0.0          # bolt handle up (0..1)
	var draw := 0.0          # bolt back (0..1)
	var to_bolt := 0.0       # right hand off the grip and on the bolt
	var left_pos := Vector3.ZERO
	var clip := false
	var clip_pos := Vector3.ZERO
	if _cycle_t >= 0.0 and _reload_t < 0.0:
		var t := _cycle_t
		# 0.10-0.22 hand to the bolt; 0.22-0.32 up; 0.32-0.48 back; 0.48-0.64 home; 0.64-0.74 down; back to the grip
		to_bolt = smoothstep(0.08, 0.22, t) * (1.0 - smoothstep(0.74, 0.9, t))
		lift = smoothstep(0.22, 0.32, t) * (1.0 - smoothstep(0.64, 0.74, t))
		draw = smoothstep(0.32, 0.46, t) * (1.0 - smoothstep(0.48, 0.62, t))
		rot += Vector3(0, 0, deg_to_rad(-9.0)) * to_bolt          # rolled over a little to work it
		pos += Vector3(0, 0, 0.012) * (smoothstep(0.32, 0.4, t) - smoothstep(0.4, 0.5, t))
	if _reload_t >= 0.0:
		var t := _reload_t
		# 0.00-0.30 rifle rolled over, bolt up and back
		# 0.30-0.80 left hand down to the pouch for a clip and back up
		# 0.80-1.55 clip into the guide, thumb strips the rounds down
		# 1.55-1.85 empty clip flicked away
		# 1.85-2.15 bolt home and down
		# 2.15-2.50 back on target
		var tilt := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(2.15, RIFLE_RELOAD, t))
		pos += Vector3(-0.05, 0.05, 0.06) * tilt
		rot += Vector3(deg_to_rad(10.0), deg_to_rad(12.0), deg_to_rad(-28.0)) * tilt
		to_bolt = smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(2.15, 2.35, t))
		lift = smoothstep(0.1, 0.2, t) * (1.0 - smoothstep(2.0, 2.12, t))
		draw = smoothstep(0.2, 0.3, t) * (1.0 - smoothstep(1.85, 2.0, t))
		var guide := Vector3(0.0, 0.06, 0.12)                     # just above the open breech
		if t < 0.8:
			var down := sin(clampf((t - 0.3) / 0.5, 0.0, 1.0) * PI)
			left_pos = Vector3(-0.04, -0.3, 0.2) * down + (guide - Vector3(-0.012, -0.05, -0.32)) * smoothstep(0.62, 0.8, t)
			clip = t > 0.52
			clip_pos = Vector3.ZERO
		elif t < RIFLE_SEAT:
			left_pos = guide - Vector3(-0.012, -0.05, -0.32) + Vector3(0, -0.035 * smoothstep(0.95, 1.45, t), 0)
			clip = true
			clip_pos = Vector3(0, -0.035 * smoothstep(0.95, 1.45, t), 0)
		elif t < 1.85:
			var off := smoothstep(RIFLE_SEAT, 1.8, t)
			left_pos = (guide - Vector3(-0.012, -0.05, -0.32)) * (1.0 - off)
			clip = t < 1.62
			clip_pos = Vector3(-0.08, 0.06, 0) * off
	pose.position = pos
	pose.rotation = rot
	_rifle_bolt.rotation.z = deg_to_rad(80.0) * lift
	_rifle_bolt.position.z = 0.09 * draw
	_rifle_rhand.position = (R_BOLT_KNOB + Vector3(0.0, 0.05 * lift, 0.09 * draw) - Vector3(0.0, -0.07, 0.2)) * to_bolt
	left.position = left_pos
	_rifle_clip.visible = clip
	_rifle_clip.position = clip_pos


func _build_rifle() -> void:
	var root := Node3D.new()
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var steel := _mat(Color(0.09, 0.09, 0.1), 0.38, 0.8)
	var blued := _mat(Color(0.06, 0.065, 0.08), 0.3, 0.85)
	var wood := _mat(Color(0.33, 0.17, 0.07), 0.55, 0.0)
	var brass := _mat(Color(0.6, 0.45, 0.18), 0.3, 0.9)
	# the stock runs the length of it: butt, wrist, fore-end, a hand guard on top
	_box(pose, Vector3(0.04, 0.1, 0.24), Vector3(0, -0.055, 0.33), Vector3(-6, 0, 0), wood)            # butt
	_box(pose, Vector3(0.034, 0.05, 0.14), Vector3(0, -0.03, 0.17), Vector3(10, 0, 0), wood)           # wrist
	_box(pose, Vector3(0.038, 0.045, 0.62), Vector3(0, -0.012, -0.34), Vector3.ZERO, wood)             # fore-end
	_box(pose, Vector3(0.03, 0.016, 0.42), Vector3(0, 0.022, -0.36), Vector3.ZERO, wood)               # hand guard
	_box(pose, Vector3(0.042, 0.012, 0.03), Vector3(0, -0.012, -0.1), Vector3.ZERO, steel)             # band
	_box(pose, Vector3(0.042, 0.012, 0.03), Vector3(0, -0.012, -0.58), Vector3.ZERO, steel)            # band
	# receiver, barrel, front sight, the magazine well and trigger guard
	_cyl(pose, 0.017, 0.2, Vector3(0, 0.02, 0.04), Vector3(90, 0, 0), blued)
	_cyl(pose, 0.009, 0.4, Vector3(0, 0.03, -0.73), Vector3(90, 0, 0), blued)
	_box(pose, Vector3(0.004, 0.02, 0.012), Vector3(0, 0.048, -0.9), Vector3.ZERO, steel)
	_box(pose, Vector3(0.026, 0.008, 0.05), Vector3(0, 0.044, -0.06), Vector3.ZERO, steel)             # rear sight
	_box(pose, Vector3(0.03, 0.04, 0.07), Vector3(0, -0.03, 0.02), Vector3.ZERO, steel)
	_box(pose, Vector3(0.008, 0.03, 0.06), Vector3(0, -0.06, 0.08), Vector3(0, 0, 0), steel)
	# the bolt: a sleeve along the receiver and the turned-down handle
	_rifle_bolt = Node3D.new()
	_rifle_bolt.position = Vector3(0.0, 0.022, 0.07)
	pose.add_child(_rifle_bolt)
	_cyl(_rifle_bolt, 0.013, 0.1, Vector3(0, 0, 0.0), Vector3(90, 0, 0), steel)
	_cyl(_rifle_bolt, 0.005, 0.055, Vector3(0.028, -0.012, 0.0), Vector3(0, 0, 65), steel)
	_add(_rifle_bolt, SphereMesh.new(), Vector3(0.052, -0.024, 0.0), Vector3.ZERO, steel).scale = Vector3.ONE * 0.022
	# a sling swivel and a bit of sling
	_box(pose, Vector3(0.012, 0.004, 0.3), Vector3(-0.022, -0.05, -0.15), Vector3(0, 0, 0), _mat(Color(0.28, 0.2, 0.1), 0.85, 0.0))
	# right hand on the wrist (it goes up to the bolt between shots)
	_rifle_rhand = Node3D.new()
	pose.add_child(_rifle_rhand)
	_hand(_rifle_rhand, Vector3(0, -0.07, 0.2), Vector3(0.1, -0.3, 0.52), false)
	# left hand under the fore-end, with a stripper clip of five when reloading
	var left := Node3D.new()
	pose.add_child(left)
	_hand(left, Vector3(-0.004, -0.06, -0.32), Vector3(-0.28, -0.33, 0.06), true)
	_rifle_clip = Node3D.new()
	left.add_child(_rifle_clip)
	# the clip sits in the fingertips, rounds standing up out of it
	_box(_rifle_clip, Vector3(0.016, 0.006, 0.062), Vector3(0.0, 0.0, -0.345), Vector3.ZERO, steel)
	for i in 5:
		_cyl(_rifle_clip, 0.0045, 0.06, Vector3(0.0, 0.03, -0.369 + i * 0.012), Vector3.ZERO, brass)
	_rifle_clip.visible = false
	_left.append(left)
	root.visible = false


func _muzzle() -> Vector3:
	if weapon == REVOLVER:
		return to_local(_rev_muzzle.global_position)
	var local := [Vector3(0, 0.02, -0.19), Vector3(0, 0.018, -0.64), Vector3(0, 0.012, -0.445), Vector3(0, 0.03, -0.6), Vector3(0, 0.0, -0.76), Vector3(0, 0.03, -0.93)][weapon] as Vector3
	return to_local(_pose[weapon].to_global(local))


# --- first-person arms (the rigged Tripo WW1 arms, FPArm) ---------------------------
# Each weapon that uses them says where each hand goes and how it is shaped, in
# that weapon's own model space (so the numbers follow the model, not the view):
#   index_k, little_k - where the index and little-finger knuckles go; or
#   wrist, along - the wrist (hand bone origin) and which way the hand runs
#   palm   - which way the palm faces
#   elbow  - where the forearm comes from; the wrist bends to suit
#   pose   - FPArm finger pose (bone -> degrees, +X curls toward the palm)
#   pull   - added to the pose by the trigger pull (0..1), trigger hand only
#   away   - for the support hand: where it goes (offset in metres, in the
#            view's space) when it lets go (reloads)
# Guns not listed keep their own procedural hands; the procedural pistol is one.
const ARM_GRIPS := {
	REVOLVER: {
		"R": {"index_k": Vector3(-0.255, 0.36, 0.11), "little_k": Vector3(-0.40, 0.06, 0.12), "palm": Vector3(0.0, 0.0, -1.0), "elbow": Vector3(-1.9, -0.6, 0.55),
			"pose": {"index_01": Vector3(-26, 0, -20), "index_02": Vector3(60, 0, 0), "index_03": Vector3(20, 0, 0),
			"middle_01": Vector3(36, 0, 0), "middle_02": Vector3(60, 0, 0), "middle_03": Vector3(27, 0, 0),
			"ring_01": Vector3(40, 0, 0), "ring_02": Vector3(25, 0, 0), "ring_03": Vector3(19, 0, 0),
			"little_01": Vector3(16, 0, 0), "little_02": Vector3(95, 0, 0), "little_03": Vector3(43, 0, 0),
			"thumb_01": Vector3(-20, 0, 0), "thumb_02": Vector3(10, 0, 0), "thumb_03": Vector3(0, 0, 0)},
			"pull": {"index_01": Vector3(8, 0, 0), "index_02": Vector3(15, 0, 0), "index_03": Vector3(10, 0, 0)}},
		"L": {"wrist": Vector3(-0.50, -0.02, -0.17), "along": Vector3(0.25, 0.15, 0.95), "palm": Vector3(0.0, 1.0, 0.0), "elbow": Vector3(-1.5, -1.0, -0.8),
			"pose": {"index_01": Vector3(60, 0, 0), "index_02": Vector3(70, 0, 0), "index_03": Vector3(40, 0, 0),
			"middle_01": Vector3(62, 0, 0), "middle_02": Vector3(70, 0, 0), "middle_03": Vector3(40, 0, 0),
			"ring_01": Vector3(64, 0, 0), "ring_02": Vector3(70, 0, 0), "ring_03": Vector3(40, 0, 0),
			"little_01": Vector3(66, 0, 0), "little_02": Vector3(68, 0, 0), "little_03": Vector3(40, 0, 0),
			"thumb_01": Vector3(10, 0, 0), "thumb_02": Vector3(10, 0, 0), "thumb_03": Vector3(10, 0, 0)},
			"away": Vector3(-0.12, -0.28, 0.12)}
	},
}
## The arms each gun is using: gun index -> {"R": FPArm, "L": FPArm}
var _arms := {}
## Where the support hand sits on its gun (the pose node's space), so it can let go and come back.
var _arm_home := {}


## Build and place the arms a gun asks for (ARM_GRIPS), under its pose node, so
## they follow everything the gun does. `model` is the node the grip numbers are in.
func _build_arms(gun: int, pose: Node3D, model: Node3D) -> void:
	if not ARM_GRIPS.has(gun) or not FPArm.exists("R"):
		return
	var arms := {}
	for side: String in ARM_GRIPS[gun]:
		var arm := FPArm.new(side)
		pose.add_child(arm)
		arms[side] = arm
	_arms[gun] = arms
	apply_grip(gun, ARM_GRIPS[gun], model)


## Put the hands of `gun` where `grip` says (also used to tune grips by hand).
func apply_grip(gun: int, grip: Dictionary, model: Node3D) -> void:
	var xf := model.transform
	for side: String in grip:
		var g: Dictionary = grip[side]
		var arm: FPArm = _arms[gun][side]
		var hand: Transform3D
		if g.has("index_k"):
			hand = arm.frame_from_knuckles(xf * g.index_k, xf * g.little_k, xf.basis * g.palm)
		else:
			hand = FPArm.frame(xf * g.wrist, xf.basis * g.along, xf.basis * g.palm)
		arm.set_pose(g.pose)
		if g.has("elbow"):
			arm.place(hand, xf * g.elbow)            # forearm back toward the elbow, the wrist bent to suit
		else:
			arm.place_hand(hand)
		_arm_home[arm] = arm.transform
	_grips_live[gun] = grip
var _grips_live := {}
var _arm_pull_last := -1.0


## The trigger finger follows the pull (0..1).
func _arm_trigger(gun: int, pull: float) -> void:
	if not _arms.has(gun) or absf(pull - _arm_pull_last) < 0.002:
		return
	_arm_pull_last = pull
	var g: Dictionary = _grips_live[gun]["R"]
	if not g.has("pull"):
		return
	var pose: Dictionary = g.pose.duplicate()
	for b: String in g.pull:
		pose[b] = pose.get(b, Vector3.ZERO) + g.pull[b] * pull
	(_arms[gun]["R"] as FPArm).set_pose(pose)


## The support hand lets go (0) or holds on (1), eased.
func _arm_support(gun: int, hold: float) -> void:
	if not _arms.has(gun) or not _arms[gun].has("L"):
		return
	var arm: FPArm = _arms[gun]["L"]
	var g: Dictionary = _grips_live[gun]["L"]
	var home: Transform3D = _arm_home[arm]
	var away: Vector3 = g.get("away", Vector3(0, -0.3, 0.1))
	var k := 1.0 - hold
	arm.transform = Transform3D(home.basis.rotated(Vector3.RIGHT, -0.6 * k).orthonormalized(), home.origin + away * k)
	arm.visible = k < 0.98


# --- the revolver (Tripo model, split into parts) ------------------------------------
# A WW1 top-break service revolver. `revolver_parts.glb` is the Tripo model cut
# into its working parts in Blender (see claude/revolver-breakdown.md): the frame,
# the barrel assembly on its hinge pin, a rebuilt six-chamber cylinder riding
# with the barrel, the extractor star, six rounds and six fired cases, and the
# hammer and trigger on their own pivots. All in the original model's space, so
# placement, scale and the bore are unchanged. If the parts file is missing the
# fused `revolver.glb` is used and only the whole gun moves (the old reload).
# Held one-handed low on the right, no hands yet.
const V_HOME := Vector3(0.2, -0.165, -0.45)
## Canted in a little (top toward the middle of the screen) and turned in a
## touch so the left flank, cylinder and frame show, the bore converging on
## the crosshair a few metres out.
const V_TILT := Vector3(2.0, 6.0, 9.0)
## The model is about a metre long; a Webley Mk VI is 0.286 m.
const V_SCALE := 0.29
## The bore at the muzzle, in the model's own units (it points down +X).
const V_BORE := Vector3(0.49, 0.572, 0.0)
const V_PARTS := "res://art/weapons/revolver/revolver_parts.glb"
const V_FUSED := "res://art/weapons/revolver/revolver.glb"
## How the parts move (model space, Y up, X along the barrel):
const V_OPEN := -68.0          # barrel on the hinge, degrees about Z (negative: muzzle down)
const V_EJECT := -0.032        # extractor stroke along the cylinder axis
const V_COCK := 45.0           # hammer, degrees about Z (positive: spur back)
const V_PULL := -12.0          # trigger, degrees about Z (negative: blade back)
# The reload, seconds (REVOLVER_RELOAD 3.0; the rounds count at REVOLVER_SEAT 2.35):
const V_T_OPEN := Vector2(0.15, 0.5)      # barrel falls open
const V_T_EJECT := Vector2(0.42, 0.5)     # extractor throws everything out at the end of the opening
const V_T_BACK := Vector2(0.52, 0.62)     # and snaps back
const V_T_LOAD := Vector2(0.75, 2.1)      # six rounds in, one after another
const V_T_CLOSE := Vector2(2.2, 2.34)     # snapped shut (the rounds count at 2.35)

var _rev_muzzle: Node3D
var _rev_model: Node3D
var _rv_parts := false
var _rv_barrel: Node3D
var _rv_cyl: Node3D
var _rv_ext: Node3D
var _rv_hammer: Node3D
var _rv_trigger: Node3D
var _rv_rounds: Array[Node3D] = []
var _rv_cases: Array[Node3D] = []
var _rv_round_x: Array[float] = []
## Which chambers hold a live round (the rest hold a fired case).
var rv_live: Array[bool] = [true, true, true, true, true, true]
## Shots since the cylinder was at 0: the chamber under the hammer is rv_index % 6.
var rv_index := 0
var _rv_cyl_from := 0.0
var _rv_cyl_t := 9.0
var _rv_cyl_len := 0.07
## A double-action pull: seconds into it (-1 when not pulling) and how long it takes.
var _rv_pull_t := -1.0
var _rv_pull_len := 0.08
var _rv_thrown := false
var _rv_clicked := 0
## Brass thrown out by the last reload (for the tests).
var rv_spent: Array[RigidBody3D] = []

## The cylinder turns one chamber: during the pull, or on the shot if there was none.
func _rv_turn() -> void:
	_rv_cyl_from = _rv_cyl.rotation.x
	rv_index += 1
	_rv_cyl_t = 0.0
	_rv_cyl_len = _rv_pull_len * 0.8 if _rv_pull_t >= 0.0 else 0.07


func _revolver_fired() -> void:
	if not _rv_parts:
		return
	if _rv_pull_t < 0.0:
		_rv_turn()                               # no pull (pull = 0): turn on the shot
	_rv_pull_t = -1.0
	rv_live[rv_index % 6] = false                # the chamber under the hammer


func _animate_revolver() -> void:
	var pose := _pose[REVOLVER]
	var k := _kick * _kick
	# the kick: up and back hard, a little twist
	var pos := V_HOME + Vector3(0.0, 0.02 * k, 0.05 * k)
	var rot := V_TILT * (PI / 180.0) + Vector3(deg_to_rad(16.0) * k, deg_to_rad(-1.5) * k, deg_to_rad(randf_range(-0.8, 0.8)) * k)
	if _reload_t >= 0.0 and not _rv_parts:
		_animate_revolver_fused(_reload_t, pos, rot, pose)
		return
	if _reload_t >= 0.0:
		var t := _reload_t
		# the wrist turns the gun over a little to watch the breech (the mechanism does the work)
		var present := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(2.25, 2.7, t))
		pos += Vector3(-0.05, 0.015, 0.05) * present
		rot += Vector3(deg_to_rad(12.0), deg_to_rad(22.0), deg_to_rad(-30.0)) * present
		# closing: the snap jolts the hand
		var snap := smoothstep(2.28, 2.31, t) * (1.0 - smoothstep(2.31, 2.5, t))
		rot += Vector3(deg_to_rad(5.0), 0, 0) * snap
	pose.position = pos
	pose.rotation = rot
	if _rv_parts:
		_animate_revolver_parts()


func _animate_revolver_parts() -> void:
	var dt := get_process_delta_time()
	var t := _reload_t
	# barrel on its hinge
	var open := 0.0
	if t >= 0.0:
		var o := smoothstep(V_T_OPEN.x, V_T_OPEN.y, t)
		var c := smoothstep(V_T_CLOSE.x, V_T_CLOSE.y, t)
		open = o * (1.0 - c * c)                 # opens easy, shuts fast
	_rv_barrel.rotation.z = deg_to_rad(V_OPEN) * open
	# extractor: out at the end of the opening, snaps back
	var ex := 0.0
	if t >= 0.0:
		ex = smoothstep(V_T_EJECT.x, V_T_EJECT.y, t) * (1.0 - smoothstep(V_T_BACK.x, V_T_BACK.y, t))
		if t >= V_T_EJECT.y - 0.02 and not _rv_thrown:
			_rv_thrown = true
			_throw_brass()
	_rv_ext.position.x = V_EJECT * ex
	# cylinder: a quick turn of one chamber per shot
	_rv_cyl_t += dt
	var target := float(rv_index % 6) * PI / 3.0
	var from := _rv_cyl_from
	if target < from - 0.01:
		from -= TAU                              # always turn the same way
	_rv_cyl.rotation.x = lerpf(from, target, smoothstep(0.0, _rv_cyl_len, _rv_cyl_t))
	# the pull: trigger back, hammer up to full cock; on the shot the hammer
	# falls (a couple of frames) and the trigger goes forward again
	var h := 0.0
	var pull := 0.0
	if _rv_pull_t >= 0.0:
		_rv_pull_t += dt
		var k := smoothstep(0.0, _rv_pull_len, _rv_pull_t)
		h = k
		pull = k
	elif _since_shot < 0.25 and _reload_t < 0.0:
		h = 1.0 - smoothstep(0.0, 0.03, _since_shot)
		pull = 1.0 - smoothstep(0.03, 0.22, _since_shot)
	_rv_hammer.rotation.z = deg_to_rad(V_COCK) * h
	_rv_trigger.rotation.z = deg_to_rad(V_PULL) * pull
	_arm_trigger(REVOLVER, pull)
	# the support hand lets go for the reload and takes hold again after the snap shut
	var hold := 1.0
	if t >= 0.0:
		hold = 1.0 - smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(2.35, 2.75, t))
	_arm_support(REVOLVER, hold)
	# rounds and cases
	for c in 6:
		var live := rv_live[c]
		var shown_round := live
		var shown_case := not live
		var slide := 0.0
		if t >= 0.0 and _rv_thrown:
			# out and gone; then the new ones go in, one after another, from the top chamber round
			var order := (c - rv_index % 6 + 6) % 6
			var step := (V_T_LOAD.y - V_T_LOAD.x) / 6.0
			var t0 := V_T_LOAD.x + order * step
			shown_case = false
			shown_round = t >= t0
			slide = 1.0 - smoothstep(t0, t0 + step * 0.75, t)
			if t >= t0 + step * 0.75 and _rv_clicked <= order:
				_rv_clicked = order + 1
				SfxSynth.play(self, "dry_click", _rv_rounds[c].global_position, -20.0, randf_range(1.3, 1.6))
		_rv_rounds[c].visible = shown_round
		_rv_cases[c].visible = shown_case
		_rv_rounds[c].position.x = _rv_round_x[c] - 0.09 * slide     # from behind the cylinder, along its axis


## The reload has put six live rounds in (called at REVOLVER_SEAT by the player's
## timing, and here when the view's own clock passes it).
func revolver_loaded() -> void:
	for c in 6:
		rv_live[c] = true


func _revolver_reset_reload() -> void:
	_rv_pull_t = -1.0
	_rv_thrown = false
	_rv_clicked = 0


## Everything in the cylinder goes: fired cases and any live rounds left, out of
## the gun as real bodies, at full size where they would be in the world (the
## view model is drawn shrunk toward the camera).
func _throw_brass() -> void:
	SfxSynth.play(self, "brass", global_position, -10.0, randf_range(0.95, 1.05))
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene
	if cam == null or scene == null:
		return
	var eye := cam.global_position
	rv_spent.clear()
	for c in 6:
		var src := _rv_cases[c] if not rv_live[c] else _rv_rounds[c]
		var mi := src as MeshInstance3D
		if mi == null:
			continue
		var g := mi.global_transform
		var aabb := mi.mesh.get_aabb()
		var centre_local := aabb.get_center()
		var at := eye + (g * centre_local - eye) / SHRINK
		var body := RigidBody3D.new()
		body.collision_layer = 1 << 3
		body.collision_mask = 1 | (1 << 3)
		body.mass = 0.012
		body.continuous_cd = true
		body.angular_damp = 0.8
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.45
		pm.friction = 0.5
		body.physics_material_override = pm
		var len_real := aabb.size.x * V_SCALE
		var r_real := maxf(aabb.size.y, aabb.size.z) * 0.5 * V_SCALE
		var shape := CylinderShape3D.new()
		shape.radius = r_real
		shape.height = len_real
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.rotation.z = PI * 0.5                  # the cylinder shape stands on Y; the case lies along its X
		body.add_child(cs)
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.scale = Vector3.ONE * V_SCALE
		copy.position = -centre_local * V_SCALE
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.add_child(copy)
		body.add_to_group("spent_brass")
		scene.add_child(body)
		body.global_transform = Transform3D(g.basis.orthonormalized(), at)
		# out along the cylinder axis (back toward the shooter, up off the tipped barrel), spread, down
		var out := -g.basis.x.normalized()
		body.linear_velocity = out * randf_range(0.9, 1.4) + cam.global_basis.x * randf_range(0.2, 0.6) + Vector3(0, randf_range(-0.3, 0.3), 0)
		body.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		rv_spent.append(body)
		body.contact_monitor = true
		body.max_contacts_reported = 1
		var hits := [0]
		body.body_entered.connect(func(_b: Node) -> void:
			if hits[0] < 3 and body.linear_velocity.length() > 0.4:
				hits[0] += 1
				SfxSynth.play(body, "brass_tink", body.global_position, -14.0 - hits[0] * 4.0, randf_range(0.85, 1.25)))
		get_tree().create_timer(25.0).timeout.connect(body.queue_free)
	# keep the floor from filling up
	var all := get_tree().get_nodes_in_group("spent_brass")
	for i in maxi(all.size() - 72, 0):
		all[i].queue_free()


## The fused model has no moving parts: the whole gun tips down and in instead.
func _animate_revolver_fused(t: float, pos: Vector3, rot: Vector3, pose: Node3D) -> void:
	var down := smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(2.2, 2.45, t))
	pos += Vector3(-0.07, -0.06, 0.07) * down
	rot += Vector3(deg_to_rad(-55.0), deg_to_rad(28.0), deg_to_rad(-20.0)) * down
	var snap := smoothstep(2.25, 2.32, t) * (1.0 - smoothstep(2.32, 2.6, t))
	rot += Vector3(deg_to_rad(9.0), 0, 0) * snap
	pose.position = pos
	pose.rotation = rot


func _build_revolver() -> void:
	var root := Node3D.new()
	root.name = "Revolver"
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	# Model +X is the muzzle: turn it to point down -Z, and place it so the
	# bore runs at the height the other guns' sights do, the grip under the hand.
	var path := V_PARTS if ResourceLoader.exists(V_PARTS) else V_FUSED
	_rev_model = (load(path) as PackedScene).instantiate() as Node3D
	_rev_model.name = "Model"
	_rev_model.basis = Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * V_SCALE)
	_rev_model.position = Vector3(0, 0.02, -0.21) - _rev_model.basis * V_BORE
	pose.add_child(_rev_model)
	for mi in _rev_model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 2                 # keeps blood decals off the gun
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rev_muzzle = Node3D.new()
	_rev_muzzle.name = "Muzzle"
	_rev_muzzle.position = V_BORE + Vector3(0.02, 0, 0)    # just out of the bore
	_rev_model.add_child(_rev_muzzle)
	_rv_barrel = _rev_model.find_child("BarrelAssembly", true, false)
	_rv_parts = _rv_barrel != null
	if _rv_parts:
		_rv_cyl = _rev_model.find_child("Cylinder", true, false)
		_rv_ext = _rev_model.find_child("Extractor", true, false)
		_rv_hammer = _rev_model.find_child("Hammer", true, false)
		_rv_trigger = _rev_model.find_child("Trigger", true, false)
		for c in 6:
			_rv_rounds.append(_rev_model.find_child("Round_%d" % (c + 1), true, false))
			_rv_cases.append(_rev_model.find_child("Case_%d" % (c + 1), true, false))
			_rv_round_x.append(_rv_rounds[c].position.x)
			_rv_cases[c].visible = false
	# the rigged WW1 arms (if they are in the project): right hand on the grip,
	# left hand under it in support
	_build_arms(REVOLVER, pose, _rev_model)
	# the per-gun left-arm slot (procedural hands' left arm): empty for the revolver
	var left := Node3D.new()
	pose.add_child(left)
	_left.append(left)
	root.visible = false


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
