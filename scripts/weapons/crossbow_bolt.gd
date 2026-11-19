class_name CrossbowBolt
extends Node3D
## A heavy crossbow bolt (the crossbow in the old stake gun's slot). It flies
## (gravity, swept each physics step so it cannot tunnel), and where it lands
## decides what it does:
##   - through a hand, a forearm or a foot (sometimes an upper arm or a shin):
##     it wounds and flies on, slower, into whatever is behind;
##   - into a body with solid wall or floor close behind it along the line
##     (PIN_REACH from the entry point): it goes through, bites into the wall,
##     and the body is pinned there (Clown.bolt_pin): a living one struggles,
##     a dead one hangs from it in its own ragdoll;
##   - into a body with nothing behind: it stays in, riding on the bone;
##   - into the world: it sticks, its point in the wall.
## Damage is the clown's own zone damage (head x4, torso x1, limbs less): it
## wounds, it does not kill everything it touches, and it pushes nobody about.
## Bolts left in the world are capped (MAX_LOOSE, oldest go first).

const SPEED := 72.0          ## m/s off the string
const GRAVITY := 9.8         ## real drop: about 0.4 m at 20 m
const LENGTH := 0.46         ## tip to nock
const DAMAGE := 70.0
const PIN_REACH := 0.5       ## entry point to wall: a limb is pinned if a wall is this close behind
const DRIVE_REACH := 1.4     ## through the body (or neck): a wall this far back still takes it,
							 ## the heavy bolt driving them back onto it
const WALL_BITE := 0.05      ## how far the point goes into the wall
const MAX_LOOSE := 40
const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2
## How deep it sinks into each part when it stays in (tip past the entry point).
const DEPTH := {&"Neck": 0.12, &"Chest": 0.2, &"Spine": 0.19, &"Hips": 0.18, &"UpperArm": 0.09,
	&"LowerArm": 0.07, &"Hand": 0.05, &"UpperLeg": 0.12, &"LowerLeg": 0.09, &"Foot": 0.06}
## Thin parts it goes straight through (and the chance it does).
const THROUGH := {&"Hand": 1.0, &"LowerArm": 0.85, &"Foot": 0.9, &"UpperArm": 0.4, &"LowerLeg": 0.45}

var vel := Vector3.ZERO
var shot_id := 0
var damage := DAMAGE
var state := "flying"        ## flying, in_world, in_body, pinned
var clown: Clown             ## who it is in (or pinned)
var bone := &""
var _travel := 0.0
var _exclude: Array[RID] = []
static var _loose: Array[CrossbowBolt] = []
static var _mesh: Mesh
static var _fx_mat: StandardMaterial3D


## Loose a bolt from `from` along `dir`. `parent` owns the level.
static func launch(parent: Node, from: Vector3, dir: Vector3, id: int, exclude: Array[RID] = []) -> CrossbowBolt:
	var b := CrossbowBolt.new()
	parent.add_child(b)
	b.shot_id = id
	b._exclude = exclude.duplicate()
	b.global_position = from
	b.vel = dir.normalized() * SPEED
	b._face(dir)
	return b


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = bolt_mesh()
	mi.layers = 1 | 2
	add_child(mi)


func _face(dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT
	look_at(global_position + dir, up)


func _physics_process(delta: float) -> void:
	if state != "flying":
		set_physics_process(false)
		return
	var step := vel * delta
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + step, LAYER_WORLD | LAYER_RAGDOLL)
	q.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.collider
		if c is PhysicalBone3D and c.has_meta(&"clown"):
			if _hit_body(c, hit.position):
				return
			# through a limb: on it goes from here (the rest of this step is lost)
			global_position = hit.position + vel.normalized() * 0.02
			return
		elif c is PhysicalBone3D:
			_exclude.append(c.get_rid())        # a loose bit of someone: brush past
		elif c.has_method("shot"):
			c.shot(hit.position, vel.normalized(), damage)      # a fuel drum, a target
			_stick(hit.position, hit.normal)
			return
		else:
			_stick(hit.position, hit.normal)
			return
	global_position += step
	_travel += step.length()
	vel += Vector3.DOWN * GRAVITY * delta
	_face(vel)
	if _travel > 140.0 or global_position.y < -50.0:
		queue_free()


