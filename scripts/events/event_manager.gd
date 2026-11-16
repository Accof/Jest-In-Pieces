class_name EventManager
extends Node
## Gives each event door on the floor something behind it, takes the player
## through (fade, into a pocket room built far from the level, door bolted),
## pays out when the room is done, and brings them back.

const FEATURES := ["mg_nest", "shooting_gallery", "card_game"]                      # the big set-pieces, once a run each
const ODDITIES := ["high_wire", "grand_staircase", "meat_locker"]
const POCKET := Vector3(4000, 0, 0)               # far from any level

var game: Node
var player: FpsPlayer
var room: EventRoom
var used_features: Array[String] = []
var _door: EventDoor
var _fade: ColorRect
var _busy := false
var _rooms := 0


func _ready() -> void:
	add_to_group(&"event_manager")
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


## A new run: every set-piece is available again.
func new_run() -> void:
	used_features.clear()


## A new floor: decide what is behind each door.
func new_floor() -> void:
	room = null
	var doors := get_tree().get_nodes_in_group(&"event_doors").filter(func(d): return not d.is_exit)
	doors.shuffle()
	var odd := ODDITIES.duplicate()
	odd.shuffle()
	var feature_given := false
	for d: EventDoor in doors:
		var free := FEATURES.filter(func(f: String) -> bool: return not used_features.has(f))
		if not feature_given and not free.is_empty():
			d.set_kind(free.pick_random())
			feature_given = true
			continue
		if odd.is_empty():
			odd = ODDITIES.duplicate()
			odd.shuffle()
		d.set_kind(odd.pop_back())


func make_room(kind: String) -> EventRoom:
	match kind:
		"mg_nest": return MgNest.new()
		"shooting_gallery": return ShootingGallery.new()
		"card_game": return CardGame.new()
		"high_wire": return HighWire.new()
		"grand_staircase": return GrandStaircase.new()
		"meat_locker": return MeatLocker.new()
	return null


func enter(door: EventDoor) -> void:
	if _busy or room != null:
		return
	_busy = true
	_door = door
	door.used = true
	door._refresh()
	if door.kind in FEATURES:
		used_features.append(door.kind)
	await _fade_to(1.0, 0.35)
	room = make_room(door.kind)
	room.player = player
	game.world().add_child(room)
	room.global_position = POCKET + Vector3(_rooms * 300.0, 0, 0)
	_rooms += 1
	room.build()
	room.finished.connect(_on_finished)
	if room.exit_door:
		room.exit_door.on_use = leave
	player.in_event = true
	player.global_transform = room.global_transform * room.entry
	player.velocity = Vector3.ZERO
	player.camera.rotation.x = 0.0
	await get_tree().physics_frame
	room.begin()
	await _fade_to(0.0, 0.45)
	_busy = false


func leave() -> void:
	if _busy or room == null:
		return
	_busy = true
	if player.has_method("dismount"):
		player.dismount()
	await _fade_to(1.0, 0.35)
	var back := _door.global_transform
	player.global_position = back.origin + back.basis.z * 0.9 + Vector3.UP * 0.05
	player.rotation = Vector3(0, atan2(back.basis.z.x, back.basis.z.z) + PI, 0)
	player.velocity = Vector3.ZERO
	player.in_event = false
	room.queue_free()
	room = null
	await get_tree().physics_frame
	await _fade_to(0.0, 0.45)
	_busy = false


func _on_finished(_r: EventRoom, result: Dictionary) -> void:
	Records.add(game.save, "events")
	if result.get("tier", "") == "GOLD":
		Records.add(game.save, "golds")
	if int(result.get("knockdowns", 0)) > 0:
		Records.add(game.save, "knockdowns", int(result.knockdowns))
	var lines: Array[String] = [result.get("line", "Done")]
	var t: int = result.get("tickets", 0)
	if t > 0:
		game.run_tickets += t
		lines.append("+%d tickets" % t)
	var h: float = result.get("heal", 0.0)
	if h > 0.0:
		player.heal(h)
		lines.append("+%d health" % int(h) if h < 900.0 else "full health")
	if result.get("extra", "") != "":
		lines.append(result.extra)
	game.event_banner("\n".join(lines))
	game._refresh_hud()
	if result.get("upgrade", false):
		await get_tree().create_timer(1.8).timeout
		game.offer_event_upgrade()


## A kill inside an event: counts toward the run, but not the floor's clowns.
func event_kill(c: Clown) -> void:
	game.event_kill(c)


func _fade_to(a: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, time)
	await tw.finished
