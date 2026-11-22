class_name TrenchArt
extends Node3D
## Dresses a TrenchMaze: the carved mud, revetments, duckboards, water,
## landmarks and the battlefield beyond. Built once per floor.

var maze: TrenchMaze
var rng := RandomNumberGenerator.new()
var _multi := {}                 ## key -> {mesh, mat, xfs}
var _body: StaticBody3D          ## revetment, roof and prop collision
var _mats := {}
## Where things are, for the ambience: dugout doors (drips), lined walls
## (creaks), the music box.
var drip_spots: Array[Vector3] = []
var creak_spots: Array[Vector3] = []
## Where loose iron and wire can rattle in the wind (pickets).
var rattle_spots: Array[Vector3] = []
var music_box := Vector3.INF
var _far_noise: FastNoiseLite
var _far_holes: FastNoiseLite

const BAG := Vector3(0.52, 0.14, 0.3)

## Which scanned set each old texture name now uses, and how it is set up
## (pbr_object.gdshader parameters). Wattle has no scan: it keeps its
## procedural texture.
const PBR_FOR := {
	"board": {set = "rough_wood", tile = 1.0, grain = true, darken = 0.74, wet = 0.55, grime = 0.42, rough_min = 0.42, tint = Color(0.93, 0.86, 0.78), splash = 0.9, wet_edges = 0.8},
	"planks_wet": {set = "rough_wood", tile = 1.0, grain = true, darken = 0.7, wet = 0.62, grime = 0.48, rough_min = 0.38, tint = Color(0.93, 0.86, 0.78), splash = 1.0, wet_edges = 0.9},
	"timber": {set = "rough_wood", tile = 1.0, grain = true, darken = 0.58, wet = 0.6, grime = 0.5, rough_min = 0.42, tint = Color(0.88, 0.8, 0.72), splash = 0.9, wet_edges = 0.7},
	"burlap": {set = "hessian_230", tile = 0.45, grain = false, darken = 0.46, saturation = 0.66, wet = 0.68, grime = 0.85, rough_min = 0.55, tint = Color(0.84, 0.76, 0.64), normal_strength = 1.2, splash = 1.0},
	"dug_timber": {set = "rough_wood", tile = 1.0, grain = true, darken = 0.58, wet = 0.5, grime = 0.5, rough_min = 0.45, tint = Color(0.88, 0.8, 0.72), under_cover = 1.0},
	"dug_iron": {set = "rusty_metal_04", tile = 1.6, grain = false, darken = 0.7, wet = 0.2, grime = 0.4, rough_min = 0.5, metal_from_albedo = 0.2, under_cover = 1.0},
	"iron": {set = "rusty_metal_04", tile = 1.6, grain = false, darken = 0.8, wet = 0.3, grime = 0.35, rough_min = 0.4, metal_from_albedo = 0.55, splash = 0.7},
}


func build(m: TrenchMaze) -> void:
	maze = m
	rng.seed = m.rng.seed + 17
	_body = StaticBody3D.new()
	_body.name = "Props"
	_body.collision_layer = Maze.LAYER_WORLD
	_body.collision_mask = 0
	add_child(_body)
	_terrain()
	_revetments()
	_parapets()
	_fire_steps()
	_duckboards()
	_water()
	_landmarks()
	_bridges()
	_ramps()
	_far()
	_wire()
	_no_mans_land()
	var st := rng.state
	_horizon()
	rng.state = st              # the scenery out there leaves the trench's own dressing as it was
	_props()
	_signs()
	_carnival()
	_wind_things()
	_smoke()
	_mist()
	_flush()
	_share_sky()
	var amb := TrenchAmbience.new()
	amb.name = "Ambience"
	add_child(amb)
	amb.setup(maze, self)


static func tex(name_: String) -> Texture2D:
	return load("res://art/trench/%s.png" % name_)


## Bounced light (SDFGI): the sunlit wall and parapet light the shadowed side
## and the floor, so the trench is lit from one side and from above rather
## than by an even fill, and the floor is lit by what it can actually see.
## With it on the baked "deeper is darker" sky visibility is left off (the GI
## does that occlusion itself). Costs GPU time: switch off here (or NO_GI=1)
## if frame rate suffers; the even fill is then used as before.
static var bounce_light := OS.has_environment("GI")   # off: it read as a sunny day and stalled the frame for seconds as it rebuilt (user, 22 Nov)


## Where the light comes from: low, behind the storm cloud, over No Man's
## Land (the sky shader's light_dir; the sun shines along -LIGHT_DIR).
const LIGHT_DIR := Vector3(-0.45, 0.32, -0.83)


## The storm day (used by the game on trench floors). A tonal hierarchy, not
## a dim screen: the sky the brightest thing, the haze-softened battlefield,
## the parapets in moderate diffuse light, the trench walls darkening toward
## the bottom (sky visibility, baked per floor), the floor dark but catching
## the sky in its water.
static func make_environment() -> Environment:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/overcast_sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", tex("noise"))
	sky_mat.set_shader_parameter("light_dir", LIGHT_DIR)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# the sky's light, but less of it than before: the trench is lit from above
	# and the baked sky visibility takes it away lower down
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0 if bounce_light else 0.85   # (0.75 hid the floor; 1.05 took the gloom away)
	if bounce_light:
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.15
		env.sdfgi_energy = 1.5
		env.sdfgi_bounce_feedback = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssao_radius = 1.4
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.ssil_radius = 4.0
	# atmospheric depth: nothing in the first 18 m (the trench stays crisp and
	# the enemies in it clear), softening through the middle distance, the far
	# battlefield hazy and blue-grey
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.47, 0.52, 0.58)
	env.fog_density = 0.82
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 320.0
	env.fog_depth_curve = 1.7
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.2
	# the ground mist's volume (TrenchArt._mist) needs the volumetric fog; it
	# has no fog of its own everywhere (density 0), only what the volume adds,
	# lit by the sky's ambient and a little by the sun
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.66, 0.7, 0.75)
	env.volumetric_fog_ambient_inject = 0.85
	env.volumetric_fog_anisotropy = 0.55            # (stronger toward the light: figures out there against the glow)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.08
	env.adjustment_color_correction = make_grade()
	return env


## The grade: cold blue-grey shadows, neutral mid-tones (the materials keep
## their own colour), a touch of warmth only in the brightest light, and a
## little saturation taken out of the darks. Not a blue filter: the cast
## fades out as the image brightens.
static func make_grade() -> ImageTexture3D:
	var n := 24
	var images: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := Vector3(r, g, b) / float(n - 1)
				var lum := c.dot(Vector3(0.299, 0.587, 0.114))
				var shadow := 1.0 - smoothstep(0.02, 0.5, lum)
				var high := smoothstep(0.6, 1.0, lum)
				var out := c
				out = out.lerp(Vector3.ONE * lum, 0.25 * shadow)                 # darks a little less saturated
				out *= Vector3.ONE.lerp(Vector3(0.88, 0.95, 1.08), shadow * 0.85)  # and cold
				out *= Vector3.ONE.lerp(Vector3(1.03, 1.0, 0.96), high * 0.6)     # light, a little warm
				img.set_pixel(r, g, Color(clampf(out.x, 0.0, 1.0), clampf(out.y, 0.0, 1.0), clampf(out.z, 0.0, 1.0)))
		images.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, n, n, n, false, images)
	return t


## The eye adjusting: brighter in a dugout or a deep dark corner, back down
## out in the open, over a second or two.
static func make_camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	# only a little: the trench is meant to be darker than the sky, and a free
	# auto exposure would lift it back to grey
	ca.auto_exposure_scale = 0.3
	ca.auto_exposure_speed = 0.5
	ca.auto_exposure_min_sensitivity = 95.0
	ca.auto_exposure_max_sensitivity = 280.0 if bounce_light else 180.0   # looking down into the trench, the eye opens up a little
	return ca


## Cold daylight breaking through the cloud, low over No Man's Land: it lights
## the parapets and the tops of the far walls; the trench interiors fall into
## shadow.
static func setup_sun(sun: DirectionalLight3D) -> void:
	sun.light_color = Color(0.82, 0.86, 0.94)
	sun.light_energy = 1.2 if bounce_light else 0.85   # (with the bounce, more of it reaches the floor indirectly)
	sun.light_specular = 0.08            # overcast: no hard sun glints on the water
	sun.light_angular_distance = 2.5
	sun.light_volumetric_fog_energy = 0.35
	sun.shadow_enabled = true
	sun.shadow_opacity = 1.0
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0
	sun.look_at_from_position(Vector3.ZERO, -LIGHT_DIR, Vector3.UP)
	sun.position = Vector3.ZERO


## A scanned set from art/trench/pbr/<name>: albedo, normal, packed AO/rough/height.
static func pbr(name_: String, map: String) -> Texture2D:
	return load("res://art/trench/pbr/%s/%s_%s_2k.png" % [name_, name_, map])


var _ground_mat: ShaderMaterial


## The ground's material (mud_terrain.gdshader): the brown mud on the walls
## and up top, rocks on rims and damage, firmer procedural ground further
## off, the scanned wet mud on the trench floor.
func ground_material() -> ShaderMaterial:
	if _ground_mat:
		return _ground_mat
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mud_terrain.gdshader")
	for pair: Array in [["wall", "brown_mud_wall"], ["rocks", "rocks_ground_08"]]:
		mat.set_shader_parameter(pair[0] + "_a", pbr(pair[1], "diff"))
		mat.set_shader_parameter(pair[0] + "_n", pbr(pair[1], "nor_gl"))
		mat.set_shader_parameter(pair[0] + "_ard", pbr(pair[1], "ard"))
	mat.set_shader_parameter("firm_a", tex("ground_firm"))
	mat.set_shader_parameter("firm_n", tex("ground_firm_n"))
	mat.set_shader_parameter("firm_r", tex("ground_firm_r"))
	mat.set_shader_parameter("noise_tex", tex("noise"))
	# the trench floor: the Poly Haven scan (art/trench/polyhaven)
	mat.set_shader_parameter("floor_a", load("res://art/trench/polyhaven/brown_mud_03_diff_2k.png"))
	mat.set_shader_parameter("floor_n", load("res://art/trench/polyhaven/brown_mud_03_nor_gl_2k.png"))
	mat.set_shader_parameter("floor_ard", load("res://art/trench/polyhaven/brown_mud_03_ard_2k.png"))
	if bounce_light:
		mat.set_shader_parameter("sky_occlusion", 0.0)
	_ground_mat = mat
	return mat


## Give every prop material the floor's sky visibility, so linings, bags and
## boards down in the trench darken with it as the ground does.
func _share_sky() -> void:
	var t := maze.sky_texture()
	var org := maze.origin
	var size := Vector2((maze.sky_w - 1) * TrenchMaze.SKY_STEP * TrenchMaze.RES, (maze.sky_d - 1) * TrenchMaze.SKY_STEP * TrenchMaze.RES)
	for m: Material in _mats.values():
		if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("pbr_object.gdshader"):
			var sm := m as ShaderMaterial
			sm.set_shader_parameter("sky_tex", t)
			sm.set_shader_parameter("sky_origin", org)
			sm.set_shader_parameter("sky_size", size)
			sm.set_shader_parameter("sky_on", true)
			if bounce_light:
				sm.set_shader_parameter("sky_occlusion", 0.0)


## How broken-down the ground is around each point (vertex A, 0..1): the
## slumped stretch, walls whose lining has come away, the rims of shell
## holes. Rocks and rubble show there.
var _damage := {}


func _damage_at(x: float, z: float) -> float:
	var m := maze
	if _damage.is_empty():
		_damage[Vector2i(-999, -999)] = 0.0
		for c: Vector2i in m.open_cells:
			var d := 0.0
			if m.collapsed.has(c):
				d = 1.0
			for dir in Maze.DIRS:
				if m.wall(c, dir) == "broken":
					d = maxf(d, 0.65)
			if d > 0.0:
				_damage[c] = d
	var fx := x / m.cell - 0.5
	var fz := z / m.cell - 0.5
	var best := 0.0
	var c0 := Vector2i(int(floor(fx)), int(floor(fz)))
	for dz in range(-1, 3):
		for dx in range(-1, 3):
			var c := c0 + Vector2i(dx, dz)
			var d: float = _damage.get(c, 0.0)
			if d > 0.0:
				var dist := Vector2(fx - c.x, fz - c.y).length()
				best = maxf(best, d * (1.0 - smoothstep(0.6, 1.4, dist)))
	return best


