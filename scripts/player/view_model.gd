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
const TRENCH := 7
const MP18 := 8

## Seconds the reload animations take. The player script reads these.
const PISTOL_RELOAD := 1.55
const SHELL_TIME := 0.48
const SHELL_INTRO := 0.3
const SWAP_TIME := 0.3
const SMG_RELOAD := 1.9
const SMG_SEAT := 1.12          # the new magazine clicks home
const STAKE_RELOAD := 2.9
const STAKE_SEAT := 1.5         # the new stake is on the rail
const RIFLE_CYCLE := 0.95       # working the bolt after a shot (the SMLE: see L_CYCLE)
const REVOLVER_RELOAD := 3.0    # broken open, the extractor throws everything out, six in, snapped shut
const REVOLVER_SEAT := 2.35     # the rounds are in (the frame snaps shut)
const MP18_RELOAD := 3.4        # (the Snail Drum upgrade) empty drum out sideways, a full one fetched and seated
const MP18_SEAT := 2.45         # the new drum is home
const MP18_STICK_RELOAD := 2.85 # the 20-round stick: drawn out, dropped, a fresh one pushed in and slapped
const MP18_STICK_SEAT := 1.95

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
	_build_trench()
	_build_mp18()
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
	_flash.light_energy = [5.0, 9.0, 4.0, 1.5, 8.0, 8.0, 10.0, 11.0, 6.0][weapon]
	_flash_mesh.position = muzzle
	_flash_mesh.scale = Vector3.ONE * [1.0, 1.8, 0.9, 2.4, 2.2, 2.0, 1.9, 2.3, 1.2][weapon] * randf_range(0.7, 1.25)
	if weapon == RIFLE:
		_cycle_t = 0.0
	if weapon == REVOLVER:
		_revolver_fired()
	if weapon == TRENCH:
		_trench_fired()
	if weapon == MP18:
		_mp_fired()
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
	_mp_charge = mp_bolt_forward
	if weapon == REVOLVER:
		_revolver_reset_reload()


func stop_reload() -> void:
	_reload_t = -1.0
	_le_reset()
	_mp_reset_reload()
	_revolver_reset_reload()


## Shell-by-shell loading: the lead-in before the first shell, and each shell after.
func shell_intro() -> float:
	return T_SHELL_INTRO if weapon == TRENCH else SHELL_INTRO


func shell_time() -> float:
	return T_SHELL_TIME if weapon == TRENCH else SHELL_TIME


## A shell has gone into the tube (the shotguns load one at a time).
func shell_loaded() -> void:
	if weapon == TRENCH:
		_sg_shell_in = true


func reloading() -> bool:
	return _reload_t >= 0.0


func swap_to(w: int) -> void:
	if w == weapon and _swap_t < 0.0:
		return
	_swap_to = w
	_swap_t = 0.0
	_reload_t = -1.0
	_cycle_t = -1.0
	_le_reset()
	_mp_reset_reload()
	_revolver_reset_reload()


func swapping() -> bool:
	return _swap_t >= 0.0


## `speed` is how fast the player is walking; `look` is this frame's mouse movement.
var _frame_dt := 0.016


func animate(delta: float, speed: float, look: Vector2) -> void:
	_frame_dt = delta
	_time += delta
	_since_shot += delta
	_kick = move_toward(_kick, 0.0, delta * [7.0, 3.2, 14.0, 2.2, 11.0, 3.0, 3.6, 2.6, 12.0][weapon])
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
	var steady := 1.0 - 0.85 * (ads if weapon == RIFLE else 0.0)          # aimed: the sway and bob mostly go
	root.position = (bob + breathe + Vector3(_sway.x, _sway.y, 0)) * steady + Vector3(0, -drop * 0.35, 0)
	root.rotation = Vector3(-drop * 0.9 + _sway.y * 1.2 * steady, _sway.x * 1.5 * steady, _sway.x * 0.8 * steady)

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
	elif weapon == TRENCH:
		_animate_trench()
	elif weapon == MP18:
		_animate_mp18()
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


# --- the bolt-action rifle: a WW1 Lee-Enfield SMLE Mk III ----------------------------------
# art/weapons/smle/smle.glb, built from the untouched Tripo model by
# art/weapons/smle/source/build_smle.py (claude/smle.md): Body (stock, receiver with an
# open bolt-way, charger bridge, sights) and the bolt: Bolt (slides) carrying BoltTurn
# (turns about the bore: body, rib, lug, head, handle, knob) and CockingPiece (slides
# only). Markers: Muzzle, SightRear, SightFront, Ejection, ChargerGuide, MagMouth, Knob.
# Metres, +X the muzzle, +Y up, +Z the right side. Shouldered, real size.
const L_PATH := "res://art/weapons/smle/smle.glb"
const L_HOME := Vector3(0.105, -0.150, -0.46)
const L_TILT := Vector3(0.0, 2.0, 2.5)
const L_BORE_Y := 0.1917
const L_TRAVEL := 0.0832                 # the bolt's stroke
const L_LIFT := 60.0                     # the handle turned up to unlock (degrees about the bore)
const L_EYE := 0.52                      # aiming: the eye behind the rear notch (view space, before the shrink): just behind the cocking piece
## Working the bolt after a shot (s): the right hand off the wrist to the knob, up,
## back (the case flies), forward (a round chambered), down, back to the wrist.
const L_CYCLE := {"to_knob": Vector2(0.05, 0.19), "up": Vector2(0.19, 0.28), "back": Vector2(0.28, 0.43), "eject": Vector2(0.38, 0.0),
	"fwd": Vector2(0.48, 0.62), "down": Vector2(0.62, 0.71), "to_grip": Vector2(0.71, 0.92)}
## The reload's steps (s). Built per reload from how many chargers and loose rounds it needs.
const L_STEP := {"open": 0.55, "fetch": 0.55, "seat": 0.14, "press": 0.45, "strip": 0.2, "fetch_round": 0.45, "press_round": 0.3, "close": 0.62, "settle": 0.2}
const L_POUCH := Vector3(0.20, -0.48, 0.12)          # the right hand at the belt (pose space)
const L_ROUND_GAP := 0.0116                          # rounds stacked in a charger
var ads := 0.0                                       # set by the player: 0 hip .. 1 aimed
var _le_model: Node3D
var _le_muzzle: Node3D
var _le_bolt: Node3D
var _le_turn: Node3D
var _le_cock: Node3D
var _le_bolt_rest := Vector3.ZERO
var _le_cock_rest := Vector3.ZERO
var _le_mark := {}                                   # marker name -> position (model space)
var _le_knob_rel := Vector3.ZERO                     # the knob's centre in the bolt's space, handle down
var _le_charger: Node3D                              # a five-round charger (the rounds are its children)
var _le_round: Node3D                                # a loose round in the hand
var _le_top: Node3D                                  # the top round in the magazine (seen with the bolt open)
var _le_plan: Array = []                             # this reload's steps: {kind, t0, t1, ...}
var _le_events: Array = []                           # [time, rounds] the player counts in
var _le_total := 0.0
var _le_done := {}                                   # one-shot things this cycle or reload has done
var _le_hand_r := false                              # the right hand is off the wrist (keys applied)
var _le_last_key: Array = []                         # the right hand's key last frame (each step blends from it)
var le_lift := 0.0                                   # the bolt as drawn this frame (for the tests)
var le_draw := 0.0
var le_rounds_in_mag := 0                            # set by the player (rounds below the bolt, for the top round)
var le_spent: Array[RigidBody3D] = []                # cases and chargers thrown (for the tests)


func _build_rifle() -> void:
	var root := Node3D.new()
	root.name = "SMLE"
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var left := Node3D.new()
	pose.add_child(left)
	_left.append(left)
	root.visible = false
	if not ResourceLoader.exists(L_PATH):
		return
	_le_model = (load(L_PATH) as PackedScene).instantiate() as Node3D
	_le_model.name = "Model"
	_le_model.basis = Basis(Vector3.UP, PI * 0.5)
	_le_model.position = Vector3(0, 0.018 - L_BORE_Y, -0.04)
	pose.add_child(_le_model)
	for mi in _le_model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 2
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in ["Muzzle", "SightRear", "SightFront", "Ejection", "ChargerGuide", "MagMouth"]:
		var node := _le_model.find_child(n, true, false) as Node3D
		_le_mark[n] = node.position if node else Vector3.ZERO
	_le_muzzle = _le_model.find_child("Muzzle", true, false) as Node3D
	_le_bolt = _le_model.find_child("Bolt", true, false) as Node3D
	_le_turn = _le_model.find_child("BoltTurn", true, false) as Node3D
	_le_cock = _le_model.find_child("CockingPiece", true, false) as Node3D
	var knob := _le_model.find_child("Knob", true, false) as Node3D
	if _le_bolt:
		_le_bolt_rest = _le_bolt.position
	if _le_cock:
		_le_cock_rest = _le_cock.position
	if knob:
		_le_knob_rel = knob.position
	# the charger, a loose round and the magazine's top round (.303: 77 mm long)
	_le_charger = Node3D.new()
	_le_model.add_child(_le_charger)
	var clip_m := _mat(Color(0.12, 0.12, 0.13), 0.5, 0.8)
	_box(_le_charger, Vector3(0.004, 0.064, 0.016), Vector3(-0.002, 0.026, 0), Vector3.ZERO, clip_m)      # the strip the rims slide in
	for k in 5:
		var r := _le_cartridge()
		r.position = Vector3(0, k * L_ROUND_GAP, 0)
		r.name = "R%d" % k
		_le_charger.add_child(r)
	_le_charger.visible = false
	_le_round = _le_cartridge()
	_le_model.add_child(_le_round)
	_le_round.visible = false
	_le_top = _le_cartridge()
	_le_model.add_child(_le_top)
	_le_top.position = Vector3(_le_mark.ChargerGuide.x + 0.003, L_BORE_Y - 0.0105, 0)
	_le_top.visible = false
	for n: Node3D in [_le_charger, _le_round, _le_top]:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = 2
	_build_arms(RIFLE, pose, _le_model)


## The knob's centre in the bolt's space with the handle down (for the tests).
func _knob_local() -> Vector3:
	return _le_knob_rel


## A .303 round: rim at the origin, the bullet out along +X (77 mm).
func _le_cartridge() -> Node3D:
	var n := Node3D.new()
	var brass := _brass_mat()
	var lead := _mat(Color(0.55, 0.38, 0.22), 0.4, 0.85)       # cupro-nickel jacket, dirty
	_cyl(n, 0.0068, 0.0015, Vector3(0.0008, 0, 0), Vector3(0, 0, 90), brass)         # rim
	_cyl(n, 0.0059, 0.046, Vector3(0.0245, 0, 0), Vector3(0, 0, 90), brass)          # case
	_cyl(n, 0.0042, 0.008, Vector3(0.0515, 0, 0), Vector3(0, 0, 90), brass)          # shoulder and neck
	var b := _cyl(n, 0.0039, 0.020, Vector3(0.0655, 0, 0), Vector3(0, 0, 90), lead)  # the bullet
	(b.mesh as CylinderMesh).top_radius = 0.0012
	return n


