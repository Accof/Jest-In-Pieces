class_name BaseUsable
extends StaticBody3D
## Something in the base you look at and press [E] on. `text` (or `text_fn`,
## if set) is the prompt; `action` runs when it is used.

var text := ""
var text_fn: Callable
var action: Callable


static func make(size: Vector3, prompt_text: String, on_use: Callable) -> BaseUsable:
	var u := BaseUsable.new()
	u.collision_layer = 1
	u.collision_mask = 0
	u.text = prompt_text
	u.action = on_use
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	u.add_child(cs)
	return u


func prompt() -> String:
	return text_fn.call() if text_fn.is_valid() else text


func use(p: Node) -> void:
	if action.is_valid():
		action.call(p)
