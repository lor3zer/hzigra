extends Control

## Все экраны меню строятся из кода: главное меню, настройка гонки,
## песочница, гараж, настройки, мультиплеер и лобби.

var _holder: VBoxContainer
var _title: Label
var _subtitle: Label
var _toast: Label
var _screen := ""
var _preview_pivot: Node3D
var _preview_model: CarModel
var _status: Label
var _hosts_box: VBoxContainer
var _lobby_players: VBoxContainer
var _lobby_cfg: VBoxContainer
var _garage_sel := ""
var _garage_paint := 0
var _garage_info: VBoxContainer
var _garage_return := "main"
var _toast_time := 0.0


func _ready() -> void:
	theme = UITheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var grad := Gradient.new()
	grad.set_color(0, Color(0.04, 0.09, 0.2))
	grad.set_color(1, Color(0.01, 0.01, 0.04))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	_title = UITheme.label("", 46, UITheme.ACCENT)
	header.add_child(_title)
	_subtitle = UITheme.label("", 22, Color(0.7, 0.75, 0.85))
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(_subtitle)
	_holder = VBoxContainer.new()
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_holder)

	_toast = UITheme.label("", 24, Color(1, 0.5, 0.4))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -500
	_toast.offset_right = 500
	_toast.offset_top = -60
	_toast.offset_bottom = -20
	add_child(_toast)

	Net.players_changed.connect(_on_players_changed)
	Net.config_changed.connect(_on_config_changed)
	Net.hosts_changed.connect(_refresh_hosts)
	Net.connection_result.connect(_on_connection_result)


func _process(dt: float) -> void:
	if _preview_pivot and is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y += dt * 0.5
	_toast_time -= dt
	_toast.visible = _toast_time > 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match _screen:
			"main":
				get_tree().quit()
			"garage":
				open(_garage_return)
			"lobby":
				Net.leave()
				open("mp")
			_:
				open("main")


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 4.0


func open(screen: String) -> void:
	if screen != "mp":
		Net.stop_discovery()
	_screen = screen
	_preview_pivot = null
	for c in _holder.get_children():
		c.queue_free()
	match screen:
		"race":
			_race_setup()
		"sandbox":
			_sandbox_setup()
		"garage":
			_garage()
		"settings":
			_settings()
		"mp":
			_mp()
		"lobby":
			_lobby()
		_:
			_main()
	if Game.pending_message != "":
		toast(Game.pending_message)
		Game.pending_message = ""


func _set_title(t: String, sub := "") -> void:
	_title.text = t
	_subtitle.text = sub


# ---------------------------------------------------------------- виджеты

func _selector(parent: Control, title: String, options: Array, idx: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UITheme.label(title, 26)
	l.custom_minimum_size.x = 250
	row.add_child(l)
	var state := {"i": clampi(idx, 0, options.size() - 1)}
	var val := UITheme.label(str(options[state["i"]]), 26, Color(1, 0.92, 0.5))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.custom_minimum_size.x = 300
	var step := func(d: int):
		state["i"] = posmod(state["i"] + d, options.size())
		val.text = str(options[state["i"]])
		cb.call(state["i"])
	row.add_child(UITheme.button("<", step.bind(-1), Vector2(70, 56)))
	row.add_child(val)
	row.add_child(UITheme.button(">", step.bind(1), Vector2(70, 56)))


func _bottom_bar() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	_holder.add_child(hb)
	return hb


func _accent_button(text: String, cb: Callable, w := 260.0) -> Button:
	var b := UITheme.button(text, cb, Vector2(w, 70))
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0.0, 0.45, 0.7), UITheme.ACCENT))
	b.add_theme_font_size_override("font_size", 30)
	return b


func _scroll_box() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_holder.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	return vb


func _range_names(from: int, to: int) -> Array:
	var out := []
	for i in range(from, to + 1):
		out.append(str(i))
	return out


