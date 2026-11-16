class_name GrandStaircase
extends EventRoom
## THE GRAND STAIRCASE. What is left of a theatre foyer: one long, steep
## flight of forty steps under a chandelier. You stand at the top. Clowns come
## up from the foyer in little conga lines, slowly. Shoot them and they go all
## the way back down, and a body rolling down the stairs takes out whoever it
## meets on the way. At the top a rack of barrels waits to be let go; the
## chandelier hangs by one chain.

const STEPS := 40
const RISE := 0.2
const RUN := 0.35
const TOP := STEPS * RISE              ## 8m
const BOTTOM_Z := -STEPS * RUN         ## -14m
const HALF_W := 4.4                    ## stairs run x -4.4..4.4
const GROUPS := [3, 4, 3, 5, 4, 4]
const GROUP_GAP := 6.0
const MAX_ALIVE := 12

var knockdowns := 0
var full_flights := 0
var _queue: Array = []                 # [time, x, z]
var _spawned := 0
var _knockers: Array[RigidBody3D] = []
var _hud: Label
var _ticker: Label
var _last_knock_t := -9.0
var _combo := 0
var _ending := -1.0
var _chandelier: RigidBody3D
var _chain: MeshInstance3D
var _barrels: Array[RigidBody3D] = []
var _chock: Array = []                 # the board holding them: [mesh, body]


func build() -> void:
	title = "The Grand Staircase"
	concrete_room(Vector3(-5.6, 0, -27), Vector3(11.2, 15, 34))
	_stairs()
	_landing()
	_foyer()
	_chandelier_build()
	_barrel_rack()
	_lights()
	make_exit(Vector3(0, TOP, 6.88), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0.6, TOP + 0.05, 1.5))
	_build_hud()


# --- the set ------------------------------------------------------------------------------
func _stairs() -> void:
	var stone := PhysicsMaterial.new()
	stone.friction = 0.45                # worn marble: bodies slide and roll on it
	stone.bounce = 0.1
	for k in STEPS:
		var top := (k + 1) * RISE
		var z0 := BOTTOM_Z + k * RUN
		var mi := solid(Vector3(0, top * 0.5, z0 + RUN * 0.5), Vector3(HALF_W * 2.0, top, RUN), "floor_conc")
		# the solid() body is the last child added: give it the marble
		var body := get_child(get_child_count() - 1) as StaticBody3D
		body.physics_material_override = stone
		# a strip of faded red runner up the middle
		var run := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4, 0.02, RUN + 0.01)
		run.mesh = bm
		run.material_override = _runner_mat()
		run.position = Vector3(0, top + 0.01, z0 + RUN * 0.5)
		add_child(run)
		mi.set_meta(&"step", k)
		# a brass nosing on every tread: you can count them all the way down
		var nose := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(HALF_W * 2.0, 0.035, 0.05)
		nose.mesh = nm
		nose.material_override = LevelArt._mat("brass")
		nose.position = Vector3(0, top + 0.005, z0 + 0.025)
		add_child(nose)
	# A smooth ramp over the steps for the player only (bodies get the edges).
	# Its top face runs exactly over the step nosings, from the foyer floor in
	# front of the first step to the top tread, so no edge sticks up
	# through it (it used to sag below the upper steps, which caught your feet).
	var slope := RISE / RUN
	var lo := Vector3(0, 0.0, BOTTOM_Z - RUN)                 # the line y = (z - lo.z) * slope
	var hi := Vector3(0, TOP, -RUN)                            # the top tread, level with the landing
	var up := Vector3(0, 1.0, -slope).normalized()
	var thick := 0.3
	beam(lo - up * (thick * 0.5 - 0.02), hi - up * (thick * 0.5 - 0.02), Vector2(HALF_W * 2.0, thick), "", true, FpsPlayer.LAYER_RAMP)
	# banisters: posts, a rail just under hip height (bodies go over it now and then)
	for sd: float in [-1.0, 1.0]:
		var x := sd * (HALF_W + 0.1)
		beam(Vector3(x, 0.95, BOTTOM_Z - 0.4), Vector3(x, TOP + 0.95, 0.3), Vector2(0.14, 0.12), "wood")
		for k in range(0, STEPS + 1, 4):
			var top := k * RISE
			solid(Vector3(x, top + 0.47, BOTTOM_Z + k * RUN), Vector3(0.08, 0.94, 0.08), "wood", false)
		# under the stairs: the side of the flight, panelled
		beam(Vector3(x + sd * 0.05, 0.0, BOTTOM_Z), Vector3(x + sd * 0.05, TOP, 0.0), Vector2(0.06, 0.5), "harlequin_faded", false)


