class_name FrontAtmosphere
extends Node3D
## The weather of the Drowned Front (Operation Drowned Front, Milestone 4),
## after the reference picture (docs/reference/no_mans_land_reference.png): a
## sickly green-grey haze that takes the far side of No Man's Land away, a
## pale dirty yellow-grey overcast with no sun in it, bright diffuse distance,
## near-black wet mud in the foreground with water standing in the low
## places, the near timber and wire sharp and the far trees only shapes, low
## smoke drifting over the shell holes.
##
## Used only on Front floors (Game._apply_floor_look when the maze is a
## FrontMaze). The bunkers, the base and the legacy trench keep their own
## environments: nothing here touches theirs.
##
## It is also the one visibility model for the eyes and the AI (D-08): the
## node joins the "fog" group, and ClownBrain._can_see_player asks
## visibility(a, b) of whatever is in it; past SIGHT_M it answers below the
## brain's 0.3 and he does not see you, however clear his line.

## Where the sickly light comes from: high and behind the cloud, over No
## Man's Land (the sky shader's glow; the sun shines along -LIGHT_DIR).
const LIGHT_DIR := Vector3(-0.3, 0.36, -0.88)   # low, behind the trees across the field, as in the reference
## How far a man can make another out through the haze (m): visibility()
## falls to the brains' threshold here. The reference reads as 30-60 m.
const SIGHT_M := 55.0
## The haze: physically coherent depth fog, not an overlay.
const FOG_COLOR := Color(0.58, 0.585, 0.545)
const FOG_BEGIN := 6.0
const FOG_END := 140.0
const FOG_DENSITY := 0.9           # what is left of the far trees: shapes

static var _grade: ImageTexture3D


static func make_environment() -> Environment:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/overcast_sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", TrenchArt.tex("noise"))
	sky_mat.set_shader_parameter("light_dir", LIGHT_DIR)
	# a flat pale overcast, faintly yellow-green, hardly any cloud structure
	sky_mat.set_shader_parameter("mass", Color(0.33, 0.34, 0.32))
	sky_mat.set_shader_parameter("body", Color(0.45, 0.46, 0.44))
	sky_mat.set_shader_parameter("opening", Color(0.66, 0.66, 0.62))
	sky_mat.set_shader_parameter("warm", Color(0.94, 0.90, 0.80))   # the glow where the sun hides, low over their side
	sky_mat.set_shader_parameter("horizon", Color(0.62, 0.62, 0.575))
	sky_mat.set_shader_parameter("ground", Color(0.26, 0.25, 0.22))
	sky_mat.set_shader_parameter("energy", 0.9)
	sky_mat.set_shader_parameter("coverage", 0.5)   # in this shader more coverage = fewer openings, and past ~0.7 the whole sky is one pale plate (M4 pass 1-3 had 0.82: bland, no cloud); 0.56 gives the legacy day's layered masses in this palette
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_sky_contribution = 0.3
	# (pass 6) a fixed ambient, not the sky's: with the sky taken down to the
	# image's weight the ambient it gave fell with it, and on the Mac the
	# ground went black (Andrew: "really so hard to see where I'm going")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.68, 0.62)
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
	env.ssao_radius = 1.4
	env.ssao_power = 1.3
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_intensity = 0.5
	env.ssil_radius = 4.0
	# the haze: from a few metres out, almost everything gone by the far end,
	# the sky taking its colour at the horizon so ground and sky merge
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.3           # the haze lit from behind, toward the hidden sun
	env.fog_density = FOG_DENSITY
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 1.0
	env.fog_aerial_perspective = 0.85    # the far posts fade into the sky behind them, not into a darker grey
	env.fog_sky_affect = 0.6
	# the ground mist's volume (FrontArt._mist) still needs the volumetric fog
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.70, 0.705, 0.65)
	env.volumetric_fog_ambient_inject = 0.9
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.7
	env.adjustment_contrast = 1.06
	env.adjustment_color_correction = make_grade()
	return env


