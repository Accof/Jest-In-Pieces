class_name Squad
extends RefCounted
## (Milestone 9) A small, imperfect group of the director's men sharing one
## task. It does not replace the brains or the duties: each man still sees,
## hears, hunts, searches and goes back to his job on his own. The squad
## adds three things a group of men would do and a line of strangers would
## not:
##
##   word     when one of them is alerted (he saw, he heard, he was shot at),
##            the others within `word_range` by path are told where - once,
##            and only most of the time (`word_chance`): an imperfect group.
##   withdraw when half or more of them are down and the rest have lost
##            contact (back to IDLE), the rest fall back to where the squad
##            came from and hold there - most of the time (`withdraw_chance`);
##            otherwise they hold where they are.
##   hold     nothing more: the duties are the task (the parapet, the beat).
##
## Ticked by the director with the events (every 0.5 s). Deterministic: the
## director's RNG decides the chances.

var name := ""
var members: Array[BattleDuty] = []
var origin := Vector3.ZERO            ## where they came from (the withdrawal's goal)
var origin_face := Vector3.FORWARD
var word_range := 20.0
var word_chance := 0.7
var withdraw_chance := 0.6
var told := {}                        ## BattleDuty -> true, once each
var withdrawn := false
var words := 0
var _size0 := 0


func _init(n: String, ms: Array, at: Vector3, face: Vector3) -> void:
	name = n
	for d in ms:
		if d is BattleDuty:
			members.append(d)
	origin = at
	origin_face = face
	_size0 = members.size()


func alive() -> Array[BattleDuty]:
	var out: Array[BattleDuty] = []
	for d in members:
		if is_instance_valid(d) and is_instance_valid(d.clown) and not d.clown.dead:
			out.append(d)
	return out


func dead_count() -> int:
	return _size0 - alive().size()


## One tick. `rng` decides the chances, `maze` the path distances. Returns a
## short line for the log when something happened, else "".
func tick(rng: RandomNumberGenerator, maze: TrenchMaze) -> String:
	var live := alive()
	if live.is_empty():
		return ""
	var out := ""
	# word: an alerted man tells the others where
	for d in live:
		var b := d.brain
		if b == null or b.mind == ClownBrain.Mind.IDLE or b._last_known == Vector3.INF:
			continue
		for o in live:
			if o == d or told.has(o) or o.brain == null or o.brain.mind != ClownBrain.Mind.IDLE:
				continue
			told[o] = true
			if rng.randf() > word_chance:
				continue
			var cells: int = maze.path_cells(maze.cell_of(d.clown.global_position), maze.cell_of(o.clown.global_position))
			if cells >= 9999 or cells * maze.cell > word_range:
				continue
			o.told_hops = 1
			o.brain.alert(b._last_known, true, false)
			words += 1
			out += "word to %s; " % o.clown.name
	# withdraw: half down and the rest without contact
	if not withdrawn and _size0 >= 2 and dead_count() * 2 >= _size0:
		var all_idle := true
		for d in live:
			if d.brain == null or d.brain.mind != ClownBrain.Mind.IDLE:
				all_idle = false
		if all_idle:
			withdrawn = true
			if rng.randf() <= withdraw_chance:
				for d in live:
					d.relocate(origin, origin_face, BattleDuty.Kind.GUARD)
				out += "withdraw x%d to %s; " % [live.size(), origin.snapped(Vector3.ONE)]
			else:
				out += "holds (%d down); " % dead_count()
	return out
