class_name SfxSynth
extends RefCounted
## Procedural sample builders for the Sfx autoload. Pure functions: no nodes,
## no audio server. Every sound is generated in code (no audio files) as mono
## 16-bit PCM inside an AudioStreamWAV. Ambient loops are built so that every
## oscillator completes a whole number of cycles over the loop, which makes the
## loop point seamless.

const MIX_RATE := 22050
const AMBIENT_RATE := 11025
const AMBIENT_SECONDS := 8.0

## Every one-shot name Sfx.play() accepts. zombie_groan has 3 variants.
const SOUND_NAMES := [
	"pistol_shot", "shotgun_shot", "rifle_shot", "smg_shot",
	"dry_click", "reload", "punch_hit", "shove", "melee_swing", "blade_hit",
	"zombie_groan", "zombie_bite", "zombie_death",
	"player_hurt", "player_death", "pickup", "door", "ui_click",
	"level_up", "heartbeat",
]
const GROAN_VARIANTS := 3
const AMBIENT_KINDS := ["street", "interior", "night"]


## Renders one-shot `name` (variant only matters for zombie_groan). Returns an
## empty array for unknown names.
static func render(name: String, variant: int = 0) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s_%d" % [name, variant])
	match name:
		"pistol_shot":
			return _shot(rng, 0.25, 0.35, 0.5, 120.0, 50.0, 0.7, 22.0)
		"shotgun_shot":
			return _shot(rng, 0.5, 0.15, 0.6, 90.0, 30.0, 1.0, 9.0)
		"rifle_shot":
			return _shot(rng, 0.35, 0.6, 0.4, 180.0, 70.0, 0.5, 14.0)
		"smg_shot":
			return _shot(rng, 0.12, 0.3, 0.5, 150.0, 60.0, 0.4, 35.0)
		"dry_click":
			return _dry_click(rng)
		"reload":
			return _reload(rng)
		"punch_hit":
			return _punch_hit(rng)
		"shove":
			return _shove(rng)
		"melee_swing":
			return _melee_swing(rng)
		"blade_hit":
			return _blade_hit(rng)
		"zombie_groan":
			return _groan(rng, variant)
		"zombie_bite":
			return _bite(rng)
		"zombie_death":
			return _zombie_death(rng)
		"player_hurt":
			return _player_hurt(rng)
		"player_death":
			return _player_death(rng)
		"pickup":
			return _pickup()
		"door":
			return _door(rng)
		"ui_click":
			return _ui_click()
		"level_up":
			return _level_up()
		"heartbeat":
			return _heartbeat()
	return PackedFloat32Array()


## Renders a looping ambient bed. The loop is AMBIENT_SECONDS long and every
## frequency is snapped to a whole number of cycles per loop (k / T Hz).
static func render_ambient(kind: String) -> PackedFloat32Array:
	var layers: Array = []   # [freq, gain]
	var lfo_hz := 0.125
	var lfo_depth := 0.0
	match kind:
		"street":
			layers = [[55.0, 0.25], [55.5, 0.2], [110.0, 0.08], [165.0, 0.04]]
			lfo_hz = 0.125
			lfo_depth = 0.15
		"interior":
			layers = [[73.4, 0.22], [74.0, 0.18], [146.8, 0.06]]
			lfo_hz = 0.0625
			lfo_depth = 0.3
		"night":
			layers = [[41.2, 0.3], [49.0, 0.2], [58.25, 0.1], [82.4, 0.05]]
			lfo_hz = 0.0625
			lfo_depth = 0.4
		_:
			return PackedFloat32Array()
	var n := int(AMBIENT_RATE * AMBIENT_SECONDS)
	var out := PackedFloat32Array()
	out.resize(n)
	var lfo_cycles := maxf(1.0, round(lfo_hz * AMBIENT_SECONDS))
	for layer in layers:
		var f := snap_loop_freq(layer[0])
		var g: float = layer[1]
		var step := TAU * f / AMBIENT_RATE
		for i in n:
			out[i] += g * sin(step * i)
	# Slow swell, whole number of cycles per loop, so the loop stays seamless.
	var lfo_step := TAU * lfo_cycles / n
	for i in n:
		out[i] *= 1.0 - lfo_depth * 0.5 * (1.0 + sin(lfo_step * i))
	return _normalize(out, 0.6)


