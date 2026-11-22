class_name ExitDoor
extends StaticBody3D
## The way off a SURVIVAL floor (the enemy H.Q.): a door you choose to go
## through. Look at it within reach and press [E] (FpsPlayer._use, which finds
## anything with `use` and `prompt` on LAYER_WORLD). On ELIMINATION floors the
## exit still opens the upgrades by proximity, as it always has, and has no
## door of this kind.

## Called with the player when they go in (the game offers the upgrades).
var on_use: Callable
var label := "ENTER THE H.Q."
var used := false


func prompt() -> String:
	return "[E] %s" % label


func use(player: Node) -> void:
	if used or not on_use.is_valid():
		return
	used = true
	on_use.call(player)
