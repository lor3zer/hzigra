extends Node

## Проверка мультиплеера: два процесса (хост и клиент) на одной машине.
## godot --headless --path . res://tests/net_test.tscn -- host
## godot --headless --path . res://tests/net_test.tscn -- client

var role := "host"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	Game.settings["sound"] = false
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await _wait(5)
	if role == "host":
		await _host(main)
	else:
		await _client(main)


func _wait(n: int) -> void:
	# n "кадров" по 1/60 с реального времени
	await get_tree().create_timer(n / 60.0).timeout


func _done(ok: bool, msg: String) -> void:
	print("[%s] %s: %s" % [role, "OK" if ok else "FAIL", msg])
	get_tree().quit(0 if ok else 1)


func _host(main) -> void:
	Game.settings["player_name"] = "Хост"
	var err := Net.host_game()
	if err != OK:
		return _done(false, "host_game %d" % err)
	main.show_menu("lobby")
	var t := 0
	while Net.players.size() < 2 and t < 60 * 20:
		await _wait(1)
		t += 1
	if Net.players.size() < 2:
		return _done(false, "client did not join")
	print("[host] players: ", Net.players)
	var cfg := Net.config.duplicate()
	cfg["track"] = "coast"
	cfg["opponents"] = 2
	cfg["laps"] = 1
	Net.set_config(cfg)
	await _wait(30)
	Net.start_race()
	await _wait(10)
	var race = main.current
	if not race is Race:
		return _done(false, "race not started")
	race.player.ctrl = Car.Ctrl.AI
	race.drivers[race.player.peer_id] = AIDriver.new(race.player, race.track, 0.9, race.cars)
	await _wait(60 * 10)
	var remote: Car = null
	for c in race.cars:
		if c.ctrl == Car.Ctrl.REMOTE:
			remote = c
	if remote == null:
		return _done(false, "no remote car")
	print("[host] remote car %s progress=%.1f speed=%.1f" % [remote.driver_name, remote.progress, remote.speed])
	# ждём финиша всех
	t = 0
	while t < 60 * 120:
		await _wait(30)
		t += 30
		var all := true
		for c in race.cars:
			if not c.finished:
				all = false
		if all:
			break
	for c in race.standings():
		print("[host]   %s %s fin=%s %s" % [c.driver_name, c.def["name"], c.finished, Game.fmt_time(c.finish_time)])
	var remote_ok := remote.finished
	Net.return_to_lobby()
	await _wait(30)
	_done(remote_ok and not main.current is Race, "remote finished, back to lobby")


func _client(main) -> void:
	Game.settings["player_name"] = "Клиент"
	Game.settings["car"] = "spectre_lm"
	main.show_menu("mp")
	await _wait(60)
	print("[client] discovered hosts: ", Net.hosts.keys())
	Net.join_game("127.0.0.1")
	var t := 0
	while not main.current is Race and t < 60 * 30:
		await _wait(1)
		t += 1
	if not main.current is Race:
		return _done(false, "race did not start")
	var race = main.current
	print("[client] race started, cars=%d" % race.cars.size())
	race.player.ctrl = Car.Ctrl.AI
	race.drivers[race.player.peer_id] = AIDriver.new(race.player, race.track, 0.95, race.cars)
	await _wait(60 * 10)
	var moved := 0
	for c in race.cars:
		if c.ctrl == Car.Ctrl.REMOTE and c.progress > 50.0 and c.lap >= 1:
			moved += 1
	print("[client] remote cars moving: %d of %d" % [moved, race.cars.size() - 1])
	t = 0
	while main.current is Race and t < 60 * 150:
		await _wait(30)
		t += 30
	_done(moved >= 3 and not main.current is Race, "remote cars synced, returned to lobby")
