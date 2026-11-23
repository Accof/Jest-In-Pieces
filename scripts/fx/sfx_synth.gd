class_name SfxSynth
extends RefCounted
## Placeholder sounds made in code, for effects that have no recording yet
## (the Zornhauptmann's gag pops and squeaks, a dry click, a snarl, breath,
## a sabre's swish, boots; anyone's gurgling through a cut throat). Each is a short mono 16-bit clip, built once and
## cached. Swap any of them for a real recording by dropping a .wav of the
## same name into res://art/zornhauptmann/sfx/ (see stream()).

const RATE := 22050
static var _cache := {}


## The clip called `name`: a recording from res://art/zornhauptmann/sfx/ if
## there is one, otherwise the synthesised placeholder (null if unknown).
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := "res://art/zornhauptmann/sfx/%s.wav" % name
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	else:
		s = _make(name)
	_cache[name] = s
	return s


## Play `name` once at `at` (world); the player frees itself.
## `unit` and `max_dist` set how it carries (the defaults suit gunfire and
## handling; an explosion carries much further).
static func play(parent: Node, name: String, at: Vector3, db := 0.0, pitch := 1.0, unit := 5.0, max_dist := 45.0) -> void:
	var stream := SfxSynth.stream(name)
	if stream == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = max_dist
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	var wr: WeakRef = weakref(p)
	parent.get_tree().create_timer(stream.get_length() / maxf(p.pitch_scale, 0.1) + 0.5).timeout.connect(func() -> void:
		var node: Variant = wr.get_ref()
		if node:
			(node as Node).queue_free())


## Whether `name` is a real recording rather than a placeholder.
static func recorded(name: String) -> bool:
	return ResourceLoader.exists("res://art/zornhauptmann/sfx/%s.wav" % name)


