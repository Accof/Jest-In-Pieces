extends Node
## The Drowned Front, straight in: a run started on its first trench floor
## (Operation Drowned Front, Milestone 2: two trench systems across No Man's
## Land, SURVIVAL, the H.Q. in the enemy's rear).
##
##   godot --path . res://scenes/play_front.tscn -- [seed=N] [variant=base|smoke|barrage|mg|flare] [floor=N] [god] [perf=SECONDS]
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
	var bunker := false
	var knobs: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_ = int(a.substr(5))
		elif a.begins_with("variant="):
			FrontVariant.forced = FrontVariant.from_name(a.substr(8))
		elif a.begins_with("perf="):
			perf = float(a.substr(5))
		elif a.begins_with("floor="):
			floor_ = int(a.substr(6))
		elif a == "god":
			FpsPlayer.god_mode = true
		elif a == "bunker":
			bunker = true                       # play floor_ as a bunker instead (perf comparisons)
		elif a == "noshadows" or a == "nopost" or a == "nofog" or a.begins_with("scale=") or a.begins_with("fsr1=") or a.begins_with("fogsize=") or a == "nossil":
			knobs.append(a)                     # perf experiments, applied after the floor is built
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.trench_every = 1000 if bunker else maxi(floor_, 1)            # so floor `floor_` is a trench floor (or never, for a bunker)
	game.survival_trenches = true
	game.start_run()
	if seed_ != 0:
		game.rng.seed = seed_
	game.floor_number = floor_ - 1
	game.next_floor()
	var kind: String = "FrontMaze" if game.maze is FrontMaze else ("TrenchMaze" if game.maze is TrenchMaze else str(game.maze.get_class()))
	print("Drowned Front: floor %d, %s, %d enemies, seed %s, objective %s" % [game.floor_number, kind, game.clowns.size(), str(seed_) if seed_ != 0 else "random", ("SURVIVAL" if game.objective == 1 else "ELIMINATION")])
	# perf experiments: knock one thing out at a time and read the frame probe
	for k in knobs:
		if k == "noshadows":
			for n in get_tree().get_nodes_in_group(&"world_root") + [game._world]:
				_walk(n, func(x: Node) -> void:
					if x is Light3D:
						(x as Light3D).shadow_enabled = false)
			print("PERF knob: every light's shadows off")
		elif k == "nopost":
			var env: Environment = game._world_env.environment
			env.ssr_enabled = false
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.glow_enabled = false
			env.sdfgi_enabled = false
			print("PERF knob: SSR, SSAO, SSIL, glow, SDFGI off")
		elif k == "nofog":
			game._world_env.environment.volumetric_fog_enabled = false
			print("PERF knob: volumetric fog off")
		elif k.begins_with("scale="):
			var sc := float(k.substr(6))
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			get_viewport().scaling_3d_scale = sc
			print("PERF knob: 3D render scale %.2f (FSR 2)" % sc)
		elif k.begins_with("fsr1="):
			var sc := float(k.substr(5))
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			get_viewport().scaling_3d_scale = sc
			print("PERF knob: 3D render scale %.2f (FSR 1)" % sc)
		elif k.begins_with("fogsize="):
			var fs := int(k.substr(8))
			RenderingServer.environment_set_volumetric_fog_volume_size(fs, fs)
			print("PERF knob: volumetric fog volume %d x %d x %d (default 64)" % [fs, fs, fs])
		elif k == "nossil":
			game._world_env.environment.ssil_enabled = false
			print("PERF knob: SSIL off")
	if perf > 0.0:
		var probe: Node = load("res://scripts/dev/frame_probe.gd").new()
		probe.seconds = perf
		for a in OS.get_cmdline_user_args():
			if a.begins_with("warmup="):
				probe.warmup = float(a.substr(7))
		probe.label = "Drowned Front floor %d seed %s" % [game.floor_number, str(seed_) if seed_ != 0 else "random"]
		add_child(probe)
	if OS.has_environment("LEGACY_QUIT_AFTER"):
		# a headless smoke test: build it, stand in it a moment, leave
		await get_tree().create_timer(float(OS.get_environment("LEGACY_QUIT_AFTER"))).timeout
		print("Drowned Front: ok (%s)" % ("front" if game.maze is FrontMaze else "NOT THE FRONT"))
		get_tree().quit(0 if game.maze is FrontMaze else 1)


func _walk(n: Node, f: Callable) -> void:
	f.call(n)
	for c in n.get_children():
		_walk(c, f)
