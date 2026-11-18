extends Node3D
## The roguelite loop: title screen, the base you come round in after every
## death (shop, stats, trophies, fortune, armoury), floors of funhouse maze,
## upgrades between floors, death, and everything that carries over.

enum State { MENU, PLAYING, UPGRADE, DEAD, BASE, SHOP, CONFIRM }

const SAVE_PATH := "user://clown_save.json"
## The automated tests set Engine meta "test_save" so they never touch the real save.
const TEST_SAVE_PATH := "user://clown_save_test.json"
var save_path := SAVE_PATH

## One of three is offered after every floor.
const UPGRADES := [
	{id = "hollow", name = "Hollow Points", desc = "+25% damage with every gun."},
	{id = "trigger", name = "Itchy Finger", desc = "Fire 20% faster."},
	{id = "pellets", name = "Packed Shells", desc = "Shotgun fires 3 more pellets."},
	{id = "choke", name = "Tight Choke", desc = "Shotgun spread 30% tighter."},
	{id = "meat", name = "Thick Hide", desc = "+30 maximum health, and heal 30."},
	{id = "legs", name = "Greased Shoes", desc = "Move 12% faster."},
	{id = "leech", name = "Blood Drinker", desc = "Heal 4 health for every kill."},
	{id = "saw", name = "Bone Saw Rounds", desc = "Pistol shots can blow limbs and heads off."},
	{id = "rush", name = "Adrenaline", desc = "Headshot kills slow time for a moment."},
	{id = "bath", name = "Bloodbath", desc = "Twice the blood. Purely for show."},
	{id = "drum", name = "Snail Drum", desc = "The MP 18 takes the 32-round snail drum instead of the 20-round stick."},
]

## Bought with tickets on the menu; kept between runs.
const PERKS := [
	{id = "skin", name = "Thick Skin", desc = "+10 starting health", cost = 15, max = 5},
	{id = "hair", name = "Hair Trigger", desc = "+5% fire rate", cost = 20, max = 5},
	{id = "start", name = "Head Start", desc = "Begin each run with a random upgrade", cost = 60, max = 1},
	{id = "pockets", name = "Deep Pockets", desc = "+20% tickets from every run", cost = 40, max = 3},
	{id = "dressing", name = "Field Dressing", desc = "Heal 15 at the start of every floor", cost = 35, max = 2},
]
const NEW_SAVE := {tickets = 0, best_floor = 0, total_kills = 0, perks = {}, stats = {}, trophies = [],
	weapon_kills = {}, history = [], fortune = {}, start_weapon = 0}

var state := State.MENU
## Share of each floor's enemies that are Klappersoldats: from floor 2 at
## klapper_base, rising by klapper_per_floor each floor, up to klapper_max.
@export var klapper_base := 0.1
@export var klapper_per_floor := 0.02
@export var klapper_max := 0.2
## Share of WitzSoldats that carry a spiked trench club instead of a rifle.
@export var club_share := 0.25
## Rattlejacks (British machine gunners): from floor 2, this share of the
## floor, rising by rattle_per_floor each floor, up to rattle_max.
@export var rattle_base := 0.08
@export var rattle_per_floor := 0.02
@export var rattle_max := 0.16
## Zornhauptmanns (officers: pistol and sabre) from floor 2: zorn_base, rising
## by zorn_per_floor each floor, up to zorn_max.
@export var zorn_base := 0.06
@export var zorn_per_floor := 0.02
@export var zorn_max := 0.14
## Every this many floors is the Drowned Trenches (an outdoor trench network,
## TrenchMaze) instead of the bunkers. 0 turns them off.
@export var trench_every := 3
## Enemies on a trench floor, relative to a bunker floor (it is 2-3x bigger).
@export var trench_enemy_scale := 1.5
## Trench floors: the share of riflemen and other soldiers (the rest plain clowns).
@export var trench_soldier_share := 0.75
var floor_number := 0
var kills := 0
var run_tickets := 0
var remaining := 0
var exit_open := false
var taken: Array[String] = []
var save := NEW_SAVE.duplicate(true)
var base: Base
var _new_trophies: Array[String] = []
var _run_best_pierce := 0

var maze: Maze
var player: FpsPlayer
var clowns: Array[Clown] = []
var rng := RandomNumberGenerator.new()

