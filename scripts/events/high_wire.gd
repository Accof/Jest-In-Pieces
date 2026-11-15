class_name HighWire
extends EventRoom
## THE HIGH WIRE. A tall circus shaft. You are on a balcony near the top with
## a scoped rifle on the rail; across the shaft clowns walk two tightropes,
## arms out, wobbling. Pick them off. Under the wires the shaft is full of old
## rigging (beams, struts, a trapeze, hanging sandbags) and the bodies hit all
## of it on the way down. Headshots score most; every beam a body bounces off
## on the way down is a bonus; anyone who makes it across is a point lost.

const BAL := 19.0                  ## the balcony floor
const WIRES := [Vector2(17.5, -4.5), Vector2(14.0, -9.5)]   ## (height, z)
const HALF := 8.0                  ## the wires run x -8..8
const WALKERS := 10
const MAX_ON_WIRE := 3
const GAP := 3.2                   ## seconds between new walkers
const HEADSHOT := 3
const BODY := 1
const BONK := 1
const MAX_BONKS := 3
const TIERS := [[30, "GOLD"], [20, "SILVER"], [10, "BRONZE"]]

var rifle: SniperRifle
var score := 0
var headshots := 0
var bonks := 0
var escaped := 0
var _spawned := 0
var _next := 1.5
var _walkers: Array = []           # {clown, speed, wire, wobble, t}
var _spots: Array = []             # followspots
var _spot_on: Array = []           # what each spot is lit on (Clown or null) and until when
var _pendulums: Array = []         # [body, anchor, rope mesh]
var _hud: Label
var _ticker: Label
var _ending := -1.0


func build() -> void:
	title = "The High Wire"
	concrete_room(Vector3(-11, 0, -16), Vector3(22, 26, 26))
	_ring()
	_balcony()
	_wires()
	_rigging()
	_lights()
	make_exit(Vector3(0, BAL, 9.9), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, BAL + 0.05, 7.6))
	_build_hud()


# --- the set ------------------------------------------------------------------------------
func _ring() -> void:
	# sawdust ring painted on the floor, with a low wooden curb a body can go over
	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(14, 14)
	qm.orientation = PlaneMesh.FACE_Y
	ring.mesh = qm
	ring.material_override = LevelArt._mat("sunburst_faded")
	ring.position = Vector3(0, 0.01, -7.0)
	add_child(ring)
	for k in 20:
		var a0 := TAU * k / 20.0
		var a1 := TAU * (k + 1) / 20.0
		beam(Vector3(cos(a0) * 7.0, 0.18, -7.0 + sin(a0) * 7.0), Vector3(cos(a1) * 7.0, 0.18, -7.0 + sin(a1) * 7.0), Vector2(0.3, 0.36), "wood")
	# crates and a drum stacked by the ring
	solid(Vector3(6.2, 0.5, -12.5), Vector3(1.0, 1.0, 1.0), "crate")
	solid(Vector3(7.3, 0.5, -12.2), Vector3(1.0, 1.0, 1.0), "crate")
	solid(Vector3(6.7, 1.5, -12.4), Vector3(1.0, 1.0, 1.0), "crate")
	solid(Vector3(-7.5, 0.6, -13.0), Vector3(1.4, 1.2, 1.4), "drum")


