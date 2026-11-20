class_name ClownAnatomy
## The anatomy a blown-open body shows: skull and brain, rib cage, lungs and
## heart, spine, liver, stomach, bowel, kidneys, pelvis. Real anatomy, not
## made-up shapes: BodyParts3D 4.0 (The Database Center for Life Science) and
## the Human Reference Atlas reference organs (HuBMAP; Visible Human male), both
## CC BY 4.0 (art/anatomy/CREDITS.txt), cut down and laid out by
## art/anatomy/source/build_anatomy.py, fitted inside each body by
## fit_bodies.py (fits.json).
##
## A region is built the first time it is blown open (ClownGore._show_innards),
## on the bone that carries that part of the body, so it moves, dies and
## ragdolls with it. The meshes are shared by every body; each body gets its
## own materials (they carry its wounds), drawn only round its holes
## (shaders/anatomy.gdshaderinc).

## region -> the bone it rides and its meshes
const REGIONS := {
	"head": {bone = &"Head", file = "res://art/anatomy/head.glb"},
	"neck": {bone = &"Neck", file = "res://art/anatomy/neck.glb"},
	"chest": {bone = &"Chest", file = "res://art/anatomy/chest.glb"},
	"belly": {bone = &"Spine", file = "res://art/anatomy/belly.glb"},
	"pelvis": {bone = &"Hips", file = "res://art/anatomy/pelvis.glb"},
}
## What each blown-open part of the body shows.
const SHOWS := {&"head": ["head"], &"chest": ["chest"], &"belly": ["belly", "pelvis"]}
const TEX := "res://art/anatomy/tex/"
## How each surface is shaded: texture, tint, repeats a metre, bump, roughness, specular.
const SURFACES := {
	"bone": {tex = "bone", tint = Color(0.96, 0.93, 0.88), scale = 14.0, bump = 1.2, rough = 1.0, spec = 0.35, breaks = true},
	"cartilage": {tex = "cartilage", tint = Color(0.9, 0.9, 0.9), scale = 12.0, bump = 0.6, rough = 1.0, spec = 0.45, breaks = true},
	"brain": {tex = "brain", tint = Color(1, 1, 1), scale = 22.0, bump = 1.0, rough = 1.0, spec = 0.5, blood = 0.18},
	"lung": {tex = "lung", tint = Color(1, 1, 1), scale = 10.0, bump = 1.2, rough = 1.0, spec = 0.45},
	"heart": {tex = "heart", tint = Color(1, 1, 1), scale = 9.0, bump = 1.0, rough = 1.0, spec = 0.5},
	"liver": {tex = "liver", tint = Color(1, 1, 1), scale = 14.0, bump = 0.8, rough = 1.0, spec = 0.55},
	"gut": {tex = "gut", tint = Color(1, 1, 1), scale = 16.0, bump = 0.8, rough = 1.0, spec = 0.55},
	"colon": {tex = "colon", tint = Color(1, 1, 1), scale = 12.0, bump = 1.0, rough = 1.0, spec = 0.5},
	"kidney": {tex = "kidney", tint = Color(1, 1, 1), scale = 14.0, bump = 0.6, rough = 1.0, spec = 0.5},
	"muscle": {tex = "muscle", tint = Color(1, 1, 1), scale = 11.0, bump = 1.3, rough = 1.0, spec = 0.45, breaks = true, break_k = 1.0},
	"marrow": {tex = "marrow", tint = Color(0.9, 0.85, 0.82), scale = 40.0, bump = 1.0, rough = 1.0, spec = 0.4},
}
## How much of a hole's radius each layer is broken away in, by region: the
## muscle wall torn back to the skin's edge, the ribs snapped only nearer the
## middle (their broken ends stand round the rim), the skull broken open wide.
const BREAK := {"head": {"bone": 0.85}, "neck": {"bone": 0.7}, "chest": {"bone": 0.6, "cartilage": 0.6},
	"belly": {"bone": 0.55, "cartilage": 0.55}, "pelvis": {"bone": 0.6}}

static var _parts := {}        # region -> [[Mesh, surface kind]]
static var _fits := {}         # body -> region -> Transform3D (reference -> rest skeleton space)
static var _shader: Shader
static var _bone_shader: Shader


## Can this body show real anatomy? (A clockwork one shows machinery instead.)
static func has_fit(body: String) -> bool:
	_load_fits()
	return _fits.has(body)


