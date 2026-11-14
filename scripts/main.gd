extends Node
# Entry point. Sets up input actions and switches between menu and match.

const Game = preload("res://scripts/client/game.gd")

var game: Node3D


func _ready() -> void:
	_setup_input()
	Net.message.connect(_on_msg)
	Net.start_practice("You", 0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_screenshot(a.trim_prefix("--shot="))


func _on_msg(msg: String, a: Array) -> void:
	match msg:
		"match_start":
			_end_game()
			game = Game.new()
			add_child(game)
			game.setup(a)
		"lobby":
			if a[0].state == "lobby" and game:
				_end_game()
				Net.start_practice("You", 0)


func _end_game() -> void:
	if game:
		game.queue_free()
		game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Dev helper: `++ --shot=file.png` saves a screenshot after a few seconds and quits.
func _screenshot(path: String) -> void:
	await get_tree().create_timer(7.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _setup_input() -> void:
	var keys := {
		"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "reload": KEY_R, "scores": KEY_TAB,
	}
	for a: String in keys:
		InputMap.add_action(a)
		var e := InputEventKey.new()
		e.physical_keycode = keys[a]
		InputMap.action_add_event(a, e)
	var buttons := {"shoot": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for a: String in buttons:
		InputMap.add_action(a)
		var e := InputEventMouseButton.new()
		e.button_index = buttons[a]
		InputMap.action_add_event(a, e)
