class_name FpsPlayer
extends CharacterBody3D
## First-person player. WASD move, Shift sprint, mouse look, left click fire,
## R reload, 1 pistol, 2 shotgun, 3 submachine gun, 4 stake gun, 6 rifle,
## 7 revolver, F flashlight,
## G god mode (no damage; for testing).
## L every eligible Zornhauptmann kill is a Last Defiance (for testing).
## Q Carnival Curse (once charged by ten kills; see CarnivalCurse).

const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2
const LAYER_RAMP := 1 << 4

const WEAPONS := [
	{name = "Pistol", damage = 34.0, pellets = 1, spread = 0.0, impulse = 14.0, heavy = false, can_dismember = false, cooldown = 0.22, falloff = 60.0, mag = 17},
	{name = "Shotgun", damage = 16.0, pellets = 9, spread = 4.5, impulse = 16.0, heavy = true, can_dismember = true, cooldown = 0.8, falloff = 9.0, mag = 6, shells = true},
	{name = "SMG", damage = 21.0, pellets = 1, spread = 1.8, impulse = 8.0, heavy = false, can_dismember = false, cooldown = 0.085, falloff = 28.0, mag = 32},
	# the crossbow (the old stake gun's slot): one bolt, spanned by hand. Its damage is
	# CrossbowBolt.DAMAGE times the clown's zone multiplier (head x4, torso x1, limbs less)
	{name = "Crossbow", label = "Crossbow", damage = 70.0, pellets = 1, spread = 0.0, impulse = 1.6, heavy = false, can_dismember = false, cooldown = 0.5, falloff = 100.0, mag = 1, projectile = true, ads = true},
	{name = "Maxim", damage = 60.0, pellets = 1, spread = 2.4, impulse = 22.0, heavy = true, can_dismember = true, cooldown = 0.11, falloff = 80.0, mag = 250, belt = true},
	# A WW1 Lee-Enfield SMLE Mk III (the rifle slot; `name` stays "Rifle", what the
	# saves and stats know it by; `label` is what the HUD shows). Ten rounds; one heavy
	# round per pull, and the bolt worked after every shot (`bolt`: a round must be
	# chambered to fire). Reloaded through the top with five-round chargers and loose
	# rounds. `hip_spread`: degrees of scatter from the hip, none aimed down the sights.
	{name = "Rifle", label = "SMLE Mk III", damage = 180.0, pellets = 1, spread = 0.0, hip_spread = 1.6, impulse = 20.0, heavy = true, can_dismember = false,
		cooldown = 0.95, falloff = 220.0, mag = 10, pierce = 4, punch = 3.4, shot_sfx = "rifle_shot", semi = true, bolt = true, dry = true},
	# A WW1 top-break service revolver (the Tripo model): six heavy rounds,
	# one per pull of the trigger (semi: holding the button does not repeat),
	# a hard upward kick, slow to reload. The procedural Pistol stays as the
	# testing gun.
	# `pull`: double action. The click starts a pull that turns the cylinder and
	# raises the hammer; the shot goes when it falls, this many seconds later
	# (0 fires on the click). The cooldown runs from the shot.
	# The bodies react to it exactly as to the pistol (Andrew, 18 Nov): the same
	# push, not `heavy` (so the same deaths), and `react` = the pistol's damage
	# for the flinch, stagger and dying reactions. Only the damage is bigger.
	{name = "Revolver", damage = 80.0, pellets = 1, spread = 0.0, impulse = 14.0, heavy = false, react = 34.0, can_dismember = false, cooldown = 0.38, falloff = 70.0, mag = 6, semi = true, punch = 2.4, pull = 0.12},
	# A Winchester 1897 trench gun (the Tripo model): nine pellets that hit very
	# hard close up and fall away fast with distance, a heavy kick, and the pump
	# worked after every shot (the cooldown covers the stroke; reloading waits
	# for it). Six in the tube, loaded one at a time; firing breaks off loading.
	# `shells`: loads shell by shell (like the Shotgun). `pump`: a pump to work.
	{name = "Trench Shotgun", damage = 18.0, pellets = 9, spread = 4.0, impulse = 17.0, heavy = true, can_dismember = true, cooldown = 0.85, falloff = 8.5, mag = 6, shells = true, pump = true, semi = true, punch = 4.5, shot_sfx = "shotgun_shot"},
	# A Bergmann MP 18 (the Tripo model) with a 20-round stick magazine (`mag`; the
	# Snail Drum upgrade swaps in the 32-round drum, `drum_mag`, see mag_of): fully
	# automatic at 500 rounds a minute (`rpm`: the interval is carried from shot to
	# shot so the rate is exact whatever the frame rate, and never exceeded), less
	# per round than the revolver, good up close and falling off with distance.
	# Recoil builds through a burst (`climb` degrees a shot, `climb_grow` more per
	# shot, `lateral` degrees either way); the spread opens by `spread_grow` a shot
	# (both up to `burst_cap` shots) and the view springs back when it stops.
	{name = "MP 18", damage = 26.0, pellets = 1, spread = 1.1, impulse = 9.0, heavy = false, can_dismember = false, cooldown = 0.12, rpm = 500.0, falloff = 24.0, mag = 20, drum_mag = 32,
		climb = 0.55, climb_grow = 0.07, lateral = 0.25, spread_grow = 0.09, burst_cap = 12, shot_sfx = "mp18_shot", dry = true},
]
## The machine gun on its mount in the nest: same rounds, steadier.
const MOUNTED_MG := {name = "Maxim", damage = 60.0, pellets = 1, spread = 1.1, impulse = 22.0, heavy = true, can_dismember = true, cooldown = 0.11, falloff = 120.0, mag = 0}
const PISTOL := 0
const SHOTGUN := 1
const SMG := 2
const STAKE := 3
const MAXIM := 4
const RIFLE := 5
const REVOLVER := 6
const TRENCH := 7
const MP18 := 8

