extends Node3D
## The two objectives (Operation Drowned Front, Milestone 1), checked.
## Sections (user args; none = all):
##   bunker     floor 1, ELIMINATION: the exit is shut while anyone lives and
##              standing at it offers nothing; the last kill opens it and runs
##              the final-kill camera once; at the exit an upgrade is offered;
##              taking it starts floor 2, shut again
##   survival   floor 3 (the trenches), SURVIVAL: the exit is open from the
##              first moment with every enemy alive; the enemy count and the
##              battle are as they were; a kill counts (kills, tickets, the
##              Curse, the records) but starts no camera; the exit works with
##              enemies alive; the next floor is a bunker, ELIMINATION, shut
##   survival_clear  every enemy killed on a SURVIVAL floor: still no camera,
##              no report, no EXIT OPEN banner; the exit still works
##   legacy     survival_trenches off (the legacy scene): the trench floor keeps
##              ELIMINATION
##   save       the save file's keys are what they were before and after a
##              SURVIVAL floor; a run through floors 1-4 writes floors, best
##              floor and history; death on a SURVIVAL floor saves and ends
##              the run as anywhere
##   transitions bunker -> trench -> bunker -> bunker -> trench across floors
##              1-6: the objective and the exit state at the start of each
##   godot --headless --fixed-fps 60 res://scenes/test_objective.tscn [-- section...]