## The carved ground as chunked meshes (16 m squares, for culling).
func _terrain() -> void:
	var mat := ground_material()
	var chunk := 80                   # samples per side
	var m := maze
	var res := TrenchMaze.RES
	for cz in range(0, m.hz - 1, chunk):
		for cx in range(0, m.hx - 1, chunk):
			var x1 := mini(cx + chunk, m.hx - 1)
			var z1 := mini(cz + chunk, m.hz - 1)
			var nx := x1 - cx + 1
			var nz := z1 - cz + 1
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var uv2 := PackedVector2Array()
			uv2.resize(nx * nz)
			verts.resize(nx * nz)
			norms.resize(nx * nz)
			cols.resize(nx * nz)
			var k := 0
			for iz in range(cz, z1 + 1):
				var row := iz * m.hx
				var up_row := mini(iz + 1, m.hz - 1) * m.hx
				var dn_row := maxi(iz - 1, 0) * m.hx
				for ix in range(cx, x1 + 1):
					var i := ix + row
					var h := m.vis_h[i]
					var nrm := Vector3(m.vis_h[maxi(ix - 1, 0) + row] - m.vis_h[mini(ix + 1, m.hx - 1) + row], 2.0 * res, m.vis_h[ix + dn_row] - m.vis_h[ix + up_row])
					norms[k] = nrm.normalized()
					var sd := m.sdf[i]
					var dmg := _damage_at(verts_x(m, ix), m.origin.y + iz * res) if sd < 3.0 else 0.0
					cols[k] = Color(m.wet[i], 1.0 if sd <= 0.0 else 0.0, clampf(sd * 0.5, 0.0, 1.0), dmg)
					verts[k] = Vector3(m.origin.x + ix * res, h, m.origin.y + iz * res)
					uv2[k] = Vector2(m.sky_vis[i], m.puddle[i] if not m.puddle.is_empty() else 0.0)
					k += 1
			var idx := PackedInt32Array()
			idx.resize((nx - 1) * (nz - 1) * 6)
			k = 0
			for iz in nz - 1:
				for ix in nx - 1:
					var a := ix + iz * nx
					idx[k] = a
					idx[k + 1] = a + 1
					idx[k + 2] = a + nx
					idx[k + 3] = a + 1
					idx[k + 4] = a + nx + 1
					idx[k + 5] = a + nx
					k += 6
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
			arrays[Mesh.ARRAY_INDEX] = idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = am
			mi.material_override = mat
			add_child(mi)


# --- shared ------------------------------------------------------------------------
static func verts_x(m: TrenchMaze, ix: int) -> float:
	return m.origin.x + ix * TrenchMaze.RES



## A triplanar world-mapped material from an art/trench texture set (no
## stretching on scaled boxes).
func _mat(name_: String, scale := 1.0, rough := -1.0) -> Material:
	var key := "%s:%s" % [name_, scale]
	if _mats.has(key):
		return _mats[key]
	# the scanned sets for wood, sandbags and iron (shaders/pbr_object.gdshader)
	if PBR_FOR.has(name_):
		var spec: Dictionary = PBR_FOR[name_]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/pbr_object.gdshader")
		sm.set_shader_parameter("albedo_tex", pbr(spec.set, "diff"))
		sm.set_shader_parameter("normal_tex", pbr(spec.set, "nor_gl"))
		sm.set_shader_parameter("ard_tex", pbr(spec.set, "ard"))
		sm.set_shader_parameter("noise_tex", tex("noise"))
		for k: String in spec:
			if k != "set":
				sm.set_shader_parameter(k, spec[k])
		_mats[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name_)
	m.normal_enabled = true
	m.normal_texture = tex(name_ + "_n")
	m.normal_scale = 0.8
	if ResourceLoader.exists("res://art/trench/%s_r.png" % name_) and rough < 0.0:
		m.roughness_texture = tex(name_ + "_r")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		m.roughness = rough if rough >= 0.0 else 0.8
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


func _add(key: String, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	if not _multi.has(key):
		_multi[key] = {mesh = mesh, mat = mat, xfs = []}
	_multi[key].xfs.append(xf)


func _box(key: String, mat: Material, centre: Vector3, basis: Basis, size: Vector3) -> void:
	if not _multi.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		_multi[key] = {mesh = bm, mat = mat, xfs = []}
	_multi[key].xfs.append(Transform3D(basis.scaled_local(size), centre))


func _flush() -> void:
	for key: String in _multi:
		var e: Dictionary = _multi[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e.mesh
		mm.instance_count = e.xfs.size()
		for i in e.xfs.size():
			mm.set_instance_transform(i, e.xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = e.mat
		add_child(mmi)
	_multi.clear()


func _collide(centre: Vector3, basis: Basis, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(basis, centre)
	_body.add_child(cs)


func _floor_at(x: float, z: float) -> float:
	return maze.ground_height(x, z)


## One edge of an open cell's floor: its two ends (at floor level, y unset),
## the inward normal and its length.
func _edge(c: Vector2i, dir: Vector2i) -> Dictionary:
	var r := maze._rect(c)
	var a: Vector2
	var b: Vector2
	match dir:
		Vector2i(-1, 0):
			a = Vector2(r.position.x, r.position.y); b = Vector2(r.position.x, r.end.y)
		Vector2i(1, 0):
			a = Vector2(r.end.x, r.position.y); b = Vector2(r.end.x, r.end.y)
		Vector2i(0, -1):
			a = Vector2(r.position.x, r.position.y); b = Vector2(r.end.x, r.position.y)
		_:
			a = Vector2(r.position.x, r.end.y); b = Vector2(r.end.x, r.end.y)
	# open neighbours along the edge: the edge runs right up to them (no gap)
	return {a = a, b = b, inward = -Vector2(dir), length = a.distance_to(b)}


# --- revetments ----------------------------------------------------------------------
## Every lined wall: timber boards between posts, corrugated iron on pickets,
## sandbags, woven hurdles, or boards that have come away. Each gets a thin
## collision box so bodies hit the lining, not the earth behind it.
func _revetments() -> void:
	var planks := _mat("board", 1.6)
	var timber := _mat("timber", 0.8)
	var wattle := _mat("wattle", 1.0)
	# no scan for woven hurdles: the procedural weave, darkened and dirtied to sit with the scans
	(wattle as StandardMaterial3D).albedo_color = Color(0.5, 0.45, 0.4)
	var iron := _mat("iron", 1.0)
	var bag := _mat("burlap", 0.5)
	var bag_mesh := _bag_mesh()
	var iron_mesh := _corrugated_mesh()
	for c: Vector2i in maze.open_cells:
		for dir in Maze.DIRS:
			var t := maze.wall(c, dir)
			if t == "" or t == "earth" or t == "ramp":
				continue
			var e := _edge(c, dir)
			var inward: Vector2 = e.inward
			var a2: Vector2 = e.a + inward * 0.02
			var b2: Vector2 = e.b + inward * 0.02
			var mid2 := (a2 + b2) * 0.5
			var length: float = e.length
			var base := _floor_at(mid2.x + inward.x * 0.25, mid2.y + inward.y * 0.25) - 0.08
			var top := maze.ground_height(mid2.x - inward.x * 0.45, mid2.y - inward.y * 0.45) + 0.05
			var h := top - base
			if h < 0.4:
				continue
			# most linings stop short of the top: earth above them, sandbags or not
			var full := h
			if t in ["timber", "iron", "wattle"]:
				h = minf(h, full * _lining_height(c, dir))
			var along := Vector3(b2.x - a2.x, 0, b2.y - a2.y).normalized()
			var inn := Vector3(inward.x, 0, inward.y)
			# the lining leans back with the wall
			var lean := maxf(float(TrenchMaze.WALL_W.get(t, 0.12)) - 0.04, 0.0) / h
			var up := (Vector3.UP - inn * lean).normalized()
			var basis := Basis(along, up, along.cross(up)).orthonormalized()
			var foot := Vector3(mid2.x, base, mid2.y)
			match t:
				"timber":
					var y := 0.0
					var k := 0
					while y < h - 0.05:
						var ph := minf(0.22, h - y)
						var jitter := Vector3(0, 0, rng.randf_range(-0.01, 0.01))
						var bb := basis.rotated(along, rng.randf_range(-0.015, 0.015))
						_box("rev_planks", planks, foot + up * (y + ph * 0.5) + inn * 0.015 + jitter, bb, Vector3(length + 0.04, ph - 0.012, 0.04))
						y += ph
						k += 1
					_posts(timber, foot, up, along, inn, length, h)
				"iron":
					var n := maxi(1, int(ceil(length / 0.7)))
					var sw := length / n
					for i in n:
						var p := foot + along * (-length * 0.5 + sw * (i + 0.5))
						var bb := basis.rotated(up, rng.randf_range(-0.03, 0.03)).rotated(along, rng.randf_range(-0.02, 0.02))
						_add("rev_iron", iron_mesh, iron, Transform3D(bb.scaled_local(Vector3(sw + 0.06, h + 0.1, 1.0)), p + up * (h * 0.5) + inn * 0.02))
					_posts(timber, foot, up, along, inn, length, h, 0.07)
				"wattle":
					_box("rev_wattle", wattle, foot + up * (h * 0.5) + inn * 0.03, basis, Vector3(length + 0.05, h, 0.06))
					_posts(timber, foot, up, along, inn, length, h + 0.15, 0.06)
				"sandbag":
					_bag_wall(bag_mesh, bag, foot, along, inn, length, h)
				"broken":
					_broken(planks, timber, foot, up, along, inn, length, h)
			if t != "broken":
				# collision for the lining: thin, just behind its face
				_collide(foot + up * (h * 0.5) - inn * 0.03, basis, Vector3(length, h, 0.08))


## How much of a wall a lining covers, the same along a stretch of trench.
func _lining_height(c: Vector2i, dir: Vector2i) -> float:
	var hsh := absi((c.x / 3) * 73856093 ^ (c.y / 3) * 19349663 ^ dir.x * 83492791 ^ dir.y * 2971) % 1000
	return 0.55 + 0.45 * float(hsh) / 1000.0


func _posts(mat: Material, foot: Vector3, up: Vector3, along: Vector3, inn: Vector3, length: float, h: float, size := 0.1) -> void:
	var n := 2 if length < 1.2 else 3
	for i in n:
		var t := float(i) / (n - 1) - 0.5
		var p := foot + along * (t * (length - size)) + inn * (0.05 + size * 0.3)
		var tilt := Basis(along, rng.randf_range(-0.03, 0.03)) * Basis(Vector3.FORWARD, rng.randf_range(-0.02, 0.02))
		var b := Basis(along, up, along.cross(up)).orthonormalized()
		_box("rev_posts", mat, p + up * ((h + 0.25) * 0.5 - 0.1), tilt * b, Vector3(size, h + 0.25, size))


## Sandbags laid in courses, header and stretcher, set back a little each course.
func _bag_wall(mesh: Mesh, mat: Material, foot: Vector3, along: Vector3, inn: Vector3, length: float, h: float) -> void:
	var rows := int(h / (BAG.y * 0.92))
	for r in rows:
		var y := r * BAG.y * 0.92 + BAG.y * 0.5
		var back := -inn * (r * 0.012)
		var n := maxi(1, int(round(length / (BAG.x * 0.95))))
		var off := (BAG.x * 0.5) if r % 2 == 1 else 0.0
		for i in n:
			var x := -length * 0.5 + (i + 0.5) * (length / n) + off * 0.5
			if absf(x) > length * 0.5 + 0.05:
				continue
			var p := foot + along * x + Vector3.UP * y + inn * (BAG.z * 0.5 + 0.0) + back
			var bb := Basis.looking_at(-inn, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.12, 0.12))
			bb = bb.rotated(along, rng.randf_range(-0.06, 0.06))
			var sc := Vector3(rng.randf_range(0.9, 1.08), rng.randf_range(0.85, 1.15), rng.randf_range(0.9, 1.05))
			_add("bags", mesh, mat, Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)).rotated(Vector3.UP, rng.randf_range(-0.1, 0.1)).scaled_local(sc), p))


