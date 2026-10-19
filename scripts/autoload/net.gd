extends Node

## Мультиплеер по локальной сети (Wi-Fi / точка доступа телефона).
## ENet: хост = сервер, остальные — клиенты. Поиск игр — UDP-broadcast.
## Каждый игрок сам симулирует свою машину и рассылает её состояние,
## хост дополнительно симулирует ботов.

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

var players := {}          # peer_id -> {"name", "car", "paint"}
var config := {}           # настройки гонки от хоста
var hosts := {}            # ip -> {"name", "count", "racing", "t"}
var in_race := false

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func default_config() -> Dictionary:
	var c: Dictionary = Game.last_race.duplicate()
	c["opponents"] = 0
	return c


# ---------------------------------------------------------------- подключение

func host_game() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: Game.my_player_info()}
	config = default_config()
	in_race = false
	stop_discovery()
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	players_changed.emit()
	config_changed.emit()
	return OK


func join_game(ip: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
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
	if _bcast:
		_bcast.close()
		_bcast = null


func _on_connected() -> void:
	_register.rpc_id(1, Game.my_player_info())
	connection_result.emit(true, "")


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_result.emit(false, "Не удалось подключиться")


func _on_server_disconnected() -> void:
	leave()
	server_lost.emit()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_left.emit(id)
	if is_host():
		_sync_all()
	players_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_race and not players.has(id):
		_rejected.rpc_id(id, "Гонка уже идёт, попробуйте позже")
		get_tree().create_timer(0.5).timeout.connect(func(): if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	players[id] = {"name": str(info.get("name", "Игрок")).left(20), "car": str(info.get("car", "kestrel_rs")), "paint": int(info.get("paint", 0))}
	_sync_all()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	Game.pending_message = reason


func _sync_all() -> void:
	_sync_lobby.rpc(players, config)
	players_changed.emit()
	config_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(p: Dictionary, c: Dictionary) -> void:
	players = p
	config = c
	players_changed.emit()
	config_changed.emit()


func update_my_info() -> void:
	if not is_online():
		return
	if is_host():
		players[1] = Game.my_player_info()
		_sync_all()
	else:
		_register.rpc_id(1, Game.my_player_info())


func set_config(c: Dictionary) -> void:
	if not is_host():
		return
	config = c
	_sync_all()


# ---------------------------------------------------------------- гонка

func start_race() -> void:
	if not is_host():
		return
	var cfg := config.duplicate()
	cfg["mode"] = "race"
	cfg["net"] = true
	var grid := Game.build_mp_grid(cfg, players)
	_start_race.rpc(cfg, grid)


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
	finish_reported.emit(id, time)


func return_to_lobby() -> void:
	if is_host():
		_to_lobby.rpc()


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
			var msg := JSON.stringify({"m": MAGIC, "name": Game.settings["player_name"], "count": players.size(), "racing": in_race})
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
				hosts[ip] = {"name": str(parsed.get("name", "?")), "count": int(parsed.get("count", 1)), "racing": bool(parsed.get("racing", false)), "t": Time.get_ticks_msec()}
		var now := Time.get_ticks_msec()
		for ip in hosts.keys():
			if now - int(hosts[ip]["t"]) > 3500:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()