var _world: Node3D
var _exit: Node3D
var _world_env: WorldEnvironment
var _bunker_env: Environment
var _trench_env: Environment
var _sun: DirectionalLight3D
var _exit_light: OmniLight3D
var _ui: CanvasLayer
var main_menu: MainMenu
var _hud: Label
var _health_bar: ProgressBar
var _banner: Label
var _panel: VBoxContainer
var _offer: Array = []
var _slow_until := 0
## The final-kill camera, and whether this floor has had its final kill shown.
var kill_cam: KillCam
## The final-kill fanfare shown over the end of the killcam.
var brutality: BrutalityReport
var last_report := {}
var _pending_report := {}
var _exit_banner_due := false
var _floor_finale := false
var events: EventManager
var _event_upgrade := false


func _ready() -> void:
	add_to_group(&"game")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The project's internal name stays "Clown Shooter" so existing save files are still found.
	get_window().title = "Jest In Pieces"
	rng.randomize()
	if Engine.has_meta(&"test_save"):
		save_path = TEST_SAVE_PATH
	_load()
	_build_environment()
	_build_ui()
	events = EventManager.new()
	events.name = "Events"
	events.game = self
	add_child(events)
	_show_menu()


# --- flow ---------------------------------------------------------------------
func start_run() -> void:
	floor_number = 0
	kills = 0
	run_tickets = 0
	_run_best_pierce = 0
	taken.clear()
	_clear_floor()
	_make_player()
	events.player = player
	events.new_run()
	Records.add(save, "runs")
	if int(save.perks.get("start", 0)) > 0:
		_apply_upgrade(UPGRADES[rng.randi() % UPGRADES.size()].id)
	# Madame Bonzo's card, if one was dealt
	var f: Dictionary = save.get("fortune", {})
	match String(f.get("kind", "")):
		"upgrade":
			_apply_upgrade(String(f.value))
		"health":
			player.stats.max_health += float(f.value)
			player.heal(float(f.value))
	save.fortune = {}
	var sw := int(save.get("start_weapon", 0))
	if sw != FpsPlayer.MAXIM and sw >= 0 and sw < FpsPlayer.WEAPONS.size():
		player.select_weapon(sw)
	_save()
	next_floor()


func _make_player() -> void:
	if is_instance_valid(player):
		player.queue_free()
	player = FpsPlayer.new()
	player.show_help = false
	player.stats.max_health = 100.0 + 10.0 * int(save.perks.get("skin", 0))
	player.stats.fire_rate = 1.0 + 0.05 * int(save.perks.get("hair", 0))
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.health_changed.connect(func(_h: float, _m: float) -> void: _refresh_hud())
	player.died.connect(_on_player_died)
	if kill_cam == null:
		kill_cam = KillCam.new()
		kill_cam.name = "KillCam"
		add_child(kill_cam)
		brutality = BrutalityReport.new()
		brutality.name = "Brutality"
		add_child(brutality)
		kill_cam.focus_started.connect(_on_finale_focus)
		kill_cam.finished.connect(_on_finale_over)
		brutality.done.connect(func() -> void:
			if _exit_banner_due and state == State.PLAYING:
				_flash("EXIT OPEN")
			_exit_banner_due = false)
	kill_cam.stop("new player")
	kill_cam.player = player
	kill_cam.hide_nodes = [_hud, _health_bar, _banner]
	kill_cam.can_run = func() -> bool: return state == State.PLAYING
	player.fired.connect(_on_player_fired)
	player.ammo_changed.connect(_refresh_hud)
	player.pierced.connect(func(n: int) -> void:
		_run_best_pierce = maxi(_run_best_pierce, n)
		Records.at_least(save, "best_pierce", n))


## The base: built fresh each visit, the player stood by the cot.
func go_base() -> void:
	Engine.time_scale = 1.0
	_clear_floor()
	_apply_floor_look(false)
	_make_player()
	_world = Node3D.new()
	_world.add_to_group(&"world_root")
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	base = Base.new()
	base.game = self
	_world.add_child(base)
	base.build()
	base.player = player
	player.global_transform = base.global_transform * base.entry
	player.velocity = Vector3.ZERO
	var fresh := Records.new_trophies(save)
	_save()
	base.refresh()
	floor_number = 0
	_set_state(State.BASE)
	if not fresh.is_empty():
		var names := fresh.slice(0, 4)
		if fresh.size() > 4:
			names.append("and %d more" % (fresh.size() - 4))
		event_banner("NEW TROPH%s\n" % ("Y" if fresh.size() == 1 else "IES") + "\n".join(names) + "\n+%d tickets each" % Records.TROPHY_BONUS)