## How long this reload will take, and when its rounds go in: `chargers` five-round
## chargers then `loose` single rounds; `extract`: a live round is in the chamber and
## comes out when the bolt opens. Returns [[time, rounds], ...].
func start_rifle_reload(chargers: int, loose: int, extract: bool) -> Array:
	_reload_t = 0.0
	_le_plan = []
	_le_events = []
	_le_done = {}
	var t := 0.0
	_le_plan.append({"kind": "open", "t0": t, "t1": t + L_STEP.open, "extract": extract})
	t += L_STEP.open
	for i in chargers:
		_le_plan.append({"kind": "fetch", "t0": t, "t1": t + L_STEP.fetch, "what": "charger"})
		t += L_STEP.fetch
		_le_plan.append({"kind": "seat", "t0": t, "t1": t + L_STEP.seat})
		t += L_STEP.seat
		_le_plan.append({"kind": "press", "t0": t, "t1": t + L_STEP.press})
		t += L_STEP.press
		_le_events.append([t - 0.02, 5])
		_le_plan.append({"kind": "strip", "t0": t, "t1": t + L_STEP.strip})
		t += L_STEP.strip
	for i in loose:
		_le_plan.append({"kind": "fetch", "t0": t, "t1": t + L_STEP.fetch_round, "what": "round"})
		t += L_STEP.fetch_round
		_le_plan.append({"kind": "press_round", "t0": t, "t1": t + L_STEP.press_round})
		t += L_STEP.press_round
		_le_events.append([t - 0.02, 1])
	_le_plan.append({"kind": "close", "t0": t, "t1": t + L_STEP.close})
	t += L_STEP.close
	_le_plan.append({"kind": "settle", "t0": t, "t1": t + L_STEP.settle})
	t += L_STEP.settle
	_le_total = t
	return _le_events


func rifle_reload_total() -> float:
	return _le_total


## Work the bolt (after a shot, or to chamber a round with the action closed empty).
func rifle_cycle() -> void:
	_cycle_t = 0.0
	_le_done = {}


func _le_reset() -> void:
	_le_plan = []
	_le_done = {}
	if _le_charger:
		_le_charger.visible = false
		_le_round.visible = false


func _animate_rifle() -> void:
	var pose := _pose[RIFLE]
	if _le_model == null:
		return
	var k := _kick * _kick
	var a := smoothstep(0.0, 1.0, ads)
	# held at the hip-shoulder ...
	var pos := L_HOME
	var rot := L_TILT * (PI / 180.0)
	# ... or aimed: the rear notch and the blade on the camera's axis
	if a > 0.0:
		var m0 := Transform3D(_le_model.basis, _le_model.position)
		var rear: Vector3 = m0 * (_le_mark.SightRear as Vector3)
		var aim_pos := Vector3(-rear.x, -rear.y, -L_EYE - rear.z)
		pos = pos.lerp(aim_pos, a)
		rot = rot.lerp(Vector3.ZERO, a)
	# the shot: a hard shove back and the muzzle up (less when aimed, the stock in the shoulder)
	pos += Vector3(0, 0.010 * k, 0.05 * k) * (1.0 - 0.4 * a)
	rot += Vector3(deg_to_rad(6.0) * k * (1.0 - 0.3 * a), 0, deg_to_rad(_jitter.x) * _kick * 0.5)
	var lift := 0.0
	var draw := 0.0
	var e := func(r: Vector2, t: float) -> float: return smoothstep(r.x, r.y, t)
	var rkey: Array = []                          # the right hand's key, when it is off the wrist
	var ra: FPArm = _arms[RIFLE]["R"] if _arms.has(RIFLE) else null
	if _reload_t < 0.0 and _cycle_t >= 0.0:
		var t := _cycle_t
		var c := L_CYCLE
		lift = e.call(c.up, t) * (1.0 - e.call(c.down, t))
		draw = e.call(c.back, t) * (1.0 - e.call(c.fwd, t))
		rot += Vector3(0, 0, deg_to_rad(-5.0)) * e.call(c.to_knob, t) * (1.0 - e.call(c.to_grip, t))
		pos += Vector3(0, 0, 0.006) * (e.call(Vector2(c.back.y - 0.02, c.back.y + 0.02), t) - e.call(Vector2(c.back.y + 0.02, c.back.y + 0.1), t))   # the bolt hits its stop
		if ra:
			var grip := _rl_grip_for(RIFLE, ra, "R")
			var kn := _le_knob_key(ra, lift, draw)
			if t < c.to_knob.y:
				rkey = _rl_blend(grip, kn, e.call(c.to_knob, t))
			elif t < c.to_grip.x:
				rkey = kn
			else:
				rkey = _rl_blend(kn, grip, e.call(c.to_grip, t))
		_le_sounds_cycle(t)
		if t >= c.eject.x and not _le_done.has("eject"):
			_le_done["eject"] = true
			_le_throw(false)
	if _reload_t >= 0.0:
		var r := _le_reload(_reload_t, ra)
		lift = r[0]
		draw = r[1]
		rkey = r[2]
		var tilt: float = r[3]
		pos += Vector3(-0.03, 0.03, 0.05) * tilt
		rot += Vector3(deg_to_rad(8.0), deg_to_rad(10.0), deg_to_rad(-26.0)) * tilt
	pose.position = pos
	pose.rotation = rot
	le_lift = lift
	le_draw = draw
	_le_last_key = rkey
	if _le_turn:
		_le_turn.rotation = Vector3(deg_to_rad(-L_LIFT) * lift, 0, 0)
	if _le_bolt:
		_le_bolt.position = _le_bolt_rest + Vector3(-L_TRAVEL * draw, 0, 0)
	if _le_cock:
		_le_cock.position = _le_cock_rest + Vector3(-0.005 * lift, 0, 0)     # cocked as the handle goes up
	# the top round in the magazine shows in the open bolt-way
	_le_top.visible = draw > 0.6 and le_rounds_in_mag > 0
	if ra:
		if not rkey.is_empty():
			_rl_apply(ra, rkey)
			_le_hand_r = true
		elif _le_hand_r:
			_le_hand_r = false
			apply_grip(RIFLE, _grips_live[RIFLE], _le_model)
			_arm_pull_last = -1.0
		if rkey.is_empty():
			_arm_trigger(RIFLE, 1.0 if _since_shot < 0.12 else 0.0)


## The right hand on the knob (wherever the bolt is): pinched from behind and to the right.
func _le_knob_key(arm: FPArm, lift: float, draw: float) -> Array:
	var m := _le_model.transform
	var bolt := Transform3D(Basis(), _le_bolt_rest + Vector3(-L_TRAVEL * draw, 0, 0))
	var knob := m * (bolt * (Basis(Vector3.RIGHT, deg_to_rad(-L_LIFT) * lift) * _le_knob_rel))
	var along := (m.basis * Vector3(0.62, -0.10, -0.55)).normalized()
	var toward := m.basis * Vector3(0, 0, -1)
	var palm := (toward - along * toward.dot(along)).normalized()
	var hand := FPArm.frame(Vector3.ZERO, along, palm)
	if not _pinch_off.has(arm):
		arm.set_pose(PINCH_POSE)
		_pinch_off[arm] = arm.pinch_offset()
	hand.origin = knob - hand.basis * (_pinch_off[arm] as Vector3)
	return [hand, Vector3(0.34, -0.60, 0.40), PINCH_POSE]


## The right hand pinching a point (pose space), coming down from above and the right.
func _le_pinch_at(arm: FPArm, at: Vector3, down: float) -> Array:
	var m := _le_model.transform
	var along := (m.basis * Vector3(0.45, -0.55 * down - 0.1, -0.55)).normalized()
	var toward := (m.basis * Vector3(0, -0.6 * down, -1)).normalized()
	var palm := (toward - along * toward.dot(along)).normalized()
	var hand := FPArm.frame(Vector3.ZERO, along, palm)
	if not _pinch_off.has(arm):
		arm.set_pose(PINCH_POSE)
		_pinch_off[arm] = arm.pinch_offset()
	hand.origin = at - hand.basis * (_pinch_off[arm] as Vector3)
	return [hand, Vector3(0.34, -0.58, 0.36), PINCH_POSE]


## Where the charger sits in its guide (model space): the rims in the clip just above
## the bridge, the rounds pointing forward over the magazine.
func _le_charger_home() -> Transform3D:
	var g: Vector3 = _le_mark.ChargerGuide
	return Transform3D(Basis(), Vector3(g.x + 0.003, g.y + 0.007, 0))


## The reload at time t: [lift, draw, right-hand key (or []), tilt].
func _le_reload(t: float, ra: FPArm) -> Array:
	var lift := 1.0
	var draw := 1.0
	var key: Array = []
	var tilt := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(_le_total - L_STEP.settle - 0.25, _le_total, t))
	var step: Dictionary = {}
	for s: Dictionary in _le_plan:
		if t >= s.t0 and t < s.t1:
			step = s
			break
	if step.is_empty():
		return [0.0, 0.0, [], tilt]
	var u := (t - float(step.t0)) / maxf(float(step.t1) - float(step.t0), 0.001)
	var m := _le_model.transform
	var ch_home := _le_charger_home()
	var press_drop := (L_BORE_Y - 0.0105) - (ch_home.origin.y + 4 * L_ROUND_GAP)       # takes the top round down to the magazine's top
	_le_charger.visible = false
	_le_round.visible = false
	match step.kind:
		"open":
			lift = smoothstep(0.33, 0.48, u)
			draw = smoothstep(0.48, 0.78, u)
			if ra:
				key = _rl_blend(_rl_grip_for(RIFLE, ra, "R"), _le_knob_key(ra, lift, draw), smoothstep(0.0, 0.33, u))
				if u > 0.78:
					key = _le_knob_key(ra, lift, draw)
			if u > 0.18 and not _le_done.has("s_up"):
				_le_done["s_up"] = true
				SfxSynth.play(self, "bolt_up", global_position, -6.0, randf_range(0.95, 1.05))
			if u > 0.5 and not _le_done.has("s_back"):
				_le_done["s_back"] = true
				SfxSynth.play(self, "bolt_back", global_position, -5.0, randf_range(0.95, 1.05))
			if step.extract and u > 0.7 and not _le_done.has("extract"):
				_le_done["extract"] = true
				_le_throw(true)
		"fetch":
			var carried: Node3D = _le_charger if step.what == "charger" else _le_round
			var place := _le_charger_home() if step.what == "charger" else _le_round_home(0.0)
			var place_key := _le_place_key(ra, place, step.what == "charger") if ra else []
			var prev: Array = _le_from(step, _le_knob_key(ra, 1.0, 1.0)) if ra else []
			if ra:
				var pouch := [Transform3D(place_key[0].basis.rotated(Vector3.RIGHT, 0.5).orthonormalized(), L_POUCH), Vector3(0.36, -0.85, 0.30), PINCH_POSE]
				key = _rl_blend(prev, pouch, smoothstep(0.0, 0.45, u)) if u < 0.5 else _rl_blend(pouch, place_key, smoothstep(0.5, 1.0, u))
				if u > 0.5:
					carried.visible = true
					carried.transform = m.affine_inverse() * (key[0] as Transform3D) * (place_key[0] as Transform3D).affine_inverse() * (m * place)
					if step.what == "charger":
						_le_set_charger_rounds(0.0)
		"seat":
			_le_charger.visible = true
			_le_charger.transform = ch_home
			_le_set_charger_rounds(0.0)
			if ra:
				key = _le_place_key(ra, ch_home, true)
			if not _le_done.has("seat%f" % step.t0):
				_le_done["seat%f" % step.t0] = true
				SfxSynth.play(self, "charger_in", global_position, -6.0, randf_range(0.95, 1.05))
		"press":
			_le_charger.visible = true
			_le_charger.transform = ch_home
			var p := smoothstep(0.05, 0.95, u)
			_le_set_charger_rounds(press_drop * p)
			if ra:
				var top := m * (ch_home * Vector3(0.03, 4 * L_ROUND_GAP + press_drop * p + 0.008, 0))
				key = _le_pinch_at(ra, top, 1.0)
			if u > 0.1 and not _le_done.has("press%f" % step.t0):
				_le_done["press%f" % step.t0] = true
				SfxSynth.play(self, "rounds_in", global_position, -6.0, randf_range(0.95, 1.05))
		"strip":
			_le_charger.visible = u < 0.85
			var off := Transform3D(Basis(Vector3.FORWARD, -0.6 * u), Vector3(0, 0.04 * u, 0.05 * u))
			_le_charger.transform = ch_home * off
			_le_set_charger_rounds(press_drop - 1.0)          # empty
			if ra:
				key = _le_place_key(ra, _le_charger.transform, true)
			if u > 0.85 and not _le_done.has("strip%f" % step.t0):
				_le_done["strip%f" % step.t0] = true
				_le_throw_charger()
		"press_round":
			_le_round.visible = u < 0.95
			var p := smoothstep(0.1, 0.9, u)
			_le_round.transform = _le_round_home(p)
			if ra:
				key = _le_pinch_at(ra, m * (_le_round.transform * Vector3(0.03, 0.007, 0)), 1.0)
			if u > 0.5 and not _le_done.has("rnd%f" % step.t0):
				_le_done["rnd%f" % step.t0] = true
				SfxSynth.play(self, "round_in", global_position, -8.0, randf_range(0.95, 1.1))
		"close":
			draw = 1.0 - smoothstep(0.30, 0.58, u)
			lift = 1.0 - smoothstep(0.58, 0.72, u)
			if ra:
				var kn := _le_knob_key(ra, lift, draw)
				if u < 0.30:
					key = _rl_blend(_le_from(step, kn), kn, smoothstep(0.0, 0.30, u))
				elif u < 0.74:
					key = kn
				else:
					key = _rl_blend(kn, _rl_grip_for(RIFLE, ra, "R"), smoothstep(0.74, 1.0, u))
			if u > 0.32 and not _le_done.has("s_fwd"):
				_le_done["s_fwd"] = true
				SfxSynth.play(self, "bolt_fwd", global_position, -5.0, randf_range(0.95, 1.05))
			if u > 0.6 and not _le_done.has("s_down"):
				_le_done["s_down"] = true
				SfxSynth.play(self, "bolt_down", global_position, -6.0, randf_range(0.95, 1.05))
		"settle":
			lift = 0.0
			draw = 0.0
	return [lift, draw, key, tilt]


