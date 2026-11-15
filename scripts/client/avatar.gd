extends Node3D
# Blocky humanoid built from cubes. Feet at y=0, forward is -Z.
# Used for the local player and (with remote=true) for other players.

const Weapons = preload("res://scripts/shared/weapons.gd")

const TEAM_COLORS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.95)]
const SKIN := Color(0.93, 0.76, 0.6)
const SWING_TIME := 0.28
const GUN_SCALE := 1.4

static var _mats := {}
static var _pale_mat: StandardMaterial3D

var weapon := ""
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var aim: Node3D
var gun: Node3D
var _meshes: Array[MeshInstance3D] = []
var _pale := false
var _t := 0.0
var _walk := 0.0
var _reload := 0.0
var _swing := 0.0


func setup(team: int, nick: String, remote: bool) -> void:
	var c: Color = TEAM_COLORS[team]
	_cube(self, Vector3(0.55, 0.7, 0.3), Vector3(0, 1.1, 0), c)
	_cube(self, Vector3(0.57, 0.12, 0.32), Vector3(0, 0.8, 0), c.darkened(0.6))
	var head := _cube(self, Vector3(0.42, 0.42, 0.42), Vector3(0, 1.66, 0), SKIN)
	_cube(head, Vector3(0.08, 0.08, 0.02), Vector3(-0.1, 0.03, -0.21), Color(0.1, 0.1, 0.1))
	_cube(head, Vector3(0.08, 0.08, 0.02), Vector3(0.1, 0.03, -0.21), Color(0.1, 0.1, 0.1))
	_cube(head, Vector3(0.46, 0.14, 0.46), Vector3(0, 0.2, 0), c.darkened(0.3))   # helmet
	leg_l = _limb(Vector3(-0.14, 0.75, 0), Vector3(0.24, 0.75, 0.24), c.darkened(0.5))
	leg_r = _limb(Vector3(0.14, 0.75, 0), Vector3(0.24, 0.75, 0.24), c.darkened(0.5))
	arm_l = _limb(Vector3(-0.38, 1.42, 0), Vector3(0.18, 0.65, 0.18), c.darkened(0.2))
	aim = Node3D.new()
	aim.position = Vector3(0.42, 1.36, 0)
	add_child(aim)
	_cube(aim, Vector3(0.18, 0.18, 0.6), Vector3(0, 0, -0.3), c.darkened(0.2))
	gun = Node3D.new()
	gun.position = Vector3(0.02, 0.15, -0.5)
	aim.add_child(gun)
	set_weapon("rifle")
	if remote:
		var label := Label3D.new()
		label.text = nick
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 10
		label.modulate = c.lightened(0.5)
		label.position.y = 2.25
		add_child(label)
		# Hit volume on layer 2 so the local aim ray can land on other players.
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.8, 1.8, 0.8)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position.y = 0.9
		body.add_child(col)
		add_child(body)


func set_weapon(w: String) -> void:
	if w == weapon:
		return
	weapon = w
	for ch in gun.get_children():
		_meshes.erase(ch)
		ch.free()
	for part: Array in Weapons.PARTS[w]:
		_cube(gun, part[0] * GUN_SCALE, part[1] * GUN_SCALE, part[2])


# Spawn-protected players look pale.
func set_pale(on: bool) -> void:
	if on == _pale:
		return
	_pale = on
	if _pale_mat == null:
		_pale_mat = StandardMaterial3D.new()
		_pale_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pale_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pale_mat.albedo_color = Color(1, 1, 1, 0.55)
	for m in _meshes:
		m.material_overlay = _pale_mat if on else null


func muzzle() -> Vector3:
	return gun.global_transform * Vector3(0, 0.04, -Weapons.DATA[weapon].muzzle * GUN_SCALE)


# Knife slash.
func swing() -> void:
	_swing = SWING_TIME


func animate(delta: float, moving: bool, sprint: bool, pitch: float, reloading := false) -> void:
	_t += delta
	if moving:
		_walk += delta * (13.0 if sprint else 9.0)
	var amp := 0.8 if moving else 0.0
	var s := sin(_walk) * amp
	leg_l.rotation.x = lerpf(leg_l.rotation.x, s, minf(1.0, delta * 12.0))
	leg_r.rotation.x = -leg_l.rotation.x
	# Reload: the gun dips and tilts while the hands work on it.
	_reload = move_toward(_reload, 1.0 if reloading else 0.0, delta * 5.0)
	_swing = maxf(0.0, _swing - delta)
	var aim_x := pitch - _reload * (0.65 + sin(_t * 16.0) * 0.07)
	gun.rotation.z = _reload * 0.6
	if weapon == "knife":
		# Idle: blade slightly raised. Swing: from over the shoulder down across the body.
		var k := _swing / SWING_TIME
		aim_x = pitch + (lerpf(-0.9, 1.1, k) if k > 0.0 else 0.25)
		aim.rotation.y = sin(k * PI) * 0.5
		arm_l.rotation = Vector3(-leg_l.rotation.x, 0, 0)
	else:
		aim.rotation.y = 0.0
		arm_l.rotation = Vector3(1.35 + aim_x - _reload * 0.3, -0.62, 0)   # left hand on the gun
	aim.rotation.x = aim_x


func _limb(pos: Vector3, size: Vector3, c: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	add_child(p)
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
	if _pale:
		mi.material_overlay = _pale_mat
	parent.add_child(mi)
	_meshes.append(mi)
	return mi
