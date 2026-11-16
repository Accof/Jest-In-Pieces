class_name Base
extends EventRoom
## THE BASE. A forward command bunker that the circus moved into: concrete,
## sandbags and field telephones under strings of fairground bulbs. You come
## round here after every death. Walk about and press [E]:
##   - the Quartermaster's ticket booth: spend tickets on permanent perks
##   - the chalkboard: everything you have ever killed, and how
##   - the trophy wall: plaques that fill as you hit milestones
##   - the fortune teller: 5 tickets for a card that changes your next run
##   - the armoury rack: choose what you start a run holding
##   - the steel door: back to the front (a new run)

const FORTUNE_COST := 5
## What the fortune teller can deal: [weight, kind, value, text]
const FORTUNES := [
	[3, "upgrade", "hollow", "THE CARD OF TEETH\nYour bullets will bite deeper.\n(next run: Hollow Points)"],
	[3, "upgrade", "trigger", "THE TWITCHING HAND\nYou will fire faster than you think.\n(next run: Itchy Finger)"],
	[3, "upgrade", "meat", "THE FAT MAN\nYou will not die easily.\n(next run: Thick Hide)"],
	[3, "upgrade", "legs", "THE RUNNING CLOWN\nYour feet will be quick.\n(next run: Greased Shoes)"],
	[3, "upgrade", "leech", "THE VAMPIRE\nTheir blood will be yours.\n(next run: Blood Drinker)"],
	[2, "upgrade", "saw", "THE BUTCHER\nLimbs will come away in your hands.\n(next run: Bone Saw Rounds)"],
	[2, "upgrade", "pellets", "THE CANNON\nYour shells will be heavy.\n(next run: Packed Shells)"],
	[2, "health", "50", "THE STRONGMAN\nYou will carry more blood than most.\n(next run: +50 health)"],
	[1, "tickets", "25", "THE JACKPOT\nThe machine coughs up 25 tickets."],
	[2, "nothing", "", "THE EMPTY CHAIR\nThe card is blank.\nThe machine laughs at you."],
]
## The guns on the rack, in WEAPONS order (the Maxim is not a starting gun).
const RACK := [0, 1, 2, 3, 5]

var game: Node                     # the game: save, shop, start_run
var _stat_cols: Array[Label3D] = []   # names, values, names, values
var _history_label: Label3D
var _fortune_label: Label3D
var _rack_labels: Array[Label3D] = []
var _trophy_nodes: Array = []      # [holder, plate label, trophy]
var _booth_head: Node3D
var _fortune_glow: OmniLight3D
var _door_lamp: OmniLight3D
var _t2 := 0.0


func build() -> void:
	title = "Base"
	concrete_room(Vector3(-8, 0, -6), Vector3(16, 4.0, 12))
	entry = Transform3D(Basis(Vector3.UP, -0.75), Vector3(-5.2, 0.05, 3.6))      # waking up, looking across the room
	_dressing()
	_cot()
	_front_door()
	_quartermaster()
	_chalkboard()
	_trophy_wall()
	_fortune_teller()
	_armoury()
	_map_table()
	_lights()


func _process(delta: float) -> void:
	_t2 += delta
	if _booth_head:
		_booth_head.rotation = Vector3(sin(_t2 * 1.3) * 0.08, sin(_t2 * 0.7) * 0.35, sin(_t2 * 1.9) * 0.05)
	if _fortune_glow:
		_fortune_glow.light_energy = 2.4 + sin(_t2 * 5.0) * 0.4 + randf_range(-0.15, 0.15)
	if _door_lamp:
		_door_lamp.light_energy = 2.0 * (0.6 + 0.4 * absf(sin(_t2 * 2.2)))