## A loose round on its way into the magazine: above the opening (p 0) to pressed down (p 1).
func _le_round_home(p: float) -> Transform3D:
	var h := _le_charger_home().origin
	return Transform3D(Basis(), Vector3(h.x, lerpf(h.y + 0.004, L_BORE_Y - 0.0105, p), 0))


## The hand holding what it carries placed at `place` (model space): a charger by its
## clip from above and the right, a round by its base.
func _le_place_key(arm: FPArm, place: Transform3D, charger: bool) -> Array:
	var m := _le_model.transform
	var grab := place * (Vector3(-0.002, 0.058, 0.0) if charger else Vector3(0.008, 0.0, 0.0))
	return _le_pinch_at(arm, m * grab, 0.6)


## Where a step starts the right hand from: wherever it was when the step began.
func _le_from(step: Dictionary, fallback: Array) -> Array:
	var k := "from%f" % float(step.t0)
	if not _le_done.has(k):
		_le_done[k] = _le_last_key if not _le_last_key.is_empty() else fallback
	return _le_done[k]


## The charger's rounds dropped `dy` (negative: pressed down). Below the magazine's top
## they are in the magazine and hidden; the top round stays at the top.
func _le_set_charger_rounds(dy: float) -> void:
	var top := L_BORE_Y - 0.0105
	for k in 5:
		var r := _le_charger.get_node("R%d" % k) as Node3D
		r.position = Vector3(0, k * L_ROUND_GAP + dy, 0)
		var y := _le_charger.position.y + r.position.y
		r.visible = y > top + (-0.0005 if k == 4 else 0.003)


func _le_sounds_cycle(t: float) -> void:
	for s: Array in [["up", "bolt_up"], ["back", "bolt_back"], ["fwd", "bolt_fwd"], ["down", "bolt_down"]]:
		var at: float = (L_CYCLE[s[0]] as Vector2).x + 0.02
		if t >= at and not _le_done.has("s_" + s[0]):
			_le_done["s_" + s[0]] = true
			SfxSynth.play(self, s[1], global_position, -6.0, randf_range(0.95, 1.05))


## A case (or, opening on a live round, the round) out of the ejection opening, a real body.
func _le_throw(live: bool) -> void:
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene
	if cam == null or scene == null or _le_model == null:
		return
	var eye := cam.global_position
	var at := eye + (_le_model.global_transform * (_le_mark.Ejection as Vector3) - eye) / SHRINK
	var body := RigidBody3D.new()
	body.collision_layer = 1 << 3
	body.collision_mask = 1
	body.mass = 0.025 if live else 0.012
	var length := 0.077 if live else 0.056
	var shape := CylinderShape3D.new()
	shape.radius = 0.006
	shape.height = length
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.z = PI * 0.5
	body.add_child(cs)
	var vis := _le_cartridge()
	if not live:
		vis.get_child(3).queue_free()                # no bullet: a fired case
	vis.position = Vector3(-length * 0.5, 0, 0)
	body.add_child(vis)
	body.add_to_group("spent_brass")
	scene.add_child(body)
	var gm := _le_model.global_transform.basis.orthonormalized()
	body.global_transform = Transform3D(gm, at)
	body.linear_velocity = gm.z * randf_range(2.0, 2.8) + Vector3.UP * randf_range(1.2, 1.9) - gm.x * randf_range(0.2, 0.6)
	body.angular_velocity = Vector3(randf_range(-18, 18), randf_range(-18, 18), randf_range(-18, 18))
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var hits := [0]
	body.body_entered.connect(func(_b: Node) -> void:
		if hits[0] < 1 and body.linear_velocity.length() > 0.6:
			hits[0] += 1
			SfxSynth.play(body, "brass_tink", body.global_position, -18.0, randf_range(0.8, 1.0)))
	get_tree().create_timer(15.0).timeout.connect(body.queue_free)
	le_spent.append(body)


## The empty charger flicked away, a real body.
func _le_throw_charger() -> void:
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene
	if cam == null or scene == null:
		return
	var eye := cam.global_position
	var g := _le_charger.global_transform
	var body := RigidBody3D.new()
	body.collision_layer = 1 << 3
	body.collision_mask = 1
	body.mass = 0.02
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.006, 0.064, 0.016)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.026, 0)
	body.add_child(cs)
	_box(body, Vector3(0.004, 0.064, 0.016), Vector3(-0.002, 0.026, 0), Vector3.ZERO, _mat(Color(0.12, 0.12, 0.13), 0.5, 0.8))
	scene.add_child(body)
	body.global_transform = Transform3D(g.basis.orthonormalized(), eye + (g.origin - eye) / SHRINK)
	var gm := _le_model.global_transform.basis.orthonormalized()
	body.linear_velocity = gm.z * 1.6 + Vector3.UP * 0.8
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	get_tree().create_timer(15.0).timeout.connect(body.queue_free)
	le_spent.append(body)


