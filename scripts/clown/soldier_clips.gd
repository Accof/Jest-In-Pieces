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

	func length() -> float:
		return frames / 30.0

	## The frame (fractional) and the next to blend with.
	func _at(f: float) -> Array:
		if loop:
			f = fposmod(f, float(frames))
			var i := int(f)
			return [i, (i + 1) % frames, f - i]
		f = clampf(f, 0.0, float(frames - 1))
		var i2 := mini(int(f), frames - 1)
		return [i2, mini(i2 + 1, frames - 1), f - i2]

	func rot(bone: String, f: float) -> Quaternion:
		var a: PackedFloat32Array = bones[bone]
		var at := _at(f)
		var i: int = at[0] * 4
		var j: int = at[1] * 4
		var qa := Quaternion(a[i], a[i + 1], a[i + 2], a[i + 3])
		var qb := Quaternion(a[j], a[j + 1], a[j + 2], a[j + 3])
		return qa.slerp(qb, at[2])

	func offset(f: float) -> Vector3:
		var at := _at(f)
		var i: int = at[0] * 3
		var j: int = at[1] * 3
		return Vector3(off[i], off[i + 1], off[i + 2]).lerp(Vector3(off[j], off[j + 1], off[j + 2]), at[2])

	## The frame at which a turn on the spot has turned `angle` (radians, signed).
	func frame_for_turn(angle: float) -> float:
		var a := absf(angle)
		for i in range(1, frames):
			if absf(turn[i]) >= a:
				var a0 := absf(turn[i - 1])
				return i - 1 + (a - a0) / maxf(absf(turn[i]) - a0, 0.0001)
		return frames - 1.0

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
		for b: String in c.bones:
			var r := c.rot(b, f)
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
	func apply(sk: Skeleton3D, rest_g: Dictionary) -> void:
		if total <= 0.0005:
			return
		var share := minf(total, 1.0)
		for b: String in BONES:
			if not q.has(b):
				continue
			var bi := sk.find_bone(b)
			if bi < 0:
				continue
			var d: Quaternion = Quaternion.IDENTITY.slerp((q[b] as Quaternion).normalized(), share)
			var wanted: Quaternion = d * (rest_g[b] as Quaternion)
			var parent := sk.get_bone_parent(bi)
			var pg := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
			sk.set_bone_pose_rotation(bi, (pg.inverse() * wanted).normalized())


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
