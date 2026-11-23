class_name FrontFog
extends TrenchFog
## The rolling fog of the Drowned Front: the legacy level's fog banks
## (TrenchFog — dense low clouds that roll across on the wind, pour down into
## the trenches, thicken the ground mist's volume and cut sight both ways),
## spawned for the Front's geometry: off No Man's Land and its flanks, drifting
## toward our lines, more often than the legacy day's, and two already on the
## field when it loads.
##
## It is not in the `fog` group: FrontAtmosphere is the Front's one visibility
## model, and it multiplies this node's `visibility()` in, so the camera, the
## soldiers' eyes and the tests all see the same banks.

var front: FrontMaze
## Seconds between banks (the legacy day waits 70–150 s between them).
const BANK_EVERY := Vector2(28.0, 60.0)


func setup_front(m: FrontMaze, a: FrontArt, seed_: int) -> void:
	front = m
	setup(m, a, null, seed_)
	remove_from_group(&"fog")
	# the puffs in the haze's colour, not the legacy day's white
	_puff_mat.albedo_color = Color(0.74, 0.76, 0.79)      # cold grey (23 Nov)
	_t_bank = rng.randf_range(6.0, 14.0)
	# two banks already out there when the floor loads, well along
	for i in 2:
		var b := roll_in(i)
		if b:
			b.age = 30.0
			b.density = b.peak
			b.pos += b.vel * rng.randf_range(20.0, 45.0)


## A bank rolling in now, from the Front's far side or a flank. The field
## lies between their fire trench (low z) and ours (high z); the wind blows
## toward our lines and a little across.
func roll_in(from_side := -1) -> Bank:
	var b := super.roll_in(from_side)
	if b == null or front == null:
		return b
	var w := maze.w * maze.cell
	var z_near := (front.their_row0 + TrenchMaze.GRID_D) * maze.cell   # their fire trench's far wall
	var z_far := front.our_row0 * maze.cell                              # our fire trench
	var side := from_side if from_side >= 0 else rng.randi() % 3
	match side:
		0:   # off their side, straight over the field at us
			b.pos = Vector3(rng.randf_range(0.0, w), 0, z_near - 20.0 - b.radius)
			b.vel = Vector3(rng.randf_range(0.1, 0.5), 0, rng.randf_range(1.0, 1.6))
		1:   # from the left flank, slanting in
			b.pos = Vector3(-b.radius - 8.0, 0, rng.randf_range(z_near, lerpf(z_near, z_far, 0.6)))
			b.vel = Vector3(rng.randf_range(1.0, 1.5), 0, rng.randf_range(0.4, 0.9))
		_:   # from the right flank
			b.pos = Vector3(w + b.radius + 8.0, 0, rng.randf_range(z_near, lerpf(z_near, z_far, 0.6)))
			b.vel = Vector3(-rng.randf_range(1.0, 1.5), 0, rng.randf_range(0.4, 0.9))
	return b


## (M9) A bank rolled in off their side on the lane at `x`, to cross the
## field between `z_from` (their side) and `z_to` (ours): the director's
## concealment. With the banks full, the least of them is retired, or an
## existing one is steered across the lane (`steered` counts those). Null
## when nothing can be done.
var steered := 0


func roll_across(x: float, z_from: float, z_to: float, player_at := Vector3.INF) -> Bank:
	if banks.size() >= MAX_BANKS:
		# room: the bank that matters least to the player goes - one beyond
		# his sight, or one still thin (not yet swelled, or fading out)
		var least: Bank = null
		var least_s := INF
		for o: Bank in banks:
			var d := o.pos.distance_to(player_at) if player_at != Vector3.INF else 1e9
			var sc := 0.0 if d > 60.0 else o.density
			if sc < least_s:
				least_s = sc
				least = o
		if least == null or least_s > 0.15:
			# none to spare: the wind takes the bank nearest their side across
			# the lane instead (it keeps its shape; only its drift changes)
			var pick: Bank = null
			var pz: float = player_at.z if player_at != Vector3.INF else z_to
			for o: Bank in banks:
				if o.pos.z < pz - 25.0 and (pick == null or o.pos.z < pick.pos.z):
					pick = o
			if pick == null:
				return null
			var to := Vector3(x, 0, pz) - pick.pos        # over his lane where he is, then on
			to.y = 0.0
			pick.vel = to.normalized() * rng.randf_range(1.3, 1.7)
			steered += 1
			return pick
		if is_instance_valid(least.mm):
			least.mm.queue_free()
		banks.erase(least)
	var b := roll_in(0)
	if b == null:
		return null
	b.radius = rng.randf_range(16.0, 22.0)
	b.peak = rng.randf_range(0.6, 0.8)
	b.pos = Vector3(x + rng.randf_range(-4.0, 4.0), 0, z_from - b.radius * 0.6)
	b.vel = Vector3(rng.randf_range(-0.2, 0.2), 0, signf(z_to - z_from) * rng.randf_range(1.3, 1.7))
	return b


func _process(delta: float) -> void:
	super._process(delta)
	# the legacy cadence (70-150 s) is for a day with a battle going on; here
	# the fog is the weather. TrenchFog resets the timer past our range when a
	# bank rolls; we pull it back in once.
	if _t_bank > BANK_EVERY.y:
		_t_bank = rng.randf_range(BANK_EVERY.x, BANK_EVERY.y)


## Every bank gone (tests, and the director when it wants a clear field).
func clear_banks() -> void:
	for b in banks:
		if b.mm and is_instance_valid(b.mm):
			b.mm.queue_free()
	banks.clear()
	_upload()
