class_name Car
extends Node3D

## Аркадная физика машины на плоскости. Управляется игроком, ИИ
## или состоянием, пришедшим по сети (REMOTE).

enum Ctrl { PLAYER, AI, REMOTE }

signal lap_completed(car: Car, lap_time: float, is_best: bool)
signal shifted(up: bool)

var def: Dictionary
var paint := 0
var ctrl := Ctrl.PLAYER
var peer_id := 0
var driver_name := ""
var track: Track
var model: CarModel
var name_label: Label3D
var sound: EngineSound
var eng: Dictionary

var yaw := 0.0
var vel := Vector3.ZERO
var speed := 0.0
var steer := 0.0
var top_speed := 70.0
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_nitro := false
var nitro := 100.0
var nitro_active := false
var offroad := false
var wall_hit := 0.0
var lat_acc := 0.0
var lon_acc := 0.0
var slip := 0.0            # 0..1 — насколько шины на пределе (для визга)

# трансмиссия
var rpm := 900.0
var gear := 1
var limiter := false
var throttle_level := 0.0  # сглаженный газ
var _shift_timer := 0.0

var seg := 0
var progress := 0.0
var lateral := 0.0
var lap := 0
var max_lap := 0
var race_dist := 0.0
var lap_start := 0.0
var last_lap := 0.0
var best_lap := 0.0
var finished := false
var finish_time := 0.0
var wrong_way := 0.0

# сетевая интерполяция
var net_pos := Vector3.ZERO
var net_vel := Vector3.ZERO
var net_yaw := 0.0
var net_steer := 0.0
var net_age := 0.0
var net_nitro := false
var net_throttle := 0.0


func setup(d: Dictionary, p: int, t: Track) -> void:
	track = t
	set_def(d, p)


func set_def(d: Dictionary, p: int) -> void:
	def = d
	paint = p
	top_speed = d["top"] / 3.6
	eng = EngineDB.ENGINES.get(d.get("engine", "v8x"), EngineDB.ENGINES["v8x"])
	rpm = eng["idle"]
	gear = 1
	if model:
		model.queue_free()
	model = CarModel.new()
	add_child(model)
	model.build(def, paint)
	if sound:
		sound.refresh()


func show_name(text: String) -> void:
	if name_label == null:
		name_label = Label3D.new()
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.font_size = 48
		name_label.pixel_size = 0.01
		name_label.visibility_range_end = 120.0
		name_label.outline_size = 12
		name_label.no_depth_test = true
		name_label.position = Vector3(0, 2.3, 0)
		add_child(name_label)
	name_label.text = text


func place(pos: Vector3, y: float) -> void:
	position = pos
	yaw = y
	rotation.y = yaw
	vel = Vector3.ZERO
	speed = 0.0
	steer = 0.0
	var info := track.project(pos, -1)
	seg = info["idx"]
	progress = info["dist"]
	lateral = info["lat"]
	net_pos = pos
	net_yaw = y
	_update_race_dist()


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func respawn() -> void:
	var i := seg
	var p := track.pts[i]
	place(p, Track.yaw_from_dir(track.tangents[i]))


