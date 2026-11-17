class_name KillCam
extends Node3D
## The final-kill camera. When the last enemy of a floor or an event room goes
## down, the view leaves the player's eyes for a moment: a camera picked to
## suit how and where it died (low and to the side, three-quarter, over the
## shoulder, from above, down at floor level, from behind it, or riding along
## with a body that is falling a long way), time slowing almost to a stop and
## creeping back, the body doing whatever the physics does with it, a beat at
## full speed on the corpse, then back to the player's eyes.
##
## It only watches. The ragdoll, gore and impulses are never touched; the
## camera adapts to them. If anything goes wrong (the body is freed, the
## player dies, the game pauses, the floor changes, it runs too long) it
## puts everything back at once: time, camera, controls, sound.

signal finished
## Time has come back to full speed and it is resting on the body: the moment
## for anything to show over it (the brutality report). Call hold() to stay.
signal focus_started(clown: Clown)

# --- settings --------------------------------------------------------------------------
@export var enabled := true
@export var min_time_scale := 0.25
@export var impact_seconds := 0.2          ## 100% down to min_time_scale
@export var slow_seconds := 1.0            ## held at min_time_scale
@export var recover_seconds := 0.8         ## back up to 100%
@export var focus_seconds := 1.0           ## at full speed, still on the body
@export var return_seconds := 0.4          ## back to the player's eyes
@export var max_seconds := 5.0             ## never longer than this, all told
@export var fly_in_seconds := 0.35         ## from the player's eyes to the shot
@export var dynamic_angles := true         ## off: always the three-quarter shot
@export var stationary_shots := true
@export var tracking_shots := true
@export var avoid_repeats := true
@export var follow_falls := true
@export var collision_checks := true
@export var audio_muffle := true
@export var fov := 60.0
@export var distance := 2.9                ## camera to body, before it is pulled in
@export var height := 1.35                 ## of the eye-level shots, above the floor
@export var aim_smoothing := 3.0           ## how fast a still camera turns to keep the body framed
@export var track_smoothing := 2.6         ## how fast a tracking camera follows
@export var fall_drop := 1.2               ## a drop below the feet worth following (m)
@export var letterbox := true

const LAYER_WORLD := 1
const SHOTS := ["low_side", "three_quarter", "over_shoulder", "elevated", "ground", "rear", "tracking"]

# --- state (read by the tests) ----------------------------------------------------------
var active := false
var shot := ""                 ## the composition in use ("player" = stayed in first person)
var tracking := false
static var history: Array[String] = []    ## the last few shots (kept across floors, to vary them)
var candidates_tried := 0
var aborted := ""              ## why the last one stopped early ("" = ran its course)
var player: FpsPlayer
var hide_nodes: Array = []     ## HUD bits hidden while it runs
var can_run: Callable          ## extra check from the game (still playing?)

var _target: Clown
var _cam: Camera3D
var _t := 0.0                  ## real seconds since it began
var _end_focus := 0.0
var _returning := -1.0
var _from := Transform3D()
var _shot_xf := Transform3D()
var _look := Vector3.ZERO
var _offset := Vector3.ZERO
var _last_focus := Vector3.ZERO
var _moving_until := 0.0
var _hold_until := 0.0
var _held := 0.0
var _focus_sent := false
var _dip := false              ## cut through black instead of flying (path blocked)
var _ret_dip := false
var _overlay: ColorRect
var _bars: Array[ColorRect] = []
var _lowpass: AudioEffectLowPassFilter
var _was_visible := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"kill_cam")
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.near = 0.05
	add_child(_cam)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if i == 0 else Control.PRESET_BOTTOM_WIDE)
		bar.visible = false
		layer.add_child(bar)
		_bars.append(bar)
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)
	set_process(false)


