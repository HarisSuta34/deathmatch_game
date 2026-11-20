extends Control
# Main menu (nickname, create/join room, practice) and the room lobby. Built in code.

const Config = preload("res://scripts/config.gd")
const Maps = preload("res://scripts/shared/maps.gd")
const Room = preload("res://scripts/shared/room.gd")

const MINUTES := [5, 10, 15]
const SETTINGS := "user://settings.cfg"

var main_page: VBoxContainer
var lobby_page: VBoxContainer
var nick_edit: LineEdit
var code_edit: LineEdit
var url_edit: LineEdit
var controls_page: VBoxContainer
var practice_map: OptionButton
var status: Label
var code_label: Label
var count_label: Label
var players_box: VBoxContainer
var map_opt: OptionButton
var len_opt: OptionButton
var start_btn: Button
var lobby_msg: Label
var _pending := []    # [msg, args] to send as soon as we are connected
var _lobby := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.1, 0.3)   # the 3D backdrop shows through
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	theme = _make_theme()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := _box_style(Color(0.05, 0.07, 0.12, 0.86), Color(1, 0.8, 0.3))
	sb.set_content_margin_all(26)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var holder := VBoxContainer.new()
	panel.add_child(holder)
	_build_main(holder)
	_build_lobby(holder)
	_build_controls(holder)
	lobby_page.visible = false
	controls_page.visible = false
	if Config.touch_device():
		_touch_text(nick_edit, "Your nickname")
		_touch_text(code_edit, "Room code")
	Net.message.connect(_on_msg)
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		nick_edit.text = cfg.get_value("player", "nick", "")


func _build_main(holder: Control) -> void:
	main_page = _page(holder)
	main_page.add_child(_title())
	main_page.add_child(_label("Red vs Blue team deathmatch, 2v2 up to 10v10", 18, Color(0.7, 0.75, 0.85)))
	main_page.add_child(_gap(10))
	nick_edit = _edit("Your nickname", 16)
	main_page.add_child(nick_edit)
	main_page.add_child(_button("Create Room", func() -> void: _go("create", [_nick()])))
	var join := HBoxContainer.new()
	code_edit = _edit("Room code", 4)
	code_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	join.add_child(code_edit)
	join.add_child(_button("Join Room", _join))
	main_page.add_child(join)
	main_page.add_child(_gap(10))
	var prac := HBoxContainer.new()
	practice_map = OptionButton.new()
	for n: String in Maps.NAMES:
		practice_map.add_item(n)
	prac.add_child(practice_map)
	var pb := _button("Practice Offline (vs bots)", func() -> void:
		_save()
		Net.start_practice(_nick(), practice_map.selected))
	pb.size_flags_horizontal = SIZE_EXPAND_FILL
	prac.add_child(pb)
	main_page.add_child(prac)
	main_page.add_child(_button("Controls", func() -> void:
		main_page.visible = false
		controls_page.visible = true))
	status = _label("", 18, Color(1, 0.75, 0.4))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_page.add_child(status)
	main_page.add_child(_gap(10))
	var srv := HBoxContainer.new()
	srv.add_child(_label("Server", 14, Color(0.6, 0.6, 0.65)))
	url_edit = _edit("ws://localhost:9080", 200)
	url_edit.text = Config.server_url()
	url_edit.add_theme_font_size_override("font_size", 14)
	url_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	srv.add_child(url_edit)
	main_page.add_child(srv)


