extends Node3D
## Dev: a census of a floor - what is in the world by node class, lights with
## shadows, mesh instances vs multimeshes, particles. For finding the cost.
##   godot --headless --fixed-fps 60 res://scenes/census.tscn -- floors=2,3,8
var game: Node3D
func _ready() -> void:
	_run()
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _run() -> void:
	var floors: Array = [2, 3, 8]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("floors="):
			floors = Array(a.substr(7).split(",")).map(func(x: String) -> int: return int(x))
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(1)
	seed(1916)
	game.rng.seed = 1916
	game.start_run()
	FpsPlayer.god_mode = true
	var at := 0
	for f: int in floors:
		while at < f:
			at += 1
			game.next_floor()
			await _frames(3)
		await _frames(20)
		var by := {}
		var shadow_lights := 0
		var lights := 0
		var mi := 0
		var mi_tris := 0
		var mm := 0
		var mm_inst := 0
		var parts := 0
		var part_amount := 0
		var decals := 0
		var bones := 0
		var stack: Array = [game._world]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var cls := n.get_class()
			by[cls] = int(by.get(cls, 0)) + 1
			if n is Light3D:
				lights += 1
				if (n as Light3D).shadow_enabled:
					shadow_lights += 1
			elif n is MultiMeshInstance3D:
				mm += 1
				if (n as MultiMeshInstance3D).multimesh:
					mm_inst += (n as MultiMeshInstance3D).multimesh.visible_instance_count if (n as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (n as MultiMeshInstance3D).multimesh.instance_count
			elif n is MeshInstance3D:
				mi += 1
				var m := (n as MeshInstance3D).mesh
				if m:
					for s in m.get_surface_count():
						var arr := m.surface_get_arrays(s)
						if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null and arr[Mesh.ARRAY_INDEX].size() > 0:
							mi_tris += arr[Mesh.ARRAY_INDEX].size() / 3
						elif arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
							mi_tris += arr[Mesh.ARRAY_VERTEX].size() / 3
			elif n is GPUParticles3D or n is CPUParticles3D:
				parts += 1
				part_amount += n.amount
			elif n is Decal:
				decals += 1
			elif n is PhysicalBone3D:
				bones += 1
		var kind := "Front" if game.maze is FrontMaze else ("trench" if game.maze is TrenchMaze else "bunker")
		print("CENSUS floor %d (%s): %d enemies | lights %d (%d with shadows) | MeshInstance3D %d (%dk tris) | MultiMesh %d (%d instances) | particles %d (%d quads) | decals %d | physical bones %d" % [
			game.floor_number, kind, game.clowns.size(), lights, shadow_lights, mi, mi_tris / 1000, mm, mm_inst, parts, part_amount, decals, bones])
		var keys := by.keys()
		keys.sort_custom(func(a, b): return by[a] > by[b])
		var row := "   top classes:"
		for k in keys.slice(0, 14):
			row += " %s %d," % [k, by[k]]
		print(row)
	get_tree().quit()