func _balcony() -> void:
	# the gallery along the back wall
	solid(Vector3(0, BAL - 0.2, 7.0), Vector3(22, 0.4, 6.0), "planks_dark")
	for sd: float in [-1.0, 1.0]:
		solid(Vector3(sd * 6.5, BAL + 0.5, 4.05), Vector3(9.0, 1.0, 0.1), "wood")
	# a pulpit of iron grating out over the drop: you can see straight down
	# through it. One invisible slab to stand on, the bars drawn over it.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(4.0, 0.1, 3.0)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, BAL - 0.05, 2.5)
	add_child(floor_body)
	for k in 30:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 0.05, 0.022)
		bar.mesh = bm
		bar.material_override = LevelArt._mat("iron")
		bar.position = Vector3(0, BAL - 0.03, 1.05 + k * 0.1)
		add_child(bar)
	for x: float in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		solid(Vector3(x, BAL - 0.07, 2.5), Vector3(0.04, 0.09, 3.0), "iron", false)
	# thin iron rails round it (no wall to look over)
	for side: Array in [[Vector3(0, 0, 1.0), Vector3(4.1, 0.05, 0.05)], [Vector3(-2.05, 0, 2.5), Vector3(0.05, 0.05, 3.0)], [Vector3(2.05, 0, 2.5), Vector3(0.05, 0.05, 3.0)]]:
		var at: Vector3 = side[0]
		solid(at + Vector3(0, BAL + 1.0, 0), side[1], "iron")
		if at.z > 1.5:                           # no middle rail across the front: it would cut the view
			solid(at + Vector3(0, BAL + 0.55, 0), side[1], "iron", false)
	for at: Vector3 in [Vector3(-2.05, 0, 1.0), Vector3(2.05, 0, 1.0), Vector3(-2.05, 0, 4.0), Vector3(2.05, 0, 4.0), Vector3(0, 0, 1.0)]:
		solid(at + Vector3(0, BAL + 0.5, 0), Vector3(0.05, 1.0, 0.05), "iron", false)
	# brackets under the pulpit
	for x: float in [-1.9, 1.9]:
		beam(Vector3(x, BAL - 2.2, 4.0), Vector3(x, BAL - 0.1, 1.1), Vector2(0.1, 0.1), "iron", false)
	# the rifle on the front rail
	rifle = SniperRifle.new()
	add_child(rifle)
	rifle.position = Vector3(0, BAL + 1.1, 1.15)
	rifle.floor_y = to_global(Vector3(0, BAL, 0)).y
	rifle.fired.connect(_on_rifle)
	bulb(Vector3(-2.0, BAL + 2.4, 9.6), 1.6, 6.0)


func _wires() -> void:
	for w: Vector2 in WIRES:
		var wire := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = HALF * 2.0 + 2.4
		wire.mesh = cm
		wire.material_override = LevelArt._mat("wire")
		wire.position = Vector3(0, w.x, w.y)
		wire.rotation.z = PI * 0.5
		add_child(wire)
		for sd: float in [-1.0, 1.0]:
			var px := sd * (HALF + 0.9)
			solid(Vector3(px, w.x - 0.1, w.y), Vector3(1.6, 0.2, 1.6), "planks_dark")
			solid(Vector3(px, w.x + 1.0, w.y - 0.78), Vector3(1.6, 1.8, 0.06), "harlequin_faded", false)
			# the platform's mast, down to the floor
			beam(Vector3(px + sd * 0.6, 0.0, w.y + 0.6), Vector3(px + sd * 0.6, w.x, w.y + 0.6), Vector2(0.16, 0.16), "iron")
			beam(Vector3(px + sd * 0.6, 0.0, w.y - 0.6), Vector3(px + sd * 0.6, w.x, w.y - 0.6), Vector2(0.16, 0.16), "iron")


## Old rigging under the wires: the things a body hits on the way down.
func _rigging() -> void:
	var t := Vector2(0.3, 0.3)
	# under the near wire (z -3)
	beam(Vector3(-7.2, 12.5, -4.5), Vector3(-1.6, 12.5, -4.5), t, "wood")
	beam(Vector3(0.8, 9.2, -4.6), Vector3(6.8, 9.2, -4.4), t, "wood")
	beam(Vector3(-3.4, 5.6, -4.5), Vector3(2.2, 5.6, -4.5), t, "wood")
	beam(Vector3(-7.0, 1.0, -4.5), Vector3(-2.0, 8.2, -4.5), t, "wood")          # a strut
	beam(Vector3(7.0, 3.0, -4.1), Vector3(4.5, 7.0, -4.7), t, "wood")
	# under the far wire (z -8)
	beam(Vector3(0.2, 10.2, -9.5), Vector3(6.6, 10.2, -9.5), t, "wood")
	beam(Vector3(-6.8, 7.0, -9.5), Vector3(-0.6, 7.0, -9.5), t, "wood")
	beam(Vector3(-2.2, 3.4, -9.6), Vector3(4.2, 3.4, -9.4), t, "wood")
	beam(Vector3(3.0, 0.0, -9.5), Vector3(7.5, 6.5, -9.5), t, "wood")
	# cross pieces between the rows
	beam(Vector3(2.4, 11.0, -11.0), Vector3(2.4, 11.0, -3.0), t, "wood")
	beam(Vector3(-4.6, 8.0, -11.0), Vector3(-4.6, 8.0, -3.0), t, "wood")
	beam(Vector3(0.0, 4.6, -11.0), Vector3(0.0, 4.6, -3.0), t, "wood")
	# a trapeze still hanging from the near beam, and sandbags on ropes
	_pendulum(Vector3(-4.4, 12.3, -4.5), 2.8, "trapeze")
	_pendulum(Vector3(2.4, 10.8, -7.1), 2.2, "bag")
	_pendulum(Vector3(-4.6, 7.8, -7.5), 1.8, "bag")
	_pendulum(Vector3(4.0, 9.0, -4.5), 1.6, "bag")


