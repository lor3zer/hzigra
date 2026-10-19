class_name Race
extends Node3D

## Сцена заезда: трасса, машины, камера, правила гонки и сетевой обмен.

var config: Dictionary
var grid: Array
var track: Track
var cars: Array = []
var cars_by_id := {}
var player: Car
var drivers := {}          # id машины -> AIDriver
var camera: Camera3D
var hud: HUD
var ui_sound: AudioStreamPlayer
var headlight: SpotLight3D

var mode := "race"
var net := false
var laps := 3
var state := "countdown"
var countdown := 3.6
var race_time := 0.0
var cam_mode := 0
var _cam_yaw := 0.0
var _send_timer := 0.0
var _last_count := 0
var _results_pending := false


func setup(c: Dictionary, g: Array) -> void:
	config = c
	grid = g
	mode = c["mode"]
	net = bool(c.get("net", false))
	laps = int(c.get("laps", 3))
	cam_mode = int(Game.settings["camera"])

	track = Track.new()
	add_child(track)
	track.build(TrackDB.get_track(c["track"]), bool(c["reverse"]), int(c["tod"]), bool(Game.settings["shadows"]))

	var my_id := Net.my_id() if net else 1
	var skill := Game.difficulty_skill(int(c.get("difficulty", 1)))
	for slot in grid.size():
		var e: Dictionary = grid[slot]
		var car := Car.new()
		add_child(car)
		car.setup(CarDB.get_car(e["car"]), int(e["paint"]), track)
		car.peer_id = int(e["id"])
		car.driver_name = str(e["name"])
		var gs := track.grid_slot(slot)
		car.place(gs["pos"], gs["yaw"])
		var is_ai := bool(e["ai"])
		if not is_ai and car.peer_id == my_id:
			car.ctrl = Car.Ctrl.PLAYER
			player = car
		elif is_ai and (not net or Net.is_host()):
			car.ctrl = Car.Ctrl.AI
			var sk := skill * randf_range(0.96, 1.0) if mode == "race" else randf_range(0.82, 0.92)
			drivers[car.peer_id] = AIDriver.new(car, track, sk, cars)
		else:
			car.ctrl = Car.Ctrl.REMOTE
		if car != player and (net or mode == "race"):
			car.show_name(car.driver_name)
		car.lap_completed.connect(_on_lap)
		cars.append(car)
		cars_by_id[car.peer_id] = car

	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	if player:
		_cam_yaw = player.yaw
		_attach_headlight()

	for car in cars:
		var snd := EngineSound.new()
		car.add_child(snd)
		car.sound = snd
		snd.setup(car, car == player)
	ui_sound = AudioStreamPlayer.new()
	add_child(ui_sound)

	hud = HUD.new()
	add_child(hud)
	hud.setup(self)

	Net.finish_reported.connect(_on_finish_reported)
	if net:
		Net.remote_state.connect(_on_remote_state)
		Net.ai_states.connect(_on_ai_states)
		Net.peer_left.connect(_on_peer_left)

	if mode == "sandbox":
		state = "racing"
		countdown = 0.0
		hud.flash("Свободная езда", Color(0.3, 0.9, 1.0), true)
	_update_camera(1.0)


func _attach_headlight() -> void:
	if int(config["tod"]) != 2 or player == null:
		return
	if headlight:
		headlight.queue_free()
	headlight = SpotLight3D.new()
	headlight.light_energy = 6.0
	headlight.spot_range = 80.0
	headlight.spot_angle = 32.0
	headlight.light_color = Color(1.0, 0.95, 0.85)
	headlight.position = Vector3(0, 0.8, -player.def["len"] * 0.5)
	headlight.rotation_degrees.x = -6.0
	player.add_child(headlight)


# ---------------------------------------------------------------- цикл

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
	elif event.is_action_pressed("respawn"):
		respawn_player()
	elif event.is_action_pressed("camera"):
		cycle_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud:
		hud.toggle_pause()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if state == "countdown":
		countdown -= dt
		var n := ceili(countdown)
		if n != _last_count and n <= 3 and n > 0:
			_last_count = n
			hud.set_countdown(n)
			_ui("beep")
		if countdown <= 0.0:
			state = "racing"
			race_time = 0.0
			hud.flash("СТАРТ!", Color(0.3, 1.0, 0.4), true)
			_ui("go")
	var frozen := state == "countdown"
	if not frozen:
		race_time += dt

	if player and player.ctrl == Car.Ctrl.PLAYER:
		_player_input()
	if not frozen:
		for id in drivers:
			drivers[id].update(dt)
	else:
		# боты газуют на старте
		var tt := countdown * 3.0
		for id in drivers:
			var c: Car = drivers[id].car
			c.in_throttle = clampf(0.35 + 0.65 * sin(tt + float(id) * 1.7) * sin(tt * 0.37 + float(id)), 0.0, 1.0)

	for car in cars:
		if car.ctrl == Car.Ctrl.REMOTE:
			car.update_remote(dt)
		else:
			car.simulate(dt, race_time, frozen)
	if bool(config.get("collisions", true)):
		_collide()
	if track.is_open:
		_collide_cones()

	_net_send(dt)
	_update_camera(dt)


