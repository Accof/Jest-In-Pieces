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
static func play(parent: Node, name: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	var stream := SfxSynth.stream(name)
	if stream == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 5.0
	p.max_distance = 45.0
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
		"carnival_tune":
			data = _tune(rng)
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