## Bring every board and label up to date with the save.
func refresh() -> void:
	var save: Dictionary = game.save
	# the chalkboard, in two columns of names and numbers
	var half := (Records.STATS.size() + 1) / 2
	for col in 2:
		var text := ""
		for i in range(col * half, mini((col + 1) * half, Records.STATS.size())):
			var st: Array = Records.STATS[i]
			text += "%s:  %d\n" % [String(st[1]), Records.stat(save, st[0])]
		_stat_cols[col].text = text
	# trophies
	for tn: Array in _trophy_nodes:
		var t: Dictionary = tn[2]
		var won := Records.has_trophy(save, t.id)
		(tn[0] as Node3D).visible = won
		(tn[3] as Node3D).visible = not won
		var have := Records.stat(save, t.stat)
		(tn[1] as Label3D).text = "%s\n%s" % [t.name if won else "? ? ?", t.desc if won else "%s  (%d/%d)" % [t.desc, mini(have, int(t.need)), int(t.need)]]
		(tn[1] as Label3D).modulate = Color(0.95, 0.85, 0.55) if won else Color(0.55, 0.55, 0.55)
	# the rack
	var start := int(save.get("start_weapon", 0))
	var wk: Dictionary = save.get("weapon_kills", {})
	for i in RACK.size():
		var w: Dictionary = FpsPlayer.WEAPONS[RACK[i]]
		_rack_labels[i].text = "%s%s\n%d kills" % ["> " if RACK[i] == start else "", w.name, int(wk.get(w.name, 0))]
		_rack_labels[i].modulate = Color(1.0, 0.85, 0.4) if RACK[i] == start else Color(0.85, 0.82, 0.75)
	# the fortune waiting for the next run
	var f: Variant = save.get("fortune", null)
	_fortune_label.text = ("YOUR CARD\n" + str((f as Dictionary).get("text", ""))) if f is Dictionary and not (f as Dictionary).is_empty() else "MADAME BONZO\nSEES ALL\n%d tickets" % FORTUNE_COST
	# run history on the map table's board
	var hist: Array = save.get("history", [])
	var h := "LAST RUNS\n\n"
	if hist.is_empty():
		h += "(none yet)"
	for r: Variant in hist:
		if r is Dictionary:
			h += "floor %d   %d kills   +%d tickets\n" % [int(r.get("floor", 0)), int(r.get("kills", 0)), int(r.get("tickets", 0))]
	_history_label.text = h


# --- the stations ---------------------------------------------------------------------
func _front_door() -> void:
	# a heavy steel door in the north wall, a red lamp over it, a painted sign
	solid(Vector3(0, 1.15, -5.95), Vector3(1.6, 2.3, 0.12), "door", false)
	solid(Vector3(0, 2.4, -5.95), Vector3(1.9, 0.12, 0.2), "steel", false)
	for x: float in [-0.9, 0.9]:
		solid(Vector3(x, 1.2, -5.95), Vector3(0.12, 2.4, 0.2), "steel", false)
	_label("TO THE FRONT", Vector3(0, 2.85, -5.88), 0.0, 64, Color(0.95, 0.2, 0.12))
	_label("[E] start a run", Vector3(0, 0.4, -5.86), 0.0, 40, Color(0.8, 0.75, 0.65))
	_door_lamp = bulb(Vector3(0, 3.3, -5.7), 2.0, 6.0, Color(1.0, 0.2, 0.1), false)
	var u := BaseUsable.make(Vector3(1.6, 2.3, 0.4), "[E] To the front: start a run", func(_p: Node) -> void: game.start_run())
	add_child(u)
	u.position = Vector3(0, 1.15, -5.75)
	# sandbags either side
	for x: float in [-1.6, 1.6]:
		for k in 3:
			solid(Vector3(x + signf(x) * k * 0.15, 0.2 + k * 0.32, -5.6), Vector3(0.9, 0.3, 0.5), "sandbag")


