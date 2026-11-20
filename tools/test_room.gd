extends SceneTree
# Logic test for the room simulation (no graphics, no network).
# Run: tools\godot.ps1 --headless --path . -s tools/test_room.gd   (every line should say PASS)

const Weapons = preload("res://scripts/shared/weapons.gd")
const Maps = preload("res://scripts/shared/maps.gd")

var log := []
var r: RefCounted


func _init() -> void:
	r = load("res://scripts/shared/room.gd").new()
	r.send = func(id: int, msg: String, args: Array) -> void:
		if msg != "snap":
			log.append([id, msg, args])
	for i in 3:
		r.add_player(10 + i, "P%d" % i)
	r.handle(10, "start", [])
	_expect("odd count refused", _last("error") == [r.START_ERROR])
	r.add_player(13, "P3")
	r.handle(11, "start", [])
	_expect("non-host cannot start", r.state == "lobby")
	r.handle(10, "set_opt", [0, 5])
	r.handle(10, "start", [])
	_expect("match started", r.state == "match" and r.minutes == 5)
	var team_of := {}
	var teams := [[], []]
	for id: int in r.players:
		teams[r.players[id].team].append(r.players[id])
	_expect("teams equal", teams[0].size() == 2 and teams[1].size() == 2)
	_wait(r.WARMUP + 0.5)
	var a: Dictionary = teams[0][0]
	var mate: Dictionary = teams[0][1]
	var b: Dictionary = teams[1][0]
	_expect("spawned in bases", a.alive and b.alive and a.pos.z < -30 and b.pos.z > 30)
	_expect("no spawn protection at match start", _dmg(a, b, Vector3(10, 0.1, -10), Vector3(10, 0.1, -20)) > 0)
	_expect("no friendly fire", _dmg(a, mate, Vector3(10, 0.1, -10), Vector3(10, 0.1, -20)) == 0)
	for i in 10:
		_shoot(a, b)
		r.tick(0.1)
	_expect("rifle killed target", not b.alive and r.scores == [1, 0] and a.kills == 1)
	var before: int = a.ammo
	for i in 10:
		_shoot(a, b)
	_expect("fire rate limited", before - a.ammo <= 5)
	_wait(r.RESPAWN_DELAY + 0.2)
	_expect("respawned after 10 s", b.alive and b.hp == 100)
	_shoot(b, a)   # shooting does not end the protection
	_expect("respawn protection blocks damage", _dmg(a, b, Vector3(10, 0.1, -10), Vector3(10, 0.1, -20)) == 0)
	_wait(r.SPAWN_PROTECT - 2.5)   # about 8.9 s after the respawn
	_expect("protection lasts the full time", _dmg(a, b, Vector3(10, 0.1, -10), Vector3(10, 0.1, -20)) == 0)
	_wait(1.0)
	_expect("protection ends after 10 s", _dmg(a, b, Vector3(10, 0.1, -10), Vector3(10, 0.1, -20)) > 0)
	b.hp = 100
	# Crouching lowers the hitbox: a shot at chest height of a standing player misses.
	r.handle(b.id, "state", [Vector3(10, 0.1, -20), 0.0, 0.0, r.FLAG_CROUCH])
	r.handle(a.id, "state", [Vector3(10, 0.1, -10), 0.0, 0.0, 0])
	r.tick(0.6)
	r.handle(a.id, "shoot", [Vector3(10, 1.6, -10), Vector3(0, 0, -1), 1, float(r.tick_n)])
	_expect("shot over a crouched player misses", b.hp == 100)
	r.handle(b.id, "state", [Vector3(10, 0.1, -20), 0.0, 0.0, 0])
	r.tick(0.6)
	r.handle(a.id, "shoot", [Vector3(10, 1.6, -10), Vector3(0, 0, -1), 1, float(r.tick_n)])
	_expect("same shot hits when standing", b.hp < 100)
	_expect("sniper weak up close, strong far", Weapons.damage_at("sniper", 5.0) < 70 and Weapons.damage_at("sniper", 60.0) >= 100)
	_expect("shotgun strong close, weak far", Weapons.damage_at("shotgun", 3.0) * 10 > 100 and Weapons.damage_at("shotgun", 40.0) * 10 < 30)
	b.hp = 100
	r.handle(a.id, "state", [Vector3(0, 0.1, -10), 0.0, 0.0, 0])
	r.handle(b.id, "state", [Vector3(0, 0.1, 10), 0.0, 0.0, 0])
	r.tick(0.6)
	r.handle(a.id, "shoot", [Vector3(0, 1.6, -10), Vector3(0, 0, 1), 1, float(r.tick_n)])
	_expect("wall blocks shot", b.hp == 100)
	# Heal zone.
	_wait(12.0)
	_expect("heal zone appears", r.heal_pos != null and _last("heal").size() == 1)
	var hp_pos: Vector3 = r.heal_pos
	var hz: float = Maps.get_map(0).hz
	_expect("heal zone not in a base", absf(hp_pos.z) < hz - 17.0)
	a.hp = 100
	r.handle(a.id, "state", [hp_pos, 0.0, 0.0, 0])
	log.clear()
	r.tick(0.1)
	_expect("full health cannot pick up", r.heal_pos != null and _last("heal_full") == [] and log.any(func(e: Array) -> bool: return e[1] == "heal_full" and e[0] == a.id))
	a.hp = 40
	r.tick(0.1)
	_expect("heal restores full health", a.hp == 100 and r.heal_pos == null and _last("heal_taken")[0] == a.id)
	_wait(26.0)
	_expect("heal reappears elsewhere", r.heal_pos != null and (r.heal_pos as Vector3).distance_to(hp_pos) >= 15.0)
	var ok := true
	for m: int in Maps.COUNT:
		r._map = Maps.get_map(m)
		for i in 40:
			var s: Variant = r._heal_spot()
			ok = ok and s != null and absf((s as Vector3).z) < float(r._map.hz) - 17.0
	r._map = Maps.get_map(0)
	_expect("heal spots valid on all maps", ok)
	r.remove_player(b.id)
	_expect("match continues uneven", r.state == "match" and r.players.size() == 3)
	_wait(310.0)
	_expect("match ended", _last("match_end").size() == 4)
	_wait(11.0)
	_expect("back to lobby", r.state == "lobby")
	# Every spawn slot on every map must be free standing room on the base floor.
	for m: int in Maps.COUNT:
		var map: Dictionary = Maps.get_map(m)
		var good := true
		for team in 2:
			for n in 10:
				var p: Vector3 = Maps.spawn_point(map, team, n)[0]
				var f: float = Maps.ray_world(map, p + Vector3(0, 9, 0), p - Vector3(0, 1, 0))
				good = good and absf((9.0 - 10.0 * f) + 0.1) < 0.2
		_expect("map %d spawns clear" % m, good)
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds / 0.05):
		r.tick(0.05)


func _shoot(from: Dictionary, to: Dictionary) -> void:
	var origin: Vector3 = from.pos + Vector3(0, 1.5, 0)
	r.handle(from.id, "shoot", [origin, (to.pos + Vector3(0, 1, 0) - origin).normalized(), 1, float(r.tick_n)])


# Moves a and b, lets a fire once at b, returns the damage dealt.
func _dmg(a: Dictionary, b: Dictionary, pa: Vector3, pb: Vector3) -> int:
	r.handle(a.id, "state", [pa, 0.0, 0.0, 0])
	r.handle(b.id, "state", [pb, 0.0, 0.0, 0])
	r.tick(0.6)
	var before: int = b.hp
	_shoot(a, b)
	return before - b.hp


func _last(msg: String) -> Array:
	for i in range(log.size() - 1, -1, -1):
		if log[i][1] == msg:
			return log[i][2]
	return []


func _expect(what: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
