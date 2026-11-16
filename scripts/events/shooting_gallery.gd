class_name ShootingGallery
extends EventRoom
## THE SHOOTING GALLERY. A fairground booth: a counter, strings of bulbs, three
## rows of painted cover and a harlequin backdrop. Plywood clowns and soldiers
## flip up and drop again, faster and faster; a few of the soldiers are real
## and shoot back. Don't shoot the little girl. Forty-five seconds.

const TIME := 45.0
const ROWS := [[-1.6, 0.9], [-4.6, 1.2], [-7.4, 1.5]]     # [z, cover height]
const SLOTS := [-3.4, -1.7, 0.0, 1.7, 3.4]
const TIERS := [[80, "GOLD"], [55, "SILVER"], [30, "BRONZE"]]

var score := 0
var _targets: Array[GalleryTarget] = []
var _soldiers: Array = []          # [clown, timer, up]
var _next := 1.0
var _running := false
var _over := false
var _hud: Label


func build() -> void:
	title = "The Shooting Gallery"
	concrete_room(Vector3(-5, 0, -9), Vector3(10, 4.2, 12.5))
	# the counter you shoot over
	solid(Vector3(0, 0.52, 1.2), Vector3(9.8, 1.05, 0.5), "planks")
	solid(Vector3(0, 1.08, 1.15), Vector3(9.9, 0.06, 0.65), "planks_dark")
	# three rows of painted cover, a backdrop
	for row: Array in ROWS:
		solid(Vector3(0, float(row[1]) * 0.5, float(row[0])), Vector3(9.6, float(row[1]), 0.25), "planks")
		var band := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(9.6, 0.22)
		band.mesh = qm
		band.material_override = LevelArt._mat("harlequin_faded")
		band.position = Vector3(0, float(row[1]) - 0.14, float(row[0]) + 0.13)
		add_child(band)
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(10, 4.2)
	back.mesh = bq
	back.material_override = LevelArt._mat("sunburst_faded")
	back.position = Vector3(0, 2.1, -8.97)
	add_child(back)
	# bulbs: a string across the front of the booth and down the sides
	for i in 13:
		var x := lerpf(-4.6, 4.6, i / 12.0)
		var col: Color = [Color(1.0, 0.8, 0.45), Color(1.0, 0.4, 0.3), Color(0.5, 0.8, 1.0)][i % 3]
		bulb(Vector3(x, 3.6 - sin(i / 12.0 * PI) * 0.25, 0.9), 0.9 if i % 3 == 0 else 0.0, 6.0, col, false)
	for z: float in [-2.5, -6.0]:
		bulb(Vector3(0, 3.9, z), 3.0, 9.0)
	# footlights along each row of cover, washing up the targets, and two
	# floods from over the counter
	for row: Array in ROWS:
		for x: float in [-3.0, 0.0, 3.0]:
			var fl := OmniLight3D.new()
			fl.light_color = Color(1.0, 0.82, 0.55)
			fl.light_energy = 1.6
			fl.omni_range = 2.6
			fl.position = Vector3(x, float(row[1]) + 0.1, float(row[0]) + 0.35)
			add_child(fl)
	for sd: float in [-1.0, 1.0]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.9, 0.75)
		sp.light_energy = 8.0
		sp.spot_range = 16.0
		sp.spot_angle = 32.0
		sp.shadow_enabled = true
		add_child(sp)
		sp.position = Vector3(sd * 3.0, 3.8, 0.6)
		sp.look_at(to_global(Vector3(sd * 0.8, 1.2, -5.0)), Vector3.UP)
	# the targets: a plywood cutout behind every slot of every row
	for r in ROWS.size():
		for x: float in SLOTS:
			var t := GalleryTarget.new()
			add_child(t)
			t.position = Vector3(x + randf_range(-0.2, 0.2), float(ROWS[r][1]) - 0.5, float(ROWS[r][0]) - 0.3)
			t.gallery = self
			_targets.append(t)
	make_exit(Vector3(0, 0, 3.38), Vector3(0, 0, -1))
	entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 2.2))
	_build_hud()