func _quartermaster() -> void:
	# a ticket booth against the west wall: counter, back panel with a
	# window, a striped awning, and a clown in a cap behind it
	var x := -7.0
	solid(Vector3(x + 0.55, 0.55, -1.0), Vector3(0.6, 1.1, 3.0), "planks_dark")
	solid(Vector3(x + 0.55, 1.12, -1.0), Vector3(0.75, 0.05, 3.15), "wood")
	solid(Vector3(x - 0.75, 1.9, -1.0), Vector3(0.1, 3.8, 3.4), "harlequin_faded", false)
	for k in 7:
		var stripe := "harlequin_faded" if k % 2 == 0 else "wood"
		solid(Vector3(x + 0.7, 2.75 - 0.0, -2.5 + k * 0.5 + 0.25), Vector3(1.4, 0.06, 0.5), stripe, false)
	_label("QUARTERMASTER", Vector3(x + 0.86, 2.98, -1.0), PI * 0.5, 54, Color(0.95, 0.75, 0.3))
	_label("TICKETS TAKEN HERE", Vector3(x + 0.87, 1.3, -1.0), PI * 0.5, 36, Color(0.85, 0.8, 0.7))
	for z: float in [-2.3, -1.6, -0.9, -0.2, 0.4]:
		bulb(Vector3(x + 1.38, 2.68, z), 0.0 if int(z * 10) % 2 else 0.8, 3.0, Color(1.0, 0.7, 0.4), false)
	# ticket rolls and a cash box on the counter
	for z: float in [-2.0, -1.7]:
		var roll := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.08
		cm.height = 0.07
		roll.mesh = cm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.7, 0.15, 0.1)
		roll.material_override = rm
		roll.position = Vector3(x + 0.55, 1.18, z)
		add_child(roll)
	solid(Vector3(x + 0.5, 1.22, 0.1), Vector3(0.3, 0.15, 0.4), "steel", false)
	var u := BaseUsable.make(Vector3(0.8, 1.2, 3.0), "", func(_p: Node) -> void: game.open_shop())
	u.text_fn = func() -> String: return "[E] Quartermaster: spend tickets  (%d)" % int(game.save.get("tickets", 0))
	add_child(u)
	u.position = Vector3(x + 0.55, 0.9, -1.0)
	# the clown who keeps the booth (he does not move much)
	var qm := Clown.new()
	add_child(qm)
	qm.position = Vector3(x - 0.3, 0, -1.4)
	qm.rotation.y = PI * 0.5
	qm.always_pose = true
	qm.set_process(true)
	qm.extra_pose = func() -> void:
		qm._turn("Neck", Vector3.BACK, sin(_t2 * 0.6) * 0.15)
		qm._turn("Spine", Vector3.RIGHT, deg_to_rad(8.0))


func _chalkboard() -> void:
	# a big blackboard on the east wall, framed in wood, with the tallies
	var x := 7.92
	var board := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(5.4, 2.5)
	board.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.07, 0.09, 0.075)
	bm.roughness = 0.95
	board.material_override = bm
	board.position = Vector3(x, 2.05, 0.6)
	board.rotation.y = -PI * 0.5
	add_child(board)
	for y: float in [0.78, 3.32]:
		solid(Vector3(x - 0.02, y, 0.6), Vector3(0.08, 0.08, 5.6), "wood", false)
	for z: float in [-2.12, 3.32]:
		solid(Vector3(x - 0.02, 2.05, z), Vector3(0.08, 2.62, 0.08), "wood", false)
	# chalk: each column a label of names (left) and one of numbers (right),
	# each in a box the width of its half of the board
	var chalk := Color(0.9, 0.9, 0.85)
	_label("LIFETIME", Vector3(x - 0.03, 3.08, 0.6), -PI * 0.5, 44, chalk).outline_size = 0
	for col in 2:
		var centre := 0.6 + (col - 0.5) * 2.6           # board runs z -2.1..3.3
		var l := _label("", Vector3(x - 0.03, 1.95, centre), -PI * 0.5, 38, chalk)
		l.outline_size = 0
		l.line_spacing = 1.0
		_stat_cols.append(l)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 6.0
	lamp.spot_range = 7.0
	lamp.spot_angle = 50.0
	add_child(lamp)
	lamp.position = Vector3(6.0, 3.7, 0.6)
	lamp.look_at(to_global(Vector3(x, 2.0, 0.6)), Vector3.UP)


func _trophy_wall() -> void:
	# plaques on the south wall, two rows of eight; each holds a trophy once
	# it is won, and an empty bracket with a "?" until then
	var z := 5.9
	for i in Records.TROPHIES.size():
		var t: Dictionary = Records.TROPHIES[i]
		var col := i % 8
		var row := i / 8
		var at := Vector3(-0.9 - col * 0.9, 2.7 - row * 1.25, z)        # reads left to right from inside
		solid(at + Vector3(0, 0.0, 0.03), Vector3(0.72, 0.9, 0.05), "wood", false)
		solid(at + Vector3(0, -0.33, -0.12), Vector3(0.6, 0.04, 0.26), "planks_dark", false)
		var holder := Node3D.new()
		add_child(holder)
		holder.position = at + Vector3(0, -0.31, -0.12)
		_trophy_model(holder, String(t.model))
		var plate := _label("", at + Vector3(0, -0.56, -0.01), PI, 20, Color.WHITE)
		plate.width = 190.0
		plate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var mark := _label("?", at + Vector3(0, 0.05, -0.01), PI, 72, Color(0.35, 0.33, 0.3))
		_trophy_nodes.append([holder, plate, t, mark])
	_label("TROPHIES", Vector3(-4.05, 3.55, 5.88), PI, 52, Color(0.95, 0.75, 0.3))
	for x: float in [-6.5, -4.0, -1.5]:
		bulb(Vector3(x, 3.75, 5.4), 2.6, 4.5, Color(1.0, 0.8, 0.55), false)


