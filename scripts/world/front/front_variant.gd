class_name FrontVariant
extends RefCounted
## (Milestone 11) The Front's crossing comes in a few authored configurations
## on top of the base, picked from the floor's seed (or forced: the run arg
## `variant=smoke|barrage|mg|flare|base`, or `FrontVariant.forced`):
##
##   BASE     the crossing as built through M4-M10
##   SMOKE    smoke-heavy: banks roll in twice as often and thicker, more
##            low smoke drifting, the director's smoke event twice as likely
##   BARRAGE  artillery-heavy: the first salvo sooner, the lulls half as long,
##            a shell more per salvo, a third more shell-holes to use, the
##            shellfire event twice as likely
##   MG       MG-defended: three nests instead of two, each firing across the
##            field more often, the MG-sector event more likely; the fairness
##            stays the artillery's zone and the guns' arcs (J5: three guns
##            still leave the flanks and the holes)
##   and, as a second dimension, the LIGHT: day (approved), dawn, night -
##   the night crossing has flares popped over the field every so often: a
##   pop, a light climbing, then drifting down for ten seconds, while which
##   everyone (the guns, the brains, you) sees further through the haze.
##
## Every configuration keeps the geometry's connectivity (the route is the
## maze's own; only the crater count changes, and craters never cut the
## route), the threats' fairness (the artillery zone and clearance, the
## guns' arcs and the standoffs are untouched) and the visibility model
## (one function, FrontAtmosphere.visibility, with the flare's glow as a
## factor). Knobs are multipliers over the base values, so the base stays
## what Andrew approved.
enum Kind { BASE, SMOKE, BARRAGE, MG }
const NAMES := ["base", "smoke", "barrage", "mg"]
## Picking weights by seed (base most common).
const WEIGHTS := [46.0, 20.0, 20.0, 14.0]
## (24 Nov) The time of day is its own dimension, picked separately, so any
## lean can come at any light: DAY is the approved M4 look; DAWN a low sun
## over their side, warm and not bright, its light glancing off the wet
## field; NIGHT the moonlit crossing - a cold low moon for the sheen, the
## sky near black, flares going up over the field. Andrew, on the flare
## renders: "the light shining off no man's land ... almost like a moonlit
## battlefield" - and asked for a dawn with the best of both.
enum Light { DAY, DAWN, NIGHT }
const LIGHT_NAMES := ["day", "dawn", "night"]
const LIGHT_WEIGHTS := [50.0, 30.0, 20.0]

static var forced := -1
static var forced_light := -1


static func _roll(seed_value: int, salt: int, weights: Array) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + salt
	var total := 0.0
	for w: float in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return 0


static func pick(seed_value: int) -> int:
	if forced >= 0:
		return forced
	return _roll(seed_value, 13, WEIGHTS)


static func pick_light(seed_value: int) -> int:
	if forced_light >= 0:
		return forced_light
	return _roll(seed_value, 101, LIGHT_WEIGHTS)


static func from_name(n: String) -> int:
	var i := NAMES.find(n.to_lower())
	return i if i >= 0 else -1


static func light_from_name(n: String) -> int:
	var i := LIGHT_NAMES.find(n.to_lower())
	return i if i >= 0 else -1


## The knobs of a configuration: multipliers and counts over the base.
static func knobs(kind: int, light: int = Light.DAY) -> Dictionary:
	var k := {
		name = NAMES[kind] + ("" if light == Light.DAY else " " + LIGHT_NAMES[light]),
		lean = NAMES[kind],
		light = light,
		light_name = LIGHT_NAMES[light],
		fog_every = 1.0,           # bank cadence multiplier (lower: more often)
		fog_peak = 1.0,            # bank density multiplier
		fog_prerolled = 2,         # banks already out when the floor loads
		smoke_patches = 8,         # low drifting smoke patches over the field
		art_first = 1.0,           # time to the first salvo
		art_lull = 1.0,            # between salvos
		art_salvo_extra = 0,       # shells more per salvo
		craters = 1.0,             # shell-hole count multiplier
		nests = 2,
		mg_idle = 1.0,             # the guns' idle burst cadence multiplier
		flares = light == Light.NIGHT,
		director = {},             # event weight multipliers
	}
	match kind:
		Kind.SMOKE:
			k.fog_every = 0.5
			k.fog_peak = 1.25
			k.fog_prerolled = 3
			k.smoke_patches = 13
			k.director = {smoke = 2.0}
		Kind.BARRAGE:
			k.art_first = 0.6
			k.art_lull = 0.5
			k.art_salvo_extra = 1
			k.craters = 1.3
			k.director = {shellfire = 2.0}
		Kind.MG:
			k.nests = 3
			k.mg_idle = 0.6
			k.director = {mg_sector = 1.6, parapet = 1.3}
	if light == Light.NIGHT:
		k.fog_peak *= 0.9
		k.director = k.director.duplicate()
		k.director.silhouette = float(k.director.get("silhouette", 1.0)) * 1.5
		k.director.investigate = float(k.director.get("investigate", 1.0)) * 1.3
	return k