func _landing() -> void:
	solid(Vector3(0, TOP * 0.5, 3.5), Vector3(11.2, TOP, 7.0), "floor_conc")
	# railings on either side of the top of the flight
	for sd: float in [-1.0, 1.0]:
		solid(Vector3(sd * 5.05, TOP + 0.5, 0.15), Vector3(1.1, 1.0, 0.12), "wood")
	# portraits along the landing wall
	for x: float in [-5.5, 5.5]:
		solid(Vector3(x, TOP + 2.4, 6.9), Vector3(1.4, 1.8, 0.06), "poster", false)


func _foyer() -> void:
	# the foyer floor is plain; two doors the clowns come through, a ticket booth
	for x: float in [-3.2, 3.2]:
		solid(Vector3(x, 1.2, -26.9), Vector3(1.6, 2.4, 0.1), "door", false)
	solid(Vector3(-4.6, 1.1, -21.0), Vector3(1.6, 2.2, 1.6), "planks_dark")
	solid(Vector3(-4.6, 2.3, -21.0), Vector3(1.8, 0.2, 1.8), "harlequin_faded")
	# two fuel drums by the bottom step: for whoever is standing next to them
	for x: float in [-4.6, 4.6]:
		var drum := ExplosiveBarrel.new()
		add_child(drum)
		drum.position = Vector3(x, 0.0, BOTTOM_Z - 1.6)


func _chandelier_build() -> void:
	var anchor := Vector3(0, 14.8, -7.0)
	_chandelier = RigidBody3D.new()
	_chandelier.mass = 140.0
	_chandelier.collision_layer = 1
	_chandelier.collision_mask = 1 | (1 << 2)
	_chandelier.freeze = true
	_chandelier.continuous_cd = true
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.1
	cyl.height = 0.7
	cs.shape = cyl
	_chandelier.add_child(cs)
	var brass := LevelArt._mat("brass")
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.1
	ring.mesh = tm
	ring.material_override = brass
	_chandelier.add_child(ring)
	var hub := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.7
	hub.mesh = sm
	hub.material_override = brass
	_chandelier.add_child(hub)
	for k in 10:
		var a := TAU * k / 10.0
		var arm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.02
		cm.height = 1.0
		arm.mesh = cm
		arm.material_override = brass
		arm.position = Vector3(cos(a) * 0.5, 0.05, sin(a) * 0.5)
		arm.rotation = Vector3(0, -a, PI * 0.5)
		_chandelier.add_child(arm)
		var bulb_m := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.06
		bs.height = 0.14
		bulb_m.mesh = bs
		bulb_m.material_override = LevelArt._mat("bulb_hot")
		bulb_m.position = Vector3(cos(a) * 1.03, 0.14, sin(a) * 1.03)
		_chandelier.add_child(bulb_m)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.5)
	glow.light_energy = 9.0
	glow.omni_range = 16.0
	glow.shadow_enabled = true
	glow.position = Vector3(0, -0.4, 0)
	_chandelier.add_child(glow)
	add_child(_chandelier)
	_chandelier.position = anchor + Vector3.DOWN * 3.6
	# the chain: shoot it
	_chain = MeshInstance3D.new()
	var chm := CylinderMesh.new()
	chm.top_radius = 0.035
	chm.bottom_radius = 0.035
	chm.height = 3.4
	_chain.mesh = chm
	_chain.material_override = LevelArt._mat("iron")
	_chain.position = anchor + Vector3.DOWN * 1.7
	add_child(_chain)
	var trig := ShotTrigger.new()
	var tcs := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(0.3, 3.2, 0.3)
	tcs.shape = tb
	trig.add_child(tcs)
	add_child(trig)
	trig.position = _chain.position
	trig.triggered.connect(_drop_chandelier)
	_knockers.append(_chandelier)


