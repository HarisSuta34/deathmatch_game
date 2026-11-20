extends Control
# On-screen controls for phones and tablets: a joystick that appears where the left
# thumb touches, drag anywhere else to look around, and round buttons.
# Uses raw multi-touch events so several fingers work at once.

const STICK_R := 110.0
const BUTTONS := [
	# id, text, offset from the corner, radius, corner (br = bottom-right, tl = top-left)
	["fire", "FIRE", Vector2(-170, -235), 88.0, "br"],
	["aim", "AIM", Vector2(-340, -110), 58.0, "br"],
	["jump", "JUMP", Vector2(-120, -430), 58.0, "br"],
	["reload", "R", Vector2(-330, -310), 50.0, "br"],
	["crouch", "CROUCH", Vector2(-480, -95), 56.0, "br"],
	["score", "SCORE", Vector2(220, 40), 40.0, "tl"],
]

var player: CharacterBody3D
var _owner := {}          # touch index -> "stick" | "look" | button id
var _held := {}
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _center(b: Array) -> Vector2:
	return b[2] + (size if b[4] == "br" else Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if not _owner.is_empty():
			for i: int in _owner.keys():
				_touch_up(i)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		var o: String = _owner.get(event.index, "")
		if o == "stick":
			_stick_vec = ((event.position - _stick_center) / STICK_R).limit_length(1.0)
			player.touch_move = _stick_vec
		elif o == "look" or o == "fire":   # the finger on FIRE can also drag to aim
			player.look(event.relative, player.TOUCH_SENS)


func _touch_down(i: int, pos: Vector2) -> void:
	for b: Array in BUTTONS:
		if pos.distance_to(_center(b)) <= b[3] * 1.2:
			_owner[i] = b[0]
			_press(b[0], true)
			return
	if pos.x < size.x * 0.4 and pos.y > size.y * 0.3:
		_owner[i] = "stick"
		_stick_center = pos
		_stick_vec = Vector2.ZERO
	else:
		_owner[i] = "look"


func _touch_up(i: int) -> void:
	var o: String = _owner.get(i, "")
	_owner.erase(i)
	if o == "stick":
		_stick_vec = Vector2.ZERO
		player.touch_move = Vector2.ZERO
	elif o != "look" and o != "":
		_press(o, false)


func _press(id: String, down: bool) -> void:
	_held[id] = down
	match id:
		"fire":   # tap to start shooting, tap again to stop
			if down:
				player.touch_shoot = not player.touch_shoot
		"aim":
			if down:
				player.aim_toggle = not player.aim_toggle
		"crouch":
			if down:
				player.toggle_crouch()
		"jump", "reload", "score":
			var action: String = "scores" if id == "score" else id
			if down:
				Input.action_press(action)
			else:
				Input.action_release(action)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var active: bool = _owner.values().has("stick")
	var base := _stick_center if active else Vector2(210, size.y - 200)
	draw_circle(base, STICK_R, Color(1, 1, 1, 0.1))
	draw_arc(base, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(base + _stick_vec * STICK_R, 46, Color(1, 1, 1, 0.4))
	if not active:
		_text(font, base + Vector2(0, STICK_R + 28), "MOVE", 18)
	for b: Array in BUTTONS:
		var c := _center(b)
		var firing: bool = b[0] == "fire" and player.touch_shoot
		var on: bool = _held.get(b[0], false) or firing or (b[0] == "aim" and player.aim_toggle) or (b[0] == "crouch" and player.crouching)
		draw_circle(c, b[3], Color(1, 0.45, 0.3, 0.6) if on else Color(0, 0, 0, 0.38))
		draw_arc(c, b[3], 0, TAU, 40, Color(1, 1, 1, 0.65), 3.0)
		_text(font, c, "STOP" if firing else b[1], 24 if b[3] > 60.0 else 18)


func _text(font: Font, c: Vector2, text: String, fs: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