func _ui(name: String) -> void:
	ui_sound.stream = EngineSound.stream(name, false)
	ui_sound.play()


func _player_input() -> void:
	var tc := hud.touch
	var thr := maxf(Input.get_action_strength("accelerate"), tc.gas)
	var brk := maxf(Input.get_action_strength("brake"), tc.brake)
	var st := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if int(Game.settings["steering"]) == 1:
		var ax := Input.get_accelerometer().x - Game.tilt_zero
		var sens := float(Game.settings["tilt_sens"])
		if bool(Game.settings["tilt_invert"]):
			ax = -ax
		st += clampf(ax / 4.5 * sens, -1.0, 1.0)
	else:
		st += tc.steer
	player.in_throttle = clampf(thr, 0.0, 1.0)
	player.in_brake = clampf(brk, 0.0, 1.0)
	player.in_steer = clampf(st, -1.0, 1.0)
	player.in_nitro = Input.is_action_pressed("nitro") or tc.nitro


func _update_camera(dt: float) -> void:
	if player == null:
		return
	var fwd := player.forward()
	var k := 1.0 - exp(-5.0 * dt)
	_cam_yaw = lerp_angle(_cam_yaw, player.yaw, k)
	var cam_fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
	var shake := Vector3.ZERO
	if player.wall_hit > 0.0:
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * player.wall_hit * 0.25
	var spd := clampf(absf(player.speed) / player.top_speed, 0.0, 1.0)
	match cam_mode:
		2:
			camera.position = player.position + Vector3(0, 1.15, 0) + fwd * 0.2
			camera.look_at(camera.position + fwd * 10.0 + Vector3(0, -0.3, 0))
		_:
			var dist := 7.0 if cam_mode == 0 else 11.0
			var height := 2.4 if cam_mode == 0 else 3.8
			dist += spd * 1.5
			camera.position = player.position - cam_fwd * dist + Vector3(0, height, 0) + shake
			camera.look_at(player.position + fwd * 4.0 + Vector3(0, 1.0, 0))
	var fov := 68.0 + spd * 16.0 + (6.0 if player.nitro_active else 0.0)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-3.0 * dt))


# ---------------------------------------------------------------- столкновения

func _collide() -> void:
	var n := cars.size()
	for a in n:
		for b in range(a + 1, n):
			var ca: Car = cars[a]
			var cb: Car = cars[b]
			var move_a := ca.ctrl != Car.Ctrl.REMOTE
			var move_b := cb.ctrl != Car.Ctrl.REMOTE
			if not move_a and not move_b:
				continue
			if ca.position.distance_squared_to(cb.position) > 64.0:
				continue
			var la: float = ca.def["len"] * 0.25
			var lb: float = cb.def["len"] * 0.25
			var ra: float = ca.def["wid"] * 0.52
			var rb: float = cb.def["wid"] * 0.52
			var ma: float = ca.def["mass"]
			var mb: float = cb.def["mass"]
			for oa: float in [-1.0, 1.0]:
				for ob: float in [-1.0, 1.0]:
					var pa := ca.position + ca.forward() * oa * la
					var pb := cb.position + cb.forward() * ob * lb
					var d := pb - pa
					d.y = 0.0
					var dist := d.length()
					if dist >= ra + rb or dist < 0.001:
						continue
					var nrm := d / dist
					var overlap := ra + rb - dist
					var wa := mb / (ma + mb) if move_b else 1.0
					var wb := ma / (ma + mb) if move_a else 1.0
					if move_a:
						ca.position -= nrm * overlap * wa
					if move_b:
						cb.position += nrm * overlap * wb
					var rv := (cb.vel - ca.vel).dot(nrm)
					if rv < 0.0:
						var j := -1.3 * rv / (1.0 / ma + 1.0 / mb)
						if rv < -2.5:
							var strength := clampf(-rv / 15.0, 0.15, 1.0)
							if ca.sound and (ca == player or cb != player):
								ca.sound.impact(strength)
							elif cb.sound:
								cb.sound.impact(strength)
						if move_a:
							ca.vel -= nrm * j / ma
						if move_b:
							cb.vel += nrm * j / mb