func save_now() -> void:
	_save()


func next_floor() -> void:
	floor_number += 1
	_clear_floor()
	_world = Node3D.new()
	_world.add_to_group(&"world_root")
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	var outdoor := is_trench_floor(floor_number)
	maze = TrenchMaze.new() if outdoor else Maze.new()
	_world.add_child(maze)
	var size := mini(5 + floor_number / 2, 9)
	maze.generate(size + 2, size, rng.randi())     # a little wider than deep: room for a long route
	_apply_floor_look(outdoor)
	var spawn := maze.cell_center(maze.start_cell)
	player.global_position = spawn + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	if outdoor and maze.route.size() > 2:
		var ahead := maze.cell_center(maze.route[2])
		player.rotation.y = atan2(spawn.x - ahead.x, spawn.z - ahead.z)
	_build_exit()
	events.new_floor()
	for l: JokerLocker in get_tree().get_nodes_in_group(&"joker_lockers"):
		if l.is_inside_tree() and not l.is_queued_for_deletion():
			l.player = player
			l.opened.connect(_on_locker_opened)

	if floor_number > 1 and int(save.perks.get("dressing", 0)) > 0:
		player.heal(15.0 * int(save.perks.dressing))
	var count := mini(4 + floor_number * 2, 18)
	if outdoor:
		count = mini(int(count * trench_enemy_scale), 26)
	var gun_share := clampf(0.12 + 0.06 * floor_number, 0.0, 0.5)
	# WitzSoldats: riflemen in gas masks. One in eight on floor 1, rising to a third.
	var soldier_share := clampf(0.07 + 0.05 * floor_number, 0.0, 0.33)
	# Klappersoldats: clockwork infantry, from floor 2.
	var klapper_share := clampf(klapper_base + klapper_per_floor * (floor_number - 2), 0.0, klapper_max) if floor_number >= 2 else 0.0
	var rattle_share := clampf(rattle_base + rattle_per_floor * (floor_number - 2), 0.0, rattle_max) if floor_number >= 2 else 0.0
	var zorn_share := clampf(zorn_base + zorn_per_floor * (floor_number - 2), 0.0, zorn_max) if floor_number >= 2 else 0.0
	var cells := maze.cells_far_from(maze.start_cell, maze.span(3))
	if cells.is_empty():
		cells = maze.cells_far_from(maze.start_cell, 1)
	if outdoor:
		# soldiers' country: mostly riflemen, machine gunners and clockwork
		# infantry, an officer, a few clowns
		soldier_share = trench_soldier_share
		klapper_share = maxf(klapper_share, 0.14)
		rattle_share = maxf(rattle_share, 0.16)
		zorn_share = maxf(zorn_share, 0.08)
	clowns.clear()
	# A table or two in the side rooms with some of them sat round it.
	var seated := _place_tables(soldier_share) if not outdoor else 0
	_clear_drums.call_deferred()
	for i in maxi(count - seated, 0):
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		var c: Clown
		var roll := rng.randf()
		if roll < klapper_share:
			c = spawn_klapper()
		elif roll < klapper_share + rattle_share:
			c = spawn_rattlejack()
		elif roll < klapper_share + rattle_share + zorn_share:
			c = spawn_zornhauptmann()
		else:
			var soldier := rng.randf() < soldier_share
			c = _spawn_clown(soldier, not soldier and rng.randf() < gun_share)
		c.global_position = maze.cell_center(cell) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)) * maze.scale()
		c.global_position.y = maze.floor_height(c.global_position)
		c.rotation.y = rng.randf() * TAU
	if outdoor and floor_number >= 3 and not clowns.any(func(x: Clown) -> bool: return x is Zornhauptmann):
		# a trench has an officer
		var z := spawn_zornhauptmann()
		var zc: Vector2i = cells[rng.randi() % cells.size()]
		z.global_position = maze.cell_center(zc)
	remaining = clowns.size()
	_floor_finale = false
	if kill_cam:
		kill_cam.stop("new floor")
	exit_open = false
	_set_state(State.PLAYING)
	_flash("FLOOR %d%s" % [floor_number, "  -  THE DROWNED TRENCHES" if outdoor else ""])