## 3D-превью машины во вьюпорте.
func _preview(parent: Control, car_id: String, paint: int) -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(300, 200)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.3
	vp.add_child(light)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.5, 0.8, 1.0)
	vp.add_child(rim)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 3.6
	floor_mesh.bottom_radius = 3.6
	floor_mesh.height = 0.05
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.16, 0.25)
	fm.metallic = 0.4
	fm.roughness = 0.3
	floor_mi.material_override = fm
	floor_mi.position.y = -0.03
	vp.add_child(floor_mi)
	_preview_pivot = Node3D.new()
	_preview_pivot.rotation.y = 0.6
	vp.add_child(_preview_pivot)
	_preview_model = CarModel.new()
	_preview_pivot.add_child(_preview_model)
	_preview_model.build(CarDB.get_car(car_id), paint)
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	cam.position = Vector3(0, 2.2, 7.6)
	cam.look_at(Vector3(0, 0.55, 0))


func _car_row(parent: Control, back_to: String) -> void:
	var c := CarDB.get_car(Game.settings["car"])
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UITheme.label("Машина: %s  [%s]" % [c["name"], CarDB.CLASS_NAMES[c["class"]]], 26, Color(1, 0.92, 0.5))
	l.custom_minimum_size.x = 560
	row.add_child(l)
	var go := func():
		_garage_return = back_to
		open("garage")
	row.add_child(UITheme.button("Гараж", go, Vector2(180, 56)))


# ---------------------------------------------------------------- экраны

func _main() -> void:
	_set_title("NITRO RUSH", "  аркадные гонки")
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.add_child(hb)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(left)
	left.add_child(_accent_button("Гонка", open.bind("race"), 420))
	left.add_child(UITheme.button("Песочница", open.bind("sandbox"), Vector2(420, 66)))
	left.add_child(UITheme.button("Мультиплеер (Wi-Fi)", open.bind("mp"), Vector2(420, 66)))
	var garage := func():
		_garage_return = "main"
		open("garage")
	left.add_child(UITheme.button("Гараж", garage, Vector2(420, 66)))
	left.add_child(UITheme.button("Настройки", open.bind("settings"), Vector2(420, 66)))
	if OS.get_name() != "iOS":
		left.add_child(UITheme.button("Выход", get_tree().quit, Vector2(420, 56)))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	_preview(right, Game.settings["car"], int(Game.settings["paint"]))
	var c := CarDB.get_car(Game.settings["car"])
	var cl := UITheme.label("%s · %s · %d км/ч" % [c["name"], CarDB.CLASS_NAMES[c["class"]], int(c["top"])], 28)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(cl)
	var pl := UITheme.label("Пилот: %s" % Game.settings["player_name"], 22, Color(0.7, 0.75, 0.85))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(pl)


func _record_text(track_id: String, reverse: bool) -> String:
	var rec: Dictionary = Game.records.get(Game.record_key(track_id, reverse), {})
	if rec.is_empty():
		return "Рекорд круга: —"
	return "Рекорд круга: %s  (%s, %s)" % [Game.fmt_time(rec["time"]), rec["car"], rec["name"]]


func _race_setup() -> void:
	_set_title("Гонка", "  настройка заезда")
	var cfg: Dictionary = Game.last_race
	var vb := _scroll_box()
	var tracks := TrackDB.race_tracks()
	var names := []
	var tidx := 0
	for i in tracks.size():
		names.append(tracks[i]["name"])
		if tracks[i]["id"] == cfg["track"]:
			tidx = i
	cfg["track"] = tracks[tidx]["id"]
	var info := UITheme.label("", 22, Color(0.7, 0.8, 0.95))
	var refresh := func():
		var t := TrackDB.get_track(cfg["track"])
		info.text = "%s · %.1f км\n%s" % [t["desc"], _track_length(t), _record_text(cfg["track"], cfg["reverse"])]
	_selector(vb, "Трасса", names, tidx, func(i):
		cfg["track"] = tracks[i]["id"]
		refresh.call())
	_selector(vb, "Направление", ["Прямое", "Обратное"], 1 if cfg["reverse"] else 0, func(i):
		cfg["reverse"] = i == 1
		refresh.call())
	_selector(vb, "Кругов", _range_names(1, 10), int(cfg["laps"]) - 1, func(i): cfg["laps"] = i + 1)
	_selector(vb, "Соперники", _range_names(0, 7), int(cfg["opponents"]), func(i): cfg["opponents"] = i)
	_selector(vb, "Сложность", TrackDB.DIFFICULTY_NAMES, int(cfg["difficulty"]), func(i): cfg["difficulty"] = i)
	_selector(vb, "Время суток", TrackDB.TOD_NAMES, int(cfg["tod"]), func(i): cfg["tod"] = i)
	_selector(vb, "Столкновения", ["Выкл", "Вкл"], 1 if cfg["collisions"] else 0, func(i): cfg["collisions"] = i == 1)
	vb.add_child(info)
	refresh.call()
	_car_row(vb, "race")
	var bar := _bottom_bar()
	bar.add_child(UITheme.button("Назад", open.bind("main"), Vector2(200, 70)))
	bar.add_child(_accent_button("СТАРТ", Game.start_single_race))


