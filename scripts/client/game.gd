extends Node3D
# Client-side match world: map, local player, other players (interpolated), effects, HUD.

signal leave   # the player pressed "Leave Match"

const Maps = preload("res://scripts/shared/maps.gd")
const Weapons = preload("res://scripts/shared/weapons.gd")
const Player = preload("res://scripts/client/player.gd")
const Avatar = preload("res://scripts/client/avatar.gd")
const Hud = preload("res://scripts/client/hud.gd")

const TICK_RATE := 20.0
const INTERP_TICKS := 2.0   # render other players 100 ms in the past
# Snapshot flag bits (bit0 alive and bit1 protected are set by the server).
const F_ALIVE := 1
const F_PROTECTED := 2
const F_MOVING := 4
const F_SPRINT := 8
const F_RELOAD := 16
const F_CROUCH := 32
const F_AIR := 64

var map: Dictionary
var map_id := 0
var player: CharacterBody3D
var hud: CanvasLayer
var my_id := 0
var my_team := 0
var info := {}       # id -> {nick, team, kills, deaths, weapon, alive}
var avatars := {}    # id -> Avatar (other players)
var scores := [0, 0]
var time_left := 0.0
var protected := false
var shield_left := 0.0
var _snaps := []     # [{t, ids, data}]
var _est_tick := 0.0
var _send_acc := 0.0
var _tracer_mat := StandardMaterial3D.new()
var _heal: Node3D


# a = match_start args: [map_id, time_left, [[id, nick, team], ...], intro_seconds]
func setup(a: Array) -> void:
	my_id = Net.my_id
	map_id = a[0]
	time_left = a[1]
	_build_world(a[0])
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1, 0.9, 0.5)
	for e: Array in a[2]:
		info[e[0]] = {"nick": e[1], "team": e[2], "kills": 0, "deaths": 0, "weapon": "rifle", "alive": false}
	my_team = info[my_id].team
	for id: int in info:
		if id == my_id:
			continue
		var av := Avatar.new()
		add_child(av)
		av.setup(info[id].team, info[id].nick, true, info[id].team == my_team)
		av.visible = false
		av.position.y = -500.0
		avatars[id] = av
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
	hud.show_intro(a[3])
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
				shield_left = a[4] if a.size() > 4 else 0.0
				hud.hide_overlay()
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
			_flash(a[0])
			if a[0] == my_id:
				player.hp = a[1]
				hud.damage_flash()
				Sfx.play("hurt", -4.0)
			if a[2] == my_id:
				hud.hit_marker(false)
				Sfx.play("hit", -6.0)
		"kill":
			var k: int = a[0]
			var v: int = a[1]
			scores = a[3]
			_flash(v)
			if info.has(k):
				info[k].kills += 1
			if info.has(v):
				info[v].deaths += 1
				info[v].alive = false
			hud.add_kill(k, v, a[2])
			if v == my_id:
				player.die()
				shield_left = 0.0
				hud.damage_flash()
				Sfx.play("hurt")
				hud.show_death(k, a[4])
			if k == my_id:
				hud.hit_marker(true)
				Sfx.play("kill", -4.0)
		"left":
			if avatars.has(a[0]):
				avatars[a[0]].queue_free()
				avatars.erase(a[0])
			info.erase(a[0])
		"heal":
			_show_heal(a[0])
		"heal_taken":
			_heal_taken(a[0], a[1], a[2])
		"heal_full":
			hud.center_msg("Health already full", 1.6)
		"match_end":
			time_left = 0.0
			scores = a[0]
			player.die()
			if _heal:
				_heal.queue_free()
				_heal = null
			hud.show_results(a[0], a[1], a[2], a[3])


func _flash(id: int) -> void:
	if id == my_id:
		player.avatar.flash()
	elif avatars.has(id):
		avatars[id].flash()


