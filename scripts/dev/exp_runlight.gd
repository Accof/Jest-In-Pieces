extends Node3D
## Throwaway lighting experiment for the run quads.
func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.31, 0.34)
	env.ambient_light_energy = 0.22
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var wall := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(6, 4); pm.orientation = PlaneMesh.FACE_Z
	wall.mesh = pm
	var wm := StandardMaterial3D.new(); wm.albedo_color = Color(0.6, 0.55, 0.45); wall.material_override = wm
	wall.position = Vector3(0, 1.5, -2)
	add_child(wall)
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.78, 0.5); l.light_energy = 2.0; l.omni_range = 6.5; l.position = Vector3(0, 2.4, 0.3); add_child(l)
	var cam := Camera3D.new(); cam.fov = 75; cam.position = Vector3(0, 1.5, 1.2); add_child(cam); cam.make_current()
	var quad := QuadMesh.new(); quad.size = Vector2(0.4, 0.8); quad.center_offset = Vector3(0, -0.4, 0)
	var xs := [-1.2, -0.4, 0.4, 1.2]
	var mats: Array = []
	# A: the run shader as is
	var a := ShaderMaterial.new(); a.shader = load("res://shaders/blood_run.gdshader"); a.set_shader_parameter("mask", load("res://art/blood/splat2/drip_mask.png")); a.set_shader_parameter("progress", 1.0); mats.append(a)
	# B: standard material, the deep colour, opaque
	var b := StandardMaterial3D.new(); b.albedo_color = Color(0.04, 0.003, 0.004); mats.append(b)
	# C: standard material, the thin colour
	var c := StandardMaterial3D.new(); c.albedo_color = Color(0.16, 0.01, 0.008); mats.append(c)
	# D: the run shader with the mask forced full (a red rectangle) via progress 1 and a flat shader
	var d := ShaderMaterial.new(); d.shader = load("res://shaders/exp_flat.gdshader"); mats.append(d)
	for i in 4:
		var m := MeshInstance3D.new(); m.mesh = quad; m.material_override = mats[i]
		m.position = Vector3(xs[i], 1.9, -2 + 0.006)
		add_child(m)
	# E: a heavy decal on the wall; F: flat shader at the sRGB-encoded deep (0.221, 0.039, 0.051);
	# G: flat shader at linear deep (0.04, 0.003, 0.004); H: flat at sRGB-encoded thin
	var dec := Decal.new(); dec.texture_albedo = load("res://art/blood/splat2/splat_heavy_0.png"); dec.size = Vector3(0.6, 0.3, 0.6)
	dec.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(-1.2, 1.0, -2)); add_child(dec)
	var cols := [Color(0.221, 0.039, 0.051), Color(0.04, 0.003, 0.004), Color(0.437, 0.100, 0.086)]
	for i in 3:
		var fm := ShaderMaterial.new(); fm.shader = load("res://shaders/exp_flat.gdshader"); fm.set_shader_parameter("col", cols[i])
		var m := MeshInstance3D.new(); m.mesh = quad; m.material_override = fm; m.position = Vector3(-0.4 + i * 0.8, 1.0, -2 + 0.006); add_child(m)
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/exp/runlight.png")
	get_tree().quit()
