class_name SettingsPanel
extends RefCounted

## Пункты настроек — общие для экрана меню и паузы в гонке.
## changed(key) вызывается после каждого изменения: гонка применяет его сразу
## (руль, камера, тени, FPS), звук применяется здесь же.

static func build(vb: Control, in_race: bool, changed: Callable, toast: Callable) -> void:
	var s: Dictionary = Game.settings
	var set_value := func(key: String, value: Variant):
		s[key] = value
		changed.call(key)
	if not in_race:
		var row := HBoxContainer.new()
		vb.add_child(row)
		var nl := UITheme.label("Имя пилота", 26)
		nl.custom_minimum_size.x = 250
		row.add_child(nl)
		var name_edit := LineEdit.new()
		name_edit.text = s["player_name"]
		name_edit.max_length = 16
		name_edit.custom_minimum_size = Vector2(440, 56)
		name_edit.text_changed.connect(func(t): s["player_name"] = t.strip_edges() if t.strip_edges() != "" else "Игрок")
		row.add_child(name_edit)
	UITheme.selector(vb, "Руль", ["Кнопки", "Наклон телефона"], int(s["steering"]), func(i): set_value.call("steering", i))
	var sens := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
	var sens_names := sens.map(func(v): return "x%.2f" % v)
	UITheme.selector(vb, "Чувствит. наклона", sens_names, maxi(0, sens.find(float(s["tilt_sens"]))),
		func(i): set_value.call("tilt_sens", sens[i]))
	UITheme.selector(vb, "Инверсия наклона", ["Нет", "Да"], 1 if s["tilt_invert"] else 0, func(i): set_value.call("tilt_invert", i == 1))
	var calib := func():
		Game.tilt_zero = Input.get_accelerometer().x
		toast.call("Нулевое положение сохранено")
	vb.add_child(UITheme.button("Откалибровать наклон (держите телефон ровно)", calib, Vector2(0, 56)))
	UITheme.selector(vb, "Камера", ["Ближняя", "Дальняя", "С капота"], int(s["camera"]), func(i): set_value.call("camera", i))
	UITheme.selector(vb, "Тени", ["Выкл", "Вкл"], 1 if s["shadows"] else 0, func(i): set_value.call("shadows", i == 1))
	UITheme.selector(vb, "Звук", ["Выкл", "Вкл"], 1 if s["sound"] else 0, func(i):
		set_value.call("sound", i == 1)
		Game.apply_audio())
	var vols := [0.1, 0.2, 0.4, 0.6, 0.8, 1.0]
	UITheme.selector(vb, "Громкость звуков", vols.map(func(v): return "%d%%" % int(v * 100)), _nearest(vols, float(s["volume"])),
		func(i):
			set_value.call("volume", vols[i])
			Game.apply_audio())
	var mvols := [0.0, 0.1, 0.2, 0.4, 0.6, 0.8, 1.0]
	UITheme.selector(vb, "Музыка", mvols.map(func(v): return "Выкл" if v == 0.0 else "%d%%" % int(v * 100)),
		_nearest(mvols, float(s["music"])), func(i):
			set_value.call("music", mvols[i])
			Game.apply_audio())
	UITheme.selector(vb, "Показывать FPS", ["Нет", "Да"], 1 if s["show_fps"] else 0, func(i): set_value.call("show_fps", i == 1))


static func _nearest(values: Array, v: float) -> int:
	var best := 0
	for k in values.size():
		if absf(float(values[k]) - v) < absf(float(values[best]) - v):
			best = k
	return best