## Into someone. Returns true if the bolt stopped (stays in, or pinned).
func _hit_body(pb: PhysicalBone3D, at: Vector3) -> bool:
	var who: Clown = pb.get_meta(&"clown")
	var dir := vel.normalized()
	var b := StringName(pb.bone_name)
	var zone := Clown._zone(b)
	var through: bool = randf() < float(THROUGH.get(zone, 0.0))
	# solid wall (or floor) close behind, along the line: can it nail them to it?
	var wall := {}
	if not through:
		var reach := DRIVE_REACH if zone in [&"Chest", &"Spine", &"Hips", &"Neck"] else PIN_REACH
		var wq := PhysicsRayQueryParameters3D.create(at, at + dir * (reach + WALL_BITE), LAYER_WORLD)
		wall = get_world_3d().direct_space_state.intersect_ray(wq)
		if not wall.is_empty() and ((wall.collider as Object).has_method("shot") or (wall.normal as Vector3).dot(dir) > -0.25):
			wall = {}                           # a drum, or only grazing it
		elif not wall.is_empty() and at.distance_to(wall.position) > PIN_REACH and absf((wall.normal as Vector3).y) > 0.5:
			wall = {}                           # only a wall is worth driving them back onto, not the floor
	var pin := not wall.is_empty()
	var was_dead := who.dead
	who.hit({
		collider = pb, position = at, direction = dir, damage = damage,
		impulse = 1.6 if not was_dead else 2.2,         # a shove, not a launch
		react = 62.0, heavy = false, can_dismember = false, shot_id = shot_id,
		blood = 1.1, weapon = "Crossbow", crossbow = true, pinned = pin,
	})
	SfxSynth.play(self, "bolt_flesh", at, -2.0)
	if not is_instance_valid(pb) or not pb.is_inside_tree():
		queue_free()                             # the part it hit came off
		return true
	if through or pin:
		# out the far side: an exit wound and a spray behind
		var out := at + dir * (0.07 if through else 0.18)
		who.gore.add_wound(b, out, 30.0)
		Blood.spawn_hit(out, dir, 0.7 if through else 0.9, who.mechanical)
	if through:
		_exclude.append(pb.get_rid())
		vel *= 0.62
		return false
	clown = who
	bone = b
	set_physics_process(false)
	if pin:
		var tip: Vector3 = (wall.position as Vector3) + dir * WALL_BITE
		global_position = tip
		_face(dir)
		if who.bolt_pin(self, pb, at, wall.position, wall.normal):
			state = "pinned"
			_wall_fx(wall.position, wall.normal, true)
			Blood.spawn_decal(wall.position, wall.normal, randf_range(0.35, 0.5), "impact", Vector3.ZERO, 1.0, 1.0, who.mechanical)
			var down := (Vector3.DOWN - (wall.normal as Vector3) * Vector3.DOWN.dot(wall.normal)).normalized()
			if down.length() > 0.5:
				Blood.spawn_decal(wall.position + down * 0.22, wall.normal, 0.3, "streak", down, 1.0, 1.6, who.mechanical)
			_register_loose()
			return true
	# stays in: tip a part's depth past the entry point, riding on the bone
	global_position = at + dir * float(DEPTH.get(zone, 0.12))
	_face(dir)
	state = "in_body"
	who.bolt_embed(self, pb)
	return true


## Into the world: point in, shaft out.
func _stick(at: Vector3, normal: Vector3) -> void:
	var dir := vel.normalized()
	global_position = at + dir * WALL_BITE * clampf(-dir.dot(normal) * 1.4, 0.4, 1.0)
	_face(dir)
	state = "in_world"
	set_physics_process(false)
	_wall_fx(at, normal, false)
	_register_loose()


## The clown it pinned (by a limb) has torn itself off it: the bolt comes
## out of the wall with the limb and stays in it.
func torn_free(who: Clown) -> void:
	state = "in_body"
	_loose.erase(self)
	var pb: PhysicalBone3D = who.ragdoll.bones.get(bone)
	if pb:
		global_position -= global_basis.z * -0.06            # out of the wall a little
		who.bolt_embed(self, pb)


