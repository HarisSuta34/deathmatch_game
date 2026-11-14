extends Node
# Headless test client used by tools/test_net.ps1 (not part of the game).
#   ++ --bot=create   creates a room, writes its code to user://bot_code.txt, starts at 4 players
#   ++ --bot=join     joins the room from that file
# In the match every bot stands at a fixed duel spot and shoots at the first living enemy.

const CODE_FILE := "user://bot_code.txt"

var mode := ""
var port := 9080
var teams := {}
var enemy_pos := {}
var alive := false
var pos := Vector3.ZERO
var tick := 0.0
var in_match := false
var _send_t := 0.0
var _shoot_t := 0.0


func _ready() -> void:
	Net.message.connect(_on_msg)
	Net.connected.connect(func() -> void:
		if mode == "create":
			Net.send("create", ["Creator"])
		else:
			Net.send("join", [FileAccess.get_file_as_string(CODE_FILE).strip_edges(), "Bot%d" % (randi() % 1000)]))
	Net.disconnected.connect(func() -> void:
		print("BOT disconnected")
		get_tree().quit(1))
	Net.connect_to("ws://localhost:%d" % port)


func _on_msg(msg: String, a: Array) -> void:
	match msg:
		"joined":
			print("BOT joined room ", a[0])
			if mode == "create":
				FileAccess.open(CODE_FILE, FileAccess.WRITE).store_string(a[0])
		"lobby":
			if a[0].state == "lobby" and in_match:
				print("BOT back in lobby")
				get_tree().quit()
			elif mode == "create" and a[0].players.size() == 4 and not in_match:
				Net.send("start")
		"error":
			print("BOT error: ", a[0])
		"match_start":
			in_match = true
			for e: Array in a[2]:
				teams[e[0]] = e[2]
			print("BOT match started, my team ", teams[Net.my_id])
		"spawn":
			if a[0] == Net.my_id:
				alive = true
				pos = Vector3(10 + (Net.my_id % 5), 0.1, -10 if teams[Net.my_id] == 0 else -22)
		"snap":
			tick = a[0]
			enemy_pos.clear()
			var ids: PackedInt32Array = a[2]
			var d: PackedFloat32Array = a[3]
			for j in ids.size():
				if teams.get(ids[j], -1) != teams[Net.my_id] and (int(d[j * 6 + 5]) & 1) != 0:
					enemy_pos[ids[j]] = Vector3(d[j * 6], d[j * 6 + 1], d[j * 6 + 2])
		"hit":
			if a[0] == Net.my_id:
				print("BOT took damage, hp ", a[1])
		"kill":
			if a[1] == Net.my_id:
				alive = false
			print("BOT kill event: %d killed %d with %s, scores %s" % [a[0], a[1], a[2], a[3]])
		"match_end":
			print("BOT match end: scores %s winner %d" % [a[0], a[1]])


func _process(delta: float) -> void:
	if not alive:
		return
	_send_t += delta
	_shoot_t += delta
	if _send_t >= 0.05:
		_send_t = 0.0
		Net.send("state", [pos, 0.0, 0.0, 0])
	if _shoot_t >= 0.3 and not enemy_pos.is_empty():
		_shoot_t = 0.0
		var origin := pos + Vector3(0, 1.5, 0)
		var target: Vector3 = enemy_pos.values()[0] + Vector3(0, 1, 0)
		Net.send("shoot", [origin, (target - origin).normalized(), randi() & 0xFFFF, tick])
