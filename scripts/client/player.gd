extends CharacterBody3D
# Local player: movement, crouch, weapon handling and the over-the-shoulder camera.
# Camera collision: a sphere is swept from the player's head (always a free spot, inside
# the player's own capsule) toward the wanted camera spot. The camera stops where the
# sphere would first touch a wall: it snaps in at once (so it never sees inside walls)
# and eases back out smoothly when the obstacle is gone.

const Avatar = preload("res://scripts/client/avatar.gd")
const Weapons = preload("res://scripts/shared/weapons.gd")
const Config = preload("res://scripts/config.gd")

signal fired(origin: Vector3, dir: Vector3, seed_val: int)

const SPEED := 6.0
const SPRINT_SPEED := 9.0
const CROUCH_SPEED := 3.0
const JUMP := 7.5
const GRAVITY := 22.0
const ACCEL := 30.0        # ground acceleration (m/s^2)
const DECEL := 38.0        # ground braking
const AIR_ACCEL := 9.0
const SENS := 0.0025
const TOUCH_SENS := 0.006
const BASE_FOV := 75.0
const STAND_EYE := 1.55
const CROUCH_EYE := 1.05
const CAM_OFFSET := Vector3(0.9, 0.55, 3.4)      # right, up, back from the head
const CAM_OFFSET_AIM := Vector3(0.75, 0.4, 2.2)
const CAM_RADIUS := 0.3
const SHOULDER := 0.55     # shots leave from this far right of the head
const STAND_H := 1.8
const CROUCH_H := 1.25

var active := false   # alive and controllable
var hp := 100
var weapon := "rifle"
var ammo := 0
var cooldown := 0.0
var reload_left := 0.0
var yaw := 0.0
var pitch := 0.0
var zoomed := false
var aim_blocked := false   # a wall is between the gun and the crosshair target
var moving := false
var sprinting := false
var crouching := false
var airborne := false
var touch_mode := Config.touch_device()
var touch_move := Vector2.ZERO   # on-screen joystick
var touch_shoot := false         # on-screen FIRE held
var _was_touch := false
var aim_toggle := false          # on-screen AIM button or Q
var avatar: Node3D
var cam: Camera3D
var eye := STAND_EYE
var _body_yaw := 0.0
var _mouse_shoot := false
var _mouse_aim := false
var _was_shoot := false
var _capture_frame := 0
var _step_t := 0.0
var _cam_off := CAM_OFFSET
var _cam_frac := 1.0
var _cam_sphere := SphereShape3D.new()
var _shape := CapsuleShape3D.new()
var _col := CollisionShape3D.new()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.3
	_shape.radius = 0.38
	_shape.height = STAND_H
	_col.shape = _shape
	_col.position.y = STAND_H * 0.5
	add_child(_col)
	avatar = Avatar.new()
	add_child(avatar)
	_cam_sphere.radius = CAM_RADIUS
	cam = Camera3D.new()
	cam.fov = BASE_FOV
	cam.near = 0.05
	cam.top_level = true
	add_child(cam)
	cam.make_current()


func respawn(pos: Vector3, new_yaw: float, new_weapon: String) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
	_body_yaw = new_yaw
	pitch = 0.0
	weapon = new_weapon
	ammo = Weapons.DATA[weapon].mag
	hp = 100
	cooldown = 0.0
	reload_left = 0.0
	aim_toggle = false
	_set_crouch(false)
	active = true
	avatar.set_weapon(weapon)
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_capture_frame = Engine.get_process_frames()


func die() -> void:
	active = false
	hp = 0
	zoomed = false
	aim_toggle = false
	touch_shoot = false
	velocity = Vector3.ZERO
	_set_crouch(false)


func start_reload() -> void:
	if reload_left <= 0.0 and ammo < Weapons.DATA[weapon].mag:
		reload_left = Weapons.DATA[weapon].reload
		Net.send("reload")
		Sfx.play("reload", -4.0, 1.8 / reload_left)


func look(rel: Vector2, sens: float) -> void:
	var k := sens * cam.fov / BASE_FOV
	yaw -= rel.x * k
	pitch = clampf(pitch - rel.y * k, -1.4, 1.4)


func toggle_crouch() -> void:
	if active:
		_set_crouch(not crouching)


# Standing up is only allowed when there is room above.
func _set_crouch(on: bool) -> void:
	if not on and crouching and is_inside_tree():
		var test := CapsuleShape3D.new()
		test.radius = _shape.radius - 0.02
		test.height = STAND_H
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = test
		q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_H * 0.5 + 0.02, 0))
		q.collision_mask = 1
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return
	crouching = on
	_shape.height = CROUCH_H if on else STAND_H
	_col.position.y = _shape.height * 0.5


func _input(event: InputEvent) -> void:
	# Real mouse buttons only (device -1 = mouse events emulated from a touchscreen).
	if event is InputEventMouseButton and event.device != -1:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_shoot = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_aim = event.pressed