func _spawn_clown(soldier: bool, gun: bool) -> Clown:
	var c := Clown.new()
	c.max_health = 100.0 * (1.0 + 0.1 * (floor_number - 1))
	if soldier:
		c.body = "witzsoldat"
	_world.add_child(c)
	# one WitzSoldat in four leaves the rifle behind and comes at you with a club
	var clubber := soldier and rng.randf() < club_share
	if clubber:
		c.give_club()
	elif soldier:
		c.give_rifle()
	elif gun:
		c.give_gun()
	var brain := ClownBrain.new()
	brain.maze = maze
	brain.player = player
	brain.others = clowns
	brain.move_speed = rng.randf_range(2.8, 3.5) + 0.06 * floor_number
	brain.run_speed = minf(rng.randf_range(4.9, 5.8) + 0.1 * floor_number, 6.8)
	if clubber:
		brain.clubman()
	elif soldier:
		brain.rifleman()
	brain.name = "Brain"
	c.add_child(brain)
	c.died.connect(_on_clown_died)
	clowns.append(c)
	return c


## A Klappersoldat, set up like an ordinary soldier and then given its own
## (slower, heavier-hitting, never-running) settings. Not yet placed.
func spawn_klapper() -> Klappersoldat:
	var c := Klappersoldat.new()
	c.max_health = 100.0 * (1.0 + 0.1 * (floor_number - 1))     # the Klappersoldat multiplies this
	_world.add_child(c)
	var brain := ClownBrain.new()
	brain.maze = maze
	brain.player = player
	brain.others = clowns
	brain.move_speed = rng.randf_range(2.8, 3.5) + 0.06 * floor_number
	brain.run_speed = minf(rng.randf_range(4.9, 5.8) + 0.1 * floor_number, 6.8)
	c.setup_brain(brain)
	brain.name = "Brain"
	c.add_child(brain)
	c.died.connect(_on_clown_died)
	clowns.append(c)
	return c


## A Rattlejack: a machine gunner with a Lewis gun, firing in bursts. Not yet placed.
func spawn_rattlejack() -> Rattlejack:
	var c := Rattlejack.new()
	c.max_health = 100.0 * (1.0 + 0.1 * (floor_number - 1))
	_world.add_child(c)
	c.give_rifle()
	var brain := ClownBrain.new()
	brain.maze = maze
	brain.player = player
	brain.others = clowns
	brain.move_speed = rng.randf_range(2.6, 3.2) + 0.06 * floor_number      # carrying 12 kg of gun
	brain.run_speed = minf(rng.randf_range(4.4, 5.2) + 0.1 * floor_number, 6.2)
	c.setup_brain(brain)
	brain.name = "Brain"
	c.add_child(brain)
	c.died.connect(_on_clown_died)
	clowns.append(c)
	return c


## Der Zornhauptmann: an officer with a pistol and a sabre. Not yet placed.
func spawn_zornhauptmann() -> Zornhauptmann:
	var c := Zornhauptmann.new()
	c.max_health = 100.0 * (1.0 + 0.1 * (floor_number - 1))     # times officer_health_multiplier
	_world.add_child(c)
	c.give_officer_kit()
	var brain := ClownBrain.new()
	brain.maze = maze
	brain.player = player
	brain.others = clowns
	c.setup_brain(brain)
	brain.move_speed += 0.04 * floor_number
	brain.run_speed = brain.move_speed
	brain.name = "Brain"
	c.add_child(brain)
	c.died.connect(_on_clown_died)
	clowns.append(c)
	return c


## Tables in dead-end side rooms (one on early floors, now and then two),
## each with two or three sat round it. Returns how many were seated.
## Fuel drums are placed with the rest of the dressing; once the tables are in
## too, nudge any drum that ended up inside something.
func _clear_drums() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(maze):
		return
	for b: ExplosiveBarrel in get_tree().get_nodes_in_group(&"barrels"):
		if is_instance_valid(b) and b.is_inside_tree():
			b.clear_spot(maze.cell_center(maze.cell_of(b.global_position)))


