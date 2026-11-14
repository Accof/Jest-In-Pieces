class_name FpsPlayer
extends CharacterBody3D
## First-person player. WASD move, Shift sprint, mouse look, left click fire,
## R reload, 1 pistol, 2 shotgun, F flashlight.

const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2
const LAYER_RAMP := 1 << 4

const WEAPONS := [
	{name = "Pistol", damage = 34.0, pellets = 1, spread = 0.0, impulse = 14.0, heavy = false, can_dismember = false, cooldown = 0.22, falloff = 60.0, mag = 17},
	{name = "Shotgun", damage = 16.0, pellets = 9, spread = 4.5, impulse = 16.0, heavy = true, can_dismember = true, cooldown = 0.8, falloff = 9.0, mag = 6},
]

signal reset_requested
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
}

var health := 100.0
var dead := false
var weapon := 0
## Rounds loaded in each gun. Spare ammunition is unlimited for now.
var ammo: Array[int] = [17, 6]
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


func _ready() -> void:
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
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.visible = show_help
	hud.add_child(_label)
	_update_label()
	health = stats.max_health
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


func _unhandled_input(event: InputEvent) -> void:
	if dead:
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
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: select_weapon(0)
			KEY_2: select_weapon(1)
			KEY_F: flashlight.visible = not flashlight.visible
			KEY_R: reload()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode == reset_key:
			reset_requested.emit()
		_update_label()


func _process(delta: float) -> void:
	view.animate(delta, Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0, _look)
	_look = Vector2.ZERO
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, delta * 1.2)
	_kick = move_toward(_kick, 0.0, delta * 0.5)
	camera.rotation.z = _kick * 0.3


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if dead:
		velocity = Vector3(0, velocity.y - 9.8 * delta, 0)
		move_and_slide()
		return
	_tick_reload(delta)
	# Holding the button keeps firing.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		fire()
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	var dir := (global_basis * input.normalized())
	var s: float = (sprint_speed if Input.is_key_pressed(KEY_SHIFT) else speed) * stats.speed
	velocity.x = dir.x * s
	velocity.z = dir.z * s
	velocity.y = velocity.y - 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()


func select_weapon(w: int) -> void:
	if w == weapon or dead:
		return
	_reload_left = -1.0
	_shell_left = -1.0
	weapon = w
	view.swap_to(w)
	_cooldown = maxf(_cooldown, ViewModel.SWAP_TIME)
	ammo_changed.emit()
	_update_label()


## Start reloading the gun in hand, if it has room.
func reload() -> void:
	if dead or view.swapping() or view.reloading() or ammo[weapon] >= WEAPONS[weapon].mag:
		return
	view.start_reload()
	if weapon == 0:
		_reload_left = ViewModel.PISTOL_RELOAD * 0.62      # the moment the magazine seats
	else:
		_shell_left = ViewModel.SHELL_INTRO + ViewModel.SHELL_TIME * 0.85


func _tick_reload(delta: float) -> void:
	if weapon == 0:
		if _reload_left >= 0.0:
			_reload_left -= delta
			if _reload_left < 0.0:
				ammo[0] = WEAPONS[0].mag
				ammo_changed.emit()
				_update_label()
		if view.reloading() and view._reload_t >= ViewModel.PISTOL_RELOAD:
			view.stop_reload()
			view.slide_locked = false
	elif _shell_left >= 0.0:
		# Shells go in one at a time, so the shotgun can be fired part-way through.
		_shell_left -= delta
		if _shell_left < 0.0:
			ammo[1] += 1
			ammo_changed.emit()
			_update_label()
			if ammo[1] >= WEAPONS[1].mag:
				_shell_left = -1.0
				view.stop_reload()
			else:
				_shell_left = ViewModel.SHELL_TIME


func fire() -> void:
	if _cooldown > 0.0 or dead or view.swapping():
		return
	if weapon == 0 and view.reloading():
		return
	if ammo[weapon] <= 0:
		reload()
		return
	if weapon == 1 and view.reloading():
		_shell_left = -1.0                      # break off loading to shoot
		view.stop_reload()
	var w: Dictionary = WEAPONS[weapon]
	_cooldown = w.cooldown / stats.fire_rate
	_shot_id += 1
	ammo[weapon] -= 1
	if weapon == 0 and ammo[0] == 0:
		view.slide_locked = true
	view.fire()
	var from := camera.global_position
	var aim := -camera.global_basis.z
	var pellets: int = w.pellets + (stats.pellets if w.pellets > 1 else 0)
	for i in pellets:
		var d := aim
		if w.spread > 0.0:
			var s: float = deg_to_rad(w.spread) * stats.spread
			d = (aim + camera.global_basis.x * randfn(0.0, s * 0.5) + camera.global_basis.y * randfn(0.0, s * 0.5)).normalized()
		shoot_ray(from, d, w, _shot_id)
	fired.emit(weapon)
	ammo_changed.emit()
	_update_label()


## Fire one ray with a weapon definition. Also used by the automated tests.
func shoot_ray(from: Vector3, dir: Vector3, w: Dictionary, shot_id: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0, LAYER_WORLD | LAYER_RAGDOLL)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return hit
	var c: Object = hit.collider
	if c is PhysicalBone3D and c.has_meta(&"clown"):
		var dist: float = from.distance_to(hit.position)
		var scale := clampf(1.0 - maxf(dist - w.falloff * 0.4, 0.0) / w.falloff, 0.2, 1.0)
		(c.get_meta(&"clown") as Clown).hit({
			collider = c, position = hit.position, direction = dir,
			damage = w.damage * scale * stats.damage, impulse = w.impulse * scale,
			heavy = w.heavy and scale > 0.5,
			can_dismember = (w.can_dismember or stats.pistol_dismember) and scale > 0.6,
			shot_id = shot_id, blood = stats.blood,
		})
	return hit


func take_damage(amount: float, from_dir: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	_hurt.color.a = clampf(0.25 + amount * 0.02, 0.0, 0.7)
	_kick = clampf(from_dir.dot(global_basis.x), -1.0, 1.0) * 0.25 + randf_range(-0.05, 0.05)
	health_changed.emit(health, stats.max_health)
	if health <= 0.0:
		dead = true
		camera.position.y = 0.45        # dropped to the floor
		camera.rotation.z = 0.5
		died.emit()


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(health + amount, stats.max_health)
	health_changed.emit(health, stats.max_health)


func _update_label() -> void:
	_label.text = "%s %d/%d   [R] reload  [1] pistol  [2] shotgun  [F] light  [Backspace] reset  [Esc] mouse" % [WEAPONS[weapon].name, ammo[weapon], WEAPONS[weapon].mag]
