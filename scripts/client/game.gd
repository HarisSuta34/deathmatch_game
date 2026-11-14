extends Node3D
# Client-side match world: map, local player, other players (interpolated), effects, HUD.

const Maps = preload("res://scripts/shared/maps.gd")
const Weapons = preload("res://scripts/shared/weapons.gd")
const Player = preload("res://scripts/client/player.gd")
const Avatar = preload("res://scripts/client/avatar.gd")
const Hud = preload("res://scripts/client/hud.gd")

const TICK_RATE := 20.0
const INTERP_TICKS := 2.0   # render other players 100 ms in the past

var map: Dictionary
var player: CharacterBody3D
var hud: CanvasLayer
var my_id := 0
var info := {}       # id -> {nick, team, kills, deaths, weapon, alive}
var avatars := {}    # id -> Avatar (other players)
var scores := [0, 0]
var time_left := 0.0
var protected := false
var _snaps := []     # [{t, ids, data}]
var _est_tick := 0.0
var _send_acc := 0.0
var _tracer_mat := StandardMaterial3D.new()


# a = match_start args: [map_id, time_left, [[id, nick, team], ...], warmup_seconds]
func setup(a: Array) -> void:
	my_id = Net.my_id
	time_left = a[1]
	_build_world(a[0])
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1, 0.9, 0.5)
	for e: Array in a[2]:
		info[e[0]] = {"nick": e[1], "team": e[2], "kills": 0, "deaths": 0, "weapon": "rifle", "alive": false}
		if e[0] != my_id:
			var av := Avatar.new()
			add_child(av)
			av.setup(e[2], e[1], true)
			av.visible = false
			av.position.y = -500.0
			avatars[e[0]] = av
	var me: Dictionary = info[my_id]
	player = Player.new()
	add_child(player)
	player.avatar.setup(me.team, me.nick, false)
	var sp: Array = Maps.spawn_point(map, me.team, 2)
	player.global_position = sp[0]
	player.yaw = sp[1]
	player.fired.connect(_on_fired)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.show_loadout(a[3])
	Net.message.connect(_on_msg)


func pick(w: String) -> void:
	Net.send("pick", [w])


func nick(id: int) -> String:
	return info[id].nick if info.has(id) else "?"


func _on_msg(msg: String, a: Array) -> void:
	match msg:
		"spawn":
			var id: int = a[0]
			if not info.has(id):
				return
			info[id].weapon = a[3]
			info[id].alive = true
			if id == my_id:
				player.respawn(a[1], a[2], a[3])
				hud.hide_loadout()
			else:
				avatars[id].set_weapon(a[3])
		"snap":
			_snaps.append({"t": a[0], "ids": a[2], "data": a[3]})
			if _snaps.size() > 40:
				_snaps.pop_front()
			time_left = a[1]
			# Keep a smooth local estimate of the server tick.
			var err: float = a[0] - _est_tick
			_est_tick = float(a[0]) if absf(err) > 4.0 else _est_tick + err * 0.1
		"shot":
			if info.has(a[0]) and a[0] != my_id:
				_tracers(a[0], a[1], a[2], a[3])
		"hit":
			if a[0] == my_id:
				player.hp = a[1]
				hud.damage_flash()
			if a[2] == my_id:
				hud.hit_marker(false)
		"kill":
			var k: int = a[0]
			var v: int = a[1]
			scores = a[3]
			if info.has(k):
				info[k].kills += 1
			if info.has(v):
				info[v].deaths += 1
				info[v].alive = false
			hud.add_kill(k, v, a[2])
			if v == my_id:
				player.die()
				hud.damage_flash()
				hud.center_msg("Killed by %s" % nick(k) if k != 0 else "You fell", 3.0)
				hud.show_loadout(a[4])
			if k == my_id:
				hud.hit_marker(true)
		"left":
			if avatars.has(a[0]):
				avatars[a[0]].queue_free()
				avatars.erase(a[0])
			info.erase(a[0])
		"match_end":
			player.die()
			hud.show_results(a[0], a[1], a[2], a[3])


func _process(delta: float) -> void:
	_est_tick += delta * TICK_RATE
	_interpolate(delta)
	if player.active:
		_send_acc += delta
		if _send_acc >= 1.0 / TICK_RATE:
			_send_acc = 0.0
			var f := (4 if player.moving else 0) | (8 if player.sprinting else 0)
			Net.send("state", [player.global_position, player.yaw, player.pitch, f])


# Place every other player between the two snapshots around the render time.
func _interpolate(delta: float) -> void:
	if _snaps.is_empty():
		return
	var rt := _est_tick - INTERP_TICKS
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[0]
	for i in range(_snaps.size() - 1, -1, -1):
		if _snaps[i].t <= rt:
			a = _snaps[i]
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var k := 0.0
	if b.t > a.t:
		k = clampf((rt - a.t) / (b.t - a.t), 0.0, 1.0)
	var ids: PackedInt32Array = b.ids
	var db: PackedFloat32Array = b.data
	var da: PackedFloat32Array = a.data
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.24) < 0.14
	for j in ids.size():
		var id := ids[j]
		var o := j * 6
		var flags := int(db[o + 5])
		if id == my_id:
			protected = (flags & 2) != 0
			continue
		if not avatars.has(id):
			continue
		var av: Node3D = avatars[id]
		if (flags & 1) == 0 or not info[id].alive:
			av.visible = false
			av.position.y = -500.0
			continue
		av.visible = (flags & 2) == 0 or blink   # blink while spawn-protected
		var pb := Vector3(db[o], db[o + 1], db[o + 2])
		var pa := pb
		var ya := db[o + 3]
		var xa := db[o + 4]
		var i := (a.ids as PackedInt32Array).find(id)
		if i >= 0 and (int(da[i * 6 + 5]) & 1) != 0:
			var prev := Vector3(da[i * 6], da[i * 6 + 1], da[i * 6 + 2])
			if prev.distance_to(pb) < 6.0:   # bigger jump = respawn teleport, don't slide
				pa = prev
				ya = da[i * 6 + 3]
				xa = da[i * 6 + 4]
		av.position = pa.lerp(pb, k)
		av.rotation.y = lerp_angle(ya, db[o + 3], k)
		av.animate(delta, (flags & 4) != 0, (flags & 8) != 0, lerpf(xa, db[o + 4], k))


func _on_fired(origin: Vector3, dir: Vector3, seed_val: int) -> void:
	Net.send("shoot", [origin, dir, seed_val, _est_tick - INTERP_TICKS])
	_tracers(my_id, origin, dir, seed_val)


func _tracers(id: int, origin: Vector3, dir: Vector3, seed_val: int) -> void:
	var wname: String = info[id].weapon
	var av: Node3D = player.avatar if id == my_id else avatars.get(id)
	if av == null:
		return
	var from: Vector3 = av.muzzle()
	var space := get_world_3d().direct_space_state
	var reach: float = Weapons.DATA[wname].range
	for d: Vector3 in Weapons.pellet_dirs(wname, dir, seed_val):
		var to := origin + d * reach
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, to, 3))
		if hit:
			to = hit.position
		var length := from.distance_to(to)
		if length < 0.6:
			continue
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.04, 0.04, length)
		mesh.material = _tracer_mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
		mi.look_at_from_position((from + to) * 0.5, to, up)
		get_tree().create_timer(0.07).timeout.connect(mi.queue_free)


func _build_world(map_id: int) -> void:
	map = Maps.get_map(map_id)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	add_child(Maps.build(map))
