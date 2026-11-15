class_name HighWire
extends EventRoom
## THE HIGH WIRE. A tall round shaft lit like a circus tent. Up in the dark,
## clowns walk a tightrope between two platforms, arms out, wobbling; two
## WitzSoldats on the platforms shoot down. Everything you hit up there comes
## all the way down.

const H := 11.0                    ## height of the wire
const SPAN := 9.0
var _walkers: Array = []           # [clown, speed, phase]


func build() -> void:
	title = "The High Wire"
	concrete_room(Vector3(-6, 0, -7), Vector3(12, 15, 14))
	# a faded ring painted on the floor, and sawdust
	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(9, 9)
	qm.orientation = PlaneMesh.FACE_Y
	ring.mesh = qm
	ring.material_override = LevelArt._mat("sunburst_faded")
	ring.position = Vector3(0, 0.01, 0)
	add_child(ring)
	# platforms with ladders, and the wire
	for sd: float in [-1.0, 1.0]:
		# no collision: shots from the floor get through, and the dead drop straight off
		solid(Vector3(sd * (SPAN * 0.5 + 0.8), H - 0.1, 0), Vector3(1.6, 0.2, 2.0), "planks_dark", false)
		for k in 2:
			solid(Vector3(sd * (SPAN * 0.5 + 0.8) + (k - 0.5) * 1.3, (H - 0.2) * 0.5, -0.9), Vector3(0.12, H - 0.2, 0.12), "metal", false)
		solid(Vector3(sd * (SPAN * 0.5 + 0.8), H + 0.5, -0.95), Vector3(1.6, 1.0, 0.06), "harlequin_faded", false)
	var wire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = SPAN + 1.6
	wire.mesh = cm
	wire.material_override = LevelArt._mat("wire")
	wire.position = Vector3(0, H, 0)
	wire.rotation.z = PI * 0.5
	add_child(wire)
	# a safety net that was taken down long ago: just its frame, sagging
	solid(Vector3(0, 0.25, 3.5), Vector3(5.0, 0.5, 0.2), "planks_dark")
	# spotlights from below on the wire, and a bulb by the door
	for sd: float in [-1.0, 1.0]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.85, 0.65)
		sp.light_energy = 16.0
		sp.spot_range = 22.0
		sp.spot_angle = 20.0
		sp.shadow_enabled = true
		sp.light_volumetric_fog_energy = 3.0
		add_child(sp)
		sp.position = Vector3(sd * 4.5, 0.6, 5.5)
		sp.look_at(to_global(Vector3(0, H, 0)), Vector3.UP)
	bulb(Vector3(0, 3.0, 5.5), 2.0, 8.0)
	# a ring of carnival bulbs round the shaft at the height of the wire, and
	# a chandelier of them above it: the act is lit, the floor is not
	for k in 16:
		var a := TAU * k / 16.0
		var col := Color(1.0, 0.75, 0.45) if k % 2 == 0 else Color(1.0, 0.45, 0.3)
		bulb(Vector3(cos(a) * 5.7, H + 1.4, sin(a) * 6.7), 1.4 if k % 4 == 0 else 0.0, 7.0, col, false)
	bulb(Vector3(0, H + 3.0, 0), 4.0, 12.0, Color(1.0, 0.85, 0.65), true)
	make_exit(Vector3(0, 0, 6.9), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 5.8))


func begin() -> void:
	# three on the wire, arms out
	for i in 3:
		var c := spawn(Vector3(lerpf(-3.0, 3.0, i / 2.0), H, 0), "clown", "static")
		c.rotation.y = PI * 0.5 * (1.0 if i % 2 == 0 else -1.0)
		c.extra_pose = _balance.bind(c)
		c.get_node("Brain").queue_free()          # it only walks the wire
		c.always_pose = true
		c.set_process(true)
		_walkers.append([c, randf_range(0.4, 0.8) * (1.0 if i % 2 == 0 else -1.0), randf() * TAU])
	# two riflemen on the platforms
	for sd: float in [-1.0, 1.0]:
		var s := spawn(Vector3(sd * (SPAN * 0.5 + 0.9), H, 0.2), "witzsoldat", "static")
		var b: RoomBrain = s.get_node("Brain")
		b.accuracy = 0.35
		b.gun_damage = 9.0
		b.shot_gap = Vector2(2.6, 3.8)


func _process(delta: float) -> void:
	for w: Array in _walkers:
		var c: Clown = w[0]
		if not is_instance_valid(c) or c.dead or c.downed:
			continue
		# shuffle along the wire, turning at the ends
		var x := c.position.x + float(w[1]) * delta
		if absf(x) > SPAN * 0.5 - 0.6:
			w[1] = -float(w[1])
			x = clampf(x, -(SPAN * 0.5 - 0.6), SPAN * 0.5 - 0.6)
		c.position = Vector3(x, H, 0)
		c.rotation.y = PI * 0.5 * signf(w[1])
		c.velocity = Vector3(float(w[1]), 0, 0)
		c.walk_amount = 0.35
		w[2] += delta


## Arms straight out, the body swaying over the wire.
func _balance(c: Clown) -> void:
	var t := Time.get_ticks_msec() * 0.001 + c.get_instance_id() % 7
	for s: float in [1.0, -1.0]:
		var side := "Left" if s > 0.0 else "Right"
		c._turn(side + "UpperArm", Vector3.BACK, deg_to_rad(76.0) * s + sin(t * 1.7) * 0.25)
	c._turn("Spine", Vector3.BACK, sin(t * 1.7) * 0.12)
	c._turn("Neck", Vector3.BACK, -sin(t * 1.7) * 0.1)
