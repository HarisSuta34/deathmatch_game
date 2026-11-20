extends Node
# Sound autoload. Everything is synthesized in code at startup (no audio files).
# The dedicated server never calls init(), so it generates nothing.

const RATE := 22050
const MUSIC_RATE := 11025

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _bulgaria: AudioStreamPlayer

const KNIFE_CLIP := "res://audio/knife_kill.ogg"


func init() -> void:
	if _music:
		return
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_streams = {
		"shot_rifle": _wav(_blast(0.2, 26.0, 0.55, 170.0, 0.5, 0.9), RATE),
		"shot_sniper": _wav(_blast(0.8, 6.5, 0.22, 85.0, 0.9, 1.0), RATE),
		"shot_shotgun": _wav(_blast(0.45, 11.0, 0.38, 110.0, 0.8, 1.0), RATE),
		"shot_knife": _wav(_whoosh(0.22), RATE),
		"step": _wav(_blast(0.07, 55.0, 0.14, 75.0, 0.5, 0.7), RATE),
		"jump": _wav(_tone(0.13, 280.0, 560.0, 14.0, 0.35), RATE),
		"hit": _wav(_tone(0.05, 1100.0, 1100.0, 40.0, 0.4), RATE),
		"hurt": _wav(_tone(0.18, 220.0, 110.0, 12.0, 0.6), RATE),
		"empty": _wav(_blast(0.04, 120.0, 0.9, 1500.0, 0.3, 0.4), RATE),
	}
	var heal := _tone(0.45, 440.0, 990.0, 5.0, 0.35)
	_mix(heal, _tone(0.3, 660.0, 1320.0, 7.0, 0.25), int(0.12 * RATE))
	_streams["heal"] = _wav(heal, RATE)
	var kill := _tone(0.3, 660.0, 660.0, 9.0, 0.4)
	_mix(kill, _tone(0.2, 990.0, 990.0, 9.0, 0.4), int(0.09 * RATE))
	_streams["kill"] = _wav(kill, RATE)
	# Reload: magazine out, magazine in, bolt.
	var rel := PackedFloat32Array()
	rel.resize(int(0.75 * RATE))
	_mix(rel, _blast(0.05, 70.0, 0.8, 900.0, 0.3, 0.6), 0)
	_mix(rel, _blast(0.06, 60.0, 0.6, 500.0, 0.4, 0.7), int(0.32 * RATE))
	_mix(rel, _blast(0.05, 80.0, 0.9, 1300.0, 0.3, 0.6), int(0.6 * RATE))
	_streams["reload"] = _wav(rel, RATE)
	# Knife-kill jingle: your own clip at res://audio/knife_kill.ogg if present, else the built-in one.
	_bulgaria = AudioStreamPlayer.new()
	_bulgaria.volume_db = -2.0
	if ResourceLoader.exists(KNIFE_CLIP):
		_bulgaria.stream = load(KNIFE_CLIP)
	else:
		_bulgaria.stream = _make_ruchenitsa()
	add_child(_bulgaria)
	_music = AudioStreamPlayer.new()
	_music.stream = _make_music()
	_music.volume_db = -13.0
	add_child(_music)


# Plays a sound without position (own actions, UI).
func play(sound: String, db := 0.0, pitch := 1.0) -> void:
	if _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


# Plays a sound in the world: audible across the whole map, quieter with distance.
func play_at(sound: String, pos: Vector3, parent: Node, db := 0.0) -> void:
	if _pool.is_empty():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sound]
	p.volume_db = db
	p.unit_size = 14.0
	p.max_db = 0.0
	p.position = pos
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# Plays the knife-kill jingle from the start (restarts if a second knife kill happens).
func bulgaria() -> void:
	if _bulgaria:
		_bulgaria.stop()
		_bulgaria.play()


func music(on: bool) -> void:
	if _music == null or _music.playing == on:
		return
	if on:
		_music.play()
	else:
		_music.stop()


# ---------- synthesis ----------

func _wav(samples: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int) -> void:
	for i in mini(src.size(), dst.size() - offset):
		dst[offset + i] += src[i]


