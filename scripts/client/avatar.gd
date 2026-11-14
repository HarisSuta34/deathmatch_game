extends Node3D
# Blocky humanoid built from cubes. Feet at y=0, forward is -Z.
# Used for the local player and (with remote=true) for other players.

const TEAM_COLORS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.95)]
const SKIN := Color(0.93, 0.76, 0.6)
const METAL := Color(0.16, 0.16, 0.18)

static var _mats := {}

var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var aim: Node3D
var gun: Node3D
var _t := 0.0
var _swing := 0.0


func setup(team: int, nick: String, remote: bool) -> void:
	var c: Color = TEAM_COLORS[team]
	_cube(self, Vector3(0.55, 0.7, 0.3), Vector3(0, 1.1, 0), c)
	var head := _cube(self, Vector3(0.42, 0.42, 0.42), Vector3(0, 1.66, 0), SKIN)
	_cube(head, Vector3(0.08, 0.08, 0.02), Vector3(-0.1, 0.03, -0.21), METAL)
	_cube(head, Vector3(0.08, 0.08, 0.02), Vector3(0.1, 0.03, -0.21), METAL)
	leg_l = _limb(Vector3(-0.14, 0.75, 0), Vector3(0.24, 0.75, 0.24), c.darkened(0.5))
	leg_r = _limb(Vector3(0.14, 0.75, 0), Vector3(0.24, 0.75, 0.24), c.darkened(0.5))
	arm_l = _limb(Vector3(-0.38, 1.42, 0), Vector3(0.18, 0.65, 0.18), c.darkened(0.2))
	aim = Node3D.new()
	aim.position = Vector3(0.38, 1.36, 0)
	add_child(aim)
	_cube(aim, Vector3(0.18, 0.18, 0.6), Vector3(0, 0, -0.3), c.darkened(0.2))
	gun = Node3D.new()
	gun.position = Vector3(-0.06, 0.02, -0.6)
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
		label.position.y = 2.2
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
	for ch in gun.get_children():
		ch.queue_free()
	match w:
		"sniper":
			_cube(gun, Vector3(0.08, 0.12, 1.2), Vector3(0, 0, -0.3), METAL)
			_cube(gun, Vector3(0.07, 0.07, 0.3), Vector3(0, 0.1, -0.15), Color(0.3, 0.3, 0.35))
		"shotgun":
			_cube(gun, Vector3(0.13, 0.13, 0.65), Vector3(0, 0, -0.1), METAL)
			_cube(gun, Vector3(0.15, 0.1, 0.25), Vector3(0, -0.06, -0.2), Color(0.5, 0.33, 0.18))
		_:
			_cube(gun, Vector3(0.1, 0.14, 0.75), Vector3(0, 0, -0.15), METAL)
			_cube(gun, Vector3(0.08, 0.22, 0.1), Vector3(0, -0.16, -0.05), METAL)


func muzzle() -> Vector3:
	return aim.global_transform * Vector3(-0.06, 0.02, -1.2)


func animate(delta: float, moving: bool, sprint: bool, pitch: float) -> void:
	if moving:
		_t += delta * (13.0 if sprint else 9.0)
	_swing = lerpf(_swing, 0.8 if moving else 0.0, minf(1.0, delta * 10.0))
	var s := sin(_t) * _swing
	leg_l.rotation.x = s
	leg_r.rotation.x = -s
	arm_l.rotation.x = -s
	aim.rotation.x = pitch


func _limb(pos: Vector3, size: Vector3, c: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	add_child(p)
	_cube(p, size, Vector3(0, -size.y * 0.5, 0), c)
	return p


static func _cube(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
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
	parent.add_child(mi)
	return mi