func _muzzle() -> Vector3:
	if weapon == REVOLVER:
		return to_local(_rev_muzzle.global_position)
	if weapon == TRENCH:
		return to_local(_sg_muzzle.global_position)
	if weapon == MP18:
		return to_local(_mp_muzzle.global_position)
	if weapon == RIFLE and _le_muzzle:
		return to_local(_le_muzzle.global_position)
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
	TRENCH: {
		"R": {"index_k": Vector3(-0.194, 0.140, 0.045), "little_k": Vector3(-0.236, 0.084, 0.047), "palm": Vector3(0.0, -0.2, -1.0), "elbow": Vector3(-0.45, -0.10, 0.34),
			"pose": {"index_01": Vector3(10, 0, 15), "index_02": Vector3(15, 0, 0), "index_03": Vector3(40, 0, 0),
			"middle_01": Vector3(15, 0, 0), "middle_02": Vector3(25, 0, 0), "middle_03": Vector3(12, 0, 0),
			"ring_01": Vector3(55, 0, 0), "ring_02": Vector3(5, 0, 0), "ring_03": Vector3(4, 0, 0),
			"little_01": Vector3(50, 0, 0), "little_02": Vector3(60, 0, 0), "little_03": Vector3(30, 0, 0),
			"thumb_01": Vector3(6, 0, -24), "thumb_02": Vector3(10, 0, 0), "thumb_03": Vector3(0, 0, 0)},
			"pull": {"index_01": Vector3(6, 0, 0), "index_02": Vector3(14, 0, 0), "index_03": Vector3(10, 0, 0)}},
		"L": {"index_k": Vector3(0.24, 0.086, 0.012), "little_k": Vector3(0.17, 0.088, 0.016), "palm": Vector3(0.0, 0.92, -0.38), "elbow": Vector3(-0.12, -0.14, -0.25),
			"pose": {"index_01": Vector3(-10, 0, 0), "index_02": Vector3(80, 0, 0), "index_03": Vector3(40, 0, 0),
			"middle_01": Vector3(5, 0, 0), "middle_02": Vector3(65, 0, 0), "middle_03": Vector3(32, 0, 0),
			"ring_01": Vector3(10, 0, 0), "ring_02": Vector3(55, 0, 0), "ring_03": Vector3(28, 0, 0),
			"little_01": Vector3(5, 0, 0), "little_02": Vector3(110, 0, 0), "little_03": Vector3(55, 0, 0),
			"thumb_01": Vector3(-18, 0, 8), "thumb_02": Vector3(0, 0, 0), "thumb_03": Vector3(15, 0, 0)}}
	},
	RIFLE: {
		"R": {"index_k": Vector3(-0.283, 0.146, 0.054), "little_k": Vector3(-0.320, 0.099, 0.054), "palm": Vector3(0.0, -0.05, -1.0), "elbow": Vector3(-0.60, -0.10, 0.24),
			"pose": {"index_01": Vector3(20, 0, 0), "index_02": Vector3(15, 0, 0), "index_03": Vector3(10, 0, 0),
			"middle_01": Vector3(60, 0, 0), "middle_02": Vector3(10, 0, 0), "middle_03": Vector3(5, 0, 0),
			"ring_01": Vector3(85, 0, 0), "ring_02": Vector3(70, 0, 0), "ring_03": Vector3(40, 0, 0),
			"little_01": Vector3(80, 0, 0), "little_02": Vector3(0, 0, 0), "little_03": Vector3(0, 0, 0),
			"thumb_01": Vector3(-30, 0, -40), "thumb_02": Vector3(40, 0, 0), "thumb_03": Vector3(30, 0, 0)},
			"pull": {"index_01": Vector3(6, 0, 0), "index_02": Vector3(14, 0, 0), "index_03": Vector3(10, 0, 0)}},
		"L": {"index_k": Vector3(0.118, 0.147, 0.018), "little_k": Vector3(0.053, 0.144, 0.018), "palm": Vector3(0.0, 0.92, -0.38), "elbow": Vector3(-0.15, -0.10, -0.28),
			"pose": {"index_01": Vector3(-10, 0, 0), "index_02": Vector3(70, 0, 0), "index_03": Vector3(35, 0, 0),
			"middle_01": Vector3(-10, 0, 0), "middle_02": Vector3(70, 0, 0), "middle_03": Vector3(35, 0, 0),
			"ring_01": Vector3(0, 0, 0), "ring_02": Vector3(45, 0, 0), "ring_03": Vector3(22, 0, 0),
			"little_01": Vector3(-10, 0, 0), "little_02": Vector3(105, 0, 0), "little_03": Vector3(52, 0, 0),
			"thumb_01": Vector3(-30, 0, 8), "thumb_02": Vector3(-10, 0, 0), "thumb_03": Vector3(0, 0, 0)}}
	},
	MP18: {
		"R": {"index_k": Vector3(-0.170, 0.092, 0.053), "little_k": Vector3(-0.215, 0.039, 0.055), "palm": Vector3(0.0, -0.2, -1.0), "elbow": Vector3(-0.45, -0.18, 0.34),
			"pose": {"index_01": Vector3(0, 0, 5), "index_02": Vector3(30, 0, 0), "index_03": Vector3(40, 0, 0),
			"middle_01": Vector3(20, 0, 0), "middle_02": Vector3(75, 0, 0), "middle_03": Vector3(38, 0, 0),
			"ring_01": Vector3(65, 0, 0), "ring_02": Vector3(0, 0, 0), "ring_03": Vector3(0, 0, 0),
			"little_01": Vector3(40, 0, 0), "little_02": Vector3(70, 0, 0), "little_03": Vector3(35, 0, 0),
			"thumb_01": Vector3(-30, 0, -24), "thumb_02": Vector3(0, 0, 0), "thumb_03": Vector3(0, 0, 0)},
			"pull": {"index_01": Vector3(6, 0, 0), "index_02": Vector3(14, 0, 0), "index_03": Vector3(10, 0, 0)}},
		"L": {"index_k": Vector3(0.02, 0.032, 0.006), "little_k": Vector3(-0.05, 0.036, 0.010), "palm": Vector3(0.0, 0.92, -0.38), "elbow": Vector3(-0.20, -0.16, -0.25),
			"pose": {"index_01": Vector3(-10, 0, 0), "index_02": Vector3(20, 0, 0), "index_03": Vector3(18, 0, 0),
			"middle_01": Vector3(-10, 0, 0), "middle_02": Vector3(35, 0, 0), "middle_03": Vector3(32, 0, 0),
			"ring_01": Vector3(-10, 0, 0), "ring_02": Vector3(20, 0, 0), "ring_03": Vector3(14, 0, 0),
			"little_01": Vector3(-10, 0, 0), "little_02": Vector3(0, 0, 0), "little_03": Vector3(0, 0, 0),
			"thumb_01": Vector3(-6, 0, 16), "thumb_02": Vector3(-10, 0, 0), "thumb_03": Vector3(0, 0, 0)}}
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
	_rv_left_hand(t)
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


# --- the hands through the top-break reload -----------------------------------------
# The way a Webley is reloaded: the left hand comes over, thumbs the latch and
# rides the barrel open, then holds the open gun by the frame; the right hand
# lets go of the grip, fetches rounds and pinches them into the chambers one by
# one (from the right, so the cylinder face stays in view); it takes the grip
# again, and the left hand goes under the barrel and pushes it shut.
# Each key is a hand frame, an elbow and a finger pose in the pose node's space,
# worked out every frame from the part it holds (the barrel keys ride the hinge,
# the pinch follows the round as it slides home). Knuckle points are in the gun
# model's units with the barrel shut; elbows are in the pose node's space
# (metres, low and to the side so the forearms leave the bottom of the screen).
const V_HINGE := Vector3(0.092, 0.425, 0.0)
const LH_LATCH := {"index_k": Vector3(0.0, 0.70, -0.06), "little_k": Vector3(0.28, 0.70, -0.04), "palm": Vector3(0.0, -1.0, 0.15), "elbow": Vector3(-0.42, -0.62, 0.08),
	"pose": {"index_01": Vector3(30, 0, 0), "index_02": Vector3(35, 0, 0), "index_03": Vector3(20, 0, 0),
		"middle_01": Vector3(35, 0, 0), "middle_02": Vector3(40, 0, 0), "middle_03": Vector3(20, 0, 0),
		"ring_01": Vector3(38, 0, 0), "ring_02": Vector3(40, 0, 0), "ring_03": Vector3(20, 0, 0),
		"little_01": Vector3(40, 0, 0), "little_02": Vector3(40, 0, 0), "little_03": Vector3(20, 0, 0),
		"thumb_01": Vector3(-10, 0, 0), "thumb_02": Vector3(0, 0, 0), "thumb_03": Vector3(5, 0, 0)}}
## The open gun held in the left hand by its barrel (hanging muzzle down), from
## below and to the left, so the cylinder face on top stays in view for loading.
## Barrel space (it rides the hinge).
const LH_HOLD := {"index_k": Vector3(0.20, 0.57, -0.11), "little_k": Vector3(0.44, 0.57, -0.11), "palm": Vector3(0.0, 0.0, 1.0), "elbow": Vector3(-0.30, -0.70, 0.10),
	"pose": {"index_01": Vector3(55, 0, 0), "index_02": Vector3(60, 0, 0), "index_03": Vector3(35, 0, 0),
		"middle_01": Vector3(58, 0, 0), "middle_02": Vector3(62, 0, 0), "middle_03": Vector3(35, 0, 0),
		"ring_01": Vector3(60, 0, 0), "ring_02": Vector3(62, 0, 0), "ring_03": Vector3(35, 0, 0),
		"little_01": Vector3(62, 0, 0), "little_02": Vector3(60, 0, 0), "little_03": Vector3(35, 0, 0),
		"thumb_01": Vector3(20, 0, 0), "thumb_02": Vector3(10, 0, 0), "thumb_03": Vector3(10, 0, 0)}}
const LH_CLOSE := {"index_k": Vector3(0.34, 0.45, -0.04), "little_k": Vector3(0.06, 0.45, -0.04), "palm": Vector3(0.0, 1.0, 0.1), "elbow": Vector3(-0.32, -0.66, 0.02),
	"pose": {"index_01": Vector3(45, 0, 0), "index_02": Vector3(45, 0, 0), "index_03": Vector3(25, 0, 0),
		"middle_01": Vector3(48, 0, 0), "middle_02": Vector3(45, 0, 0), "middle_03": Vector3(25, 0, 0),
		"ring_01": Vector3(50, 0, 0), "ring_02": Vector3(45, 0, 0), "ring_03": Vector3(25, 0, 0),
		"little_01": Vector3(52, 0, 0), "little_02": Vector3(45, 0, 0), "little_03": Vector3(25, 0, 0),
		"thumb_01": Vector3(10, 0, 0), "thumb_02": Vector3(10, 0, 0), "thumb_03": Vector3(10, 0, 0)}}
## Thumb and index tips about a round's width apart (searched: test_arms --pinch-search),
## the other fingers tucked.
const PINCH_POSE := {"index_01": Vector3(50, 0, 0), "index_02": Vector3(24, 0, 0), "index_03": Vector3(14, 0, 0),
	"middle_01": Vector3(80, 0, 0), "middle_02": Vector3(95, 0, 0), "middle_03": Vector3(55, 0, 0),
	"ring_01": Vector3(82, 0, 0), "ring_02": Vector3(95, 0, 0), "ring_03": Vector3(55, 0, 0),
	"little_01": Vector3(84, 0, 0), "little_02": Vector3(92, 0, 0), "little_03": Vector3(55, 0, 0),
	"thumb_01": Vector3(20, 0, -20), "thumb_02": Vector3(0, 0, 0), "thumb_03": Vector3(0, 0, 0)}
## The right hand's pinch: it comes in from the gun's right, `lean` of its line
## across the gun (the rest down the chamber); the pinch point on the round's base.
const RH_PINCH := {"lean": 0.7, "elbow": Vector3(0.36, -0.55, 0.42), "fetch": Vector3(0.10, -0.30, 0.16)}
## Reload clock (s).
const RL_T := {"l_latch": Vector2(0.0, 0.15), "l_hold": Vector2(0.5, 0.62), "r_fetch": Vector2(0.56, 0.64), "r_pinch": Vector2(0.64, 0.75),
	"r_grip": Vector2(2.08, 2.2), "l_close": Vector2(2.08, 2.2), "l_support": Vector2(2.36, 2.75)}
var _rl_active := false
var _rl_round: Node3D                       # the round in the right hand on the way from the pouch
var _pinch_off := {}                        # FPArm -> pinch point in its hand frame


func _rl_from_knuckles(arm: FPArm, key: Dictionary, barrel: bool) -> Transform3D:
	var m := _rev_model.transform
	var f := func(p: Vector3) -> Vector3:
		return m * (_rv_barrel.transform * (p - V_HINGE)) if barrel else m * p
	var b := (m.basis * (_rv_barrel.transform.basis if barrel else Basis())).orthonormalized()
	return arm.frame_from_knuckles(f.call(key.index_k), f.call(key.little_k), b * key.palm)


## A side's grip from ARM_GRIPS, as a key.
func _rl_grip(arm: FPArm, side: String) -> Array:
	var m := _rev_model.transform
	var g: Dictionary = ARM_GRIPS[REVOLVER][side]
	var hand: Transform3D
	if g.has("index_k"):
		hand = arm.frame_from_knuckles(m * g.index_k, m * g.little_k, m.basis * g.palm)
	else:
		hand = FPArm.frame(m * g.wrist, m.basis * g.along, m.basis * g.palm)
	return [hand, m * g.get("elbow", Vector3(-1.5, -1.0, -0.8)), g.pose]


## The right hand pinching chamber `c`'s round by its base (wherever it is now).
func _rl_pinch(arm: FPArm, c: int) -> Array:
	var m := _rev_model.transform
	var rd := _rv_rounds[c] as MeshInstance3D
	var rx := (_pose[REVOLVER] as Node3D).global_transform.affine_inverse() * rd.global_transform
	var aabb := rd.mesh.get_aabb()
	var base := rx * Vector3(aabb.position.x, aabb.get_center().y, aabb.get_center().z)
	var a := rx.basis.x.normalized()                          # into the chamber
	var side := (m.basis * Vector3(0, 0, 1)).normalized()     # the gun's right
	side = (side - a * side.dot(a)).normalized()
	var along := (a * (1.0 - RH_PINCH.lean) - side * RH_PINCH.lean).normalized()
	var palm := (a - along * a.dot(along)).normalized()        # fingers curl toward the chamber
	var hand := FPArm.frame(Vector3.ZERO, along, palm)
	if not _pinch_off.has(arm):
		arm.set_pose(PINCH_POSE)
		_pinch_off[arm] = arm.pinch_offset()
	hand.origin = base - hand.basis * (_pinch_off[arm] as Vector3)
	return [hand, RH_PINCH.elbow, PINCH_POSE]


func _rl_blend(a: Array, b: Array, k: float) -> Array:
	k = clampf(k, 0.0, 1.0)
	var ha: Transform3D = a[0]
	var hb: Transform3D = b[0]
	var q := ha.basis.get_rotation_quaternion().slerp(hb.basis.get_rotation_quaternion(), k)
	var pose := {}
	var pa: Dictionary = a[2]
	var pb: Dictionary = b[2]
	for bn in pa.keys() + pb.keys():
		pose[bn] = (pa.get(bn, Vector3.ZERO) as Vector3).lerp(pb.get(bn, Vector3.ZERO), k)
	return [Transform3D(Basis(q), ha.origin.lerp(hb.origin, k)), (a[1] as Vector3).lerp(b[1], k), pose]


func _rl_apply(arm: FPArm, key: Array) -> void:
	arm.set_pose(key[2])
	arm.place(key[0], key[1])


## Both hands at reload time `t` (< 0: not reloading).
func _rv_left_hand(t: float) -> void:
	if not _arms.has(REVOLVER) or not _arms[REVOLVER].has("L"):
		return
	var la: FPArm = _arms[REVOLVER]["L"]
	var ra: FPArm = _arms[REVOLVER]["R"]
	la.visible = true
	if t < 0.0 or t >= RL_T.l_support.y:
		if _rl_active:
			_rl_active = false
			apply_grip(REVOLVER, _grips_live[REVOLVER], _rev_model)   # both hands exactly back on their grips
			_arm_pull_last = -1.0
		if _rl_round:
			_rl_round.visible = false
		return
	_rl_active = true
	var e := func(r: Vector2) -> float: return smoothstep(r.x, r.y, t)
	var m := _rev_model.transform
	var latch := [_rl_from_knuckles(la, LH_LATCH, true), LH_LATCH.elbow, LH_LATCH.pose]
	var hold := [_rl_from_knuckles(la, LH_HOLD, true), LH_HOLD.elbow, LH_HOLD.pose]
	var close := [_rl_from_knuckles(la, LH_CLOSE, true), LH_CLOSE.elbow, LH_CLOSE.pose]
	# left: latch, ride it open, hold the gun, under the barrel, ride it shut, back
	var lk: Array
	if t < RL_T.l_latch.y:
		lk = _rl_blend(_rl_grip(la, "L"), latch, e.call(RL_T.l_latch))
	elif t < RL_T.l_hold.x:
		lk = latch
	elif t < RL_T.l_close.x:
		lk = _rl_blend(latch, hold, e.call(RL_T.l_hold))
	elif t < RL_T.l_support.x:
		lk = _rl_blend(hold, close, e.call(RL_T.l_close))
	else:
		lk = _rl_blend(close, _rl_grip(la, "L"), e.call(RL_T.l_support))
	_rl_apply(la, lk)
	# right: on the grip until the gun is held, to the pouch, round after round, back
	var first := rv_index % 6
	var step := (V_T_LOAD.y - V_T_LOAD.x) / 6.0
	var grip := _rl_grip(ra, "R")
	var rk: Array
	if t < RL_T.r_fetch.x:
		rk = grip
	elif t < RL_T.r_pinch.x:
		var fetch := grip.duplicate()
		fetch[0] = Transform3D((grip[0] as Transform3D).basis, (grip[0] as Transform3D).origin + RH_PINCH.fetch)
		fetch[2] = PINCH_POSE
		rk = _rl_blend(grip, fetch, e.call(RL_T.r_fetch))
	elif t < V_T_LOAD.x + 0.001:
		var fetch := grip.duplicate()
		fetch[0] = Transform3D((grip[0] as Transform3D).basis, (grip[0] as Transform3D).origin + RH_PINCH.fetch)
		fetch[2] = PINCH_POSE
		rk = _rl_blend(fetch, _rl_pinch(ra, first), e.call(RL_T.r_pinch))
	elif t < RL_T.r_grip.x:
		var order := clampi(int((t - V_T_LOAD.x) / step), 0, 5)
		var c := (order + first) % 6
		var t0 := V_T_LOAD.x + order * step
		var into := step * 0.75
		if t < t0 + into or order == 5:
			rk = _rl_pinch(ra, c)
		else:
			rk = _rl_blend(_rl_pinch(ra, c), _rl_pinch(ra, (order + 1 + first) % 6), smoothstep(t0 + into, t0 + step, t))
	elif t < RL_T.r_grip.y:
		rk = _rl_blend(_rl_pinch(ra, (5 + first) % 6), grip, e.call(RL_T.r_grip))
	else:
		rk = grip
	_rl_apply(ra, rk)
	# a round in the right fingers on the way back from the pouch
	if _rl_round == null:
		_rl_round = _make_hand_round(ra)
	if _rl_round:
		_rl_round.visible = t > RL_T.r_fetch.y - 0.02 and t < V_T_LOAD.x


## A copy of one of the gun's rounds, held at the tip of the index finger.
func _make_hand_round(arm: FPArm) -> Node3D:
	var src := _rv_rounds[0] as MeshInstance3D
	if src == null:
		return null
	var att := BoneAttachment3D.new()
	arm.skeleton.add_child(att)
	att.bone_name = "index_03." + arm.side
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.layers = 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * V_SCALE / FPArm.SIZE             # real size in the arm's units
	mi.position = Vector3(0.0, 0.022, 0.012) / FPArm.SIZE
	mi.rotation_degrees = Vector3(0, 0, 90)
	att.add_child(mi)
	att.visible = false
	return att


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


# --- the trench shotgun (Tripo Winchester 1897, refined in Blender) ---------------------
# art/weapons/trench_shotgun/trench_shotgun.glb, built from the untouched Tripo GLB by
# art/weapons/trench_shotgun/source/build_shotgun.py: Body (with a modelled perforated
# heat shield and the magazine tube), Pump (slides along the tube) and Hammer (on its
# pivot). Metres, +X the muzzle, +Y up, +Z the right side. Held shouldered, real size.
const T_PATH := "res://art/weapons/trench_shotgun/trench_shotgun.glb"
const T_HOME := Vector3(0.13, -0.15, -0.33)
const T_TILT := Vector3(0.0, 2.5, 4.0)        # turned in a touch, canted a little
const T_BORE := Vector3(0.492, 0.1508, 0.0)  # the bore at the muzzle (model space)
const T_PUMP_TRAVEL := 0.066                  # the pump's full stroke: its rear stops just short of the receiver
const T_PUMP := Vector4(0.28, 0.20, 0.07, 0.17)   # after a shot: wait (the kick settles first), back, hold, forward (s)
## The gun gives with the stroke (most of the pump's travel is toward the eye, so
## this is what sells it): dips and comes back into the shoulder, straight back (no pull to the side).
const T_RACK_POS := Vector3(0.0, -0.022, 0.03)
const T_RACK_ROT := Vector3(-4.0, 0.0, -3.0)
## Loading: rolled over to the right (the loading port under the
## receiver turns toward the eye), brought up and in front, muzzle off to the left.
const T_LOAD_POS := Vector3(-0.08, 0.0, -0.06)
## while loading the right elbow stays low on the right (view space), not carried up by the roll
const T_LOAD_R_ELBOW := Vector3(0.12, -0.85, 0.25)
const T_LOAD_ROT := Vector3(10.0, 14.0, -62.0)
## Loading: per shell (the player's clock uses these through shell_intro/shell_time).
const T_SHELL_INTRO := 0.42
const T_POUCH := Vector3(-0.22, -0.52, 0.16)     # where the left hand goes for a shell (pose space, below the view)
const T_SHELL_TIME := 0.62
const T_HAMMER_DOWN := -22.0                  # degrees about Z from cocked (the model's pose)
const T_PORT := Vector3(-0.095, 0.168, 0.026)  # the ejection port, right side of the receiver
# a shell's way in: held under the loading port nose up, up into it, forward into the tube
const T_SHELL_BELOW := Vector3(-0.112, 0.068, 0.0)  # base of the shell, below the port
const T_SHELL_UP := Vector3(-0.104, 0.1185, 0.0)    # up in the receiver, on the magazine's axis
const T_SHELL_HOME := Vector3(-0.010, 0.1185, 0.0)  # pushed forward into the tube
const T_SHELL_TILT := 22.0                           # nose up below the port (degrees)
const T_SHELL_BASE := 0.034                          # the shell's base from its origin (along -X)

var _sg_root: Node3D
var _sg_model: Node3D
var _sg_muzzle: Node3D
var _sg_pump: Node3D
var _sg_hammer: Node3D
var _sg_pump_rest := Vector3.ZERO
var _sg_pump_s := 0.0                         # 0 forward .. 1 right back
var _sg_cocked := true
var _sg_ejected := true
var _sg_clacked := 0
var _sg_shell_in := false
var sg_hulls: Array[RigidBody3D] = []         # spent hulls thrown (for the tests)


func _build_trench() -> void:
	var root := Node3D.new()
	root.name = "TrenchShotgun"
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var left := Node3D.new()
	pose.add_child(left)
	_left.append(left)
	root.visible = false
	_sg_root = root
	if not ResourceLoader.exists(T_PATH):
		return
	_sg_model = (load(T_PATH) as PackedScene).instantiate() as Node3D
	_sg_model.name = "Model"
	# +X (the muzzle) down -Z; the bore at the height the other guns' sights are
	_sg_model.basis = Basis(Vector3.UP, PI * 0.5)
	_sg_model.position = Vector3(0, 0.018, -0.09) - _sg_model.basis * Vector3(-0.0, T_BORE.y, 0.0)
	pose.add_child(_sg_model)
	for mi in _sg_model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 2
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sg_muzzle = Node3D.new()
	_sg_muzzle.name = "Muzzle"
	_sg_muzzle.position = T_BORE + Vector3(0.03, 0, 0)
	_sg_model.add_child(_sg_muzzle)
	_sg_pump = _sg_model.find_child("Pump", true, false)
	_sg_hammer = _sg_model.find_child("Hammer", true, false)
	if _sg_pump:
		_sg_pump_rest = _sg_pump.position
	_build_arms(TRENCH, pose, _sg_model)


## A 12-bore paper shell, real size, lying along X (brass head at -X).
func _shell_mesh() -> Node3D:
	var n := Node3D.new()
	var hull := _cyl(n, 0.0093, 0.056, Vector3(0.006, 0, 0), Vector3(0, 0, 90), _mat(Color(0.42, 0.05, 0.04), 0.6, 0.0))
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := _cyl(n, 0.0098, 0.012, Vector3(-0.028, 0, 0), Vector3(0, 0, 90), _mat(Color(0.72, 0.55, 0.25), 0.3, 0.9))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 2
	return n


func _trench_fired() -> void:
	_sg_cocked = false
	_sg_ejected = false
	_sg_clacked = 0


func _animate_trench() -> void:
	var pose := _pose[TRENCH]
	if _sg_model == null:
		return
	var k := _kick * _kick
	# heavy: back into the shoulder and the muzzle up, settling slowly
	var pos := T_HOME + Vector3(0.004, 0.03 * k, 0.085 * k)
	var rot := Vector3(deg_to_rad(T_TILT.x + 10.0 * k), deg_to_rad(T_TILT.y - 1.5 * k), deg_to_rad(T_TILT.z + 2.0 * k))
	# the pump: back and forward after each shot
	var t := _since_shot
	var w := T_PUMP
	var s := 0.0
	if t > w.x and t < w.x + w.y + w.z + w.w:
		if t < w.x + w.y:
			s = smoothstep(w.x, w.x + w.y, t)
		elif t < w.x + w.y + w.z:
			s = 1.0
		else:
			s = 1.0 - smoothstep(w.x + w.y + w.z, w.x + w.y + w.z + w.w, t)
		if _sg_clacked == 0 and t > w.x:
			_sg_clacked = 1
			SfxSynth.play(self, "pump_back", global_position, -6.0, randf_range(0.95, 1.05))
		if _sg_clacked == 1 and t > w.x + w.y + w.z:
			_sg_clacked = 2
			SfxSynth.play(self, "pump_fwd", global_position, -5.0, randf_range(0.95, 1.05))
	if s > 0.92 and not _sg_ejected:
		_sg_ejected = true
		_sg_cocked = true
		_throw_hull()
	_sg_pump_s = s
	# the whole gun gives with the stroke, most at the back of it
	var rack := smoothstep(0.0, 1.0, s)
	pos += T_RACK_POS * rack
	rot += T_RACK_ROT * (PI / 180.0) * rack
	# loading: rolled over to the left and up, the loading port toward the eye and the
	# left hand; eases in and back out (also when a shot breaks it off)
	var want := 1.0 if _reload_t >= 0.0 else 0.0
	_sg_load = move_toward(_sg_load, want, _frame_dt / (T_SHELL_INTRO if want > 0.0 else 0.22))
	var load := smoothstep(0.0, 1.0, _sg_load)
	pos += T_LOAD_POS * load
	rot += T_LOAD_ROT * (PI / 180.0) * load
	pose.position = pos
	pose.rotation = rot
	if _sg_pump:
		_sg_pump.position = _sg_pump_rest + Vector3(-T_PUMP_TRAVEL * s, 0, 0)
	if _sg_hammer:
		var cock := 1.0 if _sg_cocked else s
		_sg_hammer.rotation.z = deg_to_rad(T_HAMMER_DOWN) * (1.0 - cock)
	# the trigger finger: a quick squeeze at the shot
	if load > 0.001 and _arms.has(TRENCH):
		var ra: FPArm = _arms[TRENCH]["R"]
		var g: Dictionary = ARM_GRIPS[TRENCH]["R"]
		var m := _sg_model.transform
		var hand := ra.frame_from_knuckles(m * g.index_k, m * g.little_k, m.basis * g.palm)
		ra.set_pose(g.pose)
		ra.place(hand, (m * g.elbow).lerp(T_LOAD_R_ELBOW, load))
		_sg_r_moved = true
	elif _sg_r_moved:
		_sg_r_moved = false
		apply_grip(TRENCH, _grips_live[TRENCH], _sg_model)
		_arm_pull_last = -1.0
	_arm_trigger(TRENCH, 1.0 - smoothstep(0.0, 0.14, t) if t < 0.14 else 0.0)
	_trench_left(s, load)


## The left hand: on the pump (riding it), or loading: down to the belt for a
## shell, up under the loading port holding it by the brass, up into the port and
## forward into the tube with the thumb behind it, down for the next. The shell
## follows the hand until it reaches the port; then the hand follows the shell.
var _sg_load := 0.0                           # 0 on the pump .. 1 loading (eased)
var _sg_r_moved := false                      # the right elbow has been moved for loading
var _sg_load_key: Array = []                  # the last loading key (to ease back from)
var _sg_load_shell: Node3D                    # the shell going in (in the gun model's space)


func _sg_pump_key(arm: FPArm, pump_s: float) -> Array:
	var g: Dictionary = ARM_GRIPS[TRENCH]["L"]
	var m := _sg_model.transform
	var off := Vector3(-T_PUMP_TRAVEL * pump_s, 0, 0)
	var hand := arm.frame_from_knuckles(m * (g.index_k + off), m * (g.little_k + off), m.basis * g.palm)
	return [hand, m * g.elbow, g.pose]


## The hand holding the shell by its base: pinch point on `base`, the hand behind
## and below it, coming from the left.
func _sg_shell_key(arm: FPArm, base: Vector3) -> Array:
	var m := _sg_model.transform
	var along := (m.basis * Vector3(0.75, 0.45, 0.30)).normalized()
	var up := m.basis * Vector3.UP
	var palm := (up - along * up.dot(along)).normalized()
	var hand := FPArm.frame(Vector3.ZERO, along, palm)
	if not _pinch_off.has(arm):
		arm.set_pose(PINCH_POSE)
		_pinch_off[arm] = arm.pinch_offset()
	hand.origin = m * base - hand.basis * (_pinch_off[arm] as Vector3)
	return [hand, Vector3(-0.20, -0.85, 0.15), PINCH_POSE]


func _sg_pouch_key(arm: FPArm, pump_hand: Array) -> Array:
	var h: Transform3D = pump_hand[0]
	# a fixed spot low on the left of the view (the belt), whatever the gun is doing
	return [Transform3D(h.basis.rotated(Vector3.RIGHT, -0.5).orthonormalized(), T_POUCH), Vector3(-0.30, -0.90, 0.20), PINCH_POSE]


## Where the shell is at loading phase `c` (0..1 of one shell): [base, axis] in model space.
func _sg_shell_at(c: float) -> Array:
	var tilted := Vector3(cos(deg_to_rad(T_SHELL_TILT)), sin(deg_to_rad(T_SHELL_TILT)), 0)
	if c < 0.65:
		var k := smoothstep(0.5, 0.65, c)
		return [T_SHELL_BELOW.lerp(T_SHELL_UP, k), tilted.slerp(Vector3.RIGHT, k)]
	var k2 := smoothstep(0.65, 0.85, c)
	return [T_SHELL_UP.lerp(T_SHELL_HOME, k2), Vector3.RIGHT]


func _sg_place_shell(base: Vector3, axis: Vector3) -> void:
	if _sg_load_shell == null:
		_sg_load_shell = _shell_mesh()
		_sg_model.add_child(_sg_load_shell)
	var x := axis.normalized()
	var z := x.cross(Vector3.UP).normalized()
	var b := Basis(x, z.cross(x), z)
	_sg_load_shell.transform = Transform3D(b, base + x * T_SHELL_BASE)


func _trench_left(pump_s: float, load: float) -> void:
	if not _arms.has(TRENCH) or not _arms[TRENCH].has("L"):
		return
	var arm: FPArm = _arms[TRENCH]["L"]
	var pump := _sg_pump_key(arm, pump_s)
	var shell_vis := false
	var key: Array
	if _reload_t >= 0.0:
		var pouch := _sg_pouch_key(arm, pump)
		var t := _reload_t
		if t < T_SHELL_INTRO:
			key = _rl_blend(pump, pouch, smoothstep(0.0, T_SHELL_INTRO * 0.8, t))
		else:
			var c := fposmod(t - T_SHELL_INTRO, T_SHELL_TIME) / T_SHELL_TIME
			var below: Array = _sg_shell_at(0.5)
			if c < 0.25:
				key = pouch                                   # a shell from the belt
			elif c < 0.5:
				key = _rl_blend(pouch, _sg_shell_key(arm, below[0]), smoothstep(0.25, 0.5, c))
				shell_vis = c > 0.3
			elif c < 0.85:
				var at: Array = _sg_shell_at(c)
				key = _sg_shell_key(arm, at[0])
				_sg_place_shell(at[0], at[1])
				shell_vis = true
			else:
				key = _rl_blend(_sg_shell_key(arm, T_SHELL_HOME), pouch, smoothstep(0.85, 1.0, c))
			if c >= 0.25 and c < 0.5 and shell_vis:
				# on its way up the shell is in the fingers: put it where the pinch is
				_rl_apply(arm, key)
				var pinch := _sg_model.transform.affine_inverse() * ((key[0] as Transform3D) * (_pinch_off[arm] as Vector3))
				_sg_place_shell(pinch, below[1])
		_sg_load_key = key
		if _sg_shell_in:
			_sg_shell_in = false
			SfxSynth.play(self, "shell_in", global_position, -8.0, randf_range(0.95, 1.08))
	elif load > 0.001 and not _sg_load_key.is_empty():
		key = _rl_blend(pump, _sg_load_key, load)             # back to the pump
	else:
		key = pump
	_rl_apply(arm, key)
	if _sg_load_shell:
		_sg_load_shell.visible = shell_vis


## The spent hull out of the port on the right, spinning, onto the floor.
func _throw_hull() -> void:
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene
	if cam == null or scene == null or _sg_model == null:
		return
	var eye := cam.global_position
	var port := _sg_model.global_transform * T_PORT
	var at := eye + (port - eye) / SHRINK
	var body := RigidBody3D.new()
	body.collision_layer = 1 << 3
	body.collision_mask = 1 | (1 << 3)
	body.mass = 0.02
	body.continuous_cd = true
	body.angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.6
	body.physics_material_override = pm
	var shape := CylinderShape3D.new()
	shape.radius = 0.0098
	shape.height = 0.068
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.z = PI * 0.5
	body.add_child(cs)
	var mesh := _shell_mesh()
	for mi in mesh.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh)
	body.add_to_group("spent_brass")
	scene.add_child(body)
	var g := _sg_model.global_transform.basis.orthonormalized()
	body.global_transform = Transform3D(g, at)
	# out to the right, up, a little back
	body.linear_velocity = g.z * randf_range(1.6, 2.3) + Vector3.UP * randf_range(1.0, 1.6) - g.x * randf_range(0.2, 0.5)
	body.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var hits := [0]
	body.body_entered.connect(func(_b: Node) -> void:
		if hits[0] < 2 and body.linear_velocity.length() > 0.5:
			hits[0] += 1
			SfxSynth.play(body, "brass_tink", body.global_position, -18.0 - hits[0] * 4.0, randf_range(0.5, 0.7)))
	sg_hulls.append(body)
	get_tree().create_timer(25.0).timeout.connect(body.queue_free)
	var all := get_tree().get_nodes_in_group("spent_brass")
	for i in maxi(all.size() - 72, 0):
		all[i].queue_free()


