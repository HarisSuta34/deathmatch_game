extends CharacterBody3D
# Local player: third-person controller, over-the-shoulder camera rig.

const Avatar = preload("res://scripts/client/avatar.gd")
const Weapons = preload("res://scripts/shared/weapons.gd")

const SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP := 7.5
const GRAVITY := 22.0
const ACCEL := 60.0
const SENS := 0.0025
const BASE_FOV := 75.0
const EYE := Vector3(0, 1.5, 0)

signal fired(origin: Vector3, dir: Vector3, seed_val: int)

var active := false   # alive and controllable
var hp := 100
var weapon := "rifle"
var ammo := 0
var cooldown := 0.0
var reload_left := 0.0
var _capture_frame := 0
var _step_t := 0.0
var yaw := 0.0
var pitch := 0.0
var zoomed := false
var moving := false
var sprinting := false
var avatar: Node3D
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.3
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	avatar = Avatar.new()
	add_child(avatar)
	pivot = Node3D.new()
	pivot.position.y = 1.55
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.position = Vector3(0.9, 0.8, 0)
	arm.spring_length = 3.2
	arm.collision_mask = 1
	arm.margin = 0.15
	var s := SphereShape3D.new()
	s.radius = 0.15
	arm.shape = s
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = BASE_FOV
	cam.current = true
	arm.add_child(cam)


func respawn(pos: Vector3, new_yaw: float, new_weapon: String) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = 0.0
	weapon = new_weapon
	ammo = Weapons.DATA[weapon].mag
	hp = 100
	cooldown = 0.0
	reload_left = 0.0
	active = true
	avatar.set_weapon(weapon)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_capture_frame = Engine.get_process_frames()


func die() -> void:
	active = false
	hp = 0
	zoomed = false
	velocity = Vector3.ZERO


func start_reload() -> void:
	if reload_left <= 0.0 and ammo < Weapons.DATA[weapon].mag:
		reload_left = Weapons.DATA[weapon].reload
		Net.send("reload")
		Sfx.play("reload", -4.0, 1.8 / reload_left)


func _fire() -> void:
	var w: Dictionary = Weapons.DATA[weapon]
	if w.mag > 0:
		ammo -= 1
	cooldown = w.interval
	# Aim point: what the crosshair is on (ray starts in front of the player, not behind).
	var fwd := -cam.global_transform.basis.z
	var from := cam.global_position + fwd * arm.get_hit_length()
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 500.0, 3)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit.position if hit else from + fwd * 500.0
	var origin := global_position + EYE
	var dir := (target - origin).normalized()
	if weapon == "sniper" and not zoomed:
		var s: float = Weapons.SNIPER_HIP_SPREAD
		dir = (dir + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
	if w.melee:
		avatar.swing()
	fired.emit(origin, dir, randi() & 0xFFFFFF)
	pitch = minf(pitch + w.kick, 1.4)


func _update_weapon(delta: float) -> void:
	var w: Dictionary = Weapons.DATA[weapon]
	cooldown -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = w.mag
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Engine.get_process_frames() > _capture_frame + 1
	zoomed = active and captured and reload_left <= 0.0 and Input.is_action_pressed("aim")
	if active and captured:
		var want: bool = Input.is_action_pressed("shoot") if w.auto else Input.is_action_just_pressed("shoot")
		if want and cooldown <= 0.0 and reload_left <= 0.0:
			if ammo > 0 or w.mag == 0:
				_fire()
			elif Input.is_action_just_pressed("shoot"):
				Sfx.play("empty")   # no automatic reload: press R
		if Input.is_action_just_pressed("reload"):
			start_reload()
	# Camera: zoom in when aiming; the sniper scope goes first-person.
	var scoped := zoomed and weapon == "sniper"
	var k := minf(1.0, delta * 14.0)
	cam.fov = lerpf(cam.fov, w.zoom_fov if zoomed else BASE_FOV, k)
	arm.spring_length = lerpf(arm.spring_length, 0.0 if scoped else (2.2 if zoomed else 3.2), k)
	arm.position = arm.position.lerp(Vector3.ZERO if scoped else Vector3(0.9, 0.8, 0), k)
	avatar.visible = active and arm.spring_length > 0.6


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var k := SENS * cam.fov / BASE_FOV
		yaw -= event.relative.x * k
		pitch = clampf(pitch - event.relative.y * k, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and not captured and active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_capture_frame = Engine.get_process_frames()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not active:
		return
	var input := Input.get_vector("left", "right", "forward", "back")
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	sprinting = Input.is_action_pressed("sprint") and not zoomed and input.y < 0.0
	var spd: float = (SPRINT_SPEED if sprinting else SPEED) * Weapons.DATA[weapon].speed
	velocity.x = move_toward(velocity.x, dir.x * spd, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_pressed("jump"):
		velocity.y = JUMP
		Sfx.play("jump", -8.0)
	move_and_slide()
	moving = is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5
	if moving:
		_step_t -= delta * (1.4 if sprinting else 1.0)
		if _step_t <= 0.0:
			_step_t = 0.36
			Sfx.play("step", -9.0, randf_range(0.85, 1.15))


func _process(delta: float) -> void:
	_update_weapon(delta)
	pivot.rotation = Vector3(pitch, yaw, 0)
	avatar.rotation.y = yaw
	avatar.animate(delta, moving and active, sprinting, pitch, reload_left > 0.0)