static func _make(name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var data := PackedFloat32Array()
	match name:
		"dry_click":
			data = _thump(0.05, 2400.0, 2400.0, 0.004, 0.5, rng, 0.003, 0.7)
		"pop":
			data = _thump(0.16, 170.0, 70.0, 0.05, 0.9, rng, 0.02, 0.5)
		"soft_pop":
			data = _mix(_thump(0.14, 150.0, 80.0, 0.045, 0.55, rng, 0.015, 0.25), _paper(0.5, 0.18, rng))
		"spring":
			data = _boing(0.32, rng)
		"squeak":
			data = _squeak(0.22)
		"bubble_pop":
			data = _chirp(0.03, 2200.0, 4200.0, 0.4)
		"snarl":
			data = _growl(0.55, rng)
		"breath":
			data = _breath(1.0, rng)
		"whoosh":
			data = _whoosh(0.32, rng)
		"stamp":
			data = _thump(0.14, 95.0, 50.0, 0.06, 1.0, rng, 0.025, 0.6)
		"step":
			data = _thump(0.09, 120.0, 70.0, 0.03, 0.55, rng, 0.03, 0.45)
		"gurgle":
			data = _gurgle(1.1, rng)
		# --- Carnival Curse
		"musicbox":
			data = _musicbox(1.2, [1318.5, 1244.5], 0.5)          # a music-box note, the second tine flat
		"curse_ready":
			data = _musicbox(1.4, [1046.5, 1568.0], 0.35)
		"chime":
			data = _mix(_musicbox(0.9, [880.0, 932.3, 1396.9], 0.45), _paper(0.3, 0.12, rng))
		"windup":
			data = _ratchet(0.32, 34.0, rng)
		"creak":
			data = _creak(0.45, rng)
		"crack":
			data = _crack(0.18, rng, 1.0)
		"crack_big":
			data = _crack(0.32, rng, 1.6)
		"porcelain":
			data = _mix(_crack(0.12, rng, 0.8), _chirp(0.25, 3100.0, 2600.0, 0.25))
		"strain":
			data = _strain(0.5, rng)
		"metal_snap":
			data = _mix(_crack(0.12, rng, 1.1), _chirp(0.35, 1800.0, 1650.0, 0.3))
		"choke":
			data = _gurgle(0.5, rng, 1.6)
		# --- the Drowned Trenches: the war beyond, the weather, the ground underfoot
		"wind":
			return _loop(_wind(8.0, rng))
		"rumble":
			return _loop(_rumble(10.0, rng))
		"artillery":
			data = _distant_boom(4.0, rng, 1.0)
		"artillery_near":
			data = _distant_boom(3.0, rng, 0.55)
		"mg_far":
			data = _burst(rng, rng.randi_range(6, 11), 0.085, 0.6)
		"rifle_far":
			data = _burst(rng, 1, 0.0, 0.9)
		"drip":
			data = _drip(0.25, rng)
		"timber_creak":
			data = _creak(1.1, rng)
		"shout":                                  # a man calling out, muffled through a gas mask
			data = _shout(0.62, rng)
		"scream":                                 # a man screaming somewhere out there, through a mask
			data = _scream(1.5, rng)
		"bridge_step":                            # a boot on a footbridge's planks: a knock and a give
			data = _mix(_thump(0.12, 210.0, 120.0, 0.03, 0.7, rng, 0.01, 0.35), _creak(0.25, rng))
		# --- the revolver
		"revolver_shot":
			data = _gunshot(rng)
		# --- the MP 18 (synthesized placeholders, not recordings)
		"mp18_shot":
			data = _mix(_mp18_shot(rng), _crack(0.03, rng, 0.35))
		"drum_out":
			data = _mix(_crack(0.04, rng, 0.8), _ratchet(0.18, 30.0, rng))
		"drum_in":
			data = _mix(_thump(0.1, 220.0, 140.0, 0.02, 0.8, rng, 0.015, 0.9), _crack(0.05, rng, 1.0))
		# --- the SMLE (synthesized placeholders, not recordings)
		"rifle_shot":
			data = _mix(_gunshot(rng), _crack(0.06, rng, 1.0))
		# the crossbow: the string's slap and twang, the prod's thump through the stock
		"xbow_shot":
			data = _mix(_mix(_twang(0.55, 92.0, rng), _thump(0.12, 160.0, 70.0, 0.03, 0.8, rng, 0.012, 0.9)), _crack(0.02, rng, 0.7))
		"xbow_span":
			data = _mix(_creak(0.6, rng), _ratchet(0.6, 14.0, rng))
		"xbow_latch":
			data = _mix(_crack(0.025, rng, 0.8), _thump(0.05, 900.0, 500.0, 0.006, 0.5, rng, 0.006, 0.6))
		"bolt_seat":
			data = _mix(_crack(0.02, rng, 0.4), _thump(0.04, 500.0, 300.0, 0.008, 0.35, rng, 0.01, 0.3))
		"bolt_flesh":
			data = _mix(_thump(0.1, 120.0, 60.0, 0.025, 0.9, rng, 0.03, 0.4), _squelch(0.16, rng))
		"bolt_wall":
			data = _mix(_thump(0.07, 420.0, 160.0, 0.012, 0.8, rng, 0.02, 0.8), _crack(0.03, rng, 0.6))
		"bolt_up":
			data = _mix(_crack(0.03, rng, 0.5), _thump(0.04, 600.0, 400.0, 0.005, 0.4, rng, 0.01, 0.5))
		"bolt_back":
			data = _mix(_ratchet(0.10, 45.0, rng), _thump(0.05, 300.0, 200.0, 0.01, 0.6, rng, 0.01, 0.7))
		"bolt_fwd":
			data = _mix(_ratchet(0.09, 50.0, rng), _thump(0.06, 260.0, 160.0, 0.01, 0.7, rng, 0.012, 0.8))
		"bolt_down":
			data = _mix(_crack(0.035, rng, 0.8), _thump(0.05, 420.0, 260.0, 0.008, 0.6, rng, 0.01, 0.7))
		"charger_in":
			data = _mix(_crack(0.03, rng, 0.6), _ratchet(0.05, 80.0, rng))
		"rounds_in":
			data = _ratchet(0.32, 18.0, rng)
		"round_in":
			data = _mix(_crack(0.025, rng, 0.5), _ratchet(0.06, 40.0, rng))
		"mag_out":                                # the stick magazine: catch pressed, drawn out
			data = _mix(_crack(0.03, rng, 0.7), _ratchet(0.07, 70.0, rng))
		"mag_in":                                 # pushed home and slapped
			data = _mix(_thump(0.07, 320.0, 180.0, 0.01, 0.8, rng, 0.012, 0.8), _crack(0.04, rng, 1.0))
		"mp18_charge":
			data = _mix(_ratchet(0.12, 55.0, rng), _thump(0.06, 400.0, 250.0, 0.01, 0.5, rng, 0.01, 0.6))
		# --- the trench shotgun
		"shotgun_shot":
			data = _shotgun_boom(rng)
		"pump_back":
			data = _mix(_crack(0.05, rng, 0.8), _ratchet(0.11, 45.0, rng))
		"pump_fwd":
			data = _mix(_thump(0.09, 260.0, 150.0, 0.015, 0.7, rng, 0.012, 0.9), _crack(0.05, rng, 1.0))
		"shell_in":
			data = _mix(_thump(0.07, 520.0, 320.0, 0.01, 0.35, rng, 0.008, 0.5), _crack(0.03, rng, 0.5))
		"revolver_cock":
			data = _cock(rng)
		"revolver_open":
			data = _mix(_crack(0.08, rng, 0.7), _ratchet(0.25, 20.0, rng))
		"brass":
			data = _brass_fall(rng)
		"brass_tink":
			data = _tink(rng)
		"revolver_close":
			data = _mix(_thump(0.09, 300.0, 180.0, 0.02, 0.6, rng, 0.01, 0.8), _crack(0.06, rng, 0.9))
		"metal_rattle":
			data = _rattle(1.6, rng)
		"water_slosh":
			data = _slosh(1.8, rng)
		"whistle_far":
			data = _whistle_far(rng)
		"fs_mud":
			data = _mix(_thump(0.16, 90.0, 50.0, 0.05, 0.4, rng, 0.02, 0.15), _squelch(0.24, rng))
		"fs_water":
			data = _mix(_thump(0.1, 80.0, 50.0, 0.03, 0.25, rng, 0.01, 0.1), _splash(0.3, rng))
		"fs_wood":
			data = _mix(_thump(0.1, 210.0, 120.0, 0.025, 0.7, rng, 0.012, 0.35), _crack(0.05, rng, 0.35))
		"fs_earth":
			data = _thump(0.12, 110.0, 60.0, 0.035, 0.5, rng, 0.03, 0.35)
		"splash":
			data = _splash(0.6, rng)
		# bullet impacts by surface (Impacts, M5; placeholders: no recordings yet)
		"imp_mud":
			data = _mix(_thump(0.09, 120.0, 55.0, 0.03, 0.7, rng, 0.02, 0.3), _squelch(0.12, rng))
		"imp_earth":
			data = _thump(0.07, 160.0, 70.0, 0.02, 0.6, rng, 0.03, 0.5)
		"imp_wood":
			data = _mix(_crack(0.05, rng, 0.8), _thump(0.06, 380.0, 150.0, 0.012, 0.6, rng, 0.015, 0.4))
		"imp_stone":
			data = _mix(_crack(0.04, rng, 1.0), _chirp(0.08, 2600.0, 1900.0, 0.25))
		"imp_metal":
			data = _mix(_chirp(0.22, 3100.0, 2700.0, 0.35), _crack(0.025, rng, 0.7))
		"imp_bag":
			data = _thump(0.08, 140.0, 60.0, 0.03, 0.5, rng, 0.04, 0.3)
		"mg_shot":                                # a heavy machine gun's round, close: a bark with a deep thump under it
			data = _mix(_crack(0.03, rng, 1.3), _thump(0.09, 160.0, 70.0, 0.02, 0.9, rng, 0.02, 0.6))
		"shell_whistle":                          # a shell coming in: a falling whistle, louder as it comes
			data = _whistle_in(2.4, rng)
		"imp_water":
			data = _mix(_thump(0.05, 200.0, 90.0, 0.015, 0.3, rng, 0.01, 0.1), _splash(0.22, rng))
		"carnival_tune":
			data = _tune(rng)
		# the stick grenade (placeholders: no recordings yet)
		"grenade_cap":                            # the end cap unscrewed and the cord pulled: a scrape, a tug, the igniter's pop
			data = _mix(_mix(_scrape(0.16, rng), _offset(_thump(0.05, 1400.0, 900.0, 0.006, 0.45, rng, 0.004, 0.5), 0.18)),
				_offset(_fizz(0.5, rng), 0.21))
		"grenade_throw":                          # the arm going through, the grenade spinning off
			data = _whoosh(0.4, rng)
		"grenade_bounce":                         # a can and a wooden handle hitting the ground
			data = _mix(_thump(0.12, 380.0, 240.0, 0.018, 0.55, rng, 0.01, 0.5), _thump(0.09, 1600.0, 1300.0, 0.012, 0.18, rng, 0.004, 0.2))
		"grenade_boom":                           # close: a sharp crack, a heavy thump, debris pattering down
			data = _grenade_boom(rng, 0.0)
		"grenade_boom_far":                       # a way off: the crack gone, a dull thud and a roll
			data = _grenade_boom(rng, 1.0)
		_:
			return null
	return _wav(data)


static func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## A shell's whistle: a tone sliding down from high, swelling toward the end,
## a little breath of noise in it.
static func _whistle_in(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(2600.0, 900.0, pow(t, 0.8))
		phase += TAU * f / RATE
		var env := pow(t, 1.6) * (1.0 - smoothstep(0.96, 1.0, t))
		var wob := 1.0 + 0.02 * sin(t * 60.0)
		out[i] = (sin(phase * wob) * 0.7 + sin(phase * 2.01) * 0.12 + (rng.randf() * 2.0 - 1.0) * 0.08) * env * 0.5
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


## A low thump that falls in pitch, with a click of noise on the front.
static func _thump(len: float, f0: float, f1: float, tau: float, amp: float, rng: RandomNumberGenerator, noise_len: float, noise_amp: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f1, f0, exp(-t / (len * 0.35)))
		ph += TAU * f / RATE
		var env := exp(-t / tau) * minf(t / 0.002, 1.0)
		var v := sin(ph) * env * amp
		if t < noise_len:
			v += rng.randf_range(-1.0, 1.0) * noise_amp * (1.0 - t / noise_len)
		out[i] = v
	return out


## A bowstring let go: a low note and its overtones, buzzing a little, dying away.
static func _twang(len: float, f: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t / 0.11) * minf(t / 0.001, 1.0)
		var wob := 1.0 + 0.02 * exp(-t / 0.05)
		var v := sin(TAU * f * wob * t) * 0.55 + sin(TAU * f * 2.01 * t) * 0.25 * exp(-t / 0.06) + sin(TAU * f * 3.03 * t) * 0.12 * exp(-t / 0.04)
		v += rng.randf_range(-1.0, 1.0) * 0.15 * exp(-t / 0.02)
		out[i] = clampf(v * 1.3, -1.0, 1.0) * env * 0.8
	return out


## Paper settling: crackly, thinning noise.
static func _paper(len: float, amp: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var crack := 1.0 if rng.randf() < 0.012 * exp(-t * 4.0) else 0.0
		var x := rng.randf_range(-1.0, 1.0) * (0.25 + crack * 3.0)
		lp += (x - lp) * 0.45
		out[i] = (x - lp) * amp * exp(-t * 5.0)
	return out


## A springy boing: a sine whose pitch wobbles and settles.
static func _boing(len: float, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 330.0 + 170.0 * exp(-t * 9.0) * sin(t * TAU * 11.0) + 60.0 * (1.0 - exp(-t * 6.0))
		ph += TAU * f / RATE
		out[i] = (sin(ph) * 0.8 + sin(ph * 2.0) * 0.15) * exp(-t * 8.0) * minf(t / 0.004, 1.0) * 0.6
	return out


## A rubbery squeak: up, a wobble, down.
static func _squeak(len: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var f := 950.0 + 700.0 * sin(u * PI) + 40.0 * sin(t * TAU * 28.0)
		ph += TAU * f / RATE
		var env := sin(u * PI) * 0.45
		out[i] = (sin(ph) + 0.3 * sin(ph * 2.0) + 0.12 * sin(ph * 3.0)) * env * 0.6
	return out


static func _chirp(len: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f1, t / len) / RATE
		out[i] = sin(ph) * amp * exp(-t / (len * 0.3))
	return out


## A snarl through the teeth: low, rough, pulsing.
static func _growl(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		ph += TAU * (95.0 + 20.0 * sin(u * PI)) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.12
		lp2 += (lp - lp2) * 0.3
		var pulse := 0.55 + 0.45 * sin(t * TAU * 27.0)
		var env := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.6, 1.0, u))
		out[i] = (lp2 * 3.0 + sin(ph) * 0.25) * pulse * env * 0.7
	return out


## A music-box tine (or a few): a bright decaying tone with a slightly
## detuned partial, `wobble` 0..1 bending it out of tune.
static func _musicbox(len: float, freqs: Array, wobble: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for f0: float in freqs:
		var ph := 0.0
		var ph2 := 0.0
		for i in n:
			var t := float(i) / RATE
			var f := f0 * (1.0 + wobble * 0.012 * sin(t * TAU * 5.3))
			ph += TAU * f / RATE
			ph2 += TAU * f * 2.76 / RATE
			out[i] += (sin(ph) + 0.25 * sin(ph2) * exp(-t * 9.0)) * exp(-t * 3.2) * minf(t / 0.002, 1.0) * 0.28
	return out


## A clockwork key being wound: quick clicks of a ratchet.
static func _ratchet(len: float, rate: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var next := 0.0
	for i in n:
		var t := float(i) / RATE
		if t >= next:
			next = t + 1.0 / rate * rng.randf_range(0.8, 1.2)
			var k := 0
			while k < 260 and i + k < n:
				var tt := float(k) / RATE
				out[i + k] += rng.randf_range(-1.0, 1.0) * exp(-tt * 900.0) * 0.6 + sin(tt * TAU * 2300.0) * exp(-tt * 400.0) * 0.25
				k += 1
	return out


## Old wood (or old joints) creaking under strain: a slow, grinding stick-slip.
static func _creak(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var f := 140.0 + 60.0 * sin(u * PI) + 25.0 * sin(t * 37.0)
		ph += TAU * f / RATE
		var stick := 0.5 + 0.5 * signf(sin(ph))
		lp += (rng.randf_range(-1.0, 1.0) * stick - lp) * 0.35
		out[i] = lp * sin(u * PI) * 0.55
	return out


## A man shouting, two syllables, through a mask: a buzzy voice (a sawtooth with
## jitter) shaped by two moving formants, the highs gone in the rubber.
static func _shout(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var b1 := [0.0, 0.0]
	var b2 := [0.0, 0.0]
	var lp := 0.0
	var f0 := rng.randf_range(170.0, 230.0)
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var syl := 0 if u < 0.42 else 1
		var su := u / 0.42 if syl == 0 else (u - 0.48) / 0.52
		var env := 0.0 if u > 0.42 and u < 0.48 else clampf(su * 8.0, 0.0, 1.0) * clampf((1.0 - su) * 4.0, 0.0, 1.0)
		var f := f0 * (1.0 + 0.12 * sin(su * PI) - 0.08 * syl) * (1.0 + rng.randf_range(-0.01, 0.01))
		ph = fmod(ph + f / RATE, 1.0)
		var src := ph * 2.0 - 1.0
		# two resonances (an "a" sliding to an "e"), a simple two-pole each
		var fa: float = lerpf(750.0, 500.0, float(syl))
		var fb: float = lerpf(1150.0, 1800.0, float(syl))
		var y1 := _reson(src, fa, 9.0, b1)
		var y2 := _reson(src, fb, 11.0, b2)
		var v := y1 * 0.6 + y2 * 0.4
		lp += (v - lp) * 0.3                     # the mask takes the top off
		out[i] = lp * env * 0.5
	return out


## A long, rising, breaking scream: the voice pushed high and ragged (pitch
## climbing then cracking, a fast waver), two formants, the mask dulling it.
static func _scream(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var b1 := [0.0, 0.0]
	var b2 := [0.0, 0.0]
	var lp := 0.0
	var f0 := rng.randf_range(330.0, 420.0)
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var env := clampf(u * 12.0, 0.0, 1.0) * pow(1.0 - u, 0.6)
		var crack := 1.0 + 0.35 * smoothstep(0.55, 0.62, u) - 0.25 * smoothstep(0.62, 0.9, u)
		var f := f0 * (1.0 + 0.4 * sin(u * PI * 0.8)) * crack * (1.0 + 0.04 * sin(t * 38.0)) * (1.0 + rng.randf_range(-0.02, 0.02))
		ph = fmod(ph + f / RATE, 1.0)
		var src := (ph * 2.0 - 1.0) + rng.randf_range(-0.25, 0.25)
		var y1 := _reson(src, 850.0, 7.0, b1)
		var y2 := _reson(src, 1350.0, 9.0, b2)
		lp += ((y1 * 0.6 + y2 * 0.4) - lp) * 0.35
		out[i] = lp * env * 0.55
	return out


static func _reson(x: float, f: float, q: float, st: Array) -> float:
	var w := TAU * f / RATE
	var r := 1.0 - w / (2.0 * q)
	var y := x * (1.0 - r) + 2.0 * r * cos(w) * float(st[0]) - r * r * float(st[1])
	st[1] = st[0]
	st[0] = y
	return y


## A sharp crack: a snap of noise with a hard, dry body (bone, or wood).
static func _crack(len: float, rng: RandomNumberGenerator, size: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (220.0 / size) / RATE
		var snap := rng.randf_range(-1.0, 1.0) * exp(-t * 160.0 / size)
		var crunch := rng.randf_range(-1.0, 1.0) * exp(-t * 35.0 / size) * 0.35 * (1.0 if rng.randf() < 0.3 else 0.2)
		var body := sin(ph) * exp(-t * 28.0 / size) * 0.4
		out[i] = (snap + crunch + body) * minf(size, 1.0) * 0.9
	return out


## A strained, choked noise in the throat (no words): a tight buzzing.
static func _strain(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		ph += TAU * (150.0 + 40.0 * u + 6.0 * sin(t * 40.0)) / RATE
		var buzz := clampf(sin(ph) * 3.0, -1.0, 1.0)
		lp += (buzz + rng.randf_range(-0.4, 0.4) - lp) * 0.18
		out[i] = lp * sin(u * PI) * (0.6 + 0.4 * sin(t * 23.0)) * 0.45
	return out


## Choking on blood: a wet, bubbling rasp with irregular pops.
static func _gurgle(len: float, rng: RandomNumberGenerator, rough := 1.0) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var bub := 0.0
	var bub_ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.08 * rough
		lp2 += (lp - lp2) * 0.25
		if rng.randf() < 0.0012 * rough:
			bub = 1.0
			bub_ph = 0.0
		bub *= 0.9985
		bub_ph += TAU * (180.0 + 400.0 * bub) / RATE
		var env := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.55, 1.0, u)) * (0.6 + 0.4 * sin(t * TAU * 6.5))
		out[i] = (lp2 * 2.5 + sin(bub_ph) * bub * 0.35) * env * 0.8
	return out


## A heavy breath through the nose: in, a beat, out.
static func _breath(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.2
		var env := sin(clampf(u / 0.4, 0.0, 1.0) * PI) * 0.5 + sin(clampf((u - 0.5) / 0.5, 0.0, 1.0) * PI) * 0.8
		out[i] = (x - lp) * env * 0.12
	return out


## A blade through the air: band noise that sweeps up and away.
static func _whoosh(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 0.0
	var hi := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		var x := rng.randf_range(-1.0, 1.0)
		var a := lerpf(0.05, 0.35, u)
		lo += (x - lo) * a
		hi += (lo - hi) * 0.05
		var env := pow(sin(u * PI), 2.0)
		out[i] = (lo - hi) * env * 0.9
	return out


# --- the Drowned Trenches ------------------------------------------------------------
## A clip that loops (wind, the low rumble of the guns).
static func _loop(data: PackedFloat32Array) -> AudioStreamWAV:
	# fade the ends into each other so the loop does not click
	var n := data.size()
	var x := int(RATE * 0.5)
	for i in x:
		var t := float(i) / x
		data[i] = data[i] * t + data[n - x + i] * (1.0 - t)
	data.resize(n - x)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = data.size()
	return w


## Cold wind over open ground: filtered noise in slow gusts, a faint whistle.
static func _wind(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var gust := 0.55 + 0.3 * sin(t * TAU / len * 2.0) + 0.15 * sin(t * TAU / len * 5.0 + 1.3)
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * (0.02 + 0.03 * gust)
		lp2 += (lp - lp2) * 0.12
		ph += TAU * (620.0 + 90.0 * gust) / RATE
		out[i] = lp2 * 3.2 * gust + sin(ph) * 0.006 * gust * gust
	return out


## The guns, far off: a continuous low rumble.
static func _rumble(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.004
		lp2 += (lp - lp2) * 0.02
		out[i] = lp2 * 14.0 * (0.7 + 0.3 * sin(t * 0.9))
	return out


## A grenade going off: `far` 0 close (crack, thump, debris), 1 a long way off
## (low and dull, a longer roll).
static func _grenade_boom(rng: RandomNumberGenerator, far: float) -> PackedFloat32Array:
	var len := lerpf(2.6, 3.4, far)
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var cut := lerpf(0.2, 0.03, far)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * cut
		lp2 += (lp - lp2) * cut * 0.6
		ph += TAU * lerpf(70.0, 34.0, minf(t * 4.0, 1.0)) / RATE
		var crack := x * exp(-t * 90.0) * 1.4 * (1.0 - far)
		var body := lp * exp(-t * 14.0) * 2.2 * (1.0 - 0.6 * far)
		var thump := sin(ph) * exp(-t * lerpf(7.0, 3.5, far)) * 0.9
		var roll := lp2 * 7.0 * minf(t / 0.05, 1.0) * exp(-t * lerpf(1.6, 1.0, far)) * lerpf(0.35, 0.6, far)
		out[i] = clampf((crack + body + thump + roll) * minf(t / 0.0005, 1.0), -1.0, 1.0)
	# debris and grit coming down, close only
	if far < 0.5:
		for k in 26:
			var at := int(rng.randf_range(0.25, 1.6) * RATE)
			var amp := rng.randf_range(0.05, 0.18)
			var f := rng.randf_range(900.0, 3200.0)
			for i in range(at, mini(at + int(0.03 * RATE), n)):
				var t := float(i - at) / RATE
				out[i] += (sin(TAU * f * t) * 0.5 + rng.randf_range(-0.5, 0.5)) * exp(-t * 160.0) * amp
	return out


## A dry scrape (a screw cap turning).
static func _scrape(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + x - prev)
		prev = x
		var grit := 0.5 + 0.5 * sin(TAU * 38.0 * t + sin(t * 70.0))
		out[i] = hp * 0.22 * grit * sin(PI * t / len)
	return out


## The igniter's fizz in the handle, dying away.
static func _fizz(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		hp = 0.85 * (hp + x - prev)
		prev = x
		out[i] = hp * 0.12 * exp(-t * 5.0) * minf(t / 0.01, 1.0)
	return out


## `data` starting `seconds` later.
static func _offset(data: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var pad := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(pad + data.size())
	for i in data.size():
		out[pad + i] = data[i]
	return out


## A shell landing far away: a soft thud, then a long rolling rumble.
static func _distant_boom(len: float, rng: RandomNumberGenerator, far: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var cut := lerpf(0.06, 0.012, far)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * cut
		lp2 += (lp - lp2) * cut
		ph += TAU * lerpf(48.0, 30.0, minf(t * 2.0, 1.0)) / RATE
		var env := minf(t / 0.03, 1.0) * (exp(-t * 2.2) * 0.8 + exp(-t * 0.7) * 0.25)
		out[i] = (lp2 * 9.0 + sin(ph) * 0.5 * exp(-t * 3.0)) * env * 0.8
	return out


## Gunfire a long way off: dull cracks with a tail, `count` of them `gap` apart.
static func _burst(rng: RandomNumberGenerator, count: int, gap: float, amp: float) -> PackedFloat32Array:
	var len := count * gap + 0.9
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in count:
		var start := int((k * gap + rng.randf_range(0.0, 0.012)) * RATE)
		var lp := 0.0
		for i in range(start, mini(start + int(0.8 * RATE), n)):
			var t := float(i - start) / RATE
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
			out[i] += lp * (exp(-t * 40.0) * 2.0 + exp(-t * 6.0) * 0.35) * amp
	return out


## A drop of water into a puddle.
static func _drip(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (900.0 + 1400.0 * exp(-t * 40.0)) / RATE
		out[i] = sin(ph) * exp(-t * 30.0) * 0.35 + rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.1
	return out


## A boot pulling out of mud: a wet suck.
static func _squelch(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
		ph += TAU * (180.0 + 260.0 * u) / RATE
		var env := sin(u * PI) * (0.6 + 0.4 * sin(ph))
		out[i] = lp * env * 0.5
	return out


## Water splashed: a bright burst of noise falling off.
static func _splash(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.5
		hp = x - lp
		var bubbles := 0.0
		if rng.randf() < 0.004 * exp(-t * 6.0):
			bubbles = 1.0
		out[i] = (hp * exp(-t * 9.0) * 0.5 + lp * exp(-t * 14.0) * 0.4 + bubbles * 0.4) * minf(t / 0.004, 1.0)
	return out


## A few bars of a carnival waltz on a worn music box, slowing as it runs down.
static func _tune(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var notes := [659.3, 784.0, 880.0, 784.0, 659.3, 587.3, 523.3, 587.3, 659.3, 0.0, 659.3, 698.5, 784.0, 698.5, 659.3, 523.3]
	var beat := 0.34
	var out := PackedFloat32Array()
	out.resize(int((notes.size() * beat * 1.4 + 1.5) * RATE))
	var t0 := 0.0
	for k in notes.size():
		var f: float = notes[k]
		var stretch := 1.0 + 0.4 * float(k) / notes.size()          # the spring running down
		if f > 0.0:
			var sag := 1.0 - 0.05 * float(k) / notes.size()             # and the pitch sagging with it
			var note := _musicbox(1.1, [f * sag * 0.985, f * 2.0 * sag * 0.99], 0.6)
			var start := int(t0 * RATE)
			for i in note.size():
				if start + i < out.size():
					out[start + i] += note[i] * 0.55
		t0 += beat * stretch
	return out


## Loose iron and wire in the wind: a few tinny knocks, irregular, ringing a
## moment each.
static func _rattle(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hits := rng.randi_range(4, 8)
	for k in hits:
		var start := int(rng.randf_range(0.0, len - 0.35) * RATE)
		var f := rng.randf_range(1900.0, 2600.0)
		var amp := rng.randf_range(0.12, 0.3)
		for i in range(start, mini(start + int(0.35 * RATE), n)):
			var t := float(i - start) / RATE
			var ring := sin(TAU * f * t) + 0.6 * sin(TAU * f * 1.47 * t) + 0.35 * sin(TAU * f * 2.31 * t)
			out[i] += (ring * exp(-t * 28.0) * 0.4 + rng.randf_range(-1.0, 1.0) * exp(-t * 400.0)) * amp
	return out


## Water moving in the trench: slow laps against the mud, a bubble or two.
static func _slosh(len: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var laps := rng.randf_range(1.5, 2.5)
	for i in n:
		var t := float(i) / RATE
		var u := t / len
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.06
		lp2 += (lp - lp2) * 0.2
		var env := pow(maxf(sin(u * PI * laps), 0.0), 2.0) * sin(u * PI)
		out[i] = lp2 * env * 1.4
	for k in rng.randi_range(1, 3):
		var b := _chirp(0.05, rng.randf_range(350.0, 600.0), rng.randf_range(800.0, 1200.0), 0.15)
		var start := int(rng.randf_range(0.1, len - 0.2) * RATE)
		for i in b.size():
			if start + i < n:
				out[start + i] += b[i]
	return out


## A trench whistle a long way off: two blasts, the pea trilling, dulled by
## distance and trailing off on the air.
static func _whistle_far(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len := 2.6
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := rng.randf_range(2300.0, 2800.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var on := 0.0
		if t < 0.35:
			on = 1.0
		elif t > 0.55 and t < 1.6:
			on = 1.0
		var trill := 1.0 + 0.025 * sin(TAU * 28.0 * t)
		ph += TAU * f * trill / RATE
		out[i] = sin(ph) * on * (0.6 + 0.4 * sin(TAU * 28.0 * t)) * 0.08
	# soften the edges and add a long smeared echo: it is far away
	var lp := 0.0
	for i in n:
		lp += (out[i] - lp) * 0.25
		out[i] = lp
	for i in range(n - 1, int(0.18 * RATE), -1):
		out[i] += out[i - int(0.18 * RATE)] * 0.35
	return out


## A heavy black-powder-era revolver round: a hard crack on the front, a deep
## boom under it, and a rough tail rolling off.
static func _gunshot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len := 1.1
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.35
		lp2 += (lp - lp2) * 0.04
		ph += TAU * lerpf(45.0, 110.0, exp(-t * 18.0)) / RATE
		var crack := x * exp(-t * 160.0) * 1.0
		var body := lp * exp(-t * 22.0) * 0.8
		var boom := sin(ph) * exp(-t * 9.0) * 0.75
		var tail := lp2 * exp(-t * 3.5) * 2.2
		out[i] = clampf((crack + body + boom + tail) * minf(t / 0.0007, 1.0), -1.0, 1.0)
	return out




## A 9 mm submachine-gun round: a short bark, little boom, a quick tail (it has to
## sit under the next one 0.12 s later), and the bolt slamming home under it.
static func _mp18_shot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len := 0.45
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.42
		lp2 += (lp - lp2) * 0.06
		ph += TAU * lerpf(70.0, 160.0, exp(-t * 30.0)) / RATE
		var crack := x * exp(-t * 220.0)
		var body := lp * exp(-t * 34.0) * 0.8
		var boom := sin(ph) * exp(-t * 18.0) * 0.55
		var tail := lp2 * exp(-t * 7.0) * 1.6
		var bolt := 0.0
		if t > 0.028 and t < 0.05:
			bolt = sin(TAU * 1900.0 * t) * exp(-(t - 0.028) * 260.0) * 0.35
		out[i] = clampf((crack + body + boom + tail + bolt) * minf(t / 0.0006, 1.0), -1.0, 1.0)
	return out


## A 12-bore going off: a deeper, longer boom than the revolver, more body, a long tail.
static func _shotgun_boom(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len := 1.5
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.28
		lp2 += (lp - lp2) * 0.03
		ph += TAU * lerpf(32.0, 85.0, exp(-t * 14.0)) / RATE
		var crack := x * exp(-t * 120.0) * 1.0
		var body := lp * exp(-t * 15.0) * 1.0
		var boom := sin(ph) * exp(-t * 6.5) * 0.95
		var tail := lp2 * exp(-t * 2.6) * 2.6
		out[i] = clampf((crack + body + boom + tail) * minf(t / 0.0007, 1.0), -1.0, 1.0)
	return out


## A spent case landing: a bright little ping, a second one as it bounces.
static func _tink(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.4 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := rng.randf_range(3800.0, 5200.0)
	for i in n:
		var t := float(i) / RATE
		var ring := sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.76 * t) + 0.3 * sin(TAU * f * 5.4 * t)
		out[i] = ring * exp(-t * 22.0) * 0.25 + rng.randf_range(-1.0, 1.0) * exp(-t * 600.0) * 0.3
	return out


## Six cases thrown out of the cylinder together: a short brassy jangle.
static func _brass_fall(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in 6:
		var t0 := int(rng.randf_range(0.0, 0.06) * RATE)
		var f := rng.randf_range(2600.0, 4200.0)
		for i in range(t0, n):
			var t := float(i - t0) / RATE
			out[i] += (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.3 * t)) * exp(-t * 30.0) * 0.12
	return out


## A double-action pull: the cylinder stop dropping and the cylinder turning
## (a softer ratchety tick), then the hammer coming back hard against its
## spring (a sharper, heavier click), about 70 ms apart.
static func _cock(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.22 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for spec: Array in [[0.006, 2100.0, 0.45, 260.0], [0.024, 1700.0, 0.3, 300.0], [0.078, 3100.0, 0.9, 180.0]]:
		var t0 := int((spec[0] + rng.randf_range(-0.003, 0.003)) * RATE)
		var f: float = spec[1] * rng.randf_range(0.95, 1.05)
		var amp: float = spec[2]
		var decay: float = spec[3]
		for i in range(t0, n):
			var t := float(i - t0) / RATE
			var ring := sin(TAU * f * t) + 0.55 * sin(TAU * f * 1.73 * t) + 0.3 * sin(TAU * f * 2.9 * t)
			out[i] += (ring * 0.35 + rng.randf_range(-1.0, 1.0) * exp(-t * 900.0)) * exp(-t * decay) * amp
	# a little low body: the gun's weight
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		out[i] = clampf(out[i] + lp * exp(-maxf(t - 0.078, 0.0) * 60.0) * 0.25 * float(t > 0.075), -1.0, 1.0)
	return out

