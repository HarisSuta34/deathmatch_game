extends Node3D
# Blocky humanoid built from cubes. Feet at y=0, forward is -Z.
# Used for the local player and (with remote=true) for other players.
# The upper body faces the aim direction; the hips/legs turn toward the movement
# direction, so strafing and diagonals look right.

const Weapons = preload("res://scripts/shared/weapons.gd")

const TEAM_COLORS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.95)]
const FRIEND := Color(0.35, 1.0, 0.45)    # teammate tag: green (neither red nor blue)
const ENEMY := Color(1.0, 0.6, 0.1)       # enemy tag: orange
const SKIN := Color(0.93, 0.76, 0.6)
const SWING_TIME := 0.28
const GUN_SCALE := 1.4
const GUN_POS := Vector3(0.02, 0.15, -0.5)
const CROUCH_DROP := 0.45
const KICK := {"rifle": 0.35, "sniper": 1.0, "shotgun": 1.0, "knife": 0.0}

static var _mats := {}
static var _shield_mat: StandardMaterial3D

var weapon := ""
var tag: Node3D            # name tag (+ marker for teammates), scaled by game.gd with distance
var upper: Node3D
var hips: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var aim: Node3D
var gun: Node3D
var shield: MeshInstance3D
var _overlay := StandardMaterial3D.new()
var _meshes: Array[MeshInstance3D] = []
var _hit_col: CollisionShape3D
var _marker: Node3D
var _t := 0.0
var _walk := 0.0
var _amp := 0.0
var _air := 0.0
var _crouch := 0.0
var _reload := 0.0
var _swing := 0.0
var _kick := 0.0
var _flash := 0.0
var _sway := Vector2.ZERO
var _last_yaw := 0.0
var _shielded := false
var _hit_crouch := false


func setup(team: int, nick: String, remote: bool, friendly := false) -> void:
	var c: Color = TEAM_COLORS[team]
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	upper = Node3D.new()
	add_child(upper)
	_cube(upper, Vector3(0.55, 0.7, 0.3), Vector3(0, 1.1, 0), c)
	_cube(upper, Vector3(0.57, 0.12, 0.32), Vector3(0, 0.8, 0), c.darkened(0.6))
	var head := _cube(upper, Vector3(0.42, 0.42, 0.42), Vector3(0, 1.66, 0), SKIN)
	_cube(head, Vector3(0.08, 0.08, 0.02), Vector3(-0.1, 0.03, -0.21), Color(0.1, 0.1, 0.1))
	_cube(head, Vector3(0.08, 0.08, 0.02), Vector3(0.1, 0.03, -0.21), Color(0.1, 0.1, 0.1))
	_cube(head, Vector3(0.46, 0.14, 0.46), Vector3(0, 0.2, 0), c.darkened(0.3))   # helmet
	hips = Node3D.new()
	hips.position.y = 0.75
	add_child(hips)
	leg_l = _limb(hips, Vector3(-0.14, 0, 0), Vector3(0.24, 0.75, 0.24), c.darkened(0.5))
	leg_r = _limb(hips, Vector3(0.14, 0, 0), Vector3(0.24, 0.75, 0.24), c.darkened(0.5))
	arm_l = _limb(upper, Vector3(-0.38, 1.42, 0), Vector3(0.18, 0.65, 0.18), c.darkened(0.2))
	aim = Node3D.new()
	aim.position = Vector3(0.42, 1.36, 0)
	upper.add_child(aim)
	_cube(aim, Vector3(0.18, 0.18, 0.6), Vector3(0, 0, -0.3), c.darkened(0.2))
	gun = Node3D.new()
	gun.position = GUN_POS
	aim.add_child(gun)
	set_weapon("rifle")
	# Invincibility shield: a translucent glowing shell around the body.
	if _shield_mat == null:
		_shield_mat = StandardMaterial3D.new()
		_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shield_mat.albedo_color = Color(0.4, 0.95, 1.0, 0.22)
	var sm := BoxMesh.new()
	sm.size = Vector3(1.15, 2.2, 1.15)
	sm.material = _shield_mat
	shield = MeshInstance3D.new()
	shield.mesh = sm
	shield.position.y = 1.05
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.visible = false
	add_child(shield)
	if remote:
		_make_tag(nick, friendly)
		# Hit volume on layer 2 so the local aim ray can land on other players.
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.8, 1.8, 0.8)
		_hit_col = CollisionShape3D.new()
		_hit_col.shape = shape
		_hit_col.position.y = 0.9
		body.add_child(_hit_col)
		add_child(body)


