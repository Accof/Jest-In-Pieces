class_name TrenchField
extends Node3D
## The fight out in No Man's Land, in front of the clowns' wire: WitzSoldats
## (real bodies, real hitboxes, real deaths) holding shell holes and the
## wrecked sandbag posts, firing out at the enemy line across the way,
## dashing from cover to cover, ducking when a shell lands near, now and then
## killed, and reinforced by small parties coming along the line through the
## mist from the flanks. TrenchBattle makes it on a trench floor.
##
## These men are the battle, not the floor's enemies: they are not on the
## game's list (killing them is not needed to clear the floor), they never
## look for the player and never fire at him. The player can shoot them
## (the Lee-Enfield's long shots); they duck and run when hit at.
##
## The ground out there (beyond the carved trench ground, which ends 12 m
## past the grid) gets collision here, so bodies land on it.

var maze: TrenchMaze
var art: TrenchArt
var player: Node3D
var game: Node
var rng := RandomNumberGenerator.new()
## How many men it keeps out there (more come when it falls short).
var target_alive := 7
## No shell lands within this of the player (nothing unseen hurts him).
var shell_clear := 14.0

## Cover out there: {pos: Vector3 (where a man kneels), face: Vector3 (toward
## the enemy), kind: "bags" | "crater" | "hole", man: FieldSoldier or null}
var posts: Array[Dictionary] = []
var men: Array[FieldSoldier] = []
var bodies: Array[Clown] = []

# counters (tests, the report)
var spawned := 0
var reinforcements := 0     ## parties sent in
var casualties := 0         ## killed by the battle (shells, the far side's rifles)
var player_kills := 0
var shells := 0
var near_misses := 0

var _t_reinforce := 6.0
var _t_casualty := 20.0
var _t_shell := 9.0
var _left_x := 0.0
var _right_x := 0.0


func setup(m: TrenchMaze, a: TrenchArt, seed_: int, pl: Node3D, g: Node) -> void:
	maze = m
	art = a
	player = pl
	game = g
	rng.seed = seed_
	_left_x = -52.0
	_right_x = maze.w * maze.cell + 52.0
	_ground()
	_find_posts()
	_t_casualty = rng.randf_range(15.0, 30.0)
	# the men already out there when the floor begins
	var free := posts.filter(func(p: Dictionary) -> bool: return p.kind != "hole" or rng.randf() < 0.6)
	_shuffle(free)
	for i in mini(target_alive, free.size()):
		var post: Dictionary = free[i]
		var s := _spawn(post.pos + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.2, 0.3)))
		s.take(post)


# --- the ground out there ------------------------------------------------------
## Collision for the ground beyond the carved trench ground: four strips of
## height map round it (front, back and the two sides), 1 m a sample.
func _ground() -> void:
	var body := StaticBody3D.new()
	body.name = "FieldGround"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var inner_lo := maze.origin
	var inner_hi := maze.origin + Vector2((maze.hx - 1) * TrenchMaze.RES, (maze.hz - 1) * TrenchMaze.RES)
	var lo := inner_lo - Vector2(60.0, 85.0)
	var hi := inner_hi + Vector2(60.0, 30.0)
	# (overlapping the carved ground by half a metre so nothing slips between)
	var strips := [
		Rect2(Vector2(lo.x, lo.y), Vector2(hi.x - lo.x, inner_lo.y - lo.y + 0.5)),           # in front: No Man's Land
		Rect2(Vector2(lo.x, inner_hi.y - 0.5), Vector2(hi.x - lo.x, hi.y - inner_hi.y + 0.5)),  # behind the lines
		Rect2(Vector2(lo.x, inner_lo.y), Vector2(inner_lo.x - lo.x + 0.5, inner_hi.y - inner_lo.y)),
		Rect2(Vector2(inner_hi.x - 0.5, inner_lo.y), Vector2(hi.x - inner_hi.x + 0.5, inner_hi.y - inner_lo.y)),
	]
	for r: Rect2 in strips:
		var nx := int(ceil(r.size.x)) + 1
		var nz := int(ceil(r.size.y)) + 1
		var data := PackedFloat32Array()
		data.resize(nx * nz)
		for iz in nz:
			for ix in nx:
				data[ix + iz * nx] = art.height_at(r.position.x + ix * (r.size.x / (nx - 1)), r.position.y + iz * (r.size.y / (nz - 1)))
		var hm := HeightMapShape3D.new()
		hm.map_width = nx
		hm.map_depth = nz
		hm.map_data = data
		var cs := CollisionShape3D.new()
		cs.shape = hm
		cs.position = Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
		cs.scale = Vector3(r.size.x / (nx - 1), 1.0, r.size.y / (nz - 1))
		body.add_child(cs)