func _lights() -> void:
	# lamps down the walls at three heights, so you can see to the floor
	for y: float in [3.0, 9.0, 15.0]:
		for x: float in [-10.6, 10.6]:
			for z: float in [-13.0, -5.0]:
				bulb(Vector3(x, y, z), 2.2, 9.0, Color(1.0, 0.72, 0.45), false)
	bulb(Vector3(0, 1.8, -7.0), 2.5, 10.0, Color(1.0, 0.8, 0.55), true)
	# a chandelier of carnival bulbs over the wires
	for k in 16:
		var a := TAU * k / 16.0
		var col := Color(1.0, 0.75, 0.45) if k % 2 == 0 else Color(1.0, 0.45, 0.3)
		bulb(Vector3(cos(a) * 3.0, 21.5, -7.0 + sin(a) * 3.0), 1.2 if k % 4 == 0 else 0.0, 9.0, col, false)
	bulb(Vector3(0, 22.5, -7.0), 4.0, 14.0, Color(1.0, 0.85, 0.65), true)
	# three followspots from the balcony front: each picks out a walker
	for k in MAX_ON_WIRE:
		var fs := SpotLight3D.new()
		fs.light_color = Color(1.0, 0.95, 0.85)
		fs.light_energy = 0.0
		fs.spot_range = 34.0
		fs.spot_angle = 4.5
		fs.spot_attenuation = 0.3
		fs.shadow_enabled = true
		fs.light_volumetric_fog_energy = 1.5
		add_child(fs)
		fs.position = Vector3((k - 1) * 7.0, BAL - 0.8, 4.2)
		_spots.append(fs)
		_spot_on.append([null, 0.0])


func _pendulum(anchor: Vector3, length: float, kind: String) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1 | (1 << 2)          # world and ragdolls
	rb.mass = 9.0 if kind == "trapeze" else 25.0
	rb.angular_damp = 0.6
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if kind == "trapeze":
		var bar := CylinderShape3D.new()
		bar.radius = 0.04
		bar.height = 1.2
		cs.shape = bar
		cs.rotation.z = PI * 0.5
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 1.2
		mi.mesh = cm
		mi.rotation.z = PI * 0.5
		mi.material_override = LevelArt._mat("wood")
	else:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.28
		cap.height = 0.9
		cs.shape = cap
		var cap_m := CapsuleMesh.new()
		cap_m.radius = 0.28
		cap_m.height = 0.9
		mi.mesh = cap_m
		mi.material_override = LevelArt._mat("sandbag")
	rb.add_child(cs)
	rb.add_child(mi)
	add_child(rb)
	rb.position = anchor + Vector3.DOWN * length
	var pin := PinJoint3D.new()
	add_child(pin)
	pin.position = anchor
	pin.node_a = pin.get_path_to(rb)
	# a second pin for the trapeze so it hangs from both ends, like one
	var rope := MeshInstance3D.new()
	rope.mesh = ImmediateMesh.new()
	rope.material_override = LevelArt._mat("wire")
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)
	_pendulums.append([rb, anchor, rope, kind])
	rb.apply_central_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * rb.mass * 0.6)


# --- running it ---------------------------------------------------------------------------
func begin() -> void:
	_t = 0.0
	var g := get_tree().get_first_node_in_group(&"game")
	if g and g.has_method("event_banner"):
		g.event_banner("THE HIGH WIRE\n[E] Take the rifle on the rail.  [RMB] Scope\nHeadshots %d   body %d   every beam they hit on the way down +%d" % [HEADSHOT, BODY, BONK])


func _process(delta: float) -> void:
	_t += delta
	_walk(delta)
	_update_spots(delta)
	_update_ropes()
	_update_hud()
	if done:
		return
	_next -= delta
	if _spawned < WALKERS and _next <= 0.0 and _walkers.size() < MAX_ON_WIRE:
		_spawn_walker()
		_next = GAP * randf_range(0.8, 1.25)
	if _spawned >= WALKERS and _walkers.is_empty():
		if _ending < 0.0:
			_ending = _t
		elif _t - _ending > 3.5:
			_finish()


