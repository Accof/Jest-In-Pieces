class_name CarnivalCurse
extends Node
## Carnival Curse: the player's super kill. Every enemy the player kills
## charges it (one point each, ten to fill); full, it waits. Aim at an enemy
## and press the curse key (Q): a small cursed porcelain clown head (the
## Jester's Hex) flies at him, and if it strikes a living, eligible enemy he
## is executed as a Broken Marionette (see Marionette) and the charge is
## spent. A miss, a wall, a corpse: the charge is kept. One head in the air
## at a time. The player keeps full control throughout.
##
## Kill credit: every death the game counts, except one credited to someone
## else (a Rattlejack's Death Rattle, a dying officer's last shot: `friendly`),
## the curse's own (unless curse_counts_towards_recharge), and a body counted
## already.

signal changed

@export var enabled := true                         ## SuperKillEnabled
@export var required_kills := 10                    ## SuperKillRequiredKills
@export var max_stored_charges := 1                 ## SuperKillMaxStoredCharges
@export var curse_range := 35.0                     ## SuperKillRange (m)
@export var projectile_speed := 24.0                ## SuperKillProjectileSpeed (m/s)
@export var projectile_lifetime := 2.2              ## SuperKillProjectileLifetime (s)
@export var execution_duration := 2.8               ## SuperKillExecutionDuration: to the ragdoll taking him
@export var initial_seizure_duration := 0.5         ## SuperKillInitialSeizureDuration
@export var first_arm_duration := 0.6               ## SuperKillFirstArmDuration
@export var second_arm_duration := 0.6              ## SuperKillSecondArmDuration
@export var neck_duration := 0.5                    ## SuperKillNeckDuration
@export var final_pause_duration := 0.2             ## SuperKillFinalPauseDuration
@export var allow_arm_order_variation := true       ## SuperKillAllowArmOrderVariation
@export var allow_neck_direction_variation := true  ## SuperKillAllowNeckDirectionVariation
@export var use_puppet_strings := true              ## SuperKillUsePuppetStrings
@export var pose_matched_ragdoll := true            ## SuperKillPoseMatchedRagdoll
@export var counts_towards_recharge := false        ## SuperKillCountsTowardsRecharge
@export var boss_instant_kill := false              ## SuperKillBossInstantKill
@export var key := KEY_Q                            ## the curse key (configurable)

var kills := 0                  ## towards the next charge
var charges := 0
var executions := 0             ## tests
var shots := 0                  ## heads thrown
var aim_target: Clown           ## the valid enemy under the crosshair, or null
var aim_block := ""             ## why the one under the crosshair is not valid ("" if none or valid)
var projectile: JestersHex      ## the one in the air
var last_result := ""           ## "executed", "wall", "missed", "invalid"

var player: FpsPlayer
var _counted := {}
var _hud: Control
var _label: Label
var _icon: Control
var _pulse := 0.0
var _note: String = ""
var _note_t := 0.0


func setup(p: FpsPlayer) -> void:
	player = p
	if p.hud_layer:
		_build_hud(p.hud_layer)
	_refresh()


func ready_to_use() -> bool:
	return enabled and charges > 0


## A clown died. One point if the player gets the credit for it.
func on_kill(c: Clown) -> void:
	if not enabled or c == null:
		return
	var id := c.get_instance_id()
	if _counted.has(id):
		return
	_counted[id] = true
	var death: Dictionary = c.death
	if death.get("friendly", false):
		return
	if death.get("curse", false) and not counts_towards_recharge:
		return
	if charges >= max_stored_charges:
		return
	kills += 1
	if kills >= required_kills:
		kills = 0
		charges = mini(charges + 1, max_stored_charges)
		_on_ready()
	_refresh()


func _on_ready() -> void:
	_pulse = 1.2
	if player and player.is_inside_tree():
		SfxSynth.play(player, "curse_ready", player.global_position + Vector3.UP * 1.6, -8.0, 1.0)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_pulse = maxf(_pulse - delta, 0.0)
	_note_t = maxf(_note_t - delta, 0.0)
	var before := aim_target
	var before_block := aim_block
	_aim()
	if before != aim_target or before_block != aim_block:
		player.redraw_crosshair()
	_refresh()


## Who is under the crosshair, and can he be cursed.
func _aim() -> void:
	aim_target = null
	aim_block = ""
	if not ready_to_use() or player.dead or player.cinematic or player.camera == null:
		return
	var from := player.camera.global_position
	var dir := -player.camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * curse_range, 1 | (1 << 2))
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is PhysicalBone3D) or not (hit.collider as Node).has_meta(&"clown"):
		return
	var c := (hit.collider as Node).get_meta(&"clown") as Clown
	var why := c.curse_block()
	if why == "immune" and boss_instant_kill:
		why = ""
	if why != "":
		aim_block = why
		return
	aim_target = c


