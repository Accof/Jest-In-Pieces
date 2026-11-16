class_name JokerLocker
extends Node3D
## A bank of three tall, thin WW1 steel lockers against a corridor wall. One
## has a little joker card pinned to its door, and something inside it
## laughs when you are near. Put enough rounds through that door and it
## bursts open: out falls a clown that has been dead in there a long time,
## riddled with your bullets. Worth extra tickets.
##
## Placeholder art and sound (code-built meshes; tools/gen_locker_assets.py).

signal opened(locker: JokerLocker)

const W := 0.62                 ## one locker's width
const D := 0.5                  ## depth
const H := 2.05                 ## height
const T := 0.018                ## sheet steel
const LAYER_WORLD := 1
const SFX := "res://art/locker/sfx/%s.wav"

## Which of the three is the joker's (-1: none, a plain bank).
@export var joker_index := 1
## Damage the door takes before the latch gives.
@export var door_health := 90.0
## Tickets for finding it.
@export var tickets := 8
## How near the player has to be for it to laugh, and how often it might.
@export var laugh_range := 7.0
@export var laugh_every := Vector2(4.5, 10.0)
@export_range(0.0, 1.0) var laugh_chance := 0.6

var player: Node3D
var is_open := false
var corpse: Clown               ## the clown that fell out
var laughs := 0                 ## test hooks
var hits := 0

var _doors: Array[Node3D] = []
var _door_hp := 0.0
var _laugh_t := 3.0
var _audio: AudioStreamPlayer3D
var _streams := {}
var _shots: Array = []          ## [world pos, dir] of every round through the joker's door
var _paint: StandardMaterial3D
var _dark: StandardMaterial3D
var _rattle := 0.0
var _shells: Array[StaticBody3D] = []


func _ready() -> void:
	add_to_group(&"joker_lockers")
	_door_hp = door_health
	_laugh_t = randf_range(1.5, 4.0)
	_paint = StandardMaterial3D.new()
	_paint.albedo_texture = load("res://art/locker/locker_paint.png")
	_paint.uv1_triplanar = true
	_paint.uv1_scale = Vector3(1.6, 0.8, 1.6)
	_paint.metallic = 0.35
	_paint.roughness = 0.72
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.02, 0.02, 0.018)
	_dark.roughness = 1.0
	for i in 3:
		_build_locker(i)
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 3.0
	_audio.max_distance = 30.0
	_audio.position = _locker_x(maxi(joker_index, 0)) + Vector3(0, 1.4, D * 0.5)
	add_child(_audio)


func _locker_x(i: int) -> Vector3:
	return Vector3((i - 1) * W, 0, 0)