## Nearest frequency that is a whole number of cycles in one ambient loop.
static func snap_loop_freq(hz: float) -> float:
	return round(hz * AMBIENT_SECONDS) / AMBIENT_SECONDS


## Packs float samples (-1..1) into an AudioStreamWAV.
static func make_wav(samples: PackedFloat32Array, rate: int = MIX_RATE, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


# ---- building blocks -------------------------------------------------------

static func _count(seconds: float, rate: int = MIX_RATE) -> int:
	return maxi(1, int(seconds * rate))


## Oscillator with a linear pitch sweep and optional vibrato.
## wave: "sine", "square", "saw", "tri".
static func tone(seconds: float, f0: float, f1: float, wave: String,
		vib_depth: float = 0.0, vib_hz: float = 0.0, rate: int = MIX_RATE) -> PackedFloat32Array:
	var n := _count(seconds, rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t) + vib_depth * sin(TAU * vib_hz * i / rate)
		phase = fposmod(phase + f / rate, 1.0)
		match wave:
			"square":
				out[i] = 1.0 if phase < 0.5 else -1.0
			"saw":
				out[i] = 2.0 * phase - 1.0
			"tri":
				out[i] = 4.0 * absf(phase - 0.5) - 1.0
			_:
				out[i] = sin(TAU * phase)
	return out


static func noise(seconds: float, rng: RandomNumberGenerator, rate: int = MIX_RATE) -> PackedFloat32Array:
	var n := _count(seconds, rate)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## One-pole low-pass. alpha in (0, 1]: closer to 1 = brighter.
static func lowpass(buf: PackedFloat32Array, alpha: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	var y := 0.0
	for i in out.size():
		y += alpha * (out[i] - y)
		out[i] = y
	return out


static func highpass(buf: PackedFloat32Array, alpha: float) -> PackedFloat32Array:
	var low := lowpass(buf, alpha)
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] - low[i]
	return out


## Exponential decay, `rate_per_sec` is how many e-folds per second.
static func decay(buf: PackedFloat32Array, rate_per_sec: float, rate: int = MIX_RATE) -> PackedFloat32Array:
	var out := buf.duplicate()
	for i in out.size():
		out[i] *= exp(-rate_per_sec * i / rate)
	return out


## Linear attack then linear release, both in seconds.
static func attack_release(buf: PackedFloat32Array, attack: float, release: float, rate: int = MIX_RATE) -> PackedFloat32Array:
	var out := buf.duplicate()
	var a := maxi(1, int(attack * rate))
	var r := maxi(1, int(release * rate))
	var n := out.size()
	for i in n:
		var g := 1.0
		if i < a:
			g = float(i) / a
		var from_end := n - i
		if from_end < r:
			g = minf(g, float(from_end) / r)
		out[i] *= g
	return out


static func scale(buf: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	for i in out.size():
		out[i] *= gain
	return out


## Adds `src * gain` into `dst` starting at `offset_sec`. Grows dst if needed.
static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset_sec: float,
		gain: float = 1.0, rate: int = MIX_RATE) -> PackedFloat32Array:
	var start := int(offset_sec * rate)
	var needed := start + src.size()
	if dst.size() < needed:
		dst.resize(needed)
	for i in src.size():
		dst[start + i] += src[i] * gain
	return dst


static func _normalize(buf: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	if m <= 0.0:
		return buf
	return scale(buf, peak / m)


# ---- sound recipes ---------------------------------------------------------

## Gunshot: filtered noise body, bright crack, low pitched thump.
static func _shot(rng: RandomNumberGenerator, length: float, body_alpha: float, crack_gain: float,
		thump_f0: float, thump_f1: float, thump_gain: float, fade: float) -> PackedFloat32Array:
	var body := decay(lowpass(noise(length, rng), body_alpha), fade * 0.8)
	var crack := scale(decay(highpass(noise(length, rng), 0.5), fade * 2.5), crack_gain)
	var thump := scale(decay(tone(length, thump_f0, thump_f1, "sine"), fade * 0.8), thump_gain)
	var out := PackedFloat32Array()
	out.resize(_count(length))
	mix_into(out, body, 0.0, 0.8)
	mix_into(out, crack, 0.0, 0.5)
	mix_into(out, thump, 0.0, 1.0)
	return _normalize(out)


static func _dry_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var tick := decay(tone(0.03, 1800.0, 1800.0, "square"), 120.0)
	var clack := scale(decay(highpass(noise(0.02, rng), 0.6), 150.0), 0.5)
	var out := PackedFloat32Array()
	out.resize(_count(0.04))
	mix_into(out, tick, 0.0, 0.5)
	mix_into(out, clack, 0.0, 0.5)
	return _normalize(out, 0.7)


static func _reload(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count(0.55))
	mix_into(out, decay(tone(0.03, 900.0, 900.0, "square"), 120.0), 0.0, 0.5)
	mix_into(out, decay(highpass(noise(0.03, rng), 0.5), 120.0), 0.0, 0.4)
	mix_into(out, decay(tone(0.04, 1300.0, 1300.0, "square"), 100.0), 0.45, 0.5)
	mix_into(out, decay(highpass(noise(0.04, rng), 0.5), 100.0), 0.45, 0.4)
	return _normalize(out, 0.7)


static func _punch_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var smack := decay(lowpass(noise(0.12, rng), 0.2), 30.0)
	var thud := decay(tone(0.12, 160.0, 60.0, "sine"), 25.0)
	var out := PackedFloat32Array()
	out.resize(_count(0.12))
	mix_into(out, smack, 0.0, 0.8)
	mix_into(out, thud, 0.0, 0.7)
	return _normalize(out)


static func _shove(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var push := attack_release(lowpass(noise(0.2, rng), 0.1), 0.01, 0.15)
	var thud := decay(tone(0.2, 90.0, 45.0, "sine"), 12.0)
	var out := PackedFloat32Array()
	out.resize(_count(0.2))
	mix_into(out, push, 0.0, 0.6)
	mix_into(out, thud, 0.0, 0.8)
	return _normalize(out)


static func _melee_swing(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var air := highpass(noise(0.3, rng), 0.1)
	var swell := attack_release(air, 0.12, 0.15)
	return _normalize(scale(swell, 0.8))


static func _blade_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var metal := scale(decay(highpass(noise(0.1, rng), 0.7), 40.0), 0.8)
	var ring := scale(decay(tone(0.08, 1200.0, 600.0, "square"), 40.0), 0.3)
	var out := PackedFloat32Array()
	out.resize(_count(0.1))
	mix_into(out, metal, 0.0, 1.0)
	mix_into(out, ring, 0.0, 1.0)
	return _normalize(out)


## Three pitch variants (variant 0..2) of a low, breathy saw groan with a
## formant-like low-pass and a faint overtone.
static func _groan(rng: RandomNumberGenerator, variant: int) -> PackedFloat32Array:
	var bases := [70.0, 90.0, 55.0]
	var base: float = bases[posmod(variant, bases.size())]
	var length := 1.1
	var voice := lowpass(tone(length, base, base * 0.8, "saw", base * 0.03, 5.0), 0.08)
	var overtone := scale(tone(length, base * 2.3, base * 2.1, "sine"), 0.2)
	var breath := scale(lowpass(noise(length, rng), 0.05), 0.1)
	var out := PackedFloat32Array()
	out.resize(_count(length))
	mix_into(out, voice, 0.0, 0.8)
	mix_into(out, overtone, 0.0, 1.0)
	mix_into(out, breath, 0.0, 1.0)
	return _normalize(attack_release(out, 0.2, 0.4), 0.8)


static func _bite(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var snap := decay(tone(0.2, 160.0, 90.0, "square"), 15.0)
	var wet := decay(lowpass(noise(0.2, rng), 0.4), 25.0)
	var out := PackedFloat32Array()
	out.resize(_count(0.2))
	mix_into(out, scale(snap, 0.5), 0.0, 1.0)
	mix_into(out, scale(wet, 0.6), 0.0, 1.0)
	return _normalize(out)


static func _zombie_death(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length := 0.9
	var moan := decay(lowpass(tone(length, 130.0, 35.0, "saw"), 0.15), 3.0)
	var breath := scale(decay(lowpass(noise(length, rng), 0.05), 4.0), 0.3)
	var out := PackedFloat32Array()
	out.resize(_count(length))
	mix_into(out, moan, 0.0, 0.8)
	mix_into(out, breath, 0.0, 1.0)
	return _normalize(out, 0.8)


static func _player_hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var yelp := decay(tone(0.16, 420.0, 240.0, "square"), 10.0)
	var grit := scale(decay(highpass(noise(0.06, rng), 0.5), 40.0), 0.4)
	var out := PackedFloat32Array()
	out.resize(_count(0.16))
	mix_into(out, scale(yelp, 0.5), 0.0, 1.0)
	mix_into(out, grit, 0.0, 1.0)
	return _normalize(out, 0.8)


static func _player_death(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length := 1.4
	var fall := decay(lowpass(tone(length, 320.0, 50.0, "saw", 6.0, 4.0), 0.2), 2.5)
	var breath := scale(decay(lowpass(noise(length, rng), 0.05), 2.0), 0.25)
	var out := PackedFloat32Array()
	out.resize(_count(length))
	mix_into(out, fall, 0.0, 0.7)
	mix_into(out, breath, 0.0, 1.0)
	return _normalize(attack_release(out, 0.01, 0.3), 0.8)


static func _pickup() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count(0.15))
	mix_into(out, attack_release(tone(0.06, 880.0, 880.0, "sine"), 0.005, 0.03), 0.0, 0.6)
	mix_into(out, attack_release(tone(0.08, 1320.0, 1320.0, "sine"), 0.005, 0.05), 0.06, 0.6)
	return _normalize(out, 0.6)


static func _door(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var creak := attack_release(tone(0.5, 180.0, 120.0, "saw", 8.0, 6.0), 0.1, 0.2)
	var thud := decay(lowpass(noise(0.05, rng), 0.05), 60.0)
	var out := PackedFloat32Array()
	out.resize(_count(0.5))
	mix_into(out, scale(lowpass(creak, 0.1), 0.4), 0.0, 1.0)
	mix_into(out, thud, 0.0, 0.8)
	return _normalize(out, 0.7)


static func _ui_click() -> PackedFloat32Array:
	return _normalize(scale(decay(tone(0.025, 1000.0, 1000.0, "sine"), 150.0), 0.6), 0.5)


static func _level_up() -> PackedFloat32Array:
	# C5 E5 G5 C6 arpeggio.
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var out := PackedFloat32Array()
	out.resize(_count(0.5))
	for k in notes.size():
		var note := attack_release(tone(0.15, notes[k], notes[k], "tri"), 0.005, 0.08)
		mix_into(out, note, 0.1 * k, 0.6)
	return _normalize(out, 0.6)


static func _heartbeat() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count(0.6))
	mix_into(out, decay(tone(0.25, 55.0, 40.0, "sine"), 18.0), 0.0, 0.9)
	mix_into(out, decay(tone(0.2, 55.0, 40.0, "sine"), 18.0), 0.25, 0.7)
	return _normalize(out, 0.8)