func _barrel_rack() -> void:
	# a rack of five barrels on its side at the head of the stairs, held by a
	# chock with a rope; shoot the rope
	for k in 4:
		var rb := RigidBody3D.new()
		rb.mass = 60.0
		rb.collision_layer = 1
		rb.collision_mask = 1 | (1 << 2)
		rb.freeze = true
		rb.continuous_cd = true
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.32
		cyl.height = 0.85
		cs.shape = cyl
		cs.rotation.z = PI * 0.5
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 0.3
		cm.height = 0.85
		mi.mesh = cm
		mi.rotation.z = PI * 0.5
		mi.material_override = LevelArt._mat("wood")
		rb.add_child(mi)
		for sd: float in [-0.3, 0.3]:
			var hoop := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.325
			hm.bottom_radius = 0.325
			hm.height = 0.05
			hoop.mesh = hm
			hoop.rotation.z = PI * 0.5
			hoop.position.x = sd
			hoop.material_override = LevelArt._mat("iron")
			rb.add_child(hoop)
		add_child(rb)
		rb.position = Vector3(-3.9 + k * 0.9, TOP + 0.33, 0.55 + (k % 2) * 0.1)
		_barrels.append(rb)
		_knockers.append(rb)
	var chock_mesh := solid(Vector3(-2.55, TOP + 0.12, 0.08), Vector3(3.8, 0.24, 0.14), "wood")
	_chock = [chock_mesh, get_child(get_child_count() - 1)]
	# the rope lashed over the top of them, to a post at each end
	var rope := ShotTrigger.new()
	var cs2 := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.9, 0.22, 0.22)
	cs2.shape = bx
	rope.add_child(cs2)
	add_child(rope)
	rope.position = Vector3(-2.55, TOP + 0.72, 0.6)
	var rope_m := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.025
	rm.bottom_radius = 0.025
	rm.height = 3.9
	rope_m.mesh = rm
	rope_m.rotation.z = PI * 0.5
	rope_m.material_override = LevelArt._mat("cloth")
	rope.add_child(rope_m)
	rope.triggered.connect(func() -> void: rope_m.visible = false)
	for sd: float in [-1.0, 1.0]:
		solid(Vector3(-2.55 + sd * 2.0, TOP + 0.4, 0.6), Vector3(0.1, 0.8, 0.1), "wood")
	rope.triggered.connect(_release_barrels)
	solid(Vector3(-4.55, TOP + 1.0, 0.66), Vector3(0.5, 0.26, 0.04), "harlequin_faded", false)


func _lights() -> void:
	# sconces down both walls of the flight, a lamp over every few steps
	for k in range(2, STEPS, 6):
		var z := BOTTOM_Z + k * RUN
		var y := k * RISE + 2.6
		for x: float in [-5.3, 5.3]:
			bulb(Vector3(x, y, z), 3.2, 8.0, Color(1.0, 0.74, 0.46), false)
	# the foyer, where they come in
	bulb(Vector3(0, 3.6, -22.0), 6.0, 14.0, Color(1.0, 0.78, 0.52), true)
	bulb(Vector3(0, 3.0, -16.0), 3.5, 9.0, Color(1.0, 0.7, 0.45), false)
	bulb(Vector3(0, TOP + 3.0, 4.5), 1.6, 7.0)
	# thin the level's haze in here: you need to see to the bottom of the flight
	var clear := FogVolume.new()
	clear.size = Vector3(12, 16, 35)
	clear.position = Vector3(0, 7.5, -10.0)
	var fm := FogMaterial.new()
	fm.density = -0.028
	clear.material = fm
	add_child(clear)