func _fortune_teller() -> void:
	# a glass cabinet in the south-east corner: a clown automaton bust in a
	# turban, lit from inside; put tickets in, a card comes out
	var at := Vector3(6.6, 0, 4.7)
	var yaw := deg_to_rad(-135.0)
	var root := Node3D.new()
	add_child(root)
	root.position = at
	root.rotation.y = yaw
	var plinth := solid(Vector3.ZERO, Vector3(1.3, 1.0, 0.9), "planks_dark")
	plinth.reparent(root, false)
	plinth.position = Vector3(0, 0.5, 0)
	var crown := solid(Vector3.ZERO, Vector3(1.4, 0.25, 1.0), "harlequin_faded", false)
	crown.reparent(root, false)
	crown.position = Vector3(0, 2.35, 0)
	for x: float in [-0.62, 0.62]:
		var post := solid(Vector3.ZERO, Vector3(0.08, 1.25, 0.08), "brass", false)
		post.reparent(root, false)
		post.position = Vector3(x, 1.62, 0.42)
	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.22, 1.22, 0.82)
	glass.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.7, 0.8, 0.75, 0.15)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.05
	gmat.metallic_specular = 0.9
	glass.material_override = gmat
	glass.position = Vector3(0, 1.62, 0)
	root.add_child(glass)
	# the automaton: shoulders in a velvet robe, white face, red nose, turban
	var bust := Node3D.new()
	bust.position = Vector3(0, 1.0, -0.05)
	root.add_child(bust)
	var robe := StandardMaterial3D.new()
	robe.albedo_color = Color(0.3, 0.05, 0.12)
	robe.roughness = 0.9
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.92, 0.9, 0.85)
	var nose := StandardMaterial3D.new()
	nose.albedo_color = Color(0.8, 0.05, 0.04)
	nose.emission_enabled = true
	nose.emission = Color(0.6, 0.02, 0.0)
	nose.emission_energy_multiplier = 0.6
	_prim(bust, "box", Vector3(0.62, 0.3, 0.32), Vector3(0, 0.15, 0), robe)
	_booth_head = Node3D.new()
	_booth_head.position = Vector3(0, 0.52, 0)
	bust.add_child(_booth_head)
	_prim(_booth_head, "sphere", Vector3(0.2, 0.24, 0.2), Vector3.ZERO, face)
	_prim(_booth_head, "sphere", Vector3(0.05, 0.05, 0.05), Vector3(0, -0.01, 0.1), nose)
	for x: float in [-0.05, 0.05]:
		_prim(_booth_head, "sphere", Vector3(0.025, 0.03, 0.02), Vector3(x, 0.04, 0.09), LevelArt._mat("iron"))
	_prim(_booth_head, "sphere", Vector3(0.23, 0.14, 0.23), Vector3(0, 0.13, -0.01), robe)
	_prim(_booth_head, "sphere", Vector3(0.04, 0.04, 0.04), Vector3(0, 0.17, 0.11), LevelArt._mat("brass"))
	# a crystal ball on a little stand, and hands either side of it
	var ball := StandardMaterial3D.new()
	ball.albedo_color = Color(0.6, 0.75, 1.0, 0.5)
	ball.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.emission_enabled = true
	ball.emission = Color(0.3, 0.5, 1.0)
	ball.emission_energy_multiplier = 1.4
	_prim(root, "sphere", Vector3(0.12, 0.12, 0.12), Vector3(0, 1.17, 0.18), ball)
	for x: float in [-0.16, 0.16]:
		_prim(root, "sphere", Vector3(0.07, 0.04, 0.09), Vector3(x, 1.1, 0.16), face)
	_fortune_glow = OmniLight3D.new()
	_fortune_glow.light_color = Color(0.55, 0.65, 1.0)
	_fortune_glow.light_energy = 2.4
	_fortune_glow.omni_range = 3.0
	_fortune_glow.position = Vector3(0, 1.35, 0.25)
	root.add_child(_fortune_glow)
	_fortune_label = _label("", Vector3.ZERO, 0.0, 26, Color(0.95, 0.85, 0.6))
	_fortune_label.reparent(root, false)
	_fortune_label.position = Vector3(0, 0.62, 0.47)
	_fortune_label.rotation = Vector3.ZERO
	var sign_l := _label("MADAME BONZO", Vector3.ZERO, 0.0, 34, Color(0.95, 0.75, 0.3))
	sign_l.reparent(root, false)
	sign_l.position = Vector3(0, 2.35, 0.52)
	sign_l.rotation = Vector3.ZERO
	var u := BaseUsable.make(Vector3(1.3, 2.2, 1.0), "", _fortune)
	u.text_fn = func() -> String:
		var f: Variant = game.save.get("fortune", null)
		if f is Dictionary and not (f as Dictionary).is_empty():
			return "Madame Bonzo has already told your fortune for the next run"
		return "[E] Madame Bonzo: your fortune, %d tickets  (%d)" % [FORTUNE_COST, int(game.save.get("tickets", 0))]
	root.add_child(u)
	u.position = Vector3(0, 1.1, 0)


