extends Node3D
## A controlled room for judging blood: six floor strips in the game's own
## surfaces (churned mud, concrete floor, firm ground, planks, iron, duckboards)
## in front of a concrete wall, each given the same set of blood: a body's pool,
## a small pool, bullet exit sprays, a heavy impact, small splats and a wall hit.
## The game's bunker environment (SSR, SSAO, fog, filmic), lit bright or dim.
##   godot --rendering-method forward_plus res://scenes/look_blood.tscn -- --tag=X [--dim]
## Writes /tmp/look_blood_<tag>_<view>.png.
const STRIPS := [
	["mud", "res://art/trench/mud_churned"],
	["concrete", "res://art/level/floor_conc"],
	["ground", "res://art/trench/ground_firm"],
	["planks", "res://art/level/planks"],
	["iron", "res://art/trench/iron"],
	["duckboard", "res://art/level/duckboard"],
]
const W := 2.4            # each strip's width (x)
const D := 4.0            # depth (z), wall at z = -D/2
var tag := "x"
var dim := false
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	dim = "--dim" in OS.get_cmdline_user_args()
	_build()
	_run()


func _mat(base: String, tiling: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + ".png")
	if ResourceLoader.exists(base + "_n.png"):
		m.normal_enabled = true
		m.normal_texture = load(base + "_n.png")
	if ResourceLoader.exists(base + "_r.png"):
		m.roughness_texture = load(base + "_r.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	else:
		m.roughness = 0.85
	m.uv1_scale = Vector3(tiling, tiling, 1)
	m.uv1_triplanar = true
	return m


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	body.position = at
	add_child(body)


func _build() -> void:
	var n := STRIPS.size()
	for i in n:
		_box(Vector3(W, 0.2, D), Vector3((i - (n - 1) * 0.5) * W, -0.1, 0), _mat(STRIPS[i][1], 0.5))
	_box(Vector3(W * n, 3.0, 0.3), Vector3(0, 1.5, -D * 0.5 - 0.15), _mat("res://art/level/wall_conc", 0.5))
	# the game's bunker environment (game.gd _build_environment), without the sky sun
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.31, 0.34)
	env.ambient_light_energy = 0.12 if dim else 0.22
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.ssao_radius = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# bare bulbs over the strips: warm, like the bunker's
	for i in n:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 0.9 if dim else 2.0
		l.omni_range = 5.0 if dim else 6.5
		l.shadow_enabled = true
		l.position = Vector3((i - (n - 1) * 0.5) * W, 2.4, 0.3)
		add_child(l)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.02
	add_child(cam)
	cam.make_current()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(view: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/look_blood_%s_%s.png" % [tag, view])


func _run() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	Blood.clear()
	if "--legacy" in OS.get_cmdline_user_args():
		Blood.use_legacy_splatters = true
		Blood._load_splatters()
	Blood._rng.seed = 1918
	var n := STRIPS.size()
	for i in n:
		var cx := (float(i) - (n - 1) * 0.5) * W
		# a body's pool and a small one
		Blood.spawn_pool(Vector3(cx - 0.35, 0.0, 0.55), Vector3.UP, 0.85)
		Blood.spawn_pool(Vector3(cx + 0.7, 0.0, 1.25), Vector3.UP, 0.3)
		# a shot through a standing body: exit spray onto the floor ahead and the wall
		Blood.spawn_hit(Vector3(cx + 0.2, 1.2, 0.2), Vector3(0.05, -0.55, -1.0), 1.4)
		Blood.spawn_hit(Vector3(cx - 0.6, 1.0, -0.6), Vector3(-0.1, -0.15, -1.0), 1.0)
		# a body slamming the floor (heavy impact), a few small splats
		Blood.spawn_decal(Vector3(cx + 0.55, 0.0, -0.35), Vector3.UP, 0.75, "impact")
		for k in 4:
			Blood.spawn_decal(Vector3(cx - 0.8 + 0.35 * k, 0.0, 1.55), Vector3.UP, 0.16, "spray", Vector3(0.3, 0, -1))
		Blood.spawn_decal(Vector3(cx + 0.9, 0.0, 0.35), Vector3.UP, 0.5, "streak", Vector3(1, 0, -0.4), 1.0, 1.8)
	await _wait(12.0)                      # pools spread and settle
	await get_tree().process_frame
	print("BLOODMEM textures %.1f MB, decals visible %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		Blood._decals.filter(func(d: Decal) -> bool: return d.visible).size()])
	if "--memonly" in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	# gameplay distance: standing at the near edge of each pair of strips
	for i in [0, 1, 3]:
		var cx := (float(i) - (n - 1) * 0.5) * W
		cam.position = Vector3(cx + 0.2, 1.7, 2.6)
		cam.look_at(Vector3(cx + 0.1, 0.0, 0.0))
		await _shot("play_%s" % STRIPS[i][0])
	# wide: three strips and the wall
	cam.position = Vector3(-W * 1.5, 2.2, 3.6)
	cam.look_at(Vector3(-W * 1.5, 0.4, -1.0))
	await _shot("wide")
	# close-ups: the body pool, the spray, the wall
	for i in [0, 1, 4]:
		var cx := (float(i) - (n - 1) * 0.5) * W
		cam.position = Vector3(cx - 0.3, 0.55, 1.15)
		cam.look_at(Vector3(cx - 0.35, 0.0, 0.5))
		await _shot("close_pool_%s" % STRIPS[i][0])
		cam.position = Vector3(cx + 0.2, 0.6, 0.35)
		cam.look_at(Vector3(cx + 0.35, 0.0, -0.5))
		await _shot("close_spray_%s" % STRIPS[i][0])
	cam.position = Vector3(-W * 2.0, 1.1, -0.6)
	cam.look_at(Vector3(-W * 2.5 + 0.2, 0.9, -D * 0.5))
	await _shot("close_wall")
	get_tree().quit()