func begin() -> void:
	# three real WitzSoldats crouch behind the back row
	for x: float in [-2.6, 0.0, 2.6]:
		var c := spawn(Vector3(x, 0, float(ROWS[2][0]) - 0.6), "witzsoldat", "static")
		c.rotation.y = 0.0
		c.crouch_amount = 1.0
		var b: RoomBrain = c.get_node("Brain")
		b.accuracy = 0.4
		b.gun_damage = 8.0
		b.shot_gap = Vector2(0.9, 1.3)
		b.process_mode = Node.PROCESS_MODE_DISABLED
		_soldiers.append([c, randf_range(4.0, 8.0), false])
	_flash("STEP UP!\nForty-five seconds. Mind the little girl.")
	await get_tree().create_timer(2.5).timeout
	_running = true
	_t = 0.0


func _process(delta: float) -> void:
	_update_hud()
	if not _running:
		return
	_t += delta
	var k := clampf(_t / TIME, 0.0, 1.0)
	_next -= delta
	if _next <= 0.0:
		_next = lerpf(1.2, 0.5, k)
		for i in (1 if randf() < 0.6 - k * 0.3 else 2):
			var down := _targets.filter(func(t: GalleryTarget) -> bool: return t.state == 0)
			if down.is_empty():
				break
			var t: GalleryTarget = down.pick_random()
			var roll := randf()
			t.pop("civilian" if roll < 0.14 else ("soldier" if roll < 0.55 else "clown"), lerpf(1.9, 1.0, k))
	# the real ones: duck down, come up, aim, shoot, duck again
	for s: Array in _soldiers:
		var c: Clown = s[0]
		if not is_instance_valid(c) or c.dead or c.downed:
			continue
		var b: RoomBrain = c.get_node("Brain")
		s[1] -= delta
		if s[1] <= 0.0:
			s[2] = not s[2]
			s[1] = randf_range(2.0, 3.0) if s[2] else randf_range(3.0, 6.0) * lerpf(1.0, 0.6, k)
			b.process_mode = Node.PROCESS_MODE_INHERIT if s[2] else Node.PROCESS_MODE_DISABLED
			b._cooldown = 0.9
		c.crouch_amount = move_toward(c.crouch_amount, 0.0 if s[2] else 1.0, delta * 4.0)
		c.aim_amount = move_toward(c.aim_amount, 1.0 if s[2] else 0.0, delta * 3.0)
		c.aim_point = player.global_position + Vector3.UP * 1.3
	if _t >= TIME:
		_finish()


## A cutout was hit: what it was, and whether it was in the head.
func scored(kind: String, head: bool) -> void:
	match kind:
		"civilian":
			score -= 5
			_flash("-5  NOT HER!")
		_:
			score += 2 if head else 1


func enemy_died(_c: Clown) -> void:
	if _running:
		score += 5


func _finish() -> void:
	_running = false
	_over = true
	for t: GalleryTarget in _targets:
		t.drop()
	# the real ones slip away behind the backdrop
	for s: Array in _soldiers:
		var c: Clown = s[0]
		if is_instance_valid(c) and not c.dead:
			c.queue_free()
	var tier := ""
	for tr: Array in TIERS:
		if score >= int(tr[0]):
			tier = tr[1]
			break
	var r := {success = tier != "", tickets = 0, heal = 0.0, upgrade = false}
	match tier:
		"GOLD":
			r.tickets = 12
			r.heal = 999.0
			r.upgrade = true
		"SILVER":
			r.tickets = 8
			r.heal = 50.0
			r.upgrade = true
		"BRONZE":
			r.tickets = 4
			r.heal = 25.0
	r.tier = tier
	r.line = "SHOOTING GALLERY  %s\nScore %d" % [tier if tier != "" else "- no prize", score]
	complete(r)


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


func _update_hud() -> void:
	if _hud:
		_hud.text = ("%d   |   SCORE %d" % [ceil(maxf(TIME - _t, 0.0)), score]) if _running else ("SCORE %d" % score if _over else "")


func _flash(t: String) -> void:
	var g := get_tree().get_first_node_in_group(&"game")
	if g and g.has_method("event_banner"):
		g.event_banner(t)
