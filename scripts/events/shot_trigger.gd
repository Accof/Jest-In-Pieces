class_name ShotTrigger
extends StaticBody3D
## Something small you shoot to make something happen (a chain, a rope, a
## latch). The player's bullets call shot() on any collider that has it.

signal triggered

var once := true
var _fired := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0


func shot(_at: Vector3, _dir: Vector3, _damage: float) -> void:
	if once and _fired:
		return
	_fired = true
	triggered.emit()
	if once:
		collision_layer = 0
