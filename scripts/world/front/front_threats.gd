class_name FrontThreats
extends Node3D
## The core combat hazards of the Drowned Front (M6, package C5): the enemy
## machine guns on their parapet (`FrontMg`) and the guns behind their lines
## (`FrontArtillery`). Made by `Game` after the floor's soldiers, given the
## maze, the player and a way to spawn a soldier for each gun.
##
## Nest placement is from the geometry, not by hand: a fire bay of theirs on
## their fire row, facing our lines, whose parapet has a clear view across the
## field, with the nests well apart so the field has a flank the other gun
## cannot see. Each nest sits on the bay's parapet with its gunner on the fire
## step behind it.

const NESTS := 2
const NEST_SPACING := 18.0

var maze: FrontMaze
var player: FpsPlayer
var nests: Array[FrontMg] = []
var artillery: FrontArtillery
var flares: FrontFlares = null        ## (M11) the flare-lit crossing only
var _rng := RandomNumberGenerator.new()


func setup(m: FrontMaze, p: FpsPlayer, seed_: int, spawn_soldier: Callable) -> void:
	maze = m
	player = p
	_rng.seed = seed_
	var want_nests := int(m.knobs.get("nests", NESTS))
	for site: Dictionary in nest_sites():
		if nests.size() >= want_nests:
			break
		var mg := FrontMg.new()
		mg.name = "MG%d" % nests.size()
		add_child(mg)
		mg.setup(m, p, site.at, site.facing, _rng.randi())
		var gunner: Clown = spawn_soldier.call()
		if gunner:
			gunner.global_position = site.stand
			gunner.rotation.y = atan2(site.facing.x, site.facing.z)
			mg.set_gunner(gunner)
		nests.append(mg)
	artillery = FrontArtillery.new()
	artillery.name = "Artillery"
	add_child(artillery)
	artillery.setup(m, p, _rng.randi())
	if bool(m.knobs.get("flares", false)):
		flares = FrontFlares.new()
		flares.name = "Flares"
		add_child(flares)
		flares.setup(m, p, _rng.randi())


## Where a gun could go: their fire bays facing us with a clear view over the
## parapet, best first, spaced apart.
func nest_sites() -> Array:
	var cands: Array = []
	var fire_row := maze.their_row0 + TrenchMaze.GRID_D - 1 - TrenchMaze.FIRE_ROW
	var w := maze.w * maze.cell
	for c: Vector2i in maze.theirs.keys():
		if maze.kind.get(c, "") != "fire" and maze.kind.get(c, "") != "op":
			continue
		if c.y != fire_row and maze.kind.get(c, "") != "op":
			continue
		var f := maze.facing_of(c)
		if f != 1:
			continue
		var fd := Vector2i(0, 1)
		if maze.open_cells.has(c + fd):
			continue                                   # not a front wall
		var centre := maze.cell_center(c)
		var floor_y := maze.floor_height(centre)
		# on the lip: past the wall's batter (the Front's walls lean, D-18) and the
		# parapet bags that stand on the ground beyond it
		var batter: float = 0.0
		for v in maze.wall_w().values():
			batter = maxf(batter, float(v))
		var lip := Vector3(centre.x, 0, (c.y + 1) * maze.cell + batter + 0.7)
		var top := maze.ground_height(lip.x, lip.z)
		var at := Vector3(lip.x, top + 0.06, lip.z)
		var stand := Vector3(centre.x, floor_y + TrenchMaze.FIRE_STEP_H, (c.y + 1) * maze.cell - 0.45)
		stand.y = maxf(stand.y, maze.floor_height(stand) + 0.05)
		# a view: from the muzzle height, out over the field, clear at 25 and 50 m
		var view := 0.0
		for dist: float in [25.0, 50.0]:
			for side: float in [-0.5, 0.0, 0.5]:
				var dir := Vector3(side, 0, 1).normalized()
				var to: Vector3 = at + dir * dist
				to.y = maze.ground_height(to.x, to.z) + 1.2
				if _clear(at + Vector3.UP * 0.42, to):
					view += 1.0
		if view < 4.0:
			continue
		# away from the edges of the field
		var edge := minf(centre.x, w - centre.x)
		cands.append({at = at, stand = stand, facing = Vector3(0, 0, 1), cell = c, score = view * 10.0 + minf(edge, 12.0) + _rng.randf() * 3.0})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var picked: Array = []
	for cd: Dictionary in cands:
		var ok := true
		for p: Dictionary in picked:
			if absf(float(p.at.x) - float(cd.at.x)) < NEST_SPACING:
				ok = false
		if ok:
			picked.append(cd)
	return picked


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, FpsPlayer.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
