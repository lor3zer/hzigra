class_name HUD
extends CanvasLayer

var race: Race
var touch: TouchControls
var minimap: Minimap

var _pos_label: Label
var _lap_label: Label
var _time_label: Label
var _best_label: Label
var _speed_label: Label
var _unit_label: Label
var _nitro_bar: ProgressBar
var _rpm_bar: ProgressBar
var _rpm_fill: StyleBoxFlat
var _gear_label: Label
var _center_label: Label
var _msg_label: Label
var _wrong_label: Label
var _fps_label: Label
var _root: Control
var _overlay: Control
var _results_grid: GridContainer
var _results_timer := 0.0
var _msg_time := 0.0
var _center_time := 0.0


func setup(r: Race) -> void:
	race = r
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UITheme.make()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	touch = TouchControls.new()
	touch.show_steer = int(Game.settings["steering"]) == 0
	_root.add_child(touch)

	var is_race := race.mode == "race"
	_pos_label = _lbl(54, Color.WHITE, 0, 0, 24, 14, 260, 64)
	_lap_label = _lbl(28, Color(0.8, 0.9, 1.0), 0, 0, 26, 78, 300, 40)
	_pos_label.visible = is_race
	if not is_race:
		_lap_label.position.y = 20
	_time_label = _lbl(34, Color.WHITE, 0.5, 0, -170, 14, 340, 44)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label = _lbl(22, Color(0.75, 0.85, 1.0), 0.5, 0, -220, 56, 440, 32)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label = _lbl(64, Color.WHITE, 0.5, 1, -110, -150, 220, 76)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit_label = _lbl(22, Color(0.75, 0.85, 1.0), 0.5, 1, -110, -80, 220, 28)
	_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit_label.text = "км/ч"
	_gear_label = _lbl(52, Color(1, 0.85, 0.3), 0.5, 1, -190, -138, 70, 66)
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rpm_bar = ProgressBar.new()
	_rpm_bar.max_value = 1.0
	_rpm_bar.show_percentage = false
	_rpm_fill = StyleBoxFlat.new()
	_rpm_fill.bg_color = Color(1, 0.85, 0.3)
	_rpm_fill.set_corner_radius_all(4)
	_rpm_bar.add_theme_stylebox_override("fill", _rpm_fill)
	_place(_rpm_bar, 0.5, 1, -150, -160, 300, 10)
	_root.add_child(_rpm_bar)
	_nitro_bar = ProgressBar.new()
	_nitro_bar.max_value = 100.0
	_nitro_bar.show_percentage = false
	_place(_nitro_bar, 0.5, 1, -110, -46, 220, 14)
	_root.add_child(_nitro_bar)
	_center_label = _lbl(110, Color(1, 0.9, 0.2), 0.5, 0.5, -400, -160, 800, 140)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label = _lbl(36, Color.WHITE, 0.5, 0.5, -400, -20, 800, 50)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong_label = _lbl(44, Color(1, 0.3, 0.3), 0.5, 0.5, -400, 40, 800, 60)
	_wrong_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong_label.text = "НЕ ТУДА!"
	_wrong_label.visible = false
	_fps_label = _lbl(18, Color(0.7, 1, 0.7), 0, 1, 24, -30, 200, 24)
	_fps_label.visible = bool(Game.settings["show_fps"])

	# кнопки справа сверху
	var pause_btn := UITheme.button("II", toggle_pause, Vector2(76, 64))
	_place(pause_btn, 1, 0, -96, 14, 76, 64)
	_root.add_child(pause_btn)
	var cam_btn := UITheme.button("CAM", race.cycle_camera, Vector2(96, 64))
	cam_btn.add_theme_font_size_override("font_size", 20)
	_place(cam_btn, 1, 0, -204, 14, 96, 64)
	_root.add_child(cam_btn)
	var resp_btn := UITheme.button("R", race.respawn_player, Vector2(64, 64))
	_place(resp_btn, 1, 0, -280, 14, 64, 64)
	_root.add_child(resp_btn)

	minimap = Minimap.new()
	_place(minimap, 1, 0, -224, 92, 204, 204)
	minimap.size = Vector2(204, 204)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(minimap)
	minimap.setup(race)


func _place(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


func _lbl(font_size: int, color: Color, ax: float, ay: float, x: float, y: float, w: float, h: float) -> Label:
	var l := UITheme.label("", font_size, color)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, ax, ay, x, y, w, h)
	_root.add_child(l)
	return l


func set_countdown(n: int) -> void:
	_center_label.text = str(n)
	_center_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2) if n > 1 else Color(1, 0.85, 0.1))
	_center_time = 0.9


func flash(text: String, color := Color(0.3, 1.0, 0.4), big := false) -> void:
	if big:
		_center_label.text = text
		_center_label.add_theme_color_override("font_color", color)
		_center_time = 1.2
	else:
		_msg_label.text = text
		_msg_label.add_theme_color_override("font_color", color)
		_msg_time = 2.2


