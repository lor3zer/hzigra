extends Node

## Мультиплеер. Два режима:
##  * игра по Wi-Fi: один телефон — хост (сервер + игрок), остальные подключаются;
##  * выделенный сервер (например, на Armbian): отдельный процесс без графики,
##    запускается с ключом --server (или как серверная сборка). Лобби ведёт
##    "лидер" — первый подключившийся игрок, он выбирает трассу и даёт старт.
## ENet. Каждый игрок сам симулирует свою машину и рассылает её состояние
## (через сервер), сервер симулирует ботов. Поиск игр в локальной сети — UDP-broadcast.

signal players_changed
signal config_changed
signal hosts_changed
signal connection_result(ok: bool, message: String)
signal server_lost
signal race_start(config: Dictionary, grid: Array)
signal remote_state(id: int, state: Array)
signal ai_states(states: Array)
signal finish_reported(id: int, time: float)
signal peer_left(id: int)
signal back_to_lobby

const PORT := 24680
const DISCOVERY_PORT := 24681
const MAGIC := "NITRORUSH1"
const MAX_PLAYERS := 8
const PROTOCOL := 2          # меняется при несовместимых изменениях сетевого кода

var players := {}            # peer_id -> {"name", "car", "paint", "tune"}
var config := {}             # настройки гонки
var hosts := {}              # ip -> {"name", "count", "racing", "port", "t"}
var in_race := false
var leader := 0              # кто управляет лобби (на телефоне-хосте — сам хост)
var dedicated := false       # этот процесс — выделенный сервер
var remote_dedicated := false  # мы подключены к выделенному серверу
var server_name := ""
var port := PORT
var max_players := MAX_PLAYERS
var default_bots := 3

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_parse_args()


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Сервер (телефон-хост или выделенный сервер): симулирует ботов, ведёт лобби.
func is_host() -> bool:
	return is_online() and multiplayer.is_server()


## Может ли этот игрок менять настройки лобби и запускать гонку.
func is_leader() -> bool:
	if dedicated or not is_online():
		return false
	return my_id() == leader


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func default_config() -> Dictionary:
	var c: Dictionary = Game.last_race.duplicate()
	c["opponents"] = default_bots if dedicated else 0
	return c


func log_msg(text: String) -> void:
	if dedicated:
		print("[%s] %s" % [Time.get_datetime_string_from_system(false, true), text])


# ---------------------------------------------------------------- выделенный сервер

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var want := OS.has_feature("dedicated_server") or "--server" in args or "--server" in OS.get_cmdline_args()
	if not want:
		return
	server_name = "Nitro Rush сервер"
	for a in args:
		if a.begins_with("--port="):
			port = clampi(int(a.get_slice("=", 1)), 1024, 65535)
		elif a.begins_with("--name="):
			server_name = a.get_slice("=", 1).strip_edges().left(32)
		elif a.begins_with("--max-players="):
			max_players = clampi(int(a.get_slice("=", 1)), 2, 16)
		elif a.begins_with("--bots="):
			default_bots = clampi(int(a.get_slice("=", 1)), 0, 6)
	dedicated = true


func start_dedicated() -> Error:
	Engine.max_fps = 60
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		print("ОШИБКА: не удалось открыть UDP-порт %d (код %d). Порт занят или нет прав." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	players = {}
	leader = 0
	config = default_config()
	in_race = false
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	log_msg("Сервер «%s» запущен: UDP %d, до %d игроков, протокол %d" % [server_name, port, max_players, PROTOCOL])
	log_msg("Локальные адреса: %s" % ", ".join(local_ips()))
	return OK


# ---------------------------------------------------------------- подключение

func host_game() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: Game.my_player_info()}
	leader = 1
	remote_dedicated = false
	config = default_config()
	in_race = false
	stop_discovery()
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	players_changed.emit()
	config_changed.emit()
	return OK