func _place_tables(soldier_share: float) -> int:
	var rooms: Array[Vector2i] = []
	for c: Vector2i in maze.side_cells:
		if maze.path_cells(maze.start_cell, c) >= 3 and c != maze.exit_cell:
			rooms.append(c)
	rooms.shuffle()
	var tables := mini(rooms.size(), 1 if floor_number <= 2 or rng.randf() < 0.5 else 2)
	var n := 0
	for i in tables:
		var cell: Vector2i = rooms[i]
		var t := MessTable.new()
		_world.add_child(t)
		t.global_position = maze.cell_center(cell)
		t.rotation.y = PI * 0.5 * (rng.randi() % 2)
		t.player = player
		var seats := 2 + rng.randi() % 2
		for k in seats:
			var soldier := rng.randf() < soldier_share * 1.5
			var c := _spawn_clown(soldier, false)
			t.seat(c, k)
			n += 1
	return n


func _clear_floor() -> void:
	if events and events.room and is_instance_valid(events.room):
		events.room.queue_free()
		events.room = null
	if is_instance_valid(player):
		player.in_event = false
		player.dismount()
	if is_instance_valid(_world):
		_world.queue_free()
	clowns.clear()
	base = null
	Blood.clear()


## The killcam has come back to full speed on the last body: the coroner's
## report, its brutality score and the tickets it is worth, with fanfare.
func _on_finale_focus(c: Clown) -> void:
	_pending_report = {}
	if c == null or not is_instance_valid(c):
		return
	# worked out now, while the body is fresh; shown once the camera is back
	_pending_report = Injuries.assess(c)


## The killcam is completely over and the view is back with the player: now
## the brutality report and its tickets. (Nothing if it was cut short.)
func _on_finale_over() -> void:
	var r := _pending_report
	_pending_report = {}
	if kill_cam.aborted != "" or r.is_empty() or state != State.PLAYING:
		if _exit_banner_due and state == State.PLAYING:
			_flash("EXIT OPEN")
		_exit_banner_due = false
		return
	last_report = r
	brutality.show_report(last_report)
	run_tickets += int(last_report.tickets)
	Records.add(save, "brutality_tickets", int(last_report.tickets))
	save["best_brutality"] = maxi(int(save.get("best_brutality", 0)), int(last_report.score))
	_refresh_hud()


## A joker locker shot open: a bonus, not a kill (it was long dead).
func _on_locker_opened(l: JokerLocker) -> void:
	run_tickets += l.tickets
	Records.add(save, "locker_jokers")
	_flash("LOCKER JOKER!   +%d TICKETS" % l.tickets)
	_refresh_hud()


func _on_clown_died(c: Clown) -> void:
	kills += 1
	if player and player.curse:
		player.curse.on_kill(c)
	Records.kill(save, c)
	remaining -= 1
	var headshot := c.last_hit_zone == &"Neck"
	run_tickets += 2 if headshot else 1
	if player.stats.lifesteal > 0.0:
		player.heal(player.stats.lifesteal)
	if headshot and player.stats.slowmo:
		Engine.time_scale = 0.3
		_slow_until = Time.get_ticks_msec() + 450
	if remaining <= 0 and not _floor_finale:
		# the last of them: show it go down (once per floor)
		_floor_finale = true
		_slow_until = 0
		if kill_cam and kill_cam.play(c):
			_exit_banner_due = true       # shown once the camera and the report are done
		else:
			_flash("EXIT OPEN")
	if remaining <= 0:
		exit_open = true
		_exit_light.light_color = Color(0.3, 1.0, 0.4)
		_exit_light.light_energy = 4.0
	_refresh_hud()


## Gunshots carry along the corridors; clowns close enough come looking.
func _on_player_fired(weapon: int) -> void:
	if player.in_event:
		return
	for c: Clown in clowns:
		if is_instance_valid(c) and not c.dead:
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b:
				b.hear(player.global_position, 1 if weapon in [FpsPlayer.SHOTGUN, FpsPlayer.REVOLVER, FpsPlayer.TRENCH, FpsPlayer.RIFLE] else 0)   # the shotguns, the revolver and the .303 carry further