## Один шаг физики. frozen — стоим на старте (можно газовать, но не ехать).
func simulate(dt: float, time: float, frozen: bool) -> void:
	var max_v := top_speed
	var acc: float = def["accel"]
	var handling: float = def["handling"]
	var grip: float = def["grip"]
	var brake: float = def["brake"]
	nitro_active = in_nitro and nitro > 1.0 and in_throttle > 0.1 and not frozen
	if nitro_active:
		max_v *= 1.12
		acc *= 1.6
		nitro = maxf(0.0, nitro - 28.0 * dt)
	else:
		nitro = minf(100.0, nitro + 4.0 * dt)
	if offroad:
		max_v *= 0.45

	var target_steer := clampf(in_steer, -1.0, 1.0)
	steer = move_toward(steer, target_steer, 5.0 * dt)
	if frozen:
		vel = Vector3.ZERO
		speed = 0.0
		slip = 0.0
		_update_drivetrain(dt, in_throttle, true)
		model.animate(dt, 0.0, steer, 0.0, 0.0, in_brake > 0.1, false)
		return

	var fwd := forward()
	var rgt := right()
	var vf := vel.dot(fwd)
	var vr := vel.dot(rgt)
	var vf0 := vf

	# двигатель
	if in_throttle > 0.01:
		var ratio := clampf(vf / max_v, 0.0, 1.2)
		vf += acc * in_throttle * maxf(0.0, 1.0 - ratio * ratio) * dt
	# тормоз / задний ход
	if in_brake > 0.01:
		if vf > 0.5:
			vf = maxf(vf - brake * in_brake * dt, 0.0)
		else:
			vf = maxf(vf - acc * 0.6 * in_brake * dt, -top_speed * 0.22)
	# сопротивление
	if in_throttle < 0.01 and in_brake < 0.01:
		vf = move_toward(vf, 0.0, 2.2 * dt)
	vf -= vf * (0.012 + (0.9 if offroad else 0.0)) * dt
	if vf > max_v:
		vf = move_toward(vf, max_v, (22.0 if offroad else 6.0) * dt)

	# поворот
	var sabs := absf(vf)
	var low := clampf(sabs / 6.0, 0.0, 1.0)
	var high := 1.0 - 0.45 * clampf(sabs / top_speed, 0.0, 1.0)
	var dir_sign := 1.0 if vf >= -0.1 else -1.0
	var yaw_rate := -steer * handling * low * high * dir_sign
	var a_lat_max: float = grip * 9.81 * (0.55 if offroad else 1.0)
	if sabs > 1.0:
		var max_rate := a_lat_max / sabs * 1.15
		yaw_rate = clampf(yaw_rate, -max_rate, max_rate)
	yaw += yaw_rate * dt

	# скорость частично "поворачивает" вслед за кузовом: небольшой занос
	var vel_world := fwd * vf + rgt * vr
	fwd = forward()
	rgt = right()
	vf = vel_world.dot(fwd)
	vr = vel_world.dot(rgt)
	var grip_k := 7.5 * grip / 2.2 * (0.5 if offroad else 1.0)
	vr = lerpf(vr, 0.0, 1.0 - exp(-grip_k * dt))
	vel = fwd * vf + rgt * vr
	lat_acc = yaw_rate * vf
	slip = clampf((absf(lat_acc) / a_lat_max - 0.8) * 4.0, 0.0, 1.0)
	if in_brake > 0.6 and vf > 18.0:
		slip = maxf(slip, 0.55 * in_brake)
	if offroad:
		slip = 0.0
	lon_acc = (vf - vf0) / maxf(dt, 0.001)
	speed = vf

	position += vel * dt
	rotation.y = yaw
	_update_drivetrain(dt, in_throttle, false)
	_constrain(dt)
	_update_progress(time, dt)
	model.animate(dt, speed, steer, lat_acc, lon_acc, in_brake > 0.1 and speed > 0.5, nitro_active)


func _constrain(dt: float) -> void:
	wall_hit = maxf(0.0, wall_hit - dt)
	var info := track.project(position, seg)
	seg = info["idx"]
	progress = info["dist"]
	lateral = info["lat"]
	if track.is_open:
		offroad = false
		var lim := track.half_size - 1.3
		for axis in [0, 2]:
			var v: float = position[axis]
			if absf(v) > lim:
				position[axis] = signf(v) * lim
				if vel[axis] * signf(v) > 0.0:
					vel[axis] = -vel[axis] * 0.3
					wall_hit = 0.3
		return
	offroad = absf(lateral) > track.half_width + 1.3
	var wid: float = def["wid"]
	var limit := track.wall_dist - wid * 0.5 - 0.1
	if absf(lateral) > limit:
		var n: Vector3 = info["normal"]
		var s := signf(lateral)
		position -= n * s * (absf(lateral) - limit)
		var vn := vel.dot(n * s)
		if vn > 0.0:
			vel -= n * s * vn * 1.3
			vel *= 0.97
			wall_hit = clampf(vn / 15.0, 0.2, 1.0)
		lateral = s * limit


