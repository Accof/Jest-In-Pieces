class_name MgNest
extends EventRoom
## The machine-gun nest. A sandbagged parapet over no man's land at dusk: mud,
## craters, wire, burning wrecks, flares, and fog. Man the gun; for ninety
## seconds clowns and WitzSoldats come out of the fog at you. Kill as many as
## you can. Survive it and the gun is yours.

const FIELD_Y := 1.2               ## no man's land, level with the top of the trench
const WAVE_TIME := 90.0
const MAX_ALIVE := 18
## [start second, what, how many, over how many seconds]
const WAVES := [
	[3.0, "shamble", 9, 18.0],
	[28.0, "run", 8, 14.0],
	[34.0, "soldier", 4, 12.0],
	[58.0, "run", 12, 16.0],
	[60.0, "soldier", 4, 10.0],
	[66.0, "shamble", 6, 10.0],
]
const TIERS := [[36, "GOLD"], [26, "SILVER"], [16, "BRONZE"]]

var gun: MountedGun
var _queue: Array = []             # [time, kind]
var _running := false
var _over := false
var _breached := 0
var _spawned := 0
var _flare_t := 1.5
var _flares: Array = []
var _fires: Array = []
var _hud: Label
var _heat_bar: ProgressBar
var _craters: Array[Vector3] = []
var _in_trench := 0


func build() -> void:
	title = "Machine-gun nest"
	# the trench: floor, back wall with the door, side walls, and the parapet
	solid(Vector3(0, -0.2, 0.9), Vector3(9.0, 0.4, 4.2), "mud")
	solid(Vector3(0, 1.0, 3.1), Vector3(9.0, 2.6, 0.4), "planks")
	solid(Vector3(-4.6, 1.0, 0.9), Vector3(0.4, 2.6, 4.6), "sandbags")
	solid(Vector3(4.6, 1.0, 0.9), Vector3(0.4, 2.6, 4.6), "sandbags")
	solid(Vector3(0, 0.5, -1.25), Vector3(9.0, 1.0, 0.5), "planks")          # firing step face
	# sandbag parapet, gap in the middle for the gun
	for side: float in [-1.0, 1.0]:
		solid(Vector3(side * 2.65, 1.28, -1.25), Vector3(3.9, 0.55, 0.7), "sandbags")
	solid(Vector3(0, 1.08, -1.25), Vector3(1.4, 0.16, 0.7), "sandbags")
	for i in 22:
		var bag := MeshInstance3D.new()
		bag.mesh = _bag_mesh()
		bag.position = Vector3(randf_range(-4.3, 4.3), 1.6 + randf_range(0.0, 0.06), -1.25 + randf_range(-0.25, 0.25))
		if absf(bag.position.x) < 0.8:
			continue
		bag.rotation = Vector3(0, randf_range(-0.3, 0.3), PI * 0.5)
		add_child(bag)
	# the gun on the parapet
	gun = MountedGun.new()
	add_child(gun)
	gun.position = Vector3(0, 0.98, -1.2)
	gun.floor_y = to_global(Vector3.ZERO).y
	gun.ripped_off.connect(func() -> void: _flash_text("It's yours. 250 rounds on the belt."))
	make_exit(Vector3(0, 0, 2.88), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 2.0))
	# no man's land
	_field()
	# lighting: a cold dusk overhead, a lantern in the trench
	bulb(Vector3(-3.5, 2.0, 2.2), 1.6, 6.0, Color(1.0, 0.7, 0.4), false)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 0.72)
	moon.light_energy = 0.8
	moon.rotation = Vector3(deg_to_rad(-25), deg_to_rad(20), 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 80.0
	add_child(moon)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.6, 0.62, 0.7)
	fill.light_energy = 1.2
	fill.omni_range = 30.0
	fill.position = Vector3(0, 6.0, -14.0)
	add_child(fill)
	_build_hud()


