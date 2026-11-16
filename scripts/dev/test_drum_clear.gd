extends Node
## Fuel drums must stand clear: nothing solid inside the drum, and no
## level dressing (multimesh pieces) with its centre inside it.
func _ready() -> void:
	Engine.set_meta(&"test_save", true)
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var drums := 0
	var bad := 0
	var hits := {}
	for fl in 12:
		game.start_run()
		game.floor_number = 2 + fl
		game.next_floor()
		for i in 4:
			await get_tree().physics_frame
		var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var cyl := CylinderShape3D.new(); cyl.radius = ExplosiveBarrel.RADIUS - 0.02; cyl.height = ExplosiveBarrel.HEIGHT - 0.06
		q.shape = cyl
		q.collision_mask = 1
		for b: ExplosiveBarrel in game.get_tree().get_nodes_in_group(&"barrels"):
			drums += 1
			q.transform = Transform3D(Basis.IDENTITY, b.global_position + Vector3.UP * ExplosiveBarrel.HEIGHT * 0.5)
			q.exclude = [b.get_rid()]
			var res := space.intersect_shape(q, 8)
			var what := []
			for r in res:
				var o: Node = r.collider
				var desc := "?"
				if o is CollisionObject3D:
					var owner_id := (o as CollisionObject3D).shape_find_owner(r.shape)
					var sh := (o as CollisionObject3D).shape_owner_get_shape(owner_id, 0)
					var xf := (o as CollisionObject3D).shape_owner_get_transform(owner_id)
					var sz = sh.size if sh is BoxShape3D else (sh.get_class())
					desc = "%s/%s %s at %s (drum %s) parent=%s" % [o.get_class(), o.get_script().get_global_name() if o.get_script() else "", sz, (o as Node3D).global_transform * xf.origin, b.global_position, o.get_parent().name]
				what.append(o.get_class())
			for t in game.get_tree().get_nodes_in_group(&"mess_tables"):
				if (t as Node3D).global_position.distance_to(b.global_position) < 1.5:
					what.append("mess_table")
			if not what.is_empty():
				bad += 1
				for w in what:
					hits[w] = hits.get(w, 0) + 1
	print("DRUMS: %d of %d clip something  %s" % [bad, drums, hits])
	get_tree().quit()