static func _load_fits() -> void:
	if not _fits.is_empty():
		return
	var f := FileAccess.open("res://art/anatomy/fits.json", FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for body: String in data:
		_fits[body] = {}
		for region: String in data[body]:
			var d: Dictionary = data[body][region]
			var b: Array = d.basis
			# basis is written as rows of a diagonal-ish 3x3: columns are its transposed rows
			var basis := Basis(Vector3(b[0][0], b[1][0], b[2][0]), Vector3(b[0][1], b[1][1], b[2][1]), Vector3(b[0][2], b[1][2], b[2][2]))
			var o: Array = d.origin
			_fits[body][region] = Transform3D(basis, Vector3(o[0], o[1], o[2]))


## Where `region`'s reference anatomy goes in `body`'s skeleton at rest.
static func fit(body: String, region: String) -> Transform3D:
	_load_fits()
	return (_fits.get(body, {}) as Dictionary).get(region, Transform3D.IDENTITY)


## The region's meshes (loaded once, shared): [[mesh, surface kind]].
static func parts(region: String) -> Array:
	if _parts.has(region):
		return _parts[region]
	var out := []
	var scene := (load(REGIONS[region].file) as PackedScene).instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh
		var kind := "bone"
		if m.get_surface_count() > 0 and m.surface_get_material(0):
			kind = m.surface_get_material(0).resource_name
		out.append([m, kind if SURFACES.has(kind) else "bone"])
	scene.free()
	_parts[region] = out
	return out


## A body's own material for one surface of one region.
static func material(kind: String, to_rest: Transform3D, region: String = "") -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/anatomy.gdshader")
		_bone_shader = load("res://shaders/anatomy_bone.gdshader")
	var s: Dictionary = SURFACES[kind]
	var m := ShaderMaterial.new()
	m.shader = _bone_shader if s.get("breaks", false) else _shader
	m.set_shader_parameter("albedo_tex", load(TEX + s.tex + "_albedo.png"))
	m.set_shader_parameter("hr_tex", load(TEX + s.tex + "_hr.png"))
	m.set_shader_parameter("tint", s.tint)
	m.set_shader_parameter("tex_scale", s.scale)
	m.set_shader_parameter("bump", s.bump)
	m.set_shader_parameter("rough_mul", s.rough)
	m.set_shader_parameter("specular_amount", s.spec)
	m.set_shader_parameter("breaks", s.get("breaks", false))
	m.set_shader_parameter("break_k", (BREAK.get(region, {}) as Dictionary).get(kind, s.get("break_k", 0.95)))
	m.set_shader_parameter("blood_amount", s.get("blood", 0.35))
	m.set_shader_parameter("to_rest", Projection(to_rest))
	return m


## Build `region` on `skel` for a body of kind `body`: returns the node holding
## it (under a BoneAttachment3D on the region's bone) and its new materials.
static func build(skel: Skeleton3D, body: String, region: String) -> Array:
	var bone: StringName = REGIONS[region].bone
	var bi := skel.find_bone(bone)
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skel.add_child(att)
	var holder := Node3D.new()
	holder.name = "Anatomy_" + region
	att.add_child(holder)
	var to_rest := fit(body, region)
	# the bone carries it: undo the bone's own rest, then place it in rest space
	holder.transform = skel.get_bone_global_rest(bi).affine_inverse() * to_rest
	var mats := {}
	for p: Array in parts(region):
		var kind: String = p[1]
		if not mats.has(kind):
			mats[kind] = material(kind, to_rest, region)
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = mats[kind]
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # inside a body: nothing to shadow
		holder.add_child(mi)
	return [holder, mats.values()]


# --- the long bones' ends: stumps, severed limbs, broken limbs ----------------------
## joints.glb (art/anatomy/source/build_joints.py): <Side><Bone>_<Prox|Dist>, each
## on its own frame (the joint's middle at the origin, +Y up the shaft, +Z the
## front), at real size; `length` the whole bone, `width` its shaft, `kept` the
## piece's length.
const JOINTS := "res://art/anatomy/joints.glb"
## Which piece a stump keeps poking out past its cap, and which a severed limb
## carries at its top: by the segment that came off.
const STUMP_PIECE := {"LowerArm": "Humerus_Dist", "Hand": "Forearm_Dist", "LowerLeg": "Femur_Dist", "Foot": "Shin_Dist"}
const GIB_PIECE := {"UpperArm": "Humerus_Prox", "LowerArm": "Forearm_Prox", "UpperLeg": "Femur_Prox", "LowerLeg": "Shin_Prox"}
## The rig segment each bone spans (for its length): bone -> [from, to]
const SPANS := {"Humerus": ["UpperArm", "LowerArm"], "Forearm": ["LowerArm", "Hand"], "Femur": ["UpperLeg", "LowerLeg"], "Shin": ["LowerLeg", "Foot"]}

static var _pieces := {}       # name -> {mesh, length, width, kept}


static func piece(name: String) -> Dictionary:
	if _pieces.is_empty():
		var scene := (load(JOINTS) as PackedScene).instantiate()
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var n := String(mi.name)
			var meta: Dictionary = {}
			for key in ["length", "width", "kept"]:
				if mi.has_meta("extras"):
					meta[key] = (mi.get_meta("extras") as Dictionary).get(key, 0.0)
			_pieces[n] = {mesh = mi.mesh, length = float(meta.get("length", 0.3)), width = float(meta.get("width", 0.025)), kept = float(meta.get("kept", 0.08))}
		scene.free()
	return _pieces.get(name, {})


## Materials for exposed bone and marrow: drawn whole (not only round a hole),
## for pieces that stick out where the body is broken. Shared per body.
static var _exposed: Array = []


static func exposed_materials() -> Array:
	if not _exposed.is_empty():
		return _exposed
	var bone := material("bone", Transform3D.IDENTITY)
	bone.set_shader_parameter("breaks", false)
	bone.set_shader_parameter("show_all", true)
	bone.set_shader_parameter("blood_amount", 0.5)
	var marrow := material("marrow", Transform3D.IDENTITY)
	marrow.shader = bone.shader
	marrow.set_shader_parameter("show_all", true)
	marrow.set_shader_parameter("blood_amount", 0.45)
	_exposed = [bone, marrow]
	return _exposed


## A bone piece as a MeshInstance3D, in a space where `joint` is the joint's
## middle and the shaft runs toward `toward`. `length` the bone's length in
## this body (sets the size along it), `limb_radius` the limb round it (the
## bone is never thicker than about half of it).
static func piece_node(name: String, joint: Vector3, toward: Vector3, length: float, limb_radius: float, mats: Array) -> MeshInstance3D:
	var p := piece(name)
	if p.is_empty():
		return null
	var y := (toward - joint).normalized()
	var z := Vector3.BACK - y * Vector3.BACK.dot(y)                  # the body's front, square to the shaft
	if z.length() < 0.2:
		z = Vector3.UP - y * Vector3.UP.dot(y)
	z = z.normalized()
	var x := y.cross(z)
	var sy: float = length / maxf(p.length, 0.01)
	var k := minf(sy, 0.45 * limb_radius / maxf(p.width * 0.5, 0.004))
	var mi := MeshInstance3D.new()
	mi.mesh = p.mesh
	mi.transform = Transform3D(Basis(x * k, y * sy, z * k), joint)
	for i in mi.mesh.get_surface_count():
		var sm := mi.mesh.surface_get_material(i)
		mi.set_surface_override_material(i, mats[1] if sm and sm.resource_name == "marrow" else mats[0])
	mi.layers = 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _exposed_kind := {}


## Any surface kind drawn whole (show_all), shared: torn meat at a break, a
## loop of bowel hanging out of a belly.
static func exposed(kind: String) -> ShaderMaterial:
	if not _exposed_kind.has(kind):
		var m := material(kind, Transform3D.IDENTITY)
		m.set_shader_parameter("show_all", true)
		m.set_shader_parameter("breaks", false)
		_exposed_kind[kind] = m
	return _exposed_kind[kind]


static var _link: ArrayMesh


## One length of a spilled loop of small bowel (procedural geometry, the gut
## texture on it): a tube 4.4 cm across, gently bent, pinched and swelling along
## its length, its ends tapered so the links of a chain overlap. Along Y,
## centred, about 11 cm long, for GoreBit links.
static func gut_link() -> ArrayMesh:
	if _link:
		return _link
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var sides := 12
	var half := 0.056
	var pts: Array = []
	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(-half, half, t)
		var bend := sin(t * PI) * 0.009                       # bowed to one side
		var r := 0.022 * (1.0 + 0.1 * sin(t * TAU * 2.5)) * (0.55 + 0.45 * sin(t * PI))
		var ring: Array = []
		for j in sides:
			var a := TAU * j / sides
			var wob := 1.0 + 0.05 * sin(a * 3.0 + t * 7.0)
			ring.append(Vector3(cos(a) * r * wob + bend, y, sin(a) * r * wob))
		pts.append(ring)
	for i in rings:
		for j in sides:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % sides]
			var c: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][(j + 1) % sides]
			for v: Vector3 in [a, c, b, b, c, d]:
				st.add_vertex(v)
	# the ends closed
	for e: int in [0, rings]:
		var ctr := Vector3(sin(float(e) / rings * PI) * 0.009, lerpf(-half, half, float(e) / rings) * 1.03, 0)
		for j in sides:
			var a: Vector3 = pts[e][j]
			var b: Vector3 = pts[e][(j + 1) % sides]
			if e == 0:
				for v: Vector3 in [ctr, a, b]:
					st.add_vertex(v)
			else:
				for v: Vector3 in [ctr, b, a]:
					st.add_vertex(v)
	st.index()
	st.generate_normals()
	_link = st.commit()
	_link.surface_set_material(0, exposed("gut"))
	return _link