## Testing aid: take no damage. Kept for the whole session, across runs.
static var god_mode := false

signal reset_requested
## A rifle round went through more than one body (how many it hit).
signal pierced(count: int)
signal health_changed(health: float, max_health: float)
signal died
signal fired(weapon: int)
signal ammo_changed

@export var speed := 4.5
@export var sprint_speed := 6.4
@export var mouse_sensitivity := 0.0022
## Set false when a game mode draws its own HUD text.
@export var show_help := true

## Changed by upgrades.
var stats := {
	damage = 1.0, fire_rate = 1.0, pellets = 0, speed = 1.0, max_health = 100.0,
	lifesteal = 0.0, pistol_dismember = false, slowmo = false, blood = 1.0, spread = 1.0,
	mp18_drum = false,
}

var health := 100.0
var dead := false
var weapon := 0
## Rounds loaded in each gun. Spare ammunition is unlimited for now.
var ammo: Array[int] = [17, 6, 32, 1, 0, 10, 6, 6, 20]
## The rifle: a round in the chamber (ammo counts it). Fired: empty until the bolt is worked.
var rifle_chambered := true
var _rifle_cycle_left := -1.0
## The rifle's reload: [time, rounds] as each charger or round goes in, and its clock.
var _rifle_events: Array = []
var _rifle_reload_t := -1.0
var _rifle_reload_total := 0.0
## Aiming down the sights (right mouse; the rifle): 0 hip .. 1 aimed.
var ads := 0.0
const ADS_FOV := 58.0
## Inside an event room (gunshots are not heard in the level).
var in_event := false
## The final-kill camera has the view: no moving, looking or shooting, and the
## gun and crosshair are put away until it hands back.
var cinematic := false:
	set(v):
		cinematic = v
		if view:
			view.visible = not v
		if hud_layer:
			hud_layer.visible = not v
var hud_layer: CanvasLayer
## The mounted gun the player is behind, if any.
var mount: Node = null
var _prompt: Label
var view: ViewModel
## Key that asks for a reset in the test room (R is reload).
var reset_key := KEY_BACKSPACE
var _reload_left := -1.0        # pistol: seconds until the new magazine is in
var _shell_left := -1.0         # shotgun: seconds until the next shell is in
var _look := Vector2.ZERO
var camera: Camera3D
var flashlight: SpotLight3D
var _cooldown := 0.0
var _shot_id := 0
var _label: Label
var _hurt: ColorRect
var _kick := 0.0
## Muzzle climb from a heavy gun: added to the camera pitch, recovering.
var _punch := 0.0
var _punch_v := 0.0
## A semi-automatic shot asked for a moment too early: taken when it can be.
var _queued := -1.0
var _dry_at := -1000
## Shots in the current burst (an automatic weapon with `rpm`), and when the last went.
var burst := 0
var _burst_at := -10.0
## A double-action pull under way: the shot goes when this runs out.
var _pull_left := -1.0
var _shake := 0.0
var _cross: Control
## The super kill, charged by kills.
var curse: CarnivalCurse

## Grenades: their own key and their own count, apart from the guns (the gun in
## hand stays selected). Hold the key to bring one up, let go to throw it
## overhand; a quick tap is a short underhand toss.
@export var grenade_key := KEY_T                    ## (G, the usual key, is the god-mode toggle here)
const GRENADE_TAP := 0.2                            ## s: let go sooner than this and it is tossed underhand
var grenade_kind := "frag"
var grenades := {}                                  ## kind -> how many carried
var grenades_thrown: Array[Grenade] = []            ## (for the tests)
var _g_key_down := false
var _g_hold := 0.0
var _g_wanted := false                              ## pressed, not brought up yet (a reload or swap finishing first)
var _g_let_go := false                              ## and already let go: throw it as soon as it is up
var _g_under := false
var _g_hud: Control


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = 1 << 1
	collision_mask = LAYER_WORLD | LAYER_RAMP
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 80.0
	camera.near = 0.02
	add_child(camera)
	camera.make_current()
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 34.0
	flashlight.light_energy = 4.0
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.15, -0.1, 0.0)
	camera.add_child(flashlight)
	view = ViewModel.new()
	camera.add_child(view)
	var hud := CanvasLayer.new()
	add_child(hud)
	hud_layer = hud
	_hurt = ColorRect.new()
	_hurt.color = Color(0.5, 0.0, 0.0, 0.0)
	_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hurt)
	var cross := Control.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_crosshair.bind(cross))
	hud.add_child(cross)
	_cross = cross
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.visible = show_help
	hud.add_child(_label)
	for k: String in Grenade.TYPES:
		grenades[k] = int(Grenade.TYPES[k].start)
	view.grenade_released.connect(_on_grenade_released)
	_g_hud = Control.new()
	_g_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_g_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_g_hud.draw.connect(_draw_grenades.bind(_g_hud))
	hud.add_child(_g_hud)
	_update_label()
	health = stats.max_health
	curse = CarnivalCurse.new()
	curse.name = "CarnivalCurse"
	add_child(curse)
	curse.setup(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A plain cross with a gap in the middle, dark outline so it shows on any surface.
func _draw_crosshair(c: Control) -> void:
	var m := (c.size * 0.5).floor()
	# Sized from the window height so it is the same apparent size on a
	# high-resolution (Retina) screen as on a small window.
	var u := maxf(1.0, c.size.y / 540.0)
	var gap := 5.0 * u
	var length := 9.0 * u
	for pass_i in 2:
		var col := Color(0, 0, 0, 0.75) if pass_i == 0 else Color(1, 1, 1, 1)
		var w := (4.0 if pass_i == 0 else 2.0) * u
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			c.draw_line(m + d * gap, m + d * (gap + length), col, w)
	# the Carnival Curse is charged and there is an enemy it can take under
	# the crosshair: a thin violet diamond round it (red when he shrugs it off)
	if curse and curse.ready_to_use() and (curse.aim_target != null or curse.aim_block == "immune"):
		var col2 := Color(0.8, 0.35, 1.0, 0.9) if curse.aim_target else Color(0.9, 0.15, 0.15, 0.8)
		var r := 20.0 * u
		var pts := PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0), m + Vector2(0, -r)])
		c.draw_polyline(pts, Color(0, 0, 0, 0.6), 3.0 * u)
		c.draw_polyline(pts, col2, 1.5 * u)