## Boards come away: a few still on, some leaning out, some in the mud.
func _broken(planks: Material, timber: Material, foot: Vector3, up: Vector3, along: Vector3, inn: Vector3, length: float, h: float) -> void:
	var b := Basis(along, up, along.cross(up)).orthonormalized()
	var y := 0.0
	while y < h * 0.5:
		_box("rev_planks", planks, foot + up * (y + 0.11) + inn * 0.015, b, Vector3(length, 0.21, 0.04))
		y += 0.22
	for i in rng.randi_range(2, 3):
		var lean := Basis(along, rng.randf_range(0.25, 0.7)) * b
		var p := foot + along * rng.randf_range(-length * 0.3, length * 0.3) + inn * rng.randf_range(0.15, 0.35) + Vector3.UP * rng.randf_range(0.3, 0.7)
		_box("rev_planks", planks, p, lean.rotated(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(length * rng.randf_range(0.6, 1.0), 0.2, 0.04))
	for i in rng.randi_range(0, 2):
		var p := foot + along * rng.randf_range(-length * 0.4, length * 0.4) + inn * rng.randf_range(0.25, 0.6) + Vector3.UP * 0.1
		_box("rev_planks", planks, p, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(length * 0.7, 0.2, 0.04))
	var post := foot + along * (length * 0.5 - 0.05) + inn * 0.06
	_box("rev_posts", timber, post + Vector3.UP * (h * 0.45), Basis(along, 0.2) * b, Vector3(0.1, h * 0.9, 0.1))


## A sandbag: a squashed, slumped pillow.
func _bag_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 16
	m.rings = 9
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var p := v[i]
		# a flat-bottomed, boxy pillow, sagging in the middle
		var q := Vector3(signf(p.x) * pow(absf(p.x) * 2.0, 0.55) * 0.5, signf(p.y) * pow(absf(p.y) * 2.0, 0.8) * 0.5, signf(p.z) * pow(absf(p.z) * 2.0, 0.6) * 0.5)
		q.y = maxf(q.y, -0.42)
		q.y -= 0.08 * (1.0 - absf(q.x) * 2.0) * (1.0 if q.y > 0.0 else 0.0)
		v[i] = q * BAG
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st2 := SurfaceTool.new()
	st2.create_from(am, 0)
	st2.generate_normals()
	return st2.commit()


## A corrugated sheet one unit square (x along, y up), the waves across it.
func _corrugated_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 48
	for side in 2:
		for i in nx:
			var x0 := float(i) / nx - 0.5
			var x1 := float(i + 1) / nx - 0.5
			var z0 := sin(x0 * TAU * 8.0) * 0.012
			var z1 := sin(x1 * TAU * 8.0) * 0.012
			var n0 := Vector3(-cos(x0 * TAU * 8.0) * 0.6, 0, 1).normalized()
			var n1 := Vector3(-cos(x1 * TAU * 8.0) * 0.6, 0, 1).normalized()
			var zs := 1.0 if side == 0 else -1.0
			var quad := [[Vector3(x0, -0.5, z0), n0, Vector2(x0 + 0.5, 1)], [Vector3(x1, -0.5, z1), n1, Vector2(x1 + 0.5, 1)],
				[Vector3(x1, 0.5, z1), n1, Vector2(x1 + 0.5, 0)], [Vector3(x0, 0.5, z0), n0, Vector2(x0 + 0.5, 0)]]
			var order := [0, 2, 1, 0, 3, 2] if side == 0 else [0, 1, 2, 0, 2, 3]
			for k: int in order:
				st.set_normal(quad[k][1] * Vector3(1, 1, zs))
				st.set_uv(quad[k][2])
				st.add_vertex(quad[k][0] - Vector3(0, 0, 0.004 * zs))
	st.generate_tangents()
	return st.commit()


# --- parapet, parados, fire steps -----------------------------------------------------
## Sandbags along the top of the fire trench's front wall (a gap here and
## there to look through) and a lower row along the parados.
func _parapets() -> void:
	var mesh := _bag_mesh()
	var mat := _mat("burlap", 0.5)
	for c: Vector2i in maze.open_cells:
		var k: String = maze.kind[c]
		var front := k in ["fire", "op", "sap"] and not maze.open_cells.has(c + Vector2i(0, -1))
		var back := k in ["fire", "traverse", "support"] and not maze.open_cells.has(c + Vector2i(0, 1)) and rng.randf() < 0.6 and maze.wall(c, Vector2i(0, 1)) != "ramp"
		for pass_ in 2:
			if (pass_ == 0 and not front) or (pass_ == 1 and not back):
				continue
			var dir := Vector2i(0, -1) if pass_ == 0 else Vector2i(0, 1)
			var e := _edge(c, dir)
			var a: Vector2 = e.a
			var b: Vector2 = e.b
			var out := Vector2(dir) * (0.45 if pass_ == 0 else 0.4)
			var rows := 2
			var gap := rng.randf() < 0.35 and pass_ == 0
			for r in rows:
				var n := 3
				for i in n:
					if gap and r == rows - 1 and i == 1:
						continue                # a loophole
					var t := (i + 0.5 + (0.5 if r % 2 else 0.0)) / n
					if t > 1.0:
						continue
					var p2 := a.lerp(b, t) + out + Vector2(dir) * (r * -0.03)
					var y := maze.ground_height(p2.x, p2.y)
					var along := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
					var bb := Basis(along, Vector3.UP, along.cross(Vector3.UP)).rotated(Vector3.UP, rng.randf_range(-0.15, 0.15))
					_add("bags", mesh, mat, Transform3D(bb.scaled_local(Vector3(rng.randf_range(0.9, 1.05), rng.randf_range(0.85, 1.1), 1.0)), Vector3(p2.x, y + BAG.y * (0.35 + r * 0.9), p2.y)))


## Each fire bay's step: a board top and a boarded riser under the front wall.
func _fire_steps() -> void:
	var planks := _mat("board", 1.6)
	for c: Vector2i in maze.bays:
		var r := maze._rect(c)
		var z_edge := c.y * maze.cell + TrenchMaze.EDGE
		var depth_ := z_edge - r.position.y
		var x0 := r.position.x + 0.05
		var x1 := r.end.x - 0.05
		var cx := (x0 + x1) * 0.5
		var top := maze.ground_height(cx, z_edge - depth_ * 0.5)
		var base := maze.ground_height(cx, z_edge + 0.2)
		_box("step_planks", planks, Vector3(cx, top - 0.02, z_edge - depth_ * 0.5), Basis(), Vector3(x1 - x0, 0.05, depth_))
		var h := top - base
		if h > 0.1:
			_box("step_planks", planks, Vector3(cx, base + h * 0.5, z_edge + 0.01), Basis(), Vector3(x1 - x0, h + 0.05, 0.04))


# --- duckboards --------------------------------------------------------------------
func _duckboards() -> void:
	var wood := _mat("board", 1.0)
	var dark := _mat("timber", 0.8)
	for d: Dictionary in maze.duckboards:
		var a: Vector3 = d.a
		var b: Vector3 = d.b
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var along := (b - a).normalized()
		var flat := Vector3(along.x, 0, along.z).normalized()
		var side := flat.cross(Vector3.UP).normalized()
		var basis := Basis(side, along.cross(side).normalized(), -along).orthonormalized()
		# two runners under the slats, sagging a little
		for s in [-0.24, 0.24]:
			var mid: Vector3 = (a + b) * 0.5 + side * float(s) + Vector3.DOWN * 0.065
			_box("db_runners", dark, mid, basis, Vector3(0.06, 0.07, length))
		var n := int(length / 0.2)
		for i in n:
			var t := (i + 0.5) / n
			if rng.randf() < float(d.broken) * 0.8:
				continue                          # a missing slat: the water under it shows
			var p := a.lerp(b, t)
			var bb := basis
			var drop := 0.0
			if rng.randf() < float(d.broken):
				bb = bb.rotated(along, rng.randf_range(-0.25, 0.25)).rotated(side, rng.randf_range(-0.15, 0.15))
				drop = rng.randf_range(0.02, 0.07)
			bb = bb.rotated(Vector3.UP, rng.randf_range(-0.03, 0.03))
			var w := rng.randf_range(0.6, 0.66)
			_box("db_slats", wood, p + Vector3.DOWN * (0.015 + drop) + side * rng.randf_range(-0.02, 0.02), bb, Vector3(w, 0.035, 0.12))


# --- water -------------------------------------------------------------------------------
func _water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water_mud.gdshader")
	mat.set_shader_parameter("noise_tex", tex("noise"))
	for wa: Dictionary in maze.water:
		var r: Rect2 = wa.rect
		var pm := PlaneMesh.new()
		pm.size = r.size
		pm.subdivide_width = 0
		pm.subdivide_depth = 0
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.get_center().x, wa.level, r.get_center().y)
		add_child(mi)


# --- landmarks -----------------------------------------------------------------------------
func _landmarks() -> void:
	for l: Dictionary in maze.landmarks:
		match String(l.kind):
			"exit":
				_bunker_portal(l.cell, l.dir)
			"dugout":
				_dugout(l)
			"tree":
				_tree(l.cell)
			"gunpit":
				_gun(l)
			"op":
				_op(l.cell)


## The way down: a concrete bunker entrance in the end wall of the fire trench.
func _bunker_portal(c: Vector2i, dir: Vector2i) -> void:
	var conc := _mat("timber", 0.8)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.36, 0.35, 0.33)
	cm.roughness = 0.85
	cm.albedo_texture = load("res://art/level/wall_conc.png")
	cm.uv1_triplanar = true
	cm.uv1_world_triplanar = true
	cm.uv1_scale = Vector3.ONE * 0.5
	var e := _edge(c, dir)
	var mid: Vector2 = (e.a + e.b) * 0.5
	var inward := Vector3(-dir.x, 0, -dir.y)
	var along := Vector3(dir.y, 0, dir.x)
	var base := maze.floor_height(Vector3(mid.x, 0, mid.y) + inward * 0.5)
	var p := Vector3(mid.x, base, mid.y)
	var b := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	# a squat concrete face with a doorway, steel lintel, the clown's mark
	_box("conc", cm, p + Vector3.UP * 1.25 - inward * 0.25, b, Vector3(2.6, 2.6, 0.5))
	_box("conc", cm, p + Vector3.UP * 2.3 + inward * 0.05, b, Vector3(2.0, 0.35, 0.2))
	var door := StandardMaterial3D.new()
	door.albedo_color = Color(0.03, 0.03, 0.03)
	_box("portal_dark", door, p + Vector3.UP * 1.05 + inward * 0.02, b, Vector3(1.15, 2.1, 0.05))
	_collide(p + Vector3.UP * 1.25 - inward * 0.25, b, Vector3(2.6, 2.6, 0.5))
	var sign := Label3D.new()
	sign.text = "H.Q. BUNKER"
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.modulate = Color(0.85, 0.82, 0.75)
	sign.position = p + Vector3.UP * 2.62 + inward * 0.16
	sign.basis = Basis.looking_at(-inward, Vector3.UP)
	add_child(sign)


## A dugout: a timber-framed entrance off the trench, a roof of beams,
## corrugated iron and sandbags over the pit, and a lantern inside.
func _dugout(l: Dictionary) -> void:
	# (under the roof: the sky's light shut out of the timber and the iron)
	var timber := _mat("dug_timber", 0.8)
	var iron := _mat("dug_iron", 1.0)
	var cells: Array[Vector2i] = []
	for c: Vector2i in maze.open_cells:
		if maze.kind[c] == "dugout" and Vector2(c).distance_to(Vector2(l.cell)) < 2.5:
			cells.append(c)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c in cells:
		lo = lo.min(Vector2(c) * maze.cell)
		hi = hi.max((Vector2(c) + Vector2.ONE) * maze.cell)
	var mid := (lo + hi) * 0.5
	var floor_y := maze.floor_height(Vector3(mid.x, 0, mid.y))
	# the roof clears a man everywhere under it: 2.3 m over the highest of
	# its floor (the floor rises toward the door, where the entrance trench is shallower)
	var top_floor := floor_y
	var under: Array[Vector2i] = cells.duplicate()
	under.append(l.entrance)
	for c in under:
		for u in [0.15, 0.5, 0.85]:
			for v in [0.15, 0.5, 0.85]:
				top_floor = maxf(top_floor, maze.floor_height(Vector3((c.x + u) * maze.cell, 0, (c.y + v) * maze.cell)))
	# and up to the ground round it, so the earth walls (which lean back as
	# they rise) meet the roof instead of showing daylight between
	var ground := INF
	for c in cells:
		for dir in Maze.DIRS:
			var n: Vector2i = c + dir
			if not maze.open_cells.has(n):
				ground = minf(ground, maze.floor_height(Vector3((n.x + 0.5) * maze.cell, 0, (n.y + 0.5) * maze.cell)))
	var roof_y := top_floor + 2.3
	if ground < INF:
		roof_y = clampf(ground - 0.1, roof_y, top_floor + 3.0)
	# out past the room's floor into the earth all round: the walls lean back
	# as they rise, and a roof cut to the floor left daylight down the sides
	var size := hi - lo + Vector2(1.4, 1.4)
	# beams across, iron over them, bags on top
	var n := int(size.x / 0.45)
	for i in n:
		var x := lo.x - 0.7 + (i + 0.5) * size.x / n
		_box("dug_beams", timber, Vector3(x, roof_y, mid.y), Basis(), Vector3(0.14, 0.16, size.y))
	_box("dug_iron", iron, Vector3(mid.x, roof_y + 0.1, mid.y), Basis(), Vector3(size.x, 0.03, size.y))
	var bag := _mat("burlap", 0.5)
	var mesh := _bag_mesh()
	for r in 2:
		for i in int(size.x / 0.5):
			for j in int(size.y / 0.32):
				var p := Vector3(lo.x - 0.6 + (i + 0.5) * 0.5 + (0.25 if j % 2 else 0.0), roof_y + 0.18 + r * 0.13, lo.y - 0.6 + (j + 0.5) * 0.32)
				if p.x > hi.x + 0.65:
					continue
				_add("bags", mesh, bag, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), p))
	_collide(Vector3(mid.x, roof_y + 0.12, mid.y), Basis(), Vector3(size.x, 0.3, size.y))
	# boarded headers round the room under the roof's edge: where an earth
	# wall leans back from the floor, they close the gap up to the roof
	var hdr := 1.3
	for side: Array in [[Vector2(lo.x, mid.y), Vector2(0, 1), hi.y - lo.y], [Vector2(hi.x, mid.y), Vector2(0, 1), hi.y - lo.y], [Vector2(mid.x, lo.y), Vector2(1, 0), hi.x - lo.x], [Vector2(mid.x, hi.y), Vector2(1, 0), hi.x - lo.x]]:
		var at: Vector2 = side[0]
		var along: Vector2 = side[1]
		var out := Vector2(along.y, along.x) * signf((at - mid).dot(Vector2(along.y, along.x)))
		# not across the door
		var door_c := Vector2(l.entrance) * maze.cell + Vector2.ONE * maze.cell * 0.5
		if (door_c - mid).dot(out) > 0.0 and absf((door_c - at).dot(along)) < (side[2] as float) * 0.5:
			continue
		var c3 := Vector3(at.x + out.x * 0.04, roof_y - hdr * 0.5, at.y + out.y * 0.04)
		var sz := Vector3(0.06, hdr, side[2] + 0.2) if along.y != 0 else Vector3(side[2] + 0.2, hdr, 0.06)
		_box("dug_beams", timber, c3, Basis(), sz)
	# entrance frame where the stub meets it
	var ent: Vector2i = l.entrance
	var dir: Vector2i = l.dir
	var e := _edge(ent, dir)
	var fm: Vector2 = (e.a + e.b) * 0.5 + Vector2(dir) * 0.05
	var fy := maze.floor_height(Vector3(fm.x, 0, fm.y))
	var across := Vector3(dir.y, 0, dir.x)
	# heavy door frame: 1.25 m between the posts, the lintel 2.25 m up (the
	# player is 0.6 m across and 1.8 m tall; a soldier the same)
	for s in [-0.72, 0.72]:
		_box("dug_beams", timber, Vector3(fm.x, fy + 1.1, fm.y) + across * s, Basis(), Vector3(0.18, 2.4, 0.18))
	_box("dug_beams", timber, Vector3(fm.x, fy + 2.33, fm.y), Basis(Vector3.UP, PI * 0.5 if dir.y == 0 else 0.0), Vector3(1.75, 0.2, 0.2))
	# props under the roof: posts holding it up at the back corners
	for cc: Vector2 in [Vector2(lo.x + 0.12, lo.y + 0.12), Vector2(hi.x - 0.12, lo.y + 0.12), Vector2(lo.x + 0.12, hi.y - 0.12), Vector2(hi.x - 0.12, hi.y - 0.12)]:
		var py := maze.floor_height(Vector3(cc.x, 0, cc.y))
		_box("dug_beams", timber, Vector3(cc.x, (py + roof_y) * 0.5, cc.y), Basis(), Vector3(0.16, roof_y - py, 0.16))
	# a lantern burning inside: warm light, kept low so the corners stay dark
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.66, 0.36)
	lamp.light_energy = 1.5
	lamp.omni_range = 4.6
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = true
	lamp.position = Vector3(mid.x, roof_y - 0.45, mid.y)
	add_child(lamp)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.8, 0.5)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.65, 0.3)
	glass.emission_energy_multiplier = 3.0
	_box("lantern", glass, lamp.position + Vector3.DOWN * 0.05, Basis(), Vector3(0.1, 0.16, 0.1))


