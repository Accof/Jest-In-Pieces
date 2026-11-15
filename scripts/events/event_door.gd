class_name EventDoor
extends StaticBody3D
## A steel door in a bunker wall that opens onto something: an event room
## (the machine-gun nest) or one of the odder rooms. [E] to go through.
## Inside, the matching exit door is locked until the room is done.

var kind := ""              ## what is behind it; set by the EventManager
var is_exit := false        ## the way back out, inside an event room
var locked := false
var used := false
var _lamp: OmniLight3D
var _sign: MeshInstance3D
var _sign_mat: StandardMaterial3D
var on_use: Callable        ## exit doors: what to do when used


func _ready() -> void:
	add_to_group(&"event_doors" if not is_exit else &"exit_doors")
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 2.1, 0.12)
	cs.shape = box
	cs.position = Vector3(0, 1.05, 0.06)
	add_child(cs)
	# a lit sign over the door, and a bulb
	_sign = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.16, 0.04)
	_sign.mesh = bm
	_sign_mat = StandardMaterial3D.new()
	_sign_mat.emission_enabled = true
	_sign.material_override = _sign_mat
	_sign.position = Vector3(0, 2.32, 0.08)
	add_child(_sign)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, 2.25, 0.45)
	_lamp.omni_range = 3.0
	_lamp.light_energy = 0.9
	add_child(_lamp)
	_refresh()


func set_kind(k: String) -> void:
	kind = k
	_refresh()


func _refresh() -> void:
	if _sign_mat == null:
		return
	var c := Color(0.9, 0.12, 0.08)                   # red: something big in there
	if is_exit:
		c = Color(0.85, 0.15, 0.1) if locked else Color(0.25, 0.9, 0.3)
	elif used:
		c = Color(0.08, 0.08, 0.08)
	elif kind != "" and not (kind in EventManager.FEATURES):
		c = Color(1.0, 0.6, 0.15)                     # amber: who knows
	_sign_mat.albedo_color = c
	_sign_mat.emission = c
	_sign_mat.emission_energy_multiplier = 0.4 if used else 2.5
	_lamp.light_color = c
	_lamp.visible = not used


func set_locked(v: bool) -> void:
	locked = v
	_refresh()


## What the player sees when looking at it.
func prompt() -> String:
	if is_exit:
		return "Bolted shut" if locked else "[E] Leave"
	if used:
		return "Sealed"
	return "[E] Open"


func use(player: Node) -> void:
	if is_exit:
		if not locked and on_use.is_valid():
			on_use.call()
		return
	if used or kind == "":
		return
	var mgr := get_tree().get_first_node_in_group(&"event_manager")
	if mgr:
		mgr.enter(self)
