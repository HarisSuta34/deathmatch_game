extends CanvasLayer
# In-match UI, built in code: health, ammo, timer, scores, kill feed, crosshair/scope,
# scoreboard (Tab), match intro, death screen (live scores + respawn countdown + weapon
# picker), results, shield timer, heal effects, desktop AIM button and touch controls.

const Weapons = preload("res://scripts/shared/weapons.gd")
const Maps = preload("res://scripts/shared/maps.gd")
const Touch = preload("res://scripts/client/touch.gd")

const TEAM_NAMES := ["RED", "BLUE"]
const TEAM_COLORS := [Color(1, 0.38, 0.38), Color(0.45, 0.65, 1)]
const DIM := Color(0.75, 0.78, 0.85)

var game: Node3D
var root: Control
var cross: Control
var hp_label: Label
var hp_bg: ColorRect
var hp_fill: ColorRect
var ammo_label: Label
var weapon_label: Label
var score_labels := []
var timer_label: Label
var feed: VBoxContainer
var msg_label: Label
var shield_label: Label
var flash: ColorRect
var popup: Label
var board: PanelContainer
var results: PanelContainer
var results_timer: Label
var leave_btn: Button
var aim_btn: Button
var touch: Control
# Intro / death overlay.
var overlay: PanelContainer
var ov_title: Label
var ov_sub: Label
var ov_intro: HBoxContainer
var ov_board: Control
var dead_slot: VBoxContainer
var intro_slot: CenterContainer
var picker: GridContainer
var ov_timer: Label
var picker_buttons := {}
var _mode := ""          # "" | "intro" | "dead"
var _ov_t := 0.0
var _board_t := 0.0
var _msg_t := 0.0
var _hit_t := 0.0
var _hit_kill := false
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
	_place(hp_fill, Control.PRESET_BOTTOM_LEFT, 24, -36, 220, 12)

	ammo_label = _label("", 34)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(ammo_label, Control.PRESET_BOTTOM_RIGHT, -424, -70, 400, 46)
	weapon_label = _label("", 22)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(weapon_label, Control.PRESET_BOTTOM_RIGHT, -524, -102, 500, 32)

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
	feed.add_theme_constant_override("separation", 4)
	_place(feed, Control.PRESET_TOP_RIGHT, -684, 14, 660, 260)

	msg_label = _label("", 24)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(msg_label, Control.PRESET_CENTER, -400, 70, 800, 36)
	shield_label = _label("", 24, Color(0.5, 0.95, 1.0))
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(shield_label, Control.PRESET_CENTER, -300, 110, 600, 34)
	popup = _label("", 44, Color(0.4, 1.0, 0.5))
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.modulate.a = 0.0
	_place(popup, Control.PRESET_CENTER, -300, -120, 600, 60)

	leave_btn = Button.new()
	leave_btn.text = "Leave Match"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.pressed.connect(func() -> void: game.leave.emit())
	_place(leave_btn, Control.PRESET_TOP_LEFT, 16, 14, 130, 36)

	if game.player.touch_mode:
		touch = Touch.new()
		touch.player = game.player
		root.add_child(touch)
	else:
		# For touchpad users: aim without a right click (also the Q key).
		aim_btn = Button.new()
		aim_btn.toggle_mode = true
		aim_btn.focus_mode = Control.FOCUS_NONE
		aim_btn.add_theme_font_size_override("font_size", 18)
		aim_btn.toggled.connect(func(on: bool) -> void: game.player.aim_toggle = on)
		_place(aim_btn, Control.PRESET_BOTTOM_RIGHT, -174, -156, 150, 42)

	board = _panel()
	results = _panel()
	_build_overlay()