func _fortune(_p: Node) -> void:
	var save: Dictionary = game.save
	var f: Variant = save.get("fortune", null)
	if f is Dictionary and not (f as Dictionary).is_empty():
		game.event_banner("Madame Bonzo stares at you.\nOne card per run.")
		return
	if int(save.get("tickets", 0)) < FORTUNE_COST:
		game.event_banner("Madame Bonzo wants %d tickets." % FORTUNE_COST)
		return
	save.tickets = int(save.tickets) - FORTUNE_COST
	var total := 0
	for x: Array in FORTUNES:
		total += int(x[0])
	var roll := randi() % total
	var pick: Array = FORTUNES[0]
	for x: Array in FORTUNES:
		roll -= int(x[0])
		if roll < 0:
			pick = x
			break
	if pick[1] == "tickets":
		save.tickets = int(save.tickets) + int(pick[2])
		save.fortune = {kind = "nothing", value = "", text = "THE JACKPOT (paid)"}
	else:
		save.fortune = {kind = pick[1], value = pick[2], text = pick[3]}
	game.event_banner(pick[3])
	_booth_head.scale = Vector3.ONE * 1.15
	create_tween().tween_property(_booth_head, "scale", Vector3.ONE, 0.4)
	game.save_now()
	refresh()


func _armoury() -> void:
	# a wooden rack on the north wall, east of the door: the guns hang on
	# pegs; [E] on one to start runs holding it
	var z := -5.88
	solid(Vector3(4.8, 1.75, z + 0.04), Vector3(4.6, 2.3, 0.06), "planks_dark", false)
	_label("ARMOURY", Vector3(4.8, 3.1, z + 0.08), 0.0, 52, Color(0.95, 0.75, 0.3))
	for i in RACK.size():
		var at := Vector3(3.0 + i * 0.9, 1.9, z + 0.18)
		for dx: float in [-0.25, 0.25]:
			solid(at + Vector3(dx, -0.12, -0.08), Vector3(0.04, 0.04, 0.16), "brass", false)
		var holder := Node3D.new()
		add_child(holder)
		holder.position = at
		holder.rotation.z = PI * 0.5
		holder.scale = Vector3.ONE * 1.35
		_gun_model(holder, RACK[i])
		var lab := _label("", at + Vector3(0, -0.95, 0.0), 0.0, 30, Color.WHITE)
		_rack_labels.append(lab)
		var w: Dictionary = FpsPlayer.WEAPONS[RACK[i]]
		var u := BaseUsable.make(Vector3(0.7, 1.4, 0.4), "[E] Start runs holding the %s" % w.name, _pick_gun.bind(RACK[i]))
		add_child(u)
		u.position = at + Vector3(0, -0.2, 0.15)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.85, 0.65)
	spot.light_energy = 6.0
	spot.spot_range = 6.0
	spot.spot_angle = 40.0
	add_child(spot)
	spot.position = Vector3(4.8, 3.7, -3.4)
	spot.look_at(to_global(Vector3(4.8, 1.6, -5.9)), Vector3.UP)


func _pick_gun(_p: Node, w: int) -> void:
	game.save.start_weapon = w
	game.save_now()
	game.event_banner("You will start with the %s." % FpsPlayer.WEAPONS[w].name)
	refresh()