# --- cover ---------------------------------------------------------------------
func _find_posts() -> void:
	var taken: Array[Vector3] = []
	var add := func(p: Vector3, kind: String) -> void:
		for q in taken:
			if Vector2(q.x - p.x, q.z - p.z).length() < 4.0:
				return
		p.y = art.height_at(p.x, p.z)
		taken.append(p)
		posts.append({pos = p, face = Vector3(0, 0, -1), kind = kind, man = null})
	# the wrecked sandbag posts: kneel behind them (on the near side)
	for c: Vector3 in art.nml_posts:
		add.call(c + Vector3(0, 0, 1.1), "bags")
		add.call(c + Vector3(1.6, 0, 1.4), "bags")
	# shell holes close in: the near lip of each
	for cr: Vector4 in maze.crater_list:
		if cr.y < -5.0 and cr.y > -11.0 and cr.z > 1.2:
			add.call(Vector3(cr.x, 0, cr.y + cr.z * 0.6), "crater")
	# further out, where the ground dips (the far ground's shell holes)
	var w := maze.w * maze.cell
	for iz in range(0, 16):
		for ix in range(0, int((w + 50.0) / 3.5)):
			var x := -25.0 + ix * 3.5 + rng.randf_range(-1.0, 1.0)
			var z := -13.0 - iz * 3.2 + rng.randf_range(-1.0, 1.0)
			var h := art.height_at(x, z)
			var rim := 0.0
			for a in 6:
				var ang := TAU * a / 6.0
				rim += art.height_at(x + cos(ang) * 2.0, z + sin(ang) * 2.0)
			if rim / 6.0 - h > 0.35:
				add.call(Vector3(x, 0, z + 0.6), "hole")
	posts.assign(posts.filter(func(p: Dictionary) -> bool: return (p.pos as Vector3).z < -4.0 and (p.pos as Vector3).z > -62.0))


func free_posts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in posts:
		if p.man == null or not is_instance_valid(p.man):
			p.man = null
			out.append(p)
	return out


