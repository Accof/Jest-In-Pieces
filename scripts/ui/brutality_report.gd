class_name BrutalityReport
extends CanvasLayer
## The final-kill fanfare: over the killcam's last look at the body, a
## parade-drum roll and the coroner's report, one injury at a time, each
## with its brutality points; the total counts up; the rank is stamped down
## with a cymbal crash and a wheezy calliope ta-da; confetti; the tickets
## ring up. Then it fades and play goes on.
##
## show_report(report) starts it and returns how long it runs (real seconds).

signal done

const SFX := "res://art/ui/sfx/%s.wav"
@export var line_gap := 0.36          ## seconds between injuries
@export var hold := 1.7               ## on screen once it is all up

var shown := false                    ## tests
var tickets_shown := 0
var lines_shown := 0
var _t := 0.0
var _events: Array = []               # [time, Callable], in order
var _len := 0.0
var _root: Control
var _list: VBoxContainer
var _total: Label
var _score := 0
var _shown_score := 0.0
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_i := 0
var _u := 1.0


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	set_process(false)


## Begin the report. Returns its length in real seconds.
func show_report(r: Dictionary) -> float:
	clear()
	shown = true
	lines_shown = 0
	tickets_shown = 0
	_score = int(r.score)
	_shown_score = 0.0
	_t = 0.0
	_u = maxf(get_viewport().get_visible_rect().size.y / 720.0, 0.5)
	_build(r)
	var lines: Array = r.lines
	var at := 0.45
	_at(0.0, _sfx_play.bind("drumroll", -4.0))
	for i in lines.size():
		_at(at, _reveal.bind(i, lines[i]))
		at += line_gap
	at += 0.25
	_at(at, _stamp.bind(String(r.rank)))
	at += 0.75
	_at(at, _pay.bind(int(r.tickets)))
	at += hold
	_at(at, _fade)
	_len = at + 0.55
	set_process(true)
	return _len


func clear() -> void:
	if _root and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_events.clear()
	shown = false
	set_process(false)
	for p in _sfx:
		p.stop()


func _at(t: float, f: Callable) -> void:
	_events.append([t, f])


func _process(d: float) -> void:
	var dt := clampf(d / maxf(Engine.time_scale, 0.01), 0.0, 0.1)
	_t += dt
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var e: Array = _events.pop_front()
		(e[1] as Callable).call()
	# the total ticks up toward the points revealed so far
	if _total and is_instance_valid(_total):
		var target := float(_total.get_meta(&"target", 0))
		_shown_score = move_toward(_shown_score, target, maxf(target - _shown_score, 30.0) * dt * 6.0)
		_total.text = "BRUTALITY  %d" % int(round(_shown_score))
	if _t >= _len:
		clear()
		done.emit()