func _map_table() -> void:
	# the war-room table: a painted map of the funhouse front, pins and toy
	# clowns, a field telephone, and a board with the last few runs
	var top := 0.9
	solid(Vector3(0.6, top * 0.5, 0.6), Vector3(2.6, top, 1.5), "planks_dark")
	var map := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.4, 1.3)
	qm.orientation = PlaneMesh.FACE_Y
	map.mesh = qm
	map.material_override = LevelArt._mat("sunburst_faded")
	map.position = Vector3(0.6, top + 0.005, 0.6)
	add_child(map)
	var pin := StandardMaterial3D.new()
	pin.albedo_color = Color(0.8, 0.08, 0.06)
	for i in 9:
		_prim(self, "sphere", Vector3(0.03, 0.03, 0.03), Vector3(randf_range(-0.4, 1.6), top + 0.05, randf_range(0.1, 1.1)), pin)
	solid(Vector3(1.6, top + 0.08, 1.05), Vector3(0.22, 0.16, 0.16), "steel", false)        # field telephone
	solid(Vector3(-0.3, top + 0.02, 0.3), Vector3(0.3, 0.04, 0.22), "wood", false)        # a ledger
	# the board on an easel at the end of the table
	solid(Vector3(-1.4, 1.35, 0.6), Vector3(0.06, 1.3, 1.3), "planks_dark", false)
	for z: float in [0.05, 1.15]:
		beam(Vector3(-1.55, 0.0, z), Vector3(-1.42, 2.0, z), Vector2(0.05, 0.05), "wood", false)
	_history_label = _label("", Vector3(-1.36, 1.4, 0.6), PI * 0.5, 30, Color(0.92, 0.88, 0.8))
	bulb(Vector3(0.6, 2.4, 0.6), 2.0, 5.0, Color(1.0, 0.75, 0.45), true)


func _cot() -> void:
	# where you come round: an army cot by the west wall
	solid(Vector3(-6.4, 0.35, 4.2), Vector3(0.8, 0.1, 2.0), "cloth")
	for z: float in [3.3, 5.1]:
		solid(Vector3(-6.4, 0.17, z), Vector3(0.8, 0.34, 0.05), "iron", false)
	solid(Vector3(-6.4, 0.45, 4.95), Vector3(0.6, 0.12, 0.35), "cloth", false)


func _dressing() -> void:
	# sandbag walls, crates, a carousel horse's head on a pole, bunting,
	# posters and a gramophone
	for z: float in [-4.5, 2.0]:
		for k in 4:
			solid(Vector3(7.5, 0.18 + (k % 2) * 0.32, z + k * 0.45), Vector3(0.5, 0.3, 0.45), "sandbag")
	for p: Vector3 in [Vector3(-7.3, 0.4, -4.9), Vector3(-6.6, 0.4, -5.3), Vector3(-7.0, 1.2, -5.1), Vector3(2.0, 0.4, 5.3)]:
		solid(p, Vector3(0.8, 0.8, 0.8), "crate")
	# carousel horse: a painted head on a brass pole
	var pole := solid(Vector3(-3.0, 1.9, -4.6), Vector3(0.06, 3.8, 0.06), "brass", false)
	pole.name = "Pole"
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.88, 0.85, 0.78)
	var gold := LevelArt._mat("brass")
	_prim(self, "box", Vector3(0.22, 0.5, 0.9), Vector3(-3.0, 1.55, -4.6), white)
	_prim(self, "box", Vector3(0.2, 0.42, 0.22), Vector3(-3.0, 1.95, -4.15), white)
	_prim(self, "box", Vector3(0.16, 0.2, 0.32), Vector3(-3.0, 1.95, -3.95), white)
	_prim(self, "box", Vector3(0.24, 0.08, 0.6), Vector3(-3.0, 1.82, -4.6), gold)
	for i in 6:
		_prim(self, "box", Vector3(0.05, 0.1 + i * 0.01, 0.06), Vector3(-3.0, 2.15 - i * 0.05, -4.35 - i * 0.06), LevelArt._mat("cloth"))
	# posters
	for p: Array in [[Vector3(-7.94, 2.2, 2.5), PI * 0.5], [Vector3(2.5, 2.3, -5.94), 0.0], [Vector3(7.94, 2.1, 4.6), -PI * 0.5]]:
		var poster := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(0.9, 1.3)
		poster.mesh = pq
		poster.material_override = LevelArt._mat("poster")
		poster.position = p[0]
		poster.rotation.y = p[1]
		add_child(poster)
	# bunting across the ceiling
	for line: Array in [[Vector3(-7.8, 3.7, -5.8), Vector3(7.8, 3.7, 5.8)], [Vector3(-7.8, 3.7, 5.8), Vector3(7.8, 3.7, -5.8)]]:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		for i in 24:
			var t := (i + 0.5) / 24.0
			var flag := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(0.25, 0.3, 0.01)
			flag.mesh = fm
			flag.material_override = LevelArt._mat("pennant") if i % 2 == 0 else LevelArt._mat("harlequin_faded")
			flag.position = a.lerp(b, t) + Vector3.DOWN * (0.35 * sin(t * PI) + 0.15)
			flag.rotation = Vector3(PI, atan2(b.x - a.x, b.z - a.z) + PI * 0.5, 0)
			add_child(flag)
	# gramophone on a crate
	solid(Vector3(2.0, 0.85, 5.3), Vector3(0.4, 0.12, 0.4), "wood", false)
	var horn := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.24
	hm.bottom_radius = 0.03
	hm.height = 0.45
	horn.mesh = hm
	horn.material_override = gold
	horn.position = Vector3(2.0, 1.2, 5.15)
	horn.rotation.x = -0.9
	add_child(horn)


