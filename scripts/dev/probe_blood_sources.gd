extends Node
## Headless probe (25 Nov): who fires the blood on a revolver body shot? Shoots
## each sandbox clown in the chest with the revolver until it dies, then
## watches 6 s, logging every plume (Blood._burst) with its caller, and the
## decals and droplets spent. Run:
##   godot --headless --fixed-fps 60 --path . res://scenes/probe_blood_sources.tscn

var _log: Array = []

func _ready() -> void:
	_run()

func _run() -> void:
	var scene: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(scene)
	for i in 5:
		await get_tree().physics_frame
	var player: FpsPlayer = scene.player
	var blood: Node = get_node("/root/Blood")
	blood.probe = Callable(self, "_on_burst")
	var w: Dictionary = {}
	for ww: Dictionary in FpsPlayer.WEAPONS:
		if ww.name == "Revolver":
			w = ww
	var shots_total := 0
	for ci in mini(scene.clowns.size(), 6):
		var c: Clown = scene.clowns[ci]
		var zones := ["chest", "chest", "chest", "chest", "belly", "left thigh"]
		var zone: String = zones[ci]
		var off := Vector3(0, 1.35, 0) if zone == "chest" else (Vector3(0, 1.05, 0) if zone == "belly" else Vector3(0.1, 0.75, 0))
		var target: Vector3 = c.global_position + off
		var from := target + Vector3(0.0, 0.25, 3.0)
		print("\n== clown %d, revolver to the %s ==" % [ci, zone])
		var shots := 0
		while not c.dead and shots < 6:
			_log.clear()
			var d0: int = blood._decals.filter(func(d): return d.visible).size()
			var dr0: int = blood._drop_pos.size()
			var sp0: int = blood.sprays
			player.shoot_ray(from, (target - from).normalized(), w, 500 + ci * 10 + shots)
			shots += 1
			shots_total += 1
			for f in 3:
				await get_tree().physics_frame
			var d1: int = blood._decals.filter(func(d): return d.visible).size()
			print("  shot %d: health=%.0f dead=%s  plumes=%d  decals+%d  droplets+%d" % [shots, c.health, c.dead, blood.sprays - sp0, d1 - d0, blood._drop_pos.size() - dr0])
			for e in _log:
				print("     plume tier=%s amount=%.2f  from %s" % [e.tier, e.amount, e.who])
		# the death playing out
		_log.clear()
		var sp1: int = blood.sprays
		var d2: int = blood._decals.filter(func(d): return d.visible).size()
		for f in 360:
			await get_tree().physics_frame
		var d3: int = blood._decals.filter(func(d): return d.visible).size()
		print("  6 s after: plumes=%d  decals+%d  throat=%s" % [blood.sprays - sp1, d3 - d2, c.throat_death])
		var by := {}
		for e in _log:
			by[e.who] = by.get(e.who, 0) + 1
		for k in by:
			print("     %d x %s" % [by[k], k])
	print("\nshots in all: %d" % shots_total)
	get_tree().quit()


func _on_burst(tier: String, amount: float) -> void:
	var who := "?"
	var st := get_stack()
	# the first frame outside blood_manager
	for fr in st:
		var src: String = fr.source
		if not src.contains("blood_manager") and not src.contains("probe_blood"):
			who = "%s:%d %s" % [src.get_file(), fr.line, fr.function]
			break
	_log.append({tier = tier, amount = amount, who = who})