## Footbridges over the main trenches: rough planks across two stringers, a
## sill on the ground at each end, a handrail on one side only (the other
## open, nothing to stop a body going over). The deck, stringers and rail
## have collision; soldiers walk the deck (TrenchMaze.bridge_at).
func _bridges() -> void:
	var planks := _mat("planks_wet", 1.4)
	var timber := _mat("timber", 0.8)
	for b: Dictionary in maze.bridges:
		var a: Vector3 = b.a
		var e: Vector3 = b.b
		var wdt: float = b.width
		var along := (e - a).normalized()
		var flat := Vector3(along.x, 0, along.z).normalized()
		var side := flat.cross(Vector3.UP).normalized()
		var up := along.cross(side).normalized() * -1.0
		if up.y < 0.0:
			up = -up
		var length := a.distance_to(e)
		var basis := Basis(side, up, -along).orthonormalized()
		var mid := (a + e) * 0.5
		# stringers along the deck's edges (not under it: headroom for a man
		# walking the trench below), running out onto the ground
		for s: float in [-1.0, 1.0]:
			# (flush with the deck: no kerb for a body to catch on going over the side)
			var p: Vector3 = mid + side * s * (wdt * 0.5 + 0.06) - up * 0.07
			_box("br_beams", timber, p, basis, Vector3(0.12, 0.14, length + 0.6))
			_collide(p, basis, Vector3(0.12, 0.14, length + 0.6))
		# planks across, uneven: gaps, a few short or split, some sagging
		var n := int(length / 0.21)
		for i in n:
			var t := (i + 0.5) / n
			if rng.randf() < 0.05 and i > 1 and i < n - 2:
				continue                                  # one missing
			var lw := wdt * (rng.randf_range(0.62, 0.85) if rng.randf() < 0.12 else rng.randf_range(0.95, 1.05))
			var shift := (wdt - lw) * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
			var bb := basis.rotated(along, rng.randf_range(-0.03, 0.03)).rotated(up, rng.randf_range(-0.04, 0.04))
			var p := a.lerp(e, t) + side * shift - up * (0.03 + rng.randf_range(0.0, 0.012))
			_box("br_planks", planks, p, bb, Vector3(lw, 0.05, 0.19))
		# the walking surface: one smooth box for collision under the planks
		_collide(mid - up * 0.035, basis, Vector3(wdt, 0.06, length))
		# a sill across each end, bedded in the ground
		for end: Vector3 in [a, e]:
			_box("br_beams", timber, end - up * 0.12, basis, Vector3(wdt + 0.3, 0.16, 0.2))
		# a handrail on one side: posts and a rail
		var rs := 1.0 if rng.randf() < 0.5 else -1.0
		b["rail_side"] = side * rs          # (which side the rail is on: tests, the AI)
		var posts := maxi(2, int(length / 1.3) + 1)
		for i in posts:
			var t := float(i) / (posts - 1)
			var p := a.lerp(e, t) + side * rs * (wdt * 0.5 - 0.04) + Vector3.UP * 0.45
			var lean := Basis(flat, rng.randf_range(-0.05, 0.05))
			_box("br_beams", timber, p, lean, Vector3(0.08, 0.95, 0.08))
			_collide(p, lean, Vector3(0.08, 0.95, 0.08))
		var rail := mid + side * rs * (wdt * 0.5 - 0.04) + Vector3.UP * 0.9
		_box("br_beams", timber, rail, basis, Vector3(0.07, 0.07, length))
		_collide(rail, basis, Vector3(0.07, 0.07, length))


## The ramps up out of the trench: boards laid up them as rough steps, a
## post either side of the mouth.
func _ramps() -> void:
	var planks := _mat("planks_wet", 1.4)
	var timber := _mat("timber", 0.8)
	for r: Dictionary in maze.ramps:
		var foot: Vector2 = r.foot
		var head: Vector2 = r.head
		var u := (head - foot).normalized()
		var side := Vector3(-u.y, 0, u.x)
		var n := int(TrenchMaze.RAMP_LEN / 0.42)
		for i in n:
			var t := (i + 0.5) / n
			var p2 := foot.lerp(head, t)
			var y := maze.ground_height(p2.x, p2.y)
			var bb := Basis(Vector3.UP, atan2(u.x, u.y)).rotated(side, rng.randf_range(-0.05, 0.05))
			_box("step_planks", planks, Vector3(p2.x, y + 0.01, p2.y), bb, Vector3(r.width * 0.8, 0.04, 0.16))
		for s: float in [-1.0, 1.0]:
			var p2: Vector2 = foot + Vector2(side.x, side.z) * s * (float(r.width) * 0.5 + 0.12)
			var y := maze.ground_height(p2.x, p2.y)
			_box("rev_posts", timber, Vector3(p2.x, y + 0.9, p2.y), Basis(), Vector3(0.12, 1.9, 0.12))


## The shattered tree: a stripped trunk snapped off, splintered at the top.
func _tree(c: Vector2i) -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.17, 0.15, 0.13)
	bark.roughness = 0.9
	bark.albedo_texture = tex("timber")
	bark.uv1_scale = Vector3(1, 3, 1)
	# on the top ground beside the junction, the side with most room
	var best := Vector2.ZERO
	for dir in Maze.DIRS:
		if not maze.open_cells.has(c + dir):
			best = Vector2(dir)
			break
	var base2 := (Vector2(c) + Vector2(0.5, 0.5)) * maze.cell + best * (maze.cell * 0.5 + 1.1)
	var y := maze.ground_height(base2.x, base2.y) - 0.3
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.34
	trunk.height = 4.6
	trunk.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = trunk
	mi.material_override = bark
	mi.position = Vector3(base2.x, y + 2.3, base2.y)
	mi.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))
	add_child(mi)
	var top := mi.position + mi.basis.y * 2.3
	for i in 6:
		var sp := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(0.3, 0.9)
		_box("splinters", bark, top + sp + mi.basis.y * h * 0.5, mi.basis * Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0.0, 0.25)), Vector3(0.05, h, 0.04))
	for i in 2:
		var at := mi.position + mi.basis.y * rng.randf_range(0.0, 1.8)
		var dir := Vector3(cos(i * 2.6 + 0.4), 0.5, sin(i * 2.6 + 0.4)).normalized()
		var length := rng.randf_range(0.6, 1.3)
		_box("splinters", bark, at + dir * length * 0.5, Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT), Vector3(0.09, 0.09, length))
	var cs_pos := mi.position
	_collide(cs_pos, mi.basis, Vector3(0.5, 4.6, 0.5))


## A ruined field gun in its pit: wheels, a snapped trail, the barrel down.
func _gun(l: Dictionary) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.17, 0.18, 0.15)
	steel.roughness = 0.6
	steel.metallic = 0.4
	var wood := _mat("timber", 0.8)
	var cells: Array[Vector2i] = []
	for c: Vector2i in maze.open_cells:
		if maze.kind[c] == "gunpit" and Vector2(c).distance_to(Vector2(l.cell)) < 3.5:
			cells.append(c)
	var mid := Vector3.ZERO
	for c in cells:
		mid += Vector3((c.x + 0.5) * maze.cell, 0, (c.y + 0.5) * maze.cell)
	mid /= maxf(cells.size(), 1)
	mid.y = maze.floor_height(mid)
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	for s in [-0.75, 0.75]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.6
		wheel.bottom_radius = 0.6
		wheel.height = 0.1
		wheel.radial_segments = 14
		var mi := MeshInstance3D.new()
		mi.mesh = wheel
		mi.material_override = wood
		mi.basis = b * Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		mi.position = mid + b * Vector3(s, 0.55, 0)
		add_child(mi)
	_box("gun_steel", steel, mid + b * Vector3(0, 0.75, 0.3), b * Basis(Vector3.RIGHT, -0.12), Vector3(0.18, 0.18, 2.3))
	_box("gun_steel", steel, mid + b * Vector3(0, 0.95, -0.35), b * Basis(Vector3.RIGHT, 0.1), Vector3(1.5, 0.9, 0.04))
	_box("gun_steel", steel, mid + b * Vector3(0.05, 0.3, -1.4), b * Basis(Vector3.UP, 0.25) * Basis(Vector3.RIGHT, 0.3), Vector3(0.14, 0.12, 1.7))
	_collide(mid + b * Vector3(0, 0.7, 0), b, Vector3(1.6, 1.3, 1.2))


## The observation post at the head of a sap: sandbags round it and a periscope.
func _op(c: Vector2i) -> void:
	var p := maze.cell_center(c)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.21, 0.18)
	steel.roughness = 0.55
	var top := maze.ground_height(p.x, p.z - 1.0)
	_box("periscope", steel, Vector3(p.x + 0.3, (p.y + top) * 0.5 + 0.4, p.z - 0.55), Basis(), Vector3(0.07, top - p.y + 0.8, 0.09))
	_box("periscope", steel, Vector3(p.x + 0.3, top + 0.75, p.z - 0.58), Basis(), Vector3(0.09, 0.12, 0.14))


