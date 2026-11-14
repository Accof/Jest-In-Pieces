extends Node
## Headless check: twists every joint both ways about every axis and prints
## the angle it stops at next to the limit that was asked for.
const Rag := preload("res://scripts/clown/clown_ragdoll.gd")

func _ready() -> void:
	_run()

func _run() -> void:
	var one := [Vector2(0, 1)]
	var hold := {support = one, legs = one, spine = one, neck = one, arms = one}
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var names := ["x", "y", "z"]
	var bad := 0
	for d: Dictionary in Rag.defs():
		if d.p == &"":
			continue
		var line := "%-14s" % d.n
		for ax in 3:
			var got := []
			for dir: float in [-1.0, 1.0]:
				var inst: Node3D = load("res://art/clown/clown.glb").instantiate()
				add_child(inst)
				var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
				var rag = Rag.new()
				inst.add_child(rag)
				rag.build(skel)
				rag.dead_joint_friction = 0.0
				rag.max_bone_spin = 100.0
				rag.muscle_strength = 1.0
				await get_tree().physics_frame
				await get_tree().physics_frame
				for pb: PhysicalBone3D in rag.bones.values():
					pb.gravity_scale = 0.0
				rag.start(hold)
				rag.weaken(d.n, 0.0)
				rag.upright_stiffness = 0.0
				rag.upright_damping = 0.0
				var child: PhysicalBone3D = rag.bones[d.n]
				var parent: PhysicalBone3D = rag.bones[d.p]
				# Twist the joint with a firm, finite torque (and the opposite on its parent).
				var torque: float = clampf(d.m * 6.0, 2.0, 60.0)
				for f in 150:
					await get_tree().physics_frame
					var t: Vector3 = parent.global_basis * axes[ax] * dir * torque
					PhysicsServer3D.body_apply_torque(child.get_rid(), t)
					PhysicsServer3D.body_apply_torque(parent.get_rid(), -t)
				var rel := (parent.global_basis.inverse() * child.global_basis).orthonormalized()
				var rv: Vector3 = Rag._rot_error(rel, Basis.IDENTITY)
				got.append(rad_to_deg(rv[ax]))
				inst.queue_free()
				await get_tree().physics_frame
			var want: Array = d[names[ax]]
			var ok: bool = abs(got[0] - want[0]) < 6.0 and abs(got[1] - want[1]) < 6.0
			if not ok:
				bad += 1
			line += "  %s[%4d,%4d] got[%4d,%4d]%s" % [names[ax], want[0], want[1], got[0], got[1], "" if ok else " <<<"]
		print(line)
	print("Readings more than 6 degrees off: ", bad, "  (hinges should be exact; ball joints give a little under sustained force)")
	get_tree().quit()