## A loud noise anywhere (an explosion): clowns within `cells` come looking.
func noise_at(where: Vector3, cells: int) -> void:
	for c: Clown in clowns:
		if is_instance_valid(c) and not c.dead:
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b:
				b.hear(where, cells)


func _on_player_died() -> void:
	run_tickets = int(round(run_tickets * (1.0 + 0.2 * int(save.perks.get("pockets", 0)))))
	save.tickets = int(save.tickets) + run_tickets
	save.best_floor = maxi(int(save.best_floor), floor_number)
	Records.add(save, "tickets_earned", run_tickets)
	var hist: Array = save.get("history", [])
	hist.push_front({floor = floor_number, kills = kills, tickets = run_tickets})
	save.history = hist.slice(0, 6)
	_new_trophies = Records.new_trophies(save)
	_save()
	_set_state(State.DEAD)


func _process(_delta: float) -> void:
	if _slow_until > 0 and Time.get_ticks_msec() >= _slow_until and not (kill_cam and kill_cam.active):
		_slow_until = 0
		Engine.time_scale = 1.0
	if state == State.PLAYING and is_instance_valid(_exit) and is_instance_valid(player):
		if exit_open and player.global_position.distance_to(_exit.global_position) < 1.3:
			_offer_upgrades()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match state:
		State.MENU:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				go_base()
		State.BASE:
			if event.keycode == KEY_ESCAPE:
				_show_menu()
		State.SHOP:
			if event.keycode in [KEY_ESCAPE, KEY_E]:
				close_shop()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_buy_perk(event.keycode - KEY_1)
		State.CONFIRM:
			if event.keycode == KEY_ESCAPE:
				_show_menu()
		State.UPGRADE:
			if event.keycode in [KEY_1, KEY_2, KEY_3]:
				_pick_upgrade(event.keycode - KEY_1)
		State.DEAD:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]:
				go_base()


# --- upgrades and perks ---------------------------------------------------------
func _offer_upgrades() -> void:
	if not _event_upgrade:
		Records.add(save, "floors")
		_save()
	var pool := UPGRADES.filter(func(u: Dictionary) -> bool: return not (u.id in ["saw", "rush", "bath", "drum"] and u.id in taken))
	pool.shuffle()
	_offer = pool.slice(0, 3)
	_set_state(State.UPGRADE)


func _pick_upgrade(i: int) -> void:
	if i < 0 or i >= _offer.size():
		return
	_apply_upgrade(_offer[i].id)
	if _event_upgrade:
		_event_upgrade = false
		_set_state(State.PLAYING)
		return
	next_floor()


## An event room paid out an upgrade: choose one, then carry on.
func offer_event_upgrade() -> void:
	if state != State.PLAYING:
		return
	_event_upgrade = true
	_offer_upgrades()


## A kill inside an event room: counts for the run, not for the floor.
func event_kill(c: Clown) -> void:
	kills += 1
	Records.kill(save, c)
	run_tickets += 2 if c.last_hit_zone == &"Neck" else 1
	if player.stats.lifesteal > 0.0:
		player.heal(player.stats.lifesteal)
	_refresh_hud()


func world() -> Node3D:
	return _world


## A longer, bigger message than _flash, for event results.
func event_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.0)


func _apply_upgrade(id: String) -> void:
	taken.append(id)
	var s: Dictionary = player.stats
	match id:
		"hollow": s.damage *= 1.25
		"trigger": s.fire_rate *= 1.2
		"pellets": s.pellets += 3
		"choke": s.spread *= 0.7
		"meat":
			s.max_health += 30.0
			player.heal(30.0)
		"legs": s.speed *= 1.12
		"leech": s.lifesteal += 4.0
		"saw": s.pistol_dismember = true
		"rush": s.slowmo = true
		"bath": s.blood *= 2.0
		"drum": player.give_mp18_drum()


func _buy_perk(i: int) -> void:
	if i < 0 or i >= PERKS.size():
		return
	var p: Dictionary = PERKS[i]
	var owned := int(save.perks.get(p.id, 0))
	if owned >= p.max or int(save.tickets) < p.cost:
		return
	save.tickets = int(save.tickets) - p.cost
	save.perks[p.id] = owned + 1
	_save()
	if state == State.SHOP:
		open_shop()