# --- the far battlefield ---------------------------------------------------------------------
## Beyond the carved ground: the battlefield to the horizon, low and coarse,
## churned and shell-holed toward No Man's Land (z < 0), lost in haze.
func _far() -> void:
	var m := maze
	var mat := ground_material()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var holes := FastNoiseLite.new()
	holes.seed = rng.randi()
	holes.noise_type = FastNoiseLite.TYPE_CELLULAR
	holes.frequency = 0.09
	_far_noise = noise
	_far_holes = holes
	var inner := Rect2(m.origin, Vector2((m.hx - 1) * TrenchMaze.RES, (m.hz - 1) * TrenchMaze.RES))
	var step := 2.5
	var reach := 260.0
	var lo := inner.position - Vector2.ONE * reach
	var n := int((inner.size.x + reach * 2.0) / step) + 1
	var nz := int((inner.size.y + reach * 2.0) / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize(n * nz)
	for iz in nz:
		for ix in n:
			var x := lo.x + ix * step
			var z := lo.y + iz * step
			var q := Vector2(x, z)
			var h := noise.get_noise_2d(x, z) * 2.2
			# shell holes everywhere out there, thickest in No Man's Land
			var nml := 1.0 - smoothstep(-30.0, 10.0, z)
			var cell := holes.get_noise_2d(x, z)
			h += (minf(cell, 0.2) - 0.2) * (1.2 + 1.8 * nml)
			# meet the carved ground at its edge
			var dx := maxf(maxf(inner.position.x - x, x - inner.end.x), 0.0)
			var dz := maxf(maxf(inner.position.y - z, z - inner.end.y), 0.0)
			var out := Vector2(dx, dz).length()
			var edge_h := m.ground_height(clampf(x, inner.position.x, inner.end.x), clampf(z, inner.position.y, inner.end.y))
			h = lerpf(edge_h - 0.04, h, smoothstep(0.0, 25.0, out))
			if out <= 0.0:
				h = edge_h - 0.12              # under the carved ground: hidden
			hs[ix + iz * n] = h
	for iz in nz:
		for ix in n:
			var i := ix + iz * n
			var hl := hs[maxi(ix - 1, 0) + iz * n]
			var hr := hs[mini(ix + 1, n - 1) + iz * n]
			var hd := hs[ix + maxi(iz - 1, 0) * n]
			var hu := hs[ix + mini(iz + 1, nz - 1) * n]
			var x := lo.x + ix * step
			var z := lo.y + iz * step
			st.set_normal(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			var nml := 1.0 - smoothstep(-30.0, 10.0, z)
			st.set_color(Color(0.6, 0.0, lerpf(1.0, 0.4, nml), 0.0))
			st.set_uv2(Vector2(1.0, 0.0))           # open sky out there
			st.add_vertex(Vector3(x, hs[i], z))
	for iz in nz - 1:
		for ix in n - 1:
			var x := lo.x + (ix + 0.5) * step
			var z := lo.y + (iz + 0.5) * step
			if inner.grow(-step).has_point(Vector2(x, z)):
				continue
			var a := ix + iz * n
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	var mi := MeshInstance3D.new()
	mi.name = "Battlefield"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The ground height anywhere: the carved ground where there is some, the far
## battlefield (as _far makes it) beyond.
func height_at(x: float, z: float) -> float:
	var m := maze
	var inner := Rect2(m.origin, Vector2((m.hx - 1) * TrenchMaze.RES, (m.hz - 1) * TrenchMaze.RES))
	if inner.grow(-0.5).has_point(Vector2(x, z)):
		return m.ground_height(x, z)
	var h := _far_noise.get_noise_2d(x, z) * 2.2
	var nml := 1.0 - smoothstep(-30.0, 10.0, z)
	h += (minf(_far_holes.get_noise_2d(x, z), 0.2) - 0.2) * (1.2 + 1.8 * nml)
	var dx := maxf(maxf(inner.position.x - x, x - inner.end.x), 0.0)
	var dz := maxf(maxf(inner.position.y - z, z - inner.end.y), 0.0)
	var edge_h := m.ground_height(clampf(x, inner.position.x, inner.end.x), clampf(z, inner.position.y, inner.end.y))
	return lerpf(edge_h - 0.04, h, smoothstep(0.0, 25.0, Vector2(dx, dz).length()))


## The wrecked sandbag posts out in No Man's Land (their middles, on the
## ground): cover for the soldiers out there (TrenchBattle's field).
var nml_posts: Array[Vector3] = []


# --- materials for the clutter -----------------------------------------------------
func _plain(key: String, col: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


# --- barbed wire ---------------------------------------------------------------------
## Entanglements in front of the fire trench: screw pickets in two staggered
## rows, wire strung between them and criss-crossed, concertina coils along
## the front, sagging and broken in places; gaps where the saps go out. No
## collision (nobody goes out there); the wire sways a little in the wind.
func _wire() -> void:
	var m := maze
	var picket := _mat("iron", 1.6)
	var lines := PackedVector3Array()
	var cols := PackedColorArray()
	var sap_x: Array[float] = []
	for l: Dictionary in m.landmarks:
		if l.kind == "op":
			sap_x.append((l.cell.x + 0.5) * m.cell)
	var x0 := -6.0
	var x1 := m.w * m.cell + 6.0
	for row in 2:
		var z := 0.4 - row * 1.6
		var posts: Array[Vector3] = []
		var x := x0 + row * 1.2
		while x < x1:
			var gap := false
			for sx in sap_x:
				if absf(x - sx) < 2.2:
					gap = true
			var p := Vector3(x + rng.randf_range(-0.3, 0.3), 0, z + rng.randf_range(-0.35, 0.35))
			p.y = height_at(p.x, p.z)
			if gap or rng.randf() < 0.08:
				posts.append(Vector3.INF)               # a gap, or a picket blown out
			else:
				var lean := Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0.0, 0.25 if rng.randf() < 0.8 else 0.6))
				var hgt := rng.randf_range(1.0, 1.3)
				_box("wire_pickets", picket, p + lean * Vector3.UP * hgt * 0.5, lean, Vector3(0.035, hgt, 0.035))
				posts.append(p + lean * Vector3.UP * hgt)
				if posts.size() % 4 == 0:
					rattle_spots.append(p + Vector3.UP * 0.8)
			x += rng.randf_range(2.2, 2.8)
		# strands between neighbouring pickets at three heights, sagging
		for i in posts.size() - 1:
			var a := posts[i]
			var b := posts[i + 1]
			if a == Vector3.INF or b == Vector3.INF:
				continue
			for k in 3:
				if rng.randf() < 0.15:
					continue                            # cut
				var f: float = [1.0, 0.65, 0.3][k]
				var pa := Vector3(a.x, lerpf(height_at(a.x, a.z), a.y, f), a.z)
				var pb := Vector3(b.x, lerpf(height_at(b.x, b.z), b.y, f), b.z)
				_strand(lines, cols, pa, pb, rng.randf_range(0.05, 0.25))
			# and one diagonally across, top to foot
			if rng.randf() < 0.7:
				_strand(lines, cols, a, Vector3(b.x, height_at(b.x, b.z) + 0.1, b.z), 0.1)
	# concertina coils along the front
	var z := -2.6
	var x := x0
	while x < x1:
		var length := rng.randf_range(4.0, 8.0)
		var gap := false
		for sx in sap_x:
			if absf(x + length * 0.5 - sx) < 4.0:
				gap = true
		if not gap and rng.randf() < 0.85:
			_coil(lines, cols, Vector3(x, 0, z + rng.randf_range(-0.4, 0.4)), length, rng.randf_range(0.35, 0.5))
		x += length + rng.randf_range(0.5, 2.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wire_sway.gdshader")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Wire"
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_wire_lines = lines


var _wire_lines := PackedVector3Array()


## One strand of wire from a to b, sagging, with barbs. Vertex colour R is
## how free it is to sway (0 at the pickets).
func _strand(lines: PackedVector3Array, cols: PackedColorArray, a: Vector3, b: Vector3, sag: float) -> void:
	var n := 10
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var sway_a := 4.0 * (t - 1.0 / n) * (1.0 - (t - 1.0 / n))
		lines.append(prev)
		cols.append(Color(sway_a, 0, 0))
		lines.append(p)
		cols.append(Color(4.0 * t * (1.0 - t), 0, 0))
		# a barb: a little cross
		var bdir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * 0.03
		lines.append(p - bdir)
		cols.append(Color(4.0 * t * (1.0 - t), 0, 0))
		lines.append(p + bdir)
		cols.append(Color(4.0 * t * (1.0 - t), 0, 0))
		prev = p


## A concertina coil lying along x: loops of wire, squashed and trodden down
## in places, clinging to the ground.
func _coil(lines: PackedVector3Array, cols: PackedColorArray, start: Vector3, length: float, radius: float) -> void:
	var loops := int(length / 0.22)
	var steps := loops * 12
	var prev := Vector3.INF
	for i in steps + 1:
		var t := float(i) / steps
		var a := t * loops * TAU
		var x := start.x + t * length
		var squash := 0.6 + 0.4 * sin(t * 7.0 + start.x)
		var p := Vector3(x + sin(a) * 0.05, 0, start.z + cos(a) * radius)
		var g := height_at(p.x, p.z)
		p.y = g + radius * squash * (1.0 + sin(a))
		if prev != Vector3.INF:
			lines.append(prev)
			cols.append(Color(0.4, 0, 0))
			lines.append(p)
			cols.append(Color(0.4, 0, 0))
		prev = p


# --- No Man's Land ---------------------------------------------------------------------
## Out past the wire: dead trees, a wrecked limber, rubbish of war, and
## rainwater standing in the deeper shell holes.
func _no_mans_land() -> void:
	var bark := _plain("bark", Color(0.13, 0.115, 0.1), 0.9)
	for i in 7:
		var p := Vector3(rng.randf_range(-40.0, maze.w * maze.cell + 40.0), 0, rng.randf_range(-70.0, -8.0))
		_dead_tree(p, bark, rng.randf_range(2.5, 6.5))
	# behind the lines too, a few
	for i in 3:
		var p := Vector3(rng.randf_range(-30.0, maze.w * maze.cell + 30.0), 0, maze.d * maze.cell + rng.randf_range(14.0, 40.0))
		_dead_tree(p, bark, rng.randf_range(3.0, 7.0))
	# a wrecked limber, a wheel off it
	var wood := _mat("timber", 0.8)
	var lp := Vector3(rng.randf_range(10.0, maze.w * maze.cell - 10.0), 0, rng.randf_range(-22.0, -12.0))
	lp.y = height_at(lp.x, lp.z)
	var lb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, 0.35)
	_box("nml_wood", wood, lp + lb * Vector3(0, 0.5, 0), lb, Vector3(1.1, 0.7, 1.6))
	_wheel(lp + lb * Vector3(0.75, 0.5, 0.3), lb * Basis(Vector3.FORWARD, PI * 0.5), wood)
	_wheel(lp + Vector3(2.0, 0.08, 1.0), Basis(), wood)
	# water in the deep shell holes
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water_mud.gdshader")
	mat.set_shader_parameter("noise_tex", tex("noise"))
	for cr: Vector4 in maze.crater_list:
		if cr.w < 0.55:
			continue
		var bottom := maze.ground_height(cr.x, cr.y)
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * cr.z * 1.4
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.set_instance_shader_parameter("round", 1.0)     # a disc, not a slab over the rim
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cr.x, bottom + cr.w * 0.35, cr.y)
		add_child(mi)


# --- the horizon -----------------------------------------------------------------------
## What stands against the sky: a broken village and a church tower far off
## (the haze turns them to blue-grey shapes), more shattered trees at every
## distance, a few wrecked sandbag posts out in No Man's Land, and now and
## then figures moving far away along the skyline. Nothing out here collides;
## nothing out here is in the fight.
func _horizon() -> void:
	var mid := Vector3(maze.w * maze.cell * 0.5, 0, maze.d * maze.cell * 0.5)
	var ruin := _plain("ruin", Color(0.16, 0.15, 0.145), 0.95)
	var church := false
	var placed: Array[float] = []
	for i in 11:
		# around the far edge, thickest ahead, never straight behind the player's line
		var a := -PI * 0.5 + rng.randf_range(-1.25, 1.25) * (1.0 if i < 8 else 2.2)
		var ok := true
		for b in placed:
			if absf(angle_difference(a, b)) < 0.16:
				ok = false
		if not ok:
			continue
		placed.append(a)
		var r := rng.randf_range(170.0, 250.0)
		var at := mid + Vector3(cos(a), 0, sin(a)) * r
		at.y = height_at(at.x, at.z) - 0.5
		var face := Basis(Vector3.UP, a + PI * 0.5 + rng.randf_range(-0.3, 0.3))
		if not church and i == 2:
			church = true
			_ruined_church(at, face, ruin)
		else:
			_ruined_block(at, face, ruin)
	# shattered trees: near, middle and far, sparse
	var bark := _plain("bark", Color(0.13, 0.115, 0.1), 0.9)
	for i in 16:
		var a := rng.randf_range(-PI, 0.0) if i < 12 else rng.randf_range(0.0, PI)
		var r := rng.randf_range(40.0, 150.0)
		var p := mid + Vector3(cos(a), 0, sin(a)) * r
		_dead_tree(p, bark, rng.randf_range(3.0, 9.0) * (1.0 + r / 300.0))
	# wrecked sandbag posts in No Man's Land: a broken horseshoe, half fallen
	var bags := _bag_mesh()
	var burlap := _mat("burlap", 1.0)
	for i in 3:
		var c := Vector3(rng.randf_range(12.0, maze.w * maze.cell - 12.0), 0, rng.randf_range(-48.0, -16.0))
		nml_posts.append(c)
		var turn := rng.randf() * TAU
		for k in 3:
			if rng.randf() < 0.25:
				continue                                    # a side blown away
			var ang := turn + (k - 1) * 1.1
			var along := Vector3(cos(ang), 0, sin(ang))
			var inn := along.cross(Vector3.UP)
			var foot := c - inn * 1.3
			foot.y = height_at(foot.x, foot.z) - 0.08
			_bag_wall(bags, burlap, foot, along, inn, rng.randf_range(1.2, 2.2), rng.randf_range(0.3, 0.75))
			# bags thrown off it
			for j in rng.randi_range(1, 3):
				var q := foot + along * rng.randf_range(-1.5, 1.5) - inn * rng.randf_range(0.6, 2.2)
				q.y = height_at(q.x, q.z) + 0.06
				var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3))
				_add("nml_bags", bags, burlap, Transform3D(bb, q))
	# figures far off on the skyline, now and then
	var dark := _plain("far_figure", Color(0.06, 0.06, 0.065), 1.0)
	for i in 3:
		var f := FarFigures.new()
		f.name = "FarFigures%d" % i
		add_child(f)
		var a := -PI * 0.5 + rng.randf_range(-1.0, 1.0)
		if i == 2:
			a = PI * 0.5 + rng.randf_range(-0.8, 0.8)               # one party behind the lines
		var r := rng.randf_range(85.0, 150.0)
		var c := mid + Vector3(cos(a), 0, sin(a)) * r
		var dir := Vector3(-sin(a), 0, cos(a)) * (1.0 if rng.randf() < 0.5 else -1.0)
		f.setup(self, c - dir * 30.0, c + dir * 30.0, rng.randi_range(1, 3), dark, rng.randi())