func _process(delta: float) -> void:
	_est_tick += delta * TICK_RATE
	shield_left = maxf(0.0, shield_left - delta)
	_interpolate(delta)
	if player.active:
		_send_acc += delta
		if _send_acc >= 1.0 / TICK_RATE:
			_send_acc = 0.0
			var f := (F_MOVING if player.moving else 0) | (F_SPRINT if player.sprinting else 0) \
				| (F_RELOAD if player.reload_left > 0.0 else 0) | (F_CROUCH if player.crouching else 0) \
				| (F_AIR if player.airborne else 0)
			Net.send("state", [player.global_position, player.yaw, player.pitch, f])
	# Keep name tags readable at a distance.
	var cam_pos: Vector3 = player.cam.global_position
	for id: int in avatars:
		var av: Node3D = avatars[id]
		if av.visible and av.tag:
			av.tag.scale = Vector3.ONE * clampf(cam_pos.distance_to(av.position) / 14.0, 1.0, 3.5)
	if _heal:
		_heal.get_child(0).position.y = 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.15
		_heal.get_child(0).rotation.y += delta * 1.5


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
	var dt: float = (b.t - a.t) / TICK_RATE
	if b.t > a.t:
		k = clampf((rt - a.t) / (b.t - a.t), 0.0, 1.0)
	var ids: PackedInt32Array = b.ids
	var db: PackedFloat32Array = b.data
	var da: PackedFloat32Array = a.data
	for j in ids.size():
		var id := ids[j]
		var o := j * 6
		var flags := int(db[o + 5])
		if id == my_id:
			protected = (flags & F_PROTECTED) != 0
			player.avatar.set_shield(protected and player.active)
			continue
		if not avatars.has(id):
			continue
		var av: Node3D = avatars[id]
		if (flags & F_ALIVE) == 0 or not info[id].alive:
			av.visible = false
			av.position.y = -500.0
			continue
		av.visible = true
		av.set_shield((flags & F_PROTECTED) != 0)
		var pb := Vector3(db[o], db[o + 1], db[o + 2])
		var pa := pb
		var ya := db[o + 3]
		var xa := db[o + 4]
		var i := (a.ids as PackedInt32Array).find(id)
		if i >= 0 and (int(da[i * 6 + 5]) & F_ALIVE) != 0:
			var prev := Vector3(da[i * 6], da[i * 6 + 1], da[i * 6 + 2])
			if prev.distance_to(pb) < 6.0:   # bigger jump = respawn teleport, don't slide
				pa = prev
				ya = da[i * 6 + 3]
				xa = da[i * 6 + 4]
		var vel := (pb - pa) / dt if dt > 0.0 else Vector3.ZERO
		av.position = pa.lerp(pb, k)
		av.rotation.y = lerp_angle(ya, db[o + 3], k)
		av.animate(delta, vel, (flags & F_SPRINT) != 0, lerpf(xa, db[o + 4], k),
			(flags & F_RELOAD) != 0, (flags & F_CROUCH) != 0, (flags & F_AIR) != 0)


func _on_fired(origin: Vector3, dir: Vector3, seed_val: int) -> void:
	Net.send("shoot", [origin, dir, seed_val, _est_tick - INTERP_TICKS])
	_tracers(my_id, origin, dir, seed_val)


func _tracers(id: int, origin: Vector3, dir: Vector3, seed_val: int) -> void:
	var wname: String = info[id].weapon
	var av: Node3D = player.avatar if id == my_id else avatars.get(id)
	if av == null:
		return
	if id == my_id:
		Sfx.play("shot_" + wname, -3.0)
	else:
		Sfx.play_at("shot_" + wname, av.position + Vector3(0, 1.4, 0), self, 3.0)
		av.shoot_anim()
	if Weapons.DATA[wname].melee:
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


# ---------- heal zone ----------

func _unlit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# Green glowing field with a white cross on the ground and a floating, spinning cross above.
func _show_heal(pos: Vector3) -> void:
	if _heal:
		_heal.queue_free()
	_heal = Node3D.new()
	_heal.position = pos
	add_child(_heal)
	var floating := Node3D.new()
	_heal.add_child(floating)   # child 0: animated in _process
	var white := _unlit(Color(1, 1, 1))
	var green := _unlit(Color(0.2, 1.0, 0.35))
	_box(floating, Vector3(0.75, 0.25, 0.25), Vector3.ZERO, white)
	_box(floating, Vector3(0.25, 0.75, 0.25), Vector3.ZERO, white)
	_box(floating, Vector3(0.85, 0.35, 0.2), Vector3.ZERO, green)
	_box(floating, Vector3(0.35, 0.85, 0.2), Vector3.ZERO, green)
	_box(_heal, Vector3(2.8, 0.05, 2.8), Vector3(0, 0.03, 0), _unlit(Color(0.2, 1.0, 0.35, 0.45)))
	_box(_heal, Vector3(1.8, 0.07, 0.5), Vector3(0, 0.05, 0), white)
	_box(_heal, Vector3(0.5, 0.07, 1.8), Vector3(0, 0.05, 0), white)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.4)
	light.light_energy = 1.5
	light.omni_range = 4.0
	light.position.y = 1.0
	_heal.add_child(light)


func _heal_taken(id: int, pos: Vector3, new_hp: int) -> void:
	if _heal:
		_heal.queue_free()
		_heal = null
	# Burst of green particles where it was picked up (seen by everyone).
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = 0.6
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.14
	mesh.material = _unlit(Color(0.3, 1.0, 0.4))
	p.mesh = mesh
	p.position = pos + Vector3(0, 0.6, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	if id == my_id:
		player.hp = new_hp
		hud.heal_effect()
		Sfx.play("heal")
	else:
		Sfx.play_at("heal", pos, self, -2.0)


func _build_world(id: int) -> void:
	map = Maps.get_map(id)
	Maps.build_scene(self, map)