## Адрес: "192.168.0.10", "example.com" или "example.com:24680".
func join_game(address: String) -> Error:
	leave()
	var host := address.strip_edges()
	var p := PORT
	if host.count(":") == 1:
		p = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	if host == "" or p <= 0:
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, p)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_race = false
	leader = 0
	remote_dedicated = false
	if _bcast:
		_bcast.close()
		_bcast = null


func _on_connected() -> void:
	var info := Game.my_player_info()
	info["protocol"] = PROTOCOL
	_register.rpc_id(1, info)
	connection_result.emit(true, "")


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_result.emit(false, "Не удалось подключиться")


func _on_server_disconnected() -> void:
	leave()
	server_lost.emit()


func _on_peer_connected(id: int) -> void:
	log_msg("Подключение: peer %d" % id)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		log_msg("Отключился: %s" % players[id]["name"])
	players.erase(id)
	peer_left.emit(id)
	if is_host():
		if id == leader:
			leader = players.keys()[0] if not players.is_empty() else 0
			if leader != 0:
				log_msg("Новый лидер лобби: %s" % players[leader]["name"])
		if dedicated and in_race and players.is_empty():
			log_msg("Все игроки вышли — гонка остановлена")
			_to_lobby.rpc()
		_sync_all()
	players_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if int(info.get("protocol", PROTOCOL)) != PROTOCOL:
		_kick(id, "Версия игры не совпадает с сервером — обновите игру")
		return
	if in_race and not players.has(id):
		_kick(id, "Гонка уже идёт, попробуйте позже")
		return
	if not players.has(id) and players.size() >= max_players:
		_kick(id, "Сервер заполнен")
		return
	var is_new := not players.has(id)
	var car_id := str(info.get("car", ""))
	if not CarDB.has_car(car_id):
		car_id = CarDB.CARS[0]["id"]
	players[id] = {"name": str(info.get("name", "Игрок")).left(20), "car": car_id,
		"paint": int(info.get("paint", 0)), "tune": Game.sanitize_tune(info.get("tune", {}))}
	if leader == 0 or not players.has(leader):
		leader = id
	if is_new:
		log_msg("Игрок %s (%s), всего %d" % [players[id]["name"], CarDB.get_car(players[id]["car"])["name"], players.size()])
	_sync_all()


func _kick(id: int, reason: String) -> void:
	log_msg("Отказ peer %d: %s" % [id, reason])
	_rejected.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(func():
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(id))


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	Game.pending_message = reason


func _sync_all() -> void:
	_sync_lobby.rpc(players, config, leader, server_name if dedicated else "")
	players_changed.emit()
	config_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(p: Dictionary, c: Dictionary, lead: int, sname: String) -> void:
	players = p
	config = c
	leader = lead
	server_name = sname
	remote_dedicated = sname != ""
	players_changed.emit()
	config_changed.emit()


func update_my_info() -> void:
	if not is_online():
		return
	if is_host() and not dedicated:
		players[1] = Game.my_player_info()
		_sync_all()
	else:
		var info := Game.my_player_info()
		info["protocol"] = PROTOCOL
		_register.rpc_id(1, info)


func set_config(c: Dictionary) -> void:
	if is_host():
		config = _sanitize_config(c)
		_sync_all()
	elif is_leader():
		_req_config.rpc_id(1, c)


@rpc("any_peer", "call_remote", "reliable")
func _req_config(c: Dictionary) -> void:
	if not multiplayer.is_server() or in_race or multiplayer.get_remote_sender_id() != leader:
		return
	config = _sanitize_config(c)
	_sync_all()


static func _sanitize_config(c: Dictionary) -> Dictionary:
	var track := str(c.get("track", "valley"))
	var ok := false
	for t in TrackDB.race_tracks():
		if t["id"] == track:
			ok = true
	return {
		"track": track if ok else "valley",
		"laps": clampi(int(c.get("laps", 3)), 1, 10),
		"opponents": clampi(int(c.get("opponents", 0)), 0, 6),
		"difficulty": clampi(int(c.get("difficulty", 1)), 0, 2),
		"reverse": bool(c.get("reverse", false)),
		"tod": clampi(int(c.get("tod", 0)), 0, 2),
		"collisions": bool(c.get("collisions", true)),
	}