## A broken building: walls of different heights with ragged tops, a chimney.
func _ruined_block(at: Vector3, face: Basis, mat: Material) -> void:
	var w := rng.randf_range(8.0, 16.0)
	var dpt := rng.randf_range(6.0, 10.0)
	var h := rng.randf_range(4.0, 9.0)
	for side in 4:
		if rng.randf() < 0.3:
			continue                                         # gone
		var along := face * (Vector3.RIGHT if side % 2 == 0 else Vector3.BACK)
		var length := w if side % 2 == 0 else dpt
		var off := face * (Vector3(0, 0, dpt * 0.5) if side == 0 else Vector3(0, 0, -dpt * 0.5) if side == 2 else Vector3(w * 0.5, 0, 0) if side == 1 else Vector3(-w * 0.5, 0, 0))
		# the wall in slices, each a different height: a ragged top
		var n := int(length / 1.6)
		for k in n:
			var t := (k + 0.5) / n - 0.5
			var hh := h * rng.randf_range(0.25, 1.0) * (1.0 - absf(t) * 0.5)
			var cpos := at + off + along * t * length + Vector3.UP * hh * 0.5
			_box("ruins", mat, cpos, Basis(along.cross(Vector3.UP), Vector3.UP, along).orthonormalized(), Vector3(0.6, hh, length / n + 0.05))
	if rng.randf() < 0.6:
		var ch := rng.randf_range(h, h * 1.6)
		_box("ruins", mat, at + face * Vector3(rng.randf_range(-w, w) * 0.4, ch * 0.5, 0), face, Vector3(1.0, ch, 1.0))
	# rubble at the foot
	for k in 6:
		var q := at + face * Vector3(rng.randf_range(-w, w) * 0.6, 0, rng.randf_range(-dpt, dpt) * 0.6)
		var sz := rng.randf_range(1.5, 4.0)
		_box("ruins", mat, q + Vector3.UP * sz * 0.15, Basis(Vector3.UP, rng.randf() * TAU), Vector3(sz, sz * 0.4, sz * 0.8))


## The church: the stump of the tower, its top shot away, the nave walls
## broken down to the windows.
func _ruined_church(at: Vector3, face: Basis, mat: Material) -> void:
	var th := rng.randf_range(16.0, 22.0)
	_box("ruins", mat, at + Vector3.UP * th * 0.5, face, Vector3(5.0, th, 5.0))
	# the broken crown: corners left standing
	for k in 4:
		if rng.randf() < 0.35:
			continue
		var c := Vector3(1 if k % 2 == 0 else -1, 0, 1 if k < 2 else -1) * 2.1
		var extra := rng.randf_range(1.5, 4.5)
		_box("ruins", mat, at + face * (c + Vector3.UP * (th + extra * 0.5)), face, Vector3(0.9, extra, 0.9))
	# nave behind it
	var length := rng.randf_range(18.0, 26.0)
	for side in [-1, 1]:
		var n := 9
		for k in n:
			var t := (k + 0.5) / n
			var hh := rng.randf_range(2.5, 8.0) * (1.0 - t * 0.4)
			var pos := at + face * Vector3(side * 4.5, hh * 0.5, 2.5 + t * length)
			_box("ruins", mat, pos, face, Vector3(0.8, hh, length / n + 0.05))


func _dead_tree(p: Vector3, bark: Material, h: float) -> void:
	p.y = height_at(p.x, p.z) - 0.2
	var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.18))
	var tr := CylinderMesh.new()
	tr.top_radius = rng.randf_range(0.06, 0.16)
	tr.bottom_radius = rng.randf_range(0.2, 0.32)
	tr.height = h
	tr.radial_segments = 8
	tr.rings = 1
	_add("dead_trunk_%d" % int(h * 2.0), tr, bark, Transform3D(tilt, p + tilt * Vector3.UP * h * 0.5))
	for k in rng.randi_range(1, 3):
		var at := p + tilt * Vector3.UP * h * rng.randf_range(0.5, 0.95)
		var dir := (tilt * Vector3(cos(k * 2.3 + p.x), rng.randf_range(0.2, 0.8), sin(k * 2.3 + p.x))).normalized()
		var length := rng.randf_range(0.5, 1.6)
		_box("splinters", bark, at + dir * length * 0.5, Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT), Vector3(0.07, 0.07, length))


func _wheel(at: Vector3, b: Basis, wood: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.65
	cm.bottom_radius = 0.65
	cm.height = 0.09
	cm.radial_segments = 16
	cm.rings = 1
	_add("wheels", cm, wood, Transform3D(b, at))


# --- clutter -------------------------------------------------------------------------------
## A spot against wall `dir` of cell `c`, `t` along it (0..1) and `out` from
## it: on the floor, facing into the trench (-Z toward the wall).
func _spot(c: Vector2i, dir: Vector2i, t: float, out: float) -> Transform3D:
	var e := _edge(c, dir)
	var a: Vector2 = e.a
	var b: Vector2 = e.b
	var inward: Vector2 = e.inward
	# stand clear of the lining (sandbags stick out a hand's breadth or more)
	out += {"sandbag": 0.33, "timber": 0.07, "iron": 0.07, "wattle": 0.08, "broken": 0.12}.get(maze.wall(c, dir), 0.0)
	var p2 := a.lerp(b, clampf(t, 0.1, 0.9)) + inward * out
	var p := Vector3(p2.x, 0, p2.y)
	p.y = maze.floor_height(p)
	var basis := Basis.looking_at(Vector3(-inward.x, 0, -inward.y), Vector3.UP)
	return Transform3D(basis, p)


## One piece of clutter by kind, at `xf` (on the floor, -Z toward the wall).
## Big pieces get collision.
func _thing(kind: String, xf: Transform3D) -> void:
	var b := xf.basis
	var p := xf.origin
	var board := _mat("board", 1.0)
	var olive := _plain("olive", Color(0.17, 0.18, 0.12), 0.7, 0.2)
	var steel := _plain("steel", Color(0.2, 0.2, 0.19), 0.45, 0.6)
	var tin := _plain("tin", Color(0.32, 0.3, 0.27), 0.35, 0.8)
	var khaki := _plain("khaki", Color(0.23, 0.2, 0.13), 0.9)
	var wool := _plain("wool", Color(0.13, 0.12, 0.11), 1.0)
	var wood := _mat("timber", 0.8)
	match kind:
		"crate":
			var s := Vector3(rng.randf_range(0.55, 0.7), rng.randf_range(0.3, 0.38), rng.randf_range(0.36, 0.42))
			var bb := b.rotated(Vector3.UP, rng.randf_range(-0.15, 0.15))
			var at := p + b * Vector3(0, s.y * 0.5, -s.z * 0.5 + 0.02)
			_box("crates", board, at, bb, s)
			_box("crate_bands", olive, at, bb, s + Vector3(-s.x * 0.7, 0.01, 0.01))
			_collide(at, bb, s)
		"crates":
			_thing("crate", xf)
			_thing("crate", Transform3D(b.rotated(Vector3.UP, rng.randf_range(-0.2, 0.2)), p + Vector3.UP * 0.36))
		"shell_box":
			var at := p + b * Vector3(0, 0.15, -0.25)
			_box("crates", board, at, b, Vector3(0.75, 0.3, 0.3))
			_collide(at, b, Vector3(0.75, 0.3, 0.3))
			for k in 3:
				var cm := CylinderMesh.new()
				cm.top_radius = 0.035
				cm.bottom_radius = 0.042
				cm.height = 0.45
				cm.radial_segments = 8
				_add("shells", cm, _plain("brass", Color(0.45, 0.35, 0.16), 0.35, 0.8), Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), p + b * Vector3(-0.2 + k * 0.2, 0.34, -0.1)))
		"shovel":
			var lean := b * Basis(Vector3.RIGHT, 0.32)
			_box("tool_handles", wood, p + lean * Vector3(0, 0.55, -0.12), lean, Vector3(0.035, 1.0, 0.035))
			_box("tool_steel", steel, p + lean * Vector3(0, 0.1, -0.1), lean, Vector3(0.2, 0.26, 0.015))
		"pickaxe":
			var lean := b * Basis(Vector3.RIGHT, 0.35) * Basis(Vector3.FORWARD, 0.15)
			_box("tool_handles", wood, p + lean * Vector3(0, 0.45, -0.12), lean, Vector3(0.04, 0.85, 0.04))
			_box("tool_steel", steel, p + lean * Vector3(0, 0.88, -0.12), lean * Basis(Vector3.FORWARD, 0.1), Vector3(0.6, 0.05, 0.04))
		"rifle":
			var lean := b * Basis(Vector3.RIGHT, 0.3)
			_box("rifles", wood, p + lean * Vector3(0, 0.55, -0.1), lean, Vector3(0.05, 1.1, 0.05))
			_box("tool_steel", steel, p + lean * Vector3(0, 1.0, -0.1), lean, Vector3(0.02, 0.4, 0.02))
		"rifle_rack":
			_box("rack", wood, p + b * Vector3(0, 0.15, -0.15), b, Vector3(0.9, 0.06, 0.12))
			_box("rack", wood, p + b * Vector3(0, 0.95, -0.08), b, Vector3(0.9, 0.06, 0.08))
			for k in rng.randi_range(1, 3):
				_thing("rifle", Transform3D(b, p + b * Vector3(-0.3 + k * 0.25, 0, 0)))
		"helmet":
			var hm := SphereMesh.new()
			hm.radius = 0.16
			hm.height = 0.12
			hm.is_hemisphere = true
			hm.radial_segments = 12
			hm.rings = 4
			var hb := Basis(Vector3.UP, rng.randf() * TAU) * (Basis(Vector3.RIGHT, PI) if rng.randf() < 0.3 else Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)))
			_add("helmets", hm, olive, Transform3D(hb, p + b * Vector3(0, 0.03, -0.25)))
			var brim := CylinderMesh.new()
			brim.top_radius = 0.2
			brim.bottom_radius = 0.2
			brim.height = 0.01
			brim.radial_segments = 14
			_add("helmet_brims", brim, olive, Transform3D(hb, p + b * Vector3(0, 0.03, -0.25)))
		"tins":
			for k in rng.randi_range(2, 5):
				var cm := CylinderMesh.new()
				cm.top_radius = 0.04
				cm.bottom_radius = 0.04
				cm.height = 0.1
				cm.radial_segments = 8
				var tb := Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), PI * 0.5 if rng.randf() < 0.6 else 0.0)
				_add("tins", cm, tin, Transform3D(tb, p + b * Vector3(rng.randf_range(-0.3, 0.3), 0.04, -rng.randf_range(0.1, 0.4))))
		"bag":
			var bm := SphereMesh.new()
			bm.radius = 0.5
			bm.height = 1.0
			bm.radial_segments = 8
			bm.rings = 5
			_add("bags_kit", bm, khaki, Transform3D(b.rotated(Vector3.UP, rng.randf()).scaled(Vector3(0.4, 0.22, 0.28)), p + b * Vector3(0, 0.1, -0.2)))
		"blanket":
			_box("blankets", wool, p + b * Vector3(0, 0.05, -0.3), b.rotated(Vector3.UP, rng.randf_range(-0.4, 0.4)) * Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1)), Vector3(0.9, 0.08, 0.5))
		"stretcher":
			var lean := b * Basis(Vector3.RIGHT, 0.22)
			for sx in [-0.26, 0.26]:
				_box("tool_handles", wood, p + lean * Vector3(sx, 1.0, -0.12), lean, Vector3(0.04, 2.1, 0.04))
			_box("canvas_sheets", _plain("canvas", Color(0.28, 0.25, 0.18), 0.95), p + lean * Vector3(0, 1.0, -0.13), lean, Vector3(0.5, 1.6, 0.01))
		"telephone":
			var at := p + b * Vector3(0, 0.0, -0.2)
			_box("phones", _plain("phone", Color(0.14, 0.12, 0.08), 0.6), at + Vector3.UP * 0.07, b, Vector3(0.24, 0.14, 0.11))
			_box("tool_steel", steel, at + Vector3.UP * 0.16 + b * Vector3(0, 0, 0.0), b, Vector3(0.2, 0.025, 0.025))
		"reel":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.22
			cm.bottom_radius = 0.22
			cm.height = 0.25
			cm.radial_segments = 12
			_add("reels", cm, wood, Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), p + b * Vector3(0, 0.22, -0.25)))
			var core := CylinderMesh.new()
			core.top_radius = 0.17
			core.bottom_radius = 0.17
			core.height = 0.22
			_add("reel_wire", core, _plain("wirecoil", Color(0.1, 0.09, 0.08), 0.5, 0.6), Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), p + b * Vector3(0, 0.22, -0.25)))
		"iron_sheet":
			var lean := b * Basis(Vector3.RIGHT, 0.25)
			_add("rev_iron", _corrugated_mesh(), _mat("iron", 1.0), Transform3D(lean.scaled_local(Vector3(0.7, 1.6, 1.0)), p + lean * Vector3(0, 0.8, -0.15)))
		"bunk":
			for sx in [-0.85, 0.85]:
				for sz in [-0.05, -0.75]:
					_box("rack", wood, p + b * Vector3(sx, 0.35, sz), b, Vector3(0.08, 0.7, 0.08))
			_box("crates", board, p + b * Vector3(0, 0.55, -0.4), b, Vector3(1.8, 0.05, 0.75))
			_box("blankets", wool, p + b * Vector3(0.1, 0.6, -0.4), b * Basis(Vector3.UP, 0.05), Vector3(1.4, 0.06, 0.6))
			_collide(p + b * Vector3(0, 0.35, -0.4), b, Vector3(1.8, 0.7, 0.8))