func redraw_crosshair() -> void:
	if _cross:
		_cross.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if dead or cinematic:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and mount:
		mount.look(event.relative * mouse_sensitivity)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += event.relative
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			fire()
	elif event is InputEventKey and not event.pressed and event.keycode == grenade_key:
		_grenade_up()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == grenade_key:
			_grenade_down()
		match event.keycode:
			KEY_1: select_weapon(0)
			KEY_2: select_weapon(1)
			KEY_3: select_weapon(2)
			KEY_4: select_weapon(3)
			KEY_5:
				if ammo[MAXIM] > 0:
					select_weapon(MAXIM)
			KEY_6: select_weapon(RIFLE)
			KEY_7: select_weapon(REVOLVER)
			KEY_8: select_weapon(TRENCH)
			KEY_9: select_weapon(MP18)
			KEY_E: _use()
			KEY_G:
				god_mode = not god_mode
				ammo_changed.emit()
			KEY_F: flashlight.visible = not flashlight.visible
			KEY_L:
				# testing: every eligible Zornhauptmann kill is a Last Defiance
				Zornhauptmann.always_defiance = not Zornhauptmann.always_defiance
			KEY_R: reload()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if curse and event.keycode == curse.key:
			curse.activate()
		if event.keycode == reset_key:
			reset_requested.emit()
		_update_label()


func _process(delta: float) -> void:
	view.stake_ready = ammo[STAKE] > 0
	_update_prompt()
	view.animate(delta, Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0, _look)
	_look = Vector2.ZERO
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, delta * 1.2)
	_kick = move_toward(_kick, 0.0, delta * 0.5)
	camera.rotation.z = _kick * 0.3
	_tick_punch(delta)
	# explosion shake: a hard jolt that rattles out
	if _shake > 0.001:
		_shake = move_toward(_shake, 0.0, delta * 1.6)
		var t := Time.get_ticks_msec() * 0.001
		var s := _shake * _shake
		camera.h_offset = (sin(t * 47.0) + sin(t * 83.0) * 0.5) * 0.05 * s
		camera.v_offset = (sin(t * 59.0 + 1.3) + sin(t * 97.0) * 0.5) * 0.05 * s
		camera.rotation.z += sin(t * 37.0) * 0.04 * s
	elif camera.h_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if dead:
		velocity = Vector3(0, velocity.y - 9.8 * delta, 0)
		move_and_slide()
		return
	if cinematic:
		velocity = Vector3(0, velocity.y - 9.8 * delta if not is_on_floor() else 0.0, 0)
		move_and_slide()
		return
	_tick_reload(delta)
	_tick_ads(delta)
	_tick_grenade(delta)
	# Holding the button keeps firing (not a semi-automatic: one shot a pull).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not WEAPONS[weapon].get("semi", false):
		fire()
	if _pull_left >= 0.0:
		_pull_left -= delta
		if dead or view.swapping() or view.reloading():
			_cancel_pull()
		elif _pull_left < 0.0:
			_discharge()
	if _queued >= 0.0:
		_queued -= delta
		if _cooldown <= 0.0:
			_queued = -1.0
			fire()
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if mount:
		input = Vector3.ZERO                     # hands on the gun
	var dir := (global_basis * input.normalized())
	var s: float = (sprint_speed if Input.is_key_pressed(KEY_SHIFT) else speed) * stats.speed * (0.75 if weapon == MAXIM else 1.0)
	velocity.x = dir.x * s
	velocity.z = dir.z * s
	velocity.y = velocity.y - 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()


func select_weapon(w: int) -> void:
	if w == weapon or dead or mount or view.grenade_busy():
		return
	_reload_left = -1.0
	_shell_left = -1.0
	_queued = -1.0
	_cancel_pull()
	if weapon == RIFLE:
		_rifle_put_away()
	weapon = w
	view.swap_to(w)
	_cooldown = maxf(_cooldown, ViewModel.SWAP_TIME)
	ammo_changed.emit()
	_update_label()
	if w == STAKE and ammo[STAKE] == 0:
		# drawn empty: span it and lay a bolt as soon as it is up
		get_tree().create_timer(ViewModel.SWAP_TIME + 0.05).timeout.connect(func() -> void:
			if weapon == STAKE and ammo[STAKE] == 0 and not dead:
				reload())


