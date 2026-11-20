extends Node3D
# Live 3D scene shown behind the menu: a random map with the camera slowly
# circling two squads that face each other.

const Maps = preload("res://scripts/shared/maps.gd")
const Weapons = preload("res://scripts/shared/weapons.gd")
const Avatar = preload("res://scripts/client/avatar.gd")

var cam: Camera3D
var avatars := []
var _angle := randf() * TAU


func _ready() -> void:
	var map: Dictionary = Maps.get_map(randi() % Maps.COUNT)
	Maps.build_scene(self, map)
	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	for i in 8:
		var team := i % 2
		var x := (i / 2 - 1.5) * 3.0
		var z := -14.0 if team == 0 else 14.0
		var f := Maps.ray_world(map, Vector3(x, 30, z), Vector3(x, -1, z))
		var av := Avatar.new()
		add_child(av)
		av.setup(team, "", false)
		av.set_weapon(Weapons.LIST[(i / 2) % Weapons.LIST.size()])
		av.position = Vector3(x, 30.0 - 31.0 * f, z)
		av.rotation.y = PI if team == 0 else 0.0
		avatars.append(av)
	_process(0.0)


func _process(delta: float) -> void:
	_angle += delta * 0.07
	cam.position = Vector3(sin(_angle) * 44.0, 19.0, cos(_angle) * 44.0)
	cam.look_at(Vector3(0, 3, 0))
	for av: Node3D in avatars:
		av.animate(delta, Vector3.ZERO, false, 0.0)
