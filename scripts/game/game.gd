extends Node3D
## The roguelite loop: menu, floors of funhouse maze, upgrades between floors,
## death, and the tickets and perks that carry over between runs.

enum State { MENU, PLAYING, UPGRADE, DEAD }

const SAVE_PATH := "user://clown_save.json"

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
]

## Bought with tickets on the menu; kept between runs.
const PERKS := [
	{id = "skin", name = "Thick Skin", desc = "+10 starting health", cost = 15, max = 5},
	{id = "hair", name = "Hair Trigger", desc = "+5% fire rate", cost = 20, max = 5},
	{id = "start", name = "Head Start", desc = "Begin each run with a random upgrade", cost = 60, max = 1},
]

var state := State.MENU
var floor_number := 0
var kills := 0
var run_tickets := 0
var remaining := 0
var exit_open := false
var taken: Array[String] = []
var save := {tickets = 0, best_floor = 0, total_kills = 0, perks = {}}

var maze: Maze
var player: FpsPlayer
var clowns: Array[Clown] = []
var rng := RandomNumberGenerator.new()

var _world: Node3D
var _exit: Node3D
var _exit_light: OmniLight3D
var _ui: CanvasLayer
var _hud: Label
var _health_bar: ProgressBar
var _banner: Label
var _panel: VBoxContainer
var _offer: Array = []
var _slow_until := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The project's internal name stays "Clown Shooter" so existing save files are still found.
	get_window().title = "Jest In Pieces"
	rng.randomize()
	_load()
	_build_environment()
	_build_ui()
	_show_menu()


# --- flow ---------------------------------------------------------------------
func start_run() -> void:
	floor_number = 0
	kills = 0
	run_tickets = 0
	taken.clear()
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
	player.fired.connect(_on_player_fired)
	player.ammo_changed.connect(_refresh_hud)
	if int(save.perks.get("start", 0)) > 0:
		_apply_upgrade(UPGRADES[rng.randi() % UPGRADES.size()].id)
	next_floor()


func next_floor() -> void:
	floor_number += 1
	_clear_floor()
	_world = Node3D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	maze = Maze.new()
	_world.add_child(maze)
	var size := mini(5 + floor_number / 2, 9)
	maze.generate(size, size, rng.randi())
	var spawn := maze.cell_center(maze.start_cell)
	player.global_position = spawn + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	_build_exit()

	var count := mini(4 + floor_number * 2, 18)
	var gun_share := clampf(0.12 + 0.06 * floor_number, 0.0, 0.5)
	var cells := maze.cells_far_from(maze.start_cell, 3)
	if cells.is_empty():
		cells = maze.cells_far_from(maze.start_cell, 1)
	clowns.clear()
	for i in count:
		var c := Clown.new()
		c.max_health = 100.0 * (1.0 + 0.1 * (floor_number - 1))
		_world.add_child(c)
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		c.global_position = maze.cell_center(cell) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
		c.rotation.y = rng.randf() * TAU
		if rng.randf() < gun_share:
			c.give_gun()
		var brain := ClownBrain.new()
		brain.maze = maze
		brain.player = player
		brain.others = clowns
		brain.move_speed = rng.randf_range(2.8, 3.5) + 0.06 * floor_number
		brain.run_speed = minf(rng.randf_range(4.9, 5.8) + 0.1 * floor_number, 6.8)
		brain.name = "Brain"
		c.add_child(brain)
		c.died.connect(_on_clown_died)
		clowns.append(c)
	remaining = count
	exit_open = false
	_set_state(State.PLAYING)
	_flash("FLOOR %d" % floor_number)


func _clear_floor() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	clowns.clear()
	Blood.clear()


func _on_clown_died(c: Clown) -> void:
	kills += 1
	remaining -= 1
	var headshot := c.last_hit_zone == &"Neck"
	run_tickets += 2 if headshot else 1
	if player.stats.lifesteal > 0.0:
		player.heal(player.stats.lifesteal)
	if headshot and player.stats.slowmo:
		Engine.time_scale = 0.3
		_slow_until = Time.get_ticks_msec() + 450
	if remaining <= 0:
		exit_open = true
		_exit_light.light_color = Color(0.3, 1.0, 0.4)
		_exit_light.light_energy = 4.0
		_flash("EXIT OPEN")
	_refresh_hud()