func _process(dt: float) -> void:
	if race == null:
		return
	_msg_time -= dt
	_center_time -= dt
	_msg_label.visible = _msg_time > 0.0
	_center_label.visible = _center_time > 0.0
	_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	var p := race.player
	if p == null:
		return
	touch.nitro_level = p.nitro
	_speed_label.text = str(int(absf(p.speed) * 3.6))
	_nitro_bar.value = p.nitro
	var rl: float = p.eng["redline"]
	var r := clampf(p.rpm / rl, 0.0, 1.0)
	_rpm_bar.value = r
	_rpm_fill.bg_color = Color(1, 0.2, 0.15) if r > 0.92 else (Color(1, 0.6, 0.2) if r > 0.8 else Color(1, 0.85, 0.3))
	if int(p.eng["gears"]) <= 1:
		_gear_label.text = "D"
	elif p.speed < -0.5 and p.in_brake > 0.1:
		_gear_label.text = "R"
	else:
		_gear_label.text = str(p.gear)
	_wrong_label.visible = p.wrong_way > 1.2 and race.mode == "race"
	var t := race.race_time
	if race.mode == "race":
		var st := race.standings()
		_pos_label.text = "%d/%d" % [st.find(p) + 1, st.size()]
		_lap_label.text = "Круг %d/%d" % [clampi(p.lap, 1, race.laps), race.laps]
		if p.finished:
			_time_label.text = Game.fmt_time(p.finish_time)
		else:
			_time_label.text = Game.fmt_time(t) if race.state != "countdown" else "0:00.000"
	else:
		_lap_label.text = "Песочница · %s" % p.def["name"]
		_time_label.text = Game.fmt_time(t - p.lap_start) if p.max_lap >= 1 else "--:--.---"
	_best_label.text = "Посл. %s   Лучш. %s" % [Game.fmt_time(p.last_lap), Game.fmt_time(p.best_lap)]

	if _results_grid and is_instance_valid(_results_grid):
		_results_timer -= dt
		if _results_timer <= 0.0:
			_results_timer = 0.5
			_fill_results()


# ---------------------------------------------------------------- оверлеи

func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	_results_grid = null


func _make_overlay(title: String) -> VBoxContainer:
	_close_overlay()
	touch.reset()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	panel.add_child(vb)
	var tl := UITheme.label(title, 40, UITheme.ACCENT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	return vb


func toggle_pause() -> void:
	if _overlay and _results_grid == null:
		_resume()
		return
	if _results_grid:
		return
	_open_pause()


func _open_pause() -> void:
	var vb := _make_overlay("Пауза")
	if not race.net:
		get_tree().paused = true
	vb.add_child(UITheme.button("Продолжить", _resume))
	if race.mode == "sandbox":
		vb.add_child(UITheme.button("Сменить машину", show_car_select))
	if not race.net:
		vb.add_child(UITheme.button("Рестарт", race.restart))
	var back_on_track := func():
		_resume()
		race.respawn_player()
	vb.add_child(UITheme.button("Вернуть на трассу", back_on_track))
	vb.add_child(UITheme.button("Выйти из сети" if race.net else "В меню", race.quit_to_menu))


func _resume() -> void:
	_close_overlay()
	get_tree().paused = false


func show_car_select() -> void:
	var vb := _make_overlay("Машина")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for c in CarDB.CARS:
		var id: String = c["id"]
		var pick := func():
			race.change_player_car(id)
			_resume()
		var b := UITheme.button("%s  [%s]" % [c["name"], CarDB.CLASS_NAMES[c["class"]]], pick, Vector2(360, 58))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	vb.add_child(UITheme.button("Назад", _open_pause))


func show_results() -> void:
	get_tree().paused = false
	var vb := _make_overlay("Результаты")
	_results_grid = GridContainer.new()
	_results_grid.columns = 4
	vb.add_child(_results_grid)
	_fill_results()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	if race.net:
		if Net.is_host() or Net.is_leader():
			row.add_child(UITheme.button("В лобби", Net.return_to_lobby, Vector2(240, 64)))
		elif Net.remote_dedicated:
			row.add_child(UITheme.label("Сервер вернёт в лобби сам", 22))
		else:
			row.add_child(UITheme.label("Ждём хоста...", 22))
		row.add_child(UITheme.button("Выйти", race.quit_to_menu, Vector2(200, 64)))
	else:
		row.add_child(UITheme.button("Ещё раз", race.restart, Vector2(240, 64)))
		row.add_child(UITheme.button("В меню", race.quit_to_menu, Vector2(200, 64)))


func _fill_results() -> void:
	for c in _results_grid.get_children():
		c.queue_free()
	for h in ["#", "Пилот", "Машина", "Время"]:
		_results_grid.add_child(UITheme.label(h, 22, UITheme.ACCENT))
	var st := race.standings()
	for i in st.size():
		var car: Car = st[i]
		var col := Color(1, 0.9, 0.3) if car == race.player else Color.WHITE
		_results_grid.add_child(UITheme.label(str(i + 1), 24, col))
		_results_grid.add_child(UITheme.label(car.driver_name, 24, col))
		_results_grid.add_child(UITheme.label(car.def["name"], 22, col))
		var tt := "едет..."
		if car.finished:
			tt = Game.fmt_time(car.finish_time)
		elif not race.net:
			tt = "~" + Game.fmt_time(race.estimate_finish(car))
		_results_grid.add_child(UITheme.label(tt, 24, col))
