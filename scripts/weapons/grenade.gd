class_name Grenade
extends RigidBody3D
## A thrown grenade: a real rigid body (gravity, bounces, rolls, spins) with a
## fuse that starts when it leaves the hand. When the fuse runs out it goes off
## wherever it is, in the air or lying still, exactly once, through the shared
## Explosion (its profile does the damage, the throwing about and the effects),
## and then it is gone.
##
## Every kind of grenade is an entry in TYPES: its model (kept apart from this
## logic, so it can be swapped for a better one), mass, fuse, throw speeds, how
## many can be carried and which Explosion profile it uses. A new grenade is a
## new entry (and, if it bursts differently, a new Explosion profile).

const TYPES := {
	"frag": {
		label = "Stick grenade",
		model = "res://art/weapons/grenade/stick_grenade.glb",
		mass = 0.6,                # kg: the head about two thirds of it
		fuse = 4.0,                # s from leaving the hand
		blast = "frag",            # Explosion.PROFILES key
		throw_speed = 14.0,        # m/s, overhand
		throw_lift = 0.3,          # the overhand throw leaves this much above the aim (radians): a lob
		toss_speed = 6.5,          # m/s, the short underhand toss
		toss_lift = 0.32,
		start = 3,
		max_carry = 5,
		# collision: the steel can and the wooden handle (metres, along the grenade's +Y)
		head = {radius = 0.035, height = 0.10, y = 0.066},
		handle = {radius = 0.013, height = 0.26, y = -0.12},
		fuse_at = Vector3(0, -0.248, 0),   # the end of the handle: where the fuse smoke comes out
	},
}

const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2
const LAYER_DEBRIS := 1 << 3

enum State { ARMED, EXPLODED }

var kind := "frag"
var state := State.ARMED
var fuse_left := 4.0
var bounces := 0                   ## times it has hit something hard enough to be heard (for the tests)
var exploded_at := Vector3.INF     ## where it went off (for the tests)
var _spec: Dictionary
var _last_bounce := -1.0
var _age := 0.0
var _smoke: CPUParticles3D

static var live: Array[Grenade] = []      ## every grenade in flight or lying armed


## Throw a grenade of `kind` from `from` at `velocity`, spinning at `spin`.
## `parent` owns the level (it is freed with it); `ignore` are bodies it must
## not hit (the thrower).
static func throw(parent: Node, kind_: String, from: Vector3, velocity: Vector3, spin: Vector3, ignore: Array[PhysicsBody3D] = []) -> Grenade:
	var g := Grenade.new()
	g.kind = kind_
	g._spec = TYPES.get(kind_, TYPES.frag)
	g._build()
	for b in ignore:
		if is_instance_valid(b):
			g.add_collision_exception_with(b)
	parent.add_child(g)
	g.global_position = from
	g.global_basis = Basis.looking_at(velocity.normalized() if velocity.length() > 0.1 else Vector3.FORWARD, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	g.linear_velocity = velocity
	g.angular_velocity = spin
	SfxSynth.play(parent, "grenade_throw", from, -6.0, 1.0)
	return g


func _build() -> void:
	name = "Grenade"
	mass = float(_spec.mass)
	fuse_left = float(_spec.fuse)
	collision_layer = LAYER_DEBRIS
	collision_mask = LAYER_WORLD | LAYER_RAGDOLL
	continuous_cd = true                         # fast and small: never through a wall or the floor
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = 0.05
	angular_damp = 0.8                           # rolls a little way, then settles
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO                # the model's origin is its balance point
	var pm := PhysicsMaterial.new()
	pm.friction = 0.75
	pm.bounce = 0.2                              # a dull bounce or two, not a rubber ball
	physics_material_override = pm
	for part: String in ["head", "handle"]:
		var d: Dictionary = _spec[part]
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = float(d.radius)
		cy.height = float(d.height)
		cs.shape = cy
		cs.position = Vector3(0, float(d.y), 0)
		add_child(cs)
	var path := String(_spec.model)
	if ResourceLoader.exists(path):
		var m := (load(path) as PackedScene).instantiate() as Node3D
		m.name = "Model"
		add_child(m)
	# the fuse burning in the handle: a thin wisp out of its end
	_smoke = CPUParticles3D.new()
	_smoke.emitting = false                      # lit a moment after it leaves the hand (not in the thrower's face)
	_smoke.amount = 14
	_smoke.lifetime = 0.9
	_smoke.local_coords = false
	_smoke.position = _spec.fuse_at
	_smoke.direction = Vector3(0, -1, 0)
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 0.1
	_smoke.initial_velocity_max = 0.3
	_smoke.gravity = Vector3(0, 0.35, 0)
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	_smoke.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = sg
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	sm.albedo_texture = soft
	q.material = sm
	_smoke.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, Color(0.78, 0.77, 0.74, 0.35))
	grad.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	_smoke.color_ramp = grad
	add_child(_smoke)
	body_entered.connect(_on_hit)


func _enter_tree() -> void:
	if not live.has(self):
		live.append(self)


func _exit_tree() -> void:
	live.erase(self)


func _physics_process(delta: float) -> void:
	if state != State.ARMED:
		return
	_age += delta
	fuse_left -= delta
	if not _smoke.emitting and _age > 0.18:
		_smoke.emitting = true
	# rolling resistance (the physics has none: a can on a stick would roll on
	# for ever): slow and on the ground, it drags to a stop like the real thing
	var slow := linear_velocity.length() < 0.9 and get_contact_count() > 0
	angular_damp = 5.0 if slow else 0.8
	linear_damp = 2.0 if slow else 0.05
	if fuse_left <= 0.0:
		explode()
	elif global_position.y < -50.0:
		queue_free()                             # fell out of the world: no one to hurt there


## Off it goes (once): the blast where it is, then the grenade is gone.
func explode() -> void:
	if state != State.ARMED:
		return
	state = State.EXPLODED
	exploded_at = global_position
	set_physics_process(false)
	freeze = true
	var parent := get_parent()
	Explosion.detonate(parent, global_position, String(_spec.blast))
	queue_free()


## A knock against the ground, a wall or a body: heard if it hit hard enough.
func _on_hit(_body: Node) -> void:
	var speed := linear_velocity.length()
	if speed < 1.0 or _age - _last_bounce < 0.12:
		return
	_last_bounce = _age
	bounces += 1
	SfxSynth.play(get_parent(), "grenade_bounce", global_position, clampf(-14.0 + speed * 1.6, -14.0, 0.0), clampf(0.85 + speed * 0.03, 0.85, 1.2))