## The Quartermaster's booth: perks for tickets.
func open_shop() -> void:
	_set_state(State.SHOP)
	_title("QUARTERMASTER", 44)
	_title("%d tickets" % int(save.tickets), 24)
	for i in PERKS.size():
		var p: Dictionary = PERKS[i]
		var owned := int(save.perks.get(p.id, 0))
		var label := "[%d]  %s  -  %s   (%d/%d)   %s" % [i + 1, p.name, p.desc, owned, p.max, "MAXED" if owned >= p.max else "%d tickets" % p.cost]
		var b := _button(label, _buy_perk.bind(i))
		b.disabled = owned >= p.max or int(save.tickets) < p.cost
	_button("Done  [E / Esc]", close_shop)


func close_shop() -> void:
	_set_state(State.BASE)
	if base:
		base.refresh()


## Wipe the save: tickets, perks, trophies, stats, all of it.
func new_game(confirmed := false) -> void:
	if not confirmed:
		_set_state(State.CONFIRM)
		_title("NEW GAME", 48)
		_title("This wipes everything: tickets, perks, trophies and every stat.", 22)
		_title("It cannot be undone.", 22)
		_button("Yes, wipe it all", new_game.bind(true))
		_button("No  [Esc]", _show_menu)
		return
	save = NEW_SAVE.duplicate(true)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_save()
	_show_menu()
	_flash("A FRESH START")


# --- world dressing -------------------------------------------------------------
func _build_environment() -> void:
	# Overcast dusk above; below ground, damp concrete lit only by bare bulbs,
	# with a haze in the air that the bulbs glow through.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.065, 0.075)
	sky_mat.sky_horizon_color = Color(0.26, 0.24, 0.23)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.04, 0.035, 0.03)
	sky_mat.ground_horizon_color = Color(0.2, 0.18, 0.16)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sky_energy_multiplier = 0.8
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.31, 0.34)
	env.ambient_light_energy = 0.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.ssr_enabled = true                    # wet floors pick up the bulbs
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.ssao_radius = 1.2
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.085, 0.08)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.62, 0.58, 0.52)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 32.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_world_env = we
	_bunker_env = env
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_color = Color(0.58, 0.62, 0.72)
	sun.light_energy = 0.45
	sun.light_volumetric_fog_energy = 0.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(-140.0), 0.0)
	add_child(sun)


func is_trench_floor(n: int) -> bool:
	return trench_every > 0 and n > 0 and n % trench_every == 0


## Trench floors are outdoors by day: the overcast sky and its light; the
## bunkers and the base keep their dark.
func _apply_floor_look(outdoor: bool) -> void:
	if _world_env == null:
		return
	if outdoor:
		if _trench_env == null:
			_trench_env = TrenchArt.make_environment()
		_world_env.environment = _trench_env
		_world_env.camera_attributes = TrenchArt.make_camera_attributes()
		TrenchArt.setup_sun(_sun)
	else:
		_world_env.environment = _bunker_env
		_world_env.camera_attributes = null
		_sun.light_color = Color(0.58, 0.62, 0.72)
		_sun.light_energy = 0.45
		_sun.light_angular_distance = 0.0
		_sun.light_volumetric_fog_energy = 0.3
		_sun.shadow_opacity = 1.0
		_sun.shadow_blur = 1.0
		_sun.directional_shadow_max_distance = 40.0
		_sun.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(-140.0), 0.0)


func _build_exit() -> void:
	_exit = Node3D.new()
	_world.add_child(_exit)
	_exit.global_transform = maze.exit_transform()
	var door := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 2.1, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.1)
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	door.mesh = box
	door.position.y = 1.05
	_exit.add_child(door)
	_exit_light = OmniLight3D.new()
	_exit_light.position.y = 1.6
	_exit_light.omni_range = 6.0
	_exit_light.light_color = Color(1.0, 0.15, 0.1)
	_exit_light.light_energy = 1.5
	if maze is TrenchMaze:
		_exit_light.omni_range = 3.5            # by day it only needs to mark the door
		_exit_light.light_energy = 0.8
	_exit.add_child(_exit_light)