## Rounds a gun holds: the MP 18 takes a 20-round stick magazine until the Snail
## Drum upgrade gives it the 32-round drum.
func mag_of(w: int) -> int:
	if w == MP18 and stats.get("mp18_drum", false):
		return int(WEAPONS[w].drum_mag)
	return int(WEAPONS[w].mag)


## The MP 18 gets the snail drum (an upgrade): the view swaps the magazine and the
## gun comes up full.
func give_mp18_drum() -> void:
	stats.mp18_drum = true
	view.set_mp_drum(true)
	ammo[MP18] = mag_of(MP18)
	ammo_changed.emit()
	_update_label()


## Leaving the rifle mid-cycle or mid-reload: the bolt is closed as it goes down
## (rounds already in stay in; a round is chambered if there is one).
func _rifle_put_away() -> void:
	if _rifle_cycle_left >= 0.0 or _rifle_reload_t >= 0.0:
		_rifle_cycle_left = -1.0
		_rifle_reload_t = -1.0
		_rifle_events = []
		rifle_chambered = ammo[RIFLE] > 0
	ads = 0.0


## The rifle's reload: the bolt opens (a live round in the chamber comes out with it),
## then five-round chargers and loose rounds until it holds ten, and the bolt shut.
func _start_rifle_reload() -> void:
	if _rifle_reload_t >= 0.0 or _rifle_cycle_left >= 0.0:
		return
	var extract := rifle_chambered and ammo[RIFLE] > 0
	if extract:
		ammo[RIFLE] -= 1
	rifle_chambered = false
	var need: int = mag_of(RIFLE) - ammo[RIFLE]
	_rifle_events = view.start_rifle_reload(need / 5, need % 5, extract)
	_rifle_reload_total = view.rifle_reload_total()
	_rifle_reload_t = 0.0
	view.le_rounds_in_mag = ammo[RIFLE]
	ammo_changed.emit()
	_update_label()


func _tick_rifle(delta: float) -> void:
	if _rifle_cycle_left >= 0.0:
		_rifle_cycle_left -= delta
		if _rifle_cycle_left < 0.0:
			rifle_chambered = ammo[RIFLE] > 0          # the bolt went home on the next round
	if _rifle_reload_t >= 0.0:
		_rifle_reload_t += delta
		while not _rifle_events.is_empty() and _rifle_reload_t >= float(_rifle_events[0][0]):
			ammo[RIFLE] = mini(ammo[RIFLE] + int(_rifle_events[0][1]), mag_of(RIFLE))
			_rifle_events.pop_front()
			view.le_rounds_in_mag = ammo[RIFLE]
			ammo_changed.emit()
			_update_label()
		if _rifle_reload_t >= _rifle_reload_total:
			_rifle_reload_t = -1.0
			view.stop_reload()
			rifle_chambered = ammo[RIFLE] > 0          # the bolt shut on the top round
	view.le_rounds_in_mag = ammo[RIFLE] - (1 if rifle_chambered else 0)


## Start reloading the gun in hand, if it has room.
func reload() -> void:
	if WEAPONS[weapon].get("belt", false):
		return                                   # a belt: what you have is what you get
	if dead or view.swapping() or view.reloading() or view.grenade_busy() or ammo[weapon] >= mag_of(weapon):
		return
	if WEAPONS[weapon].get("pump", false) and _cooldown > 0.0:
		return                                   # still working the pump
	if weapon == RIFLE:
		_start_rifle_reload()
		return
	view.start_reload()
	if weapon == PISTOL:
		_reload_left = ViewModel.PISTOL_RELOAD * 0.62      # the moment the magazine seats
	elif weapon == SMG:
		_reload_left = ViewModel.SMG_SEAT
	elif weapon == STAKE:
		_reload_left = ViewModel.STAKE_SEAT
	elif weapon == REVOLVER:
		_reload_left = ViewModel.REVOLVER_SEAT
		SfxSynth.play(self, "revolver_open", camera.global_position, -8.0, 1.0)
	elif weapon == MP18:
		_reload_left = view.mp_seat_time()
	else:
		_shell_left = view.shell_intro() + view.shell_time() * 0.85