var fails := 0
var game: Node3D
const ELIMINATION := 0
const SURVIVAL := 1


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := ["bunker", "survival", "survival_clear", "legacy", "save", "transitions"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("OBJECTIVE: %d failed" % fails)
	get_tree().quit()


func _new_game(seed_: int, survival_trenches := true) -> void:
	if game:
		game.queue_free()
		await _frames(2)
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	game.survival_trenches = survival_trenches
	add_child(game)
	await _frames(1)
	seed(seed_)
	game.rng.seed = seed_
	game.start_run()
	FpsPlayer.god_mode = true
	await _frames(3)


## Start the run at floor `n` (the floors before it are skipped).
func _go_to_floor(n: int) -> void:
	game.floor_number = n - 1
	game.next_floor()
	await _frames(3)


func _living() -> Array:
	return game.clowns.filter(func(c: Clown) -> bool: return is_instance_valid(c) and not c.dead)


## A round through the head: dead at once, never a Last Defiance.
func _kill(c: Clown) -> void:
	c.hit({collider = c.ragdoll.bones[&"Neck"], position = c.global_position + Vector3(0, 1.75, 0), direction = Vector3(0, 0, -1), damage = 5000.0, impulse = 14.0, shot_id = randi()})


func _at_exit() -> void:
	game.player.global_position = game._exit.global_position + Vector3.UP * 0.1
	game.player.velocity = Vector3.ZERO
	await _frames(4)


## Stand in front of the SURVIVAL door, look at it: what the [E] ray finds.
func _face_exit() -> Object:
	var p: FpsPlayer = game.player
	for side in [1.0, -1.0]:
		var at: Vector3 = game._exit.global_position + game._exit.global_basis.z * 1.2 * side
		p.global_position = at + Vector3.UP * 0.1
		p.velocity = Vector3.ZERO
		p.look_at(Vector3(game._exit.global_position.x, p.global_position.y, game._exit.global_position.z))
		p.rotation.x = 0.0
		p.rotation.z = 0.0
		p.camera.rotation.x = 0.0
		await _frames(2)
		var u: Object = p._usable()
		if u != null:
			return u
	return null


## Go through the SURVIVAL door: [E] looking at it.
func _use_exit() -> void:
	var u := await _face_exit()
	if u:
		game.player._use()
	await _frames(4)


func _away_from_exit() -> void:
	game.player.global_position = game.maze.cell_center(game.maze.start_cell) + Vector3.UP * 0.1
	await _frames(2)


## A dictionary's keys as sorted Strings (the save in memory has StringName
## keys, the file String ones).
func _keys(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.keys():
		out.append(String(k))
	out.sort()
	return out


func _light_green() -> bool:
	var col: Color = game._exit_light.light_color
	return col.g > 0.8 and col.r < 0.5


## Wait for a killcam to run its course (or for `frames` if none starts).
func _settle_killcam(frames := 900) -> bool:
	var kc: KillCam = game.kill_cam
	var ran := false
	var n := 0
	while n < frames:
		await get_tree().process_frame
		n += 1
		if kc.active:
			ran = true
		elif ran:
			break
	# the report after it
	await _frames(20)
	return ran


# --- bunker: ELIMINATION as it always was -------------------------------------------
func _bunker() -> void:
	print("-- bunker")
	await _new_game(101)
	await _go_to_floor(1)
	_check(game.maze is Maze and not (game.maze is TrenchMaze), "floor 1 is a bunker")
	_check(game.objective == ELIMINATION, "objective ELIMINATION")
	var n := _living().size()
	_check(n > 0 and game.remaining == n, "%d enemies, remaining counts them" % n)
	_check(not game.exit_open, "the exit is shut")
	_check(not _light_green(), "the door's light is red")
	_check("Clowns left: %d" % n in game._hud.text and not ("REACH" in game._hud.text), "the HUD counts clowns left")
	await _at_exit()
	_check(game.state == game.State.PLAYING, "standing at the shut exit offers nothing (state %d)" % game.state)
	await _away_from_exit()
	# all but one
	var living := _living()
	var tickets0: int = game.run_tickets
	for i in living.size() - 1:
		_kill(living[i])
	await _frames(30)
	_check(_living().size() == 1 and game.remaining == 1, "one left: remaining 1")
	_check(not game.exit_open and not game._floor_finale, "still shut, no finale yet")
	_check(not game.kill_cam.active, "no camera for an ordinary kill")
	_check(game.run_tickets >= tickets0 + living.size() - 1, "tickets for the kills (%d -> %d)" % [tickets0, game.run_tickets])
	# the last
	var kills0: int = game.kills
	_kill(_living()[0])
	await _frames(2)
	_check(game._floor_finale, "the last kill is the floor finale")
	var ran := await _settle_killcam()
	_check(ran, "the final-kill camera ran")
	_check(not game.kill_cam.active, "and is over")
	_check(game.exit_open and _light_green(), "the exit is open, the light green")
	_check(game.kills == kills0 + 1 and game.remaining == 0, "kills %d, remaining 0" % game.kills)
	_check("EXIT OPEN" in game._hud.text, "the HUD says EXIT OPEN")
	_check(game._exit.get_node_or_null("ExitDoor") == null, "no [E] door on an ELIMINATION floor: it takes you by proximity, as always")
	await _at_exit()
	_check(game.state == game.State.UPGRADE and game._offer.size() == 3, "at the exit: three upgrades offered (state %d)" % game.state)
	game._pick_upgrade(0)
	await _frames(3)
	_check(game.floor_number == 2 and game.objective == ELIMINATION and not game.exit_open and game.remaining == _living().size() and game.remaining > 0,
		"floor 2: a bunker, ELIMINATION, shut, %d enemies" % game.remaining)
	_check(not game._floor_finale and not game.kill_cam.active, "the finale is reset for the new floor")


# --- survival: the trenches ---------------------------------------------------------------
func _survival() -> void:
	print("-- survival")
	await _new_game(303)
	await _go_to_floor(3)
	_check(game.maze is TrenchMaze, "floor 3 is the trenches")
	_check(game.objective == SURVIVAL, "objective SURVIVAL")
	var n := _living().size()
	# the enemy count is what it was: mini(int(mini(4 + 3 * 2, 18) * 1.5), 26) = 15, plus an officer if none rolled
	_check(n >= 15 and n <= 16, "%d enemies (15 as before, 16 with the guaranteed officer)" % n)
	_check(game.clowns.any(func(c: Clown) -> bool: return c is Zornhauptmann), "an officer among them")
	_check(game.remaining == n, "remaining still counts them (%d)" % game.remaining)
	_check(game.battle != null and not game.battle.duties.is_empty(), "the battle hands out duties (%d)" % (game.battle.duties.size() if game.battle else 0))
	_check(game.exit_open, "the exit is open from the start, with everyone alive")
	_check(_light_green(), "the door's light is green from the start")
	_check("REACH THE ENEMY H.Q." in game._hud.text and not ("Clowns left" in game._hud.text), "the HUD says reach the H.Q., not clowns left")
	# a kill counts, but is no finale
	var kills0: int = game.kills
	var tickets0: int = game.run_tickets
	var curse_kills0: int = game.player.curse.kills if game.player.curse else -1
	var saved_kills0 := int(game.save.get("total_kills", 0))
	var victim: Clown = _living()[0]
	_kill(victim)
	await _frames(30)
	_check(game.kills == kills0 + 1, "the kill counts (%d)" % game.kills)
	_check(game.run_tickets >= tickets0 + 1, "tickets for it (%d -> %d)" % [tickets0, game.run_tickets])
	_check(game.player.curse == null or game.player.curse.kills == curse_kills0 + 1 or game.player.curse.charges > 0, "the Carnival Curse charges from it")
	_check(int(game.save.get("total_kills", 0)) == saved_kills0 + 1, "the records count it")
	_check(game.remaining == n - 1, "remaining %d" % game.remaining)
	_check(not game._floor_finale and not game.kill_cam.active, "no finale, no camera")
	var ran := await _settle_killcam(90)
	_check(not ran, "no camera in the seconds after either")
	# the exit works with the rest alive, but only on purpose: [E] at the door
	_check(_living().size() == n - 1, "%d still alive" % _living().size())
	await _at_exit()
	_check(game.state == game.State.PLAYING, "standing at the open H.Q. door takes you nowhere by itself (state %d)" % game.state)
	var door := await _face_exit()
	_check(door is ExitDoor and door.prompt().begins_with("[E]"), "looking at the door from 1.2 m: the prompt '%s'" % (door.prompt() if door else "(nothing)"))
	_check("[E]" in game._hud.text, "the HUD says [E] to go in")
	await _use_exit()
	_check(game.state == game.State.UPGRADE and game._offer.size() == 3, "[E] at the H.Q. with enemies alive: three upgrades offered (state %d)" % game.state)
	game._pick_upgrade(1)
	await _frames(3)
	_check(game.floor_number == 4 and not (game.maze is TrenchMaze) and game.objective == ELIMINATION, "floor 4: a bunker, ELIMINATION")
	_check(not game.exit_open and not _light_green() and game.remaining == _living().size() and game.remaining > 0, "shut again, %d enemies to kill" % game.remaining)
	_check("Clowns left" in game._hud.text, "the HUD counts clowns left again")


# --- survival_clear: every enemy dead on a SURVIVAL floor --------------------------------------
func _survival_clear() -> void:
	print("-- survival_clear")
	await _new_game(305)
	await _go_to_floor(3)
	var n := _living().size()
	var report0: Dictionary = game.last_report.duplicate() if game.get("last_report") != null else {}
	for c: Clown in _living():
		_kill(c)
	await _frames(30)
	_check(_living().is_empty() and game.remaining == 0, "all %d dead, remaining 0" % n)
	_check(not game._floor_finale, "no finale")
	var ran := await _settle_killcam(120)
	_check(not ran and not game.kill_cam.active, "no final-kill camera")
	_check(game.last_report == report0, "no brutality report")
	_check(game.exit_open and _light_green(), "the exit is open (as it was)")
	_check(not ("EXIT OPEN" in game._hud.text), "no EXIT OPEN on the HUD (it was never shut)")
	await _at_exit()
	_check(game.state == game.State.PLAYING, "standing at the door still takes you nowhere by itself")
	await _use_exit()
	_check(game.state == game.State.UPGRADE, "[E] at the door still works (state %d)" % game.state)


# --- legacy: the old rule on request ----------------------------------------------------------
func _legacy() -> void:
	print("-- legacy")
	await _new_game(307, false)
	await _go_to_floor(3)
	_check(game.maze is TrenchMaze, "a trench floor")
	_check(game.objective == ELIMINATION, "survival_trenches off: ELIMINATION")
	_check(game._exit.get_node_or_null("ExitDoor") == null, "no [E] door: the old proximity exit")
	_check(not game.exit_open and not _light_green(), "the exit is shut")
	_check("Clowns left" in game._hud.text, "the HUD counts clowns left")
	await _at_exit()
	_check(game.state == game.State.PLAYING, "standing at the exit offers nothing")


# --- save: nothing new in the file, the run recorded as before --------------------------------
func _save() -> void:
	print("-- save")
	await _new_game(309)
	var keys0: Array = _keys(game.save)
	var floors0 := int((game.save.get("stats", {}) as Dictionary).get("floors", 0))
	await _go_to_floor(3)
	await _use_exit()
	_check(game.state == game.State.UPGRADE, "[E] at the H.Q. offers upgrades")
	var keys1: Array = _keys(game.save)
	_check(keys1 == keys0, "the save's keys are unchanged by a SURVIVAL floor (%s)" % str(keys1))
	_check(int((game.save.get("stats", {}) as Dictionary).get("floors", 0)) == floors0 + 1, "the floor is counted as cleared")
	game._pick_upgrade(0)
	await _frames(3)
	_check(game.floor_number == 4, "floor 4")
	# die on the next trench floor
	await _go_to_floor(6)
	_check(game.objective == SURVIVAL and game.exit_open, "floor 6: SURVIVAL, open")
	var tickets: int = game.run_tickets
	FpsPlayer.god_mode = false
	game.player.take_damage(99999.0)
	await _frames(5)
	FpsPlayer.god_mode = true
	_check(game.state == game.State.DEAD, "dead ends the run (state %d)" % game.state)
	_check(int(game.save.best_floor) >= 6, "best floor %d" % int(game.save.best_floor))
	var hist: Array = game.save.get("history", [])
	_check(not hist.is_empty() and int(hist[0].floor) == 6 and int(hist[0].tickets) == int(round(tickets * (1.0 + 0.2 * int(game.save.perks.get("pockets", 0))))), "the run is in the history (floor %d, %d tickets)" % [int(hist[0].floor) if not hist.is_empty() else -1, int(hist[0].tickets) if not hist.is_empty() else -1])
	# the file round-trips
	var path: String = game.save_path
	_check(FileAccess.file_exists(path), "the save file was written (%s)" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	var back = JSON.parse_string(f.get_as_text()) if f else null
	var keys2: Array = _keys(back) if back is Dictionary else []
	_check(keys2 == keys1, "and reads back with the same keys")


# --- transitions: floors 1-6 in turn -----------------------------------------------------------
func _transitions() -> void:
	print("-- transitions")
	await _new_game(311)          # start_run builds floor 1 itself
	var expect := {1: ELIMINATION, 2: ELIMINATION, 3: SURVIVAL, 4: ELIMINATION, 5: ELIMINATION, 6: SURVIVAL}
	for n in range(1, 7):
		if n > 1:
			game.next_floor()
			await _frames(3)
		var want: int = expect[n]
		var trench := game.maze is TrenchMaze
		_check(game.floor_number == n and game.objective == want and trench == (want == SURVIVAL) and game.exit_open == (want == SURVIVAL) and _light_green() == (want == SURVIVAL)
			and game.remaining == _living().size() and game.remaining > 0 and not game._floor_finale,
			"floor %d: %s, %s, %s, %d enemies" % [n, "trench" if trench else "bunker", "SURVIVAL" if game.objective == SURVIVAL else "ELIMINATION", "open" if game.exit_open else "shut", game.remaining])