func _unhandled_input(event: InputEvent) -> void:
	if touch_mode:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		look(event.relative, SENS)
	elif event is InputEventMouseButton and event.pressed and not captured and active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_capture_frame = Engine.get_process_frames()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not active:
		return
	if Input.is_action_just_pressed("crouch"):
		toggle_crouch()
	# get_vector + limit_length: diagonals (two keys) are never faster than straight moves.
	var input := (Input.get_vector("left", "right", "forward", "back") + touch_move).limit_length(1.0)
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	var sprint_key := Input.is_action_pressed("sprint") or (touch_mode and touch_move.length() > 0.95)
	sprinting = sprint_key and not zoomed and not crouching and input.y < -0.3
	var spd: float = (CROUCH_SPEED if crouching else SPRINT_SPEED if sprinting else SPEED) * Weapons.DATA[weapon].speed
	var target := Vector2(dir.x, dir.z) * spd
	var on_floor := is_on_floor()
	var rate := (ACCEL if target.length() > 0.1 else DECEL) if on_floor else AIR_ACCEL
	var hv := Vector2(velocity.x, velocity.z).move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.y
	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif Input.is_action_pressed("jump"):
		if crouching:
			_set_crouch(false)
		else:
			velocity.y = JUMP
			Sfx.play("jump", -8.0)
	move_and_slide()
	airborne = not is_on_floor()
	moving = hv.length() > 0.5
	if moving and not airborne:
		_step_t -= delta * (hv.length() / SPEED)
		if _step_t <= 0.0:
			_step_t = 0.38
			Sfx.play("step", -12.0 if crouching else -9.0, randf_range(0.85, 1.15))


func _process(delta: float) -> void:
	_update_weapon(delta)
	# The body follows the aim smoothly instead of snapping.
	_body_yaw = lerp_angle(_body_yaw, yaw, 1.0 - exp(-18.0 * delta))
	avatar.rotation.y = _body_yaw
	var vel := velocity if active else Vector3.ZERO
	avatar.animate(delta, vel, sprinting, pitch, reload_left > 0.0, crouching, airborne and active)
	_update_camera(delta)
	aim_blocked = active and not Weapons.DATA[weapon].melee and aim_solution()[2]


func _update_weapon(delta: float) -> void:
	var w: Dictionary = Weapons.DATA[weapon]
	cooldown -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = w.mag
	var mouse_ok := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Engine.get_process_frames() > _capture_frame + 1
	var can_play := active and (touch_mode or mouse_ok)
	if Input.is_action_just_pressed("aim_toggle"):
		aim_toggle = not aim_toggle
	if not active:
		aim_toggle = false
	zoomed = can_play and reload_left <= 0.0 and not w.melee and ((_mouse_aim and mouse_ok) or aim_toggle)
	var want_shoot := _mouse_shoot and mouse_ok
	var just := want_shoot and not _was_shoot
	_was_shoot = want_shoot
	if can_play:
		# Touch FIRE works like a trigger: while held, every weapon fires at its own rate.
		var touch_just := touch_shoot and not _was_touch
		_was_touch = touch_shoot
		var want: bool = (want_shoot if w.auto else just) or touch_shoot
		if want and cooldown <= 0.0 and reload_left <= 0.0:
			if ammo > 0 or w.mag == 0:
				_fire()
			elif just or touch_just:
				Sfx.play("empty")   # no automatic reload: press R
		if Input.is_action_just_pressed("reload"):
			start_reload()
	var k := 1.0 - exp(-14.0 * delta)
	cam.fov = lerpf(cam.fov, w.zoom_fov if zoomed else BASE_FOV, k)


func _update_camera(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	eye = lerpf(eye, CROUCH_EYE if crouching else STAND_EYE, k)
	var scoped := zoomed and weapon == "sniper"
	_cam_off = _cam_off.lerp(Vector3.ZERO if scoped else (CAM_OFFSET_AIM if zoomed else CAM_OFFSET), k)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	var head := global_position + Vector3(0, eye, 0)
	var motion := basis * _cam_off
	var frac := 1.0
	if motion.length() > 0.01:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _cam_sphere
		q.transform = Transform3D(Basis(), head)
		q.motion = motion
		q.collision_mask = 1
		frac = get_world_3d().direct_space_state.cast_motion(q)[0]
	if frac < _cam_frac:
		_cam_frac = frac   # obstacle: pull in immediately, never clip into the wall
	else:
		_cam_frac = lerpf(_cam_frac, frac, 1.0 - exp(-5.0 * delta))
	cam.global_transform = Transform3D(basis, head + motion * _cam_frac)
	avatar.visible = active and _cam_off.length() * _cam_frac > 0.7


# Where a shot starts and where it goes: [origin, target, blocked].
# Target = what the crosshair is on (camera ray, started level with the player so walls
# behind the player are ignored). Origin = the right shoulder, on the camera's side, so
# peeking around a corner works the way the camera shows it. The shoulder point is pulled
# back toward the head if a wall is in between, so shots never start inside a wall.
# blocked = a wall sits between the shoulder and the crosshair target (crosshair turns red).
func aim_solution() -> Array:
	var space := get_world_3d().direct_space_state
	var fwd := -cam.global_transform.basis.z
	var head := global_position + Vector3(0, eye, 0)
	var from := cam.global_position + fwd * maxf(0.0, (head - cam.global_position).dot(fwd))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * 500.0, 3))
	var target: Vector3 = hit.position if hit else from + fwd * 500.0
	var origin := head + Basis(Vector3.UP, yaw) * Vector3(SHOULDER, 0.1, 0)
	var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(head, origin, 1))
	if side:
		origin = head.lerp(side.position, 0.8)
	var blocked := false
	var path := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target, 1))
	if path and (path.position as Vector3).distance_to(target) > 0.6:
		blocked = true
	return [origin, target, blocked]


func _fire() -> void:
	var w: Dictionary = Weapons.DATA[weapon]
	if w.mag > 0:
		ammo -= 1
	cooldown = w.interval
	var sol := aim_solution()
	var origin: Vector3 = sol[0]
	var target: Vector3 = sol[1]
	var dir := (target - origin).normalized()
	if weapon == "sniper" and not zoomed:
		var s: float = Weapons.SNIPER_HIP_SPREAD
		dir = (dir + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
	avatar.shoot_anim()
	fired.emit(origin, dir, randi() & 0xFFFFFF)
	pitch = minf(pitch + w.kick, 1.4)
	yaw += randf_range(-0.5, 0.5) * w.kick * 0.5
