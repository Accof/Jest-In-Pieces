extends Node
## The Drowned Front, straight in: a run started on its first trench floor
## (Operation Drowned Front, Milestone 2: two trench systems across No Man's
## Land, SURVIVAL, the H.Q. in the enemy's rear).
##
##   godot --path . res://scenes/play_front.tscn -- [seed=N] [floor=N] [god] [perf=SECONDS]
##
## `floor=` picks the floor number it is played as (3 by default: the first
## trench floor of a run); `seed=` fixes the layout; `god` god mode; `perf=30`
## prints frame-time summaries every 30 s (scripts/dev/frame_probe.gd). The
## real save is untouched (test_save).

var game: Node


func _ready() -> void:
	var seed_ := 0
	var floor_ := 3
	var perf := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_ = int(a.substr(5))
		elif a.begins_with("perf="):
			perf = float(a.substr(5))
		elif a.begins_with("floor="):
			floor_ = int(a.substr(6))
		elif a == "god":
			FpsPlayer.god_mode = true
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.trench_every = maxi(floor_, 1)            # so floor `floor_` is a trench floor
	game.survival_trenches = true
	game.start_run()
	if seed_ != 0:
		game.rng.seed = seed_
	game.floor_number = floor_ - 1
	game.next_floor()
	var kind: String = "FrontMaze" if game.maze is FrontMaze else ("TrenchMaze" if game.maze is TrenchMaze else str(game.maze.get_class()))
	print("Drowned Front: floor %d, %s, %d enemies, seed %s, objective %s" % [game.floor_number, kind, game.clowns.size(), str(seed_) if seed_ != 0 else "random", ("SURVIVAL" if game.objective == 1 else "ELIMINATION")])
	if perf > 0.0:
		var probe: Node = load("res://scripts/dev/frame_probe.gd").new()
		probe.seconds = perf
		probe.label = "Drowned Front floor %d seed %s" % [game.floor_number, str(seed_) if seed_ != 0 else "random"]
		add_child(probe)
	if OS.has_environment("LEGACY_QUIT_AFTER"):
		# a headless smoke test: build it, stand in it a moment, leave
		await get_tree().create_timer(float(OS.get_environment("LEGACY_QUIT_AFTER"))).timeout
		print("Drowned Front: ok (%s)" % ("front" if game.maze is FrontMaze else "NOT THE FRONT"))
		get_tree().quit(0 if game.maze is FrontMaze else 1)