# Teammates: green tag + diamond marker, both visible through walls.
# Enemies: orange tag that is hidden behind walls (only seen in line of sight).
func _make_tag(nick: String, friendly: bool) -> void:
	tag = Node3D.new()
	tag.position.y = 2.25
	add_child(tag)
	var label := Label3D.new()
	label.text = nick
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.font_size = 40
	label.outline_size = 12
	label.modulate = FRIEND if friendly else ENEMY
	label.no_depth_test = friendly
	label.render_priority = 10 if friendly else 0
	tag.add_child(label)
	if friendly:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = FRIEND
		m.no_depth_test = true
		m.render_priority = 10
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.17, 0.17, 0.17)
		mesh.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation = Vector3(0, 0, PI / 4)
		_marker = Node3D.new()
		_marker.position.y = 0.32
		_marker.add_child(mi)
		tag.add_child(_marker)


func set_weapon(w: String) -> void:
	if w == weapon:
		return
	weapon = w
	for ch in gun.get_children():
		_meshes.erase(ch)
		ch.free()
	for part: Array in Weapons.parts(w):
		_cube(gun, part[0] * GUN_SCALE, part[1] * GUN_SCALE, part[2])


func set_shield(on: bool) -> void:
	_shielded = on
	shield.visible = on


# Brief bright flash when this player takes damage (seen by everyone).
func flash() -> void:
	_flash = 0.22


func muzzle() -> Vector3:
	return gun.global_transform * Vector3(0, 0.04, -Weapons.DATA[weapon].muzzle * GUN_SCALE)


# Called on every shot: knife slash or gun recoil.
func shoot_anim() -> void:
	if weapon == "knife":
		_swing = SWING_TIME
	else:
		_kick = KICK[weapon]


