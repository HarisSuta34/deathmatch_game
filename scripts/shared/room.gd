extends RefCounted
# Authoritative game room: lobby + match simulation.
# The dedicated server keeps one instance per room; offline practice runs one in-process.
# Outgoing messages go through `send(peer_id, msg, args)`.

const Weapons = preload("res://scripts/shared/weapons.gd")
const Maps = preload("res://scripts/shared/maps.gd")

const TICK := 0.05            # snapshot interval (20 Hz)
const MAX_HP := 100
const MAX_PLAYERS := 20
const RESPAWN_DELAY := 10.0      # death screen (scores + loadout) is shown during this time
const SPAWN_PROTECT := 10.0      # invincible after a respawn (not at match start), even while shooting
const WARMUP := 8.0              # match intro screen before the first spawn
const RESULTS_TIME := 10.0
const EYE := Vector3(0, 1.5, 0)
const BOX_HALF := Vector3(0.4, 0, 0.4)
const STAND_H := 1.8
const CROUCH_H := 1.25
const FLAG_CROUCH := 32
const HEAL_RADIUS := 1.4
const HEAL_DELAY := [15.0, 25.0]   # seconds until the heal zone reappears after a pickup
const START_ERROR := "Need an even number of players (4-20) to start"

var code := ""
var host_id := 0
var state := "lobby"          # lobby | match | results
var map_id := 0
var minutes := 10
var players := {}             # id -> player Dictionary
var scores := [0, 0]
var time_left := 0.0
var tick_n := 0
var dev := false              # dev server: skip the 4-20 even rule
var dev_seconds := 0.0        # dev server: override match length
var practice := false         # offline room with bots
var send: Callable
var heal_pos: Variant = null  # Vector3 while a heal zone is on the map

var _now := 0.0
var _acc := 0.0
var _warm_until := 0.0
var _state_until := 0.0
var _spawn_n := 0
var _history := []            # [{t: tick, p: {id: position}}] for lag compensation
var _map: Dictionary
var _rng := RandomNumberGenerator.new()
var _heal_at := 0.0
var _last_heal := Vector3(0, -100, 0)


func add_player(id: int, nick: String, bot := false, team := -1) -> void:
	players[id] = {
		"id": id, "nick": nick, "bot": bot, "team": team,
		"weapon": "rifle", "next_weapon": "rifle",
		"hp": MAX_HP, "alive": false, "pos": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "flags": 0,
		"kills": 0, "deaths": 0, "respawn_at": 0.0, "protect_until": 0.0,
		"ammo": 0, "shot_time": 0.0, "reload_until": 0.0, "think_at": 0.0,
		"protect_next": false, "heal_msg_at": 0.0,
	}
	if host_id == 0 and not bot:
		host_id = id
	if not practice:
		_send_lobby()


func remove_player(id: int) -> void:
	if not players.has(id):
		return
	players.erase(id)
	if id == host_id:
		host_id = 0
		for pid: int in players:
			if not players[pid].bot:
				host_id = pid
				break
	if state != "lobby":
		_all("left", [id])
	_send_lobby()


func human_count() -> int:
	var n := 0
	for id: int in players:
		if not players[id].bot:
			n += 1
	return n


func handle(id: int, msg: String, a: Array) -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	match msg:
		"set_opt":
			if id == host_id and state == "lobby" and a.size() == 2 and a[0] is int and a[1] is int:
				if a[0] >= 0 and a[0] < Maps.COUNT:
					map_id = a[0]
				if a[1] in [5, 10, 15]:
					minutes = a[1]
				_send_lobby()
		"start":
			if id == host_id and state == "lobby":
				_try_start()
		"state":
			if state == "match" and p.alive and a.size() == 4 and a[0] is Vector3 and a[1] is float and a[2] is float and a[3] is int:
				if a[0].is_finite() and is_finite(a[1]) and is_finite(a[2]):
					p.pos = a[0]
					p.yaw = a[1]
					p.pitch = a[2]
					p.flags = a[3]
		"shoot":
			if a.size() == 4 and a[0] is Vector3 and a[1] is Vector3 and a[2] is int and a[3] is float:
				_shoot(p, a[0], a[1], a[2], a[3])
		"reload":
			var w: Dictionary = Weapons.DATA[p.weapon]
			if p.alive and w.mag > 0:
				p.ammo = w.mag
				p.reload_until = _now + w.reload - 0.25
		"pick":
			if a.size() == 1 and a[0] is String and Weapons.DATA.has(a[0]):
				p.next_weapon = a[0]