func _field() -> void:
	var span := Vector2(80.0, 90.0)
	solid(Vector3(0, FIELD_Y - 0.5, -1.6 - span.y * 0.5), Vector3(span.x, 1.0, span.y), "ground")
	# craters: rings of churned earth (cover for soldiers, they stop bullets)
	for i in 26:
		var p := Vector3(randf_range(-22.0, 22.0), FIELD_Y, randf_range(-58.0, -9.0))
		var r := randf_range(1.2, 2.4)
		var lip := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.7
		tm.outer_radius = r
		tm.rings = 18
		tm.ring_segments = 8
		lip.mesh = tm
		lip.material_override = LevelArt._mat("mud")
		lip.position = p + Vector3.UP * 0.02
		lip.scale = Vector3(1, 0.55, 1)
		add_child(lip)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r * 0.85
		cyl.height = 0.5
		cs.shape = cyl
		body.add_child(cs)
		body.position = p + Vector3.UP * 0.12
		add_child(body)
		_craters.append(p + Vector3(0, 0, r * 0.95))          # the near lip: where a soldier hides
	# wire entanglements and posts
	for i in 9:
		var a := Vector3(randf_range(-24.0, 18.0), FIELD_Y, randf_range(-50.0, -6.0))
		var dir := Vector3(1, 0, randf_range(-0.3, 0.3)).normalized()
		var length := randf_range(4.0, 9.0)
		for k in int(length / 1.6) + 1:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 1.1, 0.07)
			post.mesh = bm
			post.material_override = LevelArt._mat("wood")
			post.position = a + dir * k * 1.6 + Vector3.UP * 0.5
			post.rotation.z = randf_range(-0.25, 0.25)
			add_child(post)
		var coil := MeshInstance3D.new()
		coil.mesh = LevelArt._coil_mesh()
		coil.position = a + dir * length * 0.5 + Vector3.UP * 0.35
		coil.basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).scaled(Vector3(length / 3.0, 1, 1))
		add_child(coil)
	# burning wrecks: a broken limber, a crashed lorry, a dead horse cart
	for p: Vector3 in [Vector3(-12, FIELD_Y, -24), Vector3(15, FIELD_Y, -38), Vector3(-4, FIELD_Y, -47)]:
		solid(p + Vector3(0, 0.5, 0), Vector3(randf_range(2.0, 3.2), 1.0, randf_range(1.4, 2.0)), "metal")
		solid(p + Vector3(0.6, 1.1, 0.2), Vector3(1.0, 0.4, 0.8), "planks_dark", false)
		var fire := OmniLight3D.new()
		fire.light_color = Color(1.0, 0.5, 0.18)
		fire.light_energy = 3.0
		fire.omni_range = 9.0
		fire.shadow_enabled = true
		fire.light_volumetric_fog_energy = 3.0
		fire.position = p + Vector3.UP * 1.6
		add_child(fire)
		_fires.append(fire)
	# fog rolling over the far half of the field: they come out of it
	var fog := FogVolume.new()
	fog.size = Vector3(90, 5, 50)
	fog.position = Vector3(0, FIELD_Y + 1.5, -55)
	var fm := FogMaterial.new()
	fm.density = 0.12
	fm.albedo = Color(0.55, 0.53, 0.5)
	fm.edge_fade = 0.4
	fog.material = fm
	add_child(fog)


func begin() -> void:
	gun.active = true
	gun.player = player
	_queue.clear()
	for w: Array in WAVES:
		for i in int(w[2]):
			_queue.append([float(w[0]) + float(w[3]) * float(i) / float(w[2]) + randf_range(-0.4, 0.4), w[1]])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_running = true
	_t = 0.0
	_flash_text("MAN THE GUN\n[E] at the gun")


func _process(delta: float) -> void:
	# fires flicker, flares drift down
	for f: OmniLight3D in _fires:
		f.light_energy = 2.6 + sin(Time.get_ticks_msec() * 0.013 + f.position.x) * 0.5 + randf_range(-0.3, 0.3)
	_flare_t -= delta
	if _flare_t <= 0.0:
		_flare_t = randf_range(4.5, 8.0)
		_launch_flare()
	for fl: Array in _flares:
		if not is_instance_valid(fl[0]):
			continue
		var l: OmniLight3D = fl[0]
		fl[1] += delta
		l.position += Vector3(0.3, -0.6, 0) * delta
		l.light_energy = 9.0 * clampf(1.0 - fl[1] / 9.0, 0.0, 1.0)
		if fl[1] > 9.0:
			l.queue_free()
	_flares = _flares.filter(func(fl: Array) -> bool: return is_instance_valid(fl[0]))
	_update_hud()
	if not _running:
		return
	_t += delta
	var alive := enemies.filter(func(e: Clown) -> bool: return is_instance_valid(e) and not e.dead and not e.downed).size()
	while not _queue.is_empty() and _queue[0][0] <= _t and alive < MAX_ALIVE:
		_spawn_runner(_queue.pop_front()[1])
		alive += 1
	# who has got into the trench? Then the gunner may let go and fight them off
	var in_trench := enemies.filter(func(e: Clown) -> bool:
		return is_instance_valid(e) and not e.dead and e.global_position.y < global_position.y + FIELD_Y - 0.5)
	_in_trench = in_trench.size()
	gun.leave_ok = _in_trench > 0 or _t > WAVE_TIME
	if _t > WAVE_TIME and not _over:
		_queue.clear()                  # time's up: nobody else comes
		var left := enemies.filter(func(e: Clown) -> bool: return is_instance_valid(e) and not e.dead and not e.crawling and not e.downed)
		if left.is_empty() or _t > WAVE_TIME + 12.0:
			_finish()