## Clutter where people lived and fought: kit in the dugouts, shell boxes in
## the gun pit, a telephone at the OP, odds and ends along the walls (never
## much in the way: big pieces only where there is room).
func _props() -> void:
	var m := maze
	# along the trenches: every few cells something small against a wall
	var small := ["shovel", "pickaxe", "helmet", "tins", "bag", "blanket", "rifle", "tins", "helmet", "iron_sheet"]
	var cells: Array = m.open_cells.keys()
	cells.sort()
	var i := 0
	for c: Vector2i in cells:
		i += 1
		var k: String = m.kind[c]
		if c == m.start_cell or c == m.exit_cell:
			continue
		var walls: Array[Vector2i] = []
		for dir in Maze.DIRS:
			if not m.open_cells.has(c + dir) and m.wall(c, dir) != "ramp":
				walls.append(dir)
		if walls.is_empty():
			continue
		var dir: Vector2i = walls[rng.randi() % walls.size()]
		if k in ["junction", "stub"] and rng.randf() < 0.5:
			_thing(["crates", "crate", "shell_box"][rng.randi() % 3], _spot(c, dir, rng.randf_range(0.25, 0.75), 0.05))
		elif rng.randf() < 0.16:
			var what: String = small[rng.randi() % small.size()]
			if what == "iron_sheet" and m.wall(c, dir) != "earth":
				what = "tins"
			_thing(what, _spot(c, dir, rng.randf_range(0.2, 0.8), 0.02))
	# the dugouts: a bunk, crates, a rack of rifles, a telephone, a blanket
	for l: Dictionary in m.landmarks:
		match String(l.kind):
			"dugout":
				var room: Array[Vector2i] = []
				for c: Vector2i in m.open_cells:
					if m.kind[c] == "dugout" and Vector2(c).distance_to(Vector2(l.cell)) < 2.5:
						room.append(c)
				var back: Vector2i = l.dir
				var placed := 0
				for c in room:
					if m.open_cells.has(c + back):
						continue
					if placed == 0:
						_thing("bunk", _spot(c, back, 0.5, 0.02))
					elif placed == 1:
						_thing("crates", _spot(c, back, 0.5, 0.02))
						_thing("telephone", Transform3D(_spot(c, back, 0.5, 0.02).basis, _spot(c, back, 0.5, 0.02).origin + Vector3.UP * 0.72))
					elif placed == 2:
						# the bigger dugout's third bay: a second bunk, ammunition beside it
						_thing("bunk", _spot(c, back, 0.45, 0.02))
						_thing("shell_box", _spot(c, back, 0.92, 0.02))
					placed += 1
				for c in room:
					for dir in Maze.DIRS:
						if dir != back and dir != -back and not m.open_cells.has(c + dir) and rng.randf() < 0.5:
							_thing(["rifle_rack", "bag", "helmet", "tins", "reel"][rng.randi() % 5], _spot(c, dir, 0.5, 0.02))
							break
				drip_spots.append(m.cell_center(l.entrance) + Vector3.UP * 1.9)
			"gunpit":
				var c: Vector2i = l.cell
				for dir in Maze.DIRS:
					if not m.open_cells.has(c + dir):
						_thing("shell_box", _spot(c, dir, 0.5, 0.02))
						break
			"op":
				var c: Vector2i = l.cell
				for dir in Maze.DIRS:
					if not m.open_cells.has(c + dir) and dir != Vector2i(0, -1):
						_thing("telephone", _spot(c, dir, 0.4, 0.02))
						_thing("reel", _spot(c, dir, 0.75, 0.02))
						break
	# at the start: a stretcher left against the wall
	var s := m.start_cell
	for dir in Maze.DIRS:
		if not m.open_cells.has(s + dir) and dir.y == 0:
			_thing("stretcher", _spot(s, dir, 0.5, 0.0))
			break
	# up on the ground: a few sheets of iron, duckboards stacked, a coil of wire
	for k in 8:
		var p := Vector3(rng.randf_range(0.0, m.w * m.cell), 0, rng.randf_range(m.FIRE_ROW * m.cell + 4.0, m.d * m.cell))
		var near: Dictionary = m._nearest(p.x, p.z)
		if near.d < 1.2:
			continue
		p.y = m.ground_height(p.x, p.z)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		if k % 2 == 0:
			_add("rev_iron", _corrugated_mesh(), _mat("iron", 1.0), Transform3D((b * Basis(Vector3.RIGHT, PI * 0.5 - 0.06)).scaled_local(Vector3(0.7, 1.8, 1.0)), p + Vector3.UP * 0.03))
		else:
			_thing("crate", Transform3D(b, p))
	# creak sources: some lined walls
	for c: Vector2i in cells:
		if creak_spots.size() > 24:
			break
		for dir in Maze.DIRS:
			var t := m.wall(c, dir)
			if t in ["timber", "broken", "iron"] and rng.randf() < 0.15:
				creak_spots.append(_spot(c, dir, 0.5, 0.0).origin + Vector3.UP * 1.2)
	# drips: where the flooded water stands
	for wa: Dictionary in m.water:
		drip_spots.append(Vector3((wa.rect as Rect2).get_center().x, float(wa.level) + 1.5, (wa.rect as Rect2).get_center().y))


# --- signs ----------------------------------------------------------------------------------
## Boards on posts at the junctions: where each trench goes, painted by hand.
const TRENCH_NAMES := ["PICCADILLY", "OXFORD ST", "BOND ST", "STRAND", "REGENT ST", "BAKER ST", "WHITEHALL", "PARK LANE"]


func _signs() -> void:
	var m := maze
	var names := TRENCH_NAMES.duplicate()
	names.shuffle()
	var comm_names := {}
	for t: String in m.trenches:
		if t.begins_with("comm") or t.begins_with("rear"):
			comm_names[t] = names.pop_back() if not names.is_empty() else "C.T."
	var signs := 0
	for t: String in comm_names:
		var cells: Array = m.trenches[t]
		if cells.is_empty():
			continue
		# at each end of the communication trench, where it meets a line
		for c: Vector2i in [cells[0], cells.back()]:
			var walls: Array[Vector2i] = []
			for dir in Maze.DIRS:
				if not m.open_cells.has(c + dir):
					walls.append(dir)
			if walls.is_empty():
				continue
			var xf := _spot(c, walls[0], 0.5, 0.0)
			var text: String = comm_names[t]
			var to_front: bool = (cells.back() as Vector2i).y < (cells[0] as Vector2i).y
			if t.begins_with("rear"):
				text += "\nTO THE FRONT  ^" if c == cells.back() else "\nTO H.Q."
			else:
				text += "\n" + ("FIRE TRENCH ->" if to_front else "SUPPORT ->")
			_sign(xf, text)
			signs += 1
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			var xf := _spot(l.entrance, Vector2i(l.dir.y, l.dir.x), 0.3, 0.0)
			_sign(xf, "DUG-OUT No.%d" % (signs % 9 + 1), 0.55)
			signs += 1


func _sign(xf: Transform3D, text: String, height := 1.6) -> void:
	var wood := _mat("timber", 0.8)
	var b := xf.basis
	var p := xf.origin
	var top := maze.ground_height(p.x - b.z.x * 0.4, p.z - b.z.z * 0.4)
	var post_h := maxf(height, top - p.y + 0.3)
	_box("sign_posts", wood, p + b * Vector3(0.0, post_h * 0.5, -0.06), b, Vector3(0.07, post_h, 0.07))
	var board_at := p + b * Vector3(0.0, minf(post_h - 0.1, 1.75), 0.0)
	var bb := b.rotated(b.z, rng.randf_range(-0.12, 0.12))
	_box("sign_boards", _mat("board", 1.0), board_at, bb, Vector3(0.75, 0.3, 0.025))
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.0036
	l.modulate = Color(0.86, 0.83, 0.76, 0.92)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.transform = Transform3D(bb, board_at + bb.z * 0.015)
	add_child(l)


# --- carnival corruption ---------------------------------------------------------------------
## Rare, discovered, not advertised: a cracked porcelain clown head in the
## mud, a faded circus bill in a dugout, a broken wind-up toy, a music box
## (it plays now and then), a red balloon caught on the wire, a sign daubed on
## the timber.
func _carnival() -> void:
	var m := maze
	# the porcelain head, half sunk in a communication trench
	var comm := []
	for t: String in m.trenches:
		if t.begins_with("comm"):
			comm.append(t)
	if not comm.is_empty():
		var cells: Array = m.trenches[comm[rng.randi() % comm.size()]]
		var c: Vector2i = cells[cells.size() / 2]
		for dir in Maze.DIRS:
			if not m.open_cells.has(c + dir):
				var xf := _spot(c, dir, 0.35, 0.06)
				_porcelain_head(xf.origin + Vector3.UP * 0.02, xf.basis)
				break
	var dugs: Array = m.landmarks.filter(func(l: Dictionary) -> bool: return l.kind == "dugout")
	if not dugs.is_empty():
		var l: Dictionary = dugs[0]
		var room: Array[Vector2i] = []
		for c: Vector2i in m.open_cells:
			if m.kind[c] == "dugout" and Vector2(c).distance_to(Vector2(l.cell)) < 2.5:
				room.append(c)
		# the bill on a side wall, the music box on a crate
		for c in room:
			for dir in Maze.DIRS:
				if not m.open_cells.has(c + dir) and dir != l.dir:
					var xf := _spot(c, dir, 0.5, 0.03)
					var bill := MeshInstance3D.new()
					var q := QuadMesh.new()
					q.size = Vector2(0.42, 0.63)
					bill.mesh = q
					var bm := StandardMaterial3D.new()
					bm.albedo_texture = tex("circus_bill")
					bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					bm.roughness = 0.9
					bill.material_override = bm
					bill.transform = Transform3D(xf.basis.rotated(xf.basis.z, rng.randf_range(-0.08, 0.08)), xf.origin + Vector3.UP * 1.25)
					add_child(bill)
					var crate := Transform3D(xf.basis, xf.origin + xf.basis.x * 0.5)
					_thing("crate", crate)
					music_box = crate.origin + Vector3.UP * 0.4
					var box := _plain("musicbox", Color(0.3, 0.12, 0.08), 0.4)
					_box("music_box", box, music_box + Vector3.UP * 0.05, xf.basis.rotated(Vector3.UP, 0.4), Vector3(0.16, 0.09, 0.11))
					_box("music_box_lid", box, music_box + Vector3.UP * 0.13 + xf.basis.z * 0.05, xf.basis.rotated(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, -1.1), Vector3(0.16, 0.01, 0.11))
					_box("tool_steel", _plain("steel", Color(0.2, 0.2, 0.19), 0.45, 0.6), music_box + Vector3.UP * 0.07 + xf.basis.x * 0.09, xf.basis, Vector3(0.05, 0.012, 0.012))
					# a broken watch beside it
					var w := CylinderMesh.new()
					w.top_radius = 0.025
					w.bottom_radius = 0.025
					w.height = 0.008
					_add("watch", w, _plain("brass", Color(0.45, 0.35, 0.16), 0.35, 0.8), Transform3D(Basis(), music_box + xf.basis.x * -0.15 + Vector3.UP * 0.005))
					break
			if music_box != Vector3.INF:
				break
	# a broken wind-up toy: a tin clown on its side in a stub
	for c: Vector2i in m.open_cells:
		if m.kind[c] == "stub" and rng.randf() < 0.5:
			for dir in Maze.DIRS:
				if not m.open_cells.has(c + dir):
					var xf := _spot(c, dir, 0.6, 0.12)
					var tb := xf.basis * Basis(Vector3.FORWARD, PI * 0.5)
					var red := _plain("toy_red", Color(0.42, 0.06, 0.05), 0.35, 0.5)
					var white := _plain("toy_white", Color(0.6, 0.58, 0.52), 0.35, 0.4)
					_box("toy", red, xf.origin + Vector3.UP * 0.035, tb, Vector3(0.05, 0.09, 0.04))
					var hm := SphereMesh.new()
					hm.radius = 0.025
					hm.height = 0.05
					_add("toy_head", hm, white, Transform3D(tb, xf.origin + Vector3.UP * 0.035 + tb.y * 0.065))
					_box("tool_steel", _plain("steel", Color(0.2, 0.2, 0.19), 0.45, 0.6), xf.origin + Vector3.UP * 0.035 - tb.z * 0.03, tb, Vector3(0.03, 0.008, 0.02))
					break
			break
	# a red balloon caught on the wire, in sight of the fire step
	if _wire_lines.size() > 40:
		var at := _wire_lines[rng.randi_range(0, _wire_lines.size() / 2) * 2]
		var bal := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.38
		bal.mesh = sm
		var bm := ShaderMaterial.new()
		bm.shader = load("res://shaders/balloon_sway.gdshader")
		bal.material_override = bm
		bal.position = at + Vector3.UP * 0.75
		bal.name = "Balloon"
		add_child(bal)
		var st := ImmediateMesh.new()
		st.surface_begin(Mesh.PRIMITIVE_LINES)
		st.surface_add_vertex(at)
		st.surface_add_vertex(at + Vector3.UP * 0.57)
		st.surface_end()
		var string := MeshInstance3D.new()
		string.mesh = st
		string.material_override = _plain("string", Color(0.6, 0.6, 0.6), 0.9)
		add_child(string)
	# a sign daubed on a timber lining
	for c: Vector2i in m.open_cells:
		for dir in Maze.DIRS:
			if m.wall(c, dir) == "timber" and rng.randf() < 0.04:
				var xf := _spot(c, dir, 0.5, 0.045)
				var q := QuadMesh.new()
				q.size = Vector2(0.75, 0.75)
				var mi := MeshInstance3D.new()
				mi.mesh = q
				var sm := StandardMaterial3D.new()
				sm.albedo_texture = tex("symbol")
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.roughness = 0.6
				mi.material_override = sm
				mi.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 1.0)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				return


