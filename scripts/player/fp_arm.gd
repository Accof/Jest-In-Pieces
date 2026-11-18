class_name FPArm
extends Node3D
## One first-person arm: the Tripo WW1 arm (dark green knitted wool glove,
## grey sleeve), rigged in Blender (art/arms/source/build_arms.py). A weapon
## places it by its hand and poses its fingers; nothing here knows about guns.
##
## Bones (suffix .L / .R): forearm > hand > thumb_01..03, index_01..03,
## middle_01..03, ring_01..03, little_01..03. Each bone's local +X rotation
## curls it toward the palm (Y runs along the bone, Z is the palm side).
## Poses are dictionaries of bone name (no suffix) -> Vector3 degrees (XYZ).

const PATHS := {"L": "res://art/arms/arm_L.gltf", "R": "res://art/arms/arm_R.gltf"}

## Scale on the imported arm. Tripo has no real units: at 1.0 the gloved hand is
## 25 cm wrist to fingertip; 0.78 makes it about 19.5 cm with an 8.5 cm knuckle span.
const SIZE := 0.78

## Named hand shapes any weapon can start from.
const POSES := {
	"open": {},
	"fist": {"index_01": Vector3(80, 0, 0), "index_02": Vector3(95, 0, 0), "index_03": Vector3(60, 0, 0),
		"middle_01": Vector3(80, 0, 0), "middle_02": Vector3(95, 0, 0), "middle_03": Vector3(60, 0, 0),
		"ring_01": Vector3(80, 0, 0), "ring_02": Vector3(95, 0, 0), "ring_03": Vector3(60, 0, 0),
		"little_01": Vector3(80, 0, 0), "little_02": Vector3(95, 0, 0), "little_03": Vector3(60, 0, 0),
		"thumb_01": Vector3(25, 0, 0), "thumb_02": Vector3(35, 0, 0), "thumb_03": Vector3(40, 0, 0)},
}

var side := "R"
var model: Node3D
var skeleton: Skeleton3D
var _hand := -1
var _target := {}            # bone index -> Quaternion (the pose to reach)
var _held := {}              # bone index -> Quaternion set by place() (wrist, forearm): kept by later poses
var _blend := 0.0            # 0 = snap
var available := false


static func exists(s: String) -> bool:
	return ResourceLoader.exists(PATHS[s])


func _init(s: String = "R") -> void:
	side = s
	name = "Arm" + s
	if not exists(s):
		return
	model = (load(PATHS[s]) as PackedScene).instantiate() as Node3D
	model.scale *= SIZE
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_hand = skeleton.find_bone("hand." + side)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 2                                  # like the guns: no blood decals on it
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		ap.stop()                                      # poses come from code
	available = true


## The pose to hold: bone (no suffix) -> degrees. Bones not named go back to rest.
## `seconds` > 0 eases there; 0 snaps.
func set_pose(pose: Dictionary, seconds: float = 0.0) -> void:
	if not available:
		return
	_target.clear()
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b).trim_suffix("." + side)
		if not pose.has(n) and _held.has(b):
			_target[b] = _held[b]
			continue
		var e: Vector3 = pose.get(n, Vector3.ZERO)
		var rest := skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
		_target[b] = rest * Quaternion.from_euler(e * (PI / 180.0))
	_blend = seconds
	if seconds <= 0.0:
		for b: int in _target:
			skeleton.set_bone_pose_rotation(b, _target[b])


func _process(delta: float) -> void:
	if not available or _blend <= 0.0:
		return
	var k := clampf(delta / _blend, 0.0, 1.0)
	for b: int in _target:
		skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp(_target[b], k))
	_blend = maxf(_blend - delta, 0.0)


## Where the hand bone is (its posed transform) in this node's own space.
func hand_local() -> Transform3D:
	var sk := skeleton.global_transform if skeleton.is_inside_tree() else (model.transform * skeleton.transform)
	var to_self := (model.transform * skeleton.transform) if not is_inside_tree() else (global_transform.affine_inverse() * sk)
	return to_self * skeleton.get_bone_global_pose(_hand)


