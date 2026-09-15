extends SceneTree

## Generates every sound in the game from scratch and writes them to
## assets/audio/ as binary AudioStreamWAV resources.
##
##     godot --headless --path . --script res://tools/build_audio.gd
##
## Why synthesised rather than sourced: there is no audio in the asset packs
## this project uses, and a "free" sound pulled off the internet is a licence
## question nobody wants to answer later. Everything here is generated from
## noise and sine waves, so it is unambiguously ours and costs no attribution.
##
## Saved as .res, NOT .wav, on purpose. Godot's save_to_wav() does not write
## loop points, so a looping ambience would need a hand-edited .import file to
## survive; an AudioStreamWAV resource carries loop_mode with it and load()s
## directly with no import step at all.

const OUT_DIR := "res://assets/audio/"
## 22 kHz is plenty for this material and halves the file sizes. Nothing here
## has meaningful content above 11 kHz.
const RATE := 22050
const TAU_F := TAU

var _rng := RandomNumberGenerator.new()
var _failures := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_rng.seed = 0xC021F1E

	# The peak each sound is normalised to IS the mix. Measured before this was
	# added, a footstep peaked at 0.97 and the pickup chime at 0.26 — so every
	# step drowned the reward sound. Levels are set here, deliberately, rather
	# than falling out of however loud the synthesis happened to be.
	_write("sfx_step", _step(), false, 0.32)      # plays constantly; keep it under everything
	_write("sfx_chop", _chop(), false, 0.85)
	_write("sfx_pickup", _pickup(), false, 0.60)
	_write("sfx_craft", _craft(), false, 0.70)
	_write("sfx_place", _place(), false, 0.75)
	_write("sfx_ui", _ui_click(), false, 0.30)
	_write("sfx_eat", _eat(), false, 0.55)
	_write("sfx_fizzle", _fizzle(), false, 0.50)   # a wet log refusing to catch
	_write("sfx_fire", _fire(), true, 0.45)       # a bed, not an event
	_write("amb_day", _ambience_day(), true, 0.50)
	_write("amb_night", _ambience_night(), true, 0.42)
	# Sits ABOVE the day/night bed it replaces (0.50/0.42) because rain is the
	# loudest thing in a real downpour — but not by much, or it stops being cozy.
	_write("amb_rain", _ambience_rain(), true, 0.52)
	_write("music_theme", _music(), true, 0.55)

	if _failures > 0:
		push_error("build_audio: %d sound(s) failed to save" % _failures)
		quit(1)
		return
	print("build_audio: done")
	quit(0)


# --- writing ----------------------------------------------------------------

## Saves a float buffer (-1..1) as a 16-bit mono AudioStreamWAV, and asserts it
## round-trips — a resource that saves but will not load back is worse than a
## loud failure here.
func _write(name: String, samples: PackedFloat32Array, looping: bool, peak: float) -> void:
	samples = _normalise(samples, peak)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = _to_pcm16(samples)
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	var path := OUT_DIR + name + ".res"
	if ResourceSaver.save(stream, path) != OK:
		push_error("build_audio: could not save %s" % path)
		_failures += 1
		return
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
	if back == null or back.data.size() != stream.data.size():
		push_error("build_audio: %s did not round-trip" % path)
		_failures += 1
		return
	print("  %-14s %5.2fs  %6.1f KB  peak %.2f%s" % [name, float(samples.size()) / RATE,
		stream.data.size() / 1024.0, peak, "  (looping)" if looping else ""])