func tick(delta: float) -> void:
	_now += delta
	if state == "results":
		if _now >= _state_until:
			state = "lobby"
			_send_lobby()
		return
	if state != "match":
		return
	if _now >= _warm_until:
		time_left -= delta
		if time_left <= 0.0:
			_end_match()
			return
	for id: int in players:
		var p: Dictionary = players[id]
		if not p.alive:
			if _now >= p.respawn_at:
				_spawn(p)
		elif p.pos.y < -20.0:
			_kill(p, {})
		elif p.bot:
			_bot_think(p)
	if _now >= _warm_until:
		_update_heal()
	_acc += delta
	if _acc >= TICK:
		_acc = minf(_acc - TICK, TICK)
		tick_n += 1
		_snapshot()


# ---------- lobby / match flow ----------

func _all(msg: String, args: Array) -> void:
	for id: int in players:
		if not players[id].bot:
			send.call(id, msg, args)


func _send_lobby() -> void:
	var list := []
	for id: int in players:
		list.append([id, players[id].nick])
	_all("lobby", [{"code": code, "host": host_id, "map": map_id, "minutes": minutes, "players": list, "state": state}])


func _try_start() -> void:
	var n := players.size()
	if not (dev or practice) and (n < 4 or n > MAX_PLAYERS or n % 2 != 0):
		send.call(host_id, "error", [START_ERROR])
		return
	_map = Maps.get_map(map_id)
	if not practice:
		# Random, equal teams: shuffle, then first half red, second half blue.
		var ids := players.keys()
		ids.shuffle()
		for i in ids.size():
			players[ids[i]].team = 0 if i < (ids.size() + 1) / 2 else 1
	scores = [0, 0]
	time_left = dev_seconds if dev_seconds > 0.0 else minutes * 60.0
	state = "match"
	_history.clear()
	_spawn_n = _rng.randi() % 10
	_warm_until = _now + WARMUP
	heal_pos = null
	_heal_at = _warm_until + _rng.randf_range(6.0, 10.0)
	var info := []
	for id: int in players:
		var p: Dictionary = players[id]
		p.kills = 0
		p.deaths = 0
		p.alive = false
		p.protect_next = false   # no spawn protection at match start
		p.respawn_at = _warm_until
		info.append([id, p.nick, p.team])
	_all("match_start", [map_id, time_left, info, WARMUP])


func _end_match() -> void:
	state = "results"
	heal_pos = null
	_state_until = _now + RESULTS_TIME
	var stats := []
	for id: int in players:
		var p: Dictionary = players[id]
		p.alive = false
		stats.append([id, p.nick, p.team, p.kills, p.deaths])
	var winner := -1
	if scores[0] != scores[1]:
		winner = 0 if scores[0] > scores[1] else 1
	_all("match_end", [scores.duplicate(), winner, stats, RESULTS_TIME])