## Gunshots carry along the corridors; clowns close enough come looking.
func _on_player_fired(weapon: int) -> void:
	for c: Clown in clowns:
		if is_instance_valid(c) and not c.dead:
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b:
				b.hear(player.global_position, 1 if weapon == 1 else 0)


func _on_player_died() -> void:
	save.tickets = int(save.tickets) + run_tickets
	save.best_floor = maxi(int(save.best_floor), floor_number)
	save.total_kills = int(save.total_kills) + kills
	_save()
	_set_state(State.DEAD)


func _process(_delta: float) -> void:
	if _slow_until > 0 and Time.get_ticks_msec() >= _slow_until:
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
				start_run()
			elif event.keycode in [KEY_1, KEY_2, KEY_3]:
				_buy_perk(event.keycode - KEY_1)
		State.UPGRADE:
			if event.keycode in [KEY_1, KEY_2, KEY_3]:
				_pick_upgrade(event.keycode - KEY_1)
		State.DEAD:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]:
				_show_menu()


# --- upgrades and perks ---------------------------------------------------------
func _offer_upgrades() -> void:
	var pool := UPGRADES.filter(func(u: Dictionary) -> bool: return not (u.id in ["saw", "rush", "bath"] and u.id in taken))
	pool.shuffle()
	_offer = pool.slice(0, 3)
	_set_state(State.UPGRADE)


func _pick_upgrade(i: int) -> void:
	if i < 0 or i >= _offer.size():
		return
	_apply_upgrade(_offer[i].id)
	next_floor()


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
	_show_menu()


# --- world dressing -------------------------------------------------------------
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.18, 0.28)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.03, 0.07)
	env.fog_density = 0.035
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_exit() -> void:
	_exit = Node3D.new()
	_world.add_child(_exit)
	_exit.global_position = maze.cell_center(maze.exit_cell)
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
	_exit.add_child(_exit_light)


# --- interface ------------------------------------------------------------------
func _build_ui() -> void:
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
	get_tree().paused = s == State.UPGRADE or s == State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if s == State.PLAYING else Input.MOUSE_MODE_VISIBLE
	for n in _panel.get_children():
		n.queue_free()
	_hud.visible = s == State.PLAYING or s == State.UPGRADE
	_health_bar.visible = _hud.visible
	match s:
		State.UPGRADE:
			_title("FLOOR %d CLEARED" % floor_number, 34)
			_title("Pick one", 20)
			for i in _offer.size():
				_button("[%d]  %s  -  %s" % [i + 1, _offer[i].name, _offer[i].desc], _pick_upgrade.bind(i))
		State.DEAD:
			_title("YOU DIED", 54)
			_title("Floor %d   |   %d kills   |   +%d tickets" % [floor_number, kills, run_tickets], 22)
			_button("Back to the menu  [Enter]", _show_menu)
	_refresh_hud()


func _show_menu() -> void:
	Engine.time_scale = 1.0
	_clear_floor()
	if is_instance_valid(player):
		player.queue_free()
	_set_state(State.MENU)
	_title("JEST IN PIECES", 60)
	_title("Best floor %d   |   %d kills all time   |   %d tickets" % [int(save.best_floor), int(save.total_kills), int(save.tickets)], 20)
	_button("START RUN  [Enter]", start_run)
	_title("Permanent perks", 22)
	for i in PERKS.size():
		var p: Dictionary = PERKS[i]
		var owned := int(save.perks.get(p.id, 0))
		var label := "[%d]  %s  -  %s   (%d/%d)   %s" % [i + 1, p.name, p.desc, owned, p.max, "MAXED" if owned >= p.max else "%d tickets" % p.cost]
		var b := _button(label, _buy_perk.bind(i))
		b.disabled = owned >= p.max or int(save.tickets) < p.cost
	_title("WASD move   Shift sprint   Mouse aim   Click fire   R reload   1/2 weapons   F light", 16)


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
	var w: Dictionary = FpsPlayer.WEAPONS[player.weapon]
	_hud.text = "Floor %d     Clowns left: %d     Tickets: %d     %s %d/%d%s" % [floor_number, maxi(remaining, 0), run_tickets, w.name, player.ammo[player.weapon], w.mag,
		"     EXIT OPEN - find the green door" if exit_open else ""]
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
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		for k: String in parsed:
			save[k] = parsed[k]


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