func _lights() -> void:
	# strings of fairground bulbs along the ceiling, warm, a few dead
	for z: float in [-3.5, 0.0, 3.5]:
		for x: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			var lit := randf() > 0.15
			bulb(Vector3(x, 3.75, z), 2.0 if lit else 0.0, 6.0, Color(1.0, 0.72, 0.45), lit and x == 0.0)


# --- helpers ----------------------------------------------------------------------------
func _label(text: String, pos: Vector3, yaw: float, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.rotation.y = yaw
	l.shaded = false
	l.double_sided = false
	add_child(l)
	return l


func _prim(parent: Node3D, kind: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	match kind:
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			mi.mesh = s
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			mi.mesh = c
		_:
			mi.mesh = BoxMesh.new()
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


func _metal(c: Color, rough := 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.9
	m.roughness = rough
	return m


## What stands on a trophy plaque.
func _trophy_model(h: Node3D, kind: String) -> void:
	var gold := _metal(Color(0.85, 0.65, 0.2))
	var silver := _metal(Color(0.75, 0.75, 0.78))
	var bronze := _metal(Color(0.6, 0.35, 0.18), 0.4)
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.82, 0.76, 0.62)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.05, 0.04)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.1)
	match kind:
		"cup_gold", "cup_silver", "cup_bronze":
			var m: Material = gold if kind == "cup_gold" else (silver if kind == "cup_silver" else bronze)
			_prim(h, "cyl", Vector3(0.14, 0.04, 0.14), Vector3(0, 0.02, 0), m)
			_prim(h, "cyl", Vector3(0.04, 0.1, 0.04), Vector3(0, 0.09, 0), m)
			_prim(h, "sphere", Vector3(0.2, 0.2, 0.2), Vector3(0, 0.22, 0), m)
			for x: float in [-0.12, 0.12]:
				_prim(h, "box", Vector3(0.03, 0.1, 0.03), Vector3(x, 0.24, 0), m)
		"nose":
			_prim(h, "cyl", Vector3(0.1, 0.04, 0.1), Vector3(0, 0.02, 0), gold)
			_prim(h, "sphere", Vector3(0.13, 0.13, 0.13), Vector3(0, 0.11, 0), red)
		"skull":
			_prim(h, "sphere", Vector3(0.17, 0.17, 0.19), Vector3(0, 0.12, 0), bone)
			_prim(h, "box", Vector3(0.12, 0.05, 0.1), Vector3(0, 0.03, 0.03), bone)
			for x: float in [-0.04, 0.04]:
				_prim(h, "sphere", Vector3(0.045, 0.045, 0.03), Vector3(x, 0.13, -0.085), dark)
		"drum":
			_prim(h, "cyl", Vector3(0.16, 0.24, 0.16), Vector3(0, 0.12, 0), LevelArt._mat("barrel"))
		"stake":
			var b := _prim(h, "cyl", Vector3(0.035, 0.4, 0.035), Vector3(0, 0.14, 0), LevelArt._mat("wood"))
			b.rotation.z = 1.1
			_prim(h, "box", Vector3(0.05, 0.05, 0.05), Vector3(0.18, 0.22, 0), red)
		"mask":
			_prim(h, "sphere", Vector3(0.16, 0.2, 0.15), Vector3(0, 0.14, 0), dark)
			for x: float in [-0.04, 0.04]:
				_prim(h, "sphere", Vector3(0.05, 0.05, 0.03), Vector3(x, 0.17, -0.07), _metal(Color(0.3, 0.4, 0.35), 0.2))
			_prim(h, "cyl", Vector3(0.07, 0.08, 0.07), Vector3(0, 0.06, -0.07), silver)
		"bone":
			var b := _prim(h, "cyl", Vector3(0.04, 0.32, 0.04), Vector3(0, 0.05, 0), bone)
			b.rotation.z = PI * 0.5
			for x: float in [-0.17, 0.17]:
				_prim(h, "sphere", Vector3(0.07, 0.07, 0.07), Vector3(x, 0.05, 0), bone)
		"ring":
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.05
			tm.outer_radius = 0.1
			t.mesh = tm
			t.material_override = gold
			t.position = Vector3(0, 0.12, 0)
			t.rotation.x = PI * 0.5
			h.add_child(t)
		"pin":
			_prim(h, "sphere", Vector3(0.11, 0.2, 0.11), Vector3(0, 0.1, 0), bone)
			_prim(h, "sphere", Vector3(0.07, 0.1, 0.07), Vector3(0, 0.25, 0), bone)
			_prim(h, "cyl", Vector3(0.075, 0.02, 0.075), Vector3(0, 0.2, 0), red)
		"plate":
			_prim(h, "cyl", Vector3(0.24, 0.015, 0.24), Vector3(0, 0.01, 0), bone)
			_prim(h, "sphere", Vector3(0.09, 0.05, 0.12), Vector3(0, 0.04, 0), red)
		_:
			var m: Material = gold if kind == "medal_gold" else (silver if kind == "medal_silver" else bronze)
			_prim(h, "box", Vector3(0.06, 0.16, 0.01), Vector3(0, 0.25, 0), red)
			var d := _prim(h, "cyl", Vector3(0.14, 0.02, 0.14), Vector3(0, 0.12, 0), m)
			d.rotation.x = PI * 0.5