static var _runner: Material
static func _runner_mat() -> Material:
	if _runner == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.05, 0.05)
		m.roughness = 0.95
		_runner = m
	return _runner


# --- running it ---------------------------------------------------------------------------
func begin() -> void:
	_t = 0.0
	var t := 1.5
	for n: int in GROUPS:
		var x := randf_range(-2.6, 2.6)
		for i in n:
			_queue.append([t + i * 0.7, x + randf_range(-0.2, 0.2), -25.5])
		t += GROUP_GAP
	var g := get_tree().get_first_node_in_group(&"game")
	if g and g.has_method("event_banner"):
		g.event_banner("THE GRAND STAIRCASE\nKnock them back down.\nShoot the rope on the barrel rack.  Shoot the chandelier chain.")


func _process(delta: float) -> void:
	_t += delta
	_update_hud()
	if _chain and _chandelier and not _chandelier.freeze:
		_chain.visible = false
	if done:
		return
	var alive := enemies.filter(func(e: Clown) -> bool: return is_instance_valid(e) and not e.dead).size()
	while not _queue.is_empty() and _queue[0][0] <= _t and alive < MAX_ALIVE:
		var q: Array = _queue.pop_front()
		_spawn_clown(float(q[1]), float(q[2]))
		alive += 1
	if _queue.is_empty() and alive == 0:
		if _ending < 0.0:
			_ending = _t
		elif _t - _ending > 3.5:
			_finish()


func _physics_process(_delta: float) -> void:
	if done:
		return
	_knock_downs()


func _spawn_clown(x: float, z: float) -> void:
	var c := spawn(Vector3(x, 0, z), "clown", "room")
	_spawned += 1
	c.rotation.y = 0.0
	var b: RoomBrain = c.get_node("Brain")
	b.hunting = true
	b.move_speed = 0.9
	b.run_speed = randf_range(0.85, 1.25)       # a slow trudge up forty steps
	b.melee_damage = 5.0
	var lo := to_global(Vector3(-HALF_W + 0.4, 0, -30))
	var hi := to_global(Vector3(HALF_W - 0.4, 0, 8))
	b.bounds = AABB(lo, hi - lo)
	b.floor_at = _floor_at
	c.died.connect(_fell)
	c.set_meta(&"start_y", 0.0)


## The height of the floor under a point (global), for clowns walking the stairs.
func _floor_at(p: Vector3) -> float:
	var l := to_local(p)
	var h := clampf((l.z - BOTTOM_Z) / -BOTTOM_Z * TOP, 0.0, TOP)
	return global_position.y + h


## Shot on the stairs: no last stand, it goes straight over backwards and down.
func _fell(c: Clown) -> void:
	if not is_instance_valid(c) or not c.ragdoll:
		return
	var l := to_local(c.global_position)
	c.set_meta(&"died_y", l.y)
	if l.z > BOTTOM_Z and l.z < 0.5:
		var down := global_basis * Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 1.6), -randf_range(2.2, 3.6))
		c.ragdoll.tumble.call_deferred(down, randf_range(3.0, 7.0))
	_watch_flight.call_deferred(c)


## Did it go all the way from high up to the foyer floor?
func _watch_flight(c: Clown) -> void:
	var start_y: float = c.get_meta(&"died_y", 0.0)
	if start_y < TOP * 0.5:
		return
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(c) or not c.ragdoll or not c.ragdoll.bones.has(&"Hips"):
		return
	var l := to_local((c.ragdoll.bones[&"Hips"] as PhysicalBone3D).global_position)
	if l.z < BOTTOM_Z + 0.5:
		full_flights += 1
		_say("ALL THE WAY DOWN")