## The climb after a heavy shot: pitch goes up fast, then settles back over
## about half a second (a spring), so the next deliberate shot is on target.
func _tick_punch(delta: float) -> void:
	if absf(_punch) < 0.00001 and absf(_punch_v) < 0.00001:
		return
	var before := _punch
	# small fixed steps: a long frame (a hitch) must not throw the spring out
	var left := minf(delta, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		_punch_v += (-_punch * 90.0 - _punch_v * 13.0) * h
		_punch += _punch_v * h
		left -= h
	camera.rotation.x = clampf(camera.rotation.x + (_punch - before), -1.5, 1.5)


## Aiming down the rifle's sights (right mouse held): the view narrows, the gun comes
## up to the eye; not while reloading or changing guns. Other guns: none.
func _tick_ads(delta: float) -> void:
	var can_aim: bool = weapon == RIFLE or WEAPONS[weapon].get("ads", false)
	var want := can_aim and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if aim_override >= 0.0:
		want = aim_override > 0.5 and can_aim
	if view.reloading() or view.swapping() or view.grenade_busy() or not can_aim:
		want = false
	ads = move_toward(ads, 1.0 if want else 0.0, delta * 5.0)
	view.ads = ads
	if not cinematic:
		camera.fov = lerpf(80.0, ADS_FOV, smoothstep(0.0, 1.0, ads))
## The tests hold the aim without a mouse: -1 off, 0 not aiming, 1 aiming.
var aim_override := -1.0


## Loads shell by shell (the shotguns): can be fired part-way through.
func _shells() -> bool:
	return WEAPONS[weapon].get("shells", false)


func _tick_reload(delta: float) -> void:
	if weapon == RIFLE:
		_tick_rifle(delta)
		return
	if not _shells():
		if _reload_left >= 0.0:
			_reload_left -= delta
			if _reload_left < 0.0:
				ammo[weapon] = mag_of(weapon)
				if weapon == REVOLVER:
					SfxSynth.play(self, "revolver_close", camera.global_position, -6.0, 1.0)
					view.revolver_loaded()
				ammo_changed.emit()
				_update_label()
		var total: float = {PISTOL: ViewModel.PISTOL_RELOAD, SMG: ViewModel.SMG_RELOAD, STAKE: ViewModel.STAKE_RELOAD, REVOLVER: ViewModel.REVOLVER_RELOAD, MP18: view.mp_reload_time()}.get(weapon, ViewModel.STAKE_RELOAD)
		if view.reloading() and view._reload_t >= total:
			view.stop_reload()
			view.slide_locked = false
	elif _shell_left >= 0.0:
		# Shells go in one at a time, so the shotgun can be fired part-way through.
		_shell_left -= delta
		if _shell_left < 0.0:
			ammo[weapon] += 1
			view.shell_loaded()
			ammo_changed.emit()
			_update_label()
			if ammo[weapon] >= mag_of(weapon):
				_shell_left = -1.0
				view.stop_reload()
			else:
				_shell_left = view.shell_time()


func fire() -> void:
	if mount:
		mount.trigger()
		return
	if _pull_left >= 0.0:
		return                                   # already pulling: the shot is on its way
	if _cooldown > 0.0 and WEAPONS[weapon].get("semi", false) and not dead:
		_queued = 0.15                           # pulled a moment early: fire when it can
	if _cooldown > 0.0 or dead or view.swapping() or view.grenade_busy():
		return
	if WEAPONS[weapon].get("belt", false) and ammo[weapon] <= 0:
		select_weapon(PISTOL)                    # belt empty: the gun is thrown away
		return
	if not _shells() and view.reloading():
		return
	if ammo[weapon] <= 0:
		if WEAPONS[weapon].get("dry", false) and not view.reloading() and Time.get_ticks_msec() - _dry_at > 400:
			_dry_at = Time.get_ticks_msec()
			SfxSynth.play(self, "dry_click", camera.global_position, -10.0, 1.1)   # the trigger on an empty drum
		reload()
		return
	if WEAPONS[weapon].get("bolt", false) and not rifle_chambered:
		if _rifle_reload_t >= 0.0 or _rifle_cycle_left >= 0.0:
			return
		_rifle_cycle_left = ViewModel.RIFLE_CYCLE       # closed on an empty chamber (a reload broken off): work it
		_cooldown = ViewModel.RIFLE_CYCLE
		view.rifle_cycle()
		return
	if weapon == MP18 and view.mp_bolt_forward and not view.reloading():
		view.mp_bolt_forward = false             # a full drum went on but the handle was never pulled (a swap mid-change): cocked now
	if _shells() and view.reloading():
		_shell_left = -1.0                      # break off loading to shoot
		view.stop_reload()
	var pull: float = WEAPONS[weapon].get("pull", 0.0)
	if pull > 0.0:
		# double action: the trigger comes back, the cylinder turns, the hammer rises
		_pull_left = pull
		view.start_pull(pull)
		# the click-click of the cylinder stop and the hammer coming back: what sells the pull
		SfxSynth.play(self, "revolver_cock", camera.global_position + camera.global_basis * Vector3(0.15, -0.15, -0.35), -4.0, randf_range(0.96, 1.04))
		return
	_discharge()


func _cancel_pull() -> void:
	if _pull_left >= 0.0:
		_pull_left = -1.0
		view.cancel_pull()


## The shot itself (after the pull, for a double-action gun).
func _discharge() -> void:
	_pull_left = -1.0
	if ammo[weapon] <= 0:
		return
	var w: Dictionary = WEAPONS[weapon]
	if w.has("rpm"):
		# exact rate: carry what is left of the interval into the next one (only
		# while the burst goes on: a fresh pull starts from now)
		var interval: float = 60.0 / w.rpm / stats.fire_rate
		var now := Time.get_ticks_msec() / 1000.0
		var going := now - _burst_at < interval * 2.5 and _cooldown > -interval
		_cooldown = (_cooldown + interval) if going else interval
		burst = (burst + 1) if going else 1
		_burst_at = now
	else:
		_cooldown = w.cooldown / stats.fire_rate
	_shot_id += 1
	ammo[weapon] -= 1
	if weapon == 0 and ammo[0] == 0:
		view.slide_locked = true
	if weapon == MP18 and ammo[MP18] == 0:
		view.mp_bolt_forward = true              # the last round: the bolt runs home on an empty drum
	if weapon == RIFLE:
		rifle_chambered = false                  # fired: the case is in the chamber until the bolt is worked
		_rifle_cycle_left = ViewModel.RIFLE_CYCLE
	view.fire()
	var from := camera.global_position
	var aim := -camera.global_basis.z
	if w.has("punch"):
		# a heavy round: the muzzle climbs, the view jolts, and it is loud
		_punch_v += deg_to_rad(w.punch) * randf_range(0.9, 1.1) * 14.0
		_kick += randf_range(-0.05, 0.05)
		shake(0.14)
		SfxSynth.play(self, w.get("shot_sfx", "revolver_shot"), camera.global_position + aim * 0.3, 2.0, randf_range(0.95, 1.04))
	if w.has("climb"):
		# an automatic: each round lifts the muzzle a little more than the last, and
		# pushes it a touch to one side; the spring brings the pitch back after
		var b := float(mini(burst, w.burst_cap))
		_punch_v += deg_to_rad(w.climb * (1.0 + w.climb_grow * b)) * 14.0 * randf_range(0.85, 1.15)
		rotate_y(deg_to_rad(randf_range(-1.0, 1.0) * w.lateral * (0.6 + 0.4 * b / w.burst_cap)))
		SfxSynth.play(self, w.get("shot_sfx", "revolver_shot"), camera.global_position + aim * 0.3, -1.0, randf_range(0.96, 1.05))
	if w.get("projectile", false):
		# a bolt, not a bullet: it flies, and the crossbow is spanned again by itself
		var world := get_tree().get_first_node_in_group(&"world_root")
		var ex: Array[RID] = [get_rid()]
		CrossbowBolt.launch(world if world else get_parent(), from + aim * 0.25, aim, _shot_id, ex)
		SfxSynth.play(self, "xbow_shot", camera.global_position + aim * 0.3, 0.0, randf_range(0.95, 1.05))
		_kick = 0.22
		shake(0.1)
		get_tree().create_timer(0.45).timeout.connect(func() -> void:
			if weapon == STAKE and ammo[STAKE] == 0:
				reload())
		fired.emit(weapon)
		ammo_changed.emit()
		_update_label()
		return
	var pellets: int = w.pellets + (stats.pellets if w.pellets > 1 else 0)
	for i in pellets:
		var d := aim
		var spread: float = w.spread + float(w.get("hip_spread", 0.0)) * (1.0 - ads)    # the rifle from the hip scatters; aimed it does not
		if spread > 0.0:
			var s: float = deg_to_rad(spread) * (stats.spread if w.pellets > 1 else 1.0)
			if w.has("spread_grow"):
				s *= 1.0 + w.spread_grow * float(mini(burst, w.burst_cap))
			d = (aim + camera.global_basis.x * randfn(0.0, s * 0.5) + camera.global_basis.y * randfn(0.0, s * 0.5)).normalized()
		shoot_ray(from, d, w, _shot_id)
	fired.emit(weapon)
	ammo_changed.emit()
	_update_label()


## Fire one ray with a weapon definition. Also used by the automated tests.
func shoot_ray(from: Vector3, dir: Vector3, w: Dictionary, shot_id: int, also_ignore: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 130.0, LAYER_WORLD | LAYER_RAGDOLL)
	var ex: Array[RID] = [get_rid()]
	ex.append_array(also_ignore)
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_near_misses(from, hit.position if not hit.is_empty() else from + dir * 130.0, hit.get("collider"))
	if hit.is_empty():
		return hit
	var c: Object = hit.collider
	if not (c is PhysicalBone3D) and c.has_method("shot"):
		# drums, gallery targets: anything that reacts to being hit
		c.shot(hit.position, dir, w.damage * stats.damage)
		return hit
	if c is PhysicalBone3D and c.has_meta(&"clown"):
		_hit_clown(c, hit.position, from, from.distance_to(hit.position), dir, w, shot_id, 1.0)
		var pierce: int = w.get("pierce", 0)
		if pierce > 0:
			_pierce(c.get_meta(&"clown"), hit.position, from, dir, w, shot_id, pierce, ex)
	return hit


## A round that goes close by a man he did not hit (within 1.3 m of his
## chest, along the line it flew): he hears it crack past (the soldiers' brains
## flinch, duck and keep their heads down; the men out in No Man's Land get down).
func _near_misses(from: Vector3, to: Vector3, hit_collider: Object) -> void:
	var hit_clown: Object = hit_collider.get_meta(&"clown") if hit_collider is PhysicalBone3D and (hit_collider as Object).has_meta(&"clown") else null
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 < 0.01:
		return
	for n in get_tree().get_nodes_in_group(&"clowns"):
		var c := n as Clown
		if c == null or c == hit_clown or c.dead:
			continue
		var chest := c.global_position + Vector3.UP * 1.25
		var t := clampf((chest - from).dot(seg) / len2, 0.0, 1.0)
		if t <= 0.0 or t >= 1.0:
			continue                              # not past him (stopped short, or behind the gun)
		var d := chest.distance_to(from + seg * t)
		if d > 1.3:
			continue
		var b := c.get_node_or_null("Brain")
		if b and b.has_method("near_miss"):
			b.near_miss(from, d, from + seg * t)
		var f := c.get_node_or_null("Field")
		if f and f.has_method("duck"):
			f.duck(randf_range(0.8, 1.6))


func _hit_clown(c: PhysicalBone3D, at: Vector3, from: Vector3, dist: float, dir: Vector3, w: Dictionary, shot_id: int, mult: float) -> void:
	var scale := clampf(1.0 - maxf(dist - w.falloff * 0.4, 0.0) / w.falloff, 0.2, 1.0) * mult
	(c.get_meta(&"clown") as Clown).hit({
		collider = c, position = at, direction = dir,
		damage = w.damage * scale * stats.damage, impulse = w.impulse * scale,
		react = w.get("react", w.damage) * scale * stats.damage,
		heavy = w.heavy and scale > 0.5,
		can_dismember = (w.can_dismember or (stats.pistol_dismember and w.name == "Pistol")) and scale > 0.6,
		shot_id = shot_id, blood = stats.blood, dist = dist, weapon = w.name,
	})


## A round that goes on through: out the back of this one (blood and all),
## into whoever is behind, up to `left` more bodies or a wall.
func _pierce(first: Clown, at: Vector3, origin: Vector3, dir: Vector3, w: Dictionary, shot_id: int, left: int, ex: Array[RID]) -> void:
	var ss := get_world_3d().direct_space_state
	var victim := first
	var pos := at
	var mult := 1.0
	var through := 0
	while left > 0 and victim:
		for pb: PhysicalBone3D in victim.ragdoll.bones.values():
			ex.append(pb.get_rid())
		# where it comes out of this body: the far side along the line
		var out := pos + dir * 0.3
		var back := PhysicsRayQueryParameters3D.create(pos + dir * 0.7, pos, LAYER_RAGDOLL)
		back.exclude = [get_rid()]
		var exit_hit := ss.intersect_ray(back)
		if not exit_hit.is_empty() and exit_hit.collider is PhysicalBone3D and exit_hit.collider.get_meta(&"clown", null) == victim:
			out = exit_hit.position
		Blood.spawn_hit(out, dir, 1.3 * stats.blood, victim.mechanical)
		mult *= 0.85
		left -= 1
		var q := PhysicsRayQueryParameters3D.create(out, out + dir * 120.0, LAYER_WORLD | LAYER_RAGDOLL)
		q.exclude = ex
		var h := ss.intersect_ray(q)
		victim = null
		if h.is_empty():
			break
		var c: Object = h.collider
		if c is PhysicalBone3D and c.has_meta(&"clown"):
			through += 1
			_hit_clown(c, h.position, origin, origin.distance_to(h.position), dir, w, shot_id + 1000 * through, mult)
			victim = c.get_meta(&"clown")
			pos = h.position
		elif c.has_method("shot"):
			c.shot(h.position, dir, w.damage * mult * stats.damage)
	if through > 0:
		pierced.emit(through + 1)


## [E]: open a door, take a mounted gun, whatever is in front of you.
func _use() -> void:
	if mount:
		if mount.has_method("can_leave") and not mount.can_leave():
			return
		dismount()
		return
	var u := _usable()
	if u:
		u.use(self)


func _usable() -> Object:
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 2.4, LAYER_WORLD)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var c: Object = hit.collider
	return c if c.has_method("use") else null