func _build_lobby(holder: Control) -> void:
	lobby_page = _page(holder)
	lobby_page.add_child(_label("ROOM CODE", 18, Color(0.7, 0.75, 0.85)))
	code_label = _label("", 72, Color(1, 0.9, 0.4))
	lobby_page.add_child(code_label)
	lobby_page.add_child(_label("Share this code with your friends", 16, Color(0.7, 0.75, 0.85)))
	count_label = _label("", 22)
	lobby_page.add_child(count_label)
	players_box = VBoxContainer.new()
	lobby_page.add_child(players_box)
	lobby_page.add_child(_gap(6))
	map_opt = OptionButton.new()
	for n: String in Maps.NAMES:
		map_opt.add_item(n)
	len_opt = OptionButton.new()
	for m: int in MINUTES:
		len_opt.add_item("%d minutes" % m)
	for o: OptionButton in [map_opt, len_opt]:
		o.size_flags_horizontal = SIZE_EXPAND_FILL
		o.item_selected.connect(func(_i: int) -> void:
			Net.send("set_opt", [map_opt.selected, MINUTES[len_opt.selected]]))
	var opts := GridContainer.new()
	opts.columns = 2
	opts.add_child(_label("Map", 18))
	opts.add_child(map_opt)
	opts.add_child(_label("Match length  ", 18))
	opts.add_child(len_opt)
	lobby_page.add_child(opts)
	start_btn = _button("Start Match", func() -> void: Net.send("start"))
	lobby_page.add_child(start_btn)
	lobby_msg = _label("", 18, Color(1, 0.75, 0.4))
	lobby_page.add_child(lobby_msg)
	lobby_page.add_child(_button("Leave Room", func() -> void:
		Net.send("leave")
		_show_main("")))


# ---------- flow ----------

func _nick() -> String:
	var n := nick_edit.text.strip_edges()
	return n if n != "" else "Player"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "nick", nick_edit.text)
	cfg.save(SETTINGS)


func _join() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		status.text = "Enter the 4-letter room code"
	else:
		_go("join", [code, _nick()])


# Sends a create/join request, connecting to the server first if needed.
func _go(msg: String, args: Array) -> void:
	_save()
	if Net.is_online():
		Net.send(msg, args)
	else:
		_pending = [msg, args]
		status.text = "Connecting to the server... (a sleeping free server can take a minute)"
		Net.connect_to(url_edit.text.strip_edges())


func _on_connected() -> void:
	status.text = ""
	if not _pending.is_empty():
		Net.send(_pending[0], _pending[1])
		_pending = []


func _on_disconnected() -> void:
	_pending = []
	_show_main("Could not reach the server, or the connection was lost.")


const DESKTOP_CONTROLS := [
	["W A S D  or  arrow keys", "Move (two keys = diagonal)"],
	["Mouse", "Look around"],
	["Left click", "Shoot"],
	["Right click,  Q  or  AIM button", "Aim / sniper scope"],
	["R", "Reload"],
	["Space", "Jump"],
	["Shift", "Sprint"],
	["C  or  Ctrl", "Crouch / stand up"],
	["Tab", "Scoreboard"],
	["1 - 4", "Choose weapon (loadout screen)"],
	["Esc", "Free the mouse cursor"],
]
const TOUCH_CONTROLS := [
	["Left thumb", "Joystick: move (push fully forward to sprint)"],
	["Drag on the right", "Look around"],
	["FIRE", "Shoot while held; slide the finger to aim as you shoot"],
	["Top-right button", "Full screen on / off"],
	["AIM", "Aim / scope on or off"],
	["R", "Reload"],
	["JUMP", "Jump"],
	["CROUCH", "Crouch / stand up"],
	["SCORE", "Scoreboard (hold)"],
	["Tap a weapon card", "Choose weapon"],
]


