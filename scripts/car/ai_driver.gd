class_name AIDriver
extends RefCounted

## Простой, но быстрый пилот: едет по осевой с собственным смещением,
## заранее тормозит перед поворотами по профилю скоростей трассы.

var car: Car
var track: Track
var skill := 1.0
var lane := 0.0
var lane_target := 0.0
var vmax := PackedFloat32Array()
var stuck := 0.0
var lane_timer := 0.0
var rng := RandomNumberGenerator.new()
var others: Array = []


func _init(c: Car, t: Track, sk: float, all_cars: Array) -> void:
	car = c
	track = t
	skill = sk
	others = all_cars
	rng.randomize()
	lane = rng.randf_range(-0.3, 0.3) * track.half_width
	lane_target = lane
	lane_timer = rng.randf_range(2.0, 6.0)
	build_profile()


func build_profile() -> void:
	var n := track.pts.size()
	vmax.resize(n)
	var h: float = car.def["handling"]
	var g: float = car.def["grip"] * 9.81
	var top := car.top_speed
	for i in n:
		var r := track.radius[i]
		var v1 := sqrt(g * r)
		var v2 := h * r / (1.0 + 0.45 * h * r / top)
		vmax[i] = minf(minf(v1, v2) * 0.9 * skill, top * (0.9 + 0.1 * skill))
	var brake: float = car.def["brake"] * 0.65
	for _pass in 2:
		for k in range(n - 1, -1, -1):
			var j := (k + 1) % n
			var lim := sqrt(vmax[j] * vmax[j] + 2.0 * brake * Track.SPACING)
			if lim < vmax[k]:
				vmax[k] = lim


func update(dt: float) -> void:
	var n := track.pts.size()
	var i := car.seg
	var spd := car.speed
	var look := int((9.0 + absf(spd) * 0.42) / Track.SPACING)
	var ti := (i + look) % n

	# смена полосы и объезд соперников
	lane_timer -= dt
	if lane_timer <= 0.0:
		lane_timer = rng.randf_range(3.0, 7.0)
		lane_target = rng.randf_range(-0.35, 0.35) * track.half_width
	var fwd := car.forward()
	var rgt := car.right()
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var d: Vector3 = o.position - car.position
		var ahead := d.dot(fwd)
		var side := d.dot(rgt)
		if ahead > 0.0 and ahead < 18.0 and absf(side) < 2.6 and o.speed < spd + 1.0:
			lane_target = clampf(lane - signf(side + 0.01) * 4.0, -track.half_width * 0.6, track.half_width * 0.6)
			break
	lane = move_toward(lane, lane_target, 2.5 * dt)

	var target := track.pts[ti] + track.normals[ti] * lane
	var to := target - car.position
	var ang := atan2(to.dot(rgt), to.dot(fwd))
	var steer := clampf(ang * 2.6, -1.0, 1.0)

	var vt := vmax[(i + 2) % n]
	var throttle := 0.0
	var brake := 0.0
	if spd < vt - 1.0:
		throttle = 1.0
	elif spd > vt + 1.5:
		brake = clampf((spd - vt) / 6.0, 0.2, 1.0)
	else:
		throttle = 0.5
	# нитро на длинных прямых
	var far := vmax[(i + 60) % n]
	var nitro := skill > 0.9 and car.nitro > 40.0 and far > spd + 15.0 and absf(steer) < 0.2

	# застрял — сдаём назад
	if absf(spd) < 2.0 and throttle > 0.0:
		stuck += dt
	else:
		stuck = maxf(0.0, stuck - dt)
	if stuck > 2.5:
		if stuck > 4.5:
			car.respawn()
			stuck = 0.0
		else:
			throttle = 0.0
			brake = 1.0
			steer = -steer

	car.in_steer = steer
	car.in_throttle = throttle
	car.in_brake = brake
	car.in_nitro = nitro
