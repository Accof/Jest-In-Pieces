extends Node3D
## Does anything survive a floor? Walks a run floor by floor, lets each floor
## live for a while with the player shooting and enemies dying, then prints
## what the engine is holding: nodes, orphans, objects, resources, physics
## bodies, and the child counts of everything that outlives a floor (the
## tree root, the autoloads, the player, the game node). Growth from floor to
## floor is a leak.
##   godot --headless --fixed-fps 60 res://scenes/leak_probe.tscn [-- floors=8 live=240 quiet]

var game: Node3D
var floors := 8
var live := 240
var quiet := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("floors="):
			floors = int(a.substr(7))
		elif a.begins_with("live="):
			live = int(a.substr(5))
		elif a == "quiet":
			quiet = true
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + _count(ch)
	return c


func _report(label: String) -> Dictionary:
	var root := get_tree().root
	var d := {
		label = label,
		nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		objects = Performance.get_monitor(Performance.OBJECT_COUNT),
		resources = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		phys = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		mem_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	# who outlives a floor, and how big they have grown
	var holders := {}
	for ch in root.get_children():
		if ch == self:
			continue
		holders[ch.name] = _count(ch)
	if game:
		for ch in game.get_children():
			if ch.name != "" and not (ch.is_in_group(&"world_root")):
				holders["Game/" + str(ch.name)] = _count(ch)
		if is_instance_valid(game.player):
			holders["Game/Player"] = _count(game.player)
	d.holders = holders
	return d


func _run() -> void:
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(1)
	seed(1916)
	game.rng.seed = 1916
	game.start_run()
	FpsPlayer.god_mode = true
	var reports: Array = []
	reports.append(_report("start"))
	for f in floors:
		game.next_floor()
		await _frames(5)
		# live a little: the player fires at the floor and at enemies, enemies die
		var pl: FpsPlayer = game.player
		for i in live:
			await get_tree().physics_frame
			if i % 6 == 0 and is_instance_valid(pl):
				var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.RIFLE]
				var dir := Vector3(randf_range(-0.6, 0.6), randf_range(-0.7, 0.1), -1.0).normalized()
				pl.shoot_ray(pl.global_position + Vector3.UP * 1.5, pl.global_basis * dir, w, i)
			if i % 40 == 0:
				for c: Clown in game.clowns:
					if not c.dead and randf() < 0.3:
						var chest: PhysicalBone3D = c.ragdoll.bones.get(&"Chest")
						if chest:
							c.hit({collider = chest, position = c.global_position + Vector3.UP * 1.2, direction = Vector3.FORWARD, damage = 400.0, impulse = 6.0, shot_id = i, weapon = "Rifle", dist = 10.0})
						break
			if i % 50 == 25 and game.maze is TrenchMaze:
				Explosion.detonate(game._world, pl.global_position + pl.global_basis * Vector3(0, 0.5, -8.0), "grenade")
		await _frames(30)
		var r := _report("floor %d (%s)" % [game.floor_number, "Front" if game.maze is FrontMaze else ("trench" if game.maze is TrenchMaze else "bunker")])
		reports.append(r)
		if not quiet:
			print("%-20s nodes %5d  orphans %4d  objects %6d  resources %5d  phys %4d  mem %.0f MB" % [r.label, r.nodes, r.orphans, r.objects, r.resources, r.phys, r.mem_mb])
	# the growth
	print("\nLEAK PROBE: holders that grew across floors (children counted recursively)")
	var first: Dictionary = reports[1].holders
	var last: Dictionary = reports[reports.size() - 1].holders
	var keys := last.keys()
	keys.sort()
	for k in keys:
		var a: int = int(first.get(k, 0))
		var b: int = int(last.get(k, 0))
		var row := "   %-28s" % k
		for r: Dictionary in reports.slice(1):
			row += " %5d" % int(r.holders.get(k, 0))
		print(row + ("   <-- GROWS" if b > a + 5 else ""))
	var n0: int = reports[1].nodes
	var n1: int = reports[reports.size() - 1].nodes
	print("   nodes %d -> %d, orphans %d -> %d, objects %d -> %d, resources %d -> %d, physics %d -> %d" % [n0, n1, reports[1].orphans, reports[reports.size() - 1].orphans, reports[1].objects, reports[reports.size() - 1].objects, reports[1].resources, reports[reports.size() - 1].resources, reports[1].phys, reports[reports.size() - 1].phys])
	get_tree().quit()
