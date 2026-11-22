extends Node
## The legacy Drowned Trenches, playable on their own: the trench floor as it
## was before Operation Drowned Front (archive/legacy_drowned_trenches).
##
##   godot --path . res://scenes/legacy_drowned_trenches.tscn -- [seed=N] [floor=N] [god] [perf=SECONDS]
##
## Starts a run straight onto a trench floor with the game's own trench
## generator (TrenchMaze, TrenchArt, TrenchBattle...), the real save untouched
## (test_save). `floor=` picks which floor number it is played as (3 by
## default: the first trench floor of a run, with its enemy count and
## shares); `seed=` fixes the layout; `god` turns god mode on; `perf=30`
## prints frame-time summaries every 30 s of play (scripts/dev/frame_probe.gd:
## the way to record the real baseline on the target machine).
##
## This scene plays whatever TrenchMaze and its friends are in the tree now.
## While they are the legacy classes (the plan keeps them; the new front gets
## classes of its own) this IS the legacy level. If they are ever changed, the
## byte-exact copies in archive/legacy_drowned_trenches/snapshot/ and its
## RESTORE.md bring the originals back; verify with the archive's check.sh.

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
	game.survival_trenches = false                 # the old rule: every enemy must die before the exit opens
	game.start_run()
	if seed_ != 0:
		game.rng.seed = seed_
	game.floor_number = floor_ - 1
	game.next_floor()
	var kind: String = "TrenchMaze" if game.maze is TrenchMaze else str(game.maze.get_class())
	print("legacy Drowned Trenches: floor %d, %s, %d enemies, seed %s, objective %s" % [game.floor_number, kind, game.clowns.size(), str(seed_) if seed_ != 0 else "random", ("SURVIVAL" if game.objective == 1 else "ELIMINATION")])
	if perf > 0.0:
		var probe: Node = load("res://scripts/dev/frame_probe.gd").new()
		probe.seconds = perf
		probe.label = "legacy trench floor %d seed %s" % [game.floor_number, str(seed_) if seed_ != 0 else "random"]
		add_child(probe)
	if OS.has_environment("LEGACY_QUIT_AFTER"):
		# a headless smoke test: build it, stand in it a moment, leave
		await get_tree().create_timer(float(OS.get_environment("LEGACY_QUIT_AFTER"))).timeout
		print("legacy Drowned Trenches: ok (%s)" % ("trench" if game.maze is TrenchMaze else "NOT A TRENCH"))
		get_tree().quit(0 if game.maze is TrenchMaze else 1)