func _process(delta: float) -> void:
	var p: CharacterBody3D = game.player
	var w: Dictionary = Weapons.DATA[p.weapon]
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	for c: Control in [hp_label, hp_bg, hp_fill, ammo_label, weapon_label]:
		c.visible = p.active
	hp_label.text = "HP %d" % p.hp
	hp_fill.size.x = 220.0 * p.hp / 100.0
	hp_fill.color = Color(0.3, 0.9, 0.35) if p.hp > 35 else Color(0.95, 0.3, 0.25)
	ammo_label.text = "%d / %d" % [p.ammo, w.mag] if w.mag > 0 else ""
	weapon_label.text = "RELOADING..." if p.reload_left > 0.0 else w.name
	var t := maxi(0, ceili(game.time_left))
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	score_labels[0].text = "RED  %d" % game.scores[0]
	score_labels[1].text = "%d  BLUE" % game.scores[1]
	leave_btn.visible = p.touch_mode or not captured
	if aim_btn:
		aim_btn.visible = p.active and not w.melee
		aim_btn.set_pressed_no_signal(p.aim_toggle)
		aim_btn.text = "AIM: ON  (Q)" if p.aim_toggle else "AIM  (Q)"

	_msg_t -= delta
	if _msg_t > 0.0:
		pass
	elif p.active and not p.touch_mode and not captured:
		msg_label.text = "Click to play"
	elif p.active and w.mag > 0 and p.ammo == 0 and p.reload_left <= 0.0:
		msg_label.text = "Tap R to reload" if p.touch_mode else "Press R to reload"
	else:
		msg_label.text = ""
	shield_label.visible = p.active and game.shield_left > 0.0
	shield_label.text = "INVINCIBLE  %d" % ceili(game.shield_left)
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.9)
	_hit_t -= delta
	cross.queue_redraw()

	var show_board := Input.is_action_pressed("scores") and not results.visible and _mode == ""
	_board_t -= delta
	if show_board and (not board.visible or _board_t <= 0.0):
		_board_t = 0.5
		_fill_panel(board, "SCOREBOARD", Color.WHITE)
	board.visible = show_board
	if overlay.visible:
		_ov_t -= delta
		if _mode == "intro":
			ov_timer.text = "Match starts in %d" % maxi(1, ceili(_ov_t))
		else:
			ov_timer.text = "Respawning in %.1f s" % maxf(_ov_t, 0.0)
			ov_sub.text = "RED %d     %s     %d BLUE" % [game.scores[0], timer_label.text, game.scores[1]]
			if _board_t <= 0.0:
				_board_t = 0.5
				_refill(ov_board, _teams_table(game.info, game.scores))
	if results.visible:
		_results_t -= delta
		results_timer.text = "Back to the lobby in %d s" % maxi(0, ceili(_results_t))
	if touch:
		touch.visible = p.active and _mode == "" and not results.visible


func _unhandled_key_input(event: InputEvent) -> void:
	if overlay.visible and event.pressed and not event.echo:
		var i: int = event.physical_keycode - KEY_1
		if i >= 0 and i < Weapons.LIST.size():
			_pick(Weapons.LIST[i])


# ---------- events called by game.gd ----------

