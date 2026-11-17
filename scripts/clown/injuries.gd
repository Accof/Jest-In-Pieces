class_name Injuries
extends RefCounted
## The coroner's report on a dead enemy, for the final-kill fanfare: every
## injury it took, worked out from where each round landed on the body
## (through the eye, the jaw, the heart, a lung, the guts...), what the gore
## system did to it (skull split open, ribs blown out, guts spilled, limbs
## off, torn in half, shot clean through) and any explosions it was caught
## in (and the bones they broke). Each injury scores brutality points; the
## total buys a rank and tickets. A Klappersoldat gets an engineer's report
## instead: lenses, mainspring, bellows, gear train, drive shaft.

## Human wording, then the clockwork version. %s = "left"/"right".
const TEXT := {
	eye = ["Through the %s eye", "%s optic lens shattered"],
	between_eyes = ["Right between the eyes", "Between the lenses"],
	forehead = ["Through the forehead", "Through the porcelain brow"],
	temple = ["Through the %s temple", "Through the %s side of the skull"],
	back_head = ["Through the back of the head", "Through the back of the skull casing"],
	top_head = ["Through the crown of the skull", "Through the top of the iron skull"],
	nose = ["Nose blown off", "Porcelain nose shot off"],
	cheek = ["%s cheekbone shattered", "%s cheek plate shattered"],
	mouth = ["Through the mouth", "Through the grinning mouth"],
	jaw = ["Jaw shot away", "Jaw hinge sheared off"],
	throat = ["Throat torn open", "Neck cabling torn out"],
	neck = ["Neck snapped", "Neck spindle snapped"],
	brain = ["Brain destroyed", "Clockwork governor destroyed"],
	skull = ["Skull split open", "Iron skull cracked open"],
	head_off = ["DECAPITATED", "Head torn off its spindle"],
	heart = ["Shot through the heart", "Mainspring snapped"],
	lung = ["%s lung punctured", "%s bellows punctured"],
	lungs = ["Both lungs punctured", "Both bellows punctured"],
	collarbone = ["%s collarbone shattered", "%s shoulder strut snapped"],
	spine = ["Spine severed", "Drive shaft severed"],
	liver = ["Liver ruptured", "Oil reservoir ruptured"],
	spleen = ["Spleen burst", "Governor linkage burst"],
	gut = ["Gut-shot", "Gear housing holed"],
	pelvis = ["Pelvis shattered", "Hip joint smashed"],
	groin = ["Shot in the groin", "Shot in the crank case"],
	ribs = ["Ribcage blown open", "Chest housing blown open"],
	guts = ["Guts spilled on the floor", "Gear train spilled on the floor"],
	through = ["Shot clean through", "Holed clean through"],
	bone = ["%s shattered", "%s snapped"],
	knee = ["%s kneecap blown off", "%s knee joint sheared"],
	both_legs = ["Both legs broken", "Both leg struts snapped"],
	arm_broken = ["%s arm broken, bone through the skin", "%s arm strut snapped"],
	both_arms = ["Both arms broken", "Both arm struts snapped"],
	limb_off = ["%s torn off", "%s torn from its socket"],
	halved = ["TORN IN HALF", "SNAPPED IN TWO"],
	blast = ["Caught in an explosion (%s)", "Caught in an explosion (%s)"],
	ribs_broken = ["Ribs broken", "Chest frame buckled"],
	bones_broken = ["Collarbone and pelvis fractured", "Frame rods snapped"],
	spine_broken = ["Back broken", "Main shaft bent double"],
	eardrums = ["Eardrums burst", "Every spring sprung"],
	stake = ["Impaled on a stake", "Impaled on a stake"],
	riddled = ["Riddled: %s bullet wounds", "Riddled: %s bullet holes"],
	overkill = ["Overkill x%s", "Overkill x%s"],
	desecrated = ["Shot %s more times after it died", "Shot %s more times after it stopped"],
	oil = ["", "Oil lines ruptured"],
}

const POINTS := {
	eye = 60, between_eyes = 55, forehead = 40, temple = 40, back_head = 35, top_head = 35, nose = 35,
	cheek = 30, mouth = 45, jaw = 55, throat = 45, neck = 35, brain = 70, skull = 80, head_off = 130,
	heart = 75, lung = 40, lungs = 85, collarbone = 25, spine = 60, liver = 45, spleen = 40, gut = 35,
	pelvis = 45, groin = 30, ribs = 60, guts = 70, through = 55, bone = 30, knee = 40, limb_off = 55,
	halved = 160, blast = 40, ribs_broken = 30, bones_broken = 35, spine_broken = 45, eardrums = 15,
	stake = 85, both_legs = 70, arm_broken = 30, both_arms = 50, riddled = 0, overkill = 0, desecrated = 0, oil = 20,
}