## One locker: a shell with its own colliders, a hinged door (shootable),
## louvres top and bottom, a handle, a stencilled number.
func _build_locker(i: int) -> void:
	var o := _locker_x(i)
	var shell := StaticBody3D.new()
	shell.collision_layer = LAYER_WORLD
	shell.collision_mask = 0
	shell.position = o
	add_child(shell)
	_shells.append(shell)
	var hw := W * 0.5
	var parts := [
		[Vector3(W, H, T), Vector3(0, H * 0.5, -D * 0.5 + T * 0.5)],                 # back
		[Vector3(T, H, D), Vector3(-hw + T * 0.5, H * 0.5, 0)],                       # sides
		[Vector3(T, H, D), Vector3(hw - T * 0.5, H * 0.5, 0)],
		[Vector3(W, T, D), Vector3(0, H - T * 0.5, 0)],                               # top
		[Vector3(W, 0.08, D), Vector3(0, 0.04, 0)],                                   # plinth
	]
	for p: Array in parts:
		_box(shell, p[0], p[1], _paint, true)
	# a sloped cap so it reads as a locker, not a box
	_box(shell, Vector3(W + 0.01, 0.025, D + 0.03), Vector3(0, H + 0.0125, 0.01), _paint, false)
	# the door, hung on its left edge
	var pivot := Node3D.new()
	pivot.position = Vector3(-hw + 0.004, 0, D * 0.5 - T * 0.5)
	shell.add_child(pivot)
	var door := Door.new()
	door.locker = self
	door.index = i
	door.collision_layer = LAYER_WORLD
	door.collision_mask = 0
	pivot.add_child(door)
	var dw := W - 0.012
	var dh := H - 0.1
	_box(door, Vector3(dw, dh, T), Vector3(dw * 0.5, 0.08 + dh * 0.5, 0), _paint, true)
	# pressed louvres: a dark slot behind each lip
	for band: float in [dh - 0.22, 0.32]:
		for k in 5:
			var y := 0.08 + band + k * 0.035
			_box(door, Vector3(dw * 0.62, 0.012, 0.004), Vector3(dw * 0.5, y, T * 0.5 + 0.001), _dark, false)
			var lip := _box(door, Vector3(dw * 0.62, 0.016, 0.012), Vector3(dw * 0.5, y + 0.008, T * 0.5 + 0.006), _paint, false)
			lip.rotation.x = -0.6
	# handle and latch plate on the free edge
	var steel := LevelArt._mat("steel_box")
	_box(door, Vector3(0.05, 0.16, 0.006), Vector3(dw - 0.06, 1.05, T * 0.5 + 0.003), steel, false)
	_box(door, Vector3(0.02, 0.12, 0.03), Vector3(dw - 0.06, 1.05, T * 0.5 + 0.02), steel, false)
	# a stencilled number
	var num := Label3D.new()
	num.text = str(randi_range(11, 98))
	num.font_size = 48
	num.pixel_size = 0.0012
	num.modulate = Color(0.78, 0.76, 0.66, 0.85)
	num.outline_size = 0
	num.shaded = true
	num.position = Vector3(dw * 0.5, 1.55, T * 0.5 + 0.002)
	door.add_child(num)
	if i == joker_index:
		var card := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.075, 0.105)
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://art/locker/joker_card.png")
		m.roughness = 0.8
		q.material = m
		card.mesh = q
		card.position = Vector3(dw * 0.5 + 0.07, 1.36, T * 0.5 + 0.003)
		card.rotation.z = randf_range(-0.25, 0.25)
		door.add_child(card)
		_box(door, Vector3(0.008, 0.008, 0.01), card.position + Vector3(0, 0.04, 0.003), steel, false)   # the nail
	_doors.append(pivot)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		parent.add_child(cs)
	return mi


func _sound(name_: String, db := 0.0, at: Vector3 = Vector3.INF) -> void:
	if not _streams.has(name_):
		_streams[name_] = load(SFX % name_)
	var p := _audio
	if at != Vector3.INF:
		p = AudioStreamPlayer3D.new()
		p.unit_size = 3.0
		add_child(p)
		p.global_position = at
		p.finished.connect(p.queue_free)
	p.stream = _streams[name_]
	p.volume_db = db
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


# --- the laugh ------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _rattle > 0.0:
		_rattle -= delta
		var d: Node3D = _doors[joker_index]
		d.rotation.y = -0.012 * sin(_rattle * 70.0) * clampf(_rattle * 3.0, 0.0, 1.0) if _rattle > 0.0 else 0.0
	if is_open or joker_index < 0 or player == null or not is_instance_valid(player):
		return
	_laugh_t -= delta
	if _laugh_t > 0.0:
		return
	_laugh_t = randf_range(laugh_every.x, laugh_every.y)
	if player.global_position.distance_to(global_position) < laugh_range and randf() < laugh_chance:
		laugh()


func laugh() -> void:
	laughs += 1
	_sound("laugh_%d" % (randi() % 3), 2.0)
	_rattle = 0.5
	get_tree().create_timer(randf_range(0.2, 0.6)).timeout.connect(func() -> void:
		if not is_open:
			_sound("rattle_%d" % (randi() % 2), -6.0, _hole_world(Vector3(W * 0.9, 1.05, 0))))


func _hole_world(door_local: Vector3) -> Vector3:
	return (_doors[maxi(joker_index, 0)] as Node3D).global_transform * door_local