# --- building it --------------------------------------------------------------------------
func _label(text: String, size: float, col: Color, outline := 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * _u))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", int(outline * _u))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build(r: Dictionary) -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# a dark band across the middle, so it reads over any scene
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.0, 0.0, 0.5)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.12
	shade.anchor_bottom = 0.88
	_root.add_child(shade)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.14
	box.anchor_bottom = 0.14
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", int(4 * _u))
	_root.add_child(box)
	var title := _label("FINAL KILL", 58, Color(0.85, 0.06, 0.05), 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var who := _label(String(r.name), 20, Color(0.8, 0.75, 0.68), 6)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(who)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10 * _u
	box.add_child(gap)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(2 * _u))
	_list.custom_minimum_size.x = 560 * _u
	box.add_child(_list)
	_total = _label("BRUTALITY  0", 34, Color(1.0, 0.82, 0.3), 9)
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.set_meta(&"target", 0)
	box.add_child(_total)
	# the title slams in
	title.pivot_offset = Vector2(280, 35) * _u
	title.scale = Vector2.ONE * 2.6
	title.modulate.a = 0.0
	var tw := _tween()
	tw.tween_property(title, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(title, "modulate:a", 1.0, 0.12)
	_sfx_play("stamp", -6.0)


func _tween() -> Tween:
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	return tw


func _reveal(i: int, line: Dictionary) -> void:
	if _list == null or not is_instance_valid(_list):
		return
	lines_shown += 1
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var worst := i >= 0 and int(line.points) >= 80
	var txt := _label(String(line.text), 28 if worst else 25, Color(1, 0.35, 0.3) if worst else Color(0.95, 0.9, 0.85), 7)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var pts := _label("+%d" % int(line.points), 27, Color(1.0, 0.82, 0.3), 7)
	row.add_child(pts)
	_list.add_child(row)
	row.modulate = Color(3, 3, 3, 0)
	row.position.x = -60 * _u
	var tw := _tween()
	tw.tween_property(row, "modulate", Color(1, 1, 1, 1), 0.18)
	_total.set_meta(&"target", int(_total.get_meta(&"target", 0)) + int(line.points))
	_sfx_play("line_%d" % (i % 3), -3.0 if not worst else 1.0)
	if worst:
		_shake(6.0)


func _stamp(rank: String) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	_total.set_meta(&"target", _score)
	var st := _label(rank, 74, Color(0.9, 0.05, 0.04), 14)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.anchor_left = 0.5
	st.anchor_right = 0.5
	st.anchor_top = 0.76
	st.anchor_bottom = 0.76
	st.grow_horizontal = Control.GROW_DIRECTION_BOTH
	st.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(st)
	st.rotation = deg_to_rad(-7.0)
	st.scale = Vector2.ONE * 3.0
	st.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(st):
		return
	st.pivot_offset = st.size * 0.5
	var tw := _tween()
	tw.tween_property(st, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(st, "modulate:a", 1.0, 0.1)
	tw.tween_property(st, "scale", Vector2.ONE * 1.08, 0.06)
	tw.tween_property(st, "scale", Vector2.ONE, 0.1)
	_sfx_play("stamp", 2.0)
	_sfx_play("crash", -3.0)
	_sfx_play("fanfare", 0.0)
	_shake(14.0)
	_confetti()


func _pay(tickets: int) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	tickets_shown = tickets
	var l := _label("+%d TICKETS" % tickets, 40, Color(1.0, 0.85, 0.25), 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.86
	l.anchor_bottom = 0.86
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(l)
	l.scale = Vector2.ONE * 0.2
	await get_tree().process_frame
	if not is_instance_valid(l):
		return
	l.pivot_offset = l.size * 0.5
	var tw := _tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.15, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.tween_property(l, "modulate", Color(1.6, 1.4, 0.8), 0.15)
	tw.tween_property(l, "modulate", Color.WHITE, 0.3)
	_sfx_play("coins", 0.0)


func _fade() -> void:
	if _root and is_instance_valid(_root):
		var tw := _tween()
		tw.tween_property(_root, "modulate:a", 0.0, 0.5)


## A jolt of the whole report.
func _shake(px: float) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var tw := _tween()
	for k in 5:
		tw.tween_property(_root, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * px * _u * (1.0 - k / 5.0), 0.03)
	tw.tween_property(_root, "position", Vector2.ZERO, 0.03)


## Paper confetti thrown up from both bottom corners: red, gold, cream, black.
func _confetti() -> void:
	var vp := get_viewport().get_visible_rect().size
	for side: float in [0.0, 1.0]:
		var p := CPUParticles2D.new()
		p.position = Vector2(vp.x * side, vp.y + 10)
		p.amount = 90
		p.one_shot = true
		p.explosiveness = 0.92
		p.lifetime = 2.6
		p.direction = Vector2(1.0 if side == 0.0 else -1.0, -2.2).normalized()
		p.spread = 22.0
		p.initial_velocity_min = 700.0 * _u
		p.initial_velocity_max = 1150.0 * _u
		p.gravity = Vector2(0, 900.0 * _u)
		p.damping_min = 40.0
		p.damping_max = 120.0
		p.angular_velocity_min = -720.0
		p.angular_velocity_max = 720.0
		p.scale_amount_min = 5.0 * _u
		p.scale_amount_max = 10.0 * _u
		var g := Gradient.new()
		g.set_color(0, Color(0.85, 0.08, 0.06))
		g.set_color(1, Color(0.95, 0.8, 0.3))
		g.add_point(0.4, Color(0.95, 0.92, 0.85))
		g.add_point(0.7, Color(0.1, 0.08, 0.08))
		p.color_initial_ramp = g
		_root.add_child(p)
		p.emitting = true


func _sfx_play(sound: String, db := 0.0) -> void:
	var path := SFX % sound
	if not ResourceLoader.exists(path):
		return
	var pl := _sfx[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx.size()
	pl.stream = load(path)
	pl.volume_db = db
	pl.play()
