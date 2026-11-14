extends CharacterBody3D
# Local player: third-person controller, over-the-shoulder camera rig.

const Avatar = preload("res://scripts/client/avatar.gd")

const SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP := 7.5
const GRAVITY := 22.0
const ACCEL := 60.0
const SENS := 0.0025
const BASE_FOV := 75.0
const EYE := Vector3(0, 1.5, 0)

var active := false   # alive and controllable
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
	arm.position = Vector3(0.65, 0.25, 0)
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


func respawn(pos: Vector3, new_yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = 0.0
	active = true
	avatar.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var k := SENS * cam.fov / BASE_FOV
		yaw -= event.relative.x * k
		pitch = clampf(pitch - event.relative.y * k, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and not captured and active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not active:
		return
	var input := Input.get_vector("left", "right", "forward", "back")
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	sprinting = Input.is_action_pressed("sprint") and not zoomed and input.y < 0.0
	var spd := SPRINT_SPEED if sprinting else SPEED
	velocity.x = move_toward(velocity.x, dir.x * spd, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_pressed("jump"):
		velocity.y = JUMP
	move_and_slide()
	moving = is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5


func _process(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	avatar.rotation.y = yaw
	avatar.animate(delta, moving and active, sprinting, pitch)
