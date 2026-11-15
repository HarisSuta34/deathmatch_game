extends Node
# Sound autoload. Everything is synthesized in code at startup (no audio files).
# The dedicated server never calls init(), so it generates nothing.

const RATE := 22050
const MUSIC_RATE := 11025

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer


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
