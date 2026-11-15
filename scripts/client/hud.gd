extends CanvasLayer
# In-match UI: health, ammo, timer, scores, kill feed, crosshair/scope,
# scoreboard (Tab), loadout picker, results screen. Built in code.

const Weapons = preload("res://scripts/shared/weapons.gd")

const TEAM_NAMES := ["RED", "BLUE"]
const TEAM_COLORS := [Color(1, 0.38, 0.38), Color(0.45, 0.65, 1)]

var game: Node3D
var root: Control
var cross: Control
var hp_label: Label
var hp_fill: ColorRect
var hp_bg: ColorRect
var ammo_label: Label
var weapon_label: Label
var score_labels := []
var timer_label: Label
var feed: VBoxContainer
var msg_label: Label
var flash: ColorRect
var board: PanelContainer
var loadout: PanelContainer
var loadout_timer: Label
var loadout_buttons := {}
var results: PanelContainer
var results_timer: Label
var leave_btn: Button
var _msg_t := 0.0
var _hit_t := 0.0
var _hit_kill := false
var _load_t := 0.0
var _results_t := 0.0


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	flash = ColorRect.new()
	flash.color = Color(1, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(flash, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	cross = Control.new()
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(cross, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	cross.draw.connect(_draw_cross)

	hp_label = _label("", 34)
	_place(hp_label, Control.PRESET_BOTTOM_LEFT, 24, -84, 300, 46)
	hp_bg = ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.5)
	_place(hp_bg, Control.PRESET_BOTTOM_LEFT, 24, -36, 220, 12)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.3, 0.9, 0.35)
	_place(hp_fill, Control.PRESET_BOTTOM_LEFT, 24, -36, 220, 12)

	ammo_label = _label("", 34)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(ammo_label, Control.PRESET_BOTTOM_RIGHT, -324, -70, 300, 46)
	weapon_label = _label("", 18)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(weapon_label, Control.PRESET_BOTTOM_RIGHT, -324, -96, 300, 26)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 28)
	_place(top, Control.PRESET_CENTER_TOP, -260, 10, 520, 44)
	score_labels = [_label("", 28, TEAM_COLORS[0]), _label("", 28, TEAM_COLORS[1])]
	timer_label = _label("", 30)
	top.add_child(score_labels[0])
	top.add_child(timer_label)
	top.add_child(score_labels[1])

	feed = VBoxContainer.new()
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(feed, Control.PRESET_TOP_RIGHT, -444, 14, 420, 200)

	msg_label = _label("", 24)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(msg_label, Control.PRESET_CENTER, -300, 70, 600, 36)

	leave_btn = Button.new()
	leave_btn.text = "Leave Match"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.pressed.connect(func() -> void: game.leave.emit())
	_place(leave_btn, Control.PRESET_TOP_LEFT, 16, 14, 130, 36)

	board = _panel()
	results = _panel()
	_build_loadout()


func _process(delta: float) -> void:
	var p: CharacterBody3D = game.player
	var w: Dictionary = Weapons.DATA[p.weapon]
	hp_label.text = "HP %d" % p.hp
	hp_fill.size.x = 220.0 * p.hp / 100.0
	hp_fill.color = Color(0.3, 0.9, 0.35) if p.hp > 35 else Color(0.95, 0.3, 0.25)
	ammo_label.text = "%d / %d" % [p.ammo, w.mag] if w.mag > 0 else ""
	weapon_label.text = "RELOADING..." if p.reload_left > 0.0 else w.name
	var t := maxi(0, ceili(game.time_left))
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	score_labels[0].text = "RED  %d" % game.scores[0]
	score_labels[1].text = "%d  BLUE" % game.scores[1]

	for c: Control in [hp_label, hp_bg, hp_fill, ammo_label, weapon_label]:
		c.visible = p.active
	leave_btn.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

	_msg_t -= delta
	if p.active and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		msg_label.text = "Click to play"
	elif p.active and w.mag > 0 and p.ammo == 0 and p.reload_left <= 0.0:
		msg_label.text = "Press R to reload"
	elif p.active and game.protected:
		msg_label.text = "INVINCIBLE  (ends when you attack)"
	elif _msg_t <= 0.0:
		msg_label.text = ""
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.9)
	_hit_t -= delta
	cross.queue_redraw()

	var show_board := Input.is_action_pressed("scores") and not results.visible
	if show_board and not board.visible:
		_fill_panel(board, "SCOREBOARD", Color.WHITE, game.info, game.scores)
	board.visible = show_board
	if loadout.visible:
		_load_t -= delta
		loadout_timer.text = "Spawning in %.1f s" % maxf(_load_t, 0.0)
	if results.visible:
		_results_t -= delta
		results_timer.text = "Back to the lobby in %d s" % maxi(0, ceili(_results_t))


func _unhandled_key_input(event: InputEvent) -> void:
	if loadout.visible and event.pressed and not event.echo:
		var i: int = event.physical_keycode - KEY_1
		if i >= 0 and i < Weapons.LIST.size():
			_pick(Weapons.LIST[i])


# ---------- events called by game.gd ----------

func show_loadout(seconds: float) -> void:
	_load_t = seconds
	loadout.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_loadout() -> void:
	loadout.visible = false


func damage_flash() -> void:
	flash.color.a = 0.35


func hit_marker(kill: bool) -> void:
	_hit_t = 0.35 if kill else 0.15
	_hit_kill = kill


func center_msg(text: String, seconds: float) -> void:
	msg_label.text = text
	_msg_t = seconds