func _build_controls(holder: Control) -> void:
	controls_page = _page(holder)
	controls_page.custom_minimum_size.x = 900
	controls_page.add_child(_label("CONTROLS", 40, Color(1, 0.85, 0.3)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	controls_page.add_child(cols)
	for part: Array in [["Keyboard and mouse", DESKTOP_CONTROLS], ["Phone / tablet (touch)", TOUCH_CONTROLS]]:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = SIZE_EXPAND_FILL
		cols.add_child(v)
		v.add_child(_label(part[0], 22, Color(0.5, 0.75, 1)))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		v.add_child(grid)
		for row: Array in part[1]:
			var k := _label(row[0], 16, Color(1, 0.9, 0.5))
			k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(k)
			var d := _label(row[1], 16)
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			grid.add_child(d)
	controls_page.add_child(_button("Back", func() -> void: _show_main("")))


# Phones: Godot's text field cannot open the on-screen keyboard reliably on the web,
# so tapping the field opens the browser's own text prompt instead.
func _touch_text(e: LineEdit, title: String) -> void:
	e.editable = false
	e.add_theme_color_override("font_uneditable_color", Color.WHITE)
	e.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and OS.has_feature("web"):
			var v: Variant = JavaScriptBridge.eval("window.prompt(%s, %s)" % [JSON.stringify(title), JSON.stringify(e.text)], true)
			if v is String:
				e.text = (v as String).strip_edges().left(e.max_length))


func _show_main(text: String) -> void:
	controls_page.visible = false
	lobby_page.visible = false
	main_page.visible = true
	status.text = text


func _on_msg(msg: String, a: Array) -> void:
	match msg:
		"lobby":
			if Net.local_room:      # practice match finished
				Net.close()
				_show_main("")
				return
			_lobby = a[0]
			_refresh()
			if _lobby.state == "lobby":
				main_page.visible = false
				lobby_page.visible = true
		"error":
			if lobby_page.visible:
				lobby_msg.text = a[0]
			else:
				status.text = a[0]


func _refresh() -> void:
	var list: Array = _lobby.players
	var host: bool = _lobby.host == Net.my_id
	code_label.text = _lobby.code
	count_label.text = "Players (%d/%d)" % [list.size(), Room.MAX_PLAYERS]
	for ch in players_box.get_children():
		ch.queue_free()
	for e: Array in list:
		var text: String = e[1]
		if e[0] == _lobby.host:
			text += "   (host)"
		players_box.add_child(_label(text, 18, Color(1, 0.9, 0.4) if e[0] == Net.my_id else Color.WHITE))
	map_opt.select(_lobby.map)
	len_opt.select(MINUTES.find(_lobby.minutes))
	map_opt.disabled = not host
	len_opt.disabled = not host
	start_btn.disabled = not host
	start_btn.text = "Start Match" if host else "Waiting for the host to start"
	var n := list.size()
	lobby_msg.text = "" if n >= 4 and n <= Room.MAX_PLAYERS and n % 2 == 0 else Room.START_ERROR


# ---------- widgets ----------

func _box_style(c: Color, border := Color(0, 0, 0, 0.45)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(9)
	sb.border_width_bottom = 3
	sb.border_color = border
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	for type: String in ["Button", "OptionButton"]:
		th.set_stylebox("normal", type, _box_style(Color(0.17, 0.22, 0.34)))
		th.set_stylebox("hover", type, _box_style(Color(0.24, 0.33, 0.52)))
		th.set_stylebox("pressed", type, _box_style(Color(0.85, 0.3, 0.25)))
		th.set_stylebox("disabled", type, _box_style(Color(0.13, 0.14, 0.18)))
		th.set_stylebox("focus", type, StyleBoxEmpty.new())
	th.set_stylebox("normal", "LineEdit", _box_style(Color(0.06, 0.07, 0.1), Color(0.3, 0.4, 0.6)))
	th.set_stylebox("focus", "LineEdit", _box_style(Color(0.06, 0.07, 0.1), Color(1, 0.8, 0.3)))
	return th


func _title() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	for part: Array in [["BLOCK", Color(1, 0.36, 0.33)], ["DEATHMATCH", Color(0.4, 0.62, 1)]]:
		var l := _label(part[0], 58, part[1])
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 12)
		h.add_child(l)
	return h
func _page(holder: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 460
	v.add_theme_constant_override("separation", 10)
	holder.add_child(v)
	return v


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.add_theme_font_size_override("font_size", 20)
	return e


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	return b


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c
