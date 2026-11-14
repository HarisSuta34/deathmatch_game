extends Node
# Networking autoload, same node on server and clients.
# Client:  Net.send(msg, args) -> server;  Net.message(msg, args) <- server.
# Server:  keeps the rooms and routes each peer's messages to its room.
# Offline: a local Room is driven directly, no sockets involved.

const Room = preload("res://scripts/shared/room.gd")

signal message(msg: String, args: Array)
signal connected
signal disconnected

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const MAX_ROOMS := 50

var is_server := false
var my_id := 0
var dev := false
var dev_seconds := 0.0
var rooms := {}          # code -> Room            (server)
var peer_room := {}      # peer id -> Room         (server)
var local_room: Room     # offline practice room   (client)


func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void:
		my_id = multiplayer.get_unique_id()
		connected.emit())
	multiplayer.connection_failed.connect(func() -> void:
		close()
		disconnected.emit())
	multiplayer.server_disconnected.connect(func() -> void:
		close()
		disconnected.emit())
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if is_server:
			_leave(id))


func _physics_process(delta: float) -> void:
	if is_server:
		for code: String in rooms:
			rooms[code].tick(delta)
	elif local_room:
		local_room.tick(delta)


# ---------- client ----------

func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return not is_server and peer is WebSocketMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func connect_to(url: String) -> void:
	close()
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = 60.0   # free hosts can take a while to wake up
	if peer.create_client(url) != OK:
		disconnected.emit.call_deferred()
		return
	multiplayer.multiplayer_peer = peer


func close() -> void:
	local_room = null
	if not is_server:
		multiplayer.multiplayer_peer = null


func send(msg: String, args: Array = []) -> void:
	if local_room:
		local_room.handle(my_id, msg, args)
	elif is_online():
		_c2s.rpc_id(1, msg, args)


func start_practice(nick: String, map_id: int) -> void:
	close()
	my_id = 1
	local_room = Room.new()
	local_room.practice = true
	local_room.map_id = map_id
	local_room.dev_seconds = dev_seconds
	# Deferred, so messages arrive after the caller finished, like on a network.
	local_room.send = func(_id: int, msg: String, args: Array) -> void:
		message.emit.call_deferred(msg, args)
	local_room.add_player(1, nick, false, 0)
	for i in 4:
		local_room.add_player(-1 - i, "Bot %d" % (i + 1), true, 1)
	local_room.handle(1, "start", [])


# ---------- server ----------

func start_server(port: int) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	if peer.create_server(port) != OK:
		return false
	(multiplayer as SceneMultiplayer).server_relay = false   # clients only ever talk to the server
	multiplayer.multiplayer_peer = peer
	is_server = true
	return true


@rpc("any_peer", "call_remote", "reliable")
func _c2s(msg: String, args: Array) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	match msg:
		"create":
			_leave(id)
			if rooms.size() >= MAX_ROOMS:
				_s2c.rpc_id(id, "error", ["Server is full, try again later"])
				return
			var room := Room.new()
			room.code = _new_code()
			room.dev = dev
			room.dev_seconds = dev_seconds
			room.send = _send_to
			rooms[room.code] = room
			_enter(id, room, args)
		"join":
			_leave(id)
			var code := str(args[0]).strip_edges().to_upper() if args.size() > 0 else ""
			var room: Room = rooms.get(code)
			if room == null:
				_s2c.rpc_id(id, "error", ["Room not found"])
			elif room.state != "lobby":
				_s2c.rpc_id(id, "error", ["That room is in the middle of a match"])
			elif room.players.size() >= Room.MAX_PLAYERS:
				_s2c.rpc_id(id, "error", ["Room is full"])
			else:
				_enter(id, room, args)
		"leave":
			_leave(id)
		_:
			if peer_room.has(id):
				peer_room[id].handle(id, msg, args)


@rpc("authority", "call_remote", "reliable")
func _s2c(msg: String, args: Array) -> void:
	message.emit(msg, args)


func _send_to(id: int, msg: String, args: Array) -> void:
	_s2c.rpc_id(id, msg, args)


func _enter(id: int, room: Room, args: Array) -> void:
	var nick := str(args[-1]).strip_edges().left(16) if args.size() > 0 else ""
	if nick == "":
		nick = "Player"
	peer_room[id] = room
	_s2c.rpc_id(id, "joined", [room.code])
	room.add_player(id, nick)
	print("[%s] %s joined (%d players, %d rooms)" % [room.code, nick, room.players.size(), rooms.size()])


func _leave(id: int) -> void:
	var room: Room = peer_room.get(id)
	if room == null:
		return
	peer_room.erase(id)
	room.remove_player(id)
	if room.human_count() == 0:
		rooms.erase(room.code)
		print("[%s] room closed (%d rooms)" % [room.code, rooms.size()])


func _new_code() -> String:
	while true:
		var c := ""
		for i in 4:
			c += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not rooms.has(c):
			return c
	return ""