## Scales a buffer so its loudest sample sits exactly at `peak`. This is both
## the clip guard and the mixing desk: nothing is written above the level it
## was given, and nothing arrives quieter than intended either.
func _normalise(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0
	for value in buf:
		loudest = maxf(loudest, absf(value))
	if loudest <= 0.0001:
		push_error("build_audio: a sound came out silent")
		_failures += 1
		return buf
	var gain := peak / loudest
	for i in buf.size():
		buf[i] *= gain
	return buf


func _to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(round(clampf(samples[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, value)
	return bytes


# --- building blocks --------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	out.fill(0.0)
	return out


## Exponential decay. `curve` above 1 makes the tail snappier.
func _decay(t: float, length: float, curve := 3.0) -> float:
	return pow(maxf(0.0, 1.0 - t / length), curve)


## A short fade in and out, so a one-shot never starts or ends on a click.
func _deglitch(buf: PackedFloat32Array, fade_ms := 4.0) -> PackedFloat32Array:
	var n := mini(int(fade_ms * 0.001 * RATE), buf.size() / 2)
	for i in n:
		var k := float(i) / float(n)
		buf[i] *= k
		buf[buf.size() - 1 - i] *= k
	return buf


## Crossfades the tail of a buffer over its head so a loop has no seam. The
## buffer keeps its length; only the first `seconds` are blended.
func _seamless(buf: PackedFloat32Array, seconds := 0.5) -> PackedFloat32Array:
	var n := mini(int(seconds * RATE), buf.size() / 3)
	var tail := PackedFloat32Array()
	tail.resize(n)
	for i in n:
		tail[i] = buf[buf.size() - n + i]
	for i in n:
		var k := float(i) / float(n)
		buf[i] = buf[i] * k + tail[i] * (1.0 - k)
	# The tail has been folded into the head, so it must not also play.
	buf.resize(buf.size() - n)
	return buf


## One-pole low-pass. `cutoff` in Hz. Turns white noise into something that
## sounds like wind, surf or a footstep instead of static.
func _lowpass(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a: float = 1.0 - exp(-TAU_F * cutoff / RATE)
	var state := 0.0
	for i in buf.size():
		state += a * (buf[i] - state)
		buf[i] = state
	return buf


func _highpass(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a: float = 1.0 - exp(-TAU_F * cutoff / RATE)
	var state := 0.0
	for i in buf.size():
		state += a * (buf[i] - state)
		buf[i] = buf[i] - state
	return buf


func _noise(seconds: float) -> PackedFloat32Array:
	var buf := _buffer(seconds)
	for i in buf.size():
		buf[i] = _rng.randf_range(-1.0, 1.0)
	return buf


## Adds a decaying sine to a buffer. The workhorse for every tonal sound here.
func _add_tone(buf: PackedFloat32Array, start: float, seconds: float, hz: float,
		gain: float, curve := 3.0, bend := 0.0) -> void:
	var first := int(start * RATE)
	var count := int(seconds * RATE)
	var phase := 0.0
	for i in count:
		var index := first + i
		if index < 0 or index >= buf.size():
			continue
		var t := float(i) / RATE
		# A little pitch bend is what separates a "blip" from a "beep".
		phase += TAU_F * (hz + bend * t) / RATE
		buf[index] += sin(phase) * gain * _decay(t, seconds, curve)


# --- the sounds -------------------------------------------------------------

## Footstep: a soft low thud with a touch of grit on top.
func _step() -> PackedFloat32Array:
	var buf := _lowpass(_noise(0.09), 900.0)
	for i in buf.size():
		buf[i] *= _decay(float(i) / RATE, 0.09, 4.0) * 2.4
	_add_tone(buf, 0.0, 0.07, 95.0, 0.22, 5.0)
	return _deglitch(buf)


## Chop: a woody knock plus a bright transient, so it reads as impact on wood
## rather than a drum.
func _chop() -> PackedFloat32Array:
	var buf := _buffer(0.30)
	var crack := _highpass(_noise(0.30), 1800.0)
	for i in buf.size():
		buf[i] = crack[i] * _decay(float(i) / RATE, 0.06, 5.0) * 0.55
	_add_tone(buf, 0.0, 0.22, 180.0, 0.45, 4.0, -60.0)
	_add_tone(buf, 0.0, 0.10, 420.0, 0.20, 6.0)
	return _deglitch(buf)


## Pickup: two quick rising notes. Deliberately the most cheerful sound here.
func _pickup() -> PackedFloat32Array:
	var buf := _buffer(0.26)
	_add_tone(buf, 0.00, 0.10, 880.0, 0.30, 3.0)
	_add_tone(buf, 0.06, 0.18, 1174.7, 0.26, 3.0)
	return _deglitch(buf)


## Craft: a little three-note pentatonic flourish — the reward sound.
func _craft() -> PackedFloat32Array:
	var buf := _buffer(0.58)
	var notes := [523.25, 659.25, 783.99]
	for i in notes.size():
		_add_tone(buf, i * 0.09, 0.32, notes[i], 0.26, 2.6)
		# A quiet octave above gives it a bell-like shimmer without a filter.
		_add_tone(buf, i * 0.09, 0.22, notes[i] * 2.0, 0.07, 3.5)
	return _deglitch(buf)


## Placing a building: a heavier version of the footstep thud.
func _place() -> PackedFloat32Array:
	var buf := _lowpass(_noise(0.22), 600.0)
	for i in buf.size():
		buf[i] *= _decay(float(i) / RATE, 0.22, 3.0) * 2.0
	_add_tone(buf, 0.0, 0.18, 70.0, 0.40, 3.0, -20.0)
	return _deglitch(buf)


## UI click: short, quiet, and low enough not to be fatiguing.
func _ui_click() -> PackedFloat32Array:
	var buf := _buffer(0.07)
	_add_tone(buf, 0.0, 0.05, 620.0, 0.22, 6.0)
	return _deglitch(buf, 2.0)


## Eating or drinking: two soft gulps.
func _eat() -> PackedFloat32Array:
	var buf := _buffer(0.34)
	_add_tone(buf, 0.00, 0.12, 300.0, 0.28, 4.0, 220.0)
	_add_tone(buf, 0.15, 0.14, 240.0, 0.24, 4.0, 260.0)
	return _deglitch(buf)


## Fire: a low roar with random pops scattered through it. Loops.
func _fire() -> PackedFloat32Array:
	var seconds := 4.0
	var roar := _lowpass(_noise(seconds), 420.0)
	var hiss := _highpass(_noise(seconds), 2600.0)
	var buf := _buffer(seconds)
	for i in buf.size():
		# Slow swell so the roar breathes instead of sitting flat.
		var swell: float = 0.75 + 0.25 * sin(TAU_F * 0.3 * float(i) / RATE)
		buf[i] = roar[i] * 1.9 * swell + hiss[i] * 0.05
	for pop in 26:
		var at := _rng.randf_range(0.0, seconds - 0.1)
		_add_tone(buf, at, _rng.randf_range(0.02, 0.05),
			_rng.randf_range(700.0, 2200.0), _rng.randf_range(0.05, 0.14), 6.0)
	return _seamless(buf, 0.6)


## Daytime: surf rolling up a beach, with the odd gull. Loops.
func _ambience_day() -> PackedFloat32Array:
	var seconds := 12.0
	var surf := _lowpass(_noise(seconds), 700.0)
	var buf := _buffer(seconds)
	for i in buf.size():
		var t := float(i) / RATE
		# Two slow waves at different rates, so the swell never repeats
		# obviously within the loop.
		var swell: float = 0.45 + 0.35 * pow(maxf(0.0, sin(TAU_F * 0.11 * t)), 2.0) \
			+ 0.20 * pow(maxf(0.0, sin(TAU_F * 0.073 * t + 1.7)), 2.0)
		buf[i] = surf[i] * 2.2 * swell
	# A few gulls, sparse enough to be a surprise rather than a pattern.
	for call in 5:
		var at := _rng.randf_range(0.5, seconds - 1.2)
		_add_tone(buf, at, 0.16, _rng.randf_range(1100.0, 1500.0), 0.05, 2.0, 500.0)
		_add_tone(buf, at + 0.22, 0.13, _rng.randf_range(1000.0, 1400.0), 0.04, 2.0, 420.0)
	return _seamless(buf, 1.0)


## Night: crickets over a thin wind. Loops.
func _ambience_night() -> PackedFloat32Array:
	var seconds := 12.0
	var wind := _lowpass(_noise(seconds), 300.0)
	var buf := _buffer(seconds)
	for i in buf.size():
		var t := float(i) / RATE
		buf[i] = wind[i] * 1.3 * (0.6 + 0.4 * sin(TAU_F * 0.09 * t))
	# Crickets chirp in bursts of three, roughly every half second, each burst
	# slightly detuned from the last so it does not sound like a metronome.
	var at := 0.0
	while at < seconds - 0.4:
		var hz := _rng.randf_range(3900.0, 4400.0)
		for chirp in 3:
			_add_tone(buf, at + chirp * 0.035, 0.028, hz, 0.055, 4.0)
		at += _rng.randf_range(0.42, 0.72)
	return _seamless(buf, 1.0)


## Rain: broadband noise shaped into a hiss, with slow swells so a long loop
## does not read as a flat wall of static. Loops.
func _ambience_rain() -> PackedFloat32Array:
	var seconds := 12.0
	# Two bands rather than one: the low one is the body of the downpour, the
	# high one is the patter on leaves. A single lowpass sounds like wind.
	var body := _lowpass(_noise(seconds), 1800.0)
	var patter := _highpass(_lowpass(_noise(seconds), 6500.0), 2600.0)
	var buf := _buffer(seconds)
	for i in buf.size():
		var t := float(i) / RATE
		# Slow gusts at two incommensurate rates, so the swell never lines up
		# with itself inside the loop.
		var gust: float = 0.72 + 0.20 * sin(TAU_F * 0.08 * t) \
			+ 0.12 * sin(TAU_F * 0.053 * t + 2.1)
		buf[i] = (body[i] * 1.5 + patter[i] * 0.9) * gust
	# A handful of heavier drips, so it is rain landing on things rather than
	# a tap running.
	for drip in 9:
		var at := _rng.randf_range(0.3, seconds - 0.6)
		_add_tone(buf, at, 0.05, _rng.randf_range(600.0, 1500.0), 0.05, 5.0, 900.0)
	return _seamless(buf, 1.0)


## A wet log hitting cold coals: a short hiss with no tone in it at all.
func _fizzle() -> PackedFloat32Array:
	var seconds := 0.45
	var buf := _highpass(_lowpass(_noise(seconds), 5200.0), 900.0)
	for i in buf.size():
		var t := float(i) / RATE
		# Swells in over the first 60ms then dies away, which is what steam
		# off a hot stone actually sounds like — not a click.
		var env: float = minf(t / 0.06, 1.0) * _decay(maxf(t - 0.06, 0.0), seconds, 2.4)
		buf[i] *= env * 1.4
	return _deglitch(buf)


## The theme: a slow pentatonic melody over a drone. Pentatonic because every
## note in it agrees with every other, so a randomised melody cannot sound
## wrong — which is exactly what a background loop needs.
func _music() -> PackedFloat32Array:
	var seconds := 28.0
	var buf := _buffer(seconds)
	var scale := [261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25]

	# Drone: root and fifth, quietly, the whole way through.
	var phase_a := 0.0
	var phase_b := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		phase_a += TAU_F * 130.81 / RATE
		phase_b += TAU_F * 196.00 / RATE
		var swell: float = 0.55 + 0.45 * sin(TAU_F * 0.05 * t)
		buf[i] += (sin(phase_a) * 0.055 + sin(phase_b) * 0.035) * swell

	# Melody: one note every 0.9s, stepping mostly by one degree so it wanders
	# rather than jumps.
	var degree := 3
	var at := 0.4
	while at < seconds - 1.4:
		degree = clampi(degree + _rng.randi_range(-2, 2), 0, scale.size() - 1)
		var hz: float = scale[degree]
		_add_tone(buf, at, 1.15, hz, 0.15, 1.8)
		_add_tone(buf, at, 0.70, hz * 2.0, 0.035, 2.6)
		# An occasional harmony a third up, for warmth.
		if _rng.randf() < 0.35 and degree + 2 < scale.size():
			_add_tone(buf, at + 0.05, 0.85, scale[degree + 2], 0.055, 2.2)
		at += 0.9
	return _seamless(buf, 1.5)