func _update_progress(time: float, dt: float) -> void:
	var prev := race_dist
	_update_race_dist()
	# пересечение линии старта определяется по скачку прогресса
	var d := race_dist - prev
	if d < -track.length * 0.5:
		lap += 1
		_update_race_dist()
		if lap > max_lap:
			max_lap = lap
			if lap >= 2:
				last_lap = time - lap_start
				var is_best := best_lap == 0.0 or last_lap < best_lap
				if is_best:
					best_lap = last_lap
				lap_completed.emit(self, last_lap, is_best)
			lap_start = time
	elif d > track.length * 0.5:
		lap -= 1
		_update_race_dist()
	# движение против направления трассы
	var t := track.tangents[seg]
	if forward().dot(t) < -0.3 and speed > 4.0:
		wrong_way += dt
	else:
		wrong_way = 0.0


func _update_race_dist() -> void:
	race_dist = (lap - 1) * track.length + progress


# ---------------------------------------------------------------- трансмиссия

func _gear_top(g: int) -> float:
	return top_speed * 1.08 * pow(float(g) / float(eng["gears"]), 0.72)


## Обороты и автоматическое переключение передач (влияет только на звук и приборы).
func _update_drivetrain(dt: float, throttle: float, frozen: bool) -> void:
	throttle_level = move_toward(throttle_level, throttle, dt * 6.0)
	var redline: float = eng["redline"]
	var idle: float = eng["idle"]
	var gears: int = eng["gears"]
	var v := absf(speed)
	limiter = false
	var target: float
	if gears <= 1:
		# электромотор: обороты пропорциональны скорости
		target = maxf(500.0, v / top_speed * redline * 0.92)
		if frozen:
			target = 500.0 + throttle_level * 1200.0
	else:
		_shift_timer = maxf(0.0, _shift_timer - dt)
		var vmax_g := _gear_top(gear)
		target = redline * v / vmax_g
		if gear == 1 and v < vmax_g * 0.45:
			target = maxf(target, lerpf(idle, redline * 0.5, throttle_level))
		if frozen:
			target = lerpf(idle, redline * 1.05, throttle_level)
		elif _shift_timer <= 0.0:
			if gear < gears and target > redline * 0.94 and throttle > 0.3:
				gear += 1
				_shift_timer = 0.22
				shifted.emit(true)
			elif gear > 1 and v < _gear_top(gear - 1) * 0.58:
				gear -= 1
				_shift_timer = 0.15
				shifted.emit(false)
		target = maxf(target, idle)
		if target >= redline:
			limiter = true
			target = redline
	var rate := 14.0 if target > rpm else 8.0
	if _shift_timer > 0.1:
		rate = 22.0
	rpm = lerpf(rpm, target, 1.0 - exp(-rate * dt))


# ---------------------------------------------------------------- сеть

func net_state() -> Array:
	return [position.x, position.z, yaw, vel.x, vel.z, steer, lap, progress, nitro_active, in_throttle]


func apply_net_state(s: Array) -> void:
	net_pos = Vector3(s[0], 0.0, s[1])
	net_yaw = s[2]
	net_vel = Vector3(s[3], 0.0, s[4])
	net_steer = s[5]
	lap = s[6]
	progress = s[7]
	net_nitro = s[8]
	if s.size() > 9:
		net_throttle = s[9]
	net_age = 0.0
	_update_race_dist()


func update_remote(dt: float) -> void:
	net_age += dt
	var predicted := net_pos + net_vel * minf(net_age, 0.35)
	var k := 1.0 - exp(-12.0 * dt)
	var old := position
	var old_yaw := yaw
	if position.distance_to(predicted) > 30.0:
		position = predicted
	else:
		position = position.lerp(predicted, k)
	yaw = lerp_angle(yaw, net_yaw, k)
	rotation.y = yaw
	vel = net_vel
	speed = net_vel.dot(forward())
	steer = net_steer
	var info := track.project(position, seg)
	seg = info["idx"]
	lat_acc = angle_difference(old_yaw, yaw) / maxf(dt, 0.001) * speed
	var grip: float = def["grip"]
	slip = clampf((absf(lat_acc) / (grip * 9.81) - 0.8) * 4.0, 0.0, 1.0)
	_update_drivetrain(dt, net_throttle, false)
	model.animate(dt, speed, steer, 0.0, (position - old).length(), false, net_nitro)
