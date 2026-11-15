extends SceneTree
# Logic test for the room simulation (no graphics, no network).
# Run: tools\godot.ps1 --headless --path . -s tools/test_room.gd

const Weapons = preload("res://scripts/shared/weapons.gd")

var log := []


func _init() -> void:
	var Room: GDScript = load("res://scripts/shared/room.gd")
	var r: RefCounted = Room.new()
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
	var teams := [0, 0]
	for id: int in r.players:
		teams[r.players[id].team] += 1
	_expect("teams equal", teams == [2, 2])
	for i in 130:
		r.tick(0.05)
	var a: Dictionary
	var b: Dictionary
	for id: int in r.players:
		if r.players[id].team == 0:
			a = r.players[id]
		else:
			b = r.players[id]
	_expect("spawned in bases", a.alive and b.alive and a.pos.z < -30 and b.pos.z > 30)
	r.handle(a.id, "pick", ["sniper"])
	r.handle(a.id, "state", [Vector3(10, 0.1, -10), 0.0, 0.0, 0])
	r.handle(b.id, "state", [Vector3(10, 0.1, -20), 0.0, 0.0, 0])
	var origin := Vector3(10, 1.6, -10)
	var dir := (Vector3(10, 1.1, -20) - origin).normalized()
	r.handle(a.id, "shoot", [origin, dir, 1, float(r.tick_n)])
	_expect("spawn protection blocks damage", b.hp == 100)
	for i in 220:
		r.tick(0.05)
	for i in 10:
		r.handle(a.id, "shoot", [origin, dir, i, float(r.tick_n)])
		r.tick(0.1)
	_expect("rifle killed target", not b.alive and r.scores == [1, 0] and a.kills == 1)
	var before: int = a.ammo
	for i in 10:
		r.handle(a.id, "shoot", [origin, dir, i, float(r.tick_n)])
	_expect("fire rate limited", before - a.ammo <= 5)   # small burst allowance for network jitter
	for i in 130:
		r.tick(0.05)
	_expect("respawned", b.alive and b.hp == 100)
	r.handle(a.id, "state", [Vector3(0, 0.1, -10), 0.0, 0.0, 0])
	r.handle(b.id, "state", [Vector3(0, 0.1, 10), 0.0, 0.0, 0])
	for i in 220:
		r.tick(0.05)
	_expect("clear shot hits", _dmg(r, a, b, Vector3(10, 0.1, -10), Vector3(10, 0.1, -20)) > 0)
	r.handle(a.id, "pick", ["knife"])
	_expect("sniper weak up close, strong far", Weapons.damage_at("sniper", 5.0) < 70 and Weapons.damage_at("sniper", 60.0) >= 100)
	_expect("shotgun strong close, weak far", Weapons.damage_at("shotgun", 3.0) * 10 > 100 and Weapons.damage_at("shotgun", 40.0) * 10 < 30)
	b.hp = 100
	r.handle(a.id, "state", [Vector3(0, 0.1, -10), 0.0, 0.0, 0])
	r.handle(b.id, "state", [Vector3(0, 0.1, 10), 0.0, 0.0, 0])
	r.tick(0.2)
	r.handle(a.id, "shoot", [Vector3(0, 1.6, -10), Vector3(0, 0, 1), 1, float(r.tick_n)])
	_expect("wall blocks shot", b.hp == 100)
	r.remove_player(b.id)
	_expect("match continues uneven", r.state == "match" and r.players.size() == 3)
	for i in 6100:
		r.tick(0.05)
	_expect("match ended with winner red", _last("match_end")[1] == 0)
	for i in 220:
		r.tick(0.05)
	_expect("back to lobby", r.state == "lobby")
	# Every spawn slot on every map must be free standing room on the base floor.
	var Maps: GDScript = load("res://scripts/shared/maps.gd")
	for m: int in Maps.COUNT:
		var map: Dictionary = Maps.get_map(m)
		var ok := true
		for team in 2:
			for n in 10:
				var p: Vector3 = Maps.spawn_point(map, team, n)[0]
				var f: float = Maps.ray_world(map, p + Vector3(0, 9, 0), p - Vector3(0, 1, 0))
				ok = ok and absf((9.0 - 10.0 * f) + 0.1) < 0.2
		_expect("map %d spawns clear" % m, ok)
	quit()


# Moves a and b, lets a fire once at b, returns the damage dealt.
func _dmg(r: RefCounted, a: Dictionary, b: Dictionary, pa: Vector3, pb: Vector3) -> int:
	r.handle(a.id, "state", [pa, 0.0, 0.0, 0])
	r.handle(b.id, "state", [pb, 0.0, 0.0, 0])
	r.tick(0.5)
	var before: int = b.hp
	var origin := pa + Vector3(0, 1.5, 0)
	r.handle(a.id, "shoot", [origin, (pb + Vector3(0, 1, 0) - origin).normalized(), 1, float(r.tick_n)])
	return before - b.hp


func _last(msg: String) -> Array:
	for i in range(log.size() - 1, -1, -1):
		if log[i][1] == msg:
			return log[i][2]
	return []


func _expect(what: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