# ---------------------------------------------------------------- гонка

func start_race() -> void:
	if is_host():
		if players.is_empty():
			return
		var cfg := _sanitize_config(config)
		cfg["mode"] = "race"
		cfg["net"] = true
		var grid := Game.build_mp_grid(cfg, players)
		log_msg("Старт: %s, кругов %d, игроков %d, ботов %d" % [TrackDB.get_track(cfg["track"])["name"], cfg["laps"], players.size(), cfg["opponents"]])
		_start_race.rpc(cfg, grid)
	elif is_leader():
		_req_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_start() -> void:
	if multiplayer.is_server() and not in_race and multiplayer.get_remote_sender_id() == leader:
		start_race()


@rpc("authority", "call_local", "reliable")
func _start_race(cfg: Dictionary, grid: Array) -> void:
	in_race = true
	race_start.emit(cfg, grid)


func send_state(state: Array) -> void:
	if is_online():
		_state.rpc(state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(state: Array) -> void:
	remote_state.emit(multiplayer.get_remote_sender_id(), state)


func send_ai_states(states: Array) -> void:
	if is_host():
		_ai.rpc(states)


@rpc("authority", "call_remote", "unreliable_ordered")
func _ai(states: Array) -> void:
	ai_states.emit(states)


func report_finish(id: int, time: float) -> void:
	if is_online():
		_finish.rpc(id, time)
	else:
		finish_reported.emit(id, time)


@rpc("any_peer", "call_local", "reliable")
func _finish(id: int, time: float) -> void:
	# игрок может сообщить только о своём финише, о ботах — только сервер
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1 and sender != id:
		return
	if dedicated and players.has(id):
		log_msg("Финиш: %s — %s" % [players[id]["name"], Game.fmt_time(time)])
	finish_reported.emit(id, time)


func return_to_lobby() -> void:
	if is_host():
		log_msg("Возврат в лобби")
		_to_lobby.rpc()
	elif is_leader():
		_req_lobby.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_lobby() -> void:
	if multiplayer.is_server() and in_race and multiplayer.get_remote_sender_id() == leader:
		return_to_lobby()


@rpc("authority", "call_local", "reliable")
func _to_lobby() -> void:
	in_race = false
	back_to_lobby.emit()


# ---------------------------------------------------------------- поиск игр в сети

func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if ":" in a or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


func start_discovery() -> void:
	stop_discovery()
	hosts.clear()
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null


func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null


func _process(dt: float) -> void:
	if _bcast and is_host():
		_bcast_timer -= dt
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			var bname := server_name if dedicated else str(Game.settings["player_name"])
			var msg := JSON.stringify({"m": MAGIC, "name": bname, "count": players.size(), "racing": in_race,
				"port": port if dedicated else PORT, "dedicated": dedicated})
			var data := msg.to_utf8_buffer()
			var targets := ["255.255.255.255"]
			for ip in local_ips():
				var parts: PackedStringArray = ip.split(".")
				targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
			for t in targets:
				_bcast.set_dest_address(t, DISCOVERY_PORT)
				_bcast.put_packet(data)

	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var parsed = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary and parsed.get("m", "") == MAGIC:
				changed = true
				hosts[ip] = {"name": str(parsed.get("name", "?")), "count": int(parsed.get("count", 1)),
					"racing": bool(parsed.get("racing", false)), "port": int(parsed.get("port", PORT)),
					"dedicated": bool(parsed.get("dedicated", false)), "t": Time.get_ticks_msec()}
		var now := Time.get_ticks_msec()
		for ip in hosts.keys():
			if now - int(hosts[ip]["t"]) > 3500:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()