## Start it on `clown` (just killed). Returns false if it will not run.
func play(clown: Clown) -> bool:
	if not enabled or active or player == null or not is_instance_valid(player) or player.dead:
		return false
	if not is_instance_valid(clown) or not clown.is_inside_tree() or get_tree().paused:
		return false
	if can_run.is_valid() and not can_run.call():
		return false
	_target = clown
	active = true
	aborted = ""
	_t = 0.0
	_moving_until = 0.0
	_hold_until = 0.0
	_held = 0.0
	_focus_sent = false
	_returning = -1.0
	_last_focus = _focus()
	_prev_focus = Vector3.INF
	_speed = 0.0
	_choose()
	history.push_front(shot)
	history = history.slice(0, 3)
	_end_focus = impact_seconds + slow_seconds + recover_seconds + focus_seconds
	# take over from the player
	player.cinematic = true
	for n: Variant in hide_nodes:
		if is_instance_valid(n) and (n as Object).get("visible") != null:
			_was_visible[n] = (n as Object).get("visible")
			(n as Object).set("visible", false)
	_from = player.camera.global_transform
	if shot != "player":
		_cam.fov = player.camera.fov
		_cam.global_transform = _from
		_cam.make_current()
	if audio_muffle:
		_muffle(true)
	set_process(true)
	return true


## Put everything back now (also used when it finishes normally).
func stop(reason := "") -> void:
	if not active:
		return
	active = false
	aborted = reason
	set_process(false)
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_muffle(false)
	_overlay.color.a = 0.0
	for b in _bars:
		b.visible = false
	if is_instance_valid(player):
		player.cinematic = false
		if player.is_inside_tree() and player.camera:
			player.camera.make_current()
	for n: Variant in _was_visible:
		if is_instance_valid(n):
			(n as Object).set("visible", _was_visible[n])
	_was_visible.clear()
	_target = null
	finished.emit()


func _process(d: float) -> void:
	# real (unscaled) time: the frame's delta with the slow-motion taken back out
	var dt := clampf(d / maxf(Engine.time_scale, 0.01), 0.0, 0.1)
	# anything that means it should not be running: put it all back
	if get_tree().paused:
		stop("paused")
		return
	if not is_instance_valid(player) or not player.is_inside_tree() or player.dead:
		stop("player")
		return
	if can_run.is_valid() and not can_run.call():
		stop("game")
		return
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		if _returning < 0.0:
			_begin_return()           # the body is gone: just go back
	_t += dt
	if _t > max_seconds + _held + return_seconds + 0.5:
		stop("too long")
		return
	Engine.time_scale = _time_scale(_t)
	if audio_muffle:
		var slow := clampf((1.0 - Engine.time_scale) / maxf(1.0 - min_time_scale, 0.01), 0.0, 1.0)
		AudioServer.playback_speed_scale = lerpf(1.0, 0.78, slow)
		if _lowpass:
			_lowpass.cutoff_hz = lerpf(20000.0, 900.0, slow)
	var focus := _focus()
	_last_focus = focus
	# the letterbox slides in, and out again on the way back
	if letterbox and shot != "player":
		var h := get_viewport().get_visible_rect().size.y * 0.09
		var k := smoothstep(0.0, 0.3, _t) if _returning < 0.0 else 1.0 - smoothstep(_returning, _returning + return_seconds, _t)
		for i in 2:
			_bars[i].visible = true
			_bars[i].custom_minimum_size.y = h * k
			_bars[i].size.y = h * k
			_bars[i].position.y = 0.0 if i == 0 else get_viewport().get_visible_rect().size.y - h * k
	if _returning < 0.0:
		# stay on while the body is still going (a long fall, a Klappersoldat
		# still on its feet), up to the limit
		if _still_going():
			_moving_until = _t
		if not _focus_sent and _t >= impact_seconds + slow_seconds + recover_seconds:
			_focus_sent = true
			focus_started.emit(_target if is_instance_valid(_target) else null)
		# a moment on it once it has come to rest (a long fall lands in shot)
		var end := maxf(maxf(_end_focus, _moving_until + 0.7), _hold_until)
		if _t >= end or _t >= max_seconds + _held:
			_begin_return()
		else:
			_frame(focus, dt)
	if _returning >= 0.0:
		_return(dt)


## Stay on the body `seconds` longer from now (beyond max_seconds if need be).
func hold(seconds: float) -> void:
	if not active:
		return
	_hold_until = maxf(_hold_until, _t + seconds)
	_held = maxf(_held, _hold_until - max_seconds)


