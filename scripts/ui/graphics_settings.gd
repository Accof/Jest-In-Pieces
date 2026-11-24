class_name GraphicsSettings
extends RefCounted
## (Drowned Front M12) The player's graphics choices, kept in
## user://graphics.cfg and applied to the viewport and the floor's
## Environment whenever a floor is built or a setting changes. Until now
## the 75 % FSR 1 render scale was the project's default for everyone
## (D-10); it is still the default, but it is the player's to change.
##
##   scale      3D render scale: 0.5, 0.67, 0.75, 0.85, 1.0
##   upscaler   how a scale below 1 is brought back up: FSR 1 (near free on
##              Apple GPUs), FSR 2 (sharper, ~4 ms on the M2), bilinear
##   shadows    0 off, 1 low (2048 atlas), 2 high (4096, the default)
##   ao         screen-space ambient occlusion and indirect light (SSAO/SSIL)
##   fullscreen window or fullscreen
##
## Everything else the floors set (fog, glow, the sun's shadow distance)
## stays theirs: these are the knobs that bought the frame rate on the M2,
## each one measured (the tracker's performance note).

const PATH := "user://graphics.cfg"
const SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
const UPSCALERS := ["FSR 1", "FSR 2", "Bilinear"]
const SHADOWS := ["Off", "Low", "High"]

static var scale := 0.75
static var upscaler := 0
static var shadows := 2
static var ao := true
static var fullscreen := false
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	scale = float(cf.get_value("graphics", "scale", scale))
	upscaler = int(cf.get_value("graphics", "upscaler", upscaler))
	shadows = int(cf.get_value("graphics", "shadows", shadows))
	ao = bool(cf.get_value("graphics", "ao", ao))
	fullscreen = bool(cf.get_value("graphics", "fullscreen", fullscreen))


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "scale", scale)
	cf.set_value("graphics", "upscaler", upscaler)
	cf.set_value("graphics", "shadows", shadows)
	cf.set_value("graphics", "ao", ao)
	cf.set_value("graphics", "fullscreen", fullscreen)
	cf.save(PATH)


## Apply to a viewport (the scale and the upscaler) and, when given, to a
## floor's Environment (the ambient occlusion) and its lights (the shadows).
static func apply(vp: Viewport, env: Environment = null, world: Node = null) -> void:
	load_settings()
	vp.scaling_3d_scale = scale
	if scale >= 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		match upscaler:
			0: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			1: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			_: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.positional_shadow_atlas_size = [0, 2048, 4096][shadows]
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096][shadows], true)
	if env:
		env.ssao_enabled = ao
		env.ssil_enabled = ao
	if world:
		_shadows(world, shadows > 0)
	var mode := DisplayServer.window_get_mode()
	if fullscreen and mode != DisplayServer.WINDOW_MODE_FULLSCREEN and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and (mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Shadows off remembers which lights had them (the floors keep lamps and
## litter shadowless on purpose; those are not switched on by "High").
static func _shadows(n: Node, on: bool) -> void:
	if n is Light3D:
		var l := n as Light3D
		if on:
			if l.has_meta(&"shadow_was"):
				l.shadow_enabled = true
				l.remove_meta(&"shadow_was")
		elif l.shadow_enabled:
			l.set_meta(&"shadow_was", true)
			l.shadow_enabled = false
	for c in n.get_children():
		_shadows(c, on)


## The menu lines, as the title menu shows them.
static func describe() -> Array:
	load_settings()
	return [
		"Render scale: %d%%%s" % [int(round(scale * 100.0)), "" if scale >= 0.999 else "  (" + UPSCALERS[upscaler] + ")"],
		"Upscaler: %s" % UPSCALERS[upscaler],
		"Shadows: %s" % SHADOWS[shadows],
		"Ambient occlusion: %s" % ("On" if ao else "Off"),
		"Fullscreen: %s" % ("On" if fullscreen else "Off"),
	]


## Cycle one setting (by the index in describe()).
static func cycle(i: int) -> void:
	load_settings()
	match i:
		0:
			var k := SCALES.find(scale)
			scale = SCALES[(k + 1) % SCALES.size()] if k >= 0 else 0.75
		1:
			upscaler = (upscaler + 1) % UPSCALERS.size()
		2:
			shadows = (shadows + 1) % SHADOWS.size()
		3:
			ao = not ao
		4:
			fullscreen = not fullscreen
	save_settings()