func add_kill(killer: int, victim: int, weapon: String) -> void:
	var text := "%s fell" % game.nick(victim)
	var color := Color.WHITE
	if killer != 0:
		text = "%s  [%s]  %s" % [game.nick(killer), Weapons.DATA[weapon].name, game.nick(victim)]
		if game.info.has(killer):
			color = TEAM_COLORS[game.info[killer].team]
	var l := _label(text, 18, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed.add_child(l)
	if feed.get_child_count() > 6:
		feed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(l.queue_free)


func show_results(scores: Array, winner: int, stats: Array, seconds: float) -> void:
	var info := {}
	for s: Array in stats:
		info[s[0]] = {"nick": s[1], "team": s[2], "kills": s[3], "deaths": s[4]}
	var title := "DRAW" if winner < 0 else "%s TEAM WINS" % TEAM_NAMES[winner]
	var color: Color = Color.WHITE if winner < 0 else TEAM_COLORS[winner]
	results_timer = _fill_panel(results, title, color, info, scores)
	_results_t = seconds
	results.visible = true
	loadout.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------- building ----------

func _draw_cross() -> void:
	var c := cross.size * 0.5
	var p: CharacterBody3D = game.player
	if not p.active:
		return
	if p.zoomed and p.weapon == "sniper":
		# Scope: black everywhere outside the lens, thin crosshair inside.
		var r := cross.size.y * 0.42
		cross.draw_arc(c, r + 1500.0, 0, TAU, 96, Color.BLACK, 3000.0)
		cross.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color.BLACK, 1.5)
		cross.draw_line(c - Vector2(0, r), c + Vector2(0, r), Color.BLACK, 1.5)
	else:
		var g: float = 5.0 + Weapons.DATA[p.weapon].spread * 220.0
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			cross.draw_line(c + d * g, c + d * (g + 9.0), Color.BLACK, 4.0)
			cross.draw_line(c + d * g, c + d * (g + 9.0), Color.WHITE, 2.0)
	if _hit_t > 0.0:
		var col := Color(1, 0.25, 0.2) if _hit_kill else Color.WHITE
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			cross.draw_line(c + d * 7.0, c + d * 15.0, col, 2.5)


func _build_loadout() -> void:
	loadout = _panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	loadout.add_child(v)
	var title := _label("CHOOSE YOUR WEAPON", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var group := ButtonGroup.new()
	for i in Weapons.LIST.size():
		var w: String = Weapons.LIST[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(215, 170)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = w == "rifle"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick.bind(w))
		h.add_child(b)
		loadout_buttons[w] = b
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(190, 84)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_draw_weapon.bind(icon, w))
		box.add_child(icon)
		for line: Array in [["[%d]  %s" % [i + 1, Weapons.DATA[w].name], 17, Color.WHITE], [Weapons.DATA[w].desc, 13, Color(0.78, 0.8, 0.85)]]:
			var lab := _label(line[0], line[1], line[2])
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(lab)
	loadout_timer = _label("", 20)
	loadout_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loadout_timer)
	var hint := _label("Click or press 1-4. No choice = keep your previous weapon.", 15, Color(0.8, 0.8, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


# Side view of a weapon, drawn from the same boxes as its 3D model.
func _draw_weapon(icon: Control, w: String) -> void:
	var rects := []
	var bounds := Rect2()
	for part: Array in Weapons.PARTS[w]:
		var s: Vector3 = part[0]
		var p: Vector3 = part[1]
		var r := Rect2(-p.z - s.z * 0.5, -p.y - s.y * 0.5, s.z, s.y)
		bounds = r if rects.is_empty() else bounds.merge(r)
		rects.append([r, part[2]])
	var k := minf(minf(icon.size.x / bounds.size.x, icon.size.y / bounds.size.y) * 0.9, 300.0)
	var off := icon.size * 0.5 - bounds.get_center() * k
	for e: Array in rects:
		var r: Rect2 = e[0]
		var c: Color = e[1]
		icon.draw_rect(Rect2(r.position * k + off, r.size * k).grow(1.5), Color(0, 0, 0, 0.6))
	for e: Array in rects:
		var r: Rect2 = e[0]
		var c: Color = e[1]
		icon.draw_rect(Rect2(r.position * k + off, r.size * k), c.lightened(0.25))


func _pick(w: String) -> void:
	loadout_buttons[w].button_pressed = true
	game.pick(w)


# Fills a panel with a title and both teams' player tables. Returns the footer label.
func _fill_panel(panel: PanelContainer, title: String, color: Color, info: Dictionary, scores: Array) -> Label:
	for ch in panel.get_children():
		ch.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := _label(title, 34, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	v.add_child(h)
	for team in 2:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 300
		h.add_child(col)
		col.add_child(_label("%s  -  %d kills" % [TEAM_NAMES[team], scores[team]], 24, TEAM_COLORS[team]))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 24)
		col.add_child(grid)
		for head: String in ["Player", "Kills", "Deaths"]:
			grid.add_child(_label(head, 15, Color(0.7, 0.7, 0.7)))
		var ids := info.keys().filter(func(id: int) -> bool: return info[id].team == team)
		ids.sort_custom(func(a: int, b: int) -> bool: return info[a].kills > info[b].kills)
		for id: int in ids:
			var c := Color(1, 0.9, 0.4) if id == game.my_id else Color.WHITE
			var name_label := _label(info[id].nick, 18, c)
			name_label.custom_minimum_size.x = 170
			grid.add_child(name_label)
			grid.add_child(_label(str(info[id].kills), 18, c))
			grid.add_child(_label(str(info[id].deaths), 18, c))
	var footer := _label("", 18, Color(0.8, 0.8, 0.8))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(footer)
	return footer


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.88)
	sb.set_content_margin_all(22)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(center, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	center.add_child(p)
	return p


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l


# Adds c to the HUD anchored at `preset`, with a rect relative to that anchor.
func _place(c: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	root.add_child(c)
	c.set_anchors_preset(preset)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h