## The grade: the darks toward wet olive-brown, the mids toward sage, the
## lights a pale dirty yellow-grey. Restrained: orange flashes and red flares
## must still read.
static func make_grade() -> ImageTexture3D:
	if _grade:
		return _grade
	var n := 24
	var images: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := Vector3(r, g, b) / float(n - 1)
				var lum := c.dot(Vector3(0.299, 0.587, 0.114))
				var shadow := 1.0 - smoothstep(0.02, 0.45, lum)
				var mid := smoothstep(0.15, 0.5, lum) * (1.0 - smoothstep(0.55, 0.9, lum))
				var high := smoothstep(0.55, 1.0, lum)
				var out := c
				out = out.lerp(Vector3.ONE * lum, 0.3 * shadow)
				out *= Vector3.ONE.lerp(Vector3(1.06, 0.98, 0.88), shadow * 0.9)
				out *= Vector3.ONE.lerp(Vector3(1.0, 0.995, 0.965), mid * 0.7)
				out *= Vector3.ONE.lerp(Vector3(1.02, 1.0, 0.93), high * 0.7)
				img.set_pixel(r, g, Color(clampf(out.x, 0.0, 1.0), clampf(out.y, 0.0, 1.0), clampf(out.z, 0.0, 1.0)))
		images.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, n, n, n, false, images)
	_grade = t
	return t


## The eye: it adjusts a little in a dugout; out in the open the exposure
## stays put, so the mud stays dark under the bright haze.
static func make_camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_scale = 0.22
	ca.auto_exposure_speed = 0.5
	ca.auto_exposure_min_sensitivity = 90.0
	ca.auto_exposure_max_sensitivity = 190.0   # (pass 6) the eye opens more for the dark ground
	return ca


## No sun: a weak, very soft directional light from high behind the cloud,
## only enough to give the ground its relief and the parapets a face.
static func setup_sun(sun: DirectionalLight3D) -> void:
	sun.light_color = Color(0.86, 0.88, 0.80)
	sun.light_energy = 0.8
	sun.light_specular = 0.0             # hidden behind cloud: no glint on the water (its reflection sat right where you look down into a trench and blinded)
	sun.light_angular_distance = 6.0
	sun.light_volumetric_fog_energy = 0.25
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.65
	sun.shadow_blur = 3.0
	# (23 Nov, Andrew's M2 baseline) the shadow reaches 40 m in two splits, not
	# 70 m in four: past 40 m the haze has taken the shadow anyway, and every
	# split re-draws the field's 4.5 M triangles
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.look_at_from_position(Vector3.ZERO, -LIGHT_DIR, Vector3.UP)
	sun.position = Vector3.ZERO


# --- the one visibility model -------------------------------------------------------------
## The share of a man's outline that reaches another's eye through the haze
## and the drifting smoke along the line from a to b (1 clear .. 0 gone).
## The haze alone: exp(-k d), with k set so SIGHT_M reads 0.3. Smoke patches
## (FrontArt's) add their own optical depth.
var smoke_patches: Array = []        # {pos: Vector3, radius: float, density: float}
## The rolling fog banks (FrontFog, made by FrontArt): their visibility is
## multiplied in, so there is still one answer.
var front_fog: TrenchFog
var _k := -log(0.3) / SIGHT_M


func _ready() -> void:
	add_to_group(&"fog")


func visibility(a: Vector3, b: Vector3) -> float:
	var d := a.distance_to(b)
	var tau := _k * d
	for s: Dictionary in smoke_patches:
		# the chord of the line through the patch's sphere
		var c: Vector3 = s.pos
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var off := (a + ab * t).distance_to(c)
		var r: float = s.radius
		if off < r:
			tau += 2.0 * sqrt(r * r - off * off) * float(s.density)
	var v := exp(-tau)
	if front_fog:
		v *= front_fog.visibility(a, b)
	return v


## How far one can make a man out in this haze (where visibility falls to 0.3).
func sight_range() -> float:
	return SIGHT_M