func _spawn_walker() -> void:
	var wi := _spawned % WIRES.size()
	var w: Vector2 = WIRES[wi]
	var from_left := (_spawned / 2) % 2 == 0
	var sd := -1.0 if from_left else 1.0
	var c := spawn(Vector3(sd * (HALF + 0.4), w.x, w.y), "clown", "static")
	c.get_node("Brain").queue_free()          # it only walks the wire
	c.always_pose = true
	c.set_process(true)
	c.extra_pose = _balance.bind(c)
	c.hurt.connect(func(cl: Clown) -> void: _lose_balance.call_deferred(cl))
	c.died.connect(_fell)
	if c.ragdoll:
		c.ragdoll.landed.connect(_bonk.bind(c))
	var speed := randf_range(0.75, 1.15) * -sd
	_walkers.append({clown = c, speed = speed, wire = wi, wobble = randf_range(0.7, 1.5), t = randf() * TAU, pause = 0.0})
	_spawned += 1
	_light(c)


func _walk(delta: float) -> void:
	for w: Dictionary in _walkers.duplicate():
		var c: Clown = w.clown
		if not is_instance_valid(c) or c.dead:
			_walkers.erase(w)
			continue
		w.t += delta
		# now and then one stops dead to steady itself, then carries on
		if w.pause > 0.0:
			w.pause -= delta
		elif randf() < delta * 0.08:
			w.pause = randf_range(0.8, 1.6)
		var v: float = 0.0 if w.pause > 0.0 else w.speed
		var x: float = c.position.x + v * delta
		c.position = Vector3(x, WIRES[w.wire].x, WIRES[w.wire].y)
		c.rotation.y = PI * 0.5 * signf(w.speed)
		c.velocity = Vector3(v, 0, 0)
		c.walk_amount = 0.35 if v != 0.0 else 0.0
		# made it across: a bow, and off it goes
		if absf(x) > HALF + 0.3 and signf(x) == signf(w.speed):
			escaped += 1
			score = maxi(score - 1, 0)
			_say("ESCAPED  -1")
			_walkers.erase(w)
			enemies.erase(c)
			c.queue_free()


## Arms straight out, the body swaying over the wire.
func _balance(c: Clown) -> void:
	var wob := 1.0
	for w: Dictionary in _walkers:
		if w.clown == c:
			wob = w.wobble * (1.8 if w.pause > 0.0 else 1.0)
	var t := Time.get_ticks_msec() * 0.001 + c.get_instance_id() % 7
	for s: float in [1.0, -1.0]:
		var side := "Left" if s > 0.0 else "Right"
		c._turn(side + "UpperArm", Vector3.BACK, deg_to_rad(76.0) * s + sin(t * 1.7) * 0.25 * wob)
	c._turn("Spine", Vector3.BACK, sin(t * 1.7) * 0.12 * wob)
	c._turn("Neck", Vector3.BACK, -sin(t * 1.7) * 0.1 * wob)


## A hit anywhere on a walker: it loses its footing and drops.
func _lose_balance(c: Clown) -> void:
	if not is_instance_valid(c) or c.dead or not c.ragdoll:
		return
	var hips: PhysicalBone3D = c.ragdoll.bones.get(&"Hips")
	if hips == null:
		return
	var side := Vector3(randf_range(-0.4, 0.4), 0, -1)
	c.hit({collider = hips, position = hips.global_position, direction = side, damage = 500.0, impulse = 1.0, blood = 0.2, shot_id = -2 - int(c.get_instance_id() % 100000)})


## The rifle went off: score whatever it hit.
func _on_rifle(hit: Dictionary) -> void:
	var col: Object = hit.get("collider")
	if not (col is PhysicalBone3D) or not col.has_meta(&"clown"):
		return
	var c: Clown = col.get_meta(&"clown")
	if c.has_meta(&"scored") or not enemies.has(c):
		return
	c.set_meta(&"scored", true)
	if c._zone(StringName((col as PhysicalBone3D).bone_name)) == &"Neck":
		score += HEADSHOT
		headshots += 1
		_say("HEADSHOT  +%d" % HEADSHOT)
	else:
		score += BODY
		_say("+%d" % BODY)


## Down it goes: a push off the wire and a turn, so it tumbles.
func _fell(c: Clown) -> void:
	_score_fall.call_deferred(c)        # after the rifle has had its say
	c.set_meta(&"bonks", 0)
	if c.ragdoll:
		c.ragdoll.tumble.call_deferred(Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.0), randf_range(-0.6, 0.3)), randf_range(2.5, 6.0))


