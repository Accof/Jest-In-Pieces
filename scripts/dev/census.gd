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
		# the heaviest things: triangles per frame = instances x mesh triangles (shadow passes multiply it again)
		var heavy: Array = []
		var stack2: Array = [game._world]
		while not stack2.is_empty():
			var n2: Node = stack2.pop_back()
			stack2.append_array(n2.get_children())
			var mesh: Mesh = null
			var inst := 1
			if n2 is MultiMeshInstance3D and (n2 as MultiMeshInstance3D).multimesh:
				var mmr := (n2 as MultiMeshInstance3D).multimesh
				mesh = mmr.mesh
				inst = mmr.visible_instance_count if mmr.visible_instance_count >= 0 else mmr.instance_count
			elif n2 is MeshInstance3D:
				mesh = (n2 as MeshInstance3D).mesh
			if mesh == null:
				continue
			var tris := 0
			for s2 in mesh.get_surface_count():
				var arr2 := mesh.surface_get_arrays(s2)
				if arr2.size() > Mesh.ARRAY_INDEX and arr2[Mesh.ARRAY_INDEX] != null and arr2[Mesh.ARRAY_INDEX].size() > 0:
					tris += arr2[Mesh.ARRAY_INDEX].size() / 3
				elif arr2.size() > 0 and arr2[Mesh.ARRAY_VERTEX] != null:
					tris += arr2[Mesh.ARRAY_VERTEX].size() / 3
			var casts: bool = (n2 as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			heavy.append([tris * inst, n2.name, inst, tris, casts, mesh.get_class()])
		heavy.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var total := 0
		var total_cast := 0
		for h: Array in heavy:
			total += h[0]
			if h[4]:
				total_cast += h[0]
		print("   triangles in the world: %dk total, %dk of them casting shadows. Heaviest:" % [total / 1000, total_cast / 1000])
		for h: Array in heavy.slice(0, 18):
			print("      %7dk  %-28s x%-6d %6d tris each  %s  %s" % [h[0] / 1000, h[1], h[2], h[3], "shadows" if h[4] else "no-shadow", h[5]])
		# the lights, one line each when there are few
		if lights <= 24:
			var st3: Array = [game._world]
			while not st3.is_empty():
				var n3: Node = st3.pop_back()
				st3.append_array(n3.get_children())
				if n3 is OmniLight3D:
					var o := n3 as OmniLight3D
					print("      light %-22s parent %-18s range %5.1f energy %4.1f shadows %s fog %.1f at %s" % [o.name, o.get_parent().name, o.omni_range, o.light_energy, "YES" if o.shadow_enabled else "no", o.light_volumetric_fog_energy, o.global_position.snapped(Vector3.ONE)])
				elif n3 is SpotLight3D:
					var sp := n3 as SpotLight3D
					print("      spot  %-22s parent %-18s range %5.1f shadows %s" % [sp.name, sp.get_parent().name, sp.spot_range, "YES" if sp.shadow_enabled else "no"])
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
