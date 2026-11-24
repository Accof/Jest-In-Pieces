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
##   FLARE    the darker crossing: dusk light, and flares popped over the
##            field every so often - a pop, a light climbing, then drifting
##            down for ten seconds, while which everyone (the guns, the
##            brains, you) sees further through the haze. Rarer.
##
## Every configuration keeps the geometry's connectivity (the route is the
## maze's own; only the crater count changes, and craters never cut the
## route), the threats' fairness (the artillery zone and clearance, the
## guns' arcs and the standoffs are untouched) and the visibility model
## (one function, FrontAtmosphere.visibility, with the flare's glow as a
## factor). Knobs are multipliers over the base values, so the base stays
## what Andrew approved.
enum Kind { BASE, SMOKE, BARRAGE, MG, FLARE }
const NAMES := ["base", "smoke", "barrage", "mg", "flare"]
## Picking weights by seed (base most common; the flare crossing rare).
const WEIGHTS := [40.0, 20.0, 20.0, 14.0, 6.0]

static var forced := -1


static func pick(seed_value: int) -> int:
	if forced >= 0:
		return forced
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var total := 0.0
	for w: float in WEIGHTS:
		total += w
	var r := rng.randf() * total
	for i in WEIGHTS.size():
		r -= WEIGHTS[i]
		if r <= 0.0:
			return i
	return Kind.BASE


static func from_name(n: String) -> int:
	var i := NAMES.find(n.to_lower())
	return i if i >= 0 else -1


## The knobs of a configuration: multipliers and counts over the base.
static func knobs(kind: int) -> Dictionary:
	var k := {
		name = NAMES[kind],
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
		dusk = false,
		flares = false,
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
		Kind.FLARE:
			k.dusk = true
			k.flares = true
			k.fog_peak = 0.9
			k.director = {silhouette = 1.5, investigate = 1.3}
	return k
