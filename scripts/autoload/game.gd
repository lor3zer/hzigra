extends Node

## Глобальное состояние: настройки, рекорды, последние параметры гонки,
## управление вводом и переходы между меню и гонкой.

const SETTINGS_PATH := "user://settings.cfg"
const AI_NAMES := ["Макс", "Алекс", "Луиза", "Кира", "Тимур", "Ника", "Лео", "Ева", "Арсений", "Мира", "Гордон", "Зоя"]

var settings := {
	"player_name": "",
	"car": "kestrel_rs",
	"paint": 0,
	"steering": 0,       # 0 — кнопки, 1 — наклон
	"tilt_sens": 1.0,
	"tilt_invert": false,
	"camera": 0,         # 0 — ближняя, 1 — дальняя, 2 — с капота
	"shadows": true,
	"sound": true,
	"show_fps": false,
}
var records := {}        # "трасса|rev" -> {"time", "car", "name"}
var last_race := {"track": "valley", "laps": 3, "opponents": 5, "difficulty": 1, "reverse": false, "tod": 0, "collisions": true}
var last_sandbox := {"track": "polygon", "opponents": 0, "tod": 0, "reverse": false}

var main: Node
var pending_message := ""
var tilt_zero := 0.0


func _ready() -> void:
	_setup_input()
	load_settings()
	if settings["player_name"] == "":
		settings["player_name"] = "Игрок %d" % randi_range(100, 999)
	get_tree().set_auto_accept_quit(true)


func _setup_input() -> void:
	_add_keys("accelerate", [KEY_W, KEY_UP])
	_add_keys("brake", [KEY_S, KEY_DOWN])
	_add_keys("steer_left", [KEY_A, KEY_LEFT])
	_add_keys("steer_right", [KEY_D, KEY_RIGHT])
	_add_keys("nitro", [KEY_SPACE, KEY_SHIFT])
	_add_keys("respawn", [KEY_R])
	_add_keys("camera", [KEY_C])
	_add_keys("pause", [KEY_ESCAPE, KEY_P])
	_add_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_button("nitro", JOY_BUTTON_A)
	_add_button("respawn", JOY_BUTTON_Y)
	_add_button("camera", JOY_BUTTON_X)
	_add_button("pause", JOY_BUTTON_START)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)


func _add_keys(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_axis(action: String, axis: JoyAxis, dir: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)


func _add_button(action: String, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- сохранение

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])
	records = cfg.get_value("data", "records", {})
	var lr: Dictionary = cfg.get_value("data", "last_race", {})
	last_race.merge(lr, true)
	var ls: Dictionary = cfg.get_value("data", "last_sandbox", {})
	last_sandbox.merge(ls, true)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.set_value("data", "records", records)
	cfg.set_value("data", "last_race", last_race)
	cfg.set_value("data", "last_sandbox", last_sandbox)
	cfg.save(SETTINGS_PATH)


func record_key(track_id: String, reverse: bool) -> String:
	return "%s|%s" % [track_id, "rev" if reverse else "fwd"]


## Возвращает true, если это новый рекорд трассы.
func submit_lap(track_id: String, reverse: bool, time: float, car_name: String) -> bool:
	var key := record_key(track_id, reverse)
	var rec: Dictionary = records.get(key, {})
	if rec.is_empty() or time < float(rec["time"]):
		records[key] = {"time": time, "car": car_name, "name": settings["player_name"]}
		save_settings()
		return true
	return false


static func fmt_time(t: float) -> String:
	if t <= 0.0:
		return "--:--.---"
	var ms := int(round(t * 1000.0))
	return "%d:%02d.%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]


func my_player_info() -> Dictionary:
	return {"name": settings["player_name"], "car": settings["car"], "paint": settings["paint"]}


# ---------------------------------------------------------------- запуск

func difficulty_skill(d: int) -> float:
	return [0.84, 0.92, 1.0][clampi(d, 0, 2)]


func _ai_entries(count: int, cls: String, start_id: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool := CarDB.cars_of_class(cls)
	var names := AI_NAMES.duplicate()
	names.shuffle()
	var out := []
	for i in count:
		var c: Dictionary = pool[rng.randi() % pool.size()]
		out.append({"id": start_id - i, "name": names[i % names.size()], "car": c["id"], "paint": rng.randi() % CarDB.PAINTS.size(), "ai": true})
	return out


func start_single_race() -> void:
	var cfg := last_race.duplicate()
	cfg["mode"] = "race"
	cfg["net"] = false
	var cls: String = CarDB.get_car(settings["car"])["class"]
	var grid := _ai_entries(int(cfg["opponents"]), cls, -1)
	var me := my_player_info()
	me["id"] = 1
	me["ai"] = false
	grid.append(me)
	save_settings()
	main.start_race(cfg, grid)


func start_sandbox() -> void:
	var cfg := last_sandbox.duplicate()
	cfg["mode"] = "sandbox"
	cfg["net"] = false
	cfg["laps"] = 0
	cfg["difficulty"] = 1
	cfg["collisions"] = true
	var cls: String = CarDB.get_car(settings["car"])["class"]
	var me := my_player_info()
	me["id"] = 1
	me["ai"] = false
	var grid := [me]
	grid.append_array(_ai_entries(int(cfg["opponents"]), cls, -1))
	save_settings()
	main.start_race(cfg, grid)


## Хост собирает стартовую решётку: люди в случайном порядке, ИИ сзади.
func build_mp_grid(cfg: Dictionary, players: Dictionary) -> Array:
	var humans := []
	for id in players.keys():
		var p: Dictionary = players[id].duplicate()
		p["id"] = id
		p["ai"] = false
		humans.append(p)
	humans.shuffle()
	var cls := "sport"
	if not humans.is_empty():
		cls = CarDB.get_car(humans[0]["car"])["class"]
	humans.append_array(_ai_entries(int(cfg["opponents"]), cls, -1))
	return humans


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_settings()