## The curse key: throw the head at the enemy under the crosshair, if it can be.
func activate() -> bool:
	if not ready_to_use():
		_tell("CARNIVAL CURSE %d/%d" % [kills, required_kills])
		return false
	if player.dead or player.cinematic:
		return false
	if projectile and is_instance_valid(projectile):
		return false                               # one in the air already
	_aim()
	if aim_target == null:
		_tell("IMMUNE" if aim_block == "immune" else "NO TARGET")
		return false
	var cam := player.camera
	var from := cam.global_transform * Vector3(0.12, -0.12, -0.5)
	var target := aim_target
	var chest: PhysicalBone3D = target.ragdoll.bones.get(&"Chest")
	var aim_at: Vector3 = chest.global_position if chest else target.global_position + Vector3.UP * 1.3
	# a clear way from the hand to the target (the crosshair's ray is from the eye)
	var q := PhysicsRayQueryParameters3D.create(from, aim_at, 1)
	if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		from = cam.global_position + (-cam.global_basis.z) * 0.3
	projectile = JestersHex.launch(player.get_parent(), from, aim_at, target, self)
	shots += 1
	SfxSynth.play(player, "windup", from, -8.0, 1.0)
	SfxSynth.play(player, "dry_click", from, -10.0, 0.8)
	SfxSynth.play(player, "whoosh", from, -6.0, 0.7)
	player.redraw_crosshair()
	return true


## The head struck an enemy. Returns whether the curse took him.
func struck(c: Clown, at: Vector3, from_dir: Vector3) -> bool:
	var why := c.curse_block()
	if why == "immune" and boss_instant_kill:
		why = ""
		c.curse_immune = false
	if why == "immune":
		# known only now (it was not under the crosshair): a jolt, the charge kept
		c._flinch_from(at, from_dir, 40.0)
		last_result = "immune"
		_tell("IMMUNE")
		return false
	if why != "":
		last_result = "invalid"
		return false
	var cfg := {
		seizure = initial_seizure_duration, arm_time = first_arm_duration, arm2_time = second_arm_duration,
		neck_time = neck_duration, pause = final_pause_duration,
		collapse = maxf(execution_duration - (initial_seizure_duration + first_arm_duration + second_arm_duration + neck_duration + final_pause_duration), 0.2),
		vary_arm_order = allow_arm_order_variation, vary_neck_dir = allow_neck_direction_variation,
		use_strings = use_puppet_strings, pose_matched = pose_matched_ragdoll,
	}
	if not c.begin_curse(cfg, at, from_dir):
		last_result = "invalid"
		return false
	charges = maxi(charges - 1, 0)
	kills = 0
	executions += 1
	last_result = "executed"
	_refresh()
	return true


## The head hit a wall, missed, or ran out of time: nothing spent.
func missed(why: String) -> void:
	last_result = why
	_refresh()


func _tell(text: String) -> void:
	_note = text
	_note_t = 1.0


# --- HUD -----------------------------------------------------------------------------
func _build_hud(layer: CanvasLayer) -> void:
	_hud = Control.new()
	_hud.name = "CarnivalCurse"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud.position = Vector2(-150, -86)
	_hud.size = Vector2(300, 40)
	layer.add_child(_hud)
	_icon = Control.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.position = Vector2(0, 2)
	_icon.size = Vector2(34, 34)
	_icon.draw.connect(_draw_icon)
	_hud.add_child(_icon)
	_label = Label.new()
	_label.position = Vector2(42, 6)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_label)


func _refresh() -> void:
	if _label == null:
		return
	_hud.visible = enabled
	var ready := charges > 0
	var text := ("CARNIVAL CURSE READY  [%s]" % OS.get_keycode_string(key)) if ready else "CARNIVAL CURSE  %d/%d" % [kills, required_kills]
	if _note_t > 0.0:
		text += "   " + _note
	if _label.text != text:
		_label.text = text
	var glow := 0.5 + 0.5 * sin(_pulse * 14.0) if _pulse > 0.0 else 0.0
	_label.modulate = Color(1.0, 0.82, 0.95).lerp(Color(1, 1, 1), glow) if ready else Color(0.78, 0.74, 0.74, 0.85)
	var sc := 1.0 + 0.12 * glow
	_hud.scale = Vector2(sc, sc)
	_hud.pivot_offset = Vector2(150, 20)
	_icon.queue_redraw()


## A little porcelain clown face; lit up (and the eyes glowing) when charged,
## a dark ring filling up round it as the kills come in.
func _draw_icon() -> void:
	var c := Vector2(17, 17)
	var ready := charges > 0
	var frac := 1.0 if ready else float(kills) / float(maxi(required_kills, 1))
	_icon.draw_arc(c, 16.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, Color(0.75, 0.3, 0.95, 0.9 if ready else 0.6), 3.0)
	_icon.draw_circle(c, 11.0, Color(0.9, 0.88, 0.84) if ready else Color(0.55, 0.53, 0.5))
	var eye := Color(0.7, 0.1, 0.9) if ready else Color(0.08, 0.07, 0.07)
	_icon.draw_circle(c + Vector2(-4, -2), 2.4, eye)
	_icon.draw_circle(c + Vector2(4, -2), 2.4, eye)
	_icon.draw_circle(c + Vector2(0, 2), 2.0, Color(0.75, 0.08, 0.08))
	_icon.draw_arc(c + Vector2(0, 3), 6.0, 0.35, PI - 0.35, 12, Color(0.1, 0.05, 0.05), 1.5)
	_icon.draw_line(c + Vector2(-7, -9), c + Vector2(-3, -4), Color(0.2, 0.18, 0.16, 0.8), 1.0)     # the crack