func _spawn(p: Dictionary) -> void:
	p.weapon = p.next_weapon
	p.hp = MAX_HP
	p.alive = true
	p.ammo = Weapons.DATA[p.weapon].mag
	p.reload_until = 0.0
	var prot := SPAWN_PROTECT if p.protect_next else 0.0
	p.protect_until = _now + prot
	if p.bot:
		# Practice bots stand at a random spot on the enemy half of the map.
		var x := _rng.randf_range(-0.6, 0.6) * float(_map.hx)
		var z := _rng.randf_range(-0.1, 0.55) * float(_map.hz)
		var f := Maps.ray_world(_map, Vector3(x, 30, z), Vector3(x, -1, z))
		p.pos = Vector3(x, 30.0 - 31.0 * f, z)
		p.yaw = 0.0
	else:
		var sp: Array = Maps.spawn_point(_map, p.team, _spawn_n)
		_spawn_n += 1
		p.pos = sp[0]
		p.yaw = sp[1]
	p.pitch = 0.0
	_all("spawn", [p.id, p.pos, p.yaw, p.weapon, prot])


func _snapshot() -> void:
	var ids := PackedInt32Array()
	var data := PackedFloat32Array()   # 6 floats per player: x y z yaw pitch flags
	var hist := {}
	for id: int in players:
		var p: Dictionary = players[id]
		if p.team < 0:
			continue
		# flags: bit0 alive, bit1 spawn-protected, higher bits come from the client (animation)
		var f: int = (p.flags & ~3) | (1 if p.alive else 0) | (2 if _now < p.protect_until else 0)
		ids.append(id)
		var pos: Vector3 = p.pos
		data.append_array([pos.x, pos.y, pos.z, p.yaw, p.pitch, f])
		if p.alive:
			hist[id] = pos
	_history.append({"t": tick_n, "p": hist})
	if _history.size() > 24:
		_history.pop_front()
	_all("snap", [tick_n, time_left, ids, data])


# ---------- combat ----------

func _shoot(p: Dictionary, origin: Vector3, dir: Vector3, seed_val: int, rtick: float) -> void:
	var w: Dictionary = Weapons.DATA[p.weapon]
	if state != "match" or not p.alive or _now < p.reload_until or (w.mag > 0 and p.ammo <= 0):
		return
	if not origin.is_finite() or not dir.is_finite() or dir.length_squared() < 0.25 or not is_finite(rtick):
		return
	if origin.distance_to(p.pos + EYE) > 2.5:
		return
	# Fire-rate limit with 0.2 s of slack for network jitter.
	if p.shot_time > _now + 0.2:
		return
	p.shot_time = maxf(p.shot_time, _now - 0.2) + w.interval
	if w.mag > 0:
		p.ammo -= 1
	_fire(p, origin, dir.normalized(), seed_val, rtick)


func _fire(p: Dictionary, origin: Vector3, dir: Vector3, seed_val: int, rtick: float) -> void:
	var w: Dictionary = Weapons.DATA[p.weapon]
	var reach: float = w.range
	var rt := clampf(rtick, tick_n - 10.0, float(tick_n))
	var grow := 0.45 if w.melee else 0.0   # melee is forgiving: it hits a fattened box
	var dmg := {}   # victim id -> total damage
	for d: Vector3 in Weapons.pellet_dirs(p.weapon, dir, seed_val):
		var to := origin + d * reach
		var best := Maps.ray_world(_map, origin, to)
		var victim := 0
		for id: int in players:
			var q: Dictionary = players[id]
			if q.team == p.team or not q.alive:
				continue
			var h := CROUCH_H if (q.flags & FLAG_CROUCH) != 0 else STAND_H
			var box := AABB(_pos_at(q, rt) - BOX_HALF, Vector3(0.8, h, 0.8)).grow(grow)
			var hit: Variant = box.intersects_segment(origin, to)
			if hit != null:
				var f: float = origin.distance_to(hit) / reach
				if f < best:
					best = f
					victim = id
		if victim != 0:
			dmg[victim] = dmg.get(victim, 0) + Weapons.damage_at(p.weapon, best * reach)
	for id: int in players:
		if id != p.id and not players[id].bot:
			send.call(id, "shot", [p.id, origin, dir, seed_val])
	for vid: int in dmg:
		var v: Dictionary = players[vid]
		if _now < v.protect_until or not v.alive:
			continue
		v.hp -= dmg[vid]
		if v.hp <= 0:
			_kill(v, p)
		else:
			_all("hit", [vid, v.hp, p.id])


