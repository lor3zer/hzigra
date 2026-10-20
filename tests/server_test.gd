extends Node

## Проверка выделенного сервера: сервер запускается отдельно
##   godot --headless --path . -- --server --port=24690
## и два клиента: ... res://tests/server_test.tscn -- leader|guest 127.0.0.1:24690

var role := "guest"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "guest"
	var addr: String = args[1] if args.size() > 1 else "127.0.0.1:24690"
	Game.settings["player_name"] = "Лидер" if role == "leader" else "Гость"
	Game.settings["car"] = "raptor_v8" if role == "leader" else "spectre_lm"
	Game.set_tune(Game.settings["car"], {"wing": 3, "rims": 2})
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await _sec(0.5)
	Net.join_game(addr)
	var t := 0.0
	while Net.players.size() < 2 and t < 20.0:
		await _sec(0.2)
		t += 0.2
	if Net.players.size() < 2:
		return _done(false, "в лобби меньше двух игроков")
	print("[%s] лобби: %s, лидер=%s, я лидер=%s, сервер=%s" % [role, Net.players.size(), Net.leader, Net.is_leader(), Net.server_name])
	if role == "leader":
		if not Net.is_leader():
			return _done(false, "первый игрок не стал лидером")
		var cfg: Dictionary = Net.config.duplicate()
		cfg["track"] = "coast"
		cfg["laps"] = 1
		cfg["opponents"] = 2
		Net.set_config(cfg)
		await _sec(1.0)
		if Net.config.get("track") != "coast":
			return _done(false, "сервер не принял настройки лидера")
		Net.start_race()
	t = 0.0
	while not main.current is Race and t < 20.0:
		await _sec(0.2)
		t += 0.2
	if not main.current is Race:
		return _done(false, "гонка не началась")
	var race = main.current
	print("[%s] гонка: машин %d" % [role, race.cars.size()])
	race.player.ctrl = Car.Ctrl.AI
	race.drivers[race.player.peer_id] = AIDriver.new(race.player, race.track, 0.95, race.cars)
	t = 0.0
	var moved := 0
	while main.current is Race and t < 200.0:
		await _sec(1.0)
		t += 1.0
		if t == 15.0:
			for c in race.cars:
				if c.ctrl == Car.Ctrl.REMOTE and c.progress > 30.0:
					moved += 1
			print("[%s] чужих машин в движении: %d из %d" % [role, moved, race.cars.size() - 1])
	if main.current is Race:
		return _done(false, "сервер не вернул в лобби")
	_done(moved == 3, "гонка прошла, сервер вернул в лобби через %.0f с" % t)


func _sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _done(ok: bool, msg: String) -> void:
	print("[%s] %s: %s" % [role, "OK" if ok else "FAIL", msg])
	get_tree().quit(0 if ok else 1)