# Low-passed noise burst plus a falling sine "thump": gunshots, steps, clicks.
func _blast(dur: float, decay: float, lowpass: float, thump_hz: float, thump: float, noise: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * lowpass
		ph += TAU * thump_hz * exp(-t * 14.0) / RATE
		out[i] = (lp * noise + sin(ph) * thump) * exp(-t * decay) * 0.8
	return out


func _whoosh(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var k := float(i) / n
		lp += (randf_range(-1.0, 1.0) - lp) * (0.05 + k * 0.35)
		out[i] = lp * sin(k * PI) * 0.9
	return out


func _tone(dur: float, f0: float, f1: float, decay: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * lerpf(f0, f1, k) / RATE
		out[i] = sin(ph) * exp(-k * dur * decay) * vol
	return out


# 16-second chiptune loop: square-wave lead and bass over simple drums (Am F C G).
func _make_music() -> AudioStreamWAV:
	var step := 0.25
	var buf := PackedFloat32Array()
	buf.resize(int(64 * step * MUSIC_RATE))
	var chords := [[45, 57, 60, 64], [41, 53, 57, 60], [48, 60, 64, 67], [43, 55, 59, 62]]
	var patterns := [[1, 2, 3, 2, 1, 2, 3, 2], [3, 2, 1, 2, 3, 3, 2, 1]]
	for bar in 8:
		var ch: Array = chords[bar % 4]
		var pat: Array = patterns[bar / 4]
		for e in 8:
			var at := int((bar * 8 + e) * step * MUSIC_RATE)
			_note(buf, at, step * 0.9, ch[pat[e]] + 12, 0.13, 0.5)
			if e != 1 and e != 5:
				_note(buf, at, step * 0.8, ch[0], 0.2, 0.25)
			if e % 4 == 0:
				_drum(buf, at, 0.14, 0.5, 30.0, 110.0)
			elif e % 4 == 2:
				_drum(buf, at, 0.1, 0.22, 28.0, 0.0)
			else:
				_drum(buf, at, 0.03, 0.07, 90.0, 0.0)
	return _wav(buf, MUSIC_RATE, true)


func _note(buf: PackedFloat32Array, at: int, dur: float, midi: int, vol: float, duty: float) -> void:
	var freq := 440.0 * pow(2.0, (midi - 69) / 12.0)
	var n := mini(int(dur * MUSIC_RATE), buf.size() - at)
	var inc := freq / MUSIC_RATE
	var ph := 0.0
	for i in n:
		ph = fmod(ph + inc, 1.0)
		var env := minf(1.0, i / 40.0) * (1.0 - float(i) / n * 0.7)
		buf[at + i] += (vol if ph < duty else -vol) * env


# hz > 0: kick (falling sine); hz == 0: noise (snare / hi-hat).
func _drum(buf: PackedFloat32Array, at: int, dur: float, vol: float, decay: float, hz: float) -> void:
	var n := mini(int(dur * MUSIC_RATE), buf.size() - at)
	var ph := 0.0
	for i in n:
		var t := float(i) / MUSIC_RATE
		var v := randf_range(-1.0, 1.0)
		if hz > 0.0:
			ph += TAU * hz * exp(-t * 20.0) / MUSIC_RATE
			v = sin(ph)
		buf[at + i] += v * vol * exp(-t * decay)


# About 4 s of an original tune in the style of a Bulgarian ruchenitsa: 7/8 time (2+2+3),
# a gaida-like (Bulgarian bagpipe) melody with grace notes over a drone, and a tapan drum.
# The scale is D harmonic minor, whose augmented second (B flat to C sharp) gives the
# typical Balkan sound.
func _make_ruchenitsa() -> AudioStreamWAV:
	var eighth := 0.11
	var bars := [
		[[69, 2], [70, 1], [69, 1], [67, 1], [69, 2]],
		[[74, 2], [73, 1], [70, 1], [69, 1], [67, 2]],
		[[69, 1], [70, 1], [69, 1], [67, 1], [65, 1], [64, 2]],
		[[65, 2], [67, 1], [65, 1], [64, 1], [62, 2]],
		[[62, 2], [69, 2], [74, 3]],
	]
	var total := int((35 * eighth + 0.45) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# One cycle of a nasal, reedy waveform (strong odd and even harmonics), read as a table.
	var table := PackedFloat32Array()
	table.resize(256)
	for i in 256:
		var p := TAU * i / 256.0
		table[i] = (sin(p) + 0.7 * sin(2 * p) + 0.6 * sin(3 * p) + 0.4 * sin(4 * p) + 0.35 * sin(5 * p) + 0.2 * sin(7 * p)) / 3.0
	# Drone on low D for the whole clip.
	_reed(buf, table, 0, total, 50, 0.16, 0.0)
	var at := 0
	var step := 0
	for bar: Array in bars:
		for n: Array in bar:
			var dur := int(n[1] * eighth * RATE)
			var grace := 0
			if n[1] >= 2:   # quick ornament a step above, typical of gaida playing
				grace = int(0.03 * RATE)
				_reed(buf, table, at, grace, n[0] + 2, 0.32, 0.0)
			_reed(buf, table, at + grace, dur - grace, n[0], 0.32, 5.5)
			at += dur
		# Tapan: deep boom on the start of each group (2+2+3), stick clicks on every eighth.
		for e in 7:
			var s := (step + e) * eighth
			var pos := int(s * RATE)
			if e == 0 or e == 2 or e == 4:
				_mix(buf, _blast(0.25, 14.0, 0.05, 70.0, 0.85 if e == 0 else 0.55, 0.15), pos)
			else:
				_mix(buf, _blast(0.04, 90.0, 0.7, 900.0, 0.0, 0.18), pos)
		step += 7
	_mix(buf, _blast(0.45, 7.0, 0.05, 60.0, 1.0, 0.2), at)   # final boom
	for i in total:
		buf[i] = clampf(buf[i] * 0.9, -1.0, 1.0)
	return _wav(buf, RATE)


func _reed(buf: PackedFloat32Array, table: PackedFloat32Array, at: int, n: int, midi: int, vol: float, vibrato: float) -> void:
	var freq := 440.0 * pow(2.0, (midi - 69) / 12.0)
	var ph := 0.0
	n = mini(n, buf.size() - at)
	for i in n:
		var f := freq * (1.0 + sin(i * TAU * vibrato / RATE) * 0.006)
		ph = fmod(ph + f * 256.0 / RATE, 256.0)
		var env := minf(1.0, i / 120.0) * minf(1.0, (n - i) / 200.0)
		buf[at + i] += table[int(ph)] * vol * env