# Where player q was at snapshot tick rt (the moment the shooter saw).
func _pos_at(q: Dictionary, rt: float) -> Vector3:
	var prev: Variant = null
	for h: Dictionary in _history:
		if not h.p.has(q.id):
			prev = null
			continue
		if h.t >= rt:
			if prev == null:
				return h.p[q.id]
			return (prev.p[q.id] as Vector3).lerp(h.p[q.id], (rt - prev.t) / (h.t - prev.t))
		prev = h
	return q.pos


func _kill(v: Dictionary, attacker: Dictionary) -> void:
	v.alive = false
	v.hp = 0
	v.deaths += 1
	v.respawn_at = _now + RESPAWN_DELAY
	v.protect_next = true
	var kid := 0
	var weapon := ""
	if not attacker.is_empty():
		attacker.kills += 1
		scores[attacker.team] += 1
		kid = attacker.id
		weapon = attacker.weapon
	_all("kill", [kid, v.id, weapon, scores.duplicate(), RESPAWN_DELAY])


# Practice bots: stand still and take a slow, inaccurate rifle shot at a visible enemy.
func _bot_think(b: Dictionary) -> void:
	if _now < b.think_at:
		return
	b.think_at = _now + _rng.randf_range(1.0, 1.8)
	for id: int in players:
		var q: Dictionary = players[id]
		if q.team == b.team or not q.alive or _now < q.protect_until:
			continue
		var from: Vector3 = b.pos + EYE
		var to: Vector3 = q.pos + Vector3(0, 1.0, 0)
		if from.distance_to(to) > 70.0 or Maps.ray_world(_map, from, to) < 1.0:
			continue
		var dir := (to - from).normalized()
		b.yaw = atan2(-dir.x, -dir.z)
		b.pitch = asin(dir.y)
		dir += Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))
		_fire(b, from, dir.normalized(), _rng.randi() & 0xFFFFFF, float(tick_n))
		return


# ---------- heal zone ----------

func _update_heal() -> void:
	if heal_pos == null:
		if _now >= _heal_at:
			heal_pos = _heal_spot()
			if heal_pos == null:
				_heal_at = _now + 2.0
			else:
				_all("heal", [heal_pos])
		return
	var hp_pos: Vector3 = heal_pos
	for id: int in players:
		var p: Dictionary = players[id]
		if not p.alive:
			continue
		var d: Vector3 = p.pos - hp_pos
		if Vector2(d.x, d.z).length() > HEAL_RADIUS or absf(d.y) > 1.5:
			continue
		if p.hp >= MAX_HP:
			if not p.bot and _now >= p.heal_msg_at:
				p.heal_msg_at = _now + 2.0
				send.call(id, "heal_full", [])
			continue
		p.hp = MAX_HP
		_all("heal_taken", [id, hp_pos, p.hp])
		_last_heal = hp_pos
		heal_pos = null
		_heal_at = _now + _rng.randf_range(HEAL_DELAY[0], HEAL_DELAY[1])
		return


# A random open-ground spot between the bases (never in a base, on a roof or under a platform).
func _heal_spot() -> Variant:
	var hx: float = _map.hx
	var hz: float = _map.hz
	for i in 60:
		var c := Vector3(_rng.randf_range(-hx + 4.0, hx - 4.0), 0, _rng.randf_range(-(hz - 20.0), hz - 20.0))
		if c.distance_to(_last_heal) < 15.0:
			continue
		var ok := true
		for o: Vector3 in [Vector3.ZERO, Vector3(1.3, 0, 0), Vector3(-1.3, 0, 0), Vector3(0, 0, 1.3), Vector3(0, 0, -1.3)]:
			var x := c.x + o.x
			var z := c.z + o.z
			if absf(30.0 - 31.0 * Maps.ray_world(_map, Vector3(x, 30, z), Vector3(x, -1, z))) > 0.05:
				ok = false
				break
		if ok:
			return c
	return null