# --- interface ------------------------------------------------------------------
func _build_ui() -> void:
	main_menu = MainMenu.new()
	main_menu.name = "MainMenu"
	add_child(main_menu)
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_hud = Label.new()
	_hud.position = Vector2(20, 14)
	_hud.add_theme_font_size_override("font_size", 20)
	_ui.add_child(_hud)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(260, 16)
	_health_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_health_bar.position += Vector2(20, -40)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.6, 0.05, 0.05)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_ui.add_child(_health_bar)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position.y = 90
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.modulate.a = 0.0
	_ui.add_child(_banner)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(centre)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 14)
	centre.add_child(_panel)


func _set_state(s: State) -> void:
	state = s
	get_tree().paused = s in [State.UPGRADE, State.MENU, State.SHOP, State.CONFIRM]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if s in [State.PLAYING, State.BASE] else Input.MOUSE_MODE_VISIBLE
	for n in _panel.get_children():
		n.queue_free()
	if s != State.MENU and main_menu:
		main_menu.close()
	if s != State.PLAYING and brutality and brutality.shown:
		brutality.clear()
	_hud.visible = s in [State.PLAYING, State.UPGRADE, State.BASE]
	_health_bar.visible = _hud.visible
	match s:
		State.UPGRADE:
			_title("YOUR PRIZE" if _event_upgrade else "FLOOR %d CLEARED" % floor_number, 34)
			_title("Pick one", 20)
			for i in _offer.size():
				_button("[%d]  %s  -  %s" % [i + 1, _offer[i].name, _offer[i].desc], _pick_upgrade.bind(i))
		State.DEAD:
			_title("YOU DIED", 54)
			_title("Floor %d   |   %d kills   |   +%d tickets" % [floor_number, kills, run_tickets], 22)
			if _run_best_pierce >= 2:
				_title("Best rifle round: %d at once" % _run_best_pierce, 18)
			for t: String in _new_trophies:
				_title("NEW TROPHY: %s  (+%d tickets)" % [t, Records.TROPHY_BONUS], 20)
			_button("Back to base  [Enter]", go_base)
	_refresh_hud()


func _show_menu() -> void:
	Engine.time_scale = 1.0
	_clear_floor()
	if is_instance_valid(player):
		player.queue_free()
	_set_state(State.MENU)
	main_menu.open([["Continue", go_base], ["New Game", new_game], ["Quit", get_tree().quit]],
		"Best floor %d   ·   %d kills   ·   %d tickets   ·   %d/%d trophies" % [int(save.best_floor), int(save.total_kills), int(save.tickets), (save.get("trophies", []) as Array).size(), Records.TROPHIES.size()],
		"WASD move   ·   Shift sprint   ·   Mouse aim   ·   Click fire   ·   R reload   ·   1-4, 6 weapons   ·   E use   ·   F light   ·   G god mode")


func _title(text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	_panel.add_child(l)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(620, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	_panel.add_child(b)
	return b


func _refresh_hud() -> void:
	if not is_instance_valid(player):
		return
	if state == State.BASE or state == State.SHOP:
		_hud.text = "BASE     Tickets: %d     [E] use     [Esc] title screen%s" % [int(save.tickets), "     GOD MODE" if FpsPlayer.god_mode else ""]
		_health_bar.max_value = player.stats.max_health
		_health_bar.value = player.health
		return
	var w: Dictionary = FpsPlayer.WEAPONS[player.weapon]
	_hud.text = "Floor %d     Clowns left: %d     Tickets: %d     %s %d/%d%s" % [floor_number, maxi(remaining, 0), run_tickets, w.get("label", w.name), player.ammo[player.weapon], player.mag_of(player.weapon),
		("     EXIT OPEN - find the green door" if exit_open else "") + ("     GOD MODE" if FpsPlayer.god_mode else "")]
	_health_bar.max_value = player.stats.max_health
	_health_bar.value = player.health


func _flash(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.8)


# --- saving -------------------------------------------------------------------
func _load() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if parsed is Dictionary:
		for k: String in parsed:
			save[k] = parsed[k]
	# anything an older save lacks (numbers come back from JSON as floats,
	# which is fine; only missing keys and wrong containers are replaced)
	for k: String in NEW_SAVE:
		var want: Variant = NEW_SAVE[k]
		if not save.has(k) or (want is Dictionary and not (save[k] is Dictionary)) or (want is Array and not (save[k] is Array)):
			save[k] = want.duplicate(true) if (want is Dictionary or want is Array) else want


func _save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