## Game speed over the sequence: eased down at the impact, held, eased back.
func _time_scale(t: float) -> float:
	if _returning >= 0.0:
		return 1.0
	var a := impact_seconds
	var b := a + slow_seconds
	var c := b + recover_seconds
	if t < a:
		return lerpf(1.0, min_time_scale, smoothstep(0.0, a, t))
	if t < b:
		return min_time_scale
	if t < c:
		return lerpf(min_time_scale, 1.0, smoothstep(b, c, t))
	return 1.0


## Where to look: the middle of the body (between chest and hips), whether
## it is still on its scripted feet or already a ragdoll. A limb that comes
## off is not followed; the torso is.
func _focus() -> Vector3:
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		return _last_focus
	var pts: Array[Vector3] = []
	for b: StringName in [&"Chest", &"Hips"]:
		var p: Variant = _bone_pos(b)
		if p != null:
			pts.append(p)
	if pts.is_empty():
		return _target.global_position + Vector3.UP * 1.0
	var sum := Vector3.ZERO
	for p in pts:
		sum += p
	return sum / pts.size()


func _bone_pos(b: StringName) -> Variant:
	var rd := _target.ragdoll
	if rd and rd.active:
		var pb: Variant = rd.bones.get(b)
		if is_instance_valid(pb):
			return (pb as Node3D).global_position
		return null
	var sk := _target.skeleton
	if sk == null:
		return null
	var i := sk.find_bone(b)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else null


