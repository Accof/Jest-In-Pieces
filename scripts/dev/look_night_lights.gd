extends Node3D
## Dev: the Front's lanterns and fires (FrontLights) by night or dawn:
## captures from inside our trench by a lantern, from the ramp head across
## No Man's Land, and beside a brazier.
##   godot --path . res://scenes/look_night_lights.tscn -- [light=night|dawn] [seed=N] [tag=x]
## Writes /tmp/nlights_<tag>_<view>.png and prints the counts.

var tag := "night"
var light := "night"
var seed_ := 1916
var game: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("light="):
			light = a.substr(6)
			tag = light
		elif a.begins_with("seed="):
			seed_ = int(a.substr(5))
		elif a.begins_with("tag="):
			tag = a.substr(4)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	Engine.set_meta(&"test_save", true)
	FrontVariant.forced = FrontVariant.Kind.BASE
	FrontVariant.forced_light = FrontVariant.light_from_name(light)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(1)
	seed(seed_)
	game.rng.seed = seed_
	game.start_run()
	FpsPlayer.god_mode = true
	game.floor_number = 2          # next_floor() makes floor 3: the Front
	game.next_floor()
	await _frames(5)
	if game.director:
		game.director.auto_events = false
	var m: FrontMaze = game.maze as FrontMaze
	if m == null:
		print("LIGHTS: not a Front floor")
		get_tree().quit()
		return
	var art: FrontArt = m.find_child("Art", true, false) as FrontArt
	var fl: FrontLights = art.lights
	print("LIGHTS: %d lanterns, %d braziers, %d wreck fires (%s)" % [fl.lanterns if fl else 0, fl.braziers if fl else 0, fl.wreck_fires if fl else 0, light])
	var p: FpsPlayer = game.player
	# 1. in our trench, looking along it toward the nearest lantern
	var lamps: Array = []
	for e: Array in fl._lights:
		if e[3] == "lantern":
			lamps.append((e[0] as OmniLight3D).global_position)
	var start: Vector3 = p.global_position
	lamps.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(start) < b.distance_to(start))
	if not lamps.is_empty():
		var l: Vector3 = lamps[0]
		var cell := m.cell_of(l)
		var stand := m.cell_center(cell)
		# four metres back along the trench if there is trench there
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if m.open_cells.has(cell + d * 2):
				stand = m.cell_center(cell + d * 2)
				break
		stand.y = m.floor_height(stand) + 0.1
		p.global_position = stand
		_look(p, l)
		await _frames(25)
		_shot("trench")
	# 2. the ramp head, across No Man's Land
	var head := Vector3.INF
	for r: Dictionary in m.assault_ramps:
		if r.dir.y == -1:
			head = Vector3(r.head.x, 0, r.head.y - 1.5)
			break
	if head != Vector3.INF:
		head.y = m.floor_height(head) + 0.1
		p.global_position = head
		p.rotation.y = 0.0
		p.camera.rotation.x = deg_to_rad(4.0)
		await _frames(25)
		_shot("field")
	# 3. beside a brazier
	var fires: Array = []
	for e: Array in fl._lights:
		if e[3] == "brazier":
			fires.append((e[0] as OmniLight3D).global_position)
	if not fires.is_empty():
		var f: Vector3 = fires[0]
		var cell := m.cell_of(f)
		var stand := m.cell_center(cell)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if m.open_cells.has(cell + d):
				stand = m.cell_center(cell + d)
				break
		stand.y = m.floor_height(stand) + 0.1
		p.global_position = stand
		_look(p, f - Vector3.UP * 0.7)
		await _frames(25)
		_shot("brazier")
	# 4. a wreck fire, from six metres
	var wrecks: Array = []
	for e: Array in fl._lights:
		if e[3] == "wreck":
			wrecks.append((e[0] as OmniLight3D).global_position)
	if not wrecks.is_empty():
		var f: Vector3 = wrecks[0]
		var stand := f + Vector3(0, 0, 6.0)
		stand.y = m.ground_height(stand.x, stand.z) + 0.1
		p.global_position = stand
		_look(p, f - Vector3.UP * 0.9)
		await _frames(25)
		_shot("wreck")
	get_tree().quit()


func _look(p: FpsPlayer, at: Vector3) -> void:
	var eye: Vector3 = p.global_position + Vector3.UP * 1.6
	var d := at - eye
	p.rotation.y = atan2(-d.x, -d.z)
	p.camera.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(view: String) -> void:
	get_viewport().get_texture().get_image().save_png("/tmp/nlights_%s_%s.png" % [tag, view])
	print("shot ", view)
