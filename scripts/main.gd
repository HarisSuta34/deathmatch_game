extends Node
# Entry point. Sets up input actions and starts the game.

const Game = preload("res://scripts/client/game.gd")

var game: Node3D


func _ready() -> void:
	_setup_input()
	game = Game.new()
	add_child(game)
	game.start_test()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_screenshot(a.trim_prefix("--shot="))


# Dev helper: `-- --shot=file.png` saves a screenshot after a moment and quits.
func _screenshot(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
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