func _update_prompt() -> void:
	if _prompt == null:
		_prompt = Label.new()
		_prompt.add_theme_font_size_override("font_size", 20)
		_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
		_prompt.add_theme_constant_override("outline_size", 6)
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_prompt.position.y += 60
		_prompt.size.x = 400
		_prompt.position.x -= 200
		_label.get_parent().add_child(_prompt)
	var text := ""
	if mount:
		text = mount.prompt() if mount.has_method("prompt") else ""
	else:
		var u := _usable()
		if u and u.has_method("prompt"):
			text = u.prompt()
	_prompt.text = text


## Take a mounted gun: the body stays put and the mouse swings the gun.
func take_mount(m: Node, stand_at: Transform3D) -> void:
	mount = m
	global_transform = stand_at
	velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	view.visible = false


func dismount() -> void:
	if mount == null:
		return
	var m := mount
	mount = null
	view.visible = true
	if m.has_method("released"):
		m.released()


## Rattle the view (explosions). 1.0 is a drum going up a few metres away.
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.5)


func take_damage(amount: float, from_dir: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	if god_mode:
		_hurt.color.a = clampf(0.08 + amount * 0.005, 0.0, 0.2)     # still see you were hit
		return
	health = maxf(health - amount, 0.0)
	_hurt.color.a = clampf(0.25 + amount * 0.02, 0.0, 0.7)
	_kick = clampf(from_dir.dot(global_basis.x), -1.0, 1.0) * 0.25 + randf_range(-0.05, 0.05)
	health_changed.emit(health, stats.max_health)
	if health <= 0.0:
		dead = true
		view.grenade_cancel()
		_g_wanted = false
		_g_key_down = false
		camera.position.y = 0.45        # dropped to the floor
		camera.rotation.z = 0.5
		died.emit()


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(health + amount, stats.max_health)
	health_changed.emit(health, stats.max_health)


func _update_label() -> void:
	if _g_hud:
		_g_hud.queue_redraw()
	_label.text = "%s %d/%d   [R] reload  [T] grenade (tap: toss)  [1] pistol  [2] shotgun  [3] SMG  [4] crossbow  [6] rifle  [7] revolver  [8] trench gun  [9] MP 18  [F] light  [G] god mode%s  [L] Last Defiance always%s  [Q] Carnival Curse  [Backspace] reset  [Esc] mouse" % [WEAPONS[weapon].get("label", WEAPONS[weapon].name), ammo[weapon], mag_of(weapon), " ON" if god_mode else "", " ON" if Zornhauptmann.always_defiance else ""]


# --- grenades -------------------------------------------------------------------
## Add `n` grenades of `kind` (up to what can be carried). Returns how many were taken.
func give_grenades(n: int, kind: String = "frag") -> int:
	var cap := int(Grenade.TYPES[kind].max_carry)
	var before := int(grenades.get(kind, 0))
	grenades[kind] = mini(before + n, cap)
	ammo_changed.emit()
	_update_label()
	return int(grenades[kind]) - before


func grenade_count(kind: String = "") -> int:
	return int(grenades.get(kind if kind != "" else grenade_kind, 0))


## The key goes down: bring one up (as soon as the hands are free).
func _grenade_down() -> void:
	if dead or mount or cinematic:
		return
	if grenade_count() <= 0:
		if Time.get_ticks_msec() - _dry_at > 400:
			_dry_at = Time.get_ticks_msec()
			SfxSynth.play(self, "dry_click", camera.global_position + camera.global_basis * Vector3(0.2, -0.3, -0.3), -16.0, 0.7)   # a hand at an empty pouch
		return
	_g_key_down = true
	_g_hold = 0.0
	_g_wanted = true
	_g_let_go = false
	_try_grenade()


## The key comes up: throw it (a quick tap: an underhand toss).
func _grenade_up() -> void:
	if not _g_key_down:
		return
	_g_key_down = false
	_g_under = _g_hold < GRENADE_TAP
	var st := view.grenade_state()
	if st == "draw" or st == "held":
		view.grenade_throw(_g_under)
	elif _g_wanted:
		_g_let_go = true


func _tick_grenade(delta: float) -> void:
	if _g_key_down:
		_g_hold += delta
	_try_grenade()


func _try_grenade() -> void:
	if not _g_wanted or dead or mount:
		return
	if view.reloading() or view.swapping() or view.grenade_busy() or _pull_left >= 0.0:
		return                                  # the hands are busy: as soon as they are free
	if grenade_count() <= 0:
		_g_wanted = false
		return
	if view.grenade_draw():
		_g_wanted = false
		SfxSynth.play(self, "grenade_cap", camera.global_position + camera.global_basis * Vector3(0.15, -0.2, -0.35), -6.0)
		if _g_let_go:
			_g_let_go = false
			view.grenade_throw(_g_under)


## The moment it leaves the hand: one fewer, and off it goes.
func _on_grenade_released(underhand: bool) -> void:
	var kind := grenade_kind
	if grenade_count(kind) <= 0 or dead:
		return
	grenades[kind] = grenade_count(kind) - 1
	var spec: Dictionary = Grenade.TYPES[kind]
	var b := camera.global_basis
	var eye := camera.global_position
	# from the hand's place, out in front of the body (clear of its capsule)...
	var from := eye + b * (Vector3(0.14, -0.36, -0.42) if underhand else Vector3(0.16, -0.08, -0.45))
	# ...but never through a wall pressed up against: then from just short of it
	var space := get_world_3d().direct_space_state
	var to_hand := from - eye
	var q := PhysicsRayQueryParameters3D.create(eye, from + to_hand.normalized() * 0.07, LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		from = (hit.position as Vector3) - to_hand.normalized() * 0.08
	var lift := float(spec.toss_lift if underhand else spec.throw_lift)
	var aim := (-b.z).rotated(b.x.normalized(), lift).normalized()
	var speed := float(spec.toss_speed if underhand else spec.throw_speed)
	var v := aim * speed + Vector3(velocity.x, 0.0, velocity.z) * 0.6     # some of the run carries into it
	# end over end, a little off the line
	var spin := b.x.normalized() * (-14.0 if not underhand else -6.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2.0
	var world := get_tree().get_first_node_in_group(&"world_root")
	var g := Grenade.throw(world if world else get_parent(), kind, from, v, spin, [self])
	grenades_thrown.append(g)
	ammo_changed.emit()
	_update_label()


## The grenades carried, bottom right: a small stick grenade and the count.
func _draw_grenades(c: Control) -> void:
	var n := grenade_count()
	var u := maxf(1.0, c.size.y / 540.0)
	var at := Vector2(c.size.x - 92.0 * u, c.size.y - 40.0 * u)
	var col := Color(0.86, 0.82, 0.74, 0.85) if n > 0 else Color(0.6, 0.45, 0.42, 0.6)
	var dark := Color(0, 0, 0, 0.7)
	# the grenade, lying at an angle: a wooden handle and a steel can
	var axis := Vector2(1, -0.55).normalized()
	var side := Vector2(-axis.y, axis.x)
	var tail := at + Vector2(0, 8) * u
	var neck := tail + axis * 22.0 * u
	var head := neck + axis * 9.0 * u
	for o: float in [1.5, 0.0]:
		var w := (3.0 + o) * u
		var pc := dark if o > 0.0 else col.darkened(0.25)
		c.draw_line(tail, neck, pc, w)
		var hw := (6.0 + o) * u
		var hcol := dark if o > 0.0 else col
		c.draw_colored_polygon(PackedVector2Array([neck + side * hw, neck - side * hw, head - side * hw, head + side * hw]), hcol)
	var font := ThemeDB.fallback_font
	var fs := int(16 * u)
	var text := "x%d" % n
	var tp := at + Vector2(38.0 * u, 2.0 * u)
	c.draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(3 * u), dark)
	c.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