# --- the MP 18 (Tripo Bergmann MP 18/I, refined in Blender) -------------------------------
# art/weapons/mp18/mp18.glb, built from the untouched Tripo GLB by
# art/weapons/mp18/source/build_mp18.py: Body, StickMag (the 20-round box magazine the
# gun starts with), Drum (the snail drum and its neck; the Snail Drum upgrade) and
# Handle. Both magazines sit on the cut where they leave the magazine housing on
# the left and come out along the housing's axis. Metres, +X the muzzle, +Y up, +Z
# the right side (the magazine is on the left, -Z). Shouldered, real size.
const M_PATH := "res://art/weapons/mp18/mp18.glb"
const M_HOME := Vector3(0.12, -0.15, -0.30)
const M_TILT := Vector3(0.0, 2.5, 3.0)
const M_BORE := Vector3(0.423, 0.1256, 0.0)
const M_DRUM_OUT := Vector3(-0.491, 0.0, -0.871)   # out of the housing (model space)
const M_DRUM_TRAVEL := 0.12
## The stick runs along the housing's measured axis (build_mp18.py fits it from
## slices of the housing; it tips down and back ~6 deg from the drum's cut).
const M_STICK_OUT := Vector3(-0.5465, -0.0802, -0.8336)
const M_STICK_CENTRE := Vector3(-0.002, 0.0005, 0.0012)  # that axis at the cut, from the magazine's pivot
const M_STICK_TRAVEL := 0.07                       # the stick's top end is 3 cm up the housing; this clears it
const M_PORT := Vector3(-0.07, 0.15, 0.022)        # where the empty cases come out (right of the receiver)
## The reload (s): the hand to the drum, unlatch, draw it out, let it drop, back
## from the belt with a full one, slide it home, seat it, back to the wood.
const M_T_DRUM := {"to_drum": Vector2(0.15, 0.5), "unlatch": Vector2(0.5, 0.62), "out": Vector2(0.62, 0.95), "to_pouch": Vector2(0.95, 1.35),
	"fetch": Vector2(1.35, 1.55), "up": Vector2(1.55, 2.05), "in": Vector2(2.05, 2.4), "seat": Vector2(2.4, 2.5), "back": Vector2(2.5, 2.95), "present": Vector2(0.0, 0.3), "settle": Vector2(2.95, 3.35)}
