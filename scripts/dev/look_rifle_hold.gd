extends Node3D
## Dev: the enemy rifle in a WitzSoldat's hands, close up: the right hand on
## the wrist of the stock with the index at the trigger, the left under the
## fore-end, the bolt handle worked. Cameras are placed in the rifle's own
## frame so every shot frames the same part of it.
##   godot --path . res://scenes/look_rifle_hold.tscn -- [--tag=x] [--look=witzsoldat_dark]
## Writes /tmp/hold_<tag>_<state>_<view>.png

var tag := "x"
var look := "witzsoldat_dark"
var c: Clown
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		if a.begins_with("--look="):
			look = a.substr(7)
		if a.begins_with("--down="):
			Clown.rifle_hand_down = float(a.substr(7))
		if a.begins_with("--index="):
			Clown.rifle_index_curl = float(a.substr(8))
		if a.begins_with("--lift="):
			Clown.rifle_grip_lift = float(a.substr(7))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.21, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	fm.mesh = pm
	add_child(fm)
	cam = Camera3D.new()
	cam.fov = 35
	add_child(cam)
	_run()


var _hold_phase := -1.0


func _process(_delta: float) -> void:
	# a bolt phase held still for the camera (the clown's own _process adds delta after this)
	if _hold_phase >= 0.0 and c:
		c._shot_t = 0.3 + c.bolt_seconds * _hold_phase - 0.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Camera at `from` looking at `at`, both in the rifle's frame.
func _shot(state: String, view: String, from: Vector3, at: Vector3) -> void:
	var xf: Transform3D = c._rifle.global_transform
	cam.global_position = xf * from
	cam.look_at(xf * at, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/hold_%s_%s_%s.png" % [tag, state, view])


func _views(state: String) -> void:
	var info: Dictionary = Clown.RIFLE_INFO
	print("%s: bolt phase %.2f, bolt at %s rot z %.2f" % [state, c.bolt_phase(), c._bolt.position.snapped(Vector3(0.001, 0.001, 0.001)) if c._bolt else Vector3.ZERO, c._bolt.rotation.z if c._bolt else 0.0])
	_print_hands()
	var wrist := Vector3(0, -0.02, 0.24)
	if info.has("wrist"):
		wrist = Vector3(info.wrist[0], info.wrist[1], info.wrist[2])
	var trig := Vector3(0, -0.04, 0.32)
	if info.has("trigger"):
		trig = Vector3(info.trigger[0], info.trigger[1], info.trigger[2])
	var fore := Vector3(0, 0, 0.6)
	var bolt := Vector3(0, 0.025, 0.35)
	if info.has("bolt_root"):
		bolt = Vector3(info.bolt_root[0], info.bolt_root[1], info.bolt_root[2])
	# the right hand from the right side, low, and from below the trigger
	await _shot(state, "right", wrist + Vector3(-0.5, -0.05, 0.1), wrist + Vector3(0, -0.01, 0.03))
	await _shot(state, "trigger", trig + Vector3(-0.25, -0.3, 0.1), trig)
	# the left hand from below-left and from the muzzle end
	await _shot(state, "left", fore + Vector3(0.4, -0.3, 0.05), fore + Vector3(0, -0.02, 0))
	await _shot(state, "left_end", fore + Vector3(0.1, -0.15, 0.55), fore)
	# the bolt from above and behind, right
	await _shot(state, "bolt", bolt + Vector3(-0.9, 0.55, -0.2), bolt + Vector3(-0.03, 0.06, 0))
	await _shot(state, "bolt_top", bolt + Vector3(-0.3, 0.9, 0.5), bolt + Vector3(-0.03, 0.05, 0))
	# the whole hold from the right and from above
	await _shot(state, "whole", Vector3(-1.3, 0.3, 0.45), Vector3(0, 0, 0.45))
	await _shot(state, "above", Vector3(-0.2, 1.2, 0.4), Vector3(0, 0, 0.45))


func _run() -> void:
	seed(1917)
	c = Clown.new()
	c.body = "witzsoldat"
	c.look = look
	add_child(c)
	c.give_rifle()
	c.always_pose = true
	c.set_process(true)
	c.walk_amount = 0.0
	c.run_amount = 0.0
	c.aim_amount = 0.0
	c.aim_point = c.global_position + c.global_basis.z * 8.0 + Vector3.UP * 1.3
	await _frames(30)
	print("rifle info: ", Clown.RIFLE_INFO.keys())
	var all := "--all" in OS.get_cmdline_user_args()
	if all:
		await _views("carry")
	c.aim_amount = 1.0
	await _frames(60)
	await _views("aim")
	_print_hands()
	if "--bare" in OS.get_cmdline_user_args():
		# the rifle alone with markers: red the json's trigger, green the
		# index fingertip, blue the thumb's, yellow the right hand's wrist bone
		c.mesh.visible = false
		var sk: Skeleton3D = c.skeleton
		var rifle_in_skel: Transform3D = sk.get_bone_global_pose(sk.find_bone("Chest")) * c._rifle.transform
		var marks: Array = []
		var info: Dictionary = Clown.RIFLE_INFO
		marks.append([c._rifle.global_transform * Vector3(info.trigger[0], info.trigger[1], info.trigger[2]), Color(1, 0, 0)])
		for pair in [["RightIndex3", Color(0, 1, 0)], ["RightThumb3", Color(0.2, 0.4, 1)], ["RightHand", Color(1, 1, 0)], ["LeftIndex3", Color(0, 1, 0)], ["LeftThumb3", Color(0.2, 0.4, 1)]]:
			var bi := sk.find_bone(pair[0])
			var gp := sk.get_bone_global_pose(bi)
			# a fingertip: the bone's end, 2 cm along it
			var tip := gp.origin + gp.basis.y * (0.02 if String(pair[0]).ends_with("3") else 0.0)
			marks.append([sk.global_transform * tip, pair[1]])
		for mk: Array in marks:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.006
			sm.height = 0.012
			var mat := StandardMaterial3D.new()
			mat.albedo_color = mk[1]
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.material = mat
			mi.mesh = sm
			add_child(mi)
			mi.global_position = mk[0]
		await _views("bare")
		c.mesh.visible = true
	# the bolt, frozen at three points of the cycle
	for ph: float in ([0.25, 0.45, 0.6] if all else []):
		_hold_phase = ph
		await _frames(2)
		await _views("bolt%02d" % int(ph * 100))
	_hold_phase = -1.0
	_print_hands()
	get_tree().quit()


func _print_hands() -> void:
	var sk: Skeleton3D = c.skeleton
	var xf: Transform3D = c._rifle.transform
	var rifle_in_skel: Transform3D = sk.get_bone_global_pose(sk.find_bone("Chest")) * xf
	for side: String in ["Right", "Left"]:
		var h := sk.get_bone_global_pose(sk.find_bone(side + "Hand"))
		var local := rifle_in_skel.affine_inverse() * h
		print("%s hand in the rifle's frame: origin %s  along %s  palm %s" % [side, local.origin.snapped(Vector3(0.001, 0.001, 0.001)), local.basis.y.snapped(Vector3(0.01, 0.01, 0.01)), local.basis.x.snapped(Vector3(0.01, 0.01, 0.01))])
		for fb: String in ["Index3", "Thumb3"]:
			var bi := sk.find_bone(side + fb)
			if bi >= 0:
				var tip := rifle_in_skel.affine_inverse() * sk.get_bone_global_pose(bi)
				print("   %s %s at %s" % [side, fb, tip.origin.snapped(Vector3(0.001, 0.001, 0.001))])
