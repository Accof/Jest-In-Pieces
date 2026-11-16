class_name MuzzleFlash
extends RefCounted
## An enemy's muzzle flash: a burst of hot gas out of the barrel you can see
## from any side (three crossed petals along the shot, a star end on), a hard
## flash of light that lights the corridor for a frame or two, and a puff of
## grey smoke hanging where the muzzle was.

static var _petal_mat: StandardMaterial3D
static var _star_mat: StandardMaterial3D


static func _materials() -> void:
	if _petal_mat:
		return
	_petal_mat = _mat(_flame_tex(true))
	_star_mat = _mat(_flame_tex(false))


static func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.albedo_color = Color(2.4, 1.7, 0.9)
	m.no_depth_test = false
	return m


## A flame shape drawn into a small texture: a long tongue (`petal`), or a
## ragged star seen down the barrel.
static func _flame_tex(petal: bool) -> ImageTexture:
	var w := 64
	var h := 128 if petal else 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if petal else 78
	var spikes: Array[float] = []
	for i in 7:
		spikes.append(rng.randf_range(0.5, 1.0))
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h
			var a := 0.0
			if petal:
				# widest a third of the way out, tapering to a point
				var width := 0.85 * sin(clampf(v, 0.0, 1.0) * PI) * (1.0 - 0.45 * v) + 0.05
				a = clampf(1.0 - absf(u) / width, 0.0, 1.0)
				a = pow(a, 1.3) * (1.0 - smoothstep(0.75, 1.0, v))
			else:
				var p := Vector2(u, v * 2.0 - 1.0)
				var ang := atan2(p.y, p.x)
				var k := int(floor((ang + PI) / TAU * 7.0)) % 7
				var reach := lerpf(0.3, 1.0, spikes[k] * (0.5 + 0.5 * cos(fposmod(ang + PI, TAU / 7.0) * 7.0 - PI)))
				a = clampf(1.0 - p.length() / reach, 0.0, 1.0)
				a = pow(a, 1.2)
			var hot := clampf(a * 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, lerpf(0.45, 0.95, hot), lerpf(0.1, 0.7, hot * hot), a))
	return ImageTexture.create_from_image(img)


static func burst(parent: Node, pos: Vector3, dir: Vector3, size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_materials()
	var root := Node3D.new()
	parent.add_child(root)
	dir = dir.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	root.global_transform = Transform3D(Basis(x, dir.cross(x), dir), pos)
	var length := randf_range(0.42, 0.6) * size
	var width := randf_range(0.17, 0.24) * size
	var roll := randf() * PI
	for i in 3:
		var q := QuadMesh.new()
		q.size = Vector2(width, length)
		q.material = _petal_mat
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the quad's long side (its y) along the barrel, starting at the muzzle
		mi.transform = Transform3D(Basis(Vector3.BACK, roll + i * PI / 3.0) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, length * 0.42))
		root.add_child(mi)
	var star := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE * width * 1.7
	sq.material = _star_mat
	star.mesh = sq
	star.rotation.z = randf() * TAU
	star.position = Vector3(0, 0, 0.03)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(star)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 9.0 * size
	light.omni_range = 9.0 * size
	light.shadow_enabled = false
	light.position = Vector3(0, 0, 0.2)
	root.add_child(light)
	# two frames bright, a third fading, gone
	var tw := root.create_tween()
	tw.tween_interval(0.035)
	tw.tween_property(root, "scale", Vector3(0.6, 0.6, 1.25), 0.03)
	tw.parallel().tween_property(light, "light_energy", 2.0 * size, 0.03)
	tw.tween_callback(root.queue_free)
	if parent is Node3D:
		var smoke := MechFx.smoke(parent as Node3D, (parent as Node3D).to_local(pos + dir * 0.15), 0.15)
		if smoke:
			smoke.scale = Vector3.ONE * 1.8 * size
