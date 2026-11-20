extends Node
# Entry point. Sets up input actions and switches between menu and match.

const Game = preload("res://scripts/client/game.gd")
const Menu = preload("res://scripts/client/menu.gd")
const Backdrop = preload("res://scripts/client/backdrop.gd")
const Config = preload("res://scripts/config.gd")

var game: Node3D
var menu: Control
var backdrop: Node3D


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
		bot.url = opt.get("url", "")
		add_child(bot)
		return
	_setup_input()
	Net.message.connect(_on_msg)
	Net.disconnected.connect(_end_game)
	var t0 := Time.get_ticks_msec()
	Sfx.init()
	if opt.has("perf"):
		print("PERF sound generation: %d ms" % (Time.get_ticks_msec() - t0))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # show real headroom
		_perf_loop()
	if Config.touch_device():
		_setup_portrait_hint()
	menu = Menu.new()
	add_child(menu)
	_end_game()
	Net.dev_seconds = float(opt.get("match-seconds", 0))
	if opt.has("practice"):
		Net.start_practice("Tester", int(opt.practice))
		if opt.has("weapon"):
			Net.send("pick", [opt.weapon])
	if opt.has("shot"):
		_screenshot(opt.shot, float(opt.get("shot-delay", 2)), opt)


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
			backdrop.queue_free()
			backdrop = null
			Sfx.music(false)
			menu.visible = false
			game = Game.new()
			add_child(game)
			game.setup(a)
			game.leave.connect(func() -> void:
				Net.send("leave")
				if Net.local_room:
					Net.close()
				_end_game()
				menu._show_main(""))
		"lobby":
			if a[0].state == "lobby":
				_end_game()


# Leaves the match view and shows the menu/lobby again.
func _end_game() -> void:
	if game:
		game.queue_free()
		game = null
	menu.visible = true
	if backdrop == null:
		backdrop = Backdrop.new()
		add_child(backdrop)
	Sfx.music(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Dev helper: `++ --perf` prints frame rate and costs every 2 seconds.
func _perf_loop() -> void:
	while true:
		await get_tree().create_timer(2.0).timeout
		print("PERF fps %d | frame cpu %.1f ms | physics %.1f ms | draw calls %d | objects %d | nodes %d" % [
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


# Dev helper: `++ --shot=file.png [--shot-delay=2] [--pose=x,z,yaw,pitch] [--hud=death]`
# saves a screenshot and quits.
func _screenshot(path: String, delay: float, opt: Dictionary) -> void:
	await get_tree().create_timer(delay).timeout
	if game and opt.has("pose"):
		var v: PackedFloat64Array = (opt.pose as String).split_floats(",")
		game.player.global_position = Vector3(v[0], 0.1, v[1])
		game.player.yaw = v[2]
		game.player.pitch = v[3] if v.size() > 3 else 0.0
		await get_tree().create_timer(0.5).timeout
	if game and opt.get("hud", "") == "death":
		game.hud.show_death(-1, 7.5)
		await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _setup_input() -> void:
	var keys := {
		"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "reload": [KEY_R], "scores": [KEY_TAB],
		"crouch": [KEY_C, KEY_CTRL], "aim_toggle": [KEY_Q],
	}
	# Mouse buttons (shoot/aim) are read directly in player.gd, so that taps on a
	# touchscreen (which Godot also reports as mouse clicks) never fire the gun.
	for a: String in keys:
		InputMap.add_action(a)
		for key: Key in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(a, e)


# Phones held upright: ask to rotate (the game is laid out for landscape).
func _setup_portrait_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var l := Label.new()
	l.text = "Please rotate your phone\nto landscape"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 90)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(l)
	var update := func() -> void:
		var s := get_viewport().get_visible_rect().size
		layer.visible = s.y > s.x
	get_viewport().size_changed.connect(update)
	update.call()