var _len_cache := {}


func _track_length(t: Dictionary) -> float:
	if _len_cache.has(t["id"]):
		return _len_cache[t["id"]]
	var pts: Array = t["points"]
	var total := 0.0
	for i in pts.size():
		total += (pts[i] as Vector2).distance_to(pts[(i + 1) % pts.size()])
	# сплайн чуть длиннее ломаной
	total = total * 1.04 / 1000.0
	_len_cache[t["id"]] = total
	return total


func _sandbox_setup() -> void:
	_set_title("Песочница", "  свободная езда без правил")
	var cfg: Dictionary = Game.last_sandbox
	var vb := _scroll_box()
	var names := []
	var tidx := 0
	for i in TrackDB.TRACKS.size():
		names.append(TrackDB.TRACKS[i]["name"])
		if TrackDB.TRACKS[i]["id"] == cfg["track"]:
			tidx = i
	var info := UITheme.label("", 22, Color(0.7, 0.8, 0.95))
	var refresh := func():
		var t := TrackDB.get_track(cfg["track"])
		info.text = t["desc"] + "\nВ паузе можно сменить машину прямо на ходу. R — вернуться на трассу."
	_selector(vb, "Карта", names, tidx, func(i):
		cfg["track"] = TrackDB.TRACKS[i]["id"]
		refresh.call())
	_selector(vb, "Направление", ["Прямое", "Обратное"], 1 if cfg["reverse"] else 0, func(i): cfg["reverse"] = i == 1)
	_selector(vb, "Боты на трассе", _range_names(0, 7), int(cfg["opponents"]), func(i): cfg["opponents"] = i)
	_selector(vb, "Время суток", TrackDB.TOD_NAMES, int(cfg["tod"]), func(i): cfg["tod"] = i)
	vb.add_child(info)
	refresh.call()
	_car_row(vb, "sandbox")
	var bar := _bottom_bar()
	bar.add_child(UITheme.button("Назад", open.bind("main"), Vector2(200, 70)))
	bar.add_child(_accent_button("ПОЕХАЛИ", Game.start_sandbox))