## Still moving fast, falling, or (a Klappersoldat, a Rattlejack) still standing in its death.
func _still_going() -> bool:
	if not is_instance_valid(_target):
		return false
	# a body still playing out a staged death on its feet (the
	# Klappersoldat, the Rattlejack)
	var dy: Variant = _target.get("dying")
	if dy is String and dy != "":
		return true
	var rd := _target.ragdoll
	if rd and rd.active:
		var pb: Variant = rd.bones.get(&"Hips")
		if is_instance_valid(pb):
			var v: Vector3 = PhysicsServer3D.body_get_state((pb as PhysicsBody3D).get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			return v.length() > 2.2
	return false


# --- choosing the shot -------------------------------------------------------------------
func _choose() -> void:
	candidates_tried = 0
	tracking = false
	var space := get_world_3d().direct_space_state
	var T := _last_focus
	var ground := _ground_below(T)
	var ceiling := _ceiling_above(T)
	# which way it is going down: the way the shot pushed it, else away from the player
	var to_player := player.global_position - T
	to_player.y = 0.0
	var pdir := to_player.normalized() if to_player.length() > 0.1 else Vector3.FORWARD
	var fd := Vector3(_target.fatal_dir.x, 0, _target.fatal_dir.z)
	var F := fd.normalized() if fd.length() > 0.1 else -pdir
	var side := Vector3.UP.cross(F).normalized()
	var facing := Vector3(_target.global_basis.z.x, 0, _target.global_basis.z.z).normalized()
	# a long way down ahead of it, or already in the air: a fall worth following
	var ahead := _ground_below(T + F * 1.0 + Vector3.UP * 0.2)
	var falling := follow_falls and (ground < T.y - 2.2 or ahead < ground - fall_drop)
	var close := to_player.length() < 3.5
	var mech := _target.mechanical
	var eye := player.camera.global_position
	# Each kind of shot has an ideal bearing round the body; every bearing is
	# tried (in a corridor most of them are wall), the further from the ideal
	# the lower it scores, so each kind finds its best workable version.
	var kinds := {
		low_side = {ideal = [Vector3.UP.cross(F), -Vector3.UP.cross(F)], dist = 1.0, h = 0.55, pref = 0.3 + (0.3 if F.dot(pdir) < -0.3 else 0.0)},
		three_quarter = {ideal = [pdir.rotated(Vector3.UP, 0.9), pdir.rotated(Vector3.UP, -0.9)], dist = 1.0, h = height, pref = 0.25},
		elevated = {ideal = [pdir.rotated(Vector3.UP, 1.2), pdir.rotated(Vector3.UP, -1.2)], dist = 0.65, h = 3.0, pref = 1.2 if falling else 0.1},
		ground = {ideal = [F.rotated(Vector3.UP, 1.75), F.rotated(Vector3.UP, -1.75)], dist = 0.75, h = 0.2, pref = 0.5 if mech else 0.2},
		rear = {ideal = [-facing], dist = 0.95, h = height, pref = 0.2},
	}
	if falling and tracking_shots:
		kinds["tracking"] = {ideal = [side, -side], dist = 0.8, h = -1.0, pref = 2.0}
	var best := {}
	var best_score := -INF
	for name_: String in kinds:
		if not dynamic_angles and name_ != "three_quarter":
			continue
		if name_ == "tracking" and not tracking_shots:
			continue
		if name_ != "tracking" and not stationary_shots:
			continue
		var k: Dictionary = kinds[name_]
		var kind_best := {}
		var kind_score := -INF
		for a in 12:
			var bearing := Vector3.FORWARD.rotated(Vector3.UP, TAU * a / 12.0)
			var off := PI
			for ideal: Vector3 in k.ideal:
				off = minf(off, bearing.angle_to(ideal))
			if off > deg_to_rad(100.0):
				continue
			var y: float = (T.y + 0.9) if name_ == "tracking" else ground + float(k.h)
			if name_ == "elevated":
				y = minf(y, ceiling - 0.3)
				if y < ground + 2.1:
					break                                  # no room overhead for it
			for scale: float in [1.0, 0.78, 0.58]:
				candidates_tried += 1
				var pos := T + bearing * distance * float(k.dist) * scale
				pos.y = y
				var sc := _score(space, pos, T, F, ground, ceiling)
				if sc < -100.0:
					continue
				sc -= off / deg_to_rad(90.0) * 1.2 + (1.0 - scale) * 0.9
				if sc > kind_score:
					kind_score = sc
					kind_best = {name = name_, pos = pos}
				break
		if kind_best.is_empty():
			continue
		var score := kind_score + float(k.pref) + randf() * 0.5
		if avoid_repeats and history.has(name_):
			score -= 1.4 if history[0] == name_ else 0.6
		if score > best_score:
			best_score = score
			best = kind_best
	# over the shoulder: for a kill close up, or when nothing else fits
	var os := eye + player.global_basis.x * 0.42 + Vector3.UP * 0.06 + player.global_basis.z * 0.55
	if dynamic_angles and stationary_shots:
		candidates_tried += 1
		var sc := _score(space, os, T, F, ground, ceiling)
		if sc > -100.0:
			sc += (0.4 if close else -0.8) + randf() * 0.5
			if avoid_repeats and history.has("over_shoulder"):
				sc -= 1.4 if history[0] == "over_shoulder" else 0.6
			if sc > best_score:
				best_score = sc
				best = {name = "over_shoulder", pos = os}
	if best.is_empty():
		shot = "player"                                # nowhere safe to put it: stay in his eyes
		return
	shot = best.name
	tracking = shot == "tracking"
	_offset = best.pos - T
	_look = T
	_shot_xf = Transform3D(Basis.looking_at((T - best.pos).normalized(), Vector3.UP), best.pos)
	_dip = collision_checks and not _clear(space, player.camera.global_position, best.pos)


## How good a camera at `pos` is for a body at T going over toward F, or
## below -100 if it cannot be used at all.
func _score(space: PhysicsDirectSpaceState3D, pos: Vector3, T: Vector3, F: Vector3, ground: float, ceiling: float) -> float:
	if pos.y < ground + 0.12 or pos.y > ceiling - 0.12:
		return -1000.0
	if collision_checks and _inside(space, pos):
		return -1000.0
	if pos.distance_to(T) < 1.0:
		return -1000.0
	# what of the body (and where it will land) can be seen from here
	var pts: Array[Vector3] = [T, T + Vector3.UP * 0.45, Vector3(T.x, ground + 0.15, T.z),
		Vector3(T.x, ground + 0.3, T.z) + F * 0.9, Vector3(T.x, ground + 0.3, T.z) + F * 1.6]
	var seen := 0
	for i in pts.size():
		if not collision_checks or _clear(space, pos, pts[i]):
			seen += 1
		elif i == 0:
			return -1000.0                           # the body itself must be in view
	var vis := float(seen) / pts.size()
	if vis < 0.6:
		return -1000.0
	# side-on to the way it goes down shows the fall best
	var look := Vector3(T.x - pos.x, 0, T.z - pos.z).normalized()
	var across := 1.0 - absf(look.dot(F))
	# room round the camera (not jammed in a corner)
	var room := 0.0
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		if not collision_checks or _clear(space, pos, pos + d * 0.6):
			room += 0.25
	return vis * 3.0 + across * 1.0 + room * 0.6


func _ground_below(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 30.0, LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y - 1.0


func _ceiling_above(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 12.0, LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y + 12.0


func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


static var _probe: SphereShape3D

func _inside(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	if _probe == null:
		_probe = SphereShape3D.new()
		_probe.radius = 0.22
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = LAYER_WORLD
	return not space.intersect_shape(q, 1).is_empty()


# --- running the shot ---------------------------------------------------------------------
func _frame(focus: Vector3, dt: float) -> void:
	if shot == "player":
		return
	var space := get_world_3d().direct_space_state
	# the shot's own place: fixed, or riding along with a falling body
	if tracking:
		var want := focus + _offset
		if collision_checks:
			var q := PhysicsRayQueryParameters3D.create(focus, want, LAYER_WORLD)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				want = (hit.position as Vector3) - (want - focus).normalized() * 0.3
		# keeps up with a body falling fast, restrained when it is slow
		var speed := _focus_speed(focus, dt)
		_shot_xf.origin = _shot_xf.origin.lerp(want, 1.0 - exp(-(track_smoothing + speed * 1.2) * dt))
	else:
		# a body coming straight at the lens: ease back out of its way
		var away := _shot_xf.origin - focus
		if away.length() < 0.9 and (not collision_checks or not _inside(space, _shot_xf.origin + away.normalized() * 0.3)):
			_shot_xf.origin += away.normalized() * (0.9 - away.length()) * minf(dt * 4.0, 1.0)
	# turn gently to keep it in frame (a still camera lets it fall through the shot)
	_look = _look.lerp(focus, 1.0 - exp(-((track_smoothing * 2.5 + _speed * 1.5) if tracking else aim_smoothing) * dt))
	var dir := _look - _shot_xf.origin
	if dir.length() > 0.05:
		_shot_xf.basis = Basis.looking_at(dir.normalized(), Vector3.UP)
	var k := clampf(_t / fly_in_seconds, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	if _dip:
		# a wall between the player and the shot: through black, not through the wall
		_overlay.color.a = 1.0 - absf(e * 2.0 - 1.0)
		_cam.global_transform = _from if e < 0.5 else _shot_xf
	else:
		_cam.global_transform = _from.interpolate_with(_shot_xf, e)
	_cam.fov = lerpf(player.camera.fov, fov, e)


var _speed := 0.0
var _prev_focus := Vector3.INF

func _focus_speed(focus: Vector3, dt: float) -> float:
	if _prev_focus != Vector3.INF and dt > 0.0:
		_speed = lerpf(_speed, focus.distance_to(_prev_focus) / dt, 0.3)
	_prev_focus = focus
	return _speed


func _begin_return() -> void:
	_returning = _t
	Engine.time_scale = 1.0
	if shot == "player":
		return
	_from = _cam.global_transform
	var space := get_world_3d().direct_space_state
	_ret_dip = collision_checks and is_instance_valid(player) and not _clear(space, _from.origin, player.camera.global_position)


func _return(_dt: float) -> void:
	var k := clampf((_t - _returning) / maxf(return_seconds, 0.01), 0.0, 1.0)
	if shot != "player" and is_instance_valid(player):
		var e := k * k * (3.0 - 2.0 * k)
		var to := player.camera.global_transform
		if _ret_dip:
			_overlay.color.a = 1.0 - absf(e * 2.0 - 1.0)
			_cam.global_transform = _from if e < 0.5 else to
		else:
			_cam.global_transform = _from.interpolate_with(to, e)
		_cam.fov = lerpf(fov, player.camera.fov, e)
	if k >= 1.0:
		stop()


## Sound: duller and a touch lower while time is slow (a low-pass on the
## master bus), all of it back as time comes back.
func _muffle(on: bool) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if on and _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus, _lowpass)
	elif not on and _lowpass != null:
		for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus, i) == _lowpass:
				AudioServer.remove_bus_effect(bus, i)
		_lowpass = null


func _exit_tree() -> void:
	if active:
		stop("freed")