## Bodies, barrels and the chandelier going down the stairs bowl over any
## clown in the way.
func _knock_downs() -> void:
	var movers: Array = []                   # [position, velocity]
	for e: Clown in enemies:
		if is_instance_valid(e) and e.dead and e.ragdoll and e.ragdoll.active and not e.ragdoll.is_settled:
			for n: StringName in [&"Hips", &"Chest", &"Neck"]:
				var pb: PhysicalBone3D = e.ragdoll.bones.get(n)
				if pb and pb.linear_velocity.length() > 2.2:
					movers.append([pb.global_position, pb.linear_velocity])
	for rb: RigidBody3D in _knockers:
		if is_instance_valid(rb) and not rb.freeze and rb.linear_velocity.length() > 1.8:
			movers.append([rb.global_position, rb.linear_velocity, rb == _chandelier])
	if movers.is_empty():
		return
	for e: Clown in enemies:
		if not is_instance_valid(e) or e.dead or not e.ragdoll:
			continue
		var body := e.global_position + Vector3.UP * 0.9
		for m: Array in movers:
			var reach := 1.4 if m.size() > 2 and m[2] else 0.85
			var d: Vector3 = (m[0] as Vector3) - body
			if absf(d.y) < 1.2 and Vector2(d.x, d.z).length() < reach:
				_knock(e, m[1])
				break


func _knock(c: Clown, vel: Vector3) -> void:
	var hips: PhysicalBone3D = c.ragdoll.bones.get(&"Hips")
	if hips == null:
		return
	knockdowns += 1
	_combo = _combo + 1 if _t - _last_knock_t < 1.5 else 1
	_last_knock_t = _t
	_say("STRIKE!" if _combo >= 3 else ("DOUBLE!" if _combo == 2 else "KNOCKED FLAT"))
	var dir := vel.normalized()
	c.hit({collider = hips, position = hips.global_position, direction = dir, damage = 600.0, impulse = 2.0, blood = 0.6,
		profile = ClownRagdoll.profile_blast(), fling = vel * 0.6 + Vector3.UP * 1.5, shot_id = -50 - knockdowns})


func _release_barrels() -> void:
	_say("LOOK OUT BELOW")
	# the chock board kicks out from under them
	for n: Node in _chock:
		if is_instance_valid(n):
			n.queue_free()
	for k in _barrels.size():
		var rb := _barrels[k]
		rb.freeze = false
		rb.apply_central_impulse(global_basis * Vector3(randf_range(0.2, 1.0), 0.2, -2.2) * rb.mass)
		rb.apply_torque_impulse(global_basis * Vector3(-8.0, 0, 0) * rb.mass * 0.1)


func _drop_chandelier() -> void:
	_say("TIMBER")
	_chandelier.freeze = false
	_chandelier.apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 60.0)


func _finish() -> void:
	var tickets := 5 + mini(knockdowns, 10) + full_flights
	var r := {success = true, upgrade = knockdowns >= 4, tickets = tickets, heal = 25.0}
	r.knockdowns = knockdowns
	r.line = "THE GRAND STAIRCASE\n%d knocked flat by a falling friend   %d went all the way down" % [knockdowns, full_flights]
	complete(r)


func enemy_died(_c: Clown) -> void:
	pass


# --- HUD ----------------------------------------------------------------------------------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 24)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.position.y = 40
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hud)
	_ticker = Label.new()
	_ticker.add_theme_font_size_override("font_size", 34)
	_ticker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_ticker.add_theme_color_override("font_outline_color", Color.BLACK)
	_ticker.add_theme_constant_override("outline_size", 10)
	_ticker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ticker.position.y += 90
	_ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticker.modulate.a = 0.0
	layer.add_child(_ticker)


func _say(t: String) -> void:
	if _ticker == null:
		return
	_ticker.text = t
	_ticker.modulate.a = 1.0
	_ticker.scale = Vector2.ONE * 1.25
	var tw := _ticker.create_tween()
	tw.tween_property(_ticker, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(0.8)
	tw.tween_property(_ticker, "modulate:a", 0.0, 0.4)


func _update_hud() -> void:
	if _hud == null:
		return
	var left := _queue.size() + enemies.filter(func(e: Clown) -> bool: return is_instance_valid(e) and not e.dead).size()
	_hud.text = "" if done else "CLOWNS %d     KNOCKED FLAT %d" % [left, knockdowns]
