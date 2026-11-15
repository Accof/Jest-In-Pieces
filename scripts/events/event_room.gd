class_name EventRoom
extends Node3D
## Base for everything behind an event door. Built far from the level (a
## pocket of space the player is brought to), with its own exit door that
## stays bolted until the room is done.

signal finished(room: EventRoom, result: Dictionary)

var player: FpsPlayer
var title := "?"
var entry := Transform3D()          ## where the player arrives (local)
var exit_door: EventDoor
var enemies: Array[Clown] = []
var kills := 0
var done := false
var _t := 0.0


## Build the room's geometry and props (override).
func build() -> void:
	pass


## The player is inside and the doors have shut (override).
func begin() -> void:
	pass


## Ends the room: unbolts the exit and reports how it went.
## `result` keys: success, line (text for the banner), tickets, heal, upgrade.
func complete(result: Dictionary) -> void:
	if done:
		return
	done = true
	if exit_door:
		exit_door.set_locked(false)
	finished.emit(self, result)


# --- helpers for building -------------------------------------------------------------
## A solid box with a level material and collision.
func solid(centre: Vector3, size: Vector3, mat_key: String, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = LevelArt._mat(mat_key)
	mi.position = centre
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		body.add_child(cs)
		body.position = centre
		add_child(body)
	return mi


## A closed concrete room: floor, walls, ceiling. Inside spans `size` from `origin`.
func concrete_room(origin: Vector3, size: Vector3, floor_key := "floor_conc", ceiling := true) -> void:
	var t := 0.4
	var c := origin + size * 0.5
	solid(Vector3(c.x, origin.y - t * 0.5, c.z), Vector3(size.x + t * 2, t, size.z + t * 2), floor_key)
	if ceiling:
		solid(Vector3(c.x, origin.y + size.y + t * 0.5, c.z), Vector3(size.x + t * 2, t, size.z + t * 2), "ceil_conc")
	solid(Vector3(origin.x - t * 0.5, c.y, c.z), Vector3(t, size.y, size.z), "wall_conc")
	solid(Vector3(origin.x + size.x + t * 0.5, c.y, c.z), Vector3(t, size.y, size.z), "wall_conc")
	solid(Vector3(c.x, c.y, origin.z - t * 0.5), Vector3(size.x + t * 2, size.y, t), "wall_conc")
	solid(Vector3(c.x, c.y, origin.z + size.z + t * 0.5), Vector3(size.x + t * 2, size.y, t), "wall_conc")


## A bare bulb hanging from `at`.
func bulb(at: Vector3, energy := 3.0, range_ := 9.0, color := Color(1.0, 0.7, 0.45), shadows := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.visible = energy > 0.0
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_
	l.omni_attenuation = 1.5
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 2.0
	l.position = at
	add_child(l)
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	b.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 6.0
	b.material_override = m
	b.position = at
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	return l


## The exit door, in a wall, facing into the room along `facing`.
func make_exit(at: Vector3, facing: Vector3) -> void:
	exit_door = EventDoor.new()
	exit_door.is_exit = true
	exit_door.locked = true
	add_child(exit_door)
	exit_door.position = at
	exit_door.basis = Basis(Vector3.UP.cross(facing).normalized(), Vector3.UP, facing.normalized())
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 2.1)
	q.mesh = qm
	q.material_override = LevelArt._mat("door")
	q.position = Vector3(0, 1.05, 0.01)
	exit_door.add_child(q)


## A clown (or WitzSoldat) under a RoomBrain. `pos` is local to the room.
func spawn(pos: Vector3, body := "clown", mode := "room", gun := false) -> Clown:
	var c := Clown.new()
	c.body = body
	add_child(c)
	c.position = pos
	if body == "witzsoldat":
		c.give_rifle()
	elif gun:
		c.give_gun()
	var b := RoomBrain.new()
	b.name = "Brain"
	b.player = player
	b.mode = mode
	b.floor_y = to_global(pos).y
	c.add_child(b)
	c.died.connect(_on_enemy_died)
	enemies.append(c)
	return c


func _on_enemy_died(c: Clown) -> void:
	kills += 1
	var mgr := get_tree().get_first_node_in_group(&"event_manager")
	if mgr:
		mgr.event_kill(c)
	enemy_died(c)


## Override to react to a death (default: room done when all are dead).
func enemy_died(_c: Clown) -> void:
	if enemies.all(func(e: Clown) -> bool: return not is_instance_valid(e) or e.dead):
		complete({success = true, line = "%s - cleared" % title, tickets = 3, heal = 20.0})


## Everyone in the room comes for the player.
func alert_all() -> void:
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			var b := e.get_node_or_null("Brain")
			if b:
				b.alert(player.global_position)