## The stick: the hand closes round it, thumbs the catch, draws it straight out and
## lets it fall, takes a fresh one from the belt, pushes it up the housing and slaps
## it home (the same keys as the drum, quicker, and a slap for the seat).
const M_T_STICK := {"to_drum": Vector2(0.12, 0.4), "unlatch": Vector2(0.4, 0.48), "out": Vector2(0.48, 0.72), "to_pouch": Vector2(0.72, 1.05),
	"fetch": Vector2(1.05, 1.2), "up": Vector2(1.2, 1.6), "in": Vector2(1.6, 1.85), "seat": Vector2(1.9, 2.0), "back": Vector2(2.0, 2.4), "present": Vector2(0.0, 0.25), "settle": Vector2(2.4, 2.8)}
var _mt: Dictionary = M_T_STICK
const M_POUCH := Vector3(-0.24, -0.50, 0.16)
## While the drum is changed: rolled so the left side (and the drum) tips up toward
## the eye, the muzzle turned a touch right and the gun pushed out a little, so the
## drum rises into view instead of swinging back at the camera.
const M_PRESENT_POS := Vector3(0.0, -0.01, -0.05)
const M_PRESENT_ROT := Vector3(6.0, -8.0, -24.0)
## The hand on the magazine, in the magazine's own space (filled in from its size
## when the gun is built): on the drum, palm on its outer face and fingers over the
## top edge; on the stick, from below, palm up, fingers round its far side.
var _mp_drum_hand := Transform3D()
## Which magazine: false the stick (the gun as found), true the snail drum. While
## in use, _mp_drum / _mp_drum_rest / _mp_drum_hand / _mp_travel are the magazine
## in the gun (the names are from when the drum was the only one).
var mp_drum := false
var _mp_mags := {}                               # kind -> [node, rest, hand]
var _mp_travel := M_STICK_TRAVEL
var _mp_out := M_STICK_OUT

