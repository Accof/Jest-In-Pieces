class_name ClownHands
## The enemies' fingers (added to every body by tools/add_finger_bones.py):
## under each hand, <Side>Thumb1..3 and <Side>Index/Middle/Ring/Little1..3,
## every bone resting with the hand's own axes (+Y along the hand, Z across
## the palm, X through it). The palm faces -X on a left hand and +X on a right
## one, on every body.
##
## A finger curls by turning each of its bones about Z, toward the palm; the
## thumb folds toward the palm and across it, about the axis square to its
## own length and the palm's normal.

const FINGERS := ["Index", "Middle", "Ring", "Little"]
## Degrees each finger joint bends in a full grip (knuckle, middle, tip).
const CURL := Vector3(72.0, 88.0, 58.0)
## Degrees each thumb joint bends in a full grip.
const THUMB := Vector3(22.0, 32.0, 38.0)
const THUMB_ACROSS := 18.0           ## the thumb's base swings in over the palm this far


## Does this skeleton have fingers to curl?
static func has_fingers(sk: Skeleton3D) -> bool:
	return sk != null and sk.find_bone("LeftIndex1") >= 0


## Pose one hand. `curl` 0 open (straight) .. 1 a closed grip; `thumb` the
## same for the thumb; `index` the index finger on its own (a trigger finger,
## or -1 to follow `curl`); `spread` a little fan of the fingers when open.
static func pose(sk: Skeleton3D, side: String, curl: float, thumb: float, index: float = -1.0, spread: float = 0.0) -> void:
	if not has_fingers(sk):
		return
	var to_palm := 1.0 if side == "Left" else -1.0       # turning about +Z by + takes +Y toward -X
	for f: String in FINGERS:
		var c := curl if f != "Index" or index < 0.0 else index
		# the little finger curls a touch further and the index a touch less, as hands do
		var k := {"Index": 0.92, "Middle": 1.0, "Ring": 1.04, "Little": 1.08}[f] as float
		var fan := spread * {"Index": -6.0, "Middle": -2.0, "Ring": 2.0, "Little": 6.0}[f] as float
		for j in 3:
			var bi := sk.find_bone(side + f + str(j + 1))
			if bi < 0:
				continue
			var q := Quaternion(Vector3(0, 0, 1), deg_to_rad(CURL[j] * c * k) * to_palm)
			if j == 0 and fan != 0.0:
				q = q * Quaternion(Vector3(1, 0, 0), deg_to_rad(fan))
			sk.set_bone_pose_rotation(bi, q)
	var t1 := sk.find_bone(side + "Thumb1")
	var t2 := sk.find_bone(side + "Thumb2")
	if t1 < 0 or t2 < 0:
		return
	var along := sk.get_bone_rest(t2).origin.normalized()
	var palm := Vector3(-1.0 if side == "Left" else 1.0, 0, 0)
	var axis := along.cross(palm).normalized()
	for j in 3:
		var bi := sk.find_bone(side + "Thumb" + str(j + 1))
		var q := Quaternion(axis, deg_to_rad(THUMB[j] * thumb))
		if j == 0:
			q = Quaternion(Vector3(0, 1, 0), deg_to_rad(THUMB_ACROSS * thumb) * (1.0 if side == "Left" else -1.0)) * q
		sk.set_bone_pose_rotation(bi, q)