## A free post somewhere between `near` and `reach` metres from `from` (the
## nearest if none is).
func post_near(from: Vector3, near: float, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var pick: Array[Dictionary] = []
	for p in free_posts():
		var d := Vector2(p.pos.x - from.x, p.pos.z - from.z).length()
		if d >= near and d <= reach:
			pick.append(p)
		if d < best_d and d > 1.0:
			best_d = d
			best = p
	return pick.pick_random() if not pick.is_empty() else best


# --- men -----------------------------------------------------------------------
func _spawn(at: Vector3) -> FieldSoldier:
	var c := Clown.new()
	c.body = "witzsoldat"
	var fl: int = game.floor_number if game and "floor_number" in game else 3
	c.max_health = 100.0 * (1.0 + 0.1 * (fl - 1))
	add_child(c)
	c.give_rifle()
	c.always_pose = true
	c.set_process(true)
	at.y = art.height_at(at.x, at.z)
	c.global_position = at
	c.rotation.y = PI
	var s := FieldSoldier.new()
	s.name = "Field"
	s.field = self
	c.add_child(s)
	s.clown = c
	c.died.connect(_on_died)
	c.hurt.connect(s.shot_at.unbind(1))
	men.append(s)
	spawned += 1
	return s


func _on_died(c: Clown) -> void:
	bodies.append(c)
	# some cry out as they go down out there
	var battle := get_parent() as TrenchBattle
	if battle and rng.randf() < 0.45:
		var at := c.global_position + Vector3.UP * 0.5
		get_tree().create_timer(rng.randf_range(0.3, 1.2)).timeout.connect(func() -> void:
			if is_instance_valid(battle):
				battle.scream(at, -6.0))
	if not c.has_meta(&"field_casualty"):
		player_kills += 1
		if game and "kills" in game:
			game.kills += 1
	# the men near him get down
	for s in men:
		if is_instance_valid(s) and not s.clown.dead and s.clown.global_position.distance_to(c.global_position) < 10.0:
			s.duck(rng.randf_range(1.5, 3.5))
	# the dead out there are not kept for ever: the oldest goes once it is out of sight
	if bodies.size() > 10:
		for b in bodies.duplicate():
			if not is_instance_valid(b):
				bodies.erase(b)
			elif bodies.size() > 10 and player and b.global_position.distance_to(player.global_position) > 35.0:
				bodies.erase(b)
				b.queue_free()


func alive() -> Array[FieldSoldier]:
	var out: Array[FieldSoldier] = []
	for s in men:
		if is_instance_valid(s) and is_instance_valid(s.clown) and not s.clown.dead:
			out.append(s)
	return out


func _process(delta: float) -> void:
	if maze == null:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	var calm := 1.0
	var battle := get_parent() as TrenchBattle
	if battle:
		calm = battle.calm
	for i in range(men.size() - 1, -1, -1):
		if not is_instance_valid(men[i]):
			men.remove_at(i)
	var living := alive()
	_t_reinforce -= delta
	if _t_reinforce <= 0.0:
		_t_reinforce = rng.randf_range(14.0, 30.0) * calm
		if living.size() < target_alive:
			_reinforce(mini(target_alive - living.size(), rng.randi_range(2, 4)))
	_t_casualty -= delta
	if _t_casualty <= 0.0:
		_t_casualty = rng.randf_range(22.0, 48.0) * calm
		_casualty(living)
	_t_shell -= delta
	if _t_shell <= 0.0:
		_t_shell = rng.randf_range(8.0, 20.0) * calm
		_near_miss(living)


## A party coming along the line from one flank, through the mist, to the free posts.
func _reinforce(n: int) -> void:
	var from_left := rng.randf() < 0.5
	var z := rng.randf_range(-42.0, -18.0)
	var entry := Vector3(_left_x if from_left else _right_x, 0, z)
	var free := free_posts()
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a.pos.x - entry.x) < absf(b.pos.x - entry.x))
	if free.is_empty():
		return
	reinforcements += 1
	for i in n:
		var post: Dictionary = free[mini(i, free.size() - 1)]
		var s := _spawn(entry + Vector3((-2.6 if from_left else 2.6) * i, 0, rng.randf_range(-1.0, 1.0)))
		s.go_to(post, rng.randf_range(0.0, 0.6) + i * 0.7, false)


## One of them killed by the war out there: a shell bursting by him, or a
## round from across the way. Never near the player.
func _casualty(living: Array[FieldSoldier]) -> void:
	var pick: Array[FieldSoldier] = []
	for s in living:
		if player == null or s.clown.global_position.distance_to(player.global_position) > shell_clear + 4.0:
			pick.append(s)
	if pick.is_empty():
		return
	var s: FieldSoldier = pick.pick_random()
	var c := s.clown
	c.set_meta(&"field_casualty", true)
	casualties += 1
	if rng.randf() < 0.55:
		var at := c.global_position + Vector3(rng.randf_range(-1.5, 1.5), 0, -rng.randf_range(0.6, 2.2))
		_shell(at)
	else:
		var chest: PhysicalBone3D = c.ragdoll.bones.get(&"Chest")
		if chest:
			var dir := Vector3(rng.randf_range(-0.2, 0.2), -0.05, 1.0).normalized()       # from across No Man's Land
			c.hit({collider = chest, position = chest.global_position - dir * 0.12, direction = dir, damage = 400.0, impulse = 9.0, shot_id = rng.randi()})
			SfxSynth.play(self, "rifle_far", c.global_position - dir * 60.0, -8.0, rng.randf_range(0.9, 1.1), 30.0, 300.0)


## A shell landing near the men without hitting anyone (they get down).
func _near_miss(living: Array[FieldSoldier]) -> void:
	if living.is_empty():
		return
	var s: FieldSoldier = living.pick_random()
	var a := rng.randf() * TAU
	var at := s.clown.global_position + Vector3(cos(a), 0, sin(a) * 0.6 - 0.4) * rng.randf_range(7.5, 14.0)
	at.z = minf(at.z, -6.0)
	near_misses += 1
	_shell(at)


func _shell(at: Vector3) -> void:
	if player and Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length() < shell_clear:
		return
	at.y = art.height_at(at.x, at.z)
	shells += 1
	Explosion.detonate(self, at, "shell")
	for s in alive():
		var d := s.clown.global_position.distance_to(at)
		if d < 12.0:
			s.duck(rng.randf_range(1.2, 3.0) * (1.4 - d / 12.0))


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
