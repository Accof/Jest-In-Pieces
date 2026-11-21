class_name SoldierClips
extends RefCounted
## Motion-captured movement for the human soldiers, retargeted from the Mixamo
## reference clips in art/anim_ref (tools/anim_ref/retarget.py writes
## soldier_clips.json from them).
##
## Each clip holds, per frame, every leg/spine/neck/shoulder bone's rotation
## away from its rest pose in skeleton space (so it suits any of the soldier
## models), and the hips' offset from where they stand at rest. The arms are
## not in it: they stay on the rifle by IK.
##
## A soldier mixes them with `Mix`: add clips with weights, then apply. The
## procedural animation in clown.gd runs on top for whatever share the clips
## do not take.

const PATH := "res://art/anim_ref/soldier_clips.json"
## The bones, parents before children.
const BONES := ["Hips", "Spine", "Chest", "Neck", "Head", "LeftShoulder", "RightShoulder",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
		"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

## What a man without a rifle takes from the clips.
const LOWER := ["Hips", "Spine", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
		"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

static var _clips := {}


class Clip:
	var name := ""
	var frames := 0
	var loop := false
	var additive := false
	var stride := 0.0                   ## metres travelled per cycle (moving loops)
	var turn := PackedFloat32Array()    ## radians turned by each frame (turns on the spot)
	var bones := {}                     ## bone -> PackedFloat32Array of x,y,z,w per frame
	var off := PackedFloat32Array()     ## hips offset per frame
	var dist := PackedFloat32Array()    ## starts and stops: ground covered by each frame (m)
	var phase := PackedFloat32Array()   ## and the walking cycle's phase each frame matches

	func length() -> float:
		return frames / 30.0

	## The frame (whole), the next one and how far between, for frame `f`.
	var _i := 0
	var _j := 0
	var _u := 0.0

	func _at(f: float) -> void:
		if loop:
			f = fposmod(f, float(frames))
			_i = int(f)
			_j = _i + 1
			if _j >= frames:
				_j = 0
			_u = f - _i
			return
		f = clampf(f, 0.0, float(frames - 1))
		_i = mini(int(f), frames - 1)
		_j = mini(_i + 1, frames - 1)
		_u = f - _i

	func rot(bone: String, f: float) -> Quaternion:
		_at(f)
		return _rot_at(bones[bone])

	func _rot_at(a: PackedFloat32Array) -> Quaternion:
		var i := _i * 4
		var j := _j * 4
		var qa := Quaternion(a[i], a[i + 1], a[i + 2], a[i + 3])
		if _u < 0.001:
			return qa
		return qa.slerp(Quaternion(a[j], a[j + 1], a[j + 2], a[j + 3]), _u)

	func offset(f: float) -> Vector3:
		_at(f)
		var i := _i * 3
		var j := _j * 3
		return Vector3(off[i], off[i + 1], off[i + 2]).lerp(Vector3(off[j], off[j + 1], off[j + 2]), _u)


	## The frame at which a turn on the spot has turned `angle` (radians, signed).
	func frame_for_turn(angle: float) -> float:
		var a := absf(angle)
		for i in range(1, frames):
			if absf(turn[i]) >= a:
				var a0 := absf(turn[i - 1])
				return i - 1 + (a - a0) / maxf(absf(turn[i]) - a0, 0.0001)
		return frames - 1.0

	## Ground speed of the clip's root at frame f (m/s at 30 fps).
	func speed_at(f: float) -> float:
		var i := clampi(int(f), 0, frames - 2)
		return (dist[i + 1] - dist[i]) * 30.0

	func phase_at(f: float) -> float:
		return phase[clampi(int(round(f)), 0, frames - 1)]

	## A stop met at `speed` with the cycle at `cyc_phase`: the frame to come in
	## at (after the clip's fastest point, no faster than he is going, the legs
	## as near as can be where his are).
	func stop_entry(speed: float, cyc_phase: float, rate: float) -> int:
		var peak := 0
		for i in frames - 1:
			if speed_at(i) > speed_at(peak):
				peak = i
		var best := -1
		var best_cost := INF
		for i in range(peak, frames - 4):
			var v := speed_at(i) * rate
			if v > speed * 1.15:
				continue
			var dp := absf(wrapf(phase[i] - cyc_phase, -0.5, 0.5))
			var cost := absf(v - speed) / maxf(speed, 0.3) + dp * 1.5
			if cost < best_cost:
				best_cost = cost
				best = i
		return best

	func total_turn() -> float:
		return turn[frames - 1] if turn.size() > 0 else 0.0


static func clip(name: String) -> Clip:
	if _clips.is_empty():
		_load()
	return _clips.get(name)


static func available() -> bool:
	if _clips.is_empty():
		_load()
	return not _clips.is_empty()


static func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_warning("soldier clips missing: " + PATH)
		_clips["_none"] = null
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for name: String in data:
		var d: Dictionary = data[name]
		var c := Clip.new()
		c.name = name
		c.frames = int(d.frames)
		c.loop = d.loop
		c.additive = d.additive
		c.stride = float(d.get("stride", 0.0))
		if d.has("turn"):
			c.turn = PackedFloat32Array(d.turn)
		if d.has("dist"):
			c.dist = PackedFloat32Array(d.dist)
			c.phase = PackedFloat32Array(d.phase)
		c.off = PackedFloat32Array(d.off)
		for b: String in d.bones:
			c.bones[b] = PackedFloat32Array(d.bones[b])
		_clips[name] = c
	_clips.erase("_none")


## A blend of clips for one frame.
class Mix:
	var q := {}            ## bone -> blended rotation from rest
	var w := {}            ## bone -> weight so far
	var total := 0.0       ## the clips' share of the pose (0..1 once applied)
	var off := Vector3.ZERO

	func reset() -> void:
		q.clear()
		w.clear()
		total = 0.0
		off = Vector3.ZERO

	## Add a full-pose clip at frame `f` with weight `weight`.
	func add(c: Clip, f: float, weight: float, mirror_yaw := 0.0) -> void:
		if c == null or weight <= 0.0005:
			return
		c._at(f)
		for b: String in c.bones:
			var r := c._rot_at(c.bones[b])
			if not q.has(b):
				q[b] = r
				w[b] = weight
			else:
				var ws: float = w[b] + weight
				q[b] = (q[b] as Quaternion).slerp(r, weight / ws)
				w[b] = ws
		off += c.offset(f) * weight
		total += weight

	## Pose the skeleton: each bone's skeleton-space rotation becomes the blend
	## (taken `total` of the way from rest) times its rest rotation. `rest_g`
	## holds the bones' skeleton-space rest rotations.
	## `idx` maps each bone to [its index, its parent's index] (see indices()).
	## Each bone's skeleton-space rotation is worked out here down the chain,
	## rather than asked of the skeleton bone by bone (that recomputes it).
	func apply(sk: Skeleton3D, rest_g: Dictionary, idx: Dictionary, only: Array = BONES) -> void:
		if total <= 0.0005:
			return
		var share := minf(total, 1.0)
		var g := {}                              # bone index -> skeleton-space rotation now
		for b: String in BONES:
			if not idx.has(b):
				continue
			var bi: int = idx[b][0]
			var parent: int = idx[b][1]
			var pg: Quaternion
			if g.has(parent):
				pg = g[parent]
			elif parent >= 0:
				pg = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
			else:
				pg = Quaternion.IDENTITY
			if not q.has(b) or not only.has(b):
				g[bi] = pg * sk.get_bone_pose_rotation(bi)
				continue
			var d: Quaternion = Quaternion.IDENTITY.slerp((q[b] as Quaternion).normalized(), share)
			var wanted: Quaternion = d * (rest_g[b] as Quaternion)
			sk.set_bone_pose_rotation(bi, (pg.inverse() * wanted).normalized())
			g[bi] = wanted


## [index, parent index] of each clip bone in a skeleton.
static func indices(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for b: String in BONES:
		var bi := sk.find_bone(b)
		if bi >= 0:
			out[b] = [bi, sk.get_bone_parent(bi)]
	return out


## Layer an additive clip (rotations relative to its own first frame) over
## whatever pose the skeleton is in: each bone turned about skeleton space.
static func add_on(sk: Skeleton3D, c: Clip, f: float, weight: float) -> void:
	if c == null or weight <= 0.0005:
		return
	for b: String in BONES:
		if not c.bones.has(b):
			continue
		var bi := sk.find_bone(b)
		if bi < 0:
			continue
		var r: Quaternion = Quaternion.IDENTITY.slerp(c.rot(b, f), weight)
		var parent := sk.get_bone_parent(bi)
		var pg := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		var cur := sk.get_bone_global_pose(bi).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(bi, (pg.inverse() * (r * cur)).normalized())