const RANKS := [[0, "CLEAN KILL"], [90, "NASTY"], [170, "BRUTAL"], [270, "SAVAGE"], [400, "BUTCHERED"], [600, "GRAND GUIGNOL"]]
const MECH_RANKS := [[0, "DECOMMISSIONED"], [90, "DENTED"], [170, "WRECKED"], [270, "SCRAPPED"], [400, "SHREDDED"], [600, "SCRAP HEAP"]]

const BONE_NAMES := {
	UpperArm = ["%s upper arm (humerus)", "%s upper arm rod"], LowerArm = ["%s forearm", "%s forearm rod"],
	Hand = ["%s hand", "%s hand"], UpperLeg = ["%s thighbone (femur)", "%s thigh rod"],
	LowerLeg = ["%s shinbone", "%s shin rod"], Foot = ["%s foot", "%s foot"],
}
const LIMB_NAMES := {
	LeftUpperArm = "Left arm", RightUpperArm = "Right arm", LeftLowerArm = "Left forearm", RightLowerArm = "Right forearm",
	LeftHand = "Left hand", RightHand = "Right hand", LeftUpperLeg = "Left leg", RightUpperLeg = "Right leg",
	LeftLowerLeg = "Left leg below the knee", RightLowerLeg = "Right leg below the knee", LeftFoot = "Left foot", RightFoot = "Right foot",
}