## Killed some other way than the rifle (a pistol, a fall): a body point.
func _score_fall(c: Clown) -> void:
	if is_instance_valid(c) and not c.has_meta(&"scored"):
		c.set_meta(&"scored", true)
		score += BODY
		_say("+%d" % BODY)


## A falling body hit something. Anything above the floor is rigging: a bonus.
func _bonk(speed: float, c: Clown) -> void:
	if not is_instance_valid(c) or not c.dead or not c.ragdoll:
		return
	var y: float = (c.ragdoll.bones[&"Hips"] as PhysicalBone3D).global_position.y - global_position.y
	if y > 1.2:
		var n: int = c.get_meta(&"bonks", 0)
		if n < MAX_BONKS:
			c.set_meta(&"bonks", n + 1)
			bonks += 1
			score += BONK
			_say(["BONK", "CRACK", "THWACK", "CLANG"].pick_random() + "  +%d" % BONK)
	elif speed > 11.0:
		_say("SPLAT")


func _finish() -> void:
	var tier := ""
	for t: Array in TIERS:
		if score >= int(t[0]):
			tier = t[1]
			break
	var r := {success = tier != "", upgrade = false, tickets = 0, heal = 0.0}
	match tier:
		"GOLD":
			r.tickets = 14
			r.heal = 999.0
			r.upgrade = true
		"SILVER":
			r.tickets = 9
			r.heal = 50.0
			r.upgrade = true
		"BRONZE":
			r.tickets = 5
			r.heal = 25.0
	r.line = "THE HIGH WIRE  %s\n%d points   %d headshots   %d bonks   %d got across" % [tier if tier != "" else "- no prize", score, headshots, bonks, escaped]
	if player and player.mount == rifle:
		player.dismount()
	complete(r)


## The room ends when the act is over, not when the last one dies.
func enemy_died(_c: Clown) -> void:
	pass


# --- lights, ropes, HUD -------------------------------------------------------------------
func _light(c: Clown) -> void:
	for k in _spots.size():
		var on: Array = _spot_on[k]
		if on[0] == null or not is_instance_valid(on[0]):
			on[0] = c
			on[1] = 0.0
			return


func _update_spots(delta: float) -> void:
	for k in _spots.size():
		var fs: SpotLight3D = _spots[k]
		var on: Array = _spot_on[k]
		var c: Clown = on[0] if on[0] != null and is_instance_valid(on[0]) else null
		if c == null:
			on[0] = null
			fs.light_energy = move_toward(fs.light_energy, 0.0, delta * 30.0)
			continue
		var at := c.global_position + Vector3.UP * 1.1
		if c.dead and c.ragdoll and c.ragdoll.bones.has(&"Hips"):
			# stay on the body down to the floor, then let it go
			at = (c.ragdoll.bones[&"Hips"] as PhysicalBone3D).global_position
			on[1] += delta
			fs.spot_angle = move_toward(fs.spot_angle, 9.0, delta * 6.0)
			if on[1] > 4.0:
				on[0] = null
				continue
		else:
			fs.spot_angle = move_toward(fs.spot_angle, 4.5, delta * 6.0)
		fs.light_energy = move_toward(fs.light_energy, 60.0, delta * 120.0)
		var want := fs.global_transform.looking_at(at, Vector3.UP).basis
		fs.global_basis = fs.global_basis.slerp(want, clampf(delta * 16.0, 0.0, 1.0)).orthonormalized()


func _update_ropes() -> void:
	for p: Array in _pendulums:
		var rb: RigidBody3D = p[0]
		var im: ImmediateMesh = (p[2] as MeshInstance3D).mesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var a: Vector3 = p[1]
		if p[3] == "trapeze":
			for sd: float in [-0.55, 0.55]:
				im.surface_add_vertex(a + Vector3(sd, 0, 0))
				im.surface_add_vertex(rb.position + rb.basis.x * sd)
		else:
			im.surface_add_vertex(a)
			im.surface_add_vertex(rb.position + rb.basis.y * 0.45)
		im.surface_end()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
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
	tw.tween_interval(0.7)
	tw.tween_property(_ticker, "modulate:a", 0.0, 0.4)


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "" if done else "SCORE %d     WALKERS LEFT %d" % [score, WALKERS - _spawned + _walkers.size()]
