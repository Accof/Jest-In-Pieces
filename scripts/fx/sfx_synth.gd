class_name SfxSynth
extends RefCounted
## Placeholder sounds made in code, for effects that have no recording yet
## (the Zornhauptmann's gag pops and squeaks, a dry click, a snarl, breath,
## a sabre's swish, boots). Each is a short mono 16-bit clip, built once and
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