func _collide_cones() -> void:
	for car in cars:
		if car.ctrl == Car.Ctrl.REMOTE:
			continue
		var r: float = car.def["wid"] * 0.5 + 0.35
		for cone in track.cones:
			var d: Vector3 = car.position - cone
			d.y = 0.0
			var dist := d.length()
			if dist < r and dist > 0.001:
				var nrm := d / dist
				car.position += nrm * (r - dist)
				var vn: float = car.vel.dot(nrm)
				if vn < 0.0:
					car.vel -= nrm * vn * 1.4
					car.wall_hit = 0.3


# ---------------------------------------------------------------- правила

func standings() -> Array:
	var arr := cars.duplicate()
	arr.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_time < b.finish_time
		return a.race_dist > b.race_dist)
	return arr


func estimate_finish(car: Car) -> float:
	if car.finished:
		return car.finish_time
	var total := laps * track.length
	var avg := maxf(car.race_dist, 1.0) / maxf(race_time, 1.0)
	return race_time + maxf(total - car.race_dist, 0.0) / maxf(avg, 5.0)


func _on_lap(car: Car, lap_time: float, is_best: bool) -> void:
	if car == player:
		var reverse := bool(config["reverse"])
		if Game.submit_lap(config["track"], reverse, lap_time, car.def["name"]):
			hud.flash("РЕКОРД ТРАССЫ! %s" % Game.fmt_time(lap_time), Color(1, 0.85, 0.2))
		elif is_best:
			hud.flash("Лучший круг %s" % Game.fmt_time(lap_time), Color(0.3, 1, 0.4))
		else:
			hud.flash("Круг %s" % Game.fmt_time(lap_time), Color.WHITE)
		if mode == "race" and car.lap == laps and not car.finished:
			hud.flash("ПОСЛЕДНИЙ КРУГ", Color(1, 0.6, 0.2), true)
	if mode == "race" and car.lap > laps and not car.finished and car.ctrl != Car.Ctrl.REMOTE:
		if car == player or not net or Net.is_host():
			Net.report_finish(car.peer_id, race_time)


func _on_finish_reported(id: int, time: float) -> void:
	var car: Car = cars_by_id.get(id)
	if car == null or car.finished:
		return
	car.finished = true
	car.finish_time = time
	if car == player:
		var place := standings().find(player) + 1
		hud.flash("ФИНИШ! %d место" % place, Color(1, 0.85, 0.2), true)
		# дальше машину ведёт автопилот
		player.ctrl = Car.Ctrl.AI
		drivers[player.peer_id] = AIDriver.new(player, track, 0.85, cars)
		if not _results_pending:
			_results_pending = true
			get_tree().create_timer(2.5).timeout.connect(hud.show_results)


func respawn_player() -> void:
	if player and state != "countdown" and player.ctrl == Car.Ctrl.PLAYER:
		player.respawn()
		_cam_yaw = player.yaw


func cycle_camera() -> void:
	cam_mode = (cam_mode + 1) % 3
	Game.settings["camera"] = cam_mode
	Game.save_settings()


func change_player_car(id: String) -> void:
	if player == null:
		return
	var paint := int(Game.settings["paint"])
	player.set_def(CarDB.get_car(id), paint)
	Game.settings["car"] = id
	Game.save_settings()
	_attach_headlight()
	for d in drivers.values():
		d.build_profile()


func restart() -> void:
	get_tree().paused = false
	Game.main.start_race(config, grid)


func quit_to_menu() -> void:
	get_tree().paused = false
	if net:
		Net.leave()
		Game.main.show_menu("mp")
	else:
		Game.main.show_menu("main")


# ---------------------------------------------------------------- сеть

func _net_send(dt: float) -> void:
	if not net:
		return
	_send_timer -= dt
	if _send_timer > 0.0:
		return
	_send_timer = 0.05
	if player:
		Net.send_state(player.net_state())
	if Net.is_host():
		var states := []
		for id in drivers:
			if id < 0:
				var s: Array = [id]
				s.append_array(drivers[id].car.net_state())
				states.append(s)
		if not states.is_empty():
			Net.send_ai_states(states)


func _on_remote_state(id: int, s: Array) -> void:
	var car: Car = cars_by_id.get(id)
	if car and car.ctrl == Car.Ctrl.REMOTE and s.size() >= 9:
		car.apply_net_state(s)


func _on_ai_states(states: Array) -> void:
	for s in states:
		if not (s is Array) or s.size() < 10:
			continue
		var car: Car = cars_by_id.get(int(s[0]))
		if car and car.ctrl == Car.Ctrl.REMOTE:
			car.apply_net_state(s.slice(1))


func _on_peer_left(id: int) -> void:
	var car: Car = cars_by_id.get(id)
	if car == null:
		return
	hud.flash("%s покинул гонку" % car.driver_name, Color(1, 0.6, 0.3))
	cars.erase(car)
	cars_by_id.erase(id)
	car.queue_free()