func show_intro(seconds: float) -> void:
	_mode = "intro"
	_ov_t = seconds
	ov_title.text = "RED  vs  BLUE"
	ov_title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	ov_sub.text = "Map: %s   -   pick your weapon" % Maps.NAMES[game.map_id]
	for ch in ov_intro.get_children():
		ch.queue_free()
	var cols := []
	for team in 2:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 300
		col.add_theme_constant_override("separation", 2)
		var head := _label("%s TEAM" % TEAM_NAMES[team], 26, TEAM_COLORS[team])
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		cols.append(col)
	var vs := _label("VS", 54, Color(1, 0.85, 0.3))
	vs.custom_minimum_size.x = 110
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ov_intro.add_child(cols[0])
	ov_intro.add_child(vs)
	ov_intro.add_child(cols[1])
	# Names fade in one by one, alternating sides; "VS" pulses.
	var n := [0, 0]
	for id: int in game.info:
		var e: Dictionary = game.info[id]
		var l := _label(e.nick + ("  (you)" if id == game.my_id else ""), 20, Color(1, 0.9, 0.4) if id == game.my_id else Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate.a = 0.0
		cols[e.team].add_child(l)
		var tw := create_tween()
		tw.tween_interval(0.3 + (n[e.team] * 2 + e.team) * 0.12)
		tw.tween_property(l, "modulate:a", 1.0, 0.35)
		n[e.team] += 1
	vs.pivot_offset = Vector2(55, 35)
	var pulse := create_tween().set_loops(int(seconds / 0.8) + 1)
	pulse.tween_property(vs, "scale", Vector2(1.25, 1.25), 0.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(vs, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	ov_intro.visible = true
	ov_board.visible = false
	picker.columns = 4
	picker.reparent(intro_slot, false)
	_show_overlay()


func show_death(killer: int, seconds: float) -> void:
	_mode = "dead"
	_ov_t = seconds
	_board_t = 0.0
	ov_title.text = "KILLED BY %s" % game.nick(killer) if killer != 0 else "YOU FELL"
	ov_title.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	ov_intro.visible = false
	ov_board.visible = true
	picker.columns = 2
	picker.reparent(dead_slot, false)
	_show_overlay()


func hide_overlay() -> void:
	overlay.visible = false
	_mode = ""


func damage_flash() -> void:
	flash.color = Color(1, 0, 0, 0.35)


func heal_effect() -> void:
	flash.color = Color(0.2, 1, 0.35, 0.4)
	popup.text = "+HP   FULL HEALTH"
	popup.modulate.a = 1.0
	popup.position.y = popup.get_parent_area_size().y * 0.5 - 120.0
	var tw := create_tween().set_parallel()
	tw.tween_property(popup, "position:y", popup.position.y - 70.0, 1.4)
	tw.tween_property(popup, "modulate:a", 0.0, 1.4).set_delay(0.4)


func hit_marker(kill: bool) -> void:
	_hit_t = 0.35 if kill else 0.15
	_hit_kill = kill


func center_msg(text: String, seconds: float) -> void:
	msg_label.text = text
	_msg_t = seconds


func add_kill(killer: int, victim: int, weapon: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if killer != 0:
		row.add_child(_label(game.nick(killer), 19, _team_color(killer)))
		row.add_child(_label("[%s]" % Weapons.DATA[weapon].name, 19, Color(1, 0.92, 0.6)))
		row.add_child(_label(game.nick(victim), 19, _team_color(victim)))
	else:
		row.add_child(_label("%s fell" % game.nick(victim), 19, _team_color(victim)))
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	feed.add_child(panel)
	if feed.get_child_count() > 6:
		feed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(panel.queue_free)


func show_results(scores: Array, winner: int, stats: Array, seconds: float) -> void:
	var info := {}
	for s: Array in stats:
		info[s[0]] = {"nick": s[1], "team": s[2], "kills": s[3], "deaths": s[4]}
	var title := "DRAW" if winner < 0 else "%s TEAM WINS" % TEAM_NAMES[winner]
	var color: Color = Color.WHITE if winner < 0 else TEAM_COLORS[winner]
	results_timer = _fill_panel(results, title, color, info, scores)
	_results_t = seconds
	results.visible = true
	hide_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------- building ----------

func _team_color(id: int) -> Color:
	return TEAM_COLORS[game.info[id].team] if game.info.has(id) else Color.WHITE


func _show_overlay() -> void:
	overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


# One panel for the match intro and the death screen; the weapon picker moves
# between a row below the teams (intro) and a 2x2 grid beside the scoreboard (death).
func _build_overlay() -> void:
	overlay = _panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	overlay.add_child(v)
	ov_title = _label("", 34)
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ov_title)
	ov_sub = _label("", 22, DIM)
	ov_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ov_sub)
	var body := HBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 30)
	v.add_child(body)
	ov_intro = HBoxContainer.new()
	body.add_child(ov_intro)
	ov_board = CenterContainer.new()
	body.add_child(ov_board)
	dead_slot = VBoxContainer.new()
	body.add_child(dead_slot)
	intro_slot = CenterContainer.new()
	v.add_child(intro_slot)
	picker = GridContainer.new()
	picker.add_theme_constant_override("h_separation", 10)
	picker.add_theme_constant_override("v_separation", 10)
	intro_slot.add_child(picker)
	var group := ButtonGroup.new()
	for i in Weapons.LIST.size():
		var w: String = Weapons.LIST[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(215, 160)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = w == "rifle"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick.bind(w))
		picker.add_child(b)
		picker_buttons[w] = b
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		box.add_theme_constant_override("separation", 2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(195, 70)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_draw_weapon.bind(icon, w))
		box.add_child(icon)
		for line: Array in [["%d. %s" % [i + 1, Weapons.DATA[w].name], 18, Color.WHITE], [Weapons.DATA[w].desc, 14, DIM]]:
			var lab := _label(line[0], line[1], line[2])
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.custom_minimum_size.x = 195
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(lab)
	ov_timer = _label("", 24)
	ov_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ov_timer)
	var hint := _label("Tap or click a weapon, or press 1-4. No choice = keep your previous weapon.", 15, DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


# Side view of a weapon, drawn from the same boxes as its 3D model.
func _draw_weapon(icon: Control, w: String) -> void:
	var rects := []
	var bounds := Rect2()
	for part: Array in Weapons.parts(w):
		var s: Vector3 = part[0]
		var p: Vector3 = part[1]
		var r := Rect2(-p.z - s.z * 0.5, -p.y - s.y * 0.5, s.z, s.y)
		bounds = r if rects.is_empty() else bounds.merge(r)
		rects.append([r, part[2]])
	var k := minf(minf(icon.size.x / bounds.size.x, icon.size.y / bounds.size.y) * 0.9, 300.0)
	var off := icon.size * 0.5 - bounds.get_center() * k
	for e: Array in rects:
		var r: Rect2 = e[0]
		icon.draw_rect(Rect2(r.position * k + off, r.size * k).grow(1.5), Color(0, 0, 0, 0.6))
	for e: Array in rects:
		var r: Rect2 = e[0]
		var c: Color = e[1]
		icon.draw_rect(Rect2(r.position * k + off, r.size * k), c.lightened(0.25))


func _pick(w: String) -> void:
	picker_buttons[w].button_pressed = true
	game.pick(w)


# Two team columns (players sorted by kills) with kills and deaths.
func _teams_table(info: Dictionary, scores: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 36)
	for team in 2:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 270
		h.add_child(col)
		col.add_child(_label("%s  -  %d kills" % [TEAM_NAMES[team], scores[team]], 24, TEAM_COLORS[team]))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 20)
		col.add_child(grid)
		for head: String in ["Player", "Kills", "Deaths"]:
			grid.add_child(_label(head, 15, DIM))
		var ids := info.keys().filter(func(id: int) -> bool: return info[id].team == team)
		ids.sort_custom(func(a: int, b: int) -> bool: return info[a].kills > info[b].kills)
		for id: int in ids:
			var c := Color(1, 0.9, 0.4) if id == game.my_id else Color.WHITE
			var name_label := _label(info[id].nick, 18, c)
			name_label.custom_minimum_size.x = 150
			grid.add_child(name_label)
			grid.add_child(_label(str(info[id].kills), 18, c))
			grid.add_child(_label(str(info[id].deaths), 18, c))
	return h


func _refill(parent: Control, child: Control) -> void:
	for ch in parent.get_children():
		ch.queue_free()
	parent.add_child(child)


# Fills a panel with a title, both teams' tables and a footer label (returned).
func _fill_panel(panel: PanelContainer, title: String, color: Color, info := {}, scores := []) -> Label:
	if info.is_empty():
		info = game.info
		scores = game.scores
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var t := _label(title, 34, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_teams_table(info, scores))
	var footer := _label("", 18, DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(footer)
	_refill(panel, v)
	return footer


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11, 0.9)
	sb.set_content_margin_all(20)
	sb.set_corner_radius_all(8)
	sb.border_width_bottom = 3
	sb.border_color = Color(1, 0.8, 0.3)
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
	l.add_theme_constant_override("outline_size", 6)
	return l


# Adds c to the HUD anchored at `preset`, with a rect relative to that anchor.
func _place(c: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	root.add_child(c)
	c.set_anchors_preset(preset)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h
