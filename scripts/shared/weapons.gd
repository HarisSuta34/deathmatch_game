extends RefCounted
# Weapon stats shared by client and server.
# damage is per pellet; falloff = [start_m, end_m, min_damage] (linear).

const LIST := ["rifle", "sniper", "shotgun"]
const DATA := {
	"rifle": {
		"name": "Assault Rifle", "desc": "Automatic, medium damage",
		"damage": 18, "interval": 0.1, "mag": 30, "reload": 1.8, "pellets": 1,
		"spread": 0.012, "auto": true, "zoom_fov": 50.0, "range": 250.0,
		"falloff": [40.0, 120.0, 10], "kick": 0.006,
	},
	"sniper": {
		"name": "Sniper", "desc": "High damage, slow, scope",
		"damage": 90, "interval": 1.4, "mag": 5, "reload": 2.6, "pellets": 1,
		"spread": 0.0, "auto": false, "zoom_fov": 14.0, "range": 400.0,
		"falloff": [400.0, 401.0, 90], "kick": 0.05,
	},
	"shotgun": {
		"name": "Shotgun", "desc": "9 pellets, deadly up close",
		"damage": 13, "interval": 0.9, "mag": 6, "reload": 2.2, "pellets": 9,
		"spread": 0.075, "auto": false, "zoom_fov": 60.0, "range": 60.0,
		"falloff": [7.0, 30.0, 3], "kick": 0.04,
	},
}


# Deterministic pellet directions: client (for tracers) and server (for hits)
# compute the same spread from the same seed.
static func pellet_dirs(weapon: String, dir: Vector3, seed_val: int) -> Array:
	var d: Dictionary = DATA[weapon]
	var spread: float = d.spread
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var right := dir.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var out := []
	for i: int in d.pellets:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spread
		out.append((dir + right * (cos(a) * r) + up * (sin(a) * r)).normalized())
	return out


static func damage_at(weapon: String, dist: float) -> int:
	var d: Dictionary = DATA[weapon]
	var f: Array = d.falloff
	var t := clampf((dist - f[0]) / (f[1] - f[0]), 0.0, 1.0)
	return roundi(lerpf(d.damage, f[2], t))