func _spawn_runner(kind: String) -> void:
	var x := randf_range(-22.0, 22.0)
	var start := Vector3(x, FIELD_Y, randf_range(-66.0, -60.0))
	var c := spawn(start, "witzsoldat" if kind == "soldier" else "clown", "charge" if kind != "soldier" else "rifle")
	_spawned += 1
	c.rotation.y = 0.0
	var b: RoomBrain = c.get_node("Brain")
	b.floor_y = global_position.y + FIELD_Y
	b.target = global_position + Vector3(clampf(x * 0.15, -3.5, 3.5), FIELD_Y, -1.9)
	b.on_arrive = _breach
	match kind:
		"shamble":
			b.run_speed = randf_range(1.6, 2.4)
		"run":
			b.run_speed = randf_range(4.0, 5.0)
		"soldier":
			b.run_speed = randf_range(3.2, 3.8)
			b.gun_damage = 9.0
			b.accuracy = 0.32
			b.shot_gap = Vector2(2.4, 3.6)
			b.target = global_position + Vector3(x * 0.2, FIELD_Y, -2.0)
			# work forward crater by crater
			var near := _craters.filter(func(p: Vector3) -> bool: return absf(p.x - x) < 9.0)
			near.sort_custom(func(a: Vector3, b2: Vector3) -> bool: return a.z < b2.z)
			for p: Vector3 in near:
				if p.z > start.z + 6.0 and b.waypoints.size() < 3:
					b.waypoints.append(global_position + p)
	b.melee_damage = 12.0


## One made it to the trench: it drops in and goes for the gunner.
func _breach(c: Clown) -> void:
	_breached += 1
	var b: RoomBrain = c.get_node("Brain")
	b.floor_y = global_position.y
	b.mode = "room"
	b.hunting = true
	b.run_speed = 3.6
	var sd := -1.0 if c.position.x < 0.0 else 1.0
	c.global_position = global_position + Vector3(sd * 3.7, 0.4, randf_range(0.2, 1.6))
	c.look_at(global_position + Vector3(0, 0.4, -0.5), Vector3.UP, true)
	_flash_text("THEY'RE IN THE TRENCH\n[E] let go of the gun")


func _launch_flare() -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.92, 0.8)
	l.light_energy = 9.0
	l.omni_range = 55.0
	l.omni_attenuation = 0.8
	l.shadow_enabled = true
	l.position = Vector3(randf_range(-15.0, 15.0), 22.0, randf_range(-45.0, -20.0))
	add_child(l)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.95, 0.85)
	m.emission_enabled = true
	m.emission = Color(1, 0.9, 0.7)
	m.emission_energy_multiplier = 12.0
	ball.material_override = m
	l.add_child(ball)
	_flares.append([l, 0.0])


func _finish() -> void:
	_over = true
	_running = false
	gun.active = false
	if player.mount == gun:
		player.dismount()
	gun.can_rip = true
	var tier := ""
	for t: Array in TIERS:
		if kills >= int(t[0]):
			tier = t[1]
			break
	var r := {success = true, upgrade = false, tickets = 0, heal = 0.0}
	match tier:
		"GOLD":
			r.tickets = 15
			r.heal = 999.0
			r.upgrade = true
		"SILVER":
			r.tickets = 10
			r.heal = 60.0
			r.upgrade = true
		"BRONZE":
			r.tickets = 5
			r.heal = 30.0
	if _breached == 0:
		r.tickets += 5
	r.tier = tier
	r.line = "MACHINE-GUN NEST  %s\n%d killed%s" % [tier if tier != "" else "- no prize", kills, ("   nobody reached the trench" if _breached == 0 else "")]
	r.extra = "[E] at the gun: rip it off the mount"
	complete(r)


## Nothing else ends this room: deaths just count.
func enemy_died(_c: Clown) -> void:
	pass


# --- on-screen: timer, kills, gun heat --------------------------------------------------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.position.y = 40
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hud)
	_heat_bar = ProgressBar.new()
	_heat_bar.show_percentage = false
	_heat_bar.custom_minimum_size = Vector2(220, 14)
	_heat_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_heat_bar.position.y -= 80
	_heat_bar.max_value = 1.0
	layer.add_child(_heat_bar)


func _update_hud() -> void:
	if _hud == null:
		return
	var left := maxf(WAVE_TIME - _t, 0.0)
	_hud.text = ("%d   |   KILLS %d" % [ceil(left), kills]) if _running else ("KILLS %d" % kills if _over else "")
	if _running and _in_trench > 0:
		_hud.text += "\n%d IN THE TRENCH  -  [E] let go" % _in_trench
	elif _running and _t > WAVE_TIME:
		_hud.text = "TIME  |  KILLS %d\nfinishing off the field..." % kills
	_heat_bar.visible = player != null and player.mount == gun
	_heat_bar.value = gun.heat
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.25, 0.1) if gun.overheated else Color(0.95, 0.75, 0.3).lerp(Color(1, 0.2, 0.1), gun.heat)
	_heat_bar.add_theme_stylebox_override("fill", sb)


func _flash_text(t: String) -> void:
	var g := get_tree().get_first_node_in_group(&"game")
	if g and g.has_method("event_banner"):
		g.event_banner(t)


static var _bag: Mesh
static func _bag_mesh() -> Mesh:
	if _bag == null:
		var c := CapsuleMesh.new()
		c.radius = 0.15
		c.height = 0.6
		c.material = LevelArt._mat("sandbag")
		_bag = c
	return _bag