func _garage() -> void:
	_set_title("Гараж", "  %d машин: спорт и гипер" % CarDB.CARS.size())
	_garage_sel = Game.settings["car"]
	_garage_paint = int(Game.settings["paint"])
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.add_child(hb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for cls in ["sport", "hyper"]:
		list.add_child(UITheme.label(CarDB.CLASS_NAMES[cls].to_upper(), 24, UITheme.ACCENT if cls == "sport" else UITheme.ACCENT2))
		for c in CarDB.cars_of_class(cls):
			var id: String = c["id"]
			var pick := func():
				_garage_sel = id
				_garage_paint = int(CarDB.get_car(id)["paint"])
				_update_garage()
			var b := UITheme.button(c["name"], pick, Vector2(330, 54))
			list.add_child(b)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	_preview(right, _garage_sel, _garage_paint)
	_garage_info = VBoxContainer.new()
	right.add_child(_garage_info)
	_update_garage()

	var bar := _bottom_bar()
	bar.add_child(UITheme.button("Назад", func(): open(_garage_return), Vector2(200, 70)))
	var choose := func():
		Game.settings["car"] = _garage_sel
		Game.settings["paint"] = _garage_paint
		Game.save_settings()
		Net.update_my_info()
		open(_garage_return)
	bar.add_child(_accent_button("ВЫБРАТЬ", choose))


func _update_garage() -> void:
	var c := CarDB.get_car(_garage_sel)
	if _preview_model:
		_preview_model.build(c, _garage_paint)
	for ch in _garage_info.get_children():
		ch.queue_free()
	var top := HBoxContainer.new()
	_garage_info.add_child(top)
	top.add_child(UITheme.label(c["name"], 34, Color.WHITE))
	top.add_child(UITheme.label("  " + CarDB.CLASS_NAMES[c["class"]], 26, UITheme.ACCENT if c["class"] == "sport" else UITheme.ACCENT2))
	var grid := GridContainer.new()
	grid.columns = 4
	_garage_info.add_child(grid)
	var t100 := CarDB.zero_to_100(c)
	var stats := [
		["Скорость", "%d км/ч" % int(c["top"]), (c["top"] - 200.0) / 240.0],
		["0-100", "%.1f с" % t100, (5.0 - t100) / 3.2],
		["Управление", "%.2f" % c["handling"], (c["handling"] - 1.3) / 0.75],
		["Сцепление", "%.2f g" % c["grip"], (c["grip"] - 1.7) / 1.1],
	]
	for s in stats:
		var l := UITheme.label(s[0], 20, Color(0.7, 0.75, 0.85))
		l.custom_minimum_size.x = 130
		grid.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = clampf(s[2], 0.05, 1.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
	var vals := HBoxContainer.new()
	_garage_info.add_child(vals)
	for s in stats:
		vals.add_child(UITheme.label("%s: %s   " % [s[0], s[1]], 20))
	var eng: Dictionary = EngineDB.ENGINES.get(c.get("engine", "v8x"), {})
	_garage_info.add_child(UITheme.label("Мотор: %s" % eng.get("name", "?"), 22, Color(1, 0.85, 0.45)))
	var paints := HBoxContainer.new()
	_garage_info.add_child(paints)
	for i in CarDB.PAINTS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = CarDB.PAINT_NAMES[i]
		var sb := UITheme.box(CarDB.PAINTS[i], Color.WHITE if i == _garage_paint else Color(0, 0, 0, 0.6), 22, 4 if i == _garage_paint else 2)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var idx := i
		b.pressed.connect(func():
			_garage_paint = idx
			_update_garage())
		paints.add_child(b)


func _settings() -> void:
	_set_title("Настройки")
	var s: Dictionary = Game.settings
	var vb := _scroll_box()
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
	_selector(vb, "Руль", ["Кнопки", "Наклон телефона"], int(s["steering"]), func(i): s["steering"] = i)
	var sens := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
	var sens_names := sens.map(func(v): return "x%.2f" % v)
	_selector(vb, "Чувствит. наклона", sens_names, maxi(0, sens.find(float(s["tilt_sens"]))), func(i): s["tilt_sens"] = sens[i])
	_selector(vb, "Инверсия наклона", ["Нет", "Да"], 1 if s["tilt_invert"] else 0, func(i): s["tilt_invert"] = i == 1)
	var calib := func():
		Game.tilt_zero = Input.get_accelerometer().x
		toast("Нулевое положение сохранено")
	vb.add_child(UITheme.button("Откалибровать наклон (держите телефон ровно)", calib, Vector2(0, 56)))
	_selector(vb, "Камера", ["Ближняя", "Дальняя", "С капота"], int(s["camera"]), func(i): s["camera"] = i)
	_selector(vb, "Тени", ["Выкл", "Вкл"], 1 if s["shadows"] else 0, func(i): s["shadows"] = i == 1)
	_selector(vb, "Звук", ["Выкл", "Вкл"], 1 if s["sound"] else 0, func(i):
		s["sound"] = i == 1
		Game.apply_audio())
	var vols := [0.2, 0.4, 0.6, 0.8, 1.0]
	var vol_names := vols.map(func(v): return "%d%%" % int(v * 100))
	var vi := 0
	for k in vols.size():
		if absf(float(vols[k]) - float(s["volume"])) < 0.05:
			vi = k
	_selector(vb, "Громкость", vol_names, vi, func(i):
		s["volume"] = vols[i]
		Game.apply_audio())
	_selector(vb, "Показывать FPS", ["Нет", "Да"], 1 if s["show_fps"] else 0, func(i): s["show_fps"] = i == 1)
	var bar := _bottom_bar()
	var back := func():
		Game.save_settings()
		open("main")
	bar.add_child(_accent_button("Готово", back, 220))


# ---------------------------------------------------------------- сеть

func _mp() -> void:
	_set_title("Мультиплеер", "  локальная сеть (Wi-Fi / точка доступа)")
	Net.leave()
	Net.start_discovery()
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.add_child(hb)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 560
	hb.add_child(left)
	var row := HBoxContainer.new()
	left.add_child(row)
	row.add_child(UITheme.label("Имя", 26))
	var name_edit := LineEdit.new()
	name_edit.text = Game.settings["player_name"]
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(420, 56)
	name_edit.text_changed.connect(func(t): Game.settings["player_name"] = t.strip_edges() if t.strip_edges() != "" else "Игрок")
	row.add_child(name_edit)
	var host := func():
		Game.save_settings()
		var err := Net.host_game()
		if err == OK:
			open("lobby")
		else:
			_status.text = "Не удалось создать игру (ошибка %d)" % err
	left.add_child(_accent_button("Создать игру", host, 540))
	left.add_child(UITheme.label("Подключиться по IP:", 24))
	var row2 := HBoxContainer.new()
	left.add_child(row2)
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "192.168.0.10"
	ip_edit.custom_minimum_size = Vector2(320, 56)
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	row2.add_child(ip_edit)
	row2.add_child(UITheme.button("Подключиться", func(): _join(ip_edit.text), Vector2(210, 56)))
	var ips := Net.local_ips()
	left.add_child(UITheme.label("Ваш IP: %s" % (", ".join(ips) if not ips.is_empty() else "нет сети"), 22, Color(0.7, 0.75, 0.85)))
	var help := UITheme.label("Все телефоны должны быть в одной Wi-Fi сети или подключены\nк точке доступа одного из них. На iPhone разрешите\n«Локальная сеть» для игры в настройках.", 18, Color(0.6, 0.65, 0.75))
	left.add_child(help)
	_status = UITheme.label("", 22, Color(1, 0.85, 0.4))
	left.add_child(_status)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(UITheme.label("Найденные игры", 28, UITheme.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	_hosts_box = VBoxContainer.new()
	_hosts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_hosts_box)
	_refresh_hosts()

	var bar := _bottom_bar()
	bar.add_child(UITheme.button("Назад", open.bind("main"), Vector2(200, 70)))


func _join(ip: String) -> void:
	if ip.strip_edges() == "":
		_status.text = "Введите IP хоста"
		return
	Game.save_settings()
	var err := Net.join_game(ip)
	if err != OK:
		_status.text = "Ошибка подключения (%d)" % err
	else:
		_status.text = "Подключение к %s..." % ip


func _refresh_hosts() -> void:
	if _screen != "mp" or _hosts_box == null or not is_instance_valid(_hosts_box):
		return
	for c in _hosts_box.get_children():
		c.queue_free()
	if Net.hosts.is_empty():
		_hosts_box.add_child(UITheme.label("Поиск игр в сети...", 22, Color(0.6, 0.65, 0.75)))
		return
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		var text := "%s  (%d/8)  %s" % [h["name"], h["count"], "идёт гонка" if h["racing"] else ip]
		var b := UITheme.button(text, _join.bind(ip), Vector2(0, 60))
		b.disabled = h["racing"]
		_hosts_box.add_child(b)


func _on_connection_result(ok: bool, message: String) -> void:
	if _screen != "mp":
		return
	if ok:
		open("lobby")
	elif _status:
		_status.text = message


func _lobby() -> void:
	var ips := Net.local_ips()
	if Net.is_host():
		_set_title("Лобби", "  вы хост · IP: %s" % (", ".join(ips) if not ips.is_empty() else "?"))
	else:
		_set_title("Лобби", "  ожидание старта от хоста")
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.add_child(hb)
	var lp := PanelContainer.new()
	lp.custom_minimum_size.x = 470
	hb.add_child(lp)
	_lobby_players = VBoxContainer.new()
	lp.add_child(_lobby_players)
	var rp := VBoxContainer.new()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(rp)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(scroll)
	_lobby_cfg = VBoxContainer.new()
	_lobby_cfg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lobby_cfg)
	_car_row(rp, "lobby")
	_on_players_changed()
	_build_lobby_cfg()

	var bar := _bottom_bar()
	var leave := func():
		Net.leave()
		open("mp")
	bar.add_child(UITheme.button("Выйти", leave, Vector2(200, 70)))
	if Net.is_host():
		bar.add_child(_accent_button("СТАРТ ГОНКИ", Net.start_race, 300))


func _on_players_changed() -> void:
	if _screen != "lobby" or _lobby_players == null or not is_instance_valid(_lobby_players):
		return
	for c in _lobby_players.get_children():
		c.queue_free()
	_lobby_players.add_child(UITheme.label("Игроки (%d/%d)" % [Net.players.size(), Net.MAX_PLAYERS], 28, UITheme.ACCENT))
	var me := Net.my_id()
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var c := CarDB.get_car(p["car"])
		var tag := ""
		if id == 1:
			tag += " ★"
		if id == me:
			tag += " (вы)"
		_lobby_players.add_child(UITheme.label("%s%s" % [p["name"], tag], 26, Color.WHITE if id != me else Color(1, 0.9, 0.4)))
		_lobby_players.add_child(UITheme.label("    %s · %s" % [c["name"], CarDB.CLASS_NAMES[c["class"]]], 20, Color(0.7, 0.75, 0.85)))


func _on_config_changed() -> void:
	if _screen == "lobby" and not Net.is_host():
		_build_lobby_cfg()


func _build_lobby_cfg() -> void:
	if _lobby_cfg == null or not is_instance_valid(_lobby_cfg):
		return
	for c in _lobby_cfg.get_children():
		c.queue_free()
	var cfg: Dictionary = Net.config.duplicate()
	if cfg.is_empty():
		_lobby_cfg.add_child(UITheme.label("Получение настроек...", 22))
		return
	var tracks := TrackDB.race_tracks()
	if Net.is_host():
		var names := []
		var tidx := 0
		for i in tracks.size():
			names.append(tracks[i]["name"])
			if tracks[i]["id"] == cfg["track"]:
				tidx = i
		var push := func(key: String, value):
			cfg[key] = value
			Net.set_config(cfg.duplicate())
		_selector(_lobby_cfg, "Трасса", names, tidx, func(i): push.call("track", tracks[i]["id"]))
		_selector(_lobby_cfg, "Направление", ["Прямое", "Обратное"], 1 if cfg["reverse"] else 0, func(i): push.call("reverse", i == 1))
		_selector(_lobby_cfg, "Кругов", _range_names(1, 10), int(cfg["laps"]) - 1, func(i): push.call("laps", i + 1))
		_selector(_lobby_cfg, "Боты", _range_names(0, 6), int(cfg["opponents"]), func(i): push.call("opponents", i))
		_selector(_lobby_cfg, "Сложность ботов", TrackDB.DIFFICULTY_NAMES, int(cfg["difficulty"]), func(i): push.call("difficulty", i))
		_selector(_lobby_cfg, "Время суток", TrackDB.TOD_NAMES, int(cfg["tod"]), func(i): push.call("tod", i))
		_selector(_lobby_cfg, "Столкновения", ["Выкл", "Вкл"], 1 if cfg["collisions"] else 0, func(i): push.call("collisions", i == 1))
	else:
		var t := TrackDB.get_track(cfg["track"])
		var lines := [
			"Трасса: %s (%s)" % [t["name"], "обратное" if cfg["reverse"] else "прямое"],
			"Кругов: %d" % int(cfg["laps"]),
			"Боты: %d · %s" % [int(cfg["opponents"]), TrackDB.DIFFICULTY_NAMES[int(cfg["difficulty"])]],
			"Время суток: %s" % TrackDB.TOD_NAMES[int(cfg["tod"])],
			"Столкновения: %s" % ("вкл" if cfg["collisions"] else "выкл"),
		]
		_lobby_cfg.add_child(UITheme.label("Настройки гонки", 28, UITheme.ACCENT))
		for l in lines:
			_lobby_cfg.add_child(UITheme.label(l, 26))