## A rough model of each gun for the rack, barrel along +Y (hung on its side).
func _gun_model(h: Node3D, w: int) -> void:
	var steel := _metal(Color(0.12, 0.12, 0.13), 0.4)
	var wood := LevelArt._mat("wood")
	var brass := _metal(Color(0.55, 0.42, 0.18))
	match w:
		0:
			_prim(h, "box", Vector3(0.04, 0.24, 0.05), Vector3(0, 0.08, 0), steel)
			_prim(h, "box", Vector3(0.035, 0.05, 0.12), Vector3(0, -0.05, -0.05), wood)
		1:
			_prim(h, "cyl", Vector3(0.03, 0.62, 0.03), Vector3(0, 0.2, 0.0), steel)
			_prim(h, "cyl", Vector3(0.035, 0.25, 0.035), Vector3(0, 0.12, -0.03), wood)
			_prim(h, "box", Vector3(0.05, 0.3, 0.09), Vector3(0, -0.22, -0.02), wood)
		2:
			_prim(h, "cyl", Vector3(0.04, 0.32, 0.04), Vector3(0, 0.15, 0), steel)
			_prim(h, "box", Vector3(0.03, 0.18, 0.04), Vector3(0.05, 0.05, 0), steel)
			_prim(h, "box", Vector3(0.045, 0.24, 0.08), Vector3(0, -0.18, -0.02), wood)
		3:
			_prim(h, "box", Vector3(0.05, 0.55, 0.03), Vector3(0, 0.15, 0), steel)
			_prim(h, "cyl", Vector3(0.06, 0.32, 0.06), Vector3(0, 0.05, -0.05), brass)
			_prim(h, "box", Vector3(0.045, 0.25, 0.08), Vector3(0, -0.25, -0.03), wood)
		_:
			_prim(h, "cyl", Vector3(0.02, 0.7, 0.02), Vector3(0, 0.3, 0.0), steel)
			_prim(h, "box", Vector3(0.04, 0.75, 0.05), Vector3(0, 0.0, -0.02), wood)
			_prim(h, "box", Vector3(0.045, 0.22, 0.1), Vector3(0, -0.45, -0.04), wood)
