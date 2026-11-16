extends Node
## Renders a WitzSoldat from the side in a few states (walk, run, aim while
## walking, standing carry) to /tmp/pose_*.png, and prints the crouch and arm
## stretch numbers. Needs a window (xvfb).

var soldier: Clown
var game: Node3D
var speed := 0.0
var dir := Vector3.FORWARD


func _ready() -> void:
	_run()


func _physics_process(delta: float) -> void:
	if soldier and speed > 0.0:
		soldier.velocity = dir * speed          # feet follow velocity; the body stays put for the camera


func _run() -> void:
	game = _test_game_scene().instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.start_run()
	await get_tree().physics_frame
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns = [] as Array[Clown]
	var m: Maze = game.maze
	var a: Vector3 = m.cell_center(m.route[2])
	soldier = Clown.new()
	soldier.body = "witzsoldat"
	game._world.add_child(soldier)
	soldier.give_rifle()
	soldier.always_pose = true
	soldier.set_process(true)
	var p: FpsPlayer = game.player
	var states := [
		["stand", 0.0, 0.0, 0.0],
		["walk", 1.6, 0.0, 0.0],
		["run", 5.0, 1.0, 0.0],
		["walk_aim", 1.6, 0.0, 1.0],
		["stand_aim", 0.0, 0.0, 1.0],
		["lunge", 0.0, 0.0, 0.0],
	]
	for s: Array in states:
		soldier.global_position = Vector3(a.x, m.floor_height(a), a.z)
		soldier.rotation.y = 0.0
		dir = soldier.global_basis.z
		speed = float(s[1])
		soldier.walk_amount = 1.0 if speed > 0.0 else 0.0
		soldier.run_amount = float(s[2])
		soldier.aim_amount = float(s[3])
		soldier.crouch_amount = 0.0
		soldier.attack_amount = 0.9 if s[0] == "lunge" else 0.0
		soldier.aim_point = soldier.global_position + dir * 8.0 + Vector3.UP * 1.3
		for f in 40:
			await get_tree().physics_frame
			soldier.aim_point = soldier.global_position + dir * 8.0 + Vector3.UP * 1.3
		# camera to the soldier's side, level with the chest
		var side := soldier.global_basis.x
		p.global_position = soldier.global_position + side * 2.6 + Vector3.DOWN * 0.3
		p.look_at(Vector3(soldier.global_position.x, p.global_position.y, soldier.global_position.z))
		p.camera.rotation.x = 0.0
		await get_tree().process_frame
		await get_tree().process_frame
		var sk := soldier.skeleton
		var hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
		var stretch := []
		for arm: String in ["Right", "Left"]:
			var s0 := sk.get_bone_global_pose(sk.find_bone(arm + "UpperArm")).origin
			var e0 := sk.get_bone_global_pose(sk.find_bone(arm + "LowerArm")).origin
			var w0 := sk.get_bone_global_pose(sk.find_bone(arm + "Hand")).origin
			stretch.append("%.2f" % (s0.distance_to(w0) / (s0.distance_to(e0) + e0.distance_to(w0))))
		print("%s: hips %.2f  model y %.2f  arm stretch R/L %s  crouch %.2f" % [s[0], hips.y, soldier._model.position.y, stretch, soldier.crouch_amount])
		get_viewport().get_texture().get_image().save_png("/tmp/pose_%s.png" % s[0])
	get_tree().quit()


## The game scene, set to use a throwaway save so a test never touches yours.
func _test_game_scene() -> PackedScene:
	Engine.set_meta(&"test_save", true)
	return load("res://scenes/game.tscn")
