extends RefCounted
# Weapon stats and blocky models, shared by client and server.
# damage is per pellet; falloff = [start_m, end_m, damage_at_end] (linear between).
# mag 0 = no ammo needed (melee).

const LIST := ["rifle", "sniper", "shotgun", "knife"]
const DATA := {
	"rifle": {
		"name": "Assault Rifle", "desc": "Automatic, 30 rounds, good range",
		"damage": 17, "interval": 0.1, "mag": 30, "reload": 1.8, "pellets": 1,
		"spread": 0.008, "auto": true, "zoom_fov": 50.0, "range": 300.0,
		"falloff": [55.0, 140.0, 12], "kick": 0.006, "muzzle": 0.85, "speed": 1.0, "melee": false,
	},
	"sniper": {
		"name": "Sniper", "desc": "One-shot kill at long range, scope",
		"damage": 60, "interval": 1.5, "mag": 5, "reload": 2.3, "pellets": 1,
		"spread": 0.0, "auto": false, "zoom_fov": 14.0, "range": 400.0,
		"falloff": [10.0, 30.0, 100], "kick": 0.05, "muzzle": 1.4, "speed": 1.0, "melee": false,
	},
	"shotgun": {
		"name": "Shotgun", "desc": "10 pellets, deadly up close",
		"damage": 13, "interval": 0.9, "mag": 6, "reload": 2.1, "pellets": 10,
		"spread": 0.08, "auto": false, "zoom_fov": 60.0, "range": 50.0,
		"falloff": [6.0, 24.0, 2], "kick": 0.04, "muzzle": 0.85, "speed": 1.0, "melee": false,
	},
	"knife": {
		"name": "Bulgarian Special Knife", "desc": "Melee, 2 hits, move faster",
		"damage": 60, "interval": 0.45, "mag": 0, "reload": 0.0, "pellets": 1,
		"spread": 0.0, "auto": false, "zoom_fov": 75.0, "range": 2.8,
		"falloff": [10.0, 11.0, 60], "kick": 0.0, "muzzle": 0.5, "speed": 1.15, "melee": true,
	},
}
const SNIPER_HIP_SPREAD := 0.05   # unscoped sniper shots are inaccurate

const METAL := Color(0.2, 0.2, 0.23)
const DARK := Color(0.08, 0.08, 0.1)
const WOOD := Color(0.55, 0.36, 0.2)
const OLIVE := Color(0.3, 0.38, 0.22)
const STEEL := Color(0.8, 0.82, 0.86)
const LENS := Color(0.3, 0.55, 0.9)

# Models as boxes [size, position, color]; grip at the origin, barrel towards -Z.
# The loadout icons are drawn from the same boxes (side view).
const PARTS := {
	"rifle": [
		[Vector3(0.09, 0.14, 0.5), Vector3(0, 0.02, -0.15), METAL],
		[Vector3(0.05, 0.05, 0.4), Vector3(0, 0.04, -0.62), DARK],
		[Vector3(0.09, 0.1, 0.26), Vector3(0, 0.02, -0.5), WOOD],
		[Vector3(0.07, 0.12, 0.32), Vector3(0, -0.01, 0.26), WOOD],
		[Vector3(0.06, 0.24, 0.1), Vector3(0, -0.16, -0.2), DARK],
		[Vector3(0.06, 0.14, 0.07), Vector3(0, -0.1, 0.03), DARK],
		[Vector3(0.03, 0.06, 0.03), Vector3(0, 0.1, -0.78), DARK],
	],
	"sniper": [
		[Vector3(0.08, 0.12, 0.7), Vector3(0, 0.02, -0.15), OLIVE],
		[Vector3(0.04, 0.04, 0.8), Vector3(0, 0.04, -0.9), DARK],
		[Vector3(0.07, 0.07, 0.12), Vector3(0, 0.04, -1.34), DARK],
		[Vector3(0.08, 0.17, 0.36), Vector3(0, -0.02, 0.36), OLIVE],
		[Vector3(0.07, 0.08, 0.38), Vector3(0, 0.15, -0.2), DARK],
		[Vector3(0.09, 0.1, 0.05), Vector3(0, 0.15, -0.41), LENS],
		[Vector3(0.02, 0.22, 0.02), Vector3(0.05, -0.12, -0.72), DARK],
		[Vector3(0.02, 0.22, 0.02), Vector3(-0.05, -0.12, -0.72), DARK],
		[Vector3(0.06, 0.1, 0.12), Vector3(0, -0.09, -0.15), DARK],
		[Vector3(0.06, 0.14, 0.07), Vector3(0, -0.1, 0.05), DARK],
	],
	"shotgun": [
		[Vector3(0.1, 0.15, 0.36), Vector3(0, 0.02, -0.1), METAL],
		[Vector3(0.07, 0.07, 0.56), Vector3(0, 0.06, -0.55), DARK],
		[Vector3(0.06, 0.06, 0.46), Vector3(0, -0.02, -0.5), METAL],
		[Vector3(0.12, 0.11, 0.2), Vector3(0, -0.03, -0.45), WOOD],
		[Vector3(0.09, 0.15, 0.32), Vector3(0, -0.03, 0.24), WOOD],
		[Vector3(0.06, 0.13, 0.07), Vector3(0, -0.1, 0.04), WOOD],
	],
}
const BRASS := Color(0.85, 0.65, 0.25)
const EDGE := Color(0.97, 0.98, 1.0)

static var _knife: Array


static func parts(w: String) -> Array:
	return _knife_parts() if w == "knife" else PARTS[w]


# Knife: handle with rings and pommel, brass guard, and a blade whose spine is straight
# while the cutting edge curves up to a sharp point (built from thin slices).
static func _knife_parts() -> Array:
	if _knife.is_empty():
		var l := []
		l.append([Vector3(0.05, 0.07, 0.17), Vector3(0, -0.005, 0.01), Color(0.3, 0.18, 0.1)])
		l.append([Vector3(0.058, 0.078, 0.022), Vector3(0, -0.005, 0.05), DARK])
		l.append([Vector3(0.058, 0.078, 0.022), Vector3(0, -0.005, -0.03), DARK])
		l.append([Vector3(0.062, 0.085, 0.035), Vector3(0, -0.005, 0.105), BRASS])
		l.append([Vector3(0.07, 0.15, 0.03), Vector3(0, 0.0, -0.088), BRASS])
		var spine := 0.045
		var full := 0.095
		var n := 12
		var length := 0.44
		var dz := length / n
		for i in n:
			var t := (i + 0.5) / n
			var h := maxf(full * sqrt(maxf(0.0, 1.0 - pow(t, 2.2))), 0.012)
			var z := -0.103 - dz * (i + 0.5)
			var edge := minf(0.014, h * 0.4)
			l.append([Vector3(0.022, h - edge, dz), Vector3(0, spine - (h - edge) * 0.5, z), STEEL])
			l.append([Vector3(0.018, edge, dz), Vector3(0, spine - h + edge * 0.5, z), EDGE])
			if t < 0.6:
				l.append([Vector3(0.026, 0.012, dz), Vector3(0, spine - 0.022, z), Color(0.55, 0.57, 0.62)])
		_knife = l
	return _knife


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