## The charging handle (rides the bolt): at rest at the back of its slot (cocked);
## it flicks forward and back with each round, and runs forward and stays there
## when the drum runs dry, until the right hand pulls it back after a drum change.
## The handle is the MP 18's own: a flat bar out of a long slot in the right of the
## receiver, bent down into a hook beside the wood (it runs the slot's length).
const M_HANDLE_TRAVEL := 0.113
const M_KNOB := Vector3(0.003, -0.0126, 0.0544)     # the hook's bend, where it is pinched, from the handle's origin (model space)
const M_CHARGE_DRUM := {"reach": Vector2(2.5, 2.7), "pull": Vector2(2.72, 2.86), "back": Vector2(2.9, 3.25)}
const M_CHARGE_STICK := {"reach": Vector2(2.02, 2.2), "pull": Vector2(2.22, 2.36), "back": Vector2(2.4, 2.75)}
var _mc: Dictionary = M_CHARGE_STICK
var mp_bolt_forward := false
var _mp_charge := false                          # this drum change ends with a pull of the handle
var _mp_handle: Node3D
var _mp_handle_rest := Vector3.ZERO
var _rl_active_mp_r := false

var _mp_model: Node3D
var _mp_muzzle: Node3D
var _mp_drum: Node3D
var _mp_drum_rest := Transform3D()
var _mp_dropped := false
var _mp_sounds := 0
var _mp_shots := 0
var _mp_smoked := true
var mp_drums: Array[RigidBody3D] = []           # empty drums dropped (for the tests)