# vel: world-space velocity. Call after setting rotation.y (the aim/body yaw).
func animate(delta: float, vel: Vector3, sprint: bool, pitch: float, reloading := false, crouch := false, airborne := false) -> void:
	_t += delta
	var k := 1.0 - exp(-12.0 * delta)
	var lv := Basis(Vector3.UP, rotation.y).inverse() * vel
	var speed := Vector2(lv.x, lv.z).length()
	# Hips turn toward the movement direction (legs walk "backwards" when moving back).
	var target_hip := 0.0
	if speed > 0.4:
		target_hip = atan2(-lv.x, -lv.z)
		if absf(target_hip) > PI / 2:
			target_hip -= signf(target_hip) * PI
	hips.rotation.y = lerp_angle(hips.rotation.y, target_hip, k)
	# Walk/run cycle: speed drives the stride rate and the swing size.
	_walk += delta * speed * (1.7 if sprint else 1.5)
	_amp = lerpf(_amp, clampf(speed / 6.0, 0.0, 1.25) * (0.45 if crouch else 0.8), k)
	_air = lerpf(_air, 1.0 if airborne else 0.0, 1.0 - exp(-10.0 * delta))
	_crouch = lerpf(_crouch, 1.0 if crouch else 0.0, 1.0 - exp(-14.0 * delta))
	var s := sin(_walk) * _amp
	var bob := absf(sin(_walk)) * 0.05 * _amp
	# Leg poses: walking swing, crouch kneel, jump tuck (blended).
	var ll := lerpf(s, -1.15, _crouch * 0.85)
	var lr := lerpf(-s, 0.5, _crouch * 0.85)
	ll = lerpf(ll, -0.75, _air)
	lr = lerpf(lr, 0.35, _air)
	leg_l.rotation.x = ll
	leg_r.rotation.x = lr
	hips.position.y = 0.75 - CROUCH_DROP * _crouch
	upper.position.y = -CROUCH_DROP * _crouch + bob * (1.0 - _air)
	upper.rotation.x = 0.15 * _crouch
	if _hit_col and _hit_crouch != crouch:   # only touch the physics shape when it changes
		_hit_crouch = crouch
		var h := 1.25 if crouch else 1.8
		(_hit_col.shape as BoxShape3D).size.y = h
		_hit_col.position.y = h * 0.5
	# Weapon sway from turning, idle breathing and walking.
	var yaw_rate := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = rotation.y
	_sway = _sway.lerp(Vector2(clampf(-yaw_rate * 0.012, -0.08, 0.08), 0.0), 1.0 - exp(-8.0 * delta))
	var breathe := Vector3(sin(_t * 1.3) * 0.008, sin(_t * 2.1) * 0.008, 0)
	var walk_sway := Vector3(sin(_walk) * 0.025, absf(cos(_walk)) * 0.02, 0) * _amp
	# Recoil and reload.
	_kick = maxf(0.0, _kick - delta * 6.0)
	_reload = move_toward(_reload, 1.0 if reloading else 0.0, delta * 5.0)
	_swing = maxf(0.0, _swing - delta)
	var r := _reload
	var aim_x := pitch + _kick * 0.22
	var gun_pos := GUN_POS + breathe + walk_sway + Vector3(_sway.x, _sway.y, _kick * 0.12)
	var gun_rot := Vector3.ZERO
	var arm_x := 0.0
	match weapon:
		"rifle":   # tilt the gun sideways, left hand swaps the magazine
			aim_x -= r * 0.6
			gun_rot.z = r * 0.7
			arm_x = r * (0.4 + sin(_t * 9.0) * 0.35)
		"shotgun":   # gun low, pump racked back and forth while loading shells
			aim_x -= r * 0.35
			gun_rot.z = r * 0.35
			gun_pos.z += r * sin(_t * 13.0) * 0.07
			arm_x = r * sin(_t * 13.0) * 0.25
		"sniper":   # rifle raised and rolled, bolt worked
			aim_x += r * 0.25
			gun_rot.z = -r * 0.55
			gun_rot.y = r * sin(_t * 7.0) * 0.18
			arm_x = -r * 0.3
	gun.position = gun_pos
	gun.rotation = gun_rot
	if weapon == "knife":
		# Idle: blade raised. Swing: from over the shoulder down across the body.
		var sk := _swing / SWING_TIME
		aim_x = pitch + (lerpf(-0.9, 1.1, sk) if sk > 0.0 else 0.25)
		aim.rotation.y = sin(sk * PI) * 0.5
		arm_l.rotation = Vector3(-s * 0.8 - _air * 1.2, 0, 0)
	else:
		aim.rotation.y = 0.0
		arm_l.rotation = Vector3(1.35 + aim_x - r * 0.3 + arm_x, -0.62, 0)   # left hand on the gun
	aim.rotation.x = aim_x
	# Shield pulse, hit flash.
	if _shielded:
		_shield_mat.albedo_color.a = 0.16 + sin(Time.get_ticks_msec() / 160.0) * 0.08
	_flash = maxf(0.0, _flash - delta)
	if _flash > 0.0:
		var f := _flash / 0.22
		_overlay.albedo_color = Color(1, 1, 1).lerp(Color(1, 0.15, 0.15), 1.0 - f)
		_overlay.albedo_color.a = 0.95 * f
		_set_overlay(_overlay)
	elif _shielded:
		_overlay.albedo_color = Color(0.5, 0.95, 1.0, 0.28)
		_set_overlay(_overlay)
	else:
		_set_overlay(null)
	if _marker:
		_marker.position.y = 0.32 + sin(_t * 3.0) * 0.05
		_marker.rotation.y += delta * 2.0


func _set_overlay(m: Material) -> void:
	if _meshes.is_empty() or _meshes[0].material_overlay == m:
		return
	for mi in _meshes:
		mi.material_overlay = m


func _limb(parent: Node3D, pos: Vector3, size: Vector3, c: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	_cube(p, size, Vector3(0, -size.y * 0.5, 0), c)
	return p


func _cube(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		_mats[c] = m
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mats[c]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if not _meshes.is_empty():
		mi.material_overlay = _meshes[0].material_overlay
	parent.add_child(mi)
	_meshes.append(mi)
	return mi