# --- being shot -----------------------------------------------------------------------
## A round through a door: a bright nick in the paint, a dent you can hear,
## and on the joker's door a spit of blood back out of the hole.
func door_shot(door: Door, pos: Vector3, dir: Vector3, damage: float) -> void:
	hits += 1
	_sound("dent_%d" % (randi() % 3), -2.0, pos)
	MechFx.sparks(self, pos, -dir, 0.35)
	var hole := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * randf_range(0.011, 0.016)
	q.material = _dark
	hole.mesh = q
	door.add_child(hole)
	hole.global_position = pos
	hole.position.z = T * 0.5 + 0.0015
	hole.rotation = Vector3.ZERO
	if door.index != joker_index or is_open:
		return
	_shots.append([pos, dir])
	if randf() < 0.6:
		Blood.spawn_hit(pos - dir * 0.01, -dir, 0.25)
	_door_hp -= damage
	_rattle = maxf(_rattle, 0.15)
	if _door_hp <= 0.0:
		burst()


## The latch gives: the door slams back on its hinges and the body inside
## pitches out onto the floor.
func burst() -> void:
	if is_open or joker_index < 0:
		return
	is_open = true
	_rattle = 0.0
	var door: Node3D = _doors[joker_index]
	_sound("burst", 4.0)
	var tw := create_tween()
	tw.tween_property(door, "rotation:y", deg_to_rad(-118.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(door, "rotation:y", deg_to_rad(-96.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(door, "rotation:y", deg_to_rad(-104.0), 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# the body is wedged in by its shoulders: let the side walls go so it can
	# pitch out cleanly (they are still drawn; nothing else needs them)
	for cs in _shells[joker_index].get_children():
		if cs is CollisionShape3D and absf((cs as CollisionShape3D).position.x) > W * 0.3:
			(cs as CollisionShape3D).disabled = true
	_drop_body()
	opened.emit(self)


func _drop_body() -> void:
	var c := Clown.new()
	c.name = "LockerJoker"
	get_parent().add_child(c)
	c.global_transform = Transform3D(global_basis, global_transform * (_locker_x(joker_index) + Vector3(0, 0.08, 0.03)))
	corpse = c
	await get_tree().physics_frame
	if not is_instance_valid(c):
		return
	LockerJoker.dress(c)
	_riddle(c)
	c.dead = true
	c.set_process(false)
	var fwd := global_basis.z
	c.ragdoll.start(LockerJoker.profile_pitch_out(), fwd, fwd * 1.3 + Vector3.DOWN * 0.3)
	# it was leaning on the door: the whole stiff body tips out from the feet,
	# like a plank, and only folds once it is going over
	var feet := c.global_position
	var spin := global_basis.x * 2.4
	for pb: PhysicalBone3D in c.ragdoll.bones.values():
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, spin.cross(pb.global_position - feet) + fwd * 0.5)
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)
	c.gore.start_bleeding()
	LockerJoker.spill_cards(c, fwd)
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		if is_instance_valid(c):
			_sound("thump", 2.0, c.global_position + fwd * 0.9))


## Bullet holes where the player's rounds went through the door, and a few
## older ones besides: it has been shot before.
func _riddle(c: Clown) -> void:
	var space := get_world_3d().direct_space_state
	var made := 0
	var tries: Array = _shots.duplicate()
	tries.shuffle()
	var fwd := global_basis.z
	for k in 18:
		if tries.size() <= k:
			var pb: PhysicalBone3D = c.ragdoll.bones.values()[randi() % c.ragdoll.bones.size()]
			var aim := pb.global_position + Vector3(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06), randf_range(-0.06, 0.06))
			var from := aim + fwd * 0.6 + global_basis.x * randf_range(-0.15, 0.15)
			tries.append([from, (aim - from).normalized()])
		var shot: Array = tries[k]
		var q := PhysicsRayQueryParameters3D.create(shot[0] - shot[1] * 0.05, shot[0] + shot[1] * 1.0, 1 << 2)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not (hit.collider is PhysicalBone3D) or (hit.collider as Node).get_meta(&"clown", null) != c:
			continue
		c.gore.add_wound((hit.collider as PhysicalBone3D).bone_name, hit.position, 30.0)
		made += 1
		if made >= 12:
			break
	LockerJoker.soak(c)


class Door extends StaticBody3D:
	var locker: JokerLocker
	var index := 0

	func shot(pos: Vector3, dir: Vector3, damage: float) -> void:
		locker.door_shot(self, pos, dir, damage)