func _build_mp18() -> void:
	var root := Node3D.new()
	root.name = "MP18"
	add_child(root)
	_guns.append(root)
	var pose := Node3D.new()
	root.add_child(pose)
	_pose.append(pose)
	var left := Node3D.new()
	pose.add_child(left)
	_left.append(left)
	root.visible = false
	if not ResourceLoader.exists(M_PATH):
		return
	_mp_model = (load(M_PATH) as PackedScene).instantiate() as Node3D
	_mp_model.name = "Model"
	_mp_model.basis = Basis(Vector3.UP, PI * 0.5)
	_mp_model.position = Vector3(0, 0.018 - M_BORE.y, -0.04)
	pose.add_child(_mp_model)
	for mi in _mp_model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 2
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mp_muzzle = Node3D.new()
	_mp_muzzle.name = "Muzzle"
	_mp_muzzle.position = M_BORE + Vector3(0.012, 0, 0)
	_mp_model.add_child(_mp_muzzle)
	_mp_handle = _mp_model.find_child("Handle", true, false)
	if _mp_handle:
		_mp_handle_rest = _mp_handle.position
	for kind: String in ["Drum", "StickMag"]:
		var node := _mp_model.find_child(kind, true, false) as Node3D
		if node == null:
			continue
		var mi := (node if node is MeshInstance3D else node.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D
		var ab := mi.get_aabb()
		var hand: Transform3D
		if kind == "Drum":
			# palm on the outer (left) face of the drum, a little below its middle; fingers up over the edge
			var face := Vector3(ab.get_center().x, ab.position.y + ab.size.y * 0.45, ab.position.z)
			hand = FPArm.frame(face - Vector3.UP * 0.07 + Vector3(0, 0, -0.022), Vector3.UP, Vector3(0, 0, 1))
		else:
			# round the stick from below, 9 cm out from the housing: palm up, fingers
			# across it toward the muzzle side, the wrist back under the gun
			var out := M_STICK_OUT
			var across := Vector3(-out.z, 0, out.x).normalized()   # level, square to the stick, toward the muzzle
			var under := across.cross(out).normalized()            # square to both, pointing down under the stick
			if under.y > 0.0:
				under = -under
			var at := M_STICK_CENTRE + out * 0.09 + under * 0.029
			hand = FPArm.frame(at - across * 0.05, across, -under)
		_mp_mags[kind] = [node, node.transform, hand]
	set_mp_drum(mp_drum)
	_build_arms(MP18, pose, _mp_model)


## Fit the stick (false) or the snail drum (true): only that one is shown, and the
## reload (its keys and length) is that magazine's.
func set_mp_drum(on: bool) -> void:
	mp_drum = on
	_mt = M_T_DRUM if on else M_T_STICK
	_mc = M_CHARGE_DRUM if on else M_CHARGE_STICK
	_mp_travel = M_DRUM_TRAVEL if on else M_STICK_TRAVEL
	_mp_out = M_DRUM_OUT if on else M_STICK_OUT
	for kind: String in _mp_mags:
		var e: Array = _mp_mags[kind]
		(e[0] as Node3D).transform = e[1]
		(e[0] as Node3D).visible = (kind == "Drum") == on
	var cur: String = "Drum" if on else "StickMag"
	if _mp_mags.has(cur):
		_mp_drum = _mp_mags[cur][0]
		_mp_drum_rest = _mp_mags[cur][1]
		_mp_drum_hand = _mp_mags[cur][2]
	_mp_dropped = false
	_mp_sounds = 0


## The MP 18's reload, for the magazine in it.
func mp_reload_time() -> float:
	return MP18_RELOAD if mp_drum else MP18_STICK_RELOAD


func mp_seat_time() -> float:
	return MP18_SEAT if mp_drum else MP18_STICK_SEAT


func _mp_fired() -> void:
	_jitter = Vector2(randf_range(-1, 1), randf_range(-0.3, 1))
	_mp_shots += 1
	_mp_smoked = false
	_throw_case()
	if _mp_shots % 4 == 0:
		_mp_smoke(0.06)


## A wisp of smoke at the real muzzle (the view is drawn shrunk toward the eye).
func _mp_smoke(seconds: float) -> void:
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene as Node3D
	if cam == null or scene == null:
		return
	var eye := cam.global_position
	var at := eye + (_mp_muzzle.global_position - eye) / SHRINK
	var sm := MechFx.smoke(scene, scene.to_local(at), seconds)
	if sm:
		sm.scale = Vector3.ONE * 0.6


func _mp_reset_reload() -> void:
	if _mp_drum == null:
		return
	_mp_drum.transform = _mp_drum_rest
	_mp_drum.visible = true
	_mp_dropped = false
	_mp_sounds = 0


func _animate_mp18() -> void:
	var pose := _pose[MP18]
	if _mp_model == null:
		return
	var k := _kick * _kick
	# each round: a short shove back and a little climb, the gun buzzing in the hands
	var buzz := Vector3(_jitter.x * 0.0025, _jitter.y * 0.002, 0) * _kick
	var pos := M_HOME + Vector3(0, 0.008 * k, 0.03 * k) + buzz
	var rot := M_TILT * (PI / 180.0) + Vector3(deg_to_rad(3.0) * k, deg_to_rad(_jitter.x * 0.6) * _kick, deg_to_rad(_jitter.x * 0.8) * _kick)
	# a longer wisp when a burst ends
	if not _mp_smoked and _since_shot > 0.2:
		_mp_smoked = true
		if _mp_shots >= 3:
			_mp_smoke(0.4)
		_mp_shots = 0
	var t := _reload_t
	if t >= 0.0:
		# lowered a little and turned so the drum on the left faces the eye
		var present := smoothstep(_mt.present.x, _mt.present.y, t) * (1.0 - smoothstep(_mt.settle.x, _mt.settle.y, t))
		pos += M_PRESENT_POS * present
		rot += M_PRESENT_ROT * (PI / 180.0) * present
		var seat := smoothstep(_mt.seat.x, _mt.seat.x + 0.04, t) * (1.0 - smoothstep(_mt.seat.x + 0.04, _mt.seat.y + 0.1, t))
		rot += Vector3(0, deg_to_rad(-2.5), 0) * seat
	pose.position = pos
	pose.rotation = rot
	if not _mp_charge or t < 0.0:
		_arm_trigger(MP18, 1.0 if _since_shot < 0.14 else 0.0)
	_mp_hands(t)
	_mp_bolt(t)


## The left hand and the drum through the reload (t < 0: on the wood).
func _mp_hands(t: float) -> void:
	if not _arms.has(MP18) or not _arms[MP18].has("L") or _mp_drum == null:
		return
	var arm: FPArm = _arms[MP18]["L"]
	var m := _mp_model.transform
	var g: Dictionary = ARM_GRIPS[MP18]["L"]
	var grip := [arm.frame_from_knuckles(m * g.index_k, m * g.little_k, m.basis * g.palm), m * g.elbow, g.pose]
	if t < 0.0:
		if _mp_dropped or _mp_drum.transform != _mp_drum_rest:
			_mp_reset_reload()
		if not _rl_active_mp:
			return
		_rl_active_mp = false
		apply_grip(MP18, _grips_live[MP18], _mp_model)
		return
	_rl_active_mp = true
	var drum_pose := PINCH_POSE.duplicate()
	# round the drum's face; closed tighter round the slim stick
	var curl: Array = [55, 50, 30] if mp_drum else [72, 68, 45]
	for f in ["index", "middle", "ring", "little"]:
		drum_pose[f + "_01"] = Vector3(curl[0], 0, 0)
		drum_pose[f + "_02"] = Vector3(curl[1], 0, 0)
		drum_pose[f + "_03"] = Vector3(curl[2], 0, 0)
	drum_pose["thumb_01"] = Vector3(10 if mp_drum else 25, 0, 0)
	drum_pose["thumb_02"] = Vector3(10 if mp_drum else 20, 0, 0)
	var elbow_d := Vector3(-0.30, -0.60, 0.10) if mp_drum else Vector3(-0.28, -0.62, 0.06)
	var e := func(r: Vector2) -> float: return smoothstep(r.x, r.y, t)
	# where the drum is along its way out (0 home .. 1 drawn out)
	var out := 0.0
	if t < _mt.out.x:
		out = 0.12 * e.call(_mt.unlatch)
	elif t < _mt.to_pouch.x:
		out = 0.12 + 0.88 * e.call(_mt.out)
	elif t < _mt.in.x:
		out = 1.0
	else:
		out = 1.0 - e.call(_mt.in)
	var drum_at := Transform3D(_mp_drum_rest.basis, _mp_drum_rest.origin + _mp_out * _mp_travel * out)
	var on_drum := func(d: Transform3D) -> Array: return [m * d * _mp_drum_hand, elbow_d, drum_pose]
	var pouch := [Transform3D((m * drum_at * _mp_drum_hand).basis.rotated(Vector3.RIGHT, -0.4).orthonormalized(), M_POUCH), Vector3(-0.30, -0.85, 0.20), drum_pose]
	var key: Array
	var carried := false
	if t < _mt.to_drum.x:
		key = grip
	elif t < _mt.to_drum.y:
		key = _rl_blend(grip, on_drum.call(drum_at), e.call(_mt.to_drum))
	elif t < _mt.to_pouch.x:
		key = on_drum.call(drum_at)
	elif t < _mt.fetch.x:
		key = _rl_blend(on_drum.call(drum_at), pouch, e.call(_mt.to_pouch))
	elif t < _mt.up.x:
		key = pouch
		carried = t > _mt.fetch.x + 0.1
	elif t < _mt.in.x:
		key = _rl_blend(pouch, on_drum.call(drum_at), e.call(_mt.up))
		carried = true
	elif t < _mt.back.x:
		key = on_drum.call(drum_at)
		if not mp_drum and t < _mt.seat.y:
			# the slap: the hand drops off a couple of centimetres and comes back hard
			var sl := sin(clampf((t - _mt.in.y) / (_mt.seat.y - _mt.in.y), 0.0, 1.0) * PI)
			var h: Transform3D = key[0]
			key = [Transform3D(h.basis, h.origin + Vector3.DOWN * 0.025 * sl), key[1], key[2]]
	else:
		key = _rl_blend(on_drum.call(drum_at), grip, e.call(_mt.back))
	_rl_apply(arm, key)
	# the drum: on its housing, drawn out by the hand, dropped, carried back
	if t >= _mt.to_pouch.x and not _mp_dropped:
		_mp_dropped = true
		_drop_drum()
	if carried:
		# in the hand: wherever the hand is, the drum is where it sits in it
		_mp_drum.transform = m.affine_inverse() * (key[0] as Transform3D) * _mp_drum_hand.affine_inverse()
		_mp_drum.visible = true
	elif t >= _mt.to_pouch.x and t < _mt.up.x:
		_mp_drum.visible = false
	else:
		_mp_drum.transform = drum_at
		_mp_drum.visible = true
	if _mp_sounds == 0 and t >= _mt.unlatch.x:
		_mp_sounds = 1
		SfxSynth.play(self, "drum_out" if mp_drum else "mag_out", global_position, -6.0, randf_range(0.95, 1.05))
	if _mp_sounds == 1 and t >= _mt.seat.x:
		_mp_sounds = 2
		SfxSynth.play(self, "drum_in" if mp_drum else "mag_in", global_position, -4.0, randf_range(0.95, 1.05))
var _rl_active_mp := false


## The handle: with each round (and forward when empty), and the right hand's pull.
func _mp_bolt(t: float) -> void:
	if _mp_handle == null:
		return
	var f := 0.0
	if mp_bolt_forward:
		f = 1.0
	elif _since_shot < 0.07:
		f = smoothstep(0.0, 0.012, _since_shot) * (1.0 - smoothstep(0.02, 0.06, _since_shot))
	var ra: FPArm = _arms[MP18]["R"] if _arms.has(MP18) else null
	if t >= 0.0 and _mp_charge and ra:
		var e := func(r: Vector2) -> float: return smoothstep(r.x, r.y, t)
		if t >= _mc.pull.x:
			f = 1.0 - e.call(_mc.pull)
			if _mp_sounds < 3 and t >= _mc.pull.x + 0.03:
				_mp_sounds = 3
				SfxSynth.play(self, "mp18_charge", global_position, -5.0, randf_range(0.95, 1.05))
			if t >= _mc.pull.y:
				mp_bolt_forward = false
		_mp_handle.position = _mp_handle_rest + Vector3(M_HANDLE_TRAVEL * f, 0, 0)
		var grip := _rl_grip_for(MP18, ra, "R")
		var knob := _mp_knob_key(ra)
		var key: Array
		if t < _mc.reach.x:
			key = grip
		elif t < _mc.reach.y:
			key = _rl_blend(grip, knob, e.call(_mc.reach))
		elif t < _mc.back.x:
			key = knob
		else:
			key = _rl_blend(knob, grip, e.call(_mc.back))
		_rl_apply(ra, key)
		_rl_active_mp_r = true
		return
	_mp_handle.position = _mp_handle_rest + Vector3(M_HANDLE_TRAVEL * f, 0, 0)
	if _rl_active_mp_r:
		_rl_active_mp_r = false
		apply_grip(MP18, _grips_live[MP18], _mp_model)
		_arm_pull_last = -1.0


## A side's grip on gun `gun` (ARM_GRIPS), as a key.
func _rl_grip_for(gun: int, arm: FPArm, side: String) -> Array:
	var model: Node3D = _mp_model if gun == MP18 else (_sg_model if gun == TRENCH else (_le_model if gun == RIFLE else _rev_model))
	var m := model.transform
	var g: Dictionary = ARM_GRIPS[gun][side]
	var hand := arm.frame_from_knuckles(m * g.index_k, m * g.little_k, m.basis * g.palm) if g.has("index_k") else FPArm.frame(m * g.wrist, m.basis * g.along, m.basis * g.palm)
	return [hand, m * g.elbow, g.pose]


## The right hand pinching the handle's knob, coming from behind and to the right.
func _mp_knob_key(arm: FPArm) -> Array:
	var m := _mp_model.transform
	var knob := m * (_mp_handle.position + M_KNOB)
	var along := (m.basis * Vector3(0.62, -0.15, -0.55)).normalized()
	var toward := m.basis * Vector3(0, 0, -1)
	var palm := (toward - along * toward.dot(along)).normalized()
	var hand := FPArm.frame(Vector3.ZERO, along, palm)
	if not _pinch_off.has(arm):
		arm.set_pose(PINCH_POSE)
		_pinch_off[arm] = arm.pinch_offset()
	hand.origin = knob - hand.basis * (_pinch_off[arm] as Vector3)
	return [hand, Vector3(0.32, -0.60, 0.38), PINCH_POSE]


## The empty drum off the gun and down, a real body at full size.
func _drop_drum() -> void:
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene
	if cam == null or scene == null:
		return
	var src := (_mp_drum if _mp_drum is MeshInstance3D else _mp_drum.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D
	var eye := cam.global_position
	var g := src.global_transform
	var ab := src.get_aabb()
	var body := RigidBody3D.new()
	body.collision_layer = 1 << 3
	body.collision_mask = 1 | (1 << 3)
	body.mass = 1.2 if mp_drum else 0.35
	body.angular_damp = 1.0
	var shape := BoxShape3D.new()
	shape.size = ab.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = ab.get_center()
	body.add_child(cs)
	var copy := MeshInstance3D.new()
	copy.mesh = src.mesh
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(copy)
	scene.add_child(body)
	body.global_transform = Transform3D(g.basis.orthonormalized(), eye + (g.origin - eye) / SHRINK)
	var gm := _mp_model.global_transform.basis.orthonormalized()
	body.linear_velocity = gm * _mp_out * 0.8 + Vector3.DOWN * 0.5
	body.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var hit := [false]
	body.body_entered.connect(func(_b: Node) -> void:
		if not hit[0]:
			hit[0] = true
			SfxSynth.play(body, "metal_rattle", body.global_position, -14.0, randf_range(0.9, 1.1)))
	mp_drums.append(body)
	get_tree().create_timer(30.0).timeout.connect(body.queue_free)


## One spent 9 mm case out of the right side.
func _throw_case() -> void:
	var cam := get_parent() as Node3D
	var scene := get_tree().current_scene
	if cam == null or scene == null or _mp_model == null:
		return
	var eye := cam.global_position
	var at := eye + (_mp_model.global_transform * M_PORT - eye) / SHRINK
	var body := RigidBody3D.new()
	body.collision_layer = 1 << 3
	body.collision_mask = 1
	body.mass = 0.008
	var shape := CylinderShape3D.new()
	shape.radius = 0.005
	shape.height = 0.019
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.z = PI * 0.5
	body.add_child(cs)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.005
	cm.bottom_radius = 0.005
	cm.height = 0.019
	cm.radial_segments = 8
	cm.rings = 1
	mesh.mesh = cm
	mesh.material_override = _brass_mat()
	mesh.rotation.z = PI * 0.5
	body.add_child(mesh)
	body.add_to_group("spent_brass")
	scene.add_child(body)
	var gm := _mp_model.global_transform.basis.orthonormalized()
	body.global_transform = Transform3D(gm, at)
	body.linear_velocity = gm.z * randf_range(1.8, 2.6) + Vector3.UP * randf_range(1.0, 1.7) - gm.x * randf_range(0.0, 0.4)
	body.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var hits := [0]
	body.body_entered.connect(func(_b: Node) -> void:
		if hits[0] < 1 and body.linear_velocity.length() > 0.6:
			hits[0] += 1
			SfxSynth.play(body, "brass_tink", body.global_position, -20.0, randf_range(1.1, 1.4)))
	get_tree().create_timer(15.0).timeout.connect(body.queue_free)
	var all := get_tree().get_nodes_in_group("spent_brass")
	for i in maxi(all.size() - 72, 0):
		all[i].queue_free()
var _brass_m: StandardMaterial3D


func _brass_mat() -> StandardMaterial3D:
	if _brass_m == null:
		_brass_m = _mat(Color(0.75, 0.58, 0.28), 0.3, 0.9)
	return _brass_m


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
