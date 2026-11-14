extends Node3D
# Client-side match world: map, lighting, local player.

const Maps = preload("res://scripts/shared/maps.gd")
const Player = preload("res://scripts/client/player.gd")

var map: Dictionary
var player: CharacterBody3D


func start_test() -> void:
	_build_world(0)
	player = Player.new()
	add_child(player)
	player.avatar.setup(0, "You", false)
	var sp: Array = Maps.spawn_point(map, 0, 0)
	player.respawn(sp[0], sp[1])


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