## Put the arm so its hand bone sits at `hand` (in the parent's space): the
## wrist at hand.origin, the hand running along hand.basis.y, the palm toward
## hand.basis.z.
func place_hand(hand: Transform3D) -> void:
	if not available:
		return
	var h := (model.transform * skeleton.transform) * skeleton.get_bone_global_pose(_hand)
	transform = hand * Transform3D(h.basis.orthonormalized(), h.origin).affine_inverse()


## Put the hand at `hand` and the forearm running back from the wrist toward
## `elbow` (both in the parent's space). The wrist bends by whatever it takes
## to do both, so the hand stays exactly on its grip wherever the elbow is.
func place(hand: Transform3D, elbow: Vector3) -> void:
	if not available:
		return
	var s0 := model.transform * skeleton.transform
	var f := skeleton.find_bone("forearm." + side)
	var fr := skeleton.get_bone_global_rest(f)
	var hr := skeleton.get_bone_rest(_hand)
	var sc := s0.basis.get_scale().x                   # skeleton units -> this node's units
	var length := hr.origin.length() * sc             # forearm head to wrist
	# the forearm: along elbow -> wrist, rolled so its palm side matches the hand's
	var y := (hand.origin - elbow).normalized()
	var z := hand.basis.z - y * hand.basis.z.dot(y)
	z = z.normalized() if z.length() > 0.01 else (fr.basis.z - y * fr.basis.z.dot(y)).normalized()
	var fb := Basis(y.cross(z), y, z)
	var head := hand.origin - y * length
	# the forearm bone's own frame, from its rest axes (Y along the bone)
	var rest_axes := Basis(fr.basis.x.normalized(), fr.basis.y.normalized(), fr.basis.z.normalized())
	var bone_world := Transform3D(fb.scaled_local(Vector3.ONE * sc), head)   # scale cancels: the node stays unscaled
	var bone_in_arm := s0 * Transform3D(rest_axes, fr.origin)
	transform = bone_world * bone_in_arm.affine_inverse()
	skeleton.set_bone_pose_rotation(f, fr.basis.get_rotation_quaternion())
	# the wrist: what turns the hand's rest frame into the target
	var parent_to_bone := (transform * s0 * skeleton.get_bone_global_pose(f)).basis.orthonormalized()
	var want := parent_to_bone.inverse() * hand.basis.orthonormalized()
	var q := Quaternion(want.orthonormalized())
	skeleton.set_bone_pose_rotation(_hand, q)
	_held[_hand] = q
	_held[f] = fr.basis.get_rotation_quaternion()
	_target[_hand] = q
	_target[f] = _held[f]


## The hand frame that puts the index and little-finger knuckles at `index_k`
## and `little_k` with the palm toward `palm` (parent space): grips are easier
## to describe by where the knuckles go than by where the wrist is.
func frame_from_knuckles(index_k: Vector3, little_k: Vector3, palm: Vector3) -> Transform3D:
	var pi := skeleton.get_bone_rest(skeleton.find_bone("index_01." + side)).origin
	var pl := skeleton.get_bone_rest(skeleton.find_bone("little_01." + side)).origin
	var e1 := (pi - pl).normalized()
	var e3 := (Vector3.BACK - e1 * Vector3.BACK.dot(e1)).normalized()     # the hand bone's +Z is the palm side
	var local := Basis(e1, e3.cross(e1), e3)
	var f1 := (index_k - little_k).normalized()
	var f3 := (palm - f1 * palm.dot(f1)).normalized()
	var world := Basis(f1, f3.cross(f1), f3)
	var r := world * local.inverse()
	var mid_local := (pi + pl) * 0.5 * (model.transform * skeleton.transform).basis.get_scale().x
	return Transform3D(r, (index_k + little_k) * 0.5 - r * mid_local)


## A hand frame from where the wrist is, which way the hand points and which way the palm faces.
static func frame(wrist: Vector3, along: Vector3, palm: Vector3) -> Transform3D:
	var y := along.normalized()
	var z := (palm - y * palm.dot(y)).normalized()
	return Transform3D(Basis(y.cross(z), y, z), wrist)