## Whether this bolt can be tidied away (not holding up a living clown).
func can_cull() -> bool:
	return state != "pinned" or not is_instance_valid(clown) or clown.dead


func _register_loose() -> void:
	_loose.append(self)
	tree_exiting.connect(func() -> void: _loose.erase(self))
	if _loose.size() > MAX_LOOSE:
		for old: CrossbowBolt in _loose.duplicate():
			if old != self and is_instance_valid(old) and old.can_cull():
				old.queue_free()
				break


## A puff of grit and splinters where the point went in, and its knock.
func _wall_fx(at: Vector3, normal: Vector3, through_body: bool) -> void:
	SfxSynth.play(self, "bolt_wall", at, -1.0 if not through_body else -5.0)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.55
	p.explosiveness = 0.95
	p.direction = Vector3(0, 0, 1)
	p.spread = 55.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.004
	p.scale_amount_max = 0.012
	var m := QuadMesh.new()
	m.size = Vector2.ONE
	if _fx_mat == null:
		_fx_mat = StandardMaterial3D.new()
		_fx_mat.albedo_color = Color(0.32, 0.27, 0.21)
		_fx_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_fx_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = _fx_mat
	p.mesh = m
	var holder := get_parent()
	holder.add_child(p)
	p.global_position = at + normal * 0.01
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	p.look_at(at + normal, up)
	p.rotate_object_local(Vector3.UP, PI)          # emit along +Z = out of the wall
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## The bolt: tip at the origin, shaft back along +Z. A square iron head, an
## ash shaft, three stiff vanes at the nock.
static func bolt_mesh() -> Mesh:
	if _mesh:
		return _mesh
	var am := ArrayMesh.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://art/level/timber.png")
	wood.albedo_color = Color(0.9, 0.78, 0.6)
	wood.roughness = 0.75
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.17, 0.16, 0.15)
	iron.metallic = 0.75
	iron.roughness = 0.5
	var vane := StandardMaterial3D.new()
	vane.albedo_color = Color(0.33, 0.27, 0.2)
	vane.roughness = 0.9
	vane.cull_mode = BaseMaterial3D.CULL_DISABLED
	var along := Basis(Vector3.RIGHT, PI * 0.5)        # cylinder Y -> +Z
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.0055
	shaft.bottom_radius = 0.0062
	shaft.height = LENGTH - 0.05
	shaft.radial_segments = 8
	shaft.rings = 1
	var st := SurfaceTool.new()
	st.append_from(shaft, 0, Transform3D(along, Vector3(0, 0, 0.05 + (LENGTH - 0.05) * 0.5)))
	st.commit(am)
	am.surface_set_material(0, wood)
	# square bodkin head (four faces to a point) and a ferrule
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.0105
	head.height = 0.06
	head.radial_segments = 4
	head.rings = 1
	var ferrule := CylinderMesh.new()
	ferrule.top_radius = 0.0075
	ferrule.bottom_radius = 0.0075
	ferrule.height = 0.022
	ferrule.radial_segments = 8
	ferrule.rings = 1
	var st2 := SurfaceTool.new()
	st2.append_from(head, 0, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.25), Vector3(0, 0, 0.03)))
	st2.append_from(ferrule, 0, Transform3D(along, Vector3(0, 0, 0.065)))
	st2.commit(am)
	am.surface_set_material(1, iron)
	# three vanes, 120 degrees apart, at the back
	var st3 := SurfaceTool.new()
	st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := TAU * k / 3.0 + PI * 0.5
		var r := Vector3(cos(a), sin(a), 0)
		var z0 := LENGTH - 0.11
		var z1 := LENGTH - 0.01
		var pts := [Vector3(0, 0, z0) + r * 0.006, Vector3(0, 0, z1 - 0.02) + r * 0.024, Vector3(0, 0, z1) + r * 0.024, Vector3(0, 0, z1) + r * 0.006]
		var n := r.cross(Vector3(0, 0, 1)).normalized()
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for i: int in tri:
				st3.set_normal(n)
				st3.add_vertex(pts[i])
	st3.commit(am)
	am.surface_set_material(2, vane)
	_mesh = am
	return _mesh
