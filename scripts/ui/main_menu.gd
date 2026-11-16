class_name MainMenu
extends CanvasLayer
## The title screen: the two splash paintings (the Klappersoldat peering
## round a bunker corner; the clown mask in the trench mud with the burning
## fair beyond) drifting slowly and fading one into the other, under a
## vignette; the title and the menu in German blackletter (Fraktur) in
## fairground colours: cream and gold on circus red, the buttons alternating
## red and cream like the bunting.
##
## Fonts: UnifrakturMaguntia (title), UnifrakturCook (menu), Grenze Gotisch
## (small print); all SIL Open Font License (art/ui/fonts/OFL-*.txt).

const SPLASHES := ["res://art/ui/menu/menu_bunker.png", "res://art/ui/menu/menu_trench.png"]
const TITLE_FONT := "res://art/ui/fonts/UnifrakturMaguntia.ttf"
const MENU_FONT := "res://art/ui/fonts/UnifrakturCook-Bold.ttf"
const SMALL_FONT := "res://art/ui/fonts/GrenzeGotisch-Bold.ttf"

const RED := Color(0.62, 0.06, 0.06)
const DARK_RED := Color(0.32, 0.02, 0.03)
const CREAM := Color(0.95, 0.88, 0.72)
const GOLD := Color(0.88, 0.66, 0.24)
const INK := Color(0.08, 0.03, 0.03)

## Seconds each painting is shown, and how long the fade between them takes.
@export var hold_seconds := 7.0
@export var fade_seconds := 2.5
## How far each painting slowly pushes in while it is up.
@export var drift_zoom := 0.06

var current := 0                     ## which painting is up (tests)
var fades := 0                       ## how many fades so far (tests)
var buttons: Array[Button] = []

var _pics: Array[TextureRect] = []
var _t := 0.0
var _fading := false
var _menu: Control


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	for i in SPLASHES.size():
		var tr := TextureRect.new()
		tr.texture = load(SPLASHES[i])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate.a = 1.0 if i == 0 else 0.0
		root.add_child(tr)
		_pics.append(tr)
	# darken the left, where the menu sits, and the edges
	var shade := TextureRect.new()
	shade.texture = _vignette()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu)
	visible = false
	set_process(false)


## Show the title screen with these menu entries ([text, Callable] pairs) and
## a line of small print (records) under the title.
func open(entries: Array, small_print: String, help: String) -> void:
	visible = true
	set_process(true)
	for n in _menu.get_children():
		n.queue_free()
	buttons.clear()
	var u := maxf(get_viewport().get_visible_rect().size.y / 1080.0, 0.45)
	var col := VBoxContainer.new()
	col.anchor_left = 0.06
	col.anchor_right = 0.06
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", int(14 * u))
	_menu.add_child(col)
	var title := _label("Jest in Pieces", TITLE_FONT, 150 * u, CREAM, RED, 16 * u)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", int(6 * u))
	title.add_theme_constant_override("shadow_offset_y", int(8 * u))
	col.add_child(title)
	var sub := _label("Ein Karneval des Grauens  ·  1916", MENU_FONT, 40 * u, GOLD, INK, 8 * u)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 30 * u
	col.add_child(gap)
	for i in entries.size():
		var b := _button(String(entries[i][0]), i, u)
		b.pressed.connect(entries[i][1])
		col.add_child(b)
		buttons.append(b)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 24 * u
	col.add_child(gap2)
	col.add_child(_label(small_print, SMALL_FONT, 26 * u, CREAM, INK, 6 * u))
	var hint := _label(help, SMALL_FONT, 20 * u, Color(CREAM, 0.75), INK, 5 * u)
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -46 * u
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(hint)
	if not buttons.is_empty():
		buttons[0].grab_focus()


func close() -> void:
	visible = false
	set_process(false)


func _process(d: float) -> void:
	_t += d
	var n := _pics.size()
	# the one that is up pushes in slowly; the next one waits zoomed out
	for i in n:
		var p := _pics[i]
		p.pivot_offset = p.size * 0.5
		var age := _t if i == current else 0.0
		p.scale = Vector2.ONE * (1.0 + drift_zoom * clampf(age / (hold_seconds + fade_seconds), 0.0, 1.0))
	if not _fading and _t >= hold_seconds and n > 1:
		_fading = true
		var nxt := (current + 1) % n
		_pics[nxt].scale = Vector2.ONE
		var tw := create_tween()
		tw.tween_property(_pics[nxt], "modulate:a", 1.0, fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(_pics[current], "modulate:a", 0.0, fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void:
			current = nxt
			fades += 1
			_t = 0.0
			_fading = false)


func _label(text: String, font: String, size: float, col: Color, outline: Color, outline_px: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(font))
	l.add_theme_font_size_override("font_size", int(size))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", int(outline_px))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A fairground button: red with cream lettering or cream with red, turn
## about like the bunting, edged in gold; gold when you are on it.
func _button(text: String, i: int, u: float) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(560, 74) * u
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", load(MENU_FONT))
	b.add_theme_font_size_override("font_size", int(50 * u))
	var red := i % 2 == 0
	var face := RED if red else CREAM
	var ink := CREAM if red else RED
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", CREAM)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", CREAM)
	b.add_theme_color_override("font_outline_color", Color(INK, 0.6) if red else Color(CREAM, 0.0))
	b.add_theme_constant_override("outline_size", int(4 * u) if red else 0)
	b.add_theme_stylebox_override("normal", _box(Color(face, 0.88), GOLD, u, false))
	b.add_theme_stylebox_override("focus", _box(GOLD, CREAM, u, true))
	b.add_theme_stylebox_override("hover", _box(GOLD, CREAM, u, false))
	b.add_theme_stylebox_override("pressed", _box(DARK_RED, GOLD, u, false))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	return b


func _box(bg: Color, edge: Color, u: float, focus: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(int((4 if focus else 3) * u) + 1)
	s.set_corner_radius_all(int(8 * u))
	s.content_margin_left = 34 * u
	s.content_margin_right = 34 * u
	s.content_margin_top = 4 * u
	s.content_margin_bottom = 8 * u
	if not focus:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = int(8 * u)
		s.shadow_offset = Vector2(4, 6) * u
	return s


## Dark on the left (under the menu) and round the edges, clear on the right.
static func _vignette() -> ImageTexture:
	var w := 256
	var h := 144
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := float(x) / (w - 1)
			var v := float(y) / (h - 1)
			var left := clampf(1.0 - u / 0.55, 0.0, 1.0)
			left = left * left * 0.78
			var ex := (u - 0.5) * 2.0
			var ey := (v - 0.5) * 2.0
			var edge := clampf((ex * ex * 0.5 + ey * ey) - 0.45, 0.0, 1.0) * 0.6
			img.set_pixel(x, y, Color(0.02, 0.0, 0.0, clampf(left + edge, 0.0, 0.92)))
	return ImageTexture.create_from_image(img)