func _porcelain_head(at: Vector3, b: Basis) -> void:
	var porcelain := _plain("porcelain", Color(0.62, 0.6, 0.56), 0.25)
	var dark := _plain("porcelain_dark", Color(0.03, 0.025, 0.02), 0.9)
	var red := _plain("porcelain_red", Color(0.4, 0.05, 0.04), 0.35)
	var hb := b * Basis(Vector3.RIGHT, 0.6) * Basis(Vector3.FORWARD, 0.5)
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.24
	_add("porcelain_head", sm, porcelain, Transform3D(hb, at))
	for sx in [-0.04, 0.04]:
		var e := SphereMesh.new()
		e.radius = 0.016
		e.height = 0.03
		_add("porcelain_eyes", e, dark, Transform3D(hb, at + hb * Vector3(sx, 0.03, 0.095)))
	var nose := SphereMesh.new()
	nose.radius = 0.02
	nose.height = 0.04
	_add("porcelain_nose", nose, red, Transform3D(hb, at + hb * Vector3(0, -0.005, 0.11)))
	_box("porcelain_cracks", dark, at + hb * Vector3(0.03, 0.06, 0.08), hb * Basis(Vector3.FORWARD, 0.6), Vector3(0.004, 0.09, 0.004))
	_box("porcelain_cracks", dark, at + hb * Vector3(-0.02, -0.05, 0.085), hb, Vector3(0.07, 0.006, 0.004))


# --- wind ----------------------------------------------------------------------------------------
## Things the wind moves: torn canvas over some dugout doors, telephone cable
## looped along the walls, scraps of paper.
func _wind_things() -> void:
	var m := maze
	var canvas := ShaderMaterial.new()
	canvas.shader = load("res://shaders/cloth_wind.gdshader")
	canvas.set_shader_parameter("albedo", Color(0.26, 0.23, 0.17))
	for l: Dictionary in m.landmarks:
		if l.kind != "dugout" or rng.randf() < 0.4:
			continue
		var ent: Vector2i = l.entrance
		var dir: Vector2i = l.dir
		var e := _edge(ent, dir)
		var fm: Vector2 = (e.a + e.b) * 0.5 + Vector2(dir) * 0.12
		var fy := m.floor_height(Vector3(fm.x, 0, fm.y))
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.5)
		pm.subdivide_width = 6
		pm.subdivide_depth = 10
		pm.orientation = PlaneMesh.FACE_Z
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = canvas
		var across := Vector3(dir.y, 0, dir.x)
		mi.transform = Transform3D(Basis(across, Vector3.UP, across.cross(Vector3.UP)), Vector3(fm.x, fy + 1.25, fm.y) + across * 0.2)
		add_child(mi)
	# telephone cable along a few lined walls, looping between nails
	var cable := PackedVector3Array()
	var ccol := PackedColorArray()
	for name_: String in ["support", "fire"]:
		var cells: Array = m.trenches.get(name_, [])
		var run := 0
		for c: Vector2i in cells:
			for dir in [Vector2i(0, 1), Vector2i(0, -1)]:
				if m.wall(c, dir) in ["timber", "iron", "wattle"]:
					var e := _edge(c, dir)
					var inward: Vector2 = e.inward
					var a2: Vector2 = e.a + inward * 0.06
					var b2: Vector2 = e.b + inward * 0.06
					var y := m.floor_height(Vector3(a2.x, 0, a2.y)) + 1.55
					_strand(cable, ccol, Vector3(a2.x, y, a2.y), Vector3(b2.x, y + rng.randf_range(-0.05, 0.05), b2.y), rng.randf_range(0.08, 0.2))
					run += 1
					break
	if not cable.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = cable
		arrays[Mesh.ARRAY_COLOR] = ccol
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/wire_sway.gdshader")
		mat.set_shader_parameter("colour", Color(0.05, 0.045, 0.04))
		mat.set_shader_parameter("amount", 0.025)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# scraps of paper lifting off the ground now and then at a few junctions
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.55, 0.52, 0.45)
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	paper.roughness = 0.9
	var made := 0
	for c: Vector2i in m.open_cells:
		if made >= 4:
			break
		if m.kind[c] in ["junction", "support"] and rng.randf() < 0.06:
			var p := CPUParticles3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.09, 0.12)
			q.material = paper
			p.mesh = q
			p.amount = 3
			p.lifetime = 6.0
			p.explosiveness = 0.0
			p.randomness = 1.0
			p.direction = Vector3(1, 0.6, 0.3)
			p.spread = 40.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 1.0
			p.gravity = Vector3(0.35, -0.25, 0.1)
			p.angular_velocity_min = -200.0
			p.angular_velocity_max = 200.0
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(0.6, 0.02, 0.6)
			p.particle_flag_rotate_y = true
			p.position = m.cell_center(c) + Vector3.UP * 0.05
			p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8))
			add_child(p)
			made += 1


# --- smoke -----------------------------------------------------------------------------------------
## Slow grey plumes rising from distant shellfire, leaning with the wind.
func _smoke() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://art/level/fx_smoke.png")
	mat.albedo_color = Color(0.5, 0.49, 0.47, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	_smoke_mat = mat
	# the distant battle: tall smoke columns leaning with the wind, a few of
	# them over fires. All far out (the fog softens the farthest), mostly
	# ahead over No Man's Land, one or two behind the lines.
	var col_mat := mat.duplicate() as StandardMaterial3D
	col_mat.albedo_texture = load("res://art/level/fx_billow.png")
	col_mat.albedo_color = Color(1, 1, 1, 1)
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_texture = load("res://art/level/fx_fire.png")
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.vertex_color_use_as_albedo = true
	fire_mat.disable_receive_shadows = true
	fire_mat.no_depth_test = false
	fire_mat.disable_fog = true         # the haze would wash an additive flame to pink
	fire_mat.albedo_color = Color(0.8, 0.8, 0.8)
	var mid := maze.w * maze.cell * 0.5
	var spots: Array[Vector3] = []
	var fires := 0
	for i in 7:
		var behind := i >= 6
		var at := Vector3.ZERO
		for _try in 12:
			var a := rng.randf_range(-PI * 0.9, -PI * 0.1)
			if behind:
				a = rng.randf_range(PI * 0.2, PI * 0.8)
			var r := rng.randf_range(90.0, 240.0)
			at = Vector3(mid + cos(a) * r, 0, sin(a) * r + (maze.d * maze.cell if behind else 0.0))
			var ok := true
			for o in spots:
				if Vector2(o.x - at.x, o.z - at.z).length() < 45.0:
					ok = false
			if ok:
				break
		spots.append(at)
		at.y = height_at(at.x, at.z) - 1.0
		var fire := not behind and fires < 4 and rng.randf() < 0.6
		var size := rng.randf_range(0.8, 1.5)
		# fire smoke is black; the rest dark grey to dirty grey
		var shade := rng.randf_range(0.06, 0.09) if fire else rng.randf_range(0.1, 0.19)
		add_child(make_column(col_mat, at, size, shade, rng.randf()))
		if fire:
			fires += 1
			add_child(make_fire(fire_mat, at + Vector3(0, 0.6, 0), size))


var _smoke_mat: StandardMaterial3D


## A tall billowing smoke column: slow, dense at the root, spreading and
## thinning as it rises, carried off by the wind. `shade`: how dark.
## The ground mist (shaders/ground_mist.gdshader): a fog volume over the whole
## battlefield, low and drifting, thicker over No Man's Land. Forward+ only
## (the volumetric fog); the depth haze carries the distance without it.
var mist: FogVolume


func _mist() -> void:
	var w := maze.w * maze.cell
	var d := maze.d * maze.cell
	var lo := Vector3(-60.0, -3.2, -110.0)
	var hi := Vector3(w + 60.0, 5.0, d + 30.0)
	mist = FogVolume.new()
	mist.name = "GroundMist"
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	mist.size = hi - lo
	mist.position = (hi + lo) * 0.5
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/ground_mist.gdshader")
	fm.set_shader_parameter("noise_tex", tex("noise"))
	fm.set_shader_parameter("nml_z", TrenchMaze.FIRE_ROW * maze.cell - 2.5)
	mist.material = fm
	add_child(mist)


static func make_column(mat: Material, at: Vector3, size: float, shade: float, phase: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 20.0 * size
	q.material = mat
	p.mesh = q
	p.amount = 90
	p.lifetime = 40.0
	p.preprocess = 40.0                  # already standing when the floor loads
	p.randomness = 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.5 * size
	p.direction = Vector3(0.1, 1, 0)
	p.spread = 8.0
	p.initial_velocity_min = 1.6 * size
	p.initial_velocity_max = 2.4 * size
	p.gravity = Vector3(0.22, 0.0, 0.06) # the wind takes the top
	p.damping_min = 0.03
	p.damping_max = 0.05
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.max_value = 5.0
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.4, 1.4))
	curve.add_point(Vector2(1, 2.3))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	var s := shade
	grad.set_color(0, Color(s, s * 0.97, s * 0.94, 0.0))
	grad.add_point(0.05, Color(s, s * 0.97, s * 0.94, 0.95))
	grad.add_point(0.55, Color(s * 1.5, s * 1.48, s * 1.46, 0.7))
	grad.set_color(grad.get_point_count() - 1, Color(s * 2.0, s * 2.0, s * 2.0, 0.0))
	p.color_ramp = grad
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -1.5
	p.angular_velocity_max = 1.5
	p.position = at
	p.seed = int(phase * 100000.0)
	p.use_fixed_seed = false
	p.visibility_aabb = AABB(Vector3(-80, -10, -80), Vector3(160, 160, 160))
	p.emitting = true
	return p


## A distant fire: low licking flames and a few sparks, restrained, flickering
## by itself. No light: it is too far off to light the trench.
static func make_fire(mat: Material, at: Vector3, size: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(6.0, 7.5) * size
	q.material = mat
	p.mesh = q
	p.amount = 24
	p.lifetime = 1.4
	p.randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.6, 0.2, 2.6) * size
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.2, 0.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.18, 0.0))
	grad.add_point(0.12, Color(1.0, 0.5, 0.15, 0.75))
	grad.add_point(0.6, Color(0.75, 0.25, 0.06, 0.4))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.08, 0.02, 0.0))
	p.color_ramp = grad
	p.angle_min = -15.0
	p.angle_max = 15.0
	p.preprocess = 2.0
	p.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 14, 20))
	root.add_child(p)
	# sparks, lifted by the heat
	var sp := CPUParticles3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE * 0.35
	sq.material = mat
	sp.mesh = sq
	sp.amount = 12
	sp.lifetime = 3.0
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(2.0, 0.5, 2.0) * size
	sp.direction = Vector3.UP
	sp.spread = 25.0
	sp.initial_velocity_min = 2.0
	sp.initial_velocity_max = 5.0
	sp.gravity = Vector3(0.6, 0.4, 0.1)
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.6, 0.25, 1.0))
	sg.set_color(sg.get_point_count() - 1, Color(0.8, 0.2, 0.05, 0.0))
	sp.color_ramp = sg
	sp.preprocess = 3.0
	sp.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 30, 30))
	root.add_child(sp)
	return root




## A smoke plume at `at`, `size` scaling it. `once`: a single puff (a shell).
static func make_plume(mat: Material, at: Vector3, size: float, once := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 6.0 * size
	q.material = mat
	p.mesh = q
	p.amount = 14 if not once else 10
	p.lifetime = 22.0 if not once else 14.0
	p.one_shot = once
	p.explosiveness = 0.0 if not once else 0.85
	p.direction = Vector3(0.25, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 1.0 * size
	p.initial_velocity_max = 1.8 * size
	p.gravity = Vector3(0.45, 0.05, 0.1)
	p.damping_min = 0.02
	p.damping_max = 0.05
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 2.4))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.42, 0.41, 0.4, 0.0))
	grad.add_point(0.1, Color(0.38, 0.37, 0.36, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(0.6, 0.6, 0.6, 0.0))
	p.color_ramp = grad
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.position = at
	p.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 80, 120))
	p.emitting = true
	if once:
		p.finished.connect(p.queue_free)
	return p


func smoke_material() -> StandardMaterial3D:
	return _smoke_mat
