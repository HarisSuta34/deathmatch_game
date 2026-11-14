extends Node
# Entry point. Sets up input actions and switches between menu and match.

const Game = preload("res://scripts/client/game.gd")
const Menu = preload("res://scripts/client/menu.gd")
const Config = preload("res://scripts/config.gd")

var game: Node3D
var menu: Control


# Command line (after `++`):  --server [--port=9080] [--dev] [--match-seconds=N]
#   --dev            lets the host start with any player count (local testing)
#   --match-seconds  overrides the match length (testing)
# Dev tools: --practice, --shot=file.png, --bot=create|join
func _ready() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opt[kv[0]] = kv[1] if kv.size() > 1 else ""
	if opt.has("server") or OS.has_feature("dedicated_server"):
		_start_server(opt)
		return
	if opt.has("bot"):
		var bot: Node = load("res://scripts/dev/bot.gd").new()
		bot.mode = opt.bot
		bot.port = int(opt.get("port", Config.DEFAULT_PORT))
		add_child(bot)
		return
	_setup_input()
	Net.message.connect(_on_msg)
	Net.disconnected.connect(_end_game)
	menu = Menu.new()
	add_child(menu)
	Net.dev_seconds = float(opt.get("match-seconds", 0))
	if opt.has("practice"):
		Net.start_practice("Tester", int(opt.practice))
	if opt.has("shot"):
		_screenshot(opt.shot, float(opt.get("shot-delay", 2)))


func _start_server(opt: Dictionary) -> void:
	var port := int(opt.get("port", OS.get_environment("PORT")))
	if port <= 0:
		port = Config.DEFAULT_PORT
	Net.dev = opt.has("dev")
	Net.dev_seconds = float(opt.get("match-seconds", 0))
	Engine.physics_ticks_per_second = 30
	Engine.max_fps = 30
	if Net.start_server(port):
		print("Server listening on port %d%s" % [port, "  (dev mode)" if Net.dev else ""])
	else:
		printerr("Could not listen on port %d" % port)
		get_tree().quit(1)


func _on_msg(msg: String, a: Array) -> void:
	match msg:
		"match_start":
			_end_game()
			menu.visible = false
			game = Game.new()
			add_child(game)
			game.setup(a)
		"lobby":
			if a[0].state == "lobby":
				_end_game()


# Leaves the match view and shows the menu/lobby again.
func _end_game() -> void:
	if game:
		game.queue_free()
		game = null
	menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Dev helper: `++ --shot=file.png [--shot-delay=2]` saves a screenshot and quits.
func _screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
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