## {lines: [{text, points}] (mildest first, the worst last), score, rank, tickets, name, mech}
static func assess(c: Clown) -> Dictionary:
	var mech := c.mechanical
	var found := {}          # key -> {text, points}; one line per injury
	var add := func(key: String, side := "", pts := -1) -> void:
		var id := key + side
		if found.has(id):
			return
		var t: String = TEXT[key][1 if mech else 0]
		if t == "":
			return
		if "%s" in t:
			t = t % side
		found[id] = {text = t[0].to_upper() + t.substr(1), points = POINTS[key] if pts < 0 else pts}
	var sk := c.skeleton
	var head_y := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y
	var eyes: Array = c.spec.get("eyes", [])
	var eye_y: float = (eyes[0] as Vector3).y if not eyes.is_empty() else head_y + 0.11
	var eye_x: float = absf((eyes[0] as Vector3).x) if not eyes.is_empty() else 0.043
	var top := head_y + 0.25
	var lungs := {}
	var limb_dmg := {}
	var bullets := 0
	var after := 0
	var total := 0.0
	var head_holes := 0
	for h: Dictionary in c.hit_log:
		var r: Vector3 = h.rest
		var zone: StringName = h.zone
		var raw: float = h.raw
		total += raw
		if h.after and not h.pellet:
			after += 1
		elif not h.pellet and not h.stake and not h.heavy:
			bullets += 1
		if h.stake:
			add.call("stake")
		var side := "left" if r.x > 0.0 else "right"          # the body's own left is +x
		match zone:
			&"Neck":
				if r.y < head_y - 0.01:
					add.call("throat" if r.z > 0.0 else "neck")
					continue
				head_holes += 1
				var front := r.z > 0.04
				if front:
					if absf(absf(r.x) - eye_x) < 0.035 and absf(r.y - eye_y) < 0.04:
						add.call("eye", side)
					elif r.y < eye_y - 0.045:
						add.call("mouth" if absf(r.x) < 0.035 and r.y > eye_y - 0.095 else "jaw")
						head_holes -= 1                            # below the brain
					elif r.y < eye_y - 0.02:
						add.call("nose" if absf(r.x) < 0.03 else "cheek", side)
					elif r.y > eye_y + 0.04:
						add.call("forehead")
					else:
						add.call("between_eyes" if absf(r.x) < 0.025 else "eye", side)
				elif r.y > top - 0.07:
					add.call("top_head")
				elif r.z < -0.04:
					add.call("back_head")
				else:
					add.call("temple", side)
			&"Chest":
				if r.y > 1.42:
					add.call("collarbone", side)
				elif absf(r.x) < 0.03 and r.z < -0.05:
					add.call("spine")
				elif r.x > -0.03 and r.x < 0.11 and r.y > 1.18 and r.y < 1.4:
					add.call("heart")
				else:
					lungs[side] = true
			&"Spine":
				if absf(r.x) < 0.035 and r.z < -0.04:
					add.call("spine")
				elif r.x < -0.04:
					add.call("liver")
				elif r.x > 0.04:
					add.call("spleen")
				else:
					add.call("gut")
			&"Hips":
				if raw >= 40.0:
					add.call("pelvis")
				elif r.z > 0.03 and absf(r.x) < 0.06:
					add.call("groin")
				else:
					add.call("pelvis", "", 25)
			_:
				var bn := String(h.bone)
				limb_dmg[bn] = limb_dmg.get(bn, 0.0) + raw
	if lungs.size() >= 2:
		add.call("lungs")
	else:
		for s: String in lungs:
			add.call("lung", s)
	# limbs: enough in one part breaks the bone
	for bn: String in limb_dmg:
		if float(limb_dmg[bn]) >= 55.0:
			var part := bn.trim_prefix("Left").trim_prefix("Right")
			var sd := "Left" if bn.begins_with("Left") else "Right"
			if BONE_NAMES.has(part):
				var nm: String = BONE_NAMES[part][1 if mech else 0] % sd
				var t: String = TEXT.bone[1 if mech else 0] % nm
				found["bone" + bn] = {text = t, points = POINTS.bone}
	for side: String in c.broken_legs:
		add.call("knee", side)
	if c.broken_legs.size() >= 2:
		add.call("both_legs")
	for side: String in c.broken_arms:
		add.call("arm_broken", side)
	if c.broken_arms.size() >= 2:
		add.call("both_arms")
	# what the gore system did
	var g := c.gore
	var head_seg := ClownGore.SEGMENTS.find(&"Head")
	var head_off := (g.hidden_mask >> head_seg) & 1 == 1
	if head_off:
		add.call("head_off")
	if c._head_open and not head_off:
		add.call("skull")
	if not head_off and (c._head_open or head_holes > 0) and c.last_hit_zone == &"Neck":
		add.call("brain")
	if g._innards.has(&"chest") and (not mech or g.mech_stage(&"chest") >= 2):
		add.call("ribs")
	if g._gutted or (mech and g.mech_stage(&"belly") >= 2):
		add.call("guts")
	if g._tunnels.size() > 0:
		add.call("through")
	if c._halved or c.crawling:
		add.call("halved")
	for seg: StringName in ClownGore.SEGMENTS:
		var sname := String(seg)
		if LIMB_NAMES.has(sname) and (g.hidden_mask >> ClownGore.SEGMENTS.find(seg)) & 1 == 1 and not ((c._halved or c.crawling) and sname.contains("Leg")):
			# a forearm gone with its upper arm is one injury, not two
			var up := sname.replace("Lower", "Upper").replace("Hand", "LowerArm").replace("Foot", "LowerLeg")
			if up != sname and (g.hidden_mask >> ClownGore.SEGMENTS.find(StringName(up))) & 1 == 1:
				continue
			var t: String = TEXT.limb_off[1 if mech else 0] % LIMB_NAMES[sname]
			found["off" + sname] = {text = t, points = POINTS.limb_off}
	# explosions, and the bones they broke
	var worst := 0.0
	for s: float in c.blasts:
		worst = maxf(worst, s)
	if worst > 0.0:
		var how := "point blank" if worst > 0.75 else ("close" if worst > 0.45 else "nearby")
		add.call("blast", how, int(40 + 90 * worst))
		if worst > 0.3:
			add.call("eardrums")
		if worst > 0.4 and not found.has("ribs"):
			add.call("ribs_broken")
		if worst > 0.6:
			add.call("bones_broken")
		if worst > 0.8 and not found.has("spine"):
			add.call("spine_broken")
	if mech and (bullets > 0 or worst > 0.0):
		add.call("oil")
	if bullets >= 4:
		found["riddled"] = {text = TEXT.riddled[1 if mech else 0] % bullets, points = (bullets - 2) * 6}
	var ratio := total / maxf(c.max_health, 1.0)
	if ratio >= 2.0:
		found["overkill"] = {text = TEXT.overkill[1 if mech else 0] % ("%.1f" % ratio), points = int(minf((ratio - 1.0) * 20.0, 120.0))}
	if after >= 2:
		found["desecrated"] = {text = TEXT.desecrated[1 if mech else 0] % after, points = mini(after * 4, 60)}
	# the worst last, for the build-up
	var lines: Array = found.values()
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.points) < int(b.points))
	if lines.size() > 9:
		lines = lines.slice(lines.size() - 9)
	var score := 0
	for l: Dictionary in found.values():
		score += int(l.points)
	var rank := ""
	for r: Array in (MECH_RANKS if mech else RANKS):
		if score >= int(r[0]):
			rank = r[1]
	var name := "DER KLAPPERSOLDAT" if c is Klappersoldat else ("WITZSOLDAT" if c.body == "witzsoldat" else "CLOWN")
	return {lines = lines, score = score, rank = rank, tickets = tickets_for(score), name = name, mech = mech}


## Tickets for a brutality score: one per 25 points, at least one, at most 40.
static func tickets_for(score: int) -> int:
	return clampi(int(round(score / 25.0)), 1, 40)
