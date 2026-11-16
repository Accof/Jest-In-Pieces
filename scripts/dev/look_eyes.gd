extends Node3D
## Dev: the Klappersoldat in near darkness at 4, 10 and 18 m, as the game
## lights it (glow on), to judge how well its eyes read. /tmp/k/eyes_*.png
func _ready() -> void:
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	var e := env.environment
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.03, 0.03, 0.035)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true; e.glow_intensity = 0.7; e.glow_bloom = 0.08; e.glow_hdr_threshold = 1.0
	add_child(env)
	var floor_ := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); floor_.mesh = pm; add_child(floor_)
	var k := Klappersoldat.new()
	add_child(k)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 70
	for d: float in [4.0, 10.0, 18.0]:
		cam.position = Vector3(0.3, 1.6, d); cam.look_at(Vector3(0, 1.5, 0))
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/k/eyes_%d.png" % int(d))
	get_tree().quit()
